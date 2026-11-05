; title.s - the title before the first match: the name, the length of
; the match, one player or two, and the two teams with their flags to
; choose (the joystick up and down to a line, left and right on it), fire
; to kick off. A second page of the four lines at the top (TEAM SETTINGS,
; right on it; back: left on MAIN SETTINGS) has each team's formation.
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
; FLAGS, with the title's font): their cells' patterns, all of them once,
; which the two flags shown have copied into the codes the font leaves
; free - each side two sets of 18: a flag chosen is made ready in the set
; not shown (prep),
; and only its 18 cells change over (commit), just below the picture's
; last line - nothing is ever drawn half. A line chosen only changes
; colours. No team plays itself: choosing passes the other side's by.

        .include "game.inc"
        .include "data.inc"
        .include "flags.inc"    ; (tools/mkflags.py: the flags' file's parts)
        .include "resident.inc" ; (K_GO: build.sh)

        .repeat 256, I          ; (text as it is, ASCII: the title's font
        .charmap I, I           ; has its characters at their ASCII codes,
        .endrepeat              ; not the Plus/4's PETSCII)

        .import joy_scan, joy, min_frames, two, train, team_col, team_flk, sk
        .import lib_x0l, lib_xs, lib_y0l, lib_ys, lib_hh
        .import tac_x0l, tac_x0h, tac_xs, tac_y0l, tac_y0h, tac_ys
        .import sk_duel, jog_lo, jog_hi, kp_gl, kp_gh, kp_sl, kp_sh, kp_dn, kp_dv
        .import mus_start, mus_frame, mus_stop
        .export title, teams, TEAMS_N
        .export t_hook1, t_hook2, draw_menu, draw_lines, lines   ; (cup.s: the winner)
        .exportzp t_ptr, t_s, t_d
        .export T_LEN_ROW = LEN_ROW, T_MODE_ROW = MODE_ROW, T_FIRE_ROW = FIRE_ROW
        .export T_NAME_ROW = NAME_ROW, T_NAME_COL = NAME_COL, T_FIELD_W = FIELD_W
        .export T_LABEL_ROW = LABEL_ROW, T_LABEL_COL = LABEL_COL, T_DROP = TEXT_DROP
        .export T_VS_ROW = FLAG_ROW + FLAG_H, T_MORE_ROW = MORE_ROW
        .export T_PORTS_ROW = PORTS_ROW, T_CREDIT_ROW = CREDIT_ROW, T_SUB_ROW = SUB_ROW

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
MORE_ROW    = 9                 ; (TEAM SETTINGS, MAIN SETTINGS)
FORMS       = 9                 ; formations to choose: data/tactics.txt's
                                ; eight, then RANDOM
LINE_COL    = 7                 ; (their text,
VALUE_COL   = 24                ; the digits, the mode)
FLAG_ROW    = 11                ; the home flag's first row, 3 rows of 6
FLAG_W      = 6                 ; cells - the away one's DROP rows lower:
FLAG_H      = 3                 ; no line of the picture has both, so each
DROP        = FLAG_H + 1        ; has a second shared colour of its own
FLAG_REC    = FLAG_W * FLAG_H * 3 / 2   ; a team's: cells, colours
HOME_COL    = 5                 ;   the home team's first column
AWAY_COL    = 29                ;   the away team's
LABEL_ROW   = FLAG_ROW          ; "HOME" beside the home flag, "AWAY" beside
NAME_ROW    = FLAG_ROW + 1      ; the away one (TEXT_DROP rows lower), each over
NAME_COL    = 14                ; its name, a field of FIELD_W - all in the
FIELD_W     = 12                ; middle between the flags, as "VS"
NAME_W      = 13                ; (a name in teams: the longest 12 so far)
LABEL_COL   = NAME_COL + (FIELD_W - 4) / 2
TEXT_DROP   = DROP + 1          ; (the away side's words at its flag's foot,
                                ; the home side's at its top: "VS" between)
FIRE_ROW    = 20
PORTS_ROW   = 22                ; (where the joysticks go)
PORTS_COL   = 6
CREDIT_ROW  = 24
LINE_0      = 3                 ; the raster line of the text's first row
SPLIT_HOME  = LINE_0 + (FLAG_ROW - 1) * 8           ; (the frame's row
SPLIT_AWAY  = LINE_0 + (FLAG_ROW + DROP - 1) * 8    ; above each flag,
SPLIT_BELOW = LINE_0 + (FLAG_ROW + DROP + FLAG_H) * 8   ; and below)

                                ; (FLAGS: the patterns, FLAGS_TEAMS each
                                ; team's 18 cells and 9 colour bytes,
                                ; FLAGS_PAL the palette, FLAGS_SIG "F" if
                                ; they are there - a test has none -,
                                ; FLAGS_2ND each team's second shared
                                ; colour, FLAGS_FONT the title's font)
LOC         = $E200             ; (prep's: a pattern's code, 256 bytes,
CBUF        = $E300             ; the cells' codes and colours made ready)
CCOL        = $E320
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
        sta t_row
        jsr k_init              ; (the choices as last time)
        lda K_REQ               ; a league's match (cup.s): kicked off at
        cmp #K_PLAYED           ; once, as cup.s has chosen it
        bne :+
        jmp chosen
:       jsr skip                ; (a test: none)
        bcc :+
        rts
:       jsr joy_scan            ; (fire held from the match before: let
        lda joy                 ; go of first - its letting go kicks off)
        and #J_FIRE
        bne :-
        lda TED_SCROLLY         ; blank while it is drawn (the boot's
        and #$EF                ; screen goes now)
        sta TED_SCROLLY
        jsr mus_start           ; (its interrupt the only one: the ROM is
                                ; out, the match's is not set up yet)
        ldx #0                  ; the characters (from the flags' file:
:       lda FLAGS_FONT,x        ; codes 32 on), the frames', the screen
        sta TFONT + $100,x      ; blank
        lda FLAGS_FONT + $100,x
        sta TFONT + $200,x
        lda FLAGS_FONT + $200,x
        sta TFONT + $300,x
        lda FLAGS_FONT + $300,x
        sta TFONT + $400,x
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
        adc #96                 ; (carry clear: under 64)
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
        ldx #1                  ; between the words a cup, in the letters'
                                ; gold (its characters: tools/mkdata.py)
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
        jsr draw_lines
        jmp title_on

; draw_lines: the lines at t_ptr (lines' form: row, column, colour, the
; text, 0 - $FF the end)
draw_lines:
@line:  ldy #0
        lda (t_ptr),y           ; row ($FF: no more)
        bmi @done
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
@done:  rts

; title_on: the title drawn on, and then chosen on
title_on:
        jsr draw_menu
        jsr draw_frames
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
        jsr look                ; (the teams as the mode has them)
        jsr t_hook1             ; (cup.s: the winner's page over it)
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
        bcc :+
        jmp @go
:       jsr joy_scan            ; (joy_read, but the music not held up)
        jsr t_hook2             ; (cup.s: the winner's page, its stick -
        bcc :+                  ; C set: nothing for the title)
        jmp @next
:       jsr look                ; (the teams as the mode has them)
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
        beq :+
        jmp @go
:       lda t_new               ; up, down: a line up or down
        and #J_UP
        beq @down
        lda t_row
        beq @down
        dec t_row
        jsr hole                ; (the second page's empty line: over it)
        bne :+
        dec t_row
:       jsr show_rows
@down:  lda t_new
        and #J_DOWN
        beq @side
        lda t_row
        cmp t_last              ; (the away team's: not in a league of one)
        beq @side
        inc t_row
        jsr hole
        bne :+
        inc t_row
:       jsr show_rows
@side:  lda t_new               ; left, right: the choice on it
        and #J_LEFT | J_RIGHT
        beq @next
        and #J_RIGHT            ; (0: left)
        ldx t_row
        jsr change
        bcc :+
        lda t_row               ; (a team: its flag made ready, in with the
        sec                     ; next picture's end)
        sbc #MENU_N
        tax
        jsr prep
        inx
        stx t_pend
:       jsr show_values
@next:  lda TED_LINE            ; (out of the window before the next)
        sec
        sbc #200
        cmp #16
        bcc @next
        jsr split
        jmp @wait
@go:    jsr mus_stop
        lda t_train             ; the league: its page from the disk
        cmp #MODE_LEAGUE        ; (cup.s) - a new one or the one going on
        bcc :+
        sbc #MODE_LEAGUE - K_NEW    ; (carry set)
        sta K_REQ
        jmp K_GO
:       lda #K_TITLE            ; a match, training: back here after
        sta K_REQ
        jmp chosen

; k_init: the choices kept from the match before (K_CH), the first time
; the first of each - 3 minutes, one player, a match - and Argentina
; against Brazil (the cyan and yellow there were before); the modes there
; are to choose: the league only from the disk, going on with one only
; if there is one (L_ON)
k_init:
        lda K_CHOK
        cmp #K_MAGIC_0
        bne :+
        lda K_CHOK + 1
        cmp #K_MAGIC_1
        beq @kept
:       ldx #K_CH_N - 1
:       lda ch_first,x
        sta K_CH,x
        dex
        bpl :-
        lda #K_MAGIC_0
        sta K_CHOK
        lda #K_MAGIC_1
        sta K_CHOK + 1
@kept:  ldx #MODE_TRAIN         ; (no disk: no league)
        lda K_MAGIC
        cmp #K_MAGIC_0
        bne @none
        lda K_MAGIC + 1
        cmp #K_MAGIC_1
        bne @none
        inx                     ; (a new league)
        lda L_ON
        cmp #1
        bne @set
        inx                     ; (and the one going on)
        bne @set
@none:  lda #K_TITLE            ; (a test: nothing of cup.s)
        sta K_REQ
@set:   stx t_modes
        cpx t_train             ; (the one last time no more: a match)
        bcs :+
        lda #MODE_MATCH
        sta t_train
:       rts

; look: the teams as the mode has them - in a league of one player no
; away team (its flag and frame, its name, "VS" gone, its line not to be
; chosen: t_last), "PLAYER 1" over his; with two players "PLAYER 1" and
; "PLAYER 2" over the names, else "HOME" and "AWAY"; drawn anew only
; when that changes
look:   ldx #1                  ; (the away team shown,
        ldy #0                  ; HOME and AWAY)
        lda t_two               ; (two players: theirs)
        bne @pl
        lda t_train
        cmp #MODE_LEAGUE
        bne @set
        dex                     ; (a league of one: no away team)
@pl:    iny                     ; (the players)
@set:   cpx t_shown
        bne @redo
        cpy t_lab
        bne @redo
        rts
@redo:  stx t_shown
        sty t_lab
        txa
        clc
        adc #ROWS - 2
        sta t_last
        lda #<lines             ; the texts again (HOME, AWAY, VS, the

        sta t_ptr               ; arrows)
        lda #>lines
        sta t_ptr + 1
        jsr draw_lines
        lda t_lab
        beq @away
        ldx #7                  ; PLAYER 1, PLAYER 2
:       lda t_player,x
        sta TCODE + LABEL_ROW * 40 + LABEL_COL - 2,x
        sta TCODE + (LABEL_ROW + TEXT_DROP) * 40 + LABEL_COL - 2,x
        dex
        bpl :-
        inc TCODE + (LABEL_ROW + TEXT_DROP) * 40 + LABEL_COL + 5
@away:  lda t_shown
        bne @show
        ldx #AWAY_COL + FLAG_W - NAME_COL + 1   ; (from the name's "<" to
        lda #' '                                ; the frame's right edge)
:       sta TCODE + (FLAG_ROW + DROP - 1) * 40 + NAME_COL - 1,x
        sta TCODE + (FLAG_ROW + DROP) * 40 + NAME_COL - 1,x
        sta TCODE + (FLAG_ROW + DROP + 1) * 40 + NAME_COL - 1,x
        sta TCODE + (FLAG_ROW + DROP + 2) * 40 + NAME_COL - 1,x
        sta TCODE + (FLAG_ROW + DROP + 3) * 40 + NAME_COL - 1,x
        dex
        bpl :-
        bmi @both
@show:  jsr draw_frames         ; (its frame, its flag, its name again)
        ldx #1
        jsr prep
        inx
        stx t_pend
@both:  jsr show_values
        jmp show_rows
t_player:   .byte "PLAYER 1"
.assert LABEL_ROW + TEXT_DROP = FLAG_ROW + DROP + 1 && NAME_ROW + TEXT_DROP = FLAG_ROW + DROP + 2, error, "look: the away team's rows"
.assert FLAG_ROW + DROP - 1 = FLAG_ROW + FLAG_H, error, "look: VS in the away frame's top row"

; t_hook1, t_hook2: as the title is loaded nothing (none, C clear); after
; a match cup.s makes them jumps to its winner's page (cup.s WIN): drawn
; once the title is, and the stick its own till fire leaves it
t_hook1:
        rts
        .byte 0, 0
t_hook2:
        clc
        rts
        .byte 0

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
; four lines' text at the top, a team's label and its arrows
show_rows:
        ldx #ROWS - 1
@row:   lda #C_DIM
        cpx t_row
        bne :+
        lda #C_TEXT
:       cpx #MENU_N
        bcs @team
        pha                     ; (TCOL: $400 below the codes)
        txa
        clc
        adc #LEN_ROW
        tay
        pla
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
@team:  ldy field_at - MENU_N,x  ; "<" and ">" round the name (its label,
                                ; HOME, PLAYER 1 ..., white throughout)
        sta TCOL + NAME_ROW * 40 - 1,y
        sta TCOL + NAME_ROW * 40 + FIELD_W,y
@next:  dex
        bpl @row
        rts

; show_values: the length's and the players' digits, the mode (training:
; no length, "-"), and where the joysticks go - on the second page the
; teams' formations
show_values:
        lda t_page
        bne @forms
        ldx t_sel
        lda digit_of,x
        ldy t_train
        cpy #MODE_TRAIN
        bne :+
        lda #'-'
:       sta TCODE + LEN_ROW * 40 + VALUE_COL
        lda t_two
        clc
        adc #'1'
        sta TCODE + PLAYERS_ROW * 40 + VALUE_COL
        tya                     ; (the mode's name: MODE_W letters)
        asl a
        asl a
        asl a
        ora #MODE_W - 1
        tay
        ldx #MODE_W - 1
:       lda modes,y
        sta TCODE + MODE_ROW * 40 + VALUE_COL,x
        lda #C_VALUE
        sta TCOL + MODE_ROW * 40 + VALUE_COL,x
        dey
        dex
        bpl :-
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
@forms: ldx #0                  ; (X: the home line's place, the away's
        ldy t_form              ; 40 on)
        jsr @name
        ldx #40
        ldy t_form + 1
@name:  tya                     ; (its name: FORM_W letters)
        asl a
        sta t_c
        asl a
        adc t_c
        tay
        lda #FORM_W
        sta t_i
:       lda form_names,y
        sta TCODE + LEN_ROW * 40 + VALUE_COL,x
        lda #C_VALUE
        sta TCOL + LEN_ROW * 40 + VALUE_COL,x
        inx
        iny
        dec t_i
        bne :-
        rts

; draw_menu: the four lines at the top, the page's (t_page)
draw_menu:
        ldx #MENU_W - 1
        lda #' '
:       sta TCODE + LEN_ROW * 40 + LINE_COL,x
        sta TCODE + PLAYERS_ROW * 40 + LINE_COL,x
        sta TCODE + MODE_ROW * 40 + LINE_COL,x
        sta TCODE + MORE_ROW * 40 + LINE_COL,x
        dex
        bpl :-
        ldx t_page
        lda menu_lo,x
        sta t_ptr
        lda menu_hi,x
        sta t_ptr + 1
        jsr draw_lines
        ldx t_page              ; "<" and ">" round the values
        ldy arrows_n,x
:       tya
        sec
        sbc #40
        tay
        lda #'<'
        sta TCODE + LEN_ROW * 40 + VALUE_COL - 2,y
        lda #'>'
        sta TCODE + LEN_ROW * 40 + LINE_COL + MENU_W - 1,y
        tya
        bne :-
        jsr show_values
        jmp show_rows

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
        lda #<FLAGS_TEAMS       ; t_ptr: its cells, FLAGS_TEAMS + team *
        sta t_ptr               ; FLAG_REC
        lda #>FLAGS_TEAMS
        sta t_ptr + 1
        ldy t_team,x
        beq @at
:       lda t_ptr
        clc
        adc #FLAG_REC
        sta t_ptr
        bcc :+
        inc t_ptr + 1
:       dey
        bne :--
@at:
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
        ldy t_team,x            ; (its second shared colour: split)
        lda FLAGS_2ND,y
        sta t_2nd,x
@none:  rts

; split: $FF17 each flag's second shared colour while it is drawn - from
; the frame's row above it - and red again below them (the logo's); each
; written in the right border (anywhere else the TED shows a white pixel
; there). Interrupts held off for that line at most.
split:
        ldx #0
@one:   lda TED_LINE            ; (its row: from its first line, 6 lines)
        sec
        sbc split_at,x
        cmp #6
        bcs @one
        lda t_2nd,x
        sei
:       ldy $FF1E               ; (the beam's place across: the border)
        cpy #147
        bcc :-
        sta TED_COL2
        cli
        inx
        cpx #3
        bne @one
        rts

; new_code: the next free code of the set being made ready (t_k2: side *
; 2 + set) for pattern X, its pattern copied there from FLAGS; the code
; in A. Keeps X.
new_code:
        stx t_f
        ldy t_k2
        lda t_n
        inc t_n
        clc                     ; (the set's codes)
        adc code_lo,y
        sta t_code
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
code_lo:    .byte 8, 132, 150, 168  ; (18 each: the font has 32-131)

; draw_names: both teams' names, in the middle of their fields, in the
; shirts they play in
draw_names:
        ldx t_shown             ; (the away team's not in a league of one)
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
        lda #FIELD_W             ; in the middle: (FIELD_W - length) / 2 in
        sec
        sbc t_c
        lsr a
        sta t_f
        ldx t_x
        ldy field_at,x
        ldx #FIELD_W             ; the field blank
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
        ldx #FIELD_W
:       sta TCOL + NAME_ROW * 40,y
        iny
        dex
        bne :-
        ldx t_x
        dex
        bpl @side
        rts

MENU_N      = 4                 ; the lines to choose on: four at the top
ROWS        = MENU_N + 2        ; (the page's), the home team, the away team
MENU_W      = 27
menu_lo:    .byte <menu_1, <menu_2
menu_hi:    .byte >menu_1, >menu_2
team22:     .byte 0, 22         ; (each team's part of tac_*)
FORM_W      = 6
form_names: .byte "4-4-2 5-4-1 4-5-1 5-3-2 3-5-2 4-3-3 ATTACKDEFENDRANDOM"
.assert * - form_names = FORMS * FORM_W, error, "form_names"
; the pages' four lines (as lines)
; (draw_menu puts the arrows round the values, arrows_n lines of them)
menu_1: .byte LEN_ROW, LINE_COL, C_TEXT
        .byte "MATCH LENGTH:", 0
        .byte LEN_ROW, VALUE_COL + 2, C_TEXT
        .byte "MIN", 0
        .byte PLAYERS_ROW, LINE_COL, C_TEXT
        .byte "PLAYERS:", 0
        .byte MODE_ROW, LINE_COL, C_TEXT
        .byte "MODE:", 0
        .byte MORE_ROW, LINE_COL, C_TEXT
        .byte "TEAM SETTINGS >", 0
        .byte $FF
menu_2: .byte LEN_ROW, LINE_COL, C_TEXT
        .byte "HOME FORMATION", 0
        .byte PLAYERS_ROW, LINE_COL, C_TEXT
        .byte "AWAY FORMATION", 0
        .byte MORE_ROW, LINE_COL, C_TEXT
        .byte "< MAIN SETTINGS", 0
        .byte $FF
arrows_n:   .byte 3 * 40, 2 * 40
field_at:   .byte NAME_COL, TEXT_DROP * 40 + NAME_COL       ; (the away side's lower)
.assert TEXT_DROP * 40 + NAME_COL + FIELD_W < 256, error, "field_at"
flag_lo:    .byte <(TCODE + FLAG_ROW * 40 + HOME_COL), <(TCODE + (FLAG_ROW + DROP) * 40 + AWAY_COL)
flag_hi:    .byte >(TCODE + FLAG_ROW * 40 + HOME_COL), >(TCODE + (FLAG_ROW + DROP) * 40 + AWAY_COL)
split_at:   .byte SPLIT_HOME, SPLIT_AWAY, SPLIT_BELOW
ports_1:    .byte "  JOYSTICK IN EITHER PORT   "
PORTS_W     = * - ports_1
ports_2:    .byte " HOME: PORT 1   AWAY: PORT 2"
.assert * - ports_2 = PORTS_W, error, "ports_2: not PORTS_W"
modes:      .byte "MATCH   "    ; (t_train: MODE_*)
MODE_W      = * - modes
            .byte "TRAINING"
            .byte "LEAGUE  "
            .byte "CONTINUE"
.assert * - modes = MODE_W * 4, error, "modes: not MODE_W each"
.assert MODE_W = 8, error, "modes: 8 letters each (show_values)"
MODE_MATCH  = 0
MODE_TRAIN  = 1
MODE_LEAGUE = 2                 ; a new league (cup.s: K_NEW)
MODE_ON     = 3                 ; the league going on (K_ON)
ch_first:   .byte 0, 0, MODE_MATCH, 0, 3, 0, 0  ; (k_init: K_CH's order)

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
        .byte LABEL_ROW, LABEL_COL - 2, C_TEXT  ; (8 wide: "PLAYER 1" there
        .byte "  HOME  ", 0                     ; in a league of two, look)
        .byte LABEL_ROW + TEXT_DROP, LABEL_COL - 2, C_TEXT
        .byte "  AWAY  ", 0
        .byte NAME_ROW, NAME_COL - 1, C_TEXT
        .byte "<", 0
        .byte NAME_ROW, NAME_COL + FIELD_W, C_TEXT
        .byte ">", 0
        .byte NAME_ROW + TEXT_DROP, NAME_COL - 1, C_TEXT
        .byte "<", 0
        .byte NAME_ROW + TEXT_DROP, NAME_COL + FIELD_W, C_TEXT
        .byte ">", 0
        .byte FLAG_ROW + FLAG_H, 19, C_DIM      ; (between the flags)
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
t_bank:     .byte 0, 0          ; each side's set of codes shown
t_page:     .byte 0             ; the four lines' page: 0 the first
t_modes:    .byte 0             ; the last mode there is to choose (k_init)
t_shown:    .byte 1             ; look's: 1 the away team shown, 0 not
t_lab:      .byte 0             ;   1 "PLAYER 1" / "2", 0 "HOME" / "AWAY"
t_last:     .byte ROWS - 1      ;   the last line to choose
t_2nd:      .byte FLAG_RED, FLAG_RED, FLAG_RED  ; $FF17 while each side's
                                ; flag is drawn (commit), and below them
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
        ldy #0                  ; (training: MODE_TRAIN only)
        lda t_train
        cmp #MODE_TRAIN
        bne :+
        iny
:       sty train
        jsr skills
        jsr formations
        jmp kits

; formations: each team's formation chosen (RANDOM: one of the eight, as
; the beam has it) copied from lib_* into its part of play.s's tac_*
formations:
        ldx #1
@team:  stx t_x
        lda t_form,x
        cmp #FORMS - 1
        bcc :+
        lda $FF1E               ; (RANDOM)
        and #7
:       sta t_c                 ; its place in lib_*: * 22
        asl a
        sta t_f
        asl a
        asl a
        adc t_f
        adc t_c
        asl a
        tay
        lda team22,x            ; its team's in tac_*
        tax
        lda #22
        sta t_i
@copy:  lda lib_x0l,y
        sta tac_x0l,x
        lda lib_xs,y
        sta tac_xs,x
        lda lib_y0l,y
        sta tac_y0l,x
        lda lib_ys,y
        sta tac_ys,x
        lda lib_hh,y            ; (the high bytes: x's in bits 0-1, y's in
        pha                     ; 2-3)
        and #3
        sta tac_x0h,x
        pla
        lsr a
        lsr a
        sta tac_y0h,x
        iny
        inx
        dec t_i
        bne @copy
        ldx t_x
        dex
        bpl @team
        rts

; hole: Z set if t_row is the second page's empty line (MODE_ROW's)
hole:
        lda t_page
        beq :+
        lda t_row
        cmp #2
        rts
:       lda #1                  ; (Z clear)
        rts

; change: the choice on line X a step left (A 0) or right; carry set if a
; team changed (its shirts worked out anew)
change:
        cpx #MENU_N
        bcc :+
        jmp @team
:
        ldy t_page
        bne @page2
        cpx #3
        beq @to2
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
        tay                     ; a match, training, the league (k_init:
        beq :+                  ; what there is)
        lda t_train
        cmp t_modes
        bcs @done
        inc t_train
        clc
        rts
:       lda t_train
        beq @done
        dec t_train
        clc
        rts
@to2:   tay                     ; TEAM SETTINGS: right, the second page
        beq @done
        lda #1
@page:  sta t_page
        jsr draw_menu
        clc
        rts
@page2: cpx #3                  ; MAIN SETTINGS: left, the first page
        bne @form
        tay
        bne @done
        tya
        beq @page
@form:  tay                     ; a team's formation: the one before or
        beq :+                  ; after
        lda t_form,x
        cmp #FORMS - 1
        beq @done
        inc t_form,x
        clc
        rts
:       lda t_form,x
        beq @done
        dec t_form,x
        clc
        rts
@team:  sta t_c                 ; a team: the one before or after, round
        txa                     ; the list - not the other side's
        sec
        sbc #MENU_N
        tax
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
; team the first of its own, its second, white, red and dark blue that is
; not like the home team's (alike) - and the colour each joystick's
; player flickers to: his own a shade lighter or darker (kit)
kits:
        ldx t_team
        jsr rec
        ldy #NAME_W
        lda (t_ptr),y
        sta t_k                 ; (the home team's)
        ldx t_team + 1
        jsr rec
        ldy #NAME_W
        lda (t_ptr),y           ; its own, its second
        sta t_alt
        iny
        lda (t_ptr),y
        sta t_alt + 1
        ldy #0
:       lda t_alt,y
        jsr alike
        bne @set
        iny
        cpy #4
        bne :-                  ; (dark blue the last: never like a home
@set:   lda t_alt,y             ; shirt white and red are both like)
        ldx #1
        jsr kit
        lda t_k
        ldx #0
kit:    pha                     ; team X in shirt A (hires: luminance, hue)
        ora #$08                ; (multicolour)
        sta team_col,x
        pla
        cmp #$40                ; flickering: light, $30 darker; dark, $40
        bcs :+                  ; lighter - a dark green as light as the
        adc #$40                ; grass ($45) lighter still
        cmp #$55
        bne :++
        lda #$65
        bne :++
:       sbc #$30
:       ora #$08
        sta team_flk,x
        rts

; alike: Z clear if shirt A looks unlike the home team's (t_k) - not the
; same colour, nor as light within one shade. Keeps Y.
alike:
        sta t_c
        eor t_k
        and #7
        beq @no
        lda t_c                 ; |luminance - luminance| > 1
        lsr a
        lsr a
        lsr a
        lsr a
        sta t_c
        lda t_k
        lsr a
        lsr a
        lsr a
        lsr a
        sec
        sbc t_c
        bcs :+
        eor #$FF
        adc #1
:       cmp #2
        bcs @yes
@no:    lda #0
        rts
@yes:   lda #1
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

; skills: each player's pace and each keeper (runs, keeps): as Sensible
; Soccer has them for the team's level and stars
skills:
        ldx #1                  ; the away team, then the home team
@side:  stx t_n
        lda t_team,x
        tax
        jsr rec
        jsr runs
        jsr keeps
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
@one:   lda (t_ptr),y           ; (at the ball: the level, a star one
        asl a                   ; more - play.s duel)
        lda t_c
        adc #0
        sta sk_duel,x
        lda (t_ptr),y           ; a star 64 more
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

; keeps: side t_n's keeper as Sensible Soccer's (c12d26, play.s kp_*):
; by his team's level - a star a level better - going for the ball
; at 1056 - 32 * level, edging across at 272 - 16 * level, guessing 0-7
; or else level - 1; a player's team's as level 4 but guessing 4 (two
; players': 3, 2) - its star keeper guessing his own but 0-5
keeps:
        ldx t_n
        ldy #0
        lda (t_ptr),y           ; (the keeper's a star: bit 7)
        and #$80
        sta t_i
        lda #8
        sta kp_dn,x
        lda t_two
        bne @two
        cpx #0                  ; (side 0: the joystick's)
        bne @cpu
        lda #4
        tay
        bne @hum
@two:   lda #3
        ldy #2
@hum:   bit t_i
        bpl @set
        pha
        lda #6
        sta kp_dn,x
        pla
        bne @set
@cpu:   lda t_c                 ; (the level)
        bit t_i
        bpl :+
        cmp #2
        bcc :+
        sbc #1                  ; (carry set)
:       tay
        dey
@set:   sta t_f
        tya
        sta kp_dv,x
        ldy t_f
        lda #<1056
        sta kp_gl,x
        lda #>1056
        sta kp_gh,x
        lda #<272
        sta kp_sl,x
        lda #>272
        sta kp_sh,x
@lv:    lda kp_gl,x
        sec
        sbc #32
        sta kp_gl,x
        bcs :+
        dec kp_gh,x
:       lda kp_sl,x
        sec
        sbc #16
        sta kp_sl,x
        bcs :+
        dec kp_sh,x
:       dey
        bne @lv
        rts

; ---- what the title keeps in the program ------------------------------------

; the choices, kept from match to match (game.inc K_CH, resident.s)
t_sel       = K_CH              ; the length chosen: 3, 5, 7 minutes
t_two       = K_CH + 1          ; 1: two players
t_train     = K_CH + 2          ; the mode: MODE_*
t_team      = K_CH + 3          ; the teams chosen (2)
t_form      = K_CH + 5          ; each team's formation (form_names) (2)

        .bss
t_row:      .res 1              ; the line the stick is on: 0 length, 1 players,
                                ; 2 mode, 3 the home team, 4 the away team
t_k:        .res 1              ; (kits')


        .segment "TITLE"        ; (the title's only: gone with it)
frames_of:  .byte 100, 167, 233         ; frames to a minute: 3, 5, 7 minutes
t_alt:      .byte 0, 0, $71, $42, $26   ; (kits': the away team's own two,
                                        ; then white, red, dark blue)

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
TEAMS_N     = TEAMS             ; (cup.s: the league's)
.assert TEAMS <= 64, error, "teams: cup.s picks them from 64"
