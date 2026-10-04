; screens.s - the ship's computer and riding a lift, as the original's
;
; An overlay, kept packed in the program and unpacked into the pictures'
; slots when fire is held at a console or on a lift (paradroid.s), which
; are made again afterwards. In assembly (it was console.c and lift.c) to
; make room.
;
; The console: a page with the host's unit and the ship, deck and alert,
; and a menu of four symbols beside it. Up and down choose, fire takes the
; symbol: the first leaves, the second is the droid enquiry, the third the
; plan of the deck, the fourth the ship from the side. Fire goes back to
; the menu from there.
;
; The enquiry shows a droid's picture and its pages, as the original
; words them (picture.s). Right and left turn the pages, up and down go
; through the droid types the host is cleared for: its own and those
; below.
;
; The plan is the original's: a character a block, the character's code
; being the block's number, in the original's characters and colours, and
; the deck's blocks 3 to 41 across, as the original cuts it.
;
; The lift: the ship from the side, as the original shows it: its map in
; the upper half of the original's deck characters, multicolour, with the
; lift's shaft white and the deck it is at lit. Up and down go along the
; shaft, letting go of fire gets out there. The characters go where the
; figures' usually are, the map straight into the window of both
; pictures.

        .export _console_run, _ride_lift

        .import _wait_tick, _keys_irq, _ready, _sound, _eng_plain, _win_clear
        .import _win_put, _wp_row, _wp_col, _wp_code, _wp_attr
        .import _col_deck, _font_hi, _x_code, _x_row, _x_col, _x_attr, _xmap
        .import _x_letter, _say, _unit_name, _picture, _pic_pages
        .import _panel_status, _page_end, _anim_plan
        .import _pal_deck, _pal_mc, _dr_class, _dr_num, _d_type, _d_x, _d_y
        .import _deck, _alert, _deck_bg
        .import _icon_font, _icon_tab, _icon_lay, _plan_font, _plan_cls
        .import _side_font, _side_col, _side_rle, _side_box
        .import _shaft_col, _shaft_top, _shaft_len
        .import _lift_shaft, _lift_deck
        .import pusha
        .importzp ptr1, ptr2

        .include "build/gen/tiles.inc"   ; POOL
        .include "build/gen/sfx.inc"

K_UP      = 1                   ; game.h
K_DOWN    = 2
K_LEFT    = 4
K_RIGHT   = 8
K_FIRE    = 16
ICON_N    = 51                  ; data.h
ICON_CODE = 1
NSIDE     = 48
SIDE_BASE = 5
NLIFTS    = 30
BLK_VDOOR = 1
BLK_HDOOR = 2
BLK_VOPEN = 32
BLK_HOPEN = 36
SIDE      = POOL + SIDE_BASE - $80  ; screen code of original code c: c + SIDE
CLS_HR    = $EAA0               ; the scheme's colour of each class
DMAP      = $0400
SCR0A     = $C000
SCR0C     = $C400
SCR1A     = $D000
SCR1C     = $D400
FONT0     = $C800
FONT1     = $D800

        .bss
k:      .res 1                  ; the keys now and the tick before
prev:   .res 1
sel:    .res 1                  ; the menu's symbol
ccd:    .res 1
num:    .res 4
ct:     .res 1                  ; working values
cn:     .res 1
cr:     .res 1
cc:     .res 1
cv:     .res 1
cw:     .res 1
ch:     .res 1
ci:     .res 1
top:    .res 1
pages:  .res 1
cend:   .res 1
cbx:    .res 1
cby:    .res 1
off:    .res 2
li:     .res 1
nl:     .res 1
dbuf:   .res 8

        .segment "CONDATA"
