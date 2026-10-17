#!/usr/bin/env python3
"""Build trainschedule's data: the levels from data/*.txt and the pixel tables.

    mklevel.py <out.s> <disk-dir> <music.txt> <song-addr> <level.txt>...

Writes one assembler file with
  _levels      a table of pointers to the levels, 0-terminated
  _strip       the thin track: 8 directions x 8 lines, the half of a track
               from the middle of a cell to its edge (bit 0 = east, counting
               anticlockwise: E NE N NW W SW S SE)
  _tk_edge     the thick band a train is drawn as, per direction, by how
               much of the half is covered from the edge in; from the middle
               out is the whole half less this (engine.s): 8 x 5 x 8 lines
  _lamp        a signal's mark, right of the track seen the way it faces
  _bar         a platform's edge along the track, per axis (E, NE, N, NW)
  _gate        the end of a track at the edge of the map or a buffer stop
  _cursor      the corners of the cursor

A level in the program (all numbers little-endian, all text screen codes,
0-terminated):
  w h  start-minute(2)  perfect(2)  name  author
  tracks:   n, then each: points, x y per point
  signals:  n, then each: x y direction
  portals:  n, then each: x y
  stations: n, then each: label-x label-y name platforms,
            then each platform: number x0 y0 x1 y1
  trains:   n, then each: number (6 characters) type km/h cars visits,
            then each visit: station platform arrival(2) departure(2),
            times in seconds from the start minute
"""
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
import mkmusic                          # noqa: E402

SONG_MAX = 1536                         # game.inc: SONG_MAX
LOAD_MAX = 3072                         # front.s: SCRATCH, 3 KB

DIRS = ["E", "NE", "N", "NW", "W", "SW", "S", "SE"]
STEP = [(1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1), (0, 1), (1, 1)]
TYPES = "FIRCU"


def scr(text):
    """Text in screen codes of the upper-case character set."""
    out = []
    for c in text.upper():
        if "A" <= c <= "Z":
            out.append(ord(c) - 64)
        elif c == " " or "0" <= c <= "9" or c in "-./'()!:,":
            out.append(ord(c))
        else:
            sys.exit(f"no character {c!r} in the font")
    return out


def minutes(t):
    h, m = t.split(":")[:2]
    return int(h) * 60 + int(m)


def seconds(t):
    p = [int(v) for v in t.split(":")]
    return p[0] * 3600 + p[1] * 60 + (p[2] if len(p) > 2 else 0)


def xy(s):
    x, y = s.split(",")
    return int(x), int(y)


