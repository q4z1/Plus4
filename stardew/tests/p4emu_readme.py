#!/usr/bin/env python3
"""p4emu_readme.py - the README's pictures, in plus4emu: screenshots/*.png
(title, farm, village, mine, store, backpack, year_end)."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p4emu_snow as S
from p4emu import P4emu, ROOT
from run_tests import read_game_h

DST = os.path.join(ROOT, 'screenshots')
items, fields = read_game_h()


def setg(e, field, value, index=0):
    off, size, dims = fields[field]
    e.poke(e.sym('G') + off + index * size, [(value >> (8 * k)) & 255 for k in range(size)])


def tap(e, key, after=30):
    e.set('dbg_keys', S.K[key])
    e.frame(5)
    e.set('dbg_keys', 0)
    e.frame(after)


def shot(e, name):
    print(e.png(os.path.join(DST, name + '.png')))


e = P4emu()
try:
    S.title(e)
    e.frame(20)
    shot(e, 'title')
    S.new_game(e)
    e.frame(20)
    setg(e, 'hour', 10)
    setg(e, 'money', 1250)
    for k, (it, n) in enumerate([('IT_S_PARSNIP', 12), ('IT_PARSNIP', 7), ('IT_ORE_C', 9),
                                 ('IT_SALAD', 2)]):
        setg(e, 'inv', items[it], 5 + k)
        setg(e, 'cnt', n, 5 + k)
    # the farm: a field of parsnips, some watered
    T = {}
    for line in open(os.path.join(ROOT, 'build', 'gen', 'data.h')):
        w = line.split()
        if len(w) == 3 and w[0] == '#define':
            T[w[1]] = int(w[2])
    for y in range(6, 9):
        for x in range(3, 9):
            i = y * 20 + x
            ripe = x < 6
            setg(e, 'farm', T['T_PARSNIP'] + (y & 1) if ripe else T['T_SPROUT'] + (x & 1), 256 + i)
            setg(e, 'crop', 1, 220 + i)
            setg(e, 'age', 4 if ripe else 1, 220 + i)
    S.goto(e, 'FARM_E', 9, 5)
    tap(e, 'down', 10)
    shot(e, 'farm')
    S.goto(e, 'TOWN', 6, 8)
    e.frame(60)
    shot(e, 'village')
    S.goto(e, 'MINE_A', 9, 9, floor=23)
    setg(e, 'hp', 100)
    tap(e, 'left', 20)
    shot(e, 'mine')
    S.goto(e, 'STORE', 6, 5)
    tap(e, 'up', 10)
    tap(e, 'fire', 60)
    tap(e, 'down', 20)
    shot(e, 'store')
    tap(e, 'menu', 30)
    tap(e, 'menu', 40)
    shot(e, 'backpack')
    tap(e, 'menu', 40)
    # the last night of the year
    setg(e, 'season', 3)
    setg(e, 'day', 13)
    setg(e, 'earned', 23500)
    setg(e, 'deepest', 23)
    setg(e, 'quests', 3)
    setg(e, 'shipped', 0x13)
    for k, v in enumerate((180, 120, 60)):
        setg(e, 'friend', v, k)
    S.goto(e, 'HOUSE', 5, 4)
    tap(e, 'left', 10)
    tap(e, 'fire', 30)
    tap(e, 'fire', 150)
    shot(e, 'year_end')
finally:
    e.stop()
