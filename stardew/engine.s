; ---------------------------------------------------------------------------
; engine.s - the Plus/4 end of Stardew Pond
;
; What has to be fast or on time lives here:
;
;   1. The raster interrupt. Two stops per picture: one inside the black
;      line between map and toolbar, where the toolbar gets its own
;      character set and colours, and one below the picture, where a
;      finished picture is swapped in and the map's colours come back.
;
;   2. Figures. The map is multicolour characters and does not change while
;      someone walks over it. Every figure is drawn into characters handed
;      out afresh for every picture, over a copy of the map character it
;      covers, through a mask: pixels of colour %00 are see-through.
;
;   3. The keyboard and joysticks, read straight off the matrix.
;
; The ideas are the ones worked out for Demon Attack (two pictures, a pool
; of characters, shift tables); what is new is the mask, the colour cells
; and the map image the pool is restored from.
; ---------------------------------------------------------------------------

        .setcpu "6502"
        .macpack longbranch

        .export _eng_init, _eng_blank, _eng_unblank, _eng_fill, _eng_put
        .export _eng_romfont, _eng_reset
        .export _r_begin, _r_fig, _r_done
        .export _frames, _back, _ready, _menu
        .export _pal_map, _pal_hud
        .export _f_x, _f_y, _f_h, _f_flip, _f_col
        .exportzp _f_src
        .export _put_code, _put_attr
        .export _key_row, _joy
        .export _snd_time
        .export _pool_left, _eng_stack
        .export _keys_irq, _eng_keys, _dbg_keys
        .export _music, _eng_sfx, _sfx_lo, _sfx_hi, _sfx_noise, _sfx_len
        .import _mus_v1, _mus_v2, _mus_s1, _mus_s2, _ton_lo, _ton_hi
        .importzp sp
        .export _base_code, _base_attr

; ---- TED ------------------------------------------------------------------

TED_SCROLLY = $FF06
TED_CTRL2   = $FF07
TED_KEYS    = $FF08
TED_IRQ     = $FF09
TED_IRQEN   = $FF0A
TED_RCMP    = $FF0B
TED_SOUND   = $FF11
TED_V1LO    = $FF0E
TED_V2LO    = $FF0F
TED_V2HI    = $FF10
TED_BMBASE  = $FF12
TED_CHBASE  = $FF13
TED_VMBASE  = $FF14
TED_BG      = $FF15
TED_COL1    = $FF16
TED_COL2    = $FF17
TED_BORDER  = $FF19
KEY_ROW     = $FD30

; ---- memory ---------------------------------------------------------------

FONT0       = $C000             ; map characters, picture 0
FONT1       = $C800             ; the same, picture 1
MAT0        = $D000             ; colours; codes at +$400
MAT1        = $D800
HUDF        = $E000             ; toolbar and menu characters

MAP_ROWS    = 22
MAP_CELLS   = MAP_ROWS * 40
TILE_CHARS  = 176               ; codes 0..175 come from the tile set
POOL        = TILE_CHARS        ; 176..255 are handed out per picture
POOL_N      = 256 - POOL

HUD_LINE    = 183               ; inside row 22, the black separator
BOTTOM_LINE = 206               ; below the picture

; ---- zero page ------------------------------------------------------------

        .segment "ENGZP": zeropage
_f_src:     .res 2              ; figure: 2 bytes per line, top line first
p_shr:      .res 2              ; shift table: the byte's own share
p_shl:      .res 2              ; and its spill into the next byte
p_d:        .res 2              ; column data, biased to the cell
p_n:        .res 2              ; column mask (inverted), biased likewise
p_dst:      .res 2              ; character being drawn into
p_src:      .res 2
p_scr:      .res 2              ; matrix cell
p_a:        .res 2
p_b:        .res 2
p_c:        .res 2
z_si:       .res 1
z_b0:       .res 1
z_b1:       .res 1
z_t:        .res 1
z_m0:       .res 1
z_m1:       .res 1
z_m2:       .res 1
z_lr:       .res 1
z_rbit:     .res 1
z_ly0:      .res 1
z_row0:     .res 1
z_row:      .res 1
z_cx:       .res 1
z_col:      .res 1
z_c:        .res 1
z_fp:       .res 1
z_f11:      .res 1
z_ol:       .res 1
z_oh:       .res 1
z_old:      .res 1
z_i:        .res 1
z_cnt:      .res 1
p_cll:      .res 2              ; cell list of the back buffer: low bytes
p_clh:      .res 2              ; and high bytes
cl_cur:     .res 1              ; cells noted so far in this picture
z_scrhi:    .res 1              ; high bytes of the back buffer's codes,
z_atthi:    .res 1              ; colours
z_fonthi:   .res 1              ; and characters
z_a0:       .res 3              ; pixels seen per column in this cell row
z_h0:       .res 3              ; %11 pixels seen per column

