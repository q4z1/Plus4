; fastload.s - the fast loader's half in the Plus/4, at $FA00
;
; The boot program (boot.s) puts it here, under the KERNAL's ROM, where the
; game leaves it alone; the game calls it there (front.s) - ROM switched
; off, as it always is in the game. Its other half runs in the drive
; (drive.s, which says how the two talk).
;
;   $FA00  jmp load
;   $FA03  "RSFL", so the game can tell it is here
;   $FA07  the name: the address of a 0-terminated string
;   $FA09  where to (the file's own load address is not sent)
;
; load returns the end of what it loaded in A/X, C clear; or C set and 0
; if the file is not there or the disk failed. It uses no zero page but
; the CPU's port, $01: bit 0 DATA out, bit 1 CLK out (1 = pull the line
; low), bit 3 the tape motor (kept off), bit 6 CLK in, bit 7 DATA in (1 =
; high).
;
; The drive answers an edge of CLK within 14 us; the waits here, counted
; at the TED's fastest clock (1.79 MHz), give it 29 us before DATA is
; read, and 34 us before DATA is changed again. Everything else -
; interrupts, cycles the TED takes, a slower clock - can only make the
; waits longer, and the drive waits for every edge, so that is safe too:
; interrupts may run while it loads (the boot program's, which keeps the
; title picture in its two modes), as long as they leave $01 alone.

        .setcpu "6502"

PORT    = $01
FREE    = $08           ; both lines left high, tape motor off
CLKLO   = $0A           ; CLK pulled
DATLO   = $09           ; DATA pulled

        .org $FA00

        jmp load
        .byte $52, $53, $46, $4C        ; "RSFL"
fname:  .word 0
faddr:  .word 0

load:   lda fname
        sta nm+1
        lda fname+1
        sta nm+2
        lda faddr
        sta dst+1
        lda faddr+1
        sta dst+2

        lda #DATLO              ; asking
        sta PORT
@listen:
        bit PORT                ; till the drive lets go of CLK
        bvc @listen
        ldy #0
nm:     lda $FFFF,y
        beq @pad
        jsr put
        iny
        cpy #16
        bne nm
        beq @sent
@pad:   lda #$A0
        jsr put
        iny
        cpy #16
        bne @pad
@sent:  lda #FREE
        sta PORT

block:  jsr busy                ; till the drive takes CLK: it has read
:       bit PORT                ; the name, or we the last block; then
        bvc :-                  ; till the next block is ready (get waits
        jsr get                 ; for DATA to settle)
        sta last
        beq @last               ; 0: the last block, its count next
        cmp #$FF
        beq failed
        bne @count
@last:  jsr get
        beq theend
@count: sta count
byte:   jsr get
dst:    sta $FFFF
        inc dst+1
        bne next
        inc dst+2
next:   dec count
        bne byte
        lda last
        bne block

theend: jsr busy                ; the drive back waiting
        lda dst+1               ; where it ended
        ldx dst+2
        clc
        rts
failed: jsr busy
        lda #0
        tax
        sec
        rts

; A byte to the drive, lowest bit first: DATA set (low for 1), then CLK
; moved - low for the even bits, high for the odd. Keeps Y.
put:    sta bits
        lda #4
        sta count
@bit:   lsr bits
        lda #FREE >> 1
        rol
        sta PORT                ; the bit, CLK still high
        ora #CLKLO
        sta PORT                ; CLK low: the drive reads it
        jsr wait
        lsr bits
        lda #CLKLO >> 1
        rol
        sta PORT                ; the bit, CLK still low
        and #<~$02
        sta PORT                ; CLK high: the drive reads it
        jsr wait
        dec count
        bne @bit
        rts

busy:   bit PORT
        bvs busy
        rts

wait:   ldx #10                 ; with jsr and rts: 61 cycles, 34 us
:       dex
        bne :-
        rts

; A byte from the drive, lowest bit first: DATA read, then CLK moved - the
; drive puts the next bit on DATA for it. Z set if 0.
get:    ldy #9                  ; the drive needs a little more for a new
:       dey                     ; byte than for a bit
        bne :-
        ldx #4
@bit:   lda PORT
        ldy #CLKLO
        sty PORT
        asl
        ror bits
        ldy #8                  ; 52 cycles from the edge to the next look
:       dey
        bne :-
        lda PORT
        ldy #FREE
        sty PORT
        asl
        ror bits
        ldy #8                  ; 57 cycles
:       dey
        bne :-
        dex
        bne @bit
        lda bits
        rts

bits:   .res 1
count:  .res 1
last:   .res 1

        .assert * <= $FB00, error, "the loader is over the game's stack"
