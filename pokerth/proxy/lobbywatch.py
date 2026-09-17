#!/usr/bin/env python3
"""Watch a PokerTH lobby from the command line.

The first thing this project could do, and still the quickest way to see what
a server is actually saying: log in, then print the game list, who comes and
goes, and the chat. No Plus/4 involved.

    ./lobbywatch.py --nick Plus4
    ./lobbywatch.py --login --say "hello from a Commodore Plus/4"
    ./lobbywatch.py --server localhost --port 7234 --no-tls --dump

The lobby only names players by id, so names are resolved with
PlayerInfoRequest and cached; lobbystate.py does that and the tracking, this
file only decides how it reads.
"""

from __future__ import annotations

import argparse
import sys
import time

import pokerth_link as L
from lobbystate import LobbyState, describe_game
from pokerth_link import pb


def log(tag: str, text: str) -> None:
    print(f"{time.strftime('%H:%M:%S')}  {tag:<7} {text}", flush=True)


class LobbyWatcher(LobbyState):
    def __init__(self, link: L.Link, dump: bool = False):
        super().__init__(link)
        self.dump = dump

    def pump(self, msg) -> str:
        if self.dump:
            log("raw", L.kind_of(msg))
        return super().pump(msg)

    def run(self) -> None:
        while True:
            self.pump(self.link.recv())

    def event(self, name: str, /, **d) -> None:
        if name == "players_online":
            log("stats", f"{d['count']} players online")
        elif name == "player_joined":
            log("lobby", f"player {self.name_of(d['player_id'])} connected")
        elif name == "player_left":
            log("lobby", f"player {d['name']} disconnected")
        elif name == "player_named":
            info = d["info"]
            rights = pb.NetPlayerInfoRights.Name(info.playerRights)
            country = f", {info.countryCode}" if info.countryCode else ""
            human = "" if info.isHuman else ", bot"
            log("player", f"#{d['player_id']} is {info.playerName} "
                          f"({rights}{country}{human})")
        elif name == "player_unknown":
            log("lobby", f"player #{d['player_id']} is unknown to the server")
        elif name == "game_added":
            log("game", f"+ {d['game'].gameId} {describe_game(d['game'])}")
        elif name == "game_changed":
            log("game", f"~ {d['game'].gameId} {describe_game(d['game'])}")
        elif name == "game_removed":
            log("game", f"- {d['game_id']} closed")
        elif name == "game_player_joined":
            log("game", f"~ {d['game_id']} {self.name_of(d['player_id'])} joined")
        elif name == "game_player_left":
            log("game", f"~ {d['game_id']} {self.name_of(d['player_id'])} left")
        elif name == "game_spectator":
            verb = "is watching" if d["watching"] else "stopped watching"
            log("game", f"~ {d['game_id']} {self.name_of(d['player_id'])} {verb}")
        elif name == "game_admin":
            log("game", f"~ {d['game_id']} admin is now "
                        f"{self.name_of(d['player_id'])}")
        elif name == "chat":
            kind = pb.ChatMessage.ChatType.Name(d["chat_type"])[len("chatType"):]
            where = f"/{d['game_id']}" if d["game_id"] else ""
            log("chat", f"[{kind.lower()}{where}] {d['name']}: {d['text']}")
        elif name == "chat_rejected":
            log("chat", f"rejected: {d['text']}")
        elif name == "notice":
            log("server", d["text"])
        elif name == "ignored" and not self.dump:
            log("?", d["kind"])


def add_connection_arguments(ap: argparse.ArgumentParser) -> None:
    """The options for reaching a PokerTH server, shared with proxy.py."""
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


def connect_and_login(args, report=log):
    """Open a link and log in. Returns (link, announcement, acknowledgement, name)."""
    pin = None if args.insecure else (args.pin or "auto")
    link = L.Link(args.server, args.port, tls=args.tls, pin=pin)
    link.connect()
    report("net", f"connected to {args.server}:{args.port}"
                  + (f", TLS pin {link.peer_pin}" if args.tls else ", plain TCP"))
    if args.tls and not link.expected_pin:
        report("net", "no pin for this host - encrypted but unauthenticated")

    if args.login:
        user, password = L.read_credentials(args.credentials)
        announce, ack = L.password_login(link, user, password)
    else:
        user = args.nick
        announce, ack = L.guest_login(link, user)

    version = announce.protocolVersion
    server_type = pb.AnnounceMessage.ServerType.Name(announce.serverType)
    report("net", f"protocol {version.majorVersion}.{version.minorVersion}, "
                  f"{server_type}, {announce.numPlayersOnServer} players online")
    report("net", f"logged in as {user}, player id {ack.yourPlayerId}")
    return link, announce, ack, user


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    add_connection_arguments(ap)
    ap.add_argument("--say", metavar="TEXT",
                    help="send one line of lobby chat after logging in")
    ap.add_argument("--dump", action="store_true",
                    help="log the kind of every message, including ignored ones")
    args = ap.parse_args(argv)

    link = None
    try:
        link, announce, ack, user = connect_and_login(args)
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
    except L.LinkError as e:
        log("net", str(e))
        return 1
    except KeyboardInterrupt:
        log("net", "stopped")
    finally:
        if link is not None:
            link.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
