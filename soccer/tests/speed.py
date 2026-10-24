#!/usr/bin/env python3
"""How fast the game draws: pictures shown (50 a second) per turn of its
loop, standing and running with the view scrolling.

    tests/speed.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, labels, run_pictures  # noqa: E402


def measure(v, lab, n=200):
    f0 = v.mem(lab['frames'], 1)[0]
    t0 = v.mem(lab['tick'], 1)[0]
    run_pictures(v, lab, n)
    f1 = v.mem(lab['frames'], 1)[0]
    t1 = v.mem(lab['tick'], 1)[0]
    return ((f1 - f0) & 255) / max(1, (t1 - t0) & 255)


def main():
    lab = labels()
    v = Vice(PRG, WORK, warp=False)     # (in warp, 256 pictures can pass between
                                        # two looks, and the counters wrap)
    try:
        for _ in range(200):
            v.run_for(0.1)
            if lab['main'] <= int(v.cmd('r').splitlines()[1].split()[0][2:], 16) < 0xC000:
                break
        run_pictures(v, lab, 20)
        print('standing:          %.2f pictures per turn' % measure(v, lab))
        for name, bits in (('running right', 8), ('running right, fast', 8 + 16),
                           ('running down-left, fast', 2 + 4 + 16)):
            v.poke(lab['dbg_joy'], [bits])
            print('%-19s%.2f pictures per turn' % (name + ':', measure(v, lab)))
    finally:
        v.stop()


if __name__ == '__main__':
    main()