; ---- ordinary memory ------------------------------------------------------

        .bss
_frames:    .res 1              ; pictures shown, 50 a second
_back:      .res 1              ; the picture being drawn: 0 or 1
_ready:     .res 1              ; set when it is complete; the IRQ shows it
_menu:      .res 1              ; not 0: the whole screen is toolbar characters
_pal_map:   .res 4              ; background, %01, %10, border of the map
_pal_hud:   .res 3              ; background, %01, %10 of toolbar and menus
_snd_time:  .res 1              ; frames until the sound stops, 0 = off
_pool_left: .res 1              ; characters left over in the last picture
_keys_irq:  .res 1              ; keys down now (K_... in game.h)
keys_hit:   .res 1              ; keys that went down since eng_keys
_dbg_keys:  .res 1              ; keys as if pressed, set by the tests
kprev:      .res 1
kj1:        .res 1
kj2:        .res 1
kr:         .res 1
_music:     .res 1              ; the song wanted: 0 none, SONG_... in data.h
mcur:       .res 1              ; the song playing
m1i:        .res 1              ; where each voice is in its notes
m2i:        .res 1
m1t:        .res 1              ; frames left on each voice's note
m2t:        .res 1
mnote:      .res 1
m2note:     .res 1              ; the accompaniment's note, for after an effect
_sfx_lo:    .res 1              ; eng_sfx: frequency,
_sfx_hi:    .res 1
_sfx_noise: .res 1              ; noise or square,
_sfx_len:   .res 1              ; and how many frames
m_t:        .res 1
front:      .res 1
phase:      .res 1

_f_x:       .res 1              ; multicolour pixel of the left edge, 0..152
_f_y:       .res 1              ; display line of the top line, 0..175
_f_h:       .res 1              ; lines, up to 24
_f_flip:    .res 1              ; 1: mirrored
_f_col:     .res 1              ; colour cell for its %11 pixels, 0: none

_put_code:  .res 1
_put_attr:  .res 1

next_code:  .res 1
cl_n:       .res 2
cl_lo0:     .res POOL_N         ; cells handed a character, picture 0
cl_hi0:     .res POOL_N
cl_lo1:     .res POOL_N         ; the same, picture 1
cl_hi1:     .res POOL_N

fpx:        .res 3              ; per column: bit k = pixels in cell row k
f11:        .res 3              ; per column: bit k = %11 pixels in cell row k

; Three columns of a figure, its lines in the middle and 8 lines of nothing
; either side, so the eight lines of any cell it touches can be read
; without looking where the figure ends.
COLSZ = 48
cd0:        .res COLSZ
cd1:        .res COLSZ
cd2:        .res COLSZ
cn0:        .res COLSZ
cn1:        .res COLSZ
cn2:        .res COLSZ

; The map as it is without figures: codes and colours, 22 rows of 40. On
; a boundary of $400, so an offset's high byte can be ORed in.
        .segment "MAPIMG"
_base_code: .res $400
_base_attr: .res $400
BASEC = _base_code
BASEA = _base_attr

        .segment "TABLES"
        .align 256
shr_tab:    .res 4*256          ; [sub][b]: b shifted right by sub pixels
shl_tab:    .res 4*256          ; [sub][b]: what falls out into the next byte
nmaskof:    .res 256            ; %00 for every pixel that is not %00, else %11
revmc:      .res 256            ; the four pixels in reverse order
has11:      .res 256            ; not 0 if a pixel is %11
dark11:     .res 256            ; the byte with its %11 pixels made %01
code_lo:    .res 256            ; code * 8
code_hi:    .res 256

        .rodata
row_lo:     .repeat 25, R
            .byte <(R*40)
            .endrepeat
row_hi:     .repeat 25, R
            .byte >(R*40)
            .endrepeat
