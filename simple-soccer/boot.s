; boot.s - the disk's first program, "simple soccer": a loading screen -
; the name, a football turning, "LOADING" and its dots - while it loads the
; flags and the game, then the game
;
; As trainschedule's boot: if the drive is a 1541 (any of them), 1570 or
; 1571 - its DOS says so at $E5C5 - the fast loader's drive half goes into
; it (drive.s), the Plus/4's under the ROM at $FA00 (fastload.s), and the
; files come through them; any other drive (a 1551, 1581, SD2IEC ...) loads
; the KERNAL's way. First the flags for the title (tools/mkflags.py:
; "flags" to $E000, "flagset" to $F000, where the title finds them), then
; the game, packed (exomizer), over this program at $1001: what runs then
; is at $0400 - the interrupt, the loading, the start - which neither the
; game's file nor the KERNAL's loading touch. The interrupt goes on while
; the game unpacks itself, till its own start shuts it off.
;
; The screen: text at $0800 (colours) / $0C00 (codes), below $8000, which
; the TED reads from the RAM even while the KERNAL loads with the ROM in;
; the characters a copy of the ROM's (capitals and graphics) at $D000, in
; the RAM, the ball's nine among them, rewritten from the pictures at
; SPIN (tools/mkspinner.py) every SPIN_T frames.
;
; GAMESTART (from build.sh): where the packed game starts, as its own
; BASIC line would SYS to.

        .setcpu "6502"

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
BORDER  = $FF19
RASTER  = $FF1D
ROMON   = $FF3E
RAMON   = $FF3F
VBL     = 204           ; below the text
KIRQ    = $0314         ; the KERNAL's interrupt goes on through this
KIRQEND = $FCBE         ; and ends here, Y, X, A off the stack

DRIVE   = $0400         ; drive.s, in the drive
RESIDENT = $FA00        ; fastload.s
FL_NAME = RESIDENT + 7
FL_ADDR = RESIDENT + 9
GAME    = $1001
MATRIX  = $0800         ; colours; the codes at $0C00
CODES   = MATRIX + $400
CHARS   = $D000         ; the characters (the ROM's capitals copied)
SPIN    = $D400         ; the ball's pictures, 72 bytes each
SPIN_CODE = $60         ; its nine characters' first code (graphics the
                        ; text does not use)
SPIN_T  = 4             ; frames each picture shows
SPIN_ROW = 11
SPIN_COL = 18
DOTS    = MATRIX + 16 * 40 + 22     ; "LOADING"'s three dots' colours

WHITE   = $71
YELLOW  = $77
GREY    = $41

        .org GAME - 2
        .word GAME
        .word eol, 10           ; 10 SYS4109
        .byte $9E, "4109", 0
eol:    .word 0

        ; $100D
        jsr RESTOR              ; the KERNAL's own vectors (a fast loader
                                ; left resident points LOAD elsewhere)
        lda #0
        sta BORDER
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
:       lda CHARS,x             ; RAM under it (reading the ROM, writing
        sta CHARS,x             ; the RAM), the ball's pictures after them
        lda CHARS + $100,x
        sta CHARS + $100,x
        lda CHARS + $200,x
        sta CHARS + $200,x
        lda CHARS + $300,x
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
        sta RAMON               ; the ball's first picture (from under the
        jsr spin                ; ROM), its cells
        sta ROMON
        ldx #8
:       txa
        clc
        adc #SPIN_CODE
        ldy spin_cell,x
        sta CODES + SPIN_ROW * 40 + SPIN_COL,y
        dex
        bpl :-
        lda #<texts
        ldy #>texts
        jsr print
        lda TED07               ; text, 40 columns, 128 characters, hires
        and #$40                ; (PAL or NTSC kept)
        ora #$08
        sta TED07
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
@fast:  ldx #0                  ; the loader under the ROM (writes go to
:       lda resident_load,x     ; the RAM)
        sta RESIDENT,x
        inx
        bne :-
        inc fast
@slow:
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
        cli

        lda #<$E000             ; the flags: the title's
        sta l_addr
        lda #>$E000
        sta l_addr+1
        lda #<name_flags
        ldy #>name_flags
        jsr load
        lda #<$F000
        sta l_addr
        lda #>$F000
        sta l_addr+1
        lda #<name_set
        ldy #>name_set
        jsr load
        jmp game                ; the game, over this

name_flags: .byte "FLAGS", 0
name_set:   .byte "FLAGSET", 0

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
        .word CODES + 8 * 40 + 13
        .byte YELLOW, "SIMPLE SOCCER", 0
        .word CODES + 16 * 40 + 15
        .byte WHITE, "LOADING...", 0
        .word CODES + 22 * 40 + 8
        .byte GREY, "BY Q4Z1 2026 (& CLAUDE)", 0
        .word 0
.repeat 26, I
        .charmap $41 + I, $41 + I
.endrepeat

        .include "spinner.inc"          ; (tools/mkspinner.py)

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
        .incbin "build/fastload.bin"
        .res 256 - (* - resident_load)

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
        jsr tick
        pla
        tay
        pla
        tax
        pla
        rti
irq_rom:
        sta RAMON
        jsr tick
        sta ROMON
        jmp KIRQEND

tick:   lda IRQFLAG
        sta IRQFLAG
        inc frame
        lda frame               ; the dots after "LOADING": a wave through
        lsr                     ; them, a step every 4 frames, each dot 4
        lsr                     ; steps behind the one before
        ldx #2
@dot:   and #15
        tay
        lda dot_lum,y
        sta DOTS,x
        tya
        clc
        adc #4
        dex
        bpl @dot
        dec spin_t
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
; the dots' colours: white, its luminance rising and falling
dot_lum:    .byte $21, $21, $21, $21, $21, $21, $21, $21, $31, $41, $51, $61, $71, $61, $51, $31

tail_end:
        .assert tail_end <= $04FC, error, "the boot's tail: into the KERNAL's $04FC"

tail2_load = tail_load + (tail_end - tail)
        .org $05EC
tail2:

; the game over this program, the screen on meanwhile; then its start
game:   lda #<GAME
        sta l_addr
        lda #>GAME
        sta l_addr+1
        lda #<gname
        ldy #>gname
        jsr load
        sta VARTAB              ; where it ended
        stx VARTAB+1
        jmp GAMESTART           ; (the interrupt on: the game shuts it off)

; The file named at A/Y (0-terminated) to l_addr, by the fast loader if the
; drive runs it, else by the KERNAL; again, the border red, till it works.
; Its end in A/X.
load:   sta l_name
        sty l_name+1
@again: lda fast
        beq @kernal
        sta RAMON               ; the loader is under the ROM
        lda l_name
        sta FL_NAME
        lda l_name+1
        sta FL_NAME+1
        lda l_addr
        sta FL_ADDR
        lda l_addr+1
        sta FL_ADDR+1
        jsr RESIDENT
        sta ROMON
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
l_name: .word 0
l_addr: .word 0
frame:  .byte 0
spin_t: .byte SPIN_T
spin_k: .byte 0
tail2_end:
        .assert tail2_end <= $06EC, error, "the boot's second tail: over a page"
