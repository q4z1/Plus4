; game.inc - what the parts of Paradroid share: the keys' bits, the
; droids' and shots' numbers, the pictures' slots, and where things are in
; memory (paradroid.cfg has the whole map). The numbers that come from the
; data are in build/gen/data.inc (tools/mkdata.py).

; the keys, as eng_keys() and keys_irq have them (engine.s)
K_UP        = 1
K_DOWN      = 2
K_LEFT      = 4
K_RIGHT     = 8
K_FIRE      = 16
K_STOP      = 64
K_DIRS      = K_UP | K_DOWN | K_LEFT | K_RIGHT

; droids and shots (droids.s): droid 0 is the player
MAXD        = 13
MAXS        = 8
BOOM_GONE   = 13                ; an explosion's last step: the droid gone

; the pre-shifted pictures' slots, 512 bytes each from pre (draw.s)
SLOT_PLAYER = 0
SLOT_DROID  = 1                 ; the deck's droid types
NSLOT_DROID = 9
SLOT_EXPLO  = 10
SLOT_LASER  = 16
SLOT_PANIM  = 20                ; the player's, turning

; memory
DMAP        = $0400             ; the deck: 64 x 16 blocks
MCFONT      = $0800             ; the deck's characters in multicolour
SCR0A       = $C000             ; picture 0: colours, codes
SCR0C       = $C400
FONT0       = $C800             ; its character set
SCR1A       = $D000             ; picture 1
SCR1C       = $D400
FONT1       = $D800
PANELF      = $E000             ; the status panel's character set
BLKC        = $E800             ; [4][256]: each block's characters
BLKA        = $EC00             ; [4][256]: their colours
CLS_HR      = $EAA0             ; the deck scheme's colour of each class,
CLS_MC      = $EAB0             ; hires and multicolour-safe (move.s)

; the window's top row (screen row 8, the gap's last): its characters as
; copies in codes of their own, picture 0's in 216-235, picture 1's in
; 236-255; each picture's set keeps the other's blank (engine.s)
CUT_R0      = 216
CUT_N       = 20
