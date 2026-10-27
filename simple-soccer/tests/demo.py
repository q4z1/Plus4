"""A demo video of Simple Soccer in Yape, from the disk: the title with its
whole song and past its loop, the teams chosen (Germany against Brazil),
one player, a minute of the match - build/simple-soccer-demo.mp4, with
its sound.

    tests/demo.py

The pictures and the sound are Yape's own, frame by frame (yape.py,
video.py); the stick is moved through dbg_joy. Choosing the home team
passes the away team's by (Brazil): 13 steps right from Argentina are
Germany."""
import glob
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from yape import Yape, SHOT, host
from shot import labels, BITS
import video

lab = labels()
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'build', 'simple-soccer-demo.mp4')
TITLE_SECS = 41
MATCH_PLAN = [
    ('none', 1.5), ('fire', 0.1), ('none', 0.8), ('up', 2.5), ('up+right', 1.0), ('fire', 0.1),
    ('none', 1.0), ('up', 2.0), ('fire', 0.5), ('none', 2.5), ('down', 2.0), ('down+left', 1.5),
    ('fire', 0.1), ('up', 3.0), ('up+left', 1.0), ('fire', 0.5), ('none', 3.0), ('fire', 0.1),
    ('none', 1.5), ('right', 2.0), ('up', 2.0), ('fire', 0.1), ('none', 1.0), ('up', 2.5),
    ('fire', 0.5), ('none', 3.0), ('left', 1.5), ('down', 2.0), ('fire', 0.1), ('up', 2.0),
    ('up+right', 1.5), ('fire', 0.5), ('none', 3.0), ('fire', 0.1), ('none', 2.0), ('up', 3.0),
    ('fire', 0.1), ('none', 1.0), ('up', 2.0), ('fire', 0.5), ('none', 2.0)]
FRAMES = int((TITLE_SECS + 9 + sum(s for _, s in MATCH_PLAN) + 2) * 50)


def stick(d):
    bits = 0
    for p in d.split('+'):
        bits |= BITS.get(p, 0)
    y.poke(lab['dbg_joy'], [bits])


def press(d, hold=0.15, gap=0.25):
    stick(d)
    time.sleep(hold)
    stick('none')
    time.sleep(gap)


for f in glob.glob(SHOT + '.*'):
    os.remove(f)
y = Yape(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'build', 'simple-soccer.d64'), series=FRAMES, title=True,
         env=('YAPE_WAV=' + video.WAV, 'SDL_AUDIODRIVER=dummy'))
try:
    t0 = time.time()
    while time.time() - t0 < 180:           # loading: till the title is on
        time.sleep(1)
        if y.mem(0xfffe, 2)[1] == 0 and y.mem(0xff06, 1)[0] == 0x1b:
            break
    print('title after %d s' % (time.time() - t0))
    host('pkill', '-USR2', '-x', 'yapesdl')  # the pictures and the sound from here
    time.sleep(TITLE_SECS)
    press('down')
    press('down')                           # the home team: on to Germany
    for _ in range(13):                     # (Brazil, the away team's, passed by)
        press('right')
    press('down')                           # the away team: Brazil, as it is
    time.sleep(1.0)
    press('fire', 0.2, 0.5)
    for d, secs in MATCH_PLAN:
        stick(d)
        time.sleep(secs)
    stick('none')
    # the series' end: all its pictures written (not Yape's "SHOT" line -
    # reading for it blocked for good once the series was over)
    t0 = time.time()
    while len(glob.glob(SHOT + '.[0-9]*')) < FRAMES and time.time() - t0 < 300:
        time.sleep(1)
    time.sleep(2)
finally:
    y.stop()
print('%d frames' % len(glob.glob(SHOT + '.[0-9]*')))
video.encode(OUT)
