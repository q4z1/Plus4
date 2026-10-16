; fastload.s - the fast loader's half in the Plus/4, at $0600
;
; The boot program (boot.s) puts it here, where the KERNAL keeps nothing
; ($05EC-$07B7) and the game has nothing either; the game calls it there
; (world.c) for every file, and to save. Its other half runs in the drive
; (drive.s, which says how the two talk). The same as trainschedule's, with
; saving added.
;
;   $0600  jmp load
;   $0603  jmp save
;   $0606  "SPFL", so the game can tell it is here (the boot clears it
;          when the drive cannot run the other half)
;   $060A  the name: the address of a 0-terminated string
;   $060C  where to load to, or save from (the file's own load address is
;          neither sent nor changed)
;
; load returns the end of what it loaded in A/X, C clear; or C set and 0
; if the file is not there or the disk failed. save returns 1 in A, C
; clear, once the drive has written the file; or C set and 0. Saving
; writes into the file as it is on the disk, as long as it is - the disk
; comes with one of the right length. Both use no zero page but the CPU's
; port, $01: bit 0 DATA out, bit 1 CLK out (1 = pull the line low), bit 3
; the tape motor (kept off), bit 6 CLK in, bit 7 DATA in (1 = high).
;
; The drive answers an edge of CLK within 14 us; the waits here, counted
; at the TED's fastest clock (1.79 MHz), give it 29 us before DATA is
; read, and 34 us before DATA is changed again. Everything else -
; interrupts, cycles the TED takes, a slower clock - can only make the
; waits longer, and the drive waits for every edge, so that is safe too:
; interrupts may run while it loads, as long as they leave $01 alone.

        .setcpu "6502"

PORT    = $01
FREE    = $08           ; both lines left high, tape motor off
CLKLO   = $0A           ; CLK pulled
DATLO   = $09           ; DATA pulled

        .org $0600

        jmp load
        jmp save
        .byte $53, $50, $46, $4C        ; "SPFL"
fname:  .word 0
faddr:  .word 0

load:   lda faddr
        sta dst+1
        lda faddr+1
        sta dst+2
        lda #0
        jsr request

block:  jsr waitblk
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

save:   lda faddr
        sta @src+1
        lda faddr+1
        sta @src+2
        lda #1
        jsr request

@block: jsr waitblk             ; how many the drive wants for a sector
        beq @done               ; 0: all written
        cmp #$FF
        beq failed
        sta count
:       bit PORT                ; till the drive lets go of DATA
        bpl :-
@src:   lda $FFFF
        jsr put
        inc @src+1
        bne :+
        inc @src+2
:       dec count
        bne @src
        lda #FREE               ; DATA free for the drive's next count
        sta PORT
        jmp @block
@done:  jsr busy
        lda #1
        ldx #0
        clc
        rts

; The request: the name, 16 bytes as in the directory, then A - what to
; do with the file, 0 load, 1 save
request:
        pha
        lda fname
        sta nm+1
        lda fname+1
        sta nm+2
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
@sent:  pla
        jsr put
        lda #FREE
        sta PORT
        rts

; The next block's first byte: till the drive takes CLK (it has read the
; request, or we the last block), then till the block is ready (get waits
; for DATA to settle). Z set if 0.
waitblk:
        jsr busy
:       bit PORT
        bvc :-
        jmp get

; A byte to the drive, lowest bit first: DATA set (low for 1), then CLK
; moved - low for the even bits, high for the odd. Keeps Y.
put:    sta bits
        lda #4
        sta pairs
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
        dec pairs
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
pairs:  .res 1
count:  .res 1
last:   .res 1

        .assert * <= $07B8, error, "the loader is over the KERNAL's $07B8"
