; soccer.s - a soccer game for the Commodore Plus/4, after Sensible Soccer
; (Sensible Software, Amiga), looking like Arlasoft Soccer on the C64.
;
; For now: both teams lined up for the kick-off, and one player of the
; cyan team run about with the joystick (or the cursor keys); the view
; follows him. All of it is assembly, as Paradroid and trainschedule.

        .include "game.inc"
        .include "data.inc"

        .import eng_init, eng_begin, eng_end, eng_wait, fig_draw, joy_read
        .import cam_x, cam_y, joy, fig_x, fig_y, fig_img, fig_col
        .import __BSS_RUN__, __BSS_SIZE__

MAX_X       = (MAP_W - SCR_W) * 8 + 7
MAX_Y       = (MAP_H - SCR_H) * 8 + 7

PLAYERS     = 22                ; 0-10 cyan (from the bottom, up), 11-21 yellow
BALL        = PLAYERS           ; the figures' last
FIGS        = PLAYERS + 1

; where a figure's feet are in its sprite
FOOT_X      = 6
FOOT_Y      = 14

; the ground: the pitch's lines, in pixels
CENTRE_X    = 284
CENTRE_Y    = 290
; where feet can go: the ground, less its stands
MIN_FX      = 8
MAX_FX      = MAP_W * 8 - 8
MIN_FY      = 6 * 8
MAX_FY      = (MAP_H - 5) * 8

        .zeropage
ptr:    .res 2

; The start, where the program's BASIC line SYSes to: the ROM out, the
; variables cleared; no C, no cc65 start-up.
        .segment "STARTUP"
        sei
        cld
        ldx #$FF
        txs
        sta TED_RAM
        lda #<__BSS_RUN__
        sta ptr
        lda #>__BSS_RUN__
        sta ptr + 1
        ldx #>__BSS_SIZE__
        ldy #0
        tya
@page:  cpx #0
        beq @rest
:       sta (ptr),y
        iny
        bne :-
        inc ptr + 1
        dex
        jmp @page
@rest:  cpy #<__BSS_SIZE__
        beq @done
        sta (ptr),y
        iny
        jmp @rest
@done:  jmp main

        .bss
; the figures: players, then the ball - where their feet are on the
; ground, which way they face (0 up, clockwise to 7), their step
f_xlo:  .res FIGS
f_xhi:  .res FIGS
f_ylo:  .res FIGS
f_yhi:  .res FIGS
f_dir:  .res FIGS
f_step: .res FIGS
ctrl:   .res 1                  ; the player the joystick runs
tick:   .res 1
order:  .res FIGS               ; the figures from the top down
tmp:    .res 1
s_i:    .res 1                  ; sort's
s_j:    .res 1

        .rodata
; 4-4-2, the cyan team from the bottom: keeper, defence, midfield, attack
line_x: .word 284, 120, 220, 348, 448, 120, 220, 348, 448, 250, 318
line_y: .word 455, 410, 410, 410, 410, 350, 350, 350, 350, 300, 300

; the joystick's directions as the figures' (8: none)
joy_dir: .byte 8, 0, 4, 8, 6, 7, 5, 6, 2, 1, 3, 2, 8, 0, 4, 8
; a step in each direction
dir_dx: .byte 0, 1, 1, 1, 0, $FF, $FF, $FF
dir_dy: .byte $FF, $FF, 0, 1, 1, 1, 0, $FF
; the image for each step of the run: standing, a foot forward, standing,
; the other foot
step_img: .byte 0, 1, 0, 2

        .code

main:
        jsr eng_init
        jsr line_up
        lda #9                  ; a forward
        sta ctrl
loop:
        jsr joy_read
        inc tick
        jsr run_ctrl
        jsr follow
        jsr eng_begin
        jsr sort
        jsr draw
        jsr eng_end
        jsr eng_wait
        jmp loop

; line_up: both teams in their halves, facing each other, the ball on the
; centre spot
line_up:
        ldx #0
@pl:    txa
        asl a
        tay
        lda line_x,y
        sta f_xlo,x
        sta f_xlo + 11,x
        lda line_x + 1,y
        sta f_xhi,x
        sta f_xhi + 11,x
        lda line_y,y
        sta f_ylo,x
        lda line_y + 1,y
        sta f_yhi,x
        ; the yellow team mirrored: y' = 2 * CENTRE_Y - y
        lda #<(2 * CENTRE_Y)
        sec
        sbc line_y,y
        sta f_ylo + 11,x
        lda #>(2 * CENTRE_Y)
        sbc line_y + 1,y
        sta f_yhi + 11,x
        lda #0
        sta f_dir,x
        lda #4
        sta f_dir + 11,x
        inx
        cpx #11
        bne @pl
        ldx #0                  ; an order to sort from
:       txa
        sta order,x
        inx
        cpx #FIGS
        bne :-
        lda #<CENTRE_X
        sta f_xlo + BALL
        lda #>CENTRE_X
        sta f_xhi + BALL
        lda #<CENTRE_Y
        sta f_ylo + BALL
        lda #>CENTRE_Y
        sta f_yhi + BALL
        rts

; run_ctrl: the joystick's player a pixel a picture the way it points,
; two with fire; his step on every fourth picture
run_ctrl:
        ldx ctrl
        lda joy
        and #$0F
        tay
        lda joy_dir,y
        cmp #8
        bne :+
        lda #0                  ; standing
        sta f_step,x
        rts
