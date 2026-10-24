; play.s - the match: the players and the ball, a frame at a time (50 a
; second), as Sensible Soccer moves them
;
; The game runs on Sensible Soccer's pitch and in its units: touchlines
; at x 49 and 558, goal lines at y 49 and 689, the centre spot at 304,
; 369; soccer.s shows it on the C64's ground (ymap_*). Positions are
; 16.8 fixed point (a fraction byte, then the pixel), steps 8.8.
;
; Everything moves the same way: towards a destination, at a speed. Each
; frame its step is worked out from the way to the destination - an
; angle of 256 to the circle, linear in dy/dx (atan_tab), and 127 * sin
; of it times the speed / 256 per axis. The joystick's player is given a
; destination 1000 pixels the way the stick points; the ball one ahead
; of it when it is kicked.
;
; The ball: on the ground it loses 16 of its speed a frame, in the air
; 10; gravity takes $12 from its upward step; when it lands it loses a
; quarter of its speed and bounces with 5/8 of its downward step, and
; lies once that is under $A0. Past the walls round the pitch (x 19 /
; 588, y 20 / 719) it comes back, at half the speed.
;
; Dribbling: the joystick's player, the ball low at his feet (distance
; squared at most 32) and the stick pushed: the ball is kicked on ahead
; the way it points every frame, a little faster each four frames that
; way. Fire passes: to the nearest team-mate within 22.5 degrees of the
; way the stick (or the player) points, harder the further he is; with
; none there, straight on.

        .include "game.inc"
        .include "data.inc"

        .export play_init, play_frame
        .export o_xl, o_xh, o_yl, o_yh, o_zl, o_dir, o_step, o_spl, ctrl
        .import joy, atan_tab, sin_tab

PLAYERS     = 22                ; 0-10 the joystick's team, from its keeper
BALL        = PLAYERS           ; the last object
NOBJ        = PLAYERS + 1

SPEED_RUN   = $04E0             ; a player running
SPEED_BALL  = 896               ; and with the ball at his feet
NEAR        = 32                ; distance squared: the ball at his feet
CLOSE       = 72                ; near enough to kick it

        .zeropage
z_ax:       .res 2              ; aim's: the way to the destination
z_ay:       .res 2
z_sx:       .res 1              ;   its signs
z_sy:       .res 1
z_th:       .res 1              ;   the angle
z_p:        .res 3              ; smul's product
z_m:        .res 1
z_ms:       .res 1
z_ptr:      .res 2
z_obj:      .res 1
smul_l:     .res 1              ; smul's multiplier
smul_h:     .res 1
z_q:        .res 2              ; mul8's
z_b:        .res 1
d_ax:       .res 1              ; dist2's
d_ay:       .res 1

        .bss
; the objects: the players, then the ball
o_xf:   .res NOBJ               ; x: fraction, pixel
o_xl:   .res NOBJ
o_xh:   .res NOBJ
o_yf:   .res NOBJ
o_yl:   .res NOBJ
o_yh:   .res NOBJ
o_zf:   .res NOBJ               ; height: fraction, pixel
o_zl:   .res NOBJ
o_dzf:  .res NOBJ               ; its step, 8.8 signed
o_dzl:  .res NOBJ
o_vxf:  .res NOBJ               ; the step, 8.8 signed
o_vxl:  .res NOBJ
o_vyf:  .res NOBJ
o_vyl:  .res NOBJ
o_spl:  .res NOBJ               ; speed
o_sph:  .res NOBJ
o_txl:  .res NOBJ               ; destination
o_txh:  .res NOBJ
o_tyl:  .res NOBJ
o_tyh:  .res NOBJ
o_dir:  .res NOBJ               ; the way it faces, 0 up .. 7, clockwise
o_step: .res NOBJ               ; its running picture (players), turn (ball)
o_run:  .res NOBJ               ; frames to its next step
c_axl:  .res NOBJ               ; aim's last way and speed: the same
c_axh:  .res NOBJ               ; again, the step is still right
c_ayl:  .res NOBJ
c_ayh:  .res NOBJ
c_spl:  .res NOBJ
c_sph:  .res NOBJ

