#!/usr/bin/env python3
"""The work of the match pace.py plays, with every turn of the loop made
to play exactly three frames (its frames since the last turn patched to
a constant 3 - lda frames, sec, sbc played after loop's inc tick): the
match then goes the same way however long the turns take, so two builds
can be compared turn for turn - a pure speed-up leaves the match as it
was (the hash at the end the same) and only the cycles change.

    tests/work3.py [seed] [turns]

The work of each turn is loop to eng_end on VICE's stopwatch (1.77 MHz;
three frames are 106k, but a picture done after about 95k misses its
frame - the swap is at a fixed line). Prints the mean, the most, how many
turns went over 95k and 106k, the parts' sums (loop to place: the
match; place to eng_end: the pictures), and a hash of the players', the
ball's and the score's state.
"""
import hashlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, labels  # noqa: E402
from pace import plan, encode, game_rnd  # noqa: E402


def main():
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    turns = int(sys.argv[2]) if len(sys.argv) > 2 else 500
    lab = labels()
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
        at = lab['loop'] + 6            # (jsr joy_read, inc tick)
        fr, pl = lab['frames'], lab['played']
        want = [0xAD, fr & 255, fr >> 8, 0x38, 0xED, pl & 255, pl >> 8]
        assert list(v.mem(at, 7)) == want, 'the loop has changed: %s' % list(v.mem(at, 7))
        v.poke(at, [0xA9, 3, 0xEA, 0xEA, 0xEA, 0xEA, 0xEA])
        v.cmd('break %04x' % lab['loop'])
        v.cmd('break %04x' % lab['place'])
        v.cmd('break %04x' % lab['eng_end'])
        works, matches = [], []
        t0 = tp = None
        while len(works) < turns:
            v.cmd('x')
            r = v.cmd('r').splitlines()[1].split()
            pc, sw = int(r[0][2:], 16), int(r[-1])
            if pc == lab['loop']:
                t0 = sw
            elif pc == lab['place']:
                tp = sw
            elif t0 is not None:
                works.append(sw - t0)
                matches.append(tp - t0 if tp else 0)
                t0 = tp = None
        state = b''.join(bytes(v.mem(lab[n], 23)) for n in
                         ('o_xl', 'o_xh', 'o_yl', 'o_yh', 'o_zl', 'o_dir'))
        state += bytes(v.mem(lab['score'], 2))
    finally:
        v.stop()
    w = works[10:]                     # (the kick-off's full builds left out)
    m = matches[10:]
    print('seed %d, %d turns: mean %d, most %d, over 95k %d, over 106k %d' % (
        seed, len(w), sum(w) / len(w), max(w), sum(x > 95000 for x in w),
        sum(x > 106000 for x in w)))
    print('  the match %d, the pictures %d (means)' % (sum(m) / len(m), (sum(w) - sum(m)) / len(w)))
    print('  state %s' % hashlib.md5(state).hexdigest()[:12])


if __name__ == '__main__':
    main()
