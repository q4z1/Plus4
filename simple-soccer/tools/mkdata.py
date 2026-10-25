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
  tac_*        the formations (data/tactics.txt): for each of the eight
               and each player (0-10 the team at the bottom, 11-21 the
               one at the top) his area's corner and how far across it
               he goes for each pixel the ball goes (x / 510, y / 641,
               times 256)
  ymap_*       where a place on the pitch is on the ground: the game
               runs on Sensible Soccer's pitch, 640 long, the ground
               shows it 363 high

The colours are the TED's nearest to the C64's (VICE's "pepto" palette
against the one Yape shows, tools/yape-pal.txt).
"""
import math
import os
import random
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


# The boards along the top of the pitch, in place of the C64's: the
# game's name twice on black, its letters two cells wide (the C64's were
# one, too narrow for an M) and each in a colour of its own, and boards
# in one colour round them. Their characters take codes the ground
# does not use.
BOARD_ROW = 8
BOARD_WIDTH = 71                # cells 0-70 (the benches' grass after)
BOARD_TEXT = 'SIMPLE SOCCER'
GLYPHS = {                      # 7 x 6 multicolour pixels, a gap after
    'S': ['.XXXXX.', 'XX.....', '.XXXXX.', '.....XX', '.....XX', 'XXXXXX.'],
    'I': ['XXXXXX.', '..XX...', '..XX...', '..XX...', '..XX...', 'XXXXXX.'],
    'M': ['XX...XX', 'XXX.XXX', 'XX.X.XX', 'XX...XX', 'XX...XX', 'XX...XX'],
    'P': ['XXXXXX.', 'XX...XX', 'XX...XX', 'XXXXXX.', 'XX.....', 'XX.....'],
    'L': ['XX.....', 'XX.....', 'XX.....', 'XX.....', 'XX.....', 'XXXXXXX'],
    'E': ['XXXXXXX', 'XX.....', 'XXXXX..', 'XX.....', 'XX.....', 'XXXXXXX'],
    'O': ['.XXXXX.', 'XX...XX', 'XX...XX', 'XX...XX', 'XX...XX', '.XXXXX.'],
    'C': ['.XXXXX.', 'XX...XX', 'XX.....', 'XX.....', 'XX...XX', '.XXXXX.'],
    'R': ['XXXXXX.', 'XX...XX', 'XX...XX', 'XXXXXX.', 'XX..XX.', 'XX...XX'],
}
# (TED hue, luminance) of each letter: warm and cool, the second name the
# other way round; the board between
WARM = [(7, 7), (7, 6), (7, 5), (2, 6), (2, 5), (2, 4)]
COOL = [(3, 7), (3, 6), (3, 5), (6, 6), (6, 5), (6, 4)]
PLAIN = (6, 3)
# the crowd: a shirt colour each, the cell's own (the C64 has them all white)
CROWD = [(2, 4), (2, 6), (6, 4), (6, 6), (3, 6), (4, 4), (4, 6), (7, 7), (7, 5), (1, 7),
         (3, 4), (5, 7)]
CROWD_CHARS = {0x01, 0x03, 0x04, 0x05, 0x07, 0xCF, 0xD0, 0xD1, 0xD2}


def mc(hue, lum):
    """a multicolour cell's own colour (bit 3: multicolour)"""
    return lum << 4 | hue | 0x08


def ground():
    return [bytearray.fromhex(l.strip()) for l in open(os.path.join(DATA, 'pitch.txt'))
            if l.strip() and not l.startswith('#')]


def board_chars():
    """code -> eight bytes for the boards' characters, and the codes in
    order: the letters' halves, black, the plain board"""
    rows = ground()
    rows[BOARD_ROW][:BOARD_WIDTH] = bytes(BOARD_WIDTH)
    used = set(b for r in rows for b in r)
    free = [c for c in range(1, 256) if c not in used]
    letters = sorted(set(BOARD_TEXT) - {' '})
    shapes = {}
    for ch in letters:
        g = [l + '.' for l in GLYPHS[ch]]
        for half in range(2):
            # the letter in the cell's colour (%11) on black (%10), a black
            # line above and below
            shapes[(ch, half)] = [0xAA] + [
                sum((3 if l[half * 4 + p] == 'X' else 2) << (6 - 2 * p) for p in range(4))
                for l in g] + [0xAA]
    shapes['black'] = [0xAA] * 8
    shapes['plain'] = [0xAA] + [0xFF] * 6 + [0xAA]
    codes = dict(zip(sorted(shapes, key=str), free))
    return codes, shapes


