# Step WebLoad: why the app got slower, and the fix (bos114)

Branch `perf/webload` (from `origin/integration/p72-p79`). Everything below was measured in Chromium (Playwright), mocked Supabase, signed-in owner, https/h2 server with gzip and a **shared link** for page AND service-worker traffic, CPU throttled 4x (mid-range phone). Tools: `tests/web/webload_measure.js` (load), `tests/web/posload_test.js` (POS with 1369 items), `tests/web/webload_observers.js` (decorator cost). Reproduce: end of this file.

## 1. What was wrong (measured)

| # | Finding | Evidence |
|---|---|---|
| 1 | **The CSP `<meta>` (bos105/111) makes Chrome fetch the 110 scripts one at a time.** With a meta CSP the preload scanner stops looking ahead, so each `<script src>` costs one full round trip (RTT) before the next starts. | Same files, same server, only the meta tag removed: Home after 10.2 s -> 2.0 s at 75 ms RTT. At 150-300 ms RTT (mobile data) 110 scripts = 17-35 s of pure waiting. The old public bundle (CSP "left out of first deploy") loaded all scripts in parallel: Home 1.7 s. This is the main reason the phone got slower after the update. |
| 2 | The service worker precache downloads everything a SECOND time on the first visit and on every update (`cache: 'reload'`). | First visit = 237 requests, 2247 KB for a 1123 KB app. |
| 3 | The service worker is network-first for every file: a returning visit sends ~117 conditional requests (one RTT each, even when nothing changed). | warm visit: 117 requests, 0 bytes, Home at 11.5 s (tip) |
| 4 | The inline theme script is blocked by the page's own CSP: the hash in the meta (`4JayVL...`) is the OLD script (the glass themes edited it, the hash was not updated). Theme applied late, console error on every start. | real hash `/zibRcU0a+WHo6OiCt9LWFd4lFoHX6yNEmM7aWjqFrk=`, fixed (sec2_csp_test passes). |
| 5 | 3.7 MB of JavaScript (1.1 MB gzip), all parsed and run at start, for every screen. | 111 files, scripting 654 ms (4x CPU) before Home. |
| 6 | Google Fonts CSS is render-blocking in `<head>`. | first paint waits for a third-party host. |
| 7 | POS with the owner's catalogue (1369 items, 231 categories): all 1369 cards in one `innerHTML` (2.5 s layout freeze), then three body-wide MutationObservers (a11yfix, controls, catpick) re-scan the whole page after every insert; `fmt()` built a new `Intl` formatter per price; items, conversions and static data were read one after the other. | section 4 |

## 2. What was changed (behaviour-identical; every edit to an existing file is tagged `bos114`)

* **Build (new):** `tools/build_web.sh` (+ `tools/web_build.js`, `tools/web_deps.js`, `tools/web_lazy.json`). `web/` -> `dist/`: terser-minified JS (no source maps), one merged minified `app.css`, a **core bundle** `core.js` (start-up shell, POS path, offline start; 56 scripts joined in the original order), every other script minified under its old name and loaded **when its route opens**, `?v=<hash of that file>` per file (stable between deploys when the content is unchanged), `sw.js` with VERSION and the exact precache list, `bundle-manifest.json`. `--to <public repo>` copies dist into the public checkout with the same protections as `make_bundle.sh` (never overwrites `config.js`, keeps `setup-*.html`, `audit-a.html`, `PUBLISH_NOTES.md`, `DEPLOY_CHECKLIST.md`, `CNAME`, `.nojekyll`; refuses `main`; stops on node-style files, conflict markers, secrets). `--minify-only --no-stamp` builds the same page as `web/` (equivalence check of the minifier).
* **Which scripts are lazy is computed, not guessed:** `web_deps.js` parses every script (acorn) for what it publishes (`BOS.x`, `window.X`, `H` action handlers, `BOS_PAGES` routes) and which other scripts mention it. Anything an eager script mentions is pulled into the core automatically (25 scripts were; the build prints why). Routes -> scripts come from the `BOS_PAGES` registrations plus dependencies; decorators of a screen are attached (`purchase` loads landed / landed_q4 / purchaseprint). A script nothing would ever load fails the build.
* **`web/lazy.js` (new, in the core):** `BOS_LAZY.need/load` (dynamic `<script async=false>` keeps the original order, each file once), loading bar, a retry screen if a script cannot be fetched (L(bn,en,mix) texts), background loading of the decorators (item photos, Home badges, dashboard link) one per idle slot and never while a screen is loading, non-blocking font link. Without the map (plain `web/`) it does nothing.
* **`web/app.js`:** `dispatch()` waits for the route's script before drawing (deep links work); a token drops a late arrival for an older route; `BOS_LAZY.track` shows a loading bar after 150 ms and a "Slow connection - still loading" bar with Retry after 6 s for EVERY screen that waits (POS, lists, reports). `fmt()` uses one `Intl.NumberFormat`.
* **`web/sw.js`:** precache = exact list written by the build (core, css, decorators, manifest, icons); lazy screens are cached at runtime on first use; files with `?v=<hash>` are served cache-first (no round trip per script); an update copies unchanged files from the old cache instead of downloading them; precache takes hashed files from the HTTP cache (no second download); a page start waits at most 4 s for the network when a saved index exists; the vendor library is stale-while-revalidate. Offline start (Home + POS) unchanged and tested.
* **`web/index.html`:** `lazy.js` added, font CSS `media=print` + `<noscript>`, CSP theme-script hash fixed.
* **POS (`pos.js`, `controls.js`, `catpick.js`, `a11yfix.js`, `styles.css`):** first 72 cards drawn at once, the rest as the list is scrolled; a tap on a card updates that card only (no full redraw, no scroll jump); items, unit conversions and static data are read in parallel; stale-while-revalidate: when the item list is already on the phone (earlier open, or the saved offline copy) the POS draws from it at once and swaps in the fresh list only if something changed; skeleton cards + "Loading..." while it loads; `content-visibility:auto` on cards; the three body-wide observers ignore mutations inside the card grid; a11yfix asks ONE question per added node instead of ten.

