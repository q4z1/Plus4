; train.s - trains: coming in, running, braking, stopping, turning, going
;
; A train knows the cells it is on and the cells it may run on (its
; authority, the routes set for it): a ring of entries, each a cell with
; the way the train comes into it and goes out of it. Its front is a
; position in the front cell, in 256ths of a cell; its length the same
; (40 m a vehicle, a cell being 96 m, as in Rail Route).
;
; Speeds are 4096ths of a 256th of a cell per 50th of a second; Rail
; Route's 1 m/s^2 to speed up and 1.61 m/s^2 to brake are 4 and 7 of
; those per step. A train brakes when its braking distance reaches what
; is left of its authority, or the point where it is to stop at a
; platform: with its middle at the platform's.
;
; The player sets routes on the map (route.s); a train takes over those in
; front of it as it comes up to their signals (claim). An autopilot can
; set them instead, the way a player would.
;
; The slot being worked on is s; its ring is at rxp, ryp, rap, rbp (the
; cells, the ways in and out), its words at index s2 = s * 2.

        .macpack longbranch
        .include "game.inc"

        .export _tt_arr, _tt_plat, _tt_pts, _train_marked, _train_blink
        .export _autopilot_on, _tt_state, _tt_slot
        .export _r_state, _r_tt, _r_visit, _r_v, _r_acc, _r_vmax, _r_len
        .export _r_rem, _r_head, _r_sub, _r_tail, _r_end, _r_exit, _r_halt
        .export _r_moved, _r_sigstop, _r_brk, _r_platahead, _r_until
        .export _r_col, _r_pix, _r_dirty, _moved, _brake
        .export trains_reset, trains_step, trains_second, trains_draw
        .export trains_forget, trains_claim, tt_record
        .export tt_mode, tt_visit, train_at, trains_mark, trains_flash
        .export train_departing, train_giveback
        .export ev_why, ev_pts, ev_late, ev_wrong, ev_st, ev_rec

        .import cellp, cell_mark, cell_route, cell_under, cr_a, cr_b, bitv
        .import vc_keep
        .importzp mc, ma, mo
        .import signal_at, platform_at, route_find, route_free
        .import route_passes, route_from, route_set, rp_st, rp_pl
        .import _ndest, _dest_end, _dest_len
        .import _rt_sig, _rt_len, _rt_out, _rt_end, _rt_dirs
        .import _code_mask, _code_deco, _map_w, _map_h, _step_x, _step_y
        .import _sig_x, _sig_y, _sig_dir, _nplat, _pl_station, _pl_num
        .import _pl_x0, _pl_y0, _pl_x1, _pl_y1, _nportal, _portal_x
        .import _portal_y, _lv_trains, _lv_ntrains, _q4, _q_deco, _pool_first, _zoom
        .import _view_x, _view_y, _view_sx, _view_sy, _view_cw, _view_ch
        .import _scr_row
        .import _eng_tcell, _tc_a, _tc_ae, _tc_am, _tc_b, _tc_be, _tc_bm
        .import _tc_col, _tc_x, _tc_y, _tc_o, _tc_base, _tc_nc, _tc_cp
        .import _tc_lead
        .import _fl, _fl_n, _dl_n, _dl_lim, _tc_short
        .import _pool_end
        .import _dl_lo, _dl_hi, _dl_code, _dl_x, _dl_y, _dl_q
        .import _vput, _vget, _vp_o, _vp_c, _vp_a, _eng_below
        .import _clock_s, score_event
        .import _eng_sfx, _sfx_arrive, _sfx_leave

SLOTS   = 8                     ; trains on the map at a time
RING    = 64
OUT     = 255                   ; x of a cell outside the map
ACCEL   = 4                     ; (trains_step: 4 k)
DECEL   = 7                     ; (and 7 k)
MARGIN  = 24                    ; stop this far before a red signal
FAR     = $F000
CAR     = 107                   ; a car's length, in 256ths of a cell
V_GOING = 20 * 61               ; under way, setting off: 20 km/h

; the timetable's states
T_WAIT  = 0
T_ON    = 1
T_GONE  = 2
; the slots'
S_FREE  = 0
S_RUN   = 1                     ; under way, or stopped at a red signal
S_DWELL = 2                     ; standing at a platform
AP_LEAD = 20                    ; the autopilot's routes on from a stop: so
                                ; many seconds before it may leave at most

        .segment "GAMEZP": zeropage
rxp:    .res 2                  ; slot s's ring: the cells' x,
ryp:    .res 2                  ; y,
rap:    .res 2                  ; the ways in,
rbp:    .res 2                  ; and out
vp:     .res 2                  ; a train's record, or one of its stops
tq:     .res 2

        .bss
; the timetable: per train of the level where its data is, and what it is
; doing
tt_dlo:     .res MAX_TRAINS
tt_dhi:     .res MAX_TRAINS
_tt_state:  .res MAX_TRAINS
_tt_slot:   .res MAX_TRAINS
; what happened at each stop, for the train's timetable on screen: when it
; came ($FFFF: not yet), on which platform, what it scored
_tt_arr:    .res MAX_TRAINS * MAX_VISITS * 2
_tt_plat:   .res MAX_TRAINS * MAX_VISITS
_tt_pts:    .res MAX_TRAINS * MAX_VISITS
_train_blink: .res 1            ; the train marked is white just now
_autopilot_on: .res 1
; the trains on the map
_r_state:   .res SLOTS
_r_tt:      .res SLOTS
_r_visit:   .res SLOTS
_r_v:       .res SLOTS * 2
_r_acc:     .res SLOTS * 2
_r_vmax:    .res SLOTS * 2
_r_len:     .res SLOTS * 2
_r_rem:     .res SLOTS * 2      ; left to the stop
_r_head:    .res SLOTS
_r_sub:     .res SLOTS
_r_tail:    .res SLOTS
_r_end:     .res SLOTS
_r_exit:    .res SLOTS          ; its authority leaves the map
_r_halt:    .res SLOTS          ; stopped, and looked why
_r_moved:   .res SLOTS          ; has moved since it stopped
_r_leave:   .res SLOTS          ; its dwell is over: heard when it moves
_r_flash:   .res SLOTS          ; whistled, not yet under way: it blinks
_r_hid:     .res SLOTS          ; at its platform: its authority looks free
_r_hide:    .res SLOTS          ; up to this entry
_r_sigstop: .res SLOTS          ; its stop is a red signal
_r_brk:     .res SLOTS          ; braking for it, and fined
_r_platahead: .res SLOTS        ; its next stop is in its authority
_r_until:   .res SLOTS * 2      ; dwell till this second
_r_col:     .res SLOTS
_r_pix:     .res SLOTS          ; where its front was drawn, in steps
_r_dirty:   .res SLOTS          ; to be drawn again
_r_bank:    .res SLOTS          ; the half of its draw list on screen
_moved:     .res 1              ; something to draw
fq:         .res 256            ; characters given up, free next time
fq_n:       .res 1
fl_first:   .res 1              ; the pool the free list was made for
fl_end:     .res 1
fq_hold:    .res 1              ; fq kept back a turn
dl_cnt:     .res SLOTS * 2      ; the entries in each half of the draw list
s:          .res 1              ; the slot being worked on
s2:         .res 1
ap_turn:    .res 1
pu_x:       .res 1              ; push's entry
pu_y:       .res 1
pu_a:       .res 1
pu_b:       .res 1
ro_x:       .res 1
ro_y:       .res 1
ro_a:       .res 1
ro_b:       .res 1
ro_m:       .res 1
ro_t:       .res 1
sp_head:    .res 2              ; stop_point's
sp_target:  .res 2
sp_sig:     .res 2
sp_a:       .res 2
sp_b:       .res 2
sp_i:       .res 1
sp_st:      .res 1
sp_first:   .res 1
sp_last:    .res 1
sp_found:   .res 1
ev_why:     .res 1              ; event's
ev_pts:     .res 1
ev_late:    .res 1
ev_wrong:   .res 1
ev_st:      .res 1
ev_rec:     .res 2
ar_p:       .res 1              ; arrive's
ar_arr:     .res 2
ar_dep:     .res 2
ar_t:       .res 2
sw_t:       .res 1              ; spawn's
sw_pl:      .res 1
sw_k:       .res 1
sw_x:       .res 1
sw_y:       .res 1
sw_d:       .res 1
sw_n:       .res 1
sw_v:       .res 2
tk_r:       .res 1              ; take's
tk_k:       .res 1
tk_x:       .res 1
tk_y:       .res 1
fs_d:       .res 1
fs_x:       .res 1
fs_y:       .res 1
fs_k:       .res 1
rv_i:       .res 1              ; reverse's
rv_j:       .res 1
rv_k:       .res 1
rv_t:       .res 1
hd_k:       .res 1              ; hide_ahead's, show_ahead's
hd_x:       .res 1
hd_y:       .res 1
gb_s:       .res 1              ; train_giveback's
gb_k:       .res 1
gb_x:       .res 1
gb_y:       .res 1
gb_a:       .res 1
gb_d:       .res 2
cl_g:       .res 1              ; claim's
cl_got:     .res 1
pk_g:       .res 1              ; pick's
pk_v:       .res 1
pk_i:       .res 1
pk_best:    .res 1
pk_top:     .res 1
pk_st:      .res 1
pk_sc:      .res 1
ap_g:       .res 1              ; autopilot's
ap_v:       .res 1
ap_t:       .res 2
st_k:       .res 1              ; trains_step's
st_k4:      .res 2
st_k7:      .res 2
st_v:       .res 2
st_rem:     .res 2
st_acc:     .res 2
st_h:       .res 2
st_d:       .res 1
st_j:       .res 1
st_i:       .res 1
ps_t:       .res 1
ts_t:       .res 1              ; trains_second's
ts_when:    .res 2
td_k:       .res 1              ; trains_draw's
td_i:       .res 1
td_x:       .res 1
td_y:       .res 1
td_sh:      .res 1
td_n:       .res 1
td_step:    .res 1
td_left:    .res 2
td_gl:      .res 2
td_lo:      .res 2
td_hi:      .res 2
td_t:       .res 2
td_h:       .res 1
td_end:     .res 1
td_nc:      .res 1
td_col:     .res SLOTS          ; each train's colour, and drawn just now
td_did:     .res SLOTS
ml_a:       .res 1
ml_r:       .res 2

        .segment "RINGS"        ; the rings, 2 KB: above the map
