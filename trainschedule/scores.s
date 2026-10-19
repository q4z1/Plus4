; scores.s - the best scores: five a map, a name of three letters to each,
; kept on the disk in the file "best"
;
; The table is in the cassette buffer (game.inc: BEST), from the first
; choice of a map on. This code is not in the program: most of it comes in
; the catalogue's file, "maps", $300 into it (build.sh) - at $E300, outside
; a level (trainschedule.cfg: SCO). The catalogue is loaded before every
; choice of a map, and after a map played to its end with a score among
; its best five, for the page of them (sc_page; front.s, best_after). The
; page's own code, and saving, is a file of its own, "scores", loaded to
; $C000 for it (SCP).
;
;   sc_init   the table off the disk, the first time; the maps it has open
;             open in the game too
;   sc_page   the page after a map: its best five, the new score among
;             them, its name given by the stick - and the table saved
;   sc_stars  the choice of a map: a map's most stars in its row
;   sc_best   and below it, its best score and whose it is
;
; Saving: with the fast loader through it, into the file the disk came
; with (tools/mkd64.py makes it as long as the table), read back after and
; compared - as Stardew Pond saves. The drive's half of it is drive.s; the
; Plus/4's is here, as the loader's resident half (fastload.s) has no room
; for it. Else the KERNAL: the old file scratched, the new one saved, the
; drive's status read - by code copied to $0400 for it (KSAVE), as the ROM
; is in meanwhile, and the routes kept there are no more.

        .include "game.inc"
        .macpack longbranch

        .export sc_init, sc_page, sc_stars, sc_best

        .import load, kload, kernal_07d8, dev, fl_on, cur_map, ld_addr, ld_len
        .importzp ld_name
        .import _unlocked, _score, _perfect, _lv_name
        .import _eng_hits, _eng_choice, _eng_blank, _eng_unblank, _eng_irqon
        .import _tk_on, _tk_start, _keys, _frames
        .import __KSAVE_LOAD__, __KSAVE_RUN__, __KSAVE_SIZE__

FL_LOAD = $FA00                 ; the fast loader (fastload.s)
FL_NAME = $FA07
FL_ADDR = $FA09
KERNAL_LOAD_RAM = $07D8         ; what the KERNAL needs (front.s)
CHECK   = $0500                 ; a save read back: the routes' place
PAGE    = $C000                 ; the page's code (trainschedule.cfg: SCP)
SCR     = $F400                 ; the choice's screen (engine.s): its
COLR    = $F000                 ; characters, its colours

; the KERNAL's
SETLFS  = $FFBA
SETNAM  = $FFBD
OPEN    = $FFC0
CLOSE   = $FFC3
CHKIN   = $FFC6
CLRCHN  = $FFCC
CHRIN   = $FFCF
SAVE    = $FFD8

; the page's columns: the rank, the name, the score (5 wide), the stars
PC_RANK = 10
PC_NAME = 14
PC_SCORE = 19
PC_STARS = 26
LIST_ROW = 6                    ; the first's row, the next two below
COL_STARS_CH = COL_LOCK         ; stars in the choice's colours: gold

        .segment "TOPBSS"       ; (kept: the code comes and goes)
sc_ok:      .res 1              ; 1: the table is here
sc_name:    .res 3              ; the name given last

; screen codes for the text
.repeat 26, I
        .charmap $41 + I, $01 + I
.endrepeat

        .segment "SCORES"

; ---- the table ---------------------------------------------------------------

; sc_init: the table off the disk, if it is not here yet - all of it 0
; (no scores, no stars) if the disk has none, or not as it was saved
sc_init:
        lda sc_ok
        bne @rts
        inc sc_ok
        lda #<BEST
        ldx #>BEST
        jsr get
        bcs @none
        jsr sum
        clc
        adc BEST
        bne @none
        lda BEST_OPEN           ; (the first map is always open)
        lsr a
        bcc @none
        lda BEST_OPEN
        ora _unlocked
        sta _unlocked
@rts:   rts
@none:  ldx #BEST_LEN
        lda #0
:       sta BEST - 1,x
        dex
        bne :-
        rts

; sum: the table's bytes but the first added up (that one makes it 0)
sum:    ldx #BEST_LEN - 1
        lda #0
:       clc
        adc BEST,x
        dex
        bne :-
        rts

