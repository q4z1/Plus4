/*
 * droids.c - the player, the droids of a deck, shots and explosions
 */
#include <string.h>
#include "game.h"

unsigned char nd;                       /* droids on this deck, 0 = player */
unsigned char d_type[MAXD];
unsigned d_x[MAXD], d_y[MAXD];          /* world pixels, the middle */
signed char d_vx[MAXD], d_vy[MAXD];
unsigned char d_energy[MAXD];
unsigned char d_boom[MAXD];
unsigned char d_bx[MAXD], d_by[MAXD];   /* block of each droid */
static unsigned char d_slot[MAXD];      /* where in ship[deck] */
unsigned char d_wait[MAXD];
unsigned char d_choose[MAXD];          /* droids_step: decide a direction */
void droids_step(void);
static unsigned char d_cool[MAXD];      /* ticks until it may fire again */

unsigned s_x[MAXS], s_y[MAXS];
static signed char s_vx[MAXS], s_vy[MAXS];
unsigned char s_life[MAXS], s_img[MAXS];
static unsigned char s_own[MAXS], s_dmg[MAXS];

unsigned long score;
unsigned char score_changed;
unsigned char transfer_mode;
unsigned char touched;
unsigned char player_dead;

/* The original's rules. Every droid has up to 64 energy and gets one
 * back every four ticks (the command cyborg two). The player only at an
 * energizer, and only up to a limit that sinks while he stays in a host:
 * by one every 128, 64, 32 or 16 ticks, by the host's class. When it
 * reaches nothing, so does he. */
unsigned char burn;                     /* the player's energy limit */
unsigned char alert_acc;                /* kills by type, slowly forgotten */

static const unsigned char burn_mask[10] = { 127, 63, 63, 63, 63, 31, 31, 31, 31, 15 };
static const unsigned char kill_pts[10] = { 0, 10, 20, 30, 40, 50, 60, 70, 80, 200 };
static const unsigned char take_pts[10] = { 0, 25, 50, 75, 100, 125, 150, 175, 200, 250 };
static const unsigned char alert_pts[4] = { 0, 5, 10, 25 };
/* types the disruptor does not touch: 420, 711, 742, 821, 999 */
static const unsigned char no_disrupt[5] = { 8, 17, 18, 20, 23 };

unsigned char emax(unsigned char type)
{
    (void)type;
    return 64;
}

static void points(unsigned char n)
{
    score += n;
    score_changed = 1;
}

/* the effects: frequency, change a picture, pictures, noise */
static const unsigned freq_of[9]   = { 900, 700, 600, 200, 800, 500, 650, 300, 600 };
static const signed char d_of[9]   = { -40, -25, -3, -6, 12, 0, 6, 10, -10 };
static const unsigned char len_of[9]   = { 6, 8, 25, 6, 4, 3, 3, 30, 30 };
static const unsigned char noise_of[9] = { 0, 0, 1, 1, 0, 0, 0, 0, 0 };

void sound(unsigned char n)
{
    sfx_lo = (unsigned char)freq_of[n];
    sfx_hi = freq_of[n] >> 8;
    sfx_d = d_of[n];
    sfx_len = len_of[n];
    sfx_noise = noise_of[n];
    eng_sfx();
}

/* damage of a droid's shot, by weapon; the player's depends on the
 * target as well (hit) */
static const unsigned char wdamage[4] = { 0, 8, 16, 16 };

/* ======================================================================
 * Droids on a deck
 * ==================================================================== */

void spawn_droids(void)
{
    static unsigned char k, w, w0, wn;
    nd = 1;
    w0 = wp_first[deck];
    wn = wp_first[deck + 1] - w0;
    for (k = 0; k < 12; ++k) {
        if (!ship[deck][k])
            continue;
        w = k + 1;
        if (w >= wn)
            w = k % wn;
        d_type[nd] = ship[deck][k] - 1;
        d_x[nd] = wp_x[w0 + w] << 3;
        d_y[nd] = wp_y[w0 + w] << 3;
        d_vx[nd] = d_vy[nd] = 0;
        d_wait[nd] = 0;
        d_slot[nd] = k;
        d_boom[nd] = 0;
        d_energy[nd] = 64;
        d_cool[nd] = 16 + (rnd() & 31);
        ++nd;
    }
    memset(s_life, 0, sizeof s_life);
    d_boom[0] = 0;
    transfer_mode = 0;
    touched = 0;
}

