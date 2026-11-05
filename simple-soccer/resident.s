; resident.s - what outlasts a match: the way back to the disk
;
; The game's own interrupt and the ROM out, the KERNAL is gone for good
; once a match is on: its zero page, its variables at $0400-$07FF are the
; game's. What brings the title back after a match (and the league's page
; between its matches, cup.s) has to come from the disk - so the boot
; (boot.s) leaves this where the game never writes:
;
;   RES ($0200-$03FF)  the fast loader's Plus/4 half (fastload.s) and,
;                      for any other drive, kstub: the KERNAL woken up
;                      again, as the reset does it, and cup.s loaded
;   K_CODE ($FF40-)    k_go: "LOADING ..." on the screen, then cup.s
;                      loaded, by the fast loader or through kstub, and
;                      started (CUP)
;
; with K_VARS (game.inc) beside it: the drive, the title's choices, what
; cup.s is to do; and the league itself (L_BLOCK). The KERNAL's page 2
; and 3 are free in the game, but not while the boot runs on the KERNAL's
; way: there the game's start (simple-soccer.s) copies RES from where the
; boot keeps it, RES_STORE; and cup.s puts it back after the KERNAL has
; been at it (its reset clears page 2 and 3).
;
; build.sh assembles this as it is (one file: RES's 512 bytes, then
; K_CODE's), and makes build/gen/resident.inc of its labels for the boot
; and the game.

        .setcpu "6502"
        .include "game.inc"

IOINIT  = $FF84
RAMTAS  = $FF87
RESTOR  = $FF8A
SETLFS  = $FFBA
SETNAM  = $FFBD
LOAD    = $FFD5
ROMON   = $FF3E
RAMON   = $FF3F
KLOW    = $0600             ; kstub's own place while the KERNAL wakes up:
                            ; the reset's RAMTAS clears page 2 and 3 (not
                            ; 5 and 6: the boot ran from there too)

        .org RES
        .include "fastload.s"

; kstub: (any drive but the fast loader's) the KERNAL woken up as the
; reset wakes it - IOINIT, RAMTAS, RESTOR: the zero page, its variables,
; its vectors, the drives - but not the screen's editor nor BASIC; then
; cup.s loaded to CUP and started, the ROM out again. Its drive in X. It
; copies itself to KLOW first.
kstub:  stx kdev + 1 - klow + kstub_body
        ldx #klow_end - klow
:       lda kstub_body - 1,x
        sta KLOW - 1,x
        dex
        bne :-
        jmp KLOW
kstub_body:
        .org KLOW
klow:   sta ROMON
        jsr IOINIT
        jsr RAMTAS
        jsr RESTOR
        lda #0                  ; (IOINIT's colours: the screen black;
        sta TED_BG              ; its raster interrupt off, should the
        sta TED_BORDER          ; KERNAL let them in)
        sta TED_IRQEN
kagain: lda #3
        ldx #<n_cup
        ldy #>n_cup
        jsr SETNAM
        lda #1
kdev:   ldx #8
        ldy #0
        jsr SETLFS
        lda #0                  ; (load, not verify)
        ldx #<CUP
        ldy #>CUP
        jsr LOAD
        bcs kagain
        sta RAMON
        jmp CUP
n_cup:  .byte "CUP", 0          ; (the fast loader's too: 0 its end)
klow_end:
        .org kstub_body + (klow_end - klow)
        .assert * <= RES + $200, error, "resident.s: RES over its two pages"
        .res RES + $200 - *

; ---- K_CODE: the way back, the ROM out ------------------------------------

        .org K_CODE

; k_go: from the end of a match (play.s) or the title's league (title.s),
; the interrupt off: the screen "LOADING ...", the sound off, cup.s
; loaded and started
k_go:   sei
        lda #0
        sta TED_IRQEN
        sta $FF11               ; (the sound off)
        sta TED_BG
        sta TED_BORDER
        tax                     ; a blank screen at $0800 (colours) and
        lda #' '                ; $0C00 (codes), the ROM's characters -
:       sta $0C00,x             ; as the KERNAL's: kstub's IOINIT keeps it
        sta $0D00,x
        sta $0E00,x
        sta $0F00,x
        inx
        bne :-
        ldx #LOADING_N - 1
:       lda loading,x
        sta $0C00 + LOAD_AT,x
        lda #$71
        sta $0800 + LOAD_AT,x
        dex
        bpl :-
        lda #$1B                ; text, 25 rows, on
        sta TED_SCROLLY
        lda TED_CTRL2
        and #$40                ; (PAL or NTSC kept)
        ora #$08                ; 40 columns, 128 characters, hires
        sta TED_CTRL2
        lda #$04                ; the characters from the ROM, at $D000
        sta TED_BMBASE
        lda #$D0
        sta TED_CHBASE
        lda #$08
        sta TED_VMBASE
        lda K_FAST
        beq @kernal
@fast:  lda #<(n_cup - klow + kstub_body)
        sta nm + 1
        lda #>(n_cup - klow + kstub_body)
        sta nm + 2
        lda #<CUP
        sta dst + 1
        lda #>CUP
        sta dst + 2
        jsr load
        bcs @fast
        jmp CUP
@kernal:
        ldx K_DEV
        jmp kstub

LOAD_AT     = 16 * 40 + 15      ; where the boot's "LOADING" was
loading:    .byte $0C, $0F, $01, $04, $09, $0E, $07, $2E, $2E, $2E   ; "LOADING..."
LOADING_N   = * - loading
k_end:
        .assert * <= L_BLOCK, error, "resident.s: K_CODE into the league"
