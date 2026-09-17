/*
 * Pac-Man fuer den Commodore Plus/4
 * =================================
 *
 * Der Plus/4 hat keine Sprites. Die Figuren sind deshalb aus Zeichen gebaut,
 * die in jedem Bild neu berechnet werden - dadurch bewegen sie sich pixelweise
 * statt kachelweise und sind mit 12x12 Punkten deutlich groesser als eine
 * Kachel. Das Labyrinth fuellt den Bildschirm randlos aus.
 *
 * Wie das funktioniert:
 *
 *   Der TED stellt normalerweise die Zeichencodes ab 128 als invertierte
 *   Kopien von 0..127 dar. Mit Bit 7 in $FF07 laesst sich das abschalten;
 *   dann stehen alle 256 Zeichen frei zur Verfuegung. Die oberen 128 dienen
 *   als Vorrat: jede Figur belegt 3x3 davon. In jedem Bild werden diese
 *   Zeichen mit der pixelgenau verschobenen Figur gefuellt und an der
 *   passenden Stelle auf den Bildschirm gesetzt.
 *
 *   Damit das schnell genug ist, liegen die waagerecht vorgeschobenen
 *   Figurdaten fertig im Speicher (8 Stellungen je Form) und das Mischen
 *   mit dem Labyrinth-Hintergrund erledigt eine kurze Assemblerschleife.
 *
 *   Die Mauerlinien sind 2 Pixel vom Kachelrand nach innen gerueckt. Dadurch
 *   ist ein Korridor effektiv 12 statt 8 Pixel breit und die Figur passt
 *   hindurch, ohne die Waende zu ueberdecken.
 *
 * Aufbau der Datei:
 *   1. Hardware          5. Figuren und ihre Daten
 *   2. Zeichensatz       6. Zeichnen (mit dem Blitter)
 *   3. Labyrinth         7. Bewegung, Geister-KI
 *   4. Ton und Eingabe   8. Spielablauf
 *
 * Steuerung: W A S D oder die Cursortasten, Q beendet das Spiel.
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
#define TED_ZSATZ_M  (*(volatile unsigned char *)0xFF12)  /* Bit 2: Font aus RAM */
#define TED_ZSATZ_A  (*(volatile unsigned char *)0xFF13)  /* Bit 2-7: Fontadresse */
#define TED_HGRUND   (*(volatile unsigned char *)0xFF15)
#define TED_RAHMEN   (*(volatile unsigned char *)0xFF19)
#define TED_RASTER   (*(volatile unsigned char *)0xFF1D)
#define TED_WAAGR    (*(volatile unsigned char *)0xFF07)  /* Bit 7: Invers abschalten */
#define ROM_EIN      (*(volatile unsigned char *)0xFF3E)
#define RAM_EIN      (*(volatile unsigned char *)0xFF3F)

/* Farben: Helligkeit * 16 + Farbnummer. Hohe Helligkeiten waschen auf dem
   Plus/4 zu Weiss aus, kraeftige Farben gibt es bei Helligkeit 3 bis 6. */
#define C_SCHWARZ  0x00
#define C_WEISS    0x71
#define C_GELB     0x77   /* Pac-Man          */
#define C_ROT      0x42   /* Blinky           */
#define C_ROSA     0x6B   /* Pinky            */
#define C_CYAN     0x63   /* Inky             */
#define C_ORANGE   0x58   /* Clyde            */
#define C_BLAU     0x36   /* Mauern           */
#define C_ANGST    0x4E   /* fressbarer Geist */
#define C_HELLBLAU 0x5D
#define C_TUER     0x5B
#define C_PUNKT    0x62   /* Kruemel          */

/* ======================================================================
 * 2. Zeichensatz
 * ==================================================================== */

#define Z_MAUER    64    /* 64..79: 16 Mauerformen         */
#define Z_KRUEMEL  80
#define Z_PILLE    81
#define Z_TUER     82
#define Z_VORRAT  128    /* ab hier die Figurzeichen       */
#define EINZUG      3    /* Einrueckung der Mauerlinie     */

/* 2 KB Zeichensatz, ausgerichtet auf eine durch 2048 teilbare Adresse. */
static unsigned char zeichenspeicher[2048 + 2047];
static unsigned char *zeichensatz;
static unsigned rom_index;

