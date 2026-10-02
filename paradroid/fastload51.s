; fastload51.s - the fast loader's half in the Plus/4, for a 1551
; (drive1551.s the drive's), run at FLRUN (fastload.s, fastinit.c)
;
; Over the 1551's port: $FEF0 the byte, $FEF2 bit 6 our strobe, bit 7 the
; drive's; a byte at a time, each answered by the other side's strobe.
; First the name, its length and its letters; then the file as blocks,
; each its length (1-254; 0 the end, 255 not found) and its bytes. The
; drive leaves out the file's load address.

        .import _fl_kind, _fl_name, _fl_addr
        .import fl_len, fl_cnt, fl_total, tmo_set, tmo_tick
        .importzp fl_p, fl_n, fl_b

TPA     = $FEF0
TPC     = $FEF2
TDDRA   = $FEF3

        .segment "FL51"

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
        lda #$FF                ; the port ours
        sta TDDRA
        lda TPC
        and #$80
        sta fl_b
        lda fl_len
        jsr t_send
        bcs @gone
        ldy #0
:       cpy fl_len
        beq :+
        lda (fl_n),y
        jsr t_send
        bcs @fail
        iny
        bne :-
:       lda #$00                ; the port the drive's
        sta TDDRA
@block: jsr t_recv              ; the length, once the sector is read
        bcs @fail
        beq @done
        cmp #255
        beq @fail
        sta fl_cnt
        ldy #0
@byte:  lda TPC                 ; a byte: the drive's strobe changed
        eor fl_b
        bpl @byte
        lda fl_b
        eor #$80
        sta fl_b
        lda TPA
        sta (fl_p),y
        lda TPC                 ; taken: ours changed
        eor #$40
        sta TPC
        iny
        cpy fl_cnt
        bne @byte
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
@done:  lda fl_total
        ldx fl_total+1
        rts
@fail:  lda #0
        tax
        rts
@gone:  lda #$00                ; no drive code: the KERNAL from now on
        sta TDDRA
        sta _fl_kind
        tax
        rts

spin:   lda #$FF
        sta TDDRA
        lda TPC
        and #$80
        sta fl_b
        lda #0
        jsr t_send
        lda #$00
        sta TDDRA
        bcc :+
        sta _fl_kind            ; no answer: the KERNAL from now on
:       rts

; a byte A sent: on the port, our strobe changed, then wait for the
; drive's to change; carry set on a time-out
t_send: sta TPA
        lda TPC
        eor #$40
        sta TPC
        jsr tmo_set
:       jsr tmo_tick
        bcs :+
        lda TPC
        and #$80
        cmp fl_b
        beq :-
        sta fl_b
        clc
:       rts

; a byte received into A (flags as it), once the drive's strobe has
; changed; ours changed in answer. Carry set on a time-out.
t_recv: jsr tmo_set
:       jsr tmo_tick
        bcs @out
        lda TPC
        and #$80
        cmp fl_b
        beq :-
        sta fl_b
        lda TPA
        pha
        lda TPC
        eor #$40
        sta TPC
        pla
        clc
@out:   rts
