#!/usr/bin/env python3
"""Two people playing a whole match, from the disk, in VICE, Yape and
plus4emu: the title with the joysticks (two players, which port is home),
the walk on, both halves, every kick-off and set piece taken by a player,
the full time, the winner's page and back to the title - all as two
players at the machine would do it.

    tests/twoplayer.py [vice|yape|p4emu|all] [seed=1] [home=1|2] [len=3|5|7]

home: the port of the home team's player (2: the one in port 2 pushes
his stick in the title last, as Luca did). len: the match's minutes.

Each of the two "players" follows the ball, dribbles towards the other
goal, shoots when near it (fire held: the shot charged), passes and
tackles now and then, heads the ball when it is high, and takes his set
pieces after a while (a direction, then fire tapped or held). He reacts
to what he saw a picture or two before and makes mistakes now and then.

The joysticks: in Yape and plus4emu on the real ports (Yape: the
YAPE_SHM hook in paradroid/tools/yape.patch; plus4emu: its joystick
keys), so the game reads them as from a stick in the port. VICE 3.10 has
no way to set its ports from outside that works (its binary monitor's
"joyport set" and the "jpdb" command do nothing to the Plus/4's ports),
so there it is dbg_joy and dbg_joyb, as port 1 and 2.

A line for each thing that should not happen (as soak.py: jump, keeper,
hangs, out, gone, stuck), then the checks, OK or WRONG; the exit code
counts the wrong ones and the things seen (255 at most). Pictures:
~/.cache/simple-soccer/test/2p_<emulator>_*.png
"""
import collections
import ctypes
import math
import os
import random
import shutil
import socket
import struct
import subprocess
import sys
import time
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(1, os.path.join(HERE, '..', '..', 'paradroid', 'tests'))
from shot import labels, WORK  # noqa: E402

D64 = os.path.join(HERE, '..', 'build', 'simple-soccer.d64')
NOBJ = 23
BALL = 22
BITS = {'up': 1, 'down': 2, 'left': 4, 'right': 8, 'fire': 16}
FIRE = 16
K_HOME = 0xFCEF                 # (game.inc)
T_TWO = 0xFCE8                  # (title.s t_two = K_CH + 1)
PORTS_LINE = 0xE800 + 0x400 + 22 * 40 + 6      # (title.s, as ports.py)
PORTS_W = 28
LINE_T, LINE_B = 49, 689        # (play.s: the goal lines)
LINE_L, LINE_R = 49, 558
GOAL_X = 304                    # (between POST_L and POST_R)
JUMP = 30
KEEPER_OUT = 220
HANG = 15
GONE = 20                       # pictures a set piece's player out of view (the view pans)
GROUND_X, GROUND_Y = 23, 58
KINDS = ['kick-off', 'throw-in', 'goal kick', 'corner', "keeper's", 'free kick', 'penalty']
# 8 ways, clockwise from up: their bits
WAYS = [1, 9, 8, 10, 2, 6, 4, 5]
STUCK_AFTER = 500               # frames a set piece may wait after its fire
LONGEST = 6000                  # frames a set piece may wait at all
OUT = WORK


def png(path, w, h, rgb):
    """rgb: w * h * 3 bytes"""
    rows = b''.join(b'\0' + rgb[y * w * 3:(y + 1) * w * 3] for y in range(h))

    def chunk(t, c):
        return struct.pack('>I', len(c)) + t + c + struct.pack('>I', zlib.crc32(t + c) & 0xffffffff)
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n'
                + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
                + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))


def disk_copy(name):
    """the disk as a copy each run (where the emulators see it)"""
    os.makedirs(OUT, exist_ok=True)
    dst = os.path.join(OUT, '2p_%s.d64' % name)
    shutil.copy(D64, dst)
    return dst


# ---- the emulators: start(), mem(), joy(), wait(frames), picture(), png()

