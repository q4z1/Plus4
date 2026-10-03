#!/usr/bin/env python3
"""yape_title.py - the title's scores page in Yape, at its start: the
day's scores and the droid's picture beside them
(~/.cache/paradroid/test/yape_scores.png)"""
import os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.expanduser('~/.cache/paradroid/work/py'))
from yape import Yape
from png import read_png
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.expanduser('~/.cache/paradroid/test')
y = Yape(os.path.join(HERE, '..', 'build', 'paradroid.d64'), warp=True)
try:
    f = os.path.join(OUT, 'yape_scores.png')
    t0 = time.time()
    while time.time() - t0 < 120:
        y.png(f)
        w, h, pix = read_png(f)
        line = [pix[130][x] for x in range(48, 336)]
        # the page white, and something not white at the left (the picture)
        if line.count((250, 250, 250)) > 150 and any(p != (250, 250, 250) for p in line[:60]):
            print('scores page', f)
            break
        y.run_for(0.2)
    else:
        print('not found')
finally:
    y.stop()
