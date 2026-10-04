#!/usr/bin/env python3
"""yape_boot.py [seconds] [warp] - the game from its disk in Yape: every five
seconds the CPU's registers and a screenshot (~/.cache/paradroid/test/
yape_boot_N.bmp), to see where a start goes wrong"""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from yape import Yape
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.expanduser('~/.cache/paradroid/test')
secs = int(sys.argv[1]) if len(sys.argv) > 1 else 30
y = Yape(os.path.join(HERE, '..', 'build', 'paradroid.prg'), warp='warp' in sys.argv)
try:
    for t in range(secs // 5):
        y.run_for(5)
        print('%3d s' % ((t + 1) * 5), ' | '.join(l.strip() for l in y.regs().splitlines()
                                                if l.strip() and 'onitor' not in l and 'help' not in l))
        print('      ', y.png(os.path.join(OUT, 'yape_boot_%d.png' % t)), flush=True)
finally:
    y.stop()
