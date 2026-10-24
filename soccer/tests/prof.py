#!/usr/bin/env python3
"""Where a turn's time goes, instruction by instruction: VICE's CPU
history from one turn of the loop (loop) to its eng_end, the cycles summed up
by the label each instruction is under (the interrupt included, where
it falls), and by address for the busiest.

    tests/prof.py [dir] [top] [routine]
                                 dir as in shot.py, held while measuring;
                                 routine: a picture that called it (shift)
"""
import bisect
import collections
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, BITS, labels, run_pictures  # noqa: E402

LINE = re.compile(r'\.C:([0-9a-f]{4})  .*?(\d+)\s*$')


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else ''
    top = int(sys.argv[2]) if len(sys.argv) > 2 else 12
    want = sys.argv[3] if len(sys.argv) > 3 else None
    lab = labels()
    names = {}
    for n, a in lab.items():
        if 0x1000 <= a < 0xC000 and not n.startswith('__'):
            names.setdefault(a, n)
    addrs = sorted(names)
    v = Vice(PRG, WORK)
    try:
        for _ in range(200):
            v.run_for(0.1)
            if lab['main'] <= int(v.cmd('r').splitlines()[1].split()[0][2:], 16) < 0xC000:
                break
        run_pictures(v, lab, 20)
        if d:
            bits = 0
            for p in d.split('+'):
                bits |= BITS.get(p, 0)
            v.poke(lab['dbg_joy'], [bits])
            run_pictures(v, lab, 20)
        v.cmd('break %04x' % lab['eng_end'])
        for _ in range(20):
            v.cmd('x')
            hist = []
            for l in v.cmd('chis 60000').splitlines():
                m = LINE.match(l)
                if m:
                    hist.append((int(m.group(1), 16), int(m.group(2))))
            starts = [i for i, (a, _) in enumerate(hist) if a == lab['loop']]
            if not starts:
                print('history: %d instructions, no turn start in it' % len(hist))
                continue
            start = starts[-1]
            hist = hist[start:]
            if not want or any(a == lab[want] for a, _ in hist):
                break
    finally:
        v.stop()
    by_label = collections.Counter()
    by_addr = collections.Counter()
    for (a, c), (_, c2) in zip(hist, hist[1:]):
        i = bisect.bisect_right(addrs, a) - 1
        n = names[addrs[i]] if i >= 0 else '?'
        if a >= 0xFC00:
            n = 'interrupt'
        by_label[n] += c2 - c
        by_addr[a] += c2 - c
    total = hist[-1][1] - hist[0][1]
    print('picture: %d cycles' % total)
    for n, c in by_label.most_common():
        print('  %-12s %6d  %4.1f%%' % (n, c, 100.0 * c / total))
    print('busiest instructions:')
    for a, c in by_addr.most_common(top):
        i = bisect.bisect_right(addrs, a) - 1
        print('  %04x %-12s+%-3d %6d' % (a, names[addrs[i]], a - addrs[i], c))


if __name__ == '__main__':
    main()
