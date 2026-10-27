#!/usr/bin/env python3
"""
mkflags.py - the teams' flags for the title (data/flags.txt), as the file
"flags" on the disk: build/disk/flags.prg, which the boot loads to $D300.

    mkflags.py [--png preview.png]

A flag is 6 x 4 multicolour cells, 24 x 32 multicolour pixels (each two
hires pixels wide: 48 x 32, 3 to 2) - a third of the width 2 cells, so
stripes down in thirds lie on the cells' edges. A cell has
four colours: the title's background ($FF15, a navy blue - the flags'
navy and dark blue), white ($FF16) and red ($FF17), which every cell
shares, and one of its own: the most a cell needs of any other. Where a
cell would need two others, the lesser takes the cell's own (black the
navy) - an edge between two of them runs along the cells, a step, but no
pixel comes out in a colour that is not there.
The title draws a frame round each flag, so its navy does not run into
the background.

The cells' patterns are shared by all the flags: each different one once,
256 at most (an error, not a blur, if there are more). The title copies
the patterns of the two flags it shows into the character codes its own
font leaves free, 37 at most a flag (it keeps two sets for each side, the
next flag made ready in the one not shown).

The file, at $D300:
  $D300  the patterns, 8 bytes each
  $DB00  each team (title.s's order): its 24 cells' patterns, a row of 6 at
         a time, as their numbers, then their own colours, two cells a
         byte (the first in the low four bits), as places in the palette
  $E000  the palette, 15 colours, multicolour (bit 3 set); "F" at $E00F
"""
import math
import os
import re
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
CELLS_W, CELLS_H = 6, 4
W, H = CELLS_W * 4, CELLS_H * 8          # multicolour pixels
HW, HH = W * 2, H                       # hires pixels
LOAD = 0xD300
TEAMS_AT = 0xDB00
PALETTE_AT = 0xE000
MOST = 37                               # patterns a flag may have
BG, WHITE, RED = 0x16, 0x71, 0x32       # the title's, $FF16, $FF17
SHARED = {'navy': 0, 'white': 1, 'red': 2}
OWN = {                                 # the TED's colours (luminance, hue)
    'black': 0x00, 'yellow': 0x67, 'gold': 0x67, 'green': 0x35,
    'dark': 0x15, 'blue': 0x36, 'sky': 0x53, 'maroon': 0x12,
}
COLOURS = dict(OWN, navy=BG, white=WHITE, red=RED)
LETTERS = {'N': 'navy', 'W': 'white', 'R': 'red', 'K': 'black', 'Y': 'yellow',
           'O': 'gold', 'G': 'green', 'D': 'dark', 'B': 'blue', 'S': 'sky', 'M': 'maroon'}


def ted_rgb():
    pal = []
    for line in open(os.path.join(HERE, 'yape-pal.txt')):
        p = line.split()
        if len(p) >= 3 and all(re.fullmatch('[0-9a-fA-F]{2}', x) for x in p[:3]):
            pal.append(tuple(int(x, 16) for x in p[:3]))
    return pal


RGB = ted_rgb()


def teams():
    """the teams' names in title.s's order"""
    src = open(os.path.join(ROOT, 'title.s')).read()
    return re.findall(r'^\s+team "([^"]+)"', src, re.M)


def read():
    """the flags (name: shapes) and the sprites (name: rows)"""
    flags, sprites = {}, {}
    lines = open(os.path.join(ROOT, 'data', 'flags.txt')).read().split('\n')
    i = 0
    while i < len(lines):
        line = lines[i].rstrip()
        i += 1
        if not line or line.startswith('#'):
            continue
        if line.startswith('sprite '):
            name = line.split()[1]
            rows = []
            while lines[i].strip() != 'end':
                rows.append(lines[i].strip())
                i += 1
            i += 1
            assert len(set(map(len, rows))) == 1, 'sprite %s: rows of different lengths' % name
            assert len(rows[0]) % 2 == 0, 'sprite %s: an odd width' % name
            # drawn in square pixels: two to a multicolour pixel, the one
            # that is not see-through
            sprites[name] = [''.join(r[i] if r[i] != '.' else r[i + 1]
                                     for i in range(0, len(r), 2)) for r in rows]
            continue
        m = re.match(r'(.+?)\s{2,}(.*)', line)
        flags[m.group(1).strip()] = [s.split() for s in m.group(2).split(';')]
    return flags, sprites


