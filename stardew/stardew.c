/*
 * Stardew Pond for the Commodore Plus/4
 * =====================================
 *
 * A farm, a village and a mine, after Stardew Valley by ConcernedApe:
 * clear the field, plant what the season allows, water it every day, ship
 * the harvest; buy seeds from Otto, have Karl smelt ore and improve the
 * tools; dig down the mine for copper, iron and gold, past slimes, bats
 * and ghosts; make friends with the three villagers.
 *
 * The parts:
 *   engine.s   raster interrupt, two pictures, figures drawn pixel by pixel
 *   world.c    rooms: from disk, onto the screen, and the save file
 *   farm.c     crops and the farm's tools, and the night
 *   ui.c       toolbar, text, conversations and menus
 *   town.c     the villagers
 *   mine.c     the mine
 *   stardew.c  (this file) the farmer, time, and the main loop
 *
 * Rooms, tile sets and the toolbar's characters are files on the disk and
 * are loaded when they are needed; tools/mkdata.py makes them from the text
 * files in data/.
 */
#include <device.h>
#include <string.h>
#include "game.h"

#pragma bss-name (push, "SAVEDATA")
struct game G;
#pragma bss-name (pop)

/* ======================================================================
 * The farmer
 * ==================================================================== */

unsigned char px, py;                       /* top left of the figure  */
unsigned char pdir;
unsigned char sel;                          /* selected slot 0..15     */
unsigned char row2;                         /* 0 or 8                  */
unsigned char hurt;

const signed char dir_dx[4] = { 0, 0, -1, 1 };
const signed char dir_dy[4] = { 1, -1, 0, 0 };

static unsigned char subx, suby;            /* 16ths of a pixel        */
static unsigned char steps;                 /* pixels walked, for the legs */
static unsigned char moving;
static unsigned char use_t;                 /* frames left in the swing */
static unsigned char fx_spr, fx_x, fx_y, fx_t;

#define SPEED_X 8                           /* 16ths of a pixel per frame */
#define SPEED_Y 16                          /* a line is half a pixel wide */
#define PLAYER_COL 0x5E                     /* the shirt: blue           */
#define TICK 250                            /* frames per ten minutes    */


void place_player(unsigned char tx, unsigned char ty)
{
    px = tx << 3;
    py = ty << 4;
    if (py >= 2)
        py -= 2;
    subx = suby = 0;
    use_t = 0;
    fx_t = 0;
}

/* ======================================================================
 * Odds and ends
 * ==================================================================== */

static unsigned int rs = 0x9C35;

unsigned char rnd(void)
{
    rs ^= rs << 7;
    rs ^= rs >> 9;
    rs ^= rs << 8;
    return (unsigned char)rs;
}

void wait_frames(unsigned char n)
{
    static unsigned char f;
    f = frames;
    while ((unsigned char)(frames - f) < n)
        ;
}

/* ---- sound effects: all on voice 2, square or noise ------------------- */

static const unsigned int sfx_freq[] = {
    /* hoe water chop rock pick buy  hit  hurt swing ladder bad  eat */
       900, 850, 960, 990, 940, 980, 970, 700, 1000, 930,   600, 900
};
static const unsigned char sfx_len_of[] = {
       5,   12,  6,   6,   4,   6,   5,   15,  4,    20,   12,  10
};
static const unsigned char sfx_noise_of[] = {
       1,   1,   1,   1,   0,   0,   1,   0,   1,    0,    0,   0
};

/* on voice 2: the tune on voice 1 plays on (engine.s) */
void sfx(unsigned char kind)
{
    static unsigned int f;
    f = sfx_freq[kind];
    sfx_lo = (unsigned char)f;
    sfx_hi = (unsigned char)(f >> 8);
    sfx_noise = sfx_noise_of[kind];
    sfx_len = sfx_len_of[kind];
    eng_sfx();
}

/* ======================================================================
 * Input
 *
 * Joystick in either port, or the cursor keys and space. The rows read
 * here ($BF, $DF, $7F, $EF) are the ones no joystick shares lines with.
 * ==================================================================== */

unsigned char keys_now;                     /* keys down at the last read_keys */

unsigned char dbg_goto, dbg_floor, dbg_x, dbg_y;   /* room + 1: go there */
unsigned char dbg_loops;                    /* pictures drawn */

/* keys that went down since the last call; engine.s reads them in the
   interrupt, so none is lost while the program is busy */
