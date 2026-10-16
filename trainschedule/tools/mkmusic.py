#!/usr/bin/env python3
"""A song from data/music.txt for the player in music.inc, placed at ADDR.

    mkmusic.py <music.txt> <song> <out.prg> --org ADDR

The title's is a file of its own, "music", at $E800; the maps' are part of
their files (tools/mklevel.py builds them with build()), at SONG_BUF.

The song:
  'M', its volume (0-8), the addresses of its two tables of the TED's
  frequency register (low bytes, high bytes) and of its two voices
  the tables: one entry for each note the song uses (the first unused:
  0 is a rest)
  each voice: a note (its number in the tables; 0 a rest) and its length
  in frames (bit 7: staccato, sounding for half of it; a tied note is
  several of at most two frames, which the player never silences early);
  $FE and an address
  plays a pattern there (which ends with $FD) and goes on after it; $FF
  ends the voice: from its start again.

The patterns are found here (patterns()): whatever run of notes comes
more than once, in either voice, is put once and called. In the text (see
music.txt) "pattern NAME" starts a pattern, its v1/v2 lines its two voices;
"@NAME" in a voice plays that voice's part of it - a way to write it, the
song played out before it is packed.
"""
import re
import sys

NOTE_BASE = 48                              # C3: MIDI 48
TED_HZ = 17734470 / 160                     # PAL: the TED's sound clock


def note_number(name, where):
    m = re.fullmatch(r'([A-G])([#b]?)([2-7])', name)
    if not m:
        sys.exit(f'{where}: bad note {name!r}')
    return 'C D EF G A B'.index(m.group(1)) + {'': 0, '#': 1, 'b': -1}[m.group(2)] \
        + 12 * (int(m.group(3)) + 1)


def read(path, want):
    """the song: {'volume': n, 'v1': [...], 'v2': [...], 'pat': {name: {'v1': [...], 'v2': [...]}}}
    a voice: ('n', midi or 0, frames, staccato, tied) or ('call', name)"""
    song, target, cur = None, None, None
    for ln, raw in enumerate(open(path), 1):
        line = raw.split(';')[0].split()
        where = f'{path}:{ln}'
        if not line:
            continue
        if line[0] == 'song':
            cur = line[1]
            if cur == want:
                song = {'volume': 6, 'v1': [], 'v2': [], 'pat': {}}
                target = song
            continue
        if cur != want:
            continue
        if line[0] == 'volume':
            song['volume'] = int(line[1])
        elif line[0] == 'pattern':
            target = song['pat'].setdefault(line[1], {'v1': [], 'v2': []})
        elif line[0] == 'main':
            target = song
        elif line[0] in ('v1', 'v2'):
            voice = target[line[0]]
            last = [e for e in voice if e[0] == 'n']
            length, stacc, tied = last[-1][2:] if last else (40, False, False)
            for tok in line[1:]:
                if tok == '|':
                    continue
                if tok.startswith('@'):
                    voice.append(('call', tok[1:]))
                    continue
                name, _, l = tok.partition(':')
                if l:
                    stacc, tied = l.endswith('.'), l.endswith('~')
                    length = int(l.rstrip('.~'))
                    if not 1 <= length <= 127:
                        sys.exit(f'{where}: length {length} not 1-127')
                n = 0 if name == 'r' else note_number(name, where)
                voice.append(('n', n, length, stacc, tied))
        else:
            sys.exit(f'{where}: unknown line')
    if not song:
        sys.exit(f'{path}: no song {want}')
    return song


def frames(voice, pats, v):
    t = 0
    for e in voice:
        t += frames(pats[e[1]][v], pats, v) if e[0] == 'call' else e[2]
    return t


