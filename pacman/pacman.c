/*
 * Pac-Man for the Commodore Plus/4
 * ================================
 *
 * The Plus/4 has no sprites. The figures are therefore built from characters
 * that are recomputed on every frame - which is what lets them move pixel by
 * pixel instead of tile by tile, and makes them 12x12 pixels, clearly larger
 * than a tile. The maze fills the screen edge to edge.
 *
 * How it works:
 *
 *   Normally the TED shows character codes from 128 up as inverted copies of
 *   0..127. Bit 7 of $FF07 turns that off; all 256 characters are then free
 *   to use. The upper 128 serve as a pool: each figure claims 3x3 of them.
 *   On every frame those characters are filled with the pixel-shifted figure
 *   and placed at the right spot on the screen.
 *
 *   To make that fast enough, the horizontally pre-shifted figure data sits
 *   ready in memory (8 phases per shape) and a short assembly loop does the
 *   merging with the maze background.
 *
 *   The wall lines are inset 2 pixels from the tile edge. That makes a
 *   corridor effectively 12 instead of 8 pixels wide, so a figure fits
 *   through without covering the walls.
 *
 * Layout of this file:
 *   1. Hardware          5. Figures and their data
 *   2. Character set     6. Drawing (with the blitter)
 *   3. Maze              7. Movement, ghost AI
 *   4. Sound and input   8. Game flow
 *
 * Controls: W A S D or the cursor keys, Q quits the game.
 */

#include <conio.h>
#include <string.h>

/* ======================================================================
 * 1. Hardware
 * ==================================================================== */

#define BILD   ((unsigned char *)0x0C00)
#define FARBE  ((unsigned char *)0x0800)

#define TED_TON2_LO  (*(volatile unsigned char *)0xFF0F)
#define TED_TON2_HI  (*(volatile unsigned char *)0xFF10)
#define TED_LAUT     (*(volatile unsigned char *)0xFF11)
#define TED_ZSATZ_M  (*(volatile unsigned char *)0xFF12)  /* Bit 2: font from RAM */
#define TED_ZSATZ_A  (*(volatile unsigned char *)0xFF13)  /* Bit 2-7: font address */
#define TED_HGRUND   (*(volatile unsigned char *)0xFF15)
#define TED_RAHMEN   (*(volatile unsigned char *)0xFF19)
#define TED_RASTER   (*(volatile unsigned char *)0xFF1D)
#define TED_WAAGR    (*(volatile unsigned char *)0xFF07)  /* Bit 7: turn off inversion */
#define ROM_EIN      (*(volatile unsigned char *)0xFF3E)
#define RAM_EIN      (*(volatile unsigned char *)0xFF3F)

/* Colors: brightness * 16 + hue. High brightness washes out to white on the
   Plus/4; the strong colors are at brightness 3 to 6. */
#define C_SCHWARZ  0x00
#define C_WEISS    0x71
#define C_GELB     0x77   /* Pac-Man          */
#define C_ROT      0x42   /* Blinky           */
#define C_ROSA     0x6B   /* Pinky            */
#define C_CYAN     0x63   /* Inky             */
#define C_ORANGE   0x58   /* Clyde            */
#define C_BLAU     0x36   /* walls            */
#define C_ANGST    0x4E   /* edible ghost     */
#define C_HELLBLAU 0x5D
#define C_TUER     0x5B
#define C_PUNKT    0x62   /* dot              */

/* ======================================================================
 * 2. Character set
 * ==================================================================== */

#define Z_MAUER    64    /* 64..79: 16 wall shapes         */
#define Z_KRUEMEL  80
#define Z_PILLE    81
#define Z_TUER     82
#define Z_VORRAT  128    /* figure characters start here   */
#define EINZUG      3    /* inset of the wall line         */
#define DICKE       2    /* thickness of the wall line     */

/* 2 KB character set, aligned to an address divisible by 2048. */
static unsigned char zeichenspeicher[2048 + 2047];
static unsigned char *zeichensatz;
static unsigned rom_index;

/*
 * Fetches the ROM character set. On the Plus/4 cc65 banks the ROM out to use
 * all of memory; for the character generator at $D000 it has to come back
 * briefly. No C stack may be touched inside that window (it lives at
 * $F500-$FCFF and would be covered), hence globals only and no function call.
 */
static void font_aus_rom(void)
{
    __asm__("sei");
    ROM_EIN = 0;
    for (rom_index = 0; rom_index < 512; ++rom_index)
        zeichensatz[rom_index] = ((unsigned char *)0xD000)[rom_index];
    RAM_EIN = 0;
    __asm__("cli");
}

/*
 * Builds the 16 wall characters. What gets drawn is the outline of the wall
 * area: a line goes only on an edge that has a walkable tile behind it, moved
 * EINZUG pixels inward and DICKE pixels thick.
 *
 * EINZUG and DICKE are chosen so that the lines of opposite edges land exactly
 * on each other (both at pixel 3 and 4). A wall one tile thick is therefore
 * the same 2-pixel line as the outline of a large block - the walls look the
 * same everywhere.
 *
 * The number is a bit mask:
 *   bit 0 = open at the top, 1 = bottom, 2 = left, 3 = right.
 */
static void mauerzeichen_bauen(void)
{
    unsigned char m, y, x, b, x0, x1, y0, y1;
    unsigned char oben, unten, links, rechts;

    for (m = 0; m < 16; ++m) {
        oben   = (unsigned char)(m & 1);
        unten  = (unsigned char)(m & 2);
        links  = (unsigned char)(m & 4);
        rechts = (unsigned char)(m & 8);

        /* extent of the lines, so corners close cleanly */
        x0 = (unsigned char)(links  ? EINZUG : 0);
        x1 = (unsigned char)(rechts ? 7 - EINZUG : 7);
        y0 = (unsigned char)(oben   ? EINZUG : 0);
        y1 = (unsigned char)(unten  ? 7 - EINZUG : 7);

        for (y = 0; y < 8; ++y) {
            b = 0;
            /* horizontal lines */
            if ((oben  && y >= EINZUG && y < EINZUG + DICKE) ||
                (unten && y > 7 - EINZUG - DICKE && y <= 7 - EINZUG))
                for (x = x0; x <= x1; ++x) b |= (unsigned char)(0x80 >> x);
            /* vertical lines */
            if (y >= y0 && y <= y1) {
                for (x = 0; x < DICKE; ++x) {
                    if (links)  b |= (unsigned char)(0x80 >> (EINZUG + x));
                    if (rechts) b |= (unsigned char)(0x80 >> (7 - EINZUG - x));
                }
            }
            zeichensatz[(Z_MAUER + m) * 8 + y] = b;
        }
    }
}

static const unsigned char KLEINZEUG[] = {
    0x00, 0x00, 0x00, 0x18, 0x18, 0x00, 0x00, 0x00,   /* dot         */
    0x00, 0x3C, 0x7E, 0x7E, 0x7E, 0x7E, 0x3C, 0x00,   /* power pill  */
    0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00,   /* house door  */
};

/* ======================================================================
 * 3. Maze
 * ==================================================================== */

