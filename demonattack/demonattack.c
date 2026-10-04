/*
 * Demon Attack for the Commodore Plus/4
 * =====================================
 *
 * A rebuild of Imagic's Demon Attack as the Atari 2600 plays it - not an
 * impression of it. The 2600 cartridge is 4 KB of 6502 code, and the game
 * logic below is that code, routine by routine, read out of a disassembly
 * and written down again in C. The comments name the address of the
 * routine each part comes from, so anyone can lay the two side by side.
 *
 * Three things the 2600 does in hardware have to be done in software here:
 *
 *   - Drawing. The 2600 races the beam: its "kernel" builds the picture line
 *     by line while the television draws it. The Plus/4 draws a whole
 *     picture into a character set of its own and shows it when it is done
 *     (engine.s). The picture is the same one: 160 pixels across, one
 *     2600 line on one Plus/4 raster line.
 *
 *   - Collisions. The 2600 reads them off the video chip. Here the kernel
 *     is walked line by line in kernel() and the pixels are compared, with
 *     the same timing quirks the real chip has.
 *
 *   - Sound. The 2600's two voices run through a translation onto the TED's
 *     two.
 *
 * Everything the game remembers lives in ram[], the 128 bytes of the 2600,
 * at the addresses it uses there ($80-$FF, which is also where it sits in
 * the Plus/4's zero page). The #defines below give each byte a name.
 */

#include <string.h>

/* ======================================================================
 * 1. The engine (engine.s)
 * ==================================================================== */

extern unsigned char ram[128];
#pragma zpsym("ram")
extern const unsigned char *o_src;
#pragma zpsym("o_src")
extern const unsigned char *o_mask;
#pragma zpsym("o_mask")

extern volatile unsigned char frames;   /* counts pictures           */
extern volatile unsigned char back;     /* picture being drawn: 0/1   */
extern volatile unsigned char ready;    /* 1: show it at the bottom   */
extern unsigned char ev_line[128], ev_reg[128], ev_val[128], ev_n;
extern unsigned char o_d0, o_n, o_cx, o_nc, o_x, o_col, o_flags;
extern unsigned char coldata[9 * 32];
extern unsigned char rev[256];
extern unsigned char r_row_attr[25];
extern unsigned char a_val, a_col, a_row;
extern unsigned char score_off[6];

void eng_init(void);
void eng_reset(void);
void r_begin(void);
void r_prep8(void);
void r_draw(void);
void r_attr(void);
void r_score(void);
unsigned char *__fastcall__ r_font_ptr(unsigned char buf);
unsigned char *__fastcall__ r_scr_ptr(unsigned char buf);
unsigned char *__fastcall__ r_att_ptr(unsigned char buf);

#define FRAME_LINE 206                   /* raster line of the picture swap */
#define RASTER(d) ((unsigned char)((d) + 4))  /* display line -> raster  */

#define R_BG     0x15
#define R_A      0x16                    /* colour of %01 pixels      */
#define R_B      0x17                    /* colour of %10 pixels      */
#define R_BORDER 0x19

/* Fixed character codes. Everything from 40 up is handed out per picture. */
#define CODE_GROUND  1
#define CODE_BUNKER  2
#define CODE_SOLID   3                   /* row 24: all %11              */
#define BAR_CODE     4                   /* 4..59: points (engine.s r_quad) */
#define SCORE_CODE   60                  /* 26 characters of score line  */
                                         /* 86..91: the cannon (engine.s) */

/* ======================================================================
 * 2. The Plus/4 around it
 * ==================================================================== */

#define TED_T1_LO    (*(volatile unsigned char *)0xFF0E)
#define TED_T2_LO    (*(volatile unsigned char *)0xFF0F)
#define TED_T2_HI    (*(volatile unsigned char *)0xFF10)
#define TED_SOUND    (*(volatile unsigned char *)0xFF11)
#define TED_T1_HI    (*(volatile unsigned char *)0xFF12)
#define KEY_LATCH    (*(volatile unsigned char *)0xFF08)
#define KEY_ROW      (*(volatile unsigned char *)0xFD30)

/* ======================================================================
 * 3. The original's tables
 *
 * $1D88-$1FFF of the cartridge verbatim: the cannon, the demons and their
 * explosions, digits, the IMAGIC logo, colour tables, sounds. The game
 * reaches into them with an offset from a fixed address, and in one place
 * with an offset it never meant to (see move_demons()), so they stay one
 * block and ROM(a) finds address a in it.
 * ==================================================================== */

const unsigned char rom_hi[0x278] = {
    /* $1D88 */ 0xC6, 0xC6, 0xC6, 0xC6, 0xEE, 0xEE, 0x6C, 0x6C, 0x28, 0x28, 0x28, 0x28, 0x00, 0x80, 0x01, 0x03,
    /* $1D98 */ 0x02, 0x80, 0x03, 0x80, 0x00, 0x28, 0x28, 0x38, 0x10, 0x10, 0x08, 0x06, 0x06, 0x03, 0x05, 0x04,
    /* $1DA8 */ 0x05, 0x04, 0x05, 0x04, 0x05, 0x04, 0x00, 0x00, 0x00, 0x01, 0x01, 0x03, 0x03, 0x00, 0x00, 0x00,
    /* $1DB8 */ 0x00, 0x01, 0x01, 0x03, 0xE7, 0xE2, 0xDD, 0xD8, 0xD3, 0xCE, 0xC9, 0xC4, 0x06, 0x03, 0x01, 0x00,
    /* $1DC8 */ 0x00, 0x06, 0x01, 0x04, 0x02, 0x00, 0x0A, 0x00, 0x02, 0x10, 0x04, 0x10, 0x02, 0x04, 0x40, 0x10,
    /* $1DD8 */ 0x00, 0x10, 0x82, 0x44, 0x00, 0x00, 0x40, 0x90, 0x02, 0x08, 0x40, 0x80, 0x08, 0x00, 0x24, 0x80,
    /* $1DE8 */ 0x00, 0x00, 0x00, 0x84, 0x8A, 0x6A, 0x4A, 0x7A, 0x9A, 0x80, 0xC0, 0xA0, 0xE0, 0xB0, 0xF0, 0x03,
    /* $1DF8 */ 0x04, 0x05, 0x05, 0x06, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    /* $1E08 */ 0x00, 0x88, 0x20, 0x08, 0x00, 0x02, 0x40, 0x10, 0x00, 0x40, 0x08, 0x40, 0x04, 0x00, 0x48, 0x02,
    /* $1E18 */ 0x00, 0x44, 0x00, 0x40, 0x04, 0x20, 0x09, 0x00, 0x00, 0x03, 0x07, 0x0E, 0x19, 0xF0, 0x02, 0x00,
    /* $1E28 */ 0x00, 0x06, 0x03, 0xCE, 0x71, 0x00, 0x04, 0x00, 0x00, 0x4C, 0x46, 0x23, 0x1F, 0x02, 0x01, 0x08,
    /* $1E38 */ 0x00, 0x10, 0x21, 0x22, 0x24, 0x14, 0x0F, 0x0C, 0x00, 0x40, 0x82, 0x84, 0x64, 0x1F, 0x06, 0x00,
    /* $1E48 */ 0x00, 0x44, 0x24, 0x14, 0x0F, 0x03, 0x00, 0x00, 0x00, 0x36, 0x1D, 0x02, 0x04, 0x0A, 0x04, 0x00,
    /* $1E58 */ 0x00, 0x09, 0x1E, 0x32, 0x24, 0x08, 0x0A, 0x00, 0x00, 0x02, 0x9F, 0xB2, 0xE4, 0x48, 0x10, 0x24,
    /* $1E68 */ 0x00, 0x9F, 0x8F, 0x87, 0x88, 0x90, 0x64, 0x00, 0x00, 0x4F, 0x98, 0x8C, 0x87, 0x88, 0x70, 0x04,
    /* $1E78 */ 0x00, 0x27, 0x4C, 0x98, 0x8C, 0x87, 0x48, 0x32, 0x00, 0x04, 0x44, 0x24, 0x23, 0x23, 0x14, 0x08,
    /* $1E88 */ 0x00, 0x20, 0x24, 0x28, 0x24, 0x23, 0x27, 0x18, 0x00, 0x10, 0x20, 0x48, 0x44, 0x42, 0x47, 0x3F,
    /* $1E98 */ 0x00, 0x00, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0x05, 0x03, 0x00, 0x00,
    /* $1EA8 */ 0x00, 0x00, 0x06, 0x09, 0x09, 0x09, 0x06, 0x00, 0x00, 0x20, 0x04, 0x11, 0x80, 0x14, 0x42, 0x90,
    /* $1EB8 */ 0x00, 0x40, 0x04, 0x12, 0xA0, 0x14, 0x40, 0x84, 0x00, 0x00, 0x20, 0x14, 0x68, 0x08, 0x14, 0x20,
    /* $1EC8 */ 0x00, 0x00, 0x00, 0x10, 0x28, 0x6C, 0xC6, 0x82, 0x00, 0x00, 0x82, 0x82, 0xD6, 0x6C, 0x00, 0x00,
    /* $1ED8 */ 0x00, 0x00, 0x44, 0x82, 0x82, 0xC6, 0x7C, 0x10, 0x80, 0x20, 0x10, 0x50, 0x41, 0x84, 0x88, 0x42,
    /* $1EE8 */ 0x40, 0x08, 0x04, 0x01, 0x81, 0x22, 0x11, 0x44, 0x40, 0x80, 0xC0, 0xF0, 0xF0, 0xC0, 0x80, 0x40,
    /* $1EF8 */ 0xFF, 0xC0, 0xA0, 0x80, 0x80, 0xA0, 0xC0, 0xFF, 0x7C, 0x64, 0x64, 0x64, 0x64, 0x64, 0x64, 0x64,
    /* $1F08 */ 0x7C, 0x00, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x38, 0x00, 0x7C, 0x4C, 0x4C, 0x40,
    /* $1F18 */ 0x3C, 0x0C, 0x4C, 0x4C, 0x7C, 0x00, 0x7C, 0x4C, 0x4C, 0x0C, 0x38, 0x0C, 0x4C, 0x4C, 0x7C, 0x00,
    /* $1F28 */ 0x0C, 0x0C, 0x7E, 0x4C, 0x4C, 0x4C, 0x4C, 0x4C, 0x4C, 0x00, 0x7C, 0x4C, 0x4C, 0x0C, 0x0C, 0x7C,
    /* $1F38 */ 0x40, 0x4C, 0x7C, 0x00, 0x7C, 0x4C, 0x4C, 0x4C, 0x7C, 0x40, 0x4C, 0x4C, 0x7C, 0x00, 0x30, 0x30,
    /* $1F48 */ 0x30, 0x18, 0x18, 0x0C, 0x4C, 0x4C, 0x7C, 0x00, 0x7C, 0x4C, 0x4C, 0x4C, 0x7C, 0x64, 0x64, 0x64,
    /* $1F58 */ 0x7C, 0x00, 0x7C, 0x4C, 0x4C, 0x0C, 0x7C, 0x4C, 0x4C, 0x4C, 0x7C, 0x00, 0x00, 0x00, 0x00, 0x00,
    /* $1F68 */ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3F, 0x40, 0x49, 0x89, 0x89, 0x89, 0x89, 0x48, 0x40, 0x3F,
    /* $1F78 */ 0xFF, 0x00, 0x54, 0x54, 0x57, 0x54, 0x54, 0xA3, 0x00, 0xFF, 0xFF, 0x00, 0x99, 0xA5, 0xAD, 0xA1,
    /* $1F88 */ 0xA5, 0x19, 0x00, 0xFF, 0xFC, 0x02, 0x32, 0x49, 0x41, 0x41, 0x49, 0x32, 0x02, 0xFC, 0x06, 0x07,
    /* $1F98 */ 0x08, 0x07, 0x06, 0x07, 0x06, 0x05, 0x04, 0x03, 0x04, 0x06, 0x01, 0x00, 0x02, 0x00, 0x03, 0x00,
    /* $1FA8 */ 0x04, 0x00, 0x05, 0x00, 0x06, 0x00, 0xC8, 0xC8, 0x88, 0x48, 0x38, 0x28, 0x76, 0x78, 0x0C, 0x0C,
    /* $1FB8 */ 0x8A, 0x7A, 0x6A, 0x5A, 0x4A, 0x3A, 0x48, 0x48, 0x48, 0x78, 0x88, 0x98, 0xA8, 0xB8, 0xC6, 0xC6,
    /* $1FC8 */ 0xC6, 0xC6, 0xEE, 0xEE, 0x6C, 0x6C, 0x46, 0x46, 0x46, 0x46, 0x3E, 0x3E, 0x9C, 0x9C, 0x86, 0x86,
    /* $1FD8 */ 0x48, 0x48, 0xE4, 0xE4, 0x28, 0x28, 0x38, 0x38, 0x48, 0x48, 0x68, 0x68, 0x78, 0x78, 0x10, 0x15,
    /* $1FE8 */ 0x20, 0x25, 0x30, 0x35, 0x15, 0x00, 0x00, 0x1A, 0x00, 0x00, 0x00, 0x1C, 0x17, 0x1A, 0x15, 0x17,
    /* $1FF8 */ 0x13, 0x15, 0x11, 0x00, 0x4A, 0x12, 0x4A, 0x12,
};

