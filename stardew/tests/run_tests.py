#!/usr/bin/env python3
"""Play Stardew Pond in a headless VICE and check what happens.

    tests/run_tests.py            all tests
    tests/run_tests.py sleep ship only the tests whose names contain a word
    tests/run_tests.py -l         list the tests

Build first (./build.sh). The tests drive the game the way a player does -
keys go in through dbg_keys, which the game reads as if they were pressed -
but they set up the state they need directly: the time, the backpack, the
tiles of the farm, and they jump into rooms through dbg_goto instead of
walking there. Addresses come from build/stardew.lbl, the layout of the game
state from the struct in game.h, tile and room numbers from build/gen/data.h.

All tests run one after the other in one emulator. A failed test leaves a
screenshot in build/test/.
"""
import os
import re
import sys
import time
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, 'build', 'test')
sys.path.insert(0, HERE)
from vice import Vice  # noqa: E402


# ---------------------------------------------------------------------------
# What the build says about the program
# ---------------------------------------------------------------------------

def read_labels():
    lab = {}
    for line in open(os.path.join(ROOT, 'build', 'stardew.lbl')):
        m = re.match(r'al ([0-9A-F]+) \.(\S+)', line)
        if m:
            lab.setdefault(m.group(2), int(m.group(1), 16))
    return lab


def read_defines():
    d = {}
    for line in open(os.path.join(ROOT, 'build', 'gen', 'data.h')):
        m = re.match(r'#define (\w+) (\d+)$', line.strip())
        if m:
            d[m.group(1)] = int(m.group(2))
    return d


def read_game_h():
    """The items enum and the fields of struct game with offsets and sizes."""
    src = open(os.path.join(ROOT, 'game.h')).read()
    consts = {}
    for m in re.finditer(r'#define (\w+) (\d+)\b', src):
        consts[m.group(1)] = int(m.group(2))
    body = re.search(r'enum \{\s*(IT_NONE.*?)\};', src, re.S).group(1)
    items = {}
    for k, name in enumerate(re.findall(r'IT_\w+|N_ITEMS', body)):
        items[name] = k
    body = re.search(r'struct game \{(.*?)\};', src, re.S).group(1)
    fields, off = {}, 0
    for m in re.finditer(r'unsigned (char|long) (\w+)((?:\[[^\]]+\])*);', body):
        size = 1 if m.group(1) == 'char' else 4
        dims = [eval(d, {}, consts) for d in re.findall(r'\[([^\]]+)\]', m.group(3))]
        n = 1
        for d in dims:
            n *= d
        fields[m.group(2)] = (off, size, dims)
        off += size * n
    return items, fields


KEYS = dict(up=1, down=2, left=4, right=8, fire=16, prev=32, next=64, menu=128)
DIRS = dict(down=0, up=1, left=2, right=3)


