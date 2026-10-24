#!/usr/bin/env python3
"""Recursive-descent 68000 disassembler for reverse engineering Amiga programs.

Follows branches and calls from the entry points, so code and data are told
apart; what is never reached is listed as data (with strings). Labels are
written as L_<address>, or as the names given in a symbol file.

    m68k-dis.py [options] image.bin base [entry ...]
      -s FILE    symbols: lines "address name [comment]"; "address code" marks
                 an extra entry point without naming it
      -o FILE    write the listing there instead of stdout
      --pointers also start at every long word in the image that points into
                 it and starts with plausible code (finds jump tables)

Addresses are hexadecimal (with or without $ or 0x).
"""
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'python'))
import capstone  # noqa: E402

STOP = {'rts', 'rte', 'rtr', 'jmp', 'bra', 'bra.b', 'bra.w', 'illegal', 'stop'}


def num(s):
    s = s.strip().lstrip('$')
    return int(s, 16)


class Disassembler:
    def __init__(self, image, base):
        self.image = image
        self.base = base
        self.end = base + len(image)
        self.md = capstone.Cs(capstone.CS_ARCH_M68K,
                              capstone.CS_MODE_BIG_ENDIAN | capstone.CS_MODE_M68K_000)
        self.md.detail = True
        self.insns = {}            # address -> instruction
        self.labels = {}           # address -> name
        self.comments = {}
        self.xrefs = {}            # target -> set of sources
        self.calls = set()

    def inside(self, a):
        return self.base <= a < self.end

    def decode(self, a):
        off = a - self.base
        for i in self.md.disasm(self.image[off:off + 10], a, 1):
            try:
                i.operands
            except capstone.CsError:
                return None
            return i
        return None

    def targets(self, i):
        """Branch/call target and the absolute addresses used by i."""
        branch, refs = None, []
        mn = i.mnemonic
        for op in i.operands:
            if op.type == capstone.m68k.M68K_OP_BR_DISP:
                branch = i.address + 2 + op.br_disp.disp
            elif op.type == capstone.m68k.M68K_OP_MEM:
                if op.address_mode in (capstone.m68k.M68K_AM_ABSOLUTE_DATA_LONG,
                                       capstone.m68k.M68K_AM_ABSOLUTE_DATA_SHORT):
                    refs.append(op.imm & 0xffffffff)
                elif op.address_mode == capstone.m68k.M68K_AM_PCI_DISP:
                    refs.append(i.address + 2 + op.mem.disp)
                elif op.address_mode == capstone.m68k.M68K_AM_PCI_INDEX_8_BIT_DISP:
                    refs.append(i.address + 2 + op.mem.disp)
            elif op.type == capstone.m68k.M68K_OP_IMM and i.size >= 6:
                refs.append(op.imm & 0xffffffff)
        if mn in ('jmp', 'jsr') and refs and branch is None:
            op = i.operands[0]
            if op.type == capstone.m68k.M68K_OP_MEM and op.address_mode in (
                    capstone.m68k.M68K_AM_ABSOLUTE_DATA_LONG,
                    capstone.m68k.M68K_AM_ABSOLUTE_DATA_SHORT,
                    capstone.m68k.M68K_AM_PCI_DISP):
                branch = refs[0]
        return branch, refs

    def run(self, entries):
        todo = list(entries)
        while todo:
            a = todo.pop()
            while self.inside(a) and a not in self.insns:
                i = self.decode(a)
                if i is None:
                    self.comments.setdefault(a, 'undecodable, reached as code')
                    break
                # overlapping an instruction decoded earlier: stop
                if any(x in self.insns for x in range(a + 2, a + i.size, 2)):
                    break
                self.insns[a] = i
                branch, refs = self.targets(i)
                for r in refs:
                    if self.inside(r):
                        self.xrefs.setdefault(r, set()).add(a)
                if branch is not None and self.inside(branch):
                    self.xrefs.setdefault(branch, set()).add(a)
                    if i.mnemonic in ('jsr', 'bsr', 'bsr.b', 'bsr.w'):
                        self.calls.add(branch)
                    todo.append(branch)
                if i.mnemonic in STOP:
                    break
                a += i.size

    def plausible_code(self, a):
        """A few instructions decode without hitting data-looking opcodes."""
        n = 0
        while n < 6 and self.inside(a):
            i = self.decode(a)
            if i is None or i.mnemonic in ('illegal',) or i.mnemonic.startswith('dc'):
                return False
            if i.mnemonic in STOP:
                return True
            a += i.size
            n += 1
        return n == 6

    def pointer_entries(self):
        out = []
        for off in range(0, len(self.image) - 3, 2):
            v = int.from_bytes(self.image[off:off + 4], 'big')
            if self.inside(v) and v % 2 == 0 and self.plausible_code(v):
                out.append(v)
        return out

    def label(self, a):
        return self.labels.get(a) or f'L_{a:06x}'

    def operand_text(self, i):
        text = i.op_str
        branch, refs = self.targets(i)
        # replace numbers that are addresses inside the image by labels
        for r in ([branch] if branch is not None else []) + refs:
            if r is not None and self.inside(r) and (r in self.insns or r in self.labels
                                                     or r in self.xrefs):
                for pat in (f'${r:x}.l', f'${r:x}.w', f'${r:x}(pc)', f'${r:x}'):
                    if pat in text:
                        text = text.replace(pat, self.label(r) + ('(pc)' if '(pc)' in pat else ''), 1)
                        break
        return text

    def listing(self, out):
        a = self.base
        while a < self.end:
            if a in self.labels or a in self.xrefs or a in self.calls:
                refs = sorted(self.xrefs.get(a, ()))
                if a in self.calls:
                    out.write('\n')
                xr = ' ; refs ' + ' '.join(f'{r:06x}' for r in refs[:8]) + (' ...' if len(refs) > 8 else '') if refs else ''
                out.write(f'{self.label(a)}:{xr}\n')
            if a in self.insns:
                i = self.insns[a]
                c = self.comments.get(a, '')
                hexb = i.bytes.hex()
                out.write(f'  {a:06x}  {hexb:<20} {i.mnemonic:<9} {self.operand_text(i)}'
                          + (f'  ; {c}' if c else '') + '\n')
                a += i.size
                continue
            # data up to the next instruction or label
            e = a + 1
            while e < self.end and e not in self.insns and e not in self.labels \
                    and e not in self.xrefs and e - a < 16:
                e += 1
            chunk = self.image[a - self.base:e - self.base]
            txt = ''.join(chr(b) if 32 <= b < 127 else '.' for b in chunk)
            out.write(f'  {a:06x}  dc.b {chunk.hex(" ")}  |{txt}|\n')
            a = e


