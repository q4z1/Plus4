#!/usr/bin/env python3
"""The README's pictures, made anew in plus4emu from the disk: the title,
the choice of a map, its page of help, Riesa with trains at its platforms, a train's
timetable, the overview, the end of a level, and then Yokohama,
Alessandria, Paris and Smiths Falls in the overview, each played to its end, so
that it opens the next. The autopilot plays (as the tests do). Writes screenshots/*.png; run from trainschedule/.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from p4emu import P4emu  # noqa: E402

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(HERE, 'screenshots')


def main():
    p = P4emu()

    def wait(test, secs=120):
        for _ in range(int(secs * 10)):
            if test():
                return
            p.run_for(0.1)
        raise RuntimeError('not in time')

    def fire():
        p.set('dbg_keys', 16)
        p.run_for(0.2)
        p.set('dbg_keys', 0)
        p.run_for(0.2)

    def clock():
        m = p.mem(p.sym('clock_s'), 2)
        return m[0] | m[1] << 8

    def on_screen():
        m = p.mem(p.sym('scrn'), 2)
        return p.mem(m[0] | m[1] << 8, 1000)

    def shot(name):
        print(name, p.png(os.path.join(OUT, name)))

    try:
        # the title, the game ready (its own interrupt and the march on)
        # (the ticker starting: the map list loaded, "press fire" up)
        wait(lambda: p.peek('eng_mode') == 1 and p.mem(p.sym('mus_song'), 2) == bytes([0, 0xE8])
             and p.peek('tk_on') == 1)
        p.run_for(1)
        shot('title.png')
        fire()
        wait(lambda: p.peek('eng_mode') == 2)
        p.run_for(1.5)
        shot('maps.png')
        cm_sel = p.lab['cm_sel']                 # up to the bulb, its page
        while p.mem(cm_sel)[0] != 255:
            p.set('dbg_keys', 1)
            p.run_for(0.2)
            p.set('dbg_keys', 0)
            p.run_for(0.2)
        fire()
        p.run_for(0.5)
        shot('help.png')
        fire()                                   # closed, down to Riesa
        p.set('dbg_keys', 2)
        p.run_for(0.2)
        p.set('dbg_keys', 0)
        p.run_for(0.5)
        fire()
        wait(lambda: p.peek('ptr_on') == 1)
        p.set('autopilot_on', 1)
        p.set('speed_i', 3)                      # x10 till nearly there
        wait(lambda: clock() >= 7 * 60, 200)
        p.set('speed_i', 1)
        wait(lambda: clock() >= 7 * 60 + 24, 60)
        p.run_for(0.5)
        shot('riesa.png')
        p.poke(p.lab['hits2'], [4])              # '.': the first train's timetable
        p.run_for(1)
        shot('timetable.png')
        p.poke(p.lab['hits2'], [8])              # Esc: closed
        p.run_for(0.5)
        p.poke(p.lab['hits2'], [1])              # Z: the overview
        p.run_for(1.5)
        shot('overview.png')
        p.poke(p.lab['hits2'], [1])
        p.run_for(1.5)
        p.set('speed_i', 3)
        wait(lambda: p.peek('ended') == 1, 300)
        p.run_for(1)
        shot('done.png')
        # OTHER MAP, the second, Yokohama (the choice has it chosen): the
        # overview, trains passing at Shinagawa and Kawasaki
        p.set('dbg_keys', 8)
        p.run_for(0.2)
        p.set('dbg_keys', 0)
        p.run_for(0.2)
        fire()
        wait(lambda: bytes([3, 8, 15, 15, 19, 5]) in on_screen())    # CHOOSE
        p.run_for(1.5)
        fire()
        wait(lambda: p.peek('ptr_on') == 1)
        p.set('autopilot_on', 1)
        p.set('speed_i', 3)
        wait(lambda: clock() >= 13 * 60 + 30, 200)
        p.set('speed_i', 1)
        if p.peek('zoom') != 1:                  # (it stays as it was)
            p.poke(p.lab['hits2'], [1])          # Z: the overview
        wait(lambda: clock() >= 13 * 60 + 40, 60)
        p.run_for(0.5)
        shot('yokohama.png')
        # to its end (a star opens the third), OTHER MAP, Alessandria: the
        # overview, Milan busy
        p.set('speed_i', 3)
        wait(lambda: p.peek('ended') == 1, 300)
        p.run_for(1)
        p.set('dbg_keys', 8)
        p.run_for(0.2)
        p.set('dbg_keys', 0)
        p.run_for(0.2)
        fire()
        wait(lambda: bytes([3, 8, 15, 15, 19, 5]) in on_screen())    # CHOOSE
        p.run_for(1.5)                           # (the choice has it chosen)
        fire()
        wait(lambda: p.peek('ptr_on') == 1)
        p.set('autopilot_on', 1)
        p.set('speed_i', 3)
        wait(lambda: clock() >= 7 * 60 + 30, 200)
        p.set('speed_i', 1)
        if p.peek('zoom') != 1:                  # (it stays as it was)
            p.poke(p.lab['hits2'], [1])          # Z: the overview
        wait(lambda: clock() >= 7 * 60 + 40, 60)
        p.run_for(0.5)
        shot('alessandria.png')
        # to its end (a star opens the fourth), OTHER MAP, Paris (the
        # choice has it chosen): the overview, trains on all its lines
        p.set('speed_i', 3)
        wait(lambda: p.peek('ended') == 1, 300)
        p.run_for(1)
        p.set('dbg_keys', 8)
        p.run_for(0.2)
        p.set('dbg_keys', 0)
        p.run_for(0.2)
        fire()
        wait(lambda: bytes([3, 8, 15, 15, 19, 5]) in on_screen())    # CHOOSE
        p.run_for(1.5)
        fire()
        wait(lambda: p.peek('ptr_on') == 1)
        p.set('autopilot_on', 1)
        p.set('speed_i', 3)
        wait(lambda: clock() >= 9 * 60, 200)
        p.set('speed_i', 1)
        if p.peek('zoom') != 1:                  # (it stays as it was)
            p.poke(p.lab['hits2'], [1])          # Z: the overview
        wait(lambda: clock() >= 9 * 60 + 10, 60)
        p.run_for(0.5)
        shot('paris.png')
        # to its end (a star opens the fifth), OTHER MAP, Smiths Falls (the
        # choice has it chosen): the overview, Smiths Falls busy
        p.set('speed_i', 3)
        wait(lambda: p.peek('ended') == 1, 300)
        p.run_for(1)
        p.set('dbg_keys', 8)
        p.run_for(0.2)
        p.set('dbg_keys', 0)
        p.run_for(0.2)
        fire()
        wait(lambda: bytes([3, 8, 15, 15, 19, 5]) in on_screen())    # CHOOSE
        p.run_for(1)
        fire()
        wait(lambda: p.peek('ptr_on') == 1)
        p.set('autopilot_on', 1)
        p.set('speed_i', 3)
        wait(lambda: clock() >= 21 * 60, 200)
        p.set('speed_i', 1)
        if p.peek('zoom') != 1:                  # (it stays as it was)
            p.poke(p.lab['hits2'], [1])          # Z: the overview
        wait(lambda: clock() >= 21 * 60 + 30, 60)
        p.run_for(0.5)
        shot('smithsfalls.png')
    finally:
        p.stop()


if __name__ == '__main__':
    main()
