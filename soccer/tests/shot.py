#!/usr/bin/env python3
"""Run the soccer game in a headless VICE and look at it.

    tests/shot.py [seconds] [out.png] [dir=frames ...]

Lets the game run that many seconds of its own time (its picture count,
not the host's clock: VICE runs in warp), then saves a screenshot. Each
dir=frames holds a direction (up, down, left, right, fire, or several
joined by +) for that many pictures first, through dbg_joy.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PRG = os.path.join(HERE, 'build', 'soccer.prg')
WORK = os.path.expanduser('~/.cache/soccer/test')
BITS = {'up': 1, 'down': 2, 'left': 4, 'right': 8, 'fire': 16}


def labels():
    out = {}
    for line in open(os.path.join(HERE, 'build', 'soccer.lbl')):
        p = line.split()
        if len(p) == 3 and p[0] == 'al':
            out[p[2].lstrip('.')] = int(p[1], 16)
    return out


def run_pictures(v, lab, n):
    """Let the game run n pictures of 50 a second (its frames counter)."""
    while n > 0:
        f0 = v.mem(lab['frames'], 1)[0]
        v.run_for(0.05)
        f1 = v.mem(lab['frames'], 1)[0]
        n -= (f1 - f0) & 255


def main():
    secs = float(sys.argv[1]) if len(sys.argv) > 1 else 3
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(WORK, 'shot.png')
    lab = labels()
    v = Vice(PRG, WORK)
    try:
        # till the game runs: its frames counter moves
        for _ in range(200):
            v.run_for(0.1)
            if lab['main'] <= int(v.cmd('r').splitlines()[1].split()[0][2:], 16) < 0xC000:
                break
        run_pictures(v, lab, 10)
        for a in sys.argv[3:]:
            d, n = a.split('=')
            bits = 0
            for p in d.split('+'):
                bits |= BITS[p]
            v.poke(lab['dbg_joy'], [bits])
            run_pictures(v, lab, int(n))
            v.poke(lab['dbg_joy'], [0])
        run_pictures(v, lab, int(secs * 50))
        v.screenshot(out)
        print(out)
    finally:
        v.stop()


if __name__ == '__main__':
    main()