/*
 * Holt den ROM-Zeichensatz. cc65 blendet auf dem Plus/4 das ROM aus, um den
 * vollen Speicher nutzen zu koennen; fuer den Zeichengenerator bei $D000 muss
 * es kurz zurueck. In diesem Fenster darf kein C-Stack benutzt werden (der
 * liegt bei $F500-$FCFF und waere verdeckt), darum nur globale Variablen und
 * kein Funktionsaufruf.
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
 * Baut die 16 Mauerzeichen. Gezeichnet wird der Umriss der Mauerflaeche:
 * eine Linie kommt nur an die Kante, hinter der ein begehbares Feld liegt,
 * und zwar um EINZUG Pixel nach innen versetzt. Aus zwei Kacheln dicken
 * Bloecken werden so die doppelten Konturlinien des Originals.
 *
 * Die Nummer ist eine Bitmaske:
 *   Bit 0 = oben offen, 1 = unten, 2 = links, 3 = rechts.
 */
static void mauerzeichen_bauen(void)
{
    unsigned char m, y, x, b, x0, x1, y0, y1;

    for (m = 0; m < 16; ++m) {
        x0 = (unsigned char)((m & 4) ? EINZUG : 0);
        x1 = (unsigned char)((m & 8) ? 7 - EINZUG : 7);
        y0 = (unsigned char)((m & 1) ? EINZUG : 0);
        y1 = (unsigned char)((m & 2) ? 7 - EINZUG : 7);

        for (y = 0; y < 8; ++y) {
            b = 0;
            if (((m & 1) && y == EINZUG) || ((m & 2) && y == 7 - EINZUG))
                for (x = x0; x <= x1; ++x) b |= (unsigned char)(0x80 >> x);
            if (y >= y0 && y <= y1) {
                if (m & 4) b |= (unsigned char)(0x80 >> EINZUG);
                if (m & 8) b |= (unsigned char)(0x80 >> (7 - EINZUG));
            }
            zeichensatz[(Z_MAUER + m) * 8 + y] = b;
        }
    }
}

static const unsigned char KLEINZEUG[] = {
    0x00, 0x00, 0x00, 0x18, 0x18, 0x00, 0x00, 0x00,   /* Kruemel     */
    0x00, 0x3C, 0x7E, 0x7E, 0x7E, 0x7E, 0x3C, 0x00,   /* Kraftpille  */
    0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00,   /* Haustuer    */
};

/* ======================================================================
 * 3. Labyrinth
 * ==================================================================== */

#define KB 40          /* Kacheln waagerecht - der ganze Bildschirm */
#define KH 24          /* Kacheln senkrecht                         */
#define OFFY 1         /* Zeile 0 bleibt fuer die Anzeige frei      */

#define F_LEER   0
#define F_PUNKT  1
#define F_PILLE  2
#define F_MAUER  3
#define F_TUER   4

/* '#' Mauer, '.' Kruemel, 'o' Kraftpille, '-' Geisterhaustuer, ' ' leer. */
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

static unsigned char feld[KH][KB];       /* was liegt auf der Kachel   */
static unsigned char feldzeichen[KH][KB];/* welches Zeichen gehoert hin*/
static unsigned int  restpunkte;
static unsigned char pillenx[4], pilleny[4];
static unsigned char mauerfarbe = C_BLAU;

/* Startplaetze und Geisterhaus */
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

static unsigned char feldfarbe(unsigned char mx, unsigned char my)
{
    switch (feld[my][mx]) {
    case F_MAUER: return mauerfarbe;
    case F_TUER:  return C_TUER;
    case F_PUNKT:
    case F_PILLE: return C_PUNKT;
    default:      return C_SCHWARZ;
    }
}

/* Setzt das Zeichen einer Kachel neu - loescht damit auch eine Figur. */
static void kachel_zeichnen(unsigned char mx, unsigned char my)
{
    unsigned pos = (unsigned)(OFFY + my) * 40 + mx;
    BILD[pos] = feldzeichen[my][mx];
    FARBE[pos] = feldfarbe(mx, my);
}

