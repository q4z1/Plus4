#!/usr/bin/env python3
"""Half time and full time (play.s clock, spot, new_match; simple-soccer.s
place), scenes set up through the monitor in a match in VICE.

    tests/fulltime.py [case ...]

half     the 45th minute, the ball near a goal: no whistle 40 pictures
         on; the ball in the middle: half time (Luca: 90 minutes and the
         end of the action)
full     the same at 90: full time only once the ball is in the middle
         half; then one of them lying (as after a slide) is up again, the
         crowd roars, and all 22 walk off to the benches past the right
         touch line on the halfway line (ft_spot, TUN_X: Luca), the view
         going there - each gone there (o_off 1), full one less, 23 to 1;
         then the view to the middle spot, up and down to the very middle
         (Luca: it stopped CAM_DZ higher), and the score 10 - 12, in two
         figures each, in the middle of it (draw_hud: HUD_MID);
         screenshots fulltime-benches.png, fulltime.png

A line each, OK or WRONG; the exit code counts the wrong ones.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from keep import Scene, BALL  # noqa: E402
from shot import labels  # noqa: E402

CACHE = os.path.expanduser('~/.cache/simple-soccer')
CAM_X = (304 - 23 - (40 * 4 - 8)) & 0xFE        # (follow: the middle spot's)
CAM_Y = 369 + 58 - 88                           # (and the middle of the rows shown)
BENCH_CAM = 304                                 # (the view past this: on the benches)


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
        first = s.get('full')
        s.put('score', 0, 10)
        s.put('score', 1, 12)
        s.obj(BALL, 120, 640)           # (the ball left down near a goal)
        s.put('o_slide', 5, 1)          # (one lying)
        up, gone, benches = None, None, 0
        for k in range(1500):
            s.picture()
            if up is None and s.get('o_slide', 5) == 0:
                up = k
            cam = s.get('cam_x') | s.get('cam_x', 1) << 8
            if s.get('full') > 1 and cam > BENCH_CAM:
                benches += 1
                if benches == 1:
                    s.v.screenshot(os.path.join(CACHE, 'fulltime-benches.png'))
            if gone is None and s.get('full') == 1:
                gone = k
            if gone is not None and k > gone + 120:
                break
        left = [i for i in range(22) if s.get('o_off', i) != 1]
        cam = s.get('cam_x') | s.get('cam_x', 1) << 8
        cam_y = s.get('cam_y') | s.get('cam_y', 1) << 8
        s.v.screenshot(os.path.join(CACHE, 'fulltime.png'))
        ok = up is not None and first == 23 and gone is not None and not left and benches > 0 \
            and abs(cam - CAM_X) <= 2 and cam_y == CAM_Y
        return ok, '%s; full %d at first; up after %s pictures; all gone after %s (still on: %s); ' \
            'the view on the benches %d pictures, at last at x %d (the middle spot\'s %d), y %d (%d)' % (
                text, first, up, gone, left or 'none', benches, cam, CAM_X, cam_y, CAM_Y)
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
