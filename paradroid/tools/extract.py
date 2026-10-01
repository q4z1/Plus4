#!/usr/bin/env python3
"""
extract.py - the data of the C64 original, out of a memory dump

Paradroid (Andrew Braybrook, Hewson 1985) keeps everything it needs in
memory once it has loaded. This script reads a dump of the C64's 64 KB,
taken in VICE's monitor while a game is running (`bank ram`,
`save "ram.bin" 0 0000 ffff`, and `bank io`, `save "io.bin" 0 d000 dfff`),
and writes what the Plus/4 version uses as text files into data/:

  blocks.txt     the 32 map blocks, 4 x 4 character codes each
  decks.txt      the 16 decks, 64 x 16 blocks each, one letter per block
  chars.txt      the deck characters as pictures, with their colour
  waypoints.txt  where the droids walk on each deck
  lifts.txt      lift stops: deck, shaft, block position
  droids.txt     the 24 droid types
  ship.txt       how many droids of what class each deck gets
  panel.txt      the status panel above the deck: codes, colours, font
  sideview.txt   the side view of the ship the lifts show
  sprites.txt    lasers and explosion, from its sprites
  briefing.txt   the text pages the original shows before a game

Where the things are in the original's memory was found by tracing it in
VICE; the addresses are below. The tables are copied as they are, the
format of each file is described at its top.
"""
import sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, '..', 'data')

ram = open(sys.argv[1], 'rb').read()
io = open(sys.argv[2], 'rb').read()
if len(ram) == 65538:
    ram = ram[2:]
if len(io) == 4098:
    io = io[2:]

DECKS     = 16
DECK_LO   = 0xF100      # deck data pointers, low bytes; high bytes at +$10
BLOCKS    = 0xE800      # 32 blocks of 4 x 4 codes
FONT      = 0x7800      # deck character set
COLTAB    = 0x0800      # colour of each character code
WP_COUNT  = 0xC800      # waypoints per deck; pointers at $C810/$C820
LIFT_DECK = 0x6CC8      # lift stops 1..30: deck,
LIFT_SHFT = 0x6CE7      #   shaft,
LIFT_COL  = 0x6D07      #   column and
LIFT_ROW  = 0x6D26      #   row in characters
DROID_100 = 0xEA00      # droid types: hundreds digit (= class),
DROID_10  = 0xEA20      #   tens and units as BCD,
DROID_DRV = 0xEA40      #   drive (1, 2, 4, 8),
DROID_COL = 0xEA60      #   colour scheme,
DROID_WPN = 0xEA80      #   weapon (0 none, 1-3)
SHIP_BASE = 0xC830      # lowest class of the first droids on each deck
SHIP_CNT  = 0xF170      # droids per deck, plus one
PANEL_SCR = 0x4800      # screen; the panel is rows 0..5
PANEL_FNT = 0x7000      # its character set
SIDE_MAP  = 0xF180      # the side view: run-length coded, 64 a row
SHAFT_COL = 0x6CB0      # lift shafts in it: column,
SHAFT_TOP = 0x6CB8      #   first row (less 2),
SHAFT_LEN = 0x6CC0      #   rows (low nibble)
SHAFT_CHR = 0xF9        # the character it draws them with

LETTERS = '0123456789abcdefghijklmnopqrstuv'


def deck_blocks(d):
    p = ram[DECK_LO + d] | ram[DECK_LO + 16 + d] << 8
    out = []
    while len(out) < 1024:
        b = ram[p]
        if b & 0x80:
            n = ram[p + 1] or 256
            p += 2
        else:
            n = 1
            p += 1
        out += [b & 0x1F] * n
    return out[:1024]


def write(name, text):
    with open(os.path.join(DATA, name), 'w') as f:
        f.write(text)
    print('data/' + name)


os.makedirs(DATA, exist_ok=True)

# --- blocks -----------------------------------------------------------------
t = ['# The 32 map blocks of the original, 4 x 4 character codes each, top row',
     '# first. "block N L" gives the number and the letter decks.txt uses.', '']
for b in range(32):
    t.append('block %d %s' % (b, LETTERS[b]))
    for y in range(4):
        t.append(' '.join('%02x' % ram[BLOCKS + b * 16 + y * 4 + x] for x in range(4)))
    t.append('')
write('blocks.txt', '\n'.join(t))

# --- decks ------------------------------------------------------------------
t = ['# The 16 decks, 64 x 16 blocks each, one letter per block (blocks.txt).',
     '# A block is 4 x 4 characters, 32 x 32 pixels.', '']
