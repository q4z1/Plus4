#!/usr/bin/env python3
"""
mkflags.py - the teams' flags for the title (data/flags.txt), as the file
"flags" on the disk: build/disk/flags.prg, which the boot loads to FLAGS
(build/gen/flags.inc).

    mkflags.py [--png preview.png]

A flag is 6 x 3 multicolour cells, 24 x 24 multicolour pixels (each two
hires pixels wide: 48 x 24, 2 to 1), drawn pixel for pixel in
data/flags.txt. A cell has four colours: the title's background ($FF15, a
dark green - the flags' dark green), white ($FF16) and the flag's second
shared colour ($FF17: red, unless another leaves fewer pixels wrong),
which every cell shares, and one of its own - of the others it needs, the
one that leaves the least wrong. data/flags.txt keeps to that; where a
flag does not, the pixels it would show in another colour (the nearest
the cell has) are counted and named.
The title draws a frame round each flag, so its dark green does not run
into the background.

The cells' patterns are shared by all the flags: each different one once,
256 at most (an error, not a blur, if there are more). The title copies
the patterns of the two flags it shows into the character codes its own
font leaves free, 18 at most a flag (it keeps two sets for each side, the
next flag made ready in the one not shown).

The file, one part after the other, ending at $E200 (the loading screen's
music there) - its address and its parts' in build/gen/flags.inc, for the
boot and the title, which lies below it:
  the patterns (FLAGS_N), each a mask - bit 7 row 0, a bit set for each
    row that is not the one above it again (row 0's always) - and those
    rows: most patterns repeat rows, so they take some 5 bytes, not 8
    (the title finds where each starts once: title.s pstarts)
  each team (title.s's order): its 18 cells' patterns, a row of 6 at a
    time, as their numbers, then their own colours, two cells a byte (the
    first in the low four bits), as places in the palette
  the palette, 15 colours, multicolour (bit 3 set), then "F"
  each team's second shared colour (its "red": $FF17 while its flag is
    drawn - the title's two flags are on lines of their own)
  the title's font (tools/mkdata.py's title_font: only the title needs it,
    so it is here rather than in the game's file)
"""
import os
import re
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mkdata  # noqa: E402  (the title's font)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
CELLS_W, CELLS_H = 6, 3
W, H = CELLS_W * 4, CELLS_H * 8          # multicolour pixels
HW, HH = W * 2, H                       # hires pixels
END = 0xE200                            # the file ends below (the loading
                                        # screen's music there), as far up
                                        # as it goes: the title below it
MOST = CELLS_W * CELLS_H                # patterns a flag may have
BG, WHITE, RED = 0x05, 0x71, 0x32       # the title's, $FF16, $FF17
SHADE = 'dark'                          # the flags' colour that is the background
OWN = {                                 # the TED's colours (luminance, hue)
    'black': 0x00, 'yellow': 0x67, 'gold': 0x67, 'green': 0x35,
    'dark': BG, 'navy': 0x16, 'blue': 0x36, 'sky': 0x53, 'maroon': 0x12,
    'red': RED,                         # (a cell's own where a flag's second
}                                       # shared colour is another: Ghana)
COLOURS = dict(OWN, white=WHITE, red=RED)
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
    """the flags: name, 24 rows of 24 colours' letters (a multicolour pixel
    each)"""
    flags = {}
    lines = [l.rstrip() for l in open(os.path.join(ROOT, 'data', 'flags.txt'))]
    lines = [l for l in lines if l and not l.startswith('#')]
    i = 0
    while i < len(lines):
        name, rows = lines[i].strip(), lines[i + 1:i + 1 + H]
        i += 1 + H
        assert len(rows) == H and all(len(r) == W for r in rows), '%s: not %d x %d' % (name, W, H)
        for r in rows:
            for ch in r:
                assert ch in LETTERS, '%s: what is %r?' % (name, ch)
        flags[name] = [[LETTERS[ch] for ch in r] for r in rows]
    return flags


# ---- cells --------------------------------------------------------------------

def dist(a, b):
    """how far apart two colours look: their brightness counts most"""
    ra, rb = RGB[COLOURS[a]], RGB[COLOURS[b]]
    luma = lambda c: 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]
    return 4 * (luma(ra) - luma(rb)) ** 2 + sum((p - q) ** 2 for p, q in zip(ra, rb))


