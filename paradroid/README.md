# Paradroid for the Commodore Plus/4

**Paradroid** by Andrew Braybrook (Graftgold, published by Hewson, 1985) was
written for the C64, which has hardware sprites and a video chip that scrolls
smoothly under a fixed status panel. The Plus/4 has neither of those, and
this version is about how it manages anyway - as close to the original as
the machine allows.

The decks, their blocks and characters, the waypoints the droids walk, the
lifts, the droid types, the status panel, the side view of the ship, the
briefing, the droids' pictures, the console's pages, the colours, the sound
effects and the title's sound all come from the original, taken out of the
memory of the C64 game running in VICE. How it plays - driving, walls,
doors, bumps, the droids' ways, a game's start and end - was read from the
original's code and measured against it, often to the pixel and the tick.
The program around it is new, in C with the time-critical parts in
assembly. It loads from a disk, with a fast loader for both the 1551 and
the 1541.

![A deck: the influence device, a droid, a laser on its way](screenshots/deck.png)

**Controls**

| | |
| --- | --- |
| Joystick in either port, or the cursor keys | drive. The droid has inertia, as in the original |
| Fire (or `Space`, `CTRL` or `C=`) with a direction | lasers in that direction |
| Fire held, no direction | transfer mode: the player blinks, and touching a droid starts the transfer game |
| Fire held on a lift | the side view of the ship; up and down choose a deck on that shaft, letting go gets out there |
| Fire held at a console | the ship's computer: up and down choose a symbol, fire takes it (the first leaves); in the droid enquiry right and left turn the pages, up and down go through the droid types |
| `Run/Stop` | pause. In it: fire or `Run/Stop` go on, `Clr/Home` ends the game, `Help` freezes the picture ("Cheese") till `F7`, `F1`/`F2` colours or black and white |

On a PC keyboard in an emulator: the arrow keys, and Space or either Ctrl
key as fire (Yape puts the left Ctrl on `C=` and the right one on `CTRL`).
In Yape here only the **right Ctrl** key fires: Space and the left Ctrl do
not arrive in the game, though Yape's keyboard map has them where the game
looks (row 7, bits 4 and 5, beside `CTRL` at bit 2) - not found out why
yet. The original's briefing said "Plug your joystick into port 2" and
"Control is by joystick only"; here both ports and the keys work, and the
briefing says so.

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
  refill you up to it, at 5 points of score per point of energy. Below 8,
  the player flashes from white to black and back, with a warning sound.
- Touching a droid is a **bump**: the player is thrown back at twice its
  speed (at most its host's top speed; at 2 up and left if it stood
  still), the droid turns round and waits 16 ticks, and the stronger of
  the two hurts the weaker. It bumps once until the two are apart again.
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

**A game starts** as the original's: a page with the 001 and what it is
there for, "Game on!" in the panel, for three and a half seconds or until
fire. Then the 001 is beamed aboard, with the original's sound, at the
first waypoint of a deck between 4 and 7 - its top left; the droids start
on the waypoints after it - flashing as with low energy (it starts with
7 for that while) for 32 steps of two pictures, while the droids stand
still.

**A game ends** as the original's: the window full of static - its four
noise characters at random, black on white, going round and rolling down
the lines, with its noise - for 1.2 seconds, here for as long as the 999's
picture takes to load (the rolling is the interrupt's, so it goes on
meanwhile); then the 999 with "Transmission terminated" and its rising
tune, for 4.2 seconds.

The game runs in ticks of three pictures, as the original does: 16.7 a
second. The window scrolls a pixel at a time in any direction.

| | |
| --- | --- |
| ![Game on](screenshots/start.png) | ![Beamed aboard](screenshots/beam.png) |
| **A game's start.** The original's page, with its words and the 001's picture, in its purple. | **Beamed aboard.** The 001 flashing at the top left of the deck, as in the original, before the panel says *Mobile*. |
| ![Transfer](screenshots/transfer.png) | ![Lift](screenshots/lift.png) |
| **Transfer.** The original's board in its characters: yellow on the left, purple on the right, twelve lines each from the rail to the column of lights. The parts are the original's: dead ends, amplifiers that keep a pulse once they have one, colour changers, branches (one line in, two out) and gates (two in, both needed). A light shows the side whose line is live there and flickers when both are. You pick your colour (*Colour? 76*), then have ten seconds (*Finish -52*). As in the original, you get your droid's class plus 3 pulses and the other side its class plus 4. The side with more lights wins; a draw is a deadlock and is played again. Winning is *Complete*; losing from a host is *Rejected* and costs that host; losing as the bare 001 is *Burnt Out*, and the game is over. | **Lift.** The original's side view of the ship: its map and characters, multicolour in white, black and blue. As in the original, the lift's own shaft is white and the deck it is at is lit, by the original's rule for which characters of the deck's box change. |
| ![Your droid](screenshots/intro_you.png) | ![The other droid](screenshots/intro.png) |
| **Before a transfer.** As in the original, both droids first: your own, then the one you touched, with the original's pictures and words. | The pictures are the original's, taken from it by running its own drawing routine for each droid type (see below), and are files on the disk. |
| ![Console](screenshots/console.png) | ![Deck plan](screenshots/plan.png) |
| **Console.** The original's first page and its four symbols: leave, droid enquiry, deck plan, ship. | **Deck plan.** As the original draws it: a character per block, the character's code being the block's number, in its characters and the deck's colours; the energizers' symbol turns and the player's blinks. |
| ![Droid enquiry](screenshots/droids.png) | ![Its pages](screenshots/droids_more.png) |
| **Droid enquiry.** For the types up to your host's, with the original's picture. | Its pages are the original's, read off its screens for every type (`tools/console.py`) and stored with each picture's file. |

