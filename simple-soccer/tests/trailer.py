#!/usr/bin/env python3
"""A trailer of the moves in training: build/simple-soccer-trailer.mp4.

    tests/trailer.py            (from the scenes tests/moves.py recorded)
    tests/trailer.py --boot     (the loading and the title recorded first)
    tests/trailer.py --league   (the league recorded first)
    tests/trailer.py --crawl    (its opening alone, to look at)

It opens as a film of a galaxy far away does: a line in blue on black,
the name going off into the stars, a text crawling up into the distance.
Then the end of the loading - the football turning - going on into the
title, as the disk does it, and the title's second page with the
formations chosen there (--boot records that, from the disk in Yape:
~/.cache/simple-soccer/moves/boot). Then the title once more, TRAINING
chosen and the kick-off, and moves.py's scenes, each played and (the
shorter ones) played again at half speed, with its caption below the
pitch; then the league - LEAGUE chosen on the title, its first page,
the end of a match and the matchday's results and table after it, and
the last matchday's, the league won, and its winner's page (--league
records that, also from
the disk in Yape: WORK/league); the title once more at the end. The parts wiped into one
another with a soft edge, old-school as in those films - across, an
iris, round like a clock hand; the captions only while no wipe runs.
Last the credits,
crawling off into the stars as the opening's text does.

The scenes are the pictures and the sound moves.py keeps in
~/.cache/simple-soccer/moves/<name>; each part is made from them at the
machine's size (<name>.seq in trailer/ there), its captions in the
title's lettering put into its pictures. The parts are wiped into one
another picture by picture, at the machine's size (body.mkv), then
enlarged three times with sharp pixels (the wipes' edges too) behind
the opening. Nothing is held in memory for long: one ffmpeg graph with
every caption laid over the video held their pictures by the gigabyte.
Under it all the title's song (tools/mkmusic.py --wav), one track from
the first second to the last, lower while the game's own sound plays.
"""
import array
import glob
import math
import os
import random
import subprocess
import sys
import time
import wave

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import moves  # noqa: E402
from yape import Yape, SHOT, host  # noqa: E402
from moves import WORK, SCENES, FIRST, WAIT, TITLE, HERE, YELLOW_CAP, WHITE_CAP  # noqa: E402
from PIL import Image, ImageChops, ImageDraw, ImageFilter  # noqa: E402

OUT = os.path.join(HERE, 'build', 'simple-soccer-trailer.mp4')
T = os.path.join(WORK, 'trailer')
W, H = 384, 288                 # the machine's picture
Z = 3                           # enlarged
FPS = 50
RATE = 48000
X = 0.6                         # seconds from one part to the next
CRAWL_X = 1.0                   # the crawl's fade into the title
SCENE_MIN = 8.0                 # seconds a scene is on, at least (the captions read)
TAIL = 30                       # frames after a scene's move, at least
SONG = 0.30                     # the song's level: as loud as the Plus/4's own
BED = 0.50                      # under the game's sound (1: alone)
# how one part goes into the next: old-school wipes as in those films
# (and as MEGA65 Smaragd Dash's trailer has them, in its order), into
# the end round like a clock hand - their edge soft, EDGE pixels at the
# machine's size (a hard one between two pictures of the pitch read as a
# fault: grass on both sides, the lines not meeting)
WIPES = ['left', 'radial', 'open', 'right', 'down', 'radial',
         'left', 'close', 'right', 'up', 'open']
END_WIPE = 'radial'
EDGE = 4

# the scenes' replays, frames from the scene's first (what moves.py's
# piece() starts with) - where the default (the move's last frames) does
# not show the moment
REPLAY = {}
BOOT_LOAD = 8.0                 # seconds of the loading screen shown
BOOT_TITLE = 7.0                # of the title after it, before its second page is chosen
BOOT_CAPS = [('THE LOADER - A FAST LOADER WITH MUSIC',
              'THE TITLE SONG PLAYS ALL THROUGH THE LOADING'),
             ('THE TITLE - 35 NATIONAL TEAMS',
              'ONE OR TWO PLAYERS - A MATCH OR TRAINING'),
             ('TEAM SETTINGS - A FORMATION EACH SIDE',
              '4-4-2 TO 4-3-3 - ATTACK DEFEND OR RANDOM')]
END = ('SIMPLE SOCCER FOR THE COMMODORE PLUS/4', 'GITHUB.COM/Q4Z1/PLUS4')
# the league (--league records it, from a copy of the disk in Yape:
# WORK/league): its eight teams, Germany the player's; the results the
# disk is given (L_BLOCK) - after three matchdays, and before the last,
# where Germany beat Brazil, a point ahead, to win it (seed 25 of a
# search, its home and away goals); the match's score poked at its end
LEAGUE_TEAMS = [14, 3, 18, 12, 22, 31, 13, 0]   # (title.s teams)
LEAGUE_RES = [(2, 0), (1, 1), (3, 0), (1, 0), (1, 2), (0, 0), (1, 4), (2, 1),
              (4, 2), (4, 3), (4, 0), (0, 2), (2, 2), (1, 1), (3, 0), (0, 2),
              (0, 4), (1, 0), (4, 1), (0, 1), (2, 4), (3, 2), (3, 4), (3, 3),
              None, (1, 1), (0, 2), (2, 3)]
