#!/usr/bin/env python3
"""sid.py - run a PSID tune's own player and record what it writes to the
SID, frame by frame: a small 6502 emulator (the documented opcodes) with
64 KB of RAM, the tune loaded, init called once and play once a frame.

    from sid import record
    frames = record('Paradroid.sid', 3000)   # [ [25 registers], ... ]

or, as a script, a listing of the three voices: sid.py file.sid [frames]
"""
import struct
import sys


class CPU:
    def __init__(self, mem):
        self.m = mem
        self.a = self.x = self.y = 0
        self.s = 0xFF
        self.p = 0x24
        self.pc = 0
        self.writes = []

    # --- memory ---
    def rd(self, a):
        return self.m[a & 0xFFFF]

    def wr(self, a, v):
        a &= 0xFFFF
        self.m[a] = v & 0xFF
        if 0xD400 <= a <= 0xD418:
            self.writes.append((a - 0xD400, v & 0xFF))

    def rd16(self, a):
        return self.rd(a) | self.rd(a + 1) << 8

    def rd16zp(self, a):
        return self.rd(a & 0xFF) | self.rd((a + 1) & 0xFF) << 8

    def push(self, v):
        self.m[0x100 + self.s] = v & 0xFF
        self.s = (self.s - 1) & 0xFF

    def pull(self):
        self.s = (self.s + 1) & 0xFF
        return self.m[0x100 + self.s]

    # --- flags ---
    def nz(self, v):
        v &= 0xFF
        self.p = (self.p & 0x7D) | (v & 0x80) | (0 if v else 2)
        return v

    def flag(self, bit, on):
        self.p = (self.p | bit) if on else (self.p & ~bit & 0xFF)

    # --- addressing: returns an address (or None for accumulator/implied) ---
    def addr(self, mode):
        pc = self.pc
        if mode == 'imm':
            self.pc += 1
            return pc
        if mode == 'zp':
            self.pc += 1
            return self.rd(pc)
        if mode == 'zpx':
            self.pc += 1
            return (self.rd(pc) + self.x) & 0xFF
        if mode == 'zpy':
            self.pc += 1
            return (self.rd(pc) + self.y) & 0xFF
        if mode == 'abs':
            self.pc += 2
            return self.rd16(pc)
        if mode == 'abx':
            self.pc += 2
            return (self.rd16(pc) + self.x) & 0xFFFF
        if mode == 'aby':
            self.pc += 2
            return (self.rd16(pc) + self.y) & 0xFFFF
        if mode == 'izx':
            self.pc += 1
            return self.rd16zp(self.rd(pc) + self.x)
        if mode == 'izy':
            self.pc += 1
            return (self.rd16zp(self.rd(pc)) + self.y) & 0xFFFF
        if mode == 'ind':
            self.pc += 2
            a = self.rd16(pc)
            return self.rd(a) | self.rd((a & 0xFF00) | ((a + 1) & 0xFF)) << 8
        if mode == 'rel':
            self.pc += 1
            o = self.rd(pc)
            return (self.pc + (o - 256 if o & 0x80 else o)) & 0xFFFF
        return None

    def adc(self, v):
        c = self.p & 1
        if self.p & 8:                          # decimal
            lo = (self.a & 15) + (v & 15) + c
            hi = (self.a >> 4) + (v >> 4)
            if lo > 9:
                lo += 6
                hi += 1
            self.flag(0x40, (~(self.a ^ v) & (self.a ^ (hi << 4)) & 0x80))
            if hi > 9:
                hi += 6
            self.flag(1, hi > 15)
            self.a = self.nz(((hi << 4) | (lo & 15)) & 0xFF)
            return
        r = self.a + v + c
        self.flag(0x40, (~(self.a ^ v) & (self.a ^ r) & 0x80))
        self.flag(1, r > 0xFF)
        self.a = self.nz(r)

    def sbc(self, v):
        if self.p & 8:
            c = self.p & 1
            lo = (self.a & 15) - (v & 15) - (1 - c)
            hi = (self.a >> 4) - (v >> 4)
            if lo < 0:
                lo -= 6
                hi -= 1
            if hi < 0:
                hi -= 6
            r = self.a - v - (1 - c)
            self.flag(0x40, ((self.a ^ v) & (self.a ^ r) & 0x80))
            self.flag(1, r >= 0)
            self.a = self.nz(((hi << 4) | (lo & 15)) & 0xFF)
            return
        self.adc(v ^ 0xFF)

    def cmp(self, r, v):
        self.flag(1, r >= v)
        self.nz(r - v)

    def step(self):
        op = self.rd(self.pc)
        self.pc = (self.pc + 1) & 0xFFFF
        name, mode = OPS[op]
        a = self.addr(mode)
        f = getattr(self, 'op_' + name)
        f(a, mode)

    # --- the instructions ---
    def val(self, a, mode):
        return self.a if mode == 'acc' else self.rd(a)

    def put(self, a, mode, v):
        if mode == 'acc':
            self.a = v & 0xFF
        else:
            self.wr(a, v)

    def op_lda(self, a, m): self.a = self.nz(self.rd(a))
    def op_ldx(self, a, m): self.x = self.nz(self.rd(a))
    def op_ldy(self, a, m): self.y = self.nz(self.rd(a))
    def op_sta(self, a, m): self.wr(a, self.a)
    def op_stx(self, a, m): self.wr(a, self.x)
    def op_sty(self, a, m): self.wr(a, self.y)
    def op_tax(self, a, m): self.x = self.nz(self.a)
    def op_tay(self, a, m): self.y = self.nz(self.a)
    def op_txa(self, a, m): self.a = self.nz(self.x)
    def op_tya(self, a, m): self.a = self.nz(self.y)
    def op_tsx(self, a, m): self.x = self.nz(self.s)
    def op_txs(self, a, m): self.s = self.x
    def op_pha(self, a, m): self.push(self.a)
    def op_php(self, a, m): self.push(self.p | 0x30)
    def op_pla(self, a, m): self.a = self.nz(self.pull())
    def op_plp(self, a, m): self.p = (self.pull() & 0xEF) | 0x20
    def op_and(self, a, m): self.a = self.nz(self.a & self.rd(a))
    def op_ora(self, a, m): self.a = self.nz(self.a | self.rd(a))
    def op_eor(self, a, m): self.a = self.nz(self.a ^ self.rd(a))
    def op_adc(self, a, m): self.adc(self.rd(a))
    def op_sbc(self, a, m): self.sbc(self.rd(a))
    def op_cmp(self, a, m): self.cmp(self.a, self.rd(a))
    def op_cpx(self, a, m): self.cmp(self.x, self.rd(a))
    def op_cpy(self, a, m): self.cmp(self.y, self.rd(a))

    def op_bit(self, a, m):
        v = self.rd(a)
        self.p = (self.p & 0x3D) | (v & 0xC0) | (0 if v & self.a else 2)

    def op_inc(self, a, m): self.wr(a, self.nz(self.rd(a) + 1))
    def op_dec(self, a, m): self.wr(a, self.nz(self.rd(a) - 1))
    def op_inx(self, a, m): self.x = self.nz(self.x + 1)
    def op_iny(self, a, m): self.y = self.nz(self.y + 1)
    def op_dex(self, a, m): self.x = self.nz(self.x - 1)
    def op_dey(self, a, m): self.y = self.nz(self.y - 1)

    def op_asl(self, a, m):
        v = self.val(a, m)
        self.flag(1, v & 0x80)
        self.put(a, m, self.nz(v << 1))

    def op_lsr(self, a, m):
        v = self.val(a, m)
        self.flag(1, v & 1)
        self.put(a, m, self.nz(v >> 1))

    def op_rol(self, a, m):
        v = self.val(a, m)
        c = self.p & 1
        self.flag(1, v & 0x80)
        self.put(a, m, self.nz((v << 1) | c))

    def op_ror(self, a, m):
        v = self.val(a, m)
        c = self.p & 1
        self.flag(1, v & 1)
        self.put(a, m, self.nz((v >> 1) | (c << 7)))

    def branch(self, a, cond):
        if cond:
            self.pc = a

    def op_bpl(self, a, m): self.branch(a, not self.p & 0x80)
    def op_bmi(self, a, m): self.branch(a, self.p & 0x80)
    def op_bvc(self, a, m): self.branch(a, not self.p & 0x40)
    def op_bvs(self, a, m): self.branch(a, self.p & 0x40)
    def op_bcc(self, a, m): self.branch(a, not self.p & 1)
    def op_bcs(self, a, m): self.branch(a, self.p & 1)
    def op_bne(self, a, m): self.branch(a, not self.p & 2)
    def op_beq(self, a, m): self.branch(a, self.p & 2)
    def op_jmp(self, a, m): self.pc = a

    def op_jsr(self, a, m):
        r = (self.pc - 1) & 0xFFFF
        self.push(r >> 8)
        self.push(r)
        self.pc = a

    def op_rts(self, a, m):
        self.pc = ((self.pull() | self.pull() << 8) + 1) & 0xFFFF

    def op_rti(self, a, m):
        self.p = (self.pull() & 0xEF) | 0x20
        self.pc = self.pull() | self.pull() << 8

    def op_brk(self, a, m):
        raise RuntimeError('BRK at %04x' % ((self.pc - 1) & 0xFFFF))

    def op_clc(self, a, m): self.flag(1, 0)
    def op_sec(self, a, m): self.flag(1, 1)
    def op_cli(self, a, m): self.flag(4, 0)
    def op_sei(self, a, m): self.flag(4, 1)
    def op_cld(self, a, m): self.flag(8, 0)
    def op_sed(self, a, m): self.flag(8, 1)
    def op_clv(self, a, m): self.flag(0x40, 0)
    def op_nop(self, a, m): pass

    def op_bad(self, a, m):
        raise RuntimeError('illegal opcode %02x at %04x'
                           % (self.rd((self.pc - 1) & 0xFFFF), (self.pc - 1) & 0xFFFF))

    def call(self, addr, a=0, limit=1000000):
        """run the routine at addr until it returns"""
        self.a = a
        self.s = 0xFF
        self.push(0xFF)                 # return to $FFFF+1 = $0000: stop
        self.push(0xFF)
        self.pc = addr
        for _ in range(limit):
            if self.pc == 0 and self.s == 0xFF:
                return
            self.step()
        raise RuntimeError('no return from %04x' % addr)


