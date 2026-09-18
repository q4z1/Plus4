/*
 * A PokerTH lobby on a Commodore Plus/4.
 *
 * Stage four: the machine finally does the thing. It shows the games on the
 * server, who is online and what they are saying, and lets you say something
 * back - on a 40x25 screen, over a 2400 baud line, in about 12 KB.
 *
 * None of PokerTH gets this far. TLS, protobuf, the player table, UTF-8, the
 * 32 bit game ids - all of that stops at the proxy, which sends this program
 * the small fixed records described in ../protocol.md. What arrives here is
 * already PETSCII, already truncated to something a 40 column screen can
 * show, and never larger than the machine can swallow.
 *
 *   ../proxy/proxy.py --login --ip232
 *   ./run.sh
 *
 * Three rules are not negotiable, all learned in stage three and all of them
 * about the same thing - never letting one direction wait for the other:
 *
 *   - bytes come out of the driver unconditionally, because a full receive
 *     buffer stops transmission too
 *   - nothing ever waits for ser_put, which returns SER_ERR_OVERFLOW rather
 *     than blocking, and waiting for it in a loop is a deadlock
 *   - the proxy is told how much it may send, and is told again as soon as
 *     the bytes have been consumed
 */

#include <plus4.h>
#include <string.h>

#include "logo.h"

/* ------------------------------------------------------------------ wire */

#define PROTOCOL_VERSION 1

/* How much the proxy may have in flight. Not the size of a buffer: the
** number of bytes measured to survive the link, see "What the wire turned
** out to be" in ../README.md. 32 is the value that produced the one run
** where the whole lobby arrived intact; 16 was tried too and did not help,
** so the number is not yet the thing that is wrong. See "Where this stands"
** in ../README.md. */
#define RX_WINDOW 32

/* Proxy -> Plus/4 */
#define D_HELLO       0x01
#define D_STATE       0x02
#define D_NOTICE      0x03
#define D_GAME_CLEAR  0x10
#define D_GAME_ADD    0x11
#define D_GAME_UPDATE 0x12
#define D_GAME_REMOVE 0x13
#define D_CHAT        0x20
#define D_PLAYERS     0x21
#define D_TABLE       0x40
#define D_SEAT        0x41
#define D_SEAT_BET    0x42
#define D_HAND        0x43
#define D_BOARD       0x44
#define D_POT         0x45
#define D_TURN        0x46
#define D_ASK         0x47
#define D_RESULT      0x48
#define D_TABLE_END   0x49

/* Plus/4 -> proxy */
#define U_HELLO       0x80
#define U_ACK         0x81
#define U_CHAT        0x82
#define U_JOIN        0x83
#define U_LEAVE       0x84
#define U_ACTION      0x85
#define U_LOGIN       0x86
#define U_BYE         0x8F

#define STATE_OFFLINE    0
#define STATE_CONNECTING 1
#define STATE_LOBBY      2
#define STATE_TABLE      3
#define STATE_ERROR      4

#define GAME_PRIVATE  0x01
#define GAME_STARTED  0x02
#define GAME_RANKING  0x04

#define SEAT_TAKEN       0x01
#define SEAT_FOLDED      0x02
#define SEAT_ALL_IN      0x04
#define SEAT_DEALER      0x08
#define SEAT_YOU         0x10
#define SEAT_SITTING_OUT 0x20

#define MAY_FOLD   0x01
#define MAY_CHECK  0x02
#define MAY_CALL   0x04
#define MAY_BET    0x08
#define MAY_RAISE  0x10
#define MAY_ALL_IN 0x20

#define ACTION_FOLD  1
#define ACTION_CHECK 2
#define ACTION_CALL  3
#define ACTION_BET   4
#define ACTION_RAISE 5
#define ACTION_ALLIN 6

#define CARD_NONE 52

/*
 * Key repeat, off.
 *
 * The 264 KERNAL repeats every key rather than just the cursor keys, and
 * fast enough that an ordinary press arrives as "hhhhhhhh". RPTFLG is at
 * $0540 with the same meaning as on the C64: $80 repeats everything, $40
 * repeats nothing, $00 repeats only the cursor keys, space and delete. The
 * old value goes back on the way out - it belongs to whatever runs next.
 */
#define RPTFLG      (*(unsigned char *)0x0540)
#define RPTFLG_NONE 0x40

/*
 * The keyboard, read out of the buffer the KERNAL fills, rather than through
 * conio.
 *
 * cc65 keeps the ROM switched out on this machine so that the RAM interrupt
 * vector is the one that counts - which is how the serial driver gets to see
 * the ACIA at all. conio switches the ROM back in to call KERNAL routines,
 * and a byte that arrives during that window is delivered to the KERNAL's
 * handler instead, which knows nothing about an ACIA. It leaves the byte
 * unread, so the interrupt line stays up, so the handler is entered again
 * immediately: the storm described in ../README.md. Polling kbhit() every
 * time round the loop opens that window thousands of times a second.
 *
 * The buffer at $0527 and its length at $EF are plain RAM, filled by the
 * keyboard scan that runs in the interrupt anyway. Reading them costs no
 * ROM window at all.
 */
/* What conio.h used to provide: plain PETSCII codes as the KERNAL puts them
** in the buffer. */
#define CH_ENTER 13
#define CH_DEL   20

/*
 * The function keys, taken over for the duration.
 *
 * On this machine they are not keys that deliver a code: they are text
 * macros, and pressing F1 puts the whole word "graphic" into the keyboard
 * buffer. Eight definitions live at $0567, their lengths in the eight bytes
 * from $055F. So each is redefined here as a single byte that no ordinary
 * key produces, and the originals are put back on the way out - they belong
 * to whatever runs next, as the repeat flag does.
 */
/*
 * On, and now for a reason rather than a hope.
 *
 * Asking the machine settled it. Pressing the five keys reported, as length
 * and position: f1 18/0, f2 6/18, f3 10/24, f4 7/34, help 5/56 - and
 * 0+18=18, 18+6=24, 24+10=34. So $055F really is a table of lengths, $055E
 * is where in the definitions the key being fed out starts, and that offset
 * is the only thing that names the key.
 *
 * Which makes this the fix rather than a workaround: with every length set
 * to one, the offsets become 0 to 7 - the key number, plainly. The originals
 * go back on the way out.
 */
#define TAKE_FUNCTION_KEYS 1

#define FKEY_LENGTHS ((unsigned char *)0x055F)
#define FKEY_TEXT    ((unsigned char *)0x0567)
#define FKEY_TEXT_SIZE 128

#define KEY_F1 0x80
#define KEY_F8 0x87
#define KEY_STOP 3              /* RUN/STOP, and nothing else produces it */

/*
 * There are two ways a function key can arrive here, and both are accepted.
 *
 * The KERNAL expands the macro when a character is fetched with GETIN, and
 * this client does not use GETIN - it reads the buffer the keyboard scan
 * fills, which is what keeps the ROM switched out. So what lands in the
 * buffer is the bare key code, $85 upwards, and the redefinition above is
 * only insurance in case a machine expands it earlier.
 *
 * Which code belongs to which key on the case is not worth being sure of
 * from here - this machine has F1, F2, F3 and HELP, and shift reaches the
 * rest. All of them are accepted and the four actions repeat, so whichever
 * key is pressed, its position decides what it does. An unexpected code is
 * put in the status line rather than swallowed, which is how this was found.
 */
#define KEY_RAW_F1 0x85         /* what the keyboard scan actually delivers */
#define KEY_RAW_F8 0x8C
#define KEY_ACTION(key) (((key) - KEY_F1) & 3)
#define ACT_FOLD  0
#define ACT_CALL  1
#define ACT_RAISE 2
#define ACT_ALLIN 3

/*
 * A function key never reaches the keyboard buffer.
 *
 * Pressing one leaves no code there at all - the status line showed nothing
 * while every ordinary key showed its number. What the scan does instead is
 * note which key is waiting, in the two bytes the memory map describes as
 * being for the programmable keys, and the KERNAL then feeds the macro out
 * one character at a time when a program fetches with GETIN. This one does
 * not use GETIN, so the note is simply taken from there and cleared, which
 * turns a text macro back into the single keypress it looks like.
 */
#define FKEY_PENDING (*(unsigned char *)0x055D)
#define FKEY_STEP    (*(unsigned char *)0x055E)

#define KEY_BUFFER  ((unsigned char *)0x0527)
#define KEY_COUNT   (*(unsigned char *)0x00EF)

#if TAKE_FUNCTION_KEYS
static unsigned char saved_fkeys[8 + FKEY_TEXT_SIZE];
#endif

#if TAKE_FUNCTION_KEYS
static void take_function_keys(void)
{
    unsigned char i;

    for (i = 0; i < 8; ++i) {
        saved_fkeys[i] = FKEY_LENGTHS[i];
    }
    for (i = 0; i < FKEY_TEXT_SIZE; ++i) {
        saved_fkeys[8 + i] = FKEY_TEXT[i];
    }
    /* One byte each, laid out consecutively because every length is one. */
    for (i = 0; i < 8; ++i) {
        FKEY_LENGTHS[i] = 1;
        FKEY_TEXT[i] = KEY_F1 + i;
    }
}

