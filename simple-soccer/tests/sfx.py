#!/usr/bin/env python3
"""The match's sounds to listen to: each effect of sound.s put on its
voices (as sfx_* would) while the first kick-off waits - quiet otherwise -
VICE's sound into build/sfx.wav, a second between them. And each one's
loudness a tenth of a second at a time, as a line of digits (0 - 9) -
the frames run may run on a little, so the lines' starts drift.

    tests/sfx.py [name ...]    (default: all; names as in EFFECTS)
"""
import array
import os
import sys
import wave

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import PRG, WORK, HERE, labels, held_from_start, run_pictures  # noqa: E402

# name: (voice 0's table, voice 1's, the crowd's on voice 1, frames)
EFFECTS = {
    'kick':    (None, 'fx_kick', 0, 10),
    'whistle': ('fx_whistle', None, 0, 20),
    'goal':    ('fx_goal_w', 'fx_goal', 1, 150),
    'save':    (None, 'fx_save', 1, 60),
    'miss':    (None, 'fx_ooh', 1, 60),
    'yellow':  ('fx_whistle', 'fx_yellow', 1, 75),
    'red':     ('fx_red_w', 'fx_red', 1, 150),
}
GAP = 50
WAV = os.path.join(HERE, 'build', 'sfx.wav')


def main():
    names = sys.argv[1:] or list(EFFECTS)
    lab = labels()
    raw = os.path.join(WORK, 'sfx-raw.wav')
    v = Vice(PRG, WORK, warp=False, wav=raw)
    marks = []
    try:
        held_from_start(v, lab, 'none')
        run_pictures(v, lab, 100)               # (the kick-off waits)
        for n in names:
            v0, v1, crowd, frames = EFFECTS[n]
            marks.append((n, frames))
            v.poke(lab['v_crowd'], [crowd])
            for y, t in ((0, v0), (1, v1)):
                if t:
                    v.poke(lab['v_lo'] + y, [lab[t] & 255])
                    v.poke(lab['v_hi'] + y, [lab[t] >> 8])
                    v.poke(lab['v_ext'] + y, [0])
                    v.poke(lab['v_lo'] + 4 + y, [1])     # (v_left: the title's too)
            run_pictures(v, lab, frames + GAP)
    finally:
        v.stop()
    w = wave.open(raw)
    rate, ch = w.getframerate(), w.getnchannels()
    data = array.array('h', w.readframes(w.getnframes()))
    w.close()
    if ch > 1:
        data = data[::ch]
    os.replace(raw, WAV)
    print('%s: %.1f s, %d Hz' % (WAV, len(data) / rate, rate))
    # the loudness each tenth of a second, a line each effect from where
    # it should start (the pictures run may run on a little)
    step = rate // 10
    loud = []
    for k in range(0, len(data), step):
        part = data[k:k + step]
        rms = (sum(x * x for x in part) / max(1, len(part))) ** 0.5
        loud.append(str(min(9, int(rms / 1500))))
    t = 100
    for n, frames in marks:
        i = t * 10 // 50
        print('%-8s %s' % (n, ''.join(loud[i:i + (frames + GAP) * 10 // 50])))
        t += frames + GAP


if __name__ == '__main__':
    sys.exit(main())
