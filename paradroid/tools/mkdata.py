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

# what a block is: 1 solid, 2 door, 4 lift, 8 console, 16 energizer (where
# its walls are, character by character: the block codes' tables, below)
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
                p = {'.': 0, 'x': 1, 'o': 2, 'c': 3}[ch]
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


# --- the droids' pictures (files on the disk) ------------------------------------
# A picture is six characters wide, from 6 lines into its first row (where
# the original's sprites start). A cell with multicolour pixels is
# multicolour: %01 black, %10 the second multicolour, %11 the picture's
# colour (the C64 has %10 and %11 the other way); one with only the hires
# sprites' pixels stays hires. A file: the characters, then rows x 6 cells
# (0 none, else the character's number from 1, +$80 hires), then the number
# of characters, rows, and the two C64 colours. It is loaded to character 1
# of picture 1's set (transfer.c), its end found from its length.
PIC_TOP = 6
pics = []
cur = None
for l in read('pictures.txt').split('\n'):
    if l.startswith('picture'):
        f = dict(x.split('=') for x in l.split()[2:])
        cur = {'col': int(f['colour']), 'mc2': int(f['mc2']), 'rows': []}
        pics.append(cur)
    elif cur is not None and l and l[0] in '.ksmh':
        cur['rows'].append(l)
os.makedirs(os.path.join(ROOT, 'build', 'pics'), exist_ok=True)
pic_max = 0
for n, pic in enumerate(pics):
    rows = ['.' * 48] * PIC_TOP + pic['rows']
    nrow = (len(rows) + 7) // 8
    rows += ['.' * 48] * (nrow * 8 - len(rows))
    chars, layout = [], []
    for cr in range(nrow):
        for cx in range(6):
            cell = [rows[cr * 8 + y][cx * 8:cx * 8 + 8] for y in range(8)]
            if all(ch == '.' for r in cell for ch in r):
                layout.append(0)
                continue
            hires = all(ch in '.h' for r in cell for ch in r)
            g = []
            for r in cell:
                v = 0
                if hires:
                    for ch in r:
                        v = v << 1 | (ch == 'h')
                else:
                    for j in range(4):
                        pair = r[2 * j:2 * j + 2].replace('.', '')
                        v = v << 2 | {'k': 1, 'm': 2, 's': 3, 'h': 3, '': 0}[pair[:1]]
                g.append(v)
            if g not in chars:
                chars.append(g)
            layout.append((chars.index(g) + 1) | (0x80 if hires else 0))
    pic['data'] = sum(chars, []) + layout + [len(chars), nrow, pic['col'], pic['mc2']]
    pic['head'] = len(pic['data']) - 4
    assert len(chars) < 90 and nrow <= 12, (n, len(chars), nrow)

# --- the deck plan (console.c, an overlay) ---------------------------------------
# The original's plan characters: code = block number, $A0 the player, all
# hires. Their C64 colours alongside.
plan_font, plan_col = [], []
for m in re.finditer(r'char ([0-9a-f]{2}) col=(\d+)\n((?:[.#]{8}\n){8})', read('plan.txt')):
    plan_font += [int(r.replace('.', '0').replace('#', '1'), 2) for r in m.group(3).split()]
    plan_col.append(int(m.group(2)))
assert len(plan_col) == 33

# --- the console's menu (console.c) ------------------------------------------------
# Its four symbols, the original's hires sprites (icons.txt), as hires
# characters: per symbol its column, row, width and height in cells, then
# its cells (0 none, else the character's number from 1).
# And the decks' names (decknames.txt), for the menu page.
icon_font, icon_tab, icon_lay = [], [], []
glist = []
cur = None
for l in read('icons.txt').split('\n'):
    if l.startswith('icon'):
        _, i, col, row = l.split()
        cur = {'col': int(col), 'row': int(row), 'rows': []}
        icon_tab.append(cur)
    elif cur is not None and l and l[0] in '.h':
        cur['rows'].append(l)