static void labyrinth_aufbauen(void)
{
    unsigned char mx, my, m, n = 0;

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

    /* Zeichen je Kachel einmal bestimmen - die Mauerform haengt von den
       Nachbarn ab und aendert sich waehrend des Spiels nicht mehr. */
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
 * 4. Ton und Eingabe
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
 * Wartet auf den Strahlruecklauf. Gewartet wird auf Rasterzeile 210, also
 * knapp unterhalb des Spielfelds: danach bleibt der ganze untere Rand und
 * die Austastluecke Zeit, die Figuren neu zu setzen, bevor der Strahl sie
 * wieder erreicht.
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
 * 5. Figuren
 * ==================================================================== */

#define R_OBEN   0
#define R_LINKS  1
#define R_UNTEN  2
#define R_RECHTS 3

/* Formen: 0 = Mund zu, 1..4 = Mund offen in Richtung 0..3 */
#define FORM_ZU     0
#define FORM_GEIST  5
#define FORM_ANGST  6
#define FORM_AUGEN  7

/* Je Form 16 Zeilen zu 16 Punkten, als zwei Bytes. */
static const unsigned char FORMEN[8 * 32] = {
    /* Pac Mund zu */
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x80,
    0x07, 0xE0, 0x0F, 0xF0, 0x0F, 0xF0, 0x1F, 0xF8,
    0x1F, 0xF8, 0x0F, 0xF0, 0x0F, 0xF0, 0x07, 0xE0,
    0x01, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    /* Pac oben */
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x0C, 0x30, 0x0E, 0x70, 0x1F, 0xF8,
    0x1F, 0xF8, 0x0F, 0xF0, 0x0F, 0xF0, 0x07, 0xE0,
    0x01, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    /* Pac links */
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x80,
    0x07, 0xE0, 0x07, 0xF0, 0x03, 0xF0, 0x01, 0xF8,
    0x01, 0xF8, 0x03, 0xF0, 0x07, 0xF0, 0x07, 0xE0,
    0x01, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    /* Pac unten */
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x80,
    0x07, 0xE0, 0x0F, 0xF0, 0x0F, 0xF0, 0x1F, 0xF8,
    0x1F, 0xF8, 0x0E, 0x70, 0x0C, 0x30, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    /* Pac rechts */
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x80,
    0x07, 0xE0, 0x0F, 0xE0, 0x0F, 0xC0, 0x1F, 0x80,
    0x1F, 0x80, 0x0F, 0xC0, 0x0F, 0xE0, 0x07, 0xE0,
    0x01, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    /* Geist */
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x80,
    0x07, 0xE0, 0x0F, 0xF0, 0x09, 0x90, 0x1B, 0xD8,
    0x1F, 0xF8, 0x1F, 0xF8, 0x1F, 0xF8, 0x1F, 0xF8,
    0x1B, 0xD8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    /* Geist in Angst */
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x80,
    0x07, 0xE0, 0x0F, 0xF0, 0x09, 0x90, 0x1F, 0xF8,
    0x1F, 0xF8, 0x15, 0x58, 0x1F, 0xF8, 0x1F, 0xF8,
    0x1B, 0xD8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    /* nur Augen */
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x06, 0x60, 0x04, 0x20,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};

/* Waagerecht vorgeschobene Fassungen: je Form und Versatz drei Spalten
   zu 16 Zeilen. Wird beim Start einmal ausgerechnet. */
static unsigned char vorgeschoben[8 * 8 * 48];
static unsigned char spalte[3][24];      /* senkrecht eingepasste Figur */

static void formen_vorschieben(void)
{
    unsigned char f, d, y, hi, lo;
    unsigned char *z;

    for (f = 0; f < 8; ++f) {
        for (d = 0; d < 8; ++d) {
            z = vorgeschoben + ((unsigned)f * 8 + d) * 48;
            for (y = 0; y < 16; ++y) {
                hi = FORMEN[(unsigned)f * 32 + y * 2];
                lo = FORMEN[(unsigned)f * 32 + y * 2 + 1];
                z[y]      = (unsigned char)(hi >> d);
                z[16 + y] = (unsigned char)((hi << (8 - d)) | (lo >> d));
                z[32 + y] = (unsigned char)(lo << (8 - d));
            }
        }
    }
}

/* Zustaende eines Geistes */
#define G_HAUS   0
#define G_RAUS   1
#define G_JAGD   2
#define G_ANGST  3
#define G_AUGEN  4
#define G_REIN   5

typedef struct {
    unsigned int  cx;        /* Mittelpunkt in Spielfeldpixeln, 0..319 */
    unsigned char cy;        /* 0..191                                 */
    unsigned char r, wunsch;
    unsigned char form, farbe;
    unsigned char tempo, acc;/* 16 im acc = ein Pixel                  */
    unsigned char zustand, wartet;
    unsigned char startkx, startky;
    unsigned char zielx, ziely;
    unsigned char alt_sp, alt_ze, sichtbar;
    unsigned char neu_sp, neu_ze, vsx, vsy;   /* fuer das Zeichnen */
    unsigned int  alt_cx;                     /* Stand beim letzten Mischen */
    unsigned char alt_cy, alt_form;
} Figur;

static Figur fig[5];         /* 0 = Pac-Man, 1..4 = Geister */

static const unsigned char GEISTFARBE[5] = {
    C_GELB, C_ROT, C_ROSA, C_CYAN, C_ORANGE
};

#define PAC (&fig[0])

static unsigned zufallswert = 0x1234;

static unsigned char zufall(void)
{
    zufallswert = zufallswert * 25173 + 13849;
    return (unsigned char)(zufallswert >> 8);
}

/* ======================================================================
 * 6. Zeichnen
 * ==================================================================== */

static unsigned char *p_quelle, *p_grund, *p_ziel;

/*
 * Mischt acht Bytes: ziel = Figur | Hintergrund.
 *
 * Das ist die einzige Assemblerstelle im Programm und zugleich die
 * meistbenutzte: sie laeuft bis zu 45 mal je Bild. In C waere sie etwa
 * doppelt so langsam und das Spiel liefe nur mit halber Bildrate.
 * ptr1..ptr3 sind Zeigerplaetze, die cc65 auf der Zeropage bereithaelt.
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

/* Gibt die neun Kacheln frei, auf denen die Figur zuletzt stand. */
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
 * Das Zeichnen laeuft in drei Schritten ueber alle Figuren hinweg, nicht
 * Figur fuer Figur. Grund: gaebe eine Figur ihre alten Kacheln erst frei,
 * nachdem eine andere schon gemalt wurde, radierte sie diese wieder weg -
 * ueberlappende Geister verschwaenden dann dauerhaft.
 */

/* Schritt 1: wo steht die Figur jetzt? */
static void figur_position(Figur *f)
{
    unsigned int bx = f->cx + (KB * 8) - 8;   /* +320 haelt alles positiv */
    unsigned char by = (unsigned char)(f->cy - 8);

    f->vsx = (unsigned char)(bx & 7);
    f->vsy = (unsigned char)(by & 7);
    f->neu_sp = (unsigned char)((bx >> 3) % KB);
    f->neu_ze = (unsigned char)(by >> 3);
}

/* Schritt 2: Kacheln freigeben, die die Figur verlassen hat. */
static void figur_freigeben(Figur *f)
{
    unsigned char i, j, mx, my;

    if (!f->sichtbar) return;
    for (j = 0; j < 3; ++j) {
        my = (unsigned char)(f->alt_ze + j);
        if (my >= KH) continue;
        for (i = 0; i < 3; ++i) {
            mx = (unsigned char)(f->alt_sp + i);
            if (mx >= KB) mx = (unsigned char)(mx - KB);
            if ((unsigned char)((mx + KB - f->neu_sp) % KB) < 3
                && (unsigned char)(my - f->neu_ze) < 3) continue;
            kachel_zeichnen(mx, my);
        }
    }
}

/* Schritt 3: die neun Zeichen fuellen und auf den Bildschirm setzen. */
static void figur_malen(Figur *f, unsigned char nr)
{
    unsigned char i, j, mx, my, z, hg, neu;
    unsigned char *tab;
    unsigned pos;

    /*
     * Hat sich weder Position noch Form geaendert, stehen in den neun
     * Zeichen dieser Figur noch die richtigen Punktmuster - dann muessen
     * nur die Zeichencodes wieder auf den Bildschirm. Das Mischen ist der
     * teuerste Teil der Schleife und faellt so bei stehenden Figuren weg.
     */
    neu = (unsigned char)(f->cx != f->alt_cx || f->cy != f->alt_cy
                          || f->form != f->alt_form);
    if (neu) {
        /* Figur senkrecht einpassen: drei Spalten zu 24 Zeilen, die Form
           beginnt in Zeile vsy. Waagerecht ist sie schon vorgeschoben. */
        tab = vorgeschoben + ((unsigned)f->form * 8 + f->vsx) * 48;
        for (i = 0; i < 3; ++i) {
            memset(spalte[i], 0, 24);
            memcpy(spalte[i] + f->vsy, tab + i * 16, 16);
        }
        f->alt_cx = f->cx;
        f->alt_cy = f->cy;
        f->alt_form = f->form;
    }

    for (j = 0; j < 3; ++j) {
        my = (unsigned char)(f->neu_ze + j);
        if (my >= KH) continue;
        for (i = 0; i < 3; ++i) {
            mx = (unsigned char)(f->neu_sp + i);
            if (mx >= KB) mx = (unsigned char)(mx - KB);

            z = (unsigned char)(Z_VORRAT + nr * 9 + j * 3 + i);
            hg = feldzeichen[my][mx];

            if (neu) {
                p_quelle = &spalte[i][j * 8];
                p_grund  = zeichensatz + (unsigned)hg * 8;
                p_ziel   = zeichensatz + (unsigned)z * 8;
                zelle_mischen();
            }

            pos = (unsigned)(OFFY + my) * 40 + mx;
            BILD[pos] = z;
            /*
             * Eine Zeichenzelle kann nur eine Farbe tragen. Wo die Figur in
             * eine Mauerzelle hineinragt, behaelt die Mauer ihre Farbe -
             * sonst faerbten sich ganze Wandabschnitte mit, waehrend die
             * Figur vorbeilaeuft. Die Figuren sind deshalb so geschnitten,
             * dass nur ein bis zwei Randpixel betroffen sind; die wirken
             * dann wie eine dunkle Kontur.
             */
            FARBE[pos] = (unsigned char)(feld[my][mx] == F_MAUER
                                         ? mauerfarbe : f->farbe);
        }
    }

    f->alt_sp = f->neu_sp;
    f->alt_ze = f->neu_ze;
    f->sichtbar = 1;
}

static void alle_zeichnen(void)
{
    unsigned char i;
    for (i = 0; i < 5; ++i) figur_position(&fig[i]);
    for (i = 0; i < 5; ++i) figur_freigeben(&fig[i]);
    for (i = 1; i < 5; ++i) figur_malen(&fig[i], i);
    figur_malen(PAC, 0);
}

/* ======================================================================
 * 7. Bewegung und Geister-KI
 * ==================================================================== */

static unsigned int  angst_rest;
static unsigned char gefressen;
static unsigned int  modus_rest;
static unsigned char streunen;
static unsigned char pac_anim;

#define MITTIG(f) (((f)->cx & 7) == 4 && ((f)->cy & 7) == 4)
#define KX(f) ((unsigned char)((f)->cx >> 3))
#define KY(f) ((unsigned char)((f)->cy >> 3))

/* Ist die Nachbarkachel in Richtung r begehbar? */
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
    case 1:                                  /* Blinky jagt direkt */
        g->zielx = vx; g->ziely = vy;
        break;
    case 2:                                  /* Pinky zielt vier Felder voraus */
        zx = (signed int)vx + 4 * (PAC->r == R_RECHTS) - 4 * (PAC->r == R_LINKS);
        zy = (signed int)vy + 4 * (PAC->r == R_UNTEN)  - 4 * (PAC->r == R_OBEN);
        g->zielx = (unsigned char)(zx < 0 ? 0 : (zx >= KB ? KB - 1 : zx));
        g->ziely = (unsigned char)(zy < 0 ? 0 : (zy >= KH ? KH - 1 : zy));
        break;
    case 3:                                  /* Inky spiegelt Blinky an Pac-Man */
        zx = 2 * (signed int)vx - (signed int)KX(&fig[1]);
        zy = 2 * (signed int)vy - (signed int)KY(&fig[1]);
        g->zielx = (unsigned char)(zx < 0 ? 0 : (zx >= KB ? KB - 1 : zx));
        g->ziely = (unsigned char)(zy < 0 ? 0 : (zy >= KH ? KH - 1 : zy));
        break;
    default:                                 /* Clyde kneift aus der Naehe */
        ax = (unsigned char)(KX(g) > vx ? KX(g) - vx : vx - KX(g));
        ay = (unsigned char)(KY(g) > vy ? KY(g) - vy : vy - KY(g));
        if ((unsigned)ax + ay > 8) { g->zielx = vx; g->ziely = vy; }
        else { g->zielx = 1; g->ziely = KH - 2; }
        break;
    }
}

