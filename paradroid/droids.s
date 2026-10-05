; droids.s - the player, the droids of a deck, shots and explosions
;
; The original's rules. Every droid has up to 64 energy and gets one back
; every four ticks (the command cyborg two). The player only at an
; energizer, and only up to a limit that sinks while he stays in a host:
; by one every 128, 64, 32 or 16 ticks, by the host's class. When it
; reaches nothing, so does he.
;
; In assembly, as all of the game, to make room: everything the game
; keeps is in the program. The droids' ways are engine.s's, the player's drive,
; walls, doors and bumps move.s's.

        .export _nd, _d_type, _d_x, _d_y, _d_vx, _d_vy, _d_energy, _d_boom
        .export _d_bx, _d_by, _d_wait, _s_x, _s_y, _s_life, _s_img
        .export _score, _score_changed, _transfer_mode, _touched
        .export _player_dead, _burn, _alert_acc, _flash, _dbg_god
        .export _spawn_droids, _remove_droid, _player_fire, _move_shots
        .export _droids_fire, _collide, _energy_tick, _take_over
        .export _transfer_lost, _burnt_out

        .import _sound, _rnd, _solid_at, _blk_at, _bump_next, _bump_back
        .import _bump_i, _player_picture, pushax
        .import _ship, _deck, _level, _tick
        .import _wp_first, _wp_x, _wp_y, _dr_class, _dr_weapon, _blk_flag
        .import _d_seen

        .include "game.inc"
        .include "data.inc"

        .bss
_nd:            .res 1          ; droids on this deck, 0 = player
_d_type:        .res MAXD
_d_x:           .res 2 * MAXD   ; world pixels, the middle
_d_y:           .res 2 * MAXD
_d_vx:          .res MAXD
_d_vy:          .res MAXD
_d_energy:      .res MAXD
_d_boom:        .res MAXD
_d_bx:          .res MAXD       ; block of each droid
_d_by:          .res MAXD
d_slot:         .res MAXD       ; where in ship[deck]
_d_wait:        .res MAXD
d_cool:         .res MAXD       ; ticks until it may fire again
_s_x:           .res 2 * MAXS
_s_y:           .res 2 * MAXS
s_vx:           .res MAXS
s_vy:           .res MAXS
_s_life:        .res MAXS
_s_img:         .res MAXS
s_own:          .res MAXS
s_dmg:          .res MAXS
_score:         .res 4
_score_changed: .res 1
_transfer_mode: .res 1
_touched:       .res 1
_player_dead:   .res 1
_burn:          .res 1          ; the player's energy limit
_alert_acc:     .res 1          ; kills by type, slowly forgotten
_flash:         .res 1          ; ticks the deck stays lit (the disruptor)
_dbg_god:       .res 1          ; tests: the player takes no damage
bumped:         .res 1          ; the droid bumped last
; working values
di:     .res 1                  ; a droid
dj:     .res 1                  ; disrupt()'s (its callers loop over di)
dk:     .res 1                  ; a shot, a slot
dt:     .res 1
dw:     .res 1                  ; a weapon
ddx:    .res 1                  ; a direction, -1 0 1
ddy:    .res 1
dfrom:  .res 1
hi_i:   .res 1                  ; hit(): whom, how much, by the player
hi_d:   .res 1
hi_p:   .res 1
step:   .res 1
sx:     .res 2                  ; a shot on its way
sy:     .res 2
sbx:    .res 1
sby:    .res 1
adx:    .res 2                  ; droids_fire(): from the droid to the player
ady:    .res 2

        .rodata
burn_mask:  .byte 127, 63, 63, 63, 63, 31, 31, 31, 31, 15
kill_pts:   .byte 0, 10, 20, 30, 40, 50, 60, 70, 80, 200
take_pts:   .byte 0, 25, 50, 75, 100, 125, 150, 175, 200, 250
alert_pts:  .byte 0, 5, 10, 25
; types the disruptor does not touch: 420, 711, 742, 821, 999
no_disrupt: .byte 8, 17, 18, 20, 23
; damage of a droid's shot, by weapon; the player's depends on the target
; as well (pdamage)
wdamage:    .byte 0, 8, 16, 16
; a shot's picture by direction (dx + 1) + 3 * (dy + 1): | / - \
shot_img:   .byte 3, 0, 1,  2, 0, 2,  1, 0, 3
; a shot's start by direction -1, 0, 1: 20 across, 14 up or down
off20:      .byte <-20, 0, 20
off14:      .byte <-14, 0, 14
offhi:      .byte $FF, 0, 0

        .code

