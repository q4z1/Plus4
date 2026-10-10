/*
 * farm.c - the farm: hoeing, watering, planting, harvesting, clearing, and
 * what happens to it overnight
 *
 * A farm tile shows what grows on it, so the tile itself is the picture:
 * soil, seed, sprout, young plant, ripe crop, each dry or wet (the wet tile
 * is always the dry one plus one). What kind of crop it is and how many
 * days it has grown is kept beside the room in G.crop and G.age.
 */
#include "game.h"

/* crops 1..6: parsnip, cauliflower, tomato, melon, pumpkin, eggplant */
/* A season is 14 days: everything planted in its first days gets ripe. */
const unsigned char crop_days[7]   = { 0, 4, 8, 7, 9, 10, 5 };
const unsigned char crop_season[7] = { 0, 0, 0, 1, 1, 2, 2 };
const unsigned char crop_regrow[7] = { 0, 0, 0, 3, 0, 0, 4 };
const unsigned int seed_price[7]   = { 0, 20, 80, 50, 80, 100, 20 };

#define DEAD 0x80                           /* in G.crop: withered */

static unsigned char hit_x = 255, hit_y, hits;   /* a tree being felled */

unsigned char farm_idx(void)
{
    if (room_id == R_FARM_W)
        return 0;
    if (room_id == R_FARM_E)
        return 1;
    return 255;
}

/* the tile for crop i of farm room f; wet or dry as given */
static unsigned char crop_look(unsigned char f, unsigned char i, unsigned char wet)
{
    static unsigned char k, a, d, t;
    k = G.crop[f][i];
    a = G.age[f][i];
    if (k == 0)
        t = T_SOIL;
    else if (k & DEAD)
        t = T_DEAD;
    else {
        d = crop_days[k];
        if (a >= d)
            t = T_PARSNIP + ((k - 1) << 1);
        else if (a == 0)
            t = T_SEED;
        else if ((unsigned char)(a + a) < d)
            t = T_SPROUT;
        else
            t = T_YOUNG;
    }
    return t + wet;
}

unsigned char crop_tile(unsigned char f, unsigned char i)
{
    return crop_look(f, i, (unsigned char)((G.farm[f][i] - T_SOIL) & 1));
}

static unsigned char is_soil(unsigned char t)
{
    return (unsigned char)(t - T_SOIL) <= (unsigned char)(T_DEAD_WET - T_SOIL);
}

static unsigned char tired(void)
{
    if (G.energy < 2) {
        hud_msg("too tired");
        sfx(SFX_BAD);
        return 1;
    }
    G.energy -= 2;
    return 0;
}

/* how far a tool reaches: 1 tile, and one more per upgrade */
static unsigned char reach(unsigned char tool)
{
    return 1 + G.lvl[tool];
}

/* One use of the selected item on tile tx, ty of a farm room. Returns 1 if
   anything was done. */
