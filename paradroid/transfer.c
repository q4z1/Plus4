/*
 * transfer.c - taking a droid over: the circuit game
 *
 * As in the original: the two sides, yellow on the left and purple on the
 * right, face each other across a column of 12 lights. Each side has 12
 * lines, from its rail to the column, in four layers: where pulses are
 * put in, two layers of parts, and the connection to the column. The parts
 * are the original's: wire, dead end, amplifier (once it carries a pulse,
 * it keeps it), colour changer (the light goes to the other side), branch
 * (one line in, two out) and gate (two in, both needed, one out). How the
 * parts are laid out and how a pulse passes them follows FreedroidClassic,
 * whose authors rebuilt the original's game; the numbers of pulses (the
 * droid's class and 3, the other side's class and 4) and how the other side
 * plays are taken from the original's code. A light shows the side whose
 * line is live there, flickers when both are, and when the time is up the
 * side with more lights has won; a draw is a deadlock and is played again.
 *
 * The board is the original's characters, multicolour, drawn into the
 * window of both pictures where the figures' characters usually are.
 * Nothing is scrolled or moved in it, so the deck is simply rebuilt
 * afterwards.
 */
#include <string.h>
#include "game.h"

#define NL      12                      /* lines a side */
#define ROW0    11                      /* screen row of the first line */
#define GLYPH(c) (POOL + (c) - 0xF1)    /* the original's $F1-$FE, */
#define G_D0    (POOL + 14)             /* $D0 and $D1 */
#define G_D1    (POOL + 15)
#define FIG     (POOL + NBOARD)         /* the two droids' characters */
#define SCR0C_ROW(r) ((unsigned char *)0xC400 + (r) * 40)
#define SCR1C_ROW(r) ((unsigned char *)0xD400 + (r) * 40)

/* the parts */
#define WIRE   0
#define DEAD   1
#define AMP    2
#define SWAP   3
#define BR_T   4                        /* branch: top, middle, bottom */
#define BR_M   5
#define BR_B   6
#define GA_T   7                        /* gate */
#define GA_M   8
#define GA_B   9
#define NONE   10

/* how often a part is laid, of 100, when it is picked */
static const unsigned char prob[6]   = { 100, 2, 5, 5, 5, 5 };

/* the board (xfer.s): per side 4 layers of NL lines, a layer after the
 * other; whether each part carries a pulse; how long a pulse put in lasts */
extern unsigned char part[2 * 4 * NL], live[2 * 4 * NL], life[2 * NL];
extern unsigned char xs, xr, tcol[2], blk;
extern const unsigned char out_r[11];
void x_pass(unsigned char s);           /* pulses passed on */
void x_line(void);                      /* line xr of side xs drawn */
void x_step(unsigned char s);           /* lines drawn that changed */
void x_flow(void);                      /* the live wires' dashes move */
#define L1 NL
#define L2 (2 * NL)
#define L3 (3 * NL)
static unsigned char light[NL];         /* 0 yellow, 1 purple */

static unsigned char pulses[2];
static unsigned char cursor[2];         /* 0: above the lines, else line + 1 */
static unsigned char me;                /* the player's side */
static unsigned char leader;            /* 0, 1, or 2 for a draw */

/* a cell of side ds in row wp_row, its column counted from the left
 * side's */
static unsigned char ds;

static void cell(unsigned char col, unsigned char g, unsigned char a)
{
    wp_col = ds ? 39 - col : col;
    wp_code = g;
    wp_attr = a;
    win_put();
}

static void put(unsigned char row, unsigned char col, unsigned char g, unsigned char a)
{
    wp_row = row;
    ds = 0;
    cell(col, g, a);
}

/* ---- laying out the parts (FreedroidClassic's InventPlayground) ---- */

static void lay_out(unsigned char s)
{
    static unsigned char *p, *q;
    static unsigned char l, e, prev;
    static signed char r;
    p = part + s * 4 * NL;
    memset(p, WIRE, 4 * NL);
    for (l = 1; l < 3; ++l) {
        q = p + l * NL;                 /* this layer; q[r - NL] the one before */
        for (r = 0; r < NL; ++r) {
            if (q[r] != WIRE)
                continue;
            e = rnd() % 6;
            if (rnd() % 101 > prob[e]) {
                --r;                    /* this line again */
                continue;
            }
            prev = q[r - NL];
            if (e < 4) {
                if (e == SWAP && l != 2)
                    --r;                /* colour changers next to the column */
                else if (!out_r[prev])
                    q[r] = NONE;
                else
                    q[r] = e;
                continue;
            }
            if (r > NL - 3) {
                --r;
                continue;
            }
            if (e == 4) {               /* a branch: in the middle, out at both ends */
                if (!out_r[q[r - NL + 1]] || prev == BR_T || prev == BR_B
                    || q[r - NL + 2] == BR_T || q[r - NL + 2] == BR_B) {
                    --r;
                    continue;
                }
                if (out_r[prev])
                    q[r - NL] = DEAD;
                if (out_r[q[r - NL + 2]])
                    q[r - NL + 2] = DEAD;
                e = BR_T;
            } else {                    /* a gate: in at both ends, out in the middle */
                if (!out_r[prev] || !out_r[q[r - NL + 2]]) {
                    --r;
                    continue;
                }
                if (out_r[q[r - NL + 1]])
                    q[r - NL + 1] = DEAD;
                e = GA_T;
            }
            q[r] = e;
            q[r + 1] = e + 1;
            q[r + 2] = e + 2;
            r += 2;
        }
    }
}

