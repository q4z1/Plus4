; ---------------------------------------------------------------------------
; engine.s - the Plus/4 end of trainschedule
;
; One raster interrupt per picture, in the vertical blank: it counts the
; pictures (all time in the game is counted in them), reads keyboard and
; joysticks, and is the only place the TED's colour registers are written -
; a real TED draws a pixel wherever one is written while the beam shows it.
; The KERNAL is not used once the game runs: the interrupt is ours alone.
; With the title picture up there is a second one, where its multicolour
; part ends and the hires part begins (tools/mkpicture.py, boot.s).
; ---------------------------------------------------------------------------

        .setcpu "6502"
        .macpack longbranch
        .export _eng_init, _eng_hits, _eng_romfont
        .export _frames, _keys, _eng_hits2
        .export _scrn, _colr, _eng_vmbase, _dbg_keys, _dbg_n
        .export _eng_blank, _eng_unblank, _eng_irqon, _eng_show, _eng_dark, _eng_mode, _title_bg, _title_mc
        .export _title_split, _eng_bmtext, _title_credits, _title_ready
        .export _mus_start, _mus_quiet, _mus_song, _eng_keepirq
        .export _mus_off, _mus_toggle, _tk_start, _tk_on, _eng_choice
        .export _eng_sfx, _sfx_arrive, _sfx_leave
        .export _eng_font2
        .importzp sp, ptr1, ptr2, ptr3, ptr4

TED_SCROLLY = $FF06
TED_CTRL2   = $FF07
TED_KEYS    = $FF08
TED_IRQ     = $FF09
TED_IRQEN   = $FF0A
TED_RCMP    = $FF0B
TED_BMBASE  = $FF12
TED_CHBASE  = $FF13
TED_VMBASE  = $FF14
FONT        = $C000             ; the characters (game.inc)
TED_BG      = $FF15
TED_RHI     = $FF1C              ; the beam's line: bit 8
TED_RLO     = $FF1D              ; and bits 0-7
TED_BORDER  = $FF19
TED_HPOS    = $FF1E             ; the beam's place in its line
KEY_ROW     = $FD30

VBL_LINE    = 251               ; lines 251-268 are not drawn at all
BOARD_IRQ   = 18 * 8 + 4        ; the board's interrupt: row 18's first line
COL_PAPER   = $78               ; the book's pages: background 0 from row
                                ; 18's fifth line on, and 1 and 2 (game.inc)
COL_RULE    = $6D               ; the ruling (game.inc)
COL_COVER   = $22               ; its cover (game.inc)
COL_MC2     = $31               ; multicolour 2 above it: grey
COL_MC1     = $55               ; multicolour 1 above it: COL_ROUTE (game.inc)
BOARD_ROW   = 19                ; its first row (game.inc: BOARD_TOP)
COL_BG      = $00
TK_STRIP    = $DE00             ; the ticker's strip (game.inc)
LOCK_CODE   = 64                ; the locks' characters at $D800 (game.inc)
C_FIRST     = 64                ; the map's first character (game.inc)
VIEW_TOP    = 2                 ; the map's first row (game.inc)
LOCK_BYTES  = 6 * 8

        .segment "ENGZP": zeropage
src:        .res 2
dst:        .res 2

        .data
rl_h:       .byte 146           ; TED_HPOS from which the beam is past a
                                ; line's picture (rule): from 120 to 180 in
                                ; plus4emu, 100 to 170 in Yape
; The screen being written to: characters and colours. There are two, the
; second at $F000 (colours) and $F400 (characters): a new view is drawn into
; the one not shown, and the interrupt shows it when it is done.
_scrn:       .word $0C00
_colr:      .word $0800

        .bss
want_vm:    .res 1              ; for $FF14 in the next vertical blank, 0: none
want_ch:    .res 1              ; the characters' page there, 0: as they are
want_off:   .res 1              ; the screen off in the next vertical blank
_eng_mode:  .res 1              ; 0 text, 1 the title's bitmap
_title_bg:  .res 1              ; its colours: background, multicolour 1
_title_mc:  .res 1
_title_split: .res 1            ; the raster line its hires part starts at
irq_at:     .res 1              ; the next interrupt's line
rl_i:       .res 1              ; the book's next row to rule (rl_*)
_eng_keepirq: .res 1            ; 1: eng_blank leaves the interrupt on (the
                                ; fast loader does not mind it)

        .segment "STKBSS"       ; (trainschedule.cfg)
mstate:     .res 24             ; the music player's place (music.inc)
_mus_song:  .res 2              ; the song playing, 0: none
mus_sfx:    .res 1              ; frames left of a sound effect's step on
                                ; voice 2, 0: none playing
        .bss
_dbg_keys:  .res 1              ; for the tests: keys held as if pressed
_dbg_n:     .res 1              ; and pictures a turn of the loop, if not 0
_mus_off:   .res 1              ; 1: the music is off (F1, mus_toggle)
_tk_on:     .res 1              ; the ticker runs
tk_bits:    .res 1              ; columns left of its glyph
tk_glyph:   .res 8
tk_ct:      .res 1              ; pictures till the colours move on
tk_phase:   .res 1
_frames:    .res 1
_keys:      .res 1              ; K_... (game.h) down now
hits:       .res 1              ; pressed since eng_hits last asked
hits2:      .res 1              ; the same for more keys: Z 1
kprev2:     .res 1
knew:       .res 1
fstate:     .res 1              ; fire: 0 up, 1 down on its own, 2 a command
kr2:        .res 1
kprev:      .res 1
kr:         .res 1
want_on:    .res 1

        .code

; eng_init: the TED set up for the game, our interrupt running. The screen
; comes on in the next vertical blank, its colours set there first.
_eng_init:
        lda _eng_mode           ; the title picture up already (boot.s):
        beq :++                 ; it stays, the boot's interrupt giving
        lda #230                ; way to ours below it, where it is all
:       cmp $FF1D               ; hires till the vertical blank - only
        bne :-                  ; there: stopped between its two switches,
:       sei                     ; a picture would stay multicolour
        lda #0
        sta TED_IRQEN
        lda TED_IRQ
        sta TED_IRQ
        lda _eng_mode
        bne @keep
        lda TED_SCROLLY         ; off till the interrupt switches it on
        and #$EF
        sta TED_SCROLLY
@keep:
        lda TED_CTRL2
        and #$50                ; keep PAL/NTSC, and multicolour as it is
        ora #$88                ; (the vertical blank sets it); 256
        sta TED_CTRL2           ; characters, 40 columns
        lda TED_BMBASE
        and #$FB                ; characters from RAM
        sta TED_BMBASE
        lda TED_CHBASE
        and #$03
        ora #$C0                ; at $C000
        sta TED_CHBASE
        lda #$08                ; colours $0800, codes $0C00
        sta TED_VMBASE
        lda #0
        sta _keys
        sta hits
        sta kprev
        lda #1
        sta want_on
        lda #<irq
        sta $FFFE
        lda #>irq
        sta $FFFF
        lda #<kirq              ; with the ROM in, the KERNAL's way in to
        sta $0314               ; an interrupt: no longer the boot
        lda #>kirq              ; program's, whose memory the game takes
        sta $0315
        lda BOOT_MS+22          ; the boot program's music: on with it,
        cmp #$53                ; where it is (its place copied)
        bne :++
        lda BOOT_MS+16
        beq :++
        ldx #23
:       lda BOOT_MS,x
        sta mstate,x
        dex
        bpl :-
        jsr mus_tables
        lda #<MUSIC
        sta _mus_song
        lda #>MUSIC
        sta _mus_song+1
:       lda #<nmi
        sta $FFFA
        lda #>nmi
        sta $FFFB
        lda #VBL_LINE
        sta TED_RCMP
        sta irq_at
        lda #$02                ; raster interrupt, compare bit 8 = 0
        sta TED_IRQEN
        cli
        rts

nmi:    rti

; show_on, in the vertical blank: the screen on, as text (the game), as
; the multicolour bitmap at $C000 (the title, _eng_mode 1), or as text in
; the characters at $D800 (the choice of a map, _eng_mode 2: the ticker's
; strip is its characters 192-231)
show_on:
        lda #0
        sta want_on
        lda TED_BMBASE
        and #$C3                ; characters from RAM, bitmap base cleared
        ldx _eng_mode
        cpx #1
        bne :+
        ora #$30                ; the bitmap at $C000
:       sta TED_BMBASE
        lda TED_CHBASE
        and #$03
        ora #$C0
        cpx #2
        bne :+
        ora #$18                ; $D800
:       sta TED_CHBASE
        cpx #2
        bne :+
        jsr font_d800
:       lda #COL_BG
        sta TED_BORDER
        ldx _eng_mode
        cpx #1
        bne @text
        lda _title_bg
        sta TED_BG
        lda _title_mc
        sta $FF16
        lda #$3B                ; bitmap, display on, 25 rows, y scroll 3
        sta TED_SCROLLY
        rts
@text:  lda TED_CTRL2           ; multicolour (cells with colour bit 3) in
        ora #$10                ; the game; the choice of a map has none,
        cpx #2                  ; the ticker's colours need all 16
        bne :+
        and #<~$10
:       sta TED_CTRL2
        lda #COL_BG
        sta TED_BG
        lda #COL_MC1            ; multicolour 1: green, the cursor and a
        sta $FF16               ; route in front of a train, in its cells
        lda #COL_MC2            ; multicolour 2: grey, the leg
        sta $FF17               ; of a set switch not in the route
        lda #COL_BG             ; extended colour 3: the board has none
        sta $FF18
        lda #$1B                ; text, display on, 25 rows, y scroll 3
        sta TED_SCROLLY
        rts

; show_off, in the vertical blank: the screen off, the border black
show_off:
        lda #0
        sta want_off
        sta TED_BORDER
        lda TED_SCROLLY
        and #$EF
        sta TED_SCROLLY
        rts

