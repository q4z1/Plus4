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

        .export _move_player, _solid_at, droid_look
        .import popax, _d_x, _d_y, _d_vx, _d_vy, _d_type, _dr_drive, _d_wait

DMAP    = $0400
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
; ($1D30 there): its character and the next two the way it goes. A wall
; there - a door not open yet - and it waits two ticks. Carry set if so.
; Only near the player, where the doors open and close (elsewhere they
; stay shut, and the droids go on through them, as before). Keeps X.
droid_look:
        txa
        asl a
        tay
        lda _d_x+1,y
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
        lda tx                  ; only on the screen or about to be, where
        lsr a                   ; the doors open (deck.c, doors()): its
        lsr a                   ; block against the player's (cx, cy, as
        sta n3                  ; move_player left them)
        lda cx
        lsr a
        lsr a
        eor #$FF
        sec
        adc n3
        clc
        adc #7
        cmp #15
        bcs @free
        lda ty
        lsr a
        lsr a
        sta n3
        lda cy
        lsr a
        lsr a
        eor #$FF
        sec
        adc n3
        clc
        adc #4
        cmp #9
        bcs @free
        lda #3
        sta n3
@cell:  jsr csolid
        bne @wall
        lda _d_vx,x             ; a character on, the way it goes
        beq :++
        bmi :+
        inc tx
        bne :++
:       dec tx
:       lda _d_vy,x
        beq :++
        bmi :+
        inc ty
        bne :++
:       dec ty
:       dec n3
        bne @cell
@free:  clc
        rts
@wall:  lda #2
        sta _d_wait,x
        sec
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
