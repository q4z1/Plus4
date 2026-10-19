; route.s - finding the ways from a signal to the next
;
; Rail Route searches its network once, depth first, from every signal to
; the next ones, and keeps up to 64 ways to each. Here the network is the
; cells' direction bits, and the search runs when it is needed, from one
; signal: depth first through the cells, a train going on from a cell only
; where the track bends by 45 degrees at most - which is also what makes a
; switch a switch. Only the shortest way to each end is kept.
;
; What route_find leaves: for every place a route from the signal can end,
; the shortest way there, as the directions it leaves each cell in, the
; signal's own cell first. A route ends before the next signal facing the
; same way, or at the end of a track (it takes that cell in). dest_tx /
; dest_ty is where the player points to choose it: the signal it ends
; before, or the end of the track it runs into.
;
; The routes set and not yet taken by a train hold their cells (rt_...),
; and the first train to stand before (or come up to) their signal takes
; them over (train.s).

        .macpack longbranch
        .include "game.inc"

        .export _ndest, _dest_x, _dest_y, _dest_end, _dest_len, _dest_out
        .export _dest_tx, _dest_ty, _dest_dirs
        .export _rt_sig, _rt_len, _rt_out, _rt_end, _rt_dirs
        .export signal_at, platform_at, signal_in, route_find, route_free
        .export route_passes, routes_reset, route_from, route_set
        .export route_cancel, rp_st, rp_pl

        .import cellp, cell_mark, cell_route, cr_a, cr_b, bitv
        .importzp mc, mo
        .import _code_mask, _code_deco, _map_w, _map_h, _step_x, _step_y
        .import _nsig, _sig_x, _sig_y, _sig_dir, _nplat, _pl_station, _pl_num
        .import _pl_x0, _pl_y0, _pl_x1, _pl_y1

        .segment "GAMEZP": zeropage
rp:     .res 2                  ; a way found (dest_dirs)
rq:     .res 2                  ; a route set (rt_dirs)

        .bss
_ndest:     .res 1
_dest_x:    .res MAX_DEST       ; its last cell
_dest_y:    .res MAX_DEST
_dest_end:  .res MAX_DEST       ; 1: at the end of a track
_dest_len:  .res MAX_DEST
_dest_out:  .res MAX_DEST       ; the way out of its last cell
_dest_tx:   .res MAX_DEST
_dest_ty:   .res MAX_DEST
_rt_sig:    .res MAX_ROUTES     ; 255: unused
_rt_len:    .res MAX_ROUTES
_rt_out:    .res MAX_ROUTES
_rt_end:    .res MAX_ROUTES
; the search's stack: per depth the cell, the way in (a), which of the
; three ways on it tries (0-2: a + 3, 4, 5) and the way it went out
sx_:        .res MAX_RLEN
sy_:        .res MAX_RLEN
sa_:        .res MAX_RLEN
sc_:        .res MAX_RLEN
sb_:        .res MAX_RLEN
rf_d:       .res 1              ; its depth
rf_b:       .res 1
rf_x:       .res 1
rf_y:       .res 1
rf_na:      .res 1
rf_m:       .res 1
kp_len:     .res 1              ; keep's way: its length, end cell, kind
kp_x:       .res 1
kp_y:       .res 1
kp_end:     .res 1
rp_st:      .res 1              ; route_passes' station and platform
rp_pl:      .res 1
rw_i:       .res 1
rw_k:       .res 1
rw_x:       .res 1
rw_y:       .res 1
rw_a:       .res 1
rw_r:       .res 1
rw_best:    .res 1
rw_n:       .res 1
rw_len:     .res 1              ; route_free's, route_passes' way's length
pa_x:       .res 1
pa_y:       .res 1
pa_px:      .res 1
pa_py:      .res 1
pa_dx:      .res 1
pa_dy:      .res 1
sh_a:       .res 1
        .segment "HIBSS"        ; the ways found, 768 bytes: above the map
_dest_dirs: .res MAX_DEST * MAX_RLEN
        .segment "LOWBSS"       ; the routes set, 1 KB: in the KERNAL's
