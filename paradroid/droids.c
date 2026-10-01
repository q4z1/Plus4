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

static unsigned char drain;             /* ticks until the host loses energy */

/* how much energy a droid type has: by its class */
unsigned char emax(unsigned char type)
{
    return 40 + dr_class[type] * 20;
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

/* damage of a shot, by weapon */
static const unsigned char wdamage[4] = { 0, 10, 20, 30 };

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
        d_energy[nd] = emax(d_type[nd]);
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
    static unsigned char w, dirs, k, n, pick, sp;
    static signed char cx[3], cy[3];
    w = WPMAP[((d_y[i] >> 5) << 6) | (d_x[i] >> 5)];
    if (!w)
        return;                         /* not a waypoint: keep going */
    dirs = wp_dir[w - 1];
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

void move_droids(void)
{
    static unsigned char i;
    droids_step();
    for (i = 1; i < nd; ++i)
        if (d_choose[i]) {
            droid_choose(i);
            if (!d_wait[i]) {
                d_x[i] += d_vx[i];
                d_y[i] += d_vy[i];
            }
        }
}

/* ======================================================================
 * The player
 * ==================================================================== */

static const unsigned char vmax_of[9] = { 0, 5, 6, 0, 7, 0, 0, 0, 7 };

static unsigned char box_free(unsigned x, unsigned y)
{
    return !solid_at(x - 10, y - 7) && !solid_at(x + 10, y - 7)
        && !solid_at(x - 10, y + 7) && !solid_at(x + 10, y + 7);
}

void move_player(unsigned char k)
{
    static signed char vm;
    vm = vmax_of[dr_drive[d_type[0]]];
    if (k & K_FIRE)
        k = 0;                          /* firing or transfer: no driving */
    if (k & K_LEFT) {
        if (d_vx[0] > -vm)
            --d_vx[0];
    } else if (k & K_RIGHT) {
        if (d_vx[0] < vm)
            ++d_vx[0];
    } else if (d_vx[0] > 0)
        --d_vx[0];
    else if (d_vx[0] < 0)
        ++d_vx[0];
    if (k & K_UP) {
        if (d_vy[0] > -vm)
            --d_vy[0];
    } else if (k & K_DOWN) {
        if (d_vy[0] < vm)
            ++d_vy[0];
    } else if (d_vy[0] > 0)
        --d_vy[0];
    else if (d_vy[0] < 0)
        ++d_vy[0];

    if (d_vx[0]) {
        if (box_free(PX + d_vx[0], PY))
            PX += d_vx[0];
        else
            d_vx[0] = 0;
    }
    if (d_vy[0]) {
        if (box_free(PX, PY + d_vy[0]))
            PY += d_vy[0];
        else
            d_vy[0] = 0;
    }
}

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
    s_x[k] = d_x[i] + dx * 12;
    s_y[k] = d_y[i] + dy * 9;
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
    if (!w)
        w = 1;                          /* the device's own lasers */
    shoot(0, dx, dy, w);
    d_cool[0] = 5;
}

unsigned char dbg_god;                  /* tests: the player takes no damage */

static void hit(unsigned char i, unsigned char dmg, unsigned char by_player)
{
    if (i == 0 && dbg_god)
        return;
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
        sound(SND_BOOM);
        return;
    }
    d_boom[i] = 1;
    ship[deck][d_slot[i]] = 0;
    if (by_player) {
        score += dr_class[d_type[i]] * 100 + dr_num[d_type[i]];
        score_changed = 1;
    }
    sound(SND_BOOM);
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
                    hit(j, s_dmg[k], s_own[k] == 0);
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
        d_cool[i] = 26 - alert * 6 + (rnd() & 15);
    }
}

/* ======================================================================
 * Touching droids, energy
 * ==================================================================== */

void collide(void)
{
    static unsigned char i;
    static int dx, dy;
    touched = 0;
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
        /* a bump: both lose a little, the player is pushed back */
        hit(i, 2, 1);
        hit(0, 2, 0);
        d_vx[0] = dx < 0 ? -3 : 3;
        d_vy[0] = dy < 0 ? -2 : 2;
    }
}

void energy_tick(void)
{
    static unsigned char m;
    m = emax(d_type[0]);
    if (blk_flag[blk_at(PX, PY)] & B_ENERGY) {
        if (d_energy[0] < m) {
            ++d_energy[0];
            if (!(tick & 7))
                sound(SND_ENERGY);
        }
    } else if (d_type[0] && !--drain) {
        /* a host burns out */
        drain = 24;
        hit(0, 1, 0);
    }
}

/* the player takes droid i over: it is his host now */
void take_over(unsigned char i)
{
    d_type[0] = d_type[i];
    d_energy[0] = emax(d_type[0]);
    drain = 24;
    score += (dr_class[d_type[i]] * 100 + dr_num[d_type[i]]) * 2;
    score_changed = 1;
    remove_droid(i);
    player_picture();
}
