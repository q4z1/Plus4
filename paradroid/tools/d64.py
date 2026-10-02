#!/usr/bin/env python3
"""Write a .d64 disk image, with each file's sector interleave chosen.

    d64.py out.d64 "disk name,id" file:name[:interleave] ...

A name starting with "!" (not part of it) goes first in the directory, so
LOAD"*" loads it, wherever on the disk it is.

The DOS (and c1541) put a file's sectors 10 apart on a track: right for
the KERNAL's speed. The fast loader (fastload.s) takes a sector in less
time, so its files are better closer together. Files are put on the tracks
nearest the directory first (17, 19, 16, 20, ...), in the order given, the
way the DOS does it; a file goes on where the last one ended.
"""
import sys

SECTORS = [21] * 17 + [19] * 7 + [18] * 6 + [17] * 5     # tracks 1-35
DIR_TRACK = 18


def offset(t, s):
    return (sum(SECTORS[:t - 1]) + s) * 256


def petscii(text, size):
    b = text.upper().encode('ascii')[:size]
    return b + b'\xA0' * (size - len(b))


class Disk:
    def __init__(self, name, ident):
        self.img = bytearray(sum(SECTORS) * 256)
        self.used = {t: set() for t in range(1, 36)}
        self.used[DIR_TRACK].add(0)          # the BAM
        self.name = name
        self.ident = ident
        self.entries = []
        # the order of the tracks: nearest the directory first
        self.tracks = []
        for d in range(1, 18):
            for t in (DIR_TRACK - d, DIR_TRACK + d):
                if 1 <= t <= 35:
                    self.tracks.append(t)
        self.ti = 0
        self.sec = None

    def alloc(self, interleave):
        """the next free sector: interleave on from the last one"""
        while self.ti < len(self.tracks):
            t = self.tracks[self.ti]
            n = SECTORS[t - 1]
            if len(self.used[t]) < n:
                s = 0 if self.sec is None else (self.sec + interleave) % n
                while s in self.used[t]:
                    s = (s + 1) % n
                self.used[t].add(s)
                self.sec = s
                return t, s
            self.ti += 1
        raise SystemExit('d64.py: the disk is full')

    def add(self, name, data, interleave):
        chunks = [data[i:i + 254] for i in range(0, len(data), 254)] or [b'']
        ts = [self.alloc(interleave) for _ in chunks]
        for i, (chunk, (t, s)) in enumerate(zip(chunks, ts)):
            o = offset(t, s)
            if i + 1 < len(ts):
                self.img[o:o + 2] = bytes(ts[i + 1])
            else:
                self.img[o:o + 2] = bytes((0, len(chunk) + 1))
            self.img[o + 2:o + 2 + len(chunk)] = chunk
        if name.startswith('!'):
            self.entries.insert(0, (name[1:], ts[0], len(chunks)))
        else:
            self.entries.append((name, ts[0], len(chunks)))

    def finish(self):
        # the directory: 8 entries a sector, its sectors 3 apart
        dsecs, s = [], 1
        for i in range(0, max(len(self.entries), 1), 8):
            while s in self.used[DIR_TRACK]:
                s = (s + 1) % SECTORS[DIR_TRACK - 1]
            self.used[DIR_TRACK].add(s)
            dsecs.append(s)
            s = (s + 3) % SECTORS[DIR_TRACK - 1]
        for k, ds in enumerate(dsecs):
            o = offset(DIR_TRACK, ds)
            if k + 1 < len(dsecs):
                self.img[o:o + 2] = bytes((DIR_TRACK, dsecs[k + 1]))
            else:
                self.img[o:o + 2] = b'\x00\xff'
            for j, (name, (t, s), blocks) in enumerate(self.entries[k * 8:k * 8 + 8]):
                e = o + j * 32
                self.img[e + 2] = 0x82                   # PRG, closed
                self.img[e + 3:e + 5] = bytes((t, s))
                self.img[e + 5:e + 21] = petscii(name, 16)
                self.img[e + 30:e + 32] = bytes((blocks & 255, blocks >> 8))
        # the BAM
        o = offset(DIR_TRACK, 0)
        bam = bytearray(256)
        bam[0:4] = bytes((DIR_TRACK, 1, 0x41, 0))
        for t in range(1, 36):
            n = SECTORS[t - 1]
            bits = 0
            for s in range(n):
                if s not in self.used[t]:
                    bits |= 1 << s
            free = n - len(self.used[t])
            bam[4 * t:4 * t + 4] = bytes((free, bits & 255, bits >> 8 & 255, bits >> 16 & 255))
        bam[0x90:0xA0] = petscii(self.name, 16)
        bam[0xA0:0xA2] = b'\xA0\xA0'
        bam[0xA2:0xA4] = petscii(self.ident, 2)
        bam[0xA4] = 0xA0
        bam[0xA5:0xA7] = b'2A'
        bam[0xA7:0xAB] = b'\xA0' * 4
        self.img[o:o + 256] = bam
        return bytes(self.img)


def main():
    out, label = sys.argv[1], sys.argv[2]
    name, ident = (label.split(',') + ['00'])[:2]
    disk = Disk(name, ident)
    for arg in sys.argv[3:]:
        parts = arg.split(':')
        path, fname = parts[0], parts[1]
        il = int(parts[2]) if len(parts) > 2 else 10
        disk.add(fname, open(path, 'rb').read(), il)
    open(out, 'wb').write(disk.finish())


if __name__ == '__main__':
    main()