static void return_function_keys(void)
{
    unsigned char i;

    for (i = 0; i < 8; ++i) {
        FKEY_LENGTHS[i] = saved_fkeys[i];
    }
    for (i = 0; i < FKEY_TEXT_SIZE; ++i) {
        FKEY_TEXT[i] = saved_fkeys[8 + i];
    }
}

#endif /* TAKE_FUNCTION_KEYS */

static unsigned char read_key(void)
{
    unsigned char count;
    unsigned char key;
    unsigned char i;

    /* A function key waiting to be expanded, taken before the buffer so the
    ** macro never gets the chance to type itself out.
    **
    ** What the byte counts is still not certain - f2 and f4 were the only
    ** two inside the range first guessed at - so every plausible value is
    ** taken now and the raw one is shown, which is the only way to learn the
    ** rest. The four actions repeat over it, so whichever key is pressed,
    ** something sensible happens. */
    key = FKEY_PENDING;
    if (key != 0) {
        /* $055D counts what is left to feed out and $055E says where it
        ** started, which is what names the key - and every definition being
        ** one byte long, that start is the key number. */
        key = FKEY_STEP;
        FKEY_PENDING = 0;
        FKEY_STEP = 0;
        return KEY_F1 + (key & 7);
    }

    count = KEY_COUNT;
    if (count == 0) {
        return 0;
    }
    key = KEY_BUFFER[0];
    for (i = 1; i < count; ++i) {
        KEY_BUFFER[i - 1] = KEY_BUFFER[i];
    }
    KEY_COUNT = count - 1;
    return key;
}

/* --------------------------------------------------------------- screen */

#define SCREEN_W      40
#define ROW_HEADER     0
#define ROW_GAMES      2
#define GAME_ROWS     12
#define ROW_CHAT      15
#define CHAT_ROWS      6
#define ROW_ANNOUNCE  21        /* who won: its own line, two above the status */
#define ROW_INPUT     24

#define MAX_GAMES     GAME_ROWS

/* The table view shares the 25 rows with the lobby: the top half is drawn by
** whichever view is showing, the chat and the two bottom lines by both. */
#define MAX_SEATS     10
#define SEAT_NAME_LEN 12

#define VIEW_LOBBY 0
#define VIEW_TABLE 1
#define VIEW_LOGIN 2

/* The start screen: who are you, and the logo above it. */
#define LOGIN_LEN   16
#define ROW_LOGO     1
#define ROW_NAME    15
#define ROW_PASSWORD 17
#define LOGIN_COLUMN 11
#define NAME_LEN      26
#define CHAT_LEN      SCREEN_W
#define INPUT_LEN     38

struct game {
    unsigned int id;
    unsigned char flags;
    unsigned char players;
    unsigned char seats;
    char name[NAME_LEN + 1];
};

static struct game games[MAX_GAMES];
static unsigned char game_count = 0;
static unsigned char games_dirty = 1;

static char chat[CHAT_ROWS][CHAT_LEN + 1];
static unsigned char chat_first = 0;   /* oldest line, wraps */
static unsigned char chat_used = 0;
static unsigned char chat_dirty = 1;

static char server[24] = "";
static unsigned int players_online = 0;
static unsigned char header_dirty = 1;

static char status[SCREEN_W + 1] = "starting";
static unsigned char status_dirty = 1;

/*
 * What the table has to announce - who took the pot, and with what.
 *
 * It had been going into the chat, where the next line pushed it off the
 * screen before it could be read. It gets a line of its own instead, kept
 * until there is something new to say.
 */
static char announce[SCREEN_W + 1] = "";
static unsigned char announce_dirty = 1;



struct seat {
    unsigned char flags;
    unsigned long money;
    unsigned long bet;
    unsigned char cards[2];     /* shown at a showdown, CARD_NONE otherwise */
    char name[SEAT_NAME_LEN + 1];
};

static struct seat seats[MAX_SEATS];
static unsigned char seat_count = 0;
static unsigned char my_seat = 0xFF;
static unsigned char turn_seat = 0xFF;
static unsigned char dealer_seat = 0xFF;
static unsigned char table_dirty = 1;
static unsigned char table_head_dirty = 1;
static unsigned int seat_dirty = 0x03FF;    /* one bit per seat */

static char table_name[NAME_LEN + 1] = "";
static unsigned char board[5];
static unsigned char board_count = 0;
static unsigned char my_cards[2] = { CARD_NONE, CARD_NONE };
static unsigned long pot = 0;
static unsigned int hand_number = 0;

static unsigned char may = 0;          /* what the server would accept */
static unsigned long to_call = 0;
static unsigned long min_raise = 0;
static unsigned long my_money = 0;

static unsigned char view = VIEW_LOGIN;
static unsigned char view_dirty = 1;

static char login_name[LOGIN_LEN + 1] = "";
static char login_password[LOGIN_LEN + 1] = "";
static unsigned char login_name_len = 0;
static unsigned char login_password_len = 0;
static unsigned char login_field = 0;       /* 0 the name, 1 the password */
static unsigned char login_dirty = 1;

static char input[INPUT_LEN + 1];
static unsigned char input_len = 0;
static unsigned char input_dirty = 1;

/* ---------------------------------------------------------------- serial */

/*
 * The ACIA, polled, without an interrupt.
 *
 * cc65 ships a driver for this chip and we used it for three stages. It cost
 * us three surprises: it accepts only SER_HS_HW, its flow-stop flag blocks
 * transmission as well as reception, and - the one that ended the argument -
 * its interrupt stops being serviced. The monitor caught the machine with
 * the ACIA asking for attention, a byte unread, an overrun already recorded,
 * and the stack walking downwards in one repeating pattern: an interrupt
 * storm, entered again the moment it returns, because nobody ever takes the
 * byte that keeps the line asserted.
 *
 * So the interrupt is switched off and this program fetches bytes itself.
 * That trades one risk for another - a byte must be collected within the
 * 4 milliseconds before the next arrives at 2400 baud - and the trade is
 * worth it, because this end controls how often it looks. Nothing here
 * blocks, and serial_poll() is cheap enough to call from inside the drawing
 * loops, which is where the time goes.
 *
 * The registers (plus4.h has them as ACIA):
 *   $FD00 data    $FD01 status    $FD02 command    $FD03 control
 */
#define ACIA_RDRF 0x08          /* a byte has arrived */
#define ACIA_OVRN 0x04          /* and one was lost before it */
#define ACIA_TDRE 0x10          /* the transmitter will take one */

/* 8 bits, one stop bit, receiver clocked by the baud generator, and 1200
** baud rather than 2400: at 2400 a byte arrives every 4 milliseconds, which
** is less than this machine needs to paint a row of the screen in C.
**
** 1200. It was dropped to 600 while every update repainted ten seats; now
** that only the row that changed is touched, the drawing fits in the 8
** milliseconds between two bytes again - and at 600 a table of ten seats
** was filling in at about one seat a second, which is a long time to watch.
** The counter in the header says whether this is too fast. */
#define ACIA_CONTROL 0x18
/* DTR asserted, RTS asserted, receive interrupt disabled - that last bit is
** the whole point. */
#define ACIA_COMMAND 0x0B

static void serial_open(void)
{
    ACIA.ctrl = ACIA_CONTROL;
    ACIA.cmd = ACIA_COMMAND;
}

static void serial_close(void)
{
    ACIA.cmd = 0x0A;            /* drop DTR, leave the interrupt off */
}

static void feed(unsigned char byte);

/*
 * Take whatever has arrived. Called from the main loop and from the middle
 * of a redraw, because a redraw takes longer than the gap between two bytes.
 */
static unsigned int overruns = 0;

static void serial_poll(void)
{
    unsigned char status = ACIA.status;

    while (status & ACIA_RDRF) {
        /* A byte arrived before the last one was collected: it is gone, and
        ** the count belongs on screen rather than in a theory. */
        if (status & ACIA_OVRN) {
            ++overruns;
        }
        feed(ACIA.data);
        status = ACIA.status;
    }
}

/* One outgoing frame at a time is plenty: this end sends acknowledgements,
** the occasional chat line, and nothing else. */
static unsigned char out[INPUT_LEN + 4];
static unsigned char out_len = 0;
static unsigned char out_pos = 0;

static unsigned int acked = 0;      /* consumed bytes not yet acknowledged */

static unsigned char out_idle(void)
{
    return out_pos == out_len;
}

static void out_pump(void)
{
    while (out_pos < out_len) {
        if (!(ACIA.status & ACIA_TDRE)) {
            return;                 /* the line is busy; try again shortly */
        }
        ACIA.data = out[out_pos];
        ++out_pos;
        serial_poll();              /* sending must not cost us a byte */
    }
}

