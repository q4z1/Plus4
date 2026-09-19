/*
 * Phoenix for the Commodore Plus/4
 * ================================
 *
 * A rebuild of the Atari 2600 version of Phoenix (Atari, 1982): five waves
 * that repeat forever - two flocks of small birds, two flocks of large birds
 * whose wings have to be shot off, and the mothership with the alien queen.
 *
 * The 2600 shows 160 pixels across. The Plus/4 shows 320, so one 2600 pixel
 * is two Plus/4 pixels wide, and the 2600 playfield of 160x192 lands exactly
 * on 40x24 character cells. That is why every shape in this file is stored at
 * 2600 resolution and doubled in width when it is drawn.
 *
 * How the picture is made:
 *
 *   The Plus/4 has no sprites. Bit 7 of $FF07 switches off the TED's habit of
 *   showing codes 128..255 as inverted copies, which leaves all 256 characters
 *   free. They are divided up once (see "Character set"): a strip for the
 *   score, a set of star characters, and a pool that the moving figures write
 *   themselves into on every frame.
 *
 *   The starfield scrolls with the TED's own fine scroll ($FF06 bits 0..2),
 *   so a whole screen of stars moves one pixel per frame for free. Every
 *   eighth pixel the register wraps and the stars move on by one cell.
 *   Because the fine scroll moves *everything*, anything that is supposed to
 *   stand still on the screen - the score, the player's ship - is drawn one
 *   pixel higher for every pixel the scroll has moved. For the figures that
 *   costs nothing (they are drawn at a free vertical offset anyway), for the
 *   score it costs one pass over the score strip per frame.
 *
 * Layout of this file:
 *   1. Hardware          4. Score strip
 *   2. Character set     5. Input
 *   3. Background        6. Game flow
 */

#include <conio.h>
#include <string.h>

/* ======================================================================
 * 1. Hardware
 * ==================================================================== */

#define BILD   ((unsigned char *)0x0C00)
#define FARBE  ((unsigned char *)0x0800)

#define TED_TON1_LO  (*(volatile unsigned char *)0xFF0E)
#define TED_TON2_LO  (*(volatile unsigned char *)0xFF0F)
#define TED_TON_HI   (*(volatile unsigned char *)0xFF10)  /* Bit 0-1: voice 2 high */
#define TED_LAUT     (*(volatile unsigned char *)0xFF11)
#define TED_ZSATZ_M  (*(volatile unsigned char *)0xFF12)  /* Bit 2: font from RAM */
#define TED_ZSATZ_A  (*(volatile unsigned char *)0xFF13)  /* Bit 2-7: font address */
#define TED_SENKR    (*(volatile unsigned char *)0xFF06)  /* Bit 3: 25 rows, 0-2: y scroll */
#define TED_WAAGR    (*(volatile unsigned char *)0xFF07)  /* Bit 7: turn off inversion */
#define TED_HGRUND   (*(volatile unsigned char *)0xFF15)
#define TED_RAHMEN   (*(volatile unsigned char *)0xFF19)
#define TED_RASTER   (*(volatile unsigned char *)0xFF1D)
#define TASTENTOR    (*(volatile unsigned char *)0xFF08)  /* joystick select / read */
#define TASTENREIHE  (*(volatile unsigned char *)0xFD30)  /* keyboard row select    */
#define ROM_EIN      (*(volatile unsigned char *)0xFF3E)
#define RAM_EIN      (*(volatile unsigned char *)0xFF3F)

/* Colors are brightness * 16 + hue. Hue 1 is white, so $11..$71 is a grey
   ramp; the strong hues sit at brightness 3 to 6. */
#define C_SCHWARZ  0x00
#define C_WEISS    0x71
#define C_GRAU     0x41
#define C_DUNKEL   0x21
#define C_ROT      0x42
#define C_ORANGE   0x58
#define C_GELB     0x77
#define C_GRUEN    0x55
#define C_BLAU     0x46
#define C_HELLBLAU 0x6D
#define C_VIOLETT  0x54
#define C_TUERKIS  0x5D

/* A few things are needed before they are written down. */
static void bild_warten(void);
static void klang_weiter(void);

#define BREITE 40      /* cells across */
#define ZEILEN 25      /* cells down - 24 are visible, one is the scroll edge */

/* ======================================================================
 * 2. Character set
 *
 * 0..39    the score strip: 20 columns, top row and bottom row
 * 40..71   stars: 4 horizontal by 8 vertical positions inside the cell
 * 72       an empty cell
 * 73..255  pool for everything that moves, and for text on the title screen
 * ==================================================================== */

#define Z_PUNKTE   0
#define Z_STERN   40
#define Z_LEER    72
#define Z_VORRAT  73

static unsigned char zeichenspeicher[2048 + 2047];
static unsigned char *zeichensatz;
static unsigned rom_index;
static unsigned char romfont[512];    /* the first 64 ROM characters       */

/*
 * Fetches the ROM character set. cc65 banks the ROM out on the Plus/4 to use
 * all of memory, so the character generator at $D000 has to be switched back
 * in for a moment. Nothing inside that window may touch the C stack - it
 * lives at $F500-$FCFF and would be hidden by the ROM - hence a global loop
 * variable and no function call.
 */
static void font_aus_rom(void)
{
    __asm__("sei");
    ROM_EIN = 0;
    for (rom_index = 0; rom_index < 512; ++rom_index)
        romfont[rom_index] = ((unsigned char *)0xD000)[rom_index];
    RAM_EIN = 0;
    __asm__("cli");
}

/* Doubles the width of a nibble: %1010 becomes %11001100. Every shape in the
   game is stored at 2600 resolution and goes through this table. */
static const unsigned char VERDOPPELT[16] = {
    0x00, 0x03, 0x0C, 0x0F, 0x30, 0x33, 0x3C, 0x3F,
    0xC0, 0xC3, 0xCC, 0xCF, 0xF0, 0xF3, 0xFC, 0xFF
};

/*
 * Builds the star characters: a star is one 2600 pixel, so two Plus/4 pixels
 * wide and one high. Code 32 + y * 4 + x carries it at pixel row y and at
 * pixel column x * 2.
 */
static void sternzeichen_bauen(void)
{
    unsigned char y, x, i;
    unsigned char *z;

    for (y = 0; y < 8; ++y) {
        for (x = 0; x < 4; ++x) {
            z = zeichensatz + (Z_STERN + y * 4 + x) * 8;
            for (i = 0; i < 8; ++i) z[i] = 0;
            z[y] = (unsigned char)(0xC0 >> (x + x));
        }
    }
}

static void zeichensatz_einrichten(void)
{
    unsigned i;

    /* The character set has to start on an address divisible by 2048. */
    zeichensatz = (unsigned char *)(((unsigned)zeichenspeicher + 2047) & 0xF800);
    for (i = 0; i < 2048; ++i) zeichensatz[i] = 0;

    font_aus_rom();
    sternzeichen_bauen();

    /* Tell the TED where the character set is and that it sits in RAM. */
    TED_ZSATZ_A = (unsigned char)((((unsigned)zeichensatz) >> 8) & 0xFC)
                | (TED_ZSATZ_A & 0x02);
    TED_ZSATZ_M = TED_ZSATZ_M & ~0x04;

    /* All 256 characters of our own instead of 128 plus inverted copies. */
    TED_WAAGR = TED_WAAGR | 0x80;
}

/* ======================================================================
 * 3. Background: the scrolling starfield
 *
 * The screen memory is never moved. A shadow copy holds what belongs on each
 * cell when nothing covers it, so a figure that leaves a cell can put the
 * background back without knowing what was there.
 * ==================================================================== */

static unsigned char hg_zeichen[ZEILEN * BREITE];
static unsigned char hg_farbe[ZEILEN * BREITE];
static unsigned zeilenanfang[ZEILEN];      /* row * 40, precomputed        */

unsigned durchlaeufe;                      /* passes through the game loop  */
static unsigned char scrollpos;            /* pixels scrolled, only 0..7 matter */
static unsigned char yfein;                /* scrollpos & 7                */

#define PUNKTE_SP 20                   /* width of the score strip in cells */

#define STERNE 26
static unsigned char stern_sp[STERNE];     /* cell column                  */
static unsigned char stern_ze[STERNE];     /* cell row                     */
static unsigned char stern_z[STERNE];      /* character code               */
static unsigned char stern_f[STERNE];      /* color                        */

static unsigned zufallswert = 0x2B7D;

static unsigned char zufall(void)
{
    zufallswert = (unsigned)(zufallswert * 5 + 12345);
    return (unsigned char)(zufallswert >> 7);
}

static unsigned char anz_zeile;        /* cell row the score sits on       */

/*
 * Notes what belongs on a cell and shows it - unless the score is standing
 * on that cell. The shadow is kept up to date either way, so the star turns
 * up again the moment the score moves off it.
 */
static void hintergrund_setzen(unsigned char sp, unsigned char ze,
                               unsigned char zeichen, unsigned char farbe)
{
    unsigned p = zeilenanfang[ze] + sp;
    hg_zeichen[p] = zeichen;
    hg_farbe[p] = farbe;
    if (sp < PUNKTE_SP && ze >= anz_zeile && ze <= (unsigned char)(anz_zeile + 1))
        return;
    BILD[p] = zeichen;
    FARBE[p] = farbe;
}

/* Gives one star a fresh place in the given row. */
static void stern_neu(unsigned char i, unsigned char ze)
{
    static const unsigned char HELL[4] = { C_DUNKEL, C_GRAU, C_GRAU, C_WEISS };

    stern_sp[i] = (unsigned char)(zufall() % BREITE);
    stern_ze[i] = ze;
    stern_z[i] = (unsigned char)(Z_STERN + (zufall() & 31));
    stern_f[i] = HELL[zufall() & 3];
}

static void sternenhimmel_aufbauen(void)
{
    unsigned char i;
    unsigned p;

    for (p = 0; p < ZEILEN * BREITE; ++p) {
        hg_zeichen[p] = Z_LEER;
        hg_farbe[p] = C_SCHWARZ;
        BILD[p] = Z_LEER;
        FARBE[p] = C_SCHWARZ;
    }

    for (i = 0; i < STERNE; ++i) {
        stern_neu(i, (unsigned char)(zufall() % ZEILEN));
        hintergrund_setzen(stern_sp[i], stern_ze[i], stern_z[i], stern_f[i]);
    }
}

/*
 * One pixel further down. Every eighth pixel the fine scroll has used up its
 * range: it starts over and the stars move on by one cell, which is the only
 * moment the screen memory is touched at all.
 */
static void scrollen(void)
{
    unsigned char i, ze;

    ++scrollpos;
    yfein = (unsigned char)(scrollpos & 7);
    if (yfein != 0) return;

    for (i = 0; i < STERNE; ++i) {
        hintergrund_setzen(stern_sp[i], stern_ze[i], Z_LEER, C_SCHWARZ);
        ze = (unsigned char)(stern_ze[i] + 1);
        if (ze >= ZEILEN) {
            stern_neu(i, 0);
        } else {
            stern_ze[i] = ze;
        }
        hintergrund_setzen(stern_sp[i], stern_ze[i], stern_z[i], stern_f[i]);
    }
}

/* ======================================================================
 * 4. Score strip
 *
 * Score and remaining ships stand still while everything else scrolls, so
 * they are redrawn with a vertical offset that cancels the fine scroll out.
 * The strip is 16 cells wide and 8 pixels tall; because of the offset it
 * covers two cell rows, and which two changes as the scroll runs.
 * ==================================================================== */

