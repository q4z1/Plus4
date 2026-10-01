#!/usr/bin/env python3
"""speed.py keys secs - ticks per second while keys are held"""
import os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from vice import Vice
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
work = os.path.expanduser('~/.cache/paradroid/test')
prg = os.path.join(work, 'paradroid.prg')
open(prg, 'wb').write(open(os.path.join(ROOT, 'build', 'paradroid.prg'), 'rb').read())
lbl = {}
for l in open(os.path.join(ROOT, 'build', 'paradroid.lbl')):
    p = l.split(); lbl[p[2].lstrip('.')] = int(p[1], 16)
from game import Game
g = Game(warp=False)
v = g.v
try:
    v.poke(lbl['_dbg_keys'], [16]); v.run_for(0.1); v.poke(lbl['_dbg_keys'], [0]); v.run_for(2.0)
    v.poke(lbl['_dbg_keys'], [int(sys.argv[1]) if len(sys.argv) > 1 else 0])
    def read():
        t = v.mem(lbl['_ticks'], 2); l = v.mem(lbl['_late'], 2); f = v.mem(lbl['_frames'], 1)
        return t[0] | t[1] << 8, l[0] | l[1] << 8
    # count frames via cycles: use frames counter wrap-safe by sampling often
    t0, l0 = read()
    fr = 0; prev = v.mem(lbl['_frames'], 1)[0]
    for i in range(int(float(sys.argv[2]) * 4) if len(sys.argv) > 2 else 20):
        v.run_for(0.25)
        f = v.mem(lbl['_frames'], 1)[0]
        fr += (f - prev) & 255; prev = f
    t1, l1 = read()
    print('frames %d ticks %d late %d -> %.1f ticks/s at 50 frames/s' % (fr, t1 - t0, l1 - l0, (t1 - t0) * 50.0 / fr))
finally:
    v.stop()
