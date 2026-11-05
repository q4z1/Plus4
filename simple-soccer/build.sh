#!/bin/sh
# Build Simple Soccer: the disk it runs from, build/simple-soccer.d64, and
# the game alone, build/simple-soccer.prg (the tests start that: the title
# without its flags). The data first (tools/mkdata.py, mkmusic.py,
# mkflags.py, mkspinner.py: build/gen/, build/disk/), then the assembly
# (cl65 only assembles it and links), then the disk. On it:
#   simple soccer   the boot (boot.s): the loading screen, the fast loader
#                   (drive.s, fastload.s, as trainschedule's), the rest
#   music           the loading screen's music (music.s with BOOT,
#                   bootmus.cfg), which the title goes on with
#   flags           the title's flags (tools/mkflags.py, data/flags.txt)
#   game            the game, packed by exomizer: it unpacks itself
set -e
cd "$(dirname "$0")"
B=${CC65_BIN:-$HOME/.local/share/cc65-vs64/bin}
mkdir -p build/gen
# PACE=2: a picture every second frame instead of every third (game.inc)
DEFS=${PACE:+--asm-define PACE=$PACE}
python3 tools/mkdata.py
python3 tools/mkmusic.py
python3 tools/mkflags.py
python3 tools/mkspinner.py
# the loading screen's music first: the game's title takes its song over,
# from where build/gen/bootmus.inc says its voices are
mkdir -p build/disk
$B/cl65 -t none -g --asm-include-dir build/gen --asm-define BOOT=1 -c -o build/bootmus.o music.s
$B/cl65 -t none -C bootmus.cfg -Ln build/bootmus.lbl -o build/disk/music.prg build/bootmus.o
python3 - build/bootmus.lbl build/gen/bootmus.inc <<'PY'
import re, sys
lbl = {m.group(2): int(m.group(1), 16)
       for m in re.finditer(r"^al ([0-9A-F]+) \.(\w+)$", open(sys.argv[1]).read(), re.M)}
names = [('BM_START', 'bm_start'), ('BM_HOOK', 'bm_hook'), ('BM_SYNTH', 'synth'),
         ('BM_STATE', 'v_ptl'), ('BM_DATA', 'm_data'),
         ('BM_PH1', 's_ph1'), ('BM_PH2', 's_ph2'), ('BM_PH3', 's_ph3')]
with open(sys.argv[2], 'w') as f:
    f.write("; the loading screen's music (build.sh, from build/bootmus.lbl)\n")
    for n, l in names:
        f.write('%-11s = $%04X\n' % (n, lbl[l]))
PY
# what outlasts a match (resident.s: the fast loader's Plus/4 half, the
# KERNAL's way back) - its labels for the boot and the game
printf '%s\n' 'MEMORY { RAM: start = $0000, size = $10000, file = %O; }' \
    'SEGMENTS { CODE: load = RAM, type = rw; }' > build/raw.cfg
$B/cl65 -t none -g -C build/raw.cfg -Ln build/resident.lbl -o build/resident.bin resident.s
python3 - build/resident.lbl build/gen/resident.inc <<'PY'
import re, sys
lbl = {m.group(2): int(m.group(1), 16)
       for m in re.finditer(r"^al ([0-9A-F]+) \.(\w+)$", open(sys.argv[1]).read(), re.M)}
names = [('RES_LOAD', 'load', 0), ('RES_NM', 'nm', 1), ('RES_DST', 'dst', 1),
         ('K_GO', 'k_go', 0), ('K_END', 'k_end', 0)]
with open(sys.argv[2], 'w') as f:
    f.write("; resident.s's labels (build.sh, from build/resident.lbl)\n")
    for n, l, add in names:
        f.write('%-11s = $%04X\n' % (n, lbl[l] + add))
PY
for f in simple-soccer engine play sound title music cup; do
    $B/cl65 -t plus4 -g --asm-include-dir build/gen $DEFS -c -o build/$f.o $f.s
done
$B/cl65 -t plus4 -g -c -o build/data.o build/gen/data.s
mkdir -p build/disk
$B/cl65 -t plus4 -C simple-soccer.cfg -m build/simple-soccer.map -Ln build/simple-soccer.lbl \
    -o build/simple-soccer.prg build/simple-soccer.o build/engine.o build/play.o build/sound.o build/title.o build/music.o build/cup.o build/data.o
