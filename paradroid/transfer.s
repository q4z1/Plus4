; transfer.s - taking a droid over: the circuit game
;
; As in the original: the two sides, yellow on the left and purple on the
; right, face each other across a column of 12 lights. Each side has 12
; lines, from its rail to the column, in four layers: where pulses are
; put in, two layers of parts, and the connection to the column. The parts
; are the original's: wire, dead end, amplifier (once it carries a pulse,
; it keeps it), colour changer (the light goes to the other side), branch
; (one line in, two out) and gate (two in, both needed, one out). How the
; parts are laid out and how a pulse passes them follows FreedroidClassic,
; whose authors rebuilt the original's game; the numbers of pulses (the
; droid's class and 3, the other side's class and 4) and how the other side
; plays are taken from the original's code. A light shows the side whose
; line is live there, flickers when both are, and when the time is up the
; side with more lights has won; a draw is a deadlock and is played again.
;
; The board is the original's characters, multicolour, drawn into the
; window of both pictures where the figures' characters usually are.
; Nothing is scrolled or moved in it, so the deck is simply rebuilt
; afterwards.
;
; The transfer's overlay (with xfer.s's board): kept packed, unpacked into
; the pictures' slots by paradroid.s, which makes them again afterwards.
; The droids' pictures and the panel's letters are always there
; (picture.s).

        .export _transfer_game

        .import _x_pass, _x_line, _x_step, _x_flow, _x_layout, _x_droid
        .import _part, _live, _life, _xs, _xr, _tcol, _blk
        .import _x_attr, _x_row, _x_col, _x_code
        .import _win_put, _wp_row, _wp_col, _wp_code, _wp_attr, _win_clear
        .import _picture, _say, _unit_name, _page_end, _panel_status
        .import _board_droid, _eng_plain, _sound, _rnd
        .import _wait_tick
        .import _frames, _ready, _tick, _keys_irq, _col_deck
        .import _pal_deck, _pal_mc, _dr_class, _dr_num, _d_type, _board_font
        .import pusha
        .importzp ptr1

        .include "game.inc"
        .include "data.inc"

NL      = 12                    ; lines a side
ROW0    = 12                    ; screen row of the first line
FIG     = POOL + NBOARD         ; the two droids' characters
G_D0    = POOL + 14             ; the original's $D0 and $D1
G_D1    = POOL + 15
.define GLYPH(c) POOL + (c) - $F1   ; the original's $F1-$FE
WIRE    = 0                     ; the parts (xfer.s)
DEAD    = 1
AMP     = 2
SWAP    = 3
L2      = 2 * NL
L3      = 3 * NL

        .bss
light:  .res NL                 ; 0 yellow, 1 purple
pulses: .res 2
cursor: .res 2                  ; 0: above the lines, else line + 1
me:     .res 1                  ; the player's side
leader: .res 1                  ; 0, 1, or 2 for a draw
ds:     .res 1                  ; the side cell() draws for: its columns
                                ; counted from the left side's
flick:  .res 1
target: .res 1                  ; the other side's line
num:    .res 4
text:   .res 12
tt:     .res 1                  ; working values
tk:     .res 1
ts:     .res 1
tr:     .res 1
tv:     .res 1
ti:     .res 1                  ; the droid played against
tcd:    .res 1
tprev:  .res 1
tn:     .res 1
ta:     .res 1                  ; unit()'s colour and lines
tl1:    .res 2
tl2:    .res 2
ln:     .res 1                  ; lights()'s
lr:     .res 1
ly:     .res 1
lv:     .res 1
lc:     .res 1

        .segment "XFERDATA"
s_unit:     .byte "Unit type ", 0
s_dash:     .byte " - ", 0
s_this:     .byte "This is the unit that you", 0
s_curr:     .byte "currently control.", 0
s_none:     .byte 0
s_wish:     .byte "wish to control. Prepare to", 0
s_trans:    .byte "transfer.", 0
s_colour:   .byte "Colour? ", 0
s_finish:   .byte "Finish -", 0
s_dead:     .byte "Deadlock", 0

        .segment "XFERCODE"