/* The strip as pixels, one column after the other, and each column padded
   with seven zero bytes above and below - then the shifted copy that has to
   go into the character set on every frame is simply sixteen bytes read out
   of the middle of it. */
#define ANZ_H 22
static unsigned char anz_bild[PUNKTE_SP][ANZ_H];
static unsigned char anz_gesetzt;              /* has it been placed yet?  */

static unsigned long punkte;
static unsigned char leben;

/* The player's ship as it appears next to the score, one 2600 pixel per bit. */
static const unsigned char SCHIFF_KLEIN[8] = {
    0x00, 0x10, 0x10, 0x38, 0x38, 0x7C, 0x6C, 0x00
};

/* Draws score and ships into the pixel strip. Only called when they change. */
static void anzeige_bauen(void)
{
    unsigned char sp, r, i, ziffer;
    unsigned long rest;
    unsigned char stellen[6];
    const unsigned char *q;

    for (sp = 0; sp < PUNKTE_SP; ++sp)
        for (r = 0; r < ANZ_H; ++r)
            anz_bild[sp][r] = 0;

    /* Six digits, leading zeros kept - that is how the 2600 shows it. */
    rest = punkte;
    for (i = 6; i > 0; --i) {
        stellen[i - 1] = (unsigned char)(rest % 10);
        rest /= 10;
    }

    for (i = 0; i < 6; ++i) {
        ziffer = stellen[i];
        q = romfont + (48 + ziffer) * 8;       /* screen code of '0' is 48 */
        for (r = 0; r < 8; ++r) {
            anz_bild[i + i][7 + r]     = VERDOPPELT[q[r] >> 4];
            anz_bild[i + i + 1][7 + r] = VERDOPPELT[q[r] & 15];
        }
    }

    /* Remaining ships right of the score, two cells each like everything
       else that is eight 2600 pixels wide. */
    for (i = 0; i < 4; ++i) {
        if (i + 1 >= leben) break;
        for (r = 0; r < 8; ++r) {
            anz_bild[12 + i + i][7 + r]     = VERDOPPELT[SCHIFF_KLEIN[r] >> 4];
            anz_bild[12 + i + i + 1][7 + r] = VERDOPPELT[SCHIFF_KLEIN[r] & 15];
        }
    }
}

static void punkte_dazu(unsigned wert)
{
    unsigned long alt = punkte;
    punkte += wert;
    /* one extra ship at five thousand, as on the 2600 */
    if (alt < 5000UL && punkte >= 5000UL && leben < 6) ++leben;
    anzeige_bauen();
}

/*
 * Copies the strip into the character set, shifted down by as many pixels as
 * the fine scroll has moved, and puts the two rows of characters on screen.
 *
 * The shifting is the one thing here that happens on every single frame, so
 * it is written out in assembly - in C it cost eleven frames of the sixty
 * that a pass through the game took.
 */
unsigned char *an_quelle;
unsigned char *an_oben;
unsigned char *an_unten;

/* Copies all twenty columns of the strip into the character set at once.
   Source, top row and bottom row all advance in step, so the whole thing is
   one loop with no addressing arithmetic worth the name. */
static void anzeige_streifen(void)
{
    __asm__(
    "lda _an_quelle\n"
    "sta ptr1\n"
    "lda _an_quelle+1\n"
    "sta ptr1+1\n"
    "lda _an_oben\n"
    "sta ptr2\n"
    "lda _an_oben+1\n"
    "sta ptr2+1\n"
    "lda _an_unten\n"
    "sta ptr3\n"
    "lda _an_unten+1\n"
    "sta ptr3+1\n"
    "lda #%b\n"
    "sta tmp2\n"
    ";  sreg is a second source pointer, eight bytes further down\n"
    "lda ptr1\n"
    "clc\n"
    "adc #$08\n"
    "sta sreg\n"
    "lda ptr1+1\n"
    "adc #$00\n"
    "sta sreg+1\n"

    "anzsp:\n"
    "ldy #$07\n"
    "anzby:\n"
    "lda (ptr1),y\n"
    "sta (ptr2),y\n"
    "lda (sreg),y\n"
    "sta (ptr3),y\n"
    "dey\n"
    "bpl anzby\n"

    ";  next column: both sources on by 22, both targets by 8\n"
    "lda ptr1\n"
    "clc\n"
    "adc #%b\n"
    "sta ptr1\n"
    "bcc anzn0\n"
    "inc ptr1+1\n"
    "anzn0:\n"
    "lda sreg\n"
    "clc\n"
    "adc #%b\n"
    "sta sreg\n"
    "bcc anzn1\n"
    "inc sreg+1\n"
    "anzn1:\n"
    "lda ptr2\n"
    "clc\n"
    "adc #$08\n"
    "sta ptr2\n"
    "bcc anzn2\n"
    "inc ptr2+1\n"
    "anzn2:\n"
    "lda ptr3\n"
    "clc\n"
    "adc #$08\n"
    "sta ptr3\n"
    "bcc anzn3\n"
    "inc ptr3+1\n"
    "anzn3:\n"
    "dec tmp2\n"
    "bne anzsp\n"
    , (unsigned char)PUNKTE_SP, (unsigned char)ANZ_H, (unsigned char)ANZ_H);
}

static void anzeige_zeichnen(void)
{
    unsigned char sp, versatz, ze, r;
    unsigned p;

    /* The strip is to stand at screen pixel row 0. The fine scroll pushes
       everything down by yfein, so the strip is drawn that much higher. */
    versatz = (unsigned char)(8 - yfein);      /* 1..8 */
    ze = (unsigned char)(versatz >> 3);        /* 0 or 1 */
    versatz = (unsigned char)(versatz & 7);

    if (ze != anz_zeile || !anz_gesetzt) {
        if (anz_gesetzt) {
            /* Hand the rows we no longer stand on back to the background. */
            for (r = 0; r < 2; ++r) {
                p = zeilenanfang[anz_zeile + r];
                for (sp = 0; sp < PUNKTE_SP; ++sp) {
                    BILD[p + sp] = hg_zeichen[p + sp];
                    FARBE[p + sp] = hg_farbe[p + sp];
                }
            }
        }
        anz_zeile = ze;
        anz_gesetzt = 1;
        for (r = 0; r < 2; ++r) {
            p = zeilenanfang[ze + r];
            for (sp = 0; sp < PUNKTE_SP; ++sp) {
                BILD[p + sp] = (unsigned char)(Z_PUNKTE + r * PUNKTE_SP + sp);
                FARBE[p + sp] = C_WEISS;
            }
        }
    }

    an_quelle = &anz_bild[0][7 - versatz];
    an_oben  = zeichensatz + (Z_PUNKTE * 8);
    an_unten = zeichensatz + ((Z_PUNKTE + PUNKTE_SP) * 8);
    anzeige_streifen();
}

/* ======================================================================
 * 5. Input
 *
 * Keyboard and joysticks hang on the same port, and two latches feed it:
 * $FD30 and $FF08. The KERNAL's own scan routine at $DB70 settles what to
 * write where - it puts the row on *both* of them and then reads $FF08:
 *
 *     sta $FD30
 *     sta $FF08
 *     lda $FF08
 *
 * Writing $FF to $FF08 instead, as this file did at first, selects no row at
 * all, and then nothing is ever pressed. Reading $FF08 gives a zero bit per
 * closed contact; $FF means nobody is touching that row.
 *
 * And it has to be read *twice*. The write leaves its own value on the data
 * bus, and the TED samples the keyboard lines a cycle later - so a read in
 * the instruction right after the write hands back what was just written,
 * which looks exactly like the key on that row's own line being held down.
 * With the row $7F that is Run/Stop, and the game quit the moment it started.
 * The second read gets the TED's own sample.
 *
 * A row value with bit 1 or 2 low would also switch a joystick onto the same
 * lines. None of the rows used here does, so keyboard and joystick stay
 * apart: the joystick is asked with no keyboard row selected at all.
 *
 * The matrix, read out of the KERNAL's own table at $E026 rather than taken
 * from documentation (bit 0 first):
 *
 *   $DF  crsr down, P, L, crsr up, ., :, -, ,
 *   $BF  crsr left, *, ;, crsr right, Esc, =, +, /
 *   $7F  1, Clr/Home, F3, 2, Space, Shift, Q, Run/Stop
 * ==================================================================== */

#define ST_LINKS   0x01
#define ST_RECHTS  0x02
#define ST_SCHILD  0x04
#define ST_FEUER   0x08
#define ST_ENDE    0x10

static unsigned char tasten_lesen(unsigned char reihe)
{
    unsigned char wert;

    __asm__("sei");
    TASTENREIHE = reihe;
    TASTENTOR = reihe;
    wert = TASTENTOR;            /* still the value the write left behind */
    wert = TASTENTOR;            /* now what the TED sampled              */
    TASTENTOR = 0xFF;
    __asm__("cli");

    return wert;
}

static unsigned char joystick_lesen(void)
{
    unsigned char wert;

    __asm__("sei");
    TASTENREIHE = 0xFF;          /* no keyboard row, so no keys mixed in */
    TASTENTOR = 0xFB;            /* bit 2 low selects joystick 1         */
    wert = TASTENTOR;            /* the write's own value, still on the bus */
    wert = TASTENTOR;            /* the sampled one                         */
    TASTENTOR = 0xFF;
    __asm__("cli");

    return wert;
}

/* Reads the state of everything right now. */
static unsigned char steuerung_roh(void)
{
    unsigned char s = 0, w;

    w = joystick_lesen();
    if (!(w & 0x02)) s |= ST_SCHILD;      /* stick pulled towards you */
    if (!(w & 0x04)) s |= ST_LINKS;
    if (!(w & 0x08)) s |= ST_RECHTS;
    if (!(w & 0x40)) s |= ST_FEUER;

    w = tasten_lesen(0xBF);               /* cursor left, cursor right */
    if (!(w & 0x01)) s |= ST_LINKS;
    if (!(w & 0x08)) s |= ST_RECHTS;

    w = tasten_lesen(0xDF);               /* cursor down */
    if (!(w & 0x01)) s |= ST_SCHILD;

    w = tasten_lesen(0x7F);               /* space, Q, Run/Stop */
    if (!(w & 0x10)) s |= ST_FEUER;
    if (!(w & 0x40)) s |= ST_ENDE;
    if (!(w & 0x80)) s |= ST_ENDE;

    return s;
}

/*
 * A pass through the game takes an eighth of a second, and a tap on a key is
 * often shorter than that - asked once per pass, it would simply not be
 * there. So the port is read again while the program waits for the beam, and
 * anything seen in between is remembered until the next pass picks it up.
 * For a key that is held down this changes nothing.
 */
static unsigned char eingang_gesehen;

static void eingang_abtasten(void)
{
    eingang_gesehen |= steuerung_roh();
}

static unsigned char steuerung(void)
{
    unsigned char s = (unsigned char)(eingang_gesehen | steuerung_roh());
    eingang_gesehen = 0;
    return s;
}

/* ======================================================================
 * 6. Figures
 *
 * Every shape is stored the way the 2600 holds it: one bit per 2600 pixel,
 * one byte per row. Drawing doubles that to two Plus/4 pixels per bit, so a
 * shape eight 2600 pixels wide covers two bytes on screen - and because a
 * figure may stand anywhere, the doubled shape is kept ready in all four
 * possible horizontal positions (0, 2, 4 and 6 pixels). That is what
 * formen_vorschieben() builds at startup.
 *
 * Each figure owns a fixed group of pool characters, one per cell it can
 * cover. The group never changes, so a figure that stays put keeps writing
 * the same characters and nothing ever flickers; only when it moves to
 * another cell does the screen memory change at all.
 * ==================================================================== */

