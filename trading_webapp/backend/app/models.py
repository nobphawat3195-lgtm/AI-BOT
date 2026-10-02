"""Wire formats shared by the API, the EA bridge and the Langflow client."""

from datetime import datetime, timezone
from enum import Enum
from typing import Literal, Optional

from pydantic import BaseModel, Field, field_validator


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Side(str, Enum):
    BUY = "BUY"
    SELL = "SELL"
    HOLD = "HOLD"


class Signal(BaseModel):
    """An intent published by an upstream analyst (Langflow, TradingAgents, ...)."""

    symbol: str = "XAUUSD"
    side: Side
    confidence: float = Field(ge=0.0, le=1.0)
    entry: Optional[float] = Field(default=None, gt=0)
    stop_loss: Optional[float] = Field(default=None, gt=0)
    take_profit: Optional[float] = Field(default=None, gt=0)
    rationale: str = ""
    source: str = "manual"
    created_at: datetime = Field(default_factory=_utcnow)

    @field_validator("symbol")
    @classmethod
    def _upper(cls, v: str) -> str:
        return v.upper().strip()


class Quote(BaseModel):
    symbol: str
    bid: float = Field(gt=0)
    ask: float = Field(gt=0)
    ts: datetime = Field(default_factory=_utcnow)

    @property
    def spread(self) -> float:
        return self.ask - self.bid

    @property
    def mid(self) -> float:
        return (self.ask + self.bid) / 2


class Position(BaseModel):
    id: str
    symbol: str
    side: Literal["BUY", "SELL"]
    volume: float
    entry_price: float
    stop_loss: Optional[float] = None
    take_profit: Optional[float] = None
    opened_at: datetime = Field(default_factory=_utcnow)
    closed_at: Optional[datetime] = None
    close_price: Optional[float] = None
    profit: float = 0.0
    status: Literal["OPEN", "CLOSED"] = "OPEN"


class AccountState(BaseModel):
    balance: float
    equity: float
    open_positions: int
    day_pnl: float
    day_pnl_percent: float
    trading_halted: bool
    halt_reason: str = ""
    broker: str
    live_enabled: bool
    symbol: str


class RiskDecision(BaseModel):
    """Outcome of the pre-trade check. ``volume`` is only set when approved."""

    approved: bool
    reason: str = ""
    volume: float = 0.0
    stop_loss: Optional[float] = None
    take_profit: Optional[float] = None


class SignalResult(BaseModel):
    accepted: bool
    reason: str
    signal: Signal
    risk: RiskDecision
    position: Optional[Position] = None
