#!/bin/sh
# Start Paradroid in plus4emu (a PAL Plus/4 with 64 KB): build/paradroid.prg,
# which is all there is. A third opinion next to VICE and Yape.
#
# Which plus4emu: $PLUS4EMU, else the prebuilt Linux release unpacked in
# ~/.cache/plus4emu, else the system's. Setting it up:
#   mkdir -p ~/.cache/plus4emu && cd ~/.cache/plus4emu
#   curl -LO https://github.com/istvan-v/plus4emu/releases/download/1.2.11-beta_20190320/plus4emu-1.2.11-beta_20190320-x86_64.tar.xz
#   tar xf plus4emu-*.tar.xz
#   mkdir -p ~/.plus4emu/roms && cp plus4emu-*/roms/*.rom ~/.plus4emu/roms/
#   plus4emu-*/p4makecfg ~/.plus4emu
# (p4makecfg takes its one argument as the folder: "-h" makes a folder "-h".)
#
# Joystick: the keypad (8/2/4/6, 0 fires) or a gamepad through SDL.
cd "$(dirname "$0")"
PRG="$(pwd)/build/paradroid.prg"
CFG="$HOME/.plus4emu/config/P4_64k_PAL.cfg"
EMU=${PLUS4EMU-$HOME/.cache/plus4emu/plus4emu-1.2.11-beta_20190320/plus4emu}
if [ ! -x "$EMU" ]; then
    echo "$EMU not there (see run-plus4emu.sh): the system's plus4emu instead" >&2
    EMU=plus4emu
fi

if [ -f /.flatpak-info ]; then
    # (started from VS Code's flatpak: the emulator runs on the host)
    exec flatpak-spawn --host "$EMU" -cfg "$CFG" "$PRG"
fi
exec "$EMU" -cfg "$CFG" "$PRG"
