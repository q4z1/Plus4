#!/usr/bin/env python3
"""p4emu_tmode.py - transfer mode in plus4emu: fire held without a
direction, then with one. The player must drive (its x and y change) and
not shoot (no shot of the player's in the shots' table)."""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from p4emu import P4emu
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.expanduser('~/.cache/paradroid/test')
lbl = {}
for l in open(os.path.join(HERE, '..', 'build', 'paradroid.lbl')):
    p = l.split()
    lbl[p[2].lstrip('.')] = int(p[1], 16)


def word(e, name):
    a = e.mem(lbl[name], 2)
    return a[0] | a[1] << 8


e = P4emu(os.path.join(HERE, '..', 'build', 'paradroid.prg'))
ok = True
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
    e.run_for(8)
    e.poke(lbl['_nd'], [1])                 # no droids: no transfer
    e.poke(lbl['_dbg_keys'], [16])
    e.run_for(0.5)
    print('transfer mode', e.mem(lbl['_transfer_mode'], 1)[0])
    for k, name in ((16 | 2, 'down'), (16 | 8, 'right'), (16 | 1, 'up'), (16 | 4, 'left')):
        x0, y0 = word(e, '_d_x'), word(e, '_d_y')
        e.poke(lbl['_dbg_keys'], [k])
        shots = 0
        for i in range(10):
            e.run_for(0.06)
            shots += sum(1 for v in e.mem(lbl['_s_life'], 8) if v)
        x1, y1 = word(e, '_d_x'), word(e, '_d_y')
        print('fire+%-5s: x %d -> %d, y %d -> %d, transfer mode %d, shots %d' % (
            name, x0, x1, y0, y1, e.mem(lbl['_transfer_mode'], 1)[0], shots), flush=True)
        ok &= (x1, y1) != (x0, y0) and not shots
    e.png(os.path.join(OUT, 'tmode.png'))
    e.poke(lbl['_dbg_keys'], [0])
    e.run_for(0.3)
    print('let go: transfer mode', e.mem(lbl['_transfer_mode'], 1)[0])
finally:
    e.stop()
print('ok' if ok else 'FAILED: in transfer mode the player must drive and not shoot')
