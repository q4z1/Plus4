; ---------------------------------------------------------------------------
; engine.s - the Plus/4 end of Paradroid
;
; What has to be fast or on time lives here:
;
;   1. The raster interrupt, four stops a picture:
;        line 44   in the panel's last row: the border's colour
;        line 50   the gap rows under it, from their first line: the
;                  deck's character set, multicolour, 38 columns, x fine
;                  scroll
;        line 71   at the gap's last line the y fine scroll (see below),
;                  then the window's colour and character set
;        line 197  below the window: a finished picture is swapped in, the
;                  panel's settings for the top of the next one, the
;                  keyboard, the clock
;
;   2. The deck window. 39 x 17 cells, built from the deck's block map
;      (64 x 16 blocks of 4 x 4 characters) whenever the window has moved
;      by a whole character; otherwise only the cells figures used are put
;      back.
;
;   3. Figures. The deck is hires characters. A cell a figure covers gets a
;      character of its own from a pool, with a copy of the deck character
;      in it turned into multicolour, and is switched to multicolour in its
;      colour cell; the figure goes in through a mask. Its pixels are %01
;      and %10, the two colours all multicolour cells share.
;
; Fine scroll: the TED reads its vertical scroll register once per picture,
; so it cannot be changed under the panel. What can be changed is its line
; counter ($FF1D), which decides when it fetches the next row, and its row
; line counter (bits 0-2 of $FF1F), which decides which line of the
; characters it shows. Both set back together at the start of the last
; line of the gap row move everything below down, rows intact: by s-1
; lines when the line counter goes back by s and the row line counter is
; set to 7-s (found by trying, see the README). Below the window the line
; counter is put right again, so the picture ends where it always does.
; The window's rows start a row above it, in the gap's last row (screen
; row 8, window row 0). The TED shows that row twice: first in the gap,
; where the gap's character set is the other picture's, in which its
; characters are blank (they are copies in codes of their own, kept blank
; there: CUT_R0); then, after the counters were set back, its last s+1
; lines again, now in the window's colour and set: the window's first
; lines, cut by its top as the original's. Both the colour and the set
; change in the line the counters are set back in, after its visible part.
; ---------------------------------------------------------------------------

        .setcpu "6502"
        .macpack longbranch

        .include "game.inc"
        .include "data.inc"

        .export _eng_init, _eng_show, _eng_plain, _eng_dirty
        .export _r_begin, _r_fig, _r_done
        .export _frames, _ready, _back
        .export _e_m0, _e_sx, _e_r, _e_blank7, _e_cutrow, _e_cutn, _e_s
        .export _f_col, _f_row, _f_line, _f_h, _pre_shift
        .exportzp _f_src, _f_pre, _p_pre
        .export _col_deck, _col_panel, _col_fig1, _col_fig2, _col_border
        .export _blk_set, _bs_x, _bs_y, _bs_v
        .export _panel_put, _pp_off, _pp_code, _pp_attr
        .export _keys_irq, _eng_keys, _dbg_keys, _pause_keys
        .export _pool_left, _eng_stack, _font_hi, _f_tint, _panel_hi, _win_mc
        .export _gap_eor
        .export _mus_hook
        .import sfx_frame               ; sfx.s
        .importzp sp

; ---- TED ------------------------------------------------------------------

TED_SCROLLY = $FF06
TED_CTRL2   = $FF07
TED_KEYS    = $FF08
TED_IRQ     = $FF09
TED_IRQEN   = $FF0A
TED_RCMP    = $FF0B
TED_V1LO    = $FF0E
TED_V2LO    = $FF0F
TED_V2HI    = $FF10
TED_SOUND   = $FF11
TED_BMBASE  = $FF12
TED_CHBASE  = $FF13
TED_VMBASE  = $FF14
TED_BG      = $FF15
TED_COL1    = $FF16
TED_COL2    = $FF17
TED_BORDER  = $FF19
TED_LINE    = $FF1D
TED_HPOS    = $FF1E
TED_RC      = $FF1F
KEY_ROW     = $FD30

; ---- memory ---------------------------------------------------------------
;
; Each picture is a colour matrix and a code matrix (2 KB), followed by its
; character set.

WROW0       = 8                 ; first window row on screen (rows 6-8 the
WROWS       = 17                ; gap; the window's from the gap's last row on)
WCOLS       = 39

LINE_GAP    = 44                ; interrupt lines, see the top
LINE_RC     = 50                ; (the panel ends with line 51)
LINE_SCROLL = 71                ; two lines before the gap's last, 74
GAP_LAST    = 74
LINE_BOTTOM = 197               ; less s, the line counter is behind then
LINE_VBL    = 252               ; in the vertical blank: the panel's set-up

; ---- zero page ------------------------------------------------------------

        .segment "ENGZP": zeropage
c_i:        .res 1              ; choose: the droid
c_bx:       .res 1              ; its character, its ways, its speed
c_by:       .res 1
c_last:     .res 1
c_cx:       .res 3              ; the ways found
c_cy:       .res 3
_f_src:     .res 2              ; pre_shift: 4 bytes per line, top line first
_f_pre:     .res 2              ; r_fig: the pre-shifted copy
_p_pre:     .res 2              ; pre_shift: where to
p_shr:      .res 2              ; pre_shift: the bits to shift, the spill
p_shl:      .res 2
p_d:        .res 2              ; column data, biased to the cell
p_n:        .res 2              ; column mask, biased likewise
p_dst:      .res 2              ; character being drawn into
p_src:      .res 2
p_scr:      .res 2              ; code matrix row / cell
p_att:      .res 2              ; colour matrix row / cell
p_a:        .res 2
p_b:        .res 2
z_t:        .res 1
z_t2:       .res 1
z_si:       .res 1
z_lr:       .res 1
z_rbit:     .res 1
z_ly0:      .res 1
z_row:      .res 1
z_col:      .res 1
z_c:        .res 1
z_fp:       .res 1
z_i:        .res 1
z_cnt:      .res 1
z_bx:       .res 1
z_k:        .res 1
z_sub:      .res 1
z_mrow:     .res 1
z_scrhi:    .res 1              ; back buffer: high bytes of codes,
z_atthi:    .res 1              ;   colours
z_fonthi:   .res 1              ;   and characters
z_acc:      .res 5              ; pixels seen per column in this cell row
z_ncol:     .res 1              ; columns a figure line spreads over
z_lim:      .res 1              ; first code figures may not use
z_tag:      .res 1              ; picture serial, for the cut row
z_pc:       .res 1

; ---- ordinary memory ------------------------------------------------------

        .bss
_frames:    .res 1              ; pictures shown, 50 a second
_back:      .res 1              ; the picture being drawn: 0 or 1
_f_tint:    .res 1              ; r_fig: the cells' colour, or 0 for the deck's
_ready:     .res 1              ; set when it is complete; the IRQ shows it
front:      .res 1
phase:      .res 1
_pool_left: .res 1

