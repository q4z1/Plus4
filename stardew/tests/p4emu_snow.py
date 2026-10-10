#!/usr/bin/env python3
"""p4emu_snow.py [pictures] - "snow" in plus4emu: a pixel of colour $7F,
which the real TED draws where one of its colour registers ($FF15-$FF19)
is written while that colour is on the beam (plus4emu shows it, VICE and
Yape do not). Boots the disk, then counts such pixels on the title, in
the farmhouse, on the farm walking about, in the village and in the mine,
by line; the first picture with any goes to build/test/snow_<where>.png.
Also times the loads: pictures from the button to the room on screen."""
import os, sys, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from p4emu import P4emu, ROOT

OUT = os.path.join(ROOT, 'build', 'test')
N = int(sys.argv[1]) if len(sys.argv) > 1 and __name__ == '__main__' else 150
K = dict(up=1, down=2, left=4, right=8, fire=16, menu=128)


def count(e, where, n, keys=()):
    pos = collections.Counter()
    pics = 0
    for i in range(n):
        if keys:
            e.set('dbg_keys', K[keys[(i // 25) % len(keys)]])
        e.frame()
        s = e.snow()
        if s:
            if not pics:
                e.png(os.path.join(OUT, 'snow_%s.png' % where))
            pics += 1
            pos.update(y for y, x in s)
    e.set('dbg_keys', 0)
    e.png(os.path.join(OUT, 'p4_%s.png' % where))
    print('%-8s %3d of %d pictures with snow%s' % (
        where, pics, n, ''.join('  line %d: %d' % kv for kv in sorted(pos.items())[:8])))
    return pics


def lit(e):
    return e.mem(0xFF06)[0] & 0x10


def wait_room(e, limit=3000):
    """pictures until the screen is on again after a load"""
    n = 0
    while lit(e) and n < 100:                # (the load starting)
        e.frame()
        n += 1
    while not lit(e) and n < limit:
        e.frame()
        n += 1
    return n


def goto(e, room, x, y, floor=0):
    d = {}
    for line in open(os.path.join(ROOT, 'build', 'gen', 'data.h')):
        w = line.split()
        if len(w) == 3 and w[0] == '#define':
            d[w[1]] = w[2]
    e.set('dbg_floor', floor)
    e.set('dbg_x', x)
    e.set('dbg_y', y)
    e.set('dbg_goto', int(d['R_' + room]) + 1)
    return wait_room(e)


def title(e):
    n = 0
    # the title on screen: "new game" written, the screen on
    while not (e.peek('menu') == 1 and lit(e) and e.mem(0xFF0A)[0] & 2
               and e.mem(0xD400 + 14 * 40 + 15)[0] == 14 and not e.peek('scr_hidden')):
        e.frame()
        n += 1
        if n > 6000:
            sys.exit('no title after %d pictures' % n)
    return n


def new_game(e):
    e.set('dbg_keys', K['fire'])
    e.frame(5)
    e.set('dbg_keys', 0)
    return wait_room(e)


def boot():
    """plus4emu, the disk loaded and started, a new game in the farmhouse"""
    e = P4emu()
    title(e)
    new_game(e)
    e.frame(20)
    return e


if __name__ == '__main__':
    e = P4emu()
    try:
        n = title(e)
        print('loaded and unpacked: title after %.1f s more' % (n / 50))
        bad = count(e, 'title', N // 3)
        print('new game: %.1f s' % (new_game(e) / 50))
        e.frame(20)
        bad += count(e, 'house', N // 3, ('right', 'down'))
        print('farm:     %.1f s' % (goto(e, 'FARM_W', 10, 5) / 50))
        bad += count(e, 'farm', N, ('left', 'up', 'right', 'down'))
        print('village:  %.1f s' % (goto(e, 'TOWN', 10, 6) / 50))
        bad += count(e, 'village', N // 2, ('down', 'right'))
        print('mine:     %.1f s' % (goto(e, 'MINE_A', 9, 9, floor=23) / 50))
        bad += count(e, 'mine', N, ('left', 'right'))
        print('farm again: %.1f s' % (goto(e, 'FARM_W', 10, 5) / 50))
        print('snow in %d pictures' % bad)
        sys.exit(1 if bad else 0)
    finally:
        e.stop()