static void out_frame(unsigned char type, unsigned char length)
{
    out[0] = type;
    out[1] = length;
    out_len = length + 2;
    out_pos = 0;
    out_pump();
}

static void send_hello(void)
{
    out[2] = PROTOCOL_VERSION;
    out[3] = RX_WINDOW & 0xFF;
    out[4] = RX_WINDOW >> 8;
    out_frame(U_HELLO, 3);
}

static void send_ack(void)
{
    out[2] = acked & 0xFF;
    out[3] = acked >> 8;
    acked = 0;
    out_frame(U_ACK, 2);
}

static void send_join(unsigned int game_id)
{
    out[2] = (unsigned char)game_id;
    out[3] = (unsigned char)(game_id >> 8);
    out_frame(U_JOIN, 2);
}

/*
 * A keypress is never dropped for want of a free line.
 *
 * Both the return key and the function keys used to act only if nothing was
 * being sent at that moment - and at 1200 baud something usually is, an
 * acknowledgement being four bytes and a third of a second apart. So the
 * line sat there with "/j 1" typed into it and nothing happening, which from
 * the keyboard is indistinguishable from a broken program. What is pressed
 * is remembered instead, and goes out as soon as the line is free.
 */
static unsigned char want_send = 0;         /* the typed line */
static unsigned char want_login = 0;        /* who we are */
static unsigned char pending_action = 0;    /* an answer at a turn, plus one */
static unsigned long pending_amount = 0;

static void remember_action(unsigned char action, unsigned long amount)
{
    pending_action = action + 1;
    pending_amount = amount;
    /* Nothing more to answer: the server asked once. */
    may = 0;
    input_dirty = 1;
}

static void send_action(unsigned char action, unsigned long amount)
{
    out[2] = action;
    out[3] = (unsigned char)amount;
    out[4] = (unsigned char)(amount >> 8);
    out[5] = (unsigned char)(amount >> 16);
    out[6] = (unsigned char)(amount >> 24);
    out_frame(U_ACTION, 5);
    /* Nothing more to answer until the server asks again. */
    may = 0;
    input_dirty = 1;
}

/*
 * Who we are. The name and the password go up together, the name with its
 * length in front so the two can be told apart - and nothing of either is
 * kept on this machine afterwards, which is the only sensible place for a
 * password to not be.
 */
static void send_login(void)
{
    unsigned char i;
    unsigned char at = 2;

    out[at++] = login_name_len;
    for (i = 0; i < login_name_len; ++i) {
        out[at++] = (unsigned char)login_name[i];
    }
    for (i = 0; i < login_password_len; ++i) {
        out[at++] = (unsigned char)login_password[i];
    }
    out_frame(U_LOGIN, at - 2);

    /* The password has served its purpose. */
    for (i = 0; i < LOGIN_LEN; ++i) {
        login_password[i] = '\0';
    }
    login_password_len = 0;
}

static void send_chat(void)
{
    unsigned char i;

    for (i = 0; i < input_len; ++i) {
        out[2 + i] = (unsigned char)input[i];
    }
    out_frame(U_CHAT, input_len);
}

/* ---------------------------------------------------------------- drawing */

/*
 * Straight into screen memory, not through conio.
 *
 * conio goes through the KERNAL, which is a poor neighbour for a program
 * whose serial driver runs off the interrupt: the first version of this
 * client stalled halfway through a redraw, sometimes after two records and
 * sometimes not at all, and the monitor found the CPU wedged inside cc65's
 * number formatter. Writing the cells directly is also what pacman/ does,
 * and on this machine it is the normal way round.
 *
 * Screen memory is at $0C00, colour memory at $0800, 40 columns by 25 rows.
 * The colour byte is luminance in the high nibble and colour in the low one.
 * Setting bit 7 of a character code gives the reversed glyph, which is what
 * the header bar is made of.
 */
/*
 * Four characters of our own: the card suits.
 *
 * Letters said d, h, s and c, which reads like a hand history rather than a
 * card. The TED can take its character set from RAM, so the ROM one is
 * copied there and four unused codes are given the shapes they should have.
 *
 * Getting at the ROM set is the awkward part, and pacman/ has been here
 * first: cc65 keeps the ROM switched out to use all of memory, so it has to
 * come back for the length of the copy - and inside that window the C stack
 * is covered by it, which means globals only and no function calls.
 *
 * The set is 2 KB, not 1. The lower 128 characters come from the ROM; the
 * upper 128 are the logo, cut into tiles. Those codes are only characters of
 * their own while the TED is told not to invert - and this program needs the
 * inversion everywhere else, for the header bar and the felt. So it is
 * switched off for the start screen and back on for the game, which is also
 * why the logo is only ever seen there.
 */
#define TED_CHARSET_MODE (*(volatile unsigned char *)0xFF12)  /* bit 2: from RAM */
#define TED_CHARSET_ADDR (*(volatile unsigned char *)0xFF13)  /* bits 2-7 */
#define ROM_IN           (*(volatile unsigned char *)0xFF3E)
#define RAM_IN           (*(volatile unsigned char *)0xFF3F)
#define ROM_CHARSET      ((unsigned char *)0xD400)   /* the mixed case set */

#define SUIT_GLYPH 0x5B         /* four codes this program never prints */
#define TED_INVERT       (*(volatile unsigned char *)0xFF07)  /* bit 7 off = own */

static unsigned char charset_store[2048 + 2047];
static unsigned char *charset;
static unsigned int rom_index;          /* global: no C stack in the window */
static unsigned char saved_charset_mode;
static unsigned char saved_charset_addr;

/* Diamonds, hearts, spades, clubs - in the order the card codes use. */
static const unsigned char SUIT_SHAPES[4][8] = {
    { 0x18, 0x3C, 0x7E, 0xFF, 0x7E, 0x3C, 0x18, 0x00 },
    { 0x66, 0xFF, 0xFF, 0xFF, 0x7E, 0x3C, 0x18, 0x00 },
    { 0x18, 0x3C, 0x7E, 0xFF, 0xFF, 0x5A, 0x18, 0x3C },
    { 0x18, 0x3C, 0x3C, 0xDB, 0xFF, 0xDB, 0x18, 0x3C }
};

static void install_charset(void)
{
    unsigned int i;
    unsigned char suit;

    /* The set has to start on a 2 KB boundary, so room is taken for one and
    ** the start moved up to the next. */
    charset = (unsigned char *)
              ((((unsigned int)charset_store) + 0x07FF) & 0xF800);

    __asm__("sei");
    ROM_IN = 0;
    for (rom_index = 0; rom_index < 1024; ++rom_index) {
        charset[rom_index] = ROM_CHARSET[rom_index];
    }
    RAM_IN = 0;
    __asm__("cli");

    for (suit = 0; suit < 4; ++suit) {
        for (i = 0; i < 8; ++i) {
            charset[(SUIT_GLYPH + suit) * 8 + i] = SUIT_SHAPES[suit][i];
        }
    }

    /* The logo goes in the upper half, where the codes are otherwise the
    ** inverted characters. Anything past the tiles stays blank. */
    for (i = 1024; i < 2048; ++i) {
        charset[i] = 0;
    }
    for (suit = 0; suit < LOGO_SHAPES; ++suit) {
        for (i = 0; i < 8; ++i) {
            charset[(LOGO_FIRST_CODE + suit) * 8 + i] = LOGO_SHAPE[suit][i];
        }
    }

    saved_charset_mode = TED_CHARSET_MODE;
    saved_charset_addr = TED_CHARSET_ADDR;
    TED_CHARSET_ADDR = (unsigned char)((((unsigned int)charset) >> 8) & 0xFC)
                       | (TED_CHARSET_ADDR & 0x02);
    TED_CHARSET_MODE = TED_CHARSET_MODE & ~0x04;
}

static void restore_charset(void)
{
    TED_CHARSET_MODE = saved_charset_mode;
    TED_CHARSET_ADDR = saved_charset_addr;
}

#define SCREEN ((unsigned char *)0x0C00)
#define COLOUR ((unsigned char *)0x0800)
/* Colour is luminance in the high nibble, colour in the low one. */
#define WHITE  0x71
#define RED    0x72
#define GREEN  0x35             /* the felt: dark enough to read on */
#define CYAN   0x73             /* our own seat */
#define YELLOW 0x77             /* all in */
#define GREY   0x11             /* folded, and out of the hand */
#define REVERSED 0x80

/* What the drawing routines colour with. One variable rather than an extra
** argument on every call, because almost everything is white. */
static unsigned char pen = WHITE;

/*
 * PETSCII in, screen codes out.
 *
 * These are two different encodings and the difference is not a constant:
 * in mixed case mode PETSCII has lowercase at $41 and uppercase at $C1,
 * while the screen wants lowercase at $01 and uppercase at $41. Subtracting
 * a flat 64 or 96 is the classic way to get everything 128 too high and the
 * whole screen reversed - see the note in pacman/pacman.c.
 */
