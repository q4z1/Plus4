; help.s - the page of help, and the bulb in the choice of a map that
; opens it. Part of the overlay (trainschedule.cfg: OVL, the file "help"),
; with the choice itself (front.s).
;
; The bulb: nine characters of the choice's font at $D800, top right. Till
; the page has been read (help_read) it is lit and hops now and then; then
; it is grey and still. Up from the first map chooses it, fire opens the
; page - and Help does, anywhere in the choice.
;
; The page: as long as the text needs (tools/mkhelp.py, data/help.txt),
; drawn out first, 40 bytes a row, below the choice's font; a screen of it
; at a time is copied to one of two screens, $0800 and $C000 - neither
; shown in the choice - and that one is shown while the next is made. In
; between it moves by the pixel, the TED's y scroll: the whole screen, so
; it is all page, 24 rows high (the half rows at the top and the bottom
; under the border). The stick scrolls it, faster the longer it is held,
; and it runs out when let go - as a droid moves in Paradroid. Fire closes
; it. Both registers are written below the picture, before the vertical
; blank, the picture after shows them; the choice's screen and font stay
; as they are, but for the page's frame, eight characters lent from the
; ROM's (none of them in the choice), put back when it closes.
;
; Extended colour: a character's top two bits choose its background -
; black, the paper, a heading's band, a key's cap - and its glyph is one of
; the font's first 64; one ink for all.

        .include "game.inc"

        .export help_hits, bulb_place

        .import _frames, _keys, _kheld2, _eng_hits, _eng_hits2
        .import cm_sel, show_maps, help_read
        .import help_doc, bulb_lit, bulb_dim
        .importzp HELP_ROWS, BULB_H

TED_SCROLLY = $FF06
TED_VMBASE  = $FF14
TED_RHI     = $FF1C
TED_RLO     = $FF1D

CH_FONT     = $D800             ; the choice's characters (engine.s)
DOC         = $C800             ; the page drawn out
        .assert DOC + HELP_ROWS * 40 <= CH_FONT, lderror, "the page is too long"
PG_A       = $08               ; the two screens: colours, characters +$400
PG_B       = $C0
PAGE_L      = 1                 ; the page's columns: its edges
PAGE_R      = 38
TEXT_COL    = 3                 ; its text's first (mkhelp.py: 34 of them)
PAGE_MAX    = (HELP_ROWS - 25) * 8 + 7      ; its last pixel row on top
P_MAX       = PAGE_MAX * 16     ; the same in 16ths

ACCEL       = 3                 ; 16ths of a pixel a picture, each picture
KICK        = 16                ; held: from a stand at once
BRAKE       = 8                 ; pushed the other way
DECEL       = 4                 ; let go
VMAX        = 64                ; 4 pixels a picture

COL_PAGE    = $78               ; the board's book's paper (game.inc:
                                ; COL_INK its ink)
COL_BAND    = $6D               ; its ruling: a heading's band
COL_CAP     = $51               ; a key's cap

; the frame's characters, the ROM's [ pound ] up-arrow left-arrow # $ %
PF_TL = 27
PF_T  = 28
PF_TR = 29
PF_L  = 30
PF_R  = 31
PF_BL = 35
PF_B  = 36
PF_BR = 37
PF_A  = CH_FONT + PF_TL * 8        ; two runs of them: 5 and 3
PF_B8 = CH_FONT + PF_BL * 8

BULB_CODE = 70                  ; its characters, 3 by 3 (after the locks)
BULB_COL  = 36                  ; where (front.s puts the mark in 35)
BULB_ROW  = 0
BULB_GLYPH = CH_FONT + BULB_CODE * 8
COL_LIT   = $77
COL_OUT   = $41

        .segment "GAMEZP": zeropage
hs:     .res 2                  ; doc_make's: from, to
hd:     .res 2

        .segment "OVLBSS"       ; (behind the catalogue, trainschedule.cfg)
hh:     .res 1                  ; help_hits': the keys
hl_prev: .res 1                 ; Help, as it was
bl_f:   .res 1                  ; the bulb's: the picture last seen
bl_t:   .res 1                  ; its hop's place
bl_st:  .res 1                  ; how it is drawn: hop | 128 if read, 255
                                ; none yet
bl_y:   .res 1
pv:     .res 1                  ; the page's speed, 16ths a picture, signed
pp:     .res 2                  ; its place: the top pixel row, in 16ths
pg_row: .res 1                  ; the row on top of the screen shown
pg_vm:  .res 1                  ; and that screen
pg_ys:  .res 1                  ; the y scroll for it
pg_f:   .res 1                  ; the picture last shown
dh:     .res 1                  ; render's
rk:     .res 1                  ; doc_make's
rn:     .res 1
saved:  .res 64                 ; what the frame's characters were

        .segment "OVLDATA"
