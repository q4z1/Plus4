#!/usr/bin/env python3
"""The title's music in VICE: the title left up for some seconds (no warp:
VICE writes no sound in warp), its sound into a WAV, a screenshot; then
fire, and the match must come up and play on. With --yape: in Yape, a
video of the title's first 20 seconds with its sound.

    python3 tests/title_music.py [seconds]   -> build/title-vice.wav, .png
    python3 tests/title_music.py --yape      -> build/title-yape.mp4, .wav
"""
import os
import sys
import time
import wave
from vice import Vice

HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.path.join(HERE, '..', 'build')
CACHE = os.path.expanduser('~/.cache/simple-soccer')


if '--yape' in sys.argv:
    import glob
    from yape import Yape, SHOT, host
    import video
    for f in glob.glob(SHOT + '.*'):
        os.remove(f)
    y = Yape(os.path.join(BUILD, 'simple-soccer.prg'), series=999, title=True,
             env=('YAPE_WAV=' + video.WAV, 'SDL_AUDIODRIVER=dummy'))
    try:
        y.run_for(4)                    # (loading)
        host('pkill', '-USR2', '-x', 'yapesdl')
        y._read_until(b'SHOT ', timeout=120)
    finally:
        y.stop()
    w = wave.open(os.path.join(BUILD, 'title-yape.wav'), 'wb')
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(video.RATE)
    w.writeframes(open(video.WAV, 'rb').read())
    w.close()
    video.encode(os.path.join(BUILD, 'title-yape.mp4'))
    sys.exit()

secs = float(sys.argv[1]) if len(sys.argv) > 1 else 20
os.makedirs(CACHE, exist_ok=True)
wav = os.path.join(CACHE, 'title-vice.wav')
v = Vice(os.path.join(BUILD, 'simple-soccer.prg'), CACHE, warp=False, wav=wav, title=True)
try:
    v.run_for(4 + secs)              # (the load: some 3 seconds)
    v.screenshot(os.path.join(CACHE, 'title-vice.png'))
    print('TED:', v.cmd('io ff00').splitlines()[1:3])
    print('regs:', v.cmd('r').strip().splitlines()[-2])
    v.poke(0x0FF8, [0x54, 0x53])     # "TS": the title ends as if fire were
    v.run_for(3)                     # pressed (title.s: skip)
    v.screenshot(os.path.join(CACHE, 'match-vice.png'))
    print('TED:', v.cmd('io ff00').splitlines()[1:3])
    v.sock.sendall(b'quit\n')        # (the WAV closed properly)
    time.sleep(2)
finally:
    v.stop()
os.replace(wav, os.path.join(BUILD, 'title-vice.wav'))
for f in ('title-vice.png', 'match-vice.png'):
    os.replace(os.path.join(CACHE, f), os.path.join(BUILD, f))
print('build/title-vice.wav, build/title-vice.png, build/match-vice.png')
