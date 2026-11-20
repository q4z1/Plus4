#!/usr/bin/env python3
"""Every touch of the ball in a match with the joystick moved at random
(soak.py's plan): who touched it, from which routine (touch_x's caller),
the ball's height and speed then, who had it before and how far it went
since. Luca: the players head every passing ball, team-mates too (own
goals like rain), and every shot is blocked.

    tests/touches.py [pictures] [seed] [-v]

A summary: the touches after a kick (pass or shot, the ball's speed
SHOT_MIN or more at the kick) by another player, by caller and by the
team (mate / them), with the ball's height; -v a line each.
"""
import collections
import os
import random
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, labels, held_from_start  # noqa: E402
from soak import plan  # noqa: E402

BALL = 22
SHOT_MIN = 1700
VERB = '-v' in sys.argv


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('-')]
    n = int(args[0]) if args else 3000
    seed = int(args[1]) if len(args) > 1 else 1
    rnd = random.Random(seed)
    pa = dict(plan(rnd, n))
    lab = labels()
    code = sorted((a, nm) for nm, a in lab.items()
                  if lab['main'] <= a < 0xFD00 and not nm.startswith('@')
                  and not nm.startswith('o_') and not nm.startswith('c_'))

    def where(a):
        best = None
        for ad, nm in code:
            if ad <= a:
                best = (ad, nm)
            else:
                break
        return best[1] if best else '?'

    v = Vice(PRG, WORK, title=False)
    m = lambda name, i=0: v.mem(lab[name] + i, 1)[0]
    w16 = lambda lo, hi, i: m(lo, i) + 256 * m(hi, i)
    stats = collections.Counter()
    heights = collections.defaultdict(list)
    kick = None     # (player, team, speed, x, y) of the last kick
    try:
        held_from_start(v, lab, 'none')
        v.cmd('break %04x' % lab['eng_end'])
        v.cmd('break %04x' % lab['touch_x'])
        pic = 0
        prev_sp = 0
        while pic < n:
            out = v.cmd('x')
            pc = int(re.search(r'\.C:([0-9a-f]{4})', out).group(1), 16)
            if pc == lab['eng_end']:
                pic += 1
                if pic in pa:
                    v.poke(lab['dbg_joy'], [pa[pic]])
                # a kick: the ball fast now, touched last by kick_pl
                sp = w16('o_spl', 'o_sph', BALL)
                if sp >= 1100 and sp > prev_sp + 300 and not m('kickoff'):
                    p = m('last_pl')
                    kick = (p, 0 if p < 11 else 1, sp,
                            w16('o_xl', 'o_xh', BALL), w16('o_yl', 'o_yh', BALL), pic)
                prev_sp = sp
                continue
            regs = v.cmd('r')
            line = [ln for ln in regs.splitlines() if ln.strip().startswith('.;')][0]
            head = [ln for ln in regs.splitlines() if 'SP' in ln][0].split()
            vals = line.split()
            sp_reg = int(vals[head.index('SP')], 16)
            x = int(vals[head.index('X')], 16)
            st = v.mem(0x100 + sp_reg + 1, 2)
            caller = where((st[0] | st[1] << 8) - 2)
            z = m('o_zl', BALL)
            spd = w16('o_spl', 'o_sph', BALL)
            bx, by = w16('o_xl', 'o_xh', BALL), w16('o_yl', 'o_yh', BALL)
            before = m('last_pl')
            if kick and x != kick[0] and x < 22:
                team = 0 if x < 11 else 1
                keeper = x in (0, 11)
                who = 'keeper' if keeper else ('mate' if team == kick[1] else 'them')
                dist = ((bx - kick[3]) ** 2 + (by - kick[4]) ** 2) ** 0.5
                kind = 'shot' if kick[2] >= 1792 else 'pass'
                stats[(kind, who, caller)] += 1
                heights[(kind, who, caller)].append(z)
                if VERB:
                    print('%5d %-4s by %2d (speed %4d) -> %2d %-6s via %-12s z %2d speed %4d,'
                          ' %3d px on, %2d pictures' % (pic, kind, kick[0], kick[2], x, who,
                                                        caller, z, spd, dist, pic - kick[5]),
                          flush=True)
                kick = None
            elif VERB and x != before:
                print('%5d touch %2d via %-12s z %2d speed %4d (before %d)'
                      % (pic, x, caller, z, spd, before), flush=True)
    finally:
        v.stop()
    print('after a kick, the next touch by another:')
    for k in sorted(stats, key=lambda k: -stats[k]):
        hs = heights[k]
        print('  %-4s %-6s via %-12s %3d   height %2d-%2d (mean %.1f)'
              % (k[0], k[1], k[2], stats[k], min(hs), max(hs), sum(hs) / len(hs)))


if __name__ == '__main__':
    main()
