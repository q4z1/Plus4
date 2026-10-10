/*
 * mine.c - the mine: floors, rocks and ores, the ladder down, monsters
 *
 * A floor is one of three cave shapes from the disk (MINE_A..C), filled
 * with rocks when the farmer climbs down: plain rock near the top, copper
 * from floor 1, iron from 10, gold from 20, and now and then an amethyst.
 * Under one rock lies the ladder to the next floor. Every fifth floor
 * the lift at the entrance learns to go there.
 *
 * Monsters: slimes hop towards the farmer, bats flutter, and from floor
 * 20 on ghosts drift through the rock.
 */
#include "game.h"

#define MAXMON 4
enum { MK_SLIME, MK_BAT, MK_GHOST };

unsigned char mx[MAXMON], my[MAXMON], mk[MAXMON], mhp[MAXMON];     /* visible to tests */
static unsigned char mt[MAXMON], mdx[MAXMON], mdy[MAXMON], mflash[MAXMON];
static unsigned char msub[MAXMON];
static unsigned char mwand[MAXMON];         /* 1: stuck, wandering this hop */
unsigned char nmon;
static unsigned char tier;                  /* 0, 1, 2: floors 1-9, 10-19, 20- */
static unsigned char lad_x, lad_y;          /* the rock the ladder is under */
static unsigned char hit_x = 255, hit_y, hits;

static const unsigned char mon_col[3][3] = {
    { 0x5D, 0x5E, 0x4A },                   /* slimes: green, blue, red */
    { 0x4C, 0x3C, 0x2C },                   /* bats                     */
    { 0x69, 0x69, 0x79 },                   /* ghosts                   */
};
static const unsigned char mon_hp[3][3] = { { 3, 6, 9 }, { 4, 7, 10 }, { 10, 12, 14 } };
static const unsigned char mon_dmg[3][3] = { { 6, 10, 14 }, { 8, 12, 16 }, { 15, 18, 22 } };
static const unsigned char sword_dmg[4] = { 2, 3, 5, 8 };

static unsigned char is_floor(unsigned char t)
{
    return t == M_FLOOR || t == M_FLOOR2;
}

/* A new floor: the cave shape has just been loaded into room[] */
void mine_enter(unsigned char fl)
{
    static unsigned char i, t, r, n, x, y, want, k;
    tier = 0;
    if (fl >= 10)
        tier = 1;
    if (fl >= 20)
        tier = 2;
    nmon = 0;
    hit_x = 255;
    if (fl > G.deepest)
        G.deepest = fl;
    lad_x = 255;
    n = 0;
    i = 0;
    for (y = 0; y < RH; ++y)
        for (x = 0; x < RW; ++x, ++i) {
            t = room[i];
            if (!is_floor(t))
                continue;
            /* keep the way from the ladder clear */
            if (y >= 7 && (unsigned char)(x - 8) < 3)
                continue;
            r = rnd();
            if (r > 90)
                continue;
            r = rnd();
            t = (r & 1) ? M_ROCK : M_ROCK2;
            if (r < 4)
                t = M_GEMROCK;
            else if (r < 8)
                t = M_CRATE;
            else if (tier == 0) {
                if (r < 40)
                    t = M_COPPER;
            } else if (tier == 1) {
                if (r < 45)
                    t = M_IRON;
                else if (r < 65)
                    t = M_COPPER;
            } else {
                if (r < 40)
                    t = M_GOLD;
                else if (r < 70)
                    t = M_IRON;
            }
            room[i] = t;
            ++n;
            if (t != M_CRATE && rnd() < 256 / 12 + 1 && lad_x == 255) {
                lad_x = x;
                lad_y = y;
            }
        }
    if (lad_x == 255) {                     /* no rock took it: any rock */
        for (i = 0; i < RW * RH; ++i)
            if (room[i] == M_ROCK || room[i] == M_ROCK2) {
                lad_x = i % RW;
                lad_y = i / RW;
                break;
            }
    }
    if (lad_x == 255) {                     /* no rock at all */
        lad_x = 14;
        lad_y = 3;
        room[3 * RW + 14] = M_LADDER;
    }
    /* monsters */
    want = 1 + fl / 6;
    if (want > MAXMON)
        want = MAXMON;
    for (k = 0; k < 40 && nmon < want; ++k) {
        x = 1 + rnd() % 18;
        y = 1 + rnd() % 6;
        if (!is_floor(room[y * RW + x]))
            continue;
        mx[nmon] = x << 3;
        my[nmon] = y << 4;
        r = rnd();
        mk[nmon] = MK_SLIME;
        if (tier == 0) {
            if (r >= 200)
                mk[nmon] = MK_BAT;
        } else if (tier == 1) {
            if (r >= 128)
                mk[nmon] = MK_BAT;
        } else {
            if (r >= 170)
                mk[nmon] = MK_GHOST;
            else if (r >= 80)
                mk[nmon] = MK_BAT;
        }
        mhp[nmon] = mon_hp[mk[nmon]][tier];
        mt[nmon] = rnd() & 31;
        mdx[nmon] = 1;
        mdy[nmon] = 1;
        mflash[nmon] = 0;
        ++nmon;
    }
}

