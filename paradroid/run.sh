#!/bin/sh
# Start Paradroid in VICE: the .prg is all there is. Called by the root's
# run script.
cd "$(dirname "$0")"
BIN_DIR="$HOME/.local/share/cc65-vs64/bin"
exec "$BIN_DIR/xplus4" -autostart build/paradroid.prg
