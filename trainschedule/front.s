; front.s - before a game: the title picture, the choice of a map, and
; the disk they come from
;
; The disk has the program, the title picture in two packed files (exomizer
; "raw", unpacked by unpack.s as in Stardew Pond), a catalogue MAPS and a
; file per map, MAP1, MAP2 ..., each its song, its track and its timetable
; (tools/mklevel.py). Files are loaded the screen off and our interrupt
; stopped (eng_blank): by the fast loader the boot program left at $FA00
; (boot.s, fastload.s) if the drive runs its other half, else by the
; KERNAL, as in Stardew Pond.
;
; The choice of a map itself is an overlay (trainschedule.cfg: OVL), in a
; file of its own, "help", with the page of help its bulb opens (help.s):
; loaded to $B000 before the choice - the song, the bands and the
; characters' copy there belong to a level, which is not on then.
;
; The KERNAL needs $07D8-$07E7 to load (measured for Paradroid); the game
; keeps routes there, so those 16 bytes are kept from the start and put
; back before every load.

        .include "game.inc"
        .macpack longbranch

        .export _level_buf, disk_init, title, choose_map, load_map
        .export catalogue, unlock_next, _unlocked, map_song
        .export cm_sel, show_maps, help_read, text_screen

        .import _eng_blank, _eng_unblank, _eng_irqon, _eng_hits, _eng_text, _txt_o
        .import _txt_col, _eng_romfont, _eng_bmtext, _title_credits
        .import _title_ready, _eng_mode, _title_bg, _title_mc, _title_split
        .import _eng_keepirq, _mus_start, _mus_quiet, _mus_song, _mus_off
        .import _mus_toggle, _unpack, _unp_dst, _scrn, _colr, _ptr_on
        .import _tk_start, _tk_on, _eng_choice, _eng_loading, _eng_clear
        .import help_hits, bulb_place

SCRATCH = $E000                 ; packed files, 3 KB: the trains' rings and
                                ; the route search's tables, free here
BITMAP  = $C000                 ; the title, over the characters and the map
MUSIC   = $E800                 ; the title's song (music.inc)
TITLE_M = $0800                 ; the title's colours, then its own colours,
                                ; and its hires part's first row
; the fast loader (fastload.s)
FL_LOAD  = $FA00
FL_MAGIC = $FA03
FL_NAME  = $FA07
FL_ADDR  = $FA09
KERNAL_LOAD_RAM = $07D8         ; what the KERNAL needs to load
MAX_LIST = 7                    ; maps in the list: rows 6, 8 ... 18
OVL_ADDR = $B000                ; the overlay (trainschedule.cfg)
OVL_TITLE = $EC00               ; and where it comes packed (build.sh: 3 KB)
OVL_LEVEL = $C000
BULB_MARK = 35                  ; the column of the bulb's mark (help.s)

        .segment "GAMEZP": zeropage
fp1:    .res 2                  ; a text of the catalogue
ld_name: .res 2                 ; load's file name

        .bss
dev:        .res 1              ; the drive
kernal_07d8: .res 16
title_song: .res 1              ; 1: the title's song is there (its file)
help_ok:    .res 1              ; 1: the overlay is there (its file)
cat_ok:     .res 1              ; 1: the catalogue is there, loaded early
help_read:  .res 1              ; 1: the page of help has been read
fl_on:      .res 1              ; the fast loader runs
nmaps:      .res 1
ld_addr:    .res 2              ; load's: where to, the name's length
ld_len:     .res 1
ld_k:       .res 1
ld_t:       .res 1
cm_sel:     .res 1              ; choose_map's
cm_m:       .res 1
cm_h:       .res 1
cm_i:       .res 1
cm_k:       .res 1
cm_n:       .res 1              ; maps in the list
cur_map:    .res 1              ; the map being played, 1 on
map_song:   .res 1              ; 1: it has a song (at SONG_BUF)
cp_n:       .res 2              ; copy's
sm_i:       .res 1
        .segment "STKBSS"       ; (trainschedule.cfg)
sm_line:    .res 41             ; a row of the list (sm_blank first)
map_text:   .res 16 * 3 * 2     ; per map its name and two lines about it
        .segment "MAPHI"        ; above the map (trainschedule.cfg)
