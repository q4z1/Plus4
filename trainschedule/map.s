; map.s - the level: its cells, its characters, the part of it on screen
;
; A level comes as a list of tracks, each a line of points like Rail
; Route's own (tools/mklevel.py). Here they become cells: every cell
; records in which of the eight directions track leaves it, one bit each,
; and that is all the network there is - the routes are found by walking
; these bits (route.s). The character for a cell is made from the same
; bits: one half track per bit, from the middle of the cell to its edge,
; plus a signal's mark, a platform's edge or the end of the line. Each
; combination the map uses is a kind of cell, numbered C_FIRST on.
;
; Two sizes: in the overview a cell is one character, and a kind of cell
; is its character's code. Close up a cell is 2 x 2 characters, 16 x 16
; pixels: each kind has four quarters, and a quarter that looks like one
; already made is the same character - a quarter only shows three of the
; eight directions, so there are few of them.
;
; A cell is given as X (its column) and Y (its row); cellp finds its place
; in the map's three arrays (mc, ma, mo).

        .macpack longbranch
        .include "game.inc"

        .export _map_w, _map_h, _row_start, _code_mask, _code_deco
        .export _view_x, _view_y, _view_sx, _view_sy, _view_cw, _view_ch
        .export _nsig, _sig_x, _sig_y, _sig_dir, _nportal, _portal_x
        .export _portal_y, _nstation, _st_name, _nplat, _pl_station
        .export _pl_num, _pl_x0, _pl_y0, _pl_x1, _pl_y1, _lv_name
        .export _lv_start, _lv_perfect, _lv_trains, _lv_ntrains
        .export _scr_row, _step_x, _step_y, _zoom, _q4, _q_deco, _pool_first
        .export level_load, code_for, view_draw, view_cell, set_zoom
        .export cell_screen, view_set, cell_mark, cell_route, cell_under
        .export cellp, grey_of, vc_keep
        .export bands_make, bd_dirty, bd_act, bd_ng, bd_col, bd_code, bd_b
        .export bd_grow, bd_gp, bd_gfirst, bd_gend, bd_a, bd_olo, bd_ohi
        .export bd_t, bd_irq, bd_late, bd_r, bd_vs, bd_pubf
        .export cu_bands, cb_next, cb_vact, cb_ng
        .export code_kind, code_mc, cf_m, cf_d, cf_mc, cs_o, cr_a, cr_b, bitv
        .export pl_b
        .exportzp mc, ma, mo, lp, fp

        .import _vput, _vget, _vp_o, _vp_c, _vp_a, _pool_end
        .import _eng_row2, _r2_o, _r2_code, _r2_attr, _r2_n
        .import _scrn, _colr, _tz_q, _tz_n1, _tz_sh, _tz_edge, _eng_tzsetup
        .import _grey
        .import glyphs_make, _sg_top, _sg_bot, _sg_col, sign_of
        .import _strip, _lamp, _bar, _gate, _digit, _mc_of, _tk_edge
        .import _strip2, _lamp2, _bar2, _gate2, _tk2_edge, _strip2v, pd_n
        .import _cu_n, cu_olo, cu_ohi, cu_under, cu_ucol, cu_band, _frames

        .segment "GAMEZP": zeropage
mc:     .res 2                  ; a cell's place in MAP_CODE (cellp)
ma:     .res 2                  ;             in MAP_ATTR
mo:     .res 2                  ;             in MAP_OCC
lp:     .res 2                  ; the level's data, being read
fp:     .res 2                  ; a character of the font
qp:     .res 2                  ; a kind's quarters in q4
tb:     .res 2                  ; a table of glyphs
tp:     .res 2                  ; a row of it; a text
dp:     .res 2                  ; on screen: characters
dq:     .res 2                  ;            colours
gp:     .res 2                  ; grey_of's

        .bss
_map_w:     .res 1
_map_h:     .res 1
_view_x:    .res 1              ; map cell at the view's corner
_view_y:    .res 1
_view_sx:   .res 1              ; screen cell of the map's 0, 0
_view_sy:   .res 1
_view_cw:   .res 1              ; columns and rows shown
_view_ch:   .res 1
_nsig:      .res 1
_sig_x:     .res MAX_SIGNALS
_sig_y:     .res MAX_SIGNALS
_sig_dir:   .res MAX_SIGNALS
_nportal:   .res 1
_portal_x:  .res MAX_PORTALS
_portal_y:  .res MAX_PORTALS
_nstation:  .res 1
_st_name:   .res MAX_STATIONS * 16
_nplat:     .res 1
_pl_station: .res MAX_PLATS
_pl_num:    .res MAX_PLATS
_pl_x0:     .res MAX_PLATS      ; its end cells
_pl_y0:     .res MAX_PLATS
_pl_x1:     .res MAX_PLATS
_pl_y1:     .res MAX_PLATS
_lv_name:   .res 20
_lv_start:  .res 2              ; minutes after midnight
_lv_perfect: .res 2
_lv_trains: .res 2              ; the trains in the level data
_lv_ntrains: .res 1
_q4:        .res (C_LAST + 1 - C_FIRST) * 4     ; close up: a kind's quarters
; close up, by character: bit 0 for a quarter in the track's grey whatever
; the colour of its cell (a route's, a signal's): one with nothing but a
; platform's edge and number in it - the track it goes with keeps to the
; other quarters (tools/mklevel.py) - or a set switch's other legs. Bit 1:
; a set switch's top quarter whose lines 6-7 have the other colour, cell's
; or grey (path_split; the bands, engine.s).
        .segment "XBSS"         ; (trainschedule.cfg; cleared by make_all)
_q_deco:    .res 256
        .bss
_pool_first: .res 1             ; the first character for the trains
st_lx:      .res MAX_STATIONS   ; the stations' labels
st_ly:      .res MAX_STATIONS
        .segment "XBSS"         ; (filled as a level loads)
plain:     .res 256            ; the kind of a plain track, by its bits
        .bss
next_code:  .res 1              ; the next kind
next_q:     .res 1              ; close up: the next quarter
        .segment "BANDS"        ; (trainschedule.cfg; cleared by make)
cellbuf:    .res 64             ; a cell's pixels being made (the quarters
                                ; top left, top right, bottom left, bottom
                                ; right); 32 on, a set switch's other leg
        .bss

cf_m:       .res 1              ; code_for's bits and decoration
cf_d:       .res 1
cf_mc:      .res 1              ; and code_kind's multicolour
cs_o:       .res 2              ; cell_screen's offset, 0: not in view
cs_x:       .res 1
cr_a:       .res 1              ; cell_route's ways in and out
cr_b:       .res 1
mk_c:       .res 1              ; make's kind
mk_n:       .res 1              ; the bytes of its glyph: 8 or 32
mk_sh:      .res 1              ; that as a shift: 3 or 5
mk_mask:    .res 1
mk_deco:    .res 1
mk_d:       .res 1
mk_dst:     .res 1              ; orbuf into cellbuf + this
mk_t:       .res 1
mk_k:       .res 1
mk_i:       .res 1
mk_z:       .res 1
mk_g:       .res 1
mk_q:       .res 1
mk_nx:      .res 1
mk_ny:      .res 1
mk_qs:      .res 1              ; the quarters with something in, before
mk_qd:      .res 1              ; the edge; those with only it
mk_qg:      .res 1              ; a set switch's grey ones (lines 0-5)
mk_qb:      .res 1              ; and those of two colours (regions)
mk_qo:      .res 1              ; the overview's q_deco (ov_regions)
mk_m2:      .res 1              ; 1: a platform's kind for a route (pl_var)
mk_w:       .res 1              ; quarters: grey wanted (0 or 1)
qo_m:       .res 1
t_strip:    .res 2              ; the glyph tables of the size now (make)
t_lamp:     .res 2
t_bar:      .res 2
t_gate:     .res 2
px_b:       .res 1
px_o:       .res 1
ps_a:       .res 1
ps_b:       .res 1
ps_w:       .res 1
ps_t:       .res 1
rg_w:       .res 1
rg_o:       .res 1
rg_c:       .res 6
pk_m:       .res 1              ; path_kind's bits, ways, and the two as one
pk_a:       .res 1
pk_b:       .res 1
pk_p:       .res 1
pk_e:       .res 1
fk:         .res 1
tx_n:       .res 1
tx_max:     .res 1
sg_t:       .res 1
fl_n:       .res 2
j_x0:       .res 1              ; join's line
j_y0:       .res 1
j_x1:       .res 1
j_y1:       .res 1
j_dx:       .res 1
j_dy:       .res 1
j_d:        .res 1
j_e:        .res 1
ll_n:       .res 1              ; level_load's
ll_i:       .res 1
ll_j:       .res 1
ll_m:       .res 1
ll_px:      .res 1
ll_py:      .res 1
ll_cells:   .res 2
vs_t:       .res 1
vc_a:       .res 1
c2_x:       .res 1
c2_y:       .res 1
lb_a:       .res 1
lb_b:       .res 1
lb_k:       .res 1
lb_n:       .res 1
lb_i:       .res 1
lb_j:       .res 1
lb_c:       .res 1
lb_t:       .res 1
lb_ro:      .res 2
vd_y:       .res 1
vd_cy:      .res 1
cm_occ:     .res 1
cm_x:       .res 1
cm_y:       .res 1
cm_mc:      .res 1
vc_keep:    .res 1              ; vput1 leaves the trains' characters be
cr_x:       .res 1
cr_y:       .res 1

        .segment "STKBSS"       ; (trainschedule.cfg)
_row_start: .res 2 * 64         ; each row's first cell
        .segment "MAPHI"        ; above the map: made afresh with every
_code_mask: .res 256            ; level - the title picture is drawn over
_code_deco: .res 256            ; them
        .segment "HIBSS"
