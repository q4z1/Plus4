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

# Zwei Stufen, damit die Objektdatei in build/ landet - cl65 legt sie sonst
# immer neben der Quelldatei ab.
echo "Baue $NAME.c ..."
"$BIN_DIR/cl65" -t plus4 -O -g -c -o "$OUT/$NAME.o" "$SRC"
"$BIN_DIR/cl65" -t plus4 -o "$OUT/$NAME.prg" "$OUT/$NAME.o"
echo "Fertig: $OUT/$NAME.prg"

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
