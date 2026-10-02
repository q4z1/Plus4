/*
 * title.c - waiting for a game, as the original does it
 *
 * An overlay: this code, the briefing's text and the logo (build/gen/
 * brief.s) are linked to run in the slots of the pre-shifted pictures,
 * all of them, as the title needs none (paradroid.cfg), and are a file of
 * their own on the disk, "title", which paradroid.c loads for each title.
 * Its variables are in the program's memory, so they stay from one title
 * to the next. After a game, the original's "Transmission terminated" is
 * on the screen while it loads (paradroid.c).
 *
 * The original's title has its own sound throughout, a falling sweep and
 * a wavering low tone (music.s).
 *
 * The original's title goes round: first its logo over the whole screen;
 * then the four pages of the briefing, in a colour of their own each round
 * (yellow, pink, light green); then on white the day's top and worst
 * scores, the keys and the credits, with a droid's picture beside them.
 *
 * The briefing's text comes with the characters it needs, as codes of the
 * panel's set (brief_srcs), and its letters: letter k is character
 * brief_top[k] over brief_bot[k]. A page is rolled up through the window
 * a line of pixels at a time, the way the deck scrolls: picture 1's
 * character set holds the briefing's, and both pictures show it.
 */
#include <string.h>
#include "game.h"

#pragma code-name (push, "OVLCODE")
#pragma rodata-name (push, "OVLDATA")
#pragma data-name (push, "OVLDATA")     /* (variables with a start value) */

void wait_tick(void);
void mus_start(void);                   /* music.s: the original's sound */
void mus_stop(void);
extern unsigned long top_score, low_score;  /* paradroid.c: the day's */
extern char top_name[4], low_name[4];
extern unsigned char _OVL_LAST__[];     /* free after the overlay */

#define SCR0A ((unsigned char *)0xC000)
#define SCR0C ((unsigned char *)0xC400)
#define SCR1A ((unsigned char *)0xD000)
#define SCR1C ((unsigned char *)0xD400)

static const unsigned char *bpage;      /* the page shown */
static const unsigned char *bnext;      /* the one after it */
static unsigned char b_h;               /* its rows */
static unsigned char b_fg;              /* its letters' colour */
static unsigned char free_code;         /* picture 1's first character not in use */

/* the scores page's picture (the original's: a 614), loaded once a title
 * behind the overlay: its characters, layout and colours. The page is in
 * multicolour for it, so its letters' colour is one of 0-7. */
#define PIC_TYPE 14
#define PIC_ROW  1                      /* its first row in the page */
static unsigned char *pic, *pic_lay;
static unsigned char pic_n, pic_rows, pic_col, pic_code;

/* the rounds' colours: background, letters, border */
static const unsigned char round_bg[3] = { 0x77, 0x5B, 0x7F };
static const unsigned char round_fg[3] = { 0x48, 0x39, 0x00 };
static const unsigned char round_bd[3] = { 0x3B, 0x3B, 0x55 };

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

/* until picture t; 1 as soon as fire is pressed */
static unsigned char fire_by(unsigned char t)
{
    while ((signed char)(frames - t) < 0)
        if (keys_irq & K_FIRE)
            return 1;
    return 0;
}

/* just after a picture has begun */
static void frame_start(void)
{
    static unsigned char f;
    while (ready)
        ;
    f = frames;
    while (frames == f)
        ;
}

/* the briefing's character set in picture 1's, which both show; the page
 * cleared to colour a */
static void brief_font(unsigned char a)
{
    static unsigned char k;
    frame_start();
    win_clear(0, a);
    for (k = 0; k < NBRIEF; ++k)
        memcpy(FONT1 + k * 8, PANELF + brief_srcs[k] * 8, 8);
    font_hi[0] = 0xD8;
    free_code = NBRIEF;
}

/* picture 0's character set again, and picture 1's deck characters */
static void deck_font(void)
{
    frame_start();
    win_clear(0, 0x71);
    memcpy(FONT1, FONT0, POOL * 8);
    font_hi[0] = 0xC8;
}

/* the panel's frame in the border's colour: its cells, those in the
 * border's colour at first, are noted in fmask */
static unsigned char fmask[30];

static void frame_note(void)
{
    static unsigned char i, b;
    for (i = 0; i < 240; ++i) {
        b = 1 << (i & 7);
        if (SCR0A[i] == col_border)
            fmask[i >> 3] |= b;
        else
            fmask[i >> 3] &= ~b;
    }
}

static void frame(unsigned char to)
{
    static unsigned char i;
    for (i = 0; i < 240; ++i)
        if (fmask[i >> 3] & (1 << (i & 7)))
            SCR0A[i] = SCR1A[i] = to;
}

