; trainschedule.s - trainschedule, a signal box game for the Commodore Plus/4,
; after Rail Route (bitrich).
;
; The player sets routes from signal to signal; trains come in at the
; edges of the map and run to a timetable. This file has the game's loop,
; the clock, the cursor, the score and the text on screen; the map is
; map.s, the routes route.s, the trains train.s, the title and the disk
; front.s, the Plus/4 engine.s.
;
; Setting a route: the cursor on a signal, fire - the places a route from
; it can go to flash - the cursor on one of them, fire. Fire on a signal
; whose route no train has taken yet takes it back. A route set behind a
; standing train turns it round.
;
; All of it is assembly, to make room, as in Paradroid.

        .macpack longbranch
        .include "game.inc"
        .forceimport __STARTUP__        ; (cc65's start-up: main() is here)

        .export _main, _clock_s, score_event, _loops
        .export _cur_x, _cur_y, _clock_f, _speed_i, _score
        .export _perfect, _msg_time, _ended, _panel_t, _sel_sig, _sel_n
        .export _sel_x, _sel_y, _sel_alt, _clock_txt

        .import level_load, code_kind, code_mc, view_draw, view_cell, set_zoom
        .import bands_make, bd_dirty, cu_bands, _eng_below
        .import cell_screen, view_set, cellp, cf_m, cf_d, cf_mc, cs_o
        .importzp mc, mo, lp
        .import _map_w, _map_h, _code_mask, _code_deco, _zoom
        .import _view_x, _view_y, _view_sx, _view_sy, _view_cw, _view_ch
        .import _sig_x, _sig_y, _sig_dir, _st_name, _lv_name, _lv_start
        .import _lv_ntrains
        .import signal_in, route_find, route_free, route_set, route_from
        .import route_cancel, routes_reset
        .import _ndest, _dest_tx, _dest_ty
        .import trains_reset, trains_step, trains_second, trains_draw
        .import trains_forget, trains_claim, tt_record
        .import tt_mode, tt_visit, train_at, trains_mark, trains_flash, _moved
        .import train_giveback
        .import train_departing
        .import _tt_arr, _tt_plat, _tt_pts, _train_blink, _autopilot_on
        .import ev_why, ev_pts, ev_late, ev_wrong, ev_st, ev_rec
        .import disk_init, title, choose_map, load_map, _level_buf, map_song
        .import catalogue, unlock_next
        .export _test_map
        .import _eng_init, _eng_hits, _eng_hits2, _eng_romfont
        .import _eng_vmbase, _eng_font2, _eng_dark, _eng_show, _eng_text, _txt_o, _txt_col, _frames, _dbg_n
        .import _eng_mode, _title_bg, _title_mc, _title_split, _scrn, _colr
        .import _vput, _vget, _vp_o, _vp_c, _vp_a, _vg_a
        .import _ptr_x, _ptr_y, _ptr_w, _ptr_h, _vorg_x, _vorg_y
        .import _ptr_on, _mus_start
        .import _mc_of, _cursor, _cursor2, _cursor2u, _cu_add, _cu_clear, _cu_forget
        .import _cu_low
        .import _cu_n, _cu_m
        .import _sg_top, _sg_bot, _sg_col, _bg_top, _bg_bot, sign_of, big_of
        .import watch_set, _xs_top, _xs_bot, _wt_top, _wt_bot

SPLIT   = $80                   ; in a message: the rest on the right screen

; screen codes for the text
.repeat 26, I
        .charmap $41 + I, $01 + I
.endrepeat

        .segment "GAMEZP": zeropage
wp:     .res 2                  ; where text is being written
rp2:    .res 2                  ; and read from
gp:     .res 2
dp2:    .res 2
pn_vp:  .res 2                  ; a stop in a train's record

        .bss
_cur_x:     .res 1              ; the cell pointed at
_cur_y:     .res 1
; the clock: seconds since the level's start minute, and 50ths of the
; second running; the game's speed in 50ths of a second per picture
_clock_s:   .res 2
_clock_f:   .res 1
_speed_i:   .res 1
_score:     .res 2
_perfect:   .res 2
_msg_time:  .res 1              ; pictures the message stays
_ended:     .res 1
_loops:     .res 1              ; for measuring: turns of the loop
; choosing where a route goes: from which signal, and the cells to point
; at (they flash), and their kind without the signal's lamp (or the
; end's bar)
_sel_n:     .res 1
_sel_x:     .res MAX_DEST
_sel_y:     .res MAX_DEST
_sel_alt:   .res MAX_DEST
blink:      .res 1              ; 1: the marks are off just now
; a row of text in the making - one for all, none of them makes its row
; while another's is half done (line_blank first)
        .segment "STKBSS"       ; (trainschedule.cfg: not cleared)
line:       .res 41
        .bss
; The clock as the digits on screen, "hh:mm:ss", turned on a second at a
; time like a counter - working it out from the seconds every time costs
; more than all the trains
_clock_txt: .res 9
end_sel:    .res 1              ; the end's choice: 0 again, 1 another map
le_new:     .res 1              ; level_end's: a map unlocked
le_r:       .res 1
nv:         .res 2              ; num's number
nm_d:       .res 1
nm_any:     .res 1
hs:         .res 2              ; hhmm's seconds
hm:         .res 2
hh:         .res 1
tmp:        .res 1
tl_x:       .res 1              ; tall's column, colours, and a text's
tl_top:     .res 1              ; place in big and sign
tl_bot:     .res 1
tl_i:       .res 1
tmp2:       .res 1
bl_n:       .res 1
bl_c:       .res 1
vr_v:       .res 1
vr_hud:     .res 1              ; 1: the head rows anew too (a new zoom)
bd_t:       .res 1              ; board's
bd_r:       .res 1
bd_busy:    .res 1              ; board_step has rows to draw
bd_m:       .res 1
bd_v:       .res 1
bd_col:     .res 1
bd_when:    .res 2
pn_i:       .res 1              ; panel's
pn_n:       .res 1
pn_v:       .res 1
pn_m:       .res 1
pn_r:       .res 1
pn_first:   .res 1
pn_col:     .res 1
pn_pl:      .res 1
pn_pts:     .res 1
pn_at:      .res 2
pn_rec:     .res 2
sv_i:       .res 1              ; sel_show's and others'
sv_k:       .res 1
cu_k:       .res 1              ; cursor_show's
pf_px:      .res 2              ; ptr_follow's
pf_py:      .res 2
pf_cx:      .res 1
pf_cy:      .res 1
pf_vx:      .res 1
pf_vy:      .res 1
pf_m:       .res 1
fi_g:       .res 1              ; fire's
fi_i:       .res 1
fi_r:       .res 1
fi_b:       .res 1              ; a route taken back
le_pc:      .res 2              ; level_end's
le_p:       .res 3
mn_last:    .res 1              ; main's
mn_now:     .res 1
mn_n:       .res 1
mn_hits:    .res 1
mn_k:       .res 1
mn_t:       .res 1
mn_speed:   .res 1
mn_wait:    .res 1
mn_blink:   .res 1
mn_shown:   .res 2
        .segment "STKBSS"       ; (written before it is read)
ev_buf:     .res 64
        .bss
hd_line:    .res 40             ; the head row, as it is when no message
hd_ca:      .res 1              ; is over it: its colours, left and right
hd_cb:      .res 1
pl_row:     .res 1              ; put_half's
pl_col:     .res 1
ph_x:       .res 1
ms_i:       .res 1              ; msg's
ms_y:       .res 1
fd_n:       .res 1              ; frame_draw's
bd_s:       .res 1              ; the board's first train shown (of those
bd_k:       .res 1              ; not gone), and how many still to skip
bd_wait:    .res 1              ; board ticks till the list moves on
bd_max:     .res 1
bc_t:       .res 1              ; bd_count's
bc_n:       .res 1

        .data
; for the test build (tests/start.sh): 0 the title as ever, 1 on straight
; into that map, $FF straight to the choice of a map
_test_map:  .byte 0
_panel_t:   .byte 255           ; a train's timetable in place of the
                                ; board, or 255: the board
_sel_sig:   .byte 255           ; the signal a route is being chosen from

        .rodata
speeds:     .byte 0, 1, 3, 10
tens_lo:    .byte <10000, <1000, <100, <10, <1
tens_hi:    .byte >10000, >1000, >100, >10, >1
; the cursor's places, close up: the cell above's bottom quarters - the
; top corners there, in their lowest lines - and the cell's own; 4 on: its
; own four quarters (no room above it); 8: the overview, the cell itself.
; low: in a bottom quarter, its corners' lines in multicolour, the rest
; hires (engine.s, cu_mixup)
cq_lo:      .byte <-40, <-39, 40, 41,  0, 1, 40, 41,  0
cq_hi:      .byte >-40, >-39, 0, 0,  0, 0, 0, 0,  0
cq_mlo:     .byte <_cursor2u, <(_cursor2u + 8), <(_cursor2 + 16), <(_cursor2 + 24)
            .byte <_cursor2, <(_cursor2 + 8), <(_cursor2 + 16), <(_cursor2 + 24)
            .byte <_cursor
