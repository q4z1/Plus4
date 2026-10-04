"""p4emu.py - plus4emu (a third Plus/4 emulator, next to VICE and Yape) for
the tests, through its library: no window, no process of its own, the
emulator runs inside the test.

The library is the one in plus4emu's prebuilt Linux release (see
run-plus4emu.sh): plus4lib/libplus4emu.so, with its C interface in
plus4emu.h. A PAL Plus/4 with 64 KB and plus4emu's own ROMs; the program
is loaded as plus4emu's -prg does and started with RUN.

Pictures: 384 x 288, one line per TED line, as Yape's (tests/yape.py).
The joystick: the game's debug keys (_dbg_keys), as in the other tests.
"""
import ctypes, os, struct, zlib
from onetest import kill_other_tests

BASE = os.path.expanduser(os.environ.get(
    'P4EMU_DIR', '~/.cache/plus4emu/plus4emu-1.2.11-beta_20190320'))
# the release's own library lacks functions its program has (it was
# linked without them); ~/.cache/plus4emu/buildlib.sh builds one from
# plus4emu's source (git clone https://github.com/istvan-v/plus4emu
# ~/.cache/plus4emu/src), whose TED and CPU are the release's
LIB = os.path.expanduser(os.environ.get('P4EMU_LIB', '~/.cache/plus4emu/libplus4emu.so'))
W, H = 384, 288

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


class P4emu:
    def __init__(self, prg, boot=2.5):
        kill_other_tests()
        L = self.lib = ctypes.CDLL(LIB)
        L.Plus4VM_Create.restype = ctypes.c_void_p
        L.Plus4VM_GetLastErrorMessage.restype = ctypes.c_char_p
        L.Plus4VideoDecoder_Create.restype = ctypes.c_void_p
        L.Plus4VM_ReadMemory.restype = ctypes.c_uint8
        for f in ('Plus4VM_Run', 'Plus4VM_LoadROM', 'Plus4VM_LoadProgram',
                  'Plus4VM_SetRAMConfiguration', 'Plus4VM_PasteText'):
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
        L.Plus4VM_Reset(self.vm, 1)
        self.run_for(boot)
        self._ok(L.Plus4VM_LoadProgram(self.vm, os.path.abspath(prg).encode()))
        self._ok(L.Plus4VM_PasteText(self.vm, b'RUN\n', -1, -1))

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

    def mem(self, addr, n):
        return bytes(self.lib.Plus4VM_ReadMemory(self.vm, (addr + i) & 0xFFFF, 1) for i in range(n))

    def poke(self, addr, data):
        for i, b in enumerate(data):
            self.lib.Plus4VM_WriteMemory(self.vm, (addr + i) & 0xFFFF, b, 1)

    def key(self, code, down):
        """a key by plus4emu's code (config/p4_keys.cfg): row * 8 + column"""
        self.lib.Plus4VM_KeyboardEvent(self.vm, code, int(down))

    def pixels(self):
        """the last complete picture: H rows of W (r, g, b)"""
        b = self.done
        return [[((b[y * W + x] >> 16) & 255, (b[y * W + x] >> 8) & 255, b[y * W + x] & 255)
                 for x in range(W)] for y in range(H)]

    def png(self, dst):
        write_png(dst, self.pixels())
        return dst

    def stop(self):
        L = self.lib
        L.Plus4VM_SetVideoOutputCallback(self.vm, None, None)
        L.Plus4VM_Destroy(self.vm)
        L.Plus4VideoDecoder_Destroy(self.vd)
