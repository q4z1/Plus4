; signs.s - the tall characters: the station signs and the flap digits
;
; A station's name close up is a sign, as at a real station: dark letters
; on a light plate, its ends rounded. The clock and the score at the top
; are the digits of a split-flap board, the speed a stopwatch, a star
; before the score. All are 16 pixels high, two characters each, one
; above the other (tools/mkfont.py draws them, in halves; a half used
; twice is one character).
;
; Their characters are given out as a level needs them, each time the
; map's characters are made (pool_set, map.s): first the codes the text
; never uses (sp_codes), then from the top of the trains' pool down - the
; pool ends where they start (_pool_end). The digits, the stopwatch and
; the star always; the signs
; only the letters the level's names have, and only if the trains keep
; enough of the pool (sg_room); if not, the names stay as they were, in
; the ROM's letters.

        .macpack longbranch
        .include "game.inc"

        .export glyphs_make, _sg_top, _sg_bot, _sg_col, _bg_top, _bg_bot
        .export _pool_end, sign_of, big_of, watch_set
        .export _xs_top, _xs_bot, _wt_top, _wt_bot
        .import sg_halves, sg_ti, sg_bi, bg_ti, bg_bi
        .importzp SG_HALVES             ; (a number below 128)
        .import wt_ti, wt_bi, xs_ti, xs_bi
        .import _nstation, _st_name, _lv_name, _zoom, _pool_first

BG_N    = 13                    ; the digits, the colon, the minus, the space

        .segment "GAMEZP": zeropage
gs:     .res 2                  ; a half, being copied
gd:     .res 2                  ; its character

        .bss
_sg_top:    .res 32             ; a sign's characters, by its number
_sg_bot:    .res 32             ; (sign_of)
_sg_col:    .res 1              ; and their colour
_bg_top:    .res BG_N           ; a digit's (big_of)
_bg_bot:    .res BG_N
_pool_end:  .res 1              ; the trains' pool: _pool_first to this
_xs_top:    .res 2              ; the star's characters, left and right
_xs_bot:    .res 2
_wt_top:    .res 2              ; the stopwatch's
_wt_bot:    .res 2
_watch_v:   .res 1              ; the speed its dial shows
        .segment "BANDS"        ; (trainschedule.cfg; cleared by glyphs_make)
hcode:      .res 128            ; each half's character: 0 none yet,
                                ; $FF wanted
        .bss
sg_used:    .res 32             ; the signs the level shows
gm_i:       .res 1
gm_n:       .res 1              ; halves wanted
gm_sp:      .res 1              ; the next of sp_codes
gm_lim:     .res 1              ; the pool's end may come down to this
gm_w:       .res 1

        .rodata
