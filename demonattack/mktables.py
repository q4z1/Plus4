#!/usr/bin/env python3
"""
mktables.py - the tables Demon Attack only ever reads, made at build time.

Everything here is worked out from a handful of formulas and from the
original's own shapes (rom_hi in demonattack.c), and it never changes while
the game runs. Made once here instead of at start-up, it can sit in ROM:
that is what lets the game fit a 16 KB C16 with a 32 KB cartridge, and the
PRG uses the very same tables.

    python3 mktables.py demonattack.c > build/tables.s
"""
import re
import sys


def rom_bytes(c_source):
    """rom_hi[] out of demonattack.c: the cartridge's $1D88-$1FFF."""
    body = re.search(r'rom_hi\[0x278\]\s*=\s*\{(.*?)\};', c_source, re.S).group(1)
    body = re.sub(r'/\*.*?\*/', '', body, flags=re.S)
    vals = [int(v, 16) for v in re.findall(r'0x([0-9A-Fa-f]{2})', body)]
    assert len(vals) == 0x278, len(vals)
    return vals


def main():
    rom_hi = rom_bytes(open(sys.argv[1]).read())

    def rom(a):
        return rom_hi[a - 0x1D88]

    # sh_tab[sub*3+k][b]: the 8 pixels of b, two bits each (%11 for a set
    # one), after sub empty multicolour pixels: 24 bits over three bytes
    sh = [[0] * 256 for _ in range(12)]
    for b in range(256):
        w = 0
        for bit in range(8):
            w = (w << 2) | (3 if b & (0x80 >> bit) else 0)
        for sub in range(4):
            x = w << (2 * (4 - sub))
            sh[sub * 3 + 0][b] = (x >> 16) & 255
            sh[sub * 3 + 1][b] = (x >> 8) & 255
            sh[sub * 3 + 2][b] = x & 255

    rev = [int(f'{b:08b}'[::-1], 2) for b in range(256)]
    code_lo = [(c << 3) & 255 for c in range(256)]
    code_hi = [c >> 5 for c in range(256)]

    # pixel of a position byte: 12 + 15 * coarse - fine, fine signed
    pixtab = []
    for i in range(256):
        h = i >> 4
        s = h if h < 8 else h - 16
        pixtab.append((12 + 15 * (i & 15) - s + 160) % 160)

    # $1CCF / $1CDE: one pixel right / left in the positioning format
    right_of, left_of = [], []
    for a in range(256):
        b = (a - 0x10) & 255
        if not (b & 0x80) and b >= 0x70:
            b = (b + 0xF1) & 255
        right_of.append(b)
        b = (a + 0x10) & 255
        if (b & 0x80) and b < 0x90:
            b = (b - 0xF1) & 255
        left_of.append(b)

    # every demon picture at each of the four pixels in a character: five
    # columns of eight lines, column by column - both halves side by side,
    # the right one mirrored
    FRAMES = 28
    demon_img, demon_rows = [], []
    for f in range(FRAMES):
        for sub in range(4):
            t0, t1, t2 = sh[sub * 3], sh[sub * 3 + 1], sh[sub * 3 + 2]
            cols = [[0] * 8 for _ in range(5)]
            for i in range(8):
                g = rom(0x1E00 + (f << 3) + 7 - i)
                r = rev[g]
                cols[0][i] = t0[g]
                cols[1][i] = t1[g]
                cols[2][i] = t2[g] | t0[r]
                cols[3][i] = t1[r]
                cols[4][i] = t2[r]
            rows = [0] * 5
            for c in range(5):
                for i in range(8):
                    if cols[c][i]:
                        rows[c] |= 0x80 >> i
            for c in range(5):
                demon_img += cols[c]
            demon_rows += rows

    band_tab = []
    for f in range(64):
        v = 0
        for i in range(8):
            if rom(0x1E00 + (f << 3) + 7 - i):
                v |= 0x80 >> i
        band_tab.append(v)

    # the cannon at each of the four pixels: six characters, column by
    # column, row 21 then row 22; it stands on lines 4..15 of the 16
    cannon_img = []
    for sub in range(4):
        p = [0] * 48
        for c in range(3):
            t = sh[sub * 3 + c]
            for i in range(12):
                p[c * 16 + 4 + i] = t[rom(0x1D88 + 11 - i)]
        cannon_img += p

    # TED values for each kind of 2600 voice and each AUDF: 1024 - k * (F+1)
    tone_lo, tone_hi = [], []
    for k in (7, 21, 28, 43):
        for f in range(32):
            r = k * (f + 1)
            r = 0 if r >= 1024 else 1024 - r
            tone_lo.append(r & 255)
            tone_hi.append(r >> 8)

    out = []
    w = out.append
    w('; made by mktables.py - do not edit, change the generator')
    w('        .export sh_tab, _sh_tab, _rev, code_lo, code_hi')
    w('        .export _pixtab, _right_of, _left_of')
    w('        .export _demon_img, _demon_rows, _img_lo, _img_hi, _rows_lo, _rows_hi')
    w('        .export _band_tab, _cannon_img, _tone_lo, _tone_hi')
    w('')
    w('        .segment "TABLES"')

    def table(name, data):
        w(f'{name}:')
        for i in range(0, len(data), 16):
            w('        .byte ' + ', '.join(f'${v:02X}' for v in data[i:i + 16]))

    w('        .align 256')
    w('sh_tab:')
    w('_sh_tab:')
    for k in range(12):
        table(f'sh_{k}', sh[k])
    table('_rev', rev)
    table('code_lo', code_lo)
    table('code_hi', code_hi)
    table('_pixtab', pixtab)
    table('_right_of', right_of)
    table('_left_of', left_of)
    table('_demon_img', demon_img)
    table('_demon_rows', demon_rows)
    n = FRAMES * 4
    w('_img_lo:')
    for i in range(0, n, 8):
        w('        .byte ' + ', '.join(f'<(_demon_img+{j * 40})' for j in range(i, min(n, i + 8))))
    w('_img_hi:')
    for i in range(0, n, 8):
        w('        .byte ' + ', '.join(f'>(_demon_img+{j * 40})' for j in range(i, min(n, i + 8))))
    w('_rows_lo:')
    for i in range(0, n, 8):
        w('        .byte ' + ', '.join(f'<(_demon_rows+{j * 5})' for j in range(i, min(n, i + 8))))
    w('_rows_hi:')
    for i in range(0, n, 8):
        w('        .byte ' + ', '.join(f'>(_demon_rows+{j * 5})' for j in range(i, min(n, i + 8))))
    table('_band_tab', band_tab)
    table('_cannon_img', cannon_img)
    table('_tone_lo', tone_lo)
    table('_tone_hi', tone_hi)
    print('\n'.join(out))


main()