void remove_droid(unsigned char i)
{
    d_boom[i] = BOOM_GONE;
    ship[deck][d_slot[i]] = 0;
}

/* bit k of a waypoint's directions, from bit 0: up-left, up, up-right,
 * right, down-right, down, down-left, left */
static const signed char wbit_dx[8] = { -1, 0, 1, 1, 1, 0, -1, -1 };
static const signed char wbit_dy[8] = { -1, -1, -1, 0, 1, 1, 1, 0 };

/* a droid in the middle of a block on a waypoint picks where to go next */
static void droid_choose(unsigned char i)
{
    static unsigned char w, dirs, k, n, pick, sp, bx, by, last;
    static signed char cx[3], cy[3];
    /* the deck's waypoint in this block */
    bx = d_x[i] >> 5;
    by = d_y[i] >> 5;
    last = wp_first[deck + 1];
    for (w = wp_first[deck]; w < last; ++w)
        if ((wp_x[w] >> 2) == bx && (wp_y[w] >> 2) == by)
            break;
    if (w == last)
        return;                         /* not a waypoint: keep going */
    dirs = wp_dir[w];
    n = 0;
    for (k = 0; k < 8 && n < 3; ++k)
        if (dirs & (1 << k)) {
            cx[n] = wbit_dx[k];
            cy[n] = wbit_dy[k];
            ++n;
        }
    pick = rnd() % 3;                   /* as the original: an empty pick waits */
    sp = dr_drive[d_type[i]];
    if (pick >= n) {
        d_vx[i] = d_vy[i] = 0;
        d_wait[i] = 8;
        return;
    }
    d_vx[i] = cx[pick] * sp;
    d_vy[i] = cy[pick] * sp;
}

void droid_move(unsigned char i);

void move_droids(void)
{
    static unsigned char i;
    droids_step();
    for (i = 1; i < nd; ++i)
        if (d_choose[i]) {
            droid_choose(i);
            if (!d_wait[i])
                droid_move(i);          /* engine.s: unless a wall is ahead */
        }
}

/* ======================================================================
 * The player
 * ==================================================================== */

/* move_player(): move.s, as the original drives */

/* ======================================================================
 * Shots
 * ==================================================================== */

/* a shot from droid i in direction dx, dy (-1, 0, 1 each) */
static void shoot(unsigned char i, signed char dx, signed char dy, unsigned char w)
{
    static unsigned char k;
    for (k = 0; k < MAXS; ++k)
        if (!s_life[k])
            break;
    if (k == MAXS)
        return;
    s_x[k] = d_x[i] + dx * 20;
    s_y[k] = d_y[i] + dy * 14;
    s_vx[k] = dx * 4;
    s_vy[k] = dy * 4;
    s_life[k] = 14;
    s_own[k] = i;
    s_dmg[k] = wdamage[w];
    /* the picture: | / - \ */
    if (!dx)
        s_img[k] = 0;
    else if (!dy)
        s_img[k] = 2;
    else if (dx != dy)
        s_img[k] = 1;
    else
        s_img[k] = 3;
    sound(i ? SND_ESHOT : SND_SHOT);
}

static void hit(unsigned char i, unsigned char dmg, unsigned char by_player);

/* the disruptor: a flash that hurts every droid in sight but a few types;
 * fired by a droid, the player too */
unsigned char flash;                    /* ticks the deck stays lit */

static unsigned char immune(unsigned char t)
{
    static unsigned char k;
    for (k = 0; k < 5; ++k)
        if (no_disrupt[k] == t)
            return 1;
    return 0;
}

static void disrupt(unsigned char from)
{
    static unsigned char i, t;
    static signed char d;
    flash = 3;
    sound(SND_BOOM);
    for (i = 1; i < nd; ++i) {
        if (i == from || d_boom[i] || immune(d_type[i]))
            continue;
        if ((unsigned)(d_x[i] - PX + 160) > 320 || (unsigned)(d_y[i] - PY + 80) > 160)
            continue;                   /* out of sight */
        hit(i, (40 - d_type[i]) * 2, from == 0);
    }
    t = d_type[0];
    if (from && !immune(t)) {
        d = 32 + level - t;
        if (d > 0)
            hit(0, d, 0);
    }
}

