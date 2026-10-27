#!/usr/bin/env python3
"""
mkmusic.py - the music (data/music.txt) as assembly for music.s:
build/gen/music.inc. With --wav FILE [seconds] it also plays the bytes it
made as music.s would and writes what the TED would put out, to be
listened to without the Plus/4.

The player (music.s) is Simple Soccer's title player, grown: three voices
mixed in software the way International Karate's title does on the
Plus/4 - a timer interrupt SAMPLE_RATE times a second adds each voice's
step to its phase and the three bytes its phase points at in each voice's
wave page, and the sum goes to the TED's volume register with the TED's
sound in its "digital" mode. A wave page holds $3B plus the wave at a
level; three of them add up to $B1 plus the levels: DA mode, both voices
on, the volume 1 + the levels (the TED goes no louder than 8).

The pages are made here, not on the Plus/4: only those the instruments
use, each a wave (a Hammond's drawbars, a pulse, a saw, noise, a clipped
mix of harmonics) at a level 1-7. An instrument's envelope is a list of
pages, one a frame, so it can go from one wave to another - a Hammond's
percussion is its attack on a page with the 2 2/3' sounding, then on
the plain drawbars - and it may loop (the Leslie's tremolo).

What is made, as .byte lists the player walks:
  m_notes   each note's step, a word: 65536 * Hz / SAMPLE_RATE
  m_envs    the instruments' pages, each list ended by $FF (the last held)
            or $FE n (on at n)
  i_env     where an instrument's pages begin in m_envs
  i_flags   $40: noise, a random step
  i_drop    n: its pitch drops by step / 2^n each frame (a kick: 3, a
            boom: 7), 0 none
  i_vspd    its vibrato's speed (256 = a turn a frame), 0: none
  i_vib     where its vibrato's 32 steps are in m_vib: signed, in 256ths
            of the note's step
  v_start, v_loop   each voice's notes, and where it starts again
  m_level   each page's level (for a meter)
  the wave pages (segment WAVES, page-aligned)

A voice's notes are bytes: 0-$5F a note (its place in m_notes), $60 a
rest, $61-$7F the ticks of what follows ($61 = 1), $80+n instrument n,
$F0 the note held on, $F1 the next note without a new attack (legato),
$FD lo hi a pattern played (one deep), $FE a
pattern's end, $FF back to the voice's loop.
"""
import math
import os
import re
import struct
import sys
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..', 'data', 'music.txt')
GEN = os.path.join(HERE, '..', 'build', 'gen')

CLOCK = 17734470 / 20           # the TED's timers, PAL: 886724 Hz
LATCH = 160                     # a sample each 160 counts
SAMPLE_RATE = CLOCK / LATCH     # 5542 Hz
FRAME_RATE = 50
BASE = 0x3B                     # a wave page's level 0
NAMES = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}
# a Hammond's drawbars, 16' to 1': the harmonics of the 8' they sound
FEET = [0.5, 1.5, 1, 2, 3, 4, 5, 6, 8]


TUNE = [0]                      # cents above A 440 (data/music.txt: tune)


def hz_of(note):
    """C4 - B4 the octave of A 440 (or A tuned TUNE cents higher)"""
    n = NAMES[note[0]] + note[1:-1].count('#') - note[1:-1].count('b')
    return 440 * 2 ** ((n - 9) / 12 + int(note[-1]) - 4 + TUNE[0] / 1200)


def transpose(note, octaves):
    return note[:-1] + str(int(note[-1]) + octaves)


class Rnd:
    """music.s's random: an 8-bit Galois LFSR"""
    def __init__(self, r=0x5A):
        self.r = r

    def __call__(self):
        c = self.r & 0x80
        self.r = (self.r << 1) & 0xFF
        if c:
            self.r ^= 0x1D
        return self.r


