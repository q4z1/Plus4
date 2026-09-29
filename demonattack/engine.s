; ---------------------------------------------------------------------------
; engine.s - the Plus/4 end of Demon Attack
;
; Three jobs that have to be fast or have to be on time:
;
;   1. The raster interrupt. It works through a list of register writes,
;      each tied to a raster line, and at the bottom of the picture swaps the
;      two pictures over. This is how the demons get a colour of their own on
;      every line, the way the 2600 paints them.
;
;   2. Drawing. The screen is multicolour characters, and every figure is
;      made of characters handed out afresh for every picture. A cell two
;      figures share gets one character with both of them in it.
;
;   3. The tables all that needs, built once at start-up.
;
; Nothing in here knows anything about the game.
; ---------------------------------------------------------------------------

        .setcpu "6502"
        .macpack longbranch

        .export _eng_init, _eng_reset, _eng_chargen, _chargen
        .export _eng_page_on, _eng_page_off
        .export _frames, _back, _ready
        .export _ev_line, _ev_reg, _ev_val, _ev_n
        .export _r_begin, _r_prep8, _r_draw, _r_attr, _r_row_attr, _r_score
        .export _a_val, _a_col, _a_row, _a_n, _score_off
        .export _r_font_ptr, _r_scr_ptr, _r_att_ptr
        .export _o_d0, _o_n, _o_cx, _o_nc, _o_x, _o_col, _o_flags, _o_cmask
        .export _coldata, _rev, _sh_tab
        .exportzp _o_src, _o_mask, _o_rows
        .export _r_demon, _r_demon_off, _o_slot, _r_cannon, _r_quad, _nodraw
        .export _bar_val, _r_column, _r_vline, _o_val
        .exportzp _ram

; ---- TED ------------------------------------------------------------------

TED_SCROLLY = $FF06
TED_CTRL2   = $FF07
TED_IRQ     = $FF09
TED_IRQEN   = $FF0A
TED_RCMP    = $FF0B
TED_BMBASE  = $FF12
TED_CHBASE  = $FF13
TED_VMBASE  = $FF14
TED_BG      = $FF15
TED_COL1    = $FF16
TED_COL2    = $FF17
TED_BORDER  = $FF19
TED_SOUND   = $FF11
TED_RLINE   = $FF1D

; ---- memory ---------------------------------------------------------------

FONT0       = $C000             ; character set of picture 0, 256 * 8 bytes
FONT1       = $C800
MAT0        = $D000             ; colours at $D000, codes at $D400
MAT1        = $D800
PAGE        = $B800             ; the game-over page: colours, codes at +$400

; The character codes:
;     0          blank
;     1..3       ground, ground with a bunker, solid ground
BAR_CODE    = 4                 ; 4..59: a four-pixel point on one line (r_quad)
SCORE_CODE  = 60                ; 60..85: the score line
CANNON_CODE = 86                ; 86..91: the cannon
DEMON_CODE  = 92                ; 92..121: ten per demon slot
FIRSTDYN    = 122               ; 122..255: handed out picture by picture
EV_PER_LIST = 64                ; room for this many writes per picture
FRAME_REG   = $FF               ; "register" of the event that ends a picture
FRAME_LINE  = 206               ; raster line of that event, below the picture
TOP_LINE    = 270               ; unseen, between bottom and top border

CL_MAX      = 216               ; one cell per code that can be handed out
AR_MAX      = 32                ; runs of colour cells changed per picture

; ---- zero page ------------------------------------------------------------

        .segment "RAM2600": zeropage
_ram:   .res 128                ; $80-$FF, as on the 2600

        .segment "ENGZP": zeropage
_o_src:     .res 2              ; r_prep8: sprite bytes, top line first
_o_mask:    .res 2              ; r_draw: 8 bytes, which bits each cell line keeps
p_col:      .res 2              ; column being drawn, biased so (p_col),y = line y
p_dst:      .res 2              ; character being drawn into
p_scr:      .res 2              ; matrix cell
p_tmp:      .res 2
z_ly:       .res 1              ; first cell line of the current piece
z_end:      .res 1              ; one past its last cell line
z_i:        .res 1              ; object line the piece starts with
z_d:        .res 1              ; display line the piece starts on
z_c:        .res 1              ; column counter
z_col:      .res 1              ; screen column
z_row:      .res 1
z_fresh:    .res 1
z_t:        .res 1
z_sub:      .res 1
z_line:     .res 1
z_k:        .res 1
_o_rows:    .res 2              ; r_demon: which lines of each column are set
z_cx:       .res 1
z_nc:       .res 1
z_row0:     .res 1
z_rows:     .res 1
z_srcl:     .res 1
z_srch:     .res 1
z_old:      .res 1
z_new:      .res 1
z_nrows:    .res 1
z_si:       .res 1
z_code0:    .res 1
z_codeend:  .res 1
z_own:      .res 1
z_conf:     .res 1
z_confl:    .res 1
z_ql:       .res 1              ; r_quad
z_qr:       .res 1
z_vl:       .res 1
z_vr:       .res 1
z_v:        .res 1
z_g:        .res 1
z_c2:       .res 1
z_rol:      .res 1              ; r_draw: offset of the row in the matrix
z_roh:      .res 1
z_bias:     .res 1
z_u:        .res 1              ; every pixel of a sprite, all lines ORed
p_cll:      .res 2              ; cell list of the back buffer: low bytes
p_clh:      .res 2              ; and high bytes
p_clc:      .res 2              ; and the codes to put back

; ---- ordinary memory --------------------------------------------------------

        .bss
_frames:    .res 1              ; counts pictures, the game's only clock
_back:      .res 1              ; the picture being drawn: 0 or 1
_ready:     .res 1              ; set when it is complete; the IRQ shows it
_nodraw:    .res 1              ; bit 7: a frame whose picture is skipped
front:      .res 1
ev_pos:     .res 1
_ev_n:      .res 1              ; writes queued for the picture being drawn
_ev_line:   .res 2*EV_PER_LIST
_ev_reg:    .res 2*EV_PER_LIST
_ev_val:    .res 2*EV_PER_LIST

_o_val:     .res 1              ; r_vline: the byte
_o_d0:      .res 1              ; r_draw: top display line
_o_n:       .res 1              ; lines, up to 16
_o_cx:      .res 1              ; first screen column
_o_nc:      .res 1              ; columns, up to 9
_o_x:       .res 1              ; r_prep8: multicolour pixel 0..159
_o_col:     .res 1              ; r_prep8: first column in coldata
_o_flags:   .res 1              ; r_prep8: 1 mirror, 2 add to what is there, 4 quad
_o_cmask:   .res 2              ; columns of coldata with pixels: bit c of the
                                ; first byte is column c, the second byte column 8

next_code:  .res 1
cl_n:       .res 2
cl_lo0:     .res CL_MAX         ; cells handed a character, picture 0
cl_hi0:     .res CL_MAX
cl_cd0:     .res CL_MAX         ; and the code that goes back there
cl_lo1:     .res CL_MAX         ; the same for picture 1
cl_hi1:     .res CL_MAX
cl_cd1:     .res CL_MAX
ar_n:       .res 2
ar_lo:      .res 2*AR_MAX       ; runs of colour cells changed, per picture
ar_hi:      .res 2*AR_MAX
ar_cnt:     .res 2*AR_MAX       ; how many cells
ar_val:     .res 2*AR_MAX       ; what to put back

