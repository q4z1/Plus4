#!/usr/bin/env python3
"""A goal played for, not poked: the joystick moved by what the match
shows - to the ball, up the pitch with it to the side of the box, round
the yellow player ahead, a shot across into the far corner. The
trailer's match (tests/trailer.py --league) is played so in Yape
(yape_goal: each look and each move in one stop of its monitor, the
pictures going on where they were); here in VICE, picture by picture,
to see how it goes.

    tests/autogoal.py [pictures]

A line every few pictures: the joystick's player, the ball, the stick,
the score. The exit code 0 once the cyan team has scored.
"""
import math
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shot import PRG, WORK, BITS, labels, held_from_start  # noqa: E402

lab = labels()
N = 23                          # objects: 22 players, the ball
BALL = 22
GOAL = (304, 60)                # the yellow team's goal (cyan plays up)
FLIP_Y = 60 + 689               # the keepers' y added: y upside down
R_THROW = 1                     # (play.s rs_kind)
SHOOT_Y = (100, 210)            # a shot from between these
SIDE = 75                       # dribbled to this far to the side of the goal
POST_L, POST_R = 269, 340       # (play.s)
KEEPER_OFF = 18                 # the shot's way this far from the keeper, at least
# a shot: fire held with the stick the way it goes, longer than SHOT_HOLD
# (let go sooner it is a pass) - the shot the way he faces, once the ball
# is at his feet (play.s control); then let go
SHOT_FRAMES = 27
# a header (play.s head: fire held, the ball 13 - 26 high and within 10):
# fire held already as a high ball comes near, the stick at the goal
HEAD_Z, HEAD_NEAR = (9, 30), 24
# a cross to be headed (Pilot.heads): the ball's flight foreseen from two
# looks (its way) and its step up (gravity $12/256 a frame) - he runs to
# where it comes down to head height (HEAD_AT) first that he can reach at
# RUN_PX a frame, and presses fire FIRE_T frames before it is there: he
# jumps for it (can_try: within DHEAD_D2) and heads it as
# it comes (head: within 10, 13 - 26 high, in his HEAD_T frames up)
HEAD_AT = (14, 24)
RUN_PX = 1.8
FIRE_T = 9
HEAD_R = 7                      # within this of its way: headed (head: 10)
GRAVITY = 0x12 / 256
NAMES = ['up', 'up+right', 'right', 'down+right', 'down', 'down+left', 'left', 'up+left']


def stick_to(dx, dy):
    """the stick's way towards (dx, dy): one of eight"""
    a = math.atan2(dx, -dy)                 # 0 up, clockwise
    return NAMES[round(a / (math.pi / 4)) % 8]


def bits(stick):
    b = 0
    for p in stick.split('+'):
        b |= BITS.get(p, 0)
    return b


def read_state(mem):
    """the state from mem(addr, n): positions, the joystick's player, ..."""
    o = mem(lab['o_xl'], 4 * N)
    xs = [o[i] + 256 * o[N + i] for i in range(N)]
    ys = [o[2 * N + i] + 256 * o[3 * N + i] for i in range(N)]
    xs = [x - 65536 if x > 32767 else x for x in xs]
    ys = [y - 65536 if y > 32767 else y for y in ys]
    # kickoff, taker, dead_t, last_team, last_pl: one after the other
    assert [lab[k] - lab['kickoff'] for k in ('taker', 'dead_t', 'last_team', 'last_pl')] == [1, 2, 3, 4]
    zp = mem(lab['kickoff'], 5)
    s = dict(x=xs, y=ys, kickoff=zp[0], taker=zp[1], dead=zp[2], last_team=zp[3], last_pl=zp[4])
    s['ctrl'] = mem(lab['ctrl'], 1)[0]
    s['z'] = mem(lab['o_zl'] + BALL, 1)[0]
    s['score'] = mem(lab['score'], 2)
    s['frames'] = mem(lab['frames'], 1)[0]
    s['flip'] = mem(lab['flip'], 1)[0]
    s['min'] = mem(lab['game_min'], 1)[0]
    s['rs'] = mem(lab['rs_kind'], 1)[0]
    s['jumps'] = mem(lab['jumps'], 1)[0]
    dz = mem(lab['o_dzl'] + BALL, 1)[0] + mem(lab['o_dzf'] + BALL, 1)[0] / 256
    s['dz'] = dz - 256 if dz >= 128 else dz
    s['zs'] = mem(lab['o_zl'], N)
    return s


def headed(s):
    """whether state s shows the joystick's player heading it: up in a
    header's jump (play.s head/can_try: jumps), the ball his touch last
    (a try missed leaves it the kicker's)"""
    c = s['ctrl']
    return s['jumps'] > 0 and c < 11 and s['last_team'] == 0 and s['last_pl'] == c and \
        s['zs'][c] > 0