| | |
| --- | --- |
| ![The logo](screenshots/title.png) | ![The briefing](screenshots/briefing.png) |
| **Logo.** The original's, over the whole screen: the panel's rows show the window's character set for it. As in the original, the title starts with it. In its empty box at the bottom right, the port's credit, in the letters of the original's plates (those missing drawn in their style). | **Briefing.** The original's four pages, in the panel's letters, scrolled up a pixel at a time, each round in another of its colours: yellow, pink, light green. |
| ![The day's scores](screenshots/scores.png) | ![After a game](screenshots/highscore.png) |
| **The day's scores**, the keys and the credits, on white with the original's droid, as there. The top and worst scores start as the original's, 6809 and 6502. Then the round starts again with the logo. | **After a game** its score is the day's top or worst, if it is: the number alone, without the original's initials. |

Each of the title's screens is built with the picture off - only the
border shows, in the coming screen's colour - and switched on whole: the
logo takes some 16 pictures to build, a page about 7.

## As the original, measured

### Driving, walls and doors

The player drives as the original's does, read from its code in x64sc
([move.s](move.s)): the speed is a signed 8.8 number per axis; the
joystick adds 0.8125 a tick (0.8086 the other way), up to the host's top
speed by its drive; let go, it falls by 0.6875 a tick. The position moves
by the whole pixels of it, rounded up as there. So it starts with 1, 2, 3,
4, 5, 5, 6, 7 pixels a tick and rolls out with 7, 6, 5, 5, 4, 3, 3, 2, 1,
tick for tick as in the original.

Walls are characters there, not blocks: a character code from `$80` on. A
wall block is solid only in its two middle characters, a console often
only in its outermost row. Each tick, as there (`$39F9`, `$29C1`,
`$3849`): first the speed, then the walls - three points around the
player's character ((x + 7) / 8 across and down) for each way, looked at
only the way it drives (left and up also standing still); a wall there
stops it, its position set to 1 into its character driving right or
down, to the next character's start driving left or up - and only then
the move, by the speed's whole part. Driven into walls from one place on
the same deck in eight ways, the original and this stop on the same
pixel. The walls of each block are four bits per character row, kept in
the unused end of the block code tables at `$E800`.

The doors open as the original's (`$2A3E`, `$2A6D`, `$2B08`): when one of
those twelve points lies on a door's frame (the characters either side of
the door), the first tick only notes the door, and each tick after it
opens a row (or a column) more; untouched, it shuts one a tick. Driven at
a door, the player waits for it as long as in the original, to the tick.
A droid by a door opens it too; the original's droids touch it with the
points they look ahead at.

The droids choose their ways as the original's (from up to three ways of a
waypoint, each a third, or eight ticks' wait), at the original's speeds,
and like the original's they look ahead before each step: their
character and the next two. A wall there, a door not open yet, and they
wait two ticks. They do that near the player, where the doors open and
close; elsewhere the doors stay shut, and the droids go on through them.

The window follows the player across in steps of two pixels, in step with
its figure: the figures are of multicolour pixels, two wide, and the
player stands still in the middle of the window, as the original's
sprite. Measured against the original's screen (the same deck, the same
place, the energizer's dots found to the pixel), its deck stands a
character up and left of where the player's own coordinates put it: its
player's sprite is drawn a character right of and below its place, its
droids' sprites are not. So here too the window and the player's figure
are a character on, and where figures meet - bumps, shots, the droids'
aim, which the original leaves to its sprites' collisions - the player
counts where its figure is.

### The decks' colours

Every deck has its own colours, as in the original: each character
belongs to one of its colour classes, and each deck has one of eight
schemes, which give the classes their colours - read from the original
([data/colours.txt](data/colours.txt)). The scheme's first colour is the
window's background, its fourth the border's and the panel frame's. A
deck whose droids are gone has the dark scheme 7, and the ALERT console's
lights take the alert's colour. On the Plus/4 the colours are the nearest
of the TED's, the deck's characters' those of 0-7, as they turn
multicolour where figures are; the light green is a level darker than the
nearest, which left white figures and doors on it hard to see. The
console's deck plan, which shows the deck's own characters, has the
scheme too.

