/*
 * game.h - what the parts of Stardew Pond share
 */
#ifndef GAME_H
#define GAME_H

#include "data.h"

/* ======================================================================
 * The engine (engine.s)
 * ==================================================================== */

extern volatile unsigned char frames;   /* pictures shown, 50 a second */
extern volatile unsigned char ready;    /* 1: the back picture is done  */
extern unsigned char back;              /* picture being drawn: 0 or 1  */
extern unsigned char menu;              /* 1: whole screen in menu mode */
extern unsigned char pal_map[4];        /* background, dark, light, border */
extern unsigned char pal_hud[3];        /* background, dark, light         */
extern unsigned char f_x, f_y, f_h, f_flip, f_col;
extern const unsigned char *f_src;
#pragma zpsym("f_src")
extern unsigned char put_code, put_attr;
extern unsigned char snd_time, pool_left;
extern unsigned char base_code[1024], base_attr[1024];

void eng_stack(void);
void eng_init(void);
void eng_blank(void);
void eng_hide(void);                        /* screen off, interrupt on */
void eng_show(void);
extern unsigned char scr_hidden;
void eng_unblank(void);
void eng_fill(void);
void __fastcall__ eng_put(unsigned off);
void eng_romfont(void);
void eng_reset(void);
void r_begin(void);
void r_fig(void);
void r_done(void);
unsigned char __fastcall__ key_row(unsigned char row);
unsigned char __fastcall__ joy(unsigned char sel);
extern volatile unsigned char keys_irq;   /* keys down now      */
unsigned char eng_keys(void);             /* keys gone down since */
extern unsigned char dbg_keys;            /* tests: keys as if pressed */
extern unsigned char music;               /* SONG_..., 0 = silence     */
extern unsigned char sfx_lo, sfx_hi, sfx_noise, sfx_len;
void eng_sfx(void);                       /* an effect on voice 2      */
extern unsigned char water_n;             /* rippling pairs of characters */
extern unsigned char water_ab[24];        /* left, right, lines (bits)    */
extern unsigned char water_ph[2];         /* their place in each set      */
extern unsigned char *unp_dst;            /* unpack.s: where to         */
void __fastcall__ unpack(const unsigned char *src);   /* exomizer's raw */

/* made by tools/mkdata.py (build/gen/sprites.s) */
extern const unsigned char *const spr_tab[];
extern const unsigned char spr_h[];
extern const unsigned char icon_code[][4];
extern const unsigned char icon_col[][4];

/* ======================================================================
 * Memory
 * ==================================================================== */

extern unsigned char mt_code[512];          /* [4][128] codes per quarter  */
extern unsigned char mt_attr[512];          /* [4][128] colours            */
extern unsigned char mt_flag[128];          /* what a tile is              */
#define MT_CODE mt_code
#define MT_ATTR mt_attr
#define MT_FLAG mt_flag
#define ATT0     ((unsigned char *)0xD000)  /* colours of picture 0        */
#define SCR0     ((unsigned char *)0xD400)  /* codes of picture 0          */
#define ATT1     ((unsigned char *)0xD800)
#define SCR1     ((unsigned char *)0xDC00)

#define TED_SOUND  (*(volatile unsigned char *)0xFF11)
#define TED_V1LO   (*(volatile unsigned char *)0xFF0E)
#define TED_V2LO   (*(volatile unsigned char *)0xFF0F)
#define TED_V2HI   (*(volatile unsigned char *)0xFF10)
#define TED_V1HI   (*(volatile unsigned char *)0xFF12)

/* tile flags (mkdata.py FLAGS) */
#define F_SOLID  1
#define F_WATER  2
#define F_TILL   4
#define F_SOIL   8
#define F_WET    16
#define F_DOOR   32
#define F_USE    64

/* ======================================================================
 * Rooms (world.c)
 * ==================================================================== */

#define RW 20                               /* tiles across */
#define RH 11                               /* tiles down   */
#define RM_SET    220                      /* TS_...: */
#define TS_FARM    0
#define TS_INDOOR  1
#define TS_MINE    2
#define TS_VILLAGE 3                        /* the farm's tiles, numbered alike */
#define OUTDOOR(s) ((s) == TS_FARM || (s) == TS_VILLAGE)
#define RM_PAL    221
#define RM_EXIT   225                       /* N S E W      */
#define RM_FLAGS  229
#define RM_DOORS  230                       /* 4 x (x y room x y) */
#define RF_FARM   1
#define RF_SEASON 2
#define RF_MINE   4
#define RF_INDOOR 8