#define ROM(a) (rom_hi[(a) - 0x1D88])
#define ROMP(a) (rom_hi + ((a) - 0x1D88))

/* $1B9F: first animation frame of each demon kind, and on at $1BA7 the last */
static const unsigned char anim_lo[16] = {
    0x04, 0x07, 0x0A, 0x0D, 0x10, 0x13, 0x16, 0x19,
    0x06, 0x09, 0x0C, 0x0F, 0x12, 0x15, 0x18, 0x1B
};
#define anim_hi (anim_lo + 8)
static const unsigned char dive_dy[8] = { 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01, 0x01, 0x01 };  /* $1CB2 */
static const unsigned char dive_dx[8] = { 0x40, 0x80, 0xC0, 0xFF, 0xFF, 0xC0, 0x80, 0x40 };  /* $1CBA */
static const unsigned char cannon_colours[2] = { 0x56, 0xF8 };                              /* $1ACE */
static const unsigned char score_colours[2] = { 0x2C, 0x7A };                               /* $1AD0 */

/* The 2600's NTSC colours on the TED's, nearest by eye (a weighted RGB
   distance against VICE's YAPE palette). The TED has 121 colours; a colour
   cell in multicolour mode can only hold the first eight hues of them,
   hence the second table. */
/* NTSC colour (2600 value / 2) -> nearest TED colour */
const unsigned char ted_colour[128] = {
    0x00, 0x21, 0x41, 0x41, 0x51, 0x61, 0x61, 0x76, 0x17, 0x37, 0x47, 0x57, 0x57, 0x67, 0x67, 0x77,
    0x28, 0x38, 0x48, 0x48, 0x59, 0x59, 0x59, 0x69, 0x12, 0x38, 0x48, 0x48, 0x58, 0x58, 0x58, 0x68,
    0x02, 0x22, 0x32, 0x42, 0x42, 0x52, 0x52, 0x52, 0x14, 0x24, 0x34, 0x44, 0x44, 0x5B, 0x54, 0x54,
    0x04, 0x24, 0x34, 0x44, 0x44, 0x54, 0x54, 0x54, 0x0E, 0x1E, 0x2E, 0x3E, 0x4E, 0x4E, 0x5E, 0x5E,
    0x06, 0x16, 0x26, 0x36, 0x46, 0x46, 0x46, 0x56, 0x0D, 0x2D, 0x3D, 0x4D, 0x4D, 0x5D, 0x5D, 0x6D,
    0x0D, 0x2D, 0x3D, 0x43, 0x4D, 0x53, 0x63, 0x63, 0x03, 0x23, 0x33, 0x4C, 0x5C, 0x5C, 0x6C, 0x6C,
    0x0F, 0x25, 0x35, 0x45, 0x55, 0x55, 0x65, 0x65, 0x0A, 0x2A, 0x4F, 0x4F, 0x5F, 0x5F, 0x6F, 0x7F,
    0x07, 0x27, 0x47, 0x47, 0x57, 0x57, 0x67, 0x7A, 0x09, 0x38, 0x49, 0x49, 0x59, 0x59, 0x69, 0x69,
};
/* the same, but only hues 0-7 with the multicolour bit: for a colour cell */
const unsigned char ted_attr[128] = {
    0x08, 0x29, 0x49, 0x49, 0x59, 0x69, 0x69, 0x7E, 0x1F, 0x3F, 0x4F, 0x5F, 0x5F, 0x6F, 0x6F, 0x7F,
    0x1A, 0x3A, 0x4F, 0x4F, 0x5F, 0x5F, 0x6F, 0x6F, 0x1A, 0x3A, 0x3A, 0x4A, 0x4A, 0x5A, 0x5A, 0x6F,
    0x0A, 0x2A, 0x3A, 0x4A, 0x4A, 0x5A, 0x5A, 0x5A, 0x1C, 0x2C, 0x3C, 0x4C, 0x4C, 0x5C, 0x5C, 0x5C,
    0x0C, 0x2C, 0x3C, 0x4C, 0x4C, 0x5C, 0x5C, 0x5C, 0x0E, 0x1E, 0x2E, 0x3E, 0x4E, 0x4E, 0x5E, 0x5E,
    0x0E, 0x1E, 0x2E, 0x3E, 0x4E, 0x4E, 0x4E, 0x5E, 0x0E, 0x1E, 0x3E, 0x4E, 0x4E, 0x5B, 0x5B, 0x6B,
    0x0B, 0x3B, 0x3B, 0x4B, 0x5B, 0x5B, 0x6B, 0x6B, 0x0B, 0x2B, 0x3B, 0x4B, 0x5B, 0x5B, 0x6B, 0x6B,
    0x0D, 0x2D, 0x3D, 0x4D, 0x5D, 0x5D, 0x6D, 0x6D, 0x0D, 0x2D, 0x3D, 0x4D, 0x5D, 0x5D, 0x6F, 0x6D,
    0x0F, 0x2F, 0x4F, 0x4F, 0x5F, 0x5F, 0x6F, 0x6F, 0x0F, 0x2F, 0x4F, 0x4F, 0x5F, 0x5F, 0x6F, 0x6F,
};

/* ======================================================================
 * 4. The 2600's RAM
 * ==================================================================== */

#define wave12      ram[0x00]   /* $80 wave mod 12: which kind of demon    */
#define score_hi    (ram + 0x01) /* $81/$82 BCD, one byte per player       */
#define score_mid   (ram + 0x03) /* $83/$84                                */
#define score_lo    (ram + 0x05) /* $85/$86                                */
#define xacc        (ram + 0x07) /* $87-$89 sideways fractions per demon   */
#define racc        (ram + 0x0a) /* $8A-$8C right half while materialising */
#define pos0        (ram + 0x0d) /* $8D-$90 left halves; [3] is the cannon  */
#define pos1        (ram + 0x11) /* $91-$94 right halves; [3] is the shot or
                                    the diving demon or a piece of wreck   */
#define laser_y     ram[0x15]   /* $95 the cannon's shot, in kernel lines   */
#define laser_x     ram[0x16]   /* $96                                     */
#define spawn_slot  ram[0x17]   /* $97 demon being made; drawn four wide    */
#define low_limit   ram[0x18]   /* $98 how low the lowest demon may come    */
#define death       ram[0x19]   /* $99 counts the cannon's death down       */
#define drop_tick   ram[0x1a]   /* $9A frames until the shots drop a step   */
#define spawned     ram[0x1b]   /* $9B demons made this wave                */
#define flags       ram[0x1c]   /* $9C 7 splitting wave, 6 shot flying,
                                       0 reset switch last time            */
#define frame0      (ram + 0x1d) /* $9D-$A0 picture of each left half       */
#define frame1      (ram + 0x21) /* $A1-$A4 and of each right half          */
#define shots       (ram + 0x25) /* $A5-$AE the demons' shots, eight lines
                                    each, lowest first                      */
#define state       (ram + 0x2f) /* $AF-$B2 per demon, [3] the diver        */
#define diver_frame ram[0x33]   /* $B3                                     */
#define shots_left  ram[0x34]   /* $B4 pieces of shot still to come        */
#define snd         ram[0x35]   /* $B5 hi nibble voice 1, lo nibble voice 0 */
#define split       (ram + 0x36) /* $B6-$B8 7 split, 6 left, 5 right alive  */
#define frame_hi    ram[0x39]   /* $B9                                     */
#define lost_life   ram[0x3a]   /* $BA a bunker was lost this wave          */
#define spawn_timer ram[0x3b]   /* $BB                                     */
#define flash       ram[0x3c]   /* $BC background while the cannon blows up */
#define frame_lo    ram[0x3d]   /* $BD                                     */
#define wave        ram[0x3e]   /* $BE                                     */
#define t_bf        ram[0x3f]   /* $BF scratch, and the shot-hits-right-half
                                    collision                              */
