"""The wire protocol between the proxy and the Plus/4.

Everything hard about PokerTH - TLS, protobuf, 86 message types, player
tables, UTF-8 - stops at the proxy. What crosses the serial line to the
Plus/4 is this: a type byte, a length byte, and at most 255 bytes of payload
whose layout is fixed per type. Parsing it on a 7501 is a switch and a few
LDA/STA; there is nothing to allocate and nothing to scan for.

    +--------+--------+--------------------+
    | type   | length | payload (length)   |
    +--------+--------+--------------------+

The high bit of the type says which way the record travels: clear is proxy
to Plus/4, set is Plus/4 to proxy. That costs nothing and makes a capture
readable at a glance.

Two decisions worth stating because they shape both ends:

Text is PETSCII
    The proxy transliterates and truncates; the Plus/4 hands the bytes
    straight to conio. cc65 translates character literals to PETSCII anyway
    (see pacman/pacman.c), so this is the encoding the machine already
    thinks in. Umlauts become ae/oe/ue, anything else unrepresentable
    becomes '?'.

The Plus/4 grants credit
    A 1.76 MHz machine redrawing a screen cannot drain a UART at the same
    time, and a poker server does not wait. So the Plus/4 announces the size
    of its receive buffer in its HELLO, and the proxy never has more than
    that many unacknowledged bytes in flight. Every ACK frees what the
    Plus/4 has consumed. Flow control lives in the protocol rather than in
    RTS/CTS lines, which keeps it working over IP232 in the emulator, over a
    WiFi modem, and over a null modem cable alike.
"""

from __future__ import annotations

import struct
import unicodedata

PROTOCOL_VERSION = 1

MAX_PAYLOAD = 255
MAX_FRAME = 2 + MAX_PAYLOAD

# --- Record types ----------------------------------------------------------

# Proxy -> Plus/4.
D_HELLO = 0x01        # version(1), server name
D_STATE = 0x02        # state(1), text
D_NOTICE = 0x03       # text - server notices and errors, for the status line
D_GAME_CLEAR = 0x10   # -             forget the game list, a new one follows
D_GAME_ADD = 0x11     # id(2), flags(1), players(1), seats(1), name
D_GAME_UPDATE = 0x12  # id(2), flags(1), players(1)
D_GAME_REMOVE = 0x13  # id(2)
D_CHAT = 0x20         # kind(1), name length(1), name + text
D_PLAYERS = 0x21      # count(2)   players online

# Plus/4 -> proxy.
U_HELLO = 0x80        # version(1), receive buffer size(2)
U_ACK = 0x81          # bytes consumed since the last ACK(2)
U_CHAT = 0x82         # text
U_JOIN = 0x83         # id(2)
U_LEAVE = 0x84        # -
U_ACTION = 0x85       # action(1), amount(4)   reserved for the table stage
U_BYE = 0x8F          # -

# Types 0x40..0x5F downstream and 0x86..0x8E upstream are reserved for the
# table: seats, cards, pot, whose turn it is. They are deliberately not
# invented here - that layout should follow the first screen that draws them,
# not precede it.

TYPE_NAMES = {value: name for name, value in list(globals().items())
              if (name.startswith(("D_", "U_")) and isinstance(value, int))}


def type_name(kind: int) -> str:
    return TYPE_NAMES.get(kind, f"0x{kind:02X}")


# --- Payload vocabulary ----------------------------------------------------

# D_STATE
STATE_OFFLINE = 0
STATE_CONNECTING = 1
STATE_LOBBY = 2
STATE_TABLE = 3
STATE_ERROR = 4

# D_GAME_ADD / D_GAME_UPDATE flags.
GAME_PRIVATE = 0x01
GAME_STARTED = 0x02
GAME_RANKING = 0x04
GAME_REGISTERED_ONLY = 0x08
GAME_INVITE_ONLY = 0x10

# D_CHAT kinds, numbered as in pokerth.proto so nothing has to be translated.
CHAT_LOBBY = 0
CHAT_GAME = 1
CHAT_BOT = 2
CHAT_BROADCAST = 3
CHAT_PRIVATE = 4

# U_ACTION, numbered as NetPlayerAction in pokerth.proto.
ACTION_NONE = 0
ACTION_FOLD = 1
ACTION_CHECK = 2
ACTION_CALL = 3
ACTION_BET = 4
ACTION_RAISE = 5
ACTION_ALLIN = 6

