/*
 * draw.c - the picture: the window onto the deck, the figures in it, and
 * the status panel above
 */
#include <string.h>
#include "game.h"

/* ======================================================================
 * Pictures, shifted in advance
 *
 * engine.s draws a figure from a copy shifted for each of the four
 * multicolour pixels it can start at inside a cell (512 bytes, a slot).
 * Explosions and lasers are made once; the droids when a deck is entered,
 * for the types on it; the player's when he changes host.
 * ==================================================================== */

/* pre[]: the slots, 512 bytes each, where the start-up data was (data.s);
 * PRE_SLOTS there must be NSLOT */
unsigned char slot_of[NDROIDS];         /* 255: none */
static unsigned char pimg[DROID_H * 4];
unsigned char tick;
unsigned char hide_player;               /* the title: droids only */

static void shift_into(unsigned char n, const unsigned char *img, unsigned char h)
{
    f_src = img;
    f_h = h;
    p_pre = pre + ((unsigned)n << 9);
    pre_shift();
}

void pictures_fixed(void)
{
    static unsigned char i;
    for (i = 0; i < NEXPLO; ++i)
        shift_into(SLOT_EXPLO + i, explo_img + i * (EXPLO_H * 4), EXPLO_H);
    shift_into(SLOT_LASER + 0, laser_v, 16);
    shift_into(SLOT_LASER + 1, laser_d1, 16);
    shift_into(SLOT_LASER + 2, laser_h, 16);
    shift_into(SLOT_LASER + 3, laser_d2, 16);
}

/* a droid's picture into pimg: the template with its number in the band,
 * light digits on the dark body */
static void droid_picture(unsigned char t)
{
    static unsigned char k, d, y, x, px, sh, i;
    static unsigned bits;
    static const unsigned char *g;
    memcpy(pimg, droid_tmpl, DROID_H * 4);
    for (k = 0; k < 3; ++k) {
        d = k == 0 ? dr_class[t] : k == 1 ? dr_num[t] / 10 : dr_num[t] % 10;
        g = digit_bits + d * 2;
        bits = g[0] | (g[1] << 8);
        for (y = 0; y < 5; ++y)
            for (x = 0; x < 3; ++x, bits >>= 1)
                if (bits & 1) {
                    px = 1 + k * 4 + x;
                    i = (5 + y) * 4 + (px >> 2);
                    sh = (3 - (px & 3)) << 1;
                    pimg[i] = (pimg[i] & ~(3 << sh)) | (2 << sh);
                }
    }
}

/* a pixel of pimg made see-through */
static void clear_px(unsigned char line, unsigned char x)
{
    static unsigned char i;
    i = line * 4 + (x >> 2);
    pimg[i] &= ~(3 << ((3 - (x & 3)) << 1));
}

/* the player's droid: the same picture with its two colours swapped, in
 * four turns of its domes - as in the original, a slanted gap runs round
 * them from right to left */
static const unsigned char gap_at[4] = { 9, 7, 5, 3 };

void player_picture(void)
{
    static unsigned char i, b, f, r;
    static unsigned char base[DROID_H * 4];
    droid_picture(d_type[0]);
    for (i = 0; i < DROID_H * 4; ++i) {
        b = pimg[i];
        base[i] = ((b & 0x55) << 1) | ((b & 0xAA) >> 1);
    }
    for (f = 0; f < 4; ++f) {
        memcpy(pimg, base, sizeof base);
        for (r = 0; r < 3; ++r) {
            clear_px(r, gap_at[f] + r - 1);
            clear_px(14 - r, gap_at[f] + r - 1);
        }
        shift_into(f ? SLOT_PANIM + f - 1 : SLOT_PLAYER, pimg, DROID_H);
    }
}

void pictures_deck(void)
{
    static unsigned char i, t, n;
    memset(slot_of, 255, sizeof slot_of);
    player_picture();
    n = SLOT_DROID;
    for (i = 1; i < nd; ++i) {
        t = d_type[i];
        if (slot_of[t] == 255 && n < SLOT_DROID + NSLOT_DROID) {
            slot_of[t] = n;
            droid_picture(t);
            shift_into(n, pimg, DROID_H);
            ++n;
        }
    }
}

/* ======================================================================
 * The window onto the deck
 * ==================================================================== */

static int win_l, win_t;                /* world pixel at the window's corner */
static int org_x, org_y;                /* window column 0 / row 0, less 64 */

static void window(void)
{
    static unsigned char k;
    static signed char r0;
    win_l = (int)PX - 152;
    win_t = (int)PY - 68;
    e_sx = (unsigned char)(-win_l) & 7;
    e_m0 = (unsigned char)(((win_l + e_sx) >> 3) - 1);
    /* rows under the gap move down by k: window row 0 (screen row 7)
     * shows its last k lines at the window's top, or nothing */
    k = (unsigned char)(-win_t) & 7;
    e_s = k;
    r0 = (signed char)(((win_t + k) >> 3) - 1);
    e_r = r0;
    org_x = win_l + e_sx - 8 - 64;
    org_y = ((int)r0 << 3) - 64;
    e_blank7 = (k == 0);
    e_cutrow = k ? 1 : 0;
    e_cutn = 8 - k;
}

