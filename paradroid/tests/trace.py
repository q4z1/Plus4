#!/usr/bin/env python3
"""trace.py root out [ticks] [seed] [arena|disrupt] - the game's state tick by tick, to
compare two builds (a rewrite against what it replaces): the build in
root (a checkout of this folder) is started in VICE, its random numbers
set to the same start when a game begins, then played with the same
keys - a seeded random walk, firing in directions, never fire alone (no
transfer, lift or console) - and after each tick its droids, shots,
score and the rest written to out as JSON, one line a tick. Compare two
with tests/tracecmp.py. "arena": the droids set round the player at the
start, armed, low on energy, the player in an armed host (629); "disrupt"
the same with the player in a disruptor droid (742)."""
import hashlib, json, os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice

root, out = sys.argv[1], sys.argv[2]
T = int(sys.argv[3]) if len(sys.argv) > 3 else 400
seed = int(sys.argv[4]) if len(sys.argv) > 4 else 7
scene = sys.argv[5] if len(sys.argv) > 5 else 'walk'
WORK = os.path.expanduser('~/.cache/paradroid/test')
lbl = {}
for l in open(os.path.join(root, 'build', 'paradroid.lbl')):
    p = l.split()
    lbl[p[2].lstrip('.')] = int(p[1], 16)
d64 = os.path.join(WORK, 'trace.d64')
os.makedirs(WORK, exist_ok=True)
open(d64, 'wb').write(open(os.path.join(root, 'build', 'paradroid.d64'), 'rb').read())

MAXD, MAXS = 13, 8
ARRAYS = [('_nd', 1), ('_d_type', MAXD), ('_d_x', 2 * MAXD), ('_d_y', 2 * MAXD),
          ('_d_vx', MAXD), ('_d_vy', MAXD), ('_d_energy', MAXD), ('_d_boom', MAXD),
          ('_d_wait', MAXD), ('_s_x', 2 * MAXS), ('_s_y', 2 * MAXS), ('_s_life', MAXS),
          ('_s_img', MAXS), ('_score', 4), ('_alert_acc', 1), ('_burn', 1),
          ('_flash', 1), ('_player_dead', 1), ('_touched', 1), ('rs', 2)]

v = Vice(d64, WORK, warp=True)
def go(timeout=0.05):
    v.settle = timeout
    r = v.cmd('x')
    v.settle = 0.02
    return r
def pc():
    return int(v.cmd('r').strip().splitlines()[-2].split()[0][2:], 16)
try:
    # the title up (its interrupt running, the title's set shown)
    irq = lbl['irq']
    for i in range(300):
        v.run_for(0.2)
        vec = v.mem(0xFFFE, 2)
        if vec[0] | vec[1] << 8 == irq and v.mem(lbl['_font_hi'], 1)[0] == 0xD8:
            break
    v.run_for(1.0)
    # fire, and at the game's start the same random numbers and ticks
    v.cmd('break %04x' % lbl['_new_game'])
    v.poke(lbl['_dbg_keys'], [16])
    v.run_for(0.15)
    v.poke(lbl['_dbg_keys'], [0])
    if pc() != lbl['_new_game']:        # (unless it got there already)
        go(25.0)
    v.cmd('delete')
    v.poke(lbl['rs'], [0x34, 0x12])
    v.poke(lbl['_tick'], [0])
    v.poke(lbl['_dbg_god'], [0])
    v.cmd('break %04x' % lbl['_player_fire'])
    go(30.0)
    rnd = random.Random(seed)
    keys = 0
    if scene != 'walk':
        px = v.mem(lbl['_d_x'], 2); py = v.mem(lbl['_d_y'], 2)
        px = px[0] | px[1] << 8; py = py[0] | py[1] << 8
        v.poke(lbl['_d_type'], [16 if scene == 'arena' else 18])
        nd = v.mem(lbl['_nd'], 1)[0]
        types = [9, 14, 17, 20, 22, 2, 15, 19, 21, 23, 5, 1]
        offs = [(48, 0), (-48, 0), (0, 40), (0, -40), (48, 40), (-48, 40),
                (48, -40), (-48, -40), (96, 0), (-96, 0), (0, 80), (96, 40)]
        for i in range(1, nd):
            ox, oy = offs[i - 1]
            x, y = px + ox, py + oy
            v.poke(lbl['_d_type'] + i, [types[i - 1]])
            v.poke(lbl['_d_energy'] + i, [12 + 3 * i])
            v.poke(lbl['_d_x'] + 2 * i, [x & 255, x >> 8])
            v.poke(lbl['_d_y'] + 2 * i, [y & 255, y >> 8])
    with open(out, 'w') as f:
        for t in range(T):
            st = {n: list(v.mem(lbl[n], k)) for n, k in ARRAYS}
            if t % 10 == 9:             # what is drawn, every tenth tick:
                h = lambda a, n: hashlib.md5(bytes(v.mem(a, n))).hexdigest()[:12]
                # both pictures, in whichever order the interrupt has them
                st['pictures'] = sorted(h(a, 0x1000) for a in (0xC000, 0xD000))
                st['slots'] = h(lbl['_pre'], 23 * 512)
            f.write(json.dumps(st) + '\n')
            if t % 6 == 0:
                d = rnd.choice([0, 1, 2, 4, 8, 5, 9, 6, 10])
                keys = d | (16 if d and rnd.random() < (0.4 if scene == 'walk' else 0.8) else 0)
                v.poke(lbl['_dbg_keys'], [keys])
            try:
                v.sock.settimeout(8)
                go()
            except TimeoutError:        # the game over: no more ticks
                f.write(json.dumps({'end': t}) + '\n')
                break
            if pc() != lbl['_player_fire']:
                f.write(json.dumps({'end': t}) + '\n')
                break
finally:
    v.stop()
