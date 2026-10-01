/*
 * paradroid.c - Paradroid for the Plus/4: start, the game's course
 *
 * After Paradroid by Andrew Braybrook (Graftgold, published by Hewson,
 * 1985). The decks, their blocks and characters, the droid types, the
 * waypoints the droids walk and the lifts are the original's, taken from
 * its memory (tools/extract.py); the program around them is new.
 *
 * The game runs in ticks of three pictures, as the original does: 16.7 a
 * second. Everything moves once a tick and a new picture is drawn.
 *
 * Files:
 *   paradroid.c  (this file) start, the main loop
 *   deck.c       the ship, decks, doors
 *   lift.c       riding a lift
 *   console.c    the ship's computer
 *   transfer.c   the transfer game
 *   droids.c     the player, droids, shots, energy
 *   draw.c       the picture and the status panel
 *   engine.s     what has to be fast or on time
 */
#include <string.h>
#include <cbm.h>
#include "game.h"

unsigned ticks;                         /* for measuring: ticks done, */
unsigned late;                          /* and ticks that came too late */

static unsigned char last;              /* frames at the last tick */

/* wait for the next tick: one every three pictures; one that took longer
 * is made up by the next, unless it is far behind */
void wait_tick(void)
{
    if ((unsigned char)(frames - last) > 3)
        ++late;
    while ((unsigned char)(frames - last) < 3)
        ;
    last += 3;
    if ((unsigned char)(frames - last) > 6)
        last = frames;
    ++ticks;
    ++tick;
}

void enter(unsigned char d, unsigned char bx, unsigned char by)
{
    load_deck(d);
    spawn_droids();
    pictures_deck();
    deck_colours();
    PX = ((unsigned)bx << 5) + 16;
    PY = ((unsigned)by << 5) + 16;
    d_vx[0] = d_vy[0] = 0;
}

/* ======================================================================
 * Transfer
 * ==================================================================== */

unsigned char transfer_game(unsigned char i);
void ride_lift(unsigned char li);
void deck_plan(void);
unsigned char console_here(void);

static void transfer(unsigned char i)
{
    static unsigned char won;
    while (ready)
        ;
    won = transfer_game(i);
    if (won) {
        sound(SND_TAKEN);
        take_over(i);
        panel_status("Complete");
    } else if (d_type[0]) {
        sound(SND_LOST);
        transfer_lost();
        panel_status("Rejected");
    } else {
        panel_status("Burnt Out");
        burnt_out();
    }
    transfer_mode = 0;
    while (keys_irq & K_FIRE)
        wait_tick();
}

/* ======================================================================
 * A game
 * ==================================================================== */

static void new_game(void)
{
    static unsigned char k, i;
    level = 1;
    score = 0;
    alert = 0;
    player_dead = 0;
    new_ship();
    d_type[0] = 0;
    d_energy[0] = 64;
    burn = 64;
    alert_acc = 0;
    /* the first lift of a deck between 4 and 7, as the original starts */
    k = 4 + (rnd() & 3);
    for (i = 0; i < NLIFTS; ++i)
        if (lift_deck[i] == k)
            break;
    enter(k, lift_bx[i], lift_by[i]);
    panel_status("Mobile");
    panel_score();
}

static unsigned char lights_out;         /* this deck went dark already */

/* the ship is clear: on to the next of the fleet, droids a class higher */
static void next_ship(void)
{
    static unsigned char t;
    ++level;
    new_ship();
    for (t = 0; t < 50; ++t)
        wait_tick();
    lights_out = 0;
    spawn_droids();
    pictures_deck();
    deck_colours();
    panel_status("Mobile");
}

/* RUN/STOP: everything stands still until it is pressed again */
static void pause(void)
{
    panel_status("Pause");
    while (keys_irq & K_STOP)
        wait_tick();
    while (!(keys_irq & K_STOP))
        wait_tick();
    while (keys_irq & K_STOP)
        wait_tick();
    panel_status(transfer_mode ? "Transfer" : "Mobile");
}

