#!/bin/sh
# Build client.c and run it in VICE with the ACIA wired to the proxy.
#
# Start the proxy first, in another terminal:
#   ../proxy/proxy.py --login --ip232
#
#   ./run.sh [port]        default 6400
set -e

DIR=$(cd "$(dirname "$0")" && pwd)
BIN="$HOME/.local/share/cc65-vs64/bin"
PORT=${1:-6400}

mkdir -p "$DIR/build"
"$BIN/cl65" -t plus4 -O -g -c -o "$DIR/build/client.o" "$DIR/client.c"
"$BIN/cl65" -t plus4 -o "$DIR/build/client.prg" "$DIR/build/client.o"

# VICE runs on the host and inherits the working directory, so it is started
# from $HOME and given paths below it.
cd "$HOME"
exec "$BIN/xplus4" -autostartprgmode 1 \
    -acia -myaciadev 0 -rsdev1 "127.0.0.1:$PORT" -rsdev1ip232 \
    -autostart "$DIR/build/client.prg"