#define KB 40          /* tiles across - the whole screen            */
#define KH 24          /* tiles down                                */
#define OFFY 1         /* row 0 is reserved for the status line      */

#define F_LEER   0
#define F_PUNKT  1
#define F_PILLE  2
#define F_MAUER  3
#define F_TUER   4

/* '#' wall, '.' dot, 'o' power pill, '-' ghost house door, ' ' empty. */
static const char PLAN[KH][KB + 1] = {
    "########################################",
    "#..................##..................#",
    "#.####.#####.#####.##.#####.#####.####.#",
    "#o####.#####.#####.##.#####.#####.####o#",
    "#.####.#####.#####.##.#####.#####.####.#",
    "#......................................#",
    "#.####.##.#####.########.#####.##.####.#",
    "#......##.....#....##....#.....##......#",
    "######.#####.#####.##.#####.#####.######",
    "     #.##......          ......##.#     ",
    "######.##.#########--#########.##.######",
    "..........######        ######..........",
    "######.##.######        ######.##.######",
    "     #.##.####################.##.#     ",
    "######.##......................##.######",
    "######.#####.#####.##.#####.#####.######",
    "#..................##..................#",
    "#.####.#####.#####.##.#####.#####.####.#",
    "#o..##............................##..o#",
    "###.##.####.#####.####.#####.####.##.###",
    "#......##.....#....##....#.....##......#",
    "#.##########.#####.##.#####.##########.#",
    "#......................................#",
    "########################################",
};

/* Precomputed row starts in screen memory. Saves a 16-bit multiplication
   per cell in the drawing loops. */
static unsigned bildzeile[KH];
static unsigned char *zeile_zeichen_tab[KH];  /* pointer to feldzeichen[my] */
static unsigned char *zeile_feld_tab[KH];     /* pointer to feld[my]        */

static unsigned char feld[KH][KB];       /* what lies on the tile      */
static unsigned char feldzeichen[KH][KB];/* which character belongs on it */
static unsigned int  restpunkte;
static unsigned char pillenx[4], pilleny[4];
static unsigned char mauerfarbe = C_BLAU;

/* Starting places and ghost house */
#define PAC_STARTX 19
#define PAC_STARTY 18
#define TUERX      19
#define HAUSY      11
#define AUSY        9

static unsigned char ist_mauer(unsigned char mx, unsigned char my)
{
    if (mx >= KB || my >= KH) return 0;
    return (unsigned char)(feld[my][mx] == F_MAUER);
}


/* Redraws the character of a tile - which also erases a figure. */
static void kachel_zeichnen(unsigned char mx, unsigned char my)
{
    unsigned pos = bildzeile[my] + mx;
    unsigned char *zf = feld[my];
    BILD[pos] = feldzeichen[my][mx];
    switch (zf[mx]) {
    case F_MAUER: FARBE[pos] = mauerfarbe; break;
    case F_TUER:  FARBE[pos] = C_TUER;     break;
    case F_PUNKT:
    case F_PILLE: FARBE[pos] = C_PUNKT;    break;
    default:      FARBE[pos] = C_SCHWARZ;  break;
    }
}

static void labyrinth_aufbauen(void)
{
    unsigned char mx, my, m, n = 0;

    for (my = 0; my < KH; ++my) {
        bildzeile[my] = (unsigned)(OFFY + my) * 40;
        zeile_zeichen_tab[my] = feldzeichen[my];
        zeile_feld_tab[my] = feld[my];
    }

    restpunkte = 0;
    for (my = 0; my < KH; ++my) {
        for (mx = 0; mx < KB; ++mx) {
            switch (PLAN[my][mx]) {
            case '#': feld[my][mx] = F_MAUER; break;
            case '-': feld[my][mx] = F_TUER;  break;
            case '.': feld[my][mx] = F_PUNKT; ++restpunkte; break;
            case 'o':
                feld[my][mx] = F_PILLE;
                ++restpunkte;
                if (n < 4) { pillenx[n] = mx; pilleny[n] = my; ++n; }
                break;
            default:  feld[my][mx] = F_LEER;  break;
            }
        }
    }

    if (feld[PAC_STARTY][PAC_STARTX] == F_PUNKT) {
        feld[PAC_STARTY][PAC_STARTX] = F_LEER;
        --restpunkte;
    }

    /* Determine the character of each tile once - the wall shape depends on
       the neighbours and does not change any more during the game. */
    for (my = 0; my < KH; ++my) {
        for (mx = 0; mx < KB; ++mx) {
            switch (feld[my][mx]) {
            case F_MAUER:
                m = 0;
                if (!ist_mauer(mx, (unsigned char)(my - 1))) m |= 1;
                if (!ist_mauer(mx, (unsigned char)(my + 1))) m |= 2;
                if (!ist_mauer((unsigned char)(mx - 1), my)) m |= 4;
                if (!ist_mauer((unsigned char)(mx + 1), my)) m |= 8;
                feldzeichen[my][mx] = (unsigned char)(Z_MAUER + m);
                break;
            case F_TUER:   feldzeichen[my][mx] = Z_TUER;    break;
            case F_PUNKT:  feldzeichen[my][mx] = Z_KRUEMEL; break;
            case F_PILLE:  feldzeichen[my][mx] = Z_PILLE;   break;
            default:       feldzeichen[my][mx] = 32;        break;
            }
        }
    }
}

static void labyrinth_zeichnen(void)
{
    unsigned char mx, my;
    for (my = 0; my < KH; ++my)
        for (mx = 0; mx < KB; ++mx)
            kachel_zeichnen(mx, my);
}

static void mauern_faerben(unsigned char f)
{
    unsigned char mx, my;
    for (my = 0; my < KH; ++my)
        for (mx = 0; mx < KB; ++mx)
            if (feld[my][mx] == F_MAUER)
                FARBE[(unsigned)(OFFY + my) * 40 + mx] = f;
}

/* ======================================================================
 * 4. Sound and input
 * ==================================================================== */

static unsigned char ton_rest;

static void ton(unsigned int hoehe, unsigned char dauer)
{
    TED_TON2_LO = (unsigned char)(hoehe & 0xFF);
    TED_TON2_HI = (unsigned char)(hoehe >> 8);
    TED_LAUT = 0x26;
    ton_rest = dauer;
}

static void ton_stumm(void)
{
    TED_LAUT = 0x00;
    ton_rest = 0;
}

/*
 * Waits for the vertical retrace. It waits for raster line 210, just below
 * the playfield: after that the whole lower border and the blanking interval
 * are left to reposition the figures before the beam reaches them again.
 */
static void bild_warten(void)
{
    while (TED_RASTER >= 210) { }
    while (TED_RASTER <  210) { }
    if (ton_rest && --ton_rest == 0) TED_LAUT = 0x00;
}

static void bilder_warten(unsigned char n)
{
    while (n--) bild_warten();
}

static unsigned char taste_holen(void)
{
    unsigned char t = 0;
    while (kbhit()) t = (unsigned char)cgetc();
    return t;
}

/* ======================================================================
 * 5. Figures
 * ==================================================================== */

#define R_OBEN   0
#define R_LINKS  1
#define R_UNTEN  2
#define R_RECHTS 3

