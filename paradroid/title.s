; title.s - waiting for a game, as the original does it
;
; An overlay: this code, the briefing's text and the logo (build/gen/
; brief.s) are linked to run in the slots of the pre-shifted pictures,
; all of them, as the title needs none (paradroid.cfg), kept packed in
; the program and unpacked for each title (paradroid.s). Its variables are
; in the overlay too: they start from their first values each title.
;
; The original's title has its own sound throughout, a falling sweep and
; a wavering low tone (music.s).
;
; The original's title goes round: first its logo over the whole screen;
; then the four pages of the briefing, in a colour of their own each round
; (yellow, pink, light green); then on white the day's top and worst
; scores, the keys and the credits, with a droid's picture beside them.
;
; The briefing's text comes with the characters it needs, as codes of the
; panel's set (brief_srcs), and its letters: letter k is character
; brief_top[k] over brief_bot[k]. A page is rolled up through the window
; a line of pixels at a time, the way the deck scrolls: picture 1's
; character set holds the briefing's, and both pictures show it.

        .export _title_run, _title_scores, _ship_pages

        .import _wait_tick, _keys_irq, _eng_keys, _frames, _ready, _back
        .import _eng_plain, _win_clear, _r_done, _panel_status, _panel_frame
        .import _picture, _say, _unit_name, _num_text, _num_len
        .import _mus_start, _mus_stop, _brief_rows
        .import _br_d, _br_rr, _br_rows, _br_k, _br_code, _br_cutend
        .import _col_deck, _col_panel, _col_border, _col_fig2, _font_hi
        .import _gap_eor
        .import _panel_hi, _win_mc, _e_sx, _e_cutrow, _e_s
        .import _pause_keys, _bw, s_colour, s_bw, _deck_bg
        .import _x_attr, _x_row, _x_col, _pal_deck, _pal_mc
        .import _top_score, _low_score, _initials, _score, _x_code, _xmap
        .import _brief_srcs, _brief_pages, _brief_dig, _brief_misc, _brief_cap
        .import _logo_font, _logo_col, _logo_rle, _title_pic
        .import _d_type, _level, _dr_class, _dr_num, _ship_name, _count_on
        .import _panel_score, _score_changed, points, _sound
        .import pusha
        .importzp _br_p, sreg, ptr1, ptr2

        .include "game.inc"
        .include "data.inc"

SCORE_CELLS = 17                ; a score's line: the original's room for
                                ; the number and initials
PIC_ROW     = 2                 ; the scores page's picture: its first row
TED_SCROLLY = $FF06
TED_BORDER  = $FF19

        .segment "OVLDATA"
; (in the overlay: these start from these values each title)
shown:      .byte $FF, $FF      ; each picture's row as last made
rows:       .byte 17
tt:         .byte 0             ; brief()'s picture to be ready by
bpage:      .word 0             ; the page shown
b_h:        .byte 0             ; its rows
b_fg:       .byte 0             ; its letters' colour
free_code:  .byte 0             ; picture 1's first character not in use
pic:        .word 0             ; the scores page's picture (the
pic_lay:    .word 0             ; original's: a 614), in the overlay's
pic_n:      .byte 0             ; data: its characters, layout and
pic_rows:   .byte 0             ; colours
pic_col:    .byte 0
pic_code:   .byte 0
code:       .byte 0             ; page_show()'s
cut_end:    .byte 0
rr:         .byte 0
kk:         .byte 0
half:       .byte 0
pd:         .word 0             ; the rows' codes and colours
pa:         .word 0
yy:         .word 0             ; brief()'s
yend:       .word 0
cd:         .byte 0
cp:         .byte 0
pic_on:     .byte 0
hit:        .byte 0
bn:         .byte 0
bg_:        .byte 0
bd_:        .byte 0
dtk:        .byte 0
ff:         .byte 0
ww:         .byte 0
rr2:        .byte 0
ii:         .byte 0
cc:         .byte 0
rnd_:       .byte 0             ; the round
nn:         .byte 0
pg:         .byte 0             ; title_run()'s page (page_show() has ii)
off:        .word 0

