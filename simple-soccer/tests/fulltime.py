#!/usr/bin/env python3
"""Half time and full time (play.s clock, spot, new_match; simple-soccer.s
place), scenes set up through the monitor in a match in VICE.

    tests/fulltime.py [case ...]

half     the 45th minute, the ball near a goal: no whistle 40 pictures
         on, the score and the minute shown (at 44 not); then 45 through
         the break till the kick-off (Luca: the second half began at 46); the ball in the middle: half time (Luca: 90 minutes and the
         end of the action)
full     the same at 90: full time only once the ball is in the middle
         half; then one of them lying (as after a slide) is up again, the
         crowd roars, the teams stand where they are some 2 seconds
         (STAND_T: no one moves from the 10th picture to the 30th), then
         all 22 walk off into the tunnel between the benches on the
         halfway line (ft_spot, TUN_X: Luca) - one sent off before
         counted as gone too (the view stuck on the benches), the view
         going there - each gone there (o_off $81), full one less, 23 to 1;
         then the view to the middle spot, up and down to the very middle
         (Luca: it stopped CAM_DZ higher), and the score 10 - 12, in two
         figures each, in the middle of it (draw_hud: HUD_MID); the crowd
         murmuring on and on till fire (new_match: voice 1 never quiet
         150 pictures after all are gone - Luca);
         screenshots fulltime-stand.png, fulltime-benches.png, fulltime-tunnel.png
         (half of them gone), fulltime.png
foul     a foul in the middle at 90 minutes, the computer's free kick: no
         full time while the ball is dead nor while the kick waits - it
         is taken and played out, then the whistle, the reason gone (Luca:
         full time at once, FOUL still shown)

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
    middle: the whistle - the score and the minute shown from the minute
    on, not before it (Luca: the time up, the ball in play)"""
    s.put('game_min', 0, minute - 1)
    s.put('min_t', 0, 0)
    s.put('half', 0, 1 if minute == 90 else 0)
    s.obj(BALL, 200, 120)
    s.picture()
    if s.get('hud'):
        return False, 'the score shown at %d minutes, the ball in play' % (minute - 1)
    s.put('game_min', 0, minute)
    s.put('min_t', 0, 0)
    s.put('half', 0, 1 if minute == 90 else 0)
    s.obj(BALL, 200, 120)
    for k in range(40):
        s.picture()
        if s.get(flag):
            return False, 'whistled after %d pictures, the ball at y %d' % (k, s.where(BALL)[1])
        s.obj(BALL, 200, 120)
    if not s.get('hud'):
        return False, 'the time up, the score not shown'
    s.obj(BALL, 300, 380)
    for k in range(10):
        s.picture()
        if s.get(flag):
            return True, 'none near the goal (the score shown), at once in the middle (%d pictures)' % k
    return False, 'no whistle with the ball in the middle'


def half(lab):
    s = Scene(lab)
    try:
        s.put('min_frames', 0, 100)             # (3 minutes a match: fewer frames to a
        ok, text = wait_end(s, 'half', 45)      # minute than the break has)
        if not ok:
            return ok, text
        for k in range(400):
            s.picture()
            if s.get('game_min') != 45:
                return False, text + '; minute %d in the break' % s.get('game_min')
            if s.get('kickoff'):
                return True, text + '; 45 through the break, till the kick-off (%d pictures)' % k
        return False, text + '; no kick-off'
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
        s.put('o_off', 14, 1)           # (one sent off before: counted too -
                                        # full stuck at 2 once, Luca saw)
        up, gone, benches, quiet = None, None, 0, 0
        tun = os.path.join(CACHE, 'fulltime-tunnel.png')
        if os.path.exists(tun):
            os.remove(tun)
        pos = lambda: [s.where(i) for i in range(22) if i not in (5, 14)]    # noqa: E731
        for k in range(1500):
            s.picture()
            if up is None and s.get('o_slide', 5) == 0:
                up = k
            if k == 10:
                p10 = pos()
            if k == 30:
                moved = [i for i, (a, b) in enumerate(zip(p10, pos())) if a != b]
                s.v.screenshot(os.path.join(CACHE, 'fulltime-stand.png'))
            if gone is not None and k > gone and not s.get('v_left', 1):
                quiet += 1
            cam = s.get('cam_x') | s.get('cam_x', 1) << 8
            if s.get('full') > 1 and cam > BENCH_CAM:
                benches += 1
                if benches == 1:
                    s.v.screenshot(os.path.join(CACHE, 'fulltime-benches.png'))
            if s.get('full') == 12 and not os.path.exists(tun):
                s.v.screenshot(tun)
            if gone is None and s.get('full') == 1:
                gone = k
            if gone is not None and k > gone + 150:
                break
        left = [i for i in range(22) if not s.get('o_off', i) & 1]
        cam = s.get('cam_x') | s.get('cam_x', 1) << 8
        cam_y = s.get('cam_y') | s.get('cam_y', 1) << 8
        s.v.screenshot(os.path.join(CACHE, 'fulltime.png'))
        ok = up is not None and first == 23 and gone is not None and not left and benches > 0 \
            and abs(cam - CAM_X) <= 2 and cam_y == CAM_Y and not moved and not quiet
        return ok, '%s; full %d at first; up after %s pictures; standing from the 10th picture to ' \
            'the 30th (moved: %s); all gone after %s (still on: %s); the view on the benches %d ' \
            'pictures, at last at x %d (the middle spot\'s %d), y %d (%d); the crowd quiet %d ' \
            'pictures after' % (text, first, up, moved or 'none', gone, left or 'none', benches,
                               cam, CAM_X, cam_y, CAM_Y, quiet)
    finally:
        s.stop()


def foul(lab):
    s = Scene(lab)
    try:
        s.put('game_min', 0, 90)
        s.put('min_t', 0, 0)
        s.put('half', 0, 1)
        s.obj(BALL, 300, 380)
        s.put('rs_kind', 0, 5)          # (R_FREE, the yellow team's)
        s.put('rs_team', 0, 1)
        s.v.poke(lab['rs_x'], [300 & 255, 300 >> 8])
        s.v.poke(lab['rs_y'], [380 & 255, 380 >> 8])
        s.put('why', 0, 1)              # (WHY_FOUL)
        s.put('dead_t', 0, 40)
        taken = None
        for k in range(600):
            s.picture()
            if taken is None and k > 2 and not s.get('dead_t') and not s.get('kickoff'):
                taken = k
            if s.get('full'):
                ok = taken is not None and not s.get('why')
                return ok, 'full time after %d pictures, the free kick taken after %s, the reason ' \
                    'shown %d' % (k, taken, s.get('why'))
        return False, 'no full time in 600 pictures (the kick taken after %s)' % taken
    finally:
        s.stop()


CASES = {'half': half, 'full': full, 'foul': foul}


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
