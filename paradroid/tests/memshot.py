#!/usr/bin/env python3
"""memshot.py - run the game headless for a while and dump memory, to
reconstruct pictures offline (build: ~/.cache/paradroid/test/mem.bin)"""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from vice import Vice
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
work = os.path.expanduser('~/.cache/paradroid/test')
prg = os.path.join(work, 'paradroid.prg')
open(prg, 'wb').write(open(os.path.join(ROOT, 'build', 'paradroid.prg'), 'rb').read())
v = Vice(prg, work)
try:
    v.run_for(float(sys.argv[1]) if len(sys.argv) > 1 else 4)
    v.cmd('bank ram')
    v.cmd('save "%s" 0 0000 fcff' % os.path.join(work, 'mem.bin'))
    v.cmd('bank io')
    print(v.cmd('m ff00 ff1f'))
    v.screenshot(os.path.join(work, 'shot.png'))
finally:
    v.stop()
