#!/usr/bin/env python3
"""The crowd's "oh" (Luca): at a near miss - fast, just wide of a post
(NEAR_W) or over the bar - and at the keeper's save of the other team's
fast ball; not for a slow ball out, one far wide, the keeper's slow
catch. The ball rolled over the top goal line or at the bottom keeper,
each frame looked at: what voice 1 starts (sound.s: fx_ooh, fx_save).

    tests/crowd.py

A line each; the exit code counts the wrong ones.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from keep import Scene, BALL  # noqa: E402
from shot import labels  # noqa: E402

# (name, the ball's x, its height, speed, the sound wanted)
MISSES = [('wide-left', 252, 0, 1536, 'miss'), ('wide-right', 360, 0, 1536, 'miss'),
          ('over', 304, 24, 1536, 'miss'), ('far', 230, 0, 1536, None),
          ('slow', 262, 0, 512, None), ('goal', 304, 0, 1536, 'goal')]
R_KEEPER = 4                    # (play.s: the keeper has the ball)
SAVES = [('save', 1792, 'save'), ('soft', 768, None)]


def heard(s, lab):
    """the effect just started on voice 1, if any"""
    p = s.get('v_lo', 1) + 256 * s.get('v_hi', 1)
    if p in (lab['fx_save'] + 3, lab['fx_save'] + 6):  # (its thump: two steps
        return 'save'                                   # of a frame)
    for name, t in (('miss', 'fx_ooh'), ('goal', 'fx_goal')):
        if p == lab[t] + 4:
            return name
    return None


def quiet(s):
    for y in (0, 1):
        s.put('v_lo', y, 0)
        s.put('v_hi', y, 0)
        s.put('v_lo', 4 + y, 0)         # (v_left)
    s.put('v_crowd', 0, 0)


def miss(lab, x, z, speed):
    s = Scene(lab)
    try:
        s.v.cmd('del')
        s.v.cmd('break %04x' % lab['play_frame'])
        s.obj(0, 100, 700)
        s.obj(11, 560, 60)
        for i in list(range(1, 11)) + list(range(12, 22)):
            s.obj(i, 40 + 20 * (i % 11), 400)
        s.obj(BALL, x, 58, tx=x, ty=-200, speed=speed)
        s.put('o_zl', BALL, z)
        s.put('last_team', 0, 0)
        s.put('last_pl', 0, 9)
        quiet(s)
        got = None
        for _ in range(30):
            s.v.cmd('x')
            got = got or heard(s, lab)
            if s.get('dead_t'):
                break
        return got
    finally:
        s.stop()


def save(lab, speed):
    s = Scene(lab)
    try:
        s.v.cmd('del')
        s.v.cmd('break %04x' % lab['play_frame'])
        s.obj(0, 304, 680)
        s.obj(BALL, 304, 620, ty=700 + 32 * 100, speed=speed)
        s.put('last_team', 0, 1)
        s.put('last_pl', 0, 18)
        quiet(s)
        got = None
        for _ in range(90):
            s.v.cmd('x')
            got = got or heard(s, lab)
            if s.get('rs_kind') == R_KEEPER and s.get('kickoff'):       # (held)
                break
        return got, s.get('rs_kind'), s.get('kickoff')
    finally:
        s.stop()


def main():
    lab = labels()
    wrong = 0
    for name, x, z, speed, want in MISSES:
        got = miss(lab, x, z, speed)
        ok = got == want
        wrong += not ok
        print('%-10s x %3d, %2d high, %4d: %-5s %s' % (name, x, z, speed, got or '-',
                                                     'ok' if ok else 'WRONG'), flush=True)
    for name, speed, want in SAVES:
        got, rs, ko = save(lab, speed)
        ok = got == want and rs == R_KEEPER and ko
        wrong += not ok
        print('%-10s caught, %4d: %-5s (held: %s)  %s' % (name, speed, got or '-', rs == R_KEEPER and ko == 1,
                                                       'ok' if ok else 'WRONG'), flush=True)
    return wrong


if __name__ == '__main__':
    sys.exit(main())