/* a figure with its top left corner at world pixel (fig_x, fig_y), from
 * slot fig_n */
static int fig_x, fig_y;
static unsigned char fig_n;

static void figure(void)
{
    static int rx, ry;
    /* relative to window column 0 and row 0, plus 64 to stay positive */
    rx = fig_x - org_x;
    ry = fig_y - org_y;
    if ((unsigned)rx > 64 + 320 || (unsigned)ry > 64 + 160)
        return;
    f_col = (signed char)((unsigned char)(rx >> 3) - 8);
    f_row = (signed char)((unsigned char)(ry >> 3) - 8);
    f_line = (unsigned char)ry & 7;
    f_pre = pre + ((unsigned)fig_n << 9) + (((unsigned char)rx & 6) << 6);
    r_fig();
}

/* shot pictures: where their top left corner is from their middle */
static const signed char laser_ox[4] = { -12, -12, -12, -12 };
static const signed char laser_oy[4] = { -8, -8, -8, -8 };

void draw(void)
{
    static unsigned char i, b;
    window();
    while (ready)
        ;
    r_begin();
    for (i = 1; i < nd; ++i) {
        b = d_boom[i];
        if (b == BOOM_GONE)
            continue;
        fig_x = d_x[i] - 13;
        fig_y = d_y[i] - 8;
        if (b) {
            fig_n = SLOT_EXPLO + ((b - 1) >> 1);
        } else {
            fig_n = slot_of[d_type[i]];
            if (fig_n == 255)
                continue;
        }
        figure();
    }
    for (i = 0; i < MAXS; ++i)
        if (s_life[i]) {
            b = s_img[i];
            fig_x = s_x[i] + laser_ox[b];
            fig_y = s_y[i] + laser_oy[b];
            fig_n = SLOT_LASER + b;
            figure();
        }
    fig_x = PX - 13;
    fig_y = PY - 8;
    b = d_boom[0];
    if (b) {
        if (b < BOOM_GONE) {
            fig_n = SLOT_EXPLO + ((b - 1) >> 1);
            figure();
        }
    } else if (hide_player) {
        ;
    } else if ((!transfer_mode || (tick & 2))
               && (d_energy[0] >= (emax(d_type[0]) >> 2) || (tick & 4))) {
        b = tick & 3;
        fig_n = b ? SLOT_PANIM + b - 1 : SLOT_PLAYER;
        figure();
    }
    r_done();
}

/* ======================================================================
 * The status panel
 * ==================================================================== */

#define PANEL_TEXT 0x32                 /* the panel's red */

static void panel_char(unsigned char col, unsigned char c)
{
    pp_attr = PANEL_TEXT;
    pp_off = 80 + col;
    pp_code = c;
    panel_put();
    pp_off = 120 + col;
    pp_code = c | 0x80;
    panel_put();
}

/* text in the panel's two-line letters from column col; capitals and m
 * and w are two columns wide. Returns the column after it. */
static unsigned char panel_text(unsigned char col, const char *s)
{
    static unsigned char ch, c, wide;
    while ((ch = *s++) != 0) {
        wide = 0;
        if (ch >= '0' && ch <= '9')
            c = ch - '0';
        else if (ch == 'm') {
            c = 0x42;
            wide = 1;
        } else if (ch == 'w') {
            c = 0x54;
            wide = 1;
        } else if (ch >= 'a' && ch <= 'z')
            c = ch - 'a' + 10;
        else if (ch >= 'A' && ch <= 'Z') {
            c = ch - 'A' + 0x3A;
            wide = 1;
        } else
            c = 0x30;                   /* space */
        panel_char(col++, c);
        if (wide)
            panel_char(col++, c + 0x20);
    }
    return col;
}

void panel_init(void)
{
    static unsigned i;
    for (i = 0; i < 240; ++i) {
        pp_off = i;
        pp_code = panel_codes[i];
        pp_attr = panel_cols[i] == 4 ? 0x34 : PANEL_TEXT;
        panel_put();
    }
    for (i = 240; i < 280; ++i) {
        pp_off = i;
        pp_code = 0;
        pp_attr = col_deck;
        panel_put();
    }
}

void panel_status(const char *s)
{
    static unsigned char col;
    col = panel_text(2, s);
    while (col < 13)
        panel_char(col++, 0x30);
}

/* a number as text, up to seven digits */
static char num_buf[8];
unsigned char num_len;

const char *num_text(unsigned long v)
{
    static unsigned char n;
    n = 7;
    do {
        num_buf[--n] = '0' + (unsigned char)(v % 10);
        v /= 10;
    } while (v && n);
    num_len = 7 - n;
    return num_buf + n;
}

