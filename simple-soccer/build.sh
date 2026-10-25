#!/bin/sh
# Build Simple Soccer: build/simple-soccer.prg, one file with everything in it.
# The data first (tools/mkdata.py: build/gen/, from data/), then the
# assembly (cl65 only assembles it and links).
set -e
cd "$(dirname "$0")"
B=${CC65_BIN:-$HOME/.local/share/cc65-vs64/bin}
mkdir -p build/gen
# PACE=2: a picture every second frame instead of every third (game.inc)
DEFS=${PACE:+--asm-define PACE=$PACE}
python3 tools/mkdata.py
for f in simple-soccer engine play; do
    $B/cl65 -t plus4 -g --asm-include-dir build/gen $DEFS -c -o build/$f.o $f.s
done
$B/cl65 -t plus4 -g -c -o build/data.o build/gen/data.s
$B/cl65 -t plus4 -C simple-soccer.cfg -m build/simple-soccer.map -Ln build/simple-soccer.lbl \
    -o build/simple-soccer.prg build/simple-soccer.o build/engine.o build/play.o build/data.o
echo "build/simple-soccer.prg: $(stat -c%s build/simple-soccer.prg) bytes"
