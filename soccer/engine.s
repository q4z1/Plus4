; engine.s - the Plus/4 end of the soccer game: the pictures, the
; interrupt, the joystick
;
; Two pictures, each a colour matrix, a code matrix and a character set of
; its own: one is shown while the other is drawn, and the interrupt swaps
; them in the vertical blank (as Stardew Pond and Paradroid do), together
; with the fine scroll the picture was drawn for.
;
; The ground (data/pitch.txt) is 79 x 67 cells of 221 different characters,
; more than fit into a set with the figures' beside them. A picture's set
; holds only the ground characters it shows - at most 76 at a time - in
; codes given out as they are first met while the picture is built: a
; cache, one per picture (xlat0, xlat1: the code of each ground character
; in it, 0 none). Code 0 is the grass for good. The codes from POOL on are
; the figures' (fig_draw). A cache grown past FLUSH_AT is emptied before
; the next build, so the build that follows never reaches POOL.

        .include "game.inc"
        .include "data.inc"

        .export eng_init, eng_begin, eng_end, eng_wait, fig_draw, joy_read
        .export cam_x, cam_y, frames, joy, dbg_joy
        .export fig_x, fig_y, fig_img, fig_col
        .import _pitch_map, _pitch_font
        .import img_ox, img_oy, img_lo, img_hi

POOL        = 136               ; first code for figures
FLUSH_AT    = POOL - 80         ; worst picture: 76 ground characters
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

        .bss
frames:     .res 1              ; pictures shown, 50 a second
joy:        .res 1              ; J_ bits, joy_read's
dbg_joy:    .res 1              ; J_ bits held for joy_read by a test
back:       .res 1              ; the picture being drawn: 0 or 1
ready:      .res 1              ; it is complete; the interrupt shows it
ctrl2:      .res 1              ; $FF07 as the game wants it, without the
                                ; fine scroll
