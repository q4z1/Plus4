; unpack.s - unpacking what exomizer packed (exodecrunch.s, its "raw"
; files, as in Paradroid): every file on the disk - the toolbar's
; characters, the tile sets, the rooms - is packed, and the tile sets and
; rooms stay packed in memory once they have been loaded.
;
; unpack(src): the packed bytes at src to unp_dst on.

        .export _unpack, _unp_dst

        .segment "ENGZP": zeropage
zp_len_lo:   .res 1
zp_len_hi:   .res 1
zp_src_lo:   .res 2
zp_src_hi    = zp_src_lo + 1
zp_bits_hi:  .res 1
zp_ro_state: .res 1
zp_bitbuf:   .res 3             ; then the destination

        .code

; unpack(src): fastcall, src in A/X
_unpack:
        sta gcb + 1
        stx gcb + 2
        lda _unp_dst
        sta zp_bitbuf + 1
        lda _unp_dst + 1
        sta zp_bitbuf + 2
        jmp decrunch

; the next packed byte, keeping X, Y, C and V
get_crunched_byte:
gcb:    lda $FFFF
        inc gcb + 1
        bne :+
        inc gcb + 2
:       rts

        .bss
_unp_dst:   .res 2

        .code
DECRUNCH_FORWARDS = 1
        .include "exodecrunch.s"
