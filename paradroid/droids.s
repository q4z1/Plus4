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
        .export _d_bx, _d_by, _d_wait, _s_x, _s_y, _s_life, _s_img, _s_boom
        .export _clashes
        .export _score, _score_changed, _transfer_mode, _touched
        .export _player_dead, _burn, _alert_acc, _flash, _dbg_god
        .export _spawn_droids, _remove_droid, _player_fire, _move_shots
        .export _droids_fire, _collide, _energy_tick, _take_over
        .export _transfer_lost, _burnt_out

        .import _sound, _rnd, _solid_at, _blk_at, _bump_next, _bump_back
        .import _bump_i, _player_picture, pushax
        .import _ship, _deck, _level, _tick
        .import _wp_first, _wp_x, _wp_y, _dr_class, _dr_weapon, _blk_flag
        .import _d_seen, csolid, _player_spot
        .importzp tx, ty

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
_s_x:           .res 2 * MAXS
                .res 2 * (MAXD - MAXS)  ; (_s_y as far on as _d_y: spos)
_s_y:           .res 2 * MAXS
_s_life:        .res MAXS       ; a droid's: 255 on, hidden while 251 on
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

        .segment "LOWBSS"       ; (set before they are read: not cleared)
_d_bx:          .res MAXD       ; block of each droid
_d_by:          .res MAXD
d_slot:         .res MAXD       ; where in ship[deck]
_d_wait:        .res MAXD
d_cool:         .res MAXD       ; ticks until it may fire again
s_vx:           .res MAXS       ; a shot's step, signed
s_vy:           .res MAXS
_s_img:         .res MAXS
s_own:          .res MAXS       ; who fired it (0 the player)
s_dmg:          .res MAXS       ; what it does to the player
_s_boom:        .res MAXS       ; exploding: its step, 1-12, else 0
bx:     .res 2                  ; near()'s other place
by:     .res 2
lim:    .res 4                  ; near()'s reach: across, (at 2) down
ci:     .res 1                  ; clashes()'s
cj:     .res 1
ce:     .res 1
ct:     .res 1
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
adx:    .res 2                  ; move_shots(): from the shot to a droid
ady:    .res 2
ua:     .res 2                  ; dshoot(): sizes, across and down, then
us:     .res 2                  ; the speeds; the signs; the line's steps
uz:     .res 2

        .rodata
burn_mask:  .byte 127, 63, 63, 63, 63, 31, 31, 31, 31, 15
kill_pts:   .byte 0, 10, 20, 30, 40, 50, 60, 70, 80, 200
take_pts:   .byte 0, 25, 50, 75, 100, 125, 150, 175, 200, 250
alert_pts:  .byte 0, 5, 10, 25
; types the disruptor does not touch: 420, 711, 742, 821, 999
no_disrupt: .byte 8, 17, 18, 20, 23
; damage of a droid's shot to the player, by weapon: the original's by its
; pictures ($1AF6: those of weapon 1, $99-$9F, take 16, weapon 2's 8); the
; player's depends on the target as well (pdamage)
        .segment "XT8"
wdamage:    .byte 0, 16, 8
        .segment "XT9"
; onscr()'s limits, across and (at 2) down: added, then below
on_off:     .byte 240, 0, 128
on_hi:      .byte >576, 0, 0
on_lo:      .byte <576, 0, 216
        .rodata
; the player's shot's start by direction -1, 0, 1: 12 on, as the
; original's from its sprite ($33F8, table $6E58); the character it looks
; at for a wall there, from the player's own (less the 8 its place has
; while it shoots): 12 / 8 on, rounded down ($336F)
        .segment "UNPACK"       ; (copied to the end of $0200-$03FF at the
off12:      .byte <-12, 0, 12   ; start: their load image costs nothing)
offhi:      .byte $FF, 0, 0
        .segment "LOWEND"
offc:       .byte <-3, <-1, 0
        .rodata

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

        .segment "XT10"         ; ($E9E8)
; A := 32 - 2 * the class of droid X's type: its time between shots
cool_of:
        ldy _d_type,x
        lda _dr_class,y
        asl a
        eor #$FF
        sec
        adc #32
        rts
