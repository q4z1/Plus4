; move.s - the player's driving and the walls, as the original's
;
; Measured in the C64 original (x64sc; its code at $39F9 and $29C1): the
; speed is a signed 8.8 number per axis. The joystick adds 0.8125 a tick
; one way and 0.8086 the other ($D0 and $CF), up to the host's top speed
; (by its drive, $6D97 there, vmax here); let go, it falls by 0.6875 ($B0)
; a tick to nought. The position moves by the whole pixels of it, rounded
; up (the original's rounding: one way a pixel more at the start).
;
; Walls are characters there, not blocks: a character code from $80 on.
; After each move, three points around the player's character, ahead the
; way it drives, are looked at: two characters off beside it, one straight
; ahead (the original's $6B52 and $6B5E). A wall there stops it, and puts it
; at the edge of its character away from the wall. So the player comes up
; close to everything, as there.
;
; The walls of each block are four bits per character row, in the free end
; of the block code tables (BLKC + 192 + block; tools/mkdata.py).

        .export _move_player, _solid_at, droid_look, d_lk, _console_near
        .export _deck_colours, _colour_blocks
        .export _doors, _blk_at, _bump_next, _bump_i, _bump_back, _fig_place
        .import popax, _d_x, _d_y, _d_vx, _d_vy, _d_type, _dr_drive, _d_wait
        .import _blk_flag, _nd, _d_boom, _d_bx, _d_by
        .import _ndoor, _door_x, _door_y, _door_v, _door_s
        .import _blk_set, _bs_x, _bs_y, _bs_v

DMAP    = $0400
BLK_VDOOR = 1                   ; data.h: a door shut, up and down / across
BLK_HDOOR = 2
BLK_VOPEN = 32                  ; .. its four stages of opening
BLK_HOPEN = 36
BLKS    = $E800 + 192           ; [4][256] at block: its row's wall bits

K_UP    = 1
K_DOWN  = 2
K_LEFT  = 4
K_RIGHT = 8
K_FIRE  = 16

        .segment "ENGZP": zeropage
c_p:    .res 2                  ; the block's place in DMAP
c_q:    .res 2                  ; its row's wall bits
tx:     .res 1                  ; a character, x and y
ty:     .res 1
cx:     .res 1                  ; the player's (cy right after cx)
cy:     .res 1
kk:     .res 1
n3:     .res 1
vmax:   .res 1
vl:     .res 2                  ; the speeds' fractions, across, up/down
vh:     .res 2                  ; their whole pixels (d_vx[0], d_vy[0])
pl:     .res 2                  ; the position, low and high bytes
ph:     .res 2
ax:     .res 1
di:     .res 1
nn:     .res 1

        .bss
_bump_i: .res 1                 ; bump_next(): the droid last found
nbx:    .res 13                 ; doors(): the droids by the screen
nby:    .res 13
d_lk:   .res 13                 ; looked ahead, free: no look till the droid
                                ; turns (choose) or enters a new character
                                ; (dmove, both engine.s)

        .code

; the drives' top speeds, as the original's table
vmax_of:
        .byte 0, 5, 6, 0, 7, 0, 0, 0, 7

; the points looked at, in characters from the player's: right, left, down,
; up (three each)
sen_dx: .byte 2, 1, 2,   <-2, <-1, <-2,   1, <-1, 0,   0, 1, <-1
sen_dy: .byte 1, 0, <-1, 1, 0, <-1,   2, 2, 1,   <-1, <-2, <-2
bitv:   .byte 1, 2, 4, 8

; a wall at character (tx, ty)? Z clear if so. Keeps X.
csolid: lda ty
        and #$3C                ; the block's row, times 4
        sta c_p
        lda #0
        asl c_p                 ; times 64 in all
        rol a
        asl c_p
        rol a
        asl c_p
        rol a
        asl c_p
        rol a
        adc #>DMAP              ; (carry clear)
        sta c_p+1
        lda tx
        lsr a
        lsr a
        ora c_p
        sta c_p
        ldy #0
        lda (c_p),y
        lsr a
        lsr a                   ; the block
        clc
        adc #<BLKS
        sta c_q
        lda ty
        and #3
        adc #>BLKS
        sta c_q+1
        lda (c_q),y
        sta c_p
        lda tx
        and #3
        tay
        lda c_p
        and bitv,y
        rts

; any of the three points from X on a wall? Carry set if so.
sense:  lda #3
        sta n3
@pt:    lda cx
        clc
        adc sen_dx,x
        sta tx
        lda cy
        clc
        adc sen_dy,x
        sta ty
        jsr csolid
        bne @hit
        inx
        dec n3
        bne @pt
        clc
        rts
@hit:   sec
        rts

; the player's character: its middle's
pcell:  ldx #1
@ax:    lda ph,x
        sta cx,x
        lda pl,x
        lsr cx,x
        ror a
        lsr cx,x
        ror a
        lsr cx,x
        ror a
        sta cx,x
        dex
        bpl @ax
        rts

; one axis, X: 0 across, 1 up and down. The speed vh.vl by the keys (kp_of
; on, kn_of back), the position pl/ph moved, the points ahead looked at
axis:   stx ax
        lda kk
        and kp_of,x
        beq @nkey
        clc                     ; on: +$CF
        lda vl,x
        adc #$CF
        sta vl,x
        lda vh,x
        adc #0
        sta vh,x
        jmp @clamp
@nkey:  lda kk
        and kn_of,x
        beq @coast
        sec                     ; back: -$D0
        lda vl,x
        sbc #$D0
        sta vl,x
        lda vh,x
        sbc #0
        sta vh,x
        jmp @clamp
@coast: lda vh,x
        bmi @neg
        ora vl,x
        beq @move
        sec                     ; on, slowing: -$B0, nought at last
        lda vl,x
        sbc #$B0
        sta vl,x
        lda vh,x
        sbc #0
        sta vh,x
        bpl @move
        bmi @stop
@neg:   clc                     ; back, slowing: +$B0
        lda vl,x
        adc #$B0
        sta vl,x
        lda vh,x
        adc #0
        sta vh,x
        bmi @move
@stop:  lda #0
        sta vh,x
        sta vl,x
        beq @move
@clamp: lda vh,x
        bmi @cneg
        cmp vmax
        bcc @move
        lda vmax
        bcs @top
@cneg:  clc
        adc vmax
        bpl @move
        lda #0
        sec
        sbc vmax
@top:   sta vh,x
        lda #0
        sta vl,x
@move:  ldy #0                  ; the position += vh, and one more if vl
        lda vh,x
        bpl :+
        dey
:       lda vl,x
        cmp #1
        lda pl,x
        adc vh,x
        sta pl,x
        tya
        adc ph,x
        sta ph,x
        jsr pcell
        ldx ax
        lda vh,x                ; driving on: the points ahead that way
        bmi @back
        ora vl,x
        beq @back
        lda sp_of,x
        tax
        jsr sense
        ldx ax
        bcc @done
        lda pl,x                ; a wall: the character's back edge
        and #$F8
        bcs @wall
@back:  lda sp_of,x
        clc
        adc #3
        tax
        jsr sense
        ldx ax
        bcc @done
        lda pl,x                ; the character's front edge
        ora #7
@wall:  sta pl,x
        lda #0
        sta vh,x
        sta vl,x
@done:  rts

kp_of:  .byte K_RIGHT, K_DOWN
kn_of:  .byte K_LEFT, K_UP
sp_of:  .byte 0, 6

; move_player(k): a tick's driving by the keys k; firing, none
_move_player:
        sta kk
        and #K_FIRE
        beq :+
        lda #0
        sta kk
:       ldx _d_type
        ldy _dr_drive,x
        lda vmax_of,y
        sta vmax
        lda _d_x
        sta pl
        lda _d_x+1
        sta ph
        lda _d_y
        sta pl+1
        lda _d_y+1
        sta ph+1
        lda _d_vx
        sta vh
        lda _d_vy
        sta vh+1
        ldx #0
        jsr axis
        ldx #1
        jsr axis
        lda pl
        sta _d_x
        lda ph
        sta _d_x+1
        lda pl+1
        sta _d_y
        lda ph+1
        sta _d_y+1
        lda vh
        sta _d_vx
        lda vh+1
        sta _d_vy
        rts

; droid_look: droid X looks ahead before it moves, as the original's does
; ($1D30 there): its character and the next two the way it goes - here
; the farthest only, which it meets first. A wall there - a door not open
; yet - and it waits two ticks. Carry set if so.
; Only near the player, where the doors open and close (elsewhere they
; stay shut, and the droids go on through them, as before). Keeps X.
; Once free, the droid does not look again in the same character the same
; way (d_lk): the door ahead is near it then, and stays open.
droid_look:
        lda d_lk,x
        beq :+
        clc
        rts
:       txa
        asl a
        tay
        lda cx                  ; only on the screen or about to be, where
        lsr a                   ; the doors open (deck.c, doors()): its
        lsr a                   ; block against the player's (cx, cy, as
        sta n3                  ; move_player left them) - looked at first,
        lda _d_x+1,y            ; as most droids are farther
        asl a
        asl a
        asl a
        sta tx
        lda _d_x,y
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        ora tx
        sec
        sbc n3
        clc
        adc #7
        cmp #15
        bcs @free
        lda cy
        lsr a
        lsr a
        sta n3
        lda _d_y+1,y
        asl a
        asl a
        asl a
        sta ty
        lda _d_y,y
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        ora ty
        sec
        sbc n3
        clc
        adc #4
        cmp #9
        bcs @free
        lda _d_x+1,y            ; near: its character
        sta tx
        lda _d_x,y
        lsr tx
        ror a
        lsr tx
        ror a
        lsr tx
        ror a
        sta tx
        lda _d_y+1,y
        sta ty
        lda _d_y,y
        lsr ty
        ror a
        lsr ty
        ror a
        lsr ty
        ror a
        sta ty
        lda _d_vx,x             ; two characters on, the way it goes (the
        beq @y                  ; nearer ones it has passed already, and
        bmi :+                  ; a door near a droid does not close)
        inc tx
        inc tx
        bne @y
:       dec tx
        dec tx
@y:     lda _d_vy,x
        beq @look
        bmi :+
        inc ty
        inc ty
        bne @look
:       dec ty
        dec ty
@look:  jsr csolid
        bne @wall
        lda #1
        sta d_lk,x
@free:  clc
        rts
@wall:  lda #2
        sta _d_wait,x
        sec
        rts

; console_near(): a console within five blocks across and three up or down
; of the player: one may be used soon (paradroid.c starts the drive's motor
; for it, which takes two seconds; the player walks three blocks a second)
_console_near:
        lda _d_x+1              ; the player's block, less 5 and 3
        asl a
        asl a
        asl a
        sta tx
        lda _d_x
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        ora tx
        sec
        sbc #5
        sta tx
        lda _d_y+1
        asl a
        asl a
        asl a
        sta ty
        lda _d_y
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        ora ty
        sec
        sbc #3
        sta ty
        lda #7
        sta n3
@row:   lda #0                  ; the row in DMAP
        sta c_p
        lda ty
        and #15
        lsr a
        ror c_p
        lsr a
        ror c_p
        clc
        adc #>DMAP
        sta c_p+1
        lda tx
        sta c_q
        ldx #11
@col:   lda c_q
        and #63
        tay
        lda (c_p),y
        lsr a
        lsr a
        tay
        lda _blk_flag,y
        and #8                  ; B_CONSOLE
        bne @yes
        inc c_q
        dex
        bne @col
        inc ty
        dec n3
        bne @row
        lda #0
        tax
        rts
@yes:   lda #1
        ldx #0
        rts

; solid_at(x, y): a wall at world pixel (x, y)
_solid_at:
        sta ty
        txa
        lsr a
        ror ty
        lsr a
        ror ty
        lsr a
        ror ty
        jsr popax
        sta tx
        txa
        lsr a
        ror tx
        lsr a
        ror tx
        lsr a
        ror tx
        jsr csolid
        ldx #0
        rts

; doors(): each droid's block (d_bx, d_by, for move_shots() too); then the
; doors on the screen or about to be: one opens a stage a tick while a
; droid (not exploding) is in its block or one beside it, else it closes a
; stage. Elsewhere they stay as they are. Only the droids that can be by
; such a door are looked at: those noted in nbx/nby (nn of them).
_doors: ldx #0
        stx nn
        jsr dblk                ; the player's first
@all:   lda _d_boom,x           ; droid X by the screen?
        bne @nx
        lda _d_bx,x
        sec
        sbc _d_bx
        clc
        adc #8
        cmp #17
        bcs @nx
        lda _d_by,x
        sec
        sbc _d_by
        clc
        adc #5
        cmp #11
        bcs @nx
        ldy nn                  ; note it
        lda _d_bx,x
        sta nbx,y
        lda _d_by,x
        sta nby,y
        inc nn
@nx:    inx
        cpx _nd
        bcs @doors
        jsr dblk
        jmp @all
@doors: ldx #0
@door:  cpx _ndoor
        bcs @done
        stx di
        jsr door1
        ldx di
        inx
        bne @door
@done:  rts

; droid X's block into d_bx, d_by; keeps X
dblk:   txa
        asl a
        tay
        lda _d_x+1,y
        asl a
        asl a
        asl a
        sta tx
        lda _d_x,y
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        ora tx
        sta _d_bx,x
        lda _d_y+1,y
        asl a
        asl a
        asl a
        sta ty
        lda _d_y,y
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        ora ty
        sta _d_by,x
        rts

; door X, if near the player
door1:  lda _door_x,x           ; near the player?
        sec
        sbc _d_bx
        clc
        adc #7
        cmp #15
        bcs @next
        lda _door_y,x
        sec
        sbc _d_by
        clc
        adc #4
        cmp #9
        bcs @next
        ldy _door_x,x           ; a droid by it: its block, less one, up to
        dey                     ; two blocks less than the droid's
        sty tx
        ldy _door_y,x
        dey
        sty ty
        ldy nn
@j:     dey
        bmi @shut
        lda nbx,y
        sec
        sbc tx
        cmp #3
        bcs @j
        lda nby,y
        sec
        sbc ty
        cmp #3
        bcs @j
        lda _door_s,x           ; open a stage
        cmp #4
        bcs @next
        inc _door_s,x
        bne @set
@shut:  lda _door_s,x
        beq @next
        dec _door_s,x
@set:   lda _door_x,x
        sta _bs_x
        lda _door_y,x
        sta _bs_y
        ldy _door_v,x
        lda _door_s,x
        bne @stage
        lda #BLK_HDOOR << 2
        cpy #0
        beq @put
        lda #BLK_VDOOR << 2
        bne @put
@stage: cpy #0                  ; (the stages from 1)
        clc
        beq :+
        adc #BLK_VOPEN - 1
        bne @sh
:       adc #BLK_HOPEN - 1
@sh:    asl a
        asl a
@put:   sta _bs_v
        jmp _blk_set
@next:  rts

; bump_next(): from droid bump_i + 1 on, the next one (not exploding) that
; touches the player: less than 24 across and 16 up or down between their
; middles. Its number, 0 if none.
_bump_next:
        ldx _bump_i
@n:     inx
        cpx _nd
        bcs @none
        lda _d_boom,x
        bne @n
        txa
        asl a
        tay
        sec                     ; across: -23 .. 23, plus 23
        lda _d_x
        sbc _d_x,y
        sta tx
        lda _d_x+1
        sbc _d_x+1,y
        sta ty
        lda tx
        clc
        adc #23
        sta tx
        lda ty
        adc #0
        bne @n
        lda tx
        cmp #47
        bcs @n
        sec                     ; up and down: -15 .. 15, plus 15
        lda _d_y
        sbc _d_y,y
        sta c_q
        lda _d_y+1
        sbc _d_y+1,y
        sta c_q+1
        lda c_q
        clc
        adc #15
        sta c_q
        lda c_q+1
        adc #0
        bne @n
        lda c_q
        cmp #31
        bcs @n
        stx _bump_i
        txa
        ldx #0
        rts
@none:  stx _bump_i
        lda #0
        tax
        rts

; bump_back(i): the bump of droid i, as the original's ($1A73): the droid
; turns round and waits 16 ticks, the player is thrown back at twice its
; speed (at most its top speed), at 2 up and left if still that way
_bump_back:
        tax
        lda #16
        sta _d_wait,x
        lda #0
        sec
        sbc _d_vx,x
        sta _d_vx,x
        lda #0
        sec
        sbc _d_vy,x
        sta _d_vy,x
        lda #0                  ; the player: whole pixels only
        sta vl
        sta vl+1
        lda _d_vx
        jsr @back
        sta _d_vx
        lda _d_vy
        jsr @back
        sta _d_vy
        rts
@back:  bne :+                  ; -(v + v), with 1 for 0
        lda #1
:       eor #$FF
        clc
        adc #1
        asl a
        bmi @neg                ; no faster than the host drives (vmax,
        cmp vmax                ; move_player()'s this tick): bump on
        bcc :+                  ; bump between droids would double it
        lda vmax                ; each time, until the player flew
:       rts                     ; through walls and off the deck
@neg:   clc
        adc vmax
        bpl :+                  ; (-vmax or slower)
        lda #0
        sec
        sbc vmax
        rts
:       sec
        sbc vmax
        rts

; fig_place(d): the player's place moved by d (signed) across and down
_fig_place:
        tay
        clc
        adc _d_x
        sta _d_x
        tya                     ; (the sign into the high byte; the carry
        and #$80                ; stays)
        beq :+
        lda #$FF
:       adc _d_x+1
        sta _d_x+1
        tya
        clc
        adc _d_y
        sta _d_y
        tya
        and #$80
        beq :+
        lda #$FF
:       adc _d_y+1
        sta _d_y+1
        rts

; blk_at(x, y): the block under world pixel (x, y), as an index
_blk_at:
        sta c_p                 ; the row: y / 32
        txa
        asl a
        asl a
        asl a
        sta tx
        lda c_p
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        ora tx
        sta ty
        lsr a                   ; its place in DMAP, 64 to a row
        lsr a
        clc
        adc #>DMAP
        sta c_p+1
        lda ty
        and #3
        lsr a
        ror a
        ror a
        sta c_p
        jsr popax               ; the column: x / 32
        sta tx
        txa
        asl a
        asl a
        asl a
        sta ty
        lda tx
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        ora ty
        and #63
        tay
        lda (c_p),y
        lsr a
        lsr a
        ldx #0
        rts

; ---------------------------------------------------------------------------
; The decks' colours, the original's (data/colours.txt): every character
; has a colour class, every deck a scheme of colours for them ($27E5 and
; $2844 there).

        .import _deck_cleared, _deck_scheme, _schemes, _pal_deck, _pal_mc
        .import _alert, _deck_bg, _col_border, _eng_dirty, _panel_frame
        .import _tile_cls, _deck

BLKC    = $E800
CLS_HR  = $EAA0                 ; game.h: the scheme's TED colours, by
CLS_MC  = $EAB0                 ; class, hires and multicolour-safe
BLKA    = $EC00

; deck_colours(): the deck's own scheme, scheme 7 when its droids are
; gone; class 0 the window's background, class 3 the border's and the
; panel frame's; then every block character's colour
_deck_colours:
        lda _deck
        jsr _deck_cleared
        tax
        beq :+
        lda #7 * 12
        bne @s
:       ldx _deck
        lda _deck_scheme,x      ; (12 times the scheme)
@s:     tay
        ldx #0
:       lda _schemes,y          ; classes 0-11, as the C64's colours
        sta CLS_HR,x
        iny
        inx
        cpx #12
        bne :-
        ldx #11
:       ldy CLS_HR,x            ; the TED's
        lda _pal_mc,y
        sta CLS_MC,x
        lda _pal_deck,y
        sta CLS_HR,x
        dex
        bpl :-
        lda #$56                ; class 15: always light blue
        sta CLS_HR+15
        sta CLS_MC+15
        lda CLS_HR              ; (the background may have any colour:
        cmp #$56                ; light blue its nearest)
        bne :+
        lda #$5D
:       sta _deck_bg
        lda CLS_HR+3
        sta _col_border
        jsr _panel_frame
        jsr _colour_blocks
        jmp _eng_dirty          ; (col_deck: the game's loop)

; colour_blocks(): every block character's colour, by its class; the ALERT
; lights (class 14) the alert's
_colour_blocks:
        ldx _alert
        lda pal_alert,x
        sta CLS_HR+14
        sta CLS_MC+14
        ldx #0
@b:
        .repeat 4, R
        ldy BLKC + R * 256,x
        lda _tile_cls,y
        tay
        lda CLS_MC,y
        sta BLKA + R * 256,x
        .endrepeat
        inx
        bne @b
        rts

pal_alert:
        .byte $55, $77, $42, $32
