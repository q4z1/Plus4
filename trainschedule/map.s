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
        .export code_kind, code_mc, cf_m, cf_d, cf_mc, cs_o, cr_a, cr_b, bitv
        .exportzp mc, ma, mo, lp, fp

        .import _vput, _vget, _vp_o, _vp_c, _vp_a, _pool_end
        .import _eng_row2, _r2_o, _r2_code, _r2_attr, _r2_n
        .import _scrn, _colr, _tz_q, _tz_n1, _tz_sh, _tz_edge, _eng_tzsetup
        .import _grey
        .import glyphs_make, _sg_top, _sg_bot, _sg_col, sign_of
        .import _strip, _lamp, _bar, _gate, _digit, _mc_of, _tk_edge
        .import _strip2, _lamp2, _bar2, _gate2, _tk2_edge

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
; close up, by character: 1 for a quarter with nothing but a platform's
; edge and number in it. It shows in the track's grey whatever the colour of
; its cell (a route's, a signal's) - the track it goes with keeps to the
; other quarters (tools/mklevel.py).
_q_deco:    .res 256
_pool_first: .res 1             ; the first character for the trains
st_lx:      .res MAX_STATIONS   ; the stations' labels
st_ly:      .res MAX_STATIONS
plain:     .res 256            ; the kind of a plain track, by its bits
next_code:  .res 1              ; the next kind
next_q:     .res 1              ; close up: the next quarter
cellbuf:    .res 64             ; a cell's pixels being made (the quarters
                                ; top left, top right, bottom left, bottom
                                ; right); 32 on, a set switch's other leg

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
qo_m:       .res 1
t_strip:    .res 2              ; the glyph tables of the size now (make)
t_lamp:     .res 2
t_bar:      .res 2
t_gate:     .res 2
px_b:       .res 1
px_o:       .res 1
ps_a:       .res 1
ps_b:       .res 1
ps_t:       .res 1
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
; in the cell's own colour, its other leg grey (multicolour, engine.s sets
; multicolour 2 grey). code_path: the way, a + 16 * b, or 255 for an
; ordinary kind.
_code_path: .res 256

        .bss
; 1 for a kind in multicolour: the track grey (%10) and the mark - a
; signal's lamp, the bar where the line ends - in the cell's own colour
; (%11), red or green; the track keeps its grey. Also the kinds made from
; them without the mark, which stand in for them when the marks blink.
code_mc:    .res 256
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
        ldy #63
:       sta cellbuf,y
        dey
        bpl :-
        lda _code_path,x
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
:       lda cellbuf,y
        and #$C1
        sta cellbuf,y
        dey
        bpl :-
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
        lda mk_qs
        eor #$FF
        and qo_m
        sta mk_qd
        jmp quarters
:
        lda mk_c                ; the overview: the character itself
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
        bne @put
@look:  lda #C_FIRST
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
        lda mk_k
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
        lda next_q
        jsr grey_of
        lda next_q
        inc next_q
@put:   ldy mk_q
        sta (qp),y
        cmp #C_FIRST
        bcc :+
        tax
        lda mk_qd
        and bitv,y
        beq :+
        lda #1
        sta _q_deco,x
:       inc mk_q
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

; path_split: a set switch (kind mk_c, bits mk_mask): its way %11 (the
; cell's own colour), the rest %10, in cellbuf
path_split:
        ldx mk_c
        lda _code_path,x
        and #15
        sta ps_a
        lda _code_path,x
        lsr a
        lsr a
        lsr a
        lsr a
        sta ps_b
        lda #0
        ldy #31
:       sta cellbuf+32,y
        dey
        bpl :-
        settb t_strip
        lda #0
        sta mk_d
@d:     ldx mk_d
        lda mk_mask
        and bitv,x
        beq @nd
        lda #32                 ; the other leg to cellbuf + 32
        cpx ps_a
        beq @way
        cpx ps_b
        bne @leg
@way:   lda #0
@leg:   sta mk_dst
        txa
        jsr orbuf
@nd:    inc mk_d
        lda mk_d
        cmp #8
        bne @d
        lda #0
        sta mk_dst
        ldy mk_n
        dey
@mix:   ldx cellbuf,y
        lda _mc_of,x
        sta ps_t
        ldx cellbuf+32,y
        lda ps_t
        eor #$FF
        and _mc_of,x
        and #$AA
        ora ps_t
        sta cellbuf,y
        dey
        bpl @mix
        rts

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
        jsr zoom_tables
        jmp view_size

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
        tay
        lda _q_deco,y
        beq :+
        lda vc_a                ; (a multicolour cell's grey is %10)
        and #8
        ora #COL_TRACK
        jmp vput1
:       lda vc_a
        jmp vput1

; vputo: character A in colour vc_a at cs_o + X, past the pointer (vput)
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
; past the pointer: both its halves, both rows (signs.s). Half h of the
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
; afresh, the pointer locked out): the signs, half k of a label in half
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

; the cell c2_x, c2_y at screen offset cs_o, close up (past the pointer)
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
:       lda (mc),y
        sta (dp),y
        lda (ma),y
        sta (dq),y
        dey
        bpl :-
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
        jmp vputo
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
@col:   lda code_mc,x
        sta cm_mc
        ldy #0
        lda cm_occ
        bmi @train
        cmp #OCC_ROUTE
        bne @free
        lda #COL_ROUTE
        sta (ma),y
        bne @view
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
        lda #COL_ROUTE | 8      ; multicolour
        sta (ma),y
        ldx cr_x
        ldy cr_y
        jmp view_cell
