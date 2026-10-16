#!/usr/bin/env python3
"""drawcost.py root [seconds] [map] - what drawing the trains costs.

The build in root (a checkout of this folder, built) runs as in trace.py:
the loop's step fixed to one picture, the autopilot on, x10, into the map
(the last one open, or map steps down the list, up if below 0). After 30
seconds of the game's time (or more), for that many more from the next
draw on, every call of trains_draw from the main loop is timed, and each call of eng_tcell in it
(a cell of a train). Prints the cycles in all, per draw, per cell, and how
many pictures' worth that is (35568 cycles a picture, VICE's count).
"""
import os
import re
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402

root = sys.argv[1]
SECS = int(sys.argv[2]) if len(sys.argv) > 2 else 60
CHOOSE = int(sys.argv[3]) if len(sys.argv) > 3 else 0
WORK = os.path.expanduser('~/.cache/trainschedule/drawcost')
PICTURE = 35568


def labels(path):
    lbl = {}
    for line in open(path):
        p = line.split()
        if len(p) == 3 and p[0] == 'al':
            lbl.setdefault(p[2].lstrip('.'), int(p[1], 16))
    for n in list(lbl):
        if not n.startswith('_'):
            lbl.setdefault('_' + n, lbl[n])
    return lbl


L = labels(os.path.join(root, 'build', 'trainschedule.lbl'))
os.makedirs(WORK, exist_ok=True)
disk = os.path.join(WORK, 'drawcost.d64')
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
    done, last = 0, byte('_frames')
    while done < n:
        v.run_for(0.05)
        now = byte('_frames')
        done += (now - last) & 255
        last = now


def tap():
    v.poke(L['_dbg_keys'], [16])
    frames(4)
    v.poke(L['_dbg_keys'], [0])
    frames(4)


def clock():
    lo, hi = v.mem(L['_clock_s'], 2)
    return lo | hi << 8


def step():
    """on to the next breakpoint: its address and the cycle count"""
    v.sock.sendall(b'x\n')
    out = v._read_prompt()
    m = re.findall(r'\.C:([0-9a-f]{4}).*?(\d+)\s*\n', out)
    return int(m[-1][0], 16), int(m[-1][1])


try:
    wait_for('_eng_mode', 1)
    frames(10)
    v.poke(L['_dbg_n'], [1])
    v.poke(L['_autopilot_on'], [1])
    v.poke(L['_speed_i'], [3])
    v.poke(L['_unlocked'], [0xFF])
    tap()
    wait_for('_eng_mode', 2)
    frames(20)
    for _ in range(abs(CHOOSE)):
        v.poke(L['hits'], [2 if CHOOSE > 0 else 1])
        frames(5)
    tap()
    wait_for('_ptr_on', 0)
    while clock() < 30:
        v.run_for(0.2)
    # the call in the main loop
    td = L['trains_draw']
    dis = v.cmd(f"d {L['_main']:04x} {L['_main'] + 0x900:04x}")
    sites = [int(m.group(1), 16) for m in re.finditer(
        r'\.C:([0-9a-f]{4})\s+20 ([0-9A-F]{2}) ([0-9A-F]{2})\s+JSR', dis)
        if int(m.group(3) + m.group(2), 16) == td]
    site = sites[-1]
    # and the call of eng_tcell in it
    tcell = L['_eng_tcell']
    dis = v.cmd(f"d {td:04x} {td + 0x400:04x}")
    tsite = [int(m.group(1), 16) for m in re.finditer(
        r'\.C:([0-9a-f]{4})\s+20 ([0-9A-F]{2}) ([0-9A-F]{2})\s+JSR', dis)
        if int(m.group(3) + m.group(2), 16) == tcell][0]
    for a in (site, site + 3, tsite, tsite + 3):
        v.cmd(f'break {a:04x}')
    v.settle = 0.01
    end = None
    calls = cells = total = intcell = 0
    worst = 0
    start = tstart = None
    while True:
        a, clk = step()
        if a == site:
            if end is None:             # (from the first draw on)
                end = clock() + SECS
            elif clock() >= end:
                break
            start = clk
            calls += 1
        elif a == tsite:
            cells += 1
            tstart = clk
        elif a == tsite + 3 and tstart is not None:
            intcell += clk - tstart
            tstart = None
        elif a == site + 3 and start is not None:
            total += clk - start
            worst = max(worst, clk - start)
            start = None
    v.cmd('delete')
finally:
    v.stop()
print(f'{SECS} s of the game: {calls} draws, {cells} cells, {total} cycles '
      f'({total / PICTURE:.0f} pictures)')
if calls:
    print(f'  a draw {total // calls} cycles ({total / calls / PICTURE:.2f} '
          f'pictures), the worst {worst} ({worst / PICTURE:.2f})')
if cells:
    print(f'  {intcell} of them in eng_tcell: {intcell // cells} a cell; '
          f'the rest {(total - intcell) // calls} a draw')