ctrl:       .res 1              ; the joystick's player
fire_was:   .res 1              ; fire held last frame
drib_dir:   .res 1              ; dribbling: the way, and the touches
drib_n:     .res 1
switch_t:   .res 1              ; frames to the next look for a player
d2:         .res 2              ; dist2's result
mate:       .res 1              ; pass's
mate_d:     .res 2
mate_t:     .res 2
kick_way:   .res 1              ; pass's: the way, 0-255
tmp:        .res 2
old_x:      .res 3              ; ball_move's: where it was
old_y:      .res 3
old_z:      .res 2

        .rodata
; 4-4-2, the joystick's team from the bottom: keeper, defence,
; midfield, attack - one forward at the ball for the kick-off (the other
; team the same, mirrored)
line_x:     .word 304, 174, 264, 344, 434, 144, 274, 334, 464, 300, 334
line_y:     .word 678, 556, 556, 556, 556, 445, 489, 489, 445, 373, 382

; the joystick as a way to go (8: none)
joy_dir:    .byte 8, 0, 4, 8, 6, 7, 5, 6, 2, 1, 3, 2, 8, 0, 4, 8
; a destination 1000 pixels off, each way
vec_xl:     .byte <0, <1000, <1000, <1000, <0, <(-1000), <(-1000), <(-1000)
vec_xh:     .byte >0, >1000, >1000, >1000, >0, >(-1000), >(-1000), >(-1000)
vec_yl:     .byte <(-1000), <(-1000), <0, <1000, <1000, <1000, <0, <(-1000)
vec_yh:     .byte >(-1000), >(-1000), >0, >1000, >1000, >1000, >0, >(-1000)
; the dribble's kick, by the touches the same way / 4
drib_lo:    .byte <1024, <1089, <1088, <1216
drib_hi:    .byte >1024, >1089, >1088, >1216
; squares, for distances
sq_lo:
        .repeat 64, I
        .byte <(I * I)
        .endrepeat
sq_hi:
        .repeat 64, I
        .byte >(I * I)
        .endrepeat
qs_lo:                          ; n * n / 4, n = 0..511
        .repeat 512, I
        .byte <(I * I / 4)
        .endrepeat
qs_hi:
        .repeat 512, I
        .byte >(I * I / 4)
        .endrepeat
sq8_lo:
        .repeat 256, I
        .byte <(I * I)
        .endrepeat
sq8_hi:
        .repeat 256, I
        .byte >(I * I)
        .endrepeat

        .code

; play_init: both teams lined up, the ball on the centre spot, the
; joystick on a forward
play_init:
        ldx #0
@pl:    txa
        asl a
        tay
        lda line_x,y
        sta o_xl,x
        sta o_xl + 11,x
        lda line_x + 1,y
        sta o_xh,x
        sta o_xh + 11,x
        lda line_y,y
        sta o_yl,x
        lda line_y + 1,y
        sta o_yh,x
        lda #<738               ; mirrored: 738 - y
        sec
        sbc line_y,y
        sta o_yl + 11,x
        lda #>738
        sbc line_y + 1,y
        sta o_yh + 11,x
        lda #0
        sta o_dir,x
        lda #4
        sta o_dir + 11,x
        inx
        cpx #11
        bne @pl
        ldx #NOBJ - 1           ; standing where they are
:       jsr stand
        dex
        bpl :-
        lda #<304
        sta o_xl + BALL
        lda #>304
        sta o_xh + BALL
        lda #<369
        sta o_yl + BALL
        lda #>369
        sta o_yh + BALL
        ldx #BALL
        jsr stand
        lda #9
        sta ctrl
        rts

; stand: object X stopped, its destination where it is
stand:
        lda o_xl,x
        sta o_txl,x
        lda o_xh,x
        sta o_txh,x
        lda o_yl,x
        sta o_tyl,x
        lda o_yh,x
        sta o_tyh,x
        lda #0
        sta o_spl,x
        sta o_sph,x
        sta o_vxf,x
        sta o_vxl,x
        sta o_vyf,x
        sta o_vyl,x
        rts

; ---- a frame --------------------------------------------------------------

play_frame:
        jsr control
        ldx #PLAYERS - 1
:       stx z_obj
        jsr player_move
        ldx z_obj
        dex
        bpl :-
        jsr ball_move
        jmp switch

; control: the joystick's player - where he runs, dribbling, fire
control:
        ldx ctrl
        lda joy
        and #$0F
        tay
        lda joy_dir,y
        cmp #8
        bne @run
        jsr stand               ; the stick let go: he stops
        lda #$FF
        sta drib_dir
        jmp @fire
