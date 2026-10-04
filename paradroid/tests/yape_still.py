#!/usr/bin/env python3
"""yape_still.py [pictures] - in a game in Yape, the player standing still:
n pictures, each one's content (the lines under the panel, how many
pixels in each differ from the gap's colour) fitted to the first one's.
All must fit unshifted: a picture a line out means the interrupt that
moves the rows (engine.s, irq_scroll) or the one for the window's colour
(irq_bg) missed its moment."""
import os, sys, collections
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.expanduser('~/.cache/paradroid/work/py'))
from yape import Yape
from png import read_png
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.expanduser('~/.cache/paradroid/test')
n = int(sys.argv[1]) if len(sys.argv) > 1 else 40
lbl = {}
for l in open(os.path.join(HERE, '..', 'build', 'paradroid.lbl')):
    p = l.split()
    lbl[p[2].lstrip('.')] = int(p[1], 16)
y = Yape(os.path.join(HERE, '..', 'build', 'paradroid.prg'), warp=True)
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
    if os.environ.get('STILL_EMPTY'):
        y.poke(lbl['_nd'], [1])             # no droids: nothing else moves
    else:                                   # the droids far off, busy
        for k in range(1, y.mem(lbl['_nd'], 1)[0]):
            y.poke(lbl['_d_x'] + 2 * k, [0, 0])
            y.poke(lbl['_d_y'] + 2 * k, [0, 0])
    y.run_for(1)
    a = y.mem(lbl['_d_y'], 2)
    py0 = a[0] | a[1] << 8
    for t in range(8):                      # every fine position
        py = py0 + t
        y.poke(lbl['_d_y'], [py & 255, py >> 8])
        y.run_for(0.5)
        s = y.mem(lbl['b_s'], 2)[y.mem(lbl['front'], 1)[0]]
        ref = None
        seen = collections.Counter()
        for i in range(n):
            y.run_for(0.03)
            w, h, pix = read_png(y.png(os.path.join(OUT, 'ystill.png')))
            # each line from the panel's frame down: how many pixels
            # differ from the gap's colour, a profile of the content
            x = w // 2
            top = max(v for v in range(100) if min(pix[v][x]) > 240) + 1
            gap = pix[top + 2][x]
            prof = [sum(1 for xx in range(16, w - 16) if pix[v][xx] != gap)
                    for v in range(top, top + 150)]
            if ref is None:
                ref = prof
            # the shift that fits it best to the first picture's
            best = min(range(-3, 4), key=lambda d: sum(
                abs(prof[v + d] - ref[v]) for v in range(5, 140)))
            seen[best] += 1
        print('s=%d: shifts against the first picture %s' % (s, dict(seen)), flush=True)
finally:
    y.stop()
