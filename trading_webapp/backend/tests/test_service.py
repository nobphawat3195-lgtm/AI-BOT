"""End-to-end signal handling against the paper broker."""

import pytest

from app.models import Side, Signal

pytestmark = pytest.mark.asyncio


def _signal(**kw) -> Signal:
    base = {"symbol": "XAUUSD", "side": Side.BUY, "confidence": 0.9, "source": "test"}
    base.update(kw)
    return Signal(**base)


class TestSignalHandling:
    async def test_accepted_signal_opens_a_position(self, service, store):
        result = await service.handle_signal(_signal())
        assert result.accepted, result.reason
        assert result.position is not None
        assert result.position.side == "BUY"
        assert len(store.open_positions()) == 1

    async def test_rejected_signal_opens_nothing(self, service, store):
        result = await service.handle_signal(_signal(confidence=0.1))
        assert not result.accepted
        assert result.position is None
        assert store.open_positions() == []

    async def test_hold_is_a_no_op(self, service, store):
        result = await service.handle_signal(_signal(side=Side.HOLD))
        assert not result.accepted
        assert store.open_positions() == []

    async def test_position_limit_is_enforced(self, service, store):
        for _ in range(2):
            assert (await service.handle_signal(_signal())).accepted
        third = await service.handle_signal(_signal())
        assert not third.accepted
        assert len(store.open_positions()) == 2

    async def test_every_signal_is_logged(self, service, store):
        await service.handle_signal(_signal())
        await service.handle_signal(_signal(confidence=0.1))
        logged = store.recent_signals()
        assert len(logged) == 2
        assert {entry["accepted"] for entry in logged} == {True, False}

    async def test_halted_service_refuses_signals(self, service, store):
        service.halt("maintenance")
        result = await service.handle_signal(_signal())
        assert not result.accepted
        assert "maintenance" in result.reason
        assert store.open_positions() == []

    async def test_resume_restores_trading(self, service):
        service.halt("pause")
        service.resume()
        assert (await service.handle_signal(_signal())).accepted


class TestPositionLifecycle:
    async def test_profitable_close_credits_balance(self, service, store, feed):
        opened = (await service.handle_signal(_signal())).position
        start = store.balance()
        feed.mid = 2410.0  # +$10 in our favour
        closed = await service.close(opened.id)
        assert closed.status == "CLOSED"
        assert closed.profit > 0
        assert store.balance() == pytest.approx(start + closed.profit)
        assert store.open_positions() == []

    async def test_losing_close_debits_balance(self, service, store, feed):
        opened = (await service.handle_signal(_signal())).position
        start = store.balance()
        feed.mid = 2390.0
        closed = await service.close(opened.id)
        assert closed.profit < 0
        assert store.balance() == pytest.approx(start + closed.profit)

    async def test_sell_profits_when_price_falls(self, service, store, feed):
        opened = (await service.handle_signal(_signal(side=Side.SELL))).position
        feed.mid = 2390.0
        closed = await service.close(opened.id)
        assert closed.profit > 0

    async def test_close_all_flattens_everything(self, service, store):
        await service.handle_signal(_signal())
        await service.handle_signal(_signal())
        assert len(store.open_positions()) == 2
        closed = await service.close_all()
        assert len(closed) == 2
        assert store.open_positions() == []

    async def test_closed_position_lands_in_history(self, service, store, feed):
        opened = (await service.handle_signal(_signal())).position
        await service.close(opened.id)
        history = store.history()
        assert len(history) == 1
        assert history[0].id == opened.id


class TestMonitor:
    async def test_stop_loss_is_enforced(self, service, store, feed):
        result = await service.handle_signal(_signal(entry=2400.0, stop_loss=2397.0))
        assert result.accepted
        feed.mid = 2396.0  # driven through the stop
        closed = await service.monitor_once()
        assert len(closed) == 1
        assert closed[0].profit < 0
        assert store.open_positions() == []

    async def test_take_profit_is_enforced(self, service, store, feed):
        result = await service.handle_signal(
            _signal(entry=2400.0, stop_loss=2397.0, take_profit=2405.0)
        )
        assert result.accepted
        feed.mid = 2406.0
        closed = await service.monitor_once()
        assert len(closed) == 1
        assert closed[0].profit > 0

    async def test_untouched_position_stays_open(self, service, store, feed):
        await service.handle_signal(_signal(entry=2400.0, stop_loss=2397.0))
        feed.mid = 2401.0
        assert await service.monitor_once() == []
        assert len(store.open_positions()) == 1

    async def test_stop_loss_takes_priority_over_the_daily_cap(self, service, store, feed):
        """Per-trade protection fires first — it is the tighter of the two."""
        await service.handle_signal(_signal(entry=2400.0, stop_loss=2397.0))
        feed.mid = 2390.0
        closed = await service.monitor_once()
        assert len(closed) == 1
        assert store.open_positions() == []


class TestDailyLossCap:
    async def test_breaching_the_cap_halts_new_signals(self, service, store, feed):
        # Risk sizing keeps any single stop-out near 1%, so the cap is
        # reached through realised losses rather than one bad trade.
        opened = (await service.handle_signal(_signal(entry=2400.0, stop_loss=2397.0))).position
        feed.mid = 2390.0
        closed = await service.close(opened.id)
        assert closed.profit < 0

        state = await service.account_state()
        assert state.day_pnl_percent <= -3.0
        assert state.trading_halted
        assert "daily loss" in state.halt_reason

        feed.mid = 2400.0
        refused = await service.handle_signal(_signal())
        assert not refused.accepted
        assert store.open_positions() == []

    async def test_breaching_the_cap_flattens_open_positions(self, service, store, feed):
        # A stays tight (stopped out), B sits behind a far stop so the
        # monitor has something left to flatten once the cap trips.
        a = (await service.handle_signal(_signal(entry=2400.0, stop_loss=2397.0))).position
        b = (await service.handle_signal(_signal(entry=2400.0, stop_loss=2350.0))).position

        feed.mid = 2390.0
        await service.close(a.id)  # realise the loss that breaches the cap
        assert [p.id for p in store.open_positions()] == [b.id]

        await service.monitor_once()

        state = await service.account_state()
        assert state.trading_halted
        assert store.open_positions() == []


class TestAccountState:
    async def test_reports_broker_and_live_flag(self, service):
        state = await service.account_state()
        assert state.broker == "paper"
        assert state.live_enabled is False
        assert state.symbol == "XAUUSD"

    async def test_equity_tracks_floating_pnl(self, service, feed):
        await service.handle_signal(_signal())
        feed.mid = 2410.0
        state = await service.account_state()
        assert state.equity > state.balance
