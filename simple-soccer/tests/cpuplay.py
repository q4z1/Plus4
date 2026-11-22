#!/usr/bin/env python3
"""A match of the computer against itself, from the disk in VICE: both
teams played by the brain (play.s), each as good as the title makes the
computer's team of its level - to set beside Sensible Soccer's own
computer matches, how many goals and from where.

    tests/cpuplay.py [home away [length [n]]]

home, away: teams by their names on the title (by default GERMANY
BRAZIL); length: 0 3 minutes, 1 5 (the default), 2 7; n: matches one
after the other (each its own from the title).

Nothing in the program is changed for it; the test patches it in memory:
the title's runs and keeps take the cyan team as the computer's too
(their cpx #0 for side 0, the joystick's), and in the match cpu_side says
"the computer's" for both, play_frame leaves the cyan team's stick (pj)
to the brain, control makes the cyan brain's passes and shots (br_ev),
and play_picture's end calls the brain for the cyan team too, once a
picture as for the yellow team (a hook in the free bytes before KEEPTAB).

A line for each goal: the minute, who scored, from where the last kick
came (the ball's place when its speed last jumped, the scorer's own) and
how far from the goal; then the score.
"""
import math
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
import league as L  # noqa: E402
import plan as P  # noqa: E402

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOOK = 0xB1B0                   # (DATA's end to KEEPTAB at $B200: free)
BALL = 22
R_PENALTY = 6
SHOTS = os.environ.get('CPUPLAY_SHOTS')
IDLE = os.environ.get('CPUPLAY_IDLE')     # (the cyan team a player's who never moves the stick)
# (his fire: tapped three frames every 100 - as in Sensible Soccer's test:
# its kick-offs wait for a player; the plan in dbg_plan, 64 at most)
TAPS = [(50 + 100 * k + d, b) for k in range(31) for d, b in ((0, 'fire'), (3, 'none'))]
TAPS_END = 3150


def all_labels():
    out = {}
    for line in open(os.path.join(HERE, 'build', 'simple-soccer.lbl')):
        p = line.split()
        if len(p) == 3 and p[0] == 'al':
            out.setdefault(p[2].lstrip('.'), []).append(int(p[1], 16))
    return out


A = all_labels()


def one(n):
    return A[n][0]


def find(v, start, pattern, span=600, what=''):
    data = bytes(v.mem(start, span))
    i = data.find(bytes(pattern))
    assert i >= 0, 'not found: ' + what
    return start + i


def zp_or_abs(op_zp, op_abs, addr):
    return [op_zp, addr] if addr < 256 else [op_abs, addr & 255, addr >> 8]


def patch_title(v):
    """runs: cpx #0 / beq @put - never; keeps: cpx #0 / bne @cpu - always"""
    at = find(v, one('runs'), [0xE0, 0x00, 0xF0], what='runs cpx #0')
    v.poke(at + 2, [0xF0, 0x00])
    at = find(v, one('keeps'), [0xE0, 0x00, 0xD0], what='keeps cpx #0')
    v.poke(at + 2, [0xB0])          # (bcs: cpx #0 sets carry)


