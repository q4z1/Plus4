#!/usr/bin/env python3
"""sidmusic.py Paradroid.sid - the title's sound, from the original, into
data/music.txt.

The SID is the original's own sound driver, ripped in the state the title
leaves it in (in x64sc the title shows the same registers): voice 1 a
falling sweep, a new pitch every picture; voice 2 a low triangle that
wavers down and up, then rests; voice 3 noise, which the original switches
off ($D418 bit 7) and only uses for random numbers. So two voices, as the
TED has: voice 1 here is the sweep, voice 2 the wavering one.

The driver is run (tools/sid.py) for one round of its loop, 128 pictures,
and each voice written as its pitch in hertz per picture, the same pitch on
following pictures joined, a gate that is off a rest. The pitches are not
notes of a scale - the driver adds to its frequency registers - so they
stay hertz, which tools/mkdata.py turns into the TED's registers.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from sid import record                                  # noqa: E402

LOOP = 128              # the driver's state repeats after this many pictures
SKIP = 128              # its first round: voice 2 only comes in later
SID_CLOCK = 985248      # PAL


def voice(frames, v):
    out = []
    for r in frames:
        f = (r[v * 7] | r[v * 7 + 1] << 8) * SID_CLOCK / 16777216
        on = r[v * 7 + 4] & 1 and f >= 20
        hz = round(f) if on else 0
        if out and out[-1][0] == hz:
            out[-1][1] += 1
        else:
            out.append([hz, 1])
    return out


def line(entries):
    toks, last = [], None
    for hz, n in entries:
        t = 'r' if hz == 0 else str(hz)
        if n != last:
            t += ':%d' % n
            last = n
        toks.append(t)
    return toks


def main():
    fr = record(sys.argv[1], SKIP + 2 * LOOP)
    key = [tuple(r) for r in fr]
    assert key[SKIP:SKIP + LOOP] == key[SKIP + LOOP:SKIP + 2 * LOOP], 'no loop'
    fr = fr[SKIP:SKIP + LOOP]
    out = os.path.join(os.path.dirname(__file__), '..', 'data', 'music.txt')
    t = ['# The title\'s sound, from the original: made by tools/sidmusic.py from',
         '# its own sound driver (Paradroid.sid, PAL), one round of its loop.',
         '#',
         '#   v1 / v2 HZ[:LEN] ...  the pitch in hertz, r a rest; LEN in pictures',
         '#                         (50ths of a second), the last one given if',
         '#                         left out. The voices loop.',
         '#',
         '# Voice 1 is the original\'s falling sweep, voice 2 its wavering low',
         '# triangle. Its third voice, noise, is switched off in the original.',
         '']
    for v, name in ((0, 'v1'), (1, 'v2')):
        toks = line(voice(fr, v))
        for k in range(0, len(toks), 12):
            t.append(name + ' ' + ' '.join(toks[k:k + 12]))
    open(out, 'w').write('\n'.join(t) + '\n')
    print(out)


if __name__ == '__main__':
    main()
