# Paradroid for the Commodore Plus/4

**Paradroid** by Andrew Braybrook (Graftgold, published by Hewson, 1985) was
written for the C64, which has hardware sprites and a video chip that scrolls
smoothly under a fixed status panel. The Plus/4 has neither of those, and
this version is about how it manages anyway.

The decks, their blocks and characters, the waypoints the droids walk, the
lifts, the droid types, the status panel and the side view of the ship all
come from the original. `tools/extract.py` took them out of the memory of
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
| Fire held at a console | the deck plan; left or right switches to the droid enquiry |
| `Run/Stop` | pause |

## The game

You are the 001, an influence device beamed onto a freighter whose droids
have run wild. You can shoot them, or take one over by winning the
**transfer game** against it, which makes it your host. A host is stronger
than the bare device, but it burns out in time, so you have to keep moving
on to new ones. Energizers recharge you. Destroying droids raises the
**alert**, which turns the ALERT consoles from green through yellow to red
and makes the armed droids shoot more often. When a deck has no droids left,
its lights go out. When the whole ship is dark, the next ship of the fleet
follows, with droids a class higher.

The game runs in ticks of three pictures, as the original does: 16.7 a
second. The window scrolls a pixel at a time in any direction.

| | |
| --- | --- |
| ![Transfer](screenshots/transfer.png) | ![Lift](screenshots/lift.png) |
| **Transfer.** Twelve wires per side. Some are dead ends, and some fork and feed a neighbour's dead end. A pulse lights its wire for a while and claims the lights it reaches, unless the other side holds the same light at that moment. When the time runs out, the side with more lights wins. A draw is a deadlock and is played again. You pick your side first. Each side gets 3 pulses, plus one for every third class of its droid. | **Lift.** The original's side view of the ship, with its own characters. The shaft is drawn in, and the cabin sits at the selected deck. |
| ![Deck plan](screenshots/plan.png) | ![Droid enquiry](screenshots/droids.png) |
| **Deck plan.** One character per block: walls, doors, lifts, energizers, consoles, the droids, and the player blinking. | **Droid enquiry.** As in the original, only for droid types up to the class of your host. Written in the panel's own two-line letters. |

![Waiting for a game](screenshots/title.png)

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
last line of the gap row under the panel, the interrupt sets:

```
$FF1D := 58 - s        ; the line counter set back by s
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
line. So the gap under the panel has the deck's colour, and the window's
edge comes from the cut characters alone.

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
| `$F180` | the side view of the ship |
| `$4E40`, `$5440`… | sprites: the twin lasers (`$91`–`$97`) and the explosion (`$39`–`$43`), turned into multicolour figures |

`tools/extract.py` writes all of it as text into [data/](data/): decks as
letters, characters as pictures. [tools/mkdata.py](tools/mkdata.py) turns
that into tables, adds the doors' half-open stages, and works out the lift
cabin's row for each deck from the shafts.

### Memory

The program, the tables and 21 slots of pre-shifted pictures fill the Plus/4
up to `$C000`. Above that sit two pictures with their character sets, the
panel's character set, and the block tables. The data that is only copied
once at the start is linked into the very bytes where the slots begin, so
it is overwritten as soon as it has been copied.

## What is not 1:1

- **Rules and numbers** for energy, damage, transfer pulses and points are
  this version's own. The original's were not traced.
- The droids are **13 multicolour pixels wide** with their number in a dark
  band. The original's hires sprites are 24 pixels wide, and the Plus/4's
  characters have half the horizontal resolution.
- The **gap under the panel** has the deck's colour, not the panel
  surround's (see above).
- **Sound** is a handful of effects on one voice.

## Files

| | |
| --- | --- |
| [paradroid.c](paradroid.c) | start, the main loop, transfer and lift hooks, pause |
| [deck.c](deck.c) | the ship, loading a deck, doors, colours, alert |
| [droids.c](droids.c) | the player, the droids, shots, energy, sound effects |
| [draw.c](draw.c) | the window, figures, the status panel |
| [transfer.c](transfer.c) | the transfer game |
| [lift.c](lift.c) | the side view and riding a lift |
| [console.c](console.c) | the deck plan and the droid enquiry |
| [engine.s](engine.s) | raster interrupt and fine scroll, the two pictures, building the window, figures, keyboard |
| [game.h](game.h) | what the parts share |
| [paradroid.cfg](paradroid.cfg) | the memory layout |
| [tools/extract.py](tools/extract.py) | the original's data out of a memory dump |
| [tools/mkdata.py](tools/mkdata.py) | `data/` into `build/gen/` |
| [data/](data/) | decks, blocks, characters, waypoints, lifts, droids, panel, side view, as text |
| [tests/](tests/) | headless VICE: screenshots, speed, profile, edges and rows, stress |

## Building and running

From the repository root, with any of the `.c` files active, `F5` builds and
starts it: the root's run script hands the build to [build.sh](build.sh).
Without an editor:

```sh
sh paradroid/build.sh
xplus4 paradroid/build/paradroid.prg
```

`tools/extract.py` is only needed to take the data out of the original
again: `python3 tools/extract.py ram.bin io.bin`, with the two dumps made in
VICE's monitor (`bank ram`, `save "ram.bin" 0 0000 ffff`, and `bank io`,
`save "io.bin" 0 d000 dfff`) during a game.

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