; Columns of the figure being drawn: 9 columns of 32 bytes, the 16 lines of
; the figure in the middle and 8 zero bytes on either side, so a character
; can read lines above or below the figure without looking.
_coldata:   .res 9*32

        .segment "HIBSS"
sh_tab:     .res 12*256         ; [sub*3+k][byte]: 8 pixels shifted by sub
_sh_tab     = sh_tab
_rev:       .res 256            ; bit order reversed - the 2600's REFP1
code_lo:    .res 256            ; code * 8
code_hi:    .res 256

        .rodata
row_lo:     .repeat 25, R
            .byte <(R*40)
            .endrepeat
row_hi:     .repeat 25, R
            .byte >(R*40)
            .endrepeat
font_hi:    .byte >FONT0, >FONT1
scr_hi:     .byte >(MAT0+$400), >(MAT1+$400)
att_hi:     .byte >MAT0, >MAT1
ev_base:    .byte 0, EV_PER_LIST
cll_lo:     .byte <cl_lo0, <cl_lo1
cll_hi:     .byte >cl_lo0, >cl_lo1
clh_lo:     .byte <cl_hi0, <cl_hi1
clh_hi:     .byte >cl_hi0, >cl_hi1
clc_lo:     .byte <cl_cd0, <cl_cd1
clc_hi:     .byte >cl_cd0, >cl_cd1
ar_base:    .byte 0, AR_MAX
quad_l:     .byte $FF, $3F, $0F, $03 ; a quad pixel's share of its own byte
quad_r:     .byte $00, $C0, $F0, $FC ; and of the next one
upper_mask: .byte $FF, $7F, $3F, $1F, $0F, $07, $03, $01 ; demon lines 0..7-ly
col_bit:    .byte $01, $02, $04, $08, $10, $20, $40, $80, $00, $00
lower_mask: .byte $00, $01, $03, $07, $0F, $1F, $3F, $7F ; demon lines 8-ly..7
demon_mask: .byte $FF, $55, $AA, $55, $AA, $55, $AA, $55
            .byte $FF, $55, $AA, $55, $AA, $55, $AA, $55
_bar_val:   .byte $FF, $3F, $0F, $03, $C0, $F0, $FC
bar_base:   .repeat 8, L
            .byte BAR_CODE + 7 * L
            .endrepeat
col16p8:    .byte 8, 24, 40, 56, 72
col_lo:     .repeat 9, C
            .byte <(_coldata+8+C*32)
            .endrepeat
col_hi:     .repeat 9, C
            .byte >(_coldata+8+C*32)
            .endrepeat

        .code

; ===========================================================================
; Start-up
; ===========================================================================

_eng_init:
        sei
        ; --- tables -------------------------------------------------------
        ; sh_tab: for each shift 0..3 and each of the three bytes an 8-pixel
        ; row can touch, the multicolour bits (%11 per pixel).
        ldx #0
@sh:    stx z_t                 ; the 8 pixels
        lda #0
        sta z_sub
@shs:   ; build 12 pixels: z_sub empty ones, the 8, the rest empty,
        ; two bits each, into p_tmp (hi), p_tmp+1 (mid), z_k (lo)
        lda #0
        sta p_tmp
        sta p_tmp+1
        sta z_k
        ldy z_sub
        beq @pix
@pad:   jsr sh_zero
        dey
        bne @pad
@pix:   ldy #8
        lda z_t
        sta z_line
@pbit:  asl z_line
        bcc @p0
        jsr sh_one
        jmp @pn
@p0:    jsr sh_zero
@pn:    dey
        bne @pbit
        ; pad to 12 pixels
        lda #4
        sec
        sbc z_sub
        tay
@pad2:  jsr sh_zero
        dey
        bne @pad2
        ; store the three bytes
        lda z_sub
        asl a
        clc
        adc z_sub               ; sub*3
        clc
        adc #>sh_tab
        sta p_dst+1
        lda #0
        sta p_dst
        ldy z_t
        lda p_tmp
        sta (p_dst),y
        inc p_dst+1
        lda p_tmp+1
        sta (p_dst),y
        inc p_dst+1
        lda z_k
        sta (p_dst),y
        inc z_sub
        lda z_sub
        cmp #4
        bne @shs
        ldx z_t
        ; reversed bits
        txa
        ldy #8
@rv:    lsr a
        rol z_line
        dey
        bne @rv
        lda z_line
        sta _rev,x
        ; code * 8
        txa
        asl a
        asl a
        asl a
        sta code_lo,x
        txa
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        sta code_hi,x
        inx
        beq @tabsdone
        jmp @sh
@tabsdone:

        ; --- both pictures empty -----------------------------------------------
        lda #0
        tay
        ldx #$C0
@clr:   stx p_dst+1
        sty p_dst
@clr2:  sta (p_dst),y
        iny
        bne @clr2
        inx
        cpx #$E0
        bne @clr
        sta cl_n
        sta cl_n+1
        sta ar_n
        sta ar_n+1
        lda #$FF
        sta can_x
        sta can_x+1
        ldx #5
:       sta ds_ly,x
        dex
        bpl :-
        lda #0
        sta _ready
        sta front
        sta _ev_n
        lda #1
        sta _back
        lda #FIRSTDYN
        sta next_code

        ; an empty event list for both pictures: just the end-of-picture one
        ldx #0
        jsr ev_empty
        ldx #EV_PER_LIST
        jsr ev_empty
        lda #0
        sta ev_pos

        ; --- vectors -------------------------------------------------------
        lda #<irq
        sta $FFFE
        lda #>irq
        sta $FFFF
        lda #<nmi
        sta $FFFA
        lda #>nmi
        sta $FFFB

        ; --- TED -----------------------------------------------------------
        lda #$1B                ; text, display on, 25 rows, y scroll 3
        sta TED_SCROLLY
        lda #$98                ; 256 characters, multicolour, 40 columns
        sta TED_CTRL2
        lda TED_BMBASE
        and #$FB                ; characters from RAM
        sta TED_BMBASE
        lda #>FONT0
        sta TED_CHBASE
        lda #>MAT0
        sta TED_VMBASE
        lda #0
        sta TED_BG
        sta TED_BORDER
        sta TED_COL1
        sta TED_COL2

        lda #FRAME_LINE
        sta TED_RCMP
        lda #$02                ; raster interrupt only, compare bit 8 = 0
        sta TED_IRQEN
        lda TED_IRQ
        sta TED_IRQ
        cli
        rts

; one more pixel into the 12-pixel shift register (MSB first)
sh_one: sec
        rol z_k
        rol p_tmp+1
        rol p_tmp
        sec
        rol z_k
        rol p_tmp+1
        rol p_tmp
        rts
sh_zero:
        asl z_k
        rol p_tmp+1
        rol p_tmp
        asl z_k
        rol p_tmp+1
        rol p_tmp
        rts

ev_empty:
        lda #FRAME_LINE
        sta _ev_line,x
        lda #FRAME_REG
        sta _ev_reg,x
        rts

; Back to BASIC the hard way: a cold start. The game has used every part of
; the machine, so there is nothing to return to.
; eng_page_on / eng_page_off: a still page of plain text instead of the
; game - the score at the end of a game, to be photographed. While it is up
; there is no raster interrupt at all: one-colour characters from the ROM's
; character set, the matrix at PAGE, nothing changing on the way down.
; Off again, the picture being shown comes back and the interrupt picks up
; at the top of the next one.
_eng_page_on:
        sei
        lda #0
        sta TED_IRQEN
        lda TED_IRQ
        sta TED_IRQ
        lda #0
        sta TED_BG
        sta TED_BORDER
        sta TED_SOUND           ; quiet
        lda #$88                ; 256 characters, one colour, 40 columns
        sta TED_CTRL2
        lda TED_BMBASE
        ora #$04                ; characters from ROM
        sta TED_BMBASE
        lda #$D0                ; the ROM's own character set
        sta TED_CHBASE
        lda #>PAGE
        sta TED_VMBASE
        cli
        rts