def level(path):
    tracks, signals, portals, stations, trains = [], [], [], {}, []
    meta = {"name": "", "author": "", "about": "", "level": "", "music": "",
            "perfect": 0, "start": "00:00"}
    for n, line in enumerate(open(path), 1):
        line = line.split("#")[0].strip()
        if not line:
            continue
        word, *rest = line.split()
        where = f"{path}:{n}"
        if word in ("name", "author", "about", "level", "music"):
            meta[word] = line.split(None, 1)[1]
        elif word == "perfect":
            meta["perfect"] = int(rest[0])
        elif word == "start":
            meta["start"] = rest[0]
        elif word == "size":
            meta["w"], meta["h"] = int(rest[0]), int(rest[1])
        elif word == "track":
            pts = [xy(p) for p in rest]
            for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
                dx, dy = x1 - x0, y1 - y0
                if dx and dy and abs(dx) != abs(dy):
                    sys.exit(f"{where}: not one of the eight directions")
            tracks.append(pts)
        elif word == "signal":
            x, y = xy(rest[0])
            signals.append((x, y, DIRS.index(rest[1])))
        elif word == "portal":
            portals.append(xy(rest[0]))
        elif word == "station":
            x, y = xy(rest[1])
            stations[int(rest[0])] = [x, y, line.split(None, 3)[3], []]
        elif word == "platform":
            (x0, y0), (x1, y1) = xy(rest[2]), xy(rest[3])
            stations[int(rest[0])][3].append((int(rest[1]), x0, y0, x1, y1))
        elif word == "train":
            head, visits = line.split(":", 1)[0], line.split(" : ", 1)[1]
            words = head.split()          # the number may have a space
            number = " ".join(words[1:-3])
            typ, kmh, cars = words[-3:]
            vs = []
            for v in visits.split(","):
                sp, arr, dep = v.split()
                st, pl = sp.split("/")
                vs.append((int(st), int(pl), arr, dep))
            trains.append((number, TYPES.index(typ), int(kmh), int(cars), vs))
        else:
            sys.exit(f"{where}: what is {word}?")

    w, h = meta["w"], meta["h"]
    if w * h > 1536:
        sys.exit(f"{path}: {w}x{h} is more than 1536 cells")
    for pts in tracks:
        for x, y in pts:
            if not (0 <= x < w and 0 <= y < h):
                sys.exit(f"{path}: {x},{y} outside the map")
    start = minutes(meta["start"])
    b = [w, h, start & 255, start >> 8, meta["perfect"] & 255, meta["perfect"] >> 8]
    b += scr(meta["name"]) + [0] + scr(meta["author"]) + [0]
    b.append(len(tracks))
    for pts in tracks:
        b.append(len(pts))
        for x, y in pts:
            b += [x, y]
    b.append(len(signals))
    for x, y, d in signals:
        b += [x, y, d]
    b.append(len(portals))
    for x, y in portals:
        b += [x, y]
    b.append(len(stations))
    if sorted(stations) != list(range(1, len(stations) + 1)):
        sys.exit(f"{path}: stations must be numbered 1, 2, 3 ...")
    for i in sorted(stations):
        x, y, name, plats = stations[i]
        b += [x, y] + scr(name) + [0, len(plats)]
        for p in plats:
            b += list(p)
    b.append(len(trains))
    for number, typ, kmh, cars, vs in trains:
        num = scr(number)[:6]                 # game.inc: TR_NUM_N
        b += num + [32] * (6 - len(num)) + [typ, kmh, cars, len(vs)]
        for st, pl, arr, dep in vs:
            a = seconds(arr) - start * 60
            d = seconds(dep) - start * 60
            b += [st, pl, a & 255, a >> 8, d & 255, d >> 8]
    times = [seconds(t) for _, _, _, _, vs in trains for _, _, a, d in vs for t in (a, d)]
    hhmm = lambda t: f"{t // 3600:02d}:{t // 60 % 60:02d}"
    span = f"{hhmm(min(times))}-{hhmm(max(times))}" if times else ""
    # the list of maps shows how hard it is, after the name
    listed = meta["name"] + (" " * (24 - len(meta["name"])) + meta["level"]
                              if meta["level"] else "")
    summary = {"name": listed, "about": meta["about"], "music": meta["music"],
               "facts": f"{len(stations)} STATIONS  {len(trains)} TRAINS  {span}"}
    return b, summary


# ---- the pixel tables -----------------------------------------------------
# A cell is 8x8 pixels, its middle at the corner of pixels 3 and 4. Lines are
# kept so that they run on into the next cell: the thin track is 2 pixels
# wide, the train 4.

def half(d, x, y, wide):
    """Is pixel x, y in the half track towards d, and which of the 4 steps
    from the middle out (0) to the edge (3) is it in? None if not."""
    lo, hi = (2, 5) if wide else (3, 4)
    if d in (0, 4):                         # E W
        if not lo <= y <= hi:
            return None
        s = x - 4 if d == 0 else 3 - x
    elif d in (2, 6):                       # N S
        if not lo <= x <= hi:
            return None
        s = 3 - y if d == 2 else y - 4
    elif d in (1, 5):                       # NE SW: x + y = 7, 8 (6..9 wide)
        if not (6 if wide else 7) <= x + y <= (9 if wide else 8):
            return None
        a = x - y
        s = (a - 1) // 2 if d == 1 else (-a) // 2
    else:                                   # NW SE: x - y = 0, 1 (-1..2 wide)
        if not (-1 if wide else 0) <= x - y <= (2 if wide else 1):
            return None
        a = x + y
        s = (7 - a) // 2 if d == 3 else (a - 8) // 2
    return s if 0 <= s <= 3 else None


