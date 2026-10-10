#!/bin/sh
# Start Stardew Pond in VICE from its disk: the program loads rooms and
# tile sets as it goes, so it has to run from the .d64, not from the .prg
# on its own. Called by the root's run script with the .prg: the disk is
# the one of the same name (build/stardew-test.prg: the test build's).
cd "$(dirname "$0")"
D64=build/$(basename "${1:-stardew.prg}" .prg).d64
BIN_DIR="$HOME/.local/share/cc65-vs64/bin"
exec "$BIN_DIR/xplus4" -autostart "$D64"
