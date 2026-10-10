#!/usr/bin/env python3
"""p4emu_hud.py - the toolbar must not flicker: in the mine, swinging the
sword again and again (every blow writes the toolbar's status), the
toolbar's two lines are compared picture by picture. A picture that
differs from the one before while the next is like the one before again
is a flicker: the line was cleared and written again, and the beam caught
it in between (bars for health and energy, reported). Fails on any."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p4emu_snow as S
from p4emu import ROOT

e = S.boot()
try:
    S.goto(e, 'MINE_A', 9, 9, floor=3)
    e.set('sel', 4)                     # the sword
    e.frame(20)
    seen = []
    for i in range(60):
        e.set('dbg_keys', S.K['fire'] if i % 2 == 0 else 0)
        for f in range(6):
            e.frame()
            p = e.pixels()
            # rows 23 and 24: the picture's lines 43 + 184 on
            seen.append(tuple(tuple(p[y][32:352]) for y in range(43 + 184, 43 + 200)))
    bad = [k for k in range(1, len(seen) - 1)
           if seen[k] != seen[k - 1] and seen[k + 1] == seen[k - 1]]
    for k in bad[:10]:
        print('picture %d: the toolbar for one picture only' % k)
    print('%d pictures, %d flickers' % (len(seen), len(bad)))
    sys.exit(1 if bad else 0)
finally:
    e.stop()