def glyph(pixels):
    rows = [0] * 8
    for x, y in pixels:
        rows[y] |= 0x80 >> x
    return rows


ALL = [(x, y) for y in range(8) for x in range(8)]


def tables():
    out = {}
    out["strip"] = [glyph(p for p in ALL if half(d, *p, False) is not None)
                    for d in range(8)]
    out["tk_edge"] = [[glyph(p for p in ALL if (s := half(d, *p, True)) is not None
                             and s >= 4 - k) for k in range(5)] for d in range(8)]
    lamp = []
    for d in range(8):
        dx, dy = STEP[d]
        # right of the way it faces, 3 pixels out, near the cell's entry -
        # but W's below the track as E's: a platform's two at one height
        side = -1 if d == 4 else 1
        rx, ry = -dy * side, dx * side
        n = (dx * dx + dy * dy) ** 0.5
        cx = 4 + 3.2 * rx / n - 1.0 * dx / n
        cy = 4 + 3.2 * ry / n - 1.0 * dy / n
        lamp.append(glyph((x, y) for x, y in ALL
                          if abs(x + 0.5 - cx) <= 1.1 and abs(y + 0.5 - cy) <= 1.1))
    out["lamp"] = lamp
    out["bar"] = [glyph((x, y) for x, y in ALL if y == 6),          # E-W
                  glyph((x, y) for x, y in ALL if x + y == 11),     # NE-SW
                  glyph((x, y) for x, y in ALL if x == 6),          # N-S
                  glyph((x, y) for x, y in ALL if x - y == -3)]     # NW-SE
    # across the track through the middle, 2 pixels thick, 6 long
    across = [lambda x, y: 3 <= x <= 4 and 1 <= y <= 6,           # E W
              lambda x, y: 0 <= x - y <= 1 and 1 <= x <= 6,       # NE SW
              lambda x, y: 3 <= y <= 4 and 1 <= x <= 6,           # N S
              lambda x, y: 7 <= x + y <= 8 and 1 <= x <= 6]       # NW SE
    gate = [glyph(p for p in ALL if across[d & 3](*p)) for d in range(8)]
    out["gate"] = gate
    # platform numbers: digits of 3 x 5 pixels, a row a byte, the top 3 bits
    font = ["111101101101111", "010110010010111", "111001111100111",
            "111001111001111", "101101111001001", "111100111001111",
            "111100111101111", "111001010010010", "111101111101111",
            "111101111001111"]
    out["digit"] = [[int(d[r * 3:r * 3 + 3], 2) << 5 for r in range(5)] for d in font]
    # The pointer, in multicolour pixels (two hires wide): white (%01) with
    # a black edge (%10) below and right of it, the tip at 0, 0. Shifted in
    # advance to the four places a multicolour pixel can start in a
    # character: per shift and line, the two characters it spans, as the
    # pixels to set and the mask of what of the map stays (1s).
    white = ["X", "XX", "XXX", "XXXX", "XX", "X.X", "..X"]
    W = {(x, y) for y, r in enumerate(white) for x, c in enumerate(r) if c == "X"}
    B = {(x + dx, y + dy) for x, y in W for dx in (0, 1) for dy in (0, 1)} - W
    pdata, pmask = [], []
    for sh in range(4):
        for y in range(9):
            row_d, row_m = 0, 0
            for x in range(6):
                v = 1 if (x, y) in W else 2 if (x, y) in B else 0
                pos = 7 - (sh + x)          # pairs from the left of 16 bits
                if pos < 0:
                    continue
                row_d |= v << (pos * 2)
                if v:
                    row_m |= 3 << (pos * 2)
            row_m ^= 0xFFFF
            pdata += [row_d >> 8, row_d & 255]
            pmask += [row_m >> 8, row_m & 255]
    out["ptr_data"] = pdata
    out["ptr_mask"] = pmask
    # hires to multicolour: a pair with anything set becomes %11, the cell's
    # own colour
    out["mc_of"] = [sum(3 << (2 * k) for k in range(4) if v & (3 << (2 * k)))
                    for v in range(256)]
    out["cursor"] = [glyph([(0, 0), (1, 0), (0, 1), (7, 0), (6, 0), (7, 1),
                           (0, 7), (1, 7), (0, 6), (7, 7), (6, 7), (7, 6)])]
    return out