; the rounds' colours: background, letters, border
round_bg:   .byte $77, $5B, $7F
round_fg:   .byte $48, $39, $00
round_bd:   .byte $3B, $3B, $55
s_brief:    .byte "Briefing", 0
s_press:    .byte "Press fire", 0
s_gameon:   .byte "Game on!", 0
s_unit:     .byte "Unit type ", 0
num:        .byte "001 - ", 0
; the start page's lines, the ship's name in the fourth (the original's
; break after "eliminate" where "all" no longer fits), then the cleared
; ship's
s_l1:       .byte "This is the unit that you", 0
s_l2:       .byte "currently control. Prepare", 0
s_l3:       .byte "to board Robo-Freighter", 0
s_elim:     .byte " to eliminate", 0
s_all:      .byte " all", 0
s_l5:       .byte "all rogue robots.", 0
s_c1:       .byte "Congratulations! Ship is", 0
s_c2:       .byte "now clear of all robot", 0
s_c3:       .byte "activity. Bonus of 2000", 0
s_c4:       .byte "awarded.", 0
lines_row:  .byte 12, 14, 16,  12, 14, 16, 18
lines_col:  .byte 10, 9, 9,  10, 9, 9, 9
lines_lo:   .byte <s_l1, <s_l2, <s_l3,  <s_c1, <s_c2, <s_c3, <s_c4
lines_hi:   .byte >s_l1, >s_l2, >s_l3,  >s_c1, >s_c2, >s_c3, >s_c4
; the day's scores taken: the original's words ($E714-$E75B)
s_great:    .byte "Great Score!", 0
s_lowest:   .byte "Lowest Score of the Day!", 0
s_enter:    .byte "Please enter your initials -", 0
s_dots:     .byte "...", 0
ib:         .byte 0             ; the initials': 0 the top score's, 3 the worst's
hs_n:       .byte 0             ; how many taken
hs_l:       .byte 0             ; the one shown: A-Z 0-25, 26 a space
hs_mark:    .byte 0             ; x_code before it
hs_t:       .byte 0
hs_buf:     .res 5
sc:         .byte 0
sd:         .byte 0

        .segment "OVLCODE"

; A := fire pressed: held now, or gone down since the last look (the
; interrupt notes it), so that a short press while a page is being made
; is not lost
fired:  jsr _eng_keys
        ora _keys_irq
        and #K_FIRE
        rts

; colour_keys(): F1 colours, F2 black and white, here too, as the
; original's title ($32B7 in its loop): its word in the panel, if the
; panel shows (not over the logo). From fire_in() once a picture and
; fire_by() once a call - not more often: the keyboard is read with the
; interrupt held off.
colour_keys:
        jsr _pause_keys
        and #4 | 8
        beq @out
        and #8                  ; (as the pause's: 8 black and white)
        sta _bw
        ldy _panel_hi
        cpy #>PANELF
        bne @out
        tay
        bne :+
        lda #<s_colour
        ldx #>s_colour
        jmp _panel_status
:       lda #<s_bw
        ldx #>s_bw
        jmp _panel_status
@out:   rts

; fire_in(A): A pictures; A 1 as soon as fire is pressed
fire_in:
        sta nn
@n:     lda nn
        beq @no
        dec nn
        jsr colour_keys
        lda _frames
:       cmp _frames
        beq :-
        jsr fired
        beq @n
        lda #1
        rts
@no:    lda #0
        rts

; fire_by(A): until picture A; 1 as soon as fire is pressed (looked at
; once at least, also when the picture has gone by already)
fire_by:
        sta nn
        jsr colour_keys
:       jsr fired
        bne @yes
        lda _frames
        sec
        sbc nn
        bmi :-
        lda #0
        rts
@yes:   lda #1
        rts

; just after a picture has begun
frame_start:
        lda _ready
        bne frame_start
        lda _frames
:       cmp _frames
        beq :-
        rts

; the window cleared to colour A
clear:  pha
        lda #0
        jsr pusha
        pla
        jmp _win_clear

; the briefing's character set in picture 1's, which both show; the page
; cleared to colour A
brief_font:
        pha
        jsr frame_start
        pla
        jsr clear
        lda #<FONT1
        sta ptr2
        lda #>FONT1
        sta ptr2+1
        ldx #0
@k:     lda #0                  ; PANELF + brief_srcs[k] * 8
        sta ptr1+1
        lda _brief_srcs,x
        asl a
        rol ptr1+1
        asl a
        rol ptr1+1
        asl a
        rol ptr1+1
        sta ptr1
        lda ptr1+1
        clc
        adc #>PANELF
        sta ptr1+1
        ldy #7
:       lda (ptr1),y
        sta (ptr2),y
        dey
        bpl :-
        lda ptr2
        clc
        adc #8
        sta ptr2
        bcc :+
        inc ptr2+1
:       inx
        cpx #NBRIEF
        bne @k
        lda #$D8
        sta _font_hi
        lda #NBRIEF
        sta free_code
        rts

; picture 0's character set again, and picture 1's deck characters
deck_font:
        jsr frame_start
        lda #$71
        jsr clear
        ldx #0                  ; FONT1 := FONT0, POOL characters
:       lda FONT0,x
        sta FONT1,x
        lda FONT0 + $100,x
        sta FONT1 + $100,x
        lda FONT0 + $200,x
        sta FONT1 + $200,x
        lda FONT0 + $300,x
        sta FONT1 + $300,x
        inx
        bne :-
:       lda FONT0 + $400,x
        sta FONT1 + $400,x
        inx
        cpx #<(POOL * 8)
        bne :-
        lda #$C8
        sta _font_hi
        rts

; A := a copy of character A, the next of the copies for the window's top
; row (or 0 when there are none left)
cut_copy:
        ldx cut_end
        bne :+
        lda #0
        rts
