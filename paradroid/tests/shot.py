#!/usr/bin/env python3
"""shot.py [seconds] [keys...] - start the game headless, let it run, press
keys (as bits for dbg_keys, e.g. 8=right) for a while each, and leave a
screenshot in build/shot.png. For looking at the game without a window."""
import os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from vice import Vice

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
work = os.path.expanduser('~/.cache/paradroid/test')
os.makedirs(work, exist_ok=True)
prg = os.path.join(work, 'paradroid.prg')
open(prg, 'wb').write(open(os.path.join(ROOT, 'build', 'paradroid.prg'), 'rb').read())

labels = {}
for l in open(os.path.join(ROOT, 'build', 'paradroid.lbl')):
    p = l.split()
    labels[p[2].lstrip('.')] = int(p[1], 16)

v = Vice(prg, work)
try:
    # until the game runs, then the player cannot be hurt
    for i in range(100):
        v.run_for(0.2)
        if v.mem(labels['_ticks'], 2) != [0, 0]:
            break
    v.poke(labels['_dbg_god'], [1])
    v.run_for(float(sys.argv[1]) if len(sys.argv) > 1 else 4)
    v.cmd('warp off')
    for k in sys.argv[2:]:
        bits, secs = (k.split(':') + ['1'])[:2]
        v.poke(labels['_dbg_keys'], [int(bits)])
        v.run_for(float(secs))
    v.poke(labels['_dbg_keys'], [0])
    v.screenshot(os.path.join(work, 'shot.png'))
    print(v.cmd('r'))
finally:
    v.stop()