_eng_page_off:
        sei
        lda #$98
        sta TED_CTRL2
        lda TED_BMBASE
        and #$FB
        sta TED_BMBASE
        ldx front
        lda font_hi,x
        sta TED_CHBASE
        lda att_hi,x
        sta TED_VMBASE
        lda ev_base,x
        sta ev_pos
        lda #<TOP_LINE
        sta TED_RCMP
        lda #$03                ; raster interrupt, compare bit 8 set
        sta TED_IRQEN
        lda TED_IRQ
        sta TED_IRQ
        cli
        rts

; eng_chargen: the first 64 characters of the Plus/4's character ROM - the
; capitals, digits and signs - into chargen, for the demo's messages. The
; ROM is switched in for that; nothing on the stack is touched meanwhile,
; as the ROM hides the RAM the stack is in.
_eng_chargen:
        php
        sei
        sta $FF3E               ; ROM in
        ldx #0
:       lda $D000,x
        sta _chargen,x
        lda $D100,x
        sta _chargen+256,x
        inx
        bne :-
        sta $FF3F               ; ROM out
        plp
        rts

_eng_reset:
        sei
        lda #0
        sta TED_IRQEN
        lda TED_IRQ
        sta TED_IRQ
        sta $FF3E               ; ROM in
        jmp ($FFFC)

nmi:    rti

; ===========================================================================
; The raster interrupt
;
; ev_pos points at the next write of the picture on screen. A write is due
; at the start of its line. If that is at most two lines off, the handler
; waits for it right here; otherwise it asks to be called two lines early
; and leaves. Two, because on the visible part of the screen the CPU runs at
; half speed - a line is 57 cycles - and getting from the interrupt to the
; first write takes 70. On the lines where the TED fetches a row of
; characters it does not get the bus until the end of the line at all.
;
; A write costs some 30 cycles, so a visible line has room for one. The
; lists are built that way: every colour goes into its register a line
; before it is needed, into a register the line in between does not show,
; one per line.
; ===========================================================================

irq:    pha
        txa
        pha
        tya
        pha
        lda TED_IRQ
        sta TED_IRQ
        lda TED_IRQEN
        lsr a
        bcs @top                ; the one in the vertical blank
        ldx ev_pos
@next:  lda _ev_line,x
        cmp TED_RLINE
        beq @now
        bcc @now                ; late: at once
        sbc TED_RLINE           ; how far ahead (carry is set)
        cmp #3
        bcs @later
        lda _ev_line,x
@wait:  cmp TED_RLINE
        bne @wait
@now:   ldy _ev_reg,x
        cpy #FRAME_REG
        beq @frame
        lda _ev_val,x
        sta $FF00,y
        inx
        jmp @next
@later: lda _ev_line,x
        sec
        sbc #2                  ; come back two lines early: getting here
        sta TED_RCMP            ; takes more than a line on screen
        stx ev_pos
        pla
        tay
        pla
        tax
        pla
        rti

; Bottom of the picture: show the new one if it is finished.
@frame: lda _ready
        beq @same
        lda _back
        sta front
        tax
        lda font_hi,x
        sta TED_CHBASE
        lda att_hi,x
        sta TED_VMBASE
        txa
        eor #1
        sta _back
        lda #0
        sta _ready
@same:  inc _frames
        ldx front
        lda ev_base,x
        sta ev_pos
        ; next stop: the vertical blank, to turn the border black for the
        ; top of the next picture (the ground colour stays below it)
        lda #<TOP_LINE
        sta TED_RCMP
        lda #$03                ; raster interrupt, compare bit 8 set
        sta TED_IRQEN
        pla
        tay
        pla
        tax
        pla
        rti

@top:   lda #0
        sta TED_BORDER
        lda #$02                ; compare bit 8 clear again
        sta TED_IRQEN
        ldx ev_pos
        lda _ev_line,x
        sec
        sbc #2
        sta TED_RCMP
        pla
        tay
        pla
        tax
        pla
        rti

; ===========================================================================
; Drawing
; ===========================================================================

; r_begin: start a picture in the back buffer. Every cell the picture
; before last handed out goes back to blank, every colour cell it changed
; goes back to what it was.
_r_begin:
        ldx _back
        lda cll_lo,x
        sta p_cll
        lda cll_hi,x
        sta p_cll+1
        lda clh_lo,x
        sta p_clh
        lda clh_hi,x
        sta p_clh+1
        lda clc_lo,x
        sta p_clc
        lda clc_hi,x
        sta p_clc+1
        lda scr_hi,x
        sta z_t                 ; high byte of the code matrix
        ldy cl_n,x              ; backwards: a cell noted twice gets back
        beq @cells_done         ; what it had first
@cl:    dey
        lda (p_cll),y
        sta p_scr
        lda (p_clh),y
        clc
        adc z_t
        sta p_scr+1
        lda (p_clc),y
        sty z_line
        ldy #0
        sta (p_scr),y
        ldy z_line
        bne @cl
        lda #0
        sta cl_n,x
@cells_done:
        lda att_hi,x
        sta z_t
        lda ar_base,x
        tay
        lda ar_n,x
        beq @attr_done
        sta z_k
@ar:    lda ar_lo,y
        sta p_scr
        lda ar_hi,y
        clc
        adc z_t
        sta p_scr+1
        lda ar_cnt,y
        sta z_end
        lda ar_val,y
        sty z_line
        ldy z_end
        dey
@arr:   sta (p_scr),y
        dey
        bpl @arr
        ldy z_line
        iny
        dec z_k
        bne @ar
        lda #0
        sta ar_n,x
@attr_done:
        lda #FIRSTDYN
        sta next_code
        lda #0
        sta _ev_n
        rts

; r_prep8: turn an 8-pixel sprite into columns of multicolour bytes.
;   o_src   the sprite, top line first, o_n lines (up to 16)
;   o_x     its multicolour pixel; only the lowest two bits count here
;   o_col   the column of coldata its first byte goes to: 0 or 2 (a demon's
;           right half is exactly two columns to the right of its left one)
;   o_flags 1 = mirrored, 2 = add to the columns instead of replacing,
;           4 = quad width (every pixel four wide, nine columns from 0),
;           8 = when replacing, clear the two columns after as well - for a
;               right half that is added two columns on
_r_prep8:
        bit _nodraw             ; only working out collisions: nothing to draw
        bpl :+
        rts
:
        lda _o_x
        and #3
        sta z_sub
        lda _o_flags
        and #4
        beq :+
        jmp prep_quad
:       ; the three shift tables for this sub: bytes 0, 1 and 2 of the row
        lda z_sub
        asl a
        adc z_sub
        adc #>sh_tab
        sta p_dst+1
        adc #1
        sta p_scr+1
        adc #1
        sta p_tmp+1
        lda #0
        sta p_dst
        sta p_scr
        sta p_tmp
        ; x = where line 0 of the first column lives in coldata
        lda _o_col
        asl a
        asl a
        asl a
        asl a
        asl a
        ora #8
        tax
        lda #0
        sta z_line
        sta z_u
@line:  ldy z_line
        lda (_o_src),y
        tay
        lda _o_flags
        lsr a
        bcc :+
        lda _rev,y
        tay
