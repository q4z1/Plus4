; engine.s - the Plus/4 end of the soccer game: the pictures, the
; interrupt, the joystick
;
; Three pictures, each a colour matrix, a code matrix and a character set
; of its own: one is shown, one finished may wait to be, and the third is
; drawn. The interrupt puts a waiting picture on screen in the vertical
; blank, together with the fine scroll it was drawn for - two frames after
; the last at the earliest, so that they come at an even 25 a second. The
; game draws on as soon as a picture is handed over, and waits only while
; one is still waiting: a picture that costs more than two frames borrows
; from the one before.
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
        .import img_ox, img_oy, img_lo, img_hi

POOL        = 112               ; first code for figures
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
z_c:        .res 1              ; fill_col's column
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
z_line:     .res 1
z_end:      .res 1              ; the line below the figure's in this cell
z_fresh:    .res 1              ; pool_char: a new character for grass,
                                ; not cleared

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
b_next:     .res 3              ; next free code in its set
b_nlist:    .res 3              ; cells its figures took
pool_next:  .res 1              ; next code for a figure, 0 when used up
fig_x:      .res 2              ; fig_draw's figure: on the ground,
fig_y:      .res 2              ; its sprite's top left corner
fig_img:    .res 1
fig_col:    .res 1              ; its cells' colour

        .segment "LISTS"
lists:      .res 3 * $300       ; the cells each picture's figures took, three
                                ; pages a picture: their places in the
                                ; matrix (low, high bytes), their codes

        .segment "HIBSS"
xlat0:      .res 256
xlat1:      .res 256
xlat2:      .res 256

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
        cmp #2
        bcc @done               ; (the last only a frame ago)
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
        lda lst_hi,x            ; (its list: places, then codes)
        sta pc_lo + 2
        sta rs_lo + 2
        clc
        adc #1
        sta pc_hi + 2
        sta rs_hi + 2
        adc #1
        sta pc_cd + 2
        sta rs_cd + 2
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
        ldx back
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
        jmp eng_pool
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
        jsr cells
eng_pool:
        lda #POOL
        sta pool_next
        lda #0
        sta z_lst
        rts

; full: alloc's way out when the cache ran into the pool during a build
; (the stack as eng_begin had it): the cache emptied, the cells built anew
; - from an empty cache they cannot fill it
full:   ldx z_sp
        txs
        ldx back
        jsr flush
        jsr mapbase
        jsr cells
        jmp eng_pool

; eng_end: the picture handed over, once the last is on screen
eng_end:
        ldx back                ; the cells its figures took
        lda z_lst
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

; restore: the cells the back picture's figures took, from its list: their
; colour back to the ground's, and with carry set their codes too (the
; ground's, as the list keeps them)
restore:
        ldx back
        lda b_nlist,x
        beq rs_done
        sta z_n
        ror z_t                 ; bit 7: codes too
        ldx #0
rs_next:
rs_lo = *
        lda lists,x             ; (the picture's list: the cell's place
        sta z_att               ; in the matrix)
        sta z_scr
rs_hi = *
        lda lists + $100,x
        ora z_atthi
        sta z_att + 1
        ora #4
        sta z_scr + 1
        ldy #0
        lda #COL_LINE
        sta (z_att),y
        bit z_t
        bpl rs_skip
rs_cd = *
        lda lists + $200,x      ; (its code)
        sta (z_scr),y
rs_skip:
        inx
        dec z_n
        bne rs_next
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
        pla
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
; matrix), 1024 bytes, the lowest first, eight a turn. Past the 1000 the
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
        cpx #8
        bne :-
        lda #4
        sta z_cnt
mu_page:                        ; their high bytes, a page at a time
        lda z_src + 1
        .repeat 8, K
        sta mu_loop + 2 + 6 * K
        .endrepeat
        lda z_dst + 1
        .repeat 8, K
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
        .repeat 8, K
        lda $FF00 + K,x
        sta $FF00 + K,x
        .endrepeat
        txa
        clc
        adc #8
        tax
        bne mu_loop
        rts

; move_down: the codes moved to higher addresses, |off| = z_dst's low
; byte up, 1024 bytes into the matrix's four pages from the top down,
; the highest first, eight a turn. The bytes it puts below |off| in the
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
        ldx #7                  ; operand K: + 7 - K
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
        ldx #248
        jsr md_loop
        dec z_dst + 1
        dec z_cnt
        bne md_page
        rts
md_loop:
        .repeat 8, K
        lda $FF00 + 7 - K,x
        sta $FF00 + 7 - K,x
        .endrepeat
        txa
        sec
        sbc #8
        tax
        bcs md_loop
        rts

xlat_hi: .byte >xlat0, >xlat1, >xlat2
fnt_hi:  .byte >FNT0, >FNT1, >FNT2
mat_hi:  .byte >MAT0, >MAT1, >MAT2
lst_hi:  .byte >lists, >(lists + $300), >(lists + $600)

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
        lda b_next,y
        cmp #POOL
        bcc :+
        jmp full                ; (the cache full: emptied, built anew)
