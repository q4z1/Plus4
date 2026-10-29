#!/usr/bin/env python3
"""A video of the ball's moves in training, as Yape shows them:
build/simple-soccer-moves.mp4, with its sound and a caption to each.

    tests/moves.py [scene ...]        (all of them, else those named)
    tests/moves.py --again            (the video from the scenes recorded)
    tests/moves.py --sheet scene      (one scene, as a sheet of pictures)

From the disk: the title, TRAINING chosen, kick-off - then one scene
after another, each set up in the middle of the training match: the game
held at the start of a frame (parked in a loop, park()), the players
and the ball put where the scene wants them through the monitor, the
stick's moves as a plan by the match's frames (dbg_plan), and the game
let go with the frame's pictures and sound recorded from then on (Yape's
YAPE_SHOTN, YAPE_WAV). The players who show a move have the skills that
make it come off (sk): the rolls on a first touch, a tackle, a dribble
go by the beam, not the same from one run to the next.

Each scene's pictures and sound go to ~/.cache/simple-soccer/moves/<name>,
its captioned piece of video next to them; the video is the pieces one
after the other. The captions are in the title's own lettering
(tools/mkdata.py's FONT5), in the border below the pitch.
"""
import array
import glob
import os
import re
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
from yape import Yape, SHOT, host  # noqa: E402
from shot import HERE, BITS, labels  # noqa: E402
import mkdata  # noqa: E402

D64 = os.path.join(HERE, 'build', 'simple-soccer.d64')
PRG = os.path.join(HERE, 'build', 'simple-soccer.prg')
OUT = os.path.join(HERE, 'build', 'simple-soccer-moves.mp4')
WORK = os.path.expanduser('~/.cache/simple-soccer/moves')
WAV = SHOT + '.raw'
RATE = 48000
SERIES = 400                    # pictures recorded a scene, at most
BALL = 22
CYAN = (0, 7, 9)                # in training: the keeper, 8 and 10
YELLOW = (11, 18, 20)
W, H = 384, 288
TRACE = '--trace' in sys.argv or '--sheet' in sys.argv


def lab_all():
    """the labels, and where those are that two files have (tmp, played:
    the main loop's are in HIBSS2, $E7xx)"""
    lab = labels()
    for line in open(os.path.join(HERE, 'build', 'simple-soccer.lbl')):
        p = line.split()
        if len(p) == 3 and p[2] == '.tmp' and p[1].startswith('00E7'):
            lab['loop_tmp'] = int(p[1], 16)
    return lab


lab = lab_all()


# ---- a scene: what is poked before it starts -------------------------------

class Setup:
    def __init__(self):
        self.pokes = []

    def put(self, name, value, i=0):
        self.pokes.append((lab[name] + i, [value & 255]))

    def put16(self, lo, hi, value, i=0):
        self.put(lo, value, i)
        self.put(hi, value >> 8, i)

    def obj(self, i, x, y, d=None, tx=None, ty=None, speed=0, z=0, dz=0):
        """object i at (x, y), on its way to (tx, ty) at speed; the ball z
        high, rising by dz (8.8)"""
        self.put16('o_xl', 'o_xh', x, i)
        self.put16('o_yl', 'o_yh', y, i)
        self.put('o_xf', 0, i)
        self.put('o_yf', 0, i)
        self.put16('o_txl', 'o_txh', x if tx is None else tx, i)
        self.put16('o_tyl', 'o_tyh', y if ty is None else ty, i)
        self.put16('o_spl', 'o_sph', speed, i)
        self.put('o_zl', z, i)
        self.put('o_zf', 0, i)
        self.put('o_dzl', dz >> 8, i)
        self.put('o_dzf', dz, i)
        if i != BALL:
            for n in ('o_slide', 'o_hit', 'o_dive', 'o_hd', 'o_mov'):
                self.put(n, 0, i)
            self.put('o_new', 1, i)
            if d is not None:
                self.put('o_dir', d, i)

    def skill(self, i, pace=None, ctl=None, tck=None, hdg=None, sht=None):
        for n, v in (('sk_pace', pace), ('sk_ctl', ctl), ('sk_tck', tck),
                     ('sk_hdg', hdg), ('sk_sht', sht)):
            if v is not None:
                self.put(n, v, i)


