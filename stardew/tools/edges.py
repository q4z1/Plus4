#!/usr/bin/env python3
"""edges.py - how the path's edges in data/tiles_outdoor.txt were made.

The path tile with the grass reaching into it where it meets grass: a
ragged line of the background colour along the open side, two pixels
deep at most. One tile for every set of open sides (N, S, W, E, NS, NWE, ...): a
quarter of a tile depends only on its two sides, so all fifteen together
take twelve characters more than the path. tools/mkdata.py picks the right one for every path tile of a room
from its neighbours (rooms.txt stays a '=').

    tools/edges.py         the tiles, to paste after PATH
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# how deep the grass reaches in, along each side
DEPTH_NS = [1, 2, 1, 0, 1, 1, 2, 1]
DEPTH_WE = [1, 1, 0, 1, 2, 1, 1, 0, 1, 1, 2, 1, 0, 1, 1, 1]


def path_tile():
    lines = open(os.path.join(HERE, '..', 'data', 'tiles_outdoor.txt')).read().split('\n')
    i = next(k for k, l in enumerate(lines) if l.startswith('tile PATH '))
    return lines[i], lines[i + 1:i + 17]


def edged(pic, op):
    t = [list(l) for l in pic]
    for y in range(16):
        for x in range(8):
            g = ('N' in op and y < DEPTH_NS[x]) or ('S' in op and y > 15 - DEPTH_NS[7 - x]) or \
                ('W' in op and x < DEPTH_WE[y]) or ('E' in op and x > 7 - DEPTH_WE[15 - y])
            if g:
                t[y][x] = '.'
    return [''.join(r) for r in t]


KINDS = [''.join(d for k, d in enumerate('NSWE') if m >> k & 1) for m in range(1, 16)]


def pick(is_path, x, y):
    """the edged path tile for a path at x, y, or None for the plain one"""
    op = ''.join(d for d, (dx, dy) in (('N', (0, -1)), ('S', (0, 1)), ('W', (-1, 0)), ('E', (1, 0)))
                 if not is_path(x + dx, y + dy))
    return f'PATH_{op}' if op else None


def main():
    head, pic = path_tile()
    col = re.search(r'col=\S+', head).group(0)
    for op in KINDS:
        print(f'tile PATH_{op} {col}')
        print('\n'.join(edged(pic, op)))
        print()


if __name__ == '__main__':
    main()