font_hi:    .byte >FONT0, >FONT1
scr_hi:     .byte >(MAT0+$400), >(MAT1+$400)
att_hi:     .byte >MAT0, >MAT1
cll_hi:     .byte >cl_lo0, >cl_lo1
cll_lo:     .byte <cl_lo0, <cl_lo1
clh_lo:     .byte <cl_hi0, <cl_hi1
clh_hi:     .byte >cl_hi0, >cl_hi1

        .code

; ===========================================================================
; Start-up
; ===========================================================================

_eng_init:
        sei
        ; --- shift tables ---------------------------------------------------
        ; sub 0..3 multicolour pixels = 0, 2, 4, 6 bits
        ldx #0
@sh:    txa
        sta shr_tab,x           ; sub 0: as it is, nothing spills
        lda #0
        sta shl_tab,x
        txa
        lsr a
        lsr a
        sta shr_tab+256,x
        lsr a
        lsr a
        sta shr_tab+512,x
        lsr a
        lsr a
        sta shr_tab+768,x
        txa
        asl a
        asl a
        asl a
        asl a
        asl a
        asl a
        sta shl_tab+256,x       ; the low pixel, now the top one of the next
        txa
        asl a
        asl a
        asl a
        asl a
        sta shl_tab+512,x
        txa
        asl a
        asl a
        sta shl_tab+768,x
        ; mask, reversal and %11 for byte X, pixel by pixel
        stx z_t
        lda #0
        sta z_m0                ; mask
        sta z_m1                ; reversed
        sta z_m2                ; %11 seen
        ldy #4
@px:    lda z_t
        and #3
        sta z_b0
        ; reversed: shift the pixel in from the right
        asl z_m1
        asl z_m1
        ora z_m1
        sta z_m1
        ; mask
        lsr z_m0
        lsr z_m0
        lda z_b0
        beq :+
        lda z_m0
        ora #$C0
        sta z_m0
:       lda z_b0
        cmp #3
        bne :+
        inc z_m2
:       lsr z_t
        lsr z_t
        dey
        bne @px
        lda z_m0
        eor #$FF
        sta nmaskof,x
        lda z_m1
        sta revmc,x
        lda z_m2
        sta has11,x
        txa                     ; %11 -> %01: clear the high bit of each
        asl a                   ; pair whose low bit is set as well
        sta z_t
        txa
        and z_t
        and #$AA
        sta z_t
        txa
        eor z_t
        sta dark11,x
        ; code * 8
        txa
        asl a
        asl a
        asl a
        sta code_lo,x
        txa
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        sta code_hi,x
        inx
        beq :+
        jmp @sh
:
        ; the lines around a figure's columns: nothing, and see-through
        ldx #7
@pad:   lda #0
        sta cd0,x
        sta cd1,x
        sta cd2,x
        lda #$FF
        sta cn0,x
        sta cn1,x
        sta cn2,x
        dex
        bpl @pad

        lda #0
        sta cl_n
        sta cl_n+1
        sta _ready
        sta front
        sta _menu
        sta _snd_time
        lda #1
        sta _back
        lda #POOL
        sta next_code

        lda #<irq
        sta $FFFE
        lda #>irq
        sta $FFFF
        lda #<nmi
        sta $FFFA
        lda #>nmi
        sta $FFFB
        cli
        rts

nmi:    rti

; eng_stack: cc65's stack to $F800-$FCFF. The start-up code puts it right
; after the program's memory, which here is the character sets. Called
; first thing in main(), which has nothing on the stack that it needs.
_eng_stack:
        lda #<$FD00
        sta sp
        lda #>$FD00
        sta sp+1
        rts

; eng_blank: the screen off and no interrupt at all - for the disk. The
; KERNAL runs with the ROM switched in and would take our interrupt with its
; own handler, so there must not be one.
_eng_blank:
        sei
        lda #0
        sta TED_IRQEN
        lda TED_IRQ
        sta TED_IRQ
        lda TED_SCROLLY
        and #$EF
        sta TED_SCROLLY
        lda #0
        sta TED_SOUND
        sta _snd_time
        cli
        rts

; eng_unblank: the TED set up for the game, the picture on screen shown,
; the interrupt running.
_eng_unblank:
        sei
        lda #$98                ; 256 characters, multicolour, 40 columns
        sta TED_CTRL2
        lda TED_BMBASE
        and #$FB                ; characters from RAM
        sta TED_BMBASE
        ldx front
        lda att_hi,x
        sta TED_VMBASE
        jsr pal_top
        lda #0
        sta phase
        lda #HUD_LINE
        sta TED_RCMP
        lda #$02                ; raster interrupt, compare bit 8 = 0
        sta TED_IRQEN
        lda TED_IRQ
        sta TED_IRQ
        lda #$1B                ; text, display on, 25 rows, y scroll 3
        sta TED_SCROLLY
        cli
        rts

