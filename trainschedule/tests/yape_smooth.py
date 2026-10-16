#!/usr/bin/env python3
"""yape_smooth.py root [speed] [pictures] [from] - how smoothly the trains move,
picture by picture, in Yape (whose TED leaves the CPU less time than
VICE's).

The test build in root (a checkout of this folder: build.sh with
TEST_MAP=1, build/trainschedule-test.d64, straight into Riesa) is
started, the autopilot switched on and the game run at x10 till that
second of the game (default 330: 09:05:30, trains coming into Riesa and
leaving it, in the view); then at speed 0-3 (default 2: x3) - and with
NOPILOT=1 in the environment the autopilot off again - that many
pictures in a row are saved (Yape's YAPE_SHOTN, one a frame) and in each
the trains found: their pixels (yellow, Riesa's trains being commuter
trains), one train each where they are near one another. A train is
followed from picture to picture by where its middle is; how far that
moves each picture is what the eye sees. Prints, per train in sight
throughout: in how many pictures it moved, by how much, and the longest
run of pictures it stood still in between. Run from trainschedule/.
"""
import glob
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from yape import Yape, SHOT  # noqa: E402

root = sys.argv[1]
SPEED = int(sys.argv[2]) if len(sys.argv) > 2 else 2
N = int(sys.argv[3]) if len(sys.argv) > 3 else 150
FROM = int(sys.argv[4]) if len(sys.argv) > 4 else 330
NEAR = 5                # pixels this close are one train (over its gaps)


def labels():
    out = {}
    for line in open(os.path.join(root, 'build', 'trainschedule.lbl')):
        p = line.split()
        if len(p) == 3:
            out.setdefault(p[2].lstrip('.'), int(p[1], 16))
    for n in list(out):
        if not n.startswith('_'):
            out.setdefault('_' + n, out[n])
    return out


def trains(path):
    """the trains in a picture: the middle of each (x, y), its pixels"""
    im = Image.open(path).convert('RGB')
    w, h = im.size
    px = im.load()
    pts = [(x, y) for y in range(h) for x in range(w)
           if px[x, y][0] > 200 and px[x, y][1] > 200 and px[x, y][2] < 200]
    # one train: pixels joined by others no further than NEAR apart
    grid = {}
    for p in pts:
        grid.setdefault((p[0] // NEAR, p[1] // NEAR), []).append(p)
    seen = set()
    out = []
    for p in pts:
        if p in seen:
            continue
        seen.add(p)
        todo, blob = [p], []
        while todo:
            q = todo.pop()
            blob.append(q)
            gx, gy = q[0] // NEAR, q[1] // NEAR
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    for r in grid.get((gx + dx, gy + dy), ()):
                        if r not in seen and abs(r[0] - q[0]) <= NEAR \
                                and abs(r[1] - q[1]) <= NEAR:
                            seen.add(r)
                            todo.append(r)
        if len(blob) >= 8:
            out.append((sum(b[0] for b in blob) / len(blob),
                        sum(b[1] for b in blob) / len(blob), len(blob)))
    return out


L = labels()
y = Yape(os.path.join(root, 'build', 'trainschedule-test.d64'), series=N)
try:
    for _ in range(150):                # the level running: its name
        if y.mem(L['_lv_name'], 5) == [18, 9, 5, 19, 1] \
                and y.mem(L['_ptr_on'], 1)[0] == 1:  # (RIESA)
            break
        y.run_for(1)
    else:
        raise RuntimeError('Riesa never started')
    y.poke(L['_autopilot_on'], [1])
    y.poke(L['_speed_i'], [3])
    for _ in range(60):
        lo, hi = y.mem(L['_clock_s'], 2)
        if lo | hi << 8 >= FROM:
            break
        y.run_for(1)
    else:
        raise RuntimeError('the clock does not go')
    y.poke(L['_speed_i'], [SPEED])
    if os.environ.get('NOPILOT'):       # (from here on as a player has it:
        y.poke(L['_autopilot_on'], [0])  # the routes set stay; its search
    y.run_for(1)                        # for them is not a player's)
    for f in glob.glob(SHOT + '.*'):
        os.remove(f)
    pics = y.png_series(os.path.expanduser('~/.cache/trainschedule/test/smooth'))
finally:
    y.stop()

frames = [trains(p) for p in pics]
# follow each train of the first picture through the others
tracks = [[t] for t in frames[0]]
for fr in frames[1:]:
    for tr in tracks:
        if tr[-1] is None:
            continue
        last = tr[-1]
        best = min(fr, key=lambda t: (t[0] - last[0]) ** 2 + (t[1] - last[1]) ** 2,
                   default=None)
        if best and (best[0] - last[0]) ** 2 + (best[1] - last[1]) ** 2 < 100 \
                and abs(best[2] - last[2]) < last[2] // 3 + 8:
            tr.append(best)
        else:
            tr.append(None)
print(f'{len(pics)} pictures at speed {SPEED}')
for k, tr in enumerate(tracks):
    if None in tr:
        continue
    d = [((b[0] - a[0]) ** 2 + (b[1] - a[1]) ** 2) ** 0.5 for a, b in zip(tr, tr[1:])]
    moving = [x for x in d if x >= 0.5]
    if len(moving) < 3:
        continue
    first = next(i for i, x in enumerate(d) if x >= 0.5)
    last = max(i for i, x in enumerate(d) if x >= 0.5)
    still, run = 0, 0
    for x in d[first:last + 1]:
        run = run + 1 if x < 0.5 else 0
        still = max(still, run)
    sizes = sorted(round(x * 2) / 2 for x in moving)
    print(f'  train at {tr[0][0]:.0f},{tr[0][1]:.0f}: moved in {len(moving)} of '
          f'{len(d)} pictures, by {sizes[0]}-{sizes[-1]} px (half of them '
          f'{sizes[len(sizes) // 2]}), standing {still} pictures at most between')
    print('    ' + ''.join('.' if x < 0.5 else str(min(9, round(x))) for x in d))
