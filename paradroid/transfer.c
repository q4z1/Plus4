/*
 * transfer.c - taking a droid over: the circuit game
 *
 * As in the original, two sides face each other across a column of 12
 * lights. Each side has 12 wires leading to the lights; some end before
 * they get there, some fork and feed a neighbour's dead end as well. The
 * player has as many pulses as his droid's class and 3, the other side its
 * class and 4 (the original's numbers). A pulse runs along its wire in
 * three steps and, while it lights the wire's end, turns the lights it
 * reaches to the side's colour - unless the other side holds the same
 * light at the same time. The other side plays as the original's does: it
 * picks a wire at random, goes there and fires. When the time is up, the
 * side with more lights has won; a draw is a deadlock and is played again.
 *
 * The board is drawn into the window of both pictures with characters of
 * its own, put where the figures' characters usually are. Nothing is
 * scrolled or moved in it, so the deck is simply rebuilt afterwards.
 */
#include <string.h>
#include "game.h"


#define NROW   12
#define ROW0   11                       /* screen row of the first wire */
#define COL_L  4                        /* left side: wire start, */
#define COL_E  10                       /*   where a wire may end, */
#define COL_F  14                       /*   where it may fork, */
#define COL_LE 18                       /*   last wire column */
#define COL_C  19                       /* the lights, two columns */

/* what an input does */
#define W_WIRE  0                       /* to its light */
#define W_DEAD  1                       /* nowhere */
#define W_FORKD 2                       /* to its light and the one below */
#define W_FORKU 3                       /* to its light and the one above */
#define W_FED   4                       /* a dead end, fed by a fork */

static unsigned char kind[2][NROW];
static unsigned char glow[2][NROW];     /* ticks a pulse still lights it */
#define GLOW   24                       /* a pulse's ticks */
#define STEP   3                        /* ticks it takes for a third of a wire */

/* the last column a pulse has reached, by how long it has been running */
static unsigned char reached(unsigned char g)
{
    if (!g)
        return 0;
    if (g > GLOW - STEP)
        return COL_E - 1;
    if (g > GLOW - 2 * STEP)
        return COL_F;
    return COL_LE;
}

static unsigned char pulses[2];
static unsigned char owner[NROW];       /* 0 or 1: whose light */
static unsigned char cursor[2];

/* colours: [side][0 dim, 1 lit] */
static const unsigned char wire_col[2][2] = { { 0x27, 0x77 }, { 0x24, 0x64 } };
static const unsigned char light_col[2] = { 0x67, 0x54 };

static unsigned char xc(unsigned char g)
{
    return POOL + g;                    /* the board's characters */
}

static void put(unsigned char row, unsigned char col, unsigned char g, unsigned char a)
{
    wp_row = row;
    wp_col = col;
    wp_code = xc(g);
    wp_attr = a;
    win_put();
}

/* the column of side s mirrored: the right side is the left one reversed */
static unsigned char mc(unsigned char s, unsigned char col)
{
    return s ? 39 - col : col;
}

static void lay_out(unsigned char s)
{
    static unsigned char r, x;
    for (r = 0; r < NROW; ++r)
        kind[s][r] = 255;
    for (r = 0; r < NROW; ++r) {
        if (kind[s][r] != 255)
            continue;
        x = rnd() & 15;
        if (x < 3 && r + 1 < NROW && kind[s][r + 1] == 255) {
            kind[s][r] = W_FORKD;
            kind[s][r + 1] = W_FED;
        } else if (x < 6 && r > 0 && kind[s][r - 1] == W_WIRE) {
            kind[s][r - 1] = W_FED;     /* the wire above becomes fed */
            kind[s][r] = W_FORKU;
        } else if (x < 9)
            kind[s][r] = W_DEAD;
        else
            kind[s][r] = W_WIRE;
    }
}