# ---- painting ---------------------------------------------------------------

def paint(shapes, sprites):
    """the flag, a colour's name for each multicolour pixel: shapes at 4 x 4
    samples a pixel (the colour most of them have), then the sprites
    pixel for pixel"""
    S = 4
    img = [[None] * (W * S) for _ in range(H * S)]
    for sh in shapes:
        kind, args = sh[0], sh[1:]
        if kind == 'sprite':
            continue
        cols = None
        if kind in ('hstripes', 'vstripes'):
            cols = []
            for a in args:
                c, n = (a.split('*') + ['1'])[:2]
                cols += [c] * int(n)
        for sy in range(H * S):
            for sx in range(W * S):
                x = (sx + 0.5) / (W * S)        # 0-1 across and down
                y = (sy + 0.5) / (H * S)
                c = shape_at(kind, args, x, y, x * HW, y * HH, cols)
                if c is not None:
                    assert c in COLOURS, c
                    img[sy][sx] = c
    out = []
    for y in range(H):
        row = []
        for x in range(W):
            count = {}
            for sy in range(y * S, y * S + S):
                for sx in range(x * S, x * S + S):
                    c = img[sy][sx]
                    count[c] = count.get(c, 0) + 1
            row.append(max(count, key=lambda k: count[k]))
        out.append(row)
    for sh in shapes:
        if sh[0] != 'sprite':
            continue
        rows = sprites[sh[1]]
        # its middle at x, y (0-1 of the flag), in whole pixels
        x0 = round(float(sh[2]) * W - len(rows[0]) / 2)
        y0 = round(float(sh[3]) * H - len(rows) / 2)
        for j, r in enumerate(rows):
            for i, ch in enumerate(r):
                if ch != '.':
                    out[y0 + j][x0 + i] = LETTERS[ch]
    return out


def shape_at(kind, args, x, y, px, py, cols):
    """the colour shape (kind, args) has at x, y (0-1 of the flag; px, py
    the same in hires pixels, HW x HH), None where it is not"""
    if kind == 'field':
        return args[0]
    if kind == 'hstripes':
        return cols[min(int(y * len(cols)), len(cols) - 1)]
    if kind == 'vstripes':
        return cols[min(int(x * len(cols)), len(cols) - 1)]
    if kind == 'rect':
        x0, y0, x1, y1 = map(float, args[1:5])
        return args[0] if x0 <= x < x1 and y0 <= y < y1 else None
    if kind == 'cross':
        w = float(args[1]) * HH
        cx = float(args[2]) if len(args) > 2 else 0.5
        cy = float(args[3]) if len(args) > 3 else 0.5
        if abs(px - cx * HW) < w / 2 or abs(py - cy * HH) < w / 2:
            return args[0]
        return None
    if kind == 'saltire':
        w = float(args[1]) * HH
        x0, y0, x1, y1 = map(float, args[2:6]) if len(args) > 2 else (0, 0, 1, 1)
        if not (x0 <= x < x1 and y0 <= y < y1):
            return None
        bx0, by0, bx1, by1 = x0 * HW, y0 * HH, x1 * HW, y1 * HH
        for (ax, ay, ex, ey) in ((bx0, by0, bx1, by1), (bx0, by1, bx1, by0)):
            dx, dy = ex - ax, ey - ay
            if abs(dy * (px - ax) - dx * (py - ay)) / math.hypot(dx, dy) < w / 2:
                return args[0]
        return None
    if kind == 'ujack':
        # a Union Jack in the box: a white saltire, a thin red one off its
        # middle (the way the flag has it), a white cross, a red cross
        x0, y0, x1, y1 = map(float, args[0:4])
        if not (x0 <= x < x1 and y0 <= y < y1):
            return None
        bw, bh = (x1 - x0) * HW, (y1 - y0) * HH
        u, v = px - x0 * HW, py - y0 * HH               # in the box
        c = None
        for sign in (1, -1):
            # the diagonals: from the top left, and from the bottom left
            if sign == 1:
                d = (bh * u - bw * v) / math.hypot(bw, bh)
            else:
                d = (bh * u - bw * (bh - v)) / math.hypot(bw, bh)
            if abs(d) < bh * 0.1:
                c = 'white'
                # the red one's half: below the diagonal on the left,
                # above it on the right (counterchanged)
                side = d * sign * (1 if u < bw / 2 else -1)
                if -bh * 0.06 < side < 0:
                    c = 'red'
        if abs(u - bw / 2) < bh * 0.17 or abs(v - bh / 2) < bh * 0.17:
            c = 'white'
        if abs(u - bw / 2) < bh * 0.09 or abs(v - bh / 2) < bh * 0.09:
            c = 'red'
        return c
    if kind in ('disc', 'halfdisc', 'ring'):
        cx, cy, r = map(float, args[1:4])
        d = math.hypot(px - cx * HW, py - cy * HH)
        if kind == 'ring':
            return args[0] if r * HH - float(args[4]) * HH < d < r * HH else None
        if d < r * HH and (kind == 'disc' or py >= cy * HH):
            return args[0]
        return None
    if kind == 'star':
        cx, cy, r = map(float, args[1:4])
        return args[0] if in_star(px - cx * HW, py - cy * HH, r * HH) else None
    if kind == 'diamond':
        cx, cy, w, h = map(float, args[1:5])
        return args[0] if abs(px - cx * HW) / (w * HW / 2) + abs(py - cy * HH) / (h * HH / 2) < 1 else None
    if kind == 'band':
        # a straight band from x0 y0 to x1 y1, w thick (of the height)
        x0, y0, x1, y1, w = map(float, args[1:6])
        ax, ay, ex, ey = x0 * HW, y0 * HH, x1 * HW, y1 * HH
        dx, dy = ex - ax, ey - ay
        t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)
        if 0 <= t <= 1 and abs(dy * (px - ax) - dx * (py - ay)) / math.hypot(dx, dy) < w * HH / 2:
            return args[0]
        return None
    raise SystemExit('what is %r?' % kind)


