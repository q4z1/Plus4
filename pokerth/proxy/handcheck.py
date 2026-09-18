#!/usr/bin/env python3
"""Play a whole hand past the bridge and show what the Plus/4 would receive.

A hand needs a table with people at it, which is the one thing that cannot be
arranged on demand, and it is where most of the translation lives: seats out
of player ids, a pot the server never states, what may be done at a turn, and
hole cards that arrive encrypted. So the hand is built here instead.

    ./handcheck.py
"""

import struct
import sys

import cards
import p4wire
import pokerth_link as L
from pokerth_link import pb
from proxy import Bridge, Plus4Connection

PASSWORD = "hunter2"
ME = 42
OPPONENT = 43
GAME = 70001


class FakeSocket:
    def __init__(self):
        self.sent = bytearray()

    def sendall(self, data):
        self.sent += data

    def close(self):
        pass


class FakeLink:
    def __init__(self):
        self.sent = []

    def send(self, msg):
        self.sent.append(msg)


def game_info(msg):
    msg.gameName = "Ranking Game"
    msg.netGameType = pb.NetGameInfo.rankingGame
    msg.maxNumPlayers = 10
    msg.raiseIntervalMode = pb.NetGameInfo.raiseOnHandNum
    msg.endRaiseMode = pb.NetGameInfo.doubleBlinds
    msg.proposedGuiSpeed = 4
    msg.delayBetweenHands = 7
    msg.playerActionTimeout = 30
    msg.firstSmallBlind = 50
    msg.startMoney = 10000
    return msg


def action(bridge, player, what, total_bet, money, highest, minimum_raise,
           state=pb.netStatePreflop):
    msg, done = L.make("PlayersActionDoneMessage")
    done.gameId, done.playerId, done.gameState = GAME, player, state
    done.playerAction = what
    done.totalPlayerBet, done.playerMoney = total_bet, money
    done.highestSet, done.minimumRaise = highest, minimum_raise
    bridge.pump(msg)


def turn(bridge, player, state=pb.netStatePreflop):
    msg, whose = L.make("PlayersTurnMessage")
    whose.gameId, whose.playerId, whose.gameState = GAME, player, state
    bridge.pump(msg)


def describe(kind, payload):
    if kind == p4wire.D_TABLE:
        game, seats, mine = struct.unpack("<HBB", payload[:4])
        return f"game {game}, {seats} seats, I am in seat {mine}, " \
               f"{p4wire.unpetscii(payload[4:])!r}"
    if kind == p4wire.D_SEAT:
        number, flags, money = struct.unpack("<BBI", payload[:6])
        return f"seat {number} flags 0x{flags:02X} money {money} " \
               f"{p4wire.unpetscii(payload[6:])!r}"
    if kind == p4wire.D_SEAT_BET:
        number, flags, money, bet = struct.unpack("<BBII", payload)
        return f"seat {number} flags 0x{flags:02X} money {money} bet {bet}"
    if kind == p4wire.D_HAND:
        number, dealer, blind, card1, card2 = struct.unpack("<HBIBB", payload)
        return (f"hand {number}, dealer in seat {dealer}, small blind {blind}, "
                f"my cards {cards.card_name(card1)} {cards.card_name(card2)}")
    if kind == p4wire.D_BOARD:
        return " ".join(cards.card_name(c) for c in payload[1:]) or "(nothing)"
    if kind == p4wire.D_POT:
        return f"{struct.unpack('<I', payload)[0]}"
    if kind == p4wire.D_TURN:
        return f"seat {payload[0]}, round {payload[1]}"
    if kind == p4wire.D_ASK:
        allowed, to_call, raise_to, money = struct.unpack("<BIII", payload)
        names = [n for bit, n in [(p4wire.MAY_FOLD, "fold"),
                                  (p4wire.MAY_CHECK, "check"),
                                  (p4wire.MAY_CALL, "call"),
                                  (p4wire.MAY_BET, "bet"),
                                  (p4wire.MAY_RAISE, "raise"),
                                  (p4wire.MAY_ALL_IN, "all in")] if allowed & bit]
        return (f"{', '.join(names)}; {to_call} to call, {raise_to} minimum "
                f"raise, {money} left")
    if kind == p4wire.D_RESULT:
        number, card1, card2, won, money = struct.unpack("<BBBII", payload)
        return (f"seat {number} shows {cards.card_name(card1)} "
                f"{cards.card_name(card2)}, won {won}, has {money}")
    if kind == p4wire.D_STATE:
        return f"state {payload[0]} {p4wire.unpetscii(payload[1:])!r}"
    if kind == p4wire.D_NOTICE:
        return p4wire.unpetscii(payload)
    return p4wire.hexdump(payload)


