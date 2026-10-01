#!/bin/sh
# Build Paradroid: build/paradroid.prg
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
ls -l build/paradroid.prg
