; paradroid.s - Paradroid for the Plus/4: start, the game's course
;
; After Paradroid by Andrew Braybrook (Graftgold, published by Hewson,
; 1985). The decks, their blocks and characters, the droid types, the
; waypoints the droids walk and the lifts are the original's, taken from
; its memory (tools/extract.py); the program around them is new.
;
; The game runs in ticks of three pictures, as the original does: 16.7 a
; second. Everything moves once a tick and a new picture is drawn.
;
; All of it is assembly, to make room: everything the game keeps is in
; the program.
;
; Files:
;   paradroid.s  (this file) start, the main loop, a game's end
;   deck.s       the ship, decks, doors
;   droids.s     the player, droids, shots, energy
;   move.s       driving, walls, doors, the decks' colours
;   draw.s       the picture and the status panel (at $F300)
;   figs.s       the figures in the window (at $F300)
;   picture.s    the droids' pictures and the panel's letters
;   engine.s     what has to be fast or on time: the interrupt, the window
;   sfx.s        the sound effects' player (at $FC00); sfxcall.s starts them
;   startup.s    the start: everything into its place, once
;   unpack.s     unpacking what is kept packed (exodecrunch.s)
;   game.inc     what they share; build/gen/data.inc what the data says
; The overlays, kept packed and unpacked into the pictures' slots:
;   screens.s    the console and the lift
;   transfer.s   the transfer game, with xfer.s (its board)
;   title.s      the title, with briefrows.s and music.s; the day's scores

        .export _main, _wait_tick, _page_end, _mc_font
        .export _ticks, _late, _top_score, _low_score, _initials, last
        .export s_colour, s_bw
        .forceimport __STARTUP__        ; (cc65's start-up: main() is here)

        .import _frames, _ready, _keys_irq, _tick, _font_hi, _col_deck, _col_fig2
        .import _eng_stack, _eng_plain, _eng_show, _start_up, _beam_in
        .import _load_deck, _spawn_droids, _pictures_deck, _pictures_fixed
        .import _deck_colours, _deck_cleared, _ship_cleared, _new_ship, _rnd
        .import _lift_here, _player_spot, _lift_deck, _lift_bx, _lift_by
        .import _transfer_game, _ride_lift, _console_run, _title_run, _title_scores
        .import _take_over, _transfer_lost, _burnt_out, _sound
        .import _panel_status, _panel_score, _win_clear, _picture, _say
        .import _sfx_tick, _move_player, _move_droids, _doors, _fig_place
        .import _player_fire, _droids_fire, _move_shots, _collide, _energy_tick
        .import _sight
        .import _anim_deck, _turn_droids, _draw, _pause_keys, _bw, _col_border, _panel_frame
        .import _keep_border
        .import _unpack, _unp_dst, _blob_title, _blob_con, _blob_xfer
        .import __OVL_START__, __CONOVL_START__, __XFEROVL_START__
        .import _d_x, _d_y, _d_vx, _d_vy, _d_type, _d_energy, _d_boom
        .import _deck, _level, _score, _alert, _alert_acc, _player_dead, _burn
        .import _transfer_mode, _touched, _score_changed, _flash, _deck_bg
        .import _hide_player, _wp_first, _wp_x, _wp_y, _pal_deck, _anim_s
        .import _roll, _pic_late, _pic_until, _x_attr, _x_row, _x_col
        .import pusha
        .importzp _snd_len, ptr1, ptr2

        .include "game.inc"
        .include "data.inc"

        .data
; the day's top and worst scores and their initials (title.s takes and
; shows them); the original starts with these
_top_score:     .dword 6809
_low_score:     .dword 6502
_initials:      .byte 0, 4, 1, 19, 18, 14   ; A-Z 0-25, 26 a space: AEB, TSO

        .bss
_ticks:     .res 2              ; for measuring: ticks done,
_late:      .res 2              ; and ticks that came too late
last:       .res 1              ; frames at the last tick
over:       .res 1              ; a game has been played
lights_out: .res 1              ; this deck went dark already
held:       .res 1              ; ticks fire is held on a lift or console
fstate:     .res 1              ; fire's state (play())
ftimer:     .res 1              ; its wait
keys:       .res 1
wf:         .res 1              ; wait_free()'s keys
pf:         .res 1              ; the pause's keys
li:         .res 1
ti:         .res 1              ; transfer()'s droid
cd:         .res 1
en_d:       .res 1              ; enter()'s deck and block
en_bx:      .res 1
en_by:      .res 1
cnt:        .res 2

        .rodata
