#!/usr/bin/env python3
"""edges.py - the window's top edge for every fine position: the player is
moved down a line at a time (by poking its position), and each picture is
checked: the gap colour must end exactly at the window's first line."""
import os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.expanduser('~/.cache/paradroid/work/py'))
from vice import Vice
from game import Game
from png import read_png
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
work = os.path.expanduser('~/.cache/paradroid/test')
prg = os.path.join(work, 'paradroid.prg')
open(prg, 'wb').write(open(os.path.join(ROOT, 'build', 'paradroid.prg'), 'rb').read())
lbl = {}
for l in open(os.path.join(ROOT, 'build', 'paradroid.lbl')):
    p = l.split(); lbl[p[2].lstrip('.')] = int(p[1], 16)
g = Game(warp=False)
v = g.v
try:
    g.start_play()
    y0 = v.mem(lbl['_d_y'], 2)
    py = y0[0] | y0[1] << 8
    for k in range(9):
        y = py + k
        v.poke(lbl['_d_y'], [y & 255, y >> 8])
        v.run_for(0.3)
        f = os.path.join(work, 'e%d.png' % k)
        v.screenshot(f)
        w, h, px = read_png(f)
        gap = px[100][200]
        rows = []
        for yy in range(98, 110):
            n = sum(1 for x in range(48, 340) if px[yy][x] == gap)
            rows.append('%d:%d' % (yy, n))
        bottom = []
        for yy in range(234, 244):
            n = sum(1 for x in range(48, 340) if px[yy][x] == px[260][200])
            bottom.append('%d:%d' % (yy, n))
        print('y=%d' % y, ' '.join(rows), '| bottom', ' '.join(bottom))
finally:
    v.stop()
