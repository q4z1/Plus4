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
; the way it points every second frame, at 1024 (Sensible Soccer has a
; table that goes faster after four touches the same way, but in play
; every touch measured is 1024); going up, a pixel further out beside him
; each touch.
; Fire passes: to the nearest team-mate within 22.5 degrees of the
; way the stick (or the player) points, harder the further he is; with
; none there, straight on.

        .macpack longbranch
        .include "game.inc"
        .include "resident.inc" ; (K_GO: build.sh)
        .include "data.inc"

        .export play_init, play_frame, play_picture, pic_n, pose_of, score, game_min, hud, min_frames
        .export lift, o_off, card_pl, card_c, anew, whistle, why, jumps, HEAD_T
        .export fine_on, sp_way_of, sin4, cam_way, full
        .export sq8_lo, sq8_hi, qs_lo, qs_hi, qn_lo, qn_hi
        .import quit_a
        .export dbg_on, dbg_i, dbg_t, dbg_bits, dbg_plan, goal
        .export o_xl, o_xh, o_yl, o_yh, o_zl, o_dir, o_step, o_spl, ctrl, ctrl_b
        .export two, train, enter, TUN_IN, sk, sk_duel, jog_lo, jog_hi
        .export tac_x0l, tac_x0h, tac_xs, tac_y0l, tac_y0h, tac_ys
        .export kp_gl, kp_gh, kp_sl, kp_sh, kp_dn, kp_dv
        .import joy, joy_a, joy_b, atan_tab, sin_tab
        .importzp z_y0, z_d
mate_t      = z_y0              ; (two each of fig_draw's, dead while the
tmp         = z_d               ; match goes: scratch on the zero page)
off_pl      = $ED               ; the receiver offside, $FF none, $FE a set
off_by      = $EE               ; piece's taker in off_by (above the match's
                                ; zero page: the save keeps it), the passer
        .import sfx_kick, sfx_catch, sfx_whistle, sfx_halftime, sfx_goal
        .import sfx_save, sfx_miss, sfx_yellow, sfx_red, sfx_roar
        .import v_left, crowd1, fx_murmur

PLAYERS     = 22                ; 0-10 the joystick's team, from its keeper
BALL        = PLAYERS           ; the last object
NOBJ        = PLAYERS + 1

SPEED_RUN   = 1024              ; the joystick's player running (c1372c),
SPEED_BALL  = 896               ; and with the ball close (c13828): anyone's
SPEED_JOG   = 1024              ; going to his place
LINE_L      = 49                ; the touch lines and goal lines
LINE_R      = 558
LINE_T      = 49
LINE_B      = 689
POST_L      = 269               ; between the posts (the ball's middle on
POST_R      = 340               ; them, as they are drawn at 269-270 and
                                ; 339-340: the left one was 263, a ball
                                ; past it a goal - Luca)
NEAR_W      = 24                ; just wide: so far past a post at most,
MISS_SP     = $0300             ;   so fast at least (near_miss)
SAVE_SP     = $0400             ; a save: the ball so fast at least (a
                                ;   shot, 1792 on, 16 slower each frame)
