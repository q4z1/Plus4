#!/usr/bin/env python3
"""p4emu_xcount.py - the transfer game's counts in plus4emu: the panel's
"Colour? NN" and "Finish -NN", picture by picture, without a key pressed.
As the original's (measured in x64sc): every number from 99 down, a step
every 5.9 pictures for the colour, every 5.3 for the finish."""
import os, sys, collections
sys.path.insert(0, os.path.dirname(__file__))
from p4emu import P4emu
HERE = os.path.dirname(os.path.abspath(__file__))
lbl = {}
for l in open(os.path.join(HERE, '..', 'build', 'paradroid.lbl')):
    p = l.split()
    lbl[p[2].lstrip('.')] = int(p[1], 16)
SCR0C = 0xC400


def panel(e):
    """the panel's status as its codes: the digits are codes 0-9"""
    return tuple(e.mem(SCR0C + 80 + 1, 16))


e = P4emu(os.path.join(HERE, '..', 'build', 'paradroid.prg'))
try:
    for t in range(40):
        e.run_for(1)
        if e.mem(lbl['_font_hi'], 1)[0] == 0xD8:
            break
    e.run_for(2)
    e.poke(lbl['_dbg_god'], [1])
    e.poke(lbl['_dbg_keys'], [16])
    e.run_for(1)
    e.poke(lbl['_dbg_keys'], [0])
    e.run_for(8)
    # transfer mode, a droid brought to the player
    e.poke(lbl['_dbg_keys'], [16])
    e.run_for(0.5)
    a = e.mem(lbl['_d_x'], 2); b = e.mem(lbl['_d_y'], 2)
    e.poke(lbl['_d_x'] + 2, list(a)); e.poke(lbl['_d_y'] + 2, list(b))
    e.run_for(0.3)
    e.poke(lbl['_dbg_keys'], [0])
    last, since, steps = None, 0, collections.defaultdict(list)
    for i in range(50 * 40):
        e.frame()
        p = panel(e)
        since += 1
        if p != last:
            digits = [c for c in p if c < 10]
            word = 'colour' if 0x3a + 2 in p else 'finish' if 0x3a + 5 in p else 'other'
            if len(digits) >= 2:
                n = digits[-2] * 10 + digits[-1]
                steps[word].append((n, since))
            last, since = p, 0
        if steps['finish'] and steps['finish'][-1][0] == 0:
            break
    for w in ('colour', 'finish'):
        s = steps[w]
        if not s:
            print(w, 'not seen'); continue
        ns = [n for n, _ in s]
        gaps = [g for _, g in s[1:]]
        jumps = collections.Counter(ns[i] - ns[i + 1] for i in range(len(ns) - 1))
        print('%s: %d .. %d, %d counts, steps %s, pictures per step %.2f (%d-%d)' % (
            w, ns[0], ns[-1], len(ns), dict(jumps), sum(gaps) / len(gaps), min(gaps), max(gaps)))
finally:
    e.stop()