### Characters that move

The original animates some of the deck's characters itself, and so does
this (phases and speeds read from its lists, [data/anim.txt](data/anim.txt)):
the energizer's character `$14` turns a phase every three ticks (`$2605`,
list `$6C28`); the deck plan's symbol for an energizer is that same
character, and turns there too, while the plan's player blinks, on three
phases and off for one. Every other tick the energizer's dots, its
characters `$4C`-`$4F`, go round one character on (`$38C4`). The 001 has
the original's turning dome, a slanted gap running round it: measured in
x64sc, a hires pixel a tick over eight positions; here a multicolour
pixel every two ticks over four - the same speed.

### The transfer game

The board is the original's, character for character: its screen and
characters (`$F1`–`$FE`, `$D0`, `$D1` of the deck's set, multicolour) were
read in VICE while the original's transfer game ran. How the parts are
laid out and how a pulse passes them follows
[FreedroidClassic](https://github.com/ReinhardPrix/FreedroidClassic)
(`src/takeover.c`), whose authors rebuilt Paradroid. It has the same parts
as the original's screen and the same panel texts (*Colour? 76*,
*Finish -52*, always two digits). A side has four layers of twelve lines:
where pulses go in, two layers of parts, the connection to the column.

The work done for every line in every tick is in assembly
([xfer.s](xfer.s)): passing the pulses on, drawing a line again when it
changed, and the dashes moving along live wires, which are the two wire
characters turned by a pixel. Laying the board out and the course of the
game stay in C ([transfer.c](transfer.c)), and its state lives in the low
memory at `$0C68`, which only a disk load could disturb.

### The console

The ship's computer is the original's, read from it in VICE: its first
page (unit, ship, deck, alert) beside four symbols, which are its hires
sprites; the deck's names; and for each droid type its pages (entry,
class, height, weight, drive, brain, armament, sensors, notes). The
original builds those from a dictionary of words at `$C000`; they were
read off its screens instead, by driving its joystick through every page
of every type in the monitor and decoding the screen memory. The deck plan
is drawn the way the original's code does it: each block's number is the
character code, in the original's characters `$00`-`$1F`, hires, with the
deck's blocks 3 to 41 across.

The console is always in memory, so it opens at once: its code (1.7 KB)
at `$F400`, copied there at the start, its data in the program. The pages
about a droid come with its picture's file.

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
screen that shows a droid, straight into picture 1's character set, which
the window shows for both pictures meanwhile; the text goes there too, in
the panel's letters. The words are the original's: its unit lines read
*Unit type 476 - Maintenance robot*, *robot* for classes 1-4, *droid* for
5-8, *cyborg* for 9 and *device* for the 001.

### The sound effects

The game's sounds are the original's own effects, read from its sound
driver in x64sc ([tools/sfx.py](tools/sfx.py) into
[data/sfx.txt](data/sfx.txt)): 25 of them, each a record of a start
frequency, a step added each picture and periods, at the end of each of
which the step turns round or the frequency goes back to the start. The
original plays them on two channels, as the TED has two voices. Which
event starts which effect was read off its code: the beam at a game's
start, the shot by the host's weapon (the droids' shots are silent
there), a droid hit and destroyed, the player hit and destroyed, a bump,
the energizer for each unit of energy, "Lift" and the ride from deck to
deck, the deck cleared, the transfer's "Finish", "Complete", "Rejected",
"Burnt Out" and "Deadlock", the static and "Transmission terminated"
after a game; and on their own: the ship's hum every 32 ticks while the
second voice is free, with each deck's own periods, a warning while the
energy is below 8, and transfer mode every 8 ticks.

[sfx.s](sfx.s) plays them as the original's driver does, once a picture
from the interrupt, and turns the SID's frequency into the TED's register
each picture (a division: the TED's frequency is not linear in its
register; its lowest frequency leaves ten steps of it, not 24). The TED
has no envelope: an effect sounds while its gate and half its release
would. The TED's one volume is for both voices: the ship's hum, on the
second, plays at 2 instead of 6 while the first voice is quiet - the
original's is a soft triangle, the TED's a square, and at 6 it stood out
far more than the original's. Its noise is only on the second voice, so
the noisy effects go there. Played in a 6502 emulator, the original's
driver and the model `sfx.s` follows gave the same frequencies picture
for picture for the 22 effects compared. The player runs at `$FC00`,
copied there at the start; the effects' table is in the program, the
deck's hum's periods in the free end of the block code tables.

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
has, as text, a pitch and a length per entry. The pitches are not notes
of a scale, so they stay hertz there, and `mkdata.py` turns them into the
TED's registers. [music.s](music.s) plays them on the TED's two squares,
at volume 3, from the title's overlay; the engine's interrupt calls it
once a picture while the title runs.