def make_wave(kind, args):
    """a wave's 256 values, 0-1; and the octaves its notes are played
    lower (a 16' drawbar: its cycle is two of the 8')"""
    x = [2 * math.pi * i / 256 for i in range(256)]
    down = 0
    if kind == 'pulse':
        w = [1.0 if i < 256 * int(args[0]) / 100 else 0.0 for i in range(256)]
    elif kind == 'saw':
        w = [i / 255 for i in range(256)]
    elif kind == 'noise':
        rnd = Rnd(0xA7)
        w = [rnd() / 255 for i in range(256)]
    elif kind in ('drawbars', 'harm'):
        if kind == 'drawbars':
            # nine digits 0-8, each step 3 dB; "perc2"/"perc3": the
            # percussion's 4' or 2 2/3' at full on top
            bars = [int(c) for c in args[0]]
            assert len(bars) == 9, args
            amps = [0 if b == 0 else 10 ** (-(8 - b) * 3 / 20) for b in bars]
            harms = list(FEET)
            for a in args[1:]:
                if a.startswith('perc'):
                    harms.append({'perc2': 2, 'perc3': 3}[a])
                    amps.append(1.0)
            if amps[0] or amps[1]:          # the 16' is the cycle
                harms = [h * 2 for h in harms]
                down = 1
        else:                               # harm a1 a2 ... [clip g]
            nums, clip = args, None
            if 'clip' in args:
                i = args.index('clip')
                nums, clip = args[:i], float(args[i + 1])
            amps = [float(a) for a in nums]
            harms = list(range(1, len(amps) + 1))
        w = [sum(a * math.sin(h * t) for a, h in zip(amps, harms)) for t in x]
        if kind == 'harm' and clip:
            w = [max(-1.0, min(1.0, v * clip / max(map(abs, w)))) for v in w]
        lo, hi = min(w), max(w)
        w = [(v - lo) / (hi - lo) for v in w]
    else:
        raise SystemExit('what wave is %r?' % kind)
    return w, down


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
    song = dict(tempo=None, swing=None, waves={}, insts={}, patterns={}, voices=[])
    for s in stmts:
        if s[0] == 'tempo':
            fr = [tuple(int(x) for x in f.split('/')) for f in s[1:]]
            assert len({d for _, d in fr}) == 1, 'one denominator: %s' % s
            song['tempo'] = (fr[0][0], fr[-1][0], fr[0][1])     # even, odd, add
        elif s[0] == 'tune':
            TUNE[0] = float(s[1])
        elif s[0] == 'wave':
            song['waves'][s[1]] = make_wave(s[2], s[3:]) + (s[2],)
        elif s[0] == 'inst':
            flags, drop, vib, env, loop = 0, 0, (0, 0), [], None
            toks = s[2:]
            while toks:
                t = toks.pop(0)
                if t == 'drop':
                    drop = int(toks.pop(0))
                elif t == 'vib':
                    vib = (int(toks.pop(0)), int(toks.pop(0)))  # depth, speed
                elif t == 'loop':
                    loop = len(env)
                elif t == '0':
                    env.append(None)
                else:
                    name, level = t.rsplit('.', 1)
                    assert name in song['waves'], t
                    assert 1 <= int(level) <= 7, t
                    env.append((name, int(level)))
            assert env, s
            downs = {song['waves'][e[0]][1] for e in env if e}
            assert len(downs) <= 1, 'one octave to its waves: %s' % s
            if any(e and song['waves'][e[0]][2] == 'noise' for e in env):
                flags |= 0x40
            song['insts'][s[1]] = dict(n=len(song['insts']), flags=flags, drop=drop, vib=vib,
                                       env=env, loop=loop, down=downs.pop() if downs else 0)
        elif s[0] == 'pattern':
            song['patterns'][s[1]] = s[2:]
        elif s[0] == 'voice':
            song['voices'].append(s[1:])
        else:
            raise SystemExit('what is %r?' % s[0])
    assert len(song['voices']) == 3
    assert len(song['insts']) <= 64
    return song


