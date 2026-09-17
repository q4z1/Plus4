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
| 1 | `proxy/lobbywatch.py` — log in, show the lobby and chat on a PC terminal | **done** |
| 2 | Define the Plus/4 wire protocol, with a reference client in Python | |
| 3 | Plus/4: ACIA driver, echo test through VICE's IP232 | |
| 4 | Plus/4: lobby list and chat | |
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
  rate limited by a token per session. So chat needs a registered account,
  which means SCRAM-SHA-1 in the proxy.
- **Names are not in the events.** The lobby identifies players by id only;
  names come from `PlayerInfoRequest`. The proxy keeps that table so the
  Plus/4 does not have to.