### The pause

As the original's (`$3B7C`, read from its code): `Run/Stop` shows
*Pause*, the sound stops, and everything stands still but the deck's
turning characters, till fire or `Run/Stop`, which show *Continue*. In it,
as its briefing says, `Clr/Home` quits the game, straight to the title
(`$10D3`, no end of a game; here its score does not count), and the C64's `F7` is *Cheese*
(`$0B8A`): not even those characters turn, till its `F8`, fire, `Run/Stop`
or `Clr/Home`. The Plus/4 has no `F8`: the C64's `F7`/`F8` key is its
`Help`/`F7` key, so `Help` is *Cheese* here and `F7` goes back to the
pause, and the briefing names them so. Not in the briefing, also as in the
original (`$32B7`): `F1` shows *Colour*, `F2` *Blk-White*, and from the
pause's end on the decks are in scheme 0, the grey one, till `F1` again
(a deck without droids keeps its dark scheme 7).

### The data, from the original's memory

The C64 game keeps everything in memory once it has loaded. A dump of its
64 KB, taken in VICE's monitor during a game, holds it all. The addresses
were found by tracing the game:

| | |
| --- | --- |
| `$E800` | 32 blocks of 4 × 4 characters |
| `$F100` | 16 decks, run-length coded, 64 × 16 blocks each |
| `$7800` | the deck character set |
| `$0800` | each character's colour: the upper half its colour class, the lower its colour in the deck's scheme |
| `$6A44` | eight colour schemes, 12 colours each (classes 0-11; 12-15 are fixed). `$F160` gives each deck its scheme; a deck without droids has scheme 7 |
| `$C800` | waypoints per deck. The third byte has a bit for each of eight directions a droid may leave in. A game starts on the first |
| `$6CC8` | lift stops: deck and shaft. The position stored is where the *window* is when the player stands on the lift, five blocks left of and two above the lift itself |
| `$EA00` | droid types: number, drive, weapon |
| `$F180` | the side view of the ship, run-length coded. Code `c` shows as `c + $80`, from the upper half of the deck's character set |
| `$F120`–`$F15F` | each deck's box in the side view: row, column, rows, columns. Lighting a deck turns codes `$80`.. into `$90`.. and back |
| `$6CB0`–`$6CC7` | the lift shafts: column, top row, length. The shaft ridden gets colour `$F9`, white multicolour |
| `$4E40`, `$6440` | sprites: the explosion (blocks `$39`–`$43`) and the twin lasers (`$91`–`$97`), turned into multicolour figures: a run of hires pixels gets half as many multicolour ones about its middle, so the bolts stay thin, and the vertical one is smoothed and keeps its tips in 16 of its 21 lines |
| `$7F88`–`$7FF7` | the transfer game's characters `$F1`–`$FE` (and `$D0`, `$D1`): wires, arrows, the colour changer, boxes, the lights |
| `$6C28` | the animated characters: the energizer's, the plan's player; and at `$7BD0` the static's |
| `$C610` | the sound effects' records, their instruments at `$EAA0` |
| `$D000` | the briefing: per line its row and column, then the panel's codes. Capitals, `m` and `w` are two characters wide |

`tools/extract.py` writes most of it as text into [data/](data/): decks
as letters, characters as pictures. [tools/mkdata.py](tools/mkdata.py)
turns that into tables, adds the doors' half-open stages, and works out
the lift cabin's row for each deck from the shafts.

## On the Plus/4

### Fine scrolling under a fixed panel

The C64 version changes the VIC's vertical scroll register below its status
panel. In VICE, writing the TED's (`$FF06`) in the middle of the screen
does nothing: VICE reads it once per picture. Yape, whose TED is the
closer one to the real chip, does follow it there. What both follow are
two counters, and both can be written:

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
picture ends where it always does: in line 202 it is set to 202. The TED
ends the picture's fetching only on a line that starts as 203; set
straight to 203 within the line, as it first was, that line is skipped,
the fetching goes on through the border, and the next picture starts with
the row line counter wrong, the panel already. VICE did not mind, Yape
showed garbage from the first scrolled picture on.

Setting the line counter back has one more catch: set to the line the
raster interrupt compares with, the TED raises the interrupt again at
once. For s = 3 the counter goes to 71, the very line of the interrupt
doing it; the rest of the picture's interrupts then came one late, and
the next panel was drawn on the gap's colour, a flicker every eighth line
of scrolling. So the next interrupt's line is set before the counter.
Yape does this as the chip does; VICE does not raise it.

