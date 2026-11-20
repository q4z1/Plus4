# ZX0

Einar Saukas' optimal compressor ZX0, version 2.2, as it is
(https://github.com/einar-saukas/ZX0, commit ecde3a2, `src/` without the
decompressor; BSD 3-clause licence: `LICENSE`).

`build.sh` compiles it to `build/zx0` and packs the game with it; the boot
unpacks it with `unzx0.inc`, a 6502 decompressor written for this game.
Packing the game takes over a minute, so `build.sh` keeps the result
(`build/pack/game.zx0`) and packs again only when the game has changed.