def patch_game(v):
    me, pj, br_ev = one('me'), one('pj'), one('br_ev')
    # cpu_side: lda two / bne / lda me / cmp #1 / rts -> lda me / cmp #1: sec
    p = zp_or_abs(0xA5, 0xAD, me) + [0xC9, 0x01]
    at = find(v, one('cpu_side'), p, 16, 'cpu_side')
    v.poke(at, [0x38] + [0xEA] * (len(p) - 1))
    # play_frame: the joystick into pj before off_chk - not stored
    off = one('off_chk')
    p = zp_or_abs(0x85, 0x8D, pj) + [0x20, off & 255, off >> 8]
    at = find(v, one('play_frame'), p, 200, 'sta pj')
    v.poke(at, [0x24] if pj < 256 else [0x2C])
    # control @ev: lda me / beq @fire / lda br_ev - the branch out
    data = bytes(v.mem(one('control'), 1500))
    lme, lev = bytes(zp_or_abs(0xA5, 0xAD, me)), bytes(zp_or_abs(0xA5, 0xAD, br_ev))
    m = re.search(re.escape(lme) + b'\xf0.' + re.escape(lev), data, re.S)
    assert m, 'control @ev'
    v.poke(one('control') + m.start() + len(lme), [0xEA, 0xEA])
    # play_picture: jsr brain / : jmp swap -> jmp HOOK
    brain, swap = one('brain'), one('swap')
    at = find(v, one('play_picture'), [0x20, brain & 255, brain >> 8, 0x4C, swap & 255, swap >> 8],
              200, 'play_picture end')
    v.poke(at + 3, [0x4C, HOOK & 255, HOOK >> 8])
    # HOOK: jsr swap / lda dead_t / bne @rts / ldx ctrl / bmi @rts / jsr brain / @rts: rts
    tail = [0x20, brain & 255, brain >> 8, 0x60]
    ldx = zp_or_abs(0xA6, 0xAE, one('ctrl'))
    part2 = ldx + [0x30, 3] + tail          # (bmi over the jsr)
    hook = [0x20, swap & 255, swap >> 8] + zp_or_abs(0xA5, 0xAD, one('dead_t')) + \
        [0xD0, len(part2) - 1] + part2      # (bne to the rts)
    # swap: the brain's state (br_ev .. bs_rot, br_70, br_d) is one for the
    # yellow team only - traded too, with the cyan team's in BUF
    zp0, zpn = one('br_ev'), one('bs_rot') - one('br_ev') + 1
    hi0, hin = one('br_70'), 3
    assert one('br_d') == hi0 + 1
    myswap = HOOK + len(hook)
    buf = myswap + 2 * 19 + 7
    code = []
    for base, n, off in ((zp0, zpn, 0), (hi0, hin, zpn)):
        b = buf + off
        code += [0xA0, n - 1,                                   # ldy #n-1
                 0xB9, base & 255, base >> 8, 0x48,             # lda base,y / pha
                 0xB9, b & 255, b >> 8,                         # lda buf,y
                 0x99, base & 255, base >> 8, 0x68,             # sta base,y / pla
                 0x99, b & 255, b >> 8, 0x88, 0x10, 0xEF]       # sta buf,y / dey / bpl
    first = v.mem(swap, 4)
    assert first[0] == 0xA5 and first[2] == 0xA4, 'swap: lda ctx / ldy ctx_b'
    code += first + [0x4C, (swap + 4) & 255, (swap + 4) >> 8]
    assert len(code) == 2 * 19 + 7
    hook += code + [0] * (zpn + hin)
    assert HOOK + len(hook) <= 0xB200, 'no room: %d bytes' % len(hook)
    assert v.mem(HOOK, len(hook)) == [0] * len(hook), 'the hook\'s bytes not free'
    v.poke(HOOK, hook)
    v.poke(swap, [0x4C, myswap & 255, myswap >> 8])


