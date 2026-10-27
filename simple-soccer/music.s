; music.s - the title's music: three voices mixed in software and played
; through the TED's volume, Kernkraft 400 (data/title-music.txt).
;
; The mixing is International Karate's on the Plus/4 (System 3, 1986,
; brought over from the C64 by ATI, CSABO, SIZ and TLC; its title's player
; "Wave Convert V2.0", TLC of CNS, 1992), taken over as it is: the TED's sound in its "digital" mode, where the
; voices put out a level and the volume register is a 4-bit DAC, and timer
; 1 interrupting SAMPLE_RATE (5542) times a second. The interrupt is a
; short piece of code in the zero page that rewrites itself: each voice's
; phase is the low byte of the address it reads its wave from, its step
; and its wave page are operands, and the sample it adds up is the operand
; the next interrupt writes out first - so each comes at the same moment.
; A wave page holds $3B plus the wave at a level 0-3; the three voices'
; bytes add up to $B1 plus their levels: DA mode, both voices on, the
; volume 1 + the levels.
;
; What drives it is this file's own: once a frame mus_frame goes on with
; each voice's notes (tools/mkmusic.py has the format), walks its
; instrument's levels and puts its step and wave page into the interrupt.
; The wave pages are made at the start, $0400-$0DFF, free while the title
; is up (the figures' lists in the match).

        .include "game.inc"

        .export mus_start, mus_frame, mus_stop
        .import __SYNTH_LOAD__, __SYNTH_SIZE__
        .globalzp s_a, s_w1, s_w2, s_w3 ; (known as zero page before they are
                                        ; there: adc s_w1 a zero page add)

TED_T1LO    = $FF00
TED_T1HI    = $FF01
TED_SOUND   = $FF11
VOICES      = 3

        .segment "TITLE"
        .include "music.inc"    ; the notes (made by tools/mkmusic.py)

        .zeropage
m_ptr:  .res 2                  ; a voice's notes

; ---- the interrupt (copied into the zero page by mus_start) ---------------

        .segment "SYNTH": zeropage

; A voice's part, the same three times (12 bytes apart): the step added
; to the phase, its high byte into the address of the wave
.macro  voice ph, fl, fh, wave
        lda #0
ph = * - 1                      ; (its phase, low)
        adc #0
fl = * - 1                      ; (its step)
        sta ph
        lda #0
fh = * - 1
        adc wave
        sta wave
.endmacro

synth:  sta s_a
        lda #BASE3
s_out = * - 1                   ; (the sample worked out last time)
        sta TED_SOUND
        dec TED_IRQ             ; (writes the bits back: acknowledged)
        voice s_ph1, s_f1l, s_f1h, s_w1
        voice s_ph2, s_f2l, s_f2h, s_w2
        voice s_ph3, s_f3l, s_f3h, s_w3
        clc
        lda PAGES * 256
s_w1 = * - 2                    ; (its phase, high)
s_p1 = * - 1                    ; (its wave page)
        adc PAGES * 256
s_w2 = * - 2
        adc PAGES * 256
s_w3 = * - 2
        sta s_out
        lda #0
s_a = * - 1                     ; (A as it was)
        rti

BASE        = $3B               ; a wave page's level 0
BASE3       = 3 * BASE          ; three of them: $B1

        .segment "TITLE"

; mus_start: the wave pages made, the interrupt in the zero page and on,
; the voices at their start
mus_start:
        sei
        ; 10 pages: one flat (level 0), then 3 to a wave (pulse 50 %, saw,
        ; noise) at the levels 1-3 - BASE + the wave (0-255) * (level + 1)
        ; / 256
        ldx #0
@page:  txa
        clc
        adc #PAGES
        sta @put + 2
        lda pg_lvl,x
        sta g_lvl               ; (the level: added up level + 1 times)
        lda pg_wave,x
        sta g_wave
        ldy #0
@byte:  lda g_wave              ; the wave here
        beq @p50
        cmp #2
        beq @saw
        bcs @noise
        cpy #64                 ; pulse 25 %
        jmp @pulse
@p50:   cpy #128
@pulse: lda #0
        bcs @wave
        lda #255
        bne @wave
@saw:   tya
        jmp @wave
@noise: jsr rnd
@wave:  sta g_val               ; * (level + 1), the high byte
        stx g_x
        ldx g_lvl
        lda #0
        sta g_hi
        clc
:       adc g_val
        bcc :+
        inc g_hi
        clc
:       dex
        bpl :--
        ldx g_x
        lda g_hi
        clc
        adc #BASE
@put:   sta PAGES * 256,y
        iny
        bne @byte
        inx
        cpx #10
        bne @page
        ; the interrupt into the zero page
        ldx #<(__SYNTH_SIZE__ - 1)
:       lda __SYNTH_LOAD__,x
        sta synth,x
        dex
        bpl :-
        ; the voices at their start
        ldx #VOICES - 1
:       lda v_start_lo,x
        sta v_ptl,x
        lda v_start_hi,x
        sta v_pth,x
        lda #1
        sta v_left,x
        lda #0
        sta v_ins,x
        lda #ENV_REST
        sta v_env,x
        dex
        bpl :-
        lda #TICK_DIV - TICK_ADD ; (a tick at once)
        sta m_acc
        ; timer 1, its interrupt
        lda #<synth
        sta $FFFE
        lda #>synth
        sta $FFFF
        lda #<LATCH
        sta TED_T1LO
        lda #>LATCH
        sta TED_T1HI
        lda #$08
        sta TED_IRQEN
        lda TED_IRQ
        sta TED_IRQ
        cli
        rts

; mus_stop: the interrupt off, the TED quiet and out of its digital mode
mus_stop:
        lda #0
        sta TED_IRQEN
        lda TED_IRQ
        sta TED_IRQ
        lda #0
        sta TED_SOUND
        rts

; mus_frame: a frame of the music - a tick (a sixteenth) every 21/4
; frames, and a voice's next note when its ticks are up; each voice's
; level, its kick's falling pitch, its noise
mus_frame:
        lda m_acc
        clc
        adc #TICK_ADD
        cmp #TICK_DIV
        bcc :+
        sbc #TICK_DIV
:       sta m_acc
        lda #0
        rol a                   ; (the carry: a tick)
        sta m_tick
        ldx #VOICES - 1
@voice: lda m_tick
        beq :+
        dec v_left,x
        bne :+
        jsr event
:       jsr sound
        dex
        bpl @voice
        rts

; event: voice X's next note or rest, past what comes before it. Keeps X.
event:
        lda v_ptl,x
        sta m_ptr
        lda v_pth,x
        sta m_ptr + 1
        ldy #0
@byte:  lda (m_ptr),y
        iny
        cmp #$60
        bcc @note
        beq @rest
        cmp #$80
        bcc @len
        cmp #$FD
        bcs @flow
        and #$0F                ; an instrument
        sta v_ins,x
        jmp @byte
@len:   sbc #$5F                ; (carry clear: - $60)
        sta v_len,x
        jmp @byte
@flow:  bne @back
        lda (m_ptr),y           ; $FD: a pattern - where to come back to
        sta m_lo
        iny
        lda (m_ptr),y
        pha
        iny
        tya
        clc
        adc m_ptr
        sta v_rtl,x
        lda m_ptr + 1
        adc #0
        sta v_rth,x
        pla
        sta m_ptr + 1
        lda m_lo
        sta m_ptr
        ldy #0
        beq @byte
@back:  cmp #$FE
        bne @loop
        lda v_rtl,x             ; $FE: back from the pattern
        sta m_ptr
        lda v_rth,x
        sta m_ptr + 1
        ldy #0
        beq @byte
@loop:  lda v_loop_lo,x         ; $FF: the voice again
        sta m_ptr
        lda v_loop_hi,x
        sta m_ptr + 1
        ldy #0
        beq @byte
@rest:  lda #ENV_REST
        sta v_env,x
        jmp @on
@note:  asl a                   ; its step
        sty m_lo
        tay
        lda m_notes,y
        sta v_fl,x
        lda m_notes + 1,y
        sta v_fh,x
        ldy v_ins,x             ; its levels from the start
        lda i_env,y
        sta v_env,x
        ldy m_lo
@on:    tya                     ; on past it
        clc
        adc m_ptr
        sta v_ptl,x
        lda m_ptr + 1
        adc #0
        sta v_pth,x
        lda v_len,x
        sta v_left,x
        rts

; sound: voice X's level this frame, its pitch, into the interrupt. Keeps X.
sound:
        ldy v_env,x             ; the level, and on to the next unless
        lda m_envs,y            ; this is the last
        sta m_lvl
        lda m_envs + 1,y
        cmp #$FF
        beq :+
        inc v_env,x
:       ldy v_ins,x
        lda i_flags,y
        bpl @noise
        lda v_fh,x              ; the kick: an eighth lower each frame
        sta m_hi
        lda v_fl,x
        lsr m_hi
        ror a
        lsr m_hi
        ror a
        lsr m_hi
        ror a
        sta m_lo
        lda v_fl,x
        sec
        sbc m_lo
        sta v_fl,x
        lda v_fh,x
        sbc m_hi
        sta v_fh,x
        lda i_flags,y
@noise: asl a
        bpl :+
        jsr rnd                 ; noise: a step at random
        sta v_fh,x
:       lda m_lvl               ; its wave page at its level (0: the flat
        beq :+                  ; one)
        clc
        adc i_wave,y
        bne :++
:       lda #PAGES
:       ldy page_at,x
        sta s_p1,y
        ldy step_at,x
        lda v_fl,x
        sta s_f1l,y
        lda v_fh,x
        sta s_f1h,y
        rts

; rnd: an 8-bit Galois LFSR, never 0. Keeps X, Y.
rnd:    lda m_rnd
        asl a
        bcc :+
        eor #$1D
:       sta m_rnd
        rts

page_at:    .byte 0, s_w2 - s_w1, s_w3 - s_w1
pg_wave:    .byte 0, 0, 0, 0, 2, 2, 2, 3, 3, 3  ; each page's wave (mus_start's
pg_lvl:     .byte 0, 1, 2, 3, 1, 2, 3, 1, 2, 3  ; 0 pulse, 2 saw, 3 noise), level
step_at:    .byte 0, s_f2l - s_f1l, s_f3l - s_f1l

; each voice's
v_ptl:      .res VOICES         ; where its notes are
v_pth:      .res VOICES
v_rtl:      .res VOICES         ; where a pattern comes back to
v_rth:      .res VOICES
v_left:     .res VOICES         ; ticks to its next note
v_len:      .res VOICES         ; ticks of a note
v_ins:      .res VOICES         ; its instrument
v_env:      .res VOICES         ; its place in m_envs
v_fl:       .res VOICES         ; its step
v_fh:       .res VOICES
m_acc:      .byte 0             ; (fourths of a frame) to the next tick
m_tick:     .byte 0
m_lvl:      .byte 0
m_lo:       .byte 0
m_hi:       .byte 0
m_rnd:      .byte $5A
g_lvl:      .byte 0             ; (mus_start's)
g_wave:     .byte 0
g_val:      .byte 0
g_hi:       .byte 0
g_x:        .byte 0
