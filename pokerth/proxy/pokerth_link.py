"""Transport to a PokerTH lobby server.

Two things sit between a TCP connection and the protobuf messages defined in
pokerth.proto, and both are small enough to spell out here:

TLS
    The lobby servers use self-signed certificates, so the usual CA based
    verification would reject exactly the certificate we want to talk to. The
    real client therefore sets verify_none and instead compares the SHA-256 of
    the server's SubjectPublicKeyInfo against a pinned value
    (pokerth/src/net/tlspinning.cpp). We do the same, with the same pin, so
    the connection is encrypted *and* authenticated.

Framing
    Every message is a PokerTHMessage, serialized and prefixed with its length
    as a 4-byte big-endian integer (pokerth/src/net/asiosendbuffer.cpp:425).
    A packet is never larger than MAX_PACKET_SIZE, which is 384 bytes - worth
    remembering, because it means no single message can ever overwhelm the
    Plus/4 end of the chain.

This module deliberately knows nothing about games, players or chat. It hands
out parsed messages and takes messages to send; making sense of them is the
job of the layer above.
"""

from __future__ import annotations

import base64
import hashlib
import os
import socket
import ssl
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "gen"))
import pokerth_pb2 as pb  # noqa: E402  (needs the path above)

# --- Protocol constants, mirrored from the PokerTH sources ------------------

# src/net/netpacket.h
NET_VERSION_MAJOR = 5
NET_VERSION_MINOR = 1
MAX_PACKET_SIZE = 384

# src/game_defs.h - the client type lives in the high byte of the build id.
CLIENT_TYPE_QT_WIDGET = 0x01
CLIENT_TYPE_QML = 0x02
CLIENT_TYPE_WEB = 0x03

DEFAULT_PORT = 7234


def make_build_id(client_type: int, major: int, minor: int, revision: int) -> int:
    """(clientType << 24) | (major << 16) | (minor << 8) | revision."""
    return (client_type << 24) | (major << 16) | (minor << 8) | revision


# The server rejects build ids whose client type it does not know
# (src/net/serverlobbythread.cpp, the else branch of the buildId check), so
# until it learns about a retro client we have to introduce ourselves as a
# client type it accepts.
DEFAULT_BUILD_ID = make_build_id(CLIENT_TYPE_QT_WIDGET, 2, 1, 9)

# src/net/tlspinning.cpp - base64 SHA-256 of the server's SubjectPublicKeyInfo.
BUILTIN_PINS = {
    "pthsrv.pokerth.net": "hnyHDGXvmDBFU7MN5xXuiq4OaWWrnHNzqhKlEoSuAV4=",
}


# --- Errors -----------------------------------------------------------------

class LinkError(Exception):
    """Anything that makes the connection unusable."""


class PinMismatch(LinkError):
    def __init__(self, expected: str, got: str):
        super().__init__(
            f"TLS pin mismatch: server presents {got}, expected {expected}"
        )
        self.expected = expected
        self.got = got


class ServerError(LinkError):
    """The server sent an ErrorMessage and will close the connection."""

    def __init__(self, reason: int):
        super().__init__(f"server rejected us: {error_reason_name(reason)}")
        self.reason = reason


# --- Message helpers --------------------------------------------------------

def kind_of(msg) -> str:
    """Message kind of a PokerTHMessage, e.g. "InitAckMessage"."""
    name = pb.PokerTHMessage.PokerTHMessageType.Name(msg.messageType)
    return name[len("Type_"):]


def payload_field(kind: str) -> str:
    """Wrapper field holding a given kind: InitMessage -> initMessage."""
    return kind[0].lower() + kind[1:]


def payload_of(msg):
    """The payload submessage of a PokerTHMessage, or None if it carries none."""
    field = payload_field(kind_of(msg))
    return getattr(msg, field) if msg.HasField(field) else None


def make(kind: str):
    """Build an empty PokerTHMessage of `kind`.

    Returns the wrapper and its payload submessage; fill in the payload and
    send the wrapper.
    """
    msg = pb.PokerTHMessage()
    msg.messageType = getattr(pb.PokerTHMessage, "Type_" + kind)
    return msg, getattr(msg, payload_field(kind))


