#!/usr/bin/env python3
"""The title picture for the TED: multicolour bitmap above, hires below.

    mkpicture.py <picture.png> <out-dir> [preview.png]
        [--hires-from ROW] [--blank-from ROW] [--up ROWS]

The picture is fitted to 320 x 200. Each pixel of the TED's picture takes
the colour most of the source's pixels under it have, after each is given
the nearest of the TED's 121 colours: the source's soft edges do not turn
into colours of their own. Nearest by the TED's own measure, Y, U and V
(it makes its colours that way), brightness counting three times.

Character rows above ROW (--hires-from, 9) are multicolour bitmap: 160 x
200, a cell of 4 x 8 pixels in four colours - the background ($FF15,
black), one for the whole screen ($FF16, the commonest), two of its own.
Fine lettering with its shadows looks best so. From ROW on hires bitmap:
320 x 200, two colours to a cell of 8 x 8, for the fine detail. The game
switches between the two with a raster interrupt in a gap of black lines
there, so that row's top lines must be black. Rows from --blank-from (18)
on are left black: the game writes its text there (the credits, a line
below them; the foot is the ticker's). --up moves the picture up by whole
rows (its top must be black there); the rows given are after the move.

A cell's colours are in the screen's matrices: its character byte (high
nybble: the colour of multicolour %01 / hires 1, low nybble: %10 / hires
0) and its attribute byte (their luminances, bits 0-2 and 4-6).

Writes to <out-dir>:
  TITLE.B   the bitmap, 8000 bytes (for $C000)
  TITLE.M   the attributes (1000 bytes), $FF15, $FF16, the first hires
            row, 21 bytes of nothing, the characters (1000): for $0800,
            where they are $0800 and $0C00
and with a third argument a preview of what the Plus/4 shows.
"""
import collections
import itertools
import math
import sys

from PIL import Image

# The TED's colours as Yape shows them (video.cpp, tedmem.h)
HUE = [-2, -1, 103, 283, 53, 241, 347, 167, 123, 148, 195, 83, 265, 323, 0, 213]
LUMA = [2.00, 2.4, 2.55, 2.7, 2.9, 3.3, 3.6, 4.1, 4.95]


def ted_rgb(c):
    hue, lum = HUE[c & 15], LUMA[(c >> 4) + 1]
    sat = 0 if hue < 0 else 45.0
    y = 0 if hue == -2 else (min(lum, 5.0) - 2.0) * 255.0 / 3.0
    h = max(hue, 0) * math.pi / 180
    u, v = sat * math.cos(h), sat * math.sin(h)
    r, g, b = y + v / 0.877283, y - 0.39465 * u - 0.58060 * v, y + u / 0.492111
    return tuple(int(max(0, min(255, x))) for x in (r, g, b))


# one of each look: black once, the rest by colour and luminance
COLOURS = [0] + [c for c in range(128) if c & 15]
RGB = {c: ted_rgb(c) for c in COLOURS}


def yuv(rgb):
    r, g, b = rgb
    y = 0.299 * r + 0.587 * g + 0.114 * b
    return (y, 0.492 * (b - y), 0.877 * (r - y))


YUV = {c: yuv(RGB[c]) for c in COLOURS}


