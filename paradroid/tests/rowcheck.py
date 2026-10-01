#!/usr/bin/env python3
"""rowcheck.py - for each vertical fine position: where each line of the
window, as it is in memory, shows up on the screen VICE draws. Rows that
are shifted or rotated stand out."""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.expanduser('~/.cache/paradroid/work/py'))
from game import Game
from png import read_png

def pixels(scr, att, font, r, c, y):
    """the 8 pixels of a cell's line: 1 where not background"""
    b = font[scr[r * 40 + c] * 8 + y]
    if att[r * 40 + c] & 8:
        out = []
        for i in range(4):
            p = 1 if (b >> (6 - 2 * i)) & 3 else 0
            out += [p, p]
        return out
    return [1 if b & (0x80 >> i) else 0 for i in range(8)]

g = Game(warp=False)
try:
    g.keys(16, 0.1); g.keys(0, 0.8)
    g.poke('_nd', 1)
    py0 = g.word('_d_y')
    for t in range(9):
        py = py0 + t
        g.poke('_d_y', py & 255, py >> 8)
        g.v.run_for(0.4)
        f = g.shot('rc%d.png' % t)
        w, h, pix = read_png(f)
        front = g.byte('front')
        base = 0xC400 if front == 0 else 0xD400
        scr = g.v.mem(base, 1000); att = g.v.mem(base - 0x400, 1000)
        font = g.v.mem(base + 0x400, 2048)
        bs = g.v.mem(g.lbl['b_s'], 2)[front]; sx = g.v.mem(g.lbl['b_sx'], 2)[front]
        k = (-(py - 68)) & 7
        bg = pix[96][200]               # the gap row: the deck colour
        # every screen line in the window, as bits over columns 2..37
        shot = []
        for yy in range(h):
            shot.append([0 if pix[yy][x] == bg else 1 for x in range(32 + 16 + sx, 32 + 304 + sx)])
        res = []
        for r in range(9, 25):
            hits = []
            for y in range(8):
                line = []
                for c in range(2, 38):
                    line += pixels(scr, att, font, r, c, y)
                if sum(line) == 0 or sum(line) == len(line):
                    continue
                want = 96 + k + 8 * (r - 7) + y
                if want > 239:
                    continue            # under the picture's end
                found = [yy for yy in range(want - 20, want + 21) if shot[yy] == line]
                hits.append((y, [f - want for f in found]))
            res.append((r, hits))
        bad = [(r, hh) for r, hh in res for (y, offs) in hh if 0 not in offs]
        offs = {}
        for r, hh in res:
            for y, o in hh:
                key = 'ok' if 0 in o else ('+%d' % o[0] if o else 'none')
                offs.setdefault(key, []).append('%d.%d' % (r, y))
        print('t=%d s=%d k=%d: %s' % (t, bs, k, ' '.join('%s:%d' % (kk, len(v)) + ('' if kk == 'ok' else str(v[:6])) for kk, v in offs.items())))
finally:
    g.stop()