def error_reason_name(reason: int) -> str:
    try:
        return pb.ErrorMessage.ErrorReason.Name(reason)
    except ValueError:
        return f"unknown reason {reason}"


def spki_pin(der_cert: bytes) -> str:
    """The pin of a DER certificate: base64(SHA-256(SubjectPublicKeyInfo)).

    Hashing the public key rather than the certificate means a renewal with
    the same key pair keeps the pin, and no host name has to match - the same
    reasoning as in tlspinning.h.
    """
    from cryptography import x509
    from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

    spki = x509.load_der_x509_certificate(der_cert).public_key().public_bytes(
        Encoding.DER, PublicFormat.SubjectPublicKeyInfo
    )
    return base64.b64encode(hashlib.sha256(spki).digest()).decode("ascii")


# --- The connection ---------------------------------------------------------

class Link:
    """A framed message connection to a PokerTH server.

    `pin` selects how the certificate is checked:
      "auto"   use the built-in pin for this host, unpinned if there is none
      None     do not check at all (encrypted but unauthenticated)
      "<b64>"  require exactly this pin
    """

    def __init__(self, host: str, port: int = DEFAULT_PORT, tls: bool = True,
                 pin: str | None = "auto", timeout: float = 20.0):
        self.host = host
        self.port = port
        self.tls = tls
        self.timeout = timeout
        self.expected_pin = BUILTIN_PINS.get(host.lower()) if pin == "auto" else pin
        self.peer_pin: str | None = None
        self._sock: socket.socket | None = None
        self._buf = b""

    # -- lifecycle --

    def connect(self) -> None:
        sock = socket.create_connection((self.host, self.port), self.timeout)
        if self.tls:
            # No CA verification, by design: trust comes from the pin below.
            ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
            sock = ctx.wrap_socket(sock, server_hostname=self.host)
            self.peer_pin = spki_pin(sock.getpeercert(binary_form=True))
            if self.expected_pin and self.peer_pin != self.expected_pin:
                sock.close()
                raise PinMismatch(self.expected_pin, self.peer_pin)
        self._sock = sock

    def close(self) -> None:
        if self._sock is not None:
            try:
                self._sock.close()
            finally:
                self._sock = None

    def set_timeout(self, timeout: float | None) -> None:
        """Change the receive timeout; None blocks forever.

        Once logged in, waiting forever is correct: the protocol has no ping
        and the server only enforces a timeout on the init handshake, so an
        idle session simply stays open.
        """
        self.timeout = timeout
        if self._sock is not None:
            self._sock.settimeout(timeout)

    def __enter__(self) -> "Link":
        self.connect()
        return self

    def __exit__(self, *exc) -> None:
        self.close()

    # -- messages --

    def send(self, msg) -> None:
        body = msg.SerializeToString()
        if len(body) > MAX_PACKET_SIZE:
            raise LinkError(
                f"{kind_of(msg)} is {len(body)} bytes, over the {MAX_PACKET_SIZE} "
                "byte packet limit"
            )
        self._sock.sendall(struct.pack("!I", len(body)) + body)

    def recv(self):
        """Read one message, waiting for it. Raises ServerError on an error."""
        size, = struct.unpack("!I", self._read_exactly(4))
        if not 0 < size <= MAX_PACKET_SIZE:
            raise LinkError(f"implausible packet size {size}")
        return self._parse(self._read_exactly(size))

    def drain(self) -> list:
        """Read whatever has arrived and return the complete messages in it.

        For a select loop, where blocking in the middle of a message is not
        an option. Only call this once the socket says it is readable: a
        readable TLS socket can still yield no application data, and a single
        read can carry several messages, so both cases are handled here.
        """
        self._sock.setblocking(False)
        try:
            while True:
                try:
                    chunk = self._sock.recv(65536)
                except (ssl.SSLWantReadError, BlockingIOError):
                    break
                if not chunk:
                    raise LinkError("server closed the connection")
                self._buf += chunk
        finally:
            self._sock.settimeout(self.timeout)

        messages = []
        while len(self._buf) >= 4:
            size, = struct.unpack("!I", self._buf[:4])
            if not 0 < size <= MAX_PACKET_SIZE:
                raise LinkError(f"implausible packet size {size}")
            if len(self._buf) < 4 + size:
                break
            body, self._buf = self._buf[4:4 + size], self._buf[4 + size:]
            messages.append(self._parse(body))
        return messages

    def _parse(self, body: bytes):
        msg = pb.PokerTHMessage()
        msg.ParseFromString(body)
        if kind_of(msg) == "ErrorMessage":
            raise ServerError(msg.errorMessage.errorReason)
        return msg

    def fileno(self) -> int:
        """So the connection can go straight into select()."""
        return self._sock.fileno()

    def expect(self, kind: str):
        """Read until a message of `kind` arrives, discarding what comes before."""
        while True:
            msg = self.recv()
            if kind_of(msg) == kind:
                return msg

    def _read_exactly(self, n: int) -> bytes:
        while len(self._buf) < n:
            chunk = self._sock.recv(65536)
            if not chunk:
                raise LinkError("server closed the connection")
            self._buf += chunk
        data, self._buf = self._buf[:n], self._buf[n:]
        return data


