; music.s - the title's sound on the TED's two voices, in the title's
; overlay (paradroid.cfg)
;
; The sound is the original's, made as its driver makes it in the title
; ($054A there): no tune, but its sound effects started on their own. A
; counter goes down once a picture; each time its low seven bits are 0
; (every 128 pictures) voice 1 gets one of three falling sweeps, picked at
; random (title1-3 in data/sfx.txt: the same start and step, on the SID a
; triangle, a saw and a pulse - the TED has squares only); at 34 and 48 of
; each 64 voice 2 gets the lift's ride. sfx.s plays them, as it plays the
; game's effects, at the title's lower volume.
;
; mus_start() hands the player to the engine's interrupt (mus_hook), which
; calls it once a picture, after sfx.s. mus_stop() takes it back and
; silences both voices; title.s does that before the overlay's memory goes
; to the pictures again.

        .export _mus_start, _mus_stop
        .import _mus_tab, _mus_hook, _sound
        .importzp s_fl, s_fh, s_dl, s_dh, s_cn, s_pe, s_fg, s_0l, s_0h, s_vol
        .importzp _snd_len
        .include "data.inc"

TED_SOUND   = $FF11             ; 0-3 volume, 4 voice 1, 5 voice 2, 6 noise
TED_HPOS    = $FF1E             ; (the beam's column: a seed)
MVOL        = 3                 ; the original plays it at a third

        .segment "OVLDATA"
mc:     .byte 1                 ; the original's counter ($9C)
seed:   .byte 0

        .segment "OVLCODE"

_mus_start:
        lda TED_HPOS
        ora #1
        sta seed
        lda #1                  ; a sweep at once
        sta mc
        php
        sei
        lda #<play
        sta _mus_hook
        lda #>play
        sta _mus_hook+1
        plp
        rts

_mus_stop:
        php
        sei
        lda #0
        sta _mus_hook+1
        sta _snd_len
        sta _snd_len+1
        lda TED_SOUND
        and #$8F                ; both voices off
        sta TED_SOUND
        plp
        rts

; once a picture, from the interrupt (which keeps A, X and Y)
play:   dec mc
        lda mc
        and #$7F
        bne @v2
        lda seed                ; a random number (its own: the game's is
        asl a                   ; not the interrupt's to take)
        bcc :+
        eor #$1D
:       sta seed
        ldy #0                  ; as the original: below $55 the first,
        cmp #$55                ; below $AA the second, else the third
        bcc @pick
        ldy #8
        cmp #$AA
        bcc @pick
        ldy #16
@pick:  ldx #0                  ; voice 1, as sound() starts an effect
        lda _mus_tab,y
        sta s_0l,x
        sta s_fl,x
        lda _mus_tab+1,y
        sta s_0h,x
        sta s_fh,x
        lda _mus_tab+2,y
        sta s_dl,x
        lda _mus_tab+3,y
        sta s_dh,x
        lda _mus_tab+4,y
        sta s_cn,x
        lda _mus_tab+5,y
        sta s_pe,x
        lda _mus_tab+6,y
        sta s_fg,x
        lda _mus_tab+7,y
        sta _snd_len,x
        lda #MVOL
        sta s_vol,x
        rts
@v2:    and #$3F
        cmp #$22
        beq :+
        cmp #$30
        bne @done
:       lda #SFX_RIDE
        jsr _sound
        lda #MVOL
        sta s_vol+1
@done:  rts