def _table():
    t = {}
    groups = {
        'adc': {0x69: 'imm', 0x65: 'zp', 0x75: 'zpx', 0x6D: 'abs', 0x7D: 'abx', 0x79: 'aby', 0x61: 'izx', 0x71: 'izy'},
        'and': {0x29: 'imm', 0x25: 'zp', 0x35: 'zpx', 0x2D: 'abs', 0x3D: 'abx', 0x39: 'aby', 0x21: 'izx', 0x31: 'izy'},
        'cmp': {0xC9: 'imm', 0xC5: 'zp', 0xD5: 'zpx', 0xCD: 'abs', 0xDD: 'abx', 0xD9: 'aby', 0xC1: 'izx', 0xD1: 'izy'},
        'eor': {0x49: 'imm', 0x45: 'zp', 0x55: 'zpx', 0x4D: 'abs', 0x5D: 'abx', 0x59: 'aby', 0x41: 'izx', 0x51: 'izy'},
        'lda': {0xA9: 'imm', 0xA5: 'zp', 0xB5: 'zpx', 0xAD: 'abs', 0xBD: 'abx', 0xB9: 'aby', 0xA1: 'izx', 0xB1: 'izy'},
        'ora': {0x09: 'imm', 0x05: 'zp', 0x15: 'zpx', 0x0D: 'abs', 0x1D: 'abx', 0x19: 'aby', 0x01: 'izx', 0x11: 'izy'},
        'sbc': {0xE9: 'imm', 0xE5: 'zp', 0xF5: 'zpx', 0xED: 'abs', 0xFD: 'abx', 0xF9: 'aby', 0xE1: 'izx', 0xF1: 'izy'},
        'sta': {0x85: 'zp', 0x95: 'zpx', 0x8D: 'abs', 0x9D: 'abx', 0x99: 'aby', 0x81: 'izx', 0x91: 'izy'},
        'ldx': {0xA2: 'imm', 0xA6: 'zp', 0xB6: 'zpy', 0xAE: 'abs', 0xBE: 'aby'},
        'ldy': {0xA0: 'imm', 0xA4: 'zp', 0xB4: 'zpx', 0xAC: 'abs', 0xBC: 'abx'},
        'stx': {0x86: 'zp', 0x96: 'zpy', 0x8E: 'abs'},
        'sty': {0x84: 'zp', 0x94: 'zpx', 0x8C: 'abs'},
        'cpx': {0xE0: 'imm', 0xE4: 'zp', 0xEC: 'abs'},
        'cpy': {0xC0: 'imm', 0xC4: 'zp', 0xCC: 'abs'},
        'bit': {0x24: 'zp', 0x2C: 'abs'},
        'inc': {0xE6: 'zp', 0xF6: 'zpx', 0xEE: 'abs', 0xFE: 'abx'},
        'dec': {0xC6: 'zp', 0xD6: 'zpx', 0xCE: 'abs', 0xDE: 'abx'},
        'asl': {0x0A: 'acc', 0x06: 'zp', 0x16: 'zpx', 0x0E: 'abs', 0x1E: 'abx'},
        'lsr': {0x4A: 'acc', 0x46: 'zp', 0x56: 'zpx', 0x4E: 'abs', 0x5E: 'abx'},
        'rol': {0x2A: 'acc', 0x26: 'zp', 0x36: 'zpx', 0x2E: 'abs', 0x3E: 'abx'},
        'ror': {0x6A: 'acc', 0x66: 'zp', 0x76: 'zpx', 0x6E: 'abs', 0x7E: 'abx'},
        'jmp': {0x4C: 'abs', 0x6C: 'ind'},
        'jsr': {0x20: 'abs'},
    }
    for name, ops in groups.items():
        for op, mode in ops.items():
            t[op] = (name, mode)
    for op, name in {0x10: 'bpl', 0x30: 'bmi', 0x50: 'bvc', 0x70: 'bvs', 0x90: 'bcc',
                     0xB0: 'bcs', 0xD0: 'bne', 0xF0: 'beq'}.items():
        t[op] = (name, 'rel')
    for op, name in {0xAA: 'tax', 0xA8: 'tay', 0x8A: 'txa', 0x98: 'tya', 0xBA: 'tsx',
                     0x9A: 'txs', 0x48: 'pha', 0x08: 'php', 0x68: 'pla', 0x28: 'plp',
                     0xE8: 'inx', 0xC8: 'iny', 0xCA: 'dex', 0x88: 'dey', 0x60: 'rts',
                     0x40: 'rti', 0x00: 'brk', 0x18: 'clc', 0x38: 'sec', 0x58: 'cli',
                     0x78: 'sei', 0xD8: 'cld', 0xF8: 'sed', 0xB8: 'clv', 0xEA: 'nop'}.items():
        t[op] = (name, 'imp')
    return [t.get(i, ('bad', 'imp')) for i in range(256)]


OPS = _table()


def load(path):
    d = open(path, 'rb').read()
    off, ld, init, play, songs, start = struct.unpack('>HHHHHH', d[6:18])
    body = d[off:]
    if ld == 0:
        ld = body[0] | body[1] << 8
        body = body[2:]
    mem = bytearray(65536)
    mem[ld:ld + len(body)] = body
    return mem, init, play, start


def record(path, frames, song=None):
    """the SID's 25 registers after each frame's play call"""
    mem, init, play, start = load(path)
    cpu = CPU(mem)
    cpu.call(init, (song or start) - 1)
    regs = [0] * 25
    for a, v in cpu.writes:
        regs[a] = v
    out = []
    for _ in range(frames):
        cpu.writes = []
        cpu.call(play)
        for a, v in cpu.writes:
            regs[a] = v
        out.append(list(regs))
    return out


if __name__ == '__main__':
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 200
    for i, r in enumerate(record(sys.argv[1], n)):
        v = ['%04x %02x' % (r[k * 7] | r[k * 7 + 1] << 8, r[k * 7 + 4]) for k in range(3)]
        print('%5d  %s   %s   %s' % (i, *v))