class Pilot:
    """the stick, look by look"""

    def __init__(self, heads=False):
        self.shot_t = None                  # the frame the shot's fire went down
        self.heads = heads                  # a high ball near him: headed at the goal
        self.aim = 'up'
        self.kick = 0
        self.seen = None                    # the ball at the last look: frames, x, y, its last touch

    def decide(self, s):
        """the stick for state s - after half time (flip) the cyan team
        plays down: the pitch looked at upside down, the stick too"""
        if not s['flip']:
            return self.play(s)
        st = self.play(dict(s, y=[FLIP_Y - y for y in s['y']]))
        return '+'.join({'up': 'down', 'down': 'up'}.get(p, p) for p in st.split('+'))

    def play(self, s):
        c = s['ctrl']
        if self.shot_t is not None:         # a shot: fire held, aimed
            if (s['frames'] - self.shot_t) & 255 < SHOT_FRAMES:
                return self.aim + '+fire'
            self.shot_t = None
            return 'none'
        if c == 0xFF or c > 10:
            return 'none'
        px, py = s['x'][c], s['y'][c]
        bx, by = s['x'][BALL], s['y'][BALL]
        if s['kickoff']:                    # ours to take: on to a team-mate
            if s['taker'] == c:
                self.kick = (self.kick + 1) % 6
                return 'up+fire' if self.kick == 5 else 'up'
            return 'none'
        if self.heads:
            st = self.cross(s, c, px, py, bx, by)
            if st:
                return st
        near = math.hypot(bx - px, by - py) < 10 and s['z'] < 8
        if near and s['last_team'] == 0:
            side = 1 if px >= GOAL[0] else -1
            # a shot where one of the three ways up reaches the goal line
            # between the posts, away from the keeper
            if SHOOT_Y[0] <= py <= SHOOT_Y[1]:
                kx = s['x'][11]
                best = None
                for way, dx in (('up', 0), ('up+right', 1), ('up+left', -1)):
                    land = px + dx * (py - GOAL[1])
                    if POST_L + 12 <= land <= POST_R - 12 and abs(land - kx) >= KEEPER_OFF:
                        if best is None or abs(land - kx) > best[0]:
                            best = (abs(land - kx), way)
                if best:
                    self.aim = best[1]
                    self.shot_t = s['frames']
                    return self.aim + '+fire'
            # up the pitch to the box's side, round the yellow player ahead
            tx, ty = GOAL[0] + side * SIDE, 150
            for i in range(11, 22):
                dx, dy = s['x'][i] - px, s['y'][i] - py
                if -70 < dy < 6 and abs(dx) < 34:
                    away = -1 if dx > 0 else 1
                    if px < 120:
                        away = 1
                    elif px > 490:
                        away = -1
                    return stick_to(away * 60, -40)
            return stick_to(tx - px, ty - py)
        return stick_to(bx - px, by - py)

    def cross(self, s, c, px, py, bx, by):
        """the stick for a ball in the air to be headed, None if not one"""
        seen, self.seen = self.seen, (s['frames'], bx, by, s['last_pl'])
        at_goal = stick_to(GOAL[0] - px, GOAL[1] - py)
        if s['jumps'] and s['zs'][c]:       # up for it: fire held, at the goal
            return at_goal + '+fire'
        if s['z'] < 9 or seen is None or seen[3] != s['last_pl']:
            return None
        n = (s['frames'] - seen[0]) & 255
        if not 1 <= n <= 20:
            return None
        vx, vy = (bx - seen[1]) / n, (by - seen[2]) / n
        z, dz = s['z'], s['dz']
        for t in range(0, 80):
            zt = z + dz * t - GRAVITY * t * (t + 1) / 2
            if zt < HEAD_AT[0]:
                if dz - GRAVITY * t < 0:
                    return None             # down past his head: no header
                continue                    # (still rising to it)
            if zt > HEAD_AT[1]:
                continue
            tx, ty = bx + vx * t, by + vy * t
            d = math.hypot(tx - px, ty - py)
            if d - HEAD_R <= RUN_PX * t:    # (near enough is enough)
                if t <= FIRE_T and d < HEAD_R + 2:
                    return at_goal + '+fire'
                return stick_to(tx - px, ty - py) if d >= 3 else 'none'
        return None


# ---- in Yape -------------------------------------------------------------------

