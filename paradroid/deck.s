; deck.s - the ship, its decks, doors and lifts
;
; In assembly, as all of the game, to make room: everything the game
; keeps is in the program. The decks' colours are move.s's (deck_colours()).

        .export _deck, _ship, _level, _ndoor, _alert, _deck_bg
        .export _pal_deck, _pal_mc
        .export _door_x, _door_y, _door_v, _door_s
        .export _deck_cleared, _ship_cleared, _new_ship, _load_deck
        .export _lift_here

        .import _rnd, _blk_at, _unpack, _unp_dst, pushax
        .import _pre, _deck_pk, _deck_off, _ship_base, _ship_count
        .import _lift_deck, _lift_bx, _lift_by, _blk_flag, _d_x, _d_y
        .importzp ptr1, ptr2

        .include "game.inc"
        .include "data.inc"

MAXDOOR   = 32

        .bss
_deck:      .res 1              ; the deck we are on
_ship:      .res NDECKS * 12    ; each deck's droids: type + 1, 0 none
_level:     .res 1
_ndoor:     .res 1
_alert:     .res 1
_deck_bg:   .res 1              ; the deck's colour, without a flash
_door_x:    .res MAXDOOR        ; for doors(), move.s
_door_y:    .res MAXDOOR
_door_v:    .res MAXDOOR        ; 1 vertical, 0 horizontal
_door_s:    .res MAXDOOR        ; 0 closed .. 4 open
dd:     .res 1
dk:     .res 1
dt:     .res 1
dn:     .res 1
dr:     .res 1
dc:     .res 1                  ; console_here()'s flags

        .rodata
; The C64's colours on the TED: for each, the nearest of the TED's 121, as
; VICE draws both (measured: tests of all colours on each machine). The
; deck's light blue is the nearest of 0-7, as deck characters turn into
; multicolour in the cells figures cover. Some a level or two darker than
; the nearest, so that the white 001 and doors stand out on the decks they
; are the background of (measured: contrast against white about 2.5 now,
; 1.5 before): the light green ($7F, $75 nearest) and the cyan; the green
; with them, as the light green decks' edges are drawn in it; the yellow
; when it is the background (move.s, deck_colours()).
_pal_deck:
        .byte $00, $71, $3B, $53, $4E, $45, $36, $77
        .byte $48, $39, $5B, $31, $51, $5F, $56, $61
; the same for multicolour cells, whose colour can only be 0-7: the
; nearest of those
_pal_mc:
        .byte $00, $71, $42, $53, $44, $45, $36, $77
        .byte $42, $37, $52, $31, $51, $55, $56, $61

        .code

; deck_cleared(d): 1 if deck d has no droids left
_deck_cleared:
        asl a                   ; d * 12
        asl a
        sta dt
        asl a
        adc dt
        tax
        ldy #12
:       lda _ship,x
        bne @no
        inx
        dey
        bne :-
        lda #1
        ldx #0
        rts
@no:    lda #0
        tax
        rts

; ship_cleared(): 1 if no deck has droids left
_ship_cleared:
        ldx #NDECKS * 12 - 1
:       lda _ship,x
        bne @no
        dex
        cpx #$FF
        bne :-
        lda #1
        ldx #0
        rts
@no:    lda #0
        tax
        rts

; new_ship(): a new ship, as the original fills it: the first six droids
; of a deck are of its class or up to three above, the others lower
_new_ship:
        lda #0
        ldx #NDECKS * 12 - 1
:       sta _ship,x
        dex
        cpx #$FF
        bne :-
        sta dd
@deck:  ldx dd
        lda _ship_base,x        ; the class: the deck's, and the ship's
        clc
        adc _level
        cmp #$14
        bcc :+
        lda #$13
:       sta dt
        lda _ship_count,x
        cmp #13
        bcc :+
        lda #12
:       sta dn
        lda #0
        sta dk
@k:     lda dk
        cmp dn
        bcs @next
        cmp #6
        bcs @low
        jsr _rnd                ; the first six: up to three above
        and #3
        clc
        adc dt
        jmp @put
@low:   jsr _rnd                ; the others below, or none
        and #15
@half:  beq @skip
        sta dr
        lda dt
        clc
        adc #3
        cmp dr                  ; r >= t + 3: halved
        beq :+
        bcs @lowok