_level_buf: .res 1024           ; the map being played, as loaded
        .segment "SONGBUF"      ; (trainschedule.cfg)
song_buf:   .res SONG_MAX       ; its song
        .assert song_buf = SONG_BUF, lderror, "the song's place: game.inc and trainschedule.cfg"

        .segment "LOWDATA"      ; (early in the program: below the ROM)
; file names: PETSCII, as ca65 makes lower case for the Plus/4
n_maps:     .byte "maps", 0
n_music:    .byte "music", 0
n_title_b:  .byte "title.b", 0
n_title_m:  .byte "title.m", 0
n_map:      .byte "map0", 0, 0  ; (the number put in)
n_help:     .byte "help", 0
        .assert * < $8000, error, "file names under the ROM: the KERNAL cannot read them"

        .rodata
bit_of:     .byte 1, 2, 4, 8, 16, 32, 64, 128

        .segment "OVLDATA"      ; (the overlay)
; text on screen: screen codes
.repeat 26, I
        .charmap $41 + I, $01 + I
.endrepeat
head:       .byte "TRAIN SCHEDULE", 0
pick:       .byte "CHOOSE A MAP", 0
locked:     .byte "LOCKED: GET A STAR ON THE MAP ABOVE", 0
lock_body:  .byte LOCK_CODE, LOCK_CODE + 1, 0
lock_shut:  .byte LOCK_CODE + 2, LOCK_CODE + 3, 0
lock_open:  .byte LOCK_CODE + 4, LOCK_CODE + 5, 0
help_t1:    .byte "HOW TO PLAY, AND ALL THE KEYS", 0
help_t2:    .byte "FIRE TO READ IT - OR PRESS HELP", 0
music_t:    .byte "< MUSIC ON  >  F1", 0
.repeat 26, I
        .charmap $41 + I, $41 + I
.endrepeat

        .data
; the maps that can be chosen, a bit each (map 1: bit 0); a star on one
; opens the next (unlock_next). The test build sets it (tests/start.sh).
_unlocked:  .byte 1

        .code

; ---- the disk ----------------------------------------------------------------------

; disk_init: at the start, before the game touches $0400-$07FF
disk_init:
        lda $AE                 ; the drive the program came from
        cmp #8
        bcs :+
        lda #8
:       sta dev
        ldx #15
:       lda KERNAL_LOAD_RAM,x
        sta kernal_07d8,x
        dex
        bpl :-
        ; the loader there, and the drive holding CLK as its half does
        ; while it waits: then it is running
        ldx #0
        lda FL_MAGIC
        cmp #$52
        bne @off
        lda FL_MAGIC+1
        cmp #$53
        bne @off
        lda FL_MAGIC+2
        cmp #$46
        bne @off
        lda FL_MAGIC+3
        cmp #$4C
        bne @off
        lda $01
        and #$40
        bne @off
        inx
@off:   stx fl_on
        stx _eng_keepirq        ; the fast loader does not mind the
        ldx #0                  ; interrupt: the music goes on
        lda MUSIC               ; the boot program loaded the title's song
        cmp #$4D
        bne :+
        inx
:       stx title_song
        rts

; load: file ld_name to ld_addr; the screen off already. Until it works: a
; red border while there is no disk.
load:   ldy #$FF                ; the name's length
:       iny
        lda (ld_name),y
        bne :-
        sty ld_len
@again: lda #3
        sta ld_k
@try:   lda fl_on
        beq @kernal
        lda ld_name
        sta FL_NAME
        lda ld_name+1
        sta FL_NAME+1
        lda ld_addr
        sta FL_ADDR
        lda ld_addr+1
        sta FL_ADDR+1
        jsr FL_LOAD
        bcc @done
        bcs @fail
@kernal:
        ldx #15
:       lda kernal_07d8,x
        sta KERNAL_LOAD_RAM,x
        dex
        bpl :-
        jsr kload
        bcc @done
@fail:  dec ld_k
        bne @try
        lda #$32
        sta $FF19
        jmp @again
@done:  rts

.macro  loadto name, addr
        lda #<(name)
        sta ld_name
        lda #>(name)
        sta ld_name+1
        lda #<(addr)
        sta ld_addr
        lda #>(addr)
        sta ld_addr+1
        jsr load
.endmacro