static void play(void)
{
    static unsigned char k, held, li;
    held = 0;
    lights_out = deck_cleared(deck);
    for (;;) {
        wait_tick();
        k = keys_irq;
        if (k & K_STOP) {
            pause();
            continue;
        }
        if (player_dead) {
            if (d_boom[0] < BOOM_GONE)
                ++d_boom[0];
            else
                return;
            k = 0;
        }
        /* fire without a direction: a lift, or transfer */
        if ((k & K_FIRE) && !(k & K_DIRS)) {
            if (held < 255)
                ++held;
            if (held == 2 && (li = lift_here()) != 255) {
                ride_lift(li);
                lights_out = deck_cleared(deck);
                held = 0;
                continue;
            }
            if (held == 2 && console_here()) {
                deck_plan();
                held = 0;
                continue;
            }
            if (held == 3 && !transfer_mode) {
                transfer_mode = 1;
                panel_status("Transfer");
            }
        } else if (!(k & K_FIRE)) {
            held = 0;
            if (transfer_mode) {
                transfer_mode = 0;
                panel_status("Mobile");
            }
        }
        move_player(k);
        player_fire(k);
        move_droids();
        doors();
        droids_fire();
        move_shots();
        collide();
        if (transfer_mode && touched)
            transfer(touched);
        energy_tick();
        if (score_changed) {
            panel_score();
            if (!lights_out && deck_cleared(deck)) {
                lights_out = 1;
                score += 250;
                deck_colours();
                panel_status(ship_cleared() ? "Fleet" : "Cleared");
                if (ship_cleared()) {
                    score += 2000;
                    next_ship();
                }
                panel_score();
            }
        }
        col_deck = flash ? 0x71 : deck_bg;  /* the disruptor's flash */
        k = alert_acc >> 6;
        if (k != alert) {
            alert = k;
            deck_colours();
        }
        draw();
    }
}

/* the deck characters in multicolour, for the cells figures are in: a
 * pixel pair with anything set is %11, the cell's own colour. Made from
 * picture 0's character set, as the start-up copy is gone after a while. */
static void mc_font(void)
{
    static unsigned i;
    static unsigned char b, o;
    for (i = 0; i < POOL * 8; ++i) {
        b = FONT0[i];
        o = 0;
        if (b & 0xC0) o |= 0xC0;
        if (b & 0x30) o |= 0x30;
        if (b & 0x0C) o |= 0x0C;
        if (b & 0x03) o |= 0x03;
        MCFONT[i] = o;
    }
}

/* the best score since the machine was switched on */
static unsigned long best;

/* the title page: whose game this is, and the best score */
static void title_page(void)
{
    while (ready)
        ;
    win_letters();
    eng_plain();
    win_clear(0, 0x71);
    win_text(0, 14, "paradroid", 0x67);
    win_text(1, 9, "by andrew braybrook", 0x71);
    win_text(2, 7, "graftgold  hewson 1985", 0x71);
    win_text(4, 4, "plus4 version 2026 in c", 0x71);
    win_text(5, 10, "best", 0x71);
    win_text(5, 16, num_text(best), 0x67);
    win_text(7, 14, "press fire", 0x71);
}

/* ======================================================================
 * The disk
 * ==================================================================== */

static unsigned char dev;               /* the drive the game came from */

/* The KERNAL needs its variables at $07D8-$07E7 to load, and the deck's
 * map is there (measured: the rest of $0400-$07FF may hold anything). They
 * are kept from the start and put back for each load. */
#define KVARS ((unsigned char *)0x07D8)
static unsigned char kvars[16];

/* a file from the disk to addr. The screen is off meanwhile, as the KERNAL
 * loads with its own interrupt handler; the deck's map is unpacked again
 * afterwards. With no disk the border goes red, and it tries again. */
static void load_file(const char *name, void *addr)
{
    eng_hide();
    *(volatile unsigned char *)0xFF11 = 0;  /* sound off */
    memcpy(KVARS, kvars, sizeof kvars);
    while (!cbm_load(name, dev, addr))
        *(volatile unsigned char *)0xFF19 = 0x32;
    memcpy(kvars, KVARS, sizeof kvars);
    load_deck(deck);
    mc_font();
    eng_show();
}

/* ======================================================================
 * Waiting for a game
 * ==================================================================== */

/* The original's briefing, four pages, comes from the disk into the slots
 * of the explosions and lasers: the title has no use for them. So it is
 * loaded again for each title, and the slots made again for each game.
 * The file (tools/mkdata.py) starts with the characters it needs, as codes
 * of the panel's set, and its letters: letter k is character top[k] over
 * bot[k]. Then the pages. A page is drawn whole behind the file and rolled
 * up through the window a line of pixels at a time, the way the deck
 * scrolls: picture 1's character set holds the briefing's then, and both
 * pictures show it. */
#define BRIEF ((const unsigned char *)pre + SLOT_EXPLO * 512)
#define VS ((unsigned char *)pre + SLOT_EXPLO * 512 + BRIEF_SIZE)
static unsigned char brief_in;
static const unsigned char *b_top, *b_bot;  /* the letters */
static const unsigned char *b_first;        /* the first page */
static const unsigned char *bpage;          /* the page to show next */
static unsigned char b_h;                   /* its rows */

/* n pictures; 1 as soon as fire is pressed */
static unsigned char fire_in(unsigned n)
{
    static unsigned char f;
    while (n--) {
        f = frames;
        while (frames == f)
            ;
        if (keys_irq & K_FIRE)
            return 1;
    }
    return 0;
}

/* picture 0's character set for the window, or (0xD8) the briefing's in
 * picture 1's for both; changed just after a picture has begun, with the
 * window cleared */
