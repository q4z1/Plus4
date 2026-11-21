#!/usr/bin/env python3
"""Luca's "damn header" (snapshot that_damn_header, 21.11.): the cyan
joystick's goal kick, the keeper looking up - a team-mate offered comes
some 60 pixels ahead of the ball - then fire held with the stick back:
the kick lofted, charged, over the team-mate's head. The joystick goes to
him (switch) with fire still held from the kick: that is no fire for a
header (play.s head) - before, he headed it back the stick's way, at his
own goal.

    tests/gkhead.py [-v]

held      fire held on with the stick back from the kick: no cyan header
again     the same, but fire and the stick let go and fire pressed anew
          as the ball comes down to the next one: he heads it (asked for;
          up to three goes - whether one stands under it is chance)

A line each: the touches after the kick (who, the ball's height, its way
after), OK or WRONG. The exit code counts the wrong ones.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, BITS  # noqa: E402
from pace import game_rnd  # noqa: E402
import moves  # noqa: E402
from offer import lab, m, w, pos, R_GOALKICK, BALL  # noqa: E402

VERB = '-v' in sys.argv
UP, DOWN, FIRE = BITS['up'], BITS['down'], BITS['fire']


def case(v, again):
    s = moves.Setup()
    moves.restart(s, R_GOALKICK, 0, 364, 664)
    for i in moves.EXTRA:
        s.put('o_off', 0, i)
    for a, vals in s.pokes:
        v.poke(a, vals)
    v.poke(0xED, [0xFF])                # (play.s off_pl)
    for f in range(400):
        v.cmd('x')
        if m(v, 'kickoff') and not m(v, 'dead_t') and f > 150:
            break
    v.poke(lab['dbg_joy'], [UP])        # he looks up: a team-mate comes
    for f in range(4):
        v.cmd('x')
    v.poke(lab['dbg_joy'], [0])
    for f in range(110):
        v.cmd('x')
    off = m(v, 'offer')
    if off >= 22:
        return False, 'no one offered'
    mate = pos(v, off)
    keeper = m(v, 'taker')
    v.poke(lab['dbg_joy'], [DOWN | FIRE])
    touches = []
    last = (m(v, 'last_team'), m(v, 'last_pl'))
    kicked = False
    for f in range(120):
        v.cmd('x')
        if again and kicked and f == 30:
            v.poke(lab['dbg_joy'], [0])             # let go,
        if again and kicked and f == 34:
            v.poke(lab['dbg_joy'], [FIRE])          # pressed anew
        if VERB and kicked and f < 100:
            print('      f%d ball %s z %d fire_n %d ctrl %d at %s' % (f, pos(v, BALL), m(v, 'o_zl', BALL),
                  m(v, 'fire_n'), m(v, 'ctrl'), pos(v, m(v, 'ctrl'))))
        if not kicked:
            kicked = m(v, 'kickoff') == 0
            if kicked and VERB:
                print('   kicked at %d, the ball %s z %d, %d at %s'
                      % (f, pos(v, BALL), m(v, 'o_zl', BALL), off, mate))
            continue
        now = (m(v, 'last_team'), m(v, 'last_pl'))
        if now != last:
            vy = w(v, 'o_vyf', 'o_vyl', BALL)
            touches.append((now[1], m(v, 'o_zl', BALL), m(v, 'o_zl', now[1]), vy,
                            m(v, 'ctrl')))
            if VERB:
                print('   frame %d: %d touched it, ball %s z %d, his z %d, vy %d, ctrl %d'
                      % (f, now[1], pos(v, BALL), m(v, 'o_zl', BALL),
                         m(v, 'o_zl', now[1]), vy, m(v, 'ctrl')))
            last = now
    v.poke(lab['dbg_joy'], [0])
    # a cyan field player's header: he touched it in the air, up (his z)
    heads = [t for t in touches if 0 < t[0] < 11 and t[2] > 0]
    back = [t for t in heads if t[3] > 0]               # (vy > 0: down, back)
    text = '%d offered at %s; touches %s' % (
        off, mate, ', '.join('%d (ball z %d, his z %d, vy %d)' % t[:4] for t in touches) or 'none')
    if again:
        return bool(heads), text + (' - headed' if heads else ' - not headed')
    return not heads, text + (' - headed%s' % (' back' if back else '') if heads else ' - no header')


def main():
    v = Vice(PRG, WORK)
    wrong = 0
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
        names = [a for a in sys.argv[1:] if not a.startswith('-')] or ['held', 'again']
        for name in names:
            for go in range(3 if name == 'again' else 1):
                ok, text = case(v, name == 'again')
                if ok:
                    break
            if name == 'again':
                text += ' (go %d)' % (go + 1)
            wrong += not ok
            print('%-6s %s %s' % (name, text, 'OK' if ok else 'WRONG'), flush=True)
    finally:
        v.stop()
    return wrong


if __name__ == '__main__':
    sys.exit(main())
