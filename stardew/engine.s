; ---------------------------------------------------------------------------
; engine.s - the Plus/4 end of Stardew Pond
;
; What has to be fast or on time lives here:
;
;   1. The raster interrupt. Two stops per picture: one inside the black
;      line between map and toolbar, where the toolbar gets its own
;      character set and colours, and one in the vertical blank, where a
;      finished picture is swapped in and the map's colours come back.
;
;      A real TED draws a pixel of colour $7F wherever one of its colour
;      registers ($FF15-$FF19) is written while that colour is on the beam
;      - even when the value is the same. So they are only ever written
;      where nothing shows them: in the vertical blank (lines 251-268,
;      not even the border is drawn), and the toolbar's in the black row,
;      where every pixel is the cell's own black. The screen is switched
;      on and off in the vertical blank too, never halfway down a picture.
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
        .export _eng_hide, _eng_show, _scr_hidden
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
        .export _keys_irq, _eng_keys, _dbg_keys, _fire_down
        .export _music, _eng_sfx, _sfx_lo, _sfx_hi, _sfx_noise, _sfx_len
        .import _mus_v1, _mus_v2, _mus_s1, _mus_s2, _ton_lo, _ton_hi
        .importzp sp
        .export _base_code, _base_attr
        .export _fig_add, _figs_draw, _nfig
        .export _water_n, _water_ab, _water_ph
        .export _fa_x, _fa_y, _fa_s, _fa_f, _fa_c
        .export _blocked_at, _bk_x, _bk_y
        .import _spr_tab, _spr_h, _room, _mt_flag

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

HUD_LINE    = 181               ; inside row 22 (lines 179-186), the black
                                ; separator, past its DMA line
VBL_LINE    = 251               ; vertical blank: lines 251-268 are not drawn

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
p_pf:       .res 2              ; the figure's pixel bits
z_h2:       .res 1              ; its lines * 2
z_s:        .res 1              ; its shift, 0..3 pixels
z_xb:       .res 1              ; CB index of the cell's line 0
z_fresh:    .res 1              ; cell_get: 1 a fresh pool character
z_sx:       .res 1              ; shift, +4 if mirrored: the column masks
z_fi:       .res 1              ; figs_draw: the figure being drawn

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
knew:       .res 1              ; keys that went down in this poll
fstate:     .res 1              ; fire: 0 up, 1 held alone, 2 held and used
_fire_down: .res 1              ; fire held and down pushed (the test build)
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
scr_want:   .res 1              ; $80 the screen to go off, 1 on, in the blank
                                ; $40 off, the interrupt going on (eng_hide)
_scr_hidden: .res 1             ; eng_hide's: off till eng_show

_f_x:       .res 1              ; multicolour pixel of the left edge, 0..152
_f_y:       .res 1              ; display line of the top line, 0..175
_f_h:       .res 1              ; lines, up to 24
_f_flip:    .res 1              ; 1: mirrored
_f_col:     .res 1              ; colour cell for its %11 pixels, 0: none

_put_code:  .res 1
_put_attr:  .res 1

next_code:  .res 1
cl_n:       .res 2

; behind the game state at $0800 (stardew.cfg)
        .segment "LOWBSS"
cl_lo0:     .res POOL_N         ; cells handed a character, picture 0
cl_hi0:     .res POOL_N
cl_lo1:     .res POOL_N         ; the same, picture 1
cl_hi1:     .res POOL_N
MAXFIG = 10
_fa_x:      .res 1              ; fig_add: the figure to add
_fa_y:      .res 1
_fa_s:      .res 1
_fa_f:      .res 1
_fa_c:      .res 1
_nfig:      .res 1              ; figures in this picture
fg_x:       .res MAXFIG
fg_y:       .res MAXFIG
fg_s:       .res MAXFIG
fg_f:       .res MAXFIG
fg_c:       .res MAXFIG
fg_key:     .res MAXFIG         ; the line below its feet
fg_ord:     .res MAXFIG         ; the figures by fg_key: drawn in this order
_bk_x:      .res 1              ; blocked_at: the figure's top left
_bk_y:      .res 1
        .bss

