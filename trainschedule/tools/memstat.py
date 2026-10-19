#!/usr/bin/env python3
"""Where trainschedule's memory goes: the Plus/4's RAM and the disk.

    memstat.py [--build DIR] [--d64 FILE] [--top N]

Reads what build.sh leaves in build/ - the linker's map and labels
(trainschedule.map, trainschedule.lbl), the unpacked program
(trainschedule.raw), the maps' files (disk/MAP1 ...) and the disk
(trainschedule.d64) - and prints
  - the RAM from $0000 to $FFFF: who holds each range, and what is free
  - the program by module: code, read-only data, data, BSS, zero page
  - the largest labels (a label's size: up to the next one)
  - how full each map leaves the buffers it is loaded into
  - the disk: each file's blocks and bytes, and the blocks still free

The linker knows only its own memory areas (trainschedule.cfg); what lies
outside them - the screens, the character set, the map, the KERNAL's - is
listed in FIXED below, as trainschedule.cfg's comment describes it.
"""
import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)

LEVEL_MAX = 1024        # front.s: _level_buf
LOAD_MAX = 3072         # front.s: SCRATCH, a map's whole file

# The memory the linker does not place (trainschedule.cfg): start, end
# (inclusive), what. MAP is filled in from game.inc's MAP_MAX.
FIXED = [
    (0x0000, 0x0001, "CPU port"),
    (0x0080, 0x00FF, "KERNAL's zero page"),
    (0x0100, 0x01FF, "CPU stack"),
    (0x0200, 0x03FF, "KERNAL's work area (LOAD, $0314)"),
    (0x0800, 0x0FFF, "screen 1: colours, characters"),
    (0x1000, 0x1000, "BASIC's 0 before the program"),
    (0xC000, 0xC7FF, "character set"),
    ("MAP", None, "the map: characters, colours, holders"),
    (0xF000, 0xF7FF, "screen 2: colours, characters"),
    (0xFA00, 0xFAFF, "fast loader (fastload.s)"),
    (0xFCFC, 0xFCFF, "main()'s arguments (cc65's start-up)"),
    (0xFD00, 0xFF3F, "I/O: ACIA, ports, TED"),
    (0xFFFA, 0xFFFF, "CPU vectors"),
]

# What the linker's areas hold, for the reader (trainschedule.cfg)
AREA_NAMES = {
    "ZP": "cc65's zero page", "ZPENG": "engine's zero page",
    "ZPGAME": "game's zero page", "LOW": "routes set (rt_dirs)",
    "HEADER": "BASIC line", "MAIN": "the program",
    "SNG": "map's song", "BND": "bands, signs", "FNT2": "character set copy",
    "XB": "tables (XBSS)", "HIM": "kinds of cell, level_buf",
    "HI0": "trains' rings", "HI3": "route search, code_path",
    "HI1": "draw list 1", "HI2": "draw list 2", "STK": "small variables",
    "TOP": "trains' variables, under the ROM",
    "OVL": "overlay, outside a level: choice, help",
    "OVLB": "overlay's variables, outside a level",
}

# Files on the disk (build.sh)
FILE_NAMES = {
    "trainschedule": "boot: fast loader, drive code",
    "title.b": "title picture: bitmap (packed)",
    "title.m": "title picture: colours (packed)",
    "music": "title's song",
    "game": "the game (packed)",
    "maps": "map list",
    "help": "choice of a map, page of help (packed)",
}

CODE_SEGS = {"STARTUP", "LOWCODE", "CODE", "ONCE"}
RO_SEGS = {"RODATA", "EXEHDR", "LOADADDR"}
DATA_SEGS = {"DATA", "LOWDATA"}


def hexes(text):
    return int(text, 16)


def read_inc(path):
    """game.inc's constants (NAME = $hex or decimal)."""
    out = {}
    for line in open(path):
        m = re.match(r"(\w+)\s*=\s*(\$[0-9A-Fa-f]+|\d+)", line)
        if m:
            v = m.group(2)
            out[m.group(1)] = int(v[1:], 16) if v[0] == "$" else int(v)
    return out