class Game:
    def __init__(self):
        self.lab = read_labels()
        self.d = read_defines()
        self.it, self.fields = read_game_h()
        self.v = Vice(os.path.join(ROOT, 'build', 'stardew.d64'), OUT)
        self.G = self.lab['_G']

    # ---- memory ------------------------------------------------------------
    def addr(self, sym):
        return self.lab['_' + sym]

    def peek(self, sym, n=1):
        m = self.v.mem(self.addr(sym), n)
        return m[0] if n == 1 else m

    def poke(self, sym, *values):
        self.v.poke(self.addr(sym), list(values))

    def get(self, field, index=0):
        off, size, dims = self.fields[field]
        a = self.G + off + index * size
        b = self.v.mem(a, size)
        return sum(x << (8 * k) for k, x in enumerate(b))

    def set(self, field, value, index=0):
        off, size, dims = self.fields[field]
        self.v.poke(self.G + off + index * size,
                    [(value >> (8 * k)) & 255 for k in range(size)])

    def farm(self, f, x, y):
        return self.get('farm', f * 256 + y * 20 + x)

    def set_farm(self, f, x, y, tile, crop=0, age=0):
        i = y * 20 + x
        self.set('farm', tile, f * 256 + i)
        self.set('crop', crop, f * 220 + i)
        self.set('age', age, f * 220 + i)

    def tile(self, x, y):
        return self.v.mem(self.addr('room') + y * 20 + x, 1)[0]

    def count(self, item):
        inv = self.v.mem(self.G + self.fields['inv'][0], 16)
        cnt = self.v.mem(self.G + self.fields['cnt'][0], 16)
        return sum(c for i, c in zip(inv, cnt) if i == item)

    def give(self, slot, item, n=1, select=True):
        self.set('inv', item, slot)
        self.set('cnt', n, slot)
        if select:
            self.poke('sel', slot)
            self.poke('row2', slot & 8)

    # ---- time and input ----------------------------------------------------
    def run(self, s):
        self.v.run_for(s)

    def dark(self):
        return not (self.v.mem(0xFF06, 1)[0] & 0x10)

    def keys(self, *names):
        v = 0
        for n in names:
            v |= KEYS[n]
        self.poke('dbg_keys', v)

    def press(self, name, hold=0.1, after=0.25):
        self.keys(name)
        self.run(hold)
        self.keys()
        self.run(after)

    def wait_for(self, cond, timeout=60, what='condition'):
        """Run until cond() holds; while the screen is dark (disk), in warp."""
        end = time.time() + timeout
        warp = False
        while time.time() < end:
            if cond():
                break
            d = self.dark()
            if d != warp:
                self.v.cmd('warp on' if d else 'warp off')
                warp = d
            self.v.run_for(0.05 if d else 0.1)
        else:
            if warp:
                self.v.cmd('warp off')
            raise AssertionError(f'timed out waiting for {what}')
        if warp:
            self.v.cmd('warp off')

    def settle(self):
        self.wait_for(lambda: not self.dark(), what='the screen')
        self.run(0.2)

    def start(self, cont=False):
        """Boot (in warp) to the title, then a new game or 'continue'."""
        self.wait_for(lambda: self.v.mem(self.addr('menu'), 1)[0] == 1
                      and not self.dark() and self.v.mem(0xFF0A, 1)[0] & 2,
                      90, 'the title')
        self.v.cmd('warp off')
        self.run(0.3)
        if cont:
            self.press('down', 0.1, 0.2)
        self.press('fire', 0.1, 0.1)
        self.settle()

    def morning(self, hour=10):
        self.set('hour', hour)
        self.set('minute', 0)
        self.poke('tick_frames', 0, 0)
        self.set('energy', 100)
        self.set('hp', 100)
        self.set('rain', 0)

    def goto(self, room, x, y, face='down', floor=0):
        self.poke('dbg_floor', floor)
        self.poke('dbg_x', x)
        self.poke('dbg_y', y)
        self.poke('dbg_goto', self.d['R_' + room] + 1)
        self.wait_for(lambda: self.peek('dbg_goto') == 0, what='the room')
        self.settle()
        self.poke('pdir', DIRS[face])

    def act(self):
        """Press fire as a player does; wait out the swing."""
        self.press('fire', 0.1, 0.35)

    def sleep(self):
        """Go to bed; answer yes; through the morning page back to the house."""
        self.goto('HOUSE', 5, 4, 'left')
        day = self.get('day')
        self.act()
        self.press('fire', 0.1, 0.2)                   # yes
        self.morning_page()

    def morning_page(self):
        """The page after a night: it saves (dark screen), then waits for fire."""
        self.wait_for(self.dark, 60, 'the save')
        self.wait_for(lambda: self.peek('menu') == 1 and not self.dark(), 60,
                      'the morning page')
        self.run(0.3)
        self.press('fire', 0.1, 0.2)
        self.wait_for(lambda: self.peek('menu') == 0 and not self.dark(),
                      what='the house')
        self.run(0.2)

    def answer_dialog(self):
        self.press('fire', 0.1, 0.2)

    def shot(self, name):
        self.v.screenshot(os.path.join(OUT, name + '.png'))

    def stop(self):
        self.v.stop()


def check(cond, msg):
    if not cond:
        raise AssertionError(msg)


# ---------------------------------------------------------------------------
# The tests
# ---------------------------------------------------------------------------

TESTS = []


def test(fn):
    TESTS.append(fn)
    return fn


