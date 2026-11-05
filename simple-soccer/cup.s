; cup.s - the way back from a match, and the league: its page between
; its matches
;
; The match has the whole of the memory; after it, the title (title.s)
; and its flags come back from the disk. k_go (resident.s) loads this to
; CUP ($E500, up to picture 2's place) and starts it, the ROM out, no interrupt,
; "LOADING ..." on the screen - the ROM's characters, the colours at $0800
; and the codes at $0C00. It loads the flags and the title, and then
; (K_REQ):
;
;   K_TITLE   starts the game again: its title, the choices as they were
;   K_NEW     a new league (title.s, LEAGUE): the players' teams (one or
;             two) and six or seven the computer plays, at random; saved,
;             the page
;   K_ON      the league going on (CONTINUE): the page
;   K_PLAYED  a league's match just played: its result in the league; once
;             the players have played all theirs of the matchday, the
;             computer's others worked out; saved, the page
;
; The page: the matchday's results, the table, the next match (or the
; league's winner) - and with the stick: the next match, or back to the
; title. A match is chosen in K_CH as the title's choices are, with
; K_REQ K_PLAYED: the title kicks off at once (title.s).
;
; The league (L_BLOCK, game.inc): eight teams, each against each once,
; seven matchdays of four matches (sched_a, sched_b: Berger's circle,
; the players' first in each matchday, the two players' against each
; other the last). The players are teams 0 and 1 (the second only with
; two players). In a match with a player the lower team is the cyan one,
; the joystick's (title.s: side 0) - the player's, and with two the first
; player's. The computer's matches: six chances each side, each going in
; 6 in 32 times, 2 in 32 more for each level the other side is worse
; (Sensible Soccer's levels, title.s teams) - 1 to 15 in 32.
;
; The disk keeps the league in the file "league" (the boot loads it,
; boot.s): saved after each change - by the fast loader into the file as
; it is, read back and compared (as trainschedule saves its best scores);
; else the KERNAL's way, scratched and saved anew, by code at $0400 (the
; ROM in: CUPLOW). The fast loader's Plus/4 half has no saving (no room):
; its half of that is here.

        .include "game.inc"
        .include "flags.inc"    ; (FLAGS: tools/mkflags.py)
        .include "resident.inc" ; (RES_LOAD, RES_NM, RES_DST: build.sh)

        .import score, start, teams, TEAMS_N, joy_read, joy
        .import t_hook1, t_hook2, draw_menu, draw_lines, lines
        .importzp t_ptr, t_s, t_d
        .importzp T_LEN_ROW, T_MODE_ROW, T_FIRE_ROW, T_NAME_ROW, T_NAME_COL, T_FIELD_W
        .importzp T_LABEL_ROW, T_LABEL_COL, T_DROP, T_VS_ROW, T_MORE_ROW
        .importzp T_PORTS_ROW, T_CREDIT_ROW, T_SUB_ROW
        .import __WIN_LOAD__, __WIN_RUN__, __WIN_SIZE__
        .import __CUPLOW_LOAD__, __CUPLOW_RUN__, __CUPLOW_SIZE__

        .repeat 256, I          ; (text as it is, ASCII: put makes screen
        .charmap I, I           ; codes of it)
        .endrepeat

TITLE_AT    = $C000             ; the title's file (build.sh: "title")
NAME_W      = 13                ; title.s: a team's record, its name first,
REC_LEVEL   = NAME_W + 2        ; its level (1 the best) last
RANDOM_FORM = 8                 ; title.s: the formation RANDOM
COLR        = $0800             ; the screen (as k_go has made it)
CODES       = $0C00
CHECK       = $0600             ; the file read back; KERNAL's saving from
                                ; here (the ROM in: not from L_BLOCK)
CHANCES     = 6                 ; the computer's matches

C_HEAD      = $77               ; yellow
C_TEXT      = $71               ; white
C_DIM       = $41               ; grey
C_P1        = $77               ; the first player's team: yellow
C_P2        = $53               ; the second's: cyan