cam_x:      .res 2              ; the view's top left corner on the
cam_y:      .res 2              ; ground, in pixels (the game's)
col0:       .res 1              ; it as cells and fine scroll
row0:       .res 1
fx:         .res 1
fy:         .res 1
; per picture
b_col:      .res 2              ; ground cell at its top left, $FF none
b_row:      .res 2
b_fx:       .res 2              ; what the interrupt sets for it
b_fy:       .res 2
b_next:     .res 2              ; next free code in its set
b_nlist:    .res 2              ; cells its figures took
pool_next:  .res 1              ; next code for a figure, 0 when used up
fig_x:      .res 2              ; fig_draw's figure: on the ground,
fig_y:      .res 2              ; its sprite's top left corner
fig_img:    .res 1
fig_col:    .res 1              ; its cells' colour

        .segment "HIBSS"
xlat0:      .res 256
xlat1:      .res 256
lst_c:      .res 256            ; cells figures took, column and row:
lst_r:      .res 256            ; picture 0 from 0, picture 1 from 128

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
        ; both colour matrices white multicolour, both caches empty with
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
        lda #0
        sta xlat0,x
        sta xlat1,x
        inx
        bne :-
        ldx #7
:       lda _pitch_font,x
        sta FNT0,x
        sta FNT1,x
        dex
        bpl :-
        lda #1
        sta b_next
        sta b_next + 1
        lda #$FF
        sta b_col
        sta b_col + 1
        lda #0
        sta back
        sta ready
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
        lda ready
        beq @done
        ldx back
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
        txa
        eor #1
        sta back
        lda #0
        sta ready
@done:  pla
        tax
        pla
        rti

vm_of:  .byte >MAT0, >MAT1
ch_of:  .byte >FNT0, >FNT1

; eng_wait: till the picture handed over is on screen
eng_wait:
:       lda ready
        bne :-
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

        ; the code below for the back picture: its cache, its matrices,
        ; its characters
        ldx back
        lda xlat_hi,x
        sta cl_look + 2
        sta al_put + 2
        sta rs_look + 2
        lda fnt_hi,x
        sta al_font
        sta z_fnthi
        lda mat_hi,x
        sta z_atthi
        lda fx
        sta b_fx,x
        lda fy
        sta b_fy,x
        jsr mapbase
        lda col0
        cmp b_col,x
        bne @cells
        lda row0
        cmp b_row,x
        bne @cells
        sec                     ; the figures' cells back to the ground
        jsr restore
        jmp @pool
@cells: clc                     ; their colours back; the codes are new
        jsr restore
        jsr cells
@pool:  lda #POOL
        sta pool_next
        ldx back
        lda #0
        sta b_nlist,x
        lda lst_of,x
        sta z_lst
        rts

eng_end:
        lda #1
        sta ready
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
; colour back to the ground's, and with carry set their codes too
restore:
        ldx back
        lda b_nlist,x
        beq rs_done
        sta z_n
        ror z_t                 ; bit 7: codes too
        lda lst_of,x
        tax
rs_next:  ldy lst_r,x
        lda row40_lo,y
        sta z_att
        sta z_scr
        lda row40_hi,y
        clc
        adc z_atthi
        sta z_att + 1
        adc #4
        sta z_scr + 1
        lda row79_lo,y
        clc
        adc z_mb
        sta z_src
        lda row79_hi,y
        adc z_mb + 1
        sta z_src + 1
        ldy lst_c,x
        lda #COL_LINE
        sta (z_att),y
        bit z_t
        bpl rs_skip
        lda (z_src),y
        beq rs_put                ; the grass: code 0
        stx z_t2
        tax
rs_look = *
        lda xlat0,x             ; (the picture's cache)
        ldx z_t2
rs_put:   sta (z_scr),y
rs_skip:  inx
        dec z_n
        bne rs_next
rs_done:  rts

; cells: the back picture's code matrix, from the ground at col0, row0
cells:
        ldx back
        lda col0
        sta b_col,x
        lda row0
        sta b_row,x
        lda b_next,x
        cmp #FLUSH_AT
        bcc :+
        jsr flush
:       lda z_mb
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

xlat_hi: .byte >xlat0, >xlat1
fnt_hi:  .byte >FNT0, >FNT1
mat_hi:  .byte >MAT0, >MAT1
lst_of:  .byte 0, 128           ; each picture's half of the lists

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
        pha
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
        bcs fd_ncol             ; (off the picture, left or right)
        sta z_col
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
        lda z_dat + 1
        adc #0
        sta fd_dat + 2
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
        ldy z_line
fd_line:
        lda (z_fnt),y
fd_keep = *
        and $FFFF,x
fd_dat = *
        ora $FFFF,x
        sta (z_fnt),y
        inx
        iny
        dec z_n
        bne fd_line
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
        bcs @have
        ; a new one: the ground's character copied into it
        sta z_t
        lda pool_next
        beq @full               ; (past 255)
        sta (z_scr),y
        inc pool_next
        stx z_t2
        ldx z_lst               ; into the picture's list
        lda z_col
        sta lst_c,x
        lda z_r
        sta lst_r,x
        inc z_lst
        ldx back
        inc b_nlist,x
        ldy z_col
        lda (z_scr),y           ; to: the new one
        jsr char_at
        lda z_t                 ; from: the ground's - the grass is empty
        bne @copy
        ldy #7
:       sta (z_fnt),y
        dey
        bpl :-
        ldx z_t2
        clc
        rts
@copy:  lda z_fnt
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
        ldx z_t2
        clc
        rts
@have:  jsr char_at
        clc
        rts
@full:  lda #COL_LINE           ; the colour back; the cell stays the
                                ; ground's
        sta (z_att),y
        sec
        rts

; char_at: z_fnt = the pixels of code A in the back picture's set
char_at:
        ldy #0
        sty z_fnt + 1
        asl a
        rol z_fnt + 1
        asl a
        rol z_fnt + 1
        asl a
        rol z_fnt + 1
        sta z_fnt
        lda z_fnt + 1
        adc z_fnthi             ; (carry clear from the last rol)
        sta z_fnt + 1
        rts

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
