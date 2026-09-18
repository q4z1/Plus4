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
#define CHAT_ROWS      8
#define ROW_INPUT     24

#define MAX_GAMES     GAME_ROWS

/* The table view, on the same 25 rows: header, board, our own cards, then a
** row per seat, then the chat, the status line and the keys. */
#define MAX_SEATS     10
#define ROW_BOARD      1
#define ROW_MINE       2
#define ROW_SEATS      4
#define SEAT_NAME_LEN 12

#define VIEW_LOBBY 0
#define VIEW_TABLE 1
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

static unsigned char view = VIEW_LOBBY;
static unsigned char view_dirty = 1;

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
#define SCREEN ((unsigned char *)0x0C00)
#define COLOUR ((unsigned char *)0x0800)
#define WHITE 0x71
#define RED   0x72
#define REVERSED 0x80

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

    /* Forty cells of C on a 7501 take longer than the 4 milliseconds between
    ** two bytes at 2400 baud, so the line is checked before every row rather
    ** than between them. */
    serial_poll();
    for (i = 0; i < SCREEN_W; ++i) {
        SCREEN[at + i] = reverse ? (0x20 | REVERSED) : 0x20;
        COLOUR[at + i] = WHITE;
    }
}

static unsigned char put_text(unsigned char x, unsigned char row,
                              const char *text, unsigned char reverse)
{
    unsigned int at = (unsigned int)row * SCREEN_W;

    serial_poll();
    while (*text != '\0' && x < SCREEN_W) {
        SCREEN[at + x] = screen_code((unsigned char)*text) | reverse;
        COLOUR[at + x] = WHITE;
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
        SCREEN[at + x] = screen_code(*text);
        COLOUR[at + x] = WHITE;
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
        COLOUR[at + x] = WHITE;
        ++x;
        --width;
    }
    while (count > 0 && x < SCREEN_W) {
        SCREEN[at + x] = digits[--count] | reverse;
        COLOUR[at + x] = WHITE;
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
            COLOUR[at + x] = WHITE;
            ++x;
            --width;
        }
        return x;
    }

    while (width > count && x < SCREEN_W) {
        SCREEN[at + x] = 0x20;
        COLOUR[at + x] = WHITE;
        ++x;
        --width;
    }
    while (count > 0 && x < SCREEN_W) {
        SCREEN[at + x] = digits[--count];
        COLOUR[at + x] = WHITE;
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
static const char *const RANKS[13] = {
    "2", "3", "4", "5", "6", "7", "8", "9", "10", "j", "q", "k", "a"
};
static const char SUITS[4] = { 'd', 'h', 's', 'c' };

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
    colour = (suit < 2) ? RED : WHITE;

    while (*rank != '\0' && x < SCREEN_W) {
        SCREEN[at + x] = screen_code((unsigned char)*rank);
        COLOUR[at + x] = colour;
        ++rank;
        ++x;
    }
    if (x < SCREEN_W) {
        SCREEN[at + x] = screen_code((unsigned char)SUITS[suit]);
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
 * The table is drawn a row at a time, not all at once.
 *
 * Every pot update used to repaint ten seats, which flickers and, worse,
 * spends the milliseconds in which the next byte arrives. So each seat
 * carries a bit saying whether it has changed, and only those rows are
 * touched.
 */
static void draw_table_head(void)
{
    unsigned char x;
    unsigned char i;

    clear_row(ROW_HEADER, 1);
    x = put_text(1, ROW_HEADER, "pokerth ", REVERSED);
    put_text(x, ROW_HEADER, table_name, REVERSED);
    x = put_text(28, ROW_HEADER, "pot", REVERSED);
    put_ulong(x, ROW_HEADER, pot, 8);
    if (overruns != 0) {
        put_text(SCREEN_W - 1, ROW_HEADER, "!", REVERSED);
    }

    clear_row(ROW_BOARD, 0);
    x = put_text(0, ROW_BOARD, "board  ", 0);
    if (board_count == 0) {
        put_text(x, ROW_BOARD, "--", 0);
    } else {
        for (i = 0; i < board_count; ++i) {
            x = put_card(x, ROW_BOARD, board[i]);
            ++x;
        }
    }

    clear_row(ROW_MINE, 0);
    x = put_text(0, ROW_MINE, "you    ", 0);
    x = put_card(x, ROW_MINE, my_cards[0]);
    ++x;
    put_card(x, ROW_MINE, my_cards[1]);
    put_ulong(22, ROW_MINE, my_money, 8);

    clear_row(ROW_MINE + 1, 0);
    table_head_dirty = 0;
    header_dirty = 0;
}

static void draw_seat(unsigned char i)
{
    unsigned char row = ROW_SEATS + i;
    unsigned char flags = seats[i].flags;
    unsigned char x;

    clear_row(row, 0);
    if (i >= seat_count || !(flags & SEAT_TAKEN)) {
        return;
    }

    put_uint(0, row, i, 2, 0);
    put_text(3, row, seats[i].name, 0);
    put_ulong(15, row, seats[i].money, 8);

    if (seats[i].cards[0] <= 51) {
        /* At a showdown the cards matter more than the bet did. */
        x = put_card(24, row, seats[i].cards[0]);
        put_card(x + 1, row, seats[i].cards[1]);
    } else if (seats[i].bet != 0) {
        put_ulong(24, row, seats[i].bet, 6);
    }

    /* Four columns of marks, which is all a 40 column line can spare: the
    ** dealer, whose turn it is, and who is out of the hand. */
    x = 31;
    if (flags & SEAT_DEALER) {
        x = put_text(x, row, "d", 0);
    }
    if (i == turn_seat) {
        x = put_text(x, row, "<", 0);
    }
    if (flags & SEAT_FOLDED) {
        x = put_text(x, row, "-", 0);
    }
    if (flags & SEAT_ALL_IN) {
        put_text(x, row, "a", 0);
    }
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
    clear_row(ROW_SEATS + MAX_SEATS, 0);
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
        COLOUR[(unsigned int)ROW_INPUT * SCREEN_W + x] = WHITE;
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
    /* kind(1), name length(1), name, text - rendered as "name: text". */
    unsigned char name_len = frame[1];
    unsigned char i;
    unsigned char out_i = 0;
    char line[CHAT_LEN + 1];

    if (name_len > frame_want - 2) {
        name_len = frame_want - 2;
    }
    for (i = 0; i < name_len && out_i < CHAT_LEN; ++i) {
        line[out_i++] = (char)frame[2 + i];
    }
    if (out_i < CHAT_LEN) {
        line[out_i++] = ':';
    }
    if (out_i < CHAT_LEN) {
        line[out_i++] = ' ';
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
 * The greeting is asked for rather than sent from here: this runs inside
 * serial_poll(), which is itself called from the middle of sending, and a
 * frame built while another is going out would trample it. The main loop
 * sends it when the line is free.
 */
static void resynchronise(void)
{
    frame_state = 0;
    frame_have = 0;
    acked = 0;
    waited = 0;
    want_hello = 1;
    set_status("lost the thread - asking again");
}

static void feed(unsigned char byte)
{
    waited = 0;
    quiet = 0;
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

static void handle_key(unsigned char key)
{
    /* With something to answer, the function keys are the answer. They do
    ** nothing when it is not our turn, so a stray press cannot fold a hand. */
    if (view == VIEW_TABLE && may != 0 && out_idle()) {
        if (key >= KEY_F1 && key <= KEY_RAW_F8) {
            switch (KEY_ACTION(key)) {
            case ACT_FOLD:
                if (may & MAY_FOLD) {
                    send_action(ACTION_FOLD, 0);
                }
                return;
            case ACT_CALL:
                if (may & MAY_CHECK) {
                    send_action(ACTION_CHECK, 0);
                } else if (may & MAY_CALL) {
                    send_action(ACTION_CALL, to_call);
                }
                return;
            case ACT_RAISE:
                /* The bet is relative: what goes in on top of what is
                ** already in front of this seat. */
                if (may & MAY_RAISE) {
                    send_action(ACTION_RAISE, to_call + min_raise);
                } else if (may & MAY_BET) {
                    send_action(ACTION_BET, min_raise);
                }
                return;
            default:
                if (may & MAY_ALL_IN) {
                    send_action(ACTION_ALLIN, my_money);
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
        if (input_len > 0 && out_idle()) {
            if (input[0] == '/') {
                run_command();
            } else {
                send_chat();
            }
            input_len = 0;
            input_dirty = 1;
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

    saved_repeat = RPTFLG;
    RPTFLG = RPTFLG_NONE;
#if TAKE_FUNCTION_KEYS
    take_function_keys();
#endif

    clear_row(1, 0);
    clear_row(ROW_GAMES + GAME_ROWS + 1, 0);
    set_status("waiting for the proxy");
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
            if (want_hello) {
                want_hello = 0;
                send_hello();
            } else if (acked > 0) {
                send_ack();
            }
        }

        /* The keyboard and the two cheap rows stay immediate - typing has to
        ** feel like typing. */
        byte = read_key();
        if (byte != 0) {
            if (byte == KEY_STOP) {
                break;              /* run/stop leaves */
            }
            handle_key(byte);
        }
        if (status_dirty) draw_status();
        if (input_dirty)  draw_input();

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
            header_dirty = 1;
            games_dirty = 1;
            table_dirty = 1;
            table_head_dirty = 1;
            seat_dirty = 0x03FF;
            chat_dirty = 1;
            status_dirty = 1;
            input_dirty = 1;
            view_dirty = 0;
        }
        if (view == VIEW_TABLE) {
            if (table_dirty || header_dirty) draw_table();
        } else {
            if (header_dirty) draw_header();
            if (games_dirty)  draw_games();
        }
        /* Chat sits in the same rows in both views. */
        if (chat_dirty) draw_chat();
    }

    RPTFLG = saved_repeat;
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