/* the page rolled up by y pixels, into the back picture. As for the deck,
 * the rows move down by k lines and window row 0 shows its last k lines,
 * from copies of its characters with the rest cleared. A line of text is
 * its row, column, length and letters. The scores page has its picture
 * too, in the rows from PIC_ROW. */
static unsigned char *cut, cut_end;

static unsigned char cut_copy(unsigned char c, unsigned char k)
{
    static unsigned char *g, *o;
    if (!cut_end)
        return 0;
    g = FONT1 + c * 8;
    o = FONT1 + *cut * 8;
    memset(o, 0, 8 - k);
    memcpy(o + 8 - k, g + 8 - k, k);
    --cut_end;
    return (*cut)++;
}

/* Rows 1 to 15 only change when the page has moved by a row: the lines
 * between, the fine scroll moves them, and only row 0, the cut one, is
 * made again. shown[] is each picture's row as last made (0xFF: none). */
static unsigned char shown[2] = { 0xFF, 0xFF };

static void page_show(unsigned y, unsigned char with_pic)
{
    static unsigned char *d, *a, *q;
    static const unsigned char *p, *l;
    static unsigned char k, rr, r, n, h, w, i, c, half, code;
    static unsigned char rows = 16;     /* (in the overlay: a start value) */
    k = (unsigned char)-(unsigned char)y & 7;
    rr = (y + k) >> 3;                  /* the page's row in window row 1 */
    rows = shown[back] == rr ? 1 : 16;  /* the rows to make */
    shown[back] = rr;
    d = (back ? SCR1C : SCR0C) + 9 * 40;
    a = (back ? SCR1A : SCR0A) + 9 * 40;
    memset(d, 0, rows * 40);
    /* each picture copies of its own: the free characters halved */
    half = (unsigned char)(256 - free_code) >> 1;
    code = back ? free_code + half : free_code;
    cut = &code;
    cut_end = half;
    for (p = bpage + 1; (r = *p) != 0xFF; p += 3 + n) {
        n = p[2];
        for (h = 0; h < 2; ++h) {
            w = r + h + 1 - rr;         /* its window row */
            if (w >= rows || (!w && !k))
                continue;
            q = d + w * 40 + p[1];
            for (i = 0; i < n; ++i) {
                c = h ? brief_bot[p[3 + i]] : brief_top[p[3 + i]];
                q[i] = w ? c : c ? cut_copy(c, k) : 0;
            }
        }
    }
    bnext = p[1] ? p + 1 : brief_pages;
    if (with_pic) {
        /* its column of cells: the text's colour, then the picture's */
        for (w = 0, q = a + 2; w < rows; ++w, q += 40)
            memset(q, b_fg, 6);
        for (r = 0, l = pic_lay; r < pic_rows; ++r)
            for (i = 0; i < 6; ++i, ++l) {
                w = PIC_ROW + r + 1 - rr;
                if (!*l || w >= rows || (!w && !k))
                    continue;
                c = pic_code + (*l & 0x7F) - 1;
                d[w * 40 + 2 + i] = w ? c : cut_copy(c, k);
                a[w * 40 + 2 + i] = *l & 0x80 ? pal_deck[pic_col] : pal_mc[pic_col] | 8;
            }
    }
    e_sx = 0;
    e_cutrow = 0;
    e_s = k;
    r_done();
}

/* the day's score into page 4's line at off: the number in eight cells,
 * " - ", the initials */
static void score_line(unsigned off, unsigned long v, const char *name)
{
    static unsigned char *l, i, c;
    l = (unsigned char *)brief_pages + off;
    for (i = 8; i--; v /= 10)
        l[i] = v || i == 7 ? brief_dig[(unsigned char)(v % 10)] : brief_misc[0];
    l[8] = l[10] = brief_misc[0];
    l[9] = brief_misc[1];
    for (i = 0, l += 11; i < 3; ++i, l += 2) {
        c = name[i] - 'A';
        l[0] = c < 26 ? brief_cap[c * 2] : brief_misc[0];
        l[1] = c < 26 ? brief_cap[c * 2 + 1] : brief_misc[0];
    }
}

/* page n of the briefing, rolled up, on bg in letters fg, the border bd;
 * page 4 has the picture; 1 if fire ended it */