; cell(): column A (counted from the left side's) of side ds in row
; wp_row: character X in colour Y
cell:   stx _wp_code
        sty _wp_attr
        ldx ds
        beq :+
        eor #$FF                ; 39 - col
        sec
        adc #39
:       sta _wp_col
        jmp _win_put

; put(): column A of row tr, character X, colour Y, on the left's side
put:    pha
        lda tr
        sta _wp_row
        lda #0
        sta ds
        pla
        jmp cell

; line A of side ts drawn
draw_line:
        sta _xr
        lda ts
        sta _xs
        jmp _x_line

; draw_cursor(): the pulse in hand at side ts's cursor (if tv), or the
; cell under it again
draw_cursor:
        ldx ts
        lda cursor,x
        beq :+
        sec
        sbc #1
        jsr draw_line
:       lda ts
        sta ds
        ldx ts
        lda cursor,x
        clc
        adc #ROW0 - 1
        sta _wp_row
        lda cursor,x
        bne @hand
        ldx #GLYPH($F1)         ; the arrow above the lines
        lda ts
        beq :+
        ldx #GLYPH($F2)
:       ldy _blk
        lda #4
        jsr cell
@hand:  lda tv
        beq @off
        ldx ts
        lda pulses,x
        beq @off
        ldy _tcol,x
        ldx #GLYPH($FD)
        lda ts
        beq :+
        ldx #GLYPH($F3)
:       lda #5
        jmp cell
@off:   ldx ts
        lda cursor,x
        bne :+
        ldx #0
        ldy _blk
        lda #5
        jmp cell
:       rts

; the pulses side ts has left beside its rail, the one in hand not
; counted
draw_pulses:
        lda ts
        sta ds
        lda #0
        sta tn
@i:     lda tn
        clc
        adc #ROW0
        sta _wp_row
        ldx ts
        ldy _tcol,x
        lda tn                  ; i + 1 < pulses: one there
        clc
        adc #1
        cmp pulses,x
        ldx #0
        bcs :+
        ldx #GLYPH($FD)
        lda ts
        beq :+
        ldx #GLYPH($F3)
:       lda #1
        jsr cell
        inc tn
        lda tn
        cmp #NL
        bne @i
        rts

; light A drawn
draw_light:
        tax
        clc
        adc #ROW0
        sta tr
        ldy light,x
        lda _tcol,y
        sta tk
        tay
        ldx #GLYPH($F8)
        lda #19
        jsr put
        ldy tk
        ldx #GLYPH($F8)
        lda #20
        jmp cell

; the light above and below the column: the leader's colour
draw_leader:
        ldx leader
        ldy _blk
        cpx #2
        bcs :+
        ldy _tcol,x
:       sty tk
        lda #10
        sta tr
        ldx #GLYPH($F8)
        lda #19
        jsr put
        ldy tk
        ldx #GLYPH($F8)
        lda #20
        jsr cell
        lda #11
        sta tr
        ldy tk
        ldx #GLYPH($FE)
        lda #19
        jsr put
        ldy tk
        ldx #GLYPH($FE)
        lda #20
        jmp cell

; both droids above the board, on their sides
draw_droids:
        lda #0
        sta tn
@k:     lda tn                  ; their cells cleared first
        lsr a
        lsr a
        lsr a
        clc
        adc #9
        sta tr
        lda tn
        and #3
        clc
        adc #7
        tax
        lda tn
        and #4
        beq :+
        txa
        clc
        adc #29 - 7
        tax
:       txa
        ldx #0
        ldy _blk
        jsr put
        inc tn
        lda tn
        cmp #16
        bne @k
        lda _pal_deck+1
        ora #8
        sta _x_attr
        lda #9
        sta _x_row
        lda #FIG
        sta _x_code
        ldx #7                  ; the player's on its side
        ldy #29
        lda me
        beq :+
        ldx #29
        ldy #7
:       stx _x_col
        sty tk
        lda #SLOT_PANIM + 1
        jsr _x_droid
        lda tk
        sta _x_col
        lda #SLOT_PANIM + 2
        jmp _x_droid

; the board: both sides' rails, lines, pulses and cursors, the column of
; lights between, the droids above
board:  lda #0
        jsr pusha
        lda _blk
        jsr _win_clear
        lda #0
        sta ts
@side:  lda ts
        sta ds
        lda #ROW0 - 2
        sta tr
@row:   lda tr
        sta _wp_row
        ldx #GLYPH($F6)         ; the rail: its top, its middle, its foot
        cmp #ROW0 - 2
        bne :+
        ldx #GLYPH($F5)
:       cmp #ROW0 + NL
        bne :+
        ldx #GLYPH($F7)
:       ldy ts
        lda _tcol,y
        tay
        lda #3
        jsr cell
        lda tr                  ; the connection to the column
        cmp #ROW0
        bcs @lines
        ldx #G_D0
        lda ts
        beq @c18
        ldx #G_D1
        bne @c18
@lines: cmp #ROW0 + NL
        bcs @nrow
        ldx #GLYPH($F9)
        lda ts
        beq @c18
        ldx #GLYPH($FA)
@c18:   ldy ts
        lda _tcol,y
        tay
        lda #18
        jsr cell
@nrow:  inc tr
        lda tr
        cmp #ROW0 + NL + 1
        bne @row
        lda #0
        sta tn
:       lda tn
        jsr draw_line
        inc tn
        lda tn
        cmp #NL
        bne :-
        jsr draw_pulses
        lda #1
        sta tv
        jsr draw_cursor
        inc ts
        lda ts
        cmp #2
        beq :+
        jmp @side
:       lda #9                  ; the column's top and foot
        sta tr
        ldx #GLYPH($FB)
        ldy _blk
        lda #19
        jsr put
        ldx #GLYPH($FB)
        ldy _blk
        lda #20
        jsr cell
        lda #ROW0 + NL
        sta tr
        ldx #GLYPH($FC)
        ldy _blk
        lda #19
        jsr put
        ldx #GLYPH($FC)
        ldy _blk
        lda #20
        jsr cell
        lda #0
        sta tn
:       lda tn
        jsr draw_light
        inc tn
        lda tn
        cmp #NL
        bne :-
        jsr draw_leader
        jmp draw_droids

; ---- the lights (ProcessDisplayColumn) ----

lights: lda flick
        eor #1
        sta flick
        lda #0
        sta ln                  ; the purple ones
        sta lr
@r:     ldx lr
        ldy #0                  ; a colour changer before the column?
        lda _part + L2,x
        cmp #SWAP
        bne :+
        iny
:       sty ly                  ; yellow's
        ldy #0
        lda _part + 4 * NL + L2,x
        cmp #SWAP
        bne :+
        iny
:       sty lv                  ; purple's
        lda light,x             ; c
        ldy _live + L3,x
        beq @noy
        ldy _live + 4 * NL + L3,x
        bne @both
        lda ly                  ; yellow only: c = sy
        jmp @set
@noy:   ldy _live + 4 * NL + L3,x
        beq @set
        lda lv                  ; purple only: c = !sv
        eor #1
        jmp @set
@both:  lda ly                  ; both: c = sy == sv ? flick : sy
        cmp lv
        bne @set
        lda flick
@set:   sta lc
        cmp light,x
        beq :+
        sta light,x
        txa
        jsr draw_light
:       lda lc
        clc
        adc ln
        sta ln
        inc lr
        lda lr
        cmp #NL
        bne @r
        lda ln                  ; more purple: 1, fewer: 0, as many: 2
        ldx #2
        cmp #NL / 2
        beq :+
        ldx #0
        bcc :+
        inx
:       cpx leader
        beq :+
        stx leader
        jmp draw_leader
:       rts

; put_in(): a pulse put in by side ts at its cursor; the player's lasts
; longer
put_in: ldx ts
        lda pulses,x
        beq @no
        lda cursor,x
        beq @no
        sec
        sbc #1
        sta tr                  ; r
        lda ts                  ; i = s * 4 * NL + r
        beq :+
        lda #4 * NL
:       clc
        adc tr
        tay
        lda _part,y
        cmp #DEAD
        beq @no
        lda _live,y
        bne @no
        dec pulses,x
        lda #AMP
        sta _part,y
        lda ts                  ; life[s * NL + r]: 80 the player's, 40
        beq :+
        lda #NL
:       clc
        adc tr
        tay
        lda #40
        cpx me
        bne :+
        lda #80
:       sta _life,y
        lda #0
        sta cursor,x
        lda tr
        jsr draw_line
        lda #1
        sta tv
        jsr draw_cursor
        jsr draw_pulses
        lda #SFX_PULSE
        jmp _sound
@no:    rts

; one tick of the board: pulses age, pass on, the lights follow
step:   lda #0
        sta ts
@s:     ldx #0
        ldy #0                  ; life[s * NL + r]
        lda ts
        beq :+
        ldy #NL
        ldx #4 * NL
:       stx tk                  ; part[s * 4 * NL + r]
        lda #NL
        sta tn
@r:     lda _life,y
        beq @n
        sec
        sbc #1
        sta _life,y
        bne @n
        ldx tk                  ; aged out: a wire again
        lda #WIRE
        sta _part,x
@n:     inc tk
        iny
        dec tn
        bne @r
        lda ts
        jsr _x_pass
        lda ts
        jsr _x_step
        ldx ts
        lda cursor,x
        beq :+
        lda #1
        sta tv
        jsr draw_cursor
:       inc ts
        lda ts
        cmp #2
        bne @s
        jmp lights

; A := 1 + rnd() % NL: a line
rnd_line:
        jsr _rnd
:       cmp #NL
        bcc :+
        sbc #NL
        bcs :-
:       clc
        adc #1
        rts

; enemy(): the other side, as the original plays it: a line picked at
; random, the cursor moved there a line every other tick, and a pulse put
; in
enemy:  ldx ts
        lda pulses,x
        beq @done
        lda cursor,x
        cmp target
        bne :+
        jsr put_in
        jsr rnd_line
        sta target
        rts
:       lda _tick
        and #1
        bne @done
        lda #0
        sta tv
        jsr draw_cursor
        ldx ts
        lda cursor,x
        cmp target
        bcc :+
        dec cursor,x
        jmp :++
:       inc cursor,x
:       lda #1
        sta tv
        jmp draw_cursor
@done:  rts

; a tick: three pictures on from the last one, not from here, so that
; the steps' own time does not add up (the game's ten seconds stay ten)
wait3 = _wait_tick

