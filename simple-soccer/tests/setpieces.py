#!/usr/bin/env python3
"""The players' places at set pieces (play.s spot, sp_kind, sp_*), in a
match in VICE: goal kicks, corners, free kicks, penalties and throw-ins
for either team at a few places each - after a while waiting, each
player the formation moves and the keepers (not the joysticks' nor the
taker) is to go where the tables say: worked out here anew from play.s's
sp_* rows (the kind by the place, the team's own frame: its goal at the
top, the team at the bottom's turned about; places off the ball by its
mask), within the rows' rounding.

    tests/setpieces.py [case ...] [--flip]

(--flip: as after half time, the sides changed - flip set, the places
worked out for it; the cases' places as they are)

A line each: the case, its kind, how many places checked, OK or WRONG
(and the first wrong one); the exit code counts the wrong cases.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, HERE, labels  # noqa: E402
import moves  # noqa: E402

lab = labels()
OFF_PL = 0xED                   # (play.s)
R_THROW, R_GOALKICK, R_CORNER, R_FREE, R_PENALTY = 1, 2, 3, 5, 6
WAIT = 34                       # frames: each player's place anew every 11
NEAR = 4                        # (x / 2, y / 3 rounded; SLACK 2)


def tables():
    """play.s's sp_* rows: {(role, kind): (mask, [(a, b) * 11])}"""
    src = open(os.path.join(HERE, 'play.s')).read()
    out = {}
    for m in re.finditer(r'^sp_([td])([0-9a-f]+):.*\n\s+\.word \$([0-9A-F]+)\n\s+\.byte ([^\n]+)',
                         src, re.M):
        vals = [int(v) for v in m.group(4).split(',')]
        out[(m.group(1) == 'd', int(m.group(2), 16))] = (
            int(m.group(3), 16), list(zip(vals[0::2], vals[1::2])))
    return out


def kind(rk, top, x, y):
    """the set piece's kind (its taker's goal at the top or not), None if
    it has none"""
    right = (x >= 304) == top            # (its right, as it looks down)
    if rk == R_GOALKICK:
        return 1 if right else 2
    if rk == R_CORNER:
        return 4 if right else 5
    if rk == R_PENALTY:
        return 14
    if rk == R_THROW:
        band = (y >= 262) + (y >= 476)
        if not top:
            band = 2 - band
        return (15 if right else 18) + band
    if rk == R_FREE:
        if not (487 <= y <= 602 if top else 136 <= y < 251):
            return None
        col = sum(x >= t for t in (121, 229, 277, 330, 378, 486))
        return 12 - col if top else 6 + col


def place(entry, rel, top, bx, by):
    a, b = entry
    if rel:
        dx, dy = (a - 256 if a > 127 else a), (b - 256 if b > 127 else b)
        return (bx + dx, by + dy) if top else (bx - dx, by - dy)
    return (2 * a + 54, 3 * b + 49) if top else (553 - 2 * a, 689 - 3 * b)


CASES = {
    'goalkick-cyan-l': (R_GOALKICK, 0, 244, 664), 'goalkick-cyan-r': (R_GOALKICK, 0, 364, 664),
    'goalkick-yel-l': (R_GOALKICK, 1, 244, 74), 'goalkick-yel-r': (R_GOALKICK, 1, 364, 74),
    'corner-cyan-l': (R_CORNER, 0, 54, 54), 'corner-cyan-r': (R_CORNER, 0, 553, 54),
    'corner-yel-l': (R_CORNER, 1, 54, 684), 'corner-yel-r': (R_CORNER, 1, 553, 684),
    'free-cyan-0': (R_FREE, 0, 90, 200), 'free-cyan-3': (R_FREE, 0, 304, 230),
    'free-cyan-5': (R_FREE, 0, 420, 160), 'free-cyan-6': (R_FREE, 0, 520, 200),
    'free-yel-1': (R_FREE, 1, 200, 540), 'free-yel-4': (R_FREE, 1, 350, 500),
    'free-cyan-far': (R_FREE, 0, 304, 400),
    'penalty-cyan': (R_PENALTY, 0, 304, 107), 'penalty-yel': (R_PENALTY, 1, 304, 631),
    'throw-cyan-l0': (R_THROW, 0, 49, 150), 'throw-cyan-l2': (R_THROW, 0, 49, 600),
    'throw-cyan-r1': (R_THROW, 0, 559, 350), 'throw-yel-l1': (R_THROW, 1, 49, 400),
    'throw-yel-r0': (R_THROW, 1, 559, 150), 'throw-yel-r2': (R_THROW, 1, 559, 620),
}


def mem1(v, name, i=0):
    return v.mem(lab[name] + i, 1)[0]


def run(v, tab, name):
    rk, team, x, y = CASES[name]
    s = moves.Setup()
    moves.restart(s, rk, team, x, y)
    for i in moves.EXTRA:               # (restart is training's: all on)
        s.put('o_off', 0, i)
    for a, vals in s.pokes:
        v.poke(a, vals)
    v.poke(OFF_PL, [0xFF])
    v.poke(lab['dbg_joy'], [0])
    skip = set()                        # (who the sticks or the computer
    for f in range(WAIT):               # had, its last 22 frames)
        v.cmd('x')
        if f >= WAIT - 22:
            skip |= {mem1(v, n) for n in ('ctrl', 'ctrl_b', 'helper', 'taker')}
            skip.add(v.mem(lab['ctx_b'] + lab['helper'] - lab['ctx'], 1)[0])
    if not mem1(v, 'kickoff') and not mem1(v, 'dead_t'):
        return False, 'taken already'
    flip = mem1(v, 'flip')
    rx = mem1(v, 'rs_x') + 256 * mem1(v, 'rs_x', 1)
    ry = mem1(v, 'rs_y') + 256 * mem1(v, 'rs_y', 1)
    k = kind(rk, (team ^ flip) == 1, rx, ry)
    checked = 0
    for i in range(22):
        if i in skip:
            continue
        t, n = i // 11, i % 11
        row = tab.get((t != team, k)) if k is not None else None
        if row is None or row[1][n] == (255, 255):
            continue
        want = place(row[1][n], row[0] >> n & 1, (t ^ flip) == 1, rx, ry)
        got = (mem1(v, 'o_txl', i) + 256 * mem1(v, 'o_txh', i),
               mem1(v, 'o_tyl', i) + 256 * mem1(v, 'o_tyh', i))
        got = tuple(g - 65536 if g > 32767 else g for g in got)
        checked += 1
        if abs(got[0] - want[0]) > NEAR or abs(got[1] - want[1]) > NEAR:
            return False, 'kind %s, player %d to %s, not %s' % (k, i, got, want)
    return True, 'kind %s, %d places' % (k, checked)


def main():
    names = [a for a in sys.argv[1:] if a[0] != '-'] or list(CASES)
    tab = tables()
    v = Vice(PRG, WORK)
    wrong = 0
    try:
        v.cmd('break %04x' % lab['main'])
        v.cmd('x')
        v.cmd('del')
        v.cmd('break %04x' % lab['play_frame'])
        for _ in range(120):
            v.cmd('x')
        if '--flip' in sys.argv:
            v.poke(lab['flip'], [1])
        for name in names:
            ok, got = run(v, tab, name)
            wrong += not ok
            print('%-16s %-50s %s' % (name, got, 'OK' if ok else 'WRONG'))
    finally:
        v.stop()
    return wrong


if __name__ == '__main__':
    sys.exit(main())