#define ypos        (ram + 0x45) /* $C5-$C8 kernel line of each demon,
                                    [3] the diver                           */
#define yacc        (ram + 0x49) /* $C9-$CB                                 */
#define attract     ram[0x4c]   /* $CC                                     */
#define col_lo      ram[0x4d]   /* $CD this wave's colour table             */
#define shot_snd    ram[0x4f]   /* $CF                                     */
#define snd_idx     ram[0x50]   /* $D0                                     */
#define colmask     ram[0x51]   /* $D1 dims everything after long idling    */
#define score_col   ram[0x52]   /* $D2                                     */
#define cannon_col  ram[0x53]   /* $D3                                     */
#define bunker_col  ram[0x54]   /* $D4                                     */
#define rnd         ram[0x55]   /* $D5                                     */
#define m_linc      ram[0x56]   /* $D6-$DB how a new demon's halves fly in  */
#define m_rinc      ram[0x57]
#define m_lspd      ram[0x58]
#define m_lfrac     ram[0x59]
#define m_rspd      ram[0x5a]
#define m_rfrac     ram[0x5b]
#define t_dc        ram[0x5c]   /* $DC scratch, and a collision            */
#define digit_off(i) ram[0x5d + 2 * (i)] /* $DD.. the score's digits        */
#define sel_timer   ram[0x69]   /* $E9                                     */
#define game_no     ram[0x6a]   /* $EA BCD 1..10                            */
#define wave_flags  ram[0x6b]   /* $EB 7 no diver, 6 solid shots, 5 split,
                                       4 shots follow demon 2              */
#define flicker     ram[0x6c]   /* $EC                                     */
#define player      ram[0x6d]   /* $ED                                     */
#define laser_speed ram[0x6e]   /* $EE                                     */
#define diver_acc   ram[0x6f]   /* $EF                                     */
#define wave_idx    ram[0x70]   /* $F0 0..11, the row of the wave tables    */
#define game_on     ram[0x71]   /* $F1                                     */
#define lives       (ram + 0x72) /* $F2/$F3 spare bunkers                   */
#define award       ram[0x74]   /* $F4 a bunker being awarded              */
#define two_players ram[0x75]   /* $F5                                     */
#define tracer      ram[0x76]   /* $F6 7: the shot steers with the cannon   */
#define ground_col  ram[0x77]   /* $F7                                     */
#define coop        ram[0x78]   /* $F8 7: games 9 and 10, two at one cannon */
#define fire_prev   ram[0x79]   /* $F9                                     */

/* What the 2600 keeps in its video and sound chip. The shot's colour and
   the collision latches are shared with kernel.s (section 9). */
extern unsigned char colupf;
extern unsigned char cx_p0bl, cx_p1bl, cx_pp;
static unsigned char audc0, audf0, audv0, audc1, audf1, audv1;

/* Its inputs, active low as on the 2600. */
static unsigned char swcha = 0xFF;           /* hi nibble joystick 1     */
static unsigned char swchb = 0x0B;           /* switches; B difficulty    */
static unsigned char inpt4 = 0x80, inpt5 = 0x80;

/* The Y register, where the original relies on what it still holds. */
extern unsigned char yreg;

/* The demon a subroutine works on - the original's X. */
static unsigned char di;

/* Scratch for results on their way into an array: written straight into
   the element, cc65 would put the element's address on its stack first. */
static unsigned char tmp;

/* ======================================================================
 * 5. Small routines of the original
 * ==================================================================== */

/*
 * Horizontal positions are kept the way the 2600 needs them for its
 * positioning loop: low nibble = how many 15-pixel steps, high nibble = the
 * fine adjustment left or right. $1CCF moves such a position one pixel to
 * the right, $1CDE one pixel to the left.
 */
extern const unsigned char right_of[256];   /* $1CCF for every position */
extern const unsigned char left_of[256];    /* $1CDE, both in tables.s */
#define step_right(a) right_of[a]
#define step_left(a) left_of[a]

static unsigned char steps;

/* steps steps at once (0 = 256), leaving steps 0; in assembler, because
   the demons' moves call these a lot */
#pragma warn (unused-param, push, off)
static unsigned char __fastcall__ go_right(unsigned char a)
{
    __asm__("tax");
    __asm__("ldy %v", steps);
right:
    __asm__("lda %v,x", right_of);
    __asm__("tax");
    __asm__("dey");
    __asm__("bne %g", right);
    __asm__("sty %v", steps);
    __asm__("txa");
    __asm__("ldx #0");
    return __A__;
}

static unsigned char __fastcall__ go_left(unsigned char a)
{
    __asm__("tax");
    __asm__("ldy %v", steps);
left:
    __asm__("lda %v,x", left_of);
    __asm__("tax");
    __asm__("dey");
    __asm__("bne %g", left);
    __asm__("sty %v", steps);
    __asm__("txa");
    __asm__("ldx #0");
    return __A__;
}
#pragma warn (unused-param, pop)

static void hum_on(void)                                        /* $1BAF */
{
    snd = (snd & 0x0F) | 0x10;
}

static void diver_gone(void)                                    /* $1CC2 */
{
    state[3] = 0;
    diver_frame = 0;
    wave_flags |= 0x80;
}

static unsigned char any_shots(void)                            /* $1D31 */
{
    unsigned char x = 10;
    do {
        if (shots[--x]) return 1;
    } while (x);
    return 0;
}

/* $1D09: the line demon x drifts towards - midway between its neighbours. */
static unsigned char __fastcall__ target_y(unsigned char x)
{
    unsigned sum;
    if (x == 0) sum = 0x97 + ypos[1];
    else if (x == 1) sum = ypos[0] + ypos[2];
    else sum = ypos[1] + ((state[3] & 0x80) ? ypos[3] : low_limit);
    return (unsigned char)(sum >> 1);
}

/* $1D3D: point demon di (or the diver) at the cannon. Its position + 4 is
   compared with the cannon's in the positioning format: coarse steps first,
   and within the same coarse step by the fine value - which is only put in
   the right order on difficulty A. On B the demon gets it wrong half the
   time, and that is the whole difference the switch makes. */
static void __fastcall__ track(unsigned char a)
{
    unsigned char c, m;

    steps = 4;
    t_bf = a = go_right(a);
    t_dc = a & 0x0F;
    c = pos0[3] & 0x0F;
    if (c == t_dc) {
        m = (player ? (swchb & 0x80) : (swchb & 0x40)) ? 0x0F : 0xFF;
        t_dc = (unsigned char)((t_bf >> 4) + 8) ^ m;
        c = (unsigned char)((pos0[3] >> 4) + 8) ^ m;
    }
    if (c >= t_dc) state[di] = state[di] | 0x10;
    else state[di] = state[di] & 0xEF;
}

static void reset_laser(void)                                   /* $1CED */
{
    if (death) colupf = 0;
    laser_y = 3;
    flags &= 0xBF;
    laser_x = step_right(pos0[3]);
}

static void reset_positions(void)                               /* $1AA7 */
{
    pos0[3] = 5;
    laser_x = 0xF5;
    fire_prev = 0xF5;
    laser_y = 3;
    ypos[0] = 0x96;
    ypos[1] = 0x87;
    ypos[2] = 0x78;
    colupf = 0x6E;
    ground_col = 0x8C;
    colmask = 0xFF;
}

static void clear_game(void)                                    /* $1AD2 */
{
    attract = 0;
    memset(ram + 0x1d, 0, 0x20);                 /* $9D-$BC */
    game_on = 0xBD;
    lives[0] = lives[1] = 0;
}

/* Decimal mode, which C does not have. Valid BCD in, valid BCD out. */
static unsigned char bcd_c;
static unsigned char bcd_b;

static unsigned char __fastcall__ bcd_adc(unsigned char a)
{
    unsigned char lo = (a & 0x0F) + (bcd_b & 0x0F) + bcd_c;
    unsigned char hi = (a >> 4) + (bcd_b >> 4);
    if (lo > 9) { lo -= 10; ++hi; }
    if (hi > 9) { hi -= 10; bcd_c = 1; } else bcd_c = 0;
    return (unsigned char)((hi << 4) | lo);
}

/* $1A85: add a (units and tens) and x (hundreds) to player y's score. */
static void add_score(unsigned char a, unsigned char x, unsigned char y)
{
    bcd_c = 0; bcd_b = score_lo[y]; tmp = bcd_adc(a); score_lo[y] = tmp;
    a = x;
    if (bcd_c) { bcd_b = 0; a = bcd_adc(a); }
    bcd_c = 0; bcd_b = score_mid[y]; tmp = bcd_adc(a); score_mid[y] = tmp;
    a = bcd_c;
    bcd_c = 0; bcd_b = score_hi[y]; tmp = bcd_adc(a); score_hi[y] = tmp;
}

/* $1B7D: frames run base, +1, +2, +1, base ... - bit 5 of the state says
   which way. t_bf is the kind of demon, t_dc its state. */
static unsigned char __fastcall__ ping_pong(unsigned char y)
{
    unsigned char a;
    if (!(t_dc & 0x20)) {
        a = y + 1;
        if (a != anim_hi[t_bf]) return a;
    } else {
        a = y - 1;
        if (a != anim_lo[t_bf]) return a;
    }
    state[di] = t_dc ^ 0x20;                    /* $1B8C */
    return a;
}

/* $1B28: the next picture of demon di (3 = the diver), coming from a. */
static unsigned char __fastcall__ animate(unsigned char a)
{
    unsigned char dc;

    dc = t_dc = state[di];
    if (dc & 0x80) {
        if (dc & 0x40) {                        /* blowing up */
            --a;
            if (a == 0) {                       /* $1B52: gone */
                state[di] = dc & 0x3F;
                if (di == 3) diver_gone();
                hum_on();
                return 0;
            }
            if (a != 0x15) return a;
            /* A splitting demon's cloud has cleared: two halves fly on. */
            state[di] = (dc & 0x0F) | 0x80;
            split[di] = split[di] | 0xF0;
            hum_on();
            return 0x19;
        }
        t_bf = wave12 >> 1;                     /* $1B6F: alive */
        if (di == 3) t_bf = 7;
        return ping_pong(a);
    }
    if (dc & 0x40) {                            /* $1B65: materialising */
        ++a;
        return a == 4 ? 1 : a;
    }
    return a;
}

