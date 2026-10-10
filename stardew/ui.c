/*
 * ui.c - the toolbar, text, conversations and the menus
 *
 * The toolbar is rows 23 and 24 and has a character set of its own
 * (engine.s switches to it in the black row 22). It holds the Plus/4's
 * capitals and digits from the ROM (codes 1..63) and the item icons
 * (tools/mkdata.py, data/hud.txt). A menu shows that character set on the
 * whole screen.
 *
 * Text in the toolbar and in menus is written into both pictures, since
 * it does not move and nothing is drawn over it.
 */
#include <string.h>
#include "game.h"

unsigned char hud_msg_time;

/* ----------------------------------------------------------------------
 * Text
 * -------------------------------------------------------------------- */

/* A character of a string to a screen code. cc65 turns source text into
   PETSCII: 'a' is $41, 'A' is $C1. The ROM's capitals are codes 1..26. */
static unsigned char scode(unsigned char c)
{
    if ((unsigned char)(c - 0x41) < 26)
        return c - 0x40;
    if ((unsigned char)(c - 0xC1) < 26)
        return c - 0xC0;
    return c & 0x3F;
}

static unsigned int cell(unsigned char col, unsigned char row)
{
    return (unsigned int)row * 40 + col;
}

void text(unsigned char col, unsigned char row, const char *s, unsigned char c)
{
    static unsigned int o;
    static const char *p;
    o = cell(col, row);
    for (p = s; *p; ++p, ++o) {
        SCR0[o] = SCR1[o] = scode(*p);
        ATT0[o] = ATT1[o] = c;
    }
}

void text_both(unsigned char col, unsigned char row, const char *s, unsigned char c)
{
    text(col, row, s, c);
}

/* text in a field of w characters, the rest blank: written over whatever
   was there in one go, never cleared first - a line that is cleared and
   written again flickers if the picture is shown in between */
static void textw(unsigned char col, unsigned char row, const char *s, unsigned char c,
                  unsigned char w)
{
    static unsigned int o;
    static const char *p;
    o = cell(col, row);
    for (p = s; w; --w, ++o) {
        SCR0[o] = SCR1[o] = *p ? scode(*p++) : ' ';
        ATT0[o] = ATT1[o] = c;
    }
}

static void put(unsigned char col, unsigned char row, unsigned char code, unsigned char c)
{
    static unsigned int o;
    o = cell(col, row);
    SCR0[o] = SCR1[o] = code;
    ATT0[o] = ATT1[o] = c;
}

static void fill(unsigned char col, unsigned char row, unsigned char n, unsigned char code,
                 unsigned char c)
{
    static unsigned int o;
    o = cell(col, row);
    for (; n; --n, ++o) {
        SCR0[o] = SCR1[o] = code;
        ATT0[o] = ATT1[o] = c;
    }
}

static char nbuf[12];

/* v right aligned in width characters */
void num(unsigned char col, unsigned char row, unsigned long v, unsigned char width,
         unsigned char c)
{
    static unsigned char k;
    static unsigned int w;
    k = 11;
    nbuf[11] = 0;
    if (v < 65536UL) {
        w = (unsigned int)v;
        do {
            nbuf[--k] = '0' + w % 10;
            w /= 10;
        } while (w);
    } else {
        do {
            nbuf[--k] = '0' + (unsigned char)(v % 10);
            v /= 10;
        } while (v);
    }
    while (11 - k < width)
        nbuf[--k] = ' ';
    text(col, row, nbuf + k, c);
}

static void num2(unsigned char col, unsigned char row, unsigned char v, unsigned char c)
{
    put(col, row, '0' + v / 10, c);
    put(col + 1, row, '0' + v % 10, c);
}

/* ----------------------------------------------------------------------
 * Items
 * -------------------------------------------------------------------- */

const char *const item_name[N_ITEMS] = {
    "", "hoe", "watering can", "axe", "pickaxe", "sword",
    "parsnip seeds", "cauli seeds", "tomato seeds", "melon seeds",
    "pumpkin seeds", "eggplant seeds",
    "parsnip", "cauliflower", "tomato", "melon", "pumpkin", "eggplant",
    "wood", "stone", "fiber",
    "copper ore", "iron ore", "gold ore", "copper bar", "iron bar", "gold bar",
    "amethyst", "sprinkler", "salad", "slime"
};

const unsigned char item_icon[N_ITEMS] = {
    0, IC_HOE, IC_CAN, IC_AXE, IC_PICK, IC_SWORD,
    IC_SEEDS, IC_SEEDS, IC_SEEDS, IC_SEEDS, IC_SEEDS, IC_SEEDS,
    IC_PARSNIP, IC_CAULI, IC_TOMATO, IC_MELON, IC_PUMPKIN, IC_EGGPLANT,
    IC_WOOD, IC_STONE, IC_FIBER,
    IC_ORE, IC_ORE, IC_ORE, IC_BAR, IC_BAR, IC_BAR,
    IC_GEM, IC_SPRINKLER, IC_FOOD, IC_SLIME
};