; eng_blank: the screen off and no interrupt at all - for the disk: the
; KERNAL loads with the ROM in and its own interrupt handler (Stardew
; Pond's way). The screen goes off in a vertical blank.
_eng_blank:
        lda TED_IRQEN
        and #$02
        beq @off
        lda #1
        sta want_off
:       lda want_off
        bne :-
        lda _eng_keepirq        ; the music goes on
        beq @off
        rts
@off:   sei
        lda $FF11               ; the music waits, silent
        and #$CF
        sta $FF11
        lda #0
        sta TED_IRQEN
        lda TED_IRQ
        sta TED_IRQ
        lda TED_SCROLLY
        and #$EF
        sta TED_SCROLLY
        cli
        rts

; eng_unblank: our interrupt running again, the screen on from the next
; vertical blank - as text, or the title's bitmap if _eng_mode is 1
_eng_unblank:
        jsr _eng_irqon
; eng_show: the screen on from the next vertical blank, as eng_unblank
_eng_show:
        lda #1
        sta want_on
:       lda want_on
        bne :-
        rts

; eng_irqon: our interrupt running again, the screen still off - a picture
; made out of sight first (eng_show brings it)
_eng_irqon:
        sei
        lda #<irq
        sta $FFFE
        lda #>irq
        sta $FFFF
        lda #VBL_LINE
        sta TED_RCMP
        sta irq_at
        lda #$02
        sta TED_IRQEN
        lda TED_IRQ
        sta TED_IRQ
        cli
        rts

; eng_dark: the screen off from the next vertical blank, our interrupt (and
; the music) running on
_eng_dark:
        lda #1
        sta want_off
:       lda want_off
        bne :-
        rts

; eng_hits: the keys pressed since the last call, and none from then on
_eng_hits:
        sei
        lda hits
        ldx #0
        stx hits
        cli
        rts

; eng_vmbase(v): show the screen at v ($08: $0800/$0C00, $F0: $F000/$F400)
; from the next vertical blank on, and wait for it - in the characters at
; $C000 again, should eng_font2 have shown their copy.
_eng_vmbase:
        ldx #>FONT
        sei
        sta want_vm
        stx want_ch
        cli
:       lda want_vm
        bne :-
        rts

; eng_font2: the screen shown in a copy of the characters from the next
; vertical blank on, so that they can be made afresh out of sight (the zoom
; changing); eng_vmbase shows them again with the new view
_eng_font2:
        ldx #0
:
.repeat 8, I
        lda FONT + I * $100,x
        sta font2 + I * $100,x
.endrepeat
        inx
        bne :-
        lda #>font2
        sta want_ch
:       lda want_ch
        bne :-
        rts

        .segment "FONT2"        ; (trainschedule.cfg)
font2:  .res $800
        .code

; eng_hits2: the same for the keys of the second byte (Z = 1)
_eng_hits2:
        sei
        lda hits2
        ldx #0
        stx hits2
        cli
        rts

; Both switch the ROM in, so they have to be below $8000 themselves:
; LOWCODE comes first in the program.
        .segment "LOWCODE"

; ---------------------------------------------------------------------------
; Music (music.inc): the title's song (the file at MUSIC) while the title
; and the choice of a map are up, the map's (data/music.txt, in its file:
; at SONG_BUF) in a level. mus_start(song): that one from its start; mus_quiet: none.
; mus_song: which is playing. Voice 2 gives way to sound effects: eng_sfx
; plays the one at A/X (sfx_arrive, sfx_leave), a step a picture at most,
; and the accompaniment comes back with its next note - as in Stardew
; Pond. mus_toggle (F1, or the choice of a map): the music off, where it
; is, or on again from there; sound effects are heard either way.
; ---------------------------------------------------------------------------
MUSIC   = $E800                 ; the title's song
BOOT_MS = $07A0                 ; the boot program's player's place
MSTATE  = mstate
MUS_SFX = mus_sfx
        .code
        .include "music.inc"

_mus_start:
        sta _mus_song
        stx _mus_song+1
        jmp mus_init

_mus_quiet:
        php
        sei
        lda #0
        sta mstate+16
        sta _mus_song
        sta _mus_song+1
        lda $FF11
        and #$CF
        sta $FF11
        plp
        rts

_eng_sfx:
        php
        sei
        ldy mus_sfx             ; one at a time: a second is not heard
        bne :+
        sta sfx_get+1
        stx sfx_get+2
        jsr sfx_step
:       plp
        rts

; sfx_step: the effect's next step on voice 2 (the interrupt's, or
; eng_sfx's with it held off). A step: its frames, the frequency register's
; low byte, then its high two bits | SFX_NOISE or SFX_REST; 0 frames: the end
sfx_step:
        jsr sfx_get
        sta mus_sfx
        cmp #0                  ; (sfx_get's flags are its pointer's)
        beq @end
        jsr sfx_get
        sta $FF0F
        jsr sfx_get
        tay
        and #$03
        sta mus_t
        lda $FF10
        and #$FC
        ora mus_t
        sta $FF10
        lda #$20                ; a square ...
        cpy #SFX_NOISE
        bcc :+
        lda #$40                ; ... or noise ...
        cpy #SFX_REST
        bcc :+
        lda #0                  ; ... or a rest
:       sta mus_t
        lda $FF11
        and #$90                ; voice 1 and the D/A bit kept
        ora mus_t
        ora mstate+17           ; the music's volume
        sta $FF11
        rts
@end:   lda $FF11               ; voice 2 silent, the music has it again
        and #$9F                ; from its next note
        sta $FF11
        rts
sfx_get:
        lda $FFFF
        inc sfx_get+1
        bne :+
        inc sfx_get+2
:       rts
mus_t:  .byte 0

; The effects. The TED has no envelopes: what dies away is a noise that
; grows darker, then stutters. TONE: the register for a square of hz.
SFX_NOISE = $40
SFX_REST  = $80
.define TONE(hz) (1024 - (110840 + (hz) / 2) / (hz))
.macro  step n, reg, kind
        .byte n, <(reg), >(reg) | kind
.endmacro
.macro  rest n
        step n, 0, SFX_REST
.endmacro
        .rodata
; a train in at its platform: brakes that squeal, then steam let off
_sfx_arrive:
        .repeat 6, i            ; the squeal, wavering down
        step 2, TONE(1800 - i * 40), 0
        step 2, TONE(1840 - i * 40), 0
        .endrepeat
        rest 8
        step 4, 1012, SFX_NOISE ; pschhh
        step 4, 1008, SFX_NOISE
        step 4, 1002, SFX_NOISE
        step 4, 996, SFX_NOISE
        step 4, 988, SFX_NOISE
        step 4, 980, SFX_NOISE
        step 2, 972, SFX_NOISE
        rest 1
        step 2, 964, SFX_NOISE
        rest 2
        step 1, 956, SFX_NOISE
        rest 2
        step 1, 948, SFX_NOISE
        .byte 0
; a train away from it: the whistle, two notes at once (a picture each),
; then the engine's first puffs, closer and closer
_sfx_leave:
        step 2, TONE(850), 0    ; the steam comes up to it
        .repeat 11
        step 1, TONE(880), 0    ; A and C sharp
        step 1, TONE(1109), 0
        .endrepeat
        step 2, TONE(860), 0
        rest 10
        .repeat 5, i            ; tschuff ... tschuff-tschuff
        step 2, 1000, SFX_NOISE
        step 3, 984, SFX_NOISE
        .if i < 4
        rest 16 - i * 3
        .endif
        .endrepeat
        .byte 0
        .code

_mus_toggle:
        php
        sei
        lda _mus_off
        eor #1
        sta _mus_off
        beq :++
        lda #$EF                ; voice 1 silent, voice 2 unless a sound
        ldx mus_sfx             ; effect has it
        bne :+
        lda #$CF
:       and $FF11
        sta $FF11
:       plp
        rts

        .segment "LOWCODE"

; eng_bmtext(lines): text into the title picture's hires part, in the
; ROM's characters (the set with lower case), as boot.s writes it: lines of
; the cell to start at (a word, 0 ends them), screen codes, $FF and a
; colour to change the colour, LOWER to set the rest of the line a pixel
; lower, 0 to end the line. The ROM is in for a
; character's eight bytes at a time, so the interrupt never waits long.
_eng_bmtext:
        sta ptr1
        stx ptr1+1
@line:  jsr @next               ; where: $C000 + cell * 8, $0800 + cell
        sta ptr3
        jsr @next
        sta ptr3+1
        ora ptr3
        jeq @done
        lda ptr3
        sta ptr2
        lda ptr3+1
        asl ptr2
        rol
        asl ptr2
        rol
        asl ptr2
        rol
        ora #$C0
        sta ptr2+1
        lda ptr3+1
        ora #$08
        sta ptr3+1
@char:  jsr @next
        beq @line
        cmp #$FF
        bne @glyph
        jsr @next
        sta bm_colour
        jmp @char
@glyph: ldx #0                  ; $D400 + code * 8
        stx ptr4+1
        asl
        rol ptr4+1
        asl
        rol ptr4+1
        asl
        rol ptr4+1
        sta ptr4
        lda ptr4+1
        ora #$D4
        sta ptr4+1
        php
        sei
        sta $FF3E               ; ROM in
        ldy #7
:       lda (ptr4),y
        sta (ptr2),y
        dey
        bpl :-
        sta $FF3F               ; ROM out
        plp
        iny                     ; the cell's colours
        lda bm_colour
        lsr
        lsr
        lsr
        lsr
        sta (ptr3),y            ; attribute: luminance for 1, 0 for 0
        lda ptr3+1
        ora #$04
        sta ptr3+1
        lda bm_colour
        asl
        asl
        asl
        asl
        sta (ptr3),y            ; character: colour for 1, black for 0
        lda ptr3+1
        and #<~$04
        sta ptr3+1
        lda ptr2                ; on to the next cell
        clc
        adc #8
        sta ptr2
        bcc :+
        inc ptr2+1
:       inc ptr3
        bne @char
        inc ptr3+1
        jmp @char
@done:  rts
@next:  ldy #0                  ; the next byte of the text, Z for 0
        lda (ptr1),y
        inc ptr1
        bne :+
        inc ptr1+1
:       tax
        rts

; an interrupt while the ROM is in (none should come): just let it go
kirq:   lda TED_IRQ
        sta TED_IRQ
        jmp $FCBE

; eng_romfont: screen codes 0-63 of the ROM's upper-case set into ours,
; and over 7 of them no text has the board's book (frame_chars)
_eng_romfont:
        php
        sei
        sta $FF3E               ; ROM in
        ldx #0
:       lda $D000,x
        sta $C000,x
        lda $D100,x
        sta $C100,x
        inx
        bne :-
        sta $FF3F               ; ROM out
        plp
        jmp frame_chars

        .code
; frame_chars: the characters of the board's book (game.inc FR_*) -
; codes the ROM's characters have and no text uses
frame_chars:
        ldx #FR_N * 8 - 1
