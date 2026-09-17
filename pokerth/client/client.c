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