void player_fire(unsigned char k)
{
    static unsigned char w;
    static signed char dx, dy;
    if (d_cool[0])
        --d_cool[0];
    if (!(k & K_FIRE) || !(k & K_DIRS) || d_cool[0])
        return;
    dx = (k & K_LEFT) ? -1 : (k & K_RIGHT) ? 1 : 0;
    dy = (k & K_UP) ? -1 : (k & K_DOWN) ? 1 : 0;
    w = dr_weapon[d_type[0]];
    if (w == 3)
        disrupt(0);
    else
        shoot(0, dx, dy, w);
    d_cool[0] = 32 - 2 * dr_class[d_type[0]];
}

unsigned char dbg_god;                  /* tests: the player takes no damage */

static void hit(unsigned char i, unsigned char dmg, unsigned char by_player)
{
    if (i == 0 && dbg_god)
        return;
    if (!dmg || d_boom[i])
        return;                         /* (exploding already: it stays so) */
    if (d_energy[i] > dmg) {
        d_energy[i] -= dmg;
        if (i == 0)
            sound(SND_HIT);
        return;
    }
    d_energy[i] = 0;
    if (i == 0) {
        player_dead = 1;
        d_boom[0] = 1;
        d_vx[0] = d_vy[0] = 0;          /* the explosion stays where it is */
        sound(SND_BOOM);
        return;
    }
    d_boom[i] = 1;
    ship[deck][d_slot[i]] = 0;
    if (by_player) {
        points(kill_pts[dr_class[d_type[i]]]);
        alert_acc = alert_acc + d_type[i] < alert_acc ? 255 : alert_acc + d_type[i];
    }
    sound(SND_BOOM);
}

/* what a shot of the player's does to droid j: 16 per class of his
 * weapon and 80, less 4 per type of the droid - nothing below that */
static unsigned char pdamage(unsigned char j)
{
    static int d;
    d = 4 * dr_weapon[d_type[0]] + 16 - d_type[j];
    if (d < 0)
        return 0;
    d = d * 4 + 16;
    return d > 255 ? 255 : (unsigned char)d;
}

void move_shots(void)
{
    static unsigned char k, step, j, bx, by;
    static unsigned x, y;
    for (k = 0; k < MAXS; ++k) {
        if (!s_life[k])
            continue;
        --s_life[k];
        x = s_x[k];
        y = s_y[k];
        for (step = 0; step < 3 && s_life[k]; ++step) {
            x += s_vx[k];
            y += s_vy[k];
            if (solid_at(x, y)) {
                s_life[k] = 0;
                break;
            }
            bx = x >> 5;
            by = y >> 5;
            for (j = 0; j < nd; ++j) {
                if (j == s_own[k] || d_boom[j])
                    continue;
                if ((unsigned char)(d_bx[j] - bx + 1) > 2
                    || (unsigned char)(d_by[j] - by + 1) > 2)
                    continue;
                if ((unsigned)(x - d_x[j] + 12) < 24 && (unsigned)(y - d_y[j] + 8) < 16) {
                    if (s_own[k] == 0)
                        hit(j, pdamage(j), 1);
                    else
                        hit(j, s_dmg[k], 0);
                    s_life[k] = 0;
                    break;
                }
            }
        }
        s_x[k] = x;
        s_y[k] = y;
    }
}

