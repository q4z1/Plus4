; play.s - the match: the players and the ball, a frame at a time (50 a
; second), as Sensible Soccer moves them
;
; The game runs on Sensible Soccer's pitch and in its units: touchlines
; at x 49 and 558, goal lines at y 49 and 689, the centre spot at 304,
; 369; simple-soccer.s shows it on the C64's ground (ymap_*). Positions are
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

        .export play_init, play_frame, score
        .export dbg_on, dbg_i, dbg_t, dbg_bits, dbg_plan
        .export o_xl, o_xh, o_yl, o_yh, o_zl, o_dir, o_step, o_spl, ctrl
        .import joy, atan_tab, sin_tab
        .import tac_x0l, tac_x0h, tac_xs, tac_y0l, tac_y0h, tac_ys

PLAYERS     = 22                ; 0-10 the joystick's team, from its keeper
BALL        = PLAYERS           ; the last object
NOBJ        = PLAYERS + 1

SPEED_RUN   = $04E0             ; a player running
SPEED_BALL  = 896               ; and with the ball at his feet
SPEED_JOG   = 1024              ; going to his place
LINE_L      = 49                ; the touch lines and goal lines
LINE_R      = 558
LINE_T      = 49
LINE_B      = 689
POST_L      = 263               ; between the posts (with the ball's width)
POST_R      = 340
BAR_Z       = 17                ; under the bar
NET         = 12                ; the net this far behind the line
DEAD_OUT    = 50                ; frames the ball is dead after going out,
DEAD_GOAL   = 125               ; after a goal
CPU_WAIT    = 20                ; the yellow team's set pieces: after 40 frames
R_KICKOFF   = 0                 ; restarts
R_THROW     = 1
R_GOALKICK  = 2
R_CORNER    = 3
R_KEEPER    = 4                 ; (the keeper has it)
SPEED_DIVE  = 1280              ; the keeper going for a shot
RECV_T      = 100               ; frames a pass's receiver runs to meet it
HOLD_T      = 8                 ; a ball touched this few frames ago is held,
HOLD_D2     = 144               ; and one this near (squared) the player who
HOLD_Z      = 12                ; touched it, this low: the other team
                                ; takes it only by a tackle
SLIDE_T     = 50                ; a sliding tackle's frames,
SPEED_SLIDE = 1792              ; its speed at first,
SLIDE_DECEL = 48                ; less each frame,
SLIDE_REACH = 225               ; the ball this near (squared) it reaches,
SLIDE_Z     = 8                 ; this low
SLIDE_FROM  = 576               ; the yellow chaser slides from 24 away,
SLIDE_WAIT  = 100               ; and not again for so many frames
KEEPER_SEES = 32                ; the keeper goes for a ball this near his line
CATCH_X     = 8                 ; the keeper catches the ball this near,
CATCH_Y     = 6
CATCH_Z     = 13                ; and under this high (a lob goes over him)
SLACK       = 2                 ; a place this near the last one is the same
SPEED_CHASE = 1102              ; after the ball
SHOOT_FROM  = 150               ; the other team shoots from this near
NEAR        = 32                ; distance squared: the ball at his feet
CLOSE       = 72                ; near enough to kick it
KICK_Z      = 4                 ; and low enough
SHOT_HOLD   = 9                 ; frames fire is held for a shot
SHOT_SPEED  = 2208
SHOT_DZ     = $0140             ; its rise, 8.8: 1.25
LIFT_DZ     = $0160             ; the aftertouch's lift: 1.375,
LIFT_HI_DZ  = $0200             ;   pulled back 2

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
z_t8:       .res 1
z_px:       .res 2              ; place_formation's place
z_ti:       .res 1              ; (its index into the tables)
z_ks:       .res 2              ; keeper's speed,
z_sg:       .res 1              ; k_shot's sign across
z_dvd:      .res 2              ; div16's: dividend, then quotient,
z_dvs:      .res 2              ; divisor,
z_rem:      .res 2              ; remainder
z_py:       .res 2
z_nf:       .res 1              ; play_others': frames at once
z_f2:       .res 2              ; mul_f's
z_f10:      .res 2
z_f16:      .res 2
smul_l:     .res 1              ; smul's multiplier
smul_h:     .res 1
z_q:        .res 2              ; mul8's product
z_qp:       .res 2              ; mul8's pointers into its tables: qs_lo + a,
z_qph:      .res 2              ; qs_hi + a, qn_lo + 255 - a, qn_hi + 255 - a
z_qn:       .res 2
z_qnh:      .res 2
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
o_mov:  .res NOBJ               ; players: 1 while on the way somewhere
o_new:  .res NOBJ               ; 1: a new destination, the way not yet worked out
o_slide: .res NOBJ              ; frames left of a sliding tackle, 0 none
o_hit:  .res NOBJ               ; 1: the tackle has reached the ball
c_axl:  .res NOBJ               ; aim's last way and speed: the same
c_axh:  .res NOBJ               ; again, the step is still right
c_ayl:  .res NOBJ
c_ayh:  .res NOBJ
c_spl:  .res NOBJ
c_sph:  .res NOBJ
c_txl:  .res NOBJ               ; its last destination, and the angle to it
c_txh:  .res NOBJ               ; ($FF: there)
c_tyl:  .res NOBJ
c_tyh:  .res NOBJ
c_th:   .res NOBJ

ctrl:       .res 1              ; the joystick's player
fire_n:     .res 1              ; frames fire has been held
frame_n:    .res 1              ; frames played
b_th:       .res 1              ; the ball's angle, speed, product's low
b_spl:      .res 1              ; bytes as aim last worked them out,
b_sph:      .res 1
b_px0:      .res 1
b_py0:      .res 1
b_d:        .res 8              ; and sin * 16 (x, y), sin * 10 (x, y)
kickoff:    .res 1              ; 1 till the kick-off or set piece is taken
taker:      .res 1              ; who takes it, $FF none
dead_t:     .res 1              ; frames the ball is still dead, 0 in play
goal:       .res 1              ; 1: dead for a goal - the net holds the ball
rs_kind:    .res 1              ; the restart (R_*),
rs_team:    .res 1              ; for which team,
rs_x:       .res 2              ; where
rs_y:       .res 2
cpu_t:      .res 1              ; the yellow team's: till they take it
last_team:  .res 1              ; who touched the ball last: the team,
last_pl:    .res 1              ; the player
touch_t:    .res 1              ; frames since the ball was touched
hd_x:       .res 1              ; (held's)
hd_y:       .res 1
cpu_slide:  .res 1              ; frames till the yellow chaser may slide again
recv:       .res 1              ; the cyan player a pass went to, $FF none,
recv_t:     .res 1              ; and the frames he still goes to meet it
score:      .res 2              ; goals, cyan and yellow
r_t:        .res 1              ; the rules': attackers, the team's last
; a test's plan for the joystick, by the match's frames: (frame low, high,
; J_ bits) each, $FFFF the end; dbg_on set to 2 starts it - the frames
; counted from then, and the match's own counters from 0 too, so that it
; goes the same way in any emulator
dbg_on:     .res 1
dbg_i:      .res 1              ; the next entry's place
dbg_t:      .res 2              ; frames since
dbg_bits:   .res 1              ; the stick as the plan has it
dbg_plan:   .res 3 * 64
chaser:     .res 1              ; the other team's player after the ball,
                                ; $FF none
formation:  .res 2              ; each team's (data/tactics.txt), 0 4-4-2
at_n:       .res 1              ; the aftertouch's frame, $FF none
at_dir:     .res 1              ; the shot's way
at_side:    .res 1              ; the side it bends to, $FF none yet
at_j:       .res 1              ; the joystick's way
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
; 4-4-2 for the kick-off: keeper, defence, midfield, attack, one forward
; at the ball; x as the yellow team stands, y as the cyan team (line_up
; mirrors x for the cyan team, y for the yellow)
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
        lda #>qs_lo             ; mul8's tables
        sta z_qp + 1
        lda #>qs_hi
        sta z_qph + 1
        lda #>qn_lo
        sta z_qn + 1
        lda #>qn_hi
        sta z_qnh + 1
        jsr line_up
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
        lda #9                  ; the cyan team kicks off
        sta ctrl
        sta taker
        lda #$FF                ; no aftertouch, no one after the ball
        sta at_n
        sta chaser
        sta recv
        lda #1
        sta kickoff
        rts

; line_up: both teams lined up for a kick-off, standing
line_up:
        ldx #0
@pl:    txa
        asl a
        tay
        lda line_x,y            ; (the yellow team as the line; the cyan
        sta o_xl + 11,x         ; team, facing the other way, mirrored:
        lda line_x + 1,y        ; 608 - x - its right back on the right)
        sta o_xh + 11,x
        lda #<608
        sec
        sbc line_x,y
        sta o_xl,x
        lda #>608
        sbc line_x + 1,y
        sta o_xh,x
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
        lda #0
        sta o_xf,x
        sta o_yf,x
        sta o_xf + 11,x
        sta o_yf + 11,x
        inx
        cpx #11
        bne @pl
        ldx #PLAYERS - 1        ; standing where they are
:       jsr stand
        dex
        bpl :-
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
        sta o_mov,x
        sta o_step,x            ; (the standing picture)
        sta o_vxf,x
        sta o_vxl,x
        sta o_vyf,x
        sta o_vyl,x
        rts

; ---- a frame --------------------------------------------------------------

play_frame:
        inc frame_n
        lda dbg_on              ; (a test's plan: the stick as it says,
        beq :+                  ; frame by frame)
        jsr dbg_step
:
        lda dead_t              ; the ball dead: it rolls on, no one has
        beq @live               ; it, the others go to their places
        dec dead_t
        bne :+
        jmp restart
:       lda frame_n
        lsr a
        bcs :+
        jsr team_ai
:       jsr keepers_move
        jsr others
        jsr ball_move
        jmp net
@live:  lda touch_t             ; (frames since the ball's last touch)
        cmp #255
        beq :+
        inc touch_t
:       lda cpu_slide
        beq :+
        dec cpu_slide
:       jsr control
        lda frame_n             ; the others' minds every second frame, as
        lsr a                   ; Sensible Soccer's
        bcs :+
        jsr team_ai
:       jsr slides
        ldx ctrl                ; the two at the ball and the keepers,
        jsr @one                ; every frame
        ldx chaser
        bmi :+
        jsr @one
:       jsr keepers_move
        jsr others
        jsr aftertouch
        jsr ball_move
        jsr catch
        jsr rules
        lda frame_n
        lsr a
        bcs :+
        jmp switch              ; (every second frame)
:       rts
@one:   lda o_mov,x
        beq :+
        stx z_obj
        jsr player_move
:       rts

; dbg_step: the joystick a frame on in a test's plan
dbg_step:
        lda dbg_on
        cmp #2
        bne :+
        lda #1                  ; (starting)
        sta dbg_on
        sta frame_n
        lda #0
        sta dbg_t
        sta dbg_t + 1
        sta dbg_i
        sta dbg_bits
        sta switch_t
:       inc dbg_t
        bne :+
        inc dbg_t + 1
:       ldy dbg_i
@look:  lda dbg_t + 1           ; its next entry due: taken
        cmp dbg_plan + 1,y
        bcc @hold
        bne @take
        lda dbg_t
        cmp dbg_plan,y
        bcc @hold
@take:  lda dbg_plan + 2,y
        sta dbg_bits
        iny
        iny
        iny
        sty dbg_i
        bne @look
@hold:  lda dbg_bits
        sta joy
        rts

; others: the others moved, every frame
others  = play_others

; keepers_move: both keepers a frame (unless one is the joystick's or the
; chaser, moved already)
keepers_move:
        ldx #0
        jsr @one
        ldx #11
@one:   cpx ctrl
        beq :+
        cpx chaser
        beq :+
        lda o_mov,x
        beq :+
        stx z_obj
        jsr player_move
:       rts

; play_others: everyone else on his way somewhere a frame on - all of
; them every frame, as the ball: each picture shows them where they are
play_others:
        lda #1                  ; (a frame of running picture)
        sta z_nf
        ldx #PLAYERS - 1
@pl:    stx z_obj
        txa                     ; (the keepers, the two at the ball: their
        beq @next               ; own way)
        cpx #11
        beq @next
        cpx ctrl
        beq @next
        cpx chaser
        beq @next
        lda o_mov,x             ; (those standing passed over)
        beq @next
        lda o_new,x             ; the way anew only for a new destination:
        beq :+                  ; on a straight run it stays the same
        lda #0
        sta o_new,x
        jsr aim
        ldx z_obj
:       jsr step
        jsr arrive
        lda o_vxf,x             ; there: the standing picture, passed over
        ora o_vxl,x             ; till he has somewhere to go
        ora o_vyf,x
        ora o_vyl,x
        bne :+
        sta o_step,x
        sta o_mov,x
        beq @next
:       jsr stride
@next:  ldx z_obj
        dex
        bpl @pl
        rts

; control: the joystick's player - where he runs, dribbling, fire
control:
        lda recv_t
        beq :+
        dec recv_t
:       ldx ctrl
        lda o_slide,x           ; (sliding: the stick has no say)
        beq :+
        rts
:       lda kickoff             ; the cyan team's set piece: the stick
        beq @stick              ; turns the taker, fire kicks
        lda rs_team
        bne @stick
        lda joy
        and #$0F
        tay
        lda joy_dir,y
        cmp #8
        beq :+
        sta o_dir,x
:       jmp @fire
@stick: lda joy
        and #$0F
        tay
        lda joy_dir,y
        cmp #8
        bne @run
        jsr meet                ; the stick let go: he stops, or meets a
        lda #$FF                ; pass, or stops the ball at his feet
        sta drib_dir
        jmp @fire
@run:   sta o_dir,x
        tay
        lda #1
        sta o_mov,x
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
        jsr inside
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
        lda frame_n             ; (a touch every second frame)
        lsr a
        bcs @far
        lda kickoff             ; (not the other team's set piece)
        bne @far
        lda #0                  ; (nor while the other team holds it)
        jsr held
        bcs @far
        jsr dribble
@far:   lda kickoff
        bne @done
@fire:  lda joy                 ; fire: let go within SHOT_HOLD - 1
        and #J_FIRE             ; frames a pass, held SHOT_HOLD frames
        beq @let                ; a shot - as soon as the ball is at his
        lda fire_n              ; feet, once held so long
        cmp #$FF
        beq @done               ; (shot)
        cmp #SHOT_HOLD
        bcs :+
        inc fire_n
        lda fire_n
        cmp #1                  ; just pressed, the other team holding the
        bne @held               ; ball: a sliding tackle
        lda kickoff
        bne @held
        lda #0
        jsr held
        bcc @held
        lda #$FF
        sta fire_n
        ldx ctrl
        jmp slide
@held:  lda fire_n
        cmp #SHOT_HOLD
        bne @done
:       jsr can_kick
        bcs @done
        lda #$FF
        sta fire_n
        jmp shot
@let:   lda fire_n
        ldy #0
        sty fire_n
        cmp #1
        bcc @done               ; (not held)
        cmp #SHOT_HOLD
        bcs @done               ; (the shot taken, or held for one)
        jsr can_kick
        bcs @done
        jmp pass
@done:  rts

; meet: the joystick's player X, the stick let go: a ball come to his
; feet from someone else he stops there; a pass to him he goes to meet;
; else he stands. Keeps X.
meet:
        jsr dist2
        lda last_pl             ; (his own kick runs on)
        cmp ctrl
        beq @stand
        lda #0                  ; (one the other team holds: only a tackle)
        jsr held
        bcs @go
        lda d2 + 1
        bne @go
        lda d2
        cmp #NEAR + 1
        bcs @go
        lda o_zl + BALL
        cmp #13
        bcs @go
        ldx #BALL               ; at his feet: stopped there, his
        jsr stand
        lda ctrl
        sta last_pl
        lda #0
        sta last_team
        jsr touch
        lda #$FF
        sta recv
        ldx ctrl
        jmp stand
@go:    cpx recv                ; a pass to him: after it, while it runs
        bne @stand
        lda recv_t
        beq @stand
        lda o_xl + BALL
        sta o_txl,x
        lda o_xh + BALL
        sta o_txh,x
        lda o_yl + BALL
        sta o_tyl,x
        lda o_yh + BALL
        sta o_tyh,x
        lda #<SPEED_RUN
        sta o_spl,x
        lda #>SPEED_RUN
        sta o_sph,x
        lda #1
        sta o_mov,x
        rts
@stand: jmp stand

; inside: player X's destination inside the walls round the pitch (the
; ball's, x 19-588, y 20-719) - no one runs into the stands. Keeps X.
inside:
        lda o_txh,x
        bmi @x0
        lda o_txl,x
        cmp #<19
        lda o_txh,x
        sbc #>19
        bcs :+
@x0:    lda #<19
        sta o_txl,x
        lda #>19
        sta o_txh,x
:       lda #<588
        cmp o_txl,x
        lda #>588
        sbc o_txh,x
        bcs :+
        lda #<588
        sta o_txl,x
        lda #>588
        sta o_txh,x
:       lda o_tyh,x
        bmi @y0
        lda o_tyl,x
        cmp #<20
        lda o_tyh,x
        sbc #>20
        bcs :+
@y0:    lda #<20
        sta o_tyl,x
        lda #>20
        sta o_tyh,x
:       lda #<719
        cmp o_tyl,x
        lda #>719
        sbc o_tyh,x
        bcs :+
        lda #<719
        sta o_tyl,x
        lda #>719
        sta o_tyh,x
:       rts

; can_kick: carry clear if the joystick's player can kick the ball: at
; his feet, near enough, and low. Keeps X.
can_kick:
        jsr dist2
        lda d2 + 1
        bne @no
        lda d2
        cmp #CLOSE + 1
        bcs @no
        lda o_zl + BALL
        cmp #KICK_Z + 1
        rts
@no:    sec
        rts

; shot: the ball the way the joystick's player faces, hard and rising;
; the aftertouch on
shot:
        lda #0
        sta last_team
        jsr touch
        lda ctrl
        sta last_pl
        ldx ctrl
        ldy o_dir,x
        sty at_dir
        jsr ball_ahead
        lda #<SHOT_SPEED
        sta o_spl + BALL
        lda #>SHOT_SPEED
        sta o_sph + BALL
        lda #<SHOT_DZ
        sta o_dzf + BALL
        lda #>SHOT_DZ
        sta o_dzl + BALL
        lda #0
        sta at_n
        lda #$FF
        sta drib_dir
        lda #4                  ; the next player soon (8 frames)
        sta switch_t
        rts

; aftertouch: for ten frames after a shot, the joystick bends it - the
; first way it is pushed across the shot (or across and back) sends the
; ball's destination that side, less each frame; and on the fifth frame
; pulled back it lifts the ball high and faster, let go or across a
; little less, pushed on not at all
aftertouch:
        ldx at_n
        bpl :+
        rts                     ; (none)
:       bne :+
        lda #$FF                ; frame 0: no side yet
        sta at_side
:       lda joy                 ; the joystick's way, 8 none
        and #$0F
        tay
        lda joy_dir,y
        sta at_j
        lda at_side
        bpl @bend
        lda at_j                ; no side yet: across the shot latches it
        cmp #8
        beq @lift
        lda at_dir
        sec
        sbc at_j
        and #7
        beq @lift               ; (on, or back: no side)
        cmp #4
        beq @lift
        lda #0
        bcc :+                  ; 1-3: side 0, 5-7: side 1
        lda #1
:       sta at_side
@bend:  lda at_dir              ; the destination on by curl * weight
        asl a
        ora at_side
        tay
        lda curl_x,y
        sta tmp
        lda curl_y,y
        sta tmp + 1
        ldy at_w,x
@add:   lda tmp
        jsr add_tx
        lda tmp + 1
        jsr add_ty
        dey
        bne @add
@lift:  ldx at_n
        cpx #4
        bne @next
        lda at_j
        cmp #8
        beq @mid                ; let go
        lda at_dir
        sec
        sbc at_j
        and #7
        cmp #2
        beq @mid                ; across
        cmp #6
        beq @mid
        cmp #3
        bcc @next               ; on: nothing
        cmp #6
        bcs @next
        lda #<LIFT_HI_DZ        ; back: high
        ldx #>LIFT_HI_DZ
        ldy #0
        beq @lifted
@mid:   lda #<LIFT_DZ
        ldx #>LIFT_DZ
        ldy #1
@lifted:
        sta o_dzf + BALL
        stx o_dzl + BALL
        lda lift_lo,y
        sta o_spl + BALL
        lda lift_hi,y
        sta o_sph + BALL
        lda at_dir              ; slower diagonally (7/8) and up or down (3/4)
        lsr a
        bcs @diag
        lda at_dir
        and #3
        bne @next
        jsr spd_quarter         ; up, down: - 1/4
        jmp @next
@diag:  lda o_sph + BALL        ; - 1/4 + 1/8
        lsr a
        sta tmp + 1
        lda o_spl + BALL
        ror a
        lsr tmp + 1
        ror a
        lsr tmp + 1
        ror a
        sta tmp                 ; speed / 8
        jsr spd_quarter
        lda o_spl + BALL
        clc
        adc tmp
        sta o_spl + BALL
        lda o_sph + BALL
        adc tmp + 1
        sta o_sph + BALL
@next:  inc at_n
        lda at_n
        cmp #10
        bne @done
        lda #$FF
        sta at_n
@done:  rts

; spd_quarter: the ball's speed less a quarter
spd_quarter:
        lda o_sph + BALL
        lsr a
        sta z_p
        lda o_spl + BALL
        ror a
        lsr z_p
        ror a
        sta z_p + 1             ; speed / 4: z_p + 1 low, z_p high
        lda o_spl + BALL
        sec
        sbc z_p + 1
        sta o_spl + BALL
        lda o_sph + BALL
        sbc z_p
        sta o_sph + BALL
        rts

; add_tx, add_ty: A (signed) onto the ball's destination. Keep X and Y.
add_tx:
        sta z_t8
        clc
        adc o_txl + BALL
        sta o_txl + BALL
        lda z_t8
        and #$80
        beq :+
        lda #$FF
:       adc o_txh + BALL
        sta o_txh + BALL
        rts
add_ty:
        sta z_t8
        clc
        adc o_tyl + BALL
        sta o_tyl + BALL
        lda z_t8
        and #$80
        beq :+
        lda #$FF
:       adc o_tyh + BALL
        sta o_tyh + BALL
        rts

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
        lda #0
        sta last_team
        jsr touch
        lda ctrl
        sta last_pl
        lda #$FF                ; (a pass met)
        sta recv
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
        lda #0
        sta last_team
        jsr touch
        lda ctrl
        sta last_pl
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
        bmi :+
        stx recv                ; the joystick to him, to meet it
        stx ctrl
        lda #RECV_T
        sta recv_t
        jmp kick_to
:       ldx ctrl                ; no one: straight on
        ldy o_dir,x
        jsr ball_ahead
        lda #<1792
        sta o_spl + BALL
        lda #>1792
        sta o_sph + BALL
        jmp kicked

; kick_to: the ball passed to player X, mate_d away (squared): its
; destination 32 times as far as he is
kick_to:
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
kicked: ; (on the ground)
        lda #0
        sta o_zl + BALL
        sta o_zf + BALL
        sta o_dzl + BALL
        sta o_dzf + BALL
        lda #$FF
        sta drib_dir
        lda #4                  ; the next player soon (8 frames)
        sta switch_t
        rts

; the aftertouch: the bend for each way of the shot and side, a step
; (times the frame's weight); the speeds of a lift, high and less high
curl_x:     .byte <(-32), 32, 0, 23, 0, 0, 23, 0, 32, <(-32), 0, <(-23), 0, 0, <(-23), 0
curl_y:     .byte 0, 0, <(-23), 0, <(-32), 32, 0, 23, 0, 0, 23, 0, 32, <(-32), 0, <(-23)
at_w:       .byte 5, 4, 3, 2, 2, 2, 2, 1, 1, 1
lift_lo:    .byte <2688, <2560
lift_hi:    .byte >2688, >2560
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
        tay
        lda #0
        sec
        sbc tmp
        sta tmp
        tya
        eor #$FF
        adc #0
:       tay
        lda tmp
        cpy #0
        rts

; ---- moving ---------------------------------------------------------------

; player_move: player X, moving, a frame towards his destination, his
; running picture on (stand puts the standing picture)
player_move:
        jsr aim
        ldx z_obj
        jsr step
        jsr arrive
        lda o_vxf,x             ; still: there - the standing picture, and
        ora o_vxl,x             ; passed over till he has somewhere to go
        ora o_vyf,x
        ora o_vyl,x
        bne :+
        sta o_step,x
        sta o_mov,x
        rts
:       lda o_slide,x           ; (sliding: the stride as it is)
        bne :+
        dec o_run,x             ; a step every four frames
        bpl :+
        lda #3
        sta o_run,x
        inc o_step,x
:       rts

; arrive: player X, if a step has taken him to his destination or past
; it on either axis, put on it there, that axis's step 0 (as Sensible
; Soccer stops its players)
arrive:
        lda o_vxl,x
        ora o_vxf,x
        beq @y
        lda o_xl,x              ; past it: (x - dest) has the step's sign,
        sec                     ; or is 0
        sbc o_txl,x
        sta tmp
        lda o_xh,x
        sbc o_txh,x
        eor o_vxl,x
        bmi @y                  ; (not there yet)
        lda o_txl,x
        sta o_xl,x
        lda o_txh,x
        sta o_xh,x
        lda #0
        sta o_xf,x
        sta o_vxf,x
        sta o_vxl,x
@y:     lda o_vyl,x
        ora o_vyf,x
        beq @done
        lda o_yl,x
        sec
        sbc o_tyl,x
        lda o_yh,x
        sbc o_tyh,x
        eor o_vyl,x
        bmi @done
        lda o_tyl,x
        sta o_yl,x
        lda o_tyh,x
        sta o_yh,x
        lda #0
        sta o_yf,x
        sta o_vyf,x
        sta o_vyl,x
@done:  rts

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
        ; the angle as last time: the same way to the destination (the
        ; joystick's player), or the same destination - he runs straight
        ; at it; the ball's anew each eighth frame, as rounding turns it a
        ; little on the way
        cmp c_ayh,x
        bne @dest
        lda z_ay
        cmp c_ayl,x
        bne @dest
        lda z_ax
        cmp c_axl,x
        bne @dest
        lda z_ax + 1
        cmp c_axh,x
        beq @same
@dest:  cpx #BALL               ; (the ball's angle anew each eighth frame)
        bne :+
        lda frame_n
        and #7
        beq @new
:
        lda o_txl,x
        cmp c_txl,x
        bne @new
        lda o_txh,x
        cmp c_txh,x
        bne @new
        lda o_tyl,x
        cmp c_tyl,x
        bne @new
        lda o_tyh,x
        cmp c_tyh,x
        bne @new
        jsr @keep               ; (the way changed: remembered)
@same:  lda o_spl,x             ; the angle and the speed as last time:
        cmp c_spl,x             ; the step as it is
        bne @step
        lda o_sph,x
        cmp c_sph,x
        bne @step
        rts
@new:   jsr @keep
        lda o_txl,x
        sta c_txl,x
        lda o_txh,x
        sta c_txh,x
        lda o_tyl,x
        sta c_tyl,x
        lda o_tyh,x
        sta c_tyh,x
        jsr angle
        bcc :+
        lda #$FF                ; there: no step
        sta c_th,x
        lda #0
        sta o_vxf,x
        sta o_vxl,x
        sta o_vyf,x
        sta o_vyl,x
        sta c_spl,x             ; (a speed of 0 noted: anew next time)
        sta c_sph,x
        rts
:       lda z_th
        sta c_th,x
        lda #128                ; the way it faces: ((128 - theta) + 16) / 32
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
        beq @step
        sta o_dir,x
@step:  lda c_th,x              ; the step: 127 sin * speed per axis
        cmp #$FF
        bne :+
        rts                     ; (at the destination)
:       cpx #BALL               ; the ball slowed only by its friction:
        bne @full               ; less of the same (fric)
        jsr fric
        bcs @full
        rts
@full:  lda o_spl,x
        sta c_spl,x
        sta smul_l
        lda o_sph,x
        sta c_sph,x
        sta smul_h
        ldy c_th,x
        lda sin_tab,y
        jsr smul
        lda z_p
        sta b_px0               ; (the ball's, for its friction)
        lda z_p + 1
        sta o_vxf,x
        lda z_p + 2
        sta o_vxl,x
        lda c_th,x
        clc
        adc #64
        tay
        lda sin_tab,y
        jsr smul
        lda z_p + 1
        sta o_vyf,x
        lda z_p + 2
        sta o_vyl,x
        cpx #BALL
        beq :+
        rts
:       lda z_p                 ; the ball's: noted for its friction
        sta b_py0
        lda c_th,x
        sta b_th
        lda o_spl,x
        sta b_spl
        lda o_sph,x
        sta b_sph
        ldy c_th,x              ; sin * 16 and * 10, per axis
        lda sin_tab,y
        jsr mul_f
        lda z_f16
        sta b_d
        lda z_f16 + 1
        sta b_d + 1
        lda z_f10
        sta b_d + 4
        lda z_f10 + 1
        sta b_d + 5
        lda c_th,x
        clc
        adc #64
        tay
        lda sin_tab,y
        jsr mul_f
        lda z_f16
        sta b_d + 2
        lda z_f16 + 1
        sta b_d + 3
        lda z_f10
        sta b_d + 6
        lda z_f10 + 1
        sta b_d + 7
        rts

@keep:  lda z_ax                ; the way to the destination remembered
        sta c_axl,x
        lda z_ax + 1
        sta c_axh,x
        lda z_ay
        sta c_ayl,x
        lda z_ay + 1
        sta c_ayh,x
        rts

; fric: carry clear if the ball's step could be had from the last one,
; the same way and the speed just its friction (16 or 10) less: sin *
; friction off the product (the step's two bytes and the one below) -
; the same as a new product, much cheaper. Keeps X.
fric:
        lda c_th,x
        cmp b_th
        bne @no
        lda b_spl
        sec
        sbc o_spl,x
        tay
        lda b_sph
        sbc o_sph,x
        bne @no
        cpy #16
        beq @f16
        cpy #10
        beq @f10
@no:    sec
        rts
@f10:   ldy #4                  ; (the deltas for 10)
        bne @fric
@f16:   ldy #0
@fric:  lda b_px0
        sec
        sbc b_d,y
        sta b_px0
        lda o_vxf,x
        sbc b_d + 1,y
        sta o_vxf,x
        lda b_d + 1,y           ; (sign-extended)
        and #$80
        beq :+
        lda #$FF
:       sta tmp
        lda o_vxl,x
        sbc tmp
        sta o_vxl,x
        lda b_py0
        sec
        sbc b_d + 2,y
        sta b_py0
        lda o_vyf,x
        sbc b_d + 3,y
        sta o_vyf,x
        lda b_d + 3,y
        and #$80
        beq :+
        lda #$FF
:       sta tmp
        lda o_vyl,x
        sbc tmp
        sta o_vyl,x
        lda o_spl,x
        sta c_spl,x
        sta b_spl
        lda o_sph,x
        sta c_sph,x
        sta b_sph
        clc
        rts

; mul_f: z_f16, z_f10 = A (signed) * 16, * 10. Keeps X.
mul_f:
        sta z_f2
        ldy #0
        cmp #$80
        bcc :+
        dey
:       sty z_f2 + 1
        asl z_f2                ; 2a
        rol z_f2 + 1
        lda z_f2                ; 8a
        asl a
        sta z_f10
        lda z_f2 + 1
        rol a
        sta z_f10 + 1
        asl z_f10
        rol z_f10 + 1
        lda z_f10               ; 16a
        asl a
        sta z_f16
        lda z_f10 + 1
        rol a
        sta z_f16 + 1
        lda z_f10               ; 10a = 8a + 2a
        clc
        adc z_f2
        sta z_f10
        lda z_f10 + 1
        adc z_f2 + 1
        sta z_f10 + 1
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
:                               ; halved till both are under 256,
@half:  lda z_ax + 1            ; then under 32
        ora z_ay + 1
        beq @lo
:       lsr z_ax + 1
        ror z_ax
        lsr z_ay + 1
        ror z_ay
        lda z_ax + 1
        ora z_ay + 1
        bne :-
@lo:    lda z_ax
        ora z_ay
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        tay
        lda halves,y
        beq @look
        tay
:       lsr z_ax
        lsr z_ay
        dey
        bne :-
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

halves: .byte 0, 1, 2, 2, 3, 3, 3, 3   ; (for the top three bits of 8)

; smul: z_p (24 bits, signed) = A (signed) * smul_l/h; the step is its
; upper two bytes. Two products of bytes from tables of squares / 4 (a * b
; = (a + b)^2 / 4 - (a - b)^2 / 4). Keeps X.
smul:
        sta z_ms
        bpl :+
        eor #$FF
        clc
        adc #1
:       jsr mul_set
        ldy smul_l              ; |A| * the low byte
        jsr mul_by
        lda z_q
        sta z_p
        lda z_q + 1
        sta z_p + 1
        ldy smul_h              ; and the high byte, 8 bits up
        jsr mul_by
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
        tay
        lda z_m
        jsr mul_set
; mul_by: z_q = a * Y, a the factor mul_set was given: a * b = (a + b)^2 / 4
; - (b - a)^2 / 4, the squares / 4 from tables the pointers point into a
; place along (both sums of the same evenness: nothing lost rounding).
; Keeps X.
mul_by:
        lda (z_qp),y
        sec
        sbc (z_qn),y
        sta z_q
        lda (z_qph),y
        sbc (z_qnh),y
        sta z_q + 1
        rts

; mul_set: A the factor for mul_by. Keeps X, Y.
mul_set:
        sta z_qp
        sta z_qph
        eor #$FF
        sta z_qn
        sta z_qnh
        rts

        .segment "SQUARES"      ; (each table on a page of its own)
qs_lo:                          ; n * n / 4, n = 0..511
        .repeat 512, I
        .byte <(I * I / 4)
        .endrepeat
qs_hi:
        .repeat 512, I
        .byte >(I * I / 4)
        .endrepeat
qn_lo:                          ; (n - 255)^2 / 4, n = 0..511
        .repeat 512, I
        .byte <((I - 255) * (I - 255) / 4)
        .endrepeat
qn_hi:
        .repeat 512, I
        .byte >((I - 255) * (I - 255) / 4)
        .endrepeat
        .code

; ---- the other players ----------------------------------------------------
;
; Everyone the joystick does not run keeps to his place in the formation:
; an area for each player (data/tactics.txt), the ball's place on the
; pitch put into it - from the touch line to the other, from goal line to
; goal line. He runs there (speed 1024) and stands. Each gets his place
; worked out anew every 32nd frame, a different few each time; a place
; hardly away from the last is not a new one. The other team sends the
; player nearest the ball after it; with it at his feet he takes it
; towards the goal and shoots from close to it. Before the kick-off no
; one moves.

team_ai:
        lda kickoff
        beq @play
        lda o_spl + BALL        ; the ball moving: the set piece taken
        ora o_sph + BALL
        beq :+
        lda #0
        sta kickoff
        lda #$FF
        sta taker
        bne @play
:       jsr cpu_take            ; (the yellow team's, after a while)
@play:  lda frame_n
        and #7
        bne :+
        jsr pick_chaser         ; (every eighth frame)
:       lda frame_n             ; those with the frame's number, every 32
        lsr a                   ; frames (team_ai: every second one)
        and #15
        tax
@pl:    txa                     ; (the keepers: keeper)
        beq @next
        cpx #11
        beq @next
        cpx ctrl
        beq @next
        cpx chaser
        beq @next
        cpx taker
        beq @next
        jsr place_formation
@next:  txa
        clc
        adc #16
        tax
        cpx #PLAYERS
        bcc @pl
        lda frame_n             ; the keepers each fourth frame
        and #2
        bne :+
        ldx #0
        jsr keeper
        ldx #11
        jsr keeper
:       jmp chase

; place_formation: player X's destination, his place in the formation for
; where the ball is; jogging. Keeps X.
place_formation:
        stx z_obj
        txa                     ; the team's formation
        ldy formation
        cpx #11
        bcc :+
        ldy formation + 1
:       clc                     ; (formation * 22 + player)
        adc form22,y
        sta z_ti
        tay
        lda tac_xs,y
        sta z_m
        lda o_xl + BALL         ; x: from + (ball x - 49) * slope / 256
        sec
        sbc #49
        sta z_t8
        lda o_xh + BALL
        sbc #0
        bpl :+
        lda #0                  ; (left of the touch line: there)
        sta z_t8
:       sta tmp + 1             ; (the high byte: 0, 1)
        lda z_t8
        jsr mul8
        lda z_q + 1
        sta tmp
        lda #0
        ldx tmp + 1
        beq :++
:       lda tmp
        clc
        adc z_m
        sta tmp
        lda #0
        adc #0
        dex
        bne :-
:       sta tmp + 1
        ldy z_ti                ; (mul8 took Y)
        lda tmp
        clc
        adc tac_x0l,y
        sta z_px
        lda tmp + 1
        adc tac_x0h,y
        sta z_px + 1
        lda tac_ys,y            ; y likewise, over 641
        sta z_m
        lda o_yl + BALL
        sec
        sbc #49
        sta z_t8
        lda o_yh + BALL
        sbc #0
        bpl :+
        lda #0
        sta z_t8
:       sta tmp + 1             ; (0, 1, 2)
        lda z_t8
        jsr mul8
        lda z_q + 1
        sta tmp
        lda #0
        sta z_t8
        ldx tmp + 1
        beq :+++
:       lda tmp
        clc
        adc z_m
        sta tmp
        bcc :+
        inc z_t8
:       dex
        bne :--
:       ldx z_obj
        ldy z_ti
        lda tmp
        clc
        adc tac_y0l,y
        sta z_py
        lda z_t8
        adc tac_y0h,y
        sta z_py + 1
        ; hardly away from the last place (the ball has hardly moved):
        ; that one kept - a new way would cost a new angle; standing, and
        ; hardly away from where he stands, he stays
        lda z_px
        sec
        sbc o_txl,x
        tay
        lda z_px + 1
        sbc o_txh,x
        jsr slack
        bcs :+
        lda z_py
        sec
        sbc o_tyl,x
        tay
        lda z_py + 1
        sbc o_tyh,x
        jsr slack
        bcc @keep
:       lda o_mov,x
        bne @go
        lda z_px
        sec
        sbc o_xl,x
        tay
        lda z_px + 1
        sbc o_xh,x
        jsr slack
        bcs @go
        lda z_py
        sec
        sbc o_yl,x
        tay
        lda z_py + 1
        sbc o_yh,x
        jsr slack
        bcc @keep
@go:    lda z_px
        sta o_txl,x
        lda z_px + 1
        sta o_txh,x
        lda z_py
        sta o_tyl,x
        lda z_py + 1
        sta o_tyh,x
        jsr pace                ; as fast as gets him there by the next
        lda #1                  ; place: gliding along with the ball
        sta o_mov,x
        sta o_new,x
@keep:  rts

; stride: player X's running picture on for z_nf frames: a step every
; 16 / (speed / 256) frames - every 4 at full speed, slower when he goes
; slower (no feet faster than the ground goes by). Keeps X.
stride:
        ldy o_sph,x
        bne :+
        iny                     ; (under 256: as 256)
:       lda #0
:       clc
        adc z_nf
        dey
        bne :-
        sta z_t8                ; (speed / 256 * frames)
        lda o_run,x
        sec
        sbc z_t8
        bpl @ran
:       inc o_step,x
        clc
        adc #16
        bmi :-
@ran:   sta o_run,x
        rts

; pace: player X's speed for his new place: its way from him (the
; longer way across or along) * 12 - there in about 43 frames, still
; going when the next place comes (32) - from 192 up to SPEED_JOG.
; Keeps X.
pace:
        lda o_txl,x
        sec
        sbc o_xl,x
        sta tmp
        lda o_txh,x
        sbc o_xh,x
        jsr abs16
        bne @fast
        sta z_t8
        lda o_tyl,x
        sec
        sbc o_yl,x
        sta tmp
        lda o_tyh,x
        sbc o_yh,x
        jsr abs16
        bne @fast
        cmp z_t8
        bcs :+
        lda z_t8
:       cmp #SPEED_JOG / 12 + 1
        bcs @fast
        cmp #16
        bcs :+
        lda #16                 ; (192 at least)
:       ldy #0                  ; * 4
        sty tmp
        asl a
        rol tmp
        asl a
        rol tmp
        sta z_t8
        ldy tmp
        asl a                   ; + * 8
        rol tmp
        clc
        adc z_t8
        sta o_spl,x
        tya
        adc tmp
        sta o_sph,x
        rts
@fast:  lda #<SPEED_JOG
        sta o_spl,x
        lda #>SPEED_JOG
        sta o_sph,x
        rts

; slack: carry clear if the difference A:Y is within SLACK either way
slack:
        cmp #0
        beq @pos
        cmp #$FF
        bne @no
        cpy #<(-SLACK)          ; -SLACK..-1
        bcs @in
@no:    sec
        rts
@in:    clc
        rts
@pos:   cpy #SLACK + 1
        rts

form22: .byte 0, 22, 44, 66, 88, 110, 132, 154

; pick_chaser: the other team's player nearest the ball (not the keeper)
pick_chaser:
        lda kickoff
        ora dead_t
        bne @done
        ldx chaser              ; (not while he slides)
        bmi :+
        lda o_slide,x
        bne @done
:
        lda #$FF
        sta mate_d
        sta mate_d + 1
        ldx #PLAYERS - 1
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
        cpx #11
        bne @look
        lda mate
        sta chaser
@done:  rts

; chase: the chaser after the ball - at his feet, towards the goal at the
; bottom, and a shot from close to it
chase:
        ldx chaser
        bmi @done
        stx z_obj
        lda o_slide,x           ; (sliding: slides has him)
        bne @done
        lda #1
        sta o_mov,x
        jsr ball_near           ; at his feet, and not the cyan team's?
        bcs :+
        lda #1
        jsr held
        bcc @have
:       jsr cpu_tackle          ; (theirs, and near: a tackle)
        bcc @done
        lda frame_n             ; after it (where it is, each fourth frame)
        and #3
        bne @done
        lda o_xl + BALL
        sta o_txl,x
        lda o_xh + BALL
        sta o_txh,x
        lda o_yl + BALL
        sta o_tyl,x
        lda o_yh + BALL
        sta o_tyh,x
        lda #<SPEED_CHASE
        sta o_spl,x
        lda #>SPEED_CHASE
        sta o_sph,x
@done:  rts
@have:  ; near the goal: a shot at it
        lda o_yl,x
        cmp #<(689 - SHOOT_FROM)
        lda o_yh,x
        sbc #>(689 - SHOOT_FROM)
        bcc @run
        lda #<304               ; the ball's destination: 32 times the
        sec                     ; way to the middle of the goal
        sbc o_xl + BALL
        sta tmp
        lda #>304
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
        lda #<1000
        clc
        adc o_yl + BALL
        sta o_tyl + BALL
        lda #>1000
        adc o_yh + BALL
        sta o_tyh + BALL
        lda #<SHOT_SPEED
        sta o_spl + BALL
        lda #>SHOT_SPEED
        sta o_sph + BALL
        lda #<SHOT_DZ
        sta o_dzf + BALL
        lda #>SHOT_DZ
        sta o_dzl + BALL
        lda #1
        sta last_team
        jsr touch
        stx last_pl
        lda #$FF                ; (a moment before he goes after it again)
        sta chaser
        rts
@run:   ldy #4                  ; towards the goal: down, or down and in
        lda o_xl,x
        cmp #<(304 - 40)
        lda o_xh,x
        sbc #>(304 - 40)
        bcs :+
        ldy #3                  ; (left of it: down and right)
        bne @dir
:       lda #<(304 + 40)
        cmp o_xl,x
        lda #>(304 + 40)
        sbc o_xh,x
        bcs @dir
        ldy #5                  ; (right of it: down and left)
@dir:   tya
        sta o_dir,x
        lda o_xl,x              ; he runs that way, with it
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
        lda #<SPEED_BALL
        sta o_spl,x
        lda #>SPEED_BALL
        sta o_sph,x
        lda frame_n             ; and kicks it on ahead, every second frame
        lsr a
        bcs :+
        jsr ball_ahead
        lda #<1024
        sta o_spl + BALL
        lda #>1024
        sta o_sph + BALL
        lda #1
        sta last_team
        jsr touch
        stx last_pl
:       rts

; ball_near: carry clear if the ball is at player X's feet (distance
; squared at most 32) and low. Keeps X.
ball_near:
        jsr mate_dist
        lda tmp + 1
        bne @no
        lda tmp
        cmp #NEAR + 1
        bcs @no
        lda o_zl + BALL
        cmp #13
        rts
@no:    sec
        rts

; ---- whose the joystick is ------------------------------------------------

; switch: every few frames, the joystick to the team's player nearest the
; ball (not the keeper), unless the one it has is close to it
switch:
        lda kickoff             ; (the cyan team's set piece: the taker
        beq :+                  ; keeps it)
        lda rs_team
        bne :+
        rts
:       ldx ctrl                ; (nor from one sliding)
        lda o_slide,x
        beq :+
        rts
:       lda recv_t              ; (nor the one a pass goes to)
        beq :+
        lda recv
        cmp ctrl
        bne :+
        rts
:       dec switch_t
        bpl @done
        lda #2                  ; (each sixth frame)
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
        lda mate                ; (the last one goes back to his place:
        sta ctrl                ; team_ai)
@done:  rts

; ---- the rules ------------------------------------------------------------
;
; Over a touch line: a throw-in for the team that did not touch the ball
; last. Over a goal line between the posts and under the bar: a goal, and
; a kick-off for the team that let it in; else a goal kick or, the
; defenders' touch last, a corner. The ball is dead a while first - it
; rolls on, no one has it, the others go to their places - then it is
; put down, the taker behind it facing the middle of the pitch.

; rules: after the ball's frame, while it is in play
rules:
        lda kickoff             ; (a set piece not yet taken: it lies still)
        beq :+
        rts
:       ldx #BALL
        lda o_xl,x
        cmp #<LINE_L
        lda o_xh,x
        sbc #>LINE_L
        bcs :+
        lda #<LINE_L
        ldy #>LINE_L
        jmp @throw
:       lda #<LINE_R
        cmp o_xl,x
        lda #>LINE_R
        sbc o_xh,x
        bcs @y
        lda #<LINE_R
        ldy #>LINE_R
@throw: sta rs_x
        sty rs_x + 1
        lda o_yl,x              ; along the line where it went out, on the
        sta rs_y                ; pitch
        lda o_yh,x
        sta rs_y + 1
        lda rs_y
        cmp #<LINE_T
        lda rs_y + 1
        sbc #>LINE_T
        bcs :+
        lda #<LINE_T
        sta rs_y
        lda #>LINE_T
        sta rs_y + 1
:       lda #<LINE_B
        cmp rs_y
        lda #>LINE_B
        sbc rs_y + 1
        bcs :+
        lda #<LINE_B
        sta rs_y
        lda #>LINE_B
        sta rs_y + 1
:       lda #R_THROW
        sta rs_kind
        lda last_team
        eor #1
        sta rs_team
        jmp @dead
@y:     ldy #0                  ; the top goal line: the cyan team attacks it
        lda o_yl,x
        cmp #<LINE_T
        lda o_yh,x
        sbc #>LINE_T
        bcc @line
        iny                     ; the bottom one: the yellow team
        lda #<LINE_B
        cmp o_yl,x
        lda #>LINE_B
        sbc o_yh,x
        bcc @line
        rts
@line:  sty r_t                ; (the attackers)
        lda o_xl,x
        cmp #<POST_L
        lda o_xh,x
        sbc #>POST_L
        bcc @wide
        lda #<POST_R
        cmp o_xl,x
        lda #>POST_R
        sbc o_xh,x
        bcc @wide
        lda o_zl,x
        cmp #BAR_Z
        bcs @wide
        lda score,y             ; a goal
        clc
        adc #1
        sta score,y
        lda #1
        sta goal
        tya
        eor #1
        sta rs_team
        lda #R_KICKOFF
        sta rs_kind
        lda #<304
        sta rs_x
        lda #>304
        sta rs_x + 1
        lda #<369
        sta rs_y
        lda #>369
        sta rs_y + 1
        lda #DEAD_GOAL
        bne @dead2
@wide:  ldy #0                  ; the side it went out: x 0 left, 1 right
        lda o_xl,x
        cmp #<304
        lda o_xh,x
        sbc #>304
        bcc :+
        iny
:       lda last_team
        cmp r_t
        beq @gkick
        lda #R_CORNER           ; the defenders': a corner
        sta rs_kind
        lda r_t
        sta rs_team
        lda corner_xl,y
        sta rs_x
        lda corner_xh,y
        sta rs_x + 1
        ldy r_t
        lda corner_yl,y
        sta rs_y
        lda corner_yh,y
        sta rs_y + 1
        jmp @dead
@gkick: lda #R_GOALKICK         ; the attackers': a goal kick
        sta rs_kind
        lda r_t
        eor #1
        sta rs_team
        lda gkick_xl,y
        sta rs_x
        lda gkick_xh,y
        sta rs_x + 1
        ldy r_t
        lda gkick_yl,y
        sta rs_y
        lda gkick_yh,y
        sta rs_y + 1
@dead:  lda #DEAD_OUT
@dead2: sta dead_t
        lda #$FF                ; no one after it, no more aftertouch
        sta chaser
        sta at_n
        sta recv
        ldx ctrl
        jmp stand

corner_xl:  .byte <54, <553     ; left, right
corner_xh:  .byte >54, >553
corner_yl:  .byte <54, <684     ; top, bottom
corner_yh:  .byte >54, >684
gkick_xl:   .byte <244, <364
gkick_xh:   .byte >244, >364
gkick_yl:   .byte <74, <664
gkick_yh:   .byte >74, >664

; net: the dead ball after a goal stopped by the net, NET behind the line
net:
        lda goal
        beq @done
        ldx #BALL
        lda o_yl,x
        cmp #<(LINE_T - NET)
        lda o_yh,x
        sbc #>(LINE_T - NET)
        bcc @stop
        lda #<(LINE_B + NET)
        cmp o_yl,x
        lda #>(LINE_B + NET)
        sbc o_yh,x
        bcs @done
@stop:  lda #0
        sta o_spl,x
        sta o_sph,x
@done:  rts

; restart: the dead time over - the ball put down, the taker to it
restart:
        lda #0
        sta goal
        ldx #BALL
        sta o_xf,x
        sta o_yf,x
        sta o_zf,x
        sta o_zl,x
        sta o_dzf,x
        sta o_dzl,x
        lda rs_x
        sta o_xl,x
        lda rs_x + 1
        sta o_xh,x
        lda rs_y
        sta o_yl,x
        lda rs_y + 1
        sta o_yh,x
        jsr stand
        lda rs_kind
        bne @set
        jsr line_up             ; a kick-off: everyone back in line, the
        ldx #9                  ; centre forward at the ball
        lda rs_team
        beq :+
        ldx #20
:       stx taker
        jmp await
@set:   ldx #0                  ; the taker: a goal kick the keeper's, else
        lda rs_team             ; the team's player nearest the ball
        beq :+
        ldx #11
:       lda rs_kind
        cmp #R_GOALKICK
        beq @have
        txa
        clc
        adc #10
        sta r_t                ; (the team's last)
        jsr nearest
@have:  stx taker
        lda #<304               ; facing the middle of the pitch
        sec
        sbc o_xl + BALL
        sta z_ax
        lda #>304
        sbc o_xh + BALL
        sta z_ax + 1
        lda #<369
        sec
        sbc o_yl + BALL
        sta z_ay
        lda #>369
        sbc o_yh + BALL
        sta z_ay + 1
        jsr angle
        lda #128
        sec
        sbc z_th
        clc
        adc #16
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        sta o_dir,x
        tay                     ; just behind the ball
        lda #0
        sta o_xf,x
        sta o_yf,x
        lda behind_x,y
        jsr sext
        clc
        adc o_xl + BALL
        sta o_xl,x
        lda tmp
        adc o_xh + BALL
        sta o_xh,x
        lda behind_y,y
        jsr sext
        clc
        adc o_yl + BALL
        sta o_yl,x
        lda tmp
        adc o_yh + BALL
        sta o_yh,x
        jsr stand
        jmp await

; await: the set piece ready, for taker to take: the cyan team's with
; the joystick (fire held on from before does not kick), the yellow
; team's after a while
await:
        lda #$FF
        sta chaser
        sta at_n
        sta recv
        lda rs_team
        bne @cpu
        lda taker
        sta ctrl
        lda #$FF
        sta fire_n
        bne @go
@cpu:   lda #CPU_WAIT
        sta cpu_t
@go:    lda #1
        sta kickoff
        rts

; just behind the ball, for each way the taker faces
behind_x:   .byte 0, <(-4), <(-5), <(-4), 0, 4, 5, 4
behind_y:   .byte 5, 4, 0, <(-4), <(-5), <(-4), 0, 4

; sext: A unchanged, tmp its sign (0 or $FF). Keeps X, Y.
sext:
        pha
        and #$80
        beq :+
        lda #$FF
:       sta tmp
        pla
        rts

; nearest: X = the player from X + 1 to r_t nearest the ball, by
; |dx| + |dy| (far ones too)
nearest:
        lda #$FF
        sta mate_d
        sta mate_d + 1
@look:  inx
        lda o_xl,x
        sec
        sbc o_xl + BALL
        sta tmp
        lda o_xh,x
        sbc o_xh + BALL
        jsr abs16
        sty mate_t + 1
        sta mate_t
        lda o_yl,x
        sec
        sbc o_yl + BALL
        sta tmp
        lda o_yh,x
        sbc o_yh + BALL
        jsr abs16
        clc
        adc mate_t
        sta mate_t
        tya
        adc mate_t + 1
        sta mate_t + 1
        lda mate_t
        cmp mate_d
        lda mate_t + 1
        sbc mate_d + 1
        bcs :+
        lda mate_t
        sta mate_d
        lda mate_t + 1
        sta mate_d + 1
        stx mate
:       cpx r_t
        bne @look
        ldx mate
        rts

; cpu_take: the yellow team's set piece, once it has waited: passed to
; the nearest team-mate, or kicked on the way the taker faces
cpu_take:
        lda rs_team
        beq @done
        dec cpu_t
        bne @done
        lda #1
        sta last_team
        jsr touch
        lda taker
        sta last_pl
        lda #$FF                ; the nearest, not the keeper, not the taker
        sta mate
        sta mate_d
        sta mate_d + 1
        ldx #PLAYERS - 1
@look:  cpx taker
        beq @next
        jsr mate_dist
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
        cpx #11
        bne @look
        ldx mate
        bmi :+
        jmp kick_to
:       ldx taker
        ldy o_dir,x
        jsr ball_ahead
        lda #<2048
        sta o_spl + BALL
        lda #>2048
        sta o_sph + BALL
        jmp kicked
@done:  rts

; ---- the keepers ----------------------------------------------------------
;
; A keeper stands between his posts, 8 to 19 pixels out from his line -
; the further the ball, the further out - and a quarter of the ball's way
; from the middle across. A ball coming at his goal: he runs to where
; it crosses his line, faster. One within his reach and under the bar he
; catches, and holds till he kicks it out (the joystick's team: fire).

; keeper: keeper X's place, worked out anew. Keeps X.
keeper:
        cpx ctrl                ; (not while the joystick has him, nor
        beq @done               ; while he holds the ball)
        cpx taker
        bne :+
@done:  rts
:       stx z_obj
        lda o_xl + BALL         ; across: 304 + (ball - 304) / 4, between
        sec                     ; the posts
        sbc #<304
        sta tmp
        lda o_xh + BALL
        sbc #>304
        cmp #$80
        ror a
        ror tmp
        cmp #$80
        ror a
        ror tmp
        sta tmp + 1
        lda tmp
        clc
        adc #<304
        sta z_px
        lda tmp + 1
        adc #>304
        sta z_px + 1
        jsr k_posts
        ; out from his line: 8 + the ball's way from it / 32, at most 19
        jsr k_line              ; (tmp: the line, z_t8 bit 7: the top one)
        lda o_yl + BALL
        sec
        sbc tmp
        sta z_py
        lda o_yh + BALL
        sbc tmp + 1
        bpl :+
        eor #$FF                ; (|way|, near enough)
        sta z_py + 1
        lda z_py
        eor #$FF
        sta z_py
        lda z_py + 1
:       ldy #5                  ; / 32
:       lsr a
        ror z_py
        dey
        bne :-
        cmp #0
        bne @far
        lda z_py
        cmp #12
        bcc :+
@far:   lda #11
:       clc
        adc #8                  ; (8-19)
        bit z_t8
        bpl :+
        eor #$FF                ; (the top keeper: down from it)
        clc
        adc #1
:       sta z_py                ; the line - (8-19), or + (8-19)
        ldy #0
        ora #0
        bpl :+
        dey
:       sty z_py + 1
        lda tmp
        sec
        sbc z_py
        sta z_py
        lda tmp + 1
        sbc z_py + 1
        sta z_py + 1
        lda #<SPEED_JOG
        sta z_ks
        lda #>SPEED_JOG
        sta z_ks + 1
        ldx z_obj
        jsr k_shot              ; (a shot at him: across to it, faster)
        ldx z_obj
        lda z_px                ; somewhere else: there
        cmp o_txl,x
        bne :+
        lda z_px + 1
        cmp o_txh,x
        bne :+
        lda z_py
        cmp o_tyl,x
        bne :+
        lda z_py + 1
        cmp o_tyh,x
        beq @same
:       lda z_px
        sta o_txl,x
        lda z_px + 1
        sta o_txh,x
        lda z_py
        sta o_tyl,x
        lda z_py + 1
        sta o_tyh,x
        lda z_ks
        sta o_spl,x
        lda z_ks + 1
        sta o_sph,x
        lda #1
        sta o_mov,x
        sta o_new,x
@same:  rts

; k_line: tmp = keeper X's goal line; z_t8 bit 7 set for the top one
; (the yellow keeper's), out from it downwards. Keeps X.
k_line:
        lda #<LINE_B
        ldy #>LINE_B
        cpx #11
        bcc :+
        lda #<LINE_T
        ldy #>LINE_T
:       sta tmp
        sty tmp + 1
        lda #0
        cpx #11
        bcc :+
        lda #$80
:       sta z_t8
        rts

; k_posts: z_px between the posts (POST_L + 7 .. POST_R - 2)
k_posts:
        lda z_px
        cmp #<(POST_L + 7)
        lda z_px + 1
        sbc #>(POST_L + 7)
        bcs :+
        lda #<(POST_L + 7)
        sta z_px
        lda #>(POST_L + 7)
        sta z_px + 1
        rts
:       lda #<(POST_R - 2)
        cmp z_px
        lda #>(POST_R - 2)
        sbc z_px + 1
        bcs :+
        lda #<(POST_R - 2)
        sta z_px
        lda #>(POST_R - 2)
        sta z_px + 1
:       rts

; k_shot: a ball (768 or more) coming at keeper X's goal, KEEPER_SEES
; from his line z_py or nearer (z_t8 bit 7: the top keeper): z_px = where it
; crosses it (x + the frames till then * its step across), z_ks =
; SPEED_DIVE. Keeps X.
k_shot:
        lda o_sph + BALL
        cmp #>768
        bcs :+
@no:    rts
:       lda z_py                ; dy = his line - the ball's y
        sec
        sbc o_yl + BALL
        sta z_dvd + 1           ; (* 256 for the frames)
        lda z_py + 1
        sbc o_yh + BALL
        tay                     ; (the high byte: the sign, or too far)
        lda o_vyl + BALL        ; coming his way: the step's sign the same
        bit z_t8
        bmi @top
        cpy #0                  ; (the bottom keeper: dy 0..255, vy > 0)
        bne @no
        ora #0
        bmi @no
        sta z_dvs + 1
        lda o_vyf + BALL
        sta z_dvs
        jmp @div
@top:   cpy #$FF                ; (the top one: dy -255..-1, vy < 0)
        bne @no
        ora #0
        bpl @no
        lda #0                  ; |dy|, |vy|
        sec
        sbc z_dvd + 1
        sta z_dvd + 1
        lda #0
        sec
        sbc o_vyf + BALL
        sta z_dvs
        lda #0
        sbc o_vyl + BALL
        sta z_dvs + 1
@div:   lda z_dvd + 1           ; (late, as Sensible Soccer's: near his line)
        cmp #KEEPER_SEES + 1
        bcs @no
        lda z_dvs + 1           ; (at least half a pixel a frame)
        bne :+
        lda z_dvs
        bpl @no
:       lda #0
        sta z_dvd
        jsr div16               ; the frames till it is there
        lda z_dvd + 1
        bne @no                 ; (256 or more: not coming)
        lda o_vxl + BALL        ; x + frames * |vx|, signed
        sta z_sg
        bpl :+
        lda #0
        sec
        sbc o_vxf + BALL
        sta z_dvs
        lda #0
        sbc o_vxl + BALL
        sta z_dvs + 1
        jmp :++
:       lda o_vxf + BALL
        sta z_dvs
        lda o_vxl + BALL
        sta z_dvs + 1
:       lda z_dvd
        jsr mul_set
        ldy z_dvs               ; (|vx| low * frames) / 256
        jsr mul_by
        lda z_q + 1
        sta tmp
        ldy z_dvs + 1           ; + |vx| high * frames
        jsr mul_by
        lda tmp
        clc
        adc z_q
        sta tmp
        lda z_q + 1
        adc #0
        sta tmp + 1
        bit z_sg
        bpl :+
        lda #0
        sec
        sbc tmp
        sta tmp
        lda #0
        sbc tmp + 1
        sta tmp + 1
:       lda o_xl + BALL
        clc
        adc tmp
        sta z_px
        lda o_xh + BALL
        adc tmp + 1
        sta z_px + 1
        jsr k_posts             ; (as far as he gets: about his posts)
        lda #<SPEED_DIVE
        sta z_ks
        lda #>SPEED_DIVE
        sta z_ks + 1
        rts

; div16: z_dvd = z_dvd / z_dvs (16 bits, unsigned). Keeps X.
div16:
        lda #0
        sta z_rem
        sta z_rem + 1
        ldy #16
@bit:   asl z_dvd
        rol z_dvd + 1
        rol z_rem
        rol z_rem + 1
        lda z_rem
        sec
        sbc z_dvs
        sta tmp
        lda z_rem + 1
        sbc z_dvs + 1
        bcc :+
        sta z_rem + 1
        lda tmp
        sta z_rem
        inc z_dvd
:       dey
        bne @bit
        rts

; catch: a keeper with the ball within his reach, under the bar, not his
; own kick: he holds it
catch:
        lda kickoff
        bne @done
        lda o_zl + BALL
        cmp #CATCH_Z
        bcs @done
        ldx #0
        jsr reach
        bcc :+
        ldx #11
        jsr reach
        bcs @done
:       jmp hold
@done:  rts

; reach: carry clear if the ball is within keeper X's reach, and not
; from his own kick. Keeps X.
reach:
        cpx last_pl
        beq @no
        lda #CATCH_X
        sta z_t8
        lda o_xl + BALL
        sec
        sbc o_xl,x
        tay
        lda o_xh + BALL
        sbc o_xh,x
        jsr within
        bcs @no
        lda #CATCH_Y
        sta z_t8
        lda o_yl + BALL
        sec
        sbc o_yl,x
        tay
        lda o_yh + BALL
        sbc o_yh,x
        jmp within
@no:    sec
        rts

; within: carry clear if A:Y (high, low) is within z_t8 either way
within:
        cmp #0
        beq @pos
        cmp #$FF
        bne @no
        tya                     ; -z_t8 .. -1
        clc
        adc z_t8
        bcs @in
@no:    sec
        rts
@pos:   cpy z_t8
        beq @in
        bcs @no
@in:    clc
        rts

; hold: keeper X has the ball - it lies still before him, and he kicks it
; out as a set piece
hold:
        stx taker
        stx last_pl
        lda #R_KEEPER
        sta rs_kind
        ldy #0                  ; his team, the way he faces
        lda #0
        cpx #11
        bcc :+
        iny
        lda #4
:       sty rs_team
        sty last_team
        jsr touch
        sta o_dir,x
        jsr stand
        ldx #BALL
        jsr stand
        lda #0
        sta o_zl,x
        sta o_zf,x
        sta o_dzl,x
        sta o_dzf,x
        ldx taker               ; just before him
        lda o_xl,x
        sta o_xl + BALL
        lda o_xh,x
        sta o_xh + BALL
        ldy #<(-5)
        cpx #11
        bcc :+
        ldy #5
:       tya
        jsr sext
        clc
        adc o_yl,x
        sta o_yl + BALL
        lda tmp
        adc o_yh,x
        sta o_yh + BALL
        ldx #BALL
        jsr stand
        jmp await

; ---- holding the ball, tackles -------------------------------------------
;
; A ball a team has touched in the last HOLD_T frames is that team's: the
; other cannot stop it or dribble it away, only win it with a sliding
; tackle - fire for the cyan player, the yellow chaser when he is near.
; A tackle goes the way the player faces, fast and slower each frame;
; reaching the ball low, it knocks it on that way.

; touch: the ball just touched (touch_t from 0). Keeps A, X, Y.
touch:
        pha
        lda #0
        sta touch_t
        pla
        rts

; held: carry set if the ball is held by the team other than A's: it
; touched it HOLD_T frames ago or less, or its player who did has it by
; him, low. Keeps X, Y.
held:
        cmp last_team
        beq @no
        lda touch_t
        cmp #HOLD_T + 1
        bcc @yes
        lda o_zl + BALL
        cmp #HOLD_Z + 1
        bcs @no
        stx hd_x
        sty hd_y
        ldx last_pl
        jsr mate_dist
        ldx hd_x
        ldy hd_y
        lda tmp + 1
        bne @no
        lda tmp
        cmp #HOLD_D2 + 1
        bcs @no
@yes:   sec
        rts
@no:    clc
        rts

; slide: player X starts a sliding tackle the way he faces. Keeps X.
slide:
        lda #SLIDE_T
        sta o_slide,x
        lda #0
        sta o_hit,x
        lda #1
        sta o_step,x            ; (a foot forward)
        sta o_mov,x
        lda #<SPEED_SLIDE
        sta o_spl,x
        lda #>SPEED_SLIDE
        sta o_sph,x
        ldy o_dir,x
        lda o_xl,x
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
        lda #$FF
        sta drib_dir
        rts

; slides: the sliding tackles on a frame (the joystick's player, the
; chaser): slower, the ball knocked on if reached, up at the end
slides:
        ldx ctrl
        jsr @one
        ldx chaser
        bmi @done
@one:   lda o_slide,x
        beq @done
        dec o_slide,x
        bne :+
        jmp stand               ; (over: up again)
:       lda o_spl,x             ; slower
        sec
        sbc #SLIDE_DECEL
        sta o_spl,x
        lda o_sph,x
        sbc #0
        sta o_sph,x
        bcs :+
        lda #0
        sta o_spl,x
        sta o_sph,x
:       lda o_hit,x             ; the ball reached, low: knocked on
        bne @done
        lda o_zl + BALL
        cmp #SLIDE_Z + 1
        bcs @done
        jsr mate_dist
        lda tmp + 1
        bne @done
        lda tmp
        cmp #SLIDE_REACH + 1
        bcs @done
        lda #1
        sta o_hit,x
        stx last_pl
        lda #0
        cpx #11
        bcc :+
        lda #1
:       sta last_team
        jsr touch
        ldy o_dir,x
        jsr ball_ahead
        lda o_spl,x             ; as fast as he slides, and some
        clc
        adc #<256
        sta o_spl + BALL
        lda o_sph,x
        adc #>256
        sta o_sph + BALL
        lda #0
        sta o_dzl + BALL
        sta o_dzf + BALL
@done:  rts

; cpu_tackle: the yellow chaser X, the cyan team holding the ball and it
; near him (SLIDE_FROM, squared): a sliding tackle at it. Carry clear
; if he slides. Keeps X.
cpu_tackle:
        lda cpu_slide
        bne @no
        lda #1
        jsr held
        bcc @no
        jsr mate_dist
        lda tmp
        cmp #<(SLIDE_FROM + 1)
        lda tmp + 1
        sbc #>(SLIDE_FROM + 1)
        bcs @no
        jsr mate_way            ; facing the ball: the way from it to him
        bcs @no                 ; turned round, in eighths
        clc
        adc #128 + 16
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        sta o_dir,x
        jsr slide
        lda #SLIDE_WAIT
        sta cpu_slide
        clc
        rts
@no:    sec
        rts