rx:         .res SLOTS * RING
ry:         .res SLOTS * RING
ra:         .res SLOTS * RING
rb:         .res SLOTS * RING

        .data
_train_marked: .byte 255        ; this train blinks on the map

        .rodata
; braking distance by speed / 128: ((t + 1) * 128)^2 / 57344
_brake:     .repeat 96, T
            .word (2 * (T + 1) * (T + 1)) / 7
            .endrepeat
; freight, intercity, regional, commuter, urban: colours 0-7 only
type_col:   .byte $42, $61, $53, $77, $54

        .code

; ---- slots, records, small things ---------------------------------------------

; use_slot: slot X is the one worked on: s, s2, its ring
use_slot:
        stx s
        txa
        asl a
        sta s2
        txa
        lsr a
        lsr a
        clc
        adc #>rx
        sta rxp+1
        adc #>(ry - rx)
        sta ryp+1
        adc #>(ra - ry)
        sta rap+1
        adc #>(rb - ra)
        sta rbp+1
        txa
        and #3
        lsr a
        ror a
        ror a                   ; (s & 3) * 64
        sta rxp
        sta ryp
        sta rap
        sta rbp
        rts

; recp: vp = the record of slot s's train
recp:   ldx s
        ldy _r_tt,x
        lda tt_dlo,y
        sta vp
        lda tt_dhi,y
        sta vp+1
        rts

; visitp: vp = stop A of slot s's train (its station + 1, platform, arrival,
; departure)
visitp: sta ml_a
        asl a
        adc ml_a
        asl a
        adc #TR_VISITS
        sta ml_a
        jsr recp
        lda vp
        clc
        adc ml_a
        sta vp
        bcc :+
        inc vp+1
:       rts

; stops: the number of stops of slot s's train, in A
stops:  jsr recp
        ldy #TR_NV
        lda (vp),y
        rts

; mul8: ml_r = A * X
mul8:   sta ml_a
        lda #0
        sta ml_r
        sta ml_r+1
        cpx #0
        beq @done
@add:   lda ml_r
        clc
        adc ml_a
        sta ml_r
        bcc :+
        inc ml_r+1
:       dex
        bne @add
@done:  rts

; pos: the position of the start of entry A from the start of the tail's
; entry: its high byte, in A (the low byte is 0)
.macro  pos
        sec
        ldx s
        sbc _r_tail,x
.endmacro

; ---- the map's side -------------------------------------------------------------

; push: a cell at the end of the authority: pu_x, pu_y, in pu_a, out pu_b
push:   ldx s
        inc _r_end,x
        lda _r_end,x
        and #RING - 1
        tay
        lda pu_x
        sta (rxp),y
        lda pu_y
        sta (ryp),y
        lda pu_a
        sta (rap),y
        lda pu_b
        sta (rbp),y
        lda pu_x
        cmp #OUT
        beq @rts
        lda pu_a
        sta cr_a
        lda pu_b
        sta cr_b
        ldx pu_x
        ldy pu_y
        jmp cell_route
@rts:   rts

; run_on: from the end of the authority, on to the next signal facing the
; way the train goes (not into it), as long as the track does not fork and
; is free. A 1 if it got there, the end of the track included.
run_on:
@loop:  ldx s
        lda _r_end,x
        and #RING - 1
        tay
        lda (rbp),y
        sta ro_b
        tax
        lda (rxp),y
        clc
        adc _step_x,x
        sta ro_x
        cmp _map_w
        bcs @yes
        lda (ryp),y
        clc
        adc _step_y,x
        sta ro_y
        cmp _map_h
        bcs @yes
        ldx ro_x
        ldy ro_y
        jsr cellp
        ldy #0
        lda (mc),y
        tax
        lda _code_mask,x
        sta ro_m
        lda _code_deco,x
        sta ro_t
        lda ro_b
        clc
        adc #4
        and #7
        sta ro_a
        tax
        lda ro_m
        and bitv,x
        beq @yes                ; the track ends here
        lda ro_t
        and #DECO_SIGNAL | 7
        sec
        sbc #DECO_SIGNAL
        cmp ro_b
        beq @yes
        lda (mo),y
        bne @no
        ldy #3                  ; the one way on
@k:     tya
        clc
        adc ro_a
        and #7
        tax
        lda ro_m
        and bitv,x
        bne @way
        iny
        cpy #6
        bne @k
        jsr @push               ; the end of the line
        ldx s
        lda #1
        sta _r_exit,x
@yes:   lda #1
        rts
@no:    lda #0
        rts
@way:   stx pu_b
        jsr @push1
        jmp @loop
@push:  lda ro_b
        sta pu_b
@push1: lda ro_x
        sta pu_x
        lda ro_y
        sta pu_y
        lda ro_a
        sta pu_a
        jmp push

; ---- where to stop --------------------------------------------------------------

; stop_point: r_rem afresh: to the end of the authority, or to the platform
; of the next stop if it is on the way
stop_point:
        ldx s
        lda #0
        sta sp_found
        lda _r_head,x           ; head = pos(r_head) + r_sub
        pos
        sta sp_head+1
        ldx s
        lda _r_sub,x
        sta sp_head
        lda _r_end,x            ; pos(r_end + 1) - MARGIN
        clc
        adc #1
        pos
        sta sp_sig+1
        lda #0
        sec
        sbc #MARGIN
        sta sp_sig
        bcs :+
        dec sp_sig+1
:       ldx s
        lda _r_exit,x
        beq :+
        lda #<FAR
        sta sp_target
        lda #>FAR
        sta sp_target+1
        bne :++
:       lda sp_sig
        sta sp_target
        lda sp_sig+1
        sta sp_target+1
:       jsr stops
        ldx s
        cmp _r_visit,x
        jcc @set
        jeq @set
        lda _r_visit,x
        jsr visitp
        ldy #0
        lda (vp),y
        sec
        sbc #1
        sta sp_st
        ldx s
        lda _r_head,x
        sta sp_i
@entry: lda sp_i
        and #RING - 1
        tay
        lda (rxp),y
        cmp #OUT
        beq @last
        tax
        lda (ryp),y
        tay
        jsr platform_at
        cmp #255
        beq :+
        tax
        lda _pl_station,x
        cmp sp_st
        bne :+
        lda sp_found
        bne @also
        inc sp_found
        lda sp_i
        sta sp_first
@also:  lda sp_i
        sta sp_last
        jmp @last
:       lda sp_found
        bne @found
@last:  lda sp_i
        ldx s
        cmp _r_end,x
        beq :+
        inc sp_i
        jmp @entry
:       lda sp_found
        jeq @set
        ; the platform from the middle of one end cell to the middle of the
        ; other: the far end may be the signal past the authority
@found: lda sp_last
        and #RING - 1
        tay
        lda (rxp),y
        sta fs_x
        tax
        lda (ryp),y
        sta fs_y
        tay
        jsr platform_at
        tax
        lda fs_x
        cmp _pl_x0,x
        bne :+
        lda fs_y
        cmp _pl_y0,x
        beq @end
:       lda fs_x
        cmp _pl_x1,x
        bne :+
        lda fs_y
        cmp _pl_y1,x
        beq @end
:       inc sp_last
@end:   lda sp_first            ; a = pos(first) + 128
        pos
        sta sp_a+1
        lda #128
        sta sp_a
        lda sp_last             ; b = pos(last) + 128
        pos
        sta sp_b+1
        lda #128
        sta sp_b
        lda sp_a                ; a = (a + b) / 2 + r_len / 2
        clc
        adc sp_b
        sta sp_a
        lda sp_a+1
        adc sp_b+1
        ror a
        sta sp_a+1
        ror sp_a
        ldx s2
        lda _r_len+1,x
        lsr a
        sta ml_r+1
        lda _r_len,x
        ror a
        clc
        adc sp_a
        sta sp_a
        lda ml_r+1
        adc sp_a+1
        sta sp_a+1
        lda sp_b                ; at most b - 16
        sec
        sbc #16
        sta ml_r
        lda sp_b+1
        sbc #0
        sta ml_r+1
        lda ml_r                ; a > b - 16?
        cmp sp_a
        lda ml_r+1
        sbc sp_a+1
        bcs :+
        lda ml_r
        sta sp_a
        lda ml_r+1
        sta sp_a+1