:       tya
        ora z_u
        sta z_u
        lda _o_flags
        and #2
        bne @add
        lda (p_dst),y
        sta _coldata,x
        lda (p_scr),y
        sta _coldata+32,x
        lda (p_tmp),y
        sta _coldata+64,x
        lda _o_flags
        and #8
        beq @nx
        lda #0                  ; the two columns a right half will add to
        sta _coldata+96,x
        sta _coldata+128,x
        jmp @nx
@add:   lda (p_dst),y
        ora _coldata,x
        sta _coldata,x
        lda (p_scr),y
        ora _coldata+32,x
        sta _coldata+32,x
        lda (p_tmp),y
        ora _coldata+64,x
        sta _coldata+64,x
@nx:    inx
        inc z_line
        lda z_line
        cmp _o_n
        bne @line
        ; which of the three columns got pixels
        lda _o_flags
        and #2
        bne :+
        lda #0                  ; replacing: nothing else is there
        sta _o_cmask
        sta _o_cmask+1
:       ldx _o_col
        ldy z_u
        lda (p_dst),y
        beq :+
        lda col_bit,x
        ora _o_cmask
        sta _o_cmask
:       lda (p_scr),y
        beq :+
        lda col_bit+1,x
        ora _o_cmask
        sta _o_cmask
:       lda (p_tmp),y
        beq :+
        lda col_bit+2,x
        ora _o_cmask
        sta _o_cmask
:       rts

; Quad width: every sprite pixel is a whole multicolour byte wide, shifted by
; sub, so a line covers nine columns. Always replaces.
prep_quad:
        lda #0
        sta z_line
        sta z_u
@line:  ldy z_line
        lda (_o_src),y
        tay
        lda _o_flags
        lsr a
        bcc :+
        lda _rev,y
        tay
:       sty z_t
        tya
        ora z_u
        sta z_u
        ldx z_line
        lda #0
        .repeat 9, C
        sta _coldata+8+C*32,x
        .endrepeat
        ldy z_sub
        .repeat 8, C
        asl z_t
        bcc :+
        lda quad_l,y
        ora _coldata+8+C*32,x
        sta _coldata+8+C*32,x
        lda quad_r,y
        ora _coldata+8+(C+1)*32,x
        sta _coldata+8+(C+1)*32,x
:
        .endrepeat
        inc z_line
        lda z_line
        cmp _o_n
        jne @line
        ; columns: j for every pixel j, j+1 as well when shifted
        lda z_u
        ldx z_sub
        beq :+
        lsr a                   ; the pixel's spill into the next column
        ora z_u
:       sta _o_cmask            ; bit 7-j is column j - reverse it
        tay
        lda _rev,y
        sta _o_cmask
        lda #0
        sta _o_cmask+1
        ldx z_sub
        beq :+
        lda z_u
        and #1                  ; pixel 7 spills into column 8
        sta _o_cmask+1
:       rts

; r_draw: put the columns in coldata on the screen of the back buffer.
;   o_d0   display line of the first object line, o_n lines
;   o_cx   screen column of the first data column (wraps at 40, as the
;          2600 wraps at 160 pixels), o_nc columns
;   o_cmask the columns that have pixels at all (r_prep8 sets it)
;   o_mask 8 bytes, one per line of a character: which bits survive. That
;          is where a figure's colour comes from.
; A cell nobody has claimed yet in this picture gets a fresh character that
; is written whole; a cell somebody has claimed gets the figure added in.
; Row by row: everything that depends only on the character row is worked
; out once for all columns.
_r_draw:
        bit _nodraw             ; only working out collisions: nothing to draw
        bpl :+
        rts
:
        lda #0
        sta z_i
        lda _o_d0
        sta z_d
@piece: ; the character row of this piece and its lines in it
        lda z_d
        lsr a
        lsr a
        lsr a
        cmp #25
        bcc :+
        rts
:       sta z_row
        tax
        lda row_lo,x            ; offset of the row in the matrix
        sta z_rol
        lda row_hi,x
        sta z_roh
        clc
        ldx _back
        adc scr_hi,x
        sta p_scr+1
        lda z_rol
        sta p_scr
        lda z_d
        and #7
        sta z_ly
        lda _o_n                ; lines in this piece: min(8 - ly, n - i)
        sec
        sbc z_i
        sta z_t
        lda #8
        sec
        sbc z_ly
        cmp z_t
        bcc :+
        lda z_t
:       sta z_k
        clc
        adc z_ly
        sta z_end
        lda z_i                 ; (p_col),y is the object line for cell line
        sec                     ; y when p_col = column + i - ly
        sbc z_ly
        sta z_bias
        lda #0
        sta z_c
        lda _o_cx
        sta z_col
@col:   ldx z_c                 ; any pixels in this column at all?
        cpx #8
        bcc :+
        lda _o_cmask+1
        jmp @cm
:       lda _o_cmask
        and col_bit,x
@cm:    jeq @nextc
        lda col_lo,x            ; p_col = column + bias (signed)
        ldy z_bias
        bmi @neg
        clc
        adc z_bias
        sta p_col
        lda col_hi,x
        adc #0
        sta p_col+1
        jmp @any
@neg:   clc
        adc z_bias
        sta p_col
        lda col_hi,x
        adc #$FF
        sta p_col+1
@any:   ldy z_ly                ; any pixels in this piece?
:       lda (p_col),y
        bne @some
        iny
        cpy z_end
        bne :-
        jmp @nextc
@some:  ldy z_col
        lda (p_scr),y
        beq @new
        cmp #DEMON_CODE
        bcs @have
        ; a fixed character: draw into a copy of it
        sta z_old
        lda next_code
        jeq @nextc
        sta (p_scr),y
        inc next_code
        jsr rem_cell
        lda z_old
        ldx _back
        jsr code_ptr
        lda p_dst
        sta p_tmp
        lda p_dst+1
        sta p_tmp+1
        lda z_new
        jsr code_ptr
        ldy #7
:       lda (p_tmp),y
        sta (p_dst),y
        dey
        bpl :-
        jmp @orin
@have:  jsr taint
        ldx _back
        jsr code_ptr
        jmp @orin
@new:   sta z_old
        lda next_code
        beq @nextc
        sta (p_scr),y
        inc next_code
        jsr rem_cell
        ldx _back
        jsr code_ptr
        ; fresh: zeros, the piece, zeros
        ldy #0
        lda #0
        cpy z_ly
        beq @fdata
@fz1:   sta (p_dst),y
        iny
        cpy z_ly
        bne @fz1
@fdata: lda (p_col),y
        and (_o_mask),y
        sta (p_dst),y
        iny
        cpy z_end
        bne @fdata
        cpy #8
        beq @nextc
        lda #0
@fz2:   sta (p_dst),y
        iny
        cpy #8
        bne @fz2
        jmp @nextc
@orin:  ldy z_ly
@or:    lda (p_col),y
        and (_o_mask),y
        ora (p_dst),y
        sta (p_dst),y
        iny
        cpy z_end
        bne @or
@nextc: inc z_col
        lda z_col
        cmp #40
        bcc :+
        lda #0
        sta z_col
:       inc z_c
        lda z_c
        cmp _o_nc
        jcc @col
        ; the next piece
        lda z_i
        clc
        adc z_k
        sta z_i
        lda z_d
        clc
        adc z_k
        sta z_d
        lda z_i
        cmp _o_n
        jcc @piece
        rts

