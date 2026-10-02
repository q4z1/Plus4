#!/usr/bin/env python3
"""yape_play.py [seconds] [seed] - in Yape (warp): the title, fire to
start, then a random joystick (the game's dbg_keys, god mode); every five
seconds the game's tick count, the CPU's registers and a screenshot
(~/.cache/paradroid/test/yape_play_N.png). Fails when the game stops
ticking."""
import os, sys, random
sys.path.insert(0, os.path.dirname(__file__))
from yape import Yape
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.expanduser('~/.cache/paradroid/test')
secs = int(sys.argv[1]) if len(sys.argv) > 1 else 60
random.seed(int(sys.argv[2]) if len(sys.argv) > 2 else 1)
lbl = {}
for l in open(os.path.join(HERE, '..', 'build', 'paradroid.lbl')):
    p = l.split()
    lbl[p[2].lstrip('.')] = int(p[1], 16)

y = Yape(os.path.join(HERE, '..', 'build', 'paradroid.d64'), warp=True)
def word(n):
    a = y.mem(lbl[n], 2)
    return a[0] | a[1] << 8
try:
    # the title: up once the font's high byte is the window's ($D8)
    for t in range(30):
        y.run_for(1)
        if y.mem(lbl['_font_hi'], 1)[0] == 0xD8 and y.mem(lbl['_fl_kind'], 1) is not None:
            break
    y.run_for(2)
    y.poke(lbl['_dbg_god'], [1])
    y.poke(lbl['_dbg_keys'], [16])
    y.run_for(1)
    y.poke(lbl['_dbg_keys'], [0])
    last = None
    for t in range(secs // 5):
        for q in range(5):
            y.poke(lbl['_dbg_keys'], [random.choice([1, 2, 4, 8, 5, 6, 9, 10, 0, 16, 17, 18, 20, 24])])
            y.run_for(1)
        ticks = word('_ticks'), y.mem(lbl['_tick'], 1)[0]
        regs = [l.strip() for l in y.regs().splitlines() if 'PC:' in l]
        print('%3d s ticks %5d tick %3d deck %2d  %s' % ((t + 1) * 5, ticks[0], ticks[1],
              y.mem(lbl['_deck'], 1)[0], regs[0][:44] if regs else '?'), flush=True)
        y.png(os.path.join(OUT, 'yape_play_%d.png' % t))
        if ticks == last:
            print('STUCK')
            print(y.monitor('d'))
            sys.exit(1)
        last = ticks
finally:
    y.stop()
