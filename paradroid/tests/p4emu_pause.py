#!/usr/bin/env python3
"""p4emu_pause.py - the pause's keys, pressed on plus4emu's keyboard matrix
(VICE and Yape cannot press them): Run/Stop, then F1, F2, F3 (Cheese),
Help (back to the pause), Clr/Home (quits). A picture after each to
~/.cache/paradroid/test/pause_<n>.png, and the program counter's place."""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from p4emu import P4emu
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.expanduser('~/.cache/paradroid/test')
# plus4emu's codes: row * 8 + column, row 0 the one selected by $FE
KEY = {'help': 3, 'f1': 4, 'f2': 5, 'f3': 6, 'shift': 15, 'clr': 57,
       'stop': 63, 'space': 60}
lbl = {}
for l in open(os.path.join(HERE, '..', 'build', 'paradroid.lbl')):
    p = l.split()
    lbl[p[2].lstrip('.')] = int(p[1], 16)
seq = sys.argv[1:] or ['stop', 'f1', 'f2', 'f3', 'help', 'f3', 'clr']
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
    e.run_for(8)                # (the start page, the beam)
    e.png(os.path.join(OUT, 'pause_0.png'))
    for i, k in enumerate(seq, 1):
        for name in k.split('+'):
            e.key(KEY[name], 1)
        e.run_for(0.3)
        for name in k.split('+'):
            e.key(KEY[name], 0)
        e.run_for(1.5)
        e.png(os.path.join(OUT, 'pause_%d.png' % i))
        print(i, k, 'font_hi %02x' % e.mem(lbl['_font_hi'], 1)[0], flush=True)
finally:
    e.stop()
