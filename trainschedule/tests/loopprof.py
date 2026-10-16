#!/usr/bin/env python3
"""loopprof.py [turns] [speed] [map] [from] - the main loop, turn by turn.

The game as a player has it (no _dbg_n: the pictures go by as they do),
the autopilot on, at speed 0-3 (default 3: x10), in the map (the last one
open, or map steps down the list, up if below 0), from that second of the
game's time on (default 60). Then a breakpoint on every JSR in the main
loop and on the instruction after it (NOPILOT=1 in the environment:
the autopilot off from then on, as a player has it): for that many turns, how long each turn took
(cycles, and pictures: 35568 cycles each, VICE's count), how many turns
took how many pictures, and the calls that cost the most in the long
ones. Run from trainschedule/.
"""
import collections
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shot import Game  # noqa: E402

TURNS = int(sys.argv[1]) if len(sys.argv) > 1 else 200
SPEED = int(sys.argv[2]) if len(sys.argv) > 2 else 3
CHOOSE = int(sys.argv[3]) if len(sys.argv) > 3 else 0
FROM = int(sys.argv[4]) if len(sys.argv) > 4 else 60
PICTURE = 35568

g = Game(play=False)
L = g.lbl
names = {}
for n, a in L.items():
    names.setdefault(a, n)
try:
    g.wait_for('_eng_mode', 1)
    g.v.poke(L['_unlocked'], [0xFF])
    g.tap()
    g.wait_for('_eng_mode', 2)
    g.wait(20)
    for _ in range(abs(CHOOSE)):
        g.press('down' if CHOOSE > 0 else 'up')
        g.wait(5)
    g.tap()
    g.wait_for('_ptr_on', 1)
    g.v.poke(L['_autopilot_on'], [1])
    g.v.poke(L['_speed_i'], [3])
    while g.clock() < FROM:
        g.wait(25)
    g.v.poke(L['_speed_i'], [SPEED])
    if os.environ.get('NOPILOT'):       # (from here on the player's: the
        g.v.poke(L['_autopilot_on'], [0])  # routes set stay)
    g.wait(10)
    # the loop: from the label after the level is started to the end of main
    dis = g.v.cmd(f"d {L['_main']:04x} {L['_main'] + 0x900:04x}")
    sites = {}
    loop = None
    for m in re.finditer(r'\.C:([0-9a-f]{4})\s+20 ([0-9A-F]{2}) ([0-9A-F]{2})\s+JSR', dis):
        a = int(m.group(1), 16)
        t = int(m.group(3) + m.group(2), 16)
        sites[a] = names.get(t, f'${t:04x}')
    # the turn starts where _eng_hits is called first after level_start
    order = sorted(sites)
    i = next(k for k, a in enumerate(order) if sites[a] == 'level_start')
    head = next(a for a in order[i + 1:] if sites[a] == '_eng_hits')
    for a in sites:
        g.v.cmd(f'break {a:04x}')
        g.v.cmd(f'break {a + 3:04x}')
    g.v.settle = 0.01
    turns = []
    cur = None
    pending = {}
    while len(turns) < TURNS:
        g.v.sock.sendall(b'x\n')
        out = g.v._read_prompt()
        m = re.findall(r'\.C:([0-9a-f]{4}).*?(\d+)\s*\n', out)
        if not m:
            continue
        a, clk = int(m[-1][0], 16), int(m[-1][1])
        if a == head:
            if cur is not None:
                cur['len'] = clk - cur['start']
                turns.append(cur)
            cur = {'start': clk, 'calls': collections.Counter()}
        if cur is None:
            continue
        if a - 3 in pending:            # (a return, which may be a call too)
            cur['calls'][sites[a - 3]] += clk - pending.pop(a - 3)
        if a in sites:
            pending[a] = clk
    g.v.cmd('delete')
finally:
    g.stop()
hist = collections.Counter(min(4, max(1, round(t['len'] / PICTURE))) for t in turns)
print(f'{len(turns)} turns at speed {SPEED}: pictures a turn (4: 4 or more)')
for k in sorted(hist):
    print(f'  {k}: {hist[k]}')
busy = sorted(sum(t['calls'].values()) for t in turns)
print(f'busy a turn (the calls): half of them under {busy[len(busy) // 2]}, '
      f'nine in ten under {busy[len(busy) * 9 // 10]}')
total = collections.Counter()
worst = collections.Counter()
for t in turns:
    total.update(t['calls'])
    for n, c in t['calls'].items():
        worst[n] = max(worst[n], c)
print('cycles a turn, by call (and the most in one turn):')
for n, c in total.most_common(12):
    print(f'  {n:20s} {c // len(turns):8d} {worst[n]:8d}')
print('the longest turns:')
for t in sorted(turns, key=lambda t: -t['len'])[:8]:
    top = ', '.join(f'{n} {c}' for n, c in t['calls'].most_common(3))
    print(f'  {t["len"]:7d} ({t["len"] / PICTURE:.2f}): {top}')
