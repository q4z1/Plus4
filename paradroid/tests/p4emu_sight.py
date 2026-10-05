#!/usr/bin/env python3
"""p4emu_sight.py - which droids the player sees, as the original's $24AE
(sight.s), on deck 4 (the first deck plus4emu's start gives): a droid in
the player's room is seen, one in the room beside it, behind a wall, is
not; one behind a closed door is not, and is once the door is open (a
droid beside it opens it)."""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from p4emu import P4emu
HERE = os.path.dirname(os.path.abspath(__file__))
lbl = {}
for l in open(os.path.join(HERE, '..', 'build', 'paradroid.lbl')):
    p = l.split()
    lbl[p[2].lstrip('.')] = int(p[1], 16)
e = P4emu(os.path.join(HERE, '..', 'build', 'paradroid.prg'))
ok = True


def keys(v, t):
    e.poke(lbl['_dbg_keys'], [v])
    e.run_for(t)


def put(i, bx, by):
    x, y = bx * 32 + 16, by * 32 + 16
    e.poke(lbl['_d_x'] + 2 * i, [x & 255, x >> 8])
    e.poke(lbl['_d_y'] + 2 * i, [y & 255, y >> 8])
    e.poke(lbl['_d_vx'] + i, [0])
    e.poke(lbl['_d_vy'] + i, [0])


try:
    for t in range(300):
        e.run_for(0.1)
        if e.mem(lbl['_panel_hi'], 1)[0] == 0xD8:
            break
    e.run_for(1); keys(16, 0.2); keys(0, 0.3)
    for t in range(40):
        e.run_for(0.5)
        if e.mem(lbl['_font_hi'], 1)[0] == 0xD8:
            break
    e.run_for(9)
    e.poke(lbl['_dbg_god'], [1])
    assert e.mem(lbl['_deck'], 1)[0] == 4, 'not deck 4'
    nd = e.mem(lbl['_nd'], 1)[0]
    for name, player, droid, want in (
            ('same room', (10, 6), (12, 7), 1),
            ('behind a wall', (10, 6), (6, 6), 0),
            ('behind a closed door', (17, 5), (21, 5), 0),
            ('its door opened', (17, 5), (20, 5), 1)):
        for t in range(12):
            put(0, *player)
            for i in range(1, nd):          # droid 1 there, the others far
                put(i, *(droid if i == 1 else (40, 2)))
                e.poke(lbl['_d_wait'] + i, [60])
            e.run_for(0.1)
        e.run_for(0.5)
        seen = e.mem(lbl['_d_seen'] + 1, 1)[0]
        print('%-22s seen %d %s' % (name, seen, 'ok' if seen == want else 'FAILED'), flush=True)
        ok &= seen == want
finally:
    e.stop()
print('ok' if ok else 'FAILED')
