"""HTTP surface: auth, signal intake, and the account/position views."""

import pytest
from fastapi.testclient import TestClient

from app.broker.paper import PaperBroker
from app.config import Settings, get_settings
from app.main import app
from app.prices import StaticFeed
from app.service import TradingService
from app.store import Store

TOKEN = "test-token"
AUTH = {"X-API-Token": TOKEN}


@pytest.fixture
def client(tmp_path, monkeypatch):
    settings = Settings(
        api_token=TOKEN,
        broker="paper",
        allow_live=False,
        db_path=str(tmp_path / "api.db"),
        paper_start_balance=10_000.0,
        min_confidence=0.60,
    )
    get_settings.cache_clear()
    monkeypatch.setattr("app.security.get_settings", lambda: settings)
    monkeypatch.setattr("app.routes.get_settings", lambda: settings)

    store = Store(settings.db_path, settings.paper_start_balance)
    feed = StaticFeed(mid=2400.0, spread=0.30)
    service = TradingService(settings, store, PaperBroker(settings, store, feed))

    app.state.service = service
    with TestClient(app) as c:
        # The lifespan installs its own service; override it for the test.
        app.state.service = service
        c.feed = feed
        c.store = store
        yield c
    store.close()
    get_settings.cache_clear()


def _payload(**kw) -> dict:
    base = {"symbol": "XAUUSD", "side": "BUY", "confidence": 0.9, "source": "pytest"}
    base.update(kw)
    return base


class TestAuth:
    def test_health_needs_no_token(self, client):
        assert client.get("/api/health").status_code == 200

    @pytest.mark.parametrize(
        "path", ["/api/account", "/api/positions", "/api/signals", "/api/quote"]
    )
    def test_protected_routes_reject_missing_token(self, client, path):
        assert client.get(path).status_code == 401

    def test_wrong_token_is_rejected(self, client):
        r = client.get("/api/account", headers={"X-API-Token": "nope"})
        assert r.status_code == 401

    def test_posting_a_signal_without_a_token_is_rejected(self, client):
        r = client.post("/api/signals", json=_payload())
        assert r.status_code == 401
        assert client.store.open_positions() == []


class TestSignals:
    def test_accepted_signal_returns_a_position(self, client):
        r = client.post("/api/signals", json=_payload(), headers=AUTH)
        assert r.status_code == 200
        body = r.json()
        assert body["accepted"] is True
        assert body["position"]["side"] == "BUY"

    def test_low_confidence_is_refused(self, client):
        r = client.post("/api/signals", json=_payload(confidence=0.1), headers=AUTH)
        assert r.status_code == 200
        body = r.json()
        assert body["accepted"] is False
        assert "confidence" in body["reason"]

    def test_malformed_payload_is_a_422(self, client):
        r = client.post("/api/signals", json={"side": "SIDEWAYS"}, headers=AUTH)
        assert r.status_code == 422

    def test_confidence_out_of_range_is_a_422(self, client):
        r = client.post("/api/signals", json=_payload(confidence=5), headers=AUTH)
        assert r.status_code == 422

    def test_signal_log_records_attempts(self, client):
        client.post("/api/signals", json=_payload(), headers=AUTH)
        client.post("/api/signals", json=_payload(confidence=0.1), headers=AUTH)
        entries = client.get("/api/signals", headers=AUTH).json()
        assert len(entries) == 2


class TestAccountAndPositions:
    def test_account_reports_paper_mode(self, client):
        state = client.get("/api/account", headers=AUTH).json()
        assert state["broker"] == "paper"
        assert state["live_enabled"] is False
        assert state["balance"] == pytest.approx(10_000.0)

    def test_positions_list_reflects_open_trades(self, client):
        client.post("/api/signals", json=_payload(), headers=AUTH)
        positions = client.get("/api/positions", headers=AUTH).json()
        assert len(positions) == 1

    def test_close_endpoint_flattens_a_position(self, client):
        opened = client.post("/api/signals", json=_payload(), headers=AUTH).json()
        pid = opened["position"]["id"]
        r = client.post(f"/api/positions/{pid}/close", headers=AUTH)
        assert r.status_code == 200
        assert r.json()["status"] == "CLOSED"
        assert client.get("/api/positions", headers=AUTH).json() == []

    def test_closing_an_unknown_position_is_a_400(self, client):
        r = client.post("/api/positions/does-not-exist/close", headers=AUTH)
        assert r.status_code == 400

    def test_close_all(self, client):
        client.post("/api/signals", json=_payload(), headers=AUTH)
        client.post("/api/signals", json=_payload(), headers=AUTH)
        r = client.post("/api/positions/close-all", headers=AUTH)
        assert len(r.json()) == 2
        assert client.get("/api/positions", headers=AUTH).json() == []

    def test_history_lists_closed_trades(self, client):
        opened = client.post("/api/signals", json=_payload(), headers=AUTH).json()
        client.post(f"/api/positions/{opened['position']['id']}/close", headers=AUTH)
        history = client.get("/api/positions/history", headers=AUTH).json()
        assert len(history) == 1


class TestControl:
    def test_halt_blocks_new_signals(self, client):
        client.post("/api/control/halt", headers=AUTH)
        body = client.post("/api/signals", json=_payload(), headers=AUTH).json()
        assert body["accepted"] is False
        assert client.get("/api/account", headers=AUTH).json()["trading_halted"] is True

    def test_resume_restores_trading(self, client):
        client.post("/api/control/halt", headers=AUTH)
        client.post("/api/control/resume", headers=AUTH)
        body = client.post("/api/signals", json=_payload(), headers=AUTH).json()
        assert body["accepted"] is True


class TestWebsocket:
    def test_rejects_a_bad_token(self, client):
        with pytest.raises(Exception):
            with client.websocket_connect("/api/ws?token=wrong"):
                pass

    def test_streams_account_snapshots(self, client):
        with client.websocket_connect(f"/api/ws?token={TOKEN}") as ws:
            message = ws.receive_json()
            assert message["event"] in {"account", "signal", "position_opened"}
