#!/bin/sh
# Start the proxy and the client together.
#
# This is what F5 ends up calling when client.c is the file in the editor:
# the top level run-current.sh builds the program and hands the .prg over.
# It can also be run by hand:
#
#   ./run.sh                 build, then start proxy and emulator
#   ./run.sh some.prg        skip the build and run that
#   PORT=6401 ./run.sh       somewhere else
#
# The proxy stops any older copy of itself when it starts, so pressing F5
# twice is not a problem. It is stopped again when the emulator exits.
set -e

DIR=$(cd "$(dirname "$0")" && pwd)
BIN="$HOME/.local/share/cc65-vs64/bin"
PROXY="$DIR/../proxy"
PORT=${PORT:-6400}
PRG=$1

if [ -z "$PRG" ]; then
    echo "Building client.c ..."
    mkdir -p "$DIR/build"
    "$BIN/cl65" -t plus4 -O -g -c -o "$DIR/build/client.o" "$DIR/client.c"
    "$BIN/cl65" -t plus4 -o "$DIR/build/client.prg" "$DIR/build/client.o"
    PRG="$DIR/build/client.prg"
fi

LOG="$DIR/build/proxy.log"
echo "Starting the proxy, logging to $LOG ..."
# start.sh sees to the environment and the bindings itself, so there is
# nothing to do first.
"$PROXY/start.sh" --login --ip232 --listen "127.0.0.1:$PORT" > "$LOG" 2>&1 &
PROXY_PID=$!
trap 'kill $PROXY_PID 2>/dev/null' EXIT INT TERM

# Wait until it says it is listening, rather than guessing how long a login
# takes. It announces itself in the log once the server has let it in.
waited=0
while [ "$waited" -lt 60 ]; do
    if grep -q "waiting for a Plus/4" "$LOG" 2>/dev/null; then
        break
    fi
    if ! kill -0 "$PROXY_PID" 2>/dev/null; then
        echo "The proxy stopped before it was ready:" >&2
        tail -5 "$LOG" >&2
        exit 1
    fi
    sleep 0.5
    waited=$((waited + 1))
done

# VICE runs on the host and inherits the working directory, so it is started
# from $HOME and given paths below it.
cd "$HOME"
"$BIN/xplus4" -autostartprgmode 1 \
    -acia -myaciadev 0 -rsdev1 "127.0.0.1:$PORT" -rsdev1ip232 -rsdev1baud 1200 \
    -autostart "$PRG"
