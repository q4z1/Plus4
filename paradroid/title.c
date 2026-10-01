/*
 * title.c - waiting for a game: the title page, the briefing, the deck
 *
 * An overlay: this code and the briefing's text (build/gen/brief.s) are
 * linked to run in the slots of the explosions' and lasers' pictures
 * (paradroid.cfg) and are a file of their own on the disk, "title", which
 * paradroid.c loads for each title. Its variables are in the program's
 * memory, so they stay from one title to the next.
 *
 * The briefing is the original's four pages. The text comes with the
 * characters it needs, as codes of the panel's set (brief_srcs), and its
 * letters: letter k is character brief_top[k] over brief_bot[k]. A page
 * is rolled up through the window a line of pixels at a time, the way the
 * deck scrolls: picture 1's character set holds the briefing's, and both
 * pictures show it.
 */
#include <string.h>
#include "game.h"

#pragma code-name (push, "OVLCODE")
#pragma rodata-name (push, "OVLDATA")

void wait_tick(void);
extern unsigned long best;

static const unsigned char *bpage;      /* the page shown */
static const unsigned char *bnext;      /* the one after it */
static unsigned char b_h;               /* its rows */

/* the title page: whose game this is, and the best score */
static void title_page(void)
{
    while (ready)
        ;
    win_letters();
    eng_plain();
    win_clear(0, 0x71);
    win_text(0, 14, "paradroid", 0x67);
    win_text(1, 9, "by andrew braybrook", 0x71);
    win_text(2, 7, "graftgold  hewson 1985", 0x71);
    win_text(4, 4, "plus4 version 2026 in c", 0x71);
    win_text(5, 10, "best", 0x71);
    win_text(5, 16, num_text(best), 0x67);
    win_text(7, 14, "press fire", 0x71);
}

/* n pictures; 1 as soon as fire is pressed */
static unsigned char fire_in(unsigned n)
{
    static unsigned char f;
    while (n--) {
        f = frames;
        while (frames == f)
            ;
        if (keys_irq & K_FIRE)
            return 1;
    }
    return 0;
}

/* picture 0's character set for the window, or (0xD8) the briefing's in
 * picture 1's for both; changed just after a picture has begun, with the
 * window cleared to colour a */
static void window_font(unsigned char hi, unsigned char a)
{
    static unsigned char k, f;
    while (ready)
        ;
    f = frames;
    while (frames == f)
        ;
    win_clear(0, a);
    if (hi == 0xD8) {
        for (k = 0; k < NBRIEF; ++k)
            memcpy(FONT1 + k * 8, PANELF + brief_srcs[k] * 8, 8);
    } else
        memcpy(FONT1, FONT0, POOL * 8);
    font_hi[0] = hi;
}

/* the page rolled up by y pixels, into the back picture. As for the deck,
 * the rows move down by k lines and window row 0 shows its last k lines,
 * from copies of its characters with the rest cleared. A line of text is
 * its row, column, length and letters. */
static void page_show(unsigned y)
{
    static unsigned char *d, *q, *g, *o;
    static const unsigned char *p;
    static unsigned char k, rr, r, n, h, w, i, c, code;
    k = (unsigned char)-(unsigned char)y & 7;
    rr = (y + k) >> 3;                  /* the page's row in window row 1 */
    d = (unsigned char *)(back ? 0xD400 : 0xC400) + 9 * 40;
    memset(d, 0, 16 * 40);
    code = back ? 198 : POOL;           /* each picture copies of its own */
    for (p = bpage + 1; (r = *p) != 0xFF; p += 3 + n) {
        n = p[2];
        for (h = 0; h < 2; ++h) {
            w = r + h + 1 - rr;         /* its window row */
            if (w >= 16 || (!w && !k))
                continue;
            q = d + w * 40 + p[1];
            for (i = 0; i < n; ++i) {
                c = h ? brief_bot[p[3 + i]] : brief_top[p[3 + i]];
                if (w)
                    q[i] = c;
                else if (c) {
                    g = FONT1 + c * 8;
                    o = FONT1 + code * 8;
                    memset(o, 0, 8 - k);
                    memcpy(o + 8 - k, g + 8 - k, k);
                    q[i] = code++;
                }
            }
        }
    }
    bnext = p[1] ? p + 1 : brief_pages;
    e_sx = 0;
    e_cutrow = 0;
    e_s = k;
    r_done();
}

/* the panel's frame in the border's colour: cells of colour from to to */
static void frame(unsigned char from, unsigned char to)
{
    static unsigned char i;
    for (i = 0; i < 240; ++i)
        if (((unsigned char *)0xC000)[i] == from)
            ((unsigned char *)0xC000)[i] = ((unsigned char *)0xD000)[i] = to;
}

/* a page of the briefing, rolled up, in the original's colours: orange on
 * yellow, a red border; 1 if fire ended it */
static unsigned char brief(void)
{
    static unsigned y, end;
    static unsigned char cd, cb;
    cd = col_deck;
    cb = col_border;
    eng_plain();
    window_font(0xD8, pal_deck[8]);
    col_deck = pal_deck[7];
    col_border = 0x42;                  /* the original's red, frame and all */
    frame(cb, 0x42);
    panel_status("Briefing");
    if (!bpage)
        bpage = brief_pages;
    b_h = *bpage;
    end = b_h * 8 > 120 ? b_h * 8 - 120 : 0;
    for (y = 0; ; ++y) {
        while (ready)
            ;
        page_show(y);
        if (fire_in(y == 0 || y == end ? 120 : 1) || y == end)
            break;
    }
    bpage = bnext;
    while (ready)
        ;
    window_font(0xC8, 0x71);
    col_deck = cd;
    col_border = cb;
    frame(0x42, cb);
    panel_status("Press fire");
    return keys_irq & K_FIRE;
}

/* after a game, as the original: a droid picked at random, between
 * "Transmission" and "Terminated" */
static void terminated(void)
{
    static unsigned char cd;
    while (ready)
        ;
    eng_plain();
    cd = col_deck;
    col_deck = pal_deck[1];
    picture(rnd() & 15, 11, 16);
    x_attr = 0x63;                      /* the original's light cyan */
    x_row = 10;
    x_col = 13;
    say("Transmission");
    x_row = 22;
    x_col = 14;
    say("Terminated");
    fire_in(200);
    win_clear(0, 0x71);
    memcpy(FONT1, FONT0, POOL * 8);
    font_hi[0] = 0xC8;
    col_fig2 = 0x71;
    col_deck = cd;
}

/* the deck and its droids going about, for n ticks; 1 if fire ended it */
static unsigned char attract(unsigned char n)
{
    eng_dirty();
    while (n--) {
        wait_tick();
        if (keys_irq & K_FIRE)
            return 1;
        move_droids();
        doors();
        draw();
    }
    return 0;
}

/* the title page, a page of the briefing and the deck with its droids, in
 * turns, until fire is pressed and let go */
void title_run(unsigned char over)
{
    if (over)
        terminated();
    panel_status("Press fire");
    for (;;) {
        title_page();
        if (fire_in(300) || brief() || attract(150))
            break;
    }
    while (keys_irq & K_FIRE)
        wait_tick();
}