extern unsigned char room[256];
extern unsigned char room_id;               /* R_..., or R_MINE_A.. in the mine */
extern unsigned char floor_no;              /* mine floor, 0 = not in the mine */
extern unsigned char dev;                   /* the disk drive */

unsigned char tile_at(unsigned char tx, unsigned char ty);
unsigned char flag_at(unsigned char tx, unsigned char ty);
void set_tile(unsigned char tx, unsigned char ty, unsigned char t);
void enter_room(unsigned char id, unsigned char tx, unsigned char ty);
void show_room(void);
void set_palette(void);
unsigned int __fastcall__ load_file(const char *name, void *addr);
void load_hud(void);
unsigned char save_game(void);
unsigned char load_game(void);

/* ======================================================================
 * Items
 * ==================================================================== */

enum {
    IT_NONE,
    IT_HOE, IT_CAN, IT_AXE, IT_PICK, IT_SWORD,
    IT_S_PARSNIP, IT_S_CAULI, IT_S_TOMATO, IT_S_MELON, IT_S_PUMPKIN, IT_S_EGGPLANT,
    IT_PARSNIP, IT_CAULI, IT_TOMATO, IT_MELON, IT_PUMPKIN, IT_EGGPLANT,
    IT_WOOD, IT_STONE, IT_FIBER,
    IT_ORE_C, IT_ORE_I, IT_ORE_G, IT_BAR_C, IT_BAR_I, IT_BAR_G,
    IT_GEM, IT_SPRINKLER, IT_SALAD, IT_SLIME,
    N_ITEMS
};
#define IS_TOOL(i)  ((unsigned char)((i) - 1) < 5)
#define IS_SEED(i)  ((unsigned char)((i) - IT_S_PARSNIP) < 6)
#define IS_CROP(i)  ((unsigned char)((i) - IT_PARSNIP) < 6)
#define N_SLOTS 16

extern const char *const item_name[N_ITEMS];
extern const unsigned char item_icon[N_ITEMS];
extern const unsigned int item_price[N_ITEMS];   /* what shipping pays */
extern const unsigned char item_food[N_ITEMS];   /* energy when eaten  */

unsigned char give(unsigned char item, unsigned char n);   /* 0: no room */
unsigned char count_of(unsigned char item);
void take(unsigned char item, unsigned char n);
unsigned char item_colour(unsigned char item);

/* ======================================================================
 * The game state: everything a save file holds ($0800, see stardew.cfg)
 * ==================================================================== */

#define SAVE_MAGIC 0x5E                    /* 0x5D: before the sum */
#define N_NPC 3

struct game {
    unsigned char magic;
    unsigned char day;              /* 0..27                           */
    unsigned char season;           /* 0 spring .. 3 winter            */
    unsigned char year;             /* 1..                             */
    unsigned char hour;             /* 6..25 (1 = 25, 2 = 26: bedtime) */
    unsigned char minute;           /* 0, 10, .. 50                    */
    unsigned long money;
    unsigned long ship;             /* in the bin, paid overnight      */
    unsigned long earned;           /* all money made so far           */
    unsigned char energy;           /* 0..MAX_ENERGY                   */
    unsigned char hp;               /* 0..MAX_HP                       */
    unsigned char water;            /* in the watering can             */
    unsigned char inv[N_SLOTS];
    unsigned char cnt[N_SLOTS];
    unsigned char lvl[5];           /* hoe, can, axe, pick, sword: 0..3 */
    unsigned char rain;             /* it rains today                  */
    unsigned char deepest;          /* deepest mine floor reached      */
    unsigned char friend[N_NPC];    /* 0..250                          */
    unsigned char talked;           /* bit per villager: talked today  */
    unsigned char gifted;           /* bit per villager: gift today    */
    unsigned char quest_item;       /* the notice board's request      */
    unsigned char quest_n;
    unsigned char quest_done;
    unsigned char quests;           /* requests fulfilled this year    */
    unsigned char shipped;          /* bit per crop kind ever sold     */
    unsigned char sum;              /* save_game: all bytes add up to 0 */
    unsigned char spare[13];
    unsigned char farm[2][256];     /* the two farm rooms as they are  */
    unsigned char crop[2][RW * RH]; /* crop kind 1..6 per tile         */
    unsigned char age[2][RW * RH];  /* days it has grown               */
};
extern struct game G;
extern unsigned char nmon;                  /* mine.c: monsters on this floor */

#define MAX_ENERGY 100
#define MAX_HP 100
#define DAYS 14                             /* a season; the game is one year */

