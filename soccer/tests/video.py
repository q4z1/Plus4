#!/usr/bin/env python3
"""A video of the game as Yape shows it, every frame (50 a second), with
the joystick moved to a plan: build/soccer.mp4.

    tests/video.py [out.mp4]

Yape (without a window) saves each frame's picture while the plan runs:
directions held for so many seconds, through dbg_joy (Yape stops for a
moment each time, the pictures go on where they were). ffmpeg makes the
video, twice the size, sharp pixels.
"""
import glob
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from yape import Yape, SHOT, host  # noqa: E402
from shot import HERE, PRG, BITS, labels  # noqa: E402

FRAMES = 1500
# (direction, seconds): the kick-off passed on, a run up and a pass to the
# left, the other team going after the ball, chasing it back, a shot, and
# whatever restarts follow - fire now and then to take them
PLAN = [('none', 1.0), ('fire', 0.1), ('none', 0.4), ('up', 1.5), ('up+left', 0.6),
        ('left+fire', 0.1), ('none', 1.5), ('down', 2.5), ('down+left', 1.5),
        ('up+fire', 0.3), ('none', 2.5), ('right', 1.5), ('fire', 0.1), ('none', 2.0),
        ('left', 1.5), ('fire', 0.1), ('none', 3.0), ('fire', 0.1), ('none', 3.0)]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    out = args[0] if args else os.path.join(HERE, 'build', 'soccer.mp4')
    lab = labels()
    if '--again' in sys.argv:           # (the pictures of the last run)
        return encode(out)
    for f in glob.glob(SHOT + '.*'):
        os.remove(f)
    y = Yape(PRG, series=FRAMES)
    try:
        y.run_for(4)                    # loading and the start
        host('pkill', '-USR2', '-x', 'yapesdl')
        for d, secs in PLAN:
            bits = 0
            for p in d.split('+'):
                bits |= BITS.get(p, 0)
            y.poke(lab['dbg_joy'], [bits])
            time.sleep(secs)
        y.poke(lab['dbg_joy'], [0])
        y._read_until(b'SHOT ', timeout=120)
    finally:
        y.stop()
    encode(out)


def encode(out):
    frames = [f for f in glob.glob(SHOT + '.*') if f.rsplit('.', 1)[1].isdigit()]
    print('%d frames' % len(frames))
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-framerate', '50',
                    '-f', 'image2', '-c:v', 'ppm', '-i', SHOT + '.%03d', '-vf', 'scale=iw*2:ih*2:flags=neighbor',
                    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '18', out],
                   check=True)
    print(out)


if __name__ == '__main__':
    main()
