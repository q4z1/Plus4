; game.inc - what the parts of trainschedule share: the screen's and the
; map's places, the kinds of character, the colours, the keys
; (trainschedule.cfg has the whole map of memory)

; ---- the screen ------------------------------------------------------------
; Rows 0-1 the map's name, the clock and the score, in characters two
; rows high; rows 2-17 the map, row 18 a line, rows 19-24 the departure
; board. Hires characters, 256 of them:
;     0- 63  the upper-case font, copied from the ROM (screen codes); the
;            codes no text uses are the signs' (signs.s)
;    64-159  the track: in the overview a character for each kind of
;            cell, close up the quarters of cells (map.s)
;   then-    the trains, from a free list as they are drawn, each train
;            keeping those it is shown in till its next are (train.s)
;   -247     the station signs and the flap digits, as many as the level
;            needs (signs.s)
;   248-255  the frame round the cell pointed at, two sets so it is never
;            redrawn while shown
FONT        = $C000
VIEW_TOP    = 2
VIEW_H      = 16
BOARD_TOP   = 19
C_FIRST     = 64
C_LAST      = 159               ; the kinds of cell: 64-159
C_CURSOR    = 248
C_POOL_END  = 248

; ---- the map ---------------------------------------------------------------
; One byte per cell in each of three arrays, row after row, the map's own
; width (up to 1536 cells): the character drawn there when no train is on
; it, its colour, and who has it (OCC_...). A track character stands for
; the directions its track leaves the cell in, one bit each (D_E ...), and
; what else is drawn in it (code_deco).
MAP_CODE    = $C800
MAP_ATTR    = $CC00
MAP_OCC     = $D000
MAP_MAX     = 1024

; The map's song (data/music.txt) comes in its file (tools/mklevel.py) and
; is kept here while the map is played (front.s, load_map).
SONG_BUF    = $B000
SONG_MAX    = $0560

D_E         = 0
D_NE        = 1
D_N         = 2
D_NW        = 3
D_W         = 4
D_SW        = 5
D_S         = 6
D_SE        = 7

OCC_FREE    = 0
OCC_ROUTE   = 1
OCC_TRAIN   = $80

DECO_SIGNAL   = $08             ; + the direction it faces, bits 0-2
DECO_PLATFORM = $10
DECO_END      = $20             ; a portal or a buffer stop
DECO_NUMBER   = $40             ; the platform's number: bits 0-2, and 8
                                ; for bit 7

; colours: luminance * 16 + colour. Colours 0-7 only: a colour with bit 3
; set makes its cell multicolour (the cursor's cells, engine.s)
COL_BG      = $00
COL_TRACK   = $31
COL_ROUTE   = $55
COL_LABEL   = $41
COL_SIG_RED = $42
COL_HUD     = $71
COL_DIM     = $31
COL_LATE    = $52
COL_GOOD    = $55
COL_PLATE   = $61               ; a station sign
; the board, rows 18-24, is a small open book, in extended colour
; (engine.s): a character's top two bits choose its background. Its rows
; take turns between two registers of the paper's colour, BG_PAGE_A rows
; 19, 21 and 23, BG_PAGE_B 20, 22 and 24, and the interrupt turns a row's
; register the ruling's blue for its last line, the line under its text -
; and row 24's the cover's for its last two, the book's lower edge. No
; bits (background 0) is the paper too, never ruled: row 18, the book's
; top edge
BG_PAGE_A   = $40
BG_PAGE_B   = $80
COL_PAPER   = $78               ; (engine.s)
COL_RULE    = $6D               ; the ruling, the columns' rules too
COL_COVER   = $22               ; the cover, 2 pixels round the pages, and
                                ; the fold between them
COL_INK     = $09               ; what is written in the book
COL_INK_HEAD = $22              ; the heads
COL_INK_DIM = $48               ; a train not yet in
COL_INK_GOOD = $25              ; at its stop, setting off; a stop on time
COL_INK_LATE = $32
COL_MSG     = $32               ; a message: blinking (msg_blink)
COL_STARS   = $38
; the book's characters: ROM codes no text uses (engine.s frame_chars) -
; its top edge, the top's corners, the edge over the fold, the sides, and
; a rule (the columns', and the fold, in the cover's colour)
FR_TOP      = 0
FR_TL       = 27
FR_TR       = 28
FR_RULE     = 29
FR_TFOLD    = 30
FR_LEFT     = 44
FR_RIGHT    = 46
SCR_A       = 1                 ; the pages' first columns: the fold is
SCR_B       = 21                ; between columns 19 and 20
SCR_W       = 18
SG_LCAP     = 27                ; a sign's plate: its left end, its right
SG_RCAP     = 28                ; (signs.s, tools/mkfont.py)
HUD_NAME    = 12                ; the most of the map's name on its sign
COL_FLAP    = $51               ; the lower flap of a digit

; ---- the level ---------------------------------------------------------------
MAX_SIGNALS  = 48
MAX_PORTALS  = 12
MAX_STATIONS = 12
MAX_PLATS    = 32
MAX_TRAINS   = 24

; the routes (route.s)
MAX_DEST    = 12
MAX_RLEN    = 64
MAX_ROUTES  = 16

; a train's record in the level (tools/mklevel.py): its number, its type,
; km/h, cars, the number of its stops, then the stops (6 bytes each)
TR_NUM_N    = 6
TR_TYPE     = 6
TR_KMH      = 7
TR_CARS     = 8
TR_NV       = 9
TR_VISITS   = 10

; the trains (train.s): their timetable as the board sees it
TT_WAIT     = 0
TT_RUN      = 1
TT_STOP     = 2
TT_GONE     = 3
MAX_VISITS  = 8

; what the score hears of (trainschedule.s)
EV_ARRIVE   = 0
EV_RED      = 1
EV_BRAKE    = 2

; ---- the keys (engine.s) -------------------------------------------------------
K_UP        = 1
K_DOWN      = 2
K_LEFT      = 4
K_RIGHT     = 8
K_FIRE      = 16
K_FAST      = 32                ; +
K_SLOW      = 64                ; -
K_LEVEL     = 128               ; L

; ---- the title and the choice of a map -------------------------------------
; The ticker runs through both (engine.s): its strip is row 24 of the
; title's bitmap, and characters TK_CODE.. of the choice's, which are at
; $D800 - the ROM's upper case (0-63), the locks (LOCK_CODE: the body,
; then its top shut, then open), the strip (192-231).
TK_STRIP    = $DE00
TK_CODE     = 192
TK_COL      = $61
LOCK_CODE   = 64
COL_LOCK    = $57               ; the body: gold
COL_SHACKLE = $51               ; its shackle: grey