:       ldx #0                  ; g: the character (ptr1)
        stx ptr1+1
        asl a
        rol ptr1+1
        asl a
        rol ptr1+1
        asl a
        rol ptr1+1
        sta ptr1
        lda ptr1+1
        adc #>FONT1
        sta ptr1+1
        lda #0                  ; o: the copy (sreg: page_show() has ptr2)
        sta sreg+1
        lda code
        asl a
        rol sreg+1
        asl a
        rol sreg+1
        asl a
        rol sreg+1
        sta sreg
        lda sreg+1
        adc #>FONT1
        sta sreg+1
        lda #0                  ; all its lines (the TED shows the last k+1
        sta ff                  ; at the window's top)
        ldy #0
@l:     lda #0
        cpy ff
        bcc :+
        lda (ptr1),y
:       sta (sreg),y
        iny
        cpy #8
        bne @l
        dec cut_end
        lda code
        inc code
        rts

; page_show(): the page rolled up by yy pixels, into the back picture. As
; for the deck, the rows move down by k lines, from screen row 8 on; window
; row 0, the gap's last row, shows its last k+1 lines at the window's top,
; its characters copies in codes blank in picture 0's set, the gap's here
; (engine.s). A line of text is its row, column, length and letters. The
; scores page has its picture too (pic_on), in the rows from PIC_ROW. Rows
; 1 to 16 only change when the page has moved by a row: the lines between,
; the fine scroll moves them, and only row 0 is made again.
page_show:
        lda #0                  ; k = -y & 7
        sec
        sbc yy
        and #7
        sta kk
        clc                     ; rr = (y + k) >> 3: the page's row in
        adc yy                  ; window row 1
        sta rr
        lda yy+1
        adc #0
        lsr a
        ror rr
        lsr a
        ror rr
        lsr a
        ror rr
        ldx _back
        lda shown,x
        ldy #1
        cmp rr
        beq :+
        ldy #17
:       sty rows
        lda rr
        sta shown,x
        lda #<(SCR0C + 8 * 40)  ; the back picture's codes and colours
        ldy #<(SCR0A + 8 * 40)
        sta pd
        sty pa
        lda #>(SCR0C + 8 * 40)
        ldy #>(SCR0A + 8 * 40)
        cpx #0
        beq :+
        lda #>(SCR1C + 8 * 40)
        ldy #>(SCR1A + 8 * 40)
:       sta pd+1
        sty pa+1
        lda pd                  ; its rows cleared
        sta ptr1
        lda pd+1
        sta ptr1+1
        ldx rows
@clr:   ldy #39
        lda #0
:       sta (ptr1),y
        dey
        bpl :-
        lda ptr1
        clc
        adc #40
        sta ptr1
        bcc :+
        inc ptr1+1
:       dex
        bne @clr
        lda free_code           ; each picture copies of its own: the free
        cmp #POOL               ; characters halved - from POOL on, where
        bcs :+                  ; picture 0's set (the gap's) is blank
        lda #POOL               ; in the title (title_run())
:       sta ff
        lda #0
        sec
        sbc ff
        lsr a
        sta half
        lda ff
        ldx _back
        beq :+
        clc
        adc half
