#!/usr/bin/env python3
"""p4emu_lift.py - the lift in plus4emu:
1. where on a lift's block fire held starts it: the player put at every
   fourth pixel of the block (and a little off it), across and down; the
   original takes the whole block (paradroid's _lift_here).
2. a ride to another deck, picture by picture: the border beside the
   window and whether the window shows the side view or the deck. The
   border must change with the window, not before (it did while the
   slots were made, a second with the side view up)."""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from p4emu import P4emu
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.expanduser('~/.cache/paradroid/test')
lbl = {}
for l in open(os.path.join(HERE, '..', 'build', 'paradroid.lbl')):
    p = l.split()
    lbl[p[2].lstrip('.')] = int(p[1], 16)
decks = []
for l in open(os.path.join(HERE, '..', 'data', 'decks.txt')):
    l = l.rstrip('\n')
    if not l or l.startswith('#'):
        continue
    if l.startswith('deck'):
        decks.append([])
    else:
        decks[-1].append(l)


def word(e, name):
    a = e.mem(lbl[name], 2)
    return a[0] | a[1] << 8


def put(e, x, y):
    """the player at pixel x, y of the deck, standing (written again till
    it stays: a write in the middle of a tick may be moved by 8)"""
    for t in range(10):
        e.poke(lbl['_d_x'], [x & 255, x >> 8])
        e.poke(lbl['_d_y'], [y & 255, y >> 8])
        e.poke(lbl['_d_vx'], [0])
        e.poke(lbl['_d_vy'], [0])
        e.run_for(0.2)
        if word(e, '_d_x') == x and word(e, '_d_y') == y:
            return True
    return False


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
    d = e.mem(lbl['_deck'], 1)[0]
    m = decks[d]
    lx, ly = [(x, y) for y in range(16) for x in range(64) if m[y][x] == '3'][0]
    print('deck %d, lift at block %d, %d' % (d, lx, ly))
    # 1. where it starts
    for axis in 'xy':
        for off in (0, 16, 31, 32):
            x = lx * 32 + (off if axis == 'x' else 16)
            y = ly * 32 + (off if axis == 'y' else 16)
            if not put(e, x, y):
                print('%s %+3d: the player does not stay there' % (axis, off))
                continue
            e.poke(lbl['_dbg_keys'], [16])
            e.run_for(2.0)
            # the lift's side view: its "Deck n" in the panel, the window
            # in the deck's characters' upper half ($C8 set, no figures)
            st = e.mem(lbl['_transfer_mode'], 1)[0]
            e.png(os.path.join(OUT, 'lift_%s%d.png' % (axis, off)))
            e.poke(lbl['_dbg_keys'], [0])
            e.run_for(2.0)
            print('%s %+3d: %s' % (axis, off, 'transfer mode, no lift' if st else 'the lift'),
                  flush=True)
    # 2. a ride: on the lift, fire held, down (or up) a stop, let go
    for k in (18, 17):
        put(e, lx * 32 + 16, ly * 32 + 16)
        e.poke(lbl['_dbg_keys'], [16])
        e.run_for(2.0)
        e.poke(lbl['_dbg_keys'], [k])
        e.run_for(0.2)
        e.poke(lbl['_dbg_keys'], [16])
        e.run_for(1.0)
        e.png(os.path.join(OUT, 'ride_0.png'))
        if 'Deck %d' % d not in '':
            pass
        e.poke(lbl['_dbg_keys'], [0])
        n = 0
        while e.mem(lbl['_deck'], 1)[0] == d and n < 150:
            e.frame()
            n += 1
        if n < 150:
            break
        e.run_for(3.0)
    print('to deck %d' % e.mem(lbl['_deck'], 1)[0])
    # picture by picture: the first with the new border, the first with a
    # new window (the side view's gone)
    b0 = w0 = None
    nb = nw = None
    for i in range(300):
        e.frame()
        pix = e.pixels()
        border = pix[150][10]
        win = tuple(pix[y][x] for y in range(120, 240, 10) for x in range(60, 330, 10))
        if b0 is None:
            b0, w0 = border, win
            continue
        if nb is None and border != b0:
            nb = i
            e.png(os.path.join(OUT, 'ride_border.png'))
        if nw is None and win != w0:
            nw = i
            e.png(os.path.join(OUT, 'ride_window.png'))
        if nb is not None and nw is not None:
            break
    print('after letting go: the border new in picture %s, the window in %s' % (nb, nw))
    print('ok' if nb == nw else 'FAILED: the border must change with the window')
finally:
    e.stop()
