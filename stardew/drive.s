; drive.s - the fast loader's half in the disk drive: a 1541 (any of them),
; 1570 or 1571, at $0400
;
; The boot program (boot.s) writes it into the drive with M-W and starts it
; with M-E; from then on the drive answers only to this - the game loads
; and saves through it. The drive reads and writes the disk through its own
; DOS - a job in the job queue, as any program would - so nothing in here
; depends on the mechanics or on the disk's timing. Only the transfer is
; ours: one bit at a time on the serial bus's DATA line, each to an edge of
; CLK made by the Plus/4. The drive answers an edge within 14 us; the
; Plus/4 looks at DATA no sooner than 30 us after it (fastload.s), so every
; bit has more than twice the time it needs. The Plus/4's interrupts or the
; TED's stolen cycles can only make it later. This is Siz's way (siziolib,
; after the G.I. Joe loader), written anew; the same as trainschedule's,
; with saving added.
;
; The bus as the drive sees it ($1800): bit 0 DATA in, bit 2 CLK in (1 =
; line pulled low), bit 1 DATA out, bit 3 CLK out (1 = pull it low), bit 4
; ATN acknowledge (always 0 here: the Plus/4 leaves ATN alone).
;
; Idle, the drive holds CLK low - so the Plus/4 can tell it is there. A
; request: the Plus/4 pulls DATA, the drive lets go of CLK, the Plus/4 sends
; 16 bytes, the file's name padded with $A0 as in the directory, and what to
; do with it: 0 load, 1 save. The drive holds CLK while it looks for the
; file and reads a sector, and lets go of it when a block is ready.
;
; Loading, a block is a sector's bytes: first a count (1-254: that many
; bytes follow; 0: this is the file's last block, its count follows; 255:
; no such file, or the disk failed), then the bytes - without the file's
; load address. After a block's last bit the drive waits till the Plus/4
; lets go of CLK - it has read the bit - and only then holds CLK again:
; busy, reading the next sector, or waiting for the next request. The
; Plus/4 waits for that before it looks for the next block. So neither side
; ever assumes how fast the other is.
;
; Saving writes into the file as it is on the disk: its sectors, its length
; and its load address stay, only what it holds changes (the disk comes
; with the file, tools/mkd64.py). For each sector the drive sends a count
; the same way (1-254; 255: it failed), lets go of both lines once the
; Plus/4 has it, and takes that many bytes, sent as the name was; then it
; holds CLK while it writes the sector. After the last a 0: all written.

        .setcpu "6502"

SER     = $1800         ; VIA 1 port B: the serial bus
LED     = $1C00         ; VIA 2 port B: bit 3 the drive's light
JOB     = $04           ; the job queue's entry for buffer 4 ...
JTRK    = $0E           ; ... its track
JSEC    = $0F           ; ... and sector
BUF     = $0700         ; buffer 4
ID1     = $12           ; the disk's ID as the DOS expects it
ID2     = $13
HID1    = $16           ; the ID in the last header read
HID2    = $17

; the code's own variables, in buffer 0 (the DOS has no use for it now)
name    = $0300         ; the name asked for, 16 bytes
entry   = $0310         ; where the directory entry is
last    = $0311         ; the sector's last byte to send
from    = $0312         ; and its first
bits    = $0313         ; the byte going over the bus
tries   = $0314         ; reading a sector
op      = $0315         ; 0 load, 1 save
link    = $0316         ; saving: the sector's link, 2 bytes

        .org $0400

start:  sei
        cld

; ---- waiting for a request ----------------------------------------------

idle:   lda #$08                ; CLK held: the drive is here, and busy
        sta SER
        lda LED                 ; light off
        and #$F7
        sta LED
        cli                     ; the DOS may stop the motor meanwhile
        lda #$01
@req:   bit SER                 ; till the Plus/4 pulls DATA
        beq @req
        sei
        lda LED
        ora #$08
        sta LED
        lda #$00                ; CLK free: listening
        sta SER

        ldy #0
@name:  jsr get
        sta name,y
        iny
        cpy #16
        bne @name
        jsr get
        sta op
        lda #$08                ; busy again
        sta SER

; ---- the file in the directory -------------------------------------------

        lda #18
        ldx #1
@dsec:  jsr read
        bcs fail
        ldy #2                  ; the 8 entries at 2, 34, ... 226
@entry: lda BUF,y               ; its type: 0 is an empty entry
        beq @next
        sty entry
        ldx #0
@cmp:   lda BUF+3,y
        cmp name,x
        bne @nomatch
        iny
        inx
        cpx #16
        bne @cmp
        ldy entry               ; found: its first track and sector
        lda #4                  ; (in it the bytes from 4: 2 and 3 are
        sta from                ; the load address)
        lda BUF+1,y
        ldx BUF+2,y
        ldy op
        beq file
        jmp save
@nomatch:
        ldy entry