void panel_score(void)
{
    static const char *t;
    static unsigned char col;
    t = num_text(score);
    col = 38 - num_len;
    while (col > 30)
        panel_char(--col, 0x30);
    panel_text(38 - num_len, t);
    score_changed = 0;
}

/* ======================================================================
 * Screens drawn straight into the window (lift, console, transfer)
 * ==================================================================== */

#define SCR0A ((unsigned char *)0xC000)
#define SCR0C ((unsigned char *)0xC400)
#define SCR1A ((unsigned char *)0xD000)
#define SCR1C ((unsigned char *)0xD400)

/* the window rows (screen rows 7 to 24) of both pictures cleared */
void win_clear(unsigned char code, unsigned char attr)
{
    memset(SCR0C + 7 * 40, code, 18 * 40);
    memset(SCR1C + 7 * 40, code, 18 * 40);
    memset(SCR0A + 7 * 40, attr, 18 * 40);
    memset(SCR1A + 7 * 40, attr, 18 * 40);
}

/* a cell of both pictures, from wp_row, wp_col, wp_code, wp_attr */
unsigned char wp_row, wp_col, wp_code, wp_attr;

void win_put(void)
{
    static unsigned off;
    off = wp_row * 40 + wp_col;
    SCR0C[off] = wp_code;
    SCR1C[off] = wp_code;
    SCR0A[off] = wp_attr;
    SCR1A[off] = wp_attr;
}

static void wput(unsigned char row, unsigned char col, unsigned char code, unsigned char a)
{
    wp_row = row;
    wp_col = col;
    wp_code = code;
    wp_attr = a;
    win_put();
}

/* Text in the window, in the panel's two-line letters: its digits and
 * small letters (codes 0..35 and their lower halves, +128) copied to the
 * pool, TXT + c on top and TXT + 36 + c below; m and w are two wide. */
#define TXT (POOL + 32)

static const unsigned char wide_src[8] = { 0x42, 0x62, 0x54, 0x74, 0xC2, 0xE2, 0xD4, 0xF4 };

void win_letters(void)
{
    static unsigned char i;
    memcpy(FONT0 + TXT * 8, PANELF, 36 * 8);
    memcpy(FONT1 + TXT * 8, PANELF, 36 * 8);
    memcpy(FONT0 + (TXT + 36) * 8, PANELF + 128 * 8, 36 * 8);
    memcpy(FONT1 + (TXT + 36) * 8, PANELF + 128 * 8, 36 * 8);
    /* m and w are two columns wide */
    for (i = 0; i < 8; ++i) {
        memcpy(FONT0 + (TXT + 72 + i) * 8, PANELF + wide_src[i] * 8, 8);
        memcpy(FONT1 + (TXT + 72 + i) * 8, PANELF + wide_src[i] * 8, 8);
    }
}

/* text in two-line letters at a text line (0..7) and column */
void win_text(unsigned char line, unsigned char col, const char *s, unsigned char a)
{
    static unsigned char ch, c;
    while ((ch = *s++) != 0) {
        if (ch == 'm' || ch == 'w') {
            c = ch == 'm' ? 72 : 74;
            wput(9 + line * 2, col, TXT + c, a);
            wput(9 + line * 2, col + 1, TXT + c + 1, a);
            wput(10 + line * 2, col, TXT + c + 4, a);
            wput(10 + line * 2, col + 1, TXT + c + 5, a);
            col += 2;
            continue;
        }
        if (ch >= '0' && ch <= '9')
            c = ch - '0';
        else if (ch >= 'a' && ch <= 'z')
            c = ch - 'a' + 10;
        else {
            ++col;
            continue;
        }
        wput(9 + line * 2, col, TXT + c, a);
        wput(10 + line * 2, col, TXT + 36 + c, a);
        ++col;
    }
}

/* rows top to top + 17 of a briefing page into the back picture. The page
 * is the original's text as on the disk (tools/mkdata.py): lines of row,
 * column, length and the panel's codes, then $FF. The window shows the
 * panel's character set meanwhile, so a letter is its code over code + 128.
 * Gives back where the page ends. */
const unsigned char *win_brief(const unsigned char *p, unsigned char top)
{
    static unsigned char *sc, *d;
    static unsigned char r, n, i, y;
    sc = back ? SCR1C : SCR0C;
    memset(sc + 7 * 40, 0x30, 18 * 40);
    while ((r = *p) != 0xFF) {
        n = p[2];
        for (y = 0; y < 2; ++y, ++r)
            if ((unsigned char)(r - top) < 18) {
                d = sc + (7 + r - top) * 40 + p[1];
                for (i = 0; i < n; ++i)
                    d[i] = p[3 + i] | (y << 7);
            }
        p += 3 + n;
    }
    return p + 1;
}

