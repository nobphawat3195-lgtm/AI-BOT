"""Broker mode where a MetaTrader 5 EA is the executor.

The bridge still owns sizing and the risk gate; the approved instruction
is queued here and ``XAUUSD_Bridge_EA.mq5`` picks it up over HTTP. The
EA attaches SL/TP at the broker, so MetaTrader — not this process —
holds the protective orders.

Caveat worth knowing: the queue records *intent*. Until the EA confirms,
MetaTrader is the source of truth for whether a fill actually happened
and at what price. Reconcile against the terminal before trusting the
local P&L in this mode.
"""

from __future__ import annotations

import uuid
from collections import deque
from datetime import datetime, timezone

from ..config import Settings
from ..models import Position, Quote, Side
from ..prices import PriceFeed
from .base import Broker, BrokerError


class EaBroker(Broker):
    name = "ea"
    holds_server_side_stops = True  # the EA attaches SL/TP at the broker

    def __init__(self, settings: Settings, store, feed: PriceFeed, queue_size: int = 20) -> None:
        self._settings = settings
        self._store = store
        self._feed = feed
        self._outbox: deque[dict] = deque(maxlen=queue_size)

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
        self._outbox.append(
            {
                "id": position.id,
                "symbol": symbol,
                "side": side.value,
                "volume": volume,
                "stop_loss": stop_loss or 0.0,
                "take_profit": take_profit or 0.0,
                "issued_at": position.opened_at.isoformat(),
            }
        )
        return position

    async def close_position(self, position_id: str) -> Position:
        position = self._store.get_position(position_id)
        if position is None:
            raise BrokerError(f"unknown position {position_id}")
        if position.status == "CLOSED":
            raise BrokerError(f"position {position_id} is already closed")

        q = await self.quote(position.symbol)
        price = q.bid if position.side == "BUY" else q.ask
        direction = 1 if position.side == "BUY" else -1
        profit = round(
            (price - position.entry_price) * direction
            * position.volume * self._settings.contract_size,
            2,
        )
        self._store.close_position(position_id, price, profit)
        self._store.adjust_balance(profit)
        self._outbox.append(
            {
                "id": position_id,
                "symbol": position.symbol,
                "side": "CLOSE",
                "volume": position.volume,
                "stop_loss": 0.0,
                "take_profit": 0.0,
                "issued_at": datetime.now(timezone.utc).isoformat(),
            }
        )

        position.status = "CLOSED"
        position.close_price = price
        position.profit = profit
        position.closed_at = datetime.now(timezone.utc)
        return position

    # --- EA-facing queue --------------------------------------------
    def next_instruction(self) -> dict | None:
        """Pop the oldest pending instruction, or ``None`` when idle."""
        if not self._outbox:
            return None
        return self._outbox.popleft()

    def pending(self) -> int:
        return len(self._outbox)
