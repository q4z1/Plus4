#!/bin/sh
# Build Paradroid: build/paradroid.prg, one file with everything in it,
# packed by exomizer to load faster.
set -e
cd "$(dirname "$0")"
# not while a test runs: it would go on with the new files under it
python3 tests/onetest.py
B=${CC65_BIN:-$HOME/.local/share/cc65-vs64/bin}
export EXOMIZER=${EXOMIZER:-$B/exomizer}
mkdir -p build
asm() {
    $B/cl65 -t plus4 -g --asm-include-dir build/gen -c -o build/$1.o $1.s
}
# The data first (tools/mkdata.py: build/gen/), for the include files the
# code needs.
python3 tools/mkdata.py >/dev/null
for f in paradroid deck droids draw picture transfer screens title engine \
         xfer music briefrows move figs sfxcall sfx unpack startup sight; do
    asm $f
done
# What is used once at the start, then overwritten by the pictures' slots
# (23 of 512 bytes from data.s's INITDATA on: data.o is linked before the
# rest of it): data.s's own, and the code put elsewhere at the start (the
# sound effects' player, the unpacker, what runs at $F400) and the start's
# code itself. mkdata again, with their size, for the slots' rest.
INIT_EXTRA=0
for o in sfx:SFXCODE paradroid:SFXCODE move:SFXCODE unpack:UNPACK figs:HICODE draw:HICODE paradroid:HICODE \
         startup:INITDATA engine:INITCODE move:XT5 sight:PAGE1 sight:UNPACK \
         paradroid:LOWEND picture:LOWEND engine:HICODE figs:PAGE1 droids:UNPACK droids:HICODE droids:XT6 droids:XT7 droids:XT8 droids:XT9 droids:XT10 droids:XT11; do
    n=$($B/od65 -S build/${o%:*}.o | awk "/${o#*:}:/{print \$2}")
    INIT_EXTRA=$((INIT_EXTRA + ${n:-0}))
done
INIT_EXTRA=$INIT_EXTRA python3 tools/mkdata.py
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
        -o build/paradroid.raw build/paradroid.o build/deck.o build/droids.o \
        build/draw.o build/picture.o build/transfer.o build/screens.o build/title.o \
        build/engine.o build/xfer.o build/music.o build/briefrows.o build/move.o \
        build/figs.o build/sfxcall.o build/data.o build/brief.o build/condata.o \
        build/startup.o build/sfx.o build/unpack.o build/sight.o build/blobs.o
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
# The program packed as a whole (it starts with SYS from BASIC: exomizer
# keeps that, unpacks it into its place and starts it). The picture off
# from the start, the border black, no flashing while it unpacks: nothing
# shows till the title's first screen is whole (engine.s, eng_show).
$EXOMIZER sfx sys -t 4 -q -n -s 'lda #$0b sta $ff06 lda #0 sta $ff19' \
    -o build/paradroid.prg build/paradroid.raw
echo "build/paradroid.prg: $(stat -c%s build/paradroid.raw) bytes, packed $(stat -c%s build/paradroid.prg)"