def assemble(song, name, org):
    """the song as the player reads it, placed at org: its bytes"""
    pats = song['pat']
    for v in ('v1', 'v2'):
        for e in song[v]:
            if e[0] == 'call' and e[1] not in pats:
                sys.exit(f'{name}: no pattern {e[1]}')
    used = sorted({e[1] for part in [song] + list(pats.values()) for v in ('v1', 'v2')
                   for e in part[v] if e[0] == 'n' and e[1]})
    index = {m: k + 1 for k, m in enumerate(used)}
    regs = []
    for m in used:
        reg = round(1024 - TED_HZ / (440.0 * 2 ** ((m - 69) / 12)))
        if reg < 0:
            sys.exit(f'{name}: note {m} below what the TED can play')
        regs.append(reg)

    def flat(events, v):
        """a voice's notes, its patterns played out: (byte, byte) each"""
        out = []
        for e in events:
            if e[0] == 'call':
                out += flat(pats[e[1]][v], v)
                continue
            # tied: as notes of two frames, which the player never
            # silences (GATE), so it sounds to its end
            parts = [2] * (e[2] // 2) + [1] * (e[2] % 2) if e[4] else [e[2]]
            for f in parts:
                out.append((index[e[1]] if e[1] else 0, f | (0x80 if e[3] else 0)))
        return out

    voices = [flat(song[v], v) for v in ('v1', 'v2')]
    mains, parts = patterns(voices)
    # the voices, then the patterns (both voices' calls may share one):
    # twice, the first time to learn where the patterns are
    at = [0] * len(parts)
    for _ in range(2):
        lo = org + 10
        hi = lo + 1 + len(regs)
        body, heads, pos = [], [], hi + 1 + len(regs)

        def put(items, end):
            nonlocal pos
            for it in items:
                b = [0xFE, at[it] & 255, at[it] >> 8] if isinstance(it, int) else list(it)
                body.extend(b)
                pos += len(b)
            body.append(end)
            pos += 1
        for m in mains:
            heads.append(pos)
            put(m, 0xFF)
        for k, part in enumerate(parts):
            at[k] = pos
            put(part, 0xFD)
    head = [0x4D, song['volume'], lo & 255, lo >> 8, hi & 255, hi >> 8,
            heads[0] & 255, heads[0] >> 8, heads[1] & 255, heads[1] >> 8]
    data = bytes(head + [0] + [r & 255 for r in regs] + [0] + [r >> 8 for r in regs] + body)
    if unpack(data, org) != voices:
        sys.exit(f'{name}: the patterns do not play the song')
    return data


def patterns(voices):
    """The voices made shorter: what comes more than once (in either) once
    as a pattern, called ($FE and its address, 3 bytes) wherever it comes.
    The player cannot call from a pattern, so patterns are of notes only.
    Greedy: again and again the run of notes that saves the most bytes.
    voices: lists of notes; returns them with an int (a pattern's number)
    for each call, and the patterns."""
    seqs = [list(v) for v in voices]
    parts = []
    while True:
        best = None
        for L in range(2, max(len(s) for s in seqs) // 2 + 1):
            where = {}
            for si, sq in enumerate(seqs):
                run = 0                         # notes before i since a call
                for i, it in enumerate(sq):
                    run = 0 if isinstance(it, int) else run + 1
                    if run >= L:
                        where.setdefault(tuple(sq[i - L + 1:i + 1]), []).append((si, i - L + 1))
            if not where:
                break
            for key, at in where.items():
                if len(at) < 2:
                    continue
                n, last = 0, (-1, -1)
                for si, i in at:                # not overlapping
                    if si != last[0] or i >= last[1]:
                        n += 1
                        last = (si, i + L)
                save = n * (2 * L - 3) - (2 * L + 1)
                if save > 0 and (not best or save > best[0]):
                    best = (save, key, L)
        if not best:
            return seqs, parts
        _, key, L = best
        k = len(parts)
        parts.append(list(key))
        for si, sq in enumerate(seqs):
            out, i = [], 0
            while i < len(sq):
                if tuple(sq[i:i + L]) == key:
                    out.append(k)
                    i += L
                else:
                    out.append(sq[i])
                    i += 1
            seqs[si] = out


def unpack(data, org):
    """the song's bytes played out: per voice its notes (index, length
    byte), one time through - to check what patterns() made"""
    def b(a):
        return data[a - org]
    out = []
    for v in (6, 8):
        a, notes, ret = b(org + v) | b(org + v + 1) << 8, [], None
        while True:
            c = b(a)
            if c == 0xFF:
                break
            if c == 0xFD:
                a, ret = ret, None
            elif c == 0xFE:
                ret, a = a + 3, b(a + 1) | b(a + 2) << 8
            else:
                notes.append((c, b(a + 1)))
                a += 2
        out.append(notes)
    return out


def build(path, name, org):
    """the song from the text, at org: its bytes, and a line about it"""
    song = read(path, name)
    t1, t2 = (frames(song[v], song['pat'], v) for v in ('v1', 'v2'))
    if t1 != t2:
        print(f'music: song {name}: voice 1 lasts {t1}, voice 2 {t2} frames')
    data = assemble(song, name, org)
    return data, f'music: {name} at ${org:04X}, {len(data)} bytes, {t1} frames ({t1 / 50:.0f} s)'


def main():
    path, name, out = sys.argv[1:4]
    org = int(sys.argv[sys.argv.index('--org') + 1].lstrip('$'), 16)
    data, about = build(path, name, org)
    open(out, 'wb').write(bytes([org & 255, org >> 8]) + data)
    print(about)


if __name__ == '__main__':
    main()
