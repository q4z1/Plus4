; boot.s - the disk's first program, "trainschedule": it shows the title
; picture and loads the game behind it
;
; If the drive is a 1541 (any of them), 1570 or 1571 - its DOS says so at
; $E5C5 - the boot writes the fast loader's drive half into it (drive.s),
; puts the Plus/4's half under the ROM at $FA00 (fastload.s, where the game
; finds it again for the maps) and loads with it. Any other drive (a 1551,
; 1581, SD2IEC ...) loads the KERNAL's way. First the title picture, packed
; (title.b, title.m: unpacked by exomizer's decruncher), which is then
; shown - so it is there a few seconds after RUN - and then the game, the
; picture staying on (the game finds it up and leaves it, front.s). The
; credits and a line below them ("loading", its dots pulsing) are written
; into it with the ROM's characters; the foot is the game's ticker's (engine.s). The picture is multicolour bitmap above a row of its
; own and hires bitmap from there (tools/mkpicture.py): a raster interrupt
; switches between the two, in a band of black lines. It goes on while the
; game loads and unpacks itself, till the game's own takes over. The
; loading runs at $0400, which neither the game's file nor the KERNAL's
; loading touch, as the game overwrites the boot at $1001; the interrupt
; too.
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
BMBASE  = $FF12
VMBASE  = $FF14
BG      = $FF15
MC1     = $FF16
BORDER  = $FF19
RASTER  = $FF1D
RCMP    = $FF0B
TOP     = 3             ; the raster line of the picture's first (engine
                        ; and front.s: the same)
VBL     = 251           ; below the picture, not drawn
KIRQ    = $0314         ; the KERNAL's interrupt goes on through this
KIRQEND = $FCBE         ; and ends here, Y, X, A off the stack
CREDIT  = $51           ; grey
NAME    = $42           ; red
FOOT    = $61           ; light grey
ROMON   = $FF3E
DOT_ON  = $E0           ; the dots (the interrupt): 0 till the text is in
RAMON   = $FF3F

DRIVE   = $0500         ; drive.s, in the drive
RESIDENT = $FA00        ; fastload.s
FL_NAME = RESIDENT + 7
FL_ADDR = RESIDENT + 9
GAME    = $1001
PACKED  = $2000         ; a packed file, before it is unpacked
BITMAP  = $C000         ; the title: its bitmap
MUSIC   = $E800         ; the title's song, the file "music"
MATRIX  = $0800         ; its colours ($0800) and characters ($0C00), the
                        ; two colours for the whole screen after them

; the decruncher's zero page (exodecrunch.s): free while the KERNAL works
zp_len_lo   = $D0
zp_len_hi   = $D1
zp_src_lo   = $D2
zp_src_hi   = zp_src_lo + 1
zp_bits_hi  = $D4
zp_ro_state = $D5
zp_bitbuf   = $D6               ; and the destination after it
DEST    = zp_bitbuf + 1  ; where it unpacks to

        .org GAME - 2
        .word GAME
        .word eol, 10           ; 10 SYS4109
        .byte $9E, "4109", 0
eol:    .word 0

        ; $100D
        jsr RESTOR              ; the KERNAL's own vectors: a fast loader
                                ; left resident (SJL264 at $05F5) points
                                ; LOAD into what the copies below overwrite
        lda #$00
        sta BORDER
        ldx #0
:       lda tail_load,x
        sta tail,x
        inx
        cpx #tail_end - tail
        bne :-
        ldx #0                  ; the player: a page, and the rest (not
:       lda player_load,x       ; beyond it: the KERNAL's $07D8-$07E7)
        sta player,x
        inx
        bne :-
:       lda player_load+256,x
        sta player+256,x
        inx
        cpx #player_end - player - 256
        bne :-
        lda FA
        cmp #8
        bcs :+
        lda #8
:       sta dev

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
@fast:  ldx #0                  ; the loader under the ROM (writes go to
:       lda resident_load,x     ; the RAM)
        sta RESIDENT,x
        inx
        bne :-
        inc fast
