#!/usr/bin/env python3
"""What each part of the game's loop costs, in cycles (VICE's stopwatch,
the interrupt included): breakpoints on the parts' entries.

    tests/cost.py [dir]      dir as in shot.py: held while measuring
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, BITS, labels, run_pictures  # noqa: E402

# (eng_end to the next loop: waiting for the picture to be shown)
PARTS = ['loop', 'run_ctrl', 'follow', 'eng_begin', 'sort', 'draw', 'eng_end']


def main():
    lab = labels()
    v = Vice(PRG, WORK)
    try:
        for _ in range(200):
            v.run_for(0.1)
            if lab['main'] <= int(v.cmd('r').splitlines()[1].split()[0][2:], 16) < 0xC000:
                break
        run_pictures(v, lab, 20)
        if len(sys.argv) > 1:
            bits = 0
            for p in sys.argv[1].split('+'):
                bits |= BITS[p]
            v.poke(lab['dbg_joy'], [bits])
            run_pictures(v, lab, 20)
        for p in PARTS:
            v.cmd('break %04x' % lab[p])
        tot = {p: 0 for p in PARTS}
        last = None
        n = 0
        for _ in range(8 * len(PARTS) + 1):
            out = v.cmd('x')
            m = re.search(r'\.C:([0-9a-f]{4})', out)
            r = v.cmd('r').splitlines()[1].split()
            pc, sw = int(r[0][2:], 16), int(r[-1])
            name = [p for p in PARTS if lab[p] == pc][0]
            if last:
                tot[last[0]] += sw - last[1]
                n += last[0] == PARTS[0]
            last = (name, sw)
        for p in PARTS:
            print('%-10s %6d cycles a turn' % (p, tot[p] / max(n, 1)))
    finally:
        v.stop()


if __name__ == '__main__':
    main()
