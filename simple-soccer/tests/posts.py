#!/usr/bin/env python3
"""The goal's width against its drawing (Luca: a ball just past the left
post was a goal, on the right it was not). The posts are drawn at x
269-270 and 339-340 (data/pitch.txt, the goal at the top); a ball
whose middle crosses the line between 269 and 340 is a goal.

    tests/posts.py

The ball rolled slowly over the top goal line at each x below, the
keepers out of the way; a line each, goal or not, and whether that is
right. The exit code counts the wrong ones.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from keep import Scene, BALL  # noqa: E402
from shot import labels  # noqa: E402

CASES = [(262, False), (266, False), (268, False), (269, True), (271, True), (304, True),
         (338, True), (340, True), (341, False), (346, False)]


def main():
    lab = labels()
    wrong = 0
    for x, want in CASES:
        s = Scene(lab)
        try:
            s.v.cmd('del')
            s.v.cmd('break %04x' % lab['play_frame'])
            s.obj(0, 100, 700)
            s.obj(11, 560, 60)
            for i in list(range(1, 11)) + list(range(12, 22)):
                s.obj(i, 40 + 20 * (i % 11), 400)
            s.obj(BALL, x, 54, tx=x, ty=-200, speed=512)
            s.put('last_team', 0, 0)
            s.put('last_pl', 0, 9)
            score = s.get('score') + s.get('score', 1)     # (goal: 1 from the
            goal = False                                    # match's start)
            for _ in range(20):
                s.v.cmd('x')
                if s.get('score') + s.get('score', 1) != score:
                    goal = True
                    break
                if s.get('dead_t'):
                    break
            ok = goal == want
            wrong += not ok
            print('x %3d  %-8s %s' % (x, 'goal' if goal else 'no goal', 'ok' if ok else 'WRONG'),
                  flush=True)
        finally:
            s.stop()
    return wrong


if __name__ == '__main__':
    sys.exit(main())
