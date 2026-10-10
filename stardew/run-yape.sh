#!/bin/sh
# Start Stardew Pond in Yape from its disk (the game loads rooms and tile
# sets as it goes, so the .prg alone would not do). Called by the root's
# run script when the F5 configuration "... in Yape" is chosen. Yape and
# the gamepad are set up as for Paradroid: its run-yape.sh does the rest.
cd "$(dirname "$0")"
exec ../paradroid/run-yape.sh "$(pwd)/build/stardew.d64"