@test
def hoe_seed_water(g):
    """Hoe, sow and water one tile in front of the farmhouse."""
    T, I = g.d, g.it
    g.morning()
    g.goto('FARM_E', 3, 6, 'down')
    g.give(0, I['IT_HOE'])
    g.act()
    check(g.tile(3, 7) == T['T_SOIL'], f'hoe: tile {g.tile(3, 7)}, want SOIL')
    g.give(5, I['IT_S_PARSNIP'], 5)
    g.act()
    check(g.tile(3, 7) == T['T_SEED'], f'seed: tile {g.tile(3, 7)}, want SEED')
    check(g.count(I['IT_S_PARSNIP']) == 4, 'one seed should be gone')
    water = g.get('water')
    g.give(1, I['IT_CAN'])
    g.act()
    check(g.tile(3, 7) == T['T_SEED_WET'], f'water: tile {g.tile(3, 7)}, want SEED_WET')
    check(g.get('water') == water - 1, 'the can should hold one less')


@test
def sleep_grows(g):
    """A watered seed is a sprout the next morning, and dry again."""
    T = g.d
    g.set_farm(1, 3, 7, T['T_SEED_WET'], 1, 0)
    day = g.get('day')
    g.sleep()
    check(g.get('day') == day + 1, 'a new day')
    check(g.peek('room_id') == T['R_HOUSE'], 'wakes up in the house')
    t = g.farm(1, 3, 7)
    check(t in (T['T_SPROUT'], T['T_SPROUT_WET']), f'tile {t}, want a sprout')
    check(g.get('age', 220 + 7 * 20 + 3) == 1, 'grown one day')
    check(g.get('energy') == 100, 'energy back to full')


@test
def unwatered_does_not_grow(g):
    """A dry seed stays a seed overnight."""
    T = g.d
    g.set_farm(1, 4, 7, T['T_SEED'], 1, 0)
    g.sleep()
    check(g.get('age', 220 + 7 * 20 + 4) == 0, 'a dry seed must not grow')


@test
def harvest_and_ship(g):
    """A ripe parsnip comes out; shipped, it is paid overnight."""
    T, I = g.d, g.it
    g.morning()
    g.set_farm(1, 3, 7, T['T_PARSNIP'], 1, 4)
    g.goto('FARM_E', 3, 6, 'down')
    g.give(0, I['IT_HOE'])
    before = g.count(I['IT_PARSNIP'])
    g.act()
    check(g.count(I['IT_PARSNIP']) == before + 1, 'a parsnip in the backpack')
    check(g.tile(3, 7) in (T['T_SOIL'], T['T_SOIL_WET']), 'the tile is soil again')
    slot = [g.get('inv', k) for k in range(16)].index(I['IT_PARSNIP'])
    n = g.get('cnt', slot)
    g.set('money', 500)
    g.goto('FARM_E', 10, 4, 'up')
    g.poke('sel', slot)
    g.poke('row2', slot & 8)
    g.act()
    check(g.get('ship') == 35 * n, f'ship {g.get("ship")}, want {35 * n}')
    g.sleep()
    check(g.get('money') == 500 + 35 * n, f'money {g.get("money")}, want {500 + 35 * n}')
    check(g.get('ship') == 0, 'the bin is empty again')


@test
def smith_upgrades_hoe(g):
    """Three copper bars and 300 gold make a copper hoe, which tills two tiles."""
    T, I = g.d, g.it
    g.morning()
    g.set('money', 1000)
    g.set('lvl', 0, 0)
    g.give(7, I['IT_BAR_C'], 3, select=False)
    g.goto('SMITH', 6, 5, 'up')
    g.act()
    check(g.peek('menu') == 1, 'the smith menu is open')
    for _ in range(3):
        g.press('down', 0.1, 0.3)
    g.press('fire', 0.1, 0.4)
    check(g.get('lvl', 0) == 1, f'hoe level {g.get("lvl", 0)}, want 1')
    check(g.get('money') == 700, f'money {g.get("money")}, want 700')
    check(g.count(I['IT_BAR_C']) == 0, 'the bars are used')
    g.press('menu', 0.1, 0.4)
    check(g.peek('menu') == 0, 'the menu is closed')
    g.set_farm(1, 14, 7, T['T_GRASS'])
    g.set_farm(1, 14, 8, T['T_GRASS'])
    g.goto('FARM_E', 14, 6, 'down')
    g.give(0, I['IT_HOE'])
    g.act()
    check(g.tile(14, 7) == T['T_SOIL'] and g.tile(14, 8) == T['T_SOIL'],
          f'tiles {g.tile(14, 7)} {g.tile(14, 8)}, want two SOIL')


