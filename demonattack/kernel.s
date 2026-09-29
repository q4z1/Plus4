; ---------------------------------------------------------------------------
; kernel.s - what the 2600's kernel shows, and what collides in it
;
; On the 2600 the "kernel" is the part of the program that races the beam:
; it builds the picture line by line while the television draws it, and the
; video chip notes on the way which objects touched. The game logic (C,
; demonattack.c) only reads the collision latches afterwards.
;
; This is the same thing done after the fact: it walks the lines the 2600
; kernel would draw, works out which pixels would be lit - with the timing
; quirks of the real chip, see the C part's comments on the kernel - sets
; the collision latches, and draws the picture into the back buffer of the
; Plus/4 screen, together with the list of colour register writes the raster
; interrupt carries out while it is shown.
;
; It reads the game's state straight out of the 2600 RAM image at $80-$FF,
; so the addresses below are the original's.
; ---------------------------------------------------------------------------

        .setcpu "6502"
        .macpack longbranch

        .importzp _ram, _o_src, _o_mask, _o_rows
        .import _o_d0, _o_n, _o_cx, _o_nc, _o_x, _o_col, _o_flags, _o_cmask
        .import _r_column, _r_vline, _o_val
        .import _r_prep8, _r_draw, _r_demon, _r_demon_off, _o_slot, _r_attr, _r_cannon, _r_quad
        .import _a_val, _a_col, _a_row, _a_n
        .import _coldata, _rev, _ev_line, _ev_reg, _ev_val, _back
        .import _rom_hi, _ted_colour, _ted_attr, _pixtab
        .import _band_tab, _img_lo, _img_hi, _rows_lo, _rows_hi
        .import _cannon_img
        .import _colupf, _cx_p0bl, _cx_p1bl, _cx_pp, _yreg, _nodraw
        .export _kernel_asm

; ---- the 2600 RAM ---------------------------------------------------------

POS0        = $8D               ; left halves, [3] the cannon
POS1        = $91               ; right halves, [3] shot / diver / wreck
LASER_Y     = $95
LASER_X     = $96
SPAWN_SLOT  = $97
DEATH       = $99
FRAME0      = $9D
FRAME1      = $A1
SHOTS       = $A5
DIVER_FRAME = $B3
FLASH       = $BC
FRAME_LO    = $BD
T_BF        = $BF
YPOS        = $C5               ; [3] the diver
COL_LO      = $CD
COLMASK     = $D1
SCORE_COL   = $D2
T_DC        = $DC
E7          = $E7
WAVE_FLAGS  = $EB
FLICKER     = $EC
PLAYER      = $ED
LIVES       = $F2
GROUND_COL  = $F7
COOP        = $F8

ROM         = _rom_hi - $1D88   ; ROM+a is address a of the cartridge

LT_POS      = 0
LT_DRAW     = 1
LT_EMPTY    = 2
LT_LOW      = 3

MODE_SHOTS  = 0
MODE_DIVER  = 1
MODE_WRECK  = 2

R_BG        = $15
R_A         = $16
R_B         = $17
R_BORDER    = $19
FRAME_REG   = $FF
FRAME_LINE  = 206

        .segment "ENGZP": zeropage
p_g0:       .res 2              ; the rows of the left half's picture
p_g1:       .res 2              ; and of the right half's
p_cols:     .res 2              ; this wave's colour table

        .bss                    ; scratch that needs no zero page
k_bx:       .res 1              ; the ball's pixel
k_btop:     .res 1              ; display lines it shows on
k_bbot:     .res 1
k_mode:     .res 1              ; what the band under the demons holds
k_evi:      .res 1              ; next free event
k_lt:       .res 1              ; line_of: kind of line
k_lx:       .res 1              ;          its kernel line counter
k_lj:       .res 1              ;          its demon
k_d:        .res 1
k_j:        .res 1              ; demon
k_pl:       .res 1              ; pixel of the left half
k_pr:       .res 1              ; and the right one
k_q:        .res 1              ; quad wide
k_d0:       .res 1              ; display line of the top
k_f0:       .res 1
k_f1:       .res 1
k_i:        .res 1
k_t:        .res 1
k_u:        .res 1
k_g:        .res 1
k_p:        .res 1
k_wa:       .res 1
k_wb:       .res 1
k_band:     .res 1              ; rows of a figure with pixels, bit 7 = top
k_bcx:      .res 1
k_bnc:      .res 1
k_top:      .res 1              ; first kernel line of the lower band
k_pc:       .res 1              ; cannon pixel
k_pb:       .res 1              ; its P1's pixel
k_c:        .res 1
k_x:        .res 1
k_e:        .res 1
k_n:        .res 1
k_ga:       .res 1              ; overlap8 arguments
k_pa:       .res 1
k_gb:       .res 1
k_pbb:      .res 1
k_dr:       .res 1              ; diver_row's scratch
k_last:     .res 1              ; last line of a block of shot
k_have:     .res 1              ; get_rows done for this demon
k_smode:    .res 1              ; which case shot_fast has
k_fast:     .res 1              ; this demon was drawn by r_demon
k_xmin:     .res 1              ; lines of shot drawn: lowest kernel line
k_xmax:     .res 1              ; and highest
k_v:        .res 1              ; shot block's shape
k_vh:       .res 1              ; and the one above it
k_c8:       .res 1
k_flp:      .res 1
k_ye:       .res 1

        .bss