unsigned char read_keys(void)
{
    if (scr_hidden)                         /* a menu drawn: on with it */
        eng_show();
    keys_now = keys_irq;
    return eng_keys();
}

unsigned char fire_pressed(void)
{
    return read_keys() & K_FIRE;
}

void wait_fire(void)
{
    do {
        wait_frames(1);
    } while (!(read_keys() & (K_FIRE | K_MENU)));
}

/* ======================================================================
 * Figures: collected, sorted by where their feet are, drawn
 * ==================================================================== */

static const unsigned char use_spr[4] = { S_P_USE_DOWN, S_P_USE_UP, S_P_USE_SIDE, S_P_USE_SIDE };

static void player_fig(void)
{
    static unsigned char s, fl, c;
    fl = 0;
    c = steps & 12;                         /* legs: 0 stand, 4 step, 8 stand, 12 step */
    if (use_t) {
        s = use_spr[pdir];
        fl = pdir == D_LEFT;
    } else if (pdir == D_DOWN || pdir == D_UP) {
        s = pdir == D_DOWN ? S_P_DOWN : S_P_UP;
        if (moving && (c & 4)) {
            ++s;                            /* the step frame */
            fl = c == 12;
        }
    } else {
        s = (moving && (c & 4)) ? S_P_SIDE1 : S_P_SIDE;
        fl = pdir == D_LEFT;
    }
    if (hurt & 4)
        return;                             /* blinking after a blow */
    fig(px, py, s, fl, PLAYER_COL);
}

static unsigned char target_x, target_y;    /* the tile in front */

static void draw(void)
{
    static unsigned char it;
    nfig = 0;
    player_fig();
    if (floor_no)
        mine_draw();
    else
        npc_draw();
    if (fx_t)
        fig(fx_x, fx_y, fx_spr, pdir == D_LEFT, fx_spr == S_DUST ? 0 : 0x79);
    /* the cursor on the tile in front, when holding something to use */
    it = G.inv[sel];
    if (it && target_x < RW && target_y < RH && !use_t)
        fig(target_x << 3, target_y << 4, S_CURSOR, 0, 0);
    figs_draw();
}

/* ======================================================================
 * Walking: edges lead to the next room, doors to another one
 * ==================================================================== */

static void go_edge(unsigned char d)
{
    static unsigned char to, x, y;
    to = room[RM_EXIT + d];
    if (to == 255)
        return;
    x = px;
    y = py;
    enter_room(to, 0, 0);
    switch (d) {
    case 0: px = x; py = 160; break;        /* north: arrive at the bottom */
    case 1: px = x; py = 0; break;
    case 2: px = 0; py = y; break;          /* east: arrive on the left */
    case 3: px = 152; py = y; break;
    }
    /* a bush where the path was: look along the edge for a way in */
    for (x = 0; x < 20 && blocked(px, py); ++x) {
        if (d < 2)
            px = (px + 8) % 160;
        else
            py = py >= 150 ? 0 : py + 8;
    }
}

/* The farmer is on a door: go through it. A door that leads nowhere is
   locked, and 1 comes back - the caller puts him back where he was. */
static unsigned char check_door(void)
{
    static unsigned char tx, ty, k, *d;
    tx = px;  tx += 4;  tx >>= 3;
    ty = py;  ty += 13; ty >>= 4;
    if (!(flag_at(tx, ty) & F_DOOR))
        return 0;
    for (k = 0; k < 4; ++k) {
        d = room + RM_DOORS + k * 5;
        if (d[0] == tx && d[1] == ty) {
            if ((d[2] == R_LENA_HOUSE || d[2] == R_MARA_HOUSE)
                && (G.hour < 9 || G.hour >= 22)) {
                if (!hud_msg_time)
                    hud_msg("they're asleep");
                return 1;
            }
            sfx(SFX_LADDER);
            floor_no = 0;
            enter_room(d[2], d[3], d[4]);
            return 0;
        }
    }
    if (floor_no) {                         /* the ladder up, out of the mine */
        floor_no = 0;
        sfx(SFX_LADDER);
        enter_room(R_MINE_TOP, 14, 6);
        return 0;
    }
    if (!hud_msg_time)
        hud_msg("it is locked");
    return 1;
}

