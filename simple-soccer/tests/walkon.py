#!/usr/bin/env python3
"""The teams coming on before a match (play.s walk_on, walking), from the
disk in VICE: a match started from the title - the players at first past
the right touch line, a step apart (TUN_X + 8 each), walking on to their
places for the kick-off, the ball dead meanwhile (dead_t 1); once they all
stand there (enter 0), the kick-off - and the joystick's player able to
take it. A test's match (the title skipped, tests/vice.py) has them lined
up at once, as before. The ball on the middle spot then (restart had
put it at the last set piece's place, 0,0: no kick-off for the stick).

    tests/walkon.py

A line each, OK or WRONG; the exit code counts the wrong ones.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import league as L  # noqa: E402
import cpuplay as C  # noqa: E402
from vice import Vice  # noqa: E402

TUN_X = 584                     # (play.s)


def places(v):
    m = {n: v.mem(C.one(n), 22) for n in ('o_xl', 'o_xh', 'o_yl', 'o_yh')}
    return [(m['o_xl'][i] + 256 * m['o_xh'][i], m['o_yl'][i] + 256 * m['o_yh'][i]) for i in range(22)]


def main():
    wrong = 0

    def report(name, ok, text):
        nonlocal wrong
        print('%-8s %s %s' % (name, text, 'OK' if ok else 'WRONG'), flush=True)
        wrong += not ok
    v = Vice(L.D64, L.CACHE, drive='1541', title=True)
    try:
        L.wait(v, lambda: L.at_title(v), 'the title')
        v.run_for(0.5)
        v.poke(L.K_CH, [0, 0, 0, L.T['GERMANY'], L.T['BRAZIL']])
        v.cmd('break %04x' % C.one('play_frame'))
        L.press(v)
        v.cmd('x')                      # (the match's first frame)
        start = places(v)
        report('start', all(x >= TUN_X - 4 for x, _ in start) and v.mem(C.one('enter'), 1)[0] == 1,
               'all past the touch line: x %d - %d' % (min(x for x, _ in start), max(x for x, _ in start)))
        frames, shot = 0, False
        while frames < 2000 and v.mem(C.one('enter'), 1)[0]:
            v.cmd('x')
            frames += 1
            if not shot and frames == 150:
                v.screenshot(os.path.join(L.CACHE, 'walkon.png'))
                shot = True
            if v.mem(C.one('dead_t'), 1)[0] == 0:
                break
        dead = v.mem(C.one('dead_t'), 1)[0]
        arrived = places(v)
        mov = v.mem(C.one('o_mov'), 22)
        if any(mov):
            t = {n: v.mem(C.one(n), 22) for n in ('o_txl', 'o_txh', 'o_tyl', 'o_tyh')}
            print('   still on the way:', [(i, arrived[i], (t['o_txl'][i] + 256 * t['o_txh'][i],
                                                       t['o_tyl'][i] + 256 * t['o_tyh'][i]))
                                         for i in range(22) if mov[i]])
        report('walk', not v.mem(C.one('enter'), 1)[0] and frames < 2000,
               'on and in their places after %d frames, the ball dead till then (dead_t %d)' % (frames, dead))
        for _ in range(5):
            v.cmd('x')
        lined = places(v)
        far = [i for i in range(22) if abs(lined[i][0] - arrived[i][0]) > 2 or abs(lined[i][1] - arrived[i][1]) > 2]
        bx = v.mem(C.one('o_xl') + 22, 1)[0] + 256 * v.mem(C.one('o_xh') + 22, 1)[0]
        by = v.mem(C.one('o_yl') + 22, 1)[0] + 256 * v.mem(C.one('o_yh') + 22, 1)[0]
        report('kickoff', v.mem(C.one('kickoff'), 1)[0] == 1 and v.mem(C.one('dead_t'), 1)[0] == 0
               and not far and (bx, by) == (304, 369),
               'the kick-off waiting, the ball at %d,%d (the middle spot: once at 0,0), no one moved '
               'by the line-up: %s' % (bx, by, far or 'none'))
        v.cmd('del')
    finally:
        v.stop()
    return wrong


if __name__ == '__main__':
    sys.exit(main())
