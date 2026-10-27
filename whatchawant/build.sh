#!/bin/sh
# Build the demo: build/whatchawant.prg. The music's data first
# (tools/mkmusic.py: build/gen/music.inc), then the assembly (cl65 only
# assembles it and links). With --wav, also build/music.wav: the music as
# tools/mkmusic.py plays it in Python, to be listened to without the
# Plus/4 (WAV_SECONDS long, 60 if not said).
set -e
cd "$(dirname "$0")"
B=${CC65_BIN:-$HOME/.local/share/cc65-vs64/bin}
mkdir -p build/gen
python3 tools/mkmusic.py
for f in whatchawant music; do
    $B/cl65 -t plus4 -g --asm-include-dir build/gen -c -o build/$f.o $f.s
done
$B/cl65 -t plus4 -C whatchawant.cfg -m build/whatchawant.map -Ln build/whatchawant.lbl \
    -o build/whatchawant.prg build/whatchawant.o build/music.o
echo "build/whatchawant.prg: $(stat -c%s build/whatchawant.prg) bytes"
if [ "$1" = --wav ]; then
    python3 tools/mkmusic.py --wav build/music.wav ${WAV_SECONDS:-60}
fi
