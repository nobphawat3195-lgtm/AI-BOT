"""Preflight only: structural checks + independent arithmetic fixtures.
Does not compile/execute MQL5 or emulate MT5. Uses Python standard library only.
"""
from pathlib import Path
import hashlib
import math
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'XAU_Adaptive_Regime_Grid_v1.mq5'
TEXT = SOURCE.read_text(encoding='utf-8')

class SourceContracts(unittest.TestCase):
    def test_native_interfaces(self):
        for token in ('#include <Trade/Trade.mqh>', 'CTrade trade;',
                      'DetectMarketRegime()', 'CalculateBasketRisk()',
                      'CanAddGridPosition()', 'double OnTester()',
                      'ACCOUNT_MARGIN_MODE_RETAIL_HEDGING'):
            self.assertIn(token, TEXT)
        for token in ('MarketInfo(', 'OP_BUY', 'OP_SELL', 'OrderLots(', 'OrderProfit('):
            self.assertNotIn(token, TEXT)

    def test_bounded_inputs(self):
        inputs = re.findall(r'^input\s+(?!group\b)\w+\s+(\w+)\s*=', TEXT, re.M)
        self.assertEqual(len(inputs), 31)
        self.assertEqual(len(inputs), len(set(inputs)))
        self.assertRegex(TEXT, r'input bool EnableRangeMode=false;')

    def test_unique_functions(self):
        functions = re.findall(r'^(?:void|bool|int|uint|double|datetime|MARKET_REGIME)\s+(\w+)\s*\(', TEXT, re.M)
        self.assertEqual(len(functions), len(set(functions)))

    def test_balanced_delimiters(self):
        # Remove comments and quoted strings first; this is not a language parser.
        clean = re.sub(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"', '', TEXT, flags=re.S)
        stack = []
        pairs = {')': '(', ']': '[', '}': '{'}
        for char in clean:
            if char in '([{': stack.append(char)
            elif char in ')]}':
                self.assertTrue(stack)
                self.assertEqual(stack.pop(), pairs[char])
        self.assertEqual(stack, [])

    def test_closed_bar_calls_and_execution_contract(self):
        self.assertIn('CopyBuffer(hATR[0],0,2,ATR_BASELINE_BARS', TEXT)
        self.assertIn('CopyRates(_Symbol,PERIOD_M5,1,1,r)', TEXT)
        self.assertIn('CopyRates(_Symbol,PERIOD_M5,start,bar-1,rates)', TEXT)
        self.assertNotRegex(TEXT, r'BufferValue\([^;\n]*,0,0,')
        self.assertIn('trade.PositionClose(ticket,DEVIATION_POINTS)', TEXT)
        self.assertIn('!ok || !RetcodeOK() || trade.ResultDeal()==0', TEXT)
        self.assertIn('if(closing || basket.count==0) return;', TEXT)
        self.assertIn('MathAbs(basket.volume-filledVolume)>1e-8', TEXT)
        self.assertIn('Put("version",-1.0)', TEXT)
        self.assertIn('if(tester) return;', TEXT)

class IndependentArithmeticFixtures(unittest.TestCase):
    """Independent numerical examples of design requirements, NOT EA execution tests."""
    def test_average_and_executable_side(self):
        positions = [(3000.20, .01), (2998.20, .01), (2996.20, .005)]
        average = sum(p*v for p,v in positions) / sum(v for _,v in positions)
        self.assertAlmostEqual(average, 2998.6)
        atr = 2.0
        buy_tp = average + atr * .4
        bid, ask = buy_tp-.1, buy_tp+.1
        self.assertFalse(bid >= buy_tp)  # Ask crossing does not close buy.
        sell_tp = average - atr * .4
        bid, ask = sell_tp-.1, sell_tp+.1
        self.assertFalse(ask <= sell_tp) # Bid crossing does not close sell.

    def test_gold_budget_can_reject_500(self):
        # Explicit hypothetical contract: 100 oz/lot, 1 lot loses $100 per $1 move.
        equity, risk, cap, atr, stop_atr = 500, .015, 4, 2, 3.5
        loss_per_lot = 100 * atr * stop_atr + 10 + 100*.40
        raw = equity*risk/(cap*loss_per_lot)
        self.assertLess(raw, .01)
        self.assertGreater(.01*cap*loss_per_lot, equity*risk)

    def test_full_reservation_bounds_adverse_entries(self):
        # Budget across equal-size entries toward an immutable stop.
        for direction in (-1,1):
            entry, stop_distance, contract = 3000., 7., 100.
            stop = entry-direction*stop_distance
            unit_loss = stop_distance*contract+50.
            budget, cap, step = 150., 4, .001
            volume = math.floor(budget/(cap*unit_loss)/step)*step
            prices = [entry-direction*i*1.4 for i in range(cap)]
            actual_risk = sum(max(0., direction*(p-stop))*contract*volume+50*volume for p in prices)
            self.assertLessEqual(actual_risk, budget+1e-9)
            self.assertLessEqual(cap*unit_loss*volume, budget+1e-9)

    def test_session_midnight_and_boundaries(self):
        # Reference specification independent from source parser.
        def active(minute, a, b):
            if a==b: return True
            return a<=minute<b if a<b else minute>=a or minute<b
        self.assertTrue(active(23*60,22*60,2*60))
        self.assertTrue(active(0,22*60,2*60))
        self.assertFalse(active(2*60,22*60,2*60))
        self.assertFalse(active(21*60,22*60,2*60))
        self.assertTrue(active(500,0,0))

    def test_vwap_weighted_fixture(self):
        # Typical prices 100,102,98 and weights 10,20,10.
        vwap = sum(p*v for p,v in [(100,10),(102,20),(98,10)]) / 40
        self.assertAlmostEqual(vwap, 100.5)

    def test_equity_vs_balance_recovery(self):
        net, balance_dd, equity_dd = 300, 50, 250
        self.assertEqual(net/balance_dd, 6)
        self.assertEqual(net/equity_dd, 1.2)
        self.assertLess(net/equity_dd, 1.5)

if __name__ == '__main__':
    print('PREFLIGHT ONLY — not native compilation, MT5 execution, or backtest', flush=True)
    print('Source SHA256:', hashlib.sha256(SOURCE.read_bytes()).hexdigest(), flush=True)
    unittest.main(verbosity=2)