@b:     txa
        lsr a
        lsr a
        lsr a
        tay
        lda fr_code,y
        asl a
        asl a
        asl a                   ; (carry: code 32 on, the font's next page)
        sta tmp
        txa
        and #7
        ora tmp
        tay
        lda fr_bits,x
        bcs :+
        sta FONT,y
        bcc :++
:       sta FONT + $100,y
:       dex
        bpl @b
        rts

        .rodata
; the book's (game.inc FR_*): its top edge, the top's corners, a rule (the
; columns', the fold), the top edge over the fold, the left side, the
; right. The cover 2 pixels wide, under 2 lines of gap at the top
fr_code:    .byte 0, 27, 28, 29, 30, 44, 46
FR_N = * - fr_code
fr_bits:    .byte $00, $00, $FF, $FF, $00, $00, $00, $00
            .byte $00, $00, $FF, $FF, $C0, $C0, $C0, $C0
            .byte $00, $00, $FF, $FF, $03, $03, $03, $03
            .byte $80, $80, $80, $80, $80, $80, $80, $80
            .byte $00, $00, $FF, $FF, $80, $80, $80, $80
            .byte $C0, $C0, $C0, $C0, $C0, $C0, $C0, $C0
            .byte $03, $03, $03, $03, $03, $03, $03, $03

; the book's rows 19-24 ruled (irq): each one's interrupt two lines before
; its write, the line before the one it is for (in whose right border it is
; written), the register and its colour, and the register of the row above
; to put back
rl_irq:     .byte 19 * 8 + 8, 20 * 8 + 8, 21 * 8 + 8, 22 * 8 + 8, 23 * 8 + 8
            .byte 24 * 8 + 7
RL_N = * - rl_irq
rl_line:    .byte 19 * 8 + 10, 20 * 8 + 10, 21 * 8 + 10, 22 * 8 + 10, 23 * 8 + 10
            .byte 24 * 8 + 9
rl_reg:     .byte $16, $17, $16, $17, $16, $17
rl_col:     .byte COL_RULE, COL_RULE, COL_RULE, COL_RULE, COL_RULE, COL_COVER
rl_back:    .byte $17, $16, $17, $16, $17, $16
        .segment "LOWCODE"

; font_d800, in the vertical blank that brings the choice of a map up: its
; characters at $D800 - the ROM's upper-case ones (codes 0-63) and the
; locks (64-69). Over the title's bitmap, which is gone from now on, so
; this cannot be done before; a copy of 560 bytes, done long before the
; beam is down at row 19, where the bitmap had them.
font_d800:
        sta $FF3E               ; ROM in
        ldx #0
:       lda $D000,x
        sta $D800,x
        lda $D100,x
        sta $D900,x
        inx
        bne :-
        sta $FF3F               ; ROM out
        ldx #LOCK_BYTES - 1
:       lda lock_chars,x
        sta $D800 + LOCK_CODE * 8,x
        dex
        bpl :-
        rts

; ---------------------------------------------------------------------------
; The ticker: a line of text that runs through the foot of the title and
; the choice of a map, a pixel a picture. Its strip of 40 cells is
; $DE00-$DF3F: row 24 of the title's bitmap, and characters 192-231 of
; the choice's font at $D800 - the same bytes, so the text runs on from
; the one into the other. Each picture the strip is rolled left a pixel,
; the next column of the next glyph (the ROM's characters with
; lower case) coming in at the right. tk_start: from the text's start,
; the strip empty; tk_on 0 stops it (the level takes the memory).
; ---------------------------------------------------------------------------
tk_tick:
        lda tk_bits
        bne :+
        jsr tk_next
:       dec tk_bits
        ldx #7
@row:   asl tk_glyph,x
.repeat 40, I
        rol TK_STRIP + (39 - I) * 8,x
.endrepeat
        dex
        bpl @row
        rts

; tk_next: the next character's glyph to tk_glyph, from the start again at
; the text's end
tk_next:
tk_rd:  lda tk_text             ; (the address moves on)
        cmp #$FF
        bne :+
        lda #<tk_text
        sta tk_rd+1
        lda #>tk_text
        sta tk_rd+2
        bne tk_rd
:       inc tk_rd+1
        bne :+
        inc tk_rd+2
:       ldx #0                  ; $D400 + code * 8
        stx tk_g+2
        asl a
        rol tk_g+2
        asl a
        rol tk_g+2
        asl a
        rol tk_g+2
        sta tk_g+1
        lda tk_g+2
        ora #$D4
        sta tk_g+2
        sta $FF3E               ; ROM in
        ldx #7
tk_g:   lda $D400,x
        sta tk_glyph,x
        dex
        bpl tk_g
        sta $FF3F               ; ROM out
        lda #8
        sta tk_bits
        rts

; tk_colours: the ticker's row in colours from the logo's gold to its
; blue and back (tk_ramp), the wave moving right a cell every TK_STEP
; pictures. On the title the bitmap's two matrices (luminance, colour of
; the 1 bits), in the choice of a map the colours of its characters.
TK_STEP = 4
tk_colours:
        dec tk_ct
        bpl :+
        lda #TK_STEP - 1
        sta tk_ct
        dec tk_phase
        bpl :+
        lda #31
        sta tk_phase
:       ldy tk_phase
        ldx #0
        lda _eng_mode
        cmp #1
        beq @title
@text:  lda tk_ramp,y
        sta $F000 + 24 * 40,x
        iny
        tya
        and #31
        tay
        inx
        cpx #40
        bne @text
        rts
@title: lda tk_ramp,y
        lsr a
        lsr a
        lsr a
        lsr a
        sta $0800 + 24 * 40,x   ; luminance for 1, 0 for 0
        lda tk_ramp,y
        asl a
        asl a
        asl a
        asl a
        sta $0C00 + 24 * 40,x   ; colour for 1, black for 0
        iny
        tya
        and #31
        tay
        inx
        cpx #40
        bne @title
        rts
        .code

; tk_start: the ticker from its start, in an empty strip (its colours are
; tk_colours', from the next picture on)
_tk_start:
        lda #0
        sta _tk_on
        sta tk_bits
        lda #<tk_text
        sta tk_rd+1
        lda #>tk_text
        sta tk_rd+2
        lda #0
        ldx #160
:       sta TK_STRIP - 1,x
        sta TK_STRIP + 159,x
        dex
        bne :-
@on:    lda #1
        sta _tk_on
        rts

; eng_choice: the choice of a map on, from the next vertical blank - the
; second screen ($F000/$F400), drawn by then, in the characters at $D800.
; From the title the change is all in that one blank: the ticker runs on.
_eng_choice:
        lda TED_IRQEN
        and #$02
        bne :+
        lda #2
        sta _eng_mode
        lda #$F0
        sta want_vm
        jmp _eng_unblank
:       sei
        lda #2
        sta _eng_mode
        lda #$F0
        sta want_vm
        lda #1
        sta want_on
        cli
:       lda want_on
        bne :-
        rts

        .bss
tmp:    .res 1
        .code

; ===========================================================================
; The raster interrupt
; ===========================================================================

irq:    pha
        txa
        pha
        tya
        pha
        lda TED_IRQ
        sta TED_IRQ
        lda irq_at
        cmp #VBL_LINE
        beq @vbl
        lda _eng_mode
        bne @title
        lda irq_at              ; a band of the map's (bands_vbl)
        cmp #BOARD_IRQ
        beq :++
        bcc :+
        jmp rule                ; (a row of the board's book)
:       jsr band
        jmp @out
        ; the game: the board, a book, in extended colour - the top two
        ; bits of a character's code choose its background, the paper of
        ; its rows among them ($FF16, $FF17) - and so without multicolour.
        ; Switched in row 18, the book's top edge: its characters (codes
        ; below 64, hires) look the same either way. Background 0 turns
        ; the paper there, in the row's fifth line (the beam's line counts
        ; one ahead): the two lines over the cover stay black, a gap to the
        ; map. The beam is not on the paper yet then: no snow (plus4emu)
:       lda TED_RHI
        lsr a
        bcs :++
        lda TED_RLO
        cmp #18 * 8 + 4 + 3
        bcc :-
        bne :++
        lda rl_h                ; (the line before's right border)
:       cmp TED_HPOS
        bcs :-
:       lda #COL_PAPER
        sta TED_BG
        lda TED_CTRL2
        and #<~$10
        sta TED_CTRL2
        lda TED_SCROLLY
        ora #$40
        sta TED_SCROLLY
        lda #COL_PAPER          ; (no cell of row 18 shows them: no snow)
        sta $FF17
        sta $FF16
        ldx #0
        stx rl_i
        lda rl_irq
        sta irq_at
        sta TED_RCMP
        jmp @out
@title: lda TED_CTRL2           ; the title's hires part, to the vertical
        and #<~$10              ; blank
        sta TED_CTRL2
        lda #VBL_LINE
        sta irq_at
        sta TED_RCMP
        jmp @out
@vbl:   lda _eng_mode           ; the game: the map in multicolour, the
        bne :+                  ; board's mode from row 18
        lda #COL_BG
        sta TED_BG
        lda TED_SCROLLY
        and #<~$40
        sta TED_SCROLLY
        lda TED_CTRL2
        ora #$10
        sta TED_CTRL2
        lda #COL_MC2
        sta $FF17
        lda #COL_MC1
        sta $FF16
        lda #BOARD_IRQ
        sta irq_at
        sta TED_RCMP
        bne :++
:       cmp #1                  ; the title: multicolour at the top, hires
        bne :+                  ; from its split
        lda TED_CTRL2
        ora #$10
        sta TED_CTRL2
        lda _title_split
        sta irq_at
        sta TED_RCMP
:       lda want_off
        beq :+
        jsr show_off
:       lda want_on
        beq :+
        jsr show_on
:       lda want_vm
        beq :+
        sta TED_VMBASE
        lda #0
        sta want_vm
:       lda want_ch             ; (in the same blank: eng_font2)
        beq :+
        lda TED_CHBASE
        and #$03
        ora want_ch
        sta TED_CHBASE
        lda #0
        sta want_ch
:       lda _tk_on              ; (before the beam is at the foot again)
        beq :+
        jsr tk_tick
        jsr tk_colours
:       inc _frames
        jsr bands_vbl           ; the bands' interrupts may come in from
        cli                     ; here on: the keys, the pointer and the
        jsr kpoll               ; music may wait for them, nothing of
        jsr ptr_irq             ; theirs in common
        jsr band_resolve
        lda mus_sfx             ; a sound effect's next step
        beq :+
        dec mus_sfx
        bne :+
        jsr sfx_step
:       lda _mus_off
        bne @out
        jsr mus_tick
@out:
irq_out:
        pla
        tay
        pla
        tax
        pla
        rti

; rule: a row of the board's book ruled: its register the ruling's blue for its
; last line, written in the right border of the line before (as above) -
; and back to the paper in the next row's interrupt, the row below
; on the other register meanwhile: only that write has to be on
; time. Row 24's turns the cover's two lines earlier, the book's
; lower edge, till the vertical blank. Too late (the interrupt kept
; waiting): no line this picture, rather than half a line
rule:   ldx rl_i
        ldy rl_back,x           ; the row above's register: paper again
        lda #COL_PAPER
        sta $FF00,y
        ldy rl_reg,x
        lda rl_col,x
        pha
        lda rl_line,x
        tax
        pla
:       cpx TED_RLO
        beq rl_w
        bcs :-
        bcc :++
rl_w:   tax
        lda rl_h
:       cmp TED_HPOS
        bcs :-
        txa
        sta $FF00,y
:       ldx rl_i                ; the next row's, if the beam is not past it
rl_n:   inx
        cpx #RL_N
        bcs rl_v
        lda TED_RLO
        cmp rl_irq,x
        bcs rl_n
        stx rl_i
        lda rl_irq,x
        bne :+
rl_v:   lda #VBL_LINE
:       sta irq_at
        sta TED_RCMP
        jmp irq_out

; ---------------------------------------------------------------------------
; Keyboard and joysticks, straight off the matrix. The row goes to both
; latches and $FF08 is read twice: the first read still sees the value
; just written. Both give 1 bits for what is down.
;
; K_ bits (game.h): up 1, down 2, left 4, right 8, fire 16, + 32, - 64,
; L 128. Joystick 1 or 2, cursor keys; fire is also Space and Return.
; F1 turns the music off and on, here, wherever the game is.
; ---------------------------------------------------------------------------
kpoll:  ldx #$FF
        stx KEY_ROW
        lda #$FB                ; joystick 1: fire is bit 6
        sta TED_KEYS
        lda TED_KEYS
        lda TED_KEYS
        eor #$FF
        tax
        and #$0F
        sta kr
        txa
        and #$40
        beq :+
        lda #16
        ora kr
        sta kr
:       lda #$FD                ; joystick 2: fire is bit 7
        sta TED_KEYS
        lda TED_KEYS
        lda TED_KEYS
        eor #$FF
        tax
        and #$0F
        ora kr
        sta kr
        txa
        and #$80
        beq :+
        lda #16
        ora kr
        sta kr
:       lda #$BF                ; cursor left 0, cursor right 3, + 6
        jsr krow
        tax
        and #$01
        beq :+
        lda #4
        ora kr
        sta kr
:       txa
        and #$08
        beq :+
        lda #8
        ora kr
        sta kr
:       txa
        and #$40
        beq :+
        lda #32
        ora kr
        sta kr
:       lda #$DF                ; cursor down 0, L 2, cursor up 3, - 6
        jsr krow
        tax
        and #$01
        beq :+
        lda #2
        ora kr
        sta kr
:       txa
        and #$04
        beq :+
        lda #128
        ora kr
        sta kr
:       txa
        and #$08
        beq :+
        lda #1
        ora kr
        sta kr
:       txa
        and #$40
        beq :+
        lda #64
        ora kr
        sta kr
:       lda #$7F                ; space 4
        jsr krow
        and #$10
        beq :+
        lda #16
        ora kr
        sta kr
:       lda #0                  ; the second byte: Z 1, ',' 2, '.' 4, Esc 8
        sta kr2
        lda #$FD                ; Z 4 (not a joystick line)
        jsr krow
        and #$10
        beq :+
        lda #1
        sta kr2
:       lda #$DF                ; ',' 7, '.' 4
        jsr krow
        tax
        and #$80
        beq :+
        lda #2
        ora kr2
        sta kr2
:       txa
        and #$10
        beq :+
        lda #4
        ora kr2
        sta kr2
:       lda #$BF                ; Esc 4
        jsr krow
        and #$10
        beq :+
        lda #8
        ora kr2
        sta kr2
:       lda #$FE                ; F1 4, as 16 here (not a joystick line)
        jsr krow
        and #$10
        ora kr2
        sta kr2
        lda kprev2
        eor #$FF
        and kr2
        tax
        and #$0F
        ora hits2
        sta hits2
        txa
        and #$10
        beq :+
        jsr _mus_toggle
:       lda kr2
        sta kprev2
        lda #$FE                ; return 1
        jsr krow
        and #$02
        beq :+
        lda #16
        ora kr
        sta kr
:       lda #$FF
        sta TED_KEYS
        sta KEY_ROW
        lda kr
        ora _dbg_keys
        sta kr
        sta _keys
        lda kprev
        eor #$FF
        and kr
        sta knew                ; pressed since the last picture
        ; Everything has to work with a joystick of one button, as in
        ; Stardew Pond: fire on its own counts when it is let go; held, a
        ; direction makes it a command instead (hits2: up 16, down 32,
        ; left 64, right 128), and then it does not count as fire.
        lda kr
        and #16
        beq @fup
        lda fstate
        bne :+
        lda #1                  ; fire pressed: on its own so far
        sta fstate
:       lda knew
        and #$0F
        beq @held
        tax
        lda combo,x
        ora hits2
        sta hits2
        lda #2
        sta fstate
@held:  lda knew                ; held: no fire, no directions yet
        and #$E0
        sta knew
        jmp @add
@fup:   lda fstate
        cmp #1
        bne :+
        lda knew                ; let go, on its own: that is fire
        ora #16
        sta knew
:       lda #0
        sta fstate
@add:   lda knew
        ora hits
        sta hits
        lda kr
        sta kprev
        rts

; the command for the directions newly pushed with fire held (one of them)
combo:  .byte 0, 16, 32, 16, 64, 16, 32, 16, 128, 16, 32, 16, 64, 16, 32, 16

krow:   sta KEY_ROW
        sta TED_KEYS
        lda TED_KEYS
        lda TED_KEYS
        eor #$FF
        rts

; ===========================================================================
; A cell of a train (train.s), in either size: a cell is tz_q characters
; (1, or 4 close up). Each character of it the train's band touches is
; made anew from the map's character there (tc_base) and the band, in
; multicolour so that the track left in it stays grey: over the
; half track it comes in by (direction tc_a) from the edge in tc_ae steps
; and from the middle out tc_am; likewise for the half it goes out by (tc_b,
; tc_be, tc_bm). A band is tk_edge[d][e] AND NOT tk_edge[d][N - m] (0-N
; steps each, 0 = none, N = the whole half: 4 steps in the overview, 8
; close up). It is made in cband, the whole cell, only at the bytes a half
; track in its direction can touch at all (ix_tab, made by eng_tzsetup for
; the size): a few of the 32.
; Its character comes from the free list (fl_n of them in fl); the draw
; list (dl_..., at dl_n) notes where on screen it is to be (offset tc_o +
; 0, 1, 40, 41), what, and which map cell and quarter - it is not shown
; yet: train.s shows a train's characters all at once.
; ===========================================================================

        .export _eng_tcell
        .export _tc_a, _tc_ae, _tc_am, _tc_b, _tc_be, _tc_bm
        .export _tc_o, _tc_col, _tc_x, _tc_y, _tc_base, _tc_lead
        .export _tz_q, _tz_n1, _tz_sh, _tz_edge, _eng_tzsetup, _grey
        .import grey_of
        .importzp fp
        .export _fl, _fl_n, _dl_n, _dl_lim, _tc_nc, _tc_cp, _tc_short
        .export _dl_lo, _dl_hi, _dl_code, _dl_x, _dl_y, _dl_q

        .bss
_tc_a:      .res 1
_tc_ae:     .res 1
_tc_am:     .res 1
_tc_b:      .res 1
_tc_be:     .res 1
_tc_bm:     .res 1
_tc_o:      .res 2
_tc_col:    .res 1
_tc_x:      .res 1
_tc_y:      .res 1
_tc_base:   .res 4
_tc_lead:   .res 1              ; the cell of its front, a route's: the
                                ; track in front of it green (%01)
_tz_q:      .res 1              ; characters a cell: 1 or 4
_tz_n1:     .res 1              ; steps of a half + 1: 5 or 9
_tz_sh:     .res 1              ; table entry size as a shift: 3 or 5
_tz_edge:   .res 2
        .segment "XBSS"         ; (trainschedule.cfg: made before read)
_fl:        .res 256            ; the free list: characters for trains
        .bss
_fl_n:      .res 1
_tc_short:  .res 1              ; a character left out: none to be had
_dl_n:      .res 1
_dl_lim:    .res 1
tq:         .res 1
tqo:        .res 1
tz:         .res 1
tcode:      .res 1
h_e:        .res 1              ; half's
h_m:        .res 1
h_end:      .res 1
ts_d:       .res 1              ; eng_tzsetup's
ts_n:       .res 1
ts_size:    .res 1
ed_lo:      .res 8 * 9          ; tk_edge[d][s] for the size, each d and s,
ed_hi:      .res 8 * 9          ; d's from ed_d[d] on
ed_d:       .res 8
        .segment "XBSS"
ix_tab:     .res 256            ; the bytes of a cell a half track in
        .bss
ix_end:     .res 8              ; direction d may touch: from d * 32 to
ix_q:       .res 8              ; ix_end[d]; its characters, a bit each
cband:      .res 32             ; the band (0 but while a cell is made)
aband:      .res 32             ; the cell of its front: the way in front
ld_n:       .res 1
ld_t:       .res 1
_grey:      .res 160 * 8        ; each of the map's characters, 0-159, as
                                ; it is under a train: multicolour, its
                                ; track grey (map.s grey_of)
        .segment "STKBSS"
_tc_nc:     .res 1              ; gaps between cars in the cell (close up)
_tc_cp:     .res 3              ; where, 0-255 along it as tc_ae counts
cd:         .res 1
ce:         .res 1
ce1:        .res 1
        .code

        .segment "DLIST1"       ; at $EC00, above the map
_dl_lo:     .res 256
_dl_hi:     .res 256
_dl_code:   .res 256
_dl_x:      .res 256
        .segment "DLIST2"       ; at $F800, above the second screen
_dl_y:      .res 256
_dl_q:      .res 256
        .code

qoff:   .byte 0, 1, 40, 41

; eng_tzsetup: for the size now (tz_..., map.s), where each tk_edge[d][s]
; is (ed_...), and which bytes of a cell each direction's whole half
; touches (ix_...)
_eng_tzsetup:
        lda _tz_edge
        sta ptr1
        lda _tz_edge+1
        sta ptr1+1
        lda #1
        ldx _tz_sh
:       asl a
        dex
        bne :-
        sta ts_size
        ldx #0
        ldy #0
@d:     txa
        sta ed_d,y
        lda _tz_n1
        sta ts_n
@s:     lda ptr1
        sta ed_lo,x
        clc
        adc ts_size
        sta ptr1
        lda ptr1+1
        sta ed_hi,x
        adc #0
        sta ptr1+1
        inx
        dec ts_n
        bne @s
        iny
        cpy #8
        bne @d
        ldy #0
@id:    sty ts_d
        lda ed_d,y              ; tk_edge[d][N]
        clc
        adc _tz_n1
        tax
        dex
        lda ed_lo,x
        sta ptr1
        lda ed_hi,x
        sta ptr1+1
        tya
        asl a
        asl a
        asl a
        asl a
        asl a
        tax
        lda #0
        sta ix_q,y
        ldy #0
@ib:    lda (ptr1),y
        beq @in
        tya
        sta ix_tab,x
        inx
        lsr a
        lsr a
        lsr a
        sty ts_n
        tay
        lda qbit,y
        ldy ts_d
        ora ix_q,y
        sta ix_q,y
        ldy ts_n
@in:    iny
        cpy ts_size
        bne @ib
        txa
        ldy ts_d
        sta ix_end,y
        iny
        cpy #8
        bne @id
        ; the font's characters in _grey too (the map's own are made there
        ; as they are made)
        lda #0
        sta ts_d
@g:     lda ts_d
        jsr font_at
        stx fp
        sta fp+1
        lda ts_d
        jsr grey_of
        inc ts_d
        lda ts_d
        cmp #C_FIRST
        bne @g
        rts

qbit:   .byte 1, 2, 4, 8

_eng_tcell:
        lda _tc_lead            ; the cell of its front: what lies in front
        beq :+                  ; of it, in aband
        jsr lead
        ; the band: the half it comes in by, the half it goes out by, less
        ; the gaps
:       ldx _tc_a
        lda _tc_ae
        ldy _tc_am
        jsr half
        ldx _tc_b
        lda _tc_be
        ldy _tc_bm
        jsr half
        jsr cuts
        ldx _tc_a               ; the characters it may touch
        lda ix_q,x
        ldx _tc_b
        ora ix_q,x
        sta tz
        lda #0
        sta tq
@quarter:
        lsr tz
        jcc @next
        lda tq
        asl a
        asl a
        asl a
        sta tqo
        tay
        lda cband,y
        ora cband+1,y
        ora cband+2,y
        ora cband+3,y
        ora cband+4,y
        ora cband+5,y
        ora cband+6,y
        ora cband+7,y
        jeq @next               ; the band misses this character
        ldx _dl_n
        cpx _dl_lim
        jeq @short              ; the list is full
        ldx _fl_n
        jeq @short              ; no characters left
        dex
        stx _fl_n
        lda _fl,x
        sta tcode
        ; the map's character with the band over it (both at their place
        ; less tqo: the band is cband + tqo)
        ldy tq
        lda _tc_base,y          ; src: it in _grey
        ldx #0
        stx src+1
        asl a
        rol src+1
        asl a
        rol src+1
        asl a
        rol src+1
        clc
        adc #<_grey
        tax
        lda src+1
        adc #>_grey
        sta src+1
        txa
        sec
        sbc tqo
        sta src
        bcs :+
        dec src+1