def read_cfg(path):
    """trainschedule.cfg: each segment's memory area."""
    text = re.sub(r"#.*", "", open(path).read())
    segs = {}
    body = re.search(r"SEGMENTS\s*{(.*?)}", text, re.S).group(1)
    for m in re.finditer(r"(\w+)\s*:\s*load\s*=\s*(\w+)", body):
        segs[m.group(1)] = m.group(2)
    return segs


def read_labels(path):
    labels = {}
    for line in open(path):
        p = line.split()
        if len(p) == 3:
            labels[p[2].lstrip(".")] = hexes(p[1])
    return labels


def read_map(path):
    """The linker's map: the segments, and the modules' parts of them."""
    text = open(path).read()
    segs = {}
    part = text.split("Segment list:")[1].split("Exports list")[0]
    for m in re.finditer(r"^(\w+)\s+([0-9A-F]{6})\s+([0-9A-F]{6})\s+([0-9A-F]{6})",
                         part, re.M):
        segs[m.group(1)] = (hexes(m.group(2)), hexes(m.group(3)), hexes(m.group(4)))
    mods = {}
    part = text.split("Modules list:")[1].split("Segment list:")[0]
    mod = None
    for line in part.splitlines():
        m = re.match(r"^(\S.*):$", line)
        if m:
            name = m.group(1)
            lib = re.search(r"\((\w+\.o)\)$", name)
            mod = "cc65 runtime" if lib else name
            mods.setdefault(mod, {})
            continue
        m = re.match(r"^\s+(\w+)\s+Offs=\w+\s+Size=([0-9A-F]+)", line)
        if m and mod:
            mods[mod][m.group(1)] = mods[mod].get(m.group(1), 0) + hexes(m.group(2))
    for seg, (start, end, size) in segs.items():  # what the linker adds itself:
        rest = size - sum(p.get(seg, 0) for p in mods.values())   # the
        if rest > 0:                                # constructors' tables
            mods.setdefault("linker tables", {})[seg] = rest
    return segs, mods


def runs(owner, lo=0, hi=0xFFFF):
    """Ranges of the same owner, in address order."""
    out = []
    start = lo
    for a in range(lo + 1, hi + 2):
        if a > hi or owner[a] != owner[start]:
            out.append((start, a - 1, owner[start]))
            start = a
    return out


