#!/usr/bin/env python3
"""
mkmusic.py - the title's music (data/title-music.txt) as assembly for
music.s: build/gen/music.inc. With --wav FILE it also plays the bytes it
made as music.s would and writes what the TED would put out, to be
listened to without the Plus/4.

The player (music.s) mixes three voices in software, the way International
Karate's title does on the Plus/4: a timer interrupt SAMPLE_RATE times a
second adds each voice's step to its phase and the three bytes its phase
points at in each voice's wave page, and the sum goes to the TED's volume
register with the TED's sound in its "digital" mode. A wave page holds
$3B plus the wave at a level 0-3; three of them add up to $B1 plus the
levels: DA mode, both voices on, the volume 1 + the levels.

What is made, as .byte lists the player walks:
  m_notes   each note's step, a word: 65536 * Hz / SAMPLE_RATE
  m_envs    the instruments' levels, each list ended by $FF
  i_wave    an instrument's wave pages (PAGES + 4 * wave, + the level)
  i_env     where its levels begin in m_envs
  i_flags   $80: its pitch drops (the kick); $40: noise, a random step
  v_start, v_loop   each voice's notes, and where it starts again

A voice's notes are bytes: 0-$5F a note (its place in m_notes), $60 a
rest, $61-$7F the ticks of what follows ($61 = 1), $80+n instrument n,
$FD lo hi a pattern played (one deep), $FE a pattern's end, $FF back to
the voice's loop.
"""
import math
import os
import re
import struct
import sys
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..', 'data', 'title-music.txt')
GEN = os.path.join(HERE, '..', 'build', 'gen')

CLOCK = 17734470 / 20           # the TED's timers, PAL: 886724 Hz
LATCH = 160                     # a sample each 160 counts
SAMPLE_RATE = CLOCK / LATCH     # 5542 Hz
FRAME_RATE = 50
BASE = 0x3B                     # a wave page's level 0
WAVES = ['pulse50', 'pulse25', 'saw', 'noise']
PAGES = 0xD0                    # the wave pages: $D000-$DFFF, 4 to a wave
NAMES = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}


def hz_of(note):
    """C4 - B4 the octave of A 440"""
    n = NAMES[note[0]] + note[1:-1].count('#') - note[1:-1].count('b')
    return 440 * 2 ** ((n - 9) / 12 + int(note[-1]) - 4)


def parse(path):
    stmts = []
    for line in open(path):
        line = re.sub(r'(^|\s)#.*', '', line).rstrip()    # (not F#5's)
        if not line.strip():
            continue
        if line[0].isspace():
            stmts[-1] += line.split()
        else:
            stmts.append(line.split())
    tempo, insts, patterns, voices = None, {}, {}, []
    for s in stmts:
        if s[0] == 'tempo':
            num, den = s[1].split('/')
            tempo = (int(num), int(den))
        elif s[0] == 'inst':
            drop = 'drop' in s[3:]
            levels = [int(x) for x in s[3:] if x != 'drop']
            assert all(0 <= x <= 3 for x in levels), s
            insts[s[1]] = (len(insts), WAVES.index(s[2]), drop, levels)
        elif s[0] == 'pattern':
            patterns[s[1]] = s[2:]
        elif s[0] == 'voice':
            voices.append(s[1:])
        else:
            raise SystemExit('what is %r?' % s[0])
    assert len(voices) == 3
    return tempo, insts, patterns, voices


class Song:
    def __init__(self, path):
        self.tempo, self.insts, self.patterns, self.voices = parse(path)
        self.notes = sorted({t for p in list(self.patterns.values()) + self.voices
                             for t in p if t[0] in NAMES}, key=hz_of)

    def compile(self, toks, is_pattern):
        """bytes and ticks; the ticks up to "loop" and in all"""
        out, ticks, at_loop, bar = [], 0, None, 0
        length, cur_len = 2, None
        for t in toks:
            if t == '|':
                assert bar == 16, 'a bar of %d ticks: %s' % (bar, ' '.join(toks))
                bar = 0
            elif t == 'loop':
                assert not is_pattern
                at_loop = len(out) + out.count('call'), ticks    # (in bytes)
            elif t[0] == '/':
                length = int(t[1:])
                assert 1 <= length <= 31
            elif t[0] == '@':
                out.append(0x80 + self.insts[t[1:]][0])
            elif t[0] == '*':
                out += ['call', t[1:]]
                ticks += self.pattern_ticks(t[1:])
                cur_len = None          # (the pattern's own length now)
            elif t == '-' or t[0] in NAMES:
                if length != cur_len:
                    out.append(0x60 + length)
                    cur_len = length
                out.append(0x60 if t == '-' else self.notes.index(t))
                ticks += length
                bar += length
            else:
                raise SystemExit('what is %r?' % t)
        out.append(0xFE if is_pattern else 0xFF)
        return out, ticks, at_loop

    def pattern_ticks(self, name):
        return self.compile(self.patterns[name], True)[1]


