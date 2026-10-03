#!/usr/bin/env python3
"""screens.py - the README's screenshots, made in a headless VICE:
title, briefing, a deck with droids, the transfer game, a lift, the deck plan and
the droid enquiry, the transfer's introduction, the day's top score after a
game. Written to screenshots/."""
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
    g.poke('_d_vx', 0)                  # (no rolling on from where it was)
    g.poke('_d_vy', 0)


g = Game(warp=False)
try:
    # a page of the briefing, a few lines rolled up (the title's first
    # screen, the original's logo, is over by the time Game() is ready)
    g.v.run_for(5.0)
    save(g, 'briefing.png')
    # the title's round on: the scores page (white), then the logo of the
    # next round (the panel's rows in the window's set)
    g.v.cmd('warp on')
    for key in ('scores', 'title'):
        for i in range(2000):
            g.v.run_for(0.05)
            if (g.byte('_panel_hi') == 0xD8) if key == 'title' else (g.byte('_col_deck') == 0x71):
                break
        g.v.cmd('warp off')
        g.v.run_for(0.4)
        save(g, key + '.png')
        g.v.cmd('warp on')
    g.v.cmd('warp off')
    g.start_play()                      # the start page, the beam
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
    g.keys(18, 0.15); g.keys(16, 0.3); g.keys(0, 0.2)
    g.settle()                          # (another deck takes a moment)
    # a console: plan and enquiry
    m = decks[g.byte('_deck')]
    x, y = [(x, y) for y in range(1, 15) for x in range(1, 63) if m[y][x] == 'l'
            and any(m[y + b][x + a] in 'ghijstu' for a, b in ((1, 0), (-1, 0), (0, 1), (0, -1)))][0]
    to(g, x, y); g.keys(0, 0.4)
    # the console, an overlay from the disk: its menu, then the deck plan
    # (down twice, fire), the droid enquiry (up, fire) and a page of it
    g.keys(16, 0.7); g.keys(0, 6.0)
    save(g, 'console.png')
    for k in (2, 2):
        g.keys(k, 0.15); g.keys(0, 0.3)
    g.keys(16, 0.15); g.keys(0, 1.0)
    save(g, 'plan.png')
    g.keys(16, 0.15); g.keys(0, 0.8)
    g.keys(1, 0.15); g.keys(0, 0.3)
    g.poke('_d_type', 9)
    g.keys(16, 0.15); g.keys(0, 3.5)
    save(g, 'droids.png')
    g.keys(8, 0.15); g.keys(0, 3.5)
    save(g, 'droids_more.png')
    g.keys(16, 0.15); g.keys(0, 0.8)
    g.keys(1, 0.15); g.keys(0, 0.3)
    g.keys(16, 0.15); g.keys(0, 1.0)
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
    g.keys(16, 0.1); g.keys(0, 0.1)     # (held on, fire would skip a page)
    # the introduction: both droids, from the disk, in picture 1's set
    for i in range(60):
        if g.byte('_font_hi') == 0xD8:
            break
        g.v.run_for(0.2)
    g.v.run_for(1.0)
    save(g, 'intro_you.png')
    g.v.run_for(5.0)
    save(g, 'intro.png')
    # the board is up when the sides' colours are set; fire takes yellow
    for i in range(100):
        if g.byte('_tcol') != 0:
            break
        g.v.run_for(0.2)
    g.v.run_for(1.0)
    g.keys(16, 0.15); g.keys(0, 0.3)
    # pulses into three lines without a dead end: the cursor starts above
    # the lines each time
    part = g.v.mem(g.lbl['_part'], 12)
    for target in [r for r in range(12) if part[r] != 1][2:5]:
        for k in range(target + 1):
            g.keys(2, 0.1); g.keys(0, 0.1)
        g.keys(16, 0.12); g.keys(0, 0.2)
    g.v.run_for(1.0)
    save(g, 'transfer.png')
    # the day's top score after a game: the transfer played out, the game
    # ended with a score, and the next title round's scores page
    g.v.cmd('warp on')
    for i in range(100):
        if g.byte('_hide_player') == 0:
            break
        g.v.run_for(0.2)
    g.poke('_score', 12345 & 255, 12345 >> 8, 0, 0)
    g.poke('_dbg_god', 0)
    g.poke('_d_energy', 0)
    g.poke('_player_dead', 1); g.poke('_d_boom', 1)
    for key in ('title', 'scores'):         # the logo, then on to the scores
        for i in range(3000):
            g.v.run_for(0.05)
            if (g.byte('_panel_hi') == 0xD8) if key == 'title' else (g.byte('_col_deck') == 0x71):
                break
    g.v.cmd('warp off')
    g.v.run_for(0.4)
    save(g, 'highscore.png')
finally:
    g.stop()
