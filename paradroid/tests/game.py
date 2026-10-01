"""game.py - start Paradroid in a headless VICE and drive it (for tests)"""
import os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from vice import Vice

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
WORK = os.path.expanduser('~/.cache/paradroid/test')


def labels():
    lbl = {}
    for l in open(os.path.join(ROOT, 'build', 'paradroid.lbl')):
        p = l.split()
        lbl[p[2].lstrip('.')] = int(p[1], 16)
    return lbl


class Game:
    def __init__(self, god=True, warp=True):
        os.makedirs(WORK, exist_ok=True)
        # from the disk, which the briefing comes from
        d64 = os.path.join(WORK, 'paradroid.d64')
        open(d64, 'wb').write(open(os.path.join(ROOT, 'build', 'paradroid.d64'), 'rb').read())
        self.lbl = labels()
        self.v = Vice(d64, WORK, warp=True)
        irq = self.lbl['irq']
        # until the game's own interrupt runs and the title is up, loaded
        # from the disk: the picture on again (the title counts pictures,
        # not ticks)
        for i in range(200):
            self.v.run_for(0.2)
            vec = self.v.mem(0xFFFE, 2)
            if (vec[0] | vec[1] << 8 == irq and self.byte('_hide_player')
                    and self.v.mem(0xFF06, 1)[0] & 0x10):
                break
        if god:
            self.poke('_dbg_god', 1)
        if not warp:
            self.v.cmd('warp off')

    def start_play(self):
        """from the title into a game, standing still"""
        self.keys(16, 0.15)
        self.keys(0, 0.3)
        for i in range(50):
            if self.byte('_hide_player') == 0:
                break
            self.v.run_for(0.1)
        self.v.run_for(2.0)         # entering the deck takes a moment

    def word(self, name):
        m = self.v.mem(self.lbl[name], 2)
        return m[0] | m[1] << 8

    def byte(self, name, off=0):
        return self.v.mem(self.lbl[name] + off, 1)[0]

    def poke(self, name, *vals, off=0):
        self.v.poke(self.lbl[name] + off, list(vals))

    def keys(self, bits, secs):
        self.poke('_dbg_keys', bits)
        self.v.run_for(secs)

    def shot(self, name):
        path = os.path.join(WORK, name)
        self.v.screenshot(path)
        return path

    def stop(self):
        self.v.stop()
