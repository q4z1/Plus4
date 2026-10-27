#!/usr/bin/env python3
"""Keeping the ball: scenes set up through the monitor, then played on.

    tests/keep.py [case ...]

dribble-*  the joystick's player runs up with the ball at his feet, the
           other team's chaser in his way (straight ahead, to one side):
           the pictures he keeps it for (at most 60) and how far he got
receive-*  a pass coming at him from ahead, as fast as a pass goes,
           he standing or running on to it: is the ball his after it -
           his touch last, at his feet (CLOSE) or, running, dribbled on
           (12 pixels)?
pass-aside he passes with nobody straight ahead of him, one team-mate
           ahead and to the side: does the ball go to him (recv)?

Each case one line; the exit code counts the cases that went wrong
(only the receive and pass cases can: dribbling is a measure).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, BITS, labels, held_from_start  # noqa: E402

BALL = 22
CLOSE = 72


class Scene:
    def __init__(self, lab):
        self.lab = lab
        self.v = Vice(PRG, WORK)
        v = self.v
        held_from_start(v, lab, 'up')
        v.cmd('watch store %04x' % lab['shown'])
        for _ in range(40):
            v.cmd('x')
        v.poke(lab['dbg_joy'], [0])
        v.cmd('del')
        v.cmd('break %04x' % lab['eng_end'])
        v.cmd('x')
        self.put('kickoff', 0, 0)       # (not taken with the stick alone)
        self.put('taker', 0, 255)

    def put(self, n, i, value):
        self.v.poke(self.lab[n] + i, [value & 255])

    def put16(self, lo, hi, i, value):
        self.put(lo, i, value)
        self.put(hi, i, value >> 8)

    def get(self, n, i=0):
        return self.v.mem(self.lab[n] + i, 1)[0]

    def get16(self, lo, hi, i):
        w = self.get(lo, i) + 256 * self.get(hi, i)
        return w - 65536 if w > 32767 else w

    def obj(self, i, x, y, tx=None, ty=None, speed=0, d=None):
        self.put16('o_xl', 'o_xh', i, x)
        self.put16('o_yl', 'o_yh', i, y)
        self.put('o_xf', i, 0)
        self.put('o_yf', i, 0)
        self.put16('o_txl', 'o_txh', i, x if tx is None else tx)
        self.put16('o_tyl', 'o_tyh', i, y if ty is None else ty)
        self.put16('o_spl', 'o_sph', i, speed)
        if i == BALL:
            self.put('o_zl', i, 0)
            self.put('o_zf', i, 0)
            self.put('o_dzl', i, 0)
            self.put('o_dzf', i, 0)
        else:
            self.put('o_slide', i, 0)
            self.put('o_new', i, 1)
            if d is not None:
                self.put('o_dir', i, d)

    def where(self, i):
        return self.get16('o_xl', 'o_xh', i), self.get16('o_yl', 'o_yh', i)

    def picture(self):
        self.v.cmd('x')

    def stop(self):
        self.v.stop()


def d2(a, b):
    return (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2


def dribble(lab, dx):
    s = Scene(lab)
    try:
        p = s.get('ctrl')
        s.obj(p, 304, 600, d=0)
        s.obj(BALL, 304, 596)
        s.put('last_team', 0, 0)
        s.put('last_pl', 0, p)
        s.v.poke(lab['dbg_joy'], [BITS['up']])
        c = None
        for k in range(60):
            if k == 1:                  # the chaser in his way
                c = s.get('chaser')
                if c < 22:
                    s.obj(c, 304 + dx, 470, speed=0)
            s.picture()
            if s.get('last_team') == 1:
                return k, s.where(p)[1]
        return 60, s.where(p)[1]
    finally:
        s.stop()


def receive(lab, stick):
    s = Scene(lab)
    try:
        p = s.get('ctrl')
        s.obj(p, 304, 600, d=0)
        s.obj(BALL, 304, 480, ty=600 + 32 * 120, speed=1792)
        s.put('last_team', 0, 0)
        s.put('last_pl', 0, (p + 1) % 11 or 1)      # a team-mate's pass
        s.put('recv', 0, p)
        s.put('recv_t', 0, 100)
        s.v.poke(lab['dbg_joy'], [BITS[stick]] if stick != 'none' else [0])
        for _ in range(25):
            s.picture()
        q = s.get('ctrl')
        sp = s.get16('o_spl', 'o_sph', BALL)
        dd = d2(s.where(q), s.where(BALL))
        # standing: the ball at his feet; running: his, dribbled on ahead
        ok = s.get('last_pl') == q and dd <= (CLOSE if stick == 'none' else 144)
        return ok, q, dd, sp
    finally:
        s.stop()


def pass_aside(lab):
    s = Scene(lab)
    try:
        p = s.get('ctrl')
        # facing up, his team-mates all behind him but one, ahead and well
        # to the right - none within 22.5 degrees of the way he faces
        s.obj(p, 304, 500, d=0)
        s.obj(BALL, 304, 496)
        mate = 1 if p != 1 else 2
        for i in range(1, 11):
            if i == mate:
                s.obj(i, 380, 440)
            elif i != p:
                s.obj(i, 100 + 40 * i, 680)
        s.put('last_team', 0, 0)
        s.put('last_pl', 0, p)
        s.v.poke(lab['dbg_joy'], [BITS['fire']])
        s.picture()
        s.v.poke(lab['dbg_joy'], [0])
        s.picture()
        r = s.get('recv')
        return r == mate, r
    finally:
        s.stop()


def main():
    lab = labels()
    cases = sys.argv[1:] or ['dribble-ahead', 'dribble-side', 'receive-none',
                             'receive-up', 'pass-aside']
    bad = 0
    for c in cases:
        if c.startswith('dribble'):
            k, y = dribble(lab, 0 if c == 'dribble-ahead' else 14)
            print('%-14s kept %2d pictures, up to y %d' % (c, k, y))
        elif c.startswith('receive'):
            ok, q, dd, sp = receive(lab, c.split('-')[1])
            bad += not ok
            print('%-14s %s  joystick %d, ball %d away (squared), speed %d'
                  % (c, 'ok' if ok else 'LOST', q, dd, sp))
        elif c == 'pass-aside':
            ok, r = pass_aside(lab)
            bad += not ok
            print('%-14s %s  receiver %d' % (c, 'ok' if ok else 'NOBODY', r))
    sys.exit(bad)


if __name__ == '__main__':
    main()