; a hop and a smaller one, then a rest (to 64): pixels up, a picture each
hop:    .byte 0, 1, 2, 3, 3, 4, 4, 4, 4, 3, 3, 2, 1, 0
        .byte 0, 1, 1, 2, 2, 2, 2, 1, 1
HOP_N = * - hop

; the frame, 2 pixels wide in the ink, inside the page's edge cells
frame:  .byte $FF, $FF, $C0, $C0, $C0, $C0, $C0, $C0     ; top left
        .byte $FF, $FF, $00, $00, $00, $00, $00, $00     ; top
        .byte $FF, $FF, $03, $03, $03, $03, $03, $03     ; top right
        .byte $C0, $C0, $C0, $C0, $C0, $C0, $C0, $C0     ; left
        .byte $03, $03, $03, $03, $03, $03, $03, $03     ; right
        .byte $C0, $C0, $C0, $C0, $C0, $C0, $FF, $FF     ; bottom left
        .byte $00, $00, $00, $00, $00, $00, $FF, $FF     ; bottom
        .byte $03, $03, $03, $03, $03, $03, $FF, $FF     ; bottom right

; a row by its kind (mkhelp.py): black, top, bottom, text, heading - its
; left edge, its inside, its right edge
kind_l: .byte 32, PF_TL | 64, PF_BL | 64, PF_L | 64, PF_L | 64
kind_f: .byte 32, PF_T | 64, PF_B | 64, 32 | 64, 32 | 128
kind_r: .byte 32, PF_TR | 64, PF_BR | 64, PF_R | 64, PF_R | 64

        .segment "OVLCODE"

; ---- the bulb ----------------------------------------------------------------

; bulb_place: its characters on the choice's screen, dark till they are
; drawn (their bytes are still the title's picture's)
bulb_place:
        lda #255
        sta bl_st
        ldx #2
:
.repeat 3, R
        txa
        clc
        adc #BULB_CODE + R * 3
        sta $F400 + (BULB_ROW + R) * 40 + BULB_COL,x
        lda #COL_BG
        sta $F000 + (BULB_ROW + R) * 40 + BULB_COL,x
.endrepeat
        dex
        bpl :-
        rts

; bulb_tick: a picture on, the bulb as it is now, drawn if that changed
bulb_tick:
        lda _frames
        cmp bl_f
        beq @rts
        sta bl_f
        lda help_read
        beq :+
        lda #128
        bne @st
:       inc bl_t
        lda bl_t
        and #63
        tax
        lda #0
        cpx #HOP_N
        bcs @st
        lda hop,x
@st:    cmp bl_st
        beq @rts
        sta bl_st
        jmp bulb_draw
@rts:   rts

; bulb_draw: its characters drawn afresh as bl_st says, while the beam is
; not on them (and done before it is back)
bulb_draw:
        lda bl_st
        and #7
        eor #$FF                ; its top: 24 - BULB_H - the hop
        sec
        adc #24 - BULB_H
        sta bl_y
        ldx #<bulb_lit
        ldy #>bulb_lit
        lda bl_st
        bpl :+
        ldx #<bulb_dim
        ldy #>bulb_dim
:       stx bd0+1
        sty bd0+2
        inx
        bne :+
        iny
:       stx bd1+1
        sty bd1+2
        inx
        bne :+
        iny
:       stx bd2+1
        sty bd2+2
:       lda TED_RHI             ; lines 32-239: below it, above the blank
        lsr a
        bcs :-
        lda TED_RLO
        cmp #32
        bcc :-
        cmp #240
        bcs :-
        lda #0
        ldx #9 * 8 - 1
:       sta BULB_GLYPH,x
        dex
        bpl :-
        ldx #0                  ; its rows, 3 bytes each
bd_row: lda bl_y                ; to (y / 8) * 24 + y & 7
        lsr a
        lsr a
        lsr a
        tay
        lda #0
:       dey
        bmi :+
        clc
        adc #24
        bne :-
:       sta dh
        lda bl_y
        and #7
        ora dh
        tay
bd0:    lda bulb_lit,x
        sta BULB_GLYPH,y
bd1:    lda bulb_lit+1,x
        sta BULB_GLYPH + 8,y
