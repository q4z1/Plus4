; the drive code for fastinit.c, assembled from drive1551.s and
; drive1541.s
        .segment "INITDATA"
        .export _drive1551, _drive1551_size, _drive1541, _drive1541_size
_drive1551:      .incbin "build/drive1551.bin"
_drive1551_end:
_drive1551_size: .word _drive1551_end - _drive1551
_drive1541:      .incbin "build/drive1541.bin"
_drive1541_end:
_drive1541_size: .word _drive1541_end - _drive1541
