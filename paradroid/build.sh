#!/bin/sh
# Build Paradroid: build/paradroid.prg and the disk it runs from,
# build/paradroid.d64, with the briefing as a file of its own.
set -e
cd "$(dirname "$0")"
B=${CC65_BIN:-$HOME/.local/share/cc65-vs64/bin}
mkdir -p build
python3 tools/mkdata.py
for f in paradroid deck droids draw transfer lift console; do
    $B/cl65 -t plus4 -O -Cl -g -I build/gen -c -o build/$f.o $f.c
done
$B/cl65 -t plus4 -g -c -o build/engine.o engine.s
$B/cl65 -t plus4 -g -c -o build/data.o build/gen/data.s
$B/cl65 -t plus4 -C paradroid.cfg -m build/paradroid.map -Ln build/paradroid.lbl \
    -o build/paradroid.prg build/paradroid.o build/deck.o build/droids.o \
    build/draw.o build/transfer.o build/lift.o build/console.o build/engine.o build/data.o

# The disk. c1541 comes with VICE; inside a Flatpak sandbox it is on the host.
if command -v c1541 >/dev/null 2>&1; then
    C1541=c1541
else
    C1541="flatpak-spawn --host c1541"
fi
rm -f build/paradroid.d64
$C1541 -format "paradroid,pd" d64 build/paradroid.d64 \
       -write build/paradroid.prg paradroid -write build/disk/briefing briefing >/dev/null
echo "build/paradroid.d64:"
$C1541 -attach build/paradroid.d64 -list
