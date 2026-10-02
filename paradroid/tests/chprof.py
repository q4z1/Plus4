#!/usr/bin/env python3
"""chprof.py keys [instructions] - where the time goes, exactly: the
monitor's CPU history (chis) of the last instructions, its cycles counted
per symbol of build/paradroid.lbl, exclusive and inclusive of calls.
Unlike profile.py's samples, which the monitor takes at its own moments."""
import os, sys, re, bisect, collections
sys.path.insert(0, os.path.dirname(__file__))
from game import Game
HERE = os.path.dirname(os.path.abspath(__file__))
labs = {}
for l in open(os.path.join(HERE, '..', 'build', 'paradroid.lbl')):
    p = l.split()
    a, n = int(p[1], 16), p[2].lstrip('.')
    if n.startswith('@') or n.startswith('__') or re.match(r'L[0-9A-F]{4}$', n):
        continue
    labs.setdefault(a, n)
addrs = sorted(labs)
def where(pc):
    i = bisect.bisect_right(addrs, pc) - 1
    return labs[addrs[i]] if i >= 0 else '?'
keys = int(sys.argv[1]) if len(sys.argv) > 1 else 0
n = int(sys.argv[2]) if len(sys.argv) > 2 else 60000
g = Game(warp=False)
try:
    g.start_play()
    g.poke('_dbg_keys', keys)
    g.v.run_for(3)
    g.v.settle = 3.0
    out = g.v.cmd('chis %d' % n)
finally:
    g.stop()
ins = []
for l in out.splitlines():
    m = re.match(r'\.C:([0-9a-f]{4})\s+((?:[0-9A-F]{2} )+)\s+(\S+).*?(\d+)\s*$', l)
    if m:
        ins.append((int(m.group(1), 16), m.group(3), int(m.group(4))))
excl = collections.Counter(); incl = collections.Counter()
stack = []
for (pc, op, clk), nxt in zip(ins, ins[1:]):
    c = nxt[2] - clk
    if c < 0 or c > 100:
        continue
    excl[where(pc)] += c
    for fn in set(stack):
        incl[fn] += c
    if op == 'JSR':
        stack.append(where(nxt[0]))
    elif op == 'RTS' and stack:
        stack.pop()
total = sum(excl.values())
print('%d cycles, %d instructions' % (total, len(ins)))
print('exclusive:')
for k, c in excl.most_common(25):
    print('  %5.1f%%  %s' % (100.0 * c / total, k))
print('inclusive:')
for k, c in incl.most_common(25):
    print('  %5.1f%%  %s' % (100.0 * c / total, k))