def stopped_reader(y):
    """mem(addr, n) for a monitor open: Yape's dumps (320 bytes each) kept,
    so a look takes a few"""
    from moves import monitor_cmd
    have = {}

    def mem(addr, n):
        if not all(addr + i in have for i in range(n)):
            monitor_cmd(y, 'm %04x' % addr)
            text = y._read_until(b' %04X: ' % ((addr + 19 * 16) & 0xFFFF), timeout=10)
            text += y._read_until(b'\n', timeout=10)
            for line in text.splitlines():
                m = re.match(r'\s*([0-9A-F]{4}): ((?:[0-9A-F]{2} +){1,17})', line)
                if m:
                    a = int(m.group(1), 16)
                    for k, b in enumerate(m.group(2).split()[:16]):
                        have[a + k] = int(b, 16)
        return [have[addr + i] for i in range(n)]
    return mem


def yape_goal(y, at_goal, secs=900, step=0.03, log=None, clock_back=True, tick=None, open_secs=0,
              clean=False, heads=False, on_head=None):
    """the pilot at the cyan joystick in Yape (dbg_joy) till the cyan team
    scores: at_goal(since) called then, the machine still stopped -
    since: the match's frames from the last set piece; False if
    it has not in secs seconds. (clock_back: the match's clock set back
    to minute 5 at minute 40 - no half time, no end, till it scores;
    tick() now and then, the machine running). open_secs: only a goal
    from open play counts - no set piece but a throw-in for so many
    seconds before it (the set pieces put the players in their places at
    once: a cut in the picture), else it plays on for another. clean:
    the score kept as it was at the start (a goal that does not count,
    one of the yellow team's: set back), so the one that counts is the
    first on the board. heads: a high ball near the joystick's player
    headed at the goal (fire held); on_head() called the first time the
    joystick's player has headed it (headed)"""
    from moves import monitor_open, monitor_cmd
    pilot = Pilot()
    pilot.heads = heads
    first = None
    t0 = time.time()
    n = 0
    t, last, set_t = 0, None, -10 ** 6      # (the match's frames since the start)
    while time.time() - t0 < secs:
        monitor_open(y)
        s = read_state(stopped_reader(y))
        if first is None:
            first = s['score'][0]
        if last is not None:
            t += (s['frames'] - last) & 255
        last = s['frames']
        if s['kickoff'] and s['rs'] != R_THROW:
            set_t = t
        scored = s['score'][0] != first
        if scored and t - set_t < open_secs * 50:
            if log:
                log('a goal %d frames after a set piece: not from open play, on' % (t - set_t))
            if not clean:
                first = s['score'][0]
            scored = False
        st = 'none' if scored else pilot.decide(s)
        if on_head and headed(s):
            on_head()
            on_head = None
        if scored:
            at_goal(t - set_t)
        if log and n % 10 == 0:
            c = s['ctrl']
            log('f%3d ctrl %3d at %s ball %d,%d %-14s %d-%d' % (
                s['frames'], c, '%d,%d' % (s['x'][c], s['y'][c]) if c < N else '-',
                s['x'][BALL], s['y'][BALL], st, s['score'][0], s['score'][1]))
        n += 1
        cmds = ['> %04x %02x' % (lab['dbg_joy'], bits(st))]
        if clean and not scored and s['score'] != [first, 0]:
            cmds.append('> %04x %02x %02x' % (lab['score'], first, 0))
        if clock_back and s['min'] >= 40:   # (no half time: the clock back)
            cmds.append('> %04x %02x' % (lab['game_min'], 5))
        monitor_cmd(y, *cmds, 'x')
        y._read_until(b'MONITOR LEFT\n', timeout=20)
        if scored:
            return True
        if tick and n % 25 == 0:            # (the caller's, now and then)
            tick()
        time.sleep(step)
    return False


def main():
    from vice import Vice
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 1500
    v = Vice(PRG, WORK)
    pilot = Pilot()
    try:
        held_from_start(v, lab, 'none')
        v.cmd('watch store %04x' % lab['shown'])
        for _ in range(60):
            v.cmd('x')
        for pic in range(n):
            s = read_state(v.mem)
            st = pilot.decide(s)
            v.poke(lab['dbg_joy'], [bits(st)])
            c = s['ctrl']
            if pic % 3 == 0 or s['score'][0]:
                print('%4d ctrl %3d at %s ball %d,%d z%d last %d/%d %-14s %d-%d' % (
                    pic, c, '%d,%d' % (s['x'][c], s['y'][c]) if c < N else '-',
                    s['x'][BALL], s['y'][BALL], s['z'], s['last_team'], s['last_pl'], st,
                    s['score'][0], s['score'][1]))
            if s['score'][0]:
                return 0
            v.cmd('x')
        return 1
    finally:
        v.stop()


if __name__ == '__main__':
    sys.exit(main())
