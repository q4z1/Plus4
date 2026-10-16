#!/usr/bin/env python3
"""A song from data/music.txt as a .wav, to hear it without the game.

    song2wav.py <music.txt> <song> <out.wav> [--loops N]

Plays the bytes tools/mkmusic.py makes of it, patterns and all, as
music.inc does: a picture at a time (50 a second), each note from the
song's own table of the TED's frequency register, silent GATE pictures
before its end (half its length if staccato; never if it is no longer
than GATE); two squares at the song's volume. N times through (default 1).
"""
import struct
import sys
import wave

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import mkmusic                                          # noqa: E402

RATE = 44100
FPS = 17734470 / 20 / (312 * 57)                         # PAL pictures a second
GATE = 2


def frames(notes, data, org):
    """per picture the frequency sounding, or 0"""
    lo, hi = (data[2] | data[3] << 8) - org, (data[4] | data[5] << 8) - org
    out = []
    for n, lb in notes:
        length, gate = lb & 0x7F, (lb & 0x7F) >> 1 if lb & 0x80 else GATE
        hz = mkmusic.TED_HZ / (1024 - (data[lo + n] | (data[hi + n] & 3) << 8)) if n else 0
        for left in range(length, 0, -1):
            # the player: on when read, off when the frames left reach gate
            out.append(hz if left > gate or gate >= length else 0)
    return out


def main():
    path, name, out = sys.argv[1:4]
    loops = int(sys.argv[sys.argv.index('--loops') + 1]) if '--loops' in sys.argv else 1
    org = 0xB000
    data, _ = mkmusic.build(path, name, org)
    voices = [frames(v, data, org) * loops for v in mkmusic.unpack(data, org)]
    n = max(len(v) for v in voices)
    amp = 3000 * data[1] / 8
    per = RATE / FPS
    samples = []
    phase = [0.0, 0.0]
    for f in range(n):
        for s in range(int((f + 1) * per) - int(f * per)):
            mix = 0.0
            for k, v in enumerate(voices):
                hz = v[f] if f < len(v) else 0
                if hz:
                    phase[k] = (phase[k] + hz / RATE) % 1.0
                    mix += amp if phase[k] < 0.5 else -amp
            samples.append(int(mix))
    with wave.open(out, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(struct.pack(f'<{len(samples)}h', *samples))
    print(f'{out}: {name}, {n / FPS:.1f} s')


if __name__ == '__main__':
    main()
