; pause.s - the match held, and left from there - saved, if it is to be
;
; The pause: the keys RUN/STOP or P (not the joystick: in the match fire
; and the stick are the play's - the user's choice). The match stops, the
; sound with it, and a page of the ROM's characters goes over picture 2's
; place (engine.s: the pictures are worked out anew after it, eng_init):
; "PAUSE", the score and the minute, CONTINUE and QUIT - the stick up and
; down, fire let go (or the cursor keys and the space bar); RUN/STOP or P
; goes on as well. QUIT asks "SAVE THE MATCH?": YES, NO (RUN/STOP or P:
; on with it after all). Left, the match goes to the title (cup.s: K_QUIT,
; no winner's page) - a league's to the league's page, not played (K_ON:
; still to play); saved, to the title too, after cup.s has saved it
; (K_SAVE: SAVE_AT, game.inc) - the title's CONTINUE takes it up again
; (K_RESUME: resume, at the game's start).
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
        .import sq8_lo, sq8_hi, qs_lo, qs_hi, qn_lo, qn_hi
        .import __BSS_RUN__, __LOWBSS_RUN__, __HIBSS2_RUN__, __HIBSS2_SIZE__
        .export pause_chk, dbg_key, resume, squares, quit_a

SCR         = $EC00             ; the page: picture 2's place (engine.s
ATT         = $E800             ; MAT2: its codes, its colours)
TEXT_COL    = $71               ; (k_go's)
TOP         = 9                 ; the page's rows: "PAUSE",
SCORE_ROW   = 11                ; the score and the minute,
ROW_ON      = 13                ; CONTINUE,
ROW_QUIT    = 14                ; QUIT (all from TOP within 256 places)
MARK_COL    = 14                ; the column of the choice's mark
Z_A         = $F8               ; (sv_move, squares, page: above the
Z_B         = $FA               ; match's zero page - sv_move brings that
Z_N         = $FC               ; back - and below the KERNAL's)
Z_C         = $FE
Z_D         = $FF
Z_T         = $F6               ; (2: squares)

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
        ldx #0                  ; CONTINUE, QUIT
        jsr page
        cmp #1
        bne @on
        ldx #W_SAVE             ; SAVE THE MATCH? YES, NO
        jsr page
        bmi @on                 ; (the key: on with it)
        beq :+
        jsr quit                ; NO (with the disk: never back)
        jmp @on
:       clc                     ; YES: the match to SAVE_AT (sv_tab: first
        jsr sv_move             ; K_REQ, K_CHOK, K_CH as they are), for
        lda #K_SAVE             ; cup.s to save
        jsr quit_a
@on:    jsr calm                ; (the key let go: else it is paused anew)
        jsr eng_init            ; (the pictures anew; it lets the interrupt
        lda frames              ; in)
        sta played
        rts

; quit: the match left - a league's for its page, not played; else for
; the title, no winner's page - or, a test without the disk, a match
; anew (play.s: no title here, the pictures are over it)
quit:   lda #K_ON
        ldx K_REQ
        cpx #K_PLAYED
        beq quit_a
        lda #K_QUIT
quit_a: sta K_REQ               ; (K_SAVE: pack has kept the K_REQ before)
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

; resume: (the game's start, after the title) K_RESUME: the match saved
; back from SAVE_AT, its K_REQ with it; C set if so
resume: lda K_REQ
        cmp #K_RESUME
        beq :+
        clc
        rts
:       sei                     ; (C set: from the save)
sv_move:                        ; sv_tab's blocks to the save (C clear) or
        lda #Z_A                ; back from it (C set)
        ldx #Z_B
        bcc :+
        lda #Z_B
        ldx #Z_A
:       sta @from + 1
        stx @to + 1
        ldx #SV_N * 6
@blk:   lda sv_tab - 6,x        ; its place, the save's, the bytes
        sta Z_A
        lda sv_tab - 5,x
        sta Z_A + 1
        lda sv_tab - 4,x
        sta Z_B
        lda sv_tab - 3,x
        sta Z_B + 1
        ldy sv_tab - 2,x        ; (bytes: under 256 as Y, pages)
        lda sv_tab - 1,x
        sta Z_N
@from:  lda (Z_A),y
@to:    sta (Z_B),y
        dey
        cpy #$FF
        bne @from
        inc Z_A + 1             ; (a page on: whole pages after)
        inc Z_B + 1
        dec Z_N
        bpl @from
        txa
        sec
        sbc #6
        tax
        bne @blk
        sec
        rts

; squares: the squares' tables worked out anew (the game's start: their
; places may have held a saved match) - sq8 n * n (n 0-255), qs n * n / 4
; (0-511): + (n + 1) / 2 each, qn (n - 255)^2 / 4 (0-511): qs turned round
squares:
        lda #0
        sta Z_A                 ; qs
        sta Z_A + 1
        sta Z_B                 ; sq8
        sta Z_B + 1
        sta Z_C                 ; (the half: n over 255)
        tax
@n:     lda Z_A
        ldy Z_C
        bne @hi
        sta qs_lo,x
        lda Z_A + 1
        sta qs_hi,x
        lda Z_B
        sta sq8_lo,x
        lda Z_B + 1
        sta sq8_hi,x
        txa                     ; sq8 + 2n + 1
        sec
        adc Z_B
        sta Z_B
        bcc :+
        inc Z_B + 1
        clc
:       txa
        adc Z_B
        sta Z_B
        bcc @d
        inc Z_B + 1
        bne @d
@hi:    sta qs_lo + 256,x
        lda Z_A + 1
        sta qs_hi + 256,x
@d:     txa                     ; qs + (n + 1) / 2
        clc
        adc #1
        ror a
        ldy Z_C
        beq :+
        ora #$80                ; (n over 255: 128 more)
:       clc
        adc Z_A
        sta Z_A
        bcc :+
        inc Z_A + 1
:       inx
        bne @n
        inc Z_C
        lda Z_C
        cmp #2
        bne @n
@q:     txa                     ; qn: qs turned round at 255
        eor #$FF
        tay
        lda qs_lo,y
        sta qn_lo,x
        lda qs_hi,y
        sta qn_hi,x
        lda qs_lo + 1,x
        sta qn_lo + 256,x
        lda qs_hi + 1,x
        sta qn_hi + 256,x
        inx
        bne @q
        rts

        .rodata
; the blocks of a match a save keeps: its place, the save's, the bytes
; (under 256 or whole pages: sv_move) - K_REQ, K_CHOK, K_CH
; first (cup.s m_load: K_CHOK there tells a save); the zero page from 2
; (not the CPU's port) to the match's end; the variables; FORMS's tables,
; not K_VARS after them
.macro block place, save, bytes
        .word place, save
        .byte <(bytes - 1), >(bytes - 1)
        .assert bytes < 256 || bytes .mod 256 = 0, lderror, "pause.s: a block neither under 256 nor whole pages"
.endmacro
sv_tab: block K_REQ, SAVE_AT, K_CH + K_CH_N - K_REQ
        block $0002, SAVE_AT + SV_HEAD, $EC - 1
        block __HIBSS2_RUN__, SAVE_AT + SV_HEAD + $EC - 1, __HIBSS2_SIZE__
        block __BSS_RUN__, $B800, $0400
        block __LOWBSS_RUN__, $BC00, $0200      ; (to the test's word)
        block $FC00, $BE00, K_VARS - $FC00
SV_N    = (* - sv_tab) / 6
SV_HEAD = K_CH + K_CH_N - K_REQ
.assert SAVE_AT + SV_HEAD + $EC - 1 + __HIBSS2_SIZE__ <= $B500, lderror, "pause.s: the save's first part into TABLES"
.assert sq8_lo = SAVE_AT && qs_lo = $B800, lderror, "pause.s: the squares not where the save is"

; the pages' words: each its place from row TOP (row * 40 + column), its
; length, its letters; $FF the page's end
.macro word row, col, text
        .byte (row - TOP) * 40 + col, .strlen(text)
        .repeat .strlen(text), I
        .byte .strat(text, I)
        .endrepeat
.endmacro
w_tab:  word TOP, 17, "PAUSE"
        word SCORE_ROW, 18, "-"
        .byte (SCORE_ROW - TOP) * 40 + 26, 1, $27     ; (')
        word ROW_ON, 16, "CONTINUE"
        word ROW_QUIT, 16, "QUIT"
        .byte $FF
W_SAVE  = * - w_tab
        word TOP, 12, "SAVE THE MATCH?"
        word ROW_ON, 16, "YES"
        word ROW_QUIT, 16, "NO"
        .byte $FF

        .code
        .segment "PAUSEUI"

; page: page X (w_tab: 0 the pause's, W_SAVE the question) shown, the
; choice with the stick: A (Z set) 0 the first, 1 the second; $FF (N set)
; P or RUN/STOP - on with the match
page:   stx Z_D
        lda #PAGE_BG
        sta TED_BG
        sta TED_BORDER
.assert PAGE_BG = PAGE_BORDER, error, "pause.s: the page's border its ground's colour" 
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
        ldy Z_D                 ; the words
@word:  lda w_tab,y
        cmp #$FF
        beq @words
        tax
        iny
        lda w_tab,y
        sta Z_C
:       iny
        lda w_tab,y
        sta SCR + TOP * 40,x
        inx
        dec Z_C
        bne :-
        iny
        bne @word
@words: lda Z_D                 ; the score and the minute: the pause's
        bne @ns                 ; ("-", "'": its words)
        lda score
        ldx #15
        jsr num
        lda score + 1
        ldx #20
        jsr num
        lda game_min
        ldx #24
        jsr num
@ns:    lda #$1B                ; text, 25 rows, on - k_go's: 40 columns,
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
        lda #0                  ; the first first
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
@on:    lda #$FF
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

        .segment "LOWBSS"       ; (cleared at the start)
p_tmp:  .res 1
p_sel:  .res 1                  ; the choice: 0 CONTINUE, 1 QUIT
p_old:  .res 1                  ; the stick as it was
dbg_key: .res 1                 ; (a test's RUN/STOP: $80)
