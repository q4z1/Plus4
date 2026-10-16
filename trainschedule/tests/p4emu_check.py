#!/usr/bin/env python3
"""trainschedule in plus4emu, from its disk: how long till the title
picture, till the game is ready, the choice of a map and a level, with
pictures of each (in ~/.cache/trainschedule/test). Times are the emulated
machine's. Run from trainschedule/.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from p4emu import P4emu  # noqa: E402

OUT = os.path.expanduser('~/.cache/trainschedule/test')
os.makedirs(OUT, exist_ok=True)


def main():
    p = P4emu()
    t0 = p.frames
    def secs():
        return (p.frames - t0) / 50
    def wait(test, limit=120):
        while secs() < limit:
            if test():
                return secs()
            p.run_for(0.1)
        raise RuntimeError('not in time')
    def fire():
        p.set('dbg_keys', 16)
        p.run_for(0.2)
        p.set('dbg_keys', 0)
        p.run_for(0.2)
    try:
        t = wait(lambda: p.mem(0x07B0)[0] == 1 and p.mem(0x07B6)[0] == 0x53)   # boot.s: its player playing
        print(f'music after {t:5.1f} s (from RUN)')
        t = wait(lambda: p.mem(0xFF06)[0] & 0x20)
        print(f'picture after {t:5.1f} s')
        p.run_for(3)
        p.png(os.path.join(OUT, 'p4emu_loading.png'))
        t = wait(lambda: p.peek('eng_mode') == 1 and p.mem(p.lab['_mus_song'], 2) == bytes([0, 0xE8]))
        print(f'game running after {t:5.1f} s')
        p.run_for(2)
        p.png(os.path.join(OUT, 'p4emu_title.png'))
        fire()
        t = wait(lambda: p.peek('eng_mode') == 2 and p.peek('ptr_on') == 0, secs() + 30)
        p.run_for(1)
        print(f'map list after {t:5.1f} s')
        p.png(os.path.join(OUT, 'p4emu_maps.png'))
        fire()
        t = wait(lambda: p.peek('ptr_on') == 1, secs() + 30)
        print(f'level after {t:5.1f} s')
        p.set('autopilot_on', 1)
        p.run_for(20)
        p.png(os.path.join(OUT, 'p4emu_level.png'))
        print('level: $FF12', hex(p.mem(0xFF12)[0]), 'score', p.peek('score'), 'song', p.mem(p.lab['_mus_song'], 2).hex())
    finally:
        p.stop()


if __name__ == '__main__':
    main()