; how the window maps onto the deck; set by the game before r_begin
_e_m0:      .res 1              ; deck column at window column 0 (0..255)
_e_sx:      .res 1              ; x fine scroll, 0..7
_e_r:       .res 1              ; deck row at window row 0 (signed)
_e_blank7:  .res 1              ; window row 0 is above the window: blank
_e_cutrow:  .res 1              ; 0 none, else window row + 1 to cut
_e_cutn:    .res 1              ; lines to clear at its top
_e_s:       .res 1              ; line counter set back by this in the gap

; per picture
b_valid:    .res 2              ; built at all
b_m0:       .res 2              ; the mapping it was built for
b_r:        .res 2
b_blank7:   .res 2
b_cut:      .res 2              ; window row + 1 it cut, 0 none
b_sx:       .res 2              ; what the interrupt sets for it
b_s:        .res 2              ; the line counter's set-back: s's even part
b_yo:       .res 2              ; the window's y scroll: 3 + s's odd part
b_rcv:      .res 2

; colours
_col_deck:   .res 1             ; the window's background
_col_panel:  .res 1             ; the panel's background
_col_fig1:   .res 1             ; figures: %01
_col_fig2:   .res 1             ;          %10
_col_border: .res 1

; figure
_f_col:     .res 1              ; window column of its left cell (signed)
_f_row:     .res 1              ; window row of its top cell (signed)
_f_line:    .res 1              ; line in that cell, 0..7
_f_h:       .res 1              ; pre_shift: lines, up to 20

; block changes still to be shown in a picture
NPEND = 16
pend_x:     .res NPEND
pend_y:     .res NPEND
pend_m:     .res NPEND          ; bit 0: picture 0 still to do, bit 1: 1

_pp_off:    .res 2
_pp_code:   .res 1
_pp_attr:   .res 1

; keys
_keys_irq:  .res 1
keys_hit:   .res 1
_dbg_keys:  .res 1
kprev:      .res 1

_mus_hook:  .res 2              ; music once a picture (the title's: music.s)

next_code:  .res 1
cl_n:       .res 2
POOL_N      = 256 - POOL
        .segment "LOWBSS"
_bs_x:      .res 1              ; (these written before they are read:
_bs_y:      .res 1              ; LOWBSS is not cleared)
_bs_v:      .res 1
kj:         .res 1              ; the keys' reading
kr:         .res 1
CL_N = POOL_N + WCOLS           ; the cut row notes a cell per copy use
cl_col0:    .res CL_N           ; cells handed a character, picture 0
cl_row0:    .res CL_N
cl_col1:    .res CL_N
cl_row1:    .res CL_N
        .bss

; the cut row: which codes have a cut copy in this picture
cut_tag:    .res 256
cut_code:   .res 256

        .segment "TABLES"
        .align 256
nmaskof:    .res 256            ; %11 for every pixel that is %00, else %00
code_lo:    .res 256            ; code * 8
code_hi:    .res 256
ident:      .res 256            ; the byte itself

        .data
; the window's character set per picture; the briefing puts the panel's there
_font_hi:
font_hi:    .byte >FONT0, >FONT1
; the panel rows' character set: the panel's, or a picture over the whole
; screen's (the title's logo)
_panel_hi:  .byte >PANELF
; the window's multicolour bit: off for pages of hires text only, whose
; colours can then be any of the TED's (in multicolour mode a colour of 8
; or more makes a cell multicolour)
_win_mc:    .byte $10
; the gap's character set against the window's: the other picture's
; (FONT0 ^ FONT1), or the same for a picture over the whole screen (the
; logo); eng_plain() sets it back
_gap_eor:   .byte >(FONT0 ^ FONT1)

        .rodata
rowc_lo:    .repeat WROWS, R    ; window rows in the code matrix
            .byte <((WROW0+R)*40)
            .endrepeat
rowc_hi:    .repeat WROWS, R
            .byte >((WROW0+R)*40)
            .endrepeat
scr_hi:     .byte >SCR0C, >SCR1C
att_hi:     .byte >SCR0A, >SCR1A
cl_lo_c:    .byte <cl_col0, <cl_col1
cl_hi_c:    .byte >cl_col0, >cl_col1
cl_lo_r:    .byte <cl_row0, <cl_row1
cl_hi_r:    .byte >cl_row0, >cl_row1

        .code

; ===========================================================================
; Start-up
; ===========================================================================

; eng_stack: cc65's stack to $FC00-$FCFF. Called first thing in main().
_eng_stack:
        lda #<$FD00
        sta sp
        lda #>$FD00
        sta sp+1
        rts

        .segment "INITCODE"     ; once at the start, then overwritten
_eng_init:
        sei
        sta $FF3F               ; RAM everywhere
        ldx #0
        ; the mask: %11 for each pixel pair that is %00
@sh:    stx z_t
        lda #0
        sta z_t2
        ldy #4
@px:    asl z_t2
        asl z_t2
        lda z_t
        and #$C0
        bne :+
        lda z_t2
        ora #3
        sta z_t2
:       asl z_t
        asl z_t
        dey
        bne @px
        lda z_t2
        sta nmaskof,x
        ; code * 8
        txa
        asl a
        asl a
        asl a
        sta code_lo,x
        txa
        sta ident,x
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        sta code_hi,x
        inx
        bne @sh
        lda #0
        sta _ready
        sta front
        sta b_valid
        sta b_valid+1
        sta cl_n
        sta cl_n+1
        sta _dbg_keys
        sta keys_hit
        sta z_tag
        ldx #NPEND-1
:       sta pend_m,x
        dex
        bpl :-
        lda #1
        sta _back
        lda #1                  ; no shift
        jsr _eng_roll
        lda #6
        sta b_rcv
        sta b_rcv+1

        lda #<irq
        sta $FFFE
        lda #>irq
        sta $FFFF
        lda #<nmi
        sta $FFFA
        lda #>nmi
        sta $FFFB
        cli
        rts

        .code

nmi:    rti

