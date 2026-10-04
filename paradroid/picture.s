; picture.s - the droids' pictures and the panel's letters in the window
;
; For the transfer's introduction, the console's droid enquiry, the
; title's start page and a game's end (xfer.s draws them: x_letter,
; x_picture). In assembly (it was picture.c) to make room.

        .export _unit_name, _say, _picture, _pic_pages, _pic_late, _pic_until

        .import _panel_code, _x_letter, _x_picture, _xmap, _load_file
        .import _win_clear, _eng_roll, _roll, _frames, _font_hi, _col_fig2
        .import _x_attr, _x_row, _x_col, _x_code, _pal_deck, _pal_mc, _dr_class
        .import pusha, pushax, popa
        .importzp ptr1, ptr2

FONT1   = $D800

        .data
name:   .byte "p00", 0          ; the picture's file

        .bss
_pic_pages: .res 2              ; the console's pages about the droid
_pic_late:  .res 1              ; the window cleared once loaded, not
_pic_until: .res 1              ; before this picture, and the static
                                ; stopped
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

; picture(t, row, col): droid type t's picture from the disk at row, col
; of a cleared window, picture 1's set shown for both pictures; letters
; can follow. The file (tools/mkdata.py) ends with where its header is;
; after the header come the console's pages about the droid.
_picture:
        sta pcol
        jsr popa
        sta prow
        jsr popa
        sta pt
        lda _pic_late
        bne :+
        jsr clear
:       lda pt                  ; its name: "p" and two digits
        ldx #$30
:       cmp #10
        bcc :+
        sbc #10
        inx
        bne :-
:       stx name+1
        ora #$30
        sta name+2
        lda #<name
        ldx #>name
        jsr pushax
        lda #<(FONT1 + 8)
        ldx #>(FONT1 + 8)
        jsr _load_file          ; its length: the end
        clc
        adc #<(FONT1 + 8)
        sta ee
        txa
        adc #>(FONT1 + 8)
        sta ee+1
        lda _pic_late
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
@head:  lda ee                  ; e: where its header is, from its end
        sta ptr1
        lda ee+1
        sta ptr1+1
        ldy #<-2
        dec ptr1+1
        lda (ptr1),y
        tax
        iny
        lda (ptr1),y
        clc
        adc #>(FONT1 + 8)
        sta ptr1+1
        txa
        clc
        adc #<(FONT1 + 8)
        sta ptr1
        bcc :+
        inc ptr1+1
:       lda ptr1                ; the pages after the header's 4 bytes
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

; the window cleared, white
clear:  lda #0
        jsr pusha
        lda #$71
        jmp _win_clear