; get: the file "best" to A/X; C set if it is not there or the disk failed
get:    sta ld_addr
        stx ld_addr+1
        jsr names
        lda #<(BEST_NAME + 3)
        sta ld_name
        lda #>(BEST_NAME + 3)
        sta ld_name+1
        lda fl_on
        beq @kernal
        lda ld_name
        sta FL_NAME
        lda ld_name+1
        sta FL_NAME+1
        lda ld_addr
        sta FL_ADDR
        lda ld_addr+1
        sta FL_ADDR+1
        jmp FL_LOAD
@kernal:
        lda #4
        sta ld_len
        jsr k07d8
        jmp kload

; names: the file's name below the ROM, for the KERNAL - "s0:best", the
; command that scratches it, the name itself from 3 on
names:  ldx #7
:       lda n_best,x
        sta BEST_NAME,x
        dex
        bpl :-
        rts

; k07d8: what the KERNAL needs at $07D8 back (front.s keeps it)
k07d8:  ldx #15
:       lda kernal_07d8,x
        sta KERNAL_LOAD_RAM,x
        dex
        bpl :-
        rts

; ---- the choice of a map -------------------------------------------------------

; sc_stars: map X's most stars in the choice's row Y, at its end
sc_stars:
        lda BEST_STARS,x
        sta n
        lda #37
        jsr at
        lda #COL_STARS_CH
        sta col
        ldx #0
        beq star                ; (put_stars: n of 3)

; put_stars: n stars of 3, a space for each missing
put_stars:
        ldx #0
star:   lda #' '
        cpx n
        bcs :+
        lda #'*'
:       jsr put
        inx
        cpx #3
        bne star
        rts

; sc_best: row Y below the choice - map X's best score and its name; blank
; for none (and for X 128 on: the bulb chosen)
sc_best:
        stx n
        lda #COL_DIM
        jsr row
        ldx n
        bmi @rts
        lda BEST_LO,x
        ora BEST_HI,x
        beq @rts
        lda #<t_best
        ldx #>t_best
        jsr text
        ldx n
        lda #0                  ; as long as it is
        jsr score
        lda #<t_by
        ldx #>t_by
        jsr text
        ldx n
        jmp name
@rts:   rts

; sc_page: the page of the map's best five after it was played to its end
; (page): its code first, a file of its own, to $C000 - the level's
; characters were there, and the level is over
sc_page:
        ldx #6
:       lda n_page,x            ; (its name below the ROM, for the KERNAL)
        sta BEST_NAME,x
        dex
        bpl :-
        lda #<BEST_NAME
        sta ld_name
        lda #>BEST_NAME
        sta ld_name+1
        lda #<PAGE
        sta ld_addr
        lda #>PAGE
        sta ld_addr+1
        jsr load
        jmp page

; ---- the page (its own file: SCPAGE) ----------------------------------------------

        .segment "SCPAGE"

; page: the page of the map's best five, the score just made among them
; (if it is) - its name given, and the table saved
page:
        ldx cur_map
        dex
        stx m
        ldy #0                  ; its rank: before the first that has less
        txa
@rank:  tax
        lda BEST_LO,x
        cmp _score
        lda BEST_HI,x
        sbc _score+1
        bcc @in
        txa
        adc #MAX_MAPS - 1       ; (C set)
        iny
        cpy #5
        bne @rank
        jmp _eng_irqon          ; (not among them after all: "loading" on,
                                ; and the interrupt again, should the
                                ; KERNAL have loaded)
@in:    sty rank
        stx at_i
        lda m                   ; from the fifth up to it: each down a place
        clc
        adc #4 * MAX_MAPS
        tax
@down:  cpx at_i
        beq @new
        ldy #5                  ; score low, high, three letters
@each:  lda BEST_LO - MAX_MAPS,x
        sta BEST_LO,x
        txa
        clc
        adc #5 * MAX_MAPS
        tax
        dey
        bne @each
        txa
        sec
        sbc #26 * MAX_MAPS      ; back, and a rank up
        tax
        bcs @down
@new:   lda _score
        sta BEST_LO,x
        sta nv
        lda _score+1
        sta BEST_HI,x
        sta nv+1
        lda sc_name             ; the name given last, at first AAA
        bne :+
        lda #'A'
        sta sc_name
        sta sc_name+1
        sta sc_name+2
:       jsr stars               ; the map's most stars
        ldx m
        cmp BEST_STARS,x
        bcc :+
        sta BEST_STARS,x