; eng_show: the TED set up for the game and the interrupt running; the
; picture still off (only the border shows, as from the program's start):
; the title switches it on when its first screen is whole.
_eng_show:
        sei
        lda TED_BMBASE
        and #$FB                ; characters from RAM
        sta TED_BMBASE
        ldx front
        lda att_hi,x
        sta TED_VMBASE
        jsr panel_regs
        lda #0
        sta phase
        lda #LINE_GAP
        sta TED_RCMP
        lda #$02                ; raster interrupt, compare bit 8 = 0
        sta TED_IRQEN
        lda TED_IRQ
        sta TED_IRQ
        lda #$0B                ; text, display off, 25 rows, y scroll 3
        sta TED_SCROLLY
        cli
        rts

; eng_plain: both pictures unscrolled and to be built afresh - for
; screens drawn straight into the window, like the transfer game's
_eng_plain:
        ldx #1
:       lda #0
        sta b_sx,x
        sta b_cut,x
        sta b_valid,x
        sta cl_n,x
        jsr set_s               ; (s = 0)
        dex
        bpl :-
        lda #>(FONT0 ^ FONT1)
        sta _gap_eor
        ldx #WCOLS              ; the window's top row blank: unscrolled,
        lda #0                  ; its last line is the window's first
:       sta SCR0C + WROW0 * 40,x
        sta SCR1C + WROW0 * 40,x
        dex
        bpl :-
        rts

; eng_dirty: both pictures to be built afresh, for new colours
_eng_dirty:
        lda #0
        sta b_valid
        sta b_valid+1
        rts

; ===========================================================================
; The raster interrupt
; ===========================================================================

irq:    pha
        txa
        pha
        tya
        pha
        lda TED_IRQ
        sta TED_IRQ
        ldx phase
        lda @lo,x
        sta @j+1
        lda @hi,x
        sta @j+2
@j:     jmp $FFFF
@lo:    .byte <irq_gap, <irq_rc, <irq_scroll, <irq_bottom, <irq_vbl
@hi:    .byte >irq_gap, >irq_rc, >irq_scroll, >irq_bottom, >irq_vbl

; Under the panel: the deck's background. The panel's last row is all
; foreground, so it can change anywhere in it. The gap row under it is the
; deck's colour too; a different colour there would have to change exactly
; at the window's first line, and on the TED a write that exact cannot be
; timed reliably (see the README).
irq_gap:
        lda #47
:       cmp TED_LINE
        bcs :-
        lda _col_border
        cmp _col_panel          ; only if it changes: the TED shows a pixel
        beq :+                  ; of colour $7F where a colour register is
        sta TED_BG              ; written (the real one, and plus4emu) -
:       lda #1                  ; "snow" at the logo's top left, all grey
        sta phase
        lda #LINE_RC
        sta TED_RCMP
        jmp irq_out

; The gap rows: the deck's character set and modes (nothing shows in them,
; their cells are blank in it); then irq_scroll.
irq_rc:
        ; from the gap's first line, 52. The gap's cells are blank in the
        ; deck's characters, not in the panel's: set at line 55 as it was,
        ; the switch came a little late now and then, and the gap showed
        ; a line of the panel's characters in its first cells.
        lda #51
:       cmp TED_LINE
        bcs :-
        ldy front
        lda font_hi,y           ; the other picture's set ($C8 <-> $D8):
        eor _gap_eor            ; the top row's copies are blank in it
        sta TED_CHBASE
        lda b_sx,y
        ora #$80                ; 256 characters, 38 columns,
        ora _win_mc             ; multicolour unless a page is all hires
        sta TED_CTRL2
        lda _col_fig1
        sta TED_COL1
        lda _col_fig2
        sta TED_COL2
        lda #2
        sta phase
        lda #LINE_SCROLL
        sta TED_RCMP
        jmp irq_out

; At the start of line GAP_LAST, the gap's last: line counter and row line
; counter set back; then, in the rest of that line, the window's colour and
; character set, from the next line on.
irq_scroll:
        ldy front
        ; the y scroll for the window (set_s), now, in line 71 or 72: a
        ; line whose counter agrees with it in its last three bits would
        ; fetch a row at once (71, 72, 73: 7, 0, 1; the window's 3 or 4)
        lda TED_SCROLLY
        and #$F8
        ora b_yo,y
        sta TED_SCROLLY
        ; the next interrupt's line first: the line counter is set back
        ; below, to 74 - s, and set to this interrupt's line (71, for s =
        ; 3) the TED raises it again at once (Yape does, as the real chip;
        ; VICE does not). That ran the rest of the picture's interrupts
        ; one late, and the next panel was drawn on the gap's colour: it
        ; flickered, every eighth line of scrolling.
        lda #3
        sta phase
        lda #LINE_BOTTOM
        sec
        sbc b_s,y
        sta TED_RCMP
        ; in step with the line before, written in its right part (the
        ; gap's colour again: the counters below are set at the same point
        ; of the next line each time, as they were when the window's colour
        ; was written here)
        ldx #GAP_LAST - 1
:       cpx TED_LINE
        beq @l57
        bcs :-
        bcc @bg                 ; late: at once
@l57:   lda TED_HPOS
        cmp #124
        bcc :+
        cmp #196
        bcc @bg
:       cpx TED_LINE
        beq @l57
@bg:    lda _col_border
        sta TED_BG
        lda #GAP_LAST - 1
:       cmp TED_LINE
        bcs :-
        lda #GAP_LAST
        sec
        sbc b_s,y
        sta TED_LINE
        lda TED_RC
        and #$F8
        ora b_rcv,y
        sta TED_RC
        ; then the window's colour and set, in this line's right part: in
        ; Yape written from $FF1E 108 to 174 it shows from the next line's
        ; start. The counters were set at $FF1E 106 to 122 (measured): the
        ; same line, so on at once, from 136 (from 108, the last pixels of
        ; this line came in the colour now and then). The TED does not stop the
        ; processor in this line, whatever s is: it decided that at the
        ; line's start, before the counters changed.
        ldx _col_deck
:       lda TED_HPOS
        cmp #136
        bcc :-
        stx TED_BG
        lda font_hi,y
        sta TED_CHBASE
        jmp irq_out

; Below the window: the line counter put right again, so the picture ends
; at line 204 as always; and only then the panel's settings.
irq_bottom:
        ldy front
        lda b_s,y
        beq @end
        ; in line 202 (202 - s in counter terms) it is set to 202, so that
        ; the next line starts as 203: the TED ends the picture's fetching
        ; only on a line that starts as 203. Set to 203 within the line,
        ; that line is skipped, the fetching goes on, and the next
        ; picture starts with its row line counter wrong (Yape, as the
        ; real TED; VICE did not mind).
        lda #201
        sec
        sbc b_s,y
:       cmp TED_LINE
        bcs :-
        lda #202
        sta TED_LINE
@end:   lda #203                ; the picture's end, then the panel
:       cmp TED_LINE
        bcs :-
        lda _ready
        beq @same
        lda _back
        sta front
        tax
        lda att_hi,x
        sta TED_VMBASE
        txa
        eor #1
        sta _back
        lda #0
        sta _ready
@same:  inc _frames
        jsr kpoll
        jsr sfx_frame
        lda _mus_hook+1
        beq :+
        jsr mus_go
:       lda #4
        sta phase
        lda #LINE_VBL
        sta TED_RCMP
        jmp irq_out

; In the vertical blank: the panel's registers for the picture's top. Not
; right under the window: VICE draws a pixel of the window's colour into
; the border where a TED register is written there ("snow").
irq_vbl:
        jsr panel_regs
        lda _roll                       ; the static rolling (terminated())
        beq :+
        jsr roll_step
:       lda #0
        sta phase
        lda #LINE_GAP
        sta TED_RCMP
