#!/usr/bin/env python3
"""yape_rollcheck.py [pictures] - the briefing rolling in Yape, picture by
picture: where the window's rows show up against where they are meant to
(their lines found in the screenshot, as yape_rowcheck.py does), and the
line the window's colour starts on. Pictures with rows out of place or a
late colour are listed."""
import os, sys, collections
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.expanduser('~/.cache/paradroid/work/py'))
from yape import Yape
from png import read_png
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.expanduser('~/.cache/paradroid/test')
n = int(sys.argv[1]) if len(sys.argv) > 1 else 100
lbl = {}
for l in open(os.path.join(HERE, '..', 'build', 'paradroid.lbl')):
    p = l.split()
    lbl[p[2].lstrip('.')] = int(p[1], 16)
OX, OY = 32, 41                         # the screen's top left in Yape's shots
WROW0 = 8


def pixels(scr, att, font, r, c, y):
    b = font[scr[r * 40 + c] * 8 + y]
    return [1 if b & (0x80 >> i) else 0 for i in range(8)]


y = Yape(os.path.join(HERE, '..', 'build', 'paradroid.prg'), warp=True)
summary = collections.Counter()
try:
    for t in range(80):
        y.run_for(0.5)
        if y.mem(lbl['_col_deck'], 1)[0] in (0x77, 0x5B, 0x7F):
            break
    for i in range(n):
        y.run_for(0.05)
        f = y.png(os.path.join(OUT, 'yroll.png'))
        w, h, pix = read_png(f)
        front = y.mem(lbl['front'], 1)[0]
        s = y.mem(lbl['b_s'], 2)[front]
        base = 0xC400 if front == 0 else 0xD400
        scr = y.mem(base, 1000); att = y.mem(base - 0x400, 1000)
        font = y.mem(y.mem(lbl['_font_hi'], 1)[0] << 8, 2048)
        if os.environ.get('ROLL_DUMP') and i == 5:
            import json, shutil
            shutil.copy(f, os.path.join(OUT, 'yroll_dump.png'))
            json.dump({'scr': scr, 'att': att, 'font': font, 's': s}, open(os.path.join(OUT, 'yroll_dump.json'), 'w'))
        gap = pix[OY + 8 * 7][OX + 160]
        top = next(v for v in range(OY + 8 * 7, OY + 8 * 12)
                   if pix[v][OX + 160] != gap) - OY
        if top > 90:
            continue                    # a page being built
        mid = pix[OY + top + 60][OX + 16:OX + 304]
        wbg = max(set(mid), key=mid.count)    # the window's colour
        shot = [[0 if pix[v][x] in (wbg, gap) else 1 for x in range(OX + 16, OX + 304)]
                for v in range(h)]
        offs = collections.Counter()
        for r in range(WROW0 + 1, 24):
            for yy in range(8):
                line = []
                for c in range(2, 38):
                    line += pixels(scr, att, font, r, c, yy)
                if 8 < sum(line) < len(line) - 8:
                    want = OY + s + 8 * r + yy
                    found = [d for d in range(-9, 10) if 0 <= want + d < h and shot[want + d] == line]
                    if found:
                        offs[min(found, key=abs)] += 1
        main = offs.most_common(1)[0][0] if offs else None
        key = (top, main)
        summary[key] += 1
        if main != 0 or top != 72:
            print('picture %d: s=%d window colour from %d, rows %s' % (i, s, top, dict(offs)), flush=True)
    print('top line, row offset: pictures', dict(summary))
finally:
    y.stop()