LEAGUE_SCORE = ([2, 1], [3, 0])         # France 1:2 Germany, Germany 3:0 Brazil
LEAGUE_CAPS = [('THE LEAGUE - EIGHT TEAMS',
                'EACH AGAINST EACH - ONE OR TWO PLAYERS'),
               ('AFTER EACH MATCH - THE MATCHDAY',
                'AND THE TABLE - SAVED ON THE DISK'),
               ('THE LAST MATCHDAY',
                'FIRST AGAINST SECOND - FOR THE LEAGUE'),
               ('THE WINNER',
                'A PAGE OF ITS OWN - AFTER EVERY MATCH TOO')]
L_BLOCK, L_LEN, K_CH = 0xFFC8, 42, 0xFCE7      # (game.inc)
END_FRAME = 150                 # the title's picture the end holds (MODE: TRAINING)


# ---- the lettering --------------------------------------------------------------

def text_mask(lines, scale, width=None, gap=2):
    """lines of the title's lettering, white on black ('L'), each line
    in the middle, scale times the machine's pixels"""
    width = width or max(len(l) for l in lines) * 8
    img = Image.new('L', (width, len(lines) * (8 + gap)), 0)
    for r, line in enumerate(lines):
        for x, y in rows(line, width):
            img.putpixel((x, r * (8 + gap) + y), 255)
    return img.resize((img.width * scale, img.height * scale), Image.NEAREST)


def rows(text, width):
    pts = []
    x0 = (width - len(text) * 8) // 2
    for k, ch in enumerate(text):
        c = ord(ch) - 32
        if ch != ' ' and not any(moves.FONT[c * 8:c * 8 + 8]):
            raise ValueError('no %r in the title font' % ch)
        for r in range(8):
            for b in range(8):
                if moves.FONT[c * 8 + r] & (0x80 >> b):
                    pts.append((x0 + k * 8 + b, r))
    return pts


def caption_img(lines):
    """a caption at the machine's size: the first line yellow, the second
    white, a shadow below each, the width of the picture"""
    img = Image.new('RGBA', (W, 28), (0, 0, 0, 0))
    for r, (line, colour) in enumerate(zip(lines, (YELLOW_CAP, WHITE_CAP))):
        m = text_mask([line], 1, W, gap=0)
        img.paste((16, 16, 16, 255), (1, r * 14 + 1), m)
        img.paste(colour + (255,), (0, r * 14), m)
    return img


def label_img(text):
    m = text_mask([text], 1, gap=0)
    img = Image.new('RGBA', m.size, (0, 0, 0, 0))
    img.paste(YELLOW_CAP + (255,), (0, 0), m)
    return img


# ---- the opening ----------------------------------------------------------------

CRAWL = ['EPISODE 264', 'THE MOVES', '',
         'THE COMMODORE PLUS/4 HAS', 'WAITED A LONG TIME FOR A', 'GAME OF FOOTBALL.', '',
         'NOW SIMPLE SOCCER TAKES', 'THE PITCH: PLAYED AS THE', 'AMIGA CLASSIC IS PLAYED',
         'AND DRAWN AS THE C64 DRAWS', 'IT - ALL IN 6502 ASSEMBLY.', '',
         'ON THE TRAINING GROUND A', 'KEEPER AND FOUR A SIDE', 'SHOW EVERY MOVE THE',
         'JOYSTICK CAN MAKE....']
# the closing crawl, as the opening's
CREDITS = ['SIMPLE SOCCER', 'THE CREDITS', '',
           'BY Q4Z1 2026 (& CLAUDE)', '',
           'AFTER TWO GREAT GAMES', '',
           'SENSIBLE SOCCER - AMIGA', 'BY SENSIBLE SOFTWARE', '',
           'ARLASOFT SOCCER - C64', 'BY ARLASOFT', '',
           'TESTED ON REAL HARDWARE', 'BY LUCA', '',
           'THE MUSIC PLAYER FROM', 'INTERNATIONAL KARATE BY', 'CSABO - ATI - SIZ - TLC', '',
           'THE FAST LOADER AFTER', 'SIZ AND SIZIOLIB', '',
           'THANKS TO PLUS4WORLD', 'AND THE WHOLE PLUS/4 SCENE', '', '',
           'SEE YOU ON THE PITCH....']
CREDITS_START, CREDITS_HOLD = 0.6, 3.5  # its crawl from; the last line held (seconds)
BLUE = (0x4B, 0xD5, 0xEE)
CRAWL_YELLOW = (0xE5, 0xB1, 0x3A)
# when (seconds)
A_IN, A_OUT, A_END = 0.5, 4.0, 5.0      # the blue line
LOGO, LOGO_END = 5.6, 11.0              # the name going off
CR_START, CR_SPEED = 6.4, 46.0          # the crawl: texture rows a second
CRAWL_S = 31.0                          # the opening in all (the fade into the title's in it)