#define FIG_N     14         /* ship and birds                             */
#define SCH_N      6         /* shot, eggs and the force field             */
#define SCH_SP     3         /* a shot is never wider than three cells     */
#define SCH_ZE     2
#define SCH_ZN     (SCH_SP * SCH_ZE)

/*
 * How many characters a figure needs depends on its size, and the sizes
 * differ from wave to wave: twelve small birds of six characters fit in the
 * same pool as eight large ones of fifteen. The pool is therefore handed out
 * again whenever a wave starts.
 */
/*
 * Every figure owns its own run of characters, so the picture of a figure is
 * one unbroken block of memory in the character set. The slots are handed out
 * once; there are enough characters for all of them.
 */
/*
 * Every figure owns its own run of characters, so the picture of a figure is
 * one unbroken block of memory in the character set. How many it needs
 * depends on the wave - a small bird covers six cells, a large one fifteen -
 * so the pool is handed out again whenever a wave starts.
 */
static unsigned char fig_basis[FIG_N + SCH_N];   /* first character code    */
static unsigned fig_zeichen[FIG_N + SCH_N];      /* and its byte offset     */
static unsigned char fig_n;                      /* slots for birds         */

static void vorrat_verteilen(unsigned char gross, unsigned char voegel)
{
    unsigned char i, code;

    fig_n = voegel;
    code = Z_VORRAT;
    fig_basis[0] = code;                 /* the ship is always small */
    fig_zeichen[0] = (unsigned)code << 3;
    code = (unsigned char)(code + 8);

    for (i = 1; i < FIG_N; ++i) {
        fig_basis[i] = code;
        fig_zeichen[i] = (unsigned)code << 3;
        if (i <= voegel) code = (unsigned char)(code + gross);
    }
    for (i = 0; i < SCH_N; ++i) {
        fig_basis[FIG_N + i] = code;
        fig_zeichen[FIG_N + i] = (unsigned)code << 3;
        code = (unsigned char)(code + 8);
    }
}

/* ---- the shapes, one bit per 2600 pixel -------------------------------- */

static const unsigned char SCHIFF[8] = {
    0x18,   /*    ##      */
    0x18,   /*    ##      */
    0x3C,   /*   ####     */
    0x3C,   /*   ####     */
    0x7E,   /*  ######    */
    0xFF,   /* ########   */
    0xDB,   /* ## ## ##   */
    0x99    /* #  ##  #   */
};

static const unsigned char SCHUSS[4] = {
    0x18, 0x18, 0x18, 0x18
};

/* The small bird of waves one and two, wings up, out and down. */
static const unsigned char VOGEL_HOCH[8] = {
    0xC3,   /* ##    ##   */
    0x66,   /*  ##  ##    */
    0x3C,   /*   ####     */
    0x3C,   /*   ####     */
    0x18,   /*    ##      */
    0x00,
    0x00,
    0x00
};

static const unsigned char VOGEL_FLACH[8] = {
    0x00,
    0x00,
    0xFF,   /* ########   */
    0x7E,   /*  ######    */
    0x3C,   /*   ####     */
    0x18,   /*    ##      */
    0x00,
    0x00
};

static const unsigned char VOGEL_TIEF[8] = {
    0x00,
    0x00,
    0x18,   /*    ##      */
    0x3C,   /*   ####     */
    0x3C,   /*   ####     */
    0x66,   /*  ##  ##    */
    0xC3,   /* ##    ##   */
    0x00
};

/*
 * The large bird of waves three and four, sixteen 2600 pixels across. The
 * outer five pixels on each side are its wings - that is what a shot takes
 * off, and only a hit in the middle six kills it.
 */
static const unsigned char GROSS_HOCH[24] = {
    0xC0, 0x03,   /* ##                          ##   */
    0xF0, 0x0F,   /* ####                      ####   */
    0x78, 0x1E,   /*  ####                    ####    */
    0x3C, 0x3C,   /*   ####                  ####     */
    0x1F, 0xF8,   /*    #####              #####      */
    0x0F, 0xF0,   /*     ########      ########       */
    0x07, 0xE0,   /*      ######        ######        */
    0x0F, 0xF0,   /*     ########      ########       */
    0x1F, 0xF8,   /*    ##########    ##########      */
    0x1B, 0xD8,   /*    ## ####        #### ##        */
    0x11, 0x88,   /*    #   #            #   #        */
    0x00, 0x00
};

static const unsigned char GROSS_TIEF[24] = {
    0x00, 0x00,
    0x07, 0xE0,
    0x0F, 0xF0,
    0x1F, 0xF8,
    0x3F, 0xFC,
    0x7F, 0xFE,
    0xFF, 0xFF,
    0x7C, 0x3E,
    0x38, 0x1C,
    0x1B, 0xD8,
    0x11, 0x88,
    0x00, 0x00
};

/* What a bird leaves behind, two frames of it. */
static const unsigned char KNALL1[8] = {
    0x00, 0x18, 0x24, 0x42, 0x42, 0x24, 0x18, 0x00
};

static const unsigned char KNALL2[8] = {
    0x81, 0x42, 0x00, 0x24, 0x24, 0x00, 0x42, 0x81
};

/* What the birds drop. */
static const unsigned char EI[3] = {
    0x18, 0x3C, 0x18
};

/* The force field above the ship, shimmering in two frames. */
static const unsigned char SCHILD1[3] = {
    0xDB, 0x66, 0x00
};

static const unsigned char SCHILD2[3] = {
    0x66, 0xDB, 0x00
};

/* ---- ready made character blocks ---------------------------------------
 *
 * A figure can stand at four horizontal and eight vertical positions inside
 * its cells, so there are 32 ways it can look. All 32 are worked out when a
 * wave starts and kept as finished blocks of characters. Drawing a figure is
 * then no more than copying its block into the character set and putting the
 * codes on the screen - no shifting, no merging, no arithmetic per pixel row.
 *
 * That is what makes the whole thing fast enough. Working the cells out on
 * every frame cost about 4000 cycles per figure; a frame has 17784.
 *
 * The blocks are built afresh for each kind of wave, because the large birds
 * of waves three and four need five cells by three where a small one needs
 * three by two, and both sets at once would not fit in memory.
 * ---------------------------------------------------------------------- */

#define FORM_SCHIFF  0
#define FORM_SCHUSS  1
#define FORM_KNALL   2    /* two frames                                   */
#define FORM_EI      4
#define FORM_SCHILD  5    /* two frames                                   */
#define FORM_VOGEL   7    /* small bird, three flapping frames            */
#define FORM_GROSS   7    /* large bird, two flapping frames              */
#define FORM_GROSS_L 9    /* right wing shot off                          */
#define FORM_GROSS_R 10   /* left wing shot off                           */
#define FORM_GROSS_0 11   /* both wings gone                              */
#define FORMEN_N    12

/*
 * Room for all views of all shapes of one wave. The largest set is waves
 * three and four: seven small shapes at 48 bytes a view plus five large ones
 * at 120, each in 32 views - 29952 bytes.
 */
#define BLOCKRAUM 30208

static unsigned char bloecke[BLOCKRAUM];
static unsigned blockende;
static unsigned char *form_block[FORMEN_N];  /* where each shape starts     */
static unsigned char f_sp[FORMEN_N];         /* cells across               */
static unsigned char f_ze[FORMEN_N];         /* cells down                 */
static unsigned char f_n[FORMEN_N];          /* characters it uses         */
static unsigned form_stufe[FORMEN_N];        /* bytes from one view to next */
static unsigned char *zeile_bild[ZEILEN];    /* screen address of each row  */

/*
 * Works out all 32 views of one shape. The shape is stored one bit per 2600
 * pixel; it is doubled in width here and shifted to the right by twice the
 * horizontal position, which is why a shape eight 2600 pixels wide can reach
 * into three cells.
 *
 * maske1 and maske2 are laid over the shape data first. That is how the
 * large birds lose a wing: the same picture, with one side masked away.
 */
static void form_ablegen(unsigned char nr, const unsigned char *daten,
                         unsigned char w2, unsigned char h,
                         unsigned char maske1, unsigned char maske2)
{
    unsigned char zeile[16][5];
    unsigned char breit[4];
    unsigned char p, r, i, w, s, voff, py, zr, sp, ze, roh;
    unsigned char *block;
    unsigned gr;

    w = (unsigned char)(w2 + w2);
    sp = (unsigned char)(w + 1);
    ze = (unsigned char)((h + 14) >> 3);
    f_sp[nr] = sp;
    f_ze[nr] = ze;
    f_n[nr] = (unsigned char)(sp * ze);
    gr = (unsigned)f_n[nr] * 8;
    form_stufe[nr] = gr;
    form_block[nr] = bloecke + blockende;
    blockende += gr * 32;

    for (p = 0; p < 4; ++p) {
        s = (unsigned char)(p + p);
        for (r = 0; r < h; ++r) {
            for (i = 0; i < w2; ++i) {
                roh = daten[r * w2 + i];
                roh = (unsigned char)(roh & (i ? maske2 : maske1));
                breit[i + i]     = VERDOPPELT[roh >> 4];
                breit[i + i + 1] = VERDOPPELT[roh & 15];
            }
            for (i = 0; i < sp; ++i) zeile[r][i] = 0;
            if (s == 0) {
                for (i = 0; i < w; ++i) zeile[r][i] = breit[i];
            } else {
                zeile[r][0] = (unsigned char)(breit[0] >> s);
                for (i = 1; i < w; ++i)
                    zeile[r][i] = (unsigned char)((breit[i - 1] << (8 - s))
                                                | (breit[i] >> s));
                zeile[r][w] = (unsigned char)(breit[w - 1] << (8 - s));
            }
        }

        for (voff = 0; voff < 8; ++voff) {
            block = form_block[nr] + ((unsigned)(p * 8 + voff) * gr);
            for (i = 0; i < gr; ++i) block[i] = 0;
            for (r = 0; r < h; ++r) {
                py = (unsigned char)(voff + r);
                zr = (unsigned char)(py >> 3);
                py = (unsigned char)(py & 7);
                if (zr >= ze) break;
                for (i = 0; i < sp; ++i)
                    block[(zr * sp + i) * 8 + py] = zeile[r][i];
            }
        }
    }
}

/* Everything that is on the screen no matter which wave it is. */
static void formen_grundstock(void)
{
    blockende = 0;
    form_ablegen(FORM_SCHIFF, SCHIFF, 1, 8, 0xFF, 0xFF);
    form_ablegen(FORM_SCHUSS, SCHUSS, 1, 4, 0xFF, 0xFF);
    form_ablegen(FORM_KNALL,     KNALL1, 1, 8, 0xFF, 0xFF);
    form_ablegen(FORM_KNALL + 1, KNALL2, 1, 8, 0xFF, 0xFF);
    form_ablegen(FORM_EI, EI, 1, 3, 0xFF, 0xFF);
    form_ablegen(FORM_SCHILD,     SCHILD1, 1, 3, 0xFF, 0xFF);
    form_ablegen(FORM_SCHILD + 1, SCHILD2, 1, 3, 0xFF, 0xFF);
}

static void formen_klein(void)
{
    formen_grundstock();
    form_ablegen(FORM_VOGEL,     VOGEL_HOCH,  1, 8, 0xFF, 0xFF);
    form_ablegen(FORM_VOGEL + 1, VOGEL_FLACH, 1, 8, 0xFF, 0xFF);
    form_ablegen(FORM_VOGEL + 2, VOGEL_TIEF,  1, 8, 0xFF, 0xFF);
}