src:        .res 16             ; a sprite, top line first
g1r:        .res 8              ; right half's rows, mirrored
.export shbuf
shbuf:      .res 80             ; the shot's lines, kernel line x at 79 - x

        .rodata
bit_of:     .byte $80, $40, $20, $10, $08, $04, $02, $01
mask_demon: .byte $FF, $55, $AA, $55, $AA, $55, $AA, $55
mask_01:    .byte $55, $55, $55, $55, $55, $55, $55, $55
mask_10:    .byte $AA, $AA, $AA, $AA, $AA, $AA, $AA, $AA
mask_11:    .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF

        .code

; ---------------------------------------------------------------------------
; ev_put: one register write for the raster interrupt.
;   A = display line it is due at the start of, X = register, Y = value
ev_put:
        bit _nodraw
        bpl :+
        rts
:
        clc
        adc #4
        stx k_t
        ldx k_evi
        sta _ev_line,x
        lda k_t
        sta _ev_reg,x
        tya
        sta _ev_val,x
        inc k_evi
        rts

; ---------------------------------------------------------------------------
; line_of: what kind of line display line A is: k_lt, k_lx, k_lj.
line_of:
        sta k_d
        lda #180
        sec
        sbc YPOS+2              ; 180 - lowest demon
        cmp k_d
        bcs @zonea
        adc #3                  ; carry clear: 183 - lowest demon
        cmp k_d
        bcc @low
        lda #LT_POS
        sta k_lt
        rts
@low:   lda #183
        sec
        sbc k_d
        sta k_lx
        lda #LT_LOW
        sta k_lt
        rts
@zonea: lda #180
        sec
        sbc k_d
        sta k_lx
        cmp #163
        bcs @pos
        ldx #0
@dj:    lda k_lx
        cmp YPOS,x
        bcc @below
        lda YPOS,x              ; x >= c: drawn if x <= c + 7
        clc
        adc #7
        cmp k_lx
        bcc @nextj
        stx k_lj
        lda #LT_DRAW
        sta k_lt
        rts
@below: cpx #2                  ; x < c: positioning for the next demon?
        bcs @nextj
        lda YPOS,x
        sec
        sbc #3
        cmp k_lx
        beq @pos
        bcc @pos
@nextj: inx
        cpx #3
        bne @dj
        stx k_lj
        lda #LT_EMPTY
        sta k_lt
        rts
@pos:   lda #LT_POS
        sta k_lt
        rts

; is kernel line X one of the diver's? carry set if so
diver_row:
        cpx YPOS+3
        bcc @no
        lda YPOS+3
        clc
        adc #7
        stx k_dr
        cmp k_dr
        bcc @no
        sec
        rts
@no:    clc
        rts

; ---------------------------------------------------------------------------
; thresh: the pixel from which a new ENABL shows in the line line_of looked
; at; A = 0 for a write that switches the ball off, 1 for on. Returns in A.
thresh:
        sta k_t
        lda k_lt
        cmp #LT_DRAW
        bne :+
        lda #104
        bne @plus
:       cmp #LT_EMPTY
        bne :+
        lda #26
        bne @plus
:       lda k_mode
        cmp #MODE_WRECK
        bne :+
        lda #2
        bne @plus
:       cmp #MODE_SHOTS
        bne @diver
        lda k_lx
        cmp #12
        bcs :+
        lda #17
        bne @plus
:       lda k_t                 ; x >= 12: 0 or 2
        asl a
        rts
@diver: ldx k_lx
        jsr diver_row
        lda #0
        rol a
        sta k_u                 ; 1 on a line of the diver
        lda #59
        ldx k_lx
        cpx #12
        bcc :+
        lda #41
:       ldx k_u
        beq @plus
        clc
        adc #21                 ; 80 / 62
@plus:  ldx k_t
        beq :+
        clc
        adc #3
:       rts

; ---------------------------------------------------------------------------
; ball_scan: k_btop..k_bbot, the display lines the ball shows on.
ball_scan:
        lda LASER_Y
        clc
        adc #7
        jsr dline
        sta k_d0
@top:   lda k_d0
        cmp #184
        bcc :+
        lda #1                  ; off the band: none
        sta k_btop
        lda #0
        sta k_bbot
        rts
:       jsr line_of
        lda k_lt
        bne @topok
        inc k_d0
        jmp @top
@topok: lda #1
        jsr thresh
        sta k_t
        lda k_bx
        cmp k_t
        lda k_d0
        bcs :+
        adc #1                  ; the line before shows it off here
:       sta k_btop
        lda LASER_Y
        jsr dline
        clc
        adc #1
        sta k_d0
@bot:   lda k_d0
        cmp #184
        bcc :+
        lda #183
        sta k_bbot
        rts
:       jsr line_of
        lda k_lt
        bne @botok
        inc k_d0
        jmp @bot
@botok: lda #0
        jsr thresh
        sta k_t
        lda k_d0
        ldx k_bx
        cpx k_t
        bcc :+
        sec
        sbc #1
:       sta k_bbot
        rts

; display line of kernel line A
dline:
        cmp YPOS+2
        bcc @low
        eor #$FF
        sec
        adc #180                ; 180 - A
        rts
@low:   eor #$FF
        sec
        adc #183
        rts

