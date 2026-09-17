/*
 * Does anything actually come out of this machine?
 *
 * Stage three of the PokerTH client, and the first line of it that runs on
 * the Plus/4. Before a protocol can be spoken there has to be a wire, so this
 * program does the smallest thing that proves one: it sends every byte value
 * from 0 to 255 out of the ACIA and echoes back whatever arrives.
 *
 * The ramp is the point. The proxy's records contain arbitrary bytes - a
 * length of 255, a game id, PETSCII - so we need to know that all 256 values
 * survive the trip in both directions. VICE reaches the outside world with
 * its IP232 protocol, which is not a plain byte pipe: it claims 0xFF for
 * itself and doubles it to mean a literal one. ../proxy/wirecheck.py is the
 * other end and checks the ramp arrives intact.
 *
 * The Plus/4 is the one 264 machine with a 6551 ACIA on board, at $FD00.
 * cc65 ships a driver for it, interrupt driven on receive, so this program
 * never touches the chip directly - plus4_stdser_ser does.
 */

#include <conio.h>
#include <plus4.h>
#include <serial.h>
#include <stdio.h>

#define RAMP_LENGTH 256

/* Room for a whole probe, so that the driver's buffer can always be emptied
** into it. The indices are unsigned char and the ring is 256 bytes, so they
** wrap by themselves. */
#define ECHO_RING 256
static unsigned char ring[ECHO_RING];

static const struct ser_params params = {
    /* 2400 baud is what a real Plus/4 on a serial WiFi modem can be relied
    ** on to do. The emulator does not care, and there is no point being
    ** faster here than the slowest link we mean to support. */
    SER_BAUD_2400,
    SER_BITS_8,
    SER_STOP_1,
    SER_PAR_NONE,
    /* Not a preference: SER_HS_HW is the only value the cc65 driver accepts.
    ** Anything else fails ser_open with SER_ERR_INIT_FAILED and no further
    ** explanation. It makes the driver raise and lower RTS as its 256 byte
    ** receive buffer fills - which is worth having on a real cable, but does
    ** not reach a proxy at the far end of a TCP socket. Hence the credit
    ** scheme in ../protocol.md. */
    SER_HS_HW
};

int main(void)
{
    unsigned char byte;
    unsigned char head = 0;
    unsigned char tail = 0;
    unsigned char err;
    unsigned int pending = 0;
    unsigned int ramp = 0;
    unsigned int received = 0;

    clrscr();
    cputs("plus/4 acia echo test\r\n\r\n");

    err = ser_install(plus4_stdser_ser);
    if (err != SER_ERR_OK) {
        cprintf("no serial driver, error %u\r\n", err);
        return 1;
    }
    err = ser_open(&params);
    if (err != SER_ERR_OK) {
        cprintf("cannot open the port, error %u\r\n", err);
        return 1;
    }

    cputs("sending 0..255 and echoing\r\n");
    cputs("press a key to stop\r\n");

    /*
     * Reading and writing share one loop, and reading may never wait for
     * writing. That is the whole lesson of this program, learned twice.
     *
     * The driver raises a Stopped flag when its own receive buffer runs low,
     * so that it can drop RTS and ask the other end to pause - and TryToSend
     * bails out while that flag is up. So a full receive buffer stops
     * transmission as well. The first attempt sent the ramp without reading
     * and deadlocked the moment the other end answered. The second read one
     * byte at a time but only after the previous echo had gone out, and
     * deadlocked just as thoroughly: the echo could not leave because the
     * receive buffer was full, and the receive buffer could not empty because
     * the program was waiting for the echo to leave. It stopped after seven
     * bytes, with the driver reporting nothing free.
     *
     * So bytes are taken out of the driver unconditionally, into a ring of
     * our own, and sent from there whenever the line happens to be willing.
     * Draining the driver is what clears its Stopped flag - at 63 bytes free
     * - which is what lets anything be sent at all.
     *
     * The proxy never relies on this working out: the credit scheme in
     * ../protocol.md exists so that the driver's buffer never fills in the
     * first place.
     */
    for (;;) {
        /* Always take what has arrived, whatever the sending side is doing. */
        if (pending < ECHO_RING && ser_get((char *)&byte) == SER_ERR_OK) {
            ring[tail++] = byte;        /* unsigned char, wraps with the ring */
            ++pending;
            ++received;
            if ((received & 0x3F) == 0) {
                gotoxy(0, 6);
                /* RecvFreeCnt is at a fixed address in the cc65 driver: how
                ** much room is left in its 256 byte receive buffer. Worth
                ** watching, because at zero it drops bytes silently. */
                cprintf("sent %u  recv %u  last $%02x  free %u  ",
                        ramp, received, byte, *(unsigned char *)0x07D3);
            }
        }

        /* Send what is waiting, but never wait for it. */
        if (pending > 0) {
            if (ser_put((char)ring[head]) != SER_ERR_OVERFLOW) {
                ++head;
                --pending;
            }
        } else if (ramp < RAMP_LENGTH) {
            if (ser_put((char)ramp) != SER_ERR_OVERFLOW) {
                ++ramp;
            }
        }

        if (kbhit()) {
            cgetc();
            break;
        }
    }

    ser_close();
    ser_uninstall();
    gotoxy(0, 8);
    cprintf("stopped: sent %u, received %u\r\n", ramp, received);
    return 0;
}
