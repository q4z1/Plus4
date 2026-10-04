; draw.s - the picture: the window onto the deck, the figures in it, and
; the status panel above
;
; In assembly, as all of the game, to make room: everything the game
; keeps is in the program. Its code and tables run at $F400 on (HICODE, with
; figs.s), copied there at the start.

        .export _pictures_fixed, _player_picture, _board_droid, _pictures_deck
        .export _draw, _panel_code, _panel_status, _num_text, _panel_score
        .export _win_clear, _win_put
        .export _slot_of, _tick, _hide_player, _num_len
        .export _wp_row, _wp_col, _wp_code, _wp_attr

        .import _pre_shift, _pre, _r_begin, _r_done, _figure, _draw_figs
        .import _ready, _e_sx, _e_m0, _e_s, _e_r, _e_blank7, _e_cutrow, _e_cutn
        .import _f_h, _f_tint, _explo_col, _panel_put, _pp_off, _pp_code, _pp_attr
        .import _d_x, _d_y, _d_type, _d_boom, _d_energy, _nd, _transfer_mode
        .import _score, _score_changed
        .import _droid_tmpl, _digit_bits, _fixed_pk, _unpack, _unp_dst
        .import _dr_class, _dr_num
        .import popa
        .importzp _f_src, _p_pre, _org_x, _org_y, _fig_x, _fig_y, _fig_n
        .importzp sreg, ptr1

        .include "game.inc"
        .include "data.inc"

PANEL_TEXT  = $3B               ; the panel's red

        .bss
_slot_of:       .res NDROIDS    ; each type's slot on this deck, 255 none
_tick:          .res 1
_hide_player:   .res 1          ; the title: droids only
_num_len:       .res 1
_wp_row:        .res 1          ; win_put()'s cell
_wp_col:        .res 1
_wp_code:       .res 1
_wp_attr:       .res 1
pimg:   .res DROID_H * 4        ; a droid's picture being made
base:   .res DROID_H * 4        ; the player's, its colours swapped
num_buf:.res 8
dn:     .res 1                  ; a slot
dt:     .res 1                  ; a type
dk:     .res 1
dy:     .res 1
dx:     .res 1
bits:   .res 2
pcol:   .res 1                  ; panel_char()'s
pch:    .res 1
pf:     .res 1                  ; player_picture()'s turn
wl:     .res 2                  ; world pixel at the window's corner
wt:     .res 2
n32:    .res 4                  ; num_text()'s number
nd_:    .res 1                  ; a digit's count

        .segment "HICODE"
; a multicolour pixel's place in its byte: kept, and set to %10
px_and: .byte $3F, $CF, $F3, $FC
px_or2: .byte $80, $20, $08, $02
; num_text()'s powers of ten, low byte first
pow10:  .dword 1000000, 100000, 10000, 1000, 100, 10

        .segment "HICODE"

; ======================================================================
; Pictures, shifted in advance
;
; engine.s draws a figure from a copy shifted for each of the four
; multicolour pixels it can start at inside a cell (512 bytes, a slot).
; Explosions and lasers are made once; the droids when a deck is entered,
; for the types on it; the player's when he changes host.
; ======================================================================

; shift_into: A/X's picture, 16 lines, into slot dn
shift_pimg:
        lda #<pimg
        ldx #>pimg
shift_into:
        sta _f_src
        stx _f_src+1
        lda #16
        sta _f_h
        lda #<_pre
        sta _p_pre
        lda dn
        asl a
        adc #>_pre
        sta _p_pre+1
        jmp _pre_shift

; pictures_fixed(): the explosions' and lasers' slots, from their pictures
; kept packed, unpacked into the last two slots first (the player's dome's:
; pictures_deck() makes them after this)
FIXED   = _pre + 21 * 512
_pictures_fixed:
        lda #<FIXED
        sta _unp_dst
        lda #>FIXED
        sta _unp_dst+1
        lda #<_fixed_pk
        ldx #>_fixed_pk
        jsr _unpack
        lda #SLOT_EXPLO         ; the explosion's six, the lasers' four:
        sta dn                  ; | / - \, one after the other
        lda #<FIXED
        sta bits
        lda #>FIXED
        sta bits+1