def cells(img, second='red'):
    """each cell: (its pattern: 8 bytes, its own colour); and how many
    pixels came out in another colour. second: the flag's second shared
    colour ($FF17 while it is drawn), red unless another loses fewer pixels
    (best_second). A cell's own colour is the one of the others that
    leaves the least wrong; a pixel it cannot show takes the nearest it has"""
    out, lost = [], 0
    shared = (SHADE, 'white', second)
    for cy in range(CELLS_H):
        for cx in range(CELLS_W):
            px = [img[cy * 8 + y][cx * 4 + x] for y in range(8) for x in range(4)]
            others = sorted(set(p for p in px if p not in shared))

            def wrong(own):
                have = shared + (own,)
                return sum(min(dist(c, p) for c in have) for p in px)
            own = min(others, key=wrong) if others else 'black'
            have = [SHADE, 'white', second, own]
            pat = []
            for y in range(8):
                b = 0
                for x in range(4):
                    p = img[cy * 8 + y][cx * 4 + x]
                    if p not in have:
                        p = min(have, key=lambda c: dist(c, p))
                        lost += 1
                    b = b << 2 | (3 if p == own else have.index(p))
                pat.append(b)
            out.append((bytes(pat), own))
    return out, lost


def best_second(img):
    """the flag's second shared colour: the one that leaves the fewest
    pixels in another colour - red, unless another does better (Brazil's
    green and yellow, Ghana's gold, green and red: each cell has room for
    one colour of its own besides)"""
    return min(['red'] + [c for c in OWN if c not in ('red', SHADE)], key=lambda c: (cells(img, c)[1], c != 'red'))


def main():
    names = teams()
    defs = read()
    missing = [n for n in names if n not in defs]
    if missing:
        raise SystemExit('no flag for %s' % ', '.join(missing))
    all_cells, second = {}, {}
    for n in names:
        img = defs[n]
        second[n] = best_second(img)
        all_cells[n], lost = cells(img, second[n])
        if lost:
            print('  %-13s %d pixels in another colour' % (n, lost))
        if second[n] != 'red':
            print('  %-13s %s for red' % (n, second[n]))
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
    # the file: the patterns, the teams, the palette ("F" its 16th byte),
    # the second colours, the title's font - one after the other
    data = bytearray()
    for p in pats:                              # each: its mask, its rows
        rows = [r for i, r in enumerate(p) if i == 0 or r != p[i - 1]]
        data.append(sum(0x80 >> i for i in range(8) if i == 0 or p[i] != p[i - 1]))
        data += bytes(rows)
    at = {'FLAGS_TEAMS': len(data)}
    pat_bytes = len(data)
    for n in names:
        cs = all_cells[n]
        data += bytes(pats.index(pat) for pat, _ in cs)
        data += bytes(palette.index(cs[i][1]) | palette.index(cs[i + 1][1]) << 4
                      for i in range(0, len(cs), 2))
    at['FLAGS_PAL'] = len(data)
    data += bytes(OWN[c] | 0x08 for c in palette) + bytes(15 - len(palette))
    at['FLAGS_SIG'] = len(data)
    data += b'F'                                # (the title: the flags are there)
    at['FLAGS_2ND'] = len(data)
    data += bytes(COLOURS[second[n]] for n in names)
    at['FLAGS_FONT'] = len(data)
    data += bytes(mkdata.title_font())
    load = END - len(data)
    at = {k: load + v for k, v in at.items()}
    os.makedirs(os.path.join(ROOT, 'build', 'disk'), exist_ok=True)
    open(os.path.join(ROOT, 'build', 'disk', 'flags.prg'), 'wb').write(
        struct.pack('<H', load) + bytes(data))
    with open(os.path.join(ROOT, 'build', 'gen', 'flags.inc'), 'w') as f:
        f.write('; the flags\' file (tools/mkflags.py) - do not edit\n')
        f.write('FLAGS       = $%04X             ; the patterns: a mask, its rows\n' % load)
        f.write('FLAGS_N     = %d               ; (patterns)\n' % len(pats))
        for k, v in at.items():
            f.write('%-11s = $%04X\n' % (k, v))
        f.write('FLAGS_END   = $%04X\n' % (load + len(data)))
    print('flags: %d teams, %d patterns (%d bytes), %d colours of their own, %d bytes'
          % (len(names), len(pats), pat_bytes, len(palette), len(data)))
    if len(sys.argv) > 2 and sys.argv[1] == '--png':
        preview(sys.argv[2], names, all_cells, second)


def preview(path, names, all_cells, second):
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
                    rgb = [bg, RGB[WHITE], RGB[COLOURS[second[n]]], RGB[OWN[own]]][v]
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
