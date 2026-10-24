# toolchain

Tools for looking at the Amiga originals of ports to the Plus/4: running
them without a window, getting files off their disks, disassembling their
68000 code. The Plus/4 side itself (cc65, VICE, Yape, plus4emu) is set up
outside this repository.

```sh
toolchain/setup.sh
```

| Path | What | Source |
| --- | --- | --- |
| `tools/bin/amiga-run` | Amiga emulator without a window, driven by a command script: frames, joystick, mouse, keys, screenshots, memory dumps, breakpoints, traces, snapshots (see below) | `tools/amiga-run/`, on the core of [vAmiga](https://github.com/dirkwhoffmann/vAmiga) (pinned commit, cloned into `tools/src/vAmiga`) |
| `tools/bin/adf.py` | lists and extracts the files of an Amiga disk image (ADF, OFS/FFS) | written here |
| `tools/bin/m68k-dis.py` | recursive-descent 68000 disassembler: follows branches and calls, so code and data come apart; labels from a symbol file | written here |
| `tools/python/` | the Python module `capstone`, which `m68k-dis.py` uses | pip |
| `*.rom` | an Amiga Kickstart ROM (1.3 for the A500) – local only, not in the repo | your own copy |

The vAmiga sources, the built emulator, the Python modules and the ROM are
listed in `.gitignore`; `setup.sh` restores all of them but the ROM.

## Running Amiga programs

`tools/bin/amiga-run` emulates an Amiga (the vAmiga core) without a window,
as fast as it can (about four times real time), and does what a script
says, line by line:

```sh
cat > boot.txt <<'EOS'
config A500_OCS_1MB
rom "toolchain/Kickstart v1.3 rev 34.5 (1987)(Commodore)(A500-A1000-A2000-CDTV).rom"
disk 0 game.adf
power
frames 1500              # 30 seconds (PAL)
mouse 1 left             # click
frames 250
joy 2 up fire            # joystick in port 2
frames 100
joy 2 release
shot title.ppm           # screenshot, 368 x 287 lores pixels
dump chip.bin 0 80000    # memory (hex address and length)
until 1c2f0 500          # run to an address (at most 500 frames), print the registers
save title.vasnap        # snapshot; "load" continues from it
EOS
toolchain/tools/bin/amiga-run boot.txt
```

All commands are listed at the top of
[tools/amiga-run/amiga-run.cpp](tools/amiga-run/amiga-run.cpp). A Kickstart
ROM is needed; it is not included (it may not be redistributed) and goes
into `toolchain/` as a `.rom` file.

`tools/bin/m68k-dis.py` turns the code into a listing, `tools/bin/adf.py`
gets the files off a disk image. Games that load with a track loader of
their own have no file system on their disks; `adf.py` says so, and their
code is best taken from memory (`dump`) once it is loaded.