static unsigned char screen_code(unsigned char petscii)
{
    /* Four bytes of text stand for the card suits, which are characters of
    ** our own and so cannot travel as text themselves. */
    if (petscii >= 1 && petscii <= 4) {
        return SUIT_GLYPH + petscii - 1;
    }
    if (petscii >= 0xC1 && petscii <= 0xDA) {
        return petscii - 0x80;          /* A-Z */
    }
    if (petscii >= 0x41 && petscii <= 0x5F) {
        return petscii - 0x40;          /* a-z and a few symbols */
    }
    if (petscii >= 0x20 && petscii <= 0x3F) {
        return petscii;                 /* space, digits, punctuation */
    }
    return 0x20;                        /* anything else: a space */
}

static void clear_row(unsigned char row, unsigned char reverse)
{
    unsigned int at = (unsigned int)row * SCREEN_W;
    unsigned char i;

    /* Once a row is not enough. Forty cells of C on a 7501 take longer than
    ** the gap between two bytes, and how much longer is not something to
    ** estimate - so the line is checked every eighth cell, which bounds the
    ** wait whatever the compiler makes of this loop. */
    for (i = 0; i < SCREEN_W; ++i) {
        if ((i & 7) == 0) {
            serial_poll();
        }
        SCREEN[at + i] = reverse ? (0x20 | REVERSED) : 0x20;
        COLOUR[at + i] = pen;
    }
}

static unsigned char put_text(unsigned char x, unsigned char row,
                              const char *text, unsigned char reverse)
{
    unsigned int at = (unsigned int)row * SCREEN_W;

    while (*text != '\0' && x < SCREEN_W) {
        unsigned char here = (unsigned char)*text;
        unsigned char next = (unsigned char)text[1];
        unsigned char colour = pen;

        if ((x & 7) == 0) {
            serial_poll();
        }

        /* A card takes its own colour, all of it: the suit byte, and the
        ** rank standing in front of it. Otherwise a line drawn in yellow
        ** gives a yellow ten with a red diamond after it, which is not what
        ** a card looks like. */
        if (here >= 1 && here <= 4) {
            colour = here <= 2 ? RED : WHITE;
        } else if (next >= 1 && next <= 4) {
            colour = next <= 2 ? RED : WHITE;
        }

        SCREEN[at + x] = screen_code(here) | reverse;
        COLOUR[at + x] = colour;
        ++text;
        ++x;
    }
    return x;
}

static unsigned char put_chars(unsigned char x, unsigned char row,
                               const unsigned char *text, unsigned char length)
{
    unsigned int at = (unsigned int)row * SCREEN_W;

    while (length > 0 && x < SCREEN_W) {
        if ((x & 7) == 0) {
            serial_poll();
        }
        SCREEN[at + x] = screen_code(*text);
        COLOUR[at + x] = pen;
        ++text;
        ++x;
        --length;
    }
    return x;
}

/*
 * Numbers without printf: cc65's formatter is built on repeated division,
 * and nothing here needs more than an unsigned int in a few columns.
 */
static unsigned char put_uint(unsigned char x, unsigned char row,
                              unsigned int value, unsigned char width,
                              unsigned char reverse)
{
    unsigned char digits[5];
    unsigned char count = 0;
    unsigned int at = (unsigned int)row * SCREEN_W;

    do {
        digits[count++] = (unsigned char)('0' + (value % 10));
        value /= 10;
    } while (value != 0 && count < sizeof(digits));

    while (width > count && x < SCREEN_W) {
        SCREEN[at + x] = 0x20 | reverse;
        COLOUR[at + x] = pen;
        ++x;
        --width;
    }
    while (count > 0 && x < SCREEN_W) {
        SCREEN[at + x] = digits[--count] | reverse;
        COLOUR[at + x] = pen;
        ++x;
    }
    return x;
}

/*
 * Money does not fit in an int. PokerTH counts chips in 32 bits and a stack
 * that grows all evening would overflow a 16 bit one, so the arithmetic is
 * long here - slow on a 7501, but it happens only when something changes on
 * screen.
 */
static unsigned char put_ulong(unsigned char x, unsigned char row,
                               unsigned long value, unsigned char width)
{
    unsigned char digits[10];
    unsigned char count = 0;
    unsigned int at = (unsigned int)row * SCREEN_W;

    do {
        serial_poll();          /* a 32 bit division costs more than a byte */
        digits[count++] = (unsigned char)('0' + (unsigned char)(value % 10));
        value /= 10;
    } while (value != 0 && count < sizeof(digits));

    /* Too wide for its column means the value is nonsense - a byte went
    ** missing somewhere. Better a row of hashes than digits spilling into
    ** the next field and looking like data. */
    if (count > width && width > 0) {
        while (width > 0 && x < SCREEN_W) {
            SCREEN[at + x] = screen_code('#');
            COLOUR[at + x] = pen;
            ++x;
            --width;
        }
        return x;
    }

    while (width > count && x < SCREEN_W) {
        SCREEN[at + x] = 0x20;
        COLOUR[at + x] = pen;
        ++x;
        --width;
    }
    while (count > 0 && x < SCREEN_W) {
        SCREEN[at + x] = digits[--count];
        COLOUR[at + x] = pen;
        ++x;
    }
    return x;
}

/*
 * A card is a number from 0 to 51: the rank is the code modulo 13 counting 2
 * up to ace, and the suit is the code divided by 13 in the order diamonds,
 * hearts, spades, clubs. The suits are letters for now and the two red ones
 * are drawn in red, which costs nothing because the colour cell is written
 * anyway.
 */
/* Every card two characters wide, ten written as t the way a hand history
** does - which is what lets five of them fit across the table. */
static const char *const RANKS[13] = {
    "2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "A"
};
/* The suits are characters of our own now; see install_charset. */

static unsigned char put_card(unsigned char x, unsigned char row,
                              unsigned char code)
{
    unsigned int at = (unsigned int)row * SCREEN_W;
    unsigned char suit;
    unsigned char colour;
    const char *rank;

    if (code > 51) {
        return put_text(x, row, "--", 0);
    }
    suit = code / 13;
    rank = RANKS[code % 13];
    colour = (suit < 2) ? RED : pen;

    while (*rank != '\0' && x < SCREEN_W) {
        SCREEN[at + x] = screen_code((unsigned char)*rank);
        COLOUR[at + x] = colour;
        ++rank;
        ++x;
    }
    if (x < SCREEN_W) {
        SCREEN[at + x] = SUIT_GLYPH + suit;
        COLOUR[at + x] = colour;
        ++x;
    }
    return x;
}

static void draw_header(void)
{
    unsigned char x;

    clear_row(ROW_HEADER, 1);
    x = put_text(1, ROW_HEADER, "pokerth ", REVERSED);
    put_text(x, ROW_HEADER, server, REVERSED);
    x = put_uint(28, ROW_HEADER, players_online, 3, REVERSED);
    x = put_text(x, ROW_HEADER, " on", REVERSED);
    /* Bytes the ACIA dropped because we were too slow to collect them. It
    ** belongs on screen: it is the number that says whether this machine is
    ** keeping up, and it should stay at nought. */
    if (overruns != 0) {
        x = put_text(x + 1, ROW_HEADER, "!", REVERSED);
        put_uint(x, ROW_HEADER, overruns, 1, REVERSED);
    }
    header_dirty = 0;
}

static void draw_games(void)
{
    unsigned char i;
    unsigned char x;
    unsigned char flags;

    for (i = 0; i < GAME_ROWS; ++i) {
        serial_poll();   /* a row takes longer than a byte does */
        clear_row(ROW_GAMES + i, 0);
        if (i >= game_count) {
            continue;
        }
        flags = games[i].flags;
        x = put_uint(0, ROW_GAMES + i, games[i].id, 2, 0);
        ++x;
        x = put_chars(x, ROW_GAMES + i,
                      (const unsigned char *)(flags & GAME_RANKING ? "r" :
                                              (flags & GAME_PRIVATE ? "p" : " ")), 1);
        x = put_chars(x, ROW_GAMES + i,
                      (const unsigned char *)(flags & GAME_STARTED ? "*" : " "), 1);
        ++x;
        put_text(x, ROW_GAMES + i, games[i].name, 0);
        x = put_uint(33, ROW_GAMES + i, games[i].players, 2, 0);
        x = put_text(x, ROW_GAMES + i, "/", 0);
        put_uint(x, ROW_GAMES + i, games[i].seats, 2, 0);
    }
    if (game_count == 0) {
        put_text(0, ROW_GAMES, "no games on this server", 0);
    }
    games_dirty = 0;
}

/*
 * The table, as a table.
 *
 * Ten places around an oval, our own at the bottom where a player sits, the
 * board and the pot on the felt between them. The felt is nothing but
 * reversed spaces in green: a character cell has one colour and the
 * background belongs to the whole screen, so a solid shape can only be made
 * of reversed characters - which is exactly what is wanted here.
 *
 * State is colour rather than punctuation, there being no room for symbols:
 * our own seat is cyan, a folded one goes grey, all in is yellow, and whose
 * turn it is shows as the name in reverse. Only the dealer keeps a letter.
 *
 * Drawing stays a row at a time: each seat carries a bit saying whether it
 * has changed, and repainting all ten for every pot update both flickers and
 * costs the milliseconds in which the next byte arrives.
 */
