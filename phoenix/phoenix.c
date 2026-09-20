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
 *   The starfield is moved star by star, in software. The TED's own fine
 *   scroll ($FF06 bits 0..2) would do it for a whole screen for nothing, and
 *   that is how this started - but it moves *everything* in the instant the
 *   register is written, while a figure only follows on its next redraw, and
 *   a redraw takes longer than a frame. See scrollen() for what that looked
 *   like. The register now stays put and the stars carry themselves.
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
/*
 * The first wave's colours are picked off a running original: the ROM was
 * stopped in Stella and the pixels read out, then matched against the
 * Plus/4's own palette. The birds are a deep blue-violet, the ground band
 * the same violet a shade lighter, and the ship a sandy orange. A cell can
 * only hold one colour, so each of these is the dominant one of the two the
 * 2600 puts in its sprite.
 *
 * The later waves' colours are still taken off still pictures, which is not
 * the same thing - a 2600 cycles its colours while it sits in its demo, so
 * a screenshot may not show what a game shows.
 */
#define C_V_VIOLETT 0x3E     /* measured (106,46,201)                       */
#define C_V_GRUEN   0x6A
#define C_V_BLAU    0x6D
#define C_V_ROT     0x62
#define C_SCHIFF    0x58     /* measured (210,142,83)                       */
#define C_BALKEN1   0x44     /* measured (167,76,204)                       */
#define C_BALKEN2   0x5E
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
#define Z_BALKEN  20   /* the solid band across the bottom                 */
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

    /* the band the original draws across the foot of the screen */
    for (i = 0; i < 8; ++i) zeichensatz[Z_BALKEN * 8 + i] = 0xFF;

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

/*
 * The TED's fine scroll is left at zero for good; this is kept because every
 * figure position is worked out relative to it and zero is simply the case
 * where it costs nothing.
 */
static unsigned char yfein;

#define PUNKTE_SP 20                   /* width of the score strip in cells */

#define STERNE 26
static unsigned char stern_sp[STERNE];     /* cell column                  */
static unsigned char stern_ze[STERNE];     /* cell row                     */
static unsigned char stern_y[STERNE];      /* pixel row, 0..ZEILEN*8-1     */
static unsigned char stern_x4[STERNE];     /* which quarter of the cell    */
static unsigned char stern_z[STERNE];      /* character code               */
static unsigned char stern_f[STERNE];      /* color                        */
static unsigned stern_p[STERNE];           /* its cell, precomputed        */
static unsigned char stern_zu[STERNE];     /* 1 = the score covers it      */

static unsigned zufallswert = 0x2B7D;

static unsigned char zufall(void)
{
    zufallswert = (unsigned)(zufallswert * 5 + 12345);
    return (unsigned char)(zufallswert >> 7);
}

static unsigned char anz_zeile = 1;    /* cell row the score sits on       */
static unsigned char anz_gesetzt;      /* are its cells on the screen?     */
static unsigned char leben;            /* ships in hand                    */

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
    unsigned p;

    stern_sp[i] = (unsigned char)(zufall() % BREITE);
    stern_y[i] = (unsigned char)(ze << 3);
    stern_ze[i] = ze;
    stern_x4[i] = (unsigned char)(zufall() & 3);
    stern_z[i] = (unsigned char)(Z_STERN + stern_x4[i]);
    stern_f[i] = HELL[zufall() & 3];
    p = zeilenanfang[ze] + stern_sp[i];
    stern_p[i] = p;
    stern_zu[i] = (unsigned char)(stern_sp[i] < PUNKTE_SP && ze <= 2);
    hg_farbe[p] = stern_f[i];
    hg_zeichen[p] = stern_z[i];
    if (!stern_zu[i]) { BILD[p] = stern_z[i]; FARBE[p] = stern_f[i]; }
}

#define BALKEN_ZEILE 23

static unsigned char balkenfarbe = C_BALKEN1;

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
        stern_neu(i, (unsigned char)(zufall() % BALKEN_ZEILE));
        hintergrund_setzen(stern_sp[i], stern_ze[i], stern_z[i], stern_f[i]);
    }

    /* the band along the bottom, which the original has and which the stars
       therefore keep clear of */
    for (i = 0; i < BREITE; ++i)
        hintergrund_setzen(i, BALKEN_ZEILE, Z_BALKEN, balkenfarbe);

    /* The score went with the rest of the screen and has to be put back. */
    anz_gesetzt = 0;
}

/*
 * One pixel further down - in software, star by star.
 *
 * The TED's own fine scroll would do this for a whole screen for nothing, and
 * that is how this started. But it moves *everything* at once, including the
 * figures, and a figure only gets its compensating redraw on the next pass -
 * which takes five frames. So every time the register stepped, the figures
 * stood a pixel wrong until they were drawn again, and when it wrapped from
 * seven back to zero they jumped seven pixels up and crawled back down one by
 * one. Once a second, and very visible.
 *
 * There is no way to synchronise that while drawing takes longer than a
 * frame, so the register now stays where it is and the stars carry themselves.
 * They are sparse, so it costs almost nothing - and it hands back the pass
 * over the score strip, which only had to be redrawn because the scroll moved
 * underneath it.
 */
