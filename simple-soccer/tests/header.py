#!/usr/bin/env python3
"""Headers (play.s head): a ball coming at a player's head, in a match in
VICE - the cyan joystick on 9 at (304, 500) facing up, the ball flying
down at him; the others off but the keepers and one yellow far away.

    tests/header.py [case ...]

up        the stick up: he jumps and heads it up the pitch
right     the stick right: headed right (the ball near: he runs off its
          way)
none      the stick let go: headed the way he faces (up)
high      the ball over his head (40 high): it goes over, no header
runner    7 the runner to a pass to him (recv, helper), the joystick on 9
          far off: 7 heads it on towards the goal his team attacks (up)

A line each: who touched it, where it went, how fast, his jump; OK or
WRONG; a screenshot as he heads it (header-<case>.png). The exit code counts the wrong ones.
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
HEAD_SPEED = 1536

# name: (player heading, the stick, z, (x, y) of the player, want: way
#        'up'/'right'/None (no header), speed)
CASES = {
    'up': (9, 'up', 18, 'up', HEAD_SPEED),
    'right': (9, 'right', 18, 'right', HEAD_SPEED),
    'none': (9, '', 18, 'up', HEAD_SPEED),
    'high': (9, 'up', 40, None, 0),
    'runner': (7, '', 18, 'up', HEAD_SPEED),
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
    who, stick, z, way, speed = CASES[name]
    v.poke(lab['dbg_joy'], [bits(stick)])   # (read once a picture: its
    for _ in range(6):                       # stick first, then the scene)
        v.cmd('x')
    s = moves.Setup()
    moves.open_play(s, 9)
    for i in range(1, 22):              # (the keepers, 7, 9 and one yellow)
        s.put('o_off', 0 if i in (7, 9, 11, 21) else 1, i)
    s.obj(0, 304, 676, d=0)
    s.obj(11, 304, 62, d=4)
    s.obj(21, 150, 150, d=4)
    s.obj(who, 304, 500, d=0)
    if who != 9:                        # (the joystick's far off)
        s.obj(9, 520, 650, d=0)
        s.obj(7, 304, 500, d=0)
        s.put('recv', who)
        s.put('helper', who)
        s.put('recv_t', 100)
        s.put('last_pl', 8)             # (a team-mate's pass)
    else:
        s.obj(7, 100, 650, d=0)
    y0 = 482 if 'right' in stick else 440   # (running across: it comes
    moves.flight(s, 304, y0, 304, y0 + 32 * 60, 1536, z, 0)  # soon)
    for a, vals in s.pokes:
        v.poke(a, vals)
    v.poke(OFF_PL, [0xFF])
    jump = 0
    for f in range(40):
        v.cmd('x')
        jump = max(jump, v.mem(lab['o_zl'] + who, 1)[0])
        if v.mem(lab['last_pl'], 1)[0] == who and jump:
            v.cmd('x')
            raw = [v.mem(lab[n] + BALL, 1)[0] for n in ('o_xl', 'o_xh', 'o_yl', 'o_yh',
                                                          'o_txl', 'o_txh', 'o_tyl', 'o_tyh',
                                                          'o_spl', 'o_sph')]
            for _ in range(6):          # (a picture or two on: drawn)
                v.cmd('x')
            v.screenshot(os.path.join(WORK, 'header-%s.png' % name))
            w = lambda k: (raw[k] + 256 * raw[k + 1]) - (65536 if raw[k + 1] > 127 else 0)
            bx, by, tx, ty, sp = w(0), w(2), w(4), w(6), w(8)
            went = 'up' if ty < by - 500 and abs(tx - bx) < 100 else \
                'right' if tx > bx + 500 and abs(ty - by) < 100 else '(%d,%d)' % (tx - bx, ty - by)
            ok = way == went and abs(sp - speed) <= 40
            return ok, '%d headed it %s at %d, his jump %d' % (who, went, sp, jump)
    zb = v.mem(lab['o_zl'] + BALL, 1)[0]
    return way is None, 'no header (the ball %d high, last %d)' % (zb, v.mem(lab['last_pl'], 1)[0])


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
            print('%-7s %-50s %s' % (name, got, 'OK' if ok else 'WRONG'), flush=True)
            for _ in range(100):        # (whatever follows, over)
                v.cmd('x')
    finally:
        v.stop()
    return wrong


if __name__ == '__main__':
    sys.exit(main())