#define FELT_TOP   3
#define FELT_ROWS  7
#define ROW_YOU   12

static const unsigned char felt_left[FELT_ROWS]  = { 12, 10,  9,  9,  9, 10, 12 };
static const unsigned char felt_right[FELT_ROWS] = { 27, 29, 30, 30, 30, 29, 27 };
static const unsigned char felt_solid[FELT_ROWS] = {  1,  0,  0,  0,  0,  0,  1 };

/* The ten places, starting at the bottom middle and going round. Twelve
** columns above and below, nine at the sides where the felt leaves less. */
static const unsigned char place_x[MAX_SEATS] = { 14,  1,  0,  0,  1, 14, 27, 31, 31, 27 };
static const unsigned char place_y[MAX_SEATS] = { 10, 10,  7,  4,  1,  1,  1,  4,  7, 10 };
static const unsigned char place_w[MAX_SEATS] = { 12, 12,  9,  9, 12, 12, 12,  9,  9, 12 };

static void blank(unsigned char x, unsigned char row, unsigned char width)
{
    unsigned int at = (unsigned int)row * SCREEN_W;

    while (width > 0 && x < SCREEN_W) {
        if ((x & 7) == 0) {
            serial_poll();
        }
        SCREEN[at + x] = 0x20;
        COLOUR[at + x] = pen;
        ++x;
        --width;
    }
}

static void fill(unsigned char x, unsigned char row, unsigned char last)
{
    unsigned int at = (unsigned int)row * SCREEN_W;

    while (x <= last && x < SCREEN_W) {
        if ((x & 7) == 0) {
            serial_poll();
        }
        SCREEN[at + x] = 0x20 | REVERSED;
        COLOUR[at + x] = GREEN;
        ++x;
    }
}

/* Where a seat sits on screen: our own at the bottom, the rest in order
** round the table from there. */
static unsigned char place_of(unsigned char number)
{
    if (my_seat >= MAX_SEATS) {
        return number;
    }
    return (unsigned char)((number + MAX_SEATS - my_seat) % MAX_SEATS);
}

static void draw_felt(void)
{
    unsigned char r;
    unsigned char row;
    unsigned char x;

    for (r = 0; r < FELT_ROWS; ++r) {
        row = FELT_TOP + r;
        serial_poll();
        pen = WHITE;
        blank(felt_left[r], row, felt_right[r] - felt_left[r] + 1);
        if (felt_solid[r]) {
            fill(felt_left[r], row, felt_right[r]);
        } else {
            fill(felt_left[r], row, felt_left[r] + 1);
            fill(felt_right[r] - 1, row, felt_right[r]);
        }
    }

    /* The board, on the felt. Five cards of two characters and the gaps
    ** between them come to fourteen, centred in what the felt leaves. */
    pen = WHITE;
    x = 13;
    if (board_count == 0) {
        put_text(x, FELT_TOP + 2, "-- -- -- -- --", 0);
    } else {
        for (r = 0; r < board_count; ++r) {
            x = put_card(x, FELT_TOP + 2, board[r]) + 1;
        }
        while (r < 5) {
            x = put_text(x, FELT_TOP + 2, "--", 0) + 1;
            ++r;
        }
    }

    x = put_text(15, FELT_TOP + 4, "pot ", 0);
    put_ulong(x, FELT_TOP + 4, pot, 0);
}

static void draw_table_head(void)
{
    unsigned char x;

    pen = WHITE;
    clear_row(ROW_HEADER, 1);
    x = put_text(1, ROW_HEADER, "pokerth ", REVERSED);
    put_text(x, ROW_HEADER, table_name, REVERSED);
    if (overruns != 0) {
        put_text(SCREEN_W - 1, ROW_HEADER, "!", REVERSED);
    }

    /* Our own two cards and what is left of our money, under our seat. */
    clear_row(ROW_YOU, 0);
    x = put_text(14, ROW_YOU, "", 0);
    x = put_card(14, ROW_YOU, my_cards[0]);
    x = put_card(x + 1, ROW_YOU, my_cards[1]);
    put_ulong(x + 2, ROW_YOU, my_money, 0);

    draw_felt();
    table_head_dirty = 0;
    header_dirty = 0;
}

/* How many columns a number will want, so that it can be left out when
** there are not that many. */
static unsigned char digits_of(unsigned long value)
{
    unsigned char n = 1;

    while (value >= 10) {
        value /= 10;
        ++n;
    }
    return n;
}

static void draw_seat(unsigned char i)
{
    char shown[SEAT_NAME_LEN + 1];
    unsigned char n;
    unsigned char place = place_of(i);
    unsigned char x = place_x[place];
    unsigned char y = place_y[place];
    unsigned char width = place_w[place];
    unsigned char flags = seats[i].flags;
    unsigned char reverse = 0;
    unsigned char at;

    pen = WHITE;
    blank(x, y, width);
    blank(x, y + 1, width);
    if (i >= seat_count || !(flags & SEAT_TAKEN)) {
        return;
    }

    if (flags & SEAT_FOLDED) {
        pen = GREY;
    } else if (flags & SEAT_ALL_IN) {
        pen = YELLOW;
    } else if (flags & SEAT_YOU) {
        pen = CYAN;
    }
    if (i == turn_seat) {
        reverse = REVERSED;         /* whose turn it is, without a symbol */
    }

    /* The name, cut to the place rather than to the twelve characters the
    ** protocol allows - the places at the sides are nine wide, and the felt
    ** starts where they end. */
    n = (flags & SEAT_DEALER) ? width - 2 : width;
    for (at = 0; at < n && seats[i].name[at] != '\0'; ++at) {
        shown[at] = seats[i].name[at];
    }
    shown[at] = '\0';
    at = put_text(x, y, shown, reverse);
    if (flags & SEAT_DEALER) {
        put_text(at + 1, y, "d", 0);
    }

    /*
     * Money, and what is in front of them - but never past the place they
     * sit in. The places at the sides are nine columns wide and the felt
     * begins immediately after, so anything written beyond that lands on the
     * table and stays there: only the place itself is wiped before drawing.
     * Where there is no room for both, the cards win, a showdown being the
     * moment they matter.
     */
    if (seats[i].cards[0] <= 51 && width < 12) {
        at = put_card(x, y + 1, seats[i].cards[0]);
        put_card(at + 1, y + 1, seats[i].cards[1]);
    } else {
        at = put_ulong(x, y + 1, seats[i].money, 0);
        if (seats[i].cards[0] <= 51) {
            if (at + 6 <= x + width) {
                at = put_card(at + 1, y + 1, seats[i].cards[0]);
                put_card(at + 1, y + 1, seats[i].cards[1]);
            }
        } else if (seats[i].bet != 0
                   && at + 1 + digits_of(seats[i].bet) <= x + width) {
            put_ulong(at + 1, y + 1, seats[i].bet, 0);
        }
    }
    pen = WHITE;
}

static void draw_table(void)
{
    unsigned char i;

    if (table_head_dirty) {
        draw_table_head();
    }
    for (i = 0; i < MAX_SEATS; ++i) {
        if (seat_dirty & (1U << i)) {
            seat_dirty &= ~(1U << i);
            draw_seat(i);
        }
    }
    table_dirty = 0;
}

static void draw_chat(void)
{
    unsigned char i;
    unsigned char line;

    for (i = 0; i < CHAT_ROWS; ++i) {
        serial_poll();   /* a row takes longer than a byte does */
        clear_row(ROW_CHAT + i, 0);
        if (i < chat_used) {
            line = (chat_first + i) % CHAT_ROWS;
            put_text(0, ROW_CHAT + i, chat[line], 0);
        }
    }
    chat_dirty = 0;
}

/*
 * The start screen.
 *
 * The logo is drawn from the upper half of the character set, which is only
 * ours while the TED's inversion is switched off - so nothing on this screen
 * uses reverse video, and the fields are marked out with brackets instead.
 */
