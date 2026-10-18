#!/usr/bin/env python3
"""trace.py root out [seconds] [map] [scene] - the game's memory second by second,
to compare two builds (a rewrite against what it replaces, tracecmp.py).

The build in root (a checkout of this folder, built) is started from its
disk in VICE; at the title the loop's step is fixed to one picture
(_dbg_n: the game then runs the same whatever its speed), the autopilot
switched on and the speed set to x10; then into the map (the last one
open, or map steps down the list from it, up if map is below 0). At the
start of every trains_second() - once a second of the game's time -
memory $0400-$FCFF is saved to out/NNNN.bin, with the labels as
out/labels. Ends when the timetable is
through, or after that many seconds.

scene "auto" (the default): the autopilot alone. "play": the autopilot,
and the player too - signals and where their routes go chosen, routes
taken back, the other size, the trains' timetables paged through, the
view scrolled, trains pointed at, the speed changed: first a fixed list,
then at random (seeded), one thing every few seconds.
"""
import os
import random
import shutil
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402

root, out = sys.argv[1], os.path.abspath(sys.argv[2])
SECS = int(sys.argv[3]) if len(sys.argv) > 3 else 2000
CHOOSE = int(sys.argv[4]) if len(sys.argv) > 4 else 0
SCENE = sys.argv[5] if len(sys.argv) > 5 else 'auto'
WORK = os.path.expanduser('~/.cache/trainschedule/trace')


def labels(path):
    lbl = {}
    for line in open(path):
        p = line.split()
        if len(p) == 3 and p[0] == 'al':
            lbl.setdefault(p[2].lstrip('.'), int(p[1], 16))
    for n in list(lbl):                 # (C's names, or assembly's own)
        if not n.startswith('_'):
            lbl.setdefault('_' + n, lbl[n])
    return lbl


shutil.rmtree(out, ignore_errors=True)
os.makedirs(out)
shutil.copy(os.path.join(root, 'build', 'trainschedule.lbl'),
            os.path.join(out, 'labels'))
L = labels(os.path.join(out, 'labels'))
os.makedirs(WORK, exist_ok=True)
disk = os.path.join(WORK, 'trace.d64')
shutil.copy(os.path.join(root, 'build', 'trainschedule.d64'), disk)

v = Vice(disk, WORK, drive=1541)


def byte(name):
    return v.mem(L[name], 1)[0]


def wait_for(name, value, limit=600):
    for _ in range(limit):
        if byte(name) == value:
            return
        v.run_for(0.2)
    raise RuntimeError(f'{name} never became {value}')


def frames(n):
    """let n pictures go by"""
    done, last = 0, byte('_frames')
    while done < n:
        v.run_for(0.05)
        now = byte('_frames')
        done += (now - last) & 255
        last = now


def tap(bits=16):
    v.poke(L['_dbg_keys'], [bits])
    frames(4)
    v.poke(L['_dbg_keys'], [0])
    frames(4)


def mem(name, n):
    return v.mem(L[name], n)


def point(x, y):
    """the pointer's tip to the middle of map cell x, y (the game follows
    it in its next turn)"""
    z = byte('_zoom')
    px, py = (x * 8 + 4) * z, (y * 8 + 4) * z
    v.poke(L['_ptr_x'], [px & 255, px >> 8])
    v.poke(L['_ptr_y'], [py & 255, py >> 8])


def train_cell():
    w, h = byte('_map_w'), byte('_map_h')
    occ = v.mem(0xD000, w * h)
    for i, o in enumerate(occ):
        if o & 0x80:
            return i % w, i // w
    return None


