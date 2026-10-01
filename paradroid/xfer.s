; xfer.s - the transfer game's board: how pulses pass and how a line is
; drawn. transfer.c lays the board out and runs the game; this is what it
; does for every line every tick, and is shorter and faster here.
;
; A side has 4 layers of 12 lines, a layer after the other: part[] holds
; the parts (transfer.c), live[] whether each carries a pulse (0 or 1).
; Side 0 is the left, yellow; side 1 the right, purple, drawn mirrored.

        .include "build/gen/tiles.inc"

        .export _part, _live, _life, _drawn
        .export _xs, _xr, _tcol, _blk
        .export _x_pass, _x_line, _x_step, _x_flow
        .export _out_r

NL      = 12
ROW0    = 11                    ; screen row of the first line

; the parts, as in transfer.c
WIRE    = 0
DEAD    = 1
AMP     = 2
SWAP    = 3
BR_T    = 4
BR_B    = 6
GA_M    = 8
NONE    = 10

G_F1    = POOL + 0              ; the original's characters $F1 on:
G_F2    = POOL + 1              ;   wires left and right,
G_F3    = POOL + 2              ;   arrows pointing left
G_FD    = POOL + 12             ;   and right

FONT0   = $C800
FONT1   = $D800

        .segment "ENGZP": zeropage
pa0:    .res 2                  ; the line's row in both pictures:
pc0:    .res 2                  ;   colours and codes
pa1:    .res 2
pc1:    .res 2
xi:     .res 1                  ; index of the cell in part/live
xe:     .res 1                  ; its part
xv:     .res 1                  ; and whether live
xk:     .res 1                  ; live bits of the line, for drawn[]
xat:    .res 1                  ; attribute to draw with
xw:     .res 1                  ; the side's wire character
xcs:    .res 1                  ; its colour
xco:    .res 1                  ; the other side's
xcol:   .res 1
xn:     .res 1
xp:     .res 1

        .segment "LOWBSS"
_part:  .res 2 * 4 * NL
_live:  .res 2 * 4 * NL
_life:  .res 2 * NL             ; ticks a pulse put in has left
_drawn: .res 2 * NL             ; live bits as last drawn

        .bss
_xs:    .res 1                  ; the side and line x_line draws
_xr:    .res 1
_tcol:  .res 2                  ; the sides' colours
_blk:   .res 1                  ; a dead wire's

        .rodata
; a part passes a pulse on to the right; it takes one from the left; its
; character (the arrows of DEAD and AMP for the left side)
_out_r: .byte 1, 0, 1, 1, 1, 0, 1, 0, 1, 0, 0
in_l:   .byte 1, 1, 1, 1, 0, 1, 0, 1, 0, 1, 0
glyph:  .byte G_F1, G_F3, G_FD, POOL+3, POOL+4, POOL+5, POOL+6
        .byte POOL+4, POOL+5, POOL+6, 0
base48: .byte 0, 4 * NL
base12: .byte 0, NL
rowlo:  .repeat NL, R
        .byte <((ROW0 + R) * 40)
        .endrepeat
rowhi:  .repeat NL, R
        .byte >((ROW0 + R) * 40)
        .endrepeat

        .code

; ---------------------------------------------------------------------------
; x_pass: side A's pulses passed on, layer by layer (FreedroidClassic's
; ProcessPlayground): layer 0 is live where a pulse was put in; a part is
; live as the part before it, an amplifier stays live once it was, a
; branch's ends follow its middle, a gate's middle needs both its ends,
; and the last layer is live where the one before passes on. Twice, for
; the branches, which look at their middle below them.
_x_pass:
        tax
        ldy base12,x
        lda base48,x
        sta xp
        tax
        lda #NL
        sta xn
@l0:    lda _life,y
        beq :+
        lda #1
:       sta _live,x
        inx
        iny
        dec xn
        bne @l0
        lda #2
        sta xk
@pass:  lda xp
        clc
        adc #NL
        tax
        lda #3 * NL
        sta xn
@cell:  lda xn
        cmp #NL + 1
        bcs @mid
        lda _live - NL,x        ; the last layer
        beq @st
        ldy _part - NL,x
        lda _out_r,y
        jmp @st
@mid:   ldy _part,x
        cpy #AMP
        bne :+
        lda _live - NL,x
        ora _live,x
        jmp @st
:       cpy #BR_T
        bne :+
        lda _live + 1,x
        jmp @st
:       cpy #BR_B
        bne :+
        lda _live - 1,x
        jmp @st
:       cpy #GA_M
        bne :+
        lda _live - 1,x
        and _live + 1,x
        jmp @st
:       lda #0
        cpy #DEAD
        beq @st
        cpy #NONE
        beq @st
        lda _live - NL,x
@st:    sta _live,x
        inx
        dec xn
        bne @cell
        dec xk
        bne @pass
        rts