static void walk(unsigned char n, unsigned char k)
{
    static unsigned char s, d, x, y, ox, oy, stuck;
    moving = 0;
    if (!(k & 15))
        return;
    /* one direction at a time, the last one pressed wins ties */
    if (k & K_LEFT) d = D_LEFT;
    else if (k & K_RIGHT) d = D_RIGHT;
    else if (k & K_UP) d = D_UP;
    else d = D_DOWN;
    pdir = d;
    moving = 1;
    if (d >= D_LEFT) {
        s = subx + n * SPEED_X;
        subx = s & 15;
    } else {
        s = suby + n * SPEED_Y;
        suby = s & 15;
    }
    s >>= 4;
    ox = px;
    oy = py;
    stuck = blocked(px, py);                /* inside something: let him out */
    while (s--) {
        x = px + dir_dx[d];
        y = py + dir_dy[d];
        if (d == D_LEFT && px == 0) { go_edge(3); return; }
        if (d == D_RIGHT && px >= 152) { go_edge(2); return; }
        if (d == D_UP && py == 0) { go_edge(0); return; }
        if (d == D_DOWN && py >= 160) { go_edge(1); return; }
        if (!stuck && blocked(x, y)) {
            /* at a corner: slide towards the middle of the tile */
            if (d < D_LEFT) {
                x = ((px + 4) >> 3) << 3;
                if (px < x && !blocked(px + 1, py)) ++px;
                else if (px > x && !blocked(px - 1, py)) --px;
                else break;
            } else {
                y = (((py + 13) >> 4) << 4) - 2;
                if (py < y && !blocked(px, py + 1)) ++py;
                else if (py > y && !blocked(px, py - 1)) --py;
                else break;
            }
            ++steps;
            continue;
        }
        px = x;
        py = y;
        ++steps;
    }
    /* onto a locked door: back to where he came from - unless he was
       standing on it already and is on his way off */
    if (check_door() && !stuck
        && (((ox + 4) ^ (px + 4)) & 0xF8 || ((oy + 13) ^ (py + 13)) & 0xF0)) {
        px = ox;
        py = oy;
    }
}

/* ======================================================================
 * Doing things
 * ==================================================================== */

static void effect(unsigned char spr)
{
    fx_spr = spr;
    fx_x = target_x << 3;
    fx_y = target_y << 4;
    fx_t = 10;
}

static void ship(void)
{
    static unsigned char it, n;
    static unsigned int v;
    it = G.inv[sel];
    if (!it || !item_price[it] || IS_TOOL(it)) {
        hud_msg("shipping bin");
        return;
    }
    n = G.cnt[sel];
    v = item_price[it] * n;
    G.ship += v;
    if (IS_CROP(it))
        G.shipped |= 1 << (it - IT_PARSNIP);
    G.inv[sel] = 0;
    G.cnt[sel] = 0;
    hud_slots();
    sfx(SFX_BUY);
    hud_msg("shipped!");
}

static void sleep_now(void)
{
    if (ask("go to bed and end the day?"))
        new_day(0);
}

/* a tile that does something when used, whatever is in the hand */
static unsigned char use_tile(unsigned char tx, unsigned char ty)
{
    static unsigned char t, s;
    t = tile_at(tx, ty);
    s = room[RM_SET];
    if (OUTDOOR(s)) {
        switch (t) {
        case T_BIN: ship(); return 1;
        case T_SIGN_SHOP: hud_msg("otto's store"); return 1;
        case T_SIGN_SMITH: hud_msg("karl, smith"); return 1;
        case T_BOARD: board_menu(); return 1;
        }
    } else if (s == TS_INDOOR) {
        switch (t) {
        case I_BED_TOP:
        case I_BED_BOT:
            if (room_id == R_HOUSE)
                sleep_now();
            else
                hud_msg("not your bed");
            return 1;
        case I_COUNTER:
            if (room_id == R_STORE) shop_menu();
            else smith_menu();
            return 1;
        case I_ANVIL:
        case I_FURNACE: smith_menu(); return 1;
        case I_CHEST: say(0, "an old chest. grandpa's things are in it."); return 1;
        }
    } else {
        switch (t) {
        case M_LIFT: lift_menu(); return 1;
        case M_LADDER:
            sfx(SFX_LADDER);
            ++floor_no;
            enter_room(R_MINE_A + floor_no % 3, 9, 9);
            return 1;
        }
    }
    return 0;
}