:       lda tcode
        jsr font_at
        sta dst+1
        txa
        sec
        sbc tqo
        sta dst
        bcs :+
        dec dst+1
:       lda _tc_lead
        beq @grey
        ldy tqo
        lda aband,y
        ora aband+1,y
        ora aband+2,y
        ora aband+3,y
        ora aband+4,y
        ora aband+5,y
        ora aband+6,y
        ora aband+7,y
        beq @grey
        ; the track in front of it green (%01), behind grey (%10): from
        ; %10 to %01 is EOR %11
        lda #8
        sta ld_n
@lead:  ldx aband,y
        lda _mc_of,x
        and (src),y
        sta ld_t
        lsr a
        ora ld_t
        eor (src),y
        ldx cband,y
        ora _mc_of,x
        sta (dst),y
        iny
        dec ld_n
        bne @lead
        jmp @noted
@grey:  ldy tqo                 ; multicolour: the track grey (%10), the
        .repeat 8               ; band over it in the cell's colour (%11)
        ldx cband,y
        lda (src),y
        ora _mc_of,x
        sta (dst),y
        iny
        .endrepeat
        ; noted: where on screen (train.s puts it there, with the others)
@noted: ldy tq
        lda qoff,y
        clc
        adc _tc_o
        ldx _dl_n
        sta _dl_lo,x
        lda _tc_o+1
        adc #0
        sta _dl_hi,x
        lda tcode
        sta _dl_code,x
        lda _tc_x
        sta _dl_x,x
        lda _tc_y
        sta _dl_y,x
        lda tq
        sta _dl_q,x
        inc _dl_n
        jmp @next
