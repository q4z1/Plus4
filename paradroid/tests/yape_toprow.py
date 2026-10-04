#!/usr/bin/env python3
"""yape_toprow.py [samples] - in a game in Yape, driving about: the
window's top row (screen row 8, whose last lines the TED shows at the
window's top) in the picture on show, against the deck. Its cells are
copies of the deck's characters in codes of their own, each picture its
own (engine.s, cut_row); every deck cell there must show its character.
Cells a figure is in (multicolour) are left out."""
import os, re, sys, random
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.expanduser('~/.cache/paradroid/work/py'))
from yape import Yape
HERE = os.path.dirname(os.path.abspath(__file__))
n = int(sys.argv[1]) if len(sys.argv) > 1 else 150
lbl = {}
for l in open(os.path.join(HERE, '..', 'build', 'paradroid.lbl')):
    p = l.split()
    lbl[p[2].lstrip('.')] = int(p[1], 16)
y = Yape(os.path.join(HERE, '..', 'build', 'paradroid.prg'))


def snapshot(*ranges):
    """memory, the machine stopped once for all of it"""
    cmds = []
    for a, k in ranges:                 # (Yape lists so much at a time)
        for b in range(a, a + k, 0x100):
            cmds.append('m %04x %04x' % (b, min(a + k, b + 0x100) - 1))
    out = y.monitor(*cmds)
    mem = {}
    for l in out.splitlines():
        m = re.match(r'\s*([0-9A-F]{4}): ((?:[0-9A-F]{2} +){1,17})', l)
        if m:
            a = int(m.group(1), 16)
            for i, b in enumerate(m.group(2).split()):
                mem.setdefault(a + i, int(b, 16))
    missing = [a + i for a, k in ranges for i in range(k) if a + i not in mem]
    assert not missing, 'not listed: %04x' % missing[0]
    return mem


bad = checked = 0
try:
    for t in range(60):
        y.run_for(1)
        if y.mem(lbl['_font_hi'], 1)[0] == 0xD8:
            break
    y.run_for(2)
    y.poke(lbl['_dbg_god'], [1])
    y.poke(lbl['_dbg_keys'], [16])
    y.run_for(1)
    y.poke(lbl['_dbg_keys'], [0])
    y.run_for(4)
    dmap = y.mem(0x0400, 1024)
    blkc = y.mem(0xE800, 1024)
    rnd = random.Random(3)
    for i in range(n):
        if i % 8 == 0:
            y.poke(lbl['_dbg_keys'], [rnd.choice([10, 6, 9, 5, 2, 1, 8, 4])])
        y.run_for(0.05)
        mem = snapshot((lbl['front'], 1), (lbl['b_m0'], 2), (lbl['b_r'], 2),
                       (lbl['_ready'], 1), (0xC000 + 320, 40), (0xC400 + 320, 40),
                       (0xD000 + 320, 40), (0xD400 + 320, 40),
                       (0xC800, 0x800), (0xD800, 0x800))
        f = mem[lbl['front']]
        m0, r = mem[lbl['b_m0'] + f], mem[lbl['b_r'] + f]
        r = r - 256 if r > 127 else r
        att = 0xC000 + f * 0x1000 + 320
        scr = att + 0x400
        font = 0xC800 + f * 0x1000
        if not 0 <= r < 64:
            continue
        wrong = []
        for c in range(39):
            if mem[att + c] & 8:
                continue                # a figure's cell
            x = (m0 + c) & 255
            want = blkc[(r & 3) * 256 + dmap[(r >> 2) * 64 + (x >> 2)] + (x & 3)]
            have = mem[scr + c]
            g = lambda k: [mem[font + k * 8 + j] for j in range(8)]
            if g(want) != g(have):
                wrong.append(c)
        checked += 1
        if wrong:
            bad += 1
            print('sample %d, picture %d: cells %s wrong' % (i, f, wrong), flush=True)
    print('top row: %d of %d samples wrong' % (bad, checked))
finally:
    y.stop()
