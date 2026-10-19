#!/bin/sh
# Build trainschedule: build/trainschedule.prg, and the disk it runs from,
# build/trainschedule.d64. On the disk: the boot program first (boot.s, with
# the fast loader, drive.s and fastload.s), "trainschedule"; the game it
# loads, "game"; the title picture and the maps as files of their own:
#   title.b, title.m   the title picture (tools/mkpicture.py), packed by
#                      exomizer ("raw": the game unpacks them, unpack.s)
#   music              the title's music (tools/mkmusic.py, data/music.txt)
#   maps               the catalogue, map1, map2 ... the maps, each its
#                      song, track and timetable (tools/mklevel.py,
#                      data/*.txt, the songs from data/music.txt)
#   help               the overlay: the choice of a map and the page of
#                      help (front.s, help.s, tools/mkhelp.py, data/help.txt)
#   scores             the page of a map's best scores, and saving them
#                      (scores.s; the rest of its code is in "maps")
#   best               the best scores (scores.s), as the disk brings them:
#                      none - the fast loader saves into it
# The program is packed too, as Stardew Pond's: it unpacks itself.
set -e
cd "$(dirname "$0")"
B=${CC65_BIN:-$HOME/.local/share/cc65-vs64/bin}
EXOMIZER=${EXOMIZER:-$B/exomizer}
mkdir -p build/gen build/disk
# (a map's song where the game keeps it: game.inc's SONG_BUF)
SONG_BUF=$(sed -n 's/^SONG_BUF *= *\$\([0-9A-Fa-f]*\).*/\1/p' game.inc)
python3 tools/mklevel.py build/gen/data.s build/disk data/music.txt $SONG_BUF \
    data/riesa.txt data/yokohama.txt data/alessandria.txt data/paris.txt data/smithsfalls.txt data/copenhagen.txt
python3 tools/mkpicture.py data/start.png build/disk --up 2 --hires-from 7 --blank-from 16
python3 tools/mkfont.py build/gen/font.s
python3 tools/mkhelp.py data/help.txt build/gen/help.s
# the game: all assembly (cl65 only assembles it and links)
for f in trainschedule map route train front engine signs unpack help scores; do
    $B/cl65 -t plus4 -g -c -o build/$f.o $f.s
done
$B/cl65 -t plus4 -g -c -o build/data.o build/gen/data.s
$B/cl65 -t plus4 -g -c -o build/font.o build/gen/font.s
$B/cl65 -t plus4 -g -c -o build/helpdoc.o build/gen/help.s
$B/cl65 -t plus4 -C trainschedule.cfg -m build/trainschedule.map \
    -Ln build/trainschedule.lbl -o build/trainschedule.raw \
    build/trainschedule.o build/map.o build/route.o build/train.o \
    build/front.o build/engine.o build/signs.o build/unpack.o build/data.o \
    build/font.o build/help.o build/helpdoc.o build/scores.o
cp build/trainschedule.raw build/trainschedule-plain.prg
# the best scores' code (trainschedule.cfg: SCO, $E300) after the catalogue
# in its file, which the game loads to $E000; and their file as it comes:
# its load address, the cassette buffer (game.inc BEST), and 0s as long as
# the table - no scores, which the game takes for none at all
python3 - build/disk/MAPS build/scores.bin build/disk/maps.prg build/disk/best.prg <<'PY'
import re, sys
cat, code = open(sys.argv[1], "rb").read(), open(sys.argv[2], "rb").read()
if len(cat) - 2 > 0x300:
    sys.exit(f"the catalogue: {len(cat) - 2} bytes, over the $300 before the scores' code")
open(sys.argv[3], "wb").write(cat + bytes(0x302 - len(cat)) + code)
maps = int(re.search(r"^MAX_MAPS *= *(\d+)", open("game.inc").read(), re.M).group(1))
open(sys.argv[4], "wb").write(bytes([0x33, 0x03]) + bytes(2 + maps + 5 * 5 * maps))
PY
printf '\000\000' | cat - build/page.bin > build/disk/scores.prg
echo "scores: $(stat -c%s build/scores.bin) bytes, maps file $(stat -c%s build/disk/maps.prg), the page $(stat -c%s build/page.bin)"
# the overlay (trainschedule.cfg: OVL) packed, as the title's files, with a
# load address the game ignores; front.s unpacks it from $EC00, 3 KB
$EXOMIZER raw -q -o build/help.exo build/help.bin
printf '\000\000' | cat - build/help.exo > build/disk/help.prg
echo "help: $(stat -c%s build/help.bin) bytes, packed $(stat -c%s build/help.exo)"
[ "$(stat -c%s build/help.exo)" -le 3072 ] || { echo "help packed: over 3 KB" >&2; exit 1; }
# (it leaves the screen as it is, and the interrupts on: the title picture,
# which the boot program shows while it loads the game, in its two modes)
$EXOMIZER sfx sys -t 4 -q -n -Di_irq_enter=1 -Di_irq_during=1 -Di_irq_exit=1 \
    -o build/trainschedule.prg build/trainschedule.raw
