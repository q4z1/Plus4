#!/usr/bin/env python3
"""p4emu_shots.py - pictures of the game in plus4emu, to look at:
build/test/shot_<where>.png for the farmhouse, the farm, the village and
mine floors, after walking a little."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p4emu_snow as S
from p4emu import ROOT

OUT = os.path.join(ROOT, 'build', 'test')
WHERE = [('house', 'HOUSE', 5, 4, 0), ('farm', 'FARM_E', 10, 5, 0),
         ('village', 'TOWN', 10, 6, 0), ('mine23', 'MINE_A', 9, 9, 23)]

if __name__ == '__main__':
    want = sys.argv[1:]
    e = S.boot()
    try:
        for name, room, x, y, fl in WHERE:
            if want and name not in want:
                continue
            S.goto(e, room, x, y, floor=fl)
            for k in (('left', 'right') if fl else ('left', 'up', 'right')):
                e.set('dbg_keys', S.K[k])
                e.frame(15)
            e.set('dbg_keys', 0)
            e.frame(int(os.environ.get('WAIT', '30')))
            print(e.png(os.path.join(OUT, 'shot_%s.png' % name)))
    finally:
        e.stop()
