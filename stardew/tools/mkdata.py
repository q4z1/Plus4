#!/usr/bin/env python3
"""Turn the text files in data/ into what the game loads and links.

Pictures are drawn as text, one character per multicolour pixel:

    .   %00  background colour (see-through in figures)
    x   %01  the dark colour, the same all over the screen
    o   %10  the light brown, the same all over the screen
    #   %11  the colour of the character cell

Out of data/ come

    build/disk/TILES0..2   tile sets: characters and the 2x2 blocks
    build/disk/HUD         the toolbar's character set (icons)
    build/disk/ROOMnn      rooms: 20x11 tiles, colours, exits, doors
    build/gen/sprites.s    the figures, linked into the program
    build/gen/data.h       names for all of it, for the C side

With --preview the tile sets, icons and figures are also drawn into PNG
files (needs PIL), to look at without an emulator.
"""
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DATA = os.path.join(ROOT, 'data')
OUT = os.path.join(ROOT, 'build')

TILE_CHARS = 176          # codes 0..175 of a tile set; the rest is the pool
MAX_TILES = 128
PIX = {'.': 0, 'x': 1, 'o': 2, '#': 3}

COLOURS = ['black', 'white', 'red', 'cyan', 'purple', 'green', 'blue',
           'yellow', 'orange', 'brown', 'ygreen', 'pink', 'teal', 'lblue',
           'dblue', 'lgreen']


def colour(tok):
    """'green3' -> TED colour byte (luminance in bits 4-6)."""
    m = re.fullmatch(r'([a-z]+)([0-7])', tok)
    if not m or m.group(1) not in COLOURS:
        raise ValueError(f'bad colour {tok!r}')
    return int(m.group(2)) << 4 | COLOURS.index(m.group(1))


def cell_colour(tok):
    """A colour cell in multicolour mode: only colours 0-7, bit 3 set."""
    c = colour(tok)
    if c & 0x0F > 7:
        raise ValueError(f'{tok}: a colour cell can only hold colours 0-7')
    return c | 0x08


def fail(where, msg):
    sys.exit(f'{where}: {msg}')


# ---------------------------------------------------------------------------
# Reading the art files
# ---------------------------------------------------------------------------

def blocks(path):
    """Yield (header words, picture lines, line number) for every block.

    A block starts with a line that does not look like picture data and is
    followed by picture lines (only the four pixel characters)."""
    lines = open(path).read().split('\n')
    i = 0
    while i < len(lines):
        line = lines[i].split(';')[0].rstrip()
        if not line.strip() or line.lstrip().startswith('#!'):
            i += 1
            continue
        head = line.split()
        start = i + 1
        i += 1
        pic = []
        while i < len(lines):
            l = lines[i].split(';')[0].rstrip()
            if l and all(ch in PIX for ch in l.strip()) and l == l.strip():
                pic.append(l)
                i += 1
            else:
                break
        yield head, pic, start


def opts(words):
    d = {}
    for w in words:
        if '=' in w:
            k, v = w.split('=', 1)
            d[k] = v
    return d


def pic_bytes(pic, where):
    """Picture lines (4n pixels wide) -> rows of bytes."""
    rows = []
    for l in pic:
        if len(l) % 4:
            fail(where, f'line {l!r} is not a multiple of 4 pixels')
        b = []
        for k in range(0, len(l), 4):
            v = 0
            for ch in l[k:k + 4]:
                v = v << 2 | PIX[ch]
            b.append(v)
        rows.append(b)
    return rows


class CharSet:
    """Characters of a tile set, identical ones shared."""

    def __init__(self, first, limit, name):
        self.chars = []
        self.index = {}
        self.first = first
        self.limit = limit
        self.name = name

    def add(self, data):
        data = tuple(data)
        if data not in self.index:
            code = self.first + len(self.chars)
            if code >= self.limit:
                sys.exit(f'{self.name}: more than {self.limit - self.first} characters')
            self.index[data] = code
            self.chars.append(data)
        return self.index[data]


