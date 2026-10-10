/*
 * testmenu.c - the test build's menu: go anywhere
 *
 * Only in build/stardew-test.d64 (build.sh): right after the start, and
 * whenever fire is held and the stick pushed down, this menu goes to any
 * room - the farm, the village, the houses, the mountain, the mine's
 * entrance or any floor of the mine - at a season and hour of choice,
 * with a god mode that keeps health and energy full. The first time it
 * also fills the backpack: gold tools, seeds, sprinklers, food, ore, bars.
 *
 * It is not in the program: there is no room left in memory for it. It
 * is a file of its own, loaded over the map image at $E800 (stardew.cfg),
 * which is drawn afresh by the room it goes to.
 */
#include "game.h"

#pragma code-name ("TESTMENU")
#pragma rodata-name ("TESTMENU")
#pragma data-name ("TESTMENU")
#pragma bss-name ("TESTMENU")

#define N_PLACES 12
#define P_FLOOR 9                           /* the row with the floor number */

static const char *const names[N_PLACES] = {
    "farm, west", "farm, east", "farmhouse", "village", "upper village",
    "otto's store", "karl's smithy", "mountain", "mine entrance", "mine floor",
    "lena's house", "mara's house"
};
static const unsigned char ids[N_PLACES] = {
    R_FARM_W, R_FARM_E, R_HOUSE, R_TOWN, R_TOWN_N, R_STORE, R_SMITH,
    R_MOUNTAIN, R_MINE_TOP, R_MINE_A, R_LENA_HOUSE, R_MARA_HOUSE
};
static const unsigned char start_x[N_ROOMS] = ROOM_START_X;
static const unsigned char start_y[N_ROOMS] = ROOM_START_Y;
static const char *const seasons[4] = { "spring", "summer", "fall  ", "winter" };

/* the backpack for testing everything */
static const unsigned char kit_item[N_SLOTS] = {
    IT_HOE, IT_CAN, IT_AXE, IT_PICK, IT_SWORD, IT_S_PARSNIP, IT_S_CAULI,
    IT_SPRINKLER, IT_SALAD, IT_ORE_C, IT_ORE_I, IT_ORE_G, IT_BAR_C, IT_BAR_I,
    IT_BAR_G, IT_GEM
};

static unsigned char cur, fl, season, hour, god, k, row;

static void kit(void)
{
    for (k = 0; k < N_SLOTS; ++k) {
        G.inv[k] = kit_item[k];
        G.cnt[k] = IS_TOOL(kit_item[k]) ? 1 : 20;
    }
    for (k = 0; k < 5; ++k)
        G.lvl[k] = 3;                       /* gold */
    G.water = 80;
    G.money = 50000UL;
    test_kit = 1;
}

static unsigned char row_of(unsigned char c)
{
    return c < N_PLACES ? 4 + c : 17 + c - N_PLACES;
}

static void values(void)
{
    text(16, 4 + P_FLOOR, "<", C_GREY);
    num(18, 4 + P_FLOOR, fl, 2, C_YELLOW);
    text(21, 4 + P_FLOOR, ">", C_GREY);
    text(14, 17, "<", C_GREY);
    text(16, 17, seasons[season], C_YELLOW);
    text(23, 17, ">", C_GREY);
    text(14, 18, "<", C_GREY);
    num(16, 18, hour >= 24 ? hour - 24 : hour, 2, C_YELLOW);
    text(18, 18, ":00", C_YELLOW);
    text(23, 18, ">", C_GREY);
    text(14, 19, "<", C_GREY);
    text(16, 19, god ? "on " : "off", C_YELLOW);
    text(23, 19, ">", C_GREY);
}

void test_menu(void)
{
    if (!test_kit)
        kit();
    fl = floor_no ? floor_no : 1;
    season = G.season;
    hour = G.hour;
    god = test_god;
    cur = P_FLOOR;
    for (k = 0; k < N_PLACES; ++k)
        if (ids[k] == room_id)
            cur = k;
    menu_on();
    frame_box(1, 1, 38, 21);
    text(3, 2, "test: go anywhere", C_YELLOW);
    for (k = 0; k < N_PLACES; ++k)
        text(4, 4 + k, names[k], C_WHITE);
    text(4, 17, "season", C_WHITE);
    text(4, 18, "hour", C_WHITE);
    text(4, 19, "god mode", C_WHITE);
    text(26, 19, "no damage,", C_GREY);
    text(26, 20, "full energy", C_GREY);
    text(2, 22, "fire: go there   left/right: change", C_GREY);
    text(2, 23, "fire+up: back    fire+down: this menu", C_GREY);
    for (;;) {
        values();
        for (k = 0; k < N_PLACES + 3; ++k)
            put(2, row_of(k), k == cur ? H_SEL_L : ' ', C_WHITE);
        k = menu_key();
        if (k & K_MENU) {                   /* back where it was */
            dbg_floor = floor_no;
            dbg_x = (px + 4) >> 3;
            dbg_y = (py + 13) >> 4;
            dbg_goto = room_id + 1;
            break;
        }
        if (k & K_UP)
            cur = cur ? cur - 1 : N_PLACES + 2;
        if (k & K_DOWN)
            cur = cur < N_PLACES + 2 ? cur + 1 : 0;
        if (k & (K_LEFT | K_RIGHT)) {
            row = (k & K_RIGHT) ? 1 : 255;  /* +1 or -1 */
            if (cur == P_FLOOR) {
                fl += row;
                if (fl == 0) fl = 30;
                if (fl > 30) fl = 1;
            } else if (cur == N_PLACES) {
                season = (season + row) & 3;
            } else if (cur == N_PLACES + 1) {
                hour += row;
                if (hour < 6) hour = 25;
                if (hour > 25) hour = 6;
            } else if (cur == N_PLACES + 2) {
                god ^= 1;
            }
        }
        if ((k & K_FIRE) && cur < N_PLACES) {
            G.season = season;
            G.hour = hour;
            G.minute = 0;
            test_god = god;
            dbg_floor = 0;
            dbg_goto = ids[cur] + 1;
            if (cur == P_FLOOR) {           /* as the ladder chooses them */
                dbg_floor = fl;
                dbg_goto = R_MINE_A + fl % 3 + 1;
            }
            dbg_x = start_x[dbg_goto - 1];
            dbg_y = start_y[dbg_goto - 1];
            break;
        }
    }
    /* dark till the room is there: the map image is this menu now */
    eng_hide();
    menu = 0;
}
