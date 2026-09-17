"""What is happening at one table, kept so the Plus/4 does not have to.

The server describes a hand as a stream of events and never as a picture: it
says who acted and what their total bet now is, but never what the pot holds;
it says who sits where once, at the start, and afterwards speaks only in
player ids. A client is expected to keep the table itself.

So this does, and it keeps it in the terms the Plus/4 draws in - seats rather
than ids, one pot, and for each seat the money, the bet and whether they are
still in the hand. It also works out which actions the server would accept,
because that is arithmetic over highestSet and minimumRaise which there is no
reason to do twice, let alone on a 7501.
"""

from __future__ import annotations

import cards
import p4wire


class Seat:
    def __init__(self, number: int, player_id: int = 0):
        self.number = number
        self.player_id = player_id
        self.money = 0
        self.bet = 0
        self.folded = False
        self.all_in = False
        self.sitting_out = False
        self.cards = (cards.CARD_NONE, cards.CARD_NONE)

    def flags(self, dealer: int, me: int) -> int:
        value = p4wire.SEAT_TAKEN if self.player_id else 0
        if self.folded:
            value |= p4wire.SEAT_FOLDED
        if self.all_in:
            value |= p4wire.SEAT_ALL_IN
        if self.sitting_out:
            value |= p4wire.SEAT_SITTING_OUT
        if self.player_id and self.player_id == dealer:
            value |= p4wire.SEAT_DEALER
        if self.player_id and self.player_id == me:
            value |= p4wire.SEAT_YOU
        return value


class Table:
    """One game we are sitting at."""

    def __init__(self, game_id: int, wire_id: int, info, my_player_id: int,
                 spectator: bool = False):
        self.game_id = game_id
        self.wire_id = wire_id
        self.info = info
        self.me = my_player_id
        self.spectator = spectator
        self.name = info.gameName
        self.seat_count = info.maxNumPlayers
        self.seats = [Seat(i) for i in range(self.seat_count)]
        self.dealer = 0
        self.hand_number = 0
        self.board: list[int] = []
        self.betting_round = p4wire.ROUND_PREFLOP
        self.highest_set = 0
        self.minimum_raise = info.firstSmallBlind * 2
        self.my_cards = (cards.CARD_NONE, cards.CARD_NONE)
        self.started = False

    # -- who sits where --

    def seat_of(self, player_id: int) -> int:
        for seat in self.seats:
            if seat.player_id == player_id:
                return seat.number
        return 0xFF                       # not at this table

    def seat_for(self, player_id: int) -> Seat | None:
        number = self.seat_of(player_id)
        return self.seats[number] if number != 0xFF else None

    def place(self, player_ids) -> None:
        """Seat everyone, in the order the server gave."""
        for seat in self.seats:
            seat.player_id = 0
        for number, player_id in enumerate(player_ids):
            if number < self.seat_count:
                self.seats[number].player_id = player_id

    def take_a_seat(self, player_id: int) -> Seat | None:
        """Put a latecomer in the first free seat."""
        if self.seat_of(player_id) != 0xFF:
            return self.seat_for(player_id)
        for seat in self.seats:
            if not seat.player_id:
                seat.player_id = player_id
                return seat
        return None

    # -- the hand --

    def start_hand(self, hand_number: int, dealer: int, seat_states) -> None:
        self.hand_number = hand_number
        self.dealer = dealer
        self.board = []
        self.betting_round = p4wire.ROUND_PREFLOP
        self.highest_set = 0
        self.minimum_raise = self.info.firstSmallBlind * 2
        for number, seat in enumerate(self.seats):
            seat.bet = 0
            seat.folded = False
            seat.all_in = False
            seat.cards = (cards.CARD_NONE, cards.CARD_NONE)
            if number < len(seat_states):
                # netPlayerStateNormal is 0; anything else is not playing.
                seat.sitting_out = seat_states[number] != 0

    def action_done(self, player_id: int, action: int, total_bet: int,
                    money: int, highest_set: int, minimum_raise: int) -> Seat | None:
        seat = self.seat_for(player_id)
        self.highest_set = highest_set
        self.minimum_raise = minimum_raise
        if seat is None:
            return None
        seat.bet = total_bet
        seat.money = money
        if action == p4wire.ACTION_FOLD:
            seat.folded = True
        elif action == p4wire.ACTION_ALLIN or (money == 0 and total_bet > 0):
            seat.all_in = True
        return seat

    @property
    def pot(self) -> int:
        return sum(seat.bet for seat in self.seats)

    @property
    def my_seat(self) -> Seat | None:
        return self.seat_for(self.me)

    # -- what we may do --

    def what_may_i_do(self) -> tuple[int, int, int, int]:
        """(allowed actions, to call, minimum raise, my money).

        The amounts are what the Plus/4 needs to offer a choice without doing
        any poker arithmetic itself. A player with no money left can only sit
        it out, which the server expects as a call of nothing - see the bot in
        pokerth_bot.cpp, which does exactly that.
        """
        seat = self.my_seat
        if seat is None:
            return 0, 0, 0, 0

        money = seat.money
        to_call = max(0, self.highest_set - seat.bet)
        if money == 0:
            return p4wire.MAY_CALL, 0, 0, 0

        allowed = p4wire.MAY_FOLD
        if to_call == 0:
            allowed |= p4wire.MAY_CHECK
            if money > 0:
                allowed |= p4wire.MAY_BET
        else:
            if money >= to_call:
                allowed |= p4wire.MAY_CALL
            if money > to_call:
                allowed |= p4wire.MAY_RAISE
        allowed |= p4wire.MAY_ALL_IN
        return allowed, min(to_call, money), self.minimum_raise, money

    # -- the records that describe it --

    def table_frame(self) -> bytes:
        my_seat = self.my_seat
        return p4wire.table(self.wire_id, self.seat_count,
                            my_seat.number if my_seat else 0xFF, self.name)

    def seat_frames(self, name_of) -> list[bytes]:
        frames = []
        for seat in self.seats:
            if not seat.player_id:
                continue
            frames.append(p4wire.seat(seat.number, seat.flags(self.dealer, self.me),
                                      seat.money, name_of(seat.player_id)))
        return frames

    def seat_bet_frame(self, seat: Seat) -> bytes:
        return p4wire.seat_bet(seat.number, seat.flags(self.dealer, self.me),
                               seat.money, seat.bet)