:
        ; the page, on the second screen (the choice's) while "loading" is
        ; shown, then shown in one go
        jsr clear
        lda #COL_HUD
        sta col
        lda #13
        ldy #1
        jsr at
        lda #<t_head
        ldx #>t_head
        jsr text
        ldx #$FF                ; "BEST ON" and the map's name, centred
:       inx
        lda _lv_name,x
        bne :-
        stx n
        sec
        lda #32
        sbc n
        lsr a
        ldy #3
        jsr at
        lda #COL_LABEL
        sta col
        lda #<t_on
        ldx #>t_on
        jsr text
        lda #<_lv_name
        ldx #>_lv_name
        jsr text
        lda #0
        sta r
@row:   jsr list_row
        inc r
        lda r
        cmp #5
        bne @row
        ldy #20
        lda #COL_LABEL
        jsr row
        lda #<t_new
        ldx #>t_new
        jsr text
        ldy #21
        lda #COL_DIM
        jsr row
        lda #<t_keys
        ldx #>t_keys
        jsr text
        lda _tk_on
        bne :+
        jsr _tk_start
:       jsr _eng_choice
        lda #0
        sta pos
        sta held
        jsr _eng_hits           ; (none from before)

        ; the name: up and down a letter, held on and on; left and right
        ; the one before or after; fire takes it
@name:  jsr letters
        lda _frames
:       cmp _frames             ; the next picture
        beq :-
        jsr _eng_hits
        sta h
        and #K_FIRE
        jne @done
        lda _keys
        and #K_UP | K_DOWN | K_FIRE
        beq @free
        cmp #K_FIRE
        bcs @free               ; (fire held: a command, no letter)
        inc held                ; after 20 pictures, every 4th
        ldx held
        cpx #20
        bcc @keys
        ldx #16
        stx held
        ora h
        sta h
        bne @keys
@free:  lda #0
        sta held
@keys:  ldx pos
        lda h
        and #K_UP
        beq @no_up
        lda sc_name,x           ; A ... Z, space, A
        cmp #' '
        bne :+
        lda #0
:       clc
        adc #1
        cmp #27
        bcc @set
        lda #' '
        bne @set
@no_up: lda h
        and #K_DOWN
        beq @side
        lda sc_name,x           ; and back
        cmp #' '
        bne :+
        lda #27
:       sec
        sbc #1
        bne @set
        lda #' '
@set:   sta sc_name,x
        jmp @name
@side:  lda h
        and #K_LEFT
        beq :+
        txa
        beq :+
        dec pos
:       lda h
        and #K_RIGHT
        beq @again
        cpx #2
        bcs @again
        inc pos
@again: jmp @name

@done:  lda #3                  ; no letter blinking any more
        sta pos
        jsr letters
        ldy #20
        lda #COL_LABEL
        jsr row
        lda #<t_saving
        ldx #>t_saving
        jsr text
        ldy #21
        lda #COL_DIM
        jsr row
        jsr save
        lda #0
        rol a
        sta n                   ; 1: it failed
        ldy #20
        lda #COL_LABEL
        jsr row
        lda #<t_saved
        ldx #>t_saved
        ldy n
        beq :+
        lda #COL_LATE
        sta col
        lda #<t_failed
        ldx #>t_failed
:       jsr text
        ldy #21
        lda #COL_DIM
        jsr row
        lda #<t_go_on
        ldx #>t_go_on
        jsr text
        jsr _eng_hits
:       jsr _eng_hits
        and #K_FIRE
        beq :-
        rts

; letters: the new score's name, from sc_name to its row and the table -
; the one at pos blinking (pos 3: none)
letters:
        lda rank
        asl a
        adc #LIST_ROW
        tay
        lda #PC_NAME
        jsr at
        ldy #0
        ldx at_i
:       lda sc_name,y
        sta BEST_C1,x
        txa
        clc
        adc #5 * MAX_MAPS
        tax
        lda #COL_HUD
        cpy pos
        bne :+
        lda #COL_HUD | $80
:       sta col
        lda sc_name,y
        jsr put
        iny
        cpy #3
        bne :--
        rts

; list_row: rank r's row of the page - in white the new score's, the
; others grey; nothing but the rank where there is no score
list_row:
        lda r
        asl a
        adc #LIST_ROW
        sta ry
        tay
        lda #PC_RANK
        jsr at
        ldx #COL_DIM
        lda r
        cmp rank
        bne :+
        ldx #COL_HUD
:       stx col
        clc
        adc #'1'
        jsr put
        lda #'.'
        jsr put
        lda r                   ; its index: r * 7 + m
        asl a
        asl a
        asl a
        sec
        sbc r
        clc
        adc m
        sta n
        tax
        lda BEST_LO,x
        ora BEST_HI,x
        beq @rts
        lda #PC_NAME
        jsr at
        jsr name
        lda #PC_SCORE
        jsr at
        ldx n
        lda #1                  ; 5 wide
        jsr score
        ldx n
        lda BEST_LO,x
        sta nv
        lda BEST_HI,x
        sta nv+1
        jsr stars
        sta n
        ldy ry
        lda #PC_STARS
        jsr at
        lda #COL_STARS_CH
        sta col
        jmp put_stars
@rts:   rts

        .segment "SCORES"

; name: the three letters of score X (the table's index)
name:   lda BEST_C1,x
        jsr put
        lda BEST_C2,x
        jsr put
        lda BEST_C3,x
        jmp put

; score: score X (the table's index) in decimal, 5 wide (A 1) or as long
; as it is (A 0)
score:  sta pad
        lda BEST_LO,x
        sta nv
        lda BEST_HI,x
        sta nv+1
        ldx #0
        stx nz
@pow:   ldy #'0'                ; this power of 10's digit
@sub:   lda nv
        cmp pw_lo,x
        lda nv+1
        sbc pw_hi,x
        bcc @dig
        sta nv+1
        lda nv
        sbc pw_lo,x
        sta nv
        iny
        bne @sub
@dig:   cpy #'0'
        bne @put
        cpx #4
        beq @put
        lda nz
        bne @put
        lda pad                 ; a 0 in front: a space, or nothing
        beq @next
        ldy #' '
        bne @out
@put:   sty nz
@out:   tya
        jsr put
@next:  inx
        cpx #5
        bne @pow
        rts

        .segment "SCPAGE"

; stars: A = the stars score nv makes of _perfect - 3 at 100 per cent, 2 at
; 90, 1 at 70 (as level_end gives them: score * 100 >= per cent * perfect)
stars:  lda nv
        sta mx
        lda nv+1
        sta mx+1
        lda #100
        jsr mul
        ldx #2
:       lda mr,x
        sta s100,x
        dex
        bpl :-
        lda _perfect
        sta mx
        lda _perfect+1
        sta mx+1
        ldx #3
@try:   lda pc-1,x
        jsr mul
        lda s100
        cmp mr
        lda s100+1
        sbc mr+1
        lda s100+2
        sbc mr+2
        bcs @got
        dex
        bne @try
@got:   txa
        rts

; mul: mr (24 bits) = mx (16) * A. Keeps X.
mul:    sta mk
        lda #0
        sta mr
        sta mr+1
        sta mr+2
        ldy #8
@bit:   asl mr
        rol mr+1
        rol mr+2
        asl mk
        bcc :+
        lda mr
        clc
        adc mx
        sta mr
        lda mr+1
        adc mx+1
        sta mr+1
        bcc :+
        inc mr+2
:       dey
        bne @bit
        rts

; ---- the second screen ---------------------------------------------------------

; clear: the second screen empty, its last row the ticker's characters (as
; front.s's choice_screen)
clear:  ldx #0
:       lda #32
        sta SCR,x
        sta SCR + $100,x
        sta SCR + $200,x
        sta SCR + $300 - 24,x   ; (1000 bytes)
        lda #COL_BG
        sta COLR,x
        sta COLR + $100,x
        sta COLR + $200,x
        sta COLR + $300 - 24,x
        inx
        bne :-
        ldx #39
:       txa
        clc
        adc #TK_CODE
        sta SCR + 24 * 40,x
        lda #TK_COL
        sta COLR + 24 * 40,x
        dex
        bpl :-
        rts

        .segment "SCORES"

; row: row Y blank, in colour A from now on; put goes on in its column 4
row:    sta col
        lda #0
        jsr at
        ldx #40
:       lda #' '
        jsr put
        dex
        bne :-
        lda #4

; at: what put writes next goes to row Y, column A. Keeps X and Y.
at:     sta wr_c+1
        lda #0
        sta wr_c+2
        tya
        asl a
        asl a
        asl a                   ; row * 8
        sta tmp
        asl a
        rol wr_c+2
        asl a
        rol wr_c+2              ; row * 32
        clc
        adc tmp
        bcc :+
        inc wr_c+2
        clc
:       adc wr_c+1
        sta wr_c+1
        sta wr_k+1
        lda wr_c+2
        adc #>SCR
        sta wr_c+2
        eor #>(SCR ^ COLR)
        sta wr_k+2
        rts

; put: character A there, in colour col; on to the next column. Keeps X
; and Y.
put:
wr_c:   sta SCR
        lda col
wr_k:   sta COLR
        inc wr_c+1
        inc wr_k+1
        bne :+
        inc wr_c+2
        inc wr_k+2
:       rts

; text: the 0-terminated text at A/X, put's way. Keeps Y.
text:   sta tx+1
        stx tx+2
tx:     lda $FFFF
        beq @rts
        jsr put
        inc tx+1
        bne tx
        inc tx+2
        bne tx
@rts:   rts

; ---- saving ----------------------------------------------------------------------

        .segment "SCPAGE"

; save: the table to the disk, the maps open with it; C set if it failed
save:   lda _unlocked
        sta BEST_OPEN
        jsr sum
        eor #$FF
        clc
        adc #1
        sta BEST
        lda fl_on
        beq @kernal
        jsr fsave
        bcs @rts
        lda #<CHECK             ; read back: the drive checks no more than
        ldx #>CHECK             ; the sector
        jsr get
        bcs @rts
        ldx #BEST_LEN
:       lda CHECK - 1,x
        cmp BEST - 1,x
        bne @bad
        dex
        bne :-
        clc
        rts
@bad:   sec
@rts:   rts
@kernal:
        jsr _eng_blank          ; (the ROM comes in: no interrupt of ours)
        ldx #<__KSAVE_SIZE__
:       lda __KSAVE_LOAD__ - 1,x
        sta __KSAVE_RUN__ - 1,x
        dex
        bne :-
        jsr names
        jsr k07d8
        jsr ksave
        php
        jsr _eng_unblank
        plp
        rts

; the fast loader's saving, the Plus/4's half (Stardew Pond's fastload.s):
; the request - the name as in the directory, then 1, save - then for each
; sector the drive's count, and that many bytes; 0 when all is written
PORT    = $01
FREE    = $08                   ; both lines left high, tape motor off
CLKLO   = $0A                   ; CLK pulled
DATLO   = $09                   ; DATA pulled

fsave:  lda #<BEST
        sta @src+1
        lda #>BEST
        sta @src+2
        lda #DATLO              ; asking
        sta PORT
:       bit PORT                ; till the drive lets go of CLK
        bvc :-
        ldy #0
:       lda fs_name,y
        jsr fput
        iny
        cpy #17
        bne :-
        lda #FREE
        sta PORT
@block: jsr fbusy               ; how many the drive wants for a sector,
:       bit PORT                ; once it is ready
        bvc :-
        jsr fget
        beq @done               ; 0: all written
        cmp #$FF
        beq @fail
        sta fcount
:       bit PORT                ; till the drive lets go of DATA
        bpl :-
@src:   lda $FFFF
        jsr fput
        inc @src+1
        bne :+
        inc @src+2
:       dec fcount
        bne @src
        lda #FREE               ; DATA free for the drive's next count
        sta PORT
        jmp @block
@done:  jsr fbusy
        clc
        rts
@fail:  jsr fbusy
        sec
        rts

; a byte to the drive, lowest bit first (fastload.s's put). Keeps Y.
fput:   sta fbits
        lda #4
        sta fpairs
@bit:   lsr fbits
        lda #FREE >> 1
        rol
        sta PORT                ; the bit, CLK still high
        ora #CLKLO
        sta PORT                ; CLK low: the drive reads it
        jsr fwait
        lsr fbits
        lda #CLKLO >> 1
        rol
        sta PORT                ; the bit, CLK still low
        and #<~$02
        sta PORT                ; CLK high: the drive reads it
        jsr fwait
        dec fpairs
        bne @bit
        rts

fbusy:  bit PORT
        bvs fbusy
        rts

fwait:  ldx #10                 ; with jsr and rts: 61 cycles, 34 us
:       dex
        bne :-
        rts

; a byte from the drive, lowest bit first (fastload.s's get). Z set if 0.
fget:   ldy #9
:       dey
        bne :-
        ldx #4
@bit:   lda PORT
        ldy #CLKLO
        sty PORT
        asl
        ror fbits
        ldy #8
:       dey
        bne :-
        lda PORT
        ldy #FREE
        sty PORT
        asl
        ror fbits
        ldy #8
:       dey
        bne :-
        dex
        bne @bit
        lda fbits
        rts

; ---- what the page says -------------------------------------------------------------

t_head:     .byte "TRAIN SCHEDULE", 0
t_on:       .byte "BEST ON ", 0
t_new:      .byte "A NEW BEST SCORE - YOUR NAME", 0
t_keys:     .byte "THE STICK CHANGES IT, FIRE TAKES IT", 0
t_saving:   .byte "SAVING ...", 0
t_saved:    .byte "SAVED ON THE DISK", 0
t_failed:   .byte "COULD NOT SAVE IT ON THE DISK", 0
t_go_on:    .byte "FIRE TO GO ON", 0
pc:         .byte 70, 90, 100

; its variables
m:      .res 1                  ; the map, from 0
rank:   .res 1                  ; the new score's, and its index
at_i:   .res 1
r:      .res 1                  ; list_row's: the rank, its row
ry:     .res 1
pos:    .res 1                  ; the letter being given
held:   .res 1                  ; pictures up or down has been held
h:      .res 1
mx:     .res 2                  ; mul's
mk:     .res 1
mr:     .res 3
s100:   .res 3                  ; stars'
fbits:  .res 1                  ; the fast loader's
fpairs: .res 1
fcount: .res 1

        .segment "SCORES"
t_best:     .byte "BEST SCORE ", 0
t_by:       .byte " BY ", 0
pw_lo:      .byte <10000, <1000, <100, <10, <1
pw_hi:      .byte >10000, >1000, >100, >10, >1
n:      .res 1
col:    .res 1
tmp:    .res 1
nv:     .res 2                  ; score's
pad:    .res 1
nz:     .res 1

; file names (PETSCII)
.repeat 26, I
        .charmap $41 + I, $41 + I
.endrepeat
n_best:     .byte "s0:best", 0
n_page:     .byte "scores", 0

        .segment "SCPAGE"
fs_name:    .byte "best", $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0
            .byte $A0, $A0, $A0, $A0, 1     ; and: save

; ---- saving the KERNAL's way: run at $0400, the ROM in ------------------------------

        .segment "KSAVE"

; ksave: "best" saved, the old one scratched first (the 1541's save with
; replace is not to be trusted); then the drive's status read - that also
; waits till it has really written the file. C set if it failed. dev is
; above $8000, under the ROM: read before it comes in.
ksave:  lda dev
        sta @d1+1
        sta @d2+1
        sta @d3+1
        sta $FF3E               ; ROM in
        lda #15                 ; (the boot program may have left it open:
        jsr CLOSE               ; it asks the drive what it is, boot.s)
        lda #15
@d1:    ldx #8
        ldy #15
        jsr SETLFS
        lda #7
        ldx #<BEST_NAME
        ldy #>BEST_NAME
        jsr SETNAM
        jsr OPEN
        lda #15
        jsr CLOSE
        lda #0
@d2:    ldx #8
        ldy #0
        jsr SETLFS
        lda #4
        ldx #<(BEST_NAME + 3)
        ldy #>(BEST_NAME + 3)
        jsr SETNAM
        lda #<BEST
        sta ld_name
        lda #>BEST
        sta ld_name+1
        lda #ld_name
        ldx #<(BEST + BEST_LEN)
        ldy #>(BEST + BEST_LEN)
        jsr SAVE
        bcs @fail
        lda #15
@d3:    ldx #8
        ldy #15
        jsr SETLFS
        lda #0
        jsr SETNAM
        jsr OPEN
        bcs @fail
        ldx #15
        jsr CHKIN
        jsr CHRIN
        sta @st
        jsr CHRIN
        sta @st+1
        jsr CLRCHN
        lda #15
        jsr CLOSE
        lda @st
        cmp #'0'
        bne @fail
        lda @st+1
        cmp #'0'
        bne @fail
        clc
        bcc @out
@fail:  sec
@out:   sta $FF3F               ; ROM out (C kept)
        rts
@st:    .res 2