@test
def copper_can_waters_two(g):
    T, I = g.d, g.it
    g.morning()
    g.set('lvl', 1, 1)
    g.set('water', 40)
    g.set_farm(1, 14, 7, T['T_SOIL'])
    g.set_farm(1, 14, 8, T['T_SOIL'])
    g.goto('FARM_E', 14, 6, 'down')
    g.give(1, I['IT_CAN'])
    g.act()
    check(g.tile(14, 7) == T['T_SOIL_WET'] and g.tile(14, 8) == T['T_SOIL_WET'],
          f'tiles {g.tile(14, 7)} {g.tile(14, 8)}, want two SOIL_WET')
    check(g.get('water') == 38, 'two water used')


@test
def refill_at_pond(g):
    I = g.it
    g.morning()
    g.set('water', 0)
    g.goto('FARM_W', 3, 7, 'down')         # the shore is row 8
    g.give(1, I['IT_CAN'])
    g.act()
    check(g.get('water') > 0, 'the can is full again')


@test
def sprinkler_waters_neighbours(g):
    T, I = g.d, g.it
    g.morning()
    for x, y in ((5, 8), (7, 8), (6, 9), (6, 7), (9, 8)):
        g.set_farm(1, x, y, T['T_SOIL'])
    g.set_farm(1, 6, 8, T['T_GRASS'])
    g.goto('FARM_E', 6, 7, 'down')
    g.give(6, I['IT_SPRINKLER'])
    g.act()
    check(g.tile(6, 8) == T['T_SPRINKLER'], f'tile {g.tile(6, 8)}, want SPRINKLER')
    g.sleep()
    wet = [g.farm(1, x, y) for x, y in ((5, 8), (7, 8), (6, 9), (6, 7))]
    check(all(t == T['T_SOIL_WET'] for t in wet), f'next to it: {wet}, want wet')
    if not g.get('rain'):
        # (an empty dry tile may turn back to grass overnight: not wet is all)
        check(g.farm(1, 9, 8) != T['T_SOIL_WET'], 'further away stays dry')


@test
def axe_fells_tree(g):
    T, I = g.d, g.it
    g.morning()
    g.set_farm(1, 12, 7, T['T_TREE'])
    g.goto('FARM_E', 12, 6, 'down')
    g.give(2, I['IT_AXE'])
    wood = g.count(I['IT_WOOD'])
    for _ in range(5):
        g.act()
    check(g.tile(12, 7) == T['T_STUMP'], f'tile {g.tile(12, 7)}, want STUMP')
    check(g.count(I['IT_WOOD']) == wood + 5, 'five wood')


@test
def wrong_season_refused(g):
    T, I = g.d, g.it
    g.morning()
    g.set('season', 0)
    g.set_farm(1, 3, 7, T['T_SOIL'])
    g.goto('FARM_E', 3, 6, 'down')
    g.give(5, I['IT_S_MELON'], 3)
    g.act()
    check(g.tile(3, 7) == T['T_SOIL'], 'a summer seed must not go in in spring')
    check(g.count(I['IT_S_MELON']) == 3, 'the seed stays in the bag')


@test
def season_change_kills_crops(g):
    T = g.d
    g.set('day', 27)
    g.set('season', 0)
    g.set_farm(1, 3, 7, T['T_SEED_WET'], 1, 0)
    g.sleep()
    check(g.get('season') == 1 and g.get('day') == 0, 'first day of summer')
    check(g.get('crop', 220 + 7 * 20 + 3) & 0x80, 'the parsnip has withered')
    check(g.farm(1, 3, 7) in (T['T_DEAD'], T['T_DEAD_WET']), 'and looks it')
    g.set('season', 0)


@test
def store_buys_and_sells(g):
    I = g.it
    g.morning()
    g.set('season', 0)
    g.set('money', 200)
    g.goto('STORE', 6, 5, 'up')
    g.act()
    check(g.peek('menu') == 1, 'the store menu is open')
    seeds = g.count(I['IT_S_PARSNIP'])
    g.press('fire', 0.1, 0.4)
    check(g.get('money') == 180, f'money {g.get("money")}, want 180')
    check(g.count(I['IT_S_PARSNIP']) == seeds + 1, 'one packet more')
    g.press('menu', 0.1, 0.4)


