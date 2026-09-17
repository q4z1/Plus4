/*
 * Pac-Man fuer den Commodore Plus/4
 * =================================
 *
 * Uebersetzt mit cc65 (-t plus4). Das Spiel laeuft im Textmodus, benutzt aber
 * einen eigenen Zeichensatz im RAM - dadurch gibt es runde Spielfiguren und
 * ein Labyrinth mit den typischen doppelten Konturlinien statt PETSCII-Kloetzen.
 *
 * Aufbau der Datei:
 *   1. Hardware        - TED-Register, Bildschirm- und Farbspeicher
 *   2. Zeichensatz     - ROM-Font kopieren, eigene Zeichen erzeugen
 *   3. Labyrinth       - Plan, Aufbau, Zeichnen
 *   4. Spielfiguren    - Pac-Man und die vier Geister
 *   5. Ton und Eingabe
 *   6. Spielablauf     - Runde, Level, Spielende
 *
 * Steuerung: W A S D oder die Cursortasten, Q beendet das Spiel.
 */

#include <conio.h>

/* ======================================================================
 * 1. Hardware
 * ==================================================================== */

/* Der Plus/4 hat den Bildschirmspeicher bei $0C00 und den Farbspeicher
   bei $0800. Ein Farbbyte ist Helligkeit * 16 + Farbnummer. */
#define BILD   ((unsigned char *)0x0C00)
#define FARBE  ((unsigned char *)0x0800)

#define TED_TON2_LO  (*(volatile unsigned char *)0xFF0F)  /* Tonhoehe Kanal 2 */
#define TED_TON2_HI  (*(volatile unsigned char *)0xFF10)
#define TED_LAUT     (*(volatile unsigned char *)0xFF11)  /* Lautstaerke + Kanalschalter */
#define TED_ZSATZ_M  (*(volatile unsigned char *)0xFF12)  /* Bit 2: Zeichensatz aus ROM/RAM */
#define TED_ZSATZ_A  (*(volatile unsigned char *)0xFF13)  /* Bit 2-7: Adresse des Zeichensatzes */
#define TED_HGRUND   (*(volatile unsigned char *)0xFF15)  /* Hintergrundfarbe */
#define TED_RAHMEN   (*(volatile unsigned char *)0xFF19)  /* Rahmenfarbe */
#define TED_RASTER   (*(volatile unsigned char *)0xFF1D)  /* aktuelle Rasterzeile */
#define ROM_EIN      (*(volatile unsigned char *)0xFF3E)
#define RAM_EIN      (*(volatile unsigned char *)0xFF3F)

/* Farben (Helligkeit * 16 + Farbnummer) */
/* Achtung: hohe Helligkeiten waschen auf dem Plus/4 fast alles zu Weiss aus.
   Kraeftige Farben gibt es erst bei Helligkeit 3 bis 6. */
#define C_SCHWARZ  0x00
#define C_WEISS    0x71
#define C_GELB     0x77   /* Pac-Man            */
#define C_ROT      0x42   /* Blinky             */
#define C_ROSA     0x6B   /* Pinky              */
#define C_CYAN     0x63   /* Inky               */
#define C_ORANGE   0x58   /* Clyde              */
#define C_BLAU     0x36   /* Mauern             */
#define C_ANGST    0x4E   /* fressbarer Geist   */
#define C_HELLBLAU 0x5D   /* Text im Titelbild  */
#define C_TUER     0x5B   /* Geisterhaustuer    */
#define C_PUNKT    0x62   /* helles Pfirsich fuer die Kruemel */

/* ======================================================================
 * 2. Zeichensatz
 * ==================================================================== */

/* Zeichencodes der selbst gebauten Zeichen. 96..111 sind die 16 Mauerformen,
   danach folgen die Spielfiguren. Mehr als 128 Zeichen gibt es nicht, weil
   der TED die Codes ab 128 automatisch invertiert darstellt. */
#define Z_MAUER   96
#define Z_PUNKT   112
#define Z_PILLE   113
#define Z_PAC     114   /* + Richtung: oben, links, unten, rechts */
#define Z_PAC_ZU  118
#define Z_GEIST   119
#define Z_ANGST   120
#define Z_AUGEN   121
#define Z_TUER    122

