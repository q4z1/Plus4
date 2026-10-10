#!/usr/bin/env python3
"""p4emu_testbuild.py - the test build (build/stardew-test.d64) in
plus4emu: after the start its menu is there; the stick takes it to floor
23 of the mine (god mode on), fire+down brings the menu back, and it goes
to the village in summer at noon. Pictures to build/test/testbuild_*.png."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p4emu_snow as S
from p4emu import P4emu, ROOT
from run_tests import read_game_h

OUT = os.path.join(ROOT, 'build', 'test')
items, fields = read_game_h()
D = {}
for line in open(os.path.join(ROOT, 'build', 'gen', 'data.h')):
    w = line.split()
    if len(w) == 3 and w[0] == '#define' and w[2].isdigit():
        D[w[1]] = int(w[2])


def get(e, field):
    off, size, dims = fields[field]
    b = e.mem(e.sym('G') + off, size)
    return sum(x << (8 * k) for k, x in enumerate(b))


def keys(e, *names, hold=4, after=12):
    v = 0
    for n in names:
        v |= S.K[n]
    e.set('dbg_keys', v)
    e.frame(hold)
    e.set('dbg_keys', 0)
    e.frame(after)


def menu_up(e):
    """the test menu on screen: its title in the first row of the box"""
    for _ in range(600):
        if e.peek('menu') == 1 and not e.peek('scr_hidden') and \
                e.mem(0xD400 + 2 * 40 + 3, 4) == bytes([20, 5, 19, 20]):     # "test"
            return True
        e.frame()
    return False


fails = 0


def check(cond, what):
    global fails
    print(('ok    ' if cond else 'FAIL  ') + what)
    fails += 0 if cond else 1


e = P4emu(os.path.join(ROOT, 'build', 'stardew-test.d64'))
try:
    S.title(e)
    S.new_game(e)
    check(menu_up(e), 'the test menu after the start')
    check(get(e, 'lvl') == 3 and get(e, 'money') == 50000, 'gold tools and money')
    e.frame(5)
    e.png(os.path.join(OUT, 'testbuild_menu.png'))
    # the cursor starts on the farmhouse (row 2): down to the mine floor (9)
    for _ in range(7):
        keys(e, 'down')
    for _ in range(22):                     # floor 1 -> 23
        keys(e, 'right', hold=2, after=4)
    for _ in range(5):                      # season, hour, god mode (14)
        keys(e, 'down')
    keys(e, 'right')                        # god mode on
    for _ in range(5):
        keys(e, 'up')
    keys(e, 'fire')
    S.wait_room(e)
    e.frame(30)
    check(e.peek('floor_no') == 23 and e.peek('room_id') in (D['R_MINE_A'], D['R_MINE_B'], D['R_MINE_C']),
          'floor %d of the mine' % e.peek('floor_no'))
    check(e.peek('test_god') == 1, 'god mode on')
    e.frame(200)
    check(get(e, 'hp') == 100, 'health still full among the monsters (%d)' % get(e, 'hp'))
    e.png(os.path.join(OUT, 'testbuild_mine.png'))
    # fire+down: the menu again
    e.set('dbg_keys', S.K['fire'])
    e.frame(3)
    e.set('dbg_keys', S.K['fire'] | S.K['down'])
    e.frame(3)
    e.set('dbg_keys', 0)
    check(menu_up(e), 'fire+down opens the menu in the mine')
    for _ in range(6):                      # mine floor (9) -> village (3)
        keys(e, 'up')
    for _ in range(9 + 3 - 3):              # to the season row (12)
        keys(e, 'down')
    keys(e, 'right')                        # summer
    keys(e, 'down')
    for _ in range(4):                      # hour 6 -> 10... from the game's hour
        keys(e, 'right', hold=2, after=4)
    for _ in range(10):                     # back up to the village (3)
        keys(e, 'up')
    keys(e, 'fire')
    S.wait_room(e)
    e.frame(30)
    check(e.peek('room_id') == D['R_TOWN'] and e.peek('floor_no') == 0, 'the village')
    check(get(e, 'season') == 1, 'summer')
    e.png(os.path.join(OUT, 'testbuild_village.png'))
    sys.exit(1 if fails else 0)
finally:
    e.stop()