const unsigned int item_price[N_ITEMS] = {
    0, 0, 0, 0, 0, 0,
    10, 40, 25, 40, 50, 10,
    35, 175, 60, 250, 320, 60,
    2, 2, 1,
    5, 10, 25, 60, 120, 250,
    100, 50, 60, 5
};

const unsigned char item_food[N_ITEMS] = {
    0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0,
    15, 40, 15, 45, 50, 20,
    0, 0, 0,
    0, 0, 0, 0, 0, 0,
    0, 0, 50, 0
};

/* multicolour cells: colours 0..7 with bit 3 set */
static const unsigned char seed_col[6] = { 0x69, 0x79, 0x4A, 0x5D, 0x5F, 0x3C };
static const unsigned char metal_col[4] = { 0x39, 0x4A, 0x69, 0x6F };

unsigned char item_colour(unsigned char item)
{
    if (IS_SEED(item))
        return seed_col[item - IT_S_PARSNIP];
    if (IS_TOOL(item))
        return metal_col[G.lvl[item - 1]];
    switch (item) {
    case IT_ORE_C: case IT_BAR_C: return metal_col[1];
    case IT_ORE_I: case IT_BAR_I: return metal_col[2];
    case IT_ORE_G: case IT_BAR_G: return metal_col[3];
    }
    return 0;
}

void icon(unsigned char col, unsigned char row, unsigned char item)
{
    static unsigned char k, c;
    static const unsigned char *ic, *cc;
    if (!item) {
        fill(col, row, 2, ' ', 0);
        fill(col, row + 1, 2, ' ', 0);
        return;
    }
    k = item_icon[item];
    ic = icon_code[k];
    cc = icon_col[k];
    c = item_colour(item);
    put(col, row, ic[0], c ? c : cc[0]);
    put(col + 1, row, ic[1], c ? c : cc[1]);
    put(col, row + 1, ic[2], c ? c : cc[2]);
    put(col + 1, row + 1, ic[3], c ? c : cc[3]);
}

unsigned char give(unsigned char item, unsigned char n)
{
    static unsigned char k;
    for (k = 0; k < N_SLOTS; ++k)
        if (G.inv[k] == item && G.cnt[k] < 99) {
            G.cnt[k] += n;
            if (G.cnt[k] > 99)
                G.cnt[k] = 99;
            hud_slots();
            return 1;
        }
    for (k = 0; k < N_SLOTS; ++k)
        if (!G.inv[k]) {
            G.inv[k] = item;
            G.cnt[k] = n;
            hud_slots();
            return 1;
        }
    return 0;
}

unsigned char count_of(unsigned char item)
{
    static unsigned char k, n;
    n = 0;
    for (k = 0; k < N_SLOTS; ++k)
        if (G.inv[k] == item)
            n += G.cnt[k];
    return n;
}

void take(unsigned char item, unsigned char n)
{
    static unsigned char k;
    for (k = 0; k < N_SLOTS && n; ++k)
        if (G.inv[k] == item) {
            if (G.cnt[k] > n) {
                G.cnt[k] -= n;
                n = 0;
            } else {
                n -= G.cnt[k];
                G.cnt[k] = 0;
                G.inv[k] = 0;
            }
        }
    hud_slots();
}

/* ----------------------------------------------------------------------
 * The toolbar: row 22 black, row 23-24 slots on the left, clock, money
 * and energy on the right
 * -------------------------------------------------------------------- */

static const char *const season_name[4] = { "spr", "sum", "fal", "win" };

void hud_slots(void)
{
    static unsigned char k, c;
    if (menu)
        return;
    for (k = 0; k < 8; ++k) {
        c = 3 * k;
        put(c, 23, ' ', 0);
        put(c, 24, ' ', 0);
        icon(c + 1, 23, G.inv[row2 + k]);
    }
    put(24, 23, ' ', 0);
    put(24, 24, ' ', 0);
    c = 3 * (sel - row2);
    put(c, 23, H_SEL_L, C_WHITE);
    put(c + 3, 23, H_SEL_R, C_WHITE);
    hud_status();
}