/* Shapes: 0 = mouth closed, 1..4 = mouth open in direction 0..3 */
#define FORM_ZU     0
#define FORM_GEIST  5
#define FORM_ANGST  6
#define FORM_AUGEN  7

/* Per shape 16 rows of 16 pixels, as two bytes. */
static const unsigned char FORMEN[8 * 8] = {
    /* Pac, mouth closed */
    0x18, 0x7E, 0x7E, 0xFF, 0xFF, 0x7E, 0x7E, 0x18,
    /* Pac up */
    0x00, 0x42, 0x66, 0xFF, 0xFF, 0x7E, 0x7E, 0x18,
    /* Pac left */
    0x18, 0x7E, 0x3E, 0x1F, 0x1F, 0x3E, 0x7E, 0x18,
    /* Pac down */
    0x18, 0x7E, 0x7E, 0xFF, 0xFF, 0x66, 0x42, 0x00,
    /* Pac right */
    0x18, 0x7E, 0x7C, 0xF8, 0xF8, 0x7C, 0x7E, 0x18,
    /* Ghost */
    0x18, 0x7E, 0x7E, 0xBD, 0xFF, 0xFF, 0xFF, 0xDB,
    /* Frightened ghost */
    0x18, 0x7E, 0x7E, 0x99, 0xFF, 0xAB, 0xFF, 0xDB,
    /* Eyes only */
    0x00, 0x00, 0x00, 0x42, 0x00, 0x00, 0x00, 0x00,
};

/* Horizontally pre-shifted versions: three columns of 16 rows per shape
   and offset. Computed once at startup. */
static unsigned char vorgeschoben[8 * 8 * 16];
static unsigned char spalte[2][16];      /* figure fitted vertically    */

static void formen_vorschieben(void)
{
    unsigned char f, d, y, b;
    unsigned char *z;

    for (f = 0; f < 8; ++f) {
        for (d = 0; d < 8; ++d) {
            z = vorgeschoben + ((unsigned)f * 8 + d) * 16;
            for (y = 0; y < 8; ++y) {
                b = FORMEN[(unsigned)f * 8 + y];
                z[y]     = (unsigned char)(b >> d);
                z[8 + y] = (unsigned char)(b << (8 - d));
            }
        }
    }
}

/* States of a ghost */
#define G_HAUS   0
#define G_RAUS   1
#define G_JAGD   2
#define G_ANGST  3
#define G_AUGEN  4
#define G_REIN   5

typedef struct {
    unsigned int  cx;        /* center in playfield pixels, 0..319     */
    unsigned char cy;        /* 0..191                                 */
    unsigned char r, wunsch;
    unsigned char form, farbe;
    unsigned char tempo, acc;/* 16 in acc = one pixel                  */
    unsigned char zustand, wartet;
    unsigned char startkx, startky;
    unsigned char zielx, ziely;
    unsigned char alt_sp, alt_ze, sichtbar;
    unsigned char neu_sp, neu_ze, vsx, vsy;   /* for drawing       */
    unsigned int  alt_cx;                     /* state at the last merge    */
    unsigned char alt_cy, alt_form;
    unsigned char alt_zb, alt_sb;   /* row/column used in the last frame    */
    /*
     * Padded to exactly 32 bytes. With an odd size cc65 has to do a 16-bit
     * multiplication for every fig[i]; with a power of two that becomes a
     * shift. This happens dozens of times per frame.
     */
    unsigned char fuellung[6];
} Figur;

static Figur fig[5];         /* 0 = Pac-Man, 1..4 = ghosts  */

static const unsigned char GEISTFARBE[5] = {
    C_GELB, C_ROT, C_ROSA, C_CYAN, C_ORANGE
};

#define PAC (&fig[0])

/*
 * Table of squares for the ghost AI. The distance to the target is measured
 * as dx*dx + dy*dy; cc65 calls a subroutine for every multiplication, and
 * with four ghosts at every tile center that is a great many. A lookup is
 * several times faster.
 */
static unsigned quadrat[KB];

static unsigned zufallswert = 0x1234;

static unsigned char zufall(void)
{
    zufallswert = zufallswert * 25173 + 13849;
    return (unsigned char)(zufallswert >> 8);
}

/* ======================================================================
 * 6. Drawing
 * ==================================================================== */

static unsigned char *p_quelle, *p_grund, *p_ziel;

/*
 * Merges eight bytes: target = figure | background.
 *
 * This is the only piece of assembly in the program and at the same time the
 * most used one: it runs up to 45 times per frame. In C it would be about
 * twice as slow and the game would run at half the frame rate.
 * ptr1..ptr3 are pointer slots that cc65 keeps on the zero page.
 */
static void zelle_mischen(void)
{
    __asm__("lda %v",   p_quelle); __asm__("sta ptr1");
    __asm__("lda %v+1", p_quelle); __asm__("sta ptr1+1");
    __asm__("lda %v",   p_grund);  __asm__("sta ptr2");
    __asm__("lda %v+1", p_grund);  __asm__("sta ptr2+1");
    __asm__("lda %v",   p_ziel);   __asm__("sta ptr3");
    __asm__("lda %v+1", p_ziel);   __asm__("sta ptr3+1");
    __asm__("ldy #$07");
    __asm__("pmmix: lda (ptr1),y");
    __asm__("ora (ptr2),y");
    __asm__("sta (ptr3),y");
    __asm__("dey");
    __asm__("bpl pmmix");
}

/* Releases the nine tiles the figure last stood on. */
static void figur_loeschen(Figur *f)
{
    unsigned char i, j, mx, my;

    if (!f->sichtbar) return;
    for (j = 0; j < 3; ++j) {
        my = (unsigned char)(f->alt_ze + j);
        if (my >= KH) continue;
        for (i = 0; i < 3; ++i) {
            mx = (unsigned char)(f->alt_sp + i);
            if (mx >= KB) mx = (unsigned char)(mx - KB);
            kachel_zeichnen(mx, my);
        }
    }
    f->sichtbar = 0;
}

/*
 * Drawing runs in three passes across all figures, not figure by figure.
 * Reason: if one figure released its old tiles only after another had already
 * been drawn, it would erase that one again - overlapping ghosts would then
 * disappear for good.
 */

/* Pass 1: where is the figure now? */
static void figur_position(Figur *f)
{
    unsigned int bx = f->cx + (KB * 8) - 4;   /* +320 keeps everything positive */
    unsigned char by = (unsigned char)(f->cy - 4);
    unsigned char sp;

    f->vsx = (unsigned char)(bx & 7);
    f->vsy = (unsigned char)(by & 7);
    /* Subtract once instead of using modulo - cc65 would call a whole
       division routine for %, and this runs on every frame. */
    sp = (unsigned char)(bx >> 3);
    if (sp >= KB) sp = (unsigned char)(sp - KB);
    f->neu_sp = sp;
    f->neu_ze = (unsigned char)(by >> 3);
}

/* Pass 2: release the tiles the figure has left. */
/*
 * Releases the tiles the figure has left.
 *
 * The block of 3x3 tiles only moves on every eighth pixel, so in most frames
 * it does not move at all. Then there is nothing to do here - this shortcut
 * was the single most important speedup in the game.
 */