fpx:        .res 3              ; per column: bit k = pixels in cell row k
f11:        .res 3              ; per column: bit k = %11 pixels in cell row k
dirty:      .res 3              ; per column: CB bytes not clean below line 0
_water_n:   .res 1              ; pairs of water characters (world.c)
_water_ab:  .res 24             ; left, right, the lines that are all water
_water_ph:  .res 2              ; where the ripples are in each character set

; The map as it is without figures: codes and colours, 22 rows of 40. On
; a boundary of $400, so an offset's high byte can be ORed in.
        .segment "MAPIMG"
_base_code: .res $400
_base_attr: .res $400
BASEC = _base_code
BASEA = _base_attr

        .segment "TABLES"
        .align 256
; [sub][b] for sub 1..3 (r_fig does not shift by 0): b shifted right by
; sub pixels, and what falls out of it into the next byte
shr1:       .res 3*256
shl1:       .res 3*256
shr_tab = shr1 - 256
shl_tab = shl1 - 256
nmaskof:    .res 256            ; %00 for every pixel that is not %00, else %11
revmc:      .res 256            ; the four pixels in reverse order

        .segment "HITABLES"
; Three columns of a figure, a byte of pixels and its mask (inverted) for
; every line, 8 lines of nothing above and below: the eight lines of any
; cell it touches can be read without looking where the figure ends.
COL1 = 80
COL2 = 160
CB:         .res 256
code_hi:    .res 256            ; code * 8, high byte
        .segment "TABLES"
dark11:     .res 256            ; the byte with its %11 pixels made %01
code_lo:    .res 256            ; code * 8

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
        ; the figures' columns: nothing, and see-through
        ldx #0
@pad:   lda #0
        sta CB,x
        lda #$FF
        sta CB+1,x
        inx
        inx
        bne @pad
        lda #0
        sta dirty
        sta dirty+1
        sta dirty+2

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

; eng_stack: cc65's stack to $FB00-$FCFF. The start-up code puts it right
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
; own handler, so there must not be one. If the interrupt runs, it switches
; the screen off itself, in the vertical blank: no picture is cut off
; halfway, and the border goes black where nobody sees it being written.
_eng_blank:
        lda TED_IRQEN
        and #$02
        beq @off
        lda #$80
        sta scr_want
:       bit scr_want            ; the interrupt clears it once done
        bmi :-
@off:   sei
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

; eng_unblank: the TED set up for the game, the interrupt running; the
; picture on screen shown from the next vertical blank on, colours first.
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
        lda #0
        sta _scr_hidden
        lda #1
        sta phase
        sta scr_want
        lda #VBL_LINE
        sta TED_RCMP
        lda #$02                ; raster interrupt, compare bit 8 = 0
        sta TED_IRQEN
        lda TED_IRQ
        sta TED_IRQ
        cli
:       lda scr_want            ; till it is on
        bne :-
        rts

; eng_hide: the screen dark from the next vertical blank on, the
; interrupt (music, keys) going on; eng_show: on again.
_eng_hide:
        lda #1
        sta _scr_hidden
        lda #$40
        sta scr_want
:       lda scr_want
        bne :-
        rts

_eng_show:
        lda #0
        sta _scr_hidden
        lda #1
        sta scr_want
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
        lda #VBL_LINE
        sta TED_RCMP
        jmp @out

@bottom:
        ; the vertical blank: nothing drawn, any register may be written
        bit scr_want
        bpl :+
        lda #0                  ; the screen off: black, no more interrupts
        sta TED_BORDER
        lda TED_SCROLLY
        and #$EF
        sta TED_SCROLLY
        lda #0
        sta TED_IRQEN
        sta scr_want
        jmp @out
:       lda _ready
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
        lda scr_want
        beq @on
        cmp #$40
        bne :+
        lda TED_SCROLLY         ; eng_hide: off
        and #$EF
        bne :++
:       lda #$1B                ; text, display on, 25 rows, y scroll 3
:       sta TED_SCROLLY
        lda #0
        sta scr_want
@on:
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

