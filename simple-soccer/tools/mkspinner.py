#!/usr/bin/env python3
"""
mkspinner.py - the football that turns while the boot loads (boot.s):
build/gen/spinner.inc, FRAMES pictures of 12 x 24 multicolour pixels
(as wide as 24 hires ones), each as its nine characters, a row of three at
a time (8 bytes each); and
build/gen/spinpack.inc, spinat.inc, spinvary.inc and spinvar2.inc, the
same packed for the league's loading screen (cup.s): the first picture,
where the bytes that change from picture to picture go - and those bytes,
picture by picture (spin_v0, spin_v1, ...): the first SPIN_LOW pictures in
spinvary.inc, the others in spinvar2.inc (cup.s puts them in two places,
for room).

    mkspinner.py [--png preview.png]

The ball is a sphere seen from the front, white, with the twelve black
pentagons of a football round the corners of an icosahedron, black right
up to its outline. Its pixels: %00 the background (outside it), %01 the
first shared colour (the pentagons: black), %11 the cell's (white). It turns
about the middle of a hexagon (three pentagons round it), the axis upright
and leant a little towards the viewer: no pentagon lies on it, so every
one goes round (about a pentagon, the one on the axis only turned on its
spot); a third of a turn brings it back to how it was, so FRAMES pictures
over 120 degrees go round and round without a jump.
"""
import math
import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'build', 'gen', 'spinner.inc')
PACKED = os.path.join(HERE, '..', 'build', 'gen', 'spinpack.inc')
VARY = os.path.join(HERE, '..', 'build', 'gen', 'spinvary.inc')
AT = os.path.join(HERE, '..', 'build', 'gen', 'spinat.inc')
VARY2 = os.path.join(HERE, '..', 'build', 'gen', 'spinvar2.inc')
FRAMES = 10
LOW = 5                         # pictures in spinvary.inc (cup.s: LDLOW's room)
SIZE = 24
TILT = math.radians(70)         # the axis leant back towards the viewer
PATCH = math.cos(math.radians(17))      # a pentagon's reach from its corner
BG, BLACK, WHITE = 0, 1, 3      # the multicolour pixels


def vertices():
    """an icosahedron with a face's middle on the z axis: first about z, a
    corner top and bottom, two rings of five between; then turned so the
    face of the top corner and the first two of the upper ring is on top"""
    out = [(0, 0, 1), (0, 0, -1)]
    z = 1 / math.sqrt(5)
    r = 2 / math.sqrt(5)
    for k in range(5):
        a = math.radians(72 * k)
        out.append((r * math.cos(a), r * math.sin(a), z))
        a = math.radians(72 * k + 36)
        out.append((r * math.cos(a), r * math.sin(a), -z))
    n = [sum(out[i][j] for i in (0, 2, 4)) for j in range(3)]
    ln = math.sqrt(sum(a * a for a in n))
    n = [a / ln for a in n]
    # about the axis n x z (in the x-y plane) by the angle between n and z
    ln = math.hypot(n[0], n[1])
    kx, ky = n[1] / ln, -n[0] / ln
    c, s = n[2], ln
    turned = []
    for x, y, z in out:
        d = kx * x + ky * y
        cx, cy, cz = ky * z, -kx * z, kx * y - ky * x       # k x v
        turned.append((x * c + cx * s + kx * d * (1 - c),
                       y * c + cy * s + ky * d * (1 - c),
                       z * c + cz * s))
    return turned


def frame(theta):
    vs = vertices()
    rows = []
    c = (SIZE - 1) / 2
    R = SIZE / 2 - 0.5
    for y in range(SIZE):
        row = []
        for mx in range(SIZE // 2):
            x = 2 * mx + 0.5            # (the middle of its two hires ones)
            dx, dy = (x - c) / R, (y - c) / R
            d2 = dx * dx + dy * dy
            if d2 > 1:
                row.append(BG)
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
            row.append(BLACK if near > PATCH else WHITE)
        rows.append(row)
    return rows


def chars(rows):
    out = []
    for cy in range(0, SIZE, 8):
        for cx in range(0, SIZE // 2, 4):
            for y in range(8):
                b = 0
                for x in range(4):
                    b = b << 2 | rows[cy + y][cx + x]
                out.append(b)
    return out


def main():
    frames = [frame(math.radians(120 * k / FRAMES)) for k in range(FRAMES)]
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, 'w') as f:
        f.write('; made by tools/mkspinner.py - do not edit\n')
        f.write('SPIN_FRAMES = %d\n' % FRAMES)
        f.write('spin_pics:\n')
        for k, fr in enumerate(frames):
            b = chars(fr)
            for i in range(0, len(b), 8):
                f.write('        .byte ' + ', '.join('$%02X' % x for x in b[i:i + 8]) + '\n')
    # the same packed, for the league's loading screen (cup.s, short of
    # room): the first picture whole, then of each picture only the bytes
    # that are not the same in all of them, and where they go
    pics = [chars(fr) for fr in frames]
    vary = [i for i in range(72) if len(set(p[i] for p in pics)) > 1]
    with open(PACKED, 'w') as f:
        f.write('; made by tools/mkspinner.py - do not edit\n')
        f.write('SPIN_FRAMES = %d\n' % FRAMES)
        f.write('SPIN_VARY   = %d             ; bytes that change\n' % len(vary))
        f.write('SPIN_LOW    = %d              ; pictures in spinvary.inc\n' % LOW)
        f.write('spin_first:\n')
        for i in range(0, 72, 8):
            f.write('        .byte ' + ', '.join('$%02X' % x for x in pics[0][i:i + 8]) + '\n')
    with open(AT, 'w') as f:
        f.write('; made by tools/mkspinner.py - do not edit\n')
        f.write('spin_at:\n')
        for i in range(0, len(vary), 12):
            f.write('        .byte ' + ', '.join('%d' % x for x in vary[i:i + 12]) + '\n')
    for name, ks in ((VARY, range(LOW)), (VARY2, range(LOW, FRAMES))):
        with open(name, 'w') as f:
            f.write('; made by tools/mkspinner.py - do not edit\n')
            for k in ks:
                f.write('spin_v%d:\n' % k)
                v = [pics[k][i] for i in vary]
                for i in range(0, len(v), 12):
                    f.write('        .byte ' + ', '.join('$%02X' % x for x in v[i:i + 12]) + '\n')
    print('spinner: %d frames, %d bytes of 72 change' % (FRAMES, len(vary)))
    if len(sys.argv) > 2 and sys.argv[1] == '--png':
        S = 6
        W = FRAMES * (SIZE + 2) * S
        H = SIZE * S
        pix = [[(0, 0, 0)] * W for _ in range(H)]
        for k, fr in enumerate(frames):
            for y in range(SIZE):
                for x in range(SIZE):
                    v = fr[y][x // 2]
                    rgb = (0, 80, 0) if v == BG else (0, 0, 0) if v == BLACK else (255, 255, 255)
                    for a in range(S):
                        for b in range(S):
                            pix[y * S + a][(k * (SIZE + 2) + x) * S + b] = rgb
        raw = b''.join(b'\0' + bytes(v for p in row for v in p) for row in pix)

        def chunk(t, c):
            return struct.pack('>I', len(c)) + t + c + struct.pack('>I', zlib.crc32(t + c) & 0xffffffff)
        open(sys.argv[2], 'wb').write(b'\x89PNG\r\n\x1a\n'
                                      + chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0))
                                      + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))


if __name__ == '__main__':
    main()
