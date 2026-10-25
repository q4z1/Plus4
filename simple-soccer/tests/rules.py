#!/usr/bin/env python3
"""The rules at work: the joystick moved to a plan from the program's
start, and a line each time the state of play changes - the ball dead,
a set piece waiting and for whom, taken, a goal.

    tests/rules.py [plan]

plan: picture:direction,... (directions as in shot.py, + joined; none
lets go), by default a shot into touch on the left from the kick-off.
Runs 600 pictures (36 seconds), or until the plan's last entry says end.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, BITS, labels, held_from_start  # noqa: E402

KINDS = ['kick-off', 'throw-in', 'goal kick', 'corner', 'keeper\'s']
TEAMS = ['cyan', 'yellow']
PLAN = '0:none,5:left+fire,12:left,30:none,600:end'


def main():
    plan = []
    for item in (sys.argv[1] if len(sys.argv) > 1 else PLAN).split(','):
        at, d = item.split(':')
        plan.append((int(at), d))
    lab = labels()
    v = Vice(PRG, WORK)
    try:
        held_from_start(v, lab, 'none')
        v.cmd('watch store %04x' % lab['shown'])
        last = None
        for pic in range(10000):
            for at, d in plan:
                if at == pic:
                    if d == 'end':
                        return
                    bits = 0
                    for p in d.split('+'):
                        bits |= BITS.get(p, 0)
                    v.poke(lab['dbg_joy'], [bits])
            v.cmd('x')
            m = lambda n, c=1: list(v.mem(lab[n], c))
            dead, kick, goal = m('dead_t')[0], m('kickoff')[0], m('goal')[0]
            kind, team, taker = m('rs_kind')[0], m('rs_team')[0], m('taker')[0]
            score = m('score', 2)
            state = ('dead' if dead else 'waiting' if kick else 'play', goal,
                     kind if dead or kick else None, team if dead or kick else None,
                     taker if kick else None, tuple(score))
            if state != last:
                bx = m('o_xl', 23)[22] + 256 * m('o_xh', 23)[22]
                by = m('o_yl', 23)[22] + 256 * m('o_yh', 23)[22]
                text = state[0]
                if dead or kick:
                    text += ' %s for %s' % (KINDS[kind], TEAMS[team & 1])
                if kick:
                    text += ', taker %d' % taker
                if goal:
                    text += ' (goal)'
                print('picture %4d: %-40s ball %3d,%3d z %2d  score %d-%d  ctrl %d  last %d' % (
                    pic, text, bx, by, m('o_zl', 23)[22], score[0], score[1], m('ctrl')[0],
                    m('last_pl')[0]))
                last = state
    finally:
        v.stop()


if __name__ == '__main__':
    main()