def main():
    args = sys.argv[1:]
    symfile = outfile = None
    pointers = False
    pos = []
    while args:
        x = args.pop(0)
        if x == '-s':
            symfile = args.pop(0)
        elif x == '-o':
            outfile = args.pop(0)
        elif x == '--pointers':
            pointers = True
        else:
            pos.append(x)
    if len(pos) < 2:
        sys.exit(__doc__)
    with open(pos[0], 'rb') as f:
        image = f.read()
    d = Disassembler(image, num(pos[1]))
    entries = [num(x) for x in pos[2:]] or [d.base]
    if symfile:
        for line in open(symfile):
            line = line.split('#')[0].strip()
            if not line:
                continue
            m = re.match(r'(\S+)\s+(\S+)\s*(.*)', line)
            if not m:
                continue
            a = num(m.group(1))
            if m.group(2) == 'code':
                entries.append(a)
                continue
            d.labels[a] = m.group(2)
            if m.group(3):
                d.comments[a] = m.group(3)
            if m.group(2).startswith(('f_', 'irq_')):
                entries.append(a)
    d.run(entries)
    if pointers:
        d.run(d.pointer_entries())
    out = open(outfile, 'w') if outfile else sys.stdout
    d.listing(out)
    n = sum(i.size for i in d.insns.values())
    print(f'{len(d.insns)} instructions, {n} of {len(image)} bytes code', file=sys.stderr)


if __name__ == '__main__':
    main()
