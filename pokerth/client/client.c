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

#include <conio.h>
#include <plus4.h>
#include <serial.h>
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
    char name[SEAT_NAME_LEN + 1];
};

static struct seat seats[MAX_SEATS];
static unsigned char seat_count = 0;
static unsigned char my_seat = 0xFF;
static unsigned char turn_seat = 0xFF;
static unsigned char dealer_seat = 0xFF;
static unsigned char table_dirty = 1;

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

static char input[INPUT_LEN + 1];
static unsigned char input_len = 0;
static unsigned char input_dirty = 1;

/* ---------------------------------------------------------------- serial */

static const struct ser_params params = {
    SER_BAUD_2400,
    SER_BITS_8,
    SER_STOP_1,
    SER_PAR_NONE,
    SER_HS_HW           /* the only value the cc65 driver accepts */
};

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
        if (ser_put((char)out[out_pos]) == SER_ERR_OVERFLOW) {
            return;                 /* try again next time round, never wait */
        }
        ++out_pos;
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

    for (i = 0; i < SCREEN_W; ++i) {
        SCREEN[at + i] = reverse ? (0x20 | REVERSED) : 0x20;
        COLOUR[at + i] = WHITE;
    }
}

static unsigned char put_text(unsigned char x, unsigned char row,
                              const char *text, unsigned char reverse)
{
    unsigned int at = (unsigned int)row * SCREEN_W;

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
        digits[count++] = (unsigned char)('0' + (unsigned char)(value % 10));
        value /= 10;
    } while (value != 0 && count < sizeof(digits));

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
    x = put_uint(30, ROW_HEADER, players_online, 5, REVERSED);
    put_text(x, ROW_HEADER, " on", REVERSED);
    header_dirty = 0;
}

static void draw_games(void)
{
    unsigned char i;
    unsigned char x;
    unsigned char flags;

    for (i = 0; i < GAME_ROWS; ++i) {
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

static void draw_table(void)
{
    unsigned char i;
    unsigned char x;
    unsigned char flags;

    /* Header: the game, and the pot, which is the one number everybody at a
    ** table looks at first. */
    clear_row(ROW_HEADER, 1);
    x = put_text(1, ROW_HEADER, "pokerth ", REVERSED);
    put_text(x, ROW_HEADER, table_name, REVERSED);
    x = put_text(28, ROW_HEADER, "pot ", REVERSED);
    put_ulong(x, ROW_HEADER, pot, 7);

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

    for (i = 0; i < MAX_SEATS; ++i) {
        clear_row(ROW_SEATS + i, 0);
        if (i >= seat_count || !(seats[i].flags & SEAT_TAKEN)) {
            continue;
        }
        flags = seats[i].flags;
        put_uint(0, ROW_SEATS + i, i, 2, 0);
        put_text(3, ROW_SEATS + i, seats[i].name, 0);
        put_ulong(15, ROW_SEATS + i, seats[i].money, 8);
        if (seats[i].bet != 0) {
            put_ulong(24, ROW_SEATS + i, seats[i].bet, 6);
        }
        /* Four columns of marks, which is all a 40 column line can spare:
        ** the dealer, whose turn it is, and who is out of the hand. */
        x = 31;
        if (flags & SEAT_DEALER) {
            x = put_text(x, ROW_SEATS + i, "d", 0);
        }
        if (i == turn_seat) {
            x = put_text(x, ROW_SEATS + i, "<", 0);
        }
        if (flags & SEAT_FOLDED) {
            x = put_text(x, ROW_SEATS + i, "-", 0);
        }
        if (flags & SEAT_ALL_IN) {
            put_text(x, ROW_SEATS + i, "a", 0);
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
            x = put_text(x, ROW_INPUT, "f3 check  ", 0);
        } else if (may & MAY_CALL) {
            x = put_text(x, ROW_INPUT, "f3 call ", 0);
            x = put_ulong(x, ROW_INPUT, to_call, 1);
            x += 2;
        }
        if (may & (MAY_BET | MAY_RAISE)) {
            x = put_text(x, ROW_INPUT, "f5 +", 0);
            x = put_ulong(x, ROW_INPUT, min_raise, 1);
            x += 2;
        }
        if (may & MAY_ALL_IN) {
            put_text(x, ROW_INPUT, "f7 all in", 0);
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
        case STATE_LOBBY:      set_status("in the lobby"); break;
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

    default:
        break;                      /* a record from a later stage: ignore */
    }
}

static void feed(unsigned char byte)
{
    switch (frame_state) {
    case 0:
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

static void handle_key(unsigned char key)
{
    if (key == CH_ENTER) {
        if (input_len > 0 && out_idle()) {
            send_chat();
            input_len = 0;
            input_dirty = 1;
        }
    } else if (key == CH_DEL) {
        if (input_len > 0) {
            --input_len;
            input_dirty = 1;
        }
    } else if (key >= ' ' && key != 127 && input_len < INPUT_LEN) {
        input[input_len++] = (char)key;
        input_dirty = 1;
    }
}

int main(void)
{
    unsigned char byte;
    unsigned char err;
    unsigned char saved_repeat;

    clrscr();
    bordercolor(COLOR_BLACK);
    bgcolor(COLOR_BLACK);

    err = ser_install(plus4_stdser_ser);
    if (err != SER_ERR_OK) {
        put_uint(put_text(0, 0, "no serial driver, error ", 0), 0, err, 1, 0);
        return 1;
    }
    err = ser_open(&params);
    if (err != SER_ERR_OK) {
        put_uint(put_text(0, 0, "cannot open the port, error ", 0), 0, err, 1, 0);
        return 1;
    }

    saved_repeat = RPTFLG;
    RPTFLG = RPTFLG_NONE;

    clear_row(1, 0);
    clear_row(ROW_GAMES + GAME_ROWS + 1, 0);
    set_status("waiting for the proxy");
    send_hello();

    for (;;) {
        /* Always take what has arrived. A record may repaint half the
        ** screen, which is slow, but the proxy is never allowed more than
        ** RX_WINDOW bytes in flight, so nothing can pile up behind it. */
        while (ser_get((char *)&byte) == SER_ERR_OK) {
            feed(byte);
        }

        out_pump();
        if (out_idle() && acked > 0) {
            send_ack();
        }

        if (header_dirty) draw_header();
        if (games_dirty)  draw_games();
        if (chat_dirty)   draw_chat();
        if (status_dirty) draw_status();
        if (input_dirty)  draw_input();

        if (kbhit()) {
            byte = (unsigned char)cgetc();
            if (byte == CH_F8) {
                break;
            }
            handle_key(byte);
        }
    }

    out_frame(U_BYE, 0);
    out_pump();
    RPTFLG = saved_repeat;
    ser_close();
    ser_uninstall();
    clrscr();
    put_text(0, 0, "stopped", 0);
    return 0;
}
