; boot.s - the disk's first program, "stardew": it loads the game
;
; If the drive is a 1541 (any of them), 1570 or 1571 - its DOS says so at
; $E5C5 - the boot writes the fast loader's drive half into it (drive.s),
; puts the Plus/4's half at $0600 (fastload.s, where the game finds it again
; for its rooms, tile sets and saves) and loads with it. Any other drive (a
; 1551, 1581, SD2IEC ...) loads the KERNAL's way, and so does the game
; then. The game is "game", packed by exomizer: it unpacks itself when it
; is started, as it did when it was the disk's first file. Meanwhile the
; screen says what is going on. The loading runs at $0400, which neither
; the game's file nor the KERNAL's loading touch, as the game overwrites
; the boot at $1001. (After trainschedule's boot, without its title.)
;
; GAMESTART (from build.sh): where the packed game starts, as its own
; BASIC line would SYS to.

        .setcpu "6502"

SETLFS  = $FFBA
SETNAM  = $FFBD
OPEN    = $FFC0
CLOSE   = $FFC3
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
BG      = $FF15
BORDER  = $FF19
SCREEN  = $0C00
COLOURS = $0800

DRIVE   = $0400         ; drive.s, in the drive
RESIDENT = $0600        ; fastload.s, in the Plus/4
FL_MAGIC = RESIDENT + 6
FL_NAME = RESIDENT + 10
FL_ADDR = RESIDENT + 12
GAME    = $1001

        .org GAME - 2
        .word GAME
        .word eol, 10           ; 10 SYS4109
        .byte $9E, "4109", 0
eol:    .word 0

        ; $100D
        jsr RESTOR              ; the KERNAL's own vectors: a fast loader
                                ; left resident (SJL264 at $05F5) points
                                ; LOAD into what the copies below overwrite
        ldx #0
:       lda tail_load,x
        sta tail,x
        inx
        cpx #tail_end - tail
        bne :-
        lda FA
        cmp #8
        bcs :+
        lda #8
:       sta dev

        lda #$93                ; the screen: black, the game's name and
        jsr CHROUT              ; "loading"
        lda #$00
        sta BORDER
        sta BG
        ldx #title_end - title - 1
:       lda title,x
        sta SCREEN + 11 * 40 + 14,x
        lda #$71                ; white
        sta COLOURS + 11 * 40 + 14,x
        dex
        bpl :-
        ldx #loading_end - loading - 1
:       lda loading,x
        sta SCREEN + 13 * 40 + 14,x
        lda #$51                ; grey
        sta COLOURS + 13 * 40 + 14,x
        dex
        bpl :-

        jsr detect
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
@fast:  ldx #0                  ; the loader in its place
:       lda resident_load,x
        sta RESIDENT,x
        inx
        bne :-
:       lda resident_load+256,x
        sta RESIDENT+256,x
        inx
        cpx #resident_end - resident_load - 256
        bne :-
        inc fast
        jmp game
@slow:  lda #15                 ; the command channel closed, if it was
        jsr CLOSE               ; opened: the game opens it to save
        lda #0                  ; and no loader for the game to find
        sta FL_MAGIC
        jmp game

.repeat 26, I                   ; screen codes
        .charmap $41 + I, $01 + I
.endrepeat
title:  .byte "STARDEW POND"
title_end:
loading:
        .byte "LOADING ..."
loading_end:
.repeat 26, I
        .charmap $41 + I, $41 + I
.endrepeat

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
        .incbin "build/fastload.bin"
resident_end:
        .assert resident_end - resident_load > 256, error, "the copy expects more than a page"

; ---- the last steps, at $0400 ------------------------------------------

tail_load:
        .org $0400
tail:

; the game, over the boot
game:   lda #<GAME
        sta l_addr
        lda #>GAME
        sta l_addr+1
        lda #<gname
        ldy #>gname
        jsr load
        sta VARTAB              ; where it ended
        stx VARTAB+1
        jmp GAMESTART

; The file named at A/Y (0-terminated) to l_addr, by the fast loader if the
; drive runs it, else by the KERNAL; again, the border red, till it works.
; Its end in A/X.
load:   sta l_name
        sty l_name+1
@again: lda fast
        beq @kernal
        lda l_name
        sta FL_NAME
        lda l_name+1
        sta FL_NAME+1
        lda l_addr
        sta FL_ADDR
        lda l_addr+1
        sta FL_ADDR+1
        sei                     ; (the KERNAL's interrupt kept off $01)
        jsr RESIDENT
        cli
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
        lda #$00
        sta BORDER
        pla
        rts
@red:   lda #$32                ; no disk, or it failed
        sta BORDER
        jmp @again

gname:  .byte "GAME", 0
fast:   .byte 0                 ; 1: the drive runs the fast loader
dev:    .byte 0
rom:    .byte 0, 0
l_name: .word 0
l_addr: .word 0
tail_end:
        .assert tail_end <= $04FB, error, "the boot's tail is too long"
