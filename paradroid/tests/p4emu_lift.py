#!/usr/bin/env python3
"""p4emu_lift.py - the lift in plus4emu:
1. where on a lift's block fire held starts it: the player put at every
   fourth pixel of the block (and a little off it), across and down; the
   original takes the character under the player, the lift's middle four
   (move.s's player_spot). Then driven over it with fire held: nothing.
2. a ride to another deck (fire let go, a stop chosen, fire pressed),
   picture by picture: the border beside the
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
            e.poke(lbl['_dbg_keys'], [0])       # out again: let go, fire
            e.run_for(0.3)
            e.poke(lbl['_dbg_keys'], [16])
            e.run_for(0.2)
            e.poke(lbl['_dbg_keys'], [0])
            e.run_for(2.0)
            print('%s %+3d: %s' % (axis, off, 'transfer mode, no lift' if st else 'the lift'),
                  flush=True)
    # 1b. driven over with fire held (the weapon), as the original: only
    # the character under the player counts, for 5 ticks - so it passes
    across = True
    for axis, k in (('x', 16 | 8), ('y', 16 | 2)):
        # a lift with floor two blocks before it and one after, that way
        dx, dy = (1, 0) if axis == 'x' else (0, 1)
        free = [(x, y) for y in range(2, 14) for x in range(2, 62) if m[y][x] == '3'
                and all(m[y + i * dy][x + i * dx] == 'l' for i in (-2, -1, 1))]
        if not free:
            print('driving over along %s: no lift with floor that way on deck %d' % (axis, d))
            continue
        ax, ay = free[0]
        x0 = ax * 32 + (16 if axis == 'y' else -40)
        y0 = ay * 32 + (16 if axis == 'x' else -40)
        if not put(e, x0, y0):
            print('driving over along %s: the player does not stay there' % axis)
            continue
        e.poke(lbl['_dbg_keys'], [k])
        e.run_for(1.2)
        e.poke(lbl['_dbg_keys'], [0])
        e.run_for(1.0)
        p = word(e, '_d_x' if axis == 'x' else '_d_y')
        end = (ax if axis == 'x' else ay) * 32 + 32
        print('driven over along %s with fire held: at %d, %s' % (
            axis, p, 'past it' if p > end else 'stopped (the lift opened?)'), flush=True)
        across &= p > end
        if p <= end:                    # (out of the side view again)
            e.poke(lbl['_dbg_keys'], [16]); e.run_for(0.2)
            e.poke(lbl['_dbg_keys'], [0]); e.run_for(2.0)
    # 2. a ride, as the original's: on the lift, fire held till the side
    # view shows, let go, down (or up) a stop, fire pressed and let go
    for k in (2, 1):
        put(e, lx * 32 + 16, ly * 32 + 16)
        e.poke(lbl['_dbg_keys'], [16])
        e.run_for(2.0)
        e.poke(lbl['_dbg_keys'], [0])
        e.run_for(0.3)
        e.poke(lbl['_dbg_keys'], [k])
        e.run_for(0.2)
        e.poke(lbl['_dbg_keys'], [0])
        e.run_for(0.5)
        e.png(os.path.join(OUT, 'ride_0.png'))
        e.poke(lbl['_dbg_keys'], [16])
        e.run_for(0.2)
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
    print('ok' if nb == nw and across else 'FAILED: the border must change with the window,'
          ' and driving over a lift with fire held must not start it')
finally:
    e.stop()
