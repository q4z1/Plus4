; drive1541.s - the fast loader's half in a 1541, at $0300 of its memory
;
; fastinit.c sends it there with the DOS's M-W commands and starts it with
; M-E, once. From then on it has the drive to itself: the DOS's interrupt
; stays off, and the code turns the motor on and off, moves the head and
; reads the sectors itself - the DOS needed 50 ms after each sector,
; decoding it and taking the next job, before it could read another.
;
; It waits for a file's name from the Plus/4 (fastload41.s), finds it in
; the directory and sends it over the serial bus, two bits at a time on
; CLK and DATA, each pair when the Plus/4 changes ATN. The Plus/4 waits
; long enough after each change; the drive only has to answer within that
; time.
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
; $1C00: bits 0-1 the head's stepper (+1 a half track in), 2 the motor, 3
; the LED, 5-6 the bit rate (by the track's zone), 7 SYNC (0: in one).
; $1C01 the byte under the head, ready when the V flag is set (the byte
; ready line is the 6502's SO).
;
; A sector is a header block (after a SYNC: $08, checksum, sector, track,
; the ID, in GCR: five bits a nibble) and a data block (after another
; SYNC: $07, 256 bytes, checksum: 325 bytes of GCR). The data block is
; read into BUF as it is and decoded in place, five bytes to four: the
; sector's bytes are then at D. BUF is where the DOS reads it too: its
; first 69 bytes at the top of the stack's page, which the stack never
; reaches, the rest in the page after it ($0200, the command buffer: the
; DOS's commands are done with).
;
; A byte goes out as four pairs, each nibble's from FT: FT[n] has the
; lines for n's upper pair in bits 1 and 3, with the acknowledge (bit 4),
; for its lower pair in bits 0 and 2 (shifted left to 1 and 3).

        .setcpu "6502"
        .org $0300

VIA     = $1800
VIA1IER = $180E
DISK    = $1C00                 ; head, motor, LED, bit rate, SYNC
GCR     = $1C01
DDRA2   = $1C03
VIA2IER = $1C0E
PCR2    = $1C0C
DOSTRK  = $22                   ; the DOS's: the track the head is on

BUF     = $01BB                 ; 325 bytes of GCR, decoded in place
D       = BUF + 1               ; the sector's bytes ($07 before them)

BUSY    = $08                   ; CLK pulled
ACK     = $10                   ; ATN acknowledge, while ATN is set

        ; zero page (the DOS's, which is not running any more)
cur     = $80                   ; the track the head is on
want    = $81                   ; the track and sector to read
wsec    = $82
buft    = $83                   ; the sector D holds (track 0: none)
bufs    = $84
len     = $85
pos     = $86
skip    = $87                   ; the load address's bytes still to skip
tmp     = $88
acc     = $89
nib     = $8A
nxt     = $8B                   ; the next sector of the file
nxs     = $8C
src     = $8D                   ; decoding: from, to
dst     = $8F
g0      = $91                   ; five bytes of GCR
g1      = $92
g2      = $93
g3      = $94
g4      = $95
o       = $96
t       = $97
cnt     = $98                   ; decoding: groups left
tries   = $99                   ; a read: syncs left to look at
hdr     = $9A                   ; a header, decoded: $08, checksum, sector, track
idl     = $9E                   ; waiting: time left with the motor on
name    = $A1                   ; 16
end     = $B1                   ; sending: the index after the last byte
sx      = $B2                   ; decoding: the index into src

start:  sei
        cld
        lda #$7F                ; no interrupts from either VIA
        sta VIA1IER
        sta VIA2IER
        lda DOSTRK
        sta cur
        lda #$EE                ; read mode, byte ready to the CPU
        sta PCR2
        lda #$00
        sta DDRA2
        sta buft

; wait for a name: CLK released, until ATN is set; then CLK pulled,
; listening. The motor goes off after three seconds of waiting. No name
; (a length of 0) only starts the motor, for a load that may come soon.
idle:   lda #$00
        sta VIA
        sta idl
        sta idl+1
        lda #5
        sta idl+2
@w:     bit VIA
        bmi @atn
        dec idl
        bne @w
        dec idl+1
        bne @w
        dec idl+2
        bne @w
        lda DISK                ; motor and LED off
        and #$F3
        sta DISK
:       bit VIA
        bpl :-
@atn:   lda #BUSY | ACK
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
        lda DISK                ; motor and LED on
        ora #$0C
        sta DISK
        lda len
        beq idle
        ; the directory: from track 18, sector 1
        lda #18
        ldx #1
dirsec: jsr read
        bcs fail
        ldy #2                  ; the first entry's type
entry:  lda D,y
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
        lda D,y
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
        lda D,y
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
        lda D                   ; the next directory sector
        beq fail
        ldx D+1
        jmp dirsec
fail:   lda #255
        jsr block1
        jmp idle

found:  lda #2                  ; the load address not sent
        sta skip
        lda D+1,x               ; the file's first track and sector
        pha
        lda D+2,x
        tax
        pla
file:   jsr read
        bcs fail
        ldx #254
        lda D                   ; the last sector: its own length
        bne :+
        ldx D+1
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
        lda D                   ; the next sector's track and sector
        sta nxt
        lda D+1
        sta nxs
        ldy pos                 ; the length in front of the bytes (over
        dey                     ; the link or the load address): D is
        lda len                 ; not that sector any more
        sta D,y
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
block1: sta D
        ldy #0
        sty buft                ; (D not a sector any more)
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

; a block ready: CLK released (ATN rests released)
ready:  lda #$00
        sta VIA
        rts

; ---------------------------------------------------------------------
; Reading

; read track A, sector X into D; carry set on an error. The sector D
; holds already is not read again (the directory's, for one).
read:   cmp buft
        bne :+
        cpx bufs
        bne :+
        clc
        rts
:       sta want
        stx wsec
        lda #0
        sta buft
        lda want
        jsr seek
        lda #0                  ; up to 255 SYNCs (a few revolutions)
        sta tries
@sync:  dec tries
        bne :+
        sec                     ; none of them: an error
        rts
:       jsr sync
        bcs @sync
        ldy #0                  ; a header? its first five bytes
:       bvc :-
        clv
        lda GCR
        sta g0,y
        iny
        cpy #5
        bne :-
        lda g0
        cmp #$52                ; ($08 in GCR)
        bne @sync
        lda #<g0
        sta src
        lda #>g0
        sta src+1
        lda #<hdr
        sta dst
        lda #>hdr
        sta dst+1
        lda #1
        sta cnt
        jsr decode
        lda hdr+3               ; the head on another track?
        cmp want
        beq :+
        tax
        beq @sync               ; (no track: not read right)
        cmp #36
        bcs @sync
        sta cur
        lda want
        jsr seek
        jmp @sync
:       lda hdr+2
        cmp wsec
        bne @sync
        jsr sync                ; the data block
        bcs @sync
        ldy #0
:       bvc :-
        clv
        lda GCR
        sta BUF,y
        iny
        bne :-
:       bvc :-
        clv
        lda GCR
        sta BUF+256,y
        iny
        cpy #69
        bne :-
        lda BUF
        cmp #$55                ; ($07 in GCR)
        bne @sync
        lda #<BUF               ; decoded in place, in two goes (an index
        sta src                 ; goes up to 255)
        sta dst
        lda #>BUF
        sta src+1
        sta dst+1
        lda #51
        sta cnt
        jsr decode
        lda #<(BUF + 255)
        sta src
        lda #>(BUF + 255)
        sta src+1
        lda #<(BUF + 204)
        sta dst
        lda #>(BUF + 204)
        sta dst+1
        lda #14
        sta cnt
        jsr decode
        lda #0                  ; the checksum
        tay
:       eor D,y
        iny
        bne :-
        cmp D+256
        beq :+
        jmp @sync
:       lda want
        sta buft
        lda wsec
        sta bufs
        clc
        rts

; wait for a SYNC (at most about 25 ms); then the latch cleared, the next
; byte the block's first. Carry set if none came.
sync:   lda #0
        sta t
        lda #12
        sta o
:       bit DISK
        bpl @in
        dec t
        bne :-
        dec o
        bne :-
        sec
        rts
@in:    lda GCR
        clv
        clc
        rts

; cnt groups of five bytes of GCR from src to four each at dst (in place
; too: dst stays behind), with src and dst put into the loads and stores
; (X and Y the indexes into them, under 256)
decode: lda src
        sta l0+1
        sta l1+1
        sta l2+1
        sta l3+1
        sta l4+1
        lda src+1
        sta l0+2
        sta l1+2
        sta l2+2
        sta l3+2
        sta l4+2
        lda dst
        sta s0+1
        sta s1+1
        sta s2+1
        sta s3+1
        lda dst+1
        sta s0+2
        sta s1+2
        sta s2+2
        sta s3+2
        ldx #0
        ldy #0
dloop:
l0:     lda $FFFF,x
        sta g0
        inx
l1:     lda $FFFF,x
        sta g1
        inx
l2:     lda $FFFF,x
        sta g2
        inx
l3:     lda $FFFF,x
        sta g3
        inx
l4:     lda $FFFF,x
        sta g4
        inx
        stx sx
        lda g0                  ; g0 >> 3, (g0 << 2 | g1 >> 6) & 31
        lsr a
        lsr a
        lsr a
        tax
        lda GH,x
        sta o
        lda g1
        asl a
        sta t
        lda g0
        rol a
        asl t
        rol a
        and #31
        tax
        lda GL,x
        ora o
s0:     sta $FFFF,y
        iny
        lda g1                  ; (g1 >> 1) & 31, (g1 << 4 | g2 >> 4) & 31
        lsr a
        and #31
        tax
        lda GH,x
        sta o
        lda g1
        lsr a
        lda g2
        ror a
        lsr a
        lsr a
        lsr a
        tax
        lda GL,x
        ora o
s1:     sta $FFFF,y
        iny
        lda g3                  ; (g2 << 1 | g3 >> 7) & 31, (g3 >> 2) & 31
        asl a
        lda g2
        rol a
        and #31
        tax
        lda GH,x
        sta o
        lda g3
        lsr a
        lsr a
        and #31
        tax
        lda GL,x
        ora o
s2:     sta $FFFF,y
        iny
        lda g4                  ; (g3 << 3 | g4 >> 5) & 31, g4 & 31
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        sta t
        lda g3
        asl a
        asl a
        asl a
        ora t
        and #31
        tax
        lda GH,x
        sta o
        lda g4
        and #31
        tax
        lda GL,x
        ora o
s3:     sta $FFFF,y
        iny
        ldx sx
        dec cnt
        beq :+
        jmp dloop
:       rts

; the head to track A, at the bit rate of its zone
seek:   sta tmp
        ldx #3                  ; the zone: 3 up to 17, 2 up to 24, 1 up
        cmp #18                 ; to 30, 0 beyond
        bcc :+
        dex
        cmp #25
        bcc :+
        dex
        cmp #31
        bcc :+
        dex
:       txa
        asl a
        asl a
        asl a
        asl a
        asl a
        sta t
        lda DISK
        and #$9F
        ora t
        sta DISK
        lda cur
        cmp tmp
        beq @done
@step:  lda cur
        cmp tmp
        beq @settle
        bcc @in
        dec cur                 ; out: two half tracks down
        ldx #$FF
        bne :+
@in:    inc cur
        ldx #1
:       stx t
        jsr half
        jsr half
        jmp @step
@settle:
        lda #15
        jsr msec
@done:  rts
half:   lda DISK                ; a half track: the stepper's phase on by t
        clc
        adc t
        and #3
        sta o
        lda DISK
        and #$FC
        ora o
        sta DISK
        lda #4
        ; (fall through)

; wait A milliseconds
msec:   ldx #199
:       dex
        bne :-
        sec
        sbc #1
        bne msec
        rts

; ---------------------------------------------------------------------
; Talking to the Plus/4

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

; len bytes from D + Y to the Plus/4: each as four pairs, one at each
; change of ATN (set, released, set, released), with the acknowledge to
; match. Between two bytes the drive takes 37 us, between two pairs 10:
; the Plus/4's waits are made for that.
sendblk:
        tya
        clc
        adc len
        sta end
@byte:  lda D,y
        and #$0F
        sta nib
        lda D,y
        lsr a
        lsr a
        lsr a
        lsr a
        tax
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
        cpy end
        bne @byte
        rts

; the lines for a nibble n: its upper pair in bits 1 (DATA) and 3 (CLK)
; with the acknowledge, its lower pair in bits 0 and 2; a 0 pulls its
; line, so the Plus/4 reads the bit itself
FT:
        .repeat 16, n
        .byte ((((n >> 3) & 1) ^ 1) << 1) | ((((n >> 2) & 1) ^ 1) << 3) | (((n >> 1) & 1) ^ 1) | (((n & 1) ^ 1) << 2) | ACK
        .endrepeat

; GCR's five bits to a nibble: GH the upper (shifted), GL the lower
GH:     .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$00,$10,$00,$C0,$40,$50
        .byte $00,$00,$20,$30,$00,$F0,$60,$70,$00,$90,$A0,$B0,$00,$D0,$E0,$00
GL:     .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$08,$00,$01,$00,$0C,$04,$05
        .byte $00,$00,$02,$03,$00,$0F,$06,$07,$00,$09,$0A,$0B,$00,$0D,$0E,$00
