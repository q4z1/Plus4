#!/bin/sh
# Build Stardew Pond: build/stardew.prg and the disk it runs
# from, build/stardew.d64, with the rooms, tile sets and toolbar
# characters as files of their own; and the test build,
# build/stardew-test.d64: the same program with test_build set, and its
# menu (testmenu.c) as a file on the disk. Everything on the disk is packed by
# exomizer: the files by tools/mkdata.py (the game unpacks them, unpack.s),
# the program as a whole here (it unpacks itself when it is started).
#
# The disk's first file is the boot program, "stardew" (boot.s): it starts
# the fast loader (drive.s, fastload.s) if the drive is a 1541, and loads
# the game, "game", with it or with the KERNAL. Then "save", the save file,
# as long as the game state: the fast loader writes into it (world.c).
set -e
cd "$(dirname "$0")"
# not while a test runs: it would go on with the new files under it
python3 tests/onetest.py
B=${CC65_BIN:-$HOME/.local/share/cc65-vs64/bin}
export EXOMIZER=${EXOMIZER:-$B/exomizer}
mkdir -p build
python3 tools/mkdata.py
for f in stardew world farm ui town mine testmenu; do
    $B/cl65 -t plus4 -O -Cl -g -I build/gen -c -o build/$f.o $f.c
done
for f in engine unpack; do
    $B/cl65 -t plus4 -g -c -o build/$f.o $f.s
done
$B/cl65 -t plus4 -g -c -o build/sprites.o build/gen/sprites.s
$B/cl65 -t plus4 -C stardew.cfg -m build/stardew.map -Ln build/stardew.lbl \
    -o build/stardew.raw build/stardew.o build/world.o build/farm.o build/ui.o \
    build/town.o build/mine.o build/engine.o build/unpack.o build/sprites.o \
    build/testmenu.o
# The program packed (it starts with SYS from BASIC: exomizer keeps that,
# unpacks it into its place and starts it). The screen off and the border
# black while it unpacks, no flashing: the title comes up whole.
$EXOMIZER sfx sys -t 4 -q -n -s 'lda #$0b sta $ff06 lda #0 sta $ff19' \
    -o build/stardew.prg build/stardew.raw
echo "build/stardew.prg: $(stat -c%s build/stardew.raw) bytes, packed $(stat -c%s build/stardew.prg)"

# The test build: one byte apart (test_build, in the program's DATA), so
# the labels and the tests hold for both. Its menu packed like every file.
python3 - <<'EOF2'
raw = bytearray(open('build/stardew.raw', 'rb').read())
lbl = open('build/stardew.lbl').read().split()
addr = int(lbl[lbl.index('._test_build') - 1], 16)
off = addr - (raw[0] | raw[1] << 8) + 2
assert raw[off] == 0
raw[off] = 1
open('build/stardew-test.raw', 'wb').write(raw)
EOF2
$EXOMIZER sfx sys -t 4 -q -n -s 'lda #$0b sta $ff06 lda #0 sta $ff19' \
    -o build/stardew-test.prg build/stardew-test.raw
$EXOMIZER raw -q -o build/testmenu.exo build/testmenu.bin
printf '\000\350' | cat - build/testmenu.exo > build/disk/TESTMENU
echo "build/testmenu.bin: $(stat -c%s build/testmenu.bin) bytes, packed $(stat -c%s build/testmenu.exo)"

# The boot program, with the fast loader's two halves, and where the packed
# game starts: the number its BASIC line SYSes to
printf '%s\n' 'MEMORY { RAM: start = $0000, size = $10000, file = %O; }' \
    'SEGMENTS { CODE: load = RAM, type = rw; }' > build/raw.cfg
for f in drive fastload; do
    $B/cl65 -t none -C build/raw.cfg -o build/$f.bin $f.s
done
START=$(python3 -c 'import re, sys; print(int(re.search(rb"\x9e *([0-9]+)", open(sys.argv[1], "rb").read()[:40]).group(1)))' build/stardew.prg)
$B/cl65 -t none -g -C build/raw.cfg --asm-define GAMESTART=$START -Ln build/boot.lbl -o build/boot.prg boot.s
echo "boot: $(stat -c%s build/boot.prg) bytes, drive code $(stat -c%s build/drive.bin), loader $(stat -c%s build/fastload.bin)"

# The save file as the disk brings it: its load address, the game state's
# length of zeros (no saved game: the mark is not there)
python3 - <<'EOF2'
lbl = open('build/stardew.lbl').read().split()
at = lambda name: int(lbl[lbl.index(name) - 1], 16)
run, size = at('.__SAVEDATA_RUN__'), at('.__SAVEDATA_SIZE__')
open('build/disk/SAVE', 'wb').write(bytes([run & 255, run >> 8]) + bytes(size))
EOF2

# The disk, its files a few sectors further apart than the DOS would put
# them, for the fast loader (tools/mkd64.py, trainschedule's). The game
# further still: the boot loads it with the screen on, when the TED leaves
# the CPU less time.
INTERLEAVE=${INTERLEAVE:-15}
GAME_INTERLEAVE=${GAME_INTERLEAVE:-20}
disk() {         # disk <d64> <program> [more files from build/disk]
    d64=$1
    prg=$2
    shift 2
    set -- stardew=build/boot.prg game@$GAME_INTERLEAVE="$prg" \
           hud=build/disk/HUD "$@"
    for f in build/disk/TILES* build/disk/ROOM*; do
        set -- "$@" "$(basename "$f" | tr 'A-Z' 'a-z')=$f"
    done
    python3 tools/mkd64.py "$d64" "stardew pond" sp $INTERLEAVE "$@" \
        save=build/disk/SAVE
}
echo "build/stardew.d64:"
disk build/stardew.d64 build/stardew.prg
disk build/stardew-test.d64 build/stardew-test.prg testmenu=build/disk/TESTMENU >/dev/null
echo "build/stardew-test.d64: the same, the program with its test menu"