def cells_of(rows, cw, ch):
    """Cut rows of bytes (cw bytes, ch*8 lines) into characters, row by row."""
    out = []
    for cy in range(ch):
        for cx in range(cw):
            out.append([rows[cy * 8 + l][cx] for l in range(8)])
    return out


def colour_grid(o, key, n, where):
    v = o.get(key)
    if v is None:
        fail(where, f'no {key}=')
    toks = v.split(',')
    if len(toks) == 1:
        toks = toks * n
    elif len(toks) == 2 and n == 4:          # top cells, bottom cells
        toks = [toks[0], toks[0], toks[1], toks[1]]
    if len(toks) != n:
        fail(where, f'{key}= needs 1 or {n} colours')
    return [cell_colour(t) for t in toks]


FLAGS = {'solid': 1, 'water': 2, 'till': 4, 'soil': 8, 'wet': 16,
         'door': 32, 'use': 64, 'over': 128}


def read_tileset(name):
    """data/tiles_<name>.txt -> (tiles[name] = (chars, attrs, flag, sets), order)

    chars: the four characters' bytes (top left, top right, bottom left,
    bottom right); sets: the tile sets it belongs to (in=farm,village), None
    for all of them. Codes are handed out per tile set (tile_set())."""
    path = os.path.join(DATA, f'tiles_{name}.txt')
    tiles = {}
    order = []
    for head, pic, ln in blocks(path):
        where = f'{path}:{ln}'
        kind = head[0]
        o = opts(head[1:])
        flag = 0
        for f in o.get('flags', '').split(','):
            if f:
                flag |= FLAGS[f]
        sets = set(o['in'].split(',')) if 'in' in o else None
        if kind == 'tile':
            tname = head[1]
            if 'top' in o:             # top half of one tile, bottom half of another
                a, b = tiles[o['top']], tiles[o['bottom']]
                tiles[tname] = (a[0][:2] + b[0][2:], a[1][:2] + b[1][2:], flag, sets)
                order.append(tname)
                continue
            if 'same' in o:            # the characters of another tile, other colours
                src = tiles[o['same']]
                chars = src[0]
            else:
                if len(pic) != 16:
                    fail(where, f'tile {tname}: {len(pic)} lines, not 16')
                chars = [tuple(c) for c in cells_of(pic_bytes(pic, where), 2, 2)]
            attrs = colour_grid(o, 'col', 4, where)
            if 'flags' not in o and 'same' in o:
                flag = tiles[o['same']][2]
            tiles[tname] = (chars, attrs, flag, sets)
            order.append(tname)
        elif kind == 'big':
            # big NAME WxH: W*H tiles cut from one picture, named NAME_x_y,
            # colours per character cell, row by row (cols=...)
            tname = head[1]
            w, h = map(int, head[2].split('x'))
            if len(pic) != 16 * h or any(len(l) != 8 * w for l in pic):
                fail(where, f'big {tname}: needs {8*w}x{16*h} pixels')
            rows = pic_bytes(pic, where)
            cols = colour_grid(o, 'col', 4 * w * h, where) if ',' in o.get('col', '') \
                else [cell_colour(o['col'])] * (4 * w * h)
            solid = o.get('solid')
            for ty in range(h):
                for tx in range(w):
                    chars, attrs = [], []
                    for cy in range(2):
                        for cx in range(2):
                            gx, gy = tx * 2 + cx, ty * 2 + cy
                            chars.append(tuple(rows[gy * 8 + l][gx] for l in range(8)))
                            attrs.append(cols[gy * 2 * w + gx])
                    f = flag
                    if solid is not None:
                        # solid=rows from the top that are solid, e.g. solid=2
                        f = flag | (1 if ty >= h - int(solid) or solid == 'all' else 0)
                    tn = f'{tname}_{tx}_{ty}'
                    tiles[tn] = (chars, attrs, f, sets)
                    order.append(tn)
        else:
            fail(where, f'unknown block {kind!r}')
    if len(order) > MAX_TILES:
        sys.exit(f'{path}: {len(order)} tiles, at most {MAX_TILES}')
    return tiles, order


