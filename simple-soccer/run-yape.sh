#!/bin/sh
# Start Simple Soccer in Yape. Called by the root's run script when an
# F5 configuration for Yape is chosen. Yape and the gamepad are set up as
# for Paradroid - the patched Yape, the Steam Deck's controller hidden,
# the Xbox controller's left stick and A as the joystick, its buttons kept
# from Yape's own functions: its run-yape.sh does that.
cd "$(dirname "$0")"
exec ../paradroid/run-yape.sh "$(pwd)/build/simple-soccer.d64"
