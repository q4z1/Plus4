; drive1551.s - the fast loader's half in a 1551, at $0500 of its memory
;
; fastinit.c sends it there with the DOS's M-W commands and starts it with
; M-E, once. It then stays, waiting for a file's name from the Plus/4
; (fastload.s), finds it in the directory and sends it over the 1551's
; parallel port, a whole byte at a time, each one answered. The drive's 6523 at
; $4000: port A the byte, port C bit 7 the Plus/4's strobe ($FEF2 bit 6
; there), bit 3 the drive's ($FEF2 bit 7 there). Each side changes its
; strobe when it has put a byte on the port or taken one from it; the
; other waits for that change, so neither needs to be quick.
;
; The name comes as its length and its letters. A file goes as blocks: a
; byte with the block's length (1-254), then its bytes, the file's load
; address left out; a length of 0 ends the file, 255 means it was not
; found.
;
; Sectors are read with the DOS's job queue into buffer 0 ($0300), with
; the drive's interrupt on (the disk controller lives in it).

        .setcpu "6502"
        .org $0500

PA      = $4000                 ; the byte
PC      = $4002                 ; 7: the Plus/4's strobe, 3: ours
DDRA    = $4003
JOB0    = $02                   ; job code for buffer 0
TRK0    = $08                   ; its track and sector (the DOS: $08 + 2 * buffer)
SEC0    = $09
BUF     = $0300

start:  sei
        lda #$00
        sta DDRA                ; port A from the Plus/4
        lda PC
        and #$80
        sta host                ; its strobe as it is

; wait for a name, with the controller running meanwhile
idle:   cli
        jsr getbyte
        sta len
        ldx #0
:       cpx len
        beq :+
        jsr getbyte
        sta name,x
        inx
        bne :-
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
        jsr sendbyte
        jmp finish

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
        jsr sendbyte
        ldy pos
:       lda BUF,y
        jsr sendbyte
        iny
        dec len
        bne :-
        lda BUF
        beq last
        ldx BUF+1
        jmp file
last:   lda #0
        jsr sendbyte
        jmp finish

; the end: the port the Plus/4's again
finish: lda #$00
        sta DDRA
        jmp idle

; read track A, sector X into BUF; carry set on an error
read:   sta TRK0
        stx SEC0
        lda #$80
        sta JOB0
        cli
:       lda JOB0
        bmi :-
        sei
        cmp #$02                ; 1 = done
        rts

; a byte from the Plus/4: when its strobe changes; then ours changes
getbyte:
        lda #$00
        sta DDRA
:       lda PC
        and #$80
        cmp host
        beq :-
        sta host
        lda PA
        pha
        lda PC
        eor #$08
        sta PC
        pla
        rts

; a byte to the Plus/4: ours changes with it on the port; then wait for
; its strobe to change
sendbyte:
        pha
        lda #$FF
        sta DDRA
        pla
        sta PA
        lda PC
        eor #$08
        sta PC
:       lda PC
        and #$80
        cmp host
        beq :-
        sta host
        rts

host:   .byte 0
len:    .byte 0
pos:    .byte 0
skip:   .byte 0                 ; the load address's bytes still to skip
tmp:    .byte 0
name:   .res 16
