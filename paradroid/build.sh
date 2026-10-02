#!/bin/sh
# Build Paradroid: build/paradroid.prg and the disk it runs from,
# build/paradroid.d64, with the title and briefing as a file of its own
# (an overlay, build/title.bin), the console (another, build/console.bin)
# and the droids' pictures p00-p23.
set -e
cd "$(dirname "$0")"
B=${CC65_BIN:-$HOME/.local/share/cc65-vs64/bin}
mkdir -p build
# the fast loader's drive code for a 1551, run at $0500 there, and what
# puts it there at the start: their size in INITDATA, which the
# pictures' slots take over afterwards, goes to mkdata (linked after
# data.o: the slots start where data.s's INITDATA does)
$B/cl65 -t none --start-addr 0x0500 -o build/drive1551.bin drive1551.s
$B/cl65 -t plus4 -g -c -o build/drivecode.o build_drive.s
$B/cl65 -t plus4 -O -Cl -g -c -o build/fastinit.o fastinit.c
$B/cl65 -t plus4 -g -c -o build/sfx.o sfx.s
INIT_EXTRA=0
for o in build/drivecode.o build/fastinit.o; do
    n=$($B/od65 -S $o | awk '/INITDATA:/{print $2}')
    INIT_EXTRA=$((INIT_EXTRA + ${n:-0}))
done
# (the sound effects' player too: it is copied to $FC00 at the start)
n=$($B/od65 -S build/sfx.o | awk '/SFXCODE:/{print $2}')
INIT_EXTRA=$((INIT_EXTRA + ${n:-0}))
INIT_EXTRA=$INIT_EXTRA python3 tools/mkdata.py
for f in paradroid deck droids draw transfer lift console title; do
    $B/cl65 -t plus4 -O -Cl -g -I build/gen -c -o build/$f.o $f.c
done
$B/cl65 -t plus4 -g -c -o build/engine.o engine.s
$B/cl65 -t plus4 -g -c -o build/xfer.o xfer.s
$B/cl65 -t plus4 -g -c -o build/fastload.o fastload.s
$B/cl65 -t plus4 -g -c -o build/music.o music.s
$B/cl65 -t plus4 -g -c -o build/move.o move.s
$B/cl65 -t plus4 -g --asm-include-dir build/gen -c -o build/sfxcall.o sfxcall.s
$B/cl65 -t plus4 -g -c -o build/data.o build/gen/data.s
$B/cl65 -t plus4 -g -c -o build/brief.o build/gen/brief.s
$B/cl65 -t plus4 -g -c -o build/condata.o build/gen/console.s
$B/cl65 -t plus4 -C paradroid.cfg -m build/paradroid.map -Ln build/paradroid.lbl \
    -o build/paradroid.prg build/paradroid.o build/deck.o build/droids.o \
    build/draw.o build/transfer.o build/lift.o build/console.o build/title.o build/engine.o build/xfer.o build/fastload.o build/music.o build/move.o build/sfxcall.o \
    build/data.o build/brief.o build/condata.o build/fastinit.o build/drivecode.o \
    build/sfx.o

# The disk (tools/d64.py): the files the fast loader loads nearest the
# directory, their sectors IL apart: the console first, then the title,
# then the droids' pictures (three blocks each, a track further matters
# little to them); the program, which the KERNAL loads, after them, 10
# apart as the DOS would put them, and first in the directory, so that
# LOAD"*" finds it.
IL=${IL:-8}
set -- build/paradroid.d64 "paradroid,pd" build/console.bin:console:$IL \
       build/title.bin:title:$IL
for f in build/pics/p*; do
    set -- "$@" "$f:$(basename "$f"):$IL"
done
python3 tools/d64.py "$@" build/paradroid.prg:!paradroid:10
echo "build/paradroid.d64: $(ls build/pics | wc -l) pictures, interleave $IL"
