# UI plan: calm premium shell for Islamia BOS (planning only)

Mode: My-style directed (brand ruby #a1111e / gold / ivory given). Direction name: **"Ivory Ledger"**: ivory paper, ink text, hairline rules, ruby only as brand + the single primary action, colour-meaning as 4px edge bars. Business lens: every screen answers "what needs my decision now, what is my money position" first.

Facts found in code: styles.css 224 lines; `shell(title, body, back)` in app.js builds header + body for every page; routes via hash (`#/page`), pages register in `window.BOS_PAGES`; actions via `data-act` + `H` map; `openSheet()` exists; tiles use `.t-ruby/.t-gold/.t-ink` FILLED gradients (the "loud" part); `.tabs button.on` is ruby-filled; `button.primary` ruby gradient; `.pos-item::before` already has a 6px category edge bar (good pattern, extend); `.flag` has 4px left border; `.chip.ok/warn/bad` exist. Dark mode already via prefers-color-scheme.

## 1. Design principles

1. Quiet surface, loud only when it matters. 90% of pixels ivory/white/ink. Colour = meaning, never decoration.
2. One primary action per screen (ruby solid, the only filled coloured button). Everything else: outline-hairline or text button. Destructive = text/outline in `--bad`, confirm in a sheet.
3. Marker, not fill. Status colour lives in a 4px edge bar (start side) or 8px dot or small chip with tinted text. Cards/tabs/buttons never get a coloured background.
4. Problems first, numbers second, navigation third.
5. Bangla first. Every label fits in 2 lines at 17px. Numbers always Latin lining digits (tabular) unless owner switches.
6. Thumb zone: primary actions bottom, search/filters reachable, tap targets >= 48px.
7. Few borders, hairlines (1px --line) instead of boxes; no double gold rule/diamond in header (too ornate for "calm"); keep a single gold hairline.

### Colour-meaning system (tokens)
Keep brand tokens. Add semantic tokens (light / dark):

| Token | Meaning | Light | Dark | Used for |
|---|---|---|---|---|
| `--sig-bad` | problem, overdue, due, blocked | #b3202c | #ff8d80 | edge bar, dot, amount text for dues |
| `--sig-warn` | warning, pending, needs decision | #b7791f | #f0c060 | edge bar, dot |
| `--sig-ok` | fine, paid, in stock | #2f7d57 | #7fd0a3 | edge bar, dot |
| `--sig-info` | info, draft, neutral-notice | #2c5f8f | #8fbbe8 | edge bar, dot |
| `--sig-none` | no state | var(--line) | | default bar |
| `--*-tint` | 8% tint of each for chip bg only | color-mix(in srgb, X 9%, var(--card)) | | chips |

Rules: red != brand ruby in meaning. Brand ruby is for logo, primary button, active nav indicator. Problem red is a slightly different, smaller-area hue so "ruby button" never reads as "error". Never colour a whole row/card/tab; max one marker per row; text colour only for the amount that is the problem (e.g. baki amount). Colour never sole signal: chip also has a word ("বাকি", "অপেক্ষায়"), or icon (!, clock, check, i). Contrast 4.5:1 for text, 3:1 for bars.

Implementation: one utility `.mk` : `.mk{position:relative;padding-inline-start:14px}.mk::before{content:"";position:absolute;inset-block:8px;inset-inline-start:0;width:4px;border-radius:2px;background:var(--mk,var(--line))}` plus `.mk.bad{--mk:var(--sig-bad)}` etc. Dot: `.dot.bad`. Chip: `.chip.bad` re-skinned to tint+text. Use logical properties so RTL/future safe.

### Button hierarchy
- Primary (`button.primary`): solid ruby, no gradient/inset gold ring, one per screen, sits in sticky bottom bar (`.actionbar`).
- Secondary (default `button`): transparent, 1px --line border, ink text. (Today it's gold border + ruby text; move to ink.)
- Tertiary `.link`: text only, ruby underline on press.
- Danger: outline/text in --sig-bad, never filled.
- Toggle/segment (`.tabs`, period tabs, role pills): inactive plain; active = ink text + 2px ruby underline (tabs) or soft ivory-dark fill `--chip-on` (pills). NOT ruby-filled.
- POS "Quick sale"/Pay button on the dark POS bar: allowed gold, because it is that screen's one primary; remove the `!important` gold override on `[data-act=pos_quick]` later and demote it to secondary-on-dark.

### Typography (Bangla + Latin mixed)
- Keep Anek Bangla (display) + Hind Siliguri (text), already loaded. Latin: Cormorant Garamond only for big money numerals and brand; for in-table/small Latin use text font (Cormorant is weak small). Set `font-variant-numeric: lining-nums tabular-nums` on all amounts.
- Scale (rem at 17px root): 0.82 caption / 1.0 body / 1.1 row title / 1.25 section / 1.6 page title / 2.2 hero money. Bangla line-height 1.6+, no letter-spacing, no uppercase/tracking on Bangla; tracking .08em only on Latin micro-labels.
- Section headings: ink, 700, no ruby colour, no `.orn` ornaments except on home brand line. Ruby text only for links and the active nav.
- Money: `৳` as small superscript `.cur`; negative/due uses --sig-bad text + word.

### Spacing / shape / motion
- 4px grid: 4/8/12/16/24. Card radius 14, buttons 12, chips 999. Shadow only on sheets/drawer/sticky bars; cards = hairline, no shadow. List rows 56px min, divider hairline, no dashed.
- Motion: 160-200ms ease-out; drawer slide, sheet rise, tab underline slide; skeleton shimmer off on low-end; no bouncing. Honour `prefers-reduced-motion` (already global).

## 2. Information architecture

### Drawer (left, slide-over, hamburger in header; scrim; search box on top filters menu items live + opens item/customer/report search results)
Collapsible groups (state remembered in localStorage per user, try/catch). Group header = label + count of attention items as small dot (not filled badge). Item visibility = existing role/grant logic (`S.ctx.perms`, `is_owner`); hidden, or shown as locked row "অনুমতি নেই" (lock card) only when owner wants discoverability (open question).

| Group | Maps to our existing modules | New / planned |
|---|---|---|
| Dashboard | home (problems first), owner dashboard `dash.js`, exceptions, release/emergency requests | Business/Accounting toggle, period tabs |
| Accounting | cash drawer/handover/reconcile (forms_cash), expenses & imprest, `biz.js` P&L/analysis, books-closed, ledger | day book, cash/bank book, trial-style summary |
| Item | `items` list, `itemreq`, categories & units (Lists) | Add Product with Advance Options, barcode, bulk price edit, stock-low view |
| Customer | customers, `dues.js` (baki), collections, credit limits | customer ledger statement, SMS/WhatsApp reminder |
| Sale | `pos.js` POS, sales papers (20-x), returns/complaints, discount slips, offline queue | sale history with filters, quotation |
| Supplier | supplier ledger, bill check (06-x) | supplier dues ageing |
| Purchase | requisition, quotation, PO, goods received, material issue | purchase list with filters |
| Stock & Factory | transfers, stock count, store ledger, factory sheets (03/04/05) | low-stock alerts (Sec 6 planned) |
| People | HR forms (02-x), staff approval, shifts | |
| Reports | **Report hub** (see wireframes), weekly/monthly (01-x), analysis, change log, audit log | saved views, custom report builder |
| Settings (owner) | Rules hub, Who may do what, Lists, Location limits, Form rules, Staff, Backup | |

Footer of drawer: language (bn/mix/en), location switcher (multi-shop), sync/offline status, logout. Move `langBar()` out of the header into drawer footer (header becomes: hamburger, title, search icon, one contextual icon).

### Bottom nav (4 + centre action is NOT used; keep calm)
`হোম` (home) · `মেনু/ফর্ম` (grid of all forms/modules, the current area tiles) · `বিক্রি` (POS; basket icon) · `আমি` (profile: me, shift, PIN, language). Reports reached from home + drawer. Active = ink icon + 2px ruby top indicator + label; inactive muted. Hidden on POS (POS has its own bar) and in entry forms (action bar replaces it).

### Home per role
- Owner: (1) Attention strip: list of rows with edge bars (emergency requests, release requests, staff approval, exceptions), max 5, "সব দেখুন". (2) Business/Accounting segmented toggle + period tabs. (3) Money row: Sales, Cash in drawer, Baki (due), Expenses; each a plain stat with small delta + one edge bar if abnormal. (4) Multi-shop combined card with per-shop rows (bar by shop health). (5) Quick-action icon grid (6-8, owner-editable, monochrome line icons in ivory chips, label under). (6) 7-day sales sparkline.
- Manager/showroom: Attention (own approvals), today sales vs yesterday, cash status, quick grid (POS, collect baki, expense, stock count, handover).
- Cashier/staff: big POS button is the one primary; today's drawer count; dues to collect; quick grid limited to granted forms. Locked modules appear as "অনুমতি নেই" lock card (hairline, lock icon, muted) only in the grid, one line.
- Factory/store staff: today's sheets to fill (status dots), quick grid by grant.

## 3. Wireframes (390px)

### Home (owner)
```
┌──────────────────────────────────┐
│ ☰  ইসলামিয়া মিষ্টি ঘর      🔍  ⋮│  hairline gold
├──────────────────────────────────┤
│ [ ব্যবসা | হিসাব ]   (segmented) │
│ আজ  সাপ্তাহিক  মাসিক  বার্ষিক  সব  │  underline tabs, scroll-x
│                                  │
│ ▌বিক্রি          ▌নগদ            │  ▌= 4px bar only if state
│  ৳ 48,200         ৳ 21,500       │
│  গতকাল +6%        গণনা বাকি      │
│ ▌বাকি            খরচ             │
│  ৳ 1,12,400 (লাল)  ৳ 6,300       │
│                                  │
│ সিদ্ধান্ত দরকার (3)               │
│ ▌জরুরি অনুরোধ · মিরপুর    ›       │ bar warn
│ ▌ক্যাশ কম ৳ 300 · শোরুম 2   ›      │ bar bad
│ ▌নতুন স্টাফ অপেক্ষায়        ›      │ bar info
│                                  │
│ দ্রুত কাজ                        │
│  ◯বিক্রি ◯বাকি ◯খরচ ◯স্টক        │  line icons, ivory chips
│  ◯কেনা  ◯রিপোর্ট ◯আইটেম ◯আরও     │
│                                  │
│ সব শাখা (এই সপ্তাহ)               │
│ ▌মিরপুর       ৳ 3.2L   বাকি 40K  │
│ ▌ধানমন্ডি     ৳ 2.8L   বাকি 12K  │
│ ─ মোট         ৳ 6.0L             │
├──────────────────────────────────┤
│ হোম   মেনু   (বিক্রি)   আমি        │
└──────────────────────────────────┘
```
### Drawer
```
┌─────────────────────┐
│ ⌂ ইসলামিয়া মিষ্টি ঘর │
│ [🔍 মেনু খুঁজুন…   ]  │
│ ▾ ড্যাশবোর্ড          │
│    হোম · ব্যতিক্রম ●   │  ● = small dot, count
│ ▸ হিসাব              │
│ ▸ আইটেম              │
│ ▸ কাস্টমার    ●       │
│ ▸ বিক্রি              │
│ ▸ সরবরাহকারী          │
│ ▸ ক্রয়               │
│ ▸ রিপোর্ট             │
│ ▸ সেটিংস 🔒(non-owner)│
│ ───────────────────  │
│ শাখা: মিরপুর ▾        │
│ বাং | Mix | EN        │
│ ● অনলাইন   লগআউট      │
└─────────────────────┘
```
Active row: ink bold + 3px ruby start bar. Search with text shows flat results list (menu hits, then items/customers).

### Report hub
```
← রিপোর্ট                    🔍
[সব] [বিক্রি] [হিসাব] [স্টক] [বাকি] [স্টাফ]   category pills
সংরক্ষিত ভিউ (saved views)
 ▌আমার সাপ্তাহিক বিক্রি · সব শাখা     ›
 ▌বাকি > 30 দিন                          ›
সব রিপোর্ট
  বিক্রি সারাংশ        আজ
  আইটেম-ভিত্তিক বিক্রি
  লাভ-ক্ষতি (মাসিক)
  বাকি বয়স
  ক্যাশ গ্রহণ/ঘাটতি
  খরচ (head অনুযায়ী)
  স্টক চলাচল
  অডিট/পরিবর্তন লগ
  🔒 স্টাফ বেতন (অনুমতি নেই)
[ + কাস্টম রিপোর্ট ]  ← the screen's one primary
```
### Report viewer (+ filter sheet + saved views)
```
← বিক্রি সারাংশ        ⭳ শেয়ার ⋮
আজ সাপ্তাহিক মাসিক বার্ষিক সব | কাস্টম▾
[⎚ ফিল্টার ·3]  [ভিউ: আমার সাপ্তাহিক ▾]  [গ্রুপ: শাখা ▾]
 chips: শাখা: মিরপুর ×  পেমেন্ট: বাকি ×  ক্যাট: মিষ্টি ×
 summary strip: মোট ৳… · সংখ্যা … · গড় …
 table (sticky first col, h-scroll) / group rows expandable
   শাখা     বিক্রি    ছাড়   বাকি
 ▌মিরপুর   3.2L     4K    40K
 ▌ধানমন্ডি  2.8L     1K    12K
 মোট
[ ভিউ সংরক্ষণ ]  [ CSV / PDF ]
```
Filter sheet (bottom sheet, 85% height): sections: তারিখ (presets + from/to), শাখা (multi-check), ক্যাটাগরি/আইটেম (searchable multi), পেমেন্ট (নগদ/মোবাইল/কার্ড/বাকি), ব্যক্তি (কাস্টমার/স্টাফ), পরিমাণ (min-max), অবস্থা (ok/pending/problem as dot-chips), কলাম বাছাই (column picker + drag order), গ্রুপ-বাই, সাজানো. Footer: `রিসেট` (text) + `প্রয়োগ করুন` (primary) + `ভিউ হিসেবে সংরক্ষণ` (text). Saved view = JSON {report, filters, columns, groupBy, sort, period, shared: me|role|all} stored in a table `report_views` (RLS: owner or shared) with localStorage as last-used cache only.

### Product list
```
← আইটেম                [⎚] [+]   (+ is the one primary → better: sticky bottom "নতুন আইটেম")
[🔍 নাম/বারকোড]  chips: সব · কম স্টক · ক্যাট▾ · একক▾
 ▌রসগোল্লা (কেজি)   স্টক 12.5   বিক্রয় 520   ক্রয় 410
  ▌=bar: bad out/low stock, warn near min, none ok
 columns: নাম | স্টক | বিক্রয় | ক্রয়   (margin % shown on tap/expanded)
 row tap -> detail sheet: price history, stock by shop, edit
```
Stock/price columns right-aligned tabular; low stock shows bar + word. Buying price column hidden unless grant (lock "—").

### Product add/edit
```
← নতুন আইটেম
 নাম* · ক্যাটাগরি* · একক* (কেজি/পিস/পাউন্ড) 
 বিক্রয় মূল্য* · ক্রয় মূল্য · শুরুর স্টক
 বারকোড [____] [স্ক্যান 📷]
 ▸ অ্যাডভান্সড অপশন (collapsible, closed by default)
     সাব-ক্যাটাগরি · বিবরণ · অনলাইনে বিক্রি (toggle) · পাইকারি দাম
     কম-স্টক সতর্কতা (min qty) · ভ্যাট % · ওয়ারেন্টি · ডিসকাউন্ট
     ছবি (সর্বোচ্চ ৫, compress client-side to ~800px webp)
 [ সংরক্ষণ ]  sticky primary
```
Existing price/discount limits and `itemreq` approval flow stay: non-owner saves become a change request as today. Fields beyond current `items` schema need migration (open question 1).

### POS
Keep structure (grid, cart bar). Changes: cards lose gradient/cat-tinted background and cornered shape; keep 4px category edge bar (already) with muted category palette; selected state = ink border 2px + qty chip (ruby small), not gold fill. Top: search, category pills (underline style), barcode scan icon. Bottom bar: dark wine stays (it is the brand moment) but total in ivory, the one gold/ruby primary "পেমেন্ট". Sale type, customer, discount in a sheet from the bar. Offline queue = info-dot in header.
```
☰ বিক্রি   [🔍] [▮▮ scan] ● অফলাইন ২
সব মিষ্টি দই কেক  (underline tabs)
┌▌রসগোল্লা ┐┌▌সন্দেশ   ┐
│ ৳520/কেজি ││ ৳640/কেজি │
└──────────┘└──────────┘
─────────────────────────────
 ৩ আইটেম  ৳ 2,140        [ পেমেন্ট ]
```
### Dues (baki)
```
← বাকি          [⎚]
 মোট বাকি ৳1,12,400   ▌৩০+ দিন ৳40,200
 chips: সব · ৭ দিন+ · ৩০ দিন+ · লিমিট পার · শাখা▾ ; sort: বেশি/পুরনো
 ▌রহিম স্টোর    ০১৭…   ৳18,000   ৪৫ দিন   bar bad(>30)
 ▌করিম          ০১৮…   ৳ 2,300   ৮ দিন    bar warn(>7)
   ৳ 500  ০ দিন (no bar)
 row tap -> sheet: ledger, [আদায়] primary, call, reminder
```
Age bands drive bars: 0-7 none, 8-30 warn, 30+ bad; credit-limit exceeded adds chip "লিমিট পার".

## 4. Components and migration (smallest-risk order)

New CSS (append to styles.css as a "v2" block, do not delete old rules until each screen migrates):
`--sig-*` tokens; `.mk`/`.dot`; `.chip` re-skin v2 (`.chip.v2`); `.seg` (segmented), `.ptabs` (period underline tabs); `.fbtn` (filter button with sliders icon + count); `.fchips` (applied-filter chips); `.sheet.tall`; `.row` (list row with mk); `.stat` (value+label); `.lockcard`; `.drawer`, `.scrim`; `.bnav`; `.qgrid` (quick actions); `.acc` (collapsible section, native `<details>` styled, zero JS); `.colhead` sticky table head; `.skel`.

New JS (small modules, loaded after app.js, registered through existing `window.BOS_APP`/`BOS_PAGES`/`H`):
1. `nav.js`: drawer + bottom nav + menu registry `MENU=[{group,id,route,icon,label,need:(ctx)=>bool}]` built from existing AREAS/BOS_PAGES. Hooked inside `shell()` via one flag so old pages still render.
2. `filters.js`: generic `openFilterSheet(schema, state, onApply)`, `applyFilters(rows, state)`, chips renderer, saved views (supabase table `report_views` + local cache), period helper (`today/week/month/year/all/custom`). Pure functions, unit-testable.
3. `reports.js`: report hub + viewer driven by a report definition array `{id,title,group,needs,fetch(filters),columns,groupBy,totals}`; reuse queries already in biz.js/dash.js/dues.js (do not rewrite). Export CSV (extends existing `download()`), print/PDF via window.print stylesheet.
4. Refactor `viewItems`/`drawItems` to use filter sheet + columns; `itemSheet` gets `<details>` Advance Options.
5. `dues.js` list adopt `.row.mk` + filter chips.
6. POS card restyle (CSS only first).

Migration steps (each shippable alone, nothing breaks):
1. Tokens + `.mk/.dot/.chip` additions only. No visual change. (CSS)
2. Demote fills: `.tabs button.on`, `.tile.t-*`, `.badge` -> neutral + edge bar via a `data-ui="calm"` attribute on `<body>`; toggled by a owner setting `ui_calm` (default on for owner after check, off switch). Instant rollback by removing attribute.
3. Header slim-down: language bar moves to drawer footer, behind same `H.lang` so logic unchanged.
4. Drawer + bottom nav (additive; hash routes untouched; every page still reachable from home grid).
5. Home v2 (attention strip from existing exception/release/emergency queries; period tabs reuse dash.js ranges).
6. Filter sheet in Items, Dues, Logs (replace `i_q` + category chips; keep `S.itemQ`/`S.itemCat` as state).
7. Report hub/viewer + saved views (needs table migration `report_views`).
8. Add Product advance options (needs `items` columns or `items.extra jsonb`; see Q1).
9. POS card restyle, dark-mode check, remove dead CSS.
Per step: manual check at 360px, dark mode, bn/mix/en, owner/staff/pending roles; keep i18n keys in i18n.js (add new `T` keys for every label, never hard-code).

## 5. Accessibility and low-end phone performance
- Tap target >= 48px (44 minimum); 8px gaps; drawer/sheets focus-trap, `role=dialog aria-modal`, Esc/back closes, return focus. Hardware Back must close drawer/sheet before navigating (push hash state).
- Colour never only signal (word/icon accompany bars); bars 3:1, text 4.5:1 both themes; check amber on ivory (use #b7791f only for bar, text uses darker #7a4b00 as today).
- Text 17px base, user zoom allowed (no `maximum-scale`), Bangla line-height >= 1.6, conjuncts not clipped in chips (min-height not fixed height).
- `aria-current` on nav, `aria-expanded` on groups, labels on icon-only buttons, tabs `role=tablist`.
- Perf: no gradients/blur/large shadows on lists; avoid `backdrop-filter`; CSS-only drawer (transform/opacity only); virtualise or paginate lists > 100 rows (50 per page + "আরও"); debounce search 200ms; filters run client-side on cached rows, server query only on period/shop change; images lazy + compressed; font subsets already local? (check `vendor/`) keep 2 families, `font-display: swap`; saved views and menu collapse state in localStorage with try/catch; SVG sprite icons (one file) not icon font; keep bundle split per page (already) and avoid new libraries. Test on a throttled 4x CPU Chrome profile.
- Offline: filters/search and viewing cached reports must work offline; show "অফলাইন, পুরনো তথ্য" info bar (info colour).

## 6. Open questions for the owner
1. Add Product: which extra fields need real storage now (sub-category, online-sell, wholesale price, VAT, warranty, 5 images, barcode)? VAT/Mushak is still unconfirmed (MODULE_MAP). Images need Supabase storage bucket + size cap.
2. Business vs Accounting toggle: what exactly differs (Business = sales/stock/dues; Accounting = cash, expenses, P&L, ledgers)? Confirm.
3. Locked modules: hide completely, or show "অনুমতি নেই" lock cards? (Lock cards leak existence but teach staff to request access.)
4. Multi-shop: combined report visible to owner only, or also area managers? Currency format: lakh grouping (1,12,400) or million?
5. Bottom nav: is basket = POS correct for all roles, and should "Reports" replace "Profile" for the owner?
6. Dark mode: keep automatic (phone setting) or add manual toggle? (Current is automatic only.)
7. Saved views: private per user, or owner can publish to roles?
8. Barcode scanning: camera in browser (BarcodeDetector, not on all low-end phones) or hardware scanner/typed? Is a vendor library OK?
9. Age thresholds for dues colours (8 / 30 days) and low-stock rule: owner-editable Rule/Limit per MODULE_MAP convention? (recommended: yes, as Limits, never fixed in code)
10. Keep the gold diamond header ornament and gold category palette on POS, or go fully neutral? (Plan: drop ornament, keep a single gold hairline and 4px category bars.)
