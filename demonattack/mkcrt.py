#!/usr/bin/env python3
"""
mkcrt.py - the 32 KB cartridge image as a CRT file, the format VICE knows
cartridges by.

    python3 mkcrt.py build/demonattack.bin build/demonattack.crt

A CRT file is a 64-byte header followed by one CHIP packet per ROM. For the
Plus/4 family VICE takes the signature "PLUS4 CARTRIDGE ", hardware type 0
(a plain cartridge), and CHIP packets with bank 0 for C1 and bank 1 for
C2, at $8000 for the low half and $C000 for the high one. All numbers are
big-endian.
"""
import struct
import sys

NAME = b'DEMON ATTACK'

image = open(sys.argv[1], 'rb').read()
assert len(image) == 0x8000, len(image)

header = b'PLUS4 CARTRIDGE '                      # $00 signature
header += struct.pack('>IHH', 0x40, 0x0100, 0)   # $10 length, version, type
header += bytes([0, 0, 0]) + bytes(5)            # $18 EXROM, GAME, subtype
header += NAME.ljust(32, b'\0')                  # $20 name
assert len(header) == 0x40

out = header
for start, half in ((0x8000, image[:0x4000]), (0xC000, image[0x4000:])):
    # CHIP: length incl. this header, type 0 (ROM), bank 0 (C1), address, size
    out += b'CHIP' + struct.pack('>IHHHH', 0x10 + len(half), 0, 0, start, len(half))
    out += half

open(sys.argv[2], 'wb').write(out)
