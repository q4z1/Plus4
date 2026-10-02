#!/usr/bin/env python3
"""loadtime.py [drive] - how long the title takes to load in VICE, in
pictures (50 a second), from fl_load()'s start to its return: the
player is made to die, and after the game the title is loaded again.
drive: 1541 or 1551 (the default)."""
import os, re, sys
sys.path.insert(0, os.path.dirname(__file__))
from game import Game
drive = int(sys.argv[1]) if len(sys.argv) > 1 else 1551
g = Game(drive=drive, warp=True)
v = g.v
def go():
    """run to the next breakpoint"""
    v.settle = 1.0
    out = v.cmd('x')
    v.settle = 0.02
    return out
try:
    g.start_play()
    print('kind', g.byte('_fl_kind'))
    g.poke('_dbg_god', 0)
    g.poke('_player_dead', 1)
    g.poke('_d_boom', 1)
    def clock():
        r = v.cmd('r')
        return int(r.strip().splitlines()[-2].split()[-1])
    for k in range(3):                  # pictures first, then the title
        v.cmd('break %04x' % g.lbl['_fl_load'])
        go()
        c0 = clock()
        regs = v.cmd('r')
        sp = int(re.search(r'\.;[0-9a-f]{4} (?:[0-9a-f]{2} ){3}([0-9a-f]{2})', regs).group(1), 16)
        lo, hi = v.mem(0x0100 + sp + 1, 2)
        v.cmd('delete')
        v.cmd('break %04x' % ((lo | hi << 8) + 1))
        go()
        c1 = clock()
        m = re.search(r'\.;[0-9a-f]{4} ([0-9a-f]{2}) ([0-9a-f]{2})', v.cmd('r'))
        v.cmd('delete')
        size = int(m.group(1), 16) | int(m.group(2), 16) << 8
        t = (c1 - c0) / 1773447.0       # (VICE's clock: the TED's double clock, PAL)
        print('%5d bytes: %.2f s, %.0f bytes a second' % (size, t, size / t), flush=True)
        if size > 4000:
            break
finally:
    g.stop()