def board_row():
    """the cells of the board row and their colours"""
    codes, _ = board_chars()
    cells, cols = [], []

    def name(sweep):
        cells.append(codes['black'])
        cols.append(mc(1, 7))
        i = 0
        for ch in BOARD_TEXT:
            if ch == ' ':
                cells.append(codes['black'])
                cols.append(mc(1, 7))
                sweep = COOL if sweep is WARM else WARM
                i = 0
                continue
            for half in range(2):
                cells.append(codes[(ch, half)])
                cols.append(mc(*sweep[i]))
            i += 1
        cells.append(codes['black'])
        cols.append(mc(1, 7))
    def plain(n):
        cells.extend([codes['plain']] * n)
        cols.extend([mc(*PLAIN)] * n)
    plain(4)
    name(WARM)
    plain(9)
    name(COOL)
    plain(4)
    assert len(cells) == BOARD_WIDTH, len(cells)
    return bytes(cells), cols


def pitch():
    rows = ground()
    rows[BOARD_ROW][:BOARD_WIDTH] = board_row()[0]
    return [bytes(r) for r in rows]


def colours():
    """the cells' own colours where they are not white: [(row, 79
    colours)] - the crowd's shirts, the boards"""
    rnd = random.Random(1)
    rows = pitch()
    white = ted_of(1, range(8)) | 0x08
    out = []
    for y, r in enumerate(rows):
        cols = [white] * len(r)
        for x, c in enumerate(r):
            if c in CROWD_CHARS:
                cols[x] = mc(*rnd.choice(CROWD))
        if y == BOARD_ROW:
            cols[:BOARD_WIDTH] = board_row()[1]
        if any(c != white for c in cols):
            out.append((y, cols))
    return out


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
    codes, shapes = board_chars()
    for k, c in codes.items():
        font[c * 8:c * 8 + 8] = bytes(shapes[k])
    return font


# The figures, in the order of their numbers in the game (game.inc IMG_):
# a player running in eight directions, from up clockwise, three steps
# each (the C64's sprite blocks; the third step is its fourth block),
# then the ball.
RUN_BASE = [0x20, 0x24, 0x28, 0x2C, 0x30, 0x34, 0x38, 0x3C]
# Then the ball turning (four pictures), and its shadow (its own colour
# black, from the C64's).
RUN_FRAMES = [b + f for b in RUN_BASE for f in (0, 1, 3)]
IMAGES = RUN_FRAMES + [0x40, 0x41, 0x42, 0x43, 0x54]
BLACK = {0x54}

# The pitch: Sensible Soccer's lines (goal lines at y 49 and 689, the
# halfway line at 369) onto the ground's (pixel rows 107.5, 291.5, 466.5 -
# the C64's near half is a little shorter than its far one)
PITCH_Y = (49, 369, 689)
GROUND_Y = (107.5, 291.5, 466.5)


PAD = 8


def has11(b):
    return any(b >> (2 * p) & 3 == 3 for p in range(4))


def black11(b):
    """b with its pixels in the cell's colour (%11) black (%10): what a
    player's cell shows of the white under it"""
    for p in range(4):
        if b >> (2 * p) & 3 == 3:
            b &= ~(1 << (2 * p))
    return b


def black_socks(pic):
    """A player with his socks black, not in his shirt's colour: below the
    shirt (line 8 on) nothing that takes the cell's colour - the cells at
    his feet, over the lines and next to the ball, stay white"""
    return pic[:8] + [l.replace('c', 'k') for l in pic[8:]]


def sprites():
    txt = open(os.path.join(DATA, 'sprites.txt')).read()
    return {int(m.group(1), 16): m.group(2).split()
            for m in re.finditer(r'sprite ([0-9a-f]{2})\n((?:[.sck]{12}\n){21})', txt)}