def tile_set(name, tiles, order, setname):
    """The characters of the tiles that belong to tile set setname, codes
    handed out to them; the others keep their number but get no
    characters (code 0) - the two outdoor sets number their tiles alike, so
    the game's T_... names hold in both. -> (charset, tiles[name] =
    (codes, attrs, flag))"""
    cs = CharSet(0, TILE_CHARS, f'tile set {setname}')
    cs.add([0xFF] * 8)               # code 0: the separator row, all %11
    out = {}
    for t in order:
        chars, attrs, flag, sets = tiles[t]
        if sets is None or setname in sets:
            out[t] = ([cs.add(c) for c in chars], attrs, flag)
        else:
            out[t] = ([0] * 4, [0] * 4, 1)
    return cs, out


def water_pairs(cs, tiles, order):
    """The characters that ripple (engine.s water): of every water tile,
    the halves - two characters side by side - as (left, right, lines):
    lines a bit for each line (bit 0 the top one) without a pixel of the
    background - the shore's top half moves only where it is water. They
    must not be anybody else's."""
    pairs = []
    for t in order:
        codes, attrs, flag = tiles[t]
        if not flag & FLAGS['water'] or codes == [0] * 4:
            continue
        for a, b in ((codes[0], codes[1]), (codes[2], codes[3])):
            ca, cb = cs.chars[a - cs.first], cs.chars[b - cs.first]
            lines = sum(1 << l for l in range(8)
                        if all(((v >> s) & 3) for v in (ca[l], cb[l]) for s in (0, 2, 4, 6)))
            if lines and (a, b, lines) not in pairs:
                pairs.append((a, b, lines))
    for t in order:
        codes, attrs, flag = tiles[t]
        if not flag & FLAGS['water'] and codes != [0] * 4:
            for a, b, lines in pairs:
                if a in codes or b in codes:
                    sys.exit(f'{cs.name}: water character in tile {t}, which is not water')
    if len(pairs) > 8:
        sys.exit(f'{cs.name}: {len(pairs)} pairs of water characters, at most 8')
    return pairs


def tileset_file(cs, tiles, order):
    """nchars, ntiles, the characters, then per quarter the codes, per
    quarter the colours, and the flags, each ntiles long; then the number
    of rippling pairs of characters and the pairs."""
    n = len(order)
    out = bytearray([len(cs.chars), n])
    for c in cs.chars:
        out += bytes(c)
    for k in range(4):
        out += bytes(tiles[t][0][k] for t in order)
    for k in range(4):
        out += bytes(tiles[t][1][k] for t in order)
    out += bytes(tiles[t][2] for t in order)
    pairs = water_pairs(cs, tiles, order)
    out.append(len(pairs))
    for a, b, lines in pairs:
        out += bytes([a, b, lines])
    return bytes(out)


# ---------------------------------------------------------------------------
# Toolbar characters: icons 2x2 like tiles, from code 64 on
# ---------------------------------------------------------------------------

HUD_FIRST = 64


def read_hud():
    path = os.path.join(DATA, 'hud.txt')
    cs = CharSet(HUD_FIRST, 256, path)
    icons = {}
    order = []
    for head, pic, ln in blocks(path):
        where = f'{path}:{ln}'
        o = opts(head[1:])
        if head[0] == 'icon':
            if len(pic) != 16:
                fail(where, f'icon {head[1]}: {len(pic)} lines, not 16')
            codes = [cs.add(c) for c in cells_of(pic_bytes(pic, where), 2, 2)]
            icons[head[1]] = (codes, colour_grid(o, 'col', 4, where))
            order.append(head[1])
        elif head[0] == 'char':
            # a single character, 4 pixels wide (multicolour) or with hires=1
            # 8 wide: then '#' is set and '.' is not
            if o.get('hires'):
                b = []
                for l in pic:
                    v = 0
                    for chh in l:
                        v = v << 1 | (1 if chh != '.' else 0)
                    b.append(v)
                code = cs.add(b)
            else:
                code = cs.add([r[0] for r in pic_bytes(pic, where)])
            icons[head[1]] = ([code], [])
            order.append(head[1])
        else:
            fail(where, f'unknown block {head[0]!r}')
    font = bytearray(2048)
    for i, c in enumerate(cs.chars):
        font[(HUD_FIRST + i) * 8:(HUD_FIRST + i) * 8 + 8] = bytes(c)
    font[0:8] = bytes([0xFF] * 8)    # the separator: all %11, as in the tile sets
    return font, icons, order


