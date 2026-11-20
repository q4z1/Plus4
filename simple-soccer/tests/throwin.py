#!/usr/bin/env python3
"""The computer's throw-ins (play.s brain_set), in a match in VICE: one
throw-in after another for yellow, the computer's team, on either touch
line - thrown to a team-mate, or long (a set piece's shot, from the
taker's head) 1 in 16 a frame when he faces one of the two ways its
place throws long, as Sensible Soccer's (its table: the zones by the
touch line and y 262, 476, the ways for a team attacking up, upside down
for one attacking down). The match's dice made the same each run
(play.s rnd as pace.py has it), the teams too.

    tests/throwin.py [throw-ins] [--beam]

(--beam: the dice as the match has them, by the beam - not the same
from one run to the next)

A line for each long one (where from, the way, how high and how far it
flew), then the count of each kind; the exit code 1 if a long one went
another way, or there is none.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, labels  # noqa: E402
from pace import game_rnd  # noqa: E402
import moves  # noqa: E402

lab = labels()
OFF_PL = 0xED                   # (play.s)
BALL = 22
R_THROW = 1
# A long one is a set piece's shot (bs_shot): it rises (o_dzl 1 on), a
# pass (kick_to) is flat. Not by its speed: since the throw-in went 512
# slower (c562e70, 3c83a4b: Luca found them super powerful) a long one
# is some 1690, a pass 1810 - 2066; at 2100 this test found none since.
FLIGHT = 40                     # frames the long ones are followed


# Sensible Soccer's ways (0 up, 2 right) a throw-in goes long from, a
# bit each: by its zone 0-5 (c154a2), for the team attacking up
ZONE_WAYS = [0x03, 0x06, 0x0C, 0x81, 0xC0, 0x60]


def long_ways(x, y, up):
    """the ways a throw-in at x, y goes long (c128d2: the zone)"""
    band = 0 if y < 262 else 1 if y < 476 else 2
    if up:
        zone = (5 - band) if x >= 304 else (2 - band)
        return ZONE_WAYS[zone]
    zone = band if x >= 304 else 3 + band
    w = ZONE_WAYS[zone]
    return (w >> 4 | w << 4) & 255


def mem1(v, name, i=0):
    return v.mem(lab[name] + i, 1)[0]


def ball(v):
    """the ball's x, y, z"""
    return (mem1(v, 'o_xl', BALL) + 256 * mem1(v, 'o_xh', BALL),
            mem1(v, 'o_yl', BALL) + 256 * mem1(v, 'o_yh', BALL),
            mem1(v, 'o_zl', BALL))


def throw_in(v, at):
    """one for yellow at 'at': (what it was, its line)"""
    s = moves.Setup()
    moves.restart(s, R_THROW, 1, *at)
    for i in moves.EXTRA:               # (restart is training's: all on)
        s.put('o_off', 0, i)
    for a, vals in s.pokes:
        v.poke(a, vals)
    v.poke(OFF_PL, [0xFF])
    bs_t, way, rk = 0, None, R_THROW
    for f in range(400):
        v.cmd('x')
        if f > 2 and not mem1(v, 'kickoff') and not mem1(v, 'dead_t'):
            break
        bs_t = mem1(v, 'bs_t')
        rk = mem1(v, 'rs_kind')
        taker = mem1(v, 'taker')
        if taker < 22:                  # (the last frame he was the taker)
            way = mem1(v, 'o_dir', taker)
    else:
        return 'none', 'not taken within 400 frames'
    speed = mem1(v, 'o_spl', BALL) + 256 * mem1(v, 'o_sph', BALL)
    if '-v' in sys.argv:
        print('  at %s: speed %d, z %d, dz %d, after %d frames' % (
            at, speed, mem1(v, 'o_zl', BALL), mem1(v, 'o_dzl', BALL), bs_t))
    if mem1(v, 'o_dzl', BALL) == 0:
        return 'pass', ''
    if bs_t >= 150:
        return 'late', 'kicked after %d frames waiting' % bs_t
    up = (1 ^ mem1(v, 'flip')) == 0         # (yellow: me 1)
    ways = long_ways(at[0], at[1], up)
    if way is None or rk != R_THROW:
        return 'other', 'not a throw-in kicked (another set piece first)'
    if not ways >> way & 1:
        return 'wrong', 'from %d,%d the way %s, not one of %02x' % (at[0], at[1], way, ways)
    x0, y0, z = ball(v)
    top = z
    for _ in range(FLIGHT):
        v.cmd('x')
        x, y, z = ball(v)
        top = max(top, z)
    return 'long', 'from %d,%d the way %d after %d frames: up to %d high, %d px on in %d frames' % (
        at[0], at[1], way, bs_t, top, round(((x - x0) ** 2 + (y - y0) ** 2) ** 0.5), FLIGHT)


def main():
    args = [a for a in sys.argv[1:] if a[0] != '-']
    n = int(args[0]) if args else 48
    v = Vice(PRG, WORK)
    count = {}
    try:
        v.cmd('break %04x' % lab['main'])
        v.cmd('x')
        v.cmd('del')
        v.cmd('break %04x' % lab['chosen'])     # the same teams each time
        v.cmd('x')
        v.cmd('del')
        v.poke(0xFCE0 + 7 + 3, [0, 1])          # (game.inc K_CH's t_team)
        if '--beam' not in sys.argv:
            rnd = game_rnd()
            v.poke(rnd + 7, [0x49, 0x00, 0xEA])     # (eor $FF1E -> eor #0)
            v.poke(lab['z_rnd'], [1])
        v.cmd('break %04x' % lab['play_frame'])
        for _ in range(120):
            v.cmd('x')
        for k in range(n):
            at = (49 if k & 1 else 559, 150 + 37 * k % 450)
            kind, line = throw_in(v, at)
            count[kind] = count.get(kind, 0) + 1
            if line:
                print('%-5s %s' % (kind, line))
            for _ in range(60):         # (whatever follows, over)
                v.cmd('x')
    finally:
        v.stop()
    print(', '.join('%s %d' % kv for kv in sorted(count.items())))
    return 0 if count.get('long') and not count.get('wrong') else 1


if __name__ == '__main__':
    sys.exit(main())
