#!/bin/sh
# Start Paradroid in Yape from its disk (Yape's TED is closer to the real
# chip than VICE's). Called by the root's run script with the .prg when
# the F5 configuration for Yape is chosen; works on its own too.
#
# The disk image goes to Yape with its full path: Yape looks for a
# relative one in its own folder.
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
#   it is then on both joystick ports. BOTH would leave it on none, and
#   the controller's B button steps through them (NONE, PORT1, PORT2,
#   BOTH); its LB types RUN, RB opens the menu.
# Another controller: YAPE_PAD_IGNORE and YAPE_PAD_MAP from outside (the
# mapping's GUID as SDL reports it for the controller).
cd "$(dirname "$0")"
D64="$(pwd)/build/paradroid.d64"
IGNORE=${YAPE_PAD_IGNORE-0x28de/0x1205}
MAP=${YAPE_PAD_MAP-"050018dc5e040000e002000003090000,Xbox One S Controller,a:b0,b:b1,x:b2,y:b3,back:b6,start:b7,guide:b10,leftshoulder:b4,rightshoulder:b5,leftstick:b8,rightstick:b9,dpup:h0.1,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,leftx:a0,lefty:a1,rightx:a0,righty:a1,lefttrigger:a2,righttrigger:a5,platform:Linux,"}

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
        --env=SDL_GAMECONTROLLERCONFIG="$MAP" yape "$D64"
fi
SDL_GAMECONTROLLER_IGNORE_DEVICES="$IGNORE" SDL_GAMECONTROLLERCONFIG="$MAP" exec yape "$D64"
