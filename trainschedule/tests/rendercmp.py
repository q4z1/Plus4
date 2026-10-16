#!/usr/bin/env python3
"""rendercmp.py a b - two traces of trace.py compared by what the view
shows, second by second: each of its cells as its glyph and colour, not
its character's number (two builds may hand out the trains' characters
differently and still show the same). The pointer's cells are taken as
what is under them. Lists the seconds that differ, and where.
"""
import sys

from tracecmp import Trace, BASE

FONT = 0xC000
ROWS = range(2, 18)             # the map (game.inc: VIEW_TOP, VIEW_H)


def view(t, m):
    chars, cols = t.screen(m)
    out = []
    for r in ROWS:
        for c in range(40):
            o = r * 40 + c
            code = chars[o]
            g = m[FONT + code * 8 - BASE:FONT + code * 8 + 8 - BASE]
            out.append((g, cols[o]))
    return out


def main():
    a, b = Trace(sys.argv[1]), Trace(sys.argv[2])
    n = min(a.n, b.n)
    if a.n != b.n:
        print(f'lengths differ: {a.n} and {b.n} seconds')
    bad = 0
    for i in range(n):
        va, vb = view(a, a.mem(i)), view(b, b.mem(i))
        diff = [k for k in range(len(va)) if va[k] != vb[k]]
        if diff:
            bad += 1
            if bad <= 20:
                where = ', '.join(f'{ROWS[0] + k // 40}/{k % 40}' for k in diff[:8])
                print(f'second {i}: {len(diff)} cells differ: {where}')
    print(f'{n} seconds, {bad} differ')


if __name__ == '__main__':
    main()
