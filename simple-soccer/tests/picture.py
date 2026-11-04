#!/usr/bin/env python3
"""The pictures themselves, figures and all, to compare two builds: the
match work3.py plays (every turn three frames: the same match whatever
the build's speed), and at the end of some turns (eng_end) the picture
just finished rendered from memory - its matrix (the rows shown), its
characters and its colours - into a hash of its pixels and colours. The
codes a build gives its characters may differ, the pixels may not.

    tests/picture.py out.json [seed] [turns] [every]

Then compare two runs:

    tests/picture.py --diff a.json b.json

(the turns whose pictures differ; the first difference's cell)
"""
import hashlib
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, labels  # noqa: E402
from pace import plan, encode, game_rnd  # noqa: E402

SCR_W, VIS_H = 40, 23
MATS = [0xC000, 0xD000, 0xE800]         # each picture's colours (codes $400 on)
FNTS = [0xC800, 0xD800, 0xF000]         # and characters


def grab(v, lab):
    """the picture just finished (back): (row0, col0, its cells' pixel
    and colour bytes as hex, row by row)"""
    b = v.mem(lab['back'], 1)[0]
    mat = v.mem(MATS[b], 0x400 + SCR_W * VIS_H)
    font = v.mem(FNTS[b], 0x800)
    cells = []
    for i in range(SCR_W * VIS_H):
        code = mat[0x400 + i]
        cells.append(bytes(font[code * 8:code * 8 + 8]).hex() + '%02x' % mat[i])
    return cells


def run(out, seed, turns, every):
    lab = labels()
    v = Vice(PRG, WORK)
    pics = {}
    try:
        v.cmd('break %04x' % lab['main'])
        v.cmd('x')
        v.cmd('del')
        rnd = game_rnd()
        v.poke(rnd + 7, [0x49, 0x00, 0xEA])
        v.poke(lab['z_rnd'], [1])
        v.poke(lab['dbg_plan'], encode(plan(seed)))
        v.poke(lab['dbg_on'], [2])
        v.poke(lab['loop'] + 6, [0xA9, 3, 0xEA, 0xEA, 0xEA, 0xEA, 0xEA])
        v.cmd('break %04x' % lab['eng_end'])
        for t in range(turns):
            v.cmd('x')
            if t >= 20 and t % every == 0:
                cells = grab(v, lab)
                pics[t] = {'hash': hashlib.md5(''.join(cells).encode()).hexdigest(),
                           'cells': cells}
    finally:
        v.stop()
    json.dump(pics, open(out, 'w'))
    print('%d pictures' % len(pics))


def diff(a, b):
    pa, pb = json.load(open(a)), json.load(open(b))
    bad = [t for t in pa if t in pb and pa[t]['hash'] != pb[t]['hash']]
    print('%d pictures compared, %d differ' % (len(set(pa) & set(pb)), len(bad)))
    for t in bad[:8]:
        ca, cb = pa[t]['cells'], pb[t]['cells']
        d = [i for i in range(len(ca)) if ca[i] != cb[i]]
        print('  turn %s: %d cells, the first row %d column %d: %s / %s' % (
            t, len(d), d[0] // SCR_W, d[0] % SCR_W, ca[d[0]], cb[d[0]]))
    return len(bad)


if __name__ == '__main__':
    if sys.argv[1] == '--diff':
        sys.exit(min(255, diff(sys.argv[2], sys.argv[3])))
    run(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 3,
        int(sys.argv[3]) if len(sys.argv) > 3 else 400,
        int(sys.argv[4]) if len(sys.argv) > 4 else 5)
