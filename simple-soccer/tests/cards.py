#!/usr/bin/env python3
"""The cards for a foul, as Sensible Soccer gives them (play.s foul,
c10fca): play.s's foul called again and again in a match in VICE (the
monitor sets the program counter to it, its return to play_frame) for
a yellow player sliding into a cyan one:

  middle    out of the box, yellow team-mates nearer their goal than
            him: a yellow card for ref_k fouls in 32 (the referee's, for
            the match), none else
  second    the same fouler again after a yellow: red
  lastman   the yellow team-mates all further from their goal than him
            (but the keeper): red each time
  box       in the box (a penalty): no card
  walk      a red, then the dead time on: the fouler walks off over the
            nearer touch line (o_off 2, drawn) and is gone (o_off 1) as
            play goes on - out of the pitch by then (Luca: see him go);
            shown as a second yellow (card_c 2: the yellow and the red),
            screenshots cards-walk-30.png, cards-walk-90.png

A second yellow's red has card_c 2 (drawn with the yellow beside it),
a straight red 1. And the crowd heard as each card is shown (Luca): a
yellow's murmur on voice 1 (fx_yellow), the referee's whistle on voice 0;
a red's louder murmur (fx_red) and the whistle with the crowd whistling
(fx_red_w); none without a card.

    tests/cards.py [fouls]

A line each; the exit code 1 if one is not as it should be.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, labels  # noqa: E402
import moves  # noqa: E402

lab = labels()
VICTIM, FOULER = 9, 20
BALL_ID = moves.BALL


def mem1(v, name, i=0):
    return v.mem(lab[name] + i, 1)[0]


def place(v, victim_at, mates_y):
    s = moves.Setup()
    moves.open_play(s, VICTIM, team=0, holder=VICTIM)
    s.obj(VICTIM, *victim_at, d=0)
    s.obj(FOULER, victim_at[0], victim_at[1] + 8, d=0)
    s.obj(BALL_ID, victim_at[0], victim_at[1] - 6)
    for k, i in enumerate(range(12, 22)):
        if i != FOULER:
            s.obj(i, 100 + 45 * k, mates_y, d=4)
    for i in range(22):
        s.put('o_off', 0, i)
    for a, vals in s.pokes:
        v.poke(a, vals)


def call_foul(v):
    """foul, X the fouler, back to play_frame (where the monitor stops)"""
    regs = v.cmd('r')
    ret = lab['play_frame'] - 1
    # the stack pointer: the monitor's register line, its SP column
    line = [ln for ln in regs.splitlines() if ln.strip().startswith('.;')][0]
    head = [ln for ln in regs.splitlines() if 'SP' in ln][0].split()
    vals = line.split()
    sp = int(vals[head.index('SP')], 16)
    v.poke(0x100 + sp, [ret >> 8])
    v.poke(0x100 + sp - 1, [ret & 255])
    v.cmd('r sp = %02x' % (sp - 2))
    v.cmd('r x = %02x' % FOULER)
    v.cmd('r pc = %04x' % lab['foul'])
    v.cmd('x')


def card(v):
    pl, c = mem1(v, 'card_pl'), mem1(v, 'card_c')
    return None if pl == 0xFF else ('yellow' if c == 0 else 'red')


def voice(v, y):
    """where voice y's effect is (sound.s v_lo, v_hi)"""
    return mem1(v, 'v_lo', y) + 256 * mem1(v, 'v_hi', y)