; points(A): onto the score
points: clc
        adc _score
        sta _score
        bcc @done
        inc _score + 1
        bne @done
        inc _score + 2
        bne @done
        inc _score + 3
@done:  lda #1
        sta _score_changed
        rts

; C set if the score is at least A
score_ge:
        sta lo8
        lda _score+1
        ora _score+2
        ora _score+3
        bne :+
        lda _score
        cmp lo8
        rts
:       sec
        rts

; the score less A (it is at least A)
score_sub:
        sta lo8
        lda _score
        sec
        sbc lo8
        sta _score
        ldx #0
        ldy #3
:       lda _score+1,x
        sbc #0
        sta _score+1,x
        inx
        dey
        bne :-
        rts

; Y := ship[deck] index of droid X's slot
shipx:  lda _deck               ; deck * 12
        asl a
        asl a
        sta dt
        asl a
        adc dt
        adc d_slot,x
        tay
        rts

; A := 32 - 2 * the class of droid X's type: its time between shots
cool_of:
        ldy _d_type,x
        lda _dr_class,y
        asl a
        eor #$FF
        sec
        adc #32
        rts

; ======================================================================
; Droids on a deck
; ======================================================================

; spawn_droids(): the deck's droids on its waypoints, after the first
_spawn_droids:
        lda #1
        sta _nd
        ldx _deck
        lda _wp_first,x
        sta dw                  ; w0
        lda _wp_first+1,x
        sec
        sbc dw
        sta dt                  ; wn
        lda #0
        sta dk
@k:     jsr shipk
        lda _ship,y
        bne :+
        jmp @next
:
        ldx _nd
        sec
        sbc #1
        sta _d_type,x
        lda dk                  ; w = k + 1, else k % wn
        clc
        adc #1
        cmp dt
        bcc :+
        lda dk
@mod:   cmp dt
        bcc :+
        sbc dt
        bcs @mod
:       clc
        adc dw
        tay
        txa
        asl a
        tax
        lda #0                  ; d_x, d_y: the waypoint's, times 8
        sta hi8
        lda _wp_x,y
        asl a
        rol hi8
        asl a
        rol hi8
        asl a
        rol hi8
        sta _d_x,x
        lda hi8
        sta _d_x+1,x
        lda #0
        sta hi8
        lda _wp_y,y
        asl a
        rol hi8
        asl a
        rol hi8
        asl a
        rol hi8
        sta _d_y,x
        lda hi8
        sta _d_y+1,x
        ldx _nd
        lda #0
        sta _d_vx,x
        sta _d_vy,x
        sta _d_wait,x
        sta _d_boom,x
        lda dk
        sta d_slot,x
        lda #64
        sta _d_energy,x
        jsr _rnd
        and #31
        clc
        adc #16
        ldx _nd
        sta d_cool,x
        inc _nd
@next:  inc dk
        lda dk
        cmp #12
        beq :+
        jmp @k
:
        lda #0
        ldx #MAXS - 1
:       sta _s_life,x
        dex
        bpl :-
        sta _d_boom
        sta _transfer_mode
        sta _touched
        rts

; Y := ship[deck] index of slot dk
shipk:  lda _deck
        asl a
        asl a
        sta hi8
        asl a
        adc hi8
        adc dk
        tay
        rts

        .bss
hi8:    .res 1
lo8:    .res 1
        .code

; remove_droid(i): gone from the deck and the ship
_remove_droid:
        tax
        lda #BOOM_GONE
        sta _d_boom,x
gone:   jsr shipx
        lda #0
        sta _ship,y
        rts

; ======================================================================
; Shots
; ======================================================================

; shoot(): a shot from droid di in direction ddx, ddy with weapon dw
shoot:  ldx #0
:       lda _s_life,x
        beq @free
        inx
        cpx #MAXS
        bne :-
        rts