void hud_clock(void)
{
    static unsigned char h;
    if (menu || hud_msg_time)
        return;
    fill(25, 23, 15, ' ', 0);
    if (floor_no) {
        text(25, 23, "floor", C_YELLOW);
        num(31, 23, floor_no, 2, C_YELLOW);
    } else {
        text(25, 23, season_name[G.season], C_YELLOW);
        num2(29, 23, G.day + 1, C_YELLOW);
    }
    h = G.hour;
    if (h >= 24)
        h -= 24;
    num2(34, 23, h, C_WHITE);
    put(36, 23, ':', C_WHITE);
    num2(37, 23, G.minute, C_WHITE);
    if (G.rain && !floor_no)
        put(32, 23, '*', C_CYAN);
}

/* a bar of five characters for v of 100: 0..20 pixels */
static void bar(unsigned char col, unsigned char row, unsigned char v)
{
    static unsigned char k, px, c;
    c = v > 50 ? C_BAR_G : v > 20 ? C_BAR_Y : C_BAR_R;
    px = v / 5;
    for (k = 0; k < 5; ++k, ++col) {
        if (px >= 4) {
            put(col, row, H_BAR4, c);
            px -= 4;
        } else {
            put(col, row, H_BAR0 + px, c);
            px = 0;
        }
    }
}

void hud_status(void)
{
    static unsigned char s;
    if (menu)
        return;
    fill(25, 24, 15, ' ', 0);
    s = G.inv[sel];
    if (hud_msg_time == 0 && s) {
        /* how many of the selected item */
        if (!IS_TOOL(s))
            num(25, 24, G.cnt[sel], 2, C_WHITE);
        else if (s == IT_CAN)
            num(25, 24, G.water, 2, C_CYAN);
    }
    if (floor_no) {
        put(28, 24, H_HEART, C_RED);
        bar(29, 24, G.hp);
    } else {
        put(28, 24, '$', C_YELLOW);
        num(29, 24, G.money, 5, C_YELLOW);
    }
    put(34, 24, 'e' - 0x40, G.energy < 20 ? C_RED : C_GREEN);
    bar(35, 24, G.energy);
}

/* a message in place of the clock, for two seconds */
void hud_msg(const char *s)
{
    if (menu)
        return;
    fill(25, 23, 15, ' ', 0);
    text(25, 23, s, C_WHITE);
    hud_msg_time = 100;
}

void hud_all(void)
{
    static unsigned char k;
    for (k = 0; k < 40; ++k) {
        put(k, 22, 0, 0x08);                /* the separator: %11, black */
    }
    fill(0, 23, 40, ' ', 0);
    fill(0, 24, 40, ' ', 0);
    hud_msg_time = 0;
    hud_slots();
    hud_clock();
}

/* ----------------------------------------------------------------------
 * Conversations, in the two toolbar rows
 * -------------------------------------------------------------------- */

void say(const char *who, const char *s)
{
    static const char *p, *brk;
    static unsigned char row, col, n, w;
    static char line[41];
    p = s;
    while (*p) {
        fill(0, 23, 40, ' ', 0);
        fill(0, 24, 40, ' ', 0);
        row = 23;
        col = 0;
        if (who) {
            text(0, 23, who, C_YELLOW);
            col = strlen(who) + 1;
        }
        while (*p && row <= 24) {
            /* as many words as fit */
            w = 40 - col;
            n = 0;
            brk = 0;
            while (p[n] && n < w) {
                if (p[n] == ' ')
                    brk = p + n;
                ++n;
            }
            if (p[n] && brk)
                n = brk - p;
            memcpy(line, p, n);
            line[n] = 0;
            text(col, row, line, C_WHITE);
            p += n;
            while (*p == ' ')
                ++p;
            ++row;
            col = 0;
        }
        wait_fire();
    }
    hud_all();
}

/* a question in the toolbar: yes or no, chosen with left and right (or
   up and down) and fire; fire+up or I says no at once */
unsigned char ask(const char *s)
{
    static unsigned char k, yes;
    fill(0, 23, 40, ' ', 0);
    fill(0, 24, 40, ' ', 0);
    text(0, 23, s, C_WHITE);
    yes = 1;
    for (;;) {
        put(1, 24, yes ? H_SEL_L : ' ', C_WHITE);
        text(3, 24, "yes", yes ? C_YELLOW : C_GREY);
        put(8, 24, yes ? ' ' : H_SEL_L, C_WHITE);
        text(10, 24, "no", yes ? C_GREY : C_YELLOW);
        do {
            wait_frames(1);
            k = read_keys();
        } while (!k);
        if (k & K_MENU) {
            yes = 0;
            break;
        }
        if (k & K_FIRE)
            break;
        if (k & 15)
            yes ^= 1;
    }
    hud_all();
    return yes;
}

/* ----------------------------------------------------------------------
 * Menus: the whole screen in toolbar characters
 * -------------------------------------------------------------------- */

void clear_screen(void)
{
    memset(SCR0, ' ', 1000);
    memset(SCR1, ' ', 1000);
    memset(ATT0, C_WHITE, 1000);
    memset(ATT1, C_WHITE, 1000);
}

