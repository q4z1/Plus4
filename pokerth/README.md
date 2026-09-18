# PokerTH on the Plus/4

A networked client for a 1984 machine: join the lobby of a
[PokerTH](https://github.com/pokerth/pokerth) server from a Commodore Plus/4,
see the games, chat, and play a hand.

The Plus/4 cannot do any of what a PokerTH client normally does. TLS 1.3
against a pinned key, protobuf, hole cards that arrive encrypted — none of
that fits in 64 KB behind a 1.76 MHz 7501, and none of it is interesting to
write in 6502 assembly. So it does not:
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
| 4 | [Plus/4: the lobby itself](client/client.c) | **done** - the lobby, and chat both ways |
| 5 | [Table play](client/client.c), end to end | **done** - a hand is played on the machine |
| 6 | [A client, not a display](client/client.c): a start screen that asks who you are | **done** |
| 7 | Real hardware over a serial WiFi modem | |

## Stage 1: the lobby on a terminal

```sh
cd proxy
./build-proto.sh                      # environment + bindings for pokerth.proto
$(./env.sh) lobbywatch.py --nick Plus4
```

`env.sh` prints the Python to use and builds its environment the first time.
There are two of them: VS Code runs as a Flatpak with one version of Python
and a host terminal has another, a virtual environment only works with the
interpreter that made it, and the failure reads "No module named google",
which is a confusing way to say "wrong Python". So each version gets its own
and it does not matter which one you start from.

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

$(./env.sh) lobbywatch.py --login --say "hello from a Commodore Plus/4"
```

## Stage 2: the proxy, and something to test it with

`proxy.py` holds the PokerTH session and offers it on a TCP socket as the
records described in [protocol.md](protocol.md). That socket is what VICE
connects the Plus/4's ACIA to:

```sh
$(./env.sh) proxy.py --login --verbose
xplus4 -acia -rsdev1 127.0.0.1:6400 -rsdev1ip232 -myaciadev 0
```

Until there is 6502 code to put in that emulator, `p4client.py` plays the part
of the Plus/4 over the same socket - same records, same credit, same
acknowledgements:

```sh
$(./env.sh) p4client.py
```

Type to chat, `/games` draws the lobby 40 columns wide the way the Plus/4 will
have to. It can also pretend to be slow and short of memory, which is how to
find out whether flow control works before a real machine has to prove it:

```sh
$(./env.sh) p4client.py --rx-buffer 64 --slow 0.3
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
is online, the chat, and a line to type into, on a 40x25 screen. It grew into
a table and a start screen in the stages below, and is about 16 KB with all
three - a quarter of which is the character set it carries.

**F5 starts both**, the proxy and the emulator, whichever way round you press
it. With `client.c` open at the top of the repository, the usual build script
notices `client/run.sh` and hands over to it; inside `client/`, where F5 goes
through VS64 and the debugger, `vice-with-proxy.sh` stands in for the
emulator and does the same. Either way the proxy is started first, the ACIA
is wired to it, and the proxy is stopped again on the way out. By hand:

```sh
./run.sh
```

The proxy logs to `client/build/proxy.log`, which is where to look when the
screen stays empty.

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

### What it took: the interrupt had to go

For three stages the client would stop partway through a lobby, and the
reason turned out to be one thing with many faces. The monitor caught it:

```
ACIA at $FD00:  00 9C 09 1A
                   ^^ status: interrupt asserted, a byte waiting,
                      and an overrun already recorded
CPU:            in the KERNAL, interrupts masked
stack:          walked from $FF down to $BF, one pattern repeated
```

An interrupt storm. cc65's serial driver stops being serviced, the byte that
keeps the ACIA's interrupt line asserted is never taken, and the machine
re-enters the handler for ever, ten bytes of stack at a time. Everything
since stage three follows from it - the missing bytes, the frames slipping
out of step, and the cliff between 32 and 64 bytes in flight, which was never
about how many bytes there were but about how long a burst lasted.

Three hypotheses died on the way, and they are worth listing because each
looked convincing: the emulator's warp mode (it stops at real speed too), the
key repeat flag (removing that change made it stop sooner), and conio's
keyboard polling (no difference).

What fixed it was removing the driver. The client sets up the 6551 itself
with the receive interrupt **switched off** and collects bytes when it looks,
which means this end decides how often it looks - and that turned out to be
the real work. A row of forty cells written from C takes longer than the gap
between two bytes at 2400 baud, and a 32 bit division, which is how money
reaches the screen, takes several times that. So the line is checked at the
top of every row, inside both number formatters, and between the bytes of an
outgoing frame, and the rate is halved to 1200 baud for the margin. Once per
row was not enough either - a row of forty cells is checked every eighth cell
now, which bounds the wait whatever the compiler makes of the loop.

Two things guard what is left. A frame that stays unfinished while nothing
arrives is abandoned, everything still coming is thrown away until the line
is quiet, and only then is the proxy greeted again - asking sooner meant the
rest of the old burst met a parser that had just been reset, and one session
collected a hundred and seven greetings. So one lost byte costs a redraw
instead of the session - without that, a single missing byte was
permanent, because the next one is read as a length and the parser waits for
a payload that never comes. And the count of bytes the ACIA dropped is shown
in the header: `!2` after a session means the machine fell behind twice and
caught up twice, which is a number to watch rather than a fault.

## Stage 5: a hand

The records for a table are in [protocol.md](protocol.md), the proxy speaks
them, and the machine draws them. The proxy turns player ids into seat
numbers, keeps the pot the server never states, works out which actions would
be accepted, and decrypts the two cards that arrive encrypted because we
logged in with an account.

A hand needs a table with people at it, which is the one thing that cannot be
arranged on demand, so [proxy/handcheck.py](proxy/handcheck.py) builds one:

```
D_TABLE     game 1, 10 seats, I am in seat 0, 'Ranking Game'
D_HAND      hand 1, dealer in seat 0, small blind 50, my cards 2s As
D_POT       150
D_ASK       fold, call, raise, all in; 50 to call, 100 minimum raise, 9950 left
D_RESULT    seat 0 shows 2s As, won 200, has 10100
```

`D_ASK` is the record that keeps the Plus/4 out of the poker business: the
server says what is on the table, the proxy works out what may be done about
it, and the machine only has to offer the choice.

### The table, as a table

Ten places around an oval of green felt, our own at the bottom where a player
sits, the board and the pot between them. The felt is nothing but reversed
spaces: a character cell has one colour and the background belongs to the
whole screen, so a solid shape can only be made that way.

```
       Computer5        Computer3 d     Computer6
       9850             9850            9850    50
  hopper     ####################    Computer7
  10100      #  -- -- -- -- --  #    10050  100
  Computer1  #    pot 150       #    Computer4
  10000      ####################    10000
       Computer2        akali           Computer8
       10000            10075           10075
                        7h Js   10075

akali wins 4664 with As Ac Ks Qs 7d
your turn
f1 fold  f2 call 100  f3 +100  f4 all in
```

State is colour rather than punctuation, there being no room for symbols: our
own seat cyan, a folded one grey, all in yellow, and whose turn it is shown
by their name in reverse. Only the dealer keeps a letter. Who won is said in
words on a line of its own, because a table of numbers does not say it - the
money simply moves.

The suits are characters of our own. The ROM character set is copied into
RAM, four unused codes are given the shapes they should have, and text
carries them as four reserved byte values so that a card reads as a card in
the middle of a sentence too. Diamonds and hearts are drawn red, rank
included.

The function keys took the longest to find, and the answer is worth writing
down. They are not keys that deliver a code: they are text macros, and the
KERNAL feeds one out a character at a time when a program fetches with GETIN
- which this client does not use, that being what keeps the ROM switched out.
So nothing at all arrives in the keyboard buffer. What the scan leaves
instead is two bytes: how much of the macro is left, and where in the
definition area it started. Only the second identifies the key, and only as
an offset - so every definition is redefined to one byte long, which puts
those offsets at 0 to 7, and the originals go back when the client exits.

## Stage 6: a client, not a display

The machine asks who you are before anything else happens, under the PokerTH
logo, and the proxy waits with nothing but a listening socket until it is
told. An empty password joins as a guest; an empty name falls back to the
proxy's credentials file, which is how a test run gets going with nobody at
the keyboard. Nothing of the password is kept on the Plus/4 once it is sent.

The logo is characters too. There is no bitmap to spare and none is needed:
the codes from 128 up are free the moment the TED is told to stop inverting
them, which is 128 characters of eight by eight pixels - a logo, if the tiles
that repeat are stored once and the blank ones left as spaces.
[client/make-logo.py](client/make-logo.py) renders the SVG large, crops away
the margin it is drawn inside, scales to twelve characters square and writes
`logo.h`. It needs rsvg-convert and Pillow, and only when the logo changes.
The inversion goes off for that screen and back on for the game, which is
also why the logo is only ever seen there.

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
- **32 bytes may be in flight, not 256.** At 2400 baud, 32 bytes arrived
  perfectly, 64 lost one, 128 lost most - and the cliff between them was a
  puzzle until the interrupt storm above explained it. It was never about how
  many bytes there were but about how long a burst lasted, since what the
  storm needed was one byte arriving while nobody was collecting them. The
  window stays at 32 regardless: it is a reasonable amount to have in flight
  over a line this slow.

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
  Logging into one is simply a matter of sending the password as
  `clientUserData` inside the TLS connection
  (`src/net/clientstate.cpp:1614`) - which is precisely why the pinned key
  above is worth having. The message names suggest something more elaborate,
  and the `.proto` still carries a comment about SCRAM, but no challenge and
  response takes place: those are leftovers from a design that is not what
  runs.
- **Names are not in the events.** The lobby identifies players by id only;
  names come from `PlayerInfoRequest`. The proxy keeps that table so the
  Plus/4 does not have to.
