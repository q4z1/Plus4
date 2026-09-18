#!/bin/sh
# Stands in for xplus4 when VS64 starts it.
#
# F5 inside this folder goes through VS64, which builds with its own toolchain
# and launches the emulator itself - so there is no place to add the serial
# arguments, and no place to start the proxy. Pointing vs64.viceExecutable at
# this script solves both: it starts the proxy, then runs the real emulator
# with the ACIA wired to it and everything VS64 asked for passed through
# untouched, debugger arguments and all.
#
# F5 at the top of the repository does not come this way; it uses run.sh.
set -e

DIR=$(cd "$(dirname "$0")" && pwd)
BIN="$HOME/.local/share/cc65-vs64/bin"
PROXY="$DIR/../proxy"
PORT=${PORT:-6400}
LOG="$DIR/build/proxy.log"

mkdir -p "$DIR/build"
PYTHON=$("$PROXY/env.sh" 2>/dev/null || true)
if [ -n "$PYTHON" ]; then
    [ -f "$PROXY/gen/pokerth_pb2.py" ] || "$PROXY/build-proto.sh" >&2
    "$PYTHON" "$PROXY/proxy.py" --login --ip232 \
        --listen "127.0.0.1:$PORT" > "$LOG" 2>&1 &
    PROXY_PID=$!
    trap 'kill $PROXY_PID 2>/dev/null' EXIT INT TERM

    waited=0
    while [ "$waited" -lt 60 ]; do
        grep -q "waiting for a Plus/4" "$LOG" 2>/dev/null && break
        kill -0 "$PROXY_PID" 2>/dev/null || break
        sleep 0.5
        waited=$((waited + 1))
    done
else
    echo "No Python for the proxy - see $PROXY/env.sh." >&2
fi

exec "$BIN/xplus4" \
    -acia -myaciadev 0 -rsdev1 "127.0.0.1:$PORT" -rsdev1ip232 -rsdev1baud 1200 \
    "$@"
