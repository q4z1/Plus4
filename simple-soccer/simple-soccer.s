; simple-soccer.s - Simple Soccer for the Commodore Plus/4, after Sensible Soccer
; (Sensible Software, Amiga), looking like Arlasoft Soccer on the C64.
;
; For now: both teams lined up, the ball on the centre spot; the joystick
; (or the cursor keys and the space bar) runs the cyan player nearest the
; ball, who dribbles it and passes it with fire. The match itself is
; play.s; this file has the loop, the view and the drawing. All of it is
; assembly, as Paradroid and trainschedule.

        .include "game.inc"
        .include "data.inc"

        .import eng_init, eng_begin, eng_end, fig_draw, joy_read
        .import cam_x, cam_y, frames, fig_x, fig_y, fig_img, fig_col
        .import play_init, play_frame, pose_of, score, game_min, hud
        .import title
        .import o_xl, o_xh, o_yl, o_yh, o_zl, o_dir, o_step
        .import ymap_lo, ymap_hi
        .import __BSS_RUN__, __BSS_SIZE__

MAX_X       = (MAP_W - SCR_W) * 8 + 7
MAX_Y       = (MAP_H - SCR_H) * 8 + 7

PLAYERS     = 22                ; 0-10 cyan, the joystick's; 11-21 yellow
BALL        = PLAYERS           ; the figures' last
FIGS        = PLAYERS + 1