/* $1B03: the same for one half of a split demon. t_bf holds the mask that
   clears this half's "alive" bit. */
static unsigned char __fastcall__ animate_half(unsigned char a)
{
    if (a == 0) return 0;
    t_dc = state[di];
    if (a < 4) {
        --a;
        if (a) return a;
        split[di] = split[di] & t_bf;
        if (!(split[di] & 0x60)) {              /* $1B52: both halves gone */
            state[di] = t_dc & 0x3F;
            if (di == 3) diver_gone();
        }
        hum_on();                               /* $1B5F */
        return 0;
    }
    t_bf = 7;
    return ping_pong(a);
}

/* $1AE6: every piece of shot wanders a pixel left or right, at random,
   unless it would fall off its eight pixels. */
static void wobble_shots(void)
{
    unsigned char x, a, dc = rnd;

    x = 8;
    do {
        --x;
        a = shots[x];
        if (a) {
            if (dc & 0x80) {
                if (!(a & 0x01)) a >>= 1;
            } else {
                if (!(a & 0x80)) a <<= 1;
            }
            shots[x] = a;
            dc <<= 1;
        }
    } while (x);
}

/* $1BB8: the lowest demon is down to one half - it breaks off and dives.
   Everyone above moves down a slot to make room at the top. */
static void launch_diver(void)
{
    unsigned char x, y;

    y = pos0[2];
    x = frame0[2];
    if (x < 5) {
        x = frame1[2];
        y = pos1[2];
        if (x < 5) return;
    }
    pos1[3] = y;
    diver_frame = x;
    wave_flags &= 0x7F;
    ypos[3] = ypos[2];
    state[3] = state[2] & 0xF0;
    for (x = 2; x >= 1; --x) {
        state[x] = state[x - 1];
        pos0[x] = pos0[x - 1];
        pos1[x] = pos1[x - 1];
        frame0[x] = frame0[x - 1];
        frame1[x] = frame1[x - 1];
        ypos[x] = ypos[x - 1];
        split[x] = split[x - 1];
    }
    if (!(spawn_slot & 0x80)) ++spawn_slot;
    state[0] = 0;
    frame0[0] = 0;
    frame1[0] = 0;
    split[0] = 0;
    ypos[0] = 0x96;
}

/* $1C33: the lowest demon opens fire, or the diver moves on. */
static void shoot_or_dive(void)
{
    unsigned char a, y;

    if (death) return;
    if (!(state[3] & 0x80)) {
        if (frame0[2] < 4) return;
        if (rnd < 0xB0) return;
        steps = 4;
        a = go_right(pos0[2]);
        if (any_shots()) return;
        if (ypos[2] >= 0x50) return;
        pos1[3] = a;
        shots_left = (wave_flags & 0x40) ? 4 : (rnd & 7);
        drop_tick = 0;
        return;
    }
    if (state[3] & 0x40) return;                        /* $1C6E */
    a = state[3] & 7;
    if (a == 0) {
        di = 3;
        track(pos1[3]);
    }
    y = a;
    ypos[3] = ypos[3] + dive_dy[y];
    if (ypos[3] == 0) {
        diver_gone();
        return;
    }
    a = diver_acc;
    diver_acc += dive_dx[y];
    if (diver_acc >= a) return;                        /* no carry */
    if (state[3] & 0x10) a = step_right(pos1[3]);
    else {
        a = pos1[3];
        if (a != 0x71) a = step_left(a);
    }
    pos1[3] = a;
}

/* ======================================================================
 * 6. One frame of the original: sound ($1277)
 * ==================================================================== */

static void sound_frame(void)
{
    unsigned char a, x, y;

    x = 0;
    if (!(game_on & 0x80)) {
        snd = 0;
    } else if (death) {                         /* $12A7: the cannon blows */
        x = death >> 2;
        a = death & 0x1F;
        y = 8;
        goto ch0;
    }
    switch (snd & 0x0F) {
    case 1:                                     /* $12CC: materialising */
        x = 0x0C; a = spawn_timer; y = 8;
        break;
    case 2:                                     /* $12B2: the cannon fires */
        x = shot_snd << 1;
        a = (unsigned char)~shot_snd & 7;
        y = 0x0F;
        if ((signed char)--shot_snd < 0) {
            snd &= 0xF0;
            a = snd;
            x = 0;
        }
        break;
    default:
        x = 0; a = 0xD1; y = 0;
        break;
    }
ch0:
    audv0 = x; audc0 = y; audf0 = a;

    x = 0;
    if (award) {                                /* $131D: a bunker comes */
        a = --award;
        if (a == 0) {
            x = (coop & 0x80) ? 0 : player;
            ++lives[x];
            ++x;
            lost_life = x;
        }
        if (a < 0x3D) {
            bunker_col = ~a;
            y = a >> 2;
            a = ROM(0x1FEC + y);
            if (a) {
                y = a;
                x = (award & 3) << 2;
                a = y;
                y = 4;
            }
        }
        goto ch1;
    }
    switch (snd >> 4) {
    case 1:                                     /* $135C: the demons hum */
        a = (unsigned char)~frame_lo & 0x0F;
        if (a < 4) { a -= 4; y = 2; break; }
        x = a - 4;
        if (state[3] & 0x80) { a = ROM(0x1F96 + x); y = 4; }
        else if (frame_lo & 0x10) { x = 0; a = 0x10; y = 2; }
        else { a = 0x14 - spawned + ROM(0x1FA2 + x); y = 0x0C; }
        break;
    case 2:                                     /* $134F: a demon is hit */
        x = 8;
        a = ROM(0x1E00 + snd_idx) & 7;
        ++snd_idx;
        y = 0x0C;
        break;
    case 3:                                     /* $12F7: game over */
        a = --snd_idx;
        if (a == 0) {
            snd = 0;
            ground_col = 0x4C;
            a = 0x4C;
        } else {
            y = (a >> 2) & 1;                   /* the carry the tune keeps */
            x = a >> 3;
            ++ground_col;
            a = ROM(0x1E00 + snd_idx) & 7;
            audf0 = a;
            a += 5 + y;
            audv0 = x;
        }
        y = 0x0C;
        audc0 = y;
        break;
    default:
        a = 0x87; y = 0;
        break;
    }
ch1:
    audv1 = x; audc1 = y; audf1 = a;
}

/* ======================================================================
 * 7. One frame of the original: vertical blank ($138E)
 *
 * The frame counter, the console switches, starting a game - and then the
 * game itself, from $14DC, which the game select screen and the pause after
 * a game skip.
 * ==================================================================== */

static void start_wave(unsigned char from);
static void game_logic(void);

static void vblank(void)
{
    unsigned char a, x, y, c;

    if (++frame_lo == 0) {
        ++frame_hi;
        if (!(attract & 0x80)) {
            if (frame_hi == 0) colmask = 0xF3;
            if (two_players) player ^= 1;
            else if (coop & 0x80) player ^= 1;
        } else if (coop & 0x80) {
            player ^= 1;
        }
    }

    c = ((rnd >> 5) ^ (rnd >> 6)) & 1;          /* $13BC */
    rnd = (unsigned char)((rnd << 1) | c);

    /* $13C5: game reset starts a game when it is let go */
    if (!(flags & 1) && (swchb & 1)) goto start;
    flags = (flags & 0xFE) | (swchb & 1);

    /* game select: at once when pressed, then every 32 frames */
    if (swchb & 2) {
        sel_timer = (unsigned char)((sel_timer << 1) | 1);
    } else if ((sel_timer & 0x80) || !((sel_timer ^ frame_lo) & 0x1F)) {
        sel_timer = frame_lo & 0x1F;
        reset_positions();
        clear_game();
        a = game_no + 1;
        if ((a & 0x0F) == 0x0A) a += 6;
        game_no = (a == 0x11) ? 1 : a;
    }

    /* $1405: in the demo, fire starts a game when it is let go */
    if (!(attract & 0x80) && snd != 0x30) {
        a = inpt4;
        if (!(a & 0x80)) fire_prev = a;
        else if (!(fire_prev & 0x80)) goto start;
        else fire_prev = a;
    }
    goto running;

start:                                          /* $141C */
    game_on = 0xFF;
    attract = 0xFF;
    wave = 0xFF;
    x = 0;
    y = 0;
    coop = 0;
    a = game_no - 1;
    if (a < 8) {
        if (a & 1) y = 1;
        if (a & 2) x = 0xFF;
        if (a & 4) wave = 0x0B;
    } else {
        x = 0xFF;
        coop = 0xFF;
        if (a == 8) x = 0;
    }
    tracer = x;
    two_players = y;
    player = y;
    lives[0] = lives[1] = 3;
    start_wave(0x81);

running:
    game_logic();
}