def match(v, home, away, length):
    L.wait(v, lambda: L.at_title(v), 'the title')
    v.run_for(0.5)
    v.poke(L.K_CH, [length, 0, 0, L.T[home], L.T[away]])
    for row in (4, 5):              # (each team's formation its own: on and back)
        v.poke(L.lab['t_row'], [row])
        L.press(v, 0x08, 0.1)
        L.press(v, 0x04, 0.1)
    assert L.ram(v, L.K_CH + 3, 2) == [L.T[home], L.T[away]]
    forms = L.ram(v, L.K_CH + 5, 2)
    if not IDLE:
        patch_title(v)
    v.cmd('break %04x' % one('play_frame'))
    L.press(v)
    v.cmd('x')                      # (to the match's first frame)
    v.cmd('del')
    if not IDLE:
        patch_game(v)
    if os.environ.get('CPUPLAY_RUNNER'):    # (a trial: the joystick's team's
        me = one('me')                      # runner goes for the other team's
        data = bytes(v.mem(one('help'), 60))    # ball, as the computer's)
        pat = bytes([0xA4, me, 0xF0, 0x02, 0xA9, 0x00])
        i = data.find(pat)
        assert i >= 0, 'help: ldy me / beq / lda #0'
        v.poke(one('help') + i, [0xA5, me, 0x49, 0x01, 0xEA, 0xEA])
    for item in filter(None, os.environ.get('CPUPLAY_POKES', '').split(';')):
        name, vals = item.split('=')        # (a trial: label=bytes,...)
        v.poke(one(name), [int(x) for x in vals.split(',')])
    else:
        v.poke(L.lab['dbg_joy'], [0])
        P.start(v, L.lab, TAPS)
    score_at, full_at, minute = one('score'), A['full'][-1], one('game_min')
    goals, last = [], [0, 0]
    kick = (None, None)
    old_sp, was = 0, (None, None)
    kicks = polls = waited = pens = 0
    t0 = time.time()
    while time.time() - t0 < 1800:
        v.run_for(0.03)
        st = {n: v.mem(one(n) + BALL, 1)[0] for n in ('o_xl', 'o_xh', 'o_yl', 'o_yh', 'o_spl', 'o_sph')}
        sp = st['o_spl'] + 256 * st['o_sph']
        at = (st['o_xl'] + 256 * st['o_xh'], st['o_yl'] + 256 * st['o_yh'])
        if sp > old_sp + 300:       # (a kick: where the ball was before it)
            kick = was
            kicks += 1
        polls += 1
        if SHOTS and polls % 150 == 0:
            v.screenshot(os.path.join(L.CACHE, 'cpuplay-%03d.png' % (polls // 150)))
        old_sp, was = sp, at
        sc = v.mem(score_at, 2)
        if sc != last:
            for side in (0, 1):
                if sc[side] > last[side]:
                    gy = 49 if side == 0 else 689   # (cyan attacks up: the top goal)
                    d = None if kick[0] is None else round(math.hypot(kick[0] - 304, kick[1] - gy))
                    goals.append((v.mem(minute, 1)[0], side, kick, d))
                    print('  %2d\' %s from %s, %s px out' % (goals[-1][0], ('cyan', 'yellow')[side], kick, d),
                          flush=True)
            last = sc
        ko, kind, team = v.mem(one('kickoff'), 1)[0], v.mem(one('rs_kind'), 1)[0], v.mem(one('rs_team'), 1)[0]
        waited = waited + 1 if ko else 0
        if IDLE and v.mem(one('dbg_t') + 1, 1)[0] >= TAPS_END >> 8:
            P.start(v, L.lab, TAPS)     # (on: the next 3100 frames)
            pens += 1
        if ko and kind == R_PENALTY and team == 0 and waited % 60 == 59 and not IDLE:
            v.poke(one('pj'), [0x10])   # (cyan's penalty: cpu_take's are the
            v.run_for(0.02)             # yellow team's - fire as a player's)
            pens += 1
        if waited == 600:
            print('  stuck: kickoff, kind %d, team %d' % (kind, team), flush=True)
            v.screenshot(os.path.join(L.CACHE, 'cpuplay-stuck.png'))
        if v.mem(full_at, 1)[0]:
            break
    print('  %d kicks seen in %d looks, %d fire taps at penalties' % (kicks, polls, pens))
    return forms, last, goals


def main():
    home = sys.argv[1] if len(sys.argv) > 1 else 'GERMANY'
    away = sys.argv[2] if len(sys.argv) > 2 else 'BRAZIL'
    length = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    n = int(sys.argv[4]) if len(sys.argv) > 4 else 1
    v = Vice(L.D64, L.CACHE, drive='1541', title=True)
    try:
        for k in range(n):
            forms, sc, goals = match(v, home, away, length)
            print('%s %d - %d %s (formations %s)' % (home, sc[0], sc[1], away, forms), flush=True)
            if k + 1 < n:
                L.press(v)
                v.run_for(1)
                L.press(v)
    finally:
        v.stop()


if __name__ == '__main__':
    main()