@short: lda #1                  ; (the train is to be drawn again)
        sta _tc_short
@next:  inc tq
        lda tq
        cmp _tz_q
        jne @quarter
        ; cband all 0 again
        ldx _tc_a
        jsr clear
        ldx _tc_b
; clear: cband 0 where a half track in direction X may be
clear:  lda ix_end,x
        sta h_end
        txa
        asl a
        asl a
        asl a
        asl a
        asl a
        tax
        lda #0
@l:     ldy ix_tab,x
        sta cband,y
        inx
        cpx h_end
        bne @l
        rts

; lead: into aband, the way from the train's front to the end of the cell:
; the half it goes out by, from the middle as far as the train is not
; (tc_bm), or all of it and the half it comes in by from the edge as far as
; the train is not (tc_ae). cband 0 again.
lead:   ldx _tz_n1
        dex
        stx ld_n                ; N
        lda _tc_bm
        beq @both
        lda ld_n
        sec
        sbc _tc_bm
        ldx _tc_b
        ldy ld_n
        jsr half
        jmp @move
@both:  ldx _tc_b
        lda ld_n
        ldy ld_n
        jsr half
        lda ld_n
        sec
        sbc _tc_ae
        tay
        ldx _tc_a
        lda ld_n
        jsr half
@move:  ldy #31
:       lda cband,y
        sta aband,y
        lda #0
        sta cband,y
        dey
        bpl :-
        rts

; half: into cband, the band in a half track in direction X, from the edge
; in by A steps and from the middle out by Y: tk_edge[d][A] AND NOT
; tk_edge[d][N - Y]
half:   cmp #0
        beq @rts
        cpy #0
        beq @rts
        sta h_e
        sty h_m
        lda ed_d,x
        clc
        adc h_e
        tay
        lda ed_lo,y
        sta ptr1
        lda ed_hi,y
        sta ptr1+1
        lda ed_d,x              ; + N - m: + tz_n1 - 1 - m
        clc
        adc _tz_n1
        clc
        sbc h_m
        tay
        lda ed_lo,y
        sta ptr2
        lda ed_hi,y
        sta ptr2+1
        lda ix_end,x
        sta h_end
        txa
        asl a
        asl a
        asl a
        asl a
        asl a
        tax
@l:     ldy ix_tab,x
        lda (ptr2),y
        eor #$FF
        and (ptr1),y
        ora cband,y
        sta cband,y
        inx
        cpx h_end
        bne @l
@rts:   rts

; The gaps between the cars (close up): at each place tc_cp (tc_nc of
; them) a step or two of the half it is in are cut out of the band. In
; multicolour pixels pair up: across E-W two steps from an even one, so
; that a whole pixel goes; N-S, one line does; slanting, two again, one
; would hardly show.
cuts:   lda _tc_nc
        jeq cuts9
cuts2:  dec _tc_nc
        ldx _tc_nc
        lda _tc_cp,x
        bmi cuts3
        lsr a                   ; the half it comes in by: step p / 16
        lsr a                   ; from the edge
        lsr a
        lsr a
        sta ce
        lda _tc_a
        jmp cuts4
cuts3:  eor #$FF                ; the half it goes out by: (255 - p) / 16
        lsr a
        lsr a
        lsr a
        lsr a
        sta ce
        lda _tc_b
cuts4:  sta cd
        and #3
        cmp #2
        beq cuts5
        lda ce
        and #$FE
        sta ce
        clc
        adc #2
        bne cuts6
cuts5:  lda ce
        clc
        adc #1
cuts6:  sta ce1
        ldx cd                  ; less edge[e1] and not edge[e]
        lda ed_d,x
        clc
        adc ce1
        tay
        lda ed_lo,y
        sta ptr1
        lda ed_hi,y
        sta ptr1+1
        lda ed_d,x
        clc
        adc ce
        tay
        lda ed_lo,y
        sta ptr2
        lda ed_hi,y
        sta ptr2+1
        lda ix_end,x
        sta h_end
        txa
        asl a
        asl a
        asl a
        asl a
        asl a
        tax
cuts7:  ldy ix_tab,x
        lda (ptr1),y
        eor #$FF
        ora (ptr2),y
        and cband,y
        sta cband,y
        inx
        cpx h_end
        bne cuts7
        lda _tc_nc
        jne cuts2
cuts9:  rts

; A = code -> A = high byte, X = low byte of $C000 + code * 8
font_at:
        ldx #0
        stx tmp2
        asl a
        rol tmp2
        asl a
        rol tmp2
        asl a
        rol tmp2
        tax
        lda tmp2
        clc
        adc #$C0
        rts

        .bss
tmp2:   .res 1
        .code

; ===========================================================================
; eng_text(s): a 0-terminated text of screen codes to screen offset
; txt_o, in colour txt_col; txt_o is left after it
; ===========================================================================
        .export _eng_text, _txt_o, _txt_col
        .bss
_txt_o:     .res 2
_txt_col:   .res 1
txt_bg:     .res 1
        .code
_eng_text:
        sta ptr1
        stx ptr1+1
        lda _txt_o
        sta dst
        lda _txt_o+1
        clc
        adc _scrn+1
        sta dst+1
        lda _txt_o
        sta src
        lda _txt_o+1
        clc
        adc _colr+1
        sta src+1
        lda #0                  ; in the game the board's rows (19 on) on
        ldx _eng_mode           ; the board's blue: extended colour 3
        bne @bg
        ldx _txt_o+1
        cpx #>(BOARD_ROW * 40)
        bcc @bg
        bne :+
        ldx _txt_o
        cpx #<(BOARD_ROW * 40)
        bcc @bg
:       lda #$C0
@bg:    sta txt_bg
        ldy #0
@ch:    lda (ptr1),y
        beq @end
        ora txt_bg
        sta (dst),y
        lda _txt_col
        sta (src),y
        iny
        bne @ch
@end:   tya
        clc
        adc _txt_o
        sta _txt_o
        bcc :+
        inc _txt_o+1
:       rts

; ===========================================================================
; eng_row2: a row of the map close up - r2_n cells from r2_code / r2_attr
; to the screen at offset r2_o, each cell 2 x 2 characters: the quarters of
; its kind (q4, map.s), or spaces for a cell without track; a quarter of
; only a platform's edge in the track's grey (q_deco)
; ===========================================================================
        .export _eng_row2, _r2_o, _r2_code, _r2_attr, _r2_n
        .import _q4, _q_deco

COL_TRACK = $31                 ; (game.inc)

        .bss
_r2_o:      .res 2
_r2_code:   .res 2
_r2_attr:   .res 2
_r2_n:      .res 1
r2_i:       .res 1
r2_k:       .res 1
r2_a:       .res 1
        .code

_eng_row2:
        lda _r2_code
        sta ptr1
        lda _r2_code+1
        sta ptr1+1
        lda _r2_attr
        sta ptr2
        lda _r2_attr+1
        sta ptr2+1
        lda _r2_o               ; dst: the characters, src: the colours
        sta dst
        sta src
        lda _r2_o+1
        clc
        adc _scrn+1
        sta dst+1
        lda _r2_o+1
        clc
        adc _colr+1
        sta src+1
        lda #0
        sta r2_i
