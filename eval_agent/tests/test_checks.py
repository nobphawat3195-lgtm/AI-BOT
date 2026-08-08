"""Evaluation rules — a rejection must always be traceable to a number."""

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from checks import (  # noqa: E402
    Thresholds,
    check_drawdown,
    check_out_of_sample,
    check_overfitting,
    check_profit_factor,
    check_risk_setting,
    check_sample_size,
    overall,
    run_checks,
    verdict_text,
)
from evaluate import load_report, main  # noqa: E402

T = Thresholds()


def _report(**overrides) -> dict:
    report = {
        "best_params": {"risk_percent": 0.5},
        "train": {
            "trades": 60,
            "net_profit": 1500.0,
            "win_rate": 0.55,
            "profit_factor": 1.8,
            "max_drawdown_percent": 8.0,
        },
        "test": {
            "trades": 25,
            "net_profit": 600.0,
            "win_rate": 0.52,
            "profit_factor": 1.6,
            "max_drawdown_percent": 9.0,
        },
    }
    for section, values in overrides.items():
        if isinstance(values, dict):
            report.setdefault(section, {}).update(values)
        else:
            report[section] = values
    return report


class TestSampleSize:
    def test_passes_with_enough_trades(self):
        assert check_sample_size(_report(), T).level == "pass"

    def test_fails_on_a_thin_sample(self):
        finding = check_sample_size(_report(train={"trades": 5}), T)
        assert finding.level == "fail"
        assert "noise" in finding.message


class TestProfitFactor:
    def test_passes_above_target(self):
        assert check_profit_factor(_report(), T).level == "pass"

    def test_fails_below_one(self):
        finding = check_profit_factor(_report(train={"profit_factor": 0.8}), T)
        assert finding.level == "fail"
        assert "loses money" in finding.message

    def test_warns_between_one_and_target(self):
        assert check_profit_factor(_report(train={"profit_factor": 1.1}), T).level == "warn"

    def test_warns_when_undefined(self):
        assert check_profit_factor(_report(train={"profit_factor": None}), T).level == "warn"


class TestDrawdown:
    def test_passes_when_shallow(self):
        assert check_drawdown(_report(), T).level == "pass"

    def test_fails_when_over_the_limit(self):
        finding = check_drawdown(_report(train={"max_drawdown_percent": 35.0}), T)
        assert finding.level == "fail"
        assert finding.value == 35.0

    def test_warns_when_near_the_limit(self):
        assert check_drawdown(_report(train={"max_drawdown_percent": 17.0}), T).level == "warn"


class TestOutOfSample:
    def test_passes_when_profitable(self):
        assert check_out_of_sample(_report(), T).level == "pass"

    def test_fails_without_test_trades(self):
        finding = check_out_of_sample(_report(test={"trades": 0}), T)
        assert finding.level == "fail"
        assert "unverified" in finding.message

    def test_fails_when_losing_out_of_sample(self):
        finding = check_out_of_sample(_report(test={"net_profit": -400.0}), T)
        assert finding.level == "fail"
        assert "overfitted" in finding.message

    def test_fails_when_the_test_section_is_missing(self):
        report = _report()
        del report["test"]
        assert check_out_of_sample(report, T).level == "fail"


class TestOverfitting:
    def test_passes_when_test_holds_up(self):
        assert check_overfitting(_report(), T).level == "pass"

    def test_fails_on_a_large_gap(self):
        finding = check_overfitting(
            _report(train={"profit_factor": 3.0}, test={"profit_factor": 1.0}), T
        )
        assert finding.level == "fail"
        assert "overfitted" in finding.message

    def test_warns_when_incomparable(self):
        assert check_overfitting(_report(test={"profit_factor": None}), T).level == "warn"


class TestRiskSetting:
    def test_passes_at_a_conservative_risk(self):
        assert check_risk_setting(_report(), T).level == "pass"

    def test_fails_above_the_ceiling(self):
        finding = check_risk_setting(_report(best_params={"risk_percent": 5.0}), T)
        assert finding.level == "fail"


class TestOverall:
    def test_healthy_report_passes(self):
        assert overall(run_checks(_report())) == "pass"

    def test_one_failure_sinks_the_run(self):
        assert overall(run_checks(_report(train={"profit_factor": 0.5}))) == "fail"

    def test_warnings_alone_give_caution(self):
        assert overall(run_checks(_report(train={"win_rate": 0.1}))) == "warn"

    def test_empty_findings_fail_closed(self):
        assert overall([]) == "fail"

    @pytest.mark.parametrize("level", ["pass", "warn", "fail"])
    def test_every_level_has_text(self, level):
        assert verdict_text(level)

    def test_all_checks_run(self):
        assert len(run_checks(_report())) == 7


class TestCli:
    def test_loads_a_valid_report(self, tmp_path):
        path = tmp_path / "r.json"
        path.write_text(json.dumps(_report()), encoding="utf-8")
        assert load_report(path)["train"]["trades"] == 60

    def test_missing_file_raises(self, tmp_path):
        with pytest.raises(FileNotFoundError):
            load_report(tmp_path / "nope.json")

    def test_malformed_json_raises(self, tmp_path):
        path = tmp_path / "bad.json"
        path.write_text("{not json", encoding="utf-8")
        with pytest.raises(ValueError, match="not valid JSON"):
            load_report(path)

    def test_report_without_train_section_raises(self, tmp_path):
        path = tmp_path / "empty.json"
        path.write_text("{}", encoding="utf-8")
        with pytest.raises(ValueError, match="no 'train' section"):
            load_report(path)

    def test_exit_code_zero_on_pass(self, tmp_path, capsys):
        path = tmp_path / "good.json"
        path.write_text(json.dumps(_report()), encoding="utf-8")
        assert main([str(path)]) == 0
        assert "APPROVED" in capsys.readouterr().out

    def test_exit_code_three_on_fail(self, tmp_path, capsys):
        path = tmp_path / "bad.json"
        path.write_text(json.dumps(_report(test={"net_profit": -100.0})), encoding="utf-8")
        assert main([str(path)]) == 3
        assert "REJECTED" in capsys.readouterr().out

    def test_exit_code_two_on_unreadable_input(self, tmp_path, capsys):
        assert main([str(tmp_path / "missing.json")]) == 2

    def test_json_output_is_parseable(self, tmp_path, capsys):
        path = tmp_path / "r.json"
        path.write_text(json.dumps(_report()), encoding="utf-8")
        main([str(path), "--json"])
        payload = json.loads(capsys.readouterr().out)
        assert payload["verdict"] == "pass"
        assert len(payload["findings"]) == 7

    def test_llm_is_skipped_without_a_key(self, tmp_path, capsys, monkeypatch):
        monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
        path = tmp_path / "r.json"
        path.write_text(json.dumps(_report()), encoding="utf-8")
        main([str(path), "--llm", "--json"])
        assert json.loads(capsys.readouterr().out)["commentary"] == ""
