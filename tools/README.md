# tools/

## pp-mt5-backtester

Vendored from [ek-labs/pp-mt5-backtester](https://github.com/ek-labs/pp-mt5-backtester) (MIT License) — a Go CLI for
running MetaTrader 5 Expert Advisor backtests headlessly, compiling MQL5 source, parsing strategy-tester
HTML reports, and batch-testing across symbols/timeframes.

- Windows-only at runtime (MetaTrader 5 only runs on Windows); building the CLI itself works cross-platform with Go 1.22+.
- See `tools/pp-mt5-backtester/README.md` for full command reference and `SKILL.md` for the Claude skill definition.

Build:

```bash
cd tools/pp-mt5-backtester
go build -o pp-mt5-backtester.exe ./cmd/pp-mt5-backtester   # on Windows
```

Quick start:

```powershell
pp-mt5-backtester config
pp-mt5-backtester run --ea "MACD Sample" --symbol EURUSD --period H1 --from 2023.01.01 --to 2024.01.01
pp-mt5-backtester report path\to\report.htm -o json
```
