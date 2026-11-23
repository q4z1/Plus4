#!/usr/bin/env python3
"""A keeper and a high ball in his box (play.s k_high), in a match in
VICE: the cyan keeper at the bottom, a ball put in the air in his box -
he goes to where it comes down through 20 high if that is in his box
too and he is at most half as far from it as the ball (outside the goal
area only so many times in 16, by his team's keeper). The cyan stick on
9, let alone, the yellow team off.

    tests/highball.py [case ...]

lob       lifted from the edge of the box, coming down near him: he goes
even      dropping in front of him as far from him as from the ball: he
          stays
nearball  slow, coming down beside itself, far from him: he stays
wide      coming down at the side of the box, far from him: he stays

Each frame while the ball is 20 high or more (so his other rules, for a
low ball, keep out of it) where it will come down is worked out here as
the keeper works it out (the ball's steps on, gravity $12 a frame, no
slowing in the air), and his place looked at. A line each: where it was
to come down, whether he went there, OK or WRONG; the exit code counts
the wrong ones.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, labels  # noqa: E402
import moves  # noqa: E402

lab = labels()
OFF_PL = 0xED                   # (play.s)
BALL = 22
NEAR = 3                        # (his place this near where it comes down)

# name: (the ball at, going to, speed, z, dz (8.8), he goes)
CASES = {                       # (dz -1: 0 is a ball lying, rolling)
    'lob': ((304, 605), (304, 720), 1024, 40, 256, True),
    'even': ((304, 610), (304, 720), 1024, 30, -1, False),
    'nearball': ((420, 620), (420, 720), 1024, 24, -1, False),
    'wide': ((200, 610), (60, 640), 1024, 30, -1, False),
}


def word(v, lo, hi, i):
    return v.mem(lab[lo] + i, 1)[0] + 256 * v.mem(lab[hi] + i, 1)[0]


def signed(lo, hi):
    w = lo + 256 * hi
    return w - 65536 if w > 32767 else w


def landing(v):
    """where the ball will come down through 20 (or as high as it is, 13
    at least), as k_high works it out; None if it is low"""
    m = {n: v.mem(lab[n] + BALL, 1)[0] for n in (
        'o_xl', 'o_xh', 'o_yl', 'o_yh', 'o_vxf', 'o_vxl', 'o_vyf', 'o_vyl',
        'o_zf', 'o_zl', 'o_dzf', 'o_dzl')}
    if m['o_zl'] < 13:
        return None
    h = min(20, m['o_zl'])
    z, dz = m['o_zl'] * 256 + m['o_zf'], signed(m['o_dzf'], m['o_dzl'])
    n = 0
    while True:
        n += 1
        dz -= 0x12
        z += dz
        if z < h * 256:
            break
    vx, vy = signed(m['o_vxf'], m['o_vxl']), signed(m['o_vyf'], m['o_vyl'])
    step = lambda s_: (n * abs(s_)) >> 8 if s_ >= 0 else -((n * abs(s_)) >> 8)
    return m['o_xl'] + 256 * m['o_xh'] + step(vx), m['o_yl'] + 256 * m['o_yh'] + step(vy)


def run(v, name):
    at, to, speed, z, dz, goes = CASES[name]
    s = moves.Setup()
    moves.open_play(s, 9)
    for i in range(1, 22):              # (the keepers, 9 and one yellow
        s.put('o_off', 0 if i in (9, 11, 21) else 3, i)  # far off: with
    s.obj(0, 304, 676, d=0)             # none the yellow team's set
    s.obj(11, 304, 62, d=4)             # pieces after a case have no
    s.obj(9, 304, 300, d=0)             # taker - ctrl_b $FF, a hang)
    s.obj(21, 304, 150, d=4)
    moves.flight(s, at[0], at[1], to[0], to[1], speed, z, dz)
    for a, vals in s.pokes:
        v.poke(a, vals)
    v.poke(OFF_PL, [0xFF])
    v.poke(lab['dbg_joy'], [0])
    down, went = None, False
    for f in range(60):
        v.cmd('x')
        if v.mem(lab['o_zl'] + BALL, 1)[0] < 20:
            break
        place = (word(v, 'o_txl', 'o_txh', 0), word(v, 'o_tyl', 'o_tyh', 0))
        if down and abs(place[0] - down[0]) <= NEAR and abs(place[1] - down[1]) <= NEAR:
            went = True                 # (the last frame's worked out)
        down = landing(v)
    if down is None:
        return False, 'not high'
    return went == goes, 'to come down at %d,%d - he %s' % (
        down[0], down[1], 'went there' if went else 'stayed')


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
            print('%-9s %-50s %s' % (name, got, 'OK' if ok else 'WRONG'))
            for _ in range(150):        # (whatever follows, over)
                v.cmd('x')
    finally:
        v.stop()
    return wrong


if __name__ == '__main__':
    sys.exit(main())
