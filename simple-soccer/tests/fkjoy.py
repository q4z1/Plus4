#!/usr/bin/env python3
"""A free kick for the yellow team (the computer) with cyan's joystick
player close to where it is taken, as the one who fouled - Luca saw him
stand right behind the taker. While it waits (the ball still on its
place), how near the ball the joystick's player comes: set_wall puts him
WALL_D (40) off, and he must stay there - he stands while the other
team's set piece waits, and keeps the stick till it is taken (play.s
switch).

    tests/fkjoy.py

A line each: the place, where cyan 9 stood, his nearest to the ball and
to the taker; OK if not nearer than NEAR. The exit code counts the wrong
ones.
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
NEAR = 40                       # (WALL_D)
BALL = 22
# (the place, cyan 9 off it) - yellow attacks down: behind the taker is up
CASES = [((304, 300), (0, -14)), ((304, 300), (10, -30)), ((304, 300), (0, 14)),
         ((304, 300), (30, 5)), ((200, 450), (-8, -20)), ((420, 520), (0, -24)),
         ((300, 560), (12, -18))]


def run(v, at, off):
    s = moves.Setup()
    moves.restart(s, R_FREE, 1, *at)
    for i in moves.EXTRA:               # (restart is training's: all on)
        s.put('o_off', 0, i)
    s.obj(9, at[0] + off[0], at[1] + off[1], d=0)
    for a, vals in s.pokes:
        v.poke(a, vals)
    v.poke(OFF_PL, [0xFF])
    v.poke(lab['dbg_joy'], [0])
    best = (9999, 9999)
    for f in range(400):
        v.cmd('x')
        if f < 4:                       # (put down, the wall set up)
            continue
        if not v.mem(lab['kickoff'], 1)[0]:
            break
        m = {n: v.mem(lab[n], BALL + 1) for n in ('o_xl', 'o_xh', 'o_yl', 'o_yh')}

        def where(i):
            return m['o_xl'][i] + 256 * m['o_xh'][i], m['o_yl'][i] + 256 * m['o_yh'][i]
        bx, by = where(BALL)
        if (bx, by) != at:              # (kicked)
            break
        taker = v.mem(lab['taker'], 1)[0]
        c = v.mem(lab['ctrl'], 1)[0]
        tx, ty = where(taker) if taker < BALL else (bx, by)
        x, y = where(c)
        best = min(best, (round(((x - bx) ** 2 + (y - by) ** 2) ** 0.5),
                          round(((x - tx) ** 2 + (y - ty) ** 2) ** 0.5)))
    return best


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
        for at, off in CASES:
            db, dt = run(v, at, off)
            ok = db >= NEAR
            wrong += not ok
            print('free kick at %3d,%3d, cyan 9 %+3d,%+3d: the joystick\'s %3d from the ball, %3d from the taker  %s' % (
                at[0], at[1], off[0], off[1], db, dt, 'OK' if ok else 'WRONG'))
            for _ in range(200):        # (whatever follows, over)
                v.cmd('x')
    finally:
        v.stop()
    return wrong


if __name__ == '__main__':
    sys.exit(main())
