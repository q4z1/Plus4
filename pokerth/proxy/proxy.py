#!/usr/bin/env python3
"""PokerTH on one side, a Plus/4 on the other.

This is the piece the whole design rests on. It holds a real PokerTH session
- TLS, protobuf, the player table, the game list - and exposes it to the
Plus/4 as the handful of small records described in ../protocol.md. The
Plus/4 never learns that any of the rest exists.

    ./proxy.py --login
    ./proxy.py --login --listen 127.0.0.1:6400 --verbose

The Plus/4 side is a TCP socket, which is what VICE connects its emulated
ACIA to. That connection needs --ip232, because the emulator claims 0xFF for
the modem control lines (see ip232.py); a real serial line does not.

    ./proxy.py --login --ip232
    xplus4 -acia -myaciadev 0 -rsdev1 127.0.0.1:6400 -rsdev1ip232

Until there is 6502 code to run in it, p4client.py plays the part of the
Plus/4 over the same socket.

One connection at a time. A Plus/4 is switched on and reset rather than
gracefully closed, so a new connection simply replaces the old one, and a
HELLO on an existing one means "forget what you sent me, start again".
"""

from __future__ import annotations

import argparse
import os
import select
import signal
import socket
import sys
import time
from collections import deque

import cards
import ip232
import p4wire
import pokerth_link as L
from lobbystate import LobbyState, game_flags
from lobbywatch import add_connection_arguments, connect_and_login, log


class Plus4Connection:
    """One connected Plus/4, with the credit it has granted us.

    Nothing is written to the socket unless the Plus/4 has said it has room.
    See "Flow control" in ../protocol.md.
    """

    # How many frames may wait for credit before the proxy starts throwing
    # some away. Two screens' worth of updates is plenty; beyond that the
    # Plus/4 is so far behind that old news has no value.
    MAX_QUEUE = 64

    def __init__(self, sock: socket.socket, addr, use_ip232: bool = False):
        self.sock = sock
        self.addr = addr
        # VICE does not carry plain bytes; a real serial line does. The
        # credit is counted in protocol bytes either way, so that both ends
        # agree on the same number regardless of what the transport adds.
        self.decoder = ip232.Decoder() if use_ip232 else None
        self.reader = p4wire.FrameReader()
        self.rx_buffer = 0
        self.credit = 0
        self.queue: deque[bytes] = deque()
        self.ready = False
        self.dropped = 0

    def fileno(self) -> int:
        return self.sock.fileno()

    def hello(self, rx_buffer: int) -> None:
        """Start again: the far end just told us how much room it has."""
        self.rx_buffer = rx_buffer
        self.credit = rx_buffer
        self.queue.clear()
        self.ready = True

    def send(self, frame: bytes) -> None:
        if not self.ready:
            return
        self.queue.append(frame)
        self._trim()
        self.flush()

    def ack(self, consumed: int) -> None:
        self.credit = min(self.rx_buffer, self.credit + consumed)
        self.flush()

    def flush(self) -> None:
        while self.queue:
            frame = self.queue[0]
            # A frame bigger than the whole window would otherwise wait for
            # credit that can never arrive. Letting it go when nothing is
            # outstanding keeps the guarantee that actually matters: one
            # thing on the wire at a time.
            if len(frame) > self.credit and self.credit < self.rx_buffer:
                break
            self.queue.popleft()
            self.sock.sendall(ip232.encode(frame) if self.decoder else frame)
            self.credit -= len(frame)

    def _trim(self) -> None:
        """Make room by dropping what a late arrival would not miss."""
        while len(self.queue) > self.MAX_QUEUE:
            for i, frame in enumerate(self.queue):
                if frame[0] in (p4wire.D_CHAT, p4wire.D_GAME_UPDATE):
                    del self.queue[i]
                    break
            else:
                self.queue.popleft()
            self.dropped += 1

    def receive(self, data: bytes) -> list[tuple[int, bytes]]:
        """Bytes off the socket, frames out."""
        if self.decoder is not None:
            data, dtr_changes = self.decoder.feed(data)
            for raised in dtr_changes:
                log("p4", f"DTR {'raised' if raised else 'lowered'}")
        return self.reader.feed(data)

    def carrier(self) -> None:
        """Answer the emulator's modem, which otherwise waits for a carrier."""
        if self.decoder is not None:
            self.sock.sendall(ip232.carrier(True))

    def close(self) -> None:
        try:
            self.sock.close()
        except OSError:
            pass


