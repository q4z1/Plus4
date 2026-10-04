#!/bin/sh
# Build Demon Attack, in two forms from the same source:
#
#   build/demonattack.prg   for the Plus/4, loaded from disk
#   build/demonattack.bin   a 32 KB cartridge image for the C16 and the
#                           Plus/4: C1 low ($8000) in the first 16 KB, C1
#                           high ($C000) in the second
#
# With DEBUG=1 also the test version build/dbg.prg that the comparison
# scripts drive.
set -e
cd "$(dirname "$0")"
B=${CC65_BIN:-$HOME/.local/share/cc65-vs64/bin}
mkdir -p build

python3 mktables.py demonattack.c > build/tables.s
$B/cl65 -t plus4 -g -c -o build/tables.o build/tables.s

# the PRG
$B/cl65 -t plus4 -O -Cl -g -c -o build/demonattack.o demonattack.c
$B/cl65 -t plus4 -g -c -o build/engine.o engine.s
$B/cl65 -t plus4 -g -c -o build/kernel.o kernel.s
$B/cl65 -t plus4 -C demonattack.cfg -m build/demonattack.map -Ln build/demonattack.lbl \
    -o build/demonattack.prg build/demonattack.o build/engine.o build/kernel.o build/tables.o

# the cartridge
$B/cl65 -t plus4 -O -Cl -g -DCART -c -o build/cart_c.o demonattack.c
$B/cl65 -t plus4 -g --asm-define CART -c -o build/cart_engine.o engine.s
$B/cl65 -t plus4 -g --asm-define CART -c -o build/cart_kernel.o kernel.s
$B/cl65 -t plus4 -g -c -o build/crt0_cart.o crt0_cart.s
$B/cl65 -t plus4 -C demonattack_cart.cfg -m build/cart.map -Ln build/cart.lbl \
    -o build/demonattack.bin build/crt0_cart.o build/cart_c.o build/cart_engine.o \
    build/cart_kernel.o build/tables.o
size=$(wc -c < build/demonattack.bin)
if [ "$size" -ne 32768 ]; then
    echo "cartridge image is $size bytes, not 32768" >&2
    exit 1
fi

if [ -n "$DEBUG" ]; then
    $B/cl65 -t plus4 -O -Cl -DDEBUG -g -c -o build/dbg.o demonattack.c
    $B/cl65 -t plus4 -C demonattack.cfg -Ln build/dbg.lbl -o build/dbg.prg \
        build/dbg.o build/engine.o build/kernel.o build/tables.o
fi
