#!/usr/bin/env python3
"""yape_joylag.py [seconds] - how late Yape's joystick comes after the
gamepad: Yape (at its own speed, from the title on) writes each change of
what the machine reads from the joystick ports, with the time; meanwhile
SDL is asked for the controller directly, the same way, with the time.
Move the stick and press A once READY shows. The gamepad as run-yape.sh
sets it up."""
import os, re, subprocess, sys
sys.path.insert(0, os.path.dirname(__file__))
from yape import Yape
HERE = os.path.dirname(os.path.abspath(__file__))
secs = float(sys.argv[1]) if len(sys.argv) > 1 else 40
src = open(os.path.join(HERE, '..', 'run-yape.sh')).read()
IGNORE = re.search(r'IGNORE=\$\{YAPE_PAD_IGNORE-([^}]*)\}', src).group(1)
MAP = re.search(r'MAP=\$\{YAPE_PAD_MAP-"([^"]*)"\}', src).group(1)
PAD = ['SDL_GAMECONTROLLER_IGNORE_DEVICES=' + IGNORE, 'SDL_GAMECONTROLLERCONFIG=' + MAP]
lbl = {}
for l in open(os.path.join(HERE, '..', 'build', 'paradroid.lbl')):
    p = l.split()
    lbl[p[2].lstrip('.')] = int(p[1], 16)

y = Yape(os.path.join(HERE, '..', 'build', 'paradroid.prg'),
         env=PAD + ['SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1', 'YAPE_JOYLOG=1', 'YAPE_PADKEYS=off'])
pad = None
try:
    for t in range(240):                # (the program loads at the 1541's own speed)
        y.run_for(1)
        if y.mem(lbl['_font_hi'], 1)[0] == 0xD8:
            break
    y.poke(0x0000 + lbl['_dbg_keys'], [0])
    y.lines(1)
    pad = subprocess.Popen(['flatpak-spawn', '--host'] + ['--env=' + e for e in PAD] +
                           ['python3', os.path.expanduser('~/.cache/paradroid/pads/padlog.py'), str(secs)],
                           stdout=subprocess.PIPE, text=True)
    print('READY', flush=True)
    joy = [l for l in y.lines(secs) if l.startswith('JOY ')]
    pads = [l for l in pad.communicate()[0].splitlines() if l.startswith('PAD ')]
finally:
    y.stop()
    if pad and pad.poll() is None:
        pad.kill()

# Yape's byte: active low, bit 0 up, 1 down, 2 left, 3 right, 6/7 fire
def yv(b):
    b ^= 0xFF
    return (b & 15) | (16 if b & 0xC0 else 0)
J = [(float(l.split()[1]), yv(int(l.split()[2], 16))) for l in joy]
P = [(float(l.split()[1]), int(l.split()[2], 16)) for l in pads]
print('%d changes from SDL, %d in Yape' % (len(P), len(J)))
lags = []
for t, v in P:
    later = [tj for tj, vj in J if vj == v and tj >= t - 0.005]
    if later:
        lags.append(later[0] - t)
        print('%.3f  %02X  in Yape %+.0f ms' % (t, v, (later[0] - t) * 1000))
    else:
        print('%.3f  %02X  not in Yape' % (t, v))
if lags:
    lags.sort()
    print('lag: median %.0f ms, max %.0f ms' % (lags[len(lags) // 2] * 1000, lags[-1] * 1000))