/* A menu is drawn with the screen dark and shown whole when it waits
   for the first key (read_keys): drawing it in C takes a moment, and it
   would be seen growing line by line. */
void menu_on(void)
{
    while (ready)
        ;
    eng_hide();
    clear_screen();
    menu = 1;
}

void menu_off(void)
{
    menu = 0;
    eng_fill();
    hud_all();
}

void frame_box(unsigned char x0, unsigned char y0, unsigned char x1, unsigned char y1)
{
    static unsigned char y;
    put(x0, y0, H_FR_TL, C_FRAME);
    put(x1, y0, H_FR_TR, C_FRAME);
    put(x0, y1, H_FR_BL, C_FRAME);
    put(x1, y1, H_FR_BR, C_FRAME);
    fill(x0 + 1, y0, x1 - x0 - 1, H_FR_H, C_FRAME);
    fill(x0 + 1, y1, x1 - x0 - 1, H_FR_H, C_FRAME);
    for (y = y0 + 1; y < y1; ++y) {
        put(x0, y, H_FR_V, C_FRAME);
        put(x1, y, H_FR_V, C_FRAME);
    }
}

/* one key at a time: arrows, fire, the menu key */
/* one key at a time; a direction held down repeats after 0.4 s */
static unsigned char menu_key(void)
{
    static unsigned char k, rep;
    for (;;) {
        wait_frames(1);
        k = read_keys();
        if (k) {
            rep = 0;
            return k;
        }
        if (keys_now & 15) {
            if (++rep >= 20) {
                rep = 16;
                return keys_now & 15;
            }
        } else
            rep = 0;
    }
}

/* a line inside the box of frame_box(1, ., 38, .): not its frame */
static void clear_line(unsigned char row)
{
    fill(2, row, 36, ' ', C_WHITE);
}

/* ---- the inventory -------------------------------------------------- */

static const char *const npc_name[N_NPC] = { "lena", "tom", "mara" };

static void inv_draw(unsigned char cur, unsigned char held)
{
    static unsigned char k, x, y, it;
    for (k = 0; k < N_SLOTS; ++k) {
        x = 3 + (k & 7) * 4;
        y = 4 + (k >> 3) * 4;
        put(x - 1, y, k == cur ? H_SEL_L : ' ', C_WHITE);
        put(x + 2, y, k == cur ? H_SEL_R : ' ', C_WHITE);
        icon(x, y, G.inv[k]);
        it = G.inv[k];
        if (it && !IS_TOOL(it))
            num(x, y + 2, G.cnt[k], 2, C_GREY);
        else
            fill(x, y + 2, 2, ' ', 0);
    }
    clear_line(13);
    it = G.inv[cur];
    if (it) {
        text(3, 13, item_name[it], C_YELLOW);
        if (item_price[it]) {
            text(22, 13, "sells", C_GREY);
            num(28, 13, item_price[it], 4, C_WHITE);
            put(32, 13, 'g' - 0x40, C_WHITE);
        }
        if (IS_TOOL(it)) {
            text(22, 13, "level", C_GREY);
            num(28, 13, G.lvl[it - 1], 1, C_WHITE);
        }
    }
    clear_line(14);
    if (held) {
        text(3, 14, "moving:", C_GREY);
        text(11, 14, item_name[held], C_WHITE);
    }
}

void inventory_menu(void)
{
    static unsigned char cur, k, held, hn, i, t;
    menu_on();
    frame_box(1, 1, 38, 21);
    text(3, 2, "backpack", C_YELLOW);
    text(27, 2, "$", C_YELLOW);
    num(28, 2, G.money, 7, C_YELLOW);
    text(3, 16, "friends", C_YELLOW);
    for (i = 0; i < N_NPC; ++i) {
        text(3, 17 + i, npc_name[i], C_WHITE);
        for (k = 0; k < 5; ++k)
            put(9 + k, 17 + i, G.friend[i] >= (k + 1) * 50 ? H_HEART : H_HEART0, C_RED);
    }
    text(22, 17, "deepest floor", C_GREY);
    num(35, 17, G.deepest, 2, C_WHITE);
    text(22, 18, "earned", C_GREY);
    num(30, 18, G.earned, 7, C_WHITE);
    text(3, 22, "fire: move item   fire+up: close", C_GREY);
    cur = sel;
    held = 0;
    for (;;) {
        inv_draw(cur, held);
        k = menu_key();
        if (k & K_MENU)
            break;
        if (k & K_LEFT) cur = (cur - 1) & 15;
        if (k & K_RIGHT) cur = (cur + 1) & 15;
        if (k & (K_UP | K_DOWN)) cur ^= 8;
        if (k & K_FIRE) {
            if (!held) {
                if (G.inv[cur]) {
                    held = G.inv[cur];
                    hn = G.cnt[cur];
                    i = cur;
                    G.inv[cur] = 0;
                    G.cnt[cur] = 0;
                }
            } else {
                t = G.inv[cur];
                G.inv[i] = t;
                G.cnt[i] = G.cnt[cur];
                G.inv[cur] = held;
                G.cnt[cur] = hn;
                held = 0;
            }
        }
    }
    if (held) {                             /* put it back */
        G.inv[i] = held;
        G.cnt[i] = hn;
    }
    sel = cur;
    row2 = sel & 8;
    menu_off();
}

