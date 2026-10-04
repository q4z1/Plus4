; picture.s - the droids' pictures and the panel's letters in the window
;
; For the transfer's introduction, the console's droid enquiry, the
; title's start page and a game's end (xfer.s draws them: x_letter,
; x_picture). The pictures are kept packed in the program
; (tools/mkdata.py).

        .export _unit_name, _say, _picture, _pic_pages, _pic_late, _pic_until
        .export _pic_text

        .import _panel_code, _x_letter, _x_picture, _xmap, _unpack, _unp_dst
        .import _pic_gfx, _pic_txt, _pic_go, _pic_gl, _pic_to, _pic_tl, _pre
        .import _win_clear, _eng_roll, _roll, _frames, _font_hi, _col_fig2
        .import _x_attr, _x_row, _x_col, _x_code, _pal_deck, _pal_mc, _dr_class
        .import pusha, popa
        .importzp ptr1, ptr2

        .include "game.inc"
        .include "data.inc"

; the streams unpacked into the end of the pictures' slots (23 of 512)
PICBUF_G = _pre + 23 * 512 - PIC_GFX_RAW
PICBUF_T = _pre + 23 * 512 - PIC_TXT_RAW

        .bss
_pic_pages: .res 2              ; the console's pages about the droid
_pic_late:  .res 1              ; the window cleared once loaded, not
_pic_until: .res 1              ; before this picture, and the static
                                ; stopped
_pic_text:  .res 1              ; the next picture with its pages
word:   .res 20
pt:     .res 1                  ; picture()'s type, row and column
prow:   .res 1
pcol:   .res 1
sx:     .res 1
sp_:    .res 2                  ; say()'s text
ee:     .res 2                  ; the picture's end

        .rodata
noun_lo:    .byte <n_device, <n_robot, <n_droid, <n_cyborg
noun_hi:    .byte >n_device, >n_robot, >n_droid, >n_cyborg
n_device:   .byte " device", 0
n_robot:    .byte " robot", 0
n_droid:    .byte " droid", 0
n_cyborg:   .byte " cyborg", 0
class_lo:   .byte <c0, <c1, <c2, <c3, <c4, <c5, <c6, <c7, <c8, <c9
class_hi:   .byte >c0, >c1, >c2, >c3, >c4, >c5, >c6, >c7, >c8, >c9
c0: .byte "influence", 0
c1: .byte "disposal", 0
c2: .byte "servant", 0
c3: .byte "messenger", 0
c4: .byte "maintenance", 0
c5: .byte "crew", 0
c6: .byte "sentinel", 0
c7: .byte "battle", 0
c8: .byte "security", 0
c9: .byte "command", 0

        .code

; unit_name(t): "Maintenance robot": the class, a capital first, and what
; it is
_unit_name:
        tax
        lda _dr_class,x
        sta sx
        tay
        lda class_lo,y
        sta ptr1
        lda class_hi,y
        sta ptr1+1
        ldx #0
        jsr append
        lda word                ; a capital (PETSCII)
        eor #$80
        sta word
        lda sx                  ; (class + 3) / 4: device, robot, droid,
        clc                     ; cyborg
        adc #3
        lsr a
        lsr a
        tay
        lda noun_lo,y
        sta ptr1
        lda noun_hi,y
        sta ptr1+1
        jsr append
        lda #<word
        ldx #>word
        rts
; the text at ptr1 onto word from X on; X at its end
append: ldy #0
:       lda (ptr1),y
        sta word,x
        beq :+
        inx
        iny
        bne :-
:       rts

; say(s): text from x_row, x_col on, in the panel's letters
_say:   sta sp_
        stx sp_+1
@c:     ldy #0
        lda sp_
        sta ptr2
        lda sp_+1
        sta ptr2+1
        lda (ptr2),y
        beq @done
        inc sp_
        bne :+
        inc sp_+1
:       jsr _panel_code
        sta sx
        jsr _x_letter
        lda sx
        cmp #$3A                ; two wide
        bcc @c
        adc #$20 - 1            ; (carry set)
        jsr _x_letter
        jmp @c
@done:  rts

