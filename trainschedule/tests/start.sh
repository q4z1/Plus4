#!/bin/sh
# Start trainschedule's test build: straight into a map, or straight to
# the choice of one, the maps locked as in a new game or all of them open.
#
#   tests/start.sh [MAP|choose] [locked|open] [yape|vice|plus4emu]
#
#   MAP       a map's number (1 Riesa, 2 Alessandria ...): straight into it,
#             no title, no choice (after it, OTHER MAP goes to the choice)
#   choose    straight to the choice of a map (the default)
#   locked    only the first map open, as in a new game (the default)
#   open      every map open
#   yape      Yape with the gamepad (run-yape.sh, the default); vice;
#             plus4emu (as Stardew Pond's run-plus4emu.sh)
#
# In any order. It builds first (build.sh with TEST_MAP: the game with two
# of its bytes set, test_map and unlocked) and starts
# build/trainschedule-test.d64.
set -e
cd "$(dirname "$0")/.."
MAP=255
UNLOCKED=1
EMU=yape
for a in "$@"; do
    case "$a" in
        choose) MAP=255 ;;
        [1-9]) MAP=$a ;;
        locked) UNLOCKED=1 ;;
        open) UNLOCKED=255 ;;
        yape|vice|plus4emu) EMU=$a ;;
        *) echo "start.sh: what is '$a'? [MAP|choose] [locked|open] [yape|vice|plus4emu]" >&2
           exit 1 ;;
    esac
done
TEST_MAP=$MAP TEST_UNLOCKED=$UNLOCKED sh build.sh
D64="$(pwd)/build/trainschedule-test.d64"
case "$EMU" in
    yape)
        exec ../paradroid/run-yape.sh "$D64" ;;
    vice)
        # a 1541, so the fast loader runs (xplus4's own default is a 1551)
        exec "${CC65_BIN:-$HOME/.local/share/cc65-vs64/bin}/xplus4" \
            -drive8type 1541 -autostart "$D64" ;;
    plus4emu)
        CFG="$HOME/.plus4emu/config/P4_64k_PAL.cfg"
        P4=${PLUS4EMU-$HOME/.cache/plus4emu/plus4emu-1.2.11-beta_20190320/plus4emu}
        [ -x "$P4" ] || P4=plus4emu
        if [ -f /.flatpak-info ]; then
            exec flatpak-spawn --host "$P4" -cfg "$CFG" -disk "$D64"
        fi
        exec "$P4" -cfg "$CFG" -disk "$D64" ;;
esac