# What the proxy cuts text down to. The screen is 40 columns, so a name that
# survives to the far end has to be short; the limits are here rather than in
# the Plus/4 so that the Plus/4 can trust every record it receives.
NAME_MAX = 20
GAME_NAME_MAX = 32
TEXT_MAX = 160


# --- PETSCII ---------------------------------------------------------------

# In the Plus/4's mixed case mode a byte 0x41 shows as 'a' and 0xC1 as 'A' -
# the usual CBM swap, and the same one cc65 applies to character literals.
_GERMAN = {"ä": "ae", "ö": "oe", "ü": "ue", "Ä": "Ae", "Ö": "Oe",
           "Ü": "Ue", "ß": "ss"}


def petscii(text: str, limit: int | None = None) -> bytes:
    """Transliterate text to PETSCII, dropping what the machine cannot show."""
    for src, dst in _GERMAN.items():
        text = text.replace(src, dst)
    # Strip accents that survive: é -> e. Anything still not ASCII is lost.
    text = unicodedata.normalize("NFKD", text)

    out = bytearray()
    for char in text:
        code = ord(char)
        if 0x61 <= code <= 0x7A:      # a-z
            out.append(code - 0x20)
        elif 0x41 <= code <= 0x5A:    # A-Z
            out.append(code + 0x80)
        elif 0x20 <= code <= 0x5F:    # digits, space, punctuation
            out.append(code)
        elif unicodedata.combining(char):
            continue                  # the accent of a decomposed letter
        elif code == 0x60 or 0x7B <= code <= 0x7E:
            out.append(ord("?"))      # backtick and braces have no home here
        elif code >= 0x80 or code < 0x20:
            out.append(ord("?"))
        if limit is not None and len(out) >= limit:
            break
    return bytes(out)


def unpetscii(data: bytes) -> str:
    """PETSCII back to ASCII, for logs and the reference client."""
    out = []
    for byte in data:
        if 0x41 <= byte <= 0x5A:
            out.append(chr(byte + 0x20))
        elif 0xC1 <= byte <= 0xDA:
            out.append(chr(byte - 0x80))
        elif 0x20 <= byte <= 0x5F:
            out.append(chr(byte))
        else:
            out.append("?")
    return "".join(out)


# --- Framing ---------------------------------------------------------------

class ProtocolError(Exception):
    pass


def frame(kind: int, payload: bytes = b"") -> bytes:
    if len(payload) > MAX_PAYLOAD:
        raise ProtocolError(
            f"{type_name(kind)} payload is {len(payload)} bytes, "
            f"over the {MAX_PAYLOAD} byte limit")
    return bytes((kind, len(payload))) + payload


class FrameReader:
    """Reassembles frames from a byte stream that arrives in any pieces."""

    def __init__(self):
        self._buf = bytearray()

    def feed(self, data: bytes) -> list[tuple[int, bytes]]:
        self._buf += data
        frames = []
        while len(self._buf) >= 2:
            length = self._buf[1]
            if len(self._buf) < 2 + length:
                break
            frames.append((self._buf[0], bytes(self._buf[2:2 + length])))
            del self._buf[:2 + length]
        return frames

    @property
    def pending(self) -> int:
        return len(self._buf)


# --- Building the records the proxy sends ----------------------------------

def hello(server_name: str) -> bytes:
    return frame(D_HELLO, bytes((PROTOCOL_VERSION,))
                 + petscii(server_name, NAME_MAX))


def state(value: int, text: str = "") -> bytes:
    return frame(D_STATE, bytes((value,)) + petscii(text, TEXT_MAX))


def notice(text: str) -> bytes:
    return frame(D_NOTICE, petscii(text, TEXT_MAX))


def game_clear() -> bytes:
    return frame(D_GAME_CLEAR)


def game_add(game_id: int, flags: int, players: int, seats: int,
             name: str) -> bytes:
    return frame(D_GAME_ADD,
                 struct.pack("<HBBB", game_id, flags, players, seats)
                 + petscii(name, GAME_NAME_MAX))


def game_update(game_id: int, flags: int, players: int) -> bytes:
    return frame(D_GAME_UPDATE, struct.pack("<HBB", game_id, flags, players))


def game_remove(game_id: int) -> bytes:
    return frame(D_GAME_REMOVE, struct.pack("<H", game_id))