@run:   sta o_dir,x
        tay
        lda o_xl,x              ; 1000 pixels the way the stick points
        clc
        adc vec_xl,y
        sta o_txl,x
        lda o_xh,x
        adc vec_xh,y
        sta o_txh,x
        lda o_yl,x
        clc
        adc vec_yl,y
        sta o_tyl,x
        lda o_yh,x
        adc vec_yh,y
        sta o_tyh,x
        jsr dist2               ; slower with the ball close
        lda #<SPEED_RUN
        sta o_spl,x
        lda #>SPEED_RUN
        sta o_sph,x
        lda d2 + 1
        bne @far
        lda d2
        cmp #CLOSE + 1
        bcs @far
        lda #<SPEED_BALL
        sta o_spl,x
        lda #>SPEED_BALL
        sta o_sph,x
        lda d2                  ; at his feet, low: dribbled on
        cmp #NEAR + 1
        bcs @far
        lda o_zl + BALL
        cmp #13
        bcs @far
        jsr dribble
@far:
@fire:  lda joy                 ; fire: a pass, when it is pressed
        and #J_FIRE
        tay
        eor fire_was
        and #J_FIRE
        sty fire_was
        beq @done
        tya
        beq @done
        jsr dist2
        lda d2 + 1
        bne @done
        lda d2
        cmp #CLOSE + 1
        bcs @done
        lda o_zl + BALL
        cmp #13
        bcs @done
        jsr pass
@done:  rts

; dist2: d2 = the distance squared from the joystick's player to the
; ball, $FFFF when it is 64 or more either way. Keeps X.
dist2:
        ldy ctrl
        lda o_xl + BALL
        sec
        sbc o_xl,y
        sta tmp
        lda o_xh + BALL
        sbc o_xh,y
        jsr d_abs
        bcs @big
        sta d_ax
        ldy ctrl
        lda o_yl + BALL
        sec
        sbc o_yl,y
        sta tmp
        lda o_yh + BALL
        sbc o_yh,y
        jsr d_abs
        bcs @big
        sta d_ay
        ldy d_ax
        lda sq_lo,y
        ldy d_ay
        clc
        adc sq_lo,y
        sta d2
        ldy d_ax
        lda sq_hi,y
        ldy d_ay
        adc sq_hi,y
        sta d2 + 1
        rts
@big:   lda #$FF
        sta d2
        sta d2 + 1
        rts

; d_abs: |A:tmp| (high, low) as A, carry set when 64 or more
d_abs:
        bpl :+
        eor #$FF                ; negative: -(hi:lo)
        pha
        lda tmp
        eor #$FF
        clc
        adc #1
        sta tmp
        pla
        adc #0
:       bne @big
        lda tmp
        cmp #64
        rts
@big:   sec
        rts

; dribble: the ball kicked on ahead, the way the joystick's player runs
dribble:
        ldy o_dir,x
        cpy drib_dir
        beq :+
        sty drib_dir
        lda #0
        sta drib_n
:       lda drib_n
        lsr a
        lsr a
        cmp #3
        bcc :+
        lda #3
:       tay
        lda drib_lo,y
        sta o_spl + BALL
        lda drib_hi,y
        sta o_sph + BALL
        inc drib_n
        bne :+
        dec drib_n
:       ldy drib_dir
        jsr ball_ahead
        lda o_dzl + BALL        ; no longer rising
        bmi :+
        ora o_dzf + BALL
        beq :+
        lda #$FF
        sta o_dzl + BALL
        sta o_dzf + BALL
:       rts

; ball_ahead: the ball's destination 1000 pixels from it, way Y
ball_ahead:
        lda o_xl + BALL
        clc
        adc vec_xl,y
        sta o_txl + BALL
        lda o_xh + BALL
        adc vec_xh,y
        sta o_txh + BALL
        lda o_yl + BALL
        clc
        adc vec_yl,y
        sta o_tyl + BALL
        lda o_yh + BALL
        adc vec_yh,y
        sta o_tyh + BALL
        rts

; pass: the ball to the nearest team-mate within 22.5 degrees of the way
; the joystick's player faces; or straight on
pass:
        lda #$FF
        sta mate
        sta mate_d
        sta mate_d + 1
        ldy ctrl                ; the way he kicks, 0-255
        lda o_dir,y
        asl a
        asl a
        asl a
        asl a
        asl a
        sta kick_way
        ldx #10
