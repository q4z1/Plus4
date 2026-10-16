#!/usr/bin/env python3
"""Run trainschedule in a headless VICE and look at it.

    tests/shot.py [seconds] [out.png] [keys...]

Lets the game run that many seconds of its own time (its picture count,
not the host's clock: VICE runs in warp), then saves a screenshot and
prints the screen as text. Keys are pressed as the game reads them: as
K_ bits (game.inc) poked into its key byte for a few pictures, e.g.
'level' or 'fast'. Run from trainschedule/.
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PRG = os.path.join(HERE, 'build', 'trainschedule.d64')
WORK = os.path.expanduser('~/.cache/trainschedule/test')
KEYS = {'up': 1, 'down': 2, 'left': 4, 'right': 8, 'fire': 16,
        'fast': 32, 'slow': 64, 'level': 128}


def labels():
    out = {}
    for line in open(os.path.join(HERE, 'build', 'trainschedule.lbl')):
        p = line.split()
        if len(p) == 3 and p[0] == 'al':
            out[p[2].lstrip('.')] = int(p[1], 16)
    for n in list(out):                 # (the C's names still do)
        if not n.startswith('_'):
            out.setdefault('_' + n, out[n])
    return out


def text(scr):
    rows = []
    for r in range(25):
        s = ''
        for c in scr[r * 40:(r + 1) * 40]:
            if r >= 19:                 # the board: extended colour, the
                c &= 63                 # top bits its background
            if 1 <= c <= 26:
                s += chr(64 + c)
            elif 32 <= c <= 63:
                s += chr(c)
            elif c == 0:
                s += '@'
            elif 64 <= c <= 189:
                s += '#'
            elif c >= 192:
                s += 'T'
            else:
                s += '+'
        rows.append(s)
    return '\n'.join(rows)


class Game:
    def __init__(self, play=True):
        self.lbl = labels()
        self.v = Vice(PRG, WORK)
        self.last = None
        if play:
            self.into_game()

    def into_game(self, choose=0):
        """past the title and the choice of a map (the first, or choose
        steps down), till the level runs"""
        self.wait_for('_eng_mode', 1)           # the title is shown
        self.v.poke(self.lbl['_unlocked'], [0xFF])  # every map open
        self.tap()
        self.wait_for('_eng_mode', 2)           # the choice of a map
        self.wait(20)
        for _ in range(choose):
            self.press('down')
            self.wait(5)
        self.tap()
        self.wait_for('_ptr_on', 1)             # the level has started
        self.wait(10)

    def wait_for(self, name, value, limit=6000):
        """pictures go by till the byte at name is value (the frame count
        stops while the disk loads, so: rounds of the emulator)"""
        for _ in range(limit // 10):
            if self.v.mem(self.lbl[name], 1)[0] == value:
                return
            self.v.run_for(0.2)
        raise RuntimeError(f'{name} never became {value}')

    def tap(self):
        """fire, let go: what the game takes as fire"""
        self.hold('fire')
        self.wait(4)
        self.hold()
        self.wait(4)

    def frames(self):
        return self.v.mem(self.lbl['_frames'], 1)[0]

    def wait(self, n):
        """let n pictures go by"""
        done = 0
        last = self.frames()
        while done < n:
            self.v.run_for(0.05)
            now = self.frames()
            done += (now - last) & 255
            last = now

    def point_at(self, x, y):
        """the pointer's tip to the middle of map cell x, y (the frame
        follows when the game next draws it; fire acts on that cell)"""
        z = self.v.mem(self.lbl['_zoom'], 1)[0]
        px, py = (x * 8 + 4) * z, (y * 8 + 4) * z
        self.v.poke(self.lbl['_ptr_x'], [px & 255, px >> 8])
        self.v.poke(self.lbl['_ptr_y'], [py & 255, py >> 8])
        self.v.poke(self.lbl['_cur_x'], [x])
        self.v.poke(self.lbl['_cur_y'], [y])

    def zoom(self):
        """Z: the other size (its own key byte in engine.s)"""
        self.v.poke(self.lbl['hits2'], [1])

    def hold(self, *names):
        """keys held down (as K_ bits) until hold() again"""
        bits = 0
        for n in names:
            bits |= KEYS[n]
        self.v.poke(self.lbl['_dbg_keys'], [bits])

    def press(self, *names):
        bits = 0
        for n in names:
            bits |= KEYS[n]
        a = self.lbl['hits']
        self.v.poke(a, [bits])

    def clock(self):
        lo, hi = self.v.mem(self.lbl['_clock_s'], 2)
        return lo | hi << 8

    def screen(self):
        """the screen being shown: one of two (engine.s, scrn)"""
        lo, hi = self.v.mem(self.lbl['_scrn'], 2)
        return text(self.v.mem(lo | hi << 8, 1000))

    def shot(self, path):
        self.v.screenshot(path)

    def stop(self):
        self.v.stop()


if __name__ == '__main__':
    secs = float(sys.argv[1]) if len(sys.argv) > 1 else 3
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(WORK, 'shot.png')
    g = Game()
    try:
        g.wait(100)
        for k in sys.argv[3:]:
            g.press(k)
            g.wait(10)
        g.wait(int(secs * 50))
        g.shot(out)
        print(g.screen())
        print('clock', g.clock())
    finally:
        g.stop()
