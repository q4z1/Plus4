#!/usr/bin/env python3
"""How hard a kick goes by how long fire is held (play.s control, shot_power):
a player with the ball at his feet, facing up, no team-mate ahead (all
behind him), fire held so many frames, then let go; the ball's speed as it
leaves (its first frame on: the air's 10, the ground's 16 a frame added
back). His skill set to the weakest (sk_duel 7: no bonus) or the best (15).

    tests/power.py

tap      fire 2 frames: no one to pass to - straight on at 2048
hold N   fire N frames: a shot, 1792 + 32 for each frame past 9 (2 a
         step, fire being read each second frame), 24 at most (2560)
best     held long, the best player: 192 more

A line each, OK or WRONG; the exit code counts the wrong ones.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from keep import Scene, BALL  # noqa: E402
from shot import BITS, labels  # noqa: E402

TOL = 72                        # (two steps either way, and the first frame)


def kick(lab, frames, sk):
    s = Scene(lab)
    v = s.v
    try:
        p = s.get('ctrl')
        s.obj(p, 304, 500, d=0)
        s.obj(BALL, 304, 496)
        for i in range(22):
            if i not in (p, 0, 11):
                s.obj(i, 40 + 12 * i, 700 if i < 11 else 120)
        s.put('sk_duel', p, sk)
        s.put('last_team', 0, 0)
        s.put('last_pl', 0, p)
        v.cmd('del')
        v.cmd('break %04x' % lab['play_frame'])
        v.poke(lab['dbg_joy'], [BITS['fire']])
        for f in range(frames + 40):    # (held SHOT_MAX it goes while held)
            if f == frames:
                v.poke(lab['dbg_joy'], [0])
            v.cmd('x')
            sp = s.get16('o_spl', 'o_sph', BALL)
            if sp > 0 and s.get('last_pl') == p:
                v.cmd('x')              # (one frame on: its speed known)
                sp2 = s.get16('o_spl', 'o_sph', BALL)
                return sp + (sp - sp2), s.get('o_zl', BALL)
        return 0, 0
    finally:
        s.stop()


def main():
    lab = labels()
    cases = [('tap', 2, 7, 2048), ('hold 14', 14, 7, 1792 + 32 * 5),
             ('hold 22', 22, 7, 1792 + 32 * 13), ('hold 30', 30, 7, 1792 + 32 * 21),
             ('hold 60', 60, 7, 2560), ('best', 60, 15, 2560 + 192)]
    wrong = 0
    for name, frames, sk, want in cases:
        got, z = kick(lab, frames, sk)
        ok = abs(got - want) <= TOL
        wrong += not ok
        print('%-8s fire %2d frames, skill %2d: %4d (want %4d), %2d high  %s'
              % (name, frames, sk, got, want, z, 'OK' if ok else 'WRONG'), flush=True)
    return wrong


if __name__ == '__main__':
    sys.exit(main())