; ---------------------------------------------------------------------------
; x_step: side A's lines drawn again where their live bits changed
_x_step:
        sta _xs
        lda #0
        sta _xr
@r:     ldx _xs
        lda base12,x
        clc
        adc _xr
        tax
        lda _drawn,x
        sta xn
        ldx _xs
        lda base48,x
        clc
        adc _xr
        tax
        lda _live,x
        asl a
        ora _live + NL,x
        asl a
        ora _live + 2 * NL,x
        asl a
        ora _live + 3 * NL,x
        cmp xn
        beq :+
        jsr _x_line
:       inc _xr
        lda _xr
        cmp #NL
        bne @r
        rts

; ---------------------------------------------------------------------------
; x_line: line xr of side xs. Each of the first three layers is four cells,
; columns 4-7, 8-11, 12-15 from the rail: the way in (if the part takes a
; pulse from the left), the part, the way out (if it passes one on). The
; last layer is the two cells to the column. Dead wires are black, live
; ones the side's colour - after a colour changer the other side's.
_x_line:
        ldy _xr
        lda rowlo,y
        sta pa0
        sta pc0
        sta pa1
        sta pc1
        lda rowhi,y
        ora #$C0
        sta pa0 + 1
        ora #$04
        sta pc0 + 1
        eor #$C4 ^ $D4
        sta pc1 + 1
        and #$FB
        sta pa1 + 1
        ldx _xs
        lda #G_F1
        cpx #0
        beq :+
        lda #G_F2
:       sta xw
        lda _tcol,x
        sta xcs
        txa
        eor #1
        tax
        lda _tcol,x
        sta xco
        ldx _xs
        lda base48,x
        clc
        adc _xr
        sta xi
        lda #0
        sta xk
        lda #4
        sta xcol
@layer: ldx xi
        lda _part,x
        sta xe
        lda _live,x
        sta xv
        lsr a
        rol xk
        lda _blk
        ldy xv
        beq :+
        lda xcs
:       sta xat
        ; the way in
        ldy xe
        lda in_l,y
        beq :+
        lda xw
:       pha
        ldx xcol
        jsr cell
        pla
        inx
        jsr cell
        ; the part
        inx
        ldy xe
        lda xat
        pha
        lda xcs
        cpy #SWAP
        bne :+
        lda xco
:       cpy #WIRE
        bne :+
        pla
        pha
:       sta xat
        lda glyph,y
        cpy #WIRE
        bne :+
        lda xw
:       ldy _xs
        beq :+
        ldy xe
        cpy #DEAD
        beq @flip
        cpy #AMP
        bne :+
@flip:  eor #G_F3 ^ G_FD        ; on the right the arrows point the other way
:       jsr cell
        pla
        sta xat
        ; the way out
        inx
        ldy xe
        cpy #SWAP
        bne :+
        lda xv
        beq :+
        lda xco
        sta xat
:       lda _out_r,y
        beq :+
        lda xw
:       jsr cell
        lda xcol
        clc
        adc #4
        sta xcol
        lda xi
        clc
        adc #NL
        sta xi
        lda xcol
        cmp #16
        beq :+
        jmp @layer
:       ; the last layer: live as the part before it passes on
        ldx xi
        lda _live,x
        sta xv
        lsr a
        rol xk
        ldy _part - NL,x
        lda _blk
        ldx xv
        beq @dead
        lda xcs
        cpy #SWAP
        bne @dead
        lda xco
@dead:  sta xat
        lda _out_r,y
        beq :+
        lda xw
:       ldx #16
        jsr cell
        inx
        jsr cell
        ldx _xs
        lda base12,x
        clc
        adc _xr
        tax
        lda xk
        sta _drawn,x
        rts

; cell: code A at column X from the left side's rail, colour xat, in the
; line's row of both pictures; X and the code are kept
cell:   pha
        txa
        ldy _xs
        beq :+
        eor #$FF                ; 39 - X
        clc
        adc #40
:       tay
        pla
        sta (pc0),y
        sta (pc1),y
        pha
        lda xat
        sta (pa0),y
        sta (pa1),y
        pla
        rts

; ---------------------------------------------------------------------------
; x_flow: the dashes of live wires move on, towards the column: the wire
; characters turned a pixel, the left one right, the right one left
_x_flow:
        ldx #3
@r:     lda FONT0 + G_F1 * 8,x
        lsr a
        bcc :+
        ora #$80
:       lsr a
        bcc :+
        ora #$80
:       sta FONT0 + G_F1 * 8,x
        sta FONT1 + G_F1 * 8,x
        lda FONT0 + G_F2 * 8,x
        asl a
        adc #0
        asl a
        adc #0
        sta FONT0 + G_F2 * 8,x
        sta FONT1 + G_F2 * 8,x
        inx
        cpx #5
        bne @r
        rts
