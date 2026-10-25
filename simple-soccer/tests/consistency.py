#!/usr/bin/env python3
"""Are the pictures right? At the end of many pictures (eng_end), every
cell of the picture just finished that no figure took must show the
ground's character for its place: its code's pixels in the picture's set
against the ground's character from the map. Runs the player about in
every direction meanwhile, dribbling and passing.

    tests/consistency.py [pictures per direction] [jump]

With jump, the ball (which the view follows) is also moved by up to that
many pixels either way before each picture, so the view moves by several cells between a
picture's builds (shift's longer moves, and full builds).
"""
import random
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, labels, run_pictures  # noqa: E402

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(HERE, 'tools'))
import mkdata  # noqa: E402

MAT = (0xC000, 0xD000, 0xE800)
FNT = (0xC800, 0xD800, 0xF000)


def main():
    per = int(sys.argv[1]) if len(sys.argv) > 1 else 6
    jump = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    rnd = random.Random(1)
    rows = mkdata.pitch()
    font = mkdata.chars()
    lab = labels()
    v = Vice(PRG, WORK)
    bad = checked = 0
    try:
        for _ in range(200):
            v.run_for(0.1)
            if lab['main'] <= int(v.cmd('r').splitlines()[1].split()[0][2:], 16) < 0xC000:
                break
        run_pictures(v, lab, 10)
        v.cmd('break %04x' % lab['eng_end'])
        moves = [8 + 16, 2 + 16, 4 + 16, 1 + 16, 8 + 2 + 16, 4 + 1 + 16, 8, 2, 4, 1,
                 8 + 1 + 16, 4 + 2 + 16, 2 + 16, 2 + 16, 8 + 16, 8 + 16]
        for m in moves * 2:
            v.poke(lab['dbg_joy'], [m])
            for _ in range(per):
                if jump:                # the ball, which the view follows
                    for lo, hi, top in (('o_xl', 'o_xh', 560), ('o_yl', 'o_yh', 700)):
                        p = v.mem(lab[lo] + 22, 1)[0] + 256 * v.mem(lab[hi] + 22, 1)[0]
                        p = min(max(p + rnd.randint(-jump, jump), 40), top)
                        v.poke(lab[lo] + 22, [p & 255])
                        v.poke(lab[hi] + 22, [p >> 8])
                v.cmd('x')
                b = v.mem(lab['back'], 1)[0]
                col, row = v.mem(lab['b_col'] + b, 1)[0], v.mem(lab['b_row'] + b, 1)[0]
                # the cells the figures took: a figure at a time, from
                # picture b's base (eng_end sets b_nlist from z_lst)
                base = (0, 85, 170)[b]
                n = v.mem(lab['z_lst'], 1)[0] - base
                figs = set()
                if n:
                    lo = v.mem(lab['l_lo'] + base, n)
                    hi = v.mem(lab['l_hi'] + base, n)
                    cn = v.mem(lab['l_n'] + base, n)
                    ci = v.mem(lab['l_ci'] + base, n)
                    offs = v.mem(lab['offs'] + 256 * b, 256)
                    for l, h, k, c in zip(lo, hi, cn, ci):
                        o0 = (l + 256 * h) & 0xFFFF
                        if o0 >= 0x8000:
                            o0 -= 0x10000
                        for i in range(k):
                            o = o0 + offs[(c + i) & 255]
                            figs.add((o % 40, o // 40))
                codes = v.mem(MAT[b] + 0x400, 1000)
                fnt = v.mem(FNT[b], 2048)
                for r in range(25):
                    for c in range(40):
                        if (c, r) in figs:
                            continue
                        ch = rows[row + r][col + c]
                        code = codes[r * 40 + c]
                        checked += 1
                        if fnt[code * 8:code * 8 + 8] != list(font[ch * 8:ch * 8 + 8]):
                            bad += 1
                            if bad <= 10:
                                print('picture %d at %d,%d: cell %d,%d code %d is not character %02x'
                                      % (b, col, row, c, r, code, ch))
        print('%d cells checked, %d wrong' % (checked, bad))
    finally:
        v.stop()
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
