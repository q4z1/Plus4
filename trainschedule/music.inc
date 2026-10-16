; music.inc - the music's player, once a picture from the interrupt: in the
; boot program while it loads (boot.s) and in the game after it (engine.s),
; which goes on with the boot program's song where it is. A song is what
; tools/mkmusic.py makes of data/music.txt: its volume, its own tables of
; the TED's frequency registers, its two voices with patterns in them.
; No zero page: the boot program's is the KERNAL's and exomizer's.
;
; The includer sets MSTATE: where the player keeps its place, 24 bytes -
; per voice (X = 0 or 8) the next event's address, frames left of the note,
; the frame left at which it falls silent, the voice's start, where a
; pattern returns to; then +16 1 while playing, +17 the volume, +18-21 the
; tables' addresses, +22 'S' once set up. And MUS_SFX if voice 2 waits
; while a sound effect has it (the game's: frames left of the effect).
;
; A note sounds till GATE frames before its end, so repeated notes are
; heard as two, or for half its length if it is staccato.

GATE    = 2
MS_ON   = MSTATE + 16
MS_VOL  = MSTATE + 17
MS_LO   = MSTATE + 18
MS_HI   = MSTATE + 20
MS_OK   = MSTATE + 22

; mus_init: the song at A/X from its start, playing
.proc   mus_init
        sta msrc+1
        stx msrc+2
        ldy #9
msrc:   lda $FFFF,y             ; its header: 'M', volume, tables, voices
        sta head,y
        dey
        bpl msrc
        php
        sei
        lda head+1
        sta MS_VOL
        ldx #3
:       lda head+2,x
        sta MS_LO,x
        dex
        bpl :-
        ldx #0
        jsr start
        ldx #8
        jsr start
        lda #$53
        sta MS_OK
        lda #1
        sta MS_ON
        jsr mus_tables
        plp
        rts
start:  txa                     ; a voice: X 0 or 8, from head+6 or head+8
        lsr
        lsr
        tay
        lda head+6,y
        sta MSTATE,x
        sta MSTATE+4,x
        lda head+7,y
        sta MSTATE+1,x
        sta MSTATE+5,x
        lda #1
        sta MSTATE+2,x
        rts
head:   .res 10
.endproc

.proc   mus_tick
        lda MS_ON
        bne :+
        rts
:       ldx #0
        jsr voice
        ldx #8
voice:  dec MSTATE+2,x
        beq read
        jmp gate
read:   lda MSTATE,x            ; the next event
        sta ev+1
        lda MSTATE+1,x
        sta ev+2
        ldy #0
        jsr ev
        cmp #$FD
        bcc note
        beq ret
        cmp #$FF
        beq again
        iny                     ; $FE: a pattern; back to after it later
        jsr ev
        pha
        iny
        jsr ev
        pha
        lda MSTATE,x
        clc
        adc #3
        sta MSTATE+6,x
        lda MSTATE+1,x
        adc #0
        sta MSTATE+7,x
        pla
        sta MSTATE+1,x
        pla
        sta MSTATE,x
        jmp read
ret:    lda MSTATE+6,x          ; $FD: the pattern's end
        sta MSTATE,x
        lda MSTATE+7,x
        sta MSTATE+1,x
        jmp read
again:  lda MSTATE+4,x          ; $FF: from the start again
        sta MSTATE,x
        lda MSTATE+5,x
        sta MSTATE+1,x
        jmp read
note:   sta nt
        iny
        jsr ev                  ; its length, bit 7 staccato
        bmi :+
        and #$7F
        sta MSTATE+2,x
        lda #GATE
        bne :++
:       and #$7F
        sta MSTATE+2,x
        lsr
:       sta MSTATE+3,x
        lda MSTATE,x            ; past it
        clc
        adc #2
        sta MSTATE,x
        bcc :+
        inc MSTATE+1,x
:
.ifdef MUS_SFX
        cpx #0
        beq :+
        lda MUS_SFX             ; voice 2 is a sound effect's for now
        bne done
:
.endif
        ldy nt
        beq off                 ; a rest
lo:     lda $FFFF,y
        sta flo
hi:     lda $FFFF,y
        and #$03                ; (never more than the two bits: the
        sta fhi                 ; others of $FF12 are the bitmap's)
        cpx #0
        bne v2
        lda flo                 ; voice 1: $FF0E, and $FF12's low bits
        sta $FF0E
        lda $FF12
        and #$FC
        ora fhi
        sta $FF12
        lda #$10
        bne on
v2:     lda flo                 ; voice 2: $FF0F, $FF10
        sta $FF0F
        lda $FF10
        and #$FC
        ora fhi
        sta $FF10
        lda #$20
on:     ora $FF11               ; the voice on, a square, the volume
        and #$B0
        ora MS_VOL
        sta $FF11
done:   rts
gate:   lda MSTATE+2,x
        cmp MSTATE+3,x
        bne done
.ifdef MUS_SFX
        cpx #0
        beq off
        lda MUS_SFX
        bne done
.endif
off:    lda #<~$10
        cpx #0
        beq :+
        lda #<~$20
:       and $FF11
        sta $FF11
        rts
ev:     lda $FFFF,y             ; a byte of the event at MSTATE,x
        rts
nt:     .byte 0
flo:    .byte 0
fhi:    .byte 0
.endproc

; mus_tables: the tables of the song in MSTATE into the code (after a
; mus_init, or MSTATE copied from the boot program's)
.proc   mus_tables
        lda MS_LO
        sta mus_tick::lo+1
        lda MS_LO+1
        sta mus_tick::lo+2
        lda MS_HI
        sta mus_tick::hi+1
        lda MS_HI+1
        sta mus_tick::hi+2
        rts
.endproc
