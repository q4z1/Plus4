; fastload.s - the fast loader in the Plus/4: what both its kinds share
;
; fl_load(): the file named fl_name to fl_addr, from the drive code that
; fastinit.c put into the drive. Without the KERNAL and its ROM, so the
; game's interrupt and the picture go on meanwhile; the drive waits for
; the Plus/4 at every step, so interrupts and the TED's cycles do no harm.
; Returns the bytes loaded (the file's own load address not counted), 0 if
; it failed; when the drive code does not answer at all, fl_kind is 0
; afterwards, and the KERNAL loads from then on.
;
; fl_spin(): no name, only for the drive to start its motor, for a load
; that may come soon (a console's pictures): the motor takes two seconds.
;
; There is a loader for each drive: a 1551's parallel port (fastload51.s,
; drive1551.s) and a 1541's serial bus (fastload41.s, drive1541.s).
; fastinit.c copies the one for the drive it finds to FLRUN, at the end of
; the program's memory (paradroid.cfg); both start with the same two jumps.
; fl_kind: 0 the KERNAL, 1 a 1551, 2 a 1541.

        .export _fl_load, _fl_spin, _fl_kind, _fl_name, _fl_addr
        .export tmo_set, tmo_tick
        .exportzp fl_p, fl_n, fl_b, fl_t, fl_s, fl_u, fl_len, fl_cnt, fl_total
        .import __FLRUN51_START__

        .segment "ENGZP": zeropage
fl_p:   .res 2                  ; where the next block goes
fl_n:   .res 2                  ; the name
fl_b:   .res 1                  ; the 1551's: its strobe as last seen; the
                                ; 1541's: the port with no line pulled
fl_t:   .res 1                  ; a byte as it comes or goes
fl_s:   .res 1                  ; the 1541's: the port with ATN set
fl_u:   .res 1                  ; the 1541's: the port as last read
fl_len: .res 1
fl_cnt: .res 1
fl_total:   .res 2
tmo:    .res 3                  ; a wait's time left

        .bss
_fl_kind:   .res 1
_fl_name:   .res 2
_fl_addr:   .res 2

        .code

_fl_load:
        jmp __FLRUN51_START__
_fl_spin:
        jmp __FLRUN51_START__ + 3

; a wait's time: a few seconds (the drive may have to start its motor)
tmo_set:
        lda #0
        sta tmo
        sta tmo+1
        lda #4
        sta tmo+2
        rts
; carry set when it is up
tmo_tick:
        dec tmo
        bne @on
        dec tmo+1
        bne @on
        dec tmo+2
        beq @up
@on:    clc
        rts
@up:    sec
        rts
