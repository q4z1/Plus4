#!/usr/bin/env python3
"""Double touch (play.s touch, off_chk), in a match in VICE: a set piece's
taker touching the ball again before anyone else has - the whistle, a
free kick for the other team where he is. The cyan 7 takes it, the cyan
9 on the pitch or off as the case has it; the yellow 12 on the second
joystick, let alone, far off; everyone else off (the keepers too). After
the kick 7's stick points at the ball.

    tests/dbltouch.py [case ...]

throw   a throw-in tapped into the pitch, 7 running after it: the whistle
mate    a throw-in to 9 beside him: 9 has it, play goes on
free    a free kick tapped ahead, 7 running after it: the whistle
corner  a corner tapped out, 7 running after it: the whistle

A line each: the case, what happened, OK or WRONG; the exit code counts
the wrong ones.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, BITS, labels  # noqa: E402
import moves  # noqa: E402

lab = labels()
OFF_PL = 0xED                   # (play.s)
R_THROW, R_CORNER, R_FREE = 1, 3, 5


def bits(s):
    b = 0
    for p in s.split('+'):
        b |= BITS.get(p, 0) if p else 0
    return b


def scene(s, kind, at, nine=None):
    """kind's set piece for cyan at 'at', 7 by it, 9 at nine (else off)"""
    moves.restart(s, kind, 0, *at)
    s.put('two', 1)                     # (12 on the second joystick, let
    s.put('ctrl_b', 12)                 # alone: he stands where he is)
    on = (7, 12) + ((9,) if nine else ())   # (the keepers off: no pass to
                                            # one, no catch)
    for i in range(22):
        s.put('o_off', 0 if i in on else 1, i)
    s.obj(0, 304, 676, d=0)
    s.obj(11, 304, 62, d=4)
    s.obj(12, 560, 100, d=4)
    s.obj(7, at[0] + 10, at[1] + 10, d=0)
    s.obj(9, *(nine or (60, 700)), d=0)


# name: (setup, the stick for the kick, 7 after the ball, the whistle wanted)
CASES = {
    'throw': (lambda s: scene(s, R_THROW, (49, 300)), 'down+right+fire', True, True),
    'mate': (lambda s: scene(s, R_THROW, (49, 300), nine=(110, 300)), 'right+fire', False, False),
    'free': (lambda s: scene(s, R_FREE, (304, 420)), 'up+fire', True, True),
    'corner': (lambda s: scene(s, R_CORNER, (54, 54)), 'down+right+fire', True, True),
}


def chase(v):
    """the stick from 7 to the ball"""
    m = {n: v.mem(lab[n], 23) for n in ('o_xl', 'o_xh', 'o_yl', 'o_yh')}
    dx, dy = ((m[a][22] + 256 * m[b][22]) - (m[a][7] + 256 * m[b][7])
              for a, b in (('o_xl', 'o_xh'), ('o_yl', 'o_yh')))
    stick = []
    if abs(dy) > abs(dx) / 2:
        stick.append('down' if dy > 0 else 'up')
    if abs(dx) > abs(dy) / 2:
        stick.append('right' if dx > 0 else 'left')
    return '+'.join(stick)


WHY_OFF, WHY_TWICE = 2, 3               # (play.s why: the reason shown)


def shown(v, name):
    """the reason shown: a screenshot 30 frames after the whistle"""
    for _ in range(30):
        v.cmd('x')
    v.screenshot(os.path.join(WORK, 'why-%s.png' % name))


def run(v, name):
    setup, kick, after, want = CASES[name]
    s = moves.Setup()
    setup(s)
    for a, vals in s.pokes:
        v.poke(a, vals)
    v.poke(OFF_PL, [0xFF])
    start = 60                          # (the taker set first, at the ball)
    seen = set()
    taker = None
    for f in range(start + 200):
        stick = kick if start <= f < start + 3 else chase(v) if after and f >= start + 3 else ''
        v.poke(lab['dbg_joy'], [bits(stick)])
        v.cmd('x')
        off, = v.mem(OFF_PL, 1)
        if off != 0xFF and off not in seen:
            seen.add(off)
        if f == start - 1:
            taker, = v.mem(lab['taker'], 1)
        rs, = v.mem(lab['rs_kind'], 1)
        dead, = v.mem(lab['dead_t'], 1)
        lp, = v.mem(lab['last_pl'], 1)
        if f > start and dead and rs == R_FREE:
            team, = v.mem(lab['rs_team'], 1)
            x = v.mem(lab['rs_x'], 2)
            y = v.mem(lab['rs_y'], 2)
            why, = v.mem(lab['why'], 1)
            got = 'whistle: free kick for team %d at %d,%d (taker %s, shown %d)' % (
                team, x[0] + 256 * x[1], y[0] + 256 * y[1], taker, why)
            shown(v, name)
            return want and team == 1 and taker == 7 and why == WHY_TWICE, got
        if not want and f > start + 3 and lp == 9:
            for _ in range(30):         # (the check is the next frame's)
                v.cmd('x')
            dead, = v.mem(lab['dead_t'], 1)
            rs, = v.mem(lab['rs_kind'], 1)
            if dead and rs == R_FREE:
                return False, 'whistle after 9 had it'
            return True, '9 has the ball, play on (taker %s)' % taker
    return not want, 'no whistle within 200 frames (last_pl %d, taker %s, marks %s)' % (
        lp, taker, sorted(seen))


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
            print('%-6s %-62s %s' % (name, got, 'OK' if ok else 'WRONG'))
            for _ in range(200):        # (whatever follows, over)
                v.cmd('x')
    finally:
        v.stop()
    return wrong


if __name__ == '__main__':
    sys.exit(main())
