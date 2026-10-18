#!/usr/bin/env python3
"""trainschedule in Yape: the frame to the right until the view has
scrolled - shown from the second screen at $F000 - and the picture saved.
Run from trainschedule/."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from yape import Yape  # noqa: E402
from yape_check import labels, HERE, OUT  # noqa: E402

L = labels()
y = Yape(os.path.join(HERE, 'build', 'trainschedule.d64'))
try:
    y.run_for(4)
    y.poke(L['_dbg_keys'], [8])         # right, held
    y.run_for(2.5)
    y.poke(L['_dbg_keys'], [0])
    y.run_for(0.5)
    print('$FF14', hex(y.mem(0xFF14, 1)[0]), 'view_x', y.mem(L['_view_x'], 1)[0])
    y.png(os.path.join(OUT, 'yape_scroll.png'))
finally:
    y.stop()