/* debris away from the farm: it comes back when the room is loaded again */
static unsigned char wild_action(unsigned char tx, unsigned char ty)
{
    static unsigned char t, it;
    if (!OUTDOOR(room[RM_SET]))
        return 0;
    t = tile_at(tx, ty);
    it = G.inv[sel];
    if (t == T_STONE && it == IT_PICK) {
        set_tile(tx, ty, T_GRASS);
        give(IT_STONE, 1);
        sfx(SFX_ROCK);
        return 1;
    }
    if (t == T_BRANCH && it == IT_AXE) {
        set_tile(tx, ty, T_GRASS);
        give(IT_WOOD, 1);
        sfx(SFX_CHOP);
        return 1;
    }
    if (t == T_WEEDS && it == IT_SWORD) {
        set_tile(tx, ty, T_GRASS);
        give(IT_FIBER, 1);
        sfx(SFX_SWING);
        return 1;
    }
    if ((flag_at(tx, ty) & F_WATER) && it == IT_CAN) {
        G.water = 20 + 20 * G.lvl[1];
        sfx(SFX_WATER);
        hud_msg("can is full");
        return 1;
    }
    return 0;
}

static void act(void)
{
    static unsigned char tx, ty, it, k, done;
    tx = target_x;
    ty = target_y;
    it = G.inv[sel];
    if (tx >= RW || ty >= RH)
        return;
    k = npc_at(tx, ty);
    if (k != 255) {
        npc_talk(k);
        return;
    }
    if ((flag_at(tx, ty) & F_USE) && use_tile(tx, ty))
        return;
    done = 0;
    if (farm_idx() != 255)
        done = farm_action(tx, ty);
    else if (floor_no)
        done = mine_action(tx, ty);
    if (!done)
        done = wild_action(tx, ty);
    if (it == IT_SWORD) {
        if (floor_no)
            mine_sword(tx, ty);
        if (!done)
            sfx(SFX_SWING);
        done = 1;
    }
    if (!done && item_food[it]) {
        /* food gives energy, and health: the mine has no other way */
        G.energy += item_food[it];
        if (G.energy > MAX_ENERGY)
            G.energy = MAX_ENERGY;
        G.hp += item_food[it];
        if (G.hp > MAX_HP)
            G.hp = MAX_HP;
        take(it, 1);
        sfx(SFX_EAT);
        hud_msg("yum!");
        return;
    }
    if (IS_TOOL(it)) {
        use_t = 12;
        if (it == IT_SWORD)
            effect(S_SLASH);
        else if (it == IT_CAN)
            effect(S_SPLASH);
        else
            effect(S_DUST);
    }
    hud_status();
}

/* ======================================================================
 * Time
 * ==================================================================== */

static unsigned int tick_frames;

static void new_quest(void)
{
    static unsigned char r;
    static const unsigned char pool[6] = { IT_WOOD, IT_STONE, IT_ORE_C, IT_FIBER, IT_ORE_I, IT_GEM };
    r = rnd();
    if ((r & 1) && G.season < 3) {
        /* one of this season's crops */
        G.quest_item = IT_PARSNIP + (G.season << 1) + ((r >> 1) & 1);
        G.quest_n = 3 + (r >> 6);
    } else {
        G.quest_item = pool[(r >> 1) % 6];
        G.quest_n = G.quest_item == IT_GEM ? 1 : 10 + (r >> 5);
    }
    G.quest_done = 0;
}

void new_day(unsigned char passed_out)
{
    static unsigned long paid;
    paid = G.ship;
    G.money += paid;
    G.earned += paid;
    G.ship = 0;
    if (passed_out)
        G.money -= G.money / 10;
    if (++G.day >= DAYS) {
        G.day = 0;
        if (++G.season >= 4) {
            /* the year is over: the reckoning, then the title again */
            year_end();
            game_over = 1;
            return;
        }
    }
    G.rain = G.season != 3 && rnd() < 56;
    farm_night();
    G.hour = 6;
    G.minute = 0;
    G.energy = passed_out ? MAX_ENERGY / 2 : MAX_ENERGY;
    G.hp = MAX_HP;
    G.talked = 0;
    G.gifted = 0;
    if (G.day % 7 == 0)
        new_quest();
    floor_no = 0;
    hurt = 0;
    day_report(paid);
    pdir = D_DOWN;
    enter_room(R_HOUSE, 5, 4);
}