; the top of the picture: map characters and colours, or menu ones. Only
; ever in the vertical blank (see the top of this file).
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
;   f_src  the figure (tools/mkdata.py): f_h lines of 2 bytes, then a byte
;          per line with a bit per pixel that is not %00 (bit 7 the left
;          one), then one with a bit per pixel that is %11
;   f_x    multicolour pixel of the left edge (0..152)
;   f_y    display line of the top line (0..175)
;   f_h    lines, up to 24
;   f_flip 1: mirrored
;   f_col  colour cell for cells where the figure has %11 pixels (0: none)
; Figures are drawn in order; a later one covers an earlier one.
;
; First the figure's two bytes a line are shifted into place, three columns
; of a character each, with a mask beside every byte (CB). Then every cell
; of the screen the figure has pixels in gets a character of the pool: the
; map character under the figure through the mask, and the figure in.
_r_fig:
        lda _f_h
        asl a
        sta z_h2                ; bytes of data: 2 a line
        lda _f_src              ; the pixel bits after the data
        clc
        adc z_h2
        sta p_pf
        lda _f_src+1
        adc #0
        sta p_pf+1
        lda _f_x
        and #3
        sta z_s
        ldx _f_flip
        beq :+
        ora #4
:       sta z_sx
        lda z_s
        jeq @s0

        ; --- shifted by 1-3 pixels: three columns ----------------------------
        clc
        adc #>shr_tab
        sta @r0+2
        sta @r1+2
        sta @r0f+2
        sta @r1f+2
        lda z_s
        adc #>shl_tab
        sta @l0+2
        sta @l1+2
        sta @l0f+2
        sta @l1f+2
        ldy #0
        lda _f_flip
        jne @pf
@p:     lda (_f_src),y          ; the left byte
        tax
@l0:    lda shl_tab,x           ; what spills into column 1
        sta CB+COL1+16,y
@r0:    lda shr_tab,x           ; its own share: column 0
        sta CB+16,y
        tax
        lda nmaskof,x
        sta CB+17,y
        iny
        lda (_f_src),y          ; the right byte (Y odd now)
        sta z_t
        tax
@l1:    lda shl_tab,x           ; what spills into column 2
        sta CB+COL2+15,y
        tax
        lda nmaskof,x
        sta CB+COL2+16,y
        ldx z_t
@r1:    lda shr_tab,x           ; and into column 1
        ora CB+COL1+15,y
        sta CB+COL1+15,y
        tax
        lda nmaskof,x
        sta CB+COL1+16,y
        iny
        cpy z_h2
        bne @p
@p3:    ldx #2                  ; three columns written
        jmp @tail

        ; the same mirrored: the right byte reversed is the left one
@pf:    iny
        lda (_f_src),y
        tax
        lda revmc,x
        tax
@l0f:   lda shl_tab,x
        sta CB+COL1+15,y
@r0f:   lda shr_tab,x
        sta CB+15,y
        tax
        lda nmaskof,x
        sta CB+16,y
        dey
        lda (_f_src),y
        tax
        lda revmc,x
        sta z_t
        tax
@l1f:   lda shl_tab,x
        sta CB+COL2+16,y
        tax
        lda nmaskof,x
        sta CB+COL2+17,y
        ldx z_t
@r1f:   lda shr_tab,x
        ora CB+COL1+16,y
        sta CB+COL1+16,y
        tax
        lda nmaskof,x
        sta CB+COL1+17,y
        iny
        iny
        cpy z_h2
        bne @pf
        beq @p3

        ; --- not shifted: two columns, the bytes as they are ----------------
@s0:    ldy #0
        lda _f_flip
        bne @qf
@q:     lda (_f_src),y
        sta CB+16,y
        tax
        lda nmaskof,x
        sta CB+17,y
        iny
        lda (_f_src),y
        sta CB+COL1+15,y
        tax
        lda nmaskof,x
        sta CB+COL1+16,y
        iny
        cpy z_h2
        bne @q
@q2:    ldx #1
        bne @tail
@qf:    iny                     ; mirrored
        lda (_f_src),y
        tax
        lda revmc,x
        sta CB+15,y
        tax
        lda nmaskof,x
        sta CB+16,y
        dey
        lda (_f_src),y
        tax
        lda revmc,x
        sta CB+COL1+16,y
        tax
        lda nmaskof,x
        sta CB+COL1+17,y
        iny
        iny
        cpy z_h2
        bne @qf
        beq @q2

        ; --- below the figure, 8 lines of nothing in every column written:
        ; a cell is drawn whole, whatever of it the figure leaves out. What
        ; was dirty before further down is cleared, the rest stays clean.