echo "build/trainschedule.prg: $(stat -c%s build/trainschedule.raw) bytes, packed $(stat -c%s build/trainschedule.prg)"

# The boot program, with the fast loader's two halves, and where the packed
# game starts: the number its BASIC line SYSes to
printf '%s\n' 'MEMORY { RAM: start = $0000, size = $10000, file = %O; }' \
    'SEGMENTS { CODE: load = RAM, type = rw; }' > build/raw.cfg
for f in drive fastload; do
    $B/cl65 -t none -C build/raw.cfg -o build/$f.bin $f.s
done
# the title's song, a file of its own at $E800 (the maps' are in theirs)
python3 tools/mkmusic.py data/music.txt radetzky build/disk/music.prg --org E800
START=$(python3 -c 'import re, sys; print(int(re.search(rb"\x9e *([0-9]+)", open(sys.argv[1], "rb").read()[:40]).group(1)))' build/trainschedule.prg)
$B/cl65 -t none -g -C build/raw.cfg --asm-define GAMESTART=$START -Ln build/boot.lbl -o build/boot.prg boot.s
echo "boot: $(stat -c%s build/boot.prg) bytes, drive code $(stat -c%s build/drive.bin), game at $START"

# the title's files packed, each with a load address the game ignores
for f in TITLE.B TITLE.M; do
    $EXOMIZER raw -q -o build/disk/$f.exo build/disk/$f
    printf '\000\000' | cat - build/disk/$f.exo > build/disk/$(echo $f | tr 'A-Z.' 'a-z.').prg
done
echo "title: $(stat -c%s build/disk/title.b.prg) + $(stat -c%s build/disk/title.m.prg) bytes packed"

# The disk, its files a few sectors further apart than the DOS would put
# them, for the fast loader (tools/mkd64.py). The game further still: it
# loads with the title picture on, when the TED leaves the CPU less time.
INTERLEAVE=${INTERLEAVE:-15}
GAME_INTERLEAVE=${GAME_INTERLEAVE:-20}
disk() {        # disk <d64> <the game, packed>
    d64=$1
    set -- trainschedule=build/boot.prg \
           title.b=build/disk/title.b.prg title.m=build/disk/title.m.prg \
           music=build/disk/music.prg \
           game@$GAME_INTERLEAVE="$2" maps=build/disk/maps.prg \
           help@$GAME_INTERLEAVE=build/disk/help.prg
    for f in build/disk/MAP[0-9]*; do
        set -- "$@" "$(basename "$f" | tr 'A-Z' 'a-z')=$f"
    done
    set -- "$@" scores=build/disk/scores.prg best=build/disk/best.prg
    python3 tools/mkd64.py "$d64" trainschedule rs $INTERLEAVE "$@"
}
disk build/trainschedule.d64 build/trainschedule.prg

# The test build (tests/start.sh), if TEST_MAP is given: the same game with
# two of its bytes set (tools/patch.py) - test_map: a map's number, straight
# into it, or 255, straight to the choice of a map; unlocked: the maps open,
# a bit each - on a disk of its own, build/trainschedule-test.d64
if [ -n "$TEST_MAP" ]; then
    mkdir -p build/test
    python3 tools/patch.py build/trainschedule.raw build/trainschedule.lbl \
        build/test/game.raw "_test_map=$TEST_MAP" "_unlocked=${TEST_UNLOCKED:-1}"
    $EXOMIZER sfx sys -t 4 -q -n -Di_irq_enter=1 -Di_irq_during=1 -Di_irq_exit=1 \
        -o build/test/game.prg build/test/game.raw
    disk build/trainschedule-test.d64 build/test/game.prg
    echo "build/trainschedule-test.d64: test_map $TEST_MAP, unlocked ${TEST_UNLOCKED:-1}"
fi