for ic in icon_tab:
    rows = ic['rows']
    ic['w'], ic['h'] = len(rows[0]) // 8, len(rows) // 8
    for cr in range(ic['h']):
        for cx in range(ic['w']):
            g = [int(rows[cr * 8 + y][cx * 8:cx * 8 + 8].replace('.', '0').replace('h', '1'), 2)
                 for y in range(8)]
            if not any(g):
                icon_lay.append(0)
                continue
            if g not in glist:
                glist.append(g)
            icon_lay.append(glist.index(g) + 1)
icon_font = sum(glist, [])
ICON_N = len(glist)
icon_tab = sum([[ic['col'], ic['row'], ic['w'], ic['h']] for ic in icon_tab], [])
decknames = ['deck %d' % d for d in range(16)]
if os.path.exists(os.path.join(DATA, 'decknames.txt')):
    decknames = lines('decknames.txt')

# --- the title's logo (title.c) ------------------------------------------------------
# The original's PARADROID over the whole screen (logo.txt): its characters
# numbered from 0 (the blank one) in the order met, each with its C64
# colour (a character always has the same one), and the 1000 cells as
# runs: number, count; a count of 0 ends.
ltxt = read('logo.txt')
lrows = [[int(x, 16) for x in l[4:].split()] for l in ltxt.split('\n') if l.startswith('row ')]
lcols = [[int(x, 16) for x in l[4:]] for l in ltxt.split('\n') if l.startswith('col ')]
LOGO_BG = int(re.search(r'^bg (\d+)', ltxt, re.M).group(1))
lglyph = {int(m.group(1), 16): [int(r.replace('.', '0').replace('#', '1'), 2) for r in m.group(2).split()]
          for m in re.finditer(r'char ([0-9a-f]{2})\n((?:[.#]{8}\n){8})', ltxt)}
# The port's credit in the empty box at the bottom right, two lines in the
# letters of the original's plates ("BY ANDREW BRAYBROOK"): those it has,
# and the others drawn in their style, numbered from $100 on.
CREDIT = ((20, 'PLUS/4 CONVERSION'), (21, 'BY Q4Z1 2026'))
CREDIT_COL = 11                         # the plates' letters' dark grey
CREDIT_HAS = {'B': 0xE0, 'Y': 0xFF, 'A': 0xDF, 'N': 0xE4, 'D': 0xE1, 'R': 0xE6,
              'E': 0xE2, 'W': 0xE7, 'O': 0xE5, 'K': 0xE3, ' ': 0x00}
CREDIT_NEW = {
    'P': ['######..', '##...##.', '######..', '##......', '##......', '###.....'],
    'L': ['##......', '##......', '##......', '##......', '##....#.', '#######.'],
    'U': ['##...##.', '##...##.', '##...##.', '##...##.', '##...##.', '.#####..'],
    'S': ['.#####..', '##......', '.#####..', '.....##.', '##...##.', '.#####..'],
    'C': ['.#####..', '##...##.', '##......', '##......', '##...##.', '.#####..'],
    'V': ['##...##.', '##...##.', '##...##.', '.##.##..', '..###...', '...#....'],
    'I': ['.####...', '..##....', '..##....', '..##....', '..##....', '.####...'],
    'Q': ['.#####..', '##...##.', '##...##.', '##.#.##.', '##..##..', '.###.##.'],
    'Z': ['#######.', '#....##.', '...##...', '.##.....', '##....#.', '#######.'],
    '/': ['.....##.', '....##..', '...##...', '..##....', '.##.....', '##......'],
    '4': ['...###..', '..####..', '.##.##..', '##..##..', '#######.', '....##..'],
    '1': ['..##....', '.###....', '..##....', '..##....', '..##....', '.####...'],
    '2': ['.#####..', '##...##.', '....##..', '..##....', '.##.....', '#######.'],
    '0': ['.#####..', '##..###.', '##.#.##.', '##.#.##.', '###..##.', '.#####..'],
    '6': ['.#####..', '##......', '######..', '##...##.', '##...##.', '.#####..'],
}
for k, (ch, g) in enumerate(sorted(CREDIT_NEW.items())):
    CREDIT_HAS[ch] = 0x100 + k
    lglyph[0x100 + k] = [0] + [int(r.replace('.', '0').replace('#', '1'), 2) for r in g] + [0]
