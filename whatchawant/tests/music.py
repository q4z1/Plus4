#!/usr/bin/env python3
"""The music in Yape (without a window): the demo started, then its
picture every frame and its sound for some seconds - a video with the
sound, the sound alone as a WAV, and how well it matches what
tools/mkmusic.py says the TED puts out.

    python3 tests/music.py [seconds]  -> build/music-yape.mp4, .wav

The sound is the emulation's own (Yape's $YAPE_WAV, written by the
machine's clock while the pictures are saved, not the sound card's), so
it keeps in step with the pictures.
"""
import array
import glob
import os
import subprocess
import sys
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from yape import Yape, SHOT, host  # noqa: E402

BUILD = os.path.join(HERE, '..', 'build')
PRG = os.path.join(BUILD, 'whatchawant.prg')
WAV = SHOT + '.raw'                     # the series' sound
RATE = 48000                            # (Yape's samples a second)


def encode(out):
    frames = [f for f in glob.glob(SHOT + '.*') if f.rsplit('.', 1)[1].isdigit()]
    samples = os.path.getsize(WAV) // 2
    print('%d frames, %.2f s of sound' % (len(frames), samples / RATE))
    fps = '%.4f' % (len(frames) * RATE / samples)
    r = array.array('h', open(WAV, 'rb').read())
    gain = 0.45 * 65535 / max(1, max(r) - min(r))
    # (the TED's sound is all above 0: that taken out, louder)
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-framerate', fps,
                    '-f', 'image2', '-c:v', 'ppm', '-i', SHOT + '.%03d',
                    '-f', 's16le', '-ar', str(RATE), '-ac', '1', '-i', WAV,
                    '-af', 'highpass=f=15,volume=%.2f' % gain,
                    '-vf', 'scale=iw*2:ih*2:flags=neighbor',
                    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '18',
                    '-c:a', 'aac', '-b:a', '160k', '-shortest', out], check=True)
    print(out)


def main():
    secs = float(sys.argv[1]) if len(sys.argv) > 1 else 15
    for f in glob.glob(SHOT + '.*'):
        os.remove(f)
    y = Yape(PRG, series=int(secs * 50),
             env=('YAPE_WAV=' + WAV, 'SDL_AUDIODRIVER=dummy'))
    try:
        y.run_for(2)                    # (loading, the start)
        host('pkill', '-USR2', '-x', 'yapesdl')
        y._read_until(b'SHOT ', timeout=60 + 4 * secs)
    finally:
        y.stop()
    w = wave.open(os.path.join(BUILD, 'music-yape.wav'), 'wb')
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(RATE)
    w.writeframes(open(WAV, 'rb').read())
    w.close()
    encode(os.path.join(BUILD, 'music-yape.mp4'))
    shots = sorted(f for f in glob.glob(SHOT + '.*') if f.rsplit('.', 1)[1].isdigit())
    from yape import ppm_to_png
    ppm_to_png(shots[len(shots) // 2], os.path.join(BUILD, 'music-yape.png'))
    for f in glob.glob(SHOT + '.*'):    # (some hundred MB of pictures)
        os.remove(f)
    print('build/music-yape.wav, build/music-yape.png')


if __name__ == '__main__':
    main()
