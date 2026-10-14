# Step Rec - fix/phase-Rec: the setup advisor covers every rule / switch of phases 82..98

Branch fix/phase-Rec (from integration/p72-p79 = phases 72-98 + web). New files only: `supabase/phase101.sql`, `supabase/phase101_test.sql`, `tests/sql/rec_keys.py`, `tests/sql/phase101_run.sh`, this report. No old file, no web file, no function was touched. Nothing ran against a live database.

## What was built
* `phase101.sql`: guard (markers of phases 72..97, phase98 via the `bos98` tag in `_acct_docs`, and the advisor itself; a missing phase raises and inserts nothing), then ONE `INSERT ... SELECT ... ON CONFLICT (code) DO NOTHING` into `setup_rec_defs81` (columns code, rule_key, phase, module, rec_value jsonb, ready_checks text[], reason_bn, reason_mix, reason_en, sort). 43 new rows, code = rule key, sort 300+. Paste twice = no change; an edited row is not overwritten; a deleted row comes back. The 38 older rows (phase81 / phase94) are byte-identical (md5 checked on a build without phase101).
* Rules of phases 82..97 = 48 keys (extracted from `insert into public.rules` of the phase files by `tests/sql/rec_keys.py`; phases 84, 89, 91, 93, 98 add no rule). 6 of them (scan_ai_max_per_job, scan_ai_max_per_user_day, offline_sale_max_age, inbox_rate_max_per_min, intake_reject_max_per_min, invoice_own_sales_only) already had a phase94 row, so 42 new + `stock_negative_mode` (older rule that the phase82 `guard_recommendations()` also advises on) = 43.
* No function is created or re-created. `setup_recommendations()` already reads jsonb `rec_value` of any kind, and `setup_recommend_apply()` already writes through `set_rule` (validated by kind: switch boolean, choice in `rules.choices`, number inside min..max, text string; a bad value is skipped `rejected`, the trail and audit_log are written). This was proved (T9), not assumed, so nothing needed re-creating. `web/setupadvisor.js` already shows choice / text / info rows (info rows of kind number show default and range; other info rows link to the switchboard): no web change.
* Where a value is recommended the row says why (bn / mix / en). English reasons contain no Bangla letter (tested); Bangla reasons keep common words English. Existing texts were reused where they existed (guard_recommendations, form_guard_recommendations, production_recommendations, the Dscr screen warnings).

