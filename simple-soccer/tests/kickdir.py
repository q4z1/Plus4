#!/usr/bin/env python3
"""The stick at the very first kick-off (Luca: the directional engine fails
at the very first kick-off) - a match started as a player starts it: from
a copy of the disk in Yape, the title, fire. At the kick-off the stick is
pushed each way in turn: the way the taker (the cyan 9) faces then; last
the pass, fire tapped with the stick pushed, and the way the ball goes.

    tests/kickdir.py [way] [--port2]   (way: the pass's, default up+left,
                                        down+left back to a team-mate
                                        behind, none: the stick let go; --port2:
                                        the stick in port 2 throughout)

A line each; OK or WRONG last, the exit code 1 if wrong.
"""
import math
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import moves  # noqa: E402
from yape import Yape  # noqa: E402

# the stick's ways and the way (0 up, 1 up-right ... 7 up-left) he should
# face: any way, the joystick's kick-off as a free kick (Luca: to the
# team-mates behind too; up to 90 degrees off as Sensible Soccer's before)
WAYS = [('up', 0), ('up+right', 1), ('right', 2), ('down+right', 3), ('up', 0),
        ('down', 4), ('down+left', 5), ('left', 6), ('up+left', 7)]
TAKER = 9
BALL = 22


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    pass_way = args[0] if args else 'up+left'
    port = 'dbg_joyb' if '--port2' in sys.argv else 'dbg_joy'
    lab = moves.labels()
    img = os.path.join(moves.WORK, 'kickdir.d64')
    subprocess.run(['cp', moves.D64, img], check=True)
    y = Yape(img, title=True, env=('SDL_AUDIODRIVER=dummy',))

    def wait(test, what, secs=180):
        t = time.time()
        while not test():
            if time.time() - t > secs:
                raise RuntimeError('waited in vain: ' + what)
            time.sleep(0.3)

    def ball():
        xl, = y.mem(lab['o_xl'] + BALL, 1)
        xh, = y.mem(lab['o_xh'] + BALL, 1)
        yl, = y.mem(lab['o_yl'] + BALL, 1)
        yh, = y.mem(lab['o_yh'] + BALL, 1)
        return xl + 256 * xh, yl + 256 * yh
    ok = True
    try:
        wait(lambda: y.mem(0xfffe, 2) == [lab['synth'], 0] and y.mem(0xff06, 1)[0] == 0x1b, 'the title')
        time.sleep(1)
        y.poke(lab[port], [moves.bits('fire')])
        time.sleep(0.15)
        y.poke(lab[port], [0])
        wait(lambda: y.mem(0xFFFE, 2)[1] != 0 and y.mem(0xFF07, 1)[0] & 0x10
             and y.mem(0xFF06, 1)[0] & 0x10, 'the match')
        time.sleep(1.5)
        print('kick-off %d, set piece %d, taker %d, rs_team %d, flip %d, ctrl %d, K_HOME %d' % (
            y.mem(lab['kickoff'], 1)[0], y.mem(lab['rs_kind'], 1)[0], y.mem(lab['taker'], 1)[0],
            y.mem(lab['rs_team'], 1)[0], y.mem(lab['flip'], 1)[0], y.mem(lab['ctrl'], 1)[0],
            y.mem(0xFCEF, 1)[0]))
        print('offer %d (255: no one offering)' % y.mem(lab['offer'], 1)[0])
        for stick, want in WAYS:
            y.poke(lab[port], [moves.bits(stick)])
            time.sleep(0.5)
            d, = y.mem(lab['o_dir'] + TAKER, 1)
            good = d == want
            ok = ok and good
            print('%-11s faces %d (want %d)  %s' % (stick, d, want, 'ok' if good else 'WRONG'), flush=True)
        y.poke(lab[port], [moves.bits(pass_way)])
        time.sleep(0.5)
        d, = y.mem(lab['o_dir'] + TAKER, 1)
        x0, y0 = ball()
        y.poke(lab[port], [moves.bits(pass_way + '+fire')])
        time.sleep(0.03)                # (a tap: held SHOT_HOLD it is a shot)
        y.poke(lab[port], [moves.bits(pass_way)])
        time.sleep(0.1)
        y.poke(lab[port], [0])
        t = time.time()                 # (its first 12 pixels or more: later
        while time.time() - t < 1.0:    # the other team may have it)
            x1, y1 = ball()
            if (x1 - x0) ** 2 + (y1 - y0) ** 2 > 144:
                break
        ang = (math.degrees(math.atan2(x1 - x0, y0 - y1)) + 360) % 360 if (x1, y1) != (x0, y0) else None
        want = d * 45
        good = ang is not None and min(abs(ang - want), 360 - abs(ang - want)) <= 60
        ok = ok and good
        print('pass %s: faced %d, the ball (%d,%d) -> (%d,%d), %s degrees (want about %d)  %s' % (
            pass_way, d, x0, y0, x1, y1, 'no move' if ang is None else '%.0f' % ang, want,
            'ok' if good else 'WRONG'))
        print('kick-off %d, last %d/%d' % (y.mem(lab['kickoff'], 1)[0], y.mem(lab['last_team'], 1)[0],
                                          y.mem(lab['last_pl'], 1)[0]))
    finally:
        y.stop()
        os.remove(img)
    print('OK' if ok else 'WRONG')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
