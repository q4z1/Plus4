#!/bin/sh
# Build Demon Attack: build/demonattack.prg, and with DEBUG=1 the test
# version build/dbg.prg that the comparison scripts drive.
set -e
cd "$(dirname "$0")"
B=${CC65_BIN:-$HOME/.local/share/cc65-vs64/bin}
mkdir -p build
$B/cl65 -t plus4 -O -Cl -g -c -o build/demonattack.o demonattack.c
$B/cl65 -t plus4 -g -c -o build/engine.o engine.s
$B/cl65 -t plus4 -g -c -o build/kernel.o kernel.s
$B/cl65 -t plus4 -C demonattack.cfg -m build/demonattack.map -Ln build/demonattack.lbl \
    -o build/demonattack.prg build/demonattack.o build/engine.o build/kernel.o
if [ -n "$DEBUG" ]; then
    $B/cl65 -t plus4 -O -Cl -DDEBUG -g -c -o build/dbg.o demonattack.c
    $B/cl65 -t plus4 -C demonattack.cfg -Ln build/dbg.lbl -o build/dbg.prg \
        build/dbg.o build/engine.o build/kernel.o
fi
