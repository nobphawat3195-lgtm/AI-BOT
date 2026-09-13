"""HTTP surface: signals in, account/positions out, plus a live websocket."""

from __future__ import annotations

import asyncio
import logging

from fastapi import APIRouter, Depends, HTTPException, Request, WebSocket, WebSocketDisconnect

from .broker.base import BrokerError
from .broker.ea import EaBroker
from .config import get_settings
from .models import AccountState, Position, Quote, Signal, SignalResult
from .prices import PriceFeedError
from .security import require_token
from .service import TradingService

log = logging.getLogger("xauusd.routes")

router = APIRouter()
protected = APIRouter(dependencies=[Depends(require_token)])


def _service(request: Request) -> TradingService:
    service: TradingService | None = getattr(request.app.state, "service", None)
    if service is None:
        raise HTTPException(status_code=503, detail="service not ready")
    return service


# --- public -----------------------------------------------------------
@router.get("/health")
async def health() -> dict:
    settings = get_settings()
    return {
        "status": "ok",
        "symbol": settings.symbol,
        "broker": settings.broker,
        "live_enabled": settings.live_enabled,
    }


# --- protected --------------------------------------------------------
@protected.get("/account", response_model=AccountState)
async def account(request: Request) -> AccountState:
    return await _service(request).account_state()


@protected.get("/quote", response_model=Quote)
async def quote(request: Request) -> Quote:
    try:
        return await _service(request).quote()
    except (BrokerError, PriceFeedError) as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc


@protected.post("/signals", response_model=SignalResult)
async def submit_signal(signal: Signal, request: Request) -> SignalResult:
    """Entry point for Langflow / TradingAgents / the EA advisor."""
    return await _service(request).handle_signal(signal)


@protected.get("/signals")
async def signal_log(request: Request, limit: int = 50) -> list[dict]:
    return _service(request).store.recent_signals(limit=min(limit, 200))


@protected.get("/positions", response_model=list[Position])
async def positions(request: Request) -> list[Position]:
    return _service(request).store.open_positions()


@protected.get("/positions/history", response_model=list[Position])
async def history(request: Request, limit: int = 100) -> list[Position]:
    return _service(request).store.history(limit=min(limit, 500))


@protected.post("/positions/{position_id}/close", response_model=Position)
async def close_position(position_id: str, request: Request) -> Position:
    try:
        return await _service(request).close(position_id)
    except BrokerError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@protected.post("/positions/close-all", response_model=list[Position])
async def close_all(request: Request) -> list[Position]:
    return await _service(request).close_all()


@protected.get("/ea/next-signal")
async def next_ea_instruction(request: Request) -> dict:
    """Polled by ``XAUUSD_Bridge_EA.mq5``.

    Returns ``{"id": null}`` when idle so the EA can treat every reply
    uniformly. Each instruction is delivered once.
    """
    broker = _service(request).broker
    if not isinstance(broker, EaBroker):
        raise HTTPException(
            status_code=409,
            detail=f"broker is '{broker.name}'; set XAU_BROKER=ea to drive an MT5 EA",
        )
    instruction = broker.next_instruction()
    return instruction or {"id": None}


@protected.post("/control/halt")
async def halt(request: Request, reason: str = "halted by operator") -> dict:
    _service(request).halt(reason)
    return {"trading_halted": True, "reason": reason}


@protected.post("/control/resume")
async def resume(request: Request) -> dict:
    _service(request).resume()
    return {"trading_halted": False}


# --- websocket --------------------------------------------------------
@router.websocket("/ws")
async def live_feed(websocket: WebSocket) -> None:
    """Push account snapshots and trade events to the dashboard.

    The token arrives as a query parameter because browsers cannot set
    headers on a WebSocket handshake.
    """
    settings = get_settings()
    if websocket.query_params.get("token") != settings.api_token:
        await websocket.close(code=4401)
        return

    service: TradingService | None = getattr(websocket.app.state, "service", None)
    if service is None:
        await websocket.close(code=1013)
        return

    await websocket.accept()
    queue = service.subscribe()
    try:
        while True:
            try:
                message = await asyncio.wait_for(queue.get(), timeout=3.0)
            except asyncio.TimeoutError:
                state = await service.account_state()
                message = {"event": "account", "data": state.model_dump(mode="json")}
            await websocket.send_json(message)
    except WebSocketDisconnect:
        pass
    except Exception:
        log.exception("websocket closed unexpectedly")
    finally:
        service.unsubscribe(queue)


router.include_router(protected)