def chat(kind: int, name: str, text: str) -> bytes:
    who = petscii(name, NAME_MAX)
    said = petscii(text, TEXT_MAX)
    return frame(D_CHAT, bytes((kind, len(who))) + who + said)


def players_online(count: int) -> bytes:
    return frame(D_PLAYERS, struct.pack("<H", min(count, 0xFFFF)))


# --- Reading the records the Plus/4 sends ----------------------------------

def decode_upstream(kind: int, payload: bytes) -> dict:
    """Turn one upstream record into a dict, or raise ProtocolError."""
    try:
        if kind == U_HELLO:
            version, rx_buffer = struct.unpack("<BH", payload)
            return {"kind": "hello", "version": version, "rx_buffer": rx_buffer}
        if kind == U_ACK:
            consumed, = struct.unpack("<H", payload)
            return {"kind": "ack", "consumed": consumed}
        if kind == U_CHAT:
            return {"kind": "chat", "text": unpetscii(payload)}
        if kind == U_JOIN:
            game_id, = struct.unpack("<H", payload)
            return {"kind": "join", "game_id": game_id}
        if kind == U_LEAVE:
            return {"kind": "leave"}
        if kind == U_ACTION:
            action, amount = struct.unpack("<BI", payload)
            return {"kind": "action", "action": action, "amount": amount}
        if kind == U_BYE:
            return {"kind": "bye"}
    except struct.error as e:
        raise ProtocolError(
            f"{type_name(kind)} has a payload of {len(payload)} bytes: {e}")
    raise ProtocolError(f"unknown upstream record {type_name(kind)}")


def hexdump(data: bytes) -> str:
    return " ".join(f"{b:02X}" for b in data)


# --- Self test -------------------------------------------------------------

def _selftest() -> int:
    ok = True

    def check(what, got, want):
        nonlocal ok
        if got != want:
            print(f"FAIL {what}: {got!r} != {want!r}")
            ok = False

    # Text survives the round trip, case and all.
    for text in ["hello", "PokerTH", "Table 3: all in!", "a-z A-Z 0-9"]:
        check(f"round trip {text!r}", unpetscii(petscii(text)), text)

    # cc65 turns 'A' into 193 and 'a' into 65; we must agree with it.
    check("'A'", petscii("A"), bytes((193,)))
    check("'a'", petscii("a"), bytes((65,)))

    check("umlauts", unpetscii(petscii("Grün")), "Gruen")
    check("accents", unpetscii(petscii("café")), "cafe")
    check("emoji", unpetscii(petscii("no 🂡 here")), "no ? here")
    check("truncation", len(petscii("x" * 100, 10)), 10)

    # A stream split at awkward places still yields the same frames.
    stream = (hello("pthsrv.pokerth.net")
              + state(STATE_LOBBY, "logged in")
              + game_add(4711, GAME_RANKING, 3, 10, "Ranking Game")
              + chat(CHAT_LOBBY, "hopper", "hello from a Plus/4"))
    whole = FrameReader().feed(stream)
    reader = FrameReader()
    in_pieces = []
    for i in range(0, len(stream), 7):
        in_pieces += reader.feed(stream[i:i + 7])
    check("split stream", in_pieces, whole)
    check("frame count", len(whole), 4)
    check("no leftovers", reader.pending, 0)

    # Upstream records decode to what they were built from.
    check("hello", decode_upstream(U_HELLO, struct.pack("<BH", 1, 512)),
          {"kind": "hello", "version": 1, "rx_buffer": 512})
    check("ack", decode_upstream(U_ACK, struct.pack("<H", 64)),
          {"kind": "ack", "consumed": 64})
    check("join", decode_upstream(U_JOIN, struct.pack("<H", 4711)),
          {"kind": "join", "game_id": 4711})
    check("action", decode_upstream(U_ACTION, struct.pack("<BI", ACTION_RAISE, 200)),
          {"kind": "action", "action": ACTION_RAISE, "amount": 200})

    print("\nWhat a lobby record looks like on the wire:")
    for record in whole:
        built = frame(*record)
        print(f"  {type_name(record[0]):<13} {len(built):>3} bytes  "
              f"{hexdump(built[:16])}{' ...' if len(built) > 16 else ''}")

    print("\nself test:", "ok" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    import sys
    sys.exit(_selftest())
