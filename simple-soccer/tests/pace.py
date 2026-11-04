#!/usr/bin/env python3
"""How smooth a match runs: a random joystick plan by the match's frames
(dbg_plan) from the kick-off, rnd made to leave out the beam ($FF1E) and
started at 1, and the frames between one picture shown and the next
counted - each should be PACE (3); more is a stutter.

    tests/pace.py [seeds] [pictures]      seeds: e.g. 1,2,3 (default)

A line per seed: the share of pictures on time and how many took 4, 5,
6+ frames, and the frame where the worst one came; then all seeds
together. The match goes the same way each time for the same build, but
not from one build to another once the pictures' timing changes what
happens in it (the logic runs once a picture) - so compare the shares
over several seeds, not single pictures.
"""
import collections
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, BITS, labels  # noqa: E402

DIRS = ['up', 'up+right', 'right', 'down+right', 'down', 'down+left', 'left',
        'up+left', 'none']
PACE = 3


def plan(seed):
    """64 entries (frame, J_ bits): a way held 15-120 frames, fire now
    and then - tapped, held, or pressed without the ball"""
    rnd = random.Random(seed)
    out, f = [], 0
    while len(out) < 62:
        bits = 0
        for p in rnd.choice(DIRS).split('+'):
            bits |= BITS.get(p, 0)
        if rnd.random() < 0.35:
            out.append((f, bits | BITS['fire']))
            f += rnd.choice([3, 6, 12, 36])
        out.append((f, bits))
        f += rnd.randint(15, 120)
    return out


def game_rnd():
    """play.s's rnd (the title has one of its own, above $C000)"""
    for line in open(os.path.join(os.path.dirname(PRG), 'simple-soccer.lbl')):
        p = line.split()
        if len(p) == 3 and p[2] == '.rnd' and int(p[1], 16) < 0xC000:
            return int(p[1], 16)
    raise SystemExit('no rnd')


def encode(p):
    b = []
    for f, bits in p:
        b += [f & 255, f >> 8, bits]
    return b + [255, 255, 0]


def run(lab, seed, pictures):
    v = Vice(PRG, WORK)
    try:
        v.cmd('break %04x' % lab['main'])
        v.cmd('x')
        v.cmd('del')
        rnd = game_rnd()
        assert list(v.mem(rnd + 7, 3)) == [0x4D, 0x1E, 0xFF], 'rnd has changed'
        v.poke(rnd + 7, [0x49, 0x00, 0xEA])     # eor $FF1E -> eor #0
        v.poke(lab['z_rnd'], [1])
        v.poke(lab['dbg_plan'], encode(plan(seed)))
        v.poke(lab['dbg_on'], [2])
        v.cmd('watch store %04x' % lab['shown'])
        gaps = collections.Counter()
        worst, at = 0, 0
        last = None
        frames = 0
        for _ in range(pictures):
            v.cmd('x')
            f = v.mem(lab['frames'], 1)[0]
            if last is not None:
                g = (f - last) & 255
                gaps[g] += 1
                frames += g
                if g > worst:
                    worst, at = g, frames
            last = f
        return gaps, worst, at
    finally:
        v.stop()


def line(name, gaps, extra=''):
    n = sum(gaps.values())
    on = gaps.get(PACE, 0)
    print('%-8s %5.1f %% on time  4: %3d  5: %3d  6+: %3d  (%d pictures)%s' % (
        name, 100.0 * on / n, gaps.get(4, 0), gaps.get(5, 0),
        sum(c for g, c in gaps.items() if g >= 6), n, extra), flush=True)


def main():
    seeds = [int(s) for s in (sys.argv[1] if len(sys.argv) > 1 else '1,2,3').split(',')]
    pictures = int(sys.argv[2]) if len(sys.argv) > 2 else 800
    lab = labels()
    total = collections.Counter()
    for seed in seeds:
        gaps, worst, at = run(lab, seed, pictures)
        total.update(gaps)
        line('seed %d' % seed, gaps, '  worst %d frames at frame %d' % (worst, at))
    if len(seeds) > 1:
        line('all', total)


if __name__ == '__main__':
    main()