# ---------------------------------------------------------------------------
# Figures
# ---------------------------------------------------------------------------

def read_sprites():
    path = os.path.join(DATA, 'sprites.txt')
    sprites = []
    for head, pic, ln in blocks(path):
        where = f'{path}:{ln}'
        if head[0] != 'sprite':
            fail(where, f'unknown block {head[0]!r}')
        if any(len(l) != 8 for l in pic) or not 1 <= len(pic) <= 24:
            fail(where, f'sprite {head[1]}: 8 pixels wide, 1..24 lines')
        sprites.append((head[1], pic_bytes(pic, where)))
    return sprites


# ---------------------------------------------------------------------------
# Rooms
# ---------------------------------------------------------------------------

ROOM_W, ROOM_H = 20, 11

# the tile sets by number (a room's byte 220), and which tile file each is
# made from: a room "set outdoor" gets the farm's if it is a farm room
SETS = ['farm', 'indoor', 'mine', 'village']
SET_OF = {'outdoor': ['farm', 'village'], 'indoor': ['indoor'], 'mine': ['mine']}


def read_rooms(tilesets):
    """data/rooms.txt: every room in one file."""
    path = os.path.join(DATA, 'rooms.txt')
    text = open(path).read().split('\n')
    rooms = {}
    order = []
    legend = {}
    cur = None
    i = 0
    while i < len(text):
        raw = text[i]
        line = raw.split(';')[0].rstrip()
        i += 1
        if not line.strip():
            continue
        w = line.split()
        if w[0] == 'legend':
            # legend <set> <char> <tile> ...
            ts = w[1]
            legend.setdefault(ts, {})
            for pair in w[2:]:
                if len(pair) < 3 or pair[1] != '=':
                    sys.exit(f'{path}:{i}: bad legend entry {pair!r}')
                legend[ts][pair[0]] = pair[2:]
        elif w[0] == 'room':
            cur = {'name': w[1], 'set': None, 'exits': {}, 'doors': [],
                   'pal': None, 'flags': 0, 'grid': [], 'npc': 0, 'music': 0}
            rooms[w[1]] = cur
            order.append(w[1])
        elif w[0] == 'set':
            cur['set'] = w[1]
        elif w[0] == 'pal':
            cur['pal'] = [colour(t) for t in w[1:5]]
        elif w[0] == 'exit':
            for pair in w[1:]:
                d, r = pair.split('=')
                cur['exits'][d] = r
        elif w[0] == 'door':
            # door x y ROOM x y
            cur['doors'].append((int(w[1]), int(w[2]), w[3], int(w[4]), int(w[5])))
        elif w[0] == 'flags':
            for f in w[1:]:
                cur['flags'] |= {'farm': 1, 'season': 2, 'mine': 4, 'indoor': 8}[f]
        elif w[0] == 'map':
            for _ in range(ROOM_H):
                row = text[i].rstrip('\n')
                i += 1
                if len(row) < ROOM_W:
                    row = row + ' ' * (ROOM_W - len(row))
                cur['grid'].append(row[:ROOM_W])
        else:
            sys.exit(f'{path}:{i}: unknown line {line!r}')
    files = {}
    starts = {}
    ids = {n: k for k, n in enumerate(order)}
    import forest
    import edges
    for n in order:
        r = rooms[n]
        ts = r['set']
        setname = ts if ts != 'outdoor' else ('farm' if r['flags'] & 1 else 'village')
        sid = SETS.index(setname)
        _, tiles, torder = tilesets[setname]
        b = bytearray(250)
        grid = r['grid']

        def is_tree(x, y, grid=grid, ts=ts):
            # off the room the wood goes on
            if not (0 <= x < ROOM_W and 0 <= y < ROOM_H):
                return True
            return legend[ts].get(grid[y][x]) == 'TREE'

        def is_path(x, y, grid=grid, ts=ts):
            # off the room, and at a door or a bridge, the path goes on
            if not (0 <= x < ROOM_W and 0 <= y < ROOM_H):
                return True
            return legend[ts].get(grid[y][x]) in ('PATH', 'DOOR', 'WATER', 'SHORE', 'CAVE')
        for y, row in enumerate(grid):
            for x, ch in enumerate(row):
                tn = legend[ts].get(ch)
                if tn is None:
                    sys.exit(f'room {n}: no tile for {ch!r} in legend {ts}')
                if tn == 'TREE':                # one of a wood: forest.py
                    tn = forest.pick(is_tree, x, y) or tn
                elif tn == 'PATH':              # grass at its sides: edges.py
                    tn = edges.pick(is_path, x, y) or tn
                if tiles[tn][2] == 1 and tiles[tn][0] == [0] * 4:
                    sys.exit(f'room {n}: tile {tn} is not in tile set {setname}')
                b[y * ROOM_W + x] = torder.index(tn)
        b[220] = sid
        b[221:225] = bytes(r['pal'])
        for k, d in enumerate('NSEW'):
            b[225 + k] = ids[r['exits'][d]] if d in r['exits'] else 255
        b[229] = r['flags']
        for k in range(4):
            if k < len(r['doors']):
                x, y, to, tx, ty = r['doors'][k]
                b[230 + k * 5:235 + k * 5] = bytes([x, y, ids[to], tx, ty])
            else:
                b[230 + k * 5] = 255
        files[n] = bytes(b)
        # where the test build's menu puts the farmer: the tile nearest the
        # middle he can stand on (no wall, door or water); in the mine where
        # the ladder lands, kept clear of rocks
        if setname == 'mine' and not r['doors']:   # a floor, not the entrance
            starts[n] = (9, 9)
        else:
            free = [(abs(x - 10) * 2 + abs(y - 5) * 3, x, y)
                    for y in range(ROOM_H) for x in range(ROOM_W)
                    if not tiles[torder[b[y * ROOM_W + x]]][2] & (FLAGS['solid'] | FLAGS['door'] | FLAGS['water'])
                    and y < ROOM_H - 1]
            starts[n] = min(free)[1:]
    return order, files, starts