:       lda sp_a                ; a < target, and a + 8 >= head: target = a
        cmp sp_target
        lda sp_a+1
        sbc sp_target+1
        bcs @set
        lda sp_a
        clc
        adc #8
        sta ml_r
        lda sp_a+1
        adc #0
        sta ml_r+1
        lda ml_r
        cmp sp_head
        lda ml_r+1
        sbc sp_head+1
        bcc @set
        lda sp_a
        sta sp_target
        lda sp_a+1
        sta sp_target+1
@set:   ldx s
        lda sp_found
        sta _r_platahead,x
        lda #0                  ; the stop a red signal?
        ldy _r_exit,x
        bne @sig
        ldy sp_target
        cpy sp_sig
        bne @sig
        ldy sp_target+1
        cpy sp_sig+1
        bne @sig
        jsr stops
        ldx s
        cmp _r_visit,x
        beq @nosig
        bcc @nosig
        lda #1
        bne @sig
@nosig: lda #0
@sig:   sta _r_sigstop,x
        lda #0
        sta _r_brk,x
        sta _r_halt,x
        ldy s2
        lda sp_head             ; r_rem = target > head ? target - head : 0
        cmp sp_target
        lda sp_head+1
        sbc sp_target+1
        bcc :+
        lda #0
        sta _r_rem,y
        sta _r_rem+1,y
        rts
:       lda sp_target
        sec
        sbc sp_head
        sta _r_rem,y
        lda sp_target+1
        sbc sp_head+1
        sta _r_rem+1,y
        rts

; ---- the score --------------------------------------------------------------------

