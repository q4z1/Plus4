# Paradroid for the Commodore Plus/4

**Paradroid** by Andrew Braybrook (Graftgold, published by Hewson, 1985) was
written for the C64, which has hardware sprites and a video chip that scrolls
smoothly under a fixed status panel. The Plus/4 has neither of those, and
this version is about how it manages anyway.

The decks, their blocks and characters, the waypoints the droids walk, the
lifts, the droid types, the status panel, the side view of the ship and the
briefing all come from the original. `tools/extract.py` took them out of the memory of
the C64 game running in VICE. The program around them is new, in C with the
time-critical parts in assembly.

![A deck: the influence device, droid 247, a laser on its way](screenshots/deck.png)

**Controls**

| | |
| --- | --- |
| Joystick in either port, or the cursor keys | drive. The droid has inertia, as in the original |
| Fire (or `Space`) with a direction | lasers in that direction |
| Fire held, no direction | transfer mode: the player blinks, and touching a droid starts the transfer game |
| Fire held on a lift | the side view of the ship; up and down choose a deck on that shaft, letting go gets out there |
| Fire held at a console | the ship's computer: up and down choose a symbol, fire takes it (the first leaves); in the droid enquiry right and left turn the pages, up and down go through the droid types |
| `Run/Stop` | pause |

## The game

You are the 001, an influence device beamed onto a freighter whose droids
have run wild. You can shoot them, or take one over by winning the
**transfer game** against it, which makes it your host. The rules are the
original's, read from its code:

- Every droid has up to 64 energy and slowly gets it back. A shot of yours
  takes 16 per class of your host's weapon plus 80, less 4 per type of the
  droid hit. So the bare 001 cannot hurt the 8xx and 999 at all, and you
  need better hosts to get at them. A droid's laser takes 8 or 16.
- The **disruptor** of the 711 and 742 is a flash that hurts every droid in
  sight, and you as well, except a few types.
- How much energy you may have **sinks** while you stay in a host: one
  point every 128 ticks in the 001, every 16 in the 999. When it reaches
  nothing, so do you. Moving on to a new host resets it. **Energizers**
  refill you up to it, at 5 points of score per point of energy.
- A lost transfer throws you out of your host, back into the bare 001,
  and takes that host's kill points off your score. Lost as the 001, it
  is the end.
- Points: 10 to 200 for a kill, 25 to 250 for a transfer, by class; 250 for
  a deck cleared, 2000 for a ship.
- Each kill raises the **alert** by the droid's type, and it sinks again
  slowly. While it is up it pays points, and the ALERT consoles turn from
  green through yellow and orange to red.

When a deck has no droids left, its lights go out. When the whole ship is
dark, the next ship of the fleet follows, with droids a class higher.

The game runs in ticks of three pictures, as the original does: 16.7 a
second. The window scrolls a pixel at a time in any direction.

| | |
| --- | --- |
| ![Transfer](screenshots/transfer.png) | ![Lift](screenshots/lift.png) |
| **Transfer.** The original's board in its characters: yellow on the left, purple on the right, twelve lines each from the rail to the column of lights. The parts are the original's: dead ends, amplifiers that keep a pulse once they have one, colour changers, branches (one line in, two out) and gates (two in, both needed). A light shows the side whose line is live there and flickers when both are. You pick your colour (*Colour? 76*), then have ten seconds (*Finish -52*). As in the original, you get your droid's class plus 3 pulses and the other side its class plus 4. The side with more lights wins; a draw is a deadlock and is played again. Winning is *Complete*; losing from a host is *Rejected* and costs that host; losing as the bare 001 is *Burnt Out*, and the game is over. | **Lift.** The original's side view of the ship: its map and characters, multicolour in white, black and blue. As in the original, the lift's own shaft is white and the deck it is at is lit, by the original's rule for which characters of the deck's box change. |
| ![Your droid](screenshots/intro_you.png) | ![The other droid](screenshots/intro.png) |
| **Before a transfer.** As in the original, both droids first: your own, then the one you touched, with the original's pictures and words. | The pictures are the original's, taken from it by running its own drawing routine for each droid type (see below), and are files on the disk. |
| ![Console](screenshots/console.png) | ![Deck plan](screenshots/plan.png) |
| **Console.** The original's first page and its four symbols: leave, droid enquiry, deck plan, ship. | **Deck plan.** As the original draws it: a character per block, the character's code being the block's number, in its characters and colours. |
| ![Droid enquiry](screenshots/droids.png) | ![Its pages](screenshots/droids_more.png) |
| **Droid enquiry.** For the types up to your host's, with the original's picture. | Its pages are the original's, read off its screens for every type (`tools/console.py`) and stored with each picture's file. |