def build():
    song = Song(SRC)
    assert len(song.notes) <= 0x60
    lines = ['; made by tools/mkmusic.py from data/title-music.txt - do not edit', '',
             'PAGES       = $%02X' % PAGES,
             'LATCH       = %d' % LATCH,
             'TICK_ADD    = %d' % song.tempo[1],
             'TICK_DIV    = %d' % song.tempo[0], '']
    lines.append('m_notes:')
    for n in song.notes:
        step = round(65536 * hz_of(n) / SAMPLE_RATE)
        lines.append('        .word %5d    ; %-3s %7.2f Hz' % (step, n, hz_of(n)))
    envs, env_at = [0, 0xFF], {}         # a rest's: silent
    for name, (i, w, drop, levels) in sorted(song.insts.items(), key=lambda x: x[1][0]):
        env_at[name] = len(envs)
        envs += levels + [0xFF]
    assert len(envs) <= 256
    lines += ['', 'ENV_REST    = 0', 'm_envs:  .byte ' + ', '.join('$%02X' % b for b in envs)]
    order = sorted(song.insts.items(), key=lambda x: x[1][0])
    lines.append('i_wave:  .byte ' + ', '.join('$%02X' % (PAGES + 4 * w) for _, (i, w, d, l) in order))
    lines.append('i_env:   .byte ' + ', '.join(str(env_at[n]) for n, _ in order))
    lines.append('i_flags: .byte ' + ', '.join(
        '$%02X' % ((0x80 if d else 0) | (0x40 if WAVES[w] == 'noise' else 0))
        for _, (i, w, d, l) in order))
    lines.append('')
    blobs, total = [], None
    for name in song.patterns:
        b, ticks, _ = song.compile(song.patterns[name], True)
        blobs.append(('p_' + name.replace('-', '_'), b))
    starts, loops = [], []
    for k, toks in enumerate(song.voices):
        b, ticks, at_loop = song.compile(toks, False)
        assert at_loop, 'voice %d has no loop' % k
        if total is None:
            total = (ticks, at_loop[1])
        assert (ticks, at_loop[1]) == total, \
            'voice %d: %d ticks, loop at %d - not %d, %d' % (k, ticks, at_loop[1], *total)
        blobs.append(('v_%d' % k, b))
        starts.append('v_%d' % k)
        loops.append('v_%d + %d' % (k, at_loop[0]))
    for name, b in blobs:
        items = []
        for x in b:
            if x == 'call':
                items.append('$FD')
            elif isinstance(x, str):
                items.append('<p_%s, >p_%s' % (x, x))
            else:
                items.append('$%02X' % x)
        lines.append('%s:' % name)
        for i in range(0, len(items), 12):
            lines.append('        .byte ' + ', '.join(items[i:i + 12]))
    lines.append('v_start_lo: .byte ' + ', '.join('<' + s for s in starts))
    lines.append('v_start_hi: .byte ' + ', '.join('>' + s for s in starts))
    lines.append('v_loop_lo:  .byte ' + ', '.join('<(%s)' % s for s in loops))
    lines.append('v_loop_hi:  .byte ' + ', '.join('>(%s)' % s for s in loops))
    os.makedirs(GEN, exist_ok=True)
    open(os.path.join(GEN, 'music.inc'), 'w').write('\n'.join(lines) + '\n')
    secs = total[0] * song.tempo[0] / song.tempo[1] / FRAME_RATE
    loop_secs = (total[0] - total[1]) * song.tempo[0] / song.tempo[1] / FRAME_RATE
    print('music: %d bytes of notes, %.1f s, then %.1f s again and again'
          % (sum(len(b) + b.count('call') for _, b in blobs), secs, loop_secs))
    return song, blobs, starts, loops, envs, env_at


# ---- the player again, in Python: the WAV ----------------------------------