; A cold start: the game has used all of the machine.
_eng_reset:
        sei
        lda #0
        sta TED_IRQEN
        sta $FF3E               ; ROM in
        jmp ($FFFC)

; eng_romfont: the first 64 characters of the ROM - capitals, digits,
; signs - into the toolbar character set. Code 0 stays what the toolbar
; set has there (the separator), it is '@' in the ROM.
_eng_romfont:
        php
        sei
        sta $FF3E               ; ROM in
        ldx #8
:       lda $D000,x
        sta HUDF,x
        inx
        bne :-
:       lda $D100,x
        sta HUDF+256,x
        inx
        bne :-
        sta $FF3F               ; ROM out
        plp
        rts

; ===========================================================================
; The raster interrupt
; ===========================================================================

irq:    pha
        txa
        pha
        tya
        pha
        lda TED_IRQ
        sta TED_IRQ
        lda phase
        bne @bottom
        ; inside the separator row: the toolbar's characters and colours.
        ; The row is all %11 in a black colour cell in both character
        ; sets, so it looks the same whenever the writes land.
        lda _menu
        bne :+
        lda _pal_hud
        sta TED_BG
        lda _pal_hud+1
        sta TED_COL1
        lda _pal_hud+2
        sta TED_COL2
        lda #>HUDF
        sta TED_CHBASE
:       lda #1
        sta phase
        lda #BOTTOM_LINE
        sta TED_RCMP
        jmp @out

@bottom:
        lda _ready
        beq @same
        lda _back
        sta front
        tax
        lda att_hi,x
        sta TED_VMBASE
        txa
        eor #1
        sta _back
        lda #0
        sta _ready
@same:  inc _frames
        jsr pal_top
        jsr kpoll
        jsr mplay
        lda _snd_time
        beq :+
        dec _snd_time
        bne :+
        jsr sfx_end
:       lda #0
        sta phase
        lda #HUD_LINE
        sta TED_RCMP
@out:   pla
        tay
        pla
        tax
        pla
        rti

; the top of the picture: map characters and colours, or menu ones
pal_top:
        lda _menu
        bne @m
        ldx front
        lda font_hi,x
        sta TED_CHBASE
        lda _pal_map
        sta TED_BG
        lda _pal_map+1
        sta TED_COL1
        lda _pal_map+2
        sta TED_COL2
        lda _pal_map+3
        sta TED_BORDER
        rts
@m:     lda #>HUDF
        sta TED_CHBASE
        lda _pal_hud
        sta TED_BG
        lda _pal_hud+1
        sta TED_COL1
        lda _pal_hud+2
        sta TED_COL2
        lda #0
        sta TED_BORDER
        rts

; ===========================================================================
; The map image
; ===========================================================================

; eng_fill: the map rows of both pictures from the map image. Whatever
; figures stood there are gone, and so is any note of them.
_eng_fill:
        lda #>BASEC
        sta p_src+1
        lda #>BASEA
        sta p_a+1
        lda #>(MAT0+$400)
        sta p_dst+1
        lda #>(MAT1+$400)
        sta p_b+1
        lda #>MAT0
        sta p_scr+1
        lda #>MAT1
        sta p_c+1
        lda #0
        sta p_src
        sta p_a
        sta p_dst
        sta p_b
        sta p_scr
        sta p_c
        ldx #>MAP_CELLS         ; whole pages first
        ldy #0
@pg:    lda (p_src),y
        sta (p_dst),y
        sta (p_b),y
        lda (p_a),y
        sta (p_scr),y
        sta (p_c),y
        iny
        bne @pg
        inc p_src+1
        inc p_a+1
        inc p_dst+1
        inc p_b+1
        inc p_scr+1
        inc p_c+1
        dex
        bne @pg
@rest:  lda (p_src),y
        sta (p_dst),y
        sta (p_b),y
        lda (p_a),y
        sta (p_scr),y
        sta (p_c),y
        iny
        cpy #<MAP_CELLS
        bne @rest
        lda #0
        sta cl_n
        sta cl_n+1
        lda #POOL
        sta next_code
        rts