/*
 * The large birds. Their wings are the outer five 2600 pixels on each side,
 * so the shot off states are the same picture with one side masked out - no
 * second drawing needed, and no second set of blocks either.
 */
#define FL_LINKS  0xF8
#define FL_RECHTS 0x1F
#define FL_KEINE  0x07

static void formen_gross(void)
{
    formen_grundstock();
    form_ablegen(FORM_GROSS,     GROSS_HOCH, 2, 12, 0xFF, 0xFF);
    form_ablegen(FORM_GROSS + 1, GROSS_TIEF, 2, 12, 0xFF, 0xFF);
    form_ablegen(FORM_GROSS_L, GROSS_TIEF, 2, 12, 0xFF, (unsigned char)~FL_RECHTS);
    form_ablegen(FORM_GROSS_R, GROSS_TIEF, 2, 12, (unsigned char)~FL_LINKS, 0xFF);
    form_ablegen(FORM_GROSS_0, GROSS_TIEF, 2, 12, (unsigned char)~FL_LINKS,
                 (unsigned char)~FL_RECHTS);
}

/* ---- what a figure covers at the moment -------------------------------- */

static unsigned char bel_sp[FIG_N + SCH_N];    /* left cell                 */
static unsigned char bel_ze[FIG_N + SCH_N];    /* top cell                  */
static unsigned char bel_nsp[FIG_N + SCH_N];   /* width in cells, 0 = none  */
static unsigned char bel_nze[FIG_N + SCH_N];

static void figur_loeschen(unsigned char nr);

/*
 * Copies one block into the character set and puts the codes and colours of
 * the cells it covers on the screen. Everything it needs is already worked
 * out; this is a straight copy loop, which is exactly why it is fast.
 */
unsigned char *fz_block;
unsigned char *fz_ziel;
unsigned char *fz_bild;
unsigned char fz_code, fz_farbe, fz_nsp, fz_nze, fz_laenge, fz_stufe;

static void figur_bloecken(void)
{
    __asm__(
    "lda %v\n"     "sta ptr1\n"
    "lda %v+1\n"   "sta ptr1+1\n"
    "lda %v\n"     "sta ptr2\n"
    "lda %v+1\n"   "sta ptr2+1\n"
    ";  the characters of a figure lie next to each other, so its whole\n"
    ";  picture is one run of bytes\n"
    "ldy %v\n"
    "fzcp:\n"
    "lda (ptr1),y\n"
    "sta (ptr2),y\n"
    "dey\n"
    "bpl fzcp\n"

    "lda %v\n"     "sta ptr3\n"
    "lda %v+1\n"   "sta ptr3+1\n"
    "lda %v\n"     "sta tmp1\n"
    "lda %v\n"     "sta tmp2\n"

    "fzrow:\n"
    "ldy #$00\n"
    "ldx %v\n"
    "lda tmp1\n"
    "sta tmp3\n"
    "fzcell:\n"
    "lda tmp3\n"
    "sta (ptr3),y\n"
    "inc tmp3\n"
    "iny\n"
    "dex\n"
    "bne fzcell\n"

    ";  the colour memory sits exactly $400 below the screen\n"
    "lda ptr3\n"
    "sta sreg\n"
    "lda ptr3+1\n"
    "sec\n"
    "sbc #$04\n"
    "sta sreg+1\n"
    "ldy #$00\n"
    "ldx %v\n"
    "lda %v\n"
    "fzcol:\n"
    "sta (sreg),y\n"
    "iny\n"
    "dex\n"
    "bne fzcol\n"

    "lda tmp1\n"
    "clc\n"
    "adc %v\n"
    "sta tmp1\n"
    "lda ptr3\n"
    "clc\n"
    "adc #$28\n"
    "sta ptr3\n"
    "bcc fzn1\n"
    "inc ptr3+1\n"
    "fzn1:\n"
    "dec tmp2\n"
    "bne fzrow\n"
    , fz_block, fz_block, fz_ziel, fz_ziel, fz_laenge,
      fz_bild, fz_bild, fz_code, fz_nze, fz_nsp, fz_nsp, fz_farbe, fz_stufe);
}

/*
 * Draws a figure and releases the cells it no longer needs.
 *
 * nr      slot, 0..FIG_N-1 for figures, then the shot slots
 * form    which shape
 * x2      left edge in 2600 pixels
 * sy      top edge in screen pixels, 0 is the top of the playfield
 */
static void figur_malen(unsigned char nr, unsigned char form,
                        unsigned char x2, unsigned char sy, unsigned char farbe)
{
    unsigned char sp, ze, nsp, nze, voff, c, r, alt, zeende, spende, s2;
    unsigned p;

    voff = (unsigned char)(x2 & 3);            /* horizontal position */
    sp = (unsigned char)(x2 >> 2);
    ze = (unsigned char)(sy + 8 - yfein);
    voff = (unsigned char)((voff << 3) + (ze & 7));
    ze = (unsigned char)(ze >> 3);

    /* Every comparison here is between bytes on purpose: written against
       plain constants cc65 widens them to sixteen bits and pushes both sides
       through its software stack, which costs more than the drawing itself. */
    if (ze > (unsigned char)(ZEILEN - 1) || sp > (unsigned char)(BREITE - 1)) {
        figur_loeschen(nr);
        return;
    }

    nsp = f_sp[form];
    nze = f_ze[form];
    if ((unsigned char)(ze + nze) > (unsigned char)ZEILEN)
        nze = (unsigned char)(ZEILEN - ze);
    if ((unsigned char)(sp + nsp) > (unsigned char)BREITE)
        nsp = (unsigned char)(BREITE - sp);
    zeende = (unsigned char)(ze + nze);
    spende = (unsigned char)(sp + nsp);

    /* Give back everything the figure used to cover and no longer does.
       While it stays on the same cells there is nothing to give back, and
       that is the usual case - a figure crosses a cell border only now and
       then. */
    if (bel_nsp[nr] && (bel_nsp[nr] != nsp || bel_nze[nr] != nze ||
                        bel_sp[nr] != sp || bel_ze[nr] != ze)) {
        for (r = 0; r < bel_nze[nr]; ++r) {
            alt = (unsigned char)(bel_ze[nr] + r);
            p = zeilenanfang[alt] + bel_sp[nr];
            for (c = 0; c < bel_nsp[nr]; ++c) {
                s2 = (unsigned char)(bel_sp[nr] + c);
                if (alt >= ze && alt < zeende && s2 >= sp && s2 < spende) {
                    ++p;
                    continue;
                }
                BILD[p] = hg_zeichen[p];
                FARBE[p] = hg_farbe[p];
                ++p;
            }
        }
    }

    bel_sp[nr] = sp; bel_ze[nr] = ze;
    bel_nsp[nr] = nsp; bel_nze[nr] = nze;

    fz_block = form_block[form] + form_stufe[form] * voff;
    fz_ziel = zeichensatz + fig_zeichen[nr];
    fz_bild = zeile_bild[ze] + sp;
    fz_code = fig_basis[nr];
    fz_farbe = farbe;
    fz_nsp = nsp;
    fz_nze = nze;
    fz_stufe = f_sp[form];
    fz_laenge = (unsigned char)(f_n[form] * 8 - 1);
    figur_bloecken();
}

/* Takes a figure off the screen. */
static void figur_loeschen(unsigned char nr)
{
    unsigned char r, c;
    unsigned p;

    if (!bel_nsp[nr]) return;
    for (r = 0; r < bel_nze[nr]; ++r) {
        p = zeilenanfang[bel_ze[nr] + r] + bel_sp[nr];
        for (c = 0; c < bel_nsp[nr]; ++c) {
            BILD[p] = hg_zeichen[p];
            FARBE[p] = hg_farbe[p];
            ++p;
        }
    }
    bel_nsp[nr] = 0;
}

/* ======================================================================
 * 7. Sound
 *
 * The TED has two voices and one volume for both. Voice 2 does the noises -
 * it can be switched to noise, which is what every explosion here is made
 * of - and voice 1 carries the music. A sound is a starting pitch, a step
 * added to it on every pass, and a length; that covers the falling whistle
 * of a shot as well as a bang.
 * ==================================================================== */

#define K_STILLE  0
#define K_SCHUSS  1
#define K_KNALL   2
#define K_TOD     3
#define K_TREFFER 4

static unsigned char klang_art;
static unsigned char klang_zeit;
static unsigned klang_hoehe;
static int klang_schritt;
static unsigned char klang_bits;      /* what voice 2 contributes to $FF11 */
static unsigned char musik_bits;      /* and voice 1                        */

static void laut_setzen(void)
{
    if (!klang_bits && !musik_bits) { TED_LAUT = 0; return; }
    TED_LAUT = (unsigned char)(0x08 | klang_bits | musik_bits);
}

/* Voice 1 keeps its two top bits of pitch in $FF12, next to the bit that
   says the character set is in RAM - so that one has to survive. */
static void stimme1(unsigned hoehe)
{
    TED_TON1_LO = (unsigned char)(hoehe & 0xFF);
    TED_ZSATZ_M = (unsigned char)((TED_ZSATZ_M & 0xFC) | ((hoehe >> 8) & 3));
}

static void stimme2(unsigned hoehe)
{
    TED_TON2_LO = (unsigned char)(hoehe & 0xFF);
    TED_TON_HI = (unsigned char)((TED_TON_HI & 0xFC) | ((hoehe >> 8) & 3));
}

static void klang_ausgeben(void)
{
    if (klang_art == K_STILLE) { klang_bits = 0; laut_setzen(); return; }
    stimme2(klang_hoehe);
    klang_bits = (unsigned char)(klang_art == K_SCHUSS ? 0x20 : 0x60);
    laut_setzen();
}

static void klang_starten(unsigned char art)
{
    /* A sound only gives way to one that matters more. */
    if (klang_art > art && klang_zeit) return;
    klang_art = art;
    switch (art) {
    case K_SCHUSS:  klang_hoehe = 900; klang_schritt =  20; klang_zeit = 2; break;
    case K_TREFFER: klang_hoehe = 820; klang_schritt =  30; klang_zeit = 3; break;
    case K_KNALL:   klang_hoehe = 940; klang_schritt = -25; klang_zeit = 4; break;
    default:        klang_hoehe = 760; klang_schritt = -20; klang_zeit = 12; break;
    }
    klang_ausgeben();
}

/* ---- music -------------------------------------------------------------
 *
 * Note 0 is a rest, 1 is C of the third octave and so on up in semitones.
 * The values are what the TED wants: 1024 - 111860.8 / frequency.
 * -------------------------------------------------------------------- */

static const unsigned TONHOEHE[37] = {
    0,
    169, 217, 262, 305, 345, 383, 419, 453, 485, 516, 544, 571,
    596, 620, 643, 664, 685, 704, 722, 739, 755, 770, 784, 798,
    810, 822, 834, 844, 854, 864, 873, 881, 889, 897, 904, 911
};

#define C4 13
#define D4 15
#define E4 17
#define F4 18
#define G4 20
#define A4 22
#define B4 24
#define C5 25
#define D5 27
#define E5 29
#define F5 30
#define G5 32
#define A5 34
#define B5 36
#define GIS4 21
#define DIS5 28
#define FIS5 31
#define DIS4 16
#define FIS4 19
#define PAUSE 0

