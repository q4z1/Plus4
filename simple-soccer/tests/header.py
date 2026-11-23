#!/usr/bin/env python3
"""Headers (play.s head): a ball coming at a player's head, in a match in
VICE - the cyan joystick on 9 at (304, 500) facing up, the ball flying
down at him; the others off but the keepers and one yellow far away.

    tests/header.py [case ...]

up        the stick up, fire held: he jumps and heads it up the pitch
right     the stick right, fire held: headed right (the ball near: he
          runs off its way)
none      the stick let go, fire held: headed towards the goal his team
          attacks (up)
nofire    the stick up, no fire: no header - it goes over him (Luca:
          headers of themselves met every ball going by)
high      the ball over his head (40 high), fire held: no header
runner    7 the runner to a pass to him (recv, helper), the joystick on 9
          far off: no header of himself (the joystick's team's runner
          heads none)
try       fire only tapped as the ball (18 high) is still some 30 pixels
          off, the stick let go: he jumps for it at once and heads it as
          it comes (Luca: many more tries at headers)
miss      tapped so as the ball goes over him (36 high): he jumps - a try
          missed, seen - and does not head it
tryup     as try, the ball 22 high, the stick pushed up with the tap: he
          jumps for it and heads it - the diving header (fire with the
          stick) heads only 8 - 15 high, under this one he dived for
          nothing (Luca: do the headers want no way pushed?)
cpu       a cyan shot at head height up the pitch at the computer's 20
          (its runner): no header - it goes over him (Luca: the computer
          intercepts every ball by a header; Sensible Soccer's computer
          heads none)
cpuown    the same ball, but a yellow team-mate's pass: 20 heads it -
          the computer heads its own team's balls in the air, crosses
          and passes (Luca saw too few headers)
cpukick   its keeper's goal kick coming down at 20, who runs up to it: he
          heads it on down the pitch, not back the way he ran (Luca: a
          goal kick headed back out for a corner)

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
    'up': (9, 'up+fire', 18, 'up', HEAD_SPEED),
    'right': (9, 'right+fire', 18, 'right', HEAD_SPEED),
    'none': (9, 'fire', 18, 'up', HEAD_SPEED),
    'nofire': (9, 'up', 18, None, 0),
    'high': (9, 'up+fire', 40, None, 0),
    'runner': (7, '', 18, None, 0),
    'try': (9, 'fire', 18, 'up', HEAD_SPEED),
    'miss': (9, 'fire', 36, None, 0),
    'tryup': (9, 'up+fire', 22, 'up', HEAD_SPEED),
    'cpu': (20, '', 18, None, 0),
    'cpuown': (20, '', 18, 'down', HEAD_SPEED),
    'cpukick': (20, '', 11, 'down', HEAD_SPEED),
}


def bits(s):
    b = 0
    for p in s.split('+'):
        b |= BITS.get(p, 0)
    return b


def level(dist):
    """a flight's rise (8.8) that has it as high as it started dist pixels
    on, at 1536 some 3 a frame: n frames of gravity's $12 take 9 n (n + 1)
    off n steps - the ball flies at head height, as it went with no step
    (0 held it at one height, Luca's height-locked ball: play.s ball_move)"""
    n = round(dist / 3)
    return 9 * (n + 1)


def word(v, lo, hi, i):
    w = v.mem(lab[lo] + i, 1)[0] + 256 * v.mem(lab[hi] + i, 1)[0]
    return w - 65536 if w > 32767 else w


def run_cpu(v, name):
    """the computer's runner 20 at (304, 300) facing down, a cyan shot
    flying up at his head"""
    who = 20
    v.poke(lab['dbg_joy'], [0])
    for _ in range(6):
        v.cmd('x')
    s = moves.Setup()
    moves.open_play(s, 9)
    for i in range(1, 22):
        s.put('o_off', 0 if i in (9, 11, 20) else 1, i)
    s.obj(0, 304, 676, d=0)
    s.obj(11, 304, 62, d=4)
    s.obj(9, 304, 560, d=0)
    s.obj(who, 304, 300, d=4)
    s.put('ctrl_b', who)
    s.pokes.append((lab['ctx_b'] + lab['helper'] - lab['ctx'], [who]))
    s.put('jumps', 0)                   # (none left from the case before)
    s.pokes.append((lab['lock_t'], [0, 0]))
    s.put('kick_pl', 0xFF)              # (nor the case before's header his kick)
    s.put('o_zl', 0, who)               # (nor his jump)
    for n in ('game_min', 'half', 'full', 'enter'):     # (the cases before
        s.put(n, 10 if n == 'game_min' else 0)          # ran the clock on to
                                                        # half time: all off)
    if name == 'cpuown':                # (a yellow team-mate's pass)
        s.put('last_pl', 18)
        s.put('last_team', 1)
    elif name == 'cpukick':             # (its keeper's goal kick)
        s.obj(who, 304, 300, d=0)
        s.put('last_pl', 11)
        s.put('last_team', 1)
    else:
        s.put('last_pl', 9)             # (cyan's shot)
    if name == 'cpukick':
        moves.flight(s, 304, 240, 304, 240 + 32 * 60, 1536, 18, level(60))
    else:
        moves.flight(s, 304, 360, 304, 360 - 32 * 60, 1536, 18, level(60))
    for a, vals in s.pokes:
        v.poke(a, vals)
    v.poke(OFF_PL, [0xFF])
    jump = 0
    zs = []
    for f in range(40):
        v.cmd('x')
        jump = max(jump, v.mem(lab['o_zl'] + who, 1)[0])
        by = word(v, 'o_yl', 'o_yh', BALL)
        if abs(by - 300) < 12:
            zs.append(v.mem(lab['o_zl'] + BALL, 1)[0])
        if v.mem(lab['last_pl'], 1)[0] == who:
            v.screenshot(os.path.join(WORK, 'header-%s.png' % name))
            own = name in ('cpuown', 'cpukick')
            for _ in range(4):
                v.cmd('x')
            dy = word(v, 'o_yl', 'o_yh', BALL) - by
            return own and jump > 0 and dy > 0, '%d took it (his jump %d, the ball %s high at him, then %+d down the pitch)' % (
                who, jump, zs, dy)
    return name not in ('cpuown', 'cpukick'), 'no header: it went by him %s high (he at y %d)' % (zs, word(v, 'o_yl', 'o_yh', who))


def run_try(v, name):
    """9 at (304, 500), the ball flying down at him; fire tapped (four
    frames, with the stick for tryup) once it is within 30 pixels"""
    z = CASES[name][2]
    tap = bits(CASES[name][1])
    v.poke(lab['dbg_joy'], [0])
    for _ in range(6):
        v.cmd('x')
    s = moves.Setup()
    moves.open_play(s, 9)
    for i in range(1, 22):
        s.put('o_off', 0 if i in (7, 9, 11, 21) else 1, i)
    s.obj(0, 304, 676, d=0)
    s.obj(11, 304, 62, d=4)
    s.obj(21, 150, 150, d=4)
    s.obj(7, 100, 650, d=0)
    s.obj(9, 304, 500, d=0)
    moves.flight(s, 304, 440, 304, 440 + 32 * 60, 1536, z, level(60))
    s.put('last_pl', 21)                # (the yellow team's ball)
    s.put('last_team', 1)
    for a, vals in s.pokes:
        v.poke(a, vals)
    v.poke(OFF_PL, [0xFF])
    jump, tapped, zs, dived = 0, None, [], False
    for f in range(40):
        by = word(v, 'o_yl', 'o_yh', BALL)
        if tapped is None and by > 470:
            v.poke(lab['dbg_joy'], [tap])
            tapped = f
        elif tapped is not None and f == tapped + 4:
            v.poke(lab['dbg_joy'], [0])
        v.cmd('x')
        jump = max(jump, v.mem(lab['o_zl'] + 9, 1)[0])
        dived = dived or v.mem(lab['o_slide'] + 9, 1)[0] != 0
        if abs(by - 500) < 12:
            zs.append(v.mem(lab['o_zl'] + BALL, 1)[0])
        if v.mem(lab['last_pl'], 1)[0] == 9:
            if jump:
                v.screenshot(os.path.join(WORK, 'header-%s.png' % name))
            return name != 'miss' and jump > 0 and not dived, \
                '9 headed it (his jump %d, dived %s, tapped at frame %s)' % (jump, dived, tapped)
    return name == 'miss' and jump > 0, 'no header, his jump %d, dived %s, the ball %s high by him' % (
        jump, dived, zs)


def run(v, name):
    if name in ('cpu', 'cpuown', 'cpukick'):
        return run_cpu(v, name)
    if name in ('try', 'miss', 'tryup'):
        return run_try(v, name)
    who, stick, z, way, speed = CASES[name]
    fire = 'fire' in stick              # (fire pressed as the ball comes
    stick = stick.replace('fire', '').strip('+')    # near, 16 pixels: held
    v.poke(lab['dbg_joy'], [bits(stick)])   # from afar, with the stick
    #                                         it is a diving header)
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
    moves.flight(s, 304, y0, 304, y0 + 32 * 60, 1536, z, level(500 - y0))  # soon)
    for a, vals in s.pokes:
        v.poke(a, vals)
    v.poke(OFF_PL, [0xFF])
    jump = 0
    for f in range(40):
        if fire:
            by = word(v, 'o_yl', 'o_yh', BALL)
            py = word(v, 'o_yl', 'o_yh', who)
            if abs(by - py) < 16:
                v.poke(lab['dbg_joy'], [bits(stick) | BITS['fire']])
                fire = False
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
