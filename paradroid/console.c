/*
 * console.c - the ship's computer: a plan of the deck
 *
 * Fire held at a console shows the deck from above, a character a block:
 * walls, doors, lifts, energizers, consoles, the droids, and where the
 * player is. Letting go of fire goes back.
 */
#include <string.h>
#include "game.h"

void wait_tick(void);

#define MAP_ROW 9                       /* screen row of the plan's top */

static unsigned char x0;                /* deck block at plan column 0 */

static void put(unsigned char row, unsigned char col, unsigned char code, unsigned char a)
{
    wp_row = row;
    wp_col = col;
    wp_code = code;
    wp_attr = a;
    win_put();
}

/* the console next to the player, if any */
unsigned char console_here(void)
{
    return (blk_flag[blk_at(PX - 20, PY)] | blk_flag[blk_at(PX + 20, PY)]
            | blk_flag[blk_at(PX, PY - 18)] | blk_flag[blk_at(PX, PY + 18)])
           & B_CONSOLE;
}

static void cell(unsigned char bx, unsigned char by)
{
    static unsigned char b, f, g, a;
    b = DMAP[((unsigned)by << 6) | bx] >> 2;
    f = blk_flag[b];
    a = 0x36;
    if (b == 0)
        g = X_BLANK;
    else if (f & B_LIFT) {
        g = X_LIFT;
        a = 0x67;
    } else if (f & B_ENERGY) {
        g = X_SOCKET;
        a = 0x67;
    } else if (f & B_CONSOLE) {
        g = X_SOCKET;
        a = 0x63;
    } else if (f & B_DOOR) {
        g = X_WIRE;
        a = 0x71;
    } else if (f & B_SOLID)
        g = X_LIGHT;
    else
        g = X_BLANK;
    put(MAP_ROW + by, bx - x0, POOL + g, a);
}

/* what the enquiry shows, in words */
static const char *const class_name[10] = {
    "influence", "disposal", "servant", "messenger", "maintenance",
    "crew", "sentinel", "battle", "security", "command"
};
static const char *const weapon_name[4] = { "none", "light laser", "laser", "disruptor" };

static char buf[4];

/* what the computer knows about droid type t */
static void droid_page(unsigned char t)
{
    win_clear(0, 0x71);
    win_text(0, 4, "unit", 0x71);
    buf[0] = '0' + dr_class[t];
    buf[1] = '0' + dr_num[t] / 10;
    buf[2] = '0' + dr_num[t] % 10;
    buf[3] = 0;
    win_text(0, 9, buf, 0x67);
    win_text(1, 4, "class", 0x71);
    win_text(1, 12, class_name[dr_class[t]], 0x67);
    win_text(3, 4, "speed", 0x71);
    win_text(3, 12, num_text(dr_drive[t]), 0x67);
    win_text(4, 4, "weapon", 0x71);
    win_text(4, 12, weapon_name[dr_weapon[t]], 0x67);
    win_text(5, 4, "pulses", 0x71);
    win_text(5, 12, num_text(3 + dr_class[t] / 3), 0x67);
}

/* the droid enquiry: left and right go through the types the player's
 * host is cleared for - its own class and below */
static void droids_info(void)
{
    static unsigned char t, k, prev, top;
    win_letters();
    top = dr_class[d_type[0]];
    t = 0;
    while (t + 1 < NDROIDS && dr_class[t + 1] <= top)
        ++t;
    droid_page(t);
    panel_status("Droids");
    prev = keys_irq;
    while (keys_irq & K_FIRE) {
        wait_tick();
        k = keys_irq;
        if ((k & K_RIGHT) && !(prev & K_RIGHT) && t + 1 < NDROIDS
            && dr_class[t + 1] <= top)
            droid_page(++t);
        if ((k & K_LEFT) && !(prev & K_LEFT) && t > 0)
            droid_page(--t);
        prev = k;
    }
    panel_status("Mobile");
}

void deck_plan(void)
{
    static unsigned char bx, by, lo, hi, i, k, px, py;
    while (ready)
        ;
    memcpy(FONT0 + POOL * 8, xfer_font, NXFER * 8);
    memcpy(FONT1 + POOL * 8, xfer_font, NXFER * 8);
    eng_plain();
    /* the deck's width, and where the plan starts so it fits */
    lo = 63;
    hi = 0;
    for (by = 0; by < 16; ++by)
        for (bx = 0; bx < 64; ++bx)
            if (DMAP[((unsigned)by << 6) | bx]) {
                if (bx < lo)
                    lo = bx;
                if (bx > hi)
                    hi = bx;
            }
    px = PX >> 5;
    py = PY >> 5;
    if (hi - lo < 38)
        x0 = lo - (38 - (hi - lo)) / 2;
    else {
        x0 = px > 19 ? px - 19 : 0;
        if (x0 < lo)
            x0 = lo;
        if (x0 + 38 > hi)
            x0 = hi - 38;
    }
    win_clear(POOL + X_BLANK, 0x71);
    for (by = 0; by < 16; ++by)
        for (bx = 1; bx < 39; ++bx)
            if ((unsigned char)(x0 + bx) < 64 && DMAP[((unsigned)by << 6) | (x0 + bx)])
                cell(x0 + bx, by);
    /* the droids */
    for (i = 1; i < nd; ++i)
        if (!d_boom[i]) {
            bx = (d_x[i] >> 5) - x0;
            if (bx > 0 && bx < 39)
                put(MAP_ROW + (d_y[i] >> 5), bx, POOL + X_LIGHT, 0x71);
        }
    panel_status("Deck plan");
    k = 0;
    while (keys_irq & K_FIRE) {
        wait_tick();
        if (keys_irq & (K_LEFT | K_RIGHT)) {
            droids_info();
            return;
        }
        if ((++k & 3) == 0) {
            bx = px - x0;
            if (bx > 0 && bx < 39) {
                if (k & 4)
                    put(MAP_ROW + py, bx, POOL + X_LIGHT, 0x67);
                else
                    cell(px, py);
            }
        }
    }
    panel_status("Mobile");
}
