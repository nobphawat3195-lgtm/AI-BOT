import pytest

from app.broker.paper import PaperBroker
from app.config import Settings
from app.prices import StaticFeed
from app.service import TradingService
from app.store import Store


@pytest.fixture
def settings(tmp_path) -> Settings:
    return Settings(
        api_token="test-token",
        broker="paper",
        allow_live=False,
        db_path=str(tmp_path / "test.db"),
        paper_start_balance=10_000.0,
        risk_percent=1.0,
        max_open_positions=2,
        max_daily_loss_percent=3.0,
        min_confidence=0.60,
        default_sl_usd=3.0,
    )


@pytest.fixture
def store(settings) -> Store:
    s = Store(settings.db_path, settings.paper_start_balance)
    yield s
    s.close()


@pytest.fixture
def feed() -> StaticFeed:
    return StaticFeed(mid=2400.0, spread=0.30)


@pytest.fixture
def service(settings, store, feed) -> TradingService:
    broker = PaperBroker(settings, store, feed)
    return TradingService(settings, store, broker)