unsigned char farm_action(unsigned char tx, unsigned char ty)
{
    static unsigned char f, i, t, it, k, n, done, x, y;
    f = farm_idx();
    i = ty * RW + tx;
    t = tile_at(tx, ty);
    it = G.inv[sel];

    /* a ripe crop comes out, whatever is in the hand */
    if (is_soil(t) && G.crop[f][i]) {
        k = G.crop[f][i];
        if (k & DEAD) {
            if (it == IT_HOE || it == IT_PICK || it == IT_SWORD) {
                G.crop[f][i] = 0;
                set_tile(tx, ty, T_SOIL + ((t - T_SOIL) & 1));
                sfx(SFX_HOE);
                return 1;
            }
        } else if (G.age[f][i] >= crop_days[k]) {
            if (!give(IT_PARSNIP - 1 + k, 1)) {
                hud_msg("bag is full");
                return 1;
            }
            if (crop_regrow[k])
                G.age[f][i] = crop_days[k] - crop_regrow[k];
            else
                G.crop[f][i] = 0;
            set_tile(tx, ty, crop_tile(f, i));
            sfx(SFX_PICK);
            return 1;
        }
    }

    switch (it) {
    case IT_HOE:
        if (tired())
            return 1;
        done = 0;
        x = tx;
        y = ty;
        for (n = reach(0); n; --n) {
            if (x >= RW || y >= RH)
                break;
            t = tile_at(x, y);
            if (!(flag_at(x, y) & F_TILL))
                break;
            set_tile(x, y, T_SOIL);
            G.crop[f][y * RW + x] = 0;
            done = 1;
            x += dir_dx[pdir];
            y += dir_dy[pdir];
        }
        sfx(done ? SFX_HOE : SFX_BAD);
        return 1;

    case IT_CAN:
        if (flag_at(tx, ty) & F_WATER) {
            G.water = 20 + 20 * G.lvl[1];
            sfx(SFX_WATER);
            hud_msg("can is full");
            return 1;
        }
        if (!is_soil(t))
            return 0;
        if (!G.water) {
            hud_msg("can is empty");
            sfx(SFX_BAD);
            return 1;
        }
        if (tired())
            return 1;
        x = tx;
        y = ty;
        for (n = reach(1); n && G.water; --n) {
            if (x >= RW || y >= RH)
                break;
            t = tile_at(x, y);
            if (!is_soil(t))
                break;
            if (!((t - T_SOIL) & 1)) {
                set_tile(x, y, t + 1);
                --G.water;
            }
            x += dir_dx[pdir];
            y += dir_dy[pdir];
        }
        sfx(SFX_WATER);
        return 1;

    case IT_AXE:
        if (t != T_TREE && t != T_STUMP && t != T_BRANCH)
            return 0;
        if (tired())
            return 1;
        sfx(SFX_CHOP);
        if (t == T_BRANCH) {
            set_tile(tx, ty, T_GRASS);
            give(IT_WOOD, 1);
            return 1;
        }
        if (hit_x != tx || hit_y != ty) {
            hit_x = tx;
            hit_y = ty;
            hits = 0;
        }
        ++hits;
        k = (t == T_TREE ? 5 : 3) - G.lvl[2];
        if (k > 5 || k == 0)
            k = 1;
        if (hits >= k) {
            hit_x = 255;
            if (t == T_TREE) {
                set_tile(tx, ty, T_STUMP);
                give(IT_WOOD, 5);
            } else {
                set_tile(tx, ty, T_GRASS);
                give(IT_WOOD, 2);
            }
        }
        return 1;

    case IT_PICK:
        if (t == T_STONE) {
            if (tired())
                return 1;
            set_tile(tx, ty, T_GRASS);
            give(IT_STONE, 1);
            sfx(SFX_ROCK);
            return 1;
        }
        if (t == T_SPRINKLER) {
            set_tile(tx, ty, T_GRASS);
            give(IT_SPRINKLER, 1);
            sfx(SFX_PICK);
            return 1;
        }
        if (is_soil(t) && !G.crop[f][i]) {
            if (tired())
                return 1;
            set_tile(tx, ty, T_GRASS);
            sfx(SFX_HOE);
            return 1;
        }
        return 0;

    case IT_SWORD:
        if (t == T_WEEDS) {
            set_tile(tx, ty, T_GRASS);
            if (rnd() & 1)
                give(IT_FIBER, 1);
            sfx(SFX_SWING);
            return 1;
        }
        return 0;

    case IT_SPRINKLER:
        if (t == T_GRASS || t == T_GRASS2 || (is_soil(t) && !G.crop[f][i])) {
            G.crop[f][i] = 0;
            set_tile(tx, ty, T_SPRINKLER);
            take(IT_SPRINKLER, 1);
            sfx(SFX_PICK);
            return 1;
        }
        return 0;
    }

    if (IS_SEED(it)) {
        if (!is_soil(t) || G.crop[f][i])
            return 0;
        k = it - IT_S_PARSNIP + 1;
        if (crop_season[k] != G.season) {
            hud_msg("wrong season");
            sfx(SFX_BAD);
            return 1;
        }
        G.crop[f][i] = k;
        G.age[f][i] = 0;
        take(it, 1);
        set_tile(tx, ty, crop_tile(f, i));
        sfx(SFX_PICK);
        return 1;
    }
    return 0;
}

/* ----------------------------------------------------------------------
 * Overnight
 * -------------------------------------------------------------------- */

static unsigned char water_at(unsigned char f, unsigned char i)
{
    static unsigned char t;
    t = G.farm[f][i];
    if (is_soil(t))                        /* a wet tile is the dry one + 1 */
        G.farm[f][i] = T_SOIL + ((unsigned char)(t - T_SOIL) | 1);
    return 0;
}

/* a sprinkler on one of the four tiles next to tile i */
static unsigned char near_sprinkler(unsigned char f, unsigned char i)
{
    static const unsigned char *p;
    p = G.farm[f];
    if (i >= RW && p[i - RW] == T_SPRINKLER) return 1;
    if (i < RW * (RH - 1) && p[i + RW] == T_SPRINKLER) return 1;
    if (i % RW && p[i - 1] == T_SPRINKLER) return 1;
    if (i % RW != RW - 1 && p[i + 1] == T_SPRINKLER) return 1;
    return 0;
}

void farm_night(void)
{
    static unsigned char f, i, t, k, wet, x, y;
    for (f = 0; f < 2; ++f) {
        i = 0;
        for (y = 0; y < RH; ++y) {
            for (x = 0; x < RW; ++x, ++i) {
                t = G.farm[f][i];
                if (is_soil(t)) {
                    wet = (t - T_SOIL) & 1;
                    k = G.crop[f][i];
                    if (k && !(k & DEAD)) {
                        if (crop_season[k] != G.season)
                            G.crop[f][i] = k | DEAD;
                        else if (wet && G.age[f][i] < crop_days[k])
                            ++G.age[f][i];
                    } else if (!k && !wet && rnd() < 12 && !near_sprinkler(f, i)) {
                        G.farm[f][i] = T_GRASS;     /* soil left alone */
                        continue;
                    }
                    /* the new morning: dry, or wet with rain */
                    G.farm[f][i] = crop_look(f, i, G.rain);
                } else if ((t == T_GRASS || t == T_GRASS2) && rnd() < 3
                           && x > 0 && y > 0 && x < RW - 1 && y < RH - 1) {
                    /* things turn up on the farm */
                    k = rnd();
                    if (k < 100)
                        G.farm[f][i] = T_WEEDS;
                    else if (k < 180)
                        G.farm[f][i] = T_STONE;
                    else
                        G.farm[f][i] = T_BRANCH;
                }
            }
        }
        /* sprinklers water the four tiles next to them */
        for (i = 0; i < RW * RH; ++i) {
            if (G.farm[f][i] == T_SPRINKLER) {
                if (i >= RW) water_at(f, i - RW);
                if (i < RW * (RH - 1)) water_at(f, i + RW);
                if (i % RW) water_at(f, i - 1);
                if (i % RW != RW - 1) water_at(f, i + 1);
            }
        }
    }
}