class YapeEmu:
    """Yape in lockstep through YAPE_SHM: the joysticks on the ports"""
    name = 'yape'

    def __init__(self):
        from yape import Yape
        self.y = Yape(disk_copy(self.name), warp=True, title=True, shm=True)

    def mem(self, addr, n):
        return self.y.smem(addr, n)

    def joy(self, port, bits):
        self.y.joy(port, bits)

    def wait(self, frames):
        self.y.step(frames)

    def picture(self):
        self.y.step(3)

    def end_match(self):
        pass

    def png(self, path):
        self.y.png(path)

    def stop(self):
        self.y.stop()


class P4Emu:
    """plus4emu through its library, with a 1541 and the disk: the
    joysticks by its joystick keys"""
    name = 'p4emu'
    KEYS = ({1: 80, 2: 81, 4: 82, 8: 83, 16: 86},      # joystick 1
            {1: 72, 2: 73, 4: 74, 8: 75, 16: 79})      # joystick 2

    def __init__(self):
        import p4emu
        from onetest import kill_other_tests
        kill_other_tests()
        e = self.e = p4emu.P4emu.__new__(p4emu.P4emu)
        L = e.lib = ctypes.CDLL(p4emu.LIB)
        L.Plus4VM_Create.restype = ctypes.c_void_p
        L.Plus4VM_GetLastErrorMessage.restype = ctypes.c_char_p
        L.Plus4VideoDecoder_Create.restype = ctypes.c_void_p
        L.Plus4VM_ReadMemory.restype = ctypes.c_uint8
        for f in ('Plus4VM_Run', 'Plus4VM_LoadROM', 'Plus4VM_SetRAMConfiguration',
                  'Plus4VM_PasteText', 'Plus4VM_SetDiskImageFile'):
            getattr(L, f).restype = ctypes.c_int
        e.vm = ctypes.c_void_p(L.Plus4VM_Create())
        W, H = p4emu.W, p4emu.H
        e.buf = (ctypes.c_uint32 * (W * H))()
        e.done = (ctypes.c_uint32 * (W * H))()
        e.frames = 0
        e._line = p4emu._LINE(e._on_line)
        e._frame = p4emu._FRAME(e._on_frame)
        e.vd = ctypes.c_void_p(L.Plus4VideoDecoder_Create(e._line, e._frame, None))
        L.Plus4VideoDecoder_UpdatePalette(e.vd, 0, 16, 8, 0)
        L.Plus4VM_SetVideoOutputCallback(e.vm, L.Plus4VideoDecoder_VideoCallback, e.vd)
        L.Plus4VM_SetEnableAudioOutput(e.vm, 0)
        e._ok(L.Plus4VM_SetRAMConfiguration(e.vm, ctypes.c_size_t(64), ctypes.c_uint64(0x99999999)))
        roms = os.path.join(p4emu.BASE, 'roms')
        for n, f, off in ((0, 'p4_basic.rom', 0), (1, 'p4kernal.rom', 0), (2, '3plus1.rom', 0),
                          (3, '3plus1.rom', 16384), (0x10, 'dos1541.rom', 0)):
            e._ok(L.Plus4VM_LoadROM(e.vm, n, os.path.join(roms, f).encode(), off))
        e._ok(L.Plus4VM_SetDiskImageFile(e.vm, 0, disk_copy(self.name).encode(), 0))
        L.Plus4VM_Reset(e.vm, 1)
        e.run_for(2.5)
        e._ok(L.Plus4VM_PasteText(e.vm, b'LOAD"*",8\n', -1, -1))
        ready = bytes([18, 5, 1, 4, 25, 46])            # READY. (screen codes)
        for _ in range(300):
            e.run_for(1)
            if e.mem(0x0C00, 1000).count(ready) >= 2:
                break
        else:
            raise RuntimeError('plus4emu: the load did not end')
        e._ok(L.Plus4VM_PasteText(e.vm, b'RUN\n', -1, -1))
        self.held = [0, 0]

    def mem(self, addr, n):
        return list(self.e.mem(addr, n))

    def joy(self, port, bits):
        was = self.held[port - 1]
        for b, code in self.KEYS[port - 1].items():
            if (was ^ bits) & b:
                self.e.key(code, bool(bits & b))
        self.held[port - 1] = bits

    def wait(self, frames):
        self.e.frame(frames)

    def picture(self):
        self.e.frame(3)

    def end_match(self):
        pass

    def png(self, path):
        self.e.png(path)

    def stop(self):
        self.e.stop()


