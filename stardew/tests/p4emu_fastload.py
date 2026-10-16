#!/usr/bin/env python3
"""p4emu_fastload.py - the fast loader in plus4emu, whose 1541 is a whole
one (its DOS, its 6502, the disk turning): the boot program starts it, the
game loads with it, saves with it and continues what it saved.

  - the boot's screen (build/test/fl_boot.png), the time from RUN to the
    title
  - the loader's Plus/4 half at $0600 as the boot put it, still, once the
    game has unpacked itself and runs
  - a new game, then the farm, the village, the mine: the time of each
  - a night: the morning page says "game saved", the save file on the
    disk holds the game state as it was
  - the emulator started again from that disk: "continue" brings it back

Run from stardew/ after ./build.sh."""
import os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p4emu_snow as S
from p4emu import P4emu, ROOT
from run_tests import read_game_h

OUT = os.path.join(ROOT, 'build', 'test')
SAVED = os.path.join(OUT, 'fl_saved.d64')
items, fields = read_game_h()
failed = []


def check(ok, what):
    print(('ok    ' if ok else 'FAIL  ') + what, flush=True)
    if not ok:
        failed.append(what)


def get(e, field):
    off, size, dims = fields[field]
    b = e.mem(e.sym('G') + off, size)
    return sum(x << (8 * k) for k, x in enumerate(b))


def press(e, name, hold=5, after=15):
    e.set('dbg_keys', S.K[name])
    e.frame(hold)
    e.set('dbg_keys', 0)
    e.frame(after)


def screens_say(e, text):
    """text, in screen codes, on one of the two pictures' screens"""
    codes = bytes(ord(c) - 96 if 'a' <= c <= 'z' else ord(c) for c in text)
    return codes in e.mem(0xD000, 0x1000)


def file_on_disk(d64, name):
    """a file's bytes off a .d64 (its load address too)"""
    img = open(d64, 'rb').read()
    spt = [0] + [21] * 17 + [19] * 7 + [18] * 6 + [17] * 5
    def sec(t, s):
        o = (sum(spt[1:t]) + s) * 256
        return img[o:o + 256]
    want = name.upper().encode().ljust(16, b'\xa0')
    t, s = 18, 1
    while t:
        d = sec(t, s)
        for k in range(8):
            e = d[2 + 32 * k:34 + 32 * k]
            if e[0] and e[3:19] == want:
                out, ft, fs = b'', e[1], e[2]
                while ft:
                    b = sec(ft, fs)
                    out += b[2:] if b[0] else b[2:b[1] + 1]
                    ft, fs = b[0], b[1]
                return out
        t, s = d[0], d[1]
    return None


def boot(d64):
    t0 = time.time()
    e = P4emu(d64, run='LOAD"*",8\n')        # the boot program loaded
    ran = e.frames
    print('the boot program loaded after %.1f s' % (ran / 50))
    e.lib.Plus4VM_PasteText(e.vm, b'RUN\n', -1, -1)
    e.frame(150)
    e.png(os.path.join(OUT, 'fl_boot.png'))
    n = S.title(e)
    print('title %.1f s after RUN (%.0f s here)' % ((e.frames - ran) / 50, time.time() - t0))
    return e


def main():
    os.makedirs(OUT, exist_ok=True)
    fl = open(os.path.join(ROOT, 'build', 'fastload.bin'), 'rb').read()

    e = boot(None)
    try:
        # (what it changes itself - its addresses, its variables - is $FF or
        # 0 in the file: those bytes not compared)
        now = e.mem(0x0600, len(fl))
        diff = [i for i in range(len(fl)) if now[i] != fl[i] and fl[i] not in (0, 0xFF)]
        check(not diff, 'the loader at $0600, as the boot put it%s' % (
            '' if not diff else ': differs at ' + ' '.join('$%04X' % (0x600 + i) for i in diff)))
        print('new game: %.1f s' % (S.new_game(e) / 50))
        e.frame(20)
        check(e.peek('room_id') == 2, 'in the farmhouse')
        for room, x, y, floor in (('FARM_W', 10, 5, 0), ('TOWN', 10, 6, 0),
                                  ('MINE_A', 9, 9, 23), ('FARM_W', 10, 5, 0)):
            n = S.goto(e, room, x, y, floor)
            print('%-8s %.1f s' % (room.lower(), n / 50))
            e.frame(10)
        check(e.peek('room_id') == 0, 'back on the farm')

        # a night: to bed, yes - the morning page saves
        S.goto(e, 'HOUSE', 5, 4)
        e.frame(10)
        e.set('pdir', 2)                         # facing the bed (left)
        money = get(e, 'money') + 1234           # (not what a new game has)
        e.poke(e.sym('G') + fields['money'][0], money.to_bytes(4, 'little'))
        press(e, 'fire', 5, 20)
        press(e, 'fire', 5, 10)                  # yes
        t = e.frames
        while not screens_say(e, 'game saved') and not screens_say(e, 'could not save'):
            e.frame(5)
            if e.frames - t > 50 * 120:
                break
        print('the night and the save: %.1f s' % ((e.frames - t) / 50))
        check(screens_say(e, 'game saved'), 'the morning page: "game saved."')
        day, money = get(e, 'day'), get(e, 'money')
        state = e.mem(e.sym('G'), fields_size())
    finally:
        e.stop()
    open(SAVED, 'wb').write(open(e.d64, 'rb').read())
    on_disk = file_on_disk(SAVED, 'save')
    check(on_disk is not None and on_disk[2:] == state,
          'the save file holds the game state (%s bytes)' % (len(on_disk) - 2 if on_disk else '-'))

    # again from that disk: continue
    e = boot(SAVED)
    try:
        press(e, 'down', 5, 10)
        press(e, 'fire', 5, 0)
        S.wait_room(e)
        e.frame(20)
        check(get(e, 'money') == money and get(e, 'day') == day,
              'continued: money %d day %d (saved %d, %d)' % (get(e, 'money'), get(e, 'day'), money, day))
    finally:
        e.stop()
    print('%d failed' % len(failed) if failed else 'all passed')
    return 1 if failed else 0


def fields_size():
    lbl = open(os.path.join(ROOT, 'build', 'stardew.lbl')).read().split()
    return int(lbl[lbl.index('.__SAVEDATA_SIZE__') - 1], 16)


if __name__ == '__main__':
    sys.exit(main())