; event: tell the score (game's score_event): ev_why, ev_pts, ev_late,
; ev_wrong; the train's record and station put in ev_rec and ev_st
event:  jsr recp
        lda vp
        sta ev_rec
        lda vp+1
        sta ev_rec+1
        lda #255
        ldx ev_why
        bne :+
        ldx s
        lda _r_visit,x
        jsr visitp
        ldy #0
        lda (vp),y
        sec
        sbc #1
:       sta ev_st
        jmp score_event

; arrive: at platform ar_p of its next stop: Rail Route's score for a stop,
; 10 less 2 a minute late (10 at most) and 1 for the wrong platform; and
; the time it may leave, after its dwell, 30 s at the least
arrive: ldx s
        lda _r_visit,x
        jsr visitp
        ldy #2
        lda (vp),y
        sta ar_arr
        iny
        lda (vp),y
        sta ar_arr+1
        iny
        lda (vp),y
        sta ar_dep
        iny
        lda (vp),y
        sta ar_dep+1
        lda #0
        sta ev_late
        lda ar_arr              ; clock_s > arr: t = clock_s - arr
        cmp _clock_s
        lda ar_arr+1
        sbc _clock_s+1
        bcs @ontime
        lda _clock_s
        sec
        sbc ar_arr
        sta ar_t
        lda _clock_s+1
        sbc ar_arr+1
        sta ar_t+1
@min:   lda ar_t+1              ; whole minutes, 99 at most
        bne :+
        lda ar_t
        cmp #60
        bcc @ontime
:       lda ev_late
        cmp #99
        bcs @ontime
        lda ar_t
        sec
        sbc #60
        sta ar_t
        bcs :+
        dec ar_t+1
:       inc ev_late
        bne @min
@ontime:
        ldx ar_p
        lda _pl_num,x
        ldy #1
        ldx #0
        cmp (vp),y
        beq :+
        inx
:       stx ev_wrong
        lda ev_late             ; 10 - (late >= 5 ? 10 : 2 * late) - wrong
        cmp #5
        bcc :+
        lda #5
:       asl a
        sta ml_a
        lda #10
        sec
        sbc ml_a
        sec
        sbc ev_wrong
        bpl :+
        lda #0
:       sta ev_pts
        lda #EV_ARRIVE
        sta ev_why
        jsr event
        lda #<_sfx_arrive       ; brakes and steam
        ldx #>_sfx_arrive
        jsr _eng_sfx
        ldx s
        lda _r_visit,x
        cmp #MAX_VISITS
        bcs @dwell
        ldy _r_tt,x             ; tt_..[r_tt][r_visit]
        tya
        asl a
        asl a
        asl a
        adc _r_visit,x
        tay
        ldx ar_p
        lda _pl_num,x
        sta _tt_plat,y
        lda ev_pts
        sta _tt_pts,y
        tya
        asl a
        tay
        lda #0
        rol a
        sta tq+1
        tya
        clc
        adc #<_tt_arr
        sta tq
        lda tq+1
        adc #>_tt_arr
        sta tq+1
        ldy #0
        lda _clock_s
        sta (tq),y
        iny
        lda _clock_s+1
        sta (tq),y
@dwell: lda _clock_s            ; till dep, or 30 s
        clc
        adc #30
        sta ar_t
        lda _clock_s+1
        adc #0
        sta ar_t+1
        ldx s2
        lda ar_t
        cmp ar_dep
        lda ar_t+1
        sbc ar_dep+1
        bcc :+
        lda ar_t
        sta _r_until,x
        lda ar_t+1
        sta _r_until+1,x
        rts
:       lda ar_dep
        sta _r_until,x
        lda ar_dep+1
        sta _r_until+1,x
        rts

; ---- coming in --------------------------------------------------------------------

; spawn: train sw_t onto the map, if a slot is free and so is its way in:
; A 1 if it came
spawn:  ldx #0
:       lda _r_state,x
        beq :+
        inx
        cpx #SLOTS
        bne :-
        jmp @fail
:       jsr use_slot
        ldy sw_t
        lda tt_dlo,y
        sta vp
        lda tt_dhi,y
        sta vp+1
        ; the platform of the first stop, and a portal at one of its ends
        ldx #0
@pl:    cpx _nplat
        jeq @fail
        ldy #TR_VISITS
        lda (vp),y
        sec
        sbc #1
        cmp _pl_station,x
        bne :+
        iny
        lda (vp),y
        cmp _pl_num,x
        beq @plok
:       inx
        bne @pl
@plok:  stx sw_pl
        ldy #0
@po:    cpy _nportal
        jeq @fail
        lda _portal_x,y
        cmp _pl_x0,x
        bne :+
        lda _portal_y,y
        cmp _pl_y0,x
        beq @pook
:       lda _portal_x,y
        cmp _pl_x1,x
        bne :+
        lda _portal_y,y
        cmp _pl_y1,x
        beq @pook
:       iny
        bne @po
@pook:  lda _portal_x,y
        sta sw_x
        lda _portal_y,y
        sta sw_y
        tay
        ldx sw_x
        jsr cellp
        ldy #0
        lda (mo),y
        jne @fail
        lda (mc),y
        tax
        lda _code_mask,x
        ldx #0
:       lsr a
        bcs :+
        inx
        bne :-
:       stx sw_d
        ; the train behind the portal, outside the map
        ldx s
        lda sw_t
        sta _r_tt,x
        tay
        txa
        sta _tt_slot,y
        lda #0
        sta _r_visit,x
        sta _r_exit,x
        lda #255
        sta _r_end,x
        ldy #TR_CARS
        lda (vp),y
        ldx #CAR
        jsr mul8
        ldx s2
        lda ml_r
        sta _r_len,x
        lda ml_r+1
        sta _r_len+1,x
        clc
        adc #1
        sta sw_n
        lda sw_d
        sta pu_b
        clc
        adc #4
        and #7
        sta pu_a
        lda #OUT
        sta pu_x
        lda #0
        sta pu_y
:       jsr push
        dec sw_n
        bne :-
        ldx s
        lda #0
        sta _r_tail,x
        lda sw_x
        sta pu_x
        lda sw_y
        sta pu_y
        jsr push
        ldx s
        lda _r_end,x
        sta _r_head,x
        lda #0
        sta _r_sub,x
        jsr run_on
        bne @in
        ; not free: give back what it took, try again later
        ldx s
        lda _r_head,x
        sta sw_n
@back:  ldx s
        lda _r_end,x
        clc
        adc #1
        cmp sw_n
        beq @fail
        lda sw_n
        and #RING - 1
        tay
        lda (rxp),y
        cmp #OUT
        beq :+
        tax
        lda (ryp),y
        tay
        lda #OCC_FREE
        jsr cell_mark
:       inc sw_n
        jmp @back
@fail:  lda #0
        rts
@in:    ldx s
        txa
        ora #OCC_TRAIN
        ldx sw_x
        ldy sw_y
        jsr cell_mark
        ldy sw_t
        lda tt_dlo,y
        sta vp
        lda tt_dhi,y
        sta vp+1
        ldy #TR_KMH
        lda (vp),y
        ldx #61
        jsr mul8
        ldx s2
        lda ml_r
        sta _r_vmax,x
        sta sw_v
        lda ml_r+1
        sta _r_vmax+1,x
        sta sw_v+1
        lda #0
        sta _r_acc,x
        sta _r_acc+1,x
        ldy #TR_TYPE
        lda (vp),y
        tay
        ldx s
        lda type_col,y
        sta _r_col,x
        lda #0
        sta _r_leave,x
        sta _r_flash,x
        sta _r_hid,x
        lda #S_RUN
        sta _r_state,x
        jsr stop_point
        ; come in as fast as it can and still stop in time
@fast:  lda sw_v
        ora sw_v+1
        beq @v
        lda sw_v                ; brake[v >> 7] + 8 >= r_rem?
        asl a
        lda sw_v+1
        rol a
        asl a
        tay
        lda _brake,y
        clc
        adc #8
        sta ml_r
        lda _brake+1,y
        adc #0
        sta ml_r+1
        ldx s2
        lda ml_r
        cmp _r_rem,x
        lda ml_r+1
        sbc _r_rem+1,x
        bcc @v
        lda sw_v                ; (and not below 0)
        sec
        sbc #128
        sta sw_v
        lda sw_v+1
        sbc #0
        sta sw_v+1
        bcs @fast
        lda #0
        sta sw_v
        sta sw_v+1
@v:     ldx s2
        lda sw_v
        sta _r_v,x
        lda sw_v+1
        sta _r_v+1,x
        ldx s
        lda #255
        sta _r_pix,x
        lda #1
        sta _r_dirty,x
        sta _moved
        jsr claim
        lda #1
        rts

; ---- taking routes ------------------------------------------------------------------

; take: route tk_r of the table appended to the authority, its place there
; freed
take:   ldx tk_r
        ldy _rt_sig,x
        lda _sig_x,y
        sta tk_x
        lda _sig_y,y
        sta tk_y
        lda _sig_dir,y
        clc
        adc #4
        and #7
        sta pu_a
        txa                     ; tq = rt_dirs[r]
        lsr a
        lsr a
        sta tq+1
        txa
        asl a
        asl a
        asl a
        asl a
        asl a
        asl a
        clc
        adc #<_rt_dirs
        sta tq
        lda tq+1
        adc #>_rt_dirs
        sta tq+1
        lda #0
        sta tk_k
@cell:  ldx tk_r
        ldy tk_k
        tya
        cmp _rt_len,x
        lda _rt_out,x
        bcs :+
        lda (tq),y
:       sta pu_b
        lda tk_x
        sta pu_x
        lda tk_y
        sta pu_y
        jsr push
        ldx tk_r
        lda tk_k
        cmp _rt_len,x
        beq @done
        ldx pu_b
        lda tk_x
        clc
        adc _step_x,x
        sta tk_x
        lda tk_y
        clc
        adc _step_y,x
        sta tk_y
        txa
        clc
        adc #4
        and #7
        sta pu_a
        inc tk_k
        bne @cell
@done:  lda _rt_end,x
        beq :+
        ldy s
        lda #1
        sta _r_exit,y
:       lda #255
        sta _rt_sig,x
        rts

; front_signal: the signal the authority ends before, or 255 (in A)
front_signal:
        ldx s
        lda _r_end,x
        and #RING - 1
        tay
        lda (rbp),y
        sta fs_d
        tax
        lda (rxp),y
        clc
        adc _step_x,x
        sta fs_x
        cmp _map_w
        bcs @none
        lda (ryp),y
        clc
        adc _step_y,x
        cmp _map_h
        bcs @none
        tay
        ldx fs_x
        lda fs_d
        jmp signal_at
@none:  lda #255
        rts

; rear_signal: the signal behind the train, facing the other way, with
; nothing but free cells between: what it runs to when it turns round.
; 255 if none (in A).
rear_signal:
        ldx s
        lda _r_tail,x
        and #RING - 1
        tay
        lda (rap),y
        sta fs_d
        lda (rxp),y
        sta fs_x
        lda (ryp),y
        sta fs_y
        lda #8
        sta fs_k
@cell:  lda fs_x
        cmp #OUT
        beq @none
        ldx fs_d
        clc
        adc _step_x,x
        sta fs_x
        cmp _map_w
        bcs @none
        lda fs_y
        clc
        adc _step_y,x
        sta fs_y
        cmp _map_h
        bcs @none
        tay
        ldx fs_x
        lda fs_d
        jsr signal_at
        cmp #255
        bne @rts
        ldx fs_x
        ldy fs_y
        jsr cellp
        ldy #0
        lda (mo),y
        bne @none
        dec fs_k
        bne @cell
@none:  lda #255
@rts:   rts

; head_under: the cell of the train's front (cell_under), if on the map
head_under:
        ldx s
        lda _r_head,x
        and #RING - 1
        tay
        lda (rxp),y
        cmp #OUT
        beq @rts
        tax
        lda (ryp),y
        tay
        jmp cell_under
@rts:   rts

; hide_ahead: arrived - the rest of the route it came in on, to the next
; signal, looks free (grey) from now on, its front's cell as behind it; it
; is still the train's (mo), so nothing else changes. Routes it has taken
; beyond that signal stay green: it has not been on them yet. show_ahead
; brings the green back.
hide_ahead:
        jsr head_under
        ldx s
        lda #1
        sta _r_hid,x
        sta _r_dirty,x          ; its lead grey too
        sta _moved
        lda _r_head,x
        sta hd_k
@cell:  ldx s
        lda hd_k
        sta _r_hide,x
        cmp _r_end,x
        beq @rts
        clc
        adc #1
        and #RING - 1
        tay
        lda (rxp),y
        cmp #OUT
        beq @rts
        sta hd_x
        lda (ryp),y
        sta hd_y
        lda (rap),y             ; the next route's signal: its first cell
        clc
        adc #4
        and #7
        ldx hd_x
        ldy hd_y
        jsr signal_at
        cmp #255
        bne @rts
        inc hd_k
        ldx hd_x
        ldy hd_y
        lda #OCC_FREE
        jsr cell_mark
        ldx hd_x
        ldy hd_y
        jsr cellp
        ldy #0
        lda #OCC_ROUTE
        sta (mo),y
        jmp @cell
@rts:   rts

; show_ahead: the train has a way on again - what hide_ahead made look
; free (and in its front's cell, ahead of the front) the route's green
show_ahead:
        ldx s
        lda _r_hid,x
        beq @rts
        lda #0
        sta _r_hid,x
        lda #1
        sta _r_dirty,x
        sta _moved
        lda _r_head,x
        sta hd_k
        jsr @route              ; the front's cell: still the train's, and
        ldx hd_x                ; its characters stay on screen
        cmp #OUT
        beq @rts
        ldy hd_y
        jsr cellp
        ldy #0
        lda s
        ora #OCC_TRAIN
        sta (mo),y
@cell:  ldx s
        lda hd_k
        cmp _r_hide,x
        beq @rts
        inc hd_k
        jsr @route
        cmp #OUT
        bne @cell
@rts:   rts
; @route: ring entry hd_k as part of a route (A = OUT: none, beyond the
; map); vc_keep set around the front's cell
@route: lda hd_k
        and #RING - 1
        tay
        lda (rxp),y
        cmp #OUT
        beq @out
        sta hd_x
        lda (ryp),y
        sta hd_y
        lda (rap),y
        sta cr_a
        lda (rbp),y
        sta cr_b
        ldx s
        lda hd_k
        cmp _r_head,x
        bne :+
        inc vc_keep
:       ldx hd_x
        ldy hd_y
        jsr cell_route
        ldx s
        lda hd_k
        cmp _r_head,x
        bne :+
        dec vc_keep
:       lda #0
@out:   rts

; reverse: the train turned round: its tail becomes its front. The ring's
; entries from the tail to the head turned round where they are, each one's
; ways swapped.
reverse:
        jsr head_under          ; its front's cell behind it now
        ldx s                   ; give back the authority ahead
        lda _r_head,x
        sta rv_k
@ahead: inc rv_k
        ldx s
        lda _r_end,x
        clc
        adc #1
        cmp rv_k
        beq @turn
        lda rv_k
        and #RING - 1
        tay
        lda (rxp),y
        tax
        lda (ryp),y
        tay
        lda #OCC_FREE
        jsr cell_mark
        jmp @ahead
@turn:  ldx s                   ; the tail, in the tail's entry: its byte
        lda _r_sub,x
        ldy s2
        sec
        sbc _r_len,y
        sta rv_t
        lda _r_tail,x
        sta rv_i
        lda _r_head,x
        sta rv_j
        sta _r_end,x
@swap:  lda rv_i
        cmp rv_j
        beq @mid
        jsr swap
        inc rv_i
        lda rv_i
        cmp rv_j
        beq @done
        dec rv_j
        jmp @swap
@mid:   lda rv_i                ; the middle one: its ways only
        and #RING - 1
        tay
        lda (rap),y
        tax
        lda (rbp),y
        sta (rap),y
        txa
        sta (rbp),y
@done:  ldx s
        lda #0                  ; (what it showed ahead is free now)
        sta _r_hid,x
        lda rv_t                ; r_sub = tailsub ? 256 - tailsub : 255
        beq :+
        eor #$FF
        clc
        adc #1
        bne :++
:       lda #255
:       sta _r_sub,x
        lda #0
        sta _r_exit,x
        ldx s2
        sta _r_v,x
        sta _r_v+1,x
        sta _r_acc,x
        sta _r_acc+1,x
        ldx s
        lda #1
        sta _r_dirty,x
        sta _moved
        rts

; swap: entries rv_i and rv_j of the ring swapped, the way in of each the
; way out of the other
swap:   lda rv_j
        and #RING - 1
        sta rv_k
        lda rv_i
        and #RING - 1
        tay
        lda (rxp),y
        pha
        lda (ryp),y
        pha
        lda (rap),y
        pha
        lda (rbp),y
        pha
        sty ml_a
        ldy rv_k
        lda (rxp),y
        tax
        lda (ryp),y
        sta ml_r
        lda (rap),y
        sta ml_r+1
        lda (rbp),y
        ldy ml_a
        sta (rap),y
        lda ml_r+1
        sta (rbp),y
        lda ml_r
        sta (ryp),y
        txa
        sta (rxp),y
        ldy rv_k
        pla
        sta (rap),y
        pla
        sta (rbp),y
        pla
        sta (ryp),y
        pla
        sta (rxp),y
        rts

; claim: the routes set in front of the train, one after the other; or,
; standing with none in front, one set behind it - then it turns
claim:  ldx s
        lda _r_state,x
        cmp #S_RUN
        bne @rts
        lda _r_exit,x
        bne @rts
        lda #0
        sta cl_got
@front: jsr front_signal
        cmp #255
        beq @took
        jsr route_from
        cmp #255
        beq @took
        sta tk_r
        jsr show_ahead
        jsr take
        lda #1
        sta cl_got
        ldx s
        lda _r_exit,x
        beq @front
@took:  lda cl_got
        bne @stop
        ldx s2
        lda _r_v,x
        ora _r_v+1,x
        bne @rts
        jsr rear_signal
        cmp #255
        beq @rts
        jsr route_from
        cmp #255
        beq @rts
        jsr reverse
        jsr run_on
        jsr claim               ; only once: it is moving the other way
@stop:  jmp stop_point
@rts:   rts

; train_giveback: the routes a train has taken from signal A on given
; back - if it has not passed the signal and can still stop before it.
; A 0: no train has, 1: given back, 2: too late.
train_giveback:
        tay
        lda _sig_x,y
        sta gb_x
        lda _sig_y,y
        sta gb_y
        lda _sig_dir,y          ; the way into the signal's cell
        clc
        adc #4
        and #7
        sta gb_a
        ldx #0
@slot:  stx gb_s
        lda _r_state,x
        beq @next
        jsr use_slot
        ldx s
        lda _r_head,x
        sta gb_k
@entry: ldx s                   ; ahead of its front only
        lda gb_k
        cmp _r_end,x
        beq @next
        inc gb_k
        lda gb_k
        and #RING - 1
        tay
        lda (rxp),y
        cmp gb_x
        bne @entry
        lda (ryp),y
        cmp gb_y
        bne @entry
        lda (rap),y
        cmp gb_a
        bne @entry
        beq @found
@next:  ldx gb_s
        inx
        cpx #SLOTS
        bne @slot
        lda #0
        rts
@found: ldy s2                  ; standing: it stays where it is
        lda _r_v,y
        ora _r_v+1,y
        beq @give
        lda gb_k                ; d = pos(k) - MARGIN - head
        pos
        sta gb_d+1
        lda #<-MARGIN
        sta gb_d
        dec gb_d+1
        ldx s
        lda _r_head,x
        pos
        sta ml_r+1
        ldx s
        lda gb_d
        sec
        sbc _r_sub,x
        sta gb_d
        lda gb_d+1
        sbc ml_r+1
        sta gb_d+1
        bcc @late               ; (past the place to stop)
        ldy s2                  ; brake[v >> 7] + 8 < d?
        lda _r_v,y
        asl a
        lda _r_v+1,y
        rol a
        asl a
        tay
        lda _brake,y
        clc
        adc #8
        sta ml_r
        lda _brake+1,y
        adc #0
        sta ml_r+1
        lda ml_r
        cmp gb_d
        lda ml_r+1
        sbc gb_d+1
        bcc @give
@late:  lda #2
        rts
@give:  ldx s                   ; its cells from the signal's on free
        lda gb_k
        sta hd_k
@free:  lda hd_k
        and #RING - 1
        tay
        lda (rxp),y
        cmp #OUT
        beq :+
        tax
        lda (ryp),y
        tay
        lda #OCC_FREE
        jsr cell_mark
:       ldx s
        lda hd_k
        cmp _r_end,x
        beq :+
        inc hd_k
        jmp @free
:       dec gb_k                ; its authority ends before the signal
        lda gb_k
        sta _r_end,x
        lda #0
        sta _r_exit,x
        lda #1
        sta _r_dirty,x
        sta _moved
        lda _r_state,x
        cmp #S_RUN
        bne :+
        jsr stop_point
:       lda #1
        rts

; trains_claim: every train's, after a route is set
trains_claim:
        ldx #0
:       jsr use_slot
        jsr claim
        ldx s
        inx
        cpx #SLOTS
        bne :-
        rts

; ---- the autopilot --------------------------------------------------------------

; pick: the best free route from signal pk_g to the train's stop pk_v (or
; out of the map, if it has no more): 255 if none goes there (in A)
pick:   ldy pk_g
        ldx _sig_x,y
        lda _sig_dir,y
        pha
        lda _sig_y,y
        tay
        pla
        jsr route_find
        lda #255
        sta pk_best
        sta pk_st
        lda #0
        sta pk_top
        jsr stops
        cmp pk_v
        bcc :+
        beq :+
        lda pk_v
        jsr visitp
        ldy #0
        lda (vp),y
        sec
        sbc #1
        sta pk_st
        iny
        lda (vp),y
        sta rp_pl
:       lda #0
        sta pk_i
@way:   lda pk_i
        cmp _ndest
        beq @done
        tax
        jsr route_free
        beq @next
        ldx pk_i
        lda pk_st
        cmp #255
        bne :+
        lda _dest_end,x
        asl a
        jmp @score
:       sta rp_st
        jsr route_passes
        cmp #2                  ; the platform in the timetable or none:
        beq @score              ; another may lead nowhere the train has
        lda #0                  ; to go on to (Smiths Falls' 1 and 4)
@score: sta pk_sc
        cmp pk_top
        beq @same
        bcs @best
        bcc @next
@same:  lda pk_sc
        beq @next
        ldx pk_i
        ldy pk_best
        lda _dest_len,x
        cmp _dest_len,y
        bcs @next
@best:  lda pk_sc
        sta pk_top
        lda pk_i
        sta pk_best
@next:  inc pk_i
        bne @way
@done:  lda pk_best
        rts

; The autopilot sets routes the way a good player would, ahead of time:
; from the signal the train's authority ends at, the shortest free route
; over the timetable's platform of the stop after the one it has in hand
; (or of its next, if it has none in hand), and if that platform is taken,
; none; standing at a platform, if none ahead goes there, one from the
; signal behind it - it turns when it leaves.
; ap_soon: C set if slot s's train may leave the stop it is at (or coming
; to) in AP_LEAD seconds or less - sooner, a route on from it would hold up
; trains the timetable has come first
ap_soon:
        ldx s
        lda _r_visit,x
        jsr visitp
        ldy #4
        lda (vp),y
        sec
        sbc #AP_LEAD
        sta ap_t
        iny
        lda (vp),y
        sbc #0
        sta ap_t+1
        bcc @now                ; (leaving in the first seconds)
        lda _clock_s
        cmp ap_t
        lda _clock_s+1
        sbc ap_t+1
        rts
