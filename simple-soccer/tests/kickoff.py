#!/usr/bin/env python3
"""A match started as a player starts it: from a copy of the disk in Yape,
the title, fire - then its first seconds left alone. The kick-off waits
for the cyan 9 (the stick untouched): no whistle, no set piece but the
kick-off, 0-0 - not as play.s once had it, its offside mark ($ED) as
the title left it (0: the cyan keeper offside, a penalty at once).

    tests/kickoff.py

A line every second; OK or WRONG last, the exit code 1 if wrong.
"""
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import moves  # noqa: E402
from yape import Yape  # noqa: E402

OFF_PL = 0xED                   # (play.s)
SECS = 10


def main():
    lab = moves.labels()
    img = os.path.join(moves.WORK, 'kickoff.d64')
    subprocess.run(['cp', moves.D64, img], check=True)
    y = Yape(img, title=True, env=('SDL_AUDIODRIVER=dummy',))

    def wait(test, what, secs=180):
        t = time.time()
        while not test():
            if time.time() - t > secs:
                raise RuntimeError('waited in vain: ' + what)
            time.sleep(0.3)
    ok = True
    try:
        wait(lambda: y.mem(0xfffe, 2) == [lab['synth'], 0] and y.mem(0xff06, 1)[0] == 0x1b, 'the title')
        print('the title: $ED, $EE %s' % y.mem(OFF_PL, 2))
        time.sleep(1)
        y.poke(lab['dbg_joy'], [moves.bits('fire')])
        time.sleep(0.15)
        y.poke(lab['dbg_joy'], [0])
        wait(lambda: y.mem(0xFFFE, 2)[1] != 0 and y.mem(0xFF07, 1)[0] & 0x10
             and y.mem(0xFF06, 1)[0] & 0x10, 'the match')
        wait(lambda: y.mem(lab['enter'], 1)[0] == 0, 'the teams on (walk_on)')
        t0 = time.time()
        while time.time() - t0 < SECS:
            ko, = y.mem(lab['kickoff'], 1)
            rs, = y.mem(lab['rs_kind'], 1)
            dead, = y.mem(lab['dead_t'], 1)
            taker, = y.mem(lab['taker'], 1)
            score = y.mem(lab['score'], 2)
            print('%4.1f s: kick-off %d, set piece %d, dead %d, taker %d, %d-%d, offside mark %s' % (
                time.time() - t0, ko, rs, dead, taker, score[0], score[1], y.mem(OFF_PL, 2)))
            ok = ok and ko == 1 and rs == 0 and dead == 0 and taker == 9 and score == [0, 0]
            time.sleep(1.0)
    finally:
        y.stop()
        os.remove(img)
    print('OK' if ok else 'WRONG')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