/* $14DC: everything the game does in a frame before drawing it. */
static void game_logic(void)
{
    unsigned char a, x, y;

running:
    if ((game_on & 0x80) && !(attract & 0x80)) return;

    /* $14E7: one of the demons gets its next picture */
    x = ROM(0x1D94 + (frame_lo & 7));
    if (!(x & 0x80)) {
        di = x;
        if (x == 3) {
            diver_frame = a = animate(diver_frame);
        } else if (split[x] & 0x80) {
            a = frame0[x];
            if (a == frame1[x] && a >= 5) {
                { a = animate_half(a); frame0[x] = a; }
            } else {
                t_bf = 0xBF;
                { tmp = animate_half(a); frame0[x] = tmp; }
                t_bf = 0xDF;
                a = animate_half(frame1[x]);
            }
        } else {
            { a = animate(frame0[x]); frame0[x] = a; }
        }
        frame1[x] = a;
    }

    /* $1535: the cannon */
    if (!death) {
        if (!(state[3] & 0x80)) {
            a = split[2] & 0x60;
            if (a && a != 0x60 && !any_shots()) launch_diver();
        }
        if (!(game_on & 0x80)) {                /* the demo steers itself */
            x = (frame_lo & 0x40) ? 0x0A : 0x06;
        } else {
            a = swcha;
            if (player == 0) a >>= 4;
            x = a & 0x0F;
        }
        steps = (tracer & 0x80) ? 2 : 1;
        a = pos0[3];
        if (x < 8) {                            /* right */
            if (x < 5 || a == 0xC8 || a == 0xD8) goto fire;
            a = go_right(a);
        } else {                                /* left */
            if (x == 8 || x >= 12 || a == 0x31 || a == 0x21) goto fire;
            a = go_left(a);
        }
        pos0[3] = a;
        if ((tracer & 0x80) || !(flags & 0x40))
            laser_x = step_right(a);
    }

fire:                                           /* $15AB */
    if (flags & 0x40) {                         /* the shot climbs */
        laser_y += laser_speed;
        if (laser_y >= 0xA0) reset_laser();
    } else if (!death) {
        if (game_on & 0x80) {
            if ((player ? inpt5 : inpt4) & 0x80) goto spawn;
        }
        flags |= 0x40;                          /* fire */
        if (spawn_slot & 0x80) {
            snd = (snd & 0xF0) | 0x02;
            shot_snd = 7;
        }
    }

spawn:                                          /* $15E3 */
    if (spawn_timer == 0) {
        y = 0;
        x = 3;
        do {
            --x;
            if (!(state[x] & 0xC0)) {
                /* $161C: a free slot */
                if ((game_on & 0x80) && spawned == 8) goto occupied;
                spawn_timer = (rnd & 0x1F) | 1;
                { tmp = target_y(x); ypos[x] = tmp; }
                goto slot;
            }
            ++y;
occupied:       ;
        } while (x);
        x = 0xFF;
        if (y == 0) {
            /* the wave is empty and all eight have been */
            if (state[3] & 0x80) goto slot;
            if (death | award) goto drift;
            x = (coop & 0x80) ? 0 : player;
            if (lost_life == 0 && lives[x] < 6) {
                award = 0x48;
                goto slot;                      /* x is the player here */
            }
            start_wave(0x87);                   /* $145A: next wave */
            goto running_again;
        }
slot:
        spawn_slot = x;
    }

drift:                                          /* $1635 */
    a = frame_lo & 3;
    if (a) {
        x = di = a - 1;
        a = target_y(x);
        if (a < ypos[x]) {
            if (--ypos[x] == 0) ++ypos[x];
        } else {
            ++ypos[x];
        }
        if (x == 2) {
            track(pos0[2]);
            if ((flags & 0x40) && laser_y < ypos[2])
                state[x] = state[x] ^ 0x10;               /* dodge */
        } else if (!(rnd & 7)) {
            state[x] = state[x] ^ 0x10;
        }
    }
    shoot_or_dive();

    /* $166E: the halves of split demons fly apart */
    if (flags & 0x80) {
        x = 3;
        do {
            --x;
            if ((split[x] & 0x20) && (split[x] & 0x08)) {
                if (split[x] & 0x10) {
                    a = pos1[x];
                    if (a == 0xC9) goto turn;
                    { tmp = step_right(a); pos1[x] = tmp; }
                } else {
                    a = pos1[x];
                    if (a == 0x71) goto turn;
                    { tmp = step_left(a); pos1[x] = tmp; }
                }
                goto moved;
turn:           split[x] = split[x] ^ 0x10;
                state[x] = (state[x] & 0xF0) | 1;
moved:          split[x] = split[x] & 0xF7;
            }
        } while (x);
    }

    /* $16BA: keep the demons in their bands */
    t_dc = (state[3] & 0x80) ? (unsigned char)(ypos[3] + 12) : low_limit;
    a = ypos[0];
    if (a >= 0x97) a = 0x97;
    if (a < 0x48) a = 0x48;
    ypos[0] = a;
    a -= 12;
    if (a < ypos[1]) ypos[1] = a;
    a = ypos[1] - 12;
    if (a < ypos[2]) ypos[2] = a;
    if (ypos[2] < t_dc) ypos[2] = t_dc;

    /* $16F5: later waves aim their shots with the lowest demon */
    if ((wave_flags & 0x10) && !death && spawn_slot != 2 && !(state[3] & 0x80)) {
        steps = 4;
        { tmp = go_right(pos0[2]); pos1[3] = tmp; }
    }

    /* $1712: a demon is being made */
    x = spawn_slot;
    if (!(x & 0x80)) {
        if (spawn_timer) {
            if (--spawn_timer == 0) {
                if (state[x] & 0xC0) {
                    /* done: here it is */
                    state[x] = 0x90;
                    bunker_col = 0x4C;
                    snd = 0x10;
                    frame0[x] = frame1[x] = anim_lo[wave12 >> 1];
                    steps = 8;
                    { tmp = go_right(pos0[x]); pos1[x] = tmp; }
                    goto shots_fall;
                }
                /* $1747: start: two quad-wide halves fly in from the sides */
                ++spawned;
                state[x] = state[x] | 0x40;
                t_dc = (rnd & 0x7C) + 0x10;
                m_linc = t_dc >> 1;
                m_rinc = (unsigned char)(0xA0 - t_dc) >> 1;
                m_lspd = m_lfrac = m_rspd = m_rfrac = 0;
                split[x] = 0;
                pos0[x] = 0x70;
                pos1[x] = 0xA9;
                spawn_timer = 0x20;
                snd = (snd & 0xF0) | 0x01;
            }
        }
        if ((state[x] & 0xC0) == 0x40) {        /* $1783 */
            steps = m_lspd;
            a = xacc[x];
            xacc[x] = xacc[x] + m_lfrac;
            if (xacc[x] < a) ++steps;
            if (steps) { tmp = go_right(pos0[x]); pos0[x] = tmp; }
            steps = m_rspd;
            a = racc[x];
            racc[x] = racc[x] + m_rfrac;
            if (racc[x] < a) ++steps;
            if (steps) { tmp = go_left(pos1[x]); pos1[x] = tmp; }
            a = m_lfrac;
            m_lfrac += m_linc;
            if (m_lfrac < a) ++m_lspd;
            a = m_rfrac;
            m_rfrac += m_rinc;
            if (m_rfrac < a) ++m_rspd;
        }
    }

shots_fall:                                     /* $17CF */
    if (wave_flags & 0x80) {
        if (++drop_tick == ROM(0x1DA2 + wave_idx)) {
            wobble_shots();
            drop_tick = 0;
            memmove(shots, shots + 1, 9);
            x = ypos[2] >> 3;
            if (x >= 10) x = 9;
            if (shots_left == 0) {
                x = 9;
                a = 0;
            } else {
                --shots_left;
                if (wave_flags & 0x40) a = (split[2] & 0x80) ? 0x80 : 0x81;
                else a = ROM(0x1EE0 + (rnd & ((split[2] & 0x80) ? 0x03 : 0x0F)));
            }
            shots[x] = a;
        }
    }
    return;

running_again:
    /* the next wave was set up in the middle of this frame; the original
       carries on at $14DC with it */
    goto running;
}

/* $145A / $145C: clear RAM from $81 or $87 up and set up the next wave. */
static void start_wave(unsigned char from)
{
    unsigned char a, x;

    memset(ram + (from - 0x80), 0, 0xBD - from);
    if (!(coop & 0x80) && two_players) {
        x = player ^ 1;
        if (!(lives[x] & 0x80)) {
            player = x;
            if (x) goto same_wave;
        }
    }
    ++wave;
same_wave:
    a = wave;
    wave12 = a;
    if (a >= 12) {
        do a -= 12; while (a >= 12);
        wave12 = a;
        a = (a & 3) + 8;
    }
    wave_idx = a;
    x = a >> 1;
    low_limit = 0x2C - a - a;
    wave_flags = ROM(0x1DF1 + x);
    flags |= (wave_flags & 0x20) ? 0x81 : 0x01;
    flicker = (wave_flags & 0x40) ? 0 : 4;
    laser_speed = ROM(0x1DF7 + x);
    a = wave;
    while (a >= 7) a -= 7;
    col_lo = 0xAE + (a << 3);
    reset_positions();
}

/* $1822: the score line's six digits. */
static const unsigned char times10[16] = {
    0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130, 140, 150
};

static void score_digits(void)
{
    unsigned char i, hi, mid, lo;

    if ((game_on & 0x80) && !(attract & 0x40)) {
        hi = 0; mid = game_no; lo = 0xAA;       /* game select: the number */
    } else {
        hi = score_hi[player];
        mid = score_mid[player];
        lo = score_lo[player];
    }
    digit_off(0) = times10[hi >> 4];
    digit_off(1) = times10[hi & 0x0F];
    digit_off(2) = times10[mid >> 4];
    digit_off(3) = times10[mid & 0x0F];
    digit_off(4) = times10[lo >> 4];
    digit_off(5) = times10[lo & 0x0F];
    for (i = 0; i < 5 && digit_off(i) == 0; ++i)
        digit_off(i) = 0x64;                    /* leading zeros blank */

    cannon_col = (snd == 0x30) ? flash : cannon_colours[player];
    score_col = score_colours[player];
}

/* ======================================================================
 * 8. One frame of the original: overscan ($187A)
 * ==================================================================== */

