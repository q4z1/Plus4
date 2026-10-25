; engine.s - the Plus/4 end of Simple Soccer: the pictures, the
; interrupt, the joystick
;
; Three pictures, each a colour matrix, a code matrix and a character set
; of its own: one is shown, one finished may wait to be, and the third is
; drawn. The interrupt puts a waiting picture on screen in the vertical
; blank, together with the fine scroll it was drawn for - PACE frames
; after the last at the earliest (game.inc: 3, an even 16.7 pictures a
; second; build.sh's PACE=2 for 25). The game draws on as soon as a
; picture is handed over, and waits only while one is still waiting: a
; picture that costs more than PACE frames borrows from the one before.
;
; The ground (data/pitch.txt) is 79 x 67 cells of 221 different characters,
; more than fit into a set with the figures' beside them. A picture's set
; holds only the ground characters it shows - at most 76 at a time - in
; codes given out as they are first met while the picture is built: a
; cache, one per picture (xlat0-2: the code of each ground character
; in it, 0 none). Code 0 is the grass for good. The codes from POOL on are
; the figures' (fig_draw). A cache that runs into them while a picture is
; built is emptied and the picture built anew (at most 76 ground
; characters: an empty cache cannot fill up).
;
; The view moves a few cells at most between a picture's builds, mostly:
; then the back picture is not built anew but moved over in memory, and
; only the rows and columns that come in are looked up (shift).

        .include "game.inc"
        .include "data.inc"

        .export eng_init, eng_begin, eng_end, eng_wait, fig_draw, joy_read
        .export cam_x, cam_y, frames, joy, dbg_joy
        .export fig_x, fig_y, fig_img, fig_col
        .import _pitch_map, _pitch_font
        .import img_ox, img_oy, img_lo, img_hi, light11
        .import crow_of, cmap_lo, cmap_hi

POOL        = 112               ; first code for figures
EVICT_AT    = 86                ; a cache this full gives codes back (evict)
STRIP       = 32                ; a figure's column: four cells at most
MOVE_U      = 16                ; bytes a turn when the codes are moved
VBL_LINE    = 205               ; the interrupt: below the picture

        .zeropage
z_map:      .res 2              ; the ground row being copied
z_scr:      .res 2              ; the code matrix row it goes to
z_src:      .res 2
z_dst:      .res 2
z_t:        .res 1
z_t2:       .res 1
z_row:      .res 1
z_n:        .res 1
z_mb:       .res 2              ; the ground cell at the picture's top left
z_att:      .res 2              ; a cell's colour
z_fnt:      .res 2              ; a character's pixels
z_atthi:    .res 1              ; the back picture: its colour matrix,
z_fnthi:    .res 1              ;   its characters
z_lst:      .res 1              ; the next entry in its list
z_sp:       .res 1              ; the stack in eng_begin, for full
z_dc:       .res 1              ; the view's move since the back picture
z_dr:       .res 1              ;   was built, in cells (signed)
z_cnt:      .res 1              ; shift's: pages to move
z_k:        .res 1              ; shift's: rows or columns coming in
z_c:        .res 1              ; fill_col's column; fig_draw's, from 0
; fig_draw's
z_mx:       .res 2              ; left edge, multicolour pixels
z_ty:       .res 2              ; top, lines
z_cx:       .res 1              ; cell of its current column
z_cy:       .res 1              ; and its top row
z_l0:       .res 1              ; its top line in that cell
z_rec:      .res 2              ; the image record
z_dat:      .res 2              ; the current column's pixels
z_ncol:     .res 1
z_h:        .res 1
z_col:      .res 1
z_r:        .res 1
z_y0:       .res 1              ; a column: the line in its first cell,
z_nc:       .res 1              ;   its cells,
z_c0:       .res 1              ;   their first code,
z_cc:       .res 1              ; a cell's code
z_i:        .res 1              ; and its number in the column
z_mix:      .res 1              ; bit 7: a cell showed more than grass
z_grass:    .res 1              ; a bit for each cell to be cleared
z_d:        .res 2              ; the column's pixels, less its first line
z_kp:       .res 2              ; and its bits to keep
z_cd:       .res 2              ; the column's record
z_rmp:      .res 1              ; bit 7: the cell's white turns light
z_kc0:      .res 1              ; the column's cells with pixels in the
z_kc1:      .res 1              ;   cell's colour, in the strip
z_kk:       .res 1              ; the cell's in the strip
z_ev:       .res 1              ; bit 7: the back picture's cache gives back
z_fn:       .res 1              ; evict's
z_cl:       .res 1              ; the next code in the picture's page
z_ci:       .res 1              ; restore's: the next code to put back
z_yy:       .res 1              ; a cell's place below the column's first
z_ix:       .res 1
z_cl0:      .res 1              ; a figure's first cell in the list
z_k0:       .res 1              ; a column's cells on the picture: the first,
z_k1:       .res 1              ;   past the last
z_x0:       .res 1              ;   the first's place in the list
z_ro:       .res 1              ; the row of the column's first cell in it

        .bss
frames:     .res 1              ; pictures shown, 50 a second
joy:        .res 1              ; J_ bits, joy_read's
dbg_joy:    .res 1              ; J_ bits held for joy_read by a test
back:       .res 1              ; the picture being drawn: 0, 1 or 2
shown:      .res 1              ; the one on screen, $FF none yet
queued:     .res 1              ; the one finished, waiting; $FF none
since:      .res 1              ; frames since the last was put on screen
ctrl2:      .res 1              ; $FF07 as the game wants it, without the
                                ; fine scroll
cam_x:      .res 2              ; the view's top left corner on the
cam_y:      .res 2              ; ground, in pixels (the game's)
col0:       .res 1              ; it as cells and fine scroll
row0:       .res 1
fx:         .res 1
fy:         .res 1
; per picture
b_col:      .res 3              ; ground cell at its top left, $FF none
b_row:      .res 3
b_fx:       .res 3              ; what the interrupt sets for it
b_fy:       .res 3
b_next:     .res 3              ; next code never given out in its set
fl_n:       .res 3              ; codes given back, in its fl
b_nlist:    .res 3              ; figures in its list
since_full: .res 1              ; turns since a picture was built anew
tc_col:     .res 3              ; tint's: each picture's col0 when tinted,
tc_row:     .res 3 * SCR_H      ; and each of its rows' ground row's
                                ; colours (crow_of), $FF white
z_tr:       .res 1              ; (the row tinting, its place in tc_row)
z_ti:       .res 1
pool_next:  .res 1              ; next code for a figure, 0 when used up
fig_x:      .res 2              ; fig_draw's figure: on the ground,
fig_y:      .res 2              ; its sprite's top left corner
fig_img:    .res 1
fig_col:    .res 1              ; its cells' colour

        .segment "LISTS"
; the cells each picture's figures took, a figure at a time: the place in
; the matrix of its top left cell (signed: it may be off the picture), its
; cells, where they start in the picture's pages - their places from
; there (40 * row + column) and the codes they showed before. Picture p's
; figures from p * 85.
l_lo:       .res 256
l_hi:       .res 256
l_n:        .res 256
l_ci:       .res 256
codes:      .res 3 * 256
offs:       .res 3 * 256

        .segment "HIBSS"
xlat0:      .res 256
xlat1:      .res 256
xlat2:      .res 256
fl0:        .res 256            ; each picture's codes given back (evict)
fl1:        .res 256
fl2:        .res 256
used:       .res 256            ; evict's: the codes a matrix shows

        .code

; ---- set-up ---------------------------------------------------------------

eng_init:
        sei
        lda #0
        sta TED_IRQEN
        lda TED_IRQ
        sta TED_IRQ
        lda TED_SCROLLY         ; blank till the first picture is swapped in
        and #$EF
        sta TED_SCROLLY
        lda TED_CTRL2
        and #$40                ; keep PAL/NTSC
        ora #$90                ; 256 characters, multicolour, 38 columns
        sta ctrl2
        lda TED_BMBASE
        and #$FB                ; characters from RAM
        sta TED_BMBASE
        lda #COL_GRASS
        sta TED_BG
        lda #COL_SKIN
        sta TED_COL1
        lda #COL_BLACK
        sta TED_COL2
        sta TED_BORDER
        ; the colour matrices white multicolour, the caches empty with
        ; the grass in code 0
        ldx #0
:       lda #COL_LINE
        sta MAT0,x
        sta MAT0 + $100,x
        sta MAT0 + $200,x
        sta MAT0 + $300,x
        sta MAT1,x
        sta MAT1 + $100,x
        sta MAT1 + $200,x
        sta MAT1 + $300,x
        sta MAT2,x
        sta MAT2 + $100,x
        sta MAT2 + $200,x
        sta MAT2 + $300,x
        lda #0
        sta xlat0,x
        sta xlat1,x
        sta xlat2,x
        inx
        bne :-
        ldx #7
:       lda _pitch_font,x
        sta FNT0,x
        sta FNT1,x
        sta FNT2,x
        dex
        bpl :-
        ldx #2
:       lda #1
        sta b_next,x
        lda #$FF
        sta b_col,x
        sta tc_col,x
        dex
        bpl :-
        ldx #3 * SCR_H - 1      ; (the matrices all white)
:       sta tc_row,x
        dex
        bpl :-
        sta shown
        sta queued
        lda #2
        sta since
        lda #<irq
        sta $FFFE
        lda #>irq
        sta $FFFF
        lda #<nmi
        sta $FFFA
        lda #>nmi
        sta $FFFB
        lda #VBL_LINE
        sta TED_RCMP
        lda #$02                ; raster interrupt, compare bit 8 = 0
        sta TED_IRQEN
        cli
        rts

nmi:    rti

; ---- the interrupt: in the vertical blank, a finished picture in --------

irq:    pha
        txa
        pha
        lda TED_IRQ
        sta TED_IRQ
        inc frames
        inc since
        ldx queued
        bmi @done               ; (none waiting)
        lda since
        cmp #PACE
        bcc @done               ; (the last too short a while ago)
        lda vm_of,x
        sta TED_VMBASE
        lda TED_CHBASE
        and #$03
        ora ch_of,x
        sta TED_CHBASE
        lda ctrl2
        ora b_fx,x
        sta TED_CTRL2
        lda #$10                ; on, text, 24 rows
        ora b_fy,x
        sta TED_SCROLLY
        stx shown
        lda #$FF
        sta queued
        lda #0
        sta since
@done:  pla
        tax
        pla
        rti

vm_of:  .byte >MAT0, >MAT1, >MAT2
ch_of:  .byte >FNT0, >FNT1, >FNT2

; eng_wait: till the picture handed over is on screen
eng_wait:
:       lda queued
        bpl :-
        rts

; ---- building a picture ---------------------------------------------------
;
; eng_begin starts the back picture for the view at cam_x, cam_y: its cells
; built anew when the view has moved by a whole cell since this picture
; was last built, else only the cells figures took put back. Then the
; game draws its figures (fig_draw), and eng_end hands the picture over:
; it is shown at the next vertical blank.

eng_begin:
        ; the view as cells and fine scroll: cell = pixel / 8, and the
        ; scroll registers move the picture right / down by 7 - pixel % 8
        lda cam_x + 1
        sta z_t
        lda cam_x
        tax
        and #7
        eor #7
        sta fx
        txa
        lsr z_t
        ror a
        lsr z_t
        ror a
        lsr z_t
        ror a
        sta col0
        lda cam_y + 1
        sta z_t
        lda cam_y
        tax
        and #7
        eor #7
        sta fy
        txa
        lsr z_t
        ror a
        lsr z_t
        ror a
        lsr z_t
        ror a
        sta row0

        ; the picture to draw: neither the one shown nor the one waiting
        sei
        ldx #0
:       cpx shown
        beq :+
        cpx queued
        bne :++
:       inx
        bne :--
:       cli
        stx back
        ; the code below for the back picture: its cache, its matrices,
        ; its characters, its list
        lda xlat_hi,x
        sta cl_look + 2
        sta al_put + 2
        sta fc_look + 2
        sta ev_look + 2
        sta ev_clr + 2
        lda fl_hi,x
        sta al_fl + 2
        sta ev_push + 2
        lda xlat_hi,x
        lda codes_hi,x          ; (its pages of the cells' places, codes)
        sta pc_code + 2
        sta pm_code + 2
        sta rs_code + 2
        lda offs_hi,x
        sta pc_offs + 2
        sta rs_offs + 2
        lda fnt_hi,x
        sta al_font
        sta z_fnthi
        lda mat_hi,x
        sta z_atthi
        lda fx
        sta b_fx,x
        lda fy
        sta b_fy,x
        tsx                     ; alloc's way out when the cache is full
        stx z_sp
        lda since_full          ; turns since a cache gave codes back
        cmp #255
        beq :+
        inc since_full
:       lda #0                  ; a cache filling up gives back the codes
        sta z_ev                ; its picture does not show (evict), before
        ldx back                ; it runs full - not two turns running
        lda b_next,x
        clc
        sbc fl_n,x              ; (codes in it: next - 1 - given back)
        cmp #EVICT_AT
        bcc :+
        lda since_full
        cmp #3
        bcc :+
        lda #$80
        sta z_ev
:       ldx back
        lda col0
        sec
        sbc b_col,x
        sta z_dc
        lda row0
        sec
        sbc b_row,x
        sta z_dr
        ora z_dc
        bne @moved
        jsr mapbase             ; the same cells: the figures' put back
        sec
        jsr restore
        bit z_ev
        bpl :+
        jsr evict
:       jmp eng_pool
@moved: lda b_col,x             ; three cells off at most, either way:
        cmp #$FF                ; the old picture moved over (shift)
        beq @far
        lda z_dc
        clc
        adc #3
        cmp #7
        bcs @far
        lda z_dr
        clc
        adc #3
        cmp #7
        bcs @far
        jsr shift
        jmp eng_pool
@far:   jsr mapbase             ; else built anew; the figures' colours
        clc                     ; back first
        jsr restore
        bit z_ev                ; (built anew anyway: the cache emptied)
        bpl :+
        ldx back
        jsr flush
        lda #0
        sta since_full
:       jsr cells
eng_pool:
        jsr tint
        lda #POOL
        sta pool_next
        ldx back
        lda lst_base,x
        sta z_lst
        lda #0
        sta z_cl
        rts

; tint: the back picture's cells their own colours where the ground has
; them (the crowd's shirts, the boards: mkdata's colour rows), white
; elsewhere - only the rows whose colours its view changed since it was
; last tinted. No figure gets into those rows (the players keep inside
; the walls), so restore can put white back.
tint:
        ldx back
        lda tc_base,x
        sta z_ti
        lda #0
        sta z_tr
@row:   lda row0
        clc
        adc z_tr
        tay
        lda crow_of,y           ; the colours it wants
        ldx z_ti
        cmp #$FF
        bne @own
        cmp tc_row,x            ; white, and white already
        beq @next
        sta tc_row,x
        jsr @dst
        lda #COL_LINE
        ldy #SCR_W - 1
:       sta (z_dst),y
        dey
        bpl :-
        bmi @next
@own:   cmp tc_row,x            ; its own: the same, and the view not moved
        bne @copy               ; across
        ldy back
        lda tc_col,y
        cmp col0
        beq @next
        lda tc_row,x
@copy:  sta tc_row,x
        tay
        lda cmap_lo,y
        clc
        adc col0
        sta z_src
        lda cmap_hi,y
        adc #0
        sta z_src + 1
        jsr @dst
        ldy #SCR_W - 1
:       lda (z_src),y
        sta (z_dst),y
        dey
        bpl :-
@next:  inc z_ti
        inc z_tr
        lda z_tr
        cmp #SCR_H
        bne @row
        ldx back
        lda col0
        sta tc_col,x
        rts
@dst:   ldy z_tr                ; z_dst = the row in the colour matrix
        lda r40_lo,y
        sta z_dst
        lda r40_hi,y
        clc
        adc z_atthi
        sta z_dst + 1
        rts

tc_base:    .byte 0, SCR_H, 2 * SCR_H
r40_lo:
        .repeat SCR_H, I
        .byte <(I * SCR_W)
        .endrepeat
r40_hi:
        .repeat SCR_H, I
        .byte >(I * SCR_W)
        .endrepeat

; full: alloc's way out when the cache ran into the pool during a build
; (the stack as eng_begin had it): the cache emptied, the cells built anew
; - from an empty cache they cannot fill it
full:   ldx z_sp
        txs
full_now:
        lda #0
        sta since_full
        ldx back
        jsr flush
        jsr mapbase
        jsr cells
        jmp eng_pool

; eng_end: the picture handed over, once the last is on screen
eng_end:
        ldx back                ; the columns its figures took
        lda z_lst
        sec
        sbc lst_base,x
        sta b_nlist,x
:       lda queued
        bpl :-
        stx queued
        rts

; mapbase: z_mb = the ground cell at row0, col0
;        = the ground + row0 * 79 + col0 = row0 * 80 - row0 + col0
mapbase:
        lda row0
        sta z_mb
        lda #0
        sta z_mb + 1
        ldy #4
:       asl z_mb
        rol z_mb + 1
        dey
        bne :-
        lda z_mb                ; * 16, then * 5
        ldy z_mb + 1
        asl z_mb
        rol z_mb + 1
        asl z_mb
        rol z_mb + 1
        clc
        adc z_mb
        sta z_mb
        tya
        adc z_mb + 1
        sta z_mb + 1
        lda z_mb
        sec
        sbc row0
        sta z_mb
        bcs :+
        dec z_mb + 1
:       lda z_mb
        clc
        adc col0
        sta z_mb
        bcc :+
        inc z_mb + 1
:       lda z_mb
        clc
        adc #<_pitch_map
        sta z_mb
        lda z_mb + 1
        adc #>_pitch_map
        sta z_mb + 1
        rts

; restore: the cells the back picture's figures took, from its list,
; the last figure first (a cell two figures took is listed for both, the
; later with the earlier's code): their colour back to the ground's, and
; with carry set their codes too
restore:
        ror z_t                 ; bit 7: codes too
        ldx back
        lda b_nlist,x
        beq rs_done
        clc
        adc lst_base,x
        tax                     ; past the last figure
rs_fig: dex
        lda l_lo,x              ; its base
        sta z_att
        sta z_scr
        lda l_hi,x
        clc
        adc z_atthi
        sta z_att + 1
        clc
        adc #4
        sta z_scr + 1
        lda l_ci,x
        sta z_ci
        lda l_n,x
        sta z_n
rs_cell:
        ldy z_ci
rs_offs = *
        lda offs,y              ; (the picture's page)
        sta z_yy
rs_code = *
        lda codes,y             ; (the picture's page)
        ldy z_yy
        bit z_t
        bpl :+
        sta (z_scr),y
:       lda #COL_LINE
        sta (z_att),y
        inc z_ci
        dec z_n
        bne rs_cell
        txa
        ldy back
        cmp lst_base,y
        bne rs_fig
rs_done:
        rts

; cells: the back picture's code matrix, from the ground at col0, row0
cells:
        ldx back
        lda col0
        sta b_col,x
        lda row0
        sta b_row,x
        lda z_mb
        sta z_map
        lda z_mb + 1
        sta z_map + 1
        lda z_atthi
        clc
        adc #4
        sta z_scr + 1
        lda #0
        sta z_scr
        lda #SCR_H
        sta z_row
; cl_rows: z_row rows of cells, from the ground at z_map to the codes at
; z_scr
cl_rows:
cl_row:   ldy #SCR_W - 1
cl_cell:  lda (z_map),y
        tax
cl_look = *
        lda xlat0,x             ; (the picture's cache)
        beq cl_none
cl_put:   sta (z_scr),y
        dey
        bpl cl_cell
        lda z_map
        clc
        adc #MAP_W
        sta z_map
        bcc :+
        inc z_map + 1
:       lda z_scr
        clc
        adc #SCR_W
        sta z_scr
        bcc :+
        inc z_scr + 1
:       dec z_row
        bne cl_row
        rts
cl_none:  cpx #0                  ; the grass: code 0
        beq cl_put
        jsr alloc
        jmp cl_put

; shift: the back picture, built three cells off at most (z_dc, z_dr),
; moved over to col0, row0: the cells its figures took put back where
; they were, the codes moved in memory, the rows and columns coming in
; looked up
shift:
        lda col0                ; put back, at the old place
        pha
        lda row0
        pha
        ldx back
        lda b_col,x
        sta col0
        lda b_row,x
        sta row0
        jsr mapbase
        sec
        jsr restore
        bit z_ev
        bpl :+
        jsr evict
:       pla
        sta row0
        pla
        sta col0
        jsr mapbase
        ldx back
        lda col0
        sta b_col,x
        lda row0
        sta b_row,x
        ; the move in bytes: dr * 40 + dc, -123..123
        lda z_dc
        ldx z_dr
        beq @off
        bmi @up
:       clc
        adc #SCR_W
        dex
        bne :-
        beq @off
@up:    sec
        sbc #SCR_W
        inx
        bne @up
@off:   tax
        beq @edges
        ; the codes: from base + off to base (off > 0), or from base to
        ; base - off (off < 0)
        lda z_atthi
        clc
        adc #4
        sta z_src + 1
        sta z_dst + 1
        lda #0
        sta z_src
        sta z_dst
        txa
        bmi @back
        sta z_src
        jsr move_up
        jmp @edges
@back:  eor #$FF                ; |off|
        clc
        adc #1
        sta z_dst
        jsr move_down
@edges: lda z_dc                ; the columns coming in: the last dc,
        beq @rows               ; or the first -dc
        bmi @left
        sta z_k
:       lda #SCR_W
        sec
        sbc z_k
        jsr fill_col
        dec z_k
        bne :-
        beq @rows
@left:  eor #$FF
        clc
        adc #1
        sta z_k
:       dec z_k
        lda z_k
        jsr fill_col
        lda z_k
        bne :-
@rows:  lda z_dr                ; the rows likewise
        beq @done
        bmi @top
        sta z_k
:       lda #SCR_H
        sec
        sbc z_k
        jsr fill_row
        dec z_k
        bne :-
        rts
@top:   eor #$FF
        clc
        adc #1
        sta z_k
:       dec z_k
        lda z_k
        jsr fill_row
        lda z_k
        bne :-
@done:  rts

; fill_row: row A of the back picture's codes looked up afresh
fill_row:
        tay
        lda row79_lo,y
        clc
        adc z_mb
        sta z_map
        lda row79_hi,y
        adc z_mb + 1
        sta z_map + 1
        lda row40_lo,y
        sta z_scr
        lda row40_hi,y
        clc
        adc z_atthi
        adc #4
        sta z_scr + 1
        lda #1
        sta z_row
        jmp cl_rows

; fill_col: column A of the back picture's codes looked up afresh
fill_col:
        sta z_c
        lda z_mb
        sta z_map
        lda z_mb + 1
        sta z_map + 1
        lda z_atthi
        clc
        adc #4
        sta z_scr + 1
        lda #0
        sta z_scr
        lda #SCR_H
        sta z_row
fc_cell:
        ldy z_c
        lda (z_map),y
        tax
fc_look = *
        lda xlat0,x             ; (the picture's cache)
        bne fc_put
        cpx #0                  ; the grass: code 0
        beq fc_put
        jsr alloc
fc_put: sta (z_scr),y
        lda z_map
        clc
        adc #MAP_W
        sta z_map
        bcc :+
        inc z_map + 1
:       lda z_scr
        clc
        adc #SCR_W
        sta z_scr
        bcc :+
        inc z_scr + 1
:       dec z_row
        bne fc_cell
        rts

; move_up: the codes moved to lower addresses, from z_src to z_dst (the
; matrix), 1024 bytes, the lowest first, MOVE_U a turn. Past the 1000 the
; TED shows it writes into the matrix's unused end, and reads from the
; character set behind it.
move_up:
        ldx #0                  ; the operands' low bytes, once
        ldy #0
:       txa
        clc
        adc z_src
        sta mu_loop + 1,y
        txa
        clc
        adc z_dst
        sta mu_loop + 4,y
        tya
        clc
        adc #6
        tay
        inx
        cpx #MOVE_U
        bne :-
        lda #4
        sta z_cnt
mu_page:                        ; their high bytes, a page at a time
        lda z_src + 1
        .repeat MOVE_U, K
        sta mu_loop + 2 + 6 * K
        .endrepeat
        lda z_dst + 1
        .repeat MOVE_U, K
        sta mu_loop + 5 + 6 * K
        .endrepeat
        ldx #0
        jsr mu_loop
        inc z_src + 1
        inc z_dst + 1
        dec z_cnt
        bne mu_page
        rts
mu_loop:
        .repeat MOVE_U, K
        lda $FF00 + K,x
        sta $FF00 + K,x
        .endrepeat
        txa
        clc
        adc #MOVE_U
        tax
        bne mu_loop
        rts

; move_down: the codes moved to higher addresses, |off| = z_dst's low
; byte up, 1024 bytes into the matrix's four pages from the top down,
; the highest first, MOVE_U a turn. The bytes it puts below |off| in the
; first page are cells of the rows or columns coming in, looked up after.
move_down:
        lda z_dst               ; |off|
        sta z_c
        lda z_src + 1           ; the top page
        clc
        adc #3
        sta z_dst + 1
        lda #4
        sta z_cnt
md_page:                        ; source = destination page - |off|
        lda #0
        sec
        sbc z_c
        sta z_src
        lda z_dst + 1
        sbc #0
        sta z_src + 1
        ldx #MOVE_U - 1         ; operand K: + MOVE_U - 1 - K
        ldy #0
:       txa
        clc
        adc z_src
        sta md_loop + 1,y
        lda z_src + 1
        adc #0
        sta md_loop + 2,y
        txa
        sta md_loop + 4,y
        lda z_dst + 1
        sta md_loop + 5,y
        tya
        clc
        adc #6
        tay
        dex
        bpl :-
        ldx #256 - MOVE_U
        jsr md_loop
        dec z_dst + 1
        dec z_cnt
        bne md_page
        rts
md_loop:
        .repeat MOVE_U, K
        lda $FF00 + MOVE_U - 1 - K,x
        sta $FF00 + MOVE_U - 1 - K,x
        .endrepeat
        txa
        sec
        sbc #MOVE_U
        tax
        bcs md_loop
        rts

xlat_hi: .byte >xlat0, >xlat1, >xlat2
fl_hi:   .byte >fl0, >fl1, >fl2
fnt_hi:  .byte >FNT0, >FNT1, >FNT2
mat_hi:  .byte >MAT0, >MAT1, >MAT2
lst_base: .byte 0, 85, 170
codes_hi: .byte >codes, >(codes + 256), >(codes + 512)
offs_hi:  .byte >offs, >(offs + 256), >(offs + 512)

row40_lo:
        .repeat SCR_H, I
        .byte <(I * SCR_W)
        .endrepeat
row40_hi:
        .repeat SCR_H, I
        .byte >(I * SCR_W)
        .endrepeat
row79_lo:
        .repeat SCR_H, I
        .byte <(I * MAP_W)
        .endrepeat
row79_hi:
        .repeat SCR_H, I
        .byte >(I * MAP_W)
        .endrepeat

; alloc: a code in the back picture's set for ground character X, its
; pixels copied in; the code in A. Keeps Y.
alloc:
        sty z_t
        ldy back
        lda fl_n,y              ; a code given back first, else the next
        beq al_seq              ; never given out
        sec
        sbc #1
        sta fl_n,y
        tay
al_fl = *
        lda fl0,y               ; (the picture's codes given back)
        jmp al_got
al_seq: lda b_next,y
        cmp #POOL
        bcc :+
        jmp full                ; (the cache full: emptied, built anew)
:       pha
        clc
        adc #1
        sta b_next,y
        pla
al_got: pha
al_put = *
        sta xlat0,x             ; (the picture's cache)
        ; source: the ground's character X
        lda #0
        sta z_src + 1
        txa
        asl a
        rol z_src + 1
        asl a
        rol z_src + 1
        asl a
        rol z_src + 1
        adc #<_pitch_font
        sta z_src
        lda z_src + 1
        adc #>_pitch_font
        sta z_src + 1
        ; destination: the set's code
        pla
        pha
        ldx #0
        stx z_dst + 1
        asl a
        rol z_dst + 1
        asl a
        rol z_dst + 1
        asl a
        rol z_dst + 1
        sta z_dst
        lda z_dst + 1
        clc
al_font = * + 1
        adc #>FNT0              ; (the picture's set)
        sta z_dst + 1
        ldy #7
:       lda (z_src),y
        sta (z_dst),y
        dey
        bpl :-
        pla
        ldy z_t
        rts

; evict: the back picture's cache gives back the codes its picture does
; not show: those in its code matrix marked (the figures' cells put back
; first), every character whose code is not among them taken out, its
; code onto the list alloc takes from first. Costs a pass over the
; matrix and the cache - much less than building the picture anew.
evict:
        lda #0
        sta since_full
        ldx #POOL - 1           ; none marked
:       sta used,x
        dex
        bpl :-
        lda z_atthi             ; the codes' four pages
        clc
        adc #4
        sta ev_m0 + 2
        adc #1
        sta ev_m1 + 2
        adc #1
        sta ev_m2 + 2
        adc #1
        sta ev_m3 + 2
        ldy #0
        lda #1
ev_mark:
ev_m0 = *
        ldx $FF00,y
        sta used,x
ev_m1 = *
        ldx $FF00,y
        sta used,x
ev_m2 = *
        ldx $FF00,y
        sta used,x
ev_m3 = *
        ldx $FF00,y
        sta used,x
        iny
        bne ev_mark
        ldx back
        lda fl_n,x
        sta z_fn
        ldx #0
ev_char:
ev_look = *
        ldy xlat0,x             ; (the picture's cache)
        beq ev_next
        lda used,y
        bne ev_next
        lda #0
ev_clr = *
        sta xlat0,x
        tya
        ldy z_fn
ev_push = *
        sta fl0,y               ; (the picture's codes given back)
        inc z_fn
ev_next:
        inx
        bne ev_char
        ldx back
        lda z_fn
        sta fl_n,x
        rts

; flush: the back picture's cache emptied (the grass stays in code 0)
flush:
        lda #1
        sta b_next,x
        lda #0
        sta fl_n,x
        lda xlat_hi,x
        sta @clr + 2
        lda #0
        ldy #0
@clr:   sta xlat0,y
        iny
        bne @clr
        rts

; ---- figures --------------------------------------------------------------
;
; fig_draw puts figure fig_img (tools/mkdata.py's images) into the back
; picture, its sprite's top left corner at fig_x, fig_y on the ground, in
; cells of colour fig_col. Pixels: %01 skin, %10 black, %11 the cell's
; colour (the shirt).
;
; A column of the figure gets as many codes from the pool as it covers
; cells, one after the other: their pixels lie one after the other in the
; character set, a strip, and the column goes into it in one run, its
; lines straight on into the next cell's. Over grass only - the most of
; them - the pixels go straight in and the lines above and below are
; cleared; else what each cell showed is copied into the strip first, the
; ground's character or another figure's (whose cell it takes over: drawn
; later, in front), and the pixels go in through their mask.

fig_draw:
        ; the figure's left edge in multicolour pixels of the picture,
        ; mx = (fig_x - col0 * 8) / 2 + its first column in the sprite
        lda col0
        asl a
        asl a
        sta z_t                 ; col0 * 4: half of col0 * 8
        lda fig_x + 1
        lsr a
        lda fig_x
        ror a                   ; fig_x / 2 (the ground is under 512)
        sec
        sbc z_t
        sta z_mx
        lda #0
        sbc #0
        sta z_mx + 1
        ldx fig_img
        lda img_ox,x
        clc
        adc z_mx
        sta z_mx
        bcc :+
        inc z_mx + 1
:       ; on the picture at all: -12 <= mx < 160
        lda z_mx + 1
        beq fd_xin
        cmp #$FF
        bne fd_out
        lda z_mx
        cmp #$F4
        bcc fd_out
        bcs fd_xok
fd_xin:   lda z_mx
        cmp #SCR_W * 4
        bcs fd_out
fd_xok:   ; the column of its first cell, signed: mx >> 2 (arithmetic)
        lda z_mx + 1
        lsr a
        lda z_mx
        ror a
        cmp #$80
        ror a
        sta z_cx
        ; its top, ty = fig_y - row0 * 8 + its first row in the sprite
        lda row0
        sta z_t
        lda #0
        asl z_t
        rol a
        asl z_t
        rol a
        asl z_t
        rol a
        sta z_t2
        lda fig_y
        sec
        sbc z_t
        sta z_ty
        lda fig_y + 1
        sbc z_t2
        sta z_ty + 1
        lda img_oy,x
        clc
        adc z_ty
        sta z_ty
        bcc :+
        inc z_ty + 1
:       ; on the picture: -24 <= ty < 200
        lda z_ty + 1
        beq fd_yin
        cmp #$FF
        bne fd_out
        lda z_ty
        cmp #$E8
        bcs fd_yok
fd_out:   rts
fd_yin:   lda z_ty
        cmp #SCR_H * 8
        bcs fd_out
fd_yok:   lda z_ty
        and #7
        sta z_l0
        lda z_ty + 1
        lsr a
        lda z_ty
        ror a
        cmp #$80
        ror a
        cmp #$80
        ror a
        sta z_cy
        ; the record for the shift: the number of columns, then per
        ; column its first line, its lines, their pixels, the bits to keep
        lda fig_img
        asl a
        asl a
        sta z_t
        lda z_mx
        and #3
        ora z_t
        tax
        lda img_lo,x
        sta z_dat
        lda img_hi,x
        sta z_dat + 1
        ldy #0
        lda (z_dat),y
        sta z_ncol
        inc z_dat               ; the first column
        bne :+
        inc z_dat + 1
:       ; the figure's base: its top left cell, row cy, column cx, on the
        ; matrix or off it (both signed) - each of its cells is a Y from
        ; there, 40 * its row + its column
        lda z_cy
        clc
        adc #3
        tay                     ; (rows -3 .. 27)
        lda z_cx
        clc
        adc row40s_lo,y
        sta z_att
        sta z_scr
        lda z_cx
        and #$80
        beq :+
        lda #$FF
:       adc row40s_hi,y
        clc
        adc z_atthi
        sta z_att + 1
        clc                     ; (a base above the matrix carries)
        adc #4
        sta z_scr + 1
        ; into the picture's list: the base's place in the matrix, where
        ; its cells start in the picture's pages of places and codes
        ldx z_lst
        lda z_att
        sta l_lo,x
        lda z_att + 1
        sec
        sbc z_atthi
        sta l_hi,x
        lda z_cl
        sta l_ci,x
        sta z_cl0
        lda #0
        sta z_c

fd_col: ldy #1
        lda (z_dat),y
        sta z_h                 ; its lines
        lda z_cx
        clc
        adc z_c
        cmp #SCR_W
        bcc :+
        jmp fd_ncol             ; (off the picture, left or right)
:       dey
        lda (z_dat),y           ; its first line, from the figure's top cell:
        clc                     ; the row of its first cell in the figure,
        adc z_l0                ; and the line in it
        tax
        and #7
        sta z_y0
        txa
        lsr a
        lsr a
        lsr a
        sta z_ro
        ldy #2                  ; its cells with pixels in the cell's colour:
        lda (z_dat),y           ; strip cells kc0 .. kc1 (none: 255, 0)
        cmp #$FF
        beq :+
        clc
        adc z_y0
        lsr a
        lsr a
        lsr a
:       sta z_kc0
        iny
        lda (z_dat),y
        clc
        adc z_y0
        lsr a
        lsr a
        lsr a
        sta z_kc1
        lda z_y0                ; its cells: (y0 + lines + 7) / 8
        clc
        adc z_h
        adc #7
        lsr a
        lsr a
        lsr a
        sta z_nc
        ; its cells on the picture: rows cy + ro + k, k from k0 = -row
        ; (0 at least) to k1 = 25 - row (its cells at most)
        lda z_cy
        clc
        adc z_ro
        sta z_row
        lda #0
        ldx z_row
        bpl :+
        sec
        sbc z_row
:       sta z_k0
        lda #SCR_H
        sec
        sbc z_row
        bmi fd_skip             ; (below the picture)
        cmp z_nc
        bcc :+
        lda z_nc
:       sta z_k1
        cmp z_k0
        beq fd_skip
        bcc fd_skip
        ; as many codes from the pool as it has cells, one after the other
        lda pool_next
        beq fd_skip             ; (used up)
        sta z_c0
        clc
        adc z_nc
        bcc :+
        beq :+                  ; (to the last code exactly)
fd_skip:
        jmp fd_ncol
:       sta pool_next           ; (0: used up)
        ; each cell on the picture: its colour, its new code; what it
        ; showed goes into the list (and the cell's place), and is the
        ; strip's background - grass, else its pixels copied in
        lda z_c0
        clc
        adc z_k0
        sta z_cc
        lda z_k1
        sec
        sbc z_k0
        sta z_n
        lda z_ro
        clc
        adc z_k0
        tax
        lda y40,x
        clc
        adc z_c
        tay
        lda #0
        sta z_mix
        lda z_k0
        sta z_kk
        ldx z_cl                ; (X: the list, Y: the cell)
        stx z_x0
fd_cell:                        ; its colour, where it has pixels in it and
        lda #0                  ; the cell another: he takes it, what is
        sta z_rmp               ; under it in the cell's colour (another
        lda z_kk                ; player's shirt - the ground's white, the
        cmp z_kc0               ; ball's, is in the shared light colour)
        bcc fd_keep             ; turned to the light one
        lda z_kc1
        cmp z_kk
        bcc fd_keep
        lda (z_att),y
        cmp fig_col
        beq fd_keep
        lda #$80
        sta z_rmp
        lda fig_col
        sta (z_att),y
fd_keep:
        lda (z_scr),y
pc_code = *
        sta codes,x             ; (the picture's page)
        bne fd_bg
fd_put: lda z_cc
        sta (z_scr),y
        tya
pc_offs = *
        sta offs,x              ; (the picture's page)
        inx
        inc z_cc
        inc z_kk
        tya
        clc
        adc #SCR_W
        tay
        dec z_n
        bne fd_cell
        stx z_cl
        jmp fd_strip
fd_bg:  stx z_ix                ; more than grass: its pixels into the strip
        sty z_yy
        jsr char_at
        lda z_fnt
        sta z_src
        lda z_fnt + 1
        sta z_src + 1
        lda z_cc
        jsr char_at
        ldy #7
        bit z_rmp
        bmi fd_light
:       lda (z_src),y
        sta (z_fnt),y
        dey
        bpl :-
        bmi fd_copied
fd_light:                       ; (its own colour light)
        lda (z_src),y
        tax
        lda light11,x
        sta (z_fnt),y
        dey
        bpl fd_light
fd_copied:
        lda #$80
        sta z_mix
        ldx z_ix
        ldy z_yy
        jmp fd_put
fd_strip:                       ; the column's record
        lda z_dat
        sta z_cd
        lda z_dat + 1
        sta z_cd + 1
        bit z_mix
        bmi fd_mixed0
        ; all grass: the whole strip straight from the pixels, the empty
        ; lines before and after them included - entered so that it ends
        ; with the block (strip line j at y = j + A, A = 32 - cells * 8):
        ; the strip less A is code c0 + cells - 4's pixels, the pixels
        ; less y0 and A the column's record + 4 + 8 - 32 + cells * 8 - y0
        lda z_c0
        clc
        adc z_nc
        sec
        sbc #4
        jsr char_at
        ldx z_nc
        lda fr_off,x
        sec
        sbc z_y0
        sta z_t                 ; (signed)
        clc
        adc z_cd
        sta z_d
        lda z_t
        and #$80
        beq :+
        lda #$FF
:       adc z_cd + 1
        sta z_d + 1
        lda fbn_lo,x
        sta fd_fcall + 1
        lda fbn_hi,x
        sta fd_fcall + 2
        ldy fy_of,x
fd_fcall:
        jsr fblock
        jmp fd_ncol
fd_mixed0:                      ; the strip; the pixels after the column's
        lda z_c0                ; first line, its lines, eight empty ones
        jsr char_at
        lda z_cd
        clc
        adc #4 + 8
        sta z_d
        lda z_cd + 1
        adc #0
        sta z_d + 1
fd_mixed:                       ; the grass cells on the picture (code 0
        ldx z_x0                ; in the list) cleared, then the column
        lda z_k0                ; through its mask
        asl a
        asl a
        asl a
        sta z_t
fm_cell:
        cpx z_cl
        beq fm_done
pm_code = *
        lda codes,x             ; (the picture's page)
        bne fm_next
        ldy z_t
        .repeat 8
        sta (z_fnt),y
        iny
        .endrepeat
fm_next:
        lda z_t
        clc
        adc #8
        sta z_t
        inx
        bne fm_cell
fm_done:
        ; its lines y0 .. end - 1, ending with the block: A = 32 - lines
        lda z_d                 ; the bits to keep: after the pixels and
        clc                     ; eight empty lines
        adc z_h
        sta z_kp
        lda z_d + 1
        adc #0
        sta z_kp + 1
        lda z_kp
        clc
        adc #8
        sta z_kp
        bcc :+
        inc z_kp + 1
:       lda z_h
        eor #$FF
        sec
        adc #STRIP
        sta z_t                 ; A
        tax
        lda z_d                 ; pixels and bits less A
        sec
        sbc z_t
        sta z_d
        bcs :+
        dec z_d + 1
:       lda z_kp
        sec
        sbc z_t
        sta z_kp
        bcs :+
        dec z_kp + 1
:       lda z_y0                ; the strip from line y0, less A: y0 - A,
        sec                     ; signed, mostly negative
        sbc z_t
        sta z_t2
        clc
        adc z_fnt
        sta z_fnt
        lda z_t2
        and #$80
        beq :+
        lda #$FF
:       adc z_fnt + 1
        sta z_fnt + 1
        lda mb_lo,x
        sta fd_mcall + 1
        lda mb_hi,x
        sta fd_mcall + 2
        txa
        tay
fd_mcall:
        jsr mblock
fd_ncol:                        ; the next column: 4 + 16 + 2 * its lines on
        inc z_c
        lda z_h
        asl a
        adc #4 + 16             ; (carry clear: a column is under 128 lines)
        adc z_dat
        sta z_dat
        bcc :+
        inc z_dat + 1
:       dec z_ncol
        beq :+
        jmp fd_col
:       lda z_cl                ; the figure's cells in the list, if any
        sec
        sbc z_cl0
        beq :+
        ldx z_lst
        sta l_n,x
        inc z_lst
:       rts

y40:    .byte 0, 40, 80, 120, 160, 200
; by a column's cells (1-4): where fblock is entered, its first y, the
; pixels' place against the record's
fbn_lo:
        .repeat 5, I
        .byte <(fblock + 5 * (STRIP - 8 * I))
        .endrepeat
fbn_hi:
        .repeat 5, I
        .byte >(fblock + 5 * (STRIP - 8 * I))
        .endrepeat
fy_of:
        .repeat 5, I
        .byte STRIP - 8 * I
        .endrepeat
fr_off:
        .repeat 5, I
        .byte <(4 + 8 - STRIP + 8 * I)
        .endrepeat
row40s_lo:                      ; rows -3 .. 27, times 40
        .repeat 31, I
        .byte <((I - 3) * SCR_W)
        .endrepeat
row40s_hi:
        .repeat 31, I
        .byte >((I - 3) * SCR_W)
        .endrepeat

bit_of: .byte 1, 2, 4, 8

; fblock, mblock: lines of a strip at z_fnt from y on to its end, the
; strip's last line (31) - straight from the pixels at z_d, or through
; the mask: what is there, the bits at z_kp, the pixels at z_d. Entered at
; the first line's entry (fb_*, mb_*).
fblock:
        .repeat STRIP
        lda (z_d),y
        sta (z_fnt),y
        iny
        .endrepeat
        rts
mblock:
        .repeat STRIP
        lda (z_fnt),y
        and (z_kp),y
        ora (z_d),y
        sta (z_fnt),y
        iny
        .endrepeat
        rts
fb_lo:
        .repeat STRIP + 1, I
        .byte <(fblock + 5 * I)
        .endrepeat
fb_hi:
        .repeat STRIP + 1, I
        .byte >(fblock + 5 * I)
        .endrepeat
mb_lo:
        .repeat STRIP + 1, I
        .byte <(mblock + 9 * I)
        .endrepeat
mb_hi:
        .repeat STRIP + 1, I
        .byte >(mblock + 9 * I)
        .endrepeat

; char_at: z_fnt = the pixels of code A in the back picture's set
char_at:
        tay
        lda chr_lo,y
        sta z_fnt
        lda chr_hi,y
        clc
        adc z_fnthi
        sta z_fnt + 1
        rts

chr_lo:                         ; code * 8
        .repeat 256, I
        .byte <(I * 8)
        .endrepeat
chr_hi:
        .repeat 256, I
        .byte >(I * 8)
        .endrepeat

; ---- input ----------------------------------------------------------------

; joy_read: both joysticks, the cursor keys and the space bar into joy.
; A row goes to both latches and $FF08 is read twice: the first read
; still sees the value written.
joy_read:
        sei
        lda #$FF
        sta KEY_ROW
        lda #$FB                ; joystick 1: fire is bit 6
        sta TED_KEYS
        lda TED_KEYS
        lda TED_KEYS
        eor #$FF
        tax
        and #$0F
        sta joy
        txa
        and #$40
        beq :+
        lda #J_FIRE
        ora joy
        sta joy
:       lda #$FD                ; joystick 2: fire is bit 7
        sta TED_KEYS
        lda TED_KEYS
        lda TED_KEYS
        eor #$FF
        tax
        and #$0F
        ora joy
        sta joy
        txa
        and #$80
        beq :+
        lda #J_FIRE
        ora joy
        sta joy
:       lda #$BF                ; cursor left (bit 0), right (bit 3)
        jsr krow
        lsr a
        bcc :+
        pha
        lda #J_LEFT
        ora joy
        sta joy
        pla
:       and #$04
        beq :+
        lda #J_RIGHT
        ora joy
        sta joy
:       lda #$DF                ; cursor down (bit 0), up (bit 3)
        jsr krow
        lsr a
        bcc :+
        pha
        lda #J_DOWN
        ora joy
        sta joy
        pla
:       and #$04
        beq :+
        lda #J_UP
        ora joy
        sta joy
:       lda #$7F                ; space (bit 4)
        jsr krow
        and #$10
        beq :+
        lda #J_FIRE
        ora joy
        sta joy
:       lda #$FF
        sta KEY_ROW
        sta TED_KEYS
        lda joy
        ora dbg_joy
        sta joy
        cli
        rts

; krow: keyboard row A, its keys held as bits set
krow:   sta KEY_ROW
        sta TED_KEYS
        lda TED_KEYS
        lda TED_KEYS
        eor #$FF
        rts