@now:   sec
        rts

autopilot:
        ldx s
        lda _r_exit,x
        bne @rts
        lda _r_visit,x
        sta ap_v
        lda _r_state,x
        cmp #S_DWELL
        beq :+
        lda _r_platahead,x
        beq :++
:       inc ap_v
        jsr ap_soon             ; a route on from the stop: not long before
        bcc @rts                ; it may leave
:       jsr front_signal
        cmp #255
        beq @behind
        sta ap_g
        jsr route_from
        cmp #255
        bne @rts
        jsr @pick
        bne @behind
@rts:   rts
        ; behind it: standing at a platform, or before a red signal
@behind:
        ldx s
        lda _r_state,x
        cmp #S_DWELL
        beq :+
        ldx s2
        lda _r_v,x
        ora _r_v+1,x
        ora _r_rem,x
        ora _r_rem+1,x
        bne @rts
:       jsr stops
        cmp ap_v
        bcc @rts
        beq @rts
        jsr rear_signal
        cmp #255
        beq @rts
        sta ap_g
        jsr route_from
        cmp #255
        bne @rts
; @pick: a route from ap_g set, if there is one: Z set if so
@pick:  lda ap_g
        sta pk_g
        lda ap_v
        sta pk_v
        jsr pick
        cmp #255
        beq :+
        tax
        lda ap_g
        jsr route_set
        lda #0
        rts
:       lda #1                  ; (Z clear: none)
        rts

; ---- the clock ----------------------------------------------------------------

trains_reset:
        lda #S_FREE
        ldx #SLOTS - 1
:       sta _r_state,x
        dex
        bpl :-
        lda #$FF
        ldx #0
:       sta _tt_arr,x
        sta _tt_arr+128,x
        sta _tt_arr+256,x
        inx
        bpl :-
        sta _train_marked
        lda _lv_trains
        sta vp
        lda _lv_trains+1
        sta vp+1
        ldx #0
@t:     cpx _lv_ntrains
        beq @done
        cpx #MAX_TRAINS
        beq @done
        lda vp
        sta tt_dlo,x
        lda vp+1
        sta tt_dhi,x
        lda #T_WAIT
        sta _tt_state,x
        ldy #TR_NV              ; TR_VISITS + 6 a stop
        lda (vp),y
        sta ml_a
        asl a
        adc ml_a
        asl a
        adc #TR_VISITS
        clc
        adc vp
        sta vp
        bcc :+
        inc vp+1
