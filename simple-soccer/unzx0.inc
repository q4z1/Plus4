; unzx0.inc - unpacking what ZX0 packed (Einar Saukas' format, version 2:
; github.com/einar-saukas/ZX0), written anew for the 6502 after its
; reference decompressor (dzx0.c). The game is packed so (build.sh): it
; unpacks faster than exomizer's, for a few bytes more.
;
; The format, a bit stream (most significant bit first, its bytes among
; the literal bytes and offsets) and three kinds of block:
;   literals      a length (Elias gamma), that many bytes as they are;
;                 then a bit: 1 a new offset follows, 0 the last offset
;   last offset   a length (gamma), that many bytes copied from the offset
;                 used last; then a bit: 1 a new offset, 0 literals
;   new offset    its high part (gamma, its data bits inverted: 256 ends
;                 the stream), a byte - the offset (high * 128 - byte / 2),
;                 its lowest bit the length's first bit - and the length
;                 less 1 (gamma); then a bit as after the last offset
; Elias gamma, interlaced: from 1, while a bit is 0 the value takes
; another bit at its bottom. The offset first used is 1.
;
; The game's blocks are short (15000 of them for its 51 KB: half a
; literal, a byte or two copied), so what each costs counts most: the
; lengths are worked out in A (the high byte aside, mostly 0), the bytes
; copied with Y counting, both pointers moved on once after.
;
; unzx0: from zx_src to zx_dst (the zero page, set by the caller), up to
; the end mark; the RAM in for both. Forwards, so it can unpack over
; itself: the packed bytes ending ZX0's "delta" past where the unpacked
; end. A, X, Y used. The includer gives ZX_ZP: ten bytes.

zx_src  = ZX_ZP                 ; the packed bytes
zx_dst  = ZX_ZP + 2             ; the unpacked
zx_ref  = ZX_ZP + 4             ; a match's first byte
zx_off  = ZX_ZP + 6             ; the offset (back from zx_dst)
zx_hi   = ZX_ZP + 8             ; a length's high byte (0 between blocks:
                                ; a long copy counts it down)
zx_bits = ZX_ZP + 9             ; the bits left of the last byte, a 1 after
                                ; them: 0 when they are gone

; C: the stream's next bit (A kept, X not; Y 0)
.macro  zx_bit
        .local  have
        asl zx_bits
        bne have
        jsr zx_byte
have:
.endmacro

unzx0:  lda #$80                ; (no bits: the first takes a byte)
        sta zx_bits
        lda #1
        sta zx_off
        ldy #0
        sty zx_off + 1
        sty zx_hi

; literals
zx_lit: lda #1                  ; (a length of 1 the most common: no
        zx_bit                  ; call for it)
        bcs :+
        jsr zx_gbit
:       tax
        lda zx_hi
        beq zx_lcopy
zx_llong:                       ; (256 bytes or more: the whole pages
        lda (zx_src),y          ; first)
        sta (zx_dst),y
        iny
        bne zx_llong
        inc zx_src + 1
        inc zx_dst + 1
        dec zx_hi
        bne zx_llong
        txa
        beq zx_ladd
zx_lcopy:
        lda (zx_src),y
        sta (zx_dst),y
        iny
        dex
        bne zx_lcopy
zx_ladd:
        tya
        clc
        adc zx_src
        sta zx_src
        bcc :+
        inc zx_src + 1
        clc
:       tya
        adc zx_dst
        sta zx_dst
        bcc :+
        inc zx_dst + 1
:       ldy #0
        zx_bit
        bcs zx_new
        lda #1                  ; the last offset again
        zx_bit
        bcs zx_match
        jsr zx_gbit
        ; (on into zx_match)

; a match: A (and zx_hi) bytes from zx_off back; then a bit: a new offset
; or literals
zx_match:
        tax
        lda zx_dst
        sec
        sbc zx_off
        sta zx_ref
        lda zx_dst + 1
        sbc zx_off + 1
        sta zx_ref + 1
        lda zx_hi
        beq zx_mcopy
zx_mlong:
        lda (zx_ref),y
        sta (zx_dst),y
        iny
        bne zx_mlong
        inc zx_ref + 1
        inc zx_dst + 1
        dec zx_hi
        bne zx_mlong
        txa
        beq zx_madd
zx_mcopy:
        lda (zx_ref),y
        sta (zx_dst),y
        iny
        dex
        bne zx_mcopy
zx_madd:
        tya
        clc
        adc zx_dst
        sta zx_dst
        bcc :+
        inc zx_dst + 1
:       ldy #0
        zx_bit
        bcs zx_new
        jmp zx_lit

; a new offset: its high part (the data bits inverted; past 255 the end)
zx_new: lda #1
        zx_bit
        bcs zx_nhi
zx_nbit:
        zx_bit
        rol a
        bcs zx_end
        eor #1
        zx_bit
        bcc zx_nbit
zx_nhi: lsr a                   ; high * 128: its bit 0 to bit 7 of the
        sta zx_off + 1          ; low byte
        lda #0
        ror a
        sta zx_off
        lda (zx_src),y          ; the byte: its upper seven bits off that
        tax
        inc zx_src
        bne :+
        inc zx_src + 1
:       lsr a
        eor #$FF                ; (off - b: off + ~b + 1)
        sec
        adc zx_off
        sta zx_off
        lda zx_off + 1
        adc #$FF
        sta zx_off + 1
        txa                     ; its bit 0: the length's first bit
        lsr a
        lda #1                  ; (C kept)
        bcs zx_nlen
zx_nlb: zx_bit
        rol a
        rol zx_hi
        zx_bit
        bcc zx_nlb
zx_nlen:
        clc                     ; (the length less 1)
        adc #1
        bcc :+
        inc zx_hi
:       jmp zx_match
zx_end: rts

; zx_gbit: a length (Elias gamma) on from its first bit, 0, A 1 and zx_hi
; 0 so far: its low byte in A, the high in zx_hi
zx_gbit:
        zx_bit
        rol a
        rol zx_hi
        zx_bit
        bcc zx_gbit
        rts

; zx_byte: (zx_bit's) the next byte's bits, C its first; A kept
zx_byte:
        tax
        lda (zx_src),y
        inc zx_src
        bne :+
        inc zx_src + 1
:       sec
        rol a
        sta zx_bits
        txa
        rts
