"""Broker interface shared by the paper simulator and the live adapter."""

from __future__ import annotations

from abc import ABC, abstractmethod

from ..models import Position, Quote, Side


class BrokerError(RuntimeError):
    """Raised when a broker rejects or cannot complete a request."""


class Broker(ABC):
    name: str = "abstract"

    #: True when the venue holds SL/TP itself, so the local monitor must
    #: not try to enforce them a second time.
    holds_server_side_stops: bool = True

    @abstractmethod
    async def quote(self, symbol: str) -> Quote:
        """Current bid/ask for ``symbol``."""

    @abstractmethod
    async def open_position(
        self,
        symbol: str,
        side: Side,
        volume: float,
        stop_loss: float | None,
        take_profit: float | None,
    ) -> Position:
        """Send a market order and return the resulting position."""

    @abstractmethod
    async def close_position(self, position_id: str) -> Position:
        """Flatten ``position_id`` and return it with realised profit set."""

    @abstractmethod
    async def balance(self) -> float:
        """Account balance in the deposit currency."""

    async def aclose(self) -> None:
        """Release any network resources. Overridden where needed."""
        return None