@free:  stx dk
        lda di
        asl a
        sta dt                  ; the droid's word index
        txa
        asl a
        tax                     ; the shot's
        ldy ddx                 ; x + 20 * dx
        iny
        lda off20,y
        sta lo8
        lda offhi,y
        sta hi8
        ldy dt
        clc
        lda lo8
        adc _d_x,y
        sta _s_x,x
        lda hi8
        adc _d_x+1,y
        sta _s_x+1,x
        ldy ddy                 ; y + 14 * dy
        iny
        lda off14,y
        sta lo8
        lda offhi,y
        sta hi8
        ldy dt
        clc
        lda lo8
        adc _d_y,y
        sta _s_y,x
        lda hi8
        adc _d_y+1,y
        sta _s_y+1,x
        ldx dk
        lda ddx
        asl a
        asl a
        sta s_vx,x
        lda ddy
        asl a
        asl a
        sta s_vy,x
        lda #14
        sta _s_life,x
        lda di
        sta s_own,x
        ldy dw
        lda wdamage,y
        sta s_dmg,x
        lda ddy                 ; the picture: 3 * (dy + 1) + dx + 1
        clc
        adc #1
        sta dt
        asl a
        adc dt
        sec
        adc ddx
        tay
        lda shot_img,y
        sta _s_img,x
        lda di                  ; the player's sounds by the weapon, as
        bne @quiet              ; the original's; the droids' are silent
        ldy _d_type
        lda _dr_weapon,y
        clc
        adc #SFX_SHOT1
        jmp _sound
@quiet: rts

; immune(A): Z clear (A nonzero) if type A is one the disruptor spares
immune: ldx #4
:       cmp no_disrupt,x
        beq @yes
        dex
        bpl :-
        lda #0
        rts
@yes:   lda #1
        rts

; disrupt(): a flash that hurts every droid in sight but a few types,
; fired by droid dfrom; by a droid, the player too. Keeps di.
disrupt:
        lda #3
        sta _flash
        lda #SFX_DBOOM
        jsr _sound
        lda #1
        sta dj
@i:     ldx dj
        cpx _nd
        bcc :+
        jmp @player
:       cpx dfrom
        beq @nx
        lda _d_boom,x
        bne @nx
        lda _d_seen,x           ; (only those in sight: sight.s)
        beq @nx
        lda _d_type,x
        jsr immune
        beq @body
@nx:    jmp @next
@body:  lda dj
        asl a
        tay
        sec                     ; (d_x - PX + 160) <= 320
        lda _d_x,y
        sbc _d_x
        sta sx
        lda _d_x+1,y
        sbc _d_x+1
        sta sx+1
        lda sx
        clc
        adc #160
        sta sx
        bcc :+
        inc sx+1
:       lda sx+1
        cmp #>321
        bcc :+
        bne @next
        lda sx
        cmp #<321
        bcs @next
:       sec                     ; (d_y - PY + 80) <= 160
        lda _d_y,y
        sbc _d_y
        sta sy
        lda _d_y+1,y
        sbc _d_y+1
        sta sy+1
        lda sy
        clc
        adc #80
        sta sy
        bcc :+
        inc sy+1
:       lda sy+1
        bne @next
        lda sy
        cmp #161
        bcs @next
        ldx dj                  ; (40 - type) * 2
        lda _d_type,x
        sta dt
        lda #40
        sec
        sbc dt
        asl a
        sta hi_d
        stx hi_i
        ldy #0
        lda dfrom
        bne :+
        iny
:       sty hi_p
        jsr hit
@next:  inc dj
        jmp @i
@player:
        lda dfrom
        beq @done
        lda _d_type
        jsr immune
        bne @done
        lda #32                 ; 32 + level - type, if more than none
        clc
        adc _level
        sec
        sbc _d_type
        beq @done
        bmi @done
        sta hi_d
        lda #0
        sta hi_i
        sta hi_p
        jmp hit
@done:  rts

; player_fire(k): a shot or the disruptor, if fire is held with a
; direction and the weapon is ready
_player_fire:
        sta dt
        lda d_cool
        beq :+
        dec d_cool
:       lda dt
        and #K_FIRE
        beq @no
        lda dt
        and #K_UP | K_DOWN | K_LEFT | K_RIGHT
        beq @no
        lda d_cool
        bne @no
        ldx #0                  ; dx
        lda dt
        and #K_LEFT
        beq :+
        dex
        bne @y