# ---------------------------------------------------------------------------
# Music
# ---------------------------------------------------------------------------

NOTE_BASE = 48                              # note 1 is C3 (MIDI 48)


def read_music():
    """data/music.txt -> ([(name, v1, v2)], each voice a list of (note, len))"""
    path = os.path.join(DATA, 'music.txt')
    songs = []
    for ln, raw in enumerate(open(path), 1):
        line = raw.split(';')[0].split()
        if not line:
            continue
        if line[0] == 'song':
            songs.append([line[1], [], []])
            continue
        if line[0] not in ('v1', 'v2'):
            sys.exit(f'{path}:{ln}: unknown line')
        voice = songs[-1][1 if line[0] == 'v1' else 2]
        length = voice[-1][1] if voice else 40
        for tok in line[1:]:
            if tok == '|':
                continue
            name, _, l = tok.partition(':')
            if l:
                length = int(l)
            if name == 'r':
                n = 0
            else:
                m = re.fullmatch(r'([A-G])([#b]?)([3-7])', name)
                if not m:
                    sys.exit(f'{path}:{ln}: bad note {tok!r}')
                midi = 'C D EF G A B'.index(m.group(1)) + {'': 0, '#': 1, 'b': -1}[m.group(2)] \
                    + 12 * (int(m.group(3)) + 1)
                n = midi - NOTE_BASE + 1
            voice.append((n, length))
    return songs


