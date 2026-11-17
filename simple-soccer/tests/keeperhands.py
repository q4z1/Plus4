#!/usr/bin/env python3
"""The keeper's hands (play.s catch, k_clear, k_get): only in his box,
not for a team-mate's back-pass - there he kicks it away - and holding
it, his arms down after ARMS_T. Scenes set up through the monitor in a
match in VICE, the cyan keeper (0) at the bottom.

    tests/keeperhands.py [case ...]

back     a cyan player passes back to his keeper in the box: no hold, the
         keeper kicks it away (last_pl 0, the ball going up the pitch)
shot     a yellow shot rolling at him in his box: he holds it; ARMS_T on
         he stands, the ball at his chest (pose none, lift HOLD_TOP);
         screenshots keeper-up.png, keeper-chest.png
outside  he stands out of his box, a yellow ball rolls at him: no hold,
         kicked away
loose    a still ball just out of his box, near him: he does not go
         for it (stays in his box)

A line each, OK or WRONG; the exit code counts the wrong ones.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from keep import Scene, BALL  # noqa: E402
from shot import WORK, BITS, labels  # noqa: E402

R_KEEPER = 4
BOX_B = 602                     # (play.s ka_y: the bottom box from here)
ARMS_T = 25
HOLD_TOP = 6


def held(s):
    return s.get('kickoff') == 1 and s.get('rs_kind') == R_KEEPER


def back(lab):
    s = Scene(lab)
    try:
        p = s.get('ctrl')
        s.obj(p, 304, 560, d=4)
        s.obj(BALL, 304, 564)
        s.obj(0, 304, 670)
        for i in range(1, 11):          # team-mates out of the way, behind
            if i != p:
                s.obj(i, 60 + 40 * i, 300)
        s.put('last_team', 0, 0)
        s.put('last_pl', 0, p)
        s.v.poke(lab['dbg_joy'], [BITS['fire'] | BITS['down']])
        s.picture()
        s.v.poke(lab['dbg_joy'], [0])
        for k in range(60):
            s.picture()
            if held(s):
                return False, 'held it after %d pictures' % k
            if s.get('last_pl') == 0:
                for _ in range(3):
                    s.picture()
                sp = s.get16('o_spl', 'o_sph', BALL)
                ty = s.get16('o_tyl', 'o_tyh', BALL)
                by = s.where(BALL)[1]
                return ty < by and sp > 1000 and not held(s), \
                    'kicked away: speed %d, to y %d from %d' % (sp, ty, by)
        return False, 'the keeper never got to it'
    finally:
        s.stop()


def shot(lab):
    s = Scene(lab)
    try:
        s.obj(0, 304, 680)
        s.obj(BALL, 304, 620, ty=700 + 32 * 100, speed=1536)
        s.put('last_team', 0, 1)
        s.put('last_pl', 0, 18)
        for k in range(40):
            s.picture()
            if held(s):
                break
        else:
            return False, 'not held'
        s.picture()
        s.v.screenshot(os.path.join(WORK, 'keeper-up.png'))
        up = s.get('lift')
        for _ in range(ARMS_T // 3 + 3):
            s.picture()
        s.v.screenshot(os.path.join(WORK, 'keeper-chest.png'))
        chest = s.get('lift')
        return up > HOLD_TOP and chest == HOLD_TOP and held(s), \
            'held: the ball %d up, then %d (touch_t %d)' % (up, chest, s.get('touch_t'))
    finally:
        s.stop()


def outside(lab):
    s = Scene(lab)
    try:
        s.obj(0, 304, 560)
        s.obj(BALL, 304, 470, ty=560 + 32 * 100, speed=1536)
        s.put('last_team', 0, 1)
        s.put('last_pl', 0, 18)
        for k in range(40):
            if s.get('last_pl') != 0:
                s.obj(0, 304, 560)      # (kept there, out of his box)
            s.picture()
            if held(s):
                return False, 'held it out of his box at %s' % (s.where(BALL),)
            if s.get('last_pl') == 0:
                at = s.where(BALL)
                for _ in range(3):
                    s.picture()
                ty = s.get16('o_tyl', 'o_tyh', BALL)
                return ty < s.where(BALL)[1] and not held(s) and at[1] < BOX_B, \
                    'kicked away, the ball at %s' % (at,)
        return False, 'never touched it'
    finally:
        s.stop()


def loose(lab):
    s = Scene(lab)
    try:
        s.obj(0, 304, 640)
        s.obj(BALL, 304, BOX_B - 12)
        for i in range(1, 22):          # everyone else far off
            if i != 11:
                s.obj(i, 60 + 20 * i, 200)
        s.put('last_team', 0, 1)
        s.put('last_pl', 0, 18)
        low = 999
        for k in range(30):
            s.picture()
            low = min(low, s.where(0)[1])
            if held(s):
                return False, 'held it'
        return low >= BOX_B - 4, 'the keeper as far up as y %d (the box from %d)' % (low, BOX_B)
    finally:
        s.stop()


CASES = {'back': back, 'shot': shot, 'outside': outside, 'loose': loose}


def main():
    lab = labels()
    wrong = 0
    for name in sys.argv[1:] or list(CASES):
        ok, got = CASES[name](lab)
        wrong += not ok
        print('%-8s %-60s %s' % (name, got, 'OK' if ok else 'WRONG'), flush=True)
    return wrong


if __name__ == '__main__':
    sys.exit(main())