/* one wire, lit as far as its pulse has got */
static void draw_wire(unsigned char s, unsigned char r)
{
    static unsigned char row, k, a, x, g, lit;
    row = ROW0 + r;
    k = kind[s][r];
    lit = reached(glow[s][r]);
    a = wire_col[s][lit != 0];
    put(row, mc(s, COL_L - 1), X_SOCKET, a);
    for (x = COL_L; x <= COL_LE; ++x) {
        a = wire_col[s][x <= lit];
        g = X_WIRE;
        if (k == W_DEAD || k == W_FED) {
            if (x == COL_E)
                g = s ? X_DEAD_R : X_DEAD_L;
            else if (x > COL_E)
                continue;               /* the fed part is drawn by its fork */
        } else if (x == COL_F) {
            if (k == W_FORKD)
                g = X_FORK_D;
            else if (k == W_FORKU)
                g = X_FORK_U;
        }
        put(row, mc(s, x), g, a);
    }
    /* a fork goes on into its neighbour's dead end, in the fork's colour */
    if (k == W_FORKD || k == W_FORKU) {
        a = wire_col[s][lit >= COL_F];
        row = k == W_FORKD ? row + 1 : row - 1;
        put(row, mc(s, COL_F), k == W_FORKD ? (s ? X_BEND_DR : X_BEND_D)
                                            : (s ? X_BEND_UR : X_BEND_U), a);
        for (x = COL_F + 1; x <= COL_LE; ++x)
            put(row, mc(s, x), X_WIRE, a);
    }
}

static void draw_light(unsigned char r)
{
    put(ROW0 + r, COL_C, X_LIGHT, light_col[owner[r]]);
    put(ROW0 + r, COL_C + 1, X_LIGHT, light_col[owner[r]]);
}

static void draw_cursor(unsigned char s, unsigned char on)
{
    put(ROW0 + cursor[s], mc(s, COL_L - 2),
        on ? (s ? X_PULSE_R : X_PULSE_L) : X_BLANK, wire_col[s][1]);
}

/* the pulses a side has left, as bars under the board */
static void draw_pulses(unsigned char s)
{
    static unsigned char i;
    for (i = 0; i < 13; ++i)
        put(ROW0 + NROW + 1, mc(s, COL_L + i),
            i < pulses[s] ? X_BAR : X_BLANK, wire_col[s][1]);
}

/* the time left, as a bar over the board */
static void draw_time(unsigned char t)
{
    static unsigned char i;
    for (i = 0; i < 16; ++i)
        put(ROW0 - 2, 12 + i, i < t ? X_BAR : X_BLANK, 0x71);
}

static void board(void)
{
    static unsigned char r, s;
    win_clear(xc(X_BLANK), 0x71);
    for (s = 0; s < 2; ++s) {
        for (r = 0; r < NROW; ++r)
            draw_wire(s, r);
        draw_pulses(s);
    }
    for (r = 0; r < NROW; ++r)
        draw_light(r);
}

/* the lights input r of side s reaches */
static void reach(unsigned char s, unsigned char r, unsigned char *a, unsigned char *b)
{
    *a = *b = 255;
    switch (kind[s][r]) {
    case W_WIRE: *a = r; break;
    case W_FORKD: *a = r; *b = r + 1; break;
    case W_FORKU: *a = r; *b = r - 1; break;
    }
}

static void fire(unsigned char s, unsigned char r)
{
    static unsigned char k;
    if (!pulses[s] || glow[s][r])
        return;
    --pulses[s];
    glow[s][r] = GLOW;
    k = kind[s][r];
    draw_wire(s, r);
    draw_pulses(s);
    sound(SND_PULSE);
}

/* the lights each side's pulses reach now, as bits */
static unsigned held_by(unsigned char s)
{
    static unsigned char r, a, b;
    static unsigned m;
    m = 0;
    for (r = 0; r < NROW; ++r)
        if (glow[s][r] && glow[s][r] <= GLOW - 2 * STEP) {
            reach(s, r, &a, &b);
            if (a != 255)
                m |= 1u << a;
            if (b != 255)
                m |= 1u << b;
        }
    return m;
}