; load_packed: file ld_name to SCRATCH, unpacked to A/X; load_packed_at:
; to ld_addr
load_packed:
        ldy #<SCRATCH
        sty ld_addr
        ldy #>SCRATCH
        sty ld_addr+1
load_packed_at:
        sta _unp_dst
        stx _unp_dst+1
        jsr load
        lda ld_addr
        ldx ld_addr+1
        jmp _unpack

; the screen for text again: the one at page A ($08: $0800/$0C00, $F0:
; $F000/$F400), empty, written to (not shown: eng_vmbase shows it)
text_screen:
        sta _colr+1
        ora #$04
        sta _scrn+1
        and #<~$04
        ldx #0
        stx _scrn
        stx _colr
        ldx #COL_BG
        jsr _eng_clear
        jmp _eng_romfont

; ---- the title ---------------------------------------------------------------------

; the title's music on, its file loaded first if it is not there (the boot
; program has it playing; after a level it has to come again)
music:  lda title_song
        bne :+
        loadto n_music, MUSIC
        lda #1
        sta title_song
:       lda _mus_song
        cmp #<MUSIC
        bne :+
        lda _mus_song+1
        cmp #>MUSIC
        beq @rts
:       lda #<MUSIC
        ldx #>MUSIC
        jmp _mus_start
@rts:   rts

; title: the picture, till fire is pressed (or space, or return); the boot
; program has usually shown it already (eng_mode is 1 then)
title:  lda #0
        sta _ptr_on
        lda _eng_mode
        bne @shown
        jsr _eng_blank
        lda #<n_title_b
        sta ld_name
        lda #>n_title_b
        sta ld_name+1
        lda #<BITMAP
        ldx #>BITMAP
        jsr load_packed
        lda #<n_title_m
        sta ld_name
        lda #>n_title_m
        sta ld_name+1
        lda #<TITLE_M
        ldx #>TITLE_M
        jsr load_packed
        lda TITLE_M+1000
        sta _title_bg
        lda TITLE_M+1001
        sta _title_mc
        ; multicolour above this row, hires from it (tools/mkpicture.py):
        ; the interrupt switches in its first lines, which are black
        lda TITLE_M+1002
        asl a
        asl a
        asl a
        clc
        adc #3
        sta _title_split
        lda #<_title_credits
        ldx #>_title_credits
        jsr _eng_bmtext
        jsr music
        lda #1
        sta _eng_mode
        jsr _eng_unblank
@shown: jsr music
        lda fl_on               ; the fast loader: the catalogue and the
        beq :+                  ; overlay now, "loading" still on the
        jsr catalogue           ; title and the ticker not yet running
        inc cat_ok
        lda #>OVL_TITLE
        jsr overlay
:       lda #<_title_ready
        ldx #>_title_ready
        jsr _eng_bmtext
        jsr _tk_start
        jsr _eng_hits
:       jsr _eng_hits
        and #K_FIRE
        beq :-
        rts

; ---- choosing a map ----------------------------------------------------------------

        .segment "OVLCODE"      ; (the overlay, but for is_open and catalogue)

; put_at: the text at A/X to row Y, column cm_k, in colour txt_col
put_at: pha
        lda #0
        sta _txt_o+1
        tya
        asl a                   ; row * 40: (row * 8) * 5
        asl a
        asl a
        sta _txt_o
        asl a
        rol _txt_o+1
        asl a
        rol _txt_o+1
        clc
        adc _txt_o
        sta _txt_o
        bcc :+
        inc _txt_o+1
:       lda _txt_o
        clc
        adc cm_k
        sta _txt_o
        bcc :+
        inc _txt_o+1
:       pla
        jmp _eng_text

; sm_blank: sm_line 40 spaces
sm_blank:
        lda #32
        ldx #39
:       sta sm_line,x
        dex
        bpl :-
        lda #0
        sta sm_line+40
        rts

; fp1 = text Y (0 the name, 1 and 2 the lines about it) of map X
mtext:  stx sm_i
        txa
        asl a                   ; (map * 3 + Y) * 2
        adc sm_i
        sta sm_i
        tya
        clc
        adc sm_i
        asl a
        tax
        lda map_text,x
        sta fp1
        lda map_text+1,x
        sta fp1+1
        rts

        .code
