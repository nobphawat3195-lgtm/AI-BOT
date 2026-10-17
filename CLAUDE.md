# AUTO 1 quotation system — rules for integrating Figma designs

Read this before turning a Figma frame into code here. This repo is **not** a component-based app: it is a few hand-written static HTML files with inline CSS and JS, served as-is by GitHub Pages. Figma output (React, Tailwind, shadcn…) is a reference to translate, never code to paste.

Live site: https://nobphawat3195-lgtm.github.io/AI-BOT/quotation.html · UI language: Thai (`<html lang="th">`).

## 1. Project structure

```
quotation.html   ← the product (~250 KB): quotation editor + dashboard, history, customers, reports, settings
guide.html       ← standalone animated how-to (8-step reel + written steps + FAQ)
crm.html         ← separate mobile/iPad CRM for credit customers (own page, own code; not analysed in depth)
index.html       ← separate "AI Trading Bot" page (unrelated to quotations)
assets/bg/       ← WebP photo(s) for the living background + README.md (how to swap a photo)
nobphawat3195-lgtm.github.io/   ← legacy copies, leave alone
```

- No package.json, no bundler, no framework, no lint config, no tests in the repo, no CI workflow. Deploy = merge to `main`.
- Each page is one file: `<style>` in `<head>`, markup, one `<script>` at the end of `<body>`. Keep it that way; do not introduce a build step.
- Preview locally: `python3 -m http.server 8765` from the repo root, then open `http://localhost:8765/quotation.html`. Relative asset paths (`assets/bg/…`) must keep working under the `/AI-BOT/` sub-path on GitHub Pages.
- Verification is done with Playwright (chromium) against the served page; see "Before you ship" below.

### `quotation.html` layout

| Part | Where (search for) |
|---|---|
| Base CSS + tokens | first `<style>`, `:root{` (line ~9) |
| Premium screen theme | `PREMIUM SCREEN THEME (screen only)` (~L258) |
| Motion layer (Aurora, SplitText, Spotlight, …) | comment banners from ~L514 |
| Finish layer (glass, hairlines, grain) | `FINISH LAYER` (~L664) |
| Home hero + app views CSS | `.view`, `.stat-card`, `.service-card` (~L1043+) |
| AMG chrome-silver theme (overrides the palette) | `@media screen{ :root{…}` (~L1184) |
| Garage hero clip SVG + canvas FX | `.clip`, `mountClipFx` |
| Living background | `LIVING BACKGROUND` CSS (~L1450) and JS `mountLiveBg` |
| Print rules (paper sheet) | `@media print{` (~L1608 and ~L1768) |
| Views markup | `<section id="view-home|services|quote|customers|history|reports|settings|contact" class="view">` |
| App JS | single `<script>` (~L2466–L4213) |

CSS is **layered, later wins**: base → premium → finish → AMG → print. A new rule that must beat an older one goes in the matching late layer, not in an earlier block.

## 2. Design tokens

Plain CSS custom properties on `:root`, redefined per layer (there is no token file, no Style Dictionary, no transform step). Hex values are copied by hand.

```css
/* base (L9) */
--navy0:#0b1a2e; --navy1:#0f2a4a; --navy2:#12345f;
--blue:#1e6fff; --blue2:#4d9fff; --cyan:#48d8ff;
--amber:#ff8a1e; --gold:#ffc861; --green:#0fa968; --red:#e0334f;
--font:'Kanit',sans-serif;                 /* the document font; the user's font picker overwrites it */
--ink:#e8f1ff; --sub:#93aacd; --line:#24334f; --line2:#1b2740;
--bg:#05090f; --card:rgba(14,23,40,.82); --panel:rgba(18,29,50,.72);
--input-bg:rgba(6,11,21,.66); --th-bg:rgba(30,111,255,.12); --th-ink:#a9c8ff;

/* finish layer (L670): chrome-only extras */
--font-display:'Chakra Petch','Kanit',sans-serif;   /* chrome/labels only, never the document body */
--obsidian:#04070d; --glass:rgba(13,21,36,.72); --platinum:#c9d6e8; --champagne:#e8c98a;

/* AMG layer (L1185) — the look on screen today */
--bg:#050b17; --ink:#eef2f8; --sub:#a9b6ca; --blue:#2e6bff; --blue2:#8fb8ff;
--chrome:linear-gradient(135deg,#f7f9fc,#bac4d2 32%,#6e7a8c 50%,#e4e9f0 68%,#98a4b6);
--card-fill / --glass-fill   /* navy gradient panels */
```

Current visual direction: **navy + chrome/silver + electric blue, yellow/gold as the accent**. Map Figma colour styles/variables onto these names; add a new variable only when no existing one fits, and put it in the layer where it is used. In `@media print` the same variables are reset to a white paper palette (`--ink:#0f1e33; --bg:#fff; …`), so anything that uses variables prints correctly for free; hard-coded colours do not.

