#!/usr/bin/env python3
"""How long the disk takes, in VICE's own time: from the machine's start to
the title (its music's interrupt in the zero page, the screen on).

    tests/loadtime.py [drive]      drive: 1541 (the default), 1551, 1571 ...

VICE runs in warp; the time is its CPU clock read with the monitor's
stopwatch, at the TED's 1.77 MHz.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
D64 = os.path.join(HERE, '..', 'build', 'simple-soccer.d64')
CACHE = os.path.expanduser('~/.cache/simple-soccer')
CLOCK = 1773447


def main():
    drive = sys.argv[1] if len(sys.argv) > 1 else '1541'
    v = Vice(D64, CACHE, drive=drive, title=True)
    try:
        v.cmd('sw reset')
        for _ in range(1500):
            if v.mem(0xFFFF, 1)[0] == 0 and v.mem(0xFF06, 1)[0] == 0x1B:
                out = v.cmd('sw')
                print(f'{drive}: title after {int(re.findall(r"[0-9]{3,}", out)[0]) / CLOCK:5.1f} s')
                v.screenshot(os.path.join(CACHE, 'loadtime.png'))
                return
            v.run_for(0.1)
        raise RuntimeError('no title')
    finally:
        v.stop()


if __name__ == '__main__':
    main()