static void figur_freigeben(Figur *f)
{
    unsigned char i, j, mx, my, d;

    if (!f->sichtbar) return;
    if (f->alt_sp == f->neu_sp && f->alt_ze == f->neu_ze) return;
    for (j = 0; j < 2; ++j) {
        my = (unsigned char)(f->alt_ze + j);
        if (my >= KH) continue;
        if ((unsigned char)(my - f->neu_ze) < 2) {
            /* Row still belongs to the figure - only check the columns. */
            for (i = 0; i < 2; ++i) {
                mx = (unsigned char)(f->alt_sp + i);
                if (mx >= KB) mx = (unsigned char)(mx - KB);
                d = (unsigned char)(mx + KB - f->neu_sp);
                if (d >= KB) d = (unsigned char)(d - KB);
                if (d < 2) continue;
                kachel_zeichnen(mx, my);
            }
        } else {
            for (i = 0; i < 2; ++i) {
                mx = (unsigned char)(f->alt_sp + i);
                if (mx >= KB) mx = (unsigned char)(mx - KB);
                kachel_zeichnen(mx, my);
            }
        }
    }
}

/*
 * Pass 3: fill the nine characters and put them on the screen.
 *
 * This is the hottest spot in the program - 45 cells on every frame. In C it
 * was hopelessly slow: cc65 called a 16-bit multiplication for every
 * feldzeichen[my] and pushed every screen access through its software stack,
 * together around 1200 cycles per cell. That is why an assembly routine now
 * does a whole row of three cells in one go.
 *
 * The parameters live in global variables so that the assembly part can reach
 * them without the stack.
 */
static unsigned char *am_q;      /* figure data, column 0 (next at +24)     */
static unsigned char *am_hg;     /* maze characters of the three columns    */
static unsigned char *am_fd;     /* field types of the three columns        */
static unsigned char *am_bd;     /* screen cells                            */
static unsigned char *am_fa;     /* color cells                             */
static unsigned char  am_use[3]; /* 1 = figure has pixels here              */
static unsigned char  am_z;      /* character code of the first column      */
static unsigned char  am_neu;    /* 0 = pattern is already in place         */
static unsigned char  am_fb;     /* figure color                            */
static unsigned char  am_mf, am_tf, am_pf;   /* wall, door, dot             */
static unsigned char  am_zshi;   /* high byte of the charset address        */
static unsigned char *am_tab;    /* pre-shifted figure data                 */
static unsigned char  am_vsy;    /* vertical offset                         */
static unsigned char  am_spn;    /* how many columns to process             */
/* Work bytes and color tables that only the assembly part touches */
unsigned char am_i, am_code, am_hgz, am_typ, am_farbe;
unsigned char am_labtab[5];   /* color per field type, without figure */
unsigned char am_figtab[5];   /* color per field type, with figure    */

/*
 * Fits the figure vertically: three columns of 24 pixel rows, the shape
 * starting at row am_vsy.
 *
 * This used to be memset() and memcpy(). With cc65 those are very expensive
 * for such small amounts - around 700 cycles per call, and there are thirty
 * calls per frame. Written out by hand the whole thing costs a fraction.
 */
static void spalten_fuellen(void)
{
    __asm__(
    "lda _am_tab\n"    "sta ptr1\n"
    "lda _am_tab+1\n"  "sta ptr1+1\n"
    ";  clear all 32 bytes\n"
    "lda #$00\n"
    "ldy #$1F\n"
    "sfclr:\n"
    "sta _spalte,y\n"
    "dey\n"
    "bpl sfclr\n"
    ";  copy three columns of 16 bytes into place\n"
    "lda _am_vsy\n"
    "sta tmp1\n"
    "ldx #$02\n"
    "sfsp:\n"
    "ldy #$00\n"
    "sfcp:\n"
    "lda (ptr1),y\n"
    "sty tmp2\n"
    "ldy tmp1\n"
    "sta _spalte,y\n"
    "inc tmp1\n"
    "ldy tmp2\n"
    "iny\n"
    "cpy #$08\n"
    "bcc sfcp\n"
    ";  next column: source +8, target +16\n"
    "lda ptr1\n"
    "clc\n"
    "adc #$08\n"
    "sta ptr1\n"
    "bcc sfnc\n"
    "inc ptr1+1\n"
    "sfnc:\n"
    "lda tmp1\n"
    "clc\n"
    "adc #$08\n"
    "sta tmp1\n"
    "dex\n"
    "bne sfsp\n"
    );
}

/*
 * Draws three adjacent cells.
 *
 * The character set sits on a 2 KB boundary. That allows "charset + code * 8"
 * to be formed without 16-bit arithmetic: the low byte is code*8, the high
 * byte is the charset high byte + code/32.
 *
 * The colors come from two small tables so that the assembly part needs no
 * branches - cc65 throws away labels that are only reached by unconditional
 * jumps.
 *
 * Zero page: ptr1 source, ptr2 maze characters, ptr3 screen,
 *            ptr4 field types, tmp1/tmp2 background glyph,
 *            tmp3/tmp4 color memory, sreg target glyph.
 */
static void zeile_malen(void)
{
    __asm__(
    "lda _am_q\n"      "sta ptr1\n"
    "lda _am_q+1\n"    "sta ptr1+1\n"
    "lda _am_hg\n"     "sta ptr2\n"
    "lda _am_hg+1\n"   "sta ptr2+1\n"
    "lda _am_bd\n"     "sta ptr3\n"
    "lda _am_bd+1\n"   "sta ptr3+1\n"
    "lda _am_fd\n"     "sta ptr4\n"
    "lda _am_fd+1\n"   "sta ptr4+1\n"
    "lda _am_fa\n"     "sta tmp3\n"
    "lda _am_fa+1\n"   "sta tmp4\n"
    "lda #$00\n"       "sta _am_i\n"

    "zmlp:\n"
    "ldy _am_i\n"
    ";  default: just show the maze\n"
    "lda (ptr2),y\n"
    "sta _am_code\n"
    "lda (ptr4),y\n"
    "sta _am_typ\n"
    "tax\n"
    "lda _am_labtab,x\n"
    "sta _am_farbe\n"

    ";  any figure pixels here?\n"
    "lda _am_use,y\n"
    "beq zmfertig\n"

    "lda _am_z\n"
    "clc\n"
    "adc _am_i\n"
    "sta _am_code\n"
    "ldx _am_typ\n"
    "lda _am_figtab,x\n"
    "sta _am_farbe\n"

    "lda _am_neu\n"
    "beq zmfertig\n"

    ";  target address = charset + code*8\n"
    "lda _am_code\n"
    "asl a\n" "asl a\n" "asl a\n"
    "sta sreg\n"
    "lda _am_code\n"
    "lsr a\n" "lsr a\n" "lsr a\n" "lsr a\n" "lsr a\n"
    "clc\n"
    "adc _am_zshi\n"
    "sta sreg+1\n"

    ";  address of the background glyph\n"
    "ldy _am_i\n"
    "lda (ptr2),y\n"
    "sta _am_hgz\n"
    "asl a\n" "asl a\n" "asl a\n"
    "sta tmp1\n"
    "lda _am_hgz\n"
    "lsr a\n" "lsr a\n" "lsr a\n" "lsr a\n" "lsr a\n"
    "clc\n"
    "adc _am_zshi\n"
    "sta tmp2\n"

    ";  merge eight pixel rows: figure over maze\n"
    "ldy #$07\n"
    "zmmix:\n"
    "lda (ptr1),y\n"
    "ora (tmp1),y\n"
    "sta (sreg),y\n"
    "dey\n"
    "bpl zmmix\n"

    "zmfertig:\n"
    "ldy _am_i\n"
    "lda _am_code\n"
    "sta (ptr3),y\n"
    "lda _am_farbe\n"
    "sta (tmp3),y\n"

    ";  source to the next column: 16 bytes on\n"
    "lda ptr1\n"
    "clc\n"
    "adc #$10\n"
    "sta ptr1\n"
    "bcc zmnc\n"
    "inc ptr1+1\n"
    "zmnc:\n"
    "inc _am_i\n"
    "lda _am_i\n"
    "cmp _am_spn\n"
    "jcc zmlp\n"
    );
}

