#!/usr/bin/env python3
"""p4emu_profile.py [room] [floor] - where the time goes, in plus4emu:
the program counter sampled every few microseconds while the farmer walks
about, each sample put down to the label before it (build/stardew.lbl,
C functions and assembler labels alike). The wait for the picture to be
shown (main's loop on 'ready') counts as idle.

    tests/p4emu_profile.py MINE_A 23
    tests/p4emu_profile.py TOWN"""
import bisect, collections, ctypes, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p4emu_snow as S
from p4emu import ROOT

room = sys.argv[1] if len(sys.argv) > 1 else 'MINE_A'
floor = int(sys.argv[2]) if len(sys.argv) > 2 else (23 if room.startswith('MINE') else 0)

lab = []
for line in open(os.path.join(ROOT, 'build', 'stardew.lbl')):
    a, n = line.split()[1:3]
    n = n.lstrip('.')
    if n.startswith('__') or n.startswith('@') or re.fullmatch(r'L[0-9A-F]{4}', n):
        continue                        # (C's own labels: to their function)
    lab.append((int(a, 16), n))
lab = sorted(set(lab))
addrs = [a for a, _ in lab]


def name(pc):
    if pc >= 0xFC00 or pc < 0x1000:
        return 'rom/low $%04X' % pc
    i = bisect.bisect_right(addrs, pc) - 1
    return lab[i][1] if i >= 0 else '?'


e = S.boot()
try:
    S.goto(e, room, 9 if floor else 10, 9 if floor else 6, floor=floor)
    e.frame(20)
    L = e.lib
    L.Plus4VM_GetProgramCounter.restype = ctypes.c_uint16
    hits = collections.Counter()
    pcs = collections.Counter()
    keys = ('left', 'right')
    for i in range(200):
        e.set('dbg_keys', S.K[keys[(i // 40) % 2]])
        end = e.frames + 1
        while e.frames < end:
            L.Plus4VM_Run(e.vm, ctypes.c_size_t(7))
            pc = L.Plus4VM_GetProgramCounter(e.vm)
            hits[name(pc)] += 1
            pcs[pc & 0xFFF0] += 1
    total = sum(hits.values())
    print('%s, floor %d: %d samples' % (room, floor, total))
    for n, c in hits.most_common(40):
        print('  %5.1f %%  %s' % (100.0 * c / total, n))
    if os.environ.get('BUCKET'):
        lo, hi = (int(x, 16) for x in os.environ['BUCKET'].split('-'))
        print('by address, $%04X-$%04X:' % (lo, hi))
        for a in sorted(pcs):
            if lo <= a < hi:
                print('  $%04X %5.2f %%' % (a, 100.0 * pcs[a] / total))
finally:
    e.stop()