class Bridge(LobbyState):
    """Turns lobby changes into records, and records back into lobby actions."""

    def __init__(self, link: L.Link, user: str, server_name: str,
                 verbose: bool = False):
        super().__init__(link)
        self.user = user
        self.server_name = server_name
        self.verbose = verbose
        self.plus4: Plus4Connection | None = None
        # PokerTH game ids are 32 bit and keep climbing; the wire carries 16.
        # So the proxy hands out its own small numbers and remembers which is
        # which - the Plus/4 sees a short list, not a server counter.
        self._wire_of: dict[int, int] = {}
        self._game_of: dict[int, int] = {}
        self._next_wire_id = 1

    # -- game id mapping --

    def wire_id(self, game_id: int) -> int:
        if game_id not in self._wire_of:
            wire = self._next_wire_id
            while wire in self._game_of:            # after 65535 games, reuse
                wire = wire % 0xFFFF + 1
            self._next_wire_id = wire % 0xFFFF + 1
            self._wire_of[game_id] = wire
            self._game_of[wire] = game_id
        return self._wire_of[game_id]

    def wire_id_for(self, game_id: int) -> int:
        """LobbyState asks this when it needs the downstream number."""
        return self.wire_id(game_id)

    def game_id_of(self, wire: int) -> int | None:
        return self._game_of.get(wire)

    def forget_game(self, game_id: int) -> int:
        wire = self.wire_id(game_id)
        self._wire_of.pop(game_id, None)
        self._game_of.pop(wire, None)
        return wire

    # -- sending --

    def to_plus4(self, frame: bytes) -> None:
        if self.plus4 is None:
            return
        if self.verbose:
            log("out", f"{p4wire.type_name(frame[0])} "
                       f"{len(frame)} bytes  {p4wire.hexdump(frame[:12])}")
        self.plus4.send(frame)

    def game_frame(self, game) -> bytes:
        return p4wire.game_add(self.wire_id(game.gameId), game_flags(game),
                               len(game.playerIds), game.gameInfo.maxNumPlayers,
                               game.gameInfo.gameName)

    def winning_hand(self, outcome, table) -> str:
        """The five cards that won it, if the server said which."""
        if not outcome.bestHandPosition:
            return ""
        pool = [outcome.resultCard1, outcome.resultCard2] + list(table.board)
        picked = [pool[i] for i in outcome.bestHandPosition if 0 <= i < len(pool)]
        if not picked:
            return ""
        return " with " + " ".join(cards.card_name(c) for c in picked)

    def snapshot(self) -> None:
        """Everything a Plus/4 that just said HELLO needs to draw a lobby."""
        self.to_plus4(p4wire.hello(self.server_name))
        self.to_plus4(p4wire.state(p4wire.STATE_LOBBY, f"logged in as {self.user}"))
        self.to_plus4(p4wire.players_online(self.players_online))
        self.to_plus4(p4wire.game_clear())
        for game in self.games.values():
            self.to_plus4(self.game_frame(game))
        log("p4", f"sent a snapshot of {len(self.games)} games")

        # A greeting can arrive in the middle of a hand: the Plus/4 sends one
        # when it has lost the thread, and it needs the table back as well,
        # or it sits looking at a dead one. The hand goes before the seats,
        # since starting a hand is what clears the bets.
        table = self.table
        if table is not None:
            self.to_plus4(table.table_frame())
            self.to_plus4(p4wire.state(p4wire.STATE_TABLE, table.name))
            if table.hand_number:
                self.to_plus4(p4wire.hand(table.hand_number,
                                          table.seat_of(table.dealer),
                                          table.info.firstSmallBlind,
                                          table.my_cards[0], table.my_cards[1]))
            for frame in table.seat_frames(self.name_of):
                self.to_plus4(frame)
            self.to_plus4(p4wire.board(table.board))
            self.to_plus4(p4wire.pot(table.pot))
            log("p4", f"and the table {table.name} as it stands")

    # -- lobby changes, from LobbyState --

    def event(self, name: str, /, **d) -> None:
        if name == "game_added":
            self.to_plus4(self.game_frame(d["game"]))
        elif name == "game_changed":
            game = d["game"]
            self.to_plus4(p4wire.game_update(self.wire_id(game.gameId),
                                             game_flags(game),
                                             len(game.playerIds)))
        elif name == "game_removed":
            self.to_plus4(p4wire.game_remove(self.forget_game(d["game_id"])))
        elif name == "chat":
            self.to_plus4(p4wire.chat(d["chat_type"], d["name"], d["text"]))
        elif name == "chat_rejected":
            self.to_plus4(p4wire.notice(f"chat refused: {d['text']}"))
        elif name == "notice":
            self.to_plus4(p4wire.notice(d["text"]))
        elif name == "players_online":
            self.to_plus4(p4wire.players_online(d["count"]))

        # -- at a table --

        elif name == "table_joined":
            table = d["table"]
            self.to_plus4(table.table_frame())
            self.to_plus4(p4wire.state(p4wire.STATE_TABLE, table.name))
            log("p4", f"sat down at {table.name} (game {table.game_id})")
        elif name in ("table_seated", "table_seat_changed"):
            # The seats are handed out after the acknowledgement, so the
            # table record is sent again: until now it could not say which
            # seat is ours, and that is what the screen is drawn around.
            self.to_plus4(d["table"].table_frame())
            for frame in d["table"].seat_frames(self.name_of):
                self.to_plus4(frame)
        elif name == "hand_started":
            table = d["table"]
            self.to_plus4(p4wire.hand(table.hand_number,
                                      table.seat_of(table.dealer),
                                      d["small_blind"],
                                      table.my_cards[0], table.my_cards[1]))
            for frame in table.seat_frames(self.name_of):
                self.to_plus4(frame)
            self.to_plus4(p4wire.board([]))
            self.to_plus4(p4wire.pot(0))
        elif name == "turn":
            table = d["table"]
            self.to_plus4(p4wire.turn(table.seat_of(d["player_id"]),
                                      table.betting_round))
            if d["mine"]:
                self.to_plus4(p4wire.ask(*table.what_may_i_do()))
        elif name == "action_done":
            table = d["table"]
            if d["seat"] is not None:
                self.to_plus4(table.seat_bet_frame(d["seat"]))
            self.to_plus4(p4wire.pot(table.pot))
        elif name == "board":
            self.to_plus4(p4wire.board(d["table"].board))
        elif name in ("hand_over", "cards_shown"):
            table = d["table"]
            if table is None:
                return
            won = {r.playerId: r.moneyWon for r in d.get("results", [])}
            for seat in table.seats:
                if seat.player_id and seat.cards[0] != cards.CARD_NONE:
                    self.to_plus4(p4wire.result(seat.number, seat.cards[0],
                                                seat.cards[1],
                                                won.get(seat.player_id, 0),
                                                seat.money))
            # Who won is the one thing a table of numbers does not say, so it
            # is said in words, in the chat where it stays put. A line with no
            # name is written as it stands.
            for outcome in d.get("results", []):
                if outcome.moneyWon:
                    self.to_plus4(p4wire.chat(
                        p4wire.CHAT_GAME, "",
                        f"{self.name_of(outcome.playerId)} wins "
                        f"{outcome.moneyWon}"
                        f"{self.winning_hand(outcome, table)}"))
        elif name == "table_ended":
            self.to_plus4(p4wire.table_end(d["reason"]))
            self.to_plus4(p4wire.state(p4wire.STATE_LOBBY,
                                       f"logged in as {self.user}"))
        elif name == "table_failed":
            self.to_plus4(p4wire.notice("cannot join that game"))
        elif name == "action_rejected":
            self.to_plus4(p4wire.notice("the server refused that move"))
        elif name == "cards_unreadable":
            log("p4", f"hole cards: {d['reason']}")
            self.to_plus4(p4wire.notice("cannot read my own cards"))

    # -- records from the Plus/4 --

    def from_plus4(self, kind: int, payload: bytes) -> None:
        try:
            record = p4wire.decode_upstream(kind, payload)
        except p4wire.ProtocolError as e:
            log("p4", f"ignored: {e}")
            return

        if self.verbose:
            log("in", f"{p4wire.type_name(kind)} {record}")

        what = record["kind"]
        if what == "hello":
            if record["version"] != p4wire.PROTOCOL_VERSION:
                log("p4", f"version mismatch: the Plus/4 speaks "
                          f"{record['version']}, this proxy speaks "
                          f"{p4wire.PROTOCOL_VERSION}")
                self.plus4.hello(record["rx_buffer"])
                self.to_plus4(p4wire.state(
                    p4wire.STATE_ERROR,
                    f"proxy speaks version {p4wire.PROTOCOL_VERSION}"))
                return
            log("p4", f"hello: version {record['version']}, "
                      f"{record['rx_buffer']} byte receive buffer")
            self.plus4.hello(record["rx_buffer"])
            self.snapshot()
        elif what == "ack":
            self.plus4.ack(record["consumed"])
        elif what == "chat":
            msg, chat = L.make("ChatRequestMessage")
            chat.chatText = record["text"]
            # Sitting at a table, what is typed belongs to that table. Sent
            # without one it is lobby chat, which the server refuses from a
            # player who is in a game - "chat refused" on the Plus/4.
            if self.table is not None:
                chat.targetGameId = self.table.game_id
            self.link.send(msg)
            log("p4", f"chat: {record['text']}")
        elif what == "join":
            game_id = self.game_id_of(record["game_id"])
            if game_id is None:
                self.to_plus4(p4wire.notice("no such game"))
            else:
                log("p4", f"joining game {game_id}")
                self.join_game(game_id)
        elif what == "leave":
            log("p4", "leaving the table")
            self.leave_game()
        elif what == "action":
            log("p4", f"action {record['action']} for {record['amount']}")
            self.act(record["action"], record["amount"])
        elif what == "bye":
            log("p4", "the Plus/4 said goodbye")
            raise ConnectionResetError


