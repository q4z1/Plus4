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

static unsigned rs = 0x1234;

unsigned char rnd(void)
{
    rs ^= rs << 7;
    rs ^= rs >> 9;
    rs ^= rs << 8;
    return (unsigned char)rs;
}

/* TED colour for each of the C64 colours the deck characters use. A deck
 * character in a cell that may turn multicolour must have a hue below 8. */
const unsigned char pal_deck[16] = {
    0x00, 0x71, 0x32, 0x53, 0x34, 0x45, 0x36, 0x67,
    0x37, 0x17, 0x52, 0x11, 0x31, 0x65, 0x66, 0x61
};

/* the same, with the lights out: a deck without droids */
static const unsigned char pal_dark[16] = {
    0x00, 0x31, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
    0x17, 0x07, 0x12, 0x01, 0x11, 0x15, 0x26, 0x21
};

/* the ALERT console's lights, by the alert */
static const unsigned char pal_alert[4] = { 0x45, 0x67, 0x52, 0x32 };

static const unsigned char *pal = pal_deck;

/* the colours of every block character, from the palette */
void colour_blocks(void)
{
    static unsigned i;
    static unsigned char p5;
    p5 = pal == pal_deck ? pal_alert[alert] : pal[5];
    for (i = 0; i < 1024; ++i) {
        if (tile_col[BLKC[i]] == 5)
            BLKA[i] = p5;
        else
            BLKA[i] = pal[tile_col[BLKC[i]]];
    }
}

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

/* the deck's colours: dark when its droids are gone, and the alert */
void deck_colours(void)
{
    if (deck_cleared(deck)) {
        pal = pal_dark;
        deck_bg = 0x21;
    } else {
        pal = pal_deck;
        deck_bg = 0x5D;
    }
    col_deck = deck_bg;
    colour_blocks();
    eng_dirty();
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

unsigned char blk_at(unsigned x, unsigned y)
{
    /* the block under world pixel (x, y), as an index */
    return DMAP[((y >> 5) << 6) | ((x >> 5) & 63)] >> 2;
}

/* ======================================================================
 * Loading a deck
 * ==================================================================== */

#define MAXDOOR 32
static unsigned char door_x[MAXDOOR], door_y[MAXDOOR];
static unsigned char door_v[MAXDOOR];   /* 1 vertical, 0 horizontal */
static unsigned char door_s[MAXDOOR];   /* 0 closed .. 4 open */

void load_deck(unsigned char d)
{
    static const unsigned char *p;
    static unsigned char *q, b, n;
    static unsigned i;

    deck = d;
    p = deck_off[d];
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
 * Doors: open while a droid is near
 * ==================================================================== */

void doors(void)
{
    static unsigned char i, j, want, s, x, y, pbx, pby;
    for (i = 0; i < nd; ++i) {
        d_bx[i] = d_x[i] >> 5;
        d_by[i] = d_y[i] >> 5;
    }
    pbx = d_bx[0];
    pby = d_by[0];
    for (i = 0; i < ndoor; ++i) {
        x = door_x[i];
        y = door_y[i];
        /* only doors on the screen or about to be */
        if ((unsigned char)(x - pbx + 7) > 14 || (unsigned char)(y - pby + 4) > 8)
            continue;
        want = 0;
        for (j = 0; j < nd; ++j)
            if (d_boom[j] == 0
                && (unsigned char)(d_bx[j] - x + 1) <= 2
                && (unsigned char)(d_by[j] - y + 1) <= 2) {
                want = 1;
                break;
            }
        s = door_s[i];
        if (want && s < 4)
            ++s;
        else if (!want && s > 0)
            --s;
        else
            continue;
        door_s[i] = s;
        bs_x = x;
        bs_y = y;
        if (s == 0)
            bs_v = (door_v[i] ? BLK_VDOOR : BLK_HDOOR) << 2;
        else
            bs_v = ((door_v[i] ? BLK_VOPEN : BLK_HOPEN) + s - 1) << 2;
        blk_set();
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
