#!/usr/bin/env python3
"""
mkdata.py - the game's data, from the text files in data/, as assembly

Writes build/gen/data.s (the tables) and build/gen/data.inc (their sizes
and the colours, for the code):

  pitch_map    the ground, 79 x 67 character codes, row by row
  pitch_font   its characters, 8 bytes each, multicolour
  img_*        the figures (data/sprites.txt), cut to what they cover and
               shifted to each of the four pixels in a character, ready
               to go into the characters under them

The colours are the TED's nearest to the C64's (VICE's "pepto" palette
against the one Yape shows, tools/yape-pal.txt).
"""
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, '..', 'data')
GEN = os.path.join(HERE, '..', 'build', 'gen')

C64 = ['000000', 'ffffff', '68372b', '70a4b2', '6f3d86', '588d43', '352879', 'b8c76f',
       '6f4f25', '433900', '9a6759', '444444', '6c6c6c', '9ad284', '6c5eb5', '959595']


def ted_palette():
    pal = []
    for line in open(os.path.join(HERE, 'yape-pal.txt')):
        if re.match(r'^[0-9a-f]{2} [0-9a-f]{2} [0-9a-f]{2}', line):
            pal.append(tuple(int(x, 16) for x in line.split()[:3]))
    return pal


def ted_of(c64, hues=range(16)):
    """The TED colour byte nearest to a C64 colour; hues limits the hue
    (a multicolour cell's own colour can only be 0-7)."""
    pal = ted_palette()
    want = tuple(int(C64[c64][i:i + 2], 16) for i in (0, 2, 4))
    best = None
    for lum in range(8):
        for hue in hues:
            if hue == 0 and lum:
                continue                # black has one luminance
            r, g, b = pal[lum * 16 + hue]
            d = (r - want[0]) ** 2 + (g - want[1]) ** 2 + (b - want[2]) ** 2
            if best is None or d < best[0]:
                best = (d, lum << 4 | hue)
    return best[1]


def pitch():
    rows = [bytes.fromhex(l.strip()) for l in open(os.path.join(DATA, 'pitch.txt'))
            if l.strip() and not l.startswith('#')]
    return rows


def chars():
    txt = open(os.path.join(DATA, 'chars.txt')).read()
    font = bytearray(256 * 8)
    for m in re.finditer(r'char ([0-9a-f]{2})\n((?:[.bkw]{4}\n){8})', txt):
        c = int(m.group(1), 16)
        for y, line in enumerate(m.group(2).split()):
            v = 0
            for p in line:
                v = v << 2 | '.bkw'.index(p)
            font[c * 8 + y] = v
    return font


# The figures, in the order of their numbers in the game (game.inc IMG_):
# a player running in eight directions, from up clockwise, three steps
# each (the C64's sprite blocks; the third step is its fourth block),
# then the ball.
RUN_BASE = [0x20, 0x24, 0x28, 0x2C, 0x30, 0x34, 0x38, 0x3C]
IMAGES = [b + f for b in RUN_BASE for f in (0, 1, 3)] + [0x40]


def sprites():
    txt = open(os.path.join(DATA, 'sprites.txt')).read()
    return {int(m.group(1), 16): m.group(2).split()
            for m in re.finditer(r'sprite ([0-9a-f]{2})\n((?:[.sck]{12}\n){21})', txt)}


def figure(pic):
    """A sprite cut to its pixels: (ox, oy, records): its first column and
    row in the sprite, and for each shift 0-3 (pixels to the right in its
    first character) the bytes the draw takes - the number of columns,
    then per column its first line, its lines, the lines' pixels and the
    bits to keep of what is under them (a column only as tall as its
    pixels go)."""
    rows = [i for i, l in enumerate(pic) if l.strip('.')]
    cols = [i for i in range(12) if any(l[i] != '.' for l in pic)]
    oy, h = rows[0], rows[-1] - rows[0] + 1
    ox, w = cols[0], cols[-1] - cols[0] + 1
    recs = []
    for s in range(4):
        ncol = (s + w + 3) // 4
        out = [ncol]
        for c in range(ncol):
            data, keep = [], []
            for y in range(oy, oy + h):
                d = k = 0
                for p in range(4):
                    x = c * 4 + p - s + ox
                    v = '.skc'.index(pic[y][x]) if ox <= x < ox + w else 0
                    d = d << 2 | v      # s %01 skin, k %10 black, c %11 the cell's colour
                    k = k << 2 | (0 if v else 3)
                data.append(d)
                keep.append(k)
            top = next(i for i in range(h) if keep[i] != 0xFF)
            bot = max(i for i in range(h) if keep[i] != 0xFF) + 1
            out += [top, bot - top] + data[top:bot] + keep[top:bot]
        recs.append(out)
    return ox, oy, recs


def hexrows(out, data, per=16):
    for i in range(0, len(data), per):
        out.write('        .byte ' + ', '.join('$%02X' % b for b in data[i:i + per]) + '\n')


def main():
    os.makedirs(GEN, exist_ok=True)
    rows = pitch()
    h, w = len(rows), len(rows[0])
    with open(os.path.join(GEN, 'data.s'), 'w') as out:
        out.write('; made by tools/mkdata.py from data/ - do not edit\n\n')
        out.write('        .export _pitch_map, _pitch_font\n\n        .rodata\n')
        out.write('_pitch_map:\n')
        for r in rows:
            hexrows(out, r, 40)
        out.write('\n        .segment "FONTDATA"\n_pitch_font:\n')
        hexrows(out, chars())
        spr = sprites()
        figs = [figure(spr[b]) for b in IMAGES]
        out.write('\n        .export img_ox, img_oy, img_lo, img_hi\n        .rodata\n')
        out.write('img_ox: .byte ' + ', '.join(str(f[0]) for f in figs) + '\n')
        out.write('img_oy: .byte ' + ', '.join(str(f[1]) for f in figs) + '\n')
        names = ['img%d_%d' % (i, s) for i in range(len(figs)) for s in range(4)]
        out.write('img_lo: .lobytes ' + ', '.join(names) + '\n')
        out.write('img_hi: .hibytes ' + ', '.join(names) + '\n')
        for i, f in enumerate(figs):
            for sh, rec in enumerate(f[2]):
                out.write('img%d_%d:\n' % (i, sh))
                hexrows(out, rec)
    with open(os.path.join(GEN, 'data.inc'), 'w') as out:
        out.write('; made by tools/mkdata.py from data/ - do not edit\n\n')
        out.write('MAP_W       = %d\nMAP_H       = %d\n\n' % (w, h))
        out.write('IMAGES      = %d\n\n' % len(IMAGES))
        out.write('COL_GRASS   = $%02X           ; C64 green\n' % ted_of(5))
        out.write('COL_SKIN    = $%02X           ; C64 light red, the sprites\' shared colour\n' % ted_of(10))
        out.write('COL_BLACK   = $%02X\n' % ted_of(0))
        out.write('COL_LINE    = $%02X           ; white, multicolour (the cells\' own)\n'
                  % (ted_of(1, range(8)) | 0x08))
        out.write('COL_TEAM1   = $%02X           ; cyan, multicolour\n' % (ted_of(3, range(8)) | 0x08))
        out.write('COL_TEAM2   = $%02X           ; yellow, multicolour\n' % (ted_of(7, range(8)) | 0x08))


if __name__ == '__main__':
    main()