@test
def joystick_only(g):
    """Everything with one button: fire+right the next item, fire+up the
    backpack and out of it again, and a question answered with left/right."""
    g.morning()
    g.goto('HOUSE', 5, 4, 'down')
    g.settle()
    g.poke('sel', 0)
    g.poke('row2', 0)
    g.keys('fire')
    g.run(0.1)
    g.keys('fire', 'right')                 # held: right is the next item
    g.run(0.1)
    g.keys()
    g.run(0.2)
    check(g.peek('sel') == 1, f'slot {g.peek("sel")} after fire+right, want 1')
    check(g.peek('menu') == 0, 'fire+right must not open anything')
    g.keys('fire')
    g.run(0.1)
    g.keys('fire', 'up')                    # the backpack
    g.run(0.1)
    g.keys()
    g.run(0.3)
    check(g.peek('menu') == 1, 'fire+up did not open the backpack')
    g.keys('fire')
    g.run(0.1)
    g.keys('fire', 'up')                    # and out again
    g.run(0.1)
    g.keys()
    g.run(0.5)
    check(g.peek('menu') == 0, 'fire+up did not close the backpack')
    # the bed: "no" chosen with the stick, then fire
    g.goto('HOUSE', 5, 4, 'left')
    g.settle()
    day = g.get('day')
    g.act()
    g.press('right', 0.1, 0.2)              # "no"
    g.press('fire', 0.1, 0.5)
    check(g.get('day') == day and not g.dark(), 'answered "no" and slept anyway')


@test
def blinking_ends_outside_the_mine(g):
    """Hurt in the mine and up the ladder: the blinking still ends (it
    used to stop counting outside the mine, the farmer invisible)."""
    g.morning()
    g.goto('HOUSE', 5, 4, 'down')
    g.settle()
    g.poke('hurt', 60)
    g.run(1.6)
    check(g.peek('hurt') == 0, f'hurt still {g.peek("hurt")} in the house')


@test
def menu_takes_short_presses(g):
    """A quick tap right after the menu opens must not get lost."""
    I = g.it
    g.morning()
    g.set('season', 0)
    g.set('money', 200)
    g.goto('STORE', 6, 5, 'up')
    g.keys('fire')
    g.run(0.1)
    g.keys()
    g.run(0.02)                            # the menu is being drawn now
    g.press('down', 0.04, 0.1)
    g.press('fire', 0.04, 0.4)
    check(g.get('money') == 120, f'money {g.get("money")}: the tap on down got lost '
                                 f'(parsnip seeds bought instead of cauliflower)')
    g.press('menu', 0.1, 0.4)


@test
def gift_and_talk(g):
    I = g.it
    g.morning()
    g.set('day', 0)
    g.set('friend', 0, 0)
    g.set('gifted', 0)
    g.set('talked', 0)
    g.goto('TOWN', 6, 9, 'up')
    g.poke('nwalk', 0, 0, 0)               # Lena stays where she is
    g.poke('nt', 255, 255, 255)
    check(g.peek('on') == 1, 'Lena is in the village')
    g.give(6, I['IT_MELON'], 2)
    g.act()
    g.answer_dialog()
    check(g.get('friend', 0) == 45, f'friendship {g.get("friend", 0)}, want 45 (loved)')
    check(g.count(I['IT_MELON']) == 1, 'the melon is given away')
    g.act()                                # second time: talk, no present
    g.answer_dialog()
    check(g.get('friend', 0) == 50, f'friendship {g.get("friend", 0)}, want 50 (+5 talk)')
    check(g.count(I['IT_MELON']) == 1, 'only one present a day')


@test
def villagers_at_home(g):
    g.morning(20)
    g.goto('LENA_HOUSE', 9, 7)
    check(g.peek('on', 3)[0] == 1, 'Lena is at home in the evening')
    g.goto('TOWN_N', 15, 5, 'up')
    g.set('hour', 23)
    g.keys('up')
    g.run(1.0)
    g.keys()
    check(g.peek('room_id') == g.d['R_TOWN_N'], 'the door stays shut at night')


@test
def notice_board(g):
    I = g.it
    g.morning()
    g.set('quest_item', I['IT_WOOD'])
    g.set('quest_n', 3)
    g.set('quest_done', 0)
    g.set('money', 100)
    g.give(9, I['IT_WOOD'], 5, select=False)
    wood = g.count(I['IT_WOOD'])
    g.goto('TOWN_N', 3, 7, 'up')
    g.act()
    check(g.peek('menu') == 1, 'the board is open')
    g.press('fire', 0.1, 0.4)
    check(g.get('quest_done') == 1, 'the request is done')
    check(g.count(I['IT_WOOD']) == wood - 3, 'three wood handed over')
    check(g.get('money') == 100 + 2 * 3 * 2, f'money {g.get("money")}, want 112')
    g.press('menu', 0.1, 0.4)


