# Phoenix for the Commodore Plus/4

A rebuild of **Phoenix** as the Atari 2600 played it (Atari, 1982; the arcade
original is Amstar/Centuri, 1980). All five waves, the force field, the
mothership, two-voice sound with the arcade melodies, and a starfield that
scrolls a pixel at a time.

![Title screen](screenshots/title.png)

**Controls**

| | |
| --- | --- |
| Joystick in port 1 | left/right to move, button to fire, **pull towards you** for the force field |
| Keyboard | cursor left/right, `Space` to fire, cursor down for the force field |
| `Q` or `Run/Stop` | quit |

## The five waves

| | | |
| --- | --- | --- |
| 1 | small birds, orange | a swaying formation; one drops out at a time, dives at the ship and drops an egg on the way |
| 2 | small birds, green | the same, but the button auto-repeats while it is held — the only wave that does |
| 3 | large birds, blue | shooting a wing takes it off; only a hit in the middle kills. Wings grow back |
| 4 | large birds, red | the same, faster |
| 5 | the mothership | it comes down the screen while the hull has to be chewed away from below |

After the fifth wave the round starts again, a little quicker each time.

![Wave 1](screenshots/wave1.png)
![Wave 3](screenshots/wave3.png)
![The mothership](screenshots/mothership.png)

**Scoring**, as on the 2600: a small bird is worth 20 sitting in the formation
and 80 in flight; a large one 100 to 500 depending on how far down it has come
when you hit it, and 20 for a wing. The mothership is worth 1000 to 4000 in
the first round and another 1000 per round after that, up to 9000 — the lower
you let it come, the more. Five ships, one extra at 5000 points.

The force field burns for a second and a half, cannot be raised again for
another three and a half, and roots the ship to the spot while it is up. The
ship may still fire, and anything that touches the field dies.

## How it is built

The 2600 shows 160 pixels across, the Plus/4 shows 320 — so one 2600 pixel
becomes two, and the 2600 playfield of 160×192 lands exactly on 40×24
character cells. Everything in the game is stored at 2600 resolution and
doubled in width when it is drawn. That mapping is the reason the result looks
like the original rather than like a Plus/4 game.

Three things carry the whole thing:

**The starfield scrolls in hardware.** `$FF06` bits 0–2 are the TED's fine
scroll; a whole screen of stars moves one pixel per pass for free, and only
every eighth pixel do the stars step on by one cell. Because the fine scroll
moves *everything*, whatever has to stand still — the score, the ship, the
birds — is drawn one pixel higher for every pixel the scroll has moved. For
the figures that costs nothing, because they are drawn at a free vertical
offset anyway; for the score it costs one pass over a 20-cell strip.

**Figures are finished blocks of characters, not computed ones.** The Plus/4
has no sprites, so a figure is characters that are rewritten as it moves. A
figure can stand at four horizontal and eight vertical positions inside its
cells, so there are 32 ways it can look — and all 32 are worked out when a
wave starts. Drawing is then a copy of 48 bytes into the character set plus a
handful of screen codes. Computing the cells per frame instead cost about
4000 cycles per figure, and a frame has 17784.

**The mothership is background, not a figure.** It is far too large to redraw,
so its cells live in the shadow copy of the screen and it rides the same fine
scroll as the stars — its approach is smooth and costs nothing. Figures flying
over it put it back when they move on. A shot takes a bite out of the lowest
piece of hull in its column; once a column is chewed through, the shot still
has to pass the rim, which turns and closes the gap again.

The result is nine to fifteen passes a second, depending on how much is
flying. Every speed and every length of time in the game is counted in those
passes rather than in frames, which is why [phoenix.c](phoenix.c) has a `TAKT`
constant and no magic number for the shield's second and a half.

## What is not 1:1

- **One colour per character cell.** A 2600 bird is two-toned; here a bird is
  one colour. Everything else about the palette follows the manual — violet
  and orange, violet and green, blue, red.
- **Eight small birds and six large ones** per wave, not the arcade's twenty.
  The 2600 shows far fewer than the arcade too, but not exactly these numbers.
- **The artwork is drawn by hand** from the original's proportions, not
  extracted from the 2600 ROM. The shapes read right; they are not identical.
- **Nine to fifteen steps a second** rather than sixty. Speeds are scaled so
  the ship crosses the screen and the birds dive at about the original pace;
  the movement is coarser, not slower.

## Testing

Two switches at the top of [phoenix.c](phoenix.c) exist so the game can be
watched running in an emulator with nobody at the joystick:

- `autopilot` — steers, fires and raises the field on its own, and walks
  straight through the title screen.
- `unsterblich` — nothing can kill the ship.

A real round never sets either. They are there because a game that dies
immediately without input is very hard to measure: an early measurement of the
frame rate was pure nonsense because the run had long since ended and the
machine was sitting in BASIC.

## Building and running

From the repository root, with `phoenix.c` active in the editor, `F5` builds
and starts it. Without an editor:

```sh
BIN=~/.local/share/cc65-vs64/bin
mkdir -p phoenix/build
$BIN/cl65 -t plus4 -O -Cl -g -c -o phoenix/build/phoenix.o phoenix/phoenix.c
$BIN/cl65 -t plus4       -o phoenix/build/phoenix.prg phoenix/build/phoenix.o
$BIN/xplus4 -autostartprgmode 1 phoenix/build/phoenix.prg
```

`-Cl` matters: cc65 otherwise keeps local variables on its software stack, and
that costs a sixth of the running time in a game that is busy every frame.
The switch lives in [cflags](cflags), which the build script picks up.
