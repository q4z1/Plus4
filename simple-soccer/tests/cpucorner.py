#!/usr/bin/env python3
"""The computer's corners (play.s brain_set), in a match in VICE: a corner
for the yellow team at either flag of the goal it attacks, the match's
minute 0 - 3 (game_min: the clock stands while it waits) - crossed along
the goal line in front of the goal: minute 0 low and hard (up to 12), 2 high to the
far post, 1 and 3 lifted, as ever (Luca: the computer knew one way only).
How high it went, who touched it first.

    tests/cpucorner.py

A line each, OK or WRONG; the exit code counts the wrong ones.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, labels  # noqa: E402
from pace import game_rnd  # noqa: E402
from restarts import m, w, BALL  # noqa: E402
import moves  # noqa: E402

lab = labels()
R_CORNER = 3
FLAGS = {'left': (54, 684), 'right': (553, 684)}


def case(v, x, y, minute):
    s = moves.Setup()
    moves.restart(s, R_CORNER, 1, x, y)
    for i in moves.EXTRA:
        s.put('o_off', 0, i)
    s.put('game_min', minute)
    for a, vals in s.pokes:
        v.poke(a, vals)
    v.poke(0xED, [0xFF])
    for f in range(900):                # till kicked
        v.cmd('x')
        if f > 20 and not m(v, 'kickoff'):
            break
    taker = m(v, 'taker')
    at = (w(v, 'o_xl', 'o_xh', BALL), w(v, 'o_yl', 'o_yh', BALL))
    v.poke(lab['last_pl'], [taker])
    zmax = 0
    for g in range(200):
        v.cmd('x')
        zmax = max(zmax, m(v, 'o_zl', BALL))
        pl = m(v, 'last_pl')
        if pl != taker and pl < 22:
            b = (w(v, 'o_xl', 'o_xh', BALL), w(v, 'o_yl', 'o_yh', BALL))
            return f, zmax, pl, math.hypot(b[0] - at[0], b[1] - at[1])
    return f, zmax, None, 0


def main():
    v = Vice(PRG, WORK)
    wrong = 0
    try:
        v.cmd('break %04x' % lab['main'])
        v.cmd('x')
        v.cmd('del')
        v.cmd('break %04x' % lab['chosen'])
        v.cmd('x')
        v.cmd('del')
        v.poke(0xFCE0 + 7 + 3, [0, 1])
        rnd = game_rnd()
        v.poke(rnd + 7, [0x49, 0x00, 0xEA])
        v.poke(lab['z_rnd'], [1])
        v.cmd('break %04x' % lab['play_frame'])
        for _ in range(120):
            v.cmd('x')
        for name, (x, y) in FLAGS.items():
            for minute in range(4):
                f, zmax, first, dist = case(v, x, y, minute)
                lo, hi = {0: (0, 12), 2: (25, 99)}.get(minute, (12, 24))
                ok = f < 150 and lo <= zmax <= hi
                wrong += not ok
                print('%-5s minute %d: kicked after %3d frames, %s (%2d high at most), first '
                      'touched by %-4s %3d pixels on  %s'
                      % (name, minute, f, 'low' if zmax <= 12 else 'high' if zmax >= 25 else 'lifted', zmax, first, dist,
                         'OK' if ok else 'WRONG'), flush=True)
    finally:
        v.stop()
    return wrong


if __name__ == '__main__':
    sys.exit(main())