/* Je 8 Bytes = 8 Pixelzeilen, Bit 7 ist das linke Pixel. */
static const unsigned char FIGUREN[] = {
    0x00, 0x00, 0x00, 0x18, 0x18, 0x00, 0x00, 0x00,  /* Kruemel      */
    0x00, 0x3C, 0x7E, 0x7E, 0x7E, 0x7E, 0x3C, 0x00,  /* Kraftpille   */
    0x66, 0xE7, 0xFF, 0xFF, 0xFF, 0xFF, 0x7E, 0x3C,  /* Pac oben     */
    0x3C, 0x7E, 0x3F, 0x0F, 0x0F, 0x3F, 0x7E, 0x3C,  /* Pac links    */
    0x3C, 0x7E, 0xFF, 0xFF, 0xFF, 0xFF, 0xE7, 0x66,  /* Pac unten    */
    0x3C, 0x7E, 0xFC, 0xF0, 0xF0, 0xFC, 0x7E, 0x3C,  /* Pac rechts   */
    0x3C, 0x7E, 0xFF, 0xFF, 0xFF, 0xFF, 0x7E, 0x3C,  /* Pac Mund zu  */
    0x3C, 0x7E, 0x99, 0x99, 0xFF, 0xFF, 0xFF, 0xDB,  /* Geist        */
    0x3C, 0x7E, 0x99, 0xFF, 0xDB, 0xFF, 0xFF, 0xDB,  /* Geist Angst  */
    0x00, 0x00, 0x66, 0x66, 0x00, 0x00, 0x00, 0x00,  /* nur Augen    */
    0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00,  /* Haustuer     */
};

/* Der Zeichensatz braucht 1 KB und muss an einer durch 1024 teilbaren
   Adresse liegen. Deshalb wird grosszuegig Platz reserviert und darin die
   passende Adresse gesucht. */
static unsigned char zeichenspeicher[1024 + 1023];
static unsigned char *zeichensatz;

/* Hilfsvariablen fuer das ROM-Kopieren: siehe Kommentar in font_aus_rom(). */
static unsigned rom_index;

/*
 * Holt den Zeichensatz aus dem ROM.
 *
 * cc65 blendet auf dem Plus/4 das ROM aus, um den vollen Speicher nutzen zu
 * koennen. Fuer den Zugriff auf den Zeichengenerator bei $D000 muss es kurz
 * wieder eingeblendet werden. In diesem Fenster darf kein C-Stack benutzt
 * werden, denn der liegt bei $F500-$FCFF und waere dann vom ROM verdeckt.
 * Darum sind Zaehler und Zeiger globale Variablen und es wird keine Funktion
 * aufgerufen - cc65 erzeugt daraus reine Zeropage- und Absolutzugriffe.
 */
static void font_aus_rom(void)
{
    __asm__("sei");
    ROM_EIN = 0;
    for (rom_index = 0; rom_index < 1024; ++rom_index)
        zeichensatz[rom_index] = ((unsigned char *)0xD000)[rom_index];
    RAM_EIN = 0;
    __asm__("cli");
}

/*
 * Erzeugt die 16 Mauerzeichen.
 *
 * Gezeichnet wird nicht die Mauerflaeche selbst, sondern ihr Umriss: eine
 * Linie kommt nur an die Kante, hinter der ein begehbares Feld liegt. Dadurch
 * werden aus zwei Zellen dicken Mauerbloecken automatisch die doppelten
 * Konturlinien des Originals.
 *
 * Die Nummer des Zeichens ist eine Bitmaske:
 *   Bit 0 = oben offen, Bit 1 = unten offen, Bit 2 = links, Bit 3 = rechts.
 */
static void mauerzeichen_bauen(void)
{
    unsigned char m, y, b;

    for (m = 0; m < 16; ++m) {
        for (y = 0; y < 8; ++y) {
            b = 0;
            if ((m & 1) && y == 0) b |= 0xFF;
            if ((m & 2) && y == 7) b |= 0xFF;
            if (m & 4) b |= 0x80;
            if (m & 8) b |= 0x01;
            zeichensatz[(Z_MAUER + m) * 8 + y] = b;
        }
    }
}

static void zeichensatz_einrichten(void)
{
    unsigned i;

    zeichensatz = (unsigned char *)(((unsigned)zeichenspeicher + 1023) & 0xFC00);

    font_aus_rom();
    mauerzeichen_bauen();

    for (i = 0; i < sizeof(FIGUREN); ++i)
        zeichensatz[Z_PUNKT * 8 + i] = FIGUREN[i];

    /* TED auf den Zeichensatz im RAM umschalten. Bit 1 von $FF13 steuert den
       Systemtakt und muss unveraendert bleiben. */
    TED_ZSATZ_A = (unsigned char)((((unsigned)zeichensatz) >> 8) & 0xFC)
                | (TED_ZSATZ_A & 0x02);
    TED_ZSATZ_M = TED_ZSATZ_M & ~0x04;
}

/* ======================================================================
 * 3. Labyrinth
 * ==================================================================== */

