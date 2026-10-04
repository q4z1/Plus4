#!/usr/bin/env python3
"""yape_pads.py - the gamepads Yape (SDL) sees, in its order: index 0 is
the first, and Yape's ActiveJoystick setting decides which index goes to
which joystick port"""
import os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from yape import Yape
HERE = os.path.dirname(os.path.abspath(__file__))
y = Yape(os.path.join(HERE, '..', 'build', 'paradroid.prg'))
try:
    out = y._read_until(b'Special keys', timeout=15)
    for l in out.splitlines():
        if 'joystick' in l.lower() or l.startswith('    '):
            print(l)
finally:
    y.stop()
