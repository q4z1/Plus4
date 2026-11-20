#!/usr/bin/env python3
"""Fire tapped with the ball at the joystick's player's feet, in a match
with the joystick moved at random: does a pass (or any kick) follow?
Luca: three passes in ten the ball stays glued to the foot.

    tests/taps.py [pictures] [seed] [-v]

The plan as soak.py's, but every fire a tap of one or two pictures
(passes). A tap counts when, as fire goes down, the joystick's player
has the ball (last_pl, the ball within CLOSE, low, play on). Within 15
pictures the ball should leave him - kicked (faster than 1100, touched
by him) - else the line 'glued' with what was going on.
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, BITS, labels, held_from_start  # noqa: E402
from soak import DIRS  # noqa: E402

BALL = 22
VERB = '-v' in sys.argv


def plan(rnd, n):
    out, pic = [], 0
    while pic < n:
        bits = 0
        for p in rnd.choice(DIRS).split('+'):
            bits |= BITS.get(p, 0)
        hold = rnd.randint(5, 30)
        if rnd.random() < 0.6:
            f = rnd.choice([1, 1, 2])
            out.append((pic, bits | BITS['fire']))
            out.append((pic + f, bits))
        else:
            out.append((pic, bits))
        pic += hold
    return out


def trace(v, lab, m, pa, pic0):
    """frame by frame from picture pic0 on: what the control sees"""
    v.cmd('del')
    v.cmd('break %04x' % lab['play_frame'])
    w = lambda lo, hi, i: m(lo, i) + 256 * m(hi, i)
    pic = pic0
    for f in range(60):
        out = v.cmd('x')
        if '%04x' % lab['eng_end'] in out.lower():
            pass
        c = m('ctrl')
        dx = w('o_xl', 'o_xh', BALL) - w('o_xl', 'o_xh', c)
        dy = w('o_yl', 'o_yh', BALL) - w('o_yl', 'o_yh', c)
        print('f %3d frame_n %3d pj %02x pf %02x fire_n %02x pass_q %d ctrl %d dir %d ball %+d,%+d'
              ' d2 %d z %d sp %d last %d recv %d mov %d'
              % (f, m('frame_n'), m('pj'), m('pf'), m('fire_n'), m('pass_q'), c, m('o_dir', c),
                 dx, dy, dx * dx + dy * dy, m('o_zl', BALL), w('o_spl', 'o_sph', BALL),
                 m('last_pl'), m('recv'), m('o_mov', c)))
        if f % 3 == 2:
            pic += 1
            if pic in pa:
                v.poke(lab['dbg_joy'], [pa[pic]])
                print('   joystick %02x' % pa[pic])


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('-')]
    n = int(args[0]) if args else 3000
    seed = int(args[1]) if len(args) > 1 else 1
    pa = dict(plan(random.Random(seed), n))
    lab = labels()
    v = Vice(PRG, WORK, title=False)
    a0 = lab['o_xf']
    span = lab['o_dvd'] + 23 - a0
    m = lambda name, i=0: v.mem(lab[name] + i, 1)[0]
    taps = glued = 0
    pending = None
    try:
        held_from_start(v, lab, 'none')
        v.cmd('break %04x' % lab['eng_end'])
        tr = [int(a.split('=')[1]) for a in sys.argv if a.startswith('--trace=')]
        for pic in range(n):
            if pic in pa:
                v.poke(lab['dbg_joy'], [pa[pic]])
            if tr and pic == tr[0] - 2:
                trace(v, lab, m, pa, pic)
                return
            v.cmd('x')
            raw = v.mem(a0, span)
            g = lambda name, i: raw[lab[name] - a0 + i]
            w = lambda lo, hi, i: g(lo, i) + 256 * g(hi, i)
            ctrl, last = m('ctrl'), m('last_pl')
            live = not m('dead_t') and not m('kickoff')
            sp = w('o_spl', 'o_sph', BALL)
            if pending:
                p, t0, info = pending
                if last == p and sp >= 1100:
                    pending = None
                    if VERB:
                        print('%5d ok    tap at %d, kicked after %d' % (pic, t0, pic - t0))
                elif last != p or not live:
                    pending = None
                    if VERB:
                        print('%5d gone  tap at %d: now %d has it' % (pic, t0, last))
                elif pic - t0 >= 15:
                    pending = None
                    glued += 1
                    print('%5d glued %s' % (t0, info), flush=True)
            prev = pa.get(pic)
            if prev is not None and prev & BITS['fire'] and live and ctrl < 22 and last == ctrl:
                dx = w('o_xl', 'o_xh', BALL) - w('o_xl', 'o_xh', ctrl)
                dy = w('o_yl', 'o_yh', BALL) - w('o_yl', 'o_yh', ctrl)
                z = g('o_zl', BALL)
                if dx * dx + dy * dy <= 72 and z < 5 and not pending:
                    taps += 1
                    info = ('ctrl %d dir %d stick %s, ball %+d,%+d z %d speed %d, recv %d'
                            ' helper %d slide %d lock %d,%d fire_n %02x pass_q %s'
                            % (ctrl, g('o_dir', ctrl), DIRS[[1, 9, 8, 10, 2, 6, 4, 5, 0].index(
                                prev & 15)] if (prev & 15) in [1, 9, 8, 10, 2, 6, 4, 5, 0] else prev & 15,
                               dx, dy, z, sp, m('recv'), m('helper'), g('o_slide', ctrl),
                               m('lock_t'), m('lock_t', 1), m('fire_n'),
                               v.mem(lab['pass_q'], 2)))
                    pending = (ctrl, pic, info)
    finally:
        v.stop()
    print('%d taps with the ball, %d glued' % (taps, glued))
    sys.exit(min(glued, 255))


if __name__ == '__main__':
    main()
