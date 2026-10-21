# DESKTOP_LAYOUT: making the web app a real PC page (spec and plan, 21 Oct 2026)

## বাংলা সারাংশ

মালিক চেয়েছেন একই সিস্টেম, একই ডেটাবেস, কিন্তু পিসিতে যেন সত্যিকারের ডেস্কটপ ওয়েব পাতার মতো দেখায়। এখন পিসিতে পুরো অ্যাপ ৬৪০px-এর একটা সরু ফোন-কলামে আটকে আছে (`#app { max-width: 640px }`)।
সমাধান: ফোনের ৩৬০px চেহারা **একটুও বদলাবে না**। ১০২৪px-এর বেশি চওড়া পর্দায় আলাদা একটা ডেস্কটপ CSS ফাইল (`web/desktop.css`) চালু হবে: বাঁ দিকে স্থায়ী মেনু (এখনকার drawer-এর হুবহু একই লিস্ট), উপরে টপ বার, মাঝে চওড়া কাজের জায়গা, টেবিল পুরো চওড়ায়, নিচের bottom bar লুকানো, পপ-আপ শিট মাঝখানের ডায়ালগ।
সব পাতাকে ৬টা ধরনে (ফর্ম, তালিকা, টেবিল/রিপোর্ট, ড্যাশবোর্ড, POS, সেটিংস) ভাগ করা হয়েছে; প্রতিটার একটা ডেস্কটপ টেমপ্লেট। আগে হবে POS ও সেল, তারপর স্টক, হিসাব, রিপোর্ট। মিষ্টির ব্যবসা আগে, অন্য ব্যবসা আলাদা।
কোনো ডেমো ডেটা নেই, ছাপা ফর্মের কোড অপরিবর্তিত, লাইভ ডেটাবেস বা পাবলিক রিপো ছোঁয়া হবে না। এই কাজে কোনো কোড লেখা হয়নি, শুধু পরিকল্পনা।
ফোনে সমস্যা হলে `localStorage.bos_layout = 'phone'` দিলে সবসময় ফোন-চেহারা (escape hatch)। পুরো কাজ ফিচার-ফ্ল্যাগ ও এক ফাইল মুছে ফেললেই ফেরত যায়।
`nav.js`, `ia.js`, `index.html` যে এজেন্ট ঠিক করছে সে মার্জ করার পরেই ওই ফাইলগুলো ছোঁয়া যাবে; তার আগে শুধু `desktop.css` ও টেস্ট লেখা যায়।

---

# Desktop layout specification

Scope: structure and CSS strategy only. No business rules, no printed-form codes, no live Supabase, no public-repo change, no demo data. Same screens, same RPCs, same routes. Everything below was read from branch `claude/supabase-readonly-audit-xo3qkp` (tip `8a25d49`). Line numbers refer to that tip and will drift.

## 1. Audit of the current shell

### 1.1 Why a PC shows a long narrow phone screen

| Fact | Where |
|---|---|
| The whole app is one column: `#app { max-width: 640px; margin: 0 auto; padding: 0 16px 100px; }` | `web/styles.css:24` |
| Sticky header is bled to the column edges with `margin: 0 -16px` and so is only 640px wide | `web/styles.css:29` (`header.top`) |
| Bottom bar is capped to the same column: `.bnav { max-width: 640px; margin: 0 auto; position: fixed }`; `body.has-bnav #app { padding-bottom: 96px }` | `web/styles.css:342,349` |
| Fixed action bars: `.actionbar` (max-width 640) and `.pos-bar` (full viewport width, `left:0; right:0`) | `web/styles.css:141,172` |
| Sheets (bottom-sheet modal): `.sheet-bg` flex-end, `.sheet { width:100%; max-width:640px; border-radius:20px 20px 0 0 }` | `web/styles.css:106-107`; created by `openSheet` at `web/app.js:70-77` |
| Barcode/other sheet `.bc-card` 640px, bottom aligned | `web/styles.css:422-423` |
| Control (select/menu) sheets: 480px/360px, **already centred above 641px** (`@media (min-width: 641px)`) | `web/controls.css:23-26` |
| Info-hint sheet 640px | `web/infohint.js:44` (inline CSS) |
| Invoice/pay offer bars hard-code `max-width: 616px` | `web/invoice.js:125`, `web/invoiceview.js:138` |
| Drawer is an overlay: `position: fixed; width: min(86vw, 340px)`, hidden by `transform: translateX(-102%)`, plus `.scrim` | `web/styles.css:297-301` |
| Only one real width breakpoint exists in the shell: `@media (min-width: 640px) { .pos-grid { 3 columns } }` | `web/styles.css:185` |
| Base font 17px, line-height 1.7; fonts Anek Bangla / Hind Siliguri / Cormorant Garamond | `web/styles.css:19-23`, `web/index.html:15` |

So at 1440px the app is a 640px strip in the middle with empty margins, an overlay drawer opened by a hamburger, and a phone bottom bar.

### 1.2 How each shell part works