def ram(build, cfg, inc, top):
    segs, mods = read_map(f"{build}/trainschedule.map")
    labels = read_labels(f"{build}/trainschedule.lbl")
    seg_area = read_cfg(cfg)

    areas = {}                  # name: (start, end inclusive, end used)
    for k, v in labels.items():
        m = re.fullmatch(r"__(\w+)_START__", k)
        if m and f"__{m.group(1)}_SIZE__" in labels and m.group(1) in AREA_NAMES:
            a = m.group(1)
            areas[a] = (v, v + labels[f"__{a}_SIZE__"] - 1,
                        labels.get(f"__{a}_LAST__", v))

    owner = [None] * 0x10000
    fixed = []
    for start, end, what in FIXED:
        if start == "MAP":
            start, end = 0xC800, 0xC800 + 3 * inc["MAP_MAX"] - 1
        fixed.append((start, end, what))
        for a in range(start, end + 1):
            owner[a] = ("fixed", what)
    clash = []
    for name, (start, end, size) in segs.items():
        if size == 0 or name in ("LOADADDR",):
            continue
        for a in range(start, end + 1):
            if owner[a] and owner[a][0] == "fixed":
                clash.append((a, name, owner[a][1]))
            owner[a] = ("seg", seg_area.get(name, "?"))
    for a, (start, end, last) in areas.items():
        for x in range(start, end + 1):
            if owner[x] is None:
                owner[x] = ("free", a)

    print("RAM: who holds what")
    print(f"  {'range':13} {'bytes':>6}  owner")
    totals = {"seg": 0, "fixed": 0, "free": 0, None: 0}
    free = []
    for start, end, own in runs(owner):
        n = end - start + 1
        kind = own[0] if own else None
        totals[kind] += n
        if kind == "seg":
            text = f"{own[1]:6} {AREA_NAMES.get(own[1], '')}"
        elif kind == "fixed":
            text = f"{'':6} {own[1]}"
        elif kind == "free":
            text = f"{'':6} ** free ** (end of {own[1]}: {AREA_NAMES.get(own[1], '')})"
            free.append((n, start, end, own[1]))
        else:
            text = f"{'':6} ** free ** (no owner)"
            free.append((n, start, end, None))
        print(f"  ${start:04X}-${end:04X}   {n:6}  {text}")
    print(f"  linker {totals['seg']}, fixed {totals['fixed']}, "
          f"free {totals['free'] + totals[None]} of 65536 bytes")
    for a, seg, what in clash[:1]:
        print(f"  WARNING: {seg} reaches into \"{what}\" at ${a:04X}")

    print()
    print("RAM: free, largest first")
    for n, start, end, area in sorted(free, reverse=True):
        if area == "MAIN":
            use = "code or data (loaded with the program)"
        elif area is None:
            use = "variables, read with the ROM off only" if start >= 0x8000 \
                else "variables"
        elif area.startswith("ZP"):
            use = "zero page variables"
        else:
            use = "variables (BSS)"
        print(f"  {n:5}  ${start:04X}-${end:04X}  {use}")

    print()
    print("RAM: the program by module (bytes)")
    cols = ["code", "rodata", "data", "bss", "zp", "high"]
    print(f"  {'module':16}" + "".join(f"{c:>8}" for c in cols) + f"{'total':>8}")
    sums = [0] * len(cols)
    rows = []
    for mod, parts in mods.items():
        row = [0] * len(cols)
        for seg, n in parts.items():
            area = seg_area.get(seg, "")
            if seg in CODE_SEGS:
                row[0] += n
            elif seg in RO_SEGS:
                row[1] += n
            elif seg in DATA_SEGS:
                row[2] += n
            elif area.startswith("ZP"):
                row[4] += n
            elif area == "MAIN":
                row[3] += n
            else:
                row[5] += n     # BSS of its own area, outside the program
        rows.append((sum(row), mod, row))
    for total, mod, row in sorted(rows, reverse=True):
        sums = [s + r for s, r in zip(sums, row)]
        print(f"  {mod:16}" + "".join(f"{r:8}" for r in row) + f"{total:8}")
    print(f"  {'':16}" + "".join(f"{s:8}" for s in sums) + f"{sum(sums):8}")
    print("  (bss: cleared with the program; high: its own memory above it)")

    if top:
        print()
        print(f"RAM: the {top} largest labels (up to the next label)")
        ends = sorted(set(v for k, v in labels.items() if not k.startswith("__"))
                      | {e + 1 for s, e, n in segs.values() if n})
        where = sorted(set(v for k, v in labels.items() if not k.startswith("__")))
        names = {}
        for k, v in labels.items():
            if not k.startswith("__"):
                names.setdefault(v, k)
        sizes = []
        for v in where:
            seg = next((s for s, (a, e, n) in segs.items() if n and a <= v <= e), None)
            if seg is None or seg in ("ZEROPAGE", "ENGZP", "GAMEZP"):
                continue
            nxt = next(e for e in ends if e > v)
            sizes.append((min(nxt, segs[seg][1] + 1) - v, v, names[v], seg))
        for n, v, name, seg in sorted(sizes, reverse=True)[:top]:
            print(f"  {n:5}  ${v:04X}  {name:20} {seg}")


def screen_text(b):
    return "".join(chr(c + 64) if 1 <= c <= 26 else chr(c) for c in b)


