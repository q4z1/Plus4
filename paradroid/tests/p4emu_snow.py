#!/usr/bin/env python3
"""p4emu_snow.py [pictures] - "snow" in the title, in plus4emu: the real
TED shows a pixel of colour $7F where one of its colour registers is
written while it draws (plus4emu does too; VICE and Yape do not). Counts
such pixels in each picture of the title's round, from the logo on, by
where they are; the first picture with them goes to
~/.cache/paradroid/test/snow_<n>.png. (A pixel of $7F on its own: none
of the title's pictures has that colour.)"""
import os, sys, collections
sys.path.insert(0, os.path.dirname(__file__))
from p4emu import P4emu
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.expanduser('~/.cache/paradroid/test')
n = int(sys.argv[1]) if len(sys.argv) > 1 else 1200
SNOW = (214, 255, 161)                  # $7F as plus4emu's decoder draws it
e = P4emu(os.path.join(HERE, '..', 'build', 'paradroid.prg'))
try:
    e.frame(300)                        # (unpacked, the logo coming)
    pos = collections.Counter()
    pics = 0
    for i in range(n):
        e.frame()
        p = e.pixels()
        pts = [(y, x) for y in range(0, 288) for x in range(384) if p[y][x] == SNOW]
        if pts:
            if not pics:
                e.png(os.path.join(OUT, 'snow_%d.png' % i))
            pics += 1
            pos.update(pts)
    print('%d of %d pictures with snow' % (pics, n))
    for (y, x), c in sorted(pos.items()):
        print('  line %3d, column %3d: %d pictures' % (y, x, c))
finally:
    e.stop()
