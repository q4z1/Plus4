/*
 * world.c - rooms: loading them from disk, drawing them, walking between
 * them, and the save file
 *
 * Every room is one screen of 20 x 11 tiles and a file of its own on the
 * disk (tools/mkdata.py, data/rooms.txt). A tile is four characters from
 * the room's tile set, which is a file as well. The two farm rooms are
 * loaded once, for a new game, and after that live in the game state,
 * because the farmer changes them.
 *
 * Every file is packed by exomizer (unpack.s). Tile sets and rooms stay in
 * memory as they came off the disk, packed: each is loaded once, and after
 * that walking in and out of a house or along the village costs no disk at
 * all, only the moment it takes to unpack it.
 */
#include <cbm.h>
#include <string.h>
#include "game.h"

#pragma bss-name (push, "HIBSS")
unsigned char room[256];
unsigned char mt_code[512];
unsigned char mt_attr[512];
unsigned char mt_flag[128];
#pragma bss-name (pop)

/* The tile sets as they came off the disk, packed. Each is loaded the
   first time it is needed and kept. */
static unsigned char ts0[TILES0_PACKED], ts1[TILES1_PACKED], ts2[TILES2_PACKED];
static unsigned char ts3[TILES3_PACKED];
static unsigned char *const ts_buf[4] = { ts0, ts1, ts2, ts3 };
static unsigned char ts_have[4];

/* The rooms likewise, one after the other in a pool. When it is full it
   starts again from empty: the rooms come off the disk again as they are
   needed. */
#define RC_POOL 0x380
#pragma bss-name (push, "ROOMPOOL")
static unsigned char rc_pool[RC_POOL];
#pragma bss-name (pop)
static unsigned int rc_used;
static unsigned char *rc_at[N_ROOMS];

/* Where a file is unpacked: the two pictures' screens, which are drawn
   afresh after every load anyway (the screen is off meanwhile). */
#define SCRATCH ((unsigned char *)0xD000)

unsigned char room_id;
unsigned char floor_no;
unsigned char dev;
static unsigned char cur_set = 255;

static const unsigned char row20[RH] = { 0, 20, 40, 60, 80, 100, 120, 140, 160, 180, 200 };

/* offset of the top left character of tile row ty: ty * 80 */
static const unsigned int row80[RH] = { 0, 80, 160, 240, 320, 400, 480, 560, 640, 720, 800 };

unsigned char tile_at(unsigned char tx, unsigned char ty)
{
    return room[row20[ty] + tx];
}

unsigned char flag_at(unsigned char tx, unsigned char ty)
{
    if (tx >= RW || ty >= RH)
        return F_SOLID;
    return MT_FLAG[room[row20[ty] + tx]];
}

/* the four characters of a tile into the map image (not the screen) */
static void image_tile(unsigned char tx, unsigned char ty)
{
    static unsigned char t;
    static unsigned int off;
    t = room[row20[ty] + tx];
    off = row80[ty] + (tx << 1);
    base_code[off] = MT_CODE[t];
    base_code[off + 1] = MT_CODE[128 + t];
    base_code[off + 40] = MT_CODE[256 + t];
    base_code[off + 41] = MT_CODE[384 + t];
    base_attr[off] = MT_ATTR[t];
    base_attr[off + 1] = MT_ATTR[128 + t];
    base_attr[off + 40] = MT_ATTR[256 + t];
    base_attr[off + 41] = MT_ATTR[384 + t];
}

/* a tile changes: the room, the farm if this is the farm, the map image
   and both pictures */
void set_tile(unsigned char tx, unsigned char ty, unsigned char t)
{
    static unsigned char i, f;
    static unsigned int off;
    i = row20[ty] + tx;
    room[i] = t;
    f = farm_idx();
    if (f != 255)
        G.farm[f][i] = t;
    off = row80[ty] + (tx << 1);
    put_code = MT_CODE[t];        put_attr = MT_ATTR[t];        eng_put(off);
    put_code = MT_CODE[128 + t];  put_attr = MT_ATTR[128 + t];  eng_put(off + 1);
    put_code = MT_CODE[256 + t];  put_attr = MT_ATTR[256 + t];  eng_put(off + 40);
    put_code = MT_CODE[384 + t];  put_attr = MT_ATTR[384 + t];  eng_put(off + 41);
}

/* The colours: the room's own, but outside the grass follows the season
   and the evening makes everything darker. */
static const unsigned char season_bg[4] = { 0x35, 0x3A, 0x38, 0x61 };
static const unsigned char season_dark[4] = { 0x09, 0x09, 0x09, 0x21 };

void set_palette(void)
{
    static unsigned char bg, dk;
    bg = room[RM_PAL];
    dk = room[RM_PAL + 1];
    if (room[RM_FLAGS] & RF_SEASON) {
        bg = season_bg[G.season];
        dk = season_dark[G.season];
        if (G.rain && bg > 0x10)
            bg -= 0x10;
        if (G.hour >= 18 && bg > 0x10)
            bg -= 0x10;
        if (G.hour >= 21 && bg > 0x10)
            bg -= 0x10;
    }
    pal_map[0] = bg;
    pal_map[1] = dk;
    pal_map[2] = room[RM_PAL + 2];
    pal_map[3] = room[RM_PAL + 3];
}

/* the whole room into the map image and onto both pictures */
void show_room(void)
{
    static unsigned char tx, ty;
    for (ty = 0; ty < RH; ++ty)
        for (tx = 0; tx < RW; ++tx)
            image_tile(tx, ty);
    eng_fill();
    set_palette();
}

/* ----------------------------------------------------------------------
 * The disk
 * -------------------------------------------------------------------- */