; ---- the introduction: both droids, as the original shows them ----

; unit(): droid type tt's screen in colour ta: its picture, what it is,
; and the lines at tl1, tl2
unit:   lda tt
        jsr pusha
        lda #12
        jsr pusha
        lda #2
        jsr _picture
        lda ta
        sta _x_attr
        lda #10
        sta _x_row
        lda #3
        sta _x_col
        lda #<s_unit
        ldx #>s_unit
        jsr _say
        ldx tt                  ; its number: class and two digits
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
        lda #<num
        ldx #>num
        jsr _say
        lda #<s_dash
        ldx #>s_dash
        jsr _say
        lda tt
        jsr _unit_name
        jsr _say
        lda #12
        sta _x_row
        lda #10
        sta _x_col
        lda #<s_this
        ldx #>s_this
        jsr _say
        lda #14
        sta _x_row
        lda #9
        sta _x_col
        lda tl1
        ldx tl1+1
        jsr _say
        lda #16
        sta _x_row
        lda #9
        sta _x_col
        lda tl2
        ldx tl2+1
        jsr _say
        lda #50                 ; two and a half seconds, or till fire
        sta tn
:       lda _keys_irq
        and #K_FIRE
        bne :+
        jsr wait3
        dec tn
        bne :-
:       lda _keys_irq
        and #K_FIRE
        beq :+
        jsr wait3
        jmp :-
