#!/bin/sh
# Prints the Python that runs the proxy, building its environment if needed.
#
# There are two Pythons on this machine: VS Code runs as a Flatpak and brings
# its own, the host terminal has another, and they are not the same version.
# A virtual environment only works with the interpreter that created it - the
# other one looks for a site-packages directory that is not there and reports
# that protobuf does not exist, which is a confusing way to say "wrong
# Python". So the environment is named after the version and both can sit
# side by side; whichever one you start from finds its own.
set -e

DIR=$(cd "$(dirname "$0")" && pwd)
VERSION=$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')
VENV="$DIR/.venv-$VERSION"

if [ ! -x "$VENV/bin/python" ]; then
    echo "Creating a Python $VERSION environment in $VENV ..." >&2
    python3 -m venv "$VENV" >&2
    "$VENV/bin/pip" install -q --upgrade pip >&2
    "$VENV/bin/pip" install -q -r "$DIR/requirements.txt" >&2
fi

echo "$VENV/bin/python"
