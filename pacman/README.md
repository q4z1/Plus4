# Pac-Man for the Commodore Plus/4

A complete Pac-Man: the full 40×24 maze on screen at once, four ghosts with
their own ways of hunting, power pills, levels, lives and TED sound. About
1500 lines of C and two routines in assembly.

![Pac-Man on the Plus/4](screenshots/pacman.png)

**Controls:** `W A S D` or the cursor keys. `Q` ends the game.

## How the figures are made

The Plus/4 has no sprites. Every figure is built from characters that are
recomputed on every frame — which is what lets them move pixel by pixel
instead of tile by tile, and lets them be larger than a tile.

- Bit 7 of `$FF07` switches off the TED's habit of showing codes 128–255 as
  inverted copies of 0–127. All 256 characters are then free, and the upper
  128 serve as a pool: each figure claims a few of them, has its picture
  written into them on every frame, and places them on the screen.
- The figure bitmaps are kept horizontally pre-shifted in RAM, so per frame it
  is only a merge of figure over maze background, not a shift.
- The maze wall lines are inset two pixels from the tile edge. That makes a
  corridor effectively twelve pixels wide instead of eight, so a large figure
  fits through without covering the walls.

[pacman.c](pacman.c) is commented throughout and is meant to be read top to
bottom: hardware, character set, maze, sound and input, figures, drawing,
movement and ghost AI, game flow.

## What was learned the hard way

- **Figure size costs more than it looks.** A figure wider than a tile does
  not cost proportionally more but quadratically: 1×2 cells become 3×3.
  Bringing the figures down from 10×10 to 8×8 pixels was the single biggest
  speed-up of the whole exercise — bigger than anything possible inside the
  drawing loop.
- **`memcpy`/`memset` are expensive for small blocks.** Under cc65 they cost
  around 700 cycles per call for 16 to 24 bytes, and there were thirty calls
  per frame. Written out by hand the same work costs a fraction.
- **Casting the cell loop into assembly gained nothing.** The measurable wins
  came from removing `%` and 16-bit multiplications from the C loops, from
  precomputed row starts, and from skipping work that was not needed.
- **cc65 misreads deeply nested conditional expressions.** `a ? b : c ? d : e`
  three levels down gave three ghosts the same colour. Written as a branch
  with a table it is correct.

## Building and running

From the repository root, with `pacman.c` active in the editor, `F5` builds and
starts it. Without an editor:

```sh
BIN=~/.local/share/cc65-vs64/bin
mkdir -p pacman/build
$BIN/cl65 -t plus4 -O -g -c -o pacman/build/pacman.o pacman/pacman.c
$BIN/cl65 -t plus4    -o pacman/build/pacman.prg pacman/build/pacman.o
$BIN/xplus4 -autostartprgmode 1 pacman/build/pacman.prg
```
