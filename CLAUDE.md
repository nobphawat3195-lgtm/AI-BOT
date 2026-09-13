# AI Trading Bot — Codebase Guide

## Project Overview

This is a **single-file Progressive Web App (PWA)** that provides a UI for an AI-powered Forex/crypto trading bot. It connects to MT5/MT4 brokers via MetaAPI and optionally uses an AI model (Claude, GPT-4o, Gemini, or Grok) to analyze markets and guide trade decisions. The app is entirely Thai/English bilingual.

**Deployment**: GitHub Pages at `nobphawat3195-lgtm.github.io`

---

## Repository Structure

```
AI-BOT/
├── nobphawat3195-lgtm.github.iindex.html   ← Main app (1,816 lines) — NOTE: filename typo (missing `/io/`)
└── nobphawat3195-lgtm.github.io/
    ├── index.html                           ← Empty placeholder for GitHub Pages
    └── bot                                  ← Alternate HTML copy of the app
```

**Important filename note**: `nobphawat3195-lgtm.github.iindex.html` is a malformed filename — it was intended to be at path `nobphawat3195-lgtm.github.io/index.html` but was committed with the directory separator missing.

---

## Architecture

**No build system.** No package manager. No transpiler. Everything is vanilla HTML/CSS/JavaScript in a single file.

### Technology Stack

| Layer | Technology |
|-------|-----------|
| UI | Vanilla HTML5 + custom CSS |
| Logic | Vanilla JavaScript (ES2020+, async/await) |
| State | In-memory JS object + `localStorage` |
| Fonts | Google Fonts: Orbitron, Exo 2, Share Tech Mono |
| PWA | Inline Service Worker via Blob URL |
| Hosting | GitHub Pages |

### External APIs

| Service | Base URL | Purpose |
|---------|----------|---------|
| MetaAPI | `https://mt-client-api-v1.london.agiliumtrade.ai` | MT5/MT4 broker connection |
| Claude | `console.anthropic.com` | AI market analysis (user-provided key) |
| OpenAI GPT-4o | `platform.openai.com` | AI market analysis (user-provided key) |
| Gemini | `aistudio.google.com` | AI market analysis (user-provided key) |
| Grok | xAI | AI market analysis (user-provided key) |

---

## App Pages

Navigation lives in a 64px-wide left sidebar (`sidenav`). Pages are shown/hidden with CSS class `on`.

| Page ID | Nav Label | Description |
|---------|-----------|-------------|
| `dashboard` | Dashboard | Balance/equity stats, equity chart, AI market regime, recent trades, bot start/stop |
| `settings` | Settings | Risk %, SL/TP pips, lot size mode, bot options toggles, trading session hours |
| `aiapi` | AI & API | AI model selector, AI API key input, MetaAPI token + account ID |
| `strategy` | Strategy | Trading pairs checkboxes, timeframe, indicator toggles, AI analysis intervals |
| `trades` | Trades | Open positions table, trade history, manual order form, close-all button |
| `memory` | Memory | AI analysis output, performance metrics grid, trade memory log |
| `logs` | Logs | System console output, quick-action buttons |
| `profile` | Profile | Account details from MetaAPI, app version info, disconnect button |

---

## State Management

All runtime state lives in a single global object `S` (defined at line ~1156):

```javascript
const S = {
  token, accId, aiKey, aiModel,   // credentials (persisted to localStorage)
  connected, botRunning,           // connection / bot state
  info,                            // MetaAPI account info object
  positions,                       // current open positions array
  memory,                          // trade memory array (persisted)
  settings,                        // bot settings object (persisted)
  selectedPairs,                   // array of selected trading pair symbols
  refreshTimer, aiTimer, scalpTimer, uptimeTimer  // interval handles
};
```

### localStorage Keys

