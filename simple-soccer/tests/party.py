#!/usr/bin/env python3
"""The crowd at a goal (engine.s wave: la_m, la_s): a ball rolled into the
top goal in a match in VICE, then picture by picture till the kick-off -
while play.s's goal is set every other spectator is up a pixel, the odd
ones and the even ones (la_step) by turns, PARTY_STEP (8) frames each;
their colours as before the goal (Luca: the colours turned round looked
like no party - they should jump). Every second frame of the cheering
the stands taken from the screen: two pictures by turns, the same colours
in both (party-0.png, party-1.png).

    ~/.cache/simple-soccer/venv/bin/python tests/party.py

(PIL: the venv's.) A line each, OK or WRONG; the exit code counts the
wrong ones.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from keep import Scene, BALL  # noqa: E402
from shot import WORK, labels  # noqa: E402
from PIL import Image  # noqa: E402

STANDS = (0, 0, 384, 80)        # (the screenshot's top: the stands, the boards)


def stands(s, name):
    path = os.path.join(WORK, 'party-%s.png' % name)
    s.v.screenshot(path)
    return Image.open(path).convert('RGB').crop(STANDS)


def main():
    lab = labels()
    s = Scene(lab)
    out = []
    try:
        s.obj(0, 100, 700)
        s.obj(11, 560, 60)
        for i in list(range(1, 11)) + list(range(12, 22)):
            s.obj(i, 40 + 20 * (i % 11), 400)
        s.obj(BALL, 304, 70, tx=304, ty=-200, speed=1024)
        s.put('last_team', 0, 0)
        s.put('last_pl', 0, 9)
        s.v.cmd('del')
        s.v.cmd('break %04x' % lab['play_frame'])
        seen, imgs, order, turns = 0, {}, [], set()
        for f in range(400):
            s.v.cmd('x')
            if s.get('goal'):
                seen += 1
                turns.add((s.get('la_m'), s.get('la_s')))
                if 30 <= seen < 78 and seen % 2 == 0:   # (the view still by then)
                    im = stands(s, 'seq')
                    key = im.tobytes()
                    if key not in imgs:
                        imgs[key] = im
                        im.save(os.path.join(WORK, 'party-%d.png' % (len(imgs) - 1)))
                    order.append(list(imgs).index(key))
            elif seen:
                for _ in range(8):      # (a picture built since)
                    s.v.cmd('x')
                m = s.get('la_m')
                out.append((m == 0xFF, 'after the kick-off: la_m $%02X (all of a step)' % m))
                break
        if not seen:
            return print('no goal') or 1
        out.append((turns >= {(1, 0), (1, 1)}, 'la_m, la_s while cheered: %s' % sorted(turns)))
        changes = sum(1 for x, y in zip(order, order[1:]) if x != y)
        out.append((len(imgs) == 2 and changes >= 4,
                    'the stands %d ways, changed %d times in %d frames: %s' % (
                        len(imgs), changes, 2 * len(order), ''.join(map(str, order)))))
        if len(imgs) == 2:
            a, b = list(imgs.values())
            pa, pb = list(a.getdata()), list(b.getdata())
            diff = sum(1 for p, q in zip(pa, pb) if p != q)
            out.append((diff > 500, 'the two differ in %d pixels' % diff))
            out.append((set(pa) == set(pb), 'the same colours in both (none turned): %d' % len(set(pa))))
    finally:
        s.stop()
    wrong = 0
    for ok, text in out:
        wrong += not ok
        print('%-70s %s' % (text, 'OK' if ok else 'WRONG'))
    return wrong


if __name__ == '__main__':
    sys.exit(main())
