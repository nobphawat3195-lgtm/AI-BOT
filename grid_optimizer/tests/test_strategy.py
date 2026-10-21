"""Backtest engine — arithmetic and the no-look-ahead guarantee."""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from data import load_csv, split, synthetic  # noqa: E402
from strategy import Bar, BacktestResult, Params, Trade, atr, backtest  # noqa: E402


class TestAtr:
    def test_flat_bars_have_range_equal_to_bar_height(self):
        bars = [Bar(str(i), 100, 102, 98, 100) for i in range(30)]
        assert atr(bars, 20, 14) == pytest.approx(4.0)

    def test_returns_zero_before_the_period_fills(self):
        bars = [Bar(str(i), 100, 101, 99, 100) for i in range(30)]
        assert atr(bars, 5, 14) == 0.0

    def test_wider_bars_give_larger_atr(self):
        narrow = [Bar(str(i), 100, 101, 99, 100) for i in range(30)]
        wide = [Bar(str(i), 100, 110, 90, 100) for i in range(30)]
        assert atr(wide, 20, 14) > atr(narrow, 20, 14)


class TestBacktest:
    def test_short_history_produces_no_trades(self):
        bars = [Bar(str(i), 100, 101, 99, 100) for i in range(5)]
        result = backtest(bars, Params())
        assert result.trades == []
        assert result.end_balance == result.start_balance

    def test_flat_market_never_triggers_a_breakout(self):
        bars = [Bar(str(i), 2400, 2400.5, 2399.5, 2400) for i in range(400)]
        result = backtest(bars, Params())
        assert result.trades == []

    def test_runs_on_synthetic_data(self):
        result = backtest(synthetic(n=800, seed=3), Params())
        assert isinstance(result, BacktestResult)
        assert len(result.equity_curve) >= 1

    def test_balance_matches_the_sum_of_trade_profits(self):
        result = backtest(synthetic(n=1200, seed=11), Params())
        expected = result.start_balance + sum(t.profit for t in result.trades)
        assert result.end_balance == pytest.approx(expected, abs=0.01)

    def test_every_trade_is_closed(self):
        result = backtest(synthetic(n=1200, seed=5), Params())
        for trade in result.trades:
            assert trade.exit_index is not None
            assert trade.exit_price is not None

    def test_exits_never_precede_entries(self):
        result = backtest(synthetic(n=1200, seed=9), Params())
        for trade in result.trades:
            assert trade.exit_index > trade.entry_index

    def test_only_one_position_at_a_time(self):
        result = backtest(synthetic(n=1500, seed=13), Params())
        ordered = sorted(result.trades, key=lambda t: t.entry_index)
        for earlier, later in zip(ordered, ordered[1:]):
            assert earlier.exit_index <= later.entry_index

    def test_stop_distance_scales_with_the_stop_atr_parameter(self):
        bars = synthetic(n=1200, seed=21)
        tight = backtest(bars, Params(stop_atr=0.6))
        wide = backtest(bars, Params(stop_atr=2.5))
        if tight.trades and wide.trades:
            tight_d = abs(tight.trades[0].entry - tight.trades[0].stop)
            wide_d = abs(wide.trades[0].entry - wide.trades[0].stop)
            assert wide_d > tight_d

    def test_buy_levels_face_the_right_way(self):
        result = backtest(synthetic(n=1500, seed=17), Params())
        for trade in result.trades:
            if trade.side == "BUY":
                assert trade.stop < trade.entry < trade.target
            else:
                assert trade.target < trade.entry < trade.stop

    def test_is_deterministic(self):
        bars = synthetic(n=1000, seed=4)
        first = backtest(bars, Params()).summary()
        second = backtest(bars, Params()).summary()
        assert first == second


class TestMetrics:
    def _result(self, profits: list[float]) -> BacktestResult:
        result = BacktestResult(start_balance=1000.0)
        balance = 1000.0
        for i, p in enumerate(profits):
            result.trades.append(
                Trade("BUY", 100, 99, 102, 0.1, i, i + 1, 101, p)
            )
            balance += p
            result.equity_curve.append(balance)
        return result

    def test_win_rate(self):
        assert self._result([10, -5, 10, -5]).win_rate == 0.5

    def test_profit_factor(self):
        # 20 won against 10 lost
        assert self._result([10, 10, -5, -5]).profit_factor == pytest.approx(2.0)

    def test_profit_factor_is_zero_without_wins(self):
        assert self._result([-5, -5]).profit_factor == 0.0

    def test_max_drawdown(self):
        # 1000 -> 1100 -> 990: peak 1100, trough 990 => 10%
        result = self._result([100, -110])
        assert result.max_drawdown_percent == pytest.approx(10.0)

    def test_no_drawdown_on_a_rising_curve(self):
        assert self._result([10, 10, 10]).max_drawdown_percent == 0.0

    def test_sharpe_needs_two_trades(self):
        assert self._result([10]).sharpe == 0.0

    def test_summary_is_json_friendly(self):
        summary = self._result([10, -5]).summary()
        assert set(summary) == {
            "trades", "net_profit", "end_balance", "win_rate",
            "profit_factor", "max_drawdown_percent", "sharpe",
        }


class TestData:
    def test_synthetic_is_reproducible(self):
        assert synthetic(n=50, seed=1) == synthetic(n=50, seed=1)

    def test_synthetic_bars_are_well_formed(self):
        for bar in synthetic(n=200, seed=2):
            assert bar.high >= bar.low
            assert bar.high >= max(bar.open, bar.close) - 1e-9
            assert bar.low <= min(bar.open, bar.close) + 1e-9

    def test_split_is_chronological(self):
        bars = synthetic(n=100, seed=1)
        train, test = split(bars, 0.7)
        assert len(train) == 70 and len(test) == 30
        assert train + test == bars

    @pytest.mark.parametrize("fraction", [0, 1, 1.5, -0.2])
    def test_split_rejects_bad_fractions(self, fraction):
        with pytest.raises(ValueError):
            split(synthetic(n=50), fraction)

    def test_load_csv_reads_standard_columns(self, tmp_path):
        path = tmp_path / "bars.csv"
        path.write_text(
            "Date,Open,High,Low,Close\n"
            "2026-01-01,2400,2405,2395,2402\n"
            "2026-01-02,2402,2410,2400,2408\n",
            encoding="utf-8",
        )
        bars = load_csv(path)
        assert len(bars) == 2
        assert bars[0].open == 2400 and bars[1].close == 2408

    def test_load_csv_is_case_insensitive(self, tmp_path):
        path = tmp_path / "bars.csv"
        path.write_text("time,o,h,l,c\n1,10,12,9,11\n", encoding="utf-8")
        assert load_csv(path)[0].high == 12

    def test_load_csv_rejects_missing_columns(self, tmp_path):
        path = tmp_path / "bad.csv"
        path.write_text("date,open\n2026-01-01,2400\n", encoding="utf-8")
        with pytest.raises(ValueError, match="missing column"):
            load_csv(path)

    def test_load_csv_skips_malformed_rows(self, tmp_path):
        path = tmp_path / "messy.csv"
        path.write_text(
            "date,open,high,low,close\n"
            "2026-01-01,2400,2405,2395,2402\n"
            "2026-01-02,,,,\n"
            "2026-01-03,2402,2410,2400,2408\n",
            encoding="utf-8",
        )
        assert len(load_csv(path)) == 2

    def test_missing_file_raises(self, tmp_path):
        with pytest.raises(FileNotFoundError):
            load_csv(tmp_path / "nope.csv")