# ---- the same at twice the size: a cell of 2 x 2 characters ---------------
# Worked out from the geometry rather than by hand: a pixel belongs to the
# half track towards d if it lies ahead of the middle along d and close
# enough to the line; its step is how far along it is (8 steps a half).
# Every table entry is a 16 x 16 cell as its four characters, top left,
# top right, bottom left, bottom right, 8 bytes each.
# The middle is a pixel above the cell's: so an E-W track (rows 6 and 7)
# keeps to the upper characters, and a platform's edge and number below it
# have the lower ones to themselves - they stay grey when the track takes a
# route's colour (map.s). Only up: moved across too, the NE-SW diagonals
# would miss the corners they run on through.

ALL16 = [(x, y) for y in range(16) for x in range(16)]
N2 = 8
MID_X, MID_Y = 8, 7


def geo(d, x, y):
    """(along, across) of pixel x, y from the middle, for direction d"""
    ux, uy = STEP[d]
    n = (ux * ux + uy * uy) ** 0.5
    ux, uy = ux / n, uy / n
    rx, ry = x + 0.5 - MID_X, y + 0.5 - MID_Y
    return rx * ux + ry * uy, rx * uy - ry * ux, 8 * n


def half2(d, x, y, width):
    a, p, length = geo(d, x, y)
    if a < 0 or a > length + 1 or abs(p) > width:     # (S: a pixel more)
        return None
    return min(N2 - 1, int(a / length * N2))


def cell16(pixels):
    rows = [[0] * 16 for _ in range(16)]
    for x, y in pixels:
        rows[y][x] = 1
    out = []
    for qy, qx in ((0, 0), (0, 8), (8, 0), (8, 8)):
        for y in range(8):
            b = 0
            for x in range(8):
                if rows[qy + y][qx + x]:
                    b |= 0x80 >> x
            out.append(b)
    return out


def tables2():
    out = {}
    thin = [0.75 if d & 1 else 1.0 for d in range(8)]
    out["strip2"] = [cell16(p for p in ALL16 if half2(d, *p, thin[d]) is not None)
                     for d in range(8)]
    # North and south a pixel to the left and to the right, all in one
    # column of characters: in a set switch, clear of a diagonal leg next to
    # them, which takes the other column (map.s, path_split)
    out["strip2v"] = [cell16((x + dx, y) for x, y in ALL16 if half2(d, x, y, thin[d]) is not None)
                      for d in (2, 6) for dx in (-1, 1)]
    out["tk2_edge"] = [[cell16(p for p in ALL16 if (s := half2(d, *p, 3.0)) is not None
                               and s >= N2 - k) for k in range(N2 + 1)] for d in range(8)]
    lamp = []
    for d in range(8):
        ux, uy = STEP[d]
        n = (ux * ux + uy * uy) ** 0.5
        ux, uy = ux / n, uy / n
        side = -1 if d == 4 else 1                  # (W below, as E: see lamp)
        cx = MID_X - uy * 6 * side - ux * 2.5         # right of it
        cy = MID_Y + ux * 6 * side - uy * 2.5
        cx, cy = min(max(cx, 2), 14), min(max(cy, 2), 14)   # all of it in the cell
        lamp.append(cell16((x, y) for x, y in ALL16
                           if abs(x + 0.5 - cx) <= 2 and abs(y + 0.5 - cy) <= 2))
    out["lamp2"] = lamp
    side = [-1, -1, -1, 1]
    away = [1, 0, 0, 0]         # E-W a pixel lower: clear of a train's foot
    bar = []
    for k in range(4):
        pts = []
        for x, y in ALL16:
            a, p, length = geo(k, x, y)
            if 5.0 + away[k] <= side[k] * p <= 6.2 + away[k] and abs(a) <= length + (k == 2):
                pts.append((x, y))
        bar.append(cell16(pts))
    out["bar2"] = bar
    gate = []
    for d in range(8):
        pts = []
        for x, y in ALL16:
            a, p, length = geo(d, x, y)
            if -1.5 <= a <= 0.5 and abs(p) <= 6:
                pts.append((x, y))
        gate.append(cell16(pts))
    out["gate2"] = gate
    corner = [(x, y) for x, y in ALL16
              if (x in (0, 15) and (y < 3 or y > 12)) or (y in (0, 15) and (x < 3 or x > 12))]
    out["cursor2"] = [cell16(corner)]
    return out


