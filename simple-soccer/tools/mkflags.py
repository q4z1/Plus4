#!/usr/bin/env python3
"""
mkflags.py - the teams' flags for the title (data/flags.txt), as the file
"flags" and "flagset" on the disk: build/disk/flags.prg and flagset.prg,
which the boot loads to $E000 and $F000.

    mkflags.py [--png preview.png]

A flag is 6 x 4 multicolour cells, 24 x 32 multicolour pixels (two hires
pixels wide each: 48 x 32, 3 to 2). In a cell the TED has the background
(not used), two colours every cell shares - white ($FF16) and red ($FF17)
- and one of its own: the most a flag needs there of the others; any
other there comes out as the nearer of the three. The cells' patterns
are shared by all the flags, as many as the title's character set has
codes it does not use itself (0-31, 96-127, 164-255: 156); more, and the
least used are taken for the likest of the rest.

"flagset", at $F000: the title's character set (title.s TFONT) with the
patterns at their codes - the title puts its own characters in after.
"flags", at $E000: each team (title.s's order) its 24 cells' codes, a row
of 6 at a time, then their own colours, two cells a byte (the first in
the low four bits) as places in the palette; at $E4F0 the palette, 15
colours, multicolour (bit 3 set), and "F" at $E4FF: the flags are there.
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
LOAD = 0xE000
PALETTE_AT = 0xE4F0
SET_AT = 0xF000
CODES = list(range(32)) + list(range(96, 128)) + list(range(164, 256))

WHITE, RED = 0x71, 0x42                 # the shared ones ($FF16, $FF17)
OWN = {                                 # the TED's colours (luminance, hue)
    'black': 0x00, 'yellow': 0x77, 'gold': 0x67, 'green': 0x35,
    'dark': 0x25, 'blue': 0x46, 'navy': 0x26, 'sky': 0x63, 'maroon': 0x22,
}
COLOURS = dict(OWN, white=WHITE, red=RED)


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


def flags():
    out = {}
    for line in open(os.path.join(ROOT, 'data', 'flags.txt')):
        line = line.rstrip()
        if not line or line.startswith('#'):
            continue
        m = re.match(r'(.+?)\s{2,}(.*)', line)
        out[m.group(1).strip()] = [s.split() for s in m.group(2).split(';')]
    return out


# ---- painting ---------------------------------------------------------------

def paint(shapes):
    """the flag at 4 x 4 samples a multicolour pixel, in flag units"""
    S = 4
    img = [[None] * (W * S) for _ in range(H * S)]
    for sh in shapes:
        kind, args = sh[0], sh[1:]
        if kind in ('hstripes', 'vstripes'):
            cols = []
            for a in args:
                c, n = (a.split('*') + ['1'])[:2]
                cols += [c] * int(n)
        for sy in range(H * S):
            for sx in range(W * S):
                # (x, y): 0-1 across and down; (px, py): hires pixels
                x = (sx + 0.5) / (W * S)
                y = (sy + 0.5) / (H * S)
                px, py = x * 48, y * 32
                c = None
                if kind == 'field':
                    c = args[0]
                elif kind == 'hstripes':
                    c = cols[min(int(y * len(cols)), len(cols) - 1)]
                elif kind == 'vstripes':
                    c = cols[min(int(x * len(cols)), len(cols) - 1)]
                elif kind == 'rect':
                    x0, y0, x1, y1 = map(float, args[1:5])
                    if x0 <= x < x1 and y0 <= y < y1:
                        c = args[0]
                elif kind == 'cross':
                    w = float(args[1]) * 32
                    cx = float(args[2]) if len(args) > 2 else 0.5
                    cy = float(args[3]) if len(args) > 3 else 0.5
                    if abs(px - cx * 48) < w / 2 or abs(py - cy * 32) < w / 2:
                        c = args[0]
                elif kind == 'saltire':
                    w = float(args[1]) * 32
                    x0, y0, x1, y1 = map(float, args[2:6]) if len(args) > 2 else (0, 0, 1, 1)
                    if x0 <= x < x1 and y0 <= y < y1:
                        bx0, by0, bx1, by1 = x0 * 48, y0 * 32, x1 * 48, y1 * 32
                        for (ax, ay, ex, ey) in ((bx0, by0, bx1, by1), (bx0, by1, bx1, by0)):
                            dx, dy = ex - ax, ey - ay
                            d = abs(dy * (px - ax) - dx * (py - ay)) / math.hypot(dx, dy)
                            if d < w / 2:
                                c = args[0]
                elif kind in ('disc', 'halfdisc'):
                    cx, cy, r = map(float, args[1:4])
                    if math.hypot(px - cx * 48, py - cy * 32) < r * 32:
                        if kind == 'disc' or py >= cy * 32:
                            c = args[0]
                elif kind == 'star':
                    cx, cy, r = map(float, args[1:4])
                    if in_star(px - cx * 48, py - cy * 32, r * 32):
                        c = args[0]
                elif kind == 'diamond':
                    cx, cy, w, h = map(float, args[1:5])
                    if abs(px - cx * 48) / (w * 24) + abs(py - cy * 32) / (h * 16) < 1:
                        c = args[0]
                elif kind == 'dots':
                    x0, y0, x1, y1 = map(float, args[1:5])
                    nx, ny = int(args[5]), int(args[6])
                    for i in range(nx):
                        for j in range(ny):
                            dx = x0 + (x1 - x0) * (i / max(nx - 1, 1))
                            dy = y0 + (y1 - y0) * (j / max(ny - 1, 1))
                            if abs(px - dx * 48) < 1.0 and abs(py - dy * 32) < 0.5 + 0.01:
                                c = args[0]
                else:
                    raise SystemExit('what is %r?' % kind)
                if c is not None:
                    assert c in COLOURS, c
                    img[sy][sx] = c
    # a multicolour pixel: the colour most of its samples have
    out = []
    for y in range(H):
        row = []
        for x in range(W):
            count = {}
            for sy in range(y * S, y * S + S):
                for sx in range(x * S, x * S + S):
                    c = img[sy][sx]
                    count[c] = count.get(c, 0) + 1
            # (a dot is one sample wide: any sample of a small shape wins
            # over the field, so stars and dots show)
            row.append(max(count, key=lambda k: count[k]))
        out.append(row)
    return out


def in_star(dx, dy, r):
    """inside a five-pointed star of radius r, a point up"""
    ang = math.atan2(dx, -dy)
    d = math.hypot(dx, dy)
    if d > r:
        return False
    # the edge's distance at this angle: between the points (r) and the
    # notches (r * 0.38), straight lines between them
    seg = (ang % (2 * math.pi / 5)) / (2 * math.pi / 5)
    t = abs(seg - 0.5) * 2               # 1 at a point, 0 at a notch
    inner = r * 0.38
    edge = inner + (r - inner) * t ** 1.6
    return d < edge


# ---- cells --------------------------------------------------------------------

def dist(a, b):
    """how far apart two colours look: their brightness counts most"""
    ra, rb = RGB[COLOURS[a]], RGB[COLOURS[b]]
    luma = lambda c: 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]
    return 4 * (luma(ra) - luma(rb)) ** 2 + sum((p - q) ** 2 for p, q in zip(ra, rb))


def cells(img):
    """each cell: (pattern: 8 bytes, its own colour's name)"""
    out = []
    for cy in range(CELLS_H):
        for cx in range(CELLS_W):
            px = [img[cy * 8 + y][cx * 4 + x] for y in range(8) for x in range(4)]
            others = [p for p in px if p not in ('white', 'red')]
            own = max(set(others), key=others.count) if others else 'black'
            pat = []
            for y in range(8):
                b = 0
                for x in range(4):
                    p = img[cy * 8 + y][cx * 4 + x]
                    if p not in ('white', 'red', own):
                        p = min(('white', 'red', own), key=lambda q: dist(p, q))
                    b = b << 2 | {'white': 1, 'red': 2}.get(p, 3)
                pat.append(b)
            out.append((bytes(pat), own))
    return out


def tile_dist(a, b):
    return sum(((x >> s) & 3) != ((y >> s) & 3) for x, y in zip(a, b) for s in (0, 2, 4, 6))


def main():
    names = teams()
    defs = flags()
    missing = [n for n in names if n not in defs]
    if missing:
        raise SystemExit('no flag for %s' % ', '.join(missing))
    all_cells = {n: cells(paint(defs[n])) for n in names}
    # the patterns, the most used first; too many: the least used taken for
    # the likest of the others
    use = {}
    for n in names:
        for pat, _ in all_cells[n]:
            use[pat] = use.get(pat, 0) + 1
    pats = sorted(use, key=lambda p: -use[p])
    swap = {}
    while len(pats) > len(CODES):
        p = pats.pop()
        swap[p] = min(pats, key=lambda q: tile_dist(p, q))
    for p in list(swap):
        while swap[p] in swap:
            swap[p] = swap[swap[p]]
    index = {p: i for i, p in enumerate(pats)}
    palette = sorted(set(own for n in names for _, own in all_cells[n]),
                     key=lambda c: list(OWN).index(c))
    assert len(palette) <= 15
    charset = bytearray(256 * 8)
    for i, p in enumerate(pats):
        charset[CODES[i] * 8:CODES[i] * 8 + 8] = p
    data = bytearray(PALETTE_AT + 16 - LOAD)
    at = 0
    for n in names:
        cs = all_cells[n]
        for pat, _ in cs:
            data[at] = CODES[index[swap.get(pat, pat)]]
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
    open(os.path.join(ROOT, 'build', 'disk', 'flagset.prg'), 'wb').write(
        struct.pack('<H', SET_AT) + bytes(charset))
    print('flags: %d teams, %d patterns (%d merged), %d colours, %d + %d bytes'
          % (len(names), len(pats), len(swap), len(palette), len(data), len(charset)))
    if len(sys.argv) > 2 and sys.argv[1] == '--png':
        preview(sys.argv[2], names, all_cells, swap)


def preview(path, names, all_cells, swap):
    """the flags as the TED shows them, 6 to a row, twice the size"""
    per, gap = 6, 8
    fw, fh = 48 * 2, 32 * 2
    rows = (len(names) + per - 1) // per
    PW, PH = per * (fw + gap) + gap, rows * (fh + gap) + gap
    bg = RGB[0x16]
    pix = [[bg] * PW for _ in range(PH)]
    for k, n in enumerate(names):
        ox = gap + (k % per) * (fw + gap)
        oy = gap + (k // per) * (fh + gap)
        for ci, (pat, own) in enumerate(all_cells[n]):
            pat = swap.get(pat, pat)
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
