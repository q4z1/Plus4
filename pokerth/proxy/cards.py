"""Cards, and the small piece of cryptography guarding two of them.

A card is a number from 0 to 51: the rank is `code % 13`, counting 2 up to
ace, and the suit is `code / 13` in the order diamonds, hearts, spades, clubs
(src/gui/qt6-qml/cpp/qmlguiinterface.cpp). That is the whole encoding, and it
crosses the wire to the Plus/4 unchanged - one byte a card, and 52 for a card
that is not known or not there.

The hole cards are the interesting part. A player who logged in with an
account does not get them in the clear: the server sends them encrypted with
a key derived from that account's password, so that nobody who can see the
connection - including whoever runs the server - can read them from the wire.
Which means the proxy has to do what the real client does
(src/net/clientstate.cpp, around the HandStartMessage):

  key material   SHA-1 chains over the password, laid out over key and IV
  cipher         AES-128 in CBC mode, padding off
  plain text     "playerId gameId handNum card1 card2", as decimal text

The identifiers in that plain text are not decoration. They tie the cards to
one player, one game and one hand, so a cipher text replayed from another
hand cannot pass. decrypt_hole_cards checks them and refuses if they do not
match, exactly as the client does.
"""

from __future__ import annotations

import hashlib

CARD_NONE = 52

RANKS = ("2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "A")
SUITS = ("d", "h", "s", "c")
SUIT_SYMBOLS = ("♦", "♥", "♠", "♣")


class CardError(Exception):
    pass


def card_name(code: int, symbols: bool = False) -> str:
    """A card as text, e.g. "Kh" or "K♥"."""
    if not 0 <= code <= 51:
        return "?"
    suits = SUIT_SYMBOLS if symbols else SUITS
    return RANKS[code % 13] + suits[code // 13]


def _key_and_iv(password: bytes) -> tuple[bytes, bytes]:
    """Key and IV from a password, the way CryptHelper::BytesToKey does it.

    Like OpenSSL's EVP_BytesToKey with a count of two and no salt, but spelled
    out by hand because gcrypt has nothing of the sort - so it has to be
    spelled out here as well, or the cards come back as noise.
    """
    first = hashlib.sha1(hashlib.sha1(password).digest()).digest()
    second = hashlib.sha1(hashlib.sha1(first + password).digest()).digest()
    key = first[:16]
    iv = first[16:20] + second[:12]     # 4 bytes left over from the first
    return key, iv


def decrypt_hole_cards(password: str, cipher: bytes, player_id: int,
                       game_id: int, hand_number: int) -> tuple[int, int]:
    """The two hole cards out of a HandStartMessage's encryptedCards."""
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

    if not password:
        raise CardError("no password, so nothing to decrypt with")
    if not cipher or len(cipher) % 16:
        raise CardError(f"cipher text is {len(cipher)} bytes, not whole blocks")

    key, iv = _key_and_iv(password.encode("utf-8"))
    decryptor = Cipher(algorithms.AES(key), modes.CBC(iv)).decryptor()
    plain = decryptor.update(cipher) + decryptor.finalize()

    # Padding is off, so whatever the server used to fill the last block is
    # still attached. It pads with zero bytes, and the client reads the text
    # with a stream that stops at the first one, so cut there and read the
    # decimal numbers that precede it.
    fields = plain.split(b"\0", 1)[0].split()
    if len(fields) < 5:
        raise CardError("decrypted text does not hold five numbers")
    try:
        got_player, got_game, got_hand, card1, card2 = (int(f) for f in fields[:5])
    except ValueError:
        raise CardError("decrypted text is not numbers - wrong password?")

    if (got_player, got_game, got_hand) != (player_id, game_id, hand_number):
        raise CardError(
            f"these cards belong to player {got_player}, game {got_game}, "
            f"hand {got_hand}, not to player {player_id}, game {game_id}, "
            f"hand {hand_number}")
    if not (0 <= card1 <= 51 and 0 <= card2 <= 51):
        raise CardError(f"not cards: {card1}, {card2}")
    return card1, card2


def _encrypt_for_test(password: str, text: str) -> bytes:
    """The other half, so the self test has something to decrypt."""
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

    key, iv = _key_and_iv(password.encode("utf-8"))
    data = text.encode("utf-8")
    data += b"\0" * (-len(data) % 16)   # the server pads with zeroes
    encryptor = Cipher(algorithms.AES(key), modes.CBC(iv)).encryptor()
    return encryptor.update(data) + encryptor.finalize()


def _selftest() -> int:
    ok = True

    def check(what, got, want):
        nonlocal ok
        if got != want:
            print(f"FAIL {what}: {got!r} != {want!r}")
            ok = False

    check("first card", card_name(0), "2d")
    check("last card", card_name(51), "Ac")
    check("the ten", card_name(8), "Td")
    check("ace of spades", card_name(38), "As")
    check("two of hearts", card_name(13), "2h")
    check("not a card", card_name(CARD_NONE), "?")
    check("with symbols", card_name(25, symbols=True), "A♥")
    check("every code names something",
          len({card_name(c) for c in range(52)}), 52)

    # Key derivation is deterministic and fills both key and IV.
    key, iv = _key_and_iv(b"secret")
    check("key length", len(key), 16)
    check("iv length", len(iv), 16)
    check("key is stable", _key_and_iv(b"secret"), (key, iv))
    check("another password differs", _key_and_iv(b"secreu") == (key, iv), False)

    # Round trip through the cipher, including the checks that tie the cards
    # to one hand.
    cipher = _encrypt_for_test("hunter2", "42 4711 7 26 38")
    check("cards out", decrypt_hole_cards("hunter2", cipher, 42, 4711, 7), (26, 38))

    for what, args in [("wrong player", (43, 4711, 7)),
                       ("wrong game", (42, 4712, 7)),
                       ("wrong hand", (42, 4711, 8))]:
        try:
            decrypt_hole_cards("hunter2", cipher, *args)
            print(f"FAIL {what}: accepted")
            ok = False
        except CardError:
            pass

    try:
        decrypt_hole_cards("hunter3", cipher, 42, 4711, 7)
        print("FAIL wrong password: accepted")
        ok = False
    except CardError:
        pass

    print("self test:", "ok" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    import sys
    sys.exit(_selftest())