The panel's registers for the next picture (its character set, 40
columns, its colours) are set in the vertical blank, at line 252, by an
interrupt of their own. Set right under the window, as they first were,
VICE drew a pixel of the window's colour into the border where each was
written - a dot of "snow" under the window in every picture.

`tests/rowcheck.py` checks the result for all eight positions in VICE,
`tests/yape_rowcheck.py` in Yape. For each one they compare every line of
the window on the screen with the characters in memory.

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
interrupt stops twice in the gap: at its first line for the deck's
character set and modes, and at line 71 for the scroll, so that it does
not wait through the gap. The gap's cells are blank in the deck's
characters but not in the panel's: switched a few lines into the gap, as
it was, the switch came late now and then, and a short dashed line of the
panel's characters showed in the gap (`tests/yape_gap.py` finds it).

The briefing scrolls the same way, up a pixel a tick, as the original's
(measured in x64sc: 16.7 pixels a second), and two while the joystick is
held down, as there. For that, its file brings a character set of its
own: the 109 different characters of the panel's letters it uses, put
into picture 1's character set. Between rows only the top row is made
again, the fine scroll moves the rest. Each step is made as soon as the
last one shows and handed to the interrupt in the picture before its
turn, so it shows exactly every third picture; a new row of characters is
made in assembly ([briefrows.s](briefrows.s)) in under a picture.
`tests/yape_brief.py` measures how far the page moves in each picture.

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

### Where the time goes

`tests/chprof.py` counts the cycles of every instruction of the last few
pictures from VICE's CPU history, per routine: unlike sampling through the
monitor, which stops the machine at moments of its own and so over- or
under-counts whole routines, that is exact. With a deck full of droids and
the fire button held, drawing the window takes about half of the time,
the game itself about a seventh, and a good third is left over; while the
window scrolls, building its new rows takes the most.

Everything done for each droid or door every tick is in assembly: the
droids' choices at their waypoints and their steps
([engine.s](engine.s)), looking ahead, the walls, the doors, a droid
touching the player and the block under a point ([move.s](move.s)), and
putting the droids, their explosions and the shots into the window
([figs.s](figs.s)). A droid looks ahead only when it has entered a new
character or turned, not every tick. The doors look only at the droids
that can be by a door on the screen, two to four usually, not at all of
them.

### Memory

The program, the tables and 23 slots of pre-shifted pictures fill the
Plus/4 up to `$C000`. Above that sit two pictures with their character
sets, the panel's character set, the block tables, and at `$F000` the
engine's tables and the code of the console and the figures. The data and
code used only once at the start - the fast loader's set-up and the talk
with the drive, the panel's first drawing, the engine's tables, the
character sets' first copies - are linked into the very bytes where the
slots begin, so they are overwritten as soon as they have done their work
(`INITCODE` comes right after the data: the slots start at the data's
first byte). The code copied above `$F000` and to `$FC00` comes from there
too. The title is an overlay in the slots (below).

## The disk and the fast loaders

The game runs from `build/paradroid.d64`. The title, with the briefing,
the scores page and the logo, is an **overlay**: [title.c](title.c), the
briefing's text and the logo are linked to run in the slots of the
pre-shifted pictures, all of them, as the title needs none, and written
to a file of their own, `title`. [paradroid.cfg](paradroid.cfg) puts the
overlay there, and ld65 writes it to `build/title.bin`. It is loaded for
each title, and the pictures are made again when a game starts. The decks
stay in memory: loading for a lift or a transfer would cost too much time.

With a **1551** or a **1541**, a **fast loader** loads the files while the
picture and the game's interrupt go on. At the start the game asks the
drive who it is (the reply to `UI`: `CBM DOS V2.6 TDISK` for a 1551,
`... 1541` for a 1541) and sends it its drive code with the DOS's `M-W`
commands, then starts it with `M-E` ([fastinit.c](fastinit.c), run once
and then overwritten). From then on the drive waits for a file's name,
finds the file in the directory, reads its sectors and sends them over.
The Plus/4's half for that drive is copied to the end of the program's
memory at the start ([fastload.s](fastload.s) calls it there); there is
room for one of them, not both. If the drive code does not answer, the
KERNAL loads from then on.

- **1551** ([drive1551.s](drive1551.s), [fastload51.s](fastload51.s)):
  the sectors read with the DOS's job queue, sent over its parallel port
  a byte at a time, each answered by the other side's strobe, so neither
  side depends on the other's timing.
