#!/bin/sh
# Build Stardew Pond: build/stardew.prg and the disk it runs
# from, build/stardew.d64, with the rooms, tile sets and toolbar
# characters as files of their own. Everything on the disk is packed by
# exomizer: the files by tools/mkdata.py (the game unpacks them, unpack.s),
# the program as a whole here (it unpacks itself when it is started).
set -e
cd "$(dirname "$0")"
# not while a test runs: it would go on with the new files under it
python3 tests/onetest.py
B=${CC65_BIN:-$HOME/.local/share/cc65-vs64/bin}
export EXOMIZER=${EXOMIZER:-$B/exomizer}
mkdir -p build
python3 tools/mkdata.py
for f in stardew world farm ui town mine; do
    $B/cl65 -t plus4 -O -Cl -g -I build/gen -c -o build/$f.o $f.c
done
for f in engine unpack; do
    $B/cl65 -t plus4 -g -c -o build/$f.o $f.s
done
$B/cl65 -t plus4 -g -c -o build/sprites.o build/gen/sprites.s
$B/cl65 -t plus4 -C stardew.cfg -m build/stardew.map -Ln build/stardew.lbl \
    -o build/stardew.raw build/stardew.o build/world.o build/farm.o build/ui.o \
    build/town.o build/mine.o build/engine.o build/unpack.o build/sprites.o
# The program packed (it starts with SYS from BASIC: exomizer keeps that,
# unpacks it into its place and starts it). The screen off and the border
# black while it unpacks, no flashing: the title comes up whole.
$EXOMIZER sfx sys -t 4 -q -n -s 'lda #$0b sta $ff06 lda #0 sta $ff19' \
    -o build/stardew.prg build/stardew.raw
echo "build/stardew.prg: $(stat -c%s build/stardew.raw) bytes, packed $(stat -c%s build/stardew.prg)"

# The disk. c1541 comes with VICE; inside a Flatpak sandbox it is on the host.
if command -v c1541 >/dev/null 2>&1; then
    C1541=c1541
else
    C1541="flatpak-spawn --host c1541"
fi
set -- -format "stardew pond,sp" d64 build/stardew.d64 -write build/stardew.prg stardew \
       -write build/disk/HUD hud
for f in build/disk/TILES*; do
    set -- "$@" -write "$f" "$(basename "$f" | tr 'A-Z' 'a-z')"
done
for f in build/disk/ROOM*; do
    n=$(basename "$f" | tr 'A-Z' 'a-z')
    set -- "$@" -write "$f" "$n"
done
rm -f build/stardew.d64
$C1541 "$@" >/dev/null
echo "build/stardew.d64:"
$C1541 -attach build/stardew.d64 -list 2>/dev/null | tail -n +1