def maps(build, inc):
    print("Maps: how full they leave their buffers")
    print(f"  {'file':5} {'name':26} {'cells':>11} {'level':>11} {'song':>11} {'file':>11}")
    i = 1
    while os.path.exists(f"{build}/disk/MAP{i}"):
        d = open(f"{build}/disk/MAP{i}", "rb").read()[2:]
        song = d[0] | d[1] << 8
        level = d[2 + song:]
        w, h = level[0], level[1]
        name = screen_text(level[6:level.index(0, 6)])

        def of(n, m):
            return f"{n:4}/{m:<4}" + ("!" if n > m else " ")
        print(f"  map{i:<2} {name[:26]:26} {of(w * h, inc['MAP_MAX'])} "
              f"{of(len(level), LEVEL_MAX)} {of(song, inc['SONG_MAX'])} "
              f"{of(len(d), LOAD_MAX)}")
        i += 1
    print("  (cells: game.inc MAP_MAX, level: level_buf, song: SONG_MAX, "
          "file: SCRATCH)")


def d64(path, build):
    sectors = [0] + [21] * 17 + [19] * 7 + [18] * 6 + [17] * 5
    first = [0]
    for t in range(1, 36):
        first.append(first[-1] + sectors[t - 1])
    img = open(path, "rb").read()

    def sec(t, s):
        o = (first[t] + s) * 256
        return img[o:o + 256]

    bam = sec(18, 0)
    free = sum(bam[4 + 4 * (t - 1)] for t in range(1, 36) if t != 18)
    raw = f"{build}/trainschedule.raw"
    print(f"Disk: {os.path.relpath(path)}, \"{bam[0x90:0xA0].rstrip(bytes([0xA0])).decode('latin-1').lower()}\"")
    print(f"  {'file':16} {'type':4} {'blocks':>6} {'bytes':>6}  load   what")
    used = 0
    t, s = 18, 1
    while t:
        d = sec(t, s)
        for e in range(8):
            ent = d[e * 32:e * 32 + 32]
            if not ent[2] & 7:
                continue
            name = ent[5:21].rstrip(bytes([0xA0])).decode("latin-1").lower()
            blocks = ent[30] | ent[31] << 8
            used += blocks
            size, load = 0, None
            ft, fs = ent[3], ent[4]
            while ft:
                b = sec(ft, fs)
                if load is None:
                    load = b[2] | b[3] << 8
                size += 254 if b[0] else b[1] - 1
                ft, fs = b[0], b[1]
            what = FILE_NAMES.get(name, "")
            if re.fullmatch(r"map\d+", name):
                m = open(f"{build}/disk/{name.upper()}", "rb").read()[2:]
                song = m[0] | m[1] << 8
                what = f"map: song {song}, level {len(m) - 2 - song} bytes"
            elif name == "game" and os.path.exists(raw):
                what += f", unpacked {os.path.getsize(raw) - 2} bytes"
            typ = ["del", "seq", "prg", "usr", "rel"][ent[2] & 7]
            print(f"  {name:16} {typ:4} {blocks:6} {size:6}  ${load:04X}  {what}")
        t, s = d[0], d[1]
    print(f"  {used} blocks used, {free} free (664 on an empty disk)")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--build", default=os.path.join(GAME, "build"))
    ap.add_argument("--d64", help="default: <build>/trainschedule.d64")
    ap.add_argument("--top", type=int, default=15,
                    help="largest labels to list, 0 for none")
    a = ap.parse_args()
    inc = read_inc(os.path.join(GAME, "game.inc"))
    if not os.path.exists(f"{a.build}/trainschedule.map"):
        sys.exit(f"{a.build}/trainschedule.map: missing - run build.sh first")
    ram(a.build, os.path.join(GAME, "trainschedule.cfg"), inc, a.top)
    print()
    maps(a.build, inc)
    print()
    d64(a.d64 or f"{a.build}/trainschedule.d64", a.build)


if __name__ == "__main__":
    main()