@e:     lda bits
        ldx bits+1
        jsr shift_into
        lda bits
        clc
        adc #64
        sta bits
        bcc :+
        inc bits+1
:       inc dn
        lda dn
        cmp #SLOT_LASER + 4
        bne @e
        rts

; droid_picture(A): type A's picture into pimg: the template with its
; number in the band, light digits on the dark body
droid_picture:
        tay
        ldx #DROID_H * 4 - 1
:       lda _droid_tmpl,x
        sta pimg,x
        dex
        bpl :-
        lda _dr_num,y           ; its number's tens and ones
        ldx #0
:       cmp #10
        bcc :+
        sbc #10
        inx
        bne :-
:       sta dt                  ; (ones)
        stx dk                  ; (tens)
        lda _dr_class,y         ; the digits, left to right: class, tens,
        ldx #1                  ; ones, at pixels 1, 5, 9
        jsr digit
        lda dk
        ldx #5
        jsr digit
        lda dt
        ldx #9
; digit A at pixel column X of lines 5 to 9
digit:  stx dx
        asl a
        tay
        lda _digit_bits,y
        sta bits
        lda _digit_bits+1,y
        sta bits+1
        lda #5 * 4              ; line 5's first byte
        sta dy
@line:  ldx #3
        lda dx
        sta pch
@px:    lsr bits+1
        ror bits
        bcc @next
        lda pch                 ; pimg[dy + px / 4]: %10 at px & 3
        lsr a
        lsr a
        clc
        adc dy
        tay
        lda pch
        and #3
        sty pcol
        tay
        lda px_or2,y
        sta n32
        lda px_and,y
        ldy pcol
        and pimg,y
        ora n32
        sta pimg,y
@next:  inc pch
        dex
        bne @px
        lda dy
        clc
        adc #4
        sta dy
        cmp #10 * 4
        bne @line
        rts

; clear_px: pixel dx of line A made see-through
clear_px:
        asl a
        asl a
        sta dy
        lda dx
        lsr a
        lsr a
        clc
        adc dy
        tay
        lda dx
        and #3
        tax
        lda pimg,y
        and px_and,x
        sta pimg,y
        rts

; pimg's two colours swapped (the player's)
swap:   ldx #DROID_H * 4 - 1
:       lda pimg,x
        and #$55
        asl a
        sta dy
        lda pimg,x
        and #$AA
        lsr a
        ora dy
        sta pimg,x
        dex
        bpl :-
        rts

; player_picture(): the player's droid: the same picture with its two
; colours swapped, in four turns of its domes. As in the original
; (measured in x64sc): a slanted gap, its top to the right, runs round them
; from left to right, a hires pixel a tick over eight; here a multicolour
; pixel every two ticks over four (it went two at a time before, twice as
; fast)
_player_picture:
        lda _d_type
        jsr droid_picture
        jsr swap
        ldx #DROID_H * 4 - 1
:       lda pimg,x
        sta base,x
        dex
        bpl :-
        lda #0
        sta pf
@turn:  ldx #DROID_H * 4 - 1
:       lda base,x
        sta pimg,x
        dex
        bpl :-
        lda pf                  ; the gap at 4 + turn, three lines a dome
        clc
        adc #5
        sta dx
        lda #0
        sta dk
@r:     lda dk
        jsr clear_px
        lda #14
        sec
        sbc dk
        jsr clear_px
        dec dx
        inc dk
        lda dk
        cmp #3
        bne @r
        ldx pf                  ; turn 0 the player's slot, then the dome's
        beq :+
        txa
        clc
        adc #SLOT_PANIM - 1
        tax
:       stx dn
        jsr shift_pimg
        inc pf
        lda pf
        cmp #4
        bne @turn
        rts

