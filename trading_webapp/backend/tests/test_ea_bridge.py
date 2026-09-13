"""EA broker mode: approved signals become instructions MetaTrader can pull."""

import pytest

from app.broker.ea import EaBroker
from app.broker.paper import PaperBroker
from app.models import Side, Signal
from app.service import TradingService

pytestmark = pytest.mark.asyncio


@pytest.fixture
def ea_service(settings, store, feed) -> TradingService:
    return TradingService(settings, store, EaBroker(settings, store, feed))


def _signal(**kw) -> Signal:
    base = {"symbol": "XAUUSD", "side": Side.BUY, "confidence": 0.9, "source": "test"}
    base.update(kw)
    return Signal(**base)


class TestOutbox:
    async def test_starts_empty(self, ea_service):
        assert ea_service.broker.next_instruction() is None

    async def test_approved_signal_is_queued(self, ea_service):
        result = await ea_service.handle_signal(_signal())
        assert result.accepted

        instruction = ea_service.broker.next_instruction()
        assert instruction is not None
        assert instruction["side"] == "BUY"
        assert instruction["symbol"] == "XAUUSD"
        assert instruction["volume"] > 0
        assert instruction["stop_loss"] > 0
        assert instruction["id"] == result.position.id

    async def test_rejected_signal_queues_nothing(self, ea_service):
        await ea_service.handle_signal(_signal(confidence=0.1))
        assert ea_service.broker.next_instruction() is None

    async def test_each_instruction_is_delivered_once(self, ea_service):
        await ea_service.handle_signal(_signal())
        assert ea_service.broker.next_instruction() is not None
        assert ea_service.broker.next_instruction() is None

    async def test_instructions_come_out_in_order(self, ea_service):
        first = await ea_service.handle_signal(_signal())
        second = await ea_service.handle_signal(_signal(side=Side.SELL))
        assert ea_service.broker.next_instruction()["id"] == first.position.id
        assert ea_service.broker.next_instruction()["id"] == second.position.id

    async def test_close_queues_a_close_instruction(self, ea_service):
        opened = (await ea_service.handle_signal(_signal())).position
        ea_service.broker.next_instruction()  # drain the open
        await ea_service.close(opened.id)
        instruction = ea_service.broker.next_instruction()
        assert instruction["side"] == "CLOSE"
        assert instruction["id"] == opened.id


class TestStopOwnership:
    async def test_ea_mode_defers_stops_to_metatrader(self, ea_service):
        assert ea_service.broker.holds_server_side_stops is True

    async def test_paper_mode_enforces_stops_locally(self, settings, store, feed):
        assert PaperBroker(settings, store, feed).holds_server_side_stops is False

    async def test_monitor_does_not_close_in_ea_mode(self, ea_service, store, feed):
        await ea_service.handle_signal(_signal(entry=2400.0, stop_loss=2397.0))
        # Past the stop, but a small enough loss that the daily cap
        # (the bridge's own kill switch) stays untriggered.
        feed.mid = 2396.0
        assert await ea_service.monitor_once() == []
        assert len(store.open_positions()) == 1

    async def test_daily_cap_still_flattens_in_ea_mode(self, ea_service, store, feed):
        """The bridge's kill switch outranks who owns the stops."""
        opened = (await ea_service.handle_signal(_signal(entry=2400.0, stop_loss=2397.0))).position
        feed.mid = 2390.0
        await ea_service.close(opened.id)  # realise a >3% loss

        feed.mid = 2400.0
        await ea_service.monitor_once()
        assert (await ea_service.account_state()).trading_halted