/* ---- the general store ---------------------------------------------- */

static unsigned char pay(unsigned int price)
{
    if (G.money < price) {
        sfx(SFX_BAD);
        return 0;
    }
    G.money -= price;
    sfx(SFX_BUY);
    return 1;
}

static void money_line(void)
{
    fill(26, 2, 12, ' ', 0);
    text(27, 2, "$", C_YELLOW);
    num(28, 2, G.money, 7, C_YELLOW);
}

/* one line of the shop's list, as wide as the box: what, how many, price */
static void shop_line(unsigned char row, unsigned char it, unsigned char n,
                      unsigned int price)
{
    textw(4, row, item_name[it], price ? C_WHITE : C_GREY, 18);
    if (n)
        num(22, row, n, 2, C_GREY);
    else
        fill(22, row, 2, ' ', 0);
    fill(24, row, 4, ' ', 0);
    if (price) {
        num(28, row, price, 5, C_YELLOW);
        put(33, row, 'g' - 0x40, C_YELLOW);
    } else
        fill(28, row, 6, ' ', 0);
}

static unsigned int buy_price(unsigned char it)
{
    return IS_SEED(it) ? seed_price[it - IT_S_PARSNIP + 1] : 120;
}

void shop_menu(void)
{
    static unsigned char buy[4], nb, cur, k, i, it, tab, row, n, redraw;
    menu_on();
    frame_box(1, 1, 38, 21);
    nb = 0;
    for (i = 1; i <= 6; ++i)
        if (crop_season[i] == G.season)
            buy[nb++] = IT_S_PARSNIP + i - 1;
    buy[nb++] = IT_SALAD;
    text(2, 22, "fire: trade  left/right: buy or sell", C_GREY);
    text(2, 23, "fire+up: leave the shop", C_GREY);
    cur = 0;
    tab = 0;
    redraw = 1;
    for (;;) {
        /* the whole list only when it is another one; after a trade the
           lines are written over, field by field */
        if (redraw == 1) {
            for (row = 3; row < 21; ++row)
                clear_line(row);
            textw(3, 2, tab ? "otto buys" : "otto sells", C_YELLOW, 12);
        }
        if (redraw) {
            if (!tab) {
                for (i = 0; i < nb; ++i) {
                    it = buy[i];
                    row = 4 + i * 3;
                    icon(4, row, it);
                    text(8, row, item_name[it], C_WHITE);
                    num(28, row, buy_price(it), 5, C_YELLOW);
                    put(33, row, 'g' - 0x40, C_YELLOW);
                }
            } else {
                for (i = 0; i < N_SLOTS && i < 17; ++i) {
                    it = G.inv[i];
                    n = it && item_price[it] ? G.cnt[i] : 0;
                    shop_line(3 + i, it, n, it ? item_price[it] : 0);
                }
            }
            redraw = 0;
        }
        money_line();
        /* the marker */
        if (!tab)
            for (i = 0; i < nb; ++i)
                put(2, 4 + i * 3, i == cur ? H_SEL_L : ' ', C_WHITE);
        else
            for (i = 0; i < N_SLOTS && i < 17; ++i)
                put(2, 3 + i, i == cur ? H_SEL_L : ' ', C_WHITE);
        k = menu_key();
        if (k & K_MENU)
            break;
        if (k & (K_LEFT | K_RIGHT)) {
            tab ^= 1;
            cur = 0;
            redraw = 1;
        }
        if (k & K_UP && cur)
            --cur;
        if (k & K_DOWN && cur < (tab ? N_SLOTS - 1 : nb - 1))
            ++cur;
        if (k & K_FIRE) {
            if (!tab) {
                it = buy[cur];
                if (pay(buy_price(it))) {
                    if (!give(it, 1)) {
                        G.money += buy_price(it);
                        sfx(SFX_BAD);
                    }
                }
            } else {
                it = G.inv[cur];
                if (it && item_price[it]) {
                    G.money += item_price[it];
                    G.earned += item_price[it];
                    if (IS_CROP(it))
                        G.shipped |= 1 << (it - IT_PARSNIP);
                    take(it, 1);
                    sfx(SFX_BUY);
                    redraw = 2;
                }
            }
        }
    }
    menu_off();
}