; board_droid(n, t, p): droid type t into slot n, the player's colours if
; p: the transfer's board shows the two droids from slots its overlay
; leaves alone
_board_droid:
        sta pf                  ; p (droid_picture() takes dt and dk)
        jsr popa
        sta dt                  ; t
        jsr popa
        sta dn                  ; n
        lda dt
        jsr droid_picture
        lda pf
        beq :+
        jsr swap
:       jmp shift_pimg

; pictures_deck(): the player's and the deck's droid types' slots
_pictures_deck:
        lda #255
        ldx #NDROIDS - 1
:       sta _slot_of,x
        dex
        bpl :-
        jsr _player_picture
        lda #SLOT_DROID
        sta dn
        lda #1
        sta pf
@i:     ldx pf
        cpx _nd
        bcs @done
        lda dn
        cmp #SLOT_DROID + NSLOT_DROID
        bcs @done
        ldy _d_type,x
        lda _slot_of,y
        cmp #255
        bne @next
        lda dn
        sta _slot_of,y
        tya
        jsr droid_picture
        jsr shift_pimg
        inc dn
@next:  inc pf
        bne @i
@done:  rts

; ======================================================================
; The window onto the deck
; ======================================================================

; window(): across in steps of two: the figures are of multicolour pixels,
; two wide, and with the window on every pixel the player would shake by
; one. In step with the player's figure (its left edge at PX - 13), it
; stands still in the middle, as the original's sprite does. The deck a
; character up and left of where the player's coordinates put it, as the
; original draws it (measured against its screen): its player's sprite
; stands a character down and right of its droids' for the same place.
window:
        lda _d_x                ; win_l = ((PX + 1) & ~1) - 153 + 8
        clc
        adc #1
        and #$FE
        tay
        lda _d_x+1
        adc #0
        tax
        tya
        sec
        sbc #145
        sta wl
        txa
        sbc #0
        sta wl+1
        lda _d_y                ; win_t = PY - 56 + 8
        sec
        sbc #48
        sta wt
        lda _d_y+1
        sbc #0
        sta wt+1
        lda #0                  ; e_sx = -win_l & 7
        sec
        sbc wl
        and #7
        sta _e_sx
        clc                     ; win_l + e_sx, a whole character
        adc wl
        sta wl
        bcc :+
        inc wl+1
:       lsr a                   ; e_m0: its character, less one
        lsr a
        lsr a
        sta dk
        lda wl+1
        asl a
        asl a
        asl a
        asl a
        asl a
        ora dk
        sec
        sbc #1
        sta _e_m0
        lda wl                  ; org_x = win_l + e_sx - 8 - 64
        sec
        sbc #72
        sta _org_x
        lda wl+1
        sbc #0
        sta _org_x+1
        lda #0                  ; rows under the gap move down by k: window
        sec                     ; row 0 (screen row 7) shows its last k
        sbc wt                  ; lines at the window's top, or nothing
        and #7
        sta _e_s
        tay
        clc
        adc wt
        sta wt
        bcc :+
        inc wt+1
:       lsr a                   ; r0: the row, less one
        lsr a
        lsr a
        sta dk
        lda wt+1
        asl a
        asl a
        asl a
        asl a
        asl a
        ora dk
        sec
        sbc #1
        sta _e_r
        ldx #0                  ; org_y = r0 * 8 - 64, r0 signed
        cmp #$80
        bcc :+
        dex
:       stx _org_y+1
        asl a
        rol _org_y+1
        asl a
        rol _org_y+1
        asl a
        rol _org_y+1
        sec
        sbc #64
        sta _org_y
        bcs :+
        dec _org_y+1
:       lda #0                  ; e_blank7: k == 0; e_cutrow: k != 0;
        cpy #0                  ; e_cutn: 8 - k
        bne :+
        lda #1
:       sta _e_blank7
        eor #1
        sta _e_cutrow
        tya
        eor #$FF
        sec
        adc #8
        sta _e_cutn
        rts