- **1541** ([drive1541.s](drive1541.s), [fastload41.s](fastload41.s)):
  over the serial bus, two bits at a time on CLK and DATA, clocked by the
  Plus/4 with ATN: at each change of ATN the drive puts the next pair on
  the lines, and the Plus/4 reads it a fixed time later. That time is
  the only timing there is, and interrupts or the TED's stolen cycles only
  make it longer, so the picture can stay on. ATN is wired into the
  1541's DATA line through an acknowledge bit, which the drive code turns
  with every change. Between two changes of ATN the drive has only a
  table lookup, a shift and a mask to do.

  The 1541's DOS is not used for the sectors: it needed 50 ms after each
  one (decoding it, taking the next job) before it could read the next.
  The drive code has the drive to itself, its interrupt off: it turns the
  motor on (and off after a few idle seconds), moves the head, sets the
  bit rate of the track's zone, waits for the sector's header after a
  SYNC, and reads its data block as GCR into the very place the DOS uses,
  `$01BB`–`$02FF`, the top of the stack's page and the command buffer.
  It is decoded there in place, five bytes to four, with the checksum
  checked: 18 ms. Read, decoded and sent (55 ms), a sector takes about 95
  ms. Yape, whose TED is closer to the real one, has a true 1541 but no
  1551, so this is the loader it uses.

The title (10 KB) loads in about 4.5 seconds with a 1541 and 6.4 with a
1551, measured in VICE with `tests/loadtime.py` (7.0 seconds with a 1541
when the DOS still read its sectors); with the KERNAL a 1541 takes much
longer, with a black screen.

What makes a load slow is the drive's motor, which the DOS stops when the
drive is idle and then waits two seconds for, every time. So whenever the
player comes within five blocks across and three up or down of a console,
whose droid enquiry loads the droids' pictures, and when a game ends, the
game asks the drive for no file at all, and the drive code only gives
the DOS a read of the directory to do, with nobody waiting for it: the
motor starts, and keeps going while the player stays near. The directory
stays in the drive's buffer, and is not read again for the load.

The disk is written by [tools/d64.py](tools/d64.py) rather than `c1541`,
for the sectors' order: the DOS puts a file's sectors 10 apart on a track,
right for the KERNAL. With the fast loader, a 1541 is ready for the next
sector 10 on (about 9.5 ms a sector): 10 apart, the title takes 4.3
seconds instead of 10.9 with 8. A 1551 would rather have 8 (5.2 seconds
instead of 6.0); one disk serves both, and 10 is the better one for the
two together. The fast loader's files lie nearest the directory, the
title on the very next track, then the pictures; the program, which the
KERNAL loads, comes after them, 10 apart, and first in the directory.

Loading with the KERNAL needs care in a program that uses all of memory:

- The screen is off and there is no interrupt of the game's own, because
  the KERNAL loads with the ROM switched in and its own interrupt handler.
- The deck's map lies at `$0400`–`$07FF`, where the KERNAL keeps some of
  its variables. A load test that filled ranges of that area with garbage
  first showed which bytes it really needs: only `$07D8`–`$07E7`. The game
  keeps them from the start and puts them back before each load. Then the
  deck's map is unpacked again.

## What is not 1:1

- In the **transfer game**, how the parts are laid out and how long a
  pulse lasts follow FreedroidClassic (see above), not the original's
  code. Its look, the pulse counts and how the other side plays are the
  original's.
- The droids are **13 multicolour pixels wide** with their number in a dark
  band. The original's hires sprites are 24 pixels wide, and the Plus/4's
  characters have half the horizontal resolution.
- The TED has no sprites: a cell a figure is in turns multicolour, and the
  **deck under a figure** with it, a hires pixel pair with anything set
  becoming a whole multicolour pixel. Around a droid, lines a pixel wide
  (a door's, a console's) are two wide; in the original the deck shows
  through its sprite's gaps as it is.
- The player's **colour** is the TED's second multicolour colour, which
  the droids' numbers have too: when the player flashes (low energy, a
  game's start), so do they. For the same reason the player keeps its
  white in transfer mode, where the original's turns dark grey.
- The droids look ahead, and so open **doors**, only near the player; in
  the original they do so all over the deck. A droid near a door opens it
  here rather than touching its frame.
- The deck's colour starts a line above the window's top edge (see
  above); in the original, the edge and the colour change are the same.
- **Colours**: the nearest of the TED's, the light green a level darker
  (see above); some, like the red and the light green, look a little
  different from the C64's.
- **Sound**: the effects and the title's sound are the original's, but on
  the TED's squares instead of the SID's triangles, saws and pulses, and
  without its envelopes; the TED's noise and lowest notes are higher than
  the SID's.
- The droids' **pictures** (console, transfer, the start page, the end)
  start two lines lower than the original's: the heading's letters are two
  rows tall, and the original's picture, a sprite over them, starts in
  their lower row. Characters cannot share a cell that way.
- They are files on the disk: the 999's after a game takes a second or
  two to load, during which the static goes on (1.2 seconds in the
  original). Between the start page and the deck, the window is empty for
  about four pictures, while the deck is drawn the first time.
