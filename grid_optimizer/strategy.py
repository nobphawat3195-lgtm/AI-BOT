"""A compact, deterministic XAUUSD backtest used as the optimisation target.

The strategy is an ATR-scaled breakout with a fixed reward:risk — the
same shape as the StraddleScalper presets, reduced to the parameters
worth tuning. Bar-by-bar, no look-ahead: every decision at bar *i* uses
only data up to bar *i-1*.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Sequence


@dataclass(frozen=True)
class Bar:
    time: str
    open: float
    high: float
    low: float
    close: float


@dataclass(frozen=True)
class Params:
    """Tunable knobs. Defaults are a reasonable starting grid centre."""

    atr_period: int = 14
    breakout_atr: float = 0.8      # entry distance beyond the range, in ATR
    stop_atr: float = 1.2          # stop distance, in ATR
    reward_risk: float = 1.5       # target as a multiple of the stop
    lookback: int = 20             # bars forming the breakout range
    risk_percent: float = 0.5      # equity risked per trade


@dataclass
class Trade:
    side: str
    entry: float
    stop: float
    target: float
    volume: float
    entry_index: int
    exit_index: int | None = None
    exit_price: float | None = None
    profit: float = 0.0


@dataclass
class BacktestResult:
    trades: list[Trade] = field(default_factory=list)
    equity_curve: list[float] = field(default_factory=list)
    start_balance: float = 10_000.0

    @property
    def end_balance(self) -> float:
        return self.equity_curve[-1] if self.equity_curve else self.start_balance

    @property
    def net_profit(self) -> float:
        return self.end_balance - self.start_balance

    @property
    def wins(self) -> list[Trade]:
        return [t for t in self.trades if t.profit > 0]

    @property
    def losses(self) -> list[Trade]:
        return [t for t in self.trades if t.profit <= 0]

    @property
    def win_rate(self) -> float:
        return len(self.wins) / len(self.trades) if self.trades else 0.0

    @property
    def profit_factor(self) -> float:
        gross_win = sum(t.profit for t in self.wins)
        gross_loss = abs(sum(t.profit for t in self.losses))
        if gross_loss == 0:
            return float("inf") if gross_win > 0 else 0.0
        return gross_win / gross_loss

    @property
    def max_drawdown_percent(self) -> float:
        peak = self.start_balance
        worst = 0.0
        for equity in self.equity_curve:
            peak = max(peak, equity)
            if peak > 0:
                worst = max(worst, (peak - equity) / peak * 100)
        return worst

    @property
    def sharpe(self) -> float:
        """Per-trade Sharpe. Not annualised — used only for ranking."""
        if len(self.trades) < 2:
            return 0.0
        returns = [t.profit for t in self.trades]
        mean = sum(returns) / len(returns)
        variance = sum((r - mean) ** 2 for r in returns) / (len(returns) - 1)
        sd = math.sqrt(variance)
        return mean / sd if sd > 0 else 0.0

    def summary(self) -> dict:
        return {
            "trades": len(self.trades),
            "net_profit": round(self.net_profit, 2),
            "end_balance": round(self.end_balance, 2),
            "win_rate": round(self.win_rate, 4),
            "profit_factor": (
                round(self.profit_factor, 4)
                if self.profit_factor != float("inf")
                else None
            ),
            "max_drawdown_percent": round(self.max_drawdown_percent, 3),
            "sharpe": round(self.sharpe, 4),
        }


def atr(bars: Sequence[Bar], index: int, period: int) -> float:
    """Average true range over the ``period`` bars ending at ``index``."""
    if index < period:
        return 0.0
    total = 0.0
    for i in range(index - period + 1, index + 1):
        prev_close = bars[i - 1].close if i > 0 else bars[i].open
        true_range = max(
            bars[i].high - bars[i].low,
            abs(bars[i].high - prev_close),
            abs(bars[i].low - prev_close),
        )
        total += true_range
    return total / period


def backtest(
    bars: Sequence[Bar],
    params: Params,
    start_balance: float = 10_000.0,
    contract_size: float = 100.0,
    min_lot: float = 0.01,
    max_lot: float = 5.0,
    spread: float = 0.30,
) -> BacktestResult:
    """Run ``params`` over ``bars``. One position at a time."""
    result = BacktestResult(start_balance=start_balance)
    balance = start_balance
    open_trade: Trade | None = None

    warmup = max(params.atr_period, params.lookback) + 1
    if len(bars) <= warmup:
        result.equity_curve.append(balance)
        return result

    for i in range(warmup, len(bars)):
        bar = bars[i]

        # --- manage the open position first --------------------------
        if open_trade is not None:
            exit_price = None
            if open_trade.side == "BUY":
                # Assume the stop is touched first when a bar spans both.
                if bar.low <= open_trade.stop:
                    exit_price = open_trade.stop
                elif bar.high >= open_trade.target:
                    exit_price = open_trade.target
            else:
                if bar.high >= open_trade.stop:
                    exit_price = open_trade.stop
                elif bar.low <= open_trade.target:
                    exit_price = open_trade.target

            if exit_price is not None:
                direction = 1 if open_trade.side == "BUY" else -1
                profit = (
                    (exit_price - open_trade.entry)
                    * direction
                    * open_trade.volume
                    * contract_size
                )
                open_trade.exit_index = i
                open_trade.exit_price = exit_price
                open_trade.profit = round(profit, 2)
                balance += open_trade.profit
                result.trades.append(open_trade)
                result.equity_curve.append(round(balance, 2))
                open_trade = None

        if open_trade is not None or balance <= 0:
            continue

        # --- look for a new entry ------------------------------------
        window = bars[i - params.lookback : i]
        if not window:
            continue
        range_high = max(b.high for b in window)
        range_low = min(b.low for b in window)

        a = atr(bars, i - 1, params.atr_period)
        if a <= 0:
            continue

        buy_trigger = range_high + params.breakout_atr * a
        sell_trigger = range_low - params.breakout_atr * a
        stop_distance = params.stop_atr * a
        if stop_distance <= 0:
            continue

        risk_amount = balance * (params.risk_percent / 100.0)
        volume = risk_amount / (stop_distance * contract_size)
        volume = round(round(volume / 0.01) * 0.01, 2)
        volume = min(volume, max_lot)
        if volume < min_lot:
            continue

        if bar.high >= buy_trigger:
            entry = buy_trigger + spread / 2
            open_trade = Trade(
                side="BUY",
                entry=entry,
                stop=entry - stop_distance,
                target=entry + stop_distance * params.reward_risk,
                volume=volume,
                entry_index=i,
            )
        elif bar.low <= sell_trigger:
            entry = sell_trigger - spread / 2
            open_trade = Trade(
                side="SELL",
                entry=entry,
                stop=entry + stop_distance,
                target=entry - stop_distance * params.reward_risk,
                volume=volume,
                entry_index=i,
            )

    if not result.equity_curve:
        result.equity_curve.append(balance)
    return result