static void draw_line(unsigned char s, unsigned char r)
{
    xs = s;
    xr = r;
    x_line();
}

/* the pulse in hand at the cursor, or the cell under it again */
static void draw_cursor(unsigned char s, unsigned char on)
{
    static unsigned char r;
    r = cursor[s];
    if (r)
        draw_line(s, r - 1);
    ds = s;
    wp_row = ROW0 - 1 + r;
    if (!r)
        cell(4, s ? GLYPH(0xF2) : GLYPH(0xF1), blk);
    if (on && pulses[s])
        cell(5, s ? GLYPH(0xF3) : GLYPH(0xFD), tcol[s]);
    else if (!r)
        cell(5, 0, blk);
}

/* the pulses a side has left beside its rail, the one in hand not counted */
static void draw_pulses(unsigned char s)
{
    static unsigned char i;
    ds = s;
    for (i = 0; i < NL; ++i) {
        wp_row = ROW0 + i;
        cell(1, i + 1 < pulses[s] ? (s ? GLYPH(0xF3) : GLYPH(0xFD)) : 0, tcol[s]);
    }
}

static void draw_light(unsigned char r)
{
    put(ROW0 + r, 19, GLYPH(0xF8), tcol[light[r]]);
    cell(20, GLYPH(0xF8), tcol[light[r]]);
}

static void draw_leader(void)
{
    static unsigned char a;
    a = leader < 2 ? tcol[leader] : blk;
    put(9, 19, GLYPH(0xF8), a);
    cell(20, GLYPH(0xF8), a);
    put(10, 19, GLYPH(0xFE), a);
    cell(20, GLYPH(0xFE), a);
}

/* a droid's picture, from its pre-shifted slot, at column c of rows 8-9 */
static void draw_droid(unsigned char slot, unsigned char n, unsigned char c)
{
    static unsigned char k, g;
    static const unsigned char *p;
    p = pre + ((unsigned)slot << 9) + 8;
    for (k = 0, g = FIG + n * 8; k < 8; ++k, ++g) {
        memcpy(FONT0 + g * 8, p + 24 * (k >> 1) + ((k & 1) << 3), 8);
        memcpy(FONT1 + g * 8, FONT0 + g * 8, 8);
        put(8 + (k & 1), c + (k >> 1), g, pal_deck[1] | 8);
    }
}

static unsigned char target_slot;

static void draw_droids(void)
{
    static unsigned char k;
    for (k = 8; k < 10; ++k) {
        memset(SCR0C_ROW(k) + 7, 0, 4);
        memset(SCR0C_ROW(k) + 29, 0, 4);
        memset(SCR1C_ROW(k) + 7, 0, 4);
        memset(SCR1C_ROW(k) + 29, 0, 4);
    }
    draw_droid(SLOT_PLAYER, 0, me ? 29 : 7);
    if (target_slot != 255)
        draw_droid(target_slot, 1, me ? 7 : 29);
}

static void board(void)
{
    static unsigned char r, s;
    win_clear(0, blk);
    for (s = 0; s < 2; ++s) {
        ds = s;
        for (r = ROW0 - 2; r <= ROW0 + NL; ++r) {
            wp_row = r;
            cell(3, r == ROW0 - 2 ? GLYPH(0xF5) : r == ROW0 + NL ? GLYPH(0xF7)
                    : GLYPH(0xF6), tcol[s]);
            if (r < ROW0)
                cell(18, s ? G_D1 : G_D0, tcol[s]);
            else if (r < ROW0 + NL)
                cell(18, s ? GLYPH(0xFA) : GLYPH(0xF9), tcol[s]);
        }
        for (r = 0; r < NL; ++r)
            draw_line(s, r);
        draw_pulses(s);
        draw_cursor(s, 1);
    }
    put(8, 19, GLYPH(0xFB), blk);
    cell(20, GLYPH(0xFB), blk);
    put(ROW0 + NL, 19, GLYPH(0xFC), blk);
    cell(20, GLYPH(0xFC), blk);
    for (r = 0; r < NL; ++r)
        draw_light(r);
    draw_leader();
    draw_droids();
}

/* ---- the lights (ProcessDisplayColumn) ---- */

static unsigned char flick;

static void lights(void)
{
    static unsigned char r, y, v, sy, sv, c, n;
    flick ^= 1;
    n = 0;
    for (r = 0; r < NL; ++r) {
        y = live[L3 + r];
        v = live[4 * NL + L3 + r];
        sy = part[L2 + r] == SWAP;
        sv = part[4 * NL + L2 + r] == SWAP;
        c = light[r];
        if (y && !v)
            c = sy;
        else if (v && !y)
            c = !sv;
        else if (y && v)
            c = sy == sv ? flick : sy;
        if (c != light[r]) {
            light[r] = c;
            draw_light(r);
        }
        n += c;
    }
    c = n > NL / 2 ? 1 : n < NL / 2 ? 0 : 2;
    if (c != leader) {
        leader = c;
        draw_leader();
    }
}

