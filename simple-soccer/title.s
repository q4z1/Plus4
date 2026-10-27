; title.s - the title before the first match: the name, the length of
; the match to choose (the joystick left and right), fire to kick off.
;
; It lies at $C000, loaded with the program but where the pictures go
; once the match is on (engine.s): it runs first, on a screen of its own
; (MAT2's and FNT2's place), and is gone after. Hires text, so that each
; cell can have any of the TED's colours. Its music is music.s's.

        .include "game.inc"

        .repeat 256, I          ; (text as it is, ASCII: the title's font
        .charmap I, I           ; has its characters at their ASCII codes,
        .endrepeat              ; not the Plus/4's PETSCII)

        .import joy_scan, joy, title_font, min_frames
        .import mus_start, mus_frame, mus_stop
        .export title

TCOL        = MAT2              ; the title's colours,
TCODE       = MAT2 + $400       ; codes,
TFONT       = FNT2              ; characters

C_BG        = $16               ; dark blue
C_BORDER    = $06
C_TEXT      = $71               ; white
C_VALUE     = $77               ; yellow
C_FIRE0     = $75               ; light green, and white, by turns
C_FIRE1     = $71

SKIP        = $0FF8             ; "TS" here: a test, no title (tests/vice.py,
                                ; yape.py) - behind the KERNAL's screen,
                                ; not loaded, not cleared
LOGO_ROW    = 3
LOGO_COL    = 7
VALUE_ROW   = 12
VALUE_COL   = 25                ; (the digit)
FIRE_ROW    = 16

        .zeropage
t_ptr:  .res 2                  ; (the title's)
t_dst:  .res 2

        .segment "TITLE"

title:
        lda #0
        sta t_sel               ; (3 minutes, unless chosen)
        jsr skip                ; (a test: none)
        bcc :+
        rts
:       lda #0                  ; no interrupts from the TED but the
        sta TED_IRQEN           ; music's (the ROM is out, the match's is
        lda TED_IRQ             ; not set up yet)
        sta TED_IRQ
        jsr mus_start
        lda TED_SCROLLY         ; blank while it is drawn
        and #$EF
        sta TED_SCROLLY
        ldx #0                  ; the characters
:       lda title_font,x
        sta TFONT + $100,x
        lda title_font + $100,x
        sta TFONT + $200,x
        lda title_font + $200,x
        sta TFONT + $300,x
        lda title_font + $300,x
        sta TFONT + $400,x
        lda title_font + $400,x
        sta TFONT + $500,x
        lda #' '                ; the screen: blank
        sta TCODE,x
        sta TCODE + $100,x
        sta TCODE + $200,x
        sta TCODE + $300,x
        lda #C_TEXT
        sta TCOL,x
        sta TCOL + $100,x
        sta TCOL + $200,x
        sta TCOL + $300,x
        inx
        bne :-
        ; the name, twice the size, a colour each letter (lighter above)
        ldx #0
@logo:  lda name,x
        cmp #' '
        beq @gap
        ldy #0                  ; its place in the big letters
:       cmp big_of,y
        beq :+
        iny
        bne :-
:       tya
        asl a
        asl a
        ora #128
        sta t_code
        txa
        asl a
        tay                     ; (its column: 2 a letter)
        lda t_code
        sta TCODE + LOGO_ROW * 40 + LOGO_COL,y
        clc
        adc #1
        sta TCODE + LOGO_ROW * 40 + LOGO_COL + 1,y
        adc #1
        sta TCODE + (LOGO_ROW + 1) * 40 + LOGO_COL,y
        adc #1
        sta TCODE + (LOGO_ROW + 1) * 40 + LOGO_COL + 1,y
        lda hue_of,x
        ora #$70                ; (above: the lightest)
        sta TCOL + LOGO_ROW * 40 + LOGO_COL,y
        sta TCOL + LOGO_ROW * 40 + LOGO_COL + 1,y
        and #$5F                ; (below: two shades darker)
        sta TCOL + (LOGO_ROW + 1) * 40 + LOGO_COL,y
        sta TCOL + (LOGO_ROW + 1) * 40 + LOGO_COL + 1,y
@gap:   inx
        cpx #NAME_LEN
        bne @logo
        ; the lines of text
        lda #<lines
        sta t_ptr
        lda #>lines
        sta t_ptr + 1
@line:  ldy #0
        lda (t_ptr),y           ; row ($FF: no more)
        bmi @shown
        tax
        lda row_lo,x
        clc
        iny
        adc (t_ptr),y           ; + column
        sta t_dst
        lda row_hi,x
        adc #0
        sta t_dst + 1
        iny
        lda (t_ptr),y           ; its colour
        sta t_col
        lda t_ptr               ; on to its text
        clc
        adc #3
        sta t_ptr
        bcc :+
        inc t_ptr + 1
:       ldy #0
:       lda (t_ptr),y
        beq @end
        sta (t_dst),y
        lda t_dst + 1           ; (the colour: $400 below)
        pha
        sec
        sbc #4
        sta t_dst + 1
        lda t_col
        sta (t_dst),y
        pla
        sta t_dst + 1
        iny
        bne :-
@end:   iny                     ; past the 0
        tya
        clc
        adc t_ptr
        sta t_ptr
        bcc @line
        inc t_ptr + 1
        bne @line
@shown: jsr value
        ; the TED: hires text, 40 columns, 25 rows, the title's matrix and
        ; characters
        lda TED_CTRL2
        and #$40                ; (PAL or NTSC kept)
        ora #$88                ; 256 characters, hires, 40 columns
        sta TED_CTRL2
        lda TED_BMBASE
        and #$FB                ; characters from RAM
        sta TED_BMBASE
        lda TED_CHBASE
        and #$03
        ora #>TFONT
        sta TED_CHBASE
        lda #>TCOL
        sta TED_VMBASE
        lda #C_BG
        sta TED_BG
        lda #C_BORDER
        sta TED_BORDER
        lda #$1B                ; on, text, 25 rows
        sta TED_SCROLLY
        lda #0
        sta t_was
        sta t_tick
        ; the choice: left, right; fire to kick off (on its letting go)
@wait:  lda TED_LINE            ; a frame: the beam into lines 200-215 and
        sec                     ; out of them again (a line could pass
        sbc #200                ; unseen while the music's interrupt runs)
        cmp #16
        bcs @wait
:       lda TED_LINE
        sec
        sbc #200
        cmp #16
        bcc :-
        jsr mus_frame
        inc t_tick
        lda t_tick              ; "fire" in light green and white by turns
        and #32
        beq :+
        lda #C_FIRE1
        bne :++
:       lda #C_FIRE0
:       ldx #39
:       sta TCOL + FIRE_ROW * 40,x
        dex
        bpl :-
        jsr skip
        bcs @go
        jsr joy_scan            ; (joy_read, but the music not held up)
        lda t_was               ; let go of: held before, not now
        eor #$FF
        and joy
        sta t_new               ; (pushed: now, not before)
        lda joy
        eor #$FF
        and t_was
        ldx joy
        stx t_was
        and #J_FIRE
        bne @go
        lda t_new
        and #J_LEFT
        beq :+
        lda t_sel
        beq :+
        dec t_sel
        jsr value
:       lda t_new
        and #J_RIGHT
        beq :+
        lda t_sel
        cmp #2
        beq :+
        inc t_sel
        jsr value
:       jmp @wait
@go:    jsr mus_stop
        ldx t_sel               ; the match's length
        lda frames_of,x
        sta min_frames
        rts

; skip: carry set if a test asks for no title (SKIP), the ask taken
; back - min_frames then for 3 minutes
skip:
        lda SKIP
        cmp #'T'
        bne @no
        lda SKIP + 1
        cmp #'S'
        bne @no
        lda #0
        sta SKIP
        sta SKIP + 1
        ldx t_sel
        lda frames_of,x
        sta min_frames
        sec
        rts
@no:    clc
        rts

; value: the length chosen, shown
value:
        ldx t_sel
        lda digit_of,x
        sta TCODE + VALUE_ROW * 40 + VALUE_COL
        lda #C_VALUE
        sta TCOL + VALUE_ROW * 40 + VALUE_COL
        rts

name:       .byte "SIMPLE SOCCER"
NAME_LEN    = * - name
big_of:     .byte "SIMPLECOR"           ; (mkdata's LOGO_LETTERS)
; a colour each letter: warm, then cool, round the TED's hues
hue_of:     .byte 7, 8, 2, 11, 4, 6, 0, 3, 15, 5, 10, 7, 8
digit_of:   .byte "357"
frames_of:  .byte 100, 167, 233         ; frames to a minute: 3, 5, 7 minutes

; the lines: row, column, colour, text, 0 - $FF the end
lines:
        .byte 8, 5, $61
        .byte "A FOOTBALL GAME FOR THE PLUS/4", 0
        .byte VALUE_ROW, 8, C_TEXT
        .byte "MATCH LENGTH:  <   MIN >", 0
        .byte FIRE_ROW, 9, C_FIRE0
        .byte "PRESS FIRE TO KICK OFF", 0
        .byte 19, 8, $51
        .byte "JOYSTICK IN EITHER PORT", 0
        .byte 23, 8, $41
        .byte "BY Q4Z1 2026 (& CLAUDE)", 0
        .byte $FF

row_lo:
        .repeat 25, I
        .byte <(TCODE + I * 40)
        .endrepeat
row_hi:
        .repeat 25, I
        .byte >(TCODE + I * 40)
        .endrepeat

t_col:      .byte 0
t_code:     .byte 0
t_was:      .byte 0             ; the stick as it was
t_new:      .byte 0             ; what is pushed that was not
t_tick:     .byte 0
t_sel:      .byte 0             ; the length chosen: 3, 5, 7 minutes
