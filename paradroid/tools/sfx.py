#!/usr/bin/env python3
"""sfx.py ram.bin - the original's sound effects into data/sfx.txt.

The original's sound driver ($0500, see tools/sid.py and tools/sidmusic.py)
plays an effect from a record of 16 bytes at $C610 + 16 * (number - 1): an
instrument (8 bytes at $EAA0: waveform, envelope, the frames until the gate
is let go), a start frequency and what is added to it each picture, a
period - its first length, its length after, how many - and at the end of
each period either back to a frequency or the step turned round. Two
channels, as the TED has voices; the game puts an effect's number into
$91 or $92. The numbers and where the game uses them were read off its
code in x64sc. The hum of each deck is effect $18 with the period of the
deck's own (tables at $6E60, $6E70, $6E80, set at each lift ride).
"""
import os
import sys

# name, the original's number, its channel; where the original uses it
EFFECTS = [
    ('shot1', 0x01, 1),     # the player's shot, by the host's weapon: 1 + weapon
    ('shot2', 0x02, 1),
    ('shot3', 0x03, 1),
    ('shot4', 0x04, 1),
    ('terminated', 0x05, 1),  # "Transmission terminated", after a game
    ('beam', 0x07, 1),      # a game's start: the player beamed aboard
    ('low', 0x08, 2),       # energy below 8: every 32 ticks
    ('complete', 0x0B, 1),  # "Complete"; and the transfer's own droid shown
    ('rejected', 0x0C, 1),  # "Rejected"; and the other droid shown
    ('burnt', 0x0D, 1),     # "Burnt Out"
    ('deadlock', 0x0E, 1),  # "Deadlock"
    ('static', 0x0F, 1),    # the static after a game, before "terminated"
    ('ride', 0x10, 2),      # the lift going from deck to deck
    ('dhit', 0x11, 2),      # a droid hit
    ('dboom', 0x12, 1),     # a droid destroyed
    ('pboom', 0x13, 1),     # the player destroyed
    ('energy', 0x14, 1),    # an energizer: each unit of energy
    ('pulse', 0x15, 1),     # the transfer game: a pulse put in
    ('lift', 0x16, 2),      # "Lift", and the console's menu
    ('cleared', 0x17, 1),   # the deck cleared
    ('hum', 0x18, 2),       # the ship's hum, every 32 ticks while voice 2 is free
    ('phit', 0x19, 1),      # the player hit
    ('bump', 0x1A, 1),      # the player bumping into a droid
    ('finish', 0x1B, 2),    # the transfer game's "Finish"
    ('tmode', 0x1C, 1),     # transfer mode: every 8 ticks
]

WAVES = {0x10: 'T', 0x20: 'S', 0x40: 'P', 0x80: 'N'}
RELEASE_MS = [6, 24, 48, 72, 114, 168, 204, 240, 300, 750, 1500, 2400,
              3000, 9000, 15000, 24000]


def s16(lo, hi):
    v = lo | hi << 8
    return v - 65536 if v & 0x8000 else v


def main():
    ram = open(sys.argv[1], 'rb').read()
    if len(ram) == 65538:
        ram = ram[2:]
    out = ['# The original\'s sound effects: made by tools/sfx.py from a dump of its',
           '# memory during a game (records at $C610, instruments at $EAA0).',
           '#',
           '# name  number channel  start step  first period count  reset wave',
           '#       gate release(ms)',
           '#   start, step: the SID\'s frequency, 16 bits; step added each picture',
           '#   first/period/count: the periods; at each end the step turns round,',
           '#   or with reset the frequency goes back to the start',
           '#   wave: T triangle, S saw, P pulse, N noise; gate: pictures until the',
           '#   tone is let go, then its release',
           '']
    for name, num, ch in EFFECTS:
        rec = ram[0xC610 + 16 * (num - 1):0xC610 + 16 * num]
        ins = ram[0xEAA0 + 8 * rec[0]:0xEAA0 + 8 * rec[0] + 8]
        reset = rec[12] == 1
        start = (rec[13] | rec[14] << 8) if reset else (rec[1] | rec[2] << 8)
        out.append('%-9s %02x %d  %5d %6d  %3d %3d %2d  %d %s  %3d %5d' % (
            name, num, ch, start, s16(rec[3], rec[4]), rec[5], rec[6], rec[7],
            reset, WAVES[ins[4] & 0xF0], ins[7], RELEASE_MS[ins[6] & 15]))
    out.append('')
    out.append('# the hum\'s periods, deck by deck: first, after, count')
    for a, what in ((0x6E60, 'first'), (0x6E70, 'period'), (0x6E80, 'count')):
        out.append('hum_%s %s' % (what, ' '.join(str(b) for b in ram[a:a + 16])))
    path = os.path.join(os.path.dirname(__file__), '..', 'data', 'sfx.txt')
    open(path, 'w').write('\n'.join(out) + '\n')
    print(path)


if __name__ == '__main__':
    main()
