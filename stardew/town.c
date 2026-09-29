/*
 * town.c - the villagers: where they are, how they wander, what they say,
 * and what they think of presents
 *
 * Three villagers live in the upper village: Lena in the house on the
 * left, Tom and Mara in the one on the right. From nine in the morning to
 * seven in the evening each is out in one of the two village rooms and
 * wanders about there; from seven to ten they are at home; then they go to
 * bed and the doors are shut until morning (stardew.c). Otto and Karl
 * stand behind their counters all day; talking to them is buying and
 * selling (ui.c).
 */
#include "game.h"

#define NPC_SPEED 6                         /* 16ths of a pixel per frame */

static const unsigned char npc_spr[N_NPC] = { S_G_DOWN, S_M_DOWN, S_G_DOWN };
static const unsigned char npc_col[N_NPC] = { 0x4A, 0x3D, 0x4C };
static const char *const npc_name[N_NPC] = { "lena:", "tom:", "mara:" };
static const unsigned char npc_love[N_NPC] = { IT_MELON, IT_GEM, IT_PUMPKIN };
static const unsigned char npc_like[N_NPC] = { IT_PARSNIP, IT_BAR_G, IT_CAULI };
static const unsigned char npc_hate[N_NPC] = { IT_SLIME, IT_FIBER, IT_STONE };

/* sprite offsets from the _DOWN frame: down, down step, up, side, side step */
enum { N_DOWN, N_DOWN1, N_UP, N_SIDE, N_SIDE1 };

static const char *const lines[N_NPC][4] = {
    {
        "hi! you are the new farmer, right? welcome to the valley.",
        "i love summer. melons are the best thing that grows here.",
        "the mine up north is dangerous. do not go without a sword!",
        "you know... i am really glad you moved here.",
    }, {
        "karl can make your tools better if you bring him bars.",
        "deeper down the mine the rocks hold iron, further down gold.",
        "i found an amethyst once. prettiest thing i ever saw.",
        "you are tougher than you look, farmer.",
    }, {
        "otto sells seeds for every season. plant them early!",
        "a crop only grows on days you water it. or when it rains.",
        "the smith makes sprinklers. they water the soil for you.",
        "come by any time. i will bake you something.",
    }
};

/* where each villager is on a day: room, and tile to start from */
static const unsigned char where_room[N_NPC][2] = {
    { R_TOWN, R_TOWN_N }, { R_TOWN_N, R_TOWN }, { R_TOWN, R_TOWN }
};
static const unsigned char where_x[N_NPC] = { 6, 11, 16 };
static const unsigned char where_y[N_NPC] = { 8, 7, 9 };

/* and in the evening, at home */
static const unsigned char home_room[N_NPC] = { R_LENA_HOUSE, R_MARA_HOUSE, R_MARA_HOUSE };
static const unsigned char home_x[N_NPC] = { 6, 12, 6 };
static const unsigned char home_y[N_NPC] = { 5, 6, 6 };

static unsigned char on[N_NPC];             /* in this room now */
static unsigned char nx[N_NPC], ny[N_NPC], nd[N_NPC], nt[N_NPC], nsub[N_NPC];
static unsigned char nwalk[N_NPC], nstep[N_NPC];

/* Otto and Karl */
static unsigned char keeper;                /* 0 none, 1 Otto, 2 Karl */

void npc_enter(void)
{
    static unsigned char k;
    keeper = 0;
    if (room_id == R_STORE)
        keeper = 1;
    else if (room_id == R_SMITH)
        keeper = 2;
    for (k = 0; k < N_NPC; ++k) {
        on[k] = 0;
        if (G.hour < 9 || G.hour >= 22)
            continue;                       /* asleep */
        if (G.hour >= 19 || (G.rain && k == 1)) {
            if (home_room[k] != room_id)
                continue;
            nx[k] = home_x[k] << 3;
            ny[k] = (home_y[k] << 4) - 2;
        } else {
            if (where_room[k][G.day & 1] != room_id)
                continue;
            nx[k] = where_x[k] << 3;
            ny[k] = (where_y[k] << 4) - 2;
        }
        on[k] = 1;
        nd[k] = D_DOWN;
        nt[k] = 50;
        nwalk[k] = 0;
    }
}

