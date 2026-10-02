#!/usr/bin/env python3
"""pictures.py - the droids' pictures out of the original, into data/

The original draws a droid's picture (before a transfer, at a console)
from parts, into eight sprites, two side by side in four rows; the routine
is at $3629 and takes the droid type in $58. The pictures are not stored
anywhere whole, so they were taken by running that routine in VICE's
monitor for each type, with the game at the transfer's first screen:

    > 0334 20 29 36 4c 37 03      (JSR $3629 : JMP $0337)
    break 0337
    > 0058 <type>    r pc=0334    x
    bank ram   save "g<type>.bin" 0 0000 ffff
    bank io    save "g<type>io.bin" 0 d000 d03f

and saving memory and the VIC's registers each time. This script makes
data/pictures.txt from those 48 files:

    python3 tools/pictures.py <directory with g00.bin ... g23io.bin>

The console's menu symbols are sprites too, four hires ones (two of them
twice as wide) beside its first page. With the same two dumps taken there
(c0.bin, c0io.bin), this makes data/icons.txt:

    python3 tools/pictures.py --icons <directory with c0.bin, c0io.bin>

The title's logo, the big PARADROID over the whole screen, is characters
of the deck's set, hires. From the dumps taken while it shows (logoram.bin,
logoio.bin), this makes data/logo.txt:

    python3 tools/pictures.py --logo <directory with logoram.bin, logoio.bin>
"""
import os, sys

DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'data')
if sys.argv[1] == '--icons':
    # each symbol on the character grid of the screen: its cells' column
    # and row, then its pixels from there (h set), in whole cells
    D = sys.argv[2]
    ram = open(os.path.join(D, 'c0.bin'), 'rb').read()[2:]
    io = open(os.path.join(D, 'c0io.bin'), 'rb').read()[2:]
    t = ['# The console\'s menu symbols, the original\'s hires sprites (tools/',
         '# pictures.py --icons): per symbol its first cell\'s column and row on',
         '# the screen, then its pixels from there, whole cells (h set).', '']
    row_end = 0
    for i in range(1, 5):
        x = (io[2 * i] | ((io[0x10] >> i) & 1) << 8) - 24
        y = io[2 * i + 1] - 50
        y = max(y, row_end)             # (the last two share a row: moved down)
        wide = io[0x1D] >> i & 1
        blk = ram[0x4000 + ram[0x20D + i] * 64:][:63]
        col, row, dx, dy = x // 8, y // 8, x % 8, y % 8
        w = ((dx + (48 if wide else 24)) + 7) // 8
        h = (dy + 21 + 7) // 8
        img = [['.'] * (w * 8) for _ in range(h * 8)]
        for yy in range(21):
            for b in range(24):
                if blk[3 * yy + b // 8] >> (7 - b % 8) & 1:
                    for k in range(2 if wide else 1):
                        img[dy + yy][dx + (b * 2 + k if wide else b)] = 'h'
        t.append('icon %d %d %d' % (i - 1, col, row))
        t += [''.join(r) for r in img]
        t.append('')
        row_end = (row + h) * 8
    open(os.path.join(DATA, 'icons.txt'), 'w').write('\n'.join(t))
    print('data/icons.txt')
    sys.exit()

if sys.argv[1] == '--logo':
    D = sys.argv[2]
    ram = open(os.path.join(D, 'logoram.bin'), 'rb').read()[2:]
    io = open(os.path.join(D, 'logoio.bin'), 'rb').read()[2:]
    codes = ram[0x4800:0x4800 + 1000]
    cols = [io[0x800 + i] & 15 for i in range(1000)]
    t = ['# The title\'s logo (tools/pictures.py --logo): 25 rows of 40 character',
         '# codes of the deck\'s set, then their C64 colours (hires), the',
         '# background\'s colour, then the characters.', '']
    for r in range(25):
        t.append('row ' + ' '.join('%02x' % c for c in codes[r * 40:r * 40 + 40]))
    for r in range(25):
        t.append('col ' + ''.join('%x' % c for c in cols[r * 40:r * 40 + 40]))
    t.append('bg %d' % (io[0x21] & 15))
    t.append('')
    for c in sorted(set(codes)):
        t.append('char %02x' % c)
        for y in range(8):
            v = ram[0x7800 + c * 8 + y]
            t.append(''.join('#' if v & (0x80 >> i) else '.' for i in range(8)))
        t.append('')
    open(os.path.join(DATA, 'logo.txt'), 'w').write('\n'.join(t))
    print('data/logo.txt')
    sys.exit()

DIR = sys.argv[1]
OUT = os.path.join(DATA, 'pictures.txt')
VIC_BANK = 0x4000
POINTERS = 0x020D       # the sprites' pointers, as the interrupt sets them

t = ['# The droids\' pictures, as the original draws them (tools/pictures.py):',
     '# per type its C64 colours (the sprites\' own, multicolour 2; multicolour 1',
     '# is black), then the picture, 48 pixels wide from the top left of its',
     '# first sprite: . nothing, k black, s the sprites\' colour, m multicolour',
     '# 2 (all in pixel pairs), h a hires pixel in the sprites\' colour.', '']
for n in range(24):
    ram = open(os.path.join(DIR, 'g%02d.bin' % n), 'rb').read()[2:]
    io = open(os.path.join(DIR, 'g%02dio.bin' % n), 'rb').read()[2:]
    ptr = ram[POINTERS:POINTERS + 8]
    xs = [io[2 * i] | ((io[0x10] >> i) & 1) << 8 for i in range(8)]
    ys = [io[2 * i + 1] for i in range(8)]
    mc = io[0x1C]
    cols = set(io[0x27 + i] & 15 for i in range(8))
    assert len(cols) == 1, cols
    x0, y0 = min(xs), min(ys)
    img = [['.'] * 48 for _ in range(110)]
    for i in range(8):
        blk = ram[VIC_BANK + ptr[i] * 64:VIC_BANK + ptr[i] * 64 + 63]
        for y in range(21):
            for b in range(3):
                v = blk[3 * y + b]
                X = xs[i] - x0 + b * 8
                Y = ys[i] - y0 + y
                if mc >> i & 1:
                    for k in range(4):
                        p = (v >> (6 - 2 * k)) & 3
                        if p:
                            img[Y][X + 2 * k] = img[Y][X + 2 * k + 1] = '.ksm'[p]
                else:
                    for k in range(8):
                        if v >> (7 - k) & 1:
                            img[Y][X + k] = 'h'
    while img and img[-1] == ['.'] * 48:
        img.pop()
    t.append('picture %d colour=%d mc2=%d top=%d' % (n, cols.pop(), io[0x26] & 15, y0))
    t += [''.join(r) for r in img]
    t.append('')
open(OUT, 'w').write('\n'.join(t))
print('data/pictures.txt')
