#!/bin/sh
# Start Stardew Pond in plus4emu (a PAL Plus/4 with 64 KB and a 1541) from
# its disk: the game loads rooms and tile sets as it goes. The disk of the
# .prg given (build/stardew-test.prg: the test build's). plus4emu is the
# one of the three that shows what a real TED does when a colour register
# is written while the beam draws that colour (tests/p4emu_snow.py).
# Setting plus4emu up: see ../paradroid/run-plus4emu.sh.
#
# Joystick: the keypad (8/2/4/6, 0 fires) or a gamepad through SDL.
cd "$(dirname "$0")"
D64="$(pwd)/build/$(basename "${1:-stardew.prg}" .prg).d64"
CFG="$HOME/.plus4emu/config/P4_64k_PAL.cfg"
EMU=${PLUS4EMU-$HOME/.cache/plus4emu/plus4emu-1.2.11-beta_20190320/plus4emu}
if [ ! -x "$EMU" ]; then
    echo "$EMU not there (see ../paradroid/run-plus4emu.sh): the system's plus4emu instead" >&2
    EMU=plus4emu
fi

if [ -f /.flatpak-info ]; then
    # (started from VS Code's flatpak: the emulator runs on the host)
    exec flatpak-spawn --host "$EMU" -cfg "$CFG" -disk "$D64"
fi
exec "$EMU" -cfg "$CFG" -disk "$D64"