:       lda dt
        and #K_RIGHT
        beq @y
        inx
@y:     stx ddx
        ldx #0
        lda dt
        and #K_UP
        beq :+
        dex
        bne @w
:       lda dt
        and #K_DOWN
        beq @w
        inx
@w:     stx ddy
        lda #0
        sta di
        sta dfrom
        ldy _d_type
        lda _dr_weapon,y
        sta dw
        cmp #3
        bne :+
        jsr disrupt
        jmp @cool
:       jsr shoot
@cool:  ldx #0
        jsr cool_of
        sta d_cool
@no:    rts

; hit(): droid hi_i takes hi_d, by the player if hi_p
hit:    ldx hi_i
        bne :+
        lda _dbg_god
        bne @done
:       lda hi_d
        beq @done
        lda _d_boom,x
        bne @done               ; (exploding already: it stays so)
        lda _d_energy,x
        cmp hi_d
        beq @dead
        bcc @dead
        sbc hi_d
        sta _d_energy,x
        lda #SFX_DHIT
        cpx #0
        bne :+
        lda #SFX_PHIT
:       jmp _sound
@dead:  lda #0
        sta _d_energy,x
        lda #1
        sta _d_boom,x
        cpx #0
        bne @droid
        sta _player_dead
        lda #0
        sta _d_vx
        sta _d_vy               ; the explosion stays where it is
        lda #SFX_PBOOM
        jmp _sound
@droid: jsr gone                ; off the ship
        lda hi_p
        beq @boom
        ldx hi_i
        ldy _d_type,x
        lda _dr_class,y
        tay
        lda kill_pts,y
        jsr points
        ldx hi_i                ; the alert: kills by type, up to 255
        lda _alert_acc
        clc
        adc _d_type,x
        bcc :+
        lda #255
:       sta _alert_acc
@boom:  lda #SFX_DBOOM
        jmp _sound
@done:  rts

; A := what a shot of the player's does to droid hi_i: 16 per class of his
; weapon and 80, less 4 per type of the droid - nothing below that
pdamage:
        ldy _d_type
        lda _dr_weapon,y
        asl a
        asl a
        clc
        adc #16
        ldx hi_i
        sec
        sbc _d_type,x
        bcc @none
        asl a
        asl a
        adc #16
        rts
@none:  lda #0
        rts

; move_shots(): every shot three steps on, or until it hits
_move_shots:
        lda #0
        sta dk
@k:     ldx dk
        lda _s_life,x
        bne :+
        jmp @next
:       dec _s_life,x
        txa
        asl a
        tay
        lda _s_x,y
        sta sx
        lda _s_x+1,y
        sta sx+1
        lda _s_y,y
        sta sy
        lda _s_y+1,y
        sta sy+1
        lda #3
        sta step
@step:  ldx dk
        lda _s_life,x
        bne :+
        jmp @store
:       ldy #0                  ; x += vx, y += vy (signed)
        lda s_vx,x
        bpl :+
        dey
:       clc
        adc sx
        sta sx
        tya
        adc sx+1
        sta sx+1
        ldy #0
        lda s_vy,x
        bpl :+
        dey
:       clc
        adc sy
        sta sy
        tya
        adc sy+1
        sta sy+1
        lda sx                  ; a wall?
        ldx sx+1
        jsr pushax
        lda sy
        ldx sy+1
        jsr _solid_at
        tax
        beq :+
        jmp @end
:       lda sx+1                ; its block: x >> 5, y >> 5
        sta sbx
        lda sx
        asl a
        rol sbx
        asl a
        rol sbx
        asl a
        rol sbx
        lda sy+1
        sta sby
        lda sy
        asl a
        rol sby
        asl a
        rol sby
        asl a
        rol sby
        lda #0
        sta di
        beq @j
@nj:    jmp @nextj
@j:     ldx di
        cpx _nd
        bcc :+
        jmp @nextstep