s_unit:     .byte "Unit type ", 0
s_dash:     .byte " - ", 0
s_access:   .byte "Access granted.", 0
s_ship:     .byte "Ship  : Paradroid", 0
s_deck:     .byte "Deck  : ", 0
s_alert:    .byte "Alert : ", 0
s_console:  .byte "Console", 0
s_more:     .byte "More...", 0
s_plan:     .byte "Deck plan", 0
s_shipv:    .byte "Ship", 0
s_mobile:   .byte "Mobile", 0
s_decknum:  .byte "Deck ", 0
d0:  .byte "observation", 0
d1:  .byte "bridge", 0
d2:  .byte "airlock", 0
d3:  .byte "reactor", 0
d4:  .byte "research", 0
d5:  .byte "stores", 0
d6:  .byte "staterooms", 0
d7:  .byte "repairs", 0
d8:  .byte "quarters", 0
d9:  .byte "robo-stores", 0
d10: .byte "upper cargo", 0
d11: .byte "mid cargo", 0
d12: .byte "vehicle hold", 0
d13: .byte "shuttle bay", 0
d14: .byte "engineering", 0
d15: .byte "maintenance", 0
deck_lo:    .byte <d0, <d1, <d2, <d3, <d4, <d5, <d6, <d7
            .byte <d8, <d9, <d10, <d11, <d12, <d13, <d14, <d15
deck_hi:    .byte >d0, >d1, >d2, >d3, >d4, >d5, >d6, >d7
            .byte >d8, >d9, >d10, >d11, >d12, >d13, >d14, >d15
a0: .byte "green", 0
a1: .byte "yellow", 0
a2: .byte "amber", 0
a3: .byte "red", 0
alert_lo:   .byte <a0, <a1, <a2, <a3
alert_hi:   .byte >a0, >a1, >a2, >a3

        .segment "CONCODE"

; the keys of this tick
tick_keys:
        jsr _wait_tick
        lda k
        sta prev
        lda _keys_irq
        sta k
        rts

; A := the keys A that went down this tick (Z set if none)
pressed:
        sta cv
        lda prev
        eor #$FF
        and k
        and cv
        rts

; picture 1's set for the window, cleared to colour A, on background X
clear:  stx cc
        pha
:       lda _ready
        bne :-
        jsr _eng_plain
        lda #0
        jsr pusha
        pla
        jsr _win_clear
        lda cc
        sta _col_deck
        lda #$D8
        sta _font_hi
        lda #140
        sta _x_code
        lda #0
        ldx #127
:       sta _xmap,x
        dex
        bpl :-
        rts

; text A/X at row cr, column cc
text:   ldy cr
        sty _x_row
        ldy cc
        sty _x_col
        jmp _say

; the unit line: "Unit type 476 - Maintenance robot", type A
unit_line:
        sta ct
        tax
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
        lda #0
        sta num+3
        lda #10
        sta cr
        lda #3
        sta cc
        lda #<s_unit
        ldx #>s_unit
        jsr text
        lda #<num
        ldx #>num
        jsr _say
        lda #<s_dash
        ldx #>s_dash
        jsr _say
        lda ct
        jsr _unit_name
        jmp _say

; ---- the menu page ----

; the menu's symbols: the chosen one white, the others light grey
icons:  lda #<_icon_lay
        sta ptr2
        lda #>_icon_lay
        sta ptr2+1
        lda #0
        sta ci                  ; the symbol
@i:     lda ci                  ; its column, row, width, height
        asl a
        asl a
        tax
        lda _icon_tab+2,x
        sta cw
        lda _icon_tab+3,x
        sta ch
        lda #0
        sta cr
@r:     lda #0
        sta cc
@c:     ldy #0
        lda (ptr2),y
        inc ptr2
        bne :+
        inc ptr2+1
:       tay
        beq @n
        clc
        adc #ICON_CODE - 1
        sta _wp_code
        lda ci
        asl a
        asl a
        tax
        lda _icon_tab+1,x
        clc
        adc cr
        sta _wp_row
        lda _icon_tab,x
        clc
        adc cc
        sta _wp_col
        lda _pal_deck+15
        ldx ci
        cpx sel
        bne :+
        lda _pal_deck+1
:       sta _wp_attr
        jsr _win_put
@n:     inc cc
        lda cc
        cmp cw
        bne @c
        inc cr
        lda cr
        cmp ch
        bne @r
        inc ci
        lda ci
        cmp #4
        bne @i
        rts

