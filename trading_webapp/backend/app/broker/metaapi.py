"""Live broker via the MetaApi cloud REST API.

MetaApi fronts a real MT4/MT5 account over HTTPS, so the bot can run on
Linux without a MetaTrader terminal. Every call refuses to proceed
unless ``settings.live_enabled`` is true — the guard lives here as well
as in the service layer so a misconfigured caller cannot bypass it.
"""

from __future__ import annotations

from datetime import datetime, timezone

import httpx

from ..config import Settings
from ..models import Position, Quote, Side
from .base import Broker, BrokerError


class MetaApiBroker(Broker):
    name = "metaapi"

    def __init__(self, settings: Settings) -> None:
        if not settings.metaapi_token or not settings.metaapi_account_id:
            raise BrokerError(
                "MetaApi requires XAU_METAAPI_TOKEN and XAU_METAAPI_ACCOUNT_ID"
            )
        self._settings = settings
        self._account = settings.metaapi_account_id
        base = f"https://mt-client-api-v1.{settings.metaapi_region}.agiliumtrade.ai"
        self._client = httpx.AsyncClient(
            base_url=base,
            timeout=settings.metaapi_timeout,
            headers={"auth-token": settings.metaapi_token},
        )

    def _guard_live(self) -> None:
        if not self._settings.allow_live:
            raise BrokerError(
                "live trading is disabled — set XAU_ALLOW_LIVE=true to enable it"
            )

    async def _request(self, method: str, path: str, **kwargs) -> dict | list:
        try:
            resp = await self._client.request(
                method, f"/users/current/accounts/{self._account}{path}", **kwargs
            )
            resp.raise_for_status()
        except httpx.HTTPStatusError as exc:
            raise BrokerError(
                f"MetaApi {exc.response.status_code}: {exc.response.text[:200]}"
            ) from exc
        except httpx.HTTPError as exc:
            raise BrokerError(f"MetaApi request failed: {exc}") from exc
        if not resp.content:
            return {}
        return resp.json()

    async def quote(self, symbol: str) -> Quote:
        data = await self._request("GET", f"/symbols/{symbol}/current-price")
        bid, ask = data.get("bid"), data.get("ask")
        if not bid or not ask:
            raise BrokerError(f"MetaApi returned no price for {symbol}")
        return Quote(symbol=symbol, bid=float(bid), ask=float(ask))

    async def balance(self) -> float:
        data = await self._request("GET", "/accountInformation")
        return float(data.get("balance", 0.0))

    async def open_position(
        self,
        symbol: str,
        side: Side,
        volume: float,
        stop_loss: float | None,
        take_profit: float | None,
    ) -> Position:
        self._guard_live()
        if side is Side.HOLD:
            raise BrokerError("cannot open a position from a HOLD signal")

        payload: dict[str, object] = {
            "actionType": "ORDER_TYPE_BUY" if side is Side.BUY else "ORDER_TYPE_SELL",
            "symbol": symbol,
            "volume": volume,
        }
        if stop_loss is not None:
            payload["stopLoss"] = stop_loss
        if take_profit is not None:
            payload["takeProfit"] = take_profit

        data = await self._request("POST", "/trade", json=payload)
        if data.get("stringCode") not in (None, "TRADE_RETCODE_DONE", "ERR_NO_ERROR"):
            raise BrokerError(f"trade rejected: {data.get('message') or data}")

        position_id = str(data.get("positionId") or data.get("orderId") or "")
        if not position_id:
            raise BrokerError("MetaApi accepted the trade but returned no position id")

        price = float(data.get("price") or 0) or (await self.quote(symbol)).mid
        return Position(
            id=position_id,
            symbol=symbol,
            side=side.value,
            volume=volume,
            entry_price=price,
            stop_loss=stop_loss,
            take_profit=take_profit,
            opened_at=datetime.now(timezone.utc),
        )

    async def close_position(self, position_id: str) -> Position:
        self._guard_live()
        data = await self._request(
            "POST",
            "/trade",
            json={"actionType": "POSITION_CLOSE_ID", "positionId": position_id},
        )
        if data.get("stringCode") not in (None, "TRADE_RETCODE_DONE", "ERR_NO_ERROR"):
            raise BrokerError(f"close rejected: {data.get('message') or data}")

        return Position(
            id=position_id,
            symbol=self._settings.symbol,
            side="BUY",
            volume=float(data.get("volume") or 0.0),
            entry_price=float(data.get("price") or 0.0),
            close_price=float(data.get("price") or 0.0),
            profit=float(data.get("profit") or 0.0),
            status="CLOSED",
            closed_at=datetime.now(timezone.utc),
        )

    async def positions(self) -> list[dict]:
        data = await self._request("GET", "/positions")
        return data if isinstance(data, list) else []

    async def aclose(self) -> None:
        await self._client.aclose()
