; unpack.inc - the files the disk keeps packed: "flags", "pages" and
; "title" (build.sh: exomizer's "raw", forwards), unpacked by exodecrunch.s
; (as trainschedule's unpack.s). The boot (boot.s) has it for the flags,
; the loading screen after a match (cup.s, LDRUN) for all three.
;
; They are loaded to UNP_AT - where the title goes, the last of them loaded
; - and unpacked from there to where they belong; the title over itself:
; moved up first to end at FLAGS, which leaves its unpacking room
; (build.sh checks: the title's end and exomizer's safety offset under
; FLAGS).
;
; unpack: the packed bytes at A/X (low, high) to unp_dst on; the zero
; page from UNP_ZP, nine bytes - free while the boot and the loading screen
; run, the KERNAL's too - and the table in the stack's page, low (the
; stack only near its top meanwhile; past BASIC's $0100-$010F). The RAM in for both its reading and
; writing.

UNP_AT          = $C000         ; (cup.s TITLE_AT)
UNP_ZP          = $D8           ; nine bytes
decrunch_table  = $0110         ; 156 bytes, up to $01AB (not at $0100:
                                ; exodecrunch.s reads it at -1,x - $FF,x
                                ; would be the zero page's)

zp_len_lo       = UNP_ZP
zp_len_hi       = UNP_ZP + 1
zp_src_lo       = UNP_ZP + 2
zp_src_hi       = zp_src_lo + 1
zp_bits_hi      = UNP_ZP + 4
zp_ro_state     = UNP_ZP + 5
zp_bitbuf       = UNP_ZP + 6    ; then the destination, two bytes
unp_dst         = zp_bitbuf + 1

unpack: sta gcb + 1
        stx gcb + 2
        jmp decrunch

; the next packed byte, keeping X, Y, C and V
get_crunched_byte:
gcb:    lda $FFFF
        inc gcb + 1
        bne :+
        inc gcb + 2
:       rts

DECRUNCH_FORWARDS = 1
        .include "exodecrunch.s"
