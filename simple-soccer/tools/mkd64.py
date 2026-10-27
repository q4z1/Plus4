#!/usr/bin/env python3
"""A .d64 disk image, its files laid out for the fast loader.

    mkd64.py <out.d64> <disk name> <id> <interleave> <name>[@<interleave>]=<file.prg> ...

The files go on the disk in the order given, as PRGs, the way the 1541's
DOS would put them - starting at the tracks next to the directory (17, 19,
16, 20 ...) - except for the gap between a file's sectors: the interleave.
The DOS uses 10, and so does VICE's c1541; the fast loader reads a sector
through the DOS and sends it before it asks for the next, which takes a
little longer than 10 sectors go by, so it would wait a whole turn of the
disk each time. The interleave is counted in sectors of the outer tracks
(21 to a turn of the disk) and scaled to the others, so the gap takes the
same time on every track. A file may have one of its own (name@n). Names
are given in lower case and stored as the Plus/4 types them (PETSCII
without shift).
"""
import sys

SECTORS = [0] + [21] * 17 + [19] * 7 + [18] * 6 + [17] * 5     # by track 1-35
DIR_TRACK = 18


def petscii(name):
    out = bytearray()
    for c in name:
        if 'a' <= c <= 'z':
            out.append(ord(c) - 32)
        else:
            out.append(ord(c))
    return bytes(out)


def padded(b, n=16):
    assert len(b) <= n, b
    return b + b'\xa0' * (n - len(b))


class Disk:
    def __init__(self):
        self.free = {t: set(range(SECTORS[t])) for t in range(1, 36)}
        self.data = {}
        self.next = (DIR_TRACK - 1, 0)

    def offset(self, t, s):
        return (sum(SECTORS[1:t]) + s) * 256

    def take(self, t, s):
        self.free[t].remove(s)

    def tracks(self):
        """the order files are given tracks: nearest the directory first"""
        for d in range(1, 18):
            for t in (DIR_TRACK - d, DIR_TRACK + d):
                if 1 <= t <= 35:
                    yield t

    def write_file(self, data, interleave):
        """data's sectors (254 bytes each) somewhere free; their places. A
        file goes on where the one before ended, in the same pattern: the
        loader reads one after the other, so the next file's first sector
        is as well placed as a file's next sector."""
        chunks = [data[i:i + 254] for i in range(0, len(data), 254)] or [b'']
        places = []
        t, s = self.next
        for _ in chunks:
            if not self.free[t]:
                t = next(u for u in self.tracks() if self.free[u])
            n = SECTORS[t]
            s %= n
            while s not in self.free[t]:
                s = (s + 1) % n
            self.take(t, s)
            places.append((t, s))
            s = (s + round(interleave * n / 21)) % n
        self.next = (t, s)
        for i, chunk in enumerate(chunks):
            if i + 1 < len(chunks):
                link = bytes(places[i + 1])
            else:
                link = bytes([0, len(chunk) + 1])
            self.data[places[i]] = link + chunk + bytes(254 - len(chunk))
        return places

    def image(self, name, disk_id, entries):
        # the directory: 18/1, then every third sector
        dir_sectors = []
        s = 1
        for i in range(0, max(len(entries), 1), 8):
            self.take(DIR_TRACK, s)
            dir_sectors.append(s)
            s = (s + 3) % SECTORS[DIR_TRACK]
        for k, ds in enumerate(dir_sectors):
            sec = bytearray(256)
            if k + 1 < len(dir_sectors):
                sec[0:2] = bytes([DIR_TRACK, dir_sectors[k + 1]])
            else:
                sec[0:2] = bytes([0, 255])
            for j, (fname, places) in enumerate(entries[k * 8:k * 8 + 8]):
                e = 2 + j * 32
                sec[e] = 0x82                       # PRG, closed
                sec[e + 1:e + 3] = bytes(places[0])
                sec[e + 3:e + 19] = padded(petscii(fname))
                sec[e + 28:e + 30] = bytes([len(places) & 255, len(places) >> 8])
            self.data[(DIR_TRACK, ds)] = bytes(sec)
        # the BAM, 18/0
        self.take(DIR_TRACK, 0)
        bam = bytearray(256)
        bam[0:4] = bytes([DIR_TRACK, 1, 0x41, 0])
        for t in range(1, 36):
            bits = 0
            for s in self.free[t]:
                bits |= 1 << s
            bam[t * 4:t * 4 + 4] = bytes([len(self.free[t]), bits & 255,
                                          (bits >> 8) & 255, bits >> 16])
        bam[0x90:0xA0] = padded(petscii(name))
        bam[0xA0:0xAB] = b'\xa0\xa0' + petscii(disk_id)[:2].ljust(2, b' ') + b'\xa0' + b'2A' + b'\xa0' * 4
        self.data[(DIR_TRACK, 0)] = bytes(bam)

        img = bytearray(sum(SECTORS) * 256)
        for (t, s), sec in self.data.items():
            o = self.offset(t, s)
            img[o:o + 256] = sec
        return bytes(img)


def main():
    out, name, disk_id, interleave = sys.argv[1:5]
    interleave = int(interleave)
    disk = Disk()
    entries = []
    for arg in sys.argv[5:]:
        fname, path = arg.split('=', 1)
        step = interleave
        if '@' in fname:
            fname, step = fname.split('@')
            step = int(step)
        places = disk.write_file(open(path, 'rb').read(), step)
        entries.append((fname, places))
    open(out, 'wb').write(disk.image(name, disk_id, entries))
    for fname, places in entries:
        print(f'{len(places):4d}  "{fname}"')
    print(f'{sum(len(f) for f in disk.free.values()) - len(disk.free[DIR_TRACK])} blocks free.')


if __name__ == '__main__':
    main()
