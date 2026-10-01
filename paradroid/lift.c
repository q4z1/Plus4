/*
 * lift.c - riding a lift: the side view of the ship
 *
 * Standing on a lift with fire held shows the ship from the side, as the
 * original does, with the lift's shaft and its cabin at the deck. Up and
 * down move the cabin along the shaft, letting go of fire gets out there.
 * The picture is the original's, drawn into the window of both pictures
 * with its characters put where the figures' usually are.
 */
#include <string.h>
#include "game.h"

void eng_plain(void);
void wait_tick(void);
void enter(unsigned char d, unsigned char bx, unsigned char by);

#define CABIN 0x6F                      /* the cabin: yellow, multicolour */

static unsigned char side_attr(unsigned char col)
{
    return col >= 8 ? (pal_deck[col & 7] | 8) : pal_deck[col];
}

static void put(unsigned char row, unsigned char col, unsigned char code, unsigned char a)
{
    wp_row = row;
    wp_col = col;
    wp_code = code;
    wp_attr = a;
    win_put();
}

static void side_view(void)
{
    static unsigned char r, c, m;
    static const unsigned char *p;
    memcpy(FONT0 + (POOL + SIDE_BASE) * 8, side_font, NSIDE * 8);
    memcpy(FONT1 + (POOL + SIDE_BASE) * 8, side_font, NSIDE * 8);
    eng_plain();
    win_clear(0, 0x71);
    p = side_map;
    for (r = 8; r < 8 + SIDE_ROWS; ++r)
        for (c = 0; c < 39; ++c) {
            m = *p++;
            if (m != 0xFF)
                put(r, c, POOL + m, side_attr(side_col[m - SIDE_BASE]));
        }
}

static void shaft(unsigned char s, unsigned char cabin_row)
{
    static unsigned char r, a;
    for (r = 0; r < shaft_len[s]; ++r) {
        a = shaft_top[s] + r == cabin_row ? CABIN
            : side_attr(side_col[SIDE_SHAFT - SIDE_BASE]);
        put(8 + shaft_top[s] + r, shaft_col[s], POOL + SIDE_SHAFT, a);
    }
}

static void deck_name(unsigned char li)
{
    static char buf[8];
    static unsigned char d;
    d = lift_deck[li];
    strcpy(buf, "Deck ");
    if (d >= 10) {
        buf[5] = '1';
        buf[6] = '0' + d - 10;
        buf[7] = 0;
    } else {
        buf[5] = '0' + d;
        buf[6] = 0;
    }
    panel_status(buf);
}

void ride_lift(unsigned char li)
{
    static unsigned char k, prev, n;
    while (ready)
        ;
    side_view();
    shaft(lift_shaft[li], deck_row[lift_deck[li]]);
    deck_name(li);
    prev = keys_irq;
    for (;;) {
        wait_tick();
        k = keys_irq;
        if (!(k & K_FIRE))
            break;
        n = li;
        if ((k & K_UP) && !(prev & K_UP) && li > 0
            && lift_shaft[li - 1] == lift_shaft[li])
            n = li - 1;
        if ((k & K_DOWN) && !(prev & K_DOWN) && li + 1 < NLIFTS
            && lift_shaft[li + 1] == lift_shaft[li])
            n = li + 1;
        prev = k;
        if (n != li) {
            li = n;
            shaft(lift_shaft[li], deck_row[lift_deck[li]]);
            deck_name(li);
            sound(SND_LIFT);
        }
    }
    if (lift_deck[li] != deck)
        enter(lift_deck[li], lift_bx[li], lift_by[li]);
    panel_status("Mobile");
}
