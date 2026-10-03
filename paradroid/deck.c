/*
 * deck.c - the ship, its decks, doors and lifts
 */
#include <string.h>
#include "game.h"

unsigned char deck;                     /* the deck we are on */
unsigned char ship[NDECKS][12];
unsigned char level;
unsigned char ndoor;
unsigned char alert;
unsigned char deck_bg;                  /* the deck's colour, without a flash */

/* rnd(): engine.s */

/* The C64's colours on the TED: for each, the nearest of the TED's 121, as
 * VICE draws both (measured: tests of all colours on each machine). The
 * deck's light blue is the nearest of 0-7, as deck characters turn into
 * multicolour in the cells figures cover. The light green one level
 * darker than the nearest found (0x7F, 0x75): nearer the C64's to the
 * eye, and white figures, doors and consoles stand out on it. */
const unsigned char pal_deck[16] = {
    0x00, 0x71, 0x3B, 0x63, 0x4E, 0x55, 0x36, 0x77,
    0x48, 0x39, 0x5B, 0x31, 0x51, 0x6F, 0x56, 0x61
};

/* the same for multicolour cells, whose colour can only be 0-7: the
 * nearest of those */
const unsigned char pal_mc[16] = {
    0x00, 0x71, 0x42, 0x63, 0x44, 0x55, 0x36, 0x77,
    0x42, 0x37, 0x52, 0x31, 0x51, 0x65, 0x56, 0x61
};

/* colour_blocks(), deck_colours(): move.s, by the original's schemes */

unsigned char deck_cleared(unsigned char d)
{
    static unsigned char k;
    for (k = 0; k < 12; ++k)
        if (ship[d][k])
            return 0;
    return 1;
}

unsigned char ship_cleared(void)
{
    static unsigned char d;
    for (d = 0; d < NDECKS; ++d)
        if (!deck_cleared(d))
            return 0;
    return 1;
}

/* a new ship, as the original fills it: the first six droids of a deck
 * are of its class or up to three above, the others lower */
void new_ship(void)
{
    static unsigned char d, k, t, n, r;
    memset(ship, 0, sizeof ship);
    for (d = 0; d < NDECKS; ++d) {
        t = ship_base[d] + level;
        if (t > 0x13)
            t = 0x13;
        n = ship_count[d];
        if (n > 12)
            n = 12;
        for (k = 0; k < n; ++k) {
            if (k < 6)
                r = t + (rnd() & 3);
            else {
                r = rnd() & 15;
                while (r && r >= t + 3)
                    r >>= 1;
                if (!r)
                    continue;
            }
            ship[d][k] = r + 1;
        }
    }
    ship[1][11] = 0x17 + 1;             /* the command cyborg */
}

/* blk_at(): move.s */


/* ======================================================================
 * Loading a deck
 * ==================================================================== */

#define MAXDOOR 32
unsigned char door_x[MAXDOOR], door_y[MAXDOOR];   /* for doors(), move.s */
unsigned char door_v[MAXDOOR];          /* 1 vertical, 0 horizontal */
unsigned char door_s[MAXDOOR];          /* 0 closed .. 4 open */

void load_deck(unsigned char d)
{
    static const unsigned char *p;
    static unsigned char *q, b, n;
    static unsigned i;

    deck = d;
    /* all decks unpacked into the droid types' slots, which are made
     * again for the deck after this (enter()) */
    unp_dst = pre + 512;
    unpack(deck_pk);
    p = pre + 512 + deck_off[d];
    q = DMAP;
    i = 0;
    while (i < 1024) {
        b = *p++;
        if (b & 0x80) {
            n = *p++;
            b = (b & 0x3F) << 2;
            i += n;
            while (n--)
                *q++ = b;
        } else {
            *q++ = b << 2;
            ++i;
        }
    }
    /* the doors */
    ndoor = 0;
    for (i = 0; i < 1024; ++i) {
        b = DMAP[i] >> 2;
        if ((b == BLK_VDOOR || b == BLK_HDOOR) && ndoor < MAXDOOR) {
            door_x[ndoor] = i & 63;
            door_y[ndoor] = i >> 6;
            door_v[ndoor] = (b == BLK_VDOOR);
            door_s[ndoor] = 0;
            ++ndoor;
        }
    }
}

/* ======================================================================
 * Lifts
 * ==================================================================== */

/* the lift stop the player stands on, near enough its middle, or 255 */
unsigned char lift_here(void)
{
    static unsigned char i, bx, by;
    if ((unsigned char)((PX & 31) - 8) > 16 || (unsigned char)((PY & 31) - 8) > 16)
        return 255;
    bx = PX >> 5;
    by = PY >> 5;
    for (i = 0; i < NLIFTS; ++i)
        if (lift_deck[i] == deck && lift_bx[i] == bx && lift_by[i] == by)
            return i;
    return 255;
}

/* the console next to the player, if any */
unsigned char console_here(void)
{
    return (blk_flag[blk_at(PX - 20, PY)] | blk_flag[blk_at(PX + 20, PY)]
            | blk_flag[blk_at(PX, PY - 18)] | blk_flag[blk_at(PX, PY + 18)])
           & B_CONSOLE;
}

/* console_near(): move.s */