; the pitch onto the ground: x - 23 (the touchlines at 49 and 558 onto
; the ground's at 26 and 535; y through ymap_*)
GROUND_X    = 23

; where a figure's feet are in its sprite; the ball's middle in its
; sprite, and its shadow's
FOOT_X      = 6
FOOT_Y      = 14
BALL_X      = 7
BALL_Y      = 11
SHADOW_Y    = 12

MAX_STEPS   = 4                 ; frames of play caught up in a turn at most

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
; the figures on the ground, worked out each turn: where their feet are
s_xl:   .res FIGS
s_xh:   .res FIGS
s_yl:   .res FIGS
s_yh:   .res FIGS
tick:   .res 1                  ; turns of the loop
played: .res 1                  ; frames played up to
order:  .res FIGS               ; the figures from the top down
s_off:  .res FIGS               ; 1: not in this picture (seen)
tmp:    .res 1
tmp2:   .res 1
hud_n:  .res 1                  ; draw_hud's place
s_i:    .res 1                  ; sort's
s_j:    .res 1

        .rodata
; the image for each step of the run: standing, a foot forward, standing,
; the other foot
step_img: .byte 0, 1, 0, 2

        .code

main:
        jsr title               ; (the title first: the length of the match)
        jsr eng_init
        jsr play_init
        ldx #0                  ; an order to sort from
:       txa
        sta order,x
        inx
        cpx #FIGS
        bne :-
        lda frames
        sta played
loop:
        jsr joy_read
        inc tick
        ; the match a frame for each frame shown since the last turn
        lda frames
        sec
        sbc played
        beq @go
        cmp #MAX_STEPS + 1
        bcc :+
        lda #MAX_STEPS
:       sta tmp
        lda frames
        sta played
:       jsr play_frame
        dec tmp
        bne :-
@go:    jsr place
        jsr follow
        jsr eng_begin
        jsr sort
        jsr draw
        jsr draw_hud
        jsr eng_end             ; (waits while a picture is still waiting)
        jmp loop

; place: each figure's feet on the ground - the ball's where it would lie
; (ymap_lo/hi[y], y < 768: by its high byte, straight from the table)
place:
        ldx #FIGS - 1
@fig:   lda o_xl,x
        sec
        sbc #GROUND_X
        sta s_xl,x
        lda o_xh,x
        sbc #0
        sta s_xh,x
        ldy o_yl,x
        lda o_yh,x
        beq @y0
        lsr a
        bcs @y1
        lda ymap_lo + 512,y
        sta s_yl,x
        lda ymap_hi + 512,y
        sta s_yh,x
        dex
        bpl @fig
        rts
@y1:    lda ymap_lo + 256,y
        sta s_yl,x
        lda ymap_hi + 256,y
        sta s_yh,x
        dex
        bpl @fig
        rts
@y0:    lda ymap_lo,y
        sta s_yl,x
        lda ymap_hi,y
        sta s_yh,x
        dex
        bpl @fig
        rts

; follow: the view on the ball, as far as the ground goes
follow:
        ldx #BALL
        lda s_xl,x
        sec
        sbc #<(SCR_W * 4 - 8)   ; (the middle of the 38 columns shown)
        sta cam_x
        lda s_xh,x
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
:       lda s_yl,x
        sec
        sbc #96
        sta cam_y
        lda s_yh,x
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
@next:  ldx s_i                 ; (mostly no lower than the one above: next)
        ldy order,x
        lda order - 1,x
        tax
        lda s_yl,y
        cmp s_yl,x
        lda s_yh,y
        sbc s_yh,x
        bcs @in
        ldx s_i
        lda order,x
        sta tmp
        stx s_j                 ; the gap
@back:  ldx s_j
        beq @put
        ldy order - 1,x         ; the figure above the gap: lower than
        ldx tmp                 ; tmp, it moves down into the gap
        lda s_yl,x
        cmp s_yl,y
        lda s_yh,x
        sbc s_yh,y
        bcs @put
        ldx s_j
        lda order - 1,x
        sta order,x
        dec s_j
        jmp @back
@put:   ldx s_j
        lda tmp
        sta order,x
@in:    inc s_i
        lda s_i
        cmp #FIGS
        bne @next
        rts

; draw: every figure, from the top down - the lower in front; the ball
; last
draw:
        lda #0
        sta tmp
@next:  ldx tmp
        lda order,x
        tax
        jsr seen
        lda #0
        rol a
        sta s_off,x
        bne @skip
        cpx #BALL
        beq @skip               ; (the ball last)
        lda s_xl,x
        sec
        sbc #FOOT_X
        sta fig_x
        lda s_xh,x
        sbc #0
        sta fig_x + 1
        lda s_yl,x
        sec
        sbc #FOOT_Y
        sta fig_y
        lda s_yh,x
        sbc #0
        sta fig_y + 1
        jsr pose_of             ; (lying, diving, holding the ball)
        cmp #$FF
        bne @img
        lda o_step,x
        and #3
        tay
        lda o_dir,x
        sta tmp2
        asl a
        adc tmp2                ; direction * 3
        adc step_img,y
@img:   sta fig_img
        lda #COL_TEAM1
        cpx #11
        bcc :+
        lda #COL_TEAM2
:       sta fig_col
        jsr fig_draw
@skip:  inc tmp
        lda tmp
        cmp #FIGS
        bne @next
        ldx #BALL               ; the ball in front of all: its cells white
        lda s_off,x             ; (engine.s)
        bne :+
        jmp draw_ball
:       rts

; draw_ball: its shadow on the ground when it is up, and the ball as high
; above it as it is - its height squeezed as the pitch is (9 / 16)
draw_ball:
        ldx #BALL
        lda s_xl,x
        sec
        sbc #BALL_X
        sta fig_x
        lda s_xh,x
        sbc #0
        sta fig_x + 1
        lda #COL_LINE
        sta fig_col
        lda o_zl,x
        beq @ball
        lda s_yl,x
        sec
        sbc #SHADOW_Y
        sta fig_y
        lda s_yh,x
        sbc #0
        sta fig_y + 1
        lda #IMG_SHADOW
        sta fig_img
        jsr fig_draw
        ldx #BALL
@ball:  lda o_zl,x              ; z * 9 / 16 = z / 2 + z / 16
        lsr a
        sta tmp2
        lsr a
        lsr a
        lsr a
        clc
        adc tmp2
        sta tmp2
        lda s_yl,x
        sec
        sbc #BALL_Y
        sta fig_y
        lda s_yh,x
        sbc #0
        sta fig_y + 1
        lda fig_y
        sec
        sbc tmp2
        sta fig_y
        bcs :+
        dec fig_y + 1
:       lda o_step,x
        and #3
        clc
        adc #IMG_BALL
        sta fig_img
        jmp fig_draw

; draw_hud: while the ball is dead for a kick-off, the score and the
; minute at the top left of the view - drawn as figures, at a place on
; the ground that moves with the view, so they keep still on the screen
HUD_X       = 20                ; (from the view's left, top - or bottom,
HUD_Y       = 10                ; the stands at the top of the view: no
HUD_LOW     = 170               ; figure goes over them, see engine.s tint)
HUD_HIGH    = 80                ; (the view higher than this: at the bottom)
draw_hud:
        lda hud
        bne :+
        rts
:       lda #COL_LINE
        sta fig_col
        lda #0
        sta hud_n
        lda score               ; cyan - yellow
        jsr hud_digit
        lda #10                 ; (the dash)
        jsr hud_digit
        lda score + 1
        jsr hud_digit
        inc hud_n               ; (a gap)
        lda game_min            ; the minute
        ldx #0
:       cmp #10
        bcc :+
        sbc #10
        inx
        bne :-
:       pha
        txa
        jsr hud_digit
        pla
        jmp hud_digit

; hud_digit: digit A (9 at most; 10 the dash) at the HUD's next place
hud_digit:
        cmp #11
        bcc :+
        lda #9
:       clc
        adc #IMG_DIGIT
        sta fig_img
        lda hud_n               ; x: the view's + HUD_X + n * 9
        asl a
        asl a
        asl a
        adc hud_n               ; (* 9)
        adc #HUD_X
        clc
        adc cam_x
        sta fig_x
        lda cam_x + 1
        adc #0
        sta fig_x + 1
        ldx #HUD_Y              ; (the stands in view at the top: at the
        lda cam_y + 1           ; bottom)
        bne :+
        lda cam_y
        cmp #HUD_HIGH
        bcs :+
        ldx #HUD_LOW
:       txa
        clc
        adc cam_y
        sta fig_y
        lda cam_y + 1
        adc #0
        sta fig_y + 1
        inc hud_n
        jmp fig_draw

; seen: carry clear if figure X may be in the view at all - its feet
; from 18 pixels left of it to 10 right, 8 above to 14 below (its sprite
; around them; the ball's height left out); a rough test that spares
; fig_draw the far ones
seen:
        lda s_xl,x
        sec
        sbc cam_x
        sta tmp2
        lda s_xh,x
        sbc cam_x + 1
        beq @y                  ; 0..255 to the right of the left edge
        cmp #1
        beq @right
        cmp #$FF
        bne @no
        lda tmp2                ; left of it: -18..-1
        cmp #<(-18)
        bcc @no
        bcs @y
@right: lda tmp2                ; 256..329
        cmp #<(SCR_W * 8 + 10)
        bcs @no
@y:     lda s_yl,x
        sec
        sbc cam_y
        sta tmp2
        lda s_yh,x
        sbc cam_y + 1
        beq @down
        cmp #$FF
        bne @no
        lda tmp2                ; above: -8..-1
        cmp #<(-8)
        bcc @no
        clc
        rts
@down:  lda tmp2                ; 0..213
        cmp #SCR_H * 8 + 14
        rts
@no:    sec
        rts