; is_open: Z clear if map X (0 on) can be chosen
is_open:
        lda bit_of,x
        and _unlocked
        rts
        .segment "OVLCODE"

; put_row: sm_line to row Y, all 40 columns, in colour txt_col
put_row:
        lda #0
        sta cm_k
        lda #<sm_line
        ldx #>sm_line
        jmp put_at

; put_text: text fp1 to row Y from column 4, the rest of the row blank, in
; colour A - one write, nothing blanked first
put_text:
        sta _txt_col
        sty cm_k
        jsr sm_blank
        ldy #0
:       lda (fp1),y
        beq :+
        sta sm_line+4,y
        iny
        bne :-
:       ldy cm_k
        jmp put_row

; show_maps: the list, the one chosen (cm_sel) marked, a lock by each,
; shut or open, and about the one chosen - or the bulb (cm_sel 255), the
; mark beside it
show_maps:
        lda #32
        ldx cm_sel
        bpl :+
        lda #$3E                ; >
:       sta $F400 + 1 * 40 + BULB_MARK
        lda #COL_HUD
        sta $F000 + 1 * 40 + BULB_MARK
        lda #0
        sta cm_i
@map:   lda cm_i
        cmp cm_n
        jeq @about
        jsr sm_blank
        ldx cm_i
        lda #32
        cpx cm_sel
        bne :+
        lda #$3E                ; >
:       sta sm_line+1
        ldy #0
        jsr mtext
        ldy #0
:       lda (fp1),y
        beq :+
        sta sm_line+6,y
        iny
        bne :-
:       lda #COL_DIM
        ldx cm_i
        cpx cm_sel
        bne :+
        lda #COL_HUD
:       sta _txt_col
        lda cm_i                ; the row: 6 + 2 * i
        asl a
        adc #6
        sta sm_i
        lda #0                  ; columns 0-2 and 5-39: the lock's are its own
        sta sm_line+3
        sta cm_k
        ldy sm_i
        lda #<sm_line
        ldx #>sm_line
        jsr put_at
        lda #5
        sta cm_k
        ldy sm_i
        lda #<(sm_line+5)
        ldx #>(sm_line+5)
        jsr put_at
        lda #3
        sta cm_k
        lda #COL_LOCK
        sta _txt_col
        ldy sm_i
        lda #<lock_body
        ldx #>lock_body
        jsr put_at
        lda #COL_SHACKLE
        sta _txt_col
        ldy sm_i
        dey
        ldx cm_i
        jsr is_open
        beq :+
        lda #<lock_open
        ldx #>lock_open
        jsr put_at
        jmp @next
:       lda #<lock_shut
        ldx #>lock_shut
        jsr put_at
@next:  inc cm_i
        jmp @map
@about: ldx cm_sel
        bpl @map1
        lda #<help_t1
        sta fp1
        lda #>help_t1
        sta fp1+1
        ldy #20
        lda #COL_LABEL
        jsr put_text
        lda #<help_t2
        sta fp1
        lda #>help_t2
        sta fp1+1
        ldy #21
        lda #COL_DIM
        jmp put_text
@map1:  ldy #1
        jsr mtext
        ldy #20
        lda #COL_LABEL
        jsr put_text
        ldx cm_sel
        jsr is_open
        beq @shut
        ldx cm_sel
        ldy #2
        jsr mtext
        ldy #21
        lda #COL_DIM
        jmp put_text
@shut:  lda #<locked
        sta fp1
        lda #>locked
        sta fp1+1
        ldy #21
        lda #COL_LATE
        jmp put_text

; the music, on or off: left and right turn it (and F1, anywhere)
show_music:
        ldx #14                 ; N
        ldy #32
        lda _mus_off
        beq :+
        ldx #6                  ; F
        ldy #6
:       stx music_t+9
        sty music_t+10
        lda #COL_DIM
        sta _txt_col
        lda #11
        sta cm_k
        ldy #22
        lda #<music_t
        ldx #>music_t
        jmp put_at

        .code
; catalogue: the catalogue off the disk (to SCRATCH): nmaps, and each
; map's texts in map_text. The screen goes off for it - but not on the
; title with the fast loader there, which loads with our interrupt
; running: the title stays up, the ticker going on.
catalogue:
        lda _eng_mode
        cmp #1
        bne :+
        lda _eng_keepirq
        bne @load
