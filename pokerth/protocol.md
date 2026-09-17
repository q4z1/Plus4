# The proxy ↔ Plus/4 protocol

Version 1.

This is what crosses the serial line. It is deliberately not PokerTH: the
proxy holds the session, the player table, the game list and the encoding
rules, and sends the Plus/4 only what it needs to put on a 40×25 screen.

Both implementations - [proxy/p4wire.py](proxy/p4wire.py) and, later, the
6502 one - are written against this page.

## Frames

```
+--------+--------+--------------------+
| type   | length | payload (length)   |
+--------+--------+--------------------+
```

One byte of type, one byte of length, up to 255 bytes of payload, so a frame
is at most 257 bytes. There is no checksum and no escape character: the
transports we use (a TCP socket through VICE's IP232, or a serial WiFi modem)
already deliver bytes in order or not at all. There is no magic byte to
resynchronise on either — if a stream is ever cut mid-frame, both ends are in
trouble that a resync would only paper over, and the Plus/4 should be reset.

The high bit of the type byte gives the direction: clear means proxy to
Plus/4, set means Plus/4 to proxy. Upstream types 0x86–0x8E are still
reserved.

Integers are little endian, which is what the 6502 wants. Text is PETSCII and
carries no terminator; it runs to the end of the payload.

## Proxy → Plus/4

| Type | Name | Payload |
| --- | --- | --- |
| 0x01 | `HELLO` | version(1), server name |
| 0x02 | `STATE` | state(1), text |
| 0x03 | `NOTICE` | text |
| 0x10 | `GAME_CLEAR` | — |
| 0x11 | `GAME_ADD` | id(2), flags(1), players(1), seats(1), name |
| 0x12 | `GAME_UPDATE` | id(2), flags(1), players(1) |
| 0x13 | `GAME_REMOVE` | id(2) |
| 0x20 | `CHAT` | kind(1), name length(1), name, text |
| 0x21 | `PLAYERS` | count(2) |

`STATE` is the Plus/4's whole picture of where it stands: 0 offline,
1 connecting, 2 in the lobby, 3 at a table, 4 error. The text goes in the
status line. `NOTICE` carries what the server says out of band - maintenance
warnings, rejections - and is never dropped.

`GAME_ADD` flags: 0x01 private, 0x02 started, 0x04 ranking, 0x08 registered
players only, 0x10 invitation only.

Game ids are **not** the server's. PokerTH counts games in 32 bits and keeps
counting, so the proxy hands out its own small numbers, reuses them once a
game is gone, and translates back when a `JOIN` arrives. The Plus/4 sees a
short list of short numbers, which is also what fits on its screen.

`CHAT` kinds are numbered as in `pokerth.proto` so that nothing has to be
translated: 0 lobby, 1 game, 2 bot, 3 broadcast, 4 private. The name comes
first with its length so the Plus/4 can colour it differently without
scanning for a separator.

## Proxy → Plus/4, at a table

| Type | Name | Payload |
| --- | --- | --- |
| 0x40 | `TABLE` | id(2), seats(1), my seat(1), name |
| 0x41 | `SEAT` | seat(1), flags(1), money(4), name |
| 0x42 | `SEAT_BET` | seat(1), flags(1), money(4), bet(4) |
| 0x43 | `HAND` | number(2), dealer seat(1), small blind(4), card(1), card(1) |
| 0x44 | `BOARD` | count(1), that many cards |
| 0x45 | `POT` | pot(4) |
| 0x46 | `TURN` | seat(1), betting round(1) |
| 0x47 | `ASK` | allowed(1), to call(4), minimum raise(4), my money(4) |
| 0x48 | `RESULT` | seat(1), card(1), card(1), won(4), money(4) |
| 0x49 | `TABLE_END` | reason(1) |

Seats, not player ids. The server speaks in ids that mean nothing on a
screen; the proxy maps them to the seat numbers the table is drawn with, the
same way it hands out its own game ids.

`SEAT` flags: 0x01 taken, 0x02 folded, 0x04 all in, 0x08 dealer, 0x10 you,
0x20 sitting out.

`ASK` says it is your turn and what the server would accept, as bits in the
order of the actions: 0x01 fold, 0x02 check, 0x04 call, 0x08 bet, 0x10 raise,
0x20 all in. The three amounts are what the Plus/4 needs to offer a sensible
choice without doing any poker arithmetic of its own.

**Money is four bytes** because PokerTH counts it in 32 bits. A ranking game
starts everyone at 10000, which would fit in two, but a stack that grows all
evening would not, and truncating somebody's chips is not a rounding error.

**A card is one byte**, 0 to 51: rank is the code modulo 13 counting 2 up to
ace, suit is the code divided by 13 in the order diamonds, hearts, spades,
clubs. 52 means a card that is unknown or not there. The encoding is
PokerTH's own and crosses unchanged, so the Plus/4 needs one small table to
draw it and no conversion at all.

Hole cards take a detour worth knowing about: a player who logged in with an
account is sent them encrypted, with a key derived from that account's
password, so that nobody watching the connection can read them. The proxy
decrypts them (see proxy/cards.py) and what reaches the Plus/4 in `HAND` is
two plain card bytes.

## Plus/4 → proxy

| Type | Name | Payload |
| --- | --- | --- |
| 0x80 | `HELLO` | version(1), receive buffer size(2) |
| 0x81 | `ACK` | bytes consumed since the last ACK(2) |
| 0x82 | `CHAT` | text |
| 0x83 | `JOIN` | id(2) |
| 0x84 | `LEAVE` | — |
| 0x85 | `ACTION` | action(1), amount(4) |
| 0x8F | `BYE` | — |

`ACTION` is numbered as `NetPlayerAction` in `pokerth.proto`: 1 fold,
2 check, 3 call, 4 bet, 5 raise, 6 all in. It belongs to the table stage and
is listed here only so the numbering is fixed.

## Who speaks first

The Plus/4 does. It is the end that gets switched on and reset, so the proxy
waits for `HELLO` and treats every further `HELLO` as "start again": forget
what you thought I knew, here is the world from scratch.

```
Plus/4  -> HELLO version=1, rx=512
proxy   -> HELLO version=1, "pthsrv.pokerth.net"
proxy   -> STATE connecting
proxy   -> STATE lobby, "logged in as akali"
proxy   -> PLAYERS 7
proxy   -> GAME_CLEAR
proxy   -> GAME_ADD 4711 ...
```

If the versions differ, the proxy sends `STATE error` with a text saying so
and stops. Two versions that disagree about payload layouts cannot usefully
guess their way to agreement.

## Flow control

The Plus/4 grants credit. It announces the size of its receive buffer in
`HELLO`, and the proxy never has more than that many bytes outstanding:

- the proxy starts with `credit = rx_buffer`
- before sending a frame of *n* bytes it needs `credit ≥ n`, and then
  subtracts *n*
- a frame larger than `rx_buffer` is sent anyway, but only while nothing at
  all is outstanding; otherwise it could wait for credit that can never
  arrive
- every `ACK` adds back the bytes the Plus/4 has consumed, capped at
  `rx_buffer`
- the count includes the two header bytes, so both ends count the same thing

**The buffer the Plus/4 announces is not the buffer it has.** cc65's driver
holds 256 bytes, but the number to announce is however much may be in flight
without anything being lost, and that is a good deal smaller. Measured with
`echo/wiretest.sh` through VICE at 2400 baud: 32 bytes in flight arrive
perfectly, 64 lose a byte, 128 lose most of themselves. So 32 it is, until
the client is real enough to measure again - see "What the wire turned out to
be" in README.md.

The Plus/4 should acknowledge as it drains rather than at the end, roughly
every quarter buffer, so the proxy is never idle for want of credit. And it
must drain the driver unconditionally, into a buffer of its own, never
waiting for something it wants to send first: in cc65's driver a full receive
buffer stops transmission as well, so a program that waits to send before it
reads deadlocks both directions at once.

This matters more than it looks. A 1.76 MHz machine repainting a screen
cannot also drain a UART, and a poker server does not wait - a missed action
timeout is a folded hand. Doing it in the protocol rather than with RTS/CTS
lines keeps it working the same way over IP232 in the emulator, over a serial
WiFi modem, and over a null modem cable.

When credit runs out, events queue up in the proxy. The queue is not allowed
to grow without bound, so the proxy may fold several `GAME_UPDATE`s for the
same game into one and drop the oldest chat lines. It never drops `STATE`,
`NOTICE` or anything belonging to a hand in progress.
