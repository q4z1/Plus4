#!/usr/bin/env python3
"""tracecmp.py a b - two traces of tests/trace.py compared: the first tick
where they part, and what differs there."""
import json, sys

import os
if not (os.path.exists(sys.argv[1]) and os.path.exists(sys.argv[2])):
    sys.exit('a trace is missing')
a = [json.loads(l) for l in open(sys.argv[1])]
b = [json.loads(l) for l in open(sys.argv[2])]
n = min(len(a), len(b))
for t in range(n):
    if a[t] != b[t]:
        print('tick %d differs:' % t)
        for k in sorted(set(a[t]) | set(b[t])):
            if a[t].get(k) != b[t].get(k):
                print('  %-12s %s\n  %-12s %s' % (k, a[t].get(k), '', b[t].get(k)))
        sys.exit(1)
print('%d ticks the same%s' % (n, '' if len(a) == len(b) else ' (lengths %d, %d)' % (len(a), len(b))))
