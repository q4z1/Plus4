#!/bin/sh
# Start Paradroid in Yape (Yape's TED is closer to the real chip than
# VICE's): the .prg given, else build/paradroid.prg. Called by the root's
# run script with the .prg when an F5 configuration for Yape is chosen
# (build/paradroid-god.prg for the immortal one); works on its own too.
#
# Which Yape: the one built with tools/yape.patch (in
# ~/.cache/paradroid/yapesdl, or $YAPE), else the system's. The patch is
# what makes a gamepad playable: Yape took one of SDL's events a frame,
# and a gamepad's stream of axis events left its stick seconds behind; and
# YAPE_PADKEYS=off keeps the gamepad's buttons from doing Yape's things (B
# stepped the active joystick on, LB typed RUN, RB opened the menu).
# Building it:
#   git clone https://github.com/calmopyrin/yapesdl ~/.cache/paradroid/yapesdl
#   cd ~/.cache/paradroid/yapesdl && git apply <this folder>/tools/yape.patch && make
#
# The program goes to Yape with its full path: Yape looks for a relative
# one in its own folder.
#
# The gamepad. Yape takes a game controller's right stick and its A button
# (through SDL) as the joystick, and the Steam Deck's own controller gets
# in the way of a second one. So, for the Xbox One S controller over
# Bluetooth this was set up for:
# - the Steam Deck's controller (28de:1205) hidden from SDL;
# - the Xbox controller's left stick given to SDL as its right one too,
#   A as fire (its own mapping: SDL's for it takes the right stick from the
#   wrong axes);
# - Yape's "active joy for keyset" put to NONE first: with one controller,
#   it is then on both joystick ports (BOTH would leave it on none).
# Another controller: YAPE_PAD_IGNORE and YAPE_PAD_MAP from outside (the
# mapping's GUID as SDL reports it for the controller).
if [ -n "$1" ]; then
    PRG="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
    cd "$(dirname "$0")"
else
    cd "$(dirname "$0")"
    PRG="$(pwd)/build/paradroid.prg"
fi
IGNORE=${YAPE_PAD_IGNORE-0x28de/0x1205}
MAP=${YAPE_PAD_MAP-"050018dc5e040000e002000003090000,Xbox One S Controller,a:b0,b:b1,x:b2,y:b3,back:b6,start:b7,guide:b10,leftshoulder:b4,rightshoulder:b5,leftstick:b8,rightstick:b9,dpup:h0.1,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,leftx:a0,lefty:a1,rightx:a0,righty:a1,lefttrigger:a2,righttrigger:a5,platform:Linux,"}
YAPE=${YAPE-$HOME/.cache/paradroid/yapesdl/yapesdl}
if [ ! -x "$YAPE" ]; then
    echo "$YAPE not built (see run-yape.sh): the system's yape instead -" >&2
    echo "its gamepad lags, and B steps the active joystick on." >&2
    YAPE=yape
fi

CONF="$HOME/.local/share/Gaia/yapeSDL/yape.conf"
if [ -f "$CONF" ]; then
    if grep -q '^ActiveJoystick' "$CONF"; then
        sed -i 's/^ActiveJoystick = .*/ActiveJoystick = 0/' "$CONF"
    else
        echo 'ActiveJoystick = 0' >> "$CONF"
    fi
fi

if [ -f /.flatpak-info ]; then
    # (started from VS Code's flatpak: Yape is the host's)
    exec flatpak-spawn --host --env=SDL_GAMECONTROLLER_IGNORE_DEVICES="$IGNORE" \
        --env=SDL_GAMECONTROLLERCONFIG="$MAP" --env=YAPE_PADKEYS=off "$YAPE" "$PRG"
fi
SDL_GAMECONTROLLER_IGNORE_DEVICES="$IGNORE" SDL_GAMECONTROLLERCONFIG="$MAP" YAPE_PADKEYS=off \
    exec "$YAPE" "$PRG"