/*
 * What the arcade machine played: "Romance de Amor" while the first flock
 * comes in, and "Fuer Elise" once the mothership is gone. Both are cut down
 * to the phrase everybody recognises - a pass through the game is an eighth
 * of a second, and that is all the resolution there is.
 */
static const unsigned char MUS_ROMANZE[] = {
    B4,2, E5,6, E5,2, FIS5,2, G5,4, FIS5,2, E5,2, DIS5,4, E5,6,
    B4,2, E5,4, G5,4, B5,6, A5,2, G5,2, FIS5,4, E5,8, PAUSE,4, 255,0
};

static const unsigned char MUS_ELISE[] = {
    E5,1, DIS5,1, E5,1, DIS5,1, E5,1, B4,1, D5,1, C5,1,
    A4,3, PAUSE,1, C4,1, E4,1, A4,1, B4,3, PAUSE,1,
    E4,1, GIS4,1, B4,1, C5,3, PAUSE,1, E4,1,
    E5,1, DIS5,1, E5,1, DIS5,1, E5,1, B4,1, D5,1, C5,1, A4,4, PAUSE,4, 255,0
};

/* The three loops the 2600 hums while a wave is running. */
static const unsigned char MUS_FLUG[] = {
    C4,1, E4,1, G4,1, E4,1, 255,0
};

static const unsigned char MUS_GROSS[] = {
    B4,1, A4,1, G4,1, F4,1, E4,1, D4,1, 255,0
};

static const unsigned char MUS_MUTTER[] = {
    C4,2, PAUSE,1, C4,1, PAUSE,2, 255,0
};

static const unsigned char *musik_stueck;
static unsigned char musik_pos;
static unsigned char musik_rest;
static unsigned char musik_schleife;

static void musik_starten(const unsigned char *stueck, unsigned char schleife)
{
    musik_stueck = stueck;
    musik_pos = 0;
    musik_rest = 0;
    musik_schleife = schleife;
}

static void musik_aus(void)
{
    musik_stueck = 0;
    musik_bits = 0;
    laut_setzen();
}

/* Returns 0 once a piece that does not loop has finished. */
static unsigned char musik_weiter(void)
{
    unsigned char note;

    if (!musik_stueck) return 0;
    if (musik_rest) { --musik_rest; return 1; }

    note = musik_stueck[musik_pos];
    if (note == 255) {
        if (!musik_schleife) { musik_aus(); return 0; }
        musik_pos = 0;
        note = musik_stueck[0];
    }
    musik_rest = musik_stueck[musik_pos + 1];
    musik_pos = (unsigned char)(musik_pos + 2);

    if (note == PAUSE) {
        musik_bits = 0;
    } else {
        stimme1(TONHOEHE[note]);
        musik_bits = 0x10;
    }
    laut_setzen();
    return 1;
}

static void klang_weiter(void)
{
    musik_weiter();
    if (klang_art == K_STILLE) return;
    if (--klang_zeit == 0) { klang_art = K_STILLE; klang_ausgeben(); return; }
    klang_hoehe = (unsigned)((int)klang_hoehe + klang_schritt);
    klang_ausgeben();
}

/* ======================================================================
 * 8. The player's ship
 *
 * The ship holds the bottom of the screen, fires one shot at a time and can
 * raise a force field: on the 2600 that is the joystick pulled towards you.
 * It burns for one and a half seconds, cannot be raised again for another
 * three and a half, and roots the ship to the spot while it is up - but the
 * ship may still fire, and anything that touches the field dies.
 * ==================================================================== */

/*
 * A pass through the game takes between three and six frames, depending on
 * how much is flying - so the game runs at some ten to fifteen steps a
 * second. That is what the Plus/4 gives when a dozen figures have to be
 * drawn out of characters; there are no sprites to hand the work to.
 * Every speed and every length of time below is counted in those steps.
 */
#define TAKT          12     /* steps per second, near enough              */

#define SPIEL_OBEN    24     /* first pixel row below the score             */
#define SPIEL_UNTEN  192

#define SCHIFF_Y     176     /* top edge of the ship in screen pixels       */
#define SCHIFF_BREIT   8
#define SCHIFF_LINKS   2
#define SCHIFF_RECHTS 150

#define SCHILD_DAUER  18     /* one and a half seconds                      */
#define SCHILD_PAUSE  42     /* three and a half before it works again      */

#define SLOT_SCHIFF   0
#define SLOT_SCHUSS   FIG_N
#define SLOT_EI       (FIG_N + 1)
#define EIER          4
#define SLOT_SCHILD   (FIG_N + SCH_N - 1)

static unsigned char spieler_x;
static unsigned char schild_zeit;
static unsigned char schild_sperre;
static unsigned char feuer_alt;
static unsigned char dauerfeuer;      /* wave 2 lets you hold the button    */

static unsigned char schuss_aktiv;
static unsigned char schuss_x;
static unsigned char schuss_y;

static void spieler_setzen(void)
{
    spieler_x = 76;
    schild_zeit = 0;
    schild_sperre = 0;
    schuss_aktiv = 0;
    feuer_alt = 0;
    figur_loeschen(SLOT_SCHUSS);
    figur_loeschen(SLOT_SCHILD);
}

static void spieler_steuern(unsigned char s)
{
    unsigned char feuer = (unsigned char)(s & ST_FEUER);

    if (schild_sperre) --schild_sperre;

    if (schild_zeit) {
        --schild_zeit;
        if (schild_zeit == 0) {
            schild_sperre = SCHILD_PAUSE;
            figur_loeschen(SLOT_SCHILD);
        }
    } else {
        if ((s & ST_SCHILD) && !schild_sperre) {
            schild_zeit = SCHILD_DAUER;
        } else {
            if (s & ST_LINKS) {
                spieler_x = (unsigned char)(spieler_x - 5);
                if (spieler_x < SCHIFF_LINKS || spieler_x > 200)
                    spieler_x = SCHIFF_LINKS;
            }
            if (s & ST_RECHTS) {
                spieler_x = (unsigned char)(spieler_x + 5);
                if (spieler_x > SCHIFF_RECHTS) spieler_x = SCHIFF_RECHTS;
            }
        }
    }

    if (feuer && !schuss_aktiv && (dauerfeuer || !feuer_alt)) {
        schuss_aktiv = 1;
        schuss_x = spieler_x;
        schuss_y = SCHIFF_Y - 4;
        klang_starten(K_SCHUSS);
    }
    feuer_alt = feuer;
}

static void schuss_bewegen(void)
{
    if (!schuss_aktiv) return;
    schuss_y = (unsigned char)(schuss_y - 16);
    if (schuss_y < SPIEL_OBEN || schuss_y > 200) {
        schuss_aktiv = 0;
        figur_loeschen(SLOT_SCHUSS);
    }
}

static void spieler_malen(void)
{
    figur_malen(SLOT_SCHIFF, FORM_SCHIFF, spieler_x, SCHIFF_Y, C_WEISS);
    if (schuss_aktiv)
        figur_malen(SLOT_SCHUSS, FORM_SCHUSS, schuss_x, schuss_y, C_GELB);
    if (schild_zeit)
        figur_malen(SLOT_SCHILD, (unsigned char)(FORM_SCHILD + (schild_zeit & 1)),
                    spieler_x, SCHIFF_Y - 4, C_TUERKIS);
}

/* ======================================================================
 * 9. The birds of waves one and two
 *
 * A flock sits in a formation that sways from side to side. Now and then one
 * of them drops out, dives at the ship in a curve, drops an egg on the way
 * and, if it survives, comes back in over the top edge and takes its place in
 * the formation again. In formation a bird is worth 20 points, in flight 80 -
 * which is exactly the invitation to wait that the arcade machine made.
 * ==================================================================== */

#define V_LEER    0
#define V_FORM    1
#define V_STURZ   2
#define V_RUECK   3
#define V_TOT     4

#define VOEGEL       8
#define V_SPALTEN    4
#define V_ABSTAND   30       /* distance inside the formation, 2600 pixels */
#define V_ZEILE     16
#define V_OBEN      40       /* where the formation sits                   */

static unsigned char v_zustand[VOEGEL];
static unsigned char v_x[VOEGEL];
static unsigned char v_y[VOEGEL];
static signed char v_dx[VOEGEL];
static signed char v_dy[VOEGEL];
static unsigned char v_platz[VOEGEL];     /* place in the formation        */
static unsigned char v_flug[VOEGEL];      /* wing beat                     */
static unsigned char v_zeit[VOEGEL];
static unsigned char v_fluegel[VOEGEL];   /* bit 0 left, bit 1 right        */
static unsigned char v_regen[VOEGEL];     /* until the wings grow back      */
static unsigned char voegel_uebrig;
static unsigned char voegel_zahl;         /* how many this wave has         */
static unsigned char v_gross;             /* large birds instead of small   */
static unsigned char mutterwelle;         /* the saucer instead of a flock  */
static unsigned char v_breit;             /* width in 2600 pixels           */
static unsigned char v_hoch;              /* height in pixels               */

static unsigned char form_x;              /* left edge of the formation    */
static signed char form_dx;
static unsigned char sturz_zeit;          /* until the next one dives      */
static unsigned char welle;               /* 1..5, then round by round     */
static unsigned char runde;
static unsigned char vogelfarbe;

/* eggs the birds drop */
static unsigned char ei_aktiv[EIER];
static unsigned char ei_x[EIER];
static unsigned char ei_y[EIER];

/* Where a bird belongs when it sits in the formation. */
/*
 * Where a bird belongs while it sits in the formation. Small birds stand in
 * two rows of four, large ones in two rows of three with more room between
 * them.
 */
static unsigned char platz_x(unsigned char p)
{
    unsigned char reihe = (unsigned char)(v_gross ? 3 : V_SPALTEN);
    unsigned char sp = (unsigned char)(p >= reihe ? p - reihe : p);
    if (v_gross) return (unsigned char)(form_x + sp * 44);
    return (unsigned char)(form_x + sp * V_ABSTAND);
}

static unsigned char platz_y(unsigned char p)
{
    unsigned char reihe = (unsigned char)(v_gross ? 3 : V_SPALTEN);
    if (p >= reihe) return (unsigned char)(V_OBEN + (v_gross ? 26 : V_ZEILE));
    return V_OBEN;
}

static void mutter_aufbauen(void);

static unsigned char satz_geladen;      /* which set of shapes is in memory */

static void text_zeigen(unsigned char x, unsigned char y,
                        const char *t, unsigned char farbe);
static void textfont_laden(void);

/* Puts the number of the coming wave on the screen while its shapes are
   being worked out. */
static void welle_ansagen(void)
{
    char zeile[8];

    textfont_laden();
    zeile[0] = 'W'; zeile[1] = 'A'; zeile[2] = 'V'; zeile[3] = 'E';
    zeile[4] = ' '; zeile[5] = (char)('0' + welle); zeile[6] = 0;
    text_zeigen(17, 11, zeile, C_WEISS);
    bild_warten();
}

