; sound.s - the match's sounds on the TED's two voices: the ball kicked,
; the keeper's catch, the referee's whistle, the crowd at a goal.
;
; An effect is a list of steps - frames, the frequency register's low
; byte, its high two bits | a kind (SFX_NOISE, SFX_REST) - ended by 0
; frames; sfx_start puts one on a voice, the interrupt (snd_tick) goes on
; with it 50 times a second, whatever the pictures do. A new effect on a
; voice takes over from the one there. Voice 0 is the TED's first (square
; only), voice 1 its second (square or noise).

        .include "game.inc"

        .export snd_init, snd_tick
        .export sfx_kick, sfx_catch, sfx_whistle, sfx_halftime, sfx_goal

TED_V1LO    = $FF0E             ; voice 1's frequency, low
TED_V2LO    = $FF0F             ; voice 2's
TED_V2HI    = $FF10             ; (its high two bits)
TED_SOUND   = $FF11             ; volume, voices on, voice 2 noise
TED_V1HI    = $FF12             ; (its high two bits, with the bitmap's)

VOLUME      = 6

SFX_NOISE   = $40
SFX_REST    = $80
; the frequency register for a square of hz (PAL)
.define TONE(hz) (1024 - (110840 + (hz) / 2) / (hz))
.macro  step n, reg, kind
        .byte n, <(reg), >(reg) | kind
.endmacro
.macro  rest n
        step n, 0, SFX_REST
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
        bne @next
        jsr advance
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
        jmp off
:       pha
        iny
        lda (snd_p),y
        pha                     ; (the low byte)
        iny
        lda (snd_p),y
        tay                     ; (the high bits and the kind)
        lda snd_p               ; on past it
        clc
        adc #3
        sta snd_p
        bcc :+
        inc snd_p + 1
:       tya
        ldy snd_v
        pha
        lda snd_p
        sta v_lo,y
        lda snd_p + 1
        sta v_hi,y
        pla
        sta snd_k               ; (the high bits and the kind)
        pla                     ; the low byte to the voice
        cpy #0
        bne :+
        sta TED_V1LO
        lda TED_V1HI
        and #$FC
        sta snd_t
        lda snd_k
        and #$03
        ora snd_t
        sta TED_V1HI
        jmp @on
:       sta TED_V2LO
        lda TED_V2HI
        and #$FC
        sta snd_t
        lda snd_k
        and #$03
        ora snd_t
        sta TED_V2HI
@on:    pla                     ; its frames
        sta v_left,y
        lda snd_k
        bmi off                 ; (a rest)
        lda on_bit,y            ; on: a square, voice 1 noise if so
        bit snd_k
        bvc :+
        lda #SFX_NOISE
:       sta snd_t
        lda TED_SOUND
        and off_mask,y
        ora snd_t
        sta TED_SOUND
        rts
off:    lda TED_SOUND           ; voice Y quiet
        and off_mask,y
        sta TED_SOUND
        rts

on_bit:     .byte $10, $20
off_mask:   .byte <~$10, <~$60
snd_k:  .byte 0
snd_t:  .byte 0

; the effects, each on its voice. Keep X, Y.
sfx_kick:
        jsr save
        lda #<kick
        ldx #>kick
        ldy #1
        jmp go
sfx_catch:
        jsr save
        lda #<catch
        ldx #>catch
        ldy #1
        jmp go
sfx_goal:
        jsr save
        lda #<goal
        ldx #>goal
        ldy #1
        jmp go
sfx_whistle:
        jsr save
        lda #<whistle
        ldx #>whistle
        ldy #0
        jmp go
sfx_halftime:
        jsr save
        lda #<halftime
        ldx #>halftime
        ldy #0
        jmp go
save:   stx snd_x               ; (X and Y kept for the one who called)
        sty snd_y
        rts
go:     jsr sfx_start
        ldx snd_x
        ldy snd_y
        rts
snd_x:  .byte 0
snd_y:  .byte 0

; The effects. The TED has no envelopes: a kick is a short noise that
; drops, the whistle a trill, the crowd a noise that swells and dies away.
        .rodata
kick:
        step 1, 900, SFX_NOISE
        step 2, 830, SFX_NOISE
        step 1, 760, SFX_NOISE
        .byte 0
catch:
        step 1, 860, SFX_NOISE
        step 1, 800, SFX_NOISE
        .byte 0
whistle:
        .repeat 7
        step 1, TONE(2800), 0
        step 1, TONE(3150), 0
        .endrepeat
        .byte 0
halftime:
        .repeat 2
        .repeat 5
        step 1, TONE(2800), 0
        step 1, TONE(3150), 0
        .endrepeat
        rest 8
        .endrepeat
        .repeat 16
        step 1, TONE(2800), 0
        step 1, TONE(3150), 0
        .endrepeat
        .byte 0
goal:
        .repeat 12, i           ; the roar, swelling
        step 3, 950 + i * 3, SFX_NOISE
        step 2, 960 + i * 3, SFX_NOISE
        .endrepeat
        .repeat 10, i           ; and dying away, in gasps
        step 3, 990 - i * 4, SFX_NOISE
        rest 1 + i / 3
        .endrepeat
        .byte 0
