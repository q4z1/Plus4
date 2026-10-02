; figs.s - the figures into the window: figure() for one, draw_figs() for
; the droids, their explosions and the shots (draw.c does the window and
; the player)
;
; A figure is at world pixel (fig_x, fig_y), its top left corner, from
; pre-shifted slot fig_n. Against the window (org_x, org_y: its column 0
; and row 0, less 64, from draw.c's window()) it gives the engine's r_fig
; its cell, line and the slot's copy for the pixel it starts at.

        .export _figure, _draw_figs, _explo_col
        .exportzp _fig_x, _fig_y, _fig_n, _org_x, _org_y
        .import _r_fig, _f_col, _f_row, _f_line, _f_tint, _pre
        .importzp _f_pre
        .import _nd, _d_boom, _d_x, _d_y, _d_type, _slot_of
        .import _s_life, _s_img, _s_x, _s_y

SLOT_EXPLO  = 10                ; game.h
SLOT_LASER  = 16
BOOM_GONE   = 13
MAXS        = 8

        .segment "ENGZP": zeropage
_fig_x: .res 2
_fig_y: .res 2
_fig_n: .res 1
_org_x: .res 2
_org_y: .res 2
rx:     .res 2
ry:     .res 1
fh:     .res 1
fi:     .res 1

        .segment "HICODE"       ; (run at $F400 on, paradroid.cfg)

; an explosion's colour by its stage, multicolour: the original's yellow,
; then its orange as it dies down - a red of middle luminance, as cells in
; multicolour can only have the colours 0-7
_explo_col:
        .byte $7F, $7F, $7F, $4A, $4A, $4A

; figure(): the one at fig_x, fig_y from slot fig_n, if it is in the window
_figure:
        sec                     ; relative to the window, plus 64: 0 .. 384
        lda _fig_x
        sbc _org_x
        sta rx
        lda _fig_x+1
        sbc _org_x+1
        sta rx+1
        beq @x
        cmp #1
        bne @out
        lda rx
        cmp #$81
        bcs @out
@x:     sec                     ; and 0 .. 224
        lda _fig_y
        sbc _org_y
        sta ry
        lda _fig_y+1
        sbc _org_y+1
        bne @out
        lda ry
        cmp #225
        bcs @out
        and #7
        sta _f_line
        lda ry
        lsr a
        lsr a
        lsr a
        sec
        sbc #8
        sta _f_row
        lda rx+1
        lsr a
        lda rx
        ror a
        lsr a
        lsr a
        sec
        sbc #8
        sta _f_col
        lda rx                  ; the copy: pre + 512 * fig_n + 64 * (rx & 6)
        and #6
        lsr a
        lsr a
        sta fh
        lda #0
        ror a
        clc
        adc #<_pre
        sta _f_pre
        lda #>_pre
        adc fh                  ; (with the low byte's carry)
        sta fh
        lda _fig_n
        asl a
        clc
        adc fh
        sta _f_pre+1
        jmp _r_fig
@out:   rts

; draw_figs(): the droids (exploding ones in their explosion's colour) and
; the shots
_draw_figs:
        lda #1
        sta fi
@droid: ldx fi
        cpx _nd
        bcs @shots
        lda _d_boom,x
        cmp #BOOM_GONE
        beq @nd
        txa
        asl a
        tay
        sec
        lda _d_x,y
        sbc #13
        sta _fig_x
        lda _d_x+1,y
        sbc #0
        sta _fig_x+1
        sec
        lda _d_y,y
        sbc #8
        sta _fig_y
        lda _d_y+1,y
        sbc #0
        sta _fig_y+1
        lda _d_boom,x
        beq @alive
        sec
        sbc #1
        lsr a
        tay
        clc
        adc #SLOT_EXPLO
        sta _fig_n
        lda _explo_col,y
        sta _f_tint
        jsr _figure
        lda #0
        sta _f_tint
        beq @nd
@alive: ldy _d_type,x
        lda _slot_of,y
        cmp #255
        beq @nd
        sta _fig_n
        jsr _figure
@nd:    inc fi
        jmp @droid
@shots: lda #0
        sta fi
@shot:  ldx fi
        lda _s_life,x
        beq @ns
        txa
        asl a
        tay
        sec
        lda _s_x,y
        sbc #12
        sta _fig_x
        lda _s_x+1,y
        sbc #0
        sta _fig_x+1
        sec
        lda _s_y,y
        sbc #8
        sta _fig_y
        lda _s_y+1,y
        sbc #0
        sta _fig_y+1
        lda _s_img,x
        clc
        adc #SLOT_LASER
        sta _fig_n
        jsr _figure
@ns:    inc fi
        lda fi
        cmp #MAXS
        bne @shot
        rts