bd2:    lda bulb_lit+2,x
        sta BULB_GLYPH + 16,y
        inc bl_y
        inx
        inx
        inx
        cpx #BULB_H * 3
        bne bd_row
        lda #COL_LIT
        ldx bl_st
        bpl :+
        lda #COL_OUT
:       ldx #2
:
.repeat 3, R
        sta $F000 + (BULB_ROW + R) * 40 + BULB_COL,x
.endrepeat
        dex
        bpl :-
        rts

; help_hits: the keys of the choice (A, from eng_hits) through the bulb
; first: up from the first map chooses it, fire on it, or Help, opens the
; page. What is left for the choice comes back in A.
help_hits:
        sta hh
        jsr bulb_tick
        jsr help_key
        bne @open
        lda cm_sel
        bpl @maps
        lda hh
        and #K_FIRE
        bne @open
        lda hh
        and #<~K_UP
        rts
@maps:  bne @out                ; (not the first)
        lda hh
        and #K_UP
        beq @out
        lda #255
        sta cm_sel
        jsr show_maps
        lda hh
        and #<~K_UP
        rts
@out:   lda hh
        rts
@open:  jsr page
        lda #0
        rts

; help_key: Z clear if Help has just been pressed
help_key:
        lda _kheld2
        and #16
        tax
        eor hl_prev
        stx hl_prev
        and hl_prev
        rts

; ---- the page ----------------------------------------------------------------

page:   jsr doc_make
        ldx #0                  ; both screens' colours: the ink
        lda #COL_INK
:       sta $0800,x
        sta $0900,x
        sta $0A00,x
        sta $0B00 - 24,x
        sta $C000,x
        sta $C100,x
        sta $C200,x
        sta $C300 - 24,x
        inx
        bne :-
        lda #0
        sta pv
        sta pp
        sta pp+1
        sta pg_row
        lda #7
        sta pg_ys
        lda #PG_A
        sta pg_vm
        lda #0
        ldx #PG_A + 4
        jsr render
        lda _frames
        sta pg_f
        jsr below               ; on: the frame's characters lent, the
        ldx #5 * 8 - 1          ; colours, the mode, the screen
:       lda PF_A,x
        sta saved,x
        lda frame,x
        sta PF_A,x
        dex
        bpl :-
        ldx #3 * 8 - 1
:       lda PF_B8,x
        sta saved + 40,x
        lda frame + 40,x
        sta PF_B8,x
        dex
        bpl :-
        lda #COL_PAGE
        sta $FF16
        lda #COL_BAND
        sta $FF17
        lda #COL_CAP
        sta $FF18
        jmp @show

@loop:  lda _frames             ; once a picture, below it
        cmp pg_f
        beq @loop
        sta pg_f
        jsr below
@show:  lda pg_ys
        ora #$50                ; extended colour, on, 24 rows
        sta TED_SCROLLY
        lda pg_vm
        sta TED_VMBASE
        cli
        jsr _eng_hits           ; fire, Esc or Help: closed
        and #K_FIRE
        bne @close
        jsr _eng_hits2
        and #8
        bne @close
        jsr help_key
        bne @close
        jsr move
        lda pp                  ; the row on top: pp / 128
        asl a
        lda pp+1
        rol a
        tax
        lda pp                  ; the scroll: 7 - (pp / 16) & 7
        lsr a
        lsr a
        lsr a
        lsr a
        and #7
        eor #7
        sta pg_ys
        cpx pg_row
        beq @loop
        stx pg_row              ; another row on top: the other screen
        lda pg_vm
        eor #PG_A ^ PG_B
        sta pg_vm
        ora #4
        tax
        lda pg_row
        jsr render
        jmp @loop

@close: jsr below               ; the choice again, its characters
        lda #$1B                ; (engine.s show_on)
        sta TED_SCROLLY
        lda #$F0
        sta TED_VMBASE
        ldx #5 * 8 - 1
:       lda saved,x
        sta PF_A,x
        dex
        bpl :-
        ldx #3 * 8 - 1
:       lda saved + 40,x
        sta PF_B8,x
        dex
        bpl :-
        cli
        lda #1
        sta help_read
        jsr _eng_hits
        jmp _eng_hits2

; below: interrupts off, the beam below the picture and not yet at the
; vertical blank's interrupt (engine.s VBL_LINE 251): what is written now
; is for the next picture, all of it
below:  sei
        lda TED_RHI
        lsr a
        bcs @no
        lda TED_RLO
        cmp #204
        bcc @no
        cmp #244
        bcc @rts
@no:    cli
        jmp below
@rts:   rts