def act(what, rnd):
    """one thing the player does"""
    if what == 'sig':
        n = byte('_nsig')
        if n:
            i = rnd.randrange(n)
            point(mem('_sig_x', n)[i], mem('_sig_y', n)[i])
    elif what == 'sel':
        n = byte('_sel_n')
        if n:
            i = rnd.randrange(n)
            point(mem('_sel_x', n)[i], mem('_sel_y', n)[i])
    elif what == 'train':
        c = train_cell()
        if c:
            point(*c)
    elif what == 'cell':
        point(rnd.randrange(byte('_map_w')), rnd.randrange(byte('_map_h')))
    elif what == 'edge':
        z = byte('_zoom')
        x = rnd.choice((2, byte('_map_w') * 8 * z - 3))
        y = rnd.randrange(byte('_map_h') * 8 * z)
        v.poke(L['_ptr_x'], [x & 255, x >> 8])
        v.poke(L['_ptr_y'], [y & 255, y >> 8])
    elif what == 'fire':
        v.poke(L['hits'], [16])
    elif what in ('slow', 'fast'):
        v.poke(L['hits'], [64 if what == 'slow' else 32])
    else:                               # the second key byte: Z 1, , 2,
        v.poke(L['hits2'], [int(what)]) # . 4, Esc 8, fire with up 16,
                                        # down 32, left 64, right 128


PLAN = {3: 'sig', 4: 'fire', 6: 'sel', 7: 'fire', 9: 'sig', 10: 'fire',
        12: '1', 14: 'sig', 15: 'fire', 17: 'sel', 18: 'fire', 20: '32',
        22: '32', 24: '2', 26: '8', 28: '1', 30: 'edge', 33: 'edge',
        40: 'train', 41: 'fire', 44: 'cell', 45: 'fire', 50: 'slow',
        52: 'fast', 55: '4', 57: '16', 60: '128', 62: '64', 64: '8'}
CHOICES = ['sig', 'fire', 'sel', 'fire', 'sig', 'fire', 'train', 'fire',
           'cell', 'fire', 'edge', '1', '32', '2', '4', '8', 'slow', 'fast',
           'route', 'route', 'route', 'back']
# what takes a few seconds: a route set (a signal, fire, where to, fire),
# and a signal fired at twice (a route set from it taken back)
MACROS = {'route': ['sig', 'fire', 'sel', 'fire'],
          'back': ['sig', 'fire', 'fire', 'fire']}

try:
    wait_for('_eng_mode', 1)                # the title
    frames(10)
    v.poke(L['_dbg_n'], [1])
    v.poke(L['_autopilot_on'], [1])
    v.poke(L['_speed_i'], [3])
    v.poke(L['_unlocked'], [0xFF])          # every map open
    tap()
    wait_for('_eng_mode', 2)                # the choice of a map
    frames(20)
    for _ in range(abs(CHOOSE)):            # (down, or up if < 0: the
        v.poke(L['hits'], [2 if CHOOSE > 0 else 1])  # last map open is
        frames(5)                           # chosen first)
    v.cmd('break %04x' % L['_trains_second'])
    tap()
    n = 0
    last = None
    rnd = random.Random(7)
    queue = []
    again = False
    v.settle = 0.01
    while n < SECS:
        v.sock.settimeout(60)
        v.sock.sendall(b'x\n')
        try:
            r = v._read_prompt()
        except (TimeoutError, OSError):     # no more seconds: the end
            if again:
                break
            # the end's page saved, then left, right (the choice there),
            # fire: the level again, a while of it
            again = True
            v.sock.settimeout(30)
            v.cmd('r')
            v.cmd(f'bsave "{out}/{n:04d}.bin" 0 0400 fcff')
            n += 1
            for bits in (4, 8):
                v.poke(L['hits'], [bits])
                v.run_for(0.5)
            v.poke(L['hits'], [16])         # (on to the next break)
            SECS = min(SECS, n + 60)
            last = None
            continue
        if '%04x' % L['_trains_second'] not in r.lower():
            continue
        c = v.mem(L['_clock_s'], 2)         # (a loop in it may start at
        if c == last:                       # its first instruction)
            continue
        last = c
        v.cmd(f'bsave "{out}/{n:04d}.bin" 0 0400 fcff')
        if SCENE == 'play':
            if n in PLAN:
                act(PLAN[n], rnd)
            elif queue:
                act(queue.pop(0), rnd)
            elif 70 < n < 600 and n % 4 == 0:
                what = rnd.choice(CHOICES)
                if what in MACROS:
                    queue = MACROS[what][1:]
                    what = MACROS[what][0]
                act(what, rnd)
            if byte('_speed_i') < 2:        # (not too slow: the end)
                v.poke(L['_speed_i'], [3])
        n += 1
    print(f'{n} seconds traced')
finally:
    v.stop()
