"""Trading service — the single path from a signal to a live order.

Holds the only mutating entry points the API exposes, so the risk gate
cannot be routed around, and runs the background loop that enforces
protective levels for brokers without server-side stops.
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone

from . import risk
from .broker.base import Broker, BrokerError
from .config import Settings
from .models import AccountState, Position, Quote, RiskDecision, Signal, SignalResult
from .prices import PriceFeedError
from .store import Store

log = logging.getLogger("xauusd.service")


class TradingService:
    def __init__(self, settings: Settings, store: Store, broker: Broker) -> None:
        self.settings = settings
        self.store = store
        self.broker = broker
        self._lock = asyncio.Lock()
        self._halt_reason = ""
        self._subscribers: set[asyncio.Queue] = set()

    # --- read paths -------------------------------------------------
    async def quote(self) -> Quote:
        return await self.broker.quote(self.settings.symbol)

    async def unrealised(self, quote: Quote | None = None) -> float:
        positions = self.store.open_positions()
        if not positions:
            return 0.0
        if quote is None:
            quote = await self.quote()
        total = 0.0
        for p in positions:
            price = quote.bid if p.side == "BUY" else quote.ask
            direction = 1 if p.side == "BUY" else -1
            total += (price - p.entry_price) * direction * p.volume * self.settings.contract_size
        return round(total, 2)

    async def account_state(self) -> AccountState:
        balance = self.store.balance()
        try:
            quote = await self.quote()
            floating = await self.unrealised(quote)
        except (BrokerError, PriceFeedError):
            floating = 0.0
        equity = balance + floating
        opening = self.store.opening_balance()
        day_pnl = equity - opening
        day_pnl_percent = (day_pnl / opening * 100) if opening else 0.0
        halted, reason = self._halt_state(day_pnl_percent)
        return AccountState(
            balance=round(balance, 2),
            equity=round(equity, 2),
            open_positions=len(self.store.open_positions()),
            day_pnl=round(day_pnl, 2),
            day_pnl_percent=round(day_pnl_percent, 3),
            trading_halted=halted,
            halt_reason=reason,
            broker=self.broker.name,
            live_enabled=self.settings.live_enabled,
            symbol=self.settings.symbol,
        )

    def _halt_state(self, day_pnl_percent: float) -> tuple[bool, str]:
        if self._halt_reason:
            return True, self._halt_reason
        if day_pnl_percent <= -abs(self.settings.max_daily_loss_percent):
            return True, (
                f"daily loss {day_pnl_percent:.2f}% reached the "
                f"{self.settings.max_daily_loss_percent:.2f}% limit"
            )
        return False, ""

    # --- control ----------------------------------------------------
    def halt(self, reason: str = "halted by operator") -> None:
        self._halt_reason = reason
        log.warning("trading halted: %s", reason)

    def resume(self) -> None:
        self._halt_reason = ""
        log.info("trading resumed")

    # --- write path -------------------------------------------------
    async def handle_signal(self, signal: Signal) -> SignalResult:
        """Risk-check ``signal`` and, if it passes, send the order."""
        async with self._lock:
            state = await self.account_state()

            if state.trading_halted:
                decision = RiskDecision(approved=False, reason=state.halt_reason)
                self.store.log_signal(signal, False, decision.reason)
                await self._publish("signal", {"accepted": False, "reason": decision.reason})
                return SignalResult(
                    accepted=False, reason=decision.reason, signal=signal, risk=decision
                )

            try:
                quote = await self.quote()
            except (BrokerError, PriceFeedError) as exc:
                reason = f"no price available: {exc}"
                self.store.log_signal(signal, False, reason)
                return SignalResult(
                    accepted=False,
                    reason=reason,
                    signal=signal,
                    risk=RiskDecision(approved=False, reason=reason),
                )

            decision = risk.evaluate(
                signal=signal,
                quote=quote,
                equity=state.equity,
                open_positions=state.open_positions,
                day_pnl_percent=state.day_pnl_percent,
                settings=self.settings,
            )

            if not decision.approved:
                self.store.log_signal(signal, False, decision.reason)
                await self._publish("signal", {"accepted": False, "reason": decision.reason})
                return SignalResult(
                    accepted=False, reason=decision.reason, signal=signal, risk=decision
                )

            try:
                position = await self.broker.open_position(
                    symbol=signal.symbol,
                    side=signal.side,
                    volume=decision.volume,
                    stop_loss=decision.stop_loss,
                    take_profit=decision.take_profit,
                )
            except BrokerError as exc:
                reason = f"broker rejected the order: {exc}"
                self.store.log_signal(signal, False, reason)
                return SignalResult(
                    accepted=False, reason=reason, signal=signal, risk=decision
                )

            self.store.log_signal(signal, True, "order placed")
            await self._publish("position_opened", position.model_dump(mode="json"))
            log.info(
                "opened %s %.2f lots @ %.2f (sl=%s tp=%s)",
                position.side, position.volume, position.entry_price,
                position.stop_loss, position.take_profit,
            )
            return SignalResult(
                accepted=True,
                reason="order placed",
                signal=signal,
                risk=decision,
                position=position,
            )

    async def close(self, position_id: str) -> Position:
        async with self._lock:
            position = await self.broker.close_position(position_id)
            await self._publish("position_closed", position.model_dump(mode="json"))
            log.info("closed %s profit=%.2f", position_id, position.profit)
            return position

    async def close_all(self) -> list[Position]:
        closed = []
        for p in self.store.open_positions():
            try:
                closed.append(await self.close(p.id))
            except BrokerError as exc:
                log.error("failed to close %s: %s", p.id, exc)
        return closed

    # --- background monitor -----------------------------------------
    async def monitor_once(self) -> list[Position]:
        """Enforce SL/TP and the daily loss cap. Returns positions closed."""
        if self.broker.holds_server_side_stops:
            # The venue enforces SL/TP itself; only the daily cap needs us.
            await self._enforce_daily_cap()
            return []

        closed: list[Position] = []
        positions = self.store.open_positions()
        if positions:
            try:
                quote = await self.quote()
            except (BrokerError, PriceFeedError) as exc:
                log.warning("monitor skipped, no price: %s", exc)
                return []
            for p in positions:
                hit = self.broker.should_exit(p, quote)
                if hit:
                    try:
                        done = await self.close(p.id)
                        log.info("%s hit for %s, profit=%.2f", hit, p.id, done.profit)
                        closed.append(done)
                    except BrokerError as exc:
                        log.error("auto-close failed for %s: %s", p.id, exc)
        await self._enforce_daily_cap()
        return closed

    async def _enforce_daily_cap(self) -> None:
        state = await self.account_state()
        if state.trading_halted and self.store.open_positions() and not self._halt_reason:
            log.warning("daily loss cap breached — flattening open positions")
            self.halt(state.halt_reason)
            await self.close_all()

    async def run_monitor(self, interval: float = 5.0) -> None:
        """Poll forever. Cancelled on shutdown."""
        log.info("position monitor started (every %.1fs)", interval)
        while True:
            try:
                await self.monitor_once()
            except asyncio.CancelledError:
                raise
            except Exception:  # keep the loop alive across transient faults
                log.exception("monitor iteration failed")
            await asyncio.sleep(interval)

    # --- websocket fan-out ------------------------------------------
    def subscribe(self) -> asyncio.Queue:
        q: asyncio.Queue = asyncio.Queue(maxsize=100)
        self._subscribers.add(q)
        return q

    def unsubscribe(self, q: asyncio.Queue) -> None:
        self._subscribers.discard(q)

    async def _publish(self, event: str, data: dict) -> None:
        message = {
            "event": event,
            "data": data,
            "ts": datetime.now(timezone.utc).isoformat(),
        }
        for q in list(self._subscribers):
            try:
                q.put_nowait(message)
            except asyncio.QueueFull:
                self._subscribers.discard(q)
