#!/usr/bin/env python3
"""Push a made-up game list through the bridge and show what comes out.

A lobby with games in it is the one thing a test server usually will not
provide, and it is exactly the path with something to get wrong: 32 bit game
ids squeezed into 16, flags gathered from three different places, names in
UTF-8 that have to survive as PETSCII within 32 characters. So the messages
are built here rather than waited for.

    ./bridgecheck.py
"""

import struct
import sys

import p4wire
import pokerth_link as L
from pokerth_link import pb
from proxy import Bridge, Plus4Connection


class FakeSocket:
    def __init__(self): self.sent = bytearray()
    def sendall(self, data): self.sent += data
    def close(self): pass


class FakeLink:
    def __init__(self): self.sent = []
    def send(self, msg): self.sent.append(msg)


def game(game_id, name, game_type, players, seats, mode=pb.netGameCreated):
    msg, payload = L.make("GameListNewMessage")
    payload.gameId = game_id
    payload.gameMode = mode
    payload.isPrivate = False
    payload.playerIds.extend(range(100, 100 + players))
    payload.adminPlayerId = 100
    info = payload.gameInfo
    info.gameName = name
    info.netGameType = game_type
    info.maxNumPlayers = seats
    info.raiseIntervalMode = pb.NetGameInfo.raiseOnHandNum
    info.endRaiseMode = pb.NetGameInfo.doubleBlinds
    info.proposedGuiSpeed = 4
    info.delayBetweenHands = 7
    info.playerActionTimeout = 30
    info.firstSmallBlind = 50
    info.startMoney = 10000
    return msg


bridge = Bridge(FakeLink(), "akali", "pthsrv.pokerth.net")
sock = FakeSocket()
bridge.plus4 = Plus4Connection(sock, ("test", 0))
bridge.plus4.hello(512)

# A PokerTH game id far beyond 16 bits, to prove the mapping earns its keep.
bridge.pump(game(70001, "Ranking Game", pb.NetGameInfo.rankingGame, 3, 10))
bridge.pump(game(70002, "Umlaute: Grün & Weiß", pb.NetGameInfo.normalGame, 1, 6))
bridge.pump(game(70003, "A name far longer than the screen could ever show",
                 pb.NetGameInfo.registeredOnlyGame, 8, 8, pb.netGameStarted))

msg, upd = L.make("GameListPlayerJoinedMessage")
upd.gameId, upd.playerId = 70001, 200
bridge.pump(msg)

msg, closed = L.make("GameListUpdateMessage")
closed.gameId, closed.gameMode = 70002, pb.netGameClosed
bridge.pump(msg)

print("frames the Plus/4 would receive:\n")
for kind, payload in p4wire.FrameReader().feed(bytes(sock.sent)):
    body = ""
    if kind == p4wire.D_GAME_ADD:
        wire, flags, players, seats = struct.unpack("<HBBB", payload[:5])
        body = (f"id={wire} flags=0x{flags:02X} {players}/{seats} "
                f"{p4wire.unpetscii(payload[5:])!r}")
    elif kind == p4wire.D_GAME_UPDATE:
        wire, flags, players = struct.unpack("<HBB", payload)
        body = f"id={wire} flags=0x{flags:02X} players={players}"
    elif kind == p4wire.D_GAME_REMOVE:
        body = f"id={struct.unpack('<H', payload)[0]}"
    print(f"  {p4wire.type_name(kind):<13} {2 + len(payload):>3} bytes  {body}")

print(f"\nevery frame within the {p4wire.MAX_FRAME} byte limit:",
      all(2 + len(p) <= p4wire.MAX_FRAME
          for _, p in p4wire.FrameReader().feed(bytes(sock.sent))))


# --- Flow control ----------------------------------------------------------
#
# The part with the most to lose: if the proxy talks over a Plus/4 that is
# busy drawing, bytes are lost and a hand goes with them. So check that
# nothing leaves without credit, that an acknowledgement releases exactly what
# it paid for, and that a hopeless backlog is thinned rather than grown.

