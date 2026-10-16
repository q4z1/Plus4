#!/usr/bin/env python3
"""One call of a routine, instruction by instruction.

    tests/fprof.py <function> [game-second]

Wakefield with the autopilot at x10 up to that second, then the next call
of <function> (e.g. _trains_draw) from entry to return: its cycles, and
where they go by label. Run from trainschedule/.
"""
import bisect
import collections
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shot import Game  # noqa: E402

FN = sys.argv[1]
AT = int(sys.argv[2]) if len(sys.argv) > 2 else 320
g = Game()
L = g.lbl
labs = {}
for n, a in L.items():
    if a >= 0x1001:
        labs.setdefault(a, n)
addrs = sorted(labs)


def where(pc):
    i = bisect.bisect_right(addrs, pc) - 1
    return labs[addrs[i]]


try:
    g.wait(30)
    g.v.poke(L['_autopilot_on'], [1])
    for _ in range(3):
        g.press('fast')
        g.wait(5)
    while g.clock() < AT:
        g.wait(25)
    g.v.cmd(f'break {L[FN]:04x}')
    g.v.settle = 1.0
    out = g.v.cmd('x')
    g.v.cmd('delete')
    sp = int(re.findall(r'SP:([0-9a-f]{2})', out)[-1], 16)
    lo, hi = g.v.mem(0x0101 + sp, 2)
    ret = (lo | hi << 8) + 1
    g.v.cmd(f'break {ret:04x}')
    out = g.v.cmd('x')
    g.v.cmd('delete')
    g.v.settle = 4.0
    out = g.v.cmd('chis 16000')
finally:
    g.stop()
ins = []
for line in out.splitlines():
    m = re.match(r'\.C:([0-9a-f]{4})\s+((?:[0-9A-F]{2} )+)\s+(\S+).*?(\d+)\s*$', line)
    if m:
        ins.append((int(m.group(1), 16), m.group(3), int(m.group(4))))
starts = [i for i, x in enumerate(ins) if x[0] == L[FN]]
if starts:
    ins = ins[starts[-1]:]
else:
    print('(the call is longer than the history: its last part only)')
ex = collections.Counter()
for (a, op, c), n in zip(ins, ins[1:]):
    ex[where(a)] += n[2] - c
print(f'{FN}: {ins[-1][2] - ins[0][2]} cycles, {len(ins)} instructions')
for n, c in ex.most_common(25):
    print(f'  {n:20s} {c:7d}')
