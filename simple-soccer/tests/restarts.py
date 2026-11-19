#!/usr/bin/env python3
"""The cyan joystick's set pieces, in a match in VICE (the rules set each
up, both teams to their places): a goal kick, a corner, a throw-in -
fire tapped (a pass: to whom, recv) or held (a shot, 30 frames, the
stick let go) once the taker is ready and the box clear; then who touches
the ball first, his team's or the other's, and how far it went till
then. Luca: the goal kick's tap had no direction, and the ball was
intercepted too easily at goal kicks, corners and throw-ins.

    tests/restarts.py [case ...] [-v]

A line each, "theirs" where the other team got to it first (a measure:
some will); the exit code counts the taps that found no one.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, labels, BITS  # noqa: E402
from pace import game_rnd  # noqa: E402
import moves  # noqa: E402

lab = labels()
BALL = 22
R_THROW, R_GOALKICK, R_CORNER = 1, 2, 3
CASES = {'goalkick': (R_GOALKICK, 244, 664), 'goalkick-r': (R_GOALKICK, 364, 664),
         'corner': (R_CORNER, 54, 54), 'corner-r': (R_CORNER, 553, 54),
         'throw': (R_THROW, 49, 300), 'throw-r': (R_THROW, 559, 450)}


def m(v, n, i=0):
    return v.mem(lab[n] + i, 1)[0]


def w(v, lo, hi, i):
    x = m(v, lo, i) + 256 * m(v, hi, i)
    return x - 65536 if x > 32767 else x


def case(v, kind, x, y, hold):
    s = moves.Setup()
    moves.restart(s, kind, 0, x, y)
    for i in moves.EXTRA:               # (restart is training's: all on)
        s.put('o_off', 0, i)
    for a, vals in s.pokes:
        v.poke(a, vals)
    v.poke(0xED, [0xFF])                # (play.s off_pl)
    for f in range(600):                # ready: the taker at it, and a while
        v.cmd('x')                      # for the box to clear and his team
        if m(v, 'kickoff') and not m(v, 'dead_t') and f > 150 and \
                not any(m(v, 'o_mov', i) for i in range(1, 11)):
            break                       # at its places (from the case before)
    taker = m(v, 'taker')
    at = (w(v, 'o_xl', 'o_xh', BALL), w(v, 'o_yl', 'o_yh', BALL))
    v.poke(lab['dbg_joy'], [BITS['fire']])
    for f in range(hold):
        v.cmd('x')
    v.poke(lab['dbg_joy'], [0])
    recv = None
    for f in range(200):
        v.cmd('x')
        if recv is None:
            if m(v, 'kickoff'):
                continue
            recv = m(v, 'recv')         # (taken: the touches from now on)
            v.poke(lab['last_pl'], [taker])
            continue
        pl = m(v, 'last_pl')
        if pl != taker and pl < 22:
            b = (w(v, 'o_xl', 'o_xh', BALL), w(v, 'o_yl', 'o_yh', BALL))
            return taker, recv, pl, math.hypot(b[0] - at[0], b[1] - at[1]), f
    return taker, recv, None, 0, 200


def main():
    v = Vice(PRG, WORK)
    wrong = 0
    try:
        v.cmd('break %04x' % lab['main'])
        v.cmd('x')
        v.cmd('del')
        v.cmd('break %04x' % lab['chosen'])     # the same teams each time
        v.cmd('x')
        v.cmd('del')
        v.poke(0xFCE0 + 7 + 3, [0, 1])          # (game.inc K_CH's t_team)
        rnd = game_rnd()
        v.poke(rnd + 7, [0x49, 0x00, 0xEA])     # (eor $FF1E -> eor #0)
        v.poke(lab['z_rnd'], [1])
        v.cmd('break %04x' % lab['play_frame'])
        for _ in range(120):
            v.cmd('x')
        names = [a for a in sys.argv[1:] if not a.startswith('-')] or list(CASES)
        for name in names:
            kind, x, y = CASES[name]
            for how, hold in (('tap', 3), ('held', 30)):
                taker, recv, first, dist, f = case(v, kind, x, y, hold)
                bad = how == 'tap' and (recv is None or recv == 0xFF)
                wrong += bad
                print('%-10s %-4s taker %2d, pass to %-4s first touched by %-4s'
                      ' after %3d frames, %3d pixels  %s'
                      % (name, how, taker, recv if recv != 0xFF else '-', first, f, dist,
                         'WRONG' if bad else 'theirs' if first is None or first >= 11
                         else 'ok'), flush=True)
    finally:
        v.stop()
    return wrong


if __name__ == '__main__':
    sys.exit(main())