@cell:  ldy r2_i
        lda (ptr2),y
        sta r2_a
        lda (ptr1),y
        cmp #64
        bcs @track
        lda #32                 ; no track: four spaces
        ldy #0
        sta (dst),y
        iny
        sta (dst),y
        ldy #40
        sta (dst),y
        iny
        sta (dst),y
        jmp @colour
@track: sec
        sbc #64
        asl a
        asl a                   ; (kind - 64) * 4: at most 95 * 4
        tax
        bcc :+
        lda _q4+256,x
        ldy #0
        jsr r2_put
        lda _q4+257,x
        iny
        jsr r2_put
        lda _q4+258,x
        ldy #40
        jsr r2_put
        lda _q4+259,x
        iny
        jsr r2_put
        jmp @on
:       lda _q4,x
        ldy #0
        jsr r2_put
        lda _q4+1,x
        iny
        jsr r2_put
        lda _q4+2,x
        ldy #40
        jsr r2_put
        lda _q4+3,x
        iny
        jsr r2_put
        jmp @on
@colour:
        lda r2_a
        ldy #0
        sta (src),y
        iny
        sta (src),y
        ldy #40
        sta (src),y
        iny
        sta (src),y
        ; on: two characters to the right
@on:        lda dst
        clc
        adc #2
        sta dst
        sta src
        bcc :+
        inc dst+1
        inc src+1
:       inc r2_i
        lda r2_i
        cmp _r2_n
        jne @cell
        rts

; r2_put: quarter A at dst + Y, its colour at src + Y. Keeps X, Y.
r2_put: sta (dst),y
        stx r2_k
        tax
        lda _q_deco,x
        and #1
        beq :+
        lda r2_a
        and #8
        ora #COL_TRACK
        bne :++
:       lda r2_a
:       sta (src),y
        ldx r2_k
        rts

; ===========================================================================
; The pointer, moved in the interrupt: a place on the map that goes a pixel
; at a time whatever the main loop is busy with, faster the longer the
; stick is held. Its tip is at map pixel ptr_x, ptr_y; vorg_x, vorg_y is
; where the map's pixel 0, 0 would be on screen. It is not drawn: the frame
; round the cell its tip is in (the cursor) shows where it is. When the
; stick is let go, the tip goes to the middle of its cell, so that the next
; cell is as far away in each direction.
;
; The main loop writes and reads the view through vput / vget: a place
; under the cursor is not written but becomes what is under the cursor.
; ===========================================================================
        .export _ptr_x, _ptr_y, _ptr_w, _ptr_h, _vorg_x, _vorg_y
        .export _ptr_on
        .export _vput, _vget, _vp_o, _vp_c, _vp_a, _vg_a
        .import _mc_of

        .segment "ENGZP": zeropage
ip1:        .res 2              ; the interrupt's own pointers
ip2:        .res 2
vp:         .res 2              ; vput's
bp1:        .res 2              ; the bands' (band may come in while
bp2:        .res 2              ; band_resolve works: ip1, ip2 are its)
mcp:        .res 2              ; band_mc's colours

        .bss
_ptr_x:     .res 2
_ptr_y:     .res 2
_ptr_w:     .res 2              ; the map in pixels: x < w, y < h
_ptr_h:     .res 2
_vorg_x:    .res 2
_vorg_y:    .res 2
_ptr_on:    .res 1
_vp_o:      .res 2
_vp_c:      .res 1
_vp_a:      .res 1
_vg_a:      .res 1
p_held:     .res 1
p_step:     .res 1
p_v:        .res 1
        .code

rowlo:  .repeat 25, R
        .byte <(R*40)
        .endrepeat
rowhi:  .repeat 25, R
        .byte >(R*40)
        .endrepeat

; in the interrupt, after the keys: move
ptr_irq:
        lda _ptr_on
        bne :+
        rts
:       lda _keys
        and #$10                ; fire held: a command, the pointer stays
        bne @still
        lda _keys
        and #$0F
        bne @move
@still: lda p_held              ; let go: to the middle of its cell, 16
        beq @rts                ; pixels close up, 8 in the overview
        lda #0
        sta p_held
        ldx #$F0
        ldy #$08
        lda _zoom
        cmp #1
        bne :+
        ldx #$F8
        ldy #$04
:       stx p_step
        sty p_v
        lda _ptr_x
        and p_step
        ora p_v
        sta _ptr_x
        lda _ptr_y
        and p_step
        ora p_v
        sta _ptr_y
@rts:   rts
@move:  ldx p_held              ; a pixel, 2 after 12 pictures, 4 after 30
        cpx #250                ; - the first time from the middle of the
        bcs :+                  ; cell into the next: a tap, a cell on
        inx
        stx p_held
:       lda #1
        cpx #1
        bne :+
        lda #9                  ; (half a cell and a pixel: 9, 5)
        ldy _zoom
        cpy #1
        bne @step
        lda #5
        bne @step
:       cpx #12
        bcc @step
        lda #2
        cpx #30
        bcc @step
        lda #4
@step:  sta p_step
        lda _keys
        and #8                  ; right
        beq @nr
        lda _ptr_x
        clc
        adc p_step
        sta _ptr_x
        bcc :+
        inc _ptr_x+1
:       lda _ptr_x              ; at most w - 1
        cmp _ptr_w
        lda _ptr_x+1
        sbc _ptr_w+1
        bcc @nr
        lda _ptr_w
        sec
        sbc #1
        sta _ptr_x
        lda _ptr_w+1
        sbc #0
        sta _ptr_x+1
@nr:    lda _keys
        and #4                  ; left
        beq @nl
        lda _ptr_x
        sec
        sbc p_step
        sta _ptr_x
        lda _ptr_x+1
        sbc #0
        sta _ptr_x+1
        bcs @nl
        lda #0
        sta _ptr_x
        sta _ptr_x+1
@nl:    lda _keys
        and #2                  ; down
        beq @nd
        lda _ptr_y
        clc
        adc p_step
        sta _ptr_y
        bcc :+
        inc _ptr_y+1
:       lda _ptr_y
        cmp _ptr_h
        lda _ptr_y+1
        sbc _ptr_h+1
        bcc @nd
        lda _ptr_h
        sec
        sbc #1
        sta _ptr_y
        lda _ptr_h+1
        sbc #0
        sta _ptr_y+1
@nd:    lda _keys
        and #1                  ; up
        beq @end
        lda _ptr_y
        sec
        sbc p_step
        sta _ptr_y
        lda _ptr_y+1
        sbc #0
        sta _ptr_y+1
        bcs @end
        lda #0
        sta _ptr_y
        sta _ptr_y+1
@end:   rts

; vput: character vp_c in colour vp_a at screen offset vp_o - or, if the
; cursor covers that place, under it
_vput:  ldx _cu_n
        jne cu_put
vput_:  lda _vp_o
        sta vp
        lda _vp_o+1
        clc
        adc _scrn+1
        sta vp+1
        ldy #0
        lda _vp_c
        sta (vp),y
        lda _vp_o+1
        clc
        adc _colr+1
        sta vp+1
        lda _vp_a
        sta (vp),y
        rts

; eng_below: wait till the beam is below the map (rows 2-17: lines 19-146,
; a row's first line being row * 8 + 3) and well before the vertical blank
; - what is put on screen then is in the next picture whole, and the blank
; sees it (band_resolve). Past line 170: the next picture's.
        .export _eng_below
_eng_below:
:       lda TED_RHI
        lsr a
        bcs :-                  ; (256 or more)
        lda TED_RLO
        cmp #171
        bcs :-
:       lda TED_RLO
        cmp #18 * 8 + 3
        bcc :-
        rts

; vget: what is at screen offset vp_o, the cursor not counted: the
; character in A, its colour in vg_a
_vget:  ldx _cu_n
        jne cu_get
vget_:  lda _vp_o
        sta vp
        lda _vp_o+1
        clc
        adc _colr+1
        sta vp+1
        ldy #0
        lda (vp),y
        sta _vg_a
        lda _vp_o+1
        clc
        adc _scrn+1
        sta vp+1
        lda (vp),y
        ldx #0
        rts

; ---------------------------------------------------------------------------
; The cursor, the corners round the cell pointed at, is a layer over the
; map: whatever is put where it is goes under it and is on
; screen with the corners over it at once - never a moment without them,
; however often a train there is drawn again. Each of its places (cu_n, 1
; or 4) has two characters, C_CURSOR + i and C_CURSOR + 4 + i, taking turns,
; so the one shown is never the one drawn into. Close up, where its corners
; are in a bottom quarter of hires, the character stays hires above them.
; Where it is thin in their lines 5-7 (2 pixels a line at most: nothing,
; a diagonal) they are hires too, and a band (map.s, cu_bands) gives those
; lines the cursor's green - till it does, in a picture or so, they have
; the track's colour. Where it has more (a sign, a platform's edge, a lamp)
; those lines are multicolour, made so by the band: what is there in its
; own colour, the corners in multicolour 1 over it. Elsewhere the whole
; place is multicolour.
; ---------------------------------------------------------------------------
        .export _cu_add, _cu_clear, _cu_forget, _cu_n, _cu_m, _cu_low, cu_lowp

C_CURSOR = 248                  ; (game.inc)

        .bss
