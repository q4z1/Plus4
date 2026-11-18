#!/usr/bin/env python3
"""Which joystick plays the home team (K_HOME; title.s home_stick, engine.s
joy_read): the one used in the title last. From the disk in Yape: the
title, two players chosen with joystick 1 - "HOME: PORT 1"; joystick 2
pushed - "HOME: PORT 2", its stick in joy_a (the home team's), port 1's
in joy_b; joystick 1 pushed again - back as it was. Luca: playing alone
with port 2, with two players his joystick was the away team's.

    tests/ports.py

A line each, OK or WRONG; the exit code counts the wrong ones. Pictures:
~/.cache/simple-soccer/test/ports_*.png
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from yape import Yape  # noqa: E402
from shot import labels, BITS, WORK  # noqa: E402

D64 = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'build', 'simple-soccer.d64')
K_HOME = 0xFCEF                 # (game.inc)
LINE = 0xE800 + 0x400 + 22 * 40 + 6     # (title.s TCODE, PORTS_ROW, PORTS_COL)
PORTS_W = 28


def main():
    lab = labels()
    y = Yape(D64, warp=True, title=True)
    wrong = 0

    def check(name, ok, got):
        nonlocal wrong
        wrong += not ok
        print('%-12s %-50s %s' % (name, got, 'OK' if ok else 'WRONG'), flush=True)

    def line():
        return bytes(y.mem(LINE, PORTS_W)).decode('ascii', 'replace').strip()

    def press(port, d):
        at = lab['dbg_joy' if port == 1 else 'dbg_joyb']
        y.poke(at, [BITS[d]])
        time.sleep(0.12)
        y.poke(at, [0])
        time.sleep(0.25)
    try:
        t0 = time.time()
        while time.time() - t0 < 180:       # loading: till the title is on
            time.sleep(1)
            if y.mem(0xfffe, 2) == [lab['synth'], 0] and y.mem(0xff06, 1)[0] == 0x1b:
                break
        time.sleep(2)
        check('boot', y.mem(K_HOME, 1)[0] & 1 == 0 and 'EITHER' in line(), line())
        press(1, 'down')                    # PLAYERS: 2
        press(1, 'right')
        time.sleep(0.5)
        y.png(os.path.join(WORK, 'ports_1.png'))
        check('two, port 1', y.mem(K_HOME, 1)[0] & 1 == 0 and line() == 'HOME: PORT 1   AWAY: PORT 2',
              line())
        press(2, 'up')                      # (to the length: nothing else)
        time.sleep(0.5)
        y.png(os.path.join(WORK, 'ports_2.png'))
        check('port 2 used', y.mem(K_HOME, 1)[0] & 1 == 1 and line() == 'HOME: PORT 2   AWAY: PORT 1',
              line())
        y.poke(lab['dbg_joyb'], [BITS['left']])
        y.poke(lab['dbg_joy'], [BITS['right']])
        time.sleep(0.2)
        a, b = y.mem(lab['joy_a'], 1)[0], y.mem(lab['joy_b'], 1)[0]
        y.poke(lab['dbg_joyb'], [0])
        y.poke(lab['dbg_joy'], [0])
        check('joy_a port 2', a == BITS['left'] and b == BITS['right'],
              'joy_a %02x, joy_b %02x' % (a, b))
        time.sleep(0.3)
        press(1, 'down')                    # (back to PLAYERS)
        check('port 1 again', y.mem(K_HOME, 1)[0] & 1 == 0 and line() == 'HOME: PORT 1   AWAY: PORT 2',
              line())
    finally:
        y.stop()
    return wrong


if __name__ == '__main__':
    sys.exit(main())