menu_page:
        ldx #$48                ; the original's orange
        lda #$71
        jsr clear
        lda #<_icon_font        ; the symbols' characters
        sta ptr1
        lda #>_icon_font
        sta ptr1+1
        lda #<(FONT1 + ICON_CODE * 8)
        sta ptr2
        lda #>(FONT1 + ICON_CODE * 8)
        sta ptr2+1
        ldx #>(ICON_N * 8)
        lda #<(ICON_N * 8)
        jsr copy
        lda _pal_deck+7
        sta _x_attr
        lda _d_type
        jsr unit_line
        lda #12
        sta cc
        lda #12
        sta cr
        lda #<s_access
        ldx #>s_access
        jsr text
        lda #15
        sta cr
        lda #<s_ship
        ldx #>s_ship
        jsr text
        lda #18
        sta cr
        lda #<s_deck
        ldx #>s_deck
        jsr text
        ldy _deck
        lda deck_lo,y
        ldx deck_hi,y
        jsr _say
        lda #21
        sta cr
        lda #<s_alert
        ldx #>s_alert
        jsr text
        ldy _alert
        lda alert_lo,y
        ldx alert_hi,y
        jsr _say
        jsr icons
        lda #<s_console
        ldx #>s_console
        jmp _panel_status

; A/X bytes from ptr1 to ptr2
copy:   sta cw
        stx ch
        ldy #0
@b:     lda cw
        ora ch
        beq @done
        lda (ptr1),y
        sta (ptr2),y
        inc ptr1
        bne :+
        inc ptr1+1
:       inc ptr2
        bne :+
        inc ptr2+1
:       lda cw
        bne :+
        dec ch
:       dec cw
        jmp @b
@done:  rts

; ---- the droid enquiry ----

; page cn of type ct's: lines of row, column, length and letters, then
; $FF; a 0 after the last page
enquiry_page:
        lda ct
        jsr pusha
        lda #12
        jsr pusha
        lda #2
        jsr _picture
        lda _pal_deck+1
        sta _col_deck
        lda #140
        sta _x_code
        lda #$63                ; the original's light cyan
        sta _x_attr
        lda ct
        jsr unit_line
        lda _pal_mc+2           ; (beside a multicolour picture)
        sta _x_attr
        lda _pic_pages
        sta ptr2
        lda _pic_pages+1
        sta ptr2+1
        ldx cn                  ; past the pages before
        beq @line
:       jsr next_byte
        cmp #$FF
        bne :-
        dex
        bne :-
@line:  ldy #0
        lda (ptr2),y
        cmp #$FF
        beq @done
        jsr next_byte
        sta _x_row
        jsr next_byte
        sta _x_col
        jsr next_byte
        sta cw
@l:     lda cw
        beq @line
        jsr next_byte
        jsr _x_letter
        dec cw
        jmp @l
@done:  lda #<s_more
        ldx #>s_more
        ldy cn
        bne :+
        lda #<s_console
        ldx #>s_console
:       jmp _panel_status

; A := the byte at ptr2, ptr2 on (X, Y kept)
next_byte:
        sty cv
        ldy #0
        lda (ptr2),y
        inc ptr2
        bne :+
        inc ptr2+1
:       ldy cv
        rts

enquiry:
        lda _d_type
        sta top
        sta ct
        lda #0
        sta cn
@page:  jsr enquiry_page
        lda _pic_pages          ; its pages: each ends with $FF, then a 0
        sta ptr2
        lda _pic_pages+1
        sta ptr2+1
        lda #0
        sta pages
@count: ldy #0
        lda (ptr2),y
        beq @keys
:       jsr next_byte
        cmp #$FF
        bne :-
        inc pages
        bne @count
@keys:  jsr tick_keys
        lda #K_FIRE | K_LEFT | K_RIGHT | K_UP | K_DOWN
        jsr pressed
        beq @keys
        lda #K_FIRE
        jsr pressed
        beq :+
        rts
:       lda #K_RIGHT
        jsr pressed
        beq @left
        ldx cn                  ; the next page, round to the first
        inx
        cpx pages
        bcc :+
        ldx #0
:       stx cn
        jmp @sound
@left:  lda #K_LEFT
        jsr pressed
        beq @type
        ldx cn                  ; the page before, round to the last
        bne :+
        ldx pages
:       dex
        stx cn
        jmp @sound
@type:  lda #K_UP               ; up: a type lower, round to the host's
        jsr pressed
        beq @down
        ldx ct
        bne :+
        ldx top
        inx
:       dex
        stx ct
        jmp @first
