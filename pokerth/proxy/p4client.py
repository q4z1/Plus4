#!/usr/bin/env python3
"""Stand-in for the Plus/4, so the protocol can be finished before the 6502 is.

It speaks exactly what ../protocol.md says the Plus/4 speaks - hello, credit,
acknowledgements and all - over the same socket VICE will later connect to.
Whatever works here has to work there, with the one difference that this end
is not short of cycles. So it can pretend to be:

    ./p4client.py --rx-buffer 64 --slow 0.3

which gives it a receive buffer a Plus/4 would be embarrassed by and makes it
take a third of a second per record, which is how you find out whether flow
control works before a real machine has to prove it the hard way.

Type to chat. /games lists what the lobby holds, drawn 40 columns wide the way
the Plus/4 will have to draw it. /join N, /leave, /quit.
"""

from __future__ import annotations

import argparse
import select
import socket
import struct
import sys
import time

import cards
import p4wire

SCREEN_WIDTH = 40

STATE_NAMES = {
    p4wire.STATE_OFFLINE: "offline",
    p4wire.STATE_CONNECTING: "connecting",
    p4wire.STATE_LOBBY: "lobby",
    p4wire.STATE_TABLE: "table",
    p4wire.STATE_ERROR: "error",
}

CHAT_NAMES = {
    p4wire.CHAT_LOBBY: "lobby",
    p4wire.CHAT_GAME: "game",
    p4wire.CHAT_BOT: "bot",
    p4wire.CHAT_BROADCAST: "broadcast",
    p4wire.CHAT_PRIVATE: "private",
}


