"""Drive a headless xplus4 through its text remote monitor.

VICE runs inside a headless gamescope, so there is no window and nothing
takes the keyboard focus away from whoever is working at the machine. It
listens on a port of its own (not VICE's default). Every emulator still
running is ended before one is started (kill_emulators).

Inside a Flatpak sandbox (VS Code as a Flatpak) VICE and gamescope are on
the host and are reached through flatpak-spawn; files VICE is to load must
then be under $HOME, which both sides see.
"""
import os
import re
import shutil
import socket
import subprocess
import time

PORT = 6580


# In the sandbox there is no xplus4, only flatpak-spawn to reach the host.
ON_HOST = shutil.which('xplus4') is None and shutil.which('flatpak-spawn') is not None


def _host(cmd):
    """The command as it has to be run: directly, or on the Flatpak host."""
    return ['flatpak-spawn', '--host'] + cmd if ON_HOST else cmd


def _emulator_pids():
    out = subprocess.run(_host(['pgrep', '-x', 'xplus4|x64sc']),
                         capture_output=True, text=True).stdout
    return out.split()


def kill_emulators():
    """End every emulator still running, before a new one is started: one
    left over (a test cut short) would keep the monitor port, and the next
    test would talk to it, running an old program. SIGTERM first, and what
    is still there after two seconds gets SIGKILL."""
    for sig in ('-TERM', '-KILL'):
        pids = _emulator_pids()
        if not pids:
            return
        subprocess.run(_host(['kill', sig] + pids))
        for _ in range(20):
            time.sleep(0.1)
            if not _emulator_pids():
                return
    raise RuntimeError('emulators still running: %s' % _emulator_pids())


class Vice:
    settle = 0.02            # after a prompt, how long to wait for more output

    def __init__(self, image, workdir, warp=True, wav=None, drive=None):
        kill_emulators()
        os.makedirs(workdir, exist_ok=True)
        self.pidfile = os.path.join(workdir, 'vice.pid')
        if os.path.exists(self.pidfile):
            os.remove(self.pidfile)
        args = ['xplus4', '-default', '-remotemonitor',
                '-remotemonitoraddress', f'ip4://127.0.0.1:{PORT}']
        if wav:                 # the sound into a file, to be checked
            args += ['-sound', '-sounddev', 'wav', '-soundarg', os.path.abspath(wav)]
        else:
            args += ['+sound']
        if warp:
            args += ['-warp']
        if drive:               # the drive at 8: 1541 or 1551 (the default)
            args += ['-drive8type', str(drive)]
        args += ['-autostart', os.path.abspath(image)]
        inner = ' '.join("'" + a.replace("'", "'\\''") + "'" for a in args)
        if ON_HOST or shutil.which('gamescope'):
            inner = f'gamescope --backend headless -W 1280 -H 800 -- {inner}'
        shell = f'echo $$ > {self.pidfile}; exec {inner}'
        self.proc = subprocess.Popen(_host(['sh', '-c', shell]),
                                     cwd=os.path.expanduser('~'),
                                     stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL)
        self.sock = None
        for _ in range(100):
            try:
                self.sock = socket.create_connection(('127.0.0.1', PORT), timeout=2)
                break
            except OSError:
                time.sleep(0.2)
        if not self.sock:
            self.stop()
            raise RuntimeError('no monitor connection')
        self.sock.settimeout(30)
        self.sock.sendall(b'\n')
        self._read_prompt()

    def _read_prompt(self):
        """Read until the output ends in a prompt and nothing more follows."""
        buf = b''
        while True:
            if re.search(rb"\((?:C|\d+):\$[0-9a-f]{4}\) $", buf):
                self.sock.settimeout(self.settle)
                try:
                    chunk = self.sock.recv(65536)
                except (socket.timeout, TimeoutError):
                    self.sock.settimeout(30)
                    return buf.decode('latin-1')
                self.sock.settimeout(30)
            else:
                chunk = self.sock.recv(65536)
            if not chunk:
                raise RuntimeError('monitor closed')
            buf += chunk

    def cmd(self, text):
        self.sock.sendall(text.encode() + b'\n')
        return self._read_prompt()

    def run_for(self, seconds):
        """Let the machine run; any command stops it again."""
        self.sock.sendall(b'x\n')
        time.sleep(seconds)
        return self.cmd('r')

    def mem(self, addr, length):
        out = self.cmd(f'm {addr:04x} {addr + length - 1:04x}')
        data = []
        for line in out.splitlines():
            m = re.match(r'>C:[0-9a-f]{4}  (.*)', line)
            if m:
                # the bytes, before the three spaces and the text column
                # (which may look like bytes itself)
                hexes = re.split(r'\s{3,}', m.group(1))[0].split()
                data += [int(b, 16) for b in hexes[:16]]
        return data[:length]

    def poke(self, addr, values):
        self.cmd(f'> {addr:04x} ' + ' '.join(f'{v & 255:02x}' for v in values))

    def screenshot(self, path):
        return self.cmd(f'screenshot "{os.path.abspath(path)}" 2')

    def stop(self):
        try:
            if self.sock:
                self.sock.close()
        except OSError:
            pass
        try:
            pid = open(self.pidfile).read().strip()
            subprocess.run(_host(['kill', pid]))
        except OSError:
            pass
        try:
            self.proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.proc.kill()
