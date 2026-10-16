#!/usr/bin/env python3
"""The game's tall characters, 16 pixels high, two characters each - the
top one in a screen row, the bottom one in the row under it:

  the station signs   a sign's letters: dark on a light plate, as on an
                      enamel station sign, in the narrow lettering of
                      DIN 1451; the plate's two rounded ends
  the flap digits     the clock and the score at the top of the screen:
                      the digits of a split-flap board, a gap across them
                      where the flaps meet
  the stopwatch       the game's speed: the factor on its dial (a pair of
                      bars for the pause), one for each speed
  the star            before the score

    mkfont.py <out.s>

Writes each different half (8 bytes) once, in sg_halves; for every sign
and every digit the numbers of its top and bottom halves. Half 0 is the
empty one: the game shows a space for it (signs.s gives the others their
characters as a level needs them).
"""
import sys

# The letters: 6 pixels wide (M and W 7), 9 high, strokes 2 wide down and
# 1 across - the ROM's weight, taller. Space is the plate alone.
B = 'XX..XX'
SIGN = {
    ' ': [],
    'A': ['.XXXX.', B, B, B, 'XXXXXX', B, B, B, B],
    'B': ['XXXXX.', B, B, B, 'XXXXX.', B, B, B, 'XXXXX.'],
    'C': ['.XXXX.', B, 'XX', 'XX', 'XX', 'XX', 'XX', B, '.XXXX.'],
    'D': ['XXXXX.', B, B, B, B, B, B, B, 'XXXXX.'],
    'E': ['XXXXXX', 'XX', 'XX', 'XX', 'XXXXX', 'XX', 'XX', 'XX', 'XXXXXX'],
    'F': ['XXXXXX', 'XX', 'XX', 'XX', 'XXXXX', 'XX', 'XX', 'XX', 'XX'],
    'G': ['.XXXX.', B, 'XX', 'XX', 'XX.XXX', B, B, B, '.XXXXX'],
    'H': [B, B, B, B, 'XXXXXX', B, B, B, B],
    'I': ['..XX'] * 9,
    'J': ['....XX'] * 6 + [B, B, '.XXXX.'],
    'K': [B, B, 'XX.XX.', 'XXXX', 'XXX', 'XXXX', 'XX.XX.', B, B],
    'L': ['XX'] * 8 + ['XXXXXX'],
    'M': ['XX...XX', 'XXX.XXX', 'XXXXXXX', 'XX.X.XX'] + ['XX...XX'] * 5,
    'N': [B, 'XXX.XX', 'XXX.XX', 'XXXXXX', 'XX.XXX', 'XX.XXX', B, B, B],
    'O': ['.XXXX.'] + [B] * 7 + ['.XXXX.'],
    'P': ['XXXXX.', B, B, B, 'XXXXX.', 'XX', 'XX', 'XX', 'XX'],
    'Q': ['.XXXX.', B, B, B, B, B, 'XX.XXX', 'XX..XX', '.XXX.X'],
    'R': ['XXXXX.', B, B, B, 'XXXXX.', 'XX.XX.', B, B, B],
    'S': ['.XXXX.', B, 'XX', 'XX', '.XXXX.', '....XX', '....XX', B, '.XXXX.'],
    'T': ['XXXXXX'] + ['..XX'] * 8,
    'U': [B] * 8 + ['.XXXX.'],
    'V': [B] * 7 + ['.XXXX.', '..XX'],
    'W': ['XX...XX'] * 5 + ['XX.X.XX', 'XXXXXXX', 'XXX.XXX', 'XX...XX'],
    'X': [B, B, B, '.XXXX.', '..XX', '.XXXX.', B, B, B],
    'Y': [B, B, B, '.XXXX.'] + ['..XX'] * 5,
    'Z': ['XXXXXX', '....XX', '....XX', '...XX', '..XX', '.XX', 'XX', 'XX', 'XXXXXX'],
}
PLATE = (2, 14)         # the plate's rows (of 16)
LETTER_TOP = 4          # the letters' first row
CAP_W = 3               # an end of the plate: pixels of it