static unsigned char brief(unsigned char n, unsigned char bg, unsigned char fg, unsigned char bd)
{
    static unsigned y, end;
    static unsigned char cd, cb, pic_on, hit;
    static unsigned char t = 0, dt = 0; /* (in the overlay: a start value) */
    static const unsigned char *p;
    cd = col_deck;
    cb = col_border;
    eng_plain();
    b_fg = fg;
    brief_font(fg);
    pic_on = n == 4;
    if (pic_on) {
        pic_code = free_code;
        memcpy(FONT1 + pic_code * 8, pic, pic_n * 8);
        free_code += pic_n;
        col_fig2 = pal_deck[pic[(unsigned)pic_n * 8 + pic_rows * 6 + 3]];
        score_line(SCORE_TOP_AT, top_score, top_name);
        score_line(SCORE_LOW_AT, low_score, low_name);
    }
    col_deck = bg;
    win_mc = pic_on ? 0x10 : 0;         /* hires but for the picture */
    frame_note();
    col_border = bd;
    frame(bd);
    panel_status("Briefing");
    for (bpage = brief_pages; n--; ) {  /* page n: past the lines before */
        p = bpage + 1;
        while (*p != 0xFF)
            p += 3 + p[2];
        bpage = p + 1;
    }
    b_h = *bpage;
    end = b_h * 8 > 120 ? b_h * 8 - 120 : 0;
    /* a line of pixels a tick, as the original; two while the joystick
     * is held down */
    shown[0] = shown[1] = 0xFF;
    for (y = 0; ; ) {
        while (ready)
            ;
        page_show(y, pic_on);
        if (y == 0 || y == end) {
            hit = fire_in(120);
            t = frames - 3;
        } else
            hit = fire_by(t + 3);
        if (hit || y == end)
            break;
        /* as many lines as ticks have gone by: a step that took longer
         * (a new row of characters) is made up for */
        dt = (unsigned char)(frames - t) / 3;
        t += dt * 3;
        y += keys_irq & K_DOWN ? dt << 1 : dt;
        if (y > end)
            y = end;
    }
    deck_font();
    win_mc = 0x10;
    col_deck = cd;
    frame(cb);
    col_border = cb;
    col_fig2 = 0x71;
    panel_status("Press fire");
    return hit;                         /* (a short press is over by now) */
}

/* the original's logo over the whole screen, the panel's rows too; 1 if
 * fire ended it */
static unsigned char logo(void)
{
    static const unsigned char *p;
    static unsigned char c, n, cd, cb, cp, k;
    static unsigned off;
    eng_plain();
    frame_start();
    /* the panel's rows kept where the pool's characters are */
    memcpy(FONT0 + POOL * 8, SCR0C, 240);
    memcpy(FONT0 + POOL * 8 + 240, SCR0A, 240);
    memcpy(FONT1, logo_font, NLOGO * 8);
    for (p = logo_rle, off = 0; (n = p[1]) != 0; p += 2)
        for (c = p[0]; n; --n, ++off) {
            SCR0C[off] = SCR1C[off] = c;
            SCR0A[off] = SCR1A[off] = pal_deck[logo_col[c]];
        }
    cd = col_deck;
    cb = col_border;
    cp = col_panel;
    col_deck = col_border = col_panel = pal_deck[LOGO_BG];
    font_hi[0] = 0xD8;
    panel_hi = 0xD8;
    k = fire_in(200);
    frame_start();
    panel_hi = 0xE0;                    /* the panel's set again */
    col_deck = cd;
    col_border = cb;
    col_panel = cp;
    memcpy(SCR0C, FONT0 + POOL * 8, 240);
    memcpy(SCR1C, FONT0 + POOL * 8, 240);
    memcpy(SCR0A, FONT0 + POOL * 8 + 240, 240);
    memcpy(SCR1A, FONT0 + POOL * 8 + 240, 240);
    memset(SCR0C + 240, 0, 120);        /* the gap rows: blank again */
    memset(SCR1C + 240, 0, 120);
    deck_font();
    return k;
}

/* the title's rounds, until fire is pressed and let go */
void title_run(void)
{
    static unsigned char r, n, *e;
    static unsigned size;
    /* the scores page's picture, behind the overlay */
    pic = _OVL_LAST__;
    size = load_file("p14", pic);
    e = pic + (pic[size - 2] | pic[size - 1] << 8);
    pic_n = e[0];
    pic_rows = e[1];
    pic_col = e[2];
    pic_lay = e - pic_rows * 6;
    mus_start();
    panel_status("Press fire");
    for (r = 0; ; r = r < 2 ? r + 1 : 0) {
        if (logo())                     /* the original's starts with it */
            break;
        for (n = 0; n < 4; ++n)
            if (brief(n, round_bg[r], round_fg[r], round_bd[r]))
                goto out;
        if (brief(4, pal_deck[1], pal_mc[8], round_bd[r]))
            break;
    }
out:
    while (keys_irq & K_FIRE)
        wait_tick();
    mus_stop();                         /* (the overlay's memory goes) */
}