static void figur_malen(Figur *f, unsigned char nr)
{
    static unsigned char i, j, my, z, neu, sp0, mx, hg;
    static unsigned char sp_von, sp_bis, ze_von, ze_bis;
    static unsigned char *zz, *zf;
    static unsigned      bo, pos;

    /*
     * If neither position nor shape has changed, the pixel patterns in the
     * nine characters are still correct - then the merge is skipped.
     */
    neu = (unsigned char)(f->cx != f->alt_cx || f->cy != f->alt_cy
                          || f->form != f->alt_form);
    if (neu) {
        am_tab = vorgeschoben + ((unsigned)f->form * 8 + f->vsx) * 16;
        am_vsy = f->vsy;
        spalten_fuellen();
        f->alt_cx = f->cx;
        f->alt_cy = f->cy;
        f->alt_form = f->form;
    }

    /*
     * The figure is exactly eight pixels big and thus fills one tile. Across
     * its direction of travel it sits flush on its tile, along it the figure
     * reaches into the next one depending on the offset. Without an offset
     * only one cell is affected, otherwise two.
     */
    sp_von = 0;
    sp_bis = (unsigned char)(f->vsx ? 1 : 0);
    ze_von = 0;
    ze_bis = (unsigned char)(f->vsy ? 1 : 0);

    sp0 = f->neu_sp;
    z = (unsigned char)(Z_VORRAT + nr * 4);
    am_neu = neu;
    am_fb = f->farbe;
    am_mf = mauerfarbe;
    am_labtab[F_LEER]  = C_SCHWARZ;
    am_labtab[F_PUNKT] = C_PUNKT;
    am_labtab[F_PILLE] = C_PUNKT;
    am_labtab[F_MAUER] = mauerfarbe;
    am_labtab[F_TUER]  = C_TUER;
    am_figtab[F_LEER]  = am_fb;
    am_figtab[F_PUNKT] = am_fb;
    am_figtab[F_PILLE] = am_fb;
    am_figtab[F_MAUER] = mauerfarbe;   /* wall keeps its color     */
    am_figtab[F_TUER]  = am_fb;

    /*
     * Across its direction of travel the figure sits exactly on its tile. The
     * second row or column is then empty and only needs to be touched if it
     * was still in use on the last frame - otherwise not at all.
     */
    am_spn = (unsigned char)((sp_bis || f->alt_sb) ? 2 : 1);

    if (sp0 <= KB - 2) {
        /* Normal case: the two columns lie next to each other. */
        for (j = 0; j < 2; ++j) {
            if (j == 1 && ze_bis == 0 && f->alt_zb == 0) break;
            my = (unsigned char)(f->neu_ze + j);
            if (my < KH) {
                bo = bildzeile[my] + sp0;
                am_q  = spalte[0] + ((unsigned)j << 3);
                am_hg = zeile_zeichen_tab[my] + sp0;
                am_fd = zeile_feld_tab[my] + sp0;
                am_bd = BILD + bo;
                am_fa = FARBE + bo;
                am_z  = z;
                if (j <= ze_bis) {
                    am_use[0] = 1;
                    am_use[1] = sp_bis;
                } else {
                    am_use[0] = am_use[1] = 0;
                }
                zeile_malen();
            }
            z = (unsigned char)(z + 2);
        }
    } else {
        /* At the tunnel edge the columns wrap - rare, hence in C. */
        for (j = 0; j < 2; ++j) {
            my = (unsigned char)(f->neu_ze + j);
            if (my < KH) {
                zz = zeile_zeichen_tab[my];
                zf = zeile_feld_tab[my];
                bo = bildzeile[my];
                for (i = 0; i < 2; ++i) {
                    mx = (unsigned char)(sp0 + i);
                    if (mx >= KB) mx = (unsigned char)(mx - KB);
                    pos = bo + mx;
                    if (j > ze_bis || i > sp_bis) {
                        BILD[pos] = zz[mx];
                        switch (zf[mx]) {
                        case F_MAUER: FARBE[pos] = mauerfarbe; break;
                        case F_TUER:  FARBE[pos] = C_TUER;     break;
                        case F_PUNKT:
                        case F_PILLE: FARBE[pos] = C_PUNKT;    break;
                        default:      FARBE[pos] = C_SCHWARZ;  break;
                        }
                    } else {
                        if (neu) {
                            hg = zz[mx];
                            p_quelle = spalte[i] + ((unsigned)j << 3);
                            p_grund  = zeichensatz + ((unsigned)hg << 3);
                            p_ziel   = zeichensatz + ((unsigned)(z + i) << 3);
                            zelle_mischen();
                        }
                        BILD[pos] = (unsigned char)(z + i);
                        FARBE[pos] = (unsigned char)(zf[mx] == F_MAUER
                                                     ? mauerfarbe : f->farbe);
                    }
                }
            }
            z = (unsigned char)(z + 2);
        }
    }

    f->alt_sp = f->neu_sp;
    f->alt_ze = f->neu_ze;
    f->alt_zb = ze_bis;
    f->alt_sb = sp_bis;
    f->sichtbar = 1;
}

static void alle_zeichnen(void)
{
    unsigned char i;
    Figur *f;

    for (i = 0, f = fig; i < 5; ++i, ++f) figur_position(f);
    for (i = 0, f = fig; i < 5; ++i, ++f) figur_freigeben(f);
    for (i = 1, f = &fig[1]; i < 5; ++i, ++f) figur_malen(f, i);
    figur_malen(PAC, 0);
}

/* ======================================================================
 * 7. Movement and ghost AI
 * ==================================================================== */

static unsigned int  angst_rest;
static unsigned char gefressen;
static unsigned int  modus_rest;
static unsigned char streunen;
static unsigned char pac_anim;

#define MITTIG(f) (((f)->cx & 7) == 4 && ((f)->cy & 7) == 4)
#define KX(f) ((unsigned char)((f)->cx >> 3))
#define KY(f) ((unsigned char)((f)->cy >> 3))