def open_play(s, ctrl, team=0, holder=None):
    """the ball in play, the cyan joystick on ctrl; the ball last touched
    by holder (of team), none after it yet"""
    for n, v in (('dead_t', 0), ('kickoff', 0), ('taker', 0xFF), ('rs_kind', 0),
                 ('goal', 0), ('throw_t', 0), ('lift', 0), ('jmp_t', 0),
                 ('card_pl', 0xFF), ('chaser', 0xFF), ('chaser2', 0xFF),
                 ('deny_t', 0), ('y_pass_t', 0), ('cpu_hold', 0), ('cpu_t', 0),
                 ('ctrl', ctrl), ('fire_n', 0), ('recv', 0xFF), ('recv_t', 0),
                 ('helper', 0xFF), ('at_n', 0xFF), ('at_side', 0xFF),
                 ('kick_pl', 0xFF), ('kick_t', 0), ('pass_q', 0),
                 ('touch_t', 0), ('last_team', team), ('score', 0),
                 ('last_pl', ctrl if holder is None else holder)):
        s.put(n, v)
    s.put('score', 0, 1)


def restart(s, kind, team, x, y):
    """a set piece the rules set up themselves, next frame: kind (R_*) for
    team at (x, y)"""
    open_play(s, 9)
    s.put('rs_kind', kind)
    s.put('rs_team', team)
    s.pokes.append((lab['rs_x'], [x & 255, x >> 8]))
    s.pokes.append((lab['rs_y'], [y & 255, y >> 8]))
    s.put('dead_t', 1)


def best(s, *players):
    for i in players:
        s.skill(i, pace=7, ctl=7, tck=7, hdg=7, sht=7)


# ---- the scenes ---------------------------------------------------------------
# name: (caption, length in frames, setup, plan [(frame, stick), ...])

def field(s, cyan=None, yellow=None, keepers=True):
    """the six players: cyan 7, 9 and yellow 18, 20 where given, the
    keepers on their lines; the yellow ones slow and no tacklers unless
    a scene says otherwise, the cyan ones all the skills"""
    if keepers:
        s.obj(0, 304, 676, d=0)
        s.obj(11, 304, 62, d=4)
    for i, (x, y, d) in zip((7, 9), cyan or ((460, 640, 0), (150, 640, 0))):
        s.obj(i, x, y, d=d)
    for i, (x, y, d) in zip((18, 20), yellow or ((120, 250, 4), (480, 200, 4))):
        s.obj(i, x, y, d=d)
    best(s, 7, 9)
    for i in (18, 20):
        s.skill(i, pace=0, ctl=0, tck=0, hdg=0, sht=2)


def flight(s, x, y, tx, ty, speed, z, dz):
    """the ball in the air at (x, y), z high, on its way to (tx, ty)"""
    s.obj(BALL, x, y, tx=tx, ty=ty, speed=speed, z=z, dz=dz)


def sc_dribble(s):
    open_play(s, 9)
    field(s, cyan=((460, 640, 0), (300, 600, 0)))
    s.obj(BALL, 300, 596)


def sc_pass(s):
    open_play(s, 9)
    field(s, cyan=((380, 400, 6), (250, 520, 1)))
    s.obj(BALL, 253, 517)


def sc_onetwo(s):
    open_play(s, 9)
    field(s, cyan=((390, 520, 6), (250, 520, 2)))
    s.obj(BALL, 254, 520)


def sc_shot(s):
    open_play(s, 9)
    field(s, cyan=((460, 400, 0), (300, 200, 0)), yellow=((150, 300, 4), (470, 330, 4)))
    s.obj(BALL, 300, 196)


def sc_dive(s):
    open_play(s, 9)
    field(s, cyan=((460, 400, 0), (404, 150, 7)), yellow=((150, 300, 4), (470, 330, 4)))
    s.obj(BALL, 400, 146)


