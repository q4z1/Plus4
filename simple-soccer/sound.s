; sound.s - the match's sounds on the TED's two voices: the ball kicked,
; the keeper's catch, the referee's whistle, the crowd - at a goal, a near
; miss, a save, a card.
;
; An effect is a list of steps - frames, the frequency register's low
; byte, its high two bits | a kind (SFX_NOISE, SFX_REST) | a volume
; (bits 2 - 5: 1 - 8, 0 VOLUME - the TED's one for both voices) - ended
; by 0 frames; sfx_start puts one on a voice, the interrupt (snd_tick) goes on
; with it 50 times a second, whatever the pictures do. A new effect on a
; voice takes over from the one there - but a kick or a catch not from
; the crowd (crowd1: it drowns them). Voice 0 is the TED's first (square
; only), voice 1 its second (square or noise).
;
; A step of both kinds (SFX_EXT: noise and rest, else meaningless) has a
; fourth byte and is worked out each frame: on voice 1 the crowd - noise,
; its register the step's and a random 0 - spread (the fourth byte, 2^n -
; 1) more each frame, many voices rather than one hiss; on voice 0 a
; glide - a square, its register the fourth byte (signed) more each frame,
; a whistle in the crowd - or, its fourth byte TRILL, a trill: the
; register's low byte flipped each frame (the referee's whistle, TONE(2800)
; and TONE(3150) in turn). A step's volume 0 is VOLUME - but voice 0's
; leaves it as it is while the crowd is on voice 1 (the referee's whistle
; at the end of the roar made it loud).

        .include "game.inc"

        .export snd_init, snd_tick
        .export sfx_kick, sfx_catch, sfx_whistle, sfx_halftime, sfx_goal
        .export sfx_save, sfx_miss, sfx_yellow, sfx_red, sfx_roar
        .export v_left, v_lo, v_hi, crowd1, fx_murmur, fx_hold, fx_fade  ; (play.s new_match)

