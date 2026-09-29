#!/bin/sh
# Build Stardew Pond: build/stardew.prg and the disk it runs
# from, build/stardew.d64, with the rooms, tile sets and toolbar
# characters as files of their own.
set -e
cd "$(dirname "$0")"
B=${CC65_BIN:-$HOME/.local/share/cc65-vs64/bin}
mkdir -p build
python3 tools/mkdata.py
for f in stardew world farm ui town mine; do
    $B/cl65 -t plus4 -O -Cl -g -I build/gen -c -o build/$f.o $f.c
done
$B/cl65 -t plus4 -g -c -o build/engine.o engine.s
$B/cl65 -t plus4 -g -c -o build/sprites.o build/gen/sprites.s
$B/cl65 -t plus4 -C stardew.cfg -m build/stardew.map -Ln build/stardew.lbl \
    -o build/stardew.prg build/stardew.o build/world.o build/farm.o build/ui.o \
    build/town.o build/mine.o build/engine.o build/sprites.o

# The disk. c1541 comes with VICE; inside a Flatpak sandbox it is on the host.
if command -v c1541 >/dev/null 2>&1; then
    C1541=c1541
else
    C1541="flatpak-spawn --host c1541"
fi
set -- -format "stardew pond,sp" d64 build/stardew.d64 -write build/stardew.prg stardew \
       -write build/disk/HUD hud
for k in 0 1 2; do
    set -- "$@" -write build/disk/TILES$k tiles$k
done
for f in build/disk/ROOM*; do
    n=$(basename "$f" | tr 'A-Z' 'a-z')
    set -- "$@" -write "$f" "$n"
done
rm -f build/stardew.d64
$C1541 "$@" >/dev/null
echo "build/stardew.d64:"
$C1541 -attach build/stardew.d64 -list | tail -n +1
