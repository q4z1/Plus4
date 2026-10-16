#!/usr/bin/env python3
"""trainschedule in Yape (whose TED is closer to the real chip than VICE's):
start it from its disk, past the title and the choice of a map (fire
twice, as the test keys), switch the autopilot on, let the level run a
while at x10, and save the pictures of each. Run from trainschedule/.

    tests/yape_check.py [seconds]
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from yape import Yape  # noqa: E402

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.expanduser('~/.cache/trainschedule/test')


def labels():
    out = {}
    for line in open(os.path.join(HERE, 'build', 'trainschedule.lbl')):
        p = line.split()
        out[p[2].lstrip('.')] = int(p[1], 16)
    for n in list(out):                 # (the C's names still do)
        if not n.startswith('_'):
            out.setdefault('_' + n, out[n])
    return out


def wait_for(y, addr, value, limit=120):
    for _ in range(limit):
        if y.mem(addr, 1)[0] == value:
            return
        y.run_for(1)
    raise RuntimeError('$%04x never became %d' % (addr, value))


def fire(y, keys):
    y.poke(keys, [16])
    y.run_for(0.3)
    y.poke(keys, [0])


if __name__ == '__main__':
    secs = float(sys.argv[1]) if len(sys.argv) > 1 else 20
    L = labels()
    y = Yape(os.path.join(HERE, 'build', 'trainschedule.d64'))
    try:
        for _ in range(120):                    # the game's interrupt: it
            if y.mem(0xFFFE, 2) == [L['irq'] & 255, L['irq'] >> 8]:
                break                           # waits on the title
            y.run_for(1)
        y.run_for(2)
        y.png(os.path.join(OUT, 'yape_title.png'))
        fire(y, L['_dbg_keys'])
        wait_for(y, L['_eng_mode'], 2)          # the choice of a map
        y.run_for(3)
        y.png(os.path.join(OUT, 'yape_maps.png'))
        fire(y, L['_dbg_keys'])
        wait_for(y, L['_ptr_on'], 1)            # the level
        y.poke(L['_autopilot_on'], [1])
        y.poke(L['_speed_i'], [3])
        y.run_for(secs)
        lo, hi = y.mem(L['_clock_s'], 2)
        print('clock', lo | hi << 8)
        y.png(os.path.join(OUT, 'yape.png'))
    finally:
        y.stop()
