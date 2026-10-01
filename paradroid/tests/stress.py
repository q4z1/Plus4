#!/usr/bin/env python3
"""stress.py [seconds] - random joystick for a while (warp, cannot die);
fails if the game stops ticking. Screenshots in ~/.cache/paradroid/test."""
import os, sys, random
sys.path.insert(0, os.path.dirname(__file__))
from game import Game
secs = float(sys.argv[1]) if len(sys.argv) > 1 else 30
random.seed(int(sys.argv[2]) if len(sys.argv) > 2 else 1)
g = Game()
try:
    g.start_play()
    t0 = g.word('_ticks')
    n = 0
    while n < secs:
        k = random.choice([1, 2, 4, 8, 5, 6, 9, 10, 0, 16, 17, 18, 20, 24, 25, 26])
        g.keys(k, 0.5)
        n += 0.5
        t = g.word('_ticks')
        if t == t0:
            print('STUCK at', n, 's'); g.shot('stuck.png')
            print(g.v.cmd('r'))
            sys.exit(1)
        t0 = t
        if int(n) % 10 == 0 and n == int(n):
            g.shot('stress%d.png' % int(n))
            print('t=%ds ticks=%d deck=%d score=%d pool_left=%d' % (n, t, g.byte('_deck'),
                  g.word('_score'), g.byte('_pool_left')))
finally:
    g.stop()