Typography: Thai-first. Fonts come from one Google Fonts `<link>` (Kanit, Sarabun, Prompt, Mitr, Itim, Srisakdi, Chonburi, Charmonman, Trirong, Chakra Petch). Body is `var(--font)`. Never set document text with a hard-coded family; `setFont(name)` swaps `--font` at runtime.

Spacing, radii and shadows are literal px values per component (no scale tokens). Typical: radii 7–16px, panels 14–22px, shadow `var(--glow)`.

## 3. Components

There is no component library, no Storybook. "Components" are CSS classes plus markup written inline or built as template strings in JS.

| Pattern | Class / id |
|---|---|
| Buttons | `.btn`, `.btn-print` (primary, light chrome), `.btn-ghost`, `.btn-danger`; icon inside `.btn .ico` (17px) |
| Cards / panels | `.panel-card` (+ `.panel-head`, `.panel-sub`), `.stat-card` (inside `.dash-stats`), `.service-card`, `.note-banner`, `.view-head` |
| Nav | `.tn-menu` → `.tn-item` (buttons with `data-view`; the guide link is an `<a>` without it) |
| Tables | quotation `table.items` (inputs in cells), plain tables for history/customers |
| Form fields | `.field`, `label`, `input`; printed twins `.pmirrored` (screen input) + `.pmirror` (print text) |
| Settings rows | `.lb-settings`, `.lb-row` (label · range · output) |

Views are `<section class="view" id="view-NAME" hidden>`; `showView(name)` toggles `hidden`, restarts `.view-enter`, sets `body.dataset.view`, and triggers per-view renderers. Add a view by: new `<section>`, add the name to `VIEWS`, a nav button with `data-view`.

Rendering is imperative: `renderItems()` builds the table rows as HTML strings (always pass user text through `escapeHtml`), `recalc()` recomputes totals, `save()`/`load()` persist state.

## 4. Frameworks & libraries

None at runtime: vanilla JS (ES2020, one global scope, `function` declarations and `const` tables), vanilla CSS. No jQuery, no CDN scripts. Only external request is Google Fonts. Canvas 2D is used for particle FX (`mountClipFx`, living-background sparks). Do not add a library for something CSS or ~30 lines of JS can do.

Motion helpers are all in-file ports of ReactBits-style effects (`mountTilt`, `mountSpotlight`, `mountButtons`, `mountSparks`, `mountReveal`, `countTo`, `mountParallax`) started from `mountMotion()`. New motion follows the same rules:

- Prefer `transform`/`opacity` and individual `translate`/`rotate`/`scale` properties; avoid layout-affecting animation.
- Always honour reduced motion: JS reads `REDUCED` / `HOVERS` (top of the motion section); CSS has `@media (prefers-reduced-motion:reduce){…}`. A `still` state must show a calm final frame, not nothing.
- Decorative layers are `pointer-events:none`, `aria-hidden="true"`, and `display:none` in print (`.no-print`).

## 5. Asset management

- **Logo:** embedded as a base64 JPEG in `<img id="logoImg">` (so it survives offline and prints); users can replace it (`handleLogo`, stored in the draft). Keep `DEFAULT_LOGO_SRC` working.
- **Photos:** `assets/bg/auto1-<id>.webp` (desktop, ≤ ~1500px wide, q≈75) and `auto1-<id>-sm.webp` (640px tall, phones ≤700px / Save-Data). Referenced by relative path from `LB_SCENES` in the script. They are lazy-loaded (one `Image()` probe, `decode()`, then shown); a failed load must degrade silently. `assets/bg/README.md` documents swapping a photo (crop, `ar`, focal point `fx/fy`, hotspot fractions).
- No image pipeline: compress with any tool (Pillow works) before committing; keep the whole folder in the low hundreds of KB. No video files. No CDN config.
- User uploads (car photo, logo) become data URLs inside the saved draft.

## 6. Icon system

No icon font or sprite file. Icons are **inline SVG, 24×24 viewBox, `fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"`** (Feather/Lucide style), always with `class="ico"` and `aria-hidden="true"`:

```html
<svg class="ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"
     stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="…"/></svg>
```

Size comes from the parent (`.btn .ico{width:17px;height:17px}`, `.tn-bell .ico`, …). Colour is inherited via `currentColor`. For a Figma icon: export as SVG, keep only the paths, normalise to this stroke style, no fixed width/height or fills. The living background has its own hidden `<symbol id="lbi-*">` set (wrench, gear, plug, wheel, nut, battery, oil, car, bolt) used via `<use href="#lbi-…">`. A few emoji (🖼 📷 🗂️ 🖨) still appear in labels; prefer SVG for new UI.