echo "build/simple-soccer.prg: $(stat -c%s build/simple-soccer.prg) bytes"
# the title and the music's interrupt, loaded after it, under the flags the
# boot has put at FLAGS (tools/mkflags.py: build/gen/flags.inc)
python3 - build/simple-soccer.map build/gen/flags.inc <<'PY'
import re, sys
m = open(sys.argv[1]).read()
end = int(re.search(r"^TITLE\s+\S+\s+(\S+)", m, re.M).group(1), 16)
synth = int(re.search(r"^SYNTH\s+\S+\s+\S+\s+(\S+)", m, re.M).group(1), 16)
flags = int(re.search(r"^FLAGS\s+= \$(\S+)", open(sys.argv[2]).read(), re.M).group(1), 16)
if end + 1 + synth > flags:
    sys.exit("the title runs into the flags at $%04X: up to $%04X" % (flags, end + synth))
print("title: up to $%04X, the flags from $%04X" % (end + synth, flags))
PY
# the title again, as a file of its own: cup.s loads it after a match (the
# match's pictures are over it); and the league as the disk keeps it, none
# yet (game.inc L_BLOCK: L_LEN bytes - their sum 0, L_ON 0)
python3 - build/simple-soccer.prg build/simple-soccer.map build/disk/title.prg build/disk/league.prg <<'PY'
import re, sys
prg = open(sys.argv[1], 'rb').read()
m = open(sys.argv[2]).read()
end = int(re.search(r"^TITLE\s+\S+\s+(\S+)", m, re.M).group(1), 16)
synth = int(re.search(r"^SYNTH\s+\S+\s+\S+\s+(\S+)", m, re.M).group(1), 16)
start = 0xC000
body = prg[2 + start - 0x1001:]
assert len(body) == end + 1 + synth - start, (len(body), end, synth)
open(sys.argv[3], 'wb').write(bytes([0x00, 0xC0]) + body)
L_LEN = 42                                  # game.inc (cup.s asserts it)
open(sys.argv[4], 'wb').write(bytes([0x00, 0x06]) + bytes(L_LEN))
print("title: %d bytes, cup: the league's page" % len(body))
PY

# The game packed (it leaves the screen and the interrupt as they are: the
# boot's loading screen goes on while it unpacks), the loader's halves, the
# boot - with where the packed game starts, the number its BASIC line SYSes
# to - and the disk, its files a few sectors further apart than the DOS
# would put them, for the fast loader (tools/mkd64.py): the music 20 (as
# fast as the loader goes), the flags and the game, loaded while the music
# plays, 36 - over a turn and a half of the disk for each sector (measured
# with tests/loadtime.py; the ROM out at the end, so its interrupt goes on)
EXOMIZER=${EXOMIZER:-$B/exomizer}
$EXOMIZER sfx sys -t 4 -q -n -Di_irq_enter=1 -Di_irq_during=1 -Di_irq_exit=1 \
    -Di_ram_exit=1 \
    -o build/disk/game.prg build/simple-soccer.prg
$B/cl65 -t none -C build/raw.cfg -o build/drive.bin drive.s
START=$(python3 -c 'import re, sys; print(int(re.search(rb"\x9e *([0-9]+)", open(sys.argv[1], "rb").read()[:40]).group(1)))' build/disk/game.prg)
$B/cl65 -t none -g -C build/raw.cfg --asm-include-dir build/gen --asm-define GAMESTART=$START \
    -Ln build/boot.lbl -o build/disk/boot.prg boot.s
python3 tools/mkd64.py build/simple-soccer.d64 "simple soccer" ss ${INTERLEAVE:-15} \
    "simple soccer=build/disk/boot.prg" music@${MUSIC_INTERLEAVE:-20}=build/disk/music.prg \
    flags@${GAME_INTERLEAVE:-36}=build/disk/flags.prg game@${GAME_INTERLEAVE:-36}=build/disk/game.prg \
    cup@${MUSIC_INTERLEAVE:-20}=build/disk/cup.prg title@${MUSIC_INTERLEAVE:-20}=build/disk/title.prg \
    league@${MUSIC_INTERLEAVE:-20}=build/disk/league.prg
echo "build/simple-soccer.d64: boot $(stat -c%s build/disk/boot.prg), game packed $(stat -c%s build/disk/game.prg) bytes"