cq_mhi:     .byte >_cursor2u, >(_cursor2u + 8), >(_cursor2 + 16), >(_cursor2 + 24)
            .byte >_cursor2, >(_cursor2 + 8), >(_cursor2 + 16), >(_cursor2 + 24)
            .byte >_cursor
cq_low:     .byte 1, 1, 1, 1,  0, 0, 1, 1,  0
type_lo:    .byte <t_freight, <t_ic, <t_regional, <t_commuter, <t_urban
type_hi:    .byte >t_freight, >t_ic, >t_regional, >t_commuter, >t_urban
t_freight:  .byte "FREIGHT", 0
t_ic:       .byte "INTERCITY", 0
t_regional: .byte "REGIONAL", 0
t_commuter: .byte "COMMUTER", 0
t_urban:    .byte "URBAN", 0
s_score:    .byte "SCORE ", 0
; the frame's sides: their columns, their characters and colours - the
; screens' blue their inner half, the frame's grey the outer
fr_cols:    .byte 0, 19, 20, 39
; board_put's fields: 0 the frame, 1 the number, 2 between, 3 the row, 4
; how it is doing
bp_kind:    .byte 0, 1, 1, 1, 1, 1, 1, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3
            .byte 0, 0, 3, 3, 2, 3, 3, 3, 3, 3, 2, 4, 4, 4, 4, 4, 4, 4, 4, 4, 0
fr_side:    .byte FR_LH | BG_FRAME, FR_LH, FR_LH | BG_FRAME, FR_LH
fr_scol:    .byte COL_FRAME, COL_SCREEN, COL_FRAME, COL_SCREEN
s_head_a:   .byte "TRAIN  NEXT STOP", 0
s_head_b:   .byte "PL TIME", 0
s_arr:      .byte "ARR ", 0
s_leaving:  .byte "LEAVING", 0
s_atstop:   .byte "AT STOP", 0
s_late:     .byte "LATE ", 0
s_ontime:   .byte "ON TIME", 0
s_departing: .byte "DEPARTING", 0
s_cars:     .byte " CARS  ", 0
s_kmh:      .byte " KM/H", 0
s_late2:    .byte " LATE ", 0
s_wrong:    .byte " WRONG PL", 0
s_wrong2:   .byte " WRONG", 0         ; (late too: no room for more)
; messages: the left screen's part, SPLIT, the right one's
s_red:      .byte "STOPPED", SPLIT, "AT A RED SIGNAL", 0
s_braking:  .byte "BRAKING", SPLIT, "FOR A RED SIGNAL", 0
s_notfree:  .byte "THAT ROUTE IS", SPLIT, "NOT FREE", 0
s_back:     .byte "ROUTE TAKEN BACK", 0
s_change:   .byte "ROUTE TAKEN BACK", SPLIT, "OR CHOOSE ANOTHER", 0
s_toolate:  .byte "TOO LATE: THE", SPLIT, "TRAIN CANNOT STOP", 0
s_inuse:    .byte "THE SIGNAL IS", SPLIT, "IN USE", 0
s_noroute:  .byte "NO FREE ROUTE", SPLIT, "FROM HERE", 0
s_where:    .byte "WHERE TO: FIRE ON", SPLIT, "A BLINKING SIGNAL", 0
s_done:     .byte "TIMETABLE DONE", 0
s_of:       .byte " OF ", 0
s_again:    .byte "PLAY AGAIN", 0
s_other:    .byte "OTHER MAP", 0
s_unlocked: .byte "NEXT MAP UNLOCKED", 0

        .code

; ---- text -------------------------------------------------------------------

.macro  ldax addr
        lda #<(addr)
        ldx #>(addr)
.endmacro

.macro  wpat addr
        lda #<(addr)
        sta wp
        lda #>(addr)
        sta wp+1
.endmacro

; txt_at: txt_o = row Y * 40 + column X
txt_at: stx tmp
        lda #0
        sta _txt_o+1
        tya
        asl a
        asl a
        asl a
        sta _txt_o
        asl a
        rol _txt_o+1
        asl a
        rol _txt_o+1
        clc
        adc _txt_o
        bcc :+
        inc _txt_o+1
        clc
:       adc tmp
        sta _txt_o
        bcc :+
        inc _txt_o+1
:       rts

; blank: Y characters from screen offset A/X on spaces (the colours
; stay) - on the board's rows the board's blue spaces; dp2 left there
blank:  sty bl_n
        ldy #32
        cpx #>(BOARD_TOP * 40)
        bcc @sp
        bne :+
        cmp #<(BOARD_TOP * 40)
        bcc @sp
:       ldy #32 | BG_FRAME
@sp:    sty bl_c
        clc
        adc _scrn
        sta dp2
        txa
        adc _scrn+1
        sta dp2+1
        lda bl_c
        ldy #0
:       sta (dp2),y
        iny
        cpy bl_n
        bne :-
        rts

; scat: the text at A/X to wp on; wp left at its 0 (written too)
scat:   sta rp2
        stx rp2+1
        ldy #0
:       lda (rp2),y
        sta (wp),y
        beq :+
        iny
        bne :-
:       tya
        clc
        adc wp
        sta wp
        bcc :+
        inc wp+1
:       rts

; putc: A to wp, on by one
putc:   ldy #0
        sta (wp),y
        inc wp
        bne :+
        inc wp+1
:       rts

; num: the number nv to wp on, without leading zeros, and a 0 after it;
; wp left at the 0
num:    lda #0
        sta nm_any
        ldx #0
@digit: lda #'0'
        sta nm_d
@sub:   lda nv
        cmp tens_lo,x
        lda nv+1
        sbc tens_hi,x
        bcc @out
        lda nv
        sbc tens_lo,x           ; (carry set)
        sta nv
        lda nv+1
        sbc tens_hi,x
        sta nv+1
        inc nm_d
        bne @sub
@out:   lda nm_d
        cmp #'0'
        bne @put
        lda nm_any
        bne @put
        cpx #4
        bne @skip
@put:   lda nm_d
        jsr putc
        lda #1
        sta nm_any
@skip:  inx
        cpx #5
        bne @digit
        lda #0
        tay
        sta (wp),y
        rts

; numa: num of A
numa:   sta nv
        lda #0
        sta nv+1
        jmp num

; two: A < 100 as two digits at wp, wp + 1
two:    ldx #'0'
:       cmp #10
        bcc :+
        sbc #10
        inx
        bne :-
:       ora #'0'
        ldy #1
        sta (wp),y
        txa
        dey
        sta (wp),y
        rts

; hhmm: hh:mm at wp (5 characters, wp kept), of hs seconds after the
; level's start
hhmm:   lda _lv_start
        sta hm
        lda _lv_start+1
        sta hm+1
@ten:   lda hs                  ; ten minutes at a time
        cmp #<600
        lda hs+1
        sbc #>600
        bcc @min
        lda hs+1
        sta hs+1
        lda hs
        sbc #<600
        sta hs
        lda hs+1
        sbc #>600
        sta hs+1
        lda hm
        clc
        adc #10
        sta hm
        bcc @ten
        inc hm+1
        bcs @ten
@min:   lda hs+1
        bne :+
        lda hs
        cmp #60
        bcc @hour
:       lda hs
        sec
        sbc #60
        sta hs
        bcs :+
        dec hs+1
:       inc hm
        bne @min
        inc hm+1
        bne @min
@hour:  lda #0
        sta hh
:       lda hm+1
        bne :+
        lda hm
        cmp #60
        bcc :+++
:       lda hm
        sec
        sbc #60
        sta hm
        bcs :+
        dec hm+1
:       inc hh
        bne :---
:       lda hh
:       cmp #24
        bcc :+
        sbc #24
        bcs :-
:       jsr two
        ldy #2
        lda #':'
        sta (wp),y
        lda wp
        clc
        adc #3
        sta wp
        bcc :+
        inc wp+1
:       lda hm
        jsr two
        lda wp
        sec
        sbc #3
        sta wp
        bcs :+
        dec wp+1
:       rts

; line_blank: line 40 spaces, and its end
line_blank:
        lda #32
        ldx #39
:       sta line,x
        dex
        bpl :-
        lda #0
        sta line+40
        rts

; ---- the board's two screens ------------------------------------------------
; Rows 18-24 are two screens side by side in one grey frame (game.inc
; COL_FRAME): row 18 its top, row 24 its foot with the LED, columns 0, 19,
; 20 and 39 its sides. Each screen is SCR_W characters, from SCR_A and
; SCR_B; row 19 is their head row, rows 20-23 the rest. A row's text is
; made in line at the columns it has on the screen.

; frame_draw: the frame, and the screens blank
frame_draw:
        lda #0
        sta bd_s
        lda #4
        sta bd_wait
        ldx #0
        ldy #18
        jsr txt_at
        jsr row_ptrs
        ldy #39
