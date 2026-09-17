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
Plus/4, set means Plus/4 to proxy. Types 0x40–0x5F and 0x86–0x8E are reserved
for the table stage - seats, cards, pot, whose turn it is - and are left
undefined on purpose, because that layout should follow the first screen that
draws them rather than precede it.

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

`CHAT` kinds are numbered as in `pokerth.proto` so that nothing has to be
translated: 0 lobby, 1 game, 2 bot, 3 broadcast, 4 private. The name comes
first with its length so the Plus/4 can colour it differently without
scanning for a separator.

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
- every `ACK` adds back the bytes the Plus/4 has consumed, capped at
  `rx_buffer`
- the count includes the two header bytes, so both ends count the same thing

The Plus/4 should acknowledge as it drains rather than at the end, roughly
every quarter buffer, so the proxy is never idle for want of credit.

This matters more than it looks. A 1.76 MHz machine repainting a screen
cannot also drain a UART, and a poker server does not wait - a missed action
timeout is a folded hand. Doing it in the protocol rather than with RTS/CTS
lines keeps it working the same way over IP232 in the emulator, over a serial
WiFi modem, and over a null modem cable.

When credit runs out, events queue up in the proxy. The queue is not allowed
to grow without bound, so the proxy may fold several `GAME_UPDATE`s for the
same game into one and drop the oldest chat lines. It never drops `STATE`,
`NOTICE` or anything belonging to a hand in progress.
