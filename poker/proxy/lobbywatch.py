#!/usr/bin/env python3
"""Watch a PokerTH lobby from the command line.

Stage one of the Plus/4 PokerTH client: no Plus/4 involved yet, no proxy yet.
This logs in as a guest and prints what the lobby sends - the game list, who
comes and goes, and the chat. Its job is to prove that the awkward half of
the problem is solved (TLS with a pinned key, protobuf, the handshake, the
version and build id rules) and to be a readable trace of the protocol while
the Plus/4 side is being written.

    ./lobbywatch.py --nick Plus4
    ./lobbywatch.py --server localhost --port 7234 --no-tls --dump

The lobby only names players by id, so player names are resolved with
PlayerInfoRequest and cached - exactly what the proxy will later have to do on
behalf of a machine that cannot keep a player table of its own.
"""

from __future__ import annotations

import argparse
import sys
import time

import pthlink as L
from pthlink import pb


def log(tag: str, text: str) -> None:
    print(f"{time.strftime('%H:%M:%S')}  {tag:<7} {text}", flush=True)


class LobbyWatcher:
    def __init__(self, link: L.Link, dump: bool = False):
        self.link = link
        self.dump = dump
        self.players: dict[int, str] = {}   # player id -> name
        self.games: dict[int, object] = {}  # game id -> GameListNewMessage
        self.me = 0

    # -- helpers --

    def name_of(self, player_id: int) -> str:
        return self.players.get(player_id, f"#{player_id}")

    def request_player_info(self, *player_ids: int) -> None:
        """Ask for the names behind player ids we have not seen before."""
        unknown = [i for i in player_ids if i and i not in self.players]
        if not unknown:
            return
        msg, req = L.make("PlayerInfoRequestMessage")
        req.playerId.extend(unknown)
        self.link.send(msg)

    def describe_game(self, game) -> str:
        info = game.gameInfo
        game_type = pb.NetGameInfo.NetGameType.Name(info.netGameType)
        mode = pb.NetGameMode.Name(game.gameMode)
        return (f"'{info.gameName}' [{game_type}] "
                f"{len(game.playerIds)}/{info.maxNumPlayers} players, "
                f"blind {info.firstSmallBlind}, {info.playerActionTimeout}s per action, "
                f"{mode}")

    # -- the loop --

    def run(self) -> None:
        while True:
            msg = self.link.recv()
            kind = L.kind_of(msg)
            if self.dump:
                log("raw", kind)
            handler = getattr(self, "on_" + kind, None)
            if handler is not None:
                handler(L.payload_of(msg))
            elif not self.dump:
                log("?", kind)

    # -- handlers, one per message kind we care about --

    def on_StatisticsMessage(self, m) -> None:
        for stat in m.statisticsData:
            name = pb.StatisticsMessage.StatisticsData.StatisticsType.Name(
                stat.statisticsType)
            log("stats", f"{name} = {stat.statisticsValue}")

    def on_PlayerListMessage(self, m) -> None:
        if m.playerListNotification == pb.PlayerListMessage.playerListNew:
            self.request_player_info(m.playerId)
            log("lobby", f"player {self.name_of(m.playerId)} connected")
        else:
            log("lobby", f"player {self.name_of(m.playerId)} disconnected")
            self.players.pop(m.playerId, None)

    def on_PlayerInfoReplyMessage(self, m) -> None:
        if not m.HasField("playerInfoData"):
            log("lobby", f"player #{m.playerId} is unknown to the server")
            return
        data = m.playerInfoData
        self.players[m.playerId] = data.playerName
        rights = pb.NetPlayerInfoRights.Name(data.playerRights)
        country = f", {data.countryCode}" if data.countryCode else ""
        human = "" if data.isHuman else ", bot"
        log("player", f"#{m.playerId} is {data.playerName} ({rights}{country}{human})")

    def on_GameListNewMessage(self, m) -> None:
        self.games[m.gameId] = m
        self.request_player_info(*m.playerIds, m.adminPlayerId)
        log("game", f"+ {m.gameId} {self.describe_game(m)}")

    def on_GameListUpdateMessage(self, m) -> None:
        mode = pb.NetGameMode.Name(m.gameMode)
        if mode == "netGameClosed":
            self.games.pop(m.gameId, None)
            log("game", f"- {m.gameId} closed")
        else:
            if m.gameId in self.games:
                self.games[m.gameId].gameMode = m.gameMode
            log("game", f"~ {m.gameId} now {mode}")

    def on_GameListPlayerJoinedMessage(self, m) -> None:
        self.request_player_info(m.playerId)
        game = self.games.get(m.gameId)
        if game is not None and m.playerId not in game.playerIds:
            game.playerIds.append(m.playerId)
        log("game", f"~ {m.gameId} {self.name_of(m.playerId)} joined")

    def on_GameListPlayerLeftMessage(self, m) -> None:
        game = self.games.get(m.gameId)
        if game is not None and m.playerId in game.playerIds:
            game.playerIds.remove(m.playerId)
        log("game", f"~ {m.gameId} {self.name_of(m.playerId)} left")

    def on_GameListSpectatorJoinedMessage(self, m) -> None:
        self.request_player_info(m.playerId)
        log("game", f"~ {m.gameId} {self.name_of(m.playerId)} is watching")

    def on_GameListSpectatorLeftMessage(self, m) -> None:
        log("game", f"~ {m.gameId} {self.name_of(m.playerId)} stopped watching")

    def on_GameListAdminChangedMessage(self, m) -> None:
        self.request_player_info(m.newAdminPlayerId)
        log("game", f"~ {m.gameId} admin is now {self.name_of(m.newAdminPlayerId)}")

    def on_ChatMessage(self, m) -> None:
        chat_type = pb.ChatMessage.ChatType.Name(m.chatType)[len("chatType"):].lower()
        who = self.name_of(m.playerId) if m.playerId else "server"
        where = f"/{m.gameId}" if m.gameId else ""
        log("chat", f"[{chat_type}{where}] {who}: {m.chatText}")

    def on_ChatRejectMessage(self, m) -> None:
        log("chat", f"rejected: {m.chatText}")

    def on_DialogMessage(self, m) -> None:
        log("server", m.notificationText)

    def on_AvatarHeaderMessage(self, m) -> None:
        pass  # Avatars are of no use to a 40x25 text screen.

    def on_AvatarDataMessage(self, m) -> None:
        pass

    def on_AvatarEndMessage(self, m) -> None:
        pass


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--server", default="pthsrv.pokerth.net")
    ap.add_argument("--port", type=int, default=L.DEFAULT_PORT)
    ap.add_argument("--nick", default="Plus4Proxy", help="guest nickname")
    ap.add_argument("--login", action="store_true",
                    help="log in with the registered account from the credentials "
                         "file instead of as a guest (guests may not chat)")
    ap.add_argument("--credentials", default=L.DEFAULT_CREDENTIALS, metavar="PATH",
                    help="key=value file with user= and password= "
                         f"(default: {L.DEFAULT_CREDENTIALS})")
    ap.add_argument("--no-tls", dest="tls", action="store_false",
                    help="plain TCP, for a local server without TLS")
    ap.add_argument("--pin", metavar="BASE64",
                    help="require this SPKI pin instead of the built-in one")
    ap.add_argument("--insecure", action="store_true",
                    help="accept any certificate (encrypted, not authenticated)")
    ap.add_argument("--say", metavar="TEXT",
                    help="send one line of lobby chat after logging in")
    ap.add_argument("--dump", action="store_true",
                    help="log the kind of every message, including ignored ones")
    args = ap.parse_args(argv)

    pin = None if args.insecure else (args.pin or "auto")
    link = L.Link(args.server, args.port, tls=args.tls, pin=pin)

    try:
        link.connect()
    except L.PinMismatch as e:
        log("net", str(e))
        return 1
    log("net", f"connected to {args.server}:{args.port}"
               + (f", TLS pin {link.peer_pin}" if args.tls else ", plain TCP"))
    if args.tls and not link.expected_pin:
        log("net", "no pin for this host - encrypted but unauthenticated")

    try:
        if args.login:
            user, password = L.read_credentials(args.credentials)
            announce, ack = L.password_login(link, user, password)
            who = f"'{user}'"
        else:
            user = args.nick
            announce, ack = L.guest_login(link, user)
            who = f"guest '{user}'"
        version = announce.protocolVersion
        server_type = pb.AnnounceMessage.ServerType.Name(announce.serverType)
        log("net", f"protocol {version.majorVersion}.{version.minorVersion}, "
                   f"{server_type}, {announce.numPlayersOnServer} players online")
        log("net", f"logged in as {who}, player id {ack.yourPlayerId}")

        watcher = LobbyWatcher(link, dump=args.dump)
        watcher.me = ack.yourPlayerId
        watcher.players[ack.yourPlayerId] = user

        if args.say:
            msg, chat = L.make("ChatRequestMessage")
            chat.chatText = args.say
            link.send(msg)
            log("chat", f"sent: {args.say}")

        link.set_timeout(None)
        log("net", "watching the lobby - Ctrl-C to stop")
        watcher.run()
    except L.ServerError as e:
        log("net", str(e))
        return 1
    except L.LinkError as e:
        log("net", str(e))
        return 1
    except KeyboardInterrupt:
        log("net", "stopped")
    finally:
        link.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
