#!/usr/bin/env python3
"""Do the players run smoothly? A plan of tests/plan.py, and for each
picture built (at place) where each player is shown: his way since the
last picture, per frame. A player running smoothly goes the same way
each frame; one that hops stands in some pictures and jumps in others.

    tests/smooth.py [plan] [pictures]

Prints, for those running (not the joystick's, the chaser, the keepers),
how often a picture showed them standing between two that showed them
moving, and how far the way per frame strays from their own mean.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import plan  # noqa: E402
from vice import Vice  # noqa: E402
from shot import PRG, WORK, labels, held_from_start  # noqa: E402


def main():
    name = sys.argv[1] if len(sys.argv) > 1 else 'passes'
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 120
    lab = labels()
    v = Vice(PRG, WORK)
    m = lambda k, c=1: list(v.mem(lab[k], c))
    try:
        held_from_start(v, lab, 'none')
        v.cmd('watch store %04x' % lab['shown'])
        for _ in range(70):
            v.cmd('x')
        plan.start(v, lab, plan.PLANS[name])
        v.cmd('del')
        v.cmd('break %04x' % lab['place'])
        prev = None
        ways = {}
        for _ in range(n):
            v.cmd('x')
            t = m('dbg_t', 2)
            f = t[0] + 256 * t[1]
            x, xh, y, yh = m('o_xl', 22), m('o_xh', 22), m('o_yl', 22), m('o_yh', 22)
            busy = {0, 11, m('ctrl')[0], m('chaser')[0]}
            pos = [(x[i] + 256 * xh[i], y[i] + 256 * yh[i]) for i in range(22)]
            if prev and f > prev[0]:
                for i in range(22):
                    if i in busy:
                        ways.setdefault(i, []).append(None)
                        continue
                    dx, dy = pos[i][0] - prev[1][i][0], pos[i][1] - prev[1][i][1]
                    ways.setdefault(i, []).append(((dx * dx + dy * dy) ** 0.5) / (f - prev[0]))
            prev = (f, pos)
        holes = runs = 0
        spread = []
        for i, w in ways.items():
            for a, b, c in zip(w, w[1:], w[2:]):
                if None in (a, b, c):
                    continue
                if a > 0.3 and c > 0.3:
                    runs += 1
                    if b < 0.1:
                        holes += 1
                    spread.append(abs(b - (a + c) / 2))
        print('pictures between two moving ones: %d, standing in %d' % (runs, holes))
        if spread:
            spread.sort()
            print('way per frame against its neighbours: median %.2f, 90%% %.2f, most %.2f px'
                  % (spread[len(spread) // 2], spread[len(spread) * 9 // 10], spread[-1]))
    finally:
        v.stop()


if __name__ == '__main__':
    main()
