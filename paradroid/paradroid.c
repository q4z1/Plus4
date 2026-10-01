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
        panel_status("Captured");
    } else {
        sound(SND_LOST);
        transfer_lost();
        panel_status("Mobile");
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
 * pixel pair with anything set is %11, the cell's own colour */
static void mc_font(void)
{
    static unsigned i;
    static unsigned char b, o;
    for (i = 0; i < POOL * 8; ++i) {
        b = tile_font[i];
        o = 0;
        if (b & 0xC0) o |= 0xC0;
        if (b & 0x30) o |= 0x30;
        if (b & 0x0C) o |= 0x0C;
        if (b & 0x03) o |= 0x03;
        MCFONT[i] = o;
    }
}

/* waiting for a game: a deck with its droids going about, no player */
static void title(void)
{
    static unsigned char t;
    hide_player = 1;
    player_dead = 0;
    t = 0;
    while (!(keys_irq & K_FIRE)) {
        if (t == 0)
            panel_status("Press fire");
        else if (t == 100)
            panel_status("Plus4 2026");
        if (++t == 200)
            t = 0;
        wait_tick();
        move_droids();
        doors();
        draw();
    }
    while (keys_irq & K_FIRE)
        wait_tick();
    hide_player = 0;
}

void main(void)
{
    eng_stack();
    eng_init();

    memcpy(FONT0, tile_font, POOL * 8);
    memcpy(FONT1, tile_font, POOL * 8);
    mc_font();
    memcpy(PANELF, panel_font, 2048);
    memcpy(BLKC, blk_code, 1024);
    colour_blocks();
    pictures_fixed();

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
