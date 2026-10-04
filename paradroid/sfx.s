; sfx.s - the original's sound effects on the TED's two voices: the part
; the interrupt runs once a picture
;
; The effects are the original's (data/sfx.txt, from its memory by
; tools/sfx.py), played as its driver plays them ($0500 there): from a
; start frequency a step added each picture; periods, at the end of each
; the step turned round or the frequency back to the start; so many
; periods. The SID's frequency is turned into the TED's register each
; picture: f = 1887446 / (1024 - register), the TED's lowest is 108 Hz.
; The TED has no envelope: an effect sounds while its gate and half its
; release would, and the original's waveforms are all squares here, but
; noise, which only the TED's voice 2 has.
;
; Where it lives: this code at $FC00, below cc65's stack (which uses a few
; dozen bytes of $FCxx), the effects' table at $FF40, above the TED's
; registers: the program's memory is full. Both are copied there at the
; start (startup.s) from INITDATA. sfxcall.s starts the effects.

        .export sfx_frame, _snd_len
        .exportzp s_fl, s_fh, s_dl, s_dh, s_cn, s_pe, s_fg, s_0l, s_0h, s_vol
        .exportzp q0, q1, r0, r1, tr0, tr1
        .import ted                     ; (sfxcall.s: the program has room)

TED_V1LO    = $FF0E
TED_V2LO    = $FF0F
TED_V2HI    = $FF10
TED_SOUND   = $FF11             ; 0-3 volume, 4 voice 1, 5 voice 2, 6 noise
TED_V1HI    = $FF12             ; 0-1 voice 1's high bits

        .segment "ENGZP": zeropage
; each voice's effect: 0 the TED's voice 1, 1 its voice 2
s_fl:   .res 2                  ; the SID's frequency
s_fh:   .res 2
s_dl:   .res 2                  ; its step
s_dh:   .res 2
s_cn:   .res 2                  ; pictures left of the period
s_pe:   .res 2                  ; the periods after the first
s_fg:   .res 2                  ; periods left (0-4), reset (5), noise (7)
_snd_len:
s_ln:   .res 2                  ; pictures it still sounds; 0 none
s_0l:   .res 2                  ; the start frequency, for reset
s_0h:   .res 2
s_vol:  .res 2                  ; the volume of each voice's effect: the
                                ; ship's hum is quieter (sfxcall.s), the
                                ; title's sound too (music.s)
q0:     .res 1                  ; the division
q1:     .res 1
r0:     .res 1
r1:     .res 1
tr0:    .res 1                  ; the TED's register
tr1:    .res 1


        .segment "SFXCODE"

; once a picture, from the interrupt (which keeps A, X and Y)
sfx_frame:
        ldx #1
@voice: lda s_ln,x
        bne :+
        jmp @next
:       dec s_ln,x
        bne :+
        jmp @off
:       clc                     ; the frequency on by the step
        lda s_fl,x
        adc s_dl,x
        sta s_fl,x
        lda s_fh,x
        adc s_dh,x
        sta s_fh,x
        jsr ted
        txa
        bne @v2
        lda tr0                 ; voice 1
        sta TED_V1LO
        lda TED_V1HI
        and #$FC
        ora tr1
        sta TED_V1HI
        lda TED_SOUND
        and #$E0
        ora s_vol               ; (VOL, the title's lower: music.s)
        ora #$10
        bne @set
@v2:    lda tr0                 ; voice 2, a square or noise
        sta TED_V2LO
        lda tr1
        sta TED_V2HI
        lda s_fg,x
        and #$80
        lsr a                   ; noise: bit 6
        bne :+
        lda #$20                ; else the square
:       ora s_vol+1             ; (the TED has one volume for both voices:
                                ; voice 1, written after, sets its own)
        sta tr0
        lda TED_SOUND
        and #$90
        ora tr0
@set:   sta TED_SOUND
        dec s_cn,x              ; the period
        bne @next
        lda s_pe,x
        sta s_cn,x
        lda s_fg,x
        and #$20
        beq @turn
        lda s_0l,x              ; back to the start
        sta s_fl,x
        lda s_0h,x
        sta s_fh,x
        jmp @count
@turn:  sec                     ; the step turned round
        lda #0
        sbc s_dl,x
        sta s_dl,x
        lda #0
        sbc s_dh,x
        sta s_dh,x
@count: dec s_fg,x
        lda s_fg,x
        and #$1F
        bne @next
        sta s_ln,x              ; (0) the last period done
@off:   lda TED_SOUND
        and off_of,x
        sta TED_SOUND
@next:  dex
        bmi :+
        jmp @voice
:       rts

off_of: .byte $EF, $9F