def no_shadow(pic):
    """A player without his shadow: the black below the last line with
    skin or shirt in it gone - no cell of the ground under it darkened"""
    body = [i for i, l in enumerate(pic) if 's' in l or 'c' in l]
    if not body:
        return pic
    return pic[:body[-1] + 1] + ['.' * len(pic[0])] * (len(pic) - body[-1] - 1)


def figure(pic, black=False):
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
    # the shadow: black below the last line with skin or shirt in it. A
    # column at the right with nothing but shadow in it is left out - a
    # column costs the draw as much as a full one, and the shadow is a
    # little shorter for it
    body = [i for i, l in enumerate(pic) if 's' in l or 'c' in l]
    last_body = body[-1] if body else len(pic)
    recs = []
    for s in range(4):
        ncol = (s + w + 3) // 4
        while ncol > 1 and not any(
                pic[y][x] != '.' for y in range(oy, min(oy + h, last_body + 1))
                for x in range((ncol - 1) * 4 - s + ox, ncol * 4 - s + ox) if ox <= x < ox + w):
            ncol -= 1
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


def tactics():
    """[formation][player 0-21] = (x from, x slope, y from, y slope): the
    team at the bottom (0-10) has the second area of each line, the team
    at the top (11-21) the first"""
    forms = []
    for line in open(os.path.join(DATA, 'tactics.txt')):
        if line.startswith('formation'):
            forms.append([None] * 22)
        elif line.strip() and not line.startswith('#'):
            v = [int(x) for x in line.split()]
            pl = v[0] - 1
            for team, (x0, y0, x1, y1) in ((0, v[5:9]), (1, v[1:5])):
                forms[-1][team * 11 + pl] = (x0, min(255, round((x1 - x0 + 1) * 256 / 510)),
                                             y0, min(255, round((y1 - y0 + 1) * 256 / 641)))
    return forms


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
        tint = colours()
        out.write('\n        .export crow_of, cmap_lo, cmap_hi\n        .rodata\n')
        out.write('crow_of:                ; each ground row: its colours\' number, $FF white\n')
        idx = {y: i for i, (y, _) in enumerate(tint)}
        hexrows(out, bytes(idx.get(y, 255) for y in range(h)))
        out.write('cmap_lo: .byte ' + ', '.join('<cmap%d' % i for i in range(len(tint))) + '\n')
        out.write('cmap_hi: .byte ' + ', '.join('>cmap%d' % i for i in range(len(tint))) + '\n')
        for i, (y, cols) in enumerate(tint):
            out.write('cmap%d:                  ; ground row %d\n' % (i, y))
            hexrows(out, bytes(cols), 40)
        spr = sprites()
        figs = [figure(black_socks(no_shadow(spr[b])) if b in RUN_FRAMES else spr[b], b in BLACK)
                for b in IMAGES]
        out.write('\n        .export img_ox, img_oy, img_lo, img_hi, black11\n        .rodata\n')
        out.write('black11:                ; a byte\'s %11 pixels made %10\n')
        hexrows(out, bytes(black11(b) for b in range(256)))
        out.write('img_ox: .byte ' + ', '.join(str(f[0]) for f in figs) + '\n')
        out.write('img_oy: .byte ' + ', '.join(str(f[1]) for f in figs) + '\n')
        names = ['img%d_%d' % (i, s) for i in range(len(figs)) for s in range(4)]
        out.write('img_lo: .lobytes ' + ', '.join(names) + '\n')
        out.write('img_hi: .hibytes ' + ', '.join(names) + '\n')
        for i, f in enumerate(figs):
            for sh, rec in enumerate(f[2]):
                out.write('img%d_%d:\n' % (i, sh))
                hexrows(out, rec)
        out.write('\n        .export tac_x0l, tac_x0h, tac_xs, tac_y0l, tac_y0h, tac_ys\n        .rodata\n')
        forms = tactics()
        for name, f in (('tac_x0l', lambda t: t[0] & 255), ('tac_x0h', lambda t: t[0] >> 8),
                        ('tac_xs', lambda t: t[1]), ('tac_y0l', lambda t: t[2] & 255),
                        ('tac_y0h', lambda t: t[2] >> 8), ('tac_ys', lambda t: t[3])):
            out.write(name + ':                ; formation * 22 + player\n')
            hexrows(out, bytes(f(t) for form in forms for t in form), 22)
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
        # the skin a little lighter than the C64's light red
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