static void overscan(void)
{
    unsigned char a, x, y;

    if (!(wave_flags & 0x80)) t_bf = cx_p1bl;

    y = yreg;
    if ((cx_pp & 0x80) && !(t_dc & 0x80)) {     /* the cannon is hit */
        death = 0x40;
        lost_life = 0x40;
        steps = 4;
        { tmp = go_left(pos0[3]); pos0[3] = tmp; }
        steps = 8;
        { tmp = go_right(pos0[3]); pos1[3] = tmp; }
        y = 0;
        shots_left = 0;
        state[3] = 0;
        wave_flags |= 0x80;
        if (!(flags & 0x40)) colupf = 0;
    }

    if (death) {
        if (--death == 0) {
            colupf = 0x6E;
            pos0[3] = 5;
            reset_laser();
            y = 0;
            if (game_on & 0x80) {
                x = player;
                if (coop & 0x80) {
                    y = player ^ 1;
                    add_score(0, 5, y);         /* the partner gets 500 */
                    x = 0;
                }
                if ((signed char)--lives[x] < 0) {
                    if (two_players) {
                        x ^= 1;
                        if (!(lives[x] & 0x80)) {
                            spawned = 8;        /* end the wave for the next */
                            state[0] = state[1] = state[2] = 0;
                            spawn_timer = 0;
                            state[3] = 0;
                            goto flashing;
                        }
                    }
                    /* $18FF: game over */
                    colupf = x;
                    cannon_col = x;
                    clear_game();
                    attract = 0x40;
                    snd = 0x30;
                    snd_idx = 0x78;
                    return;
                }
            }
        }
flashing:
        if (death >= 0x30) flash = death & 0x0F;
    }

    /* $191F: did the shot hit something? */
    if (!(flags & 0x40)) goto move;
    if (!((cx_p0bl | t_bf) & 0x40)) goto move;
    a = laser_y;
    if (a < 0x0D) goto move;
    a += 8;
    for (x = 0; a < ypos[x]; ) {
        if (++x == 4) goto move;
    }
    if (x == spawn_slot) goto move;
    a = 3;
    if (x == 3) {                               /* the diver */
        if (wave_flags & 0x80) goto move;
        if (a >= diver_frame) goto move;
        diver_frame = a;
        y = 4;
        t_dc = 4;
        goto blow_up;
    }
    if (split[x] & 0x80) {                      /* one half */
        y = 2;
        t_dc = 2;
        if (cx_p0bl & 0x40) {
            if (a >= frame0[x]) goto move;
            frame0[x] = a;
        } else {
            if (!(t_bf & 0x40)) goto move;
            if (a >= frame1[x]) goto move;
            frame1[x] = a;
        }
        goto scored;
    }
    y = 1;
    t_dc = 1;
    if (flags & 0x80) {                         /* it splits */
        a = 0x18;
        y = frame0[x];
        if (y >= 0x16) goto move;
    } else if (a >= frame0[x]) {
        goto move;
    }
    frame0[x] = frame1[x] = a;
blow_up:
    state[x] = (state[x] & 0x3F) | 0xC0;
scored:
    reset_laser();
    y = 0;
    if (game_on & 0x80) {
        y = wave_idx >> 1;
        a = 0;
        x = 0;
        do {
            bcd_c = 0;
            bcd_b = ROM(0x1FE6 + y);
            a = bcd_adc(a);
            if (bcd_c) ++x;
        } while (--t_dc);
        add_score(a, x, player);
        shots_left = 0;
        y = wave12;
        snd_idx = anim_lo[y] << 3;
        snd = (snd & 0x0F) | 0x20;
    }

move:                                           /* $19D6: the demons move */
    x = frame_lo & 3;
    t_dc = state[x] & 0xF0;
    state[x] = t_dc | ((state[x] + 1) & 0x0F);
    x = 3;
    do {
        --x;
        if ((state[x] & 0xC0) != 0x80) continue;
        if (!shots_left || x != 2) {
            /* up and down */
            y = state[x] & 7;
            a = yacc[x];
            yacc[x] = yacc[x] + ROM(0x1EF0 + y);
            if (yacc[x] < a) {
                if (state[x] & 0x08) ++ypos[x];
                else --ypos[x];
            }
        }
        /* sideways. The shooting demon skipped the line above, so y is
           whatever it last was - the original does the same, and reads its
           speed from wherever that points, even past the end of the table */
        t_dc = split[x];
        a = xacc[x];
        xacc[x] = xacc[x] + ROM(0x1EF8 + y);
        if (xacc[x] >= a) continue;
        if (t_dc & 0x80) {
            split[x] = split[x] | 0x08;
            if (!(t_dc & 0x40)) continue;
        }
        if (x == 2 && shots_left) continue;
        if (state[x] & 0x10) {
            a = pos0[x];
            if (a == 0x49) goto bounce;
            { tmp = step_right(a); pos0[x] = tmp; }
        } else {
            a = pos0[x];
            if (a == 0x71) goto bounce;
            { tmp = step_left(a); pos0[x] = tmp; }
        }
        goto halves;
bounce: state[x] = ((state[x] ^ 0x10) & 0xF0) | 1;
halves: if (split[x] == 0) {
            steps = 8;
            { tmp = go_right(pos0[x]); pos1[x] = tmp; }
        }
        y = 0;
    } while (x);
}

/* ======================================================================
 * 9. The kernel: what the 2600 shows, and what collides
 *
 * The 2600 draws the picture in three bands, and a kernel line is known by
 * a counter x that runs from 165 at the top down to 0 above the ground:
 *
 *   - the score, nine lines;
 *   - the demons: for each of the three, three lines to position its two
 *     halves, then its eight lines at x = ypos .. ypos+7. Display line
 *     180 - x here;
 *   - below the last demon, three more positioning lines, then the cannon's
 *     band down to x = 0: the cannon, the laser or diver, the wreck when it
 *     blows up. Display line 183 - x here - the three extra lines.
 *
 * The shot (the 2600's "ball") is switched on and off by a write in each
 * line - but not at the start of it. Where the write lands depends on how
 * much the kernel did before it in that line, and pixels left of that
 * point still show the ball as the line before had it. The same goes for
 * the demons' laser shots, whose shape is written even later. Both change
 * which lines show what, by one, at some positions - and so change when
 * things collide. The pixel for every kind of line is the cycle of the
 * write, times three, less the 68 pixels of horizontal blanking.
 *
 * All that is kernel.s: it runs every frame and has to be quick. Written in
 * C first, it took five frames' worth of time for one; the C version was
 * what it was checked against the original with, the assembly is the same
 * thing line for line and passes the same check.
 * ==================================================================== */

void kernel_asm(void);

extern const unsigned char pixtab[256];  /* pixel of a position byte     */
unsigned char colupf;                    /* the shot's colour            */
unsigned char cx_p0bl, cx_p1bl, cx_pp;   /* collisions of a picture      */
unsigned char yreg;                      /* the Y register, see overscan() */

/* Every demon picture, both halves side by side, at each of the four
   pixels inside a character, and the cannon likewise: made at build time
   by mktables.py (tables.s), see r_demon and r_cannon in engine.s. */
extern const unsigned char demon_rows[];
extern const unsigned char img_lo[], img_hi[], rows_lo[], rows_hi[];
extern const unsigned char band_tab[64]; /* rows of a frame with pixels  */
extern const unsigned char cannon_img[4 * 48];

/* ---- the fixed parts ------------------------------------------------------- */

/* What each buffer shows of the parts that rarely change, so they are only
   redrawn when they do. Kept flat and compared by hand: cc65 turns a
   two-dimensional array and memcmp into more work than the rest of this. */
static unsigned char shown_off[12];      /* score digits, 6 per buffer   */
static unsigned char shown_lives[2];
static unsigned char shown_cannon[2];
static unsigned char shown_bunker[2];
static unsigned char shown_ground[2];
static unsigned char shown_text[2];

/*
 * The top line in the demo. This is a rebuild, and it says so: instead of
 * the IMAGIC logo - which is not a picture of its own but player 1's score
 * set to the "digits" AB CD EA at power-on - the line takes turns with what
 * this is, whose game it is, and how to start. After a game the last score
 * takes its turn too. The game's RAM is not touched: only the drawing looks
 * at it. A message borrows the score line's 26 characters for its letters,
 * plain one-colour characters out of the Plus/4's own character ROM.
 */
#define TEXT_ROW    1
#define MSG_TIME    150                  /* pictures each: three seconds  */
#define MSGS        4
static const char *const msg_text[MSGS] = {
    "DEMON ATTACK CLONE",
    "ATARI 2600 ORIGINAL BY IMAGIC, 1982",
    "CONVERTED TO C16 / PLUS/4 BY Q4Z1 2026",
    "PRESS FIRE OR F1 TO START",
};
/* colour < 8 in a colour cell: a one-colour (hires) character */
static const unsigned char msg_attr[MSGS] = { 0x67, 0x51, 0x51, 0x67 };
extern unsigned char chargen[64 * 8];   /* engine.s: A-Z, digits, signs  */
void eng_chargen(void);
static unsigned char laser_attr;
static unsigned char msg_phase;          /* 0: the score, 1..MSGS: text   */
static unsigned char msg_timer, msg_seen;
static unsigned char letter[26];         /* show_line: letters handed out */

/* The top line of buffer b: the score's cells, or message m's. */
static void __fastcall__ show_line(unsigned char m)
{
    unsigned char i, j, n, c, b = back, *p, *f;
    const char *t;

    shown_text[b] = m;
    p = r_scr_ptr(b);
    memset(p, 0, 80);
    if (m) {
        t = msg_text[m - 1];
        f = r_font_ptr(b) + SCORE_CODE * 8;
        memset(f, 0, 26 * 8);
        p += TEXT_ROW * 40 + (40 - strlen(t)) / 2;
        n = 0;                                   /* letters handed out */
        for (i = 0; (c = t[i]) != 0; ++i) {
            if (c == ' ') continue;
            /* screen code: letters are PETSCII in cc65's strings */
            if (c >= 'A' && c <= 'Z') c = c - 'A' + 1;
            for (j = 0; j < n && letter[j] != c; ++j) ;
            if (j == n) {                        /* a new letter */
                memcpy(f + j * 8, chargen + c * 8, 8);
                letter[n++] = c;
            }
            p[i] = SCORE_CODE + j;
        }
    } else {
        for (i = 0; i < 13; ++i) {
            p[13 + i] = SCORE_CODE + i;
            p[40 + 13 + i] = SCORE_CODE + 13 + i;
        }
        memset(shown_off + (b ? 6 : 0), 0xFF, 6);   /* the score is gone */
    }
    r_row_attr[TEXT_ROW] = m ? msg_attr[m - 1] : laser_attr;
    memset(r_att_ptr(b) + TEXT_ROW * 40, r_row_attr[TEXT_ROW], 40);
}

/* What the top line shows this picture. */
static unsigned char top_line(void)
{
    unsigned char d = frames - msg_seen;
    msg_seen = frames;
    if (attract & 0x80) return msg_phase = 0;   /* a game: the score */
    if ((game_on & 0x80) && !(attract & 0x40))
        return msg_phase = 0;                   /* game select: its number */
    if (msg_phase == 0 && !(game_on & 0x80)) {  /* no score yet: the logo */
        msg_phase = 1;
        msg_timer = 0;
    }
    msg_timer += d;
    if (msg_timer >= MSG_TIME) {
        msg_timer = 0;
        if (++msg_phase > MSGS) msg_phase = (game_on & 0x80) ? 0 : 1;
    }
    return msg_phase;
}

