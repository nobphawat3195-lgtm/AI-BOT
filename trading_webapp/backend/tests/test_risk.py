"""Risk gate — the layer that decides whether real money moves."""

from datetime import datetime, timezone

import pytest

from app.config import Settings
from app.models import Quote, Side, Signal
from app.risk import evaluate, position_size, round_to_step, within_trading_hours


@pytest.fixture
def settings() -> Settings:
    return Settings(
        api_token="test",
        symbol="XAUUSD",
        risk_percent=1.0,
        max_open_positions=2,
        max_daily_loss_percent=3.0,
        max_spread_usd=0.60,
        min_confidence=0.60,
        default_sl_usd=3.0,
        default_tp_r=1.5,
    )


@pytest.fixture
def quote() -> Quote:
    return Quote(symbol="XAUUSD", bid=2399.85, ask=2400.15)


def _signal(**kw) -> Signal:
    base = {"symbol": "XAUUSD", "side": Side.BUY, "confidence": 0.8}
    base.update(kw)
    return Signal(**base)


def _eval(signal, quote, settings, **kw):
    params = {"equity": 10_000.0, "open_positions": 0, "day_pnl_percent": 0.0}
    params.update(kw)
    return evaluate(signal=signal, quote=quote, settings=settings, **params)


class TestPositionSize:
    def test_risks_the_configured_fraction_of_equity(self, settings):
        # 1% of 10_000 = $100 risked; $2 stop x 100 oz/lot = $200 per lot.
        volume = position_size(10_000, 1.0, 2.0, 100.0, settings)
        assert volume == pytest.approx(0.50)

    def test_wider_stop_gives_smaller_size(self, settings):
        tight = position_size(10_000, 1.0, 2.0, 100.0, settings)
        wide = position_size(10_000, 1.0, 8.0, 100.0, settings)
        assert wide < tight

    def test_returns_zero_when_below_broker_minimum(self, settings):
        # $1 of risk against a $50 stop cannot reach the 0.01 minimum lot.
        assert position_size(100, 1.0, 50.0, 100.0, settings) == 0.0

    def test_clamped_to_max_lot(self, settings):
        volume = position_size(10_000_000, 5.0, 1.0, 100.0, settings)
        assert volume == settings.max_lot

    @pytest.mark.parametrize("bad", [0, -1])
    def test_rejects_non_positive_inputs(self, settings, bad):
        assert position_size(bad, 1.0, 2.0, 100.0, settings) == 0.0
        assert position_size(10_000, 1.0, bad, 100.0, settings) == 0.0


class TestRounding:
    def test_rounds_to_lot_step(self):
        assert round_to_step(0.4567, 0.01) == 0.46
        assert round_to_step(1.0, 0.01) == 1.0


class TestTradingHours:
    def test_inside_simple_window(self):
        now = datetime(2026, 1, 5, 10, 0, tzinfo=timezone.utc)
        assert within_trading_hours("07:00-16:00", now)

    def test_outside_simple_window(self):
        now = datetime(2026, 1, 5, 22, 0, tzinfo=timezone.utc)
        assert not within_trading_hours("07:00-16:00", now)

    def test_window_wrapping_midnight(self):
        assert within_trading_hours(
            "22:00-02:00", datetime(2026, 1, 5, 23, 30, tzinfo=timezone.utc)
        )
        assert within_trading_hours(
            "22:00-02:00", datetime(2026, 1, 5, 1, 0, tzinfo=timezone.utc)
        )
        assert not within_trading_hours(
            "22:00-02:00", datetime(2026, 1, 5, 12, 0, tzinfo=timezone.utc)
        )

    def test_multiple_windows(self):
        spec = "07:00-11:00,14:00-18:00"
        assert within_trading_hours(spec, datetime(2026, 1, 5, 15, 0, tzinfo=timezone.utc))
        assert not within_trading_hours(spec, datetime(2026, 1, 5, 12, 0, tzinfo=timezone.utc))


class TestGate:
    def test_approves_a_clean_signal(self, settings, quote):
        decision = _eval(_signal(), quote, settings)
        assert decision.approved
        assert decision.volume > 0
        assert decision.stop_loss < quote.ask
        assert decision.take_profit > quote.ask

    def test_rejects_hold(self, settings, quote):
        assert not _eval(_signal(side=Side.HOLD), quote, settings).approved

    def test_rejects_low_confidence(self, settings, quote):
        decision = _eval(_signal(confidence=0.3), quote, settings)
        assert not decision.approved
        assert "confidence" in decision.reason

    def test_rejects_foreign_symbol(self, settings, quote):
        decision = _eval(_signal(symbol="EURUSD"), quote, settings)
        assert not decision.approved
        assert "not the configured" in decision.reason

    def test_rejects_when_position_limit_reached(self, settings, quote):
        decision = _eval(_signal(), quote, settings, open_positions=2)
        assert not decision.approved
        assert "positions" in decision.reason

    def test_rejects_once_daily_loss_hit(self, settings, quote):
        decision = _eval(_signal(), quote, settings, day_pnl_percent=-3.5)
        assert not decision.approved
        assert "daily loss" in decision.reason

    def test_rejects_wide_spread(self, settings):
        wide = Quote(symbol="XAUUSD", bid=2398.0, ask=2400.0)
        decision = _eval(_signal(), wide, settings)
        assert not decision.approved
        assert "spread" in decision.reason

    def test_rejects_buy_stop_above_entry(self, settings, quote):
        decision = _eval(
            _signal(entry=2400.0, stop_loss=2405.0), quote, settings
        )
        assert not decision.approved
        assert "below entry" in decision.reason

    def test_rejects_sell_stop_below_entry(self, settings, quote):
        decision = _eval(
            _signal(side=Side.SELL, entry=2400.0, stop_loss=2395.0), quote, settings
        )
        assert not decision.approved
        assert "above entry" in decision.reason

    def test_rejects_when_equity_too_small_to_size(self, settings, quote):
        decision = _eval(_signal(), quote, settings, equity=5.0)
        assert not decision.approved
        assert "below the broker minimum" in decision.reason

    def test_honours_explicit_levels(self, settings, quote):
        decision = _eval(
            _signal(entry=2400.0, stop_loss=2397.0, take_profit=2410.0),
            quote,
            settings,
        )
        assert decision.approved
        assert decision.stop_loss == 2397.0
        assert decision.take_profit == 2410.0

    def test_derives_target_from_stop_distance(self, settings, quote):
        decision = _eval(_signal(entry=2400.0, stop_loss=2396.0), quote, settings)
        # 4.0 stop x 1.5R = 6.0 -> 2406.0
        assert decision.take_profit == pytest.approx(2406.0)

    def test_sell_levels_face_the_right_way(self, settings, quote):
        decision = _eval(_signal(side=Side.SELL), quote, settings)
        assert decision.approved
        assert decision.stop_loss > decision.take_profit

    def test_outside_hours_is_rejected(self, quote):
        settings = Settings(api_token="t", trading_hours_utc="07:00-08:00")
        decision = evaluate(
            signal=_signal(),
            quote=quote,
            equity=10_000,
            open_positions=0,
            day_pnl_percent=0.0,
            settings=settings,
            now=datetime(2026, 1, 5, 20, 0, tzinfo=timezone.utc),
        )
        assert not decision.approved
        assert "trading hours" in decision.reason
