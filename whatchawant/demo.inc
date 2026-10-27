; demo.inc - what all of the demo's files share

; ---- TED ------------------------------------------------------------------

TED_SCROLLY = $FF06
TED_CTRL2   = $FF07
TED_IRQ     = $FF09
TED_IRQEN   = $FF0A
TED_BMBASE  = $FF12
TED_CHBASE  = $FF13
TED_VMBASE  = $FF14
TED_BG      = $FF15
TED_BORDER  = $FF19
TED_LINE    = $FF1D
TED_ROM     = $FF3E             ; a write: the ROM in
TED_RAM     = $FF3F             ; a write: RAM instead of the ROM

; ---- the screen -----------------------------------------------------------

COLRAM      = $0800             ; the TED's colours and codes where the
SCREEN      = $0C00             ; KERNAL has them
FONT        = $F000             ; the ROM's characters, copied to RAM