@down:  ldx ct                  ; down: a type higher, round to the 001
        cpx top
        bcc :+
        ldx #$FF
:       inx
        stx ct
@first: lda #0
        sta cn
@sound: lda #SFX_LIFT
        jsr _sound
        jmp @page

; ---- the deck plan ----

plan:   ldx _deck_bg
        lda #$71
        jsr clear
        ldx #33 * 8 - 1 - 256   ; its characters (264 bytes)
:       lda _plan_font + 256,x
        sta FONT1 + 256,x
        dex
        bpl :-
        ldx #0
:       lda _plan_font,x
        sta FONT1,x
        inx
        bne :-
        lda _d_x+1              ; the player's block
        sta cbx
        lda _d_x
        asl a
        rol cbx
        asl a
        rol cbx
        asl a
        rol cbx
        lda _d_y+1
        sta cby
        lda _d_y
        asl a
        rol cby
        asl a
        rol cby
        asl a
        rol cby
        lda #<(9 * 40)
        sta off
        lda #>(9 * 40)
        sta off+1
        lda #0
        sta cr                  ; y
@y:     lda cr                  ; DMAP row y
        lsr a
        lsr a
        clc
        adc #>DMAP
        sta ptr1+1
        lda cr
        ror a
        ror a
        ror a
        and #$C0
        sta ptr1
        lda #3
        sta cc                  ; x
@x:     ldy cc
        lda (ptr1),y
        lsr a
        lsr a
        cmp #BLK_VOPEN          ; a door half open: the door
        bcc :+
        cmp #BLK_HOPEN
        lda #BLK_VDOOR
        bcc :+
        lda #BLK_HDOOR
:       ldx cc                  ; the player
        cpx cbx
        bne :+
        ldx cr
        cpx cby
        bne :+
        lda #32
:       sta cv
        lda off                 ; at (9 + y) * 40 + x - 3
        clc
        adc cc
        sta ptr2
        lda off+1
        adc #0
        sta ptr2+1
        lda ptr2
        sec
        sbc #3
        sta ptr2
        bcs :+
        dec ptr2+1
:       ldy #0
        lda ptr2+1
        pha
        ora #>SCR0C
        sta ptr2+1
        lda cv
        sta (ptr2),y
        lda ptr2+1
        eor #>SCR0C ^ >SCR1C
        sta ptr2+1
        lda cv
        sta (ptr2),y
        ldx cv                  ; hires, as the original's
        lda _plan_cls,x
        tax
        lda CLS_HR,x
        sta cw
        pla
        pha
        ora #>SCR0A
        sta ptr2+1
        lda cw
        sta (ptr2),y
        pla
        ora #>SCR1A
        sta ptr2+1
        lda cw
        sta (ptr2),y
        inc cc
        lda cc
        cmp #42
        beq :+
        jmp @x
:
        lda off
        clc
        adc #40
        sta off
        bcc :+
        inc off+1
:       inc cr
        lda cr
        cmp #16
        beq :+
        jmp @y
:       lda #<s_plan
        ldx #>s_plan
        jmp _panel_status

; ---- the console ----

_console_run:
        lda _col_deck
        sta ccd
        lda #0
        sta sel
        lda _keys_irq
        sta k
        jsr menu_page
@loop:  jsr tick_keys
        lda #K_UP | K_DOWN
        jsr pressed
        beq @fire
        ldx #1                  ; down: the next symbol, up: the one before
        lda #K_UP
        jsr pressed
        beq :+
        ldx #3
:       txa
        clc
        adc sel
        and #3
        sta sel
        jsr icons
        lda #SFX_LIFT
        jsr _sound
@fire:  lda #K_FIRE
        jsr pressed
        beq @loop
        lda sel
        beq @leave
        cmp #1
        bne @other
        jsr enquiry
        jmp @menu
@other: cmp #2
        bne @ship
        jsr plan
        jmp @wait
@ship:  lda #$C8
        sta _font_hi
        jsr side_view
        lda _deck
        jsr side_light
        lda #<s_shipv
        ldx #>s_shipv
        jsr _panel_status
@wait:  jsr tick_keys
        lda sel
        cmp #2
        bne :+
        jsr _anim_plan          ; energizers, the player
:       lda #K_FIRE
        jsr pressed
        beq @wait
