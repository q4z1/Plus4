"""IP232, the protocol VICE's emulated ACIA speaks over a TCP socket.

Wiring the Plus/4's serial port to a socket is what makes the emulator usable
for this project at all, but the socket does not carry plain bytes. VICE
claims 0xFF for itself to pass the modem control lines along, and doubles it
when it means a literal one (vice/src/rs232drv/rs232net.c):

    FF FF        one data byte 0xFF
    FF 00        the emulator lowered DTR / we lower DCD
    FF 01        the emulator raised DTR / we raise DCD
    FF 02, FF 03 the same for RI, our direction only

Which matters more than it sounds: a record of the protocol in ../protocol.md
can hold 0xFF anywhere - as a length, in a game id, in PETSCII text - and an
unescaped one would be swallowed as a status byte and silently change what
the emulator thinks the modem is doing.

Real hardware does not need any of this. The escaping belongs to the emulator
socket alone, which is why it lives in its own file: the proxy turns it on
for a VICE connection and leaves it off for a serial port.
"""

from __future__ import annotations

MAGIC = 0xFF

DTR_LOW = 0
DTR_HIGH = 1
DCD_LOW = 0
DCD_HIGH = 1
DCD_MASK = 1
RI_LOW = 0
RI_HIGH = 2
RI_MASK = 2


def encode(data: bytes) -> bytes:
    """Data bytes as they have to go on an IP232 socket."""
    return data.replace(b"\xff", b"\xff\xff")


def carrier(up: bool) -> bytes:
    """Tell the emulator whether there is a carrier (DCD)."""
    return bytes((MAGIC, DCD_HIGH if up else DCD_LOW))


class Decoder:
    """Splits an IP232 stream into data and modem line changes.

    feed() returns the data bytes and any DTR changes seen, in order. The
    escape may be split across two reads, so the state is kept here.
    """

    def __init__(self):
        self._saw_magic = False

    def feed(self, chunk: bytes) -> tuple[bytes, list[bool]]:
        data = bytearray()
        dtr_changes: list[bool] = []
        for byte in chunk:
            if self._saw_magic:
                self._saw_magic = False
                if byte == MAGIC:
                    data.append(MAGIC)
                else:
                    dtr_changes.append(bool(byte & DCD_MASK))
            elif byte == MAGIC:
                self._saw_magic = True
            else:
                data.append(byte)
        return bytes(data), dtr_changes


def _selftest() -> int:
    ok = True

    def check(what, got, want):
        nonlocal ok
        if got != want:
            print(f"FAIL {what}: {got!r} != {want!r}")
            ok = False

    check("escaping", encode(b"\x01\xff\x02"), b"\x01\xff\xff\x02")
    check("nothing to escape", encode(b"abc"), b"abc")

    # Every byte value survives the round trip.
    ramp = bytes(range(256))
    data, changes = Decoder().feed(encode(ramp))
    check("ramp round trip", data, ramp)
    check("no line changes", changes, [])

    # A status byte is taken out of the data, an escape split across two
    # reads still works.
    decoder = Decoder()
    first, changes_a = decoder.feed(b"\x41\xff")
    second, changes_b = decoder.feed(b"\xff\x42\xff\x01\x43")
    check("split escape", first + second, b"\x41\xff\x42\x43")
    check("DTR raised", changes_a + changes_b, [True])

    decoder = Decoder()
    check("DTR lowered", decoder.feed(b"\xff\x00")[1], [False])

    print("self test:", "ok" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    import sys
    sys.exit(_selftest())