/* ---- the blacksmith ------------------------------------------------- */

static const char *const tool_word[5] = { "hoe", "can", "axe", "pickaxe", "sword" };
static const char *const metal_word[4] = { "", "copper", "iron", "gold" };
static const unsigned int upgrade_price[4] = { 0, 300, 1000, 3000 };
static const unsigned int smelt_price[3] = { 20, 50, 100 };

void smith_menu(void)
{
    static unsigned char cur, k, i, row, lv, bar, ok;
    static unsigned int price;
    menu_on();
    frame_box(1, 1, 38, 21);
    text(3, 2, "karl the smith", C_YELLOW);
    text(2, 22, "fire: order   fire+up: leave", C_GREY);
    cur = 0;
    for (;;) {
        money_line();
        /* 0..2 smelting, 3..7 tools, 8 sprinkler: written over, not
           cleared, so nothing flickers */
        for (i = 0; i < 3; ++i) {
            row = 4 + i;
            put(2, row, i == cur ? H_SEL_L : ' ', C_WHITE);
            text(4, row, "smelt 5", C_WHITE);
            text(12, row, item_name[IT_ORE_C + i], C_WHITE);
            num(23, row, count_of(IT_ORE_C + i), 3, C_GREY);
            num(28, row, smelt_price[i], 5, C_YELLOW);
            put(33, row, 'g' - 0x40, C_YELLOW);
        }
        for (i = 0; i < 5; ++i) {
            row = 8 + i;
            put(2, row, (i + 3) == cur ? H_SEL_L : ' ', C_WHITE);
            lv = G.lvl[i];
            if (lv >= 3) {
                textw(4, row, tool_word[i], C_GREY, 8);
                textw(12, row, "is gold", C_GREY, 23);
                continue;
            }
            textw(4, row, metal_word[lv + 1], C_WHITE, 7);
            textw(11, row, tool_word[i], C_WHITE, 8);
            text(19, row, "3 bars", C_GREY);
            num(28, row, upgrade_price[lv + 1], 5, C_YELLOW);
            put(33, row, 'g' - 0x40, C_YELLOW);
        }
        row = 14;
        put(2, row, cur == 8 ? H_SEL_L : ' ', C_WHITE);
        text(4, row, "sprinkler", C_WHITE);
        text(14, row, "cu+fe bar", C_GREY);
        num(28, row, 100, 5, C_YELLOW);
        put(33, row, 'g' - 0x40, C_YELLOW);
        text(4, 17, "bars:", C_GREY);
        num(10, 17, count_of(IT_BAR_C), 2, 0x4A & 0x77);
        text(13, 17, "cu", C_GREY);
        num(16, 17, count_of(IT_BAR_I), 2, C_WHITE);
        text(19, 17, "fe", C_GREY);
        num(22, 17, count_of(IT_BAR_G), 2, C_YELLOW);
        text(25, 17, "au", C_GREY);
        k = menu_key();
        if (k & K_MENU)
            break;
        if (k & K_UP && cur)
            --cur;
        if (k & K_DOWN && cur < 8)
            ++cur;
        if (!(k & K_FIRE))
            continue;
        ok = 0;
        if (cur < 3) {
            if (count_of(IT_ORE_C + cur) >= 5 && G.money >= smelt_price[cur]) {
                if (give(IT_BAR_C + cur, 1)) {
                    take(IT_ORE_C + cur, 5);
                    pay(smelt_price[cur]);
                    ok = 1;
                }
            }
        } else if (cur < 8) {
            i = cur - 3;
            lv = G.lvl[i];
            if (lv < 3) {
                bar = IT_BAR_C + lv;
                price = upgrade_price[lv + 1];
                if (count_of(bar) >= 3 && G.money >= price) {
                    take(bar, 3);
                    pay(price);
                    ++G.lvl[i];
                    ok = 1;
                }
            }
        } else {
            if (count_of(IT_BAR_C) && count_of(IT_BAR_I) && G.money >= 100) {
                if (give(IT_SPRINKLER, 1)) {
                    take(IT_BAR_C, 1);
                    take(IT_BAR_I, 1);
                    pay(100);
                    ok = 1;
                }
            }
        }
        if (!ok)
            sfx(SFX_BAD);
    }
    menu_off();
}

/* ---- the lift in the mine ------------------------------------------- */