class Plus4Client:
    def __init__(self, sock: socket.socket, rx_buffer: int, slow: float = 0.0,
                 auto: bool = False):
        self.sock = sock
        self.rx_buffer = rx_buffer
        self.slow = slow
        # Answering by hand is not possible when a turn lasts thirty seconds
        # and the person at the keyboard is a language model; auto goes along
        # with whatever is on the table, exactly as pokerth_bot.cpp does.
        self.auto = auto
        self.reader = p4wire.FrameReader()
        self.games: dict[int, dict] = {}
        self.server = "?"
        self.state = p4wire.STATE_OFFLINE
        self.players_online = 0
        self.unacked = 0
        self.seats: dict[int, dict] = {}
        self.my_seat = None
        self.board: list[int] = []
        self.pot = 0
        self.hand = 0
        self.may = 0
        self.to_call = 0
        self.min_raise = 0
        self.my_money = 0

    # -- talking --

    def say_hello(self) -> None:
        self.sock.sendall(p4wire.frame(
            p4wire.U_HELLO,
            struct.pack("<BH", p4wire.PROTOCOL_VERSION, self.rx_buffer)))

    def ack(self, force: bool = False) -> None:
        """Give credit back, roughly every quarter buffer, as the Plus/4 will."""
        if self.unacked and (force or self.unacked >= self.rx_buffer // 4):
            self.sock.sendall(p4wire.frame(p4wire.U_ACK,
                                           struct.pack("<H", self.unacked)))
            self.unacked = 0

    def send(self, kind: int, payload: bytes = b"") -> None:
        self.sock.sendall(p4wire.frame(kind, payload))

    # -- listening --

    def handle(self, kind: int, payload: bytes) -> None:
        # The credit covers the whole frame, header included, as both ends
        # have to agree on what was consumed.
        self.unacked += 2 + len(payload)
        if self.slow:
            time.sleep(self.slow)

        if kind == p4wire.D_HELLO:
            self.server = p4wire.unpetscii(payload[1:])
            print(f"proxy protocol {payload[0]}, server {self.server}")
        elif kind == p4wire.D_STATE:
            self.state = payload[0]
            text = p4wire.unpetscii(payload[1:])
            print(f"[{STATE_NAMES.get(self.state, self.state)}] {text}")
        elif kind == p4wire.D_NOTICE:
            print(f"! {p4wire.unpetscii(payload)}")
        elif kind == p4wire.D_GAME_CLEAR:
            self.games.clear()
            print("(game list cleared)")
        elif kind == p4wire.D_GAME_ADD:
            game_id, flags, players, seats = struct.unpack("<HBBB", payload[:5])
            self.games[game_id] = {
                "flags": flags, "players": players, "seats": seats,
                "name": p4wire.unpetscii(payload[5:]),
            }
            print(f"+ game {game_id}: {self.games[game_id]['name']} "
                  f"{players}/{seats}")
        elif kind == p4wire.D_GAME_UPDATE:
            game_id, flags, players = struct.unpack("<HBB", payload)
            game = self.games.get(game_id)
            if game:
                game.update(flags=flags, players=players)
                print(f"~ game {game_id}: {game['name']} {players}/{game['seats']}")
        elif kind == p4wire.D_GAME_REMOVE:
            game_id, = struct.unpack("<H", payload)
            game = self.games.pop(game_id, None)
            print(f"- game {game_id}: {game['name'] if game else '?'}")
        elif kind == p4wire.D_CHAT:
            name_length = payload[1]
            name = p4wire.unpetscii(payload[2:2 + name_length])
            text = p4wire.unpetscii(payload[2 + name_length:])
            print(f"<{CHAT_NAMES.get(payload[0], payload[0])}> {name}: {text}")
        elif kind == p4wire.D_PLAYERS:
            self.players_online, = struct.unpack("<H", payload)
            print(f"({self.players_online} players online)")
        elif kind == p4wire.D_TABLE:
            game_id, seats, mine = struct.unpack("<HBB", payload[:4])
            self.my_seat = None if mine == 0xFF else mine
            print(f"=== table: game {game_id}, {seats} seats, "
                  f"{p4wire.unpetscii(payload[4:])}"
                  + (f", you are in seat {mine}" if self.my_seat is not None
                     else ", not seated yet"))
        elif kind == p4wire.D_SEAT:
            number, flags, money = struct.unpack("<BBI", payload[:6])
            self.seats[number] = {"flags": flags, "money": money, "bet": 0,
                                  "name": p4wire.unpetscii(payload[6:]),
                                  "cards": None}
            print(f"  seat {number}: {self.seats[number]['name']} "
                  f"{money}{self.marks(flags)}")
        elif kind == p4wire.D_SEAT_BET:
            number, flags, money, bet = struct.unpack("<BBII", payload)
            seat = self.seats.setdefault(number, {"name": f"seat {number}",
                                                  "cards": None})
            seat.update(flags=flags, money=money, bet=bet)
            print(f"  {seat['name']}: {money} left, {bet} in{self.marks(flags)}")
        elif kind == p4wire.D_HAND:
            self.hand, dealer, blind, card1, card2 = struct.unpack("<HBIBB", payload)
            self.board = []
            self.pot = 0
            for seat in self.seats.values():
                seat["bet"] = 0
                seat["cards"] = None
            print(f"--- hand {self.hand}, dealer in seat {dealer}, "
                  f"small blind {blind}, your cards: "
                  f"{cards.card_name(card1, True)} {cards.card_name(card2, True)}")
        elif kind == p4wire.D_BOARD:
            self.board = list(payload[1:])
            if self.board:
                print("  board: " + " ".join(cards.card_name(c, True)
                                             for c in self.board))
        elif kind == p4wire.D_POT:
            self.pot, = struct.unpack("<I", payload)
            print(f"  pot: {self.pot}")
        elif kind == p4wire.D_TURN:
            seat = self.seats.get(payload[0], {})
            rounds = ("preflop", "flop", "turn", "river", "small blind",
                      "big blind")
            where = rounds[payload[1]] if payload[1] < len(rounds) else payload[1]
            print(f"  {seat.get('name', 'seat ' + str(payload[0]))} to act "
                  f"({where})")
        elif kind == p4wire.D_ASK:
            (self.may, self.to_call, self.min_raise,
             self.my_money) = struct.unpack("<BIII", payload)
            print(f"*** YOUR TURN: {self.choices()}", flush=True)
            if self.auto:
                if self.may & p4wire.MAY_CHECK:
                    print("    (auto) check", flush=True)
                    self.act(p4wire.ACTION_CHECK)
                elif self.may & p4wire.MAY_CALL:
                    print(f"    (auto) call {self.to_call}", flush=True)
                    self.act(p4wire.ACTION_CALL, self.to_call)
                else:
                    print("    (auto) fold", flush=True)
                    self.act(p4wire.ACTION_FOLD)
        elif kind == p4wire.D_RESULT:
            number, card1, card2, won, money = struct.unpack("<BBBII", payload)
            seat = self.seats.get(number, {})
            print(f"  {seat.get('name', 'seat ' + str(number))} shows "
                  f"{cards.card_name(card1, True)} {cards.card_name(card2, True)}"
                  + (f" and wins {won}" if won else "") + f", has {money}")
        elif kind == p4wire.D_TABLE_END:
            reasons = ("left", "game over", "kicked out", "could not join")
            print(f"=== table over: "
                  f"{reasons[payload[0]] if payload[0] < 4 else payload[0]}")
            self.seats.clear()
            self.my_seat = None
        else:
            print(f"? unknown record {p4wire.type_name(kind)}")

    @staticmethod
    def marks(flags: int) -> str:
        names = [n for bit, n in [(p4wire.SEAT_DEALER, "dealer"),
                                  (p4wire.SEAT_YOU, "you"),
                                  (p4wire.SEAT_FOLDED, "folded"),
                                  (p4wire.SEAT_ALL_IN, "all in"),
                                  (p4wire.SEAT_SITTING_OUT, "sitting out")]
                 if flags & bit]
        return f"  [{', '.join(names)}]" if names else ""

    def choices(self) -> str:
        offers = []
        if self.may & p4wire.MAY_FOLD:
            offers.append("/fold")
        if self.may & p4wire.MAY_CHECK:
            offers.append("/check")
        if self.may & p4wire.MAY_CALL:
            offers.append(f"/call ({self.to_call})")
        if self.may & p4wire.MAY_BET:
            offers.append(f"/bet N (at least {self.min_raise})")
        if self.may & p4wire.MAY_RAISE:
            offers.append(f"/raise N (at least {self.min_raise} more)")
        if self.may & p4wire.MAY_ALL_IN:
            offers.append(f"/allin ({self.my_money})")
        return "  ".join(offers)

    def act(self, action: int, amount: int = 0) -> None:
        self.send(p4wire.U_ACTION, struct.pack("<BI", action, amount))
        self.may = 0

    # -- the 40 column view --

    def show_table(self) -> None:
        print("+" + "-" * SCREEN_WIDTH + "+")
        board = " ".join(cards.card_name(c, True) for c in self.board) or "-"
        print(f"|{f'board {board}   pot {self.pot}':<{SCREEN_WIDTH}}|")
        print(f"|{'':-<{SCREEN_WIDTH}}|")
        for number in sorted(self.seats):
            seat = self.seats[number]
            line = (f"{number} {seat['name'][:12]:<12} {seat['money']:>7} "
                    f"{seat.get('bet', 0):>6}{self.marks(seat['flags'])}")
            print(f"|{line[:SCREEN_WIDTH]:<{SCREEN_WIDTH}}|")
        print("+" + "-" * SCREEN_WIDTH + "+")
        if self.may:
            print(self.choices())

    def show_games(self) -> None:
        print("+" + "-" * SCREEN_WIDTH + "+")
        header = f"LOBBY {self.server}"[:SCREEN_WIDTH]
        print(f"|{header:<{SCREEN_WIDTH}}|")
        print(f"|{'':-<{SCREEN_WIDTH}}|")
        if not self.games:
            print(f"|{'no games':<{SCREEN_WIDTH}}|")
        for game_id, game in sorted(self.games.items()):
            marks = ("R" if game["flags"] & p4wire.GAME_RANKING else
                     "P" if game["flags"] & p4wire.GAME_PRIVATE else " ")
            started = "*" if game["flags"] & p4wire.GAME_STARTED else " "
            seats = f"{game['players']}/{game['seats']}"
            name = game["name"][:SCREEN_WIDTH - 12]
            print(f"|{game_id:>3} {marks}{started}{name:<{SCREEN_WIDTH - 12}}"
                  f"{seats:>6} |")
        print(f"|{'':-<{SCREEN_WIDTH}}|")
        print(f"|{f'{self.players_online} players online':<{SCREEN_WIDTH}}|")
        print("+" + "-" * SCREEN_WIDTH + "+")

    # -- what is typed --

    def command(self, line: str) -> bool:
        """Returns False when it is time to stop."""
        line = line.strip()
        if not line:
            return True
        if not line.startswith("/"):
            self.send(p4wire.U_CHAT, p4wire.petscii(line, p4wire.TEXT_MAX))
            return True
        word, _, rest = line.partition(" ")
        if word == "/games":
            self.show_games()
        elif word == "/join" and rest.strip().isdigit():
            self.send(p4wire.U_JOIN, struct.pack("<H", int(rest)))
        elif word == "/leave":
            self.send(p4wire.U_LEAVE)
        elif word == "/table":
            self.show_table()
        elif word == "/fold":
            self.act(p4wire.ACTION_FOLD)
        elif word == "/check":
            self.act(p4wire.ACTION_CHECK)
        elif word == "/call":
            self.act(p4wire.ACTION_CALL, self.to_call)
        elif word == "/allin":
            self.act(p4wire.ACTION_ALLIN, self.my_money)
        elif word in ("/bet", "/raise") and rest.strip().isdigit():
            self.act(p4wire.ACTION_BET if word == "/bet" else p4wire.ACTION_RAISE,
                     int(rest))
        elif word in ("/quit", "/exit"):
            self.send(p4wire.U_BYE)
            return False
        else:
            print("commands: /games  /join N  /table  /leave  /quit"
                  "   at a turn: /fold /check /call /bet N /raise N /allin")
        return True


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--connect", default="127.0.0.1:6400", metavar="HOST:PORT")
    ap.add_argument("--rx-buffer", type=int, default=512, metavar="BYTES",
                    help="receive buffer to claim, as the Plus/4 will (default 512)")
    ap.add_argument("--slow", type=float, default=0.0, metavar="SECONDS",
                    help="pretend each record takes this long to process")
    ap.add_argument("--auto", action="store_true",
                    help="answer every turn by checking or calling, so that a "
                         "hand can be watched without anyone typing fast enough")
    args = ap.parse_args(argv)

    host, _, port = args.connect.rpartition(":")
    with socket.create_connection((host, int(port))) as sock:
        client = Plus4Client(sock, args.rx_buffer, args.slow, args.auto)
        client.say_hello()
        print(f"connected to {host}:{port}, claiming a {args.rx_buffer} byte "
              "buffer - type to chat, /games for the lobby, /quit to stop")
        try:
            while True:
                ready, _, _ = select.select([sock, sys.stdin], [], [], 0.5)
                if sock in ready:
                    data = sock.recv(4096)
                    if not data:
                        print("the proxy closed the connection")
                        return 1
                    for kind, payload in client.reader.feed(data):
                        client.handle(kind, payload)
                        client.ack()
                if sys.stdin in ready:
                    line = sys.stdin.readline()
                    if not line or not client.command(line):
                        break
                client.ack(force=True)   # idle: hand the credit back
        except KeyboardInterrupt:
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