@tail:  stx z_c
@tc:    ldx z_c
        lda dirty,x
        cmp z_h2
        bcc @tn                 ; nothing dirty below this figure
        beq @tn
        tay                     ; from the dirty end back down to the figure
        lda col_base,x
        sta @tz+1
        ora #1
        sta @tf+1
@tl:    dey
        dey
        lda #0
@tz:    sta CB+16,y
        lda #$FF
@tf:    sta CB+17,y
        cpy z_h2
        bne @tl
        ldx z_c
@tn:    lda z_h2
        sta dirty,x
        dec z_c
        bpl @tc

        ; --- which cells: the pixel bits ORed over each cell row, then cut
        ; into the three columns by the shift ---------------------------------
        lda #0
        sta fpx
        sta fpx+1
        sta fpx+2
        sta f11
        sta f11+1
        sta f11+2
        lda #1
        sta z_rbit
        lda _f_y
        and #7
        sta z_ly0
        eor #7                  ; lines in the first cell row: 8 - ly0
        clc
        adc #1
        sta z_t                 ; end of this row (line index)
        ldy #0
@row:   cpy _f_h
        jcs @rowend
        lda z_t
        cmp _f_h
        bcc :+
        lda _f_h
:       sta z_t
        sty z_i
        lda #0                  ; pixels in the row
:       ora (p_pf),y
        iny
        cpy z_t
        bne :-
        sta z_m0
        lda p_pf                ; %11 pixels in the row: h further on
        clc
        adc _f_h
        sta p_a
        lda p_pf+1
        adc #0
        sta p_a+1
        ldy z_i
        lda #0
:       ora (p_a),y
        iny
        cpy z_t
        bne :-
        sta z_m1
        ldx z_sx
        lda z_m0
        and colm0,x
        beq :+
        lda z_rbit
        ora fpx
        sta fpx
:       lda z_m0
        and colm1,x
        beq :+
        lda z_rbit
        ora fpx+1
        sta fpx+1
:       lda z_m0
        and colm2,x
        beq :+
        lda z_rbit
        ora fpx+2
        sta fpx+2
:       lda z_m1
        and colm0,x
        beq :+
        lda z_rbit
        ora f11
        sta f11
:       lda z_m1
        and colm1,x
        beq :+
        lda z_rbit
        ora f11+1
        sta f11+1
:       lda z_m1
        and colm2,x
        beq :+
        lda z_rbit
        ora f11+2
        sta f11+2
:       asl z_rbit
        lda z_t
        clc
        adc #8
        sta z_t
        jmp @row
@rowend:

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
        ; the column's lines for the first cell: from line -ly0 on
        lda z_ly0
        asl a
        eor #$FF
        sec
        adc col_base,x          ; base - 2*ly0
        sta z_xb
        lda z_row0
        sta z_row
@cell:  lsr z_fp
        bcc @skip
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
        bcc @plain
        lda _f_col
        beq @plain
        lda z_fresh
        beq :+
        jsr dark_copy           ; the map character, darkened
        jmp :++
:       jsr dark_here           ; a character that already has a figure
:       ldx z_xb
        jsr blend_here
        lda z_oh                ; the colour cell
        ora z_atthi
        sta p_scr+1
        lda z_ol
        sta p_scr
        ldy #0
        lda _f_col
        sta (p_scr),y
        jmp @skip
@plain: ldx z_xb
        lda z_fresh
        beq :+
        jsr blend_copy
        jmp @skip
:       jsr blend_here
@skip:  lsr z_f11
        lda z_fp
        beq @nextc
        inc z_row
        lda z_xb
        clc
        adc #16
        sta z_xb
        jmp @cell
@nextc: inc z_c
        lda z_c
        cmp #3
        jcc @col
        rts

; The four ways a cell gets the figure; X is the column's line 0 of this
; cell in CB, (p_dst) the character drawn into, (p_src) the map character.

; the map character through the mask, the figure in: a fresh cell
blend_copy:
        .repeat 8, L
        ldy #L
        lda (p_src),y
        and CB+2*L+1,x
        ora CB+2*L,x
        sta (p_dst),y
        .endrepeat
        rts