void lift_menu(void)
{
    static unsigned char cur, n, k, i;
    n = G.deepest / 5 + 1;                  /* floors 1, 5, 10, ... */
    if (n > 7)
        n = 7;
    menu_on();
    frame_box(10, 4, 29, 18);
    text(12, 5, "the lift", C_YELLOW);
    text(12, 17, "fire+up: stay", C_GREY);
    cur = 0;
    for (;;) {
        for (i = 0; i < n; ++i) {
            put(13, 7 + i, i == cur ? H_SEL_L : ' ', C_WHITE);
            text(15, 7 + i, "floor", C_WHITE);
            num(21, 7 + i, i ? i * 5 : 1, 2, C_WHITE);
        }
        k = menu_key();
        if (k & K_MENU) {
            menu_off();
            return;
        }
        if (k & K_UP && cur)
            --cur;
        if (k & K_DOWN && cur < n - 1)
            ++cur;
        if (k & K_FIRE)
            break;
    }
    menu = 0;
    floor_no = cur ? cur * 5 : 1;
    sfx(SFX_LADDER);
    enter_room(R_MINE_A, 0, 0);
}

/* ---- the notice board ---------------------------------------------- */

void board_menu(void)
{
    static unsigned char k, have;
    static unsigned int reward;
    menu_on();
    frame_box(4, 3, 35, 18);
    text(6, 4, "notice board", C_YELLOW);
    reward = item_price[G.quest_item] * G.quest_n * 2;
    if (G.quest_done) {
        text(6, 7, "no requests this week.", C_WHITE);
        text(6, 8, "come back on monday!", C_WHITE);
    } else {
        text(6, 7, "wanted:", C_WHITE);
        num(14, 7, G.quest_n, 2, C_WHITE);
        text(17, 7, item_name[G.quest_item], C_WHITE);
        icon(30, 6, G.quest_item);
        text(6, 9, "reward:", C_WHITE);
        num(14, 9, reward, 5, C_YELLOW);
        put(19, 9, 'g' - 0x40, C_YELLOW);
        have = count_of(G.quest_item);
        text(6, 11, "you have", C_GREY);
        num(15, 11, have, 2, C_GREY);
        if (have >= G.quest_n) {
            text(6, 14, "fire: hand them over", C_GREEN);
        }
    }
    text(6, 17, "fire+up: back", C_GREY);
    for (;;) {
        k = menu_key();
        if (k & K_MENU)
            break;
        if ((k & K_FIRE) && !G.quest_done && count_of(G.quest_item) >= G.quest_n) {
            take(G.quest_item, G.quest_n);
            G.money += reward;
            G.earned += reward;
            G.quest_done = 1;
            ++G.quests;
            for (k = 0; k < N_NPC; ++k)
                if (G.friend[k] < 240)
                    G.friend[k] += 10;
            sfx(SFX_BUY);
            clear_line(14);
            text(6, 14, "thank you! the town", C_GREEN);
            text(6, 15, "likes you a bit more.", C_GREEN);
        }
    }
    menu_off();
}

/* ---- the morning ---------------------------------------------------- */

static const char *const season_long[4] = { "spring", "summer", "fall", "winter" };

void day_report(unsigned long paid)
{
    menu_on();
    frame_box(6, 4, 33, 18);
    text(9, 6, "day", C_YELLOW);
    num(13, 6, G.day + 1, 2, C_YELLOW);
    text(16, 6, "of", C_YELLOW);
    text(19, 6, season_long[G.season], C_YELLOW);
    text(9, 7, "year", C_GREY);
    num(14, 7, G.year, 2, C_GREY);
    text(9, 9, "shipped:", C_WHITE);
    num(18, 9, paid, 6, C_WHITE);
    put(24, 9, 'g' - 0x40, C_WHITE);
    text(9, 10, "money:", C_WHITE);
    num(18, 10, G.money, 6, C_YELLOW);
    put(24, 10, 'g' - 0x40, C_YELLOW);
    text(9, 12, G.rain ? "it is raining." : "the sun is out.", C_CYAN);
    if (G.season == 3 && G.day == DAYS - 1)
        text(9, 13, "the last day of the year!", C_YELLOW);
    text(9, 14, "saving ...", C_GREY);
    if (save_game())
        text(9, 14, "game saved.", C_GREY);
    else
        text(9, 14, "could not save!", C_RED);
    eng_unblank();
    text(9, 16, "press fire", C_WHITE);
    wait_fire();
    menu = 0;
}

/* ---- the end of the year: what it was worth -------------------------- */

unsigned long score;

static const char *const rank[5] = {
    "greenhorn", "farmhand", "farmer", "master farmer", "legend of the valley"
};

/* one line of the reckoning: what, how much of it, the points */
static void reckon(unsigned char row, const char *what, unsigned long n,
                   unsigned int each)
{
    static unsigned long p;
    p = n * each;
    score += p;
    text(5, row, what, C_WHITE);
    num(21, row, n, 6, C_GREY);
    num(29, row, p, 6, C_YELLOW);
}