static void draw_login(void)
{
    unsigned char row;
    unsigned char column;
    unsigned char x;
    unsigned char i;

    pen = WHITE;
    for (row = 0; row < LOGO_CELLS; ++row) {
        serial_poll();
        for (column = 0; column < LOGO_CELLS; ++column) {
            SCREEN[(unsigned int)(ROW_LOGO + row) * SCREEN_W
                   + (SCREEN_W - LOGO_CELLS) / 2 + column] = LOGO_MAP[row][column];
            COLOUR[(unsigned int)(ROW_LOGO + row) * SCREEN_W
                   + (SCREEN_W - LOGO_CELLS) / 2 + column] = WHITE;
        }
    }

    clear_row(ROW_NAME, 0);
    put_text(2, ROW_NAME, "name", 0);
    x = put_text(LOGIN_COLUMN, ROW_NAME, "[", 0);
    x = put_text(x, ROW_NAME, login_name, 0);
    blank(x, ROW_NAME, LOGIN_COLUMN + 1 + LOGIN_LEN - x);
    put_text(LOGIN_COLUMN + 1 + LOGIN_LEN, ROW_NAME, "]", 0);

    clear_row(ROW_PASSWORD, 0);
    put_text(2, ROW_PASSWORD, "password", 0);
    put_text(LOGIN_COLUMN, ROW_PASSWORD, "[", 0);
    for (i = 0; i < LOGIN_LEN; ++i) {
        SCREEN[(unsigned int)ROW_PASSWORD * SCREEN_W + LOGIN_COLUMN + 1 + i] =
            i < login_password_len ? screen_code('*') : 0x20;
        COLOUR[(unsigned int)ROW_PASSWORD * SCREEN_W + LOGIN_COLUMN + 1 + i] = WHITE;
    }
    put_text(LOGIN_COLUMN + 1 + LOGIN_LEN, ROW_PASSWORD, "]", 0);

    /* Where the next character will land. */
    row = login_field == 0 ? ROW_NAME : ROW_PASSWORD;
    x = LOGIN_COLUMN + 1
        + (login_field == 0 ? login_name_len : login_password_len);
    if (x <= LOGIN_COLUMN + LOGIN_LEN) {
        SCREEN[(unsigned int)row * SCREEN_W + x] = screen_code('_');
        COLOUR[(unsigned int)row * SCREEN_W + x] = CYAN;
    }

    clear_row(ROW_PASSWORD + 2, 0);
    put_text(2, ROW_PASSWORD + 2,
             login_field == 0 ? "return goes to the password"
                              : "return connects", 0);
    login_dirty = 0;
}

static void draw_announce(void)
{
    pen = YELLOW;
    clear_row(ROW_ANNOUNCE, 0);
    put_text(0, ROW_ANNOUNCE, announce, 0);
    pen = WHITE;
    announce_dirty = 0;
}

static void draw_status(void)
{
    clear_row(ROW_INPUT - 1, 0);
    put_text(0, ROW_INPUT - 1, status, 0);
    status_dirty = 0;
}

static void draw_input(void)
{
    unsigned char x;

    clear_row(ROW_INPUT, 0);
    /* With something to answer, the keys matter more than the chat line. */
    if (view == VIEW_TABLE && may != 0 && input_len == 0) {
        x = 0;
        if (may & MAY_FOLD) {
            x = put_text(x, ROW_INPUT, "f1 fold  ", 0);
        }
        if (may & MAY_CHECK) {
            x = put_text(x, ROW_INPUT, "f2 check  ", 0);
        } else if (may & MAY_CALL) {
            x = put_text(x, ROW_INPUT, "f2 call ", 0);
            x = put_ulong(x, ROW_INPUT, to_call, 0);
            x += 2;
        }
        if (may & (MAY_BET | MAY_RAISE)) {
            x = put_text(x, ROW_INPUT, "f3 +", 0);
            x = put_ulong(x, ROW_INPUT, min_raise, 0);
            x += 2;
        }
        if (may & MAY_ALL_IN) {
            put_text(x, ROW_INPUT, "f4 all in", 0);
        }
        input_dirty = 0;
        return;
    }
    x = put_text(0, ROW_INPUT, ">", 0);
    input[input_len] = '\0';
    x = put_text(x, ROW_INPUT, input, 0);
    /* A block where the next character will land, so the machine looks awake. */
    if (x < SCREEN_W) {
        SCREEN[(unsigned int)ROW_INPUT * SCREEN_W + x] = 0x20 | REVERSED;
        COLOUR[(unsigned int)ROW_INPUT * SCREEN_W + x] = pen;
    }
    input_dirty = 0;
}

static void set_status(const char *text)
{
    unsigned char i = 0;

    while (text[i] != '\0' && i < SCREEN_W) {
        status[i] = text[i];
        ++i;
    }
    status[i] = '\0';
    status_dirty = 1;
}

static void add_chat(const char *text, unsigned char length)
{
    unsigned char line;
    unsigned char i;

    if (chat_used < CHAT_ROWS) {
        line = chat_used++;
    } else {
        line = chat_first;
        chat_first = (chat_first + 1) % CHAT_ROWS;
    }
    if (length > CHAT_LEN) {
        length = CHAT_LEN;
    }
    for (i = 0; i < length; ++i) {
        chat[line][i] = text[i];
    }
    chat[line][length] = '\0';
    chat_dirty = 1;
}

/* ---------------------------------------------------------------- records */

static unsigned char frame_type;
static unsigned char frame_want;
static unsigned char frame_have;
static unsigned char frame[255];
static unsigned char frame_state = 0;   /* 0 type, 1 length, 2 payload */

/* Four bytes of a record, little endian, as the money and the amounts come. */
static unsigned long read_long(unsigned char at)
{
    return (unsigned long)frame[at]
           | ((unsigned long)frame[at + 1] << 8)
           | ((unsigned long)frame[at + 2] << 16)
           | ((unsigned long)frame[at + 3] << 24);
}

static struct game *find_game(unsigned int id)
{
    unsigned char i;

    for (i = 0; i < game_count; ++i) {
        if (games[i].id == id) {
            return &games[i];
        }
    }
    return 0;
}

static void game_add(void)
{
    struct game *slot;
    unsigned int id = frame[0] | ((unsigned int)frame[1] << 8);
    unsigned char length = frame_want > 5 ? frame_want - 5 : 0;
    unsigned char i;

    slot = find_game(id);
    if (slot == 0) {
        if (game_count >= MAX_GAMES) {
            return;                 /* the screen is full; the rest can wait */
        }
        slot = &games[game_count++];
    }
    slot->id = id;
    slot->flags = frame[2];
    slot->players = frame[3];
    slot->seats = frame[4];
    if (length > NAME_LEN) {
        length = NAME_LEN;
    }
    for (i = 0; i < length; ++i) {
        slot->name[i] = (char)frame[5 + i];
    }
    slot->name[length] = '\0';
    games_dirty = 1;
}

static void game_remove(void)
{
    unsigned int id = frame[0] | ((unsigned int)frame[1] << 8);
    unsigned char i;

    for (i = 0; i < game_count; ++i) {
        if (games[i].id == id) {
            while (i + 1 < game_count) {
                games[i] = games[i + 1];
                ++i;
            }
            --game_count;
            games_dirty = 1;
            return;
        }
    }
}

static void chat_record(void)
{
    /* kind(1), name length(1), name, text - rendered as "name: text", or as
    ** it stands when there is no name, which is how the proxy announces a
    ** winner. Those go on their own line rather than into the chat. */
    unsigned char name_len = frame[1];
    unsigned char i;
    unsigned char out_i = 0;
    char line[CHAT_LEN + 1];

    if (name_len > frame_want - 2) {
        name_len = frame_want - 2;
    }
    if (name_len == 0) {
        unsigned char length = frame_want - 2;

        if (length > SCREEN_W) {
            length = SCREEN_W;
        }
        for (i = 0; i < length; ++i) {
            announce[i] = (char)frame[2 + i];
        }
        announce[length] = '\0';
        announce_dirty = 1;
        return;
    }
    for (i = 0; i < name_len && out_i < CHAT_LEN; ++i) {
        line[out_i++] = (char)frame[2 + i];
    }
    /* A line with no name in front of it is written as it stands - which is
    ** how the proxy says who won a hand. */
    if (name_len > 0) {
        if (out_i < CHAT_LEN) {
            line[out_i++] = ':';
        }
        if (out_i < CHAT_LEN) {
            line[out_i++] = ' ';
        }
    }
    for (i = 2 + name_len; i < frame_want && out_i < CHAT_LEN; ++i) {
        line[out_i++] = (char)frame[i];
    }
    add_chat(line, out_i);
}

