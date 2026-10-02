import os
import tempfile

# Must run before anything imports the app: TestClient starts the real
# lifespan, which builds its own price feed and background monitor from
# the environment. Left unset, that feed is the live Yahoo one and the
# monitor polls it on a loop — turning the suite into a network test
# that hangs whenever the upstream is slow or unreachable.
os.environ.setdefault("XAU_PRICE_FEED", "static")
os.environ.setdefault("XAU_API_TOKEN", "test-token")
os.environ.setdefault("XAU_BROKER", "paper")
os.environ.setdefault("XAU_ALLOW_LIVE", "false")
os.environ.setdefault(
    "XAU_DB_PATH", os.path.join(tempfile.gettempdir(), "xauusd_lifespan_test.db")
)

import pytest  # noqa: E402

from app.broker.paper import PaperBroker  # noqa: E402
from app.config import Settings  # noqa: E402
from app.prices import StaticFeed  # noqa: E402
from app.service import TradingService  # noqa: E402
from app.store import Store  # noqa: E402


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