def sc_bend(s):
    open_play(s, 9)
    field(s, cyan=((420, 330, 0), (250, 150, 1)), yellow=((150, 300, 4), (470, 330, 4)))
    s.obj(BALL, 254, 146)


def sc_lob(s):
    open_play(s, 9)
    field(s, cyan=((200, 400, 0), (284, 254, 0)), yellow=((150, 360, 4), (470, 380, 4)),
          keepers=False)
    s.obj(0, 304, 676, d=0)
    s.obj(11, 304, 92, d=4)
    s.obj(BALL, 284, 250)


def sc_header(s):
    open_play(s, 9, holder=7)
    field(s, cyan=((418, 100, 6), (280, 122, 0)), yellow=((200, 170, 4), (420, 230, 4)))
    s.put('kick_pl', 7)
    flight(s, 410, 100, -600, 100, 2208, 4, 0x0150)


def sc_tackle(s):
    open_play(s, 7, team=1, holder=20)
    field(s, cyan=((306, 470, 0), (150, 560, 0)), yellow=((150, 250, 4), (304, 380, 4)))
    s.skill(20, pace=2)
    s.put('chaser', 20)
    s.put('y_pass_t', 200)
    s.obj(BALL, 304, 386)


def sc_foul(s):
    open_play(s, 7, team=1, holder=20)
    field(s, cyan=((304, 352, 4), (150, 560, 0)), yellow=((150, 250, 4), (304, 380, 4)))
    s.skill(20, pace=2)
    s.put('chaser', 20)
    s.put('y_pass_t', 200)
    s.put('fouls', 1, 7)                    # (his second: a yellow card)
    s.obj(BALL, 304, 392)


def sc_free(s):
    field(s, cyan=((420, 300, 0), (215, 160, 0)), yellow=((240, 130, 4), (252, 140, 4)))
    restart(s, R_FREE, 0, 220, 150)


def sc_penalty(s):
    field(s, cyan=((420, 300, 0), (304, 130, 0)), yellow=((200, 200, 4), (400, 200, 4)))
    restart(s, R_PENALTY, 0, 304, 107)


def sc_corner(s):
    field(s, cyan=((530, 80, 0), (420, 110, 0)), yellow=((280, 110, 4), (380, 160, 4)))
    restart(s, R_CORNER, 0, 553, 54)


def sc_throw(s):
    field(s, cyan=((80, 330, 0), (170, 260, 0)), yellow=((150, 200, 4), (250, 420, 4)))
    restart(s, R_THROW, 0, 49, 330)


R_THROW, R_CORNER, R_FREE, R_PENALTY = 1, 3, 5, 6

# a shot: fire held, standing - it goes the way he faces
SHOOT = [(0, 'fire'), (12, 'none')]


def lead(plan, n=15):
    """the plan n frames later: the scene seen a moment before it moves"""
    return [(0, 'none')] + [(f + n, stick) for f, stick in plan]


