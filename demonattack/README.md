# Demon Attack for the Commodore Plus/4 and C16

A conversion of **Demon Attack** for the Atari 2600 (Imagic, 1982). All ten game
variants, one or two players, the splitting demons, the small ones that
dive at the cannon, both difficulty switches, and the original's sounds.

It comes in two forms built from the same source: a **PRG** for the
Plus/4, and a **32 KB cartridge** that also runs on the C16 with its
16 KB of RAM.

This repository also has a [Phoenix clone](../phoenix/README.md): the
Atari 2600 Phoenix on the Plus/4, built from measurements of the original,
with some parts still reconstructed. This conversion behaves like the original frame for
frame: the same rules, speeds, patterns and sounds. That is checked
automatically against the original running in an emulator. Getting there
meant solving problems the Phoenix clone could avoid, and those solutions are what
this README is mostly about.

![The demo, with the game's name at the top](screenshots/title.png)

**Controls**

| | |
| --- | --- |
| Joystick in port 1 (player 1) or port 2 (player 2) | left/right to move, button to fire |
| Keyboard | cursor left/right, `Space` to fire, for whichever player's turn it is |
| `F1` | the 2600's *Game Reset* switch: start a game |
| `F2` | *Game Select*: step through the ten variants |
| `F3` / `Help` | the left / right *difficulty* switch, A or B |
| `Run/Stop` | the PRG: leave (cold start); the cartridge: start over |

In the demo, pressing fire starts a game too.

## The ten games

| Game | |
| --- | --- |
| 1 | one player |
| 2 | two players, taking turns |
| 3, 4 | as 1 and 2, with **tracer shots**: the shot follows the cannon left and right on its way up |
| 5–8 | as 1–4, starting at a later, harder wave |
| 9 | two players at **one cannon**, control changing hands every few seconds |
| 10 | as 9, with tracer shots |

The difficulty switch changes one thing. On **A**, a demon deciding where to
go always knows which side of it the cannon is on. On **B** it gets that
wrong half the time when the two are close.

![A new wave: the demons form out of scattered points](screenshots/materialising.png)
![Hit: the screen flashes](screenshots/hit.png)

## The hall of fame page

When a game ends, the game stops on a still page before it goes back to the
demo. The page shows what a photo needs in order to count as proof of a
score:

- the game's name and the original's maker;
- the score, or both scores in a two-player game;
- the variant and the difficulty it was played at;
- the best score since the machine was switched on.

Fire, `Space` or `F1` goes on into the demo, at the point where the
original would be.

![The page at the end of a game (the score here is an example)](screenshots/gameover.png)

The page is honest, not tamper-proof: anyone with an emulator's monitor can
set a score.

The original's demo shows the IMAGIC logo at the top. The logo is not a
picture of its own: at power-on the game sets player 1's score to the
"digits" AB CD EA, whose shapes spell IMAGIC. That score is left alone in
memory here, and only the drawing shows something else in its place. Four
lines take turns there: the name, the original's maker, who converted it, and
how to start. After a game, the last score takes a turn as well. All text
uses the machine's own character ROM: 64 characters are copied out of it
once at start-up, and both the demo lines and the page take their letters
from that copy.

![The start hint in the demo](screenshots/start.png)

## What is new compared with the Phoenix clone

The Phoenix clone gets around the missing sprites with finished blocks of
characters, one colour per cell, and speeds counted in clock ticks. It
accepts the limits of all three, and its README lists them. Demon Attack
does not allow that:

- every line of a demon has its own colour;
- whether a shot hits is decided pixel by pixel, the way the 2600's video
  chip sees it;
- the timing has to be the original's exactly, or the game cannot be
  compared with the original.

### A colour on every line

A TED character cell has four colours, and two of them come from registers
that apply to the whole screen. So a raster interrupt changes those two
registers while the picture is being shown. Each picture carries a list of
register writes, each tied to a raster line, and the interrupt works
through it.

The trick that makes one write per line enough is alternating. A demon's
odd lines use one register and its even lines the other. So each register
can be changed during the line where only the other one is on screen,
without any race against the beam. The interrupt is requested two lines
ahead, because getting into the handler takes more than a line, and then it
waits for its line.

One line in eight defeats this. On the first line of every character row the
TED fetches the row's codes and holds the CPU until late in the line, so a
register write there comes too late. Those lines take their colour from the
colour cells instead, the third colour a multicolour cell has. Every
character therefore has a fixed pattern of which bit pairs each line may
use: `%11` on line 0, `%01` on odd lines, `%10` on even ones. A demon is
drawn through that mask. The ground's colour gradient uses the same list.

The price is about 15 % of the CPU: through each demon's band the interrupt
waits from one write to the next.

### Two complete screens

There are two character sets and two screens: on the Plus/4 at
`$C000`–`$DFFF`, on the cartridge at `$0800`–`$27FF`. The game
draws into the hidden one, and the interrupt swaps them at the bottom of the
picture once it is finished, so nothing is ever seen half-drawn. Every
list below exists once per screen.

### Characters handed out per picture

The Phoenix clone gives each figure a fixed block of characters. Here the characters
are pooled instead:

- **Short-lived figures** (shots, the cannon's laser, debris) get characters
  from a pool of 134, handed out afresh for every picture. Every cell handed
  out is noted together with what it held before, and the next picture drawn
  into that screen puts all of them back first.
- **Fixed characters** (the cannon, the ground with its bunkers, the score)
  are copied before anything is drawn into them. A shot passing the cannon
  then changes a copy, and the cannon's own character stays whole.
- **The three demon slots** keep ten characters each, per screen, from one
  picture to the next. When a demon moves, only the lines that changed are
  written, not all 80 bytes.
- **Where two figures meet** in one cell, the later one is ORed into the
  earlier one's character. That character is then marked, and the next time
  it is drawn it is rewritten in full, so no pixels are left behind.

Unlike in the Phoenix clone, two large figures can sit on each other for as long as
they like.

### Collisions from the picture, not from boxes

The 2600 knows about collisions only because its video chip reports them
while it draws. [kernel.s](kernel.s) replays the lines the 2600 would draw
and works out which pixels would be lit. It includes the chip's timing
quirks: a register written in the middle of a line only takes effect from a
certain pixel on, and left of it the line keeps the old shape. Wherever two
objects' pixels meet, it sets the same collision latches the chip has, and
the game reads them as it would on the 2600. The drawing then uses what this
replay worked out.

### A fixed frame rate that catches up

The Phoenix clone counts every speed in ticks of the KERNAL clock, with the remainder
of a pixel carried over, so it runs at the right speed however long drawing
takes. That is not possible here, because the logic has to advance in the
original's frames and nothing else. So:

- The cartridge is the American one and runs **sixty frames a second**. The
  Plus/4 shows fifty pictures, so five pictures owe the game six frames.
- Every picture that goes by adds six fifths of a frame. All the frames owed
  are worked out, collisions included, and only the last of them is drawn.
- A frame that is not drawn costs about a third as much as a drawn one,
  because only the collision part of the kernel runs.

The game therefore always runs at exactly the original's speed, and the
sound comes out at the original's tempo with it. Sound needs no interrupt of
its own this time: the two 2600 voices are translated onto the TED's two
once per frame, with noise always going to voice 2, the only one that can
make it.

### Checked frame for frame

Because the timing is exact, the conversion can be compared with the original
directly:

1. The original runs in Stella (driven headless as described in
   [the Phoenix clone's README](../phoenix/README.md#measuring-the-original)) and is
   stopped somewhere in a game.
2. Its 128 bytes of RAM are poked into a debug build of this conversion running
   in VICE (`DEBUG=1 ./build.sh`).
3. Both run on for the same number of frames, and the two RAM images are
   compared.

After 3000 frames of the demo and 1000 frames of a game there is **not one
byte of difference**, apart from a few bytes the 2600 uses as scratch
space while it draws. The check was run again after every change.

### Measuring where the cycles go

The Phoenix clone was tuned by counting passes per second. Here each part of a frame
is timed on its own:

- **Plain cycle counts.** The debug build can stop at any frame. It then
  switches off the interrupt and the screen, so the TED gives the CPU full
  speed throughout and nothing interrupts it. It runs the frame's parts one
  by one, each from the same state, and VICE's cycle counter at marker
  functions gives what each part costs, in plain cycles.
- **Instruction-level profiles.** VICE's CPU history (`chis`) records every
  instruction with its cycle count. Grouped by routine, and down to single
  lines of the assembly source, it shows where the time goes.

This is what found, for example:

- the position stepping in the C logic, which is now a table;
- the demons' lasers, which went through the general drawing path and now
  have a direct one;
- the fact that the joystick was read for every frame caught up, not once
  per picture.

The numbers as they stand:

| | cycles |
| --- | --- |
| left to the program per picture (display on, interrupt running) | about 20,700 |
| a frame that is drawn | about 31,000 |
| a frame that is only worked out | 8,000–10,000 |

That makes about two pictures in five drawn.

### A cartridge for 16 KB of RAM

The PRG uses the Plus/4's memory freely: when it starts, it works out some
15 KB of tables, including every demon picture at every pixel position. A
C16 has 16 KB of RAM in all, and the two screens need half of that. So the
cartridge puts everything that never changes into its ROM, and the RAM
holds only what the game writes to:

- **Tables made at build time.** [mktables.py](mktables.py) works out the
  tables the game only ever reads: the pixel shifts, the demon and cannon
  pictures, the positions, the tones. It writes them into a source file
  that goes into the ROM. The PRG uses the same file, so the two cannot
  differ. The generator was checked against the tables the earlier version
  built in memory, and they matched byte for byte.
- **Demon pictures without padding.** Each picture used to carry eight empty
  lines above and below every column, so a character could be copied out of
  it at any height. Now a picture is just its 40 bytes, and the drawing
  routine clears the lines a demon has left behind itself. That halves the
  pictures to 4.4 KB.
- **Code that changes itself runs from RAM.** Two drawing routines patch
  their own instructions while they run (the masks of a demon's lines, the
  shift table a laser column uses). The cartridge copies those two, about
  800 bytes, into RAM at start-up.
- **No room for a page of its own.** The end-of-game page used to have 2 KB
  for itself. Now it is written into the screen that is not being shown.
  Afterwards that screen is rebuilt: its cells, its colours, the cannon, the
  ground and the score are all drawn again.
- **Starting without the KERNAL.** At reset, before it has set up anything
  else, the KERNAL looks at each ROM bank for `CBM` at `$8007`. Where the
  byte before it is 1, it calls `$8000` with both halves of the cartridge
  switched in. The game takes over from there, sets up the TED itself and
  never hands back. For a moment it switches the KERNAL's half back in, to
  copy the 64 characters out of the character ROM. The code doing that sits
  in the cartridge's low half, which stays where it is.

A trap on the C16: it decodes only 16 KB, so a write to `$FFFE` lands in
RAM at `$3FFE`. The PRG sets its interrupt vectors by writing them into
RAM under the ROM. The cartridge must not do that, and has its vectors in
its own ROM instead.

On the cartridge the RAM holds the two screens at `$0800`–`$27FF`, the
characters at `$0400`, cc65's stack at `$0200`, and everything else in
3.5 KB at `$2800`. About 1 KB of the ROM is still free.

## What is not 1:1

- **Not every frame is drawn**, only about two in five. Movement is coarser
  than on the 2600, but never slower.
- **Sixty frames on fifty pictures.** Even with every picture drawn, every
  fifth picture would move two frames on. This is the small judder every
  NTSC game has on a PAL machine.
- **Colours** are the nearest the TED has to the 2600's NTSC palette.
- **The IMAGIC logo** gives way to the lines described above, and the page
  at the end of a game is new.

## Files

| | |
| --- | --- |
| [demonattack.c](demonattack.c) | the game logic, sound, input, the demo's lines and the end-of-game page, start-up and the main loop |
| [kernel.s](kernel.s) | the 2600 kernel replayed: what each line shows, the collisions, the drawing calls |
| [engine.s](engine.s) | the Plus/4 side: raster interrupt, the two screens, the character pool and the drawing routines |
| [demonattack.cfg](demonattack.cfg) | the PRG's memory layout: the 2600's RAM in zero page at `$80`–`$FF`, program to `$B7FF`, the two screens at `$C000`–`$DFFF` |
| [mktables.py](mktables.py) | makes `build/tables.s`: everything the game only reads, at build time |
| [crt0_cart.s](crt0_cart.s) | the cartridge's header and start-up |
| [mkcrt.py](mkcrt.py) | wraps the raw cartridge image into a CRT file for VICE |
| [run-yape.sh](run-yape.sh) | starts the cartridge in Yape as a C16, with a configuration of its own (F5 *in Yape*) |
| [demonattack_cart.cfg](demonattack_cart.cfg) | the cartridge's memory layout: 32 KB ROM at `$8000`, everything in RAM below `$4000` |
| [build.sh](build.sh) | builds `build/demonattack.prg`, `build/demonattack.bin` and `build/demonattack.crt`; with `DEBUG=1` also the test build `build/dbg.prg` |

## Building and running

From the repository root, with `demonattack.c` active in the editor, `F5`
builds and starts it. Unlike the other programs, this one is three sources
and a linker configuration, so the root's run script hands the build to
[build.sh](build.sh). Without an editor:

```sh
./build.sh
~/.local/share/cc65-vs64/bin/xplus4 -autostartprgmode 1 build/demonattack.prg
~/.local/share/cc65-vs64/bin/xplus4 -model c16 -cartcrt build/demonattack.crt
./run-yape.sh       # Yape: the cartridge on a C16, see below
```

`build.sh` makes everything every time: the PRG, and the cartridge in two
files with the same 32 KB of ROM in them.

| File | For |
| --- | --- |
| `build/demonattack.crt` | **VICE**: *File → Attach cartridge image* with the default *Smart-attach*, or `-cartcrt` |
| `build/demonattack.bin` | **Yape**, **plus4emu**, an **EPROM**; VICE only with `-cart` on the command line |

There is no one file every emulator takes. VICE's dialog expects a CRT
file: a header and the ROM in packets, here two of 16 KB for C1 low and C1
high ([mkcrt.py](mkcrt.py) makes it). Yape and plus4emu, on the other hand,
load ROM files as raw bytes, and so does an EPROM programmer. The raw image
has C1 low (`$8000`) in its first 16 KB and C1 high (`$C000`) in the
second, so it fits a single 27256 on a board that puts both halves on one
chip.

- **Yape** cannot load a ROM from its command line. It takes one file
  there, and only a program, disk or tape to load. A cartridge and the RAM
  size are settings in its `yape.conf`. So [run-yape.sh](run-yape.sh)
  writes Yape a configuration of its own, with the cartridge in bank 2
  (C1, `ROMC2LOW`) and 16 KB of RAM (`RamMask = 3fff`), and starts Yape
  with it: Yape comes up as a C16 running the game. Your own `yape.conf`
  stays as it is. From the repository root, the F5 configuration *in Yape*
  builds and runs the script. It also sets up the gamepad as for Paradroid,
  so a stick that SDL maps wrongly no longer holds a joystick direction
  down. On the machine that shows up as a key typing itself.

  The patched Yape from
  [../paradroid/tools/yape.patch](../paradroid/tools/yape.patch) starts the
  cartridge at once. Yape as it comes loads the ROMs in its settings only at
  a hard reset, so there `Shift`+`F11` starts it.

  Without the script, the cartridge goes in through Yape's menu (YapeSDL,
  which also runs in the browser, has the same one). Open it with `F8`,
  `Esc` or the right mouse button, choose *Attach rom...* and then
  `demonattack.bin`. Where it offers banks, `BANK#1 LO` and `BANK#2 LO` both
  work: a 32 KB file fills the low and the high half. If the machine does
  not restart by itself, `F11` resets it. For a C16, the RAM is set to
  16 KB in its options (*C264 RAM mask*, `3FFF`).
- **plus4emu** takes ROM files with an offset into the file. Cartridge 1 is
  segments 04 (low) and 05 (high): `demonattack.bin` at offset 0 for 04 and
  at offset 16384 for 05 (`memory.rom.04.file`, `memory.rom.04.offset` and
  the same for 05 in its configuration).

Yape's quick attach puts a ROM into bank 1, where the Plus/4 has its
built-in 3-plus-1 software, and not into bank 2 like a real cartridge. So
the cartridge does not assume a bank: at start-up it searches banks 1 to 3
for its own signature, from RAM, and selects the one it finds. In VICE it
has run from all three (C1, C2 and the function ROM's place). VICE's
`-c1lo` and `-c1hi` with two 16 KB halves did not work: VICE attached the
low half with an empty file name.

`build.sh` looks for cc65 in `~/.local/share/cc65-vs64/bin`, or in
`CC65_BIN` if that is set, and needs Python 3 for the tables. As for the Phoenix clone, `-Cl` is on.
