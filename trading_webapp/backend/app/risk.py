"""Pre-trade risk gate.

Every order passes through :func:`evaluate` before it reaches a broker.
The gate is deliberately conservative: anything it cannot verify is a
rejection, never a silent pass.
"""

from __future__ import annotations

from datetime import datetime, time, timezone

from .config import Settings
from .models import Quote, RiskDecision, Side, Signal


def _parse_windows(spec: str) -> list[tuple[time, time]]:
    windows: list[tuple[time, time]] = []
    for chunk in spec.split(","):
        chunk = chunk.strip()
        if not chunk:
            continue
        start_s, _, end_s = chunk.partition("-")
        sh, _, sm = start_s.strip().partition(":")
        eh, _, em = end_s.strip().partition(":")
        windows.append(
            (time(int(sh), int(sm or 0)), time(int(eh), int(em or 0)))
        )
    return windows


def within_trading_hours(spec: str, now: datetime | None = None) -> bool:
    now = now or datetime.now(timezone.utc)
    current = now.time()
    for start, end in _parse_windows(spec):
        if start <= end:
            if start <= current <= end:
                return True
        else:  # window wraps past midnight
            if current >= start or current <= end:
                return True
    return False


def round_to_step(volume: float, step: float) -> float:
    if step <= 0:
        return volume
    return round(round(volume / step) * step, 8)


def position_size(
    equity: float,
    risk_percent: float,
    stop_distance: float,
    contract_size: float,
    settings: Settings,
) -> float:
    """Lots such that a stop-out costs ``risk_percent`` of equity.

    Loss per lot is ``stop_distance * contract_size`` for a USD-quoted
    metal, so the sizing is a direct division. Returns 0.0 when the
    inputs cannot produce a valid lot.
    """
    if equity <= 0 or stop_distance <= 0 or contract_size <= 0:
        return 0.0
    risk_amount = equity * (risk_percent / 100.0)
    loss_per_lot = stop_distance * contract_size
    raw = risk_amount / loss_per_lot
    volume = round_to_step(raw, settings.lot_step)
    volume = min(volume, settings.max_lot)
    if volume < settings.min_lot:
        return 0.0
    return volume


def derive_levels(
    signal: Signal, quote: Quote, settings: Settings
) -> tuple[float, float, float]:
    """Return ``(entry, stop_loss, take_profit)`` filling in any gaps.

    A missing stop falls back to ``default_sl_usd``; a missing target is
    placed at ``default_tp_r`` times the realised stop distance.
    """
    is_buy = signal.side is Side.BUY
    entry = signal.entry or (quote.ask if is_buy else quote.bid)

    if signal.stop_loss is not None:
        stop = signal.stop_loss
    else:
        stop = entry - settings.default_sl_usd if is_buy else entry + settings.default_sl_usd

    distance = abs(entry - stop)
    if signal.take_profit is not None:
        target = signal.take_profit
    else:
        target = (
            entry + distance * settings.default_tp_r
            if is_buy
            else entry - distance * settings.default_tp_r
        )
    return entry, stop, target


def evaluate(
    signal: Signal,
    quote: Quote,
    equity: float,
    open_positions: int,
    day_pnl_percent: float,
    settings: Settings,
    now: datetime | None = None,
) -> RiskDecision:
    """Approve or reject ``signal``, sizing the trade when approved."""
    if signal.side is Side.HOLD:
        return RiskDecision(approved=False, reason="signal is HOLD")

    if signal.symbol != settings.symbol:
        return RiskDecision(
            approved=False,
            reason=f"symbol {signal.symbol} is not the configured {settings.symbol}",
        )

    if signal.confidence < settings.min_confidence:
        return RiskDecision(
            approved=False,
            reason=(
                f"confidence {signal.confidence:.2f} below "
                f"minimum {settings.min_confidence:.2f}"
            ),
        )

    if not within_trading_hours(settings.trading_hours_utc, now):
        return RiskDecision(approved=False, reason="outside configured trading hours")

    if open_positions >= settings.max_open_positions:
        return RiskDecision(
            approved=False,
            reason=f"already holding {open_positions} of {settings.max_open_positions} positions",
        )

    if day_pnl_percent <= -abs(settings.max_daily_loss_percent):
        return RiskDecision(
            approved=False,
            reason=(
                f"daily loss {day_pnl_percent:.2f}% hit the "
                f"{settings.max_daily_loss_percent:.2f}% limit"
            ),
        )

    if quote.spread > settings.max_spread_usd:
        return RiskDecision(
            approved=False,
            reason=f"spread {quote.spread:.2f} wider than {settings.max_spread_usd:.2f}",
        )

    entry, stop, target = derive_levels(signal, quote, settings)
    distance = abs(entry - stop)
    if distance <= 0:
        return RiskDecision(approved=False, reason="stop distance is zero")

    # A stop on the wrong side of entry would invert the trade's risk.
    if signal.side is Side.BUY and stop >= entry:
        return RiskDecision(approved=False, reason="BUY stop must sit below entry")
    if signal.side is Side.SELL and stop <= entry:
        return RiskDecision(approved=False, reason="SELL stop must sit above entry")

    volume = position_size(
        equity, settings.risk_percent, distance, settings.contract_size, settings
    )
    if volume <= 0:
        return RiskDecision(
            approved=False,
            reason="computed volume below the broker minimum — equity too small for this stop",
        )

    return RiskDecision(
        approved=True,
        reason="ok",
        volume=volume,
        stop_loss=stop,
        take_profit=target,
    )
