#!/bin/sh
# Generate the Python bindings for pokerth.proto into gen/.
#
# The bindings are build output and are not checked in (see .gitignore).
# With --fetch, the vendored copy of the .proto is refreshed from upstream
# first; see .proto-source.
set -e
cd "$(dirname "$0")"

VENV=.venv
PROTO_URL=https://raw.githubusercontent.com/pokerth/pokerth/stable/pokerth.proto

if [ ! -x "$VENV/bin/python" ]; then
	echo "Creating $VENV ..."
	python3 -m venv "$VENV"
	"$VENV/bin/pip" install -q --upgrade pip
	"$VENV/bin/pip" install -q -r requirements.txt
fi

if [ "$1" = "--fetch" ]; then
	echo "Fetching pokerth.proto from upstream ..."
	curl -fsS -o pokerth.proto "$PROTO_URL"
fi

mkdir -p gen
"$VENV/bin/python" -m grpc_tools.protoc -I. --python_out=gen pokerth.proto
echo "gen/pokerth_pb2.py written."