def stop_older_proxies() -> None:
    """Send any previous copy of this proxy on its way.

    Two of these must not run at once: they fight over the listening port,
    and worse, the second login as the same account makes the server drop the
    first one. A test run that quietly used a stale proxy has cost an evening
    once already, so this is not left to the person at the keyboard.
    """
    me = os.getpid()
    mine = os.path.basename(__file__)
    killed = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == me:
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                command = f.read().split(b"\0")
        except OSError:
            continue                    # gone, or not ours to look at
        if any(arg.endswith(mine.encode()) for arg in command):
            try:
                os.kill(int(entry), signal.SIGTERM)
                killed.append(entry)
            except OSError:
                pass
    if killed:
        log("net", f"stopped an older proxy ({', '.join(killed)})")
        time.sleep(1)                   # let it close its socket


def parse_listen(text: str) -> tuple[str, int]:
    host, _, port = text.rpartition(":")
    if not host or not port.isdigit():
        raise argparse.ArgumentTypeError(f"expected host:port, got {text!r}")
    return host, int(port)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    add_connection_arguments(ap)
    ap.add_argument("--listen", type=parse_listen, default="127.0.0.1:6400",
                    metavar="HOST:PORT",
                    help="where the Plus/4 side connects (default 127.0.0.1:6400)")
    ap.add_argument("--ip232", action="store_true",
                    help="speak VICE's IP232 on the Plus/4 side, which is "
                         "required when the emulator is at the other end")
    ap.add_argument("--verbose", action="store_true",
                    help="log every record in both directions")
    args = ap.parse_args(argv)

    host, port = args.listen if isinstance(args.listen, tuple) else parse_listen(args.listen)

    stop_older_proxies()

    link = None
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        link, announce, ack, user = connect_and_login(args)
        bridge = Bridge(link, user, args.server, verbose=args.verbose)
        if args.login:
            # Our own hole cards come encrypted with this; see cards.py.
            bridge.password = L.read_credentials(args.credentials)[1]
        bridge.me = ack.yourPlayerId
        bridge.players[ack.yourPlayerId] = user
        bridge.players_online = announce.numPlayersOnServer

        listener.bind((host, port))
        listener.listen(1)
        log("p4", f"waiting for a Plus/4 on {host}:{port}")
        link.set_timeout(None)

        while True:
            watching = [link, listener]
            if bridge.plus4 is not None:
                watching.append(bridge.plus4)
            for ready in select.select(watching, [], [])[0]:
                if ready is link:
                    for msg in link.drain():
                        bridge.pump(msg)
                elif ready is listener:
                    sock, addr = listener.accept()
                    if bridge.plus4 is not None:
                        log("p4", f"replacing the connection from {bridge.plus4.addr}")
                        bridge.plus4.close()
                    bridge.plus4 = Plus4Connection(sock, addr, args.ip232)
                    bridge.plus4.carrier()
                    log("p4", f"connection from {addr[0]}:{addr[1]}, "
                              "waiting for its hello")
                else:
                    try:
                        data = bridge.plus4.sock.recv(4096)
                        if not data:
                            raise ConnectionResetError
                        for kind, payload in bridge.plus4.receive(data):
                            try:
                                bridge.from_plus4(kind, payload)
                            except L.LinkError:
                                raise
                            except Exception as e:
                                # One bad record must not take the session
                                # with it. The Plus/4 has no way of knowing
                                # why the line went silent, and a crash here
                                # looks exactly like a cable falling out.
                                log("p4", f"{p4wire.type_name(kind)} failed: "
                                          f"{e.__class__.__name__}: {e}")
                                bridge.to_plus4(p4wire.notice("that did not work"))
                    except (ConnectionResetError, BrokenPipeError, OSError):
                        log("p4", f"the Plus/4 at {bridge.plus4.addr} is gone")
                        bridge.plus4.close()
                        bridge.plus4 = None
                        break
    except L.LinkError as e:
        log("net", str(e))
        return 1
    except KeyboardInterrupt:
        log("net", "stopped")
    finally:
        listener.close()
        if link is not None:
            link.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
