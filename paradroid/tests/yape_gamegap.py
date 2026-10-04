#!/usr/bin/env python3
"""yape_gamegap.py [pictures] - in a game in Yape, driving up and down
(every vertical fine position, the deck drawn anew): in each picture the
gap between the panel and the window, which must show nothing but its
colour, and the window's top at its right end, which must not move. The
window's top row is shown twice by the TED, first in the gap in the other
picture's character set, where its copies are blank (engine.s)."""
import os, sys, collections, random
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.expanduser('~/.cache/paradroid/work/py'))
from yape import Yape
from png import read_png
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.expanduser('~/.cache/paradroid/test')
n = int(sys.argv[1]) if len(sys.argv) > 1 else 150
lbl = {}
for l in open(os.path.join(HERE, '..', 'build', 'paradroid.lbl')):
    p = l.split()
    lbl[p[2].lstrip('.')] = int(p[1], 16)
y = Yape(os.path.join(HERE, '..', 'build', 'paradroid.prg'), warp=True)
tops = collections.Counter()
bad = 0
try:
    for t in range(40):
        y.run_for(1)
        if y.mem(lbl['_font_hi'], 1)[0] == 0xD8:
            break
    y.run_for(2)
    y.poke(lbl['_dbg_god'], [1])
    y.poke(lbl['_dbg_keys'], [16])
    y.run_for(1)
    y.poke(lbl['_dbg_keys'], [0])
    y.run_for(3)
    rnd = random.Random(2)
    for i in range(n):
        if i % 6 == 0:
            y.poke(lbl['_dbg_keys'], [rnd.choice([1, 2, 1, 2, 5, 6, 9, 10])])
        y.run_for(0.07)
        f = y.png(os.path.join(OUT, 'ygg.png'))
        w, h, pix = read_png(f)
        x = w // 2
        top = max(v for v in range(100) if min(pix[v][x]) > 240) + 1  # the panel's frame
        gap = pix[top + 2][x]
        xr = 32 + 8 * 39 - 1
        edge = next((v for v in range(top, top + 60) if pix[v][xr] != gap), -1)
        dirt = [(v, xx) for v in range(top, edge) for xx in range(40, 344) if pix[v][xx] != gap]
        tops[edge] += 1
        if dirt:
            bad += 1
            print('picture %d: %d pixels in the gap, first at %s' % (i, len(dirt), dirt[0]), flush=True)
            os.replace(f, os.path.join(OUT, 'ygg_%d.png' % i))
    print('window top (right end):', dict(tops), '| pictures with something in the gap:', bad)
finally:
    y.stop()
