/*
 * picture.c - the droids' pictures and the panel's letters in the window
 *
 * Always there (the transfer's overlay, transfer.c, has the rest): the
 * transfer's introduction, the console's droid enquiry, the title's start
 * page and a game's end show them. A file of its own, as cc65 puts the
 * strings of a file's tables where the file's last segment is.
 */
#include <string.h>
#include "game.h"

extern unsigned char xmap[128];
void x_letter(unsigned char c);         /* a letter of the panel's, two high */
void x_picture(const unsigned char *lay);   /* a droid's, x_code rows */

/* The pictures are files on the disk, "p00" to "p23" (tools/mkdata.py),
 * loaded to character 1 of picture 1's set, which the window shows for
 * both pictures meanwhile. The text is in the panel's letters, their
 * characters copied there too, from 100 on, the first time each is met. */
static char name[4] = "p00";

static const char *const noun[4] = { " device", " robot", " droid", " cyborg" };
static const char *const class_name[10] = {
    "influence", "disposal", "servant", "messenger", "maintenance",
    "crew", "sentinel", "battle", "security", "command"
};
static char word[20];

/* "Maintenance robot": the class, a capital first, and what it is */
const char *unit_name(unsigned char t)
{
    strcpy(word, class_name[dr_class[t]]);
    word[0] ^= 0x80;                    /* a capital (PETSCII) */
    strcat(word, noun[(dr_class[t] + 3) / 4]);
    return word;
}

/* text from x_row, x_col on, in the panel's letters (title.c too) */
void say(const char *s)
{
    static unsigned char c;
    while (*s) {
        c = panel_code(*s++);
        x_letter(c);
        if (c >= 0x3A)
            x_letter(c + 0x20);
    }
}

/* droid type t's screen: its picture and what it is; the second line is
 * the player's or the other droid's */
/* droid type t's picture from the disk at row, col of a cleared window,
 * picture 1's set shown for both pictures; letters can follow (title.c,
 * console.c too). The file (tools/mkdata.py) ends with where its header
 * is; after the header come the console's pages about the droid. */
const unsigned char *pic_pages;
unsigned char pic_late;                 /* the window cleared once loaded, */
unsigned char pic_until;                /* not before this picture, and */
                                        /* the static stopped */

void picture(unsigned char t, unsigned char row, unsigned char col)
{
    static unsigned char *e;
    if (!pic_late)
        win_clear(0, 0x71);
    name[1] = '0' + t / 10;
    name[2] = '0' + t % 10;
    e = FONT1 + 8 + load_file(name, FONT1 + 8);
    if (pic_late) {
        while ((signed char)(frames - pic_until) < 0)
            ;
        roll = 0;
        eng_roll(0);
        win_clear(0, 0x71);
        pic_late = 0;
    }
    e = FONT1 + 8 + (e[-2] | e[-1] << 8);
    pic_pages = e + 4;
    font_hi[0] = 0xD8;
    col_fig2 = pal_deck[e[3]];
    x_attr = pal_mc[e[2]];
    x_row = row;
    x_col = col;
    x_code = e[1];
    x_picture(e - e[1] * 6);
    memset(xmap, 0, sizeof xmap);
    x_code = 140;
}

