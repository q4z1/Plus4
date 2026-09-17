# PokerTH on the Plus/4

A networked client for a 1984 machine: join the lobby of a
[PokerTH](https://github.com/pokerth/pokerth) server from a Commodore Plus/4,
see the games, chat, and play a hand.

The Plus/4 cannot do any of what a PokerTH client normally does. TLS 1.3,
protobuf, SCRAM authentication — none of that fits in 64 KB behind a 1.76 MHz
7501, and none of it is interesting to write in 6502 assembly. So it does not:
a proxy on a PC speaks PokerTH on one side and something deliberately tiny on
the other.

```
  PokerTH server  <--- TLS 1.3 + protobuf --->  proxy (Python)
                                                   |
                                                   |  a handful of fixed-size
                                                   |  records over RS-232
                                                   v
                                                Plus/4
```

The Plus/4 never sees a protobuf message. It receives records like "seat 3 has
1200 chips", "your turn, 30 seconds", "chat line" and sends back `FOLD`,
`CALL`, `RAISE 200`. Everything that needs a heap, a hash function or a
certificate lives in the proxy; everything that needs a character set and a
screen lives on the Plus/4.

## Why this is worth building

The reusable part is not the poker game — it is the shape: *a world protocol
translated into something a 6502 can handle*. Once that pipe exists, the same
shape carries IRC, a chess server, or anything else. Poker is a good first
case because the data per hand is tiny and a poker table maps naturally onto
40×25 characters.

## Stages

Each stage is meant to work on its own before the next one starts.

| Stage | What | State |
| --- | --- | --- |
| 1 | `proxy/lobbywatch.py` — log in as guest or with an account, show the lobby and chat on a PC terminal | **done** |
| 2 | [The Plus/4 wire protocol](protocol.md), the proxy, and a reference client in Python | **done** |
| 3 | [Plus/4: the ACIA, and a byte that survives the trip](echo/echo.c) | **done** |
| 4 | [Plus/4: the lobby itself](client/client.c) | draws a live lobby, but not yet reliably |
| 5 | Plus/4: table rendering, playing a hand | |
| 6 | Real hardware over a serial WiFi modem | |

## Stage 1: the lobby on a terminal

```sh
cd proxy
./build-proto.sh                      # venv + Python bindings for pokerth.proto
.venv/bin/python lobbywatch.py --nick Plus4
```

`--dump` logs the kind of every message that arrives, which is the fastest way
to learn what the lobby actually sends. `--server localhost --no-tls` points it
at a locally built server.

Guests may watch but not chat, so to send anything there has to be a registered
account. Credentials are read from a `key=value` file outside the repository,
so they cannot end up in a commit:

```sh
mkdir -p ~/.config/pokerth-plus4
printf 'user=NAME\npassword=SECRET\n' > ~/.config/pokerth-plus4/credentials
chmod 600 ~/.config/pokerth-plus4/credentials

.venv/bin/python lobbywatch.py --login --say "hello from a Commodore Plus/4"
```

## Stage 2: the proxy, and something to test it with

`proxy.py` holds the PokerTH session and offers it on a TCP socket as the
records described in [protocol.md](protocol.md). That socket is what VICE
connects the Plus/4's ACIA to:

```sh
.venv/bin/python proxy.py --login --verbose
xplus4 -acia -rsdev1 127.0.0.1:6400 -rsdev1ip232 -myaciadev 0
```

Until there is 6502 code to put in that emulator, `p4client.py` plays the part
of the Plus/4 over the same socket - same records, same credit, same
acknowledgements:

```sh
.venv/bin/python p4client.py
```

Type to chat, `/games` draws the lobby 40 columns wide the way the Plus/4 will
have to. It can also pretend to be slow and short of memory, which is how to
find out whether flow control works before a real machine has to prove it:

```sh
.venv/bin/python p4client.py --rx-buffer 64 --slow 0.3
```

`bridgecheck.py` feeds the bridge a made-up game list, because a lobby with
games in it is the one thing an empty test server cannot offer.

## Stage 3: the wire

The Plus/4 is the one machine in the 264 family with a 6551 ACIA on board, at
`$FD00`, and cc65 ships a driver for it - so [echo/echo.c](echo/echo.c) never
touches the chip. It sends every byte value from 0 to 255 and echoes back
whatever arrives; [proxy/wirecheck.py](proxy/wirecheck.py) is the other end
and checks both directions byte for byte.

```sh
cd echo && ./wiretest.sh          # 32 bytes in flight: passes
cd echo && ./wiretest.sh 128      # 128: watch it fail
```

The script builds the program, starts the checker, and runs VICE with its
ACIA connected to a socket:

```sh
xplus4 -acia -myaciadev 0 -rsdev1 127.0.0.1:6400 -rsdev1ip232 \
       -autostart echo/build/echo.prg
```

## Stage 4: the lobby on the machine

[client/client.c](client/client.c) is the client proper: the game list, who
is online, the chat, and a line to type into, on a 40x25 screen in about 6 KB.
Start the proxy, then the emulator:

```sh
../proxy/proxy.py --login --ip232
./run.sh
```

It has shown a live lobby - the game "Alien" on pthsrv.pokerth.net, a ranking
game with one of ten seats taken, logged in as akali - with credit flowing
back frame for frame:

```
in   U_ACK {'consumed': 21}    out  D_HELLO 21 bytes
in   U_ACK {'consumed': 21}    out  D_STATE 21 bytes
in   U_ACK {'consumed': 4}     out  D_PLAYERS 4 bytes
in   U_ACK {'consumed': 2}     out  D_GAME_CLEAR 2 bytes
in   U_ACK {'consumed': 12}    out  D_GAME_ADD 12 bytes  "Alien"
```

Two things had to go to get that far. cc65's `cprintf` was found with the
monitor wedged in its division loop at `$23D7`, so numbers are formatted by
hand now. And `conio` went with it: the KERNAL is a poor neighbour for a
program whose serial driver runs off the interrupt, so the screen is written
cell by cell at `$0C00`, the way [pacman/](../pacman/) does it.

### Where this stands

Not reliably, is the honest answer. The run above is one of several, and the
others stop partway: the snapshot arrives with bytes missing and the frames
slip out of step, which shows up as an acknowledgement of 5 bytes for records
that are 4, 2 and 12 bytes long. The receive window is the obvious suspect
and is not the culprit - 16 behaves no better than 32.

What is worth following next is the last measurement rather than another
guess. Attaching the monitor mid-run puts the CPU inside `out_pump`, the loop
that hands the outgoing frame to the driver:

```
.C:1124  AD A8 27    LDA $27A8     ; out_pos
.C:1127  CD A7 27    CMP $27A7     ; out_len
.C:112a  90 E8       BCC $1114
```

That loop cannot spin on its own - `ser_put` either takes the byte or reports
an overflow - so either it is being re-entered, or `ser_put` is not returning
what the loop thinks it is when the driver has stopped itself. The driver
stops transmission while its receive buffer is low, which is the same
mechanism that deadlocked the echo program twice in stage 3, and this client
sends its acknowledgements through exactly that path.

## What the wire turned out to be

Four things this cost a rebuild each to find out, all of which the client
will have to live with.

- **VICE's socket is not a byte pipe.** IP232 claims `0xFF` to carry the
  modem control lines and doubles it to mean a literal one. A record can hold
  `0xFF` anywhere - a length, a game id, PETSCII - so an unescaped one would
  vanish and quietly change what the emulator believes about the carrier.
  [proxy/ip232.py](proxy/ip232.py) does the escaping, and only for emulator
  connections: real hardware needs none of it.
- **The cc65 driver only accepts `SER_HS_HW`.** Any other handshake setting
  fails `ser_open` with `SER_ERR_INIT_FAILED` and no further explanation.
- **A full receive buffer stops transmission too.** The driver raises a flag
  when its own buffer runs low so that it can drop RTS, and its send routine
  bails out while that flag is up. A program that waits to send before it
  reads therefore deadlocks in both directions at once - which it did, twice,
  the second time after exactly seven bytes. Bytes have to come out of the
  driver unconditionally, into a buffer of the program's own.
- **32 bytes may be in flight, not 256.** At 2400 baud, 32 bytes arrive
  perfectly, 64 lose one, 128 lose most. It is not the screen updates - the
  same run with eight times fewer of them loses just as much. Why the cliff
  sits between 64 and 128 is not yet understood, so the window is set to the
  number that measures clean and the question is left open for the stage that
  can measure it under a real client.

## What the protocol turned out to be

Notes from reading the PokerTH sources, so the next stage does not have to
rediscover them. File references are into the upstream repository.

- **Framing** is a 4-byte big-endian length followed by a serialized
  `PokerTHMessage` (`src/net/asiosendbuffer.cpp:425`). One wrapper message
  with a `messageType` enum and one optional field per kind, so dispatch is a
  single switch.
- **`MAX_PACKET_SIZE` is 384 bytes** (`src/net/netpacket.h:48`). No message can
  ever be larger, which is a pleasant guarantee at the far end of a 2400 baud
  line.
- **TLS trust comes from a pinned key, not a CA.** The servers are
  self-signed, so the client sets `verify_none` and compares the base64
  SHA-256 of the server's SubjectPublicKeyInfo against a pin
  (`src/net/tlspinning.cpp`). The pin for `pthsrv.pokerth.net` is in that
  file, and the running server matches it, so the proxy authenticates properly
  rather than blindly accepting any certificate.
- **The protocol major version must match exactly**, 5 at the moment
  (`src/net/netpacket.h:42`, checked in `src/net/serverlobbythread.cpp:1256`).
  The minor version is not checked. The server announces its version before we
  say anything, so the proxy simply requests what it was just told.
- **The build id encodes a client type in its high byte**, and the server
  rejects types it does not know (`src/game_defs.h:51`,
  `src/net/serverlobbythread.cpp` in the buildId block). There are three:
  Qt Widget, QML, Web. Until there is a fourth, the proxy has to introduce
  itself as one of them.
- **There is no ping.** The only timeout on the server is 60 seconds to
  complete the init handshake (`SERVER_INIT_SESSION_TIMEOUT_SEC`); an idle
  logged-in session stays open. A `StatisticsMessage` arrives every few
  seconds anyway, which doubles as a sign of life.
- **Guests may not chat** (`src/net/serverlobbythread.cpp:1776`), and chat is
  rate limited by a token per session, so chat needs a registered account.
  Logging into one is simpler than the message names suggest: despite the
  challenge/response states in the client and the SCRAM comment in the
  `.proto`, the current client just sends the password as `clientUserData`
  inside the TLS connection (`src/net/clientstate.cpp:1614`). Which is
  precisely why the pinned key above is worth having.
- **Names are not in the events.** The lobby identifies players by id only;
  names come from `PlayerInfoRequest`. The proxy keeps that table so the
  Plus/4 does not have to.