@menu:  lda #$C8
        sta _font_hi
        jsr menu_page
        jmp @loop
@leave: lda ccd
        jsr _page_end
:       lda _keys_irq
        and #K_FIRE
        beq :+
        jsr _wait_tick
        jmp :-
:       lda #<s_mobile
        ldx #>s_mobile
        jmp _panel_status

; ---- the lift ----

; A := the screen colour of the side view's colour A
side_attr:
        cmp #8
        bcs :+
        tax
        lda _pal_mc,x
        rts
:       and #7
        tax
        lda _pal_mc,x
        ora #8
        rts

; the ship from the side, from row 10, as in the original
side_view:
        ldx #NSIDE * 8 - 1 - 256
:       lda _side_font + 256,x
        sta FONT0 + (POOL + SIDE_BASE) * 8 + 256,x
        sta FONT1 + (POOL + SIDE_BASE) * 8 + 256,x
        dex
        bpl :-
        ldx #0
:       lda _side_font,x
        sta FONT0 + (POOL + SIDE_BASE) * 8,x
        sta FONT1 + (POOL + SIDE_BASE) * 8,x
        inx
        bne :-
        jsr _eng_plain
        lda #0
        jsr pusha
        lda #$71
        jsr _win_clear
        lda #<_side_rle
        sta ptr1
        lda #>_side_rle
        sta ptr1+1
        lda #<(10 * 40)
        sta off
        lda #>(10 * 40)
        sta off+1
@run:   ldy #1                  ; a code and a count, 0 the end
        lda (ptr1),y
        bne :+
        jmp @done
:       sta cn
        dey
        lda (ptr1),y
        sta cv
        lda ptr1
        clc
        adc #2
        sta ptr1
        bcc :+
        inc ptr1+1
:       lda cv
        beq @skip
        sec                     ; its colour
        sbc #$80
        tax
        lda _side_col,x
        jsr side_attr
        sta cw
        lda cv
        clc
        adc #SIDE
        sta ch
@c:     lda off
        sta ptr2
        lda off+1
        pha
        ora #>SCR0C
        sta ptr2+1
        ldy #0
        lda ch
        sta (ptr2),y
        lda ptr2+1
        eor #>SCR0C ^ >SCR1C
        sta ptr2+1
        lda ch
        sta (ptr2),y
        pla
        pha
        ora #>SCR0A
        sta ptr2+1
        lda cw
        sta (ptr2),y
        pla
        ora #>SCR1A
        sta ptr2+1
        lda cw
        sta (ptr2),y
        inc off
        bne :+
        inc off+1
:       dec cn
        bne @c
        jmp @run
@skip:  lda off                 ; nothing there: the count on
        clc
        adc cn
        sta off
        bcc :+
        inc off+1
:       jmp @run
@done:  rts

; off := row A * 40 + column X
rowcol: stx cw
        ldx #0
        stx off+1
        sta off
        asl a
        asl a
        adc off                 ; * 5
        asl a
        asl a
        rol off+1
        asl a
        rol off+1               ; * 40
        adc cw
        sta off
        bcc :+
        inc off+1
:       rts

; shaft A: its colour white, the lift ridden
shaft:  tax
        lda _shaft_len,x
        sta cn
        lda _shaft_top,x
        pha
        lda _shaft_col,x
        tax
        pla
        jsr rowcol
        lda _pal_mc+1
        ora #8
        sta cw
@r:     lda off
        sta ptr2
        lda off+1
        pha
        ora #>SCR0A
        sta ptr2+1
        ldy #0
        lda cw
        sta (ptr2),y
        pla
        ora #>SCR1A
        sta ptr2+1
        lda cw
        sta (ptr2),y
        lda off
        clc
        adc #40
        sta off
        bcc :+
        inc off+1
:       dec cn
        bne @r
        rts

; side_light(d): deck d lit, or no longer: as the original, its box's
; codes $80.. turn into $90.. and back, the ends of the deck's bars and the
; shafts kept
side_light:
        asl a
        asl a
        sta ci
        tay
        ldx _side_box+1,y       ; its row and column
        lda _side_box,y
        jsr rowcol
        ldy ci
        lda _side_box+2,y
        sta ch                  ; h
        lda _side_box+3,y
        sta cw                  ; w
        lda #0
        sta cr
