#!/usr/bin/env python3
"""Where each turn of the loop goes, part by part, in the match pace.py
plays (the same plan, rnd without the beam): VICE's stopwatch at the
parts' entries - the match's frames (play_frame, as many as frames were
shown), its once-a-picture part (play_picture), place and follow, the
picture begun (eng_begin: the ground moved, the figures taken off), the
figures sorted (sort) and drawn (draw), the score and the card - up to
eng_end, where the turn waits for its picture to be shown. In stopwatch
cycles (1.77 MHz: in the picture a CPU cycle counts two); three frames
are about 106k.

    tests/parts.py [seed] [turns] [label,...]

With labels: those as the parts instead (each part from one of them to
the next one met, eng_end closing the turn), e.g. the routines
play_picture calls: play_picture,team_ai,help,switch,brain,draw_it

Each part's mean over all turns, and over the turns that took longer than
three frames' work (SLOW), and their share of those.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, labels  # noqa: E402
from pace import plan, encode, game_rnd  # noqa: E402

PARTS = ['loop', 'play_picture', 'draw_it', 'eng_begin', 'sort', 'draw', 'draw_hud', 'eng_end']
SLOW = 106000


def main():
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    turns = int(sys.argv[2]) if len(sys.argv) > 2 else 400
    lab = labels()
    own = sys.argv[3].split(',') if len(sys.argv) > 3 else None
    parts = (['loop'] + own + ['eng_end']) if own else PARTS
    v = Vice(PRG, WORK)
    try:
        v.cmd('break %04x' % lab['main'])
        v.cmd('x')
        v.cmd('del')
        rnd = game_rnd()
        v.poke(rnd + 7, [0x49, 0x00, 0xEA])
        v.poke(lab['z_rnd'], [1])
        v.poke(lab['dbg_plan'], encode(plan(seed)))
        v.poke(lab['dbg_on'], [2])
        at = {lab[p]: p for p in parts}
        for a in at:
            v.cmd('break %04x' % a)
        rows = []
        cur, last_p, last_sw = {}, None, None
        while len(rows) < turns:
            v.cmd('x')
            r = v.cmd('r').splitlines()[1].split()
            pc, sw = int(r[0][2:], 16), int(r[-1])
            p = at.get(pc)
            if p is None:
                continue
            if last_p is not None and last_p != 'eng_end':
                name = last_p if own else {
                    'loop': 'frames', 'play_picture': 'picture', 'draw_it': 'place',
                    'eng_begin': 'begin', 'sort': 'sort', 'draw': 'draw',
                    'draw_hud': 'hud'}[last_p]
                cur[name] = cur.get(name, 0) + sw - last_sw
            if p == 'eng_end':
                if cur:
                    rows.append(cur)
                cur = {}
            last_p, last_sw = p, sw
        names = parts[:-1] if own else ['frames', 'picture', 'place', 'begin', 'sort', 'draw', 'hud']
        slow = [r for r in rows if sum(r.values()) > SLOW]
        print('%-8s %8s %8s %6s' % ('part', 'all', 'slow', 'share'))
        tot_s = sum(sum(r.values()) for r in slow) / max(1, len(slow))
        for n in names:
            a = sum(r.get(n, 0) for r in rows) / len(rows)
            s = sum(r.get(n, 0) for r in slow) / max(1, len(slow))
            print('%-12s %8d %8d %5.1f%%' % (n, a, s, 100 * s / tot_s if tot_s else 0))
        print('%-8s %8d %8d' % ('total', sum(sum(r.values()) for r in rows) / len(rows), tot_s))
        print('%d turns, %d over %d' % (len(rows), len(slow), SLOW))
    finally:
        v.stop()


if __name__ == '__main__':
    main()