## 3. Results: Home (signed-in owner)

Cold = first ever visit. Warm = returning after the 10-minute HTTP max-age (every file revalidated, 304). Hot = returning within 10 minutes. "to Home" = until the Home tiles are on screen; "incl. background" = the whole 9 s visit (service worker, idle decorators).


Slow 4G (1.6 Mbit/s, 75 ms RTT) + CPU 4x
| build | visit | requests to Home | KB gzip to Home | requests / KB incl. background (SW, idle) | first paint ms | Home interactive ms | scripting ms to Home | long tasks >50 ms (n / sum ms) | layout shift |
|---|---|---|---|---|---|---|---|---|---|
| OLD public 24e53bb (before Cat/Img/Opt/Q4/Sec) | cold | 108 | 1048 | 219 / 2099 | 2244 | 6599 | 432 | 5 / 973 | 0.015 |
| OLD public 24e53bb (before Cat/Img/Opt/Q4/Sec) | warm | 108 | 0 | 110 / 0 | 820 | 1588 | 358 | 3 / 824 | 0.014 |
| OLD public 24e53bb (before Cat/Img/Opt/Q4/Sec) | hot | 0 | 0 | 1 / 0 | 528 | 1233 | 346 | 3 / 866 | 0.014 |
| OLD public main d1b3a83 | cold | 117 | 1122 | 237 / 2247 | 1352 | 7275 | 658 | 5 / 1187 | 0.075 |
| OLD public main d1b3a83 | warm | 117 | 0 | 119 / 0 | 844 | 1911 | 448 | 4 / 885 | 0.075 |
| OLD public main d1b3a83 | hot | 0 | 0 | 1 / 0 | 824 | 1608 | 320 | 4 / 961 | 0.075 |
| CURRENT tip (before this step) | cold | 117 | 1123 | 237 / 2247 | 532 | 15485 | 612 | 5 / 848 | 0.072 |
| CURRENT tip (before this step) | warm | 117 | 0 | 119 / 0 | 344 | 11531 | 596 | 3 / 734 | 0.072 |
| CURRENT tip (before this step) | hot | 0 | 0 | 1 / 0 | 192 | 2773 | 553 | 3 / 718 | 0.072 |
| NEW build (this step) | cold | 7 | 470 | 22 / 573 | 756 | 3503 | 356 | 6 / 1503 | 0.014 |
| NEW build (this step) | warm | 3 | 0 | 5 / 0 | 312 | 820 | 261 | 3 / 1027 | 0.014 |
| NEW build (this step) | hot | 0 | 0 | 1 / 0 | 216 | 675 | 240 | 3 / 930 | 0.014 |

