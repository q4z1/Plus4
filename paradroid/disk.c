/*
 * disk.c - loading from the disk: the droids' pictures (picture.c)
 *
 * With the fast loader (fastload.s) if the drive has one; else the KERNAL
 * loads, and the screen is off meanwhile, as it loads with its own
 * interrupt handler; the deck's map is unpacked again afterwards. With no
 * disk the border goes red, and it tries again.
 *
 * And the drive's motor: started when the player comes near a console,
 * whose droid enquiry loads pictures, so that they load without waiting
 * the two seconds the DOS waits for it, and kept going while he stays
 * near; and at a game's end, for the 999's picture.
 */
#include <string.h>
#include <cbm.h>
#include "game.h"

extern unsigned char fl_kind;           /* fastload.s */
extern const char *fl_name;
extern void *fl_addr;
unsigned fl_load(void);
void fl_spin(void);
void fl_init(unsigned char dev);         /* fastinit.c */
unsigned char console_near(void);       /* move.s */
void mc_font(void);                     /* paradroid.s */

static unsigned char dev;               /* the drive the game came from */

/* The KERNAL needs its variables at $07D8-$07E7 to load, and the deck's
 * map is there (measured: the rest of $0400-$07FF may hold anything). They
 * are kept from the start and put back for each load. */
#define KVARS ((unsigned char *)0x07D8)
static unsigned char kvars[16];

/* first thing at the start: the drive the program came from */
void disk_init(void)
{
    dev = *(unsigned char *)0xAE;      /* the KERNAL's last device */
    memcpy(kvars, KVARS, sizeof kvars);
    if (dev < 8)
        dev = 8;
}

/* then, with the program's stack: the fast loader into the drive */
void disk_start(void)
{
    fl_init(dev);
}

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

static unsigned char by, t4;

/* every tick of a game: near a console, the motor started already, so
 * that the pictures of the console's droid enquiry load without waiting;
 * and kept going while the player stays near */
void disk_tick(void)
{
    if (fl_kind && !(++t4 & 3)) {
        if (!console_near())
            by = 0;
        else if (!by--) {
            fl_spin();
            by = 12;                    /* again in 48 ticks */
        }
    }
}

/* a game's start, and after a console (the motor kept going) */
void disk_idle(void)
{
    by = 0;
}

/* a game's end: the 999's picture loads after the static */
void disk_spin(void)
{
    if (fl_kind)
        fl_spin();
}