#define MB 28          /* Breite in Feldern */
#define MH 23          /* Hoehe in Feldern  */
#define OFFX 6         /* linke obere Ecke auf dem Bildschirm */
#define OFFY 2

#define F_LEER   0
#define F_PUNKT  1
#define F_PILLE  2
#define F_MAUER  3
#define F_TUER   4

/*
 * '#' Mauer, '.' Kruemel, 'o' Kraftpille, '-' Geisterhaustuer, ' ' leer.
 * Der Plan ist links/rechts spiegelsymmetrisch wie im Original.
 */
static const char PLAN[MH][MB + 1] = {
    "############################",
    "#............##............#",
    "#.####.#####.##.#####.####.#",
    "#o####.#####.##.#####.####o#",
    "#.####.#####.##.#####.####.#",
    "#..........................#",
    "#.####.##.########.##.####.#",
    "#......##..........##......#",
    "######.#####.##.#####.######",
    "     #.##          ##.#     ",
    "######.## ###--### ##.######",
    "      .   #      #   .      ",
    "######.## #      # ##.######",
    "     #.## ######## ##.#     ",
    "######.##          ##.######",
    "######.#####.##.#####.######",
    "#............##............#",
    "#.####.#####.##.#####.####.#",
    "#o..##................##..o#",
    "###.##.##.########.##.##.###",
    "#......##..........##......#",
    "#..........................#",
    "############################",
};

static unsigned char feld[MH][MB];
static unsigned int  restpunkte;        /* noch nicht gefressene Kruemel */
static unsigned char pillenx[4], pilleny[4];
static unsigned char mauerfarbe = C_BLAU;

/* Startplaetze */
#define PAC_STARTX 13
#define PAC_STARTY 18
#define TUERX      13           /* Spalte der Geisterhaustuer */
#define TUERY      10
#define HAUSY      11           /* Zeile im Geisterhaus */
#define AUSY        9           /* Zeile ueber der Tuer, schon im Freien */

static void zeichen_setzen(unsigned char sx, unsigned char sy,
                           unsigned char z, unsigned char f)
{
    unsigned pos = (unsigned)sy * 40 + sx;
    BILD[pos] = z;
    FARBE[pos] = f;
}

static unsigned char ist_mauer(unsigned char mx, unsigned char my)
{
    if (mx >= MB || my >= MH) return 0;     /* ausserhalb zaehlt als offen */
    return (unsigned char)(feld[my][mx] == F_MAUER);
}

static unsigned char mauer_maske(unsigned char mx, unsigned char my)
{
    unsigned char m = 0;
    if (!ist_mauer(mx, my - 1)) m |= 1;
    if (!ist_mauer(mx, my + 1)) m |= 2;
    if (!ist_mauer(mx - 1, my)) m |= 4;
    if (!ist_mauer(mx + 1, my)) m |= 8;
    return m;
}

static void feld_zeichnen(unsigned char mx, unsigned char my)
{
    switch (feld[my][mx]) {
    case F_MAUER:
        zeichen_setzen(OFFX + mx, OFFY + my,
                       (unsigned char)(Z_MAUER + mauer_maske(mx, my)), mauerfarbe);
        break;
    case F_TUER:
        zeichen_setzen(OFFX + mx, OFFY + my, Z_TUER, C_TUER);
        break;
    case F_PUNKT:
        zeichen_setzen(OFFX + mx, OFFY + my, Z_PUNKT, C_PUNKT);
        break;
    case F_PILLE:
        zeichen_setzen(OFFX + mx, OFFY + my, Z_PILLE, C_PUNKT);
        break;
    default:
        zeichen_setzen(OFFX + mx, OFFY + my, 32, C_SCHWARZ);
        break;
    }
}

/* Faerbt nur die Mauern um - deutlich schneller als neu zeichnen und
   dadurch ein echtes Blinken statt eines sichtbaren Bildaufbaus. */
static void mauern_faerben(unsigned char f)
{
    unsigned char mx, my;
    for (my = 0; my < MH; ++my)
        for (mx = 0; mx < MB; ++mx)
            if (feld[my][mx] == F_MAUER)
                FARBE[(unsigned)(OFFY + my) * 40 + OFFX + mx] = f;
}

static void labyrinth_zeichnen(void)
{
    unsigned char mx, my;
    for (my = 0; my < MH; ++my)
        for (mx = 0; mx < MB; ++mx)
            feld_zeichnen(mx, my);
}