static void lights(void)
{
    static unsigned char l, o;
    static unsigned m0, m1, bit;
    m0 = held_by(0);
    m1 = held_by(1);
    bit = 1;
    for (l = 0; l < NROW; ++l, bit <<= 1) {
        if (!((m0 ^ m1) & bit))
            continue;                   /* nobody, or both */
        o = (m0 & bit) ? 0 : 1;
        if (owner[l] != o) {
            owner[l] = o;
            draw_light(l);
        }
    }
}

/* the other side, as the original plays it: a wire picked at random, the
 * cursor moved there a wire every other tick, and fired */
static unsigned char target;

static void enemy(unsigned char s)
{
    if (!pulses[s])
        return;
    if (cursor[s] == target) {
        fire(s, target);
        target = rnd() % NROW;
        return;
    }
    if (tick & 1)
        return;
    draw_cursor(s, 0);
    cursor[s] += cursor[s] < target ? 1 : -1;
    draw_cursor(s, 1);
}

static void wait3(void)
{
    static unsigned char f;
    f = frames;
    while ((unsigned char)(frames - f) < 3)
        ;
}

/* the game against droid i: 1 if the player wins */
unsigned char transfer_game(unsigned char i)
{
    static unsigned char t, k, prev, s, me, r, cp, ce, tt;
    memcpy(FONT0 + POOL * 8, xfer_font, NXFER * 8);
    memcpy(FONT1 + POOL * 8, xfer_font, NXFER * 8);
    eng_plain();
    for (;;) {
        lay_out(0);
        lay_out(1);
        memset(glow, 0, sizeof glow);
        for (r = 0; r < NROW; ++r)
            owner[r] = (r + (rnd() & 1)) & 1;
        pulses[0] = pulses[1] = 0;
        cursor[0] = cursor[1] = NROW / 2;
        board();

        /* the player chooses a side */
        panel_status("Colour");
        me = 0;
        draw_cursor(0, 1);
        while (keys_irq & K_FIRE)
            wait3();
        for (t = 0; t < 50; ++t) {
            wait3();
            k = keys_irq;
            if (k & K_FIRE)
                break;
            s = (k & K_RIGHT) ? 1 : (k & K_LEFT) ? 0 : me;
            if (s != me) {
                draw_cursor(me, 0);
                me = s;
                draw_cursor(me, 1);
            }
            draw_time(16 - t / 3);
        }
        draw_cursor(me ^ 1, 1);
        pulses[me] = dr_class[d_type[0]] + 3;
        pulses[me ^ 1] = dr_class[d_type[i]] + 4;
        target = rnd() % NROW;
        draw_pulses(0);
        draw_pulses(1);

        /* the game */
        panel_status("Transfer");
        prev = keys_irq;
        for (t = 0; t < 167; ++t) {
            wait3();
            k = keys_irq;
            if ((k & K_UP) && !(prev & K_UP) && cursor[me] > 0) {
                draw_cursor(me, 0);
                --cursor[me];
                draw_cursor(me, 1);
            }
            if ((k & K_DOWN) && !(prev & K_DOWN) && cursor[me] < NROW - 1) {
                draw_cursor(me, 0);
                ++cursor[me];
                draw_cursor(me, 1);
            }
            if ((k & K_FIRE) && !(prev & K_FIRE))
                fire(me, cursor[me]);
            prev = k;
            ++tick;
            enemy(me ^ 1);
            for (s = 0; s < 2; ++s)
                for (r = 0; r < NROW; ++r)
                    if (glow[s][r]) {
                        --glow[s][r];
                        /* redrawn when it gets on, and when it is over */
                        if (glow[s][r] == 0 || glow[s][r] == GLOW - STEP
                            || glow[s][r] == GLOW - 2 * STEP)
                            draw_wire(s, r);
                    }
            lights();
            tt = 16 - t / 11;
            if ((t % 11) == 0)
                draw_time(tt);
        }
        cp = ce = 0;
        for (r = 0; r < NROW; ++r)
            if (owner[r] == me)
                ++cp;
            else
                ++ce;
        if (cp != ce)
            break;
        panel_status("Deadlock");
        for (t = 0; t < 30; ++t)
            wait3();
    }
    return cp > ce;
}
