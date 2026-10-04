; xfer.s - the transfer game's board: how pulses pass and how a line is
; drawn. transfer.s lays the board out and runs the game; this is what it
; does for every line every tick.
;
; A side has 4 layers of 12 lines, a layer after the other: part[] holds
; the parts (transfer.s), live[] whether each carries a pulse (0 or 1).
; Side 0 is the left, yellow; side 1 the right, purple, drawn mirrored.
;
; The board's part is in the transfer's overlay (XFERCODE, XFERDATA: kept
; packed, unpacked into the pictures' slots by paradroid.s); the letters
; and the droids' pictures (x_letter, x_picture) are always there, for
; the console, the title and a game's end too.

        .include "game.inc"
        .include "data.inc"

        .export _part, _live, _life, _drawn, _xmap
        .export _xs, _xr, _tcol, _blk
        .export _x_pass, _x_line, _x_step, _x_flow, _x_layout
        .export _x_letter, _x_picture, _x_droid, _x_row, _x_col, _x_attr, _x_code
        .import _pal_deck, _pre
        .import _rnd
        .export _out_r

NL      = 12
ROW0    = 12                    ; screen row of the first line

; the parts, as in transfer.s
WIRE    = 0
DEAD    = 1
AMP     = 2
SWAP    = 3
BR_T    = 4
BR_B    = 6
GA_T    = 7
GA_M    = 8
NONE    = 10

G_F1    = POOL + 0              ; the original's characters $F1 on:
G_F2    = POOL + 1              ;   wires left and right,
G_F3    = POOL + 2              ;   arrows pointing left
G_FD    = POOL + 12             ;   and right

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
p_from: .res 2
p_to:   .res 2
p_to2:  .res 2

        .segment "LOWBSS"
; before the board is laid out, transfer.s's introduction uses the same
; bytes as a map of the panel's letters to characters (128 of them)
_xmap:
_part:  .res 2 * 4 * NL
_live:  .res 2 * 4 * NL
_life:  .res 2 * NL             ; ticks a pulse put in has left
_drawn: .res 2 * NL             ; live bits as last drawn

        .bss
_x_row: .res 1                  ; x_letter, x_droid: where, and in what colour
_x_col: .res 1
_x_attr:.res 1
_x_code:.res 1                  ; x_letter: next free character, 2 a letter
_xs:    .res 1                  ; the side and line x_line draws
_xr:    .res 1
_tcol:  .res 2                  ; the sides' colours
_blk:   .res 1                  ; a dead wire's

        .segment "XFERDATA"
; a part passes a pulse on to the right; it takes one from the left; its
; character (the arrows of DEAD and AMP for the left side)
_out_r: .byte 1, 0, 1, 1, 1, 0, 1, 0, 1, 0, 0
in_l:   .byte 1, 1, 1, 1, 0, 1, 0, 1, 0, 1, 0
glyph:  .byte G_F1, G_F3, G_FD, POOL+3, POOL+4, POOL+5, POOL+6
        .byte POOL+4, POOL+5, POOL+6, 0
; how often a part is laid when it is picked, of 101: wire, dead end,
; amplifier, colour changer, branch, gate (FreedroidClassic's)
prob:   .byte 100, 2, 5, 5, 5, 5
base48: .byte 0, 4 * NL
base12: .byte 0, NL
rowlo:  .repeat NL, R
        .byte <((ROW0 + R) * 40)
        .endrepeat
rowhi:  .repeat NL, R
        .byte >((ROW0 + R) * 40)
        .endrepeat

        .segment "XFERCODE"

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

; ---------------------------------------------------------------------------
; x_layout: side A's parts laid out, as FreedroidClassic's InventPlayground
; does: every line wire to begin with, then in layers 1 and 2 each wire
; becomes a part picked at random (and accepted as often as prob says).
; Behind a part that passes nothing on there is nothing. A colour changer
; only goes next to the column. A branch takes three lines, its middle fed
; from the left, and cuts the lines before its ends; a gate takes three,
; fed at its ends, and cuts the line before its middle.
_x_layout:
        tax
        lda base48,x
        sta xp
        tax
        ldy #4 * NL
        lda #WIRE
:       sta _part,x
        inx
        dey
        bne :-
        lda #1
        sta xk                  ; the layer
@layer: lda #0
        sta xn                  ; the line
@row:   jsr @idx
        lda _part,x
        beq :+               ; set already, by a branch or gate
        jmp @next
:
@pick:  jsr _rnd
        and #7
        cmp #6
        bcs @pick
        sta xe
@prob:  jsr _rnd
        and #127
        cmp #101
        bcs @prob
        ldy xe
        cmp prob,y
        beq :+
        bcc :+                ; not this time: pick again
        jmp @row
:       jsr @idx
        ldy _part - NL,x        ; what is before it
        lda xe
        cmp #4
        bcs @three
        cmp #SWAP
        bne :+
        ldy xk
        cpy #2
        beq :+                ; colour changers next to the column only
        jmp @row
:
        ldy _part - NL,x
        lda _out_r,y
        bne :+
        lda #NONE
        sta _part,x
        jmp @next
:       lda xe
        sta _part,x
        jmp @next
@three: lda xn
        cmp #NL - 2
        bcc :+                ; no room
        jmp @row
:
        lda xe
        cmp #4
        bne @gate
        ; a branch: fed in the middle; none next to another's end
        ldy _part - NL + 1,x
        lda _out_r,y
        bne :+
        jmp @row
:
        lda _part - NL,x
        jsr @isend
        bne :+
        jmp @row
:
        lda _part - NL + 2,x
        jsr @isend
        bne :+
        jmp @row
:
        ldy _part - NL,x
        lda _out_r,y
        beq :+
        lda #DEAD
        sta _part - NL,x
:       ldy _part - NL + 2,x
        lda _out_r,y
        beq :+
        lda #DEAD
        sta _part - NL + 2,x
:       lda #BR_T
        bne @set
@gate:  ldy _part - NL,x
        lda _out_r,y
        bne :+
        jmp @row
:
        ldy _part - NL + 2,x
        lda _out_r,y
        bne :+
        jmp @row
:
        ldy _part - NL + 1,x
        lda _out_r,y
        beq :+
        lda #DEAD
        sta _part - NL + 1,x
:       lda #GA_T
@set:   sta _part,x
        clc
        adc #1
        sta _part + 1,x
        adc #1
        sta _part + 2,x
        inc xn
        inc xn
@next:  inc xn
        lda xn
        cmp #NL
        bcs :+
        jmp @row
:       inc xk
        lda xk
        cmp #3
        bcs :+
        jmp @layer
:       rts

; X := the cell of layer xk, line xn
@idx:   lda xk
        asl a
        adc xk                  ; 3 * layer
        asl a
        asl a                   ; 12 * layer
        adc xp
        adc xn
        tax
        rts

; Z set if A is a branch's end
@isend: cmp #BR_T
        beq :+
        cmp #BR_B
:       rts

; ---------------------------------------------------------------------------
; The introduction and the droids on the board (transfer.s): cells written
; into both pictures, characters into picture 1's set or both.

        .code                   ; (always there: x_letter, x_picture)

; row x_row of both pictures into pa0/pc0, pa1/pc1
rowptr: lda #0
        sta pa0 + 1
        lda _x_row
        asl a
        asl a
        adc _x_row              ; 5 * row
        asl a
        rol pa0 + 1
        asl a
        rol pa0 + 1
        asl a                   ; 40 * row
        rol pa0 + 1
        sta pa0
        sta pc0
        sta pa1
        sta pc1
        lda pa0 + 1
        ora #$C0
        sta pa0 + 1
        ora #$04
        sta pc0 + 1
        eor #$C4 ^ $D4
        sta pc1 + 1
        and #$FB
        sta pa1 + 1
        rts

; code A in column Y of the row, colour x_attr; A is kept
put2:   sta (pc0),y
        sta (pc1),y
        pha
        lda _x_attr
        sta (pa0),y
        sta (pa1),y
        pla
        rts

; p_to := address of character A in the set whose high byte is in X
charad: stx p_to + 1
        ldx #0
        stx xco
        asl a
        rol xco
        asl a
        rol xco
        asl a
        rol xco
        sta p_to
        lda xco
        ora p_to + 1
        sta p_to + 1
        rts

; x_letter: the panel's letter A (its top's code) at x_row, x_col, two rows
; high, and x_col moved on. Its two characters are copied to x_code and
; the one after it the first time; xmap remembers where.
_x_letter:
        sta xe
        tay
        lda _xmap,y
        bne @have
        lda _x_code
        sta _xmap,y
        inc _x_code
        inc _x_code
        lda xe                  ; the top
        ldx _xmap,y
        jsr @copy
        lda xe                  ; the bottom, 128 characters on
        ora #$80
        ldx _xmap,y
        inx
        jsr @copy
        lda _xmap,y
@have:  sta xe
        jsr rowptr
        ldy _x_col
        lda xe
        jsr put2
        inc _x_row
        jsr rowptr
        ldy _x_col
        lda xe
        clc
        adc #1
        jsr put2
        dec _x_row
        inc _x_col
        rts

; panel character A to character X of picture 1's set; Y is kept
@copy:  sty xk
        stx xp
        ldx #>PANELF
        jsr charad
        lda p_to
        sta p_from
        lda p_to + 1
        sta p_from + 1
        lda xp
        ldx #>FONT1
        jsr charad
        ldy #7
:       lda (p_from),y
        sta (p_to),y
        dey
        bpl :-
        ldy xk
        rts

; x_picture(lay): a droid's picture, loaded at character 1 of picture 1's
; set; its layout at lay, x_code rows of six cells (0 none, else the
; character, +$80 hires), drawn from row x_row, column x_col, in colour
; x_attr - multicolour unless the cell says hires.
_x_picture:
        sta p_from
        stx p_from + 1
        lda _x_attr
        sta xcs
        ldx #0
        stx xp                  ; index into the layout
@r:     jsr rowptr
        ldy _x_col
        lda #6
        sta xk
@c:     sty xcol
        ldy xp
        lda (p_from),y
        inc xp
        ldy xcol
        tax
        beq @n
        lda xcs
        cpx #$80
        bcs :+
        ora #8                  ; multicolour
:       sta _x_attr
        txa
        and #$7F
        jsr put2
@n:     iny
        dec xk
        bne @c
        inc _x_row
        dec _x_code
        bne @r
        lda xcs
        sta _x_attr
        rts

        .segment "XFERCODE"

; x_droid(slot): a droid's picture from its pre-shifted slot (the first of
; its four positions: columns at 8 + 24 * column) as eight characters
; x_code to x_code + 7 of both sets, 4 wide and 2 high at x_row, x_col
_x_droid:
        asl a                   ; slot * 512, + 8: column 0, line 0
        clc
        adc #>(_pre + 8)
        sta p_from + 1
        lda #<(_pre + 8)
        sta p_from
        lda #0
        sta xk                  ; the column, 0-3
@col:   lda #0
        sta xv                  ; top or bottom
@half:  lda _x_code
        ldx #>FONT0
        jsr charad
        lda p_to
        sta p_to2
        lda p_to + 1
        eor #>FONT0 ^ >FONT1
        sta p_to2 + 1
        lda xk                  ; 24 * column + 8 * half
        asl a
        adc xk
        asl a
        asl a
        asl a
        ldx xv
        beq :+
        adc #8
:       sta xw
        ldx #0
@b:     ldy xw
        lda (p_from),y
        inc xw
        stx xcol
        ldy xcol
        sta (p_to),y
        sta (p_to2),y
        inx
        cpx #8
        bne @b
        lda _x_row
        pha
        clc
        adc xv
        sta _x_row
        jsr rowptr
        pla
        sta _x_row
        lda _x_col
        clc
        adc xk
        tay
        lda _x_code
        jsr put2
        inc _x_code
        inc xv
        lda xv
        cmp #2
        bne @half
        inc xk
        lda xk
        cmp #4
        bne @col
        rts