:       pha
al_put = *
        sta xlat0,x             ; (the picture's cache)
        clc
        adc #1
        sta b_next,y
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

; flush: the back picture's cache emptied (the grass stays in code 0)
flush:
        lda #1
        sta b_next,x
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
; cells of colour fig_col. A cell it covers gets a character of its own
; from the pool, the ground's character copied into it, and the figure
; goes in through a mask; a cell another figure has already taken is drawn
; into again and gets this one's colour: figures drawn later are in front.
; Pixels: %01 skin, %10 black, %11 the cell's colour (the shirt).

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
        bne fd_col
        inc z_dat + 1

fd_col: ldy #1
        lda (z_dat),y
        sta z_h
        lda z_cx
        cmp #SCR_W
        bcc :+
        jmp fd_ncol             ; (off the picture, left or right)
:       sta z_col
        dey
        lda (z_dat),y           ; its first line: the cell and the line in it
        clc
        adc z_l0
        tax
        and #7
        sta z_line
        txa
        lsr a
        lsr a
        lsr a
        clc
        adc z_cy
        sta z_r
        lda z_dat               ; its pixels, then the bits to keep
        clc
        adc #2
        sta fd_dat + 1
        sta fd_dat2 + 1
        lda z_dat + 1
        adc #0
        sta fd_dat + 2
        sta fd_dat2 + 2
        lda fd_dat + 1
        clc
        adc z_h
        sta fd_keep + 1
        lda fd_dat + 2
        adc #0
        sta fd_keep + 2
        ldx #0                  ; the column's line
fd_cell:                        ; lines in this cell: up to its bottom, up
        lda #8                  ; to the column's
        sec
        sbc z_line
        sta z_n
        txa
        clc
        adc z_n
        cmp z_h
        bcc :+
        lda z_h
        stx z_t
        sec
        sbc z_t
        sta z_n
:       lda z_r
        cmp #SCR_H
        bcs fd_skip             ; (off the picture, above or below)
        jsr pool_char
        bcs fd_skip             ; (the pool is used up)
        lda z_line
        tay
        clc
        adc z_n
        sta z_end
        lda z_fresh
        bne fd_fresh
fd_line:                        ; into what is there, through the mask
        lda (z_fnt),y
fd_keep = *
        and $FFFF,x
fd_dat = *
        ora $FFFF,x
        sta (z_fnt),y
        inx
        iny
        cpy z_end
        bne fd_line
        beq fd_down
fd_fresh:                       ; a cell of grass, just taken: nothing to
        lda #0                  ; keep - the lines above and below the
        cpy #0                  ; figure's empty, its own straight in
        beq fd_own
        tay
:       sta (z_fnt),y
        iny
        cpy z_line
        bne :-
fd_own:
fd_dat2 = *
        lda $FFFF,x
        sta (z_fnt),y
        inx
        iny
        cpy z_end
        bne fd_own
        cpy #8
        beq fd_down
        lda #0
:       sta (z_fnt),y
        iny
        cpy #8
        bne :-
        beq fd_down
fd_skip:
        txa
        clc
        adc z_n
        tax
fd_down:
        lda #0
        sta z_line
        inc z_r
        cpx z_h
        bcc fd_cell
fd_ncol:                        ; the next column: 2 + 2 * its lines on
        inc z_cx
        lda z_h
        asl a
        adc #2                  ; (carry clear: a column is under 128 lines)
        adc z_dat
        sta z_dat
        bcc :+
        inc z_dat + 1
:       dec z_ncol
        beq :+
        jmp fd_col
:       rts

; pool_char: the pool character of the back picture's cell z_col, z_r,
; given out now if the cell has none yet; z_fnt points to its pixels.
; Carry set when the pool is used up. Keeps X.
pool_char:
        ldy z_r
        lda row40_lo,y
        sta z_att
        sta z_scr
        lda row40_hi,y
        clc
        adc z_atthi
        sta z_att + 1
        adc #4
        sta z_scr + 1
        ldy z_col
        lda fig_col
        sta (z_att),y
        lda (z_scr),y
        cmp #POOL
        bcs pc_have
        ; a new one: the ground's character copied into it
        sta z_t
        lda pool_next
        beq pc_full               ; (past 255)
        sta (z_scr),y
        inc pool_next
        stx z_t2
        ldx z_lst               ; into the picture's list: the cell's place
        tya                     ; in the matrix, and the ground's code
        clc
        adc z_att
pc_lo = *
        sta lists,x
        lda z_att + 1
        adc #0
        sec
        sbc z_atthi
pc_hi = *
        sta lists + $100,x
        lda z_t
pc_cd = *
        sta lists + $200,x
        inc z_lst
        ldy z_col
        lda (z_scr),y           ; to: the new one
        jsr char_at
        ldx z_t2
        lda z_t                 ; from: the ground's - the grass is empty,
        bne pc_copy               ; fig_draw fills it (z_fresh)
        lda #1
        sta z_fresh
        clc
        rts
pc_copy:  lda #0
        sta z_fresh
        lda z_fnt
        sta z_dst
        lda z_fnt + 1
        sta z_dst + 1
        lda z_t
        jsr char_at
        ldy #7
:       lda (z_fnt),y
        sta (z_dst),y
        dey
        bpl :-
        lda z_dst
        sta z_fnt
        lda z_dst + 1
        sta z_fnt + 1
        clc
        rts
pc_have:  jsr char_at
        lda #0
        sta z_fresh
        clc
        rts
pc_full:  lda #COL_LINE           ; the colour back; the cell stays the
                                ; ground's
        sta (z_att),y
        sec
        rts

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