/* Load a file to addr; the screen must be off (eng_blank), because the
   KERNAL does the work with its own interrupt handler in place. Tries a
   few times, then gives up: 0. Else the number of bytes loaded. */
unsigned int __fastcall__ load_file(const char *name, void *addr)
{
    static unsigned char k;
    static unsigned int n;
    static const char *nm;
    static void *ad;
    nm = name;
    ad = addr;
    for (k = 0; k < 3; ++k) {
        n = cbm_load(nm, dev, ad);
        if (n)
            return n;
    }
    return 0;
}

/* The same, until it works: a red border while there is no disk. */
static unsigned int must_load(const char *name, void *addr)
{
    static unsigned int n;
    while (!(n = load_file(name, addr)))
        *(volatile unsigned char *)0xFF19 = 0x32;
    return n;
}

static char fname[8] = "room00";

/* room id into room[]: from the pool, or off the disk into the pool */
static void load_room(unsigned char id)
{
    static unsigned char *p;
    p = rc_at[id];
    if (!p) {
        if (rc_used > RC_POOL - ROOM_PACKED_MAX) {
            memset(rc_at, 0, sizeof(rc_at));
            rc_used = 0;
        }
        p = rc_pool + rc_used;
        fname[4] = '0' + id / 10;
        fname[5] = '0' + id % 10;
        rc_used += must_load(fname, p);
        rc_at[id] = p;
    }
    unp_dst = room;
    unpack(p);
}

/* The toolbar's characters, once at the start. */
void load_hud(void)
{
    must_load("hud", SCRATCH);
    unp_dst = (unsigned char *)0xE000;
    unpack(SCRATCH);
}

static char tname[8] = "tiles0";

/* A tile set, unpacked: number of characters, number of tiles, the
   characters, then codes, colours and flags, each as long as there are
   tiles. The characters go into both map character sets, the rest into
   mt_*. */
static void unpack_tiles(const unsigned char *p)
{
    static unsigned char nc, nt, k;
    static unsigned int len;
    nc = p[0];
    nt = p[1];
    p += 2;
    len = (unsigned int)nc << 3;
    memcpy((void *)0xC000, p, len);
    memcpy((void *)0xC800, p, len);
    p += len;
    for (k = 0; k < 4; ++k, p += nt)
        memcpy(mt_code + (k << 7), p, nt);
    for (k = 0; k < 4; ++k, p += nt)
        memcpy(mt_attr + (k << 7), p, nt);
    memcpy(mt_flag, p, nt);
    p += nt;
    water_n = *p++;                 /* the water's characters (engine.s) */
    memcpy(water_ab, p, water_n * 3);
    water_ph[0] = water_ph[1] = 0;  /* both sets as they came */
}

/* Go to room id, the farmer standing on tile tx, ty. The screen goes dark
   while the room comes off the disk. */
void enter_room(unsigned char id, unsigned char tx, unsigned char ty)
{
    static unsigned char f, s;
    eng_blank();
    room_id = id;
    f = farm_idx();                 /* uses room_id */
    if (f != 255)
        memcpy(room, G.farm[f], 256);
    else
        load_room(id);
    s = room[RM_SET];
    if (s != cur_set) {
        if (!ts_have[s]) {
            tname[5] = '0' + s;
            must_load(tname, ts_buf[s]);
            ts_have[s] = 1;
        }
        unp_dst = SCRATCH;
        unpack(ts_buf[s]);
        unpack_tiles(SCRATCH);
        cur_set = s;
    }
    if (floor_no && (room[RM_FLAGS] & RF_MINE))
        mine_enter(floor_no);
    show_room();
    music = (room[RM_FLAGS] & RF_MINE) ? SONG_MINE : SONG_FARM;
    place_player(tx, ty);
    npc_enter();
    hud_all();
    eng_unblank();
}

/* A new game starts with the farm as it is on the disk. */
void farm_new(void)
{
    eng_blank();
    load_room(R_FARM_W);
    memcpy(G.farm[0], room, 256);
    load_room(R_FARM_E);
    memcpy(G.farm[1], room, 256);
    memset(G.crop, 0, sizeof(G.crop));
    memset(G.age, 0, sizeof(G.age));
}

/* the bytes of the game state added up */
static unsigned char save_sum(void)
{
    static unsigned char s;
    static const unsigned char *p;
    s = 0;
    for (p = (const unsigned char *)&G; p != (const unsigned char *)(&G + 1); ++p)
        s += *p;
    return s;
}

/* The save file: the game state as it is, one file. The old one is
   scratched first; the 1541's save-with-replace is not to be trusted.
   Then the drive's status is read: that waits until it has really written
   the file's last block and its directory entry - else, with nothing to
   load next (the house comes from memory), the file stays open on the
   disk until the drive is next spoken to, and switching off loses it. */
unsigned char save_game(void)
{
    static unsigned char r;
    static char st[2];
    eng_blank();
    G.magic = SAVE_MAGIC;
    G.sum = 0;
    G.sum = -save_sum();
    cbm_open(15, dev, 15, "s0:save");
    cbm_close(15);
    r = cbm_save("save", dev, &G, sizeof(G));
    st[0] = 0;
    if (cbm_open(15, dev, 15, "") == 0) {
        cbm_read(15, st, 2);
        cbm_close(15);
    }
    return r == 0 && st[0] == '0' && st[1] == '0';
}

/* A save that does not add up is not played: a fast loader once brought
   one back broken. */
unsigned char load_game(void)
{
    static unsigned int n;
    eng_blank();
    n = cbm_load("save", dev, &G);
    return n == sizeof(G) && G.magic == SAVE_MAGIC && save_sum() == 0;
}