/* Is the neighbouring tile in direction r walkable? */
static unsigned char frei(unsigned char kx, unsigned char ky,
                          unsigned char r, unsigned char tuer)
{
    unsigned char nx = kx, ny = ky, t;

    switch (r) {
    case R_OBEN:   --ny; break;
    case R_UNTEN:  ++ny; break;
    case R_LINKS:  nx = (unsigned char)(kx == 0 ? KB - 1 : kx - 1); break;
    default:       nx = (unsigned char)(kx >= KB - 1 ? 0 : kx + 1); break;
    }
    if (ny >= KH) return 0;
    t = feld[ny][nx];
    if (t == F_MAUER) return 0;
    if (t == F_TUER)  return tuer;
    return 1;
}

static void pixel_schritt(Figur *f)
{
    switch (f->r) {
    case R_OBEN:   --f->cy; break;
    case R_UNTEN:  ++f->cy; break;
    case R_LINKS:  f->cx = (f->cx == 0) ? (KB * 8 - 1) : (f->cx - 1); break;
    default:       f->cx = (f->cx >= KB * 8 - 1) ? 0 : (f->cx + 1); break;
    }
}

static unsigned int  punkte;
static unsigned char leben, level;
static void statuszeile(void);

static void fressen(unsigned char kx, unsigned char ky)
{
    unsigned char i;

    if (feld[ky][kx] == F_PUNKT) {
        feld[ky][kx] = F_LEER;
        feldzeichen[ky][kx] = 32;
        --restpunkte;
        punkte += 10;
        ton((pac_anim & 8) ? 560 : 620, 2);
        statuszeile();
    } else if (feld[ky][kx] == F_PILLE) {
        feld[ky][kx] = F_LEER;
        feldzeichen[ky][kx] = 32;
        --restpunkte;
        punkte += 50;
        ton(300, 12);
        statuszeile();

        angst_rest = (unsigned int)(level < 10 ? 300 - level * 20 : 100);
        gefressen = 0;
        for (i = 1; i < 5; ++i) {
            if (fig[i].zustand == G_JAGD) {
                fig[i].zustand = G_ANGST;
                fig[i].r ^= 2;
            }
        }
    }
}

static void pac_bewegen(void)
{
    Figur *f = PAC;
    unsigned char kx, ky;

    f->acc = (unsigned char)(f->acc + f->tempo);
    while (f->acc >= 16) {
        f->acc = (unsigned char)(f->acc - 16);
        kx = KX(f); ky = KY(f);
        if (MITTIG(f)) {
            if (f->wunsch != f->r && frei(kx, ky, f->wunsch, 0)) f->r = f->wunsch;
            if (!frei(kx, ky, f->r, 0)) { f->form = FORM_ZU; return; }
            fressen(kx, ky);
        }
        pixel_schritt(f);
        ++pac_anim;
    }
    f->form = (unsigned char)((pac_anim & 4) ? FORM_ZU : (1 + f->r));
}

static void ziel_bestimmen(unsigned char i)
{
    Figur *g = &fig[i];
    signed int zx, zy;
    unsigned char vx, vy, ax, ay;

    if (g->zustand == G_AUGEN) { g->zielx = TUERX; g->ziely = AUSY; return; }

    if (streunen) {
        switch (i) {
        case 1:  g->zielx = KB - 2; g->ziely = 1;      break;
        case 2:  g->zielx = 1;      g->ziely = 1;      break;
        case 3:  g->zielx = KB - 2; g->ziely = KH - 2; break;
        default: g->zielx = 1;      g->ziely = KH - 2; break;
        }
        return;
    }

    vx = KX(PAC); vy = KY(PAC);
    switch (i) {
    case 1:                                  /* Blinky chases directly */
        g->zielx = vx; g->ziely = vy;
        break;
    case 2:                                  /* Pinky aims four tiles ahead    */
        zx = (signed int)vx + 4 * (PAC->r == R_RECHTS) - 4 * (PAC->r == R_LINKS);
        zy = (signed int)vy + 4 * (PAC->r == R_UNTEN)  - 4 * (PAC->r == R_OBEN);
        g->zielx = (unsigned char)(zx < 0 ? 0 : (zx >= KB ? KB - 1 : zx));
        g->ziely = (unsigned char)(zy < 0 ? 0 : (zy >= KH ? KH - 1 : zy));
        break;
    case 3:                                  /* Inky mirrors Blinky through Pac-Man */
        zx = 2 * (signed int)vx - (signed int)KX(&fig[1]);
        zy = 2 * (signed int)vy - (signed int)KY(&fig[1]);
        g->zielx = (unsigned char)(zx < 0 ? 0 : (zx >= KB ? KB - 1 : zx));
        g->ziely = (unsigned char)(zy < 0 ? 0 : (zy >= KH ? KH - 1 : zy));
        break;
    default:                                 /* Clyde backs off up close   */
        ax = (unsigned char)(KX(g) > vx ? KX(g) - vx : vx - KX(g));
        ay = (unsigned char)(KY(g) > vy ? KY(g) - vy : vy - KY(g));
        if ((unsigned)ax + ay > 8) { g->zielx = vx; g->ziely = vy; }
        else { g->zielx = 1; g->ziely = KH - 2; }
        break;
    }
}

/* Picks the direction that gets closest to the target. Reversing is not
   allowed; on a tie up wins over left over down over right. */
static unsigned char richtung_waehlen(unsigned char i)
{
    Figur *g = &fig[i];
    unsigned char gegen = (unsigned char)(g->r ^ 2);
    unsigned char tuer = (unsigned char)(g->zustand == G_AUGEN);
    unsigned char r, beste = 255, anzahl = 0, moeglich[4];
    unsigned char kx = KX(g), ky = KY(g), nx, ny;
    unsigned int  abstand, bester = 0xFFFF;
    unsigned char dx, dy;

    for (r = 0; r < 4; ++r) {
        if (r == gegen) continue;
        if (!frei(kx, ky, r, tuer)) continue;
        nx = kx; ny = ky;
        switch (r) {
        case R_OBEN:   --ny; break;
        case R_UNTEN:  ++ny; break;
        case R_LINKS:  nx = (unsigned char)(kx == 0 ? KB - 1 : kx - 1); break;
        default:       nx = (unsigned char)(kx >= KB - 1 ? 0 : kx + 1); break;
        }
        moeglich[anzahl++] = r;
        dx = (unsigned char)(nx > g->zielx ? nx - g->zielx : g->zielx - nx);
        dy = (unsigned char)(ny > g->ziely ? ny - g->ziely : g->ziely - ny);
        abstand = quadrat[dx] + quadrat[dy];
        if (abstand < bester) { bester = abstand; beste = r; }
    }

    if (anzahl == 0) return gegen;
    if (g->zustand == G_ANGST) return moeglich[zufall() % anzahl];
    return beste;
}