# name, caption (the move, how), frames shown, setup, plan; the first
# frames are the last scene's picture still (FIRST), set pieces wait a
# while first (WAIT)
SCENES = [
    ('dribble', ('DRIBBLING', 'THE STICK - THE BALL AT HIS FEET'), 170, sc_dribble,
     lead([(0, 'up'), (55, 'up+right'), (150, 'none')])),
    ('pass', ('PASS - AND THE FIRST TOUCH', 'FIRE TAPPED: TO THE TEAM-MATE HE FACES'), 170,
     sc_pass, lead([(0, 'fire'), (3, 'none'), (60, 'up'), (170, 'none')])),
    ('onetwo', ('ONE-TWO', 'FIRE LET GO BEFORE THE BALL COMES: FIRST TIME'), 200, sc_onetwo,
     lead([(0, 'fire'), (3, 'none'), (5, 'up'), (10, 'none'), (20, 'fire'), (23, 'none'),
           (90, 'up'), (200, 'none')])),
    ('shot', ('SHOT - THE KEEPER CATCHES', 'FIRE HELD: A SHOT THE WAY HE FACES'), 140, sc_shot,
     lead(SHOOT)),
    ('dive', ('SHOT INTO THE CORNER - GOAL', 'FIRE HELD - FACING THE CORNER'), 120, sc_dive,
     lead(SHOOT)),
    ('bend', ('BENT SHOT - GOAL', 'AFTERTOUCH: THE STICK ACROSS THE SHOT'), 120, sc_bend,
     lead([(0, 'fire'), (10, 'up+left'), (22, 'none')])),
    ('lob', ('LOB - THE KEEPER GETS A HAND TO IT', 'AFTERTOUCH: THE STICK PULLED BACK'), 150, sc_lob,
     lead([(0, 'fire'), (10, 'down'), (22, 'none')])),
    ('header', ('CROSS AND DIVING HEADER - GOAL', 'FIRE AND THE STICK: HE DIVES AT THE BALL'), 110,
     sc_header, [(0, 'none'), (26, 'up+fire'), (30, 'up'), (46, 'none')]),
    ('tackle', ('SLIDING TACKLE', 'FIRE - THE OTHER TEAM ON THE BALL'), 100, sc_tackle,
     [(0, 'up'), (8, 'up+fire'), (11, 'none'), (60, 'up'), (170, 'none')]),
    ('foul', ('FOUL - FREE KICK AND A YELLOW CARD', 'A SLIDING TACKLE FROM BEHIND'), 160,
     sc_foul, [(0, 'down'), (2, 'down+fire'), (5, 'none')]),
    ('free', ('FREE KICK - GOAL', 'THE STICK TURNS HIM - FIRE HELD SHOOTS'), 110, sc_free,
     [(0, 'none'), (50, 'up+right'), (52, 'fire'), (62, 'none')]),
    ('penalty', ('PENALTY - GOAL', 'TURNED - SHOT - BENT IN WITH THE STICK'), 130, sc_penalty,
     [(0, 'none'), (50, 'up+left'), (52, 'fire'), (60, 'right+fire'), (63, 'up'), (72, 'none')]),
    ('corner', ('CORNER', 'FIRE TAPPED: A PASS'), 120, sc_corner,
     [(0, 'none'), (60, 'left'), (62, 'left+fire'), (65, 'left'), (68, 'none'),
      (110, 'down+left'), (170, 'none')]),
    ('throw', ('THROW-IN', 'FIRE TAPPED: THROWN TO A TEAM-MATE'), 130, sc_throw,
     [(0, 'none'), (60, 'up+right'), (62, 'up+right+fire'), (65, 'up+right'), (68, 'none'),
      (130, 'up'), (220, 'none')]),
]
FIRST = 4
WAIT = {'free': 35, 'penalty': 35, 'corner': 45, 'throw': 45}
TITLE = ('TRAINING', 'A KEEPER AND TWO A SIDE - NO CLOCK')


# ---- Yape ------------------------------------------------------------------------

def bits(stick):
    b = 0
    for p in stick.split('+'):
        b |= BITS.get(p, 0)
    return b


def monitor_open(y):
    host('pkill', '-USR1', '-x', 'yapesdl')
    y._read_until(b'Type ? for help!\n')


def monitor_cmd(y, *cmds):
    y.p.stdin.write(''.join(c + '\n' for c in cmds).encode())


def monitor_mem(y, addr, n):
    """n (up to 16) bytes from addr, in a monitor already open (its dump:
    20 lines of 16)"""
    monitor_cmd(y, 'm %04x' % addr)
    text = y._read_until(b' %04X: ' % ((addr + 19 * 16) & 0xFFFF), timeout=10)
    text += y._read_until(b'\n', timeout=10)
    m = re.search(r' %04X: ((?:[0-9A-F]{2} +){1,17})' % addr, text)
    return [int(b, 16) for b in m.group(1).split()][:n]


def clear_shots():
    for f in glob.glob(SHOT + '.*'):
        os.remove(f)