:       sta f_dir,x
        tay
        lda #1
        sta tmp
        lda joy
        and #J_FIRE
        beq :+
        asl tmp
:       lda dir_dx,y
        beq @y
        bmi @left
        lda f_xlo,x
        clc
        adc tmp
        sta f_xlo,x
        bcc @y
        inc f_xhi,x
        bcs @y
@left:  lda f_xlo,x
        sec
        sbc tmp
        sta f_xlo,x
        bcs @y
        dec f_xhi,x
@y:     lda dir_dy,y
        beq @step
        bmi @up
        lda f_ylo,x
        clc
        adc tmp
        sta f_ylo,x
        bcc @step
        inc f_yhi,x
        bcs @step
@up:    lda f_ylo,x
        sec
        sbc tmp
        sta f_ylo,x
        bcs @step
        dec f_yhi,x
@step:  lda tick
        and #3
        bne :+
        inc f_step,x
:       ; inside the ground
        lda f_xhi,x
        bmi @xlo
        lda f_xlo,x
        cmp #<MIN_FX
        lda f_xhi,x
        sbc #>MIN_FX
        bcs :+
@xlo:   lda #<MIN_FX
        sta f_xlo,x
        lda #>MIN_FX
        sta f_xhi,x
:       lda f_xlo,x
        cmp #<(MAX_FX + 1)
        lda f_xhi,x
        sbc #>(MAX_FX + 1)
        bcc :+
        lda #<MAX_FX
        sta f_xlo,x
        lda #>MAX_FX
        sta f_xhi,x
:       lda f_yhi,x
        bmi @ylo
        lda f_ylo,x
        cmp #<MIN_FY
        lda f_yhi,x
        sbc #>MIN_FY
        bcs :+
@ylo:   lda #<MIN_FY
        sta f_ylo,x
        lda #>MIN_FY
        sta f_yhi,x
:       lda f_ylo,x
        cmp #<(MAX_FY + 1)
        lda f_yhi,x
        sbc #>(MAX_FY + 1)
        bcc :+
        lda #<MAX_FY
        sta f_ylo,x
        lda #>MAX_FY
        sta f_yhi,x
:       rts

; follow: the view on the joystick's player, as far as the ground goes
follow:
        ldx ctrl
        lda f_xlo,x
        sec
        sbc #<(SCR_W * 4 - 8)   ; (the middle of the 38 columns shown)
        sta cam_x
        lda f_xhi,x
        sbc #>(SCR_W * 4 - 8)
        sta cam_x + 1
        bpl :+
        lda #0
        sta cam_x
        sta cam_x + 1
:       lda cam_x
        cmp #<MAX_X
        lda cam_x + 1
        sbc #>MAX_X
        bcc :+
        lda #<MAX_X
        sta cam_x
        lda #>MAX_X
        sta cam_x + 1
:       lda f_ylo,x
        sec
        sbc #96
        sta cam_y
        lda f_yhi,x
        sbc #0
        sta cam_y + 1
        bpl :+
        lda #0
        sta cam_y
        sta cam_y + 1
:       lda cam_y
        cmp #<MAX_Y
        lda cam_y + 1
        sbc #>MAX_Y
        bcc :+
        lda #<MAX_Y
        sta cam_y
        lda #>MAX_Y
        sta cam_y + 1
:       rts

; sort: order, the figures by where their feet are, from the top down
; (insertion sort on the last picture's order: from one picture to the
; next it hardly changes)
sort:
        lda #1
        sta s_i
@next:  ldx s_i
        lda order,x
        sta tmp
        stx s_j                 ; the gap
@back:  ldx s_j
        beq @put
        ldy order - 1,x         ; the figure above the gap: lower than
        ldx tmp                 ; tmp, it moves down into the gap
        lda f_ylo,x
        cmp f_ylo,y
        lda f_yhi,x
        sbc f_yhi,y
        bcs @put
        ldx s_j
        lda order - 1,x
        sta order,x
        dec s_j
        jmp @back
@put:   ldx s_j
        lda tmp
        sta order,x
        inc s_i
        lda s_i
        cmp #FIGS
        bne @next
        rts

; draw: every figure, from the top down - the lower in front
draw:
        lda #0
        sta tmp
@next:  ldx tmp
        lda order,x
        tax
        lda f_xlo,x
        sec
        sbc #FOOT_X
        sta fig_x
        lda f_xhi,x
        sbc #0
        sta fig_x + 1
        lda f_ylo,x
        sec
        sbc #FOOT_Y
        sta fig_y
        lda f_yhi,x
        sbc #0
        sta fig_y + 1
        cpx #BALL
        bne @pl
        lda #IMAGES - 1
        sta fig_img
        lda #COL_LINE
        sta fig_col
        bne @draw
@pl:    lda f_step,x
        and #3
        tay
        lda f_dir,x
        sta ptr
        asl a
        adc ptr                 ; direction * 3
        adc step_img,y
        sta fig_img
        lda #COL_TEAM1
        cpx #11
        bcc :+
        lda #COL_TEAM2
:       sta fig_col
@draw:  jsr fig_draw
        inc tmp
        lda tmp
        cmp #FIGS
        bne @next
        rts