irq_out:
        pla
        tay
        pla
        tax
        pla
        rti

; the panel at the top of the picture
panel_regs:
        lda TED_SCROLLY         ; the y scroll irq_scroll changed (the line
        and #$F8                ; counter is 252 here: 4, no row fetched)
        ora #3
        sta TED_SCROLLY
        lda _panel_hi
        sta TED_CHBASE
        lda #$88                ; 256 characters, hires, 40 columns
        sta TED_CTRL2
        lda _col_panel
        sta TED_BG
        lda _col_border
        sta TED_BORDER
        rts

; ===========================================================================
; The panel: both pictures at once
; ===========================================================================

; panel_put: pp_code and pp_attr at offset pp_off of both pictures
_panel_put:
        lda _pp_off
        sta p_a
        sta p_b
        sta p_scr
        sta p_att
        lda _pp_off+1
        tax
        ora #>SCR0C
        sta p_a+1
        txa
        ora #>SCR1C
        sta p_b+1
        txa
        ora #>SCR0A
        sta p_scr+1
        txa
        ora #>SCR1A
        sta p_att+1
        ldy #0
        lda _pp_code
        sta (p_a),y
        sta (p_b),y
        lda _pp_attr
        sta (p_scr),y
        sta (p_att),y
        rts

; ===========================================================================
; The deck window
; ===========================================================================

; blk_set: block (bs_x, bs_y) of the deck becomes bs_v (block * 4). Both
; pictures show it the next time they are drawn.
_blk_set:
        lda _bs_y
        asl a
        asl a
        asl a
        asl a
        asl a
        asl a
        ora _bs_x
        sta p_a
        lda _bs_y
        lsr a
        lsr a
        ora #>DMAP
        sta p_a+1
        ldy #0
        lda _bs_v
        sta (p_a),y
        ; note it; the same block noted already takes the new state
        ldx #NPEND-1
@f:     lda pend_m,x
        beq @n
        lda pend_x,x
        cmp _bs_x
        bne @n
        lda pend_y,x
        cmp _bs_y
        beq @set
@n:     dex
        bpl @f
        ldx #NPEND-1
@e:     lda pend_m,x
        beq @new
        dex
        bpl @e
        ; no room: both pictures rebuilt from scratch
        lda #0
        sta b_valid
        sta b_valid+1
        rts
@new:   lda _bs_x
        sta pend_x,x
        lda _bs_y
        sta pend_y,x
@set:   lda #3
        sta pend_m,x
        rts

; r_begin: start a picture in the back buffer. If the window still maps
; onto the deck as when this buffer was last drawn, only the cells figures
; used get their deck characters back; else the whole window is rebuilt.
_r_begin:
        ldx _back
        lda scr_hi,x
        sta z_scrhi
        lda att_hi,x
        sta z_atthi
        lda font_hi,x
        sta z_fonthi
        lda b_valid,x
        beq @full
        lda b_m0,x
        cmp _e_m0
        bne @full
        lda b_r,x
        cmp _e_r
        bne @full
        lda b_blank7,x
        cmp _e_blank7
        bne @full
        jsr restore
        jsr uncut
        jsr pending
        jmp @pool
@full:  jsr build
        ldx _back
        lda #1
        sta b_valid,x
        lda _e_m0
        sta b_m0,x
        lda _e_r
        sta b_r,x
        lda _e_blank7
        sta b_blank7,x
        ; the build has every block as it is now
        lda _back
        clc
        adc #1                  ; bit of this picture
        eor #$FF
        sta z_t
        ldx #NPEND-1
:       lda pend_m,x
        and z_t
        sta pend_m,x
        dex
        bpl :-
@pool:  lda #0
        ldx _back
        sta cl_n,x
        lda #POOL
        sta next_code
        lda #CUT_R0             ; (the top row's copies above)
        sta z_lim
        jmp tag_next

; tag_next: a new tag; when they run out the table starts afresh
tag_next:
        inc z_tag
        bne :++
        ldx #0
        txa
:       sta cut_tag,x
        inx
        bne :-
        inc z_tag
:       rts

; ---------------------------------------------------------------------------
; build: the whole window of the back buffer from the deck.

build:  lda #0
        sta z_i
@row:   ldx z_i
        lda rowc_lo,x
        sta p_scr
        sta p_att
        lda rowc_hi,x
        ora z_scrhi
        sta p_scr+1
        lda rowc_hi,x
        ora z_atthi
        sta p_att+1
        jsr row_build
        inc z_i
        lda z_i
        cmp #WROWS
        bne @row
        rts

; row_build: window row z_i into (p_scr), (p_att)
.proc row_build
        lda z_i
        bne notop
        lda _e_blank7
        bne blank
notop:  lda _e_r
        clc
        adc z_i
        cmp #64                 ; also catches rows above the deck (signed)
        bcc deck
blank:  ldy #WCOLS-1
        lda #0
bl:     sta (p_scr),y
        sta (p_att),y
        dey
        bpl bl
        rts
deck:   sta z_mrow
        ; the line inside the block picks the tables
        and #3
        clc
        adc #>BLKC
        sta lc0+2
        sta lc1+2
        sta lc2+2
        sta lc3+2
        sta lt+2
        clc
        adc #>(BLKA-BLKC)
        sta la0+2
        sta la1+2
        sta la2+2
        sta la3+2
        sta lta+2
        ; the block row in the deck map: 64 bytes each
        lda z_mrow
        lsr a
        lsr a
        lsr a
        ror z_t
        lsr a
        ror z_t
        ora #>DMAP
        sta lm+2
        sta lm2+2
        sta lm3+2
        lda z_t
        and #$C0
        sta lm+1
        sta lm2+1
        sta lm3+1
        ; the first block is entered at the column inside it
        lda _e_m0
        and #3
        sta z_sub
        lda _e_m0
        lsr a
        lsr a
        sta z_bx
        ; cells after the first block: full blocks, and the last few
        lda #WCOLS-4
        clc
        adc z_sub
        sta z_t
        lsr a
        lsr a
        sta z_k
        lda z_t
        and #3
        sta z_cnt
        ldy #0
        ldx z_bx
lm:     lda DMAP,x
        tax
        lda z_sub
        beq lc0
        cmp #2
        bcc lc1
        beq lc2
        jmp lc3
mid:    inc z_bx
        lda z_bx
        and #63
        sta z_bx
        tax
lm2:    lda DMAP,x
        tax
lc0:    lda BLKC,x
        sta (p_scr),y
la0:    lda BLKA,x
        sta (p_att),y
        iny
lc1:    lda BLKC+1,x
        sta (p_scr),y
la1:    lda BLKA+1,x
        sta (p_att),y
        iny
lc2:    lda BLKC+2,x
        sta (p_scr),y
la2:    lda BLKA+2,x
        sta (p_att),y
        iny
lc3:    lda BLKC+3,x
        sta (p_scr),y
la3:    lda BLKA+3,x
        sta (p_att),y
        iny
        dec z_k
        bpl mid
        lda z_cnt
        beq done
        inc z_bx
        lda z_bx
        and #63
        tax
lm3:    lda DMAP,x
        tax
lt:     lda BLKC,x
        sta (p_scr),y
lta:    lda BLKA,x
        sta (p_att),y
        inx
        iny
        dec z_cnt
        bne lt
done:   rts
.endproc

; ---------------------------------------------------------------------------
; restore: the cells noted in this picture get their deck characters back.

restore:
        ldx _back
        lda cl_n,x
        bne :+
        rts
:       sta z_cnt
        lda cl_lo_c,x
        sta p_a
        lda cl_hi_c,x
        sta p_a+1
        lda cl_lo_r,x
        sta p_b
        lda cl_hi_r,x
        sta p_b+1
        ldy #0
@cell:  sty z_k
        lda (p_a),y
        sta z_col
        lda (p_b),y
        sta z_row
        jsr cell_deck
        ldy z_k
        iny
        dec z_cnt
        bne @cell
        rts

; cell_deck: cell (z_col, z_row) of the back buffer from the deck
cell_deck:
        ldx z_row
        lda rowc_lo,x
        clc
        adc z_col
        sta p_scr
        sta p_att
        lda rowc_hi,x
        adc #0
        tax
        ora z_scrhi
        sta p_scr+1
        txa
        ora z_atthi
        sta p_att+1
        lda z_row
        bne :+
        lda _e_blank7
        bne @blank
:       lda _e_r
        clc
        adc z_row
        cmp #64
        bcs @blank
        sta z_mrow
        and #3
        clc
        adc #>BLKC
        sta @lc+2
        adc #>(BLKA-BLKC)
        sta @la+2
        lda z_mrow
        lsr a
        lsr a
        lsr a
        ror z_t
        lsr a
        ror z_t
        ora #>DMAP
        sta @lm+2
        lda z_t
        and #$C0
        sta z_t
        lda _e_m0
        clc
        adc z_col
        sta z_t2                ; deck column
        lsr a
        lsr a
        ora z_t
        sta @lm+1
@lm:    lda DMAP
        sta z_t
        lda z_t2
        and #3
        ora z_t
        tax
        ldy #0
@lc:    lda BLKC,x
        sta (p_scr),y
@la:    lda BLKA,x
        sta (p_att),y
        rts
@blank: ldy #0
        tya
        sta (p_scr),y
        sta (p_att),y
        rts

; uncut: the row the last picture in this buffer cut, rebuilt
uncut:  ldx _back
        lda b_cut,x
        beq @r
        tax
        dex
        stx z_i
        lda rowc_lo,x
        sta p_scr
        sta p_att
        lda rowc_hi,x
        ora z_scrhi
        sta p_scr+1
        lda rowc_hi,x
        ora z_atthi
        sta p_att+1
        jmp row_build
@r:     rts

; pending: blocks changed since this picture was last drawn
pending:
        lda _back
        clc
        adc #1
        sta z_t2                ; this picture's bit
        ldx #NPEND-1
@p:     lda pend_m,x
        and z_t2
        beq @n
        lda pend_m,x
        eor z_t2
        sta pend_m,x
        stx z_k
        jsr pend_block
        ldx z_k
@n:     dex
        bpl @p
        rts

; pend_block: the cells of block pend_x/y,x that lie in the window
pend_block:
        lda pend_y,x
        asl a
        asl a
        sec
        sbc _e_r                ; window row of its top line
        sta z_row
        lda pend_x,x
        asl a
        asl a
        sec
        sbc _e_m0
        sta z_c                 ; window column of its left side
        lda #4
        sta z_i
@r:     lda z_row
        cmp #WROWS
        bcs @nr
        lda #4
        sta z_lr
        lda z_c
        sta z_col
@c:     lda z_col
        cmp #WCOLS
        bcs @nc
        jsr cell_deck
@nc:    inc z_col
        dec z_lr
        bne @c
@nr:    inc z_row
        dec z_i
        bne @r
        rts

; ---------------------------------------------------------------------------
; r_done: the cut row, then the picture is complete - shown at the bottom
; of the next one.
_r_done:
        jsr cut_row
        ldx _back
        lda _e_cutrow
        sta b_cut,x
        lda _e_sx
        sta b_sx,x
        lda _e_s
        jsr set_s
        lda next_code
        beq :+
        eor #$FF
        clc
        adc #1
:       sta _pool_left
        lda #1
        sta _ready
        rts

; cut_row: the window's top row, its characters as copies in this
; picture's codes from CUT_R0 (picture 1's CUT_N on), the same character
; one copy: in the other picture's set, the gap's, these are blank. A
; character for which no code is left shows blank.
cut_row:
        ldx _e_cutrow
        bne :+
        rts