; eng_put(offset): put_code and put_attr into one cell of the map image and
; of both pictures. A figure standing there loses that cell for a picture.
_eng_put:
        sta p_a
        sta p_b
        sta p_c
        sta p_dst
        sta p_scr
        sta p_src
        txa
        ora #>BASEC
        sta p_a+1
        txa
        ora #>BASEA
        sta p_b+1
        txa
        ora #>(MAT0+$400)
        sta p_c+1
        txa
        ora #>(MAT1+$400)
        sta p_dst+1
        txa
        ora #>MAT0
        sta p_scr+1
        txa
        ora #>MAT1
        sta p_src+1
        ldy #0
        lda _put_code
        sta (p_a),y
        sta (p_c),y
        sta (p_dst),y
        lda _put_attr
        sta (p_b),y
        sta (p_scr),y
        sta (p_src),y
        rts

; ===========================================================================
; Pictures
; ===========================================================================

; r_begin: start a picture in the back buffer. Every cell handed a character
; the last time this buffer was drawn gets its map code and colour back.
_r_begin:
        ldx _back
        lda cll_lo,x
        sta p_cll
        lda cll_hi,x
        sta p_cll+1
        lda clh_lo,x
        sta p_clh
        lda clh_hi,x
        sta p_clh+1
        lda scr_hi,x
        sta z_scrhi
        lda att_hi,x
        sta z_atthi
        lda font_hi,x
        sta z_fonthi
        lda cl_n,x
        beq @done
        sta z_cnt
        ldy #0
@cell:  sty z_i
        lda (p_cll),y           ; low byte of the offset
        sta p_src
        sta p_dst
        sta p_c
        sta p_scr
        lda (p_clh),y           ; high byte
        tax
        ora #>BASEC
        sta p_src+1
        txa
        ora #>BASEA
        sta p_c+1
        txa
        ora z_scrhi
        sta p_dst+1
        txa
        ora z_atthi
        sta p_scr+1
        ldy #0
        lda (p_src),y
        sta (p_dst),y
        lda (p_c),y
        sta (p_scr),y
        ldy z_i
        iny
        dec z_cnt
        bne @cell
@done:  lda #0
        sta cl_cur
        lda #POOL
        sta next_code
        rts

; r_done: the picture is complete - show it at the bottom of the next one.
_r_done:
        ldx _back
        lda cl_cur
        sta cl_n,x
        lda next_code
        beq :+
        eor #$FF                ; 256 - next_code
        clc
        adc #1
:       sta _pool_left
        lda #1
        sta _ready
        rts

; r_fig: one figure into the back buffer.
;   f_src  2 bytes per line, f_h lines; pixels %00 are see-through
;   f_x    multicolour pixel of the left edge (0..152)
;   f_y    display line of the top line (0..175)
;   f_flip 1: mirrored
;   f_col  colour cell for cells where the figure has %11 pixels (0: none)
; Figures are drawn in order; a later one covers an earlier one.
_r_fig:
        ; --- the three columns, shifted into place ------------------------
        lda _f_x
        and #3
        tax
        clc
        adc #>shr_tab
        sta p_shr+1
        txa
        clc
        adc #>shl_tab
        sta p_shl+1
        lda #0
        sta p_shr
        sta p_shl
        sta z_si
        sta fpx
        sta fpx+1
        sta fpx+2
        sta f11
        sta f11+1
        sta f11+2
        sta z_a0
        sta z_a0+1
        sta z_a0+2
        sta z_h0
        sta z_h0+1
        sta z_h0+2
        lda _f_y
        and #7
        sta z_ly0
        sta z_lr
        lda #1
        sta z_rbit
        ldx #0
@line:  ldy z_si
        lda (_f_src),y
        sta z_b0
        iny
        lda (_f_src),y
        sta z_b1
        iny
        sty z_si
        lda _f_flip
        beq @nf
        ldy z_b0
        lda revmc,y
        pha
        ldy z_b1
        lda revmc,y
        sta z_b0
        pla
        sta z_b1