; ---------------------------------------------------------------------------
; pix_on: is pixel k_p lit in sprite byte A drawn at pixel X? k_q: quad.
; Result in A (nonzero: lit).
pix_on:
        sta k_g
        stx k_t
        lda k_p
        sec
        sbc k_t
        cmp #160
        bcc :+
        adc #159                ; wrap at 160, like the 2600
:       ldx k_q
        beq @normal
        cmp #32
        bcs @no
        lsr a
        lsr a
        tax
        lda k_g
        and bit_of,x
        rts
@normal:
        cmp #8
        bcs @no
        tax
        lda k_g
        and bit_of,x
        rts
@no:    lda #0
        rts

; overlap8: do byte k_ga at pixel k_pa and byte k_gb at pixel k_pbb share a
; pixel? Result in A.
overlap8:
        lda k_pbb
        sec
        sbc k_pa                ; d = pb - pa, signed
        bmi @neg
        cmp #8
        bcs @no
        tax
        lda k_ga
        cpx #0
        beq @and
:       asl a
        dex
        bne :-
@and:   and k_gb
        rts
@neg:   cmp #$F9                ; d > -8 ?
        bcc @no
        eor #$FF
        clc
        adc #1
        tax
        lda k_gb
:       asl a
        dex
        bne :-
        and k_ga
        rts
@no:    lda #0
        rts

; overlap: the same with either or both quad wide (k_q for both here - the
; only quad figure is the demon being made, both of whose halves are).
overlap:
        lda k_ga
        beq @no
        lda k_gb
        beq @no
        lda k_q
        bne @quad
        jmp overlap8
@quad:  lda #0
        sta k_i
@ia:    ldx k_i
        lda k_ga
        and bit_of,x
        beq @nexti
        lda k_i                 ; xa = pa + 4i
        asl a
        asl a
        clc
        adc k_pa
        sta k_u
        lda #0
        sta k_n
@kb:    ldx k_n
        lda k_gb
        and bit_of,x
        beq @nextk
        lda k_n                 ; xb = pb + 4k
        asl a
        asl a
        clc
        adc k_pbb
        sta k_t
        sec
        sbc k_u                 ; xb - xa < 4 ?
        cmp #4
        bcc @yes
        lda k_u
        sec
        sbc k_t                 ; xa - xb < 4 ?
        cmp #4
        bcc @yes
@nextk: inc k_n
        lda k_n
        cmp #8
        bne @kb
@nexti: inc k_i
        lda k_i
        cmp #8
        bne @ia
@no:    lda #0
        rts
@yes:   lda #1
        rts

; ---------------------------------------------------------------------------
; band_colours: the colours of a figure whose top line is display line k_d0,
; rows in k_band (bit 7 = top), colours at (p_cols) - indexed by 2600 row,
; bottom row 0. Odd lines get register A, even ones B, one line early; the
; first line of a character row gets its colour into the colour cells
; k_bcx..k_bcx+k_bnc-1 instead.
band_colours:
        bit _nodraw
        bpl :+
        rts
:
        lda k_d0
        sta k_d
        ldy #7
@row:   asl k_band
        bcc @next
        lda (p_cols),y
        lsr a
        tax
        lda k_d
        and #7
        bne @reg
        ; the colour cells: one run, or two where the figure wraps
        sty k_u
        lda _ted_attr,x
        sta _a_val
        lda k_d
        lsr a
        lsr a
        lsr a
        sta _a_row
        lda k_bcx
        sta _a_col
        lda k_bnc
        sta _a_n
        jsr _r_attr
        lda k_bcx
        clc
        adc k_bnc
        sec
        sbc #40
        beq @nowrap
        bcc @nowrap
        sta _a_n                ; the part past column 39, from column 0
        lda #0
        sta _a_col
        jsr _r_attr
@nowrap:
        ldy k_u
        jmp @next
@reg:   ldx k_evi               ; the register one line early
        lda k_d
        clc
        adc #3                  ; raster line of d - 1
        sta _ev_line,x
        lda k_d
        lsr a
        lda #R_B
        bcc :+
        lda #R_A
:       sta _ev_reg,x
        lda (p_cols),y
        lsr a
        sty k_u
        tay
        lda _ted_colour,y
        sta _ev_val,x
        inc k_evi
        ldy k_u
@next:  inc k_d
        dey
        jpl @row
        rts

; ---------------------------------------------------------------------------
; the band of the demons
demon_zone:
        lda #0
        sta k_j
@demon: ldx k_j
        stx _o_slot
        lda #0
        sta k_fast
        lda FRAME0,x
        sta k_f0
        ora FRAME1,x
        jeq @nextdemon
        lda FRAME1,x
        sta k_f1
        ldy POS0,x
        lda _pixtab,y
        sta k_pl
        ldy POS1,x
        lda _pixtab,y
        sta k_pr
        lda #0
        cpx SPAWN_SLOT
        bne :+
        lda #1
:       sta k_q
        lda #173
        sec
        sbc YPOS,x
        sta k_d0
        ; which rows have pixels: from the frames' tables
        ldy k_f0
        lda _band_tab,y
        ldy k_f1
        ora _band_tab,y
        sta k_band

        ; collisions need the rows themselves; most of the time neither
        ; check applies
        lda #0
        sta k_have
        lda k_q
        beq @ppnorm
        ; four wide: the halves can only meet if they start within 31
        ; pixels of each other (every pair of quad pixels is then checked
        ; exactly by overlap)
        lda k_pr
        sec
        sbc k_pl
        clc
        adc #31
        cmp #63
        bcs @pp_done
        bcc @ppcheck
