# Controls audit: where options were shown OPEN (and what the kit does about it)

Scope: web/*.js (static grep + a Playwright probe over the stub data). "Open" = every choice visible in the field itself.
Kit: `web/controls.js` + `web/controls.css`, API `BOS.ctl.{select,multi,tick,menu,seg,enhance,on,setMode}`. Switch: rule `ui_collapsed_controls` (absent = ON, `supabase/phase30_controls.sql` seeds it ON) or per phone `localStorage.bos_ctl_collapsed='off'`.

## 1. Static counts (source occurrences, not runtime rows)
| File | `<select` | `class="tog` (chips/toggles) | checkbox | Notes |
|---|---|---|---|---|
| entry.js (+forms*.js, 41 forms) | 6 | 1 (the CH builder, `data-act=pick`) | 2 | 97 `CH(` definitions: 15 render >3 options (now dropdown), the rest are 2-3 option choices (kept as compact seg) |
| settings2.js | 14 | 3 | 0 | unit/week-start/fiscal pickers; `s2_wk` week-start chips (7 options) |
| itemmaster.js | 13 | 6 | 0 | item type/unit/category selects |
| purchase.js | 9 | 1 | 0 | supplier/payment selects |
| stock2.js | 8 | 2 | 0 | filters sheet (selects + 2 on/off toggles) |
| invoice.js / recipes.js | 6 / 6 | 2 / 4 | 1 / 0 | label picker checkboxes, recipe filter chips (3) |
| items2.js | 5 | 6 | 0 | p2 seg groups, sell-unit chips `data-su` (multi) |
| reports.js | 4 | 4 | 0 | filter sheet (filters.js) |
| filters.js | 0 | 2 builder fns | 0 | `.fl-chipset`: locations/brands/modes/categories (multi, `fl_t`), sale type/status (single, `fl_one`), date presets |
| lists.js / listctl.js | 1 / 3 | 7 / 0 | 0 | list chooser chips (`ls2_pick`, one per list = 10+), status badges |
| daybook, biz, locations, rollout | 1/1/2/2 | 3/1/2/4 | 0/0/0/2 | mode / period / status filter chips |
| pos.js / pay.js | 1 / 1 | 8 / 2 | 0 | category chips, tabs, retail/wholesale, discount type, "+ cash/bkash/card" add-payment buttons: intentionally one-tap |
| bulkitems.js | 3 | 2 | 4 | row selection checkboxes (not a choice list) |
| others (app, dues, salary, salereturn, nav, pinsign...) | ~12 | ~5 | 0 | |
Total approx: 105 `<select`, 90 `tog` builders, 9 checkboxes, 0 radios, 0 `.chips` classes. No three-dot row menu needed to be invented: lists already use `⋮` (`mini` buttons); no row with 3+ inline secondary buttons was found on probed screens (enhancer kept for future rows, unit-tested on a fixture).

## 2. Runtime conversion (initial render, 360px, stub data)
| Area | Converted |
|---|---|
| 41 forms (shared builders) | 318 native selects (many are repeated table-row selects) -> sheet dropdowns; 15 CH groups (>3 options) -> dropdown; every ≤3-option CH -> compact seg; read-only entries show plain values |
| Items list / filter sheet (`p2_fb`) | 5 selects in the filter sheet; sell-unit chips (`data-su`) -> multi |
| Stock levels + filter sheet | 3 + 2 selects |
| Purchase list / sheets | 2+ selects |
| Reports filter sheet (filters.js) | 1 single chip group (presets) + 3 multi groups (locations/brands/modes...) -> dropdown/multi; sale-type & status (2 options) stay seg |
| Lists admin | list chooser chips (ls2_pick) -> dropdown |
| Daybook / Biz / Locations / Invoice | mode / period / status chip rows -> dropdown |
| POS | selects -> dropdown; payment add buttons, retail/wholesale, discount-type, tabs and category chips stay one-tap on purpose |
| Header | nav drawer selects (location, theme) are collapsed too |

## 3. Left open, and why
- On/off `.tog` switches (rules hub ~129 rows, `im_tg`, `p2_tg`, `ro_sw`...): a single boolean already collapsed to one button, not an option list.
- POS: `pos_cat` category chips (speed), `pay_add` mode buttons, retail/wholesale, discount type: the 2-3 most used one-tap choices.
- Tabs (`*_tab`, `pos_tab`): navigation, not a field.
- Groups with 2-3 mutually exclusive options: compact seg (spec).
- Date presets inside the filter sheet when ≤3 options.
- `bulkitems` checkboxes: per-row selection, not an option list.
- Native date/time/number inputs.

## 4. Limits
- Enhancer is heuristic: single-choice groups are recognised as ≥4 `button.tog[data-act][data-v]` with ≤1 `.on` in the same parent and an act not matching tabs/pos/pay/add/preset/lang. A screen that wants exemption sets `data-ctl="off"`.
- Hidden originals are 2px, opacity 0, spread so each stays clickable by code and tests.
- Multi Apply clicks only changed originals, 40ms apart (some engines redraw per click).
- Not verified on a real phone / TalkBack; only headless Chromium at 360px.
