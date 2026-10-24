#!/usr/bin/env python3
"""Lists and extracts the files of an Amiga disk image (ADF, OFS or FFS).

    adf.py list    disk.adf              # tree with sizes and block numbers
    adf.py extract disk.adf outdir       # every file, directories as folders
    adf.py boot    disk.adf out.bin      # the boot block (sectors 0-1)
"""
import os
import struct
import sys

BSIZE = 512
T_HEADER, T_DATA, T_LIST = 2, 8, 16
ST_ROOT, ST_DIR, ST_FILE = 1, 2, -3


class Adf:
    def __init__(self, image):
        """image: a file name or the image's bytes"""
        if isinstance(image, (bytes, bytearray)):
            self.data = bytes(image)
        else:
            with open(image, 'rb') as f:
                self.data = f.read()
        self.nblocks = len(self.data) // BSIZE
        self.ffs = bool(self.data[3] & 1) if self.data[:3] == b'DOS' else False
        self.root = self.nblocks // 2

    def block(self, n):
        if not 0 <= n < self.nblocks:
            raise ValueError(f'block {n} outside the disk')
        return self.data[n * BSIZE:(n + 1) * BSIZE]

    def long(self, b, off):
        return struct.unpack_from('>i', b, off if off >= 0 else BSIZE + off)[0]

    def name(self, b):
        n = b[BSIZE - 80]
        return b[BSIZE - 79:BSIZE - 79 + n].decode('latin-1')

    def entries(self, dirblock):
        """Yields (name, block, sectype) of a directory's entries."""
        b = self.block(dirblock)
        for i in range(72):
            n = self.long(b, 24 + 4 * i)
            seen = set()
            while n and n not in seen:
                seen.add(n)
                e = self.block(n)
                yield self.name(e), n, self.long(e, -4)
                n = self.long(e, -16)

    def file_data(self, header):
        b = self.block(header)
        size = self.long(b, -188)
        blocks = []
        h = b
        while True:
            count = self.long(h, 8)
            # data block pointers run backwards from offset 308
            for i in range(count):
                blocks.append(self.long(h, 308 - 4 * i))
            ext = self.long(h, -8)
            if not ext:
                break
            h = self.block(ext)
        out = bytearray()
        for n in blocks:
            d = self.block(n)
            if self.ffs:
                out += d
            else:
                out += d[24:24 + self.long(d, 12)]
        return bytes(out[:size]), blocks

    def walk(self, dirblock=None, prefix=''):
        for name, n, st in self.entries(self.root if dirblock is None else dirblock):
            path = prefix + name
            if st == ST_DIR:
                yield path + '/', n, None
                yield from self.walk(n, path + '/')
            else:
                yield path, n, st


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    cmd, adf = sys.argv[1], Adf(sys.argv[2])
    if cmd == 'boot':
        with open(sys.argv[3], 'wb') as f:
            f.write(adf.data[:1024])
        return
    rb = adf.block(adf.root)
    if adf.long(rb, 0) != T_HEADER or adf.long(rb, -4) != ST_ROOT:
        sys.exit('no AmigaDOS file system on this disk (trackloader disk?)')
    print(f'Volume "{adf.name(rb)}", {"FFS" if adf.ffs else "OFS"}', file=sys.stderr)
    for path, n, st in adf.walk():
        if path.endswith('/'):
            if cmd == 'list':
                print(f'{"":>8}  {n:5}  {path}')
            else:
                os.makedirs(os.path.join(sys.argv[3], path), exist_ok=True)
            continue
        data, blocks = adf.file_data(n)
        if cmd == 'list':
            first = blocks[0] if blocks else 0
            print(f'{len(data):8}  {n:5}  {path}  (data from block {first})')
        elif cmd == 'extract':
            out = os.path.join(sys.argv[3], path)
            os.makedirs(os.path.dirname(out) or '.', exist_ok=True)
            with open(out, 'wb') as f:
                f.write(data)
        else:
            sys.exit(__doc__)


if __name__ == '__main__':
    main()