; the same in a character drawn into already
blend_here:
        .repeat 8, L
        ldy #L
        lda (p_dst),y
        and CB+2*L+1,x
        ora CB+2*L,x
        sta (p_dst),y
        .endrepeat
        rts

; the map character with its %11 made dark (%01)
dark_copy:
        .repeat 8, L
        ldy #L
        lda (p_src),y
        tax
        lda dark11,x
        sta (p_dst),y
        .endrepeat
        rts

dark_here:
        .repeat 8, L
        ldy #L
        lda (p_dst),y
        tax
        lda dark11,x
        sta (p_dst),y
        .endrepeat
        rts

; the pixel bits of the columns: pixel p lands on p + shift; column 0 is
; positions 0-3, column 1 4-7, column 2 8-11 (bit 7 = pixel 0). Mirrored,
; pixel p lands on 7 - p + shift: the same bits reversed.
colm0:      .byte $F0, $E0, $C0, $80,  $0F, $07, $03, $01
colm1:      .byte $0F, $1E, $3C, $78,  $F0, $78, $3C, $1E
colm2:      .byte $00, $01, $03, $07,  $00, $80, $C0, $E0
col_base:   .byte 16, COL1+16, COL2+16

; ===========================================================================
; The figures of a picture: collected, sorted by where their feet are,
; drawn - those further down cover those further up
; ===========================================================================

; fig_add: the figure in fa_x, fa_y, fa_s (sprite), fa_f (1 mirrored, +$80
; drawn first of all: the cursor - a cell has one colour of its own, and a
; figure sharing one with the cursor keeps its), fa_c (colour) into the
; list, behind every one whose feet are as high or higher
_fig_add:
        ldx _nfig
        cpx #MAXFIG
        bcs @r
        lda _fa_x
        sta fg_x,x
        lda _fa_y
        sta fg_y,x
        lda _fa_f
        and #1
        sta fg_f,x
        lda _fa_c
        sta fg_c,x
        ldy _fa_s
        tya
        sta fg_s,x
        lda #0
        bit _fa_f
        bmi :+
        lda _fa_y
        clc
        adc _spr_h,y
:       sta fg_key,x
        sta z_t
        ldy _nfig
@i:     dey
        bmi @put
        ldx fg_ord,y
        lda fg_key,x
        cmp z_t
        bcc @put
        beq @put
        txa                     ; further down: one on
        sta fg_ord+1,y
        jmp @i
@put:   iny
        lda _nfig
        sta fg_ord,y
        inc _nfig
@r:     rts

; figs_draw: the picture - the map back where figures were, the figures
_figs_draw:
        jsr water
        jsr _r_begin
        lda #0
        sta z_fi
@l:     ldy z_fi
        cpy _nfig
        bcs @done
        ldx fg_ord,y
        lda fg_x,x
        sta _f_x
        lda fg_y,x
        sta _f_y
        lda fg_f,x
        sta _f_flip
        lda fg_c,x
        sta _f_col
        ldy fg_s,x
        lda _spr_h,y
        sta _f_h
        tya
        asl a
        tay
        lda _spr_tab,y
        sta _f_src
        lda _spr_tab+1,y
        sta _f_src+1
        jsr _r_fig
        inc z_fi
        jmp @l
@done:  jmp _r_done

; water: the ripples on, one pixel every 8 frames. Only in the character
; set of the picture being drawn - the one on screen is not touched, so
; no picture shows half the water moved - and that one catches up when
; it is next drawn into.
water:
        lda _water_n
        beq @r
        lda _frames
        lsr a
        lsr a
        lsr a
        and #7
        sta z_s
        ldx _back
@step:  lda _water_ph,x
        cmp z_s
        beq @r
        clc
        adc #1
        and #7
        sta _water_ph,x
        lda font_hi,x
        sta z_fonthi
        lda _water_n
        sta z_lr
        ldy #0                  ; every pair a pixel to the right, around
@pair:  sty z_i
        lda _water_ab+2,y       ; which lines: bit 7 line 7 .. bit 0 line 0
        sta z_t
        ldx _water_ab,y
        lda code_lo,x
        sta p_a
        lda code_hi,x
        ora z_fonthi
        sta p_a+1
        ldx _water_ab+1,y
        lda code_lo,x
        sta p_b
        lda code_hi,x
        ora z_fonthi
        sta p_b+1
        ldy #7
