#!/usr/bin/env python3
"""
extract.py - the graphics of the C64 version, out of a memory dump

The Plus/4 version looks like Arlasoft Soccer on the C64. That game keeps
its pitch, its character set and its sprites in memory once it has
loaded. This script reads a dump of the C64's 64 KB, taken in VICE's
monitor while a match is running (`bank ram`, `save "ram.bin" 0 0000 ffff`),
and writes what the Plus/4 version uses as text files into data/:

  pitch.txt    the ground's 67 different rows of 79 character codes:
               stands, boards, pitch, goals, benches
  rows.txt     the ground as it is shown, 103 rows: which of those each
               is (the grass between the boxes and the centre circle,
               the touchlines beside the goals, are one row many times)
  chars.txt    the characters, as pictures
  sprites.txt  the players, the ball and the keepers, as pictures

The format of each file is described at its top.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, '..', 'data')

MAP = 0xA006            # the ground, row by row
MAP_W, MAP_H = 79, 67
ROWS, ROWS_N = 0x148F, 103  # the ground's rows: which of the map's each is
FONT = 0xF000           # its character set (multicolour)
SPR_BANK = 0xC000       # sprite block n at SPR_BANK + 64 * n
SPR_FIRST, SPR_LAST = 0x20, 0x5D

# multicolour pixel -> letter. Characters: background (the grass), the
# two shared colours (light blue, black) and the cell's (white). Sprites:
# transparent, the shared skin, the sprite's own (the shirt), black.
CHAR_SYM = '.bkw'
SPR_SYM = '.sck'


def main():
    ram = open(sys.argv[1], 'rb').read()
    if len(ram) == 65538:
        ram = ram[2:]
    os.makedirs(DATA, exist_ok=True)

    with open(os.path.join(DATA, 'pitch.txt'), 'w') as f:
        f.write('# The ground: %d rows of %d character codes (hex), top to bottom.\n'
                '# Every cell is multicolour in white; the stands are at the top and\n'
                '# the bottom, the benches on the right.\n' % (MAP_H, MAP_W))
        for r in range(MAP_H):
            row = ram[MAP + r * MAP_W:MAP + (r + 1) * MAP_W]
            f.write(row.hex() + '\n')

    with open(os.path.join(DATA, 'rows.txt'), 'w') as f:
        f.write('# The ground as it is shown, top to bottom: %d rows, each one of\n'
                '# pitch.txt\'s (its number, from 0).\n' % ROWS_N)
        rows = ram[ROWS:ROWS + ROWS_N]
        for i in range(0, ROWS_N, 16):
            f.write(' '.join('%d' % r for r in rows[i:i + 16]) + '\n')

    with open(os.path.join(DATA, 'chars.txt'), 'w') as f:
        f.write('# The characters, multicolour, 4 x 8 pixels each: . the grass,\n'
                '# b light blue, k black (both shared), w the cell\'s colour (white).\n')
        for c in range(256):
            f.write('char %02x\n' % c)
            for y in range(8):
                v = ram[FONT + c * 8 + y]
                f.write(''.join(CHAR_SYM[v >> (6 - 2 * p) & 3] for p in range(4)) + '\n')

    with open(os.path.join(DATA, 'sprites.txt'), 'w') as f:
        f.write('# The sprites, multicolour, 12 x 21 pixels each: . transparent,\n'
                '# s skin (shared), c the shirt (the sprite\'s own colour), k black.\n'
                '# Each under the number of its block.\n')
        for b in range(SPR_FIRST, SPR_LAST + 1):
            a = SPR_BANK + 64 * b
            f.write('sprite %02x\n' % b)
            for y in range(21):
                line = ''
                for x in range(3):
                    v = ram[a + y * 3 + x]
                    line += ''.join(SPR_SYM[v >> (6 - 2 * p) & 3] for p in range(4))
                f.write(line + '\n')


if __name__ == '__main__':
    main()