void year_end(void)
{
    static unsigned char k, hearts, tools, kinds;
    hearts = 0;
    for (k = 0; k < N_NPC; ++k)
        hearts += G.friend[k] / 50;
    tools = 0;
    for (k = 0; k < 5; ++k)
        tools += G.lvl[k];
    kinds = 0;
    for (k = 0; k < 6; ++k)
        if (G.shipped & (1 << k))
            ++kinds;
    score = 0;
    menu_on();
    frame_box(2, 1, 37, 22);
    text(14, 2, "stardew pond", C_YELLOW);
    text(6, 3, "proof of concept in c, plus/4", C_GREY);
    text(5, 5, "the year is over.", C_WHITE);
    text(21, 7, "  what", C_GREY);
    text(29, 7, "points", C_GREY);
    reckon(8, "money earned", G.earned / 10, 1);
    text(27, 8, "0g", C_GREY);                  /* the tens left off */
    reckon(9, "hearts", hearts, 100);
    reckon(10, "deepest floor", G.deepest, 50);
    reckon(11, "tool upgrades", tools, 100);
    reckon(12, "requests", G.quests, 200);
    reckon(13, "crops shipped", kinds, 150);
    fill(29, 14, 6, H_FR_H, C_FRAME);
    text(5, 15, "score", C_YELLOW);
    num(28, 15, score, 7, C_YELLOW);
    k = 0;
    if (score >= 1500)
        k = 1;
    if (score >= 3500)
        k = 2;
    if (score >= 6000)
        k = 3;
    if (score >= 9000)
        k = 4;
    text(5, 17, "you are a", C_WHITE);
    text(15, 17, rank[k], C_GREEN);
    text(5, 19, "money", C_GREY);
    num(11, 19, G.money, 7, C_GREY);
    put(18, 19, 'g' - 0x40, C_GREY);
    text(5, 21, "press fire", C_WHITE);
    wait_fire();
}

/* ---- the title -------------------------------------------------------- */

unsigned char title_menu(void)
{
    static unsigned char cur, k, i, x;
    static const char logo[] = "stardew pond";
    static const unsigned char crops[6] = {
        IT_PARSNIP, IT_CAULI, IT_TOMATO, IT_MELON, IT_PUMPKIN, IT_EGGPLANT
    };
    menu_on();
    frame_box(1, 1, 38, 20);
    /* the name in big letters (tools/logo.py) */
    for (i = 0, x = 8; logo[i]; ++i, x += 2) {
        if (logo[i] == ' ')
            continue;
        k = IC_LOGO_S;
        switch (logo[i] & 0x7F) {
        case 'T' & 0x7F: k = IC_LOGO_T; break;
        case 'A' & 0x7F: k = IC_LOGO_A; break;
        case 'R' & 0x7F: k = IC_LOGO_R; break;
        case 'D' & 0x7F: k = IC_LOGO_D; break;
        case 'E' & 0x7F: k = IC_LOGO_E; break;
        case 'W' & 0x7F: k = IC_LOGO_W; break;
        case 'P' & 0x7F: k = IC_LOGO_P; break;
        case 'O' & 0x7F: k = IC_LOGO_O; break;
        case 'N' & 0x7F: k = IC_LOGO_N; break;
        }
        put(x, 3, icon_code[k][0], icon_col[k][0]);
        put(x + 1, 3, icon_code[k][1], icon_col[k][1]);
        put(x, 4, icon_code[k][2], icon_col[k][2]);
        put(x + 1, 4, icon_code[k][3], icon_col[k][3]);
    }
    text(10, 7, "after stardew valley", C_WHITE);
    text(9, 8, "by concernedape (2016)", C_GREY);
    for (i = 0; i < 6; ++i)
        icon(9 + i * 4, 10, crops[i]);
    text(5, 18, "a proof of concept in c for the", C_GREY);
    text(11, 19, "commodore plus/4", C_GREY);
    text(4, 22, "fire: use      fire+left/right: tool", C_GREY);
    text(4, 23, "fire+up: backpack, or out of a menu", C_GREY);
    text(4, 24, "(keys: cursor, space, , . and i)", C_GREY);
    cur = 0;
    for (;;) {
        put(13, 14, cur == 0 ? H_SEL_L : ' ', C_WHITE);
        text(15, 14, "new game", cur == 0 ? C_YELLOW : C_WHITE);
        put(13, 16, cur == 1 ? H_SEL_L : ' ', C_WHITE);
        text(15, 16, "continue", cur == 1 ? C_YELLOW : C_WHITE);
        k = menu_key();
        if (k & (K_UP | K_DOWN))
            cur ^= 1;
        if (k & K_FIRE)
            return cur;
    }
}