:       inx
        bne @t
@done:  lda #1                  ; (what is left of the last level goes)
        ldx #SLOTS - 1
:       sta _r_dirty,x
        dex
        bpl :-
        sta _moved
        rts

; trains_second: once a second of the game: trains come, leave their
; platforms, the autopilot sees to one of them, and they take what is set
trains_second:
        lda ap_turn
:       clc
        adc #1
        and #SLOTS - 1
        sta ap_turn
        ldx _autopilot_on
        beq :+
        tax
        beq :+
        lda _r_state,x
        bne :+
        txa
        bcc :-
:       lda #0
        sta ts_t
@t:     ldx ts_t
        cpx _lv_ntrains
        beq @slots
        lda _tt_state,x
        bne @nt
        lda tt_dlo,x
        sta vp
        lda tt_dhi,x
        sta vp+1
        ldy #TR_VISITS + 2      ; (its first stop's arrival)
        lda (vp),y
        sta ts_when
        iny
        lda (vp),y
        sta ts_when+1
        lda ts_when             ; a minute before it is due, or at 0
        sec
        sbc #60
        sta ts_when
        lda ts_when+1
        sbc #0
        sta ts_when+1
        bcs :+
        lda #0
        sta ts_when
        sta ts_when+1
:       lda ts_when+1
        bne :+
        lda ts_when
        beq :++                 ; (60 itself: when - 60 = 0 as well)
:       lda _clock_s
        cmp ts_when
        lda _clock_s+1
        sbc ts_when+1
        bcc @nt
:       lda ts_t
        sta sw_t
        jsr spawn
        beq @nt
        ldx ts_t
        lda #T_ON
        sta _tt_state,x
@nt:    inc ts_t
        bne @t
@slots: ldx #0
@s:     jsr use_slot
        lda _r_state,x
        cmp #S_DWELL
        bne @run
        ldy s2
        lda _clock_s
        cmp _r_until,y
        lda _clock_s+1
        sbc _r_until+1,y
        bcc @run
        inc _r_visit,x
        lda #S_RUN
        sta _r_state,x
        lda #1
        sta _r_leave,x
        lda _r_exit,x           ; a way on (or out of the map) taken
        bne :+                  ; already: what it hid green again
        lda _r_hide,x
        cmp _r_end,x
        beq :++
:       jsr show_ahead
:       jsr stop_point
@run:   ldx s
        lda _r_state,x
        beq @ns
        ; the autopilot sees to one train a second, in turn: a search for
        ; routes costs a picture and more
        lda _autopilot_on
        beq :+
        cpx ap_turn
        bne :+
        jsr autopilot
:       jsr claim
@ns:    ldx s
        inx
        cpx #SLOTS
        bne @s
        rts

; pix_step: st_h in 32nds of a cell, as trains_draw draws a train: its low
; byte, in A (X = s)
pix_step:
        lda st_h+1
        sta ps_t
        lda st_h
        ldx #5
:       lsr ps_t
        ror a
        dex
        bne :-
        ldx s
        rts

; trains_step: the trains on by A 50ths of a second of the game
trains_step:
        sta st_k
        asl a
        asl a
        sta st_k4               ; 4 k
        lda #0
        rol a
        sta st_k4+1
        lda st_k                ; 7 k = 8 k - k
        asl a
        sta st_k7
        lda #0
        rol a
        sta st_k7+1
        asl st_k7
        rol st_k7+1
        asl st_k7
        rol st_k7+1
        lda st_k7
        sec
        sbc st_k
        sta st_k7
        bcs :+
        dec st_k7+1
:       ldx #0
@slot:  jsr use_slot
        lda _r_state,x
        cmp #S_RUN
        jne @next
        ldy s2
        lda _r_v,y
        sta st_v
        lda _r_v+1,y
        sta st_v+1
        lda _r_rem,y
        sta st_rem
        lda _r_rem+1,y
        sta st_rem+1
        lda st_v                ; b = brake[v >> 7]
        asl a
        lda st_v+1
        rol a
        asl a
        tay
        lda _brake,y            ; b + 4 k >= rem: brake
        clc
        adc st_k4
        sta st_h
        lda _brake+1,y
        adc st_k4+1
        sta st_h+1
        lda st_h
        cmp st_rem
        lda st_h+1
        sbc st_rem+1
        bcc @faster
        ; braking for a red signal: Rail Route takes a point for it
        lda st_v
        ora st_v+1
        beq @slower
        ldx s
        lda _r_sigstop,x
        beq @slower
        lda _r_brk,x
        bne @slower
        lda #1
        sta _r_brk,x
        lda #EV_BRAKE
        sta ev_why
        lda #$FF
        sta ev_pts
        lda #0
        sta ev_late
        sta ev_wrong
        jsr event
@slower:
        lda st_k7               ; v = v > 7 k ? v - 7 k : 0
        cmp st_v
        lda st_k7+1
        sbc st_v+1
        bcc :+
        lda #0
        sta st_v
        sta st_v+1
        beq @run
:       lda st_v
        sec
        sbc st_k7
        sta st_v
        lda st_v+1
        sbc st_k7+1
        sta st_v+1
        jmp @run
@faster:
        ldy s2                  ; below its top speed: v += 4 k
        lda st_v
        cmp _r_vmax,y
        lda st_v+1
        sbc _r_vmax+1,y
        bcs @run
        lda st_v
        clc
        adc st_k4
        sta st_v
        lda st_v+1
        adc st_k4+1
        sta st_v+1
        lda _r_vmax,y
        cmp st_v
        lda _r_vmax+1,y
        sbc st_v+1
        bcs @run
        lda _r_vmax,y
        sta st_v
        lda _r_vmax+1,y
        sta st_v+1
@run:   lda #0                  ; d: k steps of v
        sta st_d
        ldy s2
        lda _r_acc,y
        sta st_acc
        lda _r_acc+1,y
        sta st_acc+1
        lda st_k
        sta st_j
        beq @acced
@acc:   lda st_acc
        clc
        adc st_v
        sta st_acc
        lda st_acc+1
        adc st_v+1
        sta st_acc+1
        cmp #$10
        bcc :+
        lsr a
        lsr a
        lsr a
        lsr a
        clc
        adc st_d
        sta st_d
        lda st_acc+1
        and #$0F
        sta st_acc+1
:       dec st_j
        bne @acc
@acced: ldy s2
        lda st_acc
        sta _r_acc,y
        lda st_acc+1
        sta _r_acc+1,y
        lda st_v                ; the last bit, at a crawl
        ora st_v+1
        bne :+
        lda st_rem
        ora st_rem+1
        beq :+
        lda st_k4
        cmp st_rem
        lda st_k4+1
        sbc st_rem+1
        bcc :+
        lda st_rem
        sta st_d
:       lda st_rem+1            ; at most what is left
        bne :+
        lda st_rem
        cmp st_d
        bcs :+
        sta st_d
:       ldy s2
        lda st_v
        sta _r_v,y
        lda st_v+1
        sta _r_v+1,y
        lda st_d
        bne @moves
        lda st_rem
        ora st_rem+1
        ora st_v
        ora st_v+1
        jne @next
        ldx s
        lda _r_halt,x
        jeq @stopped
        jmp @next
@moves: lda st_rem
        sec
        sbc st_d
        sta _r_rem,y
        lda st_rem+1
        sbc #0
        sta _r_rem+1,y
        ldx s
        lda #1
        sta _r_moved,x
        lda _r_leave,x          ; away from its platform: the whistle, and
        beq :+                  ; it blinks till it is under way
        lda #0
        sta _r_leave,x
        lda #1
        sta _r_flash,x
        lda #<_sfx_leave
        ldx #>_sfx_leave
        jsr _eng_sfx
        ldx s
:       lda _r_flash,x
        beq :+
        lda st_v
        cmp #<V_GOING
        lda st_v+1
        sbc #>V_GOING
        bcc :+
        lda #0                  ; under way: its own colour again
        sta _r_flash,x
        lda #1
        sta _r_dirty,x
        sta _moved
:       lda _r_sub,x
        clc
        adc st_d
        sta _r_sub,x
        bcc @tail
        jsr head_under          ; the cell its front leaves: behind it now
        ldx s
        inc _r_head,x           ; into the next cell
        lda _r_head,x
        and #RING - 1
        sta st_i
        tay
        lda (rxp),y
        cmp #OUT
        beq :+
        tax
        lda (ryp),y
        tay
        lda s
        ora #OCC_TRAIN
        jsr cell_mark
:       ldx s                   ; leaving the map: more road outside
        lda _r_exit,x
        beq @tail
        lda _r_head,x
        cmp _r_end,x
        bne @tail
        ldy st_i
        lda (rap),y
        sta pu_a
        lda (rbp),y
        sta pu_b
        lda #OUT
        sta pu_x
        lda #0
        sta pu_y
        jsr push
@tail:  ldx s                   ; what the tail has left
        lda _r_head,x
        pos
        sta st_h+1
        ldx s
        lda _r_sub,x
        ldy s2
        sec
        sbc _r_len,y
        sta st_h
        lda st_h+1
        sbc _r_len+1,y
        sta st_h+1
