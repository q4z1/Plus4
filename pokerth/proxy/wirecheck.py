#!/usr/bin/env python3
"""The other end of ../echo/echo.c: does every byte survive the wire?

Before a protocol is worth writing, the link under it has to be trustworthy.
This listens where VICE connects its emulated ACIA, waits for the Plus/4 to
send 0..255, sends the same ramp back, and checks that what is echoed matches
byte for byte. If 0xFF or a control character were mangled somewhere between
the 6551, VICE's IP232 escaping and this socket, this is where it shows.

    ./wirecheck.py &
    xplus4 -acia -myaciadev 0 -rsdev1 127.0.0.1:6400 -rsdev1ip232 \
           -autostart ../echo/build/echo.prg

Add --raw for a link that is not IP232, such as a real serial port bridged to
a socket.
"""

from __future__ import annotations

import argparse
import socket
import sys
import time

import ip232

RAMP = bytes(range(256))


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--listen", default="127.0.0.1:6400", metavar="HOST:PORT")
    ap.add_argument("--raw", action="store_true",
                    help="plain bytes instead of VICE's IP232 escaping")
    ap.add_argument("--timeout", type=float, default=120.0, metavar="SECONDS")
    ap.add_argument("--probe", type=int, default=256, metavar="BYTES",
                    help="how much of the ramp to send back (default all 256)")
    args = ap.parse_args(argv)

    host, _, port = args.listen.rpartition(":")
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind((host, int(port)))
    listener.listen(1)
    listener.settimeout(args.timeout)
    print(f"waiting on {host}:{port} ...", flush=True)

    try:
        sock, addr = listener.accept()
    except socket.timeout:
        print("nobody connected")
        return 1
    print(f"connected from {addr[0]}:{addr[1]}", flush=True)
    sock.settimeout(args.timeout)

    decoder = ip232.Decoder()
    if not args.raw:
        # Give the emulator a carrier. The cc65 driver does not look at DCD,
        # but a modem that never answers is a strange thing to emulate.
        sock.sendall(ip232.carrier(True))

    received = bytearray()
    probe_sent = False
    started = time.time()
    while time.time() - started < args.timeout:
        chunk = sock.recv(4096)
        if not chunk:
            print("the other end closed the connection")
            break
        if args.raw:
            data, changes = chunk, []
        else:
            data, changes = decoder.feed(chunk)
        for raised in changes:
            print(f"  DTR {'raised' if raised else 'lowered'}", flush=True)
        received += data
        if data:
            print(f"  {len(received):>3}/512 bytes"
                  f"{'  (ramp complete, echoing)' if len(received) >= 256 and not probe_sent else ''}",
                  flush=True)

        # Only answer once the ramp is complete, so that what follows is
        # unambiguously the echo. Talking sooner would also fill the Plus/4's
        # receive buffer while it is busy sending, which is its own lesson
        # but not this test's.
        if not probe_sent and len(received) >= len(RAMP):
            probe = RAMP[:args.probe]
            sock.sendall(probe if args.raw else ip232.encode(probe))
            probe_sent = True
        if len(received) >= len(RAMP) + args.probe:
            break

    sock.close()
    listener.close()

    sent_by_plus4 = bytes(received[:len(RAMP)])
    echoed = bytes(received[len(RAMP):len(RAMP) + args.probe])

    print()
    ok = True
    if sent_by_plus4 == RAMP:
        print("the Plus/4 sent all 256 byte values, unchanged")
    else:
        ok = False
        print(f"the ramp from the Plus/4 is wrong: {len(sent_by_plus4)} bytes")
        for i, (got, want) in enumerate(zip(sent_by_plus4, RAMP)):
            if got != want:
                print(f"  first difference at {i}: got {got:02X}, "
                      f"expected {want:02X}")
                break
    if echoed == RAMP[:args.probe]:
        print(f"and echoed all {args.probe} back, unchanged")
    else:
        ok = False
        print(f"the echo is wrong: {len(echoed)} of {args.probe} bytes")
        for i, (got, want) in enumerate(zip(echoed, RAMP)):
            if got != want:
                print(f"  first difference at {i}: got {got:02X}, "
                      f"expected {want:02X}")
                break

    print("\nwire check:", "ok" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
