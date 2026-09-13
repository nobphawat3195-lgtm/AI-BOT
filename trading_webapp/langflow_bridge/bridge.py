"""Client for publishing signals from Langflow (or any Python caller).

Two ways in:

* ``SignalClient`` — a small, dependency-light wrapper for scripts.
* ``publish_signal`` — a flat function suitable for pasting into a
  Langflow "Python Function" component.

Both refuse to send a malformed signal rather than let the bridge
reject it after a round trip.
"""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from typing import Any, Literal, Optional

DEFAULT_BASE = os.getenv("XAU_BRIDGE_URL", "http://127.0.0.1:8000")
DEFAULT_TOKEN = os.getenv("XAU_API_TOKEN", "change-me")

Side = Literal["BUY", "SELL", "HOLD"]
_VALID_SIDES = {"BUY", "SELL", "HOLD"}


class SignalError(ValueError):
    """The signal was malformed, or the bridge could not be reached."""


def build_signal(
    side: str,
    confidence: float,
    symbol: str = "XAUUSD",
    entry: Optional[float] = None,
    stop_loss: Optional[float] = None,
    take_profit: Optional[float] = None,
    rationale: str = "",
    source: str = "langflow",
) -> dict[str, Any]:
    """Validate and normalise a signal payload."""
    side = str(side).strip().upper()
    if side not in _VALID_SIDES:
        raise SignalError(f"side must be one of {sorted(_VALID_SIDES)}, got {side!r}")

    try:
        confidence = float(confidence)
    except (TypeError, ValueError) as exc:
        raise SignalError(f"confidence must be a number, got {confidence!r}") from exc
    if not 0.0 <= confidence <= 1.0:
        raise SignalError(f"confidence must be within [0, 1], got {confidence}")

    payload: dict[str, Any] = {
        "symbol": str(symbol).strip().upper(),
        "side": side,
        "confidence": confidence,
        "rationale": rationale,
        "source": source,
    }
    for key, value in (
        ("entry", entry),
        ("stop_loss", stop_loss),
        ("take_profit", take_profit),
    ):
        if value is not None:
            value = float(value)
            if value <= 0:
                raise SignalError(f"{key} must be positive, got {value}")
            payload[key] = value
    return payload


class SignalClient:
    def __init__(
        self,
        base_url: str = DEFAULT_BASE,
        token: str = DEFAULT_TOKEN,
        timeout: float = 15.0,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.token = token
        self.timeout = timeout

    def _post(self, path: str, payload: dict) -> dict:
        request = urllib.request.Request(
            f"{self.base_url}{path}",
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json", "X-API-Token": self.token},
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", "replace")[:300]
            if exc.code == 401:
                raise SignalError("bridge rejected the API token") from exc
            raise SignalError(f"bridge returned HTTP {exc.code}: {detail}") from exc
        except urllib.error.URLError as exc:
            raise SignalError(f"cannot reach the bridge at {self.base_url}: {exc.reason}") from exc

    def send(self, **kwargs) -> dict:
        """Build, validate and publish a signal. Returns the bridge's verdict."""
        return self._post("/api/signals", build_signal(**kwargs))

    def account(self) -> dict:
        request = urllib.request.Request(
            f"{self.base_url}/api/account", headers={"X-API-Token": self.token}
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.URLError as exc:
            raise SignalError(f"cannot reach the bridge: {exc}") from exc


def publish_signal(
    side: str,
    confidence: float = 0.7,
    symbol: str = "XAUUSD",
    entry: Optional[float] = None,
    stop_loss: Optional[float] = None,
    take_profit: Optional[float] = None,
    rationale: str = "",
    base_url: str = DEFAULT_BASE,
    token: str = DEFAULT_TOKEN,
) -> str:
    """Flat entry point for a Langflow Python Function component.

    Returns a short human-readable line so the flow's output panel shows
    what the bridge decided.
    """
    try:
        result = SignalClient(base_url, token).send(
            side=side,
            confidence=confidence,
            symbol=symbol,
            entry=entry,
            stop_loss=stop_loss,
            take_profit=take_profit,
            rationale=rationale,
        )
    except SignalError as exc:
        return f"ERROR: {exc}"

    verdict = "ACCEPTED" if result.get("accepted") else "REJECTED"
    reason = result.get("reason", "")
    position = result.get("position") or {}
    if position:
        return (
            f"{verdict}: {position.get('side')} {position.get('volume')} lots "
            f"@ {position.get('entry_price')} — {reason}"
        )
    return f"{verdict}: {reason}"


if __name__ == "__main__":  # smoke test against a running bridge
    import argparse

    parser = argparse.ArgumentParser(description="Publish a signal to the XAUUSD bridge.")
    parser.add_argument("side", choices=sorted(_VALID_SIDES))
    parser.add_argument("--confidence", type=float, default=0.75)
    parser.add_argument("--entry", type=float)
    parser.add_argument("--sl", type=float, dest="stop_loss")
    parser.add_argument("--tp", type=float, dest="take_profit")
    parser.add_argument("--rationale", default="manual CLI test")
    parser.add_argument("--url", default=DEFAULT_BASE)
    parser.add_argument("--token", default=DEFAULT_TOKEN)
    args = parser.parse_args()

    print(
        publish_signal(
            side=args.side,
            confidence=args.confidence,
            entry=args.entry,
            stop_loss=args.stop_loss,
            take_profit=args.take_profit,
            rationale=args.rationale,
            base_url=args.url,
            token=args.token,
        )
    )
