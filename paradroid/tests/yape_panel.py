#!/usr/bin/env python3
"""yape_panel.py [frames] [title|down] - the status panel at the top in
Yape, frame by frame: in a game, driving right or down (or on the title
with "title"), n pictures in a
row (~/.cache/paradroid/test/yape_panel_NNN.png), and each one's lines of
the panel that differ from what most pictures show there"""
import os, sys
from collections import Counter
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.expanduser('~/.cache/paradroid/work/py'))
from yape import Yape
from png import read_png
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.expanduser('~/.cache/paradroid/test')
n = int(sys.argv[1]) if len(sys.argv) > 1 else 100
title = 'title' in sys.argv
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
    y.run_for(2)
    if not title:
        y.poke(lbl['_dbg_god'], [1])
        y.poke(lbl['_dbg_keys'], [16])
        y.run_for(1)
        y.poke(lbl['_dbg_keys'], [2 if 'down' in sys.argv else 8])  # the window scrolls
        y.run_for(2)
    shots = y.png_series(os.path.join(OUT, 'yape_panel_'))
finally:
    y.stop()

# the panel: screen rows 0..5, lines 41..88 of the picture, the whole width
TOP, BOT = 30, 41 + 8 * 6
frames = []
for f in shots:
    w, h, pix = read_png(f)
    frames.append([tuple(pix[yy]) for yy in range(TOP, BOT)])
common = [Counter(fr[i] for fr in frames).most_common(1)[0][0] for i in range(BOT - TOP)]
bad = 0
for k, fr in enumerate(frames):
    diff = [TOP + i for i in range(BOT - TOP) if fr[i] != common[i]]
    if diff:
        bad += 1
        print('%3d: lines %s' % (k, diff[:16] if len(diff) <= 16 else '%d lines, %d..%d' % (len(diff), diff[0], diff[-1])))
print('%d of %d pictures differ in the panel' % (bad, len(frames)))
