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
  atan_tab     the angle of a move from its steps (|dy| * 32 + |dx|, both
               under 32): 0 along x .. 64 along y, $FF none - the angle
               Sensible Soccer steers by, linear in dy/dx rather than a
               true arc tangent
  sin_tab      127 * sin, 256 steps to a circle (signed)
  ymap_*       where a place on the pitch is on the ground: the game
               runs on Sensible Soccer's pitch, 640 long, the ground
               shows it 363 high

The colours are the TED's nearest to the C64's (VICE's "pepto" palette
against the one Yape shows, tools/yape-pal.txt).
"""
import math
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
# Then the ball turning (four pictures), and its shadow (its own colour
# black, from the C64's); then the ball again giving way, its white in the
# light shared colour (engine.s: over a cell another figure has coloured).
IMAGES = [b + f for b in RUN_BASE for f in (0, 1, 3)] + [0x40, 0x41, 0x42, 0x43, 0x54] \
    + [0x40, 0x41, 0x42, 0x43]
BLACK = {0x54}
GIVE_WAY = 29                   # the first of the giving-way pictures

# The pitch: Sensible Soccer's lines (goal lines at y 49 and 689, the
# halfway line at 369) onto the ground's (pixel rows 107.5, 291.5, 466.5 -
# the C64's near half is a little shorter than its far one)
PITCH_Y = (49, 369, 689)
GROUND_Y = (107.5, 291.5, 466.5)


PAD = 8


def has11(b):
    return any(b >> (2 * p) & 3 == 3 for p in range(4))


def light11(b):
    """b with its pixels in the cell's colour (%11) in the light shared
    colour (%01)"""
    for p in range(4):
        if b >> (2 * p) & 3 == 3:
            b &= ~(2 << (2 * p))
    return b


def sprites():
    txt = open(os.path.join(DATA, 'sprites.txt')).read()
    return {int(m.group(1), 16): m.group(2).split()
            for m in re.finditer(r'sprite ([0-9a-f]{2})\n((?:[.sck]{12}\n){21})', txt)}


def figure(pic, black=False, light=False):
    """A sprite cut to its pixels: (ox, oy, records): its first column and
    row in the sprite, and for each shift 0-3 (pixels to the right in its
    first character) the bytes the draw takes - the number of columns,
    then per column its first line, its lines, the first and the last
    line with a pixel in the cell's colour (from the first line; 255, 0
    none), PAD empty lines, the lines' pixels, PAD empty lines, and the
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
                    if black and v == 3:
                        v = 2
                    if light and v == 3:
                        v = 1
                    d = d << 2 | v      # s %01 skin, k %10 black, c %11 the cell's colour
                    k = k << 2 | (0 if v else 3)
                data.append(d)
                keep.append(k)
            top = next(i for i in range(h) if keep[i] != 0xFF)
            bot = max(i for i in range(h) if keep[i] != 0xFF) + 1
            # the lines with pixels in the cell's colour (the shirt):
            # the first and the last, from top; none: 255, 0
            col = [i - top for i in range(top, bot) if has11(data[i])]
            ctop, cbot = (col[0], col[-1]) if col else (255, 0)
            # eight empty lines before the pixels and after them: over
            # grass the draw copies whole cells (engine.s, fig_draw)
            out += [top, bot - top, ctop, cbot] + [0] * PAD + data[top:bot] + [0] * PAD \
                + keep[top:bot]
        recs.append(out)
    return ox, oy, recs


YMAP = 768


def atan(dx, dy):
    if dx == 0 and dy == 0:
        return 0xFF
    if dy <= dx:
        return int(32 * dy / dx + 0.5)
    return 64 - int(32 * dx / dy + 0.5)


def ymap(y):
    i = 0 if y < PITCH_Y[1] else 1
    return int(GROUND_Y[i] + (y - PITCH_Y[i]) * (GROUND_Y[i + 1] - GROUND_Y[i])
               / (PITCH_Y[i + 1] - PITCH_Y[i]))


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
        figs = [figure(spr[b], b in BLACK, i >= GIVE_WAY) for i, b in enumerate(IMAGES)]
        out.write('\n        .export img_ox, img_oy, img_lo, img_hi, img_alt, light11\n        .rodata\n')
        alt = [GIVE_WAY + IMAGES.index(b) - IMAGES.index(0x40) if i < GIVE_WAY and b in (0x40, 0x41, 0x42, 0x43)
               else 255 for i, b in enumerate(IMAGES)]
        out.write('img_alt: .byte ' + ', '.join(str(a) for a in alt) + '    ; giving way, 255 none\n')
        out.write('light11:                ; a byte\'s %11 pixels made %01\n')
        hexrows(out, bytes(light11(b) for b in range(256)))
        out.write('img_ox: .byte ' + ', '.join(str(f[0]) for f in figs) + '\n')
        out.write('img_oy: .byte ' + ', '.join(str(f[1]) for f in figs) + '\n')
        names = ['img%d_%d' % (i, s) for i in range(len(figs)) for s in range(4)]
        out.write('img_lo: .lobytes ' + ', '.join(names) + '\n')
        out.write('img_hi: .hibytes ' + ', '.join(names) + '\n')
        for i, f in enumerate(figs):
            for sh, rec in enumerate(f[2]):
                out.write('img%d_%d:\n' % (i, sh))
                hexrows(out, rec)
        out.write('\n        .export atan_tab, sin_tab, ymap_lo, ymap_hi\n        .segment "TABLES"\n')
        out.write('atan_tab:               ; |dy| * 32 + |dx|\n')
        hexrows(out, bytes(atan(dx, dy) for dy in range(32) for dx in range(32)))
        out.write('sin_tab:\n')
        hexrows(out, bytes((int(round(32767 * math.sin(2 * math.pi * i / 256))) >> 8) & 255
                           for i in range(256)))
        ym = [ymap(y) for y in range(YMAP)]
        out.write('ymap_lo:\n')
        hexrows(out, bytes(v & 255 for v in ym))
        out.write('ymap_hi:\n')
        hexrows(out, bytes(v >> 8 for v in ym))
    with open(os.path.join(GEN, 'data.inc'), 'w') as out:
        out.write('; made by tools/mkdata.py from data/ - do not edit\n\n')
        out.write('MAP_W       = %d\nMAP_H       = %d\n\n' % (w, h))
        out.write('IMAGES      = %d\n' % len(IMAGES))
        out.write('IMG_BALL    = %d            ; four, turning\n' % IMAGES.index(0x40))
        out.write('IMG_SHADOW  = %d\n' % IMAGES.index(0x54))
        out.write('YMAP        = %d            ; ymap_*: pitch y 0..YMAP-1\n\n' % YMAP)
        out.write('COL_GRASS   = $%02X           ; C64 green\n' % ted_of(5))
        # the skin a little lighter than the C64's light red: it is also what
        # white turns to under a shirt (engine.s), and the ball giving way
        skin = ted_of(10)
        skin = min(skin + 0x20, 0x70 | skin & 15)
        out.write('COL_SKIN    = $%02X           ; C64 light red, lighter: the shared colour\n' % skin)
        out.write('COL_BLACK   = $%02X\n' % ted_of(0))
        out.write('COL_LINE    = $%02X           ; white, multicolour (the cells\' own)\n'
                  % (ted_of(1, range(8)) | 0x08))
        out.write('COL_TEAM1   = $%02X           ; cyan, multicolour\n' % (ted_of(3, range(8)) | 0x08))
        out.write('COL_TEAM2   = $%02X           ; yellow, multicolour\n' % (ted_of(7, range(8)) | 0x08))


if __name__ == '__main__':
    main()