:       sta _br_code
        lda pd
        sta _br_d
        lda pd+1
        sta _br_d+1
        lda rr
        sta _br_rr
        lda rows
        sta _br_rows
        lda kk
        sta _br_k
        lda half
        sta _br_cutend
        lda bpage
        clc
        adc #1
        sta _br_p
        lda bpage+1
        adc #0
        sta _br_p+1
        jsr _brief_rows
        lda _br_code            ; (the picture's cut copies after)
        sta code
        lda _br_cutend
        sta cut_end
        lda pic_on
        bne :+
        jmp @done
:       lda pa                  ; its column of cells: the text's colour
        clc
        adc #2
        sta ptr1
        lda pa+1
        adc #0
        sta ptr1+1
        ldx rows
@col:   ldy #5
        lda b_fg
:       sta (ptr1),y
        dey
        bpl :-
        lda ptr1
        clc
        adc #40
        sta ptr1
        bcc :+
        inc ptr1+1
:       dex
        bne @col
        lda pic_lay             ; then the picture's
        sta ptr2
        lda pic_lay+1
        sta ptr2+1
        lda #0
        sta rr2
@r:     lda rr2
        cmp pic_rows
        bne :+
        jmp @done
:       lda #0
        sta ii
        beq @i
@nx:    jmp @next
@i:     ldy #0
        lda (ptr2),y
        beq @nx
        sta cc
        lda #PIC_ROW + 2        ; w = PIC_ROW + r + 2 - rr
        clc
        adc rr2
        sec
        sbc rr
        sta ww
        cmp rows
        bcs @nx
        lda ww                  ; the cell: w * 40 + 2 + i
        jsr times40
        lda off
        clc
        adc #2
        adc ii
        sta off
        bcc :+
        inc off+1
:       lda cc                  ; c = pic_code + (l & $7F) - 1
        and #$7F
        clc
        adc pic_code
        sec
        sbc #1
        ldx ww
        bne :+
        jsr cut_copy
:       pha
        lda pd
        clc
        adc off
        sta ptr1
        lda pd+1
        adc off+1
        sta ptr1+1
        pla
        ldy #0
        sta (ptr1),y
        ldx pic_col             ; hires cells in the picture's colour,
        lda _pal_deck,x         ; multicolour ones in its 0-7 one
        ldy cc
        bmi :+
        lda _pal_mc,x
        ora #8
:       pha
        lda pa
        clc
        adc off
        sta ptr1
        lda pa+1
        adc off+1
        sta ptr1+1
        pla
        ldy #0
        sta (ptr1),y
@next:  inc ptr2
        bne :+
        inc ptr2+1
:       inc ii
        lda ii
        cmp #6
        beq :+
        jmp @i
:       inc rr2
        jmp @r
@done:  lda #0
        sta _e_sx
        sta _e_cutrow
        lda kk
        sta _e_s                ; (r_done(): brief(), at its time)
        rts

; off := A * 40 (A below 16)
times40:
        ldx #0
        stx off+1
        sta off
        asl a
        asl a
        adc off                 ; * 5
        asl a                   ; * 10
        asl a
        rol off+1
        asl a
        rol off+1               ; * 40
        sta off
        rts

; score_line(): the day's score at ptr1 (its four bytes) and its
; initials (from initials + ib) into page 4's line at off, as the
; original's: the number to the right of eight cells, " - ", the initials
score_line:
        ldy #2                  ; its four bytes for num_text(): the high
        lda (ptr1),y            ; two in sreg
        sta sreg
        iny
        lda (ptr1),y
        sta sreg+1
        ldy #0
        lda (ptr1),y
        pha
        iny
        lda (ptr1),y
        tax
        pla
        jsr _num_text           ; its digits, PETSCII, num_len of them
        sta ptr2
        stx ptr2+1
        lda #<_brief_pages      ; the line
        clc
        adc off
        sta ptr1
        lda #>_brief_pages
        adc off+1
        sta ptr1+1
        ldy #SCORE_CELLS - 1
        lda _brief_misc
:       sta (ptr1),y
        dey
        bpl :-
        lda #8                  ; the digits from 8 - n on
        sec
        sbc _num_len
        sta sc
        ldy #0
@dig:   lda (ptr2),y
        beq @dash
        and #$0F
        tax
        lda _brief_dig,x
        sty sd
        ldy sc
        sta (ptr1),y
        inc sc
        ldy sd
        iny
        bne @dig
@dash:  ldy #9
        lda _brief_misc+1
        sta (ptr1),y
        ldy #11                 ; the initials, two cells each (a space
        ldx ib                  ; two spaces)
@ini:   stx sd
        lda _initials,x
        cmp #26
        bcs :+
        asl a
        tax
        lda _brief_cap,x
        sta (ptr1),y
        iny
        lda _brief_cap+1,x
        sta (ptr1),y
        dey
:       iny
        iny
        ldx sd
        inx
        cpy #SCORE_CELLS
        bcc @ini
        rts

; title_scores(): after a game, "Transmission terminated" still up: its
; score the day's top or worst, if it is, as the original's ($E4E5):
; "Great Score!" or "Lowest Score of the Day!" over "Transmission",
; "Please enter your initials -" over "Terminated", and three initials
; taken, each from A on: the stick steps through A-Z and a space (up or
; left back, down or right on), fire takes it
_title_scores:
        ldx #3                  ; score > top_score: the top score
@top:   lda _score,x            ; (compared from the high byte down)
        cmp _top_score,x
        bne :+
        dex
        bpl @top
        bmi @low                ; (the same)
:       bcc @low
        ldx #3
:       lda _score,x
        sta _top_score,x
        dex
        bpl :-
        lda #>s_great
        sta sd
        lda #0
        ldx #13
        ldy #<s_great
        jmp @take
@low:   ldx #3                  ; score < low_score: the worst
@lw:    lda _score,x
        cmp _low_score,x
        bne :+
        dex
        bpl @lw
        rts
:       bcc :+
        rts
:       ldx #3
:       lda _score,x
        sta _low_score,x
        dex
        bpl :-
        lda #>s_lowest
        sta sd
        lda #3
        ldx #5
        ldy #<s_lowest
@take:  sta ib
        stx _x_col
        lda #10
        sta _x_row
        tya
        ldx sd
        jsr _say
        lda #22
        sta _x_row
        lda #1
        sta _x_col
        lda #<s_enter
        ldx #>s_enter
        jsr _say
        lda #31                 ; the dots first: their characters stay
        sta _x_col
        lda #<s_dots
        ldx #>s_dots
        jsr _say
        lda #0
        sta hs_n
:       lda _keys_irq           ; (fire still held from the game: let go)
        and #K_FIRE
        bne :-
@next:  lda _x_code
        sta hs_mark
        lda #0
        sta hs_l
