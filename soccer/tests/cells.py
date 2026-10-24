#!/usr/bin/env python3
"""What building a picture's cells costs: cycles of each call of cells
(or of another routine eng_begin calls, shift say)
(VICE's stopwatch, the interrupt included), and the characters it had to
copy into the picture's set on the way (alloc) and whether it emptied
the cache first (flush).

    tests/cells.py [dir] [calls] [routine]   dir as in shot.py, held throughout
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, BITS, labels, run_pictures  # noqa: E402


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else 'right+fire'
    calls = int(sys.argv[2]) if len(sys.argv) > 2 else 12
    fn = sys.argv[3] if len(sys.argv) > 3 else 'cells'
    lab = labels()
    v = Vice(PRG, WORK)
    try:
        for _ in range(200):
            v.run_for(0.1)
            if lab['main'] <= int(v.cmd('r').splitlines()[1].split()[0][2:], 16) < 0xC000:
                break
        run_pictures(v, lab, 20)
        bits = 0
        for p in d.split('+'):
            bits |= BITS[p]
        v.poke(lab['dbg_joy'], [bits])
        run_pictures(v, lab, 20)
        # cells' return: the rts after its loop - a breakpoint on the
        # caller's next instruction instead
        code = v.mem(lab['eng_begin'], 400)
        c = lab[fn]
        ret = [lab['eng_begin'] + i + 3 for i in range(len(code) - 2)
               if code[i] == 0x20 and code[i + 1] == c & 255 and code[i + 2] == c >> 8][0]
        for a in (c, ret, lab['alloc'], lab['flush']):
            v.cmd('break %04x' % a)
        start = n_alloc = flushed = 0
        done = 0
        tot = 0
        while done < calls:
            v.cmd('x')
            r = v.cmd('r').splitlines()[1].split()
            pc, sw = int(r[0][2:], 16), int(r[-1])
            if pc == c:
                start, n_alloc, flushed = sw, 0, 0
            elif pc == lab['alloc']:
                n_alloc += 1
            elif pc == lab['flush']:
                flushed = 1
            elif start:
                print(fn + ': %6d cycles, %2d characters copied%s'
                      % (sw - start, n_alloc, ', flushed' if flushed else ''))
                tot += sw - start
                done += 1
        print('average %d' % (tot / calls))
    finally:
        v.stop()


if __name__ == '__main__':
    main()
