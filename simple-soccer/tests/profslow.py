#!/usr/bin/env python3
"""Where the slow turns' time goes, routine by routine: the match pace.py
plays (the same plan, rnd without the beam), and for each turn of the
loop whose work (loop to eng_end) is more than three frames' (SLOW)
VICE's CPU history of it, its cycles summed up by the label each
instruction is under (its @locals under their routine; the interrupt
included, where it falls) and by address.

    tests/profslow.py [seed] [slow turns] [top] [skip] [slow]

skip: the first turns left out (60: the kick-off's, which build all three
pictures afresh); slow: the work a turn must be over to count (SLOW; 0:
every turn). As work3.py, every turn plays three frames, so the match
goes the same way whatever the build's speed.

The labels' share of all those turns' cycles, then the busiest
instructions.
"""
import bisect
import collections
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, labels  # noqa: E402
from pace import plan, encode, game_rnd  # noqa: E402

LINE = re.compile(r'\.C:([0-9a-f]{4})  .*?(\d+)\s*$')
SLOW = 106000


def names_of(lab):
    names = {}
    for n, a in sorted(lab.items(), key=lambda t: (t[1], t[0].startswith('@'))):
        if 0x1000 <= a < 0xC000 and not n.startswith('__'):
            names.setdefault(a, n)
    owner = None
    for a in sorted(names):
        if names[a].startswith('@'):
            if owner:
                names[a] = owner + names[a]
        else:
            owner = names[a]
    return names


def main():
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    want = int(sys.argv[2]) if len(sys.argv) > 2 else 20
    top = int(sys.argv[3]) if len(sys.argv) > 3 else 25
    skip = int(sys.argv[4]) if len(sys.argv) > 4 else 60
    slow = int(sys.argv[5]) if len(sys.argv) > 5 else SLOW
    lab = labels()
    names = names_of(lab)
    addrs = sorted(names)
    by_label = collections.Counter()
    by_addr = collections.Counter()
    total = 0
    got = turns = 0
    v = Vice(PRG, WORK)
    try:
        v.cmd('resset "MonitorChisLines" "65536"')     # (a slow turn is more
        v.cmd('break %04x' % lab['main'])               # than the 8192 default)
        v.cmd('x')
        v.cmd('del')
        rnd = game_rnd()
        v.poke(rnd + 7, [0x49, 0x00, 0xEA])
        v.poke(lab['z_rnd'], [1])
        v.poke(lab['dbg_plan'], encode(plan(seed)))
        v.poke(lab['dbg_on'], [2])
        at = lab['loop'] + 6            # (work3.py's: three frames a turn)
        v.poke(at, [0xA9, 3, 0xEA, 0xEA, 0xEA, 0xEA, 0xEA])
        v.cmd('break %04x' % lab['loop'])
        v.cmd('break %04x' % lab['eng_end'])
        t0 = None
        while got < want and turns < 3000:
            v.cmd('x')
            r = v.cmd('r').splitlines()[1].split()
            pc, sw = int(r[0][2:], 16), int(r[-1])
            if pc == lab['loop']:
                t0 = sw
                continue
            turns += 1
            if t0 is None or sw - t0 <= slow or turns <= skip:
                continue
            hist = []
            for l in v.cmd('chis 60000').splitlines():
                m = LINE.match(l)
                if m:
                    hist.append((int(m.group(1), 16), int(m.group(2))))
            starts = [i for i, (a, _) in enumerate(hist) if a == lab['loop']]
            if not starts:
                continue
            hist = hist[starts[-1]:]
            for (a, c), (_, c2) in zip(hist, hist[1:]):
                i = bisect.bisect_right(addrs, a) - 1
                n = names[addrs[i]] if i >= 0 else '?'
                if a >= 0xFC00 or a < 0x1000:
                    n = 'interrupt'
                by_label[n] += c2 - c
                by_addr[a] += c2 - c
            total += hist[-1][1] - hist[0][1]
            got += 1
    finally:
        v.stop()
    print('%d slow turns of %d, %d cycles each on average' % (got, turns, total // max(1, got)))
    for n, c in by_label.most_common(top):
        print('  %-22s %7d  %4.1f%%' % (n, c // max(1, got), 100.0 * c / total))
    print('busiest instructions (cycles per slow turn):')
    for a, c in by_addr.most_common(top):
        i = bisect.bisect_right(addrs, a) - 1
        n = names[addrs[i]] if i >= 0 else '?'
        print('  %04x %-22s+%-3d %6d' % (a, n, a - addrs[i] if i >= 0 else 0, c // max(1, got)))


if __name__ == '__main__':
    main()