def main() -> int:
    bridge = Bridge(FakeLink(), "akali", "pthsrv.pokerth.net")
    bridge.me = ME
    bridge.password = PASSWORD
    bridge.players = {ME: "akali", OPPONENT: "hopper"}
    sock = FakeSocket()
    bridge.plus4 = Plus4Connection(sock, ("test", 0))
    bridge.plus4.hello(4096)        # not the flow control under test here

    # Sit down, and be seated.
    msg, ack = L.make("JoinGameAckMessage")
    ack.gameId, ack.areYouGameAdmin = GAME, False
    game_info(ack.gameInfo)
    bridge.pump(msg)

    msg, start = L.make("GameStartInitialMessage")
    start.gameId, start.startDealerPlayerId = GAME, ME
    start.playerSeats.extend([ME, OPPONENT])
    bridge.pump(msg)

    # A hand begins, and our two cards arrive encrypted, as they do for
    # anyone who logged in with an account.
    msg, hand = L.make("HandStartMessage")
    hand.gameId, hand.smallBlind, hand.dealerPlayerId = GAME, 50, ME
    hand.seatStates.extend([pb.netPlayerStateNormal, pb.netPlayerStateNormal])
    hand.encryptedCards = cards._encrypt_for_test(
        PASSWORD, f"{ME} {GAME} 1 26 38")       # the 2 and the ace of spades
    bridge.pump(msg)

    # Blinds, then it is our turn with a bet to answer.
    action(bridge, ME, pb.netActionBet, 50, 9950, 50, 100)
    action(bridge, OPPONENT, pb.netActionBet, 100, 9900, 100, 100)
    turn(bridge, ME)

    # We call, the other checks, and the flop comes down.
    action(bridge, ME, pb.netActionCall, 100, 9900, 100, 100)
    msg, flop = L.make("DealFlopCardsMessage")
    flop.gameId = GAME
    flop.flopCard1, flop.flopCard2, flop.flopCard3 = 0, 13, 51
    bridge.pump(msg)
    turn(bridge, ME, pb.netStateFlop)

    # Showdown.
    msg, over = L.make("EndOfHandShowCardsMessage")
    over.gameId = GAME
    won = over.playerResults.add()
    won.playerId, won.resultCard1, won.resultCard2 = ME, 26, 38
    won.moneyWon, won.playerMoney = 200, 10100
    # Which five of the seven made the hand: our two and three of the board.
    won.bestHandPosition.extend([0, 1, 2, 3, 4])
    lost = over.playerResults.add()
    lost.playerId, lost.resultCard1, lost.resultCard2 = OPPONENT, 1, 14
    lost.moneyWon, lost.playerMoney = 0, 9900
    bridge.pump(msg)

    print("what the Plus/4 would receive:\n")
    frames = p4wire.FrameReader().feed(bytes(sock.sent))
    for kind, payload in frames:
        print(f"  {p4wire.type_name(kind):<13} {2 + len(payload):>3}  "
              f"{describe(kind, payload)}")

    ok = True
    kinds = [k for k, _ in frames]
    for required in (p4wire.D_TABLE, p4wire.D_SEAT, p4wire.D_HAND, p4wire.D_TURN,
                     p4wire.D_ASK, p4wire.D_BOARD, p4wire.D_POT, p4wire.D_RESULT):
        if required not in kinds:
            print(f"\nFAIL: no {p4wire.type_name(required)} was ever sent")
            ok = False

    hands = [p for k, p in frames if k == p4wire.D_HAND]
    if hands and struct.unpack("<HBIBB", hands[0])[3:] != (26, 38):
        print("\nFAIL: the hole cards did not survive decryption")
        ok = False

    asks = [p for k, p in frames if k == p4wire.D_ASK]
    if asks:
        allowed, to_call, _, money = struct.unpack("<BIII", asks[0])
        if to_call != 50 or not allowed & p4wire.MAY_CALL:
            print(f"\nFAIL: facing 100 with 50 in, expected 50 to call, "
                  f"got {to_call}")
            ok = False
        if allowed & p4wire.MAY_CHECK:
            print("\nFAIL: offered a check with a bet outstanding")
            ok = False

    pots = [struct.unpack("<I", p)[0] for k, p in frames if k == p4wire.D_POT]
    if 200 not in pots:
        print(f"\nFAIL: the pot never reached 200, saw {pots}")
        ok = False

    if all(2 + len(p) <= p4wire.MAX_FRAME for _, p in frames):
        pass
    else:
        print("\nFAIL: a frame went over the size limit")
        ok = False

    print("\nhand check:", "ok" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
