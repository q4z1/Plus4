#!/usr/bin/env python3
"""Half time and full time (play.s clock, spot, new_match; simple-soccer.s
place), scenes set up through the monitor in a match in VICE.

    tests/fulltime.py [case ...]

half     the 45th minute, the ball near a goal: no whistle 40 pictures
         on; the ball in the middle: half time (Luca: 90 minutes and the
         end of the action)
full     the same at 90: full time only once the ball is in the middle
         half; then one of them lying (as after a slide) is up again, all
         22 walk to their places round the middle circle (ft_dx, ft_dy),
         mixed, and the view goes to the middle spot, not the ball left
         near the goal; the score 10 - 12 in two figures each;
         screenshot fulltime.png

A line each, OK or WRONG; the exit code counts the wrong ones.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from keep import Scene, BALL  # noqa: E402
from shot import labels  # noqa: E402

CACHE = os.path.expanduser('~/.cache/simple-soccer')
FT_DX = [11, 67, -23, 88, -79, -74, 51, -27, -49, -93, -47]
FT_DY = [-28, -39, 57, -30, -43, -3, 22, -56, 3, 3, 49]
FT = [(304 + x, 369 + y) for x, y in zip(FT_DX, FT_DY)] + \
     [(304 - x, 369 - y) for x, y in zip(FT_DX, FT_DY)]
CAM_X = (304 - 23 - (40 * 4 - 8)) & 0xFE        # (follow: the middle spot's)


def wait_end(s, flag, minute):
    """the minute set, the ball near the top goal: no whistle; in the
    middle: the whistle"""
    s.put('game_min', 0, minute)
    s.put('min_t', 0, 0)
    s.put('half', 0, 1 if minute == 90 else 0)
    s.obj(BALL, 200, 120)
    for k in range(40):
        s.picture()
        if s.get(flag):
            return False, 'whistled after %d pictures, the ball at y %d' % (k, s.where(BALL)[1])
        s.obj(BALL, 200, 120)
    s.obj(BALL, 300, 380)
    for k in range(10):
        s.picture()
        if s.get(flag):
            return True, 'none near the goal, at once in the middle (%d pictures)' % k
    return False, 'no whistle with the ball in the middle'


def half(lab):
    s = Scene(lab)
    try:
        return wait_end(s, 'half', 45)
    finally:
        s.stop()


def full(lab):
    s = Scene(lab)
    try:
        ok, text = wait_end(s, 'full', 90)
        if not ok:
            return ok, text
        s.put('score', 0, 10)
        s.put('score', 1, 12)
        s.obj(BALL, 120, 640)           # (the ball left down near a goal)
        s.put('o_slide', 5, 1)          # (one lying)
        up = None
        for k in range(400):
            s.picture()
            if up is None and s.get('o_slide', 5) == 0:
                up = k
        far = [(i, s.where(i)) for i in range(22)
               if abs(s.where(i)[0] - FT[i][0]) > 6 or abs(s.where(i)[1] - FT[i][1]) > 6]
        cam = s.get('cam_x') | s.get('cam_x', 1) << 8
        s.v.screenshot(os.path.join(CACHE, 'fulltime.png'))
        ok = up is not None and not far and abs(cam - CAM_X) <= 2 and s.get('full') == 1
        return ok, '%s; up after %s pictures; not at their places: %s; the view at x %d ' \
            '(the middle spot\'s %d), y %d' % (
                text, up, far or 'none', cam, CAM_X, s.get('cam_y') | s.get('cam_y', 1) << 8)
    finally:
        s.stop()


CASES = {'half': half, 'full': full}


def main():
    lab = labels()
    names = sys.argv[1:] or list(CASES)
    wrong = 0
    for name in names:
        ok, text = CASES[name](lab)
        print('%-8s %s %s' % (name, text, 'OK' if ok else 'WRONG'))
        wrong += not ok
    sys.exit(wrong)


if __name__ == '__main__':
    main()
