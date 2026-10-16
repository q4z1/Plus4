#!/usr/bin/env python3
"""patch.py <in.prg> <labels> <out.prg> name=value...: a copy of the
program with single bytes set, each found by its label (ld65's -Ln file) -
for the test build (build.sh, tests/start.sh), which is the game itself
with test_map and unlocked set, so its labels hold for both."""
import re
import sys


def main():
    src, lbl, out, *sets = sys.argv[1:]
    data = bytearray(open(src, 'rb').read())
    at = data[0] | data[1] << 8                 # the load address
    lab = {m.group(2): int(m.group(1), 16)
           for m in re.finditer(r'al ([0-9A-F]+) \.(\S+)', open(lbl).read())}
    for s in sets:
        name, value = s.split('=')
        data[lab[name] - at + 2] = int(value, 0) & 255
    open(out, 'wb').write(data)


if __name__ == '__main__':
    main()
