/*
 * console.c - the ship's computer, as the original's
 *
 * Always there: its code runs at $F400 (paradroid.cfg), copied there at the
 * start; its data is in the program. paradroid.c runs it when fire is held
 * at a console.
 *
 * The original's console: a page with the host's unit and the ship, deck
 * and alert, and a menu of four symbols beside it. Up and down choose,
 * fire takes the symbol: the first leaves, the second is the droid
 * enquiry, the third the plan of the deck, the fourth the ship from the
 * side. Fire goes back to the menu from there.
 *
 * The enquiry shows a droid's picture and its pages, as the original
 * words them; both come with the picture's file from the disk (transfer.c,
 * picture()). Right and left turn the pages, up and down go through the
 * droid types the host is cleared for: its own and those below.
 *
 * The plan is the original's: a character a block, the character's code
 * being the block's number, in the original's characters and colours, and
 * the deck's blocks 3 to 41 across, as the original cuts it.
 */
#include <string.h>
#include "game.h"

#pragma code-name (push, "HICODE")

void wait_tick(void);
void x_letter(unsigned char c);
extern unsigned char xmap[128];
extern const unsigned char plan_font[], plan_col[];
extern const unsigned char icon_font[], icon_tab[], icon_lay[];
extern const unsigned char *pic_pages;  /* transfer.c: the picture's pages */

static unsigned char k, prev;

static void tick_keys(void)
{
    wait_tick();
    prev = k;
    k = keys_irq;
}

static unsigned char pressed(unsigned char b)
{
    return (k & b) && !(prev & b);
}

/* picture 1's set for the window, cleared to colour a, on background bg */
static void clear(unsigned char bg, unsigned char a)
{
    while (ready)
        ;
    eng_plain();
    win_clear(0, a);
    col_deck = bg;
    font_hi[0] = 0xD8;
    x_code = 140;
    memset(xmap, 0, sizeof xmap);
}

/* text in the panel's letters at row, col */
static void text(unsigned char row, unsigned char col, const char *s)
{
    x_row = row;
    x_col = col;
    say(s);
}

/* the unit line: "Unit type 476 - Maintenance robot" */
static void unit_line(unsigned char t)
{
    static char num[4];
    num[0] = '0' + dr_class[t];
    num[1] = '0' + dr_num[t] / 10;
    num[2] = '0' + dr_num[t] % 10;
    num[3] = 0;
    text(10, 3, "Unit type ");
    say(num);
    say(" - ");
    say(unit_name(t));
}

/* ---- the menu page ---- */

static const char *const deck_name[16] = {
    DECK_NAMES
};
static const char *const alert_name[4] = { "green", "yellow", "amber", "red" };

static unsigned char sel;

/* the menu's symbols: the chosen one white, the others light grey */
static void icons(void)
{
    static unsigned char i, r, c, v, w, h;
    static const unsigned char *p, *t;
    p = icon_lay;
    t = icon_tab;
    for (i = 0; i < 4; ++i, t += 4) {
        w = t[2];
        h = t[3];
        for (r = 0; r < h; ++r)
            for (c = 0; c < w; ++c)
                if ((v = *p++) != 0) {
                    wp_row = t[1] + r;
                    wp_col = t[0] + c;
                    wp_code = ICON_CODE + v - 1;
                    wp_attr = i == sel ? pal_deck[1] : pal_deck[15];
                    win_put();
                }
    }
}

static void menu_page(void)
{
    clear(0x48, 0x71);                  /* the original's orange */
    memcpy(FONT1 + ICON_CODE * 8, icon_font, ICON_N * 8);
    x_attr = pal_deck[7];
    unit_line(d_type[0]);
    text(12, 12, "Access granted.");
    text(15, 12, "Ship  : Paradroid");
    text(18, 12, "Deck  : ");
    say(deck_name[deck]);
    text(21, 12, "Alert : ");
    say(alert_name[alert]);
    icons();
    panel_status("Console");
}

