; the 1551's drive code for fastinit.c, assembled from drive1551.s
        .segment "INITDATA"
        .export _drive1551, _drive1551_size
_drive1551:      .incbin "build/drive1551.bin"
_drive1551_end:
_drive1551_size: .word _drive1551_end - _drive1551