@nf:    ; the pixels, shifted into three columns; a column's mask is read
        ; off its own pixels, since %00 is exactly what is see-through
        ldy z_b0
        lda (p_shr),y
        sta cd0+8,x
        tay
        ora z_a0
        sta z_a0
        lda nmaskof,y
        sta cn0+8,x
        lda has11,y
        ora z_h0
        sta z_h0
        ldy z_b0
        lda (p_shl),y
        sta z_t
        ldy z_b1
        lda (p_shr),y
        ora z_t
        sta cd1+8,x
        tay
        ora z_a0+1
        sta z_a0+1
        lda nmaskof,y
        sta cn1+8,x
        lda has11,y
        ora z_h0+1
        sta z_h0+1
        ldy z_b1
        lda (p_shl),y
        sta cd2+8,x
        tay
        ora z_a0+2
        sta z_a0+2
        lda nmaskof,y
        sta cn2+8,x
        lda has11,y
        ora z_h0+2
        sta z_h0+2
        ; the next line; the next cell row every 8
        inc z_lr
        lda z_lr
        cmp #8
        bne :+
        jsr fold
        lda #0
        sta z_lr
        asl z_rbit
:       inx
        cpx _f_h
        jne @line
        jsr fold
        ; 8 lines of nothing after the figure
        ldy #8
@tail:  lda #0
        sta cd0+8,x
        sta cd1+8,x
        sta cd2+8,x
        lda #$FF
        sta cn0+8,x
        sta cn1+8,x
        sta cn2+8,x
        inx
        dey
        bne @tail

        ; --- the columns onto the screen, cell by cell ----------------------
        lda _f_y
        lsr a
        lsr a
        lsr a
        sta z_row0
        lda _f_x
        lsr a
        lsr a
        sta z_cx
        lda #0
        sta z_c
@col:   ldx z_c
        lda z_cx
        clc
        adc z_c
        cmp #40
        jcs @nextc
        sta z_col
        lda fpx,x
        jeq @nextc
        sta z_fp
        lda f11,x
        sta z_f11
        ; column data from line -ly0: (p_d),y is the cell's line y
        lda #8
        sec
        sbc z_ly0
        clc
        adc col_d_lo,x
        sta p_d
        lda col_d_hi,x
        adc #0
        sta p_d+1
        lda #8
        sec
        sbc z_ly0
        clc
        adc col_n_lo,x
        sta p_n
        lda col_n_hi,x
        adc #0
        sta p_n+1
        lda z_row0
        sta z_row
@cell:  lsr z_fp
        jcc @skip
        lda z_row
        cmp #MAP_ROWS
        jcs @nextc
        jsr cell_get
        jcs @nextc              ; no characters left
        ; Where the figure has %11 pixels the cell takes the figure's
        ; colour. Whatever of the map was %11 there would take it too, so
        ; it turns dark instead - a shadow, not a patch of the figure's
        ; colour.
        lda z_f11
        lsr a
        bcc @mask
        lda _f_col
        beq @mask
        .repeat 8, L
        ldy #L
        lda (p_dst),y
        tax
        lda dark11,x
        sta (p_dst),y
        .endrepeat
@mask:  ; mask and pixels into the character, all 8 lines
        .repeat 8, L
        ldy #L
        lda (p_dst),y
        and (p_n),y
        ora (p_d),y
        sta (p_dst),y
        .endrepeat
        ; the colour cell, where the figure has %11 pixels
        lda z_f11
        lsr a
        bcc @skip
        lda _f_col
        beq @skip
        lda z_oh
        ora z_atthi
        sta p_scr+1
        lda z_ol
        sta p_scr
        ldy #0
        lda _f_col
        sta (p_scr),y
@skip:  lsr z_f11
        lda z_fp
        beq @nextc
        inc z_row
        lda p_d
        clc
        adc #8
        sta p_d
        bcc :+
        inc p_d+1
:       lda p_n
        clc
        adc #8
        sta p_n
        jcc @cell
        inc p_n+1
        jmp @cell
@nextc: inc z_c
        lda z_c
        cmp #3
        jcc @col
        rts

; the cell row just finished: its bit into fpx and f11 where the columns
; had pixels, and the accumulators cleared. Keeps X.
fold:   ldy #2
@f:     lda z_a0,y
        beq @e
        lda z_rbit
        ora fpx,y
        sta fpx,y
        lda z_h0,y
        beq @e
        lda z_rbit
        ora f11,y
        sta f11,y
@e:     lda #0
        sta z_a0,y
        sta z_h0,y
        dey
        bpl @f
        rts

col_d_lo:   .byte <cd0, <cd1, <cd2
col_d_hi:   .byte >cd0, >cd1, >cd2
col_n_lo:   .byte <cn0, <cn1, <cn2
col_n_hi:   .byte >cn0, >cn1, >cn2

