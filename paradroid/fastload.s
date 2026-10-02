; fastload.s - the fast loader's half in the Plus/4
;
; fl_load(): the file named fl_name to fl_addr, from the drive code that
; fastinit.c put into a 1551 (drive1551.s). Without the KERNAL and its ROM,
; so the game's interrupt and the picture go on meanwhile; the drive waits
; for the Plus/4 at every step, so interrupts and the TED's cycles do no
; harm. Returns the bytes loaded (the file's own load address not
; counted), 0 if it failed; when the drive code does not answer at all,
; fl_kind is 0 afterwards, and the KERNAL loads from then on.
;
; Over the 1551's port: $FEF0 the byte, $FEF2 bit 6 our strobe, bit 7 the
; drive's; a byte at a time, each answered by the other side's strobe.
; First the name, its length and its letters; then the file as blocks,
; each its length (1-254; 0 the end, 255 not found) and its bytes. The
; drive leaves out the file's load address.

        .export _fl_load, _fl_kind, _fl_name, _fl_addr

TPA     = $FEF0
TPC     = $FEF2
TDDRA   = $FEF3

        .segment "ENGZP": zeropage
fp:     .res 2                  ; where the next block goes
fn:     .res 2                  ; the name
drv:    .res 1                  ; the drive's strobe as last seen

        .bss
_fl_kind:   .res 1              ; 1 with the fast loader, 0 the KERNAL's way
_fl_name:   .res 2
_fl_addr:   .res 2
len:    .res 1
cnt:    .res 1
total:  .res 2
tmo:    .res 3                  ; a wait's time left

        .code

_fl_load:
        lda _fl_addr
        sta fp
        lda _fl_addr+1
        sta fp+1
        lda _fl_name
        sta fn
        lda _fl_name+1
        sta fn+1
        lda #0
        sta total
        sta total+1
        ldy #0                  ; the name's length
:       lda (fn),y
        beq :+
        iny
        bne :-
:       sty len
        lda #$FF                ; the port ours
        sta TDDRA
        lda TPC
        and #$80
        sta drv
        lda len
        jsr t_send
        bcs @gone
        ldy #0
:       cpy len
        beq :+
        lda (fn),y
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
        sta cnt
        ldy #0
@byte:  lda TPC                 ; a byte: the drive's strobe changed
        eor drv
        bpl @byte
        lda drv
        eor #$80
        sta drv
        lda TPA
        sta (fp),y
        lda TPC                 ; taken: ours changed
        eor #$40
        sta TPC
        iny
        cpy cnt
        bne @byte
        clc                     ; fp and total on by the block
        lda fp
        adc cnt
        sta fp
        bcc :+
        inc fp+1
:       clc
        lda total
        adc cnt
        sta total
        bcc @block
        inc total+1
        bne @block
@done:  lda total
        ldx total+1
        rts
@fail:  lda #0
        tax
        rts
@gone:  lda #$00                ; no drive code: the KERNAL from now on
        sta TDDRA
        sta _fl_kind
        tax
        rts

; a wait's time: a few seconds (the drive may have to start its motor)
tmo_set:
        lda #0
        sta tmo
        sta tmo+1
        lda #4
        sta tmo+2
        rts
; carry set when it is up
tmo_tick:
        dec tmo
        bne @on
        dec tmo+1
        bne @on
        dec tmo+2
        beq @up
@on:    clc
        rts
@up:    sec
        rts

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
        cmp drv
        beq :-
        sta drv
        clc
:       rts

; a byte received into A (flags as it), once the drive's strobe has
; changed; ours changed in answer. Carry set on a time-out.
t_recv: jsr tmo_set
:       jsr tmo_tick
        bcs @out
        lda TPC
        and #$80
        cmp drv
        beq :-
        sta drv
        lda TPA
        pha
        lda TPC
        eor #$40
        sta TPC
        pla
        clc
@out:   rts