_rt_dirs:   .res MAX_ROUTES * MAX_RLEN  ; work area, not used by the game

        .code

; ---- signals and platforms ------------------------------------------------

; signal_at: the signal at X, Y facing A, or 255 (in A)
signal_at:
        sta sh_a
        stx pa_x
        sty pa_y
        ldx #0
@s:     cpx _nsig
        beq @none
        lda _sig_x,x
        cmp pa_x
        bne @no
        lda _sig_y,x
        cmp pa_y
        bne @no
        lda _sig_dir,x
        cmp sh_a
        beq @yes
@no:    inx
        bne @s
@none:  ldx #255
@yes:   txa
        rts

; signal_in: the signal at X, Y whichever way it faces, or 255 (in A)
signal_in:
        stx pa_x
        sty pa_y
        ldx #0
@s:     cpx _nsig
        beq @none
        lda _sig_x,x
        cmp pa_x
        bne @no
        lda _sig_y,x
        cmp pa_y
        beq @yes
@no:    inx
        bne @s
@none:  ldx #255
@yes:   txa
        rts

; platform_at: the platform whose track goes through X, Y, or 255 (in A)
platform_at:
        stx pa_x
        sty pa_y
        ldx #0
@p:     cpx _nplat
        beq @none
        lda _pl_x0,x
        sta pa_px
        lda _pl_y0,x
        sta pa_py
        ldy #0                  ; the step from one end to the other
        lda _pl_x1,x
        cmp pa_px
        beq :++
        bcc :+
        iny
        bne :++
:       dey
:       sty pa_dx
        ldy #0
        lda _pl_y1,x
        cmp pa_py
        beq :++
        bcc :+
        iny
        bne :++
:       dey
:       sty pa_dy
@cell:  lda pa_px
        cmp pa_x
        bne :+
        lda pa_py
        cmp pa_y
        beq @yes
:       lda pa_px
        cmp _pl_x1,x
        bne :+
        lda pa_py
        cmp _pl_y1,x
        jeq @next
:       lda pa_px
        clc
        adc pa_dx
        sta pa_px
        lda pa_py
        clc
        adc pa_dy
        sta pa_py
        jmp @cell
@next:  inx
        bne @p
@none:  ldx #255
@yes:   txa
        rts

; ---- the search -----------------------------------------------------------------

; ddp: rp = way X of the search's (dest_dirs). Keeps X.
ddp:    txa
        lsr a
        lsr a
        sta rp+1
        txa
        asl a
        asl a
        asl a
        asl a
        asl a
        asl a
        clc
        adc #<_dest_dirs
        sta rp
        lda rp+1
        adc #>_dest_dirs
        sta rp+1
        rts

; rdp: rq = route X of the table's (rt_dirs). Keeps X.
rdp:    txa
        lsr a
        lsr a
        sta rq+1
        txa
        asl a
        asl a
        asl a
        asl a
        asl a
        asl a
        clc
        adc #<_rt_dirs
        sta rq
        lda rq+1
        adc #>_rt_dirs
        sta rq+1
        rts

