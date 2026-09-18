#!/bin/sh
# The one thing to call before the emulator: the proxy, with everything it
# needs already seen to.
#
#   ./start.sh                        the proxy
#   ./start.sh --login --ip232        the proxy, with arguments
#   ./start.sh lobbywatch.py --login  any of the tools beside it
#
# It builds the Python environment on the first run and generates the
# protobuf bindings if they are missing, so there is nothing to do first and
# nothing to remember. Which environment is the right one depends on whether
# this was started from the editor or from a host terminal - see env.sh.
set -e

DIR=$(cd "$(dirname "$0")" && pwd)

case "$1" in
    *.py)
        TOOL=$1
        shift
        ;;
    *)
        TOOL=proxy.py
        ;;
esac

if [ ! -f "$DIR/$TOOL" ]; then
    echo "No such tool: $TOOL" >&2
    exit 1
fi

PYTHON=$("$DIR/env.sh")
if [ ! -f "$DIR/gen/pokerth_pb2.py" ]; then
    "$DIR/build-proto.sh" >&2
fi

exec "$PYTHON" "$DIR/$TOOL" "$@"
