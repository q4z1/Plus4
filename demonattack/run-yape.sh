#!/bin/sh
# Start Demon Attack in Yape - as the cartridge, on a C16 with 16 KB.
# Called by the root's run script when the F5 configuration for Yape is
# chosen (it passes the .prg, which is not needed here); works on its own
# too.
#
# Yape has no command-line option for a cartridge, nor for the RAM size:
# both are settings in its yape.conf. So Yape gets a configuration of its
# own (XDG_DATA_HOME: Yape keeps it under SDL's "pref path"), written
# afresh for each start - the user's own yape.conf is not touched, and a
# Yape started any other way is the usual Plus/4 without a cartridge. The
# display settings are taken over from the user's yape.conf if there is
# one.
#
# The cartridge goes into ROMC2: Yape counts the banks from 0, so that is
# bank 2, C1, where a real cartridge sits. A 32 KB image fills its low and
# high half from the one file. Yape as it comes loads the ROMs its settings
# name only at a hard reset, not at start-up: there the machine comes up in
# BASIC and shift+F11 starts the cartridge. The patched Yape does it at
# once (../paradroid/tools/yape.patch).
#
# Which Yape, and the gamepad: as for Paradroid, see ../paradroid/run-yape.sh.
# In short: the patched Yape if it is built, the Steam Deck's own controller
# hidden from SDL, the Xbox controller's left stick given to SDL as its
# right one too (Yape reads the right stick), and the gamepad's buttons kept
# from Yape's own functions. Without that, a stick SDL maps wrongly holds a
# joystick direction down - which the machine reads as a key, a D that
# types itself.
cd "$(dirname "$0")"
BIN="$(pwd)/build/demonattack.bin"
if [ ! -f "$BIN" ]; then
    echo "$BIN is not built yet: ./build.sh" >&2
    exit 1
fi
IGNORE=${YAPE_PAD_IGNORE-0x28de/0x1205}
MAP=${YAPE_PAD_MAP-"050018dc5e040000e002000003090000,Xbox One S Controller,a:b0,b:b1,x:b2,y:b3,back:b6,start:b7,guide:b10,leftshoulder:b4,rightshoulder:b5,leftstick:b8,rightstick:b9,dpup:h0.1,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,leftx:a0,lefty:a1,rightx:a0,righty:a1,lefttrigger:a2,righttrigger:a5,platform:Linux,"}
YAPE=${YAPE-$HOME/.cache/paradroid/yapesdl/yapesdl}
if [ ! -x "$YAPE" ]; then
    echo "$YAPE not built (see ../paradroid/run-yape.sh): the system's yape instead -" >&2
    echo "its gamepad lags, B steps the active joystick on, and the cartridge" >&2
    echo "only starts after shift+F11." >&2
    YAPE=yape
fi

# Yape's own configuration for this, from the user's display settings
DATA="$HOME/.cache/demonattack/yapehome"
CONF="$DATA/Gaia/yapeSDL/yape.conf"
USERCONF="$HOME/.local/share/Gaia/yapeSDL/yape.conf"
mkdir -p "$(dirname "$CONF")"
{
    echo '[Yape configuration file]'
    if [ -f "$USERCONF" ]; then
        grep -E '^(DisplayFrameRate|DisplayQuickDebugInfo|CRTEmulation|WindowMultiplier|JoystickKeysIndex) = ' "$USERCONF"
    fi
    echo '50HzTimerActive = 1'
    echo 'ActiveJoystick = 0'       # one controller on both joystick ports
    echo 'RamMask = 3fff'           # 16 KB: a C16
    echo '256KBRAM = 0'
    echo 'SaveSettingsOnExit = 0'
    echo 'ROMC0LOW = BASIC'
    echo 'ROMC0HIGH = KERNAL'
    echo 'ROMC1LOW = '
    echo 'ROMC1HIGH = '
    echo "ROMC2LOW = $BIN"
    echo 'ROMC2HIGH = '
    echo 'ROMC3LOW = '
    echo 'ROMC3HIGH = '
    echo "CurrentDirectory = $(pwd)/build"
    echo 'EmulationLevel = 0'
} > "$CONF"

if [ -f /.flatpak-info ]; then
    # (started from VS Code's flatpak: Yape is the host's)
    exec flatpak-spawn --host --env=XDG_DATA_HOME="$DATA" \
        --env=SDL_GAMECONTROLLER_IGNORE_DEVICES="$IGNORE" \
        --env=SDL_GAMECONTROLLERCONFIG="$MAP" --env=YAPE_PADKEYS=off "$YAPE"
fi
XDG_DATA_HOME="$DATA" SDL_GAMECONTROLLER_IGNORE_DEVICES="$IGNORE" \
    SDL_GAMECONTROLLERCONFIG="$MAP" YAPE_PADKEYS=off exec "$YAPE"