def emit(label, rows, f):
    flat = []

    def walk(v):
        if isinstance(v, list):
            for i in v:
                walk(i)
        else:
            flat.append(v)
    walk(rows)
    f.write(f"_{label}:\n")
    for i in range(0, len(flat), 16):
        f.write("        .byte " + ",".join(f"${v:02X}" for v in flat[i:i + 16]) + "\n")


def write_prg(path, data, addr=0):
    """a file for the disk: a load address (the game gives its own), data"""
    open(path, "wb").write(bytes([addr & 255, addr >> 8]) + bytes(data))


def main():
    """mklevel.py <out.s> <disk-dir> <music.txt> <song-addr> <level.txt>...:
    the tables into out.s; on the disk each level as MAP1, MAP2 ..., and
    MAPS, the catalogue: how many, then for each its name (and how hard it
    is), a line about it and its facts (screen codes, 0-terminated).

    A level's file starts with its song ("music NAME" in its text, from
    music.txt, placed at song-addr, SONG_BUF in game.inc): its length (2),
    0 if it has none, and the song; then the level. The game loads it to
    SCRATCH (front.s), 3 KB, and moves both where they belong."""
    out, disk, music, song_at, paths = sys.argv[1], sys.argv[2], sys.argv[3], \
        int(sys.argv[4].lstrip("$"), 16), sys.argv[5:]
    with open(out, "w") as f:
        f.write("; made by tools/mklevel.py - do not edit\n")
        f.write("        .rodata\n")
        t = tables()
        t.update(tables2())
        for name in t:
            f.write(f"        .export _{name}\n")
            emit(name, t[name], f)
    cat = [len(paths)]
    for i, path in enumerate(paths, 1):
        data, info = level(path)
        if len(data) > 1024:
            sys.exit(f"{path}: {len(data)} bytes, more than the game's 1024")
        song = b""
        if info["music"]:
            song, about = mkmusic.build(music, info["music"], song_at)
            print(f"{path}: {about}")
        if len(song) > SONG_MAX:
            sys.exit(f"{path}: its song {len(song)} bytes, more than the game's {SONG_MAX}")
        file = [len(song) & 255, len(song) >> 8] + list(song) + data
        if len(file) > LOAD_MAX:
            sys.exit(f"{path}: {len(file)} bytes, more than the game loads ({LOAD_MAX})")
        write_prg(f"{disk}/MAP{i}", file)
        for k in ("name", "about", "facts"):
            if len(info[k]) > 36:       # the list starts in column 4
                sys.exit(f"{path}: {k} longer than 36: {info[k]}")
            cat += scr(info[k]) + [0]
    write_prg(f"{disk}/MAPS", cat)


if __name__ == "__main__":
    main()