@left:  lda st_h+1
        beq @pix
        ldx s
        lda _r_tail,x
        and #RING - 1
        tay
        lda (rxp),y
        cmp #OUT
        beq :+
        tax
        lda (ryp),y
        tay
        lda #OCC_FREE
        jsr cell_mark
:       ldx s
        inc _r_tail,x
        dec st_h+1
        jmp @left
@pix:   ldx s                   ; its front in 32nds of a cell: drawn
        lda _r_head,x           ; again when it moves on one (trains_draw
        pos                     ; draws it from there)
        sta st_h+1
        ldx s
        lda _r_sub,x
        sta st_h
        jsr pix_step
        cmp _r_pix,x
        beq :+
        sta _r_pix,x
        lda #1
        sta _r_dirty,x
        sta _moved
        ; gone, when all of it is outside the map past the portal
:       lda _r_exit,x
        beq @still
        lda _r_tail,x
        sta st_i
@out:   lda _r_head,x
        clc
        adc #1
        cmp st_i
        beq @gone
        lda st_i
        and #RING - 1
        tay
        lda (rxp),y
        cmp #OUT
        bne @still
        inc st_i
        jmp @out
@gone:  ldy _r_tt,x
        lda #T_GONE
        sta _tt_state,y
        lda #S_FREE
        sta _r_state,x
        lda #1
        sta _r_dirty,x
        sta _moved
        jmp @next
@still: ldy s2
        lda _r_rem,y
        ora _r_rem+1,y
        ora _r_v,y
        ora _r_v+1,y
        bne @next
@stopped:
        ldx s
        lda #1
        sta _r_halt,x
        ; standing: at the platform of its next stop?
        jsr stops
        ldx s
        cmp _r_visit,x
        bcc @still2
        beq @still2
        lda _r_head,x
        and #RING - 1
        tay
        lda (rxp),y
        tax
        lda (ryp),y
        tay
        jsr platform_at
        sta ar_p
        cmp #255
        beq @red
        ldx s
        lda _r_visit,x
        jsr visitp
        ldy #0
        lda (vp),y
        sec
        sbc #1
        ldx ar_p
        cmp _pl_station,x
        bne @red
        ldx s
        lda #S_DWELL
        sta _r_state,x
        jsr arrive
        jsr hide_ahead
        jmp @still2
@red:   ldx s
        lda _r_moved,x
        beq @still2
        lda _r_sigstop,x
        beq @still2
        lda #EV_RED
        sta ev_why
        lda #<-2
        sta ev_pts
        lda #0
        sta ev_late
        sta ev_wrong
        jsr event
@still2:
        ldx s
        lda #0
        sta _r_moved,x
@next:  ldx s
        inx
        cpx #SLOTS
        jne @slot
        rts

; ---- what the board asks --------------------------------------------------------

; tt_record: the record of train A of the timetable, in A/X
tt_record:
        tay
        lda tt_dlo,y
        ldx tt_dhi,y
        rts

; tt_mode: what train A is doing: TT_... (in A)
tt_mode:
        tay
        lda _tt_state,y
        cmp #T_WAIT
        beq @wait
        cmp #T_GONE
        beq @gone
        ldx _tt_slot,y
        lda _r_state,x
        cmp #S_DWELL
        beq @stop
        lda #TT_RUN
        rts
@wait:  lda #TT_WAIT
        rts
@gone:  lda #TT_GONE
        rts
@stop:  lda #TT_STOP
        rts

; tt_visit: the stop train A is on its way to or standing at (in A)
tt_visit:
        tay
        lda _tt_state,y
        cmp #T_WAIT
        beq @wait
        cmp #T_GONE
        beq @gone
        ldx _tt_slot,y
        lda _r_visit,x
        rts
@wait:  lda #0
        rts
@gone:  lda tt_dlo,y
        sta tq
        lda tt_dhi,y
        sta tq+1
        ldy #TR_NV
        lda (tq),y
        rts

; train_at: the train (of the timetable) on cell X, Y, or 255 (in A)
train_at:
        jsr cellp
        ldy #0
        lda (mo),y
        bpl @none
        and #7
        tax
        lda _r_tt,x
        rts
@none:  lda #255
        rts

; trains_flash: the trains setting off drawn again (they blink)
trains_flash:
        ldx #SLOTS - 1
@s:     lda _r_state,x
        beq @n
        lda _r_flash,x
        beq @n
        sta _r_dirty,x
        sta _moved
@n:     dex
        bpl @s
        rts

; train_departing: C set if train A (of the timetable) is setting off -
; it has whistled and is not yet under way (X changed)
train_departing:
        ldx #SLOTS - 1
@s:     ldy _r_state,x
        beq @n
        cmp _r_tt,x
        bne @n
        ldy _r_flash,x
        beq @n
        sec
        rts
@n:     dex
        bpl @s
        clc
        rts

; trains_mark: train A (of the timetable) flashes on the map; 255: none.
; It is drawn again, and the one marked before
trains_mark:
        pha
        lda _train_marked
        jsr mark_dirty
        pla
        sta _train_marked
; mark_dirty: the slot of train A (of the timetable) to be drawn again
mark_dirty:
        sta td_t
        ldx #SLOTS - 1
@s:     lda _r_state,x
        beq @n
        lda _r_tt,x
        cmp td_t
        bne @n
        lda #1
        sta _r_dirty,x
        sta _moved
@n:     dex
        bpl @s
        rts

; ---- drawing ------------------------------------------------------------------
;
; Each train has a half of the draw list to itself for each of two turns
; (engine.s, eng_tcell): 16 entries at (slot * 2 + its bank) * 16. Only a
; train to be drawn again is (r_dirty: it moved by a pixel, came, went,
; turned round, blinks): into characters from the free list (fl), noted in
; its half not on screen. When all are made, they are put on screen at
; once, the beam below the map; then each train's characters of the last
; time go back to the map's - only where the screen still shows them, so
; nothing just drawn goes. Never a moment without the train, nor one with
; it half moved on. The characters given up wait a
; turn (fq) before they are free again: the picture being shown may still
; have them.

; trains_forget: the view was drawn afresh, nothing of the trains is left
; on it: every train to be drawn again, its characters given up - and kept
; back a turn longer, the old screen being shown till the next picture
trains_forget:
        jsr pool_check
        ldx #SLOTS * 2 - 1
@h:     lda dl_cnt,x
        beq @e
        sta td_t
        txa
        asl a
        asl a
        asl a
        asl a
        tay
@c:     lda _dl_code,y
        sty td_i
        ldy fq_n
        sta fq,y
        inc fq_n
        ldy td_i
        iny
        dec td_t
        bne @c
@e:     lda #0
        sta dl_cnt,x
        dex
        bpl @h
        lda #1
        sta fq_hold
        ldx #SLOTS - 1
:       sta _r_dirty,x
        dex
        bpl :-
        sta _moved
        rts

; pool_check: the free list all the pool, if the pool is not the one it
; was made for (another size, another map): the characters are new. It
; ends where the signs' characters start (signs.s)
pool_check:
        lda _pool_first
        cmp fl_first
        bne :+
        lda _pool_end
        cmp fl_end
        beq @rts
:       lda _pool_first
        sta fl_first
        lda _pool_end
        sta fl_end
        ldy fl_first
        ldx #0
:       tya
        sta _fl,x
        inx
        iny
        cpy fl_end
        bne :-
        stx _fl_n
        lda #0
        sta fq_n
        sta fq_hold
        ldx #SLOTS * 2 - 1
:       sta dl_cnt,x
        dex
        bpl :-
@rts:   rts

trains_draw:
        lda #0
        sta _moved
        jsr pool_check
        ; what was given up last time is free now
        lda fq_hold
        beq :+
        lda #0
        sta fq_hold
        beq @zoom
:       ldx fq_n
        beq @zoom
@fq:    dex
        lda fq,x
        ldy _fl_n
        sta _fl,y
        inc _fl_n
        txa
        bne @fq
        stx fq_n
@zoom:
        ; steps of a half: 4 of 32/256 of a cell in the overview, 8 of 16
        lda _zoom
        cmp #1
        bne :+
        lda #5
        ldx #4
        ldy #32
        bne :++
:       lda #4
        ldx #8
        ldy #16
:       sta td_sh
        stx td_n
        sty td_step
        ldx #0
@slot:  jsr use_slot
        lda _r_dirty,x
        jeq @nexts
        lda #0
        sta _r_dirty,x
        lda _r_bank,x           ; into its other half
        eor #1
        sta _r_bank,x
        txa
        asl a
        ora _r_bank,x
        sta td_h
        asl a
        asl a
        asl a
        asl a
        sta _dl_n
        clc
        adc #16
        sta _dl_lim
        lda #0
        sta _tc_short
        lda _r_state,x
        jeq @built              ; gone: only what it left
        lda _r_col,x            ; white now and then: the train marked,
        ldy _train_blink        ; one setting off
        beq :++
        ldy _r_flash,x
        bne :+
        ldy _r_tt,x
        cpy _train_marked
        bne :++
