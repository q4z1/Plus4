#!/usr/bin/env python3
"""Players put at their destinations from far off: a match with the
joystick at random (as tests/soak.py), the game held each time arrive
puts a player at his destination, and a line for each one more than
FAR pixels from it - his place, the destination, his step, aim's notes,
and who called arrive.

    tests/arrive.py [pictures] [seed] [two]

The exit code counts them (at most 255).
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, labels, held_from_start  # noqa: E402
import soak  # noqa: E402

FAR = 16


def snap_at(lab):
    """where arrive puts the destination's y in the place's"""
    d = open(PRG, 'rb').read()
    base = 0x1001 - 2
    a, t, y = lab['arrive'], lab['o_tyl'], lab['o_yl']
    i = d[a - base:a - base + 120].find(bytes([0xBD, t & 255, t >> 8, 0x9D, y & 255, y >> 8]))
    assert i >= 0, 'arrive: no lda o_tyl,x / sta o_yl,x'
    return a + i


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 3000
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    two = len(sys.argv) > 3 and sys.argv[3] == 'two'
    rnd = random.Random(seed)
    pa = dict(soak.plan(rnd, n))
    pb = dict(soak.plan(rnd, n)) if two else {}
    lab = labels()
    snap = snap_at(lab)
    names = sorted((a, k) for k, a in lab.items() if 0x1000 < a < 0xC000)
    v = Vice(PRG, WORK, title=False)
    seen = hits = pic = 0
    try:
        held_from_start(v, lab, 'none')
        if two:
            v.poke(lab['two'], [1])
        v.cmd('break %04x' % lab['eng_end'])
        v.cmd('break %04x' % snap)
        m = lambda a, k=1: v.mem(a, k)
        while pic < n:
            v.cmd('x')
            r = v.cmd('r').splitlines()[1].split()
            if int(r[0][2:], 16) != snap:
                pic += 1
                if pic in pa:
                    v.poke(lab['dbg_joy'], [pa[pic]])
                if pic in pb:
                    v.poke(lab['dbg_joyb'], [pb[pic]])
                continue
            hits += 1
            x, sp = int(r[2], 16), int(r[4], 16)
            g = lambda k: m(lab[k] + x)[0]
            w = lambda lo, hi: g(lo) + 256 * g(hi)
            if x >= soak.BALL or abs(w('o_yl', 'o_yh') - w('o_tyl', 'o_tyh')) <= FAR:
                continue
            seen += 1
            st = m(0x100 + sp + 1, 8)
            rets = [(st[i] | st[i + 1] << 8) + 1 for i in range(0, 8, 2)]
            name = lambda a: next(('%s+%d' % (k, a - b) for b, k in reversed(names) if b <= a), '?')
            print('%5d player %d at (%d, %d), to (%d, %d), step y %d; aim: way %d, angle %d; from %s'
                  % (pic, x, w('o_xl', 'o_xh'), w('o_yl', 'o_yh'), w('o_txl', 'o_txh'), w('o_tyl', 'o_tyh'),
                     g('o_vyl'), g('o_dir'), g('c_th'), ', '.join(name(a) for a in rets[:2])), flush=True)
    finally:
        v.stop()
    print('%d pictures, %d arrivals, %d from far off' % (pic, hits, seen))
    sys.exit(min(seen, 255))


if __name__ == '__main__':
    main()