; the code just handed out (A) in cell z_col of row z_rol/z_roh: note it,
; with what goes back there (z_old)
rem_cell:
        sta z_new
        ldx _back
        ldy cl_n,x
        lda z_rol
        clc
        adc z_col
        sta (p_cll),y
        lda z_roh
        adc #0
        sta (p_clh),y
        lda z_old
        sta (p_clc),y
        inc cl_n,x
        lda z_new
        rts

; r_vline: a vertical line one byte wide - the cannon's laser. Every line
; is the same byte.
;   o_val  the byte (its pixel, in its colour)
;   o_cx   screen column
;   o_d0   display line of the first line, o_n lines
_r_vline:
        bit _nodraw             ; only working out collisions: nothing to draw
        bpl :+
        rts
:       lda _o_cx
        sta z_col
        lda #0
        sta z_i
        lda _o_d0
        sta z_d
@piece: lda z_d
        lsr a
        lsr a
        lsr a
        cmp #25
        bcs @done
        sta z_row
        lda z_d
        and #7
        sta z_ly
        lda _o_n                ; lines in this piece: min(8 - ly, n - i)
        sec
        sbc z_i
        sta z_k
        lda #8
        sec
        sbc z_ly
        cmp z_k
        bcs :+
        sta z_k
:       lda z_k
        clc
        adc z_ly
        sta z_end
        jsr cell_get
        bcs @next               ; no characters left
        ldy #0
        lda z_fresh
        beq @or
@fr:    lda #0                  ; fresh: the byte on the piece's lines
        cpy z_ly
        bcc :+
        cpy z_end
        bcs :+
        lda _o_val
:       sta (p_dst),y
        iny
        cpy #8
        bne @fr
        beq @next
@or:    ldy z_ly
:       lda _o_val
        ora (p_dst),y
        sta (p_dst),y
        iny
        cpy z_end
        bne :-
@next:  lda z_i
        clc
        adc z_k
        sta z_i
        lda z_d
        clc
        adc z_k
        sta z_d
        lda z_i
        cmp _o_n
        bcc @piece
@done:  rts

; r_column: a column of 8-pixel lines in colour %01 - the demons' laser,
; which is a long thin figure. It goes straight from the lines to the
; characters, piece of a character row by piece, without columns in
; between: only the characters with pixels are touched at all.
;   o_src  the lines, top first, o_n of them (up to 255)
;   o_d0   display line of the first
;   o_x    multicolour pixel of their left edge
_r_column:
        bit _nodraw             ; only working out collisions: nothing to draw
        bpl :+
        rts
:       lda _o_x
        and #3
        sta z_sub
        asl a
        adc z_sub
        adc #>sh_tab
        sta z_sub               ; page of byte 0 of the shifted pixels
        lda #0
        sta z_i
        lda _o_d0
        sta z_d
@piece: lda z_d
        lsr a
        lsr a
        lsr a
        cmp #25
        bcc :+
        rts
:       sta z_row
        lda z_d
        and #7
        sta z_ly
        lda _o_n                ; lines in this piece: min(8 - ly, n - i)
        sec
        sbc z_i
        sta z_t
        lda #8
        sec
        sbc z_ly
        cmp z_t
        bcc :+
        lda z_t
:       sta z_k
        clc
        adc z_ly
        sta z_end
        lda z_i                 ; p_col = o_src + i - ly: (p_col),y is the
        sec                     ; line for cell line y
        sbc z_ly
        sta z_bias
        clc
        adc _o_src
        sta p_col
        lda _o_src+1
        adc #0
        ldx z_bias
        bpl :+
        sbc #0                  ; (carry is clear: minus one)
:       sta p_col+1
        ; all lines of the piece ORed: which columns get pixels
        lda #0
        ldy z_ly
:       ora (p_col),y
        iny
        cpy z_end
        bne :-
        sta z_u
        tax
        jeq @nextp
        lda _o_x
        lsr a
        lsr a
        sta z_col
        lda #0
        sta z_c
@col:   lda z_sub
        clc
        adc z_c
        sta @t1+2
        sta @t2+2
        sta @t0+2
@t0:    lda sh_tab,x            ; x = z_u
        beq @nextc
        jsr cell_get
        bcs @nextc              ; no characters left
        lda z_fresh
        beq @or
        ; fresh: zeros, the piece, zeros
        ldy #0
        lda #0
        cpy z_ly
        beq @fdata
@fz1:   sta (p_dst),y
        iny
        cpy z_ly
        bne @fz1
@fdata: lda (p_col),y
        tax
@t1:    lda sh_tab,x
        and #$55
        sta (p_dst),y
        iny
        cpy z_end
        bne @fdata
        cpy #8
        beq @nextc
        lda #0
@fz2:   sta (p_dst),y
        iny
        cpy #8
        bne @fz2
        beq @nextc
@or:    ldy z_ly
@ol:    lda (p_col),y
        tax
@t2:    lda sh_tab,x
        and #$55
        ora (p_dst),y
        sta (p_dst),y
        iny
        cpy z_end
        bne @ol
@nextc: ldx z_col
        inx
        cpx #40
        bcc :+
        ldx #0
:       stx z_col
        ldx z_u
        inc z_c
        lda z_c
        cmp #3
        bne @col
@nextp: lda z_i
        clc
        adc z_k
        sta z_i
        lda z_d
        clc
        adc z_k
        sta z_d
        lda z_i
        cmp _o_n
        jcc @piece
        rts

; r_quad: a sprite four times as wide - the halves of a demon being made,
; whose pictures are a few scattered points. Instead of building nine
; columns and looking at every cell, it goes point by point: each point is
; four pixels on one line, a byte in one character or split over two.
;   o_src   eight lines, top first; o_flags bit 0: mirrored
;   o_x     pixel of the sprite's left edge
;   o_d0    display line of the top line
; Uses the demon mask (see band_colours in kernel.s).
_r_quad:
        bit _nodraw             ; only working out collisions: nothing to draw
        bpl :+
        rts
:
        lda _o_x
        and #3
        sta z_ql                ; the point's own byte: vi = sub
        clc
        adc #3
        sta z_qr                ; its spill: vi = 3 + sub, if sub > 0
        lda _o_x
        lsr a
        lsr a
        sta z_cx
        lda #0
        sta z_line
@row:   ldy z_line
        lda (_o_src),y
        beq @nextrow
        tay
        lda _o_flags
        lsr a
        bcc :+
        lda _rev,y
        tay
:       sty z_g
        lda _o_d0
        clc
        adc z_line
        sta z_d
        lsr a
        lsr a
        lsr a
        cmp #25
        bcs @nextrow
        tax                     ; the character row and its matrix line
        lda row_lo,x
        sta z_rol
        sta p_scr
        lda row_hi,x
        sta z_roh
        ldx _back
        clc
        adc scr_hi,x
        sta p_scr+1
        lda z_d
        and #7
        sta z_ly                ; the line in the character
        lda z_cx
        sta z_col
@bit:   asl z_g
        bcc @nobit
        lda z_ql
        jsr quad_touch
        lda z_ql
        beq @nobit              ; sub 0: no spill
        inc z_col
        lda z_qr
        jsr quad_touch
        dec z_col
@nobit: inc z_col
        lda z_g
        bne @bit
@nextrow:
        inc z_line
        lda z_line
        cmp #8
        bne @row
        rts

; point vi (0..3: a pixel's own byte for sub 0..3, 4..6: its spill into
; the next byte for sub 1..3) on line z_ly of cell (current row, column
; z_col mod 40). A point alone in its cell is one of the fixed characters
; BAR_CODE + 7*line + vi, and costs no more than a code in the matrix; a
; second point in the cell makes it a character of its own.
quad_touch:
        sta z_v
        lda z_col
        cmp #40
        bcc :+
        sbc #40