:       lda #COL_HUD
:       sta _tc_col
        ldy s2
        lda _r_len,y            ; left = r_len, gl = left - CAR
        sta td_left
        sec
        sbc #CAR
        sta td_gl
        lda _r_len+1,y
        sta td_left+1
        sbc #0
        sta td_gl+1
        lda _r_head,x
        sta td_i
        lda _r_sub,x            ; hi = r_sub + 1, the front at a whole
        and #$E0                ; 32nd: the train moves all of a piece, its
                                ; end and its gaps with it, a pixel in the
                                ; overview, two (multicolour's) close up
        clc
        adc #1
        sta td_hi
        lda #0
        sta td_hi+1
        lda #0
        sta td_k
@cell:  lda td_left
        ora td_left+1
        jeq @built
        ; lo = left >= hi ? 0 : hi - left
        lda td_left
        cmp td_hi
        lda td_left+1
        sbc td_hi+1
        bcc :+
        lda #0
        sta td_lo
        sta td_lo+1
        beq :++
:       lda td_hi
        sec
        sbc td_left
        sta td_lo
        lda td_hi+1
        sbc td_left+1
        sta td_lo+1
:       lda td_hi               ; left -= hi - lo
        sec
        sbc td_lo
        sta td_t
        lda td_hi+1
        sbc td_lo+1
        sta td_t+1
        lda td_left
        sec
        sbc td_t
        sta td_left
        lda td_left+1
        sbc td_t+1
        sta td_left+1
        ; close up, the gaps between the cars: where in the cell the length
        ; left behind is a whole number of cars
        lda #0
        sta _tc_nc
        lda _zoom
        cmp #1
        beq @gaps
@gap:   lda td_gl
        ora td_gl+1
        beq @gaps
        lda td_gl
        cmp td_left
        lda td_gl+1
        sbc td_left+1
        bcc @gaps
        lda td_lo
        clc
        adc td_gl
        sec
        sbc td_left
        ldx _tc_nc
        sta _tc_cp,x
        inc _tc_nc
        lda td_gl
        sec
        sbc #CAR
        sta td_gl
        bcs @gap
        dec td_gl+1
        jmp @gap
@gaps:  lda td_i
        and #RING - 1
        tay
        lda (rxp),y
        cmp #OUT
        jeq @nextc
        sta td_x
        sec
        sbc _view_x
        cmp _view_cw
        jcs @nextc
        sta _tc_x               ; (cx for now)
        lda (ryp),y
        sta td_y
        sec
        sbc _view_y
        cmp _view_ch
        jcs @nextc
        ldx _zoom
        cpx #1
        beq :+
        asl a
        asl _tc_x
:       clc
        adc _view_sy
        adc #VIEW_TOP
        asl a
        tax
        lda _scr_row,x
        clc
        adc _view_sx
        sta _tc_o
        lda _scr_row+1,x
        adc #0
        sta _tc_o+1
        lda _tc_o
        clc
        adc _tc_x
        sta _tc_o
        bcc :+
        inc _tc_o+1
:       lda td_x
        sta _tc_x
        lda td_y
        sta _tc_y
        lda (rap),y
        sta _tc_a
        lda (rbp),y
        sta _tc_b
        ; the half it comes in by is 0-128 of the cell, the edge first; the
        ; half it goes out by 128-256, the middle first
        lda #0
        sta _tc_ae
        sta _tc_am
        lda td_lo+1
        bne @bhalf
        lda td_lo
        bmi @bhalf
        lda td_n                ; tc_ae = hi >= 128 ? n : (hi + step - 1) >> sh
        ldx td_hi+1
        bne :+
        ldx td_hi
        bmi :+
        lda td_step
        sec
        sbc #1
        clc
        adc td_hi               ; (< 256: hi < 128)
        jsr shr
:       sta _tc_ae
        lda td_lo               ; tc_am = n - (lo >> sh)
        jsr shr
        sta td_t
        lda td_n
        sec
        sbc td_t
        sta _tc_am
@bhalf: lda #0
        sta _tc_be
        sta _tc_bm
        lda td_hi+1             ; hi > 128?
        bne :+
        lda td_hi
        cmp #129
        bcc @base
:       lda td_n                ; tc_be = lo <= 128 ? n : n - ((lo - 128) >> sh)
        ldx td_lo+1
        bne :+
        ldx td_lo
        cpx #129
        bcc :++
:       lda td_lo
        sec
        sbc #128
        jsr shr
        sta td_t
        lda td_n
        sec
        sbc td_t
:       sta _tc_be
        lda td_hi               ; tc_bm = (hi - 128 + step - 1) >> sh
        sec
        sbc #128
        sta td_t
        lda td_hi+1
        sbc #0
        sta td_t+1
        lda td_step
        sec
        sbc #1
        clc
        adc td_t
        sta td_t
        lda td_t+1
        adc #0
        lsr a
        lda td_t
        ror a
        ldx td_sh
        dex
        jsr shrx
        sta _tc_bm
@base:  ldx td_x
        ldy td_y
        jsr cellp
        ldy #0                  ; its front's cell, a route's: green in
        ldx #0                  ; front of it
        lda td_k
        bne :+
        lda (ma),y
        and #$77
        cmp #COL_ROUTE
        bne :+
        inx
:       stx _tc_lead
        lda (mc),y
        ldx _zoom
        cpx #1
        bne :+
        sta _tc_base
        jmp @draw
:       sec                     ; its quarters
        sbc #C_FIRST
        ldx #0
        stx tq+1
        asl a
        rol tq+1
        asl a
        rol tq+1
        clc
        adc #<_q4
        sta tq
        lda tq+1
        adc #>_q4
        sta tq+1
        ldy #3
:       lda (tq),y
        sta _tc_base,y
        dey
        bpl :-
@draw:  jsr _eng_tcell
@nextc: lda #0                  ; hi = 256
        sta td_hi
        lda #1
        sta td_hi+1
        dec td_i
        inc td_k
        lda td_k
        cmp #4
        jne @cell
@built: ldx td_h                ; its new half: so many entries
        txa
        asl a
        asl a
        asl a
        asl a
        sta td_t
        lda _dl_n
        sec
        sbc td_t
        sta dl_cnt,x
        ldx s
        lda _tc_col
        ora #$08                ; (multicolour)
        sta td_col,x
        lda #1
        sta td_did,x
        lda _tc_short           ; short of characters: again next time,
        beq @nexts              ; when those given up now are free
        lda #0
        sta _tc_short
        lda #1
        sta _r_dirty,x
        sta _moved
@nexts: ldx s
        inx
        cpx #SLOTS
        jne @slot

        ; Then on screen, all of them at once, with the beam below the map:
        ; the next picture shows each train whole where it is now, none
        ; half moved on
        jsr _eng_below
        ldx #0
@show:  stx s
        lda td_did,x
        jeq @nshow
        lda #0
        sta td_did,x
        txa
        asl a
        ora _r_bank,x
        sta td_h
        tay
        lda dl_cnt,y
        sta td_nc
        tya
        asl a
        asl a
        asl a
        asl a
        sta td_i
        clc
        adc td_nc
        sta td_end
@new:   lda td_i
        cmp td_end
        beq @old
        tax
        lda _dl_lo,x
        sta _vp_o
        lda _dl_hi,x
        sta _vp_o+1
        lda _dl_code,x
        sta _vp_c
        ldx s
        lda td_col,x
        sta _vp_a
        jsr _vput
        inc td_i
        jmp @new
        ; what it left of the last time: the map again
@old:   lda td_h
        eor #1
        tax
        asl a
        asl a
        asl a
        asl a
        sta td_i
        clc
        adc dl_cnt,x
        sta td_end
        lda #0
        sta dl_cnt,x
@o:     lda td_i
        cmp td_end
        beq @nshow
        tax
        lda _dl_code,x          ; (its character free next time)
        ldy fq_n
        sta fq,y
        inc fq_n
        txa                     ; the same place drawn just now, as it
        and #15                 ; mostly is (entry i of the other half: i
        cmp td_nc               ; EOR 16): nothing more to do
        bcs @look
        txa
        eor #16
        tay
        lda _dl_lo,x
        cmp _dl_lo,y
        bne @look
        lda _dl_hi,x
        cmp _dl_hi,y
        beq @nexto
@look:  lda _dl_lo,x
        sta _vp_o
        lda _dl_hi,x
        sta _vp_o+1
        jsr _vget
        ldx td_i
        cmp _dl_code,x
        bne @nexto
        lda _dl_y,x
        tay
        lda _dl_x,x
        tax
        jsr cellp
        ldy #0
        lda (ma),y
        sta _vp_a
        lda (mc),y
        ldx _zoom
        cpx #1
        beq @put
        jsr q4at
        tax                     ; (a platform's edge alone: grey)
        lda _q_deco,x
        beq :+
        lda _vp_a
        and #8
        ora #COL_TRACK
        sta _vp_a
:       txa
@put:   sta _vp_c
        jsr _vput
@nexto: inc td_i
        jmp @o
@nshow: ldx s
        inx
        cpx #SLOTS
        jne @show
        rts

; q4at: quarter dl_q[td_i] of kind A
q4at:   sec
        sbc #C_FIRST
        ldx #0
        stx tq+1
        asl a
        rol tq+1
        asl a
        rol tq+1
        clc
        adc #<_q4
        sta tq
        lda tq+1
        adc #>_q4
        sta tq+1
        ldx td_i
        ldy _dl_q,x
        lda (tq),y
        rts

; shr: A >> td_sh; shrx: A >> X
shr:    ldx td_sh
shrx:   cpx #0
        beq @rts
:       lsr a
        dex
        bne :-
@rts:   rts
