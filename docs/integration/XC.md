# XC: daily value package (owner summary, production suggestion, price alerts, unsold stock, staff board, sync trust)

Built on `claude/supabase-readonly-audit-xo3qkp` (6bf2f6f) in branch `xc-ops`. Local throwaway Postgres only. Nothing pushed, nothing pasted into the live project.

## 1. What is built (and what is not)

| Item (brief) | Built | Phase / file |
|---|---|---|
| 1. Owner daily summary (composer, recipients, scopes, quiet day, send log, e-mail + Telegram) | Yes, backend + script + workflow | `phase494.sql`, `tools/owner_summary.py`, `.github/workflows/owner_summary.yml` |
| 2. Daily production suggestion, accuracy | Yes, backend (no screen) | `phase495.sql` |
| 3. Unsold and markdown (outcomes, wastage share) | Yes, backend (no screen; no coupon table: the till's discount rules are used) | `phase497.sql` |
| 4. Supplier price intelligence and alerts, recipe-cost preview | Yes, backend (no screen; links to the existing `p2_rate_trend`) | `phase496.sql` |
| 5. Staff coaching board (owner only) | Yes, backend (no screen; shift and role awareness NOT built) | `phase498.sql` |
| 6. Offline and sync trust | Partly: server sync report and "every shop synced?" alert; service-worker bump script and checklist. NOT built: the "N unsynced" badge, outbox viewer, conflict screen, device receipt check (they are client screens) | `phase494.sql`, `tools/bump_sw.py` |
| 7. Low-stock draft purchase orders, cash-count reminder, shop checklist with photos, temperature reminders | NOT built | - |
| SMS / WhatsApp summary | NOT built (needs consent and an approved template through `notify_outbox`) | - |
| Screens (every new screen through `web/ia.js`) | NOT built. No web file was changed. 360px and headless web tests: NOT run | - |

## 2. Settings (all OFF or blank; each has an info entry in `web/data/info.json`, from `docs/integration/XC_info.json`)

| Key | Default | Phase | Purpose |
|---|---|---|---|
| `xc_summary_on` | off | 494 | owner summary on |
| `xc_summary_email_on` | off | 494 | e-mail channel |
| `xc_summary_telegram_on` | off | 494 | Telegram channel |
| `xc_summary_times` | 21 | 494 | hours (Dhaka) |
| `xc_sync_alert_on` | off | 494 | "every shop synced?" warning |
| `xc_sync_stale_hours` | blank | 494 | hours before the warning (blank = not set, nothing flagged) |
| `xc_prod_suggest_on` | off | 495 | production suggestion |
| `xc_prod_weeks` | blank | 495 | weeks of same-weekday history (blank = data needed) |
| `xc_price_alert_on` | off | 496 | rise alert |
| `xc_price_rise_pct` | blank | 496 | rise threshold (blank = not set) |
| `xc_unsold_on` | off | 497 | end-of-day list and outcomes |
| `xc_markdown_pct` | blank | 497 | markdown % (blank = no suggestion, markdown sale refused) |
| `xc_coaching_on` | off | 498 | owner-only staff board |

Recipients (`xc_summary_recipients`, owner-entered, retired not deleted) carry the e-mail address or the Telegram chat number. Secrets (Gmail app password, Telegram bot token, bot login) stay in GitHub secrets only.

## 3. Hooks into existing code

* **No existing function, view or phase file was edited.** Every new object is a new function or table with an `xc_` prefix (or `_xc_` helper).
* Reused, read only: `daily_digest`, `_day_sales`, `_p26_rates`, `recipe_cost`, `_recipe_need`, `_rb4_prod_view`, `_rb4_prod_entry`, `_notif_add`, `rule_on`, `rule_num`, `rpt_cost_ok`.
* Sync with the existing script path: `tools/owner_summary.py` imports `notify_digest` (render, Gmail SMTP) and `ops_common` (login, redaction). `notify_digest.py` and `notify.yml` are NOT changed.
* `tests/sql/ORDER.txt`: `phase494` ... `phase498` appended after `phase478`. `docs/PASTE_ORDER.md`: rows 29 to 33.
* `web/data/info.json`: 13 entries merged with `tools/check_info_coverage.py --merge docs/integration/XC_info.json` (0 replaced). `check_info_coverage.py` exits 0.

## 4. Permissions

* Owner summary, targets, history, compose: owner, or the ops bot (purpose `notify`). Recipient addresses: owner and ops bot only (RLS).
* Production suggestion and confirmation: the production read/entry rule (owner, or the stock_production grant at that place). Accuracy: owner or the place's production reader.
* Price board and recipe preview: owner, cost right (`rpt_cost_ok`) or recipe-cost right.
* Unsold list and record: place's production reader and entry; void: owner, or the person who wrote the line within one hour.
* Staff board: owner only, and the switch.
* Every new table: RLS on, direct writes revoked, no hard delete, audit trigger.

## 5. Tests

| Suite | Checks | Result |
|---|---|---|
| `supabase/phase494_test.sql` (+ `tests/sql/xc_head.sql`) | 38 | 38 pass |
| `supabase/phase495_test.sql` | 28 | 28 pass |
| `supabase/phase496_test.sql` | 23 | 23 pass |
| `supabase/phase497_test.sql` | 27 | 27 pass |
| `supabase/phase498_test.sql` | 10 | 10 pass |
| `tests/py/test_xc_owner_summary.py` (mocks only) | 26 | all pass |
| `tests/py/test_xc_bump_sw.py` | 8 | all pass |
| `tools/check_info_coverage.py` | - | exit 0 |
| `tools/check_no_demo_leak.py` | - | run before the commit |

Paste-twice: each phase was pasted a second time on a copy of its own database with no error. Test data uses `test_*` names only; no real staff, customers or places were written (the seed places in the schema are used by id only).

Not run: the full 1 to 478 chain in `tests/sql/run_all_sql.sh` (old suites) and the web suite (`tests/web/run_all.py`). The base was checked, not the whole old suite.

## 6. Service-worker version bump (checklist)

Every deploy that changes a file under `web/` must change the cache version, or phones can keep old screens.

1. `python3 tools/bump_sw.py` (dry run: shows `bos-sw-vN -> bos-sw-vN+1`).
2. `python3 tools/bump_sw.py --write` (changes `web/sw.js` only).
3. `python3 tests/py/test_xc_bump_sw.py`.
4. Commit `web/sw.js` in the same commit as the web change.

## 7. Known limits (say these to the owner)

* The summary's sales figures are the server's own totals for the day (the same definition as the e-mail digest). Nothing is estimated.
* The production suggestion is arithmetic on past same-weekday sales. It is not a forecast; the range is the lowest and highest past day, not a confidence interval. Carry-over is the stock on hand now.
* The sync alert uses the time of the last recorded sale: the server does not store a per-device sync time in this build, so a quiet shop is not a broken one. Hours must be typed by the owner.
* Receipt gaps are flags to look at (offline outbox, voided bills), never corrections.
* Waste value in the report uses the current average cost, not the cost at the time of waste.
* The staff board ignores shifts and roles in this version.
* Markdown outcome lines never move stock; the waste is booked on the wastage screen. The discount sale is taken at the till.