| Key | Content |
|-----|---------|
| `afx_token` | MetaAPI bearer token |
| `afx_accid` | MetaAPI account ID |
| `afx_aikey` | AI API key |
| `afx_aimodel` | Selected AI model (`claude`/`gpt`/`gemini`/`grok`) |
| `afx_memory` | JSON array of up to 200 trade memory entries |
| `afx_settings` | JSON object of saved bot settings |
| `afx_pairs` | JSON array of selected trading pairs |

---

## Key Functions Reference

| Function | Location (~line) | Purpose |
|----------|-----------------|---------|
| `go(tab)` | 1213 | Navigate between pages |
| `doConnect()` | 1295 | Connect to MetaAPI, fetch account info |
| `doDisconnect()` | 1348 | Clear all credentials and reset state |
| `toggleBot()` | 1369 | Start/stop the bot and its timers |
| `simulateAIInsight()` | 1448 | **Simulated** AI analysis (hardcoded templates — real AI calls not yet implemented) |
| `runScalpCheck()` | 1488 | Periodic scalp entry evaluation |
| `loadPositions()` | 1504 | Fetch open positions from MetaAPI |
| `placeOrder()` | 1561 | Place a manual market order via MetaAPI |
| `closeAll()` | 1589 | Close all open positions |
| `addMemory(trade)` | 1607 | Append a trade to memory (max 200) |
| `renderMemory()` | 1615 | Update memory UI and trade history table |
| `updatePerformance()` | 1645 | Recalculate win rate, P&L stats from memory |
| `renderChart()` | 1666 | Draw equity chart bars (uses placeholder data) |
| `refreshAll()` | 1684 | Re-fetch account info and positions |
| `apiGet(path, token)` | 1768 | Authenticated GET to MetaAPI |
| `apiPost(path, token, body)` | 1774 | Authenticated POST to MetaAPI |
| `log(msg, cls)` | 1792 | Append timestamped line to system console |
| `buildPairGrid()` | 1248 | Render the trading pair selector grid |
| `selectAI(model, el)` | 1226 | Switch active AI model |

---

## CSS Architecture

### Design System (CSS Custom Properties)

Dark space-blue color palette defined in `:root`:

| Variable | Color | Usage |
|----------|-------|-------|
| `--bg0` | `#03060f` | Deepest background |
| `--bg1`–`--bg3` | Navy scale | Card backgrounds |
| `--blue` | `#1e6fff` | Primary accent |
| `--blue3` | `#00d4ff` | Cyan highlight |
| `--green` | `#00ff88` | Positive/profit |
| `--red` | `#ff2d55` | Negative/loss |
| `--amber` | `#ffb800` | Warning/loading |
| `--purple` | `#a855f7` | AI-related elements |
| `--text` | `#e0eeff` | Primary text |
| `--text2` | `#6b8db8` | Secondary text |
| `--text3` | `#2a4a70` | Muted text |

### Utility Class Patterns

- `.btn`, `.btn-blue`, `.btn-green`, `.btn-red`, `.btn-amber`, `.btn-ghost`, `.btn-full` — buttons
- `.card`, `.card-glow` — content cards with dark gradient background
- `.tog`, `.tog.on`, `.tog.bon`, `.tog.pon` — toggle switches (green/blue/purple active states)
- `.fi` — form inputs (text, number, select, textarea)
- `.msg`, `.msg.err`, `.msg.ok`, `.msg.info`, `.msg.warn` — feedback messages
- `.pill`, `.pill-live`, `.pill-demo`, `.pill-ok`, `.pill-blue` — status badges
- `.sv` with `.b/.g/.r/.a/.p` — stat values (blue/green/red/amber/purple)
- `.iv` with `.g/.b/.a/.p` — info values in rows

### Console Log Colors
`lg`=green, `lb`=blue, `la`=amber, `lr`=red, `ld`=dark/muted, `lp`=purple

---

## MetaAPI Integration

The MetaAPI base URL is hardcoded at line 1176:
```javascript
const API = 'https://mt-client-api-v1.london.agiliumtrade.ai';
```

