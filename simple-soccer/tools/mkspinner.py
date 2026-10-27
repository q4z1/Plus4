#!/usr/bin/env python3
"""
mkspinner.py - the football that turns while the boot loads (boot.s):
build/gen/spinner.inc, FRAMES pictures of 24 x 24 hires pixels, each as
its nine characters, a row of three at a time (8 bytes each).

    mkspinner.py [--png preview.png]

The ball is a sphere seen from the front, white, with the twelve black
pentagons of a football round the corners of an icosahedron. It turns
about one of them, tilted towards the viewer: a fifth of a turn brings it
back to how it was, so FRAMES pictures over 72 degrees go round and round
without a jump.
"""
import math
import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'build', 'gen', 'spinner.inc')
FRAMES = 8
SIZE = 24
TILT = math.radians(55)         # the axis leant back towards the viewer
PATCH = math.cos(math.radians(17))      # a pentagon's reach from its corner
RIM = 0.78                      # (and none this near the edge: the ball's
                                # outline stays round on the black)


def vertices():
    """an icosahedron about the z axis: a corner top and bottom, two rings
    of five between"""
    out = [(0, 0, 1), (0, 0, -1)]
    z = 1 / math.sqrt(5)
    r = 2 / math.sqrt(5)
    for k in range(5):
        a = math.radians(72 * k)
        out.append((r * math.cos(a), r * math.sin(a), z))
        a = math.radians(72 * k + 36)
        out.append((r * math.cos(a), r * math.sin(a), -z))
    return out


def frame(theta):
    vs = vertices()
    rows = []
    c = (SIZE - 1) / 2
    R = SIZE / 2 - 0.5
    for y in range(SIZE):
        row = []
        for x in range(SIZE):
            dx, dy = (x - c) / R, (y - c) / R
            d2 = dx * dx + dy * dy
            if d2 > 1:
                row.append(0)
                continue
            # the point on the sphere's front, in the view: x right, y up,
            # z towards the viewer; then into the ball's own frame - back
            # by the tilt about x, back by the turn about z
            px, py, pz = dx, -dy, math.sqrt(1 - d2)
            ct, st = math.cos(-TILT), math.sin(-TILT)
            py, pz = py * ct - pz * st, py * st + pz * ct
            ca, sa = math.cos(-theta), math.sin(-theta)
            px, py = px * ca - py * sa, px * sa + py * ca
            near = max(px * vx + py * vy + pz * vz for vx, vy, vz in vs)
            row.append(0 if near > PATCH and d2 < RIM else 1)
        rows.append(row)
    return rows


def chars(rows):
    out = []
    for cy in range(0, SIZE, 8):
        for cx in range(0, SIZE, 8):
            for y in range(8):
                b = 0
                for x in range(8):
                    b = b << 1 | rows[cy + y][cx + x]
                out.append(b)
    return out


def main():
    frames = [frame(math.radians(72 * k / FRAMES)) for k in range(FRAMES)]
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, 'w') as f:
        f.write('; made by tools/mkspinner.py - do not edit\n')
        f.write('SPIN_FRAMES = %d\n' % FRAMES)
        f.write('spin_pics:\n')
        for k, fr in enumerate(frames):
            b = chars(fr)
            for i in range(0, len(b), 8):
                f.write('        .byte ' + ', '.join('$%02X' % x for x in b[i:i + 8]) + '\n')
    print('spinner: %d frames' % FRAMES)
    if len(sys.argv) > 2 and sys.argv[1] == '--png':
        S = 6
        W = FRAMES * (SIZE + 2) * S
        H = SIZE * S
        pix = [[(0, 0, 0)] * W for _ in range(H)]
        for k, fr in enumerate(frames):
            for y in range(SIZE):
                for x in range(SIZE):
                    if fr[y][x]:
                        for a in range(S):
                            for b in range(S):
                                pix[y * S + a][(k * (SIZE + 2) + x) * S + b] = (255, 255, 255)
        raw = b''.join(b'\0' + bytes(v for p in row for v in p) for row in pix)

        def chunk(t, c):
            return struct.pack('>I', len(c)) + t + c + struct.pack('>I', zlib.crc32(t + c) & 0xffffffff)
        open(sys.argv[2], 'wb').write(b'\x89PNG\r\n\x1a\n'
                                      + chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0))
                                      + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))


if __name__ == '__main__':
    main()