/* ======================================================================
 * The farmer and the figures (stardew.c)
 * ==================================================================== */

enum { D_DOWN, D_UP, D_LEFT, D_RIGHT };

extern unsigned char px, py;                /* top left, multicolour pixels / lines */
extern unsigned char pdir;
extern unsigned char sel;                   /* selected slot */
extern unsigned char row2;                  /* 8: the toolbar shows slots 8..15 */
extern unsigned char hurt;                  /* frames the farmer blinks */

extern const signed char dir_dx[4], dir_dy[4];

extern unsigned char fa_x, fa_y, fa_s, fa_f, fa_c, nfig;
void fig_add(void);                         /* engine.s */
void figs_draw(void);
#define fig(x, y, s, f, c) \
    (fa_x = (x), fa_y = (y), fa_s = (s), fa_f = (f), fa_c = (c), fig_add())
void place_player(unsigned char tx, unsigned char ty);
extern unsigned char bk_x, bk_y;
unsigned char blocked_at(void);             /* engine.s */
#define blocked(x, y) (bk_x = (x), bk_y = (y), blocked_at())
unsigned char rnd(void);
void wait_frames(unsigned char n);
unsigned char fire_pressed(void);
void wait_fire(void);
unsigned char read_keys(void);
extern unsigned char keys_now;
void new_day(unsigned char passed_out);
void sfx(unsigned char kind);

enum { SFX_HOE, SFX_WATER, SFX_CHOP, SFX_ROCK, SFX_PICK, SFX_BUY, SFX_HIT,
       SFX_HURT, SFX_SWING, SFX_LADDER, SFX_BAD, SFX_EAT };

/* keys (read_keys) */
#define K_UP     1
#define K_DOWN   2
#define K_LEFT   4
#define K_RIGHT  8
#define K_FIRE   16
#define K_PREV   32
#define K_NEXT   64
#define K_MENU   128

/* ======================================================================
 * Farming (farm.c)
 * ==================================================================== */

extern const unsigned char crop_days[7];
extern const unsigned char crop_season[7];
extern const unsigned char crop_regrow[7];
extern const unsigned int seed_price[7];

unsigned char farm_idx(void);               /* 0/1 on the farm, 255 else */
unsigned char farm_action(unsigned char tx, unsigned char ty);
void farm_new(void);
void farm_night(void);
unsigned char crop_tile(unsigned char f, unsigned char i);

/* ======================================================================
 * Toolbar, text and menus (ui.c)
 * ==================================================================== */

#define C_WHITE  0x71
#define C_YELLOW 0x77
#define C_GREY   0x51
#define C_RED    0x52
#define C_GREEN  0x55
#define C_CYAN   0x63
/* multicolour cells (bit 3), for the frame's grain and the bars */
#define C_FRAME  0x3F
#define C_BAR_G  0x5D
#define C_BAR_Y  0x6F
#define C_BAR_R  0x4A

extern unsigned char hud_msg_time;

void text(unsigned char col, unsigned char row, const char *s, unsigned char c);
void text_both(unsigned char col, unsigned char row, const char *s, unsigned char c);
void num(unsigned char col, unsigned char row, unsigned long v,
         unsigned char width, unsigned char c);
void icon(unsigned char col, unsigned char row, unsigned char item);
void hud_all(void);
void hud_slots(void);
void hud_status(void);
void hud_msg(const char *s);
void hud_clock(void);
void say(const char *who, const char *s);
unsigned char ask(const char *s);
void menu_on(void);
void menu_off(void);
void clear_screen(void);
void frame_box(unsigned char x0, unsigned char y0, unsigned char x1, unsigned char y1);
void inventory_menu(void);
void shop_menu(void);
void smith_menu(void);
void lift_menu(void);
unsigned char title_menu(void);
void day_report(unsigned long paid);
void year_end(void);
extern unsigned long score;
extern unsigned char game_over;
void board_menu(void);

/* ======================================================================
 * Villagers (town.c) and the mine (mine.c)
 * ==================================================================== */

void npc_enter(void);
void npc_update(unsigned char n);
void npc_draw(void);
unsigned char npc_at(unsigned char tx, unsigned char ty);  /* 255: none */
void npc_talk(unsigned char k);
void keeper_talk(void);

void mine_enter(unsigned char fl);
void mine_update(unsigned char n);
void mine_draw(void);
unsigned char mine_action(unsigned char tx, unsigned char ty);
void mine_sword(unsigned char tx, unsigned char ty);

#endif