def snapshot(y):
    """the zero page and the variables ($F800-$FBFF), in one stop"""
    host('pkill', '-USR1', '-x', 'yapesdl')
    y._read_until(b'Type ? for help!\n')
    monitor_cmd(y, 'm 0000', 'm f800', 'm f940', 'm fa80', 'm fbc0', 'x')
    text = y._read_until(b'MONITOR LEFT\n', timeout=20)
    mem = {}
    for l in text.splitlines():
        m = re.match(r'\s*([0-9A-F]{4}): ((?:[0-9A-F]{2} +){1,17})', l)
        if m:
            a = int(m.group(1), 16)
            for k, b in enumerate(m.group(2).split()):
                mem[a + k] = int(b, 16)
    return mem


def state(mem):
    """a line of what the scene is at"""
    def b(n, i=0):
        return mem.get(lab[n] + i, 0)

    def w(lo, hi, i):
        v = b(lo, i) + 256 * b(hi, i)
        return v - 65536 if v > 32767 else v
    pl = ' '.join('%d:%d,%d%s' % (i, w('o_xl', 'o_xh', i), w('o_yl', 'o_yh', i),
                                   '/' if b('o_slide', i) else '')
                  for i in (0, 7, 9, 11, 18, 20))
    return ('t%3d ball %d,%d z%d sp%d last %d/%d ctrl %d dead %d rs %d score %d:%d | %s'
            % (b('dbg_t') + 256 * b('dbg_t', 1), w('o_xl', 'o_xh', BALL), w('o_yl', 'o_yh', BALL),
               b('o_zl', BALL), w('o_spl', 'o_sph', BALL), b('last_team'), b('last_pl'),
               b('ctrl'), b('dead_t'), b('rs_kind'), b('score'), b('score', 1), pl))


def wait_series(n, secs=60, y=None):
    """till the series' n pictures are written - meanwhile (y) what the
    scene is at, now and then"""
    t = time.time()
    while len(glob.glob(SHOT + '.[0-9][0-9][0-9]')) < n and time.time() - t < secs:
        if y is not None:
            print('   ', state(snapshot(y)))
            time.sleep(0.25)
        else:
            time.sleep(0.2)
    time.sleep(0.5)