static void fixed_parts(void)
{
    unsigned char i, n, c, k, *p;
    unsigned char b = back;

    /* the top line: a message, or the score */
    i = top_line();
    if (i != shown_text[b]) show_line(i);

    /* score line, when it changed */
    k = b ? 6 : 0;
    if (!i && (shown_off[k] != digit_off(0) || shown_off[k + 1] != digit_off(1) ||
        shown_off[k + 2] != digit_off(2) || shown_off[k + 3] != digit_off(3) ||
        shown_off[k + 4] != digit_off(4) || shown_off[k + 5] != digit_off(5))) {
        shown_off[k] = score_off[0] = digit_off(0);
        shown_off[k + 1] = score_off[1] = digit_off(1);
        shown_off[k + 2] = score_off[2] = digit_off(2);
        shown_off[k + 3] = score_off[3] = digit_off(3);
        shown_off[k + 4] = score_off[4] = digit_off(4);
        shown_off[k + 5] = score_off[5] = digit_off(5);
        o_src = ROMP(0x1F00);
        r_score();
    }

    /* bunkers */
    n = (coop & 0x80) ? lives[0] : lives[player];
    if (n & 0x80) n = 0;
    if (n > 6) n = 6;
    if (n != shown_lives[b]) {
        shown_lives[b] = n;
        p = r_scr_ptr(b) + 23 * 40 + 4;
        for (i = 0; i < 6; ++i) p[i << 1] = i < n ? CODE_BUNKER : CODE_GROUND;
    }

    /* colour cells of the cannon's rows, the bunkers' and the ground's */
    c = ted_attr[(cannon_col & colmask) >> 1];
    if (c != shown_cannon[b]) {
        shown_cannon[b] = c;
        p = r_att_ptr(b) + 21 * 40;
        memset(p, c, 80);
        r_row_attr[21] = r_row_attr[22] = c;
    }
    c = ted_attr[bunker_col >> 1];
    if (c != shown_bunker[b]) {
        shown_bunker[b] = c;
        memset(r_att_ptr(b) + 23 * 40, c, 40);
    }
    c = ted_attr[(unsigned char)((ground_col & colmask) - 12) >> 1];
    if (c != shown_ground[b]) {
        shown_ground[b] = c;
        memset(r_att_ptr(b) + 24 * 40, c, 40);
    }
}

/* The whole picture of this frame, and its collisions. */
static void kernel(void)
{
    r_begin();
    fixed_parts();
    kernel_asm();
}

/* Only the collisions: a frame whose picture is not drawn (see main). */
extern unsigned char nodraw;

static void kernel_nodraw(void)
{
    nodraw = 0x80;
    kernel_asm();
    nodraw = 0;
}

/* ======================================================================
 * 10. Sound: the 2600's two voices on the TED's two
 *
 * The 2600 divides a 31.4 kHz clock by AUDF+1 and then by a pattern chosen
 * with AUDC: 2 for a pure tone, 6 for a lower one, a 9-bit shift register
 * for noise, a 5-bit one for a buzz. The TED has two square waves, the
 * second of which can be noise instead, and one volume for both. So:
 * noise goes to voice 2, the other voice to voice 1, and the louder of the
 * two sets the volume. Everything the game plays fits.
 * ==================================================================== */

/* TED register values for each kind of voice and each AUDF, made by
   mktables.py: 1024 - 111861 / frequency, which comes out as
   1024 - k * (AUDF + 1), with k 7 for AUDC 4 and 5 (15720 / (F+1) Hz), 21
   for 12 and 13 (5240), 28 for 8 (noise) and 43 for the rest, the buzz
   (about 2620). */
extern const unsigned char tone_lo[4 * 32], tone_hi[4 * 32];

/* which of the four each AUDC value is */
static const unsigned char tone_kind[16] = {
    3, 3, 3, 3, 0, 0, 3, 3, 2, 3, 3, 3, 1, 1, 3, 3
};
static const unsigned char ted_volume[16] = {
    0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8
};

static void ted_sound(void)
{
    unsigned char c0 = audc0 & 15, c1 = audc1 & 15;
    unsigned char v0 = audv0 & 15, v1 = audv1 & 15;
    unsigned char ctl = 0, i0, i1;

    if (c0 == 0 || c0 == 11) v0 = 0;
    if (c1 == 0 || c1 == 11) v1 = 0;
    i0 = (tone_kind[c0] << 5) | (audf0 & 31);
    i1 = (tone_kind[c1] << 5) | (audf1 & 31);
    if (c0 == 8) {                              /* voice 0 noise: swap */
        if (v1) { TED_T1_LO = tone_lo[i1]; TED_T1_HI = (TED_T1_HI & 0xFC) | tone_hi[i1]; ctl |= 0x10; }
        if (v0) { TED_T2_LO = tone_lo[i0]; TED_T2_HI = (TED_T2_HI & 0xFC) | tone_hi[i0]; ctl |= 0x40; }
    } else {
        if (v0) { TED_T1_LO = tone_lo[i0]; TED_T1_HI = (TED_T1_HI & 0xFC) | tone_hi[i0]; ctl |= 0x10; }
        if (v1) { TED_T2_LO = tone_lo[i1]; TED_T2_HI = (TED_T2_HI & 0xFC) | tone_hi[i1]; ctl |= 0x20; }
    }
    TED_SOUND = ctl | ted_volume[v0 > v1 ? v0 : v1];
}

/* ======================================================================
 * 11. Input
 *
 * Keyboard and joysticks share one port with two latches, $FD30 and $FF08.
 * The row goes to both, and $FF08 has to be read twice: the first read
 * still sees the value just written. (The same as in Phoenix; its README
 * has the whole story.)
 *
 *   joystick 1 or cursor keys + space   player 1 (the keys: whoever is up)
 *   joystick 2                           player 2
 *   F1                                   game reset
 *   F2                                   game select
 *   F3 / Help                            difficulty left / right: A or B
 *   Run/Stop                             leave (cold start)
 * ==================================================================== */

static unsigned char __fastcall__ port(unsigned char row)
{
    unsigned char v;
    __asm__("sei");
    KEY_ROW = row;
    KEY_LATCH = row;
    v = KEY_LATCH;
    v = KEY_LATCH;
    KEY_LATCH = 0xFF;
    __asm__("cli");
    return v;
}

static unsigned char __fastcall__ joystick(unsigned char sel)
{
    unsigned char v;
    __asm__("sei");
    KEY_ROW = 0xFF;
    KEY_LATCH = sel;
    v = KEY_LATCH;
    v = KEY_LATCH;
    KEY_LATCH = 0xFF;
    __asm__("cli");
    return v;
}

static unsigned char keys_prev;

static void read_input(void)
{
    unsigned char j1, j2, k, f, p0, p1, kb = 0, fire0 = 0, fire1 = 0;

    j1 = ~joystick(0xFB);
    j2 = ~joystick(0xFD);
    p0 = j1 & 0x0F;                             /* right, left, down, up: */
    p1 = j2 & 0x0F;                             /* the 2600's bits        */
    if (j1 & 0x40) fire0 = 1;
    if (j2 & 0x80) fire1 = 1;

    k = ~port(0xBF);
    if (k & 0x08) kb |= 8;                      /* cursor right */
    if (k & 0x01) kb |= 4;                      /* cursor left  */
    k = ~port(0x7F);
    f = k & 0x10;                               /* space        */
    if (k & 0x80) eng_reset();                  /* Run/Stop     */
    if (player) { p1 |= kb; if (f) fire1 = 1; }
    else        { p0 |= kb; if (f) fire0 = 1; }

    swcha = (unsigned char)~((p0 << 4) | p1);
    inpt4 = fire0 ? 0x00 : 0x80;
    inpt5 = fire1 ? 0x00 : 0x80;

    k = ~port(0xFE);
    swchb = (swchb & 0xC0) | 0x0B;
    if (k & 0x10) swchb &= 0xFE;                /* F1: reset  */
    if (k & 0x20) swchb &= 0xFD;                /* F2: select */
    f = k & ~keys_prev;
    keys_prev = k;
    if (f & 0x40) swchb ^= 0x40;                /* F3: left difficulty  */
    if (f & 0x08) swchb ^= 0x80;                /* Help: right          */
}

/* ======================================================================
 * 12. Start-up and the loop
 * ==================================================================== */

extern const unsigned char bar_val[7];   /* engine.s */
static const unsigned char mask_line[8] = { 0xFF, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55 };

/* Buffer b's matrix as a picture starts out: the score's cells, the ground,
   one colour everywhere - and every fixed part to be drawn again. */
static void __fastcall__ init_matrix(unsigned char b)
{
    unsigned char i, *p = r_scr_ptr(b);

    memset(p, 0, 1000);
    for (i = 0; i < 13; ++i) {
        p[13 + i] = SCORE_CODE + i;
        p[40 + 13 + i] = SCORE_CODE + 13 + i;
    }
    memset(p + 23 * 40, CODE_GROUND, 40);
    memset(p + 24 * 40, CODE_SOLID, 40);
    memset(r_att_ptr(b), laser_attr, 1000);
    shown_lives[b] = 0xFF;
    shown_cannon[b] = 0xFF;
    shown_bunker[b] = 0xFF;
    shown_ground[b] = 0xFF;
    shown_text[b] = 0;                          /* the score's layout */
    memset(shown_off + (b ? 6 : 0), 0xFF, 6);
}

static void setup(void)
{
    unsigned i, b;
    unsigned char *p, s, h;

    laser_attr = ted_attr[0x6E >> 1];

    for (b = 0; b < 2; ++b) {
        /* fixed characters: ground and bunker; the row in the middle of
           each, lines 2..7 of row 23, alternates the two colour registers */
        p = r_font_ptr(b);
        for (i = 0; i < 8; ++i) {
            s = (i < 2) ? 0 : ((i & 1) ? 0x55 : 0xAA);
            p[CODE_GROUND * 8 + i] = s;
            p[CODE_BUNKER * 8 + i] = s;
        }
        /* a bunker: $10, $10, $38, $28, $28 at pixels 1..3 of the cell */
        p[CODE_BUNKER * 8 + 2] = (0xAA & ~0x0C) | 0x0C;
        p[CODE_BUNKER * 8 + 3] = (0x55 & ~0x0C) | 0x0C;
        p[CODE_BUNKER * 8 + 4] = (0xAA & ~0x3F) | 0x3F;
        p[CODE_BUNKER * 8 + 5] = (0x55 & ~0x33) | 0x33;
        p[CODE_BUNKER * 8 + 6] = (0xAA & ~0x33) | 0x33;
        memset(p + CODE_SOLID * 8, 0xFF, 8);
        /* the points of a demon being made: each of the seven bytes a
           four-pixel point can leave in a character, on each of its lines,
           in the colour that line has (see band_colours in kernel.s) */
        for (i = 0; i < 8; ++i) {
            s = mask_line[i];
            for (h = 0; h < 7; ++h)
                p[(BAR_CODE + 7 * i + h) * 8 + i] = bar_val[h] & s;
        }

        init_matrix(b);
    }
    for (i = 0; i < 25; ++i) r_row_attr[i] = laser_attr;
    eng_chargen();
}

