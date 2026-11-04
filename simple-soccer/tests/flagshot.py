#!/usr/bin/env python3
"""The title's flags from the disk, in Yape: a picture of the title as it
comes up, then the home team moved on to HOME and the away team to AWAY
(as many steps right), a picture each, and a series of pictures over the
last change, one a frame - each flag in its own second shared colour, no
picture with the wrong one.

    tests/flagshot.py [home steps] [away steps] [--series]

(--series: only the series - Yape's pictures go one way or the other)

Pictures: ~/.cache/simple-soccer/test/flag_*.png
"""
import glob
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from yape import Yape, SHOT, host, ppm_to_png  # noqa: E402
from shot import labels, BITS, WORK  # noqa: E402

D64 = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'build', 'simple-soccer.d64')
SERIES = 40


def main():
    home = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    away = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    series = '--series' in sys.argv
    lab = labels()
    y = Yape(D64, warp=True, series=SERIES if series else 0, title=True)
    try:
        t0 = time.time()
        while time.time() - t0 < 180:       # loading: till the title is on
            time.sleep(1)
            if y.mem(0xfffe, 2) == [lab['synth'], 0] and y.mem(0xff06, 1)[0] == 0x1b:
                break
        time.sleep(2)
        if not series:
            y.png(os.path.join(WORK, 'flag_title.png'))

        def press(d):
            y.poke(lab['dbg_joy'], [BITS[d]])
            time.sleep(0.12)
            y.poke(lab['dbg_joy'], [0])
            time.sleep(0.25)
        for _ in range(3):                  # down to the home team
            press('down')
        for _ in range(home):
            press('right')
        press('down')
        for _ in range(away - 1):
            press('right')
        time.sleep(1)
        if not series:
            y.png(os.path.join(WORK, 'flag_chosen.png'))
        else:                               # the last step, frame by frame:
            for f in glob.glob(SHOT + '.*'):    # pressed once the series runs
                os.remove(f)
            host('pkill', '-USR2', '-x', 'yapesdl')
            time.sleep(0.1)
            press('right')
            t0 = time.time()
            while len(glob.glob(SHOT + '.[0-9]*')) < SERIES and time.time() - t0 < 60:
                time.sleep(0.5)
            time.sleep(1)
            names = []
            for f in sorted(glob.glob(SHOT + '.[0-9][0-9][0-9]')):
                names.append(os.path.join(WORK, 'flag_s%s.png' % f[-3:]))
                ppm_to_png(f, names[-1])
            print('%d pictures in the series' % len(names))
    finally:
        y.stop()


if __name__ == '__main__':
    main()
