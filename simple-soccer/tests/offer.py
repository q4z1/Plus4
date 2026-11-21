#!/usr/bin/env python3
"""A team-mate offering himself at the cyan joystick's goal kick or
throw-in (Luca's wish; play.s offering): the taker looks one way (the
stick pushed a moment, then let go) and waits - after OFFER_T frames the
team-mate that way comes towards him; fire tapped passes to him. And a
goal kick tapped at once goes the way the keeper faces (pass: its cone
half as wide first) - Luca: the keeper turned, the pass went to the same
man ahead each time.

    tests/offer.py [case ...]

gk-left, gk-up, gk-right   the keeper faces so, fire tapped at once: to
                           whom (the three not all the same)
offer-gk-*                 the same, waited 110 frames: someone offering,
                           come within 90 pixels, the pass to him, his
offer-throw-*              a throw-in, its aim turned up / down a step
none-gk, none-throw        someone offering; then the stick back - at his
                           goal (the keeper), out of the pitch (left on the
                           left line): he goes back, no one offers 60
                           frames on, the throw-in's aim as it was (Luca:
                           a way to have no one offered); then the first
                           way again: someone offering (Luca: the way the
                           keeper still looked offered no one)

A line each; the exit code counts the wrong ones.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, labels, BITS  # noqa: E402
from pace import game_rnd  # noqa: E402
import moves  # noqa: E402

lab = labels()
VERB = '-v' in sys.argv
BALL = 22
R_THROW, R_GOALKICK = 1, 2
UP, DOWN, LEFT, RIGHT = BITS['up'], BITS['down'], BITS['left'], BITS['right']
CASES = {'gk-left': (R_GOALKICK, 244, 664, UP | LEFT, 0),
         'gk-up': (R_GOALKICK, 244, 664, UP, 0),
         'gk-right': (R_GOALKICK, 244, 664, UP | RIGHT, 0),
         'offer-gk-left': (R_GOALKICK, 244, 664, UP | LEFT, 110),
         'offer-gk-up': (R_GOALKICK, 244, 664, UP, 110),
         'offer-gk-right': (R_GOALKICK, 244, 664, UP | RIGHT, 110),
         'offer-throw-up': (R_THROW, 49, 300, UP, 110),
         'offer-throw-down': (R_THROW, 49, 300, DOWN, 110)}


def m(v, n, i=0):
    return v.mem(lab[n] + i, 1)[0]


def w(v, lo, hi, i):
    x = m(v, lo, i) + 256 * m(v, hi, i)
    return x - 65536 if x > 32767 else x


def pos(v, i):
    return w(v, 'o_xl', 'o_xh', i), w(v, 'o_yl', 'o_yh', i)


def case(v, kind, x, y, stick, wait):
    s = moves.Setup()
    moves.restart(s, kind, 0, x, y)
    for i in moves.EXTRA:
        s.put('o_off', 0, i)
    for a, vals in s.pokes:
        v.poke(a, vals)
    v.poke(0xED, [0xFF])                # (play.s off_pl)
    for f in range(400):
        v.cmd('x')
        if m(v, 'kickoff') and not m(v, 'dead_t') and f > 150:
            break
    v.poke(lab['dbg_joy'], [stick])     # (a moment: he looks that way)
    for f in range(4):
        v.cmd('x')
    v.poke(lab['dbg_joy'], [0])
    for f in range(wait):
        v.cmd('x')
    off = m(v, 'offer')
    ball = pos(v, BALL)
    dist = math.dist(pos(v, off), ball) if off < 22 else None
    if VERB and off < 22:
        near = sorted((math.dist(pos(v, i), pos(v, off)), i) for i in range(11, 22))[:2]
        print('   ball %s, %d at %s, nearest of theirs %s'
              % (ball, off, pos(v, off), [(i, pos(v, i)) for _, i in near]))
    taker = m(v, 'taker')
    v.poke(lab['dbg_joy'], [BITS['fire']])
    for f in range(3):
        v.cmd('x')
    v.poke(lab['dbg_joy'], [0])
    recv = None
    for f in range(150):
        v.cmd('x')
        if recv is None:
            if m(v, 'kickoff'):
                continue
            recv = m(v, 'recv')
            v.poke(lab['last_pl'], [taker])
            continue
        pl = m(v, 'last_pl')
        if pl != taker and pl < 22:
            return off, dist, recv, pl
    return off, dist, recv, None


NONE = {'none-gk': (R_GOALKICK, 244, 664, DOWN),
        'none-throw': (R_THROW, 49, 300, LEFT)}


def none_case(v, kind, x, y, back):
    s = moves.Setup()
    moves.restart(s, kind, 0, x, y)
    for i in moves.EXTRA:
        s.put('o_off', 0, i)
    for a, vals in s.pokes:
        v.poke(a, vals)
    v.poke(0xED, [0xFF])
    for f in range(400):
        v.cmd('x')
        if m(v, 'kickoff') and not m(v, 'dead_t') and f > 150:
            break
    v.poke(lab['dbg_joy'], [UP])
    for f in range(4):
        v.cmd('x')
    v.poke(lab['dbg_joy'], [0])
    for f in range(110):
        v.cmd('x')
    off = m(v, 'offer')
    if off >= 22:
        return False, 'no one offered at first'
    aim = m(v, 'sp_aim')
    v.poke(lab['dbg_joy'], [back])
    for f in range(4):
        v.cmd('x')
    v.poke(lab['dbg_joy'], [0])
    d0 = math.dist(pos(v, off), pos(v, BALL))
    for f in range(60):
        v.cmd('x')
        if m(v, 'offer') < 22:
            return False, '%d offered again after %d frames' % (m(v, 'offer'), f)
    d1 = math.dist(pos(v, off), pos(v, BALL))
    same = kind != R_THROW or m(v, 'sp_aim') == aim
    still = m(v, 'kickoff') == 1
    v.poke(lab['dbg_joy'], [UP])        # the first way again - the way the
    for f in range(4):                  # keeper still looks (Luca: it came
        v.cmd('x')                      # only for the other two)
    v.poke(lab['dbg_joy'], [0])
    again = None
    for f in range(110):
        v.cmd('x')
        if m(v, 'offer') < 22:
            again = f
            break
    return d1 > d0 + 20 and same and still and again is not None, \
        '%d offered, then back: %d -> %d away, the aim %s, the set piece %s; ' \
        'the stick the first way again: %s' % (
            off, d0, d1, 'kept' if same else 'moved', 'waiting' if still else 'taken',
            'offered after %d frames' % again if again is not None else 'no one')


def main():
    v = Vice(PRG, WORK)
    wrong = 0
    got = {}
    try:
        v.cmd('break %04x' % lab['main'])
        v.cmd('x')
        v.cmd('del')
        v.cmd('break %04x' % lab['chosen'])
        v.cmd('x')
        v.cmd('del')
        v.poke(0xFCE0 + 7 + 3, [0, 1])          # (game.inc K_CH's t_team)
        rnd = game_rnd()
        v.poke(rnd + 7, [0x49, 0x00, 0xEA])     # (eor $FF1E -> eor #0)
        v.poke(lab['z_rnd'], [1])
        v.cmd('break %04x' % lab['play_frame'])
        for _ in range(120):
            v.cmd('x')
        names = [a for a in sys.argv[1:] if not a.startswith('-')] or list(CASES) + list(NONE)
        for name in names:
            if name in NONE:
                ok, text = none_case(v, *NONE[name])
                wrong += not ok
                print('%-17s %s %s' % (name, text, 'OK' if ok else 'WRONG'), flush=True)
                continue
            kind, x, y, stick, wait = CASES[name]
            off, dist, recv, first = case(v, kind, x, y, stick, wait)
            got[name] = recv
            if wait:
                ok = off < 11 and dist is not None and dist < 90 and recv == off \
                    and first is not None and first < 11
            else:
                ok = recv is not None and recv < 11
            wrong += not ok
            print('%-17s offer %-4s %-12s pass to %-4s first touched by %-4s %s'
                  % (name, off if off < 22 else '-',
                     '(%d away)' % dist if dist is not None else '', recv, first,
                     'OK' if ok else 'WRONG'), flush=True)
        three = [got[n] for n in ('gk-left', 'gk-up', 'gk-right') if n in got]
        if len(three) == 3:
            ok = len(set(three)) == 3
            wrong += not ok
            print('the keeper\'s three ways: %s  %s' % (three, 'OK' if ok else 'WRONG'))
    finally:
        v.stop()
    return wrong


if __name__ == '__main__':
    sys.exit(main())
