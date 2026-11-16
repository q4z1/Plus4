#!/usr/bin/env python3
"""Offside (play.s off_mark, off_chk), in a match in VICE: a pass from
the cyan 7 to the cyan 9, the yellow team's last but one (12, on the second
joystick, let alone: he stays) on a line across the pitch, the keeper
behind him; the cyan 8 by the ball (he runs to it); everyone else off
the pitch. 9 is held where he is till the pass goes.

    tests/offside.py [case ...]

off     9 beyond the line when the pass goes: he gets it - the whistle,
        a free kick for the yellow team where he is
on      9 behind the line: he gets it, play goes on
level   9 level with 12 (the same y / 4): onside
own     9 beyond it, but in his own half: onside
throw   a throw-in to 9 beyond the line: no offside from a throw-in
down    the second half, cyan attacking down: offside as in 'off'

A line each: the case, what happened, OK or WRONG; the exit code counts
the wrong ones.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, BITS, labels  # noqa: E402
import moves  # noqa: E402

lab = labels()
OFF_PL = 0xED                   # (play.s)
R_THROW, R_FREE = 1, 5


def bits(s):
    b = 0
    for p in s.split('+'):
        b |= BITS.get(p, 0)
    return b


def scene(s, nine, line=250, ball=(304, 330), flip=0):
    """7 on the ball at ball facing 9, 9 at nine, yellow's 12 at line,
    the keepers in goal; all others off. flip: the sides changed (y
    upside down, cyan attacking down)"""
    def fy(y):
        return 749 - y if flip else y
    moves.open_play(s, 7, team=0, holder=7)
    s.put('flip', flip)
    s.put('two', 1)                     # (12 on the second joystick, let
    s.put('ctrl_b', 12)                 # alone: he stands where he is)
    for i in range(22):
        s.put('o_off', 0 if i in (0, 7, 8, 9, 11, 12) else 1, i)
    s.obj(0, 304, fy(676), d=4 if flip else 0)
    s.obj(8, ball[0] + 30, fy(ball[1] + 20), d=4 if flip else 0)   # (he runs to the ball, not 9)
    s.obj(11, 304, fy(62), d=0 if flip else 4)
    s.obj(12, 120, fy(line), d=0 if flip else 4)
    s.obj(7, ball[0], fy(ball[1] + 4), d=4 if flip else 0)
    s.obj(9, nine[0], fy(nine[1]), d=4 if flip else 0)
    s.obj(moves.BALL, ball[0], fy(ball[1]))


CASES = {
    'off': (lambda s: scene(s, (304, 180)), 'fire', True),
    'on': (lambda s: scene(s, (304, 262)), 'fire', False),
    'level': (lambda s: scene(s, (304, 250)), 'fire', False),
    'own': (lambda s: scene(s, (304, 420), line=500, ball=(304, 600)), 'fire', False),
    'down': (lambda s: scene(s, (304, 180), flip=1), 'fire', True),
}


def throw_scene(s):
    scene(s, (150, 180))
    moves.restart(s, R_THROW, 0, 49, 300)
    for i in range(22):                 # (restart's open_play let EXTRA on)
        s.put('o_off', 0 if i in (0, 7, 8, 9, 11, 12) else 1, i)


CASES['throw'] = (throw_scene, 'up+right+fire', False)


def run(v, name):
    setup, how, want = CASES[name]
    s = moves.Setup()
    setup(s)
    for a, vals in s.pokes:
        v.poke(a, vals)
    v.poke(OFF_PL, [0xFF])
    start = 60 if name == 'throw' else 5     # (a throw-in: its taker set first)
    seen = set()
    nine = v.mem(lab['o_yl'] + 9, 1) + v.mem(lab['o_yh'] + 9, 1)
    kicked = False
    for f in range(start + 160):
        v.poke(lab['dbg_joy'], [bits(how) if start <= f < start + 3 else 0])
        kicked = kicked or v.mem(lab['o_spl'] + 22, 1)[0] or v.mem(lab['o_sph'] + 22, 1)[0]
        if not kicked:                  # (9 held where he is till the pass)
            for k in ('o_yl', 'o_tyl'):
                v.poke(lab[k] + 9, nine[:1])
            for k in ('o_yh', 'o_tyh'):
                v.poke(lab[k] + 9, nine[1:])
        v.cmd('x')
        off, = v.mem(OFF_PL, 1)
        if off != 0xFF and off not in seen:
            seen.add(off)
            if '-v' in sys.argv:
                p = v.mem(lab['o_xl'], 92)
                print('   frame %d: %d marked, line %d, y: 9 %d, 12 %d, ball %d, 7 %d' % (
                    f, off, v.mem(lab['z_off'], 1)[0], *(p[46 + i] + 256 * p[69 + i]
                                                         for i in (9, 12, 22, 7))))
        rs, = v.mem(lab['rs_kind'], 1)
        dead, = v.mem(lab['dead_t'], 1)
        lp, = v.mem(lab['last_pl'], 1)
        if f > start and dead and rs == R_FREE:
            team, = v.mem(lab['rs_team'], 1)
            x = v.mem(lab['rs_x'], 2)
            y = v.mem(lab['rs_y'], 2)
            got = 'offside: free kick for team %d at %d,%d (9 marked: %s)' % (
                team, x[0] + 256 * x[1], y[0] + 256 * y[1], 9 in seen)
            return want and team == 1, got
        if f > start + 3 and lp == 9:
            for _ in range(4):          # (the check is the next frame's)
                v.cmd('x')
            dead, = v.mem(lab['dead_t'], 1)
            rs, = v.mem(lab['rs_kind'], 1)
            if dead and rs == R_FREE:
                continue
            return not want, '9 has the ball, play on (9 marked: %s)' % (9 in seen)
    return False, 'nothing within 160 frames (last_pl %d)' % lp


def main():
    names = [a for a in sys.argv[1:] if a[0] != '-'] or list(CASES)
    v = Vice(PRG, WORK)
    wrong = 0
    try:
        v.cmd('break %04x' % lab['main'])
        v.cmd('x')
        v.cmd('del')
        v.cmd('break %04x' % lab['play_frame'])
        for _ in range(120):
            v.cmd('x')
        for name in names:
            ok, got = run(v, name)
            wrong += not ok
            print('%-6s %-60s %s' % (name, got, 'OK' if ok else 'WRONG'))
            for _ in range(200):        # (whatever follows, over)
                v.cmd('x')
    finally:
        v.stop()
    return wrong


if __name__ == '__main__':
    sys.exit(main())
