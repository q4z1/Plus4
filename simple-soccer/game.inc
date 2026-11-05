; game.inc - what all of Simple Soccer's files share

; ---- TED ------------------------------------------------------------------

TED_SCROLLY = $FF06
TED_CTRL2   = $FF07
TED_KEYS    = $FF08
TED_IRQ     = $FF09
TED_IRQEN   = $FF0A
TED_RCMP    = $FF0B
TED_BMBASE  = $FF12
TED_CHBASE  = $FF13
TED_VMBASE  = $FF14
TED_BG      = $FF15
TED_COL1    = $FF16
TED_COL2    = $FF17
TED_BORDER  = $FF19
TED_LINE    = $FF1D
TED_RAM     = $FF3F             ; a write: RAM instead of the ROM
KEY_ROW     = $FD30

; ---- the screen -----------------------------------------------------------

SCR_W       = 40                ; built: 40 x 25 cells, of which the TED
SCR_H       = 25                ; shows 38 x 24 and a bit, by the scroll
VIS_H       = 23                ; - but the picture ends 16 lines early
                                ; (engine.s CUT_D): 22 and a bit shown, rows
                                ; 23 and 24 never - nothing is drawn there

; frames a picture stays on screen at least: 3, 16.7 pictures a second
; (build.sh: PACE=2 for 25)
.ifndef PACE
PACE        = 3
.endif

MAT0        = $C000             ; picture 0: colours, codes at +$400
FNT0        = $C800             ;   its characters
MAT1        = $D000             ; picture 1
FNT1        = $D800
MAT2        = $E800             ; picture 2
FNT2        = $F000

; ---- input: joy's bits, set while held ------------------------------------

J_UP        = $01
J_DOWN      = $02
J_LEFT      = $04
J_RIGHT     = $08
J_FIRE      = $10

; ---- what outlasts a match (resident.s) ---------------------------------
;
; From the boot on: the fast loader at $0200 (resident.s, the boot keeps a
; copy at RES_STORE, which the game's start puts back), a little code at
; K_CODE, and these, in RAM the game, the title and the KERNAL leave alone
; (under the ROM: read only with the ROM out)

RES         = $0200             ; the fast loader, the KERNAL's way back
RES_STORE   = $FA00             ; its copy, till the game's start takes it
K_VARS      = $FCE0
K_MAGIC     = K_VARS            ; 2: K_MAGIC_0, K_MAGIC_1 - the boot ran
K_MAGIC_0   = $5A               ; (K_DEV and K_FAST known); else a test,
K_MAGIC_1   = $A5               ; no disk
K_DEV       = K_VARS + 2        ; the drive
K_FAST      = K_VARS + 3        ; 1: the fast loader runs in it
K_REQ       = K_VARS + 4        ; what cup.s is to do (K_*)
K_CHOK      = K_VARS + 5        ; 2: K_MAGIC_0, K_MAGIC_1 - K_CH set
K_CH        = K_VARS + 7        ; the title's choices (title.s t_*): the
                                ; length, players, mode, the teams (2),
                                ; their formations (2)
K_CH_N      = 7
K_STORED    = K_CH + K_CH_N     ; K_MAGIC_0: RES_STORE holds RES (the boot)
K_VARS_END  = K_STORED + 1

K_TITLE     = 0                 ; K_REQ: back to the title
K_NEW       = 1                 ;   a new league
K_ON        = 2                 ;   the league's page (go on with it)
K_PLAYED    = 3                 ;   a league's match: the title kicks off
                                ;   at once, its result to the page after

K_CODE      = $FF40             ; resident.s: k_go, the way to cup.s
L_BLOCK     = $FFC8             ; the league, as the disk keeps it ("league")
L_SUM       = L_BLOCK           ; all its bytes add up to 0
L_ON        = L_BLOCK + 1       ; 1: a league goes on
L_TWO       = L_BLOCK + 2       ; 1: two players (teams 0 and 1)
L_SEL       = L_BLOCK + 3       ; the length
L_FORM      = L_BLOCK + 4       ; the players' formations (2)
L_TEAM      = L_BLOCK + 6       ; its eight teams, the players' first
L_TEAMS     = 8
L_RES       = L_TEAM + L_TEAMS  ; each match's result, goals home * 16 +
L_MATCHES   = 28                ; away; $FF not played (cup.s: the order)
L_LEN       = L_RES + L_MATCHES - L_BLOCK
L_END       = L_BLOCK + L_LEN

CUP         = $E500             ; cup.s: the way back, the league's page
