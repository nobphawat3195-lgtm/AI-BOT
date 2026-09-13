"""FastAPI entry point.

Run with:  uvicorn app.main:app --host 0.0.0.0 --port 8000
"""

from __future__ import annotations

import asyncio
import logging
import os
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from .broker.base import Broker
from .broker.ea import EaBroker
from .broker.metaapi import MetaApiBroker
from .broker.paper import PaperBroker
from .config import get_settings
from .prices import build_feed
from .routes import router
from .service import TradingService
from .store import Store

logging.basicConfig(
    level=os.getenv("XAU_LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)-7s %(name)s | %(message)s",
)
log = logging.getLogger("xauusd")

FRONTEND_DIR = Path(__file__).resolve().parents[2] / "frontend"


def build_broker(settings, store, feed) -> Broker:
    if settings.broker == "metaapi":
        log.warning(
            "MetaApi broker selected (live orders %s)",
            "ENABLED" if settings.allow_live else "blocked by XAU_ALLOW_LIVE=false",
        )
        return MetaApiBroker(settings)
    if settings.broker == "ea":
        log.warning(
            "EA bridge selected — MetaTrader executes; keep the EA in dry run until verified"
        )
        return EaBroker(settings, store, feed)
    log.info("paper broker selected — no real orders will be sent")
    return PaperBroker(settings, store, feed)


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    if settings.api_token == "change-me":
        log.warning(
            "XAU_API_TOKEN is still the default — set a real token before exposing this port"
        )

    store = Store(settings.db_path, settings.paper_start_balance)
    feed = build_feed(os.getenv("XAU_PRICE_FEED", "yahoo"))
    broker = build_broker(settings, store, feed)
    service = TradingService(settings, store, broker)

    app.state.store = store
    app.state.feed = feed
    app.state.broker = broker
    app.state.service = service

    monitor = asyncio.create_task(service.run_monitor())
    log.info("XAUUSD bot ready — broker=%s live=%s", broker.name, settings.live_enabled)
    try:
        yield
    finally:
        monitor.cancel()
        try:
            await monitor
        except asyncio.CancelledError:
            pass
        await broker.aclose()
        await feed.aclose()
        store.close()
        log.info("shutdown complete")


app = FastAPI(
    title="XAUUSD Automated Trading Bridge",
    version="1.0.0",
    description="Signal intake, risk gate and order routing for automated gold trading.",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=get_settings().cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(router, prefix="/api")

if FRONTEND_DIR.is_dir():
    app.mount("/static", StaticFiles(directory=FRONTEND_DIR), name="static")

    @app.get("/", include_in_schema=False)
    async def dashboard() -> FileResponse:
        return FileResponse(FRONTEND_DIR / "index.html")
