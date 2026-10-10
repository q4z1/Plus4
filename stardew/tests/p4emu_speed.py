#!/usr/bin/env python3
"""p4emu_speed.py - pictures drawn per second (the screen shows 50), in
plus4emu, walking about: the farmhouse, the farm, the village, and mine
floors with more and more monsters. Also the longest gap between two
pictures, in frames: what a player sees as a jerk."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from p4emu import P4emu, ROOT
import p4emu_snow as S

K = S.K


def rate(e, where, secs=4, keys=('left', 'right')):
    loops0 = e.peek('dbg_loops')
    total, worst, gap, last = 0, 0, 0, loops0
    for i in range(secs * 50):
        e.set('dbg_keys', K[keys[(i // 40) % len(keys)]])
        e.frame()
        l = e.peek('dbg_loops')
        gap += 1
        if l != last:
            worst = max(worst, gap)
            gap = 0
            total += (l - last) & 255
            last = l
    e.set('dbg_keys', 0)
    extra = ''
    if e.peek('floor_no'):
        extra = ', %d monsters' % e.peek('nmon')
    print('%-10s %4.1f pictures/s, longest %d frames%s' % (where, total / secs, worst, extra))
    return total / secs


if __name__ == '__main__':
    e = S.boot()
    try:
        S.goto(e, 'HOUSE', 5, 4); e.frame(20)
        rate(e, 'house', keys=('right', 'left'))
        S.goto(e, 'FARM_E', 10, 5); e.frame(20)
        rate(e, 'farm')
        S.goto(e, 'TOWN', 10, 6); e.frame(20)
        rate(e, 'village', keys=('down', 'up'))
        for fl in (3, 13, 23):
            S.goto(e, 'MINE_A', 9, 9, floor=fl); e.frame(20)
            rate(e, 'mine %d' % fl)
    finally:
        e.stop()