def solve(m, v):
    """m x = v, Gauss (8 unknowns)"""
    n = len(v)
    a = [row[:] + [v[i]] for i, row in enumerate(m)]
    for c in range(n):
        p = max(range(c, n), key=lambda r: abs(a[r][c]))
        a[c], a[p] = a[p], a[c]
        for r in range(n):
            if r != c:
                f = a[r][c] / a[c][c]
                a[r] = [x - f * y for x, y in zip(a[r], a[c])]
    return [a[i][n] / a[i][i] for i in range(n)]


def homography(pairs):
    """PIL's PERSPECTIVE data: the picture's (x, y) to the texture's (u, v)"""
    m, v = [], []
    for (x, y), (u, w) in pairs:
        m.append([x, y, 1, 0, 0, 0, -u * x, -u * y]); v.append(u)
        m.append([0, 0, 0, x, y, 1, -w * x, -w * y]); v.append(w)
    return solve(m, v)


def logo_image():
    """the title's name, as the title draws it (its first picture)"""
    im = Image.open(os.path.join(WORK, 'title', 'f000.ppm')).convert('RGB')
    bg = im.getpixel((W // 2, 46))
    box = None
    for y in range(44, 70):            # (below the box's top line)
        for x in range(40, W - 40):
            if im.getpixel((x, y)) != bg:
                box = (min(box[0], x), min(box[1], y), max(box[2], x + 1), max(box[3], y + 1)) \
                    if box else (x, y, x + 1, y + 1)
    logo = im.crop(box)
    mask = Image.new('L', logo.size, 0)
    for y in range(logo.height):
        for x in range(logo.width):
            if logo.getpixel((x, y)) != bg:
                mask.putpixel((x, y), 255)
    return logo, mask


def crawl(path, text=CRAWL, opening=True):
    """the opening, enlarged as the rest: path (.mkv, lossless) - or
    (not opening) the closing: the text alone crawling off into the stars
    till its last line is near, a moment held there; its length
    (seconds)"""
    w, h = W * Z, H * Z
    rnd = random.Random(264)
    stars = Image.new('RGB', (w, h))
    d = ImageDraw.Draw(stars)
    for _ in range(420):
        x, y, g = rnd.randrange(w), rnd.randrange(h), rnd.choice((90, 140, 200, 255))
        s = rnd.choice((1, 1, 1, 2, 2, 3))
        d.rectangle((x, y, x + s - 1, y + s - 1), fill=(g, g, g))
    black = Image.new('RGB', (w, h))
    line = text_mask(['A LONG TIME AGO ON A HOME COMPUTER', 'FAR FAR AWAY....'], Z, gap=6)
    line_at = ((w - line.width) // 2, (h - line.height) // 2)
    logo, logo_mask = logo_image()
    # the crawl: its text a texture, scale 4, the plane's far end at TOP
    tex = text_mask(text, 4, 28 * 8, gap=6)
    tw, th = tex.size
    win = 1300                          # texture rows on the plane
    top, bw, topw = int(0.22 * h), 1.05 * w, 0.22 * w
    co = homography([((w / 2 - bw / 2, h), (0, win)), ((w / 2 + bw / 2, h), (tw, win)),
                     ((w / 2 + topw / 2, top), (tw, 0)), ((w / 2 - topw / 2, top), (0, 0))])
    fade = Image.new('L', (w, h), 0)    # the far end dark
    for y in range(h):
        a = max(0.0, min(1.0, (y - top) / (0.42 * h)))
        fade.paste(int(255 * a ** 0.8), (0, y, w, y + 1))
    yellow = Image.new('RGB', (w, h), CRAWL_YELLOW)
    start, secs = CR_START, CRAWL_S
    if not opening:
        # the last line's middle at 70 % of the height (large and bright
        # still, the far end dims and shrinks it): where on the plane
        # that is, and so when (the picture's y to the plane's v)
        y = 0.70 * h
        v = (co[3] * w / 2 + co[4] * y + co[5]) / (co[6] * w / 2 + co[7] * y + 1)
        last = (len(text) - 0.5) * (8 + 6) * 4
        start = CREDITS_START
        secs = start + (last - v + win) / CR_SPEED + CREDITS_HOLD
    ff = subprocess.Popen(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24',
                           '-s', '%dx%d' % (w, h), '-r', str(FPS), '-i', '-',
                           '-c:v', 'ffv1', '-pix_fmt', 'bgr0', path], stdin=subprocess.PIPE)
    for f in range(int(secs * FPS)):
        t = f / FPS
        if opening and t < A_END:
            frame = black.copy()
            a = min(1, max(0, (t - A_IN) / 0.6)) * min(1, max(0, (A_OUT - t) / 0.6))
            if a > 0:
                frame.paste(tuple(int(c * a) for c in BLUE), line_at + (line_at[0] + line.width,
                                                                       line_at[1] + line.height), line)
        else:
            frame = stars.copy()
            if opening and LOGO <= t < LOGO_END:
                # off into the distance, as fast at first as at last
                k = (t - LOGO) / (LOGO_END - LOGO)
                s = 1.9 * w / logo.width * math.exp(-4.2 * k)
                lw, lh = max(1, int(logo.width * s)), max(1, int(logo.height * s))
                big = logo.resize((lw, lh), Image.NEAREST if s >= 1 else Image.BOX)
                m = logo_mask.resize((lw, lh), Image.NEAREST if s >= 1 else Image.BOX)
                if k > 0.8:
                    m = m.point(lambda p, a=(1 - k) / 0.2: int(p * a))
                frame.paste(big, ((w - lw) // 2, (h - lh) // 2), m)
            if t >= start:
                s = min(t - start, secs - CREDITS_HOLD - start) * CR_SPEED - win
                c = co[:3] + [co[3] + s * co[6], co[4] + s * co[7], co[5] + s] + co[6:]
                m = tex.transform((w, h), Image.PERSPECTIVE, c, Image.BILINEAR)
                frame.paste(yellow, (0, 0), ImageChops.multiply(m, fade))
        ff.stdin.write(frame.tobytes())
    ff.stdin.close()
    if ff.wait():
        raise RuntimeError('ffmpeg: the crawl')
    return secs


# ---- the loading -------------------------------------------------------------

def record_boot():
    """the disk in Yape from its start: the loading screen and the title
    after it, with their sound, to WORK/boot (f0000.ppm ...); the
    title's first frame in WORK/boot/title.txt"""
    moves.clear_shots()
    y = Yape(moves.D64, series=6000, title=True,
             env=('YAPE_WAV=' + moves.WAV, 'SDL_AUDIODRIVER=dummy'))
    try:
        host('pkill', '-USR2', '-x', 'yapesdl')     # the pictures and the sound from here
        t0 = time.time()
        while time.time() - t0 < 180:               # loading: till the title is on
            time.sleep(0.5)
            if y.mem(0xfffe, 2) == [moves.labels()['synth'], 0] and y.mem(0xff06, 1)[0] == 0x1b:
                break
        print('title after %d s' % (time.time() - t0))
        time.sleep(BOOT_TITLE - 1.8)

        def stick(how, wait=0.45):
            y.poke(moves.lab['dbg_joy'], [moves.bits(how)])
            time.sleep(0.15)
            y.poke(moves.lab['dbg_joy'], [0])
            time.sleep(wait)
        for how in ('down', 'down', 'down'):        # to TEAM SETTINGS
            stick(how)
        page2 = len(pictures())
        stick('right', 1.0)                         # the second page
        stick('up', 0.5)                            # AWAY FORMATION
        for wait in (0.35, 0.35, 0.6):              # 5-4-1, 4-5-1, 5-3-2
            stick('right', wait)
        stick('up', 0.5)                            # HOME FORMATION
        for wait in (0.35, 0.35, 0.35, 0.35, 0.35, 1.2):     # ... 4-3-3, ATTACK
            stick('right', wait)
        time.sleep(0.5)
    finally:
        y.stop()
    d = os.path.join(WORK, 'boot')
    subprocess.run(['rm', '-rf', d])
    os.makedirs(d)
    shots = pictures()
    end = len(shots)
    for f in shots:
        os.rename(f, os.path.join(d, 'f%04d.ppm' % int(f.rsplit('.', 1)[1])))
    os.rename(moves.WAV, os.path.join(d, 'sound.raw'))
    # the title: the first picture with the title's border all along it
    every = frames_of('boot')
    border = Image.open(os.path.join(WORK, 'title', 'f000.ppm')).getpixel((4, 4))
    lo, hi = 0, len(every) - 1
    is_title = lambda k: Image.open(every[k]).getpixel((4, 4)) == border  # noqa: E731
    assert is_title(hi) and not is_title(lo), 'no title at the end of the recording'
    while hi - lo > 1:
        mid = (lo + hi) // 2
        lo, hi = (mid, hi) if not is_title(mid) else (lo, mid)
    open(os.path.join(d, 'title.txt'), 'w').write('%d\n' % hi)
    # the second page: the first picture after the stick went right on
    # TEAM SETTINGS that differs from the one before it in its four lines
    menu = (64, 84, 320, 124)
    k = page2 + 1
    while k < end - 1 and not ImageChops.difference(
            Image.open(every[k]).crop(menu).convert('RGB'),
            Image.open(every[page2]).crop(menu).convert('RGB')).getbbox():
        k += 1
    open(os.path.join(d, 'settings.txt'), 'w').write('%d %d\n' % (k, end))
    print('%d pictures, the title from %d on, its second page from %d (%d s after it)'
          % (len(every), hi, k, (k - hi) // FPS))
    assert hi < k < end - FPS, 'the title or its second page not where it should be'


def league_block(days):
    """the league as the disk keeps it (game.inc L_BLOCK): LEAGUE_TEAMS,
    the matchdays before days played (and on the last, the computer's)"""
    res = [r if (m < days * 4 or (days == 6 and m > 24)) and r else None
           for m, r in enumerate(LEAGUE_RES)]
    lg = [0, 1, 0, 0, 0, 0] + LEAGUE_TEAMS + [255 if r is None else r[0] * 16 + r[1] for r in res]
    lg[0] = -sum(lg[1:]) & 255
    assert len(lg) == L_LEN
    return lg


def record_league():
    """the league from a copy of the disk in Yape (it writes the disk
    back), from the title on: LEAGUE chosen, the page of a new league;
    then (the league poked) the end of matchday 4's match and the page
    after it, and of the last matchday's, the league won - to
    WORK/league (f0000.ppm ...), where each is in marks.txt"""
    img = os.path.join(WORK, 'league.d64')
    subprocess.run(['cp', moves.D64, img], check=True)
    moves.clear_shots()
    y = Yape(img, series=7500, title=True,
             env=('YAPE_WAV=' + moves.WAV, 'SDL_AUDIODRIVER=dummy'))
    lab = moves.labels()
    marks = {}
    # Germany against Brazil on the title from the start: its choices
    # (K_CH) and that they are set (K_CHOK), before the title reads them
    y.poke(K_CH - 2, [0x5A, 0xA5, 0, 0, 0, 14, 3, 0, 0])

    def mark(name):
        marks[name] = len(pictures())
        print('  %-8s %d' % (name, marks[name]))

    def wait(test, what, secs=120):
        t = time.time()
        while not test():
            if time.time() - t > secs:
                raise RuntimeError('waited in vain: ' + what)
            time.sleep(0.3)

    def stick(how, wait=0.45):
        y.poke(lab['dbg_joy'], [moves.bits(how)])
        time.sleep(0.15)
        y.poke(lab['dbg_joy'], [0])
        time.sleep(wait)

    def on_page():
        row = y.mem(0x0C00 + 23 * 40, 40) + y.mem(0x0C00 + 24 * 40, 40)
        return bytes(c & 0x3F for c in row).find(bytes(c & 0x3F for c in b'TITLE')) >= 0

    def in_match():
        return y.mem(0xFFFE, 2)[1] != 0 and y.mem(0xFF07, 1)[0] & 0x10 and y.mem(0xFF06, 1)[0] & 0x10

    def match(name, score):
        stick('fire', 0.2)                  # the next match: at once
        wait(in_match, 'the match')
        time.sleep(1.0)
        y.poke(lab['score'], score)
        y.poke(lab['game_min'], [89])
        mark(name)
        while y.mem(lab['full'], 1)[0] != 1:  # (the kick-off: the stick)
            stick('up+fire', 0.1)
            y.poke(lab['score'], score)
        mark(name + '-ft')
        time.sleep(3.0)
        stick('fire', 0.2)                  # back: the page
        mark(name + '-back')
        wait(on_page, 'the page')
        mark(name + '-page')
        time.sleep(7.0)
    try:
        t0 = time.time()
        wait(lambda: y.mem(0xfffe, 2) == [lab['synth'], 0] and y.mem(0xff06, 1)[0] == 0x1b,
             'the title', 180)
        print('title after %d s' % (time.time() - t0))
        host('pkill', '-USR2', '-x', 'yapesdl')  # the pictures from here
        time.sleep(1.0)
        mark('title')
        time.sleep(2.0)
        stick('down')
        stick('down', 0.8)
        stick('right', 0.6)                 # TRAINING
        stick('right', 1.2)                 # LEAGUE
        mark('fire')
        stick('fire', 0.2)
        wait(on_page, 'the first page')
        mark('page1')
        time.sleep(5.0)
        y.poke(L_BLOCK, league_block(3))    # three matchdays played
        match('day4', LEAGUE_SCORE[0])
        y.poke(L_BLOCK, league_block(6))    # six
        match('day7', LEAGUE_SCORE[1])
        stick('fire', 0.2)                  # back to the title: the winner's page first
        mark('champ-back')
        wait(lambda: y.mem(0xfffe, 2) == [lab['synth'], 0] and y.mem(0xff06, 1)[0] & 0x10,
             'the winner\'s page')
        mark('champ')
        time.sleep(7.0)
    finally:
        y.stop()
    d = os.path.join(WORK, 'league')
    subprocess.run(['rm', '-rf', d])
    os.makedirs(d)
    for f in pictures():
        os.rename(f, os.path.join(d, 'f%04d.ppm' % int(f.rsplit('.', 1)[1])))
    if os.path.exists(moves.WAV):
        os.remove(moves.WAV)
    with open(os.path.join(d, 'marks.txt'), 'w') as f:
        for k, v in marks.items():
            f.write('%s %d\n' % (k, v))
    print('%d pictures' % len(frames_of('league')))


def league_parts(gain):
    """the league's three parts: (out, pieces, captions) - the loading
    between shown a moment only"""
    mk = dict(l.split() for l in open(os.path.join(WORK, 'league', 'marks.txt')))
    mk = {k: int(v) for k, v in mk.items()}
    load = int(1.2 * FPS)
    a = [(mk['fire'] - int(4.5 * FPS), mk['fire'] + 10, 1),
         (mk['fire'] + 10, mk['fire'] + 10 + load, 1),
         (mk['page1'], mk['page1'] + int(5.0 * FPS), 1)]
    out = [('league1', a, [(LEAGUE_CAPS[0], X, -X)])]
    for k, name in ((1, 'day4'), (2, 'day7')):
        p = [(mk[name] + 10, mk[name + '-ft'] + int(1.5 * FPS), 1),     # (from minute 89)
             (mk[name + '-back'] + 5, mk[name + '-back'] + 5 + load, 1),
             (mk[name + '-page'], mk[name + '-page'] + int(6.5 * FPS), 1)]
        out.append(('league%d' % (k + 1), p, [(LEAGUE_CAPS[k], X, -X)]))
    p = [(mk['champ-back'] + 5, mk['champ-back'] + 5 + load, 1),
         (mk['champ'], mk['champ'] + int(6.0 * FPS), 1)]
    out.append(('league4', p, [(LEAGUE_CAPS[3], X, -X)]))
    return [(o,) + part('league', o, p, gain, mute=True, caps=c) + (1,) for o, p, c in out]


def pictures():
    """the pictures Yape has written so far"""
    return [f for f in glob.glob(SHOT + '.*') if f.rsplit('.', 1)[1].isdigit()]


# ---- the wipes -----------------------------------------------------------------

def reach(kind, q):
    """how far a wipe has come, q (0..1) of its way: 255 where it has
    passed (an 'L' picture at the machine's size)"""
    m = Image.new('L', (W, H), 0)
    if q <= 0:
        return m
    d = ImageDraw.Draw(m)
    r = math.hypot(W / 2, H / 2) + 2
    if kind == 'left':                  # from the right, going left
        d.rectangle((round(W * (1 - q)), 0, W, H), 255)
    elif kind == 'right':
        d.rectangle((0, 0, round(W * q) - 1, H), 255)
    elif kind == 'up':
        d.rectangle((0, round(H * (1 - q)), W, H), 255)
    elif kind == 'down':
        d.rectangle((0, 0, W, round(H * q) - 1), 255)
    elif kind == 'radial':              # a clock's hand from twelve
        d.pieslice((W / 2 - r, H / 2 - r, W / 2 + r, H / 2 + r), -90, -90 + 360 * min(q, 1), 255)
    elif kind == 'open':                # an iris opening
        k = r * min(q, 1)
        d.ellipse((W / 2 - k, H / 2 - k, W / 2 + k, H / 2 + k), 255)
    elif kind == 'close':               # closing
        m.paste(255, (0, 0, W, H))
        k = r * (1 - min(q, 1))
        d.ellipse((W / 2 - k, H / 2 - k, W / 2 + k, H / 2 + k), 0)
    return m


def wiped(kind, a, b, p):
    """p (0..1) of the way from picture a to b: faded, or wiped with a
    soft edge"""
    if kind == 'fade':
        return Image.blend(a, b, p)
    out = a.copy()
    out.paste(b, (0, 0), reach(kind, p).filter(ImageFilter.GaussianBlur(EDGE)))
    return out


def body_video(parts, path):
    """the parts one after another, each wiped into the next, at the
    machine's size: path (.mkv, lossless, with the parts' sound,
    cross-faded) - frame by frame, so nothing much is held"""
    xf = int(X * FPS)
    spf = RATE // FPS
    pcm = array.array('h')
    for i, (_, d, snd, n, _) in enumerate(parts):
        if i == 0:
            pcm.extend(snd)
            continue
        o = xf * spf                    # (the sound: one fades into the other)
        tail = pcm[len(pcm) - o:]
        del pcm[len(pcm) - o:]
        pcm.extend(array.array('h', (int(x * (1 - k / o) + y * k / o)
                                     for k, (x, y) in enumerate(zip(tail, snd[:o])))))
        pcm.extend(snd[o:])
    wav = os.path.join(T, 'body.wav')
    with wave.open(wav, 'wb') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(pcm.tobytes())
    ff = subprocess.Popen(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24',
                           '-s', '%dx%d' % (W, H), '-r', str(FPS), '-i', '-', '-i', wav,
                           '-c:v', 'ffv1', '-pix_fmt', 'bgr0', '-c:a', 'pcm_s16le', path],
                          stdin=subprocess.PIPE)

    def pic(d, k):
        return Image.open(os.path.join(d, '%04d.ppm' % k)).convert('RGB')
    for i, (_, d, _, n, _) in enumerate(parts):
        first = xf if i else 0
        last = n - xf if i < len(parts) - 1 else n
        for k in range(first, last):
            ff.stdin.write(pic(d, k).tobytes())
        if i < len(parts) - 1:
            nd = parts[i + 1][1]
            kind = END_WIPE if i == len(parts) - 2 else WIPES[i % len(WIPES)]
            for k in range(xf):
                ff.stdin.write(wiped(kind, pic(d, last + k), pic(nd, k), (k + 1) / (xf + 1)).tobytes())
    ff.stdin.close()
    if ff.wait():
        raise RuntimeError('ffmpeg: the body')
    os.remove(wav)


# ---- the parts ------------------------------------------------------------------

def frames_of(name):
    d = os.path.join(WORK, name)
    return sorted(os.path.join(d, f) for f in os.listdir(d) if f.startswith('f') and f.endswith('.ppm'))


def sound_of(name):
    raw = os.path.join(WORK, name, 'sound.raw')
    return array.array('h', open(raw, 'rb').read()) if os.path.exists(raw) else array.array('h')


def part(name, out, pieces, gain, mute=False, caps=(), replay=None):
    """a part from a scene's pictures: pieces (first, end, times each is
    shown) one after the other; the sound with them where each is shown
    once (none where slowed or held, nor at all when mute). Its captions
    (lines, from, to seconds into the part; to None: its end, below 0:
    so long before it) put into the pictures below the pitch, and REPLAY
    above it, blinking, while
    the replay (from, to) runs - at the machine's size, enlarged with
    the rest (nothing laid over the video later: that held every
    caption's pictures in memory). Its pictures in <out>.seq; returns
    that, its sound and how many pictures"""
    every = frames_of(name)
    snd = sound_of(name)
    per = len(snd) / max(1, len(every))
    d = os.path.join(T, out + '.seq')
    subprocess.run(['rm', '-rf', d])
    os.makedirs(d)
    shown = [k for a, b, times in pieces for k in range(a, min(b, len(every))) for _ in range(times)]
    end = len(shown) / FPS
    caps = [(caption_img(lines), a, end if b is None else end + b if b < 0 else b)
            for lines, a, b in caps]
    label = label_img('REPLAY')
    for n, k in enumerate(shown):
        t = n / FPS
        marks = [(c, (0, 248)) for c, a, b in caps if a <= t < b]
        if replay and replay[0] + 0.2 <= t < min(replay[1], end - X) - 0.1 and (t - replay[0] - 0.2) % 1 < 0.7:
            marks.append((label, (40, 22)))
        if marks:
            im = Image.open(every[k]).convert('RGB')
            for m, at in marks:
                im.paste(m, at, m)
            im.save(os.path.join(d, '%04d.ppm' % n))
        else:
            os.symlink(every[k], os.path.join(d, '%04d.ppm' % n))
    # (the TED's sound is all above 0: its middle taken out - held or
    # slowed, that middle: silence - and as loud as gain says)
    mid = sum(snd) // len(snd) if snd else 0
    pcm = array.array('h')
    spf = RATE // FPS
    for a, b, times in pieces:
        b = min(b, len(every))
        if times == 1 and not mute:
            s = snd[int(a * per):int(b * per)]
            s = s[:(b - a) * spf]
            s.extend([mid] * ((b - a) * spf - len(s)))
        else:
            s = array.array('h', [mid]) * ((b - a) * times * spf)
        pcm.extend(s)
    pcm = array.array('h', (max(-32767, min(32767, int((v - mid) * gain))) for v in pcm))
    return d, pcm, len(shown)


def plan_scene(name, length):
    """a scene's pieces: the move played and some frames after it, and
    the moment played again at half speed - the part SCENE_MIN long; and
    where in it (seconds) the replay is"""
    first = WAIT.get(name, FIRST)
    have = len(frames_of(name)) - first
    want = int(SCENE_MIN * FPS)
    live = length + TAIL
    if name in REPLAY:
        ra, rb = REPLAY[name]
    else:
        r = max(0, min(length, (want - live) // 2))
        ra, rb = length - r, length
    if rb <= ra:
        return [(first, first + min(have, max(live, want)), 1)], None
    live = min(have, max(live, want - 2 * (rb - ra)))
    pieces = [(first, first + live, 1), (first + ra, first + rb, 2)]
    return pieces, (live / FPS, (live + 2 * (rb - ra)) / FPS)


def main():
    os.makedirs(T, exist_ok=True)
    if '--boot' in sys.argv:
        record_boot()
    if '--league' in sys.argv:
        record_league()
    cr = os.path.join(T, 'crawl.mkv')
    print('the opening')
    crawl(cr)
    ce = os.path.join(T, 'credits.mkv')
    print('the closing')
    closing = crawl(ce, CREDITS, opening=False)
    if '--crawl' in sys.argv:
        out = OUT.replace('.mp4', '-crawl.mp4')
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', cr, '-c:v', 'libx264', '-crf', '18',
                        '-pix_fmt', 'yuv420p', out], check=True)
        print(out)
        return
    # the game's sound as loud as moves.py has it, the same for each scene
    names = [s[0] for s in SCENES]
    rng = max(1, max(max(s) - min(s) for s in (sound_of(n) for n in names) if s))
    gain = 0.45 * 65535 / rng
    # the parts: (name, its pictures, its sound, how many, the song under
    # it); the captions on while no wipe runs
    parts = []
    t0 = int(open(os.path.join(WORK, 'boot', 'title.txt')).read())
    p2, end = map(int, open(os.path.join(WORK, 'boot', 'settings.txt')).read().split())
    a = t0 - int(BOOT_LOAD * FPS)
    # (its sound not Yape's: the monitor, asked whether the title was on
    # yet, left gaps in it - the song runs on under it instead, the same)
    parts.append(('boot',) + part('boot', 'boot', [(a, end, 1)], gain, mute=True,
                                  caps=[(BOOT_CAPS[0], 0, BOOT_LOAD), (BOOT_CAPS[1], BOOT_LOAD, (p2 - a) / FPS),
                                        (BOOT_CAPS[2], (p2 - a) / FPS, -X)])
                 + (1,))
    parts.append(('title',) + part('title', 'title', [(0, len(frames_of('title')), 1)], gain, mute=True,
                                   caps=[(TITLE, X, -X)]) + (1,))
    for name, caption, length, _, _ in SCENES:
        pieces, replay = plan_scene(name, length)
        p = part(name, name, pieces, gain, caps=[(caption, X, -X)], replay=replay)
        print('  %-10s %4.1f s%s' % (name, p[2] / FPS, '' if not replay else
                                     ', replay %.1f - %.1f' % replay))
        parts.append((name,) + p + (BED,))
    parts += league_parts(gain)
    parts.append(('end',) + part('title', 'end', [(END_FRAME, END_FRAME + 1, 8 * FPS)], gain, mute=True,
                                 caps=[(END, X, None)]) + (1,))

    # first the parts wiped into one another, at the machine's size
    # (body.mkv), then that enlarged behind the opening
    starts, t = [], 0.0
    for p in parts:
        starts.append(t)
        t += p[3] / FPS - X
    body = t + X
    off = CRAWL_S - CRAWL_X
    total = off + body - CRAWL_X + closing
    bf = os.path.join(T, 'body.mkv')
    body_video(parts, bf)
    for p in parts:
        subprocess.run(['rm', '-rf', p[1]])

    # then the opening, the body enlarged, the closing, and the sound: the game's from
    # the scenes, the song one track from the first second to the last,
    # never cut nor laid over itself - alone but in the scenes, lower
    # under them, from one level to the next in a wipe's time
    song = os.path.join(T, 'song.wav')
    subprocess.run([sys.executable, os.path.join(HERE, 'tools', 'mkmusic.py'), '--wav', song,
                    '%d' % math.ceil(total + 1)], check=True, stdout=subprocess.DEVNULL)
    lv = [(0.0, 1.0)]
    for i, p in enumerate(parts):
        lv.append((off + starts[i] + (CRAWL_X if i == 0 else X), p[4]))
    vol = '1'
    for (ta, va), (tb, vb) in zip(lv, lv[1:]):
        if va != vb:
            vol = '(%s)+(%s)*clip((t-%.2f)/%.2f,0,1)' % (vol, vb - va, tb - CRAWL_X, CRAWL_X)
    fc = ('[0:v]format=yuv444p,fps=%d,settb=AVTB[crawl];' % FPS +
          '[1:v]scale=%d:%d:flags=neighbor,format=yuv444p,fps=%d,settb=AVTB[body];' % (W * Z, H * Z, FPS) +
          '[2:v]format=yuv444p,fps=%d,settb=AVTB[closing];' % FPS +
          '[crawl][body]xfade=transition=fade:duration=%s:offset=%.3f[cb];' % (CRAWL_X, off) +
          '[cb][closing]xfade=transition=fade:duration=%s:offset=%.3f,' % (CRAWL_X, off + body - CRAWL_X) +
          'fade=t=out:st=%.2f:d=1.5,format=yuv420p[outv];' % (total - 1.5) +
          '[1:a]aresample=%d,highpass=f=15,adelay=%d:all=1[game];' % (RATE, int(off * 1000)) +
          "[3:a]aresample=%d,volume=%s,volume='%s':eval=frame,lowpass=f=9000[bed];" % (RATE, SONG, vol) +
          '[bed][game]amix=inputs=2:normalize=0:duration=first,atrim=duration=%.3f,' % total +
          'asetpts=N/SR/TB,afade=t=in:d=0.3,afade=t=out:st=%.2f:d=2.5[outa]' % (total - 2.5))
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-filter_complex_threads', '2',
                    '-i', cr, '-i', bf, '-i', ce, '-i', song, '-filter_complex', fc,
                    '-map', '[outv]', '-map', '[outa]', '-t', '%.3f' % total,
                    '-c:v', 'libx264', '-threads', '4', '-preset', 'slow', '-crf', '16', '-pix_fmt', 'yuv420p',
                    '-c:a', 'aac', '-b:a', '192k', '-movflags', '+faststart', OUT], check=True)
    print('%s: %.1f s' % (OUT, total))


if __name__ == '__main__':
    main()