static void handle_frame(void)
{
    struct game *slot;

    switch (frame_type) {
    case D_HELLO:
        {
            unsigned char i;
            unsigned char length = frame_want > 1 ? frame_want - 1 : 0;

            if (length > sizeof(server) - 1) {
                length = sizeof(server) - 1;
            }
            for (i = 0; i < length; ++i) {
                server[i] = (char)frame[1 + i];
            }
            server[length] = '\0';
            header_dirty = 1;
            if (frame[0] != PROTOCOL_VERSION) {
                set_status("the proxy speaks another version");
            }
        }
        break;

    case D_STATE:
        switch (frame[0]) {
        case STATE_CONNECTING: set_status("connecting"); break;
        case STATE_LOBBY:
            set_status("in the lobby");
            if (view != VIEW_LOBBY) {
                view = VIEW_LOBBY;
                view_dirty = 1;
            }
            break;
        case STATE_TABLE:      set_status("at a table"); break;
        case STATE_ERROR:      set_status("error"); break;
        default:               set_status("offline"); break;
        }
        if (frame_want > 1) {
            unsigned char i;
            unsigned char length = frame_want - 1;

            if (length > SCREEN_W) {
                length = SCREEN_W;
            }
            for (i = 0; i < length; ++i) {
                status[i] = (char)frame[1 + i];
            }
            status[length] = '\0';
            status_dirty = 1;
        }
        break;

    case D_NOTICE:
        {
            unsigned char i;
            unsigned char length = frame_want;

            if (length > SCREEN_W) {
                length = SCREEN_W;
            }
            for (i = 0; i < length; ++i) {
                status[i] = (char)frame[i];
            }
            status[length] = '\0';
            status_dirty = 1;
        }
        break;

    case D_GAME_CLEAR:
        game_count = 0;
        games_dirty = 1;
        break;

    case D_GAME_ADD:
        game_add();
        break;

    case D_GAME_UPDATE:
        slot = find_game(frame[0] | ((unsigned int)frame[1] << 8));
        if (slot != 0) {
            slot->flags = frame[2];
            slot->players = frame[3];
            games_dirty = 1;
        }
        break;

    case D_GAME_REMOVE:
        game_remove();
        break;

    case D_CHAT:
        chat_record();
        break;

    case D_PLAYERS:
        players_online = frame[0] | ((unsigned int)frame[1] << 8);
        header_dirty = 1;
        break;

    /* ------------------------------------------------------------ table */

    case D_TABLE:
        {
            /* id(2), seats(1), my seat(1), name. It arrives twice: once on
            ** sitting down, and again once the seats have been handed out,
            ** because only then is it known which one is ours. */
            unsigned char length = frame_want > 4 ? (unsigned char)(frame_want - 4) : 0;
            unsigned char i;

            seat_count = frame[2] > MAX_SEATS ? MAX_SEATS : frame[2];
            my_seat = frame[3];
            if (length > NAME_LEN) {
                length = NAME_LEN;
            }
            for (i = 0; i < length; ++i) {
                table_name[i] = (char)frame[4 + i];
            }
            table_name[length] = '\0';
            if (view != VIEW_TABLE) {
                view = VIEW_TABLE;
                view_dirty = 1;
            }
            table_head_dirty = 1;
            seat_dirty = 0x03FF;
            table_dirty = 1;
        }
        break;

    case D_SEAT:
        {
            /* seat(1), flags(1), money(4), name */
            unsigned char n = frame[0];
            unsigned char length = frame_want > 6 ? (unsigned char)(frame_want - 6) : 0;
            unsigned char i;

            if (n < MAX_SEATS) {
                seats[n].flags = frame[1];
                seats[n].money = read_long(2);
                seats[n].bet = 0;
                seats[n].cards[0] = CARD_NONE;
                seats[n].cards[1] = CARD_NONE;
                if (length > SEAT_NAME_LEN) {
                    length = SEAT_NAME_LEN;
                }
                for (i = 0; i < length; ++i) {
                    seats[n].name[i] = (char)frame[6 + i];
                }
                seats[n].name[length] = '\0';
                seat_dirty |= 1U << n;
                table_dirty = 1;
            }
        }
        break;

    case D_SEAT_BET:
        /* seat(1), flags(1), money(4), bet(4) */
        if (frame[0] < MAX_SEATS) {
            seats[frame[0]].flags = frame[1];
            seats[frame[0]].money = read_long(2);
            seats[frame[0]].bet = read_long(6);
            seat_dirty |= 1U << frame[0];
            table_dirty = 1;
        }
        break;

    case D_HAND:
        {
            /* hand(2), dealer seat(1), small blind(4), card(1), card(1) */
            unsigned char i;

            hand_number = frame[0] | ((unsigned int)frame[1] << 8);
            dealer_seat = frame[2];
            my_cards[0] = frame[7];
            my_cards[1] = frame[8];
            board_count = 0;
            pot = 0;
            for (i = 0; i < MAX_SEATS; ++i) {
                seats[i].bet = 0;
                seats[i].cards[0] = CARD_NONE;
                seats[i].cards[1] = CARD_NONE;
            }
            may = 0;
            table_head_dirty = 1;
            seat_dirty = 0x03FF;
            table_dirty = 1;
            input_dirty = 1;
        }
        break;

    case D_BOARD:
        {
            unsigned char i;

            board_count = frame[0] > 5 ? 5 : frame[0];
            for (i = 0; i < board_count; ++i) {
                board[i] = frame[1 + i];
            }
            table_head_dirty = 1;
            table_dirty = 1;
        }
        break;

    case D_POT:
        pot = read_long(0);
        table_head_dirty = 1;
        table_dirty = 1;
        break;

    case D_TURN:
        /* Both the seat that had the mark and the one that gets it. */
        if (turn_seat < MAX_SEATS) {
            seat_dirty |= 1U << turn_seat;
        }
        turn_seat = frame[0];
        if (turn_seat < MAX_SEATS) {
            seat_dirty |= 1U << turn_seat;
        }
        table_dirty = 1;
        break;

    case D_ASK:
        /* allowed(1), to call(4), minimum raise(4), my money(4) */
        may = frame[0];
        to_call = read_long(1);
        min_raise = read_long(5);
        my_money = read_long(9);
        set_status("your turn");
        input_dirty = 1;
        break;

    case D_RESULT:
        /* seat(1), card(1), card(1), won(4), money(4) */
        if (frame[0] < MAX_SEATS) {
            seats[frame[0]].cards[0] = frame[1];
            seats[frame[0]].cards[1] = frame[2];
            seats[frame[0]].money = read_long(7);
            seat_dirty |= 1U << frame[0];
            table_dirty = 1;
        }
        break;

    case D_TABLE_END:
        view = VIEW_LOBBY;
        view_dirty = 1;
        may = 0;
        switch (frame[0]) {
        case 1:  set_status("the game is over"); break;
        case 2:  set_status("removed from the table"); break;
        case 3:  set_status("could not join"); break;
        default: set_status("left the table"); break;
        }
        break;

    default:
        break;                      /* a record from a later stage: ignore */
    }
}

/*
 * Getting back in step.
 *
 * There is no sync mark in the protocol and no checksum: it was written for
 * a transport that delivers bytes or nothing. A byte does go missing now and
 * then, and the damage is out of all proportion - the next byte is read as a
 * type, the one after as a length, and the parser settles down to wait for a
 * payload that will never arrive. Everything stops, quietly.
 *
 * So a frame that stays unfinished while nothing arrives is abandoned, and
 * the proxy is greeted again. A HELLO means "forget what you sent me" at
 * that end, so the whole lobby comes back and the hiccup costs a redraw
 * instead of the session.
 */
#define PATIENCE 2000           /* turns of the loop, roughly a second */

static unsigned int waited = 0;
static unsigned char want_hello = 0;
static unsigned char discarding = 0;

/*
 * Drawing waits until the line goes quiet.
 *
 * This is the answer to a burst. When a hand starts, a table arrives as a
 * dozen records back to back, and repainting after each one spends exactly
 * the milliseconds in which the next byte turns up - so bytes were lost and
 * a name came out as "oppera". Taking the record costs almost nothing; it is
 * the painting that is slow. So the burst is taken in whole, and the screen
 * is brought up to date once, afterwards. Nothing is lost by waiting: the
 * intermediate states were never worth seeing.
 */
#define QUIET_ENOUGH 400        /* turns of the loop with nothing arriving */

static unsigned int quiet = 0;


/*
 * A type byte that is not a record is proof that the stream has slipped, and
 * waiting a second to find out is a second of nonsense on screen.
 */
static unsigned char known_record(unsigned char type)
{
    if (type >= D_TABLE && type <= D_TABLE_END) {
        return 1;
    }
    switch (type) {
    case D_HELLO:
    case D_STATE:
    case D_NOTICE:
    case D_GAME_CLEAR:
    case D_GAME_ADD:
    case D_GAME_UPDATE:
    case D_GAME_REMOVE:
    case D_CHAT:
    case D_PLAYERS:
        return 1;
    default:
        return 0;
    }
}

/*
 * Losing a byte used to be the start of a long argument rather than the end
 * of one. Asking for everything again while the rest of the old burst was
 * still arriving meant those bytes met a parser that had just been reset,
 * and threw it out of step immediately - a hundred greetings in one session,
 * each begetting the next.
 *
 * So what is still in flight is thrown away first. Everything is swallowed
 * until the line has been quiet for a moment, and only then is the proxy
 * asked to start again. One lost byte then costs one redraw.
 *
 * The greeting is asked for rather than sent from here for a second reason:
 * this runs inside serial_poll(), which is called from the middle of sending
 * as well, and a frame built while another is going out would trample it.
 */
static void resynchronise(void)
{
    frame_state = 0;
    frame_have = 0;
    acked = 0;
    waited = 0;
    discarding = 1;
    set_status("lost the thread - waiting for quiet");
}