/* armed droids fire at the player when they have him in line */
void droids_fire(void)
{
    static unsigned char i, w, adx, ady;
    static int dx, dy;
    for (i = 1; i < nd; ++i) {
        if (d_boom[i])
            continue;
        w = dr_weapon[d_type[i]];
        if (!w)
            continue;
        if (d_cool[i]) {
            --d_cool[i];
            continue;
        }
        dx = (int)PX - (int)d_x[i];
        dy = (int)PY - (int)d_y[i];
        if (dx < -150 || dx > 150 || dy < -90 || dy > 90)
            continue;
        if ((rnd() & 31) >= level + 2)
            continue;                   /* as the original: by the ship */
        if (w == 3) {
            disrupt(i);
            d_cool[i] = 32 - 2 * dr_class[d_type[i]];
            continue;
        }
        adx = (unsigned char)(dx < 0 ? -dx : dx);
        ady = (unsigned char)(dy < 0 ? -dy : dy);
        if (adx < 10)
            shoot(i, 0, dy < 0 ? -1 : 1, w);
        else if (ady < 10)
            shoot(i, dx < 0 ? -1 : 1, 0, w);
        else if ((unsigned char)(adx - ady + 12) < 24)
            shoot(i, dx < 0 ? -1 : 1, dy < 0 ? -1 : 1, w);
        else
            continue;
        d_cool[i] = 32 - 2 * dr_class[d_type[i]];
    }
}

/* ======================================================================
 * Touching droids, energy
 * ==================================================================== */

void collide(void)
{
    static unsigned char i;
    static int dx, dy;
    static signed char d;
    touched = 0;
    if (d_boom[0])
        return;                         /* nothing pushes an explosion */
    for (i = 1; i < nd; ++i) {
        if (d_boom[i])
            continue;
        dx = (int)PX - (int)d_x[i];
        dy = (int)PY - (int)d_y[i];
        if (dx <= -24 || dx >= 24 || dy <= -16 || dy >= 16)
            continue;
        if (transfer_mode) {
            touched = i;
            return;
        }
        /* a bump: as in the original, the stronger hurts the weaker, and
         * the player is pushed back */
        d = (signed char)d_type[0] + 2 - (signed char)d_type[i];
        if (d >= 0)
            hit(i, d * 2, 1);
        else
            hit(0, (unsigned char)(-d - 1) >> 1, 0);
        d_vx[0] = dx < 0 ? -3 : 3;
        d_vy[0] = dy < 0 ? -2 : 2;
    }
}

void energy_tick(void)
{
    static unsigned char i;
    /* the limit sinks while in a host - and in the device itself, slowly */
    if (!(tick & burn_mask[dr_class[d_type[0]]]) && burn) {
        --burn;
        if (!burn && !dbg_god) {
            d_energy[0] = 1;
            hit(0, 1, 0);
        }
    }
    if (d_energy[0] > burn && !dbg_god)
        d_energy[0] = burn;
    if (!(tick & 3)) {
        /* an energizer: a point of energy for five of score */
        if ((blk_flag[blk_at(PX, PY)] & B_ENERGY) && d_energy[0] < burn) {
            ++d_energy[0];
            if (score >= 5)
                score -= 5;
            score_changed = 1;
            if (!(tick & 7))
                sound(SND_ENERGY);
        }
        for (i = 1; i < nd; ++i)
            if (!d_boom[i] && d_energy[i] < 64) {
                d_energy[i] += d_type[i] == 23 ? 2 : 1;
                if (d_energy[i] > 64)
                    d_energy[i] = 64;
            }
    }
    /* the alert: kills are forgotten, and while it is up it pays */
    if (!(tick & 15)) {
        if (alert_acc)
            --alert_acc;
        if (alert_pts[alert_acc >> 6])
            points(alert_pts[alert_acc >> 6]);
    }
    if (flash)
        --flash;
}

/* the player takes droid i over: it is his host now */
void take_over(unsigned char i)
{
    d_type[0] = d_type[i];
    d_energy[0] = d_energy[i];          /* it keeps what it had left */
    burn = 64;
    points(take_pts[dr_class[d_type[i]]]);
    remove_droid(i);
    player_picture();
}

/* a transfer lost from a host: the device on its own again, the host's
 * kill points off the score (as the original) */
void transfer_lost(void)
{
    static unsigned char p;
    p = kill_pts[dr_class[d_type[0]]];
    score = score > p ? score - p : 0;
    score_changed = 1;
    d_type[0] = 0;
    burn = 64;
    player_picture();
}

/* a transfer lost by the bare device: it burns out */
void burnt_out(void)
{
    if (dbg_god)
        return;
    d_energy[0] = 0;
    player_dead = 1;
    d_boom[0] = 1;
    sound(SND_BOOM);
}
