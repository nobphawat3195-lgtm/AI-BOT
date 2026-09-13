"""Evaluate a backtest report and give a go / no-go verdict.

The rule checks in ``checks.py`` decide the verdict on their own. An
LLM, when a key is available, is asked only for plain-language
commentary — it cannot turn a REJECTED run into an approved one.

Usage:
    python evaluate.py best_params.json
    python evaluate.py best_params.json --llm --lang th
    python evaluate.py best_params.json --json
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

from checks import Thresholds, overall, run_checks, verdict_text

_ICON = {"pass": "[OK]  ", "warn": "[WARN]", "fail": "[FAIL]"}


def load_report(path: str | Path) -> dict:
    path = Path(path)
    if not path.is_file():
        raise FileNotFoundError(f"no such report: {path}")
    try:
        report = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ValueError(f"{path} is not valid JSON: {exc}") from exc
    if not isinstance(report, dict):
        raise ValueError(f"{path} should contain a JSON object")
    if "train" not in report:
        raise ValueError(
            f"{path} has no 'train' section — expected the output of grid_optimizer/optimize.py"
        )
    return report


def llm_commentary(report: dict, findings: list, language: str = "en") -> str:
    """Ask Claude to explain the findings. Returns '' when unavailable."""
    api_key = os.getenv("ANTHROPIC_API_KEY")
    if not api_key:
        return ""
    try:
        import anthropic
    except ImportError:
        return "(install the 'anthropic' package for LLM commentary)"

    lang_line = (
        "Answer in Thai, in simple language for a non-programmer."
        if language == "th"
        else "Answer in English, in plain language for a non-programmer."
    )
    prompt = (
        "You are reviewing an automated trading strategy backtest.\n\n"
        f"Report:\n{json.dumps(report, indent=2)}\n\n"
        f"Automated checks:\n{json.dumps([f.to_dict() for f in findings], indent=2)}\n\n"
        "In at most 150 words, explain the single biggest risk in trading this "
        "strategy with real money, and what the operator should verify next. "
        "Do not contradict the automated checks. Do not give financial advice.\n"
        f"{lang_line}"
    )
    try:
        client = anthropic.Anthropic(api_key=api_key)
        response = client.messages.create(
            model=os.getenv("EVAL_MODEL", "claude-sonnet-4-5"),
            max_tokens=500,
            messages=[{"role": "user", "content": prompt}],
        )
        return "".join(
            block.text for block in response.content if getattr(block, "type", "") == "text"
        ).strip()
    except Exception as exc:  # any client/network/auth failure
        return f"(LLM commentary unavailable: {type(exc).__name__}: {exc})"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Evaluate a grid_optimizer report and give a go / no-go verdict."
    )
    parser.add_argument("report", help="Path to best_params.json")
    parser.add_argument("--llm", action="store_true", help="Add LLM commentary (needs ANTHROPIC_API_KEY).")
    parser.add_argument("--lang", choices=["en", "th"], default="en")
    parser.add_argument("--json", action="store_true", dest="as_json", help="Machine-readable output.")
    parser.add_argument("--min-trades", type=int, default=30)
    parser.add_argument("--max-drawdown", type=float, default=20.0)
    parser.add_argument("--min-profit-factor", type=float, default=1.2)
    args = parser.parse_args(argv)

    try:
        report = load_report(args.report)
    except (OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    thresholds = Thresholds(
        min_trades=args.min_trades,
        max_drawdown_percent=args.max_drawdown,
        min_profit_factor=args.min_profit_factor,
    )
    findings = run_checks(report, thresholds)
    level = overall(findings)
    commentary = llm_commentary(report, findings, args.lang) if args.llm else ""

    if args.as_json:
        print(json.dumps(
            {
                "verdict": level,
                "summary": verdict_text(level),
                "findings": [f.to_dict() for f in findings],
                "commentary": commentary,
            },
            indent=2,
            ensure_ascii=False,
        ))
    else:
        print("\n" + "=" * 66)
        print("BACKTEST EVALUATION")
        print("=" * 66)
        for finding in findings:
            print(f"  {_ICON[finding.level]} {finding.name:<16} {finding.message}")
        print("-" * 66)
        print(f"  VERDICT: {verdict_text(level)}")
        if commentary:
            print("-" * 66)
            print(commentary)
        print("=" * 66 + "\n")

    # Exit code lets CI gate on the verdict: 0 pass, 1 warn, 3 fail.
    return {"pass": 0, "warn": 1, "fail": 3}[level]


if __name__ == "__main__":
    sys.exit(main())