static void welle_aufbauen(void)
{
    unsigned char i, satz;

    v_gross = (unsigned char)(welle == 3 || welle == 4);
    mutterwelle = (unsigned char)(welle == 5);

    /* Working out all 32 views of every shape takes over a second, so it is
       only done when the wave really needs other shapes than the one before
       - waves one and two share theirs, and so do three and four. */
    satz = (unsigned char)(v_gross ? 2 : 1);

    /* Working the shapes out takes over a second, so say what is coming
       rather than leave the screen dead. */
    if (satz != satz_geladen) welle_ansagen();

    if (mutterwelle) {
        /* The 2600 sends the saucer down on its own - no escort birds, the
           console had nothing left for them. */
        if (satz != satz_geladen) { formen_klein(); satz_geladen = satz; }
        vorrat_verteilen(8, VOEGEL);
        voegel_zahl = 0;
        v_breit = 8;
        v_hoch = 8;
        vogelfarbe = C_WEISS;
    } else if (v_gross) {
        if (satz != satz_geladen) { formen_gross(); satz_geladen = satz; }
        vorrat_verteilen(16, 6);
        voegel_zahl = 6;
        v_breit = 16;
        v_hoch = 12;
        form_x = 12;
        vogelfarbe = (unsigned char)(welle == 4 ? C_ROT : C_HELLBLAU);
    } else {
        if (satz != satz_geladen) { formen_klein(); satz_geladen = satz; }
        vorrat_verteilen(8, VOEGEL);
        voegel_zahl = VOEGEL;
        v_breit = 8;
        v_hoch = 8;
        form_x = 20;
        vogelfarbe = (unsigned char)(welle == 2 ? C_GRUEN : C_ORANGE);
    }

    for (i = 0; i < FIG_N + SCH_N; ++i) bel_nsp[i] = 0;
    sternenhimmel_aufbauen();
    if (mutterwelle) mutter_aufbauen();

    form_dx = 1;
    sturz_zeit = 16;
    voegel_uebrig = voegel_zahl;

    for (i = 0; i < voegel_zahl; ++i) {
        v_zustand[i] = V_FORM;
        v_platz[i] = i;
        v_flug[i] = (unsigned char)(i & 3);
        v_zeit[i] = 0;
        v_fluegel[i] = 3;
        v_regen[i] = 0;
        v_x[i] = platz_x(i);
        v_y[i] = platz_y(i);
    }
    for (i = voegel_zahl; i < VOEGEL; ++i) v_zustand[i] = V_LEER;
    for (i = 0; i < EIER; ++i) ei_aktiv[i] = 0;

    dauerfeuer = (unsigned char)(welle == 2);

    if (mutterwelle) musik_starten(MUS_MUTTER, 1);
    else if (v_gross) musik_starten(MUS_GROSS, 1);
    else musik_starten(MUS_FLUG, 1);
}

static const signed char WACKEL[8] = { 0, 1, 2, 1, 0, -1, -2, -1 };

static void ei_legen(unsigned char x, unsigned char y)
{
    unsigned char i;
    for (i = 0; i < EIER; ++i) {
        if (!ei_aktiv[i]) {
            ei_aktiv[i] = 1;
            ei_x[i] = x;
            ei_y[i] = y;
            return;
        }
    }
}

static void voegel_bewegen(void)
{
    unsigned char i, z;
    int x, y;

    /* the whole formation sways */
    form_x += form_dx;
    if (form_x > 44) form_dx = -1;
    if (form_x < 4)  form_dx = 1;

    /* every so often one of them drops out */
    if (sturz_zeit) {
        --sturz_zeit;
    } else {
        unsigned char versuch = (unsigned char)(zufall() % voegel_zahl);
        for (i = 0; i < voegel_zahl; ++i) {
            unsigned char k = (unsigned char)((versuch + i) % voegel_zahl);
            if (v_zustand[k] == V_FORM) {
                v_zustand[k] = V_STURZ;
                v_dy[k] = 3;
                v_dx[k] = (signed char)(v_x[k] > spieler_x ? -1 : 1);
                v_zeit[k] = 0;
                break;
            }
        }
        /* the 2600 turns the screw only gently from round to round */
        sturz_zeit = (unsigned char)(8 + (zufall() & 15));
        if (runde > 1) {
            unsigned char ab = (unsigned char)(runde - 1);
            if (ab > 4) ab = 4;
            if (sturz_zeit > ab) sturz_zeit = (unsigned char)(sturz_zeit - ab);
        }
    }

    for (i = 0; i < voegel_zahl; ++i) {
        z = v_zustand[i];
        if (z == V_LEER) continue;

        if (z == V_TOT) {
            if (--v_zeit[i] == 0) {
                v_zustand[i] = V_LEER;
                figur_loeschen((unsigned char)(i + 1));
                --voegel_uebrig;
            }
            continue;
        }

        v_flug[i] = (unsigned char)((v_flug[i] + 1) & 15);

        if (v_regen[i] && --v_regen[i] == 0) v_fluegel[i] = 3;

        if (z == V_FORM) {
            v_x[i] = platz_x(v_platz[i]);
            v_y[i] = platz_y(v_platz[i]);
            continue;
        }

        if (z == V_STURZ) {
            ++v_zeit[i];
            y = v_y[i] + v_dy[i];
            x = v_x[i] + v_dx[i] * 3 + WACKEL[v_zeit[i] & 7];
            if (v_dy[i] < 9) v_dy[i] += 2;
            /* steer towards the ship while there is still room */
            if (x > (int)spieler_x + 4) v_dx[i] = -1;
            else if (x + 4 < (int)spieler_x) v_dx[i] = 1;
            if (x < 0) x = 0;
            if (x > 152) x = 152;
            v_x[i] = (unsigned char)x;
            v_y[i] = (unsigned char)y;
            if (v_zeit[i] == 5) ei_legen((unsigned char)x, (unsigned char)(y + 8));
            if (y > SPIEL_UNTEN) {
                v_zustand[i] = V_RUECK;
                v_y[i] = SPIEL_OBEN - 8;
                figur_loeschen((unsigned char)(i + 1));
            }
            continue;
        }

        /* on the way back to its place in the formation */
        x = platz_x(v_platz[i]);
        y = platz_y(v_platz[i]);
        if (v_x[i] + 3 < x) v_x[i] = (unsigned char)(v_x[i] + 4);
        else if (v_x[i] > x + 3) v_x[i] = (unsigned char)(v_x[i] - 4);
        else v_x[i] = x;
        if (v_y[i] < y) v_y[i] = (unsigned char)(v_y[i] + 6);
        if (v_y[i] >= y && v_x[i] == x) v_zustand[i] = V_FORM;
        if (v_y[i] > y) v_y[i] = y;
    }
}

static void eier_bewegen(void)
{
    unsigned char i;
    for (i = 0; i < EIER; ++i) {
        if (!ei_aktiv[i]) continue;
        ei_y[i] = (unsigned char)(ei_y[i] + 8);
        if (ei_y[i] > SPIEL_UNTEN) {
            ei_aktiv[i] = 0;
            figur_loeschen((unsigned char)(SLOT_EI + i));
        }
    }
}

static void voegel_malen(void)
{
    static const unsigned char SCHLAG[4] = { 0, 1, 2, 1 };
    static const unsigned char OHNE[4] = {
        FORM_GROSS_0, FORM_GROSS_L, FORM_GROSS_R, 0
    };
    unsigned char i, form;

    for (i = 0; i < voegel_zahl; ++i) {
        switch (v_zustand[i]) {
        case V_LEER:
            break;
        case V_TOT:
            figur_malen((unsigned char)(i + 1),
                        (unsigned char)(FORM_KNALL + (v_zeit[i] & 1)),
                        v_x[i], v_y[i], C_WEISS);
            break;
        default:
            if (v_gross) {
                /* with both wings it flaps, otherwise it hangs in the air */
                if (v_fluegel[i] == 3)
                    form = (unsigned char)(FORM_GROSS + ((v_flug[i] >> 3) & 1));
                else
                    form = OHNE[v_fluegel[i]];
            } else {
                form = (unsigned char)(FORM_VOGEL + SCHLAG[(v_flug[i] >> 2) & 3]);
            }
            figur_malen((unsigned char)(i + 1), form, v_x[i], v_y[i], vogelfarbe);
            break;
        }
    }
    for (i = 0; i < EIER; ++i)
        if (ei_aktiv[i])
            figur_malen((unsigned char)(SLOT_EI + i), FORM_EI,
                        ei_x[i], ei_y[i], C_WEISS);
}

/* ======================================================================
 * 10. The mothership of wave five
 *
 * A saucer that comes down the screen a row at a time, riding the same fine
 * scroll as the stars, so its approach is as smooth as theirs and costs
 * nothing. It is not a figure but part of the background: its cells sit in
 * the shadow copy, which means birds and shots drawn over it put it back
 * when they move on.
 *
 * The way in is from below. Every hit takes a bite out of the lowest piece
 * of hull in that column; once a column is chewed through, the shot still
 * has to pass the rim, which turns and closes the gap again. Only then can
 * it reach the alien in the middle.
 * ==================================================================== */

#define MS_BREIT 24
#define MS_HOCH   8
#define MS_LINKS  8          /* left cell column on screen */

#define MZ_LEER    0
#define MZ_SPERRE  5         /* a piece of the turning rim */
#define MZ_CHEF    6         /* the alien in the middle    */

#define Z_MUTTER 240         /* 240..248 belong to the saucer */

/* Per row the first and last cell the saucer reaches into. */
static const unsigned char MS_VON[MS_HOCH]  = {  8,  6,  2,  0,  0,  2,  6,  8 };
static const unsigned char MS_BIS[MS_HOCH]  = { 15, 17, 21, 23, 23, 21, 17, 15 };
static const unsigned char MS_FARBE[MS_HOCH] = {
    0x45, 0x47, 0x4B, 0x42, 0x42, 0x4B, 0x47, 0x45
};

#define MS_SPERRZEILE 4      /* the row that turns */
#define MS_CHEFZEILE  2
#define MS_CHEFSP    11

static unsigned char ms_feld[MS_HOCH][MS_BREIT];
static unsigned char ms_zeile;       /* topmost cell row on screen */
static unsigned char ms_dreh;        /* how far the rim has turned */
static unsigned char ms_lebt;
static unsigned char ms_bombe_zeit;

/* The saucer's own characters: solid hull eaten away from below, the rim,
   and four cells that make up the alien. */
static const unsigned char CHEF[16] = {
    0x07, 0xE0,
    0x1F, 0xF8,
    0x3C, 0x3C,
    0x7E, 0x7E,
    0x7F, 0xFE,
    0xFF, 0xFF,
    0xEF, 0xF7,
    0xC7, 0xE3
};

static const unsigned char CHEF2[16] = {
    0xC7, 0xE3,
    0xEF, 0xF7,
    0x7F, 0xFE,
    0x3F, 0xFC,
    0x1B, 0xD8,
    0x33, 0xCC,
    0x66, 0x66,
    0x44, 0x22
};

static void mutterzeichen_bauen(void)
{
    unsigned char s, i;
    unsigned char *z;

    /* four states of hull, each bite two pixel rows deep */
    for (s = 0; s < 4; ++s) {
        z = zeichensatz + (Z_MUTTER + s) * 8;
        for (i = 0; i < 8; ++i)
            z[i] = (unsigned char)(i < (unsigned char)(8 - s - s) ? 0xFF : 0x00);
    }
    /* the rim */
    z = zeichensatz + (Z_MUTTER + 4) * 8;
    for (i = 0; i < 8; ++i) z[i] = (unsigned char)((i & 1) ? 0x66 : 0x99);

    /* the alien, two cells by two */
    for (i = 0; i < 8; ++i) {
        zeichensatz[(Z_MUTTER + 5) * 8 + i] = CHEF[i + i];
        zeichensatz[(Z_MUTTER + 6) * 8 + i] = CHEF[i + i + 1];
        zeichensatz[(Z_MUTTER + 7) * 8 + i] = CHEF2[i + i];
        zeichensatz[(Z_MUTTER + 8) * 8 + i] = CHEF2[i + i + 1];
    }
}

