#!/usr/bin/env python3
"""yape_cheese.py [pictures] - the pause's "Cheese" in Yape: nothing may
move in it, so every picture must be the first. Yape cannot press the
keys, so the pause comes from the debug keys (run/stop) and Cheese from a
patch: the pause's test for its key (F3) taken out (beq -> two nops). Pictures
unlike the first go to ~/.cache/paradroid/test/ych_<n>.png."""
import os, sys
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
y = Yape(os.path.join(HERE, '..', 'build', 'paradroid.prg'), warp=True, series=n)
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
    y.run_for(4)
    # the pause's "lda #1, rts, lda pf, and #16, beq": found in the code
    raw = open(os.path.join(HERE, '..', 'build', 'paradroid.raw'), 'rb').read()
    at = raw.find(bytes([0xA9, 0x01, 0x60, 0xAD]), 2)
    assert at >= 0 and raw[at + 6:at + 9] == bytes([0x29, 0x10, 0xF0]), \
        'the pause\'s test not found'
    at += (raw[0] | raw[1] << 8) - 2 + 6
    y.poke(lbl['_dbg_keys'], [64])
    y.run_for(0.5)
    y.poke(lbl['_dbg_keys'], [0])
    y.run_for(0.5)
    y.poke(at + 2, [0xEA, 0xEA])
    y.run_for(1)
    shots = y.png_series(os.path.join(OUT, 'ych_'))
    ref = None
    bad = 0
    for f in shots:
        w, h, pix = read_png(f)
        if ref is None:
            ref = pix
            os.rename(f, os.path.join(OUT, 'ych_ref.png'))
            continue
        d = sum(1 for v in range(h) for x in range(w) if pix[v][x] != ref[v][x])
        if d:
            bad += 1
            print('%s: %d pixels differ' % (f, d))
        else:
            os.remove(f)
    print('%d of %d pictures differ' % (bad, len(shots) - 1))
finally:
    y.stop()