@show:  ldx #0                  ; the characters the last one shown took
:       lda _xmap,x             ; made free again
        cmp hs_mark
        bcc :+
        lda #0
        sta _xmap,x
:       inx
        bne :--
        lda hs_mark
        sta _x_code
        ldy #0                  ; the line: those taken, this one, dots,
@ch:    cpy hs_n                ; and a space after them for what a wider
        beq @cur                ; one left
        bcs @dot
        tya
        clc
        adc ib
        tax
        lda _initials,x
        jmp @lt
@cur:   lda hs_l
@lt:    cmp #26
        bcc :+
        lda #$20
        bne @put
:       adc #$C1                ; (carry clear): A-Z
        bne @put
@dot:   lda #$2E
@put:   sta hs_buf,y
        iny
        cpy #3
        bne @ch
        lda #$20
        sta hs_buf+3
        lda #0
        sta hs_buf+4
        lda #22
        sta _x_row
        lda #31
        sta _x_col
        lda #<hs_buf
        ldx #>hs_buf
        jsr _say
        lda _frames             ; 8 pictures, as the original's wait
        clc
        adc #8
        sta hs_t
:       lda _frames
        cmp hs_t
        bne :-
        lda _keys_irq
        tay
        and #K_FIRE
        bne @fire
        tya
        and #K_UP | K_LEFT
        beq :+
        dec hs_l
        bpl @agn
        lda #26
        sta hs_l
        bne @agn
:       tya
        and #K_DOWN | K_RIGHT
        beq @agn
        inc hs_l
        lda hs_l
        cmp #27
        bcc @agn
        lda #0
        sta hs_l
@agn:   jmp @show
@fire:  lda hs_n
        clc
        adc ib
        tax
        lda hs_l
        sta _initials,x
:       lda _keys_irq
        and #K_FIRE
        bne :-
        inc hs_n
        lda hs_n
        cmp #3
        beq :+
        jmp @next
:       rts

; brief(): page bn of the briefing, rolled up, on bg_ in letters b_fg,
; the border bd_; page 4 has the picture; A 1 if fire ended it
brief:  ldx #<(POOL * 8)         ; picture 0's set blank from POOL on: it
        lda #0                  ; is the gap's here, the window's top row's