; For a switch in a route: the kind showing the way it is set - that way
; hires in the route's colour, its other legs grey only in quarters
; without it, else left out (path_split).
; code_path: the way, a + 16 * b, or 255 for an
; ordinary kind.
_code_path: .res 256

        .bss
; 1 for a kind in multicolour: the track grey (%10) and the mark - a
; signal's lamp, the bar where the line ends - in the cell's own colour
; (%11), red or green; the track keeps its grey. Also the kinds made from
; them without the mark, which stand in for them when the marks blink.
        .segment "XBSS"         ; (filled as a level loads)
code_mc:    .res 256
        .segment "BANDS"        ; (pl_v filled as a level loads)
pl_vt:      .res C_LAST + 1 - C_FIRST ; a platform's kind: its kind for a
pl_bt:      .res C_LAST + 1 - C_FIRST ; route in the overview (pl_var), back
pl_v = pl_vt - C_FIRST
pl_b = pl_bt - C_FIRST
        .bss
pl_k:       .res 1
pz_n:       .res 2
vq_x:       .res 1
        .segment "HIBSS"

        .data
_zoom:      .byte 2             ; characters a cell is wide

        .rodata
_step_x:    .byte 1, 1, 0, $FF, $FF, $FF, 0, 1
_step_y:    .byte 0, $FF, $FF, $FF, 0, 1, 1, 1
bitv:       .byte 1, 2, 4, 8, 16, 32, 64, 128
bit80:      .byte 128, 64, 32, 16, 8, 4, 2, 1
_scr_row:   .repeat 25, R       ; screen offset of each row
            .word R * 40
            .endrepeat
; the glyph tables, overview and close up: strips, lamps, bars, gates
mk_tabs:    .word _strip, _lamp, _bar, _gate
            .word _strip2, _lamp2, _bar2, _gate2
; where a platform's number goes close up, by the axis of its track: on
; the side of its edge, clear of the track (and of a train on it)
num_x:      .byte 10, 10, 10, 3
num_y:      .byte 10, 9, 1, 9
; a set switch's parts close up (regions): first byte, last + 1, the
; horizontal leg in it (its bit)
rg_s:       .byte 0, 6, 8, 14, 16, 24
rg_e:       .byte 6, 8, 14, 16, 24, 32
rg_h:       .byte 0, $10, 0, $01, 0, 0

        .code

; ---- cells --------------------------------------------------------------------

; cellp: cell X, Y: mc, ma, mo its place in the three arrays. Keeps X.
cellp:  tya
        asl a
        tay
        txa
        clc
        adc _row_start,y
        sta mc
        sta ma
        sta mo
        lda _row_start+1,y
        adc #>MAP_CODE
        sta mc+1
        adc #>(MAP_ATTR - MAP_CODE)     ; (no carry: the map is small)
        sta ma+1
        adc #>(MAP_OCC - MAP_ATTR)
        sta mo+1
        rts

; forks: more than two bits in A - a switch or a crossing (A not 0, Z
; clear). Keeps X.
forks:  sta fk
        sec
        sbc #1
        and fk
        sta fk
        sec
        sbc #1
        and fk
        rts

; ---- the kinds of cell ----------------------------------------------------

; code_for: the kind of cell with bits cf_m and decoration cf_d, made if
; there is none yet (A). Out of kinds, the plain track has to do.
code_for:
        lda #0
        sta cf_mc
        lda cf_d
        and #DECO_SIGNAL | DECO_END
        beq code_kind
        inc cf_mc
; code_kind: as code_for, cf_mc given
code_kind:
        lda cf_m
        ora cf_d
        ora cf_mc
        bne :+
        lda #32
        rts
:       lda cf_d
        ora cf_mc
        bne @deco
        ldx cf_m
        lda plain,x
        beq @new
        rts
@deco:  ldx #C_FIRST
@find:  cpx next_code
        beq @new
        lda _code_mask,x
        cmp cf_m
        bne @no
        lda _code_deco,x
        cmp cf_d
        bne @no
        lda _code_path,x
        cmp #255
        bne @no
        lda code_mc,x
        cmp cf_mc
        bne @no
        txa
        rts
@no:    inx
        bne @find
@new:   ldx next_code
        cpx #C_LAST + 1
        bcc @make
        lda cf_d                ; none left: the plain track, or nothing
        beq @space
        lda #0
        sta cf_d
        sta cf_mc
        beq code_kind
@space: lda #32
        rts
@make:  inc next_code
        lda cf_m
        sta _code_mask,x
        lda cf_d
        sta _code_deco,x
        lda #255
        sta _code_path,x
        lda cf_mc
        sta code_mc,x
        stx mk_c
        jsr make
        ldx mk_c
        lda cf_d
        ora cf_mc
        bne :+
        ldy cf_m
        txa
        sta plain,y
:       txa
        rts

; path_kind: the kind of a switch with bits pk_m set the way pk_a - pk_b
; (made if need be), in A
path_kind:
        lda pk_a
        cmp pk_b
        bcc @ab
        lda pk_b                ; b | a << 4
        sta pk_p
        lda pk_a
        jmp @hi
@ab:    sta pk_p                ; a | b << 4
        lda pk_b
@hi:    asl a
        asl a
        asl a
        asl a
        ora pk_p
        sta pk_p
        ldx #C_FIRST
@find:  cpx next_code
        beq @new
        lda _code_mask,x
        cmp pk_m
        bne @no
        lda _code_path,x
        cmp pk_p
        bne @no
        txa
        rts
@no:    inx
        bne @find
@new:   cpx #C_LAST + 1
        bcc @make
        ldx pk_m
        lda plain,x
        rts
@make:  inc next_code
        lda pk_m
        sta _code_mask,x
        lda #0
        sta _code_deco,x
        lda pk_p
        sta _code_path,x
        lda #0
        sta code_mc,x
        stx mk_c
        jsr make
        lda mk_c
        rts

; make_all: the characters of every kind afresh, for the size now
make_all:
        lda #0
        tax
:       sta _q_deco,x
        inx
        bne :-
        lda #C_FIRST
        sta next_q
        sta mk_c
:       lda mk_c
        cmp next_code
        beq pool_set
        jsr make
        inc mk_c
        bne :-
; pool_set: where the trains' characters start
pool_set:
        lda #C_LAST + 1
        ldx _zoom
        cpx #1
        beq :+
        lda next_q
:       sta _pool_first
        jmp glyphs_make         ; (signs.s)

.macro  settb t
        lda t
        sta tb
        lda t+1
        sta tb+1
.endmacro

; make: the character(s) of kind mk_c - in the overview its character,
; close up its four quarters, each one already made if it looks the same
make:   ldx #0                  ; the tables of the size now
        ldy #8
        lda #3
        sta mk_sh
        lda _zoom
        cmp #1
        beq :+
        ldx #8
        ldy #32
        lda #5
        sta mk_sh
:       sty mk_n
        ldy #0
:       lda mk_tabs,x
        sta t_strip,y
        inx
        iny
        cpy #8
        bne :-
        ldx mk_c
        lda _code_mask,x
        sta mk_mask
        lda _code_deco,x
        sta mk_deco
        lda #0
        sta mk_dst
        sta mk_qg
        sta mk_qb
        sta mk_qo
        ldy #63
:       sta cellbuf,y
        dey
        bpl :-
        sta mk_m2
        lda code_mc,x           ; a platform's kind for a route (pl_var):
        cmp #2                  ; the track in the cell's colour, at 32,
        bne :++                 ; the edge and its number grey - the
        lda _zoom               ; overview's only (close up no cell has it)
        cmp #1
        beq :+
        rts
:       inc mk_m2
        lda #32
        sta mk_dst
:       lda _code_path,x
        cmp #255
        beq @strips
        jsr path_split          ; a set switch: only its two colours
        lda #0
        sta mk_mask
        sta mk_deco
@strips:
        settb t_strip           ; one half track a bit
        lda #0
        sta mk_d
@strip: ldx mk_d
        lda mk_mask
        and bitv,x
        beq :+
        txa
        jsr orbuf
:       inc mk_d
        lda mk_d
        cmp #8
        bne @strip
        ldx mk_c                ; multicolour: the marks apart, at 32
        lda code_mc,x
        beq :+
        lda #32
        sta mk_dst
:       lda mk_deco             ; a signal's lamp
        and #DECO_SIGNAL
        beq :+
        settb t_lamp
        lda mk_deco
        and #7
        jsr orbuf
        ; a platform's edge along the track: its axis is the lowest bit's
        ; direction, mod 4; the end of the line across the track's one bit
:       ldx #0
:       lda mk_mask
        and bitv,x
        bne :+
        inx
        cpx #7
        bne :-
:       stx mk_d
        lda mk_deco
        and #DECO_END
        beq :+
        settb t_gate
        lda mk_d
        jsr orbuf
:       lda #0
        sta mk_dst
        jsr qocc                ; what is there before the edge
        sta mk_qs
        lda mk_deco
        and #DECO_PLATFORM
        beq :+
        settb t_bar
        lda mk_d
        and #3
        jsr orbuf
