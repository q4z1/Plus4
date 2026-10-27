; title.s - the title before the first match: the name, the length of
; the match and one player or two to choose (the joystick up and down to
; a line, left and right on it), fire to kick off.
;
; It lies at $C000, loaded with the program but where the pictures go
; once the match is on (engine.s): it runs first, on a screen of its own
; (MAT2's and FNT2's place), and is gone after. Hires text, so that each
; cell can have any of the TED's colours. Its music is music.s's.

        .include "game.inc"
        .include "data.inc"

        .repeat 256, I          ; (text as it is, ASCII: the title's font
        .charmap I, I           ; has its characters at their ASCII codes,
        .endrepeat              ; not the Plus/4's PETSCII)

        .import joy_scan, joy, title_font, min_frames, two, team_col, team_flk
        .import mus_start, mus_frame, mus_stop
        .export title

TCOL        = MAT2              ; the title's colours,
TCODE       = MAT2 + $400       ; codes,
TFONT       = FNT2              ; characters

C_BG        = $16               ; dark blue
C_BORDER    = $06
C_TEXT      = $71               ; white
C_VALUE     = $77               ; yellow
C_DIM       = $51               ; grey: the line not chosen
C_FIRE0     = $75               ; light green, and white, by turns
C_FIRE1     = $71

SKIP        = $0FF8             ; "TS" here: a test, no title (tests/vice.py,
                                ; yape.py) - behind the KERNAL's screen,
                                ; not loaded, not cleared
LOGO_ROW    = 3
LOGO_COL    = 7
VALUE_ROW   = 10
PLAYERS_ROW = 12
HOME_ROW    = 14
AWAY_ROW    = 16
NAME_COL    = 17                ; (a team's name: so many letters at most)
NAME_W      = 13
VALUE_COL   = 25                ; (the digits)
PORTS_ROW   = 21                ; (where the joysticks go)
PORTS_COL   = 6
FIRE_ROW    = 19

        .zeropage
t_ptr:  .res 2                  ; (the title's)
t_dst:  .res 2

        .segment "TITLE"

title:
        lda #0
        sta t_sel               ; (3 minutes, one player, unless chosen)
        sta t_two
        sta t_row
        jsr skip                ; (a test: none)
        bcc :+
        rts
:       lda #0                  ; no interrupts from the TED but the
        sta TED_IRQEN           ; music's (the ROM is out, the match's is
        lda TED_IRQ             ; not set up yet)
        sta TED_IRQ
        jsr mus_start
        lda TED_SCROLLY         ; blank while it is drawn
        and #$EF
        sta TED_SCROLLY
        ldx #0                  ; the characters
:       lda title_font,x
        sta TFONT + $100,x
        lda title_font + $100,x
        sta TFONT + $200,x
        lda title_font + $200,x
        sta TFONT + $300,x
        lda title_font + $300,x
        sta TFONT + $400,x
        lda title_font + $400,x
        sta TFONT + $500,x
        lda #' '                ; the screen: blank
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
        and #$5F                ; (below: two shades darker)
        sta TCOL + (LOGO_ROW + 1) * 40 + LOGO_COL,y
        sta TCOL + (LOGO_ROW + 1) * 40 + LOGO_COL + 1,y
@gap:   inx
        cpx #NAME_LEN
        bne @logo
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
@shown: jsr kits
        jsr value
        ; the TED: hires text, 40 columns, 25 rows, the title's matrix and
        ; characters
        lda TED_CTRL2
        and #$40                ; (PAL or NTSC kept)
        ora #$88                ; 256 characters, hires, 40 columns
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
        lda #C_BORDER
        sta TED_BORDER
        lda #$1B                ; on, text, 25 rows
        sta TED_SCROLLY
        lda #0
        sta t_was
        sta t_tick
        ; the choice: left, right; fire to kick off (on its letting go)
@wait:  lda TED_LINE            ; a frame: the beam into lines 200-215 and
        sec                     ; out of them again (a line could pass
        sbc #200                ; unseen while the music's interrupt runs)
        cmp #16
        bcs @wait
:       lda TED_LINE
        sec
        sbc #200
        cmp #16
        bcc :-
        jsr mus_frame
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
        jsr value
:       lda t_new
        and #J_DOWN
        beq :+
        lda t_row
        cmp #ROWS - 1
        beq :+
        inc t_row
        jsr value
:       lda t_new               ; left, right: the choice on it
        and #J_LEFT | J_RIGHT
        beq @next
        and #J_RIGHT            ; (0: left)
        ldx t_row
        jsr change
        jsr value
@next:  jmp @wait
@go:    jsr mus_stop
        jmp chosen

; skip: carry set if a test asks for no title (SKIP), the ask taken
; back - min_frames then for 3 minutes
skip:
        lda SKIP
        cmp #'T'
        bne @no
        lda SKIP + 1
        cmp #'S'
        bne @no
        lda #0
        sta SKIP
        sta SKIP + 1
        jsr chosen
        sec
        rts
@no:    clc
        rts

; chosen: the title's choices to the match - its length, one player or
; two, the teams' shirts
chosen:
        ldx t_sel
        lda frames_of,x
        sta min_frames
        lda t_two
        sta two
        jmp kits

; change: the choice on line X a step left (A 0) or right
change:
        cpx #1
        beq @players
        bcs @team
        tay                     ; the length: 3, 5, 7 minutes
        beq :+
        lda t_sel
        cmp #2
        beq @done
        inc t_sel
        rts
:       lda t_sel
        beq @done
        dec t_sel
@done:  rts
@players:
        tay                     ; one player, two
        beq :+
        lda #1
:       sta t_two
        rts
@team:  tay                     ; a team: the one before or after, round
        beq @prev               ; the list
        inc t_team - 2,x
        lda t_team - 2,x
        cmp #TEAMS
        bcc kits
        lda #0
        sta t_team - 2,x
        beq kits
@prev:  dec t_team - 2,x
        bpl kits
        lda #TEAMS - 1
        sta t_team - 2,x
        ; (on into kits)

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

; rec: t_ptr = team X's record (teams: NAME_W + 2 bytes each)
rec:    stx t_ptr
        lda #0
        sta t_ptr + 1
        txa
        ldy #4
:       asl a                   ; * 16
        rol t_ptr + 1
        dey
        bne :-
        sec
        sbc t_ptr               ; - 1
        bcs :+
        dec t_ptr + 1
:       clc
        adc #<teams
        sta t_ptr
        lda t_ptr + 1
        adc #>teams
        sta t_ptr + 1
        rts
.assert NAME_W + 2 = 15, error, "rec: records of 15"

; value: what is chosen, shown - the length, the players, the teams'
; names in their shirts, the line the stick is on in white, the others
; grey, and where the joysticks go
value:
        ldx t_sel
        lda digit_of,x
        sta TCODE + VALUE_ROW * 40 + VALUE_COL
        lda t_two
        clc
        adc #'1'
        sta TCODE + PLAYERS_ROW * 40 + VALUE_COL
        ldx #ROWS - 1
@row:   ldy row_of,x            ; (its colours: TCOL, $400 below)
        lda row_lo,y
        clc
        adc #8
        sta t_dst
        lda row_hi,y
        adc #0
        sec
        sbc #>(TCODE - TCOL)
        sta t_dst + 1
        lda #C_DIM
        cpx t_row
        bne :+
        lda #C_TEXT
:       ldy #23
:       sta (t_dst),y
        dey
        bpl :-
        dex
        bpl @row
        lda #C_VALUE
        sta TCOL + VALUE_ROW * 40 + VALUE_COL
        sta TCOL + PLAYERS_ROW * 40 + VALUE_COL
        ldx #1                  ; the teams' names
@team:  stx t_x
        lda t_team,x
        tax
        jsr rec
        ldx t_x
        ldy row_of + 2,x
        lda row_lo,y
        clc
        adc #NAME_COL
        sta t_dst
        lda row_hi,y
        adc #0
        sta t_dst + 1
        ldy #NAME_W - 1
:       lda (t_ptr),y
        sta (t_dst),y
        dey
        bpl :-
        lda t_dst + 1
        sec
        sbc #>(TCODE - TCOL)
        sta t_dst + 1
        lda team_col,x
        and #$F7                ; (hires: no multicolour bit)
        ora #$40                ; (light enough on the blue)
        ldy #NAME_W - 1
:       sta (t_dst),y
        dey
        bpl :-
        dex
        bpl @team
        ldx #PORTS_W - 1
:       lda ports_1,x
        ldy t_two
        beq :+
        lda ports_2,x
:       sta TCODE + PORTS_ROW * 40 + PORTS_COL,x
        dex
        bpl :--
        rts

ROWS        = 4                 ; the lines to choose on
row_of:     .byte VALUE_ROW, PLAYERS_ROW, HOME_ROW, AWAY_ROW
ports_1:    .byte "  JOYSTICK IN EITHER PORT   "
PORTS_W     = * - ports_1
ports_2:    .byte " HOME: PORT 1   AWAY: PORT 2"
.assert * - ports_2 = PORTS_W, error, "ports_2: not PORTS_W"

; The teams: a name, its shirt and its second, as the TED's colours
; (luminance * 16 + hue, the hue 0-7: multicolour cells have no more)
.macro  team name, home, away
        .byte name
        .res NAME_W - .strlen(name), ' '
        .byte home, away
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
        team "ARGENTINA", SKY, DARK_BLUE
        team "AUSTRALIA", YELLOW, GREEN
        team "BELGIUM", RED, YELLOW
        team "BRAZIL", YELLOW, BLUE
        team "CAMEROON", GREEN, YELLOW
        team "CANADA", RED, WHITE
        team "CHILE", RED, WHITE
        team "CHINA", RED, WHITE
        team "COLOMBIA", YELLOW, DARK_BLUE
        team "CROATIA", RED, DARK_BLUE
        team "DENMARK", RED, WHITE
        team "EGYPT", RED, WHITE
        team "ENGLAND", WHITE, RED
        team "FRANCE", DARK_BLUE, WHITE
        team "GERMANY", WHITE, RED
        team "GHANA", WHITE, RED
        team "HUNGARY", RED, WHITE
        team "IRAN", WHITE, RED
        team "ITALY", BLUE, WHITE
        team "JAPAN", DARK_BLUE, WHITE
        team "MEXICO", GREEN, WHITE
        team "MOROCCO", RED, GREEN
        team "NETHERLANDS", ORANGE, WHITE
        team "NEW ZEALAND", WHITE, DARK_BLUE
        team "NIGERIA", GREEN, WHITE
        team "POLAND", WHITE, RED
        team "PORTUGAL", DARK_RED, WHITE
        team "SAUDI ARABIA", WHITE, GREEN
        team "SCOTLAND", DARK_BLUE, YELLOW
        team "SENEGAL", WHITE, GREEN
        team "SOUTH KOREA", RED, WHITE
        team "SPAIN", RED, DARK_BLUE
        team "SWEDEN", YELLOW, DARK_BLUE
        team "URUGUAY", LIGHT_SKY, WHITE
        team "USA", WHITE, DARK_BLUE
TEAMS       = (* - teams) / (NAME_W + 2)

name:       .byte "SIMPLE SOCCER"
NAME_LEN    = * - name
big_of:     .byte "SIMPLECOR"           ; (mkdata's LOGO_LETTERS)
; a colour each letter: warm, then cool, round the TED's hues
hue_of:     .byte 7, 8, 2, 11, 4, 6, 0, 3, 15, 5, 10, 7, 8
digit_of:   .byte "357"
frames_of:  .byte 100, 167, 233         ; frames to a minute: 3, 5, 7 minutes

; the lines: row, column, colour, text, 0 - $FF the end
lines:
        .byte 7, 5, $61
        .byte "A FOOTBALL GAME FOR THE PLUS/4", 0
        .byte VALUE_ROW, 8, C_TEXT
        .byte "MATCH LENGTH:  <   MIN >", 0
        .byte PLAYERS_ROW, 8, C_TEXT
        .byte "PLAYERS:       <       >", 0
        .byte HOME_ROW, 8, C_TEXT
        .byte "HOME:  <               >", 0
        .byte AWAY_ROW, 8, C_TEXT
        .byte "AWAY:  <               >", 0
        .byte FIRE_ROW, 9, C_FIRE0
        .byte "PRESS FIRE TO KICK OFF", 0
        .byte PORTS_ROW, PORTS_COL, C_DIM       ; (its text: value)
        .byte "                            ", 0
        .byte 23, 8, $41
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
t_sel:      .byte 0             ; the length chosen: 3, 5, 7 minutes
t_two:      .byte 0             ; 1: two players
t_row:      .byte 0             ; the line the stick is on: 0 length, 1 players,
                                ; 2 the home team, 3 the away team
t_team:     .byte 0, 3          ; the teams chosen (Argentina, Brazil: the
                                ; cyan and yellow there were before)
t_k:        .byte 0             ; (kits')
t_x:        .byte 0             ; (value's)