s_mobile:   .byte "Mobile", 0
s_transfer: .byte "Transfer", 0
s_weapon:   .byte "Weapon", 0
s_pause:    .byte "Pause", 0
s_cheese:   .byte "Cheese", 0
s_colour:   .byte "Colour", 0
s_bw:       .byte "Blk-White", 0
s_continue: .byte "Continue", 0
s_fleet:    .byte "Fleet", 0
s_cleared:  .byte "Cleared", 0
s_gameover: .byte "Game over", 0
        .segment "SFXCODE"      ; (run at $FC00 on, after the effects'
                                ; player, copied there at the start: its
                                ; load image costs the program nothing)
s_complete: .byte "Complete", 0
s_rejected: .byte "Rejected", 0
s_burnt:    .byte "Burnt Out", 0
        .rodata
mc_mask:    .byte $C0, $30, $0C, $03

        .code

; status: the panel's status, the text at A/X
status = _panel_status

; wait_tick(): wait for the next tick: one every three pictures; one that
; took longer is made up by the next, unless it is far behind
_wait_tick:
        lda _frames
        sec
        sbc last
        cmp #4
        bcc @wait
        inc _late
        bne @wait
        inc _late+1
@wait:  lda _frames
        sec
        sbc last
        cmp #3
        bcc @wait
        lda last
        clc
        adc #3
        sta last
        lda _frames
        sec
        sbc last
        cmp #7
        bcc :+
        lda _frames
        sta last
:       inc _ticks
        bne :+
        inc _ticks+1
:       inc _tick
        rts

; wait_free(A): ticks till none of the keys A is down
wait_free:
        sta wf
:       lda _keys_irq
        and wf
        beq :+
        jsr _wait_tick
        jmp :-
:       rts

; wait_ready: till the picture drawn last is shown
wait_ready:
        lda _ready
        bne wait_ready
        rts

; enter(): deck en_d, the player on block en_bx, en_by
enter:  lda en_d
        jsr _load_deck
        jsr _spawn_droids
        jsr _pictures_deck
        jsr _deck_colours
        lda en_bx               ; block * 32 + 16
        jsr @at
        sta _d_x
        stx _d_x+1
        lda en_by
        jsr @at
        sta _d_y
        stx _d_y+1
        lda #0
        sta _d_vx
        sta _d_vy
        rts
@at:    ldx #0
        stx cnt
        ldy #5
:       asl a
        rol cnt
        dey
        bne :-
        clc
        adc #16
        pha
        lda cnt
        adc #0
        tax
        pla
        rts

; the score plus A/X
add_score:
        clc
        adc _score
        sta _score
        txa
        adc _score+1
        sta _score+1
        bcc :+
        inc _score+2
        bne :+
        inc _score+3
:       rts

; ======================================================================
; The overlays (screens.s, transfer.s, title.s): kept packed,
; unpacked into the pictures' slots, which are made again afterwards
; ======================================================================

