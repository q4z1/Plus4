#!/usr/bin/env python3
"""How long main()'s calls take: cycles per call site, over some turns.

    tests/calls.py [game-second] [turns]

Wakefield with the autopilot at x10 up to that second; then a breakpoint
on every JSR in main() and on the instruction after it, and the clock
read at each. Sums per called routine. Run from trainschedule/.
"""
import collections
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shot import Game  # noqa: E402

AT = int(sys.argv[1]) if len(sys.argv) > 1 else 320
TURNS = int(sys.argv[2]) if len(sys.argv) > 2 else 6

g = Game()
L = g.lbl
names = {a: n for n, a in L.items() if n.startswith('_')}
ends = sorted(a for a in names if a > L['_main'])
main_end = ends[0]
try:
    g.wait(30)
    g.v.poke(L['_autopilot_on'], [1])
    for _ in range(3):
        g.press('fast')
        g.wait(5)
    while g.clock() < AT:
        g.wait(25)
    dis = g.v.cmd(f"d {L['_main']:04x} {main_end - 1:04x}")
    sites = {}
    for m in re.finditer(r'\.C:([0-9a-f]{4})\s+20 ([0-9A-F]{2}) ([0-9A-F]{2})\s+JSR', dis):
        a = int(m.group(1), 16)
        t = int(m.group(3) + m.group(2), 16)
        sites[a] = names.get(t, f'${t:04x}')
    for a in sites:
        g.v.cmd(f'break {a:04x}')
        g.v.cmd(f'break {a + 3:04x}')
    total = collections.Counter()
    count = collections.Counter()
    start = None
    loops0 = g.v.mem(L['_loops'], 1)[0]
    pending = {}
    first = last = None
    while True:
        g.v.sock.sendall(b'x\n')
        out = g.v._read_prompt()
        m = re.findall(r'\.C:([0-9a-f]{4}).*?(\d+)\s*\n', out)
        if not m:
            continue
        a, clk = int(m[-1][0], 16), int(m[-1][1])
        if first is None:
            first = clk
        last = clk
        if a in sites:
            pending[a] = clk
        elif a - 3 in sites and a - 3 in pending:
            total[sites[a - 3]] += clk - pending.pop(a - 3)
            count[sites[a - 3]] += 1
        if (g.v.mem(L['_loops'], 1)[0] - loops0) & 255 >= TURNS:
            break
    g.v.cmd('delete')
finally:
    g.stop()
span = last - first
print(f'{TURNS} turns, {span} cycles, {span / TURNS / 35568:.2f} pictures a turn')
for n, c in total.most_common():
    print(f'  {n:20s} {c / TURNS:9.0f} a turn  ({count[n]} calls)')
