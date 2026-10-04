#!/usr/bin/env python3
"""yape_top.py [pictures] - the window's top line in Yape: on the title,
the briefing rolling up (every vertical fine position), a picture at a
time; for each fine position the screen line its colour starts on. It
must be the same for all: the window's colour is set exactly at its first
line, where the TED may stop the processor (engine.s, irq_bg)."""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.expanduser('~/.cache/paradroid/work/py'))
from yape import Yape
from png import read_png
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.expanduser('~/.cache/paradroid/test')
n = int(sys.argv[1]) if len(sys.argv) > 1 else 80
lbl = {}
for l in open(os.path.join(HERE, '..', 'build', 'paradroid.lbl')):
    p = l.split()
    lbl[p[2].lstrip('.')] = int(p[1], 16)
y = Yape(os.path.join(HERE, '..', 'build', 'paradroid.prg'), warp=True)
tops = {}
try:
    for t in range(80):                 # till the briefing rolls: its colours
        y.run_for(0.5)
        if y.mem(lbl['_col_deck'], 1)[0] in (0x77, 0x5B, 0x7F):
            break
    for i in range(n):
        y.run_for(0.05)
        f = y.png(os.path.join(OUT, 'ytop.png'))
        w, h, pix = read_png(f)
        front = y.mem(lbl['front'], 1)[0]
        s = y.mem(lbl['b_s'], 2)[front]
        x = w // 2
        # down from the panel's frame (white) through the gap to the window
        ys = [yy for yy in range(h) if min(pix[yy][x]) > 240]
        if not ys:
            continue
        yy = max(v for v in ys if v < h // 2) + 1
        gap = pix[yy + 2][x]
        while yy < h and all(pix[yy][xx] == gap for xx in range(w // 4, 3 * w // 4)):
            yy += 1
        tops.setdefault(s, []).append(yy)
        if os.environ.get('YTOP_FILL'):         # the window's edge at its right
            r = y.mem(lbl['yy'], 2)             # end (no text there), and
            xr = 32 + 8 * 39 - 1                # anything but the gap's colour
            edge = next((v for v in range(yy - 20, yy + 30) if pix[v][xr] != gap), -1)
            dirt = sum(1 for v in range(edge - 10, edge) for xx in range(40, 344)
                       if pix[v][xx] != gap)
            print('fill roll %d s %d edge %d gap-dirt %d' % (r[0] | r[1] << 8, s, edge, dirt))
            if edge != 112 and os.environ.get('YTOP_ODD'):
                import shutil
                shutil.copy(f, os.path.join(OUT, 'yodd_%d_%d.png' % (i, edge)))
        if os.environ.get('YTOP_KEEP') and yy == int(os.environ['YTOP_KEEP']):
            os.replace(f, os.path.join(OUT, 'ytop_%d_%d.png' % (yy, i)))
    for s in sorted(tops):              # (a page being built: no window)
        t = [v for v in tops[s] if v < 130]
        print('s=%d: window from line %s' % (s, ', '.join(
            '%d (%dx)' % (v, t.count(v)) for v in sorted(set(t)))))
finally:
    y.stop()
