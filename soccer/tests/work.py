#!/usr/bin/env python3
"""The work of each turn of the loop, without its wait for a picture to
be shown: VICE's stopwatch from loop to eng_end, for some turns while a
direction is held from the kick-off; their mean and the most. Two
frames' time is 71k, three 106k.

    tests/work.py [dir] [turns]
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, BITS, labels, run_pictures  # noqa: E402


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else 'up'
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 30
    lab = labels()
    v = Vice(PRG, WORK, warp=False)
    try:
        for _ in range(60):
            v.run_for(0.1)
        run_pictures(v, lab, 10)
        bits = 0
        for p in d.split('+'):
            bits |= BITS.get(p, 0)
        v.poke(lab['dbg_joy'], [bits])
        v.cmd('break %04x' % lab['loop'])
        v.cmd('break %04x' % lab['eng_end'])
        t0 = None
        works = []
        while len(works) < n:
            v.cmd('x')
            r = v.cmd('r').splitlines()[1].split()
            pc, sw = int(r[0][2:], 16), int(r[-1])
            if pc == lab['loop']:
                t0 = sw
            elif t0 is not None:
                works.append(sw - t0)
                t0 = None
        print('%s: mean %d, most %d, least %d' % (d, sum(works) / len(works), max(works), min(works)))
        print(' '.join('%d' % (w // 1000) for w in works))
    finally:
        v.stop()


if __name__ == '__main__':
    main()
