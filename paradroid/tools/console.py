#!/usr/bin/env python3
"""console.py - the console's pages about the droids, out of the original

The original's console words its droid enquiry from a dictionary; rather
than rebuilding that, its screens were read: with VICE's monitor driving
the original's joystick in the enquiry (up for the next type, right for
the next page), the screen memory of every page of every type was decoded
from the panel's letter codes (the C64's window at $4800, rows 9-24). That
went into a JSON file of [row, column, colour, text] per line; this script
turns it into data/console.txt:

    python3 tools/console.py cons_pages.json
"""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, '..', 'data')
grab = json.load(open(sys.argv[1]))
types = {}
for l in open(os.path.join(DATA, 'droids.txt')):
    p = l.split()
    if p and p[0].isdigit():
        types[p[0]] = len(types)
out = {}
for pages in grab.values():
    head = [l for l in pages[0] if l[0] == 10][0][3]
    num = head[len('Unit type '):][:3].replace(' ', '0')
    t = types[num]
    out[t] = [[l for l in pg if l[0] not in (10, 24)] for pg in pages]
t = ['# The console\'s pages about each droid type, as the original shows them',
     '# (tools/console.py): per type its pages, each line as screen row,',
     '# column and text. The first page has the picture and the unit line',
     '# only, which console.c writes itself.', '']
for n in sorted(out):
    t.append('type %d' % n)
    for pg in out[n]:
        t.append('page')
        for row, col, colour, txt in pg:
            t.append('%d %d %s' % (row, col, txt))
    t.append('')
open(os.path.join(DATA, 'console.txt'), 'w').write('\n'.join(t))
print('data/console.txt: %d types' % len(out))
