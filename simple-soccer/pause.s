; pause.s - the match held, and left from there
;
; The pause: the keys RUN/STOP or P (not the joystick: in the match fire
; and the stick are the play's - the user's choice). The match stops, the
; sound with it, and a page of the ROM's characters goes over picture 2's
; place (engine.s: the pictures are worked out anew after it, eng_init):
; "PAUSE", the score and the minute, CONTINUE and QUIT - the stick up and
; down, fire let go (or the cursor keys and the space bar); RUN/STOP or P
; goes on as well. QUIT leaves the match for the title (cup.s: K_QUIT, no
; winner's page) - a league's match for the league's page, not played
; (K_ON: still to play).
;
; The page's code (PAUSEUI) is loaded with the title, after its synth,
; and the game's start copies it to $E550 (simple-soccer.cfg PAUSEM: the
; engine's cache leaves it free) - there is no room in MAIN for it.

        .setcpu "6502"
        .macpack longbranch
        .include "game.inc"
        .include "resident.inc"     ; (K_GO)

        .import joy, joy_read, krow, eng_init, frames
        .import played, anew, whistle, score, game_min
        .export pause_chk, dbg_key

SCR         = $EC00             ; the page: picture 2's place (engine.s
ATT         = $E800             ; MAT2: its codes, its colours)
TEXT_COL    = $71               ; (k_go's)
TOP         = 9                 ; the page's rows: "PAUSE",
SCORE_ROW   = 11                ; the score and the minute,
ROW_ON      = 13                ; CONTINUE,
ROW_QUIT    = 14                ; QUIT (all from TOP within 256 places)
MARK_COL    = 14                ; the column of the choice's mark

; the characters: screen codes of the ROM's set
.repeat 26, I
        .charmap 65 + I, I + 1
.endrepeat

        .code

; pause_chk: (the main loop, after joy_read) the pause if RUN/STOP or P
; is held
pause_chk:
        jsr pause_key
        bne pause
        rts

; pause: the match held - the page (PAUSEUI) till CONTINUE or QUIT
pause:  sei
        lda #0
        sta TED_IRQEN           ; (the picture's interrupt off: it stops)
        sta $FF11               ; (the sound off)
        lda TED_IRQ
        sta TED_IRQ
        jsr frame               ; (in the border: no picture half changed)
        jsr page                ; A: 0 CONTINUE, else QUIT
        beq :+
        jsr quit                ; (with the disk: never back)
:       jsr calm                ; (the key let go: else it is paused anew)
        jsr eng_init            ; (the pictures anew; it lets the interrupt
        lda frames              ; in)
        sta played
        rts

; quit: the match left - a league's for its page, not played; else for
; the title, no winner's page - or, a test without the disk, a match
; anew (play.s: no title here, the pictures are over it)
quit:   ldx #K_ON
        lda K_REQ
        cmp #K_PLAYED
        beq :+
        ldx #K_QUIT
:       stx K_REQ
        lda K_MAGIC
        cmp #K_MAGIC_0
        bne :+
        lda K_MAGIC + 1
        cmp #K_MAGIC_1
        bne :+
        jmp K_GO
:       jsr anew
        lda #1                  ; (a kick-off, the next frame)
        jmp whistle

; pause_key: A (Z clear) if P or RUN/STOP is held - P row $DF bit 1,
; RUN/STOP row $7F bit 7 - or a test says so (dbg_key)
pause_key:
        sei
        lda #$DF
        jsr krow
        and #$02
        sta p_tmp
        lda #$7F
        jsr krow
        and #$80
        ora p_tmp
        ora dbg_key
        tax
        lda #$FF
        sta KEY_ROW
        sta TED_KEYS
        cli
        txa
        rts

; calm: till the stick, fire and P are let go (p_old: none)
calm:   jsr frame
        jsr pause_key
        bne calm
        jsr joy_read
        lda joy
        bne calm
        sta p_old
        rts

; frame: till the beam is in the bottom border anew
frame:  lda TED_LINE
        cmp #205
        bne frame
:       lda TED_LINE
        cmp #205
        beq :-
        rts

        .segment "PAUSEUI"

; page: the pause's page shown, the choice with the stick: A (Z set) 0
; CONTINUE - P and RUN/STOP too - or 1 QUIT
page:   lda #PAGE_BG
        sta TED_BG
        lda #PAGE_BORDER
        sta TED_BORDER
        ldx #0
:       lda #' '
        sta SCR,x
        sta SCR + $100,x
        sta SCR + $200,x
        sta SCR + $300,x
        lda #TEXT_COL
        sta ATT,x
        sta ATT + $100,x
        sta ATT + $200,x
        sta ATT + $300,x
        inx
        bne :-
        ldx #T_N - 1            ; the words
:       ldy t_at,x
        lda t_chr,x
        sta SCR + TOP * 40,y
        dex
        bpl :-
        lda score               ; the score and the minute
        ldx #15
        jsr num
        lda #'-'
        sta SCR + SCORE_ROW * 40 + 18
        lda score + 1
        ldx #20
        jsr num
        lda game_min
        ldx #24
        jsr num
        lda #$27                ; (')
        sta SCR + SCORE_ROW * 40 + 26
        lda #$1B                ; text, 25 rows, on - k_go's: 40 columns,
        sta TED_SCROLLY         ; 128 characters, hires, the ROM's
        lda TED_CTRL2           ; characters at $D000
        and #$40
        ora #$08
        sta TED_CTRL2
        lda #$04
        sta TED_BMBASE
        lda #$D0
        sta TED_CHBASE
        lda #>ATT
        sta TED_VMBASE
        lda #0                  ; CONTINUE first
        sta p_sel
        jsr calm                ; (all let go first: fire held for it)
@loop:  ldy #'>'                ; the mark
        ldx #' '
        lda p_sel
        beq :+
        ldy #' '
        ldx #'>'
:       sty SCR + ROW_ON * 40 + MARK_COL
        stx SCR + ROW_QUIT * 40 + MARK_COL
        jsr frame
        jsr pause_key           ; P, RUN/STOP: on with the match
        bne @on
        jsr joy_read
        lda joy
        tax                     ; (now)
        eor #$FF
        and p_old               ; fire let go: the choice
        and #J_FIRE
        bne @fire
        txa                     ; a way newly pushed: up CONTINUE, down
        eor p_old               ; QUIT
        stx p_old
        sta p_tmp
        txa
        and p_tmp
        tax
        and #J_UP
        beq :+
        lda #0
        sta p_sel
:       txa
        and #J_DOWN
        beq @loop
        lda #1
        sta p_sel
        bne @loop
@on:    lda #0
        rts
@fire:  lda p_sel
        rts

; num: A (0-99) in the score's row at column X, two places, a space for
; the tens under 10
num:    ldy #'0' - 1
:       iny
        sec
        sbc #10
        bcs :-
        adc #'0' + 10
        sta SCR + SCORE_ROW * 40 + 1,x
        tya
        cmp #'0'
        bne :+
        lda #' '
:       sta SCR + SCORE_ROW * 40,x
        rts

; the words, from row TOP: each letter's place and code
.macro word row, col, text
        .repeat .strlen(text), I
        .byte (row - TOP) * 40 + col + I
        .endrepeat
.endmacro
.macro chars text
        .repeat .strlen(text), I
        .byte .strat(text, I)
        .endrepeat
.endmacro
t_at:   word TOP, 17, "PAUSE"
        word ROW_ON, 16, "CONTINUE"
        word ROW_QUIT, 16, "QUIT"
T_N     = * - t_at
t_chr:  chars "PAUSE"
        chars "CONTINUE"
        chars "QUIT"

        .segment "LOWBSS"       ; (cleared at the start)
p_tmp:  .res 1
p_sel:  .res 1                  ; the choice: 0 CONTINUE, 1 QUIT
p_old:  .res 1                  ; the stick as it was
dbg_key: .res 1                 ; (a test's RUN/STOP: $80)