def keep(name):
    d = os.path.join(WORK, name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    for f in glob.glob(SHOT + '.[0-9][0-9][0-9]'):
        shutil.move(f, os.path.join(d, 'f' + f[-3:] + '.ppm'))
    if os.path.exists(WAV):
        shutil.move(WAV, os.path.join(d, 'sound.raw'))
    return d


PARK = 0x0FE0                   # a loop the game waits in (free: LOWBSS
FLAG = 0x0FF0                   # ends at $0FD4, SKIP is at $0FF8)


def park(y):
    """the game held at the start of play_frame: a JMP there to a loop
    in free memory that waits for FLAG, then does play_frame's first
    instruction and goes on with it. (Yape stops the CPU in the middle
    of an instruction: code it is running must not change under it -
    the loop does not, FLAG releases it.) Returns play_frame's bytes."""
    pf = lab['play_frame']
    orig = y.mem(pf, 3)
    code = [0xAD, FLAG & 255, FLAG >> 8,        # lda FLAG
            0xF0, 0xFB] + orig + [              # beq PARK, (jsr clock)
            0x4C, (pf + 3) & 255, (pf + 3) >> 8]  # jmp play_frame + 3
    y.monitor('> %04x 00' % FLAG,
              '> %04x %s' % (PARK, ' '.join('%02x' % v for v in code)),
              '> %04x 4c %02x %02x' % (pf, PARK & 255, PARK >> 8))
    for _ in range(20):
        time.sleep(0.1)
        pc = int(re.search(r'PC:([0-9A-F]{4})', y.regs()).group(1), 16)
        if PARK <= pc < PARK + 5:
            return orig
    raise RuntimeError('the game not parked: PC %04x' % pc)


def play_scene(y, name, setup, plan):
    """the game parked at play_frame, the scene put in, the plan started
    and the pictures from the next frame on"""
    pf = lab['play_frame']
    orig = park(y)
    s = Setup()
    setup(s)
    p = []
    for f, stick in plan:
        p += [f & 255, f >> 8, bits(stick)]
    p += [0xFF, 0xFF, 0]
    s.pokes.append((lab['dbg_plan'], p))
    s.put('dbg_on', 2)
    s.put('dbg_joy', 0)
    s.put('loop_tmp', 1)
    clear_shots()
    if os.path.exists(WAV):
        os.remove(WAV)
    monitor_open(y)
    frames = monitor_mem(y, lab['frames'], 1)[0]
    s.put('played', frames)
    cmds = []
    for a, vals in s.pokes:
        for k in range(0, len(vals), 16):
            cmds.append('> %04x %s' % (a + k, ' '.join('%02x' % v for v in vals[k:k + 16])))
    cmds.append('> %04x %s' % (pf, ' '.join('%02x' % v for v in orig)))
    cmds.append('> %04x 01' % FLAG)
    monitor_cmd(y, *cmds)
    time.sleep(0.3)
    host('pkill', '-USR2', '-x', 'yapesdl')  # (the series from the monitor's end)
    monitor_cmd(y, 'x')
    y._read_until(b'MONITOR LEFT\n', timeout=20)
    wait_series(SERIES, y=y if TRACE else None)
    y.poke(lab['dbg_on'], [0])
    return keep(name)


def record(names, prg=False):
    """the scenes named, from the disk and its title - or (prg) from the
    program alone, the title skipped ("TT": training), to try them out"""
    clear_shots()
    y = Yape(PRG if prg else D64, series=SERIES, title=not prg, skip='TT',
             env=('YAPE_WAV=' + WAV, 'SDL_AUDIODRIVER=dummy'))
    try:
        if prg:
            time.sleep(3)
            for name, caption, length, setup, plan in SCENES:
                if name in names:
                    print(name)
                    play_scene(y, name, setup, plan)
            return
        t0 = time.time()
        while time.time() - t0 < 180:       # loading: till the title is on
            time.sleep(1)
            if y.mem(0xfffe, 2)[1] == 0 and y.mem(0xff06, 1)[0] == 0x1b:
                break
        print('title after %d s' % (time.time() - t0))
        time.sleep(2)
        if 'title' in names:
            host('pkill', '-USR2', '-x', 'yapesdl')
        time.sleep(1.0)
        for stick in ('down', 'down', 'right'):     # MODE: TRAINING
            y.poke(lab['dbg_joy'], [bits(stick)])
            time.sleep(0.15)
            y.poke(lab['dbg_joy'], [0])
            time.sleep(0.45)
        time.sleep(0.8)
        for wait in (1.5, 0):                       # the match, the kick-off
            y.poke(lab['dbg_joy'], [bits('fire')])
            time.sleep(0.2)
            y.poke(lab['dbg_joy'], [0])
            time.sleep(wait)
        if 'title' in names:
            wait_series(SERIES)
            keep('title')
        else:
            time.sleep(3)
        for name, caption, length, setup, plan in SCENES:
            if name in names:
                print(name)
                play_scene(y, name, setup, plan)
    finally:
        y.stop()


# ---- the video ---------------------------------------------------------------------

FONT = mkdata.title_font()


def caption_rows(text, y0):
    """the caption's pixels: (x, y) in a picture W wide, the text in the
    middle, its top at y0"""
    pts = []
    x0 = (W - len(text) * 8) // 2
    for k, ch in enumerate(text):
        c = ord(ch) - 32
        if ch != ' ' and not any(FONT[c * 8:c * 8 + 8]):
            raise ValueError('no %r in the title font' % ch)
        for r in range(8):
            row = FONT[c * 8 + r]
            for b in range(8):
                if row & (0x80 >> b):
                    pts.append((x0 + k * 8 + b, y0 + r))
    return pts


YELLOW_CAP = (0xE6, 0xD8, 0x5A)        # (the title's yellow, near enough)
WHITE_CAP = (0xF0, 0xF0, 0xF0)


def stamp(src, dst, marks):
    data = bytearray(open(src, 'rb').read())
    head = data.index(b'255\n') + 4
    for pts, colour in marks:
        for x, yy in pts:
            o = head + 3 * (yy * W + x)
            data[o:o + 3] = bytes(colour)
    open(dst, 'wb').write(data)


def piece(name, caption, first, length):
    """the scene's pictures first .. first + length, its caption (two
    lines) in the border below the pitch, with their sound: <name>.mp4"""
    d = os.path.join(WORK, name)
    cap = os.path.join(d, 'cap')
    shutil.rmtree(cap, ignore_errors=True)
    os.makedirs(cap)
    marks = [(caption_rows(caption[0], 250), YELLOW_CAP),
             (caption_rows(caption[1], 264), WHITE_CAP)]
    every = sorted(glob.glob(os.path.join(d, 'f[0-9][0-9][0-9].ppm')))
    frames = every[first:first + length]
    for k, f in enumerate(frames):
        stamp(f, os.path.join(cap, '%03d.ppm' % k), marks)
    raw = os.path.join(d, 'sound.raw')
    snd = array.array('h', open(raw, 'rb').read()) if os.path.exists(raw) else array.array('h')
    per = len(snd) / max(1, len(every))
    part = snd[int(first * per):int((first + len(frames)) * per)]
    cut = os.path.join(d, 'cut.raw')
    with open(cut, 'wb') as f:
        part.tofile(f)
    out = os.path.join(d, name + '.mp4')
    # (the TED's sound is all above 0: a high pass takes that out; the
    # level as in tests/video.py)
    gain = 0.45 * 65535 / max(1, max(snd) - min(snd)) if snd else 1
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-framerate', '50',
                    '-f', 'image2', '-c:v', 'ppm', '-i', os.path.join(cap, '%03d.ppm'),
                    '-f', 's16le', '-ar', str(RATE), '-ac', '1', '-i', cut,
                    '-af', 'highpass=f=15,volume=%.2f,apad' % gain, '-shortest',
                    '-vf', 'scale=iw*2:ih*2:flags=neighbor',
                    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '18',
                    '-c:a', 'aac', '-b:a', '128k', '-ar', '48000', out], check=True)
    return out


