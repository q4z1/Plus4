#!/usr/bin/env python3
"""Simple Soccer in Yape (without a window): a screenshot after some
seconds, with directions held first as in shot.py.

    tests/yape_shot.py [seconds] [out.png] [dir=seconds ...] [--title]

--title: the title stays (else the test's marker skips it).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from yape import Yape  # noqa: E402
from shot import PRG, WORK, BITS, labels  # noqa: E402


def main():
    title = '--title' in sys.argv
    sys.argv = [a for a in sys.argv if a != '--title']
    secs = float(sys.argv[1]) if len(sys.argv) > 1 else 3
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(WORK, 'yape.png')
    os.makedirs(os.path.dirname(out), exist_ok=True)
    lab = labels()
    y = Yape(PRG, title=title)
    try:
        y.run_for(4)                    # loading and the start
        for a in sys.argv[3:]:
            d, n = a.split('=')
            bits = 0
            for p in d.split('+'):
                bits |= BITS[p]
            y.poke(lab['dbg_joy'], [bits])
            y.run_for(float(n))
            y.poke(lab['dbg_joy'], [0])
        y.run_for(secs)
        print(y.png(out))
    finally:
        y.stop()


if __name__ == '__main__':
    main()
