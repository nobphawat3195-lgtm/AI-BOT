"""Langflow bridge client: payload validation before anything leaves the process."""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "langflow_bridge"))

from bridge import SignalError, build_signal  # noqa: E402


class TestBuildSignal:
    def test_minimal_signal(self):
        payload = build_signal(side="buy", confidence=0.8)
        assert payload["side"] == "BUY"
        assert payload["symbol"] == "XAUUSD"
        assert payload["confidence"] == 0.8
        assert "entry" not in payload

    def test_normalises_case_and_whitespace(self):
        payload = build_signal(side=" sell ", confidence=0.7, symbol=" xauusd ")
        assert payload["side"] == "SELL"
        assert payload["symbol"] == "XAUUSD"

    def test_includes_optional_levels(self):
        payload = build_signal(
            side="BUY", confidence=0.9, entry=2400, stop_loss=2395, take_profit=2410
        )
        assert payload["entry"] == 2400.0
        assert payload["stop_loss"] == 2395.0
        assert payload["take_profit"] == 2410.0

    @pytest.mark.parametrize("side", ["LONG", "", "buy!", None, 5])
    def test_rejects_unknown_side(self, side):
        with pytest.raises(SignalError, match="side must be"):
            build_signal(side=side, confidence=0.8)

    @pytest.mark.parametrize("confidence", [-0.1, 1.5, 42])
    def test_rejects_out_of_range_confidence(self, confidence):
        with pytest.raises(SignalError, match=r"within \[0, 1\]"):
            build_signal(side="BUY", confidence=confidence)

    def test_rejects_non_numeric_confidence(self):
        with pytest.raises(SignalError, match="must be a number"):
            build_signal(side="BUY", confidence="high")

    @pytest.mark.parametrize("field", ["entry", "stop_loss", "take_profit"])
    def test_rejects_non_positive_prices(self, field):
        with pytest.raises(SignalError, match="must be positive"):
            build_signal(side="BUY", confidence=0.8, **{field: 0})

    def test_hold_is_a_valid_side(self):
        assert build_signal(side="HOLD", confidence=0.5)["side"] == "HOLD"
