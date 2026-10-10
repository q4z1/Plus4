#!/usr/bin/env python3
"""yape_split.py - the line between the map and the toolbar, in Yape
(whose TED leaves the processor less time than VICE's): in a series of
pictures in the farmhouse, on the farm and in the mine, row 22 (the black
separator) must be black all through, and the toolbar's first line must
show none of the map's colours - the interrupt that switches over has to
be done inside the black row, every time. Pictures to build/test/."""
import os, re, sys, zlib
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from yape import Yape

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, 'build', 'test')
os.makedirs(OUT, exist_ok=True)
lab = {}
for l in open(os.path.join(ROOT, 'build', 'stardew.lbl')):
    p = l.split()
    lab.setdefault(p[2].lstrip('.'), int(p[1], 16))
d = {}
for line in open(os.path.join(ROOT, 'build', 'gen', 'data.h')):
    w = line.split()
    if len(w) == 3 and w[0] == '#define':
        d[w[1]] = w[2]


def read_png(path):
    data = open(path, 'rb').read()
    pos, idat, w, h = 8, b'', 0, 0
    while pos < len(data):
        n = int.from_bytes(data[pos:pos + 4], 'big')
        t = data[pos + 4:pos + 8]
        c = data[pos + 8:pos + 8 + n]
        if t == b'IHDR':
            w, h = int.from_bytes(c[:4], 'big'), int.from_bytes(c[4:8], 'big')
        elif t == b'IDAT':
            idat += c
        pos += 12 + n
    raw = zlib.decompress(idat)
    return [[tuple(raw[y * (w * 3 + 1) + 1 + x * 3:y * (w * 3 + 1) + 4 + x * 3]) for x in range(w)]
            for y in range(h)]


y = Yape(os.path.join(ROOT, 'build', 'stardew.d64'), warp=True, series=12)
bad = 0
try:
    for t in range(90):
        y.run_for(1)
        scr = y.mem(0xD400 + 14 * 40 + 15, 1)[0]
        if y.mem(lab['_menu'], 1)[0] == 1 and scr == 14:
            break
    y.poke(lab['_dbg_keys'], [16])
    y.run_for(0.3)
    y.poke(lab['_dbg_keys'], [0])
    for name, room, x0, y0, fl in (('house', 'HOUSE', 5, 4, 0), ('farm', 'FARM_E', 10, 5, 0),
                                   ('mine', 'MINE_A', 9, 9, 23)):
        y.run_for(3)
        y.poke(lab['_dbg_floor'], [fl])
        y.poke(lab['_dbg_x'], [x0])
        y.poke(lab['_dbg_y'], [y0])
        y.poke(lab['_dbg_goto'], [int(d['R_' + room]) + 1])
        y.run_for(8)
        y.poke(lab['_dbg_keys'], [4])
        pics = y.png_series(os.path.join(OUT, 'yape_%s_' % name))
        y.poke(lab['_dbg_keys'], [0])
        for f in pics:
            p = read_png(f)
            # the separator: row 22 is lines 179-186, in the picture +36
            # (Yape's picture has 4 more lines at the top than the TED's count)
            rows = None
            for top in range(200, 240):
                if all(p[top + k][100] == p[top][100] for k in range(8)) and \
                        len({p[top + k][x] for k in range(8) for x in range(32, 352)}) == 1:
                    rows = top
                    break
            if rows is None:
                print('%s: no black row found' % f)
                bad += 1
                continue
            first = {p[rows + 8][x] for x in range(32, 352)}
            above = {p[rows - 1][x] for x in range(32, 352)}
            print('%s: separator at %d, toolbar line %d colours %d' % (
                os.path.basename(f), rows, rows + 8, len(first)))
    sys.exit(1 if bad else 0)
finally:
    y.stop()
