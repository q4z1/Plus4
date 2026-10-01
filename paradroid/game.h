/*
 * game.h - what the parts of Paradroid share
 */
#ifndef GAME_H
#define GAME_H

#include "data.h"

/* ======================================================================
 * The engine (engine.s)
 * ==================================================================== */

extern volatile unsigned char frames, ready;
extern unsigned char back;
extern unsigned char e_m0, e_sx, e_blank7, e_cutrow, e_cutn, e_s;
extern signed char e_r;
extern signed char f_col, f_row;
extern unsigned char f_line, f_h;
extern const unsigned char *f_src;
extern const unsigned char *f_pre;
extern unsigned char *p_pre;
#pragma zpsym("f_src")
#pragma zpsym("f_pre")
#pragma zpsym("p_pre")
extern unsigned char col_deck, col_panel, col_fig1, col_fig2, col_border;
extern unsigned char f_tint;               /* r_fig: the cells' colour, 0 the deck's */
extern unsigned char bs_x, bs_y, bs_v;
extern unsigned pp_off;
extern unsigned char pp_code, pp_attr;
extern volatile unsigned char keys_irq;
extern unsigned char dbg_keys;
extern unsigned char pool_left;
extern unsigned char sfx_lo, sfx_hi, sfx_noise, sfx_len;
extern signed char sfx_d;
void sound(unsigned char n);            /* SND_..., droids.c */
#define SND_SHOT    0
#define SND_ESHOT   1
#define SND_BOOM    2
#define SND_HIT     3
#define SND_PULSE   4
#define SND_LIFT    5
#define SND_ENERGY  6
#define SND_TAKEN   7
#define SND_LOST    8
void eng_stack(void);
void eng_init(void);
void eng_show(void);
void eng_hide(void);
void pre_shift(void);
void r_begin(void);
void r_fig(void);
void r_done(void);
void blk_set(void);
void panel_put(void);
unsigned char eng_keys(void);
void eng_sfx(void);
void eng_dirty(void);
void eng_plain(void);

#define DMAP    ((unsigned char *)0x0400)
#define MCFONT  ((unsigned char *)0x0800)
#define FONT0   ((unsigned char *)0xC800)
#define FONT1   ((unsigned char *)0xD800)
#define PANELF  ((unsigned char *)0xE000)
#define BLKC    ((unsigned char *)0xE800)
#define BLKA    ((unsigned char *)0xEC00)

#define K_UP    1
#define K_DOWN  2
#define K_LEFT  4
#define K_RIGHT 8
#define K_FIRE  16
#define K_SPACE 32
#define K_STOP  64
#define K_DIRS  15

/* ======================================================================
 * The ship and the deck (deck.c)
 * ==================================================================== */

extern unsigned char deck;
extern unsigned char ship[NDECKS][12];  /* droid type + 1 per slot, 0 none */
extern unsigned char alert;             /* 0 green .. 3 red, by kills */
extern unsigned char deck_bg;
extern unsigned char level;             /* which ship of the fleet, from 1 */
extern unsigned char ndoor;

unsigned char rnd(void);
void new_ship(void);
void load_deck(unsigned char d);
void colour_blocks(void);
void deck_colours(void);                /* by alert, and dark if cleared */
unsigned char deck_cleared(unsigned char d);
unsigned char ship_cleared(void);
unsigned char blk_at(unsigned x, unsigned y);
#define solid_at(x, y) (blk_flag[blk_at(x, y)] & B_SOLID)
void doors(void);
unsigned char lift_here(void);           /* lift stop at the player, or 255 */
extern const unsigned char pal_deck[16];

/* ======================================================================
 * Droids, the player, shots (droids.c)
 * ==================================================================== */

#define MAXD 13                         /* droids on a deck, the player too */
#define MAXS 8                          /* shots */

extern unsigned char nd;                /* droids on this deck, 0 = player */
extern unsigned char d_type[MAXD];
extern unsigned d_x[MAXD], d_y[MAXD];   /* world pixels, the middle */
extern signed char d_vx[MAXD], d_vy[MAXD];
extern unsigned char d_energy[MAXD];
extern unsigned char d_boom[MAXD];      /* 0 alive, 1..12 exploding, 13 gone */
extern unsigned char d_bx[MAXD], d_by[MAXD];
#define PX d_x[0]
#define PY d_y[0]
#define BOOM_GONE 13

extern unsigned s_x[MAXS], s_y[MAXS];
extern unsigned char s_life[MAXS], s_img[MAXS];

extern unsigned long score;
extern unsigned char score_changed;
extern unsigned char transfer_mode;     /* fire held: touching a droid takes it */
extern unsigned char touched;           /* the droid touched in transfer mode */
extern unsigned char player_dead;

void spawn_droids(void);
void move_player(unsigned char k);
void move_droids(void);
void player_fire(unsigned char k);
void move_shots(void);
void droids_fire(void);
void collide(void);
void energy_tick(void);
unsigned char emax(unsigned char type);
void take_over(unsigned char i);
void remove_droid(unsigned char i);
void transfer_lost(void);
void burnt_out(void);
extern unsigned char burn, alert_acc, flash;

/* ======================================================================
 * Drawing (draw.c)
 * ==================================================================== */

#define SLOT_PLAYER 0
#define SLOT_DROID  1                   /* .. 9: droid types on the deck */
#define NSLOT_DROID 9
#define SLOT_EXPLO  10                  /* .. 15 */
#define SLOT_LASER  16                  /* .. 19: | / - \ */
#define SLOT_PANIM  20                  /* .. 22: the player's turning dome */
#define NSLOT       23

extern unsigned char slot_of[NDROIDS];
extern unsigned char tick;
extern unsigned char hide_player;

void pictures_fixed(void);
void pictures_deck(void);
void player_picture(void);
void draw(void);
void panel_init(void);
void panel_status(const char *s);
void panel_score(void);
void win_clear(unsigned char code, unsigned char attr);
extern unsigned char wp_row, wp_col, wp_code, wp_attr;
void win_put(void);
void win_letters(void);
void win_text(unsigned char line, unsigned char col, const char *s, unsigned char a);
const char *num_text(unsigned long v);   /* up to seven digits */
unsigned char panel_code(char ch);       /* a letter's code in the panel's set */
unsigned load_file(const char *name, void *addr);   /* paradroid.c: bytes loaded */
void picture(unsigned char t, unsigned char row, unsigned char col);  /* transfer.c */
void say(const char *s);                 /* transfer.c: at x_row, x_col */
extern unsigned char x_row, x_col, x_attr, x_code;  /* xfer.s */
extern unsigned char font_hi[2];          /* the window's character set */

#endif