@test
def mine_rock_and_ladder(g):
    T, I = g.d, g.it
    g.morning()
    g.goto('MINE_B', 9, 9, 'up', floor=1)
    room = g.v.mem(g.addr('room'), 220)
    floors = (T['M_FLOOR'], T['M_FLOOR2'])
    rocks = (T['M_ROCK'], T['M_ROCK2'], T['M_COPPER'])
    best = None
    for y in range(1, 9):
        for x in range(1, 19):
            if room[y * 20 + x] in rocks and room[(y + 1) * 20 + x] in floors:
                d = abs(x - 9) + abs(y - 9)
                if best is None or d < best[0]:
                    best = (d, x, y)
    check(best, 'a rock with floor below it')
    _, x, y = best
    g.poke('px', x * 8)                     # step there without a new floor
    g.poke('py', (y + 1) * 16 - 2)
    g.poke('pdir', DIRS['up'])
    g.give(3, I['IT_PICK'])
    stone = g.count(I['IT_STONE']) + g.count(I['IT_ORE_C'])
    for _ in range(4):
        g.set('hp', 100)
        g.act()
        if g.tile(x, y) in floors + (T['M_LADDER'],):
            break
    check(g.tile(x, y) in floors + (T['M_LADDER'],), 'the rock is broken')
    check(g.count(I['IT_STONE']) + g.count(I['IT_ORE_C']) > stone, 'stone or ore')


@test
def lift(g):
    g.morning()
    g.set('deepest', 10)
    g.goto('MINE_TOP', 9, 3, 'up')
    g.act()
    check(g.peek('menu') == 1, 'the lift menu is open')
    g.press('down', 0.1, 0.3)
    g.press('down', 0.1, 0.3)
    g.press('fire', 0.1, 0.2)
    g.wait_for(lambda: g.peek('floor_no') == 10 and not g.dark(), what='floor 10')
    check(g.peek('menu') == 0, 'menu closed')


@test
def faint_in_mine(g):
    g.morning()
    g.set('money', 1000)
    g.goto('MINE_A', 9, 9, floor=3)
    g.set('hp', 0)
    g.run(0.3)
    g.answer_dialog()                       # "you black out"
    g.morning_page()
    check(g.peek('room_id') == g.d['R_HOUSE'], 'wakes up at home')
    check(g.get('money') == 900, f'money {g.get("money")}, want 900')
    check(g.peek('floor_no') == 0, 'out of the mine')


@test
def pass_out_at_two(g):
    g.morning()
    g.set('money', 1000)
    g.goto('FARM_E', 7, 5)
    g.set('hour', 25)
    g.set('minute', 50)
    g.poke('tick_frames', 245, 0)
    g.run(0.5)
    g.answer_dialog()                       # "it is 2 am"
    g.morning_page()
    check(g.get('money') == 900, f'money {g.get("money")}, want 900')
    check(g.get('energy') == 50, f'energy {g.get("energy")}, want 50')
    check(g.get('hour') == 6, 'six in the morning')


@test
def music_per_room(g):
    """The farm tune outside and at home, the mine tune below ground."""
    g.morning()
    g.goto('FARM_E', 7, 5)
    check(g.peek('music') == g.d['SONG_FARM'], 'the farm tune on the farm')
    g.goto('MINE_A', 9, 9, floor=2)
    check(g.peek('music') == g.d['SONG_MINE'], 'the mine tune in the mine')
    sounding = 0
    for _ in range(10):
        g.run(0.1)
        sounding |= g.v.mem(0xFF11, 1)[0]
    check(sounding & 0x30, 'a voice is sounding')
    g.goto('FARM_E', 7, 5)