@row:   lda #0
        sta cc                  ; x
        sta cend
        beq @x
@nr:    jmp @nrow
@x:     lda cend
        bne @nr
        lda cc
        cmp cw
        bcs @nr
        lda off                 ; SCR0C[off + x]
        clc
        adc cc
        sta ptr2
        lda off+1
        adc #>SCR0C
        sta ptr2+1
        ldy #0
        lda (ptr2),y
        cmp #POOL + SIDE_BASE
        bcc @nx
        sec
        sbc #SIDE
        ldx ch
        cpx #1
        bne @more
        cmp #$9C                ; one row: the bars, and the ends that are
        beq @dn                 ; lit too
        cmp #$9D
        beq @dn
        cmp #$90
        bcc :+
        cmp #$93
        bcc @dn
:       cmp #$8C
        bcc :+
        cmp #$8E
        bcc @up
:       cmp #$83
        bcc @up
        jmp @nx
@dn:    sec
        sbc #$10
        jmp @put
@up:    clc
        adc #$10
        jmp @put
@more:  cmp #$9E                ; more rows: up to the right end of each
        bcs @nx
        tax
        cmp #$90
        bcs :+
        adc #$10                ; c < $90: v = c + $10, c = v
        tax
        jmp :++
:       sbc #$10                ; else v = c, c = c - $10
:       stx cv                  ; v
        pha
        lda cv
        cmp #$92
        beq @end
        cmp #$95
        beq @end
        cmp #$98
        beq @end
        cmp #$9B
        bne :+
@end:   lda #1
        sta cend
:       pla
@put:   clc
        adc #SIDE
        ldy #0
        sta (ptr2),y
        tax
        lda ptr2+1
        eor #>SCR0C ^ >SCR1C
        sta ptr2+1
        txa
        sta (ptr2),y
@nx:    inc cc
        jmp @x
@nrow:  lda off
        clc
        adc #40
        sta off
        bcc :+
        inc off+1
:       inc cr
        lda cr
        cmp ch
        beq :+
        jmp @row
:       rts

; the panel: "Deck n"
deck_name:
        ldx #0
:       lda s_decknum,x
        sta dbuf,x
        beq :+
        inx
        bne :-
:       ldy li
        lda _lift_deck,y
        cmp #10
        bcc :+
        sbc #10
        pha
        lda #$31
        sta dbuf,x
        inx
        pla
:       ora #$30
        sta dbuf,x
        lda #0
        sta dbuf+1,x
        lda #<dbuf
        ldx #>dbuf
        jmp _panel_status

; ride_lift(li): the lift li is on; returns the one got out at
; (paradroid.s enters its deck: that unpacks into the slots, where this
; runs)
_ride_lift:
        sta li
:       lda _ready
        bne :-
        lda #SFX_LIFT
        jsr _sound
        jsr side_view
        ldx li
        lda _lift_shaft,x
        jsr shaft
        ldx li
        lda _lift_deck,x
        jsr side_light
        jsr deck_name
        lda _keys_irq
        sta prev
@loop:  jsr _wait_tick
        lda _keys_irq
        sta k
        and #K_FIRE
        beq @out
        lda li
        sta nl
        lda k                   ; up: the lift above on the same shaft
        and #K_UP
        beq @down
        lda prev
        and #K_UP
        bne @down
        ldx li
        beq @down
        lda _lift_shaft-1,x
        cmp _lift_shaft,x
        bne @down
        dex
        stx nl
@down:  lda k                   ; down: the one below
        and #K_DOWN
        beq @new
        lda prev
        and #K_DOWN
        bne @new
        ldx li
        inx
        cpx #NLIFTS
        bcs @new
        lda _lift_shaft,x
        ldy li
        cmp _lift_shaft,y
        bne @new
        stx nl
@new:   lda k
        sta prev
        lda nl
        cmp li
        beq @loop
        ldx li
        lda _lift_deck,x
        jsr side_light
        lda nl
        sta li
        tax
        lda _lift_deck,x
        jsr side_light
        jsr deck_name
        lda #SFX_RIDE
        jsr _sound
        jmp @loop
@out:   lda li
        ldx #0
        rts