def in_star(dx, dy, r):
    """inside a five-pointed star of radius r, a point up"""
    d = math.hypot(dx, dy)
    if d > r:
        return False
    sector = 2 * math.pi / 5
    ang = math.atan2(dx, -dy) % sector
    ang = min(ang, sector - ang)            # 0 at a point, 36 degrees a notch
    a = math.radians(36)
    p1 = (r, 0.0)
    p2 = (r * 0.382 * math.cos(a), r * 0.382 * math.sin(a))
    q = (d * math.cos(ang), d * math.sin(ang))
    cross = (p2[0] - p1[0]) * (q[1] - p1[1]) - (p2[1] - p1[1]) * (q[0] - p1[0])
    return cross >= 0


# ---- cells --------------------------------------------------------------------

def dist(a, b):
    """how far apart two colours look: their brightness counts most"""
    ra, rb = RGB[COLOURS[a]], RGB[COLOURS[b]]
    luma = lambda c: 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]
    return 4 * (luma(ra) - luma(rb)) ** 2 + sum((p - q) ** 2 for p, q in zip(ra, rb))


def cells(img, rule=None):
    """each cell: (its pattern: 8 bytes, its own colour); and how many
    pixels came out in another colour. rule (the flag's "cells C L"): a
    cell with any C in it takes C for its own, and what else it cannot
    show comes out L"""
    out, lost = [], 0
    for cy in range(CELLS_H):
        for cx in range(CELLS_W):
            px = [img[cy * 8 + y][cx * 4 + x] for y in range(8) for x in range(4)]
            others = [p for p in px if p not in SHARED]
            own = max(sorted(set(others)), key=others.count) if others else 'black'
            if rule and rule[0] in others:
                own = rule[0]
            have = ['navy', 'white', 'red', own]
            pat = []
            for y in range(8):
                b = 0
                for x in range(4):
                    p = img[cy * 8 + y][cx * 4 + x]
                    if p not in have:
                        p = 'navy' if p == 'black' else rule[1] if rule else own
                        lost += 1
                    b = b << 2 | (3 if p == own else have.index(p))
                pat.append(b)
            out.append((bytes(pat), own))
    return out, lost


