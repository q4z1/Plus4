#!/usr/bin/env python3
"""The PAL colour phase in a match, in plus4emu (the one emulator that
decodes it: VICE and Yape do not) - the cyan stick pushed round all ways
so the view scrolls, each picture's most common colour on the pitch
looked at. engine.s cuts the picture short: the line counter ($FF1D) on
16 at the cut, 16 back in the border. Jumped one more - the counter read,
the line over, then written - two lines had one phase and the frame 313
lines: an old PAL decoder (Luca's Commodore 1701) took a while to catch
up, red flashes as the view moved.

    tests/palphase.py [pictures]

A line for each picture whose pitch is not the grass's green, its
picture to ~/.cache/simple-soccer/test/pal_<n>.png; the exit code counts
them (255 at most).
"""
import collections
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                '..', '..', 'paradroid', 'tests'))
from p4emu import P4emu  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.expanduser('~/.cache/simple-soccer/test')
BITS = {'up': 1, 'down': 2, 'left': 4, 'right': 8, 'fire': 16}
WAYS = [1, 9, 8, 10, 2, 6, 4, 5]


def labels():
    out = {}
    for line in open(os.path.join(HERE, '..', 'build', 'simple-soccer.lbl')):
        p = line.split()
        out[p[2].lstrip('.')] = int(p[1], 16)
    return out


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 600
    lab = labels()
    os.makedirs(OUT, exist_ok=True)
    e = P4emu(os.path.join(HERE, '..', 'build', 'simple-soccer.prg'))
    wrong = 0
    try:
        e.run_for(6)                            # (the title)
        e.poke(lab['dbg_joy'], [BITS['fire']])
        e.run_for(0.3)
        e.poke(lab['dbg_joy'], [0])
        e.run_for(6)                            # (the match's start)
        green = None
        seen = collections.Counter()
        for i in range(n):
            e.poke(lab['dbg_joy'], [WAYS[(i // 25) % len(WAYS)]])
            e.frame()
            pix = e.pixels()
            c = collections.Counter(pix[y][x] for y in range(110, 230, 4)
                                    for x in range(60, 330, 4)).most_common(1)[0][0]
            if green is None:
                green = c
            seen[c] += 1
            if c != green:
                wrong += 1
                if wrong <= 20:
                    print('picture %d: the pitch %s, not %s' % (i, c, green), flush=True)
                    e.png(os.path.join(OUT, 'pal_%d.png' % i))
        print('%d pictures, %d with the pitch not green; colours %s' % (
            n, wrong, seen.most_common(4)))
    finally:
        e.stop()
    return min(wrong, 255)


if __name__ == '__main__':
    sys.exit(main())
