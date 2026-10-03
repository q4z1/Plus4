"""yape.py - Yape (Plus/4 emulator) without a window, for the tests

Yape has no remote monitor; its monitor reads from stdin. A build of Yape
with two hooks is used (~/.cache/paradroid/yapesdl, from
github.com/calmopyrin/yapesdl): SIGUSR1 enters the monitor, SIGUSR2 saves
the TED's picture as a PPM to $YAPE_SHOT. It runs in gamescope's headless
backend, with a configuration directory of its own, written afresh for
each start (Yape saves its settings on exit, warp too).

Yape has no true 1551: a .d64 gets a true 1541 on the serial bus.
"""
import os, re, struct, subprocess, time, zlib

YAPE = os.path.expanduser('~/.cache/paradroid/yapesdl/yapesdl')
HOME = os.path.expanduser('~/.cache/paradroid/yapehome')
SHOT = os.path.expanduser('~/.cache/paradroid/test/yape.ppm')
EMULATORS = ('yapesdl', 'yape', 'xplus4', 'x64sc')
CONF = '''[Yape configuration file]
DisplayFrameRate = 0
DisplayQuickDebugInfo = 0
50HzTimerActive = 1
ActiveJoystick = 0
RamMask = ffff
256KBRAM = 0
SaveSettingsOnExit = 0
CRTEmulation = 0
WindowMultiplier = 1
EmulationLevel = 0
'''


def host(*cmd, **kw):
    return subprocess.run(('flatpak-spawn', '--host') + cmd, **kw)


def kill_emulators():
    """every emulator gone: SIGTERM, then SIGKILL, then checked"""
    for sig in ('TERM', 'KILL'):
        for e in EMULATORS:
            host('pkill', '-' + sig, '-x', e, capture_output=True)
        time.sleep(2)
    left = host('pgrep', '-l', '-x', '|'.join(EMULATORS), capture_output=True, text=True).stdout
    left = [l for l in left.splitlines() if l.split()[-1] in EMULATORS]
    if left:
        raise RuntimeError('emulators still running: %s' % left)


def ppm_to_png(src, dst):
    d = open(src, 'rb').read()
    magic, w, h, mx, rest = d.split(maxsplit=4)
    w, h = int(w), int(h)
    rows = b''.join(b'\0' + rest[y * w * 3:(y + 1) * w * 3] for y in range(h))
    def chunk(t, c):
        return struct.pack('>I', len(c)) + t + c + struct.pack('>I', zlib.crc32(t + c) & 0xffffffff)
    open(dst, 'wb').write(b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))


class Yape:
    def __init__(self, image, warp=False, series=0, env=()):
        kill_emulators()
        conf = os.path.join(HOME, 'Gaia', 'yapeSDL')
        os.makedirs(conf, exist_ok=True)
        with open(os.path.join(conf, 'yape.conf'), 'w') as f:
            f.write(CONF)
        os.makedirs(os.path.dirname(SHOT), exist_ok=True)
        env_extra = env
        env = ['--env=XDG_DATA_HOME=' + HOME, '--env=YAPE_SHOT=' + SHOT]
        if warp:
            env.append('--env=YAPE_WARP=1')
        if series:                  # png_series(): so many pictures in a row
            env.append('--env=YAPE_SHOTN=%d' % series)
        env += ['--env=' + e for e in env_extra]
        self.p = subprocess.Popen(
            ['flatpak-spawn', '--host'] + env +
            ['gamescope', '--backend', 'headless', '-W', '1280', '-H', '800', '--',
             YAPE, os.path.abspath(image)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            bufsize=0)
        self.buf = b''
        time.sleep(3)

    def _read_until(self, marker, timeout=20):
        t = time.time() + timeout
        while marker not in self.buf:
            if time.time() > t:
                raise RuntimeError('no %r from yape; got %r' % (marker, self.buf[-400:]))
            chunk = os.read(self.p.stdout.fileno(), 65536)
            if not chunk:
                raise RuntimeError('yape gone; got %r' % self.buf[-400:])
            self.buf += chunk
        i = self.buf.index(marker) + len(marker)
        out, self.buf = self.buf[:i], self.buf[i:]
        return out.decode('latin-1')

    def monitor(self, *cmds):
        """the commands in the monitor, the machine stopped meanwhile; its
        output"""
        host('pkill', '-USR1', '-x', 'yapesdl')
        self._read_until(b'Type ? for help!\n')
        self.p.stdin.write(''.join(c + '\n' for c in cmds + ('x',)).encode())
        return self._read_until(b'MONITOR LEFT\n')

    def mem(self, addr, n):
        out = []
        while len(out) < n:
            text = self.monitor('m %04x' % (addr + len(out)))
            for l in text.splitlines():
                m = re.match(r'\s*([0-9A-F]{4}): ((?:[0-9A-F]{2} +){1,17})', l)
                if m:
                    out += [int(b, 16) for b in m.group(2).split()]
        return out[:n]

    def poke(self, addr, vals):
        self.monitor('> %04x %s' % (addr, ' '.join('%02x' % v for v in vals)))

    def regs(self):
        return self.monitor('reg')

    def run_for(self, secs):
        time.sleep(secs)

    def png(self, path):
        """the TED's picture as a PNG, 384 x 288"""
        if os.path.exists(SHOT):
            os.remove(SHOT)
        host('pkill', '-USR2', '-x', 'yapesdl')
        self._read_until(b'SHOT ')
        t = time.time() + 5
        while not os.path.exists(SHOT) and time.time() < t:
            time.sleep(0.05)
        ppm_to_png(SHOT, path)
        return path

    def png_series(self, prefix):
        """the next pictures, one a frame (as many as series= said), as
        prefix000.png on; their names"""
        import glob
        for f in glob.glob(SHOT + '.*'):
            os.remove(f)
        host('pkill', '-USR2', '-x', 'yapesdl')
        self._read_until(b'SHOT ')
        out = []
        for f in sorted(glob.glob(SHOT + '.[0-9][0-9][0-9]')):
            png = '%s%s.png' % (prefix, f[-3:])
            ppm_to_png(f, png)
            out.append(png)
        return out

    def lines(self, secs):
        """what Yape writes in the next secs seconds, line by line"""
        import select
        t = time.time() + secs
        while time.time() < t:
            r, _, _ = select.select([self.p.stdout], [], [], 0.1)
            if r:
                chunk = os.read(self.p.stdout.fileno(), 65536)
                if not chunk:
                    break
                self.buf += chunk
        out, self.buf = self.buf, b''
        return out.decode('latin-1').splitlines()

    def stop(self):
        try:
            self.p.stdin.close()
        except OSError:
            pass
        kill_emulators()            # (its gamescope ends with it)
