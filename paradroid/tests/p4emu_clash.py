#!/usr/bin/env python3
"""p4emu_clash.py - things meeting, as the original's ($19EA): only when
just two of them touch does anything happen. Measured in x64sc first
(~/.cache/paradroid/work/chain.py, touch.py); here the same rows of 123s,
right of the player on an open stretch of floor, held still:
1. one droid 48 on: the laser kills it;
2. two droids 16 apart, touching: the laser does nothing to them;
3. one droid moved into the first's explosion: it dies;
4. two droids moved into it, touching each other: three things touch,
   nothing happens while it lasts."""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from p4emu import P4emu
HERE = os.path.dirname(os.path.abspath(__file__))
lbl = {}
for l in open(os.path.join(HERE, '..', 'build', 'paradroid.lbl')):
    p = l.split()
    lbl[p[2].lstrip('.')] = int(p[1], 16)
TICK = 3 / 50
MAXD = 13
BOOM_GONE = 13

e = P4emu(os.path.join(HERE, '..', 'build', 'paradroid.prg'))
ok = True


def check(what, cond):
    global ok
    print('%-64s %s' % (what, 'ok' if cond else 'FAILED'), flush=True)
    ok &= bool(cond)


def word(name, i=0):
    a = e.mem(lbl[name] + 2 * i, 2)
    return a[0] | a[1] << 8


def setw(name, i, v):
    e.poke(lbl[name] + 2 * i, [v & 255, v >> 8])


def byte(name, i=0):
    return e.mem(lbl[name] + i, 1)[0]


def hold(n):
    """droids 1..n stand still"""
    for i in range(1, n + 1):
        if byte('_d_boom', i) == 0:
            e.poke(lbl['_d_vx'] + i, [0])
            e.poke(lbl['_d_vy'] + i, [0])
            e.poke(lbl['_d_wait'] + i, [40])


def frames(k, n):
    for _ in range(k):
        hold(n)
        e.frame()


way = (8, 1, 0)                         # right: key, x and y steps


def row(n, gap):
    """n 123s at full energy, the first 48 from the player (where its
    figure is: fig_place), then gap apart"""
    x0 = y0 = 65535                     # (not where fig_place() has it
    for _ in range(6):                  # mid-tick, 8 on)
        x0, y0 = min(x0, word('_d_x')), min(y0, word('_d_y'))
        e.frame()
    k, ux, uy = way
    e.poke(lbl['_nd'], [n + 1])
    for i in range(1, n + 1):
        d = 48 + (i - 1) * gap
        setw('_d_x', i, x0 + ux * d)
        setw('_d_y', i, y0 + uy * d)
        e.poke(lbl['_d_type'] + i, [1])
        e.poke(lbl['_d_energy'] + i, [64])
        e.poke(lbl['_d_boom'] + i, [0])
    e.poke(lbl['_s_life'], [0] * 8)
    frames(12, n)
    seen = [byte('_d_seen', i) for i in range(1, n + 1)]
    if not all(seen):
        print('  (not all seen: %s)' % seen)


def place(i, d):
    """droid i d from droid 1, the way the row goes"""
    k, ux, uy = way
    setw('_d_x', i, word('_d_x', 1) + ux * d)
    setw('_d_y', i, word('_d_y', 1) + uy * d)


def fire(n):
    """once the weapon is ready, fire the row's way for two ticks, then let
    go; True if it fired (the weapon reloading)"""
    t = 0
    while byte('d_cool') and t < 200:
        frames(1, n)
        t += 1
    e.poke(lbl['_dbg_keys'], [16 | way[0]])
    flew = False
    for _ in range(6):
        frames(1, n)
        flew |= byte('d_cool') != 0
    e.poke(lbl['_dbg_keys'], [0])
    return flew


def booms(n):
    return [byte('_d_boom', i) for i in range(1, n + 1)]


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
    # an open stretch of floor: four blocks of plain floor side by side,
    # the deck's commonest block (the map at $0400; its walls are in RAM
    # under the ROM, which the emulator's reads do not see)
    dmap = e.mem(0x0400, 1024)
    floor = max(set(dmap) - {0}, key=list(dmap).count)
    bx, by = next((bx, by) for by in range(16) for bx in range(60)
                  if all(dmap[by * 64 + bx + i] == floor for i in range(4)))
    x, y = bx * 32 + 16, by * 32 + 16
    setw('_d_x', 0, x)
    setw('_d_y', 0, y)
    e.poke(lbl['_d_vx'], [0])
    e.poke(lbl['_d_vy'], [0])
    e.poke(lbl['_nd'], [1])
    frames(30, 0)
    print('deck', byte('_deck'), 'player at', word('_d_x'), word('_d_y'))
    # 1.
    row(1, 0)
    f = fire(1)
    frames(10, 1)
    check('1. a droid alone: the laser kills it (boom %s)' % booms(1),
          f and booms(1)[0] != 0)
    frames(30, 1)
    # 2.
    row(2, 16)
    f = fire(2)
    frames(10, 2)
    check('2. two touching: fired (%s), the laser does nothing (boom %s, '
          'energy %s)' % (f, booms(2), [byte('_d_energy', i) for i in (1, 2)]),
          f and booms(2) == [0, 0])
    frames(30, 2)
    # 3.
    row(2, 40)
    fire(2)
    t = 0
    while booms(2)[0] == 0 and t < 30:
        frames(1, 2)
        t += 1
    place(2, 16)
    frames(9, 2)
    check('3. one moved into the explosion: it dies (boom %s)' % booms(2),
          booms(2)[1] != 0)
    frames(30, 2)
    # 4.
    row(3, 60)
    f = fire(3)
    t = 0
    while booms(3)[0] == 0 and t < 30:
        frames(1, 3)
        t += 1
    place(2, 16)
    place(3, 32)
    alive = f and byte('_d_boom', 1) != 0
    while 0 < byte('_d_boom', 1) < BOOM_GONE:
        frames(3, 3)
        alive &= booms(3)[1:] == [0, 0]
    check('4. two touching in it: nothing while it lasts (boom %s)' % booms(3),
          alive)
finally:
    e.stop()
print('ok' if ok else 'FAILED')
