#!/usr/bin/env python3
"""The teams coming on before a match (play.s walk_on, walking), from the
disk in VICE: a match started from the title - the players at first past
the right touch line, back in the tunnel, a step apart (WALK_FROM + 8
each: not drawn there), walking on to their places for the kick-off, the ball dead meanwhile (dead_t 1); once they all
stand there (enter 0), the kick-off - and the joystick's player able to
take it. A test's match (the title skipped, tests/vice.py) has them lined
up at once, as before. The ball on the middle spot then (restart had
put it at the last set piece's place, 0,0: no kick-off for the stick).

    tests/walkon.py

A line each, OK or WRONG; the exit code counts the wrong ones.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import league as L  # noqa: E402
import cpuplay as C  # noqa: E402
from vice import Vice  # noqa: E402

WALK_X = 72 * 8 + 23            # (play.s: the tunnel's mouth)
WALK_FROM = WALK_X + 230
WALK_OUT = 512                  # (along the tunnel's row till here)
TUN_Y = 369 + 7


def sound_lab():
    """sound.s's labels: the match's voices (the title has a v_left of its
    own, under $F000) and the roar's steps"""
    out = {}
    for line in open(os.path.join(os.path.dirname(L.D64), 'simple-soccer.lbl')):
        p = line.split()
        if len(p) == 3 and p[0] == 'al':
            n, a = p[2].lstrip('.'), int(p[1], 16)
            if n in ('v_left', 'v_lo', 'v_hi') and a >= 0xF000 or n in ('fx_goal', 'fx_goal_w'):
                out[n] = a
    return out


S = sound_lab()


def roaring(v):
    """voice 1 on with the roar (fx_goal: its next step there)"""
    left, lo, hi = v.mem(S['v_left'] + 1, 1)[0], v.mem(S['v_lo'] + 1, 1)[0], v.mem(S['v_hi'] + 1, 1)[0]
    return left != 0 and S['fx_goal'] <= lo + 256 * hi <= S['fx_goal_w']


def pause_on(v):
    """RUN/STOP - the pause page - then CONTINUE (its first), the frame's
    break off meanwhile"""
    v.cmd('del')
    v.poke(L.lab['dbg_key'], [0x80])
    L.wait(v, lambda: L.paused(v), 'the pause', 30)
    v.poke(L.lab['dbg_key'], [0])
    v.run_for(0.5)
    v.poke(L.lab['dbg_joy'], [L.FIRE])  # (CONTINUE as fire is let go: the
    v.run_for(0.02)                     # break first - the warp would run
    v.cmd('break %04x' % C.one('play_frame'))   # the walk on to its end)
    v.poke(L.lab['dbg_joy'], [0])
    v.cmd('x')


def places(v):
    m = {n: v.mem(C.one(n), 22) for n in ('o_xl', 'o_xh', 'o_yl', 'o_yh')}
    return [(m['o_xl'][i] + 256 * m['o_xh'][i], m['o_yl'][i] + 256 * m['o_yh'][i]) for i in range(22)]


def main():
    wrong = 0

    def report(name, ok, text):
        nonlocal wrong
        print('%-8s %s %s' % (name, text, 'OK' if ok else 'WRONG'), flush=True)
        wrong += not ok
    v = Vice(L.D64, L.CACHE, drive='1541', title=True)
    try:
        L.wait(v, lambda: L.at_title(v), 'the title')
        v.run_for(0.5)
        v.poke(L.K_CH, [0, 0, 0, L.T['GERMANY'], L.T['BRAZIL']])
        v.cmd('break %04x' % C.one('play_frame'))
        L.press(v)
        v.cmd('x')                      # (the match's first frame)
        start = places(v)
        report('start', all(x >= WALK_FROM - 4 for x, _ in start) and v.mem(C.one('enter'), 1)[0] >= 1,
               'all back in the tunnel: x %d - %d' % (min(x for x, _ in start), max(x for x, _ in start)))
        frames, shot, off_row, seen = 0, 0, 0, 0
        loud, quiet, paused_at = 0, [], 0
        while frames < 2000 and v.mem(C.one('enter'), 1)[0]:
            v.cmd('x')
            frames += 1
            if frames > 3:              # (the crowd roaring as they come,
                if roaring(v):          # held till they all stand - Luca)
                    loud += 1
                else:
                    quiet.append(frames)
            if frames == 60:            # (a pause meanwhile: on with it after)
                pause_on(v)
                paused_at = frames
            if frames % 3 == 0:         # (out of the tunnel, on its row till WALK_OUT)
                for x, y in places(v):
                    if WALK_OUT <= x < WALK_X + 4:
                        seen += 1
                        off_row = max(off_row, abs(y - TUN_Y))
            if not shot and frames == 150:
                v.screenshot(os.path.join(L.CACHE, 'walkon.png'))
                shot = True
            if v.mem(C.one('dead_t'), 1)[0] == 0:
                break
        dead = v.mem(C.one('dead_t'), 1)[0]
        report('roar', paused_at and loud > 100 and not quiet,
               'the crowd roaring %d of the frames coming on, a pause at %d (quiet: %s)'
               % (loud, paused_at, quiet[:8] or 'none'))
        arrived = places(v)
        mov = v.mem(C.one('o_mov'), 22)
        if any(mov):
            t = {n: v.mem(C.one(n), 22) for n in ('o_txl', 'o_txh', 'o_tyl', 'o_tyh')}
            print('   still on the way:', [(i, arrived[i], (t['o_txl'][i] + 256 * t['o_txh'][i],
                                                       t['o_tyl'][i] + 256 * t['o_tyh'][i]))
                                         for i in range(22) if mov[i]])
        report('row', seen > 50 and off_row <= 1,
               'out of the tunnel along its row till x %d: %d seen, at most %d off it' % (WALK_OUT, seen, off_row))
        report('walk', not v.mem(C.one('enter'), 1)[0] and frames < 2000,
               'on and in their places after %d frames, the ball dead till then (dead_t %d)' % (frames, dead))
        for _ in range(5):
            v.cmd('x')
        lined = places(v)
        far = [i for i in range(22) if abs(lined[i][0] - arrived[i][0]) > 2 or abs(lined[i][1] - arrived[i][1]) > 2]
        bx = v.mem(C.one('o_xl') + 22, 1)[0] + 256 * v.mem(C.one('o_xh') + 22, 1)[0]
        by = v.mem(C.one('o_yl') + 22, 1)[0] + 256 * v.mem(C.one('o_yh') + 22, 1)[0]
        report('kickoff', v.mem(C.one('kickoff'), 1)[0] == 1 and v.mem(C.one('dead_t'), 1)[0] == 0
               and not far and (bx, by) == (304, 369),
               'the kick-off waiting, the ball at %d,%d (the middle spot: once at 0,0), no one moved '
               'by the line-up: %s' % (bx, by, far or 'none'))
        v.cmd('del')
    finally:
        v.stop()
    return wrong


if __name__ == '__main__':
    sys.exit(main())