/* ---- rocks ------------------------------------------------------------ */

static unsigned char rock_hits(unsigned char t)
{
    static unsigned char h;
    switch (t) {
    case M_COPPER:  h = 3; break;
    case M_IRON:    h = 4; break;
    case M_GOLD:    h = 6; break;
    case M_GEMROCK: h = 5; break;
    default:        h = 2;
    }
    h -= G.lvl[3];
    if (h > 6 || h == 0)
        h = 1;
    return h;
}

static void rock_gone(unsigned char tx, unsigned char ty, unsigned char t)
{
    switch (t) {
    case M_COPPER:  give(IT_ORE_C, 1 + (rnd() & 1)); break;
    case M_IRON:    give(IT_ORE_I, 1 + (rnd() & 1)); break;
    case M_GOLD:    give(IT_ORE_G, 1 + (rnd() & 1)); break;
    case M_GEMROCK: give(IT_GEM, 1); break;
    case M_CRATE:
        if (rnd() < 60)
            give(IT_SALAD, 1);
        else
            give(IT_WOOD, 2);
        break;
    default:
        give(IT_STONE, 1);
    }
    if (tx == lad_x && ty == lad_y && floor_no < 30) {
        set_tile(tx, ty, M_LADDER);
        sfx(SFX_LADDER);
        hud_msg("a ladder!");
    } else
        set_tile(tx, ty, M_FLOOR);
}

unsigned char mine_action(unsigned char tx, unsigned char ty)
{
    static unsigned char t, it;
    t = tile_at(tx, ty);
    it = G.inv[sel];
    if (t == M_CRATE && (it == IT_AXE || it == IT_PICK || it == IT_SWORD)) {
        sfx(SFX_CHOP);
        rock_gone(tx, ty, t);
        return 1;
    }
    if (it != IT_PICK)
        return 0;
    if (t != M_ROCK && t != M_ROCK2 && t != M_COPPER && t != M_IRON
        && t != M_GOLD && t != M_GEMROCK)
        return 0;
    if (G.energy < 2) {
        hud_msg("too tired");
        sfx(SFX_BAD);
        return 1;
    }
    G.energy -= 2;
    sfx(SFX_ROCK);
    if (hit_x != tx || hit_y != ty) {
        hit_x = tx;
        hit_y = ty;
        hits = 0;
    }
    if (++hits >= rock_hits(t)) {
        hit_x = 255;
        rock_gone(tx, ty, t);
    }
    return 1;
}

/* ---- monsters --------------------------------------------------------- */

static void hurt_player(unsigned char k)
{
    static unsigned char d;
    d = mon_dmg[mk[k]][tier];
    if (G.hp > d)
        G.hp -= d;
    else
        G.hp = 0;
    hurt = 60;
    sfx(SFX_HURT);
    hud_status();
}

/* a step of monster ms_k by ms_dx, ms_dy that respects the rock (slimes)
   - the arguments in statics, not on cc65's stack: it runs often */
static unsigned char ms_k;
static signed char ms_dx, ms_dy;

static void mstep(void)
{
    static unsigned char x, y;
    x = mx[ms_k] + ms_dx;
    y = my[ms_k] + ms_dy;
    if (x > 152 || y > 160)
        return;
    if (mk[ms_k] == MK_SLIME && blocked(x, y))
        return;
    mx[ms_k] = x;
    my[ms_k] = y;
}