:       sta z_c2
        tay
        lda (p_scr),y
        bne @taken
        ldx z_ly                ; a cell of its own: the fixed character
        lda bar_base,x
        clc
        adc z_v
        sta (p_scr),y
        lda #0
        jmp note_cell
@taken: cmp #DEMON_CODE
        bcs @add
        ; a fixed character (another point): a copy of it
        sta z_old
        lda next_code
        beq @done
        sta (p_scr),y
        inc next_code
        sta z_new
        lda z_old
        jsr note_cell
        ldx _back
        lda z_old
        jsr code_ptr
        lda p_dst
        sta p_tmp
        lda p_dst+1
        sta p_tmp+1
        lda z_new
        jsr code_ptr
        ldy #7
:       lda (p_tmp),y
        sta (p_dst),y
        dey
        bpl :-
        jmp @or
@add:   jsr taint
        ldx _back
        jsr code_ptr
@or:    ldx z_v
        lda _bar_val,x
        ldx z_ly
        and demon_mask,x
        ldy z_ly
        ora (p_dst),y
        sta (p_dst),y
@done:  rts

; note cell z_c2 of the current row, with A to go back there
note_cell:
        pha
        ldx _back
        ldy cl_n,x
        lda z_rol
        clc
        adc z_c2
        sta (p_cll),y
        lda z_roh
        adc #0
        sta (p_clh),y
        pla
        sta (p_clc),y
        inc cl_n,x
        rts

; cell_get: the character of cell (z_row, z_col) in the back buffer, for
; drawing into: p_dst points at its 8 bytes. A cell nobody has claimed yet in
; this picture is handed a fresh character (z_fresh = 1), which the caller
; must write whole. A cell showing one of the fixed characters - the
; cannon, the ground - is handed a copy of it to draw into (z_fresh = 0),
; and gets its own back with the next picture drawn into this buffer.
; Carry set if no characters are left.
cell_get:
        ldx z_row
        lda row_lo,x
        clc
        adc z_col
        sta p_scr
        sta z_t                 ; low byte of the cell offset
        lda row_hi,x
        adc #0
        sta z_line              ; high byte of the cell offset
        ldx _back
        adc scr_hi,x
        sta p_scr+1
        ldy #0
        sty z_fresh
        lda (p_scr),y
        beq @new
        cmp #DEMON_CODE
        bcs @have               ; a demon's or handed out: add to it
        ; a fixed character: copy it
        sta z_old
        lda next_code
        beq @none
        sta (p_scr),y
        inc next_code
        jsr remember
        lda z_old
        tay
        lda code_lo,y
        sta p_tmp
        lda code_hi,y
        clc
        adc font_hi,x
        sta p_tmp+1
        lda z_new
        jsr code_ptr
        ldy #7
:       lda (p_tmp),y
        sta (p_dst),y
        dey
        bpl :-
        clc
        rts
@new:   sta z_old               ; 0 goes back there
        lda next_code
        beq @none
        sta (p_scr),y
        inc next_code
        jsr remember
        inc z_fresh
        lda z_new
        jmp @own
@have:  jsr taint
@own:   jsr code_ptr
        clc
        rts
@none:  sec
        rts

; the code just handed out (A) for cell z_t/z_line, and what goes back there
remember:
        sta z_new
        ldy cl_n,x
        lda z_t
        sta (p_cll),y
        lda z_line
        sta (p_clh),y
        lda z_old
        sta (p_clc),y
        inc cl_n,x
        rts

; p_dst = character A of the back buffer
code_ptr:
        tay
        lda code_lo,y
        sta p_dst
        lda code_hi,y
        clc
        adc font_hi,x
        sta p_dst+1
        rts