def music_asm(songs):
    s = ['; music (data/music.txt)', '        .export _mus_v1, _mus_v2, _mus_s1, _mus_s2',
         '        .export _ton_lo, _ton_hi']
    lo, hi = [0], [0]
    for n in range(1, 61):
        f = 440.0 * 2 ** ((NOTE_BASE + n - 1 - 69) / 12)
        reg = max(0, round(1024 - 111860.8 / f))
        lo.append(reg & 255)
        hi.append(reg >> 8)
    s.append('_ton_lo: .byte ' + ', '.join(map(str, lo)))
    s.append('_ton_hi: .byte ' + ', '.join(map(str, hi)))
    for v in (1, 2):
        data, starts = [], []
        for name, v1, v2 in songs:
            starts.append(len(data))
            for n, l in (v1 if v == 1 else v2):
                data += [n, l]
            data.append(255)                # back to the start of the song
        if len(data) > 256:
            sys.exit(f'music: voice {v} has {len(data)} bytes, at most 256')
        s.append(f'_mus_s{v}: .byte ' + ', '.join(map(str, starts)))
        s.append(f'_mus_v{v}:')
        for k in range(0, len(data), 16):
            s.append('        .byte ' + ', '.join(map(str, data[k:k + 16])))
    for name, v1, v2 in songs:
        t1, t2 = sum(l for _, l in v1), sum(l for _, l in v2)
        if t1 != t2:
            print(f'music: song {name}: voice 1 lasts {t1}, voice 2 {t2} frames')
    return s


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

def cname(s):
    return re.sub(r'[^A-Z0-9_]', '_', s.upper())


def write_prg(path, data, addr=0):
    with open(path, 'wb') as f:
        f.write(bytes([addr & 0xFF, addr >> 8]) + data)


EXOMIZER = os.environ.get('EXOMIZER', os.path.join(
    os.environ.get('CC65_BIN', os.path.expanduser('~/.local/share/cc65-vs64/bin')), 'exomizer'))


def write_packed(name, data):
    """A file for the disk, packed by exomizer ("raw": unpack.s unpacks it
    forwards, to wherever the game wants it). Returns the packed size."""
    with tempfile.TemporaryDirectory() as tmp:
        src, dst = os.path.join(tmp, 'in'), os.path.join(tmp, 'out')
        open(src, 'wb').write(data)
        subprocess.run([EXOMIZER, 'raw', '-q', '-o', dst, src], check=True)
        packed = open(dst, 'rb').read()
    write_prg(os.path.join(OUT, 'disk', name), packed, 0)
    return len(packed)