/* a pulse put in by side s at its cursor; the player's lasts longer */
static void put_in(unsigned char s)
{
    static unsigned char r, i;
    r = cursor[s] - 1;
    i = s * 4 * NL + r;
    if (!pulses[s] || !cursor[s] || part[i] == DEAD || live[i])
        return;
    --pulses[s];
    part[i] = AMP;
    life[s * NL + r] = s == me ? 80 : 40;
    cursor[s] = 0;
    draw_line(s, r);
    draw_cursor(s, 1);
    draw_pulses(s);
    sound(SND_PULSE);
}

/* one tick of the board: pulses age, pass on, the lights follow */
static void step(void)
{
    static unsigned char s, r;
    static unsigned char *l;
    for (s = 0; s < 2; ++s) {
        for (r = 0, l = life + s * NL; r < NL; ++r, ++l)
            if (*l && !--*l)
                part[s * 4 * NL + r] = WIRE;
        x_pass(s);
        x_step(s);
        if (cursor[s])
            draw_cursor(s, 1);
    }
    lights();
}

/* the other side, as the original plays it: a line picked at random, the
 * cursor moved there a line every other tick, and a pulse put in */
static unsigned char target;

static void enemy(unsigned char s)
{
    if (!pulses[s])
        return;
    if (cursor[s] == target) {
        put_in(s);
        target = 1 + rnd() % NL;
        return;
    }
    if (tick & 1)
        return;
    draw_cursor(s, 0);
    cursor[s] += cursor[s] < target ? 1 : -1;
    draw_cursor(s, 1);
}

static char text[12];

/* the panel: a word and a count, as the original's "Colour? 76" */
static void count(const char *w, unsigned char n)
{
    strcpy(text, w);
    strcat(text, num_text(n));
    panel_status(text);
}

static void wait3(void)
{
    static unsigned char f;
    f = frames;
    while ((unsigned char)(frames - f) < 3)
        ;
    ++tick;
}

/* the game against droid i: 1 if the player wins */
unsigned char transfer_game(unsigned char i)
{
    static unsigned char t, k, prev, s, cd;
    memcpy(FONT0 + POOL * 8, board_font, NBOARD * 8);
    memcpy(FONT1 + POOL * 8, board_font, NBOARD * 8);
    eng_plain();
    tcol[0] = pal_deck[7] | 8;
    tcol[1] = pal_deck[4] | 8;
    blk = pal_deck[0] | 8;
    cd = col_deck;
    col_deck = pal_deck[2];
    target_slot = slot_of[d_type[i]];
    for (;;) {
        lay_out(0);
        lay_out(1);
        memset(live, 0, sizeof live);
        memset(life, 0, sizeof life);
        for (t = 0; t < NL; ++t)
            light[t] = t & 1;
        leader = 2;
        me = 0;
        pulses[0] = pulses[1] = 0;
        cursor[0] = cursor[1] = 0;
        board();

        /* the player chooses a side, left yellow or right purple */
        while (keys_irq & K_FIRE)
            wait3();
        for (t = 99; t; --t) {
            if ((t & 1) == 0)
                count("Colour? ", t);
            wait3();
            k = keys_irq;
            if (k & K_FIRE)
                break;
            s = (k & K_RIGHT) ? 1 : (k & K_LEFT) ? 0 : me;
            if (s != me) {
                me = s;
                draw_droids();
            }
        }
        pulses[me] = dr_class[d_type[0]] + 3;
        pulses[me ^ 1] = dr_class[d_type[i]] + 4;
        target = 1 + rnd() % NL;
        for (s = 0; s < 2; ++s) {
            draw_pulses(s);
            draw_cursor(s, 1);
        }

        /* the game, ten seconds and the pulses' end */
        prev = keys_irq;
        for (t = 0; t < 167 + 40; ++t) {
            wait3();
            if (t < 167) {
                if (t % 3 == 0)
                    count("Finish -", (166 - t) * 3 / 5);
                k = keys_irq;
                if ((k & K_UP) && !(prev & K_UP)) {
                    draw_cursor(me, 0);
                    cursor[me] = cursor[me] > 1 ? cursor[me] - 1 : NL;
                    draw_cursor(me, 1);
                }
                if ((k & K_DOWN) && !(prev & K_DOWN)) {
                    draw_cursor(me, 0);
                    cursor[me] = cursor[me] < NL ? cursor[me] + 1 : 1;
                    draw_cursor(me, 1);
                }
                if ((k & K_FIRE) && !(prev & K_FIRE))
                    put_in(me);
                prev = k;
                enemy(me ^ 1);
            }
            if ((t & 1) == 0)
                x_flow();
            step();
        }
        if (leader != 2)
            break;
        panel_status("Deadlock");
        for (t = 0; t < 30; ++t)
            wait3();
    }
    col_deck = cd;
    return leader == me;
}