@ppnorm:
        lda k_pr
        sec
        sbc k_pl
        clc
        adc #7
        cmp #15
        bcs @pp_done
@ppcheck:
        ; the halves overlapping each other count as P0 meeting P1
        jsr get_rows
        lda k_pl
        sta k_pa
        lda k_pr
        sta k_pbb
        ldy #0
@pprow: lda (p_g0),y
        sta k_ga
        lda g1r,y
        sta k_gb
        sty k_c
        jsr overlap
        ldy k_c
        cmp #0
        beq :+
        lda #$80
        sta _cx_pp
        jmp @pp_done
:       iny
        cpy #8
        bne @pprow
@pp_done:
        ; the ball against both halves - if it is anywhere near
        lda k_btop
        cmp k_bbot
        beq :+
        bcs @ball_done
:       lda k_d0
        clc
        adc #7
        cmp k_btop
        bcc @ball_done          ; demon ends above the ball
        lda k_bbot
        cmp k_d0
        bcc @ball_done          ; ball ends above the demon
        jsr get_rows
        lda k_bx
        sta k_p
        ldy #0
@brow:  sty k_c
        tya
        eor #7
        clc
        adc k_d0                ; display line of row y: d0 + 7 - y
        cmp k_btop
        bcc @bnext
        cmp k_bbot
        beq :+
        bcs @bnext
:       lda (p_g0),y
        ldx k_pl
        jsr pix_on
        beq :+
        lda #$40
        sta _cx_p0bl
:       ldy k_c
        lda g1r,y
        ldx k_pr
        jsr pix_on
        beq @bnext
        lda #$40
        sta _cx_p1bl
@bnext: ldy k_c
        iny
        cpy #8
        bne @brow
@ball_done:
        lda k_band
        jeq @nextdemon

        lda k_d0
        sta _o_d0
        lda #8
        sta _o_n
        lda #<mask_demon
        sta _o_mask
        lda #>mask_demon
        sta _o_mask+1
        lda k_q
        jne @quad
        lda k_pl
        clc
        adc #8
        cmp k_pr
        jne @split

        ; together: one figure of 16 pixels
        lda k_pl
        lsr a
        lsr a
        sta k_bcx
        lda #4
        sta k_bnc
        lda k_pl
        and #3
        beq :+
        inc k_bnc
:       lda k_f0
        cmp k_f1
        bne @slow
        cmp #28
        bcs @slow
        ; the fast way: the demon's picture is ready-made
        asl a
        asl a
        sta k_t
        lda k_pl
        and #3
        ora k_t
        tax                     ; picture number
        lda _img_lo,x
        sta _o_src
        lda _img_hi,x
        sta _o_src+1
        lda k_pl
        sta _o_x
        jsr _r_demon
        inc k_fast
        jmp @colours
@slow:  jsr get_src
        lda #<src
        sta _o_src
        lda #>src
        sta _o_src+1
        lda k_pl
        sta _o_x
        lda #0
        sta _o_col
        lda #8
        sta _o_flags
        jsr _r_prep8
        lda #<(src+8)
        sta _o_src
        lda #>(src+8)
        sta _o_src+1
        lda #2
        sta _o_col
        lda #3
        sta _o_flags
        jsr _r_prep8
        lda k_bcx
        sta _o_cx
        lda k_bnc
        sta _o_nc
        jsr _r_draw
@colours:
        jsr cols_ptr
        jsr band_colours
        jmp @nextdemon

@quad:  ; being made: both halves four times as wide, drawn point by point
        jsr get_src
        lda #<src
        sta _o_src
        lda #>src
        sta _o_src+1
        lda k_pl
        sta _o_x
        lda #0
        sta _o_flags
        jsr _r_quad
        lda k_pl
        lsr a
        lsr a
        sta k_bcx
        lda #9
        sta k_bnc
        lda k_band
        pha
        jsr cols_ptr
        jsr band_colours
        pla
        sta k_band
        lda #<(src+8)
        sta _o_src
        lda #>(src+8)
        sta _o_src+1
        lda k_pr
        sta _o_x
        lda #1
        sta _o_flags
        jsr _r_quad
        lda k_pr
        lsr a
        lsr a
        sta k_bcx
        ; only the colour cells of its row starting a character, if the
        ; right half has pixels there
        jsr row0_only_right
        jsr band_colours
        jmp @nextdemon

@split: ; split: two figures
        jsr get_src
        lda #<src
        sta _o_src
        lda #>src
        sta _o_src+1
        lda k_pl
        sta _o_x
        lda #0
        sta _o_col
        sta _o_flags
        jsr _r_prep8
        lda k_pl
        lsr a
        lsr a
        sta _o_cx
        sta k_bcx
        lda #3
        sta _o_nc
        sta k_bnc
        jsr _r_draw
        lda #<(src+8)
        sta _o_src
        lda #>(src+8)
        sta _o_src+1
        lda k_pr
        sta _o_x
        lda #0
        sta _o_col
        lda #1
        sta _o_flags
        jsr _r_prep8
        lda k_pr
        lsr a
        lsr a
        sta _o_cx
        jsr _r_draw
        lda k_band
        pha
        jsr cols_ptr
        jsr band_colours
        pla
        sta k_band
        jsr row0_only
        lda k_pr
        lsr a
        lsr a
        sta k_bcx
        jsr band_colours