class ViceEmu:
    """VICE through its binary monitor: a stop at eng_end each picture;
    the joysticks as dbg_joy, dbg_joyb (see above)"""
    name = 'vice'
    PORT = 6584

    def __init__(self, lab):
        import vice
        vice.kill_emulators()
        self.lab = lab
        self.rid = 0
        self.cp = None
        args = ['xplus4', '-default', '+sound', '-warp', '-drive8type', '1541',
                '-binarymonitor', '-binarymonitoraddress', 'ip4://127.0.0.1:%d' % self.PORT,
                '-autostart', disk_copy(self.name)]
        inner = 'gamescope --backend headless -W 1280 -H 800 -- ' + ' '.join(
            "'" + a + "'" for a in args)
        self.p = subprocess.Popen(vice._host(['sh', '-c', 'exec ' + inner]),
                                  cwd=os.path.expanduser('~'),
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.s = None
        for _ in range(150):
            try:
                self.s = socket.create_connection(('127.0.0.1', self.PORT), timeout=60)
                break
            except OSError:
                time.sleep(0.2)
        if not self.s:
            raise RuntimeError('vice: no binary monitor')
        self.stopped = False
        self.go()

    def _recv(self, n):
        b = b''
        while len(b) < n:
            c = self.s.recv(n - len(b))
            if not c:
                raise RuntimeError('vice: monitor closed')
            b += c
        return b

    def _resp(self):
        h = self._recv(12)
        ln, typ, err, rid = struct.unpack('<IBBI', h[2:12])
        body = self._recv(ln)
        if rid == 0xFFFFFFFF:
            if typ == 0x62:
                self.stopped = True
            elif typ == 0x63:
                self.stopped = False
        return typ, err, rid, body

    def req(self, cmd, body=b''):
        self.rid += 1
        self.s.sendall(struct.pack('<BBIIB', 2, 2, len(body), self.rid, cmd) + body)
        while True:
            typ, err, rid, b = self._resp()
            if rid == self.rid:
                if err:
                    raise RuntimeError('vice: command %02x error %02x' % (cmd, err))
                return b

    def go(self):
        self.req(0xAA)

    def mem(self, addr, n):
        b = self.req(0x01, struct.pack('<BHHBH', 0, addr, addr + n - 1, 0, 0))
        self.go()
        return list(b[2:2 + n])

    def poke(self, addr, vals):
        self.req(0x02, struct.pack('<BHHBH', 0, addr, addr + len(vals) - 1, 0, 0) + bytes(vals))

    def joy(self, port, bits):
        self.poke(self.lab['dbg_joy' if port == 1 else 'dbg_joyb'], [bits])
        if not self.cp:
            self.go()

    def wait(self, frames):
        if self.cp:
            for _ in range((frames + 2) // 3):
                self.picture()
        else:
            time.sleep(max(0.1, frames * 0.004))

    def picture(self):
        """on to the next picture's end (eng_end)"""
        if not self.cp:
            b = self.req(0x12, struct.pack('<HHBBBB', self.lab['eng_end'], self.lab['eng_end'],
                                           1, 1, 4, 0))
            self.cp = struct.unpack('<I', b[:4])[0]
        self.stopped = False
        self.req(0xAA)
        self.s.settimeout(60)
        while not self.stopped:
            self._resp()

    def mem_held(self, addr, n):
        """(stopped at a picture: the machine stays so)"""
        b = self.req(0x01, struct.pack('<BHHBH', 0, addr, addr + n - 1, 0, 0))
        return list(b[2:2 + n])

    def end_match(self):
        if self.cp:
            self.req(0x13, struct.pack('<I', self.cp))
            self.cp = None
            self.go()

    def fire_away(self, port):
        """full time: fire till the game takes it (quit_a), let go there -
        the next moment $F800 on is the loader's, no place for dbg_joy"""
        at = self.lab['quit_a']
        b = self.req(0x12, struct.pack('<HHBBBB', at, at, 1, 1, 4, 0))
        cp = struct.unpack('<I', b[:4])[0]
        self.poke(self.lab['dbg_joy' if port == 1 else 'dbg_joyb'], [FIRE])
        self.stopped = False
        self.req(0xAA)
        while not self.stopped:
            self._resp()
        self.poke(self.lab['dbg_joy' if port == 1 else 'dbg_joyb'], [0])
        self.req(0x13, struct.pack('<I', cp))
        self.go()

    def png(self, path):
        b = self.req(0x84, bytes([0, 0]))
        fl = struct.unpack('<I', b[:4])[0]
        w, h, ox, oy, iw, ih, bpp = struct.unpack('<HHHHHHB', b[4:17])
        pix = b[4 + fl + 4:]
        pix += bytes(w * h - len(pix))         # (VICE 3.10 sends it 4 bytes short)
        pal = self.req(0x91, bytes([0]))
        n = struct.unpack('<H', pal[:2])[0]
        cols, o = [], 2
        for _ in range(n):
            size = pal[o]
            cols.append(bytes(pal[o + 1:o + 4]))
            o += 1 + size
        if not self.cp:
            self.go()
        cw, ch = min(w, 384), min(h, 288)
        x0 = max(0, ox + (iw - cw) // 2)
        y0 = max(0, oy + (ih - ch) // 2)
        rgb = b''.join(cols[pix[(y0 + y) * w + x0 + x]] for y in range(ch) for x in range(cw))
        png(path, cw, ch, rgb)

    def stop(self):
        import vice
        try:
            self.s.close()
        except OSError:
            pass
        vice.kill_emulators()


# ---- the two at the joysticks

def way_to(dx, dy):
    """the stick's bits for the nearest of the 8 ways"""
    if dx == 0 and dy == 0:
        return 0
    a = math.degrees(math.atan2(dx, -dy)) % 360      # 0 up, clockwise
    return WAYS[int((a + 22.5) // 45) % 8]


class Player:
    def __init__(self, port, team, rnd):
        self.port, self.team, self.rnd = port, team, rnd
        self.fire_left = 0          # pictures fire still held
        self.fire_way = 0
        self.sp = None              # a set piece of ours: [frame to go, way, pictures of fire]
        self.wiggle = 0
        self.wiggle_t = 0
        self.last = 0
        self.seen = collections.deque(maxlen=3)     # (what he reacts to)
        self.shots = self.passes = self.tackles = self.headers = self.pieces = 0

    def decide(self, st):
        r = self.rnd
        self.seen.append(st)
        if st['full'] or st['enter']:
            self.sp = None
            return 0
        if st['kickoff']:
            self.fire_left = 0
            if st['rs_team'] != self.team:
                self.sp = None
                return 0
            if self.sp is None:
                self.sp = [st['frame'] + r.randint(25, 130), self.forward(st, r.randint(-3, 3)),
                           r.choice([1, 1, 2, 4, 6, 9])]
                self.pieces += 1
            go, way, fire = self.sp
            if st['frame'] < go - 20:
                return 0
            if st['frame'] < go:
                return way
            if fire > 0:
                self.sp[2] -= 1
                return way | FIRE
            if st['frame'] > go + 250:          # (nothing: once more)
                self.sp = None
            return way
        self.sp = None
        if self.fire_left:
            self.fire_left -= 1
            return self.fire_way | FIRE
        old = self.seen[0] if r.random() < 0.6 else st       # (a picture or two late)
        me = st['ctrl']
        if me is None:
            return 0
        mx, my = st['pos'][me]
        bx, by = old['pos'][BALL]
        bz = st['z']
        d = math.hypot(bx - mx, by - my)
        goal_y = self.goal_y(st)
        if r.random() < 0.03:                   # (a slip of the hand)
            return r.choice(WAYS)
        if st['frame'] > self.wiggle_t:
            self.wiggle = r.randint(-90, 90)
            self.wiggle_t = st['frame'] + r.randint(30, 120)
        if d < 12 and bz < 6:                   # the ball at his feet
            to_goal = abs(goal_y - my)
            if to_goal < 150 + r.randint(0, 60) and r.random() < 0.5:
                self.fire_way = way_to(GOAL_X + r.randint(-40, 40) - mx, goal_y - my)
                self.fire_left = r.choice([2, 3, 4, 5, 7])
                self.shots += 1
                return self.fire_way | FIRE
            if r.random() < 0.035:
                self.fire_way = self.forward(st, r.randint(-2, 2))
                self.fire_left = 0
                self.passes += 1
                return self.fire_way | FIRE
            return way_to(GOAL_X + self.wiggle - mx, goal_y - my)
        if len(self.seen) > 1:                  # where the ball goes
            px, py = self.seen[-2]['pos'][BALL]
            bx, by = bx + 2 * (bx - px), by + 2 * (by - py)
        way = way_to(bx - mx, by - my)
        if bz > 12 and d < 28 and r.random() < 0.3:
            self.headers += 1
            return self.forward(st, 0) | FIRE
        if d < 22 and st['owner_team'] not in (None, self.team) and r.random() < 0.2:
            self.tackles += 1
            return way | FIRE
        return way

    def goal_y(self, st):
        """the goal line he plays to (his keeper's the other: soak.py)"""
        return (LINE_T, LINE_B)[self.team ^ st['flip']]

    def forward(self, st, turn):
        """the way to the other goal, turned by eighths"""
        up = self.goal_y(st) == LINE_T
        return WAYS[((0 if up else 4) + turn) % 8]


# ---- the test

def run(emu_name, seed, home, length):
    lab = labels()
    rnd = random.Random(seed)
    found = []
    wrong = 0
    tag = '2p_' + emu_name

    def check(name, ok, got):
        nonlocal wrong
        wrong += not ok
        print('%-6s %-14s %-58s %s' % (emu_name, name, got, 'OK' if ok else 'WRONG'), flush=True)
        return ok

    def seen(pic, what, text):
        found.append(what)
        if len(found) <= 60:
            print('%-6s %6d %-7s %s' % (emu_name, pic, what, text), flush=True)

    def shot(name):
        try:
            emu.png(os.path.join(OUT, '%s_%s.png' % (tag, name)))
        except Exception as ex:        # (a picture is not the test)
            print('%-6s picture %s: %s' % (emu_name, name, ex))

    t0 = time.time()
    emu = {'vice': lambda: ViceEmu(lab), 'yape': YapeEmu, 'p4emu': P4Emu}[emu_name]()
    try:
        # ---- the title
        def title_on():
            return emu.mem(0xFFFE, 2) == [lab['synth'], 0] and emu.mem(0xFF06, 1)[0] == 0x1B
        for _ in range(400):
            emu.wait(50)
            if title_on():
                break
        if not check('title', title_on(), 'the title after %.0f s' % (time.time() - t0)):
            shot('notitle')
            return wrong
        emu.wait(100)

        def push(port, way, hold=6, gap=12):
            emu.joy(port, way)
            emu.wait(hold)
            emu.joy(port, 0)
            emu.wait(gap)

        def line():
            return bytes(emu.mem(PORTS_LINE, PORTS_W)).decode('ascii', 'replace').strip()
        # length: right once for 5, twice for 7 (the first line)
        for _ in range((length - 3) // 2):
            push(1, BITS['right'])
        push(1, BITS['down'])                   # PLAYERS
        push(1, BITS['right'])                  # 2
        check('two players', emu.mem(T_TWO, 1)[0] == 1 and line() == 'HOME: PORT 1   AWAY: PORT 2',
              line())
        if home == 2:
            push(2, BITS['up'])                 # (the second player's stick)
            check('port 2 home', emu.mem(K_HOME, 1)[0] & 1 == 1
                  and line() == 'HOME: PORT 2   AWAY: PORT 1', line())
        shot('title')
        push(home, FIRE, hold=8, gap=2)         # (fire let go: the match)

        # ---- the match
        players = [Player(home, 0, random.Random(rnd.random())),
                   Player(3 - home, 1, random.Random(rnd.random()))]
        frame = 0
        last_f = None
        pic = 0
        last = last_raw = None
        hang = 0
        was_live = False
        gone = set()
        gone_n = [0, 0]
        waited = 0
        fired_at = None
        told = False
        keeper_out = set()
        jumps = []
        touches = [0, 0]
        follow = [[0, 0], [0, 0]]               # per team: pictures checked, moved the way pushed
        held = [collections.deque(maxlen=3), collections.deque(maxlen=3)]
        prev_ctrl = [None, None]
        score = None
        goals = []
        halves = set()
        last_min = 0
        min_at = 0
        entered = full_at = None
        pieces = 0
        last_kick = 0
        last_pl = None
        a0, a1 = lab['o_xl'], lab['o_zl'] + NOBJ
        z0, z1 = 0x70, 0xD0
        h0, h1 = lab['game_min'], lab['score'] + 2
        while True:
            emu.picture()
            pic += 1
            rd = emu.mem_held if isinstance(emu, ViceEmu) else emu.mem
            zp = rd(z0, z1 - z0)
            raw = rd(a0, a1 - a0)
            hd = rd(h0, h1 - h0)
            fr = rd(lab['frames'], 1)[0]
            zg = lambda n: zp[lab[n] - z0]
            hg = lambda n, i=0: hd[lab[n] - h0 + i]
            frame += (fr - last_f) & 255 if last_f is not None else 0
            last_f = fr

            def w(lo, hi, i):
                v = raw[lab[lo] - a0 + i] + 256 * raw[lab[hi] - a0 + i]
                return v - 65536 if v > 32767 else v
            pos = [(w('o_xl', 'o_xh', i), w('o_yl', 'o_yh', i)) for i in range(NOBJ)]
            z = raw[lab['o_zl'] - a0 + BALL]
            ctrl = [zg('ctrl'), zg('ctrl_b')]
            if ctrl[0] != 0xFF and ctrl[0] >= 11 or ctrl[1] != 0xFF and ctrl[1] < 11:
                ctrl.reverse()                  # (stopped while the teams were swapped)
            ctrl = [c if c < BALL else None for c in ctrl]
            kick, dead = zg('kickoff'), zg('dead_t')
            enter = rd(lab['enter'], 1)[0]
            full = hg('full')
            live = not kick and not dead and not full and not enter
            # who has the ball: the nearest within 10 px
            near = min(range(BALL), key=lambda i: math.hypot(pos[i][0] - pos[BALL][0],
                                                             pos[i][1] - pos[BALL][1]))
            owner = (0 if near < 11 else 1) if math.hypot(
                pos[near][0] - pos[BALL][0], pos[near][1] - pos[BALL][1]) < 10 and z < 6 else None
            st = {'pos': pos, 'z': z, 'kickoff': kick, 'rs_team': zg('rs_team'), 'full': full,
                  'enter': enter, 'frame': frame, 'owner_team': owner, 'flip': zg('flip') & 1}
            if entered is None and enter:
                entered = frame
                shot('walkon')
            # ---- the joysticks
            for t, p in enumerate(players):
                st['ctrl'] = ctrl[t]
                bits = p.decide(st)
                if bits != p.last:
                    emu.joy(p.port, bits)
                    p.last = bits
                held[t].append(bits)
            # ---- what is seen
            for i, a, b in jumps:               # (a jump still there a picture on: not
                c = pos[i]                      # a position read half written)
                if abs(c[0] - b[0]) <= JUMP and abs(c[1] - b[1]) <= JUMP:
                    seen(pic - 1, 'jump', 'player %d %s -> %s' % (i, a, b))
            jumps = []
            if live and was_live and last:
                for i in range(BALL):
                    dx, dy = pos[i][0] - last[i][0], pos[i][1] - last[i][1]
                    if abs(dx) > JUMP or abs(dy) > JUMP:
                        jumps.append((i, last[i], pos[i]))
                for t in (0, 1):
                    c = ctrl[t]
                    h = held[t]
                    if (c is not None and c == prev_ctrl[t] and len(h) == 3 and h[0] == h[1]
                            and h[1] & 15 and not h[1] & FIRE and c != near):
                        dx, dy = pos[c][0] - last[c][0], pos[c][1] - last[c][1]
                        want = h[1]
                        ok = ((not want & 4 or dx < 0) and (not want & 8 or dx > 0)
                              and (not want & 1 or dy < 0) and (not want & 2 or dy > 0))
                        follow[t][0] += 1
                        follow[t][1] += ok
                for k, t in ((0, 0), (11, 1)):
                    ky = pos[k][1]
                    own = players[t].goal_y(st) ^ LINE_T ^ LINE_B
                    far = abs(ky - own) > KEEPER_OUT and ctrl[t] != k    # (his player's: he may)
                    if far and k not in keeper_out:
                        seen(pic, 'keeper', '%d at %s, his line y %d; ball %s z %d, controlled %s, '
                             'last touch %d' % (k, pos[k], own, pos[BALL], z, ctrl, zg('last_pl')))
                        shot('keeper_%d' % pic)
                    if far:
                        keeper_out.add(k)
                    else:
                        keeper_out.discard(k)
            if live and z > 0 and last and z == last_z:
                hang += 1
                if hang == HANG:
                    seen(pic, 'hangs', 'ball at %s height %d' % (pos[BALL], z))
            else:
                hang = 0
            bx, by = pos[BALL]
            if not enter and not full and not (0 <= bx <= 620 and 0 <= by <= 740):
                seen(pic, 'out', 'ball at %s' % (pos[BALL],))
            lp = zg('last_pl')
            if live and lp != last_pl and lp < BALL:
                touches[0 if lp < 11 else 1] += 1
            last_pl = lp
            if kick and not enter and not full:
                cam = rd(lab['cam_x'], 4)
                cx, cy = cam[0] + 256 * cam[1], cam[2] + 256 * cam[3]
                for t in (0, 1):
                    c = ctrl[t]
                    if c is not None:
                        sx = pos[c][0] - GROUND_X - cx
                        sy = pos[c][1] + GROUND_Y - cy
                        out = not (0 <= sx < 304 and 0 <= sy < 192)
                        gone_n[t] = gone_n[t] + 1 if out else 0
                        if gone_n[t] == GONE and t not in gone and zg('rs_team') == t:
                            seen(pic, 'gone', 'team %d: %d at %s, ball %s, %s, view at %d,%d' % (
                                t, c, pos[c], pos[BALL], KINDS[zg('rs_kind') % 7], cx, cy))
                            shot('gone_%d' % pic)
                            gone.add(t)
                waited += 1
                taker = players[zg('rs_team') & 1]
                if taker.last & FIRE and fired_at is None:
                    fired_at = frame
                if not told and (fired_at is not None and frame - fired_at >= STUCK_AFTER
                                 or waited >= LONGEST // 3):
                    told = True
                    seen(pic, 'stuck', '%s for team %d waiting %d pictures, fire %s, ball %s' % (
                        KINDS[zg('rs_kind') % 7], zg('rs_team'), waited,
                        'pressed' if fired_at is not None else 'not pressed', pos[BALL]))
                    shot('stuck_%d' % pic)
            else:
                gone = set()
                gone_n = [0, 0]
                waited = 0
                fired_at = None
                told = False
            pieces += bool(kick) and not last_kick and not enter
            # ---- the match's course
            sc = (hg('score'), hg('score', 1))
            if score is not None and sc != score:
                goals.append((hg('game_min'), sc))
                print('%-6s %6d goal   %d-%d in minute %d' % (emu_name, pic, sc[0], sc[1],
                                                            hg('game_min')), flush=True)
                if len(goals) <= 3:
                    shot('goal%d' % len(goals))
            score = sc
            halves.add(hg('half'))
            gm = hg('game_min')
            if gm != last_min:
                last_min, min_at = gm, frame
            if not kick and not full and not enter and frame - min_at > 1500:
                seen(pic, 'clock', 'minute %d for %d frames' % (gm, frame - min_at))
                break
            if full and full_at is None:
                full_at = frame
                print('%-6s %6d full   %d-%d after %d frames' % (emu_name, pic, sc[0], sc[1], frame),
                      flush=True)
            if full_at is not None and frame - full_at > 300:
                break
            last, last_raw, last_z, was_live, last_kick = pos, raw, z, live, kick
            prev_ctrl = ctrl
            if len(found) > 60 or frame > (length * 60 + 240) * 50 or 'stuck' in found:
                break
        shot('fulltime')
        check('walked on', entered is not None, 'walk on at frame %s' % entered)
        check('half time', 1 in halves, 'halves seen %s' % sorted(halves))
        check('full time', full_at is not None and last_min >= 90,
              'minute %d, full at frame %s' % (last_min, full_at))
        check('both kick', min(touches) >= 10, 'touches %d / %d' % tuple(touches))
        for t in (0, 1):
            n, ok = follow[t]
            check('stick %d' % (players[t].port), n >= 50 and ok >= 0.6 * n,
                  'team %d followed it %d of %d pictures' % (t, ok, n))
        print('%-6s %d pictures, %d set pieces, %d-%d, goals %s' % (
            emu_name, pic, pieces, score[0], score[1], goals))
        for p in players:
            print('%-6s port %d: %d shots, %d passes, %d tackles, %d headers, %d set pieces' % (
                emu_name, p.port, p.shots, p.passes, p.tackles, p.headers, p.pieces))
        # ---- the end: fire, the winner's page, fire, the title
        emu.end_match()
        for p in players:
            emu.joy(p.port, 0)
        def title_lines():                      # (the winner's page runs in the title too)
            return title_on() and line().startswith('HOME:')
        page = back = False
        for i in range(40):
            if full_at is None:
                break
            if i and not title_on():            # (loading: $F800 on is the loader's -
                emu.wait(250)                   # VICE's dbg_joy not to be written)
                continue
            if i == 0 and hasattr(emu, 'fire_away'):
                emu.fire_away(home)
            else:
                push(home if i % 2 == 0 else 3 - home, FIRE, hold=4, gap=2)
            for _ in range(30):
                emu.wait(25)
                if title_lines():
                    back = True
                    break
                if title_on() and not page:
                    page = True
                    emu.wait(50)
                    shot('winner')
                    break
            if back:
                break
        check('winner page', page, 'seen' if page else 'not seen')
        emu.wait(100)
        shot('title_again')
        check('title again', back and emu.mem(T_TWO, 1)[0] == 1,
              'back: %s, players %d, %s' % (back, emu.mem(T_TWO, 1)[0] + 1, line()))
        check('ports kept', back and emu.mem(K_HOME, 1)[0] & 1 == home - 1, line())
    finally:
        emu.stop()
    seen_n = len(found)
    print('%-6s %d things seen %s, %d wrong, %.0f s' % (
        emu_name, seen_n, dict(collections.Counter(found)), wrong, time.time() - t0), flush=True)
    return wrong + seen_n


def main():
    which, seed, home, length = 'all', 1, 1, 3
    for a in sys.argv[1:]:
        if a in ('vice', 'yape', 'p4emu', 'all'):
            which = a
        elif a.startswith('seed='):
            seed = int(a[5:])
        elif a.startswith('home='):
            home = int(a[5:])
        elif a.startswith('len='):
            length = int(a[4:])
        else:
            sys.exit(__doc__)
    total = 0
    for e in (('p4emu', 'yape', 'vice') if which == 'all' else (which,)):
        total += run(e, seed, home, length)
    sys.exit(min(total, 255))


if __name__ == '__main__':
    main()