; the codes of the ROM's characters no text uses: ← ! " # $ & ' ( ) ; < = ?
; (@ , [ £ ] ↑ are the board's frame, game.inc FR_*)
sp_codes:   .byte 31, 33, 34, 35, 36, 38, 39, 40, 41, 59, 60, 61, 63
SP_N = * - sp_codes

        .code

; sign_of: the sign for screen code A (a letter, else the plate alone), in A
sign_of:
        cmp #27
        bcc :+
        lda #0
:       rts

; big_of: the digit for character A ('0'-'9', ':', '-', else the space), in A
big_of: cmp #':'
        bne :+
        lda #10
        rts
:       cmp #'-'
        bne :+
        lda #11
        rts
:       sec
        sbc #'0'
        cmp #10
        bcc :+
        lda #12
:       rts

; glyphs_make: the digits' characters and, if there is room, the signs';
; after pool_set (map.s), _pool_first set
glyphs_make:
        ldx #SG_HALVES - 1
        lda #0
:       sta hcode,x
        dex
        bne :-
        sta gm_sp
        lda #32                 ; half 0, the empty one: a space
        sta hcode
        lda #C_POOL_END
        sta _pool_end
        ; how far the pool may shrink: the trains need some 25 characters
        ; in the overview, some 60 close up (Alessandria's worst, measured)
        lda _pool_first
        clc
        adc #32
        ldx _zoom
        cpx #1
        beq :+
        adc #32
:       sta gm_lim
        ; the digits
        ldx #BG_N - 1
:       lda bg_ti,x
        jsr want
        lda bg_bi,x
        jsr want
        dex
        bpl :-
        jsr give
        ldx #BG_N - 1
:       ldy bg_ti,x
        lda hcode,y
        sta _bg_top,x
        ldy bg_bi,x
        lda hcode,y
        sta _bg_bot,x
        dex
        bpl :-
        ; the star, and the stopwatch: its top halves the same at every
        ; speed, its lower ones two characters of their own (watch_set)
        lda xs_ti
        jsr want
        lda xs_ti+1
        jsr want
        lda xs_bi
        jsr want
        lda xs_bi+1
        jsr want
        lda wt_ti
        jsr want
        lda wt_ti+1
        jsr want
        jsr give
        ldx #1
:       ldy xs_ti,x
        lda hcode,y
        sta _xs_top,x
        ldy xs_bi,x
        lda hcode,y
        sta _xs_bot,x
        ldy wt_ti,x
        lda hcode,y
        sta _wt_top,x
        dex
        bpl :-
        jsr take
        sta _wt_bot
        jsr take
        sta _wt_bot+1
        lda _watch_v
        jsr watch_set
        ; the signs the names have
        ldx #31
        lda #0
:       sta sg_used,x
        dex
        bpl :-
        lda #1
        sta sg_used + SG_LCAP
        sta sg_used + SG_RCAP
        lda #<_lv_name
        ldx #>_lv_name
        jsr used_in
        lda _zoom               ; the stations' only close up: in the
        cmp #1                  ; overview their names are in the ROM's
        beq @want               ; letters
        lda #0
        sta gm_i
@st:    lda gm_i
        cmp _nstation
        beq @want
        asl a
        asl a
        asl a
        asl a
        clc
        adc #<_st_name
        tay
        lda #>_st_name
        adc #0
        tax
        tya
        jsr used_in
        inc gm_i
        bne @st
@want:  lda #0
        sta gm_n
        ldx #31
@w:     lda sg_used,x
        beq :+
        lda sg_ti,x
        jsr want
        lda sg_bi,x
        jsr want
:       dex
        bpl @w
        ; room for them? sp_codes left, and the pool down to gm_lim
        lda _pool_end
        sec
        sbc gm_lim
        bcs :+
        lda #0
:       clc
        adc #SP_N
        sec
        sbc gm_sp
        cmp gm_n
        bcc @none
        jsr give
        ldx #31
:       ldy sg_ti,x
        lda hcode,y
        sta _sg_top,x
        ldy sg_bi,x
        lda hcode,y
        sta _sg_bot,x
        dex
        bpl :-
        lda #COL_PLATE
        sta _sg_col
        rts
@none:  ldx #31                 ; no signs: the names in the ROM's letters,
@fb:    lda #32                 ; in the lower half, as they were
        sta _sg_top,x
        cpx #27
        bcs @sp
        txa
        bne :+
@sp:    lda #32
:       sta _sg_bot,x
        dex
        bpl @fb
        lda #COL_LABEL
        sta _sg_col
        rts

; used_in: the signs of the name at A/X (screen codes, 0 at its end) used
used_in:
        sta gs
        stx gs+1
        ldy #0
:       lda (gs),y
        beq :+
        jsr sign_of
        tax
        lda #1
        sta sg_used,x
        iny
        cpy #16
        bne :-
:       rts

; want: half A wanted, if it has no character yet (X kept)
want:   tay
        beq @rts                ; the empty half: a space
        lda hcode,y
        bne @rts
        lda #$FF
        sta hcode,y
        inc gm_n
@rts:   rts

; give: a character to each half wanted, its pixels into the font
give:   ldy #SG_HALVES - 1
@h:     lda hcode,y
        cmp #$FF
        bne @next
        jsr take
        sta hcode,y
        jsr put
@next:  dey
        bne @h                  ; (not half 0)
        lda #0
        sta gm_n
        rts

; take: a character for a half, in A - a code no text uses, else the
; pool's top (X changed)
take:   ldx gm_sp
        cpx #SP_N
        bcs :+
        lda sp_codes,x
        inc gm_sp
        rts
:       dec _pool_end
        lda _pool_end
        rts

; put: half Y's pixels into character A of the font (Y kept)
put:    ldx #0
        stx gd+1
        asl a
        rol gd+1
        asl a
        rol gd+1
        asl a
        rol gd+1
        sta gd
        lda gd+1
        ora #>FONT
        sta gd+1
        tya
        ldx #0
        stx gs+1
        asl a
        rol gs+1
        asl a
        rol gs+1
        asl a
        rol gs+1
        adc #<sg_halves
        sta gs
        lda gs+1
        adc #>sg_halves
        sta gs+1
        sty gm_i
        ldy #7
:       lda (gs),y
        sta (gd),y
        dey
        bpl :-
        ldy gm_i
        rts

; watch_set: the stopwatch's dial at speed A (0 the pause, 1 x1, 2 x3,
; 3 x10): its lower halves into their two characters
watch_set:
        sta _watch_v
        asl a
        tax
        ldy wt_bi,x
        lda _wt_bot
        stx gm_w
        jsr put
        ldx gm_w
        ldy wt_bi+1,x
        lda _wt_bot+1
        jmp put