def video(names):
    parts = []
    if 'title' in names:
        parts.append(piece('title', TITLE, 0, SERIES))
    for name, caption, length, setup, plan in SCENES:
        if name in names:
            parts.append(piece(name, caption, WAIT.get(name, FIRST), length))
    lst = os.path.join(WORK, 'list.txt')
    with open(lst, 'w') as f:
        for p in parts:
            f.write("file '%s'\n" % p)
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0',
                    '-i', lst, '-c', 'copy', OUT], check=True)
    print(OUT)


def grid(name, step=None, cols=3):
    """nine of a scene's pictures, the pitch only, side by side - every
    step-th from its tenth on: <name>/grid.png"""
    from PIL import Image
    d = os.path.join(WORK, name)
    length = next((sc[2] for sc in SCENES if sc[0] == name), 300)
    step = step or max(1, length // 8)
    fs = sorted(glob.glob(os.path.join(d, 'f[0-9][0-9][0-9].ppm')))[10::step][:9]
    ims = [Image.open(f).crop((32, 40, 352, 240)) for f in fs]
    w, h = 320, 200
    img = Image.new('RGB', (cols * (w + 4), ((len(ims) + cols - 1) // cols) * (h + 4)), (255, 0, 0))
    for k, im in enumerate(ims):
        img.paste(im, ((k % cols) * (w + 4), (k // cols) * (h + 4)))
    out = os.path.join(d, 'grid.png')
    img.save(out)
    print(out, 'step', step)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    names = args or ['title'] + [s[0] for s in SCENES]
    os.makedirs(WORK, exist_ok=True)
    if '--sheet' in sys.argv:           # (from the program: quicker)
        record(names, prg=True)
        for n in names:
            grid(n)
        return
    if '--again' not in sys.argv:
        record(names)
    video(names)


if __name__ == '__main__':
    main()
