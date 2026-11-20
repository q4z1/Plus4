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
clear    he catches it, three of the yellow team in his box beside him
         (one their joystick's): none put out of it at once (Luca: the
         attacker beside the keeper vanished) - each runs out, no step
         over STEP_MAX; fire pressed and let go meanwhile does not kick it,
         only once the box is clear; screenshot keeper-clear.png
clear-top the yellow keeper catches it, the cyan joystick's player and two
         more in his box: they run out likewise, the yellow team kicks it
         out only then
slider   one of the yellow team, neither its joystick's player nor its
         runner, slides down at the cyan goal as the keeper catches it:
         slowed as any tackle, up again, out of the box, and the keeper
         kicks it out (Luca: such a one slid on 1000 pixels, off the
         pitch to y 1675, and the keeper's ball waited for him for ever)
again    he holds it, taps fire - out of his hands: not marked as a set
         piece's taker (off_pl $FE), so his next touch is no double touch
         (it was, a free kick at his box: Luca's penalty out of nowhere)

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
OFF_PL = 0xED                   # (play.s)
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


STEP_MAX = 16                   # (1024 a frame, three frames a picture: 12)
BOX_T = 137                     # (play.s: the top box above this)


def in_box(p, top):
    return 161 <= p[0] <= 446 and (p[1] < BOX_T if top else p[1] > BOX_B - 1)


def clear(lab, top=False):
    s = Scene(lab)
    try:
        keeper, mates, them = (11, range(12, 22), range(1, 11)) if top else \
            (0, range(1, 11), range(12, 22))
        gy, d = (60, 1) if top else (680, -1)
        s.obj(keeper, 304, gy)
        s.obj(BALL, 304, gy + 14 * d, ty=gy - 3200 * d, speed=1024)
        for i in mates:                 # his team-mates far up the pitch
            s.obj(i, 60 + 40 * (i % 11), 369)
        ctl = s.get('ctrl' if top else 'ctrl_b')
        if ctl not in them:
            return False, 'the other joystick on %d' % ctl
        near = [ctl] + [i for i in them if i != ctl][:2]
        for i, (x, dy) in zip(near, [(270, 10), (338, 18), (304, 40)]):
            s.obj(i, x, gy + dy * d)
        for i in them:
            if i not in near:
                s.obj(i, 60 + 40 * (i % 11), 369)
        s.put('last_team', 0, 0 if top else 1)
        s.put('last_pl', 0, 3 if top else 14)
        for k in range(20):
            s.picture()
            if s.get('kickoff') == 1 and s.get('rs_kind') == R_KEEPER:
                break
        else:
            return False, 'not held'
        was = {i: s.where(i) for i in near}
        step = 0
        busy = 0
        for k in range(150):
            if not top:                 # fire tapped: 2 pictures down, 2 up
                s.v.poke(lab['dbg_joy'], [BITS['fire'] if k % 4 < 2 else 0])
            s.picture()
            if k == 6 and not top:
                s.v.screenshot(os.path.join(WORK, 'keeper-clear.png'))
            now = {i: s.where(i) for i in near}
            step = max([step] + [max(abs(now[i][0] - was[i][0]), abs(now[i][1] - was[i][1]))
                                 for i in near])
            was = now
            inside = [i for i in them if in_box(s.where(i), top)]
            if s.get('kickoff') == 0:
                s.v.poke(lab['dbg_joy'], [0])
                return busy > 3 and step <= STEP_MAX, \
                    'taken after %d pictures, the box clear %d of them, ' \
                    'steps up to %d' % (k + 1, k + 1 - busy, step)
            if inside:
                busy = k + 1
                if k > 100:
                    return False, 'still in the box: %s' % inside
        return False, 'never taken (box clear after %d pictures)' % busy
    finally:
        s.stop()


SLIDE_T = 50
SPEED_SLIDE = 1792


def slider(lab):
    s = Scene(lab)
    try:
        gy = 680
        s.obj(0, 304, gy)
        s.obj(BALL, 304, gy - 14, ty=gy + 3200, speed=1024)
        for i in range(1, 11):
            s.obj(i, 60 + 40 * i, 369)
        ctl = s.get('ctrl_b')
        run = s.get('ctx_b', 4)          # (helper_b)
        one = next(i for i in range(12, 22) if i not in (ctl, run))
        near = [i for i in range(12, 22) if i != one][:2]
        for i in range(12, 22):         # two of his nearer the ball: the
            if i != one:                # joystick's and the runner's, not he
                s.obj(i, *((290, 590) if i == near[0] else (320, 590)
                           if i == near[1] else (60 + 40 * (i % 11), 369)))
        y0 = 610
        s.obj(one, 180, y0, tx=180, ty=y0 + 1000, speed=SPEED_SLIDE, d=4)
        s.put('o_slide', one, SLIDE_T)
        s.put('o_hit', one, 0)
        s.put('o_mov', one, 1)
        s.put('o_new', one, 0)
        if 'sl_any' in lab:
            s.put('sl_any', 0, 1)
        s.put('last_team', 0, 1)
        s.put('last_pl', 0, 14)
        low = y0
        left = []
        for k in range(20):
            s.picture()
            low = max(low, s.where(one)[1])
            if one not in (s.get('ctrl_b'), s.get('ctx_b', 4)):
                left.append(s.get('o_slide', one))
            if s.get('kickoff') == 1 and s.get('rs_kind') == R_KEEPER:
                break
        else:
            return False, 'not held'
        for k in range(200):
            s.v.poke(lab['dbg_joy'], [BITS['fire'] if k % 4 < 2 else 0])
            s.picture()
            low = max(low, s.where(one)[1])
            if one not in (s.get('ctrl_b'), s.get('ctx_b', 4)):
                left.append(s.get('o_slide', one))
            if s.get('kickoff') == 0:
                s.v.poke(lab['dbg_joy'], [0])
                # three frames a picture: his tackle's frames counted down
                # while he was neither the joystick's player nor the runner
                n = min(3, len(left))
                slowed = n == 3 and left[0] - left[2] >= 5
                return slowed and low < 720, 'taken after %d pictures, he ' \
                    'slid down to y %d (from %d), his tackle %s' % (
                        k + 1, low, y0, '-'.join(map(str, left[:4])))
        return False, 'never taken: he is at %s, o_slide %d' % (
            s.where(one), s.get('o_slide', one))
    finally:
        s.stop()


def again(lab):
    s = Scene(lab)
    try:
        gy = 680
        s.obj(0, 304, gy)
        s.obj(BALL, 304, gy - 14, ty=gy + 3200, speed=1024)
        for i in range(1, 22):
            if i != 11:
                s.obj(i, 60 + 24 * (i % 11), 300 if i < 11 else 250)
        s.put('last_team', 0, 1)
        s.put('last_pl', 0, 14)
        for k in range(20):
            s.picture()
            if held(s):
                break
        else:
            return False, 'not held'
        for k in range(60):
            s.v.poke(lab['dbg_joy'], [BITS['fire'] if k % 4 < 2 else 0])
            s.picture()
            if s.get('kickoff') == 0:
                break
        else:
            return False, 'never kicked out'
        s.v.poke(lab['dbg_joy'], [0])
        s.picture()
        if s.get('last_pl') != 0:
            return False, 'kicked, but last touched by %d' % s.get('last_pl')
        # (a set piece's taker is marked, off_pl $FE: his next touch before
        # anyone else's is whistled - off_chk)
        off = s.v.mem(OFF_PL, 1)[0]
        return off != 0xFE, 'out of his hands: off_pl $%02X (%s)' % (
            off, 'marked: his next touch a double touch' if off == 0xFE
            else 'his again')
    finally:
        s.stop()


CASES = {'back': back, 'shot': shot, 'outside': outside, 'loose': loose,
         'clear': clear, 'clear-top': lambda lab: clear(lab, True),
         'slider': slider, 'again': again}


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