print("\nflow control, with a 64 byte receive buffer:")
tight = Plus4Connection(FakeSocket(), ("test", 0))
tight.hello(64)

frames = [p4wire.notice("x" * 18) for _ in range(10)]   # 20 bytes each
for f in frames:
    tight.send(f)
print(f"  sent {len(tight.sock.sent)} of {sum(map(len, frames))} bytes, "
      f"{len(tight.queue)} frames waiting, {tight.credit} credit left")
assert len(tight.sock.sent) <= 64, "wrote more than the far end can hold"

before = len(tight.sock.sent)
tight.ack(44)
print(f"  after acknowledging 44 bytes: {len(tight.sock.sent) - before} more "
      f"bytes went out, {len(tight.queue)} frames waiting")
assert len(tight.sock.sent) - before <= 44, "sent more than was acknowledged"

for _ in range(200):
    tight.send(p4wire.chat(p4wire.CHAT_LOBBY, "someone", "still talking"))
print(f"  after 200 more chat frames with no credit: {len(tight.queue)} "
      f"queued, {tight.dropped} dropped")
assert len(tight.queue) <= Plus4Connection.MAX_QUEUE + 1, "the queue grew unchecked"

# A hand in progress must never be thinned out; only chat and game updates are.
tight.queue.clear()
tight.send(p4wire.state(p4wire.STATE_TABLE, "your turn"))
for _ in range(200):
    tight.send(p4wire.chat(p4wire.CHAT_LOBBY, "someone", "still talking"))
kept = [f[0] for f in tight.queue]
print(f"  a STATE record survived {kept.count(p4wire.D_STATE) == 1} while "
      f"{kept.count(p4wire.D_CHAT)} chat frames remain")
assert kept.count(p4wire.D_STATE) == 1, "dropped something that matters"

# A frame larger than the entire window still has to get through, or the
# Plus/4 would wait forever for a chat line it can display perfectly well.
small = Plus4Connection(FakeSocket(), ("test", 0))
small.hello(32)
big = p4wire.chat(p4wire.CHAT_LOBBY, "someone", "a line longer than the window")
small.send(big)
print(f"\n  a {len(big)} byte frame through a 32 byte window: "
      f"{len(small.sock.sent)} bytes sent, credit now {small.credit}")
assert len(small.sock.sent) == len(big), "an oversized frame was never sent"
small.send(p4wire.notice("and nothing follows until it is acknowledged"))
assert len(small.queue) == 1, "kept sending with no credit left"
small.ack(len(big))
assert not small.queue, "the acknowledgement did not release the next frame"

# --- What the Plus/4 asks for --------------------------------------------
#
# Every message the proxy sends upstream has required fields, and one left
# unset does not fail quietly: it raises while being serialized, which killed
# the proxy and looked from the Plus/4 like the cable falling out. So each
# command is built here and serialized, which is the whole test.

print("\nwhat the Plus/4 can ask for:")
asked = Bridge(FakeLink(), "akali", "pthsrv.pokerth.net")
asked.me = 42
asked.plus4 = Plus4Connection(FakeSocket(), ("test", 0))
asked.plus4.hello(512)

msg, ack = L.make("JoinGameAckMessage")
ack.gameId, ack.areYouGameAdmin = 4711, False
info = ack.gameInfo
info.gameName = "Ranking Game"
info.netGameType = pb.NetGameInfo.rankingGame
info.maxNumPlayers = 10
info.raiseIntervalMode = pb.NetGameInfo.raiseOnHandNum
info.endRaiseMode = pb.NetGameInfo.doubleBlinds
info.proposedGuiSpeed = 4
info.delayBetweenHands = 7
info.playerActionTimeout = 30
info.firstSmallBlind = 50
info.startMoney = 10000
asked.pump(msg)

asked.join_game(4711)
asked.act(p4wire.ACTION_CALL, 100)
asked.leave_game()
for sent in asked.link.sent:
    encoded = sent.SerializeToString()      # raises if a field is missing
    print(f"  {L.kind_of(sent):<28} {len(encoded):>3} bytes")
assert len(asked.link.sent) >= 3, "not every command produced a message"

print("\nall checks passed")