; a shot's picture by direction (dx + 1) + 3 * (dy + 1): | / - \
shot_img:   .byte 3, 0, 1,  2, 0, 2,  1, 0, 3
        .code

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
        sta d_cool,x            ; (ready, as the original's: $1672)
        lda dk
        sta d_slot,x
        lda #64
        sta _d_energy,x
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

; shoot(): the player's shot in direction ddx, ddy with weapon dw
shoot:  jsr free_shot
        bcs @none
        lda #0                  ; no shot if a wall is where it would
        tay                     ; start ($336F)
        tax
        jsr @pcol
        sta tx
        ldy #2 * MAXD           ; (d_y after d_x)
        jsr @pcol
        sta ty
        jsr csolid
        beq @start
        jmp @sound
@none:  rts
@pcol:  lda _d_x+1,y            ; X: the direction's character
        sta hi8
        lda _d_x,y
        lsr hi8
        ror a
        lsr hi8
        ror a
        lsr hi8
        ror a
        ldy ddx,x
        iny
        clc
        adc offc,y
        ldx #1                  ; (then ddy)
        rts
@start: ldx dk
        txa
        asl a
        tax                     ; the shot's
        ldy ddx                 ; x + 12 * dx
        iny
        lda off12,y
        sta lo8
        lda offhi,y
        sta hi8
        ldy #0
        clc
        lda lo8
        adc _d_x,y
        sta _s_x,x
        lda hi8
        adc _d_x+1,y
        sta _s_x+1,x
        ldy ddy                 ; y + 12 * dy
        iny
        lda off12,y
        sta lo8
        lda offhi,y
        sta hi8
        ldy #0
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
        lda #0
        sta s_own,x
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
@sound: ldy _d_type              ; its sound by the weapon, as the
        lda _dr_weapon,y        ; original's (the droids' are silent)
        clc
        adc #SFX_SHOT1
        jmp _sound

        .segment "HICODE"

        .segment "XT11"         ; ($EAE8)
; free_shot: dk := a free shot, C set if there is none
free_shot:
        ldx #0
:       lda _s_life,x
        beq @free
        inx
        cpx #MAXS
        bne :-
        rts                     ; (C set by cpx)
@free:  stx dk
        clc
        rts

        .segment "HICODE"
; dmg40: A := (40 - the type of droid X) * 2, what the disruptor and a
; droid's shot do to a droid ($1BF6, $2360)
dmg40:  lda #40
        sec
        sbc _d_type,x
        asl a
        rts

        .code

; dshoot(): droid di fires at the player, as the original's ($34B5): from
; where it is, the way the line of sight goes (sight.s, $24AE: the two
; distances in characters doubled while they fit a byte, then added to
; themselves while they still do), its speed that line's step over 32,
; signed, in pixels a tick - 4 to 7 along the longer way. Its picture by
; the speeds ($3530). The droid then waits 2 to 5 ticks and may fire again
; after 26 less its type.
dshoot: jsr free_shot
        bcs @none
        jsr _player_spot        ; (tx, ty: the player's character, one on
        dec tx                  ; while it is a character on: fig_place)
        dec ty
        lda di
        asl a
        tay
        ldx #0
@ax:    lda _d_x+1,y            ; the droid's character, less the player's
        sta hi8
        lda _d_x,y
        lsr hi8
        ror a
        lsr hi8
        ror a
        lsr hi8
        ror a
        sec
        sbc tx,x
        sta us,x
        bpl :+
        eor #$FF
        clc
        adc #1
:       sta ua,x
        sta uz,x
        tya
        clc
        adc #2 * MAXD
        tay
        inx
        cpx #2
        bne @ax
        lda ua
        ora ua+1
        bne @dbl
@none:  rts                     ; (the same character)
@dbl:   lda uz                  ; doubled while both fit
        asl a
        bcs @add
        tay
        lda uz+1
        asl a
        bcs @add
        sta uz+1
        sty uz
        bcc @dbl
@add:   lda uz                  ; added to while both fit
        clc
        adc ua
        bcs @v
        tay
        lda uz+1
        adc ua+1
        bcs @v
        sta uz+1
        sty uz
        bcc @add
