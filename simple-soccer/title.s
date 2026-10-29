; title.s - the title before the first match: the name, the length of
; the match, one player or two, and the two teams with their flags to
; choose (the joystick up and down to a line, left and right on it), fire
; to kick off.
;
; It lies at $C000, loaded with the program but where the pictures go
; once the match is on (engine.s): it runs first, on a screen of its own
; (MAT2's and FNT2's place), and is gone after; what it keeps in the
; program (the teams, the choosing) is in the CODE and RODATA segments.
; Its music is music.s's.
;
; The screen is multicolour text: the text's colours are all hires ones
; (hues 0-7, bit 3 clear - the name's too), the flags' cells multicolour,
; with the background (a navy blue), white and red shared and one colour
; of each cell's own. The flags come from the disk (tools/mkflags.py, at
; FLAGS): their cells' patterns, all of them once, which the two flags
; shown have copied into the codes the font leaves free - each side two
; sets of 37: a flag chosen is made ready in the set not shown (prep),
; and only its 24 cells change over (commit), just below the picture's
; last line - nothing is ever drawn half. A line chosen only changes
; colours. No team plays itself: choosing passes the other side's by.

        .include "game.inc"
        .include "data.inc"

        .repeat 256, I          ; (text as it is, ASCII: the title's font
        .charmap I, I           ; has its characters at their ASCII codes,
        .endrepeat              ; not the Plus/4's PETSCII)

        .import joy_scan, joy, title_font, min_frames, two, train, team_col, team_flk, sk
        .import jog_lo, jog_hi
        .import mus_start, mus_frame, mus_stop
        .export title

TCOL        = MAT2              ; the title's colours,
TCODE       = MAT2 + $400       ; codes,
TFONT       = FNT2              ; characters

C_BG        = $16               ; dark blue (the flags' navy too)
C_BORDER    = $06
C_TEXT      = $71               ; white
C_VALUE     = $77               ; yellow
C_DIM       = $51               ; grey: a line not chosen
C_FIRE0     = $75               ; light green, and white, by turns
C_FIRE1     = $71
C_FRAME     = $49               ; a flag's frame: grey, multicolour
FLAG_WHITE  = $71               ; the flags' shared colours ($FF16, $FF17;
FLAG_RED    = $32               ; tools/mkflags.py's WHITE, RED)

SKIP        = $0FF8             ; "TS" here: a test, no title (tests/vice.py,
                                ; yape.py) - behind the KERNAL's screen,
                                ; not loaded, not cleared
LOGO_ROW    = 1
LOGO_COL    = 7
CUP_COL     = LOGO_COL + 12     ; the cup in the gap between the words,
CUP_CODE    = '['               ; its four characters ([ \ ] ^),
CUP_TOP     = $77               ; gold, lighter above as the letters
CUP_FOOT    = $57
SUB_ROW     = 4
LEN_ROW     = 6
PLAYERS_ROW = 7
MODE_ROW    = 8
LINE_COL    = 7                 ; (their text,
VALUE_COL   = 24                ; the digits, the mode)
LABEL_ROW   = 10                ; "HOME", "AWAY"
FLAG_ROW    = 12                ; the flags' first row, 4 rows of 6 cells
FLAG_W      = 6
FLAG_H      = 4
HOME_COL    = 5                 ;   the home team's first column
AWAY_COL    = 29                ;   the away team's
NAME_ROW    = 17                ; their names, a field of NAME_W under each
NAME_W      = 13
FIRE_ROW    = 19
PORTS_ROW   = 21                ; (where the joysticks go)
PORTS_COL   = 6
CREDIT_ROW  = 23

FLAGS       = $D400             ; the disk's (tools/mkflags.py): the patterns,
FLAGS_TEAMS = $DB60             ; each team's 24 cells and 12 colour bytes,
FLAGS_PAL   = $E060             ; the palette,
FLAGS_SIG   = $E06F             ; "F": they are there (a test has none)
LOC         = $E100             ; (prep's: a pattern's code, 256 bytes,
CBUF        = $E200             ; the cells' codes and colours made ready)
CCOL        = $E220
FRAME_CODE  = 0                 ; the frames' 8 characters' first code

        .zeropage
t_ptr:  .res 2                  ; (the title's)
t_dst:  .res 2
t_cd:   .res 2
t_s:    .res 2                  ; (new_code's)
t_d:    .res 2

        .segment "TITLE"

title:
        lda #0
        sta t_sel               ; (3 minutes, one player, a match, unless
        sta t_two               ; chosen)
        sta t_train
        sta t_row
        jsr skip                ; (a test: none)
        bcc :+
        rts
:       lda TED_SCROLLY         ; blank while it is drawn (the boot's
        and #$EF                ; screen goes now)
        sta TED_SCROLLY
        lda #0                  ; no interrupts from the TED but the
        sta TED_IRQEN           ; music's (the ROM is out, the match's is
        lda TED_IRQ             ; not set up yet)
        sta TED_IRQ
        jsr mus_start
        ldx #0                  ; the characters, the frames', the screen
:       lda title_font,x        ; blank
        sta TFONT + $100,x
        lda title_font + $100,x
        sta TFONT + $200,x
        lda title_font + $200,x
        sta TFONT + $300,x
        lda title_font + $300,x
        sta TFONT + $400,x
        lda title_font + $400,x
        sta TFONT + $500,x
        lda #' '
        sta TCODE,x
        sta TCODE + $100,x
        sta TCODE + $200,x
        sta TCODE + $300,x
        lda #C_TEXT
        sta TCOL,x
        sta TCOL + $100,x
        sta TCOL + $200,x
        sta TCOL + $300,x
        inx
        bne :-
        ldx #8 * 8 - 1
:       lda frame_chars,x
        sta TFONT + FRAME_CODE * 8,x
        dex
        bpl :-
        ; the name, twice the size, a colour each letter (lighter above)
        ldx #0
@logo:  lda name,x
        cmp #' '
        beq @gap
        ldy #0                  ; its place in the big letters
:       cmp big_of,y
        beq :+
        iny
        bne :-
:       tya
        asl a
        asl a
        ora #128
        sta t_code
        txa
        asl a
        tay                     ; (its column: 2 a letter)
        lda t_code
        sta TCODE + LOGO_ROW * 40 + LOGO_COL,y
        clc
        adc #1
        sta TCODE + LOGO_ROW * 40 + LOGO_COL + 1,y
        adc #1
        sta TCODE + (LOGO_ROW + 1) * 40 + LOGO_COL,y
        adc #1
        sta TCODE + (LOGO_ROW + 1) * 40 + LOGO_COL + 1,y
        lda hue_of,x
        ora #$70                ; (above: the lightest)
        sta TCOL + LOGO_ROW * 40 + LOGO_COL,y
        sta TCOL + LOGO_ROW * 40 + LOGO_COL + 1,y
        and #$57                ; (below: two shades darker)
        sta TCOL + (LOGO_ROW + 1) * 40 + LOGO_COL,y
        sta TCOL + (LOGO_ROW + 1) * 40 + LOGO_COL + 1,y
@gap:   inx
        cpx #NAME_LEN
        bne @logo
        ldx #4 * 8 - 1          ; between the words a cup, in the letters'
:       lda cup_chars,x         ; gold (codes the text has no use for)
        sta TFONT + CUP_CODE * 8,x
        dex
        bpl :-
        ldx #1
:       txa
        clc
        adc #CUP_CODE
        sta TCODE + LOGO_ROW * 40 + CUP_COL,x
        adc #2
        sta TCODE + (LOGO_ROW + 1) * 40 + CUP_COL,x
        lda #CUP_TOP
        sta TCOL + LOGO_ROW * 40 + CUP_COL,x
        lda #CUP_FOOT
        sta TCOL + (LOGO_ROW + 1) * 40 + CUP_COL,x
        dex
        bpl :-
        ; the lines of text
        lda #<lines
        sta t_ptr
        lda #>lines
        sta t_ptr + 1
@line:  ldy #0
        lda (t_ptr),y           ; row ($FF: no more)
        bmi @shown
        tax
        lda row_lo,x
        clc
        iny
        adc (t_ptr),y           ; + column
        sta t_dst
        lda row_hi,x
        adc #0
        sta t_dst + 1
        iny
        lda (t_ptr),y           ; its colour
        sta t_col
        lda t_ptr               ; on to its text
        clc
        adc #3
        sta t_ptr
        bcc :+
        inc t_ptr + 1
:       ldy #0
:       lda (t_ptr),y
        beq @end
        sta (t_dst),y
        lda t_dst + 1           ; (the colour: $400 below)
        pha
        sec
        sbc #4
        sta t_dst + 1
        lda t_col
        sta (t_dst),y
        pla
        sta t_dst + 1
        iny
        bne :-
@end:   iny                     ; past the 0
        tya
        clc
        adc t_ptr
        sta t_ptr
        bcc @line
        inc t_ptr + 1
        bne @line
@shown: jsr draw_frames
        jsr kits
        ldx #0
        jsr prep
        jsr commit
        ldx #1
        jsr prep
        jsr commit
        jsr draw_names
        jsr show_rows
        jsr show_values
        ; the TED: multicolour text, 40 columns, 25 rows, the title's
        ; matrix and characters
        lda TED_CTRL2
        and #$40                ; (PAL or NTSC kept)
        ora #$98                ; 256 characters, multicolour, 40 columns
        sta TED_CTRL2
        lda TED_BMBASE
        and #$FB                ; characters from RAM
        sta TED_BMBASE
        lda TED_CHBASE
        and #$03
        ora #>TFONT
        sta TED_CHBASE
        lda #>TCOL
        sta TED_VMBASE
        lda #C_BG
        sta TED_BG
        lda #FLAG_WHITE
        sta TED_COL1
        lda #FLAG_RED
        sta TED_COL2
        lda #C_BORDER
        sta TED_BORDER
        lda #$1B                ; on, text, 25 rows
        sta TED_SCROLLY
        lda #0
        sta t_was
        sta t_tick
        ; the choice; fire to kick off (on its letting go)
@wait:  lda TED_LINE            ; a frame: the beam into lines 200-215 (a
        sec                     ; window: a line could pass unseen while
        sbc #200                ; the music's interrupt runs) - below the
        cmp #16                 ; picture: what changes is drawn now
        bcs @wait
        ldx t_pend              ; a flag made ready: in now, with the names
        beq :+
        dex
        jsr commit
        jsr draw_names
        lda #0
        sta t_pend
:       jsr mus_frame
        inc t_tick
        lda t_tick              ; "fire" in light green and white by turns
        and #32
        beq :+
        lda #C_FIRE1
        bne :++
:       lda #C_FIRE0
:       ldx #39
:       sta TCOL + FIRE_ROW * 40,x
        dex
        bpl :-
        jsr skip
        bcs @go
        jsr joy_scan            ; (joy_read, but the music not held up)
        lda t_was               ; let go of: held before, not now
        eor #$FF
        and joy
        sta t_new               ; (pushed: now, not before)
        lda joy
        eor #$FF
        and t_was
        ldx joy
        stx t_was
        and #J_FIRE
        bne @go
        lda t_new               ; up, down: a line up or down
        and #J_UP
        beq :+
        lda t_row
        beq :+
        dec t_row
        jsr show_rows
:       lda t_new
        and #J_DOWN
        beq :+
        lda t_row
        cmp #ROWS - 1
        beq :+
        inc t_row
        jsr show_rows
:       lda t_new               ; left, right: the choice on it
        and #J_LEFT | J_RIGHT
        beq @next
        and #J_RIGHT            ; (0: left)
        ldx t_row
        jsr change
        bcc :+
        ldx t_row               ; (a team: its flag made ready, in with the
        dex                     ; next picture's end)
        dex
        dex
        jsr prep
        inx
        stx t_pend
:       jsr show_values
@next:  lda TED_LINE            ; (out of the window before the next)
        sec
        sbc #200
        cmp #16
        bcc @next
        jmp @wait
@go:    jsr mus_stop
        jmp chosen

; skip: carry set if a test asks for no title (SKIP: "TS", "TT" for
; training), the ask taken back - the match then 3 minutes, one player,
; the first teams
skip:
        lda SKIP
        cmp #'T'
        bne @no
        lda SKIP + 1
        cmp #'S'
        beq @go
        cmp #'T'
        bne @no
        inc t_train
@go:    lda #0
        sta SKIP
        sta SKIP + 1
        jsr chosen
        sec
        rts
@no:    clc
        rts

; show_rows: the line the stick is on in white, the others grey - the
; length's, the players' and the mode's text, a team's label and its arrows
show_rows:
        ldx #ROWS - 1
@row:   lda #C_DIM
        cpx t_row
        bne :+
        lda #C_TEXT
:       cpx #3
        bcs @team
        ldy row_of,x            ; (TCOL: $400 below the codes)
        pha
        lda row_lo,y
        clc
        adc #LINE_COL
        sta t_dst
        lda row_hi,y
        adc #0
        sec
        sbc #>(TCODE - TCOL)
        sta t_dst + 1
        pla
        ldy #26
:       sta (t_dst),y
        dey
        bpl :-
        bmi @next
@team:  ldy label_at - 3,x      ; "HOME" / "AWAY", "<" and ">" round the name
        sta TCOL + LABEL_ROW * 40,y
        sta TCOL + LABEL_ROW * 40 + 1,y
        sta TCOL + LABEL_ROW * 40 + 2,y
        sta TCOL + LABEL_ROW * 40 + 3,y
        ldy field_at - 3,x
        sta TCOL + NAME_ROW * 40 - 1,y
        sta TCOL + NAME_ROW * 40 + NAME_W,y
@next:  dex
        bpl @row
        rts

; show_values: the length's and the players' digits, the mode (training:
; no length, "-"), and where the joysticks go
show_values:
        ldx t_sel
        lda digit_of,x
        ldy t_train
        beq :+
        lda #'-'
:       sta TCODE + LEN_ROW * 40 + VALUE_COL
        lda t_two
        clc
        adc #'1'
        sta TCODE + PLAYERS_ROW * 40 + VALUE_COL
        ldx #MODE_W - 1
:       lda mode_0,x
        ldy t_train
        beq :+
        lda mode_1,x
:       sta TCODE + MODE_ROW * 40 + VALUE_COL,x
        lda #C_VALUE
        sta TCOL + MODE_ROW * 40 + VALUE_COL,x
        dex
        bpl :--
        sta TCOL + LEN_ROW * 40 + VALUE_COL
        sta TCOL + PLAYERS_ROW * 40 + VALUE_COL
        ldx #PORTS_W - 1
:       lda ports_1,x
        ldy t_two
        beq :+
        lda ports_2,x
:       sta TCODE + PORTS_ROW * 40 + PORTS_COL,x
        dex
        bpl :--
        rts

; draw_frames: a grey frame round each flag's place
draw_frames:
        ldx #1
@side:  lda flag_lo,x           ; the row above the flag, a column left
        sec
        sbc #41
        sta t_dst
        sta t_cd
        lda flag_hi,x
        sbc #0
        sta t_dst + 1
        sec
        sbc #>(TCODE - TCOL)
        sta t_cd + 1
        ldy #0
        jsr @row                ; the top: corner, edge, corner
        .byte FRAME_CODE, FRAME_CODE + 1, FRAME_CODE + 2
        lda #FLAG_H             ; the sides
        sta t_i
:       jsr @down
        ldy #0
        jsr @row
        .byte FRAME_CODE + 3, ' ', FRAME_CODE + 4
        dec t_i
        bne :-
        jsr @down
        ldy #0
        jsr @row                ; the bottom
        .byte FRAME_CODE + 5, FRAME_CODE + 6, FRAME_CODE + 7
        dex
        bpl @side
        rts
@down:  lda t_dst               ; a row on
        clc
        adc #40
        sta t_dst
        sta t_cd
        bcc :+
        inc t_dst + 1
        inc t_cd + 1
:       rts
@row:   pla                     ; the three codes after the jsr: the left
        sta t_ptr               ; one, the middle ones (' ': left as they
        pla                     ; are), the right one
        sta t_ptr + 1
        ldy #1
        lda (t_ptr),y
        ldy #0
        jsr @put
        ldy #2
        lda (t_ptr),y
        cmp #' '
        beq :++
        ldy #FLAG_W
:       jsr @put
        dey
        bne :-
:       ldy #3
        lda (t_ptr),y
        ldy #FLAG_W + 1
        jsr @put
        lda t_ptr               ; back past the three
        clc
        adc #3
        tay
        lda t_ptr + 1
        adc #0
        pha
        tya
        pha
        rts
@put:   sta (t_dst),y           ; (keeps A: the code)
        pha
        lda #C_FRAME
        sta (t_cd),y
        pla
        rts

;  prep: team side X's (0 home, 1 away) flag made ready in its set of
; codes not shown: its patterns copied there, its cells' codes and colours
; to CBUF, CCOL (commit puts them on the screen). Keeps X.
prep:
        stx t_x
        lda FLAGS_SIG           ; (no flags: a test)
        cmp #'F'
        beq :+
        rts
:       lda t_bank,x            ; the other set
        eor #1
        sta t_nb
        txa                     ; (its codes: code_* at side * 2 + set)
        asl a
        ora t_nb
        sta t_k2
        lda t_team,x            ; t_ptr: its cells, FLAGS_TEAMS + team * 36
        sta t_c
        lda #0
        sta t_ptr + 1
        lda t_c
        ldy #5                  ; (* 32)
:       asl a
        rol t_ptr + 1
        dey
        bne :-
        sta t_f
        lda t_c                 ; + * 4
        asl a
        asl a
        clc
        adc t_f
        bcc :+
        inc t_ptr + 1
:       clc
        adc #<FLAGS_TEAMS
        sta t_ptr
        lda t_ptr + 1
        adc #>FLAGS_TEAMS
        sta t_ptr + 1
        ldy #FLAG_W * FLAG_H - 1        ; its patterns: none given a code yet
        lda #$FF
:       pha
        lda (t_ptr),y
        tax
        pla
        sta LOC,x
        dey
        bpl :-
        lda #0
        sta t_n                 ; (codes given)
        sta t_i
@cell:  ldy t_i                 ; cell i: its pattern's code, a new one the
        lda (t_ptr),y           ; first time
        tax
        lda LOC,x
        cmp #$FF
        bne :+
        jsr new_code
        sta LOC,x
:       ldy t_i
        sta CBUF,y
        tya                     ; its colour: the four bits of the byte
        lsr a                   ; 24 + i / 2 (the high ones for odd i)
        php
        clc
        adc #FLAG_W * FLAG_H
        tay
        lda (t_ptr),y
        plp
        bcc :+
        lsr a
        lsr a
        lsr a
        lsr a
:       and #15
        tax
        lda FLAGS_PAL,x
        ldy t_i
        sta CCOL,y
        iny
        sty t_i
        cpy #FLAG_W * FLAG_H
        bne @cell
        ldx t_x
        rts

; commit: side X's flag made ready (prep) on the screen - its cells'
; codes and colours, and its set of codes the one shown now. Keeps X.
commit:
        lda FLAGS_SIG
        cmp #'F'
        bne @none
        lda flag_lo,x           ; where it goes: codes, colours $400 below
        sta t_dst
        sta t_cd
        lda flag_hi,x
        sta t_dst + 1
        sec
        sbc #>(TCODE - TCOL)
        sta t_cd + 1
        stx t_x
        ldx #0
@row:   ldy #0
:       lda CBUF,x
        sta (t_dst),y
        lda CCOL,x
        sta (t_cd),y
        inx
        iny
        cpy #FLAG_W
        bne :-
        lda t_dst
        clc
        adc #40
        sta t_dst
        sta t_cd
        bcc :+
        inc t_dst + 1
        inc t_cd + 1
:       cpx #FLAG_W * FLAG_H
        bne @row
        ldx t_x
        lda t_bank,x
        eor #1
        sta t_bank,x
@none:  rts

; new_code: the next free code of the set being made ready (t_k2: side *
; 2 + set) for pattern X, its pattern copied there from FLAGS; the code
; in A. Keeps X.
new_code:
        stx t_f
        ldy t_k2
        lda t_n
        inc t_n
        cmp code_split,y        ; (the set's codes: two runs, the second
        bcs :+                  ; from code_split on)
        adc code_lo,y
        bcc @have
:       adc code_hi,y           ; (carry set: + 1)
@have:  sta t_code
        ldy #0                  ; the pattern, FLAGS + X * 8, to TFONT +
        sty t_s + 1             ; code * 8
        txa
        asl a
        rol t_s + 1
        asl a
        rol t_s + 1
        asl a
        rol t_s + 1
        clc
        adc #<FLAGS
        sta t_s
        lda t_s + 1
        adc #>FLAGS
        sta t_s + 1
        lda #0
        sta t_d + 1
        lda t_code
        asl a
        rol t_d + 1
        asl a
        rol t_d + 1
        asl a
        rol t_d + 1
        sta t_d
        lda t_d + 1
        clc
        adc #>TFONT
        sta t_d + 1
        ldy #7
@copy:  lda (t_s),y
        sta (t_d),y
        dey
        bpl @copy
        ldx t_f
        lda t_code
        rts

; the four sets of 37 codes the flags have (tools/mkflags.py: MOST): the
; home team's 8-31 and 96-108, 109-127 and 164-181; the away team's
; 182-218, 219-255 - all the font leaves free but the frames' 0-7
code_split: .byte 24, 19, 255, 255
code_lo:    .byte 8, 109, 182, 219
code_hi:    .byte 96 - 24 - 1, 164 - 19 - 1, 0, 0

; draw_names: both teams' names, in the middle of their fields, in the
; shirts they play in
draw_names:
        ldx #1
@side:  stx t_x
        lda t_team,x
        tax
        jsr rec                 ; t_ptr: its record
        ldy #NAME_W             ; its length: the spaces at its end off
:       dey
        lda (t_ptr),y
        and #$7F                ; (bit 7: a star)
        cmp #' '
        beq :-
        iny
        sty t_c
        lda #NAME_W             ; in the middle: (NAME_W - length) / 2 in
        sec
        sbc t_c
        lsr a
        sta t_f
        ldx t_x
        ldy field_at,x
        ldx #NAME_W             ; the field blank
        lda #' '
:       sta TCODE + NAME_ROW * 40,y
        iny
        dex
        bne :-
        ldx t_x                 ; then the name
        lda field_at,x
        clc
        adc t_f
        tax
        ldy #0
:       lda (t_ptr),y
        and #$7F
        sta TCODE + NAME_ROW * 40,x
        inx
        iny
        cpy t_c
        bne :-
        ldx t_x                 ; its colour: the shirt's, hires, light
        lda team_col,x          ; enough on the blue
        and #$F7
        ora #$40
        ldy field_at,x
        ldx #NAME_W
:       sta TCOL + NAME_ROW * 40,y
        iny
        dex
        bne :-
        ldx t_x
        dex
        bpl @side
        rts

ROWS        = 5                 ; the lines to choose on: length, players,
row_of:     .byte LEN_ROW, PLAYERS_ROW, MODE_ROW    ; mode, the home team,
                                                    ; the away team
label_at:   .byte HOME_COL + 1, AWAY_COL + 1
field_at:   .byte HOME_COL - 4, AWAY_COL - 4
flag_lo:    .byte <(TCODE + FLAG_ROW * 40 + HOME_COL), <(TCODE + FLAG_ROW * 40 + AWAY_COL)
flag_hi:    .byte >(TCODE + FLAG_ROW * 40 + HOME_COL), >(TCODE + FLAG_ROW * 40 + AWAY_COL)
ports_1:    .byte "  JOYSTICK IN EITHER PORT   "
PORTS_W     = * - ports_1
ports_2:    .byte " HOME: PORT 1   AWAY: PORT 2"
.assert * - ports_2 = PORTS_W, error, "ports_2: not PORTS_W"
mode_0:     .byte "MATCH   "
MODE_W      = * - mode_0
mode_1:     .byte "TRAINING"
.assert * - mode_1 = MODE_W, error, "mode_1: not MODE_W"

; a flag's frame, multicolour, in the cells round it: a line next to the
; flag - corners top left, top, top right, left, right, bottom left,
; bottom, bottom right
frame_chars:
        .byte 0, 0, 0, 0, 0, 0, 0, $03
        .byte 0, 0, 0, 0, 0, 0, 0, $FF
        .byte 0, 0, 0, 0, 0, 0, 0, $C0
        .byte $03, $03, $03, $03, $03, $03, $03, $03
        .byte $C0, $C0, $C0, $C0, $C0, $C0, $C0, $C0
        .byte $03, 0, 0, 0, 0, 0, 0, 0
        .byte $FF, 0, 0, 0, 0, 0, 0, 0
        .byte $C0, 0, 0, 0, 0, 0, 0, 0

; the cup: top left, top right, bottom left, bottom right
cup_chars:
        .byte $00, $0F, $3F, $4F, $4F, $2F, $1F, $0F
        .byte $00, $F0, $FC, $F2, $F2, $F4, $F8, $F0
        .byte $07, $03, $01, $01, $03, $07, $0F, $0F
        .byte $E0, $C0, $80, $80, $C0, $E0, $F0, $F0

name:       .byte "SIMPLE SOCCER"
NAME_LEN    = * - name
big_of:     .byte "SIMPLECOR"           ; (mkdata's LOGO_LETTERS)
; a colour each letter, warm to cool round the hues a multicolour screen
; leaves to text (0-7)
hue_of:     .byte 7, 7, 2, 2, 4, 4, 0, 6, 6, 3, 3, 5, 5
digit_of:   .byte "357"

; the lines: row, column, colour, text, 0 - $FF the end
lines:
        .byte SUB_ROW, 5, $61
        .byte "A FOOTBALL GAME FOR THE PLUS/4", 0
        .byte LEN_ROW, LINE_COL, C_TEXT
        .byte "MATCH LENGTH:  <   MIN    >", 0
        .byte PLAYERS_ROW, LINE_COL, C_TEXT
        .byte "PLAYERS:       <          >", 0
        .byte MODE_ROW, LINE_COL, C_TEXT
        .byte "MODE:          <          >", 0
        .byte LABEL_ROW, HOME_COL + 1, C_TEXT
        .byte "HOME", 0
        .byte LABEL_ROW, AWAY_COL + 1, C_TEXT
        .byte "AWAY", 0
        .byte NAME_ROW, HOME_COL - 5, C_TEXT
        .byte "<", 0
        .byte NAME_ROW, HOME_COL - 4 + NAME_W, C_TEXT
        .byte ">", 0
        .byte NAME_ROW, AWAY_COL - 5, C_TEXT
        .byte "<", 0
        .byte NAME_ROW, AWAY_COL - 4 + NAME_W, C_TEXT
        .byte ">", 0
        .byte FLAG_ROW + 1, 19, C_DIM
        .byte "VS", 0
        .byte FIRE_ROW, 9, C_FIRE0
        .byte "PRESS FIRE TO KICK OFF", 0
        .byte PORTS_ROW, PORTS_COL, C_DIM       ; (its text: show_values)
        .byte "                            ", 0
        .byte CREDIT_ROW, 8, $41
        .byte "BY Q4Z1 2026 (& CLAUDE)", 0
        .byte $FF

row_lo:
        .repeat 25, I
        .byte <(TCODE + I * 40)
        .endrepeat
row_hi:
        .repeat 25, I
        .byte >(TCODE + I * 40)
        .endrepeat

t_col:      .byte 0
t_code:     .byte 0
t_was:      .byte 0             ; the stick as it was
t_new:      .byte 0             ; what is pushed that was not
t_tick:     .byte 0
t_x:        .byte 0             ; (draw_team's, draw_names')
t_f:        .byte 0
t_c:        .byte 0
t_i:        .byte 0
t_n:        .byte 0
t_ccol:     .byte 0
t_team:     .byte 0, 3          ; the teams chosen (Argentina, Brazil: the
                                ; cyan and yellow there were before)
t_bank:     .byte 0, 0          ; each side's set of codes shown
t_nb:       .byte 0             ; (prep's: the set it fills,
t_k2:       .byte 0             ; that set's place in code_*)
t_pend:     .byte 0             ; a side's flag ready, 1 + side; 0 none

; chosen: the title's choices to the match - its length, one player or
; two, a match or training, the teams' shirts
chosen:
        ldx t_sel
        lda frames_of,x
        sta min_frames
        lda t_two
        sta two
        lda t_train
        sta train
        jsr skills
        jmp kits

; change: the choice on line X a step left (A 0) or right; carry set if a
; team changed (its shirts worked out anew)
change:
        cpx #1
        beq @players
        bcs @more
        tay                     ; the length: 3, 5, 7 minutes
        beq :+
        lda t_sel
        cmp #2
        beq @done
        inc t_sel
        clc
        rts
:       lda t_sel
        beq @done
        dec t_sel
@done:  clc
        rts
@players:
        tay                     ; one player, two
        beq :+
        lda #1
:       sta t_two
        clc
        rts
@more:  cpx #2
        bne @team
        tay                     ; a match, training
        beq :+
        lda #1
:       sta t_train
        clc
        rts
@team:  sta t_c                 ; a team: the one before or after, round
        dex                     ; the list - not the other side's
        dex
        dex
@step:  lda t_c
        beq @prev
        inc t_team,x
        lda t_team,x
        cmp #TEAMS
        bcc @other
        lda #0
        sta t_team,x
        beq @other
@prev:  dec t_team,x
        bpl @other
        lda #TEAMS - 1
        sta t_team,x
@other: txa
        eor #1
        tay
        lda t_team,x
        cmp t_team,y
        beq @step
        jsr kits
        sec
        rts

; kits: the shirts the teams play in - the home team its own, the away
; team its own unless it is the home team's colour, then its second,
; and if that is too, white (red against white) - and the colour each
; joystick's player flickers to: white, black on a light shirt
kits:
        ldx t_team
        jsr rec
        ldy #NAME_W
        lda (t_ptr),y
        sta t_k                 ; (the home team's)
        ldx t_team + 1
        jsr rec
        ldy #NAME_W
        lda (t_ptr),y
        eor t_k
        and #7
        beq :+
        lda (t_ptr),y           ; its own
        jmp @set
:       iny
        lda (t_ptr),y
        eor t_k
        and #7
        beq :+
        lda (t_ptr),y           ; its second
        jmp @set
:       lda t_k
        and #7
        cmp #1
        beq :+
        lda #$71
        bne @set
:       lda #$42
@set:   ldx #1
        jsr kit
        lda t_k
        ldx #0
kit:    pha                     ; team X in shirt A (hires: luminance, hue)
        ora #$08                ; (multicolour)
        sta team_col,x
        pla
        ldy #COL_LINE
        cmp #$60                ; light, or white: black
        bcs :+
        and #7
        cmp #1
        bne :++
:       ldy #$08
:       tya
        sta team_flk,x
        rts

; rec: t_ptr = team X's record (teams: NAME_W + 3 bytes each). Keeps X.
rec:    lda #0
        sta t_ptr + 1
        txa
        ldy #4
:       asl a                   ; * 16
        rol t_ptr + 1
        dey
        bne :-
        clc
        adc #<teams
        sta t_ptr
        lda t_ptr + 1
        adc #>teams
        sta t_ptr + 1
        rts
.assert NAME_W + 3 = 16, error, "rec: records of 16"

; skills: each player's five (play.s sk), 0-7: his place's in the team
; (prof), his team's strength - 0-4, 2 the middle: (9 - its level) / 2 -
; and a step up or down of his own, the same in every match (from the
; team's number); then his pace as Sensible Soccer has it (c107d4): how
; much faster than 896 he runs to the ball, halved - his team's (a
; computer's by its level, 200 - 23 * level; a player's 112, two
; players' 120) and 64 more for a star
skills:
        ldx #1                  ; the away team, then the home team
@side:  stx t_n
        lda t_team,x
        tax
        jsr rec
        inx                     ; (the steps' seed: never 0)
        stx t_c
        ldy #NAME_W + 2
        lda #9
        sec
        sbc (t_ptr),y
        lsr a
        sta t_f
        ldx t_n                 ; his skill's place: skill * 22 + side * 11
        ldy sk_last,x           ; + player, from the last
        ldx #5 * 11 - 1         ; prof's: skill * 11 + player
        lda #11
        sta t_i
@one:   lda t_c                 ; the step: -1, 0, 0, +1 (0, 1, 1, 2 here,
        asl a                   ; and - 3 with the level's - 2 below)
        bcc :+
        eor #$1D
:       sta t_c
        and #3
        lsr a
        adc #0
        clc
        adc prof,x
        adc t_f
        sec
        sbc #3
        bpl :+
        lda #0
:       cmp #8
        bcc :+
        lda #7
:       sta sk,y
        dey
        dec t_i                 ; (a skill's eleven done: the other side's
        bne :+                  ; passed by)
        lda #11
        sta t_i
        tya
        sec
        sbc #11
        tay
:       dex
        bpl @one
        jsr runs
        ldx t_n
        dex
        bpl @side
        rts

; runs: side t_n's pace (skills; t_ptr its record) and how fast its
; others go to their places (play.s jog_*: Sensible Soccer's c144dc - a
; computer's 1572 - 164 * level, a player's 1024)
runs:
        ldy #NAME_W + 2
        lda (t_ptr),y
        sta t_c                 ; (the level)
        ldx t_n
        lda #<1024
        sta jog_lo,x
        lda #>1024
        sta jog_hi,x
        lda t_two               ; two players: 120 either
        beq :+
        lda #120
        bne @put
:       lda #112                ; a player's: 112
        cpx #0                  ; (side 0: the joystick's)
        beq @put
        lda #<1572              ; the computer's places
        sta jog_lo,x
        lda #>1572
        sta jog_hi,x
        ldy t_c
:       lda jog_lo,x
        sec
        sbc #164
        sta jog_lo,x
        bcs :+
        dec jog_hi,x
:       dey
        bne :--
        lda #200                ; and pace
        ldy t_c
        sec
:       sbc #23
        dey
        bne :-
@put:   sta t_f
        txa                     ; (pace: skill 0, side * 11 on)
        beq :+
        lda #11
:       tax
        ldy #0
@one:   lda (t_ptr),y           ; a star 64 more
        asl a
        lda t_f
        bcc :+
        adc #64 - 1             ; (carry set)
:       sta sk,x
        inx
        iny
        cpy #11
        bne @one
        rts

sk_last:    .byte 4 * 22 + 10, 4 * 22 + 11 + 10
; each place's skills: pace, control, tackling, heading, shooting - the
; keeper, the backs (2, 5), the centre backs (3, 4), the wide midfielders
; (6, 9), the central ones (7, 8), the forwards (10, 11)
prof:   .byte 2, 4, 3, 3, 4, 5, 3, 3, 5, 4, 4
        .byte 2, 3, 2, 2, 3, 4, 5, 5, 4, 4, 4
        .byte 1, 4, 5, 5, 4, 3, 4, 4, 3, 2, 2
        .byte 2, 3, 5, 5, 3, 2, 3, 3, 2, 4, 4
        .byte 3, 2, 2, 2, 2, 3, 4, 4, 3, 5, 5

; ---- what the title keeps in the program ------------------------------------

        .bss
t_sel:      .res 1              ; the length chosen: 3, 5, 7 minutes
t_two:      .res 1              ; 1: two players
t_train:    .res 1              ; 1: training
t_row:      .res 1              ; the line the stick is on: 0 length, 1 players,
                                ; 2 mode, 3 the home team, 4 the away team
t_k:        .res 1              ; (kits')


        .segment "TITLE"        ; (the title's only: gone with it)
frames_of:  .byte 100, 167, 233         ; frames to a minute: 3, 5, 7 minutes

; The teams: a name, its shirt and its second, as the TED's colours
; (luminance * 16 + hue, the hue 0-7: multicolour cells have no more),
; Sensible Soccer's level for it, 1-8 (1 the best) and its stars there,
; of the eleven (a bit each, the keeper bit 0; c107d4) - the stars in
; bit 7 of the name's characters.
; Teams it has not: a level from how good we took them to be, 0-4 (4 1,
; 3 3, 2 5, 1 7, 0 8), and its stars most often: the keeper, 8 and 10.
; Their flags: data/flags.txt, in this order (tools/mkflags.py reads it).
.macro  team name, home, away, level, stars
.repeat NAME_W, I
.if I < .strlen(name)
        .byte .strat(name, I) | ((stars >> I) & 1) << 7
.else
        .byte ' ' | ((stars >> I) & 1) << 7
.endif
.endrepeat
        .byte home, away, level
.endmacro
WHITE       = $71
RED         = $42
DARK_RED    = $22
ORANGE      = $62               ; (a light red: there is no orange)
YELLOW      = $67
SKY         = $53               ; (cyan)
LIGHT_SKY   = $63
BLUE        = $46
DARK_BLUE   = $26
GREEN       = $15               ; (dark: the grass is green)
teams:
        team "ARGENTINA", SKY, DARK_BLUE, 1, %10001000001
        team "AUSTRALIA", YELLOW, GREEN, 7, %01010000001     ; (not in it: ours)
        team "BELGIUM", RED, YELLOW, 2, %01010000001
        team "BRAZIL", YELLOW, BLUE, 1, %11000000010
        team "CAMEROON", GREEN, YELLOW, 4, %11000000001
        team "CANADA", RED, WHITE, 7, %01010000001     ; (not in it: ours)
        team "CHILE", RED, WHITE, 5, %01010000001     ; (not in it: ours)
        team "CHINA", RED, WHITE, 8, %01010000001     ; (not in it: ours)
        team "COLOMBIA", YELLOW, DARK_BLUE, 2, %10010100000
        team "CROATIA", RED, DARK_BLUE, 6, %00011010000
        team "DENMARK", RED, WHITE, 2, %11000000001
        team "EGYPT", RED, WHITE, 7, %01010000001     ; (not in it: ours)
        team "ENGLAND", WHITE, RED, 1, %00110100000
        team "FRANCE", DARK_BLUE, WHITE, 1, %10000000100
        team "GERMANY", WHITE, RED, 1, %01010000010
        team "GHANA", WHITE, RED, 5, %01010000001     ; (not in it: ours)
        team "HUNGARY", RED, WHITE, 5, %10010100000
        team "IRAN", WHITE, RED, 7, %01010000001     ; (not in it: ours)
        team "ITALY", BLUE, WHITE, 1, %01000011000
        team "JAPAN", DARK_BLUE, WHITE, 5, %01010000001     ; (not in it: ours)
        team "MEXICO", GREEN, WHITE, 3, %01001000001
        team "MOROCCO", RED, GREEN, 5, %00110001000
        team "NETHERLANDS", ORANGE, WHITE, 1, %01000001100
        team "NEW ZEALAND", WHITE, DARK_BLUE, 8, %01010000001     ; (not in it: ours)
        team "NIGERIA", GREEN, WHITE, 7, %01000100010
        team "POLAND", WHITE, RED, 4, %11100000000
        team "PORTUGAL", DARK_RED, WHITE, 4, %01100000001
        team "SAUDI ARABIA", WHITE, GREEN, 8, %00010000110
        team "SCOTLAND", DARK_BLUE, YELLOW, 4, %01110000000
        team "SENEGAL", WHITE, GREEN, 5, %01010000001     ; (not in it: ours)
        team "SOUTH KOREA", RED, WHITE, 8, %01010000001
        team "SPAIN", RED, DARK_BLUE, 2, %01000000101
        team "SWEDEN", YELLOW, DARK_BLUE, 3, %11001000000
        team "URUGUAY", LIGHT_SKY, WHITE, 3, %01010000001     ; (not in it: ours)
        team "USA", WHITE, DARK_BLUE, 4, %01100000001
TEAMS       = (* - teams) / (NAME_W + 3)