:       lda #FR_BLOCK
        sta (dp2),y
        lda #COL_FRAME
        sta (wp),y
        dey
        bpl :-
        lda #FR_TL
        iny
        sta (dp2),y
        lda #FR_TR
        ldy #39
        sta (dp2),y
        lda #5
        sta fd_n
@row:   jsr next_row
        ldy #39
:       lda #32 | BG_FRAME
        sta (dp2),y
        lda #COL_HUD
        sta (wp),y
        dey
        bpl :-
        ldx #3
:       ldy fr_cols,x
        lda fr_side,x
        sta (dp2),y
        lda fr_scol,x
        sta (wp),y
        dex
        bpl :-
        dec fd_n
        bne @row
        jsr next_row
        ldy #39
:       lda #32
        sta (dp2),y
        lda #COL_FRAME
        sta (wp),y
        dey
        bpl :-
        ldy #39
        lda #FR_BR
        sta (dp2),y
        lda #COL_BG
        sta (wp),y
        ldy #0
        lda #FR_BL
        sta (dp2),y
        lda #COL_BG
        sta (wp),y
        ldy #38
        lda #FR_LED
        sta (dp2),y
        lda #COL_LED
        sta (wp),y
        lda #0                  ; no head row yet
        sta _msg_time
        jsr line_blank
        lda #COL_HUD
        tax
        jmp put_head

; next_row: dp2, wp a row on
next_row:
        lda dp2
        clc
        adc #40
        sta dp2
        bcc :+
        inc dp2+1
:       lda wp
        clc
        adc #40
        sta wp
        bcc :+
        inc wp+1
:       rts

; row_ptrs: dp2 = the screen at txt_o, wp = its colours
row_ptrs:
        lda _txt_o
        clc
        adc _scrn
        sta dp2
        lda _txt_o+1
        adc _scrn+1
        sta dp2+1
        lda _txt_o
        clc
        adc _colr
        sta wp
        lda _txt_o+1
        adc _colr+1
        sta wp+1
        rts

; put_line: line on both screens, row Y, in colour A - each half at once:
; nothing on screen is ever blank in between (a row cleared and then
; written shows as a flicker when the picture catches it)
put_line:
        sta pl_col
        sty pl_row
        ldx #SCR_A
        jsr put_half
        ldx #SCR_B
; put_half: line's columns X on to row pl_row, the screen there, in pl_col
put_half:
        stx ph_x
        ldy pl_row
        jsr txt_at
        jsr row_ptrs
        ldx ph_x
        ldy #0
:       lda line,x
        bne :+
        lda #32
:       ora #BG_FRAME
        sta (dp2),y
        lda pl_col
        sta (wp),y
        inx
        iny
        cpy #SCR_W
        bne :--
        rts

; put_head: line as the head row, the left screen in colour A, the right in
; X - kept, and shown if no message is over it
put_head:
        sta hd_ca
        stx hd_cb
        ldx #39
:       lda line,x
        sta hd_line,x
        dex
        bpl :-
        lda _msg_time
        beq head_show
        rts

