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
;
; Assembled with BOOT defined, the same is the loading screen's music: the
; disk's file "music" (build.sh, bootmus.cfg), which the boot (boot.s)
; loads to $E100 and starts there while the flags and the game load - its
; interrupt out of the zero page (the game's file loads over that), its
; wave pages around the boot's characters (page_tab), and once a frame,
; counted in its own interrupts, its notes and the boot's ball (bm_hook).
; The title then goes on with the song where it is (mus_start): its
; voices, their phases, taken over (build/gen/bootmus.inc: where they are).

        .include "game.inc"

.ifdef BOOT
        .export bm_start, bm_hook, synth, v_ptl, m_data, s_ph1, s_ph2, s_ph3

        .segment "BMLOAD"
        .addr bm_start          ; (the file's load address)

        .segment "BMHEAD"
bm_start:
        jmp start               ; A/Y: what to call each frame
bm_hook:
        jmp $FFFF               ; (an rts once the title takes over)
.else
        .include "bootmus.inc"
        .export mus_start, mus_frame, mus_stop
        .import __SYNTH_LOAD__, __SYNTH_SIZE__
        .globalzp s_a, s_w1, s_w2, s_w3 ; (known as zero page before they are
                                        ; there: adc s_w1 a zero page add)
.endif

TED_T1LO    = $FF00
TED_T1HI    = $FF01
TED_SOUND   = $FF11
VOICES      = 3

        .segment "TITLE"
m_data:
        .include "music.inc"    ; the notes (made by tools/mkmusic.py)

.ifdef BOOT
; the boot's wave pages, where its screen leaves room: $E700, $EF00-$F7FF
page_tab:   .byte $E7, $EF, $F0, $F1, $F2, $F3, $F4, $F5, $F6, $F7
FLAT        = $E7
.else
FLAT        = PAGES
.endif

        .zeropage
m_ptr:  .res 2                  ; a voice's notes

; ---- the interrupt (copied into the zero page by mus_start) ---------------

.ifdef BOOT
        .segment "SYNTH"
.else
        .segment "SYNTH": zeropage
.endif

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
        lda FLAT * 256
s_w1 = * - 2                    ; (its phase, high)
s_p1 = * - 1                    ; (its wave page)
        adc FLAT * 256
s_w2 = * - 2
        adc FLAT * 256
s_w3 = * - 2
        sta s_out
.ifdef BOOT
        dec s_cnt               ; a frame's worth of samples: the frame's
        beq frame               ; work
.endif
        lda #0
s_a = * - 1                     ; (A as it was)
        rti

.ifdef BOOT
; A frame of the music and the boot's own, the interrupt on meanwhile (it
; takes some 20 samples' time): A, as the interrupt found it, from s_a
; before the next one changes it
frame:  lda s_fpi
        sta s_cnt
        lda s_a
        pha
        txa
        pha
        tya
        pha
        cli
        jsr mus_frame
        jsr bm_hook
        pla
        tay
        pla
        tax
        pla
        rti

s_cnt:  .byte 1                 ; samples to the next frame
s_fpi:  .byte 0                 ; samples a frame: 111 (PAL), 93 (NTSC)
.endif

BASE        = $3B               ; a wave page's level 0
BASE3       = 3 * BASE          ; three of them: $B1

        .segment "TITLE"

.ifdef BOOT
; start: the wave pages made, the voices at their start, the interrupt on
; - instead of the boot's own, which was the raster's; A/Y what to call
; each frame. From here the ROM must stay out: the interrupt goes through
; $FFFE in the RAM.
start:  sta bm_hook + 1
        sty bm_hook + 2
        jsr pages               ; (the boot's interrupt meanwhile)
        jsr voices
        lda #111                ; a frame, in samples: 312 lines of 57
        bit TED_CTRL2           ; ticks of the timer (PAL), 262 (NTSC)
        bvc :+
        lda #93
:       sta s_fpi
        sei
        lda #<synth
        sta $FFFE
        lda #>synth
        sta $FFFF
        jsr timer
        cli
        rts
.else
; mus_start: the wave pages made, the interrupt in the zero page and on,
; the voices at their start - or, if the boot's music plays (the disk's
; loading screen: boot.s), the song going on as it is, from here
mus_start:
        lda $FFFE
        cmp #<BM_SYNTH
        bne @fresh
        lda $FFFF
        cmp #>BM_SYNTH
        bne @fresh
        lda #$60                ; (rts: the boot's ball no more - its code
        sta BM_HOOK             ; is where the wave pages go)
        cli                     ; (the game's start held it up)
        jsr pages
        sei
        ldx #STATE - 1          ; the voices as they are,
:       lda BM_STATE,x
        sta v_ptl,x
        dex
        bpl :-
        ldx #VOICES * 2 - 1     ; where they read their notes in this copy
:       lda v_ptl,x             ; (v_ptl, v_rtl: low; v_pth, v_rth: high)
        clc
        adc #<(m_data - BM_DATA)
        sta v_ptl,x
        lda v_pth,x
        adc #>(m_data - BM_DATA)
        sta v_pth,x
        dex
        bpl :-
        lda BM_PH1              ; their phases
        sta s_ph1
        lda BM_PH2
        sta s_ph2
        lda BM_PH3
        sta s_ph3
        jsr mus_frame           ; (the boot's frame, a little early: the
        jmp @vector             ; steps and pages into this interrupt)
@fresh: sei
        lda #0                  ; no interrupts from the TED but the
        sta TED_IRQEN           ; music's (the ROM is out, the match's is
        lda TED_IRQ             ; not set up yet)
        sta TED_IRQ
        jsr pages
        jsr voices
        jsr timer
@vector:
        lda #<synth
        sta $FFFE
        lda #>synth
        sta $FFFF
        cli
        rts
.endif

; pages: the wave pages, 10: one flat (level 0), then 3 to a wave (pulse
; 50 %, saw, noise) at the levels 1-3 - BASE + the wave (0-255) * (level +
; 1) / 256; and the interrupt into the zero page
pages:
        ldx #0
@page:
.ifdef BOOT
        lda page_tab,x
.else
        txa
        clc
        adc #PAGES
.endif
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
.ifndef BOOT
        ldx #<(__SYNTH_SIZE__ - 1)
:       lda __SYNTH_LOAD__,x
        sta synth,x
        dex
        bpl :-
.endif
        rts

; voices: each at its start
voices: ldx #VOICES - 1
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
        rts

; timer: timer 1 and its interrupt, the only one (on with cli)
timer:  lda #<LATCH
        sta TED_T1LO
        lda #>LATCH
        sta TED_T1HI
        lda #$08
        sta TED_IRQEN
        lda TED_IRQ
        sta TED_IRQ
        rts

.ifndef BOOT
; mus_stop: the interrupt off, the TED quiet and out of its digital mode
mus_stop:
        lda #0
        sta TED_IRQEN
        lda TED_IRQ
        sta TED_IRQ
        lda #0
        sta TED_SOUND
        rts
.endif

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
:
.ifdef BOOT
        tay                     ; (the boot's pages are elsewhere)
        lda page_tab - PAGES,y
.endif
        ldy page_at,x
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

; each voice's (from v_ptl to m_rnd: what the title takes over from the
; boot, the pointers' low bytes first)
v_ptl:      .res VOICES         ; where its notes are
v_rtl:      .res VOICES         ; where a pattern comes back to
v_pth:      .res VOICES
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
STATE       = * - v_ptl
g_lvl:      .byte 0             ; (mus_start's)
g_wave:     .byte 0
g_val:      .byte 0
g_hi:       .byte 0
g_x:        .byte 0