@nextdemon:
        lda k_fast              ; not drawn from its own characters: the
        bne :+                  ; slot's cells from last time go
        jsr _r_demon_off
:       inc k_j
        lda k_j
        cmp #3
        jne @demon
        rts

; the rows of both halves: p_g0, p_g1 and the mirrored g1r - once per demon
get_rows:
        lda k_have
        bne @done
        inc k_have
        lda k_f0
        jsr frame_ptr
        sta p_g0
        stx p_g0+1
        lda k_f1
        jsr frame_ptr
        sta p_g1
        stx p_g1+1
        ldy #7
:       lda (p_g1),y
        tax
        lda _rev,x
        sta g1r,y
        dey
        bpl :-
@done:  rts

; the sprite for the slow paths, top line first: left half, then right
get_src:
        jsr get_rows
        ldx #0
        ldy #7
:       lda (p_g0),y
        sta src,x
        lda (p_g1),y
        sta src+8,x
        inx
        dey
        bpl :-
        rts

; keep only the bit of k_band whose line starts a character row
row0_only:
        lda k_d0
        and #7
        beq :+
        eor #7
        clc
        adc #1                  ; the row index of the line that is 0 mod 8
:       tax
        lda k_band
        and bit_of,x
        sta k_band
        rts

; the same, and only if the right half has pixels on that line
row0_only_right:
        lda k_d0
        and #7
        beq :+
        eor #7
        clc
        adc #1
:       tax
        lda src+8,x
        beq :+
        lda bit_of,x
:       sta k_band
        rts

; p_cols = ROM + $1F00 + this wave's colour table
cols_ptr:
        lda COL_LO
        clc
        adc #<(ROM + $1F00)
        sta p_cols
        lda #>(ROM + $1F00)
        adc #0
        sta p_cols+1
        rts

; A/X = ROM + $1E00 + A * 8
frame_ptr:
        ldx #0
        stx k_t
        asl a
        rol k_t
        asl a
        rol k_t
        asl a
        rol k_t
        clc
        adc #<(ROM + $1E00)
        pha
        lda k_t
        adc #>(ROM + $1E00)
        tax
        pla
        rts

; ---------------------------------------------------------------------------
; the demons' laser as the television shows it in kernel line A
shot_new:
        cmp #80
        bcs @none
        cmp YPOS+2
        bcs @none
        sta k_t
        eor #$FF
        eor FRAME_LO
        and FLICKER
        bne @none
        lda k_t
        lsr a
        lsr a
        lsr a
        tax
        lda SHOTS,x
        rts
@none:  lda #0
        rts

; shot_fast: shot_seen, knowing which case applies to every line (k_smode)
SM_NEW   = 0                    ; the line's own shape
SM_OLD   = 1                    ; the shape of the line above
SM_MIXED = 2                    ; it depends on the line
shot_fast:
        ldx k_smode
        beq shot_new
        dex
        bne shot_seen
        clc
        adc #1
        jmp shot_new

; shot_seen: kernel line A, P1 at k_pb. The new shape lands late in the
; line; left of that point the line before still shows.
shot_seen:
        sta k_x
        jsr shot_new
        sta k_n                 ; new
        lda k_x
        clc
        adc #1
        jsr shot_new
        sta k_e                 ; old
        cmp k_n
        beq @same
        lda k_x
        ldx #101
        cmp #12
        bcs :+
        ldx #119
:       stx k_t
        sec
        sbc LASER_Y
        and #$F8
        bne :+
        lda k_t
        clc
        adc #3
        sta k_t
:       lda k_pb
        clc
        adc #8
        cmp k_t
        bcc @old
        beq @old
        lda k_pb
        cmp k_t
        bcs @same
        ; m = $FF << (8 - (t - pb))
        lda k_t
        sec
        sbc k_pb
        eor #7
        clc
        adc #1                  ; 8 - (t - pb)
        tax
        lda #$FF
:       asl a
        dex
        bne :-
        sta k_u
        and k_e
        sta k_t
        lda k_u
        eor #$FF
        and k_n
        ora k_t
        rts
@old:   lda k_e
        rts
@same:  lda k_n
        rts

; ---------------------------------------------------------------------------
; the cannon's band
lower_zone:
        ldy POS0+3
        lda _pixtab,y
        sta k_pc
        ldy POS1+3
        lda _pixtab,y
        sta k_pb
        ldy YPOS+2
        dey
        sty k_top
        ; registers for the band: the laser in %10 below row 20, shots %01
        lda #181
        sec
        sbc YPOS+2
        sta k_d
        lda _colupf
        lsr a
        tax
        ldy _ted_colour,x
        ldx #R_B
        lda k_d
        jsr ev_put
        lda k_mode
        cmp #MODE_SHOTS
        bne :+
        ldy _ted_colour+($4E >> 1)
        ldx #R_A
        lda k_d
        jsr ev_put
