/*
 * lift.c - riding a lift: the side view of the ship
 *
 * Standing on a lift with fire held shows the ship from the side, as the
 * original does: its map in the upper half of the original's deck
 * characters, multicolour, with the lift's shaft white and the deck it is
 * at lit. Up and down go along the shaft, letting go of fire gets out
 * there. The characters go where the figures' usually are, the map
 * straight into the window of both pictures.
 */
#include <string.h>
#include "game.h"

void wait_tick(void);
void enter(unsigned char d, unsigned char bx, unsigned char by);

#define SCR0A ((unsigned char *)0xC000)
#define SCR0C ((unsigned char *)0xC400)
#define SCR1A ((unsigned char *)0xD000)
#define SCR1C ((unsigned char *)0xD400)
#define SIDE (POOL + SIDE_BASE - 0x80)  /* screen code of original code c: c + SIDE */

static unsigned char side_attr(unsigned char col)
{
    return col >= 8 ? (pal_deck[col & 7] | 8) : pal_deck[col];
}

static void side_view(void)
{
    static unsigned char c, n;
    static unsigned off;
    static const unsigned char *p;
    memcpy(FONT0 + (POOL + SIDE_BASE) * 8, side_font, NSIDE * 8);
    memcpy(FONT1 + (POOL + SIDE_BASE) * 8, side_font, NSIDE * 8);
    eng_plain();
    win_clear(0, 0x71);
    p = side_rle;
    off = 9 * 40;                       /* the original's row 10 */
    while ((n = p[1]) != 0) {
        c = p[0];
        p += 2;
        for (; n; --n, ++off)
            if (c) {
                SCR0C[off] = SCR1C[off] = c + SIDE;
                SCR0A[off] = SCR1A[off] = side_attr(side_col[c - 0x80]);
            }
    }
}

/* a lift's shaft, white for the lift ridden, else as the map has it */
static void shaft(unsigned char s, unsigned char on)
{
    static unsigned char r, a;
    static unsigned off;
    a = on ? (pal_deck[1] | 8) : side_attr(side_col[0x26]);
    off = shaft_top[s] * 40 + shaft_col[s];
    for (r = 0; r < shaft_len[s]; ++r, off += 40)
        SCR0A[off] = SCR1A[off] = a;
}

/* deck d lit, or no longer: as the original, its box's codes $80.. turn
 * into $90.. and back, the ends of the deck's bars and the shafts kept */
static void light(unsigned char d)
{
    static unsigned char r, x, c, v, h, w, end;
    static unsigned off;
    static const unsigned char *b;
    b = side_box + d * 4;
    off = b[0] * 40 + b[1];
    h = b[2];
    w = b[3];
    for (r = 0; r < h; ++r, off += 40)
        for (x = 0, end = 0; x < w && !end; ++x) {
            c = SCR0C[off + x];
            if (c < POOL + SIDE_BASE)
                continue;
            c -= SIDE;
            if (h == 1) {
                /* one row: the bars, and the ends that are lit too */
                if (c == 0x9C || c == 0x9D || (c >= 0x90 && c < 0x93))
                    c -= 0x10;
                else if ((c >= 0x8C && c < 0x8E) || c < 0x83)
                    c += 0x10;
                else
                    continue;
            } else {
                /* more rows: up to the right end of each */
                if (c >= 0x9E)
                    continue;
                v = c < 0x90 ? c + 0x10 : c;
                c = c < 0x90 ? v : c - 0x10;
                end = v == 0x92 || v == 0x95 || v == 0x98 || v == 0x9B;
            }
            SCR0C[off + x] = SCR1C[off + x] = c + SIDE;
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
    shaft(lift_shaft[li], 1);
    light(lift_deck[li]);
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
            light(lift_deck[li]);
            li = n;
            light(lift_deck[li]);
            deck_name(li);
            sound(SND_LIFT);
        }
    }
    if (lift_deck[li] != deck)
        enter(lift_deck[li], lift_bx[li], lift_by[li]);
    panel_status("Mobile");
}
