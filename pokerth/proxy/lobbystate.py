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

import pokerth_link as L
from pokerth_link import pb


class LobbyState:
    """Tracks players and games; calls `event` on every change."""

    def __init__(self, link: L.Link):
        self.link = link
        self.players: dict[int, str] = {}   # player id -> name
        self.games: dict[int, object] = {}  # game id -> GameListNewMessage
        self.me = 0
        self.players_online = 0

    # -- what subclasses implement --

    def event(self, name: str, /, **data) -> None:
        """One change to the lobby. Overridden by whatever is showing it.

        `name` is positional only on purpose: events carry keywords of their
        own, and a chat event has a name= of its own to pass.
        """

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