class Rnd:
    """music.s's random: an 8-bit Galois LFSR"""
    def __init__(self):
        self.r = 0x5A

    def __call__(self):
        c = self.r & 0x80
        self.r = (self.r << 1) & 0xFF
        if c:
            self.r ^= 0x1D
        return self.r


def pages(rnd):
    out = []
    for x in range(16):
        w, m = x >> 2, (x & 3) + 1
        page = []
        for i in range(256):
            p = [255 if i < 128 else 0, 255 if i < 64 else 0, i, None][w]
            if p is None:
                p = rnd()
            page.append(BASE + (p * m >> 8))
        out.append(page)
    return out


def play(seconds, path):
    song, blobs, starts, loops, envs, env_at = build()
    # the bytes as one list, a pattern's place in it for its two bytes
    # (the second unused)
    pos, data = {}, []
    for name, b in blobs:
        pos[name] = len(data)
        for x in b:
            data += [0xFD] if x == 'call' else [x, 0] if isinstance(x, str) else [x]
    data = [pos['p_' + x.replace('-', '_')] if isinstance(x, str) else x for x in data]
    order = sorted(song.insts.items(), key=lambda x: x[1][0])
    i_wave = [4 * w for _, (i, w, d, l) in order]
    i_env = [env_at[n] for n, _ in order]
    i_flags = [(0x80 if d else 0) | (0x40 if WAVES[w] == 'noise' else 0) for _, (i, w, d, l) in order]
    steps = [round(65536 * hz_of(n) / SAMPLE_RATE) for n in song.notes]

    def loop_pos(s):
        name, plus = s.split(' + ')
        return pos[name] + int(plus)

    rnd = Rnd()
    pg = pages(rnd)
    V = [dict(p=pos[s], lp=loop_pos(l), rt=0, left=1, len=2, ins=0, env=0, f=0,
              page=0, ph=0) for s, l in zip(starts, loops)]
    acc = song.tempo[0] - song.tempo[1]
    out, sample, spf = [], 0.0, SAMPLE_RATE / FRAME_RATE
    out_v = BASE * 3
    for frame in range(int(seconds * FRAME_RATE)):
        acc += song.tempo[1]
        tick = acc >= song.tempo[0]
        if tick:
            acc -= song.tempo[0]
        for v in reversed(V):
            if tick:
                v['left'] -= 1
                if v['left'] == 0:
                    while True:
                        b = data[v['p']]
                        v['p'] += 1
                        if b < 0x60:
                            v['f'] = steps[b]
                            v['env'] = i_env[v['ins']]
                            break
                        if b == 0x60:
                            v['env'] = 0
                            break
                        if b < 0x80:
                            v['len'] = b - 0x60
                        elif b < 0xFD:
                            v['ins'] = b & 0x0F
                        elif b == 0xFD:
                            v['rt'] = v['p'] + 2
                            v['p'] = data[v['p']]
                        elif b == 0xFE:
                            v['p'] = v['rt']
                        else:
                            v['p'] = v['lp']
                    v['left'] = v['len']
            level = envs[v['env']]
            if envs[v['env'] + 1] != 0xFF:
                v['env'] += 1
            fl = i_flags[v['ins']]
            if fl & 0x80:
                v['f'] -= v['f'] >> 3
            if fl & 0x40:
                v['f'] = (v['f'] & 0xFF) | rnd() << 8
            v['page'] = i_wave[v['ins']] + level
        sample += spf
        while sample >= 1:
            sample -= 1
            out.append(out_v & 15)
            out_v = 0
            for v in V:
                v['ph'] = (v['ph'] + v['f']) & 0xFFFF
                out_v += pg[v['page']][v['ph'] >> 8]
            out_v &= 0xFF
    # the TED's volume 0-8 (more is 8), held to 44.1 kHz
    rate = 44100
    pcm = bytearray()
    for k in range(int(len(out) * rate / SAMPLE_RATE)):
        x = min(out[int(k * SAMPLE_RATE / rate)], 8)
        pcm += struct.pack('<h', int((x - 4) * 7000))
    w = wave.open(path, 'wb')
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(rate)
    w.writeframes(bytes(pcm))
    w.close()
    print('%s: %.1f s' % (path, seconds))


if __name__ == '__main__':
    if len(sys.argv) > 2 and sys.argv[1] == '--wav':
        play(float(sys.argv[3]) if len(sys.argv) > 3 else 40, sys.argv[2])
    else:
        build()
