#!/usr/bin/env python3
"""yape_start.py [logo] - a game's start in Yape, as the original's: fire on
the title (with "logo": on its logo), then 400 pictures in a row, 8 seconds
(~/.cache/paradroid/test/yape_start_NNN.png): the start page ("Game on!",
the unit), the deck with the player flashing as it is beamed in, then
"Mobile". Prints where the window changes from one to the next."""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.expanduser('~/.cache/paradroid/work/py'))
from yape import Yape
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.expanduser('~/.cache/paradroid/test')
lbl = {}
for l in open(os.path.join(HERE, '..', 'build', 'paradroid.lbl')):
    p = l.split()
    lbl[p[2].lstrip('.')] = int(p[1], 16)

y = Yape(os.path.join(HERE, '..', 'build', 'paradroid.d64'), warp=True, series=400)
try:
    for t in range(300):
        y.run_for(0.2 if 'logo' in sys.argv else 1)
        if y.mem(lbl['_panel_hi' if 'logo' in sys.argv else '_font_hi'], 1)[0] == 0xD8:
            break
    if 'logo' not in sys.argv:
        y.run_for(2)
    y.poke(lbl['_dbg_keys'], [16])
    y.run_for(0.2)
    y.poke(lbl['_dbg_keys'], [0])
    shots = y.png_series(os.path.join(OUT, 'yape_start_'))
finally:
    y.stop()

# the window's middle and the panel's text, each picture against the one
# before: where the page, the deck, the flashing and the panel change
from png import read_png
last = None
for k, f in enumerate(shots):
    w, h, pix = read_png(f)
    now = (tuple(pix[y][x] for y in range(110, 240, 4) for x in range(40, 344, 4)),
           tuple(pix[y][x] for y in range(56, 72, 2) for x in range(40, 140, 2)))
    if last and now != last:
        print('%3d (%.2f s): %s' % (k, k / 50, ' and '.join(
            n for n, a, b in zip(('window', 'panel'), now, last) if a != b)))
    last = now