for d in range(DECKS):
    bl = deck_blocks(d)
    t.append('deck %d' % d)
    for y in range(16):
        t.append(''.join(LETTERS[bl[y * 64 + x]] for x in range(64)))
    t.append('')
write('decks.txt', '\n'.join(t))

# --- characters ---------------------------------------------------------------
used = set(ram[BLOCKS:BLOCKS + 512])
# a door opens line by line: its characters with bit 7 clear are the open ones
for b in (1, 2):
    for c in ram[BLOCKS + b * 16:BLOCKS + b * 16 + 16]:
        used.add(c & 0x7F)
t = ['# The deck characters: code, C64 colour (0-15), then 8 lines of pixels.', '']
for c in sorted(used):
    t.append('char %02x col=%d' % (c, ram[COLTAB + c] & 15))
    for y in range(8):
        v = ram[FONT + c * 8 + y]
        t.append(''.join('#' if v & (0x80 >> i) else '.' for i in range(8)))
    t.append('')
write('chars.txt', '\n'.join(t))

# --- waypoints ----------------------------------------------------------------
t = ['# Waypoints: deck, then x,y in characters (always the middle of a block)',
     '# and the directions a droid may leave in, as eight bits:',
     '# 128 left, 64 down-left, 32 down, 16 down-right, 8 right, 4 up-right,',
     '# 2 up, 1 up-left. The droids of a deck start on its waypoints 1, 2, ...', '']
for d in range(DECKS):
    p = ram[WP_COUNT + 0x10 + d] | ram[WP_COUNT + 0x20 + d] << 8
    n = ram[WP_COUNT + d]
    t.append('deck %d' % d)
    for i in range(n):
        x, y, dirs = ram[p + i * 3:p + i * 3 + 3]
        t.append('%d %d %d' % (x, y, dirs))
    t.append('')
write('waypoints.txt', '\n'.join(t))

# --- lifts --------------------------------------------------------------------
t = ['# Lift stops: deck, shaft, block x, block y. Stops of one shaft are listed',
     '# from the top of the ship down; the lift moves between neighbours.', '']
