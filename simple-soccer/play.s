; play.s - the match: the players and the ball, a frame at a time (50 a
; second), as Sensible Soccer moves them
;
; The game runs on Sensible Soccer's pitch and in its units: touchlines
; at x 49 and 558, goal lines at y 49 and 689, the centre spot at 304,
; 369 - as the C64's does; simple-soccer.s shows it on the C64's ground, a
; pixel of the pitch a pixel on the screen. Positions are
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

        .export play_init, play_frame, pose_of, score, game_min, hud, min_frames
        .export lift, jmp_pl, jmp_t, o_off, card_pl, card_c
        .export dbg_on, dbg_i, dbg_t, dbg_bits, dbg_plan
        .export o_xl, o_xh, o_yl, o_yh, o_zl, o_dir, o_step, o_spl, ctrl, ctrl_b
        .export two, sk
        .import joy, joy_a, joy_b, atan_tab, sin_tab
        .import sfx_kick, sfx_catch, sfx_whistle, sfx_halftime, sfx_goal
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
NET_T       = 12                ; the net this far behind the line: at the
NET_B       = 5                 ; top, at the bottom (as the goals are drawn:
                                ; the bottom one's net is shallower)
NET_L       = 275               ; and between the side nettings (the posts
NET_R       = 335               ; are drawn at 270 and 340, the ball 5 wide)
DEAD_OUT    = 50                ; frames the ball is dead after going out,
DEAD_GOAL   = 125               ; after a goal
CPU_WAIT    = 20                ; the yellow team's set pieces: after 40 frames
R_KICKOFF   = 0                 ; restarts
R_THROW     = 1
R_GOALKICK  = 2
R_CORNER    = 3
R_KEEPER    = 4                 ; (the keeper has it)
R_FREE      = 5                 ; a foul: a free kick,
R_PENALTY   = 6                 ;   in the box a penalty
BOX_L       = 162               ; the penalty areas as drawn: across, and
BOX_R       = 446               ; from the line to (top) / from (bottom)
BOX_T       = 135
BOX_B       = 603
SPOT_T      = 104               ; the penalty spots
SPOT_B      = 634
WALL_D      = 40                ; a free kick: the other team this far off
FOUL_R      = 12                ; a tackle from behind this near the player
                                ; on the ball: a foul
THROW_T     = 10                ; a throw-in: frames the ball flies from the
THROW_HOLD  = 19                ; taker's head, drawn so high while he holds it
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
HEAD_Z_LO   = 11                ; a header: the ball this high to this high,
HEAD_Z_HI   = 22
HEAD_D2     = 100               ; this near (squared)
HEAD_SPEED  = 1792              ; then as fast as a pass, a little rising
HEAD_DZ     = $0040
JUMP_T      = 10                ; frames he is drawn in the air
DHEAD_Z_LO  = 4                 ; a diving header: the ball this high to
DHEAD_Z_HI  = 16                ; this high, up to this far (squared) before
DHEAD_D2    = 900               ; him; hit as hard as a shot
PRESSED     = 784               ; a cyan player this near (squared) the ball
                                ; makes the yellow one on it pass,
PASS_MIN    = 900               ; to a team-mate this far (squared) at least,
CPU_HOLD    = 8                 ; or else once he has had it so many looks
                                ; (every second frame), as Arlasoft Soccer's
PASS_WAIT   = 30                ; then not again for so many frames
DEAD_HALF   = 150               ; frames dead at half time and full time
DIVE_T      = 28                ; a keeper's dive: frames in the air and down,
DIVE_AIR    = 16                ; the first so many in the air
DIVE_FROM   = 8                 ; and he dives for a ball this far across
KEEPER_SEES = 32                ; the keeper goes for a ball this near his line
CATCH_X     = 8                 ; the keeper catches the ball this near,
CATCH_Y     = 6
CATCH_Z     = 13                ; and under this high (a lob goes over him)
SLACK       = 2                 ; a place this near the last one is the same
SPEED_CHASE = 1102              ; after the ball
SHOOT_FROM  = 100               ; the other team shoots from this near
NEAR        = 32                ; distance squared: the ball at his feet
TAKE_D2     = 9                 ; the other team's, this close: the yellow
                                ; chaser takes it (nearer)
CLOSE       = 72                ; near enough to kick it
DENY_T      = 25                ; frames the chaser waits after missing a take
PASS_Q      = 12                ; frames a pass let go of too soon waits for
                                ; the ball to come
KICKED_T    = 50                ; frames the one who passed or shot is not
                                ; the one to get to the ball (switch, help)
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
z_rnd:      .res 1              ; rnd's
z_off:      .res 1              ; pass's: how far off the way he kicks

; A player's control of his team - the joystick's player, fire, the pass
; on its way, the aftertouch, the dribble - for control, switch, help and
; aftertouch: the cyan team's here, the yellow team's in ctx_b while
; there are two players; swap trades them (each)
ctx:
pj:         .res 1              ; his joystick, J_ bits
ctrl:       .res 1              ; the joystick's player, $FF none
fire_n:     .res 1              ; frames fire has been held
recv:       .res 1              ; the player a pass went to, $FF none,
recv_t:     .res 1              ; and the frames he still goes to meet it
helper:     .res 1              ; the player running to a ball his team has
                                ; not got (help), $FF none
at_n:       .res 1              ; the aftertouch's frame, $FF none
at_dir:     .res 1              ; the shot's way
at_side:    .res 1              ; the side it bends to, $FF none yet
at_j:       .res 1              ; the joystick's way
drib_dir:   .res 1              ; dribbling: the way, and the touches
drib_n:     .res 1
kick_pl:    .res 1              ; the player who last passed or shot,
kick_t:     .res 1              ; and the frames since (switch, help)
pass_q:     .res 1              ; frames a pass let go of too soon waits
me:         .res 1              ; the team: 0 cyan, 1 yellow
t_lo:       .res 1              ; its keeper: 0, 11
t_hi:       .res 1              ; its last player: 10, 21
t_end:      .res 1              ; one before its keeper: $FF, 10
CTX_N       = * - ctx
ctx_b:      .res CTX_N
pj_b        = ctx_b + pj - ctx
ctrl_b      = ctx_b + ctrl - ctx
fire_n_b    = ctx_b + fire_n - ctx
recv_b      = ctx_b + recv - ctx
helper_b    = ctx_b + helper - ctx
at_n_b      = ctx_b + at_n - ctx

        .bss
; the objects: the players, then the ball
o_xf:   .res NOBJ               ; x, y: fraction,
o_yf:   .res NOBJ
o_txl:  .res NOBJ               ; (the destination: below)
o_txh:  .res NOBJ
o_tyl:  .res NOBJ
o_tyh:  .res NOBJ
o_xl:   .res NOBJ               ; pixel - as far after the place's as the
o_xh:   .res NOBJ               ; destination's (walls)
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
o_dir:  .res NOBJ               ; the way it faces, 0 up .. 7, clockwise
o_step: .res NOBJ               ; its running picture (players), turn (ball)
o_run:  .res NOBJ               ; frames to its next step
o_mov:  .res NOBJ               ; players: 1 while on the way somewhere
o_new:  .res NOBJ               ; 1: a new destination, the way not yet worked out
o_slide: .res NOBJ              ; frames left of a sliding tackle, 0 none
o_hit:  .res NOBJ               ; 1: the tackle has reached the ball
o_dive: .res NOBJ               ; a keeper's frames left of a dive, 0 none
o_dvd:  .res NOBJ               ; its way: 0 right, 1 left
        .segment "LOWBSS"       ; (down low: simple-soccer.cfg)
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
o_hd:   .res NOBJ               ; 1: the slide is a diving header
dbg_plan:   .res 3 * 64         ; (a test's plan: see dbg_on)
        .bss

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
min_t:      .res 1              ; frames into the minute
min_frames: .res 1              ; frames to a minute (the title's choice:
                                ; 100, 167, 233 - 90 in 3, 5, 7 minutes)
game_min:   .res 1              ; the match's minute, 0-90
half:       .res 1              ; 1: the second half
flip:       .res 1              ; 1: the sides changed - the cyan team at the
                                ; top, attacking down
full:       .res 1              ; 1: full time - till fire starts a new match
hud:        .res 1              ; 1: the score and the minute shown
hd_x:       .res 1              ; (held's)
cp_from:    .res 1              ; cpu_pass's: the passer, the receiver,
cp_to:      .res 1
cp_y:       .res 2              ; his y,
cp_d:       .res 2              ; his way squared
cp_k:       .res 2              ; (how far on a team-mate is)
hd_y:       .res 1
score:      .res 2              ; goals, cyan and yellow
thrower:    .res 1              ; who takes the throw-in,
throw_t:    .res 1              ; frames left of its throw (THROW_T held)
lift:       .res 1              ; how high the ball is drawn over where it is
jmp_pl:     .res 1              ; the player in the air for a header,
jmp_t:      .res 1              ; and the frames he is still up
fouls:      .res PLAYERS        ; each player's fouls in the match
o_off:      .res NOBJ           ; 1: sent off - gone from the match
card_pl:    .res 1              ; the player shown a card while the ball is
card_c:     .res 1              ; dead, $FF none; 0 yellow, 1 red
r_t:        .res 1              ; the rules': attackers, the team's last
r_s:        .res 1              ; (the side: 0 top, 1 bottom)
; a test's plan for the joystick, by the match's frames: (frame low, high,
; J_ bits) each, $FFFF the end; dbg_on set to 2 starts it - the frames
; counted from then, and the match's own counters from 0 too, so that it
; goes the same way in any emulator
dbg_on:     .res 1
dbg_i:      .res 1              ; the next entry's place
dbg_t:      .res 2              ; frames since
dbg_bits:   .res 1              ; the stick as the plan has it
chaser2:    .res 1              ; the next nearest: in support, $FF none
deny_t:     .res 1              ; frames till the chaser may try a take again
y_pass_t:   .res 1              ; frames till the yellow team passes again
cpu_hold:   .res 1              ; looks the yellow chaser has had the ball
chaser:     .res 1              ; the other team's player after the ball,
                                ; $FF none
formation:  .res 2              ; each team's (data/tactics.txt), 0 4-4-2
d2:         .res 2              ; dist2's result
mate:       .res 1              ; pass's
mate_d:     .res 2
mate_t:     .res 2
kick_way:   .res 1              ; pass's: the way, 0-255
tmp:        .res 2
old_x:      .res 3              ; ball_move's: where it was
old_y:      .res 3
old_z:      .res 2
two:        .res 1              ; 1: two players, the yellow team the second
                                ; joystick's (the title's choice)
each_v:     .res 2              ; (each's routine)

        .segment "HIBSS2"       ; (not cleared: the title fills it)
; each player's skills, 0-7, by his number (title.s skills: his place's,
; his team's level, a step of his own)
sk:
sk_pace:    .res PLAYERS        ; how fast he runs
sk_ctl:     .res PLAYERS        ; ball control: the first touch, the dribble
sk_tck:     .res PLAYERS        ; tackling: winning the ball off a player
sk_hdg:     .res PLAYERS        ; heading: how far he reaches
sk_sht:     .res PLAYERS        ; shooting: how hard
.assert sk_sht - sk = 4 * 22, error, "title.s skills: five skills of 22"


        .rodata
; the line-ups for a kick-off, as Arlasoft Soccer has them: 4-4-2, keeper,
; defence, midfield, attack - x as the yellow team stands, then y as the
; cyan team (line_up mirrors x for the cyan team, y for the yellow). The
; team kicking off has a forward at the ball, the other beside him and
; the wingers up on the halfway line; the other team keeps out of the
; centre circle.
line_kick:  .word 304, 155, 255, 355, 455, 115, 245, 365, 409, 304, 275
            .word 689, 535, 557, 557, 535, 369, 445, 445, 369, 370, 369
line_back:  .word 304, 174, 264, 344, 434, 144, 274, 334, 464, 254, 354
            .word 678, 556, 556, 556, 556, 445, 489, 489, 445, 413, 413
line_lo:    .byte <line_kick, <line_back
line_hi:    .byte >line_kick, >line_back

; the joystick as a way to go (8: none)
joy_dir:    .byte 8, 0, 4, 8, 6, 7, 5, 6, 2, 1, 3, 2, 8, 0, 4, 8
; a destination 1000 pixels off, each way
vec_xl:     .byte <0, <1000, <1000, <1000, <0, <(-1000), <(-1000), <(-1000)
vec_xh:     .byte >0, >1000, >1000, >1000, >0, >(-1000), >(-1000), >(-1000)
vec_yl:     .byte <(-1000), <(-1000), <0, <1000, <1000, <1000, <0, <(-1000)
vec_yh:     .byte >(-1000), >(-1000), >0, >1000, >1000, >1000, >0, >(-1000)
; the dribble's kick, by the touches the same way / 4: faster than he
; runs by so much, less control's 16 a step (dribble)
drib_lo:    .byte <(1024 - 896 - 48), <(1089 - 896 - 48), <(1088 - 896 - 48), <(1216 - 896 - 48)
drib_hi:    .byte >(1024 - 896 - 48), >(1089 - 896 - 48), >(1088 - 896 - 48), >(1216 - 896 - 48)
; the players' speeds by their pace, 0-7 (speed: SP_*): running, with the
; ball at his feet, after the ball; 32 a step, 4 the speeds as measured
SP_RUN      = 0
SP_BALL     = 8
SP_CHASE    = 16
sp_lo:
.repeat 8, I
        .byte <(SPEED_RUN + (I - 4) * 32)
.endrepeat
.repeat 8, I
        .byte <(SPEED_BALL + (I - 4) * 32)
.endrepeat
.repeat 8, I
        .byte <(SPEED_CHASE + (I - 4) * 32)
.endrepeat
sp_hi:
.repeat 8, I
        .byte >(SPEED_RUN + (I - 4) * 32)
.endrepeat
.repeat 8, I
        .byte >(SPEED_BALL + (I - 4) * 32)
.endrepeat
.repeat 8, I
        .byte >(SPEED_CHASE + (I - 4) * 32)
.endrepeat
; a shot's speed by the shooting, 64 a step, 4 the shot as measured
shot_lo:
.repeat 8, I
        .byte <(SHOT_SPEED + (I - 4) * 64)
.endrepeat
shot_hi:
.repeat 8, I
        .byte >(SHOT_SPEED + (I - 4) * 64)
.endrepeat
; how near (squared) the ball must be to his head by his heading, 3 as
; measured (HEAD_D2)
head_d2:
.repeat 8, I
        .byte HEAD_D2 + 1 + (I - 3) * 12
.endrepeat
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
        ldx #CTX_N - 1          ; each team's control: its team, all else
:       lda ctx_new,x           ; none ($FF)
        sta ctx,x
        lda ctx_new_b,x
        sta ctx_b,x
        dex
        bpl :-
        lda two                 ; the yellow team's: a joystick's player only
        beq :+                  ; for two
        lda #20
        sta ctrl_b
:       lda #9                  ; the cyan team kicks off (line_up: rs_team
        sta ctrl                ; 0, as the program starts)
        sta taker
        lda #$FF                ; no one after the ball, no card
        sta chaser
        sta chaser2
        sta card_pl
        lda #1
        sta kickoff
        jmp sfx_whistle

; each team's control as a match starts: pj, ctrl ... t_end (ctx)
ctx_new:    .byte 0, $FF, 0, $FF, 0, $FF, $FF, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, $FF
ctx_new_b:  .byte 0, $FF, 0, $FF, 0, $FF, $FF, 0, 0, 0, $FF, 0, $FF, 0, 0, 1, 11, 21, 10
.assert * - ctx_new_b = CTX_N, error, "ctx_new_b: not CTX_N"

; each: the routine at A (low) / Y (high) for the cyan team's control,
; and with two players for the yellow team's too (swapped in)
each:
        sta each_v
        sty each_v + 1
        jsr @call
        lda two
        beq @done
        jsr swap
        jsr @call
        jmp swap
@call:  jmp (each_v)
@done:  rts

; swap: the two teams' controls traded (ctx, ctx_b)
swap:
        ldx #CTX_N - 1
:       lda ctx,x
        ldy ctx_b,x
        sta ctx_b,x
        tya
        sta ctx,x
        dex
        bpl :-
        rts

; calm: the ball dead - no one after it, no aftertouch, no pass on its
; way, the joystick's players standing
calm:
        lda #$FF
        sta chaser
        sta at_n
        sta at_n_b
        sta recv
        sta recv_b
        ldx ctrl_b
        bmi :+
        jsr stand
:       ldx ctrl
        jmp stand

; line_up: both teams lined up for a kick-off (rs_team's), standing
line_up:
        lda rs_team             ; the cyan team: the kick-off's line if it
        ldx #0                  ; takes it, else the other
        jsr @team
        lda rs_team             ; the yellow team likewise
        eor #1
        ldx #11
        jsr @team
        lda flip                ; the sides changed: each team where the
        beq @stand              ; other was
        ldx #10
@swap:  lda o_xl,x
        ldy o_xl + 11,x
        sta o_xl + 11,x
        tya
        sta o_xl,x
        lda o_xh,x
        ldy o_xh + 11,x
        sta o_xh + 11,x
        tya
        sta o_xh,x
        lda o_yl,x
        ldy o_yl + 11,x
        sta o_yl + 11,x
        tya
        sta o_yl,x
        lda o_yh,x
        ldy o_yh + 11,x
        sta o_yh + 11,x
        tya
        sta o_yh,x
        lda o_dir,x
        ldy o_dir + 11,x
        sta o_dir + 11,x
        tya
        sta o_dir,x
        dex
        bpl @swap
@stand: ldx #PLAYERS - 1        ; standing where they are
:       jsr stand
        dex
        bpl :-
        rts
; (A: 0 the kick-off's line, 1 the other; X the team's first)
@team:  tay
        lda line_lo,y
        sta z_ptr
        lda line_hi,y
        sta z_ptr + 1
        ldy #0
@pl:    lda (z_ptr),y           ; x
        sta z_ax
        iny
        lda (z_ptr),y
        sta z_ax + 1
        tya                     ; y, 11 words on
        clc
        adc #21
        tay
        lda (z_ptr),y
        sta z_ay
        iny
        lda (z_ptr),y
        sta z_ay + 1
        tya
        sec
        sbc #21
        tay                     ; (the next one's x)
        cpx #11
        bcs @top
        lda #<608               ; the cyan team: x mirrored, facing up
        sec
        sbc z_ax
        sta o_xl,x
        lda #>608
        sbc z_ax + 1
        sta o_xh,x
        lda z_ay
        sta o_yl,x
        lda z_ay + 1
        sta o_yh,x
        lda #0
        beq @dir
@top:   lda z_ax                ; the yellow team: y mirrored, facing down
        sta o_xl,x
        lda z_ax + 1
        sta o_xh,x
        lda #<738
        sec
        sbc z_ay
        sta o_yl,x
        lda #>738
        sbc z_ay + 1
        sta o_yh,x
        lda #4
@dir:   sta o_dir,x
        lda #0
        sta o_xf,x
        sta o_yf,x
        inx
        cpy #22
        bne @pl
        rts

; top_of: A = 1 if player X's team plays from the top (attacking down),
; 0 from the bottom; Z set for 0. Keeps X, Y.
top_of:
        lda #0
        cpx #11
        bcc :+
        lda #1
:       eor flip
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
        jsr clock
        jsr throwing
        lda jmp_t               ; (a header's jump down again)
        beq :+
        dec jmp_t
:
        inc frame_n
        lda dbg_on              ; (a test's plan: the stick as it says,
        beq :+                  ; frame by frame)
        jsr dbg_step
:
        lda dead_t              ; the ball dead: it rolls on, no one has
        beq @live               ; it, the others go to their places
        lda full                ; (full time: dead till fire)
        beq :+
        jsr new_match
:       dec dead_t
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
@live:  lda touch_t             ; (frames since the ball's last touch,
        cmp #255                ; and the cyan team's last kick)
        beq :+
        inc touch_t
:       lda y_pass_t
        beq :+
        dec y_pass_t
:       lda deny_t
        beq :+
        dec deny_t
:       lda joy                 ; each team's joystick: one player either,
        ldy two                 ; two the first and the second
        beq :+
        lda joy_b
        sta pj_b
        lda joy_a
:       sta pj
        lda #<control
        ldy #>control
        jsr each
        lda frame_n             ; the others' minds every second frame, as
        lsr a                   ; Sensible Soccer's
        bcs :+
        jsr team_ai
:       jsr slides
        ldx ctrl                ; the two at the ball and the keepers,
        jsr @one                ; every frame
        ldx ctrl_b
        bmi :+
        jsr @one
:       ldx chaser
        bmi :+
        jsr @one
:       jsr keepers_move
        jsr others
        lda #<aftertouch
        ldy #>aftertouch
        jsr each
        jsr ball_move
        jsr catch
        jsr rules
        lda frame_n
        lsr a
        bcs :+
        lda #<switch            ; (every second frame)
        ldy #>switch
        jmp each
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
@one:   lda o_dive,x            ; (a dive's time)
        beq :+
        dec o_dive,x
:       cpx ctrl
        beq :+
        cpx ctrl_b
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
        cpx ctrl_b
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
        lda kick_t              ; (frames since his team's last kick)
        cmp #255
        beq :+
        inc kick_t
:       lda recv_t
        beq :+
        dec recv_t
:       ldx ctrl
        lda o_slide,x           ; (sliding: the stick has no say)
        beq :+
        rts
:       lda kickoff             ; his team's set piece: the stick turns
        bne @set                ; the taker, fire kicks
        lda pass_q              ; in play: a pass let go of too soon goes
        beq :+                  ; as the ball comes to him
        dec pass_q
        jsr can_kick
        bcs :+
        lda #0
        sta pass_q
        jmp pass
:       jsr trap                ; the first touch
        jmp @stick
@set:   lda rs_team
        cmp me
        bne @stick
        lda pj
        and #$0F
        tay
        lda joy_dir,y
        cmp #8
        beq :+
        sta o_dir,x
:       jmp @fire
@stick: lda pj
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
        ldy #SP_RUN
        jsr speed
        lda d2 + 1
        bne @far
        lda d2
        cmp #CLOSE + 1
        bcs @far
        ldy #SP_BALL
        jsr speed
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
        lda me                  ; (nor while the other team holds it)
        jsr held
        bcs @far
        jsr dribble
@far:   lda kickoff
        beq @fire
        rts
@fire:  lda pj                  ; fire: let go within SHOT_HOLD - 1
        and #J_FIRE             ; frames a pass, held SHOT_HOLD frames
        beq @let                ; a shot - as soon as the ball is at his
        lda fire_n              ; feet, once held so long
        cmp #$FF
        beq @done               ; (shot)
        lda kickoff             ; fire down, the ball at his head: a header
        bne @foot
        ldx ctrl
        jsr can_head
        bcs :+
        jmp head_it
:       lda fire_n              ; just pressed, the ball in the air before
        bne @foot               ; him: a diving header
        jsr can_dive
        bcs @foot
        lda #$FF
        sta fire_n
        jmp dive_head
@foot:  lda fire_n
        cmp #SHOT_HOLD
        bcs :+
        inc fire_n
        lda fire_n
        cmp #1                  ; just pressed, the other team holding the
        bne @held               ; ball: a sliding tackle
        lda kickoff
        bne @held
        lda me
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
        bcs @wait
        jmp pass
@wait:  lda #PASS_Q             ; (too soon: it goes as the ball comes)
        sta pass_q
@done:  rts

; meet: the joystick's player X, the stick let go: a ball come to his
; feet from someone else he stops there; a pass to him he goes to meet;
; else he stands. Keeps X.
meet:
        jsr dist2
        lda last_pl             ; (his own kick runs on)
        cmp ctrl
        beq @stand
        lda me                  ; (one the other team holds: only a tackle)
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
        lda me
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
        ldy #SP_RUN
        jsr speed
        lda #1
        sta o_mov,x
        rts
@stand: jmp stand

; inside: player X's destination inside the walls round the pitch (the
; ball's, x 19-588, y 20-719; at the top 30: his head below the boards'
; row - simple-soccer.s TOP_Y) - no one runs into the stands. Keeps X.
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
        cmp #<30
        lda o_tyh,x
        sbc #>30
        bcs :+
@y0:    lda #<30
        sta o_tyl,x
        lda #>30
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

; walls: player X kept inside the walls as inside keeps his destination
; (the place's bytes as far after its as for each other: see the .bss).
; Keeps X.
walls:
        txa
        pha
        clc
        adc #o_xl - o_txl
        tax
        jsr inside
        pla
        tax
        rts
        .assert o_xh - o_txh = o_xl - o_txl && o_yl - o_tyl = o_xl - o_txl && o_yh - o_tyh = o_xl - o_txl && o_xl - o_txl + NOBJ <= 256, error, "walls: the places as far after the destinations"

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

; can_head: carry clear if the ball is at player X's head: HEAD_Z_LO to
; HEAD_Z_HI high, near enough for his heading (head_d2). Keeps X.
can_head:
        lda o_zl + BALL
        cmp #HEAD_Z_LO
        bcc @no
        cmp #HEAD_Z_HI + 1
        bcs @no
        jsr mate_dist
        lda tmp + 1
        bne @no
        ldy sk_hdg,x            ; (by his heading)
        lda tmp
        cmp head_d2,y
        rts
@no:    sec
        rts

; can_dive: carry clear if the ball is in the air before player X, low
; enough for a diving header (DHEAD_Z_LO to DHEAD_Z_HI), not at his feet
; (HEAD_D2) but in reach of one (DHEAD_D2), within 45 degrees of the way
; he faces. Keeps X.
can_dive:
        lda o_zl + BALL
        cmp #DHEAD_Z_LO
        bcc @no
        cmp #DHEAD_Z_HI + 1
        bcs @no
        jsr mate_dist
        lda tmp + 1             ; (not at his feet: his to take there)
        bne :+
        lda tmp
        cmp #HEAD_D2 + 1
        bcc @no
:       lda tmp
        cmp #<(DHEAD_D2 + 1)
        lda tmp + 1
        sbc #>(DHEAD_D2 + 1)
        bcs @no
        jsr mate_way            ; the way from the ball to him, turned
        bcs @no                 ; round: to the ball
        eor #128
        sta tmp
        lda o_dir,x
        lsr a
        ror a
        ror a
        ror a                   ; (way * 32)
        sec
        sbc tmp
        clc
        adc #32
        cmp #65
        rts
@no:    sec
        rts

; head_it: the joystick's player heads the ball, the way the stick points
; (or he faces)
head_it:
        lda #$FF
        sta fire_n
        sta drib_dir
        lda #0
        sta kick_t
        stx kick_pl
        lda pj
        and #$0F
        tay
        lda joy_dir,y
        cmp #8
        bne :+
        lda o_dir,x
:       tay
        lda me
        ; (on into header)

; header: player X heads the ball way Y, for team A - up to it, the ball
; on that way
header:
        sta last_team
        jsr touch
        stx last_pl
        stx jmp_pl
        tya
        sta o_dir,x
        lda #JUMP_T
        sta jmp_t
        jsr ball_ahead
        lda #<HEAD_SPEED
        sta o_spl + BALL
        lda #>HEAD_SPEED
        sta o_sph + BALL
        lda #<HEAD_DZ
        sta o_dzf + BALL
        lda #>HEAD_DZ
        sta o_dzl + BALL
        jmp sfx_kick

; dive_head: player X dives for the ball, a sliding tackle in the air
; (slides heads it on when he reaches it). Keeps X.
dive_head:
        jsr slide
        lda #1
        sta o_hd,x
        rts

; shot: the ball the way the joystick's player faces, hard (his shooting)
; and rising; the aftertouch on
shot:
        lda #0
        sta kick_t
        lda me
        sta last_team
        jsr touch
        lda ctrl
        sta last_pl
        sta kick_pl
        ldx ctrl
        ldy o_dir,x
        sty at_dir
        jsr ball_ahead
        jsr shot_speed
        lda #<SHOT_DZ
        sta o_dzf + BALL
        lda #>SHOT_DZ
        sta o_dzl + BALL
        jsr sfx_kick
        lda #0
        sta at_n
        lda #$FF
        sta drib_dir
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
:       lda pj                  ; the joystick's way, 8 none
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

; dribble: the ball kicked on ahead, the way the joystick's player runs,
; faster than he runs by drib_* and (7 - control) * 16 - and with 7 -
; control in 128 a touch too heavy, 384 faster
dribble:
        lda me
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
        clc
        adc o_spl,x
        sta o_spl + BALL
        lda drib_hi,y
        adc o_sph,x
        sta o_sph + BALL
        lda sk_ctl,x
        eor #7
        sta tmp
        asl a
        asl a
        asl a
        asl a                   ; (carry clear: at most 112)
        adc o_spl + BALL
        sta o_spl + BALL
        bcc :+
        inc o_sph + BALL
:       jsr rnd
        and #127
        cmp tmp
        bcs :+
        lda o_spl + BALL
        adc #<384               ; (carry clear)
        sta o_spl + BALL
        lda o_sph + BALL
        adc #>384
        sta o_sph + BALL
:       inc drib_n
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

; trap: the first touch - a ball come to the joystick's player from
; someone else, low and in his reach (can_kick), not the other team's on
; it, is his touch: stopped at his feet, or, rolled against his control
; (10 + control in 16, a ball slower than a pass 4 more), a touch too
; heavy - on at half its speed. Keeps X (ctrl).
trap:
        ldx ctrl
        cpx last_pl
        beq @no                 ; (his own)
        lda me
        jsr held
        bcs @no
        jsr can_kick
        bcs @no
        lda me
        sta last_team
        stx last_pl
        jsr touch
        lda #$FF                ; (a pass met)
        sta recv
        lda sk_ctl,x
        adc #10                 ; (carry clear)
        ldy o_sph + BALL
        cpy #>1536
        bcs :+
        adc #4
:       sta tmp
        jsr rnd
        and #15
        cmp tmp
        bcs @heavy
        ldx #BALL
        jsr stand
        ldx ctrl
@no:    rts
@heavy: lsr o_sph + BALL
        ror o_spl + BALL
        rts

; wins: carry clear if player X wins the ball off the one on it (last_pl):
; A (a take 6, a sliding tackle 10) + his tackling - that one's control
; in 16, rolled. Keeps X.
wins:
        ldy last_pl
        clc
        adc sk_tck,x
        sec
        sbc sk_ctl,y
        bpl :+
        lda #0
:       sta tmp
        jsr rnd
        and #15
        cmp tmp
        rts

; rnd: A a byte at random - a shift register, stirred by where the beam
; is along its line. Keeps X, Y.
rnd:
        lda z_rnd
        asl a
        bcc :+
        eor #$1D
:       eor $FF1E
        sta z_rnd
        rts

; speed: player X's speed Y (SP_*) as fast as his pace. Keeps X.
speed:
        tya
        clc
        adc sk_pace,x
        tay
        lda sp_lo,y
        sta o_spl,x
        lda sp_hi,y
        sta o_sph,x
        rts

; shot_speed: the ball as hard as player X shoots (his shooting). Keeps X.
shot_speed:
        ldy sk_sht,x
        lda shot_lo,y
        sta o_spl + BALL
        lda shot_hi,y
        sta o_sph + BALL
        rts

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

; pass: the ball to the nearest team-mate within 67.5 degrees of the way
; the joystick's player faces - one more than 22.5 off it as if twice as
; far: the one the way he faces if there is one near enough, else the
; nearest to that side; or, no one, straight on
pass:
        lda #0
        sta kick_t
        lda me
        sta last_team
        jsr touch
        lda ctrl
        sta last_pl
        sta kick_pl
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
        ldx t_hi
@look:  cpx ctrl
        beq @next
        jsr mate_way            ; the way from the ball to him, 0-255
        bcs @next               ; (on the ball)
        sec
        sbc kick_way            ; within 48 of the way he kicks
        clc
        adc #48
        cmp #97
        bcs @next
        sbc #32 - 1             ; (carry clear: within 16 under 33)
        sta z_off
        jsr mate_dist           ; the nearest
        lda z_off
        cmp #33
        bcc :+
        asl tmp                 ; (further off: twice as far)
        rol tmp + 1
        bcc :+
        lda #$FF
        sta tmp
        sta tmp + 1
:       lda tmp
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
        cpx t_end
        bne @look
        ldx mate
        bmi :+
        stx recv                ; he runs to meet it (help), the joystick
        stx helper              ; to the nearest of the others (switch)
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
        jsr sfx_kick
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
        lda o_off,x             ; (one sent off: nowhere)
        bne @far
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
        lda o_slide,x           ; (a sliding tackle's way leads far on: he
        beq :+                  ; stops at the walls)
        jsr walls
:       lda o_vxf,x             ; still: there - the standing picture, and
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
; towards the goal and shoots from close to it. Before a kick-off no
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
        lda rs_kind             ; a kick-off: everyone stays in line
        bne @play
        rts
@play:  lda kickoff             ; (a free kick, a penalty waiting: they
        beq :+                  ; stay where they were put)
        lda rs_kind
        cmp #R_FREE
        bcc :+
        rts
:       lda frame_n
        ora two                 ; (the yellow team's own, unless a player's)
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
        cpx ctrl_b
        beq @next
        cpx chaser
        beq @next
        cpx chaser2
        beq @next
        cpx helper
        beq @next
        cpx helper_b
        beq @next
        lda o_slide,x           ; (one lying stays down, one sent off away)
        ora o_off,x
        bne @next
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
:       lda #<help
        ldy #>help
        jsr each
        lda two                 ; the yellow team on its own: its chaser
        bne :+                  ; and the one in support
        jsr support
        jmp chase
:       rts

; place_formation: player X's destination, his place in the formation for
; where the ball is; jogging. Keeps X.
place_formation:
        stx z_obj
        txa                     ; the team's formation
        ldy formation
        cpx #11
        bcc :+
        ldy formation + 1
:       sta z_ti                ; (the sides changed: the other team's
        lda flip                ; areas - the tables have the team at the
        beq :+                  ; bottom first)
        lda z_ti
        clc
        adc #11
        cmp #22
        bcc :++
        sbc #22
        bcs :++
:       lda z_ti
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

form22: .byte 0                 ; (the formations built in: mkdata FORMATIONS)

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
        sta mate_t              ; (the next nearest's)
        sta mate_t + 1
        sta chaser2
        sta mate
        ldx #PLAYERS - 1
@look:  jsr mate_dist
        lda tmp
        cmp mate_d
        lda tmp + 1
        sbc mate_d + 1
        bcs @second
        lda mate_d              ; nearest: the one before is next
        sta mate_t
        lda mate_d + 1
        sta mate_t + 1
        lda mate
        sta chaser2
        lda tmp
        sta mate_d
        lda tmp + 1
        sta mate_d + 1
        stx mate
        jmp @on
@second:
        lda tmp
        cmp mate_t
        lda tmp + 1
        sbc mate_t + 1
        bcs @on
        lda tmp
        sta mate_t
        lda tmp + 1
        sta mate_t + 1
        stx chaser2
@on:    dex
        cpx #11
        bne @look
        lda mate
        sta chaser
@done:  rts

; chase: the chaser after the ball - at his feet, towards the goal at the
; bottom, and a shot from close to it. A cyan player with the ball he
; stays on, as Arlasoft Soccer's do, and it is his once it is at his feet
; nearer him than the cyan player - kicked on into him, or let go.
chase:
        ldx chaser
        bmi @done
        stx z_obj
        lda o_slide,x           ; (sliding: slides has him)
        bne @done
        jsr can_head            ; the ball at his head: headed towards the
        bcs :+                  ; cyan goal, down (the sides changed: up)
        ldy #4
        lda flip
        beq @hd
        ldy #0
@hd:    lda #1
        jsr header
        lda #$FF                ; (a moment before he goes after it again)
        sta chaser
        rts
:        lda #1
        sta o_mov,x
        jsr ball_near           ; at his feet, and not the cyan team's?
        bcs :+
        lda #1
        jsr held
        bcc @have
        jsr nearer              ; the cyan team's, right at his feet: a
        bcs :+                  ; take, his tackling against the other's
        lda deny_t              ; control - not again for a while once
        bne :+                  ; missed
        lda #6
        jsr wins
        bcc @have
        lda #DENY_T
        sta deny_t
:       lda #0                  ; (not his)
        sta cpu_hold
        lda frame_n             ; after it (where it is, each second frame:
        and #1                  ; a little faster than one running with it,
        bne @done               ; he catches up)
        lda o_xl + BALL
        sta o_txl,x
        lda o_xh + BALL
        sta o_txh,x
        lda o_yl + BALL
        sta o_tyl,x
        lda o_yh + BALL
        sta o_tyh,x
        ldy #SP_CHASE
        jsr speed
@done:  rts
@have:  ; near the goal: a shot at it
        inc cpu_hold
        jsr in_range
        bcs @shoot
        jsr cpu_pass            ; (a cyan player close, or had it a while:
                                ; a pass on)
        bcc @done2
        ldx z_obj
        jmp @run
@done2: rts
@shoot:
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
        ldy flip                ; (1000 on towards it)
        lda shot_dyl,y
        clc
        adc o_yl + BALL
        sta o_tyl + BALL
        lda shot_dyh,y
        adc o_yh + BALL
        sta o_tyh + BALL
        jsr shot_speed
        lda #<SHOT_DZ
        sta o_dzf + BALL
        lda #>SHOT_DZ
        sta o_dzl + BALL
        lda #1
        sta last_team
        jsr touch
        stx last_pl
        jsr sfx_kick
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
@dir:   lda flip                ; (the sides changed: up, or up and in)
        beq :+
        tya
        eor #$FF
        sec
        adc #4
        and #7
        tay
:       tya
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
        ldy #SP_BALL
        jsr speed
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

; switch: as Sensible Soccer and the C64 do it, every second frame: the
; joystick's player keeps it while he has the ball at his feet; else it
; goes to whoever of the team gets to the ball (CLOSE, low), else to the
; player nearest it - not the helper on his way to it, not the one who
; has just passed or shot, not the keeper
switch:
        lda kickoff             ; (his team's set piece: the taker keeps
        beq :+                  ; it)
        lda rs_team
        cmp me
        bne :+
        rts
:       ldx ctrl                ; (nor from one sliding)
        lda o_slide,x
        beq :+
        rts
:       lda frame_n
        lsr a
        bcs @done
        ldx ctrl                ; at the ball: the joystick's, or another
        jsr near_ball
        bcs @done
        ldx t_hi
@at:    cpx ctrl
        beq :+
        jsr at_ball
        bcs @got
:       dex
        cpx t_lo
        bne @at
        lda #$FF                ; else the nearest
        sta mate_d
        sta mate_d + 1
        sta mate
        ldx t_hi
@look:  cpx helper
        beq @next
        jsr kicker
        bcs @next
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
        cpx t_lo
        bne @look
        ldx mate
        bmi @done               ; (no one)
@got:   cpx ctrl
        beq @done
        stx ctrl                ; (the last one goes back to his place:
        cpx helper              ; team_ai)
        bne @done
        lda #$FF                ; (the helper there: he has it now)
        sta helper
@done:  rts

; kicker: carry set if cyan player X passed or shot KICKED_T frames ago
; or less. Keeps X.
kicker:
        cpx kick_pl
        bne :+
        lda kick_t
        cmp #KICKED_T
        bcs :+
        sec
        rts
:       clc
        rts

; at_ball: carry set if cyan player X is at the ball (CLOSE, low) and is
; not the one who has just passed or shot (kicker); near_ball the same,
; whoever he is. Keeps X.
at_ball:
        jsr kicker
        bcs at_no
near_ball:
        lda o_zl + BALL
        cmp #HOLD_Z + 1
        bcs at_no
        jsr mate_dist
        lda tmp + 1
        bne at_no
        lda tmp
        cmp #CLOSE + 1
        bcs at_no
        sec
        rts
at_no:  clc
        rts

; help: the cyan player nearest a ball his team has not got - not the
; joystick's, not the keeper - runs to it on his own, as Sensible
; Soccer's and the C64's do (switch gives him the joystick there); a
; pass's receiver while it runs to him. Chosen anew each eighth frame;
; team_ai: every second one.
help:
        lda kickoff
        ora dead_t
        bne :+
        lda recv_t              ; (a pass to him on its way: he runs)
        beq @own
        lda recv
        cmp helper
        beq @run
@own:   lda me                  ; (his team's: no one)
        eor #1
        jsr held
        bcc @in
:       lda #$FF
        sta helper
        rts
@in:    lda frame_n
        and #6
        bne @run
        lda #$FF
        sta mate_d
        sta mate_d + 1
        sta mate
        ldx t_hi
@look:  cpx ctrl
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
        cpx t_lo
        bne @look
        lda mate
        sta helper
@run:   ldx helper
        bmi @out
        cpx ctrl                ; (the joystick has him now)
        beq @none
        lda #1
        sta o_mov,x
        sta o_new,x             ; (the way to it worked out anew)
        lda o_xl + BALL
        sta o_txl,x
        lda o_xh + BALL
        sta o_txh,x
        lda o_yl + BALL
        sta o_tyl,x
        lda o_yh + BALL
        sta o_tyh,x
        ldy #SP_CHASE
        jsr speed
@out:   rts
@none:  lda #$FF
        sta helper
        rts

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
        lda kickoff             ; (a set piece not yet taken: it lies still,
        ora throw_t             ; nor a throw-in flying in from outside,
        ora dead_t              ; nor a ball dead for a foul)
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
@y:     ldy #0                  ; the top goal line (the cyan team attacks
                                ; it, sides not changed)
        lda o_yl,x
        cmp #<LINE_T
        lda o_yh,x
        sbc #>LINE_T
        bcc @line
        iny                     ; the bottom one
        lda #<LINE_B
        cmp o_yl,x
        lda #>LINE_B
        sbc o_yh,x
        bcc @line
        rts
@line:  sty r_s                ; (the side)
        tya                     ; (the attackers: the side's other team,
        eor flip                ; the sides changed)
        sta r_t
        tay
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
        jsr sfx_goal
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
        ldy r_s
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
        ldy r_s
        lda gkick_yl,y
        sta rs_y
        lda gkick_yh,y
        sta rs_y + 1
@dead:  lda #DEAD_OUT
@dead2: sta dead_t
        jsr net                 ; (a goal: in the net already in this frame)
        jmp calm

corner_xl:  .byte <54, <553     ; left, right
corner_xh:  .byte >54, >553
corner_yl:  .byte <54, <684     ; top, bottom
corner_yh:  .byte >54, >684
gkick_xl:   .byte <244, <364
gkick_xh:   .byte >244, >364
gkick_yl:   .byte <74, <664
gkick_yh:   .byte >74, >664

; net: the dead ball after a goal held by the net - it stops where the
; net is drawn (NET_T, NET_B behind the line), the side netting keeps it
; inside the posts (NET_L, NET_R), and the roof sends a rising ball down
net:
        lda goal
        beq @done
        ldx #BALL
        lda o_yl,x
        cmp #<(LINE_T - NET_T)
        lda o_yh,x
        sbc #>(LINE_T - NET_T)
        bcs :+
        lda #<(LINE_T - NET_T)
        ldy #>(LINE_T - NET_T)
        jmp @stop
:       lda #<(LINE_B + NET_B)
        cmp o_yl,x
        lda #>(LINE_B + NET_B)
        sbc o_yh,x
        bcs @sides
        lda #<(LINE_B + NET_B)
        ldy #>(LINE_B + NET_B)
@stop:  sta o_yl,x
        tya
        sta o_yh,x
        lda #0
        sta o_yf,x
        sta o_spl,x
        sta o_sph,x
        lda o_dzl,x             ; rising: falls from here (dz just under 0:
        bmi @sides              ; 0 would leave it lying in the air)
        lda #$FF
        sta o_dzl,x
        sta o_dzf,x
@sides: lda o_xl,x
        cmp #<NET_L
        lda o_xh,x
        sbc #>NET_L
        bcs :+
        lda #<NET_L
        ldy #>NET_L
        jmp @x
:       lda #<NET_R
        cmp o_xl,x
        lda #>NET_R
        sbc o_xh,x
        bcs @done
        lda #<NET_R
        ldy #>NET_R
@x:     sta o_xl,x
        tya
        sta o_xh,x
        lda #0
        sta o_xf,x
@done:  rts

; restart: the dead time over - the ball put down, the taker to it
restart:
        ldx card_pl             ; a red card: off
        bmi :+
        lda card_c
        beq :+
        jsr send_off
:       lda #$FF
        sta card_pl
        lda #0
        sta goal
        ldx #PLAYERS - 1        ; everyone up again (a foul's lying)
:       sta o_slide,x
        dex
        bpl :-
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
        jsr sfx_whistle
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
        ldy #0                  ; (a free kick, a penalty: facing the goal
        lda rs_kind             ; it is for)
        cmp #R_FREE
        bcc :+
        ldy #2
        lda rs_team
        eor flip
        beq :+
        ldy #4
:       lda face_y,y
        sec
        sbc o_yl + BALL
        sta z_ay
        lda face_y + 1,y
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
        jsr throw_in
        jsr stand
        jsr set_wall
        jmp await

face_y:     .word 369, LINE_T, LINE_B   ; the middle, the top goal, the bottom

; ---- fouls ----------------------------------------------------------------
;
; A sliding tackle into the player on the ball from behind - facing within
; 45 degrees of the way he does - before it gets the ball is a foul: the
; whistle, the player down, a free kick for his team where he lies, a
; penalty if that is in the box his team attacks. For a free kick the
; other team's players near the ball stand off between it and their goal,
; a wall; for a penalty everyone but the taker and the keeper leaves the
; box.

; foul_on: carry set if sliding player X is into the other team's player
; on the ball from behind, FOUL_R near either way. Keeps X.
foul_on:
        lda #0
        cpx #11
        bcc :+
        lda #1
:       jsr held                ; (the other team's ball)
        bcc @no
        ldy last_pl
        lda o_dir,x             ; from behind: the ways 7, 0, 1 apart
        sec
        sbc o_dir,y
        clc
        adc #1
        and #7
        cmp #3
        bcs @no
        lda o_xl,x
        sec
        sbc o_xl,y
        sta tmp
        lda o_xh,x
        sbc o_xh,y
        jsr abs16
        bne @no
        cmp #FOUL_R
        bcs @no
        ldy last_pl
        lda o_yl,x
        sec
        sbc o_yl,y
        sta tmp
        lda o_yh,x
        sbc o_yh,y
        jsr abs16
        bne @no
        cmp #FOUL_R
        bcs @no
        sec
        rts
@no:    clc
        rts

; foul: player X has fouled the player on the ball - the whistle, the
; ball dead, him down, a free kick or penalty for his team; for the
; fouler's second foul a yellow card, for his fourth (a second yellow)
; a red, and he is off when play goes on (restart)
foul:
        lda #$FF
        sta card_pl
        inc fouls,x
        lda fouls,x
        lsr a
        bcs @tally              ; (an odd one: no card)
        stx card_pl
        cmp #2                  ; (fouls / 2: 1 yellow, 2 red)
        lda #0
        bcc :+
        lda #1
:       sta card_c
@tally: ldx last_pl
        lda #1                  ; down (slides lets him up when play goes on:
        sta o_slide,x           ; restart)
        lda #0
        sta o_hd,x
        jsr stand
        lda last_team
        sta rs_team
        eor flip
        sta r_s                 ; (the side his team attacks: 0 the top)
        lda #R_FREE             ; where he lies
        sta rs_kind
        lda o_xl,x
        sta rs_x
        lda o_xh,x
        sta rs_x + 1
        lda o_yl,x
        sta rs_y
        lda o_yh,x
        sta rs_y + 1
        jsr in_box              ; in the box: a penalty, from the spot
        bcs @free
        lda #R_PENALTY
        sta rs_kind
        lda #<304
        sta rs_x
        lda #>304
        sta rs_x + 1
        ldy r_s
        lda spot_l,y
        sta rs_y
        lda spot_h,y
        sta rs_y + 1
@free:  lda #DEAD_OUT
        sta dead_t
        jsr sfx_whistle
        jmp calm

; send_off: player X off the pitch for good - not drawn, not in the
; team's play, never near the ball (mate_dist); the joystick, a run to
; the ball, a pass to him on to someone else
send_off:
        lda #1
        sta o_off,x
        jsr stand
        txa
        tay
@next:  iny                     ; (a team-mate: the next one, not the
        cpy #11                 ; keeper, not one off)
        bne :+
        ldy #1
:       cpy #22
        bne :+
        ldy #12
:       lda o_off,y
        bne @next
        cpx ctrl
        bne :+
        sty ctrl
:       cpx ctrl_b
        bne :+
        sty ctrl_b
:       lda #$FF
        cpx helper
        bne :+
        sta helper
:       cpx helper_b
        bne :+
        sta helper_b
:       cpx recv
        bne :+
        sta recv
:       cpx recv_b
        bne :+
        sta recv_b
:       rts

spot_l:     .byte <SPOT_T, <SPOT_B
spot_h:     .byte >SPOT_T, >SPOT_B

; in_box: carry clear if player X is in the penalty area at side r_s
; (0 the top). Keeps X.
in_box:
        lda o_xl,x
        cmp #<BOX_L
        lda o_xh,x
        sbc #>BOX_L
        bcc @no
        lda #<BOX_R
        cmp o_xl,x
        lda #>BOX_R
        sbc o_xh,x
        bcc @no
        lda r_s
        bne :+
        lda o_yl,x              ; the top: y < BOX_T
        cmp #<BOX_T
        lda o_yh,x
        sbc #>BOX_T
        rts
:       lda #<BOX_B             ; the bottom: y > BOX_B
        cmp o_yl,x
        lda #>BOX_B
        sbc o_yh,x
        rts
@no:    sec
        rts

; set_wall: a free kick's or a penalty's players placed, the taker behind
; the ball already (restart)
set_wall:
        lda rs_kind
        cmp #R_FREE
        bcs :+
        rts
:       lda rs_team
        eor flip
        sta r_s
        ldx #PLAYERS - 1
@pl:    jsr wall_one
        dex
        bpl @pl
        rts

; wall_one: set_wall's player X. Keeps X.
wall_one:
        cpx taker
        bne :+
@next:  rts
:       lda rs_kind
        cmp #R_PENALTY
        beq @pen
        cpx #11                 ; a free kick: the other team's within
        lda #0                  ; WALL_D of the ball, WALL_D nearer their
        rol a                   ; goal
        cmp rs_team
        beq @next
        jsr wall_near
        bcs @next
        lda r_s
        bne :+
        lda o_yl + BALL
        sec
        sbc #WALL_D
        sta o_yl,x
        lda o_yh + BALL
        sbc #0
        jmp @put
:       lda o_yl + BALL
        clc
        adc #WALL_D
        sta o_yl,x
        lda o_yh + BALL
        adc #0
        jmp @put
@pen:   txa                     ; a penalty: the keeper on his line, the
        beq @keeper             ; others out of the box
        cpx #11
        beq @keeper
        jsr in_box
        bcs @next
        ldy r_s
        lda box_out,y
        sta o_yl,x
        lda #>BOX_B             ; (BOX_T + 12 and BOX_B - 12: the high
        cpy #0                  ; byte 0 and BOX_B's)
        bne @put
        lda #0
        beq @put
@keeper:
        cpx #11                 ; (only the one whose goal it is)
        lda #0
        rol a
        cmp rs_team
        beq @next
        lda #<304
        sta o_xl,x
        lda #>304
        sta o_xh,x
        ldy r_s
        lda line_in,y
        sta o_yl,x
        lda #>LINE_B
        cpy #0
        bne @put
        lda #0
@put:   sta o_yh,x
        lda #0
        sta o_yf,x
        sta o_xf,x
        lda o_yh,x              ; (on the pitch)
        bne :+
        lda o_yl,x
        cmp #LINE_T
        bcs @st
        lda #LINE_T
        sta o_yl,x
        bne @st
:       lda o_yl,x
        cmp #<LINE_B
        bcc @st
        lda #<LINE_B
        sta o_yl,x
@st:    jmp stand

box_out:    .byte <(BOX_T + 12), <(BOX_B - 12)
line_in:    .byte <(LINE_T + 4), <(LINE_B - 4)
.assert >(BOX_T + 12) = 0 && >(BOX_B - 12) = >BOX_B && >(LINE_B - 4) = >LINE_B, error, "set_wall: high bytes"

; wall_near: carry clear if player X is within WALL_D of the ball either
; way. Keeps X.
wall_near:
        lda o_xl,x
        sec
        sbc o_xl + BALL
        sta tmp
        lda o_xh,x
        sbc o_xh + BALL
        jsr abs16
        bne @no
        cmp #WALL_D
        bcs @no
        lda o_yl,x
        sec
        sbc o_yl + BALL
        sta tmp
        lda o_yh,x
        sbc o_yh + BALL
        jsr abs16
        bne @no
        cmp #WALL_D
        rts
@no:    sec
        rts

; throw_in: a throw-in's taker X behind the touch line, 5 pixels out
; (clear of it: his arms and the ball are as light as the lines), the
; ball 7 out, behind his head (throwing) - rules lets it fly in. Keeps X.
throw_in:
        lda rs_kind
        cmp #R_THROW
        bne @done
        stx thrower
        lda o_xl + BALL
        ldy o_xh + BALL
        bne @right
        sec                     ; the left line
        sbc #7
        sta o_xl + BALL
        clc
        adc #2
        bne @x
@right: clc
        adc #7
        sta o_xl + BALL
        sec
        sbc #2
@x:     sta o_xl,x
        lda o_xh + BALL
        sta o_xh,x
        lda o_yl + BALL
        sta o_yl,x
        lda o_yh + BALL
        sta o_yh,x
        lda #THROW_T
        sta throw_t
        lda #THROW_HOLD
        sta lift
@done:  rts

; throwing: a frame of the throw-in's look - the ball up over the taker's
; head while he holds it, then thrown from there: lift, how high it is
; drawn over where it is (on the ground, as far as the match goes)
throwing:
        lda kickoff
        beq @thrown
        lda rs_kind
        cmp #R_THROW
        bne @none
        lda #THROW_T
        sta throw_t
        lda #THROW_HOLD
        sta lift
        rts
@thrown:
        ldy throw_t
        beq @none
        dey
        sty throw_t
        lda throw_arc,y
        sta lift
        rts
@none:  lda #0
        sta throw_t
        sta lift
        rts

throw_arc:  .byte 0, 5, 9, 13, 16, 18, 20, 21, 21, 20   ; (from the last)

; await: the set piece ready, for taker to take: a player's team's with
; his joystick (fire held on from before does not kick), the yellow
; team on its own after a while
await:
        lda #$FF
        sta chaser
        sta at_n
        sta at_n_b
        sta recv
        sta recv_b
        lda rs_team
        bne @yellow
        lda taker
        sta ctrl
        lda #$FF
        sta fire_n
        bne @go
@yellow:
        lda two
        beq @cpu
        lda taker
        sta ctrl_b
        lda #$FF
        sta fire_n_b
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
        lda o_off,x             ; (not one sent off)
        bne @skip
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
@skip:
:       cpx r_t
        bne @look
        ldx mate
        rts

; cpu_take: the yellow team's set piece, once it has waited: passed to
; the nearest team-mate, or kicked on the way the taker faces
cpu_take:
        lda rs_team
        beq @done
        lda two                 ; (a player's: his to take)
        bne @done
        dec cpu_t
        bne @done
        lda #1
        sta last_team
        jsr touch
        lda taker
        sta last_pl
        lda rs_kind             ; a penalty: shot at a corner
        cmp #R_PENALTY
        bne :+
        jmp cpu_pen
:       lda #$FF                ; the nearest, not the keeper, not the taker
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

; cpu_pen: the yellow team's penalty, shot hard and rising at one corner
; or the other, as the frame has it
cpu_pen:
        lda frame_n
        and #1
        tay
        lda pen_xl,y
        sta o_txl + BALL
        lda pen_xh,y
        sta o_txh + BALL
        ldy flip                ; (1000 on towards the goal)
        lda shot_dyl,y
        clc
        adc o_yl + BALL
        sta o_tyl + BALL
        lda shot_dyh,y
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
        jmp sfx_kick

pen_xl:     .byte <(304 - 520), <(304 + 520)
pen_xh:     .byte >(304 - 520), >(304 + 520)

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
        cpx ctrl_b
        beq @done
        cpx taker
        beq @done
        lda o_dive,x            ; diving: in the air his dive goes on, down
        beq :+                  ; he stays down
        cmp #DIVE_T - DIVE_AIR + 1
        bcs @done
        jmp stand
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
        jsr top_of
        beq :+
        lda #<LINE_T
        ldy #>LINE_T
        sta tmp
        sty tmp + 1
        lda #$80
        sta z_t8
        rts
:       lda #<LINE_B
        ldy #>LINE_B
        sta tmp
        sty tmp + 1
        lda #0
        sta z_t8
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
        lda o_dive,x            ; far across from him: a dive that way
        bne @in
        ldy #0
        lda z_px
        sec
        sbc o_xl,x
        sta tmp
        lda z_px + 1
        sbc o_xh,x
        bpl :+
        iny                     ; (left)
        eor #$FF
        sta tmp + 1
        lda tmp
        eor #$FF
        sta tmp
        lda tmp + 1
:       bne :+
        lda tmp
        cmp #DIVE_FROM
        bcc @in
:       tya
        sta o_dvd,x
        lda #DIVE_T
        sta o_dive,x
@in:    rts

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
        ora dead_t
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
        jsr sfx_catch
        stx taker
        stx last_pl
        lda #0                  ; (caught: up with it)
        sta o_dive,x
        lda #R_KEEPER
        sta rs_kind
        ldy #0                  ; his team, the way he faces: out from
        cpx #11                 ; his goal
        bcc :+
        iny
:       jsr top_of
        beq :+
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
        jsr top_of
        beq :+
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
        lda #0
        sta o_hd,x
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
        ldx ctrl_b
        bmi :+
        jsr @one
:       ldx chaser
        bpl @one
        rts
@one:   lda o_slide,x
        bne :+
        rts
:       dec o_slide,x
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
:       lda o_hd,x              ; from behind into the player on the
        ora o_hit,x             ; ball: a foul
        bne :+
        jsr foul_on
        bcc :+
        jmp foul
:       lda o_hit,x             ; the ball reached, low: knocked on (a
        bne @done               ; diving header: in the air, headed on)
        lda o_zl + BALL
        ldy o_hd,x
        beq :+
        cmp #DHEAD_Z_HI + 1
        bcc @reach
        rts
:       cmp #SLIDE_Z + 1
        bcs @done
@reach: jsr mate_dist
        lda tmp + 1
        bne @done
        lda tmp
        cmp #SLIDE_REACH + 1
        bcs @done
        lda #1
        sta o_hit,x
        lda #0
        cpx #11
        bcc :+
        lda #1
:       pha
        jsr held                ; the other team's on it: won by a roll,
        bcc :+                  ; his tackling against that one's control
        lda #10                 ; - missed, he slides on past it
        jsr wins
        bcc :+
        pla
        rts
:       pla
        sta last_team
        stx last_pl
        jsr touch
        ldy o_dir,x
        jsr ball_ahead
        lda o_hd,x
        beq :+
        jsr shot_speed          ; a diving header: as hard as a shot
        lda #<HEAD_DZ
        sta o_dzf + BALL
        lda #>HEAD_DZ
        sta o_dzl + BALL
        jmp sfx_kick
:       lda o_spl,x             ; as fast as he slides, and some
        clc
        adc #<256
        sta o_spl + BALL
        lda o_sph,x
        adc #>256
        sta o_sph + BALL
        lda #0
        sta o_dzl + BALL
        sta o_dzf + BALL
        jmp sfx_kick
@done:  rts

; nearer: carry clear if the ball is right at player X's feet (TAKE_D2),
; nearer him than the player who touched it last. Keeps X.
nearer:
        jsr mate_dist
        lda tmp + 1
        bne @no
        lda tmp
        cmp #TAKE_D2 + 1
        bcs @no
        sta cp_d
        lda tmp + 1
        sta cp_d + 1
        stx hd_x
        ldx last_pl
        jsr mate_dist
        ldx hd_x
        lda cp_d
        cmp tmp
        lda cp_d + 1
        sbc tmp + 1
        rts
@no:    sec
        rts

; ---- poses ------------------------------------------------------------------

; pose_of: A = the picture for player X other than running, $FF none: a
; sliding tackle lying feet first (down when it has stopped), a keeper
; diving (down after it), or holding the ball up. Keeps X.
pose_of:
        cpx thrower             ; a throw-in, held or thrown, facing the
        bne @slide              ; pitch
        lda throw_t
        beq @slide
        ldy #0
        lda o_xh,x
        beq :+
        ldy #IMG_THROW_LA - IMG_THROW_RA
:       lda kickoff
        bne :+
        iny                     ; (the ball gone: thrown)
:       tya
        clc
        adc #IMG_THROW_RA
        rts
@slide: lda o_slide,x
        beq @keeper
        lda o_spl,x
        ora o_sph,x
        beq @down
        lda o_hd,x              ; a diving header: the keeper's dive, the
        beq :+                  ; right half of the ways one way, the left
        lda o_dir,x             ; half the other
        cmp #4
        lda #IMG_DIVE_A
        bcc :++
        lda #IMG_DIVE_B
        rts
:       lda o_dir,x             ; feet first: the right half of the ways
        cmp #4                  ; one picture, the left half the other
        lda #IMG_SLIDE_B
        bcc :+
        lda #IMG_SLIDE_A
:       rts
@keeper:
        txa
        beq :+
        cpx #11
        bne @none
:       lda o_dive,x
        beq @hold
        cmp #DIVE_T - DIVE_AIR + 1
        bcc @down
        lda o_dvd,x
        beq :+
        lda #IMG_DIVE_B
        rts
:       lda #IMG_DIVE_A
        rts
@hold:  lda kickoff             ; holding the ball, his to kick out
        beq @none
        cpx taker
        bne @none
        lda rs_kind
        cmp #R_KEEPER
        bne @none
        lda #IMG_HOLD
        rts
@down:  lda #IMG_DOWN
        rts
@none:  lda #$FF
        rts

; ---- the match's time ---------------------------------------------------

; clock: a frame of the match's time (not while a set piece waits, nor
; after full time): at 45 minutes half time, the yellow team to kick
; off, at 90 full time; and hud, the score and minute shown, while the
; ball is dead for a kick-off
clock:
        lda #0
        ldy rs_kind
        bne :+
        ldy kickoff
        bne @hud
        ldy dead_t
        beq :+
@hud:   lda #1
:       sta hud
        lda kickoff
        ora full
        bne @done
        inc min_t
        lda min_t
        cmp min_frames
        bcc @done
        lda #0
        sta min_t
        inc game_min
        lda game_min
        cmp #45
        bne :+
        lda #1
        sta half
        sta flip                ; (the sides change)
        sta rs_team             ; (the yellow team kicks off again)
        bne @whistle
:       cmp #90
        bne @done
        lda #1
        sta full
        lda #0
        sta rs_team
@whistle:
        lda #DEAD_HALF
        jmp whistle
@done:  rts

; whistle: the ball dead A frames, for a kick-off in the middle (rs_team's)
whistle:
        sta dead_t
        jsr sfx_halftime
        lda #R_KICKOFF
        sta rs_kind
        lda #0
        sta goal
        lda #<304
        sta rs_x
        lda #>304
        sta rs_x + 1
        lda #<369
        sta rs_y
        lda #>369
        sta rs_y + 1
        jmp calm

; new_match: after full time, the ball kept dead till fire, which starts
; a new match: no goals, the first minute, the cyan team to kick off
new_match:
        lda min_t               ; (the result shown 2 seconds at least:
        cmp #100                ; min_t counts them, the clock stopped)
        bcs :+
        inc min_t
        bcc @on
:       lda joy
        and #J_FIRE
        bne :+
@on:    inc dead_t              ; (dead on)
        rts
:       lda #0
        sta full
        sta half
        sta game_min
        sta min_t
        sta score
        sta score + 1
        sta rs_team
        sta flip
        ldx #PLAYERS - 1        ; no fouls, no one off
:       sta fouls,x
        sta o_off,x
        dex
        bpl :-
        lda #1
        sta dead_t              ; (the kick-off next frame)
        rts

; ---- the yellow team's play ---------------------------------------------

; cpu_pass: the yellow chaser X has the ball: with a cyan player close
; (PRESSED, squared), or once he has had it a moment (CPU_HOLD), it goes
; on to the team-mate furthest towards the cyan goal, PASS_MIN or more
; away; he is the chaser now, to meet it. Carry clear if passed.
cpu_pass:
        lda y_pass_t
        beq :+
        sec
        rts
:       stx cp_from
        lda cpu_hold            ; (had it long enough: on)
        cmp #CPU_HOLD
        bcs @press
        ldx #10                 ; a cyan player close?
@near:  jsr mate_dist
        lda tmp
        cmp #<PRESSED
        lda tmp + 1
        sbc #>PRESSED
        bcc @press
        dex
        bpl @near
        ldx cp_from             ; (none: on with it)
        sec
        rts
@press: lda #0                  ; the team-mate furthest on
        sta cp_y
        sta cp_y + 1
        lda #$FF
        sta cp_to
        ldx #PLAYERS - 1
@look:  cpx cp_from
        beq @next
        jsr mate_dist
        lda tmp + 1             ; (within 256 either way: not $FFFF)
        and tmp
        cmp #$FF
        beq @next
        lda tmp
        cmp #<PASS_MIN
        lda tmp + 1
        sbc #>PASS_MIN
        bcc @next               ; (too near)
        lda o_yl,x              ; how far on: y, or 738 - y the sides
        sta cp_k                ; changed
        lda o_yh,x
        sta cp_k + 1
        lda flip
        beq :+
        lda #<738
        sec
        sbc o_yl,x
        sta cp_k
        lda #>738
        sbc o_yh,x
        sta cp_k + 1
:       lda cp_k
        cmp cp_y
        lda cp_k + 1
        sbc cp_y + 1
        bcc @next
        lda cp_k
        sta cp_y
        lda cp_k + 1
        sta cp_y + 1
        lda tmp
        sta cp_d
        lda tmp + 1
        sta cp_d + 1
        stx cp_to
@next:  dex
        cpx #11
        bne @look
        ldx cp_to
        bmi @none
        lda cp_d
        sta mate_d
        lda cp_d + 1
        sta mate_d + 1
        jsr kick_to
        lda #1
        sta last_team
        jsr touch
        lda cp_from
        sta last_pl
        lda cp_to
        sta chaser
        lda #$FF
        sta chaser2
        lda #PASS_WAIT
        sta y_pass_t
        clc
        rts
@none:  ldx cp_from
        sec
        rts

; support: the yellow team's next nearest, every eighth frame: the cyan
; team on the ball, between it and his goal; the yellow team on it,
; ahead of it, towards the middle - there to be passed to
support:
        lda kickoff
        ora dead_t
        bne @out
        lda frame_n
        and #6
        bne @out
        ldx chaser2
        bmi @out
        cpx chaser
        beq @out
        lda o_slide,x
        beq :+
@out:   rts
:       ldy #0                  ; (goal side: 24 up)
        lda last_team
        bne :+
        lda #<(-24)
        jsr updown
        sta tmp + 1
        lda #0
        beq @set
:       lda #72                 ; (ahead: 72 down, 48 towards the middle)
        jsr updown
        sta tmp + 1
        lda #48
        ldy o_xh + BALL
        cpy #>304
        bcc :+
        bne @left
        ldy o_xl + BALL
        cpy #<304
        bcc :+
@left:  lda #<(-48)
:
@set:   jsr sext                ; x: the ball's + A
        clc
        adc o_xl + BALL
        sta o_txl,x
        lda tmp
        adc o_xh + BALL
        sta o_txh,x
        lda tmp + 1             ; y: the ball's + that
        jsr sext
        clc
        adc o_yl + BALL
        sta o_tyl,x
        lda tmp
        adc o_yh + BALL
        sta o_tyh,x
        jsr inside
        lda #<SPEED_JOG
        sta o_spl,x
        lda #>SPEED_JOG
        sta o_sph,x
        lda #1
        sta o_mov,x
        sta o_new,x
        rts

; in_range: carry set if the yellow chaser X is close enough to the goal
; his team attacks to shoot (SHOOT_FROM). Keeps X.
in_range:
        lda flip
        bne :+
        lda o_yl,x              ; (down: from 689 - SHOOT_FROM on)
        cmp #<(LINE_B - SHOOT_FROM)
        lda o_yh,x
        sbc #>(LINE_B - SHOOT_FROM)
        rts
:       lda o_yl,x              ; (up: below 49 + SHOOT_FROM)
        cmp #<(LINE_T + SHOOT_FROM)
        lda o_yh,x
        sbc #>(LINE_T + SHOOT_FROM)
        bcc :+
        clc
        rts
:       sec
        rts

; updown: A (signed) for the yellow team going down; negated the sides
; changed. Keeps X, Y.
updown:
        pha
        lda flip
        beq :+
        pla
        eor #$FF
        clc
        adc #1
        rts
:       pla
        rts

shot_dyl:   .byte <1000, <(-1000)
shot_dyh:   .byte >1000, >(-1000)
