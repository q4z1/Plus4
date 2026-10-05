#!/usr/bin/env python3
"""p4emu_fire.py - fire's states in plus4emu, as the original's ($31B9):
1. fire alone: a wait of 8 ticks, then transfer mode;
2. fire with a direction at once: the weapon, it shoots and drives;
3. fire alone, a direction within the wait: the weapon; the direction let
   go with fire still held stays the weapon (no transfer mode), another
   direction shoots that way;
4. fire let go: none of them."""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from p4emu import P4emu
HERE = os.path.dirname(os.path.abspath(__file__))
lbl = {}
for l in open(os.path.join(HERE, '..', 'build', 'paradroid.lbl')):
    p = l.split()
    lbl[p[2].lstrip('.')] = int(p[1], 16)
TICK = 3 / 50


def word(e, name):
    a = e.mem(lbl[name], 2)
    return a[0] | a[1] << 8


def state(e):
    return e.mem(lbl['fstate'], 1)[0], e.mem(lbl['_transfer_mode'], 1)[0]


def shots(e):
    return sum(1 for v in e.mem(lbl['_s_life'], 8) if v)


e = P4emu(os.path.join(HERE, '..', 'build', 'paradroid.prg'))
ok = True


def check(what, cond):
    global ok
    print('%-60s %s' % (what, 'ok' if cond else 'FAILED'), flush=True)
    ok &= bool(cond)


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
    e.poke(lbl['_nd'], [1])                 # no droids: nothing in the way
    e.run_for(0.5)
    check('none at the start', state(e) == (0x80, 0))
    # 1.
    e.poke(lbl['_dbg_keys'], [16])
    n = 0
    while state(e)[0] != 2 and n < 20:
        e.frame()
        n += 1
    t = 0
    while state(e) == (2, 0) and t < 60:
        e.frame()
        t += 1
    # (the frames from the wait's first tick on: 8 ticks of 3)
    check('fire alone: the wait for %d frames, then transfer mode' % t,
          22 <= t <= 24 and state(e) == (0, 1))
    e.poke(lbl['_dbg_keys'], [0])
    e.run_for(3 * TICK)
    check('let go: none', state(e) == (0x80, 0))
    e.run_for(1)
    # 2.
    x0 = word(e, '_d_x')
    e.poke(lbl['_dbg_keys'], [16 | 8])
    n = 0
    for i in range(10):
        e.run_for(TICK)
        n = max(n, shots(e))
    x1 = word(e, '_d_x')
    check('fire right at once: the weapon (state %d), %d shots, x %d -> %d'
          % (state(e)[0], n, x0, x1), state(e)[0] == 1 and n and x1 > x0)
    e.poke(lbl['_dbg_keys'], [0])
    e.run_for(1.5)
    # 3.
    e.poke(lbl['_dbg_keys'], [16])
    e.run_for(4 * TICK)
    e.poke(lbl['_dbg_keys'], [16 | 2])
    e.run_for(2 * TICK)
    check('a direction in the wait: the weapon', state(e) == (1, 0))
    e.poke(lbl['_dbg_keys'], [16])
    e.run_for(1.0)
    check('fire still held, no direction, a second: still the weapon',
          state(e) == (1, 0))
    e.run_for(0.5)
    n = 0
    e.poke(lbl['_dbg_keys'], [16 | 4])
    for i in range(10):
        e.run_for(TICK)
        n = max(n, shots(e))
    check('then left: shots (%d)' % n, n)
    # 4.
    e.poke(lbl['_dbg_keys'], [0])
    e.run_for(3 * TICK)
    check('let go: none', state(e) == (0x80, 0))
finally:
    e.stop()
print('ok' if ok else 'FAILED')