void mine_update(unsigned char n)
{
    static unsigned char k, s, r, ox, oy;
    static signed char dx, dy;
    for (k = 0; k < nmon; ++k) {
        if (mflash[k])
            mflash[k] = mflash[k] > n ? mflash[k] - n : 0;
        /* towards the farmer */
        dx = 0;
        if (px > mx[k])
            dx = 1;
        else if (px < mx[k])
            dx = -1;
        dy = 0;
        if (py > my[k])
            dy = 1;
        else if (py < my[k])
            dy = -1;
        switch (mk[k]) {
        case MK_SLIME:
            /* hop for half a second, rest for half a second; a slime
               that got stuck tries another way for one hop */
            mt[k] += n;
            if (mt[k] & 32) {
                mwand[k] = 0;
                continue;
            }
            if (mwand[k]) {
                dx = mdx[k];
                dy = mdy[k];
            }
            s = msub[k] + n * 6;
            break;
        case MK_BAT:
            mt[k] += n;
            if (mt[k] >= 40) {
                mt[k] = 0;
                r = rnd();
                mdx[k] = r & 1 ? 1 : 255;
                mdy[k] = r & 2 ? 1 : 255;
                if (r < 128) {              /* now and then straight at you */
                    mdx[k] = dx;
                    mdy[k] = dy;
                }
            }
            dx = mdx[k];
            dy = mdy[k];
            s = msub[k] + n * 10;
            break;
        default:
            s = msub[k] + n * 4;
        }
        msub[k] = s & 15;
        s >>= 4;
        r = s;                              /* steps this frame */
        ox = mx[k];
        oy = my[k];
        ms_k = k;
        while (s--) {
            ms_dx = dx;
            ms_dy = 0;
            mstep();
            ms_dx = 0;
            ms_dy = dy;
            mstep();
            mstep();
        }
        if (mk[k] == MK_SLIME && r && ox == mx[k] && oy == my[k] && !mwand[k]) {
            r = rnd();
            mwand[k] = 1;
            mdx[k] = r & 1 ? 1 : 255;
            mdy[k] = r & 2 ? 1 : 255;
            if (r & 4)
                mdx[k] = 0;
            else
                mdy[k] = 0;
        }
        if (mk[k] == MK_BAT) {
            if (mx[k] < 8 || mx[k] > 144)
                mdx[k] = -mdx[k];
            if (my[k] < 8 || my[k] > 144)
                mdy[k] = -mdy[k];
        }
        /* touching the farmer */
        if (!hurt && (unsigned char)(mx[k] - px + 6) < 13
            && (unsigned char)(my[k] - py + 10) < 21)
            hurt_player(k);
    }
}

void mine_draw(void)
{
    static unsigned char k, s;
    for (k = 0; k < nmon; ++k) {
        if (mflash[k] & 2)
            continue;
        switch (mk[k]) {
        case MK_SLIME: s = (mt[k] & 32) ? S_SLIME1 : S_SLIME; break;
        case MK_BAT:   s = (mt[k] & 4) ? S_BAT1 : S_BAT; break;
        default:       s = (mt[k] & 16) ? S_GHOST1 : S_GHOST;
        }
        if (mk[k] == MK_GHOST)
            ++mt[k];
        fig(mx[k], my[k], s, mx[k] > px, mon_col[mk[k]][tier]);
    }
}

/* the sword swung at tile tx, ty: every monster near it takes a blow */
void mine_sword(unsigned char tx, unsigned char ty)
{
    static unsigned char k, x, y, d;
    x = tx << 3;
    y = ty << 4;
    for (k = 0; k < nmon; ++k) {
        if ((unsigned char)(mx[k] - x + 8) >= 17 || (unsigned char)(my[k] - y + 12) >= 25)
            continue;
        d = sword_dmg[G.lvl[4]];
        sfx(SFX_HIT);
        mflash[k] = 12;
        /* knocked back */
        ms_k = k;
        ms_dx = dir_dx[pdir] << 2;
        ms_dy = dir_dy[pdir] << 3;
        mstep();
        if (mhp[k] > d) {
            mhp[k] -= d;
            continue;
        }
        /* gone */
        if (mk[k] == MK_SLIME && (rnd() & 1))
            give(IT_SLIME, 1);
        else if (mk[k] == MK_BAT && rnd() < 60)
            give(IT_ORE_C + tier, 1);
        else if (mk[k] == MK_GHOST && rnd() < 40)
            give(IT_GEM, 1);
        --nmon;
        mx[k] = mx[nmon]; my[k] = my[nmon]; mk[k] = mk[nmon]; mhp[k] = mhp[nmon];
        mt[k] = mt[nmon]; mdx[k] = mdx[nmon]; mdy[k] = mdy[nmon];
        mflash[k] = mflash[nmon]; msub[k] = msub[nmon];
        --k;
    }
}
