#!/usr/bin/env python3
"""
mkdata.py - the text files in data/ as tables for the program

Writes build/gen/:
  tiles.inc   POOL, the first character code figures may use (for engine.s)
  data.h      what the C side sees
  data.s      the tables

The deck characters are numbered afresh: 0 and 1 are blank (engine.s needs
the first 16 bytes of each character set empty), the others follow in the
order of the original's codes. Codes from POOL up are the figures'.

Blocks: the original's 32, and 8 more for the doors half open. A door opens
a row (vertical doors) or a column (horizontal ones) at a time; the
characters of an open part are the closed ones with bit 7 clear, as in the
original.
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
DATA = os.path.join(ROOT, 'data')
GEN = os.path.join(ROOT, 'build', 'gen')
os.makedirs(GEN, exist_ok=True)

LETTERS = '0123456789abcdefghijklmnopqrstuv'


def read(name):
    return open(os.path.join(DATA, name)).read()


def lines(name):
    return [l.rstrip('\n') for l in read(name).split('\n')
            if l.strip() and not l.startswith('#')]


# --- characters -------------------------------------------------------------
chars = {}
for m in re.finditer(r'char ([0-9a-f]{2}) col=(\d+)\n((?:[.#]{8}\n){8})', read('chars.txt')):
    c = int(m.group(1), 16)
    rows = [int(r.replace('.', '0').replace('#', '1'), 2) for r in m.group(3).split()]
    chars[c] = (int(m.group(2)), rows)

code_of = {}            # original code -> ours
glyphs = [[0] * 8, [0] * 8]
colours = [0, 0]
for c in sorted(chars):
    col, rows = chars[c]
    if not any(rows):
        code_of[c] = 0
        continue
    code_of[c] = len(glyphs)
    glyphs.append(rows)
    colours.append(col)
POOL = len(glyphs)


def mc(b):
    """a hires byte as multicolour: a pixel pair with anything set is %11"""
    out = 0
    for i in range(4):
        if (b >> (6 - 2 * i)) & 3:
            out |= 3 << (6 - 2 * i)
    return out


# --- blocks -------------------------------------------------------------------
blocks = []
cur = None
for l in lines('blocks.txt'):
    if l.startswith('block'):
        cur = []
        blocks.append(cur)
    else:
        cur += [int(x, 16) for x in l.split()]
assert len(blocks) == 32

# door animation: vertical door (block 1) opens rows 0..3 in columns 1,2;
# horizontal door (block 2) opens columns 0..3 in rows 1,2
def door_frames(b, vertical):
    out = []
    for k in range(1, 5):
        cells = list(blocks[b])
        for i in range(k):
            for j in (1, 2):
                idx = (i * 4 + j) if vertical else (j * 4 + i)
                cells[idx] &= 0x7F
        out.append(cells)
    return out


blocks += door_frames(1, True)      # 32..35
blocks += door_frames(2, False)     # 36..39
NBLK = len(blocks)

# what a block is: 1 solid, 2 door, 4 lift, 8 console, 16 energizer
FLAG = {}
for b in range(NBLK):
    FLAG[b] = 1
for b in (3, 20, 21, 24, 25):
    FLAG[b] = 0
FLAG[3] = 4
FLAG[20] = 16
FLAG[1] = FLAG[2] = 1 | 2
for b in range(32, 40):
    FLAG[b] = 2 | (0 if b in (35, 39) else 1)
for b in (16, 17, 18, 19, 28, 29, 30):
    FLAG[b] = 1 | 8

# --- decks --------------------------------------------------------------------
decks = []
cur = None
for l in lines('decks.txt'):
    if l.startswith('deck'):
        cur = []
        decks.append(cur)
    else:
        cur += [LETTERS.index(ch) for ch in l]
for d in decks:
    assert len(d) == 1024


def rle(bl):
    out = []
    i = 0
    while i < len(bl):
        n = 1
        while i + n < len(bl) and bl[i + n] == bl[i] and n < 255:
            n += 1
        if n == 1:
            out.append(bl[i])
        else:
            out += [0x80 | bl[i], n]
        i += n
    return out


deck_rle = [rle(d) for d in decks]

# --- waypoints, lifts, droids, ship ------------------------------------------
wps = []
for l in lines('waypoints.txt'):
    if l.startswith('deck'):
        wps.append([])
    else:
        wps[-1].append(tuple(int(x) for x in l.split()))

lifts = [tuple(int(x) for x in l.split()) for l in lines('lifts.txt')]
droids = [l.split() for l in lines('droids.txt')]
ship = [tuple(int(x) for x in l.split()) for l in lines('ship.txt')]

# --- panel --------------------------------------------------------------------
ptxt = read('panel.txt')
pcodes = []
pcols = []
for l in ptxt.split('\n'):
    if l.startswith('codes '):
        pcodes += [int(x, 16) for x in l[6:].split()]
    elif l.startswith('cols '):
        pcols += [int(x, 16) for x in l[5:]]
pfont = [0] * 2048
for m in re.finditer(r'char ([0-9a-f]{2})\n((?:[.#]{8}\n){8})', ptxt):
    c = int(m.group(1), 16)
    for y, r in enumerate(m.group(2).split()):
        pfont[c * 8 + y] = int(r.replace('.', '0').replace('#', '1'), 2)

# --- figures ------------------------------------------------------------------
# Multicolour, 4 bytes (16 pixels) a line. In the pictures: '.' see-through,
# 'x' %01 (dark), 'o' %10 (light).
DROID = [
    '.....xxx.....',
    '...xxxxxxx...',
    '.xxxxxxxxxxx.',
    '.............',
    'xxxxxxxxxxxxx',
    'x...x...x...x',
    'x...x...x...x',
    'x...x...x...x',
    'x...x...x...x',
    'x...x...x...x',
    'xxxxxxxxxxxxx',
    '.............',
    '.xxxxxxxxxxx.',
    '...xxxxxxx...',
    '.....xxx.....',
    '.....x.x.....',
]
DIGITS = [
    ['###', '#.#', '#.#', '#.#', '###'],
    ['.#.', '##.', '.#.', '.#.', '###'],
    ['###', '..#', '###', '#..', '###'],
    ['###', '..#', '.##', '..#', '###'],
    ['#.#', '#.#', '###', '..#', '..#'],
    ['###', '#..', '###', '..#', '###'],
    ['###', '#..', '###', '#.#', '###'],
    ['###', '..#', '..#', '.#.', '.#.'],
    ['###', '#.#', '###', '#.#', '###'],
    ['###', '#.#', '###', '..#', '###'],
]


def pic_bytes(rows, swap=False):
    out = []
    for r in rows:
        r = (r + '.' * 16)[:16]
        for b in range(4):
            v = 0
            for i in range(4):
                ch = r[b * 4 + i]
                p = {'.': 0, 'x': 1, 'o': 2}[ch]
                if swap and p:
                    p ^= 3
                v |= p << (6 - 2 * i)
            out.append(v)
    return out


def droid_rows(num):
    pic = [list(r) for r in DROID]
    for k, ch in enumerate('%03d' % num):
        g = DIGITS[int(ch)]
        for y in range(5):
            for x in range(3):
                pic[5 + y][1 + k * 4 + x] = 'o' if g[y][x] == '#' else 'x'
    return [''.join(r) for r in pic]


# the deck plan's characters (console.c), hires, '#' set
XFER = {
    'blank':  ['........'] * 8,
    'wire':   ['........', '........', '........', '########', '########', '........', '........', '........'],
    'socket': ['........', '..####..', '.#....#.', '.#.####.', '.#.####.', '.#....#.', '..####..', '........'],
    'light':  ['.######.', '########', '########', '########', '########', '########', '########', '.######.'],
    'lift':   ['..####..', '.#.##.#.', '#..##..#', '########', '########', '#..##..#', '.#.##.#.', '..####..'],
}
XFER_ORDER = ['blank', 'wire', 'socket', 'light', 'lift']

# the transfer game's, the original's: $F1-$FE, $D0, $D1 (transfer.txt);
# black is %01 on the Plus/4, where the C64 has it at %10
board = []
for m in re.finditer(r'char ([0-9a-f]{2})\n((?:[.12]{4}\n){8})', read('transfer.txt')):
    for r in m.group(2).split():
        v = 0
        for ch in r:
            v = v << 2 | {'.': 0, '1': 1, '2': 3}[ch]
        board.append(v)
NBOARD = len(board) // 8
assert NBOARD == 16

# --- side view of the ship ------------------------------------------------------
stxt = read('sideview.txt')
side_rows = []
shafts = []
side_box = []
side_chars = {}
for l in stxt.split('\n'):
    if l.startswith('row '):
        side_rows.append([int(x, 16) for x in l[4:].split()])
    elif l.startswith('shaft '):
        shafts.append(tuple(int(x) for x in l[6:].split()))
    elif l.startswith('deck '):
        side_box.append(tuple(int(x) for x in l[5:].split()[1:]))
for m in re.finditer(r'char ([0-9a-f]{2}) col=(\d+)\n((?:[.#]{8}\n){8})', stxt):
    side_chars[int(m.group(1), 16)] = (int(m.group(2)),
        [int(r.replace('.', '0').replace('#', '1'), 2) for r in m.group(3).split()])
SIDE_BASE = len(XFER_ORDER)             # after the transfer game's, in the pool
NSIDE = 0x30                            # codes $80-$AF
assert POOL + SIDE_BASE + NSIDE <= 256
# the map from its second row (the first is empty), as runs: code, count
assert not any(side_rows[0])
side_rle = []
flat = [c for r in side_rows[1:] for c in r]
i = 0
while i < len(flat):
    n = 1
    while i + n < len(flat) and flat[i + n] == flat[i] and n < 255:
        n += 1
    side_rle += [flat[i], n]
    i += n
side_rle.append(0)
side_rle.append(0)


def swap_mc(b):
    """%01 and %10 changed round: the C64 has white and black the other way"""
    return ((b & 0x55) << 1) | ((b & 0xAA) >> 1)


# --- briefing (a file on the disk) ----------------------------------------------
# The original's pages in the panel's codes: per page its height in rows,
# then each line as row, column, length and codes, then $FF; a height of 0
# ends the file. A letter is two rows, code c over c + $80; the wide ones
# (from $3A) take the code and the code + $20 beside it.
def txt_codes(text):
    out = []
    for ch in text:
        if ch.isdigit():
            c = ord(ch) - 48
        elif ch == 'm':
            c = 0x42
        elif ch == 'w':
            c = 0x54
        elif ch.islower():
            c = 0x0a + ord(ch) - 97
        elif ch == 'I':
            c = 0x16
        elif ch.isupper():
            c = 0x3a + ord(ch) - 65
        else:
            c = {'@': 0x20, '.': 0x28, ',': 0x29, ':': 0x2a, "'": 0x2d,
                 '-': 0x2e, ' ': 0x30}[ch]
        out += [c, c + 0x20] if c >= 0x3a else [c]
    return out

brief = []
page = None
for ln in lines('briefing.txt'):
    if ln.startswith('page'):
        if page:
            brief.append(page)
        page = []
        continue
    row, col, text = ln.split(' ', 2)
    # the Plus/4 is the remote terminal here
    page.append((int(row) - 2, int(col), txt_codes(text.replace('C64', 'Plus4'))))
brief.append(page)
# The briefing brings a character set of its own, for the window to scroll
# it in: the panel's characters it needs, each picture once, the blank one
# first. Its text is in letters: letter k is glyph top[k] over bot[k].
glyph_of = {}
srcs = []
def bglyph(pc):
    g = tuple(pfont[pc * 8:pc * 8 + 8])
    if g not in glyph_of:
        glyph_of[g] = len(srcs)
        srcs.append(pc)
    return glyph_of[g]
assert not any(pfont[0x30 * 8:0x31 * 8]) and not any(pfont[0xB0 * 8:0xB1 * 8])
bglyph(0x30)
letter_of = {(0, 0): 0}
for page in brief:
    for r, c, t in page:
        for pc in t:
            letter_of.setdefault((bglyph(pc), bglyph(pc | 0x80)), len(letter_of))
letters = sorted(letter_of, key=letter_of.get)
NBRIEF = len(srcs)
assert NBRIEF <= POOL, NBRIEF
pages_bin = []
for page in brief:
    pages_bin.append(max(r for r, c, t in page) + 2)
    for r, c, t in page:
        assert 1 <= c and c + len(t) <= 39, (r, c, len(t))
        pages_bin += [r, c, len(t)] + [letter_of[(bglyph(pc), bglyph(pc | 0x80))] for pc in t]
    pages_bin.append(0xFF)
pages_bin.append(0)
BRIEF_SIZE = len(srcs) + 2 * len(letters) + len(pages_bin)


# --- write ---------------------------------------------------------------------
def asm_bytes(name, data, per=16):
    out = ['_%s:' % name]
    for i in range(0, len(data), per):
        out.append('        .byte ' + ','.join('$%02x' % b for b in data[i:i + per]))
    return '\n'.join(out) + '\n'


s = ['; made by tools/mkdata.py - do not edit', '        .rodata', '']
exports = []


def emit(name, data, per=16):
    exports.append(name)
    s.append(asm_bytes(name, data, per))


emit('tile_col', colours)
# block codes, [yy][blk*4 + x]: 4 tables of 256
bc = []
for yy in range(4):
    row = [0] * 256
    for b in range(NBLK):
        for x in range(4):
            row[b * 4 + x] = code_of[blocks[b][yy * 4 + x]]
    bc += row
emit('blk_flag', [FLAG[b] for b in range(NBLK)])
# decks
allrle = []
offs = []
for r in deck_rle:
    offs.append(len(allrle))
    allrle += r
emit('deck_rle', allrle)
exports.append('deck_off')
s.append('_deck_off:\n        .word ' + ','.join('_deck_rle+%d' % o for o in offs) + '\n')
# waypoints
wx, wy, wd, wofs = [], [], [], []
for d in wps:
    wofs.append(len(wx))
    for x, y, dirs in d:
        wx.append(x)
        wy.append(y)
        wd.append(dirs)
wofs.append(len(wx))
emit('wp_x', wx)
emit('wp_y', wy)
emit('wp_dir', wd)
emit('wp_first', wofs)
emit('lift_deck', [l[0] for l in lifts])
emit('lift_shaft', [l[1] for l in lifts])
emit('lift_bx', [l[2] for l in lifts])
emit('lift_by', [l[3] for l in lifts])
emit('dr_class', [int(d[0]) // 100 for d in droids])
emit('dr_num', [int(d[0]) % 100 for d in droids])
emit('dr_drive', [int(d[1]) for d in droids])
emit('dr_weapon', [int(d[2]) for d in droids])
emit('ship_base', [x[1] for x in ship])
emit('ship_count', [x[2] for x in ship])
# figures
# a droid's picture is made when needed: the template and its number
emit('droid_tmpl', pic_bytes([r.replace('.', 'x') if 5 <= i <= 9 else r
                              for i, r in enumerate(DROID)]))
dg = []
for g in DIGITS:
    v = 0
    for y in range(5):
        for x in range(3):
            if g[y][x] == '#':
                v |= 1 << (y * 3 + x)
    dg += [v & 255, v >> 8]
emit('digit_bits', dg)
# lasers and explosion from the original's sprites (24 x 21), as 12
# multicolour pixels by 16 lines: hires pixel pairs become light pixels, the
# explosion's colours light and dark
sprites = {}
for m in re.finditer(r'sprite (\w+) (mc|hires)\n((?:[.#0-3]{12,24}\n){21})', read('sprites.txt')):
    sprites[m.group(1)] = (m.group(2), m.group(3).split())


def sprite_pic(name, top):
    kind, rows = sprites[name]
    out = []
    for r in rows[top:top + 16]:
        if kind == 'hires':
            out.append(''.join('o' if '#' in r[2 * i:2 * i + 2] else '.' for i in range(12)))
        else:
            out.append(''.join({'0': '.', '1': 'o', '2': 'x', '3': 'o'}[c] for c in r))
    return out


eimg = []
for i in range(6):
    eimg += pic_bytes(sprite_pic('explo%d' % i, 2))
emit('explo_img', eimg)
emit('laser_v', pic_bytes(sprite_pic('laser_v', 2)))
emit('laser_h', pic_bytes(sprite_pic('laser_h', 3)))
emit('laser_d1', pic_bytes(sprite_pic('laser_d1', 2)))
emit('laser_d2', pic_bytes(sprite_pic('laser_d2', 2)))

sf = []
scol = []
for c in range(0x80, 0x80 + NSIDE):
    col, g = side_chars[c]
    if col >= 8:
        g = [swap_mc(b) for b in g]
    sf += g
    scol.append(col)
emit('side_font', sf)
emit('side_col', scol)
emit('side_rle', side_rle)
# a row higher than the original's screen rows: the window's first row is
# hidden while it is not scrolled, so it sits where the original's does
emit('side_box', [v - (k == 0) for b in side_box for k, v in enumerate(b)])
emit('shaft_col', [x[0] for x in shafts])
emit('shaft_top', [x[1] - 1 for x in shafts])
emit('shaft_len', [x[2] for x in shafts])

xf = []
for name in XFER_ORDER:
    xf += [int(r.replace('.', '0').replace('#', '1'), 2) for r in XFER[name]]
emit('xfer_font', xf)
emit('board_font', board)

# Used once at the start, then overwritten: the pre-shifted pictures
# (draw.c) start where these are, 23 slots of 512 bytes. The start makes
# the explosions' and lasers' slots (10 on) before it is done with these.
PRE_SLOTS = 23
s.append('        .segment "INITDATA"')
s.append('_pre:')
init = (('tile_font', sum(glyphs, [])), ('blk_code', bc), ('panel_font', pfont),
        ('panel_codes', pcodes), ('panel_cols', pcols))
for name, data in init:
    exports.append(name)
    s.append(asm_bytes(name, data))
init_size = sum(len(d) for n, d in init)
assert init_size <= 10 * 512, init_size
s.append('        .segment "PREBSS"')
s.append('        .res %d' % (PRE_SLOTS * 512 - init_size))
exports.append('pre')

s.insert(2, '\n'.join('        .export _%s' % e for e in exports) + '\n')
open(os.path.join(GEN, 'data.s'), 'w').write('\n'.join(s))

# into the title's overlay (title.c), which is a file on the disk
b = ['; made by tools/mkdata.py - do not edit',
     '        .segment "OVLHDR"', '        .word 0         ; where a load address goes',
     '        .segment "OVLDATA"',
     '        .export _brief_srcs, _brief_top, _brief_bot, _brief_pages']
for name, data in (('brief_srcs', srcs), ('brief_top', [t for t, u in letters]),
                   ('brief_bot', [u for t, u in letters]), ('brief_pages', pages_bin)):
    b.append(asm_bytes(name, data))
open(os.path.join(GEN, 'brief.s'), 'w').write('\n'.join(b) + '\n')


h = ['/* made by tools/mkdata.py - do not edit */',
     '#define POOL %d' % POOL,
     '#define NBLK %d' % NBLK,
     '#define NDECKS %d' % len(decks),
     '#define NLIFTS %d' % len(lifts),
     '#define NDROIDS %d' % len(droids),
     '#define DROID_H %d' % len(DROID),
     '#define EXPLO_H 16', '#define NEXPLO 6',
     '#define B_SOLID 1', '#define B_DOOR 2', '#define B_LIFT 4',
     '#define B_CONSOLE 8', '#define B_ENERGY 16',
     '#define BLK_VDOOR 1', '#define BLK_HDOOR 2',
     '#define BLK_VOPEN 32', '#define BLK_HOPEN 36',
     '#define NXFER %d' % len(XFER_ORDER), '#define NBOARD %d' % NBOARD, '#define PRE_SLOTS 23',
     '#define BRIEF_SIZE %d' % BRIEF_SIZE, '#define NBRIEF %d' % NBRIEF] + \
    ['#define X_%s %d' % (n.upper(), i) for i, n in enumerate(XFER_ORDER)] + \
    ['#define NSIDE %d' % NSIDE, '#define SIDE_BASE %d' % SIDE_BASE,
     '']
for e in exports:
    if e == 'deck_off':
        h.append('extern const unsigned char *const deck_off[];')
    elif e == 'pre':
        h.append('extern unsigned char pre[];')
    else:
        h.append('extern const unsigned char %s[];' % e)
h.append('/* in the title\'s overlay (brief.s) */')
h.append('extern const unsigned char brief_srcs[], brief_top[], brief_bot[], brief_pages[];')
open(os.path.join(GEN, 'data.h'), 'w').write('\n'.join(h) + '\n')
open(os.path.join(GEN, 'tiles.inc'), 'w').write('POOL = %d\n' % POOL)
print('tiles %d, pool %d chars, blocks %d, decks %d bytes, briefing %d bytes' % (POOL - 2, 256 - POOL, NBLK, len(allrle), BRIEF_SIZE))
