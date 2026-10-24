#!/bin/sh
# Builds or installs the tools for looking at Amiga programs (the originals
# of ports to the Plus/4). Whatever is already there is skipped.
#
#   tools/bin/amiga-run  script-driven Amiga emulator (tools/amiga-run/, on
#                        the vAmiga core, cloned into tools/src/vAmiga)
#   tools/python/        capstone, the disassembler module tools/bin/m68k-dis.py uses
#
# tools/bin/adf.py and tools/bin/m68k-dis.py are scripts and are ready to use.
# A Kickstart ROM is not included: put your own copy into toolchain/ as a .rom.
#
# Usage: toolchain/setup.sh

set -e

TC=$(cd "$(dirname "$0")" && pwd)
HERE="$TC/tools"
# vAmiga's core, pinned to a known-good commit
VAMIGA_REPO=https://github.com/dirkwhoffmann/vAmiga.git
VAMIGA_COMMIT=c38fa527ea97b9b0036c0e58526cf2714fd97213

mkdir -p "$HERE/src" "$HERE/bin"

if [ ! -f "$HERE/python/capstone/__init__.py" ]; then
    python3 -m pip install -q --target "$HERE/python" capstone
fi

if [ ! -x "$HERE/bin/amiga-run" ]; then
    if [ ! -d "$HERE/src/vAmiga/.git" ]; then
        git clone -q "$VAMIGA_REPO" "$HERE/src/vAmiga"
    fi
    git -C "$HERE/src/vAmiga" fetch -q --depth 1 origin "$VAMIGA_COMMIT" 2>/dev/null || true
    git -C "$HERE/src/vAmiga" checkout -q "$VAMIGA_COMMIT"
    # this vAmiga commit uses std::format without including <format>
    cmake -S "$HERE/amiga-run" -B "$HERE/src/amiga-run-build" -DCMAKE_BUILD_TYPE=Release \
        -DVAMIGA_CORE="$HERE/src/vAmiga/Core" -DCMAKE_CXX_FLAGS="-include format" >/dev/null
    cmake --build "$HERE/src/amiga-run-build" -j"$(nproc)" --target amiga-run >/dev/null
    cp "$HERE/src/amiga-run-build/amiga-run" "$HERE/bin/"
fi

echo "Tools ready in $HERE/bin."