## 7. Styling approach

- Hand-written global CSS, class-based, no methodology (no BEM, no modules, no CSS-in-JS, no Tailwind). Class names are short and descriptive (`.tn-item`, `.stat`, `.lb-scene`); feature groups share a prefix (`lb-` living background, `clip-` hero clip, `tn-` top nav).
- Theme layers are wrapped in `@media screen{…}` so print stays a clean paper document. Anything decorative belongs in a `@media screen` block.
- **Responsive:** desktop-first with `max-width` breakpoints: **900px** (tablet), **700px** (live background swaps to `-sm` image), **640px** (phone; tables scroll inside `.table-scroll`). The nav menu becomes a horizontal scroller at ≤900px. `viewport-fit=cover` is set; use `100lvh`/`100vh` pairs for full-height layers. Check 390×844 and ≥1280 wide.
- Stacking (don't reorder): `.live-bg{z-index:0}` < `body::before` (blueprint grid, 1) < `.wrap` (1) < popovers. `z-index:-1` for the background does not work because `html` and `body` both paint a background.
- Readability over the photo: cards are ~0.8 alpha navy; `--dim` per view (`body[data-view=…] .live-bg`) controls the navy grade; the quote editor is the darkest.

## 8. Business rules that Figma changes must never break

- **Pricing:** default sell = cost × 1.5 (`MARKUP`). Alt category `alt` = (cost × 1.07) × 1.7 and writes 15 into the line's discount cell (`PRICE_CATS`, `setCat`); the 15% is shown, not folded into the price. Example: cost 1,000 → 1,500.00, or 1,819.00 with 15% → 1,546.15.
- **Line discount** (`parseDisc`): each row has a `%` / `บาท` selector (`it.discType`, default pct, `setDiscType`); a typed suffix wins and syncs the selector (`5%` = 5%, `500บ` = 500 baht). The selector is `.no-print`; paper shows the label (`5%` or `500.00 บ`). **Overall discount**: checkbox + number + `บาท`/`%` select. Then **VAT 7%** (checkbox) on the discounted total; `ยอดรวมสุทธิ` plus Thai baht-text (`bahtText`). Sample check: costs 1,480 + 650, 5% overall, VAT → 3,195.00 / 3,035.25 / 212.47 / 3,247.72.
- Cost price and price-category columns are `.no-print`; they never appear on paper.
- **Print = one A4 page.** `@media print` forces `#view-quote` only, white paper palette, hides the whole motion layer. Item-table columns are **percentages** (phones print with a narrow layout width, px columns overflow); the description column takes the rest so ordinary part names stay on one line. After any layout change, print the quote to PDF and confirm 1 page.
- Persistence is `localStorage` only, per device: `autoPartsQuotationDraft`, `autoPartsSkuCatalog`, `autoPartsQuoteHistory`, `auto1LiveBg`. Wrap access in try/catch; never rename a key without a migration.
- Public JS hooks used by markup `onclick`/tests: `recalc`, `showView`, `parsePasteText`, `setCat`, `AUTO1_BG` (`set`, `next`, `show`, `preload`, `prefs`). Keep their names.

## 9. Translating a Figma frame, step by step

1. `get_design_context` for the node → treat the React/Tailwind output as a spec. Extract colours, type scale, spacing, radii, effects.
2. Map colours to existing variables (§2). Only add a variable when truly new.
3. Write plain HTML + CSS in the right layer (screen-only styling inside `@media screen`), reuse `.btn`, `.panel-card`, `.field`, `.ico` before inventing classes.
4. Icons → inline SVG per §6. Images → WebP under `assets/<area>/`, relative path, `-sm` variant for phones if large.
5. Mobile first check at 390px, then 900/1280; add motion only with a reduced-motion path.
6. Keep Thai copy exactly as designed (don't "fix" wording); labels in the quote editor must stay in sync with `README`/`guide.html` (the guide mirrors real labels and numbers).

## 10. Before you ship

- Console clean: no `pageerror`; the only acceptable failed request in a sandbox is Google Fonts.
- Quote regression: paste `โช๊คอัพหน้า TOKICO ราคา 1480` + `ผ้าเบรคหน้า ราคา 650`, confirm 2,220.00 / 975.00, discount/VAT totals as in §8.
- Print to PDF (A4): exactly 1 page, no background, no cost column.
- Views: home, quote, services, settings render and are readable over the background; nav still switches views.
- Reduced motion (`reducedMotion:'reduce'`): no running animations in decorative layers.
- No horizontal overflow at 390px.
- Workflow used in this repo: develop on the assigned branch, push, open a draft PR (use the repo PR template if one is added), mark ready, squash-merge, then merge `origin/main` back into the branch.
