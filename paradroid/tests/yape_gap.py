#!/usr/bin/env python3
"""yape_gap.py [frames] - the gap between the status panel and the window
on the title (the briefing) in Yape, frame by frame: n pictures in a row
(~/.cache/paradroid/test/yape_gap_NNN.png), and in each the lines of the
gap with anything but the gap's colour in them, and where"""
import os, sys
from collections import Counter
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.expanduser('~/.cache/paradroid/work/py'))
from yape import Yape
from png import read_png
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.expanduser('~/.cache/paradroid/test')
n = int(sys.argv[1]) if len(sys.argv) > 1 else 300
lbl = {}
for l in open(os.path.join(HERE, '..', 'build', 'paradroid.lbl')):
    p = l.split()
    lbl[p[2].lstrip('.')] = int(p[1], 16)

y = Yape(os.path.join(HERE, '..', 'build', 'paradroid.prg'), warp=True, series=n)
try:
    for t in range(60):
        y.run_for(1)
        if y.mem(lbl['_font_hi'], 1)[0] == 0xD8:
            break
    y.run_for(1)
    shots = y.png_series(os.path.join(OUT, 'yape_gap_'))
finally:
    y.stop()

# the gap: screen rows 6..8 (the window from row 9), the screen's columns;
# its last two lines have the window's colour already (engine.s)
TOP, BOT = 41 + 8 * 6, 41 + 8 * 9 - 2
bad = 0
for k, f in enumerate(shots):
    w, h, pix = read_png(f)
    bg = Counter(pix[yy][x] for yy in range(TOP, BOT) for x in range(32, 352)).most_common(1)[0][0]
    hits = []
    for yy in range(TOP, BOT):
        xs = [x for x in range(32, 352) if pix[yy][x] != bg]
        if xs:
            hits.append('line %d (row %d.%d) x %d..%d, %d pixels' % (yy, (yy - 41) // 8, (yy - 41) % 8,
                                                                xs[0], xs[-1], len(xs)))
    if hits:
        bad += 1
        print('%3d: %s' % (k, '; '.join(hits[:3])))
print('%d of %d pictures with something in the gap' % (bad, len(shots)))