@look:  cpx ctrl
        beq @next
        jsr mate_way            ; the way from the ball to him, 0-255
        bcs @next               ; (on the ball)
        sec
        sbc kick_way            ; within 16 of the way he kicks
        clc
        adc #16
        cmp #33
        bcs @next
        jsr mate_dist           ; the nearest
        lda tmp
        cmp mate_d
        lda tmp + 1
        sbc mate_d + 1
        bcs @next
        lda tmp
        sta mate_d
        lda tmp + 1
        sta mate_d + 1
        stx mate
@next:  dex
        bpl @look
        ldx mate
        bpl :+
        jmp @none
:       ; at him: the ball's destination 32 times as far as he is
        lda o_xl,x
        sec
        sbc o_xl + BALL
        sta tmp
        lda o_xh,x
        sbc o_xh + BALL
        ldy #5
:       asl tmp
        rol a
        dey
        bne :-
        sta tmp + 1
        lda tmp
        clc
        adc o_xl + BALL
        sta o_txl + BALL
        lda tmp + 1
        adc o_xh + BALL
        sta o_txh + BALL
        lda o_yl,x
        sec
        sbc o_yl + BALL
        sta tmp
        lda o_yh,x
        sbc o_yh + BALL
        ldy #5
:       asl tmp
        rol a
        dey
        bne :-
        sta tmp + 1
        lda tmp
        clc
        adc o_yl + BALL
        sta o_tyl + BALL
        lda tmp + 1
        adc o_yh + BALL
        sta o_tyh + BALL
        ; as hard as he is far: under 99 pixels, under 240, more
        ldy #0
        lda mate_d
        cmp #<9800
        lda mate_d + 1
        sbc #>9800
        bcc @hard
        iny
        lda mate_d
        cmp #<57801
        lda mate_d + 1
        sbc #>57801
        bcc @hard
        iny
@hard:  lda pass_lo,y
        sta o_spl + BALL
        lda pass_hi,y
        sta o_sph + BALL
        jmp @kicked
@none:  ldx ctrl
        ldy o_dir,x
        jsr ball_ahead
        lda #<1792
        sta o_spl + BALL
        lda #>1792
        sta o_sph + BALL
@kicked:
        lda #0
        sta o_zl + BALL
        sta o_zf + BALL
        sta o_dzl + BALL
        sta o_dzf + BALL
        lda #$FF
        sta drib_dir
        lda #8                  ; the next player soon
        sta switch_t
        rts

pass_lo:    .byte <1536, <1792, <2048
pass_hi:    .byte >1536, >1792, >2048

; mate_way: the way from the ball to player X, 0 up .. 255 clockwise, in
; A; carry set when he is on it. Keeps X.
mate_way:
        lda o_xl,x
        sec
        sbc o_xl + BALL
        sta z_ax
        lda o_xh,x
        sbc o_xh + BALL
        sta z_ax + 1
        lda o_yl,x
        sec
        sbc o_yl + BALL
        sta z_ay
        lda o_yh,x
        sbc o_yh + BALL
        sta z_ay + 1
        jsr angle
        bcs :+
        lda #128                ; theta to the way: (128 - theta) & 255
        sec
        sbc z_th
        clc
:       rts

; mate_dist: tmp = the distance squared from the ball to player X, $FFFF
; from 256 either way. Keeps X.
mate_dist:
        lda o_xl,x
        sec
        sbc o_xl + BALL
        sta tmp
        lda o_xh,x
        sbc o_xh + BALL
        jsr abs16
        bne @far
        tay
        lda sq8_lo,y
        sta mate_t
        lda sq8_hi,y
        sta mate_t + 1
        lda o_yl,x
        sec
        sbc o_yl + BALL
        sta tmp
        lda o_yh,x
        sbc o_yh + BALL
        jsr abs16
        bne @far
        tay
        lda sq8_lo,y
        clc
        adc mate_t
        sta tmp
        lda sq8_hi,y
        adc mate_t + 1
        sta tmp + 1
        bcs @far
        rts
@far:   lda #$FF
        sta tmp
        sta tmp + 1
        rts