static void power_on(void)                                      /* $124A */
{
    memset(ram, 0, 128);
    game_no = 1;
    reset_positions();
    score_hi[0] = 0xAB;                         /* "abcdea": IMAGIC */
    score_mid[0] = 0xCD;
    score_lo[0] = 0xEA;
    rnd = 0xEA;
    start_wave(0x87);
    /* the original goes straight on into the first frame at $14DC */
    game_logic();
    score_digits();
}

/* ======================================================================
 * 13. The end of a game: a page for the hall of fame
 *
 * The original just goes back to its demo with the score at the top. Here
 * the game stops first on a still page that says everything a photo of it
 * needs to prove a score: which game this is, the score, the game number
 * and the difficulty it was played at. Fire, space or F1 goes on - into the
 * demo, just where the original would be.
 * ==================================================================== */

/* The page goes into the picture not on screen, which is built up again
   afterwards: on a C16 there is no room for a page of its own. */
void eng_page_on(void);
void eng_page_off(void);
void eng_buf_reset(void);
static unsigned char *page_scr, *page_att;

static unsigned char best[3];            /* best score since power-on, BCD */
static unsigned char game_ended;         /* set by the frame a game ends in */
static char line_buf[41];

/* A line of the page, centred; the text is PETSCII as cc65 writes it. */
static void __fastcall__ page_line(unsigned char row, unsigned char attr)
{
    unsigned char i, c, n = strlen(line_buf);
    unsigned char *p = page_scr + row * 40 + (40 - n) / 2;
    memset(page_att + row * 40, attr, 40);
    for (i = 0; i < n; ++i) {
        c = line_buf[i];
        if (c >= 'A' && c <= 'Z') c = c - 'A' + 1;     /* screen code */
        p[i] = c;
    }
}

/* Six BCD digits at p, leading zeros blank but the last. */
static void __fastcall__ put_score(char *p, unsigned char y)
{
    unsigned char d[3], i, c, lead = 1;
    d[0] = score_hi[y]; d[1] = score_mid[y]; d[2] = score_lo[y];
    for (i = 0; i < 6; ++i) {
        c = (i & 1) ? d[i >> 1] & 0x0F : d[i >> 1] >> 4;
        if (c) lead = 0;
        p[i] = (lead && i < 5) ? ' ' : '0' + c;
    }
}

static void __fastcall__ note_best(unsigned char y)
{
    if (score_hi[y] > best[0] ||
        (score_hi[y] == best[0] && (score_mid[y] > best[1] ||
         (score_mid[y] == best[1] && score_lo[y] > best[2])))) {
        best[0] = score_hi[y]; best[1] = score_mid[y]; best[2] = score_lo[y];
    }
}

#ifdef TEST_PRESS
volatile unsigned char test_press;      /* tests set it: a button is down */
#endif

static unsigned char any_button(void)
{
    read_input();
#ifdef TEST_PRESS
    if (test_press) return 1;
#endif
    return !(inpt4 & 0x80) || !(inpt5 & 0x80) || !(swchb & 1);
}

static void game_over_page(void)
{
    unsigned char two = two_players || (coop & 0x80);

    note_best(0);
    if (two) note_best(1);

    page_scr = r_scr_ptr(back);
    page_att = r_att_ptr(back);
    memset(page_scr, ' ', 1000);
    memset(page_att, 0, 1000);
    strcpy(line_buf, "DEMON ATTACK CLONE");
    page_line(3, 0x77);
    strcpy(line_buf, "CONVERTED TO C16 / PLUS/4 BY Q4Z1 2026");
    page_line(5, 0x51);
    strcpy(line_buf, "ATARI 2600 ORIGINAL BY IMAGIC, 1982");
    page_line(6, 0x51);
    strcpy(line_buf, "GAME OVER");
    page_line(10, 0x71);
    if (two) {
        strcpy(line_buf, "PLAYER 1       ");
        put_score(line_buf + 9, 0);
        page_line(13, 0x73);
        strcpy(line_buf, "PLAYER 2       ");
        put_score(line_buf + 9, 1);
        page_line(14, 0x73);
    } else {
        strcpy(line_buf, "SCORE       ");
        put_score(line_buf + 6, 0);
        page_line(13, 0x73);
    }
    /* game 1..10; the difficulty switches: player 1 the left, 2 the right */
    strcpy(line_buf, "GAME 10   DIFFICULTY A/B");
    if (game_no < 0x10) {
        line_buf[5] = '0' + game_no;
        line_buf[6] = ' ';
    }
    line_buf[21] = (swchb & 0x40) ? 'A' : 'B';
    if (two) line_buf[23] = (swchb & 0x80) ? 'A' : 'B';
    else line_buf[22] = 0;
    page_line(16, 0x71);
    strcpy(line_buf, "BEST SINCE POWER-ON       ");
    {
        unsigned char sh = score_hi[0], sm = score_mid[0], sl = score_lo[0];
        score_hi[0] = best[0]; score_mid[0] = best[1]; score_lo[0] = best[2];
        put_score(line_buf + 20, 0);
        score_hi[0] = sh; score_mid[0] = sm; score_lo[0] = sl;
    }
    page_line(18, 0x51);
    strcpy(line_buf, "PRESS FIRE TO GO ON");
    page_line(22, 0x63);

    eng_page_on();
    while (any_button()) ;                      /* let go of the last shot */
    while (!any_button()) ;
    eng_page_off();
    eng_buf_reset();                            /* the page's buffer: anew */
    init_matrix(back);
}

#ifdef DEBUG
/* For comparing with the original in an emulator: the program waits for
   dbg_go and stops after dbg_stop frames, with the game's RAM as it is at
   the end of a frame ($1277). With dbg_inject set it skips the power-on and
   carries on from whatever was put into ram[] meanwhile - a state taken
   from the original at the same point. */
volatile unsigned char dbg_ready;
volatile unsigned char dbg_go;
volatile unsigned char dbg_inject;
volatile unsigned dbg_stop = 0xFFFF;
unsigned dbg_count;
unsigned dbg_skipped;                    /* frames not drawn           */
void dbg_mark(void) { }                  /* a place for a breakpoint */
void dbg_stopped(void) { for (;;) ; }    /* and one to stop in       */

/* Measuring: with the screen off and no interrupts the CPU runs at full
   speed all the time, so the emulator's clock between two of the marks
   below is what runs between them costs. Each part starts from the same
   frame's state. */
void dbg_m0(void) { }
void dbg_m1(void) { }
void dbg_m2(void) { }
void dbg_m3(void) { }
void dbg_m4(void) { }
void dbg_m5(void) { }
void dbg_m6(void) { }
void dbg_m7(void) { }
static unsigned char dbg_ram[128];
volatile unsigned char dbg_bench;

static void dbg_measure(void)
{
    __asm__("sei");
    *(volatile unsigned char *)0xFF0A = 0;          /* no raster interrupt */
    *(volatile unsigned char *)0xFF06 &= 0xEF;      /* screen off */
    memcpy(dbg_ram, ram, 128);
    dbg_m0();
    read_input(); sound_frame(); vblank(); score_digits();
    dbg_m1();
    memcpy(ram, dbg_ram, 128);
    read_input(); sound_frame(); vblank(); score_digits();
    memcpy(dbg_ram, ram, 128);          /* the state the kernel sees */
    dbg_m2();
    r_begin(); fixed_parts();
    dbg_m3();
    kernel_asm();
    dbg_m4();
    memcpy(ram, dbg_ram, 128);
    kernel_nodraw();
    dbg_m5();
    overscan();
    dbg_m6();
    ted_sound();
    dbg_m7();
    for (;;) ;
}
#endif

/*
 * The cartridge is the American one: the 2600 runs it sixty frames a
 * second, and everything - speeds, the sound's tempo - counts in those
 * frames. The Plus/4 shows fifty pictures a second, so five pictures owe the
 * game six frames. Every picture that went by adds six fifths of a frame;
 * the frames owed are worked out - collisions and all - and the last of them
 * is drawn. The one extra frame in five, and whatever a busy moment leaves
 * behind when drawing takes longer than a picture, are simply not drawn, so
 * the game never runs slow.
 */
int main(void)
{
    unsigned char seen, behind, playing = 0, owed = 0;

    eng_init();
    setup();
#ifdef DEBUG
    dbg_ready = 1;
    while (!dbg_go) ;
    if (dbg_inject) { seen = frames; goto frame; }
#endif
    power_on();
    seen = frames;
    goto draw;

    for (;;) {
        while (ready) ;                         /* the picture is not up yet */
#if !defined(DEBUG) || defined(DEBUG_PAGE)
        if (game_ended) {                       /* a page for the photo */
            game_ended = 0;
            game_over_page();
            seen = frames - 1;                  /* no time went by for it */
        }
#endif
        behind = frames - seen;
        seen = frames;
        do owed += 6; while (--behind);         /* in fifths of a frame */
        behind = 0;
        while (owed >= 5) { owed -= 5; ++behind; }
        read_input();               /* once: nothing changes in between */
        while (--behind) {                      /* frames not drawn */
            playing = attract & 0x80;
            sound_frame();
            vblank();
            score_digits();
            kernel_nodraw();
            overscan();                         /* a game ends in here */
            if (playing && attract == 0x40) game_ended = 1;
            ted_sound();
#ifdef DEBUG
            dbg_mark();
            ++dbg_skipped;
            if (++dbg_count == dbg_stop) {
                if (dbg_bench) dbg_measure();
                dbg_stopped();
            }
#endif
        }
#ifdef DEBUG
        goto logic;
frame:
        read_input();
logic:
#endif
        playing = attract & 0x80;
        sound_frame();
        vblank();
        score_digits();
draw:
        kernel();
        ready = 1;
        overscan();
        if (playing && attract == 0x40) game_ended = 1;
        ted_sound();
#ifdef DEBUG
        dbg_mark();
        if (++dbg_count == dbg_stop) {
            if (dbg_bench) dbg_measure();
            dbg_stopped();
        }
#endif
    }
    return 0;
}
