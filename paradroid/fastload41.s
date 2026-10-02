; fastload41.s - the fast loader's half in the Plus/4, for a 1541 on the
; serial bus (drive1541.s the drive's), run at FLRUN (fastload.s,
; fastinit.c)
;
; The Plus/4 clocks everything with ATN, the drive answers each change of
; it: with two bits on CLK and DATA when it sends (DATA the higher), by
; reading the two the Plus/4 put there when it receives. The Plus/4 waits
; a fixed time after each change before it reads or changes the lines
; again, longer than the drive takes at most - that is all the timing
; there is, and interrupts or the TED's stolen cycles only make the waits
; longer. So the picture and the game's interrupt go on while it loads.
;
; $01: bit 0 DATA, bit 1 CLK, bit 2 ATN out (1 pulls the line low);
; bit 7 DATA, bit 6 CLK in (1 high).
;
; The drive's CLK says what it is doing while ATN rests: high, it waits
; (for a name, or with a block ready); low, it is busy.
;
; A name: CLK high (the drive waiting), ATN set; the drive answers with
; CLK low, listening. Then the bytes, the length and the letters, four
; changes of ATN each, the first a release; ATN released at the end, and
; the drive is busy. A file comes as blocks: CLK high, the block ready;
; its length (1-254; 0 the end, 255 not found) and its bytes, four changes
; each, the first a set; then ATN set and released once more, and the
; drive is busy again (CLK low) before the Plus/4 looks at CLK.

        .import _fl_kind, _fl_name, _fl_addr
        .import fl_len, fl_cnt, fl_total, tmo_set, tmo_tick
        .importzp fl_p, fl_n, fl_b, fl_t, fl_s, fl_u

PORT    = $01
ATN     = $04

        .segment "FL41"

        jmp load
        jmp spin

load:   lda _fl_addr
        sta fl_p
        lda _fl_addr+1
        sta fl_p+1
        lda _fl_name
        sta fl_n
        lda _fl_name+1
        sta fl_n+1
        lda #0
        sta fl_total
        sta fl_total+1
        ldy #0                  ; the name's length
:       lda (fl_n),y
        beq :+
        iny
        bne :-
:       sty fl_len
        jsr hello
        bcs gone
        lda fl_len
        jsr t_send
        ldy #0
:       cpy fl_len
        beq :+
        lda (fl_n),y
        jsr t_send
        iny
        bne :-
:       jsr bye
@block: jsr ready               ; the length, once the sector is read
        bcs @fail
        jsr wait                ; (the drive makes it ready after CLK)
        jsr t_recv
        beq @done
        cmp #255
        beq @err
        sta fl_cnt
        ldy #0
:       jsr t_recv
        sta (fl_p),y
        iny
        cpy fl_cnt
        bne :-
        jsr ack
        clc                     ; fl_p and the total on by the block
        lda fl_p
        adc fl_cnt
        sta fl_p
        bcc :+
        inc fl_p+1
:       clc
        lda fl_total
        adc fl_cnt
        sta fl_total
        bcc @block
        inc fl_total+1
        bne @block
@done:  jsr ack
        lda fl_total
        ldx fl_total+1
        rts
@err:   jsr ack
@fail:  lda #0
        tax
        rts

; no drive code: the KERNAL from now on
gone:   lda fl_b
        sta PORT
        lda #0
        sta _fl_kind
        tax
        rts

spin:   jsr hello
        bcs gone
        lda #0
        jsr t_send
        ; (bye, then nothing more)

; the end of a name: ATN released, and long enough for the drive to be
; busy (CLK low) before anything looks at CLK
bye:    lda fl_b
        sta PORT
        ldx #30
:       dex
        bne :-
        rts

; the drive's attention: CLK high (it waits), then ATN set, and CLK low
; in answer (it listens). Carry set if it does not.
hello:  lda PORT
        and #$F8                ; no line pulled by us
        sta fl_b
        sta PORT
        ora #ATN
        sta fl_s
        jsr ready
        bcs :+
        lda fl_b
        ora #ATN
        sta PORT
        jsr tmo_set
@l:     jsr tmo_tick
        bcs :+
        bit PORT
        bvs @l                  ; CLK still high
        clc
:       rts

; wait for CLK high: the drive waiting. Carry set on a time-out.
ready:  jsr tmo_set
:       jsr tmo_tick
        bcs :+
        bit PORT
        bvc :-
        clc
:       rts

; a block taken: ATN set and released, the drive busy at the first
ack:    lda fl_s
        sta PORT
        jsr wait
        lda fl_b
        sta PORT
        ; (fall through)

; the drive's longest answer to a change of ATN, plus room
wait:   ldx #12
:       dex
        bne :-
        rts

; a byte from the drive into A (flags as it); keeps Y. Four pairs, one
; at each change of ATN, read 29 cycles after the change (the drive
; answers within 13 us, 23 cycles of the TED's double clock at 1.77 MHz;
; slower in the picture); the next change 44 cycles after the last (the
; drive's answer and its next pair's load, shift and mask: 23 us). Each
; pair is taken apart while waiting for the next (before the first, two
; bits of nothing, which go out at the top of the byte).
t_recv: nop                     ; (the drive's 37 us between two bytes)
        nop
        lda fl_s
        sta PORT
        jsr pair
        lda fl_b
        sta PORT
        jsr pair
        lda fl_s
        sta PORT
        jsr pair
        lda fl_b
        sta PORT
        jsr pair
        asl fl_u                ; (the last pair: no change to wait for)
        rol fl_t
        asl fl_u
        rol fl_t
        lda fl_t
        rts
; the last pair taken apart (20 cycles), then the next read (jsr, and
; its read cycle: 29 cycles after the store to the port before the jsr)
pair:   asl fl_u                ; DATA: the higher bit
        rol fl_t
        asl fl_u                ; CLK
        rol fl_t
        lda PORT
        sta fl_u
        rts

; a byte A to the drive; keeps Y. Two bits a change of ATN, the first a
; release, held long enough for the drive to read and take them (about
; 50 us of its own)
t_send: sta fl_t
        lda #0
        jsr spair
        lda #ATN
        jsr spair
        lda #0
        jsr spair
        lda #ATN
spair:  ora fl_b
        asl fl_t                ; DATA: a 0 pulls it low
        bcs :+
        ora #$01
:       asl fl_t                ; CLK
        bcs :+
        ora #$02
:       sta PORT
        ldx #20
:       dex
        bne :-
        rts