static void geist_bewegen(unsigned char i)
{
    Figur *g = &fig[i];
    unsigned char kx, ky;

    /* Speed depending on state */
    if (g->zustand == G_ANGST)      g->tempo = 38;
    else if (g->zustand == G_AUGEN) g->tempo = 140;
    else g->tempo = (unsigned char)(level < 6 ? 57 + level * 5 : 82);

    if (g->zustand == G_HAUS) {
        if (g->wartet) --g->wartet;
        else g->zustand = G_RAUS;
        return;
    }

    g->acc = (unsigned char)(g->acc + g->tempo);
    while (g->acc >= 16) {
        g->acc = (unsigned char)(g->acc - 16);
        kx = KX(g); ky = KY(g);

        if (g->zustand == G_RAUS) {
            /* Fixed path out of the house: first under the door, then up. */
            if (!MITTIG(g)) { pixel_schritt(g); continue; }
            if (kx < TUERX)      g->r = R_RECHTS;
            else if (kx > TUERX) g->r = R_LINKS;
            else if (ky > AUSY)  g->r = R_OBEN;
            else { g->zustand = angst_rest ? G_ANGST : G_JAGD; g->r = R_LINKS; continue; }
            pixel_schritt(g);
            continue;
        }

        if (g->zustand == G_REIN) {
            if (!MITTIG(g)) { pixel_schritt(g); continue; }
            if (ky < HAUSY) { g->r = R_UNTEN; pixel_schritt(g); continue; }
            g->zustand = G_HAUS;
            g->wartet = 40;
            g->acc = 0;
            continue;
        }

        if (MITTIG(g)) {
            ziel_bestimmen(i);
            g->r = richtung_waehlen(i);
            if (g->zustand == G_AUGEN && kx == TUERX && ky == AUSY) {
                g->zustand = G_REIN;
                g->r = R_UNTEN;
            }
        }
        pixel_schritt(g);
    }

    /* Appearance by state. Deliberately written as an if-chain and not as a
       nested conditional expression - cc65 evaluates that one wrongly. */
    if (g->zustand == G_ANGST) {
        g->form = FORM_ANGST;
        /* Shortly before the power pill runs out the ghost blinks white. */
        g->farbe = (unsigned char)((angst_rest < 80 && (angst_rest & 8))
                                   ? C_WEISS : C_ANGST);
    } else if (g->zustand == G_AUGEN || g->zustand == G_REIN) {
        g->form = FORM_AUGEN;
        g->farbe = C_WEISS;
    } else {
        g->form = FORM_GEIST;
        g->farbe = GEISTFARBE[i];
    }
}

/* Check for contact. Return value 1 = Pac-Man is dead. */
static unsigned char beruehrung(void)
{
    unsigned char i, ax, ay;
    unsigned int  d, px = PAC->cx;
    unsigned char py = PAC->cy;
    Figur *g;

    for (i = 1; i < 5; ++i) {
        g = &fig[i];
        d = (g->cx > px) ? (g->cx - px) : (px - g->cx);
        if (d > KB * 4) d = KB * 8 - d;            /* across the tunnel */
        ax = (unsigned char)d;
        ay = (unsigned char)(g->cy > py ? g->cy - py : py - g->cy);
        if (ax >= 7 || ay >= 7) continue;

        if (g->zustand == G_ANGST) {
            if (gefressen < 4) ++gefressen;
            punkte = (unsigned int)(punkte + (100u << gefressen));
            g->zustand = G_AUGEN;
            g->acc = 0;
            ton(900, 10);
            statuszeile();
        } else if (g->zustand == G_JAGD || g->zustand == G_RAUS) {
            return 1;
        }
    }
    return 0;
}

/* ======================================================================
 * 8. Display and game flow
 * ==================================================================== */

static void zeichen_setzen(unsigned char sx, unsigned char sy,
                           unsigned char z, unsigned char f)
{
    unsigned pos = (unsigned)sy * 40 + sx;
    BILD[pos] = z;
    FARBE[pos] = f;
}

/*
 * For CBM targets cc65 translates character literals to PETSCII: 'A' becomes
 * 193, not 65. That is why this computes relative to 'a' resp. 'A' - which is
 * correct in both character sets. With a fixed 64 or 96 everything would land
 * 128 too high.
 */
static void text_zeigen(unsigned char sx, unsigned char sy,
                        const char *s, unsigned char f)
{
    unsigned char c;
    while ((c = (unsigned char)*s++) != 0) {
        if (c >= 'a' && c <= 'z') c = (unsigned char)(c - ('a' - 1));
        else if (c >= 'A' && c <= 'Z') c = (unsigned char)(c - ('A' - 1));
        zeichen_setzen(sx++, sy, c, f);
    }
}

static void zahl_zeigen(unsigned char sx, unsigned char sy,
                        unsigned int wert, unsigned char stellen)
{
    unsigned char i;
    for (i = stellen; i > 0; --i) {
        zeichen_setzen((unsigned char)(sx + i - 1), sy,
                       (unsigned char)(48 + wert % 10), C_WEISS);
        wert /= 10;
    }
}

static void statuszeile(void)
{
    unsigned char i;

    text_zeigen(0, 0, "SCORE", C_WEISS);
    zahl_zeigen(6, 0, punkte, 5);
    text_zeigen(15, 0, "LEVEL", C_WEISS);
    zahl_zeigen(21, 0, level, 2);
    text_zeigen(28, 0, "LIVES", C_WEISS);
    for (i = 0; i < 3; ++i)
        zeichen_setzen((unsigned char)(34 + i), 0,
                       (unsigned char)(i < leben - 1 ? Z_PILLE : 32), C_GELB);
}

static void bildschirm_leeren(void)
{
    memset(BILD, 32, 1000);
    memset(FARBE, C_SCHWARZ, 1000);
}

static void figuren_setzen(void)
{
    unsigned char i;
    static const unsigned char SX[5] = { PAC_STARTX, TUERX, TUERX - 2, TUERX, TUERX + 2 };
    static const unsigned char SY[5] = { PAC_STARTY, AUSY,  HAUSY,     HAUSY, HAUSY };

    for (i = 0; i < 5; ++i) {
        fig[i].cx = (unsigned int)SX[i] * 8 + 4;
        fig[i].cy = (unsigned char)(SY[i] * 8 + 4);
        fig[i].r = R_LINKS;
        fig[i].wunsch = R_LINKS;
        fig[i].acc = 0;
        fig[i].sichtbar = 0;
        fig[i].alt_form = 255;   /* forces the first merge     */
        fig[i].alt_zb = 1;
        fig[i].alt_sb = 1;
        fig[i].wartet = (unsigned char)(i * 25);
        fig[i].zustand = (unsigned char)(i == 1 ? G_JAGD : G_HAUS);
        fig[i].form = (unsigned char)(i == 0 ? FORM_ZU : FORM_GEIST);
    }
    /*
     * Speed in sixteenths of a pixel per loop pass.
     *
     * Drawing still costs more than one screen frame, the game manages about
     * fourteen passes per second. The values are tuned to that: 72/16 is four
     * and a half pixels per pass, so roughly 63 pixels per second - as fast
     * as the arcade machine.
     *
     * If drawing gets faster, the values belong lower, so that the movement
     * becomes finer rather than faster. The movement itself stays correct
     * either way: the loop in pac_bewegen() always goes pixel by pixel and
     * therefore hits every tile center, no matter how big the overall step.
     */
    PAC->tempo = (unsigned char)(level < 5 ? 66 + level * 6 : 90);
    fig[0].zustand = G_JAGD;
    for (i = 0; i < 5; ++i) fig[i].farbe = GEISTFARBE[i];

    angst_rest = 0;
    gefressen = 0;
    streunen = 1;
    modus_rest = 300;
    pac_anim = 0;
}