:       sta FONT0 + $400,x      ; copies are in those codes (and the logo
        inx                     ; keeps the panel's rows there for a while)
        bne :-
:       sta FONT0 + $500,x
        sta FONT0 + $600,x
        sta FONT0 + $700,x
        inx
        bne :-
        lda _col_deck
        sta cd
        jsr _eng_plain
        lda b_fg
        jsr brief_font
        lda #0
        sta pic_on
        lda bn
        cmp #4
        beq :+
        jmp @nopic
:       inc pic_on
        lda free_code           ; the picture's characters
        sta pic_code
        lda pic
        sta ptr1
        lda pic+1
        sta ptr1+1
        lda #0
        sta ptr2+1
        lda pic_code
        asl a
        rol ptr2+1
        asl a
        rol ptr2+1
        asl a
        rol ptr2+1
        sta ptr2
        lda ptr2+1
        clc
        adc #>FONT1
        sta ptr2+1
        lda #0                  ; pic_n * 8 bytes
        sta off+1
        lda pic_n
        asl a
        rol off+1
        asl a
        rol off+1
        asl a
        rol off+1
        sta off
        ldy #0
@cp:    lda off
        ora off+1
        beq @cpd
        lda (ptr1),y
        sta (ptr2),y
        inc ptr1
        bne :+
        inc ptr1+1
:       inc ptr2
        bne :+
        inc ptr2+1
:       lda off
        bne :+
        dec off+1
:       dec off
        jmp @cp
@cpd:   lda free_code
        clc
        adc pic_n
        sta free_code
        lda pic_lay             ; its colour: the header's fourth byte,
        sta ptr1                ; after the layout's rows
        lda pic_lay+1
        sta ptr1+1
        lda pic_rows
        asl a
        sta ff
        asl a
        adc ff
        clc
        adc #3
        tay
        lda (ptr1),y
        tax
        lda _pal_deck,x
        sta _col_fig2
        lda #<_top_score
        sta ptr1
        lda #>_top_score
        sta ptr1+1
        lda #<SCORE_TOP_AT
        sta off
        lda #>SCORE_TOP_AT
        sta off+1
        lda #0
        sta ib
        jsr score_line
        lda #<_low_score
        sta ptr1
        lda #>_low_score
        sta ptr1+1
        lda #<SCORE_LOW_AT
        sta off
        lda #>SCORE_LOW_AT
        sta off+1
        lda #3
        sta ib
        jsr score_line
@nopic: lda bg_
        sta _col_deck
        lda #0                  ; hires but for the picture
        ldx pic_on
        beq :+
        lda #$10
:       sta _win_mc
        lda bd_
        sta _col_border
        jsr _panel_frame
        lda #<s_brief
        ldx #>s_brief
        jsr _panel_status
        lda #<_brief_pages      ; page n: past the lines before
        sta bpage
        lda #>_brief_pages
        sta bpage+1
@skip:  lda bn
        beq @found
        dec bn
        lda bpage
        clc
        adc #1
        sta ptr1
        lda bpage+1
        adc #0
        sta ptr1+1
@line:  ldy #0
        lda (ptr1),y
        cmp #$FF
        beq :+
        ldy #2                  ; p += 3 + p[2]
        lda (ptr1),y
        clc
        adc #3
        adc ptr1
        sta ptr1
        bcc @line
        inc ptr1+1
        bne @line
:       lda ptr1
        clc
        adc #1
        sta bpage
        lda ptr1+1
        adc #0
        sta bpage+1
        jmp @skip
@found: lda bpage
        sta ptr1
        lda bpage+1
        sta ptr1+1
        ldy #0
        lda (ptr1),y
        sta b_h
        lda #0                  ; end = b_h * 8 - 120, or 0
        sta yend+1
        lda b_h
        asl a
        rol yend+1
        asl a
        rol yend+1
        asl a
        rol yend+1
        sec
        sbc #120
        sta yend
        lda yend+1
        sbc #0
        sta yend+1
        bcs :+
        lda #0
        sta yend
        sta yend+1
:       lda #$FF
        sta shown
        sta shown+1
        lda #0                  ; a line of pixels a tick, as the
        sta yy                  ; original; two while the joystick is held
        sta yy+1                ; down
@step:  lda _ready
        bne @step
        ; each step made as soon as the last is shown, and shown at its
        ; picture: ready in picture t + 2, so the interrupt shows it from
        ; t + 3 on - every third picture, however long the step took to
        ; make (one with a new row of characters takes about one)
        jsr page_show
        lda yy
        ora yy+1
        beq @whole
        lda yy
        cmp yend
        bne @mid
        lda yy+1
        cmp yend+1
        bne @mid
@whole: jsr _r_done
        lda TED_SCROLLY         ; (after the logo: now whole)
        and #$10
        bne :+
        lda #1
        jsr picture_on
:       lda #120
        jsr fire_in
        sta hit
        lda _frames
        sec
        sbc #3
        sta tt
        jmp @end
@mid:   lda tt
        clc
        adc #2
        jsr fire_by
        sta hit
        jsr _r_done
@end:   lda hit
        bne @out
        lda yy
        cmp yend
        bne :+
        lda yy+1
        cmp yend+1
        beq @out
:       lda _frames             ; as many lines as ticks have gone by: a
        clc                     ; step that was late after all is made up
        adc #1                  ; for
        sec
        sbc tt
        ldx #0
:       cmp #3
        bcc :+
        sbc #3
        inx
        bne :-
:       stx dtk
        txa
        asl a
        adc dtk
        adc tt
        sta tt
        lda _keys_irq
        and #K_DOWN
        beq :+
        asl dtk
:       lda yy
        clc
        adc dtk
        sta yy
        bcc :+
        inc yy+1
:       lda yy+1                ; no further than the end
        cmp yend+1
        bcc @next
        bne :+
        lda yy
        cmp yend
        bcc @next
:       lda yend
        sta yy
        lda yend+1
        sta yy+1
@next:  jmp @step
@out:   lda #0                  ; (the next page turns it on)
        jsr picture_on
        jsr deck_font
        lda #$10
        sta _win_mc
        lda cd                  ; (the border stays, as the original's
        sta _col_deck           ; start page has it)
        lda #$71
        sta _col_fig2
        lda #<s_press
        ldx #>s_press
        jsr _panel_status
        lda hit                 ; (a short press is over by now)
        rts

; picture_on(A): the picture off (only the border shows) or on again,
; from the next picture on: built while off, a screen shows whole at
; once. The logo leaves it off, for the page after it.
picture_on:
        pha
        jsr frame_start         ; (under the window, the border)
        pla
        php                     ; (the interrupt changes the y scroll in
        sei                     ; it: engine.s's set_s)
        beq :+
        lda TED_SCROLLY
        ora #$10
        sta TED_SCROLLY
        plp
        rts
:       lda TED_SCROLLY
        and #$EF
        sta TED_SCROLLY
        plp                     ; (the border: the interrupt in the blank,
        rts                     ; line 252 - written here, under the
                                ; window, it showed a pixel of snow)

; ptr1 to ptr2, 240 bytes
copy240:
        ldy #239
:       lda (ptr1),y
        sta (ptr2),y
        dey
        cpy #$FF
        bne :-
        rts

; logo(): the original's logo over the whole screen, the panel's rows
; too; A 1 if fire ended it. Built with the picture off, the border
; already in the logo's colour, so nothing half done shows.
logo:   jsr _eng_plain
        lda _col_deck
        sta cd
        lda _col_panel
        sta cp
        lda _deck_bg            ; the deck's colours, as the original's
        sta _col_border         ; ($27E5 on its way to the title): scheme 0
        lda #0                  ; at the start, then the last deck's
        jsr picture_on
        ldy #239                ; the panel's rows kept where the pool's
:       lda SCR0C,y             ; characters are
        sta FONT0 + POOL * 8,y
        lda SCR0A,y
        sta FONT0 + POOL * 8 + 240,y
        dey
        cpy #$FF
        bne :-
        ldx #NLOGO * 8 - 1 - 256    ; its characters (408 bytes)
:       lda _logo_font + 256,x
        sta FONT1 + 256,x
        dex
        cpx #$FF                ; (from 151: not bpl)
        bne :-
        ldx #0
:       lda _logo_font,x
        sta FONT1,x
        inx
        bne :-
        lda #<_logo_rle
        sta ptr1
        lda #>_logo_rle
        sta ptr1+1
        lda #0
        sta off
        sta off+1
@run:   ldy #1                  ; a code and a count, 0 the end
        lda (ptr1),y
        beq @done
        sta nn
        dey
        lda (ptr1),y
        sta cc
        tax
        lda _logo_col,x         ; (its colour class)
        tax
        lda CLS_HR,x
        sta ff
@cell:  lda off
        sta ptr2
        lda off+1
        pha
        ora #>SCR0C
        sta ptr2+1
        ldy #0
        lda cc
        sta (ptr2),y
        lda ptr2+1
        eor #>SCR0C ^ >SCR1C
        sta ptr2+1
        lda cc
        sta (ptr2),y
        pla
        pha
        ora #>SCR0A
        sta ptr2+1
        lda ff
        sta (ptr2),y
        pla
        ora #>SCR1A
        sta ptr2+1
        lda ff
        sta (ptr2),y
        inc off
        bne :+
        inc off+1
:       dec nn
        bne @cell
        lda ptr1
        clc
        adc #2
        sta ptr1
        bcc @run
        inc ptr1+1
        bne @run
@done:  lda _deck_bg
        sta _col_deck
        sta _col_panel
        lda _bw                 ; (startup.s's mark for the start: gone)
        and #8
        sta _bw
        lda #$D8
        sta _font_hi
        sta _panel_hi
        lda #0                  ; (the gap's rows in it too)
        sta _gap_eor
        sta _win_mc             ; hires all over: its colours are any of
        jsr frame_start         ; the 16 (the registers set for it)
        lda #1
        jsr picture_on
        lda #200
        jsr fire_in
        sta hit
        lda #0
        jsr picture_on
        lda #$E0                ; the panel's set again
        sta _panel_hi
        lda #$10                ; (multicolour again, for the next page's
        sta _win_mc             ; pictures)
        lda cd
        sta _col_deck
        lda cp                  ; (the border stays: the next page sets
        sta _col_panel          ; its own, the game the deck's)
        lda #<(FONT0 + POOL * 8)
        sta ptr1
        lda #>(FONT0 + POOL * 8)
        sta ptr1+1
        lda #<SCR0C
        sta ptr2
        lda #>SCR0C
        sta ptr2+1
        jsr copy240
        lda #>SCR1C
        sta ptr2+1
        jsr copy240
        lda #<(FONT0 + POOL * 8 + 240)
        sta ptr1
        lda #>(FONT0 + POOL * 8 + 240)
        sta ptr1+1
        lda #<SCR0A
        sta ptr2
        lda #>SCR0A
        sta ptr2+1
        jsr copy240
        lda #>SCR1A
        sta ptr2+1
        jsr copy240
        ldy #119                ; the gap rows: blank again
        lda #0
:       sta SCR0C + 240,y
        sta SCR1C + 240,y
        dey
        bpl :-
        lda _col_border         ; (kept from the deck before)
        jsr _panel_frame
        jsr deck_font
        lda hit                 ; (still off: see picture_on())
        rts

; a game's start, as the original's: for three and a half seconds (or
; until fire) the player's unit and what it is there for, in the
; original's purple, "Game on!" in the panel - as the transfer's pages
; show a unit. The page stays up while the game makes its figures and the
; deck, some 65 pictures (paradroid.s, page_end()). The same for each ship
; after the first, in whatever droid the player is then ($36B9).
start_page:
        lda #<s_gameon
        ldx #>s_gameon
        jsr _panel_status
        lda _pal_mc+4
        ldx #0
        ldy #3
        jsr unit_page
        lda #18
        sta _x_row
        lda #9
        sta _x_col
        jsr _ship_name
        jsr _say
        lda #<s_elim
        ldx #>s_elim
        jsr _say
        ldx _level              ; ships 3, 5-8: "all" on the last line
        lda #%11110100          ; (bit level - 1)
:       lsr a
        dex
        bne :-
        lda #0
        rol a
        pha
        bne :+
        lda #<s_all
        ldx #>s_all
        jsr _say
:       lda #20
        sta _x_row
        lda #9
        sta _x_col
        pla
        tay
        lda #<(s_l5 + 4)
        ldx #>(s_l5 + 4)
        cpy #0
        beq :+
        lda #<s_l5
        ldx #>s_l5
:       jsr _say
        lda TED_SCROLLY         ; (fire on the logo)
        and #$10
        bne :+
        lda #1
        jsr picture_on
:       lda #175 - 65
        jsr fire_in
:       lda _keys_irq
        and #K_FIRE
        beq :+
        jsr _wait_tick
        jmp :-
:       rts

; ship_pages(): a ship cleared, as the original's ($1272, $3816): 2000
; points to count on, the next ship (no further than the 8th: $67); the
; player's unit on the purple and the congratulations in green, three and
; a half seconds, the points counted meanwhile (one each two pictures, as
; there); then the next ship's start page
_ship_pages:
        ldx #10
:       lda #200
        jsr points
        dex
        bne :-
        lda #SFX_COMPLETE
        jsr _sound
        lda _level
        cmp #8
        bcs :+
        inc _level
:
        lda _pal_deck+4
        sta _col_border
        jsr _panel_frame
        lda _pal_mc+5
        ldx #3
        ldy #7
        jsr unit_page
        lda #88
        sta nn
@wait:  lda _frames
        clc
        adc #2
:       cmp _frames
        bne :-
        jsr _count_on
        lda _score_changed
        beq :+
        jsr _panel_score
:       dec nn
        bne @wait
:       lda _keys_irq           ; (fire let go first)
        and #K_FIRE
        bne :+
        jmp start_page
:       jsr _wait_tick
        jmp :--

; unit_page(A, X, Y): the player's unit, "Unit type 476 - Maintenance
; robot" and lines X to Y of lines_*, in colour A
unit_page:
        sta ii
        stx cc
        sty rr2
:       lda _ready
        bne :-
        jsr _eng_plain
        lda _pal_deck+1
        sta _col_deck
        lda _d_type
        jsr pusha
        lda #12
        jsr pusha
        lda #2
        jsr _picture
        lda ii
        sta _x_attr
        lda #10
        sta _x_row
        lda #3
        sta _x_col
        lda #<s_unit
        ldx #>s_unit
        jsr _say
        ldx _d_type             ; its number: class and two digits
        lda _dr_class,x
        ora #$30
        sta num
        lda _dr_num,x
        ldx #$30
:       cmp #10
        bcc :+
        sbc #10
        inx
        bne :-
:       stx num+1
        ora #$30
        sta num+2
        lda #<num
        ldx #>num
        jsr _say
        lda _d_type
        jsr _unit_name
        jsr _say
        ldx cc
@line:  lda lines_row,x
        sta _x_row
        lda lines_col,x
        sta _x_col
        txa
        pha
        ldy lines_hi,x
        lda lines_lo,x
        pha
        tya
        tax
        pla
        jsr _say
        pla
        tax
        inx
        cpx rr2
        bne @line
        rts

; title_run(): the title's rounds, until fire is pressed and let go
_title_run:
        lda #<_title_pic        ; the scores page's picture, in the
        sta pic                 ; overlay's data
        lda #>_title_pic
        sta pic+1
        lda #<(_title_pic + TITLE_PIC_HEAD)
        sta ptr2
        lda #>(_title_pic + TITLE_PIC_HEAD)
        sta ptr2+1
        ldy #0
        lda (ptr2),y
        sta pic_n
        iny
        lda (ptr2),y
        sta pic_rows
        iny
        lda (ptr2),y
        sta pic_col
        lda pic_rows            ; the layout before e: rows * 6
        asl a
        sta ff
        asl a
        adc ff
        sta ff
        lda ptr2
        sec
        sbc ff
        sta pic_lay
        lda ptr2+1
        sbc #0
        sta pic_lay+1
        jsr _mus_start
        jsr _eng_keys           ; (presses from before: gone)
        lda #<s_press
        ldx #>s_press
        jsr _panel_status
        lda #0
        sta rnd_
@round: jsr logo                ; the original's starts with it
        bne @out
        lda #0
        sta pg
@page:  lda pg
        sta bn
        ldx rnd_
        lda round_bg,x
        sta bg_
        lda round_fg,x
        sta b_fg
        lda round_bd,x
        sta bd_
        jsr brief
        bne @out
        inc pg
        lda pg
        cmp #4
        bne @page
        lda #4                  ; the scores
        sta bn
        lda _pal_deck+1
        sta bg_
        lda _pal_mc+8
        sta b_fg
        ldx rnd_
        lda round_bd,x
        sta bd_
        jsr brief
        bne @out
        ldx rnd_
        inx
        cpx #3
        bcc :+
        ldx #0
:       stx rnd_
        jmp @round
@out:   lda _keys_irq
        and #K_FIRE
        beq :+
        jsr _wait_tick
        jmp @out
:       jsr _mus_stop
        lda #1                  ; (a game starts in 001, on the first ship)
        sta _level
        lda #0
        sta _d_type
        jmp start_page          ; (before the overlay's memory goes)