@test
def effect_keeps_tune(g):
    """A sound effect takes voice 2 only: the tune on voice 1 plays on."""
    T, I = g.d, g.it
    g.morning()
    g.goto('FARM_E', 12, 9, 'up')
    g.give(0, I['IT_HOE'])
    both = 0
    for _ in range(12):
        g.set_farm(1, 12, 8, T['T_GRASS'])
        g.v.poke(g.addr('room') + 8 * 20 + 12, [T['T_GRASS']])
        g.set('energy', 100)
        g.wait_for(lambda: g.v.mem(0xFF11, 1)[0] & 0x10, 20, 'the tune')
        g.keys('fire')
        g.run(0.06)
        g.keys()
        for _ in range(4):
            g.run(0.02)
            r = g.v.mem(0xFF11, 1)[0]
            if g.peek('snd_time') and r & 0x40 and r & 0x10:
                both += 1
        if both >= 3:
            break
    check(both >= 3, 'no moment with the effect on voice 2 and the tune on voice 1')


@test
def year_end_score(g):
    """The night after the last day of winter: the reckoning, then the title."""
    g.morning()
    g.set('season', 3)
    g.set('day', 13)
    g.set('ship', 0)
    g.set('earned', 12340)                 # 1234 points
    for k, f in enumerate((100, 50, 250)):  # 2 + 1 + 5 hearts: 800
        g.set('friend', f, k)
    g.set('deepest', 12)                   # 600
    for k, l in enumerate((1, 1, 0, 2, 0)):  # 4 upgrades: 400
        g.set('lvl', l, k)
    g.set('quests', 2)                     # 400
    g.set('shipped', 0b000111)             # 3 kinds: 450
    g.goto('HOUSE', 5, 4, 'left')
    g.act()
    g.press('fire', 0.1, 0.2)              # yes, to bed
    g.wait_for(lambda: g.peek('game_over') == 1 or
               (g.peek('menu') == 1 and g.v.mem(g.addr('score'), 4) != [0, 0, 0, 0]),
               30, 'the reckoning')
    g.run(0.5)
    sc = sum(b << (8 * k) for k, b in enumerate(g.v.mem(g.addr('score'), 4)))
    g.shot('year_end')
    check(sc == 3884, f'score {sc}, want 3884')
    g.press('fire', 0.1, 0.5)              # to the title
    g.press('fire', 0.1, 0.1)              # a new game
    g.settle()
    check(g.get('season') == 0 and g.get('day') == 0 and g.get('money') == 500,
          'a new game after the title')


@test
def save_and_continue(g):
    """What the last night saved comes back with 'continue'."""
    g.sleep()
    want = {f: g.get(f) for f in ('day', 'season', 'money', 'energy')}
    farm = g.v.mem(g.G + g.fields['farm'][0], 512)
    g.run(2)
    # VICE keeps the drive's current track and writes it into the image
    # only when the head moves on or the disk is taken out: out with it
    g.v.cmd('detach 8')
    g.stop()
    g.v = Vice(os.path.join(ROOT, 'build', 'stardew.d64'), OUT)
    g.start(cont=True)
    for f, v in want.items():
        check(g.get(f) == v, f'{f} {g.get(f)}, saved {v}')
    check(g.v.mem(g.G + g.fields['farm'][0], 512) == farm, 'the farm as it was')


# ---------------------------------------------------------------------------

def main():
    args = [a for a in sys.argv[1:] if not a.startswith('-')]
    if '-l' in sys.argv:
        for t in TESTS:
            print(f'{t.__name__:28} {(t.__doc__ or "").strip()}')
        return 0
    tests = [t for t in TESTS if not args or any(a in t.__name__ for a in args)]
    os.makedirs(OUT, exist_ok=True)
    g = Game()
    failed = []
    t0 = time.time()
    try:
        g.start()
        for t in tests:
            t1 = time.time()
            try:
                t(g)
                print(f'PASS  {t.__name__}  ({time.time() - t1:.0f} s)', flush=True)
            except AssertionError as e:
                failed.append(t.__name__)
                print(f'FAIL  {t.__name__}: {e}', flush=True)
                g.shot(t.__name__)
            except Exception:
                failed.append(t.__name__)
                print(f'ERROR {t.__name__}:', flush=True)
                traceback.print_exc()
                try:
                    g.shot(t.__name__)
                except Exception:
                    pass
            # a test that left a menu or a conversation open should not
            # take the next one with it
            try:
                if g.peek('menu'):
                    g.press('menu', 0.1, 0.3)
            except Exception:
                pass
    finally:
        g.stop()
    print(f'\n{len(tests) - len(failed)} of {len(tests)} passed in {time.time() - t0:.0f} s')
    if failed:
        print('failed: ' + ', '.join(failed) + f'  (screenshots in {OUT})')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