:       rts

; intro(): both droids, the player's first
intro:  lda _ready
        bne intro
        jsr _eng_plain
        lda _col_deck
        sta tcd
        lda _pal_deck+1
        sta _col_deck
        lda #SFX_COMPLETE       ; as the original's, each
        jsr _sound
        lda _d_type
        sta tt
        lda _pal_deck+5
        sta ta
        lda #<s_curr
        sta tl1
        lda #>s_curr
        sta tl1+1
        lda #<s_none
        sta tl2
        lda #>s_none
        sta tl2+1
        jsr unit
        lda #SFX_REJECTED
        jsr _sound
        ldx ti
        lda _d_type,x
        sta tt
        lda _pal_deck+6
        sta ta
        lda #<s_wish
        sta tl1
        lda #>s_wish
        sta tl1+1
        lda #<s_trans
        sta tl2
        lda #>s_trans
        sta tl2+1
        jsr unit
        lda tcd
        jmp _page_end

; count(): the panel: the word at ptr1 and the count A, as the original's
; "Colour? 76" - always two digits, "Finish -00" at the end
count:  pha
        ldy #0
:       lda (ptr1),y
        beq :+
        sta text,y
        iny
        bne :-
:       pla
        ldx #$30
:       cmp #10
        bcc :+
        sbc #10
        inx
        bne :-
