#!/usr/bin/env python3
"""How long the disk takes, in VICE's own time: from the machine's start to
the title, to the choice of a map, to the level.

    tests/loadtime.py [drive]      drive: 1541 (the default), 1551, 1571 ...

Run from trainschedule/. VICE runs in warp; the times are its CPU clock
read with the monitor's stopwatch, at the TED's 1.77 MHz.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shot import PRG, WORK, labels  # noqa: E402
from vice import Vice  # noqa: E402

CLOCK = 1773447


def main():
    drive = sys.argv[1] if len(sys.argv) > 1 else '1541'
    lbl = labels()
    v = Vice(PRG, WORK, drive=drive)
    try:
        v.cmd('sw reset')

        def now():
            out = v.cmd('sw')
            if '-v' in sys.argv:
                print(repr(out))
            return int(re.findall(r'\d{3,}', out)[0]) / CLOCK

        def wait_for(name, value, limit=600):
            for _ in range(limit):
                if v.mem(lbl[name], 1)[0] == value:
                    return now()
                v.run_for(0.2)
            raise RuntimeError(f'{name} never became {value}')

        t = wait_for('_eng_mode', 1)
        print(f'title after {t:5.1f} s')
        v.poke(lbl['_dbg_keys'], [16])
        v.run_for(0.3)
        v.poke(lbl['_dbg_keys'], [0])
        t2 = wait_for('_eng_mode', 2)
        print(f'map list after {t2:5.1f} s')
        v.run_for(0.5)
        v.poke(lbl['_dbg_keys'], [16])
        v.run_for(0.3)
        v.poke(lbl['_dbg_keys'], [0])
        t3 = wait_for('_ptr_on', 1)
        print(f'level after {t3:5.1f} s')
        v.screenshot(os.path.join(WORK, 'loadtime.png'))
    finally:
        v.stop()


if __name__ == '__main__':
    main()
