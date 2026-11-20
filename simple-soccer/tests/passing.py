#!/usr/bin/env python3
"""Passing between team-mates in every phase of the frames (Luca: a pass
works fifty-fifty, as if the glue and the pass were out of step). The
logic runs each frame, the joystick is read once a picture (3 frames),
fire acted on every second frame, the dribble's touch every second -
so the same press may land on any of six phases.

    tests/passing.py [case ...] [-v]

dribble  the joystick's player runs up with the ball, the stick up; a
         team-mate ahead and a little to the right; after 0 - 11 frames
         of it fire tapped (one picture, two) with the stick still up:
         does the pass go (recv the mate), and does the mate get it?
letgo    as dribble, but the stick let go as fire goes down (Luca's
         glued ball: he stood, the ball rolled on out of reach)
first    a pass coming to the joystick's man (running to meet it), the
         stick let go; fire tapped 0 - 11 frames before it gets there:
         the pass on to the third man (a one-two)?

A line per phase and tap; the exit code counts the presses that went
wrong (a slide, the ball kept, the mate never reached).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from keep import Scene, BALL  # noqa: E402
from shot import BITS, labels  # noqa: E402

VERB = '-v' in sys.argv


def frames_mode(s):
    s.v.cmd('del')
    s.v.cmd('break %04x' % lab['play_frame'])


def watch(s, p, mate, n=90):
    """after the press: what became of it - 'pass' (the ball going to the
    mate, recv), 'slide', 'kept'; whether the mate got it (last_pl)"""
    what, got = None, False
    for f in range(n):
        s.v.cmd('x')
        if what is None:
            if s.get('o_slide', p):
                what = 'slide'
            elif s.get('recv') == mate and s.get('last_pl') == p:
                what = 'pass'
            elif s.get('recv') not in (mate, 255) and s.get('last_pl') == p:
                what = 'pass to %d' % s.get('recv')
        if s.get('last_pl') == mate:
            got = True
            break
        if s.get('last_team') != 0:
            break
    return what or 'kept', got, f


def others(s, keep):
    for i in range(22):
        if i not in keep and i not in (0, 11):
            s.obj(i, 40 + 12 * (i % 11), 700 if i < 11 else 40)


def dribble(phase, tap, letgo=False):
    s = Scene(lab)
    try:
        p = s.get('ctrl')
        mate = 9 if p != 9 else 8
        s.obj(p, 304, 600, d=0)
        s.obj(BALL, 304, 596)
        s.obj(mate, 330, 440)
        others(s, (p, mate))
        s.put('last_team', 0, 0)
        s.put('last_pl', 0, p)
        frames_mode(s)
        s.v.poke(lab['dbg_joy'], [BITS['up']])
        for _ in range(12 + phase):
            s.v.cmd('x')
        stick = 0 if letgo else BITS['up']
        s.v.poke(lab['dbg_joy'], [stick | BITS['fire']])
        for _ in range(tap):
            s.v.cmd('x')
        s.v.poke(lab['dbg_joy'], [stick])
        return watch(s, p, mate)
    finally:
        s.stop()


WAYS = [('up',), ('up', 'right'), ('right',), ('down', 'right'),
        ('down',), ('down', 'left'), ('left',), ('up', 'left')]
STEP = [(0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1)]


def dirs(d, phase, tap):
    """dribble as above, in way d (0 up, clockwise), in midfield; the
    mate 120 ahead that way and 20 to its right"""
    s = Scene(lab)
    try:
        p = s.get('ctrl')
        mate = 9 if p != 9 else 8
        dx, dy = STEP[d]
        x, y = 304, 380
        s.obj(p, x, y, d=d)
        s.obj(BALL, x + 4 * dx, y + 4 * dy)
        rx, ry = -dy, dx
        s.obj(mate, x + 120 * dx + 20 * rx + 60 * dx * 0,
              y + 120 * dy + 20 * ry)
        others(s, (p, mate))
        s.put('last_team', 0, 0)
        s.put('last_pl', 0, p)
        frames_mode(s)
        stick = 0
        for w in WAYS[d]:
            stick |= BITS[w]
        s.v.poke(lab['dbg_joy'], [stick])
        for _ in range(12 + phase):
            s.v.cmd('x')
        s.v.poke(lab['dbg_joy'], [stick | BITS['fire']])
        for _ in range(tap):
            s.v.cmd('x')
        s.v.poke(lab['dbg_joy'], [stick])
        return watch(s, p, mate)
    finally:
        s.stop()


def first(phase, tap):
    """the pass to p from below-left, 1792; fire tapped `phase` frames
    after it started (it takes some 14 to come): on to the mate ahead"""
    s = Scene(lab)
    try:
        p = 9
        mate = 10
        s.obj(p, 304, 520, d=0)
        s.obj(mate, 330, 380)
        s.obj(7, 150, 650, d=0)
        others(s, (p, mate, 7))
        s.obj(BALL, 304, 600, ty=520 - 32 * 80, speed=1792)
        s.put('last_team', 0, 0)
        s.put('last_pl', 0, 8)
        s.put('ctrl', 0, p)
        s.put('recv', 0, p)
        s.put('helper', 0, p)
        s.put('recv_t', 0, 100)
        frames_mode(s)
        s.v.poke(lab['dbg_joy'], [0])
        for _ in range(phase):
            s.v.cmd('x')
        s.v.poke(lab['dbg_joy'], [BITS['up'] | BITS['fire']])
        for _ in range(tap):
            s.v.cmd('x')
        s.v.poke(lab['dbg_joy'], [0])
        return watch(s, p, mate)
    finally:
        s.stop()


def main():
    global lab
    lab = labels()
    names = [a for a in sys.argv[1:] if not a.startswith('-')] or ['dribble', 'letgo', 'first']
    wrong = 0
    for name in names:
        good = 0
        n = 0
        if name.startswith('dir'):
            ways = [int(name[4:])] if name[4:] else range(8)
            for d in ways:
                for phase in range(6):
                    what, got, f = dirs(d, phase, 3)
                    ok = what == 'pass' and got
                    good += ok
                    n += 1
                    wrong += not ok
                    if VERB or not ok:
                        print('way %d phase %2d: %-10s %s (%d frames)'
                              % (d, phase, what, 'reached' if got else 'NOT reached', f),
                              flush=True)
            print('%-8s %d of %d passes reached the mate' % (name, good, n), flush=True)
            continue
        for tap in (3, 6):
            for phase in range(12):
                if name == 'letgo':
                    what, got, f = dribble(phase, tap, True)
                else:
                    what, got, f = (dribble if name == 'dribble' else first)(phase, tap)
                ok = what == 'pass' and got
                good += ok
                n += 1
                wrong += not ok
                if VERB or not ok:
                    print('%-8s tap %d phase %2d: %-10s %s (%d frames)'
                          % (name, tap, phase, what, 'reached' if got else 'NOT reached', f),
                          flush=True)
        print('%-8s %d of %d passes reached the mate' % (name, good, n), flush=True)
    return wrong


if __name__ == '__main__':
    sys.exit(main())
