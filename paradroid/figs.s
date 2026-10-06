; figs.s - the figures into the window: figure() for one, draw_figs() for
; the droids, their explosions and the shots (draw.s does the window and
; the player)
;
; A figure is at world pixel (fig_x, fig_y), its top left corner, from
; pre-shifted slot fig_n. Against the window (org_x, org_y: its column 0
; and row 0, less 64, from draw.s's window()) it gives the engine's r_fig
; its cell, line and the slot's copy for the pixel it starts at.

        .export _figure, _draw_figs, _explo_col, _fig_seen
        .exportzp _fig_x, _fig_y, _fig_n, _org_x, _org_y
        .import _r_fig, _f_col, _f_row, _f_line, _f_tint, _pre
        .importzp _f_pre
        .import _nd, _d_boom, _d_x, _d_y, _d_type, _slot_of
        .import _s_life, _s_img, _s_x, _s_y, _d_seen, _s_boom

        .include "game.inc"

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

        .segment "LOWBSS"
_fig_seen: .res 23              ; slots drawn in the window (draw.s's
                                ; turn_droids() turns those)

        .segment "PAGE1"        ; (on page 1, under the stack: sight.s)

; an explosion's colour by its stage, multicolour: the original's yellow,
; then its orange as it dies down - a red of middle luminance, as cells in
; multicolour can only have the colours 0-7
_explo_col:
        .byte $7F, $7F, $7F, $4A, $4A, $4A

        .segment "HICODE"       ; (run at $F100 on, paradroid.cfg)

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
        ldx _fig_n
        inc _fig_seen,x
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
        sec                     ; where the original's sprite is (its
        lda _d_x,y              ; droid's, its explosion's; measured
        sbc #11                 ; against its deck in x64sc)
        sta _fig_x
        lda _d_x+1,y
        sbc #0
        sta _fig_x+1
        sec
        lda _d_y,y
        sbc #11
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
@alive: lda _d_seen,x            ; (behind a wall: sight.s)
        beq @nd
        ldy _d_type,x
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
        ldy _s_life,x           ; (none, or a droid's still hidden: 251 on)
        dey
        cpy #250
        bcs @ns
        txa
        asl a
        tay
        sec                     ; (as the droids': the original's
        lda _s_x,y              ; sprites, the same way from the world)
        sbc #11
        sta _fig_x
        lda _s_x+1,y
        sbc #0
        sta _fig_x+1
        sec
        lda _s_y,y
        sbc #11
        sta _fig_y
        lda _s_y+1,y
        sbc #0
        sta _fig_y+1
        lda _s_boom,x           ; exploding: the droids' explosion
        beq @laser
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
        beq @ns
@laser: lda _s_img,x
        clc
        adc #SLOT_LASER
        sta _fig_n
        jsr _figure
@ns:    inc fi
        lda fi
        cmp #MAXS
        bne @shot
        rts

; (here, above $F000, where there is room)
        .export _panel_frame

; panel_frame(c): the status panel's frame in colour c, as the original
; colours it with the border's: its rows 0, 1, 4 and 5, and in rows 2 and
; 3 the two cells at each end
        .segment "HICODE"
_panel_frame:
        ldx #239
@c:     cpx #80
        bcc @set
        cpx #160
        bcs @set
        pha
        txa
        sbc #80 - 1             ; (carry clear: 80 less)
        cmp #40
        bcc :+
        sbc #40
:       cmp #2
        bcc @end
        cmp #38
        bcs @end
        pla
        bcc @next               ; (always: carry clear from cmp #38)
@end:   pla
@set:   sta SCR0A,x
        sta SCR1A,x
@next:  dex
        cpx #$FF
        bne @c
        rts
