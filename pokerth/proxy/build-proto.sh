#!/bin/sh
# Generate the Python bindings for pokerth.proto into gen/.
#
# The bindings are build output and are not checked in (see .gitignore).
# With --fetch, the vendored copy of the .proto is refreshed from upstream
# first; see .proto-source.
set -e
cd "$(dirname "$0")"

PROTO_URL=https://raw.githubusercontent.com/pokerth/pokerth/stable/pokerth.proto

# env.sh owns the environment, because which one is right depends on which
# Python is running this - see the note in it.
PYTHON=$(./env.sh)

if [ "$1" = "--fetch" ]; then
	echo "Fetching pokerth.proto from upstream ..."
	curl -fsS -o pokerth.proto "$PROTO_URL"
fi

mkdir -p gen
"$PYTHON" -m grpc_tools.protoc -I. --python_out=gen pokerth.proto
echo "gen/pokerth_pb2.py written."