def dist(a, b):
    """two TED colours"""
    p, q = YUV[a], YUV[b]
    return 3 * (p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2 + (p[2] - q[2]) ** 2


_near = {}


def nearest(rgb):
    c = _near.get(rgb)
    if c is None:
        p = yuv(rgb)
        c = min(COLOURS, key=lambda k: 3 * (p[0] - YUV[k][0]) ** 2
                + (p[1] - YUV[k][1]) ** 2 + (p[2] - YUV[k][2]) ** 2)
        _near[rgb] = c
    return c


def sample(src, nx, ny):
    """the picture fitted to 320 x 200, as nx x ny TED colours: each the one
    most of the source pixels under it are nearest to"""
    w, h = src.size
    scale = min(320 / w, 200 / h)
    ox, oy = (320 - w * scale) / 2, (200 - h * scale) / 2
    sx, sy = 320 / nx, 200 / ny
    px = src.load()
    out = [[0] * nx for _ in range(ny)]
    for y in range(ny):
        y0, y1 = (y * sy - oy) / scale, ((y + 1) * sy - oy) / scale
        for x in range(nx):
            x0, x1 = (x * sx - ox) / scale, ((x + 1) * sx - ox) / scale
            if x1 <= 0 or y1 <= 0 or x0 >= w or y0 >= h:
                continue
            count = collections.Counter()
            for yy in range(max(0, int(y0)), min(h, math.ceil(y1))):
                for xx in range(max(0, int(x0)), min(w, math.ceil(x1))):
                    r, g, b = px[xx, yy]
                    count[nearest((r | 7, g | 7, b | 7))] += 1
            out[y][x] = count.most_common(1)[0][0]
    return out


def best(cell, fixed, free):
    """the colours for a cell: fixed ones and free more, the least error"""
    freq = collections.Counter(c for c in cell if c not in fixed)
    cand = [c for c, _ in freq.most_common(6)] or [fixed[0] if fixed else 0]
    result = None
    for more in itertools.combinations_with_replacement(cand, free):
        pal = list(fixed) + list(more)
        err = sum(min(dist(p, q) for q in pal) for p in cell)
        if result is None or err < result[0]:
            result = (err, pal)
    return result[1]


def main():
    args = sys.argv[1:]
    hires_from, blank_from = 9, 18
    if '--hires-from' in args:
        i = args.index('--hires-from')
        hires_from = int(args[i + 1])
        del args[i:i + 2]
    if '--blank-from' in args:
        i = args.index('--blank-from')
        blank_from = int(args[i + 1])
        del args[i:i + 2]
    up = 0
    if '--up' in args:
        i = args.index('--up')
        up = int(args[i + 1]) * 8
        del args[i:i + 2]
    src = Image.open(args[0]).convert('RGB')
    out = args[1]

    hi = sample(src, 320, 200)
    mc = sample(src, 160, 200)
    if up:
        if any(any(row) for row in hi[:up] + mc[:up]):
            sys.exit(f'--up: the picture\'s top {up} lines are not black')
        hi = hi[up:] + [[0] * 320 for _ in range(up)]
        mc = mc[up:] + [[0] * 160 for _ in range(up)]
    bg = 0
    count = collections.Counter(c for row in mc[:hires_from * 8] for c in row if c != bg)
    ff16 = count.most_common(1)[0][0] if count else 0x71

    bitmap = bytearray(8000)
    attr = bytearray(1000)
    chars = bytearray(1000)
    shown = Image.new('RGB', (320, 200))
    for cy in range(25):
        for cx in range(40):
            o = cy * 40 + cx
            if cy >= blank_from:
                continue                        # black: the game's text
            if cy < hires_from:
                cell = [mc[cy * 8 + y][cx * 4 + x] for y in range(8) for x in range(4)]
                pal = best(cell, [bg, ff16], 2)
                c1, c2 = pal[2], pal[3]
                chars[o] = ((c1 & 15) << 4) | (c2 & 15)
                attr[o] = ((c2 >> 4) << 4) | (c1 >> 4)
                order = [bg, c1, c2, ff16]      # %00 %01 %10 %11
                for y in range(8):
                    b = 0
                    for x in range(4):
                        p = mc[cy * 8 + y][cx * 4 + x]
                        k = min(range(4), key=lambda i: dist(order[i], p))
                        b |= k << (6 - 2 * x)
                        for d in (0, 1):
                            shown.putpixel((cx * 8 + x * 2 + d, cy * 8 + y), RGB[order[k]])
                    bitmap[o * 8 + y] = b
            else:
                cell = [hi[cy * 8 + y][cx * 8 + x] for y in range(8) for x in range(8)]
                c0, c1 = best(cell, [], 2)
                if c1 == bg:                    # black for 0, where it is
                    c0, c1 = c1, c0
                chars[o] = ((c1 & 15) << 4) | (c0 & 15)
                attr[o] = ((c0 >> 4) << 4) | (c1 >> 4)
                for y in range(8):
                    b = 0
                    for x in range(8):
                        p = hi[cy * 8 + y][cx * 8 + x]
                        one = dist(c1, p) < dist(c0, p)
                        b |= one << (7 - x)
                        shown.putpixel((cx * 8 + x, cy * 8 + y), RGB[c1 if one else c0])
                    bitmap[o * 8 + y] = b
    gap = [y for y in range(hires_from * 8 - 8, hires_from * 8 + 8)
           if not any(hi[y]) and not any(mc[y])]
    open(f'{out}/TITLE.B', 'wb').write(bitmap)
    matrix = attr + bytes([bg, ff16, hires_from]) + bytes(21) + chars
    assert len(matrix) == 2024
    open(f'{out}/TITLE.M', 'wb').write(matrix)
    if len(args) > 2:
        shown.resize((640, 400), Image.NEAREST).save(args[2])
    print(f'picture: $FF15 {bg:02X}, $FF16 {ff16:02X}, hires from row {hires_from}'
          f' (black lines {gap[0] if gap else "-"}-{gap[-1] if gap else "-"})')
    if not [y for y in gap if y >= hires_from * 8]:
        sys.exit(f'row {hires_from} does not start with black lines')


if __name__ == '__main__':
    main()