:       lda k_mode
        cmp #MODE_WRECK
        jne @cannon

        ; $1168: the wreck, five rows of debris, both halves the same
        lda #$FF
        sta _o_x
        jsr _r_cannon
        lda DEATH
        and #$38
        lsr a
        lsr a
        lsr a
        tax
        lda ROM+$1DBC,x
        sta k_e
        lda #5
        sta k_n
@wrow:  dec k_n
        jmi @wdone
        lda k_n
        asl a
        asl a
        asl a
        sta k_x                 ; lines x-1 and x
        cmp k_top
        beq :+
        bcs @wrow
:       lda k_e
        clc
        adc k_n
        tax
        lda ROM+$1D00,x
        beq @wrow
        sta k_c
        sta src
        sta src+1
        lda #183
        sec
        sbc k_x
        sta k_d0
        ldx #2
        lda k_n
        bne :+
        dex
:       stx _o_n
        ; collisions
        lda k_bx
        sta k_p
        lda #0
        sta k_q
        ldx #0
@wcol:  stx k_i
        txa
        clc
        adc k_d0
        cmp k_btop
        bcc @wcn
        cmp k_bbot
        beq :+
        bcs @wcn
:       lda k_c
        ldx k_pc
        jsr pix_on
        beq :+
        lda #$40
        sta _cx_p0bl
:       ldx k_c
        lda _rev,x
        ldx k_pb
        jsr pix_on
        beq @wcn
        lda #$40
        sta _cx_p1bl
@wcn:   ldx k_i
        inx
        cpx _o_n
        bne @wcol
        lda k_c
        sta k_ga
        lda k_pc
        sta k_pa
        ldx k_c
        lda _rev,x
        sta k_gb
        lda k_pb
        sta k_pbb
        jsr overlap8
        beq :+
        lda #$80
        sta _cx_pp
:       lda #<src
        sta _o_src
        lda #>src
        sta _o_src+1
        lda k_pc
        sta _o_x
        lda #0
        sta _o_col
        lda #8
        sta _o_flags
        jsr _r_prep8
        lda #2
        sta _o_col
        lda #3
        sta _o_flags
        jsr _r_prep8
        lda k_d0
        sta _o_d0
        lda k_pc
        lsr a
        lsr a
        sta _o_cx
        sta _a_col
        lda #4
        sta _o_nc
        lda k_pc
        and #3
        beq :+
        inc _o_nc
:       lda #<mask_demon
        sta _o_mask
        lda #>mask_demon
        sta _o_mask+1
        jsr _r_draw
        ldx k_n
        lda ROM+$1DEC,x
        lsr a
        tax
        ldy _ted_colour,x
        stx k_u
        lda k_d0
        sec
        sbc #1
        ldx #R_A
        jsr ev_put
        lda _o_n
        cmp #2
        jne @wrow
        ldx k_u
        lda _ted_attr,x
        sta _a_val
        lda k_d0
        clc
        adc #1
        lsr a
        lsr a
        lsr a
        sta _a_row
        lda _o_nc
        sta _a_n
        jsr _r_attr
        jmp @wrow
@wdone: rts

@cannon:
        ; the cannon, and the ball against it
        lda k_bx
        sta k_p
        lda #0
        sta k_q
        lda #171
        cmp k_bbot
        bcs @cnn                ; the ball ends above the cannon
        lda k_bx
        sec
        sbc k_pc
        cmp #160
        bcc :+
        adc #159                ; wrap at 160
:       cmp #8
        bcs @cnn                ; or is not in the cannon's eight pixels
        ldx #0
@cn:    stx k_x
        lda #183
        sec
        sbc k_x
        cmp k_btop
        bcc @cnn2
        cmp k_bbot
        beq :+
        bcs @cnn2
:       lda ROM+$1D88,x
        ldx k_pc
        jsr pix_on
        beq @cnn2
        lda #$40
        sta _cx_p0bl
@cnn2:  ldx k_x
        inx
        cpx #12
        bne @cn
@cnn:   ; drawn from its fixed characters
        lda k_pc
        sta _o_x
        and #3
        tax
        lda can_lo,x
        sta _o_src
        lda can_hi,x
        sta _o_src+1
        jsr _r_cannon

        lda k_mode
        cmp #MODE_SHOTS
        jne @diver

        ; which line's shape each line shows: decided once for all lines
        ; unless the shot stands right where the shape lands (shot_fast)
        ldx #SM_MIXED
        lda k_pb
        cmp #122
        bcc :+
        ldx #SM_NEW             ; right of every landing point
:       clc
        adc #8
        cmp #102
        bcs :+
        ldx #SM_OLD             ; left of every landing point
:       stx k_smode
        ; the cannon against the shots, if they are near each other at all
        lda k_pb
        sec
        sbc k_pc
        clc
        adc #7
        cmp #15
        bcs @scdone
        ldx #0
@sc:    stx k_i
        cpx #12
        bcs @scdone
        cpx k_top
        beq :+
        bcs @scdone
:       txa
        jsr shot_fast
        beq @scn
        sta k_gb
        lda k_pb
        sta k_pbb
        ldx k_i
        lda ROM+$1D88,x
        sta k_ga
        lda k_pc
        sta k_pa
        jsr overlap8
        beq @scn
        lda #$80
        sta _cx_pp
@scn:   ldx k_i
        inx
        jmp @sc