class Song:
    def __init__(self, path):
        self.__dict__.update(parse(path))
        self.variants = {}          # (pattern, instrument) -> its bytes
        self.notes = []
        # the pages: flat first, then each (wave, level) an envelope uses
        self.pages = [None] + sorted({e for i in self.insts.values() for e in i['env'] if e})
        self.voice_bytes = [self.compile(v, None, None) for v in self.voices]
        self.notes.sort(key=hz_of)

    def note(self, t, ins):
        if ins is not None:
            t = transpose(t, -self.insts[ins]['down'])
        if t not in self.notes:
            self.notes.append(t)
        return t

    def compile(self, toks, ins, pattern):
        """bytes, ticks, the ticks and bytes up to "loop", the instrument
        at the end; notes as names (their places once all are known)"""
        out, ticks, at_loop, bar = [], 0, None, 0
        length, cur_len = 2, None
        for t in toks:
            if t == '|':
                assert bar == 16, 'a bar of %d ticks: %s' % (bar, ' '.join(toks))
                bar = 0
            elif t == 'loop':
                assert pattern is None
                at_loop = len(out), ticks
            elif t[0] == '/':
                length = int(t[1:])
                assert 1 <= length <= 31
            elif t[0] == '@':
                ins = t[1:]
                out.append(0x80 + self.insts[ins]['n'])
            elif t[0] == '*':
                name = self.variant(t[1:], ins)
                out += ['call', name]
                b, n, _, ins = self.variants_info[name]
                ticks += n
                cur_len = None          # (the pattern's own length now)
            elif t in ('-', '~') or t[0] in NAMES or t[0] == '^':
                if length != cur_len:
                    out.append(0x60 + length)
                    cur_len = length
                if t == '-':
                    out.append(0x60)
                elif t == '~':
                    out.append(0xF0)
                elif t[0] == '^':
                    out += [0xF1, ('note', self.note(t[1:], ins))]
                else:
                    out.append(('note', self.note(t, ins)))
                ticks += length
                bar += length
            else:
                raise SystemExit('what is %r?' % t)
        out.append(0xFF if pattern is None else 0xFE)
        return out, ticks, at_loop, ins

    def variant(self, name, ins):
        """the pattern compiled for the instrument it starts with: its
        notes an octave lower for a 16' organ"""
        if not hasattr(self, 'variants_info'):
            self.variants_info = {}
        down = self.insts[ins]['down'] if ins else 0
        key = 'p_%s%s' % (name.replace('-', '_'), '_lo' if down else '')
        if key not in self.variants_info:
            self.variants_info[key] = self.compile(self.patterns[name], ins, name)
        return key

    def resolved(self, b):
        """the bytes with the notes' places in m_notes"""
        return [self.notes.index(x[1]) if isinstance(x, tuple) else x for x in b]


def page_bytes(song):
    """each page as music.s finds it"""
    out = []
    for p in song.pages:
        if p is None:
            out.append([BASE] * 256)
        else:
            w = song.waves[p[0]][0]
            out.append([BASE + round(v * p[1]) for v in w])
    return out


def vib_table(depth):
    return [round(depth * math.sin(2 * math.pi * i / 32)) for i in range(32)]


def tables(song):
    envs, env_at = [0, 0xFF], {}         # a rest's: the flat page
    for name, ins in sorted(song.insts.items(), key=lambda x: x[1]['n']):
        env_at[name] = len(envs)
        envs += [song.pages.index(e) for e in ins['env']]
        envs += [0xFF] if ins['loop'] is None else [0xFE, env_at[name] + ins['loop']]
    assert len(envs) <= 256
    vibs, vib_at = [], {}
    for name, ins in song.insts.items():
        if ins['vib'][1]:
            t = tuple(vib_table(ins['vib'][0]))
            if t not in vib_at:
                vib_at[t] = len(vibs)
                vibs += t
            ins['vib_at'] = vib_at[t]
        else:
            ins['vib_at'] = 0
    return envs, env_at, vibs or [0]


