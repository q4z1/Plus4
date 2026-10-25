#!/usr/bin/env python3
"""A plan for the joystick by the match's frames (play.s dbg_plan): the
same moves at the same frames, so a move of passes and a shot goes the
same way each time - in VICE here, to work it out, and in Yape for a
video (tests/video.py --plan).

    tests/plan.py [name] [pictures]

Waits 70 pictures for the teams to stand in their places, starts the
plan, and prints a line for each picture: who has the joystick, the
ball, the state of play.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, BITS, labels, held_from_start  # noqa: E402

# (frame, direction): from that frame on; none lets go, end ends it
PLANS = {
    # out to the wing, the winger standing with the ball: the yellow
    # chaser comes for it
    'standing': [(0, 'none'), (20, 'right'), (30, 'right+fire'), (33, 'none'),
                 (70, 'up'), (72, 'up+fire'), (75, 'none'),
                 (86, 'up'), (87, 'up+fire'), (90, 'none'),
                 (110, 'right'), (111, 'right+fire'), (114, 'none'),
                 (600, 'end')],
    # the same, and then the cyan player going for the yellow one with the
    # ball, and a sliding tackle
    'tackle': [(0, 'none'), (20, 'right'), (30, 'right+fire'), (33, 'none'),
               (70, 'up'), (72, 'up+fire'), (75, 'none'),
               (86, 'up'), (87, 'up+fire'), (90, 'none'),
               (110, 'right'), (111, 'right+fire'), (114, 'none'),
               (165, 'down+left'), (175, 'left'), (178, 'left+fire'), (181, 'none'),
               (600, 'end')],
    # three passes from the kick-off, each met and stopped, out to the
    # right wing, a run up it, a shot bent in from the wing - saved
    'passes': [(0, 'none'), (20, 'right'), (30, 'right+fire'), (33, 'none'),
               (70, 'up'), (72, 'up+fire'), (75, 'none'),
               (86, 'up'), (87, 'up+fire'), (90, 'none'),
               (110, 'right'), (111, 'right+fire'), (114, 'none'),
               (142, 'up'), (150, 'up+fire'), (159, 'up+left'), (185, 'none'),
               (400, 'end')],
}


def encode(plan):
    out = []
    for frame, d in plan:
        bits = 0
        if d == 'end':
            break
        for p in d.split('+'):
            bits |= BITS.get(p, 0)
        out += [frame & 255, frame >> 8, bits]
    return out + [255, 255, 0]


def start(emu, lab, plan):
    """the plan into the game and started (emu: Vice or Yape)"""
    emu.poke(lab['dbg_plan'], encode(plan))
    emu.poke(lab['dbg_on'], [2])


def main():
    name = sys.argv[1] if len(sys.argv) > 1 else 'passes'
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 150
    lab = labels()
    v = Vice(PRG, WORK)
    m = lambda k, c=1: list(v.mem(lab[k], c))
    try:
        held_from_start(v, lab, 'none')
        v.cmd('watch store %04x' % lab['shown'])
        for _ in range(70):
            v.cmd('x')
        x, xh, y, yh = m('o_xl', 23), m('o_xh', 23), m('o_yl', 23), m('o_yh', 23)
        print('cyan:', ' '.join('%d:%d,%d' % (i, x[i] + 256 * xh[i], y[i] + 256 * yh[i])
                                for i in range(11)))
        print('yellow:', ' '.join('%d:%d,%d' % (i, x[i] + 256 * xh[i], y[i] + 256 * yh[i])
                                  for i in range(11, 22)))
        start(v, lab, PLANS[name])
        for pic in range(n):
            v.cmd('x')
            x, xh, y, yh = m('o_xl', 23), m('o_xh', 23), m('o_yl', 23), m('o_yh', 23)
            ctrl = m('ctrl')[0]
            t = m('dbg_t', 2)
            print('%4d f%4d  ctrl %2d at %3d,%3d  ball %3d,%3d z %2d spd %4d  last %2d  %s%s score %d-%d' % (
                pic, t[0] + 256 * t[1], ctrl, x[ctrl] + 256 * xh[ctrl], y[ctrl] + 256 * yh[ctrl],
                x[22] + 256 * xh[22], y[22] + 256 * yh[22], m('o_zl', 23)[22],
                m('o_spl', 23)[22] + 256 * m('o_sph', 23)[22], m('last_pl')[0],
                'dead ' if m('dead_t')[0] else '', 'wait ' if m('kickoff')[0] else '',
                *m('score', 2)))
    finally:
        v.stop()


if __name__ == '__main__':
    main()
