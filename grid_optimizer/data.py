"""Bar loading for the optimiser.

CSV is the primary path so runs are reproducible and offline. Yahoo is
offered as a convenience fetch; the synthetic generator keeps the tests
and a first-run demo working with no network at all.
"""

from __future__ import annotations

import csv
import json
import math
import random
import urllib.request
from pathlib import Path

from strategy import Bar

_YAHOO_URL = "https://query1.finance.yahoo.com/v8/finance/chart/GC=F"
_ALIASES = {
    "time": {"time", "date", "datetime", "timestamp", "<date>"},
    "open": {"open", "o", "<open>"},
    "high": {"high", "h", "<high>"},
    "low": {"low", "l", "<low>"},
    "close": {"close", "c", "price", "<close>"},
}


def load_csv(path: str | Path) -> list[Bar]:
    """Read OHLC bars from ``path``.

    Column names are matched case-insensitively against common exports
    (MetaTrader, TradingView, yfinance), so most files load unchanged.
    """
    path = Path(path)
    if not path.is_file():
        raise FileNotFoundError(f"no such CSV: {path}")

    with path.open(newline="", encoding="utf-8-sig") as fh:
        sample = fh.read(4096)
        fh.seek(0)
        try:
            dialect = csv.Sniffer().sniff(sample, delimiters=",;\t")
        except csv.Error:
            dialect = csv.excel
        reader = csv.DictReader(fh, dialect=dialect)
        if not reader.fieldnames:
            raise ValueError(f"{path} has no header row")

        mapping: dict[str, str] = {}
        for field, names in _ALIASES.items():
            for column in reader.fieldnames:
                if column.strip().lower() in names:
                    mapping[field] = column
                    break

        missing = {"open", "high", "low", "close"} - mapping.keys()
        if missing:
            raise ValueError(
                f"{path} is missing column(s) {sorted(missing)}; found {reader.fieldnames}"
            )

        bars: list[Bar] = []
        for row_number, row in enumerate(reader, start=2):
            try:
                bar = Bar(
                    time=str(row.get(mapping.get("time", ""), row_number)),
                    open=float(row[mapping["open"]]),
                    high=float(row[mapping["high"]]),
                    low=float(row[mapping["low"]]),
                    close=float(row[mapping["close"]]),
                )
            except (TypeError, ValueError):
                continue  # skip blank or malformed rows rather than abort
            if bar.high >= bar.low > 0:
                bars.append(bar)

    if not bars:
        raise ValueError(f"{path} produced no usable bars")
    return bars


def fetch_yahoo(interval: str = "1h", range_: str = "2y", timeout: float = 30.0) -> list[Bar]:
    """Download gold futures bars. Requires network access."""
    url = f"{_YAHOO_URL}?interval={interval}&range={range_}"
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 xauusd-opt"})
    with urllib.request.urlopen(request, timeout=timeout) as resp:
        payload = json.loads(resp.read().decode())

    result = payload["chart"]["result"][0]
    stamps = result["timestamp"]
    q = result["indicators"]["quote"][0]

    bars: list[Bar] = []
    for i, ts in enumerate(stamps):
        o, h, l, c = q["open"][i], q["high"][i], q["low"][i], q["close"][i]
        if None in (o, h, l, c):
            continue
        bars.append(Bar(time=str(ts), open=float(o), high=float(h), low=float(l), close=float(c)))
    if not bars:
        raise ValueError("Yahoo returned no usable bars")
    return bars


def synthetic(n: int = 1500, seed: int = 7, start: float = 2400.0) -> list[Bar]:
    """Deterministic random-walk bars — for tests and offline demos.

    Not a market model. Results from this data say nothing about a real
    edge; it exists so the pipeline can be exercised without a download.
    """
    rng = random.Random(seed)
    bars: list[Bar] = []
    price = start
    for i in range(n):
        drift = math.sin(i / 90) * 0.35
        step = rng.gauss(drift, 2.2)
        open_ = price
        close = max(50.0, price + step)
        spread = abs(rng.gauss(0, 1.6)) + 0.4
        high = max(open_, close) + spread
        low = min(open_, close) - spread
        bars.append(Bar(time=str(i), open=open_, high=high, low=max(1.0, low), close=close))
        price = close
    return bars


def split(bars: list[Bar], train_fraction: float = 0.7) -> tuple[list[Bar], list[Bar]]:
    """Chronological train/test split — never shuffled."""
    if not 0 < train_fraction < 1:
        raise ValueError("train_fraction must be within (0, 1)")
    cut = int(len(bars) * train_fraction)
    return bars[:cut], bars[cut:]