| | |
| --- | --- |
| ![The briefing](screenshots/briefing.png) | ![The day's scores](screenshots/scores.png) |
| **Briefing.** The original's four pages, in the panel's letters, scrolled up a pixel at a time, each round in another of its colours: yellow, pink, light green. | **The day's scores**, the keys and the credits, on white with the original's droid, as there. The top and worst scores start as the original's, 6809 and 6502. |
| ![The logo](screenshots/title.png) | |
| **Logo.** The original's, over the whole screen: the panel's rows show the window's character set for it. Then the round starts again. | |

## What is new compared with the other games here

### Fine scrolling under a fixed panel

The C64 version changes the VIC's vertical scroll register below its status
panel. The TED, the Plus/4's video chip, reads that register **once per
picture**, so writing it in the middle of the screen does nothing. That was
measured in VICE first: with the same character on every row, nothing moved.

What the TED does follow are two counters, and both can be written:

- `$FF1D`, the **line counter**, decides when the next row of characters is
  fetched.
- Bits 0–2 of `$FF1F`, the **row line counter**, decide which line of the
  characters is shown.

Writing only the row line counter looks like a shift if every row shows the
same characters. In fact it only **rotates** the lines within each row. That
took a test with a different character on every row to see. The two
together do move everything below, with the rows intact. At the start of the
last line of the gap under the panel, the interrupt sets:

```
$FF1D := 74 - s        ; the line counter set back by s
$FF1F := (6 - s) & 7   ; row line counter (bits 0-2) - one line later than
                       ; the obvious 7 - s, or each row's first line shows
                       ; the row above it
```

This moves the whole window down by `s` lines, `s` from 0 to 7. Below the
window, the line counter is put back to where it would have been, so the
picture ends where it always does. `tests/rowcheck.py` checks the result for
all eight positions. For each one it compares every line of the window on
VICE's screen with the characters in memory.

Moving rows down makes the top edge of the window move as well. The top
character row of the window is therefore cut: its cells get copies of their
characters with the top lines cleared, from the same pool the figures use. A
change of background colour exactly at that edge would have been simpler,
but on the TED it cannot be timed reliably. In the visible part of a line
the processor runs single-clocked, a timing loop overshoots the few usable
`$FF1E` positions, and the TED stops the processor before a row's first
line. So the deck's colour starts with the gap's last line, a line or two
above the window, and the window's edge comes from the cut characters.

The gap is three rows (6 to 8) and the window 16 rows (9 to 24), as high as
the original's and in the same place under the panel, to a pixel. The
interrupt stops twice in the gap: at line 55 for the deck's character set
and modes, and at line 71 for the scroll, so that it does not wait through
the gap.

### Figures over a hires deck

The decks are hires characters, as on the C64: each cell has a background
and one colour of its own, and walls and floors are drawn with single-pixel
lines. A droid on top of them would turn every line in its cells the
droid's colour. So the cells a figure covers switch to **multicolour**. On
the TED that is a bit in each cell's colour, while the rest of the window
stays hires. The deck character in such a cell is turned into multicolour
too (any pixel pair with something set becomes the cell's own colour). That
makes floor lines one pixel thicker inside the droid's cells and leaves
them their colour. The droid uses the two colours all multicolour cells
share: black and white.

### Pictures shifted in advance

A figure can start at four multicolour pixels inside a cell. Shifting its
16 lines at drawing time cost more than everything else in a picture put
together, as the sampling profiler (`tests/profile.py`) showed. So each
picture is shifted once into a 512-byte slot when it is needed: for the
droid types on a deck when you enter it, and for the player's droid when you
change host. A slot holds all four positions, the columns one under the
other with blank lines between them, and for each column which lines have
pixels. Drawing is then copying through a mask, and only into cells with
something in them.

The 001 has the original's turning dome, a slanted gap running round it, as
four extra slots.

### The transfer game, from the original and FreedroidClassic

The board is the original's, character for character: its screen and
characters (`$F1`–`$FE`, `$D0`, `$D1` of the deck's set, multicolour) were
read in VICE while the original's transfer game ran. How the parts are
laid out and how a pulse passes them follows
[FreedroidClassic](https://github.com/ReinhardPrix/FreedroidClassic)
(`src/takeover.c`), whose authors rebuilt Paradroid. It has the same parts
as the original's screen and the same panel texts (*Colour? 76*,
*Finish -52*). A side has four layers of twelve lines: where pulses go in,
two layers of parts, the connection to the column.

The work done for every line in every tick is in assembly
([xfer.s](xfer.s)): passing the pulses on, drawing a line again when it
changed, and the dashes moving along live wires, which are the two wire
characters turned by a pixel. Written in C, the game was 2 KB larger than
memory allowed. Laying the board out and the course of the game stay in C
([transfer.c](transfer.c)), and its state lives in the low memory at
`$0C68`, which only a disk load could disturb.

### The console

The ship's computer is the original's, read from it in VICE: its first
page (unit, ship, deck, alert) beside four symbols, which are its hires
sprites; the deck's names; and for each droid type its pages (entry,
class, height, weight, drive, brain, armament, sensors, notes). The
original builds those from a dictionary of words at `$C000`; they were
read off its screens instead, by driving its joystick through every page
of every type in the monitor and decoding the screen memory. The deck plan
is drawn the way the original's code does it: each block's number is the
character code, in the original's characters `$00`-`$1F` and colours,
hires, with the deck's blocks 3 to 41 across.

The console is a second overlay, `console`, in the same place as the
title's. It is loaded when fire is held at a console, and the explosions'
and lasers' pictures are made again afterwards. The pages about a droid come with its picture's file.

### The droids' pictures

The original draws a droid's picture from parts into eight sprites, two
side by side in four rows, with the right half often mirrored. The parts
are not stored as pictures anywhere, so [tools/pictures.py](tools/pictures.py)
works from what the original's own routine (`$3629`, type in `$58`) draws:
run in VICE's monitor once per droid type, its sprites saved each time.
The script turns them into [data/pictures.txt](data/pictures.txt), and
`mkdata.py` turns each into multicolour characters, six wide and up to
twelve high. Multicolour 1 is black, as on the C64; multicolour 2 and the
sprites' colour are set per picture. Cells with only the hires sprites'
pixels stay hires.

That is 24 files of up to three blocks, `p00`-`p23`. One is loaded for each
screen before a transfer, straight into picture 1's character set, which
the window shows for both pictures meanwhile; the text goes there too, in
the panel's letters. The words are the original's: its texts are made of
words from a dictionary at `$C000`, and its unit lines read *Unit type 476
- Maintenance robot*, *robot* for classes 1-4, *droid* for 5-8, *cyborg*
for 9 and *device* for the 001.

### The data, from the original's memory

The C64 game keeps everything in memory once it has loaded. A dump of its
64 KB, taken in VICE's monitor during a game, holds it all. The addresses
were found by tracing the game:

| | |
| --- | --- |
| `$E800` | 32 blocks of 4 × 4 characters |
| `$F100` | 16 decks, run-length coded, 64 × 16 blocks each |
| `$7800` | the deck character set |
| `$C800` | waypoints per deck. The third byte has a bit for each of eight directions a droid may leave in |
| `$6CC8` | lift stops: deck and shaft. The position stored is where the *window* is when the player stands on the lift, five blocks left of and two above the lift itself |
| `$EA00` | droid types: number, drive, weapon |
| `$F180` | the side view of the ship, run-length coded. Code `c` shows as `c + $80`, from the upper half of the deck's character set |
| `$F120`–`$F15F` | each deck's box in the side view: row, column, rows, columns. Lighting a deck turns codes `$80`.. into `$90`.. and back |
| `$6CB0`–`$6CC7` | the lift shafts: column, top row, length. The shaft ridden gets colour `$F9`, white multicolour |
| `$4E40`, `$6440` | sprites: the explosion (blocks `$39`–`$43`) and the twin lasers (`$91`–`$97`), turned into multicolour figures |
| `$7F88`–`$7FF7` | the transfer game's characters `$F1`–`$FE` (and `$D0`, `$D1`): wires, arrows, the colour changer, boxes, the lights |
| `$D000` | the briefing: per line its row and column, then the panel's codes. Capitals, `m` and `w` are two characters wide |

`tools/extract.py` writes all of it as text into [data/](data/): decks as
letters, characters as pictures. [tools/mkdata.py](tools/mkdata.py) turns
that into tables, adds the doors' half-open stages, and works out the lift
cabin's row for each deck from the shafts.

### Memory

The program, the tables and 23 slots of pre-shifted pictures fill the Plus/4
up to `$C000`. Above that sit two pictures with their character sets, the
panel's character set, and the block tables. The data that is only used
once at the start is linked into the very bytes where the slots begin, so
it is overwritten as soon as it has been copied.

### The title's sound

The original has no music, but its title has a sound of its own: a sweep
falling from 3.7 kHz to 120 Hz, a new pitch every picture, over and over,
and a low tone that wavers down from F3 to A2 and up again, then rests.
Both are triangles, at a third of the SID's volume. Its third voice plays
noise, which the original switches off and only uses for random numbers.

The tune as ripped (`Paradroid.sid`) is the game's own sound driver, set
the way the title leaves it; in x64sc the original's title shows the same
SID registers. [tools/sid.py](tools/sid.py), a small 6502 emulator, runs
that driver picture by picture and records what it writes to the SID;
[tools/sidmusic.py](tools/sidmusic.py) turns one round of its loop, 2.56
seconds, into [data/music.txt](data/music.txt): two voices, as the TED
has, as text, a pitch and a length per entry, as Stardew Pond keeps its
music. The pitches are not notes of a scale, so they stay hertz there, and
`mkdata.py` turns them into the TED's registers.

[music.s](music.s) plays them on the TED's two squares, at volume 3. It is
in the title's overlay with its data, and the engine's interrupt calls it
once a picture through a pointer while the title runs: the tempo is the
picture's, whatever the title is drawing. A sound effect would keep voice
2 meanwhile, as in Stardew Pond.

### The disk

The game runs from `build/paradroid.d64`. The title, with the briefing,
the scores page and the logo, is an **overlay**: [title.c](title.c), the
briefing's text and the logo are linked to run in the slots of the
pre-shifted pictures, all of them, as the title needs none, and written
to a file of their own, `title`. [paradroid.cfg](paradroid.cfg) puts the
overlay there, and ld65 writes it to `build/title.bin`. It is loaded for
each title, and the pictures are made again when a game starts. Loading
something more often, for a lift or a transfer, would cost too much time,
which is why the decks stay in memory.

With a **1551**, the Plus/4's own drive, a **fast loader** loads the files
while the picture and the game's interrupt go on: the title in about 3.7
seconds instead of 13 seconds of black screen with the KERNAL, a droid's
picture in about one. At the start the game asks the drive who it is (the
reply to `UI`: `CBM DOS V2.6 TDISK`) and sends it [drive1551.s](drive1551.s)
with the DOS's `M-W` commands, then starts it with `M-E`
([fastinit.c](fastinit.c), run once and then overwritten). From then on
the drive waits for a file's name on its parallel port, finds the file in
the directory, reads its sectors with the DOS's job queue and sends them a
byte at a time. Each byte is answered by the other side's strobe
([fastload.s](fastload.s)), so neither side depends on the other's
timing: not on interrupts, not on the TED taking cycles, not on how an
emulator times the drive. If the drive code does not answer, the KERNAL
loads from then on.

The console is not in memory: there is no room for its 2.9 KB. What made
it slow to load was the drive's motor, which the DOS stops when the drive
is idle and then waits two seconds for, every time: 3.3 seconds for the
console's twelve blocks. So whenever the player comes within five blocks
across and three up or down of a console, the game asks the drive for no
file at all, and the drive code only gives the DOS a read of the
directory to do, with nobody waiting for it: the motor starts, and keeps
going while the player stays near. The directory stays in the drive's
buffer, and is not read again for the load. Walking up to a console and
pressing fire at once, it loads in about 1.3 seconds; after two seconds
or more by it, in one.

The disk is written by [tools/d64.py](tools/d64.py) rather than `c1541`,
for the sectors' order: the DOS puts a file's sectors 10 apart on a track,
right for the KERNAL; the fast loader is ready for the next one sooner,
and with 8 apart the title loads a second faster. The fast loader's files
lie nearest the directory, the console on the very next track, then the
title, then the pictures; the program, which the KERNAL loads, comes after
them, 10 apart, and first in the directory.

Any other drive, a **1541** too, loads with the KERNAL. A fast loader for
the 1541 was tried: over the serial bus, with every bit answered, it
needed about 87 ms for a block, and the 1541's DOS needs a long lead
before it reads a sector, so the title still took over 7 seconds. Not
worth its memory on a Plus/4.

Loading with the KERNAL needs care in a program that uses all of memory:

- The screen is off and there is no interrupt of the game's own, because
  the KERNAL loads with the ROM switched in and its own interrupt handler.
- The deck's map lies at `$0400`–`$07FF`, where the KERNAL keeps some of
  its variables. A load test that filled ranges of that area with garbage
  first showed which bytes it really needs: only `$07D8`–`$07E7`. The game
  keeps them from the start and puts them back before each load. Then the
  deck's map is unpacked again.

The briefing scrolls up a pixel every second picture, the same way as the
deck: rows moved down by the two counters, and the window's top row made
of copies of its characters with their top lines cleared. For that, the
file brings a character set of its own: the 109 different characters of
the panel's letters it uses, put into picture 1's character set, which
both pictures show meanwhile. That leaves room for each picture's copies.
Each step draws the rows the window shows from the page's lines.

## What is not 1:1

- In the **transfer game**, how the parts are laid out and how long a
  pulse lasts follow FreedroidClassic (see above), not the original's
  code. Its look, the pulse counts and how the other side plays are the
  original's.
- The droids are **13 multicolour pixels wide** with their number in a dark
  band. The original's hires sprites are 24 pixels wide, and the Plus/4's
  characters have half the horizontal resolution.
- The deck's colour starts a line above the window's top edge (see
  above); in the original, the edge and the colour change are the same.
- **Sound** in the game is a handful of effects on one voice. The title's
  sound is the original's, but on squares instead of triangles.
- The **briefing**'s "C64 remote terminal" is a "Plus4 remote terminal"
  here.

## Files

| | |
| --- | --- |
| [paradroid.c](paradroid.c) | start, the main loop, transfer and lift hooks, pause |
| [deck.c](deck.c) | the ship, loading a deck, doors, colours, alert |
| [droids.c](droids.c) | the player, the droids, shots, energy, sound effects |
| [draw.c](draw.c) | the window, figures, the status panel |
| [transfer.c](transfer.c) | the transfer game: laying out the board, the game's course |
| [xfer.s](xfer.s) | the transfer board in assembly: laid out, pulses passed on, lines drawn, live wires moving; the introduction's letters and pictures |
| [title.c](title.c) | the overlay: the title's round of briefing, scores and logo |
| [lift.c](lift.c) | the side view and riding a lift |
| [console.c](console.c) | the overlay for the ship's computer: menu, droid enquiry, deck plan, ship |
| [music.s](music.s) | the title's sound, in its overlay |
| [engine.s](engine.s) | raster interrupt and fine scroll, the two pictures, building the window, figures, keyboard |
| [fastload.s](fastload.s), [drive1551.s](drive1551.s), [fastinit.c](fastinit.c) | the fast loader: the Plus/4's half, the 1551's half, and sending that to the drive |
| [game.h](game.h) | what the parts share |
| [paradroid.cfg](paradroid.cfg) | the memory layout |
| [build.sh](build.sh), [run.sh](run.sh) | building the program and the disk; starting VICE from the disk |
| [tools/extract.py](tools/extract.py) | the original's data out of a memory dump |
| [tools/pictures.py](tools/pictures.py) | the droids' pictures, the console's symbols and the title's logo out of the original |
| [tools/console.py](tools/console.py) | the console's pages about the droids, as read off the original's screens |
| [tools/mkdata.py](tools/mkdata.py) | `data/` into `build/gen/`, the briefing into the overlay's data, the pictures into `build/pics/` |
| [tools/sid.py](tools/sid.py), [tools/sidmusic.py](tools/sidmusic.py) | the original's sound driver run in a 6502 emulator; its title sound into `data/music.txt` |
| [tools/d64.py](tools/d64.py) | the disk image, with each file's sectors as far apart as its loader wants |
| [data/](data/) | decks, blocks, characters, waypoints, lifts, droids, panel, side view, briefing, transfer characters, droid pictures, console, logo, as text |
| [tests/](tests/) | headless VICE: screenshots, speed, profile, edges and rows, stress |

## Building and running

From the repository root, with any of the `.c` files active, `F5` builds and
starts it: the root's run script hands the build to [build.sh](build.sh)
and the start to [run.sh](run.sh). Without an editor:

```sh
sh paradroid/build.sh
xplus4 -autostart paradroid/build/paradroid.d64
```

The disk is made by `tools/d64.py`. The `.prg` alone does not run: it
needs the briefing from the disk. VICE's `xplus4` has a 1551 at device 8
by default; with `-drive8type 1541` the game loads with the KERNAL.

`tools/extract.py` is only needed to take the data out of the original
again: `python3 tools/extract.py ram.bin io.bin`, with the two dumps made in
VICE's monitor (`bank ram`, `save "ram.bin" 0 0000 ffff`, and `bank io`,
`save "io.bin" 0 d000 dfff`) during a game. Likewise `tools/sidmusic.py`
only makes `data/music.txt` again, from the ripped tune:
`python3 tools/sidmusic.py Paradroid.sid`.

## Tests

Everything in [tests/](tests/) runs VICE without a window, through its
monitor on a port of its own:

| | |
| --- | --- |
| `stress.py [s]` | random joystick for a while; fails if the game stops ticking |
| `speed.py keys s` | ticks per second while keys are held (16.7 is full speed) |
| `profile.py keys` | where the time goes, by symbol |
| `rowcheck.py` | every line of the window on screen against memory, for all eight fine positions |
| `edges.py` | the window's top edge for every fine position |
| `screens.py` | the screenshots in this README |

All of them start the game from the disk.