; cell_get: the character of cell (z_row, z_col) in the back buffer, for
; drawing into; p_dst points at its 8 bytes, z_ol/z_oh is the cell's
; offset. A cell still showing its map character is handed a character of
; the pool with a copy of the map character in it. Carry set if the pool
; is empty.
cell_get:
        ldx z_row
        lda row_lo,x
        clc
        adc z_col
        sta z_ol
        sta p_scr
        lda row_hi,x
        adc #0
        sta z_oh
        ora z_scrhi
        sta p_scr+1
        ldy #0
        lda (p_scr),y
        cmp #POOL
        bcs @have
        tax                     ; the map character
        lda next_code
        beq @none
        sta (p_scr),y
        inc next_code
        ldy cl_cur              ; note the cell
        lda z_ol
        sta (p_cll),y
        lda z_oh
        sta (p_clh),y
        inc cl_cur
        lda code_lo,x
        sta p_src
        lda code_hi,x
        ora z_fonthi
        sta p_src+1
        ldx next_code
        dex
        lda code_lo,x
        sta p_dst
        lda code_hi,x
        ora z_fonthi
        sta p_dst+1
        .repeat 8, L
        ldy #L
        lda (p_src),y
        sta (p_dst),y
        .endrepeat
        clc
        rts
@have:  tax
        lda code_lo,x
        sta p_dst
        lda code_hi,x
        ora z_fonthi
        sta p_dst+1
        clc
        rts
@none:  sec
        rts

; ===========================================================================
; Music
;
; Two voices, each a list of note and length (tools/mkdata.py, from
; data/music.txt), 255 at the end of a song. A note is sounded for all
; but the last GATE frames of its length, so repeated notes are heard as
; two. While a sound effect plays the voices keep time but stay quiet; the
; next note after it brings them back.
; ===========================================================================

GATE = 4
MVOL = 5

mplay:  lda _music
        cmp mcur
        beq @run
        sta mcur                ; another song: from its start
        tax
        jeq @quiet
        lda _mus_s1-1,x
        sta m1i
        lda _mus_s2-1,x
        sta m2i
        lda #1
        sta m1t
        sta m2t
@run:   lda mcur
        bne :+
        rts
:       ; --- voice 1 ---
        dec m1t
        bne @gate1
        ldx m1i
        lda _mus_v1,x
        cmp #255
        bne :+
        ldy mcur
        ldx _mus_s1-1,y
        lda _mus_v1,x
:       sta mnote
        lda _mus_v1+1,x
        sta m1t
        inx
        inx
        stx m1i
        ldx mnote
        beq @off1
        lda _ton_lo,x
        sta TED_V1LO
        lda TED_BMBASE
        and #$FC
        ora _ton_hi,x
        sta TED_BMBASE
        lda TED_SOUND
        and #$F0
        ora #$10 | MVOL
        sta TED_SOUND
        jmp @v2
@gate1: lda m1t
        cmp #GATE
        bne @v2
@off1:  lda TED_SOUND
        and #$EF
        sta TED_SOUND
@v2:    ; --- voice 2 ---
        dec m2t
        bne @gate2
        ldx m2i
        lda _mus_v2,x
        cmp #255
        bne :+
        ldy mcur
        ldx _mus_s2-1,y
        lda _mus_v2,x
:       sta mnote
        lda _mus_v2+1,x
        sta m2t
        inx
        inx
        stx m2i
        lda mnote
        sta m2note
        lda _snd_time
        bne @done
        ldx mnote
        beq @off2
        lda _ton_lo,x
        sta TED_V2LO
        lda _ton_hi,x
        sta TED_V2HI
        lda TED_SOUND
        and #$B0                ; no noise
        ora #$20 | MVOL
        sta TED_SOUND
@done:  rts
@gate2: lda m2t
        cmp #GATE
        bne @done
        lda _snd_time
        bne @done
@off2:  lda TED_SOUND
        and #$DF
        sta TED_SOUND
        rts
@quiet: lda TED_SOUND
        and #$8F
        sta TED_SOUND
        rts

; Sound effects borrow voice 2 - the accompaniment - and leave the tune on
; voice 1 alone. eng_sfx starts one; when it is over the accompaniment
; comes back at once with the note it would be playing now.
_eng_sfx:
        php
        sei
        lda _sfx_lo
        sta TED_V2LO
        lda _sfx_hi
        sta TED_V2HI
        lda _sfx_noise
        beq :+
        lda #$40 | MVOL         ; voice 2 as noise
        bne :++