TED_V1LO    = $FF0E             ; voice 1's frequency, low
TED_V2LO    = $FF0F             ; voice 2's
TED_V2HI    = $FF10             ; (its high two bits)
TED_SOUND   = $FF11             ; volume, voices on, voice 2 noise
TED_V1HI    = $FF12             ; (its high two bits, with the bitmap's)

VOLUME      = 6

SFX_NOISE   = $40
SFX_REST    = $80
SFX_EXT     = $C0
TRILL       = $40               ; (a glide's step: bit 6 alone - V, not N)
; the frequency register for a square of hz (PAL)
.define TONE(hz) (1024 - (110840 + (hz) / 2) / (hz))
T_LO        = TONE(2800)        ; (the trill's two notes)
T_HI        = TONE(3150)
.assert >T_LO = >T_HI, error, "a trill flips the low byte only"
.macro  step n, reg, kind
        .byte n, <(reg), >(reg) | kind
.endmacro
.macro  rest n
        step n, 0, SFX_REST
.endmacro
.macro  vstep n, reg, kind, vol
        .byte n, <(reg), >(reg) | kind | ((vol) << 2)
.endmacro
; the crowd (voice 1): n frames, the register reg + 0 - spread, at vol
.macro  crowd n, reg, vol, spread
        .byte n, <(reg), >(reg) | SFX_EXT | ((vol) << 2), spread
.endmacro
; a glide (voice 0): n frames from reg, d more each frame
.macro  glide n, reg, d
        .byte n, <(reg), >(reg) | SFX_EXT, <(d)
.endmacro
; the referee's trill (voice 0): n frames, T_LO and T_HI in turn
.macro  trill n
        glide n, T_LO, TRILL
.endmacro

        .zeropage
snd_p:  .res 2                  ; (the interrupt's, or sfx_start's with it
                                ; held off)

        .bss
v_lo:   .res 2                  ; each voice's effect: where it is,
v_hi:   .res 2
v_left: .res 2                  ; and frames left of its step, 0 none
snd_v:  .res 1                  ; (advance's voice)

        .code

; snd_init: both voices quiet, the volume up
snd_init:
        lda #0
        sta v_left
        sta v_left + 1
        lda #VOLUME
        sta TED_SOUND
        rts

; snd_tick: a frame of the effects (the interrupt's). Keeps nothing but
; what it has to: A, Y and the flags go.
snd_tick:
        ldy #1
@voice: lda v_left,y
        beq @next
        sec
        sbc #1
        sta v_left,y
        bne @frame
        jsr advance
        jmp @next
@frame: lda v_ext,y             ; (the crowd, a glide: worked out each
        beq @next               ; frame)
        jsr ext_frame
@next:  dey
        bpl @voice
        rts

; sfx_start: the effect at A (low) / X (high) on voice Y. Keeps X, Y.
sfx_start:
        php
        sei
        sta v_lo,y
        pha
        txa
        sta v_hi,y
        jsr advance
        pla
        plp
        rts

; advance: voice Y's effect a step on. Keeps X, Y.
advance:
        sty snd_v
        lda v_lo,y
        sta snd_p
        lda v_hi,y
        sta snd_p + 1
        ldy #0
        lda (snd_p),y           ; its frames: 0, the end
        bne :+
        ldy snd_v
        sta v_left,y
        sta v_ext,y
        jmp off
:       pha
        iny
        lda (snd_p),y
        sta snd_lo              ; (the low byte)
        iny
        lda (snd_p),y
        sta snd_k               ; (the high bits and the kind)
        iny
        lda (snd_p),y
        sta snd_d               ; (an extended step's fourth byte)
        ldy #3                  ; on past it: 3 bytes, extended 4
        lda snd_k
        and #SFX_EXT
        cmp #SFX_EXT
        bne :+
        iny
:       tya
        ldy snd_v
        clc
        adc snd_p
        sta v_lo,y
        lda snd_p + 1
        adc #0
        sta v_hi,y
        pla                     ; its frames
        sta v_left,y
        lda #0
        sta v_ext,y
        lda snd_k
        and #SFX_EXT
        cmp #SFX_EXT
        bne @plain
        sta v_ext,y             ; (extended: its register, its spread or
        lda snd_lo              ; step)
        sta v_rl,y
        lda snd_k
        and #3
        sta v_rh,y
        lda snd_d
        sta v_d,y
        jsr vol_k               ; its volume
        lda on_ext,y            ; on: voice 0 a square, voice 1 noise
        jsr voice_on
        cpy #0
        bne ext_frame           ; (the crowd: its first frame's noise)
        lda v_rl                ; (a glide: from its register)
        sta snd_lo
        lda v_rh
        jmp put_reg
@plain: lda snd_k               ; the register
        jsr put_reg
        lda snd_k
        bmi off                 ; (a rest)
        jsr vol_k               ; its volume
        lda on_bit,y            ; on: a square, voice 1 noise if so
        bit snd_k
        bvc :+
        lda #SFX_NOISE
:       jmp voice_on
; vol_k: the volume of step snd_k on voice Y (0: VOLUME - but voice 0's
; as it is while the crowd is on voice 1). Keeps X, Y.
vol_k:  lda snd_k
        jsr vol_of
        bne @vol
        cpy #0
        bne @full
        lda v_left + 1
        beq @full
        lda v_ext + 1
        bne off - 1             ; (an rts)
@full:  lda #VOLUME
@vol:   jmp set_vol
        rts
off:    lda TED_SOUND           ; voice Y quiet
        and off_mask,y
        sta TED_SOUND
        rts

; ext_frame: a frame of voice Y's extended step - the crowd's noise a
; random 0 - spread above its register, a glide its step on. Keeps X, Y.
ext_frame:
        cpy #0
        beq @glide
        lda lfsr                ; (its own random: the game's rnd is the
        asl a                   ; match's, the same whatever is heard)
        bcc :+
        eor #$1D
:       sta lfsr
        and v_d + 1
        clc
        adc v_rl + 1
        sta snd_lo
        lda v_rh + 1
        adc #0
        jmp put_reg
@glide: bit v_d                 ; (a trill: the low byte flipped)
        bmi @step
        bvc @step
        lda v_rl
        eor #<T_LO ^ <T_HI
        clc                     ; (the high bits as they are: + 0)
        bcc @lo
@step:  lda v_d
        clc
        adc v_rl
@lo:    sta v_rl
        sta snd_lo
        lda v_d                 ; (the step's sign)
        and #$80
        beq :+
        lda #$FF
:       adc v_rh
        and #3
        sta v_rh
        jmp put_reg

; put_reg: voice Y's frequency register, snd_lo its low byte and A's two
; low bits its high ones. Keeps X, Y.
put_reg:
        and #3
        sta snd_t
        cpy #0
        bne :+
        lda TED_V1HI            ; (its high bits with the bitmap's)
        and #$FC
        ora snd_t
        sta TED_V1HI
        lda snd_lo
        sta TED_V1LO
        rts
:       lda TED_V2HI
        and #$FC
        ora snd_t
        sta TED_V2HI
        lda snd_lo
        sta TED_V2LO
        rts

; vol_of: the volume in kind A (bits 2 - 5), Z set if 0
vol_of: lsr a
        lsr a
        and #$0F
        rts

; set_vol: the TED's volume A (both voices')
set_vol:
        sta snd_t
        lda TED_SOUND
        and #$F0
        ora snd_t
        sta TED_SOUND
        rts

; voice_on: voice Y on, A its bits (on_bit, SFX_NOISE)
voice_on:
        sta snd_t
        lda TED_SOUND
        and off_mask,y
        ora snd_t
        sta TED_SOUND
        rts

on_bit:     .byte $10, $20
on_ext:     .byte $10, SFX_NOISE
off_mask:   .byte <~$10, <~$60

        .bss
snd_k:  .res 1
snd_t:  .res 1
snd_lo: .res 1
snd_d:  .res 1
v_ext:  .res 2                  ; each voice: 0 a plain step, else an
v_rl:   .res 2                  ; extended one - its register (low, high
v_rh:   .res 2                  ; bits), its spread or step
v_d:    .res 2
v_crowd: .res 1                 ; not 0: voice 1's effect the crowd's
        .data
lfsr:   .byte $5A               ; (ext_frame's random: never 0)
        .code

; the effects, each on its voice. Keep X, Y.
sfx_kick:
        jsr save
        lda #<fx_kick
        ldx #>fx_kick
        jmp low1
sfx_catch:
        jsr save
        lda #<fx_catch
        ldx #>fx_catch
        jmp low1
sfx_goal:                       ; the crowd roaring, whistling (the roar
        jsr sfx_roar            ; first: X, Y as they were - a bit over its
        lda #<fx_goal_w         ; three bytes' jsr ran the third as code,
        ldx #>fx_goal_w         ; Luca: the crowd mad at a goal)
        ldy #0
        jmp go
sfx_roar:                       ; the crowd roaring (full time: after the
        jsr save                ; referee's whistle)
        lda #<fx_goal
        ldx #>fx_goal
        jmp crowd1
sfx_save:                       ; the keeper's save: the ball at his
        jsr save                ; hands, the crowd's "oh"
        lda #<fx_save
        ldx #>fx_save
        jmp crowd1
sfx_miss:                       ; just wide, over the bar: "oh"
        jsr save
        lda #<fx_ooh
        ldx #>fx_ooh
        jmp crowd1
sfx_yellow:                     ; a yellow card: a murmur
        jsr save
        lda #<fx_yellow
        ldx #>fx_yellow
        jmp crowd1
sfx_red:                        ; a red card: the whistle, a murmur
        jsr save                ; louder and longer, the crowd whistling
        lda #<fx_red_w
        ldx #>fx_red_w
        ldy #0
        jsr sfx_start
        lda #<fx_red
        ldx #>fx_red
        jmp crowd1
sfx_whistle:
        jsr save
        lda #<fx_whistle
        ldx #>fx_whistle
        ldy #0
        jmp go
sfx_halftime:
        jsr save
        lda #<fx_halftime
        ldx #>fx_halftime
        ldy #0
        jmp go
save:   stx snd_x               ; (X and Y kept for the one who called)
        sty snd_y
        rts
low1:   pha                     ; voice 1, but not over the crowd
        lda v_crowd
        beq :+
        lda v_left + 1
        beq :+
        pla
        jmp back
:       sta v_crowd
        pla
        ldy #1
        jmp go
crowd1: pha                     ; voice 1, the crowd's
        lda #1
        sta v_crowd
        pla
        ldy #1
go:     jsr sfx_start
back:   ldx snd_x
        ldy snd_y
        rts
snd_x:  .byte 0
snd_y:  .byte 0

; The effects. The TED has no envelopes: a kick is a short noise that
; drops, the whistle a trill, the crowd a noise that swells and dies away.
        .rodata
fx_kick:
        step 1, 900, SFX_NOISE
        step 2, 830, SFX_NOISE
        step 1, 760, SFX_NOISE
        .byte 0
fx_catch:
        step 1, 860, SFX_NOISE
        step 1, 800, SFX_NOISE
        .byte 0
fx_whistle:
        trill 14
        .byte 0
fx_halftime:
        trill 10
        rest 8
        trill 10
        rest 8
        trill 32
        .byte 0
; the crowd at a goal (Luca: barely horrible - it was a hiss that rose
; and stopped): the noise thrown about each frame (many voices, not one)
; over a low roar to a brighter shout, rising as it swells; the volume up
; in a quarter of a second, held for a second and a half, and down over a
; second in waves - in steps of 4 frames
GOAL_N = 35
fx_goal:
        .repeat GOAL_N, k
        G_I .set k * 4
        .if k = 12
fx_hold:                        ; (full time: its loud part again and
        .elseif k = 22          ; again from here, as it comes to fx_fade,
fx_fade:                        ; till the teams are gone - play.s
        .endif                  ; new_match)
        .if G_I < 12
        G_VOL .set 2 + G_I / 2
        .elseif G_I < 85
        G_VOL .set 8 - ((G_I / 9) .mod 2)
        .else
        G_VOL .set 8 - (G_I - 85) / 8 + ((G_I / 5) .mod 2)
        .endif
        .if G_VOL > 8
        G_VOL .set 8
        .endif
        .if G_VOL < 1
        G_VOL .set 1
        .endif
        G_RISE .set G_I / 4
        .if G_I > 60
        G_RISE .set 15 - (G_I - 60) / 6
        .endif
        crowd 4, 868 + G_RISE, G_VOL, 63
        .endrepeat
        .byte 0
.assert G_I >= 85, error, "fx_goal: fx_fade not in its fading"
; and whistling (Luca): up and down, three of them in the roar - done
; before the kick-off's whistle (DEAD_GOAL)
fx_goal_w:
        rest 18
        glide 7, 944, 5
        rest 2
        glide 9, 978, -2
        rest 14
        glide 5, 950, 6
        glide 6, 980, 0
        glide 7, 980, -3
        rest 20
        glide 8, 940, 5
        rest 2
        glide 10, 976, -2
        .byte 0
; a near miss, a save: "oh" - quickly up, falling as it dies away; the
; save with the ball at the keeper's hands first (catch's)
fx_save:
        step 1, 860, SFX_NOISE
        step 1, 800, SFX_NOISE
fx_ooh:                         ; (swelling over 15 frames, Luca: a soft
        .repeat 18, k           ; attack - it was 4, 6, then 7 in 6)
        .if k < 5
        O_VOL .set 2 + k
        .elseif k < 8
        O_VOL .set 7
        .else
        O_VOL .set 7 - (k - 6) / 2
        .endif
        crowd 3, 944 - 5 * k, O_VOL, 31
        .endrepeat
        .byte 0
; a card: the crowd murmurs, low, after the whistle (a yellow); a red
; louder and longer, and it whistles
fx_yellow:
        rest 14
        crowd 4, 766, 2, 31
        crowd 4, 766, 3, 31
        crowd 4, 766, 3, 31
        crowd 4, 766, 4, 31
        crowd 4, 766, 3, 31
        crowd 4, 766, 4, 31
        crowd 4, 766, 4, 31
        crowd 4, 766, 3, 31
        crowd 4, 766, 4, 31
        crowd 4, 766, 3, 31
        crowd 4, 766, 3, 31
        crowd 4, 766, 2, 31
        crowd 4, 766, 1, 31
        .byte 0
; after full time: a low murmur, on and on (new_match starts it anew) -
; the card's, swelling and dying, again and again was one for a game
; with aliens, said Luca
fx_murmur:
        crowd 255, 766, 2, 31
        .byte 0
fx_red:
        rest 14
        .repeat 30, k
        .if k < 8
        R_VOL .set 2 + k / 2
        .elseif k < 20
        R_VOL .set 6 - ((k / 3) .mod 2)
        .else
        R_VOL .set 6 - (k - 20) / 2
        .endif
        .if R_VOL < 1
        R_VOL .set 1
        .endif
        crowd 4, 770 + 2 * k, R_VOL, 31
        .endrepeat
        .byte 0
fx_red_w:                          ; (the referee's whistle, as fx_whistle's)
        trill 14
        rest 16
        glide 3, 952, 8
        glide 6, 976, 1
        glide 6, 982, -1
        glide 4, 976, -4
        rest 6
        glide 3, 958, 7
        glide 7, 979, 1
        glide 7, 986, -1
        glide 5, 979, -5
        rest 10
        glide 3, 948, 8
        glide 5, 972, 1
        glide 5, 977, -1
        glide 4, 972, -3
        rest 8
        glide 2, 960, 9
        glide 8, 978, 1
        glide 8, 986, -1
        glide 6, 978, -4
        .byte 0