:       jsr _eng_blank
@load:  loadto n_maps, SCRATCH
        lda #<SCRATCH
        sta fp1
        lda #>SCRATCH
        sta fp1+1
        ldy #0
        lda (fp1),y
        sta nmaps
        inc fp1
        lda #0
        sta cm_i
        tax
@map:   lda cm_i
        cmp nmaps
        beq @done
        cmp #16
        beq @done
        lda #3
        sta cm_k
@text:  lda fp1                 ; map_text[i][k] = p
        sta map_text,x
        lda fp1+1
        sta map_text+1,x
        inx
        inx
        ldy #0                  ; p past the text and its 0
:       lda (fp1),y
        beq :+
        iny
        bne :-
:       iny
        tya
        clc
        adc fp1
        sta fp1
        bcc :+
        inc fp1+1
:       dec cm_k
        bne @text
        inc cm_i
        bne @map
@done:  lda nmaps
        cmp #MAX_LIST
        bcc :+
        lda #MAX_LIST
:       sta cm_n
        rts

        .segment "OVLCODE"
; choice_screen: the second screen ($F000/$F400) empty, the one written
; to; its last row the ticker's characters
choice_screen:
        lda #$F4
        sta _scrn+1
        lda #$F0
        sta _colr+1
        lda #0
        sta _scrn
        sta _colr
        ldx #0
:       lda #32
        sta $F400,x
        sta $F500,x
        sta $F600,x
        sta $F700-24,x          ; (1000 bytes: to $F7E7)
        lda #COL_BG
        sta $F000,x
        sta $F100,x
        sta $F200,x
        sta $F300-24,x
        inx
        bne :-
        ldx #39
:       txa
        clc
        adc #TK_CODE
        sta $F400 + 24 * 40,x
        lda #TK_COL
        sta $F000 + 24 * 40,x
        dex
        bpl :-
        rts

; choice: the choice itself (choose_map). Drawn on the second screen while
; the title (or the screen off) is still shown, and then shown in one go,
; the ticker running on through it; a locked map cannot be taken. Above
; the first map, the bulb: the page of help (help.s).
choice: lda _tk_on
        bne :+
        jsr _tk_start
:       jsr choice_screen
        lda #COL_HUD
        sta _txt_col
        lda #13
        sta cm_k
        ldy #1
        lda #<head
        ldx #>head
        jsr put_at
        lda #COL_DIM
        sta _txt_col
        lda #14
        sta cm_k
        ldy #3
        lda #<pick
        ldx #>pick
        jsr put_at
        lda #0                  ; the last map open is the one chosen first
        sta cm_sel
        ldx #0
@last:  inx
        cpx cm_n
        bcs :+
        jsr is_open
        beq @last
        stx cm_sel
        bne @last
:       jsr show_maps
        jsr bulb_place
        jsr _eng_choice
        jsr _eng_hits
        lda #255
        sta cm_m
@loop:  jsr _eng_hits
        jsr help_hits           ; (the bulb's, and the page's)
        sta cm_h
        and #K_LEFT | K_RIGHT
        beq :+
        jsr _mus_toggle
:       lda _mus_off
        cmp cm_m
        beq :+
        sta cm_m
        jsr show_music
:       lda cm_h
        and #K_DOWN
        beq :+
        ldx cm_sel
        inx
        cpx cm_n
        bcs :+
        stx cm_sel
        jsr show_maps
:       lda cm_h
        and #K_UP
        beq :+
        lda cm_sel
        beq :+
        dec cm_sel
        jsr show_maps
:       lda cm_h
        and #K_FIRE
        beq @loop
        ldx cm_sel
        jsr is_open
        beq @loop
        ldx cm_sel
        inx
        txa
        rts

        .code
; choose_map: the catalogue off the disk, and a map chosen from it: its
; number, 1 on (in A) - by the overlay, loaded first if it is not there
; (after the title's song: from a level, its song is at $B000 till then)
choose_map:
        lda #0
        sta _ptr_on
        ldx #>OVL_TITLE         ; (where the overlay comes packed: from
        lda _eng_mode           ; the title, the trains' draw list, unused
        bne :+                  ; yet; from a level, its characters)
        ldx #>OVL_LEVEL