#define TOT       0
#define GESCHAFFT 1
#define ABBRUCH   2

static void bereit_anzeigen(void)
{
    text_zeigen(17, OFFY + AUSY, "READY!", C_GELB);
    bilder_warten(100);
    { unsigned char i; for (i = 15; i < 25; ++i) kachel_zeichnen(i, AUSY); }
}

static unsigned char runde_spielen(void)
{
    unsigned char t, i, blinktakt = 0, pillen_an = 1;

    for (;;) {
        bild_warten();

        t = taste_holen();
        switch (t) {
        case 'w': case 'W': case 145: PAC->wunsch = R_OBEN;   break;
        case 'a': case 'A': case 157: PAC->wunsch = R_LINKS;  break;
        case 's': case 'S': case 17:  PAC->wunsch = R_UNTEN;  break;
        case 'd': case 'D': case 29:  PAC->wunsch = R_RECHTS; break;
        case 'q': case 'Q': return ABBRUCH;
        default: break;
        }

        if (++blinktakt >= 16) {
            blinktakt = 0;
            pillen_an ^= 1;
            for (i = 0; i < 4; ++i)
                if (feld[pilleny[i]][pillenx[i]] == F_PILLE)
                    FARBE[(unsigned)(OFFY + pilleny[i]) * 40 + pillenx[i]] =
                        pillen_an ? C_PUNKT : C_SCHWARZ;
        }

        if (angst_rest) {
            if (--angst_rest == 0)
                for (i = 1; i < 5; ++i)
                    if (fig[i].zustand == G_ANGST) fig[i].zustand = G_JAGD;
        } else if (modus_rest && --modus_rest == 0) {
            streunen ^= 1;
            modus_rest = streunen ? 300 : 900;
            for (i = 1; i < 5; ++i)
                if (fig[i].zustand == G_JAGD) fig[i].r ^= 2;
        }

        pac_bewegen();
        for (i = 1; i < 5; ++i) geist_bewegen(i);

        alle_zeichnen();

        if (beruehrung()) return TOT;
        if (restpunkte == 0) return GESCHAFFT;
    }
}

static void sterben(void)
{
    unsigned char i;

    ton_stumm();
    for (i = 0; i < 20; ++i) {
        PAC->form = (unsigned char)((i & 1) ? FORM_ZU : (1 + (i & 3)));
        PAC->farbe = (unsigned char)((i & 1) ? C_GELB : C_ROT);
        figur_position(PAC);
        figur_freigeben(PAC);
        figur_malen(PAC, 0);
        ton((unsigned int)(760 - i * 30), 3);
        bilder_warten(5);
    }
    ton_stumm();
    figur_loeschen(PAC);
    PAC->farbe = C_GELB;
}

static void level_geschafft(void)
{
    unsigned char i;

    ton_stumm();
    for (i = 0; i < 5; ++i) figur_loeschen(&fig[i]);
    for (i = 0; i < 8; ++i) {
        mauern_faerben((unsigned char)((i & 1) ? C_WEISS : C_BLAU));
        bilder_warten(14);
    }
    mauern_faerben(C_BLAU);
}

static unsigned char titelbild(void)
{
    bildschirm_leeren();
    text_zeigen(16, 5, "PAC-MAN", C_GELB);
    text_zeigen(9, 7, "FUER COMMODORE PLUS/4", C_HELLBLAU);

    text_zeigen(8, 12, "STEUERUNG", C_WEISS);
    text_zeigen(8, 14, "W A S D  ODER CURSORTASTEN", C_PUNKT);
    text_zeigen(8, 16, "Q BEENDET DAS SPIEL", C_PUNKT);
    text_zeigen(10, 20, "LEERTASTE ZUM STARTEN", C_GELB);

    while (taste_holen()) { }
    for (;;) {
        unsigned char t = taste_holen();
        if (t == ' ') return 0;
        if (t == 'q' || t == 'Q') return 1;
        bild_warten();
    }
}

static void zeichensatz_einrichten(void)
{
    unsigned i;

    zeichensatz = (unsigned char *)(((unsigned)zeichenspeicher + 2047) & 0xF800);

    memset(zeichensatz, 0, 2048);
    font_aus_rom();
    mauerzeichen_bauen();
    for (i = 0; i < sizeof(KLEINZEUG); ++i)
        zeichensatz[Z_KRUEMEL * 8 + i] = KLEINZEUG[i];

    TED_ZSATZ_A = (unsigned char)((((unsigned)zeichensatz) >> 8) & 0xFC)
                | (TED_ZSATZ_A & 0x02);
    TED_ZSATZ_M = TED_ZSATZ_M & ~0x04;
    /* Bit 7 turns off the automatic inversion: only that makes the codes
       from 128 up characters of their own, usable as the figure pool. */
    TED_WAAGR = TED_WAAGR | 0x80;

    /* fixed values for the assembly routine */
    am_zshi = (unsigned char)(((unsigned)zeichensatz) >> 8);
    am_tf = C_TUER;
    am_pf = C_PUNKT;

    {   unsigned char i;
        for (i = 0; i < KB; ++i) quadrat[i] = (unsigned)i * i;
    }
}

int main(void)
{
    unsigned char hgrund, rahmen, zsatz, zadr, waagr, ausgang;

    hgrund = TED_HGRUND;
    rahmen = TED_RAHMEN;
    zsatz  = TED_ZSATZ_M;
    zadr   = TED_ZSATZ_A;
    waagr  = TED_WAAGR;

    cursor(0);
    ton_stumm();
    zeichensatz_einrichten();
    formen_vorschieben();

    TED_HGRUND = C_SCHWARZ;
    TED_RAHMEN = C_SCHWARZ;

    for (;;) {
        if (titelbild()) goto ende;

        punkte = 0;
        leben = 3;
        level = 1;
        labyrinth_aufbauen();

        for (;;) {
            figuren_setzen();
            bildschirm_leeren();
            labyrinth_zeichnen();
            statuszeile();
            alle_zeichnen();
            bereit_anzeigen();

            ausgang = runde_spielen();
            ton_stumm();

            if (ausgang == ABBRUCH) goto ende;

            if (ausgang == GESCHAFFT) {
                level_geschafft();
                if (level < 99) ++level;
                labyrinth_aufbauen();
                continue;
            }

            sterben();
            if (--leben == 0) {
                text_zeigen(15, OFFY + AUSY, "GAME OVER", C_ROT);
                bilder_warten(200);
                break;
            }
            statuszeile();
        }
    }

ende:
    ton_stumm();
    TED_WAAGR   = waagr;
    TED_ZSATZ_M = zsatz;
    TED_ZSATZ_A = zadr;
    TED_HGRUND  = hgrund;
    TED_RAHMEN  = rahmen;
    cursor(1);
    clrscr();
    return 0;
}
