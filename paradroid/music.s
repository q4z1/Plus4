; music.s - the title's sound on the TED's two voices, in the title's
; overlay (paradroid.cfg), as Stardew Pond plays its music
;
; The sound is the original's (data/music.txt, made from its own sound
; driver by tools/sidmusic.py): voice 1 its falling sweep, voice 2 its
; wavering low tone. tools/mkdata.py makes of each voice a list of entries:
; a length in pictures, the TED's frequency register (low byte, high bits;
; $FF a rest); a length of 0 starts the voice again.
;
; mus_start() hands the player to the engine's interrupt (mus_hook), which
; calls it once a picture: the tempo is the picture's, whatever the title is
; drawing. mus_stop() takes it back and silences both voices; title.c does
; that before the overlay's memory goes to the pictures again. A sound
; effect, should one play, keeps voice 2 meanwhile.

        .export _mus_start, _mus_stop
        .import _mus_v1, _mus_v2, _mus_hook, _snd_time

TED_V1LO    = $FF0E
TED_V2LO    = $FF0F
TED_V2HI    = $FF10
TED_SOUND   = $FF11             ; 0-3 volume, 4 voice 1, 5 voice 2, 6 noise
TED_V1HI    = $FF12             ; 0-1 voice 1's high bits (the rest: other)
MVOL        = 3                 ; the original plays it at a third

        .segment "ENGZP": zeropage
p1:     .res 2                  ; each voice's next entry
p2:     .res 2

        .segment "OVLDATA"
t1:     .byte 0                 ; pictures left of each voice's entry
t2:     .byte 0
hi:     .byte 0

        .segment "OVLCODE"

_mus_start:
        php
        sei
        jsr rew1
        jsr rew2
        lda #1
        sta t1
        sta t2
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
        lda TED_SOUND
        and #$8F                ; both voices off
        sta TED_SOUND
        plp
        rts

rew1:   lda #<_mus_v1
        sta p1
        lda #>_mus_v1
        sta p1+1
        rts

rew2:   lda #<_mus_v2
        sta p2
        lda #>_mus_v2
        sta p2+1
        rts

; once a picture, from the interrupt (which keeps A, X and Y)
play:   dec t1
        bne @v2
        ldy #0
        lda (p1),y
        bne :+
        jsr rew1                ; the end: again
        lda (p1),y
:       sta t1
        iny
        lda (p1),y
        tax
        iny
        lda (p1),y
        cmp #$FF
        beq @off1
        sta hi
        stx TED_V1LO
        lda TED_V1HI
        and #$FC
        ora hi
        sta TED_V1HI
        lda TED_SOUND
        and #$F0
        ora #$10 | MVOL
        bne @set1
@off1:  lda TED_SOUND
        and #$EF
@set1:  sta TED_SOUND
        clc
        lda p1
        adc #3
        sta p1
        bcc @v2
        inc p1+1

@v2:    dec t2
        bne @done
        ldy #0
        lda (p2),y
        bne :+
        jsr rew2
        lda (p2),y
:       sta t2
        lda _snd_time           ; an effect has voice 2: keep time only
        bne @next2
        iny
        lda (p2),y
        tax
        iny
        lda (p2),y
        cmp #$FF
        beq @off2
        stx TED_V2LO
        sta TED_V2HI
        lda TED_SOUND
        and #$B0                ; no noise
        ora #$20 | MVOL
        bne @set2
@off2:  lda TED_SOUND
        and #$DF
@set2:  sta TED_SOUND
@next2: clc
        lda p2
        adc #3
        sta p2
        bcc @done
        inc p2+1
@done:  rts
