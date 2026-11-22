#!/usr/bin/env python3
"""Shots from outside the box at the computer's keeper, as a player makes
them - how many go in, by how hard (fire held: play.s shot_power), the
aftertouch and the keeper's level. Luca: even a slight banana scores from
outside the box. Sensible Soccer's shot is 2208 for all (c11756); ours
1792 at SHOT_HOLD, 32 more each frame held on up to 2560, and up to 192
more for the best player (shot_b).

    tests/longshots.py [levels] [holds] [facings]

levels: the keeper's, comma-joined (by default 1,4,8: the best, the
player's own, the worst); holds: the frames fire is held (by default
22,33: 2208 as Sensible Soccer's, 2560 the most); facings: the ways the
shooter faces, comma-joined (by default 0: up; 1 up right, 7 up left -
Luca: a shot across from outside the box goes in often).

The cyan joystick's player, alone with the ball, facing up at the yellow
keeper's goal from 3 x 3 places outside the box; the keeper set as the
title's keeps makes the computer's of that level (kp_*); the shooter no
bonus (sk_duel 7). Each shot straight, bent left, bent right (the stick
held that way from the shot on). A line for each level and hold: goals
of the shots; then a table.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from keep import Scene, BALL  # noqa: E402
from shot import BITS, labels  # noqa: E402

lab = labels()
XS = (230, 304, 378)
YS = (200, 250, 300)            # (the goal line at 49, the box's at 136)
BENDS = (('straight', 0), ('left', BITS['left']), ('right', BITS['right']))


def keeper(s, level):
    """the yellow keeper as keeps makes the computer's of a level"""
    s.put('kp_dn', 1, 8)
    s.put('kp_dv', 1, level - 1)
    g, sl = 1056 - 32 * level, 272 - 16 * level
    s.put('kp_gl', 1, g & 255)
    s.put('kp_gh', 1, g >> 8)
    s.put('kp_sl', 1, sl & 255)
    s.put('kp_sh', 1, sl >> 8)


DIRS = {0: (0, -1), 1: (1, -1), 7: (-1, -1)}  # (up, up right, up left)


def shoot(s, x, y, hold, bend, d=0):
    v = s.v
    p = s.get('ctrl')
    for i in range(22):
        if i not in (p, 11):
            s.obj(i, 60 + 22 * (i % 11), 690 if i < 11 else 670)
    s.obj(11, 304, 60)
    dx, dy = DIRS[d]
    s.obj(p, x, y, d=d)
    s.obj(BALL, x + 4 * dx, y + 4 * dy)
    for n in ('kickoff', 'dead_t'):
        s.put(n, 0, 0)
    s.put('at_n', 0, 0xFF)
    s.put('last_team', 0, 0)
    s.put('last_pl', 0, p)
    s.put('sk_duel', p, 7)
    score = s.get('score', 0)
    v.poke(lab['dbg_joy'], [0])
    for _ in range(6):                  # (the keeper sees him)
        v.cmd('x')
        s.obj(p, x, y, d=d)
        s.obj(BALL, x + 4 * dx, y + 4 * dy)
    v.poke(lab['dbg_joy'], [BITS['fire']])
    gone = None
    for f in range(hold + 160):
        if f == hold:
            v.poke(lab['dbg_joy'], [bend])
        v.cmd('x')
        if gone is None:
            if s.get16('o_spl', 'o_sph', BALL) > 0 and s.get('last_pl') == p:
                gone = f
                v.poke(lab['dbg_joy'], [(BITS['fire'] if f < hold else 0) | bend])
            continue
        if s.get('score', 0) != score:
            return 'goal'
        if s.get('last_pl') != p or s.get('last_team') != 0:
            return 'saved'
        if s.get('dead_t') or s.get('kickoff'):
            return 'out'
    return 'none'


def main():
    levels = [int(a) for a in (sys.argv[1] if len(sys.argv) > 1 else '1,4,8').split(',')]
    holds = [int(a) for a in (sys.argv[2] if len(sys.argv) > 2 else '22,33').split(',')]
    dirs = [int(a) for a in (sys.argv[3] if len(sys.argv) > 3 else '0').split(',')]
    table = {}
    for level in levels:
        for hold in holds:
            s = Scene(lab)
            try:
                s.v.cmd('del')
                s.v.cmd('break %04x' % lab['play_frame'])
                keeper(s, level)
                res = {}
                for d in dirs:
                    for y in YS:
                        for x in XS:
                            for name, bend in BENDS:
                                res[(d, x, y, name)] = shoot(s, x, y, hold, bend, d)
            finally:
                s.stop()
            for d in dirs:
                r_d = {k: r for k, r in res.items() if k[0] == d}
                goals = sum(r == 'goal' for r in r_d.values())
                print('keeper level %d, fire %d frames, facing %d: %2d goals, %2d saved, %2d wide of %d' % (
                    level, hold, d, goals, sum(r == 'saved' for r in r_d.values()),
                    sum(r == 'out' for r in r_d.values()), len(r_d)), flush=True)
                for y in YS:
                    print('   y %3d: ' % y + '  '.join(
                        '%3d %s' % (x, ''.join(r_d[(d, x, y, n)][0].upper() if r_d[(d, x, y, n)] == 'goal'
                                               else r_d[(d, x, y, n)][0] for n, _ in BENDS)) for x in XS))
                table[(level, hold, d)] = goals
    print('goals (of %d):' % (len(XS) * len(YS) * len(BENDS)), table)


if __name__ == '__main__':
    main()