; draw(): the window, the droids, their explosions and the shots
; (figs.s), and the player's figure
_draw:  jsr window
:       lda _ready
        bne :-
        jsr _r_begin
        jsr _draw_figs
        lda _d_x                ; (see window())
        sec
        sbc #5
        sta _fig_x
        lda _d_x+1
        sbc #0
        sta _fig_x+1
        lda _d_y
        sta _fig_y
        lda _d_y+1
        sta _fig_y+1
        lda _d_boom
        beq @alive
        cmp #BOOM_GONE
        bcs @done
        sec
        sbc #1
        lsr a
        tay
        clc
        adc #SLOT_EXPLO
        sta _fig_n
        lda _explo_col,y
        sta _f_tint
        jsr _figure
        lda #0
        sta _f_tint
        beq @done
@alive: lda _hide_player
        bne @done
        lda _transfer_mode      ; blinking in transfer mode,
        beq :+
        lda _tick
        and #2
        beq @done
:       lda _d_energy           ; and with little energy
        cmp #64 / 4
        bcs :+
        lda _tick
        and #4
        beq @done
:       lda _tick               ; a turn in eight ticks, as there
        lsr a
        and #3
        beq :+
        clc
        adc #SLOT_PANIM - 1
:       sta _fig_n
        jsr _figure
@done:  jmp _r_done

; ======================================================================
; The status panel
; ======================================================================

; panel_char: character pch at column pcol, its top and its bottom (+128)
panel_char:
        lda #PANEL_TEXT
        sta _pp_attr
        lda #0
        sta _pp_off+1
        lda pcol
        clc
        adc #80
        sta _pp_off
        lda pch
        sta _pp_code
        jsr _panel_put
        lda pcol
        clc
        adc #120
        sta _pp_off
        lda #0
        sta _pp_off+1
        lda pch
        ora #$80
        sta _pp_code
        jmp _panel_put

; panel_code(ch): a character as the panel's letters have it: its top's
; code (the bottom is code + 128); from $3A on a letter is two wide, code
; and code + $20. (PETSCII: a-z $41-$5A, A-Z $C1-$DA)
_panel_code:
        ldx #0
        cmp #$30                ; 0-9
        bcc @misc
        cmp #$3A
        bcs :+
        sbc #$30 - 1            ; (carry clear)
        rts
:       cmp #$4D                ; m
        bne :+
        lda #$42
        rts
:       cmp #$57                ; w
        bne :+
        lda #$54
        rts
:       cmp #$41                ; a-z
        bcc @misc
        cmp #$5B
        bcs :+
        sbc #$41 - 10 - 1
        rts
:       cmp #$C9                ; I
        bne :+
        lda #$16
        rts
:       cmp #$C1                ; A-Z
        bcc @misc
        cmp #$DB
        bcs @misc
        sbc #$C1 - $3A - 1
        rts
@misc:  ldy #6
:       cmp misc_ch,y
        beq :+
        dey
        bpl :-
        lda #$30                ; space
        rts
:       lda misc_code,y
        rts

        .segment "HICODE"
misc_ch:    .byte $3F, $2D, $2E, $2C, $3A, $27, $21   ; ? - . , : ' !
misc_code:  .byte $24, $2E, $28, $29, $2A, $2D, $25
        .segment "HICODE"

; panel_text: the text at ptr1 from column pcol on, pcol after it
panel_text:
        ldy #0
        sty dk
@c:     ldy dk
        lda (ptr1),y
        beq @done
        inc dk
        jsr _panel_code
        sta pch
        jsr panel_char
        inc pcol
        lda pch
        cmp #$3A
        bcc @c
        clc
        adc #$20
        sta pch
        jsr panel_char
        inc pcol
        bne @c
@done:  rts

; panel_status(s): the status, padded with spaces to column 13
_panel_status:
        sta ptr1
        stx ptr1+1
        lda #2
        sta pcol
        jsr panel_text
        lda #$30
        sta pch