- **Page shell**: `shell(title, body, back)` in `web/app.js:52-68` rewrites `#app.innerHTML` on every route: `<header class="top">` (menu button, back arrow, "Main" button `.navmain`, "Back 2/3" buttons, `<h1>`, `headExtra()`), then `nav.crumb()`, then the page body. The header lives inside `#app`, so it is re-created per screen.
- **Drawer**: `web/nav.js` `mount()` (line 308) creates `.scrim` and `.drawer`; `renderDrawer()` (327) builds head (logo, name, close button), search box (`#nav_q`), body (`dr_body`: favourites, the 13 groups from `web/ia.js`, items filtered by each record's `ok(c)`), and the collapsible footer `.dr-foot` (location, language, theme, online dot, logout; styles `web/styles.css:328-341`). `openDrawer()` (404) renders and shows, `closeDrawer()` (412), Esc closes and Tab is trapped inside (422-430), every `hashchange` closes it (420). `data-act="nav_open"` / `nav_close` are the handlers (840-841).
- **Bottom bar**: `.bnav` rendered by `syncBnav()` (`web/nav.js:437-462`): 4 slots chosen from `mob` priorities in `ia.js` (Home, Sell orb, a role slot, Menu, Me). Hidden on `pos` and `entry` (`hideBnav`, 439). Visible only when `body.has-bnav`.
- **Back / Main**: `data-act="goback"` and `navmain` in `web/app.js:617-618` call `BOS_NAVSTACK` (`web/navstack.js`). These must keep working unchanged on desktop.
- **Sheets and modals**: `openSheet(html)` (`app.js:70`) appends `.sheet-bg > .sheet`; `closeSheet()` removes it; `BOS_KBD.sheet` (`kbdfix.js`) adds the sticky action bar and keyboard-aware sizing (phone only concern). Other overlays: `.ctl-bg/.ctl-sheet` (controls.js), `.bc-bg/.bc-card`, `.ihint-sheet`, `#toast` (bottom centre, `bottom: 84px` when the bottom bar is shown, `styles.css:108,343`), `#lz_slow` (`styles.css:447`).
- **Registry**: `web/ia.js` is the single list: 13 groups (`GROUPS`, lines 12-26) and 217 records created with `rec(...)` (line 38). Per-record fields used for desktop: `group`, `label`, `icon`, `ok`, `mob`, `mod`, `home`, `drawer:false`, `status`. The "about 120 routes" in the brief are the 120-odd records with `drawer: true`; the other records are sub-pages, report pages and aliases that share a screen module.
- **Themes**: `web/theme.css` (skin tokens, `html[data-skin]`, sizes in `--tap`, `--sp-*`, `--fs-*`), `web/theme_glass.css` (`html[data-theme^="glass"]`, blur only on about 8 structural layers: header, bottom bar, drawer, sheets, toast, pos bar; header rule at line 181, bottom bar 182-192), `web/theme_glass.js` (loaded in `<head>`, sets `data-fx`). Theme values `dark | light | classic | glass-light | glass-dark` are set by the inline script in `index.html` (hash pinned in the CSP meta, see section 4.5).

### 1.3 Which CSS file owns what

| File | Owns |
|---|---|
| `web/styles.css` (448 lines) | base tokens, `#app`, header, cards, grids, POS grid and bar, sheets, drawer, bottom bar, home v2 blocks, dashboard rows, `table.bz`. **All layout widths.** |
| `web/theme.css` (376) | skin on top of styles.css (`html[data-skin] body ...`), icon sizes, `@media (pointer: coarse)` touch sizes (370), bottom-bar orb (283) |
| `web/theme_glass.css` (226) | glass look; no layout except `body::before` backdrop (91) |
| `web/controls.css` (66) | custom select/menu sheets; the only existing centred-dialog behaviour (23-26) |
| Inline `<style>` strings inside about 15 JS files | `charts.js:221`, `infohint.js:44`, `invoice.js:125`, `invoiceview.js:138`, `reporthub.js:364`, `market.js:43`, `payroll.js:79`, `twofa.js:79`, ... (several contain `@media print`, e.g. `accounts.js`, `invoice.js`, `reports.js`, `payroll.js`) |

`tools/web_build.js` merges **every local `<link rel="stylesheet">` in `index.html`, in that order**, into one minified `dist/app.css` (lines "the merged stylesheet, in index.html order" and "one stylesheet link where the first local one was"). The service worker precache always contains `app.css` (`pre = ['core.js', 'app.css', ...]`).

## 2. Responsive architecture

### 2.1 Principle

Mobile-first and additive. `styles.css`, `theme.css`, `theme_glass.css`, `controls.css` are not edited for layout. A new `web/desktop.css`, loaded last, contains **only** rules inside `@media (min-width: ...)`. Below 600px the file has zero effect, so the 360px layout is byte-for-byte the same pixels as today.

### 2.2 Breakpoints

| Name | Width | Behaviour |
|---|---|---|
| Phone | 360 to 599 | Unchanged. Drawer overlay, bottom bar, bottom sheets, 640px column (the column is centred when 600 to 639). |
| Tablet | 600 to 1023 | Phone shell kept (drawer overlay + bottom bar) but the column grows to `min(100% - 32px, 880px)`; lists/tables use the extra width; sheets become centred dialogs (as `controls.css` already does at 641). No persistent sidebar (not enough room next to content). |
| Desktop | 1024 and up | Persistent left sidebar 264px, top bar, bottom bar hidden, content up to 1200px (or full width for table/report pages), two-column templates, sheets as centred dialogs or side panels. |
| Wide | 1440 and up | Sidebar 288px, content cap 1360px, master-detail (list on left 420px, record on right) for list pages, POS three zones, dashboard 4 columns. |

Landscape phones (about 700 to 900px wide, `pointer: coarse`, height under 500px) stay in the Tablet tier. Desktop rules use `(min-width: 1024px)` only, not `hover`, so a touch laptop or tablet in landscape at 1024+ also gets the desktop shell and the 44px touch sizes of `theme.css:370` still apply (they key on `pointer: coarse`, not on width).

### 2.3 Persistent sidebar (from the existing drawer)

No second menu is built. At `>= 1024px` the existing `.drawer` element **is** the sidebar:

- CSS: `.drawer { transform: none; visibility: visible; width: 264px; box-shadow: none; border-inline-end: 1px solid var(--hair); }`, `.scrim { display: none }`, `#app` and `.bnav`/`.pos-bar`/`.actionbar` get `margin-inline-start`/`inset-inline-start` of the sidebar width through one custom property `--sb-w` set on `:root` inside the media query. Using logical properties keeps it correct if direction ever flips.
- Content: exactly what `renderDrawer()` builds: brand, search, favourites, the 13 groups from `ia.js` (permission-filtered by each `ok(c)`; the server stays the authority), and the `.dr-foot` block (location, language, theme, online dot, logout). The collapsible footer and the location up/down control being built by the fix agent come along automatically because they live inside `.dr-foot`; on desktop the footer defaults to **open** (there is vertical room) but keeps its toggle.
- Groups: on desktop all 13 group headers stay collapsible; the group containing the current route is expanded (`.dr-i.on`), the others remember their state in `localStorage` (per-viewer convenience only).
- JS change needed (small, in `nav.js`): (a) `mount()` renders the drawer once when `matchMedia('(min-width:1024px)').matches` and re-renders on the media-query `change` event; (b) `openDrawer()` is a no-op on desktop (the hamburger is hidden by CSS anyway); (c) the `hashchange` auto-close (line 420) and the Esc/Tab trap (422-430) are skipped when the sidebar is persistent; (d) the dialog attributes (`role="dialog"`, `aria-modal`) become `role="navigation"` + `aria-label` while persistent. Mark this the **only** nav.js change; everything else is CSS.
- The brand block, search and footer are sticky inside the sidebar; only `.dr-body` scrolls (`overflow-y: auto` already at `styles.css:307`).
- Collapsed rail: below 1280px an optional icon-only rail (72px) toggled by a button, state in `localStorage`. Phase 2, not required for the first release.

### 2.4 Top bar

`header.top` stays the same element (it holds Back, Main, Back 2/3, title, `headExtra()`), so Back/Main behaviour is untouched. On desktop it becomes a full-width sticky bar next to the sidebar: left = Back, Main, breadcrumb (`nav.crumb()` is already rendered after the header), title; right = global "do" search trigger (Ctrl+K, section 2.9), notifications/needs-you count, theme, language, user. The hamburger `.hbtn[data-act=nav_open]` is hidden. `margin: 0 -16px` is reset to 0 and padding becomes `12px 32px`.

### 2.5 Content widths

Single CSS variable `--ct-w` (content max width), set per page pattern (section 3.1) through `body[data-pat]`:

| Pattern | `--ct-w` at 1024 to 1439 | at 1440+ |
|---|---|---|
| form | 760px (centred, label above field, two columns of fields from 900px content width) | 880px |
| list | 960px | master-detail, list 420px + detail fills |
| table / report | 100% of the content area (full width, sticky header row, horizontal scroll only inside the table wrapper) | 100% |
| dashboard / home | 1120px, 12-column grid | 1360px |
| POS | 100% (own template) | 100% |
| settings | 880px, two-pane (sections nav on left 220px) | 1040px |

Until pages declare a pattern (step 4 of the plan) the default is `--ct-w: 1120px`, and any `table` wrapper and `table.bz` are forced to full content width. "No page is ever wider than the viewport": `#app` keeps `min-width: 0` and tables sit in an `overflow-x: auto` wrapper (see 4.4).

### 2.6 Master-detail on wide screens

For list pages (customers, items, dues, purchase bills, staff, exceptions...) at 1440+: left pane is the list with search and filters; right pane shows the record that the current route opens. The existing routes `#/customers` and the record route stay; the template simply renders both into the two grid areas **without changing routes**: opening a row still sets the same hash, `shell()` receives the record screen, and the CSS keeps the list visible by caching the last list DOM in `#app` slot `A` (JS step, deferred, see plan step 9). Until then wide screens use the single column list at 960px. Below 1440 master-detail is never used (record opens full width as on phone).

### 2.7 Bottom bar, action bars, toast

- `.bnav { display: none !important }` at >= 1024 and `body.has-bnav #app { padding-bottom: 32px }`; its four destinations are already in the sidebar (Home, Sell, role slot, Me via the footer/profile entry). Tablet keeps the bottom bar.
- `.actionbar` and `.p2-bar2` (sticky bottom action rows) become `position: sticky; bottom: 0` inside the content column (not viewport-fixed across the sidebar) with `max-width: var(--ct-w)`.
- `#toast` moves to bottom-end of the content area; `body.has-bnav #toast { bottom: 84px }` is overridden.

### 2.8 Sheets become dialogs and side panels

- Default: `.sheet-bg { align-items: center }`, `.sheet { width: min(720px, 92vw); max-height: 86vh; border-radius: 18px; border-top-width: 1px }`; the drag handle pseudo-element `.sheet::before` (`theme.css:231`) is hidden. Same for `.bc-bg/.bc-card` and `.ihint-sheet`. `.ctl-*` already centred.
- Side panel: sheets that show a record or a long form (class `.sheet.side`, opted in per screen later) dock to the inline-end edge: `align-items: stretch; justify-content: flex-end; .sheet { width: 520px; height: 100vh; border-radius: 0 }`.
- Backdrop covers sidebar and top bar (z-index 20 over 41? no: the drawer is `z-index: 41`; on desktop the sidebar is set to `z-index: 6` so every scrim/sheet, which sit at 20 to 70, covers it, exactly like a normal modal).
- Focus: on open focus moves to the first field (or the close button), on close returns to the opener; Esc closes (`closesheet`); Tab is trapped inside. This is a small JS addition in `openSheet` (app.js, listed in the plan).
- `BOS_KBD.sheet` keyboard-height logic is guarded by `(pointer: coarse)` already in practice; verify it does nothing on desktop (test in section 5).

### 2.9 Keyboard and mouse

- Focus ring: one rule `:focus-visible { outline: 2px solid var(--gold); outline-offset: 2px }` in desktop.css, and the glass themes use `--amber`. No outline removal anywhere.
- Hover states for every clickable row, tile, sidebar item and table row (`:hover` gated by `@media (hover: hover)`).
- Tab order: sidebar first, then top bar, then content (DOM order is sidebar (appended to body by nav.js), `#app`). Add a "skip to content" link visible on focus, first in `body` (tiny index.html/nav.js edit, planned).
- Shortcuts (all optional, never override typing in inputs): `/` or Ctrl+K opens the existing global search (`#nav_q`), `Esc` closes dialog, `Alt+Left` = Back (already the browser behaviour through `BOS_NAVSTACK`), `Alt+H` = Main/Home, `g` then `s` = Sell, `g` then `k` = Stock (two-key, off while an input has focus), `?` lists them. POS has its own keys (section 3.3).
- Tables: row hover, sticky `thead`, clickable column headers where a list already sorts, arrow-key row navigation is phase 3.
- Context menus are not added; the three-dot rule of `IA_RULES.md` (essential actions visible, others in the menu) is unchanged.

### 2.10 Print on desktop

Printed documents are built by the template modules (`invoice.js`, `invoiceview.js`, `purchaseprint.js`, `stock2.js` challan, `payroll.js`) with their own `@media print` and `<!doctype>` HTML strings (e.g. `invoiceview.js:285`). They must not see the sidebar, top bar or content max-width. desktop.css adds one print block: `@media print { .drawer, .scrim, header.top, .bnav, #toast, nav.crumb { display: none !important } #app { margin: 0; max-width: none; padding: 0 } }`. Form codes and paper layouts are not touched (`tools/check_form_codes` style baselines stay equal; see section 5.3). A4 reports (report pages) keep their own table print CSS; the desktop table wrapper has `overflow: visible` in print.

### 2.11 Themes (glass and premium)

- Every desktop rule uses existing tokens (`--bg`, `--card`, `--hair`, `--ink`, `--glass-bar`, `--glass-rim`, `--amber`, `--sp-*`). No new colours, so all five themes (`dark`, `light`, `classic`, `glass-light`, `glass-dark`) work.
- Glass: the sidebar gets `background: var(--glass-bar)` and the same border/shadow the drawer already has in `theme_glass.css`. Blur budget rule (about 8 structural layers) is kept: sidebar and top bar replace drawer and header on desktop, the bottom bar no longer renders, so the layer count does not increase. Also the existing `html[data-fx="lite"]` and `prefers-reduced-transparency` fallbacks (`theme_glass.css:217-226`) apply unchanged.
- `body::before` gradient backdrop (`theme_glass.css:91`) is `position: fixed; inset: 0`: fine behind a sidebar layout.

### 2.12 Bangla typography and direction

Bangla is left-to-right; there is no RTL requirement. Rules: keep `letter-spacing: 0` for `:lang(bn)` (`styles.css:21-22`, `theme.css:88`), line-height 1.6 to 1.7 for body Bangla (do not tighten on desktop), numbers stay `tabular-nums` Latin digits in tables, table cells must not break a Bangla word mid-grapheme (`word-break: normal; overflow-wrap: anywhere` only on label columns). Desktop base font stays 17px (do not shrink to 14px: Bangla conjuncts get illegible); table body 15px. Use logical properties (`inline-start/end`) in new CSS so a future RTL language does not need a rewrite. Fonts are the same three families already loaded.

## 3. Page-by-page plan

### 3.1 Patterns and one desktop template each

`ia.js` has 217 records in 13 groups. Each record gets one new optional field `pat` (`'form'|'list'|'table'|'dash'|'pos'|'set'`); `shell()` copies it to `document.body.dataset.pat`. A record without `pat` behaves as today (default width, section 2.5).

| Pattern | Desktop template |
|---|---|
| **form** (enter or edit one thing: the 41 paper-form screens `#/form/..`, new item, new bill, payment, return, leave, payrequest) | Centred card column 760/880px, labels above fields, fields in two columns when wide, sticky action bar at the bottom of the card, Save left / Cancel right unchanged order, side summary box (totals, ledger effect) at 1440+ |
| **list** (find and open one record: customers, items, dues, suppliers, staff, templates, locations) | Search and filters on one row, results as a dense row list or table at 960px; master-detail at 1440+ |
| **table / report** (stock balance, ledger, day book, every `report/*`, ageing, registers) | Filter bar in one row above, full-width table with sticky header, totals row sticky at bottom, export/print buttons top right; horizontal scroll only inside the table box |
| **dash** (home, owner, dashx, biz, brandpnl, targets, control, whatsnew) | 12-column grid: Now strip full width, stat cards 4 per row, charts two per row, Recent and quick actions in the right column |
| **pos** (`pos`, `cashdrawer`, `salereturn`, `flow`) | Own template, section 3.3 |
| **set** (settings, rules, switchboard, rulehub, control, organization, profile, integrations, backup, guards, paths) | Two panes: sections list left, section form right, search across settings at the top |

### 3.2 Classification of all records

Group id : routes (the record id equals the hash route; `report/<x>`, `batchrep/<x>`, `stockrep/<x>` are table pages):

- **dash (6)**: `home`, `owner`, `brandpnl`, `targets`, `x1health`: dash. `whatsnew`: list.
- **item (10)**: `items`, `bulkitems`, `categories`, `products`, `itemmap`, `itemtypes`, `lists`, `settings2/units`: list. `items/new`: form. `itemimport`: form (wizard).
- **stock (31)**: `stock`, `stockx`, `stockout`, `variants`: list/table hybrid (table first). `report/stock_balance`, `report/daily_closing`, `report/expiry_soon`, `report/item_slow`, `report/item_turnover`, `report/k2_count_variance`, `report/stock_adjustments`, `report/stock_integrity`, `report/transfers_gap`, `report/transfers_register`, `report/wastage`, `report/wastage_rate`, `batchrep/*` (6), `stockrep/ledger`, `stockrep/recon`, `stockrecon`, `branchstmt`, `xcunsold`, `trace`, `recall`: table. `assets`, `tinting`: list.
- **purch (15)**: `purchase`, `payables`, `billpay`, `partyrequest`, `landed`, `schemes`, `settings2/suppliers`: list. `purchase/new`, `purchase/return`, `purchaseprint`, `scan`: form. `purchrep`, `report/p2_rate_trend`, `report/p4_supplier_score`, `report/supplier_ageing`: table.
- **factory (14)**: `prodplan`, `recipes`, `recipebook`, `costing`, `costsources`, `capacity`: list. `s1setup`: set. `cost116drv`, `cost116gl`, `cost116queue`, `cost116stage`, `cost116var`, `costattrib`, `prodreports`: table.
- **sale (11)**: `pos`, `cashdrawer`, `flow`: pos. `salereturn`: pos/form. `invoiceview`, `onlineorders`, `inbox`, `saleschannels`, `discounts`: list. `orderreports`: table. `website`: set.
- **cust (21)**: `customers`, `dues`, `tiers`, `crmlists`, `crmleads`, `crmtasks`, `crmcoupons`, `crmloyalty`, `crmfeedback`, `crmconsent`, `crmdupes`, `cakejobs`, `riders`, `templates`, `packflags`, `invoice`, `bankreceipt`: list. `crm360`: master-detail (special). `crmvalue`, `custinsight`: dash/table. `inboxpii`: list.
- **acc (24)**: `daybook`, `ledgerlinks`, `books85`, `books96`, `cashmoves`, `shortages`, `profitcheck`, `balancecheck`, `freshness`, `finance2`, `accounts`, `cheques`, `monthclose`: table. `quickexp`, `otherincome`, `employees/new`, `deeds`: form. `employees`, `moneyaccounts`, `wallets`, `openparties`, `paycapture`: list. `periodlock`, `moneycontrols`: set.
- **appr (17)**: `exceptions`, `pending`, `emergency`, `releases`, `changes`, `itemreq`, `payapprovals`, `posfailed`, `outbox`, `notifications`, `unmatched`, `transitshort`: list with inline approve (master-detail at 1440). `auditreports`, `numaudit`, `eqcheck`, `expenselink`, `formguard`: table.
- **reports (18)**: `report`, `reports`, `reports/hub`, `reports/map`, `reports131`, `biz`, `netprofit`, `statements`, `expenseregister`, `costunknown`, `couponuse`, `campaigns`, `catreport`, `forecast`, `market`, `biexport`: table (hub and map: dash). `dashx`: dash. `assistant`: special (chat).
- **people (13)**: `staff`, `matrix`, `attendance`, `attend2`, `leave`, `shifts`, `todo`, `announce`, `payroll`, `salary`, `benefitsx`, `payrequest`, `staffreports`: list (matrix and payroll: table; payrequest: form).
- **loc (4)**: `locations`, `locset`, `locsheet`, `rollout`: list/set.
- **settings (32)**: `settings`, `settings2`, `rules`, `rulehub`, `switchboard`, `control`, `delegation`, `organization`, `profile`, `integrations`, `connect`, `backup`, `restoredrill`, `guards`, `paths`, `parallel`, `optionsx`, `optviews`, `returnrules`, `payreqsettings`, `setupadvisor`, `twofa`, `printbooks`, `saleforms`, `partners`, `camrec`, `itemimg`, `impexp`, `xcsummary`: set. `logs`: table. `problems`, `reportproblem`: list/form.

Business scoping (owner rule): sweets business first; the pages of other businesses (Variants, Cheque/PDC, Schemes, Tinting, Import-Export, listed as PARTIAL in `DEMAND_VERIFY.md`) get the same templates but are **last** in the order and are not given special work; they keep today's visibility rules (this task does not change what the owner sees).

### 3.3 POS template (special work)

Desktop POS = three zones in one viewport with no page scroll: left category rail (sweet_kg, sweet_pc, doi, ...; the existing `data-cat` colours), centre item grid (4 to 6 columns, existing `.pos-item` tiles, `pos-grid` from 3 columns at 640 to `repeat(auto-fill, minmax(150px, 1fr))`), right cart panel 380px sticky with the existing cart and `.pos-bar` total/pay button moved from viewport-fixed into the panel bottom. Barcode scanner input (`barcode.js`) keeps focus by default on desktop, keys: `F2` focus search/scan, `F4` pay, `Esc` clear search, `+`/`-` quantity of last line, `Del` remove line. These are listed as optional and live in a new file only when the plan reaches step 6.

### 3.4 Pages needing special work (explicit list)

1. `pos` (and `cashdrawer`, `salereturn`, `flow`): own three-zone template (3.3).
2. `home` / `owner` / `dashx` / `biz`: dashboard grid; stat tiles use `.stats` (2 columns) and `.qgrid` (2 columns) today.
3. `crm360`, `customers`, `exceptions`, `pending`, `emergency`: master-detail.
4. `reports/hub` (Business Memory), `reports/map`, `report` (hub) and `dashx`: charts and filter bars (`reporthub.js:364` has its own breakpoint at 380).
5. `daybook`, `books85`, `books96`, `accounts`, `stockx`, `stockrep/ledger`, `payroll`, `matrix`: wide tables with sticky header and totals.
6. `assistant`: chat layout (messages left, tools right).
7. Form screens `#/form/<code>` (41 forms; module `formscreens.js`, `forms*.js`): form template; **codes and printed paper forms unchanged**.
8. Invoice view and print pages (`invoiceview.js`, `purchaseprint.js`, challan in `stock2.js`): inline `max-width: 616px/760px` bars (invoice.js:125, invoiceview.js:138) must not stick to viewport centre across the sidebar.
9. `settings`, `rules`, `switchboard`, `control`: two-pane settings with in-page search.

### 3.5 Priority order

1. Shell (sidebar, top bar, no bottom bar, dialogs): affects all pages at once.
2. POS and sale (`pos`, `salereturn`, `cashdrawer`, `invoiceview`, `dues`).
3. Stock (`stock`, `stockx`, stock reports, `purchase`, `purchase/new`, `payables`).
4. Accounts (`daybook`, `cashmoves`, `books*`, `accounts`, `monthclose`, `quickexp`).
5. Reports (hub, map, all `report/*`, `dashx`, `biz`).
6. Home, approvals, customers/CRM, people/payroll.
7. Factory, settings, locations.
8. Other-business pages and the long tail.

## 4. CSS strategy that does not break the phone

### 4.1 One new file

`web/desktop.css`, linked last in `<head>` of `web/index.html` (after `theme_glass.css`):

```html
<link rel="stylesheet" href="desktop.css">
```

- Because `tools/web_build.js` merges all local stylesheet links in index.html order, `desktop.css` is automatically appended to `dist/app.css` and is in the service-worker precache (`app.css` is in `pre`). **No change to `tools/web_build.js` or `tools/web_lazy.json` is needed.** The standalone minified copy `dist/desktop.css` is also emitted (the builder keeps originals), so an old cached `index.html` never 404s.
- Size budget: at most 12 KB minified (about 3 KB gzip); checked by a test (section 5).
- Contents: only `@media (min-width: 600px)`, `(min-width: 1024px)`, `(min-width: 1440px)`, `print` blocks. A test asserts that no rule exists outside a media block (so the phone can not regress by accident).
- Specificity: new rules use the same prefix as the rules they override (`html[data-skin] body ...` where theme.css does) and never `!important`, except hiding `.bnav` and `.scrim`, which already use `body.has-bnav` toggles from JS.

### 4.2 Escape hatch and feature flag

- User escape: `localStorage.bos_layout = 'phone'` makes the page always use the phone layout; `'desktop'` forces desktop; absent = automatic by width. Read in `web/theme_glass.js` (already loaded in `<head>` and in the precache) which sets `html[data-layout]`. This **avoids editing the inline theme script in index.html**, whose sha256 is pinned in the CSP meta (checked by `tests/web/sec2_csp_test.js`).
- Every desktop block is written as `@media (min-width: 1024px) { html:not([data-layout="phone"]) ... }`. A viewer can switch it in Settings, "Screen layout: automatic / phone / PC" (a three-option row in `settings2`, later step).
- Owner switch (build rule 'every owner decision is a setting with a safe default'): rule key `ui_desktop_layout`, default **true on screens >= 1024 only**; when set to false the app ignores desktop.css by setting `data-layout="phone"` for everybody. Reading a rule needs `B.rule` (available after login); before login the automatic width rule applies, so the login screen is a normal centred card.
- Rollback = delete the `<link>` line (one line of index.html) or flip the rule; nothing else depends on it.

### 4.3 Shell variables

```css
@media (min-width: 1024px) { :root { --sb-w: 264px; --top-h: 60px; --ct-w: 1120px; } }
@media (min-width: 1440px) { :root { --sb-w: 288px; --ct-w: 1360px; } }
```

### 4.4 No horizontal overflow

`html, body { overflow-x: clip }` on desktop only; `#app { min-width: 0 }`; every `table` that is not wrapped gets the wrapper class through a CSS-only approach: `#app :is(table.bz, .tbl, table) { display: block; max-width: 100%; overflow-x: auto }` is **not** used (it breaks table semantics). Instead pages keep their own wrappers and the audit test (5.2) lists pages where `scrollWidth > clientWidth` at 1024 and 1440 and each is fixed by wrapping that one table.

### 4.5 Files that may need small non-CSS edits (all marked in the plan)

`web/nav.js` (sidebar mount), `web/app.js` (`shell()` sets `data-pat`; `openSheet` focus/Esc), `web/ia.js` (`pat` field), `web/index.html` (the `<link>` line and a skip link), `web/theme_glass.js` (layout flag). The CSP hash stays valid because the inline script is not edited.

## 5. Test plan

### 5.1 New Playwright suite `tests/web/desktop_layout_test.js`

Uses the same mocked-RPC harness as `navfold_test.js` / `glass_test.js` (copy their login mock; no live Supabase, only `test_*` identifiers, no staff or demo names). Viewports: 360x740, 768x1024, 1024x768, 1440x900. Screens: `home`, `pos`, `stock`, `daybook`, `report/stock_balance`, `customers`, `settings`, one `form/<code>` screen. Checks per viewport:

| Check | 360 | 768 | 1024 | 1440 |
|---|---|---|---|---|
| `document.documentElement.scrollWidth <= innerWidth` (no horizontal overflow) | yes | yes | yes | yes |
| `#app` computed width | <= 640 (unchanged) | <= 880 | > 640 | > 900 |
| sidebar (`.drawer`) visible without clicking | no | no | yes | yes |
| bottom bar (`.bnav`) visible | yes (signed-in, non-POS) | yes | no | no |
| hamburger visible | yes | yes | no | no |
| table width equals content width on report pages | n/a | n/a | yes | yes |
| `.sheet` is centred (not bottom aligned) after opening a sheet | no | yes | yes | yes |
| Back (`goback`), Main (`navmain`), Back 2/3 buttons work and are visible | yes | yes | yes | yes |
| Esc closes sheet; focus returns to opener | n/a | yes | yes | yes |
| Tab order starts in sidebar then content | n/a | n/a | yes | yes |
| forced phone: `localStorage.bos_layout='phone'` at 1440 equals 360 layout | n/a | n/a | n/a | yes |

Plus: a **pixel guard** for the phone: screenshot of `home`, `pos` and a form at 360 compared with the committed `tests/web/*_360.png` style baselines using a tolerance of 0 differing pixels, run with and without `desktop.css` linked (proves zero effect below 600).

### 5.2 Overflow audit script

A throwaway loop (not committed) opens every `drawer:true` route at 1024 and 1440 with mocked empty data and prints routes whose `scrollWidth` exceeds the viewport; the list becomes the work list of steps 7 to 9.

### 5.3 Keeping the 186 existing suites green

- Existing suites run at 360px and never match `min-width: 600px`; desktop.css is inert for them. Run `python3 tests/web/run_all.py` (copy-based runner) before the first and after every commit and compare `summary.txt`.
- Suites that run wider than 600 (grep `viewport` in `tests/web`; only a few) are run first after each commit.
- Check also: `node tests/web/ia_test.js <abs tests/web>`, `nav`, `nav2`, `navfold`, `navstack`, `control`, `favsync`, `settings2`, `glass`, `glass_b2`, `a11y`, `sec2_csp`.
- Build checks: `node tools/web_build.js --out <scratch>/dist` must still print the merged-stylesheet and precache lines; `dist/app.css` must contain the `desktop.css` rules.
- Repo guards before every commit: `python3 tools/check_no_demo_leak.py` (OK), `tools/check_ui_inventory.py` (nothing lost or renamed), form-code baseline diff against `6bf2f6f` (printed form codes unchanged).

## 6. Implementation plan: small commits

Legend: **P** can run in parallel now (touches only new files or CSS not edited by the fix agent). **W** must wait until the current fix agent has merged (edits `nav.js`, `ia.js`, `index.html`, or the footer/location code).

| # | Commit | Files | Mode | Est. |
|---|---|---|---|---|
| 1 | Desktop shell CSS skeleton: breakpoints, variables, content width default, hide bottom bar and hamburger, header full width, sidebar styles for `.drawer` (inert until nav.js step) | `web/desktop.css` (new) | P | 0.5 d |
| 2 | Dialogs: sheets as centred dialogs and side panel class; `.bc-card`, `.ihint-sheet`; toast and action bars | `web/desktop.css` | P | 0.5 d |
| 3 | Print block, focus rings, hover, theme-glass variants (uses only tokens) | `web/desktop.css` | P | 0.5 d |
| 4 | Test suite and pixel guard | `tests/web/desktop_layout_test.js` (new) | P | 1 d |
| 5 | Link the file and the layout flag: `<link>` line, `data-layout` read, skip link | `web/index.html`, `web/theme_glass.js` | **W** | 0.25 d |
| 6 | Persistent sidebar: render drawer on desktop, skip auto-close/trap, ARIA role | `web/nav.js` | **W** | 1 d |
| 7 | Pattern field and `data-pat`: add `pat` to records (script-assisted from section 3.2), `shell()` copies it | `web/ia.js`, `web/app.js` | **W** | 1 d |
| 8 | POS template (3 zones, shortcuts) | `web/desktop.css`, `web/pos.js` (only class hooks, no logic) | after 5, 6; P with 9 | 2 d |
| 9 | Table/report template, full-width tables, overflow fixes from the audit | `web/desktop.css`, small wrappers in the offending report modules | after 5, 6 | 2 d |
| 10 | Stock, accounts, forms templates | `web/desktop.css` | after 7 | 1.5 d |
| 11 | Dashboard grid, home, owner, dashx | `web/desktop.css`, `web/dash.js` class hooks | after 7 | 1 d |
| 12 | Master-detail for lists (1440+) and settings two-pane | `web/desktop.css`, `web/app.js` | after 7 | 2 d |
| 13 | Settings row "Screen layout" and owner rule `ui_desktop_layout` (new SQL phase file only if the rule needs a default row; safe to paste twice) | `web/settings2.js`, new `supabase/phaseNNN_*.sql` | **W**, owner pastes SQL | 0.5 d |
| 14 | Long tail: other-business pages, rail mode, keyboard shortcuts overlay | `web/desktop.css`, `web/nav.js` | after 8 to 12 | 1.5 d |

Parallel groups: commits 1 to 4 together (4 files, no conflicts with the fix agent). Commits 8 and 9 in parallel after 5 and 6.

Total: about 15 working days for one developer (about 10 with two in parallel), first usable release (commits 1 to 6 plus 9) about 5 days.

Every commit: run the suites of 5.3, run `check_no_demo_leak.py`, rebase on `origin/claude/supabase-readonly-audit-xo3qkp`, push without force. New SQL (commit 13 only) goes in a new phase file, never edits an old one, and the owner pastes it himself after review; nothing in this plan writes to the live Supabase project.

### Risks

| Risk | Mitigation |
|---|---|
| Phone regression through a rule leaking outside a media query | CSS-only test that asserts every rule is inside a media block; pixel guard at 360 |
| Fix agent edits `nav.js`/`index.html` at the same time | commits 5 to 7 and 13 wait for its merge; commits 1 to 4 do not touch those files |
| Inline `<style>` blocks in JS modules (15 files) fight desktop.css | same-or-higher specificity prefix; fix per module in the audit steps |
| CSP hash break if the inline theme script is edited | never edit it; flag read goes in `theme_glass.js` |
| Glass blur cost on desktop GPUs is fine, but on a weak PC | the existing `data-fx="lite"` fallback applies; layer count does not grow |
| Pages with fixed `max-width: 616px` bars | listed in 3.4 item 8 |
| Persistent sidebar and `Esc`/focus-trap code expecting a modal drawer | skip logic in step 6, tested in 5.1 |
| Printed forms affected by the new print block | print block only hides shell parts; form codes and template HTML untouched; baseline diff in 5.3 |

### Rollback

1. Soft: set `localStorage.bos_layout = 'phone'` (one viewer) or owner rule `ui_desktop_layout = false` (everyone).
2. Hard: remove the one `<link rel="stylesheet" href="desktop.css">` line from `web/index.html` and rebuild; the nav.js sidebar code is dormant without the CSS (the drawer stays an overlay because the media-query rules are gone). `git revert` of commit 6 removes the JS part.

## 7. Decisions made (owner wants no questions)

| Decision | Reason |
|---|---|
| Phone layout is frozen: desktop code lives only in `@media (min-width: 600px+)` in a new file | owner said the 360px layout must stay as it is; a media-only file cannot change the phone |
| Desktop starts at 1024px, tablet (600 to 1023) keeps drawer and bottom bar | a 264px sidebar plus readable content needs about 1000px; portrait tablets are touch devices that already work |
| The existing drawer becomes the sidebar (same element, same `ia.js` list) | "same system": no second menu to maintain, permission filtering and the fix agent's footer and location control come for free |
| One stylesheet `web/desktop.css`, no edit to `tools/web_build.js` or `web_lazy.json` | the builder already merges every local stylesheet link and precaches `app.css`; zero build risk |
| Layout flag stored in `localStorage.bos_layout`, read in `theme_glass.js` | avoids touching the CSP-hashed inline script; works before login |
| Owner switch is a rule with a safe default (on, only effective at >= 1024) | project rule: every owner decision is a setting with a safe default |
| Tables go full width, forms stay 760 to 880px, dashboards 1120 to 1360px | long lines of form fields are hard to read; wide tables need all the columns |
| Master-detail only at >= 1440 and without new routes | keeps URLs, Back and favourites unchanged (IA rule: never rename or remove a route) |
| Sheets become centred dialogs, side panel is opt-in per screen | matches the behaviour `controls.css` already has above 641px; no per-screen rewrite |
| Page patterns added as one optional `pat` field in `ia.js` | the registry is the single source of truth (`IA_RULES.md`); records without it still work |
| Priority: shell, POS and sale, stock, accounts, reports | this is the sweets-business daily path; other-business pages last and unchanged in visibility |
| Base font stays 17px and Bangla spacing rules unchanged | Bangla conjuncts need size; desktop gets space, not smaller text |
| No keyboard shortcut works while typing in an input; POS keys only inside POS | prevents accidental sales or navigation |
| Print block hides only shell parts | printed form codes and paper templates must stay identical |
| Plan only, no code in this task | task scope; other agents are editing `web/` in the main checkout |
