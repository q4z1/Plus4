"""p4emu.py - plus4emu for the tests, through its library: no window, no
process of its own, the emulator runs inside the test (as in
paradroid/tests/p4emu.py, which explains where the library comes from).

Unlike VICE and Yape, plus4emu shows what a real TED does when one of its
colour registers is written while that colour is being drawn: a pixel of
colour $7F (see tests/p4emu_snow.py). And it emulates a whole 1541, so the
game boots from build/stardew.d64 and loads its rooms as on the real
machine, at the real speed.

Pictures: 384 x 288, one line per TED line. Input: the game's dbg_keys,
as in run_tests.py, or real keys through key().
"""
import ctypes, os, re, struct, zlib
from onetest import kill_other_tests

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
BASE = os.path.expanduser(os.environ.get(
    'P4EMU_DIR', '~/.cache/plus4emu/plus4emu-1.2.11-beta_20190320'))
LIB = os.path.expanduser(os.environ.get('P4EMU_LIB', '~/.cache/plus4emu/libplus4emu.so'))
W, H = 384, 288
SNOW = (214, 255, 161)                  # $7F as plus4emu's decoder draws it

_LINE = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p)
_FRAME = ctypes.CFUNCTYPE(None, ctypes.c_void_p)


def write_png(dst, rows):
    """rows: H lists of W (r, g, b)"""
    raw = b''.join(b'\0' + bytes(c for p in row for c in p) for row in rows)
    def chunk(t, c):
        return struct.pack('>I', len(c)) + t + c + struct.pack('>I', zlib.crc32(t + c) & 0xffffffff)
    open(dst, 'wb').write(b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', struct.pack('>IIBBBBB', len(rows[0]), len(rows), 8, 2, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))


def labels():
    lab = {}
    for line in open(os.path.join(ROOT, 'build', 'stardew.lbl')):
        m = re.match(r'al ([0-9A-F]+) \.(\S+)', line)
        if m:
            lab.setdefault(m.group(2), int(m.group(1), 16))
    return lab


class P4emu:
    def __init__(self, d64=None, boot=2.5, run='LOAD"*",8\nRUN\n'):
        kill_other_tests()
        L = self.lib = ctypes.CDLL(LIB)
        L.Plus4VM_Create.restype = ctypes.c_void_p
        L.Plus4VM_GetLastErrorMessage.restype = ctypes.c_char_p
        L.Plus4VideoDecoder_Create.restype = ctypes.c_void_p
        L.Plus4VM_ReadMemory.restype = ctypes.c_uint8
        L.Plus4VM_GetFloppyDriveLEDState.restype = ctypes.c_uint32
        for f in ('Plus4VM_Run', 'Plus4VM_LoadROM', 'Plus4VM_LoadProgram',
                  'Plus4VM_SetRAMConfiguration', 'Plus4VM_PasteText',
                  'Plus4VM_SetDiskImageFile'):
            getattr(L, f).restype = ctypes.c_int
        self.vm = ctypes.c_void_p(L.Plus4VM_Create())
        self.buf = (ctypes.c_uint32 * (W * H))()   # being drawn
        self.done = (ctypes.c_uint32 * (W * H))()  # the last complete picture
        self.frames = 0
        self._line = _LINE(self._on_line)       # (kept: ctypes frees them otherwise)
        self._frame = _FRAME(self._on_frame)
        self.vd = ctypes.c_void_p(L.Plus4VideoDecoder_Create(self._line, self._frame, None))
        L.Plus4VideoDecoder_UpdatePalette(self.vd, 0, 16, 8, 0)
        L.Plus4VM_SetVideoOutputCallback(self.vm, L.Plus4VideoDecoder_VideoCallback, self.vd)
        L.Plus4VM_SetEnableAudioOutput(self.vm, 0)
        self._ok(L.Plus4VM_SetRAMConfiguration(self.vm, ctypes.c_size_t(64),
                                               ctypes.c_uint64(0x99999999)))
        roms = os.path.join(BASE, 'roms')
        self._ok(L.Plus4VM_LoadROM(self.vm, 0, os.path.join(roms, 'p4_basic.rom').encode(), 0))
        self._ok(L.Plus4VM_LoadROM(self.vm, 1, os.path.join(roms, 'p4kernal.rom').encode(), 0))
        self._ok(L.Plus4VM_LoadROM(self.vm, 2, os.path.join(roms, '3plus1.rom').encode(), 0))
        self._ok(L.Plus4VM_LoadROM(self.vm, 3, os.path.join(roms, '3plus1.rom').encode(), 16384))
        self._ok(L.Plus4VM_LoadROM(self.vm, 0x10, os.path.join(roms, 'dos1541.rom').encode(), 0))
        if d64 is None:
            d64 = os.path.join(ROOT, 'build', 'stardew.d64')
        # a copy: the game saves to its disk
        self.d64 = os.path.join(ROOT, 'build', 'test', 'p4emu.d64')
        os.makedirs(os.path.dirname(self.d64), exist_ok=True)
        open(self.d64, 'wb').write(open(d64, 'rb').read())
        self._ok(L.Plus4VM_SetDiskImageFile(self.vm, 0, self.d64.encode(), 0))
        L.Plus4VM_Reset(self.vm, 1)
        self.run_for(boot)
        self.lab = labels()
        if run:
            # LOAD, then RUN once it is READY again (typed during the load,
            # RUN would be lost)
            load, _, rest = run.partition('\n')
            self._ok(L.Plus4VM_PasteText(self.vm, (load + '\n').encode(), -1, -1))
            ready = bytes([18, 5, 1, 4, 25, 46])           # READY. in screen codes
            for _ in range(600):
                self.run_for(1)
                if self.mem(0x0C00, 1000).count(ready) >= 2:
                    break
            else:
                raise RuntimeError('plus4emu: the load did not end')
            if rest:
                self._ok(L.Plus4VM_PasteText(self.vm, rest.encode(), -1, -1))

    def _ok(self, e):
        if e:
            raise RuntimeError('plus4emu: %s' % self.lib.Plus4VM_GetLastErrorMessage(self.vm).decode())

    def _on_line(self, ud, n, data):
        if 0 <= n < 2 * H and not n & 1:
            self.lib.Plus4VideoDecoder_DecodeLine(
                self.vd, ctypes.byref(self.buf, (n // 2) * W * 4), W, 0, ctypes.c_void_p(data))

    def _on_frame(self, ud):
        ctypes.memmove(self.done, self.buf, W * H * 4)
        self.frames += 1

    def frame(self, n=1):
        """n pictures on, ending as one is complete"""
        end = self.frames + n
        while self.frames < end:
            self._ok(self.lib.Plus4VM_Run(self.vm, ctypes.c_size_t(1000)))

    def run_for(self, seconds):
        self.frame(max(1, round(seconds * 50)))

    def led(self):
        return self.lib.Plus4VM_GetFloppyDriveLEDState(self.vm) & 255

    def mem(self, addr, n=1):
        return bytes(self.lib.Plus4VM_ReadMemory(self.vm, (addr + i) & 0xFFFF, 1) for i in range(n))

    def poke(self, addr, data):
        for i, b in enumerate(data):
            self.lib.Plus4VM_WriteMemory(self.vm, (addr + i) & 0xFFFF, b, 1)

    def sym(self, name):
        return self.lab['_' + name]

    def peek(self, name, n=1):
        m = self.mem(self.sym(name), n)
        return m[0] if n == 1 else m

    def set(self, name, *values):
        self.poke(self.sym(name), values)

    def key(self, code, down):
        """a key by plus4emu's code (config/p4_keys.cfg): row * 8 + column"""
        self.lib.Plus4VM_KeyboardEvent(self.vm, code, int(down))

    def pixels(self):
        """the last complete picture: H rows of W (r, g, b)"""
        b = self.done
        return [[((b[y * W + x] >> 16) & 255, (b[y * W + x] >> 8) & 255, b[y * W + x] & 255)
                 for x in range(W)] for y in range(H)]

    def snow(self):
        """the pixels of colour $7F in the last picture"""
        b = self.done
        want = SNOW[0] << 16 | SNOW[1] << 8 | SNOW[2]
        return [(i // W, i % W) for i in range(W * H) if b[i] & 0xFFFFFF == want]

    def png(self, dst):
        write_png(dst, self.pixels())
        return dst

    def stop(self):
        L = self.lib
        L.Plus4VM_SetVideoOutputCallback(self.vm, None, None)
        L.Plus4VM_Destroy(self.vm)
        L.Plus4VideoDecoder_Destroy(self.vd)
