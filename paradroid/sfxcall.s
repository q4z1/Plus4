; sfxcall.s - starting the original's sound effects (sfx.s plays them)
;
; sound(n): effect n (SFX_... in data.h) on its voice: the TED's voice 2
; for those on the original's channel 2 and for noise, else voice 1. A new
; effect on a voice takes over from the one there, as in the original.
;
; sfx_tick(): once a tick, the effects the original starts on its own: the
; ship's hum when voice 2 is free (every 32 ticks, with the deck's own
; periods), a warning while the energy is below 8 (every 32 ticks), and
; transfer mode (every 8 ticks).

        .export _sound, _sfx_tick, ted
        .importzp s_fl, s_fh, s_dl, s_dh, s_cn, s_pe, s_fg, s_0l, s_0h
        .importzp q0, q1, q2, r0, r1, tr0, tr1
        .importzp _snd_len
        .import _sfx_tab
        .import _ticks, _d_energy, _transfer_mode, _player_dead, _deck
        .include "sfx.inc"

BLKC    = $E800                 ; the hum's periods in its free end

        .code

_sound: asl a
        asl a
        asl a
        tay
        ldx #0
        lda _sfx_tab+6,y
        and #$40
        beq :+
        inx
:       php
        sei
        lda _sfx_tab,y
        sta s_0l,x
        sta s_fl,x
        lda _sfx_tab+1,y
        sta s_0h,x
        sta s_fh,x
        lda _sfx_tab+2,y
        sta s_dl,x
        lda _sfx_tab+3,y
        sta s_dh,x
        lda _sfx_tab+4,y
        sta s_cn,x
        lda _sfx_tab+5,y
        sta s_pe,x
        lda _sfx_tab+6,y
        sta s_fg,x
        lda _sfx_tab+7,y
        sta _snd_len,x
        plp
        rts

_sfx_tick:
        lda _player_dead
        bne @done
        lda _ticks
        and #$1F
        cmp #$11
        bne @low
        lda _snd_len+1          ; voice 2 free: the deck's hum
        bne @low
        lda #SFX_HUM
        jsr _sound
        ldy _deck
        php
        sei
        lda BLKC+160,y
        sta s_cn+1
        lda BLKC+176,y
        sta s_pe+1
        lda s_fg+1
        and #$E0
        ora BLKC+256+160,y
        sta s_fg+1
        lda #255                ; (the periods end it)
        sta _snd_len+1
        plp
@low:   lda _d_energy
        cmp #8
        bcs @mode
        lda _ticks
        and #$1F
        bne @mode
        lda #SFX_LOW
        jsr _sound
@mode:  lda _transfer_mode
        beq @done
        lda _ticks
        and #7
        bne @done
        lda #SFX_TMODE
        jsr _sound
@done:  rts

; for sfx.s: the TED's register for voice X's frequency, into tr0/tr1:
; 1024 - 1887446 / f; 0 below 1844 (the TED's lowest)
ted:    lda s_fl,x
        cmp #<1844
        lda s_fh,x
        sbc #>1844
        bcc @low
        lda #$56                ; 1887446 = $1CCC56
        sta q0
        lda #$CC
        sta q1
        lda #$1C
        sta q2
        lda #0
        sta r0
        sta r1
        ldy #24
@bit:   asl q0
        rol q1
        rol q2
        rol r0
        rol r1
        bcs @sub                ; a 17th bit: more than f anyway
        lda r0
        cmp s_fl,x
        lda r1
        sbc s_fh,x
        bcc @no
@sub:   lda r0
        sbc s_fl,x              ; (carry set)
        sta r0
        lda r1
        sbc s_fh,x
        sta r1
        inc q0
@no:    dey
        bne @bit
        sec
        lda #0
        sbc q0
        sta tr0
        lda #4
        sbc q1
        sta tr1
        rts
@low:   lda #0
        sta tr0
        sta tr1
        rts
