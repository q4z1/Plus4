#!/usr/bin/env python3
"""A joystick's throw-ins and corners aimed finer than the stick's eight
ways (play.s fine_aim), in a match in VICE: for each, the aim as it
starts (straight in for a throw-in, 19.7 degrees off the goal line for
a corner), a push at a time towards either end - a step each, none past
the end - and then fire held: the shot goes the way aimed.

    tests/aim.py [-v]

The cyan team's throw-ins on both touch lines and its corners at the
top; the yellow team, on the second joystick, its corners at the
bottom (its throw-ins upside down to the cyan team's). A line for each
case; the exit code 1 if any aim or shot is not as it should be.
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
OFF_PL = 0xED                   # (play.s)
BALL = 22
R_THROW, R_CORNER = 1, 3
THROW = [16, 32, 48, 64, 80, 96, 112]       # (play.s sp_ways_t, sp_ways_c:
CORNER = [67, 70, 74, 78, 83, 96]           # the ball on the left line
#                                             attacking up, the top left)


def mem1(v, name, i=0):
    return v.mem(lab[name] + i, 1)[0]


def word(v, lo, hi, i):
    x = mem1(v, lo, i) + 256 * mem1(v, hi, i)
    return x - 65536 if x > 32767 else x


def ways(kind, x, y, down):
    """the aims' ways (0-255, 0 up) for a set piece at x, y: the table
    turned about as play.s way_y turns it"""
    if kind == R_THROW:
        w = THROW
        flip_y = down
    else:
        w = CORNER
        flip_y = y >= 369
    if flip_y:
        w = [(128 - a) & 255 for a in w]
    if x >= 304:
        w = [(-a) & 255 for a in w]
    return w


def way_of(dx, dy):
    """the way (0-255, 0 up, clockwise) of a step dx, dy"""
    return round(math.atan2(dx, -dy) * 128 / math.pi) & 255


def off(a, b):
    d = (a - b) & 255
    return min(d, 256 - d)


def frames(v, n, joy, key):
    for _ in range(n):
        v.poke(lab[key], [joy])
        v.cmd('x')


def case(v, kind, team, at, down):
    """one set piece: the problems found, as lines"""
    bad = []
    key = 'dbg_joy' if team == 0 else 'dbg_joyb'
    s = moves.Setup()
    moves.restart(s, kind, team, *at)
    for i in moves.EXTRA:               # (restart is training's: all on)
        s.put('o_off', 0, i)
    for a, vals in s.pokes:
        v.poke(a, vals)
    v.poke(OFF_PL, [0xFF])
    for f in range(300):                # till the taker is at the ball
        frames(v, 1, 0, key)
        if mem1(v, 'kickoff') and not mem1(v, 'dead_t') and mem1(v, 'sp_aim') < 128:
            break
    else:
        return ['not ready to take within 300 frames']
    frames(v, 4, 0, key)
    bx, by = word(v, 'o_xl', 'o_xh', BALL), word(v, 'o_yl', 'o_yh', BALL)
    want = ways(kind, bx, by, down)
    n = len(want)
    aim = mem1(v, 'sp_aim')
    if aim != 3:
        bad.append('starts at aim %d, not 3' % aim)
    # towards either end: the stick the way of the aim past it
    for end in (0, n - 1, 3):
        target = want[end]
        d = ((target - want[3] + 128) & 255) - 128
        beyond = target + (48 if d > 0 else -48 if d < 0 else 0)
        stick = min(range(8), key=lambda k: off(k * 32, beyond & 255))
        bits = 0
        for p, b in (('up', 0), ('right', 2), ('down', 4), ('left', 6)):
            if (stick - b) % 8 in (7, 0, 1):
                bits |= BITS[p]
        seen = [mem1(v, 'sp_aim')]
        for _ in range(n + 2):
            frames(v, 2, bits, key)
            frames(v, 3, 0, key)
            a = mem1(v, 'sp_aim')
            if a != seen[-1]:
                seen.append(a)
        if '-v' in sys.argv:
            print('    stick %d: aims %s' % (stick, seen))
        if seen[-1] != end and not (end == 3 and off(stick * 32, want[seen[-1]]) <= off(stick * 32, target)):
            bad.append('stick %d ended at aim %d, not %d (%s)' % (stick, seen[-1], end, seen))
        if any(abs(b - a) != 1 for a, b in zip(seen, seen[1:])):
            bad.append('stepped more than one aim at a push: %s' % seen)
        d = mem1(v, 'o_dir', mem1(v, 'taker'))
        if off(d * 32, want[seen[-1]]) > 16:
            bad.append('he faces %d, the aim %d' % (d, want[seen[-1]]))
    # one step off the middle, then fire held: the shot that way
    frames(v, 2, BITS['right'] if team == 0 else BITS['left'], key)
    frames(v, 3, 0, key)
    aim = mem1(v, 'sp_aim')
    way = want[aim]
    for f in range(60):
        frames(v, 1, BITS['fire'], key)
        if not mem1(v, 'kickoff'):
            break
    else:
        bad.append('fire held 60 frames: not kicked')
        return bad
    tx, ty = word(v, 'o_txl', 'o_txh', BALL), word(v, 'o_tyl', 'o_tyh', BALL)
    x, y = word(v, 'o_xl', 'o_xh', BALL), word(v, 'o_yl', 'o_yh', BALL)
    got = way_of(tx - x, ty - y)
    if off(got, way) > 1:
        bad.append('aim %d way %d: the shot went way %d (to %d,%d from %d,%d)'
                   % (aim, way, got, tx, ty, x, y))
    if '-v' in sys.argv:
        print('    shot: aim %d way %d, went %d' % (aim, way, got))
    frames(v, 60, 0, key)
    return bad


def main():
    v = Vice(PRG, WORK)
    fails = 0
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
        v.poke(lab['two'], [1])
        cases = [(R_THROW, 0, (49, 300), False), (R_THROW, 0, (559, 450), False),
                 (R_THROW, 0, (49, 600), False), (R_THROW, 1, (559, 200), True),
                 (R_CORNER, 0, (49, 49), False), (R_CORNER, 0, (559, 49), False),
                 (R_CORNER, 1, (49, 689), True), (R_CORNER, 1, (559, 689), True)]
        for kind, team, at, down in cases:
            bad = case(v, kind, team, at, down)
            name = '%s for %s at %s' % ('throw-in' if kind == R_THROW else 'corner',
                                         'cyan' if team == 0 else 'yellow', at)
            print('%-34s %s' % (name, 'ok' if not bad else '; '.join(bad)), flush=True)
            fails += bool(bad)
    finally:
        v.stop()
    print('%d of %d not right' % (fails, len(cases)))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