@slow:
        sei                     ; the KERNAL's interrupt off, ours on: the
        lda #0                  ; music, and the picture's two modes
        sta IRQEN
        sta MS_ON               ; (silent till mus_init: the RAM there is
                                ; whatever it was at power-on)
        lda IRQFLAG
        sta IRQFLAG
        lda TED06               ; the screen off while the picture comes
        and #$EF
        sta TED06
        lda #100                ; (till the picture says where)
        sta split_at
        lda #0                  ; no dots while the picture is unpacked:
        sta DOT_ON              ; exomizer copies from what it unpacked
        lda #<irq_ram           ; the interrupt: through $FFFE when the
        sta $FFFE               ; RAM is in, through the KERNAL when the
        lda #>irq_ram           ; ROM is
        sta $FFFF
        lda #<irq_rom
        sta KIRQ
        lda #>irq_rom
        sta KIRQ+1
        lda #VBL
        sta irq_at
        sta RCMP
        lda #$02                ; the raster interrupt, line < 256
        sta IRQEN
        cli

        lda #<MUSIC             ; the music first, and on with it: it plays
        sta l_addr              ; while the rest loads
        lda #>MUSIC
        sta l_addr+1
        lda #<name_mus
        ldy #>name_mus
        jsr load
        lda #<MUSIC
        ldx #>MUSIC
        sta RAMON               ; (the song is under the ROM)
        jsr mus_init
        sta ROMON

        lda #<name_b
        ldy #>name_b
        jsr load_packed
        lda #<BITMAP
        sta DEST
        lda #>BITMAP
        sta DEST+1
        sta RAMON               ; it reads back what it unpacked: under the
        jsr decrunch            ; ROM, so the RAM must be there
        sta ROMON
        lda #<name_m
        ldy #>name_m
        jsr load_packed
        lda #<MATRIX
        sta DEST
        lda #>MATRIX
        sta DEST+1
        jsr decrunch
        lda #<texts
        ldy #>texts
        jsr print
        inc DOT_ON

        lda MATRIX + 1002       ; the hires part's first row: switched
        asl                     ; to in its first lines, which are black
        asl
        asl
        adc #TOP
        sta split_at

        lda #205                ; on, in the border below the picture
:       cmp RASTER
        bne :-
        lda BMBASE              ; the bitmap from RAM at $C000
        and #$C3
        ora #$30
        sta BMBASE
        lda #>MATRIX
        sta VMBASE
        lda TED07               ; multicolour (PAL/NTSC kept)
        and #$40
        ora #$98
        sta TED07
        lda MATRIX + 1000
        sta BG
        lda MATRIX + 1001
        sta MC1
        lda #$3B                ; bitmap, screen on
        sta TED06
        jmp game

; Text into the hires part of the picture, in the ROM's characters (the
; set with lower case). A list of lines: the cell to start at (a word, 0
; ends the list), then screen codes, $FF and a colour to change the colour,
; LOWER to set the rest of the line a pixel lower (their eighth rows, empty
; but for descenders, are lost), 0 to end the line. Each cell gets its
; colour for set pixels, black for the rest.
TP      = $DA           ; zero page (free while the KERNAL works): the text
BP      = $DC           ; the bitmap
MP      = $DE           ; the cell in the matrices
GP      = $D0           ; the character in the ROM
COLOUR  = $D2
SHIFT   = $D9           ; 1 for a pixel lower
LOWER   = $FE
print:  sta TP
        sty TP+1
@line:  jsr @next               ; where: $C000 + cell * 8, $0800 + cell
        sta MP
        jsr @next
        sta MP+1
        ora MP
        bne :+
        rts
:       ldx #0
        stx SHIFT
        lda MP
        sta BP
        lda MP+1
        asl BP
        rol
        asl BP
        rol
        asl BP
        rol
        ora #>BITMAP
        sta BP+1
        lda MP+1
        ora #>MATRIX
        sta MP+1
@char:  jsr @next
        beq @line
        cmp #LOWER
        bne :+
        inc SHIFT
        bne @char
:       cmp #$FF
        bne @glyph
        jsr @next
        sta COLOUR
        jmp @char
@glyph: ldx #0                  ; $D400 + code * 8, a byte before it
        stx GP+1                ; when lower
        asl
        rol GP+1
        asl
        rol GP+1
        asl
        rol GP+1
        sec
        sbc SHIFT
        sta GP
        lda GP+1
        ora #$D4
        sbc #0
        sta GP+1
        ldy #7
:       lda (GP),y
        sta (BP),y
        dey
        bpl :-
        iny
        lda SHIFT               ; lower: the top row empty
        beq :+
        tya
        sta (BP),y
:                               ; the cell's colours
        lda COLOUR
        lsr
        lsr
        lsr
        lsr
        sta (MP),y              ; attribute: luminance for 1, 0 for 0
        lda MP+1
        ora #$04
        sta MP+1
        lda COLOUR
        asl
        asl
        asl
        asl
        sta (MP),y              ; character: colour for 1, black for 0
        lda MP+1
        and #<~$04
        sta MP+1
        lda BP                  ; on to the next cell
        clc
        adc #8
        sta BP
        bcc :+
        inc BP+1