:       dex
        stx z_row
        lda rowc_lo,x
        sta p_scr
        lda rowc_hi,x
        ora z_scrhi
        sta p_scr+1
        lda #CUT_R0
        ldx _back
        beq :+
        lda #CUT_R0 + CUT_N
:       sta z_pc                ; the next copy's code
        lda #CUT_N              ; and how many are left (a count: picture
        sta z_k                 ; 1's end, 256, is 0 in a byte)
        lda #WCOLS-1
        sta z_col
@c:     ldy z_col
        lda (p_scr),y
        cmp #2                  ; codes 0 and 1 are blank everywhere
        bcc @n
        tax
        lda cut_tag,x
        cmp z_tag
        beq @have
        lda z_tag
        sta cut_tag,x
        lda z_k
        bne :+
        sta cut_code,x          ; none left: blank
        beq @have
:       dec z_k
        lda z_pc
        sta cut_code,x
        inc z_pc
        jsr cut_copy
        ldy z_col
        ldx z_t                 ; the character's code
@have:  lda cut_code,x
        sta (p_scr),y
@n:     dec z_col
        bpl @c
        rts

; cut_copy: character X copied to code cut_code,X
cut_copy:
        stx z_t
        lda code_lo,x
        sta p_src
        lda code_hi,x
        ora z_fonthi
        sta p_src+1
        lda cut_code,x
        tax
        lda code_lo,x
        sta p_dst
        lda code_hi,x
        ora z_fonthi
        sta p_dst+1
        ldy #7
:       lda (p_src),y
        sta (p_dst),y
        dey
        bpl :-
        rts

; note_cell: cell (z_col, z_row) holds a pool character now
note_cell:
        ldx _back
        lda cl_lo_c,x
        sta p_a
        lda cl_hi_c,x
        sta p_a+1
        lda cl_lo_r,x
        sta p_b
        lda cl_hi_r,x
        sta p_b+1
        ldy cl_n,x
        lda z_col
        sta (p_a),y
        lda z_row
        sta (p_b),y
        inc cl_n,x
        rts

