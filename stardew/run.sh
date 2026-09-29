#!/bin/sh
# Start Stardew Pond in VICE from its disk: the program loads
# rooms and tile sets as it goes, so it has to run from the .d64, not from
# the .prg on its own. Called by the root's run script with the .prg.
cd "$(dirname "$0")"
BIN_DIR="$HOME/.local/share/cc65-vs64/bin"
exec "$BIN_DIR/xplus4" -autostart build/stardew.d64
