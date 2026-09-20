# Plus/4 Playground

A workbench for writing C — with a little 6502 assembly where it matters — for the
**Commodore Plus/4**, built with [cc65](https://cc65.github.io/) and run in
[VICE](https://vice-emu.sourceforge.io/).

This is a playground, not a library: each subfolder is a self-contained program,
from a three-line "hello world" to a full arcade game. The point is to find out how
far plain C gets you on a 1984 machine with 64 KB, no sprites, and a 1.76 MHz 7501.

## What's in here

| Folder | What it is |
| --- | --- |
| [main/](main/README.md) | The starting point — `clrscr()`, `printf()`, `cgetc()`. Useful as a template and as a sanity check that the toolchain is wired up correctly. |
| [pacman/](pacman/README.md) | A complete Pac-Man: full-screen 40×24 maze, four ghosts with distinct AI, power pills, levels, lives, TED sound. ~1500 lines of C plus two assembly routines. |
| [phoenix/](phoenix/README.md) | A rebuild of the Atari 2600 **Phoenix**: all five waves, the force field, the mothership, two-voice sound with the arcade melodies, and a starfield that scrolls pixel by pixel. |
| [pokerth/](pokerth/README.md) | Work in progress: a [PokerTH](https://github.com/pokerth/pokerth) client. TLS, protobuf and authentication are handled by a proxy on a PC, which hands the Plus/4 a protocol small enough to parse in 6502. Logging in and watching a lobby works; the Plus/4 end is next. |

### The two games

| | |
| --- | --- |
| [![Phoenix](phoenix/screenshots/wave3.png)](phoenix/README.md) | [![Pac-Man](pacman/screenshots/pacman.png)](pacman/README.md) |
| **[Phoenix](phoenix/README.md)** — all five waves of the 2600 game, the force field, the mothership, a starfield scrolling a pixel at a time. One 2600 pixel is two Plus/4 pixels, so 160×192 lands exactly on 40×24 cells. | **[Pac-Man](pacman/README.md)** — the whole maze on one screen, four ghosts with their own ways of hunting, pixel-by-pixel movement. |

The Plus/4 has no sprites at all, so both games build their figures out of
characters that are rewritten as the figures move — and they do it in opposite
ways, which is the interesting part. Pac-Man works the cells out on every frame. Phoenix
cannot afford that with a dozen figures on screen, so it works out all 32 ways
a figure can sit inside its cells when a wave starts and then only copies
finished blocks. That is the difference between 4000 cycles per figure and a
few hundred; a frame has 17784.

Both folders have a README of their own with the details.

## Toolchain

| Piece | Role |
| --- | --- |
| **cc65** | C compiler, assembler and linker for 6502 targets (`cl65 -t plus4`) |
| **VICE** (`xplus4`) | Plus/4 emulator, also used for source-level debugging |
| **VS64** | VS Code extension that drives cc65 and VICE and provides breakpoints |

Both cc65 and VICE are expected under `~/.local/share/cc65-vs64/bin`. On this machine
VS Code runs as a Flatpak while cc65 and VICE are host packages, so that directory
holds small **shim scripts** that reach the host tools (`flatpak-spawn --host`,
`CC65_HOME`, …) and fall back to the plain binaries when there is no sandbox. VS64
also expects the classic cc65 layout (`<dir>/bin`, `<dir>/include`), which the shim
directory provides. If you clone this elsewhere, point
`vs64.cc65InstallDir` / `vs64.viceExecutable` in the `.vscode/settings.json` files at
your own installation, or just call `cl65` directly (see below).

## Building and running

There are two ways to work, and which one you get depends on **which folder you open
in VS Code**.

### 1. Open the repository root — build whatever file is in the editor

`F5` (or the `Plus/4: Build & Run (aktive Datei)` task) builds the `.c` file that is
currently active and starts it in VICE. `Ctrl+Shift+B` builds it without launching.
No breakpoints, but you can hop between programs freely.

This runs [.vscode/run-current.sh](.vscode/run-current.sh), which you can also call
from a shell:

```sh
.vscode/run-current.sh pacman/pacman.c
```

### 2. Open a single program folder — full debugger

Open `main/` or `pacman/` directly and `F5` uses VS64's own VICE debugger with
source-level breakpoints. It always loads the program named in that folder's
`project-config.json`, which is exactly the one program in there.

The split exists because VS64 supports **one** `project-config.json` per workspace:
its debugger always resolves the first workspace folder and the `program` field in
`launch.json` is ignored. One folder per program is the way around that.

### 3. No editor at all

```sh
BIN=~/.local/share/cc65-vs64/bin
mkdir -p pacman/build
$BIN/cl65 -t plus4 -O -g -c -o pacman/build/pacman.o pacman/pacman.c
$BIN/cl65 -t plus4    -o pacman/build/pacman.prg pacman/build/pacman.o
$BIN/xplus4 -autostartprgmode 1 pacman/build/pacman.prg
```

Two steps on purpose: `cl65` otherwise drops the object file next to the source.

## Adding a program

1. `mkdir foo`
2. Copy `main/.vscode/` into it — those three files are deliberately program-agnostic
   (they use `${workspaceFolderBasename}`), so they work as a template unchanged.
3. Copy `project-config.json` and set `name` and `main` to the new name.
4. Write `foo/foo.c`.

If a program needs more than an emulator - the PokerTH client needs a proxy
running beside it - put a `run.sh` in its folder. F5 builds as usual, notices
it, and hands the finished `.prg` over to it instead of starting VICE.

If it needs its own compiler switches, put them in a `cflags` file next to the
source. Phoenix uses that for `-Cl`: cc65 otherwise keeps local variables on
its software stack, which costs a sixth of the running time in a game that is
busy every frame.

Convention: **the folder, the source file and the output all share one name.**
`foo/foo.c` builds to `foo/build/foo.prg`. Build output never goes into git.

```
Plus4/
├── .vscode/            F5 = build & run the active .c file
├── main/
│   ├── main.c
│   ├── project-config.json
│   ├── .vscode/        F5 = VS64 build & run with debugger
│   └── build/          main.prg (ignored)
└── pacman/
    └── …same shape
```

## Things this machine taught us

Collected here because every one of them compiles cleanly and only shows up in the
emulator.

- **The ROM is banked out.** cc65 hides it to use RAM up to `$FD00`, so copying the
  character generator from `$D000` yields garbage. Page it in via `$FF3E` / `$FF3F`
  with interrupts off — and touch **no C stack** in that window (it lives at
  `$F500–$FCFF`, underneath the ROM): globals only, no locals, no calls. Check with
  `cc65 -S` that no `sp` appears between the switches.
- **Character literals are translated to PETSCII.** `'A'` is 193, not 65; `'a'` is 65.
  So `case 'w'` matches unshifted W and `case 'W'` the shifted one — handle both. When
  converting to screen codes, compute relative to `'A'`/`'a'` instead of subtracting
  64/96, or everything lands 128 too high and the TED renders all text inverted, which
  looks deliberate and is easy to miss.
- **VS64 2.6.2 always links `c64.lib`**, even for `-t plus4` — it is hardcoded and the
  `libraries` field in `project-config.json` is read but never used. The build
  succeeds and the binary is wrong (conio writes to `$0400` instead of `$0C00`). The
  `ld65` shim rewrites it to `<target>.lib`; verify with a map file (`ld65 -m map.txt`)
  that the modules come from `plus4.lib`.
- **Colors are `brightness * 16 + hue`.** High brightness washes out to white on the
  Plus/4; the strong colors live at brightness 3–6.
- **Avoid `%` and `*` in per-frame code.** cc65 calls a full division routine for a
  modulo; a single conditional subtraction or a small lookup table is far cheaper.
- **Comparing a byte against a plain constant costs a 16-bit compare.** `if (zeile >=
  ZEILEN)` with `ZEILEN` an `int` constant makes cc65 widen both sides and push them
  through its software stack. Casting the constant to `unsigned char` turns four such
  comparisons in the drawing routine back into byte compares — in Phoenix that alone
  was worth more than the assembly around it.
- **`-Cl` is worth a sixth of the running time** in a program that is busy every
  frame: cc65 otherwise keeps every local on its software stack, and each access is
  an indexed load through a zero-page pointer. There is no recursion in a game loop,
  so static locals cost nothing.
- **Whatever rides the fine scroll has to move in the retrace.** Changing the
  scroll register in the gap between two frames but stepping the cells that go
  with it from inside the game loop puts them in their new place while the
  register still holds the old offset. The background jumps a whole character
  and back, once a second, and it reads as the entire picture stuttering.
- **Measure with an autopilot and an immortality switch.** A game left alone dies in
  seconds, and then the numbers describe BASIC sitting at its prompt rather than the
  game. An early Phoenix measurement said 0.8 passes per second for exactly that
  reason; the truth was twenty times better.

### Testing without looking at the screen

VICE can be driven remotely, which makes Plus/4 programs verifiable in an automated
way:

```sh
# Screenshot after a fixed number of cycles (boot + autostart alone cost ~28M)
xplus4 -default -warp -autostart-warp -autostartprgmode 1 \
       -limitcycles 45000000 -exitscreenshot "$HOME/shot.png" \
       -autostart "$HOME/path/to/program.prg"

# Or the binary monitor, which is far more powerful
xplus4 -remotemonitor -remotemonitoraddress ip4://127.0.0.1:6510 …
```

Over the monitor socket, `m 0c00 0fe7` dumps screen memory — reconstructing the
display as text is more precise than diffing screenshots — and writing to `$0527`
(keyboard buffer) plus `$00EF` (count) injects keystrokes, so a game can be played
remotely. `x` resumes emulation. Note that `-keybuf` does **not** work together with
`-autostart`: autostart consumes the buffer itself.

## Controls

Each program lists its own; see the README in its folder.

| | |
| --- | --- |
| [Pac-Man](pacman/README.md) | `W` `A` `S` `D` or the cursor keys, `Q` quits, space starts |
| [Phoenix](phoenix/README.md) | joystick in port 1, or cursor keys and space; stick down raises the force field |