/* Puts one cell of the saucer on the screen, or clears it. */
static void mutter_zelle(unsigned char r, unsigned char c)
{
    unsigned char zr = (unsigned char)(ms_zeile + r);
    unsigned char w = ms_feld[r][c];
    unsigned char zeichen, farbe;

    if (zr >= ZEILEN) return;

    if (w == MZ_LEER) {
        zeichen = Z_LEER;
        farbe = C_SCHWARZ;
    } else if (w == MZ_SPERRE) {
        zeichen = Z_MUTTER + 4;
        farbe = C_TUERKIS;
    } else if (w == MZ_CHEF) {
        /* four cells, which one depends on where we are */
        zeichen = (unsigned char)(Z_MUTTER + 5
                + (r > MS_CHEFZEILE ? 2 : 0)
                + (c > MS_CHEFSP ? 1 : 0));
        farbe = C_VIOLETT;
    } else {
        zeichen = (unsigned char)(Z_MUTTER + 4 - w);
        farbe = MS_FARBE[r];
    }
    hintergrund_setzen((unsigned char)(MS_LINKS + c), zr, zeichen, farbe);
}

static void mutter_zeichnen(void)
{
    unsigned char r, c;
    for (r = 0; r < MS_HOCH; ++r)
        for (c = 0; c < MS_BREIT; ++c)
            mutter_zelle(r, c);
}

/* Turns the rim by one cell: the gaps travel, and a column that was open is
   closed again a moment later. */
static void mutter_drehen(void)
{
    unsigned char c, offen;

    ms_dreh = (unsigned char)((ms_dreh + 1) & 7);
    for (c = MS_VON[MS_SPERRZEILE]; c <= MS_BIS[MS_SPERRZEILE]; ++c) {
        offen = (unsigned char)(((c + ms_dreh) & 7) < 2);
        ms_feld[MS_SPERRZEILE][c] = (unsigned char)(offen ? MZ_LEER : MZ_SPERRE);
        mutter_zelle(MS_SPERRZEILE, c);
    }
}

static void mutter_aufbauen(void)
{
    unsigned char r, c;

    mutterzeichen_bauen();
    ms_zeile = 0;
    ms_dreh = 0;
    ms_lebt = 1;
    ms_bombe_zeit = 8;

    for (r = 0; r < MS_HOCH; ++r) {
        for (c = 0; c < MS_BREIT; ++c) {
            if (c < MS_VON[r] || c > MS_BIS[r]) { ms_feld[r][c] = MZ_LEER; continue; }
            if (r == MS_SPERRZEILE) { ms_feld[r][c] = MZ_SPERRE; continue; }
            if ((r == MS_CHEFZEILE || r == MS_CHEFZEILE + 1) &&
                (c == MS_CHEFSP || c == MS_CHEFSP + 1)) {
                ms_feld[r][c] = MZ_CHEF;
                continue;
            }
            ms_feld[r][c] = 4;               /* hull, undamaged */
        }
    }
    mutter_zeichnen();
}

/* One row further down. Everything it leaves behind becomes sky again. */
static void mutter_sinken(void)
{
    unsigned char c;

    for (c = 0; c < MS_BREIT; ++c)
        if (ms_zeile < ZEILEN)
            hintergrund_setzen((unsigned char)(MS_LINKS + c), ms_zeile,
                               Z_LEER, C_SCHWARZ);
    ++ms_zeile;
    mutter_zeichnen();
}

/*
 * Works out what the player's shot runs into. Returns 1 when the alien has
 * been hit and the saucer is finished.
 */
static unsigned char mutter_beschuss(void)
{
    unsigned char c, r, zr;
    signed char rr;

    if (!ms_lebt || !schuss_aktiv) return 0;

    /* which column of the saucer is the shot in? */
    c = (unsigned char)((schuss_x + 3) >> 2);      /* cell column on screen */
    if (c < MS_LINKS || c >= (unsigned char)(MS_LINKS + MS_BREIT)) return 0;
    c = (unsigned char)(c - MS_LINKS);

    /* has it reached the underside yet? A shot covers 22 pixels in a step,
       so it is asked where it stands, not where it passed - and the search
       then starts at the very bottom of the saucer, or a step could carry it
       straight through a piece of hull. */
    zr = (unsigned char)((schuss_y + 8 - yfein) >> 3);
    if (zr > (unsigned char)(ms_zeile + MS_HOCH - 1)) return 0;
    rr = MS_HOCH - 1;

    /* from below upwards, the first thing that is still standing */
    for (; rr >= 0; --rr) {
        r = (unsigned char)rr;
        if (ms_feld[r][c] == MZ_LEER) continue;

        schuss_aktiv = 0;
        figur_loeschen(SLOT_SCHUSS);

        if (ms_feld[r][c] == MZ_CHEF) {
            ms_lebt = 0;
            return 1;
        }
        if (ms_feld[r][c] == MZ_SPERRE) {
            klang_starten(K_TREFFER);       /* the rim holds */
            return 0;
        }
        --ms_feld[r][c];
        mutter_zelle(r, c);
        klang_starten(K_TREFFER);
        punkte_dazu(20);
        return 0;
    }
    return 0;
}

/*
 * The saucer comes apart. What it is worth grows with how far down it had
 * come when it was hit and with the round: a thousand up to four in the
 * first, another thousand per round, nine thousand at most - the same
 * invitation to nerve as the original.
 */
static void mutter_gesprengt(void)
{
    unsigned wert;
    unsigned char i, r, c;

    wert = (unsigned)(1000 + (unsigned)(ms_zeile >> 2) * 1000);
    if (wert > 4000) wert = 4000;
    wert += (unsigned)(runde - 1) * 1000;
    if (wert > 9000) wert = 9000;
    punkte_dazu(wert);

    musik_aus();
    klang_starten(K_TOD);
    for (i = 0; i < 16; ++i) {
        /* eat the saucer away from the middle outwards */
        for (r = 0; r < MS_HOCH; ++r)
            for (c = 0; c < MS_BREIT; ++c)
                if (ms_feld[r][c] != MZ_LEER && (zufall() & 3) == 0) {
                    ms_feld[r][c] = MZ_LEER;
                    mutter_zelle(r, c);
                }
        klang_weiter();
        bild_warten();
        anzeige_zeichnen();
        spieler_malen();
    }
    for (r = 0; r < MS_HOCH; ++r)
        for (c = 0; c < MS_BREIT; ++c) {
            ms_feld[r][c] = MZ_LEER;
            mutter_zelle(r, c);
        }

    /* the arcade machine's reward for getting this far */
    musik_starten(MUS_ELISE, 0);
    while (musik_weiter()) {
        bild_warten();
        anzeige_zeichnen();
        spieler_malen();
    }
}

/* The saucer drops one. */
static void mutter_bomben(void)
{
    unsigned char c, r;

    if (!ms_lebt) return;
    if (ms_bombe_zeit) { --ms_bombe_zeit; return; }
    ms_bombe_zeit = (unsigned char)(4 + (zufall() & 7));

    c = (unsigned char)(zufall() % MS_BREIT);
    for (r = MS_HOCH; r > 0; --r)
        if (ms_feld[r - 1][c] != MZ_LEER) {
            ei_legen((unsigned char)((MS_LINKS + c) << 2),
                     (unsigned char)(((ms_zeile + r) << 3) - 8));
            return;
        }
}

/* ======================================================================
 * 11. Hits
 * ==================================================================== */

static void vogel_toeten(unsigned char i)
{
    v_zustand[i] = V_TOT;
    v_zeit[i] = 4;
    klang_starten(K_TREFFER);
}

/*
 * Did the shot strike that bird, and where? A large bird carries its wings
 * in the outer five 2600 pixels on each side; a shot through a wing that is
 * already gone hits nothing at all, which is what makes the birds of waves
 * three and four so much harder than they look.
 */
#define T_DANEBEN  0
#define T_KOERPER  1
#define T_LINKS    2
#define T_RECHTS   3

static unsigned char treffer_schuss(unsigned char i)
{
    unsigned char sx = (unsigned char)(schuss_x + 3);
    unsigned char ab;

    if (sx < v_x[i] || sx > (unsigned char)(v_x[i] + v_breit - 1)) return T_DANEBEN;
    if (schuss_y > (unsigned char)(v_y[i] + v_hoch - 1)) return T_DANEBEN;
    if ((unsigned char)(schuss_y + 4) < v_y[i]) return T_DANEBEN;
    if (!v_gross) return T_KOERPER;

    ab = (unsigned char)(sx - v_x[i]);
    if (ab < 5)  return (unsigned char)((v_fluegel[i] & 1) ? T_LINKS : T_DANEBEN);
    if (ab >= 11) return (unsigned char)((v_fluegel[i] & 2) ? T_RECHTS : T_DANEBEN);
    return T_KOERPER;
}

/* What a large bird is worth: the longer you let it come, the more. */
static unsigned grosswert(unsigned char y)
{
    if (y < 70) return 100;
    if (y < 100) return 200;
    if (y < 130) return 300;
    return 500;
}

static unsigned char treffer_pruefen(void)
{
    unsigned char i, art;
    int sx;

    if (schuss_aktiv) {
        for (i = 0; i < voegel_zahl; ++i) {
            if (v_zustand[i] == V_LEER || v_zustand[i] == V_TOT) continue;
            art = treffer_schuss(i);
            if (art == T_DANEBEN) continue;

            schuss_aktiv = 0;
            figur_loeschen(SLOT_SCHUSS);

            if (art == T_KOERPER) {
                if (v_gross) punkte_dazu(grosswert(v_y[i]));
                else punkte_dazu((unsigned)(v_zustand[i] == V_FORM ? 20 : 80));
                vogel_toeten(i);
            } else {
                /* only a wing - it comes off, and both grow back later */
                v_fluegel[i] = (unsigned char)(v_fluegel[i] &
                                   (art == T_LINKS ? 2 : 1));
                v_regen[i] = (unsigned char)(3 * TAKT);
                punkte_dazu(20);
                klang_starten(K_TREFFER);
            }
            break;
        }
    }

    /* The force field takes anything that comes close enough. */
    if (schild_zeit) {
        for (i = 0; i < voegel_zahl; ++i) {
            if (v_zustand[i] != V_STURZ) continue;
            if (v_y[i] + 7 < SCHIFF_Y - 6 || v_y[i] > SCHIFF_Y + 8) continue;
            if (v_x[i] + 7 < (int)spieler_x - 2 ||
                v_x[i] > (int)spieler_x + SCHIFF_BREIT + 1) continue;
            punkte_dazu(80);
            vogel_toeten(i);
        }
        for (i = 0; i < EIER; ++i) {
            if (!ei_aktiv[i]) continue;
            if (ei_y[i] + 2 < SCHIFF_Y - 6 || ei_y[i] > SCHIFF_Y + 8) continue;
            ei_aktiv[i] = 0;
            figur_loeschen((unsigned char)(SLOT_EI + i));
        }
        return 0;                 /* nothing can hurt us while it burns */
    }

    /* a bird flying into the ship */
    for (i = 0; i < voegel_zahl; ++i) {
        if (v_zustand[i] != V_STURZ) continue;
        if (v_y[i] + 7 < SCHIFF_Y || v_y[i] > SCHIFF_Y + 7) continue;
        if (v_x[i] + 7 < (int)spieler_x ||
            v_x[i] > (int)spieler_x + SCHIFF_BREIT - 1) continue;
        return 1;
    }

    /* an egg landing on it */
    for (i = 0; i < EIER; ++i) {
        if (!ei_aktiv[i]) continue;
        if (ei_y[i] + 2 < SCHIFF_Y || ei_y[i] > SCHIFF_Y + 7) continue;
        sx = (int)ei_x[i] + 3;
        if (sx < (int)spieler_x || sx > (int)spieler_x + SCHIFF_BREIT - 1) continue;
        ei_aktiv[i] = 0;
        figur_loeschen((unsigned char)(SLOT_EI + i));
        return 1;
    }

    return 0;
}

