#!/usr/bin/env python3
"""How hard a kick goes by how long fire is held (play.s control, charge,
shot_power): a player with the ball at his feet, facing up, no team-mate
ahead (all behind him), fire held so many frames, then let go. Held
SHOT_HOLD the ball goes at once (Luca: as the game knows it is a shot,
not as fire is let go), at 1792; held on, CHARGE_D more each two frames,
for CHARGE_N steps at most (2560) - and the stick pulled back meanwhile,
higher. Its speed counted as if the air (10 a frame) and the ground (16)
had not slowed it. His skill set to the weakest (sk_duel 7: no bonus) or
the best (15).

    tests/power.py [case ...]

tap      fire 2 frames: no one to pass to - straight on at 2048
hold N   fire N frames: gone within 12 frames of the press, 1792 + 32 for
         each frame held past it, 24 at most (2560)
best     held long, the best player: 192 more
back     held 30 frames, the stick pulled back once it went: higher
         than without (hold 30)
again    a shot let go of, then fire tapped at once: that tap a pass
         (it was swallowed: the ball kept glued, said Luca)
caught   a throw-in passed (fire tapped), caught-long held 30: its
         receiver neither heads it nor kicks it on of himself (Luca: a
         double shot)
throw    a throw-in held 30 frames: 512 less, half the charge - and no
         aftertouch making it a shot's 2560 (super powerful, said Luca)

A line each, OK or WRONG; the exit code counts the wrong ones.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from keep import Scene, BALL  # noqa: E402
from shot import BITS, labels  # noqa: E402
import moves  # noqa: E402

TOL = 72                        # (two steps either way, and the first frame)
R_THROW = 1


def follow(s, p, frames, joy, back=0):
    """fire (and joy) held frames, then let go; the frame the ball left
    p, its speed with the slowing added back, how high it got"""
    v = s.v
    v.cmd('del')
    v.cmd('break %04x' % lab['play_frame'])
    v.poke(lab['dbg_joy'], [BITS['fire']])
    gone, top, speed, slow = None, 0, 0, 0
    for f in range(frames + 50):
        if f == frames:
            v.poke(lab['dbg_joy'], [0])
        v.cmd('x')
        sp = s.get16('o_spl', 'o_sph', BALL)
        z = s.get('o_zl', BALL)
        if gone is None:
            if sp > 0 and s.get('last_pl') == p:
                gone = f
                if back and f < frames:     # (pulled back once it went)
                    v.poke(lab['dbg_joy'], [BITS['fire'] | back])
            else:
                continue
        elif s.get('last_pl') != p:
            break
        else:
            slow += 10 if z else 16
        top = max(top, z)
        speed = max(speed, sp + slow)
    return gone, speed, top


def kick(frames, sk, back=0):
    s = Scene(lab)
    try:
        p = s.get('ctrl')
        s.obj(p, 304, 500, d=0)
        s.obj(BALL, 304, 496)
        for i in range(22):
            if i not in (p, 0, 11):
                s.obj(i, 40 + 12 * i, 700 if i < 11 else 120)
        s.put('sk_duel', p, sk)
        s.put('last_team', 0, 0)
        s.put('last_pl', 0, p)
        return follow(s, p, frames, 0, back)
    finally:
        s.stop()


def again():
    """a shot held 12 frames, let go; at once a tap with the ball back at
    his feet: a pass (the ball moving again, his kick)"""
    s = Scene(lab)
    v = s.v
    try:
        p = s.get('ctrl')
        s.obj(p, 304, 500, d=0)
        s.obj(BALL, 304, 496)
        for i in range(22):
            if i not in (p, 0, 11):
                s.obj(i, 40 + 12 * i, 700 if i < 11 else 120)
        s.put('last_team', 0, 0)
        s.put('last_pl', 0, p)
        gone, _, _ = follow(s, p, 12, 0)
        for _ in range(4):
            v.cmd('x')
        s.obj(BALL, 304, 496)           # (back at his feet, still)
        s.obj(p, 304, 500, d=0)
        s.put('last_pl', 0, p)
        v.poke(lab['dbg_joy'], [BITS['fire']])
        for _ in range(3):
            v.cmd('x')
        v.poke(lab['dbg_joy'], [0])
        for f in range(12):
            v.cmd('x')
            if s.get16('o_spl', 'o_sph', BALL) > 0:
                return True, 'the tap kicked it %d frames after' % (f + 1)
        return False, 'the tap after the shot did nothing (fire_n %02x)' % s.get('fire_n')
    finally:
        s.stop()


def throw(frames):
    s = Scene(lab)
    v = s.v
    try:
        v.cmd('del')
        v.cmd('break %04x' % lab['play_frame'])
        st = moves.Setup()
        moves.restart(st, R_THROW, 0, 49, 300)
        for i in moves.EXTRA:
            st.put('o_off', 0, i)
        for a, vals in st.pokes:
            v.poke(a, vals)
        v.poke(0xED, [0xFF])            # (play.s off_pl)
        for f in range(300):            # till the taker is ready
            v.cmd('x')
            if s.get('kickoff') and not s.get('dead_t') and s.get('sp_aim') < 128:
                break
        else:
            return None, 0, 0
        for _ in range(4):
            v.cmd('x')
        p = s.get('taker')
        s.put('sk_duel', p, 7)          # (no bonus)
        return follow(s, p, frames, 0)
    finally:
        s.stop()


def caught(frames):
    """a throw-in, fire held frames (2: a pass), then the stick let go:
    what its receiver does with it - trapped, or headed / kicked on of
    itself (Luca: the receiver shot or headed it, a double shot)"""
    s = Scene(lab)
    v = s.v
    try:
        v.cmd('del')
        v.cmd('break %04x' % lab['play_frame'])
        st = moves.Setup()
        moves.restart(st, R_THROW, 0, 49, 300)
        for i in moves.EXTRA:
            st.put('o_off', 0, i)
        for a, vals in st.pokes:
            v.poke(a, vals)
        v.poke(0xED, [0xFF])
        for f in range(300):
            v.cmd('x')
            if s.get('kickoff') and not s.get('dead_t') and s.get('sp_aim') < 128:
                break
        for _ in range(4):
            v.cmd('x')
        p = s.get('taker')
        v.poke(lab['dbg_joy'], [BITS['fire']])
        for f in range(frames):
            v.cmd('x')
        v.poke(lab['dbg_joy'], [0])
        by = [p]
        for f in range(120):
            v.cmd('x')
            pl = s.get('last_pl')
            if pl != by[-1] and pl != p:    # (the throw itself: not)
                by.append(pl)
                z = s.get('o_zl', BALL)
                sp = s.get16('o_spl', 'o_sph', BALL)
                if pl < 11 and (s.get('o_zl', pl) or sp > 1000):
                    return False, '%d (from %d) sent it on of himself: %s high, at %d' \
                        % (pl, p, z, sp)
        return len(by) > 1, 'touched by %s, no one on of himself' % by[1:]
    finally:
        s.stop()


def main():
    global lab
    lab = labels()
    hold = lambda n: 1792 + 32 * min(24, max(0, n - 10))  # noqa: E731
    cases = {'tap': (2, 7, 0, 2048), 'hold 10': (10, 7, 0, hold(10)),
             'hold 14': (14, 7, 0, hold(14)), 'hold 22': (22, 7, 0, hold(22)),
             'hold 30': (30, 7, 0, hold(30)), 'hold 60': (60, 7, 0, 2560),
             'best': (60, 15, 0, 2560 + 192)}
    names = sys.argv[1:] or list(cases) + ['back', 'again', 'throw', 'caught', 'caught-long']
    wrong = 0
    tops = {}

    def report(name, ok, text):
        nonlocal wrong
        wrong += not ok
        print('%-8s %-62s %s' % (name, text, 'OK' if ok else 'WRONG'), flush=True)
    for name in names:
        if name in cases:
            frames, sk, back, want = cases[name]
            gone, got, top = kick(frames, sk, back)
            tops[name] = top
            ok = gone is not None and abs(got - want) <= TOL and \
                (frames < 10 or gone <= 12)
            report(name, ok, 'fire %2d, skill %2d: gone at %s, %4d (want %4d), %2d high'
                   % (frames, sk, gone, got, want, top))
        elif name == 'back':
            gone, got, top = kick(30, 7, BITS['down'])
            if 'hold 30' not in tops:
                tops['hold 30'] = kick(30, 7)[2]
            report(name, gone is not None and top > tops['hold 30'] + 4,
                   'fire 30, pulled back: %4d, %2d high (not: %d)' % (got, top, tops['hold 30']))
        elif name in ('caught', 'caught-long'):
            report(name, *caught(2 if name == 'caught' else 30))
        elif name == 'again':
            report(name, *again())
        elif name == 'throw':
            gone, got, top = throw(30)
            want = 1280 + 32 * 10
            report(name, gone is not None and abs(got - want) <= TOL,
                   'a throw-in held 30: gone at %s, %4d (want %4d), %2d high'
                   % (gone, got, want, top))
    return wrong


if __name__ == '__main__':
    sys.exit(main())