Authentication uses the `auth-token` request header. All calls are direct browser fetch — no server proxy.

### Endpoints Used

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/users/current/accounts/{id}/account-information` | Account balance, equity, broker, leverage |
| GET | `/users/current/accounts/{id}/positions` | All open positions |
| POST | `/users/current/accounts/{id}/trade` | Place or close orders |

### Trade Action Types
- `ORDER_TYPE_BUY` / `ORDER_TYPE_SELL` — open a market order
- `POSITION_CLOSE_ID` — close a specific position by ID

---

## Bot Timer Logic

When the bot is started via `toggleBot()`:

1. **Uptime timer** — fires every 1s, increments `S.uptime`, updates display
2. **AI analysis timer** (`S.aiTimer`) — counts down from 3600s (60 min), calls `simulateAIInsight()` on expiry
3. **Scalp check timer** (`S.scalpTimer`) — counts down from 60s (1 min), calls `runScalpCheck()` on expiry
4. **Auto-refresh timer** (`S.refreshTimer`) — fires every 30s, calls `refreshAll()`

---

## Known Issues / Incomplete Features

1. **AI API calls are not implemented** — `simulateAIInsight()` uses hardcoded Thai-language insight templates chosen at random. Actual calls to Claude/GPT-4o/Gemini/Grok APIs are never made.

2. **Equity chart uses placeholder data** — `renderChart()` draws from a hardcoded `vals` array `[65,70,68,...,100,97]`, not real equity history.

3. **Bot options toggles are not wired to state** — the toggle buttons in Settings update their visual state but the values are never read by `runScalpCheck()` or `toggleBot()`.

4. **Filename typo** — `nobphawat3195-lgtm.github.iindex.html` should live at `nobphawat3195-lgtm.github.io/index.html`.

5. **`document.getElementById('botBtn')` reference** — `toggleBot()` at line ~1379 references `botBtn` which doesn't exist in the HTML; this will throw silently.

6. **MQL5 EA code field is decorative** — the textarea content is never sent to any AI for parsing.

---

## Development Workflow

### Editing the App

Since the entire app is a single HTML file, edit it directly. There is no build step.

```bash
# The primary source file
nobphawat3195-lgtm.github.iindex.html
```

### Deploying

GitHub Pages serves from the `nobphawat3195-lgtm.github.io/` directory. To deploy changes, the compiled/final HTML must be placed at `nobphawat3195-lgtm.github.io/index.html` and committed.

### Testing

Open the HTML file directly in a browser. There is no test suite. Verify:
- MetaAPI connection with real token + account ID
- Bot start/stop cycling
- localStorage persistence across page reloads
- Mobile layout at 375px viewport width

### PWA Service Worker

Registered inline at the bottom of the script block (line ~1808). It uses a Blob URL and provides basic fetch-fallback caching. No separate `sw.js` file is needed.

---

## Trading Pairs

Available pairs (defined in `PAIRS_ALL` at line 1177):

```
EURUSD, EURAUD, GBPUSD, USDJPY, XAUUSD, GBPJPY,
AUDUSD, USDCAD, NZDUSD, EURGBP, EURJPY, USDCHF,
BTCUSD, ETHUSD
```

Default selected: `EURUSD`, `EURAUD`, `XAUUSD`

---

## Conventions

- **No comments in CSS** — sections delimited by `/* SECTION NAME */` all-caps headers
- **No comments in JS** — sections delimited by `// ═══ SECTION ═══` banner comments
- **Minimal whitespace** — CSS rules are often one-liners for space efficiency
- **No semicolons omitted** — standard JS semicolons throughout
- **Thai language** — user-facing descriptions and help text are in Thai; labels and code identifiers are English
- **Inline styles** — used heavily in the HTML for one-off layout adjustments rather than adding utility classes
- **`id` naming** — kebab-case DOM IDs for display elements (`d-bal`, `s-model`, `conn-ok`); camelCase for JS variables