:       lda pcol
        cmp #13
        bcs @done
        jsr panel_char
        inc pcol
        bne :-
@done:  rts

; num_text(v): a number as text, up to seven digits; num_len its length
_num_text:
        sta n32
        stx n32+1
        lda sreg
        sta n32+2
        lda sreg+1
        sta n32+3
num:    ldy #0                  ; digits so far
        ldx #0                  ; the power
@pow:   lda #0
        sta nd_
@sub:   lda n32                 ; take it off as often as it goes
        sec
        sbc pow10,x
        sta bits
        lda n32+1
        sbc pow10+1,x
        sta bits+1
        lda n32+2
        sbc pow10+2,x
        sta pch
        lda n32+3
        sbc pow10+3,x
        bcc @digit
        sta n32+3
        lda pch
        sta n32+2
        lda bits+1
        sta n32+1
        lda bits
        sta n32
        inc nd_
        bne @sub
@digit: lda nd_                 ; no leading zeros
        bne :+
        cpy #0
        beq @skip
:       ora #$30
        sta num_buf,y
        iny
@skip:  inx
        inx
        inx
        inx
        cpx #6 * 4
        bne @pow
        lda n32                 ; the ones, always
        ora #$30
        sta num_buf,y
        iny
        sty _num_len
        lda #0
        sta num_buf,y
        lda #<num_buf
        ldx #>num_buf
        rts

; panel_score(): the score at the panel's right, spaces before it
_panel_score:
        ldx #3
:       lda _score,x
        sta n32,x
        dex
        bpl :-
        jsr num
        sta ptr1
        stx ptr1+1
        lda #38
        sec
        sbc _num_len
        sta dn
        lda #$30
        sta pch
        lda #30
        sta pcol
:       lda pcol
        cmp dn
        bcs :+
        jsr panel_char
        inc pcol
        bne :-
:       jsr panel_text
        lda #0
        sta _score_changed
        rts

; ======================================================================
; Screens drawn straight into the window (lift, console, transfer)
; ======================================================================

; win_clear(code, attr): the window rows (screen rows 9 to 24) of both
; pictures cleared
_win_clear:
        sta dk                  ; attr
        jsr popa                ; code
        ldy #160
:       dey
        sta SCR0C + 360,y
        sta SCR0C + 520,y
        sta SCR0C + 680,y
        sta SCR0C + 840,y
        sta SCR1C + 360,y
        sta SCR1C + 520,y
        sta SCR1C + 680,y
        sta SCR1C + 840,y
        bne :-
        lda dk
        ldy #160
:       dey
        sta SCR0A + 360,y
        sta SCR0A + 520,y
        sta SCR0A + 680,y
        sta SCR0A + 840,y
        sta SCR1A + 360,y
        sta SCR1A + 520,y
        sta SCR1A + 680,y
        sta SCR1A + 840,y
        bne :-
        rts

; win_put(): a cell of both pictures, from wp_row, wp_col, wp_code,
; wp_attr
_win_put:
        lda #0
        sta ptr1+1
        lda _wp_row             ; row * 40
        asl a
        asl a
        adc _wp_row
        asl a
        asl a
        rol ptr1+1
        asl a
        rol ptr1+1
        adc _wp_col
        sta ptr1
        bcc :+
        inc ptr1+1
:       ldy #0
        lda ptr1+1
        pha
        ora #>SCR0C
        sta ptr1+1
        lda _wp_code
        sta (ptr1),y
        lda ptr1+1
        eor #>SCR0C ^ >SCR1C
        sta ptr1+1
        lda _wp_code
        sta (ptr1),y
        pla
        pha
        ora #>SCR0A
        sta ptr1+1
        lda _wp_attr
        sta (ptr1),y
        pla
        ora #>SCR1A
        sta ptr1+1
        lda _wp_attr
        sta (ptr1),y
        rts