; abs16: |A:tmp| - the low byte in A, the high byte in the flags (Z: under
; 256)
abs16:
        bpl :+
        eor #$FF
        pha
        lda tmp
        eor #$FF
        clc
        adc #1
        sta tmp
        pla
        adc #0
:       tay
        lda tmp
        cpy #0
        rts

; ---- moving ---------------------------------------------------------------

; player_move: player X a frame towards his destination, his running
; picture on
player_move:
        lda o_spl,x
        ora o_sph,x
        bne :+
        lda #0                  ; standing
        sta o_step,x
        rts
:       jsr aim
        ldx z_obj
        jsr step
        dec o_run,x             ; a step every four frames
        bpl :+
        lda #3
        sta o_run,x
        inc o_step,x
:       rts

; ball_move: the ball a frame - see the top
ball_move:
        ldx #BALL
        stx z_obj
        lda o_xf,x              ; where it was, for the walls
        sta old_x
        lda o_xl,x
        sta old_x + 1
        lda o_xh,x
        sta old_x + 2
        lda o_yf,x
        sta old_y
        lda o_yl,x
        sta old_y + 1
        lda o_yh,x
        sta old_y + 2
        lda o_zf,x
        sta old_z
        lda o_zl,x
        sta old_z + 1
        lda o_spl,x
        ora o_sph,x
        beq @height
        jsr aim
        ldx #BALL
        ; friction: 16 on the ground, 10 in the air
        ldy #16
        lda o_zl,x
        beq :+
        ldy #10
:       sty tmp
        lda o_spl,x
        sec
        sbc tmp
        sta o_spl,x
        lda o_sph,x
        sbc #0
        sta o_sph,x
        bcs :+
        lda #0
        sta o_spl,x
        sta o_sph,x
:       jsr step
        ; turning: a picture on every 8 pixels of speed's worth
        lda o_run,x
        clc
        adc o_sph,x
        sta o_run,x
        bcc @height
        inc o_step,x
@height:
        ldx #BALL
        lda o_dzf,x
        ora o_dzl,x
        bne :+
        jmp @walls              ; lying, or rolling
:       lda o_dzf,x             ; gravity
        sec
        sbc #$12
        sta o_dzf,x
        bcs :+
        dec o_dzl,x
:       lda o_zf,x
        clc
        adc o_dzf,x
        sta o_zf,x
        lda o_zl,x
        adc o_dzl,x
        sta o_zl,x
        bmi :+
        jmp @walls
:       ; landed: a quarter of the speed lost, a bounce of 5/8
        lda o_sph,x             ; speed - speed / 4
        lsr a
        sta tmp + 1
        lda o_spl,x
        ror a
        lsr tmp + 1
        ror a
        sta tmp
        lda o_spl,x
        sec
        sbc tmp
        sta o_spl,x
        lda o_sph,x
        sbc tmp + 1
        sta o_sph,x
        lda #0
        sta o_zl,x
        sta o_zf,x
        lda #0                  ; dz = -dz
        sec
        sbc o_dzf,x
        sta o_dzf,x
        lda #0
        sbc o_dzl,x
        sta o_dzl,x
        ; - 3/8 of it: dz / 4 + dz / 8
        lsr a
        sta tmp + 1
        lda o_dzf,x
        ror a
        lsr tmp + 1
        ror a
        sta tmp
        lda tmp + 1
        sta z_p
        lsr z_p
        lda tmp
        ror a
        clc
        adc tmp
        sta tmp
        lda z_p
        adc tmp + 1
        sta tmp + 1
        lda o_dzf,x
        sec
        sbc tmp
        sta o_dzf,x
        lda o_dzl,x
        sbc tmp + 1
        sta o_dzl,x
        ; too little to bounce: it lies
        bne @walls
        lda o_dzf,x
        cmp #$A1
        bcs @walls
        lda #0
        sta o_dzf,x
@walls: ; past the walls round the pitch: back, half the speed, the
        ; destination mirrored about it
        lda o_xl,x
        cmp #<19
        lda o_xh,x
        sbc #>19
        bcc @xwall
        lda #<588
        cmp o_xl,x
        lda #>588
        sbc o_xh,x
        bcs @y
@xwall: lda o_xl,x              ; dest = 2x - dest
        asl a
        sta tmp
        lda o_xh,x
        rol a
        sta tmp + 1
        lda tmp
        sec
        sbc o_txl,x
        sta o_txl,x
        lda tmp + 1
        sbc o_txh,x
        sta o_txh,x
        jsr ball_back
