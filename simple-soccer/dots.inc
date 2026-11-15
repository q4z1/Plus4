; dots.inc - "LOADING"'s three dots on the loading screens (boot.s,
; cup.s): each swells and fades, a wave through them - a step each call
; (every 4 frames), 16 steps a swell, each dot 4 steps behind the one
; before - and each swell in the next of the name's colours, the three
; dots three of them side by side. The includer gives DOTS (the first
; dot's colour cell) and three bytes for it: DOT_P (the step, 0 to
; 6 * 16 - 1), DOT_C, DOT_H. A, X, Y used.

DOT_WAVE    = 6 * 16            ; (six colours a turn)

dots:   ldx DOT_P
        inx
        cpx #DOT_WAVE
        bcc :+
        ldx #0
:       stx DOT_P
        txa
        ldx #2
@dot:   cmp #DOT_WAVE
        bcc :+
        sbc #DOT_WAVE           ; (C set)
:       sta DOT_C
        lsr a                   ; which swell: its colour, the next dot's
        lsr a                   ; the next one along
        lsr a
        lsr a
        sta DOT_H
        txa
        clc
        adc DOT_H
        tay
        lda dot_hue,y
        sta DOT_H
        lda DOT_C
        and #15
        tay
        lda dot_lum,y
        ora DOT_H
        sta DOTS,x
        lda DOT_C
        clc
        adc #4
        dex
        bpl @dot
        rts

; the luminance through a swell, and the name's colours in its order
; (game.inc LOGO_HUES: yellow, red, purple, blue, cyan, green), two over
; for the dots after the first
dot_lum:    .byte $20, $20, $20, $20, $20, $20, $20, $20
            .byte $30, $40, $50, $60, $70, $60, $50, $30
dot_hue:    .byte 7, 2, 4, 6, 3, 5, 7, 2