- The player's **explosion** at a game's end is ours, shorter than the
  original's several explosions around it.
- The day's **scores** have no initials.
- The **briefing**'s "C64 remote terminal" is a "Plus4 remote terminal"
  here, and its keys for the pause's *Cheese* are `Help` and `F7` for the
  C64's `F7` and `F8` (see above).
- In the **title**, the original also takes `F1`/`F2` (colours, black and
  white) and `F5`/`F6` (the volume, 0-15, shown in the panel). Here only
  the pause takes `F1`/`F2`, and there is no volume.

## Files

| | |
| --- | --- |
| [paradroid.c](paradroid.c) | start, the main loop, transfer and lift hooks, pause, a game's end |
| [deck.c](deck.c) | the ship, loading a deck and finding its doors |
| [droids.c](droids.c) | the player, the droids, shots, hits, bumps, energy |
| [draw.c](draw.c) | the window, the player's figure, the status panel |
| [transfer.c](transfer.c) | the transfer game: laying out the board, the game's course; the droids' pictures |
| [xfer.s](xfer.s) | the transfer board in assembly: laid out, pulses passed on, lines drawn, live wires moving; the introduction's letters and pictures |
| [title.c](title.c) | the overlay: the title's round of logo, briefing and scores; a game's start page |
| [lift.c](lift.c) | the side view and riding a lift, in the console's overlay |
| [console.c](console.c) | the ship's computer, an overlay kept packed (with lift.c): menu, droid enquiry, deck plan, ship |
| [music.s](music.s) | the title's sound, in its overlay |
| [briefrows.s](briefrows.s) | the briefing's text into the window's rows, in the title's overlay |
| [sfx.s](sfx.s), [sfxcall.s](sfxcall.s) | the original's sound effects: the player at `$FC00`, starting them, the beam-in |
| [unpack.s](unpack.s), [exodecrunch.s](exodecrunch.s) | unpacking what exomizer packed: the decks' maps, all at once into the droid types' slots when a deck is entered; the console's and lift's overlay into the slots, which are made again afterwards |
| [move.s](move.s) | the player's driving, the walls, the doors, the droids looking ahead, bumps, the decks' colours |
| [figs.s](figs.s) | the droids, their explosions and the shots into the window, run at `$F400` |
| [engine.s](engine.s) | raster interrupt and fine scroll, the two pictures, building the window, figures, the droids' ways, keyboard, the animated characters |
| [fastload.s](fastload.s), [fastload51.s](fastload51.s), [fastload41.s](fastload41.s), [drive1551.s](drive1551.s), [drive1541.s](drive1541.s), [fastinit.c](fastinit.c) | the fast loaders: what the Plus/4's halves share, its half for a 1551 and for a 1541, the drives' halves, and sending the right one to the drive; with the rest of the start |
| [game.h](game.h) | what the parts share |
| [paradroid.cfg](paradroid.cfg) | the memory layout |
| [build.sh](build.sh), [run.sh](run.sh), [run-yape.sh](run-yape.sh) | building the program and the disk; starting VICE or Yape from the disk |
| [tools/extract.py](tools/extract.py) | the original's data out of a memory dump |
| [tools/pictures.py](tools/pictures.py) | the droids' pictures, the console's symbols and the title's logo out of the original |
| [tools/console.py](tools/console.py) | the console's pages about the droids, as read off the original's screens |
| [tools/mkdata.py](tools/mkdata.py) | `data/` into `build/gen/`, the briefing into the overlay's data, the pictures into `build/pics/` |
| [tools/sfx.py](tools/sfx.py) | the original's sound effects out of a memory dump |
| [tools/sid.py](tools/sid.py), [tools/sidmusic.py](tools/sidmusic.py) | the original's sound driver run in a 6502 emulator; its title sound into `data/music.txt` |
| [tools/d64.py](tools/d64.py) | the disk image, with each file's sectors as far apart as its loader wants |
| [tools/yape.patch](tools/yape.patch) | Yape's changes for the gamepad and the tests |
| [data/](data/) | decks, blocks, characters, colours, animated characters, waypoints, lifts, droids, panel, side view, briefing, transfer characters, droid pictures, console, logo, sound, as text |
| [tests/](tests/) | headless VICE and Yape: screenshots, speed, profile, edges and rows, stress, the title and a game's start |

## Building and running

From the repository root, with any of the `.c` files active, `F5` builds and
starts it: the root's run script hands the build to [build.sh](build.sh)
and the start to [run.sh](run.sh). Without an editor:

```sh
sh paradroid/build.sh
xplus4 -autostart paradroid/build/paradroid.d64
```

