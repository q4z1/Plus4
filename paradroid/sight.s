; sight.s - which droids the player sees, as the original's $24AE
;
; A droid behind a wall or a closed door is not shown, does not fire and
; is not hit by the disruptor (draw: figs.s, droids.s), as in the
; original: there a droid's sprite is on only while a line from the
; player's character to the droid's crosses no wall character (a code from
; $80 on, which a closed door's are).
;
; The line is the original's: from the player's character ((p + 7) / 8)
; to the droid's (d / 8), in steps of less than a character along the
; longer way - both distances doubled while they fit a byte, then added to
; themselves while they still do, as fractions of a character - each step
; looking at the character it gets into, till it has reached the droid's
; character on both ways (going left or up: has gone past it, as there).
;
; It runs on page 1, under the processor's stack ($0100-$01BF: the stack
; reaches $01D8 at its deepest, measured in the game, its pages, the
; console and transfers), copied there at the start. Each tick it looks at
; half of the droids near enough the window (even or odd ones in turn).

        .export _sight, _d_seen
        .import _d_x, _nd, _tick, csolid, _player_spot
        .importzp tx, ty

        .include "game.inc"

        .segment "ENGZP": zeropage
sg_p:   .res 2                  ; the player's character, across and down
sg_q:   .res 2                  ; the droid's
sg_u:   .res 2                  ; the distances, then the steps' fractions
sg_s:   .res 2                  ; their signs: 0 or $FF
sg_f:   .res 2                  ; the steps, signed
sg_l:   .res 2                  ; where the line is: fractions,
sg_h:   .res 2                  ; and characters
sg_t:   .res 1

        .segment "LOWBSS"
_d_seen: .res MAXD              ; 1 if the player sees the droid

        .code

_sight: jsr sg_start
@d:     dex
        bne :+
        rts
:       txa
        asl a
        tay
        jsr cell
        sta sg_q
        txa
        asl a
        adc #2 * MAXD           ; (d_y after d_x)
        tay
        jsr cell
        sta sg_q+1
        jsr dist
        bcs @no                 ; out of the window's reach: not seen
        txa                     ; half of them a tick, the others keep
        eor _tick               ; what they had
        lsr a
        bcs @d
        lda sg_u                ; the same character: seen
        ora sg_u+1
        sec
        beq @c
        jsr line
@c:     lda #0
        rol a                   ; (C: seen)
@set:   sta _d_seen,x
        jmp @d
@no:    lda #0
        beq @set

        .segment "UNPACK"       ; (the end of the unpacker's $0200-$03FF)

; A := (_d_x + Y) / 8, Y the word's offset (d_y's at 2 * MAXD on)
cell:   lda _d_x,y
        sta sg_t
        lda _d_x+1,y
        lsr a
        ror sg_t
        lsr a
        ror sg_t
        lsr a
        ror sg_t
        lda sg_t
        rts

        .segment "PAGE1"

; sg_start: the player's character to sg_p, X := nd
sg_start:
        jsr _player_spot        ; (tx, ty: the player's character)
        lda tx
        sta sg_p
        lda ty
        sta sg_p+1
        ldx _nd
        rts

; the distances from the player's character to the droid's, across and
; down: signs to sg_s, sizes to sg_u; C set if more than 27 across or 13
; down, beyond the window (X kept)
dist:   ldy #1
@a:     lda sg_q,y
        sec
        sbc sg_p,y
        pha
        lda #0
        sbc #0                  ; ($FF if negative)
        sta sg_s,y
        pla
        eor sg_s,y              ; (its size: - A = ~A + 1)
        sec
        sbc sg_s,y
        sta sg_u,y
        cmp lim,y
        bcs @out
        dey
        bpl @a
@out:   rts
lim:    .byte 28, 14

; line(): C set if the line from the player's character to the droid's,
; another one, crosses no wall (X kept)
line:   lda sg_u                ; both doubled while they fit
        sta sg_l
        lda sg_u+1
        sta sg_l+1
@dbl:   lda sg_l
        asl a
        bcs @add
        tay
        lda sg_l+1
        asl a
        bcs @add
        sta sg_l+1
        sty sg_l
        bcc @dbl
@add:   lda sg_l                ; then added to while they fit
        clc
        adc sg_u
        bcs @go
        tay
        lda sg_l+1
        adc sg_u+1
        bcs @go
        sta sg_l+1
        sty sg_l
        bcc @add
@go:    ldy #1                  ; the steps, negative where they go so;
@ax:    lda sg_s,y              ; from the player's character
        asl a                   ; (C: negative, + 1)
        lda sg_s,y
        eor sg_l,y
        adc #0
        sta sg_f,y
        lda sg_p,y
        sta sg_h,y
        lda #0
        sta sg_l,y
        dey
        bpl @ax
@step:  ldy #1                  ; a step, across and down
:       lda sg_l,y
        clc
        adc sg_f,y
        sta sg_l,y
        lda sg_h,y
        adc sg_s,y
        sta sg_h,y
        sta tx,y
        dey
        bpl :-
        jsr csolid
        clc
        bne @out                ; a wall: not seen
        lda sg_h                ; there on both ways? (C: at or past it;
        cmp sg_q                ; going back: past it)
        ror a
        eor sg_s
        sta sg_t
        lda sg_h+1
        cmp sg_q+1
        ror a
        eor sg_s+1
        and sg_t
        bpl @step
        sec
@out:   rts
