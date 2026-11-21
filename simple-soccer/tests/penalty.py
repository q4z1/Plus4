#!/usr/bin/env python3
"""A cyan penalty (play.s ball_ahead, may_face), in a match in VICE: the
stick pushed (the taker turns), fire tapped or held with it, the stick
held on after (no aftertouch's bend) - where the ball crosses the top goal
line (y 49), the posts at 269 and 339.

    tests/penalty.py [case ...]

straight  the stick up, fire tapped: at the middle (straight on)
right     up and right, fire tapped: at the right corner, inside the
          post - PEN_DX (520) across on 1000, as the computer's (cpu_pen);
          45 degrees it went wide of the post every time (Luca: the
          slightest tap with a way pushed sends it outside the goal)
left      up and left, tapped: at the left corner
rshot     up and right, fire held 20 frames: a shot at the right corner
lshot     up and left, held: at the left corner

A line each: where it was aimed, where it crossed the line or who got it;
OK if it was aimed as it should be and did not go wide. The exit code
counts the wrong ones.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, BITS, labels  # noqa: E402
import moves  # noqa: E402

lab = labels()
OFF_PL = 0xED                   # (play.s)
BALL = 22
R_PENALTY = 6
POST_L, POST_R, LINE = 269, 339, 49

# name: (the stick, frames fire is held, aimed: dx on 1000 up)
CASES = {
    'straight': ('up', 4, 0),
    'right': ('up+right', 4, 520),
    'left': ('up+left', 4, -520),
    'rshot': ('up+right', 20, 520),
    'lshot': ('up+left', 20, -520),
}


def bits(s):
    b = 0
    for p in s.split('+'):
        b |= BITS.get(p, 0)
    return b


def word(v, lo, hi, i):
    w = v.mem(lab[lo] + i, 1)[0] + 256 * v.mem(lab[hi] + i, 1)[0]
    return w - 65536 if w > 32767 else w


def run(v, name):
    stick, hold, want = CASES[name]
    s = moves.Setup()
    moves.restart(s, R_PENALTY, 0, 304, 107)
    for i in moves.EXTRA:               # (restart is training's: all on)
        s.put('o_off', 0, i)
    for a, vals in s.pokes:
        v.poke(a, vals)
    v.poke(OFF_PL, [0xFF])
    v.poke(lab['dbg_joy'], [0])
    for _ in range(120):                # (all in their places, the keeper
        v.cmd('x')                      # on his line)
        if v.mem(lab['kickoff'], 1)[0]:
            break
    for _ in range(30):
        v.cmd('x')
    v.poke(lab['dbg_joy'], [bits(stick)])   # (he turns)
    for _ in range(8):
        v.cmd('x')
    v.poke(lab['dbg_joy'], [bits(stick) | BITS['fire']])
    aim, prev = None, None
    for f in range(hold + 80):
        if f == hold:
            v.poke(lab['dbg_joy'], [bits(stick)])
        v.cmd('x')
        bx, by = word(v, 'o_xl', 'o_xh', BALL), word(v, 'o_yl', 'o_yh', BALL)
        sp = word(v, 'o_spl', 'o_sph', BALL)
        if aim is None:
            if sp > 0 and not v.mem(lab['kickoff'], 1)[0]:
                tx, ty = word(v, 'o_txl', 'o_txh', BALL), word(v, 'o_tyl', 'o_tyh', BALL)
                aim = (tx - bx, ty - by)
            prev = (bx, by)
            continue
        lt, lp = v.mem(lab['last_team'], 1)[0], v.mem(lab['last_pl'], 1)[0]
        if lt == 1:
            got = 'saved by %d at %d,%d' % (lp, bx, by)
            break
        if by <= LINE:
            x = prev[0] + (bx - prev[0]) * (prev[1] - LINE) / max(1, prev[1] - by)
            inside = POST_L < x < POST_R
            got = 'crossed the line at x %d - %s' % (x, 'in' if inside else 'WIDE')
            break
        prev = (bx, by)
    else:
        return False, 'aimed %s, never at the line' % (aim,)
    if aim is None:
        return False, 'not kicked'
    ok = abs(aim[0] - want) <= 30 and 'WIDE' not in got
    return ok, 'aimed %+d on %+d, %s' % (aim[0], aim[1], got)


def main():
    names = [a for a in sys.argv[1:] if a[0] != '-'] or list(CASES)
    v = Vice(PRG, WORK)
    wrong = 0
    try:
        v.cmd('break %04x' % lab['main'])
        v.cmd('x')
        v.cmd('del')
        v.cmd('break %04x' % lab['play_frame'])
        for _ in range(120):
            v.cmd('x')
        for name in names:
            ok, got = run(v, name)
            wrong += not ok
            print('%-8s %-58s %s' % (name, got, 'OK' if ok else 'WRONG'), flush=True)
            for _ in range(200):        # (whatever follows, over)
                v.cmd('x')
    finally:
        v.stop()
    return wrong


if __name__ == '__main__':
    sys.exit(main())
