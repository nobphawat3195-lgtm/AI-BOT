"""Deterministic checks applied to a backtest report.

These run with no API key and no network. Each check returns a verdict
plus the number that produced it, so a rejection is always explainable.
The LLM layer in ``evaluate.py`` only adds commentary on top — it never
overrides a check.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable, Literal, Optional

Level = Literal["pass", "warn", "fail"]

# Ordering used to reduce many check levels into one overall verdict.
_SEVERITY = {"pass": 0, "warn": 1, "fail": 2}


@dataclass(frozen=True)
class Finding:
    name: str
    level: Level
    message: str
    value: Optional[float] = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "level": self.level,
            "message": self.message,
            "value": self.value,
        }


@dataclass(frozen=True)
class Thresholds:
    min_trades: int = 30
    min_profit_factor: float = 1.2
    max_drawdown_percent: float = 20.0
    min_win_rate: float = 0.25
    max_risk_percent: float = 2.0
    # A test profit factor this far below train is treated as overfitting.
    overfit_pf_ratio: float = 0.6


def _get(summary: dict, key: str, default: float = 0.0) -> float:
    value = summary.get(key)
    return default if value is None else float(value)


def check_sample_size(report: dict, t: Thresholds) -> Finding:
    trades = int(_get(report.get("train", {}), "trades"))
    if trades < t.min_trades:
        return Finding(
            "sample_size",
            "fail",
            f"only {trades} trades — below {t.min_trades}, the result is noise",
            trades,
        )
    return Finding("sample_size", "pass", f"{trades} trades is an adequate sample", trades)


def check_profit_factor(report: dict, t: Thresholds) -> Finding:
    pf = report.get("train", {}).get("profit_factor")
    if pf is None:
        return Finding("profit_factor", "warn", "no losing trades — profit factor undefined")
    pf = float(pf)
    if pf < 1.0:
        return Finding("profit_factor", "fail", f"profit factor {pf:.2f} loses money", pf)
    if pf < t.min_profit_factor:
        return Finding(
            "profit_factor",
            "warn",
            f"profit factor {pf:.2f} is below the {t.min_profit_factor:.2f} target",
            pf,
        )
    return Finding("profit_factor", "pass", f"profit factor {pf:.2f}", pf)


def check_drawdown(report: dict, t: Thresholds) -> Finding:
    dd = _get(report.get("train", {}), "max_drawdown_percent")
    if dd > t.max_drawdown_percent:
        return Finding(
            "drawdown",
            "fail",
            f"max drawdown {dd:.1f}% exceeds the {t.max_drawdown_percent:.0f}% limit",
            dd,
        )
    if dd > t.max_drawdown_percent * 0.75:
        return Finding("drawdown", "warn", f"max drawdown {dd:.1f}% is close to the limit", dd)
    return Finding("drawdown", "pass", f"max drawdown {dd:.1f}%", dd)


def check_win_rate(report: dict, t: Thresholds) -> Finding:
    wr = _get(report.get("train", {}), "win_rate")
    if wr < t.min_win_rate:
        return Finding(
            "win_rate",
            "warn",
            f"win rate {wr:.0%} is low — the edge depends on rare large wins",
            wr,
        )
    return Finding("win_rate", "pass", f"win rate {wr:.0%}", wr)


def check_out_of_sample(report: dict, t: Thresholds) -> Finding:
    test = report.get("test") or {}
    if not test or int(_get(test, "trades")) == 0:
        return Finding(
            "out_of_sample",
            "fail",
            "the test slice produced no trades — the result is unverified",
            0,
        )

    test_net = _get(test, "net_profit")
    if test_net <= 0:
        return Finding(
            "out_of_sample",
            "fail",
            f"loses money out of sample (net {test_net:.2f}) — overfitted",
            test_net,
        )
    return Finding("out_of_sample", "pass", f"profitable out of sample ({test_net:.2f})", test_net)


def check_overfitting(report: dict, t: Thresholds) -> Finding:
    train_pf = report.get("train", {}).get("profit_factor")
    test_pf = report.get("test", {}).get("profit_factor")
    if train_pf is None or test_pf is None:
        return Finding("overfitting", "warn", "cannot compare train and test profit factors")

    train_pf, test_pf = float(train_pf), float(test_pf)
    if train_pf <= 0:
        return Finding("overfitting", "warn", "training profit factor is zero")

    ratio = test_pf / train_pf
    if ratio < t.overfit_pf_ratio:
        return Finding(
            "overfitting",
            "fail",
            (
                f"test profit factor {test_pf:.2f} is only {ratio:.0%} of "
                f"train {train_pf:.2f} — overfitted"
            ),
            ratio,
        )
    return Finding(
        "overfitting", "pass", f"test holds {ratio:.0%} of training performance", ratio
    )


def check_risk_setting(report: dict, t: Thresholds) -> Finding:
    risk = _get(report.get("best_params", {}), "risk_percent")
    if risk <= 0:
        return Finding("risk_setting", "warn", "no risk_percent recorded")
    if risk > t.max_risk_percent:
        return Finding(
            "risk_setting",
            "fail",
            f"risk {risk:.2f}% per trade exceeds the {t.max_risk_percent:.2f}% ceiling",
            risk,
        )
    return Finding("risk_setting", "pass", f"risk {risk:.2f}% per trade", risk)


CHECKS: tuple[Callable[[dict, Thresholds], Finding], ...] = (
    check_sample_size,
    check_profit_factor,
    check_drawdown,
    check_win_rate,
    check_out_of_sample,
    check_overfitting,
    check_risk_setting,
)


def run_checks(report: dict, thresholds: Thresholds | None = None) -> list[Finding]:
    t = thresholds or Thresholds()
    return [check(report, t) for check in CHECKS]


def overall(findings: list[Finding]) -> Level:
    """Worst level wins — one failure sinks the run."""
    if not findings:
        return "fail"
    return max(findings, key=lambda f: _SEVERITY[f.level]).level


def verdict_text(level: Level) -> str:
    return {
        "pass": "APPROVED — worth forward-testing on a demo account",
        "warn": "CAUTION — usable only with the warnings below understood",
        "fail": "REJECTED — do not trade these parameters",
    }[level]