:       lda dr
        lsr a
        jmp @half
@lowok: lda dr
@put:   sta dr
        lda dd                  ; ship[d][k] = r + 1
        asl a
        asl a
        sta dc
        asl a
        adc dc
        adc dk
        tax
        lda dr
        clc
        adc #1
        sta _ship,x
@skip:  inc dk
        bne @k
@next:  inc dd
        lda dd
        cmp #NDECKS
        beq :+
        jmp @deck
:       lda #$17 + 1            ; the command cyborg
        sta _ship + 1 * 12 + 11
        rts

; load_deck(d): deck d's blocks into DMAP (all decks unpacked into the
; droid types' slots first, which are made again for the deck after this:
; enter()), and its doors found
_load_deck:
        sta _deck
        lda #<(_pre + 512)
        sta _unp_dst
        lda #>(_pre + 512)
        sta _unp_dst+1
        lda #<_deck_pk
        ldx #>_deck_pk
        jsr _unpack
        lda _deck               ; its run-length bytes
        asl a
        tax
        lda _deck_off,x
        clc
        adc #<(_pre + 512)
        sta ptr1
        lda _deck_off+1,x
        adc #>(_pre + 512)
        sta ptr1+1
        lda #<DMAP
        sta ptr2
        lda #>DMAP
        sta ptr2+1
        ldy #0
@b:     lda (ptr1),y            ; a block, or $80 + block and a count
        inc ptr1
        bne :+
        inc ptr1+1
:       tax
        bmi @run
        asl a
        asl a
        sta (ptr2),y
        jsr @inc
        bne @b
        beq @doors
@run:   and #$3F
        asl a
        asl a
        sta dt
        lda (ptr1),y
        inc ptr1
        bne :+
        inc ptr1+1
:       tax
        beq @b                  ; (a run of none)
@r:     lda dt
        sta (ptr2),y
        jsr @inc
        dex
        bne @r
        lda ptr2+1
        cmp #>(DMAP + 1024)
        bcc @b
@doors: lda #0                  ; the doors
        sta _ndoor
        sta dk                  ; the row
@row:   ldx #0
@col:   txa
        pha
        lda dk                  ; DMAP[64 * row + col]
        lsr a
        lsr a
        clc
        adc #>DMAP
        sta ptr2+1
        lda dk
        ror a                   ; (row & 3) << 6, carry clear from above
        ror a
        ror a
        and #$C0
        sta ptr2
        pla
        tax
        tay
        lda (ptr2),y
        lsr a
        lsr a
        cmp #BLK_VDOOR
        beq @door
        cmp #BLK_HDOOR
        bne @nd
@door:  ldy _ndoor
        cpy #MAXDOOR
        bcs @nd
        sta dt
        txa
        sta _door_x,y
        lda dk
        sta _door_y,y
        lda #0
        sta _door_s,y
        lda dt
        eor #BLK_HDOOR          ; 1 for a vertical one
        lsr a
        sta _door_v,y
        inc _ndoor
@nd:    inx
        cpx #64
        bne @col
        inc dk
        lda dk
        cmp #16
        bne @row
        rts
@inc:   inc ptr2                ; Z clear unless DMAP is full
        bne :+
        inc ptr2+1
        lda ptr2+1
        cmp #>(DMAP + 1024)
:       rts

; lift_here(): the lift stop the player stands on, anywhere on its block
; (as the original's $272F, which compares the window's column and row
; with their lowest two bits off: four characters either way), or 255
_lift_here:
        lda _d_x+1              ; its block
        sta dt
        lda _d_x
        asl a
        rol dt
        asl a
        rol dt
        asl a
        rol dt
        lda _d_y+1
        sta dr
        lda _d_y
        asl a
        rol dr
        asl a
        rol dr
        asl a
        rol dr
        ldx #0
:       lda _lift_deck,x
        cmp _deck
        bne @next
        lda _lift_bx,x
        cmp dt
        bne @next
        lda _lift_by,x
        cmp dr
        bne @next
        txa
        ldx #0
        rts
@next:  inx
        cpx #NLIFTS
        bne :-
        lda #255
        ldx #0
        rts

