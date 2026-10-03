; briefrows.s - the briefing's text into the window rows, for title.c's
; page_show(), in the title's overlay
;
; A page is lines of text: a line's row, column, length and letters, the
; page ending in $FF. Letter k is character brief_top[k] over
; brief_bot[k]: a line takes two rows. Window row w (from 0) shows the
; page's row rr - 1 + w; rows 0 to br_rows - 1 are made, into the screen
; codes at br_d. Row 0 is the cut one: of its characters only the last
; br_k lines show, from copies of them (br_code on, br_cutend of them
; left; none when br_k is 0).
;
; In C this took a few pictures for the window's 16 rows, twice as each
; picture needs them, and the briefing stood still meanwhile, then caught
; up with steps of two lines.

        .export _brief_rows
        .export _br_d, _br_rr, _br_rows, _br_k, _br_code, _br_cutend, _br_p
        .import _brief_top, _brief_bot

FONT1   = $D800

        .segment "ENGZP": zeropage
_br_p:  .res 2                  ; the page's line; at the end its $FF
bq:     .res 2                  ; where a line's characters go (less 3)
bs:     .res 2                  ; cut copies: from, to
bo:     .res 2

        .segment "OVLDATA"
_br_d:      .word 0
_br_rr:     .byte 0
_br_rows:   .byte 0
_br_k:      .byte 0
_br_code:   .byte 0
_br_cutend: .byte 0
br_n:   .byte 0                 ; the line's length plus 3
br_h:   .byte 0
br_w:   .byte 0
br_lim: .byte 0                 ; cutc: the first line copied

        .segment "OVLCODE"

_brief_rows:
@line:  ldy #0
        lda (_br_p),y
        cmp #$FF
        bne :+
        rts
:       ldy #2
        lda (_br_p),y
        clc
        adc #3
        sta br_n
        lda #0
        sta br_h
@half:  ldy #0                  ; its window row: r + h + 1 - rr
        lda (_br_p),y
        sec
        adc br_h
        sec
        sbc _br_rr
        sta br_w
        cmp _br_rows
        bcc :+
@skip:  jmp @next
:       tax
        bne :+
        lda _br_k               ; row 0, and nothing of it showing
        beq @skip
:       lda br_w                ; bq: br_d + 40 * w + column - 3
        asl a
        asl a
        asl a                   ; 8 w (w < 16: no carry)
        sta bq
        lda #0
        sta bq+1
        lda bq
        asl a
        rol bq+1
        asl a
        rol bq+1                ; 32 w
        clc
        adc bq                  ; + 8 w
        sta bq
        bcc :+
        inc bq+1
:       ldy #1
        lda (_br_p),y
        sec
        sbc #3
        bcs :+
        dec bq+1
:       clc
        adc bq
        sta bq
        lda bq+1
        adc #0
        sta bq+1
        clc
        lda bq
        adc _br_d
        sta bq
        lda bq+1
        adc _br_d+1
        sta bq+1
        ldy #3
        lda br_w
        beq @cut
        lda br_h
        bne @bot
@top:   lda (_br_p),y           ; the top halves
        tax
        lda _brief_top,x
        sta (bq),y
        iny
        cpy br_n
        bne @top
        beq @next
@bot:   lda (_br_p),y           ; the bottom halves
        tax
        lda _brief_bot,x
        sta (bq),y
        iny
        cpy br_n
        bne @bot
        beq @next
@cut:   lda (_br_p),y           ; row 0: cut copies
        tax
        lda br_h
        beq :+
        lda _brief_bot,x
        bne :++
        beq :+++
:       lda _brief_top,x
        beq :++
:       jsr cutc
:       sta (bq),y
        iny
        cpy br_n
        bne @cut
@next:  inc br_h
        lda br_h
        cmp #2
        bcs :+
        jmp @half
:       clc                     ; the next line
        lda _br_p
        adc br_n
        sta _br_p
        bcc :+
        inc _br_p+1
:       jmp @line

; a copy of character A with only its last br_k lines, into the next
; free code; that code in A (0 when none is left). Keeps Y.
cutc:   ldx _br_cutend
        bne :+
        lda #0
        rts
:       dec _br_cutend
        ldx #0                  ; bs: FONT1 + 8 A
        stx bs+1
        asl a
        rol bs+1
        asl a
        rol bs+1
        asl a
        rol bs+1
        sta bs
        lda bs+1
        clc
        adc #>FONT1
        sta bs+1
        lda _br_code            ; bo: FONT1 + 8 code
        ldx #0
        stx bo+1
        asl a
        rol bo+1
        asl a
        rol bo+1
        asl a
        rol bo+1
        sta bo
        lda bo+1
        clc
        adc #>FONT1
        sta bo+1
        tya
        pha
        lda #8                  ; lines 8 - k on copied, the others cleared
        sec
        sbc _br_k
        sta br_lim
        ldy #7
@l:     cpy br_lim
        bcc @clr
        lda (bs),y
        bcs @put
@clr:   lda #0
@put:   sta (bo),y
        dey
        bpl @l
        pla
        tay
        lda _br_code
        inc _br_code
        rts
