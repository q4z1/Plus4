#!/bin/sh
# Build Paradroid: build/paradroid.prg and the disk it runs from,
# build/paradroid.d64, with the droids' pictures p00-p23.
set -e
cd "$(dirname "$0")"
# not while a test runs: it would go on with the new files under it
python3 tests/onetest.py
B=${CC65_BIN:-$HOME/.local/share/cc65-vs64/bin}
mkdir -p build
# the fast loader's drive code for a 1551, run at $0500 there, and what
# puts it there at the start: their size in INITDATA, which the
# pictures' slots take over afterwards, goes to mkdata (linked after
# data.o: the slots start where data.s's INITDATA does)
$B/cl65 -t none --start-addr 0x0500 -o build/drive1551.bin drive1551.s
$B/cl65 -t none --start-addr 0x0500 -o build/drive1541.bin drive1541.s
$B/cl65 -t plus4 -g -c -o build/drivecode.o build_drive.s
$B/cl65 -t plus4 -g -c -o build/sfx.o sfx.s
$B/cl65 -t plus4 -g -c -o build/unpack.o unpack.s
# exomizer packs: the decks' maps (mkdata.py)
export EXOMIZER=${EXOMIZER:-$B/exomizer}
INIT_EXTRA=0
for o in build/drivecode.o; do
    n=$($B/od65 -S $o | awk '/INITDATA:/{print $2}')
    INIT_EXTRA=$((INIT_EXTRA + ${n:-0}))
done
# (the sound effects' player too: it is copied to $FC00 at the start; and
# the Plus/4's halves of the fast loaders, one of which goes to FLRUN)
n=$($B/od65 -S build/sfx.o | awk '/SFXCODE:/{print $2}')
INIT_EXTRA=$((INIT_EXTRA + ${n:-0}))
n=$($B/od65 -S build/unpack.o | awk '/UNPACK:/{print $2}')
INIT_EXTRA=$((INIT_EXTRA + ${n:-0}))
$B/cl65 -t plus4 -g -c -o build/fastload51.o fastload51.s
$B/cl65 -t plus4 -g -c -o build/fastload41.o fastload41.s
for o in build/fastload51.o:FL51 build/fastload41.o:FL41; do
    n=$($B/od65 -S ${o%:*} | awk "/${o#*:}:/{print \$2}")
    INIT_EXTRA=$((INIT_EXTRA + ${n:-0}))
done
INIT_EXTRA=$INIT_EXTRA python3 tools/mkdata.py
# (and the console's and the figures' code, copied to $F400 at the start:
# its size is known once they are compiled, which needs mkdata's data.h -
# so mkdata again, with that)
$B/cl65 -t plus4 -O -Cl -g -I build/gen -c -o build/console.o console.c
$B/cl65 -t plus4 -g -c -o build/figs.o figs.s
for o in build/figs.o; do
    n=$($B/od65 -S $o | awk '/HICODE:/{print $2}')
    INIT_EXTRA=$((INIT_EXTRA + ${n:-0}))
done
# (and the rest of the start, fastinit.c, which needs data.h too)
$B/cl65 -t plus4 -O -Cl -g -I build/gen -c -o build/fastinit.o fastinit.c
n=$($B/od65 -S build/fastinit.o | awk '/INITDATA:/{print $2}')
INIT_EXTRA=$((INIT_EXTRA + ${n:-0}))
INIT_EXTRA=$INIT_EXTRA python3 tools/mkdata.py
for f in disk lift title; do
    $B/cl65 -t plus4 -O -Cl -g -I build/gen -c -o build/$f.o $f.c
