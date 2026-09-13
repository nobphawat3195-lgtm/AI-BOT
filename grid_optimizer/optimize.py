"""Optuna search over the XAUUSD strategy parameters.

Optimises a drawdown-penalised score on the training slice, then
reports the untouched test slice so an overfitted winner is visible
rather than hidden.

Usage:
    python optimize.py --trials 100
    python optimize.py --csv data/XAUUSD_H1.csv --trials 300
    python optimize.py --source yahoo --trials 200 --out best_params.json
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path

import optuna

from data import fetch_yahoo, load_csv, split, synthetic
from strategy import BacktestResult, Params, backtest

log = logging.getLogger("optimizer")

MIN_TRADES = 20  # below this a result is noise, not an edge


def score(result: BacktestResult) -> float:
    """Rank a run: profit per unit of drawdown, with a thin-sample penalty.

    Returns a large negative number for unusable runs so Optuna walks
    away from that region instead of treating it as merely mediocre.
    """
    if len(result.trades) < MIN_TRADES:
        return -1e6
    if result.end_balance <= 0:
        return -1e6

    drawdown = max(result.max_drawdown_percent, 1.0)  # floor avoids divide-by-zero spikes
    return_percent = result.net_profit / result.start_balance * 100
    return return_percent / drawdown


def build_objective(train_bars, start_balance: float):
    def objective(trial: optuna.Trial) -> float:
        params = Params(
            atr_period=trial.suggest_int("atr_period", 7, 28),
            breakout_atr=trial.suggest_float("breakout_atr", 0.1, 2.0, step=0.05),
            stop_atr=trial.suggest_float("stop_atr", 0.5, 3.0, step=0.05),
            reward_risk=trial.suggest_float("reward_risk", 0.8, 4.0, step=0.1),
            lookback=trial.suggest_int("lookback", 8, 60),
            risk_percent=trial.suggest_float("risk_percent", 0.25, 2.0, step=0.25),
        )
        result = backtest(train_bars, params, start_balance=start_balance)
        trial.set_user_attr("summary", result.summary())
        return score(result)

    return objective


def load_bars(args) -> list:
    if args.csv:
        log.info("loading bars from %s", args.csv)
        return load_csv(args.csv)
    if args.source == "yahoo":
        log.info("downloading gold bars from Yahoo (%s, %s)", args.interval, args.range)
        return fetch_yahoo(interval=args.interval, range_=args.range)
    log.warning(
        "using SYNTHETIC bars — results are a pipeline smoke test, not a real edge"
    )
    return synthetic(n=args.synthetic_bars)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Optimise XAUUSD strategy parameters.")
    parser.add_argument("--csv", help="OHLC CSV file (preferred — reproducible).")
    parser.add_argument(
        "--source",
        choices=["synthetic", "yahoo"],
        default="synthetic",
        help="Where to get bars when --csv is not given.",
    )
    parser.add_argument("--interval", default="1h", help="Yahoo bar interval.")
    parser.add_argument("--range", default="2y", help="Yahoo history range.")
    parser.add_argument("--synthetic-bars", type=int, default=1500)
    parser.add_argument("--trials", type=int, default=100)
    parser.add_argument("--balance", type=float, default=10_000.0)
    parser.add_argument("--train-fraction", type=float, default=0.7)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--out", default="best_params.json")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.WARNING if args.quiet else logging.INFO,
        format="%(levelname)-7s %(message)s",
    )
    optuna.logging.set_verbosity(
        optuna.logging.WARNING if args.quiet else optuna.logging.WARNING
    )

    try:
        bars = load_bars(args)
    except (OSError, ValueError) as exc:
        log.error("could not load bars: %s", exc)
        return 2

    train_bars, test_bars = split(bars, args.train_fraction)
    log.info("%d bars total — %d train / %d test", len(bars), len(train_bars), len(test_bars))
    if len(train_bars) < 200:
        log.error("not enough training bars (%d); supply more history", len(train_bars))
        return 2

    study = optuna.create_study(
        direction="maximize",
        sampler=optuna.samplers.TPESampler(seed=args.seed),
    )
    study.optimize(
        build_objective(train_bars, args.balance),
        n_trials=args.trials,
        show_progress_bar=not args.quiet,
    )

    if study.best_value <= -1e5:
        log.error(
            "no trial produced at least %d trades — widen the search or add history",
            MIN_TRADES,
        )
        return 1

    best = Params(**study.best_params)
    train_result = backtest(train_bars, best, start_balance=args.balance)
    test_result = backtest(test_bars, best, start_balance=args.balance)

    report = {
        "best_params": study.best_params,
        "best_score": round(study.best_value, 4),
        "train": train_result.summary(),
        "test": test_result.summary(),
        "trials": len(study.trials),
        "bars": {"total": len(bars), "train": len(train_bars), "test": len(test_bars)},
        "data_source": args.csv or args.source,
    }

    Path(args.out).write_text(json.dumps(report, indent=2), encoding="utf-8")

    print("\n" + "=" * 62)
    print("BEST PARAMETERS")
    print("=" * 62)
    for key, value in study.best_params.items():
        print(f"  {key:<16} {value}")
    print(f"\n  score (train)    {study.best_value:.4f}")
    print("\n  TRAIN  ", json.dumps(train_result.summary()))
    print("  TEST   ", json.dumps(test_result.summary()))

    train_pf = train_result.profit_factor
    test_pf = test_result.profit_factor
    if test_result.trades and test_pf < 1.0 <= train_pf:
        print(
            "\n  WARNING: profitable in training but not in test — "
            "these parameters are overfitted. Do not trade them."
        )
    elif not test_result.trades:
        print("\n  WARNING: the test slice produced no trades; the result is unverified.")
    print("=" * 62)
    print(f"\nwritten to {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