The build needs [exomizer](https://bitbucket.org/magli143/exomizer) 3.1
besides cc65 (`$EXOMIZER`, else beside cc65's tools): it packs what the
game keeps packed in memory. [unpack.s](unpack.s) unpacks it with
exomizer's own unpacker, [exodecrunch.s](exodecrunch.s), changed only
where it says so.

The `.prg` alone does not run: it needs the title and the pictures from
the disk. VICE's `xplus4` has a 1551 at device 8 by default; with
`-drive8type 1541` it has a 1541, and the game loads with the fast loader
for that.

The second F5 configuration, "... in Yape", starts it in **Yape** instead
([run-yape.sh](run-yape.sh); `sh paradroid/run-yape.sh` without an
editor). Yape gets the disk image with its full path (it looks for a
relative one in its own folder), and the gamepad set up: Yape takes a game
controller's right stick and A as the joystick, so for the Xbox One S
controller over Bluetooth the script hides the Steam Deck's own
controller from SDL, hands SDL a mapping that gives the left stick as the
right one too, and sets Yape's "active joy for keyset" to NONE, which puts
a single controller on both joystick ports. It takes a Yape built with
[tools/yape.patch](tools/yape.patch) if there is one (the script says how
to build it): Yape took one of SDL's events a frame, and a gamepad's
stream of axis events left the stick seconds behind; with all of them a
frame the stick arrives in about 30 ms (`tests/yape_joylag.py` measures
that against SDL itself, with someone moving the stick). The patched Yape
also leaves the controller's other buttons alone (`YAPE_PADKEYS=off`):
Yape's own B steps the active joystick on (BOTH leaves it on none), LB
types RUN, RB opens its menu. The patch also has the tests' hooks.

`tools/extract.py` is only needed to take the data out of the original
again: `python3 tools/extract.py ram.bin io.bin`, with the two dumps made in
VICE's monitor (`bank ram`, `save "ram.bin" 0 0000 ffff`, and `bank io`,
`save "io.bin" 0 d000 dfff`) during a game. Likewise `tools/sidmusic.py`
only makes `data/music.txt` again, from the ripped tune
(`python3 tools/sidmusic.py Paradroid.sid`), and `tools/sfx.py` makes
`data/sfx.txt` again from the same memory dump
(`python3 tools/sfx.py ram.bin`).

## Tests

Everything in [tests/](tests/) runs VICE without a window, through its
monitor on a port of its own:

| | |
| --- | --- |
| `stress.py [s]` | random joystick for a while; fails if the game stops ticking |
| `speed.py keys s` | ticks per second while keys are held (16.7 is full speed) |
| `profile.py keys` | where the time goes, by symbol, sampled (rough) |
| `chprof.py keys` | where the time goes, by symbol, every cycle of the last pictures |
| `loadtime.py [drive]` | how long the title takes to load, with a 1551 or a 1541 |
| `rowcheck.py` | every line of the window on screen against memory, for all eight fine positions |
| `edges.py` | the window's top edge for every fine position |
| `screens.py` | the screenshots in this README |

All of them start the game from the disk.

The `yape_*.py` tests run **Yape** the same way, as its TED is closer to
the real one than VICE's: a build of Yape from its sources
([yapesdl](https://github.com/calmopyrin/yapesdl)) in
`~/.cache/paradroid/yapesdl` with [tools/yape.patch](tools/yape.patch):
SIGUSR1 enters its monitor, which reads its commands from stdin, and
SIGUSR2 saves the TED's picture ([tests/yape.py](tests/yape.py)). Yape has
no true 1551; with a disk image it uses a true 1541. The program itself
loads with the KERNAL there, slowly; the tests run Yape without its speed
limit.

| | |
| --- | --- |
| `yape_boot.py [s] [warp]` | the start from the disk: registers and a screenshot every five seconds |
| `yape_play.py [s] [seed]` | the title, fire, a random joystick; fails if the game stops ticking |
| `yape_rowcheck.py` | `rowcheck.py` in Yape |
| `yape_xfer.py [n]` | transfers in Yape, their droids' pictures loaded with the fast loader |
| `yape_brief.py [n]` | the briefing in Yape, n pictures in a row: how far it moves in each |
| `yape_title.py` | the title's scores page in Yape, with its picture |
| `yape_start.py [logo]` | a game's start in Yape (fire on the briefing, or on the logo), 400 pictures in a row: the start page, the beam, "Mobile" |
| `yape_panel.py [n] [title\|down]` | the status panel in Yape, n pictures in a row: the ones it differs in (a flicker) |
| `yape_gap.py [n]` | the gap between panel and window in Yape, n pictures in a row: anything in it |
| `yape_snow.py [n] [label ...]` | the window's bottom edge in Yape, n pictures in a row: stray pixels there (with labels, those routines switched off) |
| `yape_joylag.py [s]` | how late the gamepad's stick arrives in Yape, against SDL itself (move the stick when READY shows) |
| `yape_pads.py` | the gamepads Yape sees, in its order (which one is on which joystick port) |