:       lda mk_deco
        and #DECO_NUMBER
        beq @done
        lda _zoom
        cmp #1
        bne @num2
        ; the platform's number in the middle of the cell, the track making
        ; room for it
        jsr num5
        ldy #6
        lda mk_m2               ; (the track at 32 for a route's kind)
        bne @nr2
:       lda cellbuf,y
        and #$C1
        sta cellbuf,y
        dey
        bpl :-
        bmi @nr
@nr2:   lda cellbuf+32,y
        and #$C1
        sta cellbuf+32,y
        dey
        bpl @nr2
@nr:
        ldy #0
:       lda _digit,x
        lsr a
        lsr a
        lsr a
        ora cellbuf+1,y
        sta cellbuf+1,y
        inx
        iny
        cpy #5
        bne :-
@done:  ldx mk_c
        lda code_mc,x
        beq :+
        jsr mc_mix
:       lda _zoom
        cmp #1
        beq :+
        jsr qocc                ; the quarters with only the edge in them
        lda mk_qs               ; - or a set switch's other legs: grey
        eor #$FF
        and qo_m
        ora mk_qg
        sta mk_qd
        jmp quarters
:
        ldx mk_c                ; the overview: the character itself
        lda mk_qo
        sta _q_deco,x
        txa
        jsr fontp
        ldy #7
:       lda cellbuf,y
        sta (fp),y
        dey
        bpl :-
        lda mk_c
        jmp grey_of
        ; close up, the number on the side of its edge: the edge makes room
@num2:  lda mk_d
        and #3
        tax
        lda num_x,x
        sta mk_nx
        lda num_y,x
        sta mk_ny
        lda #0
        sta mk_k
@clr:   lda #0
        sta mk_i
:       lda mk_nx
        clc
        adc mk_i
        tax
        dex
        lda mk_ny
        clc
        adc mk_k
        tay
        dey
        clc
        jsr px2
        inc mk_i
        lda mk_i
        cmp #5
        bne :-
        inc mk_k
        lda mk_k
        cmp #7
        bne @clr
        jsr num5
        stx mk_z
        lda #0
        sta mk_k
@row:   lda mk_z
        clc
        adc mk_k
        tax
        lda _digit,x
        sta mk_t                ; its pixels, from bit 7
        lda #0
        sta mk_i
@px:    asl mk_t
        bcc :+
        lda mk_nx
        clc
        adc mk_i
        tax
        lda mk_ny
        clc
        adc mk_k
        tay
        sec
        jsr px2
:       inc mk_i
        lda mk_i
        cmp #3
        bne @px
        inc mk_k
        lda mk_k
        cmp #5
        bne @row
        jmp @done

; the four quarters of kind mk_c from cellbuf: the space, one made already,
; or a new one (the space too when there is no room)
quarters:
        lda mk_c
        jsr q4p
        lda #0
        sta mk_q
@q:     lda mk_q
        asl a
        asl a
        asl a
        sta mk_g
        tax
        lda #0
        ldy #8
:       ora cellbuf,x
        inx
        dey
        bne :-
        tax
        bne @look
        lda #32                 ; nothing: the space
        jmp @put
@look:  ldy mk_q                ; its q_deco, as the one found has
        lda mk_qb               ; to have it: 1 grey, 2 two colours
        and bitv,y
        beq :+
        lda #2
:       sta mk_w
        lda mk_qd
        and bitv,y
        beq :+
        inc mk_w
:
        lda #C_FIRST
        sta mk_k
        jsr fontp
@cmp:   lda mk_k
        cmp next_q
        beq @none
        lda mk_g
        clc
        adc #7
        tax
        ldy #7
:       lda (fp),y
        cmp cellbuf,x
        bne @next
        dex
        dey
        bpl :-
        ldx mk_k
        lda _q_deco,x
        cmp mk_w
        bne @next
        txa
        jmp @put
@next:  lda fp
        clc
        adc #8
        sta fp
        bcc :+
        inc fp+1
:       inc mk_k
        jmp @cmp
@none:  cmp #C_LAST + 1         ; (A = next_q; fp its character)
        bcc @new
        lda #32                 ; out of characters
        bne @put
@new:   lda mk_g
        clc
        adc #7
        tax
        ldy #7
:       lda cellbuf,x
        sta (fp),y
        dex
        dey
        bpl :-
        ldx next_q
        lda mk_w
        sta _q_deco,x
        txa
        jsr grey_of
        lda next_q
        inc next_q
@put:   ldy mk_q
        sta (qp),y
        inc mk_q
        lda mk_q
        cmp #4
        jne @q
        rts

; mc_mix: a multicolour kind's glyph: the track in cellbuf grey (%10), the
; marks at cellbuf + 32 over it in the cell's colour (%11)
mc_mix: ldy mk_n
        dey
@b:     ldx cellbuf+32,y
        lda _mc_of,x
        sta ps_t
        ldx cellbuf,y
        lda _mc_of,x
        and #$AA
        ora ps_t
        sta cellbuf,y
        dey
        bpl @b
        rts

; qocc: the quarters of cellbuf with anything in them (or a mark of a
; multicolour kind's at 32), a bit each (bit 0 top left ... bit 3 bottom
; right), in A and qo_m
qocc:   lda #0
        sta qo_m
        ldx #31
@b:     lda cellbuf,x
        ora cellbuf+32,x
        beq :+
        txa
        lsr a
        lsr a
        lsr a
        tay
        lda bitv,y
        ora qo_m
        sta qo_m
:       dex
        bpl @b
        lda qo_m
        rts

; orbuf: cellbuf + mk_dst |= row A of the table at tb, mk_n bytes a row
orbuf:  ldx mk_sh
:       asl a
        dex
        bne :-
        clc
        adc tb
        sta tp
        lda tb+1
        adc #0
        sta tp+1
        ldy mk_n
        dey
        tya
        clc
        adc mk_dst
        tax
:       lda cellbuf,x
        ora (tp),y
        sta cellbuf,x
        dex
        dey
        bpl :-
        rts

; path_split: a set switch (kind mk_c, bits mk_mask), hires, in cellbuf:
; its way in the cell's own colour, the other legs grey. A hires character
; has one colour, but the TED can fetch a character row's colours again
; after its sixth line (engine.s, the bands): close up, a top quarter has
; one colour in its lines 0-5 - the legs going up - and one in 6-7, the
; horizontal track's (regions). The overview has the way only.
path_split:
        ldx mk_c
        lda _code_path,x
        and #15
        sta ps_a
        tay
        lda _code_path,x
        lsr a
        lsr a
        lsr a
        lsr a
        sta ps_b
        tax
        lda bitv,x
        ora bitv,y
        sta ps_w                ; the way's bits
        lda #0
        sta mk_d
@d:     settb t_strip
        ldx mk_d
        lda mk_mask
        and bitv,x
        beq @nd
        lda #0                  ; the way to cellbuf, the other legs to
        sta mk_dst              ; cellbuf + 32
        lda ps_w
        and bitv,x
        bne :+
        lda #32
        sta mk_dst
:       lda mk_n
        cmp #32
        bne @plain
        ; close up, north or south a pixel aside, clear of a diagonal leg
        ; at its side, which has that column of characters to itself
        ldy #0                  ; (strip2v: N left, N right, S left, S right)
        cpx #2
        bne @s
        lda mk_mask
        and #$02                ; north-east: north to the left
        bne @v
        iny
        lda mk_mask
        and #$08                ; north-west: to the right
        bne @v
        beq @plain
@s:     cpx #6
        bne @plain
        ldy #3
        lda mk_mask
        and #$20                ; south-west: south to the right
        bne @v
        dey
        lda mk_mask
        and #$80                ; south-east: to the left
        beq @plain
@v:     lda #<_strip2v
        sta tb
        lda #>_strip2v
        sta tb+1
        tya
        jmp @or
@plain: txa
@or:    jsr orbuf
@nd:    inc mk_d
        lda mk_d
        cmp #8
        bne @d
        lda #0
        sta mk_dst
        lda mk_n
        cmp #32
        bne ov_regions
        jmp regions
; ov_regions: the overview, a cell one character: legs going up in its
; lines 0-2, the track across in 3-4, legs going down in 5-7; the way in
; cellbuf, the other legs at 32. q_deco (mk_qo): bit 0 drawn grey, bit 1
; a band (engine.s: one more fetch of the row's colours, in line 2), bit
; 2 multicolour from there, bit 3 the cell multicolour (drawn so).
; - Only a leg going up not in the way: lines 0-2 grey, the band the
;   cell's colour (q 3).
; - More not in the way below line 3 (half the track across, a leg going
;   down): lines 3-7 multicolour, the way %11, the rest grey %10 - along
;   the track across as fine as hires. With a leg going up, it hires in
;   lines 0-2 and the band multicolour (q 6, or 7 if the leg is grey);
;   without, the whole cell multicolour (q 8): a leg going down, coarser,
;   in the right colour. (One fetch a row: no time for a second with rows
;   of switches one under the other.)
ov_regions:
        lda cellbuf+32+3        ; anything not in the way below line 3?
        ora cellbuf+32+4
        ora cellbuf+32+5
        ora cellbuf+32+6
        ora cellbuf+32+7
        bne @mc
        lda cellbuf+32
        ora cellbuf+33
        ora cellbuf+34
        beq @merge              ; no other leg going up
        lda cellbuf
        ora cellbuf+1
        ora cellbuf+2
        bne @merge              ; (the way goes up)
        lda #3
        sta mk_qo
@merge: ldy #7
:       lda cellbuf+32,y
        ora cellbuf,y
        sta cellbuf,y
        lda #0
        sta cellbuf+32,y
        dey
        bpl :-
        rts
@mc:    lda #8                  ; no leg going up: the cell multicolour
        sta mk_qo
        lda cellbuf
        ora cellbuf+1
        ora cellbuf+2
        ora cellbuf+32
        ora cellbuf+33
        ora cellbuf+34
        beq @lines
        lda #6                  ; one going up: the band, multicolour
        sta mk_qo
        lda cellbuf
        ora cellbuf+1
        ora cellbuf+2
        bne @lines
        inc mk_qo               ; (7: the leg grey)
@lines: ldy #7                  ; lines 3-7 multicolour, 0-2 hires
@l:     ldx cellbuf,y
        lda _mc_of,x
        sta mk_t
        ldx cellbuf+32,y
        lda _mc_of,x
        and #$AA
        ora mk_t
        cpy #3
        bcs :+
        lda cellbuf+32,y
        ora cellbuf,y
:       sta cellbuf,y
        lda #0
        sta cellbuf+32,y
        dey
        bpl @l
        rts

; regions: close up, the six parts of a set switch's cell that each have a
; colour of their own - top left lines 0-5 and 6-7, top right the same,
; bottom left, bottom right - from the way in cellbuf and the other legs
; in cellbuf + 32. A part's colour: its horizontal leg's (lines 6-7, the
; leg there), else the way's if it is in it, else grey. Grey takes the
; other legs in too, the way's few pixels next to them (where they meet)
; with them; the way's colour leaves them out. Then each quarter's bits:
; mk_qg the grey ones (lines 0-5), mk_qb those of two colours.
regions:
        ldx #5
@r:     lda #0
        sta rg_w
        sta rg_o
        ldy rg_s,x
:       lda cellbuf,y
        ora rg_w
        sta rg_w
        lda cellbuf+32,y
        ora rg_o
        sta rg_o
        iny
        tya
        cmp rg_e,x
        bne :-
        lda rg_w
        ora rg_o
        bne :+
        lda #$FF                ; nothing in it
        bne @put
:       lda rg_h,x
        and mk_mask
        beq @way
        and ps_w
        beq @grey
        bne @own
@way:   lda rg_w
        bne @own
@grey:  ldy rg_s,x
:       lda cellbuf+32,y
        ora cellbuf,y
        sta cellbuf,y
        iny
        tya
        cmp rg_e,x
        bne :-
        lda #1
        bne @put
@own:   lda #0
@put:   sta rg_c,x
        dex
        bpl @r
        ldy #0
        lda rg_c
        ldx rg_c+1
        jsr rg_q
        iny
        lda rg_c+2
        ldx rg_c+3
        jsr rg_q
        iny
        lda rg_c+4
        tax
        jsr rg_q
        iny
        lda rg_c+5
        tax
        jsr rg_q
        lda #0
        ldy #31
:       sta cellbuf+32,y
        dey
        bpl :-
        rts

; rg_q: quarter Y's colours, A in its lines 0-5, X in 6-7 (0 the cell's,
; 1 grey, $FF nothing there), to mk_qg and mk_qb. Keeps Y.
rg_q:   cmp #$FF
        bne :+
        txa                     ; nothing on top: as below
:       cpx #$FF
        bne :+
        tax                     ; nothing below: as on top
:       sta rg_w
        stx rg_o
        cmp #1
        bne :+
        lda bitv,y
        ora mk_qg
        sta mk_qg
:       lda rg_w
        cmp rg_o
        beq :+
        lda bitv,y
        ora mk_qb
        sta mk_qb
:       rts

; px2: close up, pixel X, Y of cellbuf set (C set) or cleared
px2:    php
        txa
        and #7
        sta px_b
        tya
        and #8
        asl a
        sta px_o
        txa
        and #8
        ora px_o
        sta px_o
        tya
        and #7
        ora px_o
        tay
        ldx px_b
        lda bit80,x
        plp
        bcc @clr
        ora cellbuf,y
        sta cellbuf,y
        rts
@clr:   eor #$FF
        and cellbuf,y
        sta cellbuf,y
        rts

; num5: the platform's number in mk_deco (bits 0-2, and 8 for bit 7)
; times 5: its digit's place in digit, in X
num5:   lda mk_deco
        and #7
        bit mk_deco
        bpl :+
        ora #8
:       sta mk_t
        asl a
        asl a
        clc
        adc mk_t
        tax
        rts

; fontp: fp = character A in the font
fontp:  ldx #0
        stx fp+1
        asl a
        rol fp+1
        asl a
        rol fp+1
        asl a
        rol fp+1
        sta fp
        lda fp+1
        ora #>FONT
        sta fp+1
        rts

; grey_of: character A's glyph (at fp) as a cell of a train shows it
; where the train is not: multicolour, its track grey (%10) - for
; eng_tcell, in _grey (engine.s)
grey_of:
        ldx #0
        stx gp+1
        asl a
        rol gp+1
        asl a
        rol gp+1
        asl a
        rol gp+1
        clc
        adc #<_grey
        sta gp
        lda gp+1
        adc #>_grey
        sta gp+1
        ldy #7
:       lda (fp),y
        tax
        lda _mc_of,x
        and #$AA
        sta (gp),y
        dey
        bpl :-
        rts

; q4p: qp = the quarters of kind A
q4p:    sec
        sbc #C_FIRST
        ldx #0
        stx qp+1
        asl a
        rol qp+1
        asl a
        rol qp+1
        clc
        adc #<_q4
        sta qp
        lda qp+1
        adc #>_q4
        sta qp+1
        rts

; ---- the bands ----------------------------------------------------------------

; A set switch's character may have two colours, one above and one below a
; line: close up, its top quarters at line 6 (path_split), in the overview
; at line 3 (ov_regions). The screen's colours have the first, and the
; interrupt has the TED fetch the row's colours again a line before that,
; with the second in (engine.s, band). Here, its list: by screen row (top
; first), the line before which (bd_gp: 5 or 2), and for each such
; character in view its column, its character and the colour from there
; on - in two sets, the one the interrupt reads (bd_act) and the one made
; afresh (bands_make).

BD_MAX = 24                     ; a set's places
BD_ROWS = 12                    ; and rows
BD_PER = 3                      ; places a row: what the interrupt has time
                                ; for (engine.s) - 2 with the fetch in line 2
BD_GR = 2 * BD_ROWS + 4         ; rows and places in all: then the cursor's
BD_PL = 2 * BD_MAX + 8          ; two pairs of rows (cu_bands)

        .bss                    ; (cleared at the start: bd_ng 0)
bd_dirty:   .res 1              ; 1: the list to be made again
bd_pubf:    .res 1              ; _frames when it was handed over
bd_act:     .res 1              ; the set the interrupt reads, 0 or 1
bd_ng:      .res 2              ; each set's rows
cb_vact:    .res 1              ; the cursor's pair of rows the interrupt
cb_next:    .res 1              ; reads, and from the next blank on
cb_ng:      .res 2              ; each pair's rows
cb_p:       .res 1              ; (cu_bands's)
cb_g0:      .res 1
cb_g:       .res 1
cb_e:       .res 1
cb_r:       .res 1
cb_c:       .res 1
cb_lo:      .res 1
cb_hi:      .res 1
bd_col:     .res BD_PL          ; the place's column
bd_code:    .res BD_PL          ; the character
bd_b:       .res BD_PL          ; the colour from the fetch on
bd_a:       .res BD_PL          ; and before it, the screen's
bd_grow:    .res BD_GR          ; a row's screen row
bd_gp:      .res BD_GR          ; the line its fetch is in
bd_gfirst:  .res BD_GR          ; its places: from
bd_gend:    .res BD_GR          ; to (not with)
        .segment "STKBSS"       ; (trainschedule.cfg; made before read)
bd_olo:     .res 2 * BD_MAX     ; the place's offset on screen
bd_ohi:     .res 2 * BD_MAX
        .bss                    ; a row's raster lines (bm_lines):
bd_t:       .res BD_GR          ; its line 0, the TED's fetch just over
bd_irq:     .res BD_GR          ; its interrupt's
bd_late:    .res BD_GR          ; vshift written only before it
bd_r:       .res BD_GR          ; vshift back in it
bd_vs:      .res BD_GR          ; vshift for the fetch
        .segment "BANDS"        ; (all set before they are read)
bm_set:     .res 1
bm_i:       .res 1
bm_iend:    .res 1
bm_g:       .res 1
bm_gbase:   .res 1
bm_gend:    .res 1
bm_y:       .res 1
bm_x:       .res 1
bm_r:       .res 1
bm_p:       .res 1
bm_col:     .res 1
bm_ch:      .res 1
bm_b:       .res 1
bm_a:       .res 1
bm_cc:      .res 1
bm_gx:      .res 1
bm_yy:      .res 1
bm_ccol:    .res 1
bm_j:       .res 1
        .code

; bands_make: the list for the view as it is, handed to the interrupt -
; once the colours of the bands drawn from the set it makes afresh are
; back (in the next vertical blank: engine.s, band_undo). None of them
; are if the list was handed over before this picture's blank: its bands
; were drawn from the set in use.
bands_make:
:       lda pd_n
        beq :+
        lda bd_pubf
        cmp _frames
        beq :-
:
        lda #0
        sta bd_dirty
        sta bm_i
        sta bm_g
        lda bd_act
        eor #1
        sta bm_set
        beq :+
        lda #BD_MAX
        sta bm_i
        lda #BD_ROWS
        sta bm_g
:       lda bm_g
        sta bm_gbase
        clc
        adc #BD_ROWS
        sta bm_gend
        lda bm_i
        clc
        adc #BD_MAX
        sta bm_iend
        lda #0
        sta bm_y
@row:   lda bm_y
        cmp _view_ch
        jeq @hand
        clc
        adc _view_y
        tay
        ldx _view_x
        jsr cellp
        lda bm_y
        ldx _zoom
        cpx #1
        beq :+
        asl a
:       clc
        adc _view_sy
        adc #VIEW_TOP
        sta bm_r
        lda #5                  ; close up: before line 6
        cpx #1
        bne :+
        lda #2                  ; the overview: before line 3
:       sta bm_p
        ldy #0
@cell:  cpy _view_cw
        beq @nrow
        jsr bm_kind
        beq @next
        sty bm_x
        lda (ma),y
        and #$77
        sta bm_col
        lda _zoom
        cmp #1
        beq @ov
        txa
        jsr q4p
        ldy #0
        jsr bm_quarter
        iny
        jsr bm_quarter
        jmp @back
@ov:    stx bm_ch               ; the overview: the cell's character
        lda _q_deco,x           ; grey or its colour above line 3, the
        and #2                  ; cell's from there - multicolour for
        beq @back               ; q_deco bit 2 (ov_regions)
        lda _q_deco,x
        lsr a
        lda bm_col
        bcc :+
        lda #COL_TRACK
:       sta bm_a
        lda _q_deco,x
        and #4
        beq :+
        lda #8
:       ora bm_col
        sta bm_b
        lda bm_x
        clc
        adc _view_sx
        sta bm_cc
        jsr bm_add
@back:  ldy bm_x
@next:  iny
        bne @cell
@nrow:  inc bm_y
        jmp @row
@hand:  lda bm_g
        sec
        sbc bm_gbase
        ldx bm_set
        sei
        sta bd_ng,x
        stx bd_act
        lda _frames
        sta bd_pubf
        cli
        rts

; cu_bands: the cursor's rows (engine.s): close up, its places in a bottom
; quarter over hires (cu_band), their lines 5-7 (the fetch in line 4) in
; its green, or multicolour where more than a little is there. Made into the pair the interrupt does not read (cb_vact), which
; it reads from the next blank on (cb_next) - till then the old pair, also
; while this one is being made. Rows top first: the top corners' places
; come first (trainschedule.s, cursor_show).
COL_CUR = $55                   ; the cursor's green (engine.s COL_MC1)

cu_bands:
        lda cb_vact
        eor #1
        sta cb_p
        cmp cb_next
        bne :+
        lda cb_vact
        sta cb_next
:       lda cb_p                ; its rows from 24 + 2 * pair, places from
        asl a                   ; 48 + 4 * pair
        adc #2 * BD_ROWS        ; (C clear)
        sta cb_g0
        sta cb_g
        lda cb_p
        asl a
        asl a
        adc #2 * BD_MAX
        sta cb_e
        lda #$FF
        sta cb_r
        lda _zoom
        cmp #2
        jne @done
        ldy #0
@pl:    cpy _cu_n
        jeq @done
        lda cu_band,y
        jeq @next
        lda cu_olo,y            ; its row and column: offset / 40
        sta cb_lo
        lda cu_ohi,y
        sta cb_hi
        ldx #0
@d8:    lda cb_lo               ; (8 rows at a time first)
        sec
        sbc #<320
        sta cb_c
        lda cb_hi
        sbc #>320
        bcc @d1
        sta cb_hi
        lda cb_c
        sta cb_lo
        txa
        adc #7                  ; (C set: 8)
        tax
        bcc @d8
@d1:    lda cb_lo
        sec
        sbc #40
        sta cb_c
        lda cb_hi
        sbc #0
        bcc @rc
        sta cb_hi
        lda cb_c
        sta cb_lo
        inx
        bne @d1
@rc:    cpx cb_r
        beq @same
        stx cb_r                ; a new row
        ldx cb_g
        lda cb_r
        sta bd_grow,x
        sta bm_r
        lda #4
        sta bd_gp,x
        sta bm_p
        jsr bm_lines
        lda cb_e
        sta bd_gfirst,x
        sta bd_gend,x
        inc cb_g
@same:  ldx cb_e
        lda cb_lo
        sta bd_col,x
        lda cu_under,y
        sta bd_code,x
        lda cu_ucol,y
        sta bd_a,x
        lda cu_band,y           ; green, or multicolour in its own colour
        lsr a
        lda #COL_CUR
        bcs :+
        lda cu_ucol,y
        ora #$08
:       sta bd_b,x
        inc cb_e
        ldx cb_g
        lda cb_e
        sta bd_gend-1,x
@next:  iny
        jmp @pl
@done:  lda cb_g
        sec
        sbc cb_g0
        ldx cb_p
        sta cb_ng,x
        stx cb_next
        rts

; bm_kind: the kind of the row's cell Y in X, Z clear if a set switch's.
; Keeps Y.
bm_kind:
        lda (mc),y
        tax
        lda _code_path,x
        cmp #255
        rts

; bm_quarter: top quarter Y (0, 1) of the set switch at bm_x on the list,
; if it has two colours. Keeps Y.
bm_quarter:
        lda (qp),y
        tax
        lda _q_deco,x
        and #2
        beq @rts
        stx bm_ch
        lda _q_deco,x           ; lines 6-7: the cell's colour under grey,
        and #1                  ; grey under the cell's
        beq :+
        lda #COL_TRACK
        sta bm_a
        lda bm_col
        jmp :++
:       lda bm_col
        sta bm_a
        lda #COL_TRACK
:       sta bm_b
        tya                     ; its column
        clc
        adc bm_x
        adc bm_x
        adc _view_sx
        sta bm_cc
        jmp bm_add
@rts:   rts

; bm_add: bm_ch at column bm_cc of row bm_r (fetch in line bm_p), the
; colour bm_b from there on, on the list - if there is room. Keeps Y.
bm_add:
        ldx bm_g                ; its row: begun already, or new
        cpx bm_gbase
        beq @new
        lda bd_grow-1,x
        cmp bm_r
        bne @new
        lda bd_gp-1,x
        cmp bm_p
        beq @old
@new:   cpx bm_gend
        jeq @rts                ; (no room: one colour)
        lda bm_r
        sta bd_grow,x
        lda bm_p
        sta bd_gp,x
        jsr bm_lines
        lda bm_i
        sta bd_gfirst,x
        sta bd_gend,x
        inc bm_g
        inx
@old:   stx bm_gx
        lda bd_gend-1,x         ; room in the row?
        sec
        sbc bd_gfirst-1,x
        cmp #BD_PER
        bcs @rts
        ldx bm_p
        cpx #2
        bne :+
        cmp #BD_PER - 1
        bcs @rts
:       ldx bm_gx
        lda bm_i
        cmp bm_iend
        beq @rts
        tax
        lda bm_ch
        sta bd_code,x
        lda bm_b
        sta bd_b,x
        lda bm_a
        sta bd_a,x
        lda bm_cc
        sta bd_col,x
        sty bm_yy
        lda bm_r                ; its offset on screen
        asl a
        tay
        lda _scr_row,y
        clc
        adc bm_cc
        sta bd_olo,x
        lda _scr_row+1,y
        adc #0
        sta bd_ohi,x
        ldy bm_yy
        inc bm_i
        ldx bm_gx
        lda bm_i
        sta bd_gend-1,x
@rts:   rts

; bm_lines: row X's raster lines (screen row bm_r, its fetch in line bm_p,
; 2, 4 or 5): line 0 8 * row + 4 (the TED fetched the row's colours in line
; -1); the interrupt in line -3 (engine.s); vshift for
; line p written before p - 1, for line 2 before p (engine.s, band, fast);
; back in p + 1. Keeps X, Y.
bm_lines:
        lda bm_r
        asl a
        asl a
        asl a
        clc
        adc #4
        sta bd_t,x
        sec
        sbc #1
        sta bd_irq,x
        lda bd_t,x
        clc
        adc bm_p
        sta bd_late,x           ; p
        sta bd_r,x              ; (vshift back in p itself: the TED has
        and #7                  ; taken it at the line's start)
        sta bd_vs,x
        dec bd_irq,x            ; the interrupt in -3: all set up by the
        dec bd_irq,x            ; time the TED lets go in line 0 (in -1 it
        lda bm_p                ; would only be served then)
        cmp #4
        bcc :+
        dec bd_late,x           ; 4, 5: vshift before p - 1, 2: before p
:       rts

; ---- the level --------------------------------------------------------------

; the next byte of the level (Z for 0)
next:   ldy #0
        lda (lp),y
        inc lp
        bne :+
        inc lp+1
:       cmp #0
        rts

; text: a 0-terminated text of the level, copied to (tp) if tx_max is not
; 0: at most tx_max - 1 characters of it, and the 0
text:   lda #0
        sta tx_n
@ch:    ldy #0
        lda (lp),y
        beq @end
        ldx tx_max
        beq @skip
        ldy tx_n
        iny
        cpy tx_max
        bcs @skip
        dey
        sta (tp),y
        inc tx_n
@skip:  inc lp
        bne @ch
        inc lp+1
        bne @ch
@end:   inc lp
        bne :+
        inc lp+1
:       lda tx_max
        beq :+
        lda #0
        ldy tx_n
        sta (tp),y
:       rts

; fill: fl_n bytes A from tp on
fill:   ldx fl_n+1
        beq @part
        ldy #0
:       sta (tp),y
        iny
        bne :-
        inc tp+1
        dex
        bne :-
@part:  ldx fl_n
        beq @done
        ldy #0
:       sta (tp),y
        iny
        dex
        bne :-
@done:  rts

.macro  fillw addr, n, value
        lda #<(addr)
        sta tp
        lda #>(addr)
        sta tp+1
        lda n
        sta fl_n
        lda n+1
        sta fl_n+1
        lda #value
        jsr fill
.endmacro

.macro  fill256 addr, value
        lda #value
        ldx #0
:       sta addr,x
        inx
        bne :-
.endmacro

; sgn: the step from A to X: 1, -1 ($FF) or 0
sgn:    sta sg_t
        cpx sg_t
        beq @z
        bcs @p
        lda #$FF
        rts
@p:     lda #1
        rts
@z:     lda #0
        rts

; While a level is built, map_occ holds the bits of each cell and
; map_attr what else is in it; then both become a character and a colour.

; join: the track from j_x0, j_y0 to j_x1, j_y1, a straight line
join:   lda j_x0
        ldx j_x1
        jsr sgn
        sta j_dx
        lda j_y0
        ldx j_y1
        jsr sgn
        sta j_dy
        ldx #0
@dir:   lda _step_x,x
        cmp j_dx
        bne :+
        lda _step_y,x
        cmp j_dy
        beq :++
:       inx
        cpx #8
        bne @dir
:       stx j_d
        txa
        clc
        adc #4
        and #7
        sta j_e
@step:  lda j_x0
        cmp j_x1
        bne :+
        lda j_y0
        cmp j_y1
        beq @done
:       ldx j_x0
        ldy j_y0
        jsr cellp
        ldx j_d
        lda bitv,x
        ldy #0
        ora (mo),y
        sta (mo),y
        lda j_x0
        clc
        adc j_dx
        sta j_x0
        tax
        lda j_y0
        clc
        adc j_dy
        sta j_y0
        tay
        jsr cellp
        ldx j_e
        lda bitv,x
        ldy #0
        ora (mo),y
        sta (mo),y
        jmp @step
@done:  rts

; level_load: the level at lp: its map, its kinds of cell, its signals,
; portals, stations and platforms, and where its trains are (lv_trains)
level_load:
        jsr next
        sta _map_w
        jsr next
        sta _map_h
        jsr next
        sta _lv_start
        jsr next
        sta _lv_start+1
        jsr next
        sta _lv_perfect
        jsr next
        sta _lv_perfect+1
        lda #<_lv_name
        sta tp
        lda #>_lv_name
        sta tp+1
        lda #20
        sta tx_max
        jsr text
        lda #0
        sta tx_max
        jsr text
        lda #0                  ; each row's first cell
        sta ll_cells
        sta ll_cells+1
        tay
@rows:  cpy _map_h
        beq @rowsdone
        tya
        asl a
        tax
        lda ll_cells
        sta _row_start,x
        clc
        adc _map_w
        sta ll_cells
        lda ll_cells+1
        sta _row_start+1,x
        adc #0
        sta ll_cells+1
        iny
        bne @rows
@rowsdone:
        fillw MAP_CODE, ll_cells, 32
        fillw MAP_OCC, ll_cells, 0
        fillw MAP_ATTR, ll_cells, 0
        fill256 plain, 0
        fill256 _code_path, 255
        fill256 code_mc, 0
        lda #0
        ldx #C_LAST - C_FIRST
:       sta pl_vt,x
        dex
        bpl :-
        fill256 _code_mask, 0
        fill256 _code_deco, 0
        lda #C_FIRST
        sta next_code
        sta next_q

        ; tracks
        jsr next
        sta ll_n
@track: lda ll_n
        beq @signals
        dec ll_n
        jsr next
        sta ll_j
        jsr next
        sta j_x0
        jsr next
        sta j_y0
@point: dec ll_j
        beq @track
        jsr next
        sta j_x1
        sta ll_px
        jsr next
        sta j_y1
        sta ll_py
        jsr join
        lda ll_px               ; (join leaves j_x0, j_y0 at its end)
        sta j_x0
        lda ll_py
        sta j_y0
        jmp @point

@signals:
        jsr next
        sta _nsig
        ldx #0
        stx ll_i
@sig:   ldx ll_i
        cpx _nsig
        beq @portals
        jsr next
        ldx ll_i
        sta _sig_x,x
        jsr next
        ldx ll_i
        sta _sig_y,x
        jsr next
        ldx ll_i
        sta _sig_dir,x
        ldy _sig_y,x
        lda _sig_x,x
        tax
        jsr cellp
        ldx ll_i
        lda _sig_dir,x
        ora #DECO_SIGNAL
        ldy #0
        sta (ma),y
        inc ll_i
        bne @sig

@portals:
        jsr next
        sta _nportal
        ldx #0
        stx ll_i
@portal:
        ldx ll_i
        cpx _nportal
        beq @stations
        jsr next
        ldx ll_i
        sta _portal_x,x
        jsr next
        ldx ll_i
        sta _portal_y,x
        inc ll_i
        bne @portal

@stations:
        jsr next
        sta _nstation
        lda #0
        sta _nplat
        sta ll_i
@station:
        ldx ll_i
        cpx _nstation
        jeq @trains
        jsr next
        ldx ll_i
        sta st_lx,x
        sta c2_x
        jsr next
        ldx ll_i
        sta st_ly,x
        sta c2_y
        jsr st_ptr
        lda #16
        sta tx_max
        jsr text
        ; the label: only where there is no track
        ldx ll_i
        jsr st_ptr
        lda #0
        sta ll_j
@label: ldy ll_j
        lda (tp),y
        beq @plats
        ldx c2_x
        cpx _map_w
        bcs @plats
        ldy c2_y
        jsr cellp
        ldy #0
        lda (mo),y
        bne :+
        ldy ll_j
        lda (tp),y
        ldy #0
        sta (mc),y
:       inc ll_j
        inc c2_x
        jmp @label
@plats: jsr next
        sta ll_n
@plat:  lda ll_n
        jeq @nextst
        dec ll_n
        ldx _nplat
        lda ll_i
        sta _pl_station,x
        jsr next
        ldx _nplat
        sta _pl_num,x
        jsr next
        ldx _nplat
        sta _pl_x0,x
        sta j_x0
        sta ll_px
        jsr next
        ldx _nplat
        sta _pl_y0,x
        sta j_y0
        sta ll_py
        jsr next
        ldx _nplat
        sta _pl_x1,x
        sta j_x1
        jsr next
        ldx _nplat
        sta _pl_y1,x
        sta j_y1
        ; the edge on the cells between its ends, its number on the one in
        ; the middle of them
        lda j_x0
        ldx j_x1
        jsr sgn
        sta j_dx
        lda j_y0
        ldx j_y1
        jsr sgn
        sta j_dy
        lda #0
        sta ll_j
@edge:  jsr pl_step
        lda j_x0
        cmp j_x1
        bne :+
        lda j_y0
        cmp j_y1
        beq @edged
:       ldx j_x0
        ldy j_y0
        jsr cellp
        ldy #0
        lda (ma),y
        ora #DECO_PLATFORM
        sta (ma),y
        inc ll_j
        jmp @edge
@edged: lda ll_j
        beq @nonum
        clc
        adc #1
        lsr a
        sta ll_j
        lda ll_px
        sta j_x0
        lda ll_py
        sta j_y0
:       jsr pl_step
        dec ll_j
        bne :-
        ldx j_x0
        ldy j_y0
        jsr cellp
        ldx _nplat
        lda _pl_num,x
        and #8
        asl a
        asl a
        asl a
        asl a
        sta ll_m
        lda _pl_num,x
        and #7
        ora ll_m
        ora #DECO_NUMBER
        ldy #0
        ora (ma),y
        sta (ma),y
@nonum: inc _nplat
        jmp @plat
@nextst:
        inc ll_i
        jmp @station

@trains:
        jsr next
        sta _lv_ntrains
        lda lp
        sta _lv_trains
        lda lp+1
        sta _lv_trains+1

        ; the cells become characters; a track that ends is a portal or a
        ; buffer stop and shows it
        lda #<MAP_CODE
        sta mc
        sta ma
        sta mo
        lda #>MAP_CODE
        sta mc+1
        lda #>MAP_ATTR
        sta ma+1
        lda #>MAP_OCC
        sta mo+1
        lda ll_cells
        sta fl_n
        lda ll_cells+1
        sta fl_n+1
@cell:  lda fl_n
        ora fl_n+1
        beq @cells
        ldy #0
        lda (mo),y
        beq @nontrack
        sta cf_m
        sec
        sbc #1
        and cf_m
        bne :+
        lda (ma),y
        ora #DECO_END
        sta (ma),y
:       lda (ma),y
        sta cf_d
        sta ll_m
        jsr code_for
        ldy #0
        sta (mc),y
        lda #COL_TRACK
        ldx cf_mc
        beq @attr
        lda #COL_SIG_RED | 8    ; the mark red, the track grey
        bne @attr
@nontrack:
        lda #COL_LABEL
@attr:  sta (ma),y
        inc mc
        inc ma
        inc mo
        bne :+
        inc mc+1
        inc ma+1
        inc mo+1
:       lda fl_n
        bne :+
        dec fl_n+1
:       dec fl_n
        jmp @cell
@cells: fillw MAP_OCC, ll_cells, OCC_FREE

        ; every signal and end of the line also without its mark, made now:
        ; a route's ends blink by it (trainschedule.s), and kinds made later
        ; would take characters from the trains' pool
        lda next_code
        sta ll_m
        lda #C_FIRST
        sta ll_i
@kind:  lda ll_i
        cmp ll_m
        jeq @kinds
        tax
        lda _code_deco,x
        sta ll_n
        lda _code_mask,x
        sta pk_m
        jsr forks
        beq @nofork
        lda #0                  ; a switch also set each way it can be
        sta pk_a
@fa:    lda pk_a
        clc
        adc #6
        cmp #8
        bcc :+
        lda #8
:       sta pk_e                ; b < a + 6 and b < 8
        lda pk_a
        clc
        adc #3
        sta pk_b
@fb:    lda pk_b
        cmp pk_e
        bcs @na
        ldx pk_a
        lda pk_m
        and bitv,x
        beq :+
        ldx pk_b
        lda pk_m
        and bitv,x
        beq :+
        jsr path_kind
:       inc pk_b
        jmp @fb
@na:    inc pk_a
        lda pk_a
        cmp #8
        bne @fa
@nofork:
        ldx ll_i
        lda _code_mask,x
        sta cf_m
        lda ll_n
        and #DECO_SIGNAL
        beq :+
        lda ll_n
        and #<~(DECO_SIGNAL | 7)
        jmp @unm
:       lda ll_n
        and #DECO_END
        beq @nk
        lda ll_n
        and #<~DECO_END
@unm:   sta cf_d
        lda #1                  ; multicolour, the track grey
        sta cf_mc
        jsr code_kind
        lda #0                  ; and in a route, hires, all green: with
        sta cf_mc               ; the mark and without
        jsr code_kind
        lda ll_n
        sta cf_d
        jsr code_kind
@nk:    inc ll_i
        jmp @kind
@kinds: jsr pool_set
        jsr zoom_tables
        lda #0
        sta _view_x
        sta _view_y
        jmp view_size

; a step along the platform being made
pl_step:
        lda j_x0
        clc
        adc j_dx
        sta j_x0
        lda j_y0
        clc
        adc j_dy
        sta j_y0
        rts

; st_ptr: tp = the name of station X. Keeps X.
st_ptr: txa
        asl a
        asl a
        asl a
        asl a
        clc
        adc #<_st_name
        sta tp
        lda #>_st_name
        adc #0
        sta tp+1
        rts

; ---- the view -----------------------------------------------------------------

; view_size: how much of the map the view shows at this size, and where:
; a small map in the middle, a large one from the view's corner
view_size:
        lda _zoom
        cmp #1
        bne @z2
        lda #40
        ldx #VIEW_H
        bne @set
@z2:    lda #20
        ldx #VIEW_H / 2
@set:   cmp _map_w
        bcc :+
        lda _map_w
:       sta _view_cw
        txa
        cmp _map_h
        bcc :+
        lda _map_h
:       sta _view_ch
        ldx _zoom
        lda _view_cw
        cpx #1
        beq :+
        asl a
:       sta vs_t
        lda #40
        sec
        sbc vs_t
        lsr a
        sta _view_sx
        lda _view_ch
        cpx #1
        beq :+
        asl a
:       sta vs_t
        lda #VIEW_H
        sec
        sbc vs_t
        lsr a
        sta _view_sy
        rts

; the tables the trains are drawn from (engine.s), for the size now
zoom_tables:
        lda _zoom
        cmp #1
        bne @z2
        lda #1
        ldx #5
        ldy #3
        sta _tz_q
        stx _tz_n1
        sty _tz_sh
        lda #<_tk_edge
        ldx #>_tk_edge
        bne @edge
@z2:    lda #4
        ldx #9
        ldy #5
        sta _tz_q
        stx _tz_n1
        sty _tz_sh
        lda #<_tk2_edge
        ldx #>_tk2_edge
@edge:  sta _tz_edge
        stx _tz_edge+1
        jmp _eng_tzsetup

; set_zoom: size A - its characters, its view
set_zoom:
        sta _zoom
        jsr make_all
        jsr pl_zoom
        jsr zoom_tables
        jmp view_size

; ---- a platform in a route, in the overview -------------------------------
; A cell of the overview is one character, track and platform's edge (and
; its number) in it: hires, a route would make the edge green too. So
; there a platform's cell in a route is a kind of its own, multicolour: the
; track in the cell's colour, the edge and the number grey (%10) - along a
; track across only, where multicolour is as fine as hires. Close up the
; edge has quarters of its own, grey (q_deco): the plain kind.

; pl_var: X a kind: its kind for a route in the overview - a platform's
; without a signal or the end of the line, made the first time - or X
pl_var:
        lda code_mc,x
        bne @self               ; (multicolour already)
        lda _code_path,x
        cmp #255
        bne @self               ; (a set switch)
        lda _code_deco,x
        and #DECO_PLATFORM | DECO_SIGNAL | DECO_END
        cmp #DECO_PLATFORM
        bne @self
        lda _code_mask,x        ; along a track across only (east, west):
        and #$EE                ; multicolour as fine as hires there, not
        bne @self               ; for one up or askew
        lda pl_v,x
        beq @make
        cmp #1
        beq @self               ; (none to be had)
        tax
@self:  rts
@make:  stx pl_k
        lda _code_mask,x
        sta cf_m
        lda _code_deco,x
        sta cf_d
        lda #2
        sta cf_mc
        jsr code_kind
        tay
        ldx pl_k
        lda code_mc,y
        cmp #2
        beq :+
        lda #1                  ; out of kinds: the plain one
        sta pl_v,x
        rts
:       tya
        sta pl_v,x
        txa
        sta pl_b,y
        tya
        tax
        rts

; pl_zoom: the map's platforms in a route to the kinds of the size now
pl_zoom:
        lda #<MAP_CODE
        sta mc
        lda #>MAP_CODE
        sta mc+1
        lda #<MAP_ATTR
        sta ma
        lda #>MAP_ATTR
        sta ma+1
        lda ll_cells
        sta pz_n
        lda ll_cells+1
        sta pz_n+1
@c:     lda pz_n
        ora pz_n+1
        beq @rts
        ldy #0
        lda (mc),y
        tax
        lda _zoom
        cmp #1
        bne @close
        lda (ma),y              ; the overview: a route's (not under a
        cmp #COL_ROUTE          ; train) the route's kind
        bne @next
        jsr pl_var
        lda code_mc,x
        cmp #2
        bne @next
        txa
        ldy #0
        sta (mc),y
        lda #COL_ROUTE | 8
        sta (ma),y
        bne @next
@close: lda code_mc,x           ; close up: the plain kind again
        cmp #2
        bne @next
        lda pl_b,x
        sta (mc),y
        lda #COL_ROUTE
        sta (ma),y
@next:  inc mc
        bne :+
        inc mc+1
:       inc ma
        bne :+
        inc ma+1
:       lda pz_n
        bne :+
        dec pz_n+1
:       dec pz_n
        jmp @c
@rts:   rts

; view_set: the view's corner on the map at X, Y, kept inside it
view_set:
        txa
        bpl :+
        ldx #0
:       tya
        bpl :+
        ldy #0
:       txa
        clc
        adc _view_cw
        cmp _map_w
        beq :+
        bcc :+
        lda _map_w
        sec
        sbc _view_cw
        tax
:       tya
        clc
        adc _view_ch
        cmp _map_h
        beq :+
        bcc :+
        lda _map_h
        sec
        sbc _view_ch
        tay
:       stx _view_x
        sty _view_y
        rts

; cell_screen: the screen offset of cell X, Y's (top left) character, or 0
; if it is not in view: in cs_o, and in A/X
cell_screen:
        txa
        sec
        sbc _view_x
        cmp _view_cw
        bcs @out
        sta cs_x
        tya
        sec
        sbc _view_y
        cmp _view_ch
        bcs @out
        ldx _zoom
        cpx #1
        beq :+
        asl a
        asl cs_x
:       clc
        adc _view_sy
        adc #VIEW_TOP
        asl a
        tay
        lda _scr_row,y
        clc
        adc _view_sx
        sta cs_o
        lda _scr_row+1,y
        adc #0
        sta cs_o+1
        lda cs_o
        clc
        adc cs_x
        sta cs_o
        bcc :+
        inc cs_o+1
:       lda cs_o
        ldx cs_o+1
        rts
@out:   lda #0
        sta cs_o
        sta cs_o+1
        tax
        rts

; vputq: as vputo, a quarter close up: one of only a platform's edge in
; the track's grey (q_deco)
vputq:  sta _vp_c
        stx vq_x
        tax
        lda vc_a
        jsr ov_col
        ldx vq_x
        jmp vput1

; ov_col: colour A of a cell with character X as drawn: grey for q_deco
; bit 0 (a multicolour cell's grey is %10), multicolour for bit 3 (the
; overview's set switches, ov_regions). Keeps Y.
        .export ov_col
ov_col: pha
        lda _q_deco,x
        lsr a
        pla
        bcc :+
        and #8
        ora #COL_TRACK
:       pha
        lda _q_deco,x
        and #8
        sta mk_t
        pla
        ora mk_t
        rts

; vputo: character A in colour vc_a at cs_o + X, past the cursor (vput)
vputo:  sta _vp_c
        lda vc_a
vput1:  sta _vp_a
        txa
        clc
        adc cs_o
        sta _vp_o
        lda cs_o+1
        adc #0
        sta _vp_o+1
        lda vc_keep
        beq @put
        lda _vp_c               ; a train's character there stays
        pha
        lda _vp_a
        pha
        jsr _vget
        tax
        pla
        sta _vp_a
        pla
        sta _vp_c
        cpx _pool_first
        bcc @put
        cpx _pool_end
        bcs @put
        rts
@put:   jmp _vput

; close up, the part of a station's sign in the cell c2_x, c2_y at cs_o,
; past the cursor: both its halves, both rows (signs.s). Half h of the
; cell is half 2 * x + h of its row; a label from cell lx on has letter k
; in half 2 * lx + k, and its plate's ends in the halves before and after
label2: lda _sg_col
        sta vc_a
        lda #0
        sta lb_j
@half:  jsr sign_at
        tax
        bmi @sp
        lda _sg_top,x
        sta lb_a
        lda _sg_bot,x
        sta lb_b
        jmp @put
@sp:    lda #32
        sta lb_a
        sta lb_b
@put:   lda lb_a
        ldx lb_j
        jsr vputo
        lda lb_j
        clc
        adc #40
        tax
        lda lb_b
        jsr vputo
        inc lb_j
        lda lb_j
        cmp #2
        bne @half
        rts

; sign_at: the sign in half lb_j of cell c2_x, c2_y - a label's letter,
; or an end of its plate - in A; $FF if none
sign_at:
        ldx #0
@st:    cpx _nstation
        beq @none
        lda st_ly,x
        cmp c2_y
        bne @no
        lda c2_x
        sec
        sbc st_lx,x
        bpl @in
        cmp #$FF                ; the cell before the label: its right
        bne @no                 ; half the plate's left end
        lda lb_j
        beq @no
        lda #SG_LCAP
        rts
@in:    asl a
        ora lb_j
        sta lb_k
        stx lb_i
        jsr st_ptr
        ldy #$FF
:       iny
        lda (tp),y
        bne :-
        cpy lb_k                ; Y: the label's length
        beq @rcap
        bcc @past
        ldy lb_k
        lda (tp),y
        jmp sign_of
@rcap:  lda #SG_RCAP
        rts
@past:  ldx lb_i
@no:    inx
        bne @st
@none:  lda #$FF
        rts

; close up, the labels in view, all at once (when the view is drawn
; afresh): the signs, half k of a label in half
; 2 * lx + k of its row, the plate's ends at k = -1 and k = its length -
; those only where the cell has no track
labels2:
        lda #0
        sta lb_i
@st:    ldx lb_i
        cpx _nstation
        jeq @done
        lda st_ly,x
        sec
        sbc _view_y
        cmp _view_ch
        jcs @next
        asl a
        clc
        adc _view_sy
        adc #VIEW_TOP
        asl a
        tay
        lda _scr_row,y
        clc
        adc _view_sx
        sta lb_ro
        lda _scr_row+1,y
        adc #0
        sta lb_ro+1
        jsr st_ptr
        ldy #$FF
:       iny
        lda (tp),y
        bne :-
        sty lb_n
        lda #$FF
        sta lb_j
@k:     lda lb_j                ; the cell: lx + k / 2, rounded down
        cmp #$80
        ror a
        ldx lb_i
        clc
        adc st_lx,x
        sta lb_c
        sec
        sbc _view_x
        cmp _view_cw
        jcs @nk
        asl a
        sta lb_t
        lda lb_j
        and #1
        ora lb_t
        clc
        adc lb_ro
        sta dp
        sta dq
        lda lb_ro+1
        adc #0
        tax
        clc
        adc _scrn+1
        sta dp+1
        txa
        clc
        adc _colr+1
        sta dq+1
        lda lb_j
        bmi @lcap
        cmp lb_n
        beq @rcap
        tay
        lda (tp),y
        jsr sign_of
        jmp @put
@lcap:  lda #SG_LCAP
        bne @end
@rcap:  lda #SG_RCAP
@end:   sta lb_a
        ldx lb_c
        ldy lb_i
        lda st_ly,y
        tay
        jsr cellp
        ldy #0
        lda (mc),y
        cmp #C_FIRST
        bcs @nk
        lda lb_a
@put:   tax
        ldy #0
        lda _sg_top,x
        sta (dp),y
        lda _sg_col
        sta (dq),y
        ldy #40
        lda _sg_bot,x
        sta (dp),y
        lda _sg_col
        sta (dq),y
@nk:    ldx lb_j
        inc lb_j
        cpx lb_n
        jne @k
@next:  inc lb_i
        jmp @st
@done:  rts

; the cell c2_x, c2_y at screen offset cs_o, close up (past the cursor)
cell2:  ldx c2_x
        ldy c2_y
        jsr cellp
        ldy #0
        lda (ma),y
        sta vc_a
        lda (mc),y
        cmp #C_FIRST
        bcc @label
        jsr q4p
        ldy #0
        lda (qp),y
        ldx #0
        jsr vputq
        ldy #1
        lda (qp),y
        ldx #1
        jsr vputq
        ldy #2
        lda (qp),y
        ldx #40
        jsr vputq
        ldy #3
        lda (qp),y
        ldx #41
        jmp vputq
@label: jmp label2

; view_draw: the whole view afresh, from the map (no trains)
view_draw:
        lda #1                  ; the bands afresh for it
        sta bd_dirty
        lda _scrn
        clc
        adc #VIEW_TOP * 40
        sta tp
        lda _scrn+1
        adc #0
        sta tp+1
        lda #<(VIEW_H * 40)
        sta fl_n
        lda #>(VIEW_H * 40)
        sta fl_n+1
        lda #32
        jsr fill
        lda _zoom
        cmp #1
        beq @z1
        lda _view_cw
        sta _r2_n
        lda #0
        sta vd_y
@row:   lda vd_y
        cmp _view_ch
        beq @labels
        clc
        adc _view_y
        sta vd_cy
        tay
        ldx _view_x
        jsr cellp
        lda mc
        sta _r2_code
        lda mc+1
        sta _r2_code+1
        lda ma
        sta _r2_attr
        lda ma+1
        sta _r2_attr+1
        ldx _view_x
        ldy vd_cy
        jsr cell_screen
        sta _r2_o
        stx _r2_o+1
        jsr _eng_row2
        inc vd_y
        bne @row
@labels:
        jmp labels2
@z1:    lda _view_sy
        clc
        adc #VIEW_TOP
        asl a
        tay
        lda _scr_row,y
        clc
        adc _view_sx
        sta dp
        sta dq
        lda _scr_row+1,y
        adc #0
        tax
        clc
        adc _scrn+1
        sta dp+1
        txa
        clc
        adc _colr+1
        sta dq+1
        lda #0
        sta vd_y
@r1:    lda vd_y
        cmp _view_ch
        beq @done
        clc
        adc _view_y
        tay
        ldx _view_x
        jsr cellp
        ldy _view_cw
        dey
@c1:    lda (mc),y
        sta (dp),y
        tax                     ; (a set switch drawn grey or multicolour:
        lda (ma),y              ; q_deco)
        jsr ov_col
        sta (dq),y
        dey
        bpl @c1
        lda dp
        clc
        adc #40
        sta dp
        sta dq
        bcc :+
        inc dp+1
        inc dq+1
:       inc vd_y
        bne @r1
@done:  rts

; view_cell: map cell X, Y drawn again, if it is in view
view_cell:
        stx c2_x
        sty c2_y
        jsr cell_screen
        lda cs_o
        ora cs_o+1
        beq @no
        lda _zoom
        cmp #1
        beq :+
        jmp cell2
:
        ldx c2_x
        ldy c2_y
        jsr cellp
        ldy #0
        lda (ma),y
        sta vc_a
        lda (mc),y
        ldx #0
        jmp vputq               ; (a set switch drawn grey: q_deco)
@no:    rts

; cell_mark: who has cell X, Y now (A, OCC_...), its colour to match, on
; screen if it is in view. A set switch is its ordinary kind again. A train
; coming in changes nothing to be seen: the route's green goes on ahead of
; its front, in that cell, till the front is in the next (cell_under).
cell_mark:
        sta cm_occ
        stx cm_x
        sty cm_y
        jsr cellp
        ldy #0
        lda cm_occ
        sta (mo),y
        bpl cm_look
        rts

; cell_under: cell X, Y, a train's, is behind its front now: the track
; there as it is free, all grey (hires) - the lamp too, red again once the
; train is gone - only where the train's own characters are not
cell_under:
        lda #OCC_TRAIN
        sta cm_occ
        stx cm_x
        sty cm_y
        jsr cellp
cm_look:
        ldy #0
        lda (mc),y
        tax
        lda _code_path,x
        cmp #255
        beq @kind
        lda cm_occ
        cmp #OCC_ROUTE
        beq @kind
        lda #1                  ; a set switch no more: the bands afresh
        sta bd_dirty
        lda _code_mask,x
        sta cf_m
        lda _code_deco,x
        sta cf_d
        jsr code_for
        ldy #0
        sta (mc),y
        tax
        ; a signal or the end of the line: free, its mark red over the grey
        ; track (multicolour); in a route all of it the route's green, under
        ; a train all grey (one colour: hires), the line unbroken
@kind:  lda _code_deco,x
        sta cf_d
        and #DECO_SIGNAL | DECO_END
        beq @col
        ldy #1
        lda cm_occ
        beq :+
        dey
:       sty cf_mc               ; free: 1, a route or a train: 0
        lda _code_mask,x
        sta cf_m
        jsr code_kind
        ldy #0
        sta (mc),y
        tax
@col:   lda code_mc,x           ; (a platform's kind for a route: the
        cmp #2                  ; plain one first, pl_var)
        bne :+
        lda pl_b,x
        tax
        ldy #0
        sta (mc),y
:       lda code_mc,x
        sta cm_mc
        ldy #0
        lda cm_occ
        bmi @train
        cmp #OCC_ROUTE
        bne @free
        lda _zoom
        cmp #1
        bne @rh
        jsr pl_var
        txa
        ldy #0
        sta (mc),y
        lda code_mc,x
        cmp #2
        bne @rh
        lda #COL_ROUTE | 8
        bne :+
@rh:    lda #COL_ROUTE
:       ldy #0
        sta (ma),y
        jmp @view
@free:  lda #COL_TRACK
        ldx cm_mc
        beq :+
        lda #COL_SIG_RED | 8
:       sta (ma),y
@view:  ldx cm_x
        ldy cm_y
        jmp view_cell
@train: lda #COL_TRACK
        sta (ma),y
        inc vc_keep
        ldx cm_x
        ldy cm_y
        jsr view_cell
        dec vc_keep
        rts

; cell_route: cell X, Y is part of a route, which goes in at cr_a and out
; at cr_b; a switch shows which way it is set
cell_route:
        stx cr_x
        sty cr_y
        jsr cellp
        ldy #0
        lda (mc),y
        tax
        lda _code_mask,x
        jsr forks
        bne @fork
        ldx cr_x
        ldy cr_y
        lda #OCC_ROUTE
        jmp cell_mark
@fork:  ldy #0
        lda #OCC_ROUTE
        sta (mo),y
        lda _code_path,x
        cmp #255
        beq :+
        lda _code_mask,x
        sta cf_m
        lda _code_deco,x
        sta cf_d
        jsr code_for
        tax
:       lda _code_mask,x
        sta pk_m
        lda cr_a
        sta pk_a
        lda cr_b
        sta pk_b
        jsr path_kind
        ldy #0
        sta (mc),y
        lda #COL_ROUTE
        sta (ma),y
        lda #1                  ; the bands afresh
        sta bd_dirty
        ldx cr_x
        ldy cr_y
        jmp view_cell