def main():
    names = teams()
    defs, sprites = read()
    missing = [n for n in names if n not in defs]
    if missing:
        raise SystemExit('no flag for %s' % ', '.join(missing))
    all_cells = {}
    for n in names:
        rule = [sh[1:] for sh in defs[n] if sh[0] == 'cells']
        all_cells[n], lost = cells(paint([sh for sh in defs[n] if sh[0] != 'cells'], sprites),
                                   rule[0] if rule else None)
        if lost and not rule:
            print('  %-13s %d pixels in another colour' % (n, lost))
    pats = []
    for n in names:
        for pat, _ in all_cells[n]:
            if pat not in pats:
                pats.append(pat)
    if len(pats) > 256:
        raise SystemExit('%d patterns: more than 256' % len(pats))
    for n in names:
        k = len(set(p for p, _ in all_cells[n]))
        if k > MOST:
            raise SystemExit('%s: %d patterns, more than %d' % (n, k, MOST))
    palette = sorted(set(own for n in names for _, own in all_cells[n]),
                     key=lambda c: list(OWN).index(c))
    assert len(palette) <= 15
    data = bytearray(PALETTE_AT + 16 - LOAD)
    for i, p in enumerate(pats):
        data[i * 8:i * 8 + 8] = p
    at = TEAMS_AT - LOAD
    for n in names:
        cs = all_cells[n]
        for pat, _ in cs:
            data[at] = pats.index(pat)
            at += 1
        for i in range(0, len(cs), 2):
            data[at] = palette.index(cs[i][1]) | palette.index(cs[i + 1][1]) << 4
            at += 1
    assert at <= PALETTE_AT - LOAD, 'the teams overrun the palette'
    for i, c in enumerate(palette):
        data[PALETTE_AT - LOAD + i] = OWN[c] | 0x08
    data[PALETTE_AT - LOAD + 15] = ord('F')     # (the title: the flags are there)
    os.makedirs(os.path.join(ROOT, 'build', 'disk'), exist_ok=True)
    open(os.path.join(ROOT, 'build', 'disk', 'flags.prg'), 'wb').write(
        struct.pack('<H', LOAD) + bytes(data))
    print('flags: %d teams, %d patterns, %d colours of their own, %d bytes'
          % (len(names), len(pats), len(palette), len(data)))
    if len(sys.argv) > 2 and sys.argv[1] == '--png':
        preview(sys.argv[2], names, all_cells)


def preview(path, names, all_cells):
    """the flags as the TED shows them, framed, 5 to a row, twice the size"""
    per, gap = 5, 12
    fw, fh = HW * 2, HH * 2
    rows = (len(names) + per - 1) // per
    PW, PH = per * (fw + gap) + gap, rows * (fh + gap) + gap
    bg = RGB[BG]
    frame = RGB[0x41]
    pix = [[bg] * PW for _ in range(PH)]
    for k, n in enumerate(names):
        ox = gap + (k % per) * (fw + gap)
        oy = gap + (k // per) * (fh + gap)
        for x in range(-4, fw + 4):
            pix[oy - 2][ox + x] = pix[oy - 1][ox + x] = frame
            pix[oy + fh][ox + x] = pix[oy + fh + 1][ox + x] = frame
        for y in range(-2, fh + 2):
            for d in range(1, 5):
                pix[oy + y][ox - d] = pix[oy + y][ox + fw + d - 1] = frame
        for ci, (pat, own) in enumerate(all_cells[n]):
            cx, cy = ci % CELLS_W, ci // CELLS_W
            for y in range(8):
                for x in range(4):
                    v = pat[y] >> (6 - 2 * x) & 3
                    rgb = [bg, RGB[WHITE], RGB[RED], RGB[OWN[own]]][v]
                    for dy in range(2):
                        for dx in range(4):
                            pix[oy + (cy * 8 + y) * 2 + dy][ox + (cx * 4 + x) * 4 + dx] = rgb
    raw = b''.join(b'\0' + bytes(c for p in row for c in p) for row in pix)

    def chunk(t, c):
        return struct.pack('>I', len(c)) + t + c + struct.pack('>I', zlib.crc32(t + c) & 0xffffffff)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n'
                           + chunk(b'IHDR', struct.pack('>IIBBBBB', PW, PH, 8, 2, 0, 0, 0))
                           + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))
    print(path)


if __name__ == '__main__':
    main()
