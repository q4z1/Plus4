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

/* ticks till none of the keys m is down */
static void __fastcall__ wait_free(unsigned char m)
{
    static unsigned char mm;
    mm = m;
    while (keys_irq & mm)
        wait_tick();
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
unsigned char ride_lift(unsigned char li);
unsigned char console_here(void);
unsigned char console_near(void);
void console_run(void);
static void console(void);
static void lift(unsigned char li);
extern unsigned char fl_kind;           /* fastload.s */
void fl_spin(void);

static void transfer(unsigned char i)
{
    static unsigned char won;
    while (ready)
        ;
    won = transfer_game(i);
    if (won) {
        sound(SFX_COMPLETE);
        take_over(i);
        panel_status("Complete");
    } else if (d_type[0]) {
        sound(SFX_REJECTED);
        transfer_lost();
        panel_status("Rejected");
    } else {
        panel_status("Burnt Out");
        sound(SFX_BURNT);
        burnt_out();
    }
    transfer_mode = 0;
    wait_free(K_FIRE);
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
    /* a deck between 4 and 7, as the original starts, on its first
     * waypoint (the droids start on the ones after) */
    k = 4 + (rnd() & 3);
    enter(k, 0, 0);
    i = wp_first[k];
    PX = wp_x[i] << 3;
    PY = wp_y[i] << 3;
    panel_score();
}

static unsigned char lights_out;         /* this deck went dark already */
void beam_in(void);

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

static unsigned char over;              /* a game has been played */

/* The pause, as the original's ($3B7C): RUN/STOP, and all stands still
 * and is quiet but the deck's turning characters, till fire or RUN/STOP.
 * In it, as its briefing says: CLR/HOME ends the game (1 back: straight
 * to the title); the C64's F7, HELP here, is "Cheese": not even those
 * turn, till its F8 (F7 here), fire or RUN/STOP. And, not in the
 * briefing, F1 for colours, F2 for black and white (the deck's scheme 0,
 * from the pause's end on). */
extern unsigned char snd_len[2];
#pragma zpsym ("snd_len")

static unsigned char pause(void)
{
    static unsigned char f;
    panel_status("Pause");
    snd_len[0] = snd_len[1] = 1;        /* (both voices off at once) */
    wait_free(K_STOP);
    while (!(keys_irq & (K_STOP | K_FIRE))) {
        wait_tick();
        f = pause_keys();
        if (f & 1)
            return 1;
        if ((f & 0x82) == 2) {
            panel_status("Cheese");
            while (!(keys_irq & (K_STOP | K_FIRE))
                   && !((f = pause_keys()) & 1) && (f & 0x82) != 0x82)
                ;
            panel_status("Pause");
        }
        if (f & 4) {
            bw = f & 0x80;
            panel_status(bw ? "Blk-White" : "Colour");
        }
        anim_deck();
    }
    wait_free(K_STOP | K_FIRE);
    deck_colours();
    panel_status("Continue");
    return 0;
}

static void play(void)
{
    static unsigned char k, held, li, by, t4;
    held = 0;
    by = 0;
    lights_out = deck_cleared(deck);
    for (;;) {
        wait_tick();
        k = keys_irq;
        if (k & K_STOP) {
            if (pause()) {
                over = 0;               /* (no end of a game shown) */
                return;
            }
            continue;
        }
        /* near a console: the drive's motor started already, so that the
         * pictures of the console's droid enquiry load without waiting the
         * two seconds for it; and kept going while the player stays near */
        if (fl_kind && !(++t4 & 3)) {
            if (!console_near())
                by = 0;
            else if (!by--) {
                fl_spin();
                by = 12;                /* again in 48 ticks */
            }
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
                lift(li);
                lights_out = deck_cleared(deck);
                held = 0;
                continue;
            }
            if (held == 2 && console_here()) {
                console();
                held = 0;
                by = 0;                 /* (the motor kept going) */
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
        sfx_tick();                     /* the original's own: hum, warning */
        move_player(k);
        move_droids();
        doors();
        /* figures against figures: the player where its figure is, a
         * character right of and below its place (draw.c), as the
         * original's sprites meet */
        fig_place(8);
        player_fire(k);
        droids_fire();
        move_shots();
        collide();
        fig_place(-8);
        if (transfer_mode && touched)
            transfer(touched);
        energy_tick();
        if (score_changed) {
            panel_score();
            if (!lights_out && deck_cleared(deck)) {
                lights_out = 1;
                score += 250;
                deck_colours();
                sound(SFX_CLEARED);
                panel_status(ship_cleared() ? "Fleet" : "Cleared");
                if (ship_cleared()) {
                    score += 2000;
                    next_ship();
                }
                panel_score();
            }
        }
        col_deck = flash ? 0x71 : deck_bg;  /* the disruptor's flash */
        anim_deck();                    /* the energizers turning */
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
void mc_font(void)
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

/* the day's top and worst scores, with initials (title.c shows them); the
 * original starts with these */
unsigned long top_score = 6809, low_score = 6502;

/* ======================================================================
 * The disk
 * ==================================================================== */

static unsigned char dev;               /* the drive the game came from */

/* The KERNAL needs its variables at $07D8-$07E7 to load, and the deck's
 * map is there (measured: the rest of $0400-$07FF may hold anything). They
 * are kept from the start and put back for each load. */
#define KVARS ((unsigned char *)0x07D8)
static unsigned char kvars[16];

/* a file from the disk to addr, with the fast loader (fastload.s) if the
 * drive has it. Else the KERNAL loads, and the screen is off meanwhile, as
 * it loads with its own interrupt handler; the deck's map is unpacked
 * again afterwards. With no disk the border goes red, and it tries
 * again. */
extern const char *fl_name;
extern void *fl_addr;
unsigned fl_load(void);
void fl_init(unsigned char dev);         /* fastinit.c */
void start_up(void);

unsigned load_file(const char *name, void *addr)
{
    static unsigned n;
    /* the fast loader: the picture and the game's interrupt go on; if
     * its drive code does not answer, the KERNAL from then on */
    fl_name = name;
    fl_addr = addr;
    while (fl_kind)
        if ((n = fl_load()) != 0)
            return n;
        else if (fl_kind)
            *(volatile unsigned char *)0xFF19 = 0x32;
    eng_hide();
    *(volatile unsigned char *)0xFF11 = 0;  /* sound off */
    memcpy(KVARS, kvars, sizeof kvars);
    while ((n = cbm_load(name, dev, addr)) == 0)
        *(volatile unsigned char *)0xFF19 = 0x32;
    memcpy(kvars, KVARS, sizeof kvars);
    load_deck(deck);
    mc_font();
    eng_show();
    return n;
}

/* ======================================================================
 * Waiting for a game
 * ==================================================================== */

/* The title and the briefing are an overlay (title.c), a file on the disk
 * that goes where the explosions' and lasers' pictures are: the title has
 * no use for them. So it is loaded for each title, and those pictures made
 * again for each game. */
extern unsigned char _OVL_START__[];
void title_run(void);

/* The console's and lift's overlay (console.c, lift.c): unpacked into
 * the pictures' slots, which are made again afterwards */
extern const unsigned char blob_con[];
extern unsigned char _CONOVL_START__[];

static void screens(void)
{
    unp_dst = _CONOVL_START__;
    unpack(blob_con);
}

static void slots_again(void)
{
    pictures_deck();
    pictures_fixed();
}

static void console(void)
{
    screens();
    console_run();
    slots_again();
}

static void lift(unsigned char li)
{
    screens();
    li = ride_lift(li);
    if (lift_deck[li] != deck)
        enter(lift_deck[li], lift_bx[li], lift_by[li]);
    slots_again();
    panel_status("Mobile");
}


/* after a game, as the original: a droid picked at random between
 * "Transmission" and "Terminated"; then the title loads */
#define SCR0A ((unsigned char *)0xC000)  /* the pictures' colours, codes */
#define SCR0C ((unsigned char *)0xC400)
#define SCR1A ((unsigned char *)0xD000)
#define SCR1C ((unsigned char *)0xD400)

static void terminated(void)
{
    static unsigned char cd, f;
    static unsigned off;
    while (ready)
        ;
    eng_plain();
    if (fl_kind)
        fl_spin();                      /* (the 999's picture loads after) */
    cd = col_deck;
    col_deck = pal_deck[1];
    /* first the static, as the original's ($378B): the window full of its
     * four noise characters at random, black on white, going round and
     * rolling down the window's lines, 52 steps in 1.2 seconds, with its
     * noise */
    memcpy(FONT1 + 250 * 8, anim_s, 4 * 8);
    font_hi[0] = 0xD8;                  /* (the deck shows the same in it) */
    for (off = 9 * 40; off < 1000; ++off) {
        SCR0C[off] = SCR1C[off] = 250 + (rnd() & 3);
        SCR0A[off] = SCR1A[off] = 0x00;
    }
    sound(SFX_STATIC);
    /* then the 999's picture, "Transmission terminated" and its tune: the
     * static goes on while the picture loads (picture(): pic_late), 1.2
     * seconds at least, as the original's (61 pictures) */
    roll = 1;
    pic_late = 1;
    pic_until = frames + 61;
    picture(23, 12, 16);
    x_attr = 0x63;                      /* the original's light cyan */
    x_row = 10;
    x_col = 13;
    say("Transmission");
    x_row = 22;
    x_col = 14;
    say("Terminated");
    sound(SFX_TERMINATED);
    for (f = 0; f < 70; ++f)            /* 4.2 seconds, as the original */
        wait_tick();
    page_end(cd);
}

/* a page in the window done with (here, title.c, transfer.c, console.c):
 * the window cleared, the deck's characters and colours back, the
 * window's colour cd */
void __fastcall__ page_end(unsigned char cd)
{
    while (ready)
        ;
    win_clear(0, 0x71);
    memcpy(FONT1, FONT0, POOL * 8);
    font_hi[0] = 0xC8;
    col_fig2 = 0x71;
    col_deck = cd;
}

static void title(void)
{
    if (over) {
        if (score > top_score)
            top_score = score;
        if (score < low_score)
            low_score = score;
    }
    hide_player = 1;
    player_dead = 0;
    if (over)
        terminated();
    else {
        /* the first time: an empty window while the title loads, not the
         * deck going on as if a game were running */
        while (ready)
            ;
        eng_plain();
        win_clear(0, 0x71);
        panel_status("Loading");
    }
    load_file("title", _OVL_START__);
    title_run();
    over = 1;
    hide_player = 0;
    pictures_fixed();
}

void main(void)
{
    dev = *(unsigned char *)0xAE;      /* the KERNAL's last device */
    memcpy(kvars, KVARS, sizeof kvars);
    if (dev < 8)
        dev = 8;
    eng_stack();
    fl_init(dev);                       /* (it needs the stack) */
    start_up();                         /* (fastinit.c) */

    new_game();
    draw();
    eng_show();
    last = frames;
    for (;;) {
        title();
        new_game();                     /* (the start page still up) */
        page_end(deck_bg);
        beam_in();                      /* (sfxcall.s) */
        last = frames;
        panel_status("Mobile");
        play();
        panel_status("Game over");
        wait_free(K_FIRE);
    }
}