for row, text in CREDIT:
    col = 18 + (20 - len(text)) // 2        # the box's inside: columns 18-37
    for i, ch in enumerate(text):
        lrows[row][col + i] = CREDIT_HAS[ch]
        if ch != ' ':
            lcols[row][col + i] = CREDIT_COL
lorder = [0x00] + sorted(c for c in lglyph if c != 0)
assert not any(lglyph[0])
lcol = {}
for r in range(25):
    for c in range(40):
        lcol[lrows[r][c]] = lcols[r][c]
logo_font = sum((lglyph[c] for c in lorder), [])
logo_col = [lcol[c] for c in lorder]
flat = [lorder.index(c) for r in lrows for c in r]
logo_rle = []
i = 0
while i < len(flat):
    n = 1
    while i + n < len(flat) and flat[i + n] == flat[i] and n < 255:
        n += 1
    logo_rle += [flat[i], n]
    i += n
logo_rle += [0, 0]

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
# an addition to the original's credits (page 4)
brief[4].append((55 - 2, 13, txt_codes('Plus4 version 2026 in C.')))
brief[4].sort()
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
# all digits and capitals too, for the day's scores and their initials,
# which title.c writes into page 4
def letters_of(text):
    return [letter_of.setdefault((bglyph(pc), bglyph(pc | 0x80)), len(letter_of))
            for pc in txt_codes(text)]
brief_dig = sum((letters_of(str(d)) for d in range(10)), [])
brief_cap = sum(((letters_of(chr(65 + i)) + letters_of(' '))[:2] for i in range(26)), [])  # (I is narrow)
brief_misc = letters_of(' ') + letters_of('-')
letters = sorted(letter_of, key=letter_of.get)
NBRIEF = len(srcs)
assert NBRIEF <= POOL, NBRIEF
# the console's pages about each droid (console.txt) after its picture: per
# page its lines as row, column, length and the panel's codes, then $FF; a
# 0 after the last page; and at the very end, where the picture's header is
cpages = {}
cur = None
for ln in lines('console.txt'):
    if ln.startswith('type'):
        cur = cpages.setdefault(int(ln.split()[1]), [])
    elif ln == 'page':
        cur.append([])
    else:
        row, col, txt = ln.split(' ', 2)
        cur[-1].append((int(row), int(col), txt_codes(txt)))
for n, pic in enumerate(pics):
    data = list(pic['data'])
    for page in cpages.get(n, []):
        for row, col, t in page:
            data += [row, col, len(t)] + t
        data.append(0xFF)
    data.append(0)
    data += [pic['head'] & 255, pic['head'] >> 8]
    assert len(data) <= 139 * 8 - 8, (n, len(data))   # below the letters (from 140)
    pic_max = max(pic_max, len(data))
    open(os.path.join(ROOT, 'build', 'pics', 'p%02d' % n), 'wb').write(bytes([0, 0] + data))

pages_bin = []
score_at = []
for page in brief:
    pages_bin.append(max(r for r, c, t in page) + 2)
    for r, c, t in page:
        assert 1 <= c and c + len(t) <= 39, (r, c, len(t))
        if page is brief[4] and r in (3, 11):   # the day's top and worst score
            score_at.append(len(pages_bin) + 3)
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
# block codes, [yy][blk*4 + x]: 4 tables of 256. The free end of each,
# from 192 on, holds the walls: for block b, at 192 + b, a bit for each of
# its four characters in row yy that is a wall - in the original, a
# character code from $80 on (doors open by clearing that bit, above)
bc = []
assert NBLK <= 64
for yy in range(4):
    row = [0] * 256
    for b in range(NBLK):
        for x in range(4):
            row[b * 4 + x] = code_of[blocks[b][yy * 4 + x]]
        row[192 + b] = sum(1 << x for x in range(4) if blocks[b][yy * 4 + x] >= 0x80)
    bc += row