_cu_n:      .res 1              ; its places on screen
_cu_m:      .res 2              ; cu_add's: the corners there, 8 bytes
cu_olo:     .res 4              ; where they are
cu_ohi:     .res 4
cu_under:   .res 4              ; what is under them
cu_ucol:    .res 4
cu_mlo:     .res 4
cu_mhi:     .res 4
cu_set:     .res 4              ; 0 or 4: the character shown
cu_i:       .res 1
cu_t:       .res 1
cu_buf:     .res 8
cu_lowp:    .res 4              ; 1: in a bottom quarter, close up
_cu_low:    .res 1              ; cu_add's: the place's cu_lowp
cu_hr:      .res 1              ; cu_glyph's: 1 hires
cu_band:    .res 4              ; its band (cu_bands): 1 green, 2 multicolour
cu_bt:      .res 1              ; (cu_glyph's)
        .code

; vput at one of the cursor's places: under it
cu_put: dex
        jmi vput_
        lda cu_olo,x
        cmp _vp_o
        bne cu_put
        lda cu_ohi,x
        cmp _vp_o+1
        bne cu_put
        lda _vp_c
        cmp cu_under,x
        bne @new
        lda _vp_a
        cmp cu_ucol,x
        bne @new
        rts                     ; as it is already
@new:   lda _vp_c               ; another character or colour: drawn
        sta cu_under,x          ; again, and its band made again
        lda _vp_a
        sta cu_ucol,x
        jsr cu_glyph
        jsr vput_
        jmp cu_bands

cu_get: dex
        jmi vget_
        lda cu_olo,x
        cmp _vp_o
        bne cu_get
        lda cu_ohi,x
        cmp _vp_o+1
        bne cu_get
        lda cu_ucol,x
        sta _vg_a
        lda cu_under,x
        ldx #0
        rts

; cu_add: the cursor's next place at screen offset vp_o, its corners cu_m
_cu_add:
        jsr _vget
        ldx _cu_n
        sta cu_under,x
        lda _cu_low
        sta cu_lowp,x
        lda _vg_a
        sta cu_ucol,x
        lda _vp_o
        sta cu_olo,x
        lda _vp_o+1
        sta cu_ohi,x
        lda _cu_m
        sta cu_mlo,x
        lda _cu_m+1
        sta cu_mhi,x
        inc _cu_n
        jsr cu_glyph            ; now with the corners over it (its band:
        jmp vput_               ; cu_bands, once all are there)

; cu_clear: what is under the cursor on screen again
_cu_clear:
        ldx _cu_n
        beq @done
        dex
        stx _cu_n
        lda cu_olo,x
        sta _vp_o
        lda cu_ohi,x
        sta _vp_o+1
        lda cu_under,x
        sta _vp_c
        lda cu_ucol,x
        sta _vp_a
        jsr _vput
        jmp _cu_clear
@done:  rts

; cu_forget: the screen is drawn afresh, the cursor is not on it
_cu_forget:
        lda #0
        sta _cu_n
        rts

; cu_glyph: place X's other character, what is under it with the corners
; over it: hires close up where hires is under them in a bottom quarter,
; else multicolour (what is under it in its own colour, the corners in
; multicolour 1); that character in vp_c, its colour in vp_a
cu_glyph:
        stx cu_i
        lda cu_set,x
        eor #4
        sta cu_set,x
        lda cu_under,x
        jsr cu_font
        ldx cu_i
        ldy #0
        sty cu_hr
        tya
        sta cu_band,x
        ldy #7
        lda cu_ucol,x
        and #$08
        bne @raw                ; multicolour under it: as it is
        lda cu_lowp,x
        sta cu_hr
        bne @raw                ; hires: as it is too
@cv:    lda (vp),y              ; else made multicolour
        tax
        lda _mc_of,x
        sta cu_buf,y
        dey
        bpl @cv
        bmi @corners
@raw:   lda (vp),y
        sta cu_buf,y
        dey
        bpl @raw
        ldx cu_i                ; hires: thin in lines 5-7? (a line with
        lda cu_hr               ; its two lowest pixels taken away empty)
        beq @corners
        inc cu_band,x           ; (1: thin)
        ldy #5
@thin:  lda cu_buf,y
        beq :+
        sec
        sbc #1
        and cu_buf,y
        sta cu_t
        beq :+
        sec
        sbc #1
        and cu_t
        bne @thick
:       iny
        cpy #8
        bne @thin
        beq @corners
@thick: inc cu_band,x           ; 2: more - lines 5-7 multicolour, its
        ldy #7                  ; band turning them so
:       ldx cu_buf,y
        lda _mc_of,x
        sta cu_buf,y
        dey
        cpy #5
        bcs :-
@corners:
        ldx cu_i
        lda cu_band,x
        sta cu_bt
        lda cu_mlo,x
        sta vp
        lda cu_mhi,x
        sta vp+1
        ldy #7
@px:    lda (vp),y              ; (the corners' pixels in pairs, as wide
        tax                     ; in hires as in multicolour)
        lda _mc_of,x
        sta cu_t
        ldx cu_bt
        dex
        beq @or                 ; hires over thin: green by its band
        eor #$FF                ; multicolour: in multicolour 1
        and cu_buf,y
        sta cu_buf,y
        lda cu_t
        and #$55
@or:    ora cu_buf,y
        sta cu_buf,y
        dey
        bpl @px
        ldx cu_i
        txa
        clc
        adc cu_set,x
        adc #C_CURSOR
        sta _vp_c
        jsr cu_font
        ldy #7
:       lda cu_buf,y
        sta (vp),y
        dey
        bpl :-
        ldx cu_i
        lda cu_ucol,x
        ldy cu_hr
        bne :+
        ora #$08
:       sta _vp_a
        rts

        .export cu_olo, cu_ohi, cu_under, cu_ucol, cu_band

; cu_font: character A in the font at vp
cu_font:
        ldx #0
        stx vp+1
        asl a
        rol vp+1
        asl a
        rol vp+1
        asl a
        rol vp+1
        sta vp
        lda vp+1
        ora #$C0                ; FONT
        sta vp+1
        rts

        .bss
bm_colour:  .res 1

        .rodata
; the title's text (boot.s writes the same): screen codes of the ROM's set
; with lower case
.repeat 26, I
        .charmap $61 + I, $01 + I
        .charmap $41 + I, $41 + I
.endrepeat
CREDIT  = $51                   ; grey
NAME    = $42                   ; red
FOOT    = $61                   ; light grey
_title_credits:
        .word 17 * 40 + 14
        .byte $FF, CREDIT, "by ", $FF, NAME, "q4z1", $FF, CREDIT, " 2026", 0
        .word 18 * 40 + 15
        .byte "(& Claude)", 0
        .word 0
_title_ready:
        .word 20 * 40 + 10
        .byte $FF, FOOT, " press fire to start", 0
        .word 0
; the ticker's text (tk_next), $FF its end; 6.25 characters a second
tk_text:
        .include "ticker.inc"
        .byte $FF

; the locks in the choice of a map (front.s), 2 x 2 characters each: the
; body (64, 65), shut over it (66, 67) or open (68, 69)
lock_chars:
        .byte $7F, $7E, $7C, $7C, $7E, $7E, $7F, $00
        .byte $FE, $7E, $3E, $3E, $7E, $7E, $FE, $00
        .byte $00, $07, $0C, $18, $18, $18, $18, $18
        .byte $00, $E0, $30, $18, $18, $18, $18, $18
        .byte $07, $0C, $18, $18, $18, $00, $00, $00
        .byte $E0, $30, $18, $18, $18, $18, $18, $18

; the ticker's colours (tk_colours): the logo's gold ($69) through yellow,
; yellow-green, light green, green and blue-green to its cyan ($63) and
; the blue below it ($43), and back - two cells each, 32 in all
tk_ramp:
        .byte $69, $69, $67, $67, $6A, $6A, $6F, $6F
        .byte $65, $65, $6C, $6C, $63, $63, $53, $53
        .byte $43, $43, $53, $53, $63, $63, $6C, $6C
        .byte $65, $65, $6F, $6F, $6A, $6A, $67, $67

; ---------------------------------------------------------------------------
; The bands: a set switch's character may have one colour above a line and
; another below it (map.s: close up its top quarters at line 6, in the
; overview at line 3) - the screen's colours have the first. In that
; character row the TED fetches the colours a second time, in the line
; before (line p: 5 or 2), with the second written in for it: vshift
; ($FF06) set so that line p counts as a row's first, the pixel row counter
; going on as it was and the same row of characters fetched again (it moves
; on in line 6). Back to 3 in line p, the colours as they were for the
; next picture. A row's line 0 is raster line 8 * row + 4.
;
; map.s's list (bands_make) has the places by row; the vertical blank
; sets the first row's interrupt (bands_vbl), each row's the next one's
; (band_at). First the places still on screen (band): their character
; there - under the cursor too, not under a train - and
; colour now. Then, once the TED has fetched the row's colours in its line
; -1 (it holds the CPU in lines -1 and 0), vshift and the second colours,
; by line p. Late (a sei of the main loop's), the row is left as it is
; for that picture rather than have the TED fetch at the wrong time.
; ---------------------------------------------------------------------------
        .import bd_act, bd_ng, bd_col, bd_code, bd_b, bd_grow, bd_gp
        .import bd_gfirst, bd_gend, bd_a, bd_olo, bd_ohi, _zoom
        .import bd_t, bd_irq, bd_late, bd_r, bd_vs, cb_next, cb_vact, cb_ng
        .import cu_bands

C_CUR  = 248                    ; the cursor's characters (C_CURSOR)
BD_ROWS = 12                    ; (map.s): a set's rows, then all the rows
BD_GR  = 2 * BD_ROWS + 4        ; and places, the cursor's two pairs too
BD_PL  = 2 * 24 + 8

        .segment "BANDS"        ; (all set before they are read)
bg_i:       .res 1              ; the row now (map.s's index)
bg_k:       .res 1              ; its place in bo
bv_base:    .res 1              ; the screen shown: its colours' page
bn_t:       .res 1              ; the row's line 0
bn_r:       .res 1              ; its line p: vshift back
bn_pre:     .res 1              ; the row band_back made ready, or $FF
bn_nx:      .res 1              ; the row it goes on with, or $FF
bv_scr:     .res 1              ; $FF06 without vshift
bn_e:       .res 1
bu_x:       .res 1
        .bss
bn_cur:     .res 1              ; band_cur's
br_k:       .res 1              ; band_resolve's
br_e:       .res 1
bd_q:       .res BD_PL          ; a place's character on screen (map.s's
bd_w:       .res BD_PL          ; places: both sets, the cursor's) and its
                                ; colour to write
bg_lo:      .res BD_GR          ; a row's colours on screen (map.s's
bg_hi:      .res BD_GR          ; rows), band_resolve's for band
bg_t:       .res BD_GR          ; writing till this line
bg_vs:      .res BD_GR          ; $FF06 for its fetch
bo:         .res 14             ; the rows this picture, top first: the
bg_n:       .res 1              ; set's and the cursor's, merged
bo_a:       .res 1              ; (bands_vbl's)
bo_ai:      .res 1
bo_b:       .res 1
bo_bi:      .res 1

        .segment "BANDS"
        .bss
bf_none:    .res 1
        .export pd_n
pd_n:       .res 1              ; rows whose colours wait to be put back
pd_g:       .res 14
        .code

; bands_vbl: the rows of this picture - the set's (bands_make) and the
; cursor's (cu_bands), top first - and the first one's interrupt, if any
bands_vbl:
        jsr band_undo           ; (from the screen shown till now)
        lda #$FF
        sta bn_pre
        lda cb_next             ; the cursor's rows as cu_bands made them
        sta cb_vact             ; last
        ldy #0
        lda _eng_mode
        bne @end
        ldx bd_act
        lda bd_ng,x
        sta bo_a
        lda #0                  ; set 1: its rows from 12 on
        cpx #0
        beq :+
        lda #BD_ROWS
:       sta bo_ai
        ldx cb_vact
        lda cb_ng,x
        sta bo_b
        txa                     ; the cursor's: 24 + 2 * pair
        asl a
        adc #2 * BD_ROWS
        sta bo_bi
@m:     lda bo_a
        ora bo_b
        beq @end
        lda bo_b
        beq @a
        lda bo_a
        beq @b
        ldx bo_ai
        lda bd_grow,x
        ldx bo_bi
        cmp bd_grow,x
        bcc @a
        beq @a
@b:     lda bo_bi
        sta bo,y
        inc bo_bi
        dec bo_b
        iny
        bne @m
@a:     lda bo_ai
        sta bo,y
        inc bo_ai
        dec bo_a
        iny
        bne @m
@end:   sty bg_n
        tya
        beq @none
        lda #0
        sta bg_k
        lda bo
        sta bg_i
        lda TED_VMBASE
        and #$F8
        sta bv_base
        lda TED_SCROLLY
        and #$F8
        sta bv_scr
        jsr band_at
        bcc @none
        jmp band                ; (its time now already)
@none:  rts

; band_at: the interrupt for row bg_i, in its line -3 (8 * row + 1) - its
; lines worked out before (map.s, bm_lines). C set: its time has come already (or will within a
; line), band now - rows one under the other leave no time for the
; interrupt to come and go. A row too late is left out.
band_at:
        ldx bg_i
        lda TED_RHI             ; in the vertical blank (from 200 on):
        lsr a                   ; the picture's to come
        bcs @set
        lda TED_RLO
        cmp #200
        bcs @set
        cmp bd_late,x
        bcs @gone               ; too late (a second row of bands in the
                                ; same row: after the first, by its line)
        adc #1                  ; (C clear)
        cmp bd_irq,x
        bcc @set                ; more than a line to come
        rts                     ; (C set) band now
@gone:  inc bg_k
        ldx bg_k
        cpx bg_n
        bcs :+
        lda bo,x
        sta bg_i
        bcc band_at
:       lda #BOARD_IRQ
        bne @irq
@set:   lda bd_irq,x
@irq:   sta irq_at
        sta TED_RCMP
        clc
        rts

; band: the interrupt for row bg_i
band:   ldx bg_i
        lda bd_gp,x
        cmp #4
        jcc fast
band_c: lda bg_t,x              ; all of it before the wait, made in the
        sta bn_t                ; blank (band_resolve) - or in the row
        jsr band_ip             ; before's band_back (band_go): a row right
band_go:                        ; under another's band has less than three
        lda bd_r,x              ; lines for its writes
        sta bn_r
        lda #$FF
        sta bn_pre
        ldy bg_vs,x
:       lda TED_RLO             ; the row's colours fetched: never into
        cmp bd_t,x              ; them
        bcc :-
        cmp bd_late,x
        jcs band_next           ; too late: as it is this picture
        sty TED_SCROLLY         ; vshift first, then the colours
        lda bd_gfirst,x
        tax
@b:     lda TED_RLO
        cmp bn_t
        bcs @end
        ldy bd_col,x            ; the second colours in, by line p - 1,
        lda (bp2),y             ; where the screen shows what it did in
        cmp bd_q,x              ; the blank (band_resolve)
        bne @nb
        lda bd_w,x
        sta (bp1),y
@nb:    inx
        cpx bn_e
        bne @b
@end:   jmp band_back

; band_resolve: in the vertical blank: for each place of the set in use,
; the character the screen shows there now and the colour to write - its
; own, under the cursor the colour of its kind (band_mc); bd_q 0 where the
; place's character is not there (a train's over it). The interrupts may
; come in meanwhile: other pointers (ip1, ip2).
band_resolve:
        lda #0
        sta br_k
@g:     ldx br_k
        cpx bg_n
        jcs @rts
        lda bo,x
        tax
        ldy bd_grow,x
        lda rowlo,y
        sta ip1
        sta ip2
        sta mcp
        sta bg_lo,x
        lda rowhi,y
        clc
        adc bv_base
        sta ip1+1
        sta mcp+1
        sta bg_hi,x
        ora #$04
        sta ip2+1
        lda bv_scr              ; the row's $FF06 for its fetch, and till
        ora bd_vs,x             ; where the colours may be written: line
        sta bg_vs,x             ; p - 1 for a fetch in 5 - from then on
        lda bd_late,x           ; the wait for line p (band_back), to put
        ldy bd_gp,x             ; vshift back as soon as the TED lets go,
        cpy #5                  ; before the next row's fetch in p + 2.
        bcs :+                  ; For one in 4 (and 2) till p (the next
        adc #1                  ; row's comes in p + 3). (C clear)
:       sta bg_t,x
        jsr band_cur
        lda bd_gend,x
        sta br_e
        lda bd_gfirst,x
        tax
@p:     ldy bd_col,x
        lda (ip2),y
        sta bd_q,x
        bit bn_cur
        bmi @cur
        cmp bd_code,x
        bne @alt
@b:     lda bd_b,x
@w:     sta bd_w,x
@n:     inx
        cpx br_e
        bne @p
        inc br_k
        jmp @g
@rts:   rts
@cur:   jsr band_curq           ; the cursor's: its green where its
        bcs @b                  ; character is, over hires
        lda #0
        sta bd_q,x
        beq @n
@alt:   jsr band_mc
        bcs :+
        lda #0                  ; (not there)
        sta bd_q,x
        beq @n
:       ora bd_b,x
        jmp @w

; band_ip: row X's colours at bp1, its characters at bp2 (as band_resolve
; found them for the screen shown), its places' end in bn_e. Keeps X.
band_ip:
        lda bg_lo,x
        sta bp1
        sta bp2
        lda bg_hi,x
        sta bp1+1
        ora #$04
        sta bp2+1
        lda bd_gend,x
        sta bn_e
        rts

; fast: a fetch in line 2 - the TED holds the CPU till the start of line 0
; or 1, leaving it less than a line: here by line -1, the row's pointers
; set, then the two writes each where the screen still shows its
; character (under the cursor: left as it is). The wait
; ends at the start of line 0 or 1 (vshift in line 2 itself: the TED
; would fetch then, from what is on the bus).
fast:   lda TED_RLO
        cmp bd_t,x
        jcs band_next
        lda bd_r,x
        sta bn_r
        jsr band_ip
        ldy bg_vs,x
        lda bd_t,x
        sta bn_t
        lda bd_gfirst,x
        tax
:       lda TED_RLO
        cmp bn_t
        bcc :-
        sty TED_SCROLLY
        ldy bd_col,x
        lda (bp2),y
        cmp bd_q,x
        bne :+
        lda bd_w,x
        sta (bp1),y
:       inx
        cpx bn_e
        beq :+
        ldy bd_col,x
        lda (bp2),y
        cmp bd_q,x
        bne :+
        lda bd_w,x
        sta (bp1),y
:       jmp band_back

; band_back: vshift back to 3 in line p, after the TED's fetch there (the
; wait sees line p only when the TED lets go). The screen's colours are put
; back in the vertical blank (band_undo): rows one under the other leave
; each other no time for it. A row right under this one goes on at once,
; without band_at - with a fetch in 5 above it, one in 4 has only the
; lines between the TED's fetches for its writes - and is made ready for
; band before the wait if more than a line is left till p (bn_pre). Not
; later: the TED may hold the CPU from line p into p + 1 (Yape), and
; vshift has to be back before the next row's fetch in p + 2.
band_back:
        ldx pd_n                ; its colours to be put back
        lda bg_i
        sta pd_g,x
        inc pd_n
        lda #$FF
        sta bn_nx
        ldx bg_k                ; the next row right under this one, with
        inx                     ; a fetch in 4 or 5: straight on with it
        cpx bg_n                ; after the wait (bn_nx), made ready now
        bcs :+                  ; if there is time (bn_pre)
        lda bo,x
        tax
        lda bd_gp,x
        cmp #4
        bcc :+
        lda bn_r
        clc
        adc #1
        cmp bd_irq,x
        bcc :+
        stx bn_nx
        lda TED_RLO
        clc
        adc #2
        cmp bn_r
        bcs :+
        stx bn_pre
        lda bg_t,x
        sta bn_t
        jsr band_ip
:       lda TED_SCROLLY
        and #$F8
        ora #$03
        tay
:       lda TED_RLO
        cmp bn_r
        bcc :-
        ldx #3                  ; well past the line's cycle 4, where the
:       dex                     ; TED looks at vshift (the line count
        bne :-                  ; moves on a few cycles before it): held
        sty TED_SCROLLY         ; by its fetch till then, or after it
        ldx bn_nx
        bmi band_next
        inc bg_k
        stx bg_i
        cpx bn_pre
        jeq band_go
        jmp band_c
band_next:
        inc bg_k
        ldx bg_k
        cpx bg_n
        bcs :+
        lda bo,x
        sta bg_i
        jsr band_at
        jcs band
        rts
:       lda #BOARD_IRQ
        sta irq_at
        sta TED_RCMP
        rts

; band_undo: in the vertical blank, the screen's colours back in the rows
; that had a band (pd_g, map.s's indexes in the set they were drawn from)
band_undo:
        ldx pd_n
        beq @rts
        dex
        stx pd_n
        lda pd_g,x
        tax
        jsr band_ip
        jsr band_cur
        lda bp1
        sta mcp
        lda bp1+1
        sta mcp+1
        lda bd_gfirst,x
        tax
@a:     ldy bd_col,x
        lda (bp2),y
        bit bn_cur
        bmi @cu
        cmp bd_code,x
        bne @alta
@wa:    lda bd_a,x
        sta (bp1),y
@na:    inx
        cpx bn_e
        bne @a
        beq band_undo
@rts:   rts
@alta:  jsr band_mc
        bcc @na
        ora bd_a,x
        sta (bp1),y
        jmp @na
@cu:    cmp bd_q,x              ; the cursor's: back where the band put
        bne @na                 ; its green (the same character, the same
        lda bd_q,x              ; colour still) - one drawn again has its
        beq @na                 ; colour already
        lda (bp1),y
        cmp bd_w,x
        beq @wa
        bne @na

; band_cur: bn_cur $80 if row X's places are the cursor's (a fetch in 4),
; else 0 - its places count only where the cursor's characters are: the
; map's own character there again is not the cursor's place (it has gone).
; Keeps X, Y.
band_cur:
        lda bd_gp,x
        cmp #4
        bne :+
        lda #$80
        bne :++
:       lda #0
:       sta bn_cur
        rts

; band_mc: A, a character on screen not place X's: C set if the cursor's,
; over place X's - and A the bits its colour keeps: its multicolour bit (at
; mcp, Y). Keeps X, Y.
band_mc:
        cmp #C_CUR
        bcc @no
        jsr band_under
        cmp bd_code,x
        bne @no
        lda (mcp),y
        and #$08
        sec
        rts
@no:    clc
        rts

; band_curq: A, the character on screen at the cursor's place X: C set if
; it is the cursor's there, with a band (cu_band). Keeps X, Y.
band_curq:
        cmp #C_CUR
        bcc @no
        and #3
        stx bu_x
        tax
        lda cu_band,x
        beq @nox
        lda cu_under,x
        ldx bu_x
        cmp bd_code,x
        bne @no
        sec
        rts
@nox:   ldx bu_x
@no:    clc
        rts

; band_under: what the cursor's character A covers - its places are its
; characters' lowest two bits. Keeps X, Y.
band_under:
        stx bu_x
        and #3
        tax
        lda cu_under,x
        ldx bu_x
        rts