static void scrollen(void)
{
    unsigned char i, y, ze, code;
    unsigned p;

    for (i = 0; i < STERNE; ++i) {
        y = (unsigned char)(stern_y[i] + 1);
        ze = (unsigned char)(y >> 3);
        p = stern_p[i];

        if (ze != stern_ze[i]) {
            /* it has left its cell: wipe the old one first */
            hg_zeichen[p] = Z_LEER;
            hg_farbe[p] = C_SCHWARZ;
            if (!stern_zu[i]) { BILD[p] = Z_LEER; FARBE[p] = C_SCHWARZ; }

            if (ze >= BALKEN_ZEILE) { stern_neu(i, 0); continue; }

            stern_ze[i] = ze;
            p = zeilenanfang[ze] + stern_sp[i];
            stern_p[i] = p;
            stern_zu[i] = (unsigned char)(stern_sp[i] < PUNKTE_SP && ze <= 2);
            hg_farbe[p] = stern_f[i];
            if (!stern_zu[i]) FARBE[p] = stern_f[i];
        }

        stern_y[i] = y;
        code = (unsigned char)(Z_STERN + ((y & 7) << 2) + stern_x4[i]);
        stern_z[i] = code;
        hg_zeichen[p] = code;
        if (!stern_zu[i]) BILD[p] = code;
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
/*
 * The strip is twenty cells wide and eight pixels tall: six digits of two
 * cells each, then the remaining ships. It sits on one row of characters and
 * is written straight into the character set - there is no second copy of it
 * in RAM and nothing is shifted.
 *
 * It used to be different. While the background was moved by the TED's fine
 * scroll, the score had to be redrawn a pixel higher on every single pass to
 * stay put, which meant keeping a pixel image of it and copying three hundred
 * odd bytes per pass. The scroll stands still now (see scrollen()), so a
 * digit is eight bytes into a character and nothing else. What used to cost
 * a fifth of every pass now costs nothing until the score changes, and then
 * about a twentieth of one.
 */
#define ANZ_ZEILE 1                    /* the cell row it stands on        */

static unsigned char punkte_z[6];        /* the six digits - this *is* the score */
static unsigned char bonus_gegeben;      /* the extra ship at 5000          */

/* The player's ship as it appears next to the score, one 2600 pixel per bit. */
static const unsigned char SCHIFF_KLEIN[8] = {
    0x00, 0x10, 0x10, 0x38, 0x38, 0x7C, 0x6C, 0x00
};

/*
 * Writes one shape, eight 2600 pixels wide, into the two characters of a
 * column pair, doubling it on the way.
 *
 * Keeping the ten digits ready-doubled in a table was tried and is a third
 * *slower*: cc65 reaches an absolute array like VERDOPPELT with one
 * instruction, while reading the same byte through a pointer costs an index
 * calculation every time. Eight rounds of two bytes also beat sixteen rounds
 * of one - a loop iteration here costs more than the work inside it.
 */
static void anz_paar(unsigned char sp, const unsigned char *q)
{
    unsigned char *z1 = zeichensatz + ((unsigned)(Z_PUNKTE + sp) << 3);
    unsigned char *z2 = z1 + 8;
    unsigned char r, b;

    for (r = 0; r < 8; ++r) {
        b = q[r];
        z1[r] = VERDOPPELT[b >> 4];
        z2[r] = VERDOPPELT[b & 15];
    }
}

static void anz_paar_leer(unsigned char sp)
{
    unsigned char *z = zeichensatz + ((unsigned)(Z_PUNKTE + sp) << 3);
    unsigned char r;
    for (r = 0; r < 16; ++r) z[r] = 0;
}

/* One digit of the score. */
static void ziffer_bauen(unsigned char i)
{
    anz_paar((unsigned char)(i + i), romfont + (48 + punkte_z[i]) * 8);
}

/* The remaining ships, right of the score. */
static void leben_bauen(void)
{
    unsigned char i;

    for (i = 0; i < 4; ++i) {
        if (i + 1 < leben) anz_paar((unsigned char)(12 + i + i), SCHIFF_KLEIN);
        else               anz_paar_leer((unsigned char)(12 + i + i));
    }
}

/* The whole strip - at the start of a game and after the screen is wiped. */
static void anzeige_bauen(void)
{
    unsigned char i;

    for (i = 0; i < 6; ++i) ziffer_bauen(i);
    leben_bauen();
}

/*
 * Adds to the score, digit by digit and with a carry, so nothing has to be
 * divided. Six digits out of a 32 bit number means six calls to cc65's long
 * division - fifteen thousand cycles, most of a frame, and it showed as a
 * hitch every time a bird died. The digits *are* the score now; there is no
 * number behind them.
 */
static void punkte_dazu(unsigned wert)
{
    unsigned char zif[6];
    unsigned char i, summe, uebertrag;

    for (i = 0; i < 6; ++i) zif[i] = 0;
    while (wert >= 1000) { wert -= 1000; ++zif[2]; }
    while (wert >= 100)  { wert -= 100;  ++zif[3]; }
    while (wert >= 10)   { wert -= 10;   ++zif[4]; }
    zif[5] = (unsigned char)wert;

    uebertrag = 0;
    i = 6;
    while (i--) {
        summe = (unsigned char)(punkte_z[i] + zif[i] + uebertrag);
        if (summe >= 10) { summe = (unsigned char)(summe - 10); uebertrag = 1; }
        else uebertrag = 0;
        if (summe != punkte_z[i]) { punkte_z[i] = summe; ziffer_bauen(i); }
    }

    /* one extra ship at five thousand, as on the 2600 */
    if (!bonus_gegeben && leben < 6 &&
        (punkte_z[0] || punkte_z[1] || punkte_z[2] >= 5)) {
        bonus_gegeben = 1;
        ++leben;
        leben_bauen();
    }
}

/* Puts the strip's cells on the screen. They only go missing when something
   wipes the whole screen, so this does nothing almost every time. */
static void anzeige_zeichnen(void)
{
    unsigned char sp;
    unsigned p;

    if (anz_gesetzt) return;
    anz_gesetzt = 1;
    anz_zeile = ANZ_ZEILE;

    p = zeilenanfang[ANZ_ZEILE];
    for (sp = 0; sp < PUNKTE_SP; ++sp) {
        BILD[p + sp] = (unsigned char)(Z_PUNKTE + sp);
        FARBE[p + sp] = C_WEISS;
    }
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
#define SCHILD_ZEICHEN 12    /* the ship in its field is five cells by two   */
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
static unsigned char *fig_zeiger[FIG_N + SCH_N]; /* and where it lives      */
static unsigned char fig_zahl[FIG_N + SCH_N];    /* how many characters      */
static unsigned char fig_n;                      /* slots for birds         */

static void vorrat_verteilen(unsigned char gross, unsigned char voegel)
{
    unsigned char i, code;

    fig_n = voegel;
    code = Z_VORRAT;
    /* The ship's slot also carries it standing in its force field, which is
       five cells by two - the ship alone is three by two. */
    fig_basis[0] = code;
    fig_zeiger[0] = zeichensatz + ((unsigned)code << 3);
    fig_zahl[0] = SCHILD_ZEICHEN;
    code = (unsigned char)(code + SCHILD_ZEICHEN);

    for (i = 1; i < FIG_N; ++i) {
        fig_basis[i] = code;
        fig_zeiger[i] = zeichensatz + ((unsigned)code << 3);
        fig_zahl[i] = (unsigned char)(i <= voegel ? gross : 0);
        if (i <= voegel) code = (unsigned char)(code + gross);
    }
    /* The shot and the shots the birds drop need six characters each and
       get eight; the force field is five cells by two and needs ten. Writing
       more characters than a figure owns runs straight into the next one. */
    for (i = 0; i < SCH_N; ++i) {
        fig_basis[FIG_N + i] = code;
        fig_zeiger[FIG_N + i] = zeichensatz + ((unsigned)code << 3);
        fig_zahl[FIG_N + i] = 8;
        code = (unsigned char)(code + 8);
    }
}

/* ---- the shapes, one bit per 2600 pixel -------------------------------- */

/*
 * All of these are traced off screenshots of the original, pixel by pixel,
 * rather than drawn by eye - which is what they were at first, and it showed.
 * The 2600 gives each sprite a different colour on different scanlines; a
 * Plus/4 character cell can only hold one, so the shapes are exact and the
 * colours are the dominant one of each.
 */

/*
 * Where the ship and its field stand. Two things to know before moving
 * these: the blitter puts a figure eight pixels below the y it is given - an
 * old scroll compensation that stayed behind when the scrolling went - and a
 * figure's block must not reach character row 23, which is the ground band,
 * or it cuts a hole in it and leaves it there.
 *
 * The 2600 stands its ship right on the band with a pixel to spare, and
 * closes the field around it down to the band itself. Both come out exactly
 * that way here.
 */
#define SCHIFF_Y     165     /* shows at 173..182, the band starts at 184   */
#define EI_UNTEN     167     /* the lowest a falling shot may be drawn      */
#define SCHIFF_BREIT   8
#define SCHIFF_HOCH   10
/* the field reaches four pixels past the ship on either side, so the ship
   keeps that much clear of both edges */
#define SCHILD_LINKS   4
#define SCHILD_OBEN    4
#define SCHILD_BREIT  16
#define SCHILD_HOCH   15
#define SCHILD_Y      (SCHIFF_Y - SCHILD_OBEN)
#define SCHIFF_LINKS  SCHILD_LINKS
#define SCHIFF_RECHTS 148

/*
 * The player's ship, read out of a running original: seven 2600 pixels
 * across and ten tall, a nose with two pods beside it. The shape here was
 * drawn off a still picture before and had the pods in the wrong place.
 */
static const unsigned char SCHIFF[10] = {
    0x10,   /*  ...#....  */
    0x92,   /*  #..#..#.  */
    0xD6,   /*  ##.#.##.  */
    0x54,   /*  .#.#.#..  */
    0x38,   /*  ..###...  */
    0x38,   /*  ..###...  */
    0x7C,   /*  .#####..  */
    0xD6,   /*  ##.#.##.  */
    0x92,   /*  #..#..#.  */
    0x82    /*  #.....#.  */
};

/*
 * Both kinds of shot are thin vertical stripes on the original, one 2600
 * pixel wide - the ship's six scanlines tall, what the birds drop five.
 * They used to be a round blob here, which is both wrong and worse: a wide
 * shape covers more character cells, and every cell it covers is one the
 * bird underneath it has to share.
 */
static const unsigned char SCHUSS[6] = {
    0x10, 0x10, 0x10, 0x10, 0x10, 0x10
};

/* The small bird of waves one and two, wings in and wings out. */
static const unsigned char VOGEL_ENG[8] = {
    0x5A,   /*  # ## #  */
    0x42,   /*  #    #  */
    0x66,   /*  ##  ##  */
    0x7E,   /*  ######  */
    0x7E,   /*  ######  */
    0x5A,   /*  # ## #  */
    0x5A,   /*  # ## #  */
    0x24    /*   #  #   */
};

static const unsigned char VOGEL_WEIT[8] = {
    0x5A,   /*  # ## #  */
    0xC3,   /* ##    ## */
    0xE7,   /* ###  ### */
    0xFF,   /* ######## */
    0xBD,   /* # #### # */
    0x99,   /* #  ##  # */
    0x99,   /* #  ##  # */
    0x24    /*   #  #   */
};

/*
 * The large bird of waves three and four, sixteen 2600 pixels across and ten
 * tall, in three wing positions. Its wings are the outer six pixels on each
 * side and its body the middle four - that is where a shot has to go.
 */
static const unsigned char GROSS_A[20] = {
    0x01, 0x80,   /*        ##        */
    0x03, 0xC0,   /*       ####       */
    0x3F, 0xFC,   /*   ############   */
    0x7D, 0xBE,   /*  ##### ## #####  */
    0x7F, 0xFE,   /*  ##############  */
    0xFB, 0xDF,   /* ##### #### ##### */
    0xC2, 0x43,   /* ##    #  #    ## */
    0x02, 0x40,   /*       #  #       */
    0x02, 0x40,   /*       #  #       */
    0x04, 0x20    /*      #    #      */
};

static const unsigned char GROSS_B[20] = {
    0x01, 0x80,   /*        ##        */
    0x03, 0xC0,   /*       ####       */
    0x0F, 0xF0,   /*     ########     */
    0x1D, 0xB8,   /*    ### ## ###    */
    0x3F, 0xFC,   /*   ############   */
    0x7B, 0xDE,   /*  #### #### ####  */
    0x62, 0x46,   /*  ##   #  #   ##  */
    0xC2, 0x43,   /* ##    #  #    ## */
    0x82, 0x41,   /* #     #  #     # */
    0x04, 0x20    /*      #    #      */
};

static const unsigned char GROSS_C[20] = {
    0x10, 0x08,   /*    #        #    */
    0x39, 0x9C,   /*   ###  ##  ###   */
    0x7F, 0xFE,   /*  ##############  */
    0xFF, 0xFF,   /* ################ */
    0xCD, 0xB3,   /* ##  ## ## ##  ## */
    0x07, 0xE0,   /*      ######      */
    0x03, 0xC0,   /*       ####       */
    0x02, 0x40,   /*       #  #       */
    0x04, 0x20,   /*      #    #      */
    0x00, 0x00
};

/* What a bird leaves behind, two frames of it. */
static const unsigned char KNALL1[8] = {
    0x00, 0x18, 0x24, 0x42, 0x42, 0x24, 0x18, 0x00
};

static const unsigned char KNALL2[8] = {
    0x81, 0x42, 0x00, 0x24, 0x24, 0x00, 0x42, 0x81
};

/*
 * The egg a large bird arrives in. Waves three and four "begin with eggs
 * floating down in a zigzag pattern, which then turn into Phoenixes".
 */
static const unsigned char GROSSEI[8] = {
    0x00,
    0x3C,   /*   ####   */
    0x7E,   /*  ######  */
    0xFF,   /* ######## */
    0xFF,   /* ######## */
    0x7E,   /*  ######  */
    0x3C,   /*   ####   */
    0x00
};

/* What the birds drop. */
static const unsigned char EI[5] = {
    0x10, 0x10, 0x10, 0x10, 0x10
};

/*
 * The ship standing in its force field, read out of a running original as
 * one picture: an arch sixteen 2600 pixels across and fifteen tall with the
 * ship inside it, four pixels down and four in from the left, open at the
 * bottom where the ship stands on the ground.
 *
 * It is one shape here and not an arch drawn over the ship, because the two
 * are only fifteen pixels tall together and would share both of their
 * character rows - and a cell holds one character and one colour. As one
 * shape there is nothing to share: while the field is up the ship is drawn
 * as this instead, in white.
 *
 * The console draws the field on every other frame and leaves it off in
 * between, which is how a 2600 shows two things that share one sprite. At
 * fifty frames a second that reads as a shimmer; we redraw twenty times a
 * second, where the same trick would be a ten hertz blink, so the field
 * simply stands while it is up.
 */
static const unsigned char SCHILD[30] = {
    0x03, 0xC0,   /*  ......####......  */
    0x0F, 0xF0,   /*  ....########....  */
    0x3F, 0xFC,   /*  ..############..  */
    0xFC, 0x3F,   /*  ######....######  */
    0xF1, 0x0F,   /*  ####...#....####  */
    0xC9, 0x23,   /*  ##..#..#..#...##  */
    0xCD, 0x63,   /*  ##..##.#.##...##  */
    0xC5, 0x43,   /*  ##...#.#.#....##  */
    0xC3, 0x83,   /*  ##....###.....##  */
    0xC3, 0x83,   /*  ##....###.....##  */
    0xC7, 0xC3,   /*  ##...#####....##  */
    0xCD, 0x63,   /*  ##..##.#.##...##  */
    0xC9, 0x23,   /*  ##..#..#..#...##  */
    0xC8, 0x23,   /*  ##..#.....#...##  */
    0xF0, 0x0F    /*  ####........####  */
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
#define FORM_SCHILD  5
#define FORM_VOGEL   7    /* small bird, two flapping frames              */
#define FORM_GROSS   7    /* large bird, two flapping frames              */
#define FORM_GROSS_L 9    /* right wing shot off                          */
#define FORM_GROSS_R 10   /* left wing shot off                           */
#define FORM_GROSS_0 11   /* both wings gone                              */
#define FORM_GROSSEI 12   /* the egg it arrives in                        */
#define FORMEN_N    13

/*
 * Room for all views of all shapes of one wave, with a little to spare. The
 * largest set is waves three and four, which needs 27648 bytes: five large
 * birds at 120 bytes a view and the rest at 48, each in 32 views, plus the
 * ship and the force field at 72 bytes in four views each - those two never
 * leave the bottom of the screen and do not need the other 28. Going over
 * this would quietly write past the end of the array, so the number wants
 * checking when a shape grows.
 */
#define BLOCKRAUM 27904

static unsigned char bloecke[BLOCKRAUM];
static unsigned blockende;
static unsigned char *form_block[FORMEN_N];  /* where each shape starts     */
static unsigned char f_sp[FORMEN_N];         /* cells across               */
static unsigned char f_ze[FORMEN_N];         /* cells down                 */
static unsigned char f_n[FORMEN_N];          /* characters it uses         */
static unsigned form_stufe[FORMEN_N];        /* bytes from one view to next */
static unsigned char f_laenge[FORMEN_N];     /* bytes of one view, minus one */
/* A ready made pointer to every one of the 32 views of every shape. Working
   the address out instead would mean a 16 bit multiplication per figure and
   per frame, which cc65 does with a subroutine call. */
static unsigned char *form_sicht[FORMEN_N * 32];
static unsigned char **form_sicht_von[FORMEN_N];
static unsigned char *zeile_bild[ZEILEN];    /* screen address of each row  */
static unsigned char *zeile_farbe[ZEILEN];   /* and its colour cells        */
static unsigned char *zeile_hg[ZEILEN];      /* the shadow copy of both     */
static unsigned char *zeile_hgf[ZEILEN];

/*
 * Works out all 32 views of one shape. The shape is stored one bit per 2600
 * pixel; it is doubled in width here and shifted to the right by twice the
 * horizontal position, which is why a shape eight 2600 pixels wide can reach
 * into three cells.
 *
 * maske1 and maske2 are laid over the shape data first. That is how the
 * large birds lose a wing: the same picture, with one side masked away.
 */
/*
 * lage is which of the eight vertical positions a shape needs. Most shapes
 * can stand anywhere and take LAGE_ALLE, which builds all 32 views. The ship
 * and its force field never leave the bottom of the screen, so they only
 * ever ask for one of the eight - building the other seven would cost two
 * kilobytes each, and there is not that much room.
 */
#define LAGE_ALLE 255
/* where the blitter looks a figure up: (y + 8 - fine scroll) & 7, and the
   fine scroll has stood at zero since the stars took over the scrolling */
#define LAGE_SCHIFF ((SCHIFF_Y + 8) & 7)
#define LAGE_SCHILD ((SCHILD_Y + 8) & 7)

static void form_ablegen(unsigned char nr, const unsigned char *daten,
                         unsigned char w2, unsigned char h,
                         unsigned char maske1, unsigned char maske2,
                         unsigned char lage)
{
    unsigned char zeile[16][5];
    unsigned char breit[4];
    unsigned char p, r, i, w, s, voff, py, zr, sp, ze, roh;
    unsigned char *block;
    unsigned gr;

    w = (unsigned char)(w2 + w2);
    sp = (unsigned char)(w + 1);
    /* A shape that can stand anywhere has to reserve a row for the worst
       case. One that always stands at the same height needs exactly as many
       rows as it covers there, which for the ship and the field is one row
       less - and that one row is what keeps them off the ground band. */
    ze = (unsigned char)(lage == LAGE_ALLE ? (h + 14) >> 3
                                           : (lage + h + 7) >> 3);
    f_sp[nr] = sp;
    f_ze[nr] = ze;
    f_n[nr] = (unsigned char)(sp * ze);
    gr = (unsigned)f_n[nr] * 8;
    form_stufe[nr] = gr;
    form_block[nr] = bloecke + blockende;
    blockende += gr * (lage == LAGE_ALLE ? 32 : 4);

    f_laenge[nr] = (unsigned char)(f_n[nr] * 8 - 1);
    form_sicht_von[nr] = &form_sicht[nr * 32];
    /* A shape with a fixed height has four blocks, one per horizontal
       position, and all eight entries of a position point at the same one. */
    for (p = 0; p < 32; ++p)
        form_sicht[nr * 32 + p] = form_block[nr]
            + (unsigned)(lage == LAGE_ALLE ? p : (p >> 3)) * gr;

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
            if (lage != LAGE_ALLE && voff != lage) continue;
            block = form_block[nr] + ((unsigned)(lage == LAGE_ALLE
                                                 ? p * 8 + voff : p) * gr);
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
    form_ablegen(FORM_SCHIFF, SCHIFF, 1, 10, 0xFF, 0xFF, LAGE_SCHIFF);
    form_ablegen(FORM_SCHUSS, SCHUSS, 1, 6, 0xFF, 0xFF, LAGE_ALLE);
    form_ablegen(FORM_KNALL,     KNALL1, 1, 8, 0xFF, 0xFF, LAGE_ALLE);
    form_ablegen(FORM_KNALL + 1, KNALL2, 1, 8, 0xFF, 0xFF, LAGE_ALLE);
    form_ablegen(FORM_EI, EI, 1, 5, 0xFF, 0xFF, LAGE_ALLE);
    form_ablegen(FORM_SCHILD, SCHILD, 2, 15, 0xFF, 0xFF, LAGE_SCHILD);
}

static void formen_klein(void)
{
    formen_grundstock();
    form_ablegen(FORM_VOGEL,     VOGEL_ENG,  1, 8, 0xFF, 0xFF, LAGE_ALLE);
    form_ablegen(FORM_VOGEL + 1, VOGEL_WEIT, 1, 8, 0xFF, 0xFF, LAGE_ALLE);
}

/*
 * The large birds. Their wings are the outer six 2600 pixels on each side and
 * the body is the middle four, so the shot-off states are the same picture
 * with one side masked away - no second drawing needed, and no second set of
 * blocks either.
 */
#define FL_LINKS  0xFC       /* the left wing in the first byte  */
#define FL_RECHTS 0x3F       /* the right wing in the second     */

static void formen_gross(void)
{
    formen_grundstock();
    form_ablegen(FORM_GROSS,     GROSS_A, 2, 10, 0xFF, 0xFF, LAGE_ALLE);
    form_ablegen(FORM_GROSS + 1, GROSS_C, 2, 10, 0xFF, 0xFF, LAGE_ALLE);
    form_ablegen(FORM_GROSS_L, GROSS_B, 2, 10, 0xFF, (unsigned char)~FL_RECHTS, LAGE_ALLE);
    form_ablegen(FORM_GROSS_R, GROSS_B, 2, 10, (unsigned char)~FL_LINKS, 0xFF, LAGE_ALLE);
    form_ablegen(FORM_GROSS_0, GROSS_B, 2, 10, (unsigned char)~FL_LINKS,
                 (unsigned char)~FL_RECHTS, LAGE_ALLE);
    form_ablegen(FORM_GROSSEI, GROSSEI, 1, 8, 0xFF, 0xFF, LAGE_ALLE);
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
unsigned char fz_zahl;          /* how many characters this figure owns     */

/*
 * A cell shows one character, so where two figures meet, one of them used to
 * lose a whole eight by eight block - very visible when a shot crosses a
 * bird. Instead of taking the cell away, this ORs our pixels into the
 * character that is already standing there. Nothing is lost, and nothing has
 * to be undone either: every figure copies its block over its own characters
 * again on the next pass, which wipes the borrowed pixels.
 *
 * The cell keeps the colour of whoever got there first. That is the price,
 * and it is a far smaller one than a hole in a bird.
 *
 * Comes back with the carry set, so the caller can branch on it - cc65
 * throws away any label that is only reached by an unconditional jump.
 */
static void figur_mischen(void)
{
    __asm__(
    "stx tmp4\n"               /* the cell counter                         */
    "lda (ptr3),y\n"           /* the character already in the cell        */
    "sty ptr4\n"               /* and which cell we are on                 */

    ";  ptr2 = character set + that character times eight\n"
    "sta ptr2\n"
    "lda #$00\n"
    "sta ptr2+1\n"
    "asl ptr2\n"  "rol ptr2+1\n"
    "asl ptr2\n"  "rol ptr2+1\n"
    "asl ptr2\n"  "rol ptr2+1\n"
    "lda ptr2\n"
    "clc\n"
    "adc %v\n"
    "sta ptr2\n"
    "lda ptr2+1\n"
    "adc %v+1\n"
    "sta ptr2+1\n"

    ";  ptr1 = character set + our own character times eight\n"
    "lda tmp3\n"
    "sta ptr1\n"
    "lda #$00\n"
    "sta ptr1+1\n"
    "asl ptr1\n"  "rol ptr1+1\n"
    "asl ptr1\n"  "rol ptr1+1\n"
    "asl ptr1\n"  "rol ptr1+1\n"
    "lda ptr1\n"
    "clc\n"
    "adc %v\n"
    "sta ptr1\n"
    "lda ptr1+1\n"
    "adc %v+1\n"
    "sta ptr1+1\n"

    ";  eight rows, our pixels added to theirs\n"
    "ldy #$07\n"
    "fmior:\n"
    "lda (ptr1),y\n"
    "ora (ptr2),y\n"
    "sta (ptr2),y\n"
    "dey\n"
    "bpl fmior\n"

    "ldx tmp4\n"
    "ldy ptr4\n"
    "sec\n"
    , zeichensatz, zeichensatz, zeichensatz, zeichensatz);
}

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

    ";  the colour memory sits exactly $400 below the screen\n"
    "fzrow:\n"
    "lda ptr3\n"
    "sta sreg\n"
    "lda ptr3+1\n"
    "sec\n"
    "sbc #$04\n"
    "sta sreg+1\n"

    "ldy #$00\n"
    "ldx %v\n"
    "lda tmp1\n"
    "sta tmp3\n"
    "fzcell:\n"
    ";  is somebody else already standing in this cell? Then we do not take\n"
    ";  it away from them - our pixels go into their character instead.\n"
    "lda (ptr3),y\n"
    "cmp #%b\n"                /* Z_VORRAT: below that it is background    */
    "bcc fznimm\n"
    "sec\n"
    "sbc %v\n"                 /* our own first character code             */
    "cmp %v\n"                 /* how many characters we own               */
    "bcc fznimm\n"
    "jsr %v\n"                 /* figur_mischen, comes back with carry set */
    "bcs fzweiter\n"
    "fznimm:\n"
    "lda tmp3\n"
    "sta (ptr3),y\n"
    "lda %v\n"
    "sta (sreg),y\n"
    "fzweiter:\n"
    "inc tmp3\n"
    "iny\n"
    "dex\n"
    "bne fzcell\n"

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
      fz_bild, fz_bild, fz_code, fz_nze,
      fz_nsp, (unsigned char)Z_VORRAT, fz_code, fz_zahl, figur_mischen, fz_farbe,
      fz_stufe);
}

/*
 * Draws a figure and releases the cells it no longer needs.
 *
 * nr      slot, 0..FIG_N-1 for figures, then the shot slots
 * form    which shape
 * x2      left edge in 2600 pixels
 * sy      top edge in screen pixels, 0 is the top of the playfield
 */
unsigned char fm_nr, fm_form, fm_x2, fm_sy, fm_farbe;
unsigned char fm_sp, fm_ze, fm_nsp, fm_nze, fm_voff, fm_zeende, fm_spende;

/*
 * Works out where a figure lands, hands back the cells it has left, and sets
 * the drawing routine going. This used to be C and was the single most
 * expensive thing in the program - a third of every pass - because cc65 keeps
 * parameters on a software stack, reads each one back through a zero page
 * pointer on every use, and widens byte arithmetic to sixteen bits at the
 * slightest excuse.
 *
 * Zero page: ptr1 screen row, ptr2 shadow characters, ptr3 shadow colours,
 *            ptr4 colour cells, tmp1..tmp4 counters.
 */
static void figur_asm(void)
{
    __asm__(
    ";  ---- where does it stand ----------------------------------------\n"
    "lda %v\n"                 /* fm_x2 */
    "and #$03\n"
    "asl a\n"
    "asl a\n"
    "asl a\n"
    "sta tmp1\n"               /* horizontal position times eight        */
    "lda %v\n"
    "lsr a\n"
    "lsr a\n"
    "sta %v\n"                 /* fm_sp = x2 / 4                         */

    "lda %v\n"                 /* fm_sy */
    "clc\n"
    "adc #$08\n"
    "sec\n"
    "sbc %v\n"                 /* minus the fine scroll                  */
    "sta tmp2\n"
    "and #$07\n"
    "ora tmp1\n"
    "sta %v\n"                 /* fm_voff: which of the 32 views          */
    "lda tmp2\n"
    "lsr a\n"
    "lsr a\n"
    "lsr a\n"
    "sta %v\n"                 /* fm_ze                                   */

    ";  ---- off the screen? -------------------------------------------\n"
    "cmp #%b\n"
    "bcs fmweg\n"
    "lda %v\n"
    "cmp #%b\n"
    "bcc fmda\n"
    "fmweg:\n"
    "lda %v\n"
    "jsr %v\n"                 /* figur_loeschen(nr)                      */
    "rts\n"

    ";  ---- how many cells, cut off at the edges ----------------------\n"
    "fmda:\n"
    "ldx %v\n"                 /* fm_form */
    "lda %v,x\n"               /* f_sp    */
    "sta %v\n"                 /* fm_nsp  */
    "lda %v,x\n"               /* f_ze    */
    "sta %v\n"                 /* fm_nze  */

    "clc\n"
    "adc %v\n"                 /* + fm_ze */
    "cmp #%b\n"
    "bcc fmzeok\n"
    "beq fmzeok\n"
    "lda #%b\n"
    "sec\n"
    "sbc %v\n"
    "sta %v\n"                 /* fm_nze = ZEILEN - ze                    */
    "lda #%b\n"
    "fmzeok:\n"
    "sta %v\n"                 /* fm_zeende                               */

    "lda %v\n"                 /* fm_nsp */
    "clc\n"
    "adc %v\n"                 /* + fm_sp */
    "cmp #%b\n"
    "bcc fmspok\n"
    "beq fmspok\n"
    "lda #%b\n"
    "sec\n"
    "sbc %v\n"
    "sta %v\n"                 /* fm_nsp = BREITE - sp                    */
    "lda #%b\n"
    "fmspok:\n"
    "sta %v\n"                 /* fm_spende                               */

    ";  ---- give back what it no longer covers -----------------------\n"
    ";  nothing to do while it stays on the same cells, which is the\n"
    ";  usual case - a figure crosses a cell border only now and then\n"
    "ldx %v\n"                 /* fm_nr */
    "lda %v,x\n"               /* bel_nsp */
    "beq fmmerk\n"
    "cmp %v\n"
    "bne fmfrei\n"
    "lda %v,x\n"               /* bel_nze */
    "cmp %v\n"
    "bne fmfrei\n"
    "lda %v,x\n"               /* bel_sp */
    "cmp %v\n"
    "bne fmfrei\n"
    "lda %v,x\n"               /* bel_ze */
    "cmp %v\n"
    "beq fmmerk\n"

    "fmfrei:\n"
    "lda #$00\n"
    "sta tmp1\n"               /* r, the row of the old rectangle          */
    "fmfz:\n"
    "ldx %v\n"
    "lda %v,x\n"               /* bel_ze */
    "clc\n"
    "adc tmp1\n"
    "sta tmp2\n"               /* alt = old top row + r                    */

    ";  is this row inside the new rectangle?\n"
    "lda #$00\n"
    "sta tmp4\n"
    "lda tmp2\n"
    "cmp %v\n"                 /* fm_ze */
    "bcc fmzn\n"
    "cmp %v\n"                 /* fm_zeende */
    "bcs fmzn\n"
    "inc tmp4\n"
    "fmzn:\n"

    ";  four row pointers, all indexed by the same cell number\n"
    "lda tmp2\n"
    "asl a\n"
    "tay\n"
    "ldx %v\n"
    "lda %v,y\n"               /* zeile_bild lo */
    "clc\n"
    "adc %v,x\n"               /* + bel_sp      */
    "sta ptr1\n"
    "lda %v+1,y\n"
    "adc #$00\n"
    "sta ptr1+1\n"
    "lda %v,y\n"               /* zeile_hg      */
    "clc\n"
    "adc %v,x\n"
    "sta ptr2\n"
    "lda %v+1,y\n"
    "adc #$00\n"
    "sta ptr2+1\n"
    "lda %v,y\n"               /* zeile_hgf     */
    "clc\n"
    "adc %v,x\n"
    "sta ptr3\n"
    "lda %v+1,y\n"
    "adc #$00\n"
    "sta ptr3+1\n"
    "lda %v,y\n"               /* zeile_farbe   */
    "clc\n"
    "adc %v,x\n"
    "sta ptr4\n"
    "lda %v+1,y\n"
    "adc #$00\n"
    "sta ptr4+1\n"

    "ldy #$00\n"
    "fmfs:\n"
    "ldx %v\n"                 /* fm_nr, needed on both ways out           */
    "lda tmp4\n"
    "beq fmweg2\n"             /* row outside - always give it back        */
    "tya\n"
    "clc\n"
    "adc %v,x\n"               /* bel_sp + c                               */
    "cmp %v\n"                 /* fm_sp                                    */
    "bcc fmweg2\n"
    "cmp %v\n"                 /* fm_spende                                */
    ";  still covered by the new rectangle, so leave it alone. The branch\n"
    ";  has to be the conditional one - cc65 throws away any label that is\n"
    ";  only reached by an unconditional jump.\n"
    "bcc fmnext\n"
    "fmweg2:\n"
    ";  Only hand a cell back if it still holds one of our own characters.\n"
    ";  Somebody else may have moved in over us since we took it, and the\n"
    ";  background would wipe them out.\n"
    "lda (ptr1),y\n"
    "sec\n"
    "sbc %v,x\n"               /* fig_basis,x                              */
    "cmp %v,x\n"               /* fig_zahl,x                               */
    "bcs fmnext\n"
    "lda (ptr2),y\n"
    "sta (ptr1),y\n"
    "lda (ptr3),y\n"
    "sta (ptr4),y\n"
    "fmnext:\n"
    "iny\n"
    "ldx %v\n"
    "tya\n"
    "cmp %v,x\n"               /* cpy has no indexed mode, so compare in A */
    "bcc fmfs\n"

    "inc tmp1\n"
    "ldx %v\n"
    "lda tmp1\n"
    "cmp %v,x\n"               /* bel_nze                                  */
    "bcc fmfz\n"

    ";  ---- remember the new rectangle -------------------------------\n"
    "fmmerk:\n"
    "ldx %v\n"
    "lda %v\n"  "sta %v,x\n"   /* bel_sp  = fm_sp  */
    "lda %v\n"  "sta %v,x\n"   /* bel_ze  = fm_ze  */
    "lda %v\n"  "sta %v,x\n"   /* bel_nsp = fm_nsp */
    "lda %v\n"  "sta %v,x\n"   /* bel_nze = fm_nze */

    ";  ---- hand the drawing routine its addresses -------------------\n"
    "lda %v\n"                 /* fm_form */
    "asl a\n"
    "tay\n"
    "lda %v,y\n"               /* form_sicht_von */
    "sta ptr1\n"
    "lda %v+1,y\n"
    "sta ptr1+1\n"
    "lda %v\n"                 /* fm_voff */
    "asl a\n"
    "tay\n"
    "lda (ptr1),y\n"
    "sta %v\n"                 /* fz_block */
    "iny\n"
    "lda (ptr1),y\n"
    "sta %v+1\n"

    "lda %v\n"                 /* fm_nr */
    "asl a\n"
    "tay\n"
    "lda %v,y\n"               /* fig_zeiger */
    "sta %v\n"                 /* fz_ziel    */
    "lda %v+1,y\n"
    "sta %v+1\n"

    "lda %v\n"                 /* fm_ze */
    "asl a\n"
    "tay\n"
    "lda %v,y\n"               /* zeile_bild */
    "clc\n"
    "adc %v\n"                 /* + fm_sp    */
    "sta %v\n"                 /* fz_bild    */
    "lda %v+1,y\n"
    "adc #$00\n"
    "sta %v+1\n"

    "ldx %v\n"                 /* fm_nr */
    "lda %v,x\n"               /* fig_basis */
    "sta %v\n"                 /* fz_code   */
    "lda %v,x\n"               /* fig_zahl  */
    "sta %v\n"                 /* fz_zahl   */
    "lda %v\n"  "sta %v\n"     /* fz_farbe  */
    "lda %v\n"  "sta %v\n"     /* fz_nsp    */
    "lda %v\n"  "sta %v\n"     /* fz_nze    */
    "ldx %v\n"                 /* fm_form   */
    "lda %v,x\n" "sta %v\n"    /* fz_stufe  */
    "lda %v,x\n" "sta %v\n"    /* fz_laenge */
    "jsr %v\n"                 /* figur_bloecken */
    , fm_x2, fm_x2, fm_sp,
      fm_sy, yfein, fm_voff, fm_ze,
      (unsigned char)ZEILEN, fm_sp, (unsigned char)BREITE,
      fm_nr, figur_loeschen,
      fm_form, f_sp, fm_nsp, f_ze, fm_nze,
      fm_ze, (unsigned char)ZEILEN, (unsigned char)ZEILEN, fm_ze, fm_nze,
      (unsigned char)ZEILEN, fm_zeende,
      fm_nsp, fm_sp, (unsigned char)BREITE, (unsigned char)BREITE, fm_sp,
      fm_nsp, (unsigned char)BREITE, fm_spende,
      fm_nr, bel_nsp, fm_nsp, bel_nze, fm_nze, bel_sp, fm_sp, bel_ze, fm_ze,
      fm_nr, bel_ze,
      fm_ze, fm_zeende,
      fm_nr, zeile_bild, bel_sp, zeile_bild,
      zeile_hg, bel_sp, zeile_hg,
      zeile_hgf, bel_sp, zeile_hgf,
      zeile_farbe, bel_sp, zeile_farbe,
      fm_nr, bel_sp, fm_sp, fm_spende, fig_basis, fig_zahl,
      fm_nr, bel_nsp,
      fm_nr, bel_nze,
      fm_nr,
      fm_sp, bel_sp, fm_ze, bel_ze, fm_nsp, bel_nsp, fm_nze, bel_nze,
      fm_form, form_sicht_von, form_sicht_von, fm_voff, fz_block, fz_block,
      fm_nr, fig_zeiger, fz_ziel, fig_zeiger, fz_ziel,
      fm_ze, zeile_bild, fm_sp, fz_bild, zeile_bild, fz_bild,
      fm_nr, fig_basis, fz_code, fig_zahl, fz_zahl,
      fm_farbe, fz_farbe, fm_nsp, fz_nsp, fm_nze, fz_nze,
      fm_form, f_sp, fz_stufe, f_laenge, fz_laenge,
      figur_bloecken);
}

static void figur_malen(unsigned char nr, unsigned char form,
                        unsigned char x2, unsigned char sy, unsigned char farbe)
{
    fm_nr = nr;
    fm_form = form;
    fm_x2 = x2;
    fm_sy = sy;
    fm_farbe = farbe;
    figur_asm();
}

/* Takes a figure off the screen. */

/*
 * Takes a figure off the screen again. A cell only goes back to background
 * if it still holds one of this figure's own characters: somebody else may
 * have moved in over it since, and handing that cell back would wipe them.
 */
static void figur_loeschen(unsigned char nr)
{
    unsigned char r, c, code;
    unsigned p;

    if (!bel_nsp[nr]) return;
    for (r = 0; r < bel_nze[nr]; ++r) {
        p = zeilenanfang[bel_ze[nr] + r] + bel_sp[nr];
        for (c = 0; c < bel_nsp[nr]; ++c) {
            code = (unsigned char)(BILD[p] - fig_basis[nr]);
            if (code < fig_zahl[nr]) {
                BILD[p] = hg_zeichen[p];
                FARBE[p] = hg_farbe[p];
            }
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

/*
 * Counting in passes has one bad habit: a pass gets shorter as the flock is
 * shot away, so the game quietly speeds up towards the end of a wave. The
 * birds are therefore run off the KERNAL's clock instead, which the machine
 * ticks sixty times a second no matter what we are drawing, and every speed
 * taken off the original below is given in pixels per tick.
 */
#define UHR (*(volatile unsigned char *)0x00A5)

static unsigned char uhr_alt;
static unsigned char takte;          /* ticks since the pass before        */

/*
 * Adds up a speed given in 32nds of a pixel per tick and hands back the
 * whole pixels that have come due, keeping the remainder for next time.
 */
static unsigned char schritt(unsigned char tempo, unsigned char *rest)
{
    unsigned wert = (unsigned)*rest + (unsigned)tempo * takte;
    *rest = (unsigned char)(wert & 31);
    return (unsigned char)(wert >> 5);
}

/*
 * Reads how long the pass before took. A pass is five ticks or so; the cap
 * is there for the pauses between waves, after which nothing should jump
 * half a screen to catch up.
 */
static void takt_messen(void)
{
    unsigned char jetzt = UHR;
    unsigned char d = (unsigned char)(jetzt - uhr_alt);
    if (d == 0) d = 1;
    if (d > 12) d = 12;
    uhr_alt = jetzt;
    takte = d;
}

#define SPIEL_OBEN    24     /* first pixel row below the score             */

/* Where the ship and its force field stand is set out with the shapes in
   section 6 - the shape tables need those numbers before this point. */

/*
 * The ship and its shot, measured off the original the same way as the
 * birds: the demo the console plays to itself moves its ship one pixel a
 * frame, and a shot leaves it at eight. The ship is slower than it feels
 * like it should be - three seconds from one side of the screen to the
 * other - and that slowness is half of what makes Phoenix Phoenix.
 */
#define TEMPO_SCHIFF  27     /* 32nds/tick: 1 pixel per frame              */
#define TEMPO_SCHUSS 213     /* 32nds/tick: 8 pixels per frame             */

#define SCHILD_DAUER  90     /* ticks: one and a half seconds               */
#define SCHILD_PAUSE 210     /* ticks: three and a half before it works again */

#define SLOT_SCHIFF   0
#define SLOT_SCHUSS   FIG_N
#define SLOT_EI       (FIG_N + 1)
#define EIER          4

static unsigned char spieler_x;
static unsigned char rest_schiff, rest_schuss;
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
    figur_loeschen(SLOT_SCHIFF);
}

static void spieler_steuern(unsigned char s)
{
    unsigned char feuer = (unsigned char)(s & ST_FEUER);
    unsigned char weit = schritt(TEMPO_SCHIFF, &rest_schiff);

    if (schild_sperre)
        schild_sperre = (unsigned char)(schild_sperre > takte ?
                                        schild_sperre - takte : 0);

    if (schild_zeit) {
        schild_zeit = (unsigned char)(schild_zeit > takte ?
                                      schild_zeit - takte : 0);
        if (schild_zeit == 0) {
            schild_sperre = SCHILD_PAUSE;
            /* the ship shrinks back to itself; the wider figure lets go of
               the cells it no longer covers on its next pass */
        }
    } else {
        if ((s & ST_SCHILD) && !schild_sperre) {
            schild_zeit = SCHILD_DAUER;
        } else {
            if (s & ST_LINKS) {
                spieler_x = (unsigned char)(spieler_x - weit);
                if (spieler_x < SCHIFF_LINKS || spieler_x > 200)
                    spieler_x = SCHIFF_LINKS;
            }
            if (s & ST_RECHTS) {
                spieler_x = (unsigned char)(spieler_x + weit);
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
    schuss_y = (unsigned char)(schuss_y - schritt(TEMPO_SCHUSS, &rest_schuss));
    if (schuss_y < SPIEL_OBEN || schuss_y > 200) {
        schuss_aktiv = 0;
        figur_loeschen(SLOT_SCHUSS);
    }
}

static void spieler_malen(void)
{
    /*
     * The field goes down before the ship. Both are only fifteen pixels
     * tall between them, so they share the same two character rows, and a
     * cell holds one colour: whoever draws first keeps it and the other one
     * has its pixels put into that cell. Drawing the field first makes the
     * arch white and the ship inside it white with it, which reads as a
     * ship standing in a field. The other way round the arch takes the
     * ship's orange, and its closed top sits on the ship like a lump.
     */
    if (schild_zeit)
        figur_malen(SLOT_SCHIFF, FORM_SCHILD,
                    (unsigned char)(spieler_x - SCHILD_LINKS),
                    (unsigned char)SCHILD_Y, C_WEISS);
    else
        figur_malen(SLOT_SCHIFF, FORM_SCHIFF, spieler_x, SCHIFF_Y, C_SCHIFF);
    if (schuss_aktiv)
        figur_malen(SLOT_SCHUSS, FORM_SCHUSS, schuss_x, schuss_y, C_GELB);
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
#define V_BODEN   3   /* levelled out, running along the bottom of the swoop */
#define V_RUECK   4
#define V_TOT     5
#define V_EI      6   /* still an egg, on its way down */

/* anything that has left the formation and can be run into */
#define IM_FLUG(z) ((z) >= V_STURZ && (z) <= V_RUECK)

/*
 * The numbers below were read off the original, frame by frame: the ROM was
 * run in Stella, stopped after every single frame and photographed, and the
 * birds measured out of those pictures. The PAL machine draws fifty frames a
 * second and its playfield is as tall as ours, so a scanline there is a
 * pixel here and the speeds carry over as they are.
 *
 *   flock          eight birds in a ring, four heights eighteen apart,
 *                  never descends, drifts sideways one pixel every three
 *                  frames and turns round at the edge of the screen
 *   swoop          two birds at a time leave the bottom of the ring and go
 *                  down four pixels every three frames - dead steady, no
 *                  gathering speed and no aiming at the ship
 *   bottom         they level out well above the ship and run along for
 *                  about a second before climbing back at the same rate
 *   pause          a second or so passes before the next two leave
 *   shots          fall eight pixels every three frames, twice a swoop
 *
 * That is a far quieter attack than the one this was before, and it is what
 * the console actually does: in the first wave the birds never reach the
 * ship at all, and what kills you is what they drop.
 */
#define TEMPO_STURZ  36      /* 32nds/tick: 4 pixels per 3 frames          */
#define TEMPO_FORM    9      /* 32nds/tick: 1 pixel per 3 frames           */
#define TEMPO_SEIT   20      /* 32nds/tick: sideways swing during a swoop  */
#define TEMPO_EI     71      /* 32nds/tick: 8 pixels per 3 frames          */

#define EI_TAKT      15      /* ticks between two shots from the flock     */
#define BODEN_DAUER  56      /* ticks along the bottom, 47 frames          */
#define PAUSE_DAUER  65      /* ticks before the next pair leaves          */
#define SCHWUNG_DAUER 34     /* ticks before the sideways swing turns      */

/* A bird bottoms out with thirteen pixels of air left under it. */
#define STURZ_ENDE (SCHIFF_Y - 13 - 8)

#define VOEGEL       8
#define V_SPALTEN    4
#define V_ABSTAND   30       /* distance inside the formation, 2600 pixels */
#define V_ZEILE     18
#define V_OBEN      33       /* where the formation sits                   */

/* The ring the first two waves sit in, measured off the original. */
static const unsigned char RING_X[VOEGEL] = { 13, 37,  0, 51,  0, 51, 13, 37 };
static const unsigned char RING_Y[VOEGEL] = {  0,  0, 18, 18, 36, 36, 54, 54 };
#define RING_BREIT  51       /* leftmost to rightmost place                */

static unsigned char v_zustand[VOEGEL];
static unsigned char v_x[VOEGEL];
static unsigned char v_y[VOEGEL];
static unsigned char v_platz[VOEGEL];     /* place in the formation        */
static unsigned char v_flug[VOEGEL];      /* wing beat                     */
static unsigned char v_zeit[VOEGEL];
static unsigned char v_hx[VOEGEL];        /* place in the formation, from    */
static unsigned char v_hy[VOEGEL];        /* form_x and absolute             */
static unsigned char v_fluegel[VOEGEL];   /* bit 0 left, bit 1 right        */
static unsigned char v_regen[VOEGEL];     /* until the wings grow back      */
static unsigned char v_boden[VOEGEL];     /* ticks left along the bottom    */
static unsigned char voegel_uebrig;
static unsigned char voegel_zahl;         /* how many this wave has         */
static unsigned char v_gross;             /* large birds instead of small   */
static unsigned char mutterwelle;         /* the saucer instead of a flock  */
static unsigned char v_breit;             /* width in 2600 pixels           */
static unsigned char v_hoch;              /* height in pixels               */
static unsigned char v_tempo;             /* how fast a dive gets, per round */

static unsigned char form_x;              /* left edge of the formation    */
static unsigned char form_max;            /* how far right it may drift     */
static signed char form_dx;
static unsigned char sturz_zeit;          /* ticks until the next pair goes */
static unsigned char ei_zeit;             /* ticks until the flock shoots   */
static unsigned char sturz_max;           /* how many may be out at once    */

/* the remainders of the three speeds, so the averages come out right */
static unsigned char rest_sturz, rest_seit, rest_form, rest_ei;
static signed char schwung_dx;            /* which way a swoop is swinging  */
static unsigned char schwung_zeit;        /* until the swing turns round    */
static unsigned char welle;               /* 1..5, then round by round     */
static unsigned char runde;
static unsigned char vogelfarbe;

/* eggs the birds drop */
static unsigned char ei_aktiv[EIER];
static unsigned char ei_x[EIER];
static unsigned char ei_y[EIER];

/*
 * Where a bird belongs while it sits in the formation. The small birds of
 * the first two waves stand in the ring the original draws them in; the
 * large ones of waves three and four stand in two rows of three, which is
 * what there is room for once a bird is sixteen pixels wide.
 */
static unsigned char platz_x(unsigned char p)
{
    unsigned char reihe;
    if (!v_gross) return (unsigned char)(form_x + RING_X[p]);
    reihe = 3;
    return (unsigned char)(form_x +
        (unsigned char)(p >= reihe ? p - reihe : p) * 44);
}

static unsigned char platz_y(unsigned char p)
{
    /* The large birds hatch out of eggs that float down from the top edge,
       so their flock sits a little lower - it gives the eggs a way to fall. */
    if (v_gross) return (unsigned char)(V_OBEN + (p >= 3 ? 34 : 8));
    return (unsigned char)(V_OBEN + RING_Y[p]);
}

/*
 * Where the bird's place is right now. The original's flock keeps its
 * height for the whole wave - it never creeps down on you - so this is
 * simply where the place was put.
 */
static unsigned char platz_jetzt_y(unsigned char p)
{
    return v_hy[p];
}

static void mutter_aufbauen(void);
/*
 * Two birds in one character cell blink at each other: whoever draws second
 * puts its pixels into the first one's character, and when the first one
 * then moves off that cell it hands the cell back to the background with
 * both of them in it. The original never lets its pair cross - the two that
 * swoop leave side by side and stay that way - so the faithful cure is also
 * the simple one: a bird does not take a step that would put it on top of
 * another. Only the sideways step is ever cancelled, so a swoop can always
 * carry on downwards and nothing can wedge itself.
 */
static unsigned char frei_von_voegeln(unsigned char nr, int x, int y)
{
    unsigned char k;
    for (k = 0; k < voegel_zahl; ++k) {
        if (k == nr) continue;
        if (v_zustand[k] == V_LEER || v_zustand[k] == V_TOT) continue;
        if (x + v_breit <= (int)v_x[k] || (int)v_x[k] + v_breit <= x) continue;
        if (y + v_hoch <= (int)v_y[k] || (int)v_y[k] + v_hoch <= y) continue;
        return 0;
    }
    return 1;
}

static void pause_laden(void);

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
        v_hoch = 10;
        form_x = 12;
        form_max = 48;
        vogelfarbe = (unsigned char)(welle == 4 ? C_V_ROT : C_V_BLAU);
    } else {
        if (satz != satz_geladen) { formen_klein(); satz_geladen = satz; }
        vorrat_verteilen(8, VOEGEL);
        voegel_zahl = VOEGEL;
        v_breit = 8;
        v_hoch = 8;
        /* the ring starts where the original's does, and may drift until
           its outer birds touch either edge of the screen */
        form_x = 53;
        form_max = (unsigned char)(152 - RING_BREIT);
        vogelfarbe = (unsigned char)(welle == 2 ? C_V_GRUEN : C_V_VIOLETT);
    }

    balkenfarbe = (unsigned char)((welle & 1) ? C_BALKEN1 : C_BALKEN2);
    for (i = 0; i < FIG_N + SCH_N; ++i) bel_nsp[i] = 0;
    sternenhimmel_aufbauen();
    if (mutterwelle) mutter_aufbauen();

    form_dx = -1;
    pause_laden();
    ei_zeit = EI_TAKT;
    rest_sturz = rest_seit = rest_form = rest_ei = 0;
    schwung_dx = -1;
    schwung_zeit = SCHWUNG_DAUER;

    /* The original sends exactly two down at a time in the first round, and
       waits until they are home before it sends the next two. Later rounds
       get one more, which is as far as the console ever turns the screw. */
    sturz_max = (unsigned char)(1 + runde);
    if (sturz_max > 3) sturz_max = 3;

    /* The swoop itself is the same speed in every round - measured off the
       original at four pixels every three frames. What gets harder is how
       soon the next pair leaves and how much the flock shoots. */
    v_tempo = TEMPO_STURZ;
    voegel_uebrig = voegel_zahl;

    for (i = 0; i < voegel_zahl; ++i) {
        v_platz[i] = i;
        v_flug[i] = (unsigned char)(i & 3);
        v_zeit[i] = 0;
        v_fluegel[i] = 3;
        v_regen[i] = 0;
        v_boden[i] = 0;
        v_hx[i] = (unsigned char)(platz_x(i) - form_x);
        v_hy[i] = platz_y(i);
        v_x[i] = (unsigned char)(form_x + v_hx[i]);

        if (v_gross) {
            /* They arrive as eggs, drifting down from above in a zigzag.
               The second row follows the first, which is the "two banks of
               eggs" the fourth wave is known for - and it waits half a place
               to the side, so the two banks never sit on top of each other
               while the second one is still waiting its turn. */
            v_zustand[i] = V_EI;
            v_y[i] = SPIEL_OBEN;
            /* a bank falls together and the second one follows a second
               and a half later, half a place to the side */
            v_zeit[i] = (unsigned char)(i >= 3 ? 30 : 0);
            if (i >= 3) v_x[i] = (unsigned char)(v_x[i] + 22);
        } else {
            v_zustand[i] = V_FORM;
            v_y[i] = v_hy[i];
        }
    }
    for (i = voegel_zahl; i < VOEGEL; ++i) v_zustand[i] = V_LEER;
    for (i = 0; i < EIER; ++i) ei_aktiv[i] = 0;

    dauerfeuer = (unsigned char)(welle == 2);

    if (mutterwelle) musik_starten(MUS_MUTTER, 1);
    else if (v_gross) musik_starten(MUS_GROSS, 1);
    else musik_starten(MUS_FLUG, 1);
}

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

/*
 * How the flock moves - taken off the original frame by frame in Stella.
 *
 * The flock sits in a ring at four fixed heights and drifts sideways a pixel
 * every three frames, turning round when its outer birds reach the edge. It
 * does not descend: sitting still is safe from the ring itself.
 *
 * Two birds leave the bottom of the ring together and swoop. The swoop is
 * dead steady - four pixels down every three frames, no gathering speed -
 * and it does not aim: the pair swings sideways on a slow rhythm of its own
 * whatever the ship does. Thirteen pixels above the ship they level out, run
 * along the bottom for about a second, then climb back at the same rate and
 * take their places again. Only a second after that do the next two leave.
 *
 * What it is not: several birds at once on zig-zag lines that drift towards
 * the ship, over a flock that creeps down as it is thinned out. That was the
 * earlier guess, and next to the console it is relentless - in the real
 * first wave the birds never come near the ship, and what kills you is what
 * they drop.
 */
/*
 * How long the flock waits before it sends the next pair. The original
 * leaves a good second; later rounds shorten it, which is the only screw
 * the console ever turns on the birds themselves.
 */
static void pause_laden(void)
{
    unsigned char weg;
    sturz_zeit = PAUSE_DAUER;
    if (runde < 2) return;
    weg = (unsigned char)((runde - 1) * 8);
    if (weg > 40) weg = 40;
    sturz_zeit = (unsigned char)(sturz_zeit - weg);
}

static void voegel_bewegen(void)
{
    unsigned char i, z, offen, geschickt;
    unsigned char ab, seit, quer;
    int x, y, zx, zy;

    /* The mothership wave flies without a flock, and none of what follows
       means anything then. */
    if (voegel_zahl == 0) return;

    /* how far everything has come since the pass before */
    ab = schritt(TEMPO_STURZ, &rest_sturz);
    seit = schritt(TEMPO_SEIT, &rest_seit);
    quer = schritt(TEMPO_FORM, &rest_form);

    /* the whole ring drifts, and turns round at the edge of the screen */
    if (form_dx < 0) {
        form_x = (unsigned char)(form_x > quer ? form_x - quer : 0);
        if (form_x == 0) form_dx = 1;
    } else {
        form_x = (unsigned char)(form_x + quer);
        if (form_x >= form_max) { form_x = form_max; form_dx = -1; }
    }

    /* the sideways swing a swoop rides on, shared by both birds in it */
    if (schwung_zeit > takte) {
        schwung_zeit = (unsigned char)(schwung_zeit - takte);
    } else {
        schwung_zeit = SCHWUNG_DAUER;
        schwung_dx = (signed char)-schwung_dx;
    }

    /*
     * The flock shoots, and in the first waves that - not the swoop - is
     * what kills you: the original drops something about every quarter of a
     * second, from wherever a bird happens to be, and it falls twice as fast
     * as a bird flies. Later rounds drop them a little closer together.
     */
    if (ei_zeit > takte) {
        ei_zeit = (unsigned char)(ei_zeit - takte);
    } else {
        unsigned char k = zufall();
        while (k >= voegel_zahl) k = (unsigned char)(k - voegel_zahl);
        for (i = 0; i < voegel_zahl; ++i) {
            unsigned char j = (unsigned char)(k + i);
            if (j >= voegel_zahl) j = (unsigned char)(j - voegel_zahl);
            if (v_zustand[j] == V_FORM || IM_FLUG(v_zustand[j])) {
                ei_legen(v_x[j], (unsigned char)(v_y[j] + v_hoch));
                break;
            }
        }
        ei_zeit = EI_TAKT;
        if (runde > 1) {
            unsigned char weg = (unsigned char)(runde - 1);
            if (weg > 6) weg = 6;
            ei_zeit = (unsigned char)(ei_zeit - weg);
        }
    }

    /* how many are away from the ring already? */
    offen = 0;
    for (i = 0; i < voegel_zahl; ++i)
        if (IM_FLUG(v_zustand[i])) ++offen;

    /* Nothing leaves while a pair is still out, and once they are home the
       clock starts again - the original waits a good second before it sends
       the next two. It always takes them off the bottom of the ring. */
    if (offen != 0) {
        pause_laden();
    } else if (sturz_zeit > takte) {
        sturz_zeit = (unsigned char)(sturz_zeit - takte);
    } else {
        geschickt = 0;
        while (geschickt < sturz_max) {
            unsigned char best = VOEGEL;
            for (i = 0; i < voegel_zahl; ++i) {
                if (v_zustand[i] != V_FORM) continue;
                if (best == VOEGEL || v_hy[v_platz[i]] > v_hy[v_platz[best]])
                    best = i;
            }
            if (best == VOEGEL) break;
            v_zustand[best] = V_STURZ;
            v_boden[best] = BODEN_DAUER;
            v_zeit[best] = 0;
            ++geschickt;
        }
        pause_laden();
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

        zx = (int)(unsigned char)(form_x + v_hx[v_platz[i]]);
        zy = (int)platz_jetzt_y(v_platz[i]);

        if (z == V_EI) {
            /* the second bank waits its turn before it sets off */
            if (v_zeit[i]) { --v_zeit[i]; continue; }

            x = (int)v_x[i] + (schwung_dx > 0 ? (int)seit : -(int)seit);
            if (x < 0) x = 0;
            if (x > 152) x = 152;
            y = (int)v_y[i] + ab;

            if (y >= zy) {          /* it has arrived, and hatches */
                v_zustand[i] = V_FORM;
                x = zx;
                y = zy;
            }
            v_x[i] = (unsigned char)x;
            v_y[i] = (unsigned char)y;
            continue;
        }

        if (z == V_FORM) {
            v_x[i] = (unsigned char)zx;
            v_y[i] = (unsigned char)zy;
            continue;
        }

        x = (int)v_x[i];
        y = (int)v_y[i];

        if (z == V_STURZ) {
            x += (schwung_dx > 0 ? (int)seit : -(int)seit);
            y += ab;
            if (y >= STURZ_ENDE) {      /* it levels out well above the ship */
                y = STURZ_ENDE;
                v_zustand[i] = V_BODEN;
            }
        } else if (z == V_BODEN) {
            /* along the bottom it drifts at the same pace as the ring */
            x += (form_dx > 0 ? (int)quer : -(int)quer);
            if (v_boden[i] > takte) {
                v_boden[i] = (unsigned char)(v_boden[i] - takte);
            } else {
                v_boden[i] = 0;
                v_zustand[i] = V_RUECK;
                v_zeit[i] = 0;
            }
        } else {
            /*
             * Coming home it works the sideways distance off while it is
             * still climbing and takes the last step up only once it stands
             * over its own place - so it never has to slide along the row
             * the others are sitting in.
             */
            ++v_zeit[i];
            if (y > zy + v_hoch) {
                y -= ab;
                if (y < zy + v_hoch) y = zy + v_hoch;
                if (x + (int)seit < zx) x += seit;
                else if (x > zx + (int)seit) x -= seit;
                else x = zx;
            } else if (x != zx) {
                if (x + (int)seit < zx) x += seit;
                else if (x > zx + (int)seit) x -= seit;
                else x = zx;
            } else {
                y -= ab;
                if (y <= zy) { y = zy; v_zustand[i] = V_FORM; }
            }
            /* and if something ever gets in the way for good, it gives up
               and drops into its place */
            if (v_zeit[i] > 120) { x = zx; y = zy; v_zustand[i] = V_FORM; }
        }

        if (x < 0) x = 0;
        if (x > 152) x = 152;
        /* never step onto another bird - the sideways step gives way */
        if (v_zustand[i] != V_FORM && !frei_von_voegeln(i, x, y)) {
            if (frei_von_voegeln(i, (int)v_x[i], y)) x = (int)v_x[i];
            else if (frei_von_voegeln(i, x, (int)v_y[i])) y = (int)v_y[i];
            else { x = (int)v_x[i]; y = (int)v_y[i]; }
        }
        v_x[i] = (unsigned char)x;
        v_y[i] = (unsigned char)y;
    }
}

/*
 * What the birds drop falls at eight pixels every three frames - twice the
 * speed of the swoop itself, which is what makes it, and not the birds, the
 * thing that kills you in the early waves.
 */
static void eier_bewegen(void)
{
    unsigned char i, ab;

    ab = schritt(TEMPO_EI, &rest_ei);
    if (ab == 0) return;
    for (i = 0; i < EIER; ++i) {
        if (!ei_aktiv[i]) continue;
        ei_y[i] = (unsigned char)(ei_y[i] + ab);
        if (ei_y[i] > EI_UNTEN) {
            ei_aktiv[i] = 0;
            figur_loeschen((unsigned char)(SLOT_EI + i));
        }
    }
}

static void voegel_malen(void)
{
    static const unsigned char SCHLAG[4] = { 0, 1, 1, 0 };
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
        case V_EI:
            if (v_zeit[i]) break;        /* still waiting its turn */
            figur_malen((unsigned char)(i + 1), FORM_GROSSEI,
                        v_x[i], v_y[i], C_GELB);
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

/*
 * The saucer, traced off a screenshot of the original like everything else.
 * It is eighty 2600 pixels across and forty-one tall - twenty character cells
 * by five and a bit - and its shape is a stepped one: two banks of blocks
 * climbing outwards from a notch at the top, a band across the full width,
 * and a hull below that tapers away to nothing.
 *
 * The alien sits in the notch, above the band. That is why the way in is from
 * below: chew a column out of the hull, wait for the turning band to open at
 * that spot, and only then is there a line to the middle.
 */
#define MS_BREIT 20
#define MS_HOCH   6
#define MS_LINKS 10          /* left cell column, centred on the screen */

#define MZ_LEER    0
#define MZ_SPERRE  5         /* a piece of the turning band */
#define MZ_CHEF    6         /* the alien in the middle     */

#define Z_MUTTER 240         /* 240..248 belong to the saucer */

/* Per row the first and last cell the saucer reaches into. */
static const unsigned char MS_VON[MS_HOCH] = {  7,  4,  0,  0,  2,  6 };
static const unsigned char MS_BIS[MS_HOCH] = { 12, 15, 19, 19, 17, 13 };

/* and its colour: the upper banks are yellow-green in the original, the band
   blue and the hull a dark magenta */
static const unsigned char MS_FARBE[MS_HOCH] = {
    0x6A, 0x6A, 0x56, 0x44, 0x44, 0x44
};

#define MS_SPERRZEILE 2      /* the row that turns   */
#define MS_CHEFZEILE  0      /* the alien, two cells */
#define MS_CHEFSP     9

static unsigned char ms_feld[MS_HOCH][MS_BREIT];
static unsigned char ms_zeile;       /* topmost cell row on screen */
static unsigned char ms_dreh;        /* how far the band has turned */
static unsigned char ms_lebt;
static unsigned char ms_bombe_zeit;
static unsigned char ms_takt;       /* until it comes down one row */

/*
 * The alien: eight 2600 pixels across and eleven tall, so two characters by
 * two once it is doubled in width.
 */
static const unsigned char CHEF[11] = {
    0x24,   /*   #  #   */
    0x18,   /*    ##    */
    0x7E,   /*  ######  */
    0xE7,   /* ###  ### */
    0x7E,   /*  ######  */
    0x18,   /*    ##    */
    0x18,   /*    ##    */
    0x18,   /*    ##    */
    0x18,   /*    ##    */
    0x24,   /*   #  #   */
    0x42    /*  #    #  */
};

static void mutterzeichen_bauen(void)
{
    unsigned char s, i, b;
    unsigned char *z;

    /* four states of hull, each bite two pixel rows deep */
    for (s = 0; s < 4; ++s) {
        z = zeichensatz + (Z_MUTTER + s) * 8;
        for (i = 0; i < 8; ++i)
            z[i] = (unsigned char)(i < (unsigned char)(8 - s - s) ? 0xFF : 0x00);
    }
    /* the turning band */
    z = zeichensatz + (Z_MUTTER + 4) * 8;
    for (i = 0; i < 8; ++i) z[i] = (unsigned char)((i & 1) ? 0x66 : 0x99);

    /* the alien, doubled in width into two characters by two */
    for (i = 0; i < 16; ++i) {
        b = (unsigned char)(i < 11 ? CHEF[i] : 0);
        if (i < 8) {
            zeichensatz[(Z_MUTTER + 5) * 8 + i] = VERDOPPELT[b >> 4];
            zeichensatz[(Z_MUTTER + 6) * 8 + i] = VERDOPPELT[b & 15];
        } else {
            zeichensatz[(Z_MUTTER + 7) * 8 + i - 8] = VERDOPPELT[b >> 4];
            zeichensatz[(Z_MUTTER + 8) * 8 + i - 8] = VERDOPPELT[b & 15];
        }
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
        farbe = C_V_VIOLETT;
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
    ms_zeile = 3;              /* it comes in below the score */
    ms_dreh = 0;
    ms_lebt = 1;
    ms_bombe_zeit = 8;
    ms_takt = 16;

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
    unsigned char br = (unsigned char)(v_zustand[i] == V_EI ? 8 : v_breit);
    unsigned char ab;

    if (sx < v_x[i] || sx > (unsigned char)(v_x[i] + br - 1)) return T_DANEBEN;
    if (schuss_y > (unsigned char)(v_y[i] + v_hoch - 1)) return T_DANEBEN;
    if ((unsigned char)(schuss_y + 4) < v_y[i]) return T_DANEBEN;
    if (!v_gross || v_zustand[i] == V_EI) return T_KOERPER;

    ab = (unsigned char)(sx - v_x[i]);
    if (ab < 6)   return (unsigned char)((v_fluegel[i] & 1) ? T_LINKS : T_DANEBEN);
    if (ab >= 10) return (unsigned char)((v_fluegel[i] & 2) ? T_RECHTS : T_DANEBEN);
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
                if (v_zustand[i] == V_EI) punkte_dazu(50);
                else if (v_gross) punkte_dazu(grosswert(v_y[i]));
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
            if (!IM_FLUG(v_zustand[i])) continue;
            if (v_y[i] + 7 < SCHILD_Y || v_y[i] > SCHILD_Y + SCHILD_HOCH - 1)
                continue;
            if (v_x[i] + 7 < (int)spieler_x - SCHILD_LINKS ||
                v_x[i] > (int)spieler_x - SCHILD_LINKS + SCHILD_BREIT - 1)
                continue;
            punkte_dazu(80);
            vogel_toeten(i);
        }
        for (i = 0; i < EIER; ++i) {
            if (!ei_aktiv[i]) continue;
            if (ei_y[i] + 4 < SCHILD_Y || ei_y[i] > SCHILD_Y + SCHILD_HOCH - 1)
                continue;
            ei_aktiv[i] = 0;
            figur_loeschen((unsigned char)(SLOT_EI + i));
        }
        return 0;                 /* nothing can hurt us while it burns */
    }

    /* a bird flying into the ship */
    for (i = 0; i < voegel_zahl; ++i) {
        if (!IM_FLUG(v_zustand[i])) continue;
        if (v_y[i] + 7 < SCHIFF_Y || v_y[i] > SCHIFF_Y + SCHIFF_HOCH - 1)
            continue;
        if (v_x[i] + 7 < (int)spieler_x ||
            v_x[i] > (int)spieler_x + SCHIFF_BREIT - 1) continue;
        return 1;
    }

    /* an egg landing on it */
    for (i = 0; i < EIER; ++i) {
        if (!ei_aktiv[i]) continue;
        if (ei_y[i] + 4 < SCHIFF_Y || ei_y[i] > SCHIFF_Y + SCHIFF_HOCH - 1)
            continue;
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
static void alles_loeschen(void);
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

/*
 * Waits without drawing anything. warten() further down redraws the figures
 * on every pass, which on a text screen means they eat the letters: the ROM
 * font is loaded into the same pool of characters the figures write
 * themselves into.
 */
static void warten_still(unsigned char schritte)
{
    while (schritte--) {
        klang_weiter();
        bild_warten();
    }
}

static void abspann(void)
{
    char zeile[8];
    unsigned char i;

    musik_aus();
    mutterwelle = 0;
    alles_loeschen();          /* figures off the screen before the font  */
    bildschirm_leeren();       /* goes into the characters they were using */
    textfont_laden();

    text_breit(11, 10, "GAME OVER", C_ROT);

    for (i = 0; i < 6; ++i) zeile[i] = (char)('0' + punkte_z[i]);
    zeile[6] = 0;
    text_zeigen(14, 14, "SCORE", C_GRAU);
    text_zeigen(20, 14, zeile, C_WEISS);

    warten_still(3 * TAKT);
    auf_feuer_warten();
}

/* ======================================================================
 * 13. Game flow
 * ==================================================================== */

/*
 * Waits for the beam to leave the playfield, so drawing starts in the gap
 * between two frames and runs down the screen roughly with it.
 */
static void bild_warten(void)
{
    ++durchlaeufe;
    while (TED_RASTER >= 210) { eingang_abtasten(); }
    while (TED_RASTER <  210) { eingang_abtasten(); }

    /* The scroll register is not touched here any more - see scrollen(). */
    if (mutterwelle && ms_lebt && ms_takt && --ms_takt == 0) {
        ms_takt = 16;
        if ((unsigned char)(ms_zeile + MS_HOCH) < 22) mutter_sinken();
    }
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

    uhr_alt = UHR;

    for (;;) {
        takt_messen();
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
                leben_bauen();
                spieler_setzen();
                welle_aufbauen();
                continue;
            }
        }

        if (treffer_pruefen() && !unsterblich) {
            sterben();
            if (--leben == 0) return 1;
            leben_bauen();
            spieler_setzen();
            warten(TAKT);
            continue;
        }

        if (!mutterwelle && voegel_uebrig == 0) {
            warten(TAKT);
            return 0;
        }

        scrollen();
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
    for (i = 0; i < ZEILEN; ++i) {
        zeile_bild[i]  = BILD + zeilenanfang[i];
        zeile_farbe[i] = FARBE + zeilenanfang[i];
        zeile_hg[i]    = hg_zeichen + zeilenanfang[i];
        zeile_hgf[i]   = hg_farbe + zeilenanfang[i];
    }

    TED_HGRUND = C_SCHWARZ;
    TED_RAHMEN = C_SCHWARZ;
    TED_SENKR = 0x10;              /* 24 rows, fine scroll at rest */

    for (;;) {
        if (titelbild()) break;

        for (i = 0; i < 6; ++i) punkte_z[i] = 0;
        bonus_gegeben = 0;
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