# the original's sound effects (data/sfx.txt, from it by tools/sfx.py), for
# sfx.s: 8 bytes each - the SID's start frequency and step, the first
# period and the ones after, then their count (bits 0-4) with reset (5),
# voice 2 (6: the original's channel 2, or noise, which only the TED's
# voice 2 has) and noise (7), and the pictures it sounds: until the period
# ends, or the gate and half the release (the TED has no envelope). The
# deck's hum's periods go into the block code tables' free end (row 0 at
# 160 and 176, row 1 at 160).
sfx_tab, sfx_names, hum = [], [], {}
for l in lines('sfx.txt'):
    w = l.split()
    if w[0].startswith('hum_'):
        hum[w[0]] = [int(x) for x in w[1:]]
        continue
    name, num, ch, start, step, first, per, cnt, reset, wave, gate, rel = w
    start, step, first, per, cnt = int(start), int(step) & 0xFFFF, int(first), int(per), int(cnt)
    total = first + per * (cnt - 1)
    sounds = min(total, int(gate) + round(int(rel) / 20 / 2), 255)
    noise = wave == 'N'
    flags = cnt | int(reset) << 5 | (noise or ch == '2') << 6 | noise << 7
    assert cnt < 32
    sfx_tab += [start & 255, start >> 8, step & 255, step >> 8, first, per, flags, sounds]
    sfx_names.append(name)
assert len(sfx_tab) <= 186, len(sfx_tab)
for k in range(16):
    bc[160 + k] = hum['hum_first'][k]
    bc[176 + k] = hum['hum_period'][k]
    bc[256 + 160 + k] = hum['hum_count'][k]
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
# multicolour pixels by 16 lines: hires pixel pairs become light pixels. The
# explosion's black stays black (%01), its yellow and orange are the cells'
# own colour (%11), which draw.c sets: yellow, then orange as it dies down
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
            out.append(''.join({'0': '.', '1': 'x', '2': 'c', '3': 'c'}[c] for c in r))
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
emit('side_box', [v for b in side_box for v in b])
emit('shaft_col', [x[0] for x in shafts])
emit('shaft_top', [x[1] for x in shafts])
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
# fastinit.c and the drive code are in INITDATA too (build.sh says how much)
init_size = (sum(len(d) for n, d in init) + int(os.environ.get('INIT_EXTRA', 0))
             + len(sfx_tab))
assert init_size <= PRE_SLOTS * 512, init_size
s.append('        .segment "SFXDATA"')       # run at $FF40, copied there at the start
s.append(asm_bytes('sfx_tab', sfx_tab))
exports.append('sfx_tab')
s.append('        .segment "PREBSS"')
s.append('        .res %d' % (PRE_SLOTS * 512 - init_size))
exports.append('pre')

s.insert(2, '\n'.join('        .export _%s' % e for e in exports) + '\n')
open(os.path.join(GEN, 'data.s'), 'w').write('\n'.join(s))
open(os.path.join(GEN, 'sfx.inc'), 'w').write(
    ''.join('SFX_%s = %d\n' % (n.upper(), i) for i, n in enumerate(sfx_names)))

# into the title's overlay (title.c), which is a file on the disk
c = ['; made by tools/mkdata.py - do not edit',
     '        .rodata', '        .export _plan_font, _plan_col']
c.append(asm_bytes('plan_font', plan_font))
c.append(asm_bytes('plan_col', plan_col))
c.append('        .export _icon_font, _icon_tab, _icon_lay')
c.append(asm_bytes('icon_font', icon_font))
c.append(asm_bytes('icon_tab', icon_tab))
c.append(asm_bytes('icon_lay', icon_lay))
open(os.path.join(GEN, 'console.s'), 'w').write('\n'.join(c) + '\n')