Fast 3G (1.6 Mbit/s, 280 ms RTT) + CPU 4x
| build | visit | requests to Home | KB gzip to Home | requests / KB incl. background (SW, idle) | first paint ms | Home interactive ms | scripting ms to Home | long tasks >50 ms (n / sum ms) | layout shift |
|---|---|---|---|---|---|---|---|---|---|
| OLD public 24e53bb (before Cat/Img/Opt/Q4/Sec) | cold | 108 | 1048 | 190 / 1887 | 1324 | 6712 | 368 | 4 / 951 | 0.015 |
| OLD public 24e53bb (before Cat/Img/Opt/Q4/Sec) | warm | 108 | 0 | 110 / 0 | 692 | 1749 | 348 | 3 / 719 | 0.014 |
| OLD public 24e53bb (before Cat/Img/Opt/Q4/Sec) | hot | 0 | 0 | 1 / 0 | 644 | 1552 | 446 | 3 / 908 | 0.014 |
| OLD public main d1b3a83 | cold | 117 | 1122 | 196 / 1882 | 1524 | 7056 | 314 | 4 / 921 | 0.075 |
| OLD public main d1b3a83 | warm | 117 | 0 | 119 / 0 | 1364 | 4071 | 430 | 6 / 1560 | 0.075 |
| OLD public main d1b3a83 | hot | 0 | 0 | 1 / 0 | 604 | 1916 | 388 | 3 / 888 | 0.075 |
| CURRENT tip (before this step) | cold | 117 | 1123 | 195 / 1870 | 984 | 41390 | 727 | 5 / 925 | 0.072 |
| CURRENT tip (before this step) | warm | 117 | 0 | 119 / 0 | 888 | 36818 | 792 | 4 / 827 | 0.072 |
| CURRENT tip (before this step) | hot | 0 | 0 | 1 / 0 | 332 | 3250 | 571 | 2 / 843 | 0.072 |
| NEW build (this step) | cold | 7 | 470 | 22 / 573 | 1104 | 3505 | 228 | 4 / 1075 | 0.014 |
| NEW build (this step) | warm | 3 | 0 | 5 / 0 | 640 | 1305 | 238 | 4 / 1343 | 0.014 |
| NEW build (this step) | hot | 0 | 0 | 1 / 0 | 220 | 855 | 318 | 4 / 1203 | 0.014 |


Target check (Slow 4G, 4x CPU, cold, against the CURRENT tip): transferred to Home 1123 KB -> 470 KB (-58 %), the whole first visit 2247 KB -> 573 KB (-74 %), requests to Home 117 -> 7, Home interactive 15.5 s -> 3.5 s (Fast 3G: 41 s -> 3.5 s; returning visit 11.5 s -> 0.8 s). Script evaluation at load (trace) 550 -> 216 ms (-61 %); the CDP ScriptDuration to Home 612 -> 356 ms (-42 %) because compiling the 1.6 MB core is part of it, so the "scripting -50 %" target is met for evaluation and NOT fully for the CDP metric (see section 6 for the next lever). The old public bundles (24e53bb 6.6 s, main 7.3 s cold) are beaten too.

Top 15 scripts by gzip bytes (current tip): assistant 30.8 KB, entry 29.7, nav 26.6, employees 22.7, forms_staff 22.4, accounts 22.1, forms_stock 21.5, stock2 21.0, partners 20.5, itemmaster 19.2, reports 18.4, forms_sales 18.2, forms_cash 17.9, pos 17.7, scan 17.5 (+ vendor/supabase.js 55 KB). Execution at load (trace, 4x CPU, ms): salereturn 62 (start-up loop), assistant 20, forms_cash 14, theme_glass 12, stock2 10, payroll 10, forms 10, attend2 9, invoice 8, ia 8, invoiceview 8, app 8, accounts 8, attendance 7, a11yfix 7 = 550 ms over 111 files; in the build core.js 185 ms + decorators 20 ms. Long tasks > 50 ms: 3-6 per start (one is parsing core.js).

## 4. POS with 1369 items (231 categories), 4x CPU, 75 ms RTT

| | before (tip) | after |
|---|---|---|
| first POS open: tap -> cards visible | 3434 ms | 656 ms |
| second open (same session) | 1889-3656 ms | 260 ms (list from memory, refreshed in the background) |
| longest single task | 2493 ms | 144 ms |
| DOM nodes after open | 8605 | 4848 (a window of 72 cards, more as the list scrolls) |
| database calls per open | 1 rpc + 5 reads first, 1 + 2 later; items as 2 serial pages | same calls, items / conversions / static data in parallel; later opens do not wait |
| per sale | 1 record_sale call, 0 other reads | unchanged (asserted) |
| loading state | text only | skeleton cards + text, loading bar after 150 ms, "Slow connection" + Retry after 6 s |

Redundant round trips: none large; the cost was serial waiting and the 1369-card render. `loadStatic()` reads the full item list once per session (a second copy of what POS reads); left alone (entry.js).

### Decorators (MutationObservers) per interaction, tip, POS open with 1369 items, 4x CPU
Callback time is small; the cost is the work they schedule (re-scanning the page after every insert).