# --- Handshake --------------------------------------------------------------

DEFAULT_CREDENTIALS = "~/.config/pokerth-plus4/credentials"


def read_credentials(path: str = DEFAULT_CREDENTIALS) -> tuple[str, str]:
    """Read "user=" and "password=" from a key=value file outside the repo."""
    values = {}
    with open(os.path.expanduser(path), encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, _, value = line.partition("=")
                values[key.strip()] = value.strip()
    missing = {"user", "password"} - values.keys()
    if missing:
        raise LinkError(f"{path} is missing: {', '.join(sorted(missing))}")
    return values["user"], values["password"]


def _login(link: Link, build_id: int):
    """Wait for the announcement and start an InitMessage that matches it.

    The server opens the conversation, so the requested protocol version can
    simply be the one it was just told.
    """
    announce = payload_of(link.expect("AnnounceMessage"))

    msg, init = make("InitMessage")
    init.requestedVersion.CopyFrom(announce.protocolVersion)
    init.buildId = build_id
    # The protocol has no platform for a 1984 home computer; this describes
    # the machine the proxy runs on, which is what the server logs.
    init.clientPlatform = pb.InitMessage.platformLinux
    return announce, msg, init


def _wait_for_ack(link: Link):
    """Read until the login is acknowledged.

    The client states still know a challenge/response exchange, but the
    current client just sends the password inside the TLS connection
    (src/net/clientstate.cpp:1614). If a server ever does challenge us, say so
    plainly rather than hanging.
    """
    while True:
        msg = link.recv()
        kind = kind_of(msg)
        if kind == "InitAckMessage":
            return payload_of(msg)
        if kind == "AuthServerChallengeMessage":
            raise LinkError(
                "server started a SCRAM challenge, which is not implemented yet"
            )


def guest_login(link: Link, nickname: str, build_id: int = DEFAULT_BUILD_ID):
    """Log in as a guest. Returns (AnnounceMessage, InitAckMessage).

    Guests may watch, but not chat: the server refuses chat from anyone with
    guest rights (src/net/serverlobbythread.cpp:1776).
    """
    announce, msg, init = _login(link, build_id)
    init.login = pb.InitMessage.guestLogin
    init.nickName = nickname
    link.send(msg)
    return announce, _wait_for_ack(link)


def password_login(link: Link, user: str, password: str,
                   build_id: int = DEFAULT_BUILD_ID):
    """Log in with a registered account. Returns (AnnounceMessage, InitAckMessage).

    The password travels as clientUserData, in the clear but inside TLS -
    which is what makes the pinned key above worth having.
    """
    announce, msg, init = _login(link, build_id)
    init.login = pb.InitMessage.authenticatedLogin
    init.nickName = user
    init.clientUserData = password.encode("utf-8")
    link.send(msg)
    return announce, _wait_for_ack(link)