def build():
    song = Song(SRC)
    assert len(song.notes) <= 0x60
    assert len(song.pages) <= 32
    envs, env_at, vibs = tables(song)
    order = sorted(song.insts.items(), key=lambda x: x[1]['n'])
    lines = ['; made by tools/mkmusic.py from data/music.txt - do not edit', '',
             'LATCH       = %d' % LATCH,
             'TICK_ADD    = %d' % song.tempo[2],
             'TICK_EVEN   = %d' % song.tempo[0],
             'TICK_ODD    = %d' % song.tempo[1],
             'NPAGES      = %d' % len(song.pages), '']
    lines.append('m_notes:')
    for n in song.notes:
        step = round(65536 * hz_of(n) / SAMPLE_RATE)
        lines.append('        .word %5d    ; %-3s %7.2f Hz' % (step, n, hz_of(n)))
    # (pages as page numbers from PAGES: the player adds it)
    lines += ['', 'ENV_REST    = 0',
              'm_envs:  .byte ' + ', '.join('$%02X' % b for b in envs)]
    lines.append('i_env:   .byte ' + ', '.join(str(env_at[n]) for n, _ in order))
    lines.append('i_flags: .byte ' + ', '.join('$%02X' % i['flags'] for _, i in order))
    lines.append('i_drop:  .byte ' + ', '.join(str(i['drop']) for _, i in order))
    lines.append('i_vspd:  .byte ' + ', '.join(str(i['vib'][1]) for _, i in order))
    lines.append('i_vib:   .byte ' + ', '.join(str(i['vib_at']) for _, i in order))
    lines.append('m_vib:   .byte ' + ', '.join('$%02X' % (v & 0xFF) for v in vibs))
    lines.append('')
    blobs = [(k, song.resolved(v[0])) for k, v in song.variants_info.items()]
    starts, loops, total = [], [], None
    for k, (b, ticks, at_loop, _) in enumerate(song.voice_bytes):
        assert at_loop, 'voice %d has no loop' % k
        if total is None:
            total = (ticks, at_loop[1])
        assert (ticks, at_loop[1]) == total, \
            'voice %d: %d ticks, loop at %d - not %d, %d' % (k, ticks, at_loop[1], *total)
        blobs.append(('v_%d' % k, song.resolved(b)))
        starts.append('v_%d' % k)
        # (bytes to the loop: a call is 3 bytes, 2 entries here)
        loops.append('v_%d + %d' % (k, at_loop[0] + b[:at_loop[0]].count('call')))
    for name, b in blobs:
        items = []
        for x in b:
            if x == 'call':
                items.append('$FD')
            elif isinstance(x, str):
                items.append('<%s, >%s' % (x, x))
            else:
                items.append('$%02X' % x)
        lines.append('%s:' % name)
        for i in range(0, len(items), 12):
            lines.append('        .byte ' + ', '.join(items[i:i + 12]))
    lines.append('v_start_lo: .byte ' + ', '.join('<' + s for s in starts))
    lines.append('v_start_hi: .byte ' + ', '.join('>' + s for s in starts))
    lines.append('v_loop_lo:  .byte ' + ', '.join('<(%s)' % s for s in loops))
    lines.append('v_loop_hi:  .byte ' + ', '.join('>(%s)' % s for s in loops))
    lines.append('m_level: .byte ' + ', '.join(str(p[1] if p else 0) for p in song.pages))
    lines += ['', '        .segment "WAVES"', 'm_pages:']
    for p, page in zip(song.pages, page_bytes(song)):
        lines.append('; %s' % ('flat' if p is None else '%s at %d' % p))
        for i in range(0, 256, 16):
            lines.append('        .byte ' + ', '.join('$%02X' % v for v in page[i:i + 16]))
    os.makedirs(GEN, exist_ok=True)
    open(os.path.join(GEN, 'music.inc'), 'w').write('\n'.join(lines) + '\n')
    frames = (total[0] / 2) * (song.tempo[0] + song.tempo[1]) / song.tempo[2]
    loop_frames = ((total[0] - total[1]) / 2) * (song.tempo[0] + song.tempo[1]) / song.tempo[2]
    print('music: %d bytes of notes, %d pages, %.1f s (%d bars), then %.1f s again and again'
          % (sum(len(b) + b.count('call') for _, b in blobs), len(song.pages),
             frames / FRAME_RATE, total[0] // 16, loop_frames / FRAME_RATE))
    return song, blobs, starts, loops, envs, env_at, vibs


# ---- the player again, in Python: the WAV ----------------------------------

def play(seconds, path):
    song, blobs, starts, loops, envs, env_at, vibs = build()
    # the bytes as one list, a pattern's place in it for its two bytes
    # (the second unused)
    pos, data = {}, []
    for name, b in blobs:
        pos[name] = len(data)
        for x in b:
            data += [0xFD] if x == 'call' else [x, 0] if isinstance(x, str) else [x]
    data = [pos[x] if isinstance(x, str) else x for x in data]
    order = sorted(song.insts.items(), key=lambda x: x[1]['n'])
    i_env = [env_at[n] for n, _ in order]
    i_flags = [i['flags'] for _, i in order]
    i_drop = [i['drop'] for _, i in order]
    i_vspd = [i['vib'][1] for _, i in order]
    i_vib = [i['vib_at'] for _, i in order]
    steps = [round(65536 * hz_of(n) / SAMPLE_RATE) for n in song.notes]

    def loop_pos(s):
        name, plus = s.split(' + ')
        return pos[name] + int(plus)

    rnd = Rnd()
    pg = page_bytes(song)
    V = [dict(p=pos[s], lp=loop_pos(l), rt=0, left=1, len=2, ins=0, env=0, f=0,
              out=0, page=0, ph=0, vph=0) for s, l in zip(starts, loops)]
    even, odd, add = song.tempo
    # (the tick sounding now, -1 before the first: the first at once)
    acc, cur = odd - add, -1
    leg = False
    out, sample, spf = [], 0.0, SAMPLE_RATE / FRAME_RATE
    out_v = BASE * 3
    for frame in range(int(seconds * FRAME_RATE)):
        acc += add
        div = odd if cur & 1 else even
        tick = acc >= div
        if tick:
            acc -= div
            cur = (cur + 1) & 15
        for v in reversed(V):
            if tick:
                v['left'] -= 1
                if v['left'] == 0:
                    while True:
                        b = data[v['p']]
                        v['p'] += 1
                        if b < 0x60:
                            v['f'] = steps[b]
                            if not leg:
                                v['env'] = i_env[v['ins']]
                            leg = False
                            break
                        if b == 0x60:
                            v['env'] = 0
                            break
                        if b == 0xF0:
                            break
                        if b == 0xF1:
                            leg = True
                            continue
                        if b < 0x80:
                            v['len'] = b - 0x60
                        elif b < 0xC0:
                            v['ins'] = b & 0x3F
                        elif b == 0xFD:
                            v['rt'] = v['p'] + 2
                            v['p'] = data[v['p']]
                        elif b == 0xFE:
                            v['p'] = v['rt']
                        else:
                            v['p'] = v['lp']
                    v['left'] = v['len']
            page = envs[v['env']]
            nxt = envs[v['env'] + 1]
            if nxt == 0xFE:
                v['env'] = envs[v['env'] + 2]
            elif nxt != 0xFF:
                v['env'] += 1
            ins = v['ins']
            if i_drop[ins]:
                v['f'] -= v['f'] >> i_drop[ins]
            if i_flags[ins] & 0x40:
                v['f'] = (v['f'] & 0xFF) | rnd() << 8
            f = v['f']
            if i_vspd[ins]:
                v['vph'] = (v['vph'] + i_vspd[ins]) & 0xFF
                f = (f + vibs[i_vib[ins] + (v['vph'] >> 3)] * (v['f'] >> 8)) & 0xFFFF
            v['out'] = f
            v['page'] = page
        sample += spf
        while sample >= 1:
            sample -= 1
            out.append(out_v & 15)
            out_v = 0
            for v in V:
                v['ph'] = (v['ph'] + v['out']) & 0xFFFF
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