/* Waehlt die Richtung, die dem Ziel am naechsten kommt. Umkehren ist
   verboten; bei Gleichstand gewinnt oben vor links vor unten vor rechts. */
static unsigned char richtung_waehlen(unsigned char i)
{
    Figur *g = &fig[i];
    unsigned char gegen = (unsigned char)(g->r ^ 2);
    unsigned char tuer = (unsigned char)(g->zustand == G_AUGEN);
    unsigned char r, beste = 255, anzahl = 0, moeglich[4];
    unsigned char kx = KX(g), ky = KY(g), nx, ny;
    unsigned int  abstand, bester = 0xFFFF;
    signed int dx, dy;

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
        dx = (signed int)nx - (signed int)g->zielx;
        dy = (signed int)ny - (signed int)g->ziely;
        abstand = (unsigned int)(dx * dx + dy * dy);
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

    /* Tempo je nach Zustand */
    if (g->zustand == G_ANGST)      g->tempo = 11;
    else if (g->zustand == G_AUGEN) g->tempo = 40;
    else g->tempo = (unsigned char)(level < 6 ? 19 + level : 24);

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
            /* Fester Weg aus dem Haus: erst unter die Tuer, dann hinauf. */
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

    /* Aussehen nach Zustand. Bewusst als Verzweigung und nicht als
       verschachtelter Bedingungsausdruck - cc65 wertet den falsch aus. */
    if (g->zustand == G_ANGST) {
        g->form = FORM_ANGST;
        /* Kurz vor Ablauf der Kraftpille blinkt der Geist weiss. */
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

/* Beruehrung pruefen. Rueckgabe 1 = Pac-Man ist tot. */
static unsigned char beruehrung(void)
{
    unsigned char i, ax, ay;
    unsigned int  d;

    for (i = 1; i < 5; ++i) {
        d = (fig[i].cx > PAC->cx) ? (fig[i].cx - PAC->cx) : (PAC->cx - fig[i].cx);
        if (d > KB * 4) d = KB * 8 - d;            /* ueber den Tunnel */
        ax = (unsigned char)d;
        ay = (unsigned char)(fig[i].cy > PAC->cy ? fig[i].cy - PAC->cy
                                                 : PAC->cy - fig[i].cy);
        if (ax >= 7 || ay >= 7) continue;

        if (fig[i].zustand == G_ANGST) {
            if (gefressen < 4) ++gefressen;
            punkte = (unsigned int)(punkte + (100u << gefressen));
            fig[i].zustand = G_AUGEN;
            fig[i].acc = 0;
            ton(900, 10);
            statuszeile();
        } else if (fig[i].zustand == G_JAGD || fig[i].zustand == G_RAUS) {
            return 1;
        }
    }
    return 0;
}

/* ======================================================================
 * 8. Anzeige und Spielablauf
 * ==================================================================== */

static void zeichen_setzen(unsigned char sx, unsigned char sy,
                           unsigned char z, unsigned char f)
{
    unsigned pos = (unsigned)sy * 40 + sx;
    BILD[pos] = z;
    FARBE[pos] = f;
}

/*
 * cc65 uebersetzt Zeichenliterale fuer CBM-Ziele nach PETSCII: aus 'A' wird
 * 193, nicht 65. Darum wird relativ zu 'a' bzw. 'A' gerechnet - das stimmt in
 * beiden Zeichensaetzen. Mit festen 64 bzw. 96 landet man 128 zu hoch.
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
        fig[i].alt_form = 255;   /* erzwingt das erste Mischen */
        fig[i].wartet = (unsigned char)(i * 25);
        fig[i].zustand = (unsigned char)(i == 1 ? G_JAGD : G_HAUS);
        fig[i].form = (unsigned char)(i == 0 ? FORM_ZU : FORM_GEIST);
    }
    PAC->tempo = (unsigned char)(level < 5 ? 23 + level : 27);
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
    /* Bit 7 schaltet die automatische Invertierung ab: erst dadurch sind die
       Codes ab 128 eigene Zeichen und koennen als Figurvorrat dienen. */
    TED_WAAGR = TED_WAAGR | 0x80;
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