; move: the page's speed by the stick (fire not held), and its place by
; that - not past its ends
move:   lda _keys
        and #K_FIRE
        bne @none
        lda _keys
        and #K_UP
        bne @up
        lda _keys
        and #K_DOWN
        bne @down
@none:  lda pv                  ; let go: slower
        beq @go
        bpl @lpos
        clc
        adc #DECEL
        bmi @set
        lda #0
        beq @set
@lpos:  sec
        sbc #DECEL
        bpl @set
        lda #0
        beq @set
@down:  lda pv
        bmi @dbr
        bne :+
        lda #KICK
        bne @set
:       clc
        adc #ACCEL
        cmp #VMAX + 1
        bcc @set
        lda #VMAX
        bne @set
@dbr:   clc                     ; going up: braking first
        adc #BRAKE
        bmi @set
        lda #0
        beq @set
@up:    lda pv
        beq @ukick
        bpl @ubr
        sec
        sbc #ACCEL
        cmp #<-VMAX
        bcs @set
        lda #<-VMAX
        bne @set
@ukick: lda #<-KICK
        bne @set
@ubr:   sec
        sbc #BRAKE
        bpl @set
        lda #0
@set:   sta pv
@go:    lda pv
        beq @rts
        ldx #0
        ora #0
        bpl :+
        dex
:       clc
        adc pp
        sta pp
        txa
        adc pp+1
        sta pp+1
        bmi @top
        cmp #>P_MAX
        bcc @rts
        bne @end
        lda pp
        cmp #<P_MAX + 1
        bcc @rts
@end:   lda #<P_MAX
        sta pp
        lda #>P_MAX
        sta pp+1
        lda #0
        sta pv
        rts
@top:   lda #0
        sta pp
        sta pp+1
        sta pv
@rts:   rts

; render: the page from row A on, a screen of it, to the characters at
; page X ($0C or $C4) - 1000 bytes, 4 runs of 250
render: stx dh
        ldx #0                  ; DOC + A * 40: A * 8 + A * 32
        stx hs+1
        asl a
        rol hs+1
        asl a
        rol hs+1
        asl a
        rol hs+1
        sta hs
        ldx hs+1
        asl a
        rol hs+1
        asl a
        rol hs+1
        clc
        adc hs
        sta hs
        txa
        adc hs+1
        adc #>DOC               ; (<DOC is 0)
        sta hs+1
.repeat 4, I
        lda hs
        clc
        adc #<(I * 250)
        sta .ident(.sprintf("rr%d", I)) + 1
        lda hs+1
        adc #>(I * 250)
        sta .ident(.sprintf("rr%d", I)) + 2
        lda dh
        clc
        adc #>(I * 250)
        sta .ident(.sprintf("rw%d", I)) + 2
.endrepeat
        ldx #0
rd_copy:
.repeat 4, I
.ident(.sprintf("rr%d", I)):
        lda DOC,x
.ident(.sprintf("rw%d", I)):
        sta a:<(I * 250),x
.endrepeat
        inx
        cpx #250
        bne rd_copy
        rts
        .assert <DOC = 0, error, "render: DOC on a page's start"

; doc_make: the page drawn out to DOC, a row of 40 by its kind
doc_make:
        lda #<help_doc
        sta hs
        lda #>help_doc
        sta hs+1
        lda #<DOC
        sta hd
        lda #>DOC
        sta hd+1
        lda #HELP_ROWS
        sta rn
@row:   ldy #0
        lda (hs),y
        sta rk
        inc hs
        bne :+
        inc hs+1
:       ldx rk
        ldy #39
@col:   lda #32
        cpy #PAGE_R + 1
        bcs @put
        cpy #PAGE_L
        bcc @put
        lda kind_l,x
        cpy #PAGE_L
        beq @put
        lda kind_r,x
        cpy #PAGE_R
        beq @put
        lda kind_f,x
@put:   sta (hd),y
        dey
        bpl @col
        ldx rk                  ; text and headings: their codes
        cpx #3
        bcc @next
        ldy #0
        lda (hs),y
        tax
        inc hs
        bne :+
        inc hs+1
:       lda #TEXT_COL           ; from the text's column: a code, or
        sta rk                  ; below 64 so many columns skipped
        txa
        beq @next
@code:  ldy #0
        lda (hs),y
        inc hs
        bne :+
        inc hs+1
:       cmp #64
        bcs :+
        adc rk
        sta rk
        bcc @on
:       ldy rk
        sta (hd),y
        inc rk
@on:    dex
        bne @code
@next:  lda hd
        clc
        adc #40
        sta hd
        bcc :+
        inc hd+1
:       dec rn
        bne @row
        rts
