; game.inc - what all of the soccer game's files share

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

MAT0        = $C000             ; picture 0: colours, codes at +$400
FNT0        = $C800             ;   its characters
MAT1        = $D000             ; picture 1
FNT1        = $D800

; ---- input: joy's bits, set while held ------------------------------------

J_UP        = $01
J_DOWN      = $02
J_LEFT      = $04
J_RIGHT     = $08
J_FIRE      = $10