:       inc MP
        bne @char
        inc MP+1
        bne @char
@done:  rts
@next:  ldy #0                  ; the next byte of the text, Z for 0
        lda (TP),y
        inc TP
        bne :+
        inc TP+1
:       tax
        rts

.repeat 26, I                   ; lower case as the ROM's second set has it
        .charmap $61 + I, $01 + I
.endrepeat
texts:                          ; as the game has them (engine.s)
        .word 17 * 40 + 14
        .byte $FF, CREDIT, "by ", $FF, NAME, "q4z1", $FF, CREDIT, " 2026", 0
        .word 18 * 40 + 15
        .byte LOWER, "(& Claude)", 0
        .word 20 * 40 + 10
        .byte $FF, FOOT, "     loading ...    ", 0
        .word 0
.repeat 26, I
        .charmap $61 + I, $61 + I
.endrepeat

; A packed file, name at A/Y, to PACKED, and the decruncher pointed at it
load_packed:
        ldx #<PACKED
        stx gcb + 1
        stx l_addr
        ldx #>PACKED
        stx gcb + 2
        stx l_addr+1
        jmp load

; the next packed byte, keeping X, Y, C and V
get_crunched_byte:
gcb:    lda $FFFF
        inc gcb + 1
        bne :+
        inc gcb + 2
:       rts

DECRUNCH_FORWARDS = 1
        .include "exodecrunch.s"

name_mus:
        .byte "MUSIC", 0
name_b: .byte "TITLE.B", 0
name_m: .byte "TITLE.M", 0

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
        .res 256 - (* - resident_load)

; ---- the last steps, at $0400 ------------------------------------------

tail_load:
        .org $0400
tail:

; The interrupt: multicolour above split_at, hires below; the dots and the
; music in the vertical blank (C set by split then), the music from MUSIC
; under the ROM (the title's song, tools/mkmusic.py)
irq_ram:
        pha
        txa
        pha
        tya
        pha
        jsr split
        bcc :+
        jsr dots
:       pla
        tay
        pla
        tax
        pla
        rti
irq_rom:
        jsr split
        bcc :+
        sta RAMON
        jsr dots
        sta ROMON
:       jmp KIRQEND
split:  lda IRQFLAG
        sta IRQFLAG
        lda irq_at
        cmp #VBL
        bne @hires
        lda TED07               ; multicolour for the top ...
        ora #$10
        sta TED07
        lda split_at            ; ... hires from split_at
        sta irq_at
        sta RCMP
        sec
        rts
@hires: lda TED07
        and #<~$10
        sta TED07
        lda #VBL
        sta irq_at
        sta RCMP
        clc
        rts

; the game behind the picture, which stays on meanwhile
game:   lda #<GAME
        sta l_addr
        lda #>GAME
        sta l_addr+1
        lda #<gname
        ldy #>gname
        jsr load
        sta VARTAB              ; where it ended
        stx VARTAB+1
        jmp GAMESTART           ; interrupts still off: the game sets its own

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
rom:    .byte 0, 0
l_name: .word 0
l_addr: .word 0
split_at:
        .byte 0
irq_at: .byte 0
tail_end:
        .assert tail_end <= $04FB, error, "the boot's tail is too long"

; the music's player, and the dots, at $05EC: the KERNAL leaves
; $05EC-$07B7 alone
player_load = tail_load + (tail_end - tail)
        .org $05EC
player:
MSTATE  = $07A0                 ; the player's place: the game takes it over
        .include "music.inc"

; The three dots after "loading", a wave going through them as a spinner
; does: each dot's luminance from dot_lum, a step every 4 frames, a dot 4
; steps behind the one before it; then the music. Not before DOT_ON: a dot
; written while exomizer unpacks the colours would be copied on by it, into
; the background's colour too.
DOTS    = MATRIX + 20 * 40 + 23 ; texts: their cells' attributes
dots:   lda DOT_ON
        beq @tick
        inc dot_t
        lda dot_t
        lsr
        lsr
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
@tick:  jmp mus_tick
dot_lum:
        .byte 2, 2, 2, 2, 2, 2, 2, 2, 3, 4, 5, 6, 6, 5, 4, 3
dot_t:  .byte 0
player_end:
        .assert player_end <= MSTATE, error, "the boot's player is too long"
        .assert player_end - player > 256, error, "the copy expects more than a page"
