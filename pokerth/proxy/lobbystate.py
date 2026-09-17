"""What the lobby looks like, kept in one place.

The server describes the lobby as a stream of small changes and never sends
a full picture: players arrive as bare ids, games arrive once and are amended
afterwards. Anything that wants to show a lobby therefore has to keep the
picture itself.

Two things do: lobbywatch.py, which prints it, and proxy.py, which forwards it
to a Plus/4. So the tracking lives here and both subclass it, implementing
`event` to say what should happen when something changes. That way the two
cannot drift apart - and when the Plus/4 end needs a detail the terminal
never showed, there is one place to add it.
"""

from __future__ import annotations

import cards
import p4wire
import pokerth_link as L
from pokerth_link import pb
from table import Table


class LobbyState:
    """Tracks players and games; calls `event` on every change."""

    def __init__(self, link: L.Link):
        self.link = link
        self.players: dict[int, str] = {}   # player id -> name
        self.games: dict[int, object] = {}  # game id -> GameListNewMessage
        self.me = 0
        self.players_online = 0
        self.password = ""          # needed to decrypt our own hole cards
        self.table: Table | None = None

    # -- what subclasses implement --

    def event(self, name: str, /, **data) -> None:
        """One change to the lobby. Overridden by whatever is showing it.

        `name` is positional only on purpose: events carry keywords of their
        own, and a chat event has a name= of its own to pass.
        """

    def wire_id_for(self, game_id: int) -> int:
        """The small number this game is known by downstream. Overridden."""
        return game_id & 0xFFFF

    # -- sitting down and playing --

    def join_game(self, game_id: int) -> None:
        msg, join = L.make("JoinExistingGameMessage")
        join.gameId = game_id
        self.link.send(msg)

    def leave_game(self) -> None:
        msg, _ = L.make("LeaveGameRequestMessage")
        self.link.send(msg)

    def act(self, action: int, relative_bet: int = 0) -> None:
        """Answer the server's invitation to act.

        The bet is relative - what goes in on top of what this seat has
        already put in - which is how pokerth_bot.cpp does it: a call is
        highestSet minus mySet, a check or a fold is nothing.
        """
        if self.table is None:
            return
        msg, mine = L.make("MyActionRequestMessage")
        mine.gameId = self.table.game_id
        mine.handNum = self.table.hand_number
        mine.gameState = self.table.betting_round
        mine.myAction = action
        mine.myRelativeBet = relative_bet
        self.link.send(msg)

    # -- helpers --

    def name_of(self, player_id: int) -> str:
        return self.players.get(player_id, f"#{player_id}")

    def request_player_info(self, *player_ids: int) -> None:
        """Ask for the names behind ids we have not seen before."""
        unknown = [i for i in player_ids if i and i not in self.players]
        if not unknown:
            return
        msg, req = L.make("PlayerInfoRequestMessage")
        req.playerId.extend(unknown)
        self.link.send(msg)

    # -- feeding it --

    def pump(self, msg) -> str:
        """Handle one message from the server. Returns its kind."""
        kind = L.kind_of(msg)
        handler = getattr(self, "on_" + kind, None)
        if handler is not None:
            handler(L.payload_of(msg))
        else:
            self.event("ignored", kind=kind)
        return kind

    # -- handlers, one per message kind we care about --

    def on_StatisticsMessage(self, m) -> None:
        for stat in m.statisticsData:
            if stat.statisticsType == pb.StatisticsMessage.StatisticsData.statNumberOfPlayers:
                self.players_online = stat.statisticsValue
                self.event("players_online", count=stat.statisticsValue)

    def on_PlayerListMessage(self, m) -> None:
        if m.playerListNotification == pb.PlayerListMessage.playerListNew:
            self.request_player_info(m.playerId)
            self.event("player_joined", player_id=m.playerId)
        else:
            self.event("player_left", player_id=m.playerId,
                       name=self.name_of(m.playerId))
            self.players.pop(m.playerId, None)

    def on_PlayerInfoReplyMessage(self, m) -> None:
        if not m.HasField("playerInfoData"):
            self.event("player_unknown", player_id=m.playerId)
            return
        data = m.playerInfoData
        self.players[m.playerId] = data.playerName
        self.event("player_named", player_id=m.playerId, info=data)

    def on_GameListNewMessage(self, m) -> None:
        self.games[m.gameId] = m
        self.request_player_info(*m.playerIds, m.adminPlayerId)
        self.event("game_added", game=m)

    def on_GameListUpdateMessage(self, m) -> None:
        if m.gameMode == pb.netGameClosed:
            self.games.pop(m.gameId, None)
            self.event("game_removed", game_id=m.gameId)
            return
        game = self.games.get(m.gameId)
        if game is not None:
            game.gameMode = m.gameMode
            self.event("game_changed", game=game)

    def on_GameListPlayerJoinedMessage(self, m) -> None:
        self.request_player_info(m.playerId)
        game = self.games.get(m.gameId)
        if game is not None and m.playerId not in game.playerIds:
            game.playerIds.append(m.playerId)
            self.event("game_changed", game=game)
        self.event("game_player_joined", game_id=m.gameId, player_id=m.playerId)

    def on_GameListPlayerLeftMessage(self, m) -> None:
        game = self.games.get(m.gameId)
        if game is not None and m.playerId in game.playerIds:
            game.playerIds.remove(m.playerId)
            self.event("game_changed", game=game)
        self.event("game_player_left", game_id=m.gameId, player_id=m.playerId)

    def on_GameListSpectatorJoinedMessage(self, m) -> None:
        self.request_player_info(m.playerId)
        self.event("game_spectator", game_id=m.gameId, player_id=m.playerId,
                   watching=True)

    def on_GameListSpectatorLeftMessage(self, m) -> None:
        self.event("game_spectator", game_id=m.gameId, player_id=m.playerId,
                   watching=False)

    def on_GameListAdminChangedMessage(self, m) -> None:
        self.request_player_info(m.newAdminPlayerId)
        self.event("game_admin", game_id=m.gameId, player_id=m.newAdminPlayerId)

    def on_ChatMessage(self, m) -> None:
        self.event("chat", chat_type=m.chatType, game_id=m.gameId,
                   player_id=m.playerId,
                   name=self.name_of(m.playerId) if m.playerId else "server",
                   text=m.chatText)

    def on_ChatRejectMessage(self, m) -> None:
        self.event("chat_rejected", text=m.chatText)

    def on_DialogMessage(self, m) -> None:
        self.event("notice", text=m.notificationText)

    # -- at a table --

    def on_JoinGameAckMessage(self, m) -> None:
        self.table = Table(m.gameId, self.wire_id_for(m.gameId), m.gameInfo,
                           self.me, spectator=m.spectateOnly)
        self.event("table_joined", table=self.table)

    def on_JoinGameFailedMessage(self, m) -> None:
        self.event("table_failed", game_id=m.gameId, reason=m.joinGameFailureReason)

    def on_GameStartInitialMessage(self, m) -> None:
        if self.table is None:
            return
        self.table.place(m.playerSeats)
        self.table.dealer = m.startDealerPlayerId
        self.table.started = True
        for seat in self.table.seats:
            if seat.player_id:
                seat.money = self.table.info.startMoney
        self.request_player_info(*m.playerSeats)
        self.event("table_seated", table=self.table)

    def on_GameStartRejoinMessage(self, m) -> None:
        if self.table is None:
            return
        self.table.place([d.playerId for d in m.rejoinPlayerData])
        self.table.dealer = m.startDealerPlayerId
        self.table.hand_number = m.handNum
        self.table.started = True
        for data in m.rejoinPlayerData:
            seat = self.table.seat_for(data.playerId)
            if seat is not None:
                seat.money = data.playerMoney
        self.request_player_info(*[d.playerId for d in m.rejoinPlayerData])
        self.event("table_seated", table=self.table)

    def on_GamePlayerJoinedMessage(self, m) -> None:
        if self.table is None:
            return
        # The message says who joined, not what they brought; their money
        # arrives with their first action.
        self.table.take_a_seat(m.playerId)
        self.request_player_info(m.playerId)
        self.event("table_seat_changed", table=self.table, player_id=m.playerId)

    def on_GamePlayerLeftMessage(self, m) -> None:
        if self.table is None:
            return
        seat = self.table.seat_for(m.playerId)
        if seat is not None:
            seat.player_id = 0
        self.event("table_seat_changed", table=self.table, player_id=m.playerId)

    def on_HandStartMessage(self, m) -> None:
        if self.table is None:
            return
        table = self.table
        expected_hand = table.hand_number + 1
        table.start_hand(expected_hand,
                         m.dealerPlayerId if m.HasField("dealerPlayerId")
                         else table.dealer,
                         list(m.seatStates))
        table.my_cards = (cards.CARD_NONE, cards.CARD_NONE)
        if m.HasField("plainCards"):
            table.my_cards = (m.plainCards.plainCard1, m.plainCards.plainCard2)
        elif m.HasField("encryptedCards") and self.password:
            try:
                table.my_cards = cards.decrypt_hole_cards(
                    self.password, m.encryptedCards, self.me, table.game_id,
                    expected_hand)
            except cards.CardError as e:
                self.event("cards_unreadable", reason=str(e))
        self.event("hand_started", table=table, small_blind=m.smallBlind)

    def on_PlayersTurnMessage(self, m) -> None:
        if self.table is None:
            return
        self.table.betting_round = m.gameState
        self.event("turn", table=self.table, player_id=m.playerId,
                   mine=m.playerId == self.me)

    def on_PlayersActionDoneMessage(self, m) -> None:
        if self.table is None:
            return
        self.table.betting_round = m.gameState
        seat = self.table.action_done(m.playerId, m.playerAction, m.totalPlayerBet,
                                      m.playerMoney, m.highestSet, m.minimumRaise)
        self.event("action_done", table=self.table, seat=seat,
                   player_id=m.playerId, action=m.playerAction)

    def on_YourActionRejectedMessage(self, m) -> None:
        self.event("action_rejected", reason=m.rejectionReason)

    def on_DealFlopCardsMessage(self, m) -> None:
        self._deal([m.flopCard1, m.flopCard2, m.flopCard3], p4wire.ROUND_FLOP)

    def on_DealTurnCardMessage(self, m) -> None:
        self._deal([m.turnCard], p4wire.ROUND_TURN)

    def on_DealRiverCardMessage(self, m) -> None:
        self._deal([m.riverCard], p4wire.ROUND_RIVER)

    def _deal(self, new_cards, betting_round) -> None:
        if self.table is None:
            return
        self.table.board.extend(new_cards)
        self.table.betting_round = betting_round
        self.event("board", table=self.table)

    def on_AllInShowCardsMessage(self, m) -> None:
        if self.table is None:
            return
        for shown in m.playersAllIn:
            seat = self.table.seat_for(shown.playerId)
            if seat is not None:
                seat.cards = (shown.allInCard1, shown.allInCard2)
        self.event("cards_shown", table=self.table)

    def on_EndOfHandShowCardsMessage(self, m) -> None:
        if self.table is None:
            return
        for outcome in m.playerResults:
            seat = self.table.seat_for(outcome.playerId)
            if seat is not None:
                seat.cards = (outcome.resultCard1, outcome.resultCard2)
                seat.money = outcome.playerMoney
        self.event("hand_over", table=self.table, results=list(m.playerResults))

    def on_EndOfHandHideCardsMessage(self, m) -> None:
        self.event("hand_over", table=self.table, results=[])

    def on_EndOfGameMessage(self, m) -> None:
        self.event("table_ended", reason=p4wire.END_GAME_OVER)
        self.table = None

    def on_RemovedFromGameMessage(self, m) -> None:
        reason = p4wire.END_GAME_OVER
        if m.removedFromGameReason == pb.RemovedFromGameMessage.removedOnRequest:
            reason = p4wire.END_LEFT
        elif m.removedFromGameReason == pb.RemovedFromGameMessage.kickedFromGame:
            reason = p4wire.END_KICKED
        self.event("table_ended", reason=reason)
        self.table = None

    # Avatars are of no use to a 40x25 text screen.
    def on_AvatarHeaderMessage(self, m) -> None:
        pass

    def on_AvatarDataMessage(self, m) -> None:
        pass

    def on_AvatarEndMessage(self, m) -> None:
        pass

    def on_UnknownAvatarMessage(self, m) -> None:
        pass


# --- Describing a game, for whoever has to show one ------------------------

def game_flags(game) -> int:
    """The flag byte of the wire protocol's GAME_ADD."""
    import p4wire

    flags = 0
    if game.isPrivate:
        flags |= p4wire.GAME_PRIVATE
    if game.gameMode == pb.netGameStarted:
        flags |= p4wire.GAME_STARTED
    game_type = game.gameInfo.netGameType
    if game_type == pb.NetGameInfo.rankingGame:
        flags |= p4wire.GAME_RANKING
    elif game_type == pb.NetGameInfo.registeredOnlyGame:
        flags |= p4wire.GAME_REGISTERED_ONLY
    elif game_type == pb.NetGameInfo.inviteOnlyGame:
        flags |= p4wire.GAME_INVITE_ONLY
    return flags


def describe_game(game) -> str:
    info = game.gameInfo
    game_type = pb.NetGameInfo.NetGameType.Name(info.netGameType)
    mode = pb.NetGameMode.Name(game.gameMode)
    return (f"'{info.gameName}' [{game_type}] "
            f"{len(game.playerIds)}/{info.maxNumPlayers} players, "
            f"blind {info.firstSmallBlind}, {info.playerActionTimeout}s per action, "
            f"{mode}")