void npc_update(unsigned char n)
{
    static unsigned char k, x, y, s, r;
    for (k = 0; k < N_NPC; ++k) {
        if (!on[k])
            continue;
        if (nt[k] > n) {
            nt[k] -= n;
        } else {
            /* something new: stand about, or walk somewhere */
            r = rnd();
            nt[k] = 40 + (r & 63);
            nwalk[k] = r & 0x80 ? 0 : 1;
            nd[k] = (r >> 2) & 3;
        }
        if (!nwalk[k])
            continue;
        s = nsub[k] + n * NPC_SPEED;
        nsub[k] = s & 15;
        s >>= 4;
        while (s--) {
            x = nx[k] + dir_dx[nd[k]];
            y = ny[k] + (dir_dy[nd[k]] << 1);
            if (x > 152 || y > 160 || blocked(x, y)
                || ((unsigned char)(x - px + 7) < 15 && (unsigned char)(y - py + 12) < 25)) {
                nwalk[k] = 0;
                break;
            }
            nx[k] = x;
            ny[k] = y;
            ++nstep[k];
        }
    }
}

void npc_draw(void)
{
    static unsigned char k, s, fl, d;
    for (k = 0; k < N_NPC; ++k) {
        if (!on[k])
            continue;
        s = npc_spr[k];
        fl = 0;
        d = nd[k];
        if (!nwalk[k] && d != D_UP)
            d = D_DOWN;                     /* standing: face the player */
        switch (d) {
        case D_DOWN:
            if (nwalk[k] && (nstep[k] & 8)) {
                s += N_DOWN1;
                fl = nstep[k] & 16 ? 1 : 0;
            }
            break;
        case D_UP:
            s += N_UP;
            if (nwalk[k] && (nstep[k] & 8))
                fl = 1;
            break;
        default:
            s += (nwalk[k] && (nstep[k] & 8)) ? N_SIDE1 : N_SIDE;
            fl = d == D_LEFT;
        }
        fig(nx[k], ny[k], s, fl, npc_col[k]);
    }
    if (keeper == 1)
        fig(5 << 3, (3 << 4) - 2, S_M_DOWN, 0, 0x2E);
    else if (keeper == 2)
        fig(5 << 3, (3 << 4) - 2, S_M_DOWN, 0, 0x29);
}

/* the villager standing on (or reaching into) tile tx, ty */
unsigned char npc_at(unsigned char tx, unsigned char ty)
{
    static unsigned char k, x, y;
    for (k = 0; k < N_NPC; ++k) {
        if (!on[k])
            continue;
        x = (nx[k] + 4) >> 3;
        y = (ny[k] + 13) >> 4;
        if (x == tx && (y == ty || (unsigned char)(y - 1) == ty))
            return k;
    }
    return 255;
}

static const unsigned char opposite[4] = { D_UP, D_DOWN, D_RIGHT, D_LEFT };

void npc_talk(unsigned char k)
{
    static unsigned char it, bit, f, i;
    static const char *s;
    bit = 1 << k;
    it = G.inv[sel];
    nwalk[k] = 0;
    nt[k] = 100;
    /* face the farmer */
    nd[k] = opposite[pdir];
    if (it && !IS_TOOL(it) && !(G.gifted & bit)) {
        G.gifted |= bit;
        take(it, 1);
        f = 8;
        s = "thank you.";
        if (it == npc_love[k]) {
            f = 45;
            s = "oh! i love this! thank you so much!";
        } else if (it == npc_like[k]) {
            f = 25;
            s = "thanks, that is really nice of you.";
        } else if (it == npc_hate[k]) {
            f = 0;
            s = "um... thanks, i guess?";
            if (G.friend[k] >= 10)
                G.friend[k] -= 10;
        }
        if (G.friend[k] + f > 250)
            G.friend[k] = 250;
        else
            G.friend[k] += f;
        say(npc_name[k], s);
        return;
    }
    if (!(G.talked & bit)) {
        G.talked |= bit;
        if (G.friend[k] <= 245)
            G.friend[k] += 5;
    }
    if (G.friend[k] >= 150)
        i = 3;
    else
        i = (G.day + G.season + k) % 3;
    say(npc_name[k], lines[k][i]);
}
