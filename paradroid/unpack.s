; unpack.s - unpacking what exomizer packed (exodecrunch.s, its "raw"
; files): the decks' maps, and later the title, the droids' pictures and
; the console's, lift's and transfer's code, all kept packed in memory.
;
; unpack(src): the packed bytes at src to unp_dst on. Run at $0200, where
; only the KERNAL's loading kept anything (copied there at the start,
; startup.s). The interrupt goes on meanwhile: its zero page is its own.

        .export _unpack, _unp_dst
        .exportzp zp_bitbuf

        .segment "ENGZP": zeropage
zp_len_lo:   .res 1
zp_len_hi:   .res 1
zp_src_lo:   .res 2
zp_src_hi    = zp_src_lo + 1
zp_bits_hi:  .res 1
zp_ro_state: .res 1
zp_bitbuf:   .res 3             ; then the destination

        .segment "UNPACK"

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

_unp_dst:   .res 2

DECRUNCH_FORWARDS = 1
        .include "exodecrunch.s"
