# So What'cha Want - a Plus/4 demo

A demo for the Commodore Plus/4 to **So What'cha Want** (Beastie Boys,
1992). The sound comes first; the pictures will be fitted to it once it
stands.

**Work in progress.** What is there: the player - three voices mixed in
software and played through the TED's volume register (International
Karate's mixer, as Simple Soccer's title has it), grown for a Hammond
organ: waves built from the nine drawbars, the percussion's click at a
note's start, a Leslie's vibrato and tremolo - and a first take of the
music. That take was guessed from the record's notes and is not
recognisable; the next one is built on samples of the record itself,
cut by hand (see below), with the organ played by the player on top.

![The sound check](screenshots/sound-check.png)

The screen shows where the music is - bar, beat, sixteenth - and each
voice's level: what the pictures will be timed by.

## Building and running

```sh
./build.sh            # build/whatchawant.prg
./build.sh --wav      # and build/music.wav: the music as the TED plays it
python3 tests/music.py [seconds]   # in Yape: build/music-yape.mp4, .wav
```

The music is written in `data/music.txt` (its format is explained at its
top); `tools/mkmusic.py` makes the player's data of it.

## Preparing the samples (Audacity)

The record is in `ref/` (not in git). What the Plus/4 can play: 5542
samples a second, 9 levels - so anything above about 2.7 kHz comes back
as a chirp, and anything quiet drowns in the steps. Pieces made to the
spec below lose most of that noise.

**The record's grid.** 85.38 beats a minute, steady all through: a bar is
**2.811 s**, two bars 5.622 s. Bar *n* starts at 0.459 s + *n* x 2.811 s:

| Part | Bars | Starts at |
| --- | --- | --- |
| intro | 0-2 | 0:00.459 |
| main loop (with vocals) | 3-42 | 0:08.892 |
| second part, round A | 43-49 | 2:01.330 |
| break | 50-51 | 2:21.007 |
| main loop again | 52-76 | 2:26.629 |
| **cleanest main loop** (almost no vocals) | **70-71** | **3:17.226** |
| also clean | 74-75 | 3:28.470 |

(Where bar 1 really falls is not certain: it may be an eighth, 0.351 s,
off. Trust your ear and cut on the downbeat you hear.)

**Each piece:**

| | |
| --- | --- |
| Format | WAV, mono, 16-bit, any sample rate (brought to 5542 Hz here) |
| Length | exactly whole bars: 2.811 s (1 bar), 5.622 s (2), 11.244 s (4) - loops seamlessly, starting on the downbeat |
| Low-pass | 2500 Hz, steep (48 dB per octave). The hi-hats mostly go with it - right so: the Plus/4 cannot play them; the player's noise adds them back |
| Dynamics | compressed hard (about 4:1 or more from -20 dB), normalised to -1 dB: few levels want a loud, even signal |
| Edges | no fades at loop ends (they would pump at every repeat); a one-shot like "Oh yeah" cut tight, no silence before or after |

**What to deliver,** into `ref/`, one file a piece:

| File | What |
| --- | --- |
| `main.wav` | the main loop, drums and bass, 1 or 2 bars |
| `b.wav` | the second part's loop |
| `intro.wav`, `break.wav` | if you want them as they are |
| `organ-*.wav` | the organ alone, if you can get it clean - else the player plays it |
| `ohyeah.wav` | the "Oh yeah", cut tight, no silence before or after |

A sample costs about 2.7 KB a second of memory (two samples to a byte),
some 7.6 KB a bar, so whole bars as loops are cheap; the demo puts the
song together of them.

## How this was made

Directed by the author, with an AI coding assistant used intensively for
the implementation - see the main README.
