#!/usr/bin/env python3
"""Who lies on the ground after a foul? (Luca, 16.11.2026: always the
first team's player, he thought.) Both ways, in a match in VICE, two
joysticks: a cyan player sliding into the yellow one on the ball from
behind, and a yellow one into the cyan one.

    tests/foulshow.py

A line each frame from the tackle on: each one's slide, fall (o_hit),
the whistle (rs_kind, last_team: whose free kick); screenshots
in ~/.cache/simple-soccer/test/foul-<case>.png.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, BITS, labels  # noqa: E402
import moves  # noqa: E402

lab = labels()


def bits(s):
    b = 0
    for p in s.split('+'):
        b |= BITS.get(p, 0)
    return b


# case: (fouler, victim, the fouler's stick plan [(frame, stick)], setup)
def cyan_fouls(s):
    moves.open_play(s, 7, team=1, holder=20)
    moves.field(s, cyan=((304, 372, 4), (150, 560, 0)), yellow=((150, 250, 4), (304, 380, 4)))
    s.put('ctrl_b', 20)
    s.obj(moves.BALL, 304, 389)


def yellow_fouls(s):
    moves.open_play(s, 9, team=0, holder=9)
    moves.field(s, cyan=((460, 640, 0), (304, 380, 0)), yellow=((150, 250, 4), (304, 388, 0)))
    s.put('ctrl_b', 20)
    s.obj(moves.BALL, 304, 371)


CASES = {'cyan': (7, 20, 'joy', cyan_fouls, 'down+fire'),
         'yellow': (20, 9, 'joyb', yellow_fouls, 'up+fire')}


def main():
    v = Vice(PRG, WORK)
    try:
        v.cmd('break %04x' % lab['main'])
        v.cmd('x')
        v.cmd('del')
        v.cmd('break %04x' % lab['play_frame'])
        for _ in range(120):                    # the match going
            v.cmd('x')
        for name, (fouler, victim, stick, setup, how) in CASES.items():
            s = moves.Setup()
            setup(s)
            for a, vals in s.pokes:
                v.poke(a, vals)
            v.poke(lab['two'], [1])
            v.poke(lab['ctrl'], [fouler if stick == 'joy' else victim])
            v.poke(lab['ctrl_b'], [fouler if stick == 'joyb' else victim])
            key = lab['dbg_joy'] if stick == 'joy' else lab['dbg_joyb']
            print('==', name, 'fouler', fouler, 'victim', victim)
            for f in range(70):
                v.poke(key, [bits(how) if f < 3 else 0])
                v.cmd('x')
                sl = v.mem(lab['o_slide'], 23)
                hit = v.mem(lab['o_hit'], 23)
                rs, = v.mem(lab['rs_kind'], 1)
                dead, lt, lp = v.mem(lab['dead_t'], 3)
                if f % 5 == 4 or f < 12:
                    print('%3d fouler slide %3d hit %3d | victim slide %3d hit %3d | rs %d dead %3d '
                          'last %d/%d | down: %s' % (
                              f, sl[fouler], hit[fouler], sl[victim], hit[victim], rs, dead, lt, lp,
                              [i for i in range(22) if sl[i]]))
                if f == 20:                     # (both lying, the whistle gone)
                    v.screenshot(os.path.join(WORK, 'foul-%s.png' % name))
            v.poke(key, [0])
            for _ in range(250):                # (the free kick taken, play on)
                v.cmd('x')
    finally:
        v.stop()


if __name__ == '__main__':
    main()