# The digits: 6 wide, 12 high (rows 2-13), strokes 2 wide both ways
D = 'XX..XX'
BIG = {
    '0': ['.XXXX.', 'XXXXXX'] + [D] * 8 + ['XXXXXX', '.XXXX.'],
    '1': ['...XX', '..XXX', '.XXXX', 'XX.XX'] + ['...XX'] * 8,
    '2': ['.XXXX.', 'XXXXXX', D, '....XX', '....XX', '...XX.', '..XX..', '.XX...',
          'XX....', 'XX....', 'XXXXXX', 'XXXXXX'],
    '3': ['.XXXX.', 'XXXXXX', D, '....XX', '....XX', '..XXX.', '..XXX.', '....XX',
          '....XX', D, 'XXXXXX', '.XXXX.'],
    '4': ['...XX.', '..XXX.', '.XXXX.', 'XX.XX.', 'XX.XX.', 'XX.XX.', 'XXXXXX', 'XXXXXX',
          '...XX.', '...XX.', '...XX.', '...XX.'],
    '5': ['XXXXXX', 'XXXXXX', 'XX....', 'XX....', 'XXXXX.', 'XXXXXX', '....XX', '....XX',
          '....XX', D, 'XXXXXX', '.XXXX.'],
    '6': ['.XXXX.', 'XXXXX.', 'XX....', 'XX....', 'XXXXX.', 'XXXXXX', D, D, D, D,
          'XXXXXX', '.XXXX.'],
    '7': ['XXXXXX', 'XXXXXX', '....XX', '....XX', '...XX.', '...XX.', '..XX..', '..XX..',
          '..XX..', '.XX...', '.XX...', '.XX...'],
    '8': ['.XXXX.', 'XXXXXX', D, D, 'XXXXXX', '.XXXX.', 'XXXXXX', D, D, D,
          'XXXXXX', '.XXXX.'],
    '9': ['.XXXX.', 'XXXXXX', D, D, D, 'XXXXXX', '.XXXXX', '....XX', '....XX', '....XX',
          '.XXXXX', '.XXXX.'],
    ':': ['', '', '..XX', '..XX', '', '', '', '', '..XX', '..XX', '', ''],
    '-': ['', '', '', '', '.XXXX', '.XXXX', '', '', '', '', '', ''],
    ' ': [],
}
BIG_ORDER = '0123456789:- '

# The stopwatch, 16 x 16, two characters wide: its crown on top and the
# button beside it; on its dial, in the lower half, the speed (trainschedule.s's
# speeds: the pause, x1, x3, x10) in small letters 5 high
WATCH = [
    '......XXXX......',
    '.......XX....XX.',
    '.....XXXXXX.XX..',
    '...XX......XX...',
    '..X..........X..',
    '.X............X.',
    '.X............X.',
    'XX............XX',
    'XX............XX',
    'XX............XX',
    'XX............XX',
    '.X............X.',
    '.X............X.',
    '..X..........X..',
    '...XX......XX...',
    '.....XXXXXX.....',
]
SMALL = {'x': ['', '', 'X.X', '.X.', 'X.X'], '1': ['.X', 'XX', '.X', '.X', '.X'],
         '3': ['XXX', '..X', '.XX', '..X', 'XXX'], '0': ['XXX', 'X.X', 'X.X', 'X.X', 'XXX'],
         '|': ['XX'] * 5, ' ': ['']}
SPEEDS = ['| |', 'x1', 'x3', 'x10']
DIAL_TOP = 8            # the dial's text: rows 8-12, all in the lower half

# The star before the score, the digits' height
STAR = [
    '', '',
    '.......XX.......',
    '......XXXX......',
    '......XXXX......',
    '.XXXXXXXXXXXXXX.',
    '..XXXXXXXXXXXX..',
    '....XXXXXXXX....',
    '....XXXXXXXX....',
    '....XXXXXXXX....',
    '...XXXXXXXXXX...',
    '...XXXX..XXXX...',
    '..XXX......XXX..',
    '..X..........X..',
]
BIG_TOP = 2             # the digits' first row
GAP = 8                 # the row left out: where the flaps meet


def row_bits(r, x):
    v = 0
    for i, c in enumerate(r):
        if c == 'X':
            v |= 0x80 >> (x + i)
    return v


def sign_glyph(ch):
    rows = SIGN[ch]
    width = max([len(r.rstrip('.')) for r in rows] + [0])
    x = 1 if width <= 6 else 0            # M and W start at the left
    out = []
    for y in range(16):
        r = rows[y - LETTER_TOP] if 0 <= y - LETTER_TOP < len(rows) else ''
        out.append(0xFF ^ row_bits(r, x) if PLATE[0] <= y <= PLATE[1] else 0)
    return out