; head_show: the head row as it is kept (a message's time is up)
head_show:
        ldx #39
:       lda hd_line,x
        sta line,x
        dex
        bpl :-
        lda #BOARD_TOP
        sta pl_row
        lda hd_ca
        sta pl_col
        ldx #SCR_A
        jsr put_half
        lda hd_cb
        sta pl_col
        ldx #SCR_B
        jmp put_half

; ---- messages -------------------------------------------------------------------

; msg: the text at A/X over the head row a few seconds, yellow and
; blinking: up to SPLIT on the left screen, the rest on the right
msg:
msg_:   sta rp2
        stx rp2+1
        lda #200
        sta _msg_time
        lda #0
        sta ms_i
        ldx #SCR_A
        jsr msg_at
        ldx #SCR_B
msg_at: ldy #BOARD_TOP
        jsr txt_at
        jsr row_ptrs
        ldy #0
@c:     sty ms_y
        ldy ms_i
        lda (rp2),y
        beq @sp
        cmp #SPLIT
        beq @sp
        inc ms_i
        bne @put
@sp:    lda #32
@put:   ldy ms_y
        ora #BG_FRAME
        sta (dp2),y
        lda #COL_MSG
        sta (wp),y
        iny
        cpy #SCR_W
        bne @c
        ldy ms_i                ; on past the SPLIT (what did not fit too)
@sk:    lda (rp2),y
        beq @end
        iny
        cmp #SPLIT
        bne @sk
@end:   sty ms_i
        rts

; msg_blink: a message on and off with the marks (blink) - by its colours:
; the extended colour mode has no blinking characters of its own
msg_blink:
        lda _msg_time
        beq @rts
        ldx #SCR_A
        ldy #BOARD_TOP
        jsr txt_at
        jsr row_ptrs
        lda #COL_MSG
        ldx blink
        beq :+
        lda #COL_SCREEN
:       ldy #SCR_W - 1
:       sta (wp),y
        dey
        bpl :-
        ldy #SCR_B - SCR_A + SCR_W - 1
:       sta (wp),y
        dey
        cpy #SCR_B - SCR_A - 1
        bne :-
@rts:   rts

clock_set:
        lda #0
        sta hs
        sta hs+1
        wpat _clock_txt
        jsr hhmm
        lda #':'
        sta _clock_txt+5
        lda #'0'
        sta _clock_txt+6
        sta _clock_txt+7
        lda #0
        sta _clock_txt+8
        rts

clock_tick:
        ldx #7
        jsr @up9
        bcc @rts
        ldx #6
        jsr @up5
        bcc @rts
        ldx #4
        jsr @up9
        bcc @rts
        ldx #3
        jsr @up5
        bcc @rts
        lda _clock_txt
        cmp #'2'
        bne :+
        lda _clock_txt+1
        cmp #'3'
        bne :+
        lda #'0'
        sta _clock_txt
        sta _clock_txt+1
        rts
:       ldx #1
        jsr @up9
        bcc @rts
        inc _clock_txt
@rts:   rts
@up9:   lda #'9' + 1            ; digit X on: C set when it went round
        .byte $2C
@up5:   lda #'5' + 1
        sta tmp
        inc _clock_txt,x
        lda _clock_txt,x
        cmp tmp
        bcc :+
        lda #'0'
        sta _clock_txt,x
:       rts

; The top two rows: the map's name on a station sign, the clock and the
; score in the digits of a split-flap board, the speed on a stopwatch, a
; star before the score (signs.s) - all two rows high.

; tall_at: dp2 and gp at the screen's and its colours' first row
tall_at:
        lda _scrn
        sta dp2
        lda _scrn+1
        sta dp2+1
        lda _colr
        sta gp
        lda _colr+1
        sta gp+1
        rts

; tall: a character two rows high at column tl_x of rows 0-1: A the top
; one in tl_top, X the one under it in tl_bot; tl_x on (after tall_at)
tall:   ldy tl_x
        sta (dp2),y
        lda tl_top
        sta (gp),y
        tya
        clc
        adc #40
        tay
        txa
        sta (dp2),y
        lda tl_bot
        sta (gp),y
        inc tl_x
        rts

; big: the text at A/X in flap digits from column tl_x on
big:    sta rp2
        stx rp2+1
        lda #0
        sta tl_i
@ch:    ldy tl_i
        lda (rp2),y
        beq @rts
        jsr big_of
        tay
        ldx _bg_bot,y
        lda _bg_top,y
        jsr tall
        inc tl_i
        bne @ch
@rts:   rts

; sign: the text at A/X (screen codes) on a sign from column tl_x on - the
; plate's ends, between them HUD_NAME letters at most
sign:   sta rp2
        stx rp2+1
        lda #SG_LCAP
        jsr sign1
        lda #0
        sta tl_i
@ch:    ldy tl_i
        cpy #HUD_NAME
        beq @end
        lda (rp2),y
        beq @end
        jsr sign_of
        jsr sign1
        inc tl_i
        bne @ch
@end:   lda #SG_RCAP
sign1:  tay
        ldx _sg_bot,y
        lda _sg_top,y
        jmp tall

hud_clock:
        jsr tall_at
        lda #14
        sta tl_x
        lda #COL_HUD
        sta tl_top
        lda #COL_FLAP
        sta tl_bot
        ldax _clock_txt
        jsr big
        lda _speed_i            ; the speed on the stopwatch's dial, all
        jsr watch_set           ; white, for the small letters on it
        inc tl_x                ; (column 23)
        lda #COL_HUD
        sta tl_bot
        ldx _wt_bot
        lda _wt_top
        jsr tall
        ldx _wt_bot+1
        lda _wt_top+1
        jmp tall

hud_score:
        wpat ev_buf
        lda _score
        sta nv
        lda _score+1
        sta nv+1
        bpl :+
        lda #'-'
        jsr putc
        lda #0
        sec
        sbc nv
        sta nv
        lda #0
        sbc nv+1
        sta nv+1
:       jsr num
        lda #26
        ldx #0
        ldy #14
        jsr blank
        lda #40 + 26
        ldx #0
        ldy #14
        jsr blank
        lda wp                  ; the star and a space before it: at
        sec                     ; 40 - its length - 3
        sbc #<ev_buf
        sta tmp
        lda #40 - 3
        sec
        sbc tmp
        sta tl_x
        jsr tall_at
        lda #COL_HUD
        sta tl_top
        lda #COL_FLAP
        sta tl_bot
        ldx _xs_bot
        lda _xs_top
        jsr tall
        ldx _xs_bot+1
        lda _xs_top+1
        jsr tall
        inc tl_x
        ldax ev_buf
        jmp big

hud:    lda #0
        tax
        ldy #80
        jsr blank
        jsr tall_at
        lda #0
        sta tl_x
        lda _sg_col             ; the sign; without one the name in white
        cmp #COL_PLATE
        beq :+
        lda #COL_HUD
:       sta tl_top
        sta tl_bot
        ldax _lv_name
        jsr sign
        jsr hud_clock
        jmp hud_score

; ---- the departure board ----------------------------------------------------
; The trains of the timetable still to run, four at a time: number, the
; stop it is on its way to (the left screen), its platform, when it is due
; there (or leaves, if it is standing there), and how it is doing (the
; right one). With more than four the list moves on a row every two
; seconds, and back to the top from the end (bd_scroll).

board_head:
        jsr line_blank
        wpat line + SCR_A
        ldax s_head_a
        jsr scat
        wpat line + SCR_B
        ldax s_head_b
        jsr scat
        lda #COL_DB_DIM
        tax
        jmp put_head

; stname: rp2 = the name of station A
stname: asl a
        asl a
        asl a
        asl a
        clc
        adc #<_st_name
        sta rp2
        lda #>_st_name
        adc #0
        sta rp2+1
        rts

; cpname: the name at rp2 to line + X, at most Y characters
cpname: sty tmp
        ldy #0
:       cpy tmp
        beq :+
        lda (rp2),y
        beq :+
        sta line,x
        inx
        iny
        bne :-
:       rts

; board: the departure board afresh, all of it - or the timetable of the
; train looked at (panel)
board:  lda _panel_t
        cmp #255
        jne panel
        jsr board_begin
:       jsr board_step
        lda bd_busy
        bne :-
        rts

; board_tick: the same, once a second in the game - the board a row a turn
; (board_step), so that no turn takes long and the trains run on evenly
board_tick:
        jsr bd_scroll
        lda _panel_t
        cmp #255
        jne panel
board_begin:
        lda bd_s
        sta bd_k
        lda #BOARD_TOP + 1
        sta bd_r
        lda #0
        sta bd_t
        lda #1
        sta bd_busy
        rts

; board_step: the board's next row, if it is being drawn - till the trains
; are through, and the rows left blanked. Not over a train's timetable or
; the end of the level.
board_step:
        lda bd_busy
        beq @rts
        lda _panel_t
        cmp #255
        bne @off
        lda _ended
        beq @train
@off:   lda #0
        sta bd_busy
@rts:   rts
@train: lda bd_t
        cmp _lv_ntrains
        jeq @rest
        lda bd_r
        cmp #BOARD_TOP + 5
        jeq @rest
        lda bd_t
        jsr tt_mode
        sta bd_m
        cmp #TT_GONE
        jeq @next
        lda bd_k                ; (above the list's part shown)
        beq :+
        dec bd_k
        jmp @next
:
        lda bd_t
        jsr tt_visit
        sta bd_v
        lda bd_t
        jsr tt_record
        sta pn_rec
        stx pn_rec+1
        jsr line_blank
        lda pn_rec
        sta rp2
        lda pn_rec+1
        sta rp2+1
        ldy #TR_NUM_N - 1
:       lda (rp2),y
        sta line + SCR_A,y
        dey
        bpl :-
        lda #COL_HUD
        sta bd_col
        ldy #TR_NV
        lda bd_v
        cmp (rp2),y
        bcc @stop
        wpat line + 8
        ldax s_leaving
        jsr scat
        jmp @put
@stop:  asl a                   ; vp = p + TR_VISITS + v * 6
        adc bd_v
        asl a
        adc #TR_VISITS
        clc
        adc pn_rec
        sta pn_vp
        lda pn_rec+1
        adc #0
        sta pn_vp+1
        ldy #0
        lda (pn_vp),y
        sec
        sbc #1
        jsr stname
        ldx #8
        ldy #11
        jsr cpname
        ldy #1
        lda (pn_vp),y
        clc
        adc #'0'
        sta line+21
        ldy #2                  ; when: its arrival, or its departure
        lda bd_m
        cmp #TT_STOP
        bne :+
        ldy #4
:       lda (pn_vp),y
        sta bd_when
        sta hs
        iny
        lda (pn_vp),y
        sta bd_when+1
        sta hs+1
        wpat line + 24
        jsr hhmm
        wpat line + 30
        lda bd_m
        cmp #TT_STOP
        bne :+
        ldax s_atstop
        jsr scat
        lda #COL_GOOD
        sta bd_col
        bne @put
:       lda bd_when             ; clock_s > when + 59?
        clc
        adc #59
        sta nv
        lda bd_when+1
        adc #0
        sta nv+1
        lda nv
        cmp _clock_s
        lda nv+1
        sbc _clock_s+1
        bcs @ontime
        ldax s_late
        jsr scat
        lda _clock_s            ; (clock_s - when) / 60
        sec
        sbc bd_when
        sta hs
        lda _clock_s+1
        sbc bd_when+1
        sta hs+1
        jsr div60
        jsr num
        lda #COL_LATE
        sta bd_col
        bne @put
@ontime:
        lda bd_m
        cmp #TT_WAIT
        bne :+
        lda #0
        tay
        sta (wp),y
        lda #COL_DB_DIM
        sta bd_col
        bne @put
:       lda bd_t                ; on time: setting off, or on its way
        jsr train_departing
        bcc :+
        ldax s_departing
        jsr scat
        lda #COL_GOOD
        sta bd_col
        bne @put
:       ldax s_ontime
        jsr scat
@put:   ldx #0                  ; the text's end a space again
:       lda line,x
        beq :+
        inx
        bne :-
:       lda #32
        sta line,x
        lda #0
        sta line+40
        jsr board_put
        inc bd_r
        inc bd_t
        rts
@next:  inc bd_t
        jmp @train
@rest:  lda bd_r
        cmp #BOARD_TOP + 5
        beq @done
        jsr line_blank
        ldy bd_r
        lda #COL_DB_DIM
        jsr put_line
        inc bd_r
        bne @rest
@done:  lda #0
        sta bd_busy
        rts

; board_put: line as row bd_r of the board, in bd_col - as a DB board
; shows a train: its row in the lighter blue, cut into fields by the
; board's own between them, its number dark on white, and how late it
; is, if it is, on white too (bp_kind). Each character with its colour,
; the row in one go (nothing seen half written); the frame left as it is
board_put:
        ldx #0
        ldy bd_r
        jsr txt_at
        jsr row_ptrs
        ldy #39
@ch:    ldx bp_kind,y
        beq @next
        lda line,y
        bne :+
        lda #32
:       dex
        beq @white
        dex
        beq @gap
        dex
        beq @band
        ldx bd_col              ; how late: on white
        cpx #COL_LATE
        bne @band
        ldx #COL_DB_LATE
        ora #BG_WHITE
        bne @put
@white: ldx #COL_DB_ON
        ora #BG_WHITE
        bne @put
@gap:   ora #BG_FRAME
        bne @put
@band:  ldx bd_col
        ora #BG_BAND
@put:   sta (dp2),y
        txa
        sta (wp),y
@next:  dey
        bpl @ch
        rts

; bd_scroll, once a second: the list a row on, if it is longer than the
; screens: two seconds a row, four at the top and at the end
bd_scroll:
        jsr bd_count
        sec
        sbc #4
        beq :+
        bcs :++
:       lda #0
        sta bd_s
        lda #4
        sta bd_wait
        rts
:       sta bd_max
        cmp bd_s                ; (fewer than it was)
        bcs :+
        sta bd_s
:       dec bd_wait
        bne @rts
        lda bd_s
        cmp bd_max
        bcs @top
        inc bd_s
        ldx #2
        lda bd_s
        cmp bd_max
        bne :+
        ldx #4
:       stx bd_wait
@rts:   rts
@top:   lda #0
        sta bd_s
        lda #4
        sta bd_wait
        rts

; bd_count: the trains not gone yet, in A
bd_count:
        lda #0
        sta bc_t
        sta bc_n
:       lda bc_t
        cmp _lv_ntrains
        beq :+
        jsr tt_mode
        inc bc_t
        cmp #TT_GONE
        beq :-
        inc bc_n
        bne :-
:       lda bc_n
        rts

; div60: nv = hs / 60
div60:  lda #0
        sta nv
        sta nv+1
@sub:   lda hs
        cmp #60
        lda hs+1
        sbc #0
        bcc @rts
        lda hs
        sbc #60
        sta hs
        bcs :+
        dec hs+1
:       inc nv
        bne @sub
        inc nv+1
        jmp @sub
@rts:   rts

; ---- a train's timetable ------------------------------------------------------
; As Rail Route shows it when a train is clicked: every stop with its
; platform and the times it is to arrive and leave; for the stops made, when
; it came and what that scored. The stop it is on its way to has a '>'.

panel:  lda _panel_t
        jsr tt_record
        sta pn_rec
        stx pn_rec+1
        sta rp2
        stx rp2+1
        ldy #TR_NV
        lda (rp2),y
        sta pn_n
        lda _panel_t
        jsr tt_visit
        sta pn_v
        lda _panel_t
        jsr tt_mode
        sta pn_m
        jsr line_blank
        lda pn_rec
        sta rp2
        lda pn_rec+1
        sta rp2+1
        ldy #TR_NUM_N - 1
:       lda (rp2),y
        sta line + SCR_A,y
        dey
        bpl :-
        wpat line + SCR_A + TR_NUM_N + 1
        ldy #TR_TYPE
        lda (rp2),y
        tay
        lda type_lo,y
        ldx type_hi,y
        jsr scat
        wpat line + SCR_B
        lda pn_rec
        sta rp2
        lda pn_rec+1
        sta rp2+1
        ldy #TR_CARS
        lda (rp2),y
        jsr numa
        ldax s_cars
        jsr scat
        lda pn_rec
        sta rp2
        lda pn_rec+1
        sta rp2+1
        ldy #TR_KMH
        lda (rp2),y
        jsr numa
        ldax s_kmh
        jsr scat
        lda #COL_HUD
        tax
        jsr put_head
        ; four stops at a time: from the one before the next on
        lda #0
        sta pn_first
        lda pn_n
        cmp #5
        bcc :++
        lda pn_v
        cmp #2
        bcc :++
        sec
        sbc #1                  ; v - 1 > n - 4 ? n - 4 : v - 1
        sta pn_first
        lda pn_n
        sec
        sbc #4
        cmp pn_first
        bcs :+
        sta pn_first
:
:       lda #BOARD_TOP + 1
        sta pn_r
        lda pn_first
        sta pn_i
@stop:  lda pn_i
        cmp pn_n
        jcs @rest
        lda pn_r
        cmp #BOARD_TOP + 5
        jeq @rest
        lda pn_i                ; vp = rec + TR_VISITS + i * 6
        asl a
        adc pn_i
        asl a
        adc #TR_VISITS
        clc
        adc pn_rec
        sta pn_vp
        lda pn_rec+1
        adc #0
        sta pn_vp+1
        jsr line_blank
        lda pn_i
        cmp pn_v
        bne :+
        lda pn_m
        cmp #TT_GONE
        beq :+
        lda #'>'
        sta line + SCR_A
:       ldy #0
        lda (pn_vp),y
        sec
        sbc #1
        jsr stname
        ldx #SCR_A + 1
        ldy #11
        jsr cpname
        ldy #1
        lda (pn_vp),y
        sta pn_pl
        lda #COL_DB_DIM
        sta pn_col
        lda #$FF                ; at: when it came, $FFFF: not yet
        sta pn_at
        sta pn_at+1
        lda pn_i
        cmp #MAX_VISITS
        bcs :+
        lda _panel_t            ; tt_..[panel_t][i]
        asl a
        asl a
        asl a
        adc pn_i
        sta tmp
        asl a
        tax
        lda #0
        rol a
        sta tmp2
        txa
        clc
        adc #<_tt_arr
        sta rp2
        lda tmp2
        adc #>_tt_arr
        sta rp2+1
        ldy #0
        lda (rp2),y
        sta pn_at
        iny
        lda (rp2),y
        sta pn_at+1
:       lda pn_at
        and pn_at+1
        cmp #$FF
        beq @notyet
        ldx tmp
        lda _tt_plat,x
        sta pn_pl
        lda _tt_pts,x
        sta pn_pts
        ldy #COL_GOOD           ; 10: good, 5 on: white, else late
        cmp #10
        beq :++
        ldy #COL_HUD
        sec
        sbc #5
        bvc :+
        eor #$80
:       bpl :+
        ldy #COL_LATE
:       sty pn_col
        jmp @line
@notyet:
        lda pn_i
        cmp pn_v
        bne @line
        lda #COL_HUD
        sta pn_col
@line:  lda pn_pl
        clc
        adc #'0'
        sta line+14
        lda pn_at               ; the right screen: when it came, and
        and pn_at+1             ; what that scored; or the times it is
        cmp #$FF                ; to come and go
        bne @came
        ldy #2
        lda (pn_vp),y
        sta hs
        iny
        lda (pn_vp),y
        sta hs+1
        wpat line + SCR_B
        jsr hhmm
        lda #'-'
        sta line + SCR_B + 5
        ldy #4
        lda (pn_vp),y
        sta hs
        iny
        lda (pn_vp),y
        sta hs+1
        wpat line + SCR_B + 6
        jsr hhmm
        jmp @put
@came:  wpat line + SCR_B
        ldax s_arr
        jsr scat
        lda pn_at
        sta hs
        lda pn_at+1
        sta hs+1
        jsr hhmm
        wpat line + SCR_B + 13
        lda pn_pts
        bpl :+
        lda #'-'
        jsr putc
        lda #0
        sec
        sbc pn_pts
        jmp :++
:       lda #'+'
        jsr putc
        lda pn_pts
:       jsr numa
@put:   ldy pn_r
        lda pn_col
        jsr put_line
        inc pn_i
        inc pn_r
        jmp @stop
@rest:  jsr line_blank
:       lda pn_r
        cmp #BOARD_TOP + 5
        beq :+
        tay
        lda #COL_DB_DIM
        jsr put_line
        inc pn_r
        bne :-
:       rts

; panel_open: train A's timetable in place of the board
panel_open:
        sta _panel_t
        jsr trains_mark
        jmp panel

panel_close:
        lda #255
        sta _panel_t
        jsr trains_mark
        jsr board_head
        jmp board

; ---- the score ----------------------------------------------------------------

; score_event: what the trains tell the score (train.s): ev_why (EV_...),
; ev_pts, the train's record ev_rec, its station ev_st, ev_late, ev_wrong
score_event:
        lda ev_pts
        clc
        adc _score
        sta _score
        lda ev_pts
        and #$80                ; (its sign)
        beq :+
        lda #$FF
:       adc _score+1
        sta _score+1
        jsr hud_score
        lda ev_rec
        sta rp2
        lda ev_rec+1
        sta rp2+1
        ldy #TR_NUM_N - 1
:       lda (rp2),y
        sta ev_buf,y
        dey
        bpl :-
        wpat ev_buf + TR_NUM_N         ; arriving: the train and where, SPLIT,
        lda #32                 ; the points, how late, the wrong platform;
        jsr putc                ; else the train, the points, SPLIT, the
        lda ev_why              ; red signal
        cmp #EV_ARRIVE
        bne @red
        lda ev_st
        jsr stname
        lda rp2
        ldx rp2+1
        jsr scat
        lda #SPLIT
        jsr putc
        jsr ev_points
        lda ev_late
        beq :+
        ldax s_late2
        jsr scat
        lda ev_late
        jsr numa
:       lda ev_wrong
        beq @msg
        ldax s_wrong
        ldy ev_late
        beq :+
        ldax s_wrong2
:       jsr scat
        jmp @msg
@red:   jsr ev_points
        lda #32
        jsr putc
        lda ev_why
        cmp #EV_RED
        bne :+
        ldax s_red
        jsr scat
        jmp @msg
:       ldax s_braking
        jsr scat
@msg:   ldax ev_buf
        jmp msg

; ev_points: ev_pts, with its sign, to wp on
ev_points:
        lda ev_pts
        bmi :+
        lda #'+'
        jsr putc
        lda ev_pts
        jmp numa
:       lda #'-'
        jsr putc
        lda #0
        sec
        sbc ev_pts
        jmp numa

; ---- the cursor ----------------------------------------------------------------

; The places to choose from blink - only their marks, the red lamp of the
; signal a route would end before (or the bar where the track ends): the
; cell is drawn as the kind without it every other moment. (Not with the
; TED's flash bit: it does nothing once multicolour is on, which the
; cursor needs.)
sel_show:
        lda #0
        sta sv_i
@sel:   ldx sv_i
        cpx _sel_n
        beq @done
        ldy _sel_y,x
        lda _sel_x,x
        tax
        lda blink
        bne @alt
        jsr view_cell
        jmp @next
@alt:   jsr cellp               ; the other kind, just for drawing
        ldy #0
        lda (mc),y
        sta sv_k
        ldx sv_i
        lda _sel_alt,x
        sta (mc),y
        ldy _sel_y,x
        lda _sel_x,x
        tax
        jsr view_cell
        ldx sv_i
        ldy _sel_y,x
        lda _sel_x,x
        tax
        jsr cellp
        lda sv_k
        ldy #0
        sta (mc),y
@next:  inc sv_i
        bne @sel
@done:  rts

; unmarked: the kind of cell X, Y without its mark (A)
unmarked:
        jsr cellp
        ldy #0
        lda (mc),y
        tax
        lda _code_mask,x
        sta cf_m
        lda code_mc,x           ; in the mode it is in
        sta cf_mc
        lda _code_deco,x
        tay
        and #DECO_SIGNAL
        beq :+
        tya
        and #<~(DECO_SIGNAL | 7)
        jmp :++
:       tya
        and #<~DECO_END
:       sta cf_d
        jmp code_kind

sel_clear:
        lda #0
        sta sv_i
:       ldx sv_i
        cpx _sel_n
        beq :+
        ldy _sel_y,x
        lda _sel_x,x
        tax
        jsr view_cell
        inc sv_i
        bne :-
:       lda #0
        sta _sel_n
        lda #255
        sta _sel_sig
        rts

; the cursor: the corners of the cell over what is there (engine.s, cu_add)
cursor_show:
        lda _cu_n
        bne @done               ; (shown already)
        ldx _cur_x
        ldy _cur_y
        jsr cell_screen
        lda cs_o
        ora cs_o+1
        beq @done
        ldx #0                  ; close up: its places (cq_), their top
        lda _zoom               ; corners in the cell above if that is in
        cmp #1                  ; view (4 on: in the cell's own top
        bne :+                  ; quarters)
        ldx #8                  ; the overview: one place
        bne @set
:       lda cs_o+1
        bne @set
        lda cs_o
        cmp #3 * 40
        bcs @set
        ldx #4
@set:   stx cu_k
@q:     ldx cu_k
        lda cs_o
        clc
        adc cq_lo,x
        sta _vp_o
        lda cs_o+1
        adc cq_hi,x
        sta _vp_o+1
        lda cq_mlo,x
        sta _cu_m
        lda cq_mhi,x
        sta _cu_m+1
        lda cq_low,x
        sta _cu_low
        jsr _cu_add
        inc cu_k
        lda cu_k
        and #3
        beq :+
        lda cu_k
        cmp #9
        bne @q
:       jmp cu_bands            ; its bands (map.s)
@done:  rts

cursor_hide:
        jsr _cu_clear
        jmp cu_bands

; div3: A / 3
div3:   ldx #0
:       cmp #3
        bcc :+
        sbc #3
        inx
        bne :-
:       txa
        rts

; where the pointer's tip is now (the interrupt moves it), and what that
; means: the frame round its cell, and the view moved on a third of itself
; when that cell is at its edge
ptr_follow:
        sei
        lda _ptr_x
        sta pf_px
        lda _ptr_x+1
        sta pf_px+1
        lda _ptr_y
        sta pf_py
        lda _ptr_y+1
        sta pf_py+1
        cli
        ldx #3
        lda _zoom
        cmp #1
        beq :+
        inx
:       lsr pf_px+1
        ror pf_px
        lsr pf_py+1
        ror pf_py
        dex
        bne :-
        lda pf_px
        sta pf_cx
        lda pf_py
        sta pf_cy
        cmp _cur_y
        bne :+
        lda pf_cx
        cmp _cur_x
        bne :+
        rts
:       jsr _eng_below          ; the old frame gone and the new one there
        jsr cursor_hide         ; below the map: no picture with half of
                                ; each, and its bands by the blank
        lda pf_cx
        sta _cur_x
        lda pf_cy
        sta _cur_y
        lda _view_x
        sta pf_vx
        lda _view_y
        sta pf_vy
        lda _view_cw
        jsr div3
        sta pf_m
        lda pf_vx               ; cx < vx + 1: vx = cx > m ? cx - m : 0
        cmp pf_cx
        bcc @right
        lda pf_cx
        sec
        sbc pf_m
        beq :+
        bcs :++
:       lda #0
:       sta pf_vx
        jmp @y
@right: lda pf_cx               ; cx + 2 > vx + view_cw:
        clc                     ; vx = cx + m + 1 - view_cw
        adc #2
        sta tmp
        lda #0
        rol a
        sta tmp2
        lda pf_vx
        clc
        adc _view_cw
        sta nv
        lda #0
        rol a
        sta nv+1
        lda nv
        cmp tmp
        lda nv+1
        sbc tmp2
        bcs @y
        lda pf_cx
        clc
        adc pf_m
        sec
        adc #0                  ; (+ 1)
        sec
        sbc _view_cw
        sta pf_vx
@y:     lda _view_ch
        jsr div3
        sta pf_m
        lda pf_vy
        cmp pf_cy
        bcc @down
        lda pf_cy
        sec
        sbc pf_m
        beq :+
        bcs :++
:       lda #0
:       sta pf_vy
        jmp @set
@down:  lda pf_cy
        clc
        adc #2
        sta tmp
        lda #0
        rol a
        sta tmp2
        lda pf_vy
        clc
        adc _view_ch
        sta nv
        lda #0
        rol a
        sta nv+1
        lda nv
        cmp tmp
        lda nv+1
        sbc tmp2
        bcs @set
        lda pf_cy
        clc
        adc pf_m
        sec
        adc #0
        sec
        sbc _view_ch
        sta pf_vy
@set:   lda _view_x
        sta tmp
        lda _view_y
        sta tmp2
        ldx pf_vx
        ldy pf_vy
        jsr view_set
        lda _view_x
        cmp tmp
        bne :+
        lda _view_y
        cmp tmp2
        bne :+
        jmp cursor_show
:       jmp view_redraw

; the pointer's view of the map: where its pixel 0, 0 is on screen, and
; how far it goes
ptr_frame:
        sei
        lda _view_sx            ; vorg_x = view_sx * 8 - view_x * cs
        jsr times8
        sta _vorg_x
        stx _vorg_x+1
        lda _view_x
        jsr timescs
        lda _vorg_x
        sec
        sbc nv
        sta _vorg_x
        lda _vorg_x+1
        sbc nv+1
        sta _vorg_x+1
        lda _view_sy            ; vorg_y = (VIEW_TOP + view_sy) * 8
        clc                     ;          - view_y * cs
        adc #VIEW_TOP
        jsr times8
        sta _vorg_y
        stx _vorg_y+1
        lda _view_y
        jsr timescs
        lda _vorg_y
        sec
        sbc nv
        sta _vorg_y
        lda _vorg_y+1
        sbc nv+1
        sta _vorg_y+1
        lda _map_w              ; ptr_w = map_w * cs, ptr_h likewise
        jsr timescs
        lda nv
        sta _ptr_w
        lda nv+1
        sta _ptr_w+1
        lda _map_h
        jsr timescs
        lda nv
        sta _ptr_h
        lda nv+1
        sta _ptr_h+1
        cli
        rts

; times8: A * 8 in A/X; timescs: A * zoom * 8 in nv
times8: ldx #0
        stx tmp2
        asl a
        rol tmp2
        asl a
        rol tmp2
        asl a
        rol tmp2
        ldx tmp2
        rts
timescs:
        jsr times8
        sta nv
        stx nv+1
        lda _zoom
        cmp #1
        beq :+
        asl nv
        rol nv+1
:       rts

; the view drawn afresh, out of sight: on the screen not shown, which is
; shown when it is done - no picture of a half-drawn map
view_redraw:
        jsr _cu_forget          ; the cursor stays on the old screen: nothing
                                ; drawn now goes under it
        lda _colr+1
        cmp #$08
        bne :+
        lda #$F4                ; s, c: the other screen
        ldx #$F0
        ldy #$F0
        bne :++
:       lda #$0C
        ldx #$08
        ldy #$08
:       sty vr_v
        sta wp+1                ; the top two lines and everything below
        stx dp2+1               ; the map; the map is drawn anew
        lda _scrn+1
        sta rp2+1
        lda _colr+1
        sta gp+1
        lda #0
        sta wp
        sta dp2
        sta rp2
        sta gp
        ldy #79
:       lda (rp2),y
        sta (wp),y
        lda (gp),y
        sta (dp2),y
        dey
        bpl :-
        lda #<(18 * 40)
        sta wp
        sta dp2
        sta rp2
        sta gp
        lda #>(18 * 40)
        clc
        adc wp+1
        sta wp+1
        lda #>(18 * 40)
        clc
        adc dp2+1
        sta dp2+1
        lda #>(18 * 40)
        clc
        adc rp2+1
        sta rp2+1
        lda #>(18 * 40)
        clc
        adc gp+1
        sta gp+1
        ldy #0
:       lda (rp2),y             ; 7 rows: 280 bytes, 256 and 24
        sta (wp),y
        lda (gp),y
        sta (dp2),y
        iny
        bne :-
        inc wp+1
        inc dp2+1
        inc rp2+1
        inc gp+1
        ldy #23
:       lda (rp2),y
        sta (wp),y
        lda (gp),y
        sta (dp2),y
        dey
        bpl :-
        lda wp+1
        sec
        sbc #>(18 * 40) + 1
        sta _scrn+1
        lda dp2+1
        sec
        sbc #>(18 * 40) + 1
        sta _colr+1
        lda vr_hud              ; a new zoom, new characters for the sign:
        beq :+                  ; the map's name drawn again
        lda #0
        sta vr_hud
        jsr hud
:       jsr view_draw
        jsr trains_forget
        jsr trains_draw
        jsr sel_show
        jsr cursor_show
        jsr ptr_frame
        jsr bands_make          ; (its bands from the first picture on)
        lda vr_v
        jmp _eng_vmbase

; the view with the cursor in the middle
view_centre:
        lda _view_cw
        lsr a
        sta tmp
        lda _cur_x
        sec
        sbc tmp
        beq :+
        bcs :++
:       lda #0
:       tax
        lda _view_ch
        lsr a
        sta tmp
        lda _cur_y
        sec
        sbc tmp
        beq :+
        bcs :++
:       lda #0
:       tay
        jsr view_set
        jmp view_redraw

; Z: close up or the overview. The characters change with it: the old view
; stays up in a copy of them (the cursor, too, where it is) while they and
; the new view are made out of sight, and both come in one vertical blank.
zoom_switch:
        sei
        lda _zoom
        cmp #1
        bne :+
        asl _ptr_x
        rol _ptr_x+1
        asl _ptr_y
        rol _ptr_y+1
        jmp :++
:       lsr _ptr_x+1
        ror _ptr_x
        lsr _ptr_y+1
        ror _ptr_y
:       cli
        jsr _eng_font2
        lda _zoom
        eor #3                  ; 1 <-> 2
        jsr set_zoom
        lda #1
        sta vr_hud
        jmp view_centre

; fire: choose a signal, choose where its route goes, take a route back
; (a train's too, if it can still stop) and choose another, or say what
; train is under the cursor
fire:   ldx _cur_x
        ldy _cur_y
        jsr signal_in
        sta fi_g
        lda _sel_sig
        cmp #255
        beq @signal
        ldx #0                  ; one of the places to choose?
:       cpx _sel_n
        beq @not
        lda _sel_x,x
        cmp _cur_x
        bne @no
        lda _sel_y,x
        cmp _cur_y
        beq @chosen
@no:    inx
        bne :-
@chosen:
        lda _sel_sig
        sta fi_g
        jsr sel_clear
        ldy fi_g
        ldx _sig_x,y
        lda _sig_dir,y
        pha
        lda _sig_y,y
        tay
        pla
        jsr route_find
        ldx #0
:       cpx _ndest
        beq @notfree
        lda _dest_tx,x
        cmp _cur_x
        bne :+
        lda _dest_ty,x
        cmp _cur_y
        beq :++
:       inx
        bne :--
:       lda fi_g
        jsr route_set
        cmp #255
        beq @notfree
        jmp trains_claim
@notfree:
        ldax s_notfree
        jmp msg_
@not:   lda _sel_sig
        sta fi_r
        jsr sel_clear
        lda fi_g
        cmp #255
        jeq @rts
        cmp fi_r
        jeq @rts
@signal:
        lda fi_g
        cmp #255
        jeq @train
        ldx #0
        stx fi_b
        jsr route_from
        cmp #255
        beq :+
        tax
        jsr route_cancel
        jmp @back
:       lda fi_g
        jsr train_giveback
        beq @find
        cmp #1
        beq @back
        ldax s_toolate
        jmp msg_
@back:  inc fi_b
@find:  ldy fi_g
        ldx _sig_x,y
        lda _sig_dir,y
        pha
        lda _sig_y,y
        tay
        pla
        jsr route_find
        lda #0
        sta _sel_n
        sta fi_i
@dest:  ldx fi_i
        cpx _ndest
        beq @dests
        jsr route_free
        beq @nd
        ldx fi_i
        ldy _sel_n
        lda _dest_tx,x
        sta _sel_x,y
        lda _dest_ty,x
        sta _sel_y,y
        ldy _dest_ty,x
        lda _dest_tx,x
        tax
        jsr unmarked
        ldy _sel_n
        sta _sel_alt,y
        inc _sel_n
@nd:    inc fi_i
        bne @dest
@dests: lda _sel_n
        bne :+++
        lda fi_b
        beq :+
        ldax s_back
        jmp msg_
:       ldx _cur_x
        ldy _cur_y
        jsr cellp
        ldy #0
        lda (mo),y
        beq :+
        ldax s_inuse
        jmp msg_
:       ldax s_noroute
        jmp msg_
:       lda fi_g
        sta _sel_sig
        jsr sel_show
        ldax s_where
        ldy fi_b
        beq :+
        ldax s_change
:       jmp msg_
@train: ldx _cur_x
        ldy _cur_y
        jsr train_at
        cmp #255
        beq :+
        jmp panel_open
:       lda _panel_t
        cmp #255
        beq @rts
        jmp panel_close
@rts:   rts

; ---- the game ----------------------------------------------------------------

; level_start: the level from the start. The screen is dark while it is
; made - its characters, the head row, the board, the map - and comes on
; with all of it there
level_start:
        jsr _eng_dark
        lda #<_level_buf
        sta lp
        lda #>_level_buf
        sta lp+1
        jsr level_load
        lda #0
        sta _clock_s
        sta _clock_s+1
        sta _clock_f
        sta _score
        sta _score+1
        sta _ended
        sta _sel_n
        lda #255
        sta _sel_sig
        jsr clock_set
        lda _map_w
        lsr a
        sta _cur_x
        lda _map_h
        lsr a
        sta _cur_y
        sei                     ; the pointer in the middle of its cell
        lda _cur_x
        jsr ptrpos
        sta _ptr_x
        stx _ptr_x+1
        lda _cur_y
        jsr ptrpos
        sta _ptr_y
        stx _ptr_y+1
        cli
        ldx #1                  ; (none in the tests: it moves when the
        lda _dbg_n              ; interrupt comes)
        beq :+
        dex
:       stx _ptr_on
        lda #255
        sta _panel_t
        jsr routes_reset
        jsr trains_reset
        lda #0
        sta _perfect
        sta _perfect+1
        sta mn_t
:       lda mn_t
        cmp _lv_ntrains
        beq :+
        jsr tt_record
        sta rp2
        stx rp2+1
        ldy #TR_NV
        lda (rp2),y
        asl a                   ; 10 a stop
        sta tmp
        asl a
        asl a
        adc tmp
        clc
        adc _perfect
        sta _perfect
        bcc :++
        inc _perfect+1
        bcs :++
:       jmp @done
:       inc mn_t
        bne :---
@done:  jsr hud
        jsr frame_draw
        jsr board_head
        jsr board
        jsr view_centre
        jsr _eng_show
        lda map_song            ; the map's music, which came with it
        beq :+
        lda #<SONG_BUF
        ldx #>SONG_BUF
        jmp _mus_start
:       rts

; ptrpos: (A * 8 + 4) * zoom in A/X
ptrpos: jsr times8
        ora #4
        sta nv
        stx nv+1
        lda _zoom
        cmp #1
        beq :+
        asl nv
        rol nv+1
:       lda nv
        ldx nv+1
        rts

; the timetable is through: the score, and stars as Rail Route gives them,
; at 70, 90 and 100 per cent of all there was to get
level_end:
        lda #1
        sta _ended
        lda #255
        sta _panel_t
        jsr trains_mark
        lda #BOARD_TOP + 1      ; the screens: the score on the left, what
        sta le_r                ; next on the right
:       jsr line_blank
        ldy le_r
        lda #COL_DB_DIM
        jsr put_line
        inc le_r
        lda le_r
        cmp #BOARD_TOP + 5
        bne :-
        ; pc = score <= 0 || !perfect ? 0 : score * 100 / perfect
        lda #0
        sta le_pc
        sta le_pc+1
        lda _score+1
        jmi @pc
        ora _score
        beq @pc
        lda _perfect
        ora _perfect+1
        beq @pc
        lda #0                  ; le_p = score * 100 (24 bits)
        sta le_p
        sta le_p+1
        sta le_p+2
        ldx #100
:       lda le_p
        clc
        adc _score
        sta le_p
        lda le_p+1
        adc _score+1
        sta le_p+1
        bcc :+
        inc le_p+2
:       dex
        bne :--
        ldx #24                 ; / perfect
        lda #0
        sta tmp
        sta tmp2
@div:   asl le_p
        rol le_p+1
        rol le_p+2
        rol tmp
        rol tmp2
        lda tmp
        cmp _perfect
        lda tmp2
        sbc _perfect+1
        bcc :+
        lda tmp
        sbc _perfect
        sta tmp
        lda tmp2
        sbc _perfect+1
        sta tmp2
        inc le_p
:       dex
        bne @div
        lda le_p
        sta le_pc
        lda le_p+1
        sta le_pc+1
@pc:    jsr line_blank
        wpat line + SCR_A
        ldax s_score
        jsr scat
        lda _score
        ldx _score+1
        bpl :+
        lda #0
        tax
:       sta nv
        stx nv+1
        jsr num
        ldax s_of
        jsr scat
        lda _perfect
        sta nv
        lda _perfect+1
        sta nv+1
        jsr num
        ldy #BOARD_TOP + 1
        lda #COL_HUD
        jsr put_line
        jsr line_blank
        wpat line + SCR_A
        lda le_pc
        sta nv
        lda le_pc+1
        sta nv+1
        jsr num
        lda #'%'
        jsr putc
        lda #BOARD_TOP + 2
        sta pl_row
        lda #COL_HUD
        sta pl_col
        ldx #SCR_A
        jsr put_half
        ; the stars
        ldy #0                  ; pc >= 100: 3, >= 90: 2, >= 70: 1
        lda le_pc+1
        bne @three
        lda le_pc
        cmp #70
        bcc @stars
        iny
        cmp #90
        bcc @stars
        iny
        cmp #100
        bcc @stars
@three: ldy #3
@stars: lda #0                  ; a star opens the next map
        sta le_new
        tya
        beq :+
        pha
        jsr unlock_next
        rol le_new
        pla
        tay
:       jsr line_blank
        ldx #SCR_A
:       dey
        bmi :+
        lda #'*'
        sta line,x
        inx
        inx
        bne :-
:       lda #BOARD_TOP + 3
        sta pl_row
        lda #$77
        sta pl_col
        ldx #SCR_A
        jsr put_half
        jsr line_blank          ; the head: done, and a map unlocked
        wpat line + SCR_A
        ldax s_done
        jsr scat
        lda le_new
        beq :+
        wpat line + SCR_B
        ldax s_unlocked
        jsr scat
:       lda #COL_HUD
        ldx #COL_GOOD
        jsr put_head
        lda #0
        sta end_sel
        ; the end's choice: the level again, or the next; left and right
        ; choose, fire takes it
end_choice:
        lda #COL_HUD
        sta pl_col
        jsr line_blank
        wpat line + SCR_B + 1
        ldax s_again
        jsr scat
        lda end_sel
        jsr ec_mark
        lda #BOARD_TOP + 2
        jsr ec_put
        jsr line_blank
        wpat line + SCR_B + 1
        ldax s_other
        jsr scat
        lda end_sel
        eor #1
        jsr ec_mark
        lda #BOARD_TOP + 3
ec_put: sta pl_row
        ldx #SCR_B
        jmp put_half
; ec_mark: the '>' before it if A is 0
ec_mark:
        bne :+
        lda #'>'
        sta line + SCR_B
:       rts

_main:  lda $FF06
        and #$20
        beq @text
        ; the boot program has the title picture up: it stays
        lda #1
        sta _eng_mode
        lda $0800 + 1000
        sta _title_bg
        lda $0800 + 1001
        sta _title_mc
        lda $0800 + 1002
        asl a
        asl a
        asl a
        clc
        adc #3
        sta _title_split
        jmp @go
@text:  ldx #0
:       lda #32
        sta $0C00,x
        sta $0D00,x
        sta $0E00,x
        sta $0F00-24,x
        lda #COL_BG
        sta $0800,x
        sta $0900,x
        sta $0A00,x
        sta $0B00-24,x
        inx
        bne :-
        jsr _eng_romfont
@go:    jsr disk_init
        jsr _eng_init
        lda #1
        sta _speed_i
        lda _test_map           ; the test build (tests/start.sh): straight
        beq @title              ; into a map, or to the choice of one
        bmi @choose
        pha
        jsr catalogue
        pla
        jmp @load
@title: jsr title
@choose:
        jsr choose_map
@load:  jsr load_map
        jsr level_start
        lda _frames
        ldx _dbg_n              ; (the tests count from 0)
        beq :+
        lda #0
:       sta mn_last
        lda #$FF
        sta mn_shown
        sta mn_shown+1

@loop:  lda bd_dirty             ; the bands of set switches (map.s)
        beq :+
        jsr bands_make
:       lda _frames
        ldx _dbg_n              ; (the tests' pictures are counted, not
        beq :+                  ; waited for)
        txa
        clc
        adc mn_last
:       sta mn_now
        inc _loops
        sec
        sbc mn_last
        cmp #5
        bcc :+
        lda #4
:       sta mn_n
        lda mn_now
        sta mn_last
        jsr _eng_hits
        sta mn_hits
        lda _ended
        beq @play
        lda mn_hits
        and #K_LEFT | K_RIGHT | K_UP | K_DOWN
        beq :+
        lda end_sel
        eor #1
        sta end_sel
        jsr end_choice
:       lda mn_hits
        and #K_LEVEL
        beq :+
        lda #1
        sta end_sel
:       lda mn_hits
        and #K_FIRE | K_LEVEL
        beq @loop
        lda end_sel
        beq :+
        jsr choose_map
        jsr load_map
:       jsr level_start
        jmp @loop

        ; commands: the keys, or fire held with a direction (engine.s): up
        ; the other size, down the next train's timetable, left slower,
        ; right faster
@play:  jsr _eng_hits2
        sta mn_k
        and #1 | 16
        beq :+
        jsr cursor_hide
        jsr zoom_switch
        ; , and . page through the trains' timetables, Esc closes; fire and
        ; down goes on through them, and back to the board after the last
:       lda mn_k
        and #2 | 4 | 32
        beq @esc
        lda _lv_ntrains
        beq @esc
        lda mn_k
        and #4 | 32
        beq @prev
        ldx _panel_t
        inx                     ; 255 + 1: 0
        cpx _lv_ntrains
        bcc @open
        bcs @close
@prev:  ldx _panel_t
        cpx #255
        beq :+
        txa
        bne :++
:       ldx _lv_ntrains
:       dex
@open:  txa
        jsr panel_open
        jmp @esc
@close: jsr panel_close
@esc:   lda mn_k
        and #8
        beq :+
        lda _panel_t
        cmp #255
        beq :+
        jsr panel_close
:       lda mn_k
        bpl :+
        lda mn_hits
        ora #K_FAST
        sta mn_hits
:       lda mn_k
        and #64
        beq :+
        lda mn_hits
        ora #K_SLOW
        sta mn_hits
:       lda mn_hits
        and #K_FAST
        beq :+
        lda _speed_i
        cmp #3
        bcs :+
        inc _speed_i
:       lda mn_hits
        and #K_SLOW
        beq :+
        lda _speed_i
        beq :+
        dec _speed_i
:       lda mn_hits
        and #K_FIRE
        beq :+
        jsr cursor_hide
        jsr fire
        jsr cursor_show
:       jsr ptr_follow

        ; the game runs on by 50ths of a second: one step for all the
        ; pictures since the last, times the game's speed
        ldx _speed_i
        lda speeds,x
        ldx mn_n
        sta tmp
        lda #0
:       dex
        bmi :+
        clc
        adc tmp
        bne :-                  ; (0: the speed is 0)
:       sta mn_k
        cmp #0
        beq @drawn
        jsr trains_step
        lda _clock_f
        clc
        adc mn_k
        sta _clock_f
:       lda _clock_f
        cmp #50
        bcc @drawn
        sbc #50
        sta _clock_f
        inc _clock_s
        bne :+
        inc _clock_s+1
:       jsr clock_tick
        jsr trains_second
        jmp :--
@drawn: lda _moved
        beq :+
        jsr trains_draw
        jsr sel_show
        ; the marks blink, and the train whose timetable is open
:       lda mn_now
        eor mn_blink
        and #16
        beq @msg
        lda mn_now
        sta mn_blink
        and #16
        beq :+
        lda #1
:       sta blink
        sta _train_blink
        jsr msg_blink
        jsr trains_flash        ; (the trains setting off)
        lda _sel_n
        beq :+
        jsr sel_show
:       lda _panel_t
        cmp #255
        beq @msg
        jsr trains_mark
        ; while a route's end is to be chosen, the line says so
@msg:   lda _sel_sig
        cmp #255
        beq :+
        lda _msg_time
        cmp #20
        bcs :+
        ldax s_where
        jsr msg_
:       lda _msg_time
        beq @clock
        sec
        sbc mn_n
        beq :+
        bcs :++
:       lda #0
:       sta _msg_time
        bne @clock
        jsr head_show
        ; the clock when it shows something new; the board once a second of
        ; real time at most - it is not cheap
@clock: jsr board_step
        lda _clock_s
        cmp mn_shown
        bne :+
        lda _clock_s+1
        cmp mn_shown+1
        bne :+
        lda _speed_i
        cmp mn_speed
        beq :++
:       lda _speed_i
        sta mn_speed
        jsr hud_clock
:       lda mn_wait
        sec
        sbc mn_n
        beq :+
        bcs :++
:       lda #0
:       sta mn_wait
        lda _clock_s
        cmp mn_shown
        bne :+
        lda _clock_s+1
        cmp mn_shown+1
        beq @wait
:       lda mn_wait
        bne @wait
        lda _clock_s
        sta mn_shown
        lda _clock_s+1
        sta mn_shown+1
        lda #50
        sta mn_wait
        jsr board_tick
        lda _lv_ntrains
        beq @wait
        lda #0
        sta mn_t
:       lda mn_t
        cmp _lv_ntrains
        beq :+
        jsr tt_mode
        cmp #TT_GONE
        bne @wait
        inc mn_t
        bne :-
:       jsr level_end
@wait:  lda _dbg_n
        jne @loop
:       lda _frames
        cmp mn_now
        beq :-
        jmp @loop