; the zero page: the KERNAL's own leaves these alone
c_ptr       = $D0               ; put's place on the screen
c_col       = $D2               ; its colour
c_txt       = $D3               ; text's
c_tmp       = $D5
wl_p        = c_ptr             ; (win_*: the list's end so far)

; the page's rows
ROW_HEAD    = 0
ROW_DAY     = 2
ROW_RES     = 4                 ; the matchday's four
ROW_TAB     = 9                 ; the table's head, its eight below
ROW_NEXT    = 19
ROW_DISK    = 21
ROW_MENU    = 23                ; the choices, two rows

        .segment "CUPHDR"
        .addr CUP               ; (the file's load address)

        .segment "CUP"

cup:    ldx #$FF
        txs
        cld
        stx $FF0D               ; (the TED's cursor off the screen: the
        lda #3                  ; KERNAL's IOINIT puts it at the top)
        sta $FF0C
        lda TED_LINE            ; (the dice: from the beam and the timer)
        eor $FF02
        ora #1
        sta seed
        ldx #<__CUPLOW_SIZE__   ; the files' names and the KERNAL's way
:       lda __CUPLOW_LOAD__ - 1,x   ; low (CUPLOW)
        sta __CUPLOW_RUN__ - 1,x
        dex
        bne :-
        lda #<FLAGS             ; the flags and the title back
        ldx #>FLAGS
        ldy #<n_flags
        jsr dload
        lda #<TITLE_AT
        ldx #>TITLE_AT
        ldy #<n_title
        jsr dload
        lda K_REQ
        cmp #K_NEW
        beq @new
        cmp #K_ON
        beq @page
        cmp #K_PLAYED
        beq @played
        jsr win_match           ; (K_TITLE: after a match - its winner)
        jmp restart
@new:   lda L_ON                ; one going on: kept, unless the stick
        cmp #1                  ; says it is to go (ask)
        bne :+
        jsr ask
        bcc :+
        lda #MODE_ON_T          ; (kept: CONTINUE on the title)
        sta t_train
        lda #K_TITLE
        sta K_REQ
        jmp restart
:       jsr new_league
        jmp @save
@played:
        jsr record
@save:  jsr page
        jsr save
        jmp @menu
@page:  jsr page
@menu:  jsr menu                ; C set: the next match
        bcs :+
        jsr to_title
        lda L_ON                ; (the league over: its winner)
        bne restart
        jsr win_league
        jmp restart
:       jsr to_match
        ; fall through

; restart: the game from its start (simple-soccer.s), the fast loader and
; kstub back at RES (the KERNAL's reset has cleared them)
restart:
        ldx #0
:       lda res_copy,x
        sta RES,x
        lda res_copy + $100,x
        sta RES + $100,x
        inx
        bne :-
        jmp start

; ask: (LEAGUE chosen, a league going on) its page, and that a new one
; takes its place - the disk keeps one; C set if it is to be kept (the
; choice the stick is on at first)
ask:    jsr page
        ldy #ROW_NEXT
        lda #C_HEAD
        jsr row
        lda #<t_going
        ldx #>t_going
        jsr text
        ldy #ROW_DISK
        lda #C_DIM
        jsr row
        lda #4
        jsr col
        lda #<t_one
        ldx #>t_one
        jsr text
        lda #2                  ; (the choices: keep it, a new one)
        sta m_off
        jmp menu

; ---- the winner's page ---------------------------------------------------------
;
; The title (title.s) as it is, its four lines at the top made what
; the match came to - FULL TIME and who won it, the score where "VS"
; was; or the league's winner, first and second in the flags' places -
; "PRESS FIRE TO GO ON"; fire, and it is the title. WIN's code does that
; from $E340 (free while the title runs), its hooks turned to it; what
; it writes is a list made here (w_lst): each entry the place (from
; TCODE), its colour, how many characters, them.

TCODE       = MAT2 + $400       ; (title.s: the title's codes, colours)

; win_match: the match's page - its teams as the title has them
win_match:
        jsr win_start
        lda #<t_ft
        ldx #>t_ft
        jsr wl_head
        lda score               ; who won: home, away, or neither
        cmp score + 1
        beq @draw
        ldx #0
        bcs :+
        inx
:       lda t_team,x
        jsr wl_name
        lda #<t_wins
        ldx #>t_wins
        jsr wl_cat
        jmp @line
@draw:  lda #<t_draw
        ldx #>t_draw
        jsr wl_cat
@line:  jsr wl_second
        lda #0                  ; the score where "VS" was: "2 - 1"
        sta w_n
        lda score
        jsr wl_num
        lda #<t_vs
        ldx #>t_vs
        jsr wl_cat
        lda score + 1
        jsr wl_num
        jsr wl_vs
        jmp win_end

; win_league: the league's - its first and second in the title's two
; places (the choices the title has after it)
win_league:
        jsr table
        lda order
        jsr slot_team
        sta t_team
        lda order + 1
        jsr slot_team
        sta t_team + 1
        lda #0                  ; (a match: both teams shown - title.s look)
        sta t_train
        jsr win_start
        lda #<t_wonby
        ldx #>t_wonby
        jsr wl_head
        lda t_team
        jsr wl_name
        jsr wl_second
        lda #0                  ; no "VS": first and second
        sta w_n
        jsr wl_vs
        ldx #1                  ; "1ST" and "2ND" for "HOME" and "AWAY"
:       stx w_x
        lda w_lab_r,x
        ldy #<T_LABEL_COL
        jsr wl_at
        lda #C_TEXT
        jsr wl_colour
        ldx w_x
        lda w_lab_lo,x
        ldy w_lab_hi,x
        tax
        tya
        stx c_txt
        sta c_txt + 1
        jsr wl_text
        ldx w_x
        dex
        bpl :-
        jmp win_end

; slot_team: league team A's in the title's teams
slot_team:
        tax
        lda L_TEAM,x
        rts

; win_start: the list empty, its first entries: the arrows round the
; names gone, "PRESS FIRE TO GO ON"
win_start:
        lda #<w_lst_load
        sta wl_p
        lda #>w_lst_load
        sta wl_p + 1
        ldx #3
:       stx w_x
        lda w_arr_r,x
        ldy w_arr_c,x
        jsr wl_at
        lda #C_TEXT
        jsr wl_colour
        lda #<t_blank1
        sta c_txt
        lda #>t_blank1
        sta c_txt + 1
        jsr wl_text
        ldx w_x
        dex
        bpl :-
        lda #<T_FIRE_ROW
        ldy #9
        jsr wl_at
        lda #$75                ; (title.s C_FIRE0: it flashes the row)
        jsr wl_colour
        lda #<t_goon
        sta c_txt
        lda #>t_goon
        sta c_txt + 1
        jmp wl_text

; wl_head: text A/X, yellow, in the middle of the first line
wl_head:
        sta c_txt
        stx c_txt + 1
        lda #<T_LEN_ROW
        jsr wl_mid
        lda #$77                ; (title.s C_VALUE)
        jsr wl_colour
        jmp wl_text

; wl_name: team A's name (title.s teams) into w_buf; wl_cat: text A/X
; after it
wl_name:
        jsr rec
        ldy #NAME_W             ; (to its last letter)
:       dey
        lda (c_txt),y
        and #$7F
        cmp #' '
        beq :-
        iny
        sty w_n
:       dey
        lda (c_txt),y
        and #$7F
        sta w_buf,y
        tya
        bne :-
        rts
wl_cat: sta c_txt
        stx c_txt + 1
        ldy #0
        ldx w_n
:       lda (c_txt),y
        sta w_buf,x
        beq :+
        inx
        iny
        bne :-
:       stx w_n
        rts

; wl_num: goals A after w_buf's w_n
wl_num: ldx w_n
        cmp #10
        bcc :+
        pha
        lda #'1'                ; (14 at most)
        sta w_buf,x
        inx
        pla
        sec
        sbc #10
:       ora #'0'
        sta w_buf,x
        inx
        stx w_n
        rts

; wl_second: w_buf (w_n long), white, in the middle of the third line
wl_second:
        lda #<T_MODE_ROW
        ldx w_n
        jsr wl_mid_n
        lda #$71                ; (title.s C_TEXT)
        bne wl_buf
; wl_vs: w_buf (w_n long, 0: none) in the middle of seven where "VS"
; is (blanks round it: "VS" gone)
wl_vs:  lda #<T_VS_ROW
        ldy #17
        jsr wl_at
        lda #$71                ; (title.s C_TEXT)
        jsr wl_colour
        lda #7
        jsr wl_byte
        lda #7                  ; (the blanks before it)
        sec
        sbc w_n
        lsr a
        sta w_y
        ldx #0
@char:  txa
        sec
        sbc w_y
        bcc @blank
        cmp w_n
        bcs @blank
        tay
        lda w_buf,y
        .byte $2C               ; (bit: past the next)
@blank: lda #' '
        jsr wl_byte
        inx
        cpx #7
        bne @char
        rts
; wl_buf: an entry of w_buf, w_n long, in colour A (its place: wl_at)
wl_buf: jsr wl_colour
        ldx w_n
        txa
        jsr wl_byte
        ldx #0
:       cpx w_n
        beq :+
        lda w_buf,x
        jsr wl_byte
        inx
        bne :-
:       rts

; wl_mid: the text at c_txt (0-terminated) in the middle of line A;
; wl_mid_n: X long
wl_mid: pha
        ldy #$FF
:       iny
        lda (c_txt),y
        bne :-
        tya
        tax
        pla
wl_mid_n:
        pha
        txa
        lsr a
        eor #$FF
        sec
        adc #20                 ; (20 - length / 2)
        tay
        pla
        ; fall through
; wl_at: a new entry at line A, column Y: its place
wl_at:  tax
        tya
        clc
        adc t40_lo,x
        pha
        lda t40_hi,x
        adc #0
        tax
        pla
        jsr wl_byte
        txa
        jmp wl_byte
; wl_colour: its colour A
wl_colour = wl_byte
; wl_text: the text at c_txt (0-terminated): how long, then it
wl_text:
        ldy #$FF
:       iny
        lda (c_txt),y
        bne :-
        tya
        jsr wl_byte
        ldy #0
:       lda (c_txt),y
        beq :+
        jsr wl_byte
        iny
        bne :-
:       rts
; wl_byte: A onto the list. Keeps X and Y.
wl_byte:
        sty w_y2
        ldy #0
        sta (wl_p),y
        inc wl_p
        bne :+
        inc wl_p + 1
:       ldy w_y2
        rts

; win_end: the list ended, WIN where it runs, the title's hooks to it
win_end:
        lda #$FF
        jsr wl_byte
        jsr wl_byte
        ldx #0                  ; (its first page, then the rest: no more
:       lda __WIN_LOAD__,x      ; - CUP starts after it)
        sta __WIN_RUN__,x
        inx
        bne :-
        ldx #<(__WIN_SIZE__ - $100)
:       lda __WIN_LOAD__ + $100 - 1,x
        sta __WIN_RUN__ + $100 - 1,x
        dex
        bne :-
        lda #$4C                ; (jmp)
        sta t_hook1
        sta t_hook2
        lda #<win_draw
        sta t_hook1 + 1
        lda #>win_draw
        sta t_hook1 + 2
        lda #<win_key
        sta t_hook2 + 1
        lda #>win_key
        sta t_hook2 + 2
        rts

t_ft:       .byte "FULL TIME", 0
t_wins:     .byte " WINS", 0
t_draw:     .byte "A DRAW", 0
t_wonby:    .byte "THE LEAGUE IS WON BY", 0
t_goon:     .byte "PRESS FIRE TO GO ON   ", 0   ; (over "... TO KICK OFF")
t_blank1:   .byte " ", 0
t_1st:      .byte "1ST ", 0
t_2nd:      .byte "2ND ", 0
w_lab_r:    .byte <T_LABEL_ROW, <(T_LABEL_ROW + T_DROP)
w_lab_lo:   .byte <t_1st, <t_2nd
w_lab_hi:   .byte >t_1st, >t_2nd
w_arr_r:    .byte <T_NAME_ROW, <T_NAME_ROW, <(T_NAME_ROW + T_DROP), <(T_NAME_ROW + T_DROP)
w_arr_c:    .byte <(T_NAME_COL - 1), <(T_NAME_COL + T_FIELD_W), <(T_NAME_COL - 1), <(T_NAME_COL + T_FIELD_W)
t40_lo:
        .repeat 25, I
        .byte <(I * 40)
        .endrepeat
t40_hi:
        .repeat 25, I
        .byte >(I * 40)
        .endrepeat
w_buf:  .res 32
w_n:    .res 1
w_x:    .res 1
w_y:    .res 1
w_y2:   .res 1

; ---- WIN: the winner's page in the title, at $E340 ------------------------------

        .segment "WIN"

; win_draw (t_hook1): the title drawn - its four lines blank, the line
; under the name, and the joysticks' and the credit's at the foot; what
; the list says over it
win_draw:
        ldx #39
        lda #' '
:       sta a:TCODE + 40 * T_LEN_ROW,x
        sta a:TCODE + 40 * (T_LEN_ROW + 1),x
        sta a:TCODE + 40 * (T_LEN_ROW + 2),x
        sta a:TCODE + 40 * T_MORE_ROW,x
        sta a:TCODE + 40 * T_PORTS_ROW,x
        sta a:TCODE + 40 * T_CREDIT_ROW,x
        sta a:TCODE + 40 * T_SUB_ROW,x
        dex
        bpl :-
        lda #1
        sta w_on
        lda #0
        beq w_walk

; win_key (t_hook2): C clear while the page is gone (the title's own);
; else C set - fire's letting go makes it the title: what the list
; wrote blank again, the four lines and the title's texts as they are
win_key:
        lda w_on
        bne :+
        clc
        rts
:       lda joy
        and #J_FIRE
        beq :+
        sta w_held
        sec
        rts
:       lda w_held
        bne :+
        sec
        rts
:       lda #0
        sta w_on
        lda #$80
        jsr w_walk
        lda #<lines             ; (the texts first: the menu's values then
        sta t_ptr               ; fill the joysticks' line)
        lda #>lines
        sta t_ptr + 1
        jsr draw_lines
        jsr draw_menu
        sec
        rts

; w_walk: the list's texts (A 0), or blanks where they are (A $80)
w_walk: sta w_mode
        lda #<w_lst
        sta t_s
        lda #>w_lst
        sta t_s + 1
@entry: ldy #1
        lda (t_s),y             ; (its place, from TCODE; $FFFF the end)
        cmp #$FF
        beq @done
        clc
        adc #>TCODE
        sta t_d + 1
        dey
        lda (t_s),y
        sta t_d                 ; (TCODE: at a page's start)
        ldy #2
        lda (t_s),y
        sta w_col
        iny
        lda (t_s),y
        sta w_len
        lda t_s                 ; on to its characters
        clc
        adc #4
        sta t_s
        bcc :+
        inc t_s + 1
:       ldy #0
@char:  cpy w_len
        beq @next
        lda (t_s),y
        bit w_mode
        bpl :+
        lda #' '
:       sta (t_d),y
        lda t_d + 1             ; (its colour: $400 below)
        pha
        sec
        sbc #4
        sta t_d + 1
        lda w_col
        sta (t_d),y
        pla
        sta t_d + 1
        iny
        bne @char
@next:  tya
        clc
        adc t_s
        sta t_s
        bcc @entry
        inc t_s + 1
        bne @entry
@done:  rts

w_on:   .byte 0
w_held: .byte 0
w_mode: .byte 0
w_col:  .byte 0
w_len:  .byte 0
w_lst:                          ; (made by cup.s: w_lst_load)
w_lst_load = w_lst - __WIN_RUN__ + __WIN_LOAD__
        .res 160

        .segment "CUP"
.assert <TCODE = 0, error, "w_walk: TCODE at a page's start"
.assert __WIN_SIZE__ > $100 && __WIN_SIZE__ <= $200, error, "WIN: win_end copies a page and the rest"

; new_league: the players' teams (title.s's choices: K_CH) - one, or two
; - and the computer's at random, none twice; nothing played
new_league:
        lda t_sel
        sta L_SEL
        lda t_two
        sta L_TWO
        lda t_team
        sta L_TEAM
        lda t_team + 1
        sta L_TEAM + 1
        lda t_form
        sta L_FORM
        lda t_form + 1
        sta L_FORM + 1
        ldx L_TWO               ; (the computer's from 1 or 2 on)
        inx
@team:  stx c_tmp
@any:   jsr rnd
        and #63
        cmp #<TEAMS_N
        bcs @any
        ldy #0                  ; not one already in it (those before X)
:       cmp L_TEAM,y
        beq @any
        iny
        cpy c_tmp
        bcc :-
        sta L_TEAM,x
        inx
        cpx #L_TEAMS
        bne @team
        ldx #L_MATCHES - 1
        lda #$FF
:       sta L_RES,x
        dex
        bpl :-
        lda #1
        sta L_ON
        rts

; record: the match just played (next_match's, as it was chosen) - its
; result as the score says, the cyan team the lower one (to_match); then,
; the players done with its matchday, the computer's matches of it
record:
        jsr next_match
        bcs @rts                ; (none: never)
        stx c_tmp               ; (its matchday)
        lda sched_a,y
        cmp sched_b,y
        lda score               ; (the cyan team's goals: the lower one's)
        ldx score + 1
        bcc :+
        lda score + 1           ; (the lower one is the away team)
        ldx score
:       jsr clamp
        asl a
        asl a
        asl a
        asl a
        sta c_col
        txa
        jsr clamp
        ora c_col
        sta L_RES,y
        sty last_m
        jsr next_match          ; the players' next: still this matchday?
        bcs :+
        cpx c_tmp
        beq @rts
:       ldx c_tmp               ; no: the computer's of it
        jsr day_first
@sim:   lda L_RES,y
        cmp #$FF
        bne :+
        jsr simulate
:       iny
        dex
        bne @sim
@rts:   rts

; clamp: goals A, 14 at most ($FF is "not played")
clamp:  cmp #15
        bcc :+
        lda #14
:       rts

; simulate: match Y the computer's way (both teams the computer's). Keeps
; X and Y.
simulate:
        stx sim_x
        sty sim_y
        ldx sched_a,y
        lda sched_b,y
        tay
        jsr goals               ; the home team's against the away team's
        asl a
        asl a
        asl a
        asl a
        sta sim_g
        txa                     ; and the other way round
        sty sim_t
        tay
        ldx sim_t
        jsr goals
        ora sim_g
        ldy sim_y
        sta L_RES,y
        ldx sim_x
        rts

; goals: team X's against team Y (in the league): CHANCES chances, each
; going in 6 in 32 times and 2 more for each level the other is worse.
; Keeps X and Y.
goals:  stx sim_a
        sty sim_b
        lda L_TEAM,y
        jsr level
        sta sim_l
        lda L_TEAM,x
        jsr level
        sta c_tmp
        lda sim_l               ; (theirs - ours: how much worse they are)
        sec
        sbc c_tmp
        asl a
        clc
        adc #6
        bmi :+                  ; 1 - 15 in 32
        bne :++
:       lda #1
:       cmp #16
        bcc :+
        lda #15
:       sta sim_p
        lda #0
        sta sim_n
        ldx #CHANCES
:       jsr rnd
        and #31
        cmp sim_p
        bcs :+
        inc sim_n
:       dex
        bne :--
        lda sim_n
        ldx sim_a
        ldy sim_b
        rts

; level: team A's level (title.s teams: 1 the best, 8 the worst). Keeps
; X and Y.
level:  sty lv_y
        jsr rec
        ldy #REC_LEVEL
        lda (c_txt),y
        ldy lv_y
        rts

; rec: c_txt = team A's record (title.s teams, 16 bytes each). Keeps X, Y.
rec:    pha
        sta c_txt
        lda #0
        asl c_txt               ; * 16
        rol a
        asl c_txt
        rol a
        asl c_txt
        rol a
        asl c_txt
        rol a
        sta c_txt + 1
        lda c_txt
        clc
        adc #<teams
        sta c_txt
        lda c_txt + 1
        adc #>teams
        sta c_txt + 1
        pla
        rts

; next_match: the players' next match not played: C clear and its number
; in Y, its matchday in X - C set if there is none (the league is over)
next_match:
        ldy #0
@m:     lda L_RES,y
        cmp #$FF
        bne @next
        jsr player_in
        bcc @found
@next:  iny
        cpy #L_MATCHES
        bne @m
        sec
        rts
@found: tya
        lsr a
        lsr a
        tax
        clc
        rts

; player_in: C clear if a player's team plays in match Y. Keeps X and Y.
player_in:
        lda sched_a,y
        cmp sched_b,y
        bcc :+
        lda sched_b,y           ; (the lower one: a player's if any)
:       cmp L_TWO               ; (0 a player's; with two players 1 too)
        beq :+
        bcs @no
:       clc
        rts
@no:    sec
        rts

; day_first: matchday X's first match in Y, X its four. Keeps nothing else.
day_first:
        txa
        asl a
        asl a
        tay
        ldx #4
        rts

; cksum: L_SUM for the league as it is now (all its bytes add up to 0)
cksum:  lda #0
        ldx #L_LEN - 1
:       clc
        adc L_BLOCK,x           ; (all but L_SUM)
        dex
        bne :-
        eor #$FF
        clc
        adc #1
        sta L_SUM
        rts

; to_match: the players' next match chosen as the title's choices, the
; lower team cyan (side 0: the joystick's); K_PLAYED - the title kicks it
; off at once
to_match:
        jsr next_match
        lda L_SEL
        sta t_sel
        lda #0                  ; (a match)
        sta t_train
        lda sched_a,y
        ldx sched_b,y
        cmp sched_b,y
        bcc :+
        lda sched_b,y           ; (the lower one first)
        ldx sched_a,y
:       tay
        lda #0                  ; two players: both teams theirs
        cpx L_TWO
        bne :+
        lda #1
:       sta t_two
        jsr side                ; the cyan team (Y),
        sta t_form
        lda L_TEAM,y
        sta t_team
        txa                     ; the yellow one (X)
        tay
        jsr side
        sta t_form + 1
        lda L_TEAM,y
        sta t_team + 1
        lda #K_PLAYED
        sta K_REQ
        rts

; side: team Y's formation - a player's his own (L_FORM), the computer's
; any (RANDOM)
side:   lda #RANDOM_FORM
        cpy L_TWO
        beq :+
        bcs @rts
:       lda L_FORM,y
@rts:   rts

; to_title: the title's choices as the league's (LEAGUE, or CONTINUE while
; it goes on)
to_title:
        lda L_SEL
        sta t_sel
        lda L_TWO
        sta t_two
        lda L_TEAM
        sta t_team
        lda L_TEAM + 1
        sta t_team + 1
        lda L_FORM
        sta t_form
        lda L_FORM + 1
        sta t_form + 1
        lda #2                  ; (title.s MODE_LEAGUE, MODE_ON)
        clc
        adc L_ON
        sta t_train
        lda #K_TITLE
        sta K_REQ
        rts

; ---- the page ----------------------------------------------------------------

; page: the league on the screen - the matchday's results, the table, the
; next match or the winner
page:   ldx #0                  ; blank
        lda #' ' & $3F
:       sta CODES,x
        sta CODES + $100,x
        sta CODES + $200,x
        sta CODES + $300,x
        inx
        bne :-
        ldy #ROW_HEAD
        lda #C_HEAD
        jsr row
        lda #10
        jsr col
        lda #<t_head
        ldx #>t_head
        jsr text
        ; the matchday: the last one played, else the next
        lda K_REQ
        cmp #K_PLAYED
        bne :+
        lda last_m
        lsr a
        lsr a
        bpl @day                ; (always)
:       jsr next_match
        txa
        bcc @day
        lda #6                  ; (over: the last)
@day:   sta day
        ldy #ROW_DAY
        lda #C_TEXT
        jsr row
        lda #12
        jsr col
        lda #<t_day
        ldx #>t_day
        jsr text
        lda day
        clc
        adc #'1'
        jsr put
        lda #<t_of
        ldx #>t_of
        jsr text
        ; its four matches
        ldx day
        jsr day_first
        stx c_tmp
        lda #ROW_RES
        sta r_row
@res:   sty r_m
        ldy r_row
        lda #C_TEXT
        jsr row
        ldy r_m
        lda #1
        jsr col
        lda sched_a,y
        jsr team_name
        ldy r_m
        lda #16
        jsr col
        lda L_RES,y
        cmp #$FF
        beq @notyet
        pha
        lsr a
        lsr a
        lsr a
        lsr a
        jsr num2
        lda #':'
        jsr put
        pla
        and #15
        jsr num2l
        jmp @away
@notyet:
        lda #<t_vs
        ldx #>t_vs
        jsr text
@away:  ldy r_m
        lda #23
        jsr col
        lda sched_b,y
        jsr team_name
        ldy r_m
        iny
        inc r_row
        dec c_tmp
        bne @res
        jsr table               ; the table
        ldy #ROW_TAB
        lda #C_DIM
        jsr row
        lda #<t_tab
        ldx #>t_tab
        jsr text
        lda #0
        sta r_i
@tab:   lda r_i
        clc
        adc #ROW_TAB + 1
        tay
        lda #C_TEXT
        jsr row
        ldx r_i
        lda r_i
        clc
        adc #'1'
        jsr put
        lda #'.'
        jsr put
        lda #3
        jsr col
        ldx r_i
        lda order,x
        sta r_t
        jsr team_name
        lda #17
        jsr col
        ldx r_t
        lda tb_p,x
        jsr num2
        lda #20
        jsr col
        lda tb_w,x
        jsr num2
        lda #23
        jsr col
        lda tb_d,x
        jsr num2
        lda #26
        jsr col
        lda tb_l,x
        jsr num2
        lda #29
        jsr col
        lda tb_f,x
        jsr num2
        lda #':'
        jsr put
        lda tb_a,x
        jsr num2l
        lda #36
        jsr col
        lda tb_pts,x
        jsr num2
        inc r_i
        lda r_i
        cmp #L_TEAMS
        beq :+
        jmp @tab
:       ; the next match, or the winner
        ldy #ROW_NEXT
        lda #C_TEXT
        jsr row
        jsr next_match
        bcs @over
        sty r_m
        lda #<t_next
        ldx #>t_next
        jsr text
        ldy r_m
        lda sched_a,y
        jsr team_name
        lda #<t_dash
        ldx #>t_dash
        jsr text
        ldy r_m
        lda sched_b,y
        jmp team_name
@over:  lda #0                  ; (no more: saved as over)
        sta L_ON
        lda #<t_won
        ldx #>t_won
        jsr text
        lda order
        jmp team_name

; table: tb_* for each team of the league from the results so far, and
; order: the teams from the top - points, goal difference, goals, and
; the lower team first
table:  ldx #L_TEAMS * 7 - 1    ; (tb_*: 7 rows of 8)
        lda #0
:       sta tb_p,x
        dex
        bpl :-
        ldy #L_MATCHES - 1
@m:     lda L_RES,y
        cmp #$FF
        beq @next
        pha
        lsr a
        lsr a
        lsr a
        lsr a
        sta r_hg
        pla
        and #15
        sta r_ag
        lda sched_a,y
        tax
        lda r_hg
        sta r_g1
        lda r_ag
        sta r_g2
        jsr tally
        lda sched_b,y
        tax
        lda r_ag
        sta r_g1
        lda r_hg
        sta r_g2
        jsr tally
@next:  dey
        bpl @m
        ldx #L_TEAMS - 1        ; the keys: points, then the difference
:       txa                     ; (+128), then the goals
        sta order,x
        lda tb_f,x
        sec
        sbc tb_a,x
        eor #$80
        sta tb_gd,x
        dex
        bpl :-
        ldx #0                  ; sorted: the best of those left to the
@pick:  stx r_i                 ; front, each place in turn (r_t: the
        stx r_t                 ; best's place so far)
        txa
        tay
@try:   iny
        cpy #L_TEAMS
        beq @put
        lda order,y
        sta r_k
        ldx r_t
        lda order,x
        tax
        jsr better
        bcc @try
        sty r_t
        jmp @try
@put:   ldx r_t                 ; the best to the front
        ldy r_i
        lda order,x
        pha
        lda order,y
        sta order,x
        pla
        sta order,y
        ldx r_i
        inx
        cpx #L_TEAMS
        bne @pick
        rts

; better: C set if team r_k is ahead of team X - more points, a better
; difference, more goals; all the same, the lower number. Keeps Y.
better: stx r_t2
        lda tb_pts,x
        ldx r_k
        cmp tb_pts,x            ; (C clear: X's fewer)
        bne @ne
        ldx r_t2
        lda tb_gd,x
        ldx r_k
        cmp tb_gd,x
        bne @ne
        ldx r_t2
        lda tb_f,x
        ldx r_k
        cmp tb_f,x
        bne @ne
        lda r_k                 ; (C clear: r_k the lower)
        cmp r_t2
@ne:    bcc :+
        clc
        rts
:       sec
        rts

; tally: team X's match: r_g1 its goals, r_g2 the other's. Keeps Y.
tally:  inc tb_p,x
        lda tb_f,x
        clc
        adc r_g1
        sta tb_f,x
        lda tb_a,x
        clc
        adc r_g2
        sta tb_a,x
        lda r_g1
        cmp r_g2
        beq @draw
        bcc @lost
        inc tb_w,x
        lda tb_pts,x
        adc #3 - 1              ; (carry set)
        sta tb_pts,x
        rts
@draw:  inc tb_d,x
        inc tb_pts,x
        rts
@lost:  inc tb_l,x
        rts

; ---- writing on the page -------------------------------------------------------

; row: row Y, in colour A, from its first column
row:    sta c_col
        lda row_lo,y
        sta c_ptr
        lda row_hi,y
        sta c_ptr + 1
        lda #0
        sta c_x
        rts

; col: on to column A of the row
col:    sta c_x
        rts

; put: character A (ASCII) there, in colour c_col; on to the next column.
; Keeps X and Y.
put:    sty c_y
        ldy c_x
        and #$3F                ; (the ROM's screen codes: the capitals,
        sta (c_ptr),y           ; the digits, the signs)
        lda c_ptr + 1
        pha
        sec
        sbc #>(CODES - COLR)
        sta c_ptr + 1
        lda c_col
        sta (c_ptr),y
        pla
        sta c_ptr + 1
        inc c_x
        ldy c_y
        rts

; text: the 0-terminated text at A/X. Keeps Y.
text:   sta c_txt
        stx c_txt + 1
        sty c_y2
        ldy #0
:       lda (c_txt),y
        beq :+
        jsr put
        iny
        bne :-
:       ldy c_y2
        rts

; team_name: league team A's name, the players' in their colours (the
; colour back after it). Keeps Y.
team_name:
        sty c_y2
        tax
        lda c_col
        pha
        cpx #0
        bne :+
        lda #C_P1
:       cpx #1
        bne :+
        ldy L_TWO
        beq :+
        lda #C_P2
:       sta c_col
        lda L_TEAM,x
        jsr rec
        ldy #NAME_W             ; (its length: to its last letter)
:       dey
        lda (c_txt),y
        and #$7F                ; (bit 7: a star)
        cmp #' '
        beq :-
        iny
        sty c_tmp3
        ldy #0
:       lda (c_txt),y
        jsr put
        iny
        cpy c_tmp3
        bne :-
        pla
        sta c_col
        ldy c_y2
        rts

; num2: A (0-99) in two columns, right-aligned; num2l: left-aligned.
; Keep X and Y.
num2:   jsr tens
        bne :+
        lda #' '
        bne :++
:       ora #'0'
:       jsr put
        lda c_tmp2
        ora #'0'
        jmp put
num2l:  jsr tens
        beq :+
        ora #'0'
        jsr put
:       lda c_tmp2
        ora #'0'
        jsr put
        lda c_tmp3              ; (a blank after one digit)
        bne :+
        lda #' '
        jmp put
:       rts
; tens: A's tens in A (Z set if none), its ones in c_tmp2
tens:   stx c_x2
        ldx #0
:       cmp #10
        bcc :+
        sbc #10
        inx
        bne :-
:       sta c_tmp2
        stx c_tmp3
        ldx c_x2
        lda c_tmp3              ; (Z: no tens)
        rts

; ---- the choice -----------------------------------------------------------------

; menu: the next match or back to the title, by the stick (up, down),
; fire on its letting go; C set: the next match. With the league over
; only the title.
menu:   lda L_ON
        sta m_n                 ; (0: one choice)
        lda #0
        sta m_sel
        sta m_was
:       jsr joy_read            ; (fire still held: let go of first)
        lda joy
        and #J_FIRE
        bne :-
@draw:  ldx #0                  ; the choices, the one chosen white
@line:  txa
        clc
        adc #ROW_MENU
        tay
        lda #C_DIM
        cpx m_sel
        bne :+
        lda #C_TEXT
:       jsr row
        lda #10
        jsr col
        lda #'>'
        cpx m_sel
        beq :+
        lda #' '
:       jsr put
        lda #' '
        jsr put
        stx m_x
        txa
        ldy m_n
        bne :+
        lda #1                  ; (over: the title only)
:       clc
        adc m_off
        tay
        lda m_lo,y
        ldx m_hi,y
        jsr text
        ldx m_x
        lda m_n
        beq @wait
        inx
        cpx #2
        bne @line
@wait:  jsr frame
        jsr joy_read
        lda joy
        tax
        eor #$FF
        and m_was               ; (let go of: held before, not now)
        stx m_was
        and #J_FIRE
        bne @go
        txa                     ; (up, down: the other one, if there is)
        and #J_UP | J_DOWN
        beq @wait
        lda m_n
        beq @wait
        lda m_sel
        eor #1
        sta m_sel
:       jsr frame               ; (till let go)
        jsr joy_read
        lda joy
        and #J_UP | J_DOWN
        bne :-
        jmp @draw
@go:    lda m_n                 ; C set: the next match (the first)
        beq :+
        lda #0
        cmp m_sel
        rts
:       clc
        rts

; frame: till the beam is below the picture, once
frame:  lda TED_LINE
        cmp #210
        bne frame
:       lda TED_LINE
        cmp #210
        beq :-
        rts

; ---- the disk -----------------------------------------------------------------------

; dload: to A/X the file named at Y (in CUPLOW, low for the KERNAL: its
; name 0-terminated); till it works, the border red
dload:  sta dl_lo
        stx dl_hi
        sty dl_name
        lda #>__CUPLOW_RUN__
        sta dl_name + 1
@again: lda K_FAST
        beq @kernal
        lda dl_name
        sta RES_NM
        lda dl_name + 1
        sta RES_NM + 1
        lda dl_lo
        sta RES_DST
        lda dl_hi
        sta RES_DST + 1
        jsr RES_LOAD
        bcc @ok
        bcs @red
@kernal:
        jsr k_load
        bcc @ok
@red:   lda #$32
        sta TED_BORDER
        jmp @again
@ok:    lda #0
        sta TED_BORDER
        rts

; save: the league to the disk ("SAVING ...", then what came of it)
save:   jsr cksum
        ldy #ROW_DISK
        lda #C_DIM
        jsr row
        lda #13
        jsr col
        lda #<t_saving
        ldx #>t_saving
        jsr text
        ldx #L_LEN - 1          ; (a copy low: for the KERNAL, and to
:       lda L_BLOCK,x           ; compare it with what is read back)
        sta save_buf,x
        dex
        bpl :-
        lda K_FAST
        beq @kernal
        jsr fsave
        bcs @failed
        lda #<n_league          ; read back
        sta RES_NM
        lda #>n_league
        sta RES_NM + 1
        lda #<CHECK
        sta RES_DST
        lda #>CHECK
        sta RES_DST + 1
        jsr RES_LOAD
        bcs @failed
        ldx #L_LEN - 1
:       lda CHECK,x
        cmp save_buf,x
        bne @failed
        dex
        bpl :-
        bmi @saved
@kernal:
        ldx #L_LEN - 1
:       lda save_buf,x
        sta CHECK,x
        dex
        bpl :-
        jsr k_save
        bcs @failed
@saved: lda #<t_saved
        ldx #>t_saved
        bne :+
@failed:
        lda #<t_failed
        ldx #>t_failed
:       pha
        ldy #ROW_DISK
        lda #C_DIM
        jsr row
        lda #5
        jsr col
        pla
        jmp text

; The fast loader's saving, the Plus/4's half (trainschedule's scores.s):
; the request - the name as in the directory, then 1, save - then for each
; sector the drive's count, and that many bytes; 0 when all is written.
; The waits counted for the CPU's fastest; slower they are only longer,
; which the drive waits for.
PORT    = $01
FREE    = $08                   ; both lines left high, tape motor off
CLKLO   = $0A                   ; CLK pulled
DATLO   = $09                   ; DATA pulled

fsave:  lda #<save_buf
        sta @src+1
        lda #>save_buf
        sta @src+2
        lda #DATLO              ; asking
        sta PORT
:       bit PORT                ; till the drive lets go of CLK
        bvc :-
        ldy #0
:       lda fs_name,y
        jsr fput
        iny
        cpy #17
        bne :-
        lda #FREE
        sta PORT
@block: jsr fbusy               ; how many the drive wants for a sector,
:       bit PORT                ; once it is ready
        bvc :-
        jsr fget
        beq @done               ; 0: all written
        cmp #$FF
        beq @fail
        sta fcount
:       bit PORT                ; till the drive lets go of DATA
        bpl :-
@src:   lda $FFFF
        jsr fput
        inc @src+1
        bne :+
        inc @src+2
:       dec fcount
        bne @src
        lda #FREE               ; DATA free for the drive's next count
        sta PORT
        jmp @block
@done:  jsr fbusy
        clc
        rts
@fail:  jsr fbusy
        sec
        rts

; a byte to the drive, lowest bit first (fastload.s's put). Keeps Y.
fput:   sta fbits
        lda #4
        sta fpairs
@bit:   lsr fbits
        lda #FREE >> 1
        rol
        sta PORT                ; the bit, CLK still high
        ora #CLKLO
        sta PORT                ; CLK low: the drive reads it
        jsr fwait
        lsr fbits
        lda #CLKLO >> 1
        rol
        sta PORT                ; the bit, CLK still low
        and #<~$02
        sta PORT                ; CLK high: the drive reads it
        jsr fwait
        dec fpairs
        bne @bit
        rts

fbusy:  bit PORT
        bvs fbusy
        rts

fwait:  ldx #10                 ; with jsr and rts: 61 cycles, 34 us
:       dex
        bne :-
        rts

; a byte from the drive, lowest bit first (fastload.s's get). Z set if 0.
fget:   ldy #9
:       dey
        bne :-
        ldx #4
@bit:   lda PORT
        ldy #CLKLO
        sty PORT
        asl
        ror fbits
        ldy #8
:       dey
        bne :-
        lda PORT
        ldy #FREE
        sty PORT
        asl
        ror fbits
        ldy #8
:       dey
        bne :-
        dex
        bne @bit
        lda fbits
        rts

; rnd: a byte at random (a 16-bit Galois LFSR)
rnd:    lsr seed + 1
        ror seed
        bcc :+
        lda seed + 1
        eor #$B4
        sta seed + 1
:       lda seed
        rts

; ---- what it says, the league's order ------------------------------------------

t_head:     .byte "SIMPLE SOCCER LEAGUE", 0
t_day:      .byte "MATCHDAY ", 0
t_of:       .byte " OF 7", 0
t_vs:       .byte " - ", 0
t_tab:      .byte "   TEAM           P  W  D  L GOALS PTS", 0
t_next:     .byte "NEXT: ", 0
t_dash:     .byte " - ", 0
t_won:      .byte "THE LEAGUE IS WON BY ", 0
t_play:     .byte "PLAY THE NEXT MATCH", 0
t_back:     .byte "BACK TO THE TITLE", 0
t_saving:   .byte "SAVING ...", 0
t_saved:    .byte "THE LEAGUE IS SAVED ON THE DISK", 0
t_failed:   .byte "COULD NOT SAVE THE LEAGUE ON THE DISK", 0
m_lo:       .byte <t_play, <t_back, <t_keep, <t_anew   ; (the league over:
m_hi:       .byte >t_play, >t_back, >t_keep, >t_anew   ; the title only; m_off 2: ask's)
t_keep:     .byte "KEEP THIS LEAGUE", 0
t_anew:     .byte "START A NEW LEAGUE", 0
t_going:    .byte "A NEW LEAGUE WOULD TAKE THIS ONE", 0
t_one:      .byte "THE DISK KEEPS ONE LEAGUE ONLY", 0
MODE_ON_T   = 3                 ; (title.s MODE_ON: CONTINUE)

row_lo:
        .repeat 25, I
        .byte <(CODES + I * 40)
        .endrepeat
row_hi:
        .repeat 25, I
        .byte >(CODES + I * 40)
        .endrepeat

; the matches, matchday by matchday: home team, away team (Berger's
; circle, the players' teams 0 and 1 meeting on the last day)
sched_a:    .byte 7, 1, 2, 4,  3, 5, 2, 6,  0, 1, 4, 7,  6, 2, 5, 4
            .byte 0, 1, 3, 7,  4, 1, 2, 6,  0, 5, 3, 7
sched_b:    .byte 0, 3, 6, 5,  0, 1, 7, 4,  5, 6, 2, 3,  0, 1, 3, 7
            .byte 2, 4, 6, 5,  0, 7, 3, 5,  1, 2, 4, 6
.assert * - sched_b = L_MATCHES, error, "sched_b: not L_MATCHES"

; the fast loader's request to save "league" (the name as the directory
; has it: PETSCII, padded), then 1: save
fs_name:    .byte $4C, $45, $41, $47, $55, $45, $A0, $A0
            .byte $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, 1

; resident.s's RES as the boot left it: put back before the game starts
res_copy:   .incbin "build/resident.bin", 0, $200

; its variables
seed:   .word 0
last_m: .res 1                  ; the match just played (record)
day:    .res 1                  ; the page's matchday
r_row:  .res 1
r_m:    .res 1
r_i:    .res 1
r_t:    .res 1
r_t2:   .res 1
r_k:    .res 1
r_hg:   .res 1
r_ag:   .res 1
r_g1:   .res 1
r_g2:   .res 1
c_x:    .res 1
c_y:    .res 1
c_y2:   .res 1
c_x2:   .res 1
c_tmp2: .res 1
c_tmp3: .res 1
m_n:    .res 1
m_sel:  .res 1
m_was:  .res 1
m_off:  .byte 0                 ; menu's texts: 0 the page's, 2 ask's
m_x:    .res 1
sim_x:  .res 1
sim_y:  .res 1
sim_a:  .res 1
sim_b:  .res 1
sim_g:  .res 1
sim_t:  .res 1
sim_l:  .res 1
sim_p:  .res 1
sim_n:  .res 1
lv_y:   .res 1
dl_name: .res 2
dl_lo:  .res 1
dl_hi:  .res 1
fbits:  .res 1
fpairs: .res 1
fcount: .res 1
save_buf: .res L_LEN
tb_p:   .res L_TEAMS            ; (table: 7 rows, in this order)
tb_w:   .res L_TEAMS
tb_d:   .res L_TEAMS
tb_l:   .res L_TEAMS
tb_f:   .res L_TEAMS
tb_a:   .res L_TEAMS
tb_pts: .res L_TEAMS
tb_gd:  .res L_TEAMS
order:  .res L_TEAMS

; the choices as title.s has them (K_CH)
t_sel       = K_CH
t_two       = K_CH + 1
t_train     = K_CH + 2
t_team      = K_CH + 3
t_form      = K_CH + 5

; ---- the KERNAL's way: run at $0400, the ROM in -------------------------------

        .segment "CUPLOW"

SETLFS  = $FFBA
SETNAM  = $FFBD
OPEN    = $FFC0
CLOSE   = $FFC3
CHKIN   = $FFC6
CLRCHN  = $FFCC
CHRIN   = $FFCF
LOAD    = $FFD5
SAVE    = $FFD8

; k_load: file dl_name (here, below $8000) to dl_lo/dl_hi; C set if it
; failed
k_load: ldy #$FF                ; (its length)
        lda dl_name
        sta @len + 1
        lda dl_name + 1
        sta @len + 2
:       iny
@len:   lda $FFFF,y
        bne :-
        lda K_DEV               ; (under the ROM: read before it comes in)
        sta @dev + 1
        lda dl_lo
        sta @lo + 1
        lda dl_hi
        sta @hi + 1
        tya
        ldx dl_name
        ldy dl_name + 1
        sta $FF3E               ; the ROM in
        jsr SETNAM
        lda #1
@dev:   ldx #8
        ldy #0
        jsr SETLFS
        lda #0
@lo:    ldx #0
@hi:    ldy #0
        jsr LOAD
        sta $FF3F               ; (C kept)
        rts

; k_save: CHECK saved as "league", the old one scratched first (the
; 1541's save with replace is not to be trusted); then the drive's status
; read - that also waits till it has really written the file. C set if it
; failed.
k_save: lda K_DEV
        sta @d1 + 1
        sta @d2 + 1
        sta @d3 + 1
        sta $FF3E               ; the ROM in
        lda #15
@d1:    ldx #8
        ldy #15
        jsr SETLFS
        lda #n_scratch_end - n_scratch
        ldx #<n_scratch
        ldy #>n_scratch
        jsr SETNAM
        jsr OPEN
        lda #15
        jsr CLOSE
        lda #0
@d2:    ldx #8
        ldy #0
        jsr SETLFS
        lda #6
        ldx #<n_league
        ldy #>n_league
        jsr SETNAM
        lda #<CHECK
        sta c_tmp
        lda #>CHECK
        sta c_tmp + 1
        lda #<c_tmp
        ldx #<(CHECK + L_LEN)
        ldy #>(CHECK + L_LEN)
        jsr SAVE
        bcs @fail
        lda #15
@d3:    ldx #8
        ldy #15
        jsr SETLFS
        lda #0
        jsr SETNAM
        jsr OPEN
        bcs @fail
        ldx #15
        jsr CHKIN
        jsr CHRIN
        sta @st
        jsr CHRIN
        sta @st + 1
        jsr CLRCHN
        lda #15
        jsr CLOSE
        lda @st
        cmp #'0'
        bne @fail
        lda @st + 1
        cmp #'0'
        bne @fail
        clc
        bcc @out
@fail:  sec
@out:   sta $FF3F               ; the ROM out (C kept)
        rts
@st:    .res 2

; the files' names (PETSCII capitals: as ASCII's)
n_flags:    .byte "FLAGS", 0
n_title:    .byte "TITLE", 0
n_scratch:  .byte "S0:"
n_league:   .byte "LEAGUE", 0
n_scratch_end = * - 1
.assert L_LEN = 42, error, "L_LEN: build.sh makes the file league that long"
.assert L_END <= $FFF6, error, "the league: into what the KERNAL's RAMTAS writes"
