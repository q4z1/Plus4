#!/bin/sh
# Build echo.c, run it in VICE with the ACIA wired to a socket, and check
# that every byte survives the round trip. See ../README.md, stage three.
#
#   ./wiretest.sh [bytes in flight]      default 32
#
# 32 is not a round number picked for looks - see "What the wire turned out
# to be" in ../README.md. Pass 128 to watch it fail.
set -e

DIR=$(cd "$(dirname "$0")" && pwd)
BIN="$HOME/.local/share/cc65-vs64/bin"
PROBE=${1:-32}

mkdir -p "$DIR/build"
echo "Building echo.c ..."
"$BIN/cl65" -t plus4 -O -g -c -o "$DIR/build/echo.o" "$DIR/echo.c"
"$BIN/cl65" -t plus4 -o "$DIR/build/echo.prg" "$DIR/build/echo.o"

echo "Starting the checker ..."
python3 "$DIR/../proxy/wirecheck.py" --probe "$PROBE" --timeout 250 &
CHECKER=$!
sleep 1

# VICE runs on the host rather than in the editor's sandbox and inherits the
# working directory, so it is started from $HOME and given paths below it.
echo "Starting VICE ..."
cd "$HOME"
"$BIN/xplus4" -default -warp -autostartprgmode 1 \
    -acia -myaciadev 0 -rsdev1 127.0.0.1:6400 -rsdev1ip232 \
    -limitcycles 600000000 \
    -exitscreenshot "$DIR/build/echo.png" \
    -autostart "$DIR/build/echo.prg" >/dev/null 2>&1 || true

wait "$CHECKER"