:       ldy dk
        txa
        cmp s_own,y
        beq @nj
        lda _d_boom,x
        bne @nj
        lda _d_bx,x             ; a block apart at most
        sec
        sbc sbx
        clc
        adc #1
        cmp #3
        bcs @nj
        lda _d_by,x
        sec
        sbc sby
        clc
        adc #1
        cmp #3
        bcs @nj
        txa
        asl a
        tay
        lda sx                  ; (x - d_x + 12) < 24
        sec
        sbc _d_x,y
        sta adx
        lda sx+1
        sbc _d_x+1,y
        sta adx+1
        lda adx
        clc
        adc #12
        tax
        lda adx+1
        adc #0
        bne @nextj
        cpx #24
        bcs @nextj
        lda sy                  ; (y - d_y + 8) < 16
        sec
        sbc _d_y,y
        sta ady
        lda sy+1
        sbc _d_y+1,y
        sta ady+1
        lda ady
        clc
        adc #8
        tax
        lda ady+1
        adc #0
        bne @nextj
        cpx #16
        bcs @nextj
        lda di                  ; a hit
        sta hi_i
        ldy dk
        lda s_own,y
        bne @droids
        jsr pdamage
        sta hi_d
        lda #1
        sta hi_p
        bne @hit
@droids:
        lda s_dmg,y
        sta hi_d
        lda #0
        sta hi_p
@hit:   jsr hit
@end:   ldx dk
        lda #0
        sta _s_life,x
        beq @store
@nextj: inc di
        jmp @j
@nextstep:
        dec step
        beq @store
        jmp @step
@store: lda dk
        asl a
        tay
        lda sx
        sta _s_x,y
        lda sx+1
        sta _s_x+1,y
        lda sy
        sta _s_y,y
        lda sy+1
        sta _s_y+1,y
@next:  inc dk
        lda dk
        cmp #MAXS
        beq :+
        jmp @k
:       rts

; droids_fire(): armed droids fire at the player when they have him in
; line
_droids_fire:
        lda #1
        sta di
@i:     ldx di
        cpx _nd
        bcc :+
        rts