:       pha
        txa
        sta text,y
        iny
        pla
        ora #$30
        sta text,y
        iny
        lda #0
        sta text,y
        lda #<text
        ldx #>text
        jmp _panel_status

; transfer_game(i): the game against droid i: 1 if the player wins
_transfer_game:
        sta ti
        jsr intro
        ldx #NBOARD * 8 - 1     ; the board's characters
:       lda _board_font,x
        sta FONT0 + POOL * 8,x
        sta FONT1 + POOL * 8,x
        dex
        bpl :-
        jsr _eng_plain
        lda _pal_mc+7
        ora #8
        sta _tcol
        lda _pal_mc+4
        ora #8
        sta _tcol+1
        lda _pal_deck+0
        ora #8
        sta _blk
        lda _pal_deck+2         ; (the game's loop sets the deck's back,
        sta _col_deck           ; when it draws the deck again)
        ; both droids into the slots after this overlay (it is unpacked
        ; where theirs were): the player's in its colours
        lda #SLOT_PANIM + 1
        jsr pusha
        lda _d_type
        jsr pusha
        lda #1
        jsr _board_droid
        lda #SLOT_PANIM + 2
        jsr pusha
        ldx ti
        lda _d_type,x
        jsr pusha
        lda #0
        jsr _board_droid
@round: lda #0
        jsr _x_layout
        lda #1
        jsr _x_layout
        lda #0
        ldx #2 * 4 * NL - 1
:       sta _live,x
        dex
        bpl :-
        ldx #2 * NL - 1
:       sta _life,x
        dex
        bpl :-
        ldx #NL - 1
:       txa
        and #1
        sta light,x
        dex
        bpl :-
        lda #2
        sta leader
        lda #0
        sta me
        sta pulses
        sta pulses+1
        sta cursor
        sta cursor+1
        jsr board
        ; the player chooses a side, left yellow or right purple
:       lda _keys_irq
        and #K_FIRE
        beq :+
        jsr wait3
        jmp :-
:       lda #99
        sta tt
