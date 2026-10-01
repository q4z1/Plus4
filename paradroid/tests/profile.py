#!/usr/bin/env python3
"""profile.py keys [samples] - where the time goes: the program counter,
sampled through VICE's monitor, counted per symbol of build/paradroid.lbl"""
import os, sys, time, random, re, bisect
from collections import Counter
sys.path.insert(0, os.path.dirname(__file__))
from vice import Vice
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
work = os.path.expanduser('~/.cache/paradroid/test')
prg = os.path.join(work, 'paradroid.prg')
open(prg, 'wb').write(open(os.path.join(ROOT, 'build', 'paradroid.prg'), 'rb').read())
syms = []
for l in open(os.path.join(ROOT, 'build', 'paradroid.lbl')):
    p = l.split()
    name = p[2].lstrip('.')
    if name.startswith('@') or name.startswith('L') and re.match(r'L[0-9A-F]{4}$', name):
        continue
    syms.append((int(p[1], 16), name))
syms.sort()
addrs = [a for a, n in syms]
from game import Game
g = Game(warp=False)
v = g.v
try:
    v.poke(g.lbl['_dbg_keys'], [16]); v.run_for(0.3); v.poke(g.lbl['_dbg_keys'], [0]); v.run_for(0.5)
    keys = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    lbl = dict((n, a) for a, n in syms)
    v.poke(lbl['_dbg_keys'], [keys])
    v.run_for(1)
    c = Counter()
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 300
    for i in range(n):
        v.sock.sendall(b'x\n')
        time.sleep(random.uniform(0.01, 0.05))
        r = v.cmd('r')
        m = re.search(r'\.;([0-9a-f]{4})', r)
        pc = int(m.group(1), 16)
        k = bisect.bisect_right(addrs, pc) - 1
        c[syms[k][1] if k >= 0 else '?'] += 1
    for name, cnt in c.most_common(30):
        print('%5.1f%%  %s' % (100.0 * cnt / n, name))
finally:
    v.stop()
