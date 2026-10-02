/*
 * fastinit.c - the fast loader into the drive, once at the start
 *
 * Asks the drive at device dev who it is (the reply to a UI command: "CBM
 * DOS V2.6 TDISK" for a 1551), and for a 1551 sends the drive code
 * (drive1551.s) over with the DOS's M-W commands and starts it with M-E.
 * Anything else, a 1541 too, keeps loading with the KERNAL (fl_kind 0).
 *
 * It also puts the sound effects' player where it runs (sfx.s).
 *
 * Code and drive code are in INITDATA: used once, then overwritten. The
 * variables are in LOWBSS, which has room: not in INITDATA, as cc65 puts
 * a function's static locals in the bss segment right where it is, so in
 * the code's own segment they would land between the function's label and
 * its code.
 */
#include <cbm.h>
#include <string.h>

#pragma code-name (push, "INITDATA")
#pragma rodata-name (push, "INITDATA")
#pragma bss-name (push, "LOWBSS")

extern unsigned char fl_kind;
extern const unsigned char drive1551[];
extern const unsigned drive1551_size;

static char buf[40];

/* the sound effects' player and their table, linked to run at $FC00 and
 * $FF40 (paradroid.cfg, sfx.s): there, and both voices quiet */
extern unsigned char _SFXCODE_LOAD__[], _SFXCODE_RUN__[], _SFXCODE_SIZE__[];
extern unsigned char _SFXDATA_LOAD__[], _SFXDATA_RUN__[], _SFXDATA_SIZE__[];
extern unsigned char snd_len[2];
#pragma zpsym ("snd_len")

void fl_init(unsigned char dev)
{
    static unsigned a;
    static unsigned char n, i;
    static int got;
    memcpy(_SFXCODE_RUN__, _SFXCODE_LOAD__, (unsigned)_SFXCODE_SIZE__);
    memcpy(_SFXDATA_RUN__, _SFXDATA_LOAD__, (unsigned)_SFXDATA_SIZE__);
    snd_len[0] = snd_len[1] = 0;
    fl_kind = 0;
    if (cbm_open(15, dev, 15, "ui"))
        return;
    got = cbm_read(15, buf, sizeof buf - 1);
    buf[got > 0 ? got : 0] = 0;
    if (!strstr(buf, "tdisk")) {
        cbm_close(15);
        return;
    }
    fl_kind = 1;
    /* M-W: 32 bytes at a time to $0500 on */
    for (a = 0; a < drive1551_size; a += 32) {
        n = drive1551_size - a < 32 ? drive1551_size - a : 32;
        buf[0] = 'm';
        buf[1] = '-';
        buf[2] = 'w';
        buf[3] = (unsigned char)(0x0500 + a);
        buf[4] = (unsigned char)((0x0500 + a) >> 8);
        buf[5] = n;
        for (i = 0; i < n; ++i)
            buf[6 + i] = drive1551[a + i];
        cbm_write(15, buf, 6 + n);
    }
    /* M-E: the drive code runs from now on, and nothing more goes to the
     * drive the KERNAL's way (no close: that would talk to it) */
    buf[0] = 'm';
    buf[1] = '-';
    buf[2] = 'e';
    buf[3] = 0x00;
    buf[4] = 0x05;
    cbm_write(15, buf, 5);
}
