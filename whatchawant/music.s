; music.s - the music: three voices mixed in software and played through
; the TED's volume (data/music.txt, tools/mkmusic.py).
;
; The mixing is International Karate's on the Plus/4 (System 3, 1986,
; brought over from the C64 by ATI, CSABO, SIZ and TLC; its title's player
; "Wave Convert V2.0", TLC of CNS, 1992), as Simple Soccer's title has it:
; the TED's sound in its "digital" mode, where the voices put out a level
; and the volume register is a 4-bit DAC, and timer 1 interrupting
; SAMPLE_RATE (5542) times a second. The interrupt is a short piece of
; code in the zero page that rewrites itself: each voice's phase is the
; low byte of the address it reads its wave from, its step and its wave
; page are operands, and the sample it adds up is the operand the next
; interrupt writes out first - so each comes at the same moment. A wave
; page holds $3B plus the wave at a level; the three voices' bytes add up
; to $B1 plus their levels: DA mode, both voices on, the volume 1 + the
; levels.
;
; What drives it is Simple Soccer's sequencer, grown for an organ: once a
; frame mus_frame goes on with each voice's notes, walks its instrument's
; pages (a page a frame: the wave can change - a Hammond's percussion -
; and the list can loop - a Leslie's tremolo), sways its pitch (the
; Leslie's vibrato) and puts its step and wave page into the interrupt.
; The ticks can swing: those on the beat longer than those off it. The
; wave pages are made by tools/mkmusic.py and loaded with the program.

        .include "demo.inc"

        .export mus_start, mus_frame, mus_stop
        .export m_pos, m_bar, v_page, m_level
        .import __SYNTH_LOAD__, __SYNTH_SIZE__
        .globalzp s_a, s_w1, s_w2, s_w3 ; (known as zero page before they are
                                        ; there: adc s_w1 a zero page add)

TED_T1LO    = $FF00
TED_T1HI    = $FF01
TED_SOUND   = $FF11
VOICES      = 3

        .rodata
        .include "music.inc"    ; the notes, the pages (tools/mkmusic.py)

PAGES       = >m_pages

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
        lda m_pages
s_w1 = * - 2                    ; (its phase, high)
s_p1 = * - 1                    ; (its wave page)
        adc m_pages
s_w2 = * - 2
        adc m_pages
s_w3 = * - 2
        sta s_out
        lda #0
s_a = * - 1                     ; (A as it was)
        rti

BASE        = $3B               ; a wave page's level 0
BASE3       = 3 * BASE          ; three of them: $B1

        .code

; mus_start: the interrupt in the zero page and on, the voices at their
; start
mus_start:
        sei
        ldx #<(__SYNTH_SIZE__ - 1)
:       lda __SYNTH_LOAD__,x
        sta synth,x
        dex
        bpl :-
        ldx #VOICES - 1
:       lda v_start_lo,x
        sta v_ptl,x
        lda v_start_hi,x
        sta v_pth,x
        lda #1
        sta v_left,x
        lda #0
        sta v_ins,x
        sta v_vph,x
        lda #ENV_REST
        sta v_env,x
        dex
        bpl :-
        lda #TICK_ODD - TICK_ADD ; (a tick at once: m_pos is odd)
        sta m_acc
        lda #$FF                ; (the first tick makes it bar 0, tick 0)
        sta m_pos
        sta m_bar
        sta m_bar + 1
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

; mus_frame: a frame of the music - a tick (a sixteenth) when its frames
; are up (TICK_EVEN or TICK_ODD fourths of a frame, by turns: the swing),
; and a voice's next note when its ticks are up; each voice's page, its
; kick's falling pitch, its noise, its vibrato. m_bar, m_pos: where the
; music is, the bar and its tick (0-15) - for what goes with it
mus_frame:
        lda m_pos               ; this tick's length
        lsr a
        lda #TICK_EVEN
        bcc :+
        lda #TICK_ODD
:       sta m_lo
        lda m_acc
        clc
        adc #TICK_ADD
        cmp m_lo
        bcc :+
        sbc m_lo
:       sta m_acc
        lda #0
        rol a                   ; (the carry: a tick)
        sta m_tick
        beq @voices
        inc m_pos               ; where the music is
        lda m_pos
        cmp #16
        bcc @voices
        lda #0
        sta m_pos
        inc m_bar
        bne @voices
        inc m_bar + 1
@voices:
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
        bcs :+
        jmp @note
:       bne :+
        jmp @rest
:       cmp #$80
        bcc @len
        cmp #$C0
        bcs @more
        and #$3F                ; an instrument
        sta v_ins,x
        jmp @byte
@len:   sbc #$5F                ; (carry clear: - $60)
        sta v_len,x
        jmp @byte
@more:  cmp #$F0
        bne :+
        jmp @on                 ; $F0: the note held on
:       cmp #$F1
        bne :+
        sta m_leg               ; $F1: the next note without a new attack
        jmp @byte
:       cmp #$FD
        bne @back
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
        ldy m_leg               ; its pages from the start (unless legato)
        bne :+
        ldy v_ins,x
        lda i_env,y
        sta v_env,x
:       lda #0
        sta m_leg
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

; sound: voice X's page this frame, its pitch, into the interrupt. Keeps X.
sound:
        ldy v_env,x             ; the page, and on to the next: unless
        lda m_envs,y            ; this is the last ($FF), or the list
        sta v_page,x            ; loops ($FE: on at the next byte)
        lda m_envs + 1,y
        cmp #$FF
        beq @held
        cmp #$FE
        bne @next
        lda m_envs + 2,y
        sta v_env,x
        jmp @held
@next:  inc v_env,x
@held:  ldy v_ins,x
        lda i_drop,y
        beq @noise
        sta m_cnt               ; a kick, a boom: the step / 2^n lower each
        lda v_fh,x              ; frame
        sta m_hi
        lda v_fl,x
:       lsr m_hi
        ror a
        dec m_cnt
        bne :-
        sta m_lo
        lda v_fl,x
        sec
        sbc m_lo
        sta v_fl,x
        lda v_fh,x
        sbc m_hi
        sta v_fh,x
@noise: lda i_flags,y
        and #$40
        beq :+
        jsr rnd                 ; noise: a step at random
        sta v_fh,x
:       lda v_fl,x              ; the step that sounds: the note's, swayed
        sta m_lo
        lda v_fh,x
        sta m_hi
        lda i_vspd,y
        beq @out
        clc                     ; the vibrato: on round its turn, and
        adc v_vph,x             ; its 32 steps' one there times the
        sta v_vph,x             ; note's step / 256 added
        lsr a
        lsr a
        lsr a
        clc
        adc i_vib,y
        tay
        lda m_vib,y
        beq @out
        bmi @down
        sta m_cnt
:       lda m_lo
        clc
        adc v_fh,x
        sta m_lo
        bcc :+
        inc m_hi
:       dec m_cnt
        bne :--
        beq @out
@down:  eor #$FF
        clc
        adc #1
        sta m_cnt
:       lda m_lo
        sec
        sbc v_fh,x
        sta m_lo
        bcs :+
        dec m_hi
:       dec m_cnt
        bne :--
@out:   lda v_page,x            ; its wave page
        clc
        adc #PAGES
        ldy page_at,x
        sta s_p1,y
        ldy step_at,x
        lda m_lo
        sta s_f1l,y
        lda m_hi
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
step_at:    .byte 0, s_f2l - s_f1l, s_f3l - s_f1l

        .bss
; each voice's
v_ptl:      .res VOICES         ; where its notes are
v_pth:      .res VOICES
v_rtl:      .res VOICES         ; where a pattern comes back to
v_rth:      .res VOICES
v_left:     .res VOICES         ; ticks to its next note
v_len:      .res VOICES         ; ticks of a note
v_ins:      .res VOICES         ; its instrument
v_env:      .res VOICES         ; its place in m_envs
v_page:     .res VOICES         ; its page now (0: silent)
v_fl:       .res VOICES         ; its note's step
v_fh:       .res VOICES
v_vph:      .res VOICES         ; its vibrato's turn
m_acc:      .res 1              ; (fourths of a frame) to the next tick
m_tick:     .res 1
m_pos:      .res 1              ; the tick in the bar, 0-15
m_bar:      .res 2              ; the bar, from 0
m_lo:       .res 1
m_hi:       .res 1
m_cnt:      .res 1
m_leg:      .res 1              ; the next note legato

        .data
m_rnd:      .byte $5A
