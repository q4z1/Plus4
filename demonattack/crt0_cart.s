; ---------------------------------------------------------------------------
; crt0_cart.s - start-up of the cartridge
;
; At reset the KERNAL looks at each ROM bank for "CBM" at $8007, and where
; the byte before it is 1 it calls $8000 at once - before it has set up
; anything else, with interrupts off and the cartridge's two halves (C1 low
; and C1 high) switched in. Nothing of the machine's own start-up has
; happened: no RAM test, no TED set-up, no BASIC. The game does it all
; itself and never goes back.
; ---------------------------------------------------------------------------

        .export __STARTUP__ : absolute = 1
        .export cart_start
        .import _main, zerobss, copydata, _eng_irq, _eng_nmi
        .import __RAMCODE_LOAD__, __RAMCODE_RUN__, __RAMCODE_SIZE__
        .importzp sp, ptr1, ptr2

CHARGEN     = $0400             ; engine.s has the same
CSTACK_TOP  = $0400             ; cc65's stack grows down from here to $0200
BANKSEL     = $FDD0             ; + low bank + 4 * high bank selects them
PROBE       = $0600             ; where find_bank runs (RAM nothing else uses)

        .segment "STARTUP"
        jmp cart_start          ; $8000: the KERNAL comes here
        .byte 0, 0, 0
        .byte 1                 ; $8006: start at once
        .byte $43, $42, $4D     ; $8007: "CBM"
sig:    .byte $44, $41, $43, $51, $34, $5A, $31 ; $800A: "DACQ4Z1", ours
SIGLEN      = * - sig

cart_start:
        sei
        cld
        ldx #$FF
        txs
        ; Which bank is this? A cartridge is C1 (bank 2) on a real machine
        ; and in VICE, but an emulator may well put an image where the
        ; Plus/4 has its 3-plus-1 ROM (bank 1) - Yape does. Switching banks
        ; pulls the ROM away under the code that does it, so the search
        ; runs from RAM.
        ldx #find_end - find_bank - 1
:       lda find_bank,x
        sta PROBE,x
        dex
        bpl :-
        jsr PROBE               ; X: low and high bank both ours, selected
        ; the ROM's character set, while this code - in the low half,
        ; which stays where it is - can still see the KERNAL's half
        txa
        and #3                  ; our low bank, the KERNAL as high
        tay
        sta BANKSEL,y
        ldy #0
:       lda $D000,y
        sta CHARGEN,y
        lda $D100,y
        sta CHARGEN+256,y
        iny
        bne :-
        sta BANKSEL,x           ; both halves ours again
        ; the parts of RAM the program needs set up
        jsr zerobss
        jsr copydata
        lda #<__RAMCODE_LOAD__
        sta ptr1
        lda #>__RAMCODE_LOAD__
        sta ptr1+1
        lda #<__RAMCODE_RUN__
        sta ptr2
        lda #>__RAMCODE_RUN__
        sta ptr2+1
        ldx #>__RAMCODE_SIZE__
        ldy #0
        inx
@page:  dex
        beq @rest
:       lda (ptr1),y
        sta (ptr2),y
        iny
        bne :-
        inc ptr1+1
        inc ptr2+1
        bne @page
@rest:  ldx #<__RAMCODE_SIZE__
        beq @done
:       lda (ptr1),y
        sta (ptr2),y
        iny
        dex
        bne :-
@done:  lda #<CSTACK_TOP
        sta sp
        lda #>CSTACK_TOP
        sta sp+1
        jmp _main

; find_bank: copied to PROBE and run there. Tries banks 1, 2 and 3 (both
; halves) until $8007 holds "CBM" and our signature; returns with that one
; selected and its BANKSEL offset in X. The signature it compares with is
; copied along with it, so it does not need the ROM it is looking for.
find_bank:
        ldx #5                  ; bank 1 low and high
@bank:  sta BANKSEL,x
        ldy #SIGLEN + 2
@cmp:   lda $8007,y
        cmp PROBE + find_sig - find_bank,y
        bne @next
        dey
        bpl @cmp
        rts                     ; found: X is the bank
@next:  txa
        clc
        adc #5
        tax
        cpx #20
        bne @bank
        ldx #10                 ; not to be: C1, where a cartridge belongs
        sta BANKSEL,x
        rts
find_sig:
        .byte $43, $42, $4D, $44, $41, $43, $51, $34, $5A, $31
find_end:

        .segment "VECTORS"
        .word _eng_nmi, cart_start, _eng_irq