slots_again:
        jsr _pictures_fixed     ; (first: it unpacks into the player's)
        jmp _pictures_deck

; the console and lift's
screens:
        lda #<__CONOVL_START__
        sta _unp_dst
        lda #>__CONOVL_START__
        sta _unp_dst+1
        lda #<_blob_con
        ldx #>_blob_con
        jmp _unpack

console:
        jsr screens
        jsr _console_run
        jmp slots_again

; lift(A): the lift A, and out where the player gets out: another deck
; is entered (which unpacks into the slots, so not from the lift's code)
lift:   sta li
        jsr screens
        lda li
        jsr _ride_lift
        tax
        lda _lift_deck,x
        cmp _deck
        beq @same
        sta en_d
        lda _lift_bx,x
        sta en_bx
        lda _lift_by,x
        sta en_by
        inc _keep_border        ; the new deck's border and panel frame
        jsr enter               ; only as the deck shows: the side view
        dec _keep_border        ; stays up while the slots are made, a
        jsr slots_again         ; second
        jsr _draw
        jsr wait_ready
        lda _deck_bg            ; (the next picture's colours: the
        sta _col_deck           ; interrupt has just swapped)
        lda CLS_HR+3            ; (deck_colours()'s border)
        sta _col_border
        jsr _panel_frame
        jmp :+
@same:  jsr slots_again
:       lda #<s_mobile
        ldx #>s_mobile
        jmp status

; transfer(A): the transfer game against droid A, and what follows
transfer:
        sta ti
        jsr wait_ready
        lda #<__XFEROVL_START__
        sta _unp_dst
        lda #>__XFEROVL_START__
        sta _unp_dst+1
        lda #<_blob_xfer
        ldx #>_blob_xfer
        jsr _unpack
        lda ti
        jsr _transfer_game
        cmp #0
        beq @lost
        lda #SFX_COMPLETE
        jsr _sound
        lda ti
        jsr _take_over
        lda #<s_complete
        ldx #>s_complete
        jsr status
        jmp @end
@lost:  lda _d_type
        beq @burnt
        lda #SFX_REJECTED
        jsr _sound
        jsr _transfer_lost
        lda #<s_rejected
        ldx #>s_rejected
        jsr status
        jmp @end
@burnt: lda #<s_burnt
        ldx #>s_burnt
        jsr status
        lda #SFX_BURNT
        jsr _sound
        jsr _burnt_out
@end:   lda #0
        sta _transfer_mode
        jsr slots_again
        lda #K_FIRE
        jmp wait_free

; ======================================================================
; A game
; ======================================================================

new_game:
        lda #1
        sta _level
        lda #0
        ldx #3
:       sta _score,x
        dex
        bpl :-
        sta _alert
        sta _player_dead
        jsr _new_ship
        lda #0
        sta _d_type
        lda #64
        sta _d_energy
        sta _burn
        lda #0
        sta _alert_acc
        jsr _rnd                ; a deck between 4 and 7, as the original
        and #3                  ; starts, on its first waypoint (the
        clc                     ; droids start on the ones after)
        adc #4
        sta en_d
        lda #0
        sta en_bx
        sta en_by
        jsr enter
        ldx en_d
        ldy _wp_first,x
        lda #0
        sta cnt
        lda _wp_x,y
        asl a
        rol cnt
        asl a
        rol cnt
        asl a
        rol cnt
        sta _d_x
        lda cnt
        sta _d_x+1
        lda #0
        sta cnt
        lda _wp_y,y
        asl a
        rol cnt
        asl a
        rol cnt
        asl a
        rol cnt
        sta _d_y
        lda cnt
        sta _d_y+1
        jmp _panel_score

; the ship is clear: on to the next of the fleet, droids a class higher
next_ship:
        lda _level              ; (no more than 8, as the original's $67)
        cmp #8
        bcs :+
        inc _level
:
        jsr _new_ship
        lda #50
        sta cnt
:       jsr _wait_tick
        dec cnt
        bne :-
        lda #0
        sta lights_out
        jsr _spawn_droids
        jsr _pictures_deck
        jsr _deck_colours
        lda #<s_mobile
        ldx #>s_mobile
        jmp status

; pause(): the pause, as the original's ($3B7C): RUN/STOP, and all stands
; still and is quiet but the deck's turning characters and the droids'
; turning domes (here all droids of a type turn together), till fire or
; RUN/STOP. In it, as its briefing says: CLR/HOME ends the game (A 1:
; straight to the title); "Cheese": not even those turn, till fire,
; RUN/STOP, CLR/HOME or the key back to the pause. And, not in the
; original's briefing, colours or black and white (the deck's scheme 0,
; from the pause's end on). The original has them on the C64's F1/F2 and
; F7/F8, two of them with shift; here they are the Plus/4's four keys
; without it: F1 colours, F2 black and white, F3 Cheese, HELP the pause.
pause:  lda #<s_pause
        ldx #>s_pause
        jsr status
        lda #1                  ; (both voices off at once)
        sta _snd_len
        sta _snd_len+1
        lda #K_STOP
        jsr wait_free
@loop:  lda _keys_irq
        and #K_STOP | K_FIRE
        bne @end
        jsr _wait_tick
        jsr _pause_keys
        sta pf
        lsr a
        bcc :+
        lda #1                  ; CLR/HOME
        rts
:       lda pf
        and #16
        beq @f1
        lda #<s_cheese          ; F3
        ldx #>s_cheese
        jsr status
@ch:    jsr _wait_tick          ; (the keys once a tick, as the pause: read
        lda _keys_irq           ; all the time, their reading held off the
        and #K_STOP | K_FIRE    ; interrupt, and the window's top line
        bne @chend              ; flickered)
        jsr _pause_keys
        sta pf
        and #1 | 2              ; CLR/HOME, HELP
        beq @ch
@chend: lda #<s_pause
        ldx #>s_pause
        jsr status
@f1:    lda pf
        and #4 | 8
        beq @anim
        and #8                  ; F1, F2
        sta _bw
        bne :+
        lda #<s_colour
        ldx #>s_colour
        jsr status
        jmp @anim
:       lda #<s_bw
        ldx #>s_bw
        jsr status
@anim:  jsr _anim_deck
        jsr _draw
        jsr _turn_droids        ; (the domes turning)
        jmp @loop
@end:   lda #K_STOP | K_FIRE
        jsr wait_free
        jsr _deck_colours
        lda #<s_continue
        ldx #>s_continue
        jsr status
        lda #0
        rts

; play_init(): fire in none of its states
        .segment "LOWEND"       ; (at $0FEB on, copied there at the start)
play_init:
        lda #$80
        sta fstate
        lda #0
        sta held
        rts
        .code

; play(): a game, till the player is gone
play:   jsr play_init
        lda _deck
        jsr _deck_cleared
        sta lights_out
@tick:  jsr _wait_tick
        lda _keys_irq
        sta keys
        and #K_STOP
        beq @go
        jsr pause
        beq @tick
        lda #0                  ; (no end of a game shown)
        sta over
        rts
@go:    lda _player_dead
        beq @fire
        lda _d_boom
        cmp #BOOM_GONE
        bcc :+
        rts
:       inc _d_boom
        lda #0
        sta keys
; fire, as the original's ($31B9, $3A): pressed with a direction, the
; weapon, which fires while fire stays held, whichever way the stick goes;
; pressed without one, a wait of 8 ticks (half a second): a direction in
; it, the weapon still (fire let go by then: one shot); none, transfer
; mode, till fire is let go. The droid drives all the while.
@fire:  lda fstate
        bmi @st80               ; $80: none
        cmp #2
        beq @st2                ; 2: the wait
        lda keys                ; 1, the weapon, and 0, transfer mode:
        and #K_FIRE             ; till fire is let go
        bne @lc
@mob:   lda #$80
        sta fstate
        lda #0
        sta _transfer_mode
        lda #<s_mobile
        ldx #>s_mobile
        jsr status
        jmp @lc
@st80:  lda keys
        and #K_FIRE
        beq @lc
        lda #2
        sta fstate
        lda #9                  ; (8 after this tick, as there: transfer
        sta ftimer              ; mode in fire's ninth tick)
@st2:   lda keys
        and #K_DIRS
        beq @wait
        lda #1
        sta fstate
        lda #<s_weapon
        ldx #>s_weapon
        jsr status
        jmp @lc
@wait:  dec ftimer
        bne @lc
        lda #0
        sta fstate
        lda #1
        sta _transfer_mode
        lda #<s_transfer
        ldx #>s_transfer
        jsr status
; a lift or a console, fire held on it for 5 ticks in any of those states
; (the original's $2E7B)
@lc:    lda fstate
        bmi @nolc
        jsr _player_spot        ; (on the character itself, not its block:
        beq @nolc               ; driven over with fire held, nothing)
        lda held
        cmp #4
        bne @held
        jsr _lift_here
        cmp #255
        beq @cons
        jsr lift
        lda _deck
        jsr _deck_cleared
        sta lights_out
        jmp @again
@cons:  jsr console
@again: jsr play_init
        jmp @tick
@held:  inc held
        bne @move
@nolc:  lda #0
        sta held
@move:  jsr _sfx_tick           ; the original's own: hum, warning
        lda keys
        jsr _move_player
        jsr _move_droids
        jsr _doors
        lda #8                  ; figures against figures: the player where
        jsr _fig_place          ; its figure is, a character right of and
        lda keys                ; below its place (draw.s), as the
        and #<~K_FIRE           ; original's sprites meet; fired in the
        ldx fstate              ; weapon's state only
        dex
        bne :+
        ora #K_FIRE
:       jsr _player_fire
        jsr _droids_fire
        jsr _move_shots
        jsr _collide
        lda #<-8
        jsr _fig_place
        jsr _sight              ; the droids it sees, for the next ones
        lda _transfer_mode
        beq :+
        lda _touched
        beq :+
        jsr transfer
        jsr play_init
:       jsr _energy_tick
        lda _score_changed
        beq @flash
        jsr _panel_score
        lda lights_out
        bne @flash
        lda _deck
        jsr _deck_cleared
        cmp #0
        beq @flash
        lda #1                  ; the deck cleared
        sta lights_out
        lda #<250
        ldx #>250
        jsr add_score
        jsr _deck_colours
        lda #SFX_CLEARED
        jsr _sound
        jsr _ship_cleared
        cmp #0
        bne @fleet
        lda #<s_cleared
        ldx #>s_cleared
        jsr status
        jmp @score
@fleet: lda #<s_fleet           ; the ship too
        ldx #>s_fleet
        jsr status
        lda #<2000
        ldx #>2000
        jsr add_score
        jsr next_ship
@score: jsr _panel_score
@flash: lda #$71                ; the disruptor's flash
        ldx _flash
        bne :+
        lda _deck_bg
:       sta _col_deck
        jsr _anim_deck          ; the energizers turning
        lda _alert_acc          ; the alert by the kills
        rol a
        rol a
        rol a
        and #3
        cmp _alert
        beq :+
        sta _alert
        jsr _deck_colours
:       jsr _draw
        jsr _turn_droids        ; the droids' domes, in the time left
        jmp @tick

; mc_font(): the deck characters in multicolour, for the cells figures
; are in: a pixel pair with anything set is %11, the cell's own colour.
; Made from picture 0's character set, as the start-up copy is gone after
; a while.
_mc_font:
        lda #<FONT0
        sta ptr1
        lda #>FONT0
        sta ptr1+1
        lda #<MCFONT
        sta ptr2
        lda #>MCFONT
        sta ptr2+1
        lda #<(POOL * 8)
        sta cnt
        lda #>(POOL * 8)
        sta cnt+1
        ldy #0
@b:     lda (ptr1),y
        sta pf
        lda #0
        sta cd
        ldx #3
:       lda pf
        and mc_mask,x
        beq :+
        lda mc_mask,x
        ora cd
        sta cd
:       dex
        bpl :--
        lda cd
        sta (ptr2),y
        iny
        bne :+
        inc ptr1+1
        inc ptr2+1
:       lda cnt
        bne :+
        dec cnt+1
:       dec cnt
        lda cnt
        ora cnt+1
        bne @b
        rts

; ======================================================================
; Waiting for a game
; ======================================================================

        .segment "HICODE"       ; (room there; it is copied at the start)

; after a game, as the original: the 999 between "Transmission" and
; "Terminated"; the window's colour before it in cd, for page_end()
terminated:
        jsr wait_ready
        jsr _eng_plain
        lda _col_deck
        sta cd
        lda _pal_deck+1
        sta _col_deck
        ; first the static, as the original's ($378B): the window full of
        ; its four noise characters at random, black on white, going round
        ; and rolling down the window's lines, 52 steps in 1.2 seconds,
        ; with its noise
        ldx #31
:       lda _anim_s,x
        sta FONT1 + 250 * 8,x
        dex
        bpl :-
        lda #$D8                ; (the deck shows the same in it)
        sta _font_hi
        lda #<(8 * 40)          ; (from the window's top row on: rolled
        sta ptr1                ; down, its last lines show at the top)
        lda #>(8 * 40)
        sta ptr1+1
@cell:  jsr _rnd
        and #3
        clc
        adc #250
        ldy #0
        tax
        lda ptr1+1
        pha
        ora #>SCR0C
        sta ptr1+1
        txa
        sta (ptr1),y
        lda ptr1+1
        eor #>SCR0C ^ >SCR1C
        sta ptr1+1
        txa
        sta (ptr1),y
        pla
        pha
        ora #>SCR0A
        sta ptr1+1
        tya
        sta (ptr1),y
        pla
        pha
        ora #>SCR1A
        sta ptr1+1
        tya
        sta (ptr1),y
        pla
        sta ptr1+1
        inc ptr1
        bne :+
        inc ptr1+1
:       lda ptr1
        cmp #<1000
        bne @cell
        lda ptr1+1
        cmp #>1000
        bne @cell
        lda #SFX_STATIC
        jsr _sound
        ; then the 999's picture, "Transmission terminated" and its tune:
        ; the static goes on for 1.2 seconds, as the original's (61
        ; pictures: picture()'s pic_late)
        lda #1
        sta _roll
        sta _pic_late
        lda _frames
        clc
        adc #61
        sta _pic_until
        lda #23
        jsr pusha
        lda #12
        jsr pusha
        lda #17                 ; (the droid in the middle, under the
        jsr _picture            ; words)
        lda #$63                ; the original's light cyan
        sta _x_attr
        lda #10
        sta _x_row
        lda #13
        sta _x_col
        lda #<s_trans
        ldx #>s_trans
        jsr _say
        lda #22
        sta _x_row
        lda #14
        sta _x_col
        lda #<s_term
        ldx #>s_term
        jsr _say
        lda #SFX_TERMINATED
        jsr _sound
        lda #70                 ; 4.2 seconds, as the original
        sta cnt
:       jsr _wait_tick
        dec cnt
        bne :-
        rts

s_trans:    .byte "Transmission", 0
s_term:     .byte "Terminated", 0

        .code

; page_end(cd): a page in the window done with (here, title.s,
; transfer.s, screens.s): the window cleared, the deck's characters and
; colours back, the window's colour cd
_page_end:
        sta cd
        jsr wait_ready
        lda #0
        jsr pusha
        lda #$71
        jsr _win_clear
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
        ldx #(256 - CUT_R0) * 4 - 1 ; the window's top row's codes blank in
        lda #0                  ; both sets (the gap shows the other's)
:       sta FONT0 + CUT_R0 * 8,x
        sta FONT0 + CUT_R0 * 8 + (256 - CUT_R0) * 4,x
        sta FONT1 + CUT_R0 * 8,x
        sta FONT1 + CUT_R0 * 8 + (256 - CUT_R0) * 4,x
        dex
        cpx #$FF
        bne :-
        lda #$C8
        sta _font_hi
        lda #$71
        sta _col_fig2
        lda cd
        sta _col_deck
        rts

; title(): the day's scores taken, the end of the game, then the title
title:  lda #1
        sta _hide_player
        lda #0
        sta _player_dead
        lda over
        beq @first
        jsr terminated          ; (still up while the overlay is unpacked:
        jsr @ovl                ; the day's scores and their initials are
        jsr _title_scores       ; taken there, over it, as the original's)
        lda cd
        jsr _page_end
        jmp @run
@first: jsr wait_ready          ; the first time, or the game ended in the
        lda #0                  ; pause: the picture off, the border black,
        sta _col_border         ; while the title is made, as at the start
        sei                     ; (the original goes straight to the title)
        lda $FF06
        and #$EF
        sta $FF06
        cli
        jsr @ovl
@run:   jsr _title_run
        lda #1
        sta over
        lda #0
        sta _hide_player
        jmp _pictures_fixed
@ovl:   lda #<__OVL_START__     ; the title and the briefing (title.s), an
        sta _unp_dst            ; overlay kept packed, unpacked where the
        lda #>__OVL_START__     ; pictures' slots are: the title has no use
        sta _unp_dst+1          ; for them, they are made again for a game
        lda #<_blob_title
        ldx #>_blob_title
        jmp _unpack

_main:  jsr _eng_stack
        jsr _start_up           ; (startup.s)
        inc _keep_border        ; nothing shows till the title's first
        jsr new_game            ; screen is whole: the picture off, the
        dec _keep_border        ; border black (startup.s), not the deck's
        jsr _draw
        jsr _eng_show
        lda _frames
        sta last
@game:  jsr title
        jsr new_game            ; (the start page still up)
        lda _deck_bg
        jsr _page_end
        jsr _beam_in            ; (sfxcall.s)
        lda _frames
        sta last
        lda #<s_mobile
        ldx #>s_mobile
        jsr status
        jsr play
        lda #<s_gameover
        ldx #>s_gameover
        jsr status
        lda #K_FIRE
        jsr wait_free
        jmp @game