:       lda _d_boom,x
        bne @next
        lda _d_seen,x           ; (only seen, as the original's: sight.s)
        beq @next
        ldy _d_type,x
        lda _dr_weapon,y
        beq @next
        sta dw
        lda d_cool,x
        beq :+
        dec d_cool,x
@next:  inc di
        bne @i
:       txa                     ; dx = PX - d_x, dy = PY - d_y
        asl a
        tay
        lda _d_x
        sec
        sbc _d_x,y
        sta adx
        lda _d_x+1
        sbc _d_x+1,y
        sta adx+1
        lda _d_y
        sec
        sbc _d_y,y
        sta ady
        lda _d_y+1
        sbc _d_y+1,y
        sta ady+1
        lda adx                 ; |dx| <= 150, |dy| <= 90
        ldx adx+1
        jsr absax
        bne @next
        cmp #151
        bcs @next
        sta sbx
        lda ady
        ldx ady+1
        jsr absax
        bne @next
        cmp #91
        bcs @next
        sta sby
        jsr _rnd                ; as the original: by the ship
        and #31
        sta dt
        lda _level
        clc
        adc #2
        cmp dt
        beq @next
        bcc @next
        lda di
        sta dfrom
        lda dw
        cmp #3
        bne @aim
        jsr disrupt
        jmp @cool
@aim:   ldx #1                  ; the directions: -1 or 1 by the signs
        lda adx+1
        bpl :+
        ldx #$FF
:       stx ddx
        ldx #1
        lda ady+1
        bpl :+
        ldx #$FF
:       stx ddy
        lda sbx                 ; in line across, down or diagonally
        cmp #10
        bcs :+
        lda #0
        sta ddx
        beq @shoot
:       lda sby
        cmp #10
        bcs :+
        lda #0
        sta ddy
        beq @shoot
:       lda sbx
        sec
        sbc sby
        clc
        adc #12
        cmp #24
        bcs @next2
@shoot: jsr shoot
@cool:  ldx di
        jsr cool_of
        ldx di
        sta d_cool,x
@next2: jmp @next

; A := |A/X| low byte, Z set if it fits in a byte
absax:  cpx #0
        bpl @pos
        eor #$FF
        clc
        adc #1
        pha
        txa
        eor #$FF
        adc #0
        tax
        pla
@pos:   cpx #0
        rts

; ======================================================================
; Touching droids, energy
; ======================================================================

; collide(): a droid touching the player: bumped, or in transfer mode
; taken for the transfer
_collide:
        lda #0
        sta _touched
        lda _d_boom
        bne @done               ; nothing pushes an explosion
        lda #0
        sta _bump_i
        jsr _bump_next
        tax
        bne :+
        sta bumped              ; apart: the next touch bumps
        rts
:       lda _transfer_mode
        beq :+
        stx _touched
        rts
:       cpx bumped
        beq @done               ; once, as long as they touch
        stx bumped
        stx hi_i
        txa
        jsr _bump_back          ; both thrown back (move.s)
        lda #SFX_BUMP
        jsr _sound
        ldx hi_i                ; the stronger hurts the weaker
        lda _d_type
        clc
        adc #2
        sec
        sbc _d_type,x
        bmi @weaker
        asl a
        sta hi_d
        lda #1
        sta hi_p
        jmp hit
@weaker:
        eor #$FF                ; (-d - 1) / 2
        lsr a
        sta hi_d
        lda #0
        sta hi_i
        sta hi_p
        jmp hit
@done:  rts

; energy_tick(): the limit sinking, energizers, droids recovering, the
; alert
_energy_tick:
        ldy _d_type             ; the limit sinks while in a host - and in
        ldx _dr_class,y         ; the device itself, slowly
        lda _tick
        and burn_mask,x
        bne @limit
        lda _burn
        beq @limit
        dec _burn
        bne @limit
        lda _dbg_god
        bne @limit
        lda #1
        sta _d_energy
        sta hi_d
        lda #0
        sta hi_i
        sta hi_p
        jsr hit
@limit: lda _dbg_god
        bne :+
        lda _burn
        cmp _d_energy
        bcs :+
        sta _d_energy
:       lda _tick
        and #3
        bne @alert
        lda _d_x                ; an energizer: a point of energy for five
        ldx _d_x+1              ; of score
        jsr pushax
        lda _d_y
        ldx _d_y+1
        jsr _blk_at
        tay
        lda _blk_flag,y
        and #B_ENERGY
        beq @droids
        lda _d_energy
        cmp _burn
        bcs @droids
        inc _d_energy
        lda #5
        jsr score_ge
        bcc @took
        lda #5
        jsr score_sub
@took:  lda #1
        sta _score_changed
        lda #SFX_ENERGY         ; each unit, as the original
        jsr _sound
@droids:
        ldx #1
@d:     cpx _nd
        bcs @alert
        lda _d_boom,x
        bne @nd
        lda _d_energy,x
        cmp #64
        bcs @nd
        adc #1                  ; (carry clear: below 64)
        ldy _d_type,x
        cpy #23                 ; the command cyborg: two
        bne :+
        clc
        adc #1
:       cmp #65
        bcc :+
        lda #64
:       sta _d_energy,x
@nd:    inx
        bne @d
@alert: lda _tick               ; kills are forgotten, and while it is up
        and #15                 ; it pays
        bne @flash
        lda _alert_acc
        beq :+
        dec _alert_acc
:       lda _alert_acc
        rol a
        rol a
        rol a
        and #3
        tay
        lda alert_pts,y
        beq @flash
        jsr points
@flash: lda _flash
        beq :+
        dec _flash
:       rts

; take_over(i): the player takes droid i over: it is his host now
_take_over:
        tax
        lda _d_type,x
        sta _d_type
        lda _d_energy,x
        sta _d_energy           ; it keeps what it had left
        lda #64
        sta _burn
        stx di
        ldy _d_type,x
        lda _dr_class,y
        tay
        lda take_pts,y
        jsr points
        lda di
        jsr _remove_droid
        jmp _player_picture

; transfer_lost(): a transfer lost from a host: the device on its own
; again, the host's kill points off the score (as the original)
_transfer_lost:
        ldy _d_type
        ldx _dr_class,y
        lda kill_pts,x
        sta dt
        jsr score_ge
        bcc @zero
        lda dt
        jsr score_sub
        jmp @done
@zero:  lda #0
        sta _score
@done:  lda #1
        sta _score_changed
        lda #0
        sta _d_type
        lda #64
        sta _burn
        jmp _player_picture

; burnt_out(): a transfer lost by the bare device: it burns out
_burnt_out:
        lda _dbg_god
        bne @done
        lda #0
        sta _d_energy
        lda #1
        sta _player_dead
        sta _d_boom
        lda #SFX_PBOOM
        jmp _sound
@done:  rts
