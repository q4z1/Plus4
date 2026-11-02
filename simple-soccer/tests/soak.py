#!/usr/bin/env python3
"""A long match with the joystick moved at random, looked at picture by
picture for what should not happen.

    tests/soak.py [pictures] [seed] [two]

pictures: how many (by default 6000, six minutes of the match); seed:
the random plan's (by default 1); two: both teams on joysticks (the
second's own plan), else the yellow team the computer's. A line for
each thing seen, with the picture and where:

jump     a player more than JUMP pixels from where he was a picture
         before (play going on: not a set piece's placing)
keeper   a keeper further than KEEPER_OUT from his line (play going on)
hangs    the ball in the air, its height and step the same for HANG
         pictures
out      the ball outside the walls round the pitch
gone     a set piece waiting, a joystick's player out of the picture

The exit code counts the things seen (at most 255).
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, BITS, labels, held_from_start  # noqa: E402

NOBJ = 23
BALL = 22
JUMP = 30
KEEPER_OUT = 220
HANG = 15
LINE = (49, 689)
GROUND_X, GROUND_Y = 23, 58
KINDS = ['kick-off', 'throw-in', 'goal kick', 'corner', 'keeper\'s', 'free kick', 'penalty']
DIRS = ['up', 'up+right', 'right', 'down+right', 'down', 'down+left', 'left',
        'up+left', 'none']


def state(lab, a0, raw, i):
    """object i's every o_/c_ byte, as name=value"""
    names = sorted((a, n) for n, a in lab.items()
                   if (n.startswith('o_') or n.startswith('c_')) and a0 <= a < a0 + len(raw))
    return ' '.join('%s=%d' % (n[2:], raw[a - a0 + i]) for a, n in names)


def plan(rnd, n):
    """[(picture, bits)]: a way held 5-40 pictures, fire now and then -
    tapped (a pass), held (a shot) or pressed without the ball (a tackle)"""
    out, pic = [], 0
    while pic < n:
        bits = 0
        for p in rnd.choice(DIRS).split('+'):
            bits |= BITS.get(p, 0)
        hold = rnd.randint(5, 40)
        if rnd.random() < 0.35:
            f = rnd.choice([1, 2, 4, 12])
            out.append((pic, bits | BITS['fire']))
            out.append((pic + f, bits))
        else:
            out.append((pic, bits))
        pic += hold
    return out


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 6000
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    two = len(sys.argv) > 3 and sys.argv[3] == 'two'
    rnd = random.Random(seed)
    pa = dict(plan(rnd, n))
    pb = dict(plan(rnd, n)) if two else {}
    lab = labels()
    v = Vice(PRG, WORK, title=False)
    seen = 0
    try:
        held_from_start(v, lab, 'none')
        if two:
            v.poke(lab['two'], [1])
        v.cmd('break %04x' % lab['eng_end'])     # (a picture's work done:
        #                                          the teams not swapped)
        a0 = lab['o_xf']
        span = lab['o_dvd'] + NOBJ - a0
        m = lambda name, i=0: v.mem(lab[name] + i, 1)[0]
        last = None
        hang = 0
        was_live = False
        gone = set()
        pieces = last_kick = 0
        for pic in range(n):
            if pic in pa:
                v.poke(lab['dbg_joy'], [pa[pic]])
            if pic in pb:
                v.poke(lab['dbg_joyb'], [pb[pic]])
            v.cmd('x')
            raw = v.mem(a0, span)
            g = lambda name, i: raw[lab[name] - a0 + i]
            w = lambda lo, hi, i: (g(lo, i) + 256 * g(hi, i)) - (65536 if g(hi, i) > 127 else 0)
            pos = [(w('o_xl', 'o_xh', i), w('o_yl', 'o_yh', i)) for i in range(NOBJ)]
            z, dz = g('o_zl', BALL), g('o_dzl', BALL) * 256 + g('o_dzf', BALL)
            dead, kick, flip = m('dead_t'), m('kickoff'), m('flip')
            live = not dead and not kick

            def tell(what, text):
                nonlocal seen
                seen += 1
                print('%5d %-7s %s' % (pic, what, text), flush=True)
            if last and live and was_live:
                for i in range(BALL):
                    dx, dy = pos[i][0] - last[i][0], pos[i][1] - last[i][1]
                    if abs(dx) > JUMP or abs(dy) > JUMP:
                        tell('jump', 'player %d %s -> %s' % (i, last[i], pos[i]))
                        for st, r in (('before', last_raw), ('after', raw)):
                            print('        %s: %s' % (st, state(lab, a0, r, i)))
                        print('        ctrl %d/%d, recv %d, helper %d, kick_pl %d, taker %d'
                              % tuple(m(n) for n in ('ctrl', 'ctrl_b', 'recv', 'helper',
                                                     'kick_pl', 'taker')))
            for k, team in (((0, 0), (11, 1)) if live else ()):
                line = LINE[team ^ flip ^ 1]
                if abs(pos[k][1] - line) > KEEPER_OUT:
                    tell('keeper', '%d at %s, his line y %d' % (k, pos[k], line))
            if z > 0 and last and z == last_z and dz == last_dz:
                hang += 1
                if hang == HANG:
                    tell('hangs', 'ball at %s height %d step %d' % (pos[BALL], z, dz))
            else:
                hang = 0
            bx, by = pos[BALL]
            if not (0 <= bx <= 620 and 0 <= by <= 740):
                tell('out', 'ball at %s' % (pos[BALL],))
            if kick:
                cx = m('cam_x') + 256 * m('cam_x', 1)
                cy = m('cam_y') + 256 * m('cam_y', 1)
                for c in ('ctrl', 'ctrl_b'):
                    p = m(c)
                    if p < BALL:
                        sx = pos[p][0] - GROUND_X - cx
                        sy = pos[p][1] + GROUND_Y - cy
                        out = not (0 <= sx < 304 and 0 <= sy < 192)
                        if out and c not in gone:
                            tell('gone', '%s %d at %s, the ball at %s, %s for %d'
                                 % (c, p, pos[p], pos[BALL], KINDS[m('rs_kind')], m('rs_team')))
                        if out:
                            gone.add(c)
            else:
                gone = set()
            pieces += bool(kick) and not last_kick
            last, last_z, last_dz, was_live, last_kick = pos, z, dz, live, kick
            last_raw = raw
            if seen > 200:
                break
        print('%d pictures, %d set pieces, the score %d-%d'
              % (pic + 1, pieces, m('score'), m('score', 1)))
    finally:
        v.stop()
    print('%d seen' % seen)
    sys.exit(min(seen, 255))


if __name__ == '__main__':
    main()