def main():
    preview = '--preview' in sys.argv
    os.makedirs(os.path.join(OUT, 'disk'), exist_ok=True)
    os.makedirs(os.path.join(OUT, 'gen'), exist_ok=True)
    h = ['/* generated by tools/mkdata.py - do not edit */', '#ifndef DATA_H',
         '#define DATA_H', '']

    # Four tile sets: the farm and the village share one numbering of the
    # outdoor tiles (T_...), each with the characters of its own tiles.
    tilesets = {}
    for name in ('outdoor', 'indoor', 'mine'):
        tiles, order = read_tileset(name)
        pre = {'outdoor': 'T_', 'indoor': 'I_', 'mine': 'M_'}[name]
        h.append(f'/* {name} tiles: {len(order)} */')
        for i, n in enumerate(order):
            h.append(f'#define {pre}{cname(n)} {i}')
        h.append('')
        for setname in SET_OF[name]:
            k = SETS.index(setname)
            cs, stiles = tile_set(name, tiles, order, setname)
            tilesets[setname] = (cs, stiles, order)
            tf = tileset_file(cs, stiles, order)
            n = write_packed(f'TILES{k}', tf)
            h.append(f'#define TILES{k}_SIZE {len(tf)}    /* {setname}, {len(cs.chars)} characters */')
            h.append(f'#define TILES{k}_PACKED {n}')
        h.append('')

    font, icons, iorder = read_hud()
    n = write_packed('HUD', bytes(font))
    h.append(f'#define HUD_PACKED {n}')
    h.append('/* toolbar characters */')
    for n in iorder:
        h.append(f'#define H_{cname(n)} {icons[n][0][0]}')
    h.append('')
    # icon colours for the C side
    icol = [n for n in iorder if icons[n][1]]
    h.append(f'#define N_ICONS {len(icol)}')
    for k, n in enumerate(icol):
        h.append(f'#define IC_{cname(n)} {k}')
    h.append('')

    sprites = read_sprites()
    s = ['; generated by tools/mkdata.py - do not edit', '        .rodata',
         '        .export _spr_tab, _spr_h']
    s.append('_spr_tab:')
    for n, _ in sprites:
        s.append(f'        .word spr_{n}')
    s.append('_spr_h:')
    s.append('        .byte ' + ', '.join(str(len(r)) for _, r in sprites))
    for n, rows in sprites:
        # the lines (2 bytes each), then for engine.s's r_fig a byte a line
        # with a bit for every pixel that is not %00, and one for every
        # pixel that is %11 (bit 7 the left pixel)
        s.append(f'spr_{n}:')
        for r in rows:
            s.append('        .byte ' + ', '.join(f'${b:02X}' for b in r))
        px, p11 = [], []
        for r in rows:
            pix = [(r[k // 4] >> (6 - 2 * (k % 4))) & 3 for k in range(8)]
            px.append(sum(128 >> k for k in range(8) if pix[k]))
            p11.append(sum(128 >> k for k in range(8) if pix[k] == 3))
        s.append('        .byte ' + ', '.join(f'${b:02X}' for b in px))
        s.append('        .byte ' + ', '.join(f'${b:02X}' for b in p11))
    # icon code and colour tables
    s.append('        .export _icon_code, _icon_col')
    s.append('_icon_code:')
    for n in icol:
        s.append('        .byte ' + ', '.join(str(c) for c in icons[n][0]))
    s.append('_icon_col:')
    for n in icol:
        s.append('        .byte ' + ', '.join(f'${c:02X}' for c in icons[n][1]))
    songs = read_music()
    s += music_asm(songs)
    open(os.path.join(OUT, 'gen', 'sprites.s'), 'w').write('\n'.join(s) + '\n')
    h.append('/* songs */')
    for k, (n, _, _) in enumerate(songs):
        h.append(f'#define SONG_{cname(n)} {k + 1}')
    h.append('')
    h.append('/* figures */')
    for k, (n, _) in enumerate(sprites):
        h.append(f'#define S_{cname(n)} {k}')
    h.append('')

    rorder, rfiles, rstarts = read_rooms(tilesets)
    h.append('/* rooms */')
    most = 0
    for k, n in enumerate(rorder):
        most = max(most, write_packed(f'ROOM{k:02d}', rfiles[n]))
        h.append(f'#define R_{cname(n)} {k}')
    h.append(f'#define N_ROOMS {len(rorder)}')
    h.append(f'#define ROOM_PACKED_MAX {most}')
    h.append('#define ROOM_START_X { ' + ', '.join(str(rstarts[n][0]) for n in rorder) + ' }')
    h.append('#define ROOM_START_Y { ' + ', '.join(str(rstarts[n][1]) for n in rorder) + ' }')
    h.append('')
    h.append('#endif')
    open(os.path.join(OUT, 'gen', 'data.h'), 'w').write('\n'.join(h) + '\n')

    for name, (cs, tiles, order) in tilesets.items():
        print(f'{name}: {len(cs.chars)}/{TILE_CHARS} characters, {len(order)}/{MAX_TILES} tiles')
    print(f'hud: {len(font)} bytes, {len(iorder)} entries; sprites: {len(sprites)}; rooms: {len(rorder)}')

    if preview:
        make_preview(tilesets, font, icons, iorder, sprites, rorder, rfiles)


# ---------------------------------------------------------------------------
# Preview (PIL)
# ---------------------------------------------------------------------------

PAL = None


def ted_rgb(c):
    global PAL
    if PAL is None:
        PAL = []
        for line in open(os.path.join(HERE, 'yape-pal.txt')):
            if re.match(r'^[0-9a-f]{2} [0-9a-f]{2} [0-9a-f]{2}', line):
                PAL.append(tuple(int(x, 16) for x in line.split()[:3]))
    return PAL[(c >> 4 & 7) * 16 + (c & 15)]


def draw_char(img, x, y, data, cols, scale=2):
    """cols = (bg, c1, c2, cell colour) as TED bytes."""
    px = img.load()
    for l in range(8):
        b = data[l]
        for p in range(4):
            v = b >> (6 - 2 * p) & 3
            rgb = ted_rgb(cols[v] & 0x77 if v == 3 else cols[v])
            for sx in range(2 * scale):
                for sy in range(scale):
                    px[x + p * 2 * scale + sx, y + l * scale + sy] = rgb


def make_preview(tilesets, font, icons, iorder, sprites, rorder, rfiles):
    from PIL import Image
    pdir = os.path.join(OUT, 'preview')
    os.makedirs(pdir, exist_ok=True)
    pals = {'farm': [colour('green3'), colour('brown0'), colour('orange5')],
            'village': [colour('green3'), colour('brown0'), colour('orange5')],
            'indoor': [colour('brown4'), colour('brown0'), colour('orange5')],
            'mine': [colour('brown1'), colour('black0'), colour('orange5')]}
    for name, (cs, tiles, order) in tilesets.items():
        img = Image.new('RGB', (8 * 40 + 8, ((len(order) + 7) // 8) * 40 + 8), (40, 40, 40))
        for i, n in enumerate(order):
            codes, attrs, _ = tiles[n]
            x0, y0 = 8 + (i % 8) * 40, 8 + (i // 8) * 40
            for k in range(4):
                c = cs.chars[codes[k] - cs.first]
                draw_char(img, x0 + (k & 1) * 16, y0 + (k >> 1) * 16, c,
                          pals[name] + [attrs[k]])
        img.save(os.path.join(pdir, f'tiles_{name}.png'))
    # rooms, as the game shows them
    for k, n in enumerate(rorder):
        b = rfiles[n]
        name = SETS[b[220]]
        cs, tiles, order = tilesets[name]
        pal = list(b[221:224])
        img = Image.new('RGB', (320 * 2, 176 * 2), (0, 0, 0))
        for ty in range(11):
            for tx in range(20):
                codes, attrs, _ = tiles[order[b[ty * 20 + tx]]]
                for q in range(4):
                    c = cs.chars[codes[q] - cs.first]
                    draw_char(img, (tx * 2 + (q & 1)) * 16, (ty * 2 + (q >> 1)) * 16, c,
                              pal + [attrs[q]])
        img.save(os.path.join(pdir, f'room_{k:02d}_{n}.png'))
    # icons
    img = Image.new('RGB', (8 * 40 + 8, ((len(iorder) + 7) // 8) * 40 + 8), (40, 40, 40))
    hp = [colour('brown1'), colour('black0'), colour('orange5')]
    i = 0
    for n in iorder:
        codes, cols = icons[n]
        if not cols:
            continue
        x0, y0 = 8 + (i % 8) * 40, 8 + (i // 8) * 40
        for q in range(4):
            c = font[codes[q] * 8:codes[q] * 8 + 8]
            draw_char(img, x0 + (q & 1) * 16, y0 + (q >> 1) * 16, c, hp + [cols[q]])
        i += 1
    img.save(os.path.join(pdir, 'icons.png'))
    # figures, on grass
    img = Image.new('RGB', (8 * 40 + 8, ((len(sprites) + 7) // 8) * 56 + 8), ted_rgb(colour('green3')))
    px = img.load()
    fp = [colour('green3'), colour('brown0'), colour('orange5'), colour('blue4')]
    for i, (n, rows) in enumerate(sprites):
        x0, y0 = 8 + (i % 8) * 40, 8 + (i // 8) * 56
        for l, r in enumerate(rows):
            for bi, b in enumerate(r):
                for p in range(4):
                    v = b >> (6 - 2 * p) & 3
                    if v == 0:
                        continue
                    rgb = ted_rgb(fp[v])
                    for sx in range(4):
                        for sy in range(2):
                            px[x0 + (bi * 4 + p) * 4 + sx, y0 + l * 2 + sy] = rgb
    img.save(os.path.join(pdir, 'sprites.png'))
    print(f'preview in {pdir}')


if __name__ == '__main__':
    main()
