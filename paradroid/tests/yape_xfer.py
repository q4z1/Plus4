#!/usr/bin/env python3
"""yape_xfer.py [transfers] - in Yape (warp): the title, a game, then
transfers started by putting a droid on the player in transfer mode;
their droids' pictures load from the disk with the fast loader. A
screenshot of each introduction (~/.cache/paradroid/test/yape_xfer_N.png);
fails if the game stops ticking."""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from yape import Yape
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.expanduser('~/.cache/paradroid/test')
n = int(sys.argv[1]) if len(sys.argv) > 1 else 3
lbl = {}
for l in open(os.path.join(HERE, '..', 'build', 'paradroid.lbl')):
    p = l.split()
    lbl[p[2].lstrip('.')] = int(p[1], 16)

y = Yape(os.path.join(HERE, '..', 'build', 'paradroid.d64'), warp=True)
try:
    for t in range(60):
        y.run_for(1)
        if y.mem(lbl['_font_hi'], 1)[0] == 0xD8:
            break
    y.run_for(2)
    y.poke(lbl['_dbg_god'], [1])
    y.poke(lbl['_dbg_keys'], [16])
    y.run_for(1)
    y.poke(lbl['_dbg_keys'], [0])
    y.run_for(2)
    print('kind', y.mem(lbl['_fl_kind'], 1)[0])
    for k in range(n):
        y.poke(lbl['_dbg_keys'], [16])          # transfer mode
        y.run_for(1)
        nd = y.mem(lbl['_nd'], 1)[0]
        boom = y.mem(lbl['_d_boom'], nd)
        live = [i for i in range(1, nd) if boom[i] == 0]
        if not live:
            break
        i = live[0]
        y.poke(lbl['_d_x'] + 2 * i, y.mem(lbl['_d_x'], 2))
        y.poke(lbl['_d_y'] + 2 * i, y.mem(lbl['_d_y'], 2))
        y.run_for(2)
        y.png(os.path.join(OUT, 'yape_xfer_%d.png' % k))
        t0 = y.mem(lbl['_tick'], 1)[0]
        y.poke(lbl['_dbg_keys'], [0])
        y.run_for(8)                              # the transfer game runs out
        print('transfer %d: kind %d, ticking %s' % (k, y.mem(lbl['_fl_kind'], 1)[0],
              y.mem(lbl['_tick'], 1)[0] != t0), flush=True)
finally:
    y.stop()
