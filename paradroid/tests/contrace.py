#!/usr/bin/env python3
"""contrace.py root out - the console's and lift's pages, to compare two
builds (tests/tracecmp.py): the same random start, the player put on a
console of the deck, then its menu, the deck plan, the ship's side view,
the droid enquiry and its pages, and riding a lift up and down. For each
page checksums of picture 0's codes and colours and of picture 1's
character set: these pages are drawn straight into both pictures."""
import hashlib, json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice

root, out = sys.argv[1], sys.argv[2]
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
decks = []
for l in open(os.path.join(root, 'data', 'decks.txt')):
    l = l.rstrip('\n')
    if not l or l.startswith('#'):
        continue
    if l.startswith('deck'):
        decks.append([])
    else:
        decks[-1].append(l)
d64 = os.path.join(WORK, 'contrace.d64')
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
def keys(k, s):
    v.poke(lbl['_dbg_keys'], [k])
    v.run_for(s)
def to(x, y):
    X, Y = x * 32 + 16, y * 32 + 16
    v.poke(lbl['_d_x'], [X & 255, X >> 8])
    v.poke(lbl['_d_y'], [Y & 255, Y >> 8])
    v.poke(lbl['_d_vx'], [0])
    v.poke(lbl['_d_vy'], [0])
f = open(out, 'w')
def page(name):
    v.run_for(1.5)                      # (the page whole, the picture loaded)
    st = {'page': name, 'codes': h(0xC400 + 9 * 40, 640), 'colours': h(0xC000 + 9 * 40, 640),
          'font': h(0xD800, 0x800), 'panel': h(0xC400 + 80, 13)}
    if os.environ.get('CONTRACE_DUMP'):    # (to look into)
        open(out + '.' + name.replace(' ', '_'), 'wb').write(bytes(v.mem(0xD800, 0x800)))
    f.write(json.dumps(st) + '\n')
    f.flush()
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
    v.poke(lbl['_nd'], [1])              # (no droids in the way)
    m = decks[v.mem(lbl['_deck'], 1)[0]]
    x, y = [(x, y) for y in range(1, 15) for x in range(1, 63) if m[y][x] == 'l'
            and any(m[y + b][x + a] in 'ghijstu' for a, b in ((1, 0), (-1, 0), (0, 1), (0, -1)))][0]
    to(x, y)
    keys(0, 0.4)
    keys(16, 0.7); keys(0, 1.0)
    page('menu')
    for k in (2, 2):
        keys(k, 0.15); keys(0, 0.3)
    keys(16, 0.15); keys(0, 0.5)
    page('plan')
    keys(16, 0.15); keys(0, 0.5)
    keys(2, 0.15); keys(0, 0.3)
    keys(16, 0.15); keys(0, 0.5)
    page('ship')
    keys(16, 0.15); keys(0, 0.5)
    for k in (1, 1):                    # up twice: the enquiry
        keys(k, 0.15); keys(0, 0.3)
    v.poke(lbl['_d_type'], [9])
    keys(16, 0.15); keys(0, 0.5)
    page('enquiry')
    keys(8, 0.15); keys(0, 0.5)
    page('enquiry 2')
    keys(4, 0.15); keys(0, 0.5)
    page('enquiry back')
    keys(1, 0.15); keys(0, 0.5)
    page('enquiry type')
    keys(2, 0.15); keys(0, 0.5)
    page('enquiry type back')
    keys(16, 0.15); keys(0, 0.5)
    page('menu again')
    for k in (2, 2, 2):                 # down to leave, fire
        keys(k, 0.15); keys(0, 0.3)
    keys(16, 0.15); keys(0, 1.5)
    # a lift: up and down its shaft, out again
    v.poke(lbl['_d_type'], [0])
    m = decks[v.mem(lbl['_deck'], 1)[0]]
    lx, ly = [(x, y) for y in range(16) for x in range(64) if m[y][x] == '3'][0]
    to(lx, ly)
    keys(0, 0.4)
    keys(16, 1.0)
    page('lift')
    keys(17, 0.15); keys(16, 0.5)
    page('lift up')
    keys(18, 0.15); keys(16, 0.5)
    page('lift down')
    keys(18, 0.15); keys(16, 0.5)
    page('lift down 2')
    keys(0, 2.0)
    f.write(json.dumps({'deck': v.mem(lbl['_deck'], 1)[0]}) + '\n')
finally:
    f.close()
    v.stop()