## Table: rule -> recommended -> reason (apply-ready = one tap works on a clean system; "info" = no value recommended, the owner decides)
| rule | phase | recommended | apply-ready | reason (English, first sentence) |
|---|---|---|---|---|
| purchase_grn_guard | 82 | info (none) | - | When GRN is the source of goods and the purchase bill also adds stock, the same goods are counted twice |
| purchase_void_guard | 82 | refuse | yes | Voiding a bill whose goods were already returned, used or received by a GRN batch makes stock negative and the books wrong |
| purchase_void_payments | 82 | keep | yes | The money really left |
| unit_conv_required | 82 | refuse | only if stk_conv clean | Selling a tracked item that has no unit conversion does not reduce its stock |
| neg_grant_log | 82 | true | yes | When someone with the permission sells below zero, who, which item and how much is written as a yellow warning so the owner knows |
| production_negative_reason | 82 | required | yes | Producing without enough ingredient stock gives wrong costs |
| stock_negative_mode | 82 | info (none) | - | Choose block after the first stock count or opening stock is entered: then a sale above stock is stopped |
| form_051_mode | 83 | info (none) | - | If the 05-1 sheet is the real production record (not the recipe production screen), choose post: when the sheet posts to stock the ingredients also... |
| transit_short_mode | 83 | loss | yes | Goods that arrive short are in no book today, only on a list |
| transit_open_hours | 83 | info (none) | - | No number is built in |
| offline_soft_stock | 83 | true | yes | An offline sale has already handed the goods over; if a short stock refuses it, the sale is lost |
| acct_count_adjust | 85 | true | only if acc_start,acc_coa,acc_map clean | Without it the stock value and the books drift apart; when on, every count adjustment becomes one entry |
| acct_stock_opening | 85 | false | yes | Keep this OFF |
| acct_issue_out | 85 | true | only if acc_start,acc_coa,acc_map clean | Otherwise an own-use issue lowers stock but never shows as an expense |
| acct_transfer_mode | 85 | info (none) | - | With more than one place (showroom or store) location_tagged is the usual choice: a send entry and a receive entry through the inter-location clear... |
| acct_transit_loss | 85 | info (none) | - | Best on when transfer accounting (acct_transfer_mode) is on: the missing cost goes to the transit loss account |
| acct_transit_loss_at | 85 | receiver | yes | The usual choice: receiver |
| acct_purchase_variance | 85 | true | only if acc_start,acc_coa,acc_map clean | A return takes stock out at average cost but the supplier credit is at the bill price; without this, stock value and books differ after a return |
| acct_stock_moves_from | 85 | info (none) | - | If you turn the switches on late, type a date (YYYY-MM-DD) to avoid a big backlog; older stock movements are left out |
| manual_journal_guard | 85 | on | yes | When on, a manual journal on an inventory, COGS, sales, payable, receivable or stock-adjust account needs a reason code, and payable or receivable ... |
| acct_scheduler_on | 85 | info (none) | - | This does not work by the switch alone: a scheduler must be started on the server with pg_cron, which cannot be done from a phone |
| acct_pending_alert_days | 85 | info (none) | - | How many days old a document may be before it counts as waiting too long to reach the books |
| telegram_intake_on | 86 | info (none) | - | Nothing arrives when this is on until the outside setup (the Edge function and the bot) is done, which cannot be done from a phone |
| expiry_sale_guard | 87 | warn | yes | When expired stock is sold, warn lets the sale go through but the red warning names the batch and its expiry date |
| purchase_backdate_flag | 87 | warn | yes | When a purchase bill is posted with a date other than today, a yellow warning is kept (the stock is stamped now and the journal uses the bill date) |
| production_double_issue_guard | 87 | warn | yes | If the same goods are deducted by a recipe production run and by a stock issue or form on the same day, they may be deducted twice; warn flags it a... |
| report_cost_source | 88 | ledger_then_item_costs | yes | Every report takes the product cost from the cost the journal uses (the stock ledger), and the typed item cost only where the ledger has none (mark... |
| scan_enabled | 90 | true | yes | With scanning on, a photo of a bill or list becomes a DRAFT; nothing is entered until a person reviews and confirms it |
| scan_engine | 90 | manual | yes | Manual means you type the lines beside the photo (always works, no cost) |
| scan_min_confidence | 90 | info (none) | - | A field the reader was unsure about is shown yellow (a warning only; it never blocks Confirm) |
| pos_show_invoice_after_sale | 92 | always | yes | With always, the invoice opens on screen right after every sale, with Print, Email, SMS and WhatsApp buttons, so the customer can see and receive t... |
| cash_drawer_mode | 95 | info (none) | - | Once a cash drawer is fitted, on_cash_sale is the usual choice (the drawer is asked to open when cash is taken) |
| cash_drawer_method | 95 | info (none) | - | The connection type depends on your device and printer (browser_print_pulse, web_serial, web_usb, bluetooth) |
| cash_drawer_when | 95 | after_payment | yes | After_payment opens the drawer only once the sale is saved (recommended) |
| cash_drawer_no_sale_requires_reason | 95 | true | yes | A No sale open cannot be logged without a reason |
| acct_cost_wait_alert_days | 96 | info (none) | - | After how many days a document waiting for its cost raises an alert - the owner types the number; there is no built-in value |
| landed_cost_mode | 97 | info (none) | - | To add freight, duty and similar charges to item cost, per_shipment is the usual choice for imports and manual for a local delivery charge |
| landed_alloc_default | 97 | value | yes | Value means costly goods take a bigger share |
| landed_late_mode | 97 | split_remaining_and_cogs | yes | When a charge arrives after part of the lot was sold or used, split puts the part still on the shelf into stock cost and the part already sold into... |
| landed_cost_requires_approval | 97 | info (none) | - | With required, a landed cost cannot be posted until approved and the person who made it cannot approve it (the owner can) |
| landed_reminder_on | 97 | info (none) | - | When on, bills of imported or flagged suppliers that have no landed cost are listed |
| landed_reminder_days | 97 | info (none) | - | How many days back the reminder list looks |
| landed_base_currency | 97 | info (none) | - | The base currency code of landed costs (the currency of your books) |
Six rules of phase94 keep their existing rows (4 numbers = info, invoice_own_sales_only = true).

## Why some rows are NOT recommended (info)
Numbers (transit_open_hours, acct_pending_alert_days, acct_cost_wait_alert_days, scan_min_confidence, landed_reminder_days) and text (acct_stock_moves_from date, landed_base_currency): owner-typed, never recommended; the screen shows the shipped default and the range. Rules that depend on the shop or an outside setup: purchase_grn_guard (skip only when GRN is the goods source), form_051_mode (post only if the 05-1 sheet is the production record), acct_transfer_mode / acct_transit_loss (depend on the number of places), acct_scheduler_on (needs pg_cron on the server), telegram_intake_on (needs the Edge function and bot), cash_drawer_mode / cash_drawer_method (hardware), landed_cost_mode / landed_cost_requires_approval / landed_reminder_on (imports, what "big" means), stock_negative_mode (block only after the first count). I did not invent a value for any of these.

## Decisions the owner should know
* The three backlog accounting switches (acct_count_adjust, acct_issue_out, acct_purchase_variance) are recommended ON as the Dscr screen says, with the Dscr warnings in the reason (backlog posts at original dates, closed periods held, set acct_stock_moves_from first if unwanted). They are apply-ready only when acc_start, acc_coa, acc_map are clean; "Apply all" would turn them on once those are clean, without the Dscr confirmation sheet. acct_stock_opening is recommended OFF (double count with acct_opening; use the Opening stock screen of phase96).
* unit_conv_required refuse is apply-ready only while no tracked item has a sell unit without conversion (check stk_conv); the phase82 text said the same.
* expiry_sale_guard: warn (never stops a sale; refuse would also stop a genuine sale if an expiry date was typed wrong; the older block_expired_sale is not weakened). scan_enabled true and scan_engine manual (draft only, no cost).
* phase81 keeps production_requires_recipe as an info row while `production_recommendations()` (phase87) says ON; left as is (rows not touched).
* Not in the order file: `tests/sql/final_build.sh` and docs/PASTE_ORDER.md were not edited (another phase may also edit them); the lead should add `phase101` after `phase98`. `phase101_run.sh` appends it itself.

# যাচাই হয়েছে
Fresh scratch Postgres 16 (socket /tmp port 5544), build = final_build.sh canonical order + phase101.
* `supabase/phase101_test.sql`: **57 pass / 0 fail** (run from the repo root; `bash tests/sql/phase101_run.sh <db>`). On a build WITHOUT phase101 it gives 31 pass / 26 fail (the coverage, row, language and apply blocks fail).
  * T0 coverage: keys read from phase82..97.sql by `rec_keys.py` (48 keys, 12 phases) all exist in `rules` and all have an active row (code = key, right phase tag); 43 new rows; no key has two rows; the 38 older rows unchanged (md5); no phase99/100 row; no function body carries bos101.
  * T1 values: every recommended value is valid for its rule kind (switch boolean, choice in rules.choices, number in range, text string); all 12 number / text rules among the 48 keys have NO recommendation; no JSON null; safety rules never recommend off/allow/void; the owner example pos_show_invoice_after_sale default never -> recommended always.
  * T2 language: English reasons contain no Bangla letter, Bangla/mixed reasons are Bangla text, none empty.
  * T3 `setup_recommendations()` as owner returns all 43 (none not_installed); pos_show_invoice_after_sale = recommended / ready / one tap; defaults already right = ok; numbers = info with default and min/max; shop-dependent rows = info; backlog switches recommended but not ready on a fresh DB with the failing check named; reading changes nothing (no rule value, no audit row).
  * T4 unit_conv_required becomes not ready while a tracked item has an unconverted sell unit and apply skips it `not_ready`.
  * T5 non-owner cannot apply/read (salesperson not allowed; view-cost person reads, cannot apply).
  * T6 apply writes through set_rule: strings stay strings, trail lines, `setup_apply` audit row and `rules` audit rows exist, rows show ok afterwards, same client id = dup.
  * T7 an owner-chosen value is skipped unless overwrite AND the code is named. T8 apply-all writes nothing to a number/text rule, every applied line equals the row's recommended value, backlog switches skipped not_ready, info rows skipped no_recommendation. T9 (test rows, removed again) text value applied; bad choice / wrong type / number out of range rejected, rule unchanged; missing rule not_installed.
  * T10 paste twice: same rows, same function bodies, no rule value touched; edited row kept, deleted row restored. T11 the guard refuses (and inserts nothing) when the phase98 marker is missing.
* Older SQL suites: all 73 `supabase/*_test.sql` files (each on its own clone) on the build WITH phase101 and on the build WITHOUT it: **identical result lines for all 73**. The relevant ones: phase81 64/0, phase94 80/0, phase96 123/0, phase97 155/0, phase98 27/0, phase89 63/1 (the known P2, use phase89c). The other known baseline fails of step INT3 (phase8, 10, 15, 19, 21, 21b, 22 [22b 82/0], 23, 47, 72 [72b], 73 [73b], 76 [76b]) are unchanged. phase96 prints 123 here and on the build without phase101 (INT3 wrote 124); not caused by this step.
* `node tests/web/setupadvisor_test.js`: 22 pass / 0 fail. `node tests/web/lang_en_test.js`: 87 English strings, 0 Bangla.

# পড়ে বোঝা
* The recommended values come from the step reports and the existing recommendation functions / the Dscr screen (judgement of earlier steps, not confirmed by the owner or an accountant): e.g. transit_short_mode loss, purchase_void_payments keep, manual_journal_guard on, landed_late_mode split.
* "Apply all" in the web screen was not exercised in a browser; only the SQL it calls.
* Whether the backlog switches' warning in the reason text is enough without the Dscr confirmation sheet: the row shows the reason above the button, but an owner who taps "Apply all recommended" skips the sheet.
* ready_checks only use checks that already exist in phase81; there is no check for "GRN is the source", "more than one place", etc., so those stay info.

# যাচাই হয়নি
* Nothing ran against the live database, a real phone or a browser; the new rows were not looked at on screen.
* The Opt (phase99) and Cat (phase100) rows are not here; paste order with them (phase101 relative to 99/100) is untested: phase101 only needs 72..98 and the advisor.
* The text-apply path was proved only with a test row (a currency code) on landed_base_currency; the real rule is not recommended.
