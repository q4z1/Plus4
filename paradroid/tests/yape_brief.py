#!/usr/bin/env python3
"""yape_brief.py [frames] - the briefing scrolling in Yape, frame by frame:
the pictures (~/.cache/paradroid/test/yape_brief_NNN.png) and, for each,
how far the window's text moved since the frame before (by matching its
lines), and the lines of the window that match nothing of the frame
before"""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.expanduser('~/.cache/paradroid/work/py'))
from yape import Yape
from png import read_png
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.expanduser('~/.cache/paradroid/test')
n = int(sys.argv[1]) if len(sys.argv) > 1 else 50
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
    y.run_for(1.5)
    shots = y.png_series(os.path.join(OUT, 'yape_brief_'))
finally:
    y.stop()

# the window: screen rows 9..24 at 41 + 8 * row in the picture, columns 2..37
TOP, BOT = 41 + 8 * 9, 41 + 8 * 25
prev = None
for k, f in enumerate(shots):
    w, h, pix = read_png(f)
    rows = [tuple(pix[yy][48:336]) for yy in range(TOP, BOT)]
    if prev is not None:
        # the shift: most window lines found that many lines higher before
        best = None
        for d in range(-3, 9):
            hits = sum(1 for i in range(len(rows)) if 0 <= i + d < len(prev) and rows[i] == prev[i + d])
            if best is None or hits > best[1]:
                best = (d, hits)
        d = best[0]
        odd = [i for i in range(len(rows)) if not (0 <= i + d < len(prev) and rows[i] == prev[i + d])
               and len(set(rows[i])) > 1]
        print('%3d moved %+d  unmatched lines %s' % (k, d, odd[:12]))
    prev = rows