done
$B/cl65 -t plus4 -g -c -o build/engine.o engine.s
$B/cl65 -t plus4 -g --asm-include-dir build/gen -c -o build/droids.o droids.s
$B/cl65 -t plus4 -g -c -o build/draw.o draw.s
$B/cl65 -t plus4 -g -c -o build/deck.o deck.s
$B/cl65 -t plus4 -g --asm-include-dir build/gen -c -o build/paradroid.o paradroid.s
$B/cl65 -t plus4 -g -c -o build/picture.o picture.s
$B/cl65 -t plus4 -g --asm-include-dir build/gen -c -o build/transfer.o transfer.s
$B/cl65 -t plus4 -g -c -o build/xfer.o xfer.s
$B/cl65 -t plus4 -g -c -o build/fastload.o fastload.s
$B/cl65 -t plus4 -g -c -o build/music.o music.s
$B/cl65 -t plus4 -g -c -o build/briefrows.o briefrows.s
$B/cl65 -t plus4 -g -c -o build/move.o move.s
$B/cl65 -t plus4 -g --asm-include-dir build/gen -c -o build/sfxcall.o sfxcall.s
# (and the engine's start-up, in INITCODE right after INITDATA - not in
# it, as the slots start at its data's beginning: the data again with it)
n=$($B/od65 -S build/engine.o | awk '/INITCODE:/{print $2}')
INIT_EXTRA=$((INIT_EXTRA + ${n:-0})) python3 tools/mkdata.py >/dev/null
$B/cl65 -t plus4 -g -c -o build/data.o build/gen/data.s
$B/cl65 -t plus4 -g -c -o build/brief.o build/gen/brief.s
$B/cl65 -t plus4 -g -c -o build/condata.o build/gen/console.s
# Linked twice: the overlays kept packed in the program (BLOBS, its last
# segment, so nothing else moves) are packed from the first link's, then
# go into the second. They must not refer to BLOBS themselves: the two
# links' overlays are compared.
OVLS="con xfer title"
link() {
    $B/cl65 -t plus4 -C paradroid.cfg -m build/paradroid.map -Ln build/paradroid.lbl \
        -o build/paradroid.prg build/paradroid.o build/deck.o build/droids.o \
        build/draw.o build/picture.o build/disk.o build/transfer.o build/lift.o build/console.o build/title.o build/engine.o build/xfer.o build/fastload.o build/fastload51.o build/fastload41.o build/music.o build/briefrows.o build/move.o build/figs.o build/sfxcall.o \
        build/data.o build/brief.o build/condata.o build/fastinit.o build/drivecode.o \
        build/sfx.o build/unpack.o build/blobs.o
}
blobs() {
    {
        echo '; made by build.sh - do not edit'
        echo '        .segment "BLOBS"'
        for o in $OVLS; do
            echo "        .export _blob_$o"
            if [ "$1" = packed ]; then
                echo "_blob_$o: .incbin \"build/$o.exo\""
            else
                echo "_blob_$o:"
            fi
        done
    } > build/gen/blobs.s
    $B/cl65 -t plus4 -c -o build/blobs.o build/gen/blobs.s
}
blobs
link
for o in $OVLS; do
    cp build/$o.bin build/$o.bin.1
    $EXOMIZER raw -q -o build/$o.exo build/$o.bin
done
blobs packed
link
for o in $OVLS; do
    cmp -s build/$o.bin build/$o.bin.1 || { echo "overlay $o refers to BLOBS" >&2; exit 1; }
    echo "overlay $o: $(stat -c%s build/$o.bin) bytes, packed $(stat -c%s build/$o.exo)"
done

# The disk (tools/d64.py): the files the fast loader loads nearest the
# directory, their sectors IL apart: the title first, then the droids'
# pictures (three blocks each, a track further matters
# little to them); the program, which the KERNAL loads, after them, 10
# apart as the DOS would put them, and first in the directory, so that
# LOAD"*" finds it. IL 10: a 1541 with its fast loader reads, decodes and
# sends a sector in about 95 ms, ten sectors' time; a 1551 would be a
# little faster with 8 (5.2 s for the title instead of 6.0; the 1541
# 10.9 s instead of 4.3).
IL=${IL:-10}
set -- build/paradroid.d64 "paradroid,pd"
for f in build/pics/p*; do
    set -- "$@" "$f:$(basename "$f"):$IL"
done
python3 tools/d64.py "$@" build/paradroid.prg:!paradroid:10
echo "build/paradroid.d64: $(ls build/pics | wc -l) pictures, interleave $IL"