/* ---- the droid enquiry ---- */

/* page n of type t's: lines of row, column, length and letters, then $FF;
 * a 0 after the last page */
static void enquiry_page(unsigned char t, unsigned char n)
{
    static const unsigned char *p;
    static unsigned char i, len, first;
    first = n == 0;
    picture(t, 11, 2);
    col_deck = pal_deck[1];
    x_code = 140;
    x_attr = 0x63;                      /* the original's light cyan */
    unit_line(t);
    x_attr = pal_mc[2];                 /* (beside a multicolour picture) */
    p = pic_pages;
    while (n--)
        while (*p++ != 0xFF)
            ;
    while (*p != 0xFF) {
        x_row = p[0];
        x_col = p[1];
        len = p[2];
        p += 3;
        for (i = 0; i < len; ++i)
            x_letter(*p++);
    }
    panel_status(first ? "Console" : "More...");
}

static void enquiry(void)
{
    static unsigned char t, n, pages, top;
    static const unsigned char *p;
    top = d_type[0];
    t = top;
    n = 0;
    for (;;) {
        enquiry_page(t, n);
        for (pages = 0, p = pic_pages; *p; ++pages)
            while (*p++ != 0xFF)
                ;
        do
            tick_keys();
        while (!(pressed(K_FIRE) || pressed(K_LEFT) || pressed(K_RIGHT)
                 || pressed(K_UP) || pressed(K_DOWN)));
        if (pressed(K_FIRE))
            return;
        if (pressed(K_RIGHT))
            n = n + 1 < pages ? n + 1 : 0;
        else if (pressed(K_LEFT))
            n = n ? n - 1 : pages - 1;
        else {
            t = pressed(K_UP) ? (t ? t - 1 : top) : (t < top ? t + 1 : 0);
            n = 0;
        }
        sound(SFX_LIFT);
    }
}

/* ---- the deck plan ---- */

static void plan(void)
{
    static unsigned char x, y, b;
    static unsigned off;
    clear(deck_bg, 0x71);
    memcpy(FONT1, plan_font, 33 * 8);
    for (y = 0; y < 16; ++y)
        for (x = 3; x < 42; ++x) {
            b = DMAP[((unsigned)y << 6) | x] >> 2;
            if (b >= BLK_VOPEN)         /* a door half open: the door */
                b = b < BLK_HOPEN ? BLK_VDOOR : BLK_HDOOR;
            if (x == (PX >> 5) && y == (PY >> 5))
                b = 32;                 /* the player */
            off = (9 + y) * 40 + x - 3;
            ((unsigned char *)0xC400)[off] = ((unsigned char *)0xD400)[off] = b;
            ((unsigned char *)0xC000)[off] = ((unsigned char *)0xD000)[off] =
                pal_deck[plan_col[b]];  /* hires, as the original's */
        }
    panel_status("Deck plan");
}

/* ---- the console ---- */

void console_run(void)
{
    static unsigned char cd;
    cd = col_deck;
    sel = 0;
    k = keys_irq;
    menu_page();
    for (;;) {
        tick_keys();
        if (pressed(K_UP) || pressed(K_DOWN)) {
            sel = (sel + (pressed(K_UP) ? 3 : 1)) & 3;
            icons();
            sound(SFX_LIFT);
        }
        if (!pressed(K_FIRE))
            continue;
        if (sel == 0)
            break;
        if (sel == 1)
            enquiry();
        else {
            if (sel == 2)
                plan();
            else {
                font_hi[0] = 0xC8;
                side_view();
                side_light(deck);
                panel_status("Ship");
            }
            do
                tick_keys();
            while (!pressed(K_FIRE));
        }
        font_hi[0] = 0xC8;
        menu_page();
    }
    page_end(cd);
    while (keys_irq & K_FIRE)
        wait_tick();
    panel_status("Mobile");
}