/* Baut den Plan in das Spielfeld um und zaehlt die Kruemel. */
static void labyrinth_aufbauen(void)
{
    unsigned char mx, my, n = 0;

    restpunkte = 0;
    for (my = 0; my < MH; ++my) {
        for (mx = 0; mx < MB; ++mx) {
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

    /* Unter Pac-Man liegt kein Kruemel. */
    if (feld[PAC_STARTY][PAC_STARTX] == F_PUNKT) {
        feld[PAC_STARTY][PAC_STARTX] = F_LEER;
        --restpunkte;
    }
}

/* ======================================================================
 * 4. Spielfiguren
 * ==================================================================== */

#define R_OBEN   0
#define R_LINKS  1
#define R_UNTEN  2
#define R_RECHTS 3

static const signed char DX[4] = {  0, -1,  0,  1 };
static const signed char DY[4] = { -1,  0,  1,  0 };

static unsigned char pac_x, pac_y, pac_r, pac_wunsch, pac_offen;

/* Zustaende eines Geistes */
#define G_HAUS   0      /* wartet im Geisterhaus          */
#define G_RAUS   1      /* verlaesst das Haus (Zwangsweg) */
#define G_JAGD   2      /* normal unterwegs               */
#define G_ANGST  3      /* fluechtet, ist fressbar        */
#define G_AUGEN  4      /* gefressen, laeuft nach Hause   */
#define G_REIN   5      /* steigt in das Haus hinab       */

typedef struct {
    unsigned char x, y;
    unsigned char r;            /* Blickrichtung */
    unsigned char zustand;
    unsigned char farbe;
    unsigned char startx, starty;
    unsigned char zielx, ziely;
    unsigned char wartet;       /* Restzeit im Haus */
    unsigned char takt;         /* Zaehler bis zum naechsten Schritt */
} Geist;

static Geist geister[4];

static unsigned int  angst_rest;    /* Restdauer der Kraftpille in Bildern */
static unsigned char gefressen;     /* wieviele Geister in dieser Pille schon */
static unsigned int  modus_rest;    /* Restzeit bis Jagd/Streunen wechselt */
static unsigned char streunen;      /* 1 = Geister laufen in ihre Ecken */

static unsigned zufallswert = 0x1234;

static unsigned char zufall(void)
{
    zufallswert = zufallswert * 25173 + 13849;
    return (unsigned char)(zufallswert >> 8);
}

/* Darf auf dieses Feld gelaufen werden? Die Haustuer nur, wenn tuer != 0. */
static unsigned char begehbar(unsigned char mx, unsigned char my, unsigned char tuer)
{
    unsigned char f;
    if (my >= MH) return 0;
    if (mx >= MB) return 0;
    f = feld[my][mx];
    if (f == F_MAUER) return 0;
    if (f == F_TUER)  return tuer;
    return 1;
}

/* Ein Feld weiter in Richtung r, mit Tunnel am linken und rechten Rand. */
static unsigned char naechstes_x(unsigned char mx, unsigned char r)
{
    signed char nx = (signed char)mx + DX[r];
    if (nx < 0) return MB - 1;
    if (nx >= MB) return 0;
    return (unsigned char)nx;
}

static unsigned char naechstes_y(unsigned char my, unsigned char r)
{
    return (unsigned char)((signed char)my + DY[r]);
}

static void figuren_setzen(void)
{
    unsigned char i;

    pac_x = PAC_STARTX;
    pac_y = PAC_STARTY;
    pac_r = R_LINKS;
    pac_wunsch = R_LINKS;
    pac_offen = 1;

    for (i = 0; i < 4; ++i) {
        geister[i].x = geister[i].startx;
        geister[i].y = geister[i].starty;
        geister[i].r = R_LINKS;
        geister[i].takt = 0;
        geister[i].wartet = (unsigned char)(i * 12);
        geister[i].zustand = (i == 0) ? G_JAGD : G_HAUS;
    }

    angst_rest = 0;
    gefressen = 0;
    streunen = 1;
    modus_rest = 300;
}

static void geister_anlegen(void)
{
    /* Blinky startet bereits ueber dem Haus, die anderen warten darin. */
    geister[0].farbe = C_ROT;      geister[0].startx = TUERX;    geister[0].starty = AUSY;
    geister[1].farbe = C_ROSA;     geister[1].startx = TUERX;    geister[1].starty = HAUSY;
    geister[2].farbe = C_CYAN;     geister[2].startx = TUERX - 2; geister[2].starty = HAUSY;
    geister[3].farbe = C_ORANGE;   geister[3].startx = TUERX + 2; geister[3].starty = HAUSY;
}

/* Zielfeld eines Geistes bestimmen - das ist die eigentliche "KI". */
static void ziel_bestimmen(unsigned char i)
{
    Geist *g = &geister[i];
    signed int zx, zy;
    unsigned char vx, vy;

    if (g->zustand == G_AUGEN) {          /* Augen laufen zur Haustuer */
        g->zielx = TUERX;
        g->ziely = AUSY;
        return;
    }

    if (streunen) {                        /* jeder Geist hat seine Ecke */
        switch (i) {
        case 0: g->zielx = MB - 2; g->ziely = 0;      break;
        case 1: g->zielx = 1;      g->ziely = 0;      break;
        case 2: g->zielx = MB - 2; g->ziely = MH - 1; break;
        default: g->zielx = 1;     g->ziely = MH - 1; break;
        }
        return;
    }

    /* zwei bzw. vier Felder vor Pac-Man */
    vx = naechstes_x(naechstes_x(pac_x, pac_r), pac_r);
    vy = (unsigned char)((signed char)pac_y + 2 * DY[pac_r]);

    switch (i) {
    case 0:                                /* Blinky jagt direkt */
        g->zielx = pac_x;
        g->ziely = pac_y;
        break;
    case 1:                                /* Pinky zielt vor Pac-Man */
        g->zielx = naechstes_x(naechstes_x(vx, pac_r), pac_r);
        zy = (signed int)(signed char)vy + 2 * DY[pac_r];
        g->ziely = (unsigned char)(zy < 0 ? 0 : (zy >= MH ? MH - 1 : zy));
        break;
    case 2:                                /* Inky spiegelt Blinky an diesem Punkt */
        zx = 2 * (signed int)vx - (signed int)geister[0].x;
        zy = 2 * (signed int)(signed char)vy - (signed int)geister[0].y;
        g->zielx = (unsigned char)(zx < 0 ? 0 : (zx >= MB ? MB - 1 : zx));
        g->ziely = (unsigned char)(zy < 0 ? 0 : (zy >= MH ? MH - 1 : zy));
        break;
    default: {                             /* Clyde kneift aus der Naehe */
        signed char ax = (signed char)(g->x - pac_x);
        signed char ay = (signed char)(g->y - pac_y);
        if (ax < 0) ax = -ax;
        if (ay < 0) ay = -ay;
        if (ax + ay > 8) {
            g->zielx = pac_x;
            g->ziely = pac_y;
        } else {
            g->zielx = 1;
            g->ziely = MH - 1;
        }
        break;
      }
    }
}

/*
 * Waehlt die Richtung, die dem Ziel am naechsten kommt. Umkehren ist
 * verboten - genau wie im Original. Bei Gleichstand gewinnt die zuerst
 * gepruefte Richtung (oben, links, unten, rechts).
 */
static unsigned char richtung_waehlen(unsigned char i)
{
    Geist *g = &geister[i];
    unsigned char gegen = g->r ^ 2;
    unsigned char tuer = (unsigned char)(g->zustand == G_AUGEN);
    unsigned char r, beste = 255, nx, ny, anzahl = 0;
    unsigned char moeglich[4];
    unsigned int abstand, bester = 0xFFFF;
    signed int dx, dy;

    for (r = 0; r < 4; ++r) {
        if (r == gegen) continue;
        nx = naechstes_x(g->x, r);
        ny = naechstes_y(g->y, r);
        if (!begehbar(nx, ny, tuer)) continue;

        moeglich[anzahl++] = r;
        dx = (signed int)nx - (signed int)g->zielx;
        dy = (signed int)ny - (signed int)g->ziely;
        abstand = (unsigned int)(dx * dx + dy * dy);
        if (abstand < bester) { bester = abstand; beste = r; }
    }

    if (anzahl == 0) return gegen;                 /* Sackgasse: umdrehen */
    if (g->zustand == G_ANGST)                     /* in Panik: Zufall */
        return moeglich[zufall() % anzahl];
    return beste;
}

/* ======================================================================
 * 5. Ton und Eingabe
 * ==================================================================== */

static unsigned char ton_rest;

static void ton(unsigned int hoehe, unsigned char dauer)
{
    TED_TON2_LO = (unsigned char)(hoehe & 0xFF);
    TED_TON2_HI = (unsigned char)(hoehe >> 8);
    TED_LAUT = 0x26;              /* Kanal 2 an, Lautstaerke 6 */
    ton_rest = dauer;
}

static void ton_stumm(void)
{
    TED_LAUT = 0x00;
    ton_rest = 0;
}

/* Wartet auf den naechsten Bildaufbau und zaehlt dabei den Ton herunter. */
static void bild_warten(void)
{
    while (TED_RASTER >= 200) { }
    while (TED_RASTER <  200) { }
    if (ton_rest && --ton_rest == 0) TED_LAUT = 0x00;
}

static void bilder_warten(unsigned char n)
{
    while (n--) bild_warten();
}

/* Liefert die zuletzt gedrueckte Taste oder 0. */
static unsigned char taste_holen(void)
{
    unsigned char t = 0;
    while (kbhit()) t = (unsigned char)cgetc();
    return t;
}

/* ======================================================================
 * 6. Anzeige
 * ==================================================================== */

static unsigned int  punkte;
static unsigned char leben, level;

/*
 * Gibt Text aus, indem Buchstaben in Bildschirmcodes umgerechnet werden.
 *
 * Achtung, Stolperstein: cc65 uebersetzt Zeichen- und Textliteralen fuer
 * CBM-Ziele nach PETSCII. Aus 'A' im Quelltext wird also nicht 65, sondern
 * 193. Deshalb wird hier nicht mit festen Zahlen gerechnet, sondern relativ
 * zu 'a' bzw. 'A' - das stimmt in beiden Zeichensaetzen. Zieht man stattdessen
 * 64 bzw. 96 ab, landet man 128 zu hoch und der TED stellt alles invers dar.
 * Ziffern und Satzzeichen haben in PETSCII schon den richtigen Wert.
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
                       (unsigned char)(i < leben - 1 ? Z_PAC + R_RECHTS : 32), C_GELB);
}

static void bildschirm_leeren(void)
{
    unsigned i;
    for (i = 0; i < 1000; ++i) { BILD[i] = 32; FARBE[i] = C_SCHWARZ; }
}

/* Zeichnet einen waagerechten Ausschnitt des Labyrinths neu - damit werden
   eingeblendete Texte wie READY! wieder entfernt. */
static void bereich_neu(unsigned char von, unsigned char bis, unsigned char my)
{
    while (von <= bis) feld_zeichnen(von++, my);
}

static void figuren_zeichnen(void)
{
    unsigned char i, z, f;

    for (i = 0; i < 4; ++i) {
        if (geister[i].zustand == G_AUGEN || geister[i].zustand == G_REIN)
            z = Z_AUGEN;
        else if (geister[i].zustand == G_ANGST)
            z = Z_ANGST;
        else
            z = Z_GEIST;

        if (geister[i].zustand == G_ANGST)
            /* Kurz vor Ablauf der Kraftpille blinken die Geister weiss. */
            f = (angst_rest < 80 && (angst_rest & 8)) ? C_WEISS : C_ANGST;
        else
            f = geister[i].farbe;

        zeichen_setzen((unsigned char)(OFFX + geister[i].x),
                       (unsigned char)(OFFY + geister[i].y), z, f);
    }
    zeichen_setzen((unsigned char)(OFFX + pac_x), (unsigned char)(OFFY + pac_y),
                   (unsigned char)(pac_offen ? Z_PAC + pac_r : Z_PAC_ZU), C_GELB);
}

/* ======================================================================
 * 7. Spielablauf
 * ==================================================================== */

#define TOT       0
#define GESCHAFFT 1
#define ABBRUCH   2

static void alle_neu_zeichnen(void)
{
    labyrinth_zeichnen();
    figuren_zeichnen();
    statuszeile();
}

static void bereit_anzeigen(void)
{
    text_zeigen(OFFX + 11, OFFY + AUSY, "READY!", C_GELB);
    bilder_warten(100);
    bereich_neu(9, 18, AUSY);
}

/* Pac-Man frisst, was auf seinem Feld liegt. */
static void fressen(void)
{
    unsigned char i;

    if (feld[pac_y][pac_x] == F_PUNKT) {
        feld[pac_y][pac_x] = F_LEER;
        --restpunkte;
        punkte += 10;
        ton(pac_offen ? 560 : 620, 2);
        statuszeile();
    } else if (feld[pac_y][pac_x] == F_PILLE) {
        feld[pac_y][pac_x] = F_LEER;
        --restpunkte;
        punkte += 50;
        ton(300, 12);
        statuszeile();

        /* Mit steigendem Level wirkt die Kraftpille kuerzer. */
        angst_rest = (unsigned int)(level < 10 ? 300 - level * 20 : 100);
        gefressen = 0;
        for (i = 0; i < 4; ++i) {
            if (geister[i].zustand == G_JAGD) {
                geister[i].zustand = G_ANGST;
                geister[i].r ^= 2;            /* Geister drehen um */
            }
        }
    }
}

static void pacman_ziehen(void)
{
    unsigned char nx, ny;

    /* Wenn die gewuenschte Richtung frei ist, wird sofort abgebogen. */
    nx = naechstes_x(pac_x, pac_wunsch);
    ny = naechstes_y(pac_y, pac_wunsch);
    if (begehbar(nx, ny, 0)) pac_r = pac_wunsch;

    nx = naechstes_x(pac_x, pac_r);
    ny = naechstes_y(pac_y, pac_r);
    if (!begehbar(nx, ny, 0)) return;         /* vor der Wand stehenbleiben */

    feld_zeichnen(pac_x, pac_y);              /* altes Feld freigeben */
    pac_x = nx;
    pac_y = ny;
    pac_offen ^= 1;
    fressen();
}

static void geist_ziehen(unsigned char i)
{
    Geist *g = &geister[i];
    unsigned char altx = g->x, alty = g->y;

    switch (g->zustand) {

    case G_HAUS:
        if (g->wartet) --g->wartet;
        else g->zustand = G_RAUS;
        return;

    case G_RAUS:                              /* fester Weg durch die Tuer */
        if (g->x < TUERX) ++g->x;
        else if (g->x > TUERX) --g->x;
        else if (g->y > AUSY) --g->y;
        if (g->x == TUERX && g->y == AUSY) {
            /* Laeuft gerade eine Kraftpille, ist auch der Neuankoemmling fressbar. */
            g->zustand = angst_rest ? G_ANGST : G_JAGD;
            g->r = R_LINKS;
        }
        break;

    case G_REIN:                              /* zurueck ins Haus hinab */
        if (g->y < HAUSY) ++g->y;
        if (g->y == HAUSY) {
            g->zustand = G_HAUS;
            g->wartet = 40;
            g->r = R_OBEN;
        }
        break;

    default:
        ziel_bestimmen(i);
        g->r = richtung_waehlen(i);
        g->x = naechstes_x(g->x, g->r);
        g->y = naechstes_y(g->y, g->r);
        if (g->zustand == G_AUGEN && g->x == TUERX && g->y == AUSY)
            g->zustand = G_REIN;
        break;
    }

    feld_zeichnen(altx, alty);
}

/* Beruehren sich Pac-Man und ein Geist? Rueckgabe: 1 = Pac-Man ist tot. */
static unsigned char zusammenstoss(void)
{
    unsigned char i;

    for (i = 0; i < 4; ++i) {
        if (geister[i].x != pac_x || geister[i].y != pac_y) continue;
        if (geister[i].zustand == G_ANGST) {
            if (gefressen < 4) ++gefressen;
            punkte = (unsigned int)(punkte + (100u << gefressen));
            geister[i].zustand = G_AUGEN;
            ton(900, 10);
            statuszeile();
        } else if (geister[i].zustand == G_JAGD) {
            return 1;
        }
    }
    return 0;
}

static void sterben(void)
{
    unsigned char i;

    ton_stumm();
    for (i = 0; i < 20; ++i) {
        zeichen_setzen((unsigned char)(OFFX + pac_x), (unsigned char)(OFFY + pac_y),
                       (unsigned char)((i & 2) ? Z_PAC_ZU : Z_PAC + (i & 3)),
                       (unsigned char)((i & 1) ? C_GELB : C_ROT));
        ton((unsigned int)(760 - i * 30), 3);
        bilder_warten(5);
    }
    ton_stumm();
    zeichen_setzen((unsigned char)(OFFX + pac_x), (unsigned char)(OFFY + pac_y), 32, C_SCHWARZ);
}

static void level_geschafft(void)
{
    unsigned char i;

    ton_stumm();
    for (i = 0; i < 8; ++i) {
        mauern_faerben((unsigned char)((i & 1) ? C_WEISS : C_BLAU));
        bilder_warten(14);
    }
    mauern_faerben(C_BLAU);
}

/*
 * Eine Runde: laeuft, bis Pac-Man stirbt, das Level leer ist oder Q kommt.
 * Pac-Man und die Geister haben eigene Taktzaehler, dadurch koennen sie
 * unterschiedlich schnell sein.
 */
static unsigned char runde_spielen(void)
{
    unsigned char pac_takt = 0, pac_tempo, geist_tempo, t, i, blinktakt = 0;
    unsigned char pillen_an = 1;

    /* Mit jedem Level wird es ein wenig schneller. */
    pac_tempo = (unsigned char)(level < 5 ? 7 - level / 2 : 5);
    geist_tempo = (unsigned char)(level < 6 ? 9 - level / 2 : 6);

    for (;;) {
        bild_warten();

        /* --- Eingabe --- */
        /* Auch hier gilt PETSCII: 'w' ist der Code der ungeshifteten Taste W,
           'W' der mit Shift. Die Zahlen sind die vier Cursortasten. */
        t = taste_holen();
        switch (t) {
        case 'w': case 'W': case 145: pac_wunsch = R_OBEN;   break;
        case 'a': case 'A': case 157: pac_wunsch = R_LINKS;  break;
        case 's': case 'S': case 17:  pac_wunsch = R_UNTEN;  break;
        case 'd': case 'D': case 29:  pac_wunsch = R_RECHTS; break;
        case 'q': case 'Q': return ABBRUCH;
        default: break;
        }

        /* --- Kraftpillen blinken --- */
        if (++blinktakt >= 16) {
            blinktakt = 0;
            pillen_an ^= 1;
            for (i = 0; i < 4; ++i)
                if (feld[pilleny[i]][pillenx[i]] == F_PILLE)
                    zeichen_setzen((unsigned char)(OFFX + pillenx[i]),
                                   (unsigned char)(OFFY + pilleny[i]),
                                   Z_PILLE, pillen_an ? C_PUNKT : C_SCHWARZ);
        }

        /* --- Jagd- und Angstphasen --- */
        if (angst_rest) {
            if (--angst_rest == 0)
                for (i = 0; i < 4; ++i)
                    if (geister[i].zustand == G_ANGST) geister[i].zustand = G_JAGD;
        } else if (modus_rest && --modus_rest == 0) {
            streunen ^= 1;
            modus_rest = streunen ? 300 : 900;
            for (i = 0; i < 4; ++i)
                if (geister[i].zustand == G_JAGD) geister[i].r ^= 2;
        }

        /* --- Pac-Man --- */
        if (++pac_takt >= pac_tempo) {
            pac_takt = 0;
            pacman_ziehen();
            if (zusammenstoss()) return TOT;
            if (restpunkte == 0) return GESCHAFFT;
        }

        /* --- Geister --- */
        for (i = 0; i < 4; ++i) {
            unsigned char tempo = geist_tempo;
            if (geister[i].zustand == G_ANGST) tempo = (unsigned char)(geist_tempo + 4);
            else if (geister[i].zustand == G_AUGEN) tempo = 3;
            if (++geister[i].takt < tempo) continue;
            geister[i].takt = 0;
            geist_ziehen(i);
        }
        if (zusammenstoss()) return TOT;

        figuren_zeichnen();
    }
}

static unsigned char titelbild(void)
{
    bildschirm_leeren();
    text_zeigen(15, 4, "PAC-MAN", C_GELB);
    text_zeigen(10, 6, "FUER COMMODORE PLUS/4", C_HELLBLAU);

    zeichen_setzen(13, 4, Z_PAC + R_RECHTS, C_GELB);
    zeichen_setzen(24, 4, Z_GEIST, C_ROT);

    text_zeigen(8, 11, "STEUERUNG", C_WEISS);
    text_zeigen(8, 13, "W A S D  ODER CURSORTASTEN", C_PUNKT);
    text_zeigen(8, 15, "Q BEENDET DAS SPIEL", C_PUNKT);

    zeichen_setzen(8, 17, Z_PUNKT, C_PUNKT);
    text_zeigen(10, 17, "10 PUNKTE", C_WEISS);
    zeichen_setzen(8, 18, Z_PILLE, C_PUNKT);
    text_zeigen(10, 18, "50 PUNKTE UND GEISTERJAGD", C_WEISS);

    text_zeigen(10, 21, "LEERTASTE ZUM STARTEN", C_GELB);

    while (taste_holen()) { }            /* alte Tastendruecke verwerfen */
    for (;;) {
        unsigned char t = taste_holen();
        if (t == ' ') return 0;
        if (t == 'q' || t == 'Q') return 1;
        bild_warten();
    }
}

static void spiel_vorbei(void)
{
    text_zeigen(OFFX + 9, OFFY + AUSY, "GAME OVER", C_ROT);
    bilder_warten(200);
}

int main(void)
{
    unsigned char hgrund, rahmen, zsatz, zadr, ausgang;

    /* Ausgangszustand merken, damit der Rechner danach wieder normal ist. */
    hgrund = TED_HGRUND;
    rahmen = TED_RAHMEN;
    zsatz  = TED_ZSATZ_M;
    zadr   = TED_ZSATZ_A;

    cursor(0);
    ton_stumm();
    zeichensatz_einrichten();
    geister_anlegen();

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
            alle_neu_zeichnen();
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
                spiel_vorbei();
                break;
            }
            statuszeile();
        }
    }

ende:
    /* Alles zuruecksetzen und ein sauberes BASIC hinterlassen. */
    ton_stumm();
    TED_ZSATZ_M = zsatz;
    TED_ZSATZ_A = zadr;
    TED_HGRUND = hgrund;
    TED_RAHMEN = rahmen;
    cursor(1);
    clrscr();
    return 0;
}
