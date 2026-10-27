; whatchawant.s - a Plus/4 demo to So What'cha Want (Beastie Boys, 1992).
;
; For now the sound alone (music.s), with what is needed to fit pictures
; to it later: where the music is, bar and tick, and each voice's level,
; on the screen.

        .include "demo.inc"

        .import mus_start, mus_frame, m_pos, m_bar, v_page, m_level
        .import __BSS_RUN__, __BSS_SIZE__

; screen codes for the texts: A-Z are 1-26, the rest as in ASCII (the
; ASCII codes as numbers: 'A' would be the target's PETSCII already)
.repeat 26, i
        .charmap $41 + i, 1 + i
.endrepeat

ROW_BAR     = 12                ; where "BAR" and the meters are
ROW_METER   = 15
METER_X     = 12

        .zeropage
ptr:    .res 2
t_at:   .res 2

; The start, where the program's BASIC line SYSes to: the ROM's characters
; copied to RAM while the ROM is in, then the ROM out, the variables
; cleared; no C, no cc65 start-up.
        .segment "STARTUP"
        sei
        cld
        ldx #$FF
        txs
        sta TED_ROM
        ldx #0
:       lda $D000,x
        sta FONT,x
        lda $D100,x
        sta FONT + $100,x
        lda $D200,x
        sta FONT + $200,x
        lda $D300,x
        sta FONT + $300,x
        inx
        bne :-
        sta TED_RAM
        lda #<__BSS_RUN__
        sta ptr
        lda #>__BSS_RUN__
        sta ptr + 1
        ldx #>__BSS_SIZE__
        ldy #0
        tya
@page:  cpx #0
        beq @rest
:       sta (ptr),y
        iny
        bne :-
        inc ptr + 1
        dex
        jmp @page
@rest:  cpy #<__BSS_SIZE__
        beq @done
        sta (ptr),y
        iny
        jmp @rest
@done:  jmp main

        .code

main:
        lda #0
        sta TED_BORDER
        sta TED_BG
        lda #$08                ; 40 columns, 128 characters and reverse
        sta TED_CTRL2
        lda TED_BMBASE          ; the characters from RAM
        and #$FB
        sta TED_BMBASE
        lda #>FONT
        sta TED_CHBASE
        lda #>COLRAM
        sta TED_VMBASE
        lda #$1B                ; on, text, 25 rows
        sta TED_SCROLLY
        ldx #0                  ; the screen empty, grey
:       lda #' '
        sta SCREEN,x
        sta SCREEN + $100,x
        sta SCREEN + $200,x
        sta SCREEN + $2E8,x
        lda #$51
        sta COLRAM,x
        sta COLRAM + $100,x
        sta COLRAM + $200,x
        sta COLRAM + $2E8,x
        inx
        bne :-
        ldx #0                  ; the texts
@text:  lda texts + 1,x
        beq @shown
        sta ptr + 1
        lda texts,x
        sta ptr
        lda texts + 2,x
        sta t_col
        ldy #0
@char:  lda (ptr),y
        beq @next
        sty t_y
        pha
        lda texts + 3,x         ; (where it goes: the screen's offset)
        clc
        adc t_y
        sta t_at
        lda texts + 4,x
        adc #0
        sta t_at + 1
        pla
        ldy #0
        sta (t_at),y
        lda t_at + 1            ; its colour $400 lower
        sec
        sbc #>(SCREEN - COLRAM)
        sta t_at + 1
        lda t_col
        sta (t_at),y
        ldy t_y
        iny
        bne @char
@next:  txa
        clc
        adc #5
        tax
        bne @text
@shown: jsr mus_start

; once a frame: the music on, where it is shown
@frame: lda TED_LINE            ; out of lines 200-215, then into them (a
        sec                     ; window: a line could pass unseen while
        sbc #200                ; the music's interrupt runs)
        cmp #16
        bcc @frame
:       lda TED_LINE
        sec
        sbc #200
        cmp #16
        bcs :-
        jsr mus_frame
        jsr show
        jmp @frame

; show: the bar (from 1, as a musician counts), the beat (1-4) and the
; sixteenth in it (1-4), each voice's level as a bar of up to 7
show:
        lda m_bar               ; the bar + 1 in decimal, three digits
        clc
        adc #1
        sta t_n
        lda m_bar + 1
        adc #0
        sta t_n + 1
        ldx #0
@digit: ldy #'0'
@sub:   lda t_n
        sec
        sbc tens_lo,x
        sta t_y
        lda t_n + 1
        sbc tens_hi,x
        bcc @put
        sta t_n + 1
        lda t_y
        sta t_n
        iny
        bne @sub
@put:   tya
        sta SCREEN + ROW_BAR * 40 + 17,x
        inx
        cpx #3
        bne @digit
        lda m_pos               ; the beat
        lsr a
        lsr a
        clc
        adc #'1'
        sta SCREEN + ROW_BAR * 40 + 27
        lda m_pos               ; the sixteenth
        and #3
        clc
        adc #'1'
        sta SCREEN + ROW_BAR * 40 + 29
        ldx #2                  ; the meters
@meter: ldy v_page,x
        lda m_level,y
        sta t_n
        lda meter_lo,x
        sta ptr
        lda meter_hi,x
        sta ptr + 1
        ldy #0
:       lda #$A0                ; (a reverse space: a block)
        cpy t_n
        bcc :+
        lda #' '
:       sta (ptr),y
        iny
        cpy #7
        bne :--
        dex
        bpl @meter
        rts

tens_lo:    .byte <100, <10, <1
tens_hi:    .byte >100, >10, >1
METER0      = SCREEN + ROW_METER * 40 + METER_X + 8
meter_lo:   .byte <METER0, <(METER0 + 80), <(METER0 + 160)
meter_hi:   .byte >METER0, >(METER0 + 80), >(METER0 + 160)

        .rodata
; the texts: where, its colour, where on the screen
.macro  text str, col, row, column
        .addr :+
        .byte col
        .addr SCREEN + (row) * 40 + (column)
        .pushseg
        .segment "STRINGS"
:       .byte str, 0
        .popseg
.endmacro

texts:  text "SO WHAT'CHA WANT", $71, 3, 12
        text "A PLUS/4 DEMO - THE SOUND FIRST", $41, 5, 4
        text "BAR      BEAT  .", $61, ROW_BAR, 13
        text "ORGAN", $45, ROW_METER, METER_X
        text "BASS", $43, ROW_METER + 2, METER_X
        text "DRUMS", $47, ROW_METER + 4, METER_X
        text "THREE VOICES MIXED IN SOFTWARE,", $31, 21, 4
        text "PLAYED THROUGH THE TED'S VOLUME", $31, 22, 4
        .addr 0

        .bss
t_col:  .res 1
t_y:    .res 1
t_n:    .res 2
