#!/usr/bin/env python3
"""p4emu_vscroll.py [pictures] - in a game in plus4emu, driving up and
down: in every picture the border beside the window, which must be the
border's colour above it, and the window's most common colour, by the
fine scroll s. With an odd s the TED's PAL phase went wrong under the
gap, and the window's colours with it (engine.s, set_s); on the real
Plus/4 and in plus4emu they flickered, VICE and Yape do not show it.
Pictures with the border wrong go to ~/.cache/paradroid/test/p4v_<n>.png."""
import os, sys, collections
sys.path.insert(0, os.path.dirname(__file__))
from p4emu import P4emu
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.expanduser('~/.cache/paradroid/test')
n = int(sys.argv[1]) if len(sys.argv) > 1 else 200
lbl = {}
for l in open(os.path.join(HERE, '..', 'build', 'paradroid.lbl')):
    p = l.split()
    lbl[p[2].lstrip('.')] = int(p[1], 16)
e = P4emu(os.path.join(HERE, '..', 'build', 'paradroid.prg'))
try:
    for t in range(40):
        e.run_for(1)
        if e.mem(lbl['_font_hi'], 1)[0] == 0xD8:
            break
    e.run_for(2)
    e.poke(lbl['_dbg_god'], [1])
    e.poke(lbl['_dbg_keys'], [16])
    e.run_for(1)
    e.poke(lbl['_dbg_keys'], [0])
    e.run_for(3)
    seen = collections.Counter()
    for i in range(n):
        e.poke(lbl['_dbg_keys'], [1 if (i // 40) % 2 else 2])
        front = e.mem(lbl['front'], 1)[0]       # (the next picture's: swapped at line 203)
        s = e.mem(lbl['b_s'] + front, 1)[0] + e.mem(lbl['b_yo'] + front, 1)[0] - 3
        e.frame()
        pix = e.pixels()
        side = pix[150][10]
        top = pix[20][10]
        win = collections.Counter(pix[y][x] for y in range(115, 240, 3) for x in range(48, 340, 3))
        key = (top, side, win.most_common(1)[0][0])
        seen[key, s & 1] += 1
        if side != top:
            print('picture %d: border top %s, beside %s, window %s, s=%d' % (
                i, top, side, key[2], s), flush=True)
            e.png(os.path.join(OUT, 'p4v_%d.png' % i))
    for (k, odd), v in seen.most_common():
        print('%3d pictures, s %s: %s' % (v, 'odd ' if odd else 'even', k))
finally:
    e.stop()