static void clock(unsigned char n)
{
    tick_frames += n;
    if (tick_frames < TICK)
        return;
    tick_frames -= TICK;
    G.minute += 10;
    if (G.minute >= 60) {
        G.minute = 0;
        ++G.hour;
        set_palette();
        if (G.hour == 9 || G.hour == 19 || G.hour == 22)
            npc_enter();                    /* the villagers come and go */
    }
    hud_clock();
    if (G.hour >= 26) {
        say(0, "it is 2 am. you pass out from exhaustion...");
        new_day(1);
    }
}

unsigned char game_over;                    /* the year is over */

/* ======================================================================
 * The game
 * ==================================================================== */

static void new_game(void)
{
    static unsigned char k;
    memset(&G, 0, sizeof(G));
    G.magic = SAVE_MAGIC;
    G.year = 1;
    G.hour = 6;
    G.money = 500;
    G.energy = MAX_ENERGY;
    G.hp = MAX_HP;
    G.water = 20;
    for (k = 0; k < 5; ++k) {
        G.inv[k] = IT_HOE + k;
        G.cnt[k] = 1;
    }
    G.inv[5] = IT_S_PARSNIP;
    G.cnt[5] = 15;
    new_quest();
    farm_new();
}

static void faint(void)
{
    say(0, "you black out... someone carries you home.");
    new_day(1);
}

void main(void)
{
    static unsigned char last, n, k, e;

    eng_stack();                            /* see engine.s */

    dev = getcurrentdevice();
    if (dev < 8)
        dev = 8;
    eng_init();
    eng_blank();
    load_hud();
    eng_romfont();
    pal_hud[0] = 0x19;                      /* dark wood */
    pal_hud[1] = 0x00;
    pal_hud[2] = 0x58;
    menu = 1;
    music = SONG_FARM;
    eng_unblank();

    for (;;) {                              /* a game, and after it the next */
    k = title_menu();
    rs ^= frames | (frames << 8);           /* the time spent at the title */
    e = 0;
    if (k == 0 || !(e = load_game()))
        new_game();
    /* nothing of the last game's mine: no monsters at home */
    floor_no = 0;
    nmon = 0;
    hurt = 0;
    menu = 0;
    game_over = 0;
    pdir = D_DOWN;
    enter_room(R_HOUSE, 5, 4);
    if (k && !e)
        hud_msg("no saved game");

    last = frames;
    while (!game_over) {
        /* the logic runs while the last picture waits to be shown */
        n = frames - last;
        last += n;
        if (n > 6)
            n = 6;

        if (dbg_goto) {
            floor_no = dbg_floor;
            enter_room(dbg_goto - 1, dbg_x, dbg_y);
            dbg_goto = 0;
            continue;
        }

        e = read_keys();
        k = keys_now;

        /* slots: , and . or fire held with left/right (engine.s kpoll) */
        if (e & K_PREV) {
            sel = (sel - 1) & 15;
            row2 = sel & 8;
            hud_slots();
        }
        if (e & K_NEXT) {
            sel = (sel + 1) & 15;
            row2 = sel & 8;
            hud_slots();
        }
        if (e & K_MENU) {
            inventory_menu();
            continue;
        }

        /* the tile in front of the farmer */
        target_x = px;  target_x += 4;  target_x >>= 3;  target_x += dir_dx[pdir];
        target_y = py;  target_y += 13; target_y >>= 4; target_y += dir_dy[pdir];

        /* fire counts when it is let go, and not if a direction was
           pushed meanwhile (engine.s): it was another item then */
        if ((e & K_FIRE) && !use_t)
            act();

        if (use_t)
            use_t = use_t > n ? use_t - n : 0;
        else if (!(k & K_FIRE))
            walk(n, k);
        else
            moving = 0;
        if (fx_t)
            fx_t = fx_t > n ? fx_t - n : 0;
        /* after a blow the farmer blinks for a while - wherever he is: a
           count left standing outside the mine kept him invisible */
        if (hurt)
            hurt = hurt > n ? hurt - n : 0;

        if (hud_msg_time) {
            if (hud_msg_time > n)
                hud_msg_time -= n;
            else {
                hud_msg_time = 0;
                hud_clock();
                hud_status();
            }
        }

        if (floor_no) {
            mine_update(n);
            if (!G.hp) {
                faint();
                continue;
            }
        } else
            npc_update(n);
        clock(n);

        if (game_over)
            break;
        while (ready)
            ;
        draw();
        ++dbg_loops;
    }
    }
}