/*
 * A stand-in for a player, so the game can be watched running without a hand
 * on the joystick. It aims at the lowest bird it can see, fires without
 * pause and raises the field when something comes down on top of it. Only
 * used for testing; a real round never switches it on.
 */
static unsigned char unsterblich;      /* testing only, never set in a game */

static unsigned char autopilot_steuern(void)
{
    unsigned char i, s;
    unsigned char tiefste = 0, ziel = 80;

    /* The button has to be let go of between shots, so it is pulsed. */
    s = (unsigned char)((durchlaeufe & 1) ? ST_FEUER : 0);

    if (mutterwelle) {
        /* keep under the middle of the saucer and keep firing */
        ziel = (unsigned char)((MS_LINKS + MS_CHEFSP) << 2);
        if (ziel > spieler_x + 4) return (unsigned char)(s | ST_RECHTS);
        if (ziel + 4 < spieler_x) return (unsigned char)(s | ST_LINKS);
        return s;
    }

    for (i = 0; i < voegel_zahl; ++i) {
        if (v_zustand[i] == V_LEER || v_zustand[i] == V_TOT) continue;
        if (v_y[i] >= tiefste) { tiefste = v_y[i]; ziel = v_x[i]; }
    }
    if (tiefste > SCHIFF_Y - 24 && ziel + 12 > spieler_x &&
        ziel < (unsigned char)(spieler_x + 12))
        return ST_SCHILD;

    if (ziel + 2 > spieler_x + 4) s |= ST_RECHTS;
    else if (ziel + 6 < spieler_x) s |= ST_LINKS;
    return s;
}

/* ======================================================================
 * 12. Text and title
 *
 * Text is only ever shown when nothing is flying, so the pool of figure
 * characters is free and the ROM font can be dropped into it.
 * ==================================================================== */

#define Z_TEXT Z_VORRAT           /* 64 characters of ROM font */

static void warten(unsigned char schritte);
static unsigned char autopilot;

static void textfont_laden(void)
{
    unsigned i;
    for (i = 0; i < 512; ++i) zeichensatz[Z_TEXT * 8 + i] = romfont[i];
}

/*
 * cc65 turns 'A' in the source into PETSCII 193, not into 65. Screen codes
 * are something else again: there an A is 1. Everything from space to '?'
 * happens to be the same in both, so only the letters need moving.
 */
static void text_zeigen(unsigned char x, unsigned char y,
                        const char *t, unsigned char farbe)
{
    unsigned char c;
    while (*t) {
        c = (unsigned char)*t++;
        if (c >= 193 && c <= 218) c = (unsigned char)(c - 192);
        else if (c > 63) c = 32;
        hintergrund_setzen(x, y, (unsigned char)(Z_TEXT + c), farbe);
        ++x;
    }
}

/*
 * The same text twice as wide, one character per half letter - the whole
 * game is drawn at two Plus/4 pixels per 2600 pixel, and the title should
 * not be the one place that is not.
 */
#define Z_BREIT (Z_TEXT + 64)

static void text_breit(unsigned char x, unsigned char y,
                       const char *t, unsigned char farbe)
{
    unsigned char c, r, code = Z_BREIT;
    const unsigned char *q;

    while (*t) {
        c = (unsigned char)*t++;
        if (c >= 193 && c <= 218) c = (unsigned char)(c - 192);
        else if (c > 63) c = 32;
        q = romfont + (unsigned)c * 8;
        for (r = 0; r < 8; ++r) {
            zeichensatz[code * 8 + r]       = VERDOPPELT[q[r] >> 4];
            zeichensatz[(code + 1) * 8 + r] = VERDOPPELT[q[r] & 15];
        }
        hintergrund_setzen(x, y, code, farbe);
        hintergrund_setzen((unsigned char)(x + 1), y, (unsigned char)(code + 1), farbe);
        x = (unsigned char)(x + 2);
        code = (unsigned char)(code + 2);
    }
}

static void bildschirm_leeren(void)
{
    unsigned p;
    for (p = 0; p < ZEILEN * BREITE; ++p) {
        hg_zeichen[p] = Z_LEER;
        hg_farbe[p] = C_SCHWARZ;
        BILD[p] = Z_LEER;
        FARBE[p] = C_SCHWARZ;
    }
    anz_gesetzt = 0;
}

/* Waits for the fire button to be let go of and pressed again. */
static unsigned char auf_feuer_warten(void)
{
    unsigned char s;

    if (autopilot) return 0;       /* testing runs straight through */
    for (;;) {
        s = steuerung();
        if (s & ST_ENDE) return 1;
        if (!(s & ST_FEUER)) break;
        klang_weiter();
        bild_warten();
    }
    for (;;) {
        s = steuerung();
        if (s & ST_ENDE) return 1;
        if (s & ST_FEUER) return 0;
        klang_weiter();
        bild_warten();
    }
}

static unsigned char titelbild(void)
{
    unsigned char i;

    musik_aus();
    scrollpos = 0;
    yfein = 0;
    bildschirm_leeren();
    textfont_laden();

    text_breit(13,  3, "PHOENIX", C_GELB);
    text_zeigen( 8,  6, "AFTER THE ATARI 2600 GAME", C_GRAU);

    text_zeigen(10,  9, "JOYSTICK IN PORT 1", C_WEISS);
    text_zeigen(10, 10, "OR THE CURSOR KEYS", C_WEISS);

    text_zeigen(10, 13, "BUTTON OR SPACE", C_TUERKIS);
    text_zeigen(28, 13, "FIRE", C_GRAU);
    text_zeigen(10, 14, "STICK DOWN", C_TUERKIS);
    text_zeigen(28, 14, "SHIELD", C_GRAU);
    text_zeigen(10, 15, "Q", C_TUERKIS);
    text_zeigen(28, 15, "QUIT", C_GRAU);

    text_zeigen(11, 19, "PRESS FIRE TO START", C_ORANGE);

    musik_starten(MUS_ROMANZE, 1);
    for (i = 0; i < 4; ++i) {
        klang_weiter();
        bild_warten();
    }
    return auf_feuer_warten();
}

static void abspann(void)
{
    musik_aus();
    textfont_laden();
    text_breit(11, 11, "GAME OVER", C_ROT);
    warten(3 * TAKT);
    auf_feuer_warten();
}

/* ======================================================================
 * 13. Game flow
 * ==================================================================== */

/*
 * Waits for the beam to leave the playfield and then hands the TED the new
 * fine scroll position, so the picture never changes while it is being drawn.
 */
static void bild_warten(void)
{
    ++durchlaeufe;
    while (TED_RASTER >= 210) { eingang_abtasten(); }
    while (TED_RASTER <  210) { eingang_abtasten(); }
    TED_SENKR = (unsigned char)(0x10 | yfein);   /* 24 rows, fine scroll */
}

static void bild_zeichnen(void)
{
    bild_warten();
    anzeige_zeichnen();          /* topmost row first, the beam follows */
    voegel_malen();
    spieler_malen();
}

static void alles_loeschen(void)
{
    unsigned char i;
    for (i = 0; i < FIG_N + SCH_N; ++i) figur_loeschen(i);
}

static void warten(unsigned char bilder)
{
    while (bilder--) {
        scrollen();
        klang_weiter();
        bild_zeichnen();
    }
}

/* The ship blows up and the round starts over. */
static void sterben(void)
{
    unsigned char i;

    musik_aus();
    klang_starten(K_TOD);
    for (i = 0; i < 12; ++i) {
        scrollen();
        klang_weiter();
        bild_warten();
        anzeige_zeichnen();
        voegel_malen();
        figur_malen(SLOT_SCHIFF, (unsigned char)(FORM_KNALL + (i & 1)),
                    spieler_x, SCHIFF_Y, (unsigned char)((i & 1) ? C_GELB : C_ROT));
    }
    figur_loeschen(SLOT_SCHIFF);
}

/* Plays one wave. Returns 0 when it is cleared, 1 when the last life is gone
   and 2 when the player asked to stop. */
static unsigned char welle_spielen(void)
{
    unsigned char s;

    welle_aufbauen();
    spieler_setzen();

    for (;;) {
        s = autopilot ? autopilot_steuern() : steuerung();
        if (s & ST_ENDE) return 2;

        spieler_steuern(s);
        schuss_bewegen();
        voegel_bewegen();
        eier_bewegen();

        if (mutterwelle) {
            mutter_bomben();
            if ((durchlaeufe & 1) == 0) mutter_drehen();
            if (mutter_beschuss()) {
                mutter_gesprengt();
                return 0;
            }
            /* it comes down until it is on top of the ship */
            if (ms_zeile + MS_HOCH >= 22) {
                if (unsterblich) { welle_aufbauen(); continue; }
                sterben();
                if (--leben == 0) return 1;
                anzeige_bauen();
                spieler_setzen();
                welle_aufbauen();
                continue;
            }
        }

        if (treffer_pruefen() && !unsterblich) {
            sterben();
            if (--leben == 0) return 1;
            anzeige_bauen();
            spieler_setzen();
            warten(TAKT);
            continue;
        }

        if (!mutterwelle && voegel_uebrig == 0) {
            warten(TAKT);
            return 0;
        }

        /* In the saucer wave the background is what carries the saucer down,
           and it takes its time about it. */
        if (!mutterwelle || (durchlaeufe & 1) == 0) {
            scrollen();
            if (mutterwelle && yfein == 0 && ms_zeile + MS_HOCH < 22) mutter_sinken();
        }
        klang_weiter();
        bild_zeichnen();
    }
}

int main(void)
{
    unsigned char hgrund, rahmen, senkr, zsatz, zadr, waagr;
    unsigned char i, aus;

    hgrund = TED_HGRUND;
    rahmen = TED_RAHMEN;
    senkr  = TED_SENKR;
    zsatz  = TED_ZSATZ_M;
    zadr   = TED_ZSATZ_A;
    waagr  = TED_WAAGR;

    cursor(0);
    TED_LAUT = 0;

    for (i = 0; i < ZEILEN; ++i) zeilenanfang[i] = (unsigned)i * BREITE;
    for (i = 0; i < FIG_N + SCH_N; ++i) bel_nsp[i] = 0;

    zeichensatz_einrichten();
    for (i = 0; i < ZEILEN; ++i) zeile_bild[i] = BILD + zeilenanfang[i];

    TED_HGRUND = C_SCHWARZ;
    TED_RAHMEN = C_SCHWARZ;

    for (;;) {
        if (titelbild()) break;

        punkte = 0;
        leben = 5;
        welle = 1;
        runde = 1;
        anzeige_bauen();

        for (;;) {
            aus = welle_spielen();
            if (aus == 2) goto ende;
            alles_loeschen();
            if (aus == 1) break;
            ++welle;
            if (welle > 5) { welle = 1; ++runde; }  /* five waves, then again */
        }

        abspann();
    }

ende:
    TED_LAUT = 0;
    TED_WAAGR   = waagr;
    TED_ZSATZ_M = zsatz;
    TED_ZSATZ_A = zadr;
    TED_SENKR   = senkr;
    TED_HGRUND  = hgrund;
    TED_RAHMEN  = rahmen;
    clrscr();
    return 0;
}
