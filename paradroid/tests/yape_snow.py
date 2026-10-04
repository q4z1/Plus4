#!/usr/bin/env python3
"""yape_snow.py [frames] [label ...] - the window's bottom edge in Yape, in
a game standing still: n pictures in a row, and in each the pixels of its
last lines and the border under it that are neither the line's own
colours nor the border's (a register written while the TED draws them).
With labels: those routines return at once (an RTS poked over their
first byte), to find which write it is."""
import os, sys
from collections import Counter
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.expanduser('~/.cache/paradroid/work/py'))
from yape import Yape
from png import read_png
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.expanduser('~/.cache/paradroid/test')
args = sys.argv[1:]
n = int(args.pop(0)) if args and args[0].isdigit() else 50
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
    y.poke(lbl['_dbg_god'], [1])
    y.poke(lbl['_dbg_keys'], [16])
    y.run_for(1)
    y.poke(lbl['_dbg_keys'], [0])
    y.run_for(6)                    # the start page, the beam, then play
    y.poke(lbl['_nd'], [1])         # (no droids passing)
    for name in args:
        y.poke(lbl[name], [0x60])
    y.run_for(0.5)
    shots = y.png_series(os.path.join(OUT, 'yape_snow_'))
finally:
    y.stop()

# the window's last lines and the border's first: a pixel whose colour
# shows in no other picture at that place is snow
frames = [read_png(f)[2] for f in shots]
bad = 0
for k, pix in enumerate(frames):
    hits = []
    for yy in range(232, 248):
        for x in range(32, 352):
            c = pix[yy][x][:3]
            if sum(1 for f in frames if f[yy][x][:3] == c) <= len(frames) // 4:
                hits.append((x, yy, c))
    if hits:
        bad += 1
        if bad <= 8:
            print('%3d: %s' % (k, hits[:4]))
print('%d of %d pictures with snow at the bottom edge' % (bad, len(frames)))