```
observer (script)       | POS calls/records/callback-ms | Home | Customers | Stock
a11yfix.js             69/7832/189ms | 0/0/0ms | 4/8/3ms | 7/15/5ms
badges107.js           69/106/3ms | 0/0/0ms | 4/8/1ms | 7/12/0ms
catpick.js             69/106/3ms | 0/0/0ms | 4/8/0ms | 7/12/0ms
controls.js            102/15283/4ms | 0/0/0ms | 4/8/2ms | 7/12/1ms
dashx.js               69/106/1ms | 0/0/0ms | 4/8/0ms | 7/12/0ms
itemimg.js             69/106/4ms | 0/0/0ms | 4/8/0ms | 7/12/1ms
landed.js              69/106/2ms | 0/0/0ms | 4/8/0ms | 7/12/0ms
pay.js                 69/106/20ms | 0/0/0ms | 4/8/0ms | 7/12/0ms
purchaseprint.js       35/72/5ms | 0/0/0ms | 2/4/0ms | 4/7/0ms
scripting ms (all): pos_1369_items=1177 task=6500  home=0 task=39  customers=33 task=262  stock=40 task=207
```
Switching one off (observe() ignored) saves, while the POS opens: a11yfix -1039 ms scripting / -2.6 s task, controls -1079 / -3.8 s, catpick -91 / -0.5 s, pay -1.2 s task, dashx -1.8 s task. After the card-grid guards the task total is 6.5 s -> 3.4 s; what is left is their work for the 231 category chips and the shell, not for the cards. Home, Customers, Stock: each observer < 5 ms per screen. itemimg is off by default and returns at once.

## 5. Tests

* `tests/web/lazy_test.js` (new): built index has <= 5 script tags + lazy map; 15 deep links on a cold start (employees, accounts, purchase, landed, assistant, customers, dashx, whatsnew, settings2, payroll, attendance, finance2, partners, costing, books85); all 127 ia.js routes show the same screen title as plain `web/`; no page error that plain web/ does not also have; each script requested once; revisits add no listeners; a blocked script shows the retry screen and Retry works; service worker: one cache, core only (19 entries, none of the lazy screens), offline cold start opens the shell and the POS cards, an offline sale is queued, a lazy screen opened offline says "needs internet".
* `tests/web/order_lazy_test.js` (new copy of the invariants lazy loading changes; `order_test.js` is unchanged and still checks `web/index.html`), `tests/web/catpick_b3_test.js` (catpick_b2 without the "at most 14 added lines vs origin" guard; this branch edits pos.js on purpose), `tests/web/posload_test.js` (1369 items: loading state, window of cards, first-card time, long task, round trips, one sale).
* Full suite: @@RESULTS@@

## 6. Not done / honest limits

* The core is still 1.6 MB minified (455 KB gzip): 25 scripts are pulled in by static references from eager code (forms*, items2/itemmaster/bulkitems/locations, reports/daybook/salary, stock2/recipes, ownerboard, notifications, optviews ...). Making the six forms files lazy needs a small change in nav.js/app.js (their "is this form live" checks read `BOS.forms[code]`); stock2/reports lazy needs `B.flagChip` in entry.js guarded. Estimated further -25 % core bytes and the rest of the scripting target.
* The POS card window means a keyboard-only user cannot Tab through all 1369 cards without scrolling (search and category filter are the way); phone POS is touch.
* HTTP caching on GitHub Pages cannot be changed (max-age=600); the per-file `?v=` and the service worker make returning visits independent of it.
* Measured on a laptop with throttling, not on the owner's phone; one shared link, no packet loss. Google Fonts are blocked in the harness (the real font CSS is now non-blocking).
* `swupdate_test` (needs a git source and the old make_bundle), `a11y_test` (script-order + "a11yfix blocked" comparison) and `errlog_test` (build id from the first `?v=` script) are written for one-tag-per-script pages: on the bundle they fail only on those assertions; they pass on `web/`.

## 7. Reproduce

```
tools/build_web.sh                                   # -> dist/ (installs terser + esbuild into ~/.cache/bos-build once)
tools/build_web.sh --to /home/user/islamia-bos-app   # also sync into the public checkout (a pages/* branch; never pushes)
WEB_DIR=$PWD/dist bash tests/web/run_all.sh          # suite against the build
node tests/web/lazy_test.js; node tests/web/order_lazy_test.js; node tests/web/posload_test.js
NET=slow4g CPU=4 node tests/web/webload_measure.js tip=web new=dist
node tests/web/webload_observers.js
```