@line:  asl z_t
        bcc @skip               ; (grass in it: the shore's top)
        lda (p_a),y
        sta z_m0
        lda (p_b),y
        sta z_m1
        lsr a                   ; the right byte's last bit round to the left
        ror z_m0
        ror z_m1
        lsr a
        ror z_m0
        ror z_m1
        lda z_m0
        sta (p_a),y
        lda z_m1
        sta (p_b),y
@skip:  dey
        bpl @line
        ldy z_i
        iny
        iny
        iny
        dec z_lr
        bne @pair
        ldx _back
        jmp @step
@r:     rts

; blocked_at: 1 if a figure at bk_x, bk_y (top left, pixels and lines)
; would stand on something solid. Its feet are a box 6 pixels wide and
; 4 lines high at the bottom of its 16 lines; off the room is solid too.
RW = 20
RH = 11
_blocked_at:
        lda _bk_x
        clc
        adc #1
        lsr a
        lsr a
        lsr a
        sta z_m0                ; left column
        lda _bk_x
        clc
        adc #6
        lsr a
        lsr a
        lsr a
        cmp #RW
        bcs @yes
        sta z_m1                ; right column
        lda _bk_y
        clc
        adc #15
        lsr a
        lsr a
        lsr a
        lsr a
        cmp #RH
        bcs @yes
        sta z_m2                ; bottom row
        lda _bk_y
        clc
        adc #12
        lsr a
        lsr a
        lsr a
        lsr a                   ; top row
        jsr @row
        bne @yes
        lda z_m2
        cmp z_t
        beq @no
        jsr @row
        bne @yes
@no:    lda #0
        tax
        rts
@yes:   lda #1
        ldx #0
        rts
@row:   sta z_t                 ; row * 20: both corners' flags, solid?
        asl a
        asl a
        sta z_i
        asl a
        asl a
        clc
        adc z_i
        sta z_i
        adc z_m0
        tay
        ldx _room,y
        lda _mt_flag,x
        sta z_lr
        lda z_i
        clc
        adc z_m1
        tay
        ldx _room,y
        lda _mt_flag,x
        ora z_lr
        and #1
        rts

; cell_get: the character of cell (z_row, z_col) in the back buffer, for
; drawing into; p_dst points at its 8 bytes, z_ol/z_oh is the cell's
; offset. A cell still showing its map character is handed a character of
; the pool (z_fresh = 1, p_src = the map character, to be drawn through
; the mask); else z_fresh = 0. Carry set if the pool is empty.
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
        lda #1
        sta z_fresh
        clc
        rts
@have:  tax
        lda code_lo,x
        sta p_dst
        lda code_hi,x
        ora z_fonthi
        sta p_dst+1
        lda #0
        sta z_fresh
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
        and #$EF                ; fire: see below
        sta knew
        ; Everything is to be done with a joystick of one button. Fire on
        ; its own counts when it is let go. Held, a direction makes it
        ; something else: left and right the previous and next item, up the
        ; backpack or out of a menu - and then it does not count as fire,
        ; nor the direction as one.
        lda _keys_irq
        and #16
        beq @fup
        lda fstate
        bne :+
        lda #1                  ; fire pressed: on its own so far
        sta fstate
:       lda knew
        and #$0F
        beq @add
        tax
        lda combo,x
        ora keys_hit
        sta keys_hit
        cpx #2                  ; down on its own: noted apart
        bne :+
        stx _fire_down
:       lda #2
        sta fstate
        lda knew
        and #$F0
        sta knew
        jmp @add
@fup:   lda fstate              ; fire let go: was it on its own?
        cmp #1
        bne :+
        lda #16
        ora keys_hit
        sta keys_hit
:       lda #0
        sta fstate
@add:   lda knew
        ora keys_hit
        sta keys_hit
        rts

; fire held and a direction pressed (up 1, down 2, left 4, right 8): left
; is previous, right next, up the menu key
combo:  .byte 0, 128, 0, 128, 32, 32, 32, 32, 64, 64, 64, 64, 32, 32, 32, 32

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
