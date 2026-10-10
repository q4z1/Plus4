#!/bin/sh
# Start Stardew Pond in Yape from its disk (the game loads rooms and tile
# sets as it goes, so the .prg alone would not do): the disk of the .prg
# given, build/stardew-test.prg the test build's. Called by the root's run
# script when an F5 configuration for Yape is chosen. Yape and the gamepad
# are set up as for Paradroid: its run-yape.sh does the rest.
cd "$(dirname "$0")"
exec ../paradroid/run-yape.sh "$(pwd)/build/$(basename "${1:-stardew.prg}" .prg).d64"
