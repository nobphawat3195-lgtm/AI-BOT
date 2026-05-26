# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is **AI Trading Bot v4.0** — a single-file, pure HTML/CSS/JS progressive web app (PWA) for semi-automated forex/crypto trading. It connects to MT5 brokers via MetaAPI and supports multiple AI backends (Claude, GPT-4o, Gemini, Grok) for market analysis.

There is no build system, no package manager, no framework, and no test suite. The entire application lives in a single HTML file.

## File Structure

```
nobphawat3195-lgtm.github.io/
  bot          ← Main application (HTML/CSS/JS, ~1800 lines)
  index.html   ← Empty placeholder for GitHub Pages root
nobphawat3195-lgtm.github.iindex.html  ← Root-level duplicate of bot (typo in filename)
```

The canonical source is `nobphawat3195-lgtm.github.io/bot`. It is served at `https://nobphawat3195-lgtm.github.io/bot` via GitHub Pages. The root-level file (`nobphawat3195-lgtm.github.iindex.html`) is a copy with a typo in its name — keep these in sync if making changes.

## Development Workflow

No build step. Edit the file directly and open it in a browser.

To serve locally:
```bash
cd nobphawat3195-lgtm.github.io
python3 -m http.server 8080
# then open http://localhost:8080/bot
```

## Architecture

The app is structured as a single HTML file with three major sections: CSS styles, HTML markup, and a `<script>` block.

### State (`S` object)

All runtime state lives in the global `S` object (line ~1156). Persistent fields are synced to `localStorage` with the `afx_` prefix:

| localStorage key | Purpose |
|---|---|
| `afx_token` | MetaAPI auth token |
| `afx_accid` | MT5 account ID |
| `afx_aikey` | AI provider API key |
| `afx_aimodel` | Selected AI (`claude`/`gpt`/`gemini`/`grok`) |
| `afx_memory` | Trade history array (max 200 entries) |
| `afx_settings` | Bot settings object |
| `afx_pairs` | Selected trading pairs array |

### Navigation / Page System

Pages are `<div class="page">` elements. Only the one with class `on` is visible. The `go(tab)` function handles switching by toggling `.on` on both the `.nav-item` and `#page-{tab}` elements.

Pages: `dashboard`, `settings`, `aiapi`, `strategy`, `trades`, `memory`, `logs`, `profile`

### External API Integration

MetaAPI base URL: `https://mt-client-api-v1.london.agiliumtrade.ai`

Two helpers in the `<script>`:
- `apiGet(path, token)` — authenticated GET
- `apiPost(path, token, body)` — authenticated POST with JSON body

The auth header is `auth-token: <token>` (not `Authorization: Bearer`).

Key endpoints used:
- `GET /users/current/accounts/{accId}/account-information` — account info
- `GET /users/current/accounts/{accId}/positions` — open positions
- `POST /users/current/accounts/{accId}/trade` — place/close orders

### AI Analysis

**Current state: AI analysis is fully simulated.** `simulateAIInsight()` randomly picks from 3 hardcoded insight objects. Actual AI API calls (to Claude, GPT-4o, etc.) are not yet implemented — the API key is stored but never used to make a real HTTP request. This is the main missing feature.

When implementing real AI calls, the prompt should include: live position data, account balance/equity, selected pairs, active technical indicators, and any MQL5 EA code pasted by the user (`#inp-ea`).

### Bot Timers

When the bot is running, three `setInterval` timers fire:
- **Uptime timer** — every 1s, updates `s-uptime` display
- **AI timer** — countdown from `aiCountdown` (default 3600s), calls `simulateAIInsight()` when it hits 0
- **Scalp timer** — countdown from `scalpCountdown` (default 60s), calls `runScalpCheck()` when it hits 0

All timers are stored on `S` (`S.refreshTimer`, `S.aiTimer`, `S.scalpTimer`, `S.uptimeTimer`) and must be cleared via `clearInterval` on disconnect/stop.

### CSS Design System

CSS variables are defined in `:root` at the top of the `<style>` block. Key variables:

- Colors: `--blue`, `--blue2`, `--blue3`, `--green`, `--green2`, `--red`, `--red2`, `--amber`, `--purple`, `--purple2`
- Backgrounds: `--bg0` through `--bg3`, `--card`, `--card2`
- Borders: `--border`, `--border2`
- Text: `--text`, `--text2`, `--text3`

**Known bug**: In the splash section (`#splash` and nearby elements), some CSS variable references use an en-dash (`–`) instead of double-dash (`--`), e.g. `var(–bg0)` instead of `var(--bg0)`. These are broken references; fix them to `--` when editing that section.

### PWA

An inline service worker is registered at the bottom of the script using a `Blob` URL. It does a basic fetch-with-cache-fallback. No manifest file exists.

## Known Issues / Quirks

- Lines ~488–600 in `nobphawat3195-lgtm.github.io/bot` contain stray markdown code fences (` ``` `) inside the HTML. These appear to be accidental and should be removed.
- The equity chart (`renderChart()`) uses hardcoded bar values — it is not driven by real historical data.
- `runScalpCheck()` only logs to the console — it does not place real orders.
- The `botBtn` element referenced in `toggleBot()` does not exist in the HTML (only `startBtn` does), which will cause a silent JS error when starting/stopping the bot.