@y:     lda o_yl,x
        cmp #<20
        lda o_yh,x
        sbc #>20
        bcc @ywall
        lda #<719
        cmp o_yl,x
        lda #>719
        sbc o_yh,x
        bcs @done
@ywall: lda o_yl,x
        asl a
        sta tmp
        lda o_yh,x
        rol a
        sta tmp + 1
        lda tmp
        sec
        sbc o_tyl,x
        sta o_tyl,x
        lda tmp + 1
        sbc o_tyh,x
        sta o_tyh,x
        jsr ball_back
@done:  rts

; ball_back: the ball back where it was, at half the speed
ball_back:
        lsr o_sph,x
        ror o_spl,x
        lda old_x
        sta o_xf,x
        lda old_x + 1
        sta o_xl,x
        lda old_x + 2
        sta o_xh,x
        lda old_y
        sta o_yf,x
        lda old_y + 1
        sta o_yl,x
        lda old_y + 2
        sta o_yh,x
        lda old_z
        sta o_zf,x
        lda old_z + 1
        sta o_zl,x
        rts

; step: object X on by its step
step:
        lda o_vxl,x             ; (sign-extended)
        and #$80
        beq :+
        lda #$FF
:       sta tmp
        lda o_xf,x
        clc
        adc o_vxf,x
        sta o_xf,x
        lda o_xl,x
        adc o_vxl,x
        sta o_xl,x
        lda o_xh,x
        adc tmp
        sta o_xh,x
        lda o_vyl,x
        and #$80
        beq :+
        lda #$FF
:       sta tmp
        lda o_yf,x
        clc
        adc o_vyf,x
        sta o_yf,x
        lda o_yl,x
        adc o_vyl,x
        sta o_yl,x
        lda o_yh,x
        adc tmp
        sta o_yh,x
        rts

; aim: object X's step from the way to its destination and its speed,
; and the way it faces (players)
aim:
        lda o_txl,x
        sec
        sbc o_xl,x
        sta z_ax
        lda o_txh,x
        sbc o_xh,x
        sta z_ax + 1
        lda o_tyl,x
        sec
        sbc o_yl,x
        sta z_ay
        lda o_tyh,x
        sbc o_yh,x
        sta z_ay + 1
        cmp c_ayh,x             ; the way and the speed as last frame:
        bne @new                ; the step as it is
        lda z_ay
        cmp c_ayl,x
        bne @new
        lda z_ax
        cmp c_axl,x
        bne @new
        lda z_ax + 1
        cmp c_axh,x
        bne @new
        lda o_spl,x
        cmp c_spl,x
        bne @new
        lda o_sph,x
        cmp c_sph,x
        bne @new
        rts
@new:   lda z_ax
        sta c_axl,x
        lda z_ax + 1
        sta c_axh,x
        lda z_ay
        sta c_ayl,x
        lda z_ay + 1
        sta c_ayh,x
        lda o_spl,x
        sta c_spl,x
        lda o_sph,x
        sta c_sph,x
        jsr angle
        bcc :+
        lda #0                  ; there: no step
        sta o_vxf,x
        sta o_vxl,x
        sta o_vyf,x
        sta o_vyl,x
        rts
:       lda #128                ; the way it faces: ((128 - theta) + 16) / 32
        sec
        sbc z_th
        clc
        adc #16
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        cpx #BALL
        beq :+
        sta o_dir,x
:       lda o_spl,x
        sta smul_l
        lda o_sph,x
        sta smul_h
        ldy z_th
        lda sin_tab,y
        jsr smul
        lda z_p + 1
        sta o_vxf,x
        lda z_p + 2
        sta o_vxl,x
        lda z_th
        clc
        adc #64
        tay
        lda sin_tab,y
        jsr smul
        lda z_p + 1
        sta o_vyf,x
        lda z_p + 2
        sta o_vyl,x
        rts

; angle: z_th = the angle (256 to the circle, 0 down, 64 right,
; clockwise from below the way Sensible Soccer counts) of the way z_ax,
; z_ay; carry set when both are 0. Keeps X.
angle:
        lda z_ax + 1
        sta z_sx
        bpl :+
        lda #0
        sec
        sbc z_ax
        sta z_ax
        lda #0
        sbc z_ax + 1
        sta z_ax + 1
