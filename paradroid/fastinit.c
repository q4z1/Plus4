/*
 * fastinit.c - the fast loader into the drive, once at the start
 *
 * Asks the drive at device dev who it is (the reply to a UI command: "CBM
 * DOS V2.6 TDISK" for a 1551, "... 1541" for a 1541), sends the drive code
 * for it (drive1551.s, drive1541.s) over with the DOS's M-W commands and
 * starts it with M-E, and puts the Plus/4's half for it (fastload51.s,
 * fastload41.s) where fastload.s calls it. Any other drive keeps loading
 * with the KERNAL (fl_kind 0).
 *
 * It also puts the sound effects' player where it runs (sfx.s), and
 * draws the status panel (panel_init()).
 *
 * Code and drive code are in INITDATA: used once, then overwritten. The
 * variables are in LOWBSS, which has room: not in INITDATA, as cc65 puts
 * a function's static locals in the bss segment right where it is, so in
 * the code's own segment they would land between the function's label and
 * its code.
 */
#include <cbm.h>
#include <string.h>
#include "game.h"

#pragma code-name (push, "INITDATA")
#pragma rodata-name (push, "INITDATA")
#pragma bss-name (push, "LOWBSS")

extern unsigned char fl_kind;
extern const unsigned char drive1551[], drive1541[];
extern const unsigned drive1551_size, drive1541_size;
/* the Plus/4's halves, linked to run at FLRUN (paradroid.cfg) */
extern unsigned char _FL51_LOAD__[], _FL51_RUN__[], _FL51_SIZE__[];
extern unsigned char _FL41_LOAD__[], _FL41_RUN__[], _FL41_SIZE__[];

static char buf[40];

/* the sound effects' player and their table, linked to run at $FC00 and
 * $FF40 (paradroid.cfg, sfx.s): there, and both voices quiet */
extern unsigned char _SFXCODE_LOAD__[], _SFXCODE_RUN__[], _SFXCODE_SIZE__[];
extern unsigned char _SFXDATA_LOAD__[], _SFXDATA_RUN__[], _SFXDATA_SIZE__[];
/* the console and the figures, linked to run at $F400 likewise */
extern unsigned char _HICODE_LOAD__[], _HICODE_RUN__[], _HICODE_SIZE__[];
extern unsigned char snd_len[2];
#pragma zpsym ("snd_len")

void fl_init(unsigned char dev)
{
    static unsigned a, size, at;
    static unsigned char n, i;
    static int got;
    static const unsigned char *code;
    memcpy(_SFXCODE_RUN__, _SFXCODE_LOAD__, (unsigned)_SFXCODE_SIZE__);
    memcpy(_SFXDATA_RUN__, _SFXDATA_LOAD__, (unsigned)_SFXDATA_SIZE__);
    memcpy(_HICODE_RUN__, _HICODE_LOAD__, (unsigned)_HICODE_SIZE__);
    snd_len[0] = snd_len[1] = 0;
    fl_kind = 0;
    if (cbm_open(15, dev, 15, "ui"))
        return;
    got = cbm_read(15, buf, sizeof buf - 1);
    buf[got > 0 ? got : 0] = 0;
    if (strstr(buf, "tdisk")) {
        fl_kind = 1;
        code = drive1551;
        size = drive1551_size;
        at = 0x0500;
        memcpy(_FL51_RUN__, _FL51_LOAD__, (unsigned)_FL51_SIZE__);
    } else if (strstr(buf, "1541")) {
        fl_kind = 2;
        code = drive1541;
        size = drive1541_size;
        at = 0x0300;
        memcpy(_FL41_RUN__, _FL41_LOAD__, (unsigned)_FL41_SIZE__);
    } else {
        cbm_close(15);
        return;
    }
    /* M-W: 32 bytes at a time to its place on */
    for (a = 0; a < size; a += 32) {
        n = size - a < 32 ? size - a : 32;
        buf[0] = 'm';
        buf[1] = '-';
        buf[2] = 'w';
        buf[3] = (unsigned char)(at + a);
        buf[4] = (unsigned char)((at + a) >> 8);
        buf[5] = n;
        for (i = 0; i < n; ++i)
            buf[6 + i] = code[a + i];
        cbm_write(15, buf, 6 + n);
    }
    /* M-E: the drive code runs from now on, and nothing more goes to the
     * drive the KERNAL's way (no close: that would talk to it) */
    buf[0] = 'm';
    buf[1] = '-';
    buf[2] = 'e';
    buf[3] = (unsigned char)at;
    buf[4] = (unsigned char)(at >> 8);
    cbm_write(15, buf, 5);
}

/* the status panel, the original's, and the gap's rows under it blank */
static void panel_init(void)
{
    static unsigned i;
    for (i = 0; i < 240; ++i) {
        pp_off = i;
        pp_code = panel_codes[i];
        pp_attr = panel_cols[i] == 4 ? 0x4E : 0x3B;   /* purple, red */
        panel_put();
    }
    for (i = 240; i < 360; ++i) {
        pp_off = i;
        pp_code = 0;
        pp_attr = col_deck;
        panel_put();
    }
}

/* the rest of the start (main(), after fl_init()): the engine, the
 * character sets and block tables, the colours, the panel */
void mc_font(void);                     /* paradroid.c */

void start_up(void)
{
    eng_init();
    memcpy(FONT0, tile_font, POOL * 8);
    memcpy(FONT1, tile_font, POOL * 8);
    mc_font();
    memcpy(PANELF, panel_font, 2048);
    memcpy(BLKC, blk_code, 1024);
    col_panel = 0x71;
    col_border = 0x4E;                  /* the original's purple */
    col_deck = 0x5D;
    col_fig1 = 0x00;
    col_fig2 = 0x71;
    panel_init();
}