@side:  lda tt
        and #1
        bne :+
        lda #<s_colour
        sta ptr1
        lda #>s_colour
        sta ptr1+1
        lda tt
        jsr count
:       jsr wait3
        lda _keys_irq
        sta tk
        and #K_FIRE
        bne @chosen
        lda tk                  ; right purple, left yellow
        and #K_RIGHT
        beq :+
        lda #1
        bne :++
:       lda tk
        and #K_LEFT
        beq @same
        lda #0
:       cmp me
        beq @same
        sta me
        jsr draw_droids
@same:  dec tt
        bne @side
@chosen:
        ldx _d_type             ; pulses: the class and 3, the other's and 4
        lda _dr_class,x
        clc
        adc #3
        ldx me
        sta pulses,x
        ldx ti
        ldy _d_type,x
        lda _dr_class,y
        clc
        adc #4
        ldx me
        pha
        txa
        eor #1
        tax
        pla
        sta pulses,x
        jsr rnd_line
        sta target
        lda #0
        sta ts
:       jsr draw_pulses
        lda #1
        sta tv
        jsr draw_cursor
        inc ts
        lda ts
        cmp #2
        bne :-
        ; the game, ten seconds and the pulses' end
        lda _keys_irq
        sta tprev
        lda #0
        sta tt
@tick:  jsr wait3
        lda tt
        bne :+
        lda #SFX_FINISH
        jsr _sound
:       lda tt
        cmp #167
        bcc :+
        jmp @flow
:                               ; t % 3 == 0: "Finish" and the seconds
:       sec
        sbc #3
        bcs :-
        adc #3
        bne @keys
        lda #<s_finish
        sta ptr1
        lda #>s_finish
        sta ptr1+1
        lda #166                ; (166 - t) * 3 / 5
        sec
        sbc tt
        sta tn
        lda #0
        sta tr
        lda tn
        asl a
        rol tr
        clc
        adc tn
        sta tn
        lda tr
        adc #0
        sta tr
        ldx #0
:       lda tn
        sec
        sbc #5
        tay
        lda tr
        sbc #0
        bcc :+
        sta tr
        sty tn
        inx
        bne :-
:       txa
        jsr count
@keys:  lda _keys_irq
        sta tk
        lda me
        sta ts
        lda tk                  ; up: the line above, round to the last
        and #K_UP
        beq @down
        lda tprev
        and #K_UP
        bne @down
        lda #0
        sta tv
        jsr draw_cursor
        ldx me
        lda cursor,x
        cmp #2
        bcs :+
        lda #NL + 1
:       sec
        sbc #1
        sta cursor,x
        lda #1
        sta tv
        jsr draw_cursor
@down:  lda tk                  ; down: the line below, round to the first
        and #K_DOWN
        beq @put
        lda tprev
        and #K_DOWN
        bne @put
        lda #0
        sta tv
        jsr draw_cursor
        ldx me
        lda cursor,x
        cmp #NL
        bcc :+
        lda #0
:       clc
        adc #1
        sta cursor,x
        lda #1
        sta tv
        jsr draw_cursor
@put:   lda tk                  ; fire: a pulse in
        and #K_FIRE
        beq :+
        lda tprev
        and #K_FIRE
        bne :+
        jsr put_in
:       lda tk
        sta tprev
        lda me
        eor #1
        sta ts
        jsr enemy
@flow:  lda tt
        and #1
        bne :+
        jsr _x_flow
:       jsr step
        inc tt
        lda tt
        cmp #167 + 40
        beq :+
        jmp @tick
:       lda leader
        cmp #2
        bne @over
        lda #<s_dead
        ldx #>s_dead
        jsr _panel_status
        lda #SFX_DEADLOCK
        jsr _sound
        lda #30
        sta tt
:       jsr wait3
        dec tt
        bne :-
        jmp @round
@over:  ldx #0
        lda leader
        cmp me
        bne :+
        inx
:       txa
        rts
