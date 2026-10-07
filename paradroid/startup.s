; startup.s - the start, once: everything into its place
;
; The sound effects' player to $FC00 (sfx.s) and both voices quiet, the
; code that runs at $F100 (the figures, the window and the panel: figs.s,
; draw.s), tables into free ends of memory (mkdata.py's XT1-XT5), the engine (eng_init()), the unpacker to $0200 (once the
; KERNAL's interrupt, whose vector is at $0314, is off), the character
; sets and block tables, the colours, and the status panel.
;
; In INITDATA: used once, then overwritten by the pictures' slots.

        .export _start_up, _god_init

        .import _eng_init, _mc_font, _panel_put, _pp_off, _pp_code, _pp_attr
        .import _col_panel, _col_border, _col_deck, _col_fig1, _col_fig2, _bw
        .import _tile_font, _panel_font, _blk_code, _panel_codes, _panel_cols
        .import __SFXCODE_LOAD__, __SFXCODE_RUN__, __SFXCODE_SIZE__
        .import __HICODE_LOAD__, __HICODE_RUN__, __HICODE_SIZE__
        .import __UNPACK_LOAD__, __UNPACK_RUN__, __UNPACK_SIZE__
        .import __PAGE1_LOAD__, __PAGE1_RUN__, __PAGE1_SIZE__
        .import __LOWEND_LOAD__, __LOWEND_RUN__, __LOWEND_SIZE__
        .import __XT1_LOAD__, __XT1_RUN__, __XT1_SIZE__
        .import __XT2_LOAD__, __XT2_RUN__, __XT2_SIZE__
        .import __XT3_LOAD__, __XT3_RUN__, __XT3_SIZE__
        .import __XT4_LOAD__, __XT4_RUN__, __XT4_SIZE__
        .import __XT5_LOAD__, __XT5_RUN__, __XT5_SIZE__
        .import __XT6_LOAD__, __XT6_RUN__, __XT6_SIZE__
        .import __XT7_LOAD__, __XT7_RUN__, __XT7_SIZE__
        .import __XT8_LOAD__, __XT8_RUN__, __XT8_SIZE__
        .import __XT9_LOAD__, __XT9_RUN__, __XT9_SIZE__
        .import __XT10_LOAD__, __XT10_RUN__, __XT10_SIZE__
        .import __XT11_LOAD__, __XT11_RUN__, __XT11_SIZE__
        .import _dbg_god
        .importzp _snd_len, ptr1, ptr2

        .include "game.inc"
        .include "data.inc"

        .segment "INITDATA"

; copy: A/X bytes from ptr1 to ptr2
copy:   sta cnt
        stx cnt+1
        ldy #0
@b:     lda cnt
        ora cnt+1
        beq @done
        lda (ptr1),y
        sta (ptr2),y
        inc ptr1
        bne :+
        inc ptr1+1
:       inc ptr2
        bne :+
        inc ptr2+1
:       lda cnt
        bne :+
        dec cnt+1
:       dec cnt
        jmp @b
@done:  rts

.macro  move from, to, size
        lda #<(from)
        sta ptr1
        lda #>(from)
        sta ptr1+1
        lda #<(to)
        sta ptr2
        lda #>(to)
        sta ptr2+1
        lda #<(size)
        ldx #>(size)
        jsr copy
.endmacro

_start_up:
        move __SFXCODE_LOAD__, __SFXCODE_RUN__, __SFXCODE_SIZE__
        move __HICODE_LOAD__, __HICODE_RUN__, __HICODE_SIZE__
        move __XT1_LOAD__, __XT1_RUN__, __XT1_SIZE__
        move __XT2_LOAD__, __XT2_RUN__, __XT2_SIZE__
        move __XT3_LOAD__, __XT3_RUN__, __XT3_SIZE__
        move __XT4_LOAD__, __XT4_RUN__, __XT4_SIZE__
        move __XT5_LOAD__, __XT5_RUN__, __XT5_SIZE__
        move _blk_code, BLKC, 1024
        move __XT6_LOAD__, __XT6_RUN__, __XT6_SIZE__    ; (into its free ends; all before
                                ; eng_init(), which writes where their
                                ; load images are)
        move __XT7_LOAD__, __XT7_RUN__, __XT7_SIZE__
        move __XT8_LOAD__, __XT8_RUN__, __XT8_SIZE__
        move __XT9_LOAD__, __XT9_RUN__, __XT9_SIZE__
        move __XT10_LOAD__, __XT10_RUN__, __XT10_SIZE__
        move __XT11_LOAD__, __XT11_RUN__, __XT11_SIZE__
        lda #0
        sta _snd_len
        sta _snd_len+1
_god_init = * + 1               ; 1 in paradroid-god.prg (build.sh): the
        lda #0                  ; player takes no damage, to play it
        sta _dbg_god            ; through
        jsr _eng_init
        move __UNPACK_LOAD__, __UNPACK_RUN__, __UNPACK_SIZE__
        move __PAGE1_LOAD__, __PAGE1_RUN__, __PAGE1_SIZE__
        move __LOWEND_LOAD__, __LOWEND_RUN__, __LOWEND_SIZE__
        move _tile_font, FONT0, POOL * 8
        move _tile_font, FONT1, POOL * 8
        jsr _mc_font
        move _panel_font, PANELF, 2048
        lda #$71
        sta _col_panel
        lda #0                  ; black till the title's first screen
        sta _col_border         ; (the picture is off, paradroid.s)
        lda #$5D
        sta _col_deck
        lda #0
        sta _col_fig1
        lda #$80                ; (the first title's logo in scheme 0, as
        sta _bw                 ; the original's at its start: title.s)
        lda #$71
        sta _col_fig2
        ; the status panel, the original's, and the gap's rows under it
        ; blank
        lda #0
        sta _pp_off
        sta _pp_off+1
@p:     ldx _pp_off
        lda _panel_codes,x
        sta _pp_code
        lda #$3B                ; red, purple where it is 4
        ldy _panel_cols,x
        cpy #4
        bne :+
        lda #$4E
:       sta _pp_attr
        jsr _panel_put
        inc _pp_off
        lda _pp_off
        cmp #240
        bne @p
@g:     lda #0
        sta _pp_code
        lda _col_deck
        sta _pp_attr
        jsr _panel_put
        inc _pp_off
        bne :+
        inc _pp_off+1
:       lda _pp_off+1
        beq @g
        lda _pp_off
        cmp #<360
        bne @g
        rts

cnt:    .res 2