BAR_Z       = 17                ; under the bar
NET_T       = 12                ; the net this far behind the line: at the
NET_B       = 5                 ; top, at the bottom (as the goals are drawn:
                                ; the bottom one's net is shallower)
NET_L       = 275               ; and between the side nettings (the posts
NET_R       = 335               ; are drawn at 270 and 340, the ball 5 wide)
DEAD_OUT    = 50                ; frames the ball is dead after going out,
DEAD_GOAL   = 125               ; after a goal
DEAD_FOUL   = 125               ; after a whistle (free_at): its card, its
                                ; reason seen, everyone to his place - in a
                                ; second it was gone, said Luca
CPU_WAIT    = 40                ; the yellow team's set pieces: after 40 frames
R_KICKOFF   = 0                 ; restarts
R_THROW     = 1
R_GOALKICK  = 2
R_CORNER    = 3
R_KEEPER    = 4                 ; (the keeper has it)
R_FREE      = 5                 ; a foul: a free kick,
R_PENALTY   = 6                 ;   in the box a penalty
BOX_L       = 161               ; the penalty areas as Sensible Soccer's
BOX_R       = 446               ; rules have them (c11b9a): across, and
BOX_T       = 137               ; from the line to (top) / from (bottom)
BOX_B       = 601
SPOT_T      = 107               ; the penalty spots (c11b9a)
SPOT_B      = 631
WALL_D      = 54                ; a set piece: the other team this far off
                                ; (in y: in line with Sensible Soccer's
                                ; wall, 51-56 - at 40 one put out stood
                                ; alone in front of it, the computer's
                                ; man at the ball in Luca's picture:
                                ; tests/freekick.py, fkcpu.py)
THROW_T     = 10                ; a throw-in: frames the ball flies from the
THROW_HOLD  = 18                ; taker's head, drawn so high while he holds it
                                ; (in his hands: data/sprites.txt 60, 62)
HOLD_LIFT   = 14 + HOLD_UP      ; a keeper's hands up, the ball held in them
HOLD_TOP    = 6                 ; (the top goal's keeper: before his chest -
HOLD_UP     = 3                 ; his arms up drawn this much higher: draw)
ARMS_T      = 25                ; frames holding it up, then at his chest
SPEED_DIVE  = 2048              ; his dive (c0dffc),
SPEED_DIVE_W = 1280             ; the wrong way at a penalty (c0dffe),
DIVE_SLOW   = 72                ; less each frame after the first two
                                ; (about as its: some 60 pixels in all)
SHOT_L      = 263               ; a shot at his goal: crossing his line
SHOT_R      = 344               ; this far across
SPEED_NEAR  = 1024              ; the keeper going for a ball he is nearest
NEAR_Z      = 17                ; (under this high, in his box)
GET_D2      = 5120              ; this near (squared; its 5000), this low
GET_Z       = 13
PEN_DX      = 520               ; a penalty at a corner: so far across on 1000
PEN_REACH   = 12                ; he dives once a penalty is this near his
PEN_REACH2  = 20                ; line, now and then this near
RECV_T      = 100               ; frames a pass's receiver runs to meet it
HOLD_T      = 8                 ; a ball touched this few frames ago is held,
HOLD_D2     = 144               ; and one this near (squared) the player who
HOLD_Z      = 12                ; touched it, this low: the other team
                                ; takes it only by a tackle
SLIDE_T     = 50                ; a sliding tackle's frames,
SPEED_SLIDE = 1792              ; its speed at first,
SLIDE_DECEL = 48                ; less each frame,
SLIDE_REACH = 64                ; the ball this near (squared) it reaches
                                ; (Sensible Soccer's, c13f7a; a diving
                                ; header too),
SLIDE_Z     = 8                 ; this low
FALL_T      = 50                ; frames one knocked over by it lies (c10f0c)
FALL_DECEL  = 96                ; and slides on slower each frame (c14150)
FOUL_D2     = 800               ; a foul only this near the ball (squared)
LOCK_T      = 24                ; frames the other team cannot dribble it
                                ; (the C64's 12 of its 25 a second)
DBL_T       = 8                 ; - and no one after a set piece's kick
GLUE_T      = 16                ; and a dribbler past his glue (dribble)
GLUE_GAP    = 16                ; no dribble touch this long: his turns anew
BR_WAIT     = 15                ; the computer: frames between its kicks (c15486)
BR_KICKED   = 13                ; and from its team's last (c1547a: $56 < 13)
CPU_SLIDE_D2 = 200              ; the yellow runner slides in this near it
CPU_OPP_D2  = 3200              ; the cyan player this near it (c154a8)
DHEAD_Z_LO  = 8                 ; a diving header (Sensible Soccer's only
DHEAD_Z_HI  = 15                ; header, c13af4, c140d4): fire pressed, the
DHEAD_D2    = 2450              ; stick pushed, the ball higher than 8 this
                                ; near (squared); he dives the stick's way,
SPEED_DHEAD = 2048              ; so fast, slowing so much a frame, and in
DHEAD_DECEL = 36                ; the first frames of it heads the ball 8 -
DHEAD_T     = 16                ; 15 high on: a quarter faster than he goes,
DHEAD_DZ    = $00A0             ; rising 0.625
HEAD_LO     = 13                ; a header (head): the ball this high and up
HEAD_HI     = 26                ; to this, its distance squared at most
HEAD_D2     = 100               ; HEAD_D2 from him; headed on at HEAD_SPEED,
HEAD_SPEED  = 1536              ; rising as a diving header's; he jumps
HEAD_T      = 16                ; HEAD_T frames, his arms up (o_zl, a
                                ; player's: pose_of)
DEAD_HALF   = 150               ; frames dead at half time and full time
MID_T       = LINE_T + (LINE_B - LINE_T) / 4    ; the pitch's middle half:
MID_B       = LINE_B - (LINE_B - LINE_T) / 4    ;   the whistle there (clock)
DIVE_T      = 40                ; a keeper's dive: frames in the air and down,
DIVE_AIR    = 16                ; the first so many in the air
KEEPER_SEES = 76                ; he goes for a shot once it is this near
                                ; his place, in the box (Sensible Soccer's)
DIVE_DY     = 16                ; he dives for a shot this near him (c0e4d8),
DIVE_Z      = 16                ; this low (c13038),
CATCH_X     = 3                 ; the keeper catches the ball this near
                                ; (Sensible Soccer's: else he dives),
CATCH_Y     = 6
DIVE_X      = 6                 ; diving, he gets to it this far across
CATCH_Z     = 13                ; and under this high (a lob goes over him)
OWN_T       = 12                ; frames: his own parry or kick his again
SLACK       = 2                 ; a place this near the last one is the same
NEAR        = 32                ; distance squared: the ball at his feet
DRIB_NEAR   = 50                ; - for a dribble's touch: the C64 asks
                                ; for 32 at its 25 Hz step, measured in
                                ; its pictures it touches it at 51, not
                                ; at 66
CLOSE       = 72                ; near enough to kick it
OFFER_T     = 40                ; frames a set piece's taker looks a way
                                ; before the team-mate that way comes
PASS_Q      = 12                ; frames a pass let go of too soon waits for
                                ; the ball to come
KICKED_T    = 50                ; frames the one who passed or shot is not
                                ; the one to get to the ball (switch, help)
KICK_Z      = 4                 ; and low enough
TRAP_Z      = 4                 ; low enough to stop dead (Sensible Soccer)
SHOT_HOLD   = 9                 ; frames fire is held for a shot
CHARGE_N    = 12                ; fire held on after a shot: steps (two frames
                                ; each) it goes harder (charge)
CHARGE_D    = 64                ; a step's speed (a throw-in's half): 1792 to
                                ; 2560, as fire held before the shot went
CHARGE_DZ   = $20               ; pulled back, a step's rise, to LIFT_HI_DZ
SHOT_CPU    = 13                ; the computer's sh_pow: 2208, as ever
SHOT_SPEED  = 2208
SHOT_DZ     = $0170             ; its rise, 8.8: 1.44 - over the heads
                                ; (13) from some 14 frames to 27, its top
                                ; 14.7 under the bar (17); 1.25 had it at
                                ; 11 at most: everyone in its way took it
SET_DZ      = $0140             ; a set piece's kick's rise: 1.25
.assert >SET_DZ = >SHOT_DZ, error, "shot: SET_DZ, SHOT_DZ one high byte"
FAST_SP     = $0600             ; a ball this fast (a shot) the joystick's
FAST_Z      = 6                 ;   player takes only this low
LIFT_DZ     = $0160             ; the aftertouch's lift: 1.375,
LIFT_HI_DZ  = $0200             ;   pulled back 2

        .segment "MATCHZP": zeropage
; the title's synth's zero page ($A8 on: music.s) and the 8 bytes below
; it, free once the match is on - main clears it after the title: the
; match's busiest variables
rs_kind:    .res 1              ; the restart (R_*), for which team (rs_x,
rs_team:    .res 1              ; rs_y: where)
r_t:        .res 1              ; the rules': attackers, the team's last
r_s:        .res 1              ; (the side: 0 top, 1 bottom)
thrower:    .res 1              ; who takes the throw-in
cpu_t:      .res 1              ; the yellow team's: till they take it
br_ev:      .res 1              ; brain's: 1 a pass, 2 a shot for control,
br_t:       .res 1              ; frames till it may kick again,
br_r:       .res 1              ; the frame's die,
br_6c:      .res 1              ; looks left to find a team-mate to pass to,
br_6e:      .res 1              ; its last kick's kind (0 shot, 1 flat, 2
                                ; high; br_70, br_d: in the BSS)
br_g:       .res 1              ; the way from the ball to the goal (256),
br_w:       .res 1              ; a way (0-7)
br_n:       .res 1              ; (br_cone's: the nearest, his team)
bs_t:       .res 1              ; its set piece: frames since it was ready,
bs_rot:     .res 1              ; and the way he turns looking (1, $FF)
hd_y:       .res 1              ; (dist_y, pair_d2: with hd_x)
mf_a:       .res 1              ; (may_face's: the way, the middle way)
k_dy:       .res 1              ; (k_shot's: the ball's way to his line,
k_f:        .res 1              ; the frames it takes)
k_i:        .res 1              ; (k_get's: the player looked at; k_d2)
kick_way:   .res 1              ; pass's: the way, 0-255
frame_n:    .res 1              ; frames played
pp_help:    .res 1              ; play_picture's: bit 7 clear, help
pic_n:      .res 1              ; frames since the last picture (play_picture)
form_i:     .res 1              ; team_ai's next of the eleven to place,
form_n:     .res 1              ; and how many more
b_th:       .res 1              ; the ball's angle, speed, product's low
b_spl:      .res 1              ; bytes as aim last worked them out,
b_sph:      .res 1
b_px0:      .res 1
b_py0:      .res 1
b_d:        .res 8              ; and sin * 16 (x, y), sin * 10 (x, y)
kickoff:    .res 1              ; 1 till the kick-off or set piece is taken
taker:      .res 1              ; who takes it, $FF none
dead_t:     .res 1              ; frames the ball is still dead, 0 in play
last_team:  .res 1              ; who touched the ball last: the team,
last_pl:    .res 1              ; the player
touch_t:    .res 1              ; frames since the ball was touched
min_t:      .res 1              ; frames into the minute
flip:       .res 1              ; 1: the sides changed - the cyan team at the
                                ; top, attacking down
d6:         .res 2              ; the ball's distance squared to the goal / 16
sq_h:       .res 1              ; (quarter's)
throw_t:    .res 1              ; frames left of its throw (THROW_T held)
pen_kick:   .res 1              ; not 0: the ball last kicked from the
                                ; penalty spot (touch)
k_on:       .res 1              ; (k_shot's: 1 a shot at his goal)
pfire:      .res 1              ; (control's: pf as it was)
mf_c:       .res 1
d2:         .res 2              ; dist2's result
mate:       .res 1              ; pass's
mate_d:     .res 2
tr_t:       .res 2              ; (triple's)
; each team's (by me), out of the controls swap trades: used by one
; routine each
at_side:    .res 2              ; the side its shot bends to, $FF none yet
pass_q:     .res 2              ; frames a pass let go of too soon waits
pf:         .res 2              ; his joystick the frame before
at_j:       .res 1              ; (aftertouch's: the joystick's way,
at_d:       .res 1              ; and its team's at_dir)
at_dir:     .res 2              ; the shot's way
kick_t:     .res 2              ; frames since its last pass or shot (kick_pl)
recv_t:     .res 2              ; frames recv still goes to meet a pass

        .zeropage
z_ax:       .res 2              ; aim's: the way to the destination
z_ay:       .res 2
sp_s        = z_ax              ; (fine_aim's: the stick's way 0-255, how
sp_d        = z_ax + 1          ; far the aim is off it; way_y's count)
sp_n        = z_ay
sp_r        = z_ay + 1          ; (fine_aim's: the middle of the aims' ways)
lm_g        = z_ax              ; (last_man's: the goal's y, the fouled
lm_v        = z_ay              ; player's distance squared / 16 to it,
lm_f        = mf_a              ; the fouler)
p_w         = mf_a              ; (pass's cone: half its width)
sp_w        = mf_c              ; (sin4's way)
z_sx:       .res 1              ;   its signs
z_sy:       .res 1
z_sw:       .res 1              ; angle's: bit 7, dx and dy swapped
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
z_f2:       .res 2              ; mul_f's
z_f10:      .res 2
z_f16:      .res 2
smul_l:     .res 1              ; smul's multiplier
smul_h:     .res 1
z_q:        .res 2              ; mul_by's product
z_qp:       .res 2              ; mul_by's pointers into its tables: qs_lo + a,
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
helper:     .res 1              ; the player running to a ball his team has
                                ; not got (help), $FF none
at_n:       .res 1              ; the aftertouch's frame, $FF none
kick_pl:    .res 1              ; the player who last passed or shot,
CTX_VAR     = * - ctx           ; (swap: these traded, the rest flipped)
me:         .res 1              ; the team: 0 cyan, 1 yellow
t_lo:       .res 1              ; its keeper: 0, 11
t_hi:       .res 1              ; its last player: 10, 21
t_end:      .res 1              ; one before its keeper: $FF, 10
CTX_N       = * - ctx
.assert CTX_N - CTX_VAR = 4 && t_end - ctx = CTX_N - 1, error, "swap: me .. t_end not the last four"
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
o_hit:  .res NOBJ               ; 1: the tackle has reached the ball ($80:
                                ; missed it, lost to a better one: slides)
o_dive: .res NOBJ               ; a keeper's frames left of a dive, 0 none
o_dvd:  .res NOBJ               ; its way: 0 right, 1 left
        .segment "LOWBSS"       ; (down low: simple-soccer.cfg)
sp_aim:     .res 1              ; a joystick's throw-in or corner: its aim
                                ; (sp_ways' index, $FF none yet)
sp_j:       .res 1              ; fine_aim's: the stick's way the frame
sp_rep:     .res 1              ; before, frames till it turns the aim again
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
glue_n:     .res 2              ; each team's dribbler's turns with it,
glue_d:     .res 2              ; his last way,
glue_f:     .res 2              ; the frame of his last touch (dribble)
o_3yl:      .res NOBJ           ; (o_3*: below)
        .bss
o_3xf:      .res NOBJ           ; each object's step three times over
o_3xl:      .res NOBJ           ; (triple): play_others's for a picture of
o_3yf:      .res NOBJ           ; three frames (o_3yl in the LOWBSS)

goal:       .res 1              ; 1: dead for a goal - the net holds the ball
rs_x:       .res 2              ; where
rs_y:       .res 2
pass_w:     .res 2              ; the way pass_q's pass goes
near_z:     .res 1
near_d:     .res 1              ; at_ball_d's: so near (squared, + 1)
offer:      .res 1              ; offering's: the team-mate coming, $FF none,
offer_w:    .res 1              ; the way the taker looks, the frames he
offer_t:    .res 1              ; has looked it, the place (sp_add's order:
offer_x:    .res 2              ; x, y)
offer_y:    .res 2
min_frames: .res 1              ; frames to a minute (the title's choice:
                                ; 100, 167, 233 - 90 in 3, 5, 7 minutes)
game_min:   .res 1              ; the match's minute, 0-90
half:       .res 1              ; 1: the second half
full:       .res 1              ; full time: the players still on, 1 more
                                ; (ft_spot) - till fire starts a new match
hud:        .res 1              ; 1: the score and the minute shown
hd_x:       .res 1              ; (dist_y, pair_d2)
br_70:      .res 1              ; brain's (br_*: MATCHZP): the side its kick
                                ; bends to (1, $FF, 0 none), his distance
br_d:       .res 2              ; squared to the ball
score:      .res 2              ; goals, cyan and yellow
lift:       .res 1              ; how high the ball is drawn over where it is
fouls:      .res PLAYERS        ; each player's yellow cards in the match
ref_k:      .res 1              ; the referee's: a yellow in 32 fouls
o_off:      .res NOBJ           ; 1: sent off - gone from the match (2:
                                ; walking off, drawn still - walk_off)
card_pl:    .res 1              ; the player shown a card while the ball is
card_c:     .res 1              ; dead, $FF none; 0 yellow, 1 red
sh_pow:     .res 1              ; how hard the shot: 0 - 24 (shot_power)
jumps:      .res 1              ; frames a header's jump may still go on
sl_any:     .res 1              ; not 0: someone may be sliding or down
                                ; (o_slide) - slides looks through them all
lock_t:     .res 2              ; each team's frames its joystick's player may
                                ; not dribble, tackled (Sensible Soccer's $74)
old_z:      .res 2              ; ball_move's: where it was (old_x, old_y:
old_x       = $EF               ; above the match's zero page, not saved -
old_y       = $F2               ; ball_move's alone)
; more of a routine's own over pause.s's (Z_*, $F6 on: only while the
; match is paused - between frames, never inside one of these)
each_v      = $F5               ; (each's routine)
k_d2        = $F7               ; (k_get's, k_high's: a way squared)
cp_d        = $F9               ; (can_slide's: his way squared)

        .segment "DATA"         ; (not saved: resume's 0)
enter:      .byte 0             ; 1: the teams to come on (walk_on) - the
                                ; title's, not a test's
        .bss
; why: the reason for the whistle shown till the set piece is taken -
; WHY_FOUL, WHY_OFF (offside), WHY_TWICE (a double touch); 0 none
why:        .res 1
WHY_FOUL    = 1
WHY_OFF     = 2
WHY_TWICE   = 3
; a test's plan for the joystick, by the match's frames: (frame low, high,
; J_ bits) each, $FFFF the end; dbg_on set to 2 starts it - the frames
; counted from then, and the match's own counters from 0 too, so that it
; goes the same way in any emulator
dbg_on:     .res 1
dbg_i:      .res 1              ; the next entry's place
dbg_t:      .res 2              ; frames since
dbg_bits:   .res 1              ; the stick as the plan has it

        .segment "DATA"         ; (the title's: a saved match's own)
two:        .res 1              ; 1: two players, the yellow team the second
                                ; joystick's (the title's choice)
train:      .res 1              ; 1: training - a keeper and four a side, no
                                ; time (the title's choice)

        .segment "HIBSS3"       ; (not saved: nor enter - resume)
wk_yl:      .res PLAYERS        ; (walk_on's: each one's place, y)
wk_yh:      .res PLAYERS

        .segment "HIBSS2"       ; (not cleared: the title fills it)
; each player's pace by his number (title.s runs: Sensible Soccer's)
sk:
sk_pace:    .res PLAYERS        ; how fast he runs to the ball: 896 + twice
                                ; this (title.s runs: Sensible Soccer's)
jog_lo:     .res 2              ; each team's others' speed to their places
jog_hi:     .res 2              ; (title.s runs: Sensible Soccer's)
kp_gl:      .res 2              ; each team's keeper: going for the ball,
kp_gh:      .res 2
kp_sl:      .res 2              ; edging across to a shot,
kp_sh:      .res 2
kp_dn:      .res 2              ; and his guesses at a shot's pace: the
kp_dv:      .res 2              ; first kp_dn of 16 his own, the rest kp_dv
                                ; (title.s keeps: Sensible Soccer's)
sk_duel:    .res PLAYERS        ; how good he is at the ball: 15 less his
                                ; team's level (1 the best, 8), a star one
                                ; more - 7 to 15 (title.s runs)
tac_ys:     .res 44             ; (tac_*: below)

; the formations the teams play (data/tactics.txt; title.s chosen copies
; them from its lib_*): each team's 22 players - 0-10 at the bottom of the
; pitch, 11-21 at the top - the cyan team's first, then the yellow
; team's: each one's area's corner and how far across it he goes for each
; pixel the ball goes (x / 510, y / 641, times 256)
        .segment "FORMS"        ; (RAM with the ROM out, not cleared)
tac_x0l:    .res 44
tac_x0h:    .res 44
tac_xs:     .res 44
tac_y0l:    .res 44
tac_y0h:    .res 44



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

; may_face: the ways a taker may be off the middle one, + 1, by the
; restart (R_*) - a goal kick and the keeper's within 45 degrees of
; straight out (as the computer's in Sensible Soccer, its and $bb: no
; kick across his own goal, whose aftertouch would bend it back into
; it); a corner's middle way by the corner: top left, top right, bottom
; left, bottom right
face_r:     .byte 3, 3, 2, 2, 2, 5, 2
corner_c:   .byte 3, 5, 1, 7
; the joystick as a way to go (8: none)
joy_dir:    .byte 8, 0, 4, 8, 6, 7, 5, 6, 2, 1, 3, 2, 8, 0, 4, 8
; a destination 1000 pixels off, each way
vec_xl:     .byte <0, <1000, <1000, <1000, <0, <(-1000), <(-1000), <(-1000)
vec_xh:     .byte >0, >1000, >1000, >1000, >0, >(-1000), >(-1000), >(-1000)
vec_yl:     .byte <(-1000), <(-1000), <0, <1000, <1000, <1000, <0, <(-1000)
vec_yh:     .byte >(-1000), >(-1000), >0, >1000, >1000, >1000, >0, >(-1000)
; the players' speeds (speed: SP_*): on the joystick, with the ball close,
; running to it
SP_RUN      = 0
SP_BALL     = 1
SP_CHASE    = 2
; squares, for distances (sq_*: those under 64, the same)
sq_lo       = sq8_lo
sq_hi       = sq8_hi
        .pushseg
        .segment "PAGES"        ; (on pages of their own: no index crosses)
sq8_lo:
        .repeat 256, I
        .byte <(I * I)
        .endrepeat
sq8_hi:
        .repeat 256, I
        .byte >(I * I)
        .endrepeat
        .popseg

        .code

; play_init: both teams lined up, the ball on the centre spot, the
; joystick on a forward
play_init:
        jsr squad
        lda #>qs_lo             ; mul_by's tables
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
        lda #20                 ; the yellow team's joystick's player
        sta ctrl_b
        lda #9                  ; the cyan team kicks off (line_up: rs_team
        sta ctrl                ; 0, as the program starts)
        sta taker
        lda #$FF                ; no card, no one offside (off_pl: above the
        sta card_pl             ; match's zero page, as the title left it -
        sta off_pl              ; its 0 the keeper offside: a penalty; nor
        sta thrower             ; a throw-in - head: 0 the keeper's kicks)
        lda #0
        sta why
        jsr await               ; (as every kick-off: no one offering - its
        lda enter               ; 0, the keeper: the first kick-off's tap
        bne walk_on             ; went back to him, Luca)
        jmp sfx_whistle

; walk_on: from the title (enter), the teams come on out of the tunnel at
; WALK_X, a step apart, one after the other, to their places for the
; kick-off - along the tunnel's row, down its steps, till WALK_OUT, then
; each to his place (walking; Luca: not out of nowhere) - the ball dead
; till they stand there, then the whistle (Luca)
walk_on:
        ldx #PLAYERS - 1
@pl:    jsr stand               ; (his place there his destination)
        lda o_yl,x              ; (his place's y kept for walking, the
        sta wk_yl,x             ; tunnel's row his destination's)
        lda o_yh,x
        sta wk_yh,x
        txa                     ; (WALK_X + 8 X: carry clear)
        asl a
        asl a
        asl a
        adc #<WALK_FROM         ; (no carry: under 256)
        sta o_xl,x
        lda #>WALK_FROM
        sta o_xh,x
        lda #<TUN_Y
        sta o_yl,x
        sta o_tyl,x
        lda #<SPEED_JOG
        sta o_spl,x
        lda #>SPEED_JOG
        sta o_sph,x
        lda #>TUN_Y             ; (1)
        sta o_yh,x
        sta o_tyh,x
        sta o_mov,x
        sta o_new,x
        dex
        bpl @pl
.assert <WALK_FROM + 8 * (PLAYERS - 1) < 256 && >TUN_Y = 1, error, "walk_on"
.assert <WALK_OUT = 0 && WALK_OUT > 608 - 115 && WALK_OUT < TUN_M, error, "walk_on: WALK_OUT"
        sta kickoff             ; (A 1: team_ai leaves them on their way)
        asl a
        sta dead_t
        rts

; each team's control as a match starts: pj, ctrl ... t_end (ctx)
ctx_new:    .byte 0, $FF, 0, $FF, $FF, $FF, 0, 0, 0, 10, $FF
ctx_new_b:  .byte 0, $FF, 0, $FF, $FF, $FF, $FF, 1, 11, 21, 10
.assert * - ctx_new_b = CTX_N, error, "ctx_new_b: not CTX_N"

; each: the routine at A (low) / Y (high) for the cyan team's control,
; and with two players for the yellow team's too (swapped in)
each:
        sta each_v
        sty each_v + 1
        jsr @call
        jsr swap
        jsr @call
        jmp swap
@call:  jmp (each_v)

; swap: the two teams' controls traded (ctx, ctx_b) - unrolled, as each
; calls it for every routine twice. The team's own four (me .. t_end) are
; one of two values each: flipped in place (their ctx_b bytes unused).
swap:
        .repeat CTX_VAR, I
        lda ctx + I
        ldy ctx_b + I
        sta ctx_b + I
        sty ctx + I
        .endrepeat
        lda me
        eor #0 ^ 1
        sta me
        lda t_lo
        eor #0 ^ 11
        sta t_lo
        lda t_hi
        eor #10 ^ 21
        sta t_hi
        lda t_end
        eor #$FF ^ 10
        sta t_end
        rts

; calm: the ball dead - no one after it, no aftertouch, no pass on its
; way, the joystick's players standing
calm:
        lda #$FF
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
        eor flip                ; takes it, else the other (the sides
        ldx #0                  ; changed: the yellow team's, as the two
        jsr @team               ; change places after)
        lda rs_team             ; the yellow team likewise
        eor flip
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

; slow: object X's speed A less, down to 0 at most. Keeps X, Y.
slow:   sta tmp
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
:       rts

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
; still: object X's steps 0 (A = 0). Keeps A, X, Y.
still:
        sta o_vxf,x
        sta o_vxl,x
        sta o_vyf,x
        sta o_vyl,x
        sta o_3xf,x
        sta o_3xl,x
        sta o_3yf,x
        sta o_3yl,x
        rts

; ---- a frame --------------------------------------------------------------

; get_up: everyone lying or sliding up again, standing (restart's, in the
; dead time)
get_up:
        ldx #PLAYERS - 1
@pl:    lda o_slide,x
        beq @next
        lda #0
        sta o_slide,x
        sta o_hd,x
        jsr stand
@next:  dex
        bpl @pl
        ldx card_pl             ; (a red card: off he walks - Luca: see
        bmi :+                  ; him go)
        lda card_c
        beq :+
        jmp walk_off
:       rts

play_frame:
        jsr clock
        jsr throwing
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
:       jsr walking             ; (one walking off for a red card: the
        bcc @dt                 ; ball dead till he is off the pitch)
        lda dead_t
        cmp #2
        bcc :+
@dt:    dec dead_t
        bne :+
        jmp restart
:       lda dead_t              ; (FALL_T frames into a whistle's dead time,
        cmp #DEAD_FOUL - FALL_T ; or 10 into one after the ball went out:
        beq :+                  ; everyone lying up again, to his place -
        cmp #DEAD_OUT - 10      ; Luca: they lay till the restart)
        bne :++
:       jsr get_up
:       jsr keepers_move
        jsr ball_move
        jmp net
@live:  lda touch_t             ; (frames since the ball's last touch,
        cmp #255                ; and the cyan team's last kick)
        beq :+
        inc touch_t
:       ldx #1                  ; (lock_t: down to 0)
:       lda lock_t,x
        beq :+
        dec lock_t,x
:       dex
        bpl :--
        lda joy                 ; each team's joystick: one player either,
        ldy two                 ; two the first and the second
        beq :+
        lda joy_b
        sta pj_b
        lda joy_a
:       sta pj
        jsr off_chk
        jsr duel
        jsr control             ; (as each: the cyan team's, the yellow
        jsr swap                ; team's swapped in)
        jsr control
        jsr swap
        lda two                 ; the computer's runner slides in as
        bne :+                  ; Sensible Soccer's, every frame (c154a8)
        lda last_team           ; - for the cyan team's ball only: one
        bne :+                  ; of its own passes coming to him he slid
        ldx helper_b            ; for, down for nothing (Luca)
        bmi :+
        lda o_slide,x
        bne :+
        jsr cpu_slide
        bcs :+
        jsr slide
:       jsr slides
        ldx ctrl                ; the two at the ball and the keepers,
        jsr @one                ; every frame
        ldx ctrl_b
        bmi :+
        jsr @one
:       jsr keepers_move
        lda at_n                ; (no aftertouch on either side: nothing
        and at_n_b              ; for it to do)
        bmi :+
        lda #<aftertouch
        ldy #>aftertouch
        jsr each
:       jsr ball_move
        jsr take                ; (each team's helper at it: his; a ball
        jsr head                ; at his head headed on)
        ldx helper_b            ; (the yellow team's swapped in only when
        bmi :+                  ; its runner is near the ball across, or
        jsr near_x              ; the ball as high as a head)
        bcc @yel
:       lda o_zl + BALL
        cmp #HEAD_LO
        bcc @noyel
        cmp #HEAD_HI + 1
        bcs @noyel
@yel:   jsr swap
        jsr take
        jsr head
        jsr swap
@noyel:
        lda jumps               ; (the headers' jumps: down - only while
        beq @jumped             ; one may go on)
        dec jumps
        ldx #PLAYERS - 1
:       lda o_zl,x
        beq :+
        dec o_zl,x
:       dex
        bpl :--
@jumped:
        jsr catch
        jmp rules
@one:   lda o_mov,x
        beq :+
        stx z_obj
        jsr player_move
:       rts

; play_picture: once a picture, after its frames (pic_n of them, 3 when
; it comes in time): the others on their way as far as those frames take
; them, then the teams' minds - their places in the formation, the
; keepers', the runners to the ball, the joystick to the one at the ball.
; The ball, the two at it and the keepers go every frame (play_frame).
play_picture:
        jsr play_others
        jsr team_ai             ; (carry clear: the runners too)
        ror pp_help
        jsr @team               ; the cyan team's, then the yellow team's
        jsr swap                ; (as each, the two at once)
        jsr @team
        lda dead_t              ; the yellow team on its own: its brain's
        ora two                 ; stick for its joystick's player till the
        bne :+                  ; next picture
        ldx ctrl
        bmi :+
        jsr brain
:       jmp swap
@team:  bit pp_help
        bmi :+
        jsr help
:       lda dead_t              ; (in play)
        bne :+
        jmp switch
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

; keepers_move: both keepers a frame (unless one is a joystick's, moved
; already)
keepers_move:
        lda pen_kick            ; (a penalty on its way: their minds every
        beq :+                  ; frame, not every fourth - k_pen)
        ldx #0
        jsr keeper
        ldx #11
        jsr keeper
:       ldx #0
        jsr @one
        ldx #11
@one:   lda o_dive,x            ; (a dive's time, its speed less each frame)
        beq :++
        dec o_dive,x
        cmp #DIVE_T - 1
        bcs :++
        lda o_spl,x
        sec
        sbc #DIVE_SLOW
        tay
        lda o_sph,x
        sbc #0
        bcs :+
        lda #0
        tay
:       sta o_sph,x
        tya
        sta o_spl,x
:       cpx ctrl
        beq :+
        cpx ctrl_b
        beq :+
        lda o_mov,x
        beq :+
        stx z_obj
        jsr player_move
:       rts

; step_in: object X on by its step. In line at its two places
; (player_move, ball_move).
.macro step_in
        lda o_xf,x              ; (the step's sign carried into the high
        clc                     ; byte: up one, or down one unless a carry)
        adc o_vxf,x
        sta o_xf,x
        lda o_vxl,x
        bmi :+                  ; (x: on, or back)
        adc o_xl,x
        sta o_xl,x
        bcc :++
        inc o_xh,x
        bcs :++
:       adc o_xl,x
        sta o_xl,x
        bcs :+
        dec o_xh,x
:       lda o_yf,x              ; (y likewise)
        clc
        adc o_vyf,x
        sta o_yf,x
        lda o_vyl,x
        bmi :+
        adc o_yl,x
        sta o_yl,x
        bcc :++
        inc o_yh,x
        bcs :++
:       adc o_yl,x
        sta o_yl,x
        bcs :+
        dec o_yh,x
:
.endmacro

; arrive: player X, if a step has taken him to his destination or past
; it on either axis, put on it there, that axis's step 0 (as Sensible
; Soccer stops its players) - in line at its two places
.macro arrive_in
        lda o_vxl,x
        ora o_vxf,x
        beq :+
        lda o_xl,x              ; past it: (x - dest) has the step's sign,
        sec                     ; or is 0
        sbc o_txl,x
        lda o_xh,x
        sbc o_txh,x
        eor o_vxl,x
        bmi :+                  ; (not there yet)
        lda o_txl,x
        sta o_xl,x
        lda o_txh,x
        sta o_xh,x
        lda #0
        sta o_xf,x
        sta o_vxf,x
        sta o_vxl,x
        sta o_3xf,x
        sta o_3xl,x
:       lda o_vyl,x
        ora o_vyf,x
        beq :+
        lda o_yl,x
        sec
        sbc o_tyl,x
        lda o_yh,x
        sbc o_tyh,x
        eor o_vyl,x
        bmi :+
        lda o_tyl,x
        sta o_yl,x
        lda o_tyh,x
        sta o_yh,x
        lda #0
        sta o_yf,x
        sta o_vyf,x
        sta o_vyl,x
        sta o_3yf,x
        sta o_3yl,x
:
.endmacro

; play_others: everyone else on his way somewhere pic_n frames on, once a
; picture: his step pic_n times, so each picture shows him where he is
play_others:
        ldx #PLAYERS - 1        ; (21 .. 12, 10 .. 1: the keepers have their
        bne @look               ; own way)
@own:   cpx ctrl                ; (the two at the ball: their own way)
        beq @next
        cpx ctrl_b
        bne @go
@next:  dex
        beq @done
        cpx #11
        bne @look
        dex
        bne @look
@done:  stx z_obj               ; (0, as it was left)
        rts
@look:  lda o_mov,x             ; (those standing passed over)
        beq @next
        lda full                ; (after full time, or coming on, no own
        ora enter               ; way: with the rest - and the way anew
        beq @own                ; each picture, the destination noted
        sta o_new,x             ; changed: angle's is rough, on a long way
        dec c_tyh,x             ; one end came first, the other crept on
@go:    stx z_obj               ; - Luca: he ran on standing there)
        lda o_new,x             ; the way anew only for a new destination:
        ora o_slide,x           ; on a straight run it stays the same (a
        beq @step               ; slide's, slower each frame: always)
        lda #0
        sta o_new,x
        jsr aim
        ldx z_obj
@step:  ldy pic_n                ; (three frames, as mostly: his step
        cpy #3                  ; three times, o_3*, in one go)
        bne @sub
        lda o_xf,x
        clc
        adc o_3xf,x
        sta o_xf,x
        lda o_3xl,x
        bmi @sx3
        adc o_xl,x
        sta o_xl,x
        bcc @sy3
        inc o_xh,x
        bcs @sy3
@sx3:   adc o_xl,x
        sta o_xl,x
        bcs @sy3
        dec o_xh,x
@sy3:   lda o_yf,x
        clc
        adc o_3yf,x
        sta o_yf,x
        lda o_3yl,x
        bmi @sy3n
        adc o_yl,x
        sta o_yl,x
        bcc @arr
        inc o_yh,x
        jmp @arr
@sy3n:  adc o_yl,x
        sta o_yl,x
        bcs @arr
        dec o_yh,x
        jmp @arr
@sub:   lda o_xf,x              ; on by his step (as step, the step's
        clc                     ; sign carried into the high byte)
        adc o_vxf,x
        sta o_xf,x
        lda o_vxl,x
        bmi @xl
        adc o_xl,x
        sta o_xl,x
        bcc @y
        inc o_xh,x
        bcs @y
@xl:    adc o_xl,x
        sta o_xl,x
        bcs @y
        dec o_xh,x
@y:     lda o_yf,x
        clc
        adc o_vyf,x
        sta o_yf,x
        lda o_vyl,x
        bmi @yl
        adc o_yl,x
        sta o_yl,x
        bcc @next1
        inc o_yh,x
        bcs @next1
@yl:    adc o_yl,x
        sta o_yl,x
        bcs @next1
        dec o_yh,x
@next1: dey
        bne @sub
@arr:   arrive_in               ; (past it: put there)
        lda o_vxf,x             ; there: the standing picture, passed over
        ora o_vxl,x             ; till he has somewhere to go
        ora o_vyf,x
        ora o_vyl,x
        bne @run
        sta o_step,x
        sta o_mov,x
        jmp @next
@run:   lda o_sph,x             ; his running picture on: a step every
        bne :+                  ; 16 / (speed / 256) frames - every 4 at full
        lda #1                  ; speed, no feet faster than the ground goes
:       sta z_t8                ; by (under 256: as 256)
        ldy pic_n
        cpy #3
        bne @frm
        asl a                   ; (three frames, as mostly: twice it and
        clc                     ; once more)
        adc z_t8
        jmp @frm3
@frm:   lda #0
:       clc
        adc z_t8
        dey
        bne :-
@frm3:  sta z_t8                ; (speed / 256 * frames)
        lda o_run,x
        sec
        sbc z_t8
        bpl @ran
:       inc o_step,x
        clc
        adc #16
        bmi :-
@ran:   sta o_run,x
        jmp @next

; triple: object X's step three times over, o_3* (play_others's for a
; picture of three frames) - kept wherever the step is set. Keeps X.
triple:
        lda o_vxf,x
        asl a
        sta tr_t
        lda o_vxl,x
        rol a
        sta tr_t + 1
        lda tr_t
        clc
        adc o_vxf,x
        sta o_3xf,x
        lda tr_t + 1
        adc o_vxl,x
        sta o_3xl,x
        lda o_vyf,x
        asl a
        sta tr_t
        lda o_vyl,x
        rol a
        sta tr_t + 1
        lda tr_t
        clc
        adc o_vyf,x
        sta o_3yf,x
        lda tr_t + 1
        adc o_vyl,x
        sta o_3yl,x
        rts



; joy_way: A = the way the stick (pj) points, 8 none (Z set, carry set),
; Y its bits. Keeps X.
joy_way:
        lda pj
        and #$0F
        tay
        lda joy_dir,y
        cmp #8
        rts

; control: the joystick's player - where he runs, dribbling, fire; for
; the computer's team its brain works his stick out first, and a pass
; or a shot it wants (br_ev) is made where fire would make one
control:
        ldx me                  ; (fire as it was the frame before)
        lda pf,x
        sta pfire
        lda pj
        sta pf,x
        lda kick_t,x            ; (frames since his team's last kick)
        cmp #255
        beq :+
        inc kick_t,x
:       lda recv_t,x
        beq :+
        dec recv_t,x
:       ldx ctrl
        lda o_slide,x           ; (sliding: the stick has no say)
        beq :+
        rts
:       lda kickoff             ; his team's set piece: the stick turns
        bne @set                ; the taker, fire kicks
        ldy me                  ; in play: a pass let go of too soon goes
        lda pass_q,y            ; as the ball comes to him - the way he
        beq :+                  ; faced as fire was let go (he turns to
        cpx recv                ; meet it), not counting down while a
        bne @qo                 ; pass is on its way to him, nor while
        lda recv_t,y            ; his own ball is (meet: he goes after
        bne @qk                 ; it)
@qo:    cpy last_team
        bne @qd
        cpx last_pl
        beq @qk
@qd:    lda pass_q,y
        sec
        sbc #1
        sta pass_q,y
@qk:    jsr can_kick
        bcs :+
        lda #0
        ldy me
        sta pass_q,y
        lda pass_w,y
        sta o_dir,x
        jmp pass
:       jmp @stick
@set:   lda rs_team
        cmp me
        beq :+
        lda rs_kind             ; (the other team's: at a goal kick and
        cmp #R_GOALKICK         ; the keeper's ball to his place as the
        beq @off                ; rest, spot - out of the box: box_busy;
        cmp #R_KEEPER           ; else he stands off, set_wall - on his
        beq @off                ; way he passed by the ball, at a free
        jmp stand               ; kick 5 pixels off)
@off:   jmp place_formation
:       jsr no_offer            ; (the stick back: no one offered, Luca)
        bcc :+
        jmp @ev
:       jsr fine_kind           ; (a joystick's throw-in or corner: the
        bcs :+                  ; stick turns its aim, fine_aim)
        jsr fine_aim
        jmp @of
:       jsr joy_way
        beq :+
        jsr may_face
        bcs :+
        sta o_dir,x
:
@of:    jsr offering            ; (a team-mate comes to the way he looks)
        jmp @ev
@stick: jsr joy_way
        bne @run
        jsr meet                ; the stick let go: he stops, or meets a
        jmp @fire               ; pass, or stops the ball at his feet
@run:   sta o_dir,x
        tay
        lda #1
        sta o_mov,x
        jsr aim_run             ; ahead the way the stick points (set
        jsr inside              ; each frame)
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
        cmp #DRIB_NEAR + 1
        bcs @far
        lda o_zl + BALL
        cmp #13
        bcs @far
        ldy o_sph + BALL        ; (a fast ball - a shot, a clearance -
        cpy #>FAST_SP           ; only at his feet: at the body's height
        bcc :+                  ; anyone running by took it, Luca: they
        cpx last_pl             ; block every shot; and not his own:
        beq @far                ; running on after it, the stick pulled
        cmp #FAST_Z + 1         ; back, he took his shot back)
        bcs @far
:
        lda frame_n             ; (a touch every second frame, the teams
        eor me                  ; in turn, as Sensible Soccer's: face to
        lsr a                   ; face, either may get it - but a turn at
        bcc :+                  ; once: the C64 turns him only on his
        ldy me                  ; team's frames)
        lda o_dir,x
        cmp glue_d,y
        beq @far
:
        lda kickoff             ; (not the other team's set piece, nor
        bne @far                ; just tackled: lock_t)
        ldy me
        lda lock_t,y
        bne @far
        jsr dribble
@far:   lda kickoff
        beq @ev
        rts
@ev:    lda me                  ; the brain's pass or shot, as fire's
        beq @fire               ; (its team's only)
        lda br_ev
        beq @fire
        pha
        lda #0
        sta br_ev
        ldx ctrl
        jsr can_kick
        pla
        bcs @fire
        cmp #1
        bne :+
        jmp pass
:       lda #SHOT_CPU
        sta sh_pow
        jmp shot
@fire:  lda frame_n             ; fire as Sensible Soccer's players act on
        eor me                  ; it: every second frame (the dribble's),
        lsr a
        jcs @done               ; as it was the frame before - so one or
        lda pfire               ; two frames after it is pressed or let go
        and #J_FIRE             ; fire: let go within SHOT_HOLD - 1
        jeq @let                ; frames a pass, held SHOT_HOLD frames a
        lda fire_n              ; shot at once, held on harder (charge) -
        cmp #$FF                ; Luca: the ball must go as the game knows
        jeq @done               ; it is a shot, not as fire is let go
        cmp #$80                ; (the shot on its way: fire held on)
        jcs @charge
        lda kickoff             ; pressed, the stick pushed, the ball in
        bne @foot               ; the air near him: a diving header (as
        ldx ctrl                ; Sensible Soccer has only that, c13af4)
        lda fire_n
        bne @foot
        jsr can_dive
        bcs @foot
        lda #$FF
        sta fire_n
        jmp dive_head
@foot:  lda fire_n
        cmp #SHOT_HOLD
        bcs @held
        ldx ctrl                ; (the way he faces while fire is held:
        ldy me                  ; pass_q's pass - let go, he turns to meet
        lda o_dir,x             ; the ball, and it went back)
        sta pass_w,y
        inc fire_n              ; (two frames a time)
        inc fire_n
        lda fire_n
        cmp #2                  ; just pressed, the ball not at his feet
        bne @held               ; but near: a sliding tackle (can_slide)
        lda kickoff
        bne @held
        jsr can_slide
        bcs @try
        lda #$FF
        sta fire_n
        ldx ctrl
        jmp slide
@try:   jsr can_try             ; (the ball in the air near him: he jumps
        bcs @held               ; for it - head heads it if it comes, Luca:
        lda #$FF                ; many more tries, missed ones too)
        sta fire_n
        lda #HEAD_T
        sta o_zl,x
        sta jumps
        rts
@held:  lda fire_n                ; (held SHOT_HOLD: the shot, as soon as
        cmp #SHOT_HOLD          ; the ball is at his feet - fire held on
        bcc @done               ; charges it: $80 on, a throw-in $C0 on)
        jsr can_kick
        bcs @done
        ldy #$80
        jsr at_throw
        beq :+
        ldy #$C0
:       jsr lofted              ; (a goal kick, the keeper's, a corner:
        bcs :+                  ; high unless the stick pushes on - $A0)
        ldy #$A0
:       sty fire_n
@kick:  lda #0                  ; (as hard as shot_power's least)
        sta sh_pow
        jmp shot
@charge:
        and #$1F                ; (fire held on: the steps so far)
        cmp #CHARGE_N
        bcs @full
        lda last_team           ; (the ball still his kick, untouched)
        cmp me
        bne @full
        lda last_pl
        cmp kick_pl
        bne @full
        inc fire_n
        jmp charge
@full:  lda #$FF                ; (no more: till fire is let go)
        sta fire_n
        rts
@let:   lda fire_n
        ldy #0
        sty fire_n
        cmp #1
        bcc @done               ; (not held)
        cmp #$80
        bcs @done               ; (the shot taken)
        cmp #SHOT_HOLD          ; let go after SHOT_HOLD, the ball not at
        bcc :+                  ; his feet then: the shot if it is now
        jsr can_kick
        bcs @done
        jmp @kick
:       jsr can_kick
        bcs @wait
        ldy me                  ; (the way he faced with fire held)
        lda pass_w,y
        sta o_dir,x
        jmp pass
@wait:  lda #PASS_Q             ; (too soon: it goes as the ball comes)
        ldy me
        sta pass_q,y
@done:  rts

; duel: both joystick's players at the ball, low, and neither team just
; having won it so: one of them gets it, as on the C64 (Arlasoft Soccer,
; whose players keep the ball so): the better (sk_duel) the more often -
; 16 in 32 even, each level between them one in 32 more, at most 23 -
; the ball dead at his feet, and the other team not to dribble it for
; LOCK_T frames
duel:
        lda lock_t
        ora lock_t + 1
        bne @no
        lda o_zl + BALL
        cmp #13
        bcs @no
        ldx ctrl_b
        bmi @no
        jsr at_feet
        bcs @no
        ldx ctrl
        jsr at_feet
        bcs @no
        ldy ctrl_b
        jsr odds
        ldy #1                  ; (the loser's team)
        bcc :+
        ldx ctrl_b
        dey
:       lda #LOCK_T
        sta lock_t,y
        tya
        eor #1
        sta last_team
        jsr touch_x
        ldx #BALL
        jmp stand
@no:    rts

; at_feet: carry clear if player X is at the ball (NEAR), not sliding.
; Keeps X.
at_feet:
        lda o_slide,x
        bne @far
        jsr mate_dist
        lda tmp + 1
        bne @far
        lda tmp
        cmp #NEAR + 1
        rts
@far:   sec
        rts

; odds: carry clear if player X wins the ball from player Y, the better
; (sk_duel) the more often: 16 in 32 even, each level between them one in
; 32 more, 9 - 23. Keeps X, Y.
odds:
        lda sk_duel,x
        clc
        adc #16
        sec
        sbc sk_duel,y
        cmp #9
        bcs :+
        lda #9
:       cmp #24
        bcc :+
        lda #23
:       sta tmp
        jsr rnd
        and #31
        cmp tmp
        rts

; may_face: carry clear if a set piece's taker may face way A, as
; Sensible Soccer lets him (a bit for each way, c0f8ea): into the pitch
; or towards the other goal - up to 90 degrees off for a throw-in and
; the computer's kick-off, 45 for a goal kick, the keeper's kick, a
; corner and a penalty, any way for a free kick and a joystick's
; kick-off. Keeps A, X.
may_face:
        sta mf_a
        ldy rs_kind
        lda rs_team             ; the other goal: up 0, down 4
        eor flip
        beq :+
        lda #4
:       cpy #R_THROW            ; a throw-in: away from its line
        bne @corner
        jsr ball_rx
        lda #2
        bcc @c
        lda #6
        bcs @c
@corner:
        cpy #R_CORNER           ; a corner: the diagonal into the pitch
        bne @c
        lda #0
        sta mf_c
        lda o_yl + BALL
        cmp #<369
        lda o_yh + BALL
        sbc #>369
        rol mf_c
        jsr ball_rx
        rol mf_c
        ldy mf_c
        lda corner_c,y
@c:     sta mf_c
        lda mf_a                ; how far off it: 0-4 ways
        sec
        sbc mf_c
        and #7
        cmp #5
        bcc :+
        eor #$FF
        adc #8                  ; (carry set: 8 less it)
:       ldy rs_kind             ; (a joystick's kick-off any way, as a
        bne @r                  ; free kick's - Luca: to the team-mates
        pha                     ; behind too; the computer's as Sensible
        jsr cpu_side            ; Soccer's)
        pla
        bcs @r
        ldy #R_FREE
@r:     cmp face_r,y
        lda mf_a
        rts

; ---- a throw-in's and a corner's aim ---------------------------------------
;
; A joystick's throw-in or corner is aimed finer than its eight ways:
; each push of the stick turns the aim a step towards the way pushed
; (held, a step every SP_REP frames after SP_FIRST), among sp_ways' -
; a throw-in's seven, 22.5 degrees apart up to 67.5 either side of
; straight in (not along the line), a corner's six from just off the
; goal line to 45 degrees in (the box is all within 25: the C64 turns
; its corners in to 8.5 and 19.3). Two dots show the aim (draw_aim); the
; kick goes that way (aim_to), a pass to a team-mate within half the
; usual cone of it (pass).

SP_FIRST    = 15
SP_REP      = 8

; fine_kind: carry clear if the set piece is a throw-in or a corner and
; team me plays by joystick
fine_kind:
        lda me
        beq :+
        lda two
        beq @no
:       lda rs_kind
        cmp #R_THROW
        beq @yes
        cmp #R_CORNER
        beq @yes
@no:    sec
        rts
@yes:   clc
        rts

; fine_on: carry clear and A = the aim's way (0-255) if the ball is a
; joystick's throw-in or corner being taken, aimed. Keeps X.
fine_on:
        lda kickoff
        beq @no
        lda sp_aim
        bmi @no
        jsr fine_kind
        bcs @no
        jmp sp_way_of
@no:    sec
        rts

; aim_to: the ball's destination 1000 pixels the aim's way, if fine_on.
; Keeps X.
aim_to:
        jsr fine_on
        bcs @no
        pha
        jsr sin4                ; x: + sin
        clc
        adc o_xl + BALL
        sta o_txl + BALL
        lda tmp + 1
        adc o_xh + BALL
        sta o_txh + BALL
        pla
        clc
        adc #64                 ; y: - cos (sin a quarter on)
        jsr sin4
        lda o_yl + BALL
        sec
        sbc tmp
        sta o_tyl + BALL
        lda o_yh + BALL
        sbc tmp + 1
        sta o_tyh + BALL
@no:    rts

; sin4: tmp, Y:A = 1000 * sin of way A (0-255: 0 up, 64 right), signed
; (sin_t's 250, times 4). Keeps X.
sin4:
        sta sp_w
        and #63
        bit sp_w                ; (the second and fourth quarters: back)
        bvc :+
        eor #$FF
        clc
        adc #65
:       tay
        lda sin_t,y
        sta tmp
        lda #0
        asl tmp
        rol a
        asl tmp
        rol a
        sta tmp + 1
        bit sp_w                ; (the second half: less than 0)
        bpl :+
        jsr neg_tmp
:       ldy tmp + 1
        lda tmp
        rts

; fine_aim: a frame of a joystick's throw-in or corner, player X its
; taker: the aim first the middle one, then turned by the stick; he
; faces it (the nearest of his eight ways). Keeps X.
fine_aim:
        lda sp_aim
        bpl :+
        lda #3                  ; (both: the fourth, straight in; the old
        sta sp_aim              ; corner's diagonal, 19.7 degrees)
        lda pj                  ; (the stick held as it began: no step till
        and #$0F                ; it is pushed again)
        tay
        lda joy_dir,y
        sta sp_j
        lda #0
        sta sp_rep
:       lda pj
        and #$0F
        tay
        lda joy_dir,y
        cmp sp_j
        sta sp_j
        bne @new                ; (pushed another way: a step at once)
        cmp #8
        beq @face               ; (let go)
        dec sp_rep
        bne @face
        lda #SP_REP
        bne @step
@new:   cmp #8
        beq @face
        lda #SP_FIRST
@step:  sta sp_rep
        jsr sp_way_of           ; (sp_n: how many; after them the middle
        ldy sp_n                ; one, straight in - the ways measured
        jsr way_y               ; from it either side, not round about:
        sta sp_r                ; the stick out of the pitch goes to an
        lda sp_j                ; end)
        asl a                   ; the stick's way, 0-255
        asl a
        asl a
        asl a
        asl a
        sec
        sbc sp_r
        eor #$80
        sta sp_s
        jsr sp_way_of           ; a step, if one is nearer it
        jsr sp_off
        sta sp_d
        ldy sp_aim
        iny
        cpy sp_n
        bcs @back
        jsr sp_try
        bcc @face
@back:  ldy sp_aim
        dey
        bmi @face
        jsr sp_try
@face:  jsr sp_way_of           ; (the aim's way)
        jsr dir_a
        sta o_dir,x
        rts

; sp_try: carry clear, the aim aim Y, if its way is nearer the stick's
; than sp_d. Keeps X.
sp_try:
        tya
        pha
        jsr way_y
        jsr sp_off
        tay
        pla
        cpy sp_d
        bcs :+
        sta sp_aim
:       rts

; sp_off: A = how far way A is from the stick's: both from the middle
; one (sp_r), -128 to 127 (+ 128: sp_s the stick's)
sp_off:
        sec
        sbc sp_r
        eor #$80
        sec
        sbc sp_s
        bcs :+
        eor #$FF
        adc #1
:       rts

; sp_way_of: A = the way of aim sp_aim. Keeps X.
sp_way_of:
        ldy sp_aim
        jmp way_y

; way_y: A = the way of aim Y (sp_ways' for the kind, turned about for
; the side: a throw-in from the right line, a corner at the right turned
; across; a throw-in for the team attacking down, a corner at the bottom
; upside down); sp_n how many aims the kind has. Keeps X.
way_y:
        lda rs_kind
        cmp #R_CORNER
        beq @corner
        lda #7
        sta sp_n
        lda sp_ways_t,y
        sta sp_w
        lda rs_team             ; (attacking down: upside down)
        eor flip
        beq @x
        bne @y
@corner:
        lda #6
        sta sp_n
        lda sp_ways_c,y
        sta sp_w
        lda o_yl + BALL         ; (the bottom: upside down)
        cmp #<369
        lda o_yh + BALL
        sbc #>369
        bcc @x
@y:     lda #128
        sec
        sbc sp_w
        sta sp_w
@x:     jsr ball_rx             ; (the right: across)
        lda sp_w
        bcc :+
        eor #$FF
        clc
        adc #1
:       rts

; the aims, from the ball on the left touch line attacking up and the
; top left corner: ways 0-255, 0 up, 64 right
sp_ways_t:  .byte 16, 32, 48, 64, 80, 96, 112, 64     ; (then the middle)
sp_ways_c:  .byte 67, 70, 74, 78, 83, 96, 96
sin_t:      .byte 0, 6, 12, 18, 25, 31, 37, 43, 49, 55, 61, 67, 73, 78, 84, 90, 96, 101, 107, 112, 118, 123, 129, 134, 139, 144, 149, 154, 159, 163, 168, 172, 177, 181, 185, 189, 193, 197, 201, 204, 208, 211, 214, 218, 220, 223, 226, 229, 231, 233, 235, 237, 239, 241, 243, 244, 245, 246, 247, 248, 249, 249, 250, 250, 250

; ball_rx: carry set if the ball is right of the middle (x 304 on)
ball_rx:
        lda o_xl + BALL
        cmp #<304
        lda o_xh + BALL
        sbc #>304
        rts

; meet: the joystick's player X, the stick let go: a pass to him he goes
; to meet; his own ball while fire is held (a pass or a shot to come) or
; a pass let go of too soon waits (pass_q), after it too; else he stands
; - and a ball come to him runs on past him, as Sensible Soccer's does
; (c1383e: no stick, no touch). Keeps X.
meet:
        jsr dist2
        ldy me
        cpx recv                ; a pass to him: after it, while it runs
        bne @mine
        lda recv_t,y
        bne @go
@mine:  cpy last_team           ; (his dribble, the stick let go as fire
        bne @stand              ; went down: he stood, the ball rolled on
        cpx last_pl             ; out of his reach and the pass waited in
        bne @stand              ; vain - Luca: three passes in ten the
        lda pass_q,y            ; ball stays glued, tests/taps.py)
        bne @go
        lda fire_n
        beq @stand
        bmi @stand
@go:    ldy #SP_RUN
        jsr to_ball
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
; his feet, near enough, and low - a goal kick or the keeper's ball not
; while the other team is in the box still (box_busy). Keeps X.
can_kick:
        lda kickoff
        beq :+
        jsr box_busy
        bcs @no
:       jsr dist2
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

; can_dive: carry clear if the stick is pushed and the ball in the air
; (higher than DHEAD_Z_LO, at most DHEAD_Z_HI) near player X (DHEAD_D2).
; Higher, he jumps for it (can_try) and heads it the stick's way - the
; dive heads only DHEAD_Z_HI high: under a higher ball he dived for
; nothing (Luca: do the headers want no way pushed?). Keeps X.
can_dive:
        jsr stick_way
        cmp #8
        beq @no
        lda o_zl + BALL
        cmp #DHEAD_Z_LO + 1
        bcc @no
        cmp #DHEAD_Z_HI + 1
        bcs @no
        jsr mate_dist
        lda tmp
        cmp #<(DHEAD_D2 + 1)
        lda tmp + 1
        sbc #>(DHEAD_D2 + 1)
        rts
@no:    sec
        rts

; can_slide: carry clear if the joystick's player X slides for the ball
; as Sensible Soccer's do (c13aa6) - whoever's it is: the stick pushed,
; the ball low (SLIDE_Z), near (DHEAD_D2, as for a diving header) but not
; close (CLOSE: its $37 alone), and the helper not nearer it. Keeps X.
can_slide:
        cpx recv                ; (a pass on its way to him: fire passes
        bne :+                  ; it on as it comes, pass_q - he slid
        ldy me                  ; for it, Luca's passes went wrong)
        lda recv_t,y
        bne @no
:       lda last_team           ; (nor for his own ball, dribbled ahead)
        cmp me
        bne :+
        cpx last_pl
        beq @no
:       jsr stick_way
        cmp #8
        beq @no
        jsr slide_d2
        bcs @no
        lda tmp
        sta cp_d
        lda tmp + 1
        sta cp_d + 1
        ldy helper
        bmi @yes
        jsr dist_y
        lda tmp
        cmp cp_d
        lda tmp + 1
        sbc cp_d + 1
        bcc @no                 ; (the helper nearer)
@yes:   clc
        rts
@no:    sec
        rts

; cpu_slide: carry clear if the yellow team's runner X (its helper)
; slides in, as Sensible Soccer's computer team's runner does (c154a8,
; c142b2): the ball where he can slide for it (slide_d2) and within
; CPU_SLIDE_D2 of him, the cyan joystick's player within CPU_OPP_D2 of it
; and not facing his way or one off it (not round past 0). Keeps X.
cpu_slide:
        jsr slide_d2
        bcs @no
        lda tmp + 1
        bne @no
        lda tmp
        cmp #CPU_SLIDE_D2 + 1
        bcs @no
        ldy ctrl
        jsr dist_y
        lda tmp
        cmp #<(CPU_OPP_D2 + 1)
        lda tmp + 1
        sbc #>(CPU_OPP_D2 + 1)
        bcs @no
        lda o_dir,y
        sec
        sbc o_dir,x
        clc
        adc #1
        cmp #3
        bcc @no
        clc
        rts
@no:    sec
        rts

; slide_d2: carry clear if the ball is where player X can slide for it
; (Sensible Soccer's $37): low (SLIDE_Z), its distance squared above
; CLOSE and at most DHEAD_D2 - tmp that. Keeps X.
slide_d2:
        lda o_zl + BALL
        cmp #SLIDE_Z + 1
        bcs @no
        jsr mate_dist
        lda tmp + 1
        bne :+
        lda tmp
        cmp #CLOSE + 1
        bcc @no
:       lda tmp
        cmp #<(DHEAD_D2 + 1)
        lda tmp + 1
        sbc #>(DHEAD_D2 + 1)
        rts
@no:    sec
        rts

; stick_way: A = the way the joystick points, 8 none. Keeps X.
stick_way:
        lda pj
        and #$0F
        tay
        lda joy_dir,y
        rts

; dive_head: player X dives for the ball, a sliding tackle in the air
; (slides heads it on when he reaches it). Keeps X.
dive_head:
        jsr stick_way           ; (the stick's way)
        sta o_dir,x
        jsr slide
        lda #1
        sta o_hd,x
        lda #<SPEED_DHEAD
        sta o_spl,x
        lda #>SPEED_DHEAD
        sta o_sph,x
        rts

; shot: the ball the way the joystick's player faces, hard (his shooting)
; and rising; the aftertouch on
shot:
        jsr kick_by
        ldy me                  ; (the team's)
        lda o_dir,x
        sta at_dir,y
        tay
        jsr ball_ahead
        jsr aim_to
        jsr shot_power
        lda #<SHOT_DZ
        ldy kickoff             ; (a set piece's kick, a throw-in: as
        beq :+                  ; before, their flights set by it - at
        lda #<SET_DZ            ; 1.44 the long throws and goal kicks
:       sta o_dzf + BALL        ; came down into the heads)
        lda #>SHOT_DZ
        sta o_dzl + BALL
        jsr sfx_kick
        jsr at_throw            ; (a long throw-in: from his head - and no
        beq @at                 ; aftertouch: on its fifth frame it set it
        sta o_zl + BALL         ; to a shot's 2560, the throw-ins went
        lda #$FF                ; super powerful still, said Luca)
        .byte $2C               ; (bit: over the lda)
@at:    lda #0
        sta at_n
        lda #$FF
        rts

; lofted: carry clear if the set piece the joystick's team takes is one
; whose kick held goes high by itself (charge): a goal kick, the keeper's,
; a corner - Luca: the goal kick to be high, it was always intercepted.
; Keeps X.
lofted:
        lda kickoff
        beq @no
        lda rs_kind
        cmp #R_GOALKICK
        beq @yes
        cmp #R_CORNER
        beq @yes
        cmp #R_KEEPER
        beq @yes
@no:    sec
        rts
@yes:   clc
        rts

; charge: a step of fire held on after the joystick's shot (control) -
; the ball CHARGE_D faster (a throw-in half), and the stick pulled back
; CHARGE_DZ more rise, up to LIFT_HI_DZ: let go before CHARGE_N steps, a
; shot as hard and high as wanted (Luca). The computer's shot as Sensible
; Soccer's: its aftertouch's lift.
charge:
        lda #CHARGE_D
        bit fire_n              ; (bit 6: a throw-in)
        bvc :+
        lsr a
:       clc
        adc o_spl + BALL
        sta o_spl + BALL
        bcc :+
        inc o_sph + BALL
:       jsr stick_way           ; pulled back: 3 - 5 off the shot's way -
        cmp #8                  ; a goal kick's, the keeper's, a corner's
        beq @let                ; (bit 5) let go or across too
        sta tmp
        ldy me
        lda at_dir,y
        sec
        sbc tmp
        and #7
        cmp #3
        bcc @on
        cmp #6
        bcc @up
        cmp #7
        bcs @on
@let:   lda fire_n              ; (let go, across: bit 5's only)
        and #$20
        beq @done
        bne @up
@on:    cmp #2                  ; (0, 1, 7 on: low)
        beq @let
@done2: rts
@up:    lda o_dzf + BALL        ; (rising less than LIFT_HI_DZ: more)
        cmp #<LIFT_HI_DZ
        lda o_dzl + BALL
        sbc #>LIFT_HI_DZ
        bvc :+
        eor #$80
:       bpl @done
        lda o_dzf + BALL
        clc
        adc #CHARGE_DZ
        sta o_dzf + BALL
        bcc @done
        inc o_dzl + BALL
@done:  rts

; aftertouch: for ten frames after a shot, the joystick bends it - the
; first way it is pushed across the shot (or across and back) sends the
; ball's destination that side, less each frame; and on the fifth frame
; pulled back it lifts the ball high and faster, let go or across a
; little less, pushed on not at all
aftertouch:
        ldx at_n
        bpl :+
        rts                     ; (none)
:       ldy me                  ; (at_side, at_dir: the team's)
        lda at_dir,y
        sta at_d
        txa
        bne :+
        lda #$FF                ; frame 0: no side yet
        sta at_side,y
:       lda pj                  ; the joystick's way, 8 none
        and #$0F
        tax
        lda joy_dir,x
        sta at_j
        ldx at_n
        lda at_side,y
        bpl @bend
        lda at_j                ; no side yet: across the shot latches it
        cmp #8
        beq @lift
        lda at_d
        sec
        sbc at_j
        and #7
        beq @lift               ; (on, or back: no side)
        cmp #4
        beq @lift
        lda #0
        bcc :+                  ; 1-3: side 0, 5-7: side 1
        lda #1
:       sta at_side,y
@bend:  lda at_d                ; the destination on by curl * weight
        asl a
        ora at_side,y
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
        lda me                  ; (a player's shot: fire held on lifts it,
        beq @next               ; charge - not this)
        lda two
        bne @next
        lda at_j
        cmp #8
        beq @mid                ; let go
        lda at_d
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
        lda at_d                ; slower diagonally (7/8) and up or down (3/4)
        lsr a
        bcs @diag
        lda at_d
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
        ldy ctrl                ; |dx|, |dy|: the high byte 0, or $FF and
        lda o_xl + BALL         ; the low byte negated (in tmp, as are the
        sec                     ; far ones'); 64 or more, or else: far
        sbc o_xl,y
        sta tmp
        lda o_xh + BALL
        sbc o_xh,y
        beq @x
        bpl @big
        cmp #$FF
        bne @xbig
        lda tmp
        eor #$FF
        clc
        adc #1
        sta tmp
        bcs @big                ; (256)
@x:     lda tmp
        cmp #64
        bcs @big
        sta d_ax
        lda o_yl + BALL
        sec
        sbc o_yl,y
        sta tmp
        lda o_yh + BALL
        sbc o_yh,y
        beq @y
        bpl @big
        cmp #$FF
        bne @xbig
        lda tmp
        eor #$FF
        clc
        adc #1
        sta tmp
        bcs @big
@y:     lda tmp
        cmp #64
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
@xbig:  lda tmp                 ; (negative and far: the low byte negated)
        eor #$FF
        clc
        adc #1
        sta tmp
@big:   lda #$FF
        sta d2
        sta d2 + 1
        rts

; dribble: the ball kicked on ahead, the way the joystick's player runs,
; as fast as he runs, on every other touch a little faster by his skill
; (drib_of: the better, the closer it stays) and with it behind him half
; a pixel a frame more - unless he is past his glue, as on the C64
; (Arlasoft Soccer): his team counts his turns with the ball since it
; got it (no touch for GLUE_GAP frames: anew); from glue_of's on (by
; sk_duel: 4 - 21), a turn with the other team's joystick's player at the
; ball too has his team not touch it for GLUE_T frames - the other's then
dribble:
        ldy me
        lda frame_n
        sec
        sbc glue_f,y
        cmp #GLUE_GAP + 1
        lda frame_n
        sta glue_f,y
        lda o_dir,x
        bcc @on
        sta glue_d,y            ; (anew)
        lda #0
        sta glue_n,y
        beq @kick
@on:    cmp glue_d,y
        beq @kick
        sta glue_d,y            ; (a turn)
        lda glue_n,y
        clc
        adc #1
        sta glue_n,y
        ldy sk_duel,x
        cmp glue_of - 7,y
        bcc @kick
        txa                     ; (the other team's at it: near_ball)
        pha
        clc
        ldx ctrl_b
        bmi :+
        jsr near_ball
:       pla
        tax
        bcc @kick
        ldy me
        lda #GLUE_T
        sta lock_t,y
        rts
@kick:
        jsr touch_me
        ldy sk_duel,x           ; as fast as he runs; every other touch
        lda frame_n             ; (the C64's L48F7, frame bit 1) faster
        and #2                  ; by drib_of, by his skill
        beq :+
        lda drib_of - 7,y
:       clc
        adc o_spl,x
        sta o_spl + BALL
        lda o_sph,x
        adc #0
        sta o_sph + BALL
        jsr ball_way            ; and half a pixel a frame more with it
        sec                     ; behind him - 90 degrees or more off
        sbc o_dir,x             ; the way he faces (L4924's): ahead of
        sec                     ; him at once
        sbc #2
        and #7
        cmp #5
        bcs :+
        inc o_sph + BALL
:
        ldy o_dir,x             ; up: the ball a pixel further out beside
        bne @ahead              ; him while it is within 4 of his x (to
        lda o_xl + BALL         ; the right if level), as Sensible Soccer
        sec                     ; has it - else it would be hidden behind
        sbc o_xl,x              ; him; so it is at his right foot, and a
        bmi @left               ; turn up and right keeps it (at his
        cmp #5                  ; feet: x within 7, the low byte enough)
        bcs @ahead
        inc o_xl + BALL
        bne @ahead
        inc o_xh + BALL
        bne @ahead
@left:  cmp #<(-4)
        bcc @ahead
        lda o_xl + BALL
        bne :+
        dec o_xh + BALL
:       dec o_xl + BALL
@ahead: jsr ball_ahead
        lda o_dzl + BALL        ; no longer rising
        bmi :+
        ora o_dzf + BALL
        beq :+
        lda #$FF
        sta o_dzl + BALL
        sta o_dzf + BALL
:       rts

        .segment "RODATA"
glue_of:    .byte 4, 5, 6, 8, 11, 14, 17, 21, 21    ; (by sk_duel, 7-15: the
                                ; C64's $3E88 - 8 - 22 kept the ball too long,
                                ; Ghana's too, said Luca)
drib_of:    .byte 130, 116, 102, 88, 74, 60, 46, 32, 32  ; ($3E80)
        .segment "CODE"

; trap: the first touch, as Sensible Soccer's (c14314, c118ea): the
; helper running to the ball, at it (at_ball), has the joystick now and
; stops; the ball lies dead a pixel before him, the way he faces, on the
; ground. Keeps X (ctrl).
trap:
        jsr touch_me
        jsr stand
        ldy o_dir,x
        lda vec_xh,y
        jsr one
        lda o_xl,x
        clc
        adc tmp
        sta o_xl + BALL
        lda o_xh,x
        adc tmp + 1
        sta o_xh + BALL
        lda vec_yh,y
        jsr one
        lda o_yl,x
        clc
        adc tmp
        sta o_yl + BALL
        lda o_yh,x
        adc tmp + 1
        sta o_yh + BALL
        lda #0
        sta o_zf + BALL
        sta o_zl + BALL
        lda o_dzl + BALL        ; (its fall halved)
        cmp #$80
        ror o_dzl + BALL
        ror o_dzf + BALL
        ldx #BALL
        jsr stand
        ldx ctrl
        rts

; one: tmp = -1, 0 or 1 by the sign of A (a way's high byte, vec_*h).
; Keeps X, Y.
one:
        cmp #0
        beq @z
        bmi @m
        lda #1
        sta tmp
        lda #0
        sta tmp + 1
        rts
@m:     lda #$FF
        sta tmp
        sta tmp + 1
        rts
@z:     sta tmp
        sta tmp + 1
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

; to_ball: player X on his way to the ball, at speed Y (speed)
to_ball:
        lda o_xl + BALL
        sta o_txl,x
        lda o_xh + BALL
        sta o_txh,x
        lda o_yl + BALL
        sta o_tyl,x
        lda o_yh + BALL
        sta o_tyh,x
        jmp speed

; speed: player X's speed Y (SP_*): SPEED_RUN, SPEED_BALL, or running
; to the ball 896 + twice his pace (Sensible Soccer's c107d4: his team's
; and his own on top). Keeps X, Y.
speed:
        lda #<SPEED_RUN
        sta o_spl,x
        lda #>SPEED_RUN
        cpy #SP_RUN
        beq @hi
        lda #<SPEED_BALL
        sta o_spl,x
        lda #>SPEED_BALL
        cpy #SP_BALL
        beq @hi
        lda sk_pace,x
        asl a
        sta o_spl,x
        lda #>896
        adc #0
        sta o_sph,x
        lda o_spl,x
        clc
        adc #<896
        sta o_spl,x
        bcc :+
        inc o_sph,x
:       rts
@hi:    sta o_sph,x
        rts

; shot_speed: the ball as hard as anyone shoots, as in Sensible Soccer
; (c11756: SHOT_SPEED, for all). Keeps X, Y.
shot_speed:
        lda #<SHOT_SPEED
        sta o_spl + BALL
        lda #>SHOT_SPEED
        sta o_sph + BALL
        rts

; shot_power: the ball as hard as sh_pow has it - 1792 and 32 a step,
; up to 2560 (Sensible Soccer's, and the C64's, is 2208 for all: sh_pow
; 13, the computer's), more by the kicker X's skill (shot_b, by sk_duel:
; up to 192); a throw-in 512 less (it went to the moon, said Luca). Keeps X.
shot_power:
        lda #0
        sta tmp + 1
        lda sh_pow
        asl a
        asl a
        asl a
        asl a
        rol tmp + 1
        asl a
        rol tmp + 1
        ldy sk_duel,x
        clc
        adc shot_b - 7,y
        bcc :+
        inc tmp + 1
:       clc
        adc #<1792
        sta o_spl + BALL
        lda tmp + 1
        adc #>1792
        sta o_sph + BALL
        jsr at_throw
        beq :+
        lda o_sph + BALL
        sec
        sbc #>512
        sta o_sph + BALL
:       rts
shot_b:     .byte 0, 24, 48, 72, 96, 128, 160, 192, 192

; kick_by: the joystick's player (ctrl) kicks the ball - his team's and
; his touch, and his kick. X = ctrl after.
kick_by:
        lda me
        sta last_team
        tay
        lda #0
        sta kick_t,y
        ldx ctrl                ; (X: his)
        stx kick_pl
        jmp touch_x

; ball_ahead: the ball's destination 1000 pixels from it, way Y - a
; corner's and a throw-in's turned in a little, as the C64 turns them: up
; or down (along a touch line) 250 across towards the middle; a corner
; along the goal line 150 in from it, slanting 350 in from it, not 1000.
; Keeps X.
ball_ahead:
        txa
        pha
        ldx #BALL
        jsr aim_way
        pla
        tax
        lda kickoff             ; (a set piece taken)
        beq @no
        lda rs_kind
        cmp #R_THROW
        beq @in
        cmp #R_CORNER
        beq @in
        cmp #R_PENALTY          ; a penalty's slanting: at the corner, as
        bne @no                 ; the computer's (cpu_pen) - PEN_DX across,
        tya                     ; inside the post; 1000 sent every one
        lsr a                   ; with a way pushed wide, said Luca
        bcc @no
        cpy #4                  ; (1, 3: right)
        lda #<(PEN_DX - 1000)
        ldy #>(PEN_DX - 1000)
        bcc @add
        lda #<(1000 - PEN_DX)
        ldy #>(1000 - PEN_DX)
        bcs @add
@in:    tya
        and #3
        bne @y
        jsr ball_rx             ; up or down: across, towards the middle
        lda #<250
        ldy #>250
        bcc @add
        lda #<(-250)
        ldy #>(-250)
@add:   clc
        adc o_txl + BALL
        sta o_txl + BALL
        tya
        adc o_txh + BALL
        sta o_txh + BALL
@no:    rts
@y:     lda rs_kind             ; (a corner's: the way odd, slanting)
        cmp #R_CORNER
        bne @no
        tya
        lsr a
        lda #<150
        sta tmp
        lda #>150
        bcc :+
        lda #<350
        sta tmp
        lda #>350
:       sta tmp + 1
        lda o_yl + BALL         ; (in: down from the top line, up from
        cmp #<369               ; the bottom one)
        lda o_yh + BALL
        sbc #>369
        bcc :+
        lda #0
        sbc tmp                 ; (carry set)
        sta tmp
        lda #0
        sbc tmp + 1
        sta tmp + 1
:       lda o_yl + BALL
        clc
        adc tmp
        sta o_tyl + BALL
        lda o_yh + BALL
        adc tmp + 1
        sta o_tyh + BALL
        rts

; pass: the ball to the nearest team-mate within 67.5 degrees of the way
; the joystick's player faces - one more than 22.5 off it as if twice as
; far: the one the way he faces if there is one near enough, else the
; nearest to that side; or, no one, straight on
pass:
        jsr kick_by
        ldx offer               ; (a team-mate offering himself at a
        bmi :+                  ; throw-in or goal kick: to him - offering)
        lda kickoff
        beq :+
        stx mate
        bpl @got
:       ldy ctrl                ; the way he kicks, 0-255
        lda o_dir,y
        asl a
        asl a
        asl a
        asl a
        asl a
        sta kick_way
        lda #48
        sta p_w
        jsr fine_on             ; (a throw-in's or corner's aim: that way,
        bcs :+                  ; and the cone half as wide first)
        sta kick_way
        bcc @half
:       jsr keeper_kick         ; (a goal kick, the keeper's: half as wide
        bcc @half               ; first - the way he faces chooses, Luca;
        lda kickoff             ; no one so: as wide - a tap a safe pass;
        beq @one                ; a kick-off's too, Luca: else always to
        lda rs_kind             ; the two beside him, the nearest)
        bne @one                ; (R_KICKOFF)
@half:  lsr p_w
        jsr pass_scan
        ldx mate
        bpl @got
        asl p_w
@one:   jsr pass_scan
@got:   ldx mate
        bmi :+
        stx recv                ; he runs to meet it (help), the joystick
        stx helper              ; to the nearest of the others (switch)
        ldy me
        lda #RECV_T
        sta recv_t,y
        jsr off_mark
        jmp kick_to
:       ldx ctrl                ; no one: straight on, 2048 - far enough
        ldy o_dir,x             ; to leave the kicker behind (Luca; the C64
        jsr ball_ahead          ; and Sensible Soccer 1792)
        jsr aim_to
        lda #<2048
        sta o_spl + BALL
        lda #>2048
        sta o_sph + BALL
        jmp kicked

;
; offering: a frame of the joystick's throw-in, goal kick or keeper's ball,
; player X its taker - Luca's: looking the same way OFFER_T frames, the
; team-mate that way (as pass would choose him, its cone half as wide
; first) comes to 62 pixels from the ball (spot: offer_x, offer_y) and stays; a
; tap passes to him (pass). Looking another way, he goes back to his
; place, and the next comes after OFFER_T more. Keeps X.
offering:
        lda rs_kind
        cmp #R_THROW
        beq :+
        jsr keeper_kick
        bcs @no
:       jsr fine_on             ; (a throw-in: its aim's way)
        bcc :+
        lda o_dir,x
        asl a
        asl a
        asl a
        asl a
        asl a
:       ldy offer_t             ; (no_offer's $FF: the stick let go, none;
        iny                     ; pushed any way - the way he looks too -
        bne @cmp                ; a way anew, Luca: all three again)
        pha
        jsr joy_way
        pla
        bcc @new
        rts
@cmp:   cmp offer_w
        beq @same
@new:   sta offer_w
        lda #0
        sta offer_t
        lda #$FF
        sta offer
@no:    rts
@same:  lda offer_t
        cmp #OFFER_T
        bcs @no
        inc offer_t
        cmp #OFFER_T - 1
        bne @no
        txa
        pha
        lda offer_w
        sta kick_way
        lda #24
        sta p_w
        jsr pass_scan
        ldx mate
        bpl :+
        asl p_w
        jsr pass_scan
        ldx mate
        bmi @none
:       stx offer
        lda offer_w             ; his place: OFFER_D the way from the ball
        jsr sin_d
        ldy #0
        jsr ball_add
        sta offer_x
        sty offer_x + 1
        lda offer_w
        clc
        adc #64
        jsr sin_d
        eor #$FF                ; (y: - cos)
        clc
        adc #1
        ldy #o_yl - o_xl
        jsr ball_add
        sta offer_y
        sty offer_y + 1
@none:  pla
        tax
        rts

; no_offer: carry set if the stick points back at the joystick's
; throw-in - out of the pitch: left on the left line, right on the right
; - or at its goal kick or keeper's ball - at its own goal: the team-mate
; offered (offering) goes back to his place and no one comes till the
; stick is pushed again, any way - the way the keeper still looks too
; (Luca: it came only for the other two); the aim stays (Luca: a way to
; have no one offered). Not the computer's: its brain turns its taker
; with a stick of its own (br_stick), out of the pitch too. Keeps X.
no_offer:
        jsr cpu_side
        bcs @no
        lda pj
        and #$0F
        tay
        lda joy_dir,y           ; (0-7, 8 let go)
        sta tmp
        lda rs_kind
        cmp #R_THROW
        bne @keeper
        ldy #6                  ; (the left line: left)
        lda o_xh + BALL
        beq @cmp
        ldy #2
        bne @cmp
@keeper:
        jsr keeper_kick
        bcs @no
        ldy #4                  ; (attacking up: down)
        lda rs_team
        eor flip
        beq @cmp
        ldy #0
@cmp:   cpy tmp
        bne @no
        lda #$FF
        sta offer
        sta offer_t             ; (none till the stick is pushed: offering)
        sec
        rts
@no:    clc
        rts

; ball_add: A, Y = the ball's x (Y 0) or y (Y o_yl - o_xl) + A, signed
ball_add:
        sta tmp
        clc
        adc o_xl + BALL,y
        pha
        lda tmp
        and #$80
        beq :+
        lda #$FF
:       adc o_xh + BALL,y
        tay
        pla
        rts

; sin_d: A = 62 * sin of way A (0 up, 64 right), signed: sin4's / 16
sin_d:
        jsr sin4
        ldy #4
:       lda tmp + 1
        cmp #$80
        ror tmp + 1
        ror tmp
        dey
        bne :-
        lda tmp
        rts

; keeper_kick: carry clear if the joystick's team takes a goal kick or the
; keeper's ball. Keeps X.
keeper_kick:
        lda kickoff
        beq @no
        lda rs_kind
        cmp #R_GOALKICK
        beq @yes
        cmp #R_KEEPER
        beq @yes
@no:    sec
        rts
@yes:   clc
        rts

; pass_scan: mate = the team-mate pass kicks to - kick_way, p_w - $FF none
pass_scan:
        lda #$FF
        sta mate
        sta mate_d
        sta mate_d + 1
        ldx t_hi
@look:  cpx ctrl
        beq @next
        jsr mate_way            ; the way from the ball to him, 0-255
        bcs @next               ; (on the ball)
        sec
        sbc kick_way            ; within p_w of the way he kicks
        clc
        adc p_w
        sta z_off
        lda p_w
        asl a
        cmp z_off
        bcc @next
        lda z_off               ; (within 16: under 33)
        sec
        sbc p_w
        clc
        adc #16
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
:       jsr closer
@next:  dex
        cpx t_end
        bne @look
        rts

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
        ; as hard as he is far, as the C64's L4383 has it: a step each 50
        ; pixels (pass_d; mate_d may be doubled: his own distance), and
        ; harder the better the kicker (pass_b, by sk_duel: $3E98)
        jsr mate_dist
        ldy #0
@far:   lda tmp
        cmp pass_dl,y
        lda tmp + 1
        sbc pass_dh,y
        bcc @hard
        iny
        cpy #5
        bcc @far
@hard:  lda pass_lo,y
        sta o_spl + BALL
        lda pass_hi,y
        sta o_sph + BALL
        ldy kick_pl
        lda sk_duel,y
        tay
        lda pass_bl - 7,y
        clc
        adc o_spl + BALL
        sta o_spl + BALL
        lda pass_bh - 7,y
        adc o_sph + BALL
        sta o_sph + BALL
kicked: ; (on the ground - a throw-in's from his head: at_throw)
        lda #0
        sta o_zf + BALL
        sta o_dzf + BALL
        tay
        jsr at_throw
        sta o_zl + BALL
        sty o_dzl + BALL
        lda #$FF
        jmp sfx_kick

; at_throw: a throw-in being taken: A = 12, the ball's height as it leaves
; his hands, Y = 1, a pass's rise (8.8), as the C64 throws it; else A = 0
; (Z set), Y kept
at_throw:
        lda kickoff
        beq @no
        lda rs_kind
        cmp #R_THROW
        bne @no
        lda #12
        ldy #1
        rts
@no:    lda #0
        rts

; the aftertouch: the bend for each way of the shot and side, a step
; (times the frame's weight); the speeds of a lift, high and less high
curl_x:     .byte <(-32), 32, 0, 23, 0, 0, 23, 0, 32, <(-32), 0, <(-23), 0, 0, <(-23), 0
curl_y:     .byte 0, 0, <(-23), 0, <(-32), 32, 0, 23, 0, 0, 23, 0, 32, <(-32), 0, <(-23)
at_w:       .byte 5, 4, 3, 2, 2, 2, 2, 1, 1, 1
lift_lo:    .byte <2688, <2560
lift_hi:    .byte >2688, >2560
; a pass's speed by its length ($3EC8/$3ED0: under 50 pixels, 100, .. 250,
; more - squared, pass_d*), and more by the kicker's skill ($3E98/$3EA0)
pass_lo:    .byte <1536, <1664, <1792, <1877, <1962, <2048
pass_hi:    .byte >1536, >1664, >1792, >1877, >1962, >2048
pass_dl:    .byte <2496, <10000, <22496, <40000, <62496
pass_dh:    .byte >2496, >10000, >22496, >40000, >62496
pass_bl:    .byte <0, <48, <96, <144, <192, <256, <320, <384, <384
pass_bh:    .byte >0, >48, >96, >144, >192, >256, >320, >384, >384

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
        jsr ball_dx             ; |x - the ball's x|, under 256
        bcs @far
        lda sq8_lo,y
        sta mate_t
        lda sq8_hi,y
        sta mate_t + 1
        jsr ball_dy             ; |y - the ball's y|
        bcs @far
        jsr sq_add
        bcs @far
        rts
@far:   lda #$FF
        sta tmp
        sta tmp + 1
        rts

; ball_dx: Y = |player X's x - the ball's|, carry clear - set if 256 or
; more; ball_dy: the same of y. Keeps X.
ball_dy:
        lda o_yl,x
        sec
        sbc o_yl + BALL
        tay
        lda o_yh,x
        sbc o_yh + BALL
        jmp bd_hi
ball_dx:
        lda o_xl,x
        sec
        sbc o_xl + BALL
        tay
        lda o_xh,x
        sbc o_xh + BALL
bd_hi:  beq @near
        cmp #$FF
        bne @far
        tya                     ; (less: negated, the carry set)
        eor #$FF
        adc #0
        beq @far                ; (256)
        tay
@near:  clc
        rts
@far:   sec
        rts

; dist_y: tmp = the distance squared from the ball to player Y, as
; mate_dist has it. Keeps X, Y.
dist_y:
        stx hd_x
        sty hd_y
        tya
        tax
        jsr mate_dist
        ldx hd_x
        ldy hd_y
        rts

; closer: player X mate, tmp his distance mate_d, if it is less than
; mate_d. Keeps X.
closer:
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
:       rts

; adx, ady: |player X's x - the ball's|, |y - y|, as abs16 has it. Keeps X.
adx:    lda o_xl,x
        sec
        sbc o_xl + BALL
        sta tmp
        lda o_xh,x
        sbc o_xh + BALL
        jmp abs16
ady:    lda o_yl,x
        sec
        sbc o_yl + BALL
        sta tmp
        lda o_yh,x
        sbc o_yh + BALL
        ; (on to abs16)

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
        step_in
        arrive_in
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
        jeq @height
        jsr aim
        ldx #BALL
        ; friction: 16 on the ground, 10 in the air
        lda #16
        ldy o_zl,x
        beq :+
        lda #10
:       jsr slow
        step_in
        ; turning: a picture on every 16 pixels it rolls (a frame goes
        ; speed / 512 of them) - no more than one a picture till a speed
        ; of 3584, no picture skipped
        lda o_sph,x
        asl a
        asl a
        asl a
        adc o_run,x             ; (carry clear: the speed under 8192)
        sta o_run,x
        bcc @height
        inc o_step,x
@height:
        ldx #BALL
        lda o_dzf,x
        ora o_dzl,x
        bne :+
        lda o_zl,x              ; (no step but up in the air: it falls - a
        bne :+                  ; step of exactly 0, gravity's $12 a frame
        jmp @walls              ; against the charge's $20 two, held it
                                ; at one height till touched: Luca)
                                ; lying, or rolling
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
        ldy #2                  ; speed - speed / 4
        jsr sp_cut
        lda #0
        sta o_zl,x
        sta o_zf,x
        sec                     ; dz = -dz
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

; smul_in: z_p (24 bits, signed) = A (signed) * smul_l/h; the step is its
; upper two bytes. Two products of bytes from tables of squares / 4 (a * b
; = (a + b)^2 / 4 - (a - b)^2 / 4). Keeps X. In line: aim's, twice.
.macro smul_in
        sta z_ms
        bpl :+
        eor #$FF
        clc
        adc #1
:       sta z_qp                ; (mul_set and mul_by, in line)
        sta z_qph
        eor #$FF
        sta z_qn
        sta z_qnh
        ldy smul_l              ; |A| * the low byte (0: none - many a
        bne :+                  ; speed has none)
        sty z_p
        sty z_p + 1
        beq :++
:       lda (z_qp),y
        sec
        sbc (z_qn),y
        sta z_p
        lda (z_qph),y
        sbc (z_qnh),y
        sta z_p + 1
:       ldy smul_h              ; and the high byte, 8 bits up
        lda (z_qp),y
        sec
        sbc (z_qn),y
        sta z_q
        lda (z_qph),y
        sbc (z_qnh),y
        sta z_p + 2
        lda z_q
        clc
        adc z_p + 1
        sta z_p + 1
        bcc :+
        inc z_p + 2
:       lda z_ms
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
:
.endmacro

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
        lda z_ax                ; the way to the destination remembered
        sta c_axl,x             ; (in line: nearly every new way)
        lda z_ax + 1
        sta c_axh,x
        lda z_ay
        sta c_ayl,x
        lda z_ay + 1
        sta c_ayh,x
@same:  lda o_spl,x             ; the angle and the speed as last time:
        cmp c_spl,x             ; the step as it is
        bne @step
        lda o_sph,x
        cmp c_sph,x
        bne @step
        rts
@new:
        lda z_ax                ; the way to the destination remembered
        sta c_axl,x             ; (in line: nearly every new way)
        lda z_ax + 1
        sta c_axh,x
        lda z_ay
        sta c_ayl,x
        lda z_ay + 1
        sta c_ayh,x
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
        jsr still
        sta c_spl,x             ; (a speed of 0 noted: anew next time)
        sta c_sph,x
        rts
:       lda z_th                ; ($FF notes "there": an angle of 255 goes
        cmp #$FF                ; as 0 - else the step from before stays,
        adc #0                  ; and arrive puts him at the destination)
        sta c_th,x
        jsr dir_th              ; the way it faces
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
        smul_in
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
        smul_in
        lda z_p + 1
        sta o_vyf,x
        lda z_p + 2
        sta o_vyl,x
        cpx #BALL
        beq :+
        jmp triple

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
        lda z_ax + 1            ; then under 32: one of them 256-1023, at
        ora z_ay + 1            ; once - four halvings (1 the high bytes
        beq @lo                 ; together) or five (2, 3), shifted and
        cmp #4                  ; joined (z_th free till the end)
        bcs @half
        cmp #2
        bcs @five
        lda z_ax + 1
        asl a
        asl a
        asl a
        asl a
        sta z_th
        lda z_ax
        lsr a
        lsr a
        lsr a
        lsr a
        ora z_th
        sta z_ax
        lda z_ay + 1
        asl a
        asl a
        asl a
        asl a
        sta z_th
        lda z_ay
        lsr a
        lsr a
        lsr a
        lsr a
        jmp @join
@five:  lda z_ax + 1
        asl a
        asl a
        asl a
        sta z_th
        lda z_ax
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        ora z_th
        sta z_ax
        lda z_ay + 1
        asl a
        asl a
        asl a
        sta z_th
        lda z_ay
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
@join:  ora z_th
        sta z_ay
        lda #0
        sta z_ax + 1
        sta z_ay + 1
        jmp @look
@half:
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
@look:  lda z_ax                ; the larger as ax (ay the larger: swapped,
        cmp z_ay                ; and the angle 64 less)
        lda #0
        bcs :+
        lda z_ax
        ldy z_ay
        sta z_ay
        sty z_ax
        lda #$80
:       sta z_sw
        lda z_ax                ; (both 0: none)
        beq @none
@up:    cmp #16                 ; both doubled till the larger is 16-31 (the
        bcs :+                  ; angle the same: it goes by the ratio)
        asl z_ay
        asl a
        bcc @up
:       sbc #16                 ; atan_tab[(ax - 16) * 32 + ay]: its page
        asl a                   ; from bit 3 of ax - 16, out into the carry
        asl a                   ; by the fifth shift (the table on a page
        asl a                   ; of its own: TABLES)
        asl a
        asl a
        ora z_ay
        tay
        bcs :+
        lda atan_tab,y
        bcc :++
:       lda atan_tab + 256,y
:       bit z_sw
        bpl :+
        eor #$FF                ; (64 - it)
        clc
        adc #65
:       sta z_th
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
; goal line. He runs there as fast as his team goes (pace) and stands.
; Each gets his place worked out anew every 11th frame, as Sensible
; Soccer's - once a picture, one of each team for each of its frames; a
; place hardly away from the last is not a new one. The other team sends the
; player nearest the ball after it; with it at his feet he takes it
; towards the goal and shoots from close to it. Before a kick-off no
; one moves.

; team_ai: once a picture; carry clear if the teams' runners are to be
; worked out too (help)
team_ai:
        lda kickoff
        beq @play
        lda o_spl + BALL        ; the ball moving: the set piece taken
        ora o_sph + BALL
        beq :+
        lda #0
        sta kickoff
        sta why                 ; (the whistle's reason no longer shown,
        lda #$FF                ; nor its card)
        sta card_pl
        sta taker
        bne @play
:       jsr cpu_take            ; (the yellow team's, after a while)
        lda rs_kind             ; a kick-off: everyone stays in line
        bne @play
        sec
        rts
@play:  lda form_i              ; one of each team's eleven a frame in turn,
        clc                     ; so each anew every 11 frames, as Sensible
        adc pic_n               ; Soccer's (c144d2)
        cmp #11
        bcc :+
        sbc #11
:       sta form_i
        tax
        lda pic_n
        asl a
        sta form_n
@pl:    txa                     ; (the keepers: keeper)
        beq @next
        cpx #11
        beq @next
        lda full                ; (full time: the joysticks' too, to the
        bne @all                ; middle - spot)
        cpx ctrl
        beq @next
        cpx ctrl_b
        bne :+
        lda kickoff             ; (the computer's at a set piece: to his
        beq @next               ; place as the rest - set_wall alone put
        lda two                 ; him WALL_D off, in front of the wall
        beq @all                ; as it was, Luca saw)
        bne @next
:
        cpx helper
        beq @next
        cpx helper_b
        beq @next
@all:   lda o_off,x             ; (one lying stays down, one walking off -
        and #2                  ; 2, training's absent 3 - away; one sent
        ora o_slide,x           ; off goes on unseen, so ft_spot counts him
        bne @next               ; at full time: full stuck at 2, Luca saw)
        cpx taker
        bne :+
        lda full
        beq @next
:       jsr place_formation     ; (a set piece: the other team's off its
                                ; way - keep_off)
@next:  cpx #11                 ; (his and the other team's, then the next
        bcs :+                  ; one's)
        txa
        adc #11
        bne @more
:       txa
        sbc #10
        cmp #11
        bcc @more
        lda #0
@more:  tax
        dec form_n
        bne @pl
        ldx #0                  ; the keepers (every second frame in
        jsr keeper              ; Sensible Soccer)
        ldx #11
        jsr keeper
        lda full                ; (the runners: help, play_picture - not
        cmp #1                  ; after full time: no one runs to it)
        rts

; place_formation: player X's destination, his place in the formation for
; where the ball is; jogging. Keeps X.
place_formation:
        stx z_obj
        txa                     ; the team's formation: its own of tac_*
        ldy #0                  ; (the title's choice)
        cpx #11
        bcc :+
        iny
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
        ldy z_t8                ; z_m * it (mul8, in line)
        lda z_m
        sta z_qp
        sta z_qph
        eor #$FF
        sta z_qn
        sta z_qnh
        lda (z_qp),y
        cmp (z_qn),y            ; (the low byte's borrow)
        lda (z_qph),y
        sbc (z_qnh),y
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
        ldy z_ti                ; (the multiplying took Y)
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
        ldy z_t8                ; (mul8, in line)
        lda z_m
        sta z_qp
        sta z_qph
        eor #$FF
        sta z_qn
        sta z_qnh
        lda (z_qp),y
        cmp (z_qn),y
        lda (z_qph),y
        sbc (z_qnh),y
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
        jsr spot                ; a set piece waiting: Sensible Soccer's
        bcc :+                  ; place for him, else his formation's out
        jsr keep_off            ; of its way
:
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
        jsr pace                ; as fast as his team goes there
        lda #1
        sta o_mov,x
        sta o_new,x
@keep:  rts

; keep_off: player X's new place (z_px, z_py) out of the way of the
; other team's set piece, while it is dead or waits, where Sensible
; Soccer has no place of its own for him (spot: a throw-in, a free kick
; away from the goal, some of its shirts): WALL_D from where it is taken
; (as set_wall puts those already there), on its side. His own team's
; as their formation has them. Keeps X.
keep_off:
        lda dead_t
        ora kickoff
        beq @done
        lda rs_kind             ; (not a kick-off: line_up; nor a penalty:
        beq @done               ; spot)
        cmp #R_PENALTY
        beq @done
        jsr team_y
        cpy rs_team
        beq @done
        jsr rs_side
        lda #WALL_D             ; within WALL_D of it both ways: WALL_D
        sta z_t8                ; off it on the side
        lda z_px
        sec
        sbc rs_x
        tay
        lda z_px + 1
        sbc rs_x + 1
        jsr within
        bcs @done
        lda z_py
        sec
        sbc rs_y
        tay
        lda z_py + 1
        sbc rs_y + 1
        jsr within
        bcs @done
        ldy r_s
        lda rs_y
        clc
        adc wall_dl,y
        sta z_py
        lda rs_y + 1
        adc wall_dh,y
        sta z_py + 1
@done:  rts

wall_dl:    .byte <(-WALL_D), <WALL_D
wall_dh:    .byte >(-WALL_D), >WALL_D

; ft_spot: spot's at full time - STAND_T frames where they are (Luca:
; the teams stand first, cheering or not), then everyone off the pitch,
; into the tunnel between the benches, TUN_X, TUN_Y (Luca:
; the teams gone, the score in the middle): in its mouth he is gone (o_off
; 1), full one less - none left: full 1. Carry clear, z_px, z_py; set for
; one gone. Keeps X.
TUN_M       = 72 * 8 + 23       ; (the tunnel's mouth: mkdata TUNNEL_COL, simple-soccer.s GROUND_X)
TUN_IN      = TUN_M + 4         ; (gone there - his shirt in the white
TUN_X       = TUN_IN            ; column before the benches' colours: no
                                ; further, team_ai sees him there only
                                ; every 11 frames - he went on into the
                                ; coach's red)
WALK_X      = TUN_M
WALK_FROM   = WALK_X + 230      ; (coming on: back in the tunnel, not drawn
                                ; - simple-soccer.s place - till the view
                                ; has got there from the middle spot, Luca)
TUN_Y       = 369 + 7           ; (his feet: him in the middle of its mouth,
                                ; as the tunnel on the halfway line - mkdata)
WALK_OUT    = 512               ; (coming on: along TUN_Y till here, then
                                ; to his place - walking; a whole high
                                ; byte, beyond every place line_up has)
STAND_T     = 100               ; (new_match: and fire not before)
ft_spot:
        lda o_off,x             ; (gone already: a keeper asks each frame)
        bne @off
        lda min_t
        cmp #STAND_T
        bcs @walk
        lda o_xl,x              ; (standing: his place where he is)
        sta z_px
        lda o_xh,x
        sta z_px + 1
        lda o_yl,x
        sta z_py
        lda o_yh,x
        sta z_py + 1
        clc
        rts
@walk:  lda o_xl,x
        cmp #<TUN_IN
        lda o_xh,x
        sbc #>TUN_IN
        bcc @on                 ; (there: no need to stop him - A 0 on)
@off:   bmi @gone               ; gone: counted once, o_off $81 - one sent
        lda #$81                ; off before (1) as well: full stuck at 2,
        sta o_off,x             ; the view on the benches, no score in the
        dec full                ; middle, Luca saw after a red card
@gone:  sec
        rts
@on:    lda #<TUN_X
        sta z_px
        lda #>TUN_X
        sta z_px + 1
        lda #<TUN_Y
        sta z_py
        lda #>TUN_Y
        sta z_py + 1
        clc
        rts

; spot: player X's place while a set piece waits - Sensible Soccer's for
; each kind of set piece (sp_kind) and shirt, the team taking it's and
; the other's (sp_*: in a team's own frame, its goal at the top: x / 2
; and y / 3 from 54, 49; the team at the bottom's turned about - or, its
; bit in the mask, off the ball as far as the two bytes say): carry clear,
; z_px, z_py; carry set none - his formation's then. Keeps X.
spot:
        lda full                ; (full time: ft_spot)
        bne ft_spot
@play:  cpx offer               ; (the team-mate offering himself: offering's
        bne :+                  ; place for him)
        lda kickoff
        beq :+
        lda offer_x
        sta z_px
        lda offer_x + 1
        sta z_px + 1
        lda offer_y
        sta z_py
        lda offer_y + 1
        sta z_py + 1
        clc
        rts
:       lda dead_t
        ora kickoff
        beq @no
        jsr sp_kind
        bcc :+
@no:    sec
        rts
:       sta tmp
        jsr team_y              ; (the other team's: 21 on)
        cpy rs_team
        beq :+
        clc
        adc #21
        sta tmp
:       ldy tmp
        lda sp_hi,y
        beq @none
        sta z_ptr + 1
        lda sp_lo,y
        sta z_ptr
        txa                     ; his shirt's, 2 + 2 * (X mod 11) on
        cpx #11
        bcc :+
        sbc #11
:       sta tmp
        asl a
        adc #2
        tay
        lda (z_ptr),y
        sta z_ax
        iny
        and (z_ptr),y           ; ($FF, $FF: none)
        cmp #$FF
        beq @none
        lda (z_ptr),y
        sta z_ay
        ldy #0                  ; his bit of the mask: off the ball?
        lda tmp
        cmp #8
        bcc :+
        iny
        sbc #8
:       sta tmp + 1
        lda (z_ptr),y
        ldy tmp + 1
        iny
:       lsr a
        dey
        bne :-
        bcs @ball
        lda #0                  ; x * 2, y * 3
        sta z_ax + 1
        sta z_ay + 1
        asl z_ax
        rol z_ax + 1
        lda z_ay
        asl a
        rol z_ay + 1
        adc z_ay
        sta z_ay
        bcc :+
        inc z_ay + 1
:       jsr sp_top
        beq @turn
        lda z_ax                ; the team at the top: from 54, 49
        clc
        adc #54
        sta z_px
        lda z_ax + 1
        adc #0
        sta z_px + 1
        lda z_ay
        clc
        adc #49
        sta z_py
        lda z_ay + 1
        adc #0
        sta z_py + 1
        clc
        rts
@none:  sec
        rts
@turn:  lda #<553               ; the team at the bottom: 553 - x, 689 - y
        sec
        sbc z_ax
        sta z_px
        lda #>553
        sbc z_ax + 1
        sta z_px + 1
        lda #<689
        sec
        sbc z_ay
        sta z_py
        lda #>689
        sbc z_ay + 1
        sta z_py + 1
        clc
        rts
@ball:  jsr sp_top              ; off the ball (turned about at the bottom)
        bne :+
        lda #0
        sec
        sbc z_ax
        sta z_ax
        lda #0
        sec
        sbc z_ay
        sta z_ay
:       lda z_ax
        ldy #0
        jsr sp_add
        sta z_px
        sty z_px + 1
        lda z_ay
        ldy #rs_y - rs_x
        jsr sp_add
        sta z_py
        sty z_py + 1
        clc
        rts

; sp_add: A, Y = rs_x (Y 0) or rs_y (Y 2) + A (signed). Keeps X.
sp_add:
        sta tmp
        clc
        adc rs_x,y
        pha
        lda tmp
        and #$80
        beq :+
        lda #$FF
:       adc rs_x + 1,y
        tay
        pla
        rts

; sp_top: Z clear if player X's team has its goal at the top. Keeps X.
sp_top:
        jsr team_y
        tya
        eor flip
        rts

; sp_kind: A = the kind of the set piece waiting, carry clear - as
; Sensible Soccer has them, by its place for the team taking it (its own
; frame: its goal at the top, its right as it looks down): a goal kick
; its right 1, its left 2; the keeper's ball 3; a corner its right 4,
; its left 5; a free kick in the band before the goal it attacks 6 - 12
; by the column from its right (x 121, 229, 277, 330, 378, 486), a
; penalty 14; a throw-in on its right 15 - 17, on its left 18 - 20, by
; the band from its goal (y 262, 476). Carry set none: a kick-off
; (line_up), a free kick elsewhere. Keeps X.
sp_kind:
        lda rs_team
        eor flip
        sta tmp + 1             ; (1: the taker's goal at the top)
        lda rs_x
        cmp #<304
        lda rs_x + 1
        sbc #>304
        lda #0
        rol a                   ; (1: the right half)
        eor tmp + 1
        eor #1
        sta tmp                 ; (1: its right)
        ldy rs_kind
        cpy #R_GOALKICK
        bne :+
        lda #2
        bne @side
:       cpy #R_CORNER
        bne :+
        lda #5
@side:  sec
        sbc tmp
        clc
        rts
:       cpy #R_KEEPER
        bne :+
        lda #3
        clc
        rts
:       cpy #R_PENALTY
        bne :+
        lda #14
        clc
        rts
:       cpy #R_THROW
        bne @free
        ldy #0                  ; the band (y 262, 476)
        jsr sp_ge
        lda #0
        adc #0
        sta z_ax
        ldy #1
        jsr sp_ge
        lda z_ax
        adc #0                  ; (0 - 2 from the top)
        ldy tmp + 1
        bne :+
        eor #$FF                ; (the taker's goal at the bottom: 2 - it)
        sec
        adc #2
:       clc
        adc #18
        ldy tmp
        beq :+
        sbc #3 - 1              ; (its right: 15 on - the carry clear)
:       clc
        rts
@free:  cpy #R_FREE
        bne @none
        ldy #2                  ; the band before the goal attacked: y
        lda tmp + 1             ; 136 - 250 attacking up, 487 - 602 down
        beq :+
        ldy #4
:       jsr sp_ge
        bcc @none
        iny
        jsr sp_ge
        bcs @none
        ldy #0                  ; the column from the left
:       lda rs_x
        cmp fk_xl,y
        lda rs_x + 1
        sbc fk_xh,y
        bcc :+
        iny
        cpy #6
        bne :-
:       tya
        ldy tmp + 1             ; from its right: 12 less it attacking
        beq :+                  ; down, 6 on attacking up
        eor #$FF
        sec
        adc #12
        clc
        rts
:       clc
        adc #6
        rts
@none:  sec
        rts

; sp_ge: carry set if rs_y is sp_y* Y or more. Keeps X, Y.
sp_ge:
        lda rs_y
        cmp sp_yl,y
        lda rs_y + 1
        sbc sp_yh,y
        rts

; pace: player X's speed to his new place: his team's (jog_*: Sensible
; Soccer's for it, c144dc). Keeps X.
pace:
        jsr team_y
        lda jog_lo,y
        sta o_spl,x
        lda jog_hi,y
        sta o_sph,x
        rts

; team_y: Y = player X's team, 0 cyan, 1 yellow. Keeps A, X.
team_y:
        ldy #0
        cpx #11
        bcc :+
        iny
:       rts

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

form22: .byte 0, 22             ; (each team's in tac_*)

; ---- whose the joystick is ------------------------------------------------

; take: every frame (play_frame) and in switch - the helper running to
; the ball gets it as he is at it (at_ball - Sensible Soccer's runner,
; c14314), the joystick his, his first touch (trap) - unless the other
; team holds it (on the C64 only the joystick's players fight for it:
; duel); not just after losing it so. Carry set if he did. Once a picture
; only, as switch had it, a pass and its receiver running to meet it
; passed each other between two looks (some 18 pixels a picture against
; the 5.6 of at_ball) - the kick-off's pass never got there (Luca).
take:
        lda kickoff
        ora dead_t
        bne @no
        ldx helper
        bmi @no
        beq @no                 ; (a keeper: his hands, catch's - a pass
        cpx #11                 ; back to him too)
        beq @no
        cpx recv                ; (a pass to him: not locked - a set
        beq :+                  ; piece's lock, DBL_T, let the kick-off
        ldy me                  ; run past its receiver beside the taker)
        lda lock_t,y
        bne @no
:       jsr near_x              ; (near across first, the rest only then)
        bcs @no
        lda #TRAP_Z + 1
        sta near_z
        lda #NEAR + 1           ; (a pass's receiver as near as the
        cpx recv                ; joystick's, CLOSE: at NEAR a pass going
        bne @at                 ; by him six pixels off ran past him -
        ldy thrower             ; Luca: the passes work fifty-fifty; a
        cpy last_pl             ; throw-in's, untouched, as high as his
        bne :+                  ; head - chest or head, it flew over him
        ldy #HEAD_HI + 1        ; at 18 to the other team, and he may not
        sty near_z              ; head it on: head)
:       lda #CLOSE + 1
@at:    jsr at_ball_d
        bcc @no
        lda me
        jsr held
        bcs @no
        stx ctrl
        lda #$FF
        sta helper
        jsr trap
        sec
        rts
@no:    clc
        rts

; head: a header, every frame (play_frame) for each team - neither
; original has any but the diving one (Luca missed them): the ball HEAD_LO
; to HEAD_HI high within HEAD_D2 of the team's joystick's player with fire
; pressed (not a keeper, not sliding, not jumping still, not the one who
; just kicked it): he jumps (HEAD_T) and heads it on, the way the stick
; points, let go on towards the goal his team attacks. Fire and the stick
; for a ball in the air is the diving header still: harder, further. The
; computer heads none, as Sensible Soccer's (its header's fire, c1539c, is
; dead code): it takes a high ball with the foot, up to 12 high. (The
; headers of themselves, the joystick's team's runner's too, met every
; ball going by, a team-mate's shot as well, the way he faced: own goals
; like rain, said Luca; the computer's on the other team's balls took
; every shot and long pass at head height, to its keeper too - a header
; now only when asked for.)
head:
        lda kickoff
        ora dead_t
        bne @no
        lda o_zl + BALL
        cmp #HEAD_LO
        bcc @no
        cmp #HEAD_HI + 1
        bcs @no
        ldy me
        lda lock_t,y
        bne @no
        cpy last_team           ; (its own throw-in, untouched since: not
        bne :+                  ; headed of itself - a double shot, said
        lda last_pl             ; Luca: thrown to him at head height, he
        cmp thrower             ; headed it on)
        beq @no
:       ldx ctrl
        bmi @no
        jsr cpu_side            ; (the computer's: only its own team's
        bcc :+                  ; ball, a cross, a pass in the air - Luca
        lda last_pl             ; saw too few headers; once it headed the
        cmp #12                 ; other team's too, every shot at head
        bcs @can                ; height and long pass, back to its keeper
        rts                     ; too. Not its keeper's, 11: Luca saw every
                                ; goal kick met by a team-mate's head)
:       lda pj                  ; (the joystick's: with fire only - or in
        and #J_FIRE             ; the air already, jumped for it: can_try;
        beq :+                  ; not fire held on since a kick, $80 on:
        lda fire_n              ; Luca's goal kick lofted, fire held, the
        bpl :++                 ; team-mate it flew over got the joystick
:       lda o_zl,x              ; and headed it back, the stick's way)
        beq @no
:
@can:   jsr can_head
        bcc @go
@no:    rts
@go:    lda #HEAD_T
        sta o_zl,x
        sta jumps
        lda me
        sta last_team
        jsr touch_x
        jsr cpu_side            ; (the computer's: always up the pitch,
        lda #8                  ; never the way he ran to it - the stick
        bcs :+                  ; brain made: Luca saw a goal kick headed
        jsr stick_way           ; back, out for a corner)
:       cmp #8
        bne @way
        jsr top_of              ; (from the top: down the pitch)
        beq @way
        lda #4
@way:   sta o_dir,x
        tay
        jsr ball_ahead
        lda #<HEAD_SPEED
        sta o_spl + BALL
        lda #>HEAD_SPEED
        sta o_sph + BALL
        lda #<DHEAD_DZ
        sta o_dzf + BALL
        lda #>DHEAD_DZ
        sta o_dzl + BALL
        jmp sfx_kick

; cpu_side: carry set if the team playing (me) is the computer's - the
; yellow one, not two players. Keeps X, Y.
cpu_side:
        lda two
        bne :+
        lda me
        cmp #1
        rts
:       clc
        rts

; can_head: carry clear if player X may head the ball on now (head).
; Keeps X.
can_head:
        txa                     ; (no keeper: his hands)
        beq @no
        cpx #11
        beq @no
        lda o_slide,x
        bne @no
        lda o_zl,x              ; (in the air: a try's jump, not one he
        beq :+                  ; has headed it in already)
        cpx last_pl
        bne :+
        lda last_team
        cmp me
        beq @no
:       jsr kicker
        bcs @no
        jsr mate_dist
        lda tmp + 1
        bne @no
        lda tmp
        cmp #HEAD_D2 + 1
        rts
@no:    sec
        rts

; can_try: carry clear if the joystick's player X, fire just pressed,
; jumps for a header (control): the ball in the air - higher than a
; sliding tackle's (SLIDE_Z), however high - and near (DHEAD_D2, as
; a diving header's); not a keeper, nor one sliding or in the air, nor the
; one who has just kicked it. He is up HEAD_T frames, head heads it if it
; comes to his head meanwhile - else a try missed (Luca: more tries at
; headers, at corners too, missed ones as well). Keeps X.
can_try:
        jsr cpu_side            ; (the computer heads none: no tries)
        bcs @no
        txa
        beq @no
        cpx #11
        beq @no
        lda o_slide,x
        ora o_zl,x
        bne @no
        lda o_zl + BALL         ; (however high: he tries, by instinct -
        cmp #SLIDE_Z + 1        ; Luca; above 40 he slid for it)
        bcc @no
        jsr kicker
        bcs @no
        jsr mate_dist
        lda tmp
        cmp #<(DHEAD_D2 + 1)
        lda tmp + 1
        sbc #>(DHEAD_D2 + 1)
        rts
@no:    sec
        rts

; near_x: carry clear if player X is within 8 of the ball across (at_ball's
; at most 5; the low bytes enough: never a near one missed). Keeps X, Y.
near_x:
        lda o_xl,x
        sec
        sbc o_xl + BALL
        clc
        adc #8
        cmp #17
        rts

; switch, once a picture: as Sensible Soccer and the C64 do it: the
; helper running to the ball gets it as he is at it (at_ball - Sensible
; Soccer's runner, c14314), his first touch (trap); else the joystick's
; player keeps it while he has the ball at his feet, or it
; goes to the player nearest it - not the helper on his way to it, not
; the one who has just passed or shot, not the keeper
switch:
        lda kickoff             ; (a set piece waiting: his team's, the
        beq :+                  ; taker keeps it; the other team's, the
        rts                     ; one set_wall put off - the nearest, on
                                ; his way to his place, stood still
                                ; where the stick took him, in the wall's
                                ; way: Luca)
:       ldx ctrl                ; (nor from one sliding)
        lda o_slide,x
        beq :+
        rts
:       jsr take                ; (the helper at it: his)
        bcc :+
        rts
:       ldx ctrl                ; the joystick's at the ball: his still
        jsr near_ball
        jcs @done
        lda #$FF                ; else the nearest
        sta mate_d
        sta mate_d + 1
        sta mate
        ldx t_hi
@look:  cpx helper
        jeq @next
        cpx kick_pl             ; (kicker, mate_dist, closer: in line -
        bne :+                  ; given up once |dx| squared alone is no
        jsr kicker              ; nearer than the nearest so far)
        jcs @next
:       lda o_off,x
        bne @next
        lda o_xl,x
        sec
        sbc o_xl + BALL
        tay
        lda o_xh,x
        sbc o_xh + BALL
        beq @dx
        cmp #$FF
        bne @next
        tya
        eor #$FF
        adc #0
        beq @next
        tay
@dx:    lda sq8_lo,y
        sta mate_t
        cmp mate_d
        lda sq8_hi,y
        sta mate_t + 1
        sbc mate_d + 1
        bcs @next
        jsr ball_dy
        bcs @next
        jsr sq_add
        bcs @next
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
        jne @look
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

; kicker: carry set if player X of the joystick's team passed or shot
; KICKED_T frames ago or less, or took a set piece and may not touch the
; ball again yet (off_pl $FE, off_by him: double touch) - not his to run
; to, nor the joystick's. Keeps X, Y.
kicker:
        cpx kick_pl
        bne @no
        lda off_pl
        cmp #$FE
        bne :+
        cpx off_by
        beq @yes
:       lda me                  ; (the team's: Y kept)
        bne :+
        lda kick_t
        jmp @t
:       lda kick_t + 1
@t:     cmp #KICKED_T
        bcs @no
@yes:   sec
        rts
@no:    clc
        rts

; at_ball: carry set if cyan player X is at the ball as Sensible Soccer's
; runner takes it (c14314): at his feet (NEAR), on the ground (TRAP_Z) -
; and not the one who has just passed or shot (kicker). Keeps X.
at_ball:
        lda #TRAP_Z + 1
        sta near_z
        lda #NEAR + 1
at_ball_d:                      ; (A: so near, squared, + 1; near_z: so
        sta near_d              ; low, + 1)
        jsr kicker
        bcs at_no
        lda o_zl + BALL
        cmp near_z
        bcs at_no
        jsr mate_dist
        lda tmp + 1
        bne at_no
        lda tmp
        cmp near_d
        bcs at_no
        sec
        rts

; near_ball: carry set if cyan player X is at the ball, CLOSE, low.
; Keeps X.
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
; team_ai: once a picture.
help:
        lda kickoff
        ora dead_t
        bne :+
        ldy me                  ; (a pass to him on its way: he runs)
        lda recv_t,y
        beq @own
        lda recv
        cmp helper
        beq @run
@own:   lda #$FF                ; (his team's: no one; nor anyone's, a
        ldy two                 ; joystick's team - only its joystick's
        bne @held               ; player goes for it then, as on the C64)
        ldy me
        beq @held
        lda #0                  ; (the computer's: its own)
@held:  jsr held
        bcc @in
:       lda #$FF
        sta helper
        rts
@in:    lda frame_n             ; (anew each eighth frame: one in the
        and #7                  ; frames since the last picture)
        cmp pic_n
        bcs @run
        lda #$FF
        sta mate_d
        sta mate_d + 1
        sta mate
        ldx t_hi
@look:  cpx ctrl
        beq @next
        jsr mate_dist
        jsr closer
@next:  dex
        cpx t_lo
        bne @look
        lda mate
        sta helper
@run:   ldx helper
        bmi @out
        cpx ctrl                ; (the joystick has him now)
        beq @none
        lda o_slide,x           ; (sliding, down: slides has him)
        bne @out
        lda #1
        sta o_mov,x
        sta o_new,x             ; (the way to it worked out anew)
        ldy #SP_CHASE
        jsr to_ball
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
        lda score,y             ; a goal (99 at most: the HUD's two
        cmp #99                 ; figures)
        bcs :+
        adc #1
        sta score,y
:
        jsr sfx_goal
        lda #1
        sta goal
        tya
        eor #1
        sta rs_team
        jsr kick_spot
        lda #DEAD_GOAL
        bne @dead2
@wide:  jsr near_miss
        ldy #0                  ; the side it went out: x 0 left, 1 right
        lda o_xl,x
        cmp #<304
        lda o_xh,x
        sbc #>304
        bcc :+
        iny
:       lda last_team           ; (the other team's either way)
        eor #1
        sta rs_team
        lda #R_CORNER           ; the defenders': a corner
        sta rs_kind
        lda last_team
        cmp r_t
        bne :+
        dec rs_kind             ; the attackers': a goal kick (its
        iny                     ; places after the corners')
        iny
:       lda rs_xl,y
        sta rs_x
        lda rs_xh,y
        sta rs_x + 1
        tya
        and #2
        ora r_s
        tay
        lda rs_yl,y
        sta rs_y
        lda rs_yh,y
        sta rs_y + 1
@dead:  lda #DEAD_OUT
@dead2: sta dead_t
        jsr net                 ; (a goal: in the net already in this frame)
        jmp calm

rs_xl:      .byte <54, <553, <244, <364     ; corners left, right,
rs_xh:      .byte >54, >553, >244, >364     ; goal kicks left, right
rs_yl:      .byte <54, <684, <74, <664      ; top, bottom - corners',
rs_yh:      .byte >54, >684, >74, >664      ; goal kicks'
.assert R_GOALKICK = R_CORNER - 1, error, "the goal kick: dec rs_kind"

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
        lda #$FF                ; (no throw-in's or corner's aim yet)
        sta sp_aim
        ldx card_pl             ; a red card: off (the card shown till the
        bmi :+                  ; free kick is taken: team_ai)
        lda card_c
        beq :+
        jsr send_off
:       lda #$FF
        sta off_pl              ; (no one offside)
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
        jsr dir_th
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

; foul: player X has fouled the player on the ball - the whistle, the
; ball dead, him down, a free kick or penalty for his team. A card as
; Sensible Soccer gives it (c10fca): none for a penalty; a red if the
; one fouled was the last man, nearer the goal than all the fouler's
; team-mates but the keeper; else a yellow for ref_k fouls in 32 (the
; referee's, for the match: squad), a second yellow a red - he is off
; when play goes on (restart)
foul:
        lda #WHY_FOUL
        sta why
        lda #$FF
        sta card_pl
        stx lm_f
        lda last_team           ; (in_box's side: the one the fouled
        eor flip                ; player's team attacks)
        sta r_s
        ldx last_pl
        jsr in_box
        bcc @tally              ; (a penalty: no card)
        jsr last_man
        ldx lm_f
        lda #1                  ; (the last man: red)
        bcc @card
        jsr rnd
        and #31
        cmp ref_k
        bcs @tally
        lda fouls,x             ; (a yellow: 0, his second 2 - red,
        inc fouls,x             ; shown with the yellow: draw_card -
        asl a                   ; Luca: which red it was)
@card:  stx card_pl
        sta card_c
@tally: ldx last_pl
        lda #1                  ; down (slides lets him up when play goes on:
        sta o_slide,x           ; restart)
        sta sl_any
        lda #0
        sta o_hd,x
        jsr stand
free_at:                        ; (offside: a free kick where X is, for last_team)
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
        lda why                 ; (a foul's only: a double touch, offside
        cmp #WHY_FOUL           ; there on the box's line - the keeper
        beq @pen                ; touching his goal kick again gave the
        ldy r_s                 ; other team a penalty, Luca)
        lda box_yl,y
        sta rs_y
        lda box_yh,y
        sta rs_y + 1
        bne @free
@pen:   lda #R_PENALTY
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
@free:  lda #DEAD_FOUL
        sta dead_t
        lda why                 ; (a card: the crowd murmurs - a red
        cmp #WHY_FOUL           ; louder and longer, and it whistles:
        bne @wh                 ; Luca)
        lda card_pl
        bmi @wh
        lda card_c
        beq :+
        jsr sfx_red             ; (the referee's whistle its own)
        jmp calm
:       jsr sfx_yellow
@wh:    jsr sfx_whistle
        jmp calm

; near_miss: the ball X out over a goal line, no goal - fast and just
; wide or over the bar (NEAR_W pixels past a post at most): the crowd's
; "oh" (Luca). Keeps X.
near_miss:
        lda o_sph,x
        cmp #>MISS_SP
        bcc @no
        lda o_xl,x
        cmp #<(POST_L - NEAR_W)
        lda o_xh,x
        sbc #>(POST_L - NEAR_W)
        bcc @no
        lda #<(POST_R + NEAR_W)
        cmp o_xl,x
        lda #>(POST_R + NEAR_W)
        sbc o_xh,x
        bcc @no
        jmp sfx_miss
@no:    rts

box_yl:     .byte <BOX_T, <BOX_B    ; the box's line, a free kick on it
box_yh:     .byte >BOX_T, >BOX_B

;
; Offside, as the laws have it (Sensible Soccer and the C64 have none): a
; pass to a team-mate in the other team's half, nearer its goal line than
; the ball and than the other team's last but one at the moment it is
; played - not from a throw-in, a goal kick or a corner - and he the next
; to touch the ball: the whistle, a free kick for the other team where he
; is. Anyone else touching it first, or the ball dead, and it is over.
; The same for a set piece's taker touching it again before anyone else
; has (double touch: touch marks him).

; off_mark: the pass to player X (team me) - offside? Keeps X. (Its
; pieces: kick_way the side the team attacks - 0 up, $FF down - z_off
; the line, tmp the nearest two of the others to their line, mate_t
; counting; positions y / 4, up the more the nearer the goal attacked)
off_mark:
        lda off_pl              ; (a set piece's taker marked: kept)
        bmi :+
        lda #$FF
        sta off_pl
:
        lda kickoff             ; (a throw-in, goal kick, corner: never -
        beq :+                  ; a kick-off: no one is ahead)
        lda rs_kind
        cmp #R_KEEPER
        bcc @rts
:       lda me
        eor flip
        beq :+
        lda #$FF
:       sta kick_way
        ldy #BALL               ; the line: the ball, the half's,
        jsr off_y
        sta z_off
        lda #369 / 4
        eor kick_way
        jsr @less
        lda #$FF                ; and the other team's last but one
        sta tmp
        sta tmp + 1
        lda #11
        sta mate_t
        ldy #21
        lda me
        beq @opp
        ldy #10
@opp:   lda o_off,y
        bne @next
        jsr off_y
        cmp tmp
        bcs :+
        ldx tmp                 ; (the nearest so far now the second)
        stx tmp + 1
        sta tmp
        bcc @next
:       cmp tmp + 1
        bcs @next
        sta tmp + 1
@next:  dey
        dec mate_t
        bne @opp
        lda tmp + 1
        jsr @less
        ldx recv                ; he beyond it: offside
        txa
        tay
        jsr off_y
        cmp z_off
        bcs @rts
        stx off_pl
        lda ctrl
        sta off_by
@rts:   rts
@less:  cmp z_off               ; (the line: the nearer)
        bcs :+
        sta z_off
:       rts

; off_y: A = object Y's y / 4, upside down (kick_way $FF) for a team
; attacking down. Keeps X, Y (not mate_t + 1).
off_y:
        lda o_yh,y
        lsr a
        sta mate_t + 1
        lda o_yl,y
        ror a
        lsr mate_t + 1
        ror a
        eor kick_way
        rts

; off_chk: a frame of play - the receiver offside the next to touch the
; ball: the whistle; anyone else (but the passer): over
off_chk:
        ldx off_pl
        bmi @rts
        lda last_pl
        cmp off_by
        beq @rts
        ldy #$FF                ; over, either way
        sty off_pl
        cpx last_pl
        bne @rts
        lda #WHY_OFF            ; (off_by $FE: the taker's double touch)
        ldy off_by
        iny
        iny
        bne :+
        lda #WHY_TWICE
:       sta why
        ldy #0                  ; the free kick the other team's
        cpx #11
        bcs :+
        iny
:       sty last_team
        jmp free_at
@rts:   rts

; walk_off: player X shown a red card, off the team's play as send_off
; has him, but seen walking off over the nearer touch line in the dead
; time (o_off 2: drawn still; restart's send_off makes it 1, gone) -
; Luca: he wanted to see him go. Keeps X.

; send_off: player X off the pitch for good - not drawn, not in the
; team's play, never near the ball (mate_dist); the joystick, a run to
; the ball, a pass to him on to someone else
walk_off:
        lda #2
        jsr off_x
        ldy #6                  ; (the nearer touch line: left, right)
        lda o_xl,x
        cmp #<304
        lda o_xh,x
        sbc #>304
        bcc :+
        ldy #2
:       tya
        sta o_dir,x
        lda #<SPEED_JOG         ; (his running pictures: walking, not
        sta o_spl,x             ; others' play - o_mov 0)
        lda #>SPEED_JOG
        sta o_sph,x
        rts

; walking: the one walking off (card_pl, o_off 2) WALK_S a frame on to
; the touch line he makes for (o_dir 2 or 6: walk_off), a step of his
; running pictures every four frames; carry set while he is on his way
; (play_frame keeps the ball dead till he is off). Keeps nothing.
WALK_S      = 2
walking:
        lda enter               ; (coming on: the ball dead till all of
        beq @card               ; them stand at their places - walk_on -
        ldx #PLAYERS - 1        ; then the whistle)
@out:   lda o_xh,x              ; (past WALK_OUT: off the tunnel's row, to
        cmp #>WALK_OUT          ; his place - aim sees it changed; once
        bcs :+                  ; there, the same)
        lda wk_yl,x
        sta o_tyl,x
        lda wk_yh,x
        sta o_tyh,x
:       dex
        bpl @out
        ldx #PLAYERS - 1
:       lda o_mov,x
        bne @on
        dex
        bpl :-
        lda #0                  ; (all there: the kick-off at once, as
        sta enter               ; play_init set it up - its ball, taker,
        sta dead_t              ; joystick; not restart's, whose place is
        jsr line_up             ; the last set piece's - each in line, his
        jsr sfx_whistle         ; way for it)
@on:    sec
        rts
@card:  ldx card_pl
        bmi @off
        lda o_off,x
        cmp #2
        bne @off
        lda o_dir,x
        cmp #2
        bne @left
        lda o_xl,x
        clc
        adc #WALK_S
        sta o_xl,x
        bcc :+
        inc o_xh,x
:       lda o_xl,x              ; (beyond the touch line: off)
        cmp #<(LINE_R + 30)
        lda o_xh,x
        sbc #>(LINE_R + 30)
        bcs @off
        bcc @step
@left:  lda o_xl,x
        sec
        sbc #WALK_S
        sta o_xl,x
        bcs :+
        dec o_xh,x
:       lda o_xl,x
        cmp #<(LINE_L - 30)
        lda o_xh,x
        sbc #>(LINE_L - 30)
        bcc @off
@step:  lda o_xl,x              ; (his destination with him: no one
        sta o_txl,x             ; turns him back)
        lda o_xh,x
        sta o_txh,x
        dec o_run,x
        bpl :+
        lda #3
        sta o_run,x
        inc o_step,x
:       sec
        rts
@off:   clc
        rts

send_off:
        lda #1
off_x:  sta o_off,x
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

ref_tab:    .byte 4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 6, 7, 7, 8, 9, 10

; last_man: carry clear if player X, fouled by lm_f, is the last man -
; nearer the goal at side r_s than every one of lm_f's team-mates but
; the keeper and those sent off (by distance / 4, squared: gd6)
last_man:
        ldy r_s
        lda gl_l,y
        sta lm_g
        lda gl_h,y
        sta lm_g + 1
        jsr gd6
        lda tmp
        sta lm_v
        lda tmp + 1
        sta lm_v + 1
        ldx #1                  ; (the fouler's team-mates)
        lda lm_f
        cmp #11
        bcc @next
        ldx #12
@next:  cpx lm_f
        beq @skip
        lda o_off,x
        bne @skip
        jsr gd6
        lda lm_v                ; (as near or nearer: not the last man)
        cmp tmp
        lda lm_v + 1
        sbc tmp + 1
        bcs @no
@skip:  inx
        cpx #11
        beq @yes
        cpx #22
        bne @next
@yes:   clc
        rts
@no:    sec
        rts

; gd6: tmp = (the distance from player X to (304, lm_g) / 4) squared.
; Keeps X.
gd6:
        lda o_xl,x
        sec
        sbc #<304
        pha
        lda o_xh,x
        sbc #>304
        tay
        pla
        jsr quarter
        lda sq8_lo,y
        sta tmp
        lda sq8_hi,y
        sta tmp + 1
        lda o_yl,x
        sec
        sbc lm_g
        pha
        lda o_yh,x
        sbc lm_g + 1
        tay
        pla
        jsr quarter
        lda sq8_lo,y
        clc
        adc tmp
        sta tmp
        lda sq8_hi,y
        adc tmp + 1
        sta tmp + 1
        rts

gl_l:       .byte <49, <689     ; the goal lines' middles: top, bottom
gl_h:       .byte >49, >689

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

; set_wall: a set piece's players placed, the taker behind the ball
; already (restart; hold, the keeper's): the other team's off the ball -
; out of the box at a goal kick and the keeper's ball, a penalty's all
; out of it - till it is taken (team_ai, control, keep_off)
set_wall:
        lda rs_kind
        bne :+
        rts                     ; (a kick-off: line_up has them)
:       jsr rs_side
        ldx #PLAYERS - 1
@pl:    jsr wall_one
        dex
        bpl @pl
        rts

; rs_side: r_s = the side of the set piece (rs_*) the other team keeps
; off towards: the goal its team attacks (0 the top) - a goal kick's,
; the keeper's ball's, a corner's the other (its box; off the line into
; the pitch). Keeps X.
rs_side:
        lda rs_team
        eor flip
        ldy rs_kind
        cpy #R_GOALKICK
        beq :+
        cpy #R_KEEPER
        beq :+
        cpy #R_CORNER
        bne :++
:       eor #1
:       sta r_s
        rts

; box_busy: carry set if a goal kick or the keeper's ball waits and one
; of the other team is in its box still - they run out of it to their
; places (spot), seen, and it is taken only then: put out of it at once
; (set_wall, as before) the attacker beside the keeper who caught the
; ball vanished (Luca). Keeps X.
box_busy:
        lda rs_kind
        cmp #R_GOALKICK
        beq :+
        cmp #R_KEEPER
        bne @free
:       txa
        pha
        jsr rs_side
        ldx #PLAYERS - 1
@pl:    jsr team_y
        cpy rs_team
        beq @next
        lda o_off,x             ; (one sent off: not there)
        bne @next
        jsr in_box
        bcc @busy
@next:  dex
        bpl @pl
        pla
        tax
@free:  clc
        rts
@busy:  pla
        tax
        sec
        rts

; wall_one: set_wall's player X. Keeps X.
wall_one:
        cpx taker
        bne :+
@next:  rts
:       lda rs_kind
        cmp #R_PENALTY
        beq @pen
        cpx #11                 ; the rest: the other team's within WALL_D
        lda #0                  ; of the ball, WALL_D nearer their goal (a
        rol a                   ; free kick's wall) - a goal kick's out of
        cmp rs_team             ; its box
        beq @next
        lda rs_kind
        cmp #R_GOALKICK         ; (a goal kick, the keeper's ball: they run
        beq @next               ; out of the box - box_busy)
        cmp #R_KEEPER
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
@box:   jsr in_box
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
        tay
        lda #0
        sta o_yf,x
        sta o_xf,x
        tya                     ; (on the pitch)
        bne :+
        lda o_yl,x
        cmp #LINE_T
        bcs @st
        lda #LINE_T
        sta o_yl,x
        bne @st
:       lsr a                   ; (256-511: on it - only the low byte
        bcs @st                 ; looked at, it put them at 433, behind
        lda o_yl,x              ; the taker, Luca)
        cmp #<LINE_B
        bcc @st
        lda #<LINE_B
        sta o_yl,x
@st:    jmp stand

box_out:    .byte <(BOX_T + 12), <(BOX_B - 12)
line_in:    .byte <(LINE_T + 4), <(LINE_B - 4)
.assert >(BOX_T + 12) = 0 && >(BOX_B - 12) = >BOX_B && >(LINE_B - 4) = >LINE_B && >LINE_B = 2 && LINE_T < 256, error, "set_wall: high bytes"

; wall_near: carry clear if player X is within WALL_D of the ball either
; way. Keeps X.
wall_near:
        jsr adx
        bne @no
        cmp #WALL_D
        bcs @no
        jsr ady
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
; head while he holds it, then thrown from there - and of a keeper's, the
; ball in his hands: lift, how high it is drawn over where it is (on the
; ground, as far as the match goes)
throwing:
        lda kickoff
        beq @thrown
        lda rs_kind
        ldy #HOLD_LIFT          ; (the keeper's: in his hands over his head
        cmp #R_KEEPER           ; - the top one's before his chest: over
        bne @throw              ; his head it would be drawn on his line,
        lda rs_team             ; in the net; after ARMS_T both at the
        eor flip                ; chest, the arms down)
        beq :+
        ldy #HOLD_TOP + HOLD_UP
:       lda touch_t
        cmp #ARMS_T
        bcc @hold
        ldy #HOLD_TOP
        bne @hold
@throw: cmp #R_THROW
        bne @none
        lda #THROW_T
        sta throw_t
        ldy #THROW_HOLD
@hold:  sty lift
        rts
@thrown:                        ; (thrown: the ball itself flies, from
        ldy throw_t             ; his head - at_throw)
        beq @none
        dey
        sty throw_t
        lda #0
        sta lift
        rts
@none:  lda #0
        sta throw_t
        sta lift
        rts


; await: the set piece ready, for taker to take: a player's team's with
; his joystick (fire held on from before does not kick), the yellow
; team on its own after a while
await:
        lda #$FF
        sta offer               ; (no one offering yet: offering - nor
        sta offer_w             ; till the stick is pushed, Luca: the way
        sta offer_t             ; the keeper looked at first called one)
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
        lda taker
        sta ctrl_b
        lda #0                  ; (brain_set's clock)
        sta bs_t
        lda #1
        sta bs_rot
        lda #$FF
        sta fire_n_b
        lda two
        bne @go
        lda #CPU_WAIT
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
        jsr adx
        sty mate_t + 1
        sta mate_t
        jsr ady
        clc
        adc mate_t
        sta tmp
        tya
        adc mate_t + 1
        sta tmp + 1
        jsr closer
@skip:  cpx r_t
        bne @look
        ldx mate
        rts

; cpu_take: the yellow team's penalty, once it has waited (its other set
; pieces: brain_set)
cpu_take:
        lda rs_team
        beq @done
        lda two                 ; (a player's: his to take)
        bne @done
        lda rs_kind             ; (the rest: brain_set)
        cmp #R_PENALTY
        bne @done
        lda cpu_t               ; (frames)
        sec
        sbc pic_n
        sta cpu_t
        beq :+
        bcs @done
:
        lda #1
        sta last_team
        ldx taker
        jsr touch_x
        jmp cpu_pen             ; a penalty: shot at a corner
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

pen_xl:     .byte <(304 - PEN_DX), <(304 + PEN_DX)
pen_xh:     .byte >(304 - PEN_DX), >(304 + PEN_DX)

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
        lda o_dive,x            ; diving: his dive goes on, slowing
        beq :+                  ; (keepers_move)
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
        jsr spot                ; (a set piece waiting: his place for it,
        bcc @set                ; Sensible Soccer's - else his own - and
        lda dead_t              ; nothing to go for till it is taken: the
        ora kickoff             ; ball on the penalty spot is no slow ball
        bne @set                ; near him)
        jsr k_high              ; (a high ball into his box: to where it
        bcc @set                ; comes down)
        ldx z_obj
        jsr k_shot              ; (a shot at him: across to it, faster)
        ldx z_obj
        jsr k_get               ; (a slow ball near him, or he the nearest:
                                ; to it)
@set:   lda z_px                ; somewhere else: there
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

; k_posts: z_px between the posts (POST_L + 1 .. POST_R - 2)
k_posts:
        lda z_px
        cmp #<(POST_L + 1)
        lda z_px + 1
        sbc #>(POST_L + 1)
        bcs :+
        lda #<(POST_L + 1)
        sta z_px
        lda #>(POST_L + 1)
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

; k_shot: a ball (512 or more) coming at keeper X's goal, z_py his line
; (z_t8 bit 7: the top keeper): z_px = where it crosses it (x + the
; frames till then * its step across), z_ks = kp_s* - as Sensible
; Soccer's keeper (c12fce, c109ce) he edges across to it, and dives at
; the last moment: the ball DIVE_DY from him or nearer, crossing more
; than he gets to edging, and as far as his dive gets in the frames it
; still takes, or further - his dive's pace guessed anew each time, as
; its keeper does. Keeps X.
k_shot:
        lda #0
        sta k_on
        lda o_sph + BALL
        cmp #>512
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
@div:   lda z_dvd + 1
        sta k_dy
        cmp #KEEPER_SEES + 1    ; (not till it is in the box)
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
        lda z_dvd
        sta k_f
        jsr step_x              ; x + frames * vx
        lda o_xl + BALL
        clc
        adc tmp
        sta tmp
        lda o_xh + BALL
        adc tmp + 1
        sta tmp + 1
        lda tmp                 ; (only a ball at his goal: crossing
        cmp #<SHOT_L            ; between 263 and 344, c12f30)
        lda tmp + 1
        sbc #>SHOT_L
        bcc @wide
        lda #<SHOT_R
        cmp tmp
        lda #>SHOT_R
        sbc tmp + 1
        bcs :+
@wide:  rts
:       inc k_on                ; (a shot at his goal: k_get leaves it)
        lda tmp
        sta z_px
        lda tmp + 1
        sta z_px + 1
        jsr k_posts             ; (as far as he gets: about his posts)
        jsr team_y              ; (his team's: kp_s*)
        lda kp_sl,y
        sta z_ks
        lda kp_sh,y
        sta z_ks + 1
        lda o_dive,x
        beq :+
        jmp @in
:       lda pen_kick
        beq :+
        jmp k_pen
:       lda k_dy                ; near him, and low enough (16, c13038)?
        cmp #DIVE_DY + 1
        bcs @in
        lda o_zl + BALL
        cmp #DIVE_Z + 1
        bcs @in
        lda z_px                ; how far across, which way
        sec
        sbc o_xl,x
        sta tmp
        lda z_px + 1
        sbc o_xh,x
        php
        jsr abs16
        sta tmp
        sty tmp + 1
        ldy #0
        plp
        bpl :+
        iny                     ; (left)
:       sty z_sg
        lda tmp + 1
        bne @dive               ; (far)
        lda tmp
        cmp #2
        bcc @in                 ; (where he is)
        asl a                   ; (in half pixels: 2 * how far)
        bcs @dive
        sta tmp
        jsr team_y
        jsr rnd                 ; his dive's half pixels a frame as he
        and #15                 ; guesses them, 6-13 (c0e020 by his
        cmp kp_dn,y             ; team's table: kp_*)
        bcc :+
        lda kp_dv,y
:       clc
        adc #6
        sta z_t8
        lda #0                  ; * the frames left
        ldy k_f
        beq @dive
:       clc
        adc z_t8
        bcs @in
        dey
        bne :-
        cmp tmp
        beq @dive
        bcs @in                 ; (not yet)
@dive:  lda #<SPEED_DIVE
        sta z_ks
        lda #>SPEED_DIVE
        sta z_ks + 1
        ldy z_sg
        jmp k_dive
@in:    rts

; k_get: keeper X goes for the ball, as Sensible Soccer's: a slow one
; (under 512) low and near him, not held by the other team, kp_g*
; (c130fa); or one in his box, low, that he is nearer than the players
; going for it - both teams' joystick's, the one run after it, the pass's
; - SPEED_NEAR (c12f46). And, as neither original has it, one the other
; team holds - a dribbler's - low in his box within GET_D2 of him: he goes
; for it, SPEED_NEAR (Luca: too many goals, walked in; the dribbler at his
; feet he never took). Keeps X.
k_get:
        lda #0                  ; (the other team's: held)
        cpx #11
        bcc :+
        lda #1
:       jsr held
        lda #0
        ror a
        sta k_i                 ; (bit 7: held - @key's)
        jsr mate_dist
        lda tmp
        sta k_d2
        lda tmp + 1
        sta k_d2 + 1
        bit k_i
        bpl :+
        cmp #>GET_D2            ; (held: only near him, and dribbled -
        bcs @out                ; not a shot just kicked, under 1536)
        lda o_sph + BALL
        cmp #>1536
        bcc @near
@out:   rts
:       lda o_sph + BALL
        cmp #>512
        bcs @near
        lda o_zl + BALL
        cmp #GET_Z
        bcs @out
        lda tmp + 1
        cmp #>GET_D2
        bcs @near
        jsr ball_box            ; (in his box only: out of it no hands;
        bcs @out                ; @near's its own box)
        jsr team_y              ; (his team's: kp_g*)
        lda kp_gl,y
        sta z_ks
        lda kp_gh,y
        sta z_ks + 1
        jmp @go1
@near:  bit k_i                 ; (not a shot at his goal: k_shot's -
        bmi :+                  ; a dribble at it it takes for one)
        lda k_on
        bne @no
:
        lda o_zl + BALL         ; nearer than the players after it?
        cmp #NEAR_Z
        bcs @no
        lda o_xl + BALL         ; (in his box)
        cmp #<BOX_L
        lda o_xh + BALL
        sbc #>BOX_L
        bcc @no
        lda #<BOX_R
        cmp o_xl + BALL
        lda #>BOX_R
        sbc o_xh + BALL
        bcc @no
        jsr top_of
        beq :+
        lda o_yl + BALL
        cmp #<BOX_T
        lda o_yh + BALL
        sbc #>BOX_T
        bcs @no
        bcc @key
:       lda #<BOX_B
        cmp o_yl + BALL
        lda #>BOX_B
        sbc o_yh + BALL
        bcs @no
@key:   stx z_obj
        lda k_i                 ; (held: at the dribbler's feet - he is
        bmi @rush               ; never nearer)
        lda #NEAR_N - 1
        sta k_i
:       ldy k_i
        ldx near_of,y
        lda 0,x
        jsr k_nearer
        bcc @not
        dec k_i
        bpl :-
@rush:  ldx z_obj
        ldy #<SPEED_NEAR
        lda #>SPEED_NEAR
@go:    sty z_ks
        sta z_ks + 1
@go1:
        lda o_xl + BALL
        sta z_px
        lda o_xh + BALL
        sta z_px + 1
        lda o_yl + BALL
        sta z_py
        lda o_yh + BALL
        sta z_py + 1
@no:    rts
@not:   ldx z_obj
        rts

; k_high: keeper X and a high ball in his box, as Sensible Soccer's
; (c12a80, c12e0c, c10e66): where it will come down through 20 high (or
; through as high as it is, 13 at least), if that is in his box too and
; he at most half as far from it as the ball - there, SPEED_NEAR; the
; ball in his goal area always, else 12 - his team's keeper's level times
; in 16 (the level: kp_g*). Carry clear if so: z_px, z_py, z_ks. Keeps X.
k_high:
        lda o_zl + BALL         ; (high: 13 at least)
        cmp #13
        jcc @no
        lda o_vxl + BALL        ; (moving: a pixel a frame at least, one
        clc                     ; way or the other - Sensible Soccer's
        adc #1                  ; from -1 to 1 still)
        cmp #2
        bcs :+
        lda o_vyl + BALL
        clc
        adc #1
        cmp #2
        jcc @no
:       lda o_xl + BALL         ; (the ball: z_ax, z_ay)
        sta z_ax
        lda o_xh + BALL
        sta z_ax + 1
        lda o_yl + BALL
        sta z_ay
        lda o_yh + BALL
        sta z_ay + 1
        ldy #0                  ; in his box now
        jsr k_area
        jcs @no
        ldy #4                  ; in his goal area, or the die
        jsr k_area
        bcc @fall
        jsr team_y
        lda #<1056              ; (the level: (1056 - kp_g) / 32)
        sec
        sbc kp_gl,y
        pha
        lda #>1056
        sbc kp_gh,y
        sta tmp + 1
        pla
        ldy #5
        jsr shr16
        eor #$FF                ; (12 - it)
        sec
        adc #12
        sta z_t8
        jsr rnd
        lsr a
        lsr a
        lsr a
        lsr a
        cmp z_t8
        jcs @no
@fall:  lda o_zl + BALL         ; the frames till it comes down through h
        cmp #20                 ; (20, or as high as it is)
        bcc :+
        lda #20
:       sta z_t8
        lda o_zf + BALL
        sta tmp
        lda o_zl + BALL
        sta tmp + 1
        lda o_dzf + BALL
        sta z_dvd
        lda o_dzl + BALL
        sta z_dvd + 1
        ldy #0
:       iny
        jeq @no                 ; (not down in 255 frames)
        lda z_dvd               ; (gravity, then the step up or down)
        sec
        sbc #$12
        sta z_dvd
        bcs :+
        dec z_dvd + 1
:       lda tmp
        clc
        adc z_dvd
        sta tmp
        lda tmp + 1
        adc z_dvd + 1
        sta tmp + 1
        bmi :+
        cmp z_t8
        bcs :--
:       sty k_f
        stx z_obj
        tya                     ; there: the ball's x, y + frames * steps
        jsr step_x
        lda tmp
        clc
        adc o_xl + BALL
        sta z_ax
        lda tmp + 1
        adc o_xh + BALL
        sta z_ax + 1
        lda k_f
        jsr step_y
        lda tmp
        clc
        adc o_yl + BALL
        sta z_ay
        lda tmp + 1
        adc o_yh + BALL
        sta z_ay + 1
        ldx z_obj
        ldy #0                  ; in his box
        jsr k_area
        jcs @no
        ldx #BALL               ; he at most half as far as the ball:
        jsr l_d2                ; 4 * his way squared no more than its
        ldx z_obj
        bcs :+                  ; (the ball far: any)
        lda tmp
        sta k_d2
        lda tmp + 1
        sta k_d2 + 1
        jsr l_d2
        jcs @no
        asl tmp
        rol tmp + 1
        jcs @no
        asl tmp
        rol tmp + 1
        jcs @no
        lda k_d2
        cmp tmp
        lda k_d2 + 1
        sbc tmp + 1
        jcc @no
:       lda z_ax
        sta z_px
        lda z_ax + 1
        sta z_px + 1
        lda z_ay
        sta z_py
        lda z_ay + 1
        sta z_py + 1
        lda #<SPEED_NEAR
        sta z_ks
        lda #>SPEED_NEAR
        sta z_ks + 1
        clc
        rts
@no:    sec
        rts

; k_area: carry clear if (z_ax, z_ay) is in keeper X's penalty area (Y
; 0) or goal area (Y 4): x from ka_x Y to ka_x Y + 2; y to ka_y Y (the
; top's), or from ka_y Y + 2 (the bottom's). Keeps X.
k_area:
        lda z_ax
        cmp ka_x,y
        lda z_ax + 1
        sbc ka_x + 1,y
        bcc @out
        lda ka_x + 2,y
        cmp z_ax
        lda ka_x + 3,y
        sbc z_ax + 1
        bcc @out
        jsr top_of
        beq @bottom
        lda ka_y,y
        cmp z_ay
        lda ka_y + 1,y
        sbc z_ay + 1
        bcc @out
        clc
        rts
@bottom:
        lda z_ay
        cmp ka_y + 2,y
        lda z_ay + 1
        sbc ka_y + 3,y
        bcc @out
        clc
        rts
@out:   sec
        rts

ka_x:       .word 161, 446, 241, 366
ka_y:       .word 136, 602, 78, 660

; l_d2: tmp = the distance squared from (z_ax, z_ay) to object X, carry
; set if it is 65536 or more. Keeps X.
l_d2:
        lda #0
        sta mate_t
        sta mate_t + 1
        lda z_ax
        sec
        sbc o_xl,x
        sta tmp
        lda z_ax + 1
        sbc o_xh,x
        jsr abs16
        bne @far
        tay
        jsr sq_add
        lda tmp
        sta mate_t
        lda tmp + 1
        sta mate_t + 1
        lda z_ay
        sec
        sbc o_yl,x
        sta tmp
        lda z_ay + 1
        sbc o_yh,x
        jsr abs16
        bne @far
        tay
        jmp sq_add
@far:   sec
        rts

; k_nearer: carry clear if player A (none: $FF) is nearer the ball than
; keeper z_obj (k_d2) - not the keeper himself
k_nearer:
        cmp #PLAYERS
        bcs @far
        cmp z_obj
        beq @far
        tax
        jsr mate_dist
        lda tmp
        cmp k_d2
        lda tmp + 1
        sbc k_d2 + 1
        rts
@far:   sec
        rts

near_of:    .byte ctrl, ctrl_b, recv, recv_b, helper, helper_b
NEAR_N      = * - near_of

; step_x: tmp = A frames * the ball's step across (8.8, signed) / 256 -
; its way in so many frames. Keeps X.
step_y:                         ; (the same down)
        ldy o_vyf + BALL
        sty z_dvs
        ldy o_vyl + BALL
        jmp step_c
step_x:
        ldy o_vxf + BALL
        sty z_dvs
        ldy o_vxl + BALL
step_c: sty z_dvs + 1
        sty z_sg
        jsr mul_set
        bit z_sg                ; (|step|)
        bpl :+
        lda #0
        sec
        sbc z_dvs
        sta z_dvs
        lda #0
        sbc z_dvs + 1
        sta z_dvs + 1
:       ldy z_dvs               ; (low * frames) / 256
        jsr mul_by
        lda z_q + 1
        sta tmp
        ldy z_dvs + 1           ; + high * frames
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
; neg_tmp: tmp = -tmp
neg_tmp:
        lda #0
        sec
        sbc tmp
        sta tmp
        lda #0
        sbc tmp + 1
        sta tmp + 1
:       rts

; k_dive: keeper X dives, way Y (0 right, 1 left), z_ks fast: his
; destination 1000 pixels across. Keeps X.
k_dive:
        tya
        sta o_dvd,x
        lda dive_dx,y
        clc
        adc o_xl,x
        sta z_px
        lda dive_dxh,y
        adc o_xh,x
        sta z_px + 1
        lda #DIVE_T
        sta o_dive,x
        rts

dive_dx:    .byte <1000, <(-1000)
dive_dxh:   .byte >1000, >(-1000)

; k_pen: keeper X and a penalty coming, z_px where it crosses his line:
; as Sensible Soccer's (c109ce, c13038) he waits on his line till it is
; PEN_REACH from it (one time in four PEN_REACH2), then dives - to the
; side it crosses on (straight at him: right), one time in four the
; other way and slower. Keeps X.
k_pen:
        jsr rnd
        ldy #PEN_REACH
        and #$18
        bne :+
        ldy #PEN_REACH2
:       tya
        cmp k_dy
        bcs @dive
        lda o_xl,x              ; (not yet: he stays)
        sta z_px
        lda o_xh,x
        sta z_px + 1
        rts
@dive:  ldy #0                  ; right (0) or left (1)
        lda z_px
        cmp o_xl,x
        lda z_px + 1
        sbc o_xh,x
        bcs :+
        iny
:       lda #<SPEED_DIVE
        sta z_ks
        lda #>SPEED_DIVE
        sta z_ks + 1
        jsr rnd                 ; (one in four: the wrong way, slower)
        and #6
        bne :+
        tya
        eor #1
        tay
        lda #<SPEED_DIVE_W
        sta z_ks
        lda #>SPEED_DIVE_W
        sta z_ks + 1
:       jmp k_dive

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
; own kick: he holds it - in his box, and not a team-mate's back-pass;
; else he kicks it away (k_clear)
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
:       jsr ball_box            ; (his hands: in his box only, nor
        bcs k_clear             ; for a team-mate's back-pass)
        ldy #0
        cpx #11
        bcc :+
        iny
:       cpy last_team
        bne @theirs
        cpx last_pl             ; (his own parry, his own kick: his
        bne k_clear             ; hands again OWN_T frames on - else
        lda touch_t             ; the ball he had saved was the team's
        cmp #OWN_T              ; back-pass, he kicked it away, Luca;
        bcc @done               ; not his set piece's kick untouched
        lda off_pl              ; since, off_pl $FE: a double touch, a
        cmp #$FE                ; free kick in his box - a penalty
        beq @done               ; after his goal kick, said Luca)
@hands: lda o_dive,x            ; (diving: it bounces off him)
        bne parry
        jmp hold
@theirs:
        lda o_sph + BALL        ; (their shot saved, caught or parried:
        cmp #>SAVE_SP           ; the crowd's "oh" - Luca)
        bcc @hands
        jsr @hands
        jmp sfx_save
@done:  rts

; ball_box: carry clear if the ball is in keeper X's penalty area (k_area).
; Keeps X.
ball_box:
        lda o_xl + BALL
        sta z_ax
        lda o_xh + BALL
        sta z_ax + 1
        lda o_yl + BALL
        sta z_ay
        lda o_yh + BALL
        sta z_ay + 1
        ldy #0
        jmp k_area

; k_clear: keeper X at a ball he may not take in his hands - out of his
; box, or a team-mate's back-pass: he kicks it away out from his goal,
; as hard as a shot and rising. Keeps X.
k_clear:
        lda #0                  ; (stopped: no dive on)
        sta o_dive,x
        tay
        cpx #11
        bcc :+
        iny
:       sty last_team
        jsr touch_x
        jsr top_of              ; the way out: down from the top goal
        beq :+
        lda #4
:       sta o_dir,x
        tay
        jsr ball_ahead
        jsr shot_speed
        lda #<SHOT_DZ
        sta o_dzf + BALL
        lda #>SHOT_DZ
        sta o_dzl + BALL
        jmp sfx_kick

; parry: keeper X diving has got to the ball: as from Sensible Soccer's
; it bounces off him out to the side he dives and away from his goal, a
; quarter and a 64th slower, and he goes on half as fast. Keeps X.
parry:
        ldy #0
        cpx #11
        bcc :+
        iny
:       sty last_team
        jsr touch_x
        ldy o_dvd,x
        lda par_dx,y
        clc
        adc o_xl + BALL
        sta o_txl + BALL
        lda par_dxh,y
        adc o_xh + BALL
        sta o_txh + BALL
        ldy #0                  ; (the top keeper: down, the bottom one up)
        jsr top_of
        bne :+
        iny
:       lda par_dy,y
        clc
        adc o_yl + BALL
        sta o_tyl + BALL
        lda par_dyh,y
        adc o_yh + BALL
        sta o_tyh + BALL
        lda o_sph + BALL        ; s - s/4 - s/64
        sta tmp + 1
        lda o_spl + BALL
        ldy #2
        jsr ball_less
        ldy #4                  ; (s/4 / 16)
        lda tmp
        jsr ball_less
        lda o_sph,x             ; his: s/2 - s/32
        sta tmp + 1
        lda o_spl,x
        ldy #1
        jsr shr16
        sta o_spl,x
        lda tmp + 1
        sta o_sph,x
        ldy #4
        jsr sp_cut
        jmp sfx_kick

; sp_cut: player X's speed less itself shifted right Y times. Keeps X.
sp_cut: lda o_sph,x
        sta tmp + 1
        lda o_spl,x
        jsr shr16
        sta tmp
        lda o_spl,x
        sec
        sbc tmp
        sta o_spl,x
        lda o_sph,x
        sbc tmp + 1
        sta o_sph,x
        rts

; shr16: A (low) and tmp + 1 (high) shifted right Y times; A the low
; byte, tmp + 1 the high one. Keeps X.
; ball_less: the ball's speed less (tmp + 1, A) shifted right Y times.
; Keeps X.
ball_less:
        jsr shr16
        sta tmp
        lda o_spl + BALL
        sec
        sbc tmp
        sta o_spl + BALL
        lda o_sph + BALL
        sbc tmp + 1
        sta o_sph + BALL
        rts

; sq_add: tmp = mate_t + Y squared (sq8), A its high byte, carry set if
; it overflows. Keeps X, Y.
sq_add:
        lda sq8_lo,y
        clc
        adc mate_t
        sta tmp
        lda sq8_hi,y
        adc mate_t + 1
        sta tmp + 1
        rts

shr16:
:       lsr tmp + 1
        ror a
        dey
        bne :-
        rts

par_dx:     .byte <980, <(-980)
par_dxh:    .byte >980, >(-980)
par_dy:     .byte <770, <(-770)
par_dyh:    .byte >770, >(-770)

; reach: carry clear if the ball is within keeper X's reach, and not
; from his own kick. Keeps X.
reach:
        cpx last_pl
        beq @no
        lda #CATCH_X
        ldy o_dive,x            ; (diving, lying across: further)
        beq :+
        lda #DIVE_X
:       sta z_t8
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
        jsr touch_x
        sta o_dir,x
        jsr stand
        ldx #BALL
        jsr stand
        lda #0
        sta o_zl,x
        sta o_zf,x
        sta o_dzl,x
        sta o_dzf,x
        ldx taker               ; where he is, drawn in his hands (throwing)
        lda o_xl,x
        sta o_xl + BALL
        lda o_xh,x
        sta o_xh + BALL
        lda o_yl,x
        sta o_yl + BALL
        lda o_yh,x
        sta o_yh + BALL
        ldx #BALL
        jsr stand
        jsr set_wall
        jmp await

; ---- holding the ball, tackles -------------------------------------------
;
; A ball a team has touched in the last HOLD_T frames is that team's (who
; runs to it, a foul from behind) - but, as in Sensible Soccer, that does
; not keep it: whoever gets to it has it, and a sliding tackle that
; reaches it wins it, no roll for either. A tackle goes the way the
; player faces, fast and slower each frame; reaching the ball low, it
; knocks it on that way.

; touch: the ball just touched by X (touch_t from 0; a set piece's
; taker twice: double touch, below). Keeps A, X, Y.
; touch_me: by player X of the joystick's team (me), a pass met: the
; ball his; touch_x: by player X (last_pl). Keep X, Y.
touch_me:
        lda #$FF                ; (a pass met)
        sta recv
        lda me
        sta last_team
touch_x:
        php                     ; (another touches it: thrown no longer -
        cpx thrower             ; head)
        beq :+
        pha
        lda #$FF
        sta thrower
        pla
:       plp
        stx last_pl
touch:
        php
        pha
        lda #0
        sta touch_t
        sta pen_kick
        lda kickoff             ; (the penalty taken: pen_kick)
        beq @dbl
        lda rs_kind
        cmp #R_PENALTY
        bne :+
        sta pen_kick
:       cmp #R_KEEPER           ; (the keeper's ball out of his hands is
        beq @dbl                ; no set piece: his again at once - his
                                ; touch after it was a double touch, a
                                ; free kick at his box, Luca's penalty)
        lda off_pl              ; a set piece's kick: its taker not to
        cmp #$FF                ; touch it again before anyone else -
        bne @dbl                ; off_pl $FE, off_by him (not after the
        dec off_pl              ; kick), and no one's dribble for DBL_T
        stx off_by              ; frames: the ball away from his feet
        lda #DBL_T
        sta lock_t
        sta lock_t + 1
        bne @done
@dbl:   lda off_pl              ; (marked: the taker again - off_chk's
        cmp #$FE                ; whistle, as for offside; anyone else
        bne @done               ; first: over)
        cpx off_by
        bne :+
        stx off_pl
        sta off_by              ; ($FE: no one's)
        bcs @done
:       inc off_pl
        lda #0                  ; (and no lock: DBL_T kept the receiver
        sta lock_t              ; beside the kick-off's taker from
        sta lock_t + 1          ; dribbling on - he ran off without the
                                ; ball, Luca)
@done:  pla
        plp
        rts

; held: carry set if the ball is held by the team other than A's: it
; touched it HOLD_T frames ago or less, or its player who did has it by
; him, low - not one down, sliding or knocked over (Luca: a ball by one
; lying there no one came for). Keeps X, Y.
held:
        cmp last_team
        beq @no
        lda touch_t
        cmp #HOLD_T + 1
        bcc @yes
        lda o_zl + BALL
        cmp #HOLD_Z + 1
        bcs @no
        tya
        pha
        ldy last_pl
        lda o_slide,y           ; (down: as far as can be)
        sta tmp + 1
        bne :+
        jsr dist_y
:       pla
        tay
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
; nudge: way Y that player X slides turned one step towards his team's
; stick, unless that is the same or the other way (Sensible Soccer's
; c113f8). Keeps X.
nudge:
        sty tmp
        lda pj
        cpx #11
        bcc :+
        lda pj_b
:       and #$0F
        tay
        lda joy_dir,y
        cmp #8
        beq @keep
        eor #$FF                ; way - stick
        sec
        adc tmp
        and #7
        beq @keep
        cmp #4
        beq @keep
        ldy tmp
        bcc :+
        iny
        iny
:       dey
        tya
        and #7
        tay
        rts
@keep:  ldy tmp
        rts

slide:
        lda #0
        sta o_hd,x
        lda #SLIDE_T
        sta o_slide,x
        sta sl_any
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
        jsr aim_way
        lda #$FF
        rts

; aim_run: the joystick's player X's destination RUN_D pixels the way Y,
; set again each frame he runs: 1000 pixels on, inside cut it at the
; walls round the pitch from far off and turned his way - running up and
; right from the middle he went 34 degrees off up, the ball he dribbled 45:
; it was soon out of his reach (Luca: no diagonal ever keeps the ball).
; Keeps X, Y.
RUN_D       = 128
aim_run:
        lda o_xl,x
        clc
        adc run_x,y
        sta o_txl,x
        lda run_x,y
        and #$80                ; (the high byte: the sign's)
        beq :+
        lda #$FF
:       adc o_xh,x
        sta o_txh,x
        lda o_yl,x
        clc
        adc run_y,y
        sta o_tyl,x
        lda run_y,y
        and #$80
        beq :+
        lda #$FF
:       adc o_yh,x
        sta o_tyh,x
        rts
run_x:      .byte 0, RUN_D - 1, RUN_D - 1, RUN_D - 1, 0, <(1 - RUN_D), <(1 - RUN_D), <(1 - RUN_D)
run_y:      .byte <(1 - RUN_D), <(1 - RUN_D), 0, RUN_D - 1, RUN_D - 1, RUN_D - 1, 0, <(1 - RUN_D)

; aim_way: object X's destination 1000 pixels from it, way Y. Keeps X, Y.
aim_way:
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
        rts

; slides: the sliding tackles on a frame: slower, the ball knocked on if
; reached, up at the end - and the ones knocked over. Each one sliding or
; down, not only the joystick's players and the yellow team's runner, who
; start the tackles: one no longer the runner when the computer's runner
; changed slid on at full speed, never slower, 1000 pixels to where
; slide aimed him - off the pitch, down there for good (Luca's long
; tackle, its colours left on the boards) - and in the box, there the
; keeper's ball waited for him (box_busy) for ever (Luca's stuck keeper)
slides:
        lda sl_any              ; (no one: as quick as it was)
        beq @rts
        lda #0
        sta sl_any
        ldx #PLAYERS - 1
@pl:    lda o_slide,x
        beq @next
        sta sl_any
        txa
        pha
        jsr @one
        pla
        tax
@next:  dex
        bpl @pl
        rts
@one:   lda dead_t              ; (a foul whistled in this frame, by the
        bne @rts                ; cyan team's: its victim, the yellow
        lda o_slide,x           ; team's joystick's, stays down - not up
        bne :+                  ; again at once, his turn after it)
@rts:   rts
:       dec o_slide,x
        bne :+
        jmp stand               ; (over: up again)
:       lda #SLIDE_DECEL        ; slower
        ldy o_hd,x
        beq :+
        lda #DHEAD_DECEL
:       ldy o_hit,x             ; (knocked over: as Sensible Soccer's fall)
        cpy #3
        bne :+
        lda #FALL_DECEL
:       jsr slow
        lda o_hit,x             ; (knocked over himself: no more)
        cmp #3
        bne :+
        rts
:       cmp #0                  ; the ball reached, low: knocked on (a
        bne @bump               ; diving header: in the air, headed on) -
        lda o_zl + BALL         ; not, the other team's player he slides
        ldy o_hd,x              ; into knocked over (bump)
        beq :+
        cmp #DHEAD_Z_LO         ; (a header: 8 - 15 high, in his dive's
        bcc @bump               ; first frames)
        cmp #DHEAD_Z_HI + 1
        bcs @bump
        lda o_slide,x
        cmp #SLIDE_T - DHEAD_T
        bcs @reach
@bump:  jmp bump
:       cmp #SLIDE_Z + 1
        bcs @bump
@reach: jsr mate_dist
        lda tmp + 1
        bne @bump
        lda tmp
        cmp #SLIDE_REACH + 1
        bcs @bump
        lda o_hd,x              ; the other team's joystick's player with
        bne @take               ; it at his feet: the better more often
        ldy ctrl_b              ; (odds, as duel's - Arlasoft's: both
        cpx #11                 ; teams at it); lost, the tackle misses
        bcc :+                  ; it (o_hit $80: his fall a foul, bump)
        ldy ctrl
:       tya
        bmi @take
        stx z_obj
        tax
        jsr at_feet
        ldx z_obj
        bcs @take
        ldy ctrl_b
        cpx #11
        bcc :+
        ldy ctrl
:       jsr odds
        bcc @take
        lda #$80
        sta o_hit,x
        jmp bump
@take:  jsr clean
        sta o_hit,x
        lda #0                  ; his, whoever's it was (c13f5a) - and
        cpx #11                 ; the other team's joystick's player
        bcc :+                  ; not to dribble it for LOCK_T frames
        lda #1
:       sta last_team
        eor #1
        tay
        lda #LOCK_T
        sta lock_t,y
        jsr touch_x
        ldy o_dir,x
        jsr nudge               ; (a way nearer the stick's)
        jsr ball_ahead
        lda o_sph,x             ; a quarter faster than he slides (its
        sta tmp + 1             ; c113f8) - the computer's team's as fast
        lda o_spl,x             ; (c1145a) - and he half as fast
        lsr tmp + 1
        ror a
        lsr tmp + 1
        ror a
        cpx #11
        bcc :+
        ldy two
        bne :+
        lda #0
        sta tmp + 1
:       clc
        adc o_spl,x
        sta o_spl + BALL
        lda tmp + 1
        adc o_sph,x
        sta o_sph + BALL
        lda o_hd,x              ; a header: rising (c11522), he on as fast
        beq :+
        lda #<DHEAD_DZ
        sta o_dzf + BALL
        lda #>DHEAD_DZ
        sta o_dzl + BALL
        jmp sfx_kick
:       lsr o_sph,x
        ror o_spl,x
        lda #0                  ; (off the ground: it drops - a step of 0
        ldy o_zl + BALL         ; would hold it up there)
        beq :+
        lda #$FF
:       sta o_dzl + BALL
        sta o_dzf + BALL
        jmp sfx_kick
@done:  rts

; victim: Y = the player a sliding tackle by X can knock over, as in
; Sensible Soccer (c10f0c) the other team's joystick's; N set if none.
; Keeps X.
victim:
        cpx #11
        bcs :+
        ldy ctrl_b              ; (ldy last: N for none)
        rts
:       ldy ctrl
        rts

; clean: A = player X's sliding tackle reaching the ball as Sensible
; Soccer has it (c1148a): 2 clean, the other team's joystick's player
; not right at it nor by him; 1 he is - a foul if he is knocked over
; from behind (bump). Keeps X.
clean:
        jsr victim
        bmi @near
        jsr pair_d2
        lda tmp + 1
        bne :+
        lda tmp
        cmp #NEAR + 1
        bcc @near
:       jsr dist_y
        lda tmp + 1
        bne :+
        lda tmp
        cmp #9
        bcc @near
:       lda #2
        rts
@near:  lda #1
        rts

; bump: sliding player X, fast still (512), into the other team's
; joystick's player (victim, within NEAR): he is knocked over - down
; FALL_T frames, sliding on slower (o_hit 3) - and the tackle slowed to a
; quarter (a keeper only slows it). A foul, near the ball (FOUL_D2), if
; the tackle had not reached the ball, or had with him right at it and
; comes from behind: Sensible Soccer's c10f0c. Keeps X.
bump:
        lda o_hd,x
        beq :+
@out:   rts
:       lda o_sph,x
        cmp #>512
        bcc @out
        jsr victim
        bmi @out
        lda o_slide,y           ; (down already)
        beq :+
        lda o_hit,y
        cmp #3
        beq @out
:       jsr pair_d2
        lda tmp + 1
        bne @out
        lda tmp
        cmp #NEAR + 1
        bcs @out
        lsr o_sph,x
        ror o_spl,x
        lsr o_sph,x
        ror o_spl,x
        tya                     ; (a keeper: only that)
        beq @no
        cmp #11
        beq @no
        lda #FALL_T
        sta o_slide,y
        sta sl_any
        lda #3
        sta o_hit,y
        lda #0
        sta o_hd,y
        jsr dist_y
        lda tmp
        cmp #<(FOUL_D2 + 1)
        lda tmp + 1
        sbc #>(FOUL_D2 + 1)
        bcs @no
        lda o_hit,x
        beq @foul
        bmi @foul               ; (missed it: slides)
        cmp #2
        beq @no
        lda o_dir,x             ; (from behind: the ways at most one
        sec                     ; apart, not round past 0)
        sbc o_dir,y
        clc
        adc #1
        cmp #3
        bcs @no
@foul:  sty last_pl             ; (the free kick his team's)
        lda #0
        cpy #11
        bcc :+
        lda #1
:       sta last_team
        jmp foul
@no:    rts

; pair_d2: tmp = the distance squared between players X and Y, $FFFF from
; 256 either way. Keeps X, Y.
pair_d2:
        sty hd_y
        lda o_xl,x
        sec
        sbc o_xl,y
        sta tmp
        lda o_xh,x
        sbc o_xh,y
        jsr abs16
        bne @far
        tay
        lda sq8_lo,y
        sta mate_t
        lda sq8_hi,y
        sta mate_t + 1
        ldy hd_y
        lda o_yl,x
        sec
        sbc o_yl,y
        sta tmp
        lda o_yh,x
        sbc o_yh,y
        jsr abs16
        bne @far
        tay
        jsr sq_add
        bcc @out
@far:   lda #$FF
        sta tmp
        sta tmp + 1
@out:   ldy hd_y
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
        lda o_hit,x             ; (knocked over: down)
        cmp #3
        beq @down
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
        lda touch_t             ; (after ARMS_T at his chest: standing)
        cmp #ARMS_T
        bcs @none
        lda #IMG_HOLD
        rts
@down:  lda #IMG_DOWN
        rts
@none:  lda goal                ; (Luca: celebrations - after a goal the
        beq @ft                 ; scorers' team, at full time the winners:
        lda rs_team             ; each jumps, his arms up, by turns)
        eor #1
        bpl @team
@ft:    lda full
        beq @no
        lda score
        cmp score + 1
        beq @no                 ; (a draw: no one)
        lda #0
        rol a                   ; (1: the cyan team won)
        eor #1
@team:  cpx #11                 ; (his team and A's: 0 0 or 1 1 - A * 2
        rol a                   ; + his + 1 has bit 1 clear)
        adc #1
        and #2
        bne @no
        txa                     ; (Luca: twice as often, and he jumps -
        asl a                   ; draw: IMG_HOLD three lines higher - 8
        asl a                   ; frames in 32)
        asl a
        adc frame_n
        and #$18
        bne @no
        lda #IMG_HOLD
        rts
@no:    lda #$FF
        rts

; cam_way: A = the way the view leans ahead of the ball (follow) - at a
; goal kick and the keeper's ball the way the taker faces, the team-mate
; he may pass to in view (Luca: as the original's view, when the keeper
; turns); else $FF
cam_way:
        lda kickoff
        beq @no
        lda rs_kind
        cmp #R_GOALKICK
        beq :+
        cmp #R_KEEPER
        bne @no
:       ldx taker
        bmi @no
        lda o_dir,x
        rts
@no:    lda #$FF
        rts

; ---- the match's time ---------------------------------------------------

; clock: a frame of the match's time (not while a set piece waits, nor
; after full time): at 45 minutes half time, the yellow team to kick
; off, at 90 full time - each once the ball is in the middle half of the
; pitch (MID_T - MID_B), the action at a goal played out; and hud, the score and minute shown, while the
; ball is dead or a set piece waits (Luca: at every stop - it was the
; kick-off's only), and from 45 or 90 minutes on till the whistle (Luca:
; the time up, the ball still in play)
clock:
        lda #0
        ldy kickoff
        bne @hud
        ldy dead_t
        beq :+
@hud:   lda #1
:       sta hud
        lda kickoff
        ora full
        ora train               ; (training: no time)
        bne @done
        lda game_min            ; (the half's last minute: no more - 90
        cmp #90                 ; on whichever half, a test's too)
        bcs @end
        cmp #45
        bne :+
        ldy half
        beq @end
:       inc min_t
        lda min_t
        cmp min_frames
        bcc @done
        lda #0
        sta min_t
        inc game_min
@done:  rts
@end:   inc hud                 ; (the time up: shown - 1 or 2)
        ldy dead_t              ; (not while the ball is dead: a foul at 90
        bne @done               ; minutes is taken, Luca - the whistle went,
        lda o_yl + BALL         ; FOUL still shown) 45 or 90 minutes and the action's end:
        cmp #<MID_T             ; the whistle once the ball is in the
        lda o_yh + BALL         ; middle half of the pitch - near either
        sbc #>MID_T             ; goal play goes on (Luca's vote)
        bcc @done
        lda o_yl + BALL
        cmp #<MID_B
        lda o_yh + BALL
        sbc #>MID_B
        bcs @done
        lda game_min
        cmp #90
        bcs :+
        lda #1
        sta half
        sta flip                ; (the sides change)
        sta rs_team             ; (the yellow team kicks off again)
        bne @whistle
:       lda #PLAYERS + 1        ; (full time: the players still on, one
        sta full                ; more - ft_spot)
        jsr sfx_roar
        lda #0
        sta rs_team
        sta min_t               ; (new_match counts from here)
@whistle:
        lda #DEAD_HALF
        jmp whistle

; whistle: the ball dead A frames, for a kick-off in the middle (rs_team's)
whistle:
        sta dead_t
        jsr sfx_halftime
        lda #0
        sta goal
        jsr kick_spot
        jmp calm

; kick_spot: a kick-off next, from the middle
kick_spot:
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
        rts

; new_match: after full time, the ball kept dead till fire, which goes
; back to the title (resident.s: the title and the league's page from the
; disk, cup.s) - or, a test without the disk, starts a new match: no
; goals, the first minute, the cyan team to kick off
new_match:
        lda v_left + 1          ; (the crowd quiet: it murmurs, on and on
        bne @loud               ; till fire - Luca)
        lda #<fx_murmur
        ldx #>fx_murmur
        jsr crowd1
@loud:  lda min_t               ; (the result shown 2 seconds at least:
        cmp #STAND_T            ; min_t counts them from the whistle - the
        bcs :+                  ; teams stand meanwhile, ft_spot)
        inc min_t
        cmp #FALL_T             ; (FALL_T frames in, those lying up, to
        bne @on                 ; the middle with the rest - Luca: one
        jsr get_up              ; sliding at the end lay there dead)
        jmp @on
:       lda joy
        and #J_FIRE
        bne :+
@on:    inc dead_t              ; (dead on)
        rts
:       lda K_REQ               ; (pause.s quit_a: K_GO, or without the
        jmp quit_a              ; disk anew)
anew:   lda #0                  ; (pause.s: a match anew)
        sta full
        sta half
        sta game_min
        sta min_t
        sta score
        sta score + 1
        sta rs_team
        sta flip
        jsr squad
        lda #1
        sta dead_t              ; (the kick-off next frame)
        rts

; squad: no cards, no one off - but in training only the keepers and
; four of each team: a centre back (4), the central midfielders (7, 8)
; and the centre forward (10); the match's referee (ref_k: how often he
; shows a yellow, of Sensible Soccer's c0fa92 by chance)
squad:
        jsr rnd
        and #15
        tax
        lda ref_tab,x
        sta ref_k
        ldx #PLAYERS - 1
:       lda #0
        sta fouls,x
        ldy train
        beq :+
        lda off_train,x
:       sta o_off,x
        dex
        bpl :--
        rts

off_train:  .byte 0, 3, 3, 0, 3, 3, 0, 0, 3, 0, 3   ; (3: team_ai's too)
            .byte 0, 3, 3, 0, 3, 3, 0, 0, 3, 0, 3

; ---- the yellow team's play ---------------------------------------------

; ---- the computer's mind -----------------------------------------------------
;
; The computer runs the yellow team on its own as Sensible Soccer's does
; (c14a4e): with a joystick for its joystick's player, as a player's -
; control, switch, help and the rest are the same for both teams. brain
; works his stick out once a picture (play_picture), and when to pass or
; shoot; what Sensible Soccer's does at random each frame it does as
; often for the frames since the last picture (chance_*).

; chance_*: Sensible Soccer's die each frame for the frames since the
; last picture (1 - 4): 256 * (1 - (1 - p)^frames), p 1 in 4, 1 in 8,
; 9 in 256 - the die is under it
chance_4:   .byte 64, 112, 148, 175
chance_8:   .byte 32, 60, 84, 106
chance_9:   .byte 9, 18, 26, 34

; brain: the computer's joystick for its joystick's player X: pj his
; stick, br_ev 1 a pass, 2 a shot (control makes it). Keeps X.
brain:
        lda #0
        sta pj
        sta br_ev
        lda br_t                ; (frames: down to 0 - at set pieces too,
        sec                     ; else one kicked just before the whistle
        sbc pic_n               ; keeps it from ever taking it)
        bcs :+
        lda #0
:       sta br_t
        lda kickoff             ; (its set pieces: brain_set; the other
        beq @play               ; team's: nothing)
        lda rs_team
        cmp me
        jeq brain_set
        rts
@play:  jsr rnd
        sta br_r
        lda at_n                ; its shot on its way: the aftertouch
        bmi :+
        jmp br_after
:       jsr goal_way
        jsr mate_dist
        lda tmp
        sta br_d
        lda tmp + 1
        sta br_d + 1
        bne br_free
        lda tmp
        cmp #CLOSE + 1
        bcc br_have
; br_free (c15064): without it he runs to the ball - turned to it only if
; it is near (800), that way already or 1 in 8
br_free:
        jsr ball_way
        sta br_w
        cmp o_dir,x
        beq @to
        lda br_d
        cmp #<800
        lda br_d + 1
        sbc #>800
        bcc @to
        jsr rnd                 ; (1 in 8 a frame)
        ldy pic_n
        cmp chance_8 - 1,y
        bcc @to
        lda o_dir,x
        jmp br_stick
@to:    lda br_w
        jmp br_stick

; br_have (c14e9c): the ball his - shot near the goal if he faces it,
; else passed, dribbled on to the goal or sideways by how near the cyan
; players are
br_have:
        lda d6                  ; near enough (28800), and so near (12800)
        cmp #<(28800 / 16 + 1)  ; or 1 in 4 (d6: / 16)
        lda d6 + 1
        sbc #>(28800 / 16 + 1)
        bcs @far
        lda d6
        cmp #<(12800 / 16)
        lda d6 + 1
        sbc #>(12800 / 16)
        bcc :+
        jsr rnd                 ; (1 in 4 a frame)
        ldy pic_n
        cmp chance_4 - 1,y
        bcs @far
:       ldy #15                 ; facing it: within 15 (3200 near: 50)
        lda d6
        cmp #<(3200 / 16 + 1)
        lda d6 + 1
        sbc #>(3200 / 16 + 1)
        bcs :+
        ldy #50
:       sty br_w
        jsr facing              ; A = his way - the goal's (256)
        bmi :+
        cmp br_w
        beq @shot
        bcs @far
        bcc @shot
:       eor #$FF                ; (-A - 1 >= tol: off)
        cmp br_w
        bcs @far
@shot:  lda #0
        jmp br_shoot
@far:   lda br_6c               ; looking for a team-mate to pass to
        beq @near
        sec                     ; (frames: down to 0)
        sbc pic_n
        bcs :+
        lda #0
:       sta br_6c
        jsr br_cone
        jcs br_side
        jeq br_pass
        jmp br_side
@near:  lda d6                  ; near the goal (9800): on to it
        cmp #<(9800 / 16)
        lda d6 + 1
        sbc #>(9800 / 16)
        bcs :+
        jmp br_goal
:       ldy ctrl_b              ; the cyan joystick's player near (800 /
        jsr br_opp              ; 5000), else its runner
        bcs :+
        beq br_close
        bne br_near
:       ldy helper_b
        jsr br_opp
        bcs br_goal
        beq br_close
        bne br_near
; br_close (c14f6e): pressed - far from the goal (180000) a long ball,
; else passed if a team-mate is the one that way
br_close:
        lda d6
        cmp #<(180000 / 16 + 1)
        lda d6 + 1
        sbc #>(180000 / 16 + 1)
        jcs br_long
        jsr br_cone
        bcs br_try
        beq br_pass
        bne br_try
; br_near (c14fb0): a cyan player coming - 9 in 256 a long ball if far
; (48400), 1 in 4 a pass if a team-mate is that way, else on to the goal
br_near:
        lda br_r                ; (9 in 256 a frame)
        ldy pic_n
        cmp chance_9 - 1,y
        bcs :+
        lda d6
        cmp #<(48400 / 16 + 1)
        lda d6 + 1
        sbc #>(48400 / 16 + 1)
        bcs br_long
:       jsr rnd                 ; (1 in 4 a frame)
        ldy pic_n
        cmp chance_4 - 1,y
        bcs br_goal
        jsr br_cone
        bcs br_try
        beq br_pass
; br_try (c14ff0): 1 in 4 (32 in 128) he starts looking for a team-mate
; for 4 frames, stepping aside; else on to the goal
br_try:
        lda br_6c
        bne br_goal
        jsr rnd                 ; (1 in 4 a frame)
        ldy pic_n
        cmp chance_4 - 1,y
        bcs br_goal
        lda #4
        sta br_6c
; br_side (c15010): a step aside - his way turned one way or the other,
; the ball at his feet (a dribble's: DRIB_NEAR - with NEAR he went on
; straight with it most pictures, out over the line)
br_side:
        lda br_d
        cmp #DRIB_NEAR + 1
        bcs br_dir
        lda #1
        bit br_r
        bpl :+
        lda #$FF
:       clc
        adc o_dir,x
        and #7
        jmp br_stick
; br_goal (c15042): on to the goal, the ball at his feet
br_goal:
        lda br_d
        cmp #DRIB_NEAR + 1
        bcs br_dir
        jsr goal_dir
        jmp br_stick
br_dir: lda o_dir,x             ; (on as he goes)
        jmp br_stick

; br_pass (c150a4): a pass the way he faces - not if it kicked a moment
; ago, nor his team
br_pass:
        lda #0
        sta br_6c
        lda br_t
        bne @no
        ldy me
        lda kick_t,y
        cmp #BR_KICKED
        bcc @no
        lda #BR_WAIT
        sta br_t
        lda #1
        sta br_ev
        jmp br_dir
@no:    rts

; br_long (c150e8): facing the goal, one way off or so, a long ball (2:
; lifted, far from it, 115600; else 1: low), else br_try
br_long:
        jsr goal_dir
        sec
        sbc o_dir,x
        clc
        adc #1
        and #7
        cmp #3
        bcs br_try
        lda d6
        cmp #<(115600 / 16 + 1)
        lda d6 + 1
        sbc #>(115600 / 16 + 1)
        bcc :+
        lda #2
        bne br_kick
:       lda #1
        bne br_kick

; br_shoot (c15152): a shot of kind A (0) - not if it kicked a moment
; ago, nor his team - bent to the side of the goal he faces
br_shoot:
        ldy br_t
        bne br_none
        pha                     ; (the kind kept)
        ldy me
        lda kick_t,y
        tay
        pla
        cpy #BR_KICKED
        bcc br_none
br_kick:
        sta br_6e
        lda #BR_WAIT
        sta br_t
        lda #2
        sta br_ev
        jsr facing              ; (the side: his way's off the goal's -
        ldy #$FF                ; bent back to it)
        cmp #0
        bpl :+
        ldy #1
:       sty br_70
        jmp br_dir
br_none:
        rts

; br_after (c153e0): his shot on its way: half the frames the stick on
; it (kind 0), let go (1) or pulled back (2); the others across it to
; its side, 1 - 3 ways by its kind
br_after:
        ldy br_70
        beq @on
        lda br_r
        lsr a
        bcc @on
        lda br_6e               ; (+ kind + 1, - kind - 1)
        cpy #1
        bne :+
        adc #0                  ; (carry set)
        bne @add
:       eor #$FF
        bne @add
@on:    lda br_6e
        cmp #1
        beq @none
        asl a                   ; (0: on, 2: back, 4 round)
@add:   ldy me
        clc
        adc at_dir,y
        and #7
        jmp br_stick
@none:  rts

; brain_set: the computer's set piece, as Sensible Soccer's (c14b08 -
; c14e48): ready, it waits 50 frames and a few more (up to 63, its die
; anew each frame) - a throw-in's taker turning about meanwhile to look
; for someone, a corner's facing along the goal line, a free kick's to
; the goal - then: a kick-off is passed, a throw-in thrown long 1 in 16
; (a frame) if he faces one of the ways its place throws long (thr_ok),
; as a set piece kicked hard (bs_shot), else passed; a
; corner crossed along the goal line, in front of the goal, as on the C64
; (ball_ahead turns it in); a free kick
; 15 in 16 shot if he faces the goal (else he turns to it), 1 in 16
; passed; a goal kick and the keeper's kicked long. A pass only to a
; team-mate nearest that way (br_cone), else he turns on - after 150
; frames kicked (Sensible Soccer's kick-off; here any set piece's, that
; none waits for ever). The penalty: cpu_take's. Keeps X.
brain_set:
        lda rs_kind
        cmp #R_PENALTY
        beq @none
        lda bs_t                ; (frames, no further than 255)
        clc
        adc pic_n
        bcc :+
        lda #255
:       sta bs_t
        jsr rnd
        sta br_r
        jsr goal_way
        jsr rnd                 ; waiting: 50 + 0-63 frames
        and #$3F
        clc
        adc #50
        cmp bs_t
        bcc @go
        beq @go
        ldy rs_kind             ; meanwhile: turning about, along the
        cpy #R_THROW            ; goal line (a corner), or to the goal
        jeq bs_turn
        cpy #R_CORNER
        bne :+
        jsr bs_along
        jmp br_stick
:       cpy #R_FREE
        bne @none
        jsr goal_dir
        jmp br_stick
@none:  rts
@go:    lda bs_t                ; (no one to pass to after 150 frames:
        cmp #150                ; kicked - as Sensible Soccer's kick-off,
        jcs bs_shot             ; and so no set piece waits for ever)
        ldy rs_kind
        cpy #R_KICKOFF
        beq bs_pass             ; a kick-off: passed
        cpy #R_THROW
        bne @corner
        lda br_r                ; a throw-in: 1 in 16 long, if he faces
        and #$0F                ; that way (c14d1c)
        bne bs_pass
        jsr thr_ok
        bcc bs_pass
        jmp bs_shot
@corner:
        cpy #R_CORNER
        bne @free
        jsr bs_along            ; a corner: crossed along the goal line,
        cmp o_dir,x             ; in front of the goal, as on the C64
        bne :+
        lda br_t
        bne @none
        lda game_min            ; (lifted, not bent - by the minute, the
        and #3                  ; clock standing: 0 low and hard, 2 high
        cmp #3                  ; to the far post, else lifted - Luca: it
        bne :+                  ; knew one way only)
        lda #1
:       jsr br_kick
        lda #0
        sta br_70
        rts
:       jmp br_stick
@free:  cpy #R_FREE
        bne bs_shot             ; a goal kick, the keeper's: long
        lda br_r                ; a free kick: 15 in 16 shot facing the
        and #$0F                ; goal (else turned to it), 1 in 16
        beq bs_pass             ; passed
        jsr goal_dir
        cmp o_dir,x
        beq bs_shot
        jmp br_stick

; bs_along: A = the way along the goal line towards the goal - right in
; a corner on the left, left on the right. Keeps X.
bs_along:
        jsr ball_rx
        lda #2
        bcc :+
        lda #6
:       rts

; dir_th: A = the way (0-7) angle z_th faces: ((128 - theta) + 16) / 32;
; goal_dir: the way from the ball to the goal (br_g); dir_a: angle A's.
; Keep X, Y.
dir_th: lda #128
        sec
        sbc z_th
        .byte $2C               ; (bit abs: over lda br_g)
goal_dir:
        lda br_g
dir_a:
        clc
        adc #16
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        rts

; bs_pass (c14d88): passed if the one nearest the ball the way he faces
; is a team-mate, else he turns on looking (bs_turn)
bs_pass:
        jsr br_cone
        bcs bs_turn
        jeq br_pass
; bs_turn (c14dd0): 1 frame in 8 he turns a way on, the way he turns
; looking, as far as he may - then back the other way
bs_turn:
        jsr rnd                 ; (1 in 8 a frame)
        ldy pic_n
        cmp chance_8 - 1,y
        bcs @no
        lda o_dir,x
        clc
        adc bs_rot
        and #7
        sta br_w
        jsr may_face
        bcs :+
        lda br_w
        jmp br_stick
:       lda bs_rot              ; (as far as he may: back)
        eor #$FE
        sta bs_rot
@no:    rts

; bs_shot (c14d7a, c151c4): a set piece kicked hard: a free kick by how
; far the goal is (0 under 28800, 1 under 57800, else 2: lifted), a goal
; kick or the keeper's low (1); the rest 3 in 4 by how far, else lifted
bs_shot:
        lda br_t                ; (not if it kicked a moment ago)
        bne @no
        ldy rs_kind
        cpy #R_GOALKICK
        beq @low
        cpy #R_KEEPER
        beq @low
        cpy #R_FREE
        beq @far
        lda br_r
        and #$18
        beq @high
@far:   lda d6
        cmp #<(28800 / 16)
        lda d6 + 1
        sbc #>(28800 / 16)
        bcc @shot
        lda d6
        cmp #<(57800 / 16)
        lda d6 + 1
        sbc #>(57800 / 16)
        bcc @low
@high:  lda #2
        jmp br_kick
@low:   lda #1
        jmp br_kick
@shot:  lda #0
        jmp br_kick
@no:    rts

; thr_ok (c14c3a, c128d2, c154a2): carry set if the taker X of a
; throw-in faces one of the two ways its place throws long - by the touch
; line, three bands along it (y from 262, from 476), for a team attacking
; up: on the left touch line right and down-right in the band nearest the
; goal attacked, up-right and right in the middle, up and up-right in its
; own; on the right the same the other way round; attacking down all
; upside down. Keeps X.
thr_ok:
        ldy #0
        lda o_yl + BALL
        cmp #<262
        lda o_yh + BALL
        sbc #>262
        bcc @side
        iny
        lda o_yl + BALL
        cmp #<476
        lda o_yh + BALL
        sbc #>476
        bcc @side
        iny
@side:  jsr ball_rx             ; (carry set: the right touch line)
        bcc :+
        iny
        iny
        iny
:       lda me                  ; (attacking down)
        eor flip
        beq :+
        tya
        clc
        adc #6
        tay
:       lda thr_ways,y
        ldy o_dir,x
        iny
:       lsr a                   ; (bit o_dir into the carry)
        dey
        bne :-
        rts

; br_stick: pj = the stick way A (0-7). Keeps X.
br_stick:
        tay
        lda dir_bits,y
        sta pj
        rts

; facing: A = player X's way * 32 - br_g, the way to the goal (signed,
; 256 round). Keeps X.
facing:
        lda o_dir,x
        asl a
        asl a
        asl a
        asl a
        asl a
        sec
        sbc br_g
        rts

; br_opp: carry clear if cyan player Y is near the ball - Z set within
; 800 (squared), clear within 5000 - carry set if not or none. Keeps X.
br_opp:
        tya
        bmi @no
        jsr dist_y
        lda tmp + 1
        cmp #>5000
        bcc :+
        bne @no
        lda tmp
        cmp #<5000
        bcs @no
:       lda tmp
        cmp #<800
        lda tmp + 1
        sbc #>800
        lda #1
        bcs :+
        lda #0
:       clc
        rts
@no:    sec
        rts

; br_cone (c15508): the player nearest the ball, of either team (not
; player X, not one sliding or down), within 16 (of 256) of the way X
; faces from it: carry set none, else Z set if he is X's team-mate.
; Keeps X.
br_cone:
        stx z_obj
        lda #$FF
        sta mate
        sta mate_d
        sta mate_d + 1
        ldx #PLAYERS - 1
@look:  cpx z_obj
        jeq @next
        lda o_slide,x
        jne @next
        lda o_off,x             ; (mate_dist, closer: in line - given up
        jne @next               ; once |dx| squared alone is no nearer than
        jsr ball_dx             ; the nearest so far, as switch; one far
        jcs @next               ; off: never the nearest that way)
        lda sq8_lo,y
        sta mate_t
        cmp mate_d
        lda sq8_hi,y
        sta mate_t + 1
        sbc mate_d + 1
        jcs @next
        jsr ball_dy
        jcs @next
        jsr sq_add
        jcs @next
        cmp #$FF                ; (from $FF00 on: as far off)
        jeq @next
        lda tmp
        cmp mate_d
        lda tmp + 1
        sbc mate_d + 1
        jcs @next
        jsr near45              ; (more than 45 degrees off: never in it)
        bcs @next
        lda tmp                 ; his way from the ball
        pha
        lda tmp + 1
        pha
        jsr mate_way
        sta br_w
        pla
        sta tmp + 1
        pla
        sta tmp
        bcs @next
        ldy z_obj
        lda o_dir,y
        asl a
        asl a
        asl a
        asl a
        asl a
        sec
        sbc br_w
        clc
        adc #16
        cmp #33
        bcs @next
        lda tmp
        sta mate_d
        lda tmp + 1
        sta mate_d + 1
        stx mate
@next:  dex
        jpl @look
        ldx z_obj
        lda mate
        bmi @none
        cmp #11                 ; (his team-mate: the same side of 11)
        lda #0
        rol a
        sta br_n
        cpx #11
        lda #0
        rol a
        eor br_n
        clc
        rts
@none:  sec
        rts

; near45: carry clear if player X is within 45 degrees of the way player
; z_obj faces, seen from the ball (under 256 off it either way, as
; mate_dist found) - a look that costs no angle: br_cone's cone (22.5
; degrees either side) lies inside it. Keeps X.
near45:
        lda o_xl,x              ; dx, dy from the ball to him (z_ax, z_ay:
        sec                     ; angle's, worked out anew after), and
        sbc o_xl + BALL         ; their sizes (z_sx, z_sy)
        sta z_ax
        lda o_xh,x
        sbc o_xh + BALL
        sta z_ax + 1
        lda z_ax
        ldy z_ax + 1
        bpl :+
        eor #$FF
        clc
        adc #1
:       sta z_sx
        lda o_yl,x
        sec
        sbc o_yl + BALL
        sta z_ay
        lda o_yh,x
        sbc o_yh + BALL
        sta z_ay + 1
        lda z_ay
        ldy z_ay + 1
        bpl :+
        eor #$FF
        clc
        adc #1
:       sta z_sy
        ldy z_obj
        lda o_dir,y
        tay
        beq @up
        dey
        beq @ur
        dey
        beq @right
        dey
        beq @dr
        dey
        beq @down
        dey
        beq @dl
        dey
        beq @left
        lda z_ax + 1            ; up left: dx < 0, dy < 0
        bpl @no
        lda z_ay + 1
        bpl @no
        bmi @yes
@up:    lda z_ay + 1            ; up: dy < 0, |dy| > |dx|
        bpl @no
        lda z_sx
        cmp z_sy
        bcc @yes
        bcs @no
@ur:    lda z_ay + 1            ; up right: dy < 0, dx > 0
        bpl @no
        lda z_ax + 1
        bmi @no
        lda z_sx
        bne @yes
        beq @no
@right: lda z_ax + 1            ; right: dx > 0, |dx| > |dy|
        bmi @no
        lda z_sy
        cmp z_sx
        bcc @yes
        bcs @no
@dr:    lda z_ax + 1            ; down right: dx > 0, dy > 0
        bmi @no
        lda z_ay + 1
        bmi @no
        lda z_sx
        beq @no
        lda z_sy
        bne @yes
        beq @no
@down:  lda z_ay + 1            ; down: dy > 0, |dy| > |dx|
        bmi @no
        lda z_sx
        cmp z_sy
        bcc @yes
        bcs @no
@dl:    lda z_ax + 1            ; down left: dx < 0, dy > 0
        bpl @no
        lda z_ay + 1
        bmi @no
        lda z_sy
        bne @yes
@no:    sec
        rts
@left:  lda z_ax + 1            ; left: dx < 0, |dx| > |dy|
        bpl @no
        lda z_sy
        cmp z_sx
        bcs @no
@yes:   clc
        rts

; goal_way: br_g = the way from the ball to the goal it attacks (as
; the way a player faces, * 32), d6 the distance squared / 16 (from the
; quarter distances: under 256 either way). Keeps X.
goal_way:
        lda #<304
        sec
        sbc o_xl + BALL
        sta z_ax
        lda #>304
        sbc o_xh + BALL
        sta z_ax + 1
        lda me                  ; (the goal: the top one, 49, the cyan
        eor flip                ; team's before the sides change; else
        beq :+                  ; 689)
        lda #<689
        ldy #>689
        bne :++
:       lda #<49
        ldy #>49
:       sec
        sbc o_yl + BALL
        sta z_ay
        tya
        sbc o_yh + BALL
        sta z_ay + 1
        ldy z_ax + 1
        lda z_ax
        jsr quarter
        lda sq8_lo,y
        sta d6
        lda sq8_hi,y
        sta d6 + 1
        ldy z_ay + 1
        lda z_ay
        jsr quarter
        lda sq8_lo,y
        clc
        adc d6
        sta d6
        lda sq8_hi,y
        adc d6 + 1
        sta d6 + 1
        jsr angle
        lda #128
        sec
        sbc z_th
        sta br_g
        rts

; quarter: Y = |Y:A| / 4 (under 1024). Keeps X.
quarter:
        sty sq_h
        cpy #$80
        bcc :+
        eor #$FF
        clc
        adc #1
        pha
        lda sq_h
        eor #$FF
        adc #0
        sta sq_h
        pla
:       lsr sq_h
        ror a
        lsr sq_h
        ror a
        tay
        rts

; ball_way: A = the way (0-7) from player X to the ball. Keeps X.
ball_way:
        lda o_xl + BALL
        sec
        sbc o_xl,x
        sta z_ax
        lda o_xh + BALL
        sbc o_xh,x
        sta z_ax + 1
        lda o_yl + BALL
        sec
        sbc o_yl,x
        sta z_ay
        lda o_yh + BALL
        sbc o_yh,x
        sta z_ay + 1
        jsr angle
        lda #128 + 16
        sec
        sbc z_th
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        rts

; each way's joystick bits
; spot's: the bands (sp_kind: a throw-in's, a free kick's attacking up,
; down), the free kick's columns; Sensible Soccer's places at set pieces
; (sp_lo, sp_hi: by the kind, the team taking it's, then the other's 21
; on; 0 none)
sp_yl:      .byte <262, <476, <136, <251, <487, <603
sp_yh:      .byte >262, >476, >136, >251, >487, >603
fk_xl:      .byte <121, <229, <277, <330, <378, <486
fk_xh:      .byte >121, >229, >277, >330, >378, >486
sp_lo:  .byte 0, <sp_t1, <sp_t2, <sp_t3, <sp_t4, <sp_t5, <sp_t6, <sp_t7, <sp_t8, <sp_t9, <sp_ta, <sp_tb, <sp_tc, 0, <sp_te, <sp_tf, <sp_t10, <sp_t11, <sp_t12, <sp_t13, <sp_t14
        .byte 0, <sp_d1, <sp_d2, <sp_d3, <sp_d4, <sp_d5, <sp_d6, <sp_d7, <sp_d8, <sp_d9, <sp_da, <sp_db, <sp_dc, 0, <sp_de, 0, 0, 0, 0, 0, 0
sp_hi:  .byte 0, >sp_t1, >sp_t2, >sp_t3, >sp_t4, >sp_t5, >sp_t6, >sp_t7, >sp_t8, >sp_t9, >sp_ta, >sp_tb, >sp_tc, 0, >sp_te, >sp_tf, >sp_t10, >sp_t11, >sp_t12, >sp_t13, >sp_t14
        .byte 0, >sp_d1, >sp_d2, >sp_d3, >sp_d4, >sp_d5, >sp_d6, >sp_d7, >sp_d8, >sp_d9, >sp_da, >sp_db, >sp_dc, 0, >sp_de, 0, 0, 0, 0, 0, 0
sp_t1:  ; taker: goal kick, its right
        .word $000
        .byte 145,3, 50,55, 100,44, 150,44, 200,55, 50,118, 100,92, 150,92, 200,118, 100,148, 150,148
sp_t2:  ; taker: goal kick, its left
        .word $000
        .byte 105,3, 50,55, 100,44, 150,44, 200,55, 50,118, 100,92, 150,92, 200,118, 100,148, 150,148
sp_t3:  ; taker: the keeper's ball
        .word $001
        .byte 0,0, 50,55, 100,44, 150,44, 200,55, 50,118, 100,92, 150,92, 200,118, 100,148, 150,148
sp_t4:  ; taker: corner, its right
        .word $000
        .byte 125,2, 50,200, 100,92, 150,92, 245,200, 75,167, 125,200, 175,167, 225,185, 105,204, 145,204
sp_t5:  ; taker: corner, its left
        .word $000
        .byte 125,2, 5,200, 100,92, 150,92, 200,92, 25,185, 75,167, 125,200, 175,167, 105,204, 145,204
sp_t6:  ; taker: free kick, column 0 from its right
        .word $180
        .byte 125,2, 255,255, 255,255, 255,255, 255,255, 80,174, 150,167, 226,231, 0,241, 120,204, 140,202
sp_t7:  ; taker: free kick, column 1 from its right
        .word $180
        .byte 125,2, 255,255, 255,255, 255,255, 255,255, 80,174, 125,137, 226,231, 0,241, 120,204, 140,204
sp_t8:  ; taker: free kick, column 2 from its right
        .word $180
        .byte 125,2, 255,255, 255,255, 255,255, 255,255, 80,174, 125,137, 226,231, 0,241, 120,204, 140,204
sp_t9:  ; taker: free kick, column 3 from its right
        .word $7E0
        .byte 125,2, 255,255, 255,255, 255,255, 255,255, 166,20, 221,221, 20,196, 120,30, 236,246, 40,241
sp_ta:  ; taker: free kick, column 4 from its right
        .word $060
        .byte 125,2, 255,255, 255,255, 255,255, 255,255, 0,241, 30,231, 125,137, 170,174, 110,204, 130,204
sp_tb:  ; taker: free kick, column 5 from its right
        .word $060
        .byte 125,2, 255,255, 255,255, 255,255, 255,255, 0,241, 30,231, 125,137, 170,174, 110,204, 130,204
sp_tc:  ; taker: free kick, column 6 from its right
        .word $060
        .byte 125,2, 255,255, 255,255, 255,255, 255,255, 0,241, 30,231, 100,167, 170,174, 110,202, 130,204
sp_te:  ; taker: penalty
        .word $000
        .byte 125,2, 50,92, 100,92, 150,92, 200,92, 50,167, 100,167, 150,167, 200,167, 110,185, 125,174
sp_tf:  ; taker: throw-in, its right, band 0 from its goal
        .word $198
        .byte 255,255, 255,255, 255,255, 181,0, 231,0, 255,255, 255,255, 181,50, 206,75, 255,255, 255,255
sp_t10:  ; taker: throw-in, its right, band 1 from its goal
        .word $5C0
        .byte 255,255, 255,255, 255,255, 255,255, 255,255, 255,255, 156,25, 181,236, 231,231, 255,255, 181,75
sp_t11:  ; taker: throw-in, its right, band 2 from its goal
        .word $1C0
        .byte 255,255, 255,255, 255,255, 255,255, 255,255, 255,255, 181,206, 181,0, 231,0, 255,255, 255,255
sp_t12:  ; taker: throw-in, its left, band 0 from its goal
        .word $066
        .byte 255,255, 25,0, 75,0, 255,255, 255,255, 75,50, 50,75, 255,255, 255,255, 255,255, 255,255
sp_t13:  ; taker: throw-in, its left, band 1 from its goal
        .word $4E0
        .byte 255,255, 255,255, 255,255, 255,255, 255,255, 25,231, 75,236, 100,25, 255,255, 255,255, 75,75
sp_t14:  ; taker: throw-in, its left, band 2 from its goal
        .word $0E0
        .byte 255,255, 255,255, 255,255, 255,255, 255,255, 25,0, 75,0, 75,206, 255,255, 255,255, 255,255
sp_d1:  ; the other team: goal kick, its right
        .word $000
        .byte 125,4, 50,48, 100,48, 150,48, 200,48, 50,81, 100,92, 150,92, 200,81, 100,148, 150,148
sp_d2:  ; the other team: goal kick, its left
        .word $000
        .byte 125,4, 50,48, 100,48, 150,48, 200,48, 50,81, 100,92, 150,92, 200,81, 100,148, 150,148
sp_d3:  ; the other team: the keeper's ball
        .word $000
        .byte 125,4, 50,48, 100,48, 150,48, 200,48, 50,81, 100,92, 150,92, 200,81, 100,148, 150,148
sp_d4:  ; the other team: corner, its right
        .word $000
        .byte 125,1, 88,13, 112,7, 138,7, 162,13, 75,37, 100,18, 150,28, 200,55, 100,100, 150,100
sp_d5:  ; the other team: corner, its left
        .word $000
        .byte 125,1, 88,13, 112,7, 138,7, 162,13, 50,55, 100,28, 150,18, 175,37, 100,100, 150,100
sp_d6:  ; the other team: free kick, column 0 from its right
        .word $006
        .byte 125,1, 43,219, 48,227, 140,9, 105,7, 95,7, 125,9, 170,17, 170,29, 255,255, 255,255
sp_d7:  ; the other team: free kick, column 1 from its right
        .word $01E
        .byte 125,1, 30,215, 37,220, 43,225, 48,230, 100,7, 125,11, 140,13, 155,4, 255,255, 255,255
sp_d8:  ; the other team: free kick, column 2 from its right
        .word $01E
        .byte 125,1, 14,203, 23,206, 31,209, 38,212, 100,7, 125,11, 140,13, 155,4, 255,255, 255,255
sp_d9:  ; the other team: free kick, column 3 from its right
        .word $1FE
        .byte 125,1, 241,202, 251,201, 5,201, 15,202, 176,20, 206,201, 60,211, 70,40, 255,255, 255,255
sp_da:  ; the other team: free kick, column 4 from its right
        .word $01E
        .byte 125,1, 218,212, 225,209, 233,206, 242,203, 95,4, 110,13, 125,11, 150,7, 255,255, 255,255
sp_db:  ; the other team: free kick, column 5 from its right
        .word $01E
        .byte 125,1, 208,230, 213,225, 219,220, 226,215, 95,4, 110,13, 125,11, 150,7, 255,255, 255,255
sp_dc:  ; the other team: free kick, column 6 from its right
        .word $018
        .byte 125,1, 145,7, 110,9, 208,227, 213,219, 80,29, 80,17, 125,9, 155,7, 255,255, 255,255
sp_de:  ; the other team: penalty
        .word $000
        .byte 125,1, 88,29, 112,41, 138,41, 162,29, 35,52, 100,55, 150,55, 215,52, 75,100, 150,100
; thr_ways: the ways a throw-in goes long from (thr_ok), a bit each (0
; up, 2 right): attacking up, the left touch line's bands from the top,
; then the right's; attacking down the same (Sensible Soccer's c154a2,
; for the other team its nibbles swapped)
thr_ways:   .byte $0C, $06, $03, $60, $C0, $81
            .byte $18, $0C, $06, $30, $60, $C0
dir_bits:   .byte J_UP, J_UP | J_RIGHT, J_RIGHT, J_DOWN | J_RIGHT
            .byte J_DOWN, J_DOWN | J_LEFT, J_LEFT, J_UP | J_LEFT

shot_dyl:   .byte <1000, <(-1000)
shot_dyh:   .byte >1000, >(-1000)