; ===========================================================================
; Figures
;
; A figure is drawn from a pre-shifted copy: for each of the four
; multicolour pixels it may start at inside a cell, 128 bytes holding its
; four columns of up to 20 lines one under the other (at col_at), 7 lines
; of nothing before each and after the last, so the eight lines of any cell
; with a line of the figure can be read without looking where the figure
; ends. At mask_at, 3 bytes for each column: which of its lines have pixels
; (bit = line).
; ===========================================================================

; pre_shift: f_src (f_h lines of 3 bytes, 12 pixels) into the 512 bytes at
; p_pre
_pre_shift:
        lda #0
        sta z_sub
@sub:   ; clear the 128 bytes
        ldy #127
        lda #0
:       sta (_p_pre),y
        dey
        bpl :-
        sta z_acc+3             ; (the column a shift spills into)
        lda z_sub               ; the shift: 2 bits a pixel
        asl a
        sta p_shr
        lda #0
        sta z_si                ; source index
        sta z_i                 ; line
@line:  ldy z_si
        ldx #0
:       lda (_f_src),y
        sta z_acc,x
        iny
        inx
        cpx #3
        bne :-
        sty z_si
        ; column 0: byte 0's share; column c: byte c-1's spill and byte c's
        lda #0
        sta z_t                 ; spill
        sta z_k                 ; column
@col:   ldx z_k                 ; (shifted here, not by tables: this is
        lda z_acc,x             ; done once for a picture, and 2K is the
        ldx #0                  ; console's)
        stx p_shl
        ldx p_shr
        beq @shd
:       lsr a
        ror p_shl
        dex
        bne :-
@shd:   ora z_t
        sta z_c
        lda p_shl
        sta z_t
        ldx z_k
        lda col_at,x
        clc
        adc z_i
        tay
        lda z_c
        sta (_p_pre),y
        beq @nx
        ; the line has pixels: its bit
        lda z_i
        lsr a
        lsr a
        lsr a
        clc
        adc mask_at,x
        tay
        lda z_i
        and #7
        tax
        lda bitof,x
        ora (_p_pre),y
        sta (_p_pre),y
@nx:    inc z_k
        lda z_k
        cmp #4
        bne @col
        inc z_i
        lda z_i
        cmp _f_h
        bne @line
        ; next sub, 128 bytes on
        lda _p_pre
        clc
        adc #128
        sta _p_pre
        bcc :+
        inc _p_pre+1
:       inc z_sub
        lda z_sub
        cmp #4
        jne @sub
        rts

bitof:  .byte 1, 2, 4, 8, 16, 32, 64, 128
; in a copy's 128 bytes: a column's line 0, its line mask
col_at: .byte 7, 7 + 27, 7 + 2 * 27, 7 + 3 * 27
mask_at:.byte 115, 118, 121, 124

; r_fig: one figure into the back buffer.
;   f_pre  its pre-shifted copy for the pixel it starts at in its cell
;   f_col  window column of the cell its left edge is in (may be < 0)
;   f_row  window row of the cell its top line is in (may be < 0)
;   f_line line inside that cell, 0..7
; Figures are drawn in order; a later one covers an earlier one.
_r_fig:
        lda #0
        sta z_c
@col:   lda _f_col
        clc
        adc z_c
        cmp #WCOLS              ; also < 0, as unsigned
        jcs @nextc
        sta z_col
        ; which cell rows have pixels: row k shows the column's lines
        ; 8k - f_line to 8k - f_line + 7, the low 8 - f_line bits of line
        ; mask byte k and the high f_line bits of byte k - 1
        ldx z_c
        ldy mask_at,x
        lda col_at,x            ; (the lines of row 0 from line -f_line)
        sec
        sbc _f_line
        sta z_t2
        ldx _f_line
        lda (_f_pre),y
        sta z_t
        and lo_f,x
        sta z_acc
        lda z_t
        and hi_f,x
        sta z_acc+1
        iny
        lda (_f_pre),y
        sta z_t
        and lo_f,x
        ora z_acc+1
        sta z_acc+1
        lda z_t
        and hi_f,x
        sta z_acc+2
        iny
        lda (_f_pre),y
        sta z_t
        and lo_f,x
        ora z_acc+2
        sta z_acc+2
        lda z_t
        and hi_f,x
        sta z_acc+3
        ldx #0
@cell:  lda z_acc,x
        bne @row
@skip:  inx
        cpx #4
        bcc @cell
        jmp @nextc
@skipk: ldx z_k
        jmp @skip
@row:   stx z_k
        txa
        clc
        adc _f_row
        cmp #WROWS              ; also < 0
        bcs @skipk
        sta z_row
        tay
        bne :+
        lda _e_blank7           ; row 0 above the window
        bne @skipk
:       txa                     ; (p_d),y: the cell's line y
        asl a
        asl a
        asl a
        adc z_t2
        adc _f_pre
        sta p_d
        lda _f_pre+1
        adc #0
        sta p_d+1
        jsr cell_get
        bcs @nextc              ; no characters left
        .repeat 8, L
        ldy #L
        lda (p_d),y
        tax
        lda (p_src),y
        and nmaskof,x
        ora ident,x
        sta (p_dst),y
        .endrepeat
        jmp @skipk
@nextc: inc z_c
        lda z_c
        cmp #4
        jcc @col
        rts

; r_fig's line masks for f_line: a mask byte's lines in its own cell row,
; and in the next
lo_f:   .byte $FF, $7F, $3F, $1F, $0F, $07, $03, $01
hi_f:   .byte $00, $80, $C0, $E0, $F0, $F8, $FC, $FE

; cell_get: the character of cell (z_row, z_col) in the back buffer, for
; drawing into; p_dst points at its 8 bytes, p_src at what is behind the
; figure: the character itself, or for a cell still showing a deck
; character, that character in multicolour - the cell is handed a character
; of the pool then and switched to multicolour. Carry set if the pool is
; empty.
cell_get:
        ldx z_row
        lda rowc_lo,x
        clc
        adc z_col
        sta p_scr
        sta p_att
        lda rowc_hi,x
        adc #0
        tax
        ora z_scrhi
        sta p_scr+1
        txa
        ora z_atthi
        sta p_att+1
        ldy #0
        lda (p_scr),y
        cmp #POOL
        bcs @have
        tax                     ; the deck character
        lda next_code
        cmp z_lim
        beq @none
        sta (p_scr),y
        inc next_code
        lda _f_tint             ; the figure's colour, multicolour,
        beq :+
        sta (p_att),y
        ldx #0                  ; (and nothing behind it: the deck's lines
        beq :++                 ; would show in that colour too)
:       lda (p_att),y
        ora #$08                ; or the deck's, multicolour
        sta (p_att),y
:
        lda code_lo,x           ; behind it: the deck character in multicolour
        sta p_src
        lda code_hi,x
        clc
        adc #>MCFONT
        sta p_src+1
        jsr note_cell
        ldx next_code
        dex
        lda code_lo,x
        sta p_dst
        lda code_hi,x
        ora z_fonthi
        sta p_dst+1
        clc
        rts