; keep: a way found, of kp_len steps (the search's sb_), to kp_x, kp_y
; (kp_end: at the end of a track), leaving it by rf_b - kept if it goes
; somewhere new, or is shorter than the way kept there
keep:   ldx #0
@find:  cpx _ndest
        beq @new
        lda _dest_x,x
        cmp kp_x
        bne :+
        lda _dest_y,x
        cmp kp_y
        beq @old
:       inx
        bne @find
@new:   cpx #MAX_DEST
        beq @rts
        inc _ndest
        bne @set
@old:   lda kp_len
        cmp _dest_len,x
        bcs @rts
@set:   lda kp_x
        sta _dest_x,x
        lda kp_y
        sta _dest_y,x
        lda kp_end
        sta _dest_end,x
        lda kp_len
        sta _dest_len,x
        lda rf_b
        sta _dest_out,x
        lda kp_end
        beq :+
        lda kp_x
        sta _dest_tx,x
        lda kp_y
        sta _dest_ty,x
        jmp @dirs
:       ldy rf_b
        lda kp_x
        clc
        adc _step_x,y
        sta _dest_tx,x
        lda kp_y
        clc
        adc _step_y,y
        sta _dest_ty,x
@dirs:  jsr ddp
        ldy kp_len
        beq @rts
        dey
:       lda sb_,y
        sta (rp),y
        dey
        bpl :-
@rts:   rts

; route_find: all the ways from the signal at X, Y facing A
route_find:
        stx sx_
        sty sy_
        clc
        adc #4
        and #7
        sta sa_
        lda #0                  ; straight on through the signal only
        sta sc_
        sta _ndest
        sta rf_d
@loop:  ldx rf_d
        lda sc_,x
        cmp #3
        bcs @back
        cpx #0
        bne @try
        cmp #1
        bcc @try
@back:  dec rf_d
        bmi @done
        ldx rf_d
        inc sc_,x
        jmp @loop
@done:  rts
        ; the track bends by 45 degrees at most: out at a + 4, 3 or 5 -
        ; straight on first, so that of two ways as long (a diagonal step
        ; is a step), keep has the straighter: not over two crossovers to
        ; the other track and back
@try:   tay
        lda rf_turn,y
        clc
        adc sa_,x
        and #7
        sta rf_b
        ldy sy_,x
        lda sx_,x
        tax
        jsr cellp
        ldy #0
        lda (mc),y
        tay
        lda _code_mask,y
        ldx rf_b
        and bitv,x
        jeq @next
        ldx rf_d
        cpx #MAX_RLEN - 1
        jcs @next
        ldy rf_b
        lda sx_,x
        clc
        adc _step_x,y
        sta rf_x
        cmp _map_w
        jcs @next
        lda sy_,x
        clc
        adc _step_y,y
        sta rf_y
        cmp _map_h
        jcs @next
        tya
        clc
        adc #4
        and #7
        sta rf_na
        ldx rf_x
        ldy rf_y
        jsr cellp
        ldy #0
        lda (mc),y
        tay
        lda _code_mask,y
        sta rf_m
        ldx rf_na
        and bitv,x
        jeq @next
        ldx rf_d
        lda rf_b
        sta sb_,x
        ; a signal facing the way the train goes ends the route before it
        lda _code_deco,y
        and #DECO_SIGNAL | 7
        sec
        sbc #DECO_SIGNAL
        cmp rf_b
        bne @nosig
        lda rf_d
        sta kp_len
        lda sx_,x
        sta kp_x
        lda sy_,x
        sta kp_y
        lda #0
        sta kp_end
        jsr keep
        jmp @next
@nosig: lda rf_m                ; the end of the track: in it
        sec
        sbc #1
        and rf_m
        bne @on
        inx
        stx kp_len
        lda rf_x
        sta kp_x
        lda rf_y
        sta kp_y
        lda #1
        sta kp_end
        jsr keep
@next:  ldx rf_d
        inc sc_,x
        jmp @loop
@on:    inc rf_d
        ldx rf_d
        lda rf_x
        sta sx_,x
        lda rf_y
        sta sy_,x
        lda rf_na
        sta sa_,x
        lda #0
        sta sc_,x
        jmp @loop

rf_turn: .byte 4, 3, 5

; route_free: every cell of way X is free (the signal's own too): A 1 or 0
route_free:
        jsr ddp
        lda sx_
        sta rw_x
        lda sy_
        sta rw_y
        lda _dest_len,x
        sta rw_len
        lda #0
        sta rw_k
@cell:  ldx rw_x
        ldy rw_y
        jsr cellp
        ldy #0
        lda (mo),y
        bne @taken
        ldy rw_k
        cpy rw_len
        beq @free
        lda (rp),y
        tax
        lda rw_x
        clc
        adc _step_x,x
        sta rw_x
        lda rw_y
        clc
        adc _step_y,x
        sta rw_y
        inc rw_k
        bne @cell
@taken: lda #0
        rts
@free:  lda #1
        rts

; route_passes: way X goes over a platform of station rp_st (any platform
; if rp_pl is 0): A 1; 2 if it is the platform asked for. Not counting the
; signal's own cell: a train stops before it, so a platform ending there is
; one it has left behind.
route_passes:
        jsr ddp
        lda sx_
        sta rw_x
        lda sy_
        sta rw_y
        lda _dest_len,x
        sta rw_len
        lda #0
        sta rw_best
        sta rw_k
        beq @last
@cell:  ldx rw_x
        ldy rw_y
        jsr platform_at
        cmp #255
        beq @last
        tax
        lda _pl_station,x
        cmp rp_st
        bne @last
        lda _pl_num,x
        cmp rp_pl
        beq @two
        lda #1
        sta rw_best
@last:  ldy rw_k
        cpy rw_len
        beq @done
        lda (rp),y
        tax
        lda rw_x
        clc
        adc _step_x,x
        sta rw_x
        lda rw_y
        clc
        adc _step_y,x
        sta rw_y
        inc rw_k
        bne @cell
@done:  lda rw_best
        rts
@two:   lda #2
        rts

; ---- the routes set -------------------------------------------------------------

routes_reset:
        lda #255
        ldx #MAX_ROUTES - 1
:       sta _rt_sig,x
        dex
        bpl :-
        rts

; route_from: the route set from signal A, or 255 (in A)
route_from:
        ldx #0
:       cmp _rt_sig,x
        beq @yes
        inx
        cpx #MAX_ROUTES
        bne :-
        ldx #255
@yes:   txa
        rts

; route_set: way X of the last route_find (from signal A) set: its cells
; taken, the signal green. A the route, or 255 if it is not free, or there
; is no room for another route.
route_set:
        sta rw_a
        stx rw_i
        jsr route_free
        beq @no
        ldx #0
:       lda _rt_sig,x
        cmp #255
        beq :+
        inx
        cpx #MAX_ROUTES
        bne :-
@no:    lda #255
        rts
:       stx rw_r
        lda rw_a
        sta _rt_sig,x
        ldy rw_i
        lda _dest_len,y
        sta _rt_len,x
        lda _dest_out,y
        sta _rt_out,x
        lda _dest_end,y
        sta _rt_end,x
        jsr rdp
        ldx rw_i
        jsr ddp
        ldx rw_a
        lda _sig_x,x
        sta rw_x
        lda _sig_y,x
        sta rw_y
        lda _sig_dir,x
        clc
        adc #4
        and #7
        sta cr_a
        ldx rw_i
        lda _dest_len,x
        sta rw_n
        lda #0
        sta rw_k
@cell:  ldx rw_i
        lda _dest_out,x
        ldy rw_k
        cpy rw_n
        bcs :+
        lda (rp),y
:       sta cr_b
        ldx rw_x
        ldy rw_y
        jsr cell_route
        ldy rw_k
        cpy rw_n
        beq @done
        lda cr_b
        sta (rq),y
        tax
        lda rw_x
        clc
        adc _step_x,x
        sta rw_x
        lda rw_y
        clc
        adc _step_y,x
        sta rw_y
        txa
        clc
        adc #4
        and #7
        sta cr_a
        inc rw_k
        bne @cell
@done:  lda rw_r
        rts

; route_cancel: route X, which no train has taken, given up: its cells free
route_cancel:
        stx rw_r
        jsr rdp
        ldy _rt_sig,x
        lda _sig_x,y
        sta rw_x
        lda _sig_y,y
        sta rw_y
        lda #0
        sta rw_k
@cell:  ldx rw_x
        ldy rw_y
        lda #OCC_FREE
        jsr cell_mark
        ldx rw_r
        ldy rw_k
        tya
        cmp _rt_len,x
        beq @done
        lda (rq),y
        tax
        lda rw_x
        clc
        adc _step_x,x
        sta rw_x
        lda rw_y
        clc
        adc _step_y,x
        sta rw_y
        inc rw_k
        bne @cell
@done:  ldx rw_r
        lda #255
        sta _rt_sig,x
        rts
