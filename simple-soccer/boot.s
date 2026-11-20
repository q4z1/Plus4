; boot.s - the disk's first program, "simple soccer": a loading screen -
; the name, a football turning, "LOADING" and its dots - while it loads the
; flags and the game, then the game
;
; As trainschedule's boot: if the drive is a 1541 (any of them), 1570 or
; 1571 - its DOS says so at $E5C5 - the fast loader's drive half goes into
; it (drive.s), the Plus/4's at $0200 (fastload.s, in resident.s: the ROM
; out from then on, the KERNAL's page 2 and 3 of no more use), and the
; files come through them; any other drive (a 1551, 1581, SD2IEC ...) loads
; the KERNAL's way. Either way it leaves what outlasts a match (resident.s:
; RES kept at RES_STORE for the game's start, K_CODE, K_VARS - the way back
; from a match to the disk). With the fast loader first the music (music.s, the
; file "music" to $E200): it plays from then on, through the title, which
; goes on with it - the ROM out for good, its interrupt through $FFFE, the
; ball and the dots turned on by it once a frame. (Not the KERNAL's way:
; its loading would be held up by the interrupt, 5542 a second, through
; the ROM's handler.) Then the flags for the title (tools/mkflags.py:
; "flags", packed - unpack.inc - to FLAGS, just below $E200, where the
; title finds them), the
; league the disk keeps (the file "league", to L_BLOCK under the ROM, if
; it is there and whole), then
; the game, packed (ZX0: unzx0.inc), loaded high - at ZX_AT, up to just
; past its end - and unpacked over itself and this program from $1001:
; what runs then is at $0400 and $F800 - the interrupt, the loading, the
; unpacking, the start - which neither the game's file nor the KERNAL's
; loading touch. The interrupt goes on while the game unpacks, till its
; own start shuts it off.
;
; The screen: text at $0800 (colours) / $0C00 (codes), below $8000, which
; the TED reads from the RAM even while the KERNAL loads with the ROM in;
; the characters a copy of the ROM's (capitals and graphics) at $D000, in
; the RAM, the ball's nine among them, rewritten from the pictures at
; SPIN (tools/mkspinner.py) every SPIN_T frames - multicolour, white with
; black pentagons ($FF16), the only cells with the colour's bit 3. The characters are copied
; to $E800, out of the flags' way: the title's screen later.
;
; From build.sh: GAMESTART, where the game starts, as its own BASIC line
; SYSes to; ZX_AT, where its packed file goes, and ZX_END, where it ends
; unpacked.

        .setcpu "6502"

        .include "game.inc"     ; (K_*, L_*: what outlasts a match)
        .include "bootmus.inc"  ; (the music's: build.sh)
        .include "flags.inc"    ; (FLAGS: tools/mkflags.py)
        .include "resident.inc" ; (resident.s's labels: build.sh)
        .include "logo.inc"     ; (the name's sizes: tools/mkdata.py)

SETLFS  = $FFBA
SETNAM  = $FFBD
OPEN    = $FFC0
CHKIN   = $FFC6
CHKOUT  = $FFC9
CHRIN   = $FFCF
CHROUT  = $FFD2
CLRCHN  = $FFCC
CLALL   = $FFE7
LOAD    = $FFD5
RESTOR  = $FF8A
READST  = $FFB7
FA      = $AE           ; the device last used: where the boot came from
VARTAB  = $2D           ; BASIC: the program's end
TED06   = $FF06
TED07   = $FF07
IRQFLAG = $FF09
IRQEN   = $FF0A
RCMP    = $FF0B
BMBASE  = $FF12
CHBASE  = $FF13
VMBASE  = $FF14
BG      = $FF15
COL1    = $FF16         ; multicolour %01: the ball's pentagons
BORDER  = $FF19
RASTER  = $FF1D
ROMON   = $FF3E
RAMON   = $FF3F
VBL     = 204           ; below the text
KIRQ    = $0314         ; the KERNAL's interrupt goes on through this
KIRQEND = $FCBE         ; and ends here, Y, X, A off the stack

DRIVE   = $0400         ; drive.s, in the drive
GAME    = $1001
L_LOAD  = $2400         ; the league loaded here first (past this program)
MATRIX  = $0800         ; colours; the codes at $0C00
CODES   = MATRIX + $400
ROMFONT = $D000         ; the ROM's capitals and graphics
CHARS   = $E800         ; the characters (the ROM's copied)
SPIN    = $EC00         ; the ball's pictures, 72 bytes each
SPIN_CODE = $70         ; its nine characters' first code (graphics the
                        ; text does not use)
SPIN_T  = 4             ; frames each picture shows
SPIN_ROW = 11
SPIN_COL = 18
DOTS    = MATRIX + 16 * 40 + 22     ; "LOADING"'s three dots' colours
LOGO_ROW = 1            ; the name as the title has it, where it has it
LOGO_COL = 7            ; (title.s LOGO_ROW, LOGO_COL; its characters from
                        ; LOGO_CODE on, graphics the text does not use)

WHITE   = $71
BALL    = $79           ; white, multicolour (the ball's cells)

        .org GAME - 2
        .word GAME
        .word eol, 10           ; 10 SYS4109
        .byte $9E, "4109", 0
eol:    .word 0

        ; $100D
        jsr RESTOR              ; the KERNAL's own vectors (a fast loader
                                ; left resident points LOAD elsewhere)
        lda #PAGE_BORDER
        sta BORDER
        lda #PAGE_BG
        sta BG
        lda TED06               ; the screen off while it is made
        and #$EF
        sta TED06
        ldx #0                  ; what runs from $0400 and $05EC
:       lda tail_load,x
        sta tail,x
        lda tail2_load,x
        sta tail2,x
        inx
        bne :-
        ldx #0                  ; the ROM's capitals and graphics into the
:       lda ROMFONT,x           ; RAM (writes go to the RAM under the
        sta CHARS,x             ; ROM), the ball's pictures after them
        lda ROMFONT + $100,x
        sta CHARS + $100,x
        lda ROMFONT + $200,x
        sta CHARS + $200,x
        lda ROMFONT + $300,x
        sta CHARS + $300,x
        lda spin_pics,x
        sta SPIN,x
        lda spin_pics + $100,x
        sta SPIN + $100,x
        lda spin_pics + $200,x
        sta SPIN + $200,x
        lda #' '                ; the screen: blank, the text white
        sta CODES,x
        sta CODES + $100,x
        sta CODES + $200,x
        sta CODES + $300,x
        lda #WHITE
        sta MATRIX,x
        sta MATRIX + $100,x
        sta MATRIX + $200,x
        sta MATRIX + $300,x
        inx
        bne :-
        .assert SPIN_FRAMES * 72 <= $300, error, "the ball's pictures: over $300"
        .assert LOGO_CODE + LOGO_N <= SPIN_CODE, error, "the name's characters: into the ball's"
        ldx #0                  ; the name: its characters (tools/mkdata.py,
:       lda logo_chars,x        ; the title's), its two rows
        sta CHARS + LOGO_CODE * 8,x
        lda logo_chars + LOGO_N * 4,x
        sta CHARS + LOGO_CODE * 8 + LOGO_N * 4,x
        inx
        cpx #LOGO_N * 4
        bne :-
        ldx #LOGO_W - 1
:       lda logo_codes,x
        sta CODES + LOGO_ROW * 40 + LOGO_COL,x
        lda logo_codes + LOGO_W,x
        sta CODES + (LOGO_ROW + 1) * 40 + LOGO_COL,x
        lda logo_cols,x
        sta MATRIX + LOGO_ROW * 40 + LOGO_COL,x
        lda logo_cols + LOGO_W,x
        sta MATRIX + (LOGO_ROW + 1) * 40 + LOGO_COL,x
        dex
        bpl :-
        sei                     ; the ball's first picture (from under the
        sta RAMON               ; ROM - no interrupt meanwhile: the
        jsr spin                ; KERNAL's would go through $FFFE in the
        sta ROMON               ; RAM, not set yet), its cells
        cli
        ldx #8
:       txa
        clc
        adc #SPIN_CODE
        ldy spin_cell,x
        sta CODES + SPIN_ROW * 40 + SPIN_COL,y
        lda #BALL
        sta MATRIX + SPIN_ROW * 40 + SPIN_COL,y
        dex
        bpl :-
        lda #<texts
        ldy #>texts
        jsr print
        lda TED07               ; text, 40 columns, 128 characters,
        and #$40                ; multicolour (only the ball's cells; PAL
        ora #$18                ; or NTSC kept)
        sta TED07
        lda #$00                ; its pentagons black (the screen still
        sta COL1                ; off: no snow)
        lda BMBASE              ; the characters from the RAM
        and #$FB
        sta BMBASE
        lda CHBASE
        and #$03
        ora #>CHARS
        sta CHBASE
        lda #>MATRIX
        sta VMBASE
        lda FA
        cmp #8
        bcs :+
        lda #8
:       sta dev

        lda #$1B                ; the screen on: text, 25 rows
        sta TED06
        jsr detect              ; the drive: a fast one? (the KERNAL's
                                ; interrupt still: ours after, as
                                ; trainschedule's - a 1551 loaded the
                                ; KERNAL's way crashed with ours here)
        bcs @slow
        jsr upload
        bcs @slow
        ldx #0                  ; the drive holds CLK when it runs (a
        ldy #0                  ; quarter of a second at most)
@alive: bit $01
        bvc @fast
        dex
        bne @alive
        dey
        bne @alive
        beq @slow               ; it did not start
@fast:  inc fast
@slow:  ldx #0                  ; what outlasts a match (resident.s): RES
:       lda resident_load,x     ; kept under the ROM (writes go to the
        sta RES_STORE,x         ; RAM) till the game starts, K_CODE where
        lda resident_load + $100,x  ; it stays
        sta RES_STORE + $100,x
        inx
        bne :-
        ldx #K_CODE_LEN
:       lda resident_load + $200 - 1,x
        sta K_CODE - 1,x
        dex
        bne :-
        lda #K_MAGIC_0          ; and what it is to know: where the boot
        sta K_MAGIC             ; came from, how it loaded
        sta K_STORED
        lda #K_MAGIC_1
        sta K_MAGIC + 1
        lda dev
        sta K_DEV
        lda fast
        sta K_FAST
        lda #K_TITLE
        sta K_REQ
        .assert K_TITLE = 0, error, "boot: K_HOME 0 too"
        sta K_HOME              ; (port 1 the home team's, till the title
                                ; sees the other used: home_stick)
        sei                     ; our interrupt: the ball, the dots - through
        lda #0                  ; $FFFE while the RAM is in, through the
        sta IRQEN               ; KERNAL while the ROM is
        lda IRQFLAG
        sta IRQFLAG
        lda #<irq_ram
        sta $FFFE
        lda #>irq_ram
        sta $FFFF
        lda #<irq_rom
        sta KIRQ
        lda #>irq_rom
        sta KIRQ+1
        lda #VBL
        sta RCMP
        lda #$02                ; the raster interrupt, line < 256
        sta IRQEN
        lda fast                ; the fast loader: the ROM out from here
        beq :++                 ; (the interrupt through $FFFE), and its
        sta RAMON               ; Plus/4 half at RES (the KERNAL's page 2
        inc music               ; and 3: of no more use)
        ldx #0
:       lda RES_STORE,x
        sta RES,x
        lda RES_STORE + $100,x
        sta RES + $100,x
        inx
        bne :-
:       cli

        lda fast                ; the music, with the fast loader - it
        beq @flags              ; starts with the game's last MUSIC_LEFT
        lda #<BM_START          ; blocks (zx_hook): it takes the most of
        sta l_addr              ; the machine, the loading would go at
        lda #>BM_START          ; half the speed with it (Luca's: it
        sta l_addr+1            ; brings the player back, and goes on into
        lda #<name_music        ; the title)
        ldy #>name_music
        jsr load

@flags: lda #<UNP_AT            ; the flags: the title's (build/gen/flags.inc),
        sta l_addr              ; packed (unpack.inc) - unpacked to FLAGS,
        lda #>UNP_AT            ; the RAM in meanwhile (the KERNAL's way:
        sta l_addr+1            ; the interrupt through $FFFE then, the
        lda #<name_flags        ; boot's own)
        ldy #>name_flags
        jsr load
        sta RAMON
        lda #<FLAGS
        sta z:unp_dst
        lda #>FLAGS
        sta z:unp_dst+1
        lda #<UNP_AT
        ldx #>UNP_AT
        jsr unpack
        lda music
        bne :+
        sta ROMON
:
        lda #<L_LOAD            ; the league as the disk keeps it - if it
        sta l_addr              ; does, and as it was saved (its bytes add
        lda #>L_LOAD            ; up to 0): else none. Loaded low, where
        sta l_addr+1            ; the game goes next (the KERNAL's LOAD
        inc l_opt               ; under the ROM left it empty from a
        lda #<name_league       ; 1551), then under the ROM
        ldy #>name_league
        jsr load
        dec l_opt               ; (C kept)
        sei
        sta RAMON
        ldx #L_LEN - 1
        lda #0
        bcs @none
:       clc
        adc L_LOAD,x
        pha
        lda L_LOAD,x
        sta L_BLOCK,x
        pla
        dex
        bpl :-
        tax
        bne @none
        lda L_ON
        cmp #1
        beq :+
@none:  lda #0
        sta L_ON
:       ldx music
        bne :+
        sta ROMON
:       cli
        jmp game                ; the game, over this

name_flags: .byte "FLAGS", 0
name_music: .byte "MUSIC", 0
name_league: .byte "LEAGUE", 0

; the ball's nine cells, a row of three at a time
spin_cell:  .byte 0, 1, 2, 40, 41, 42, 80, 81, 82

; Text in the ROM's characters: a list of lines - the cell to start at (a
; word, 0 ends the list), its colour, screen codes, 0 to end the line.
TP      = $DA           ; zero page (free while the KERNAL works)
MP      = $DC
print:  sta TP
        sty TP+1
@line:  jsr @next
        sta MP
        jsr @next
        sta MP+1
        ora MP
        bne :+
        rts
:       jsr @next
        sta @col + 1
        ldy #0
@char:  sty @y + 1
        jsr @next
        beq @line
@y:     ldy #0
        sta (MP),y              ; (the codes at MP; the colours $400 below)
        lda MP+1
        pha
        sec
        sbc #>(CODES - MATRIX)
        sta MP+1
@col:   lda #0
        sta (MP),y
        pla
        sta MP+1
        iny
        bne @char
@next:  ldy #0                  ; the next byte of the text, Z for 0
        lda (TP),y
        inc TP
        bne :+
        inc TP+1
:       tax
        rts

.repeat 26, I                   ; capitals as the ROM's first set has them
        .charmap $41 + I, $01 + I
.endrepeat
texts:
        .word CODES + 16 * 40 + 15
        .byte WHITE, "LOADING...", 0
        .word 0
.repeat 26, I
        .charmap $41 + I, $41 + I
.endrepeat

        .include "spinner.inc"          ; (tools/mkspinner.py)
        .include "logodata.inc"         ; (tools/mkdata.py)

        .include "unpack.inc"   ; (the flags: packed)

; the game's unpacking (unzx0.inc), run at ZX_RUN once the game is loaded:
; under the ROM (the RAM in while it runs), below RES_STORE, past the
; music's wave pages - the game's variables later, cleared by its start
ZX_RUN  = $F800
ZX_ZP   = $D8
zx_load:
        .org ZX_RUN
zx_run:
        .include "unzx0.inc"

; zx_whole: (the KERNAL's way) the game unpacked, all of it loaded
zx_whole:
        lda #<ZX_AT
        sta zx_src
        lda #>ZX_AT
        sta zx_src+1
        lda #<GAME
        sta zx_dst
        lda #>GAME
        sta zx_dst+1
        jmp unzx0

zx_run_end:
        .assert zx_run_end <= RES_STORE, error, "boot.s: unzx0 into RES_STORE"
        .assert zx_run_end - zx_run <= $200, error, "boot.s: unzx0 over two pages"
        .org zx_load + (zx_run_end - zx_run)

; the loading and unpacking at once (the fast loader's way: the KERNAL is
; out, $0700 free) - run at ST_RUN, copied there by game
ST_RUN  = $0700
st_load:
        .org ST_RUN
st_run:
; zx_stream: (the fast loader) the game loaded and unpacked at once: the
; unpacking goes on while the drive reads the next sector. The two take
; turns, each on its own stack: the loader calls zx_hook after each block
; (fastload.s hook), which goes on with the unpacking (on its stack,
; from ZX_STACK down) if enough is in; the unpacking calls zx_more when it
; is not, which goes back to the loader. Unpacked to the end, it goes back
; through zx_finish. Again from the start, the border red, should the
; loading fail.
ZX_STACK = $01A0                ; (the stack's page: the flags' unpacking
                                ; table, done with)
zx_stream:
        lda #<zx_hook
        sta RES_HOOK
        lda #>zx_hook
        sta RES_HOOK+1
        lda #ZX_TOMUSIC         ; (once: again after a failure, the
        sta zx_tomusic          ; music not started twice)
zx_again:
        lda #<ZX_AT
        sta zx_src
        lda #>ZX_AT
        sta zx_src+1
        sta zx_endhi            ; (nothing in yet)
        sec
        sbc #2
        sta zx_lim
        lda #<GAME
        sta zx_dst
        lda #>GAME
        sta zx_dst+1
        lda #>(zx_finish - 1)   ; the unpacking's stack: zx_go to start
        sta ZX_STACK            ; with, zx_finish to end with
        lda #<(zx_finish - 1)
        sta ZX_STACK - 1
        lda #>(zx_go - 1)
        sta ZX_STACK - 2
        lda #<(zx_go - 1)
        sta ZX_STACK - 3
        lda #<(ZX_STACK - 4)
        sta zx_sp
        lda #0
        sta zx_done
        lda #<zx_name
        sta RES_NM
        lda #>zx_name
        sta RES_NM+1
        lda #<ZX_AT
        sta RES_DST
        lda #>ZX_AT
        sta RES_DST+1
        jsr RES_LOAD
        bcs @red
        lda zx_done             ; (a last block of no bytes: no hook for
        bne :+                  ; it)
        jsr zx_eof
        lda zx_done
        beq @red
:       lda #<RES_BUSY          ; (the hook as it was)
        sta RES_HOOK
        lda #>RES_BUSY
        sta RES_HOOK+1
        lda #PAGE_BORDER
        sta BORDER
        rts
@red:   lda #$32
        sta BORDER
        jmp zx_again

; zx_hook: (the loader's, a block in) how far the packed bytes are: on with
; the unpacking if it can go on
zx_hook:
        dec zx_tomusic          ; the music from here on
        bne :+
        lda #<tick              ; (the ball and the dots each frame from
        ldy #>tick              ; it)
        jsr BM_START
:       ldx RES_DST+1           ; (their end's page)
        lda RES_LAST            ; (0: the last block)
        bne :+
zx_eof: ldx #$FF                ; (all in)
:       stx zx_endhi
        dex
        dex
        stx zx_lim
        lda zx_done
        bne @back
        lda zx_src+1
        cmp zx_lim
        bcs @back
        tsx                     ; to the unpacking
        stx ld_sp
        ldx zx_sp
        txs
@back:  rts

; zx_more: (the unpacking's) back to the loader, for more
zx_more:
        tsx
        stx zx_sp
        ldx ld_sp
        txs
        rts

; zx_finish: (unpacked to the end) back to the loader, for good
zx_finish:
        inc zx_done
        ldx ld_sp
        txs
        rts

zx_name: .byte "GAME", 0
zx_sp:  .byte 0                 ; the unpacking's stack, while it waits
ld_sp:  .byte 0                 ; the loader's, while the unpacking runs
zx_done: .byte 0
zx_tomusic: .byte 0             ; blocks till the music starts
                                ; (MUSIC_LEFT: the game's blocks with the
                                ; music, from build.sh)
.if ZX_BLOCKS > MUSIC_LEFT
ZX_TOMUSIC = ZX_BLOCKS - MUSIC_LEFT
.else
ZX_TOMUSIC = 1
.endif
st_run_end:
        .assert st_run_end <= $07D8, error, "boot.s: zx_stream into $07D8"
        .org st_load + (st_run_end - st_run)

; ---- which drive -----------------------------------------------------------

; C clear for a drive the loader knows: "54" at $E5C5 in its ROM (the
; 1541's "CBM DOS V2.6 1541"; also the 1541-II's and 1541C's) or "57" (the
; 1570's and 1571's "V3.0 157x"). Leaves channel 15 open.
detect: lda #15
        ldx dev
        ldy #15
        jsr SETLFS
        lda #0
        jsr SETNAM
        jsr OPEN
        bcs @no
        ldx #15
        jsr CHKOUT
        bcs @no
        ldx #0
:       lda mr,x
        jsr CHROUT
        inx
        cpx #6
        bne :-
        jsr CLRCHN
        ldx #15
        jsr CHKIN
        bcs @no
        jsr CHRIN
        sta rom
        jsr CHRIN
        sta rom+1
        jsr CLRCHN
        jsr READST
        and #$83                ; no device, time out
        bne @no
        lda rom
        cmp #'5'
        bne @no
        lda rom+1
        cmp #'4'
        beq @yes
        cmp #'7'
        bne @no
@yes:   clc
        rts
@no:    jsr CLRCHN
        sec
        rts

mr:     .byte "M-R", $C5, $E5, 2
rom:    .byte 0, 0

; ---- the drive's half --------------------------------------------------

; drive.s by M-W, 32 bytes a time, and started by M-E. Channel 15 is then
; forgotten (CLALL), not closed: closing would talk to the drive, which is
; no longer listening.
upload: lda #<drive_load
        sta @src+1
        lda #>drive_load
        sta @src+2
        lda #<DRIVE
        sta mw+3
        lda #>DRIVE
        sta mw+4
@chunk: ldx #15
        jsr CHKOUT
        bcs @no
        ldx #0
:       lda mw,x
        jsr CHROUT
        inx
        cpx #6
        bne :-
        ldy #0
@src:   lda $FFFF,y
        jsr CHROUT
        iny
        cpy #32
        bne @src
        jsr CLRCHN
        lda @src+1
        clc
        adc #32
        sta @src+1
        bcc :+
        inc @src+2
:       lda mw+3
        clc
        adc #32
        sta mw+3
        bcc :+
        inc mw+4
:       lda mw+3                ; till all of it is in
        cmp #<(DRIVE + drive_end - drive_load)
        lda mw+4
        sbc #>(DRIVE + drive_end - drive_load)
        bcc @chunk
        ldx #15
        jsr CHKOUT
        bcs @no
        ldx #0
:       lda me,x
        jsr CHROUT
        inx
        cpx #5
        bne :-
        jsr CLRCHN
        jsr CLALL
        clc
        rts
@no:    jsr CLRCHN
        sec
        rts

mw:     .byte "M-W", 0, 0, 32
me:     .byte "M-E", <DRIVE, >DRIVE

drive_load:
        .incbin "build/drive.bin"
drive_end:
resident_load:
        .incbin "build/resident.bin"    ; (RES's two pages, then K_CODE's)
K_CODE_LEN = K_END - K_CODE

; ---- the last steps, at $0400 and $05EC ---------------------------------
;
; (the KERNAL keeps its own at $04FC-$05EB, and needs $07D8-$07E7: it
; wrote into a longer tail here while it loaded from a 1551)

tail_load:
        .org $0400
tail:

; The interrupt, every frame: the dots, and every SPIN_T frames the ball's
; next picture; through $FFFE (the RAM in) or the KERNAL's (the ROM in:
; the RAM in for it a moment, the pictures are under the ROM)
irq_ram:
        pha
        txa
        pha
        tya
        pha
        jsr irq_tick
        pla
        tay
        pla
        tax
        pla
        rti
irq_rom:
        sta RAMON
        jsr irq_tick
        sta ROMON
        jmp KIRQEND

irq_tick:
        lda IRQFLAG
        sta IRQFLAG
tick:   inc frame               ; (the music calls this once a frame)
        lda frame               ; the dots after "LOADING" (dots.inc), a
        and #3                  ; step every 4 frames
        bne :+
        jsr dots
:       dec spin_t
        beq :+
        rts
:       lda #SPIN_T
        sta spin_t
        ldx spin_k              ; the ball's next picture
        inx
        cpx #SPIN_FRAMES
        bne :+
        ldx #0
:       stx spin_k
spin:   ldx spin_k              ; picture spin_k into the nine characters
        lda spin_lo,x
        sta @from + 1
        lda spin_hi,x
        sta @from + 2
        ldx #71
@from:  lda SPIN,x
        sta CHARS + SPIN_CODE * 8,x
        dex
        bpl @from
        rts

spin_lo:
        .repeat SPIN_FRAMES, I
        .byte <(SPIN + I * 72)
        .endrepeat
spin_hi:
        .repeat SPIN_FRAMES, I
        .byte >(SPIN + I * 72)
        .endrepeat
DOT_P       = dot_p             ; (dots.inc's variables: tail2's)
DOT_C       = dot_c
DOT_H       = dot_h
        .include "dots.inc"

tail_end:
        .assert tail_end <= $04FC, error, "the boot's tail: into the KERNAL's $04FC"

tail2_load = tail_load + (tail_end - tail)
        .org $05EC
tail2:

; the game over this program, the screen on meanwhile; then its start
; (packed by ZX0: to ZX_AT, under its end, and unpacked to GAME by unzx0 -
; copied to ZX_RUN first: this program's main part is the first the
; unpacking writes over. With the fast loader as it comes, zx_stream; else
; once it is in, the RAM in: ZX_RUN is under the ROM)
game:   ldx #0                  ; (two pages: whatever is past it too)
:       lda zx_load,x
        sta zx_run,x
        lda zx_load + $100,x
        sta zx_run + $100,x
        inx
        bne :-
        lda fast
        beq @kernal
        ldx #st_run_end - st_run
:       lda st_load - 1,x
        sta st_run - 1,x
        dex
        bne :-
        jsr zx_stream
        jmp @go
@kernal:
        lda #<ZX_AT
        sta l_addr
        lda #>ZX_AT
        sta l_addr+1
        lda #<gname
        ldy #>gname
        jsr load
        sta RAMON
        jsr zx_whole
@go:
        lda #<ZX_END            ; where it ends
        sta VARTAB
        lda #>ZX_END
        sta VARTAB+1
        jmp GAMESTART           ; (the interrupt on: the game shuts it off)

; The file named at A/Y (0-terminated) to l_addr, by the fast loader if the
; drive runs it, else by the KERNAL; again, the border red, till it works.
; Its end in A/X.
load:   sta l_name
        sty l_name+1
@again: lda fast
        beq @kernal
        lda l_name              ; (the ROM is out: music)
        sta RES_NM
        lda l_name+1
        sta RES_NM+1
        lda l_addr
        sta RES_DST
        lda l_addr+1
        sta RES_DST+1
        jsr RES_LOAD
        bcc @done
        bcs @red
@kernal:
        lda l_name              ; its length
        sta @len+1
        lda l_name+1
        sta @len+2
        ldy #$FF
:       iny
@len:   lda $FFFF,y
        bne :-
        tya
        ldx l_name
        ldy l_name+1
        jsr SETNAM
        lda #1
        ldx dev
        ldy #0
        jsr SETLFS
        lda #0
        ldx l_addr
        ldy l_addr+1
        jsr LOAD
        bcs @red
        txa
        pha
        tya
        tax
        pla
@done:  pha
        lda #PAGE_BORDER
        sta BORDER
        pla
        rts
@red:   lda l_opt               ; (a file that may not be there: C set)
        beq :+
        rts
:       lda #$32                ; no disk, or it failed
        sta BORDER
        jmp @again

gname:  .byte "GAME", 0
fast:   .byte 0                 ; 1: the drive runs the fast loader
music:  .byte 0                 ; 1: the ROM is out (the fast loader)
l_opt:  .byte 0                 ; 1: the file may not be there
dev:    .byte 0
l_name: .word 0
l_addr: .word 0
frame:  .byte 0
spin_t: .byte SPIN_T
spin_k: .byte 0
dot_p:  .byte 0
dot_c:  .byte 0
dot_h:  .byte 0
tail2_end:
        .assert tail2_end <= $06EC, error, "the boot's second tail: over a page"

        .assert tail2_load + (tail2_end - tail2) <= L_LOAD, error, "boot.s: into L_LOAD"
        .assert tail2_load + (tail2_end - tail2) <= ZX_AT, error, "boot.s: the packed game over it (zx_load)"
