#!/usr/bin/env python3
"""The way back from a match, and the league, from the disk in VICE.

    tests/league.py [drive] [what]

drive: 1541 (the fast loader, the default) or 1551 (the KERNAL's way).
what:  back    a match to its full time, fire: the title again, the
               choices as they were
       league  a new league (LEAGUE), its page; its first match played to
               full time (the score poked); the page again - its result,
               the computer's of the matchday, the table; saved; back to
               the title (CONTINUE)
       saved   a league saved on the disk: the boot loads it, the title
               offers CONTINUE, its page
       two     two players: each one's match against the computer, then
               (a league saved before its last matchday) theirs, the end
       ask     LEAGUE with a league going on: the question - kept, then
               a new one
       all     all of them (the default)

The match is not played out: its minute is poked to 89. The joystick is
the engine's dbg_joy. Screens go to ~/.cache/simple-soccer/league-*.png.
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vice import Vice  # noqa: E402
from shot import labels  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
D64 = os.path.join(HERE, '..', 'build', 'simple-soccer.d64')
CACHE = os.path.expanduser('~/.cache/simple-soccer')
FIRE, UP, DOWN = 0x10, 0x01, 0x02
K_VARS, K_CH, L_BLOCK = 0xFCE0, 0xFCE7, 0xFFC8

lab = labels()


def ram(v, addr, n):
    """RAM, not the ROM over it"""
    v.cmd('bank ram')
    out = v.mem(addr, n)
    v.cmd('bank cpu')
    return out


def screen(v, base=0x0C00):
    """the text screen (the ROM's screen codes) as lines"""
    codes = v.mem(base, 1000)
    lines = []
    for r in range(25):
        s = ''
        for c in codes[r * 40:r * 40 + 40]:
            c &= 0x7F
            s += chr(c + 64) if 1 <= c <= 26 else (chr(c) if 32 <= c < 64 else ' ' if c == 0 else '?')
        lines.append(s.rstrip())
    return lines


def wait(v, test, what, seconds=120):
    t = time.time()
    while time.time() - t < seconds:
        if test():
            return
        v.run_for(0.2)
    v.screenshot(os.path.join(CACHE, 'league-stuck.png'))
    raise RuntimeError('waited in vain: ' + what)


def at_title(v):
    return v.mem(0xFFFE, 2) == [lab['synth'], 0] and v.mem(0xFF06, 1)[0] & 0x10


def in_match(v):
    return v.mem(0xFFFE, 2)[1] != 0 and v.mem(0xFF06, 1)[0] & 0x10 and \
        v.mem(0xFF07, 1)[0] & 0x10


def press(v, bits=FIRE, hold=0.02):
    v.poke(lab['dbg_joy'], [bits])
    v.run_for(hold)
    v.poke(lab['dbg_joy'], [0])
    v.run_for(0.3)


def full_time(v, goals=None):
    """the match to its 89th minute, the score as given; then till full
    time"""
    wait(v, lambda: v.mem(lab['game_min'], 1)[0] >= 1 or True, 'match')
    if goals:
        v.poke(lab['score'], goals)
    v.poke(lab['game_min'], [89])
    for _ in range(100):        # (the kick-off: the stick)
        if v.mem(lab['full'], 1)[0] == 1:
            break
        v.poke(lab['dbg_joy'], [UP | FIRE])
        v.run_for(0.02)
        v.poke(lab['dbg_joy'], [0])
        v.run_for(0.1)
    print('full time', v.mem(lab['full'], 1), 'minute', v.mem(lab['game_min'], 1),
          'score', v.mem(lab['score'], 2))
    assert v.mem(lab['full'], 1)[0] == 1
    if goals:
        v.poke(lab['score'], goals)
    v.run_for(1)                # (the result shown 2 seconds at least)
    assert v.mem(lab['full'], 1)[0] == 1, 'gone on from full time'


def page(v, name):
    lines = screen(v)
    print('\n'.join(lines))
    v.screenshot(os.path.join(CACHE, f'league-{name}.png'))
    return lines


def on_page(v):
    """cup.s's page: its menu drawn, the screen at $0C00"""
    return v.mem(0xFF14, 1)[0] == 0x08 and any('NEXT MATCH' in l or 'TITLE' in l or 'LEAGUE' in l
                                               for l in screen(v)[23:25])


def back(v):
    wait(v, lambda: at_title(v), 'the title')
    v.run_for(1)
    v.screenshot(os.path.join(CACHE, 'league-title1.png'))
    print('choices', ram(v, K_CH, 7))
    v.poke(K_CH, [1, 0, 0, 5, 9, 2, 3])     # 5 minutes, Canada - Croatia
    press(v)                                # (fire: let go of)
    wait(v, lambda: in_match(v), 'the match', 60)
    print('match: teams', ram(v, K_CH + 3, 2), 'min_frames', v.mem(lab['min_frames'], 1))
    full_time(v)
    press(v)
    t = time.time()
    wait(v, lambda: at_title(v), 'the title again', 180)
    print(f'back at the title after {time.time() - t:.1f} s (warp)')
    v.run_for(1)
    print('choices', ram(v, K_CH, 7))
    assert ram(v, K_CH, 7)[:5] == [1, 0, 0, 5, 9], 'the choices lost'
    v.screenshot(os.path.join(CACHE, 'league-title2.png'))


def league(v):
    wait(v, lambda: at_title(v), 'the title')
    v.run_for(1)
    v.poke(K_CH, [0, 0, 2, 14, 3, 0, 0])    # LEAGUE: Germany
    press(v)
    wait(v, lambda: on_page(v), 'the page', 180)
    v.run_for(2)
    lines = page(v, 'new')
    lg = ram(v, L_BLOCK, 42)
    print('league', lg)
    assert lg[1] == 1 and sum(lg) & 255 == 0
    press(v)                                # PLAY THE NEXT MATCH
    wait(v, lambda: in_match(v), 'the league match', 60)
    print('match: teams', ram(v, K_CH + 3, 2), 'two', ram(v, K_CH + 1, 1))
    full_time(v, [3, 1])
    press(v)
    wait(v, lambda: on_page(v), 'the page after', 180)
    v.run_for(2)
    lines = page(v, 'played')
    lg = ram(v, L_BLOCK, 42)
    print('league', lg)
    assert sum(lg) & 255 == 0
    assert any('SAVED' in l for l in lines), 'not saved'
    press(v, DOWN)                          # BACK TO THE TITLE
    press(v)
    wait(v, lambda: at_title(v), 'the title after the page', 180)
    v.run_for(1)
    print('choices', ram(v, K_CH, 7))
    v.screenshot(os.path.join(CACHE, 'league-title3.png'))


SECTORS = [0] + [21] * 17 + [19] * 7 + [18] * 6 + [17] * 5


def d64_put(image, name, data):
    """data into the file's first sector, after its load address (as the
    fast loader saves: into the file as it is)"""
    d = bytearray(open(image, 'rb').read())
    off = lambda t, s: (sum(SECTORS[1:t]) + s) * 256
    t, s = 18, 1
    while t:
        sec = d[off(t, s):off(t, s) + 256]
        for e in range(8):
            ent = sec[e * 32:e * 32 + 32]
            if ent[2] and ent[5:21].rstrip(b'\xa0') == name.upper().encode():
                o = off(ent[3], ent[4]) + 4
                d[o:o + len(data)] = bytes(data)
                return d
        t, s = sec[0], sec[1]
    raise KeyError(name)


def saved(drive):
    """a league saved on the disk (matchday 1 played): the boot loads it,
    the title offers CONTINUE, the page shows it"""
    lg = [0, 1, 0, 0, 0, 0, 14, 10, 5, 2, 1, 0, 32, 16, 0x13, 0x21, 0x00, 0x03] + [255] * 24
    lg[0] = -sum(lg[1:]) & 255
    img = os.path.join(CACHE, 'league-saved.d64')
    open(img, 'wb').write(d64_put(D64, 'league', lg))
    v = Vice(img, CACHE, drive=drive, title=True)
    try:
        wait(v, lambda: at_title(v), 'the title')
        v.run_for(1)
        assert ram(v, L_BLOCK, 42) == lg, 'the league not loaded'
        print('modes up to', v.mem(lab['t_modes'], 1))
        assert v.mem(lab['t_modes'], 1)[0] == 3, 'no CONTINUE'
        v.poke(K_CH + 2, [3])
        press(v)
        wait(v, lambda: on_page(v), 'the page', 180)
        v.run_for(2)
        lines = page(v, 'continue')
        assert 'NEXT: BELGIUM - GERMANY' in lines[19], 'not the league saved'
    finally:
        v.stop()


def boot_with(lg, drive):
    """VICE on a copy of the disk with league lg saved on it, at the title"""
    lg = list(lg)
    lg[0] = -sum(lg[1:]) & 255
    img = os.path.join(CACHE, 'league-saved.d64')
    open(img, 'wb').write(d64_put(D64, 'league', lg))
    v = Vice(img, CACHE, drive=drive, title=True)
    wait(v, lambda: at_title(v), 'the title')
    v.run_for(1)
    return v


def play(v, goals, name):
    """from the page: the next match, its score as given, the page after"""
    press(v)
    wait(v, lambda: in_match(v), 'the league match', 60)
    ch = ram(v, K_CH, 7)
    print('match: teams', ch[3:5], 'two', ch[1], 'forms', ch[5:7])
    full_time(v, goals)
    press(v)
    wait(v, lambda: on_page(v), 'the page after', 180)
    v.run_for(2)
    return ch, page(v, name)


def two(drive):
    """two players: Germany (14) the first's, Italy (18) the second's.
    A new league: the first's match, then the second's (cyan: his team,
    one player); then the last matchday (from the disk): the two against
    each other, the league over"""
    lg = [0, 1, 1, 0, 0, 0, 14, 18, 5, 2, 1, 0, 32, 16] + [255] * 28
    v = boot_with([0] * 42, drive)
    try:
        v.poke(K_CH, [0, 1, 2, 14, 18, 1, 2])   # LEAGUE, two players
        press(v)
        wait(v, lambda: on_page(v), 'the page', 180)
        v.run_for(2)
        page(v, 'two-new')
        ch, lines = play(v, [2, 0], 'two-1')
        assert ch[1] == 0 and ch[3] == 14 and ch[5] == 1, 'the first player\'s match'
        ch, lines = play(v, [1, 1], 'two-2')
        assert ch[1] == 0 and ch[3] == 18 and ch[5] == 2, 'the second player\'s match'
        assert 'MATCHDAY 1' in lines[2]
    finally:
        v.stop()
    for m in range(24):                 # matchdays 1-6 played, all 1:0
        lg[14 + m] = 0x10
    v = boot_with(lg, drive)
    try:
        v.poke(K_CH + 2, [3])           # CONTINUE
        press(v)
        wait(v, lambda: on_page(v), 'the page', 180)
        v.run_for(2)
        page(v, 'two-last')
        ch, lines = play(v, [0, 4], 'two-over')
        assert ch[1] == 1 and ch[3:5] == [14, 18], 'the players\' match'
        assert 'WON BY' in lines[19], 'not over'
        print('league', ram(v, L_BLOCK, 42))
        assert ram(v, L_BLOCK + 1, 1) == [0], 'still on'
        press(v)                        # (the title only)
        wait(v, lambda: at_title(v), 'the title', 180)
        v.run_for(1)
        print('modes up to', v.mem(lab['t_modes'], 1), 'choices', ram(v, K_CH, 7))
        assert v.mem(lab['t_modes'], 1)[0] == 2, 'CONTINUE after the end'
    finally:
        v.stop()


def ask(drive):
    """LEAGUE chosen with a league going on: its page and the question;
    kept (fire: the first choice) - back at the title, CONTINUE, the
    league as it was; then a new one (down, fire)"""
    lg = [0, 1, 0, 0, 0, 0, 14, 10, 5, 2, 1, 0, 32, 16, 0x13, 0x21, 0x00, 0x03] + [255] * 24
    lg[0] = -sum(lg[1:]) & 255
    v = boot_with(lg, drive)
    try:
        v.poke(K_CH + 2, [2])               # LEAGUE
        press(v)
        wait(v, lambda: on_page(v), 'the question', 180)
        v.run_for(2)
        lines = page(v, 'ask')
        assert 'WOULD TAKE' in lines[19] and 'KEEP THIS LEAGUE' in lines[23], 'no question'
        press(v)                            # keep it
        wait(v, lambda: at_title(v), 'the title', 180)
        v.run_for(1)
        ch = ram(v, K_CH, 7)
        print('kept: choices', ch, 'modes', v.mem(lab['t_modes'], 1))
        assert ch[2] == 3 and ram(v, L_BLOCK, 42) == lg, 'not kept'
        v.poke(K_CH + 2, [2])               # LEAGUE again: a new one
        press(v)
        wait(v, lambda: on_page(v), 'the question', 180)
        v.run_for(1)
        press(v, DOWN)
        press(v)
        wait(v, lambda: on_page(v) and 'MATCHDAY 1' in screen(v)[2] and
             any('SAVED' in l for l in screen(v)), 'the new league', 180)
        v.run_for(1)
        page(v, 'ask-new')
        new = ram(v, L_BLOCK, 42)
        print('new', new)
        assert new[1] == 1 and new[14:] == [255] * 28, 'not a new league'
    finally:
        v.stop()


def main():
    drive = sys.argv[1] if len(sys.argv) > 1 else '1541'
    what = sys.argv[2] if len(sys.argv) > 2 else 'all'
    v = Vice(D64, CACHE, drive=drive, title=True)
    try:
        if what in ('back', 'all'):
            back(v)
        if what in ('league', 'all'):
            league(v)
    finally:
        v.stop()
    if what in ('saved', 'all'):
        saved(drive)
    if what in ('two', 'all'):
        two(drive)
    if what in ('ask', 'all'):
        ask(drive)
    print('ok')


if __name__ == '__main__':
    main()
