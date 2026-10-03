#!/bin/sh
# Baut die uebergebene .c-Datei fuer den Commodore Plus/4 und startet sie in VICE.
#
# Das Ergebnis landet im build/-Verzeichnis neben der Quelldatei - also z.B.
# main/build/main.prg fuer main/main.c. Damit passt es zu dem Layout, das VS64
# beim direkten Oeffnen eines Programmordners selbst verwendet.
#
# Aufruf: run-current.sh <pfad/zur/datei.c>

set -e

SRC="$1"
BIN_DIR="$HOME/.local/share/cc65-vs64/bin"

if [ -z "$SRC" ]; then
    echo "Fehler: Keine Quelldatei uebergeben." >&2
    echo "In VS Code muss eine .c-Datei im Editor aktiv sein." >&2
    exit 1
fi

case "$SRC" in
    *.c) ;;
    *)
        echo "Fehler: '$SRC' ist keine .c-Datei." >&2
        echo "Bitte die zu startende .c-Datei im Editor aktivieren und F5 erneut druecken." >&2
        exit 1
        ;;
esac

if [ ! -f "$SRC" ]; then
    echo "Fehler: '$SRC' existiert nicht." >&2
    exit 1
fi

DIR=$(dirname "$SRC")
NAME=$(basename "$SRC" .c)
OUT="$DIR/build"

mkdir -p "$OUT"

# Ein Programm darf eigene Uebersetzerschalter mitbringen: liegt neben der
# Quelle eine Datei cflags, wird ihr Inhalt an cl65 angehaengt. Phoenix
# braucht so -Cl, weil cc65 lokale Variablen sonst ueber seinen
# Software-Stack fuehrt und das dort ein Sechstel der Rechenzeit kostet.
EXTRA=""
if [ -f "$DIR/cflags" ]; then
    EXTRA=$(cat "$DIR/cflags")
fi

# A program made of several sources (C plus assembler, its own linker
# configuration) brings its own build.sh, which must leave
# build/<name>.prg behind. Everything else is one .c file, built here.
if [ -f "$DIR/build.sh" ]; then
    echo "Baue $NAME ueber $DIR/build.sh ..."
    CC65_BIN="$BIN_DIR" sh "$DIR/build.sh"
else
    # Zwei Stufen, damit die Objektdatei in build/ landet - cl65 legt sie sonst
    # immer neben der Quelldatei ab.
    echo "Baue $NAME.c ..."
    # shellcheck disable=SC2086
    "$BIN_DIR/cl65" -t plus4 -O $EXTRA -g -c -o "$OUT/$NAME.o" "$SRC"
    "$BIN_DIR/cl65" -t plus4 -o "$OUT/$NAME.prg" "$OUT/$NAME.o"
fi
echo "Fertig: $OUT/$NAME.prg"

# The emulator: VICE, or Yape with PLUS4_EMU=yape (the F5 configuration
# "... in Yape"), whose TED is closer to the real chip. A program may bring
# its own run-yape.sh for that (Paradroid: its disk, the gamepad). Yape
# looks for a relative file name in its own folder, so it gets the full
# path; from VS Code's flatpak it is started on the host.
if [ "$PLUS4_EMU" = yape ]; then
    if [ -x "$DIR/run-yape.sh" ]; then
        echo "Starte ueber $DIR/run-yape.sh ..."
        exec "$DIR/run-yape.sh" "$OUT/$NAME.prg"
    fi
    PRG="$(cd "$OUT" && pwd)/$NAME.prg"
    echo "Starte Yape ..."
    if [ -f /.flatpak-info ]; then
        exec flatpak-spawn --host yape "$PRG"
    fi
    exec yape "$PRG"
fi

# A program may bring its own runner. The PokerTH client needs a proxy
# started next to the emulator and the ACIA wired to it, which is nobody
# else's business - so if <programm>/run.sh exists, it takes over from here
# and gets the finished .prg passed to it.
if [ -x "$DIR/run.sh" ]; then
    echo "Starte ueber $DIR/run.sh ..."
    exec "$DIR/run.sh" "$OUT/$NAME.prg"
fi

echo "Starte VICE ..."
exec "$BIN_DIR/xplus4" -autostartprgmode 1 "$OUT/$NAME.prg"
