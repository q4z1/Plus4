#!/usr/bin/env python3
"""screens.py - the README's screenshots, made in a headless VICE:
title, a deck with droids, the transfer game, a lift, the deck plan and
the droid enquiry. Written to screenshots/."""
import os, sys, shutil
sys.path.insert(0, os.path.dirname(__file__))
from game import Game, ROOT

OUT = os.path.join(ROOT, 'screenshots')
decks = []
for l in open(os.path.join(ROOT, 'data', 'decks.txt')):
    l = l.rstrip('\n')
    if not l or l.startswith('#'):
        continue
    if l.startswith('deck'):
        decks.append([])
    else:
        decks[-1].append(l)


def save(g, name):
    shutil.copy(g.shot(name), os.path.join(OUT, name))


def to(g, x, y):
    X, Y = x * 32 + 16, y * 32 + 16
    g.poke('_d_x', X & 255, X >> 8)
    g.poke('_d_y', Y & 255, Y >> 8)


g = Game(warp=False)
try:
    g.v.run_for(1.5)
    save(g, 'title.png')
    g.keys(16, 0.1); g.keys(0, 1.0)
    save(g, 'lift_stop.png')
    # a stroll and a shot
    g.keys(2, 0.35); g.keys(0, 0.3); g.keys(8, 0.6); g.keys(0, 0.5)
    g.keys(24, 0.12); g.keys(0, 0.15)
    save(g, 'deck.png')
    # the lift
    g.keys(4, 0.6); g.keys(1, 0.35); g.keys(0, 0.4)
    d = g.byte('_deck'); m = decks[d]
    lx, ly = [(x, y) for y in range(16) for x in range(64) if m[y][x] == '3'][0]
    to(g, lx, ly); g.keys(0, 0.4)
    g.keys(16, 1.0); g.keys(17, 0.15); g.keys(16, 0.4)
    save(g, 'lift.png')
    g.keys(18, 0.15); g.keys(16, 0.3); g.keys(0, 0.8)
    # a console: plan and enquiry
    m = decks[g.byte('_deck')]
    x, y = [(x, y) for y in range(1, 15) for x in range(1, 63) if m[y][x] == 'l'
            and any(m[y + b][x + a] in 'ghijstu' for a, b in ((1, 0), (-1, 0), (0, 1), (0, -1)))][0]
    to(g, x, y); g.keys(0, 0.4)
    g.keys(16, 1.2)
    save(g, 'plan.png')
    g.poke('_d_type', 10)
    g.keys(24, 0.2); g.keys(16, 0.3); g.keys(24, 0.2); g.keys(16, 0.6)
    save(g, 'droids.png')
    g.poke('_d_type', 0)
    g.keys(0, 0.8)
    # a transfer: away from the console, a live droid brought to the player
    # in transfer mode
    m = decks[g.byte('_deck')]
    x, y = [(x, y) for y in range(2, 14) for x in range(2, 62)
            if all(m[y + b][x + a] in 'lkop' for a in (-1, 0, 1) for b in (-1, 0, 1))][0]
    to(g, x, y); g.keys(0, 0.4)
    g.keys(16, 0.5)
    px = g.word('_d_x'); py = g.word('_d_y')
    i = [i for i in range(1, g.byte('_nd')) if g.byte('_d_boom', i) == 0][0]
    g.poke('_d_x', px & 255, px >> 8, off=2 * i); g.poke('_d_y', py & 255, py >> 8, off=2 * i)
    g.keys(16, 0.5); g.keys(0, 0.1)
    for i in range(60):
        if g.v.mem(g.lbl['_pulses'], 2) != [0, 0]:
            break
        g.v.run_for(0.2)
    kind = g.v.mem(g.lbl['_kind'], 12)
    cur = 6
    for target in [r for r in range(12) if kind[r] in (0, 2, 3)][:2]:
        while cur < target:
            g.keys(2, 0.12); g.keys(0, 0.12); cur += 1
        while cur > target:
            g.keys(1, 0.12); g.keys(0, 0.12); cur -= 1
        g.keys(16, 0.15); g.keys(0, 0.2)
    g.v.run_for(0.6)
    save(g, 'transfer.png')
finally:
    g.stop()