@v:     ldx #1                  ; each way: -(the signed step >> 5), as 16
@vx:    lda #0                  ; bits; |speed| to ua
        sta hi8
        lda uz,x
        ldy us,x
        bpl :+
        eor #$FF
        clc
        adc #1
        dec hi8
:       ldy #5
:       lsr hi8
        ror a
        dey
        bne :-
        sta uz,x                ; (- speed)
        cmp #$80
        bcc :+
        eor #$FF
        adc #0                  ; (C set: + 1)
:       sta ua,x
        lda #0
        sec
        sbc uz,x
        sta uz,x                ; the speed
        dex
        bpl @vx
        lda ua                  ; the picture: up and down (|) if less
        cmp ua+1                ; across than down, across (-) if at least
        lda #0                  ; twice as much, else / or \ by the signs
        bcc @img
        lda ua
        sbc ua+1
        cmp ua+1
        lda #2
        bcs @img
        lda uz
        eor uz+1
        asl a
        lda #3                  ; (the same way: \)
        bcc @img
        lda #1
@img:   ldx dk
        sta _s_img,x
        lda uz
        sta s_vx,x
        lda uz+1
        sta s_vy,x
        lda #255
        sta _s_life,x
        lda di
        sta s_own,x
        ldy dw
        lda wdamage,y
        sta s_dmg,x
        txa
        asl a
        tax
        lda di
        asl a
        tay
        lda _d_x,y
        sta _s_x,x
        lda _d_x+1,y
        sta _s_x+1,x
        lda _d_y,y
        sta _s_y,x
        lda _d_y+1,y
        sta _s_y+1,x
        ldx di
        lda #$1A
        sec
        sbc _d_type,x
        sta d_cool,x
        jsr _rnd
        and #3
        clc
        adc #2
        ldx di
        sta _d_wait,x
        rts

        .segment "HICODE"
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
        .code

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
        jsr dmg40
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
        lda #SFX_PHIT
        cpx #0
        beq :+
        lda hi_p                ; a droid: only the player's fire sounds
        beq @done               ; ($1C0F; $1BF6 is silent)
        lda #SFX_DHIT
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
        .segment "HICODE"
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
        .code

; move_shots(): every shot on - the player's three steps, a droid's one,
; its own speed - or until it hits; a droid's hits nothing while hidden
; (its first four ticks: the original's sprite is off then) and is gone
; where the original would take its sprite away ($321E)
_move_shots:
        lda #0
        sta dk
@k:     ldx dk
        lda _s_life,x
        bne :+
        jmp @next
:       lda _s_boom,x
        beq :+
        jsr sboom               ; (exploding)
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
        ldy s_own,x
        beq :+
        lda #1
:       sta step
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
        ldx dk                  ; a droid's explodes there (the original's
        lda s_own,x             ; turns to a spark, $18B7)
        beq @gone
        jsr boom
        jmp @store
@gone:  jmp @end
:       ldx dk                  ; (hidden: it hits nothing)
        lda _s_life,x
        cmp #251
        bcc :+
        jmp @nextstep
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
        lda s_dmg,y             ; the player: by the weapon; a droid: as
        ldx di                  ; the disruptor ($1BF6)
        beq :+
        jsr dmg40
:       sta hi_d
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
        beq @last
        jmp @step
@last:  ldx dk
        lda s_own,x
        beq @store
        jsr onscr
        bcc @store
        ldx dk
        lda #0
        sta _s_life,x
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

; droids_fire(): armed droids in sight fire at the player, as the
; original's ($3450): by the ship (a chance of ship / 32 a tick), when
; ready, and when one of the original's six sprites is free - a disruptor
; by the ship over 128, when none flashes ($34A1). Every droid gets
; readier every tick ($1D45).
_droids_fire:
        lda #1
        sta di
@i:     ldx di
        cpx _nd
        bcc :+
        rts
:       lda _d_boom,x
        bne @next
        lda _d_seen,x           ; (sight.s)
        beq @next
        ldy _d_type,x
        lda _dr_weapon,y
        beq @next
        sta dw
        cmp #3
        bne @gun
        jsr _rnd
        and #$7F
        cmp _level
        bcs @next
        lda _flash
        bne @next
        lda di
        sta dfrom
        jsr disrupt
        jmp @next
