; fastload.s - the fast loader's half in the Plus/4, at $FA00
;
; (Taken over from trainschedule, its waits since timed instead of
; counted: here only the boot, boot.s, loads through it - the game's
; variables are over it from $F800 on.)
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
; if the file is not there or the disk failed. Saving is not here - no
; room: the best scores' code (scores.s) has its own half of it, which the
; game loads only with them. It uses no zero page but the CPU's port, $01:
; bit 0 DATA out, bit 1 CLK out (1 = pull the line low), bit 3 the tape
; motor (kept off), bit 6 CLK in, bit 7 DATA in (1 = high).
;
; The drive answers an edge of CLK within 14 us; the waits here give it
; 29 us before DATA is read (62 us before a new byte's first bit: it
; fetches the byte first), and 34 us before DATA is changed again. They
; are timed, not counted: the TED's timer 2, running free at 886724 Hz
; (PAL; 894886 NTSC), read at each edge, then till so many ticks have
; gone by (wait) - so an interrupt in the middle of a wait uses it up
; instead of making it longer. That is what lets the boot's music, an
; interrupt 5542 times a second (music.s), play while the files load
; without slowing them down twice over. Only the low byte is looked at:
; after a long interrupt (more than 256 ticks) a wait can come out longer,
; never shorter. The drive waits for every edge, so a late one is always
; safe: interrupts may run while it loads, as long as they leave $01
; alone.

        .setcpu "6502"

PORT    = $01
FREE    = $08           ; both lines left high, tape motor off
CLKLO   = $0A           ; CLK pulled
DATLO   = $09           ; DATA pulled
TIMER   = $FF02         ; timer 2, its low byte (counting down)
T_BIT   = 26            ; ticks: 29 us, an edge to reading DATA
T_BYTE  = 55            ;   62 us, the last edge to a new byte's first bit
T_PUT   = 31            ;   34 us, an edge to changing DATA

        .org $FA00

        jmp load
        .byte $52, $53, $46, $4C        ; "RSFL"
fname:  .word 0
faddr:  .word 0

load:   lda #0                  ; timer 2 running, from 0 (a write to the
        sta TIMER               ; low byte stops it, to the high byte
        sta TIMER+1             ; starts it)
        lda fname
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
@sent:  lda #0                  ; what to do with it: load (saving is
        jsr put                 ; scores.s's)
        lda #FREE
        sta PORT

block:  jsr busy                ; till the drive takes CLK: it has read
:       bit PORT                ; the name, or we the last block; then
        bvc :-                  ; till the next block is ready (get waits
        ldy TIMER               ; from here as from an edge: the drive
        sty edge                ; needs as long as for a new byte till it
        jsr get                 ; looks for the next edge)
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
        lda #T_PUT
        sta limit
        lda #4
        sta count
@bit:   lsr bits
        lda #FREE >> 1
        rol
        sta PORT                ; the bit, CLK still high
        ora #CLKLO
        sta PORT                ; CLK low: the drive reads it
        ldx TIMER
        stx edge
        jsr wait
        lsr bits
        lda #CLKLO >> 1
        rol
        sta PORT                ; the bit, CLK still low
        and #<~$02
        sta PORT                ; CLK high: the drive reads it
        ldx TIMER
        stx edge
        jsr wait
        dec count
        bne @bit
        rts

busy:   bit PORT
        bvs busy
        rts

; wait: till limit ticks have gone by since the edge (edge: the timer then)
wait:   lda edge
        sec
        sbc TIMER
        cmp limit
        bcc wait
        rts

; A byte from the drive, lowest bit first: DATA read, then CLK moved - the
; drive puts the next bit on DATA for it. Z set if 0. Each bit as short as
; it can be (unrolled, the wait after each edge only a look at the timer
; while the bits are shifted): the CPU, not the drive, is what is slow
; here, with the TED's own fetches and the music's interrupt.
.macro  getbit  level, final
        .local  look
        lda PORT                ; the bit, DATA (bit 7)
        ldy #level
        sty PORT                ; the edge: the drive's next bit
        ldy TIMER               ; (its time)
        asl
        ror bits
    .if final
        sty edge                ; (the next byte waits from here)
    .endif
look:   tya                     ; till T_BIT ticks have gone by (after the
        sec                     ; last bit too: the drive must have taken
        sbc TIMER               ; CLK before busy looks at it, after a
        cmp #T_BIT              ; block)
        bcc look
.endmacro

get:    lda edge                ; the drive needs more for a new byte than
        sec                     ; for a bit
        sbc TIMER
        cmp #T_BYTE
        bcc get
        getbit CLKLO, 0
        getbit FREE, 0
        getbit CLKLO, 0
        getbit FREE, 0
        getbit CLKLO, 0
        getbit FREE, 0
        getbit CLKLO, 0
        getbit FREE, 1
        lda bits
        rts

bits:   .res 1
count:  .res 1
last:   .res 1
edge:   .res 1              ; the timer at the last edge
limit:  .res 1              ; ticks to wait from it

        .assert * <= $FC00, error, "the loader is over two pages"
