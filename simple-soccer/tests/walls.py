#!/usr/bin/env python3
"""Sliding tackles at the walls round the pitch: the joystick's player
put near the top or the bottom (or a side) and sent into a tackle there,
his place each picture - he must stop at the walls (play.s inside: x
19-588, y 30-719), never slide on into the stands.

    tests/walls.py [out-dir]

Each case: a line with the deepest place reached and ok / OUT, and a
screenshot when the slide is over.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, labels, held_from_start  # noqa: E402

WALL_L, WALL_R, WALL_T, WALL_B = 19, 588, 30, 719
VEC = [(0, -1000), (1000, -1000), (1000, 0), (1000, 1000),
       (0, 1000), (-1000, 1000), (-1000, 0), (-1000, -1000)]
BALL = 22
# (name, x, y, way he faces: 0 up, clockwise)
CASES = [('up', 300, 50, 0), ('up-right', 300, 50, 1), ('down', 300, 700, 4),
         ('down-left', 300, 700, 5), ('left', 40, 300, 6), ('right', 570, 300, 2)]


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(WORK, 'walls')
    os.makedirs(out, exist_ok=True)
    lab = labels()
    bad = 0
    for name, x, y, d in CASES:
        v = Vice(PRG, WORK)
        try:
            held_from_start(v, lab, 'up')
            v.cmd('watch store %04x' % lab['shown'])
            for _ in range(40):         # the kick-off taken, play on
                v.cmd('x')
            v.poke(lab['dbg_joy'], [0])
            v.cmd('del')
            v.cmd('break %04x' % lab['eng_end'])
            v.cmd('x')
            p = v.mem(lab['ctrl'], 1)[0]

            def put(n, value, i=p):
                v.poke(lab[n] + i, [value & 255])

            def put16(lo, hi, value, i=p):
                put(lo, value, i)
                put(hi, value >> 8, i)
            put16('o_xl', 'o_xh', x)
            put16('o_yl', 'o_yh', y)
            put('o_xf', 0)
            put('o_yf', 0)
            put('o_dir', d)
            put16('o_txl', 'o_txh', x + VEC[d][0])
            put16('o_tyl', 'o_tyh', y + VEC[d][1])
            put('o_slide', 50)
            put('o_hit', 0)
            put('o_hd', 0)
            put('o_step', 1)
            put('o_mov', 1)
            put16('o_spl', 'o_sph', 1792)
            bx = x + (40 if x < 304 else -40)   # the ball beside him: the view there
            put16('o_xl', 'o_xh', bx, BALL)
            put16('o_yl', 'o_yh', y, BALL)
            put16('o_spl', 'o_sph', 0, BALL)    # (lying still)
            lo_x, hi_x, lo_y, hi_y = x, x, y, y
            for _ in range(30):
                v.cmd('x')
                m = lambda n: v.mem(lab[n] + p, 1)[0]
                px = m('o_xl') + 256 * m('o_xh')
                py = m('o_yl') + 256 * m('o_yh')
                px -= 65536 if px > 32767 else 0
                py -= 65536 if py > 32767 else 0
                lo_x, hi_x = min(lo_x, px), max(hi_x, px)
                lo_y, hi_y = min(lo_y, py), max(hi_y, py)
            ok = WALL_L <= lo_x and hi_x <= WALL_R and WALL_T <= lo_y and hi_y <= WALL_B
            bad += not ok
            shot = os.path.join(out, name + '.png')
            v.screenshot(shot)
            print('%-10s from (%d,%d): x %d..%d, y %d..%d  %s  %s'
                  % (name, x, y, lo_x, hi_x, lo_y, hi_y, 'ok' if ok else 'OUT', shot))
        finally:
            v.stop()
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