def crowd_ok(v, got):
    """the sound as card got is shown: its effects just started (each a
    step on: 3 bytes)"""
    v1, v0 = voice(v, 1), voice(v, 0)
    if got == 'yellow':
        return v1 == lab['fx_yellow'] + 3 and lab['fx_whistle'] < v0 <= lab['fx_whistle'] + 42
    if got == 'red':
        return v1 == lab['fx_red'] + 3 and lab['fx_red_w'] < v0 <= lab['fx_red_w'] + 42
    return not (lab['fx_yellow'] <= v1 < lab['fx_red_w'])


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 160
    v = Vice(PRG, WORK)
    bad = 0
    try:
        v.cmd('break %04x' % lab['main'])
        v.cmd('x')
        v.cmd('del')
        v.cmd('break %04x' % lab['play_frame'])
        for _ in range(120):
            v.cmd('x')
        v.poke(lab['flip'], [0])
        ref = mem1(v, 'ref_k')
        print('the referee: a yellow for %d fouls in 32' % ref, flush=True)

        placed = [None]
        heard = []

        def run(at, mates_y, fouls_before=0):
            if placed[0] != (at, mates_y):      # (foul moves no one)
                place(v, at, mates_y)
                placed[0] = (at, mates_y)
            v.poke(lab['fouls'] + FOULER, [fouls_before])
            for y in (0, 1):                    # (voice 1 quiet: v_lo, v_hi,
                v.poke(lab['v_lo'] + y, [0])    # v_left)
                v.poke(lab['v_hi'] + y, [0])
                v.poke(lab['v_lo'] + 4 + y, [0])
            call_foul(v)
            got = card(v)
            if not crowd_ok(v, got):
                heard.append((got, voice(v, 0), voice(v, 1)))
            return got

        got = [run((304, 300), 150) for _ in range(n)]
        y = got.count('yellow')
        other = [g for g in got if g not in (None, 'yellow')]
        want = n * ref / 32
        ok = not other and abs(y - want) <= 3 * (want * (1 - ref / 32)) ** 0.5 + 1
        print('middle   %d yellow of %d (%.1f expected)%s  %s'
              % (y, n, want, ', also %s' % other if other else '', 'ok' if ok else 'NOT RIGHT'), flush=True)
        bad += not ok
        got = []
        twos = True
        for _ in range(n):
            got.append(run((304, 300), 150, fouls_before=1))
            if got[-1] == 'red' and mem1(v, 'card_c') != 2:
                twos = False
        r = got.count('red')
        ok = r and set(got) <= {None, 'red'} and twos
        print('second   %d red of %d, %s  %s' % (r, n, sorted(set(map(str, got))),
                                                 'ok' if ok else 'NOT RIGHT'), flush=True)
        bad += not ok
        got = []
        ones = True
        for _ in range(20):
            got.append(run((304, 300), 380))
            ones = ones and mem1(v, 'card_c') == 1
        ok = got.count('red') == 20 and ones
        print('lastman  %s  %s' % (sorted(set(map(str, got))), 'ok' if ok else 'NOT RIGHT'), flush=True)
        bad += not ok
        got = [run((304, 110), 380) for _ in range(20)]
        ok = got.count(None) == 20 and mem1(v, 'rs_kind') == 6
        print('box      %s, rs_kind %d  %s' % (sorted(set(map(str, got))), mem1(v, 'rs_kind'),
                                              'ok' if ok else 'NOT RIGHT'), flush=True)
        bad += not ok
        ok = not heard
        print('crowd    %s  %s' % ('as each card was shown' if ok else
                                   'not right: %s' % heard[:4], 'ok' if ok else 'NOT RIGHT'), flush=True)
        bad += not ok
        place(v, (330, 300), 380)
        placed[0] = None
        v.poke(lab['fouls'] + FOULER, [0])
        call_foul(v)
        v.poke(lab['card_c'], [2])          # (shown as a second yellow's)
        seen2 = 0
        last = None
        for f in range(400):
            v.cmd('x')
            if f in (30, 90):
                v.screenshot(os.path.join(WORK, 'cards-walk-%d.png' % f))
            off = mem1(v, 'o_off', FOULER)
            x = mem1(v, 'o_xl', FOULER) + 256 * mem1(v, 'o_xh', FOULER)
            if off == 2:
                seen2 += 1
                last = x
            if off == 1:
                break
        ok = seen2 > 0 and off == 1 and last is not None and last >= 558
        print('walk     walking off %d frames, last seen at x %s, then o_off %d  %s'
              % (seen2, last, off, 'ok' if ok else 'NOT RIGHT'), flush=True)
        bad += not ok
    finally:
        v.stop()
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