static void window_font(unsigned char hi)
{
    static unsigned char k, n;
    static unsigned char f;
    while (ready)
        ;
    f = frames;
    while (frames == f)
        ;
    win_clear(0, 0x71);
    if (hi == 0xD8) {
        n = BRIEF[0];
        for (k = 0; k < n; ++k)
            memcpy(FONT1 + k * 8, PANELF + BRIEF[1 + k] * 8, 8);
    } else
        memcpy(FONT1, FONT0, POOL * 8);
    font_hi[0] = hi;
}

/* the page at bpage drawn whole into VS, 40 codes a row */
static void page_draw(void)
{
    static const unsigned char *p;
    static unsigned char *d;
    static unsigned char r, n, i, k;
    b_h = *bpage;
    p = bpage + 1;
    memset(VS, 0, b_h * 40);
    while ((r = *p) != 0xFF) {
        n = p[2];
        d = VS + r * 40 + p[1];
        for (i = 0; i < n; ++i) {
            k = p[3 + i];
            d[i] = b_top[k];
            d[i + 40] = b_bot[k];
        }
        p += 3 + n;
    }
    bpage = p[1] ? p + 1 : b_first;
}

/* the page rolled up by y pixels, into the back picture: as for the deck,
 * the rows move down by k lines and window row 0 shows its last k lines,
 * from copies of its characters with the rest cleared */
static void page_show(unsigned y)
{
    static unsigned char *d, *g, *o;
    static const unsigned char *src;
    static unsigned char k, w, rr, i, c, code;
    k = (unsigned char)-(unsigned char)y & 7;
    rr = (y + k) >> 3;                  /* the row in window row 1 */
    d = (unsigned char *)(back ? 0xD400 : 0xC400) + 7 * 40;
    memset(d, 0, 18 * 40);
    src = VS + (rr - 1) * 40;           /* window row 0's */
    if (k && rr)
        for (w = 0, code = back ? 198 : POOL; w < 40; ++w)
            if ((c = src[w]) != 0) {
                g = FONT1 + c * 8;
                o = FONT1 + code * 8;
                for (i = 0; i < 8; ++i)
                    o[i] = i < 8 - k ? 0 : g[i];
                d[w] = code++;
            }
    for (w = 1; w < 18 && rr < b_h; ++w, ++rr)
        memcpy(d += 40, src += 40, 40);
    e_sx = 0;
    e_cutrow = 0;
    e_s = k;
    r_done();
}

/* a page of the briefing, rolled up; 1 if fire ended it */
static unsigned char brief(void)
{
    static unsigned y, end;
    eng_plain();
    window_font(0xD8);
    page_draw();
    end = b_h * 8 > 136 ? b_h * 8 - 136 : 0;
    for (y = 0; ; ++y) {
        while (ready)
            ;
        page_show(y);
        if (fire_in(y == 0 || y == end ? 120 : 2))
            break;
        if (y == end)
            break;
    }
    while (ready)
        ;
    window_font(0xC8);
    return keys_irq & K_FIRE;
}

/* the deck and its droids going about, for n ticks; 1 if fire ended it */
static unsigned char attract(unsigned char n)
{
    eng_dirty();
    while (n--) {
        wait_tick();
        if (keys_irq & K_FIRE)
            return 1;
        move_droids();
        doors();
        draw();
    }
    return 0;
}

/* waiting for a game: the title page, a page of the briefing and the deck
 * with its droids, in turns */
static void title(void)
{
    if (score > best)
        best = score;
    hide_player = 1;
    player_dead = 0;
    if (!brief_in) {
        load_file("briefing", (void *)BRIEF);
        brief_in = 1;
        b_top = BRIEF + 2 + BRIEF[0];
        b_bot = b_top + b_top[-1];
        b_first = bpage = b_bot + b_top[-1];
    }
    panel_status("Press fire");
    for (;;) {
        title_page();
        if (fire_in(300) || brief() || attract(150))
            break;
    }
    while (keys_irq & K_FIRE)
        wait_tick();
    hide_player = 0;
    /* the explosions and lasers back where the briefing was */
    brief_in = 0;
    pictures_fixed();
}

void main(void)
{
    dev = *(unsigned char *)0xAE;      /* the KERNAL's last device */
    memcpy(kvars, KVARS, sizeof kvars);
    if (dev < 8)
        dev = 8;
    eng_stack();
    eng_init();

    memcpy(FONT0, tile_font, POOL * 8);
    memcpy(FONT1, tile_font, POOL * 8);
    mc_font();
    memcpy(PANELF, panel_font, 2048);
    memcpy(BLKC, blk_code, 1024);
    colour_blocks();

    col_panel = 0x71;
    col_border = 0x34;
    col_deck = 0x5D;
    col_fig1 = 0x00;
    col_fig2 = 0x71;
    panel_init();

    new_game();
    draw();
    eng_show();
    last = frames;
    for (;;) {
        title();
        new_game();
        play();
        panel_status("Game over");
        while (keys_irq & K_FIRE)
            wait_tick();
    }
}