:       stx cm_m
        lda cat_ok              ; (loaded on the title already)
        bne :+
        jsr _eng_loading        ; else "loading" meanwhile (on the first
                                ; screen: the choice is drawn on the second)
        jsr catalogue
:       lda #0
        sta cat_ok
        jsr music
        lda cm_m
        jsr overlay
        ldx _eng_mode           ; loading: the choice's mode before it is
        dex                     ; drawn - else its rows from 19 on are the
        beq :+                  ; board's (eng_text), the ticker's
        stx _eng_mode           ; characters (3 - 1); the title stays 1
:       jmp choice

; overlay: the overlay, if it is not there, unpacked from page A
overlay:
        ldx help_ok
        bne @rts
        sta ld_addr+1
        lda _tk_on              ; (the ticker held meanwhile: the loader
        pha                     ; misses fewer sectors)
        lda #0
        sta _tk_on
        sta ld_addr
        lda #<n_help
        sta ld_name
        lda #>n_help
        sta ld_name+1
        lda #<OVL_ADDR
        ldx #>OVL_ADDR
        jsr load_packed_at
        pla
        sta _tk_on
        inc help_ok
@rts:   rts

; unlock_next: after a star on the map played, the next one open; C set if
; it was not open before (and there is one)
unlock_next:
        ldx cur_map             ; (1 on: the next one's index)
        cpx nmaps
        bcs @no
        cpx #8
        bcs @no
        jsr is_open
        bne @no
        lda bit_of,x
        ora _unlocked
        sta _unlocked
        sec
        rts
@no:    clc
        rts

; load_map: map A off the disk to SCRATCH, and from there its song (its
; length first, 0 if none) to SONG_BUF, the map after it to level_buf
load_map:
        sta cur_map
        clc
        adc #$30                ; '0' + n
        sta n_map+3
        lda #0                  ; the ticker's strip is the map's now
        sta _tk_on
        jsr _mus_quiet
        lda #0                  ; the level takes its memory
        sta title_song
        sta help_ok
        jsr _eng_loading        ; "loading" meanwhile, on the first screen
        jsr _eng_blank
        loadto n_map, SCRATCH
        lda #<(SCRATCH + 2)
        sta fp1
        lda #>(SCRATCH + 2)
        sta fp1+1
        lda SCRATCH
        sta cp_n
        ora SCRATCH+1
        sta map_song            ; (not 0: there is one)
        lda SCRATCH+1
        sta cp_n+1
        lda #<SONG_BUF
        ldx #>SONG_BUF
        jsr copy
        lda #<1024
        sta cp_n
        lda #>1024
        sta cp_n+1
        lda #<_level_buf
        ldx #>_level_buf
        jsr copy
        lda #$F0                ; the level made on the second: its view
        jsr text_screen         ; goes on the first (level_start), when
        jmp _eng_irqon          ; loading is over

; copy: cp_n bytes from fp1 on to A/X (fp1 left after them)
copy:   sta ld_name             ; (the name's pointer: free after a load)
        stx ld_name+1
        ldy #0
@byte:  lda cp_n
        ora cp_n+1
        beq @done
        lda (fp1),y
        sta (ld_name),y
        inc fp1
        bne :+
        inc fp1+1
:       inc ld_name
        bne :+
        inc ld_name+1
:       lda cp_n
        bne :+
        dec cp_n+1
:       dec cp_n
        jmp @byte
@done:  rts

; Both switch the ROM in, so they have to be below $8000 themselves:
; LOWCODE comes first in the program.
        .segment "LOWCODE"

; kload: the KERNAL loads file ld_name (ld_len long) from the drive dev to
; ld_addr: C set if it failed. Everything set before the ROM comes in -
; the game's variables may lie above $8000, under it (SETLFS and SETNAM
; only store these, as cc65's own do). The name itself the KERNAL reads
; with its ROM in: it must lie below $8000 (asserted at the names).
kload:  lda #0
        sta $AC                 ; the logical file
        sta $AD                 ; the secondary address: to the address given
        lda dev
        sta $AE
        lda ld_len
        sta $AB
        lda ld_name
        sta $AF
        lda ld_name+1
        sta $B0
        ldx ld_addr
        ldy ld_addr+1
        lda #0
        sta $FF3E               ; ROM in
        jsr $FFD5               ; LOAD
        sta $FF3F               ; ROM out (C kept)
        rts