; r_demon: a whole demon - both halves side by side, the same picture - from
; a picture built at start-up (C's demon_img): five columns of eight lines,
; each after eight zero bytes. The mask is the demons' own: line 0 of a
; character %11, odd lines %01, even ones %10 - see band_colours() in
; kernel.s for why.
;
; Each of the three demon slots has ten characters of its own - column by
; column, the character row above and then the one below - and keeps its
; cells from one picture of this buffer to the next. Those ten characters
; are 80 bytes in a row, and the picture is laid out the same way: column c
; of it is its 16 bytes from 16c + 8 - ly on, ly being the demon's first
; line within its character row. So drawing a demon is copying 80 bytes -
; or only the 40 with pixels, when ly is what it was last time and the
; zeros around them are already there.
;
; Where two demons meet in one character row, the cell belongs to the one
; drawn first (the lower slot number); the other adds itself to its
; character.
;   o_slot the slot, 0..2
;   o_src  the picture, for the demon's frame and its pixel's lowest 2 bits
;   o_d0   display line of the demon's top line
;   o_x    its pixel
_r_demon:
        bit _nodraw             ; only working out collisions: nothing to draw
        bpl :+
        rts
:
        lda _o_x
        lsr a
        lsr a
        sta z_cx
        lda #4
        sta z_nc
        lda _o_x
        and #3
        beq :+
        inc z_nc
:       lda _o_d0
        and #7
        sta z_ly
        lda _o_d0
        lsr a
        lsr a
        lsr a
        sta z_row0
        ldx #1                  ; character rows: 2 unless the demon starts
        lda z_ly                ; right on a row
        beq :+
        inx
:       stx z_nrows
        jsr slot_setup
        ; other cells than last time in this buffer: the old ones go
        ldx z_si
        lda z_row0
        cmp ds_row,x
        bne @moved
        lda z_cx
        cmp ds_cx,x
        bne @moved
        lda z_nrows
        cmp ds_rows,x
        bne @moved
        lda z_nc
        cmp ds_nc,x
        beq @cells
@moved: jsr slot_clear
        ldx z_si
        lda z_row0
        sta ds_row,x
        lda z_cx
        sta ds_cx,x
        lda z_nrows
        sta ds_rows,x
        lda z_nc
        sta ds_nc,x

@cells: ; claim the cells, noting those an earlier demon has
        lda #0
        sta z_conf              ; bit c: column c's upper cell is shared
        sta z_confl             ; the same for the lower cells
        lda z_row0
        sta z_row
        jsr slot_row
        lda z_nrows
        cmp #2
        bcc @chars
        inc z_row
        lda z_conf
        sta z_confl
        lda #0
        sta z_conf
        jsr slot_row
        lda z_conf              ; z_conf upper, z_confl lower
        ldx z_confl
        sta z_confl
        stx z_conf

@chars: ; the slot's 80 bytes: p_dst
        lda z_code0
        ldx _back
        jsr code_ptr
        ldx z_si
        lda z_ly
        cmp ds_ly,x
        jeq @data
        ldy ds_ly,x
        sta ds_ly,x
        cpy #8
        bcs @full               ; unknown, or somebody drew into them
        ; the characters hold nothing but the demon at line old: clear the
        ; old lines the new ones do not cover, then write the new ones
        sty z_t
        cmp z_t
        bcc @up
        sec                     ; down: old .. min(ly, old + 8)
        sbc z_t
        cmp #8
        bcc :+
        lda #8
:       sta z_k
        lda z_t
        sta z_end
        jmp @clr
@up:    adc #8                  ; up: max(ly + 8, old) .. old + 8
        cmp z_t                 ; (carry is clear)
        bcs :+
        lda z_t
:       sta z_end
        lda z_t
        clc
        adc #8
        sec
        sbc z_end
        sta z_k
@clr:   ldy z_end               ; in each of the five columns
@cc:    ldx z_k
        lda #0
:       sta (p_dst),y
        iny
        dex
        bne :-
        tya
        sec
        sbc z_k
        clc
        adc #16
        tay
        cpy #80
        bcc @cc
        jmp @data
@full:  ; everything: source from o_src + 8 - ly
        lda _o_src
        clc
        adc #8
        sta p_col
        lda _o_src+1
        adc #0
        sta p_col+1
        lda p_col
        sec
        sbc z_ly
        sta p_col
        bcs :+
        dec p_col+1
:       ldy #0
@all:   .repeat 8, L
        lda (p_col),y
        .if L = 0
        .else
        .if L & 1
        and #$55
        .else
        and #$AA
        .endif
        .endif
        sta (p_dst),y
        iny
        .endrepeat
        cpy #80
        jne @all
        jmp @shared
@data:  ; only the eight lines of each column, at 16c + ly
        lda _o_src
        clc
        adc #8
        sta p_col
        lda _o_src+1
        adc #0
        sta p_col+1
        lda p_dst
        clc
        adc z_ly
        sta p_dst
        bcc :+
        inc p_dst+1
:       ldx z_ly                ; the mask for the line each byte lands on
        lda demon_mask,x
        sta @m0+1
        lda demon_mask+1,x
        sta @m1+1
        lda demon_mask+2,x
        sta @m2+1
        lda demon_mask+3,x
        sta @m3+1
        lda demon_mask+4,x
        sta @m4+1
        lda demon_mask+5,x
        sta @m5+1
        lda demon_mask+6,x
        sta @m6+1
        lda demon_mask+7,x
        sta @m7+1
        ldy #0
@dcol:  lda (p_col),y
@m0:    and #$FF
        sta (p_dst),y
        iny
        lda (p_col),y
@m1:    and #$FF
        sta (p_dst),y
        iny
        lda (p_col),y
@m2:    and #$FF
        sta (p_dst),y
        iny
        lda (p_col),y
@m3:    and #$FF
        sta (p_dst),y
        iny
        lda (p_col),y
@m4:    and #$FF
        sta (p_dst),y
        iny
        lda (p_col),y
@m5:    and #$FF
        sta (p_dst),y
        iny
        lda (p_col),y
@m6:    and #$FF
        sta (p_dst),y
        iny
        lda (p_col),y
@m7:    and #$FF
        sta (p_dst),y
        tya
        clc
        adc #9                  ; to the next column, 16 on
        tay
        cpy #80
        bcc @dcol

@shared:
        ; cells an earlier demon holds: add this one's pieces to its
        ; characters
        lda z_conf
        ora z_confl
        bne :+
        rts
:       lda #0
        sta z_c
@sc:    lda z_cx
        clc
        adc z_c
        cmp #40
        bcc :+
        sbc #40
:       sta z_col
        ldx z_c
        lda _o_src              ; this column's source: o_src + 16c + 8
        clc
        adc col16p8,x
        sta z_srcl
        lda _o_src+1
        adc #0
        sta z_srch
        lda z_conf
        and col_bit,x
        beq @sclo
        lda z_row0
        jsr shared_cell
        lda z_srcl
        sec
        sbc z_ly
        sta p_col
        lda z_srch
        sbc #0
        sta p_col+1
        ldy z_ly
        jsr demon_or_from
@sclo:  ldx z_c
        lda z_confl
        and col_bit,x
        beq @scn
        lda z_row0
        clc
        adc #1
        jsr shared_cell
        lda z_srcl
        clc
        adc #8
        sta p_col
        lda z_srch
        adc #0
        sta p_col+1
        lda p_col
        sec
        sbc z_ly
        sta p_col
        bcs :+
        dec p_col+1
:       lda z_ly
        sta z_end
        ldy #0
        jsr demon_or_to
@scn:   inc z_c
        lda z_c
        cmp z_nc
        bcc @sc
        rts

; the character in cell (row A, column z_col): p_dst
shared_cell:
        tax
        lda row_lo,x
        clc
        adc z_col
        sta p_scr
        lda row_hi,x
        adc #0
        ldx _back
        adc scr_hi,x
        sta p_scr+1
        ldy #0
        lda (p_scr),y
        jsr taint
        jmp code_ptr

; taint: A is the code of a cell somebody adds a figure to. If it is one of
; a demon slot's characters, that character now holds more than the demon:
; the slot must write all of it next time in this buffer, not only the
; demon's lines. Keeps A and X.
taint:  cmp #FIRSTDYN
        bcs @r
        sta z_tn
        stx z_tx
        tay
        ldx slot_of-DEMON_CODE,y
        lda _back
        beq :+
        inx
        inx
        inx
:       lda #$FF
        sta ds_ly,x
        ldx z_tx
        lda z_tn
@r:     rts

slot_of:    .res 10, 0
            .res 10, 1
            .res 10, 2

; claim the slot's cells in row z_row, columns z_cx.. (z_nc of them); an
; earlier demon's cell sets bit c of z_conf instead
slot_row:
        ldx z_row
        lda row_lo,x
        sta p_scr
        lda row_hi,x
        ldx _back
        clc
        adc scr_hi,x
        sta p_scr+1
        lda z_row
        sec
        sbc z_row0              ; 0 upper, 1 lower
        clc
        adc z_code0
        sta z_own
        ldx #0                  ; column
        ldy z_cx
@c:     lda (p_scr),y
        cmp z_own
        beq @next               ; already ours
        cmp #DEMON_CODE
        bcc @claim
        cmp z_code0
        bcs @claim              ; ours (another) or a later demon's: ours now
        lda col_bit,x           ; an earlier demon's: share
        ora z_conf
        sta z_conf
        jmp @next
@claim: lda z_own
        sta (p_scr),y
@next:  inc z_own
        inc z_own
        iny
        cpy #40
        bcc :+
        ldy #0
:       inx
        cpx z_nc
        bcc @c
        rts

; r_demon_off: slot o_slot shows no demon of its own this picture
_r_demon_off:
        bit _nodraw             ; only working out collisions: nothing to draw
        bpl :+
        rts
:
        jsr slot_setup
        jsr slot_clear
        ldx z_si
        lda #0
        sta ds_rows,x
        lda #$FF
        sta ds_ly,x
        rts

; z_si = the slot's entry for this buffer, z_code0 its first character
slot_setup:
        lda _back
        beq :+
        lda #3
:       clc
        adc _o_slot
        sta z_si
        lda _o_slot
        asl a
        asl a
        adc _o_slot
        asl a                   ; slot * 10
        adc #DEMON_CODE
        sta z_code0
        adc #10
        sta z_codeend
        rts

; the cells the slot used last time go back to blank - those that still
; show one of its characters
slot_clear:
        ldx z_si
        lda ds_rows,x
        beq @done
        sta z_k
        lda ds_row,x
        sta z_row
@row:   ldx z_row
        lda row_lo,x
        sta p_scr
        lda row_hi,x
        ldx _back
        clc
        adc scr_hi,x
        sta p_scr+1
        ldx z_si
        lda ds_nc,x
        sta z_t
        lda ds_cx,x
        tay
        ldx z_t
@c:     lda (p_scr),y
        cmp z_code0
        bcc @skip
        cmp z_codeend
        bcs @skip
        lda #0
        sta (p_scr),y
@skip:  iny
        cpy #40
        bcc :+
        ldy #0
:       dex
        bne @c
        inc z_row
        dec z_k
        bne @row
@done:  rts

        .bss
ds_row:     .res 6              ; per buffer and slot: the cells last used
ds_cx:      .res 6
ds_rows:    .res 6              ; 0: none
ds_nc:      .res 6
ds_ly:      .res 6              ; the layout of the slot's characters
_o_slot:    .res 1
z_tn:       .res 1
z_tx:       .res 1
        .code

; a claimed character: add lines y..7 (demon_or_from) or y..z_end-1
demon_or_from:
        lda #8
        sta z_end
demon_or_to:
@l:     lda (p_col),y
        and demon_mask,y
        ora (p_dst),y
        sta (p_dst),y
        iny
        cpy z_end
        bne @l
        rts

; r_cannon: the cannon, in fixed characters (CANNON_CODE..+5) that are
; only rewritten when it has moved since this buffer last showed it - it
; stands still most of the time. Figures that pass over it draw into copies
; (see cell_get).
;   o_x   its pixel, or $FF for no cannon
;   o_src its six characters for that pixel: column 0 row 21, column 0 row
;         22, column 1 row 21, ... 48 bytes

_r_cannon:
        bit _nodraw             ; only working out collisions: nothing to draw
        bpl :+
        rts
:
        ldx _back
        lda _o_x
        cmp can_x,x
        beq @done
        ; take the old one off
        lda can_x,x
        cmp #$FF
        beq @put
        lsr a
        lsr a
        jsr can_cells
        lda #0
        ldy #0
        sta (p_scr),y
        sta (p_dst),y
        iny
        sta (p_scr),y
        sta (p_dst),y
        iny
        sta (p_scr),y
        sta (p_dst),y
@put:   ldx _back
        lda _o_x
        sta can_x,x
        cmp #$FF
        beq @done
        lsr a
        lsr a
        jsr can_cells
        ldy #0
        lda #CANNON_CODE
        sta (p_scr),y
        lda #CANNON_CODE+1
        sta (p_dst),y
        iny
        lda #CANNON_CODE+2
        sta (p_scr),y
        lda #CANNON_CODE+3
        sta (p_dst),y
        iny
        lda #CANNON_CODE+4
        sta (p_scr),y
        lda #CANNON_CODE+5
        sta (p_dst),y
        ; and the characters
        ldx _back
        lda font_hi,x
        clc
        adc #>(CANNON_CODE*8)
        sta p_tmp+1
        lda #<(CANNON_CODE*8)
        sta p_tmp
        ldy #47
:       lda (_o_src),y
        sta (p_tmp),y
        dey
        bpl :-
@done:  rts

; p_scr / p_dst: the code matrix at column A of rows 21 and 22
can_cells:
        clc
        adc #<(21*40)
        sta p_scr
        lda #>(21*40)
        adc scr_hi,x
        sta p_scr+1
        lda p_scr
        clc
        adc #40
        sta p_dst
        lda p_scr+1
        adc #0
        sta p_dst+1
        rts

        .bss
can_x:      .res 2              ; where each buffer shows the cannon
        .code

; r_attr: give a run of colour cells of the back buffer a colour for this
; picture, and remember what goes back there: a_val into a_n cells from
; column a_col of row a_row, not past the end of the row. What goes back is
; r_row_attr[row].
_r_attr:
        bit _nodraw             ; only working out collisions: nothing to draw
        bpl :+
        rts
:
        ldy _a_row
        lda row_lo,y
        clc
        adc _a_col
        sta p_scr
        sta z_k
        lda row_hi,y
        adc #0
        sta z_line
        ldx _back
        adc att_hi,x
        sta p_scr+1
        lda _a_col                ; clip at the end of the row
        clc
        adc _a_n
        cmp #41
        bcc :+
        lda #40
        sec
        sbc _a_col
        sta _a_n
:       lda _a_n
        beq @full
        lda ar_n,x
        cmp #AR_MAX
        bcs @full
        clc
        adc ar_base,x
        tay
        lda z_k
        sta ar_lo,y
        lda z_line
        sta ar_hi,y
        lda _a_n
        sta ar_cnt,y
        ldx _a_row
        lda _r_row_attr,x
        sta ar_val,y
        ldx _back
        inc ar_n,x
        ldy _a_n
        dey
        lda _a_val
:       sta (p_scr),y
        dey
        bpl :-
@full:  rts

; r_score: the six digits of the score line into the back buffer's own
; characters for it (SCORE_CODE onwards, 13 cells in each of rows 0 and 1).
; o_src points at the digit shapes ($1F00 of the original), score_off holds
; the six offsets into them. The digits stand at multicolour pixels 55, 63,
; ... 95 - the 2600's 48-pixel score - so each is shifted by 3 and spills
; into the cell of the next one.

_r_score:
        ldx _back
        lda font_hi,x
        sta p_dst+1
        lda #<(SCORE_CODE*8)
        sta p_dst
        lda p_dst+1
        clc
        adc #>(SCORE_CODE*8)
        sta p_dst+1
        ; clear the 26 characters
        lda #0
        ldy #26*8-1
@clr:   sta (p_dst),y
        dey
        cpy #$FF
        bne @clr
        ; the three shift tables for sub 3
        lda #(>sh_tab)+9
        sta p_scr+1
        lda #(>sh_tab)+10
        sta p_tmp+1
        lda #(>sh_tab)+11
        sta p_col+1
        lda #0
        sta p_scr
        sta p_tmp
        sta p_col
        sta z_c                 ; digit 0..5
@digit: ldx z_c
        lda _score_off,x
        sta z_i                 ; offset of this digit's shape
        lda #8
        sta z_line              ; shape row 8 is the top line
@row:   lda z_i
        clc
        adc z_line
        tay
        lda (_o_src),y
        beq @nextrow
        sta z_t
        ; display line 13 - row: cell row 0 for lines 5..7, 1 for 8..13
        lda #13
        sec
        sbc z_line
        cmp #8
        bcc :+
        ; row 1: codes 13 further on, line - 8
        sbc #8
        ldx #13
        stx z_k
        jmp :++
:       ldx #0
        stx z_k
:       sta z_ly                ; line within the character
        ; cell of the first byte: column 13 + 2*digit -> code index 2*digit
        lda z_c
        asl a
        clc
        adc z_k
        sta z_k                 ; index of the first of three characters
        ldy z_t
        lda (p_scr),y
        and #$55
        jsr score_or
        inc z_k
        ldy z_t
        lda (p_tmp),y
        and #$55
        jsr score_or
        inc z_k
        ldy z_t
        lda (p_col),y
        and #$55
        jsr score_or
@nextrow:
        dec z_line
        bpl @row
        inc z_c
        lda z_c
        cmp #6
        bne @digit
        rts

; OR A into line z_ly of score character z_k
score_or:
        sta z_end
        lda z_k
        asl a
        asl a
        asl a
        clc
        adc z_ly
        tay
        lda z_end
        ora (p_dst),y
        sta (p_dst),y
        rts

        .bss
_chargen:   .res 64*8           ; eng_chargen
_r_row_attr: .res 25            ; the colour each row goes back to
_a_val:     .res 1
_a_col:     .res 1
_a_row:     .res 1
_a_n:       .res 1
_score_off: .res 6

        .code
; Addresses in the back buffer, for the C side: A = back buffer index.
_r_font_ptr:
        tax
        lda font_hi,x
        tax
        lda #0
        rts
_r_scr_ptr:
        tax
        lda scr_hi,x
        tax
        lda #0
        rts
_r_att_ptr:
        tax
        lda att_hi,x
        tax
        lda #0
        rts
