"""Simulated broker — the default, and the only one safe to run unattended.

Prices come from the configured price feed; fills are immediate at the
touch with no slippage model. Good enough to validate wiring, risk
limits and the dashboard end to end without risking money.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

from ..config import Settings
from ..models import Position, Quote, Side
from ..prices import PriceFeed
from .base import Broker, BrokerError


class PaperBroker(Broker):
    name = "paper"
    holds_server_side_stops = False  # no venue behind us; the monitor enforces stops

    def __init__(self, settings: Settings, store, feed: PriceFeed) -> None:
        self._settings = settings
        self._store = store
        self._feed = feed

    async def quote(self, symbol: str) -> Quote:
        return await self._feed.quote(symbol)

    async def balance(self) -> float:
        return self._store.balance()

    async def open_position(
        self,
        symbol: str,
        side: Side,
        volume: float,
        stop_loss: float | None,
        take_profit: float | None,
    ) -> Position:
        if side is Side.HOLD:
            raise BrokerError("cannot open a position from a HOLD signal")
        q = await self.quote(symbol)
        price = q.ask if side is Side.BUY else q.bid
        position = Position(
            id=uuid.uuid4().hex[:12],
            symbol=symbol,
            side=side.value,
            volume=volume,
            entry_price=price,
            stop_loss=stop_loss,
            take_profit=take_profit,
            opened_at=datetime.now(timezone.utc),
        )
        self._store.add_position(position)
        return position

    async def close_position(self, position_id: str) -> Position:
        position = self._store.get_position(position_id)
        if position is None:
            raise BrokerError(f"unknown position {position_id}")
        if position.status == "CLOSED":
            raise BrokerError(f"position {position_id} is already closed")

        q = await self.quote(position.symbol)
        price = q.bid if position.side == "BUY" else q.ask
        profit = self.profit_of(position, price)

        self._store.close_position(position_id, price, profit)
        self._store.adjust_balance(profit)

        position.status = "CLOSED"
        position.close_price = price
        position.profit = profit
        position.closed_at = datetime.now(timezone.utc)
        return position

    def profit_of(self, position: Position, price: float) -> float:
        """Mark-to-market profit in account currency at ``price``."""
        direction = 1 if position.side == "BUY" else -1
        move = (price - position.entry_price) * direction
        return round(move * position.volume * self._settings.contract_size, 2)

    def should_exit(self, position: Position, quote: Quote) -> str | None:
        """Return ``'SL'``/``'TP'`` when a protective level has been touched.

        The paper broker has no server-side stops, so the polling loop
        checks them explicitly against the side the position exits on.
        """
        price = quote.bid if position.side == "BUY" else quote.ask
        if position.side == "BUY":
            if position.stop_loss is not None and price <= position.stop_loss:
                return "SL"
            if position.take_profit is not None and price >= position.take_profit:
                return "TP"
        else:
            if position.stop_loss is not None and price >= position.stop_loss:
                return "SL"
            if position.take_profit is not None and price <= position.take_profit:
                return "TP"
        return None