b = ['; made by tools/mkdata.py - do not edit',
     '        .segment "OVLHDR"', '        .word 0         ; where a load address goes',
     '        .segment "OVLDATA"',
     '        .export _brief_srcs, _brief_top, _brief_bot, _brief_pages']
for name, data in (('brief_srcs', srcs), ('brief_top', [t for t, u in letters]),
                   ('brief_bot', [u for t, u in letters]), ('brief_pages', pages_bin),
                   ('brief_dig', brief_dig), ('brief_cap', brief_cap), ('brief_misc', brief_misc)):
    b.append(asm_bytes(name, data))
b[4] = b[4] + ', _brief_dig, _brief_cap, _brief_misc, _logo_font, _logo_col, _logo_rle'
b.append(asm_bytes('logo_font', logo_font))
b.append(asm_bytes('logo_col', logo_col))
b.append(asm_bytes('logo_rle', logo_rle))

# the title's sound (data/music.txt, from the original by tools/sidmusic.py):
# per voice its entries, each a length in pictures and the TED's frequency
# register, low byte and high bits ($FF: a rest); a length of 0 ends the
# voice, which then starts again
TED_CLOCK = 17734470 / 20 / 8                   # PAL: the sound's clock
mus = {'v1': [], 'v2': []}
for l in lines('music.txt'):
    w = l.split()
    if w[0] not in mus:
        sys.exit('music.txt: unknown line ' + l)
    n = mus[w[0]][-1][1] if mus[w[0]] else 1
    for tok in w[1:]:
        hz, _, ln = tok.partition(':')
        if ln:
            n = int(ln)
        if hz == 'r':
            mus[w[0]].append((None, n))
        else:
            reg = min(1023, max(0, round(1024 - TED_CLOCK / int(hz))))
            mus[w[0]].append((reg, n))
for v in ('v1', 'v2'):
    data = []
    for reg, n in mus[v]:
        data += [n, 0, 0xFF] if reg is None else [n, reg & 255, reg >> 8]
    b.append('        .export _mus_' + v)
    b.append(asm_bytes('mus_' + v, data + [0]))
    print('music: %s %d entries, %d pictures' % (v, len(mus[v]), sum(n for r, n in mus[v])))
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
    ['#define NSIDE %d' % NSIDE, '#define SIDE_BASE %d' % SIDE_BASE] + \
    ['#define SFX_%s %d' % (n.upper(), i) for i, n in enumerate(sfx_names)] + \
    ['']
for e in exports:
    if e == 'deck_off':
        h.append('extern const unsigned char *const deck_off[];')
    elif e == 'pre':
        h.append('extern unsigned char pre[];')
    else:
        h.append('extern const unsigned char %s[];' % e)
h.append('/* in the console\'s overlay (console.s) */')
h += ['#define ICON_N %d' % ICON_N, '#define ICON_CODE 1',
      '#define DECK_NAMES ' + ', '.join('"%s"' % n for n in decknames)]
h.append('/* in the title\'s overlay (brief.s) */')
h.append('extern const unsigned char brief_srcs[], brief_top[], brief_bot[], brief_pages[];')
h.append('extern const unsigned char brief_dig[], brief_cap[], brief_misc[];')
h.append('extern const unsigned char logo_font[], logo_col[], logo_rle[];')
h += ['#define SCORE_TOP_AT %d' % score_at[0], '#define SCORE_LOW_AT %d' % score_at[1],
      '#define NLOGO %d' % len(lorder), '#define LOGO_BG %d' % LOGO_BG]
open(os.path.join(GEN, 'data.h'), 'w').write('\n'.join(h) + '\n')
open(os.path.join(GEN, 'tiles.inc'), 'w').write('POOL = %d\n' % POOL)
print('tiles %d, pool %d chars, blocks %d, decks %d bytes, briefing %d bytes, pictures up to %d' % (POOL - 2, 256 - POOL, NBLK, len(allrle), BRIEF_SIZE, pic_max))
