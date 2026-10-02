#!/usr/bin/env python3
"""yape_rowcheck.py - rowcheck.py in Yape: for each vertical fine position,
where each line of the window, as it is in memory, shows up on the screen
Yape draws. Rows that are shifted or rotated stand out. Yape's TED is
the one to trust (VICE's timing is not the real TED's)."""
import os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.expanduser('~/.cache/paradroid/work/py'))
from yape import Yape
from png import read_png
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.expanduser('~/.cache/paradroid/test')
lbl = {}
for l in open(os.path.join(HERE, '..', 'build', 'paradroid.lbl')):
    p = l.split()
    lbl[p[2].lstrip('.')] = int(p[1], 16)


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


y = Yape(os.path.join(HERE, '..', 'build', 'paradroid.d64'), warp=True)
def word(n):
    a = y.mem(lbl[n], 2)
    return a[0] | a[1] << 8
try:
    for t in range(40):
        y.run_for(1)
        if y.mem(lbl['_font_hi'], 1)[0] == 0xD8:
            break
    y.run_for(2)
    y.poke(lbl['_dbg_god'], [1])
    y.poke(lbl['_dbg_keys'], [16])
    y.run_for(1)
    y.poke(lbl['_dbg_keys'], [0])
    y.run_for(2)
    y.poke(lbl['_nd'], [1])
    py0 = word('_d_y')
    origin = None                       # the screen's top left in the shot
    for t in range(9):
        py = py0 + t
        y.poke(lbl['_d_y'], [py & 255, py >> 8])
        y.run_for(1.5)
        f = y.png(os.path.join(OUT, 'yrc%d.png' % t))
        w, h, pix = read_png(f)
        front = y.mem(lbl['front'], 1)[0]
        base = 0xC400 if front == 0 else 0xD400
        scr = y.mem(base, 1000); att = y.mem(base - 0x400, 1000)
        font = y.mem(base + 0x400, 2048)
        bs = y.mem(lbl['b_s'], 2)[front]; sx = y.mem(lbl['b_sx'], 2)[front]
        k = (-(py - 56)) & 7
        lines = {}
        for r in range(9, 25):
            for yy in range(8):
                line = []
                for c in range(2, 38):
                    line += pixels(scr, att, font, r, c, yy)
                if sum(line) and sum(line) != len(line):
                    lines[(r, yy)] = line
        if origin is None:              # found from the first: most lines in place
            best = (0, None)
            for ox in range(16, 49):
                for oy in range(16, 65):
                    bg = pix[oy + 8 * 9 - 1][ox + 160]
                    n = 0
                    for (r, yy), line in list(lines.items())[::7]:
                        sy = oy + k + 8 * r + yy
                        if sy < h and [0 if pix[sy][x] == bg else 1
                                       for x in range(ox + 16 + sx, ox + 304 + sx)] == line:
                            n += 1
                    if n > best[0]:
                        best = (n, (ox, oy))
            origin = best[1]
            print('screen at', origin, 'in the shot,', best[0], 'lines found')
        ox, oy = origin
        bg = pix[oy + 8 * 9 - 1][ox + 160]
        shot = [[0 if pix[yy][x] == bg else 1 for x in range(ox + 16 + sx, ox + 304 + sx)]
                for yy in range(h)]
        offs = {}
        for (r, yy), line in sorted(lines.items()):
            want = oy + k + 8 * r + yy
            if want - oy >= 200:
                continue                # under the picture's end (line 204 on)
            found = [s - want for s in range(want - 20, min(h, want + 21)) if shot[s] == line]
            key = 'ok' if 0 in found else ('%+d' % found[0] if found else 'none')
            offs.setdefault(key, []).append('%d.%d' % (r, yy))
        print('t=%d s=%d k=%d: %s' % (t, bs, k, ' '.join(
            '%s:%d' % (kk, len(v)) + ('' if kk == 'ok' else str(v[:6])) for kk, v in offs.items())),
            flush=True)
finally:
    y.stop()