# The original keeps where its window is when the player stands on the lift,
# which is 5 blocks left of and 2 above the lift itself.
for i in range(1, 31):
    t.append('%d %d %d %d' % (ram[LIFT_DECK + i], ram[LIFT_SHFT + i],
                              ram[LIFT_COL + i] // 4 + 5, ram[LIFT_ROW + i] // 4 + 2))
write('lifts.txt', '\n'.join(t) + '\n')

# --- droids -------------------------------------------------------------------
t = ['# The droid types: number, drive (1 2 4 8, the higher the faster),',
     '# weapon (0 none, 1-3), colour scheme of the original.', '']
for i in range(24):
    num = ram[DROID_100 + i] * 100 + (ram[DROID_10 + i] >> 4) * 10 + (ram[DROID_10 + i] & 15)
    t.append('%03d %d %d %d' % (num, ram[DROID_DRV + i], ram[DROID_WPN + i], ram[DROID_COL + i]))
write('droids.txt', '\n'.join(t) + '\n')

# --- ship ---------------------------------------------------------------------
t = ['# Per deck: the lowest droid type of its first six droids (index into',
     '# droids.txt, before the ship level is added) and how many droids it has.', '']
for d in range(DECKS):
    t.append('%d %d %d' % (d, ram[SHIP_BASE + d], ram[SHIP_CNT + d] - 1))
write('ship.txt', '\n'.join(t) + '\n')

# --- panel --------------------------------------------------------------------
codes = [ram[PANEL_SCR + i] for i in range(6 * 40)]
cols = [io[0x800 + i] & 15 for i in range(6 * 40)]
# all of its character set that is not empty: the text in it is two lines
# tall and uses most of it
pused = set(c for c in range(256) if any(ram[PANEL_FNT + c * 8:PANEL_FNT + c * 8 + 8]))
pused |= set(codes)
t = ['# The status panel: 6 rows of 40 codes, then their C64 colours, then the',
     '# characters it uses. Text in it is two lines tall: code c on top, c+128',
     '# below. Digits are 0-9, letters a-z are $0a-$23.', '']
for y in range(6):
    t.append('codes ' + ' '.join('%02x' % c for c in codes[y * 40:y * 40 + 40]))
for y in range(6):
    t.append('cols ' + ''.join('%x' % c for c in cols[y * 40:y * 40 + 40]))
t.append('')
for c in sorted(pused):
    t.append('char %02x' % c)
    for y in range(8):
        v = ram[PANEL_FNT + c * 8 + y]
        t.append(''.join('#' if v & (0x80 >> i) else '.' for i in range(8)))
    t.append('')
write('panel.txt', '\n'.join(t))

# --- side view ------------------------------------------------------------------
p = SIDE_MAP
codes = []
while len(codes) < 64 * 17:
    b = ram[p]
    if b & 0x80:
        n = ram[p + 1] or 256
        p += 2
    else:
        n = 1
        p += 1
    c = b & 0x7F
    codes += [0 if c == 0x29 else c] * n
rows = [codes[y * 64 + 3:y * 64 + 42] for y in range(13)]
used = sorted(set(c for r in rows for c in r if c) | {SHAFT_CHR})
t = ['# The side view of the ship the lifts show: 13 rows of 39 character',
     '# codes (rows from screen row 8 down), then the shafts: column, first',
     '# row, rows. Then the characters with their C64 colour; colour 8 or',
     '# more means multicolour, as on the C64. The lift shafts are drawn with',
     '# character %02x.' % SHAFT_CHR, '']
for r in rows:
    t.append('row ' + ' '.join('%02x' % c for c in r))
for k in range(8):
    t.append('shaft %d %d %d' % (ram[SHAFT_COL + k] + 1, ram[SHAFT_TOP + k] + 2,
                                 ram[SHAFT_LEN + k] & 15))
t.append('')
for c in used:
    t.append('char %02x col=%d' % (c, ram[COLTAB + c] & 15))
    for y in range(8):
        v = ram[FONT + c * 8 + y]
        t.append(''.join('#' if v & (0x80 >> i) else '.' for i in range(8)))
    t.append('')
write('sideview.txt', '\n'.join(t))

# --- sprites --------------------------------------------------------------------
# Sprites in the VIC's bank at $4000. The lasers are hires, two bolts side
# by side; the explosion is multicolour, from a spark to the last embers.
SPRITES = [('laser_h', 0x91, 0), ('laser_d2', 0x93, 0), ('laser_v', 0x95, 0),
           ('laser_d1', 0x97, 0)] + \
          [('explo%d' % i, b, 1) for i, b in enumerate((0x39, 0x3B, 0x3C, 0x3E, 0x40, 0x42))]
t = ['# Sprites of the original: name, then 21 rows. Hires ones in # and .,',
     '# multicolour ones in 0-3 (two pixels each).', '']
for name, blk, multi in SPRITES:
    a = 0x4000 + blk * 64
    t.append('sprite %s %s' % (name, 'mc' if multi else 'hires'))
    for y in range(21):
        b = ram[a + y * 3:a + y * 3 + 3]
        if multi:
            t.append(''.join('0123'[(v >> (6 - 2 * k)) & 3] for v in b for k in range(4)))
        else:
            t.append(''.join('#' if v & (0x80 >> k) else '.' for v in b for k in range(8)))
    t.append('')
write('sprites.txt', '\n'.join(t))

# --- briefing ---------------------------------------------------------------------
# At $D000: pages of text, each line as row + $80, column, the characters
# (the panel's font) and $FF. Codes from $3A on are wide letters, drawn as
# the code and the code + $20 beside it: the capitals from $3A, and m and w
# at $42 and $54. Their narrow places hold I ($16) and (c) ($20, '@' here). The rows grow down a page; a smaller one
# starts the next. Pages 0-3 are the briefing; 4 (scores, keys) and 5
# (credits) belong to the original's own title and are left out.
TXT_MAP = {0x16: 'I', 0x20: '@', 0x42: 'm', 0x54: 'w', 0x28: '.', 0x29: ',', 0x2a: ':',
           0x2d: "'", 0x2e: '-', 0x30: ' '}
def txt_char(b):
    if b in TXT_MAP:
        return TXT_MAP[b]
    if b < 10:
        return str(b)
    if b < 0x24:
        return chr(97 + b - 10)
    if 0x3a <= b <= 0x53:
        return chr(65 + b - 0x3a)
    return '?'

p = 0xD000
pages, cur, last = [], [], -1
while ram[p] >= 0x80 and ram[p] != 0xFF:
    row = ram[p] & 0x7F
    col = ram[p + 1] % 40
    p += 2
    q = p
    while ram[q] != 0xFF:
        q += 1
    if row < last:
        pages.append(cur)
        cur = []
    last = row
    cur.append((row, col, ''.join(txt_char(b) for b in ram[p:q])))
    p = q + 1
pages.append(cur)
t = ['# The original\'s briefing: per page, lines as "row col text" (rows in',
     '# the original\'s steps of two, columns of 40).', '']
for k, pg in enumerate(pages[:4]):
    t.append('page %d' % k)
    for row, col, text in pg:
        t.append('%d %d %s' % (row, col, text.rstrip()))
    t.append('')
write('briefing.txt', '\n'.join(t))