@gun:   jsr sprites
        bcs @next
        jsr _rnd
        and #$1F
        cmp _level
        bcs @next
        ldx di
        lda d_cool,x
        bne @next
        jsr dshoot
@next:  ldx di
        lda d_cool,x
        beq :+
        dec d_cool,x
:       inc di
        bne @i

        .segment "HICODE"


; sboom: a tick of shot X's explosion ($17F4): on by its speed, which then
; halves as the original's does it (-1 stays, anything else is 0), and
; the next step; gone after the last
sboom:  stx ct
        txa
        asl a
        tay
        lda #2
        sta ce
@ax:    lda s_vx,x
        pha
        clc
        adc _s_x,y
        sta _s_x,y
        pla
        pha
        and #$80                ; (signed: the high byte + $FF)
        beq :+
        lda #$FF
:       adc _s_x+1,y
        sta _s_x+1,y
        pla
        cmp #$80
        ror a
        cmp #$FF
        beq :+
        lda #0
:       sta s_vx,x
        txa
        clc
        adc #MAXS
        tax
        tya
        adc #_s_y - _s_x
        tay
        dec ce
        bne @ax
        ldx ct
        inc _s_boom,x
        lda _s_boom,x
        cmp #BOOM_GONE
        bcc :+
        lda #0
        sta _s_life,x
        sta _s_boom,x
:       rts

; clashes(): once a tick, what the original's sprites meeting do ($6D6D):
; shots meeting - a droid's explodes, the player's is gone; then each
; explosion, the droids' and the shots', hurts the player by the ship's
; number and a droid in sight by (40 - its type) * 2, every tick they
; touch, and a droid's shot touching it explodes (the player's goes on)
_clashes:
        lda #12                 ; a shot's reach, as move_shots()'s
        sta lim
        lda #8
        sta lim+2
        ldx #0
@i:     stx ci
        jsr fly
        bcs @ni
        jsr spos
        jsr b2s
        ldx ci
