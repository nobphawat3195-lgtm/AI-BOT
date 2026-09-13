"""Price feeds for XAUUSD.

``YahooFeed`` is the zero-credential default. ``StaticFeed`` backs the
tests and any offline run. Both cache briefly so a polling dashboard
cannot hammer the upstream.
"""

from __future__ import annotations

import asyncio
import time
from abc import ABC, abstractmethod

import httpx

from .models import Quote

# Gold futures — Yahoo's stand-in for spot XAUUSD.
_YAHOO_SYMBOL = "GC=F"
_YAHOO_URL = "https://query1.finance.yahoo.com/v8/finance/chart/{symbol}"


class PriceFeedError(RuntimeError):
    """Raised when no usable price could be obtained."""


class PriceFeed(ABC):
    @abstractmethod
    async def quote(self, symbol: str) -> Quote:
        ...

    async def aclose(self) -> None:
        return None


class StaticFeed(PriceFeed):
    """Fixed price, optionally nudged by the caller. Used by tests."""

    def __init__(self, mid: float = 2400.0, spread: float = 0.30) -> None:
        self.mid = mid
        self.spread = spread

    async def quote(self, symbol: str) -> Quote:
        half = self.spread / 2
        return Quote(symbol=symbol, bid=self.mid - half, ask=self.mid + half)


class YahooFeed(PriceFeed):
    """Public Yahoo Finance chart endpoint. No API key required."""

    def __init__(
        self,
        spread: float = 0.30,
        cache_seconds: float = 5.0,
        timeout: float = 10.0,
    ) -> None:
        self._spread = spread
        self._cache_seconds = cache_seconds
        self._client = httpx.AsyncClient(
            timeout=timeout, headers={"User-Agent": "Mozilla/5.0 xauusd-bot"}
        )
        self._cached: Quote | None = None
        self._cached_at = 0.0
        self._lock = asyncio.Lock()

    async def quote(self, symbol: str) -> Quote:
        async with self._lock:
            now = time.monotonic()
            if self._cached is not None and now - self._cached_at < self._cache_seconds:
                return self._cached
            mid = await self._fetch_mid()
            half = self._spread / 2
            self._cached = Quote(symbol=symbol, bid=mid - half, ask=mid + half)
            self._cached_at = now
            return self._cached

    async def _fetch_mid(self) -> float:
        try:
            resp = await self._client.get(
                _YAHOO_URL.format(symbol=_YAHOO_SYMBOL),
                params={"range": "1d", "interval": "1m"},
            )
            resp.raise_for_status()
            payload = resp.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise PriceFeedError(f"price fetch failed: {exc}") from exc

        try:
            meta = payload["chart"]["result"][0]["meta"]
            price = meta.get("regularMarketPrice")
        except (KeyError, IndexError, TypeError) as exc:
            raise PriceFeedError("unexpected price payload shape") from exc

        if not price or price <= 0:
            raise PriceFeedError("feed returned no usable price")
        return float(price)

    async def aclose(self) -> None:
        await self._client.aclose()


def build_feed(kind: str = "yahoo") -> PriceFeed:
    if kind == "static":
        return StaticFeed()
    return YahooFeed()
