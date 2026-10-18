#!/usr/bin/env python3
"""mkhelp.py <help.txt> <out.s>: the page of help (help.s) and the bulb that
opens it, as ca65 source for the overlay (segment OVLDATA).

The page is drawn in the TED's extended colour mode: a character's top two
bits choose its background - 0 black (outside the page), 1 the paper, 2 a
heading's band, 3 a key's cap - and its glyph is one of the 64 below. Each
row of the page is one of a few kinds (help.s draws it): black, the page's
top or bottom edge, or the paper with text from column TEXT_COL on, as many
codes as the row has (the rest is paper). A heading's row is its band.

  help_doc      the rows: kind, then for text and headings the number of
                bytes and the bytes: a code, or below 64 that many columns
                left as they are (paper, or the band), for runs of spaces
  HELP_ROWS     how many
  bulb_lit, bulb_dim
                the bulb, 24 x BULB_H pixels: 3 bytes a pixel row, lit
                (with its rays) and once the page has been read
"""
import re
import sys

WIDTH = 34                      # the text's columns: 3-36 (help.s TEXT_COL)
K_BLACK, K_TOP, K_BOTTOM, K_TEXT, K_HEAD = range(5)
PAPER, BAND, CAP = 64, 128, 192
BANNED = set('@[]#$%^_&*;<=>')  # their glyphs are the frame's (help.s)


def code(c, where):
    if c in BANNED or not (c == ' ' or 'A' <= c <= 'Z' or '!' <= c <= '?'):
        sys.exit(f"mkhelp: '{c}' cannot be on the page ({where})")
    o = ord(c)
    return o - 64 if 'A' <= c <= 'Z' else o


def tokens(text):
    """words and key caps: (width, codes)"""
    out = []
    for m in re.finditer(r'(\[[^\]]+\])|(\S+)', text.upper()):
        if m.group(1):
            k = ' ' + m.group(1)[1:-1] + ' '
            out.append([code(c, text) | CAP for c in k])
        else:
            out.append([code(c, text) | PAPER for c in m.group(2)])
    return out


def keyline(text, where):
    """a line as it is: words, spaces and caps where they are put"""
    codes = []
    for part in re.split(r'(\[[^\]]+\])', text.upper()):
        if part.startswith('['):
            codes += [code(c, where) | CAP for c in ' ' + part[1:-1] + ' ']
        else:
            codes += [code(c, where) | PAPER for c in part]
    while codes and codes[-1] == 32 | PAPER:
        codes.pop()
    if len(codes) > WIDTH:
        sys.exit(f"mkhelp: too long by {len(codes) - WIDTH}: {where}")
    return codes


def wrap(text):
    rows, row = [], []
    for t in tokens(text):
        need = len(t) + (1 if row else 0)
        if row and len(row) + need > WIDTH:
            rows.append(row)
            row = []
        if row:
            row.append(32 | PAPER)
        if len(t) > WIDTH:
            sys.exit(f"mkhelp: a word too long: {text}")
        row += t
    if row:
        rows.append(row)
    return rows


def page(lines):
    rows = [(K_BLACK, []), (K_TOP, [])]
    para = []

    def flush():
        if para:
            rows.extend((K_TEXT, r) for r in wrap(' '.join(para)))
            para.clear()

    for n, line in enumerate(lines, 1):
        line = line.rstrip('\n')
        if line.startswith('# ') or line == '#':
            continue
        where = f"line {n}"
        if not line.strip():
            flush()
            rows.append((K_TEXT, []))
        elif line.startswith('='):
            flush()
            t = line[1:].strip().upper()
            pad = (WIDTH - len(t)) // 2
            rows.append((K_HEAD, [32 | BAND] * pad + [code(c, where) | BAND for c in t]))
        elif line.startswith(':'):
            flush()
            rows.append((K_TEXT, keyline(line[1:], where)))
        else:
            para.append(line.strip())
    flush()
    rows += [(K_TEXT, []), (K_BOTTOM, []), (K_BLACK, [])]
    while len(rows) < 26:
        rows.append((K_BLACK, []))
    return rows


# The bulb's left half, 12 columns: the right one is its mirror image. The
# glass and its rays; the lit one has a highlight cleared in it.
BULB = [
    "...........#",
    "...........#",
    "...#........",
    "....#...####",
    ".......#####",
    "......######",
    "##....######",
    "......######",
    "......######",
    ".......#####",
    "........####",
    ".........###",
    "........####",
    ".........###",
    "........####",
    ".........###",
    "..........##",
]
RAYS = {(0, 11), (1, 11), (2, 3), (3, 4), (6, 0), (6, 1)}
GLASS_ROWS = range(3, 11)
HIGHLIGHT = [(5, 8), (6, 8), (4, 9)]


def bulb():
    full = []
    for y, half in enumerate(BULB):
        row = [c == '#' for c in half]
        full.append(row + row[::-1])
    lit = [r[:] for r in full]
    for y, x in HIGHLIGHT:
        lit[y][x] = False
    dim = [r[:] for r in full]
    for y, x in RAYS:
        dim[y][x] = dim[y][23 - x] = False
    # read: the glass only outlined
    for y in GLASS_ROWS:
        for x in range(24):
            if full[y][x] and (y, min(x, 23 - x)) not in RAYS:
                inside = all(0 <= y + dy < len(full) and 0 <= x + dx < 24
                             and full[y + dy][x + dx]
                             and (y + dy, min(x + dx, 23 - x - dx)) not in RAYS
                             for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)))
                if inside and y > GLASS_ROWS[0]:
                    dim[y][x] = False
    return lit, dim


def rows_bytes(img):
    out = []
    for r in img:
        for b in range(3):
            v = 0
            for i in range(8):
                v = v << 1 | r[b * 8 + i]
            out.append(v)
    return out


def packed(kind, codes):
    """runs of the row's own space as the number of them"""
    space = 32 | (BAND if kind == K_HEAD else PAPER)
    out, run = [], 0
    for c in codes:
        if c == space:
            run += 1
            continue
        if run:
            out.append(run)
            run = 0
        out.append(c)
    return out


def main():
    src, out = sys.argv[1:]
    rows = page(open(src).readlines())
    lit, dim = bulb()
    with open(out, 'w') as f:
        f.write("; made by tools/mkhelp.py from %s - do not edit\n" % src)
        f.write("        .export help_doc, bulb_lit, bulb_dim\n")
        f.write("        .exportzp HELP_ROWS, BULB_H\n")
        f.write("HELP_ROWS = %d\nBULB_H = %d\n" % (len(rows), len(BULB)))
        f.write('        .segment "OVLDATA"\nhelp_doc:\n')
        for kind, codes in rows:
            codes = packed(kind, codes)
            b = [kind] + ([len(codes)] + codes if kind in (K_TEXT, K_HEAD) else [])
            f.write("        .byte %s\n" % ", ".join("$%02X" % v for v in b))
        for name, img in (("bulb_lit", lit), ("bulb_dim", dim)):
            f.write("%s:\n" % name)
            bs = rows_bytes(img)
            for i in range(0, len(bs), 12):
                f.write("        .byte %s\n" % ", ".join("$%02X" % v for v in bs[i:i + 12]))
    size = sum(1 + (1 + len(packed(k, c)) if k in (K_TEXT, K_HEAD) else 0) for k, c in rows)
    print(f"help: {len(rows)} rows, {size} bytes")


if __name__ == '__main__':
    main()
