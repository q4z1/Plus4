#!/usr/bin/env python3
"""xtrace.py root out [seed] - the transfer game step by step, to compare
two builds (tests/tracecmp.py): a droid set onto the player in transfer
mode, the same random numbers when the game begins, then the board's
state at each of its steps (x_step: twice a tick) with a seeded play -
choosing a side, moving the cursor, putting pulses in: the parts, the
pulses on the lines, how long they last, and checksums of the board as
drawn and of the panel's status."""
import hashlib, json, os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice

root, out = sys.argv[1], sys.argv[2]
seed = int(sys.argv[3]) if len(sys.argv) > 3 else 3
WORK = os.path.expanduser('~/.cache/paradroid/test')
lbl = {}
for l in open(os.path.join(root, 'build', 'paradroid.lbl')):
    p = l.split()
    lbl[p[2].lstrip('.')] = int(p[1], 16)
for n in ('new_game', 'player_fire'):
    if '_' + n not in lbl:
        lbl['_' + n] = lbl[n]
if os.path.exists(out):
    os.remove(out)
d64 = os.path.join(WORK, 'xtrace.d64')
os.makedirs(WORK, exist_ok=True)
open(d64, 'wb').write(open(os.path.join(root, 'build', 'paradroid.d64'), 'rb').read())

v = Vice(d64, WORK, warp=True)
def go(t=0.05):
    v.settle = t
    r = v.cmd('x')
    v.settle = 0.02
    return r
def pc():
    return int(v.cmd('r').strip().splitlines()[-2].split()[0][2:], 16)
h = lambda a, n: hashlib.md5(bytes(v.mem(a, n))).hexdigest()[:12]
try:
    irq = lbl['irq']
    for i in range(300):
        v.run_for(0.2)
        vec = v.mem(0xFFFE, 2)
        if vec[0] | vec[1] << 8 == irq and v.mem(lbl['_font_hi'], 1)[0] == 0xD8:
            break
    v.run_for(1.0)
    v.cmd('break %04x' % lbl['_new_game'])
    v.poke(lbl['_dbg_keys'], [16])
    v.run_for(0.15)
    v.poke(lbl['_dbg_keys'], [0])
    if pc() != lbl['_new_game']:
        go(25.0)
    v.cmd('delete')
    v.poke(lbl['rs'], [0x34, 0x12])
    v.poke(lbl['_dbg_god'], [1])
    v.cmd('break %04x' % lbl['_player_fire'])
    go(30.0)
    v.cmd('delete')
    # droid 1 onto the player, fire held: transfer mode, then the touch
    x = v.mem(lbl['_d_x'], 2); y = v.mem(lbl['_d_y'], 2)
    v.poke(lbl['_d_x'] + 2, list(x)); v.poke(lbl['_d_y'] + 2, list(y))
    v.poke(lbl['_dbg_keys'], [16])
    v.cmd('break %04x' % lbl['_transfer_game'])
    go(30.0)
    v.cmd('delete')
    v.poke(lbl['_dbg_keys'], [0])
    v.poke(lbl['rs'], [0x78, 0x56])
    v.poke(lbl['_tick'], [0])
    v.cmd('break %04x' % lbl['_x_step'])
    rnd = random.Random(seed)
    v.sock.settimeout(20)
    with open(out, 'w') as f:
        for n in range(500):
            try:
                go()
            except TimeoutError:
                f.write(json.dumps({'end': n}) + '\n')
                break
            st = {'part': list(v.mem(lbl['_part'], 96)), 'live': list(v.mem(lbl['_live'], 96)),
                  'life': list(v.mem(lbl['_life'], 24)), 'rs': list(v.mem(lbl['rs'], 2)),
                  'board': h(0xC400 + 9 * 40, 640), 'colours': h(0xC000 + 9 * 40, 640),
                  'status': h(0xC400 + 80, 13)}
            f.write(json.dumps(st) + '\n')
            if n % 4 == 0:              # every other tick, new keys
                k = rnd.choice([0, 0, 1, 2, 16, 16, 8, 4])
                v.poke(lbl['_dbg_keys'], [k])
finally:
    v.stop()
