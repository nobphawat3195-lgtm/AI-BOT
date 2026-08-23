"""SQLite persistence for positions, signals and the daily equity mark.

Kept synchronous behind a lock: the write volume of a single-symbol bot
is tiny, and this keeps the storage layer easy to reason about.
"""

from __future__ import annotations

import json
import sqlite3
import threading
from datetime import date, datetime, timezone
from typing import Any, Optional

from .models import Position, Signal

_SCHEMA = """
CREATE TABLE IF NOT EXISTS positions (
    id            TEXT PRIMARY KEY,
    symbol        TEXT NOT NULL,
    side          TEXT NOT NULL,
    volume        REAL NOT NULL,
    entry_price   REAL NOT NULL,
    stop_loss     REAL,
    take_profit   REAL,
    opened_at     TEXT NOT NULL,
    closed_at     TEXT,
    close_price   REAL,
    profit        REAL NOT NULL DEFAULT 0,
    status        TEXT NOT NULL DEFAULT 'OPEN'
);
CREATE INDEX IF NOT EXISTS idx_positions_status ON positions(status);

CREATE TABLE IF NOT EXISTS signals (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    payload    TEXT NOT NULL,
    accepted   INTEGER NOT NULL,
    reason     TEXT NOT NULL,
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS day_marks (
    day             TEXT PRIMARY KEY,
    opening_balance REAL NOT NULL
);

CREATE TABLE IF NOT EXISTS account (
    id      INTEGER PRIMARY KEY CHECK (id = 1),
    balance REAL NOT NULL
);
"""


class Store:
    def __init__(self, path: str, start_balance: float) -> None:
        self._lock = threading.RLock()
        self._conn = sqlite3.connect(path, check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        with self._lock:
            self._conn.executescript(_SCHEMA)
            self._conn.execute(
                "INSERT OR IGNORE INTO account (id, balance) VALUES (1, ?)",
                (start_balance,),
            )
            self._conn.commit()

    def close(self) -> None:
        with self._lock:
            self._conn.close()

    # --- account ----------------------------------------------------
    def balance(self) -> float:
        with self._lock:
            row = self._conn.execute("SELECT balance FROM account WHERE id = 1").fetchone()
            return float(row["balance"])

    def adjust_balance(self, delta: float) -> float:
        with self._lock:
            self._conn.execute(
                "UPDATE account SET balance = balance + ? WHERE id = 1", (delta,)
            )
            self._conn.commit()
            return self.balance()

    def opening_balance(self, day: Optional[date] = None) -> float:
        """Balance recorded at the first call of the given UTC day."""
        day = day or datetime.now(timezone.utc).date()
        key = day.isoformat()
        with self._lock:
            row = self._conn.execute(
                "SELECT opening_balance FROM day_marks WHERE day = ?", (key,)
            ).fetchone()
            if row is not None:
                return float(row["opening_balance"])
            current = self.balance()
            self._conn.execute(
                "INSERT INTO day_marks (day, opening_balance) VALUES (?, ?)",
                (key, current),
            )
            self._conn.commit()
            return current

    # --- positions --------------------------------------------------
    def add_position(self, position: Position) -> None:
        with self._lock:
            self._conn.execute(
                """INSERT INTO positions
                   (id, symbol, side, volume, entry_price, stop_loss, take_profit,
                    opened_at, closed_at, close_price, profit, status)
                   VALUES (?,?,?,?,?,?,?,?,?,?,?,?)""",
                (
                    position.id,
                    position.symbol,
                    position.side,
                    position.volume,
                    position.entry_price,
                    position.stop_loss,
                    position.take_profit,
                    position.opened_at.isoformat(),
                    None,
                    None,
                    position.profit,
                    position.status,
                ),
            )
            self._conn.commit()

    def close_position(self, position_id: str, close_price: float, profit: float) -> None:
        with self._lock:
            self._conn.execute(
                """UPDATE positions
                   SET status = 'CLOSED', closed_at = ?, close_price = ?, profit = ?
                   WHERE id = ?""",
                (datetime.now(timezone.utc).isoformat(), close_price, profit, position_id),
            )
            self._conn.commit()

    def _row_to_position(self, row: sqlite3.Row) -> Position:
        data: dict[str, Any] = dict(row)
        return Position.model_validate(data)

    def open_positions(self) -> list[Position]:
        with self._lock:
            rows = self._conn.execute(
                "SELECT * FROM positions WHERE status = 'OPEN' ORDER BY opened_at"
            ).fetchall()
        return [self._row_to_position(r) for r in rows]

    def get_position(self, position_id: str) -> Optional[Position]:
        with self._lock:
            row = self._conn.execute(
                "SELECT * FROM positions WHERE id = ?", (position_id,)
            ).fetchone()
        return self._row_to_position(row) if row else None

    def history(self, limit: int = 100) -> list[Position]:
        with self._lock:
            rows = self._conn.execute(
                "SELECT * FROM positions WHERE status = 'CLOSED' "
                "ORDER BY closed_at DESC LIMIT ?",
                (limit,),
            ).fetchall()
        return [self._row_to_position(r) for r in rows]

    def realised_pnl_today(self) -> float:
        today = datetime.now(timezone.utc).date().isoformat()
        with self._lock:
            row = self._conn.execute(
                "SELECT COALESCE(SUM(profit), 0) AS total FROM positions "
                "WHERE status = 'CLOSED' AND substr(closed_at, 1, 10) = ?",
                (today,),
            ).fetchone()
        return float(row["total"])

    # --- signals ----------------------------------------------------
    def log_signal(self, signal: Signal, accepted: bool, reason: str) -> None:
        with self._lock:
            self._conn.execute(
                "INSERT INTO signals (payload, accepted, reason, created_at) VALUES (?,?,?,?)",
                (
                    signal.model_dump_json(),
                    int(accepted),
                    reason,
                    datetime.now(timezone.utc).isoformat(),
                ),
            )
            self._conn.commit()

    def recent_signals(self, limit: int = 50) -> list[dict[str, Any]]:
        with self._lock:
            rows = self._conn.execute(
                "SELECT * FROM signals ORDER BY id DESC LIMIT ?", (limit,)
            ).fetchall()
        return [
            {
                "signal": json.loads(r["payload"]),
                "accepted": bool(r["accepted"]),
                "reason": r["reason"],
                "created_at": r["created_at"],
            }
            for r in rows
        ]
