"""Runtime configuration, loaded from environment / .env.

Safety-critical defaults live here. ``broker`` stays on ``paper`` and
``allow_live`` stays off unless the operator explicitly opts in, so a
fresh checkout can never place a real order by accident.
"""

from functools import lru_cache
from typing import Literal

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env", env_prefix="XAU_", extra="ignore"
    )

    # --- API access -------------------------------------------------
    api_token: str = Field(
        default="change-me",
        description="Shared secret required in the X-API-Token header.",
    )
    cors_origins: list[str] = Field(default_factory=lambda: ["*"])

    # --- Instrument -------------------------------------------------
    symbol: str = "XAUUSD"
    contract_size: float = Field(
        default=100.0, description="Ounces per 1.00 lot for gold."
    )
    min_lot: float = 0.01
    max_lot: float = 5.0
    lot_step: float = 0.01

    # --- Broker wiring ----------------------------------------------
    broker: Literal["paper", "metaapi", "ea"] = "paper"
    allow_live: bool = Field(
        default=False,
        description="Master switch. Live orders are refused while this is False.",
    )
    metaapi_token: str = ""
    metaapi_account_id: str = ""
    metaapi_region: str = "london"
    metaapi_timeout: float = 20.0

    # --- Risk limits ------------------------------------------------
    risk_percent: float = Field(
        default=0.5, description="Account equity risked per trade, in percent."
    )
    max_open_positions: int = 2
    max_daily_loss_percent: float = Field(
        default=3.0, description="Halt trading once the day is down this much."
    )
    max_spread_usd: float = Field(
        default=0.60, description="Reject entries when the spread is wider."
    )
    min_confidence: float = Field(
        default=0.60, description="Reject signals below this confidence."
    )
    default_sl_usd: float = Field(
        default=3.0, description="Stop distance used when a signal omits one."
    )
    default_tp_r: float = Field(
        default=1.5, description="Take-profit as a multiple of the stop distance."
    )
    trading_hours_utc: str = Field(
        default="00:00-23:59",
        description="Comma-separated UTC windows, e.g. '07:00-16:00,18:00-21:00'.",
    )

    # --- Storage ----------------------------------------------------
    db_path: str = "xauusd_bot.db"
    paper_start_balance: float = 10_000.0

    @field_validator("risk_percent", "max_daily_loss_percent")
    @classmethod
    def _sane_percent(cls, v: float) -> float:
        if not 0 < v <= 100:
            raise ValueError("percent must be within (0, 100]")
        return v

    @field_validator("min_confidence")
    @classmethod
    def _sane_confidence(cls, v: float) -> float:
        if not 0 <= v <= 1:
            raise ValueError("confidence must be within [0, 1]")
        return v

    @property
    def live_enabled(self) -> bool:
        """Live trading needs both a real broker *and* the master switch."""
        return self.broker != "paper" and self.allow_live


@lru_cache
def get_settings() -> Settings:
    return Settings()