def cap_glyph(left):
    out = []
    for y in range(16):
        if not PLATE[0] <= y <= PLATE[1]:
            out.append(0)
            continue
        w = CAP_W - (1 if y in PLATE else 0)  # its corners rounded
        v = (1 << w) - 1
        out.append(v if left else (v << (8 - w)) & 0xFF)
    return out


def big_glyph(ch):
    rows = BIG[ch]
    out = []
    for y in range(16):
        r = rows[y - BIG_TOP] if 0 <= y - BIG_TOP < len(rows) else ''
        out.append(0 if y == GAP else row_bits(r, 1))
    return out


def wide(rows):
    """a 16 x 16 picture as its two columns, each 16 bytes"""
    rows = [r.ljust(16, '.') for r in rows] + ['.' * 16] * (16 - len(rows))
    return [[row_bits(r[c * 8:c * 8 + 8], 0) for r in rows] for c in (0, 1)]


def watch(text):
    g = [list(r) for r in WATCH]
    w = sum(max(len(r) for r in SMALL[c]) for c in text) + len(text) - 1
    x0 = 8 - (w + 1) // 2
    for c in text:
        rows = SMALL[c]
        for j, r in enumerate(rows):
            for i, ch in enumerate(r):
                if ch == 'X':
                    g[DIAL_TOP + j][x0 + i] = 'X'
        x0 += max(len(r) for r in rows) + 1
    return wide([''.join(r) for r in g])


def main():
    out = sys.argv[1]
    halves = [bytes(8)]                   # 0: the empty half

    def half(b):
        b = bytes(b)
        if b not in halves:
            halves.append(b)
        return halves.index(b)

    # the signs by their number: 0 the plate alone, 1-26 the letters A-Z
    # (their screen codes), 27 the plate's left end, 28 its right end
    signs = [sign_glyph(' ')] + [sign_glyph(chr(65 + i)) for i in range(26)]
    signs += [cap_glyph(True), cap_glyph(False)]
    signs += [sign_glyph(' ')] * 3
    st = [half(g[:8]) for g in signs]
    sb = [half(g[8:]) for g in signs]
    bigs = [big_glyph(c) for c in BIG_ORDER]
    bt = [half(g[:8]) for g in bigs]
    bb = [half(g[8:]) for g in bigs]
    watches = [watch(t) for t in SPEEDS]
    assert all(w[c][:8] == watches[0][c][:8] for w in watches for c in (0, 1))
    wt = [half(watches[0][c][:8]) for c in (0, 1)]
    wb = [half(w[c][8:]) for w in watches for c in (0, 1)]
    star = wide(STAR)
    xt = [half(star[c][:8]) for c in (0, 1)]
    xb = [half(star[c][8:]) for c in (0, 1)]
    assert len(halves) < 128

    def table(name, vals):
        return '%s: .byte %s\n' % (name, ', '.join(str(v) for v in vals))

    with open(out, 'w') as f:
        f.write('; made by tools/mkfont.py - the station signs and the flap digits\n')
        f.write('        .export sg_halves, sg_ti, sg_bi, bg_ti, bg_bi, SG_HALVES\n')
        f.write('        .export wt_ti, wt_bi, xs_ti, xs_bi\n')
        f.write('SG_HALVES = %d\n' % len(halves))
        f.write('        .rodata\n')
        f.write('; the halves, 8 bytes each\n')
        f.write('sg_halves:\n')
        for h in halves:
            f.write('        .byte %s\n' % ', '.join('$%02X' % b for b in h))
        f.write('; a sign\'s top and bottom halves: 0 the plate, 1-26 A-Z, 27 and\n')
        f.write('; 28 the plate\'s left and right ends, 29-31 the plate\n')
        f.write(table('sg_ti', st))
        f.write(table('sg_bi', sb))
        f.write('; a digit\'s: 0-9, 10 the colon, 11 the minus, 12 the space\n')
        f.write(table('bg_ti', bt))
        f.write(table('bg_bi', bb))
        f.write('; the stopwatch\'s top halves, left and right (the same at every\n')
        f.write('; speed), and its lower ones: speed * 2 + its column\n')
        f.write(table('wt_ti', wt))
        f.write(table('wt_bi', wb))
        f.write('; the star\'s: left, right\n')
        f.write(table('xs_ti', xt))
        f.write(table('xs_bi', xb))
    print('%s: %d halves' % (out, len(halves)))


if __name__ == '__main__':
    main()