:       lda #$20 | MVOL         ; voice 2 as a square
:       sta m_t
        lda TED_SOUND
        and #$90                ; keep voice 1 and D/A mode
        ora m_t
        sta TED_SOUND
        lda _sfx_len
        sta _snd_time
        plp
        rts

sfx_end:
        lda TED_SOUND
        and #$9F                ; voice 2 off, square and noise
        sta TED_SOUND
        lda mcur
        beq @r
        ldx m2note
        beq @r
        lda m2t
        cmp #GATE + 1
        bcc @r                  ; the note is ending anyway
        lda _ton_lo,x
        sta TED_V2LO
        lda _ton_hi,x
        sta TED_V2HI
        lda TED_SOUND
        and #$B0
        ora #$20 | MVOL
        sta TED_SOUND
@r:     rts

; ===========================================================================
; Keyboard and joysticks
;
; The interrupt reads them once a picture (kpoll) and notes every key that
; goes down, so a short press is not lost while the program is busy - with
; drawing a menu, say. eng_keys hands the presses over.
;
; The row goes to both latches, and $FF08 is read twice: the first read
; still sees the value just written (see the Phoenix clone's README).
; Both return 1 bits for keys that are down.
; ===========================================================================

; The bits are game.h's K_ constants: up 1, down 2, left 4, right 8,
; fire 16, previous 32, next 64, menu 128.
kpoll:  ldx #$FF
        stx KEY_ROW
        lda #$FB                ; joystick 1
        jsr krd
        sta kj1
        lda #$FD                ; joystick 2
        jsr krd
        sta kj2
        lda kj1
        ora kj2
        and #$0F                ; up down left right
        sta kr
        lda kj1
        and #$40
        ora kj2
        and #$C0
        beq :+
        lda #16
        ora kr
        sta kr
:       lda #$BF                ; cursor left, cursor right, Esc
        jsr krow
        tax
        and #$01
        beq :+
        lda #4
        ora kr
        sta kr
:       txa
        and #$08
        beq :+
        lda #8
        ora kr
        sta kr
:       txa
        and #$10
        beq :+
        lda #128
        ora kr
        sta kr
:       lda #$DF                ; cursor down, cursor up, '.', ','
        jsr krow
        tax
        and #$01
        beq :+
        lda #2
        ora kr
        sta kr
:       txa
        and #$08
        beq :+
        lda #1
        ora kr
        sta kr
:       txa
        and #$10
        beq :+
        lda #64
        ora kr
        sta kr
:       txa
        and #$80
        beq :+
        lda #32
        ora kr
        sta kr
:       lda #$7F                ; space
        jsr krow
        and #$10
        beq :+
        lda #16
        ora kr
        sta kr
:       lda #$EF                ; I
        jsr krow
        and #$02
        beq :+
        lda #128
        ora kr
        sta kr
:       lda #$FE                ; Return
        jsr krow
        and #$02
        beq :+
        lda #16
        ora kr
        sta kr
:       lda #$FF
        sta TED_KEYS
        sta KEY_ROW
        lda kr
        ora _dbg_keys
        sta _keys_irq
        tax
        lda kprev
        eor #$FF
        stx kprev
        and _keys_irq
        ora keys_hit
        sta keys_hit
        rts

; a row of the matrix (A), read twice: the first read is the value written
krow:   sta KEY_ROW
krd:    sta TED_KEYS
        lda TED_KEYS
        lda TED_KEYS
        eor #$FF
        rts

; eng_keys: the keys that went down since the last call
_eng_keys:
        php
        sei
        lda keys_hit
        ldx #0
        stx keys_hit
        plp
        rts

; key_row(row): the keys of one row of the matrix
_key_row:
        php
        sei
        sta KEY_ROW
        sta TED_KEYS
        lda TED_KEYS
        lda TED_KEYS
        eor #$FF
        tax
        lda #$FF
        sta TED_KEYS
        txa
        ldx #0
        plp
        rts

; joy(sel): a joystick, $FB port 1, $FD port 2
_joy:
        php
        sei
        ldx #$FF
        stx KEY_ROW
        sta TED_KEYS
        lda TED_KEYS
        lda TED_KEYS
        eor #$FF
        tax
        lda #$FF
        sta TED_KEYS
        txa
        ldx #0
        plp
        rts