@scdone:
        ; the ball against the shots, if the ball is in their eight pixels
        lda k_bx
        sec
        sbc k_pb
        cmp #8
        bcs @bsdone
        lda #184
        sec
        sbc YPOS+2
        sta k_c                 ; first line of the band
        lda k_btop
        sta k_d
@bs:    lda k_d
        cmp k_bbot
        beq :+
        bcs @bsdone
:       cmp k_c
        bcc @bsn
        eor #$FF
        sec
        adc #183                ; x = 183 - d
        jsr shot_fast
        ldx k_pb
        jsr pix_on
        beq @bsn
        lda #$40
        sta _cx_p1bl
@bsn:   inc k_d
        jmp @bs
@bsdone:
        ; the shot's lines, bottom block first, into shbuf (line x at 79 - x)
        bit _nodraw
        bpl :+
        rts
:       lda #0
        .repeat 80, I
        sta shbuf+I
        .endrepeat
        sta k_xmax
        lda #$FF
        sta k_xmin
        lda #0
        sta k_j
@blk:   ldx k_j
        lda SHOTS,x
        jeq @blknext
        txa
        asl a
        asl a
        asl a
        sta k_c                 ; 8k
        cmp k_top
        beq :+
        jcs @blkdone
:       clc
        adc #7
        cmp k_top
        bcc :+
        lda k_top
:       sta k_x                 ; first line, from the top
        cmp k_xmax
        bcc :+
        sta k_xmax
:       ; last line: 8k-1 when the block below is empty, else 8k
        lda k_c
        sta k_last
        ldx k_j
        beq :+
        lda SHOTS-1,x
        bne :+
        dec k_last
:       lda k_last
        cmp k_xmin
        bcs :+
        sta k_xmin
:       lda #79
        sec
        sbc k_x
        sta k_i                 ; where line x goes
        lda k_smode
        cmp #SM_MIXED
.ifndef SLOWSHOT
        bne @fast
.endif
@bl:    lda k_x                 ; line by line
        jsr shot_seen
        ldx k_i
        sta shbuf,x
        inc k_i
        lda k_x
        cmp k_last
        beq @blknext
        dec k_x
        jmp @bl
@fast:  ; every line shows the shape of line a = x (SM_NEW) or x + 1
        ; (SM_OLD), which is block k's for a = 8k..8k+7: shot_new with the
        ; tests taken out of the loop
        ldx k_j
        lda SHOTS,x
        sta k_v
        lda #0
        cpx #9
        bcs :+
        lda SHOTS+1,x
:       sta k_vh                ; a = 8k+8: the block above
        lda k_c
        clc
        adc #8
        sta k_c8
        lda FRAME_LO            ; line a shows when a & FLICKER is this
        eor #$FF
        and FLICKER
        sta k_flp
        ldy k_x
        ldx k_c                 ; SM_NEW: down to a = 8k - the line below
        dex                     ; is the empty block's
        lda k_smode
        beq :+
        iny                     ; SM_OLD: a = x + 1, down to k_last + 1
        ldx k_last
:       stx k_ye                ; one past the last a
        ldx k_i
        cpy #80                 ; the first a may be past the shot's end
        bcs @fskip
        cpy YPOS+2
        bcc @fl
@fskip: inx
        dey
        cpy k_ye
        beq @blknext
@fl:    tya
        and FLICKER
        cmp k_flp
        bne @fn
        lda k_v
        cpy k_c8
        bcc :+
        lda k_vh
:       sta shbuf,x
@fn:    inx
        dey
        cpy k_ye
        bne @fl
@blknext:
        inc k_j
        lda k_j
        cmp #10
        jne @blk
@blkdone:
        ; and all of it drawn at once
        lda k_xmin
        cmp #$FF
        beq @nosh
        lda #183
        sec
        sbc k_xmax
        sta _o_d0
        lda #<(shbuf+79)
        sec
        sbc k_xmax
        sta _o_src
        lda #>(shbuf+79)
        sbc #0
        sta _o_src+1
        lda k_xmax
        sec
        sbc k_xmin
        clc
        adc #1
        sta _o_n
        lda k_pb
        sta _o_x
        jmp _r_column
@nosh:  rts

@diver: ; MODE_DIVER, $1132
        lda DIVER_FRAME
        bne :+
        rts
:       jsr frame_ptr
        sta p_g1
        stx p_g1+1
        lda #0
        sta k_band
        lda k_bx
        sta k_p
        lda #0
        sta k_q
        sta k_i
@dv:    ; row i from the top: kernel line x = ypos3 + 7 - i
        lda k_i
        eor #7
        clc
        adc YPOS+3
        sta k_x
        ldy #0                  ; its byte, if the line is in the band
        cmp k_top
        beq :+
        bcs @dvb
:       lda k_i
        eor #7
        tay
        lda (p_g1),y
        tay
@dvb:   tya
        ldx k_i
        sta src,x
        cmp #1
        rol k_band
        tya
        beq @dvn
        sta k_c
        ; display line 176 - ypos3 + i
        lda #176
        sec
        sbc YPOS+3
        clc
        adc k_i
        cmp k_btop
        bcc @dvcan
        cmp k_bbot
        beq :+
        bcs @dvcan
:       lda k_c
        ldx k_pb
        jsr pix_on
        beq @dvcan
        lda #$40
        sta _cx_p1bl
