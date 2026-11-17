#!/usr/bin/env python3
"""A free kick's distance (play.s WALL_D: set_wall, keep_off), in a match
in VICE: free kicks for cyan at a few places, the cyan stick let alone -
while each waits, how near the ball the nearest yellow player (not the
keeper) comes. Sensible Soccer's wall stands 51-56 pixels from the ball
(its free kicks' places); ours, WALL_D off in y and as far across as
each stood, 48-51.

    tests/freekick.py

A line each: the place, the nearest yellow, his distance; OK if none
comes nearer than NEAR. The exit code counts the wrong ones.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, labels  # noqa: E402
import moves  # noqa: E402

lab = labels()
OFF_PL = 0xED                   # (play.s)
R_FREE = 5
NEAR = 45                       # (WALL_D 40 in y, and across)
PLACES = [(304, 250), (200, 220), (420, 230), (304, 470), (120, 400), (480, 160)]


def where(v, i):
    m = {n: v.mem(lab[n] + i, 1)[0] for n in ('o_xl', 'o_xh', 'o_yl', 'o_yh')}
    return m['o_xl'] + 256 * m['o_xh'], m['o_yl'] + 256 * m['o_yh']


def run(v, at):
    s = moves.Setup()
    moves.restart(s, R_FREE, 0, *at)
    for i in moves.EXTRA:               # (restart is training's: all on)
        s.put('o_off', 0, i)
    for a, vals in s.pokes:
        v.poke(a, vals)
    v.poke(OFF_PL, [0xFF])
    v.poke(lab['dbg_joy'], [0])
    nearest = (9999, None)
    for f in range(150):
        v.cmd('x')
        if f < 20:                      # (the wall set up first)
            continue
        if not v.mem(lab['kickoff'], 1)[0]:
            break
        bx, by = where(v, 22)
        for i in range(12, 22):         # (yellow, not the keeper 11)
            x, y = where(v, i)
            d = ((x - bx) ** 2 + (y - by) ** 2) ** 0.5
            nearest = min(nearest, (round(d), i))
    return nearest


def main():
    v = Vice(PRG, WORK)
    wrong = 0
    try:
        v.cmd('break %04x' % lab['main'])
        v.cmd('x')
        v.cmd('del')
        v.cmd('break %04x' % lab['play_frame'])
        for _ in range(120):
            v.cmd('x')
        for at in PLACES:
            d, i = run(v, at)
            ok = d >= NEAR
            wrong += not ok
            print('free kick at %3d,%3d: nearest yellow %s, %d pixels  %s' % (
                at[0], at[1], i, d, 'OK' if ok else 'WRONG'))
            for _ in range(200):        # (whatever follows, over)
                v.cmd('x')
    finally:
        v.stop()
    return wrong


if __name__ == '__main__':
    sys.exit(main())
