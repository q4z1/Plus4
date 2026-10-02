; drive1541.s - the fast loader's half in a 1541, at $0400 of its memory
;
; fastinit.c sends it there with the DOS's M-W commands and starts it with
; M-E, once. It then stays, waiting for a file's name from the Plus/4
; (fastload41.s), finds it in the directory and sends it over the serial
; bus, two bits at a time on CLK and DATA, each pair when the Plus/4
; changes ATN. The Plus/4 waits long enough after each change; the drive
; only has to answer within that time, which it does with its interrupt
; off (the DOS's could take milliseconds).
;
; $1800: bit 1 DATA out, bit 3 CLK out (1 pulls the line low), bit 4 the
; ATN acknowledge, bit 0 DATA in, bit 2 CLK in (1: low), bit 7 ATN in
; (1: set). The acknowledge must be the opposite of ATN, or the drive's
; own hardware pulls DATA low: set while ATN is set.
;
; CLK while ATN rests: released, the drive waits (for a name, or with a
; block ready); pulled, it is busy (reading, or listening to a name).
; The protocol, the blocks and the name are fastload41.s's.
;
; Sectors are read with the DOS's job queue into buffer 0 ($0300), with
; the drive's interrupt on (the disk controller lives in it).
;
; A byte goes out as four pairs: its upper nibble's from T (made at the
; start, $0700: T[b] = FT[b / 16]), its lower nibble's from FT. FT[n] has the
; lines for n's upper pair in bits 1 and 3, with the acknowledge (bit 4),
; for its lower pair in bits 0 and 2 (shifted left to 1 and 3). So
; between two changes of ATN the drive has no more than a load, a shift
; and a mask to do, and the Plus/4 need not wait for it.

        .setcpu "6502"
        .org $0400

VIA     = $1800
IER     = $180E
JOB0    = $00                   ; job code for buffer 0
TRK0    = $06                   ; its track and sector
SEC0    = $07
BUF     = $0300

T       = $0700
BUSY    = $08                   ; CLK pulled
ACK     = $10                   ; ATN acknowledge, while ATN is set

start:  sei
        lda #$02                ; no interrupt from ATN (the DOS's handler
        sta IER                 ; only notes it anyway)
        ldx #0                  ; T
:       txa
        lsr a
        lsr a
        lsr a
        lsr a
        tay
        lda FT,y
        sta T,x
        inx
        bne :-

; wait for a name, with the controller running meanwhile: CLK released,
; until ATN is set; then CLK pulled, listening. No name (a length of 0)
; only starts the motor, so that a load soon after need not wait for it:
; the directory is read, with nobody waiting for it.
idle:   lda #$00
        sta VIA
        cli
:       bit VIA
        bpl :-
        sei
        lda #BUSY | ACK
        sta VIA
        jsr getbyte
        sta len
        ldx #0
:       cpx len
        beq :+
        jsr getbyte
        sta name,x
        inx
        bne :-
:       bit VIA                 ; ATN released: the name done, busy
        bmi :-
        lda #BUSY
        sta VIA
        lda len
        bne :+
        lda #18
        ldx #1
        jsr post
        jmp idle
:       ; the directory: from track 18, sector 1
        lda #18
        ldx #1
dirsec: jsr read
        bcs fail
        ldy #2                  ; the first entry's type
entry:  lda BUF,y
        beq next                ; free
        tya
        tax
        lda #0
        sta pos
cmp1:   lda pos
        cmp len
        beq found_end
        tay
        lda name,y
        sta tmp
        txa
        clc
        adc pos
        adc #3                  ; the name is at 3 in the entry (y = type)
        tay
        lda BUF,y
        cmp tmp
        bne nomatch
        inc pos
        lda pos
        cmp #16
        bne cmp1
found_end:
        ; the name matches as far as it goes; the rest must be padding
        lda pos
        cmp #16
        beq found
        txa
        clc
        adc pos
        adc #3
        tay
        lda BUF,y
        cmp #$A0
        beq found
nomatch:
        txa
        tay
next:   tya
        clc
        adc #32
        tay
        bcc entry
        lda BUF                 ; the next directory sector
        beq fail
        ldx BUF+1
        jmp dirsec
fail:   lda #255
        jsr block1
        jmp idle

found:  lda #2                  ; the load address not sent
        sta skip
        lda BUF+1,x             ; the file's first track and sector
        pha
        lda BUF+2,x
        tax
        pla
file:   jsr read
        bcs fail
        ldx #254
        lda BUF                 ; the last sector: its own length
        bne :+
        ldx BUF+1
        dex