@next:  tya
        clc
        adc #32
        tay
        bcc @entry
        lda BUF                 ; the directory's next sector
        beq fail
        ldx BUF+1
        jmp @dsec

fail:   lda #$FF              ; 255, and nothing more
        jsr block
        jsr busy
        jmp idle

; ---- the file, a block at a time ----------------------------------------

file:   jsr read
        bcs fail
        lda BUF
        beq @last
        lda #$FF                ; a full sector: bytes up to 255
        jsr upto
        jsr block
        jmp @send
@last:  jsr block               ; the last: a 0 first (A is 0), then the
        lda BUF+1               ; count up to the byte it names
        jsr upto
        jsr put
@send:  ldy from
        lda #2                  ; the sectors after the first: from 2
        sta from
        dey
@byte:  cpy last
        bcs @end
        iny
        lda BUF,y
        jsr put
        jmp @byte
@end:   jsr busy
        lda BUF                 ; on to the next sector
        beq @idle
        ldx BUF+1
        jmp file
@idle:  jmp idle

; The bytes from 'from' up to A: A their count
upto:   sta last
        sec
        sbc from
        clc
        adc #1
        rts

; ---- saving: into the file's sectors ----------------------------------------

save:   jsr read                ; the sector first: where the file goes on
        bcs @fail
        lda BUF                 ; (kept: the buffer is the DOS's while it
        sta link                ; writes)
        lda BUF+1
        sta link+1
        lda link
        beq @last
        lda #$FF                ; a full sector: bytes up to 255
        bne @upto
@last:  lda link+1              ; the last: up to the byte it names
@upto:  jsr upto
        jsr block               ; how many: the Plus/4 sends that many
        lda #$04                ; once it has the count (lets go of CLK),
:       bit SER                 ; both lines are its
        bne :-
        lda #$00
        sta SER
        ldy from
@byte:  jsr get
        sta BUF,y
        cpy last
        beq @write
        iny
        bne @byte
@write: lda #$08                ; busy while it is written
        sta SER
        lda #$90                ; write
        jsr job
        cmp #$01
        bne @fail
        lda #2                  ; the sectors after the first: from 2
        sta from
        ldx link+1
        lda link
        bne save
        jsr block               ; all written: 0, and nothing more
        jsr busy
        jmp idle
@fail:  jmp fail

; ---- reading a sector ----------------------------------------------------

; Track A, sector X into BUF, by the DOS's job queue. C set if it failed:
; five tries, the head moved back to track 1 and out again before the
; last two, the disk's ID taken from the header if the disk was changed.
read:   sta JTRK
        stx JSEC
        lda #5
        sta tries
@try:   lda #$80                ; read
        jsr job
        cmp #$01
        beq @ok
        dec tries
        beq @bad
        lda HID1                ; another disk: its ID
        sta ID1
        lda HID2
        sta ID2
        lda tries
        cmp #2
        bne @try
        lda #$C0                ; bump
        jsr job
        jmp @try
@ok:    clc
        rts
@bad:   sec
        rts

job:    sta JOB
        cli                     ; the DOS does the job in its interrupt
@wait:  lda JOB
        bmi @wait
        sei
        rts

; ---- the bus --------------------------------------------------------------

; A byte from the Plus/4: a bit as CLK goes low, a bit as it goes high.
; DATA low is 1. Keeps Y.
get:    ldx #4
@bit:   lda #$04
@lo:    bit SER
        beq @lo
        lda SER
        lsr
        ror bits
        lda #$04
@hi:    bit SER
        bne @hi
        lda SER
        lsr
        ror bits
        dex
        bne @bit
        lda bits
        rts

; One bit out: C the bit (1: DATA left high). Waits for the edge the
; Plus/4 asks for it with: CLK going high (low = 0) or low (1).
.macro  bitout  low
        .local  wait
        ldx #$00
        bcs :+
        ldx #$02
:       lda #$04
wait:   bit SER
    .if low
        beq wait
    .else
        bne wait
    .endif
        stx SER
.endmacro

; A byte to the Plus/4, lowest bit first, bit 0 as CLK goes high. Keeps Y.
put:    sta bits
        lsr bits
        bitout 0
        lsr bits
        bitout 1
        lsr bits
        bitout 0
        lsr bits
        bitout 1
        lsr bits
        bitout 0
        lsr bits
        bitout 1
        lsr bits
        bitout 0
        lsr bits
        bitout 1
        rts

; After a block: once the Plus/4 has its last bit (it lets go of CLK),
; busy - CLK held, DATA free
busy:   lda #$04
:       bit SER
        bne :-
        lda #$08
        sta SER
        rts

; A block's count, A, while CLK is still held: its bit 0 goes on DATA as
; CLK is let go, which tells the Plus/4 the block is there.
block:  pha
        lsr
        ldx #$00
        bcs :+
        ldx #$02
:       stx SER
        pla
        jmp put

        .assert * <= $0700, error, "the drive code is over buffer 4"
