#!/usr/bin/env python3
"""A free kick for the cyan team (the joystick's) with the computer's
"joystick player" (ctrl_b, its man at the ball) close to where it is
taken, as the one who fouled - Luca saw the computer's active player
stand at the ball while the kick waited, near the box above all. While
it waits (fire not pressed), how near the ball ctrl_b stays: as cyan's
at the computer's free kicks (tests/fkjoy.py) at least WALL_D (54) off -
and in line with his team: not nearer the ball than the nearest other
yellow (the wall from the set pieces' tables, some 55 off near the box)
or at WALL_D, where there is no wall,
where set_wall alone had put him, at 40 in front of it (Luca's picture:
WALL_D was 40).

    tests/fkcpu.py

A line each: the place, where ctrl_b stood, his nearest to the ball over
the wait and where he ended; OK if not nearer than NEAR. The exit code
counts the wrong ones.
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
NEAR = 50                       # (WALL_D 54)
WALL = 53                       # (put out to WALL_D: no wall there, all right)
BALL = 22
WHO = 20                        # (the computer's man at the ball)
# (the place, ctrl_b off it) - cyan attacks up: the yellow goal at the top
CASES = [((304, 300), (0, -14)), ((304, 220), (10, 12)), ((250, 200), (0, -10)),
         ((360, 180), (-12, 6)), ((304, 460), (8, -16)), ((304, 190), (4, -12)),
         ((304, 192), (6, 8))]
# the same after half time (flip: the yellow goal at the bottom, the place
# turned about), as Luca's picture: a free kick on the box's line


def run(v, at, off, flip):
    if flip:
        at, off = (at[0], 738 - at[1]), (off[0], -off[1])
    s = moves.Setup()
    moves.restart(s, R_FREE, 0, *at)
    s.put('flip', flip)
    for i in moves.EXTRA:               # (restart is training's: all on)
        s.put('o_off', 0, i)
    s.obj(WHO, at[0] + off[0], at[1] + off[1], d=4)
    s.put('ctrl_b', WHO)
    for a, vals in s.pokes:
        v.poke(a, vals)
    v.poke(OFF_PL, [0xFF])
    v.poke(lab['dbg_joy'], [0])
    best, last = 9999, None
    for f in range(300):
        v.cmd('x')
        if f < 4:                       # (put down, the wall set up)
            continue
        m = {n: v.mem(lab[n], BALL + 1) for n in ('o_xl', 'o_xh', 'o_yl', 'o_yh')}

        def where(i):
            return m['o_xl'][i] + 256 * m['o_xh'][i], m['o_yl'][i] + 256 * m['o_yh'][i]
        bx, by = where(BALL)
        c = v.mem(lab['ctrl_b'], 1)[0]
        x, y = where(c)
        d = round(((x - bx) ** 2 + (y - by) ** 2) ** 0.5)
        if f > 60:                      # (the time to get there)
            best = min(best, d)
        last = (c, x, y, d)
    others = min(round(((where(i)[0] - bx) ** 2 + (where(i)[1] - by) ** 2) ** 0.5)
                 for i in range(12, 22) if i != c)
    return best, last, at, others


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
        for flip, (at, off) in [(f, c) for f in (0, 1) for c in CASES]:
            best, (c, x, y, d), at, others = run(v, at, off, flip)
            ok = best >= NEAR and (d >= others - 4 or d >= WALL)
            wrong += not ok
            print('%s free kick at %3d,%3d, yellow %d %+3d,%+3d: ctrl_b %d at %d,%d, %3d from the ball '
                  '(nearest %3d after a second), the nearest other %3d  %s'
                  % ('flip' if flip else '    ', at[0], at[1], WHO, off[0], off[1], c, x, y, d,
                     best, others, 'OK' if ok else 'WRONG'), flush=True)
            for _ in range(60):
                v.cmd('x')
    finally:
        v.stop()
    return wrong


if __name__ == '__main__':
    sys.exit(main())
