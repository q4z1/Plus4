#!/usr/bin/env python3
"""forest.py - how the forest tiles in data/tiles_outdoor.txt were made.

A wood seen from above: leaf clusters on a canvas of 2 x 2 tiles that
wraps around, drawn back to front, lit from the top left - a crescent of
the background colour (light: the grass's green, in autumn orange, in
winter white, so the wood follows the season), the cell's dark green as
the body, the dark colour as the shadowed rim and the gaps.

From that canvas: the inside of a wood (four tiles, chosen by the
parity of x and y, so it never repeats next to itself), and its edges
towards the grass: open to the north, south (with trunks and a shadow),
west, east, and the four corners. tools/mkdata.py picks the right one for
every tree of a room from its neighbours (rooms.txt stays a 'T').

    tools/forest.py > /tmp/forest.txt     then paste into tiles_outdoor.txt
    tools/forest.py --png out.png         a picture of a patch of wood
"""
import math
import random
import sys

W, H = 16, 32           # multicolour pixels, lines: 2 x 2 tiles


def canopy(seed=3):
    rnd = random.Random(seed)
    cl = []
    rows, cols = 5, 3
    for r in range(rows):
        for c in range(cols):
            x = (c * W / cols + (r % 2) * W / cols / 2 + rnd.uniform(-0.7, 0.7)) % W
            y = (r * H / rows + rnd.uniform(-1, 1)) % H
            cl.append((y, x, rnd.uniform(2.7, 3.2), rnd.uniform(5.0, 6.0)))
    cl.sort()                                   # back (top) to front (bottom)
    g = [['x'] * W for _ in range(H)]
    for (cy, cx, rx, ry) in cl:
        for yy in range(-9, 10):
            for xx in range(-5, 6):
                y, x = int(cy + yy) % H, int(cx + xx) % W
                dx = (int(cx + xx) + 0.5 - cx) / rx
                dy = (int(cy + yy) + 0.5 - cy) / ry
                d = math.hypot(dx, dy)
                if d > 1.0:
                    continue
                lit = -(dx * 0.7 + dy) / max(d, 0.01)
                if d > 0.72 and lit < 0.1:
                    ch = 'x'                    # the shadowed rim
                elif d > 0.45 and lit > 0.75:
                    ch = '.'                    # a crescent of light
                else:
                    ch = '#'
                g[y][x] = ch
    return g


# the edge's way in and out: how far the leaves reach, per column or line
BUMP_S = [1, 2, 2, 1, 0, 1, 2, 1]               # lines short of line 11
BUMP_N = [1, 0, 0, 1, 2, 1, 0, 1]               # lines below line 3
BUMP_W = [1, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 0, 1]
BUMP_E = [0, 0, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0]
TRUNKS = ((2,), (5,))                           # columns of the trunks, by x parity


def tile(g, px, py, op):
    """the tile at parity px, py of the canvas, open to the sides in op"""
    t = [list(''.join(g[py * 16 + y][px * 8:px * 8 + 8])) for y in range(16)]
    inside = [[True] * 8 for _ in range(16)]
    for y in range(16):
        for x in range(8):
            if 'S' in op and y > 10 - BUMP_S[x]:
                inside[y][x] = False
            if 'N' in op and y < 3 + BUMP_N[x]:
                inside[y][x] = False
            if 'W' in op and x < 1 + BUMP_W[y]:
                inside[y][x] = False
            if 'E' in op and x > 6 - BUMP_E[y]:
                inside[y][x] = False
    for y in range(16):
        for x in range(8):
            if inside[y][x]:
                # the rim against the grass: dark below and to the right,
                # the body's green above and to the left
                if ('S' in op and (y == 15 or not inside[y + 1][x])) or \
                   ('E' in op and (x == 7 or not inside[y][x + 1])):
                    t[y][x] = 'x'
                elif t[y][x] == '.' and (
                        ('N' in op and (y == 0 or not inside[y - 1][x])) or
                        ('W' in op and (x == 0 or not inside[y][x - 1]))):
                    t[y][x] = '#'
                continue
            t[y][x] = '.'
            if 'S' in op and y > 0 and inside[y - 1][x]:
                t[y][x] = 'x'                   # the shadow under the leaves
    if 'S' in op:                               # trunks under the leaves
        for tx in TRUNKS[px]:
            if 'W' in op and tx < 2 or 'E' in op and tx > 5:
                continue
            top = 11 - BUMP_S[tx]
            for y in range(top, 15):
                t[y][tx] = 'o'
                t[y][tx + 1] = 'x'
            t[15][tx] = 'x'
            t[15][tx + 1] = 'x'
    return [''.join(r) for r in t]


KINDS = ['', 'N', 'S', 'W', 'E', 'NW', 'NE', 'SW', 'SE']


def tiles(seed=3):
    """{name: lines} - FOREST_<open>_<x parity><y parity>; edges open to
    the north or south vary with x only, to the west or east with y only,
    corners not at all"""
    g = canopy(seed)
    out = {}
    for op in KINDS:
        for px in (0, 1):
            for py in (0, 1):
                if op in ('N', 'S') and py or op in ('W', 'E') and px or len(op) == 2 and (px or py):
                    continue
                out[f'FOREST_{op or "IN"}_{px}{py}'] = tile(g, px, py, op)
    return out


def main():
    t = tiles()
    if '--png' in sys.argv:
        # a patch of wood: rows of the room's way of choosing them
        sys.path.insert(0, __import__('os').path.dirname(__file__))
        import mkdata as M
        from PIL import Image
        pal = {'.': M.colour('green3'), 'x': M.colour('brown0'),
               'o': M.colour('orange5'), '#': M.colour('green1')}
        plan = ['......',
                '.TTTT.',
                '.TTTT.',
                '.TTTT.',
                '......']
        s = 4
        img = Image.new('RGB', (6 * 16 * s, 5 * 16 * s), M.ted_rgb(pal['.']))
        px = img.load()
        for ty, row in enumerate(plan):
            for tx, ch in enumerate(row):
                if ch != 'T':
                    continue
                name = pick(lambda x, y: 0 <= y < 5 and 0 <= x < 6 and plan[y][x] == 'T', tx, ty)
                for y, line in enumerate(t[name]):
                    for x, c in enumerate(line):
                        for sx in range(2 * s):
                            for sy in range(s):
                                px[(tx * 8 + x) * 2 * s + sx, (ty * 16 + y) * s + sy] = M.ted_rgb(pal[c])
        img.save(sys.argv[sys.argv.index('--png') + 1])
        return
    for name, lines in t.items():
        print(f'tile {name} col=green1 flags=solid')
        print('\n'.join(lines))
        print()


def pick(is_tree, x, y):
    """the forest tile for a tree at x, y (is_tree(x, y) for its
    neighbours), or None for a tree on its own"""
    op = ''.join(d for d, (dx, dy) in (('N', (0, -1)), ('S', (0, 1)), ('W', (-1, 0)), ('E', (1, 0)))
                 if not is_tree(x + dx, y + dy))
    if len(op) >= 3 or op in ('NS', 'WE'):
        return None
    if op in ('N', 'S'):
        return f'FOREST_{op}_{x & 1}0'
    if op in ('W', 'E'):
        return f'FOREST_{op}_0{y & 1}'
    if len(op) == 2:
        return f'FOREST_{op}_00'
    return f'FOREST_IN_{x & 1}{y & 1}'


if __name__ == '__main__':
    main()