static void feed(unsigned char byte)
{
    waited = 0;
    quiet = 0;

    /* Out of step: the rest of what is coming belongs to the old picture. */
    if (discarding) {
        return;
    }
    switch (frame_state) {
    case 0:
        if (!known_record(byte)) {
            resynchronise();
            break;
        }
        frame_type = byte;
        frame_state = 1;
        break;
    case 1:
        frame_want = byte;
        frame_have = 0;
        frame_state = frame_want == 0 ? 0 : 2;
        if (frame_state == 0) {
            handle_frame();
            acked += 2;
        }
        break;
    default:
        frame[frame_have++] = byte;
        if (frame_have == frame_want) {
            frame_state = 0;
            handle_frame();
            acked += 2 + frame_want;
        }
        break;
    }
}

/* ------------------------------------------------------------------- main */

/*
 * A line beginning with a slash is a command rather than something to say.
 * There are only two, because everything else at a table is a function key:
 * /j <number> sits down at a game from the list, /l gets up again.
 */
static void run_command(void)
{
    unsigned int value = 0;
    unsigned char i;

    if (input[1] == 'j') {
        for (i = 2; i < input_len; ++i) {
            if (input[i] >= '0' && input[i] <= '9') {
                value = value * 10 + (unsigned int)(input[i] - '0');
            }
        }
        if (value != 0) {
            send_join(value);
            set_status("sitting down");
        } else {
            set_status("which game? /j 1");
        }
    } else if (input[1] == 'l') {
        out_frame(U_LEAVE, 0);
        set_status("leaving the table");
    } else {
        set_status("/j <number> sits down, /l leaves");
    }
}

/*
 * The start screen takes the keyboard to itself: two fields and a return.
 *
 * Each field keeps its own length, and the earlier version copied the one
 * belonging to the field being left into the field being entered - so
 * pressing return after a five letter name gave a five character password of
 * nothing at all, and the server refused the login. The fields are edited
 * where they live now.
 */
static void login_edit(char *field, unsigned char *length, unsigned char key)
{
    if (key == CH_DEL) {
        if (*length > 0) {
            --(*length);
            field[*length] = '\0';
        }
    } else if (key >= ' ' && key != 127 && *length < LOGIN_LEN
               && !(key >= KEY_F1 && key <= KEY_RAW_F8)) {
        field[*length] = (char)key;
        ++(*length);
        field[*length] = '\0';
    }
}

static void handle_login_key(unsigned char key)
{
    if (key == CH_ENTER) {
        if (login_field == 0) {
            login_field = 1;
        } else {
            want_login = 1;
            set_status("connecting");
        }
    } else if (login_field == 0) {
        login_edit(login_name, &login_name_len, key);
    } else {
        login_edit(login_password, &login_password_len, key);
    }
    login_dirty = 1;
}

static void handle_key(unsigned char key)
{
    if (view == VIEW_LOGIN) {
        handle_login_key(key);
        return;
    }

    /* With something to answer, the function keys are the answer. They do
    ** nothing when it is not our turn, so a stray press cannot fold a hand. */
    if (view == VIEW_TABLE && may != 0) {
        if (key >= KEY_F1 && key <= KEY_RAW_F8) {
            switch (KEY_ACTION(key)) {
            case ACT_FOLD:
                if (may & MAY_FOLD) {
                    remember_action(ACTION_FOLD, 0);
                }
                return;
            case ACT_CALL:
                if (may & MAY_CHECK) {
                    remember_action(ACTION_CHECK, 0);
                } else if (may & MAY_CALL) {
                    remember_action(ACTION_CALL, to_call);
                }
                return;
            case ACT_RAISE:
                /* The bet is relative: what goes in on top of what is
                ** already in front of this seat. */
                if (may & MAY_RAISE) {
                    remember_action(ACTION_RAISE, to_call + min_raise);
                } else if (may & MAY_BET) {
                    remember_action(ACTION_BET, min_raise);
                }
                return;
            default:
                if (may & MAY_ALL_IN) {
                    remember_action(ACTION_ALLIN, my_money);
                }
                return;
            }
        }
    }

    if (view == VIEW_TABLE && key >= KEY_F1 && key <= KEY_RAW_F8 && may == 0) {
        set_status("not your turn");
        return;
    }
    if (key == CH_ENTER) {
        if (input_len > 0) {
            want_send = 1;
        }
    } else if (key == CH_DEL) {
        if (input_len > 0) {
            --input_len;
            input_dirty = 1;
        }
    } else if (key >= ' ' && key != 127 && input_len < INPUT_LEN
               && !(key >= KEY_F1 && key <= KEY_RAW_F8)) {
        input[input_len++] = (char)key;
        input_dirty = 1;
    }
}

int main(void)
{
    unsigned char byte;
    unsigned char saved_repeat;
    unsigned char i;

    /* Screen and colour memory cleared by hand, since conio is no longer
    ** linked in; the border and background registers are TED, not KERNAL. */
    for (i = 0; i < 25; ++i) {
        clear_row(i, 0);
    }
    *(unsigned char *)0xFF19 = 0;      /* border black */
    *(unsigned char *)0xFF15 = 0;      /* background black */

    serial_open();

    install_charset();
    /* Whatever the autostart was typing is still in the buffer, and the
    ** start screen would take it for a name - "aka" was the first thing it
    ** ever asked to log in as. */
    KEY_COUNT = 0;
    FKEY_PENDING = 0;
    saved_repeat = RPTFLG;
    RPTFLG = RPTFLG_NONE;
#if TAKE_FUNCTION_KEYS
    take_function_keys();
#endif

    set_status("who are you?");
    send_hello();

    for (;;) {
        serial_poll();

        /* Nothing arriving while a frame is half read means a byte was
        ** lost; sitting here for ever is the one outcome worth avoiding. */
        if (frame_state != 0 && ++waited > PATIENCE) {
            resynchronise();
        }

        out_pump();
        if (out_idle()) {
            /* What was asked for, in the order it matters: finding the
            ** thread again, then answering a turn before it times out, then
            ** what was typed, and the acknowledgement last - it is the only
            ** one that will still be true a moment later. */
            if (discarding && quiet >= QUIET_ENOUGH) {
                /* The line has been quiet: whatever was in flight is gone,
                ** and it is safe to start again. */
                discarding = 0;
                want_hello = 1;
            }
            if (want_hello) {
                want_hello = 0;
                send_hello();
            } else if (pending_action != 0) {
                send_action(pending_action - 1, pending_amount);
                pending_action = 0;
            } else if (want_login) {
                want_login = 0;
                send_login();
            } else if (want_send) {
                want_send = 0;
                if (input[0] == '/') {
                    run_command();
                } else {
                    send_chat();
                }
                input_len = 0;
                input_dirty = 1;
            } else if (acked > 0) {
                send_ack();
            }
        }

        /* The keyboard and the two cheap rows stay immediate - typing has to
        ** feel like typing. */
        byte = read_key();
        if (byte != 0) {
            if (byte == KEY_STOP && input_len == 0) {
                break;              /* run/stop leaves, on an empty line */
            }
            handle_key(byte);
        }
        if (status_dirty) draw_status();
        if (input_dirty && view != VIEW_LOGIN) draw_input();

        /* Everything else waits until nothing is arriving. Painting a table
        ** costs more than the gap between two bytes, so a burst is taken in
        ** whole and the screen brought up to date once, afterwards. */
        if (quiet < QUIET_ENOUGH) {
            ++quiet;
            continue;
        }

        if (view_dirty) {
            /* The other view owns the top half of the screen; wipe it and
            ** draw everything again. */
            for (i = 0; i < 25; ++i) {
                clear_row(i, 0);
            }
            /* The start screen wants the upper half of the character set for
            ** the logo; everything else wants the reverse video the TED
            ** makes from it. */
            if (view == VIEW_LOGIN) {
                TED_INVERT = TED_INVERT | 0x80;
            } else {
                TED_INVERT = TED_INVERT & 0x7F;
            }
            login_dirty = 1;
            header_dirty = 1;
            games_dirty = 1;
            table_dirty = 1;
            table_head_dirty = 1;
            seat_dirty = 0x03FF;
            chat_dirty = 1;
            announce_dirty = 1;
            status_dirty = 1;
            input_dirty = 1;
            view_dirty = 0;
        }
        if (view == VIEW_LOGIN) {
            if (login_dirty) draw_login();
        } else if (view == VIEW_TABLE) {
            if (table_dirty || header_dirty) draw_table();
        } else {
            if (header_dirty) draw_header();
            if (games_dirty)  draw_games();
        }
        /* Chat and the announcement sit in the same rows in both views that
        ** have them. */
        if (view != VIEW_LOGIN) {
            if (chat_dirty)     draw_chat();
            if (announce_dirty) draw_announce();
        }
    }

    RPTFLG = saved_repeat;
    restore_charset();
#if TAKE_FUNCTION_KEYS
    return_function_keys();
#endif
    serial_close();
    for (i = 0; i < 25; ++i) {
        clear_row(i, 0);
    }
    put_text(0, 0, "stopped", 0);
    return 0;
}