; picture(t, row, col): droid type t's picture at row, col of a cleared
; window, picture 1's set shown for both pictures; letters can follow.
; Its graphics unpacked (all the pictures' at once, into the end of the
; pictures' slots, which the overlays leave free) and its own copied to
; character 1 of picture 1's set; with pic_text set (the console), its
; pages after them, the same way.
_picture:
        sta pcol
        jsr popa
        sta prow
        jsr popa
        sta pt
        lda _pic_late
        bne :+
        jsr clear
:       lda #<_pic_gfx          ; the graphics
        ldx #>_pic_gfx
        ldy #<PICBUF_G
        sty _unp_dst
        ldy #>PICBUF_G
        sty _unp_dst+1
        jsr _unpack
        lda #<(PICBUF_G)
        ldx #>(PICBUF_G)
        ldy #0                  ; (pic_go, pic_gl)
        jsr part
        lda _pic_text
        beq :+
        lda #<_pic_txt          ; the pages
        ldx #>_pic_txt
        ldy #<PICBUF_T
        sty _unp_dst
        ldy #>PICBUF_T
        sty _unp_dst+1
        jsr _unpack
        lda #<(PICBUF_T)
        ldx #>(PICBUF_T)
        ldy #2                  ; (pic_to, pic_tl)
        jsr part
        lda #0
        sta _pic_text
:       lda _pic_late
        beq @head
:       lda _frames             ; the static stopped, not before pic_until
        sec
        sbc _pic_until
        bmi :-
        lda #0
        sta _roll
        jsr _eng_roll
        jsr clear
        lda #0
        sta _pic_late
@head:  ldx pt                  ; e: its header, the graphics' last 4
        txa
        asl a
        tax
        lda _pic_gl,x
        clc
        adc #<(FONT1 + 8 - 4)
        sta ptr1
        lda _pic_gl+1,x
        adc #>(FONT1 + 8 - 4)
        sta ptr1+1
        lda ptr1                ; the pages after the header's 4 bytes
        clc
        adc #4
        sta _pic_pages
        lda ptr1+1
        adc #0
        sta _pic_pages+1
        lda #$D8
        sta _font_hi
        ldy #3
        lda (ptr1),y
        tax
        lda _pal_deck,x
        sta _col_fig2
        dey
        lda (ptr1),y
        tax
        lda _pal_mc,x
        sta _x_attr
        lda prow
        sta _x_row
        lda pcol
        sta _x_col
        dey
        lda (ptr1),y            ; rows: x_code, and the layout before e
        sta _x_code
        asl a                   ; rows * 6
        sta sx
        asl a
        adc sx
        sta sx
        lda ptr1
        sec
        sbc sx
        pha
        lda ptr1+1
        sbc #0
        tax
        pla
        jsr _x_picture
        lda #0
        ldx #127
:       sta _xmap,x
        dex
        bpl :-
        lda #140
        sta _x_code
        rts

; picture pt's part of the stream unpacked at A/X (Y 0: the graphics,
; 2: the pages) to character 1 of picture 1's set (the pages after the
; graphics)
part:   sta ptr1
        stx ptr1+1
        lda pt
        asl a
        tax
        lda #<(FONT1 + 8)       ; to: character 1, or after the graphics
        sta ptr2
        lda #>(FONT1 + 8)
        sta ptr2+1
        cpy #0
        beq @gfx
        lda ptr2
        clc
        adc _pic_gl,x
        sta ptr2
        lda ptr2+1
        adc _pic_gl+1,x
        sta ptr2+1
        lda _pic_to,x           ; from
        clc
        adc ptr1
        sta ptr1
        lda _pic_to+1,x
        adc ptr1+1
        sta ptr1+1
        lda _pic_tl,x           ; so many
        sta ee
        lda _pic_tl+1,x
        sta ee+1
        jmp @copy
@gfx:   lda _pic_go,x
        clc
        adc ptr1
        sta ptr1
        lda _pic_go+1,x
        adc ptr1+1
        sta ptr1+1
        lda _pic_gl,x
        sta ee
        lda _pic_gl+1,x
        sta ee+1
@copy:  ldy #0
@b:     lda ee
        ora ee+1
        beq @done
        lda (ptr1),y
        sta (ptr2),y
        inc ptr1
        bne :+
        inc ptr1+1
:       inc ptr2
        bne :+
        inc ptr2+1
:       lda ee
        bne :+
        dec ee+1
:       dec ee
        jmp @b
@done:  rts

; the window cleared, white
clear:  lda #0
        jsr pusha
        lda #$71
        jmp _win_clear