@have:  tax
        lda _f_tint
        beq :+
        sta (p_att),y
:       lda code_lo,x
        sta p_dst
        sta p_src
        lda code_hi,x
        ora z_fonthi
        sta p_dst+1
        sta p_src+1
        clc
        rts
@none:  sec
        rts

; ===========================================================================
; Droids
; ===========================================================================

        .import _nd, _d_x, _d_y, _d_vx, _d_vy, _d_boom, _d_wait, _d_type
        .import _deck, _wp_first, _wp_x, _wp_y, _wp_dir, _dr_drive
        .import droid_look, d_lk
        .export _move_droids, _rnd

; move_droids(): a tick for droids 1 .. nd-1. An exploding one goes on
; exploding, a waiting one waits; one in the middle of a block, on a
; waypoint, chooses where it goes next; then they move.
_move_droids:
        ldx #1
@loop:  cpx _nd
        bcs @done
        lda _d_boom,x
        beq @alive
        cmp #BOOM_GONE
        bcs @next
        inc _d_boom,x
        bne @next
@alive: lda _d_wait,x
        beq @go
        dec _d_wait,x           ; (done waiting: on, and a new way only in
        jmp @next               ; the middle of a block, as the original)
@go:    txa
        asl a
        tay
        lda _d_x,y              ; in the middle of a block (the waypoints
        and #31                 ; all are)
        cmp #16
        bne @move
        lda _d_y,y
        and #31
        cmp #16
        bne @move
        jsr choose              ; on a waypoint: a new way, or a wait
        lda _d_wait,x
        bne @next
@move:  jsr dmove
@next:  inx
        bne @loop
@done:  rts

; droid X on its own waypoint (the very character, as the original's
; $170D; two may share a block) takes one of its first three ways, each a
; third of the time as the original picks ($1CAD there); an empty pick is
; a wait of 8 ticks. Not on one: it goes on. Keeps X.
choose: stx c_i
        txa
        asl a
        tay
        lda _d_x+1,y            ; its character
        sta c_bx
        lda _d_x,y
        lsr c_bx
        ror a
        lsr c_bx
        ror a
        lsr c_bx
        ror a
        sta c_bx
        lda _d_y+1,y
        sta c_by
        lda _d_y,y
        lsr c_by
        ror a
        lsr c_by
        ror a
        lsr c_by
        ror a
        sta c_by
        ldy _deck
        lda _wp_first+1,y
        sta c_last
        lda _wp_first,y
        tay
@find:  cpy c_last
        bcs @none
        lda _wp_x,y
        cmp c_bx
        bne @nx
        lda _wp_y,y
        cmp c_by
        beq @got
@nx:    iny
        bne @find
@none:  rts
@got:   lda _wp_dir,y           ; its ways: bit k for wbit_dx/dy[k]
        sta c_bx
        ldy #0
        ldx #0
@bit:   lsr c_bx
        bcc @nb
        lda wbit_dx,x
        sta c_cx,y
        lda wbit_dy,x
        sta c_cy,y
        iny
        cpy #3
        beq @have
@nb:    inx
        cpx #8
        bne @bit
@have:  sty c_last              ; (the ways found)
        jsr _rnd
        ldy #0
        cmp #$AA
        bcs :+
        iny
        cmp #$55
        bcs :+
        iny
:       ldx c_i
        cpy c_last
        bcc @way
        lda #0
        sta _d_vx,x
        sta _d_vy,x
        lda #8
        sta _d_wait,x
        rts
@way:   sty c_by
        lda #0                  ; a new way: look ahead again
        sta d_lk,x
        ldy _d_type,x
        lda _dr_drive,y
        sta c_bx
        ldy c_by
        lda c_cx,y
        jsr times
        sta _d_vx,x
        lda c_cy,y
        jsr times
        sta _d_vy,x
        rts
; A (-1, 0 or 1) times the droid's speed c_bx
times:  beq @r
        bmi :+
        lda c_bx
        rts
:       lda #0
        sec
        sbc c_bx
@r:     rts

; bit k of a waypoint's ways, from bit 0: up-left, up, up-right, right,
; down-right, down, down-left, left
wbit_dx: .byte <-1, 0, 1, 1, 1, 0, <-1, <-1
wbit_dy: .byte <-1, <-1, <-1, 0, 1, 1, 1, 0

        .data
rs:     .word $1234
        .code

; rnd(): the game's random numbers, a 16-bit xorshift (7, 9, 8)
_rnd:   lda rs+1
        lsr a
        lda rs
        ror a
        eor rs+1
        sta rs+1
        ror a
        eor rs
        sta rs
        eor rs+1
        sta rs+1
        rts

; droid X a tick on, unless a wall is ahead; into a new character, it
; looks ahead again next time. Keeps X.
dmove:  jsr droid_look
        bcs @r
        txa
        asl a
        tay
        lda _d_x,y
        sta c_bx
        lda _d_y,y
        sta c_by
        lda _d_vx,x
        jsr addx
        lda _d_vy,x
        jsr addy
        lda _d_x,y
        eor c_bx
        sta c_bx
        lda _d_y,y
        eor c_by
        ora c_bx
        and #$F8
        beq @r
        lda #0
        sta d_lk,x
@r:     rts

; d_x[Y/2] += A, A signed; keeps X and Y
addx:   sta z_t
        clc
        adc _d_x,y
        sta _d_x,y
        lda z_t
        and #$80
        beq :+
        lda #$FF
:       adc _d_x+1,y
        sta _d_x+1,y
        rts

addy:   sta z_t
        clc
        adc _d_y,y
        sta _d_y,y
        lda z_t
        and #$80
        beq :+
        lda #$FF
:       adc _d_y+1,y
        sta _d_y+1,y
        rts

; music, while there is some: its player, once a picture
mus_go: jmp (_mus_hook)

; ===========================================================================
; Keyboard and joysticks
;
; The interrupt reads them once a picture and notes every key that goes
; down, so a short press is not lost. The row goes to both latches, and
; $FF08 is read twice: the first read still sees the value just written.
; Bits: up 1, down 2, left 4, right 8, fire 16 (also space, CTRL and C=),
; space 32, run/stop 64. The cursor keys drive as the joystick does.
; ===========================================================================

kpoll:  ldx #$FF
        stx KEY_ROW
        lda #$FB                ; joystick 1
        jsr krd
        sta kj
        lda #$FD                ; joystick 2
        jsr krd
        ora kj
        sta kj
        and #$0F
        sta kr
        lda kj
        and #$C0                ; fire is bit 6 or 7
        beq :+
        lda #16
        ora kr
        sta kr
:       lda #$BF                ; cursor left, cursor right
        jsr krow
        tax
        and #$01
        beq :+
        lda #4
        ora kr
        sta kr
:       txa
        and #$08
        beq :+
        lda #8
        ora kr
        sta kr
:       lda #$DF                ; cursor down, cursor up
        jsr krow
        tax
        and #$01
        beq :+
        lda #2
        ora kr
        sta kr
:       txa
        and #$08
        beq :+
        lda #1
        ora kr
        sta kr
:       lda #$7F                ; space, run/stop
        jsr krow
        tax
        and #$10
        beq :+
        lda #16 | 32            ; space is fire as well
        ora kr
        sta kr
:       txa
        and #$24                ; so are CTRL and C= (an emulator's Ctrl
        beq :+                  ; keys: Yape's right and left one)
        lda #16
        ora kr
        sta kr
:       txa
        and #$80
        beq :+
        lda #64
        ora kr
        sta kr
:       lda #$FF
        sta TED_KEYS
        sta KEY_ROW
        lda kr
        ora _dbg_keys
        sta _keys_irq
        tax
        lda kprev
        eor #$FF
        stx kprev
        and _keys_irq
        ora keys_hit
        sta keys_hit
        rts

krow:   sta KEY_ROW
krd:    sta TED_KEYS
        lda TED_KEYS
        lda TED_KEYS
        eor #$FF
        rts

; pause_keys(): the keys the pause looks at, off the keyboard's rows now
; (the interrupt sets them again for its own reading): CLR/HOME 1, HELP
; 2, F1 4, F2 8, F3 16 - none with shift (the Plus/4 has F2 and F3 keys
; of their own)
_pause_keys:
        php
        sei
        lda #$7F                ; CLR/HOME: bit 1
        jsr krow
        and #2
        lsr a
        sta kj
        lda #$FE                ; HELP, F1, F2, F3: bits 3-6
        jsr krow
        lsr a
        lsr a
        and #$1E
        ora kj
        plp
        ldx #0
        rts

; eng_keys: the keys that went down since the last call
_eng_keys:
        php
        sei
        lda keys_hit
        ldx #0
        stx keys_hit
        plp
        rts

; ===========================================================================
; The original's animated characters ($2605 there, list $6C28)
; ===========================================================================

        .export _anim_deck, _anim_plan, _anim_static, _eng_roll, _roll
        .import _anim_e, _anim_emc, _anim_p, _tick

.macro dots B                   ; the four dots' row X, round once
        ldy B + (DOT_CHAR + 3) * 8,x
        lda B + (DOT_CHAR + 2) * 8,x
        sta B + (DOT_CHAR + 3) * 8,x
        lda B + (DOT_CHAR + 1) * 8,x
        sta B + (DOT_CHAR + 2) * 8,x
        lda B + DOT_CHAR * 8,x
        sta B + (DOT_CHAR + 1) * 8,x
        tya
        sta B + DOT_CHAR * 8,x
.endmacro

; anim_deck(): once a tick in the game: the energizer's character turns, a
; phase every three ticks, and every other tick its dots go round a
; character on ($38C4 there), as the original's
_anim_deck:
        lda _tick
        lsr a
        bcs @e
        ldx #7
@d:     dots FONT0
        dots FONT1
        dots MCFONT
        dex
        bpl @d
@e:     dec a_ec
        bne @out
        lda #3
        sta a_ec
        jsr a_next
        ldy #7
:       lda _anim_e,x
        sta FONT0 + ENERGY_CHAR * 8,y
        sta FONT1 + ENERGY_CHAR * 8,y
        lda _anim_emc,x
        sta MCFONT + ENERGY_CHAR * 8,y
        dex
        dey
        bpl :-
@out:   rts

; anim_plan(): once a tick on the console's deck plan (screens.s), where
; the original calls it about every 2.3 pictures: the energizer's symbol
; (block 20's) a phase every two ticks, the player's (32) every three
PLAN_E  = 20
PLAN_P  = 32
_anim_plan:
        dec a_ec
        bne @p
        lda #2
        sta a_ec
        jsr a_next
        ldy #7
:       lda _anim_e,x
        sta FONT1 + PLAN_E * 8,y
        dex
        dey
        bpl :-
@p:     dec a_pc
        bne @out
        lda #3
        sta a_pc
        inc a_pp
        lda a_pp
        and #3
        asl a
        asl a
        asl a
        ora #7
        tax
        ldy #7
:       lda _anim_p,x
        sta FONT1 + PLAN_P * 8,y
        dex
        dey
        bpl :-
@out:   rts

; anim_static(): the static's four characters (250-253 of picture 1's
; set, above a picture's and the letters', terminated() in paradroid.s)
; go round a character on, as the dots
STATIC  = FONT1 + 250 * 8
_anim_static:
        ldx #7
:       ldy STATIC + 24,x
        lda STATIC + 16,x
        sta STATIC + 24,x
        lda STATIC + 8,x
        sta STATIC + 16,x
        lda STATIC,x
        sta STATIC + 8,x
        tya
        sta STATIC,x
        dex
        bpl :-
        rts

; roll_step: in the vertical blank, while roll is set: the static a line
; further down, and round a character every other picture - in the
; interrupt, so that it goes on while the 999's picture loads
roll_step:
        inc rollc
        lda rollc
        lsr a
        bcs :+
        jsr _anim_static
:       lda rollc
        and #7
        ; (on into eng_roll)

; eng_roll(s): a page in the window moved down by s lines (0-7), both
; pictures - the static's rolling, as the original's fine scroll
_eng_roll:
        ldx #1
        jsr set_s
        dex
        ; (on into set_s)

; set_s: the window moved down by A = s lines (0-7) in picture X, for the
; interrupt (irq_scroll). The line counter is set back by s's even part
; only, its odd part is the y scroll's: the TED's PAL colour phase
; alternates with the line counter's bit 0, and a TV or plus4emu shown two
; lines of one phase in a row decodes the rest of the picture with the
; wrong one - the window's colours, green to ochre, in every picture with
; an odd s (Luca's real Plus/4). Rows are fetched where the line counter
; and the y scroll agree in their last three bits, so (line - s) & 7 = 3
; is (line - even) & 7 = 3 + odd: the same lines. A and X kept.
set_s:  pha
        and #6
        sta b_s,x
        pla
        pha
        and #1
        clc
        adc #3
        sta b_yo,x
        pla
        pha
        eor #$FF                ; 6 - s, in three bits
        clc
        adc #7
        and #7
        sta b_rcv,x
        pla
        rts

; the energizer's next phase: X its last byte's index
a_next: inc a_ep
        lda a_ep
        and #3
        asl a
        asl a
        asl a
        ora #7
        tax
        rts

        .data
a_ec:   .byte 1                 ; ticks to the next phase
a_ep:   .byte 0                 ; the phase
a_pc:   .byte 1                 ; the plan's player likewise
a_pp:   .byte 0
_roll:  .byte 0                 ; the static rolls (roll_step)
rollc:  .byte 0
