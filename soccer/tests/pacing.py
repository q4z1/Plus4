#!/usr/bin/env python3
"""Do the pictures come evenly? The frames between one picture put on
screen and the next (the interrupt's swap), counted while the player
runs, and how often each gap came.

    tests/pacing.py [dir] [swaps] [--fixed]     dir as in shot.py

--fixed: the direction held from the program's start, the first 40
pictures left out - the same match each time, to compare builds.
"""
import collections
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, BITS, labels, run_pictures, held_from_start  # noqa: E402


def main():
    fixed = '--fixed' in sys.argv
    args = [a for a in sys.argv[1:] if a != '--fixed']
    d = args[0] if len(args) > 0 else 'up'
    n = int(args[1]) if len(args) > 1 else 100
    lab = labels()
    v = Vice(PRG, WORK)
    try:
        if fixed:
            held_from_start(v, lab, d)
            v.cmd('watch store %04x' % lab['shown'])
            for _ in range(40):
                v.cmd('x')
            return count(v, lab, n)
        for _ in range(200):
            v.run_for(0.1)
            if lab['main'] <= int(v.cmd('r').splitlines()[1].split()[0][2:], 16) < 0xC000:
                break
        run_pictures(v, lab, 20)
        bits = 0
        for p in d.split('+'):
            bits |= BITS.get(p, 0)
        v.poke(lab['dbg_joy'], [bits])
        run_pictures(v, lab, 20)
        v.cmd('watch store %04x' % lab['shown'])
        count(v, lab, n)
    finally:
        v.stop()


def count(v, lab, n):
    gaps = collections.Counter()
    last = None
    for _ in range(n):
        v.cmd('x')
        f = v.mem(lab['frames'], 1)[0]
        if last is not None:
            gaps[(f - last) & 255] += 1
        last = f
    for g in sorted(gaps):
        print('%d frames: %d times' % (g, gaps[g]))


if __name__ == '__main__':
    main()