@j:     inx
        cpx #MAXS
        bcs @ni
        stx cj
        jsr fly
        bcs @nj
        ldy ci
        lda s_own,x
        ora s_own,y
        beq @nj                 ; (two of the player's)
        jsr spos
        jsr near
        bcs @nj
        ldx cj
        jsr settle
        ldx ci
        jsr settle
        jmp @ni
@nj:    ldx cj
        jmp @j
@ni:    ldx ci
        inx
        cpx #MAXS
        bcc @i
        ldx #1                  ; the droids' explosions
@e:     cpx _nd
        bcs @es
        lda _d_boom,x
        beq @ne
        cmp #BOOM_GONE
        beq @ne
        stx ce
        jsr dpos
        jsr b2s
        jsr hurt
        ldx ce
@ne:    inx
        bne @e
@es:    ldx #0                  ; the shots'
@f:     lda _s_life,x
        beq @nf
        lda _s_boom,x
        beq @nf
        stx ce
        jsr spos
        jsr b2s
        jsr hurt
        ldx ce
@nf:    inx
        cpx #MAXS
        bcc @f
        rts

; hurt: the explosion at (sx, sy) on what touches it
hurt:   lda #24                 ; a bump's reach (move.s)
        sta lim
        lda #16
        sta lim+2
        ldx #0                  ; the player, the droids in sight
@t:     cpx _nd
        bcs @shots
        lda _d_boom,x
        bne @nt
        cpx #0
        beq :+
        lda _d_seen,x
        beq @nt
:       stx ct
        jsr dpos
        jsr near
        ldx ct
        bcs @nt
        stx hi_i
        lda _level
        cpx #0
        beq :+
        jsr dmg40
:       sta hi_d
        lda #0
        sta hi_p
        jsr hit
        ldx ct
@nt:    inx
        bne @t
@shots: lda #12
        sta lim
        lda #8
        sta lim+2
        ldx #0
@s:     stx ct
        jsr fly
        bcs @ns
        lda s_own,x
        beq @ns
        jsr spos
        jsr near
        ldx ct
        bcs @ns
        jsr boom
@ns:    ldx ct
        inx
        cpx #MAXS
        bcc @s
        rts

; fly: C clear if shot X is on its way and seen (not exploding, not hidden)
fly:    lda _s_boom,x
        bne @no
        ldy _s_life,x
        dey
        cpy #250
        rts
@no:    sec
        rts

; settle: shot X met another: a droid's explodes, the player's is gone
settle: lda s_own,x
        beq :+
        jmp boom
:       sta _s_life,x
        rts

        .segment "XT7"          ; ($EBA0: the block table's free end)
; dpos: bx, by := droid X's place (X kept)
dpos:   txa
        asl a
        tay
pos:    lda _d_x,y
        sta bx
        lda _d_x+1,y
        sta bx+1
        lda _d_y,y
        sta by
        lda _d_y+1,y
        sta by+1
        rts

        .segment "XT8"          ; ($E9B0)
; b2s: sx, sy := bx, by
b2s:    ldy #3
:       lda bx,y
        sta sx,y
        dey
        bpl :-
        rts

        .segment "XT6"          ; ($EBE8)
; spos: bx, by := shot X's place (X kept): as a droid's, its words as far
; apart
spos:   txa
        asl a
        clc
        adc #_s_x - _d_x
        tay
        jmp pos

        .segment "XT9"          ; ($E8E8)
; boom: shot X explodes where it is, as the original's explosion (a
; droid's or a spark: $1BCA, $18B7) - its pictures are the droids'
boom:   lda #1
        sta _s_boom,x
        sta _s_life,x
        rts

        .segment "HICODE"

; near: C clear if (bx, by) is less than lim across and lim+2 up or down
; from (sx, sy)
near:   ldx #0
@a:     lda sx,x
        sec
        sbc bx,x
        sta lo8
        lda sx+1,x
        sbc bx+1,x
        bpl :+
        eor #$FF                ; (its size: - (hi, lo))
        sta hi8
        lda lo8
        eor #$FF
        clc
        adc #1
        sta lo8
        lda hi8
        adc #0
:       bne @out
        lda lo8
        cmp lim,x
        bcs @out
        inx
        inx
        cpx #4
        bne @a
        clc
        rts
@out:   sec
        rts

        .segment "HICODE"       ; (run at $F100 on: it costs the program
                                ; nothing)

; sprites(): C set if the original would have no sprite for a shot now:
; six in use (the droids on the screen, the droids' shots) or fifteen
; things on the deck besides the player ($3450, $32A8)
sprites:
        lda #0
        sta dt                  ; sprites
        sta step                ; things
        ldx #1
@d:     cpx _nd
        bcs @s
        lda _d_boom,x
        cmp #BOOM_GONE
        beq @dn
        inc step
        txa
        asl a
        tay
        lda _d_x,y
        sta sx
        lda _d_x+1,y
        sta sx+1
        lda _d_y,y
        sta sy
        lda _d_y+1,y
        sta sy+1
        stx dj
        jsr onscr
        ldx dj
        bcs @dn
        inc dt
@dn:    inx
        bne @d
@s:     ldx #MAXS - 1
:       lda _s_life,x
        beq :+
        lda s_own,x
        beq :+
        inc dt
        inc step
:       dex
        bpl :--
        lda step
        cmp #15
        bcs @r
        lda dt
        cmp #6
@r:     rts

        .segment "LOWEND"       ; (at the end of $0C68-$0FFF)

; onscr(): C clear if (sx, sy) is where the original keeps a sprite for a
; thing ($321E): from 240 left of the player (where its figure is) to 335
; right of it, from 128 above to 87 below
onscr:  ldx #0
        ldy #0
@a:     lda sx,x
        sec
        sbc _d_x,y
        sta lo8
        lda sx+1,x
        sbc _d_x+1,y
        sta hi8
        lda lo8
        clc
        adc on_off,x
        sta lo8
        lda hi8
        adc #0
        cmp on_hi,x
        bcc @ok
        bne @out
        lda lo8
        cmp on_lo,x
        bcs @out
@ok:    cpx #2
        beq @in
        ldx #2
        ldy #2 * MAXD
        bne @a
@in:    clc
@out:   rts

        .code

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