@dvcan: lda k_x
        cmp #12
        bcs @dvn
        tax
        lda ROM+$1D88,x
        sta k_ga
        lda k_pc
        sta k_pa
        lda k_c
        sta k_gb
        lda k_pb
        sta k_pbb
        jsr overlap8
        beq @dvn
        lda #$80
        sta _cx_pp
@dvn:   inc k_i
        lda k_i
        cmp #8
        jne @dv
        lda k_band
        bne :+
        rts
:       lda #176
        sec
        sbc YPOS+3
        sta k_d0
        sta _o_d0
        lda #<src
        sta _o_src
        lda #>src
        sta _o_src+1
        lda k_pb
        sta _o_x
        lda #0
        sta _o_col
        sta _o_flags
        lda #8
        sta _o_n
        jsr _r_prep8
        lda k_pb
        lsr a
        lsr a
        sta _o_cx
        sta k_bcx
        lda #3
        sta _o_nc
        sta k_bnc
        lda #<mask_demon
        sta _o_mask
        lda #>mask_demon
        sta _o_mask+1
        jsr _r_draw
        jsr cols_ptr
        jsr band_colours
        ; and the laser's colour back for the cannon's rows
        lda _colupf
        lsr a
        tax
        ldy _ted_colour,x
        ldx #R_B
        lda k_d0
        clc
        adc #8
        jmp ev_put

; ---------------------------------------------------------------------------
; the ball: %11 above row 21 (its colour is in the colour cells), %10 in
; the cannon's rows, whose colour cells hold the cannon's colour
draw_ball:
        bit _nodraw
        bpl :+
        rts
:
        lda _colupf
        bne :+
        rts
:       lda k_btop
        cmp k_bbot
        beq :+
        bcc :+
        rts
:       lda k_bx
        and #3
        tax
        lda ball_bits,x
        sta k_c
        lda k_bx
        lsr a
        lsr a
        sta _o_cx
        ; above row 21 all of the byte (%11), from it on %10 only
        lda k_btop
        sta _o_d0
        cmp #168
        bcs @low
        lda k_bbot
        cmp #168
        bcc :+
        lda #167
:       sec
        sbc k_btop
        clc
        adc #1
        sta _o_n
        lda k_c
        sta _o_val
        jsr _r_vline
        lda k_bbot
        cmp #168
        bcs :+
        rts
:       lda #168
        sta _o_d0
@low:   lda k_bbot
        sec
        sbc _o_d0
        clc
        adc #1
        sta _o_n
        lda k_c
        and #$AA
        sta _o_val
        jmp _r_vline

ball_bits:  .byte $C0, $30, $0C, $03
can_lo:     .byte <_cannon_img, <(_cannon_img+48), <(_cannon_img+96), <(_cannon_img+144)
can_hi:     .byte >_cannon_img, >(_cannon_img+48), >(_cannon_img+96), >(_cannon_img+144)

; ---------------------------------------------------------------------------
; kernel_asm: all of it, after r_begin and the fixed parts
_kernel_asm:
        lda #0
        sta _cx_p0bl
        sta _cx_p1bl
        sta _cx_pp
        ldy LASER_X
        lda _pixtab,y
        clc
        adc #2
        sta k_bx
        ldx #MODE_WRECK
        lda DEATH
        bne :+
        dex                     ; MODE_DIVER
        lda WAVE_FLAGS
        bpl :+
        dex                     ; MODE_SHOTS
:       stx k_mode
        ldx #0
        lda _back
        beq :+
        ldx #64
:       stx k_evi

        ; top of the picture: background and the score's colour
        lda FLASH
        lsr a
        tax
        ldy _ted_colour,x
        ldx #R_BG
        lda #<-1
        jsr ev_put
        lda SCORE_COL
        and COLMASK
        lsr a
        tax
        ldy _ted_colour,x
        ldx #R_A
        lda #<-1
        jsr ev_put

        jsr ball_scan
        jsr demon_zone

        ; $111D and $11B6: what the lower band reads when it starts
        lda _cx_pp
        sta T_DC
        lda #3
        sta T_BF
        lda k_mode
        bne :+
        lda _cx_p1bl
        sta T_BF
:       jsr lower_zone
        jsr draw_ball

        ; the ground: six lines of gradient, then the border
        lda GROUND_COL
        and COLMASK
        sta k_g
        lda #0
        sta k_i
@gr:    lda k_i
        asl a
        eor #$FF
        sec
        adc k_g                 ; g - 2i
        lsr a
        tax
        ldy _ted_colour,x
        ldx #R_B
        lda k_i
        lsr a
        bcc :+
        ldx #R_A
:       lda k_i
        clc
        adc #185
        jsr ev_put
        inc k_i
        lda k_i
        cmp #6
        bne @gr
        lda k_g
        sec
        sbc #12
        sta E7                  ; the kernel's last use of $E7
        lsr a
        tax
        ldy _ted_colour,x
        ldx #R_BORDER
        lda #191
        jsr ev_put
        bit _nodraw
        bmi :+
        ldx k_evi
        lda #FRAME_LINE
        sta _ev_line,x
        lda #FRAME_REG
        sta _ev_reg,x
:

        ; what Y holds after the kernel
        ldx PLAYER
        lda COOP
        bpl :+
        ldx #0
:       lda LIVES,x
        sta _yreg
        rts
