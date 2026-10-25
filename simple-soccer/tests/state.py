#!/usr/bin/env python3
"""The match's state while directions are held: the joystick's player
and the ball (place, speed, height) every few pictures.

    tests/state.py dir=pictures ...      dir as in shot.py, 'none' for none
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, BITS, labels, run_pictures  # noqa: E402

BALL = 22


def obj(v, lab, i):
    g = lambda n: v.mem(lab[n] + i, 1)[0]
    x = g('o_xl') + 256 * g('o_xh')
    y = g('o_yl') + 256 * g('o_yh')
    sp = g('o_spl') + 256 * v.mem(lab['o_sph'] + i, 1)[0]
    return x, y, g('o_zl'), sp


def main():
    lab = labels()
    v = Vice(PRG, WORK, warp=False)     # (in warp the counters wrap between looks)
    try:
        for _ in range(200):
            v.run_for(0.1)
            if lab['main'] <= int(v.cmd('r').splitlines()[1].split()[0][2:], 16) < 0xC000:
                break
        run_pictures(v, lab, 10)
        for a in sys.argv[1:]:
            d, n = a.split('=')
            bits = 0
            for p in d.split('+'):
                bits |= BITS.get(p, 0)
            v.poke(lab['dbg_joy'], [bits])
            for k in range(0, int(n), 5):
                run_pictures(v, lab, 5)
                c = v.mem(lab['ctrl'], 1)[0]
                print('%-12s ctrl %2d %s  ball %s' % (d, c, obj(v, lab, c), obj(v, lab, BALL)))
        v.poke(lab['dbg_joy'], [0])
        v.screenshot(os.path.join(WORK, 'state.png'))
    finally:
        v.stop()


if __name__ == '__main__':
    main()