:       txa
        sec
        sbc skip
        sta len
        lda skip                ; its first byte sent
        clc
        adc #2
        sta pos
        lda #0
        sta skip
        lda len
        beq last                ; (a file of the load address alone)
        lda BUF                 ; the next sector's track and sector
        sta nxt
        lda BUF+1
        sta nxs
        ldy pos                 ; the length in front of the bytes (over
        dey                     ; the link or the load address): BUF is
        lda len                 ; not that sector any more
        sta BUF,y
        lda #0
        sta buft
        inc len
        jsr ready
        jsr sendblk
        jsr ack
        lda nxt
        beq last
        ldx nxs
        jmp file
last:   lda #0
        jsr block1
        jmp idle

; a block of its length byte alone (0 the end, 255 not found)
block1: sta BUF
        ldy #0
        sty buft                ; (BUF not a sector any more)
        iny
        sty len
        jsr ready
        ldy #0
        jsr sendblk
        ; (fall through)

; the block taken: ATN set and released; busy from the first
ack:    bit VIA
        bpl ack
        lda #BUSY | ACK
        sta VIA
:       bit VIA
        bmi :-
        lda #BUSY
        sta VIA
        rts

; a block ready: CLK released (ATN rests released), interrupt off
ready:  sei
        lda #$00
        sta VIA
        rts

; wait until the controller is done with any job asked of it; what BUF
; holds is then known (buft 0: nothing)
settle: cli
:       ldy JOB0
        bmi :-
        dey                     ; 1 = done
        beq :+
        ldy #0
        sty buft
:       rts

; a read of track A, sector X into BUF asked of the controller, once it is
; done with any before
post:   jsr settle
        sta TRK0
        sta buft
        stx SEC0
        stx bufs
        lda #$80
        sta JOB0
        rts

; read track A, sector X into BUF; carry set on an error. A sector already
; there is not read again: the directory, read when the motor was started.
read:   jsr settle
        cmp buft
        bne :+
        cpx bufs
        beq @have
:       jsr post
        jsr settle
@have:  sei
        lda buft
        beq :+
        clc
        rts
:       sec
        rts

; a byte from the Plus/4: four changes of ATN, the first a release; at
; each, the acknowledge set to match, then the two lines read (inverted:
; 1 = low = a 0 bit). Keeps X.
getbyte:
:       bit VIA
        bmi :-
        lda #$00
        sta VIA
        jsr getpair
:       bit VIA
        bpl :-
        lda #ACK
        sta VIA
        jsr getpair
:       bit VIA
        bmi :-
        lda #$00
        sta VIA
        jsr getpair
:       bit VIA
        bpl :-
        lda #ACK
        sta VIA
        jsr getpair
        lda acc
        eor #$FF
        rts
getpair:
        lda VIA
        lsr a                   ; DATA in
        rol acc
        lsr a
        lsr a                   ; CLK in
        rol acc
        rts

; len bytes from BUF + Y to the Plus/4: each as four pairs, one at each
; change of ATN (set, released, set, released), with the acknowledge to
; match
sendblk:
@byte:  lda BUF,y
        tax
        and #$0F
        sta nib
        lda T,x
        and #$1A
:       bit VIA
        bpl :-
        sta VIA
        lda T,x
        asl a
        and #$0A
:       bit VIA
        bmi :-
        sta VIA
        ldx nib
        lda FT,x
        and #$1A
:       bit VIA
        bpl :-
        sta VIA
        lda FT,x
        asl a
        and #$0A
:       bit VIA
        bmi :-
        sta VIA
        iny
        dec len
        bne @byte
        rts

; the lines for a nibble n: its upper pair in bits 1 (DATA) and 3 (CLK)
; with the acknowledge, its lower pair in bits 0 and 2; a 0 pulls its
; line, so the Plus/4 reads the bit itself
FT:
        .repeat 16, n
        .byte ((((n >> 3) & 1) ^ 1) << 1) | ((((n >> 2) & 1) ^ 1) << 3) | (((n >> 1) & 1) ^ 1) | (((n & 1) ^ 1) << 2) | ACK
        .endrepeat

buft:   .byte 0                 ; the sector BUF holds (track 0: none)
bufs:   .byte 0
len:    .byte 0
pos:    .byte 0
skip:   .byte 0                 ; the load address's bytes still to skip
tmp:    .byte 0
acc:    .byte 0
nib:    .byte 0
nxt:    .byte 0                 ; the next sector of the file
nxs:    .byte 0
name:   .res 16