:       lda z_ay + 1
        sta z_sy
        bpl :+
        lda #0
        sec
        sbc z_ay
        sta z_ay
        lda #0
        sbc z_ay + 1
        sta z_ay + 1
:                               ; halved till both are under 32
@half:  lda z_ax + 1
        ora z_ay + 1
        bne :+
        lda z_ax
        ora z_ay
        and #$E0
        beq @look
:       lsr z_ax + 1
        ror z_ax
        lsr z_ay + 1
        ror z_ay
        jmp @half
@look:  lda z_ay                ; atan_tab[ay * 32 + ax]
        lsr a
        lsr a
        lsr a
        clc
        adc #>atan_tab
        sta z_ptr + 1
        lda z_ay
        asl a
        asl a
        asl a
        asl a
        asl a
        ora z_ax
        tay
        lda #<atan_tab
        sta z_ptr
        lda (z_ptr),y
        cmp #$FF
        beq @none
        sta z_th
        lda z_sx
        bmi @left
        lda z_sy
        bmi :+
        lda #64                 ; right, down: 64 - a
        sec
        sbc z_th
        jmp @set
:       lda #64                 ; right, up: 64 + a
        clc
        adc z_th
        jmp @set
@left:  lda z_sy
        bmi :+
        lda #192                ; left, down: 192 + a
        clc
        adc z_th
        jmp @set
:       lda #192                ; left, up: 192 - a
        sec
        sbc z_th
@set:   sta z_th
        clc
        rts
@none:  sec
        rts

; smul: z_p (24 bits, signed) = A (signed) * smul_l/h; the step is its
; upper two bytes. Two products of bytes from tables of squares / 4 (a * b
; = (a + b)^2 / 4 - (a - b)^2 / 4). Keeps X.
smul:
        sta z_ms
        bpl :+
        eor #$FF
        clc
        adc #1
:       sta z_m
        lda smul_l              ; |A| * the low byte
        jsr mul8
        lda z_q
        sta z_p
        lda z_q + 1
        sta z_p + 1
        lda smul_h              ; and the high byte, 8 bits up
        jsr mul8
        lda z_p + 1
        clc
        adc z_q
        sta z_p + 1
        lda z_q + 1
        adc #0
        sta z_p + 2
        lda z_ms
        bpl :+
        lda #0
        sec
        sbc z_p
        sta z_p
        lda #0
        sbc z_p + 1
        sta z_p + 1
        lda #0
        sbc z_p + 2
        sta z_p + 2
:       rts

; mul8: z_q = z_m * A (bytes, unsigned). Keeps X.
mul8:
        sta z_b
        clc
        adc z_m
        tay
        bcs @hi
        lda qs_lo,y             ; (a + b)^2 / 4
        sta z_q
        lda qs_hi,y
        sta z_q + 1
        jmp @sub
@hi:    lda qs_lo + 256,y
        sta z_q
        lda qs_hi + 256,y
        sta z_q + 1
@sub:   lda z_b                 ; - (a - b)^2 / 4
        sec
        sbc z_m
        bcs :+
        eor #$FF
        adc #1
:       tay
        lda z_q
        sec
        sbc qs_lo,y
        sta z_q
        lda z_q + 1
        sbc qs_hi,y
        sta z_q + 1
        rts

; ---- whose the joystick is ------------------------------------------------

; switch: every few frames, the joystick to the team's player nearest the
; ball (not the keeper), unless the one it has is close to it
switch:
        dec switch_t
        bpl @done
        lda #4
        sta switch_t
        ldx ctrl
        jsr dist2
        lda d2 + 1
        bne :+
        lda d2
        cmp #CLOSE + 1
        bcc @done
:       lda #$FF
        sta mate_d
        sta mate_d + 1
        ldx #10
@look:  jsr mate_dist
        lda tmp
        cmp mate_d
        lda tmp + 1
        sbc mate_d + 1
        bcs :+
        lda tmp
        sta mate_d
        lda tmp + 1
        sta mate_d + 1
        stx mate
:       dex
        bne @look
        lda mate_d
        and mate_d + 1
        cmp #$FF
        beq @done               ; (all far: keep him)
        ldx ctrl
        cpx mate
        beq @done
        jsr stand               ; the last one stops where he is
        lda mate
        sta ctrl
@done:  rts
