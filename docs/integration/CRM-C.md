# Integration note CRM-C: customer lists (segments), customer scores (RFM), customer value

Package C of the CRM design (`CRM_AUDIT_AND_DESIGN.md`, section 4.1). Labels 106 to 108, repo files **phase306, phase307, phase308** (label + 200, because phases 100 to 239 belong to the Unified Build Plan).
Nothing existing was edited. Every new function starts `crmc_` / `_crmc_`, every new table `crm_` / `crmc_`. Owner rules kept: every policy is a setting with a safe default, nothing starts by itself, accounting figures never change, English labels only, short screens at 360 px.

## 1. Files

| File | What |
|---|---|
| `supabase/phase306.sql` (+ `_test`, 79 checks) | 11 settings, 4 rights, `crm_metrics` (the score cache), labels with the owner's own cut-offs, refresh (on demand, capped, optional schedule), status, `crmc_me()`, the patch helper `_crmc_patch` |
| `supabase/phase307.sql` (+ `_test`, 146 checks) | `crm_segments`, `crm_segment_members`, the safe rule builder (catalog of 24 fields), preview, member pages, save / retire / freeze, item search, `_crmc_audience` |
| `supabase/phase308.sql` (+ `_test`, 85 checks) | overview (repeat-purchase rate, lifetime value, lapsed, at risk), label summary and lists, top customers, lapsed list, customer value card, customer profit view, export with log |
| `web/crm_segments.js` | screen `#/crmlists` "Customer lists" |
| `web/crm_rfm.js` | screen `#/crmvalue` "Customer value" |
| `tests/web/crm_segments_test.js` (65), `tests/web/crmc_hooks.js`, `tests/web/crmc_hooks_run.js` | web test, the exact hook text as code, the hook proof on a scratch copy |
| `tests/sql/crmc_fixture.sql`, `crmc_before_after.sh`, `crmc_hook.sh`, `crmc_perf.sql`, `run_crmc.sh` | fixture, snapshot proof, `notify_scan` hook proof, performance run, one runner for all of it |
| `docs/integration/CRM-C_info.json` | plain-English entries for the (i) info sheet |

## 2. Paste order and `ORDER`

Paste **phase306, then phase307, then phase308**, after phase98 (they also work after phase99; no CRM-C file needs phase99). Each file stops with a clear message if its predecessor is missing. Paste twice is safe (tested: no error, no change).
`tests/sql/ORDER.txt` (integrator-owned): add `phase306 phase307 phase308` after `phase99`.

## 3. Hooks in shared files (exact text, proved on a scratch copy)

`node tests/web/crmc_hooks_run.js $(pwd)/tests/web` copies `web/` and `tests/web/` to a temp folder, applies the text below, and runs ia, nav, nav2, control, favsync, settings2 and the CRM-C web test there: all pass.

**`web/ia.js`** (integrator): insert these two records right after the `rec('tiers', 'cust', ...)` line (group `cust`, no Home tile, no bottom-bar slot, English labels):

```js
  rec('crmlists', 'cust', ['Customer lists', 'Customer lists', 'Customer lists'], { icon: 'users', ok: (c) => c.own || c.GF.crm_view === true || c.GF.crm_settings_edit === true || c.GF.customer_manage === true, kw: ['customer list', 'segment', 'saved list', 'not seen', 'lapsed', 'birthday', 'high spender', 'by outlet', 'by tier', 'bought item', 'audience'], verbs: ['make a customer list', 'count customers'] }),
  rec('crmvalue', 'cust', ['Customer value', 'Customer value', 'Customer value'], { icon: 'users', ok: (c) => c.own || c.GF.crm_view === true || c.GF.crm_settings_edit === true || c.GF.customer_manage === true, kw: ['rfm', 'lifetime value', 'repeat rate', 'repeat customers', 'champion', 'at risk', 'lapsed customers', 'best customers', 'customer profit', 'churn'], verbs: ['see best customers', 'see lapsed customers'] }),
```

**`web/index.html`**: after `<script src="customers.js"></script>` add `<script src="crm_segments.js"></script><script src="crm_rfm.js"></script>`.

**`web/nav.js`** (the list of grant codes read for the menu; without this a person who holds only `crm_view` does not see the menu entry, the server still allows the screen): two edits, each site is unique.
1. `'list_manage', 'rollout_manage', 'change_approve'] : [`  becomes  `'list_manage', 'rollout_manage', 'change_approve', 'crm_view', 'crm_settings_edit'] : [`
2. `'customer_manage', 'assistant_use'];`  becomes  `'customer_manage', 'assistant_use', 'crm_view', 'crm_settings_edit'];`

**SQL `notify_scan`** (optional; without it the owner presses "Refresh scores", nothing else is lost). One guarded line, wrapped so a CRM-C error can never stop the existing scan. Marker `bosCRMC`, helper `_crmc_patch` (same contract as the earlier packages: unique site, nothing half done, second call patches nothing):

```sql
select public._crmc_patch('public.notify_scan()'::regprocedure, array[
  E'  select coalesce(sum(v::int), 0) into cnt from jsonb_each_text(made) e(k, v);',
  E'  if to_regprocedure(''public.crmc_scheduled_run()'') is not null then begin perform public.crmc_scheduled_run(); exception when others then null; end; end if; /* bosCRMC */\n  select coalesce(sum(v::int), 0) into cnt from jsonb_each_text(made) e(k, v);'
], 'bosCRMC');
```

`bash tests/sql/crmc_hook.sh` proves it on two copies of a database through phase 99 (one patched, one not): the patch applies once (t) and a second time patches nothing (f); the 37 hooks of phase 99 are all still there; with the schedule OFF (default) `notify_scan` gives the **same answer** with and without the hook and writes no score run; with the schedule ON and the hours set it refreshes once, a second scan inside the hours writes nothing, and a CRM-C function that raises an error does not stop the scan.
If package E later installs its single `bosCRM` line calling `crm_scan()`, that function may call `crmc_scheduled_run()` instead; do not install both (harmless but pointless).

**Re-paste hazard.** `notify_scan` is created only by phase46. Re-pasting phase46 removes every hook in it (bos90 and bosCRMC): run `select public._i1_apply_hooks();` and the `_crmc_patch` call above again. Phases 306 to 308 themselves patch nothing shared and can be re-pasted at any time.

Not done on purpose: no change to `customers.js` (the optional "Saved list" filter chip of the design) and no change to `pos.js`; both are integrator work after W3-I and are not needed for anything here. The customer value card for the Customer 360 screen is the server function `crmc_customer_value(customer_id)`; package A's screen can call it (visible to everyone who may open the customer profile).

## 4. Settings (module crm; every default keeps today's behaviour)

| Key | Kind | Default | What it does |
|---|---|---|---|
| `crm_segments_on` | switch | OFF | OFF: lists can be built, counted and viewed, not saved or frozen |
| `crm_rfm_recent_days` | number 1 to 3650 | blank | "recent" = bought within this many days |
| `crm_rfm_frequency_min` | number 1 to 1000 | blank | "frequent" = at least this many orders in 12 months |
| `crm_rfm_spend_min` | number | blank | "big spender" = at least this much spent in 12 months (net of returns) |
| `crm_winback_days` | number 1 to 3650 | blank | default for the lapsed list (shared with package E; whoever is pasted first seeds it) |
| `crm_metrics_batch` | number 100 to 20000 | 2000 | most customers scored in one run (technical batch, not a business limit) |
| `crm_metrics_schedule_on` | switch | OFF | OFF: scores refresh only on demand |
| `crm_metrics_schedule_hours` | number 1 to 720 | blank | blank: the scheduled refresh does nothing even if ON |
| `crm_segment_max_members` | number 100 to 50000 | 5000 | largest list that can be frozen (technical safety size) |
| `crm_seg_export_on` | switch | OFF | OFF: no export |
| `crm_seg_export_max_rows` | number 1 to 50000 | blank | blank: export stays blocked even if ON; a bigger list is refused, never cut short |

Only the owner changes rules (`set_rule`). With all three RFM numbers blank the labels are exactly those of the existing Customer value report (`m1_rfm`: Champion, At-risk, One-time, Regular, plus Inactive and No purchases); the test compares them customer by customer with the report. With all three set: Champion, Loyal, Big spender, New, Recent, At risk, Drifting, Lost, No purchases. A changed cut-off applies at once: the flags and the label are worked out when read, not stored.
Rights (`grant_defs`, module master, nobody holds them until the owner gives them; the owner always can): `crm_view`, `crm_contact_view`, `crm_export`, `crm_settings_edit`. `customer_manage` (existing) may also view and refresh. Other CRM packages seed the same codes with "where not exists".

## 5. What each function checks (all server side; a hidden button is also a refused request)

* Look (preview, pages, overview, labels, lapsed, top customers, status, pickers): owner, `customer_manage`, `crm_view` or `crm_settings_edit`.
* Refresh scores: owner, `customer_manage`, `crm_settings_edit`. Scheduled run: the notify bot or the owner, and only if the switch is ON and the hours are set.
* Save / retire / freeze: owner or `crm_settings_edit`, **and** `crm_segments_on` ON. Retire needs a reason. Idempotent by client id. Names are unique among active lists (case ignored). Nothing is deleted (a trigger refuses it); frozen members are append-only.
* Export: owner or `crm_export`, `crm_seg_export_on` ON, `crm_seg_export_max_rows` set, a reason of at least 3 characters. Logged in the append-only `crmc_export_log` and in `audit_log`. The phone column is masked unless the caller is the owner or holds `crm_contact_view`. Address, notes and birthday are never exported. Consent columns (SMS, WhatsApp, do-not-contact) are included so the receiver can filter.
* Customer profit: the above **and** the existing cost test (`biz_cost_ok`). It reads the one cost source of the reports (`_cogs_lines72`) and the places the caller may see; revenue without a known cost is shown apart, never guessed. The test checks that the customers' cost plus the walk-in sale equals `biz_daily` for the same days.
* Phones: shown masked unless package B's guard is OFF or absent, the caller is the owner, or holds `crm_contact_view`. Read through the rule `crm_pii_guard_on` (missing rule = OFF = today's behaviour) and the style rule `crm_mask_style` (missing = first 3, last 2). The answer never contains the full number for a masked caller (tested).
* Do-not-contact: if package B's table `crm_contact_prefs(customer_id, dnc)` exists, the "agreed to messages" condition excludes those customers and "not agreed" includes them; if the table or column is absent, nothing is excluded (tested both ways). The send step (package D) must still check consent itself.

## 6. The safe rule builder

A rule is data: `{"match":"all|any","conditions":[{"field":..,"op":..,"value":..}]}`, up to 8 conditions (the screen offers 5). `_crmc_rule_norm` checks it against a fixed catalog: unknown field, operator not allowed for the field, unknown key, wrong value type (numbers must be JSON numbers), out of range, list too long, rule too big, empty rule: all refused as `bad_rule:<reason>`. The checked rule is evaluated by fixed written-out queries, one branch per kind of field, with the values as parameters. There is no dynamic SQL on a user value (the only `execute` in the package is one fixed text for package B's optional table); a test reads the function source to prove it, and 45 attempts (SQL text in a field, operator or value, quotes, `%`, objects, huge lists, control characters) are refused or only ever matched as plain text.
Fields: days since last visit, orders (all time, 12 months), spent (total, 12 months), average bill, amount owed, points, days since joined, birthday month, birthday within N days, anniversary within N days, birthday this month, birthday on file, owes money, agreed to messages (any / SMS / WhatsApp), tier, customer type, customer group, source, customer label, bought at outlet, bought any of these items (optionally within N days), never bought any of these items.
A customer with no score row yet is never matched by a score condition; the preview says how many such customers there are and the screen asks for a refresh. Customer-table conditions (tier, type, group, source, birthday, joined, agreed) need no score.

## 7. Contracts for the other CRM packages

* `crm_segments(id, name, kind 'dynamic'|'list', rule, active, ...)` and `crm_segment_members(segment_id, customer_id)` as in the design. `_crmc_audience(segment_id, cap)` returns the customer ids of a list (active customers only; a frozen list returns its copied members; a list over the cap raises `over_cap:<n>`). Closed to browsers; the caller does its own permission test.
* `_crmc_scored(date)` returns one row per scored active customer: days since last, orders, spends, due, points, `r_ok`, `f_ok`, `m_ok`, `label`, `mode`. **Difference from the design:** `r_score`, `f_score`, `m_score` and `segment_label` are *not stored columns* of `crm_metrics`; they are worked out live from the stored numbers and the current cut-offs so a changed setting needs no rebuild. The scores are yes/no flags (meets the owner's cut-off or not), not 1 to 5 grades, because the owner's settings are three cut-off numbers.
* `crm_metrics` columns: last/first visit, orders (all, 12 months), lifetime spend (net of returns, same rule as `_cust_stats43`; a test compares every customer), 12-month spend, gross spend, returns, average bill, due, points, main outlet, outlets (12 months), top three items (12 months), computed at/on. Closed to browsers.

## 8. Tests and proofs (local throwaway Postgres 16, port 5573; the live Supabase was never touched)

`bash tests/sql/run_crmc.sh` builds phases 8 to 98 (and 99), pastes 306 to 308 twice and runs everything:

* `phase306_test.sql` 79 checks, `phase307_test.sql` 146, `phase308_test.sql` 85, all pass (hand-computed expectations in the fixture and the test comments).
  Negative tests: no permission (cashier, viewer without edit, exporter without view, anonymous, unknown user), saving switched off, blank settings block (export rows, schedule hours, lapsed days), injection and malformed rules (45), empty list (freeze and export refused), huge list (preview counts 127, freeze over a cap of 100 refused with the size and nothing created, export over the limit refused), duplicate name, client-id repeat, retired list, append-only members and logs, hard delete refused, bad sort / label / range.
* `crmc_before_after.sh`: on a database through phase 99 with the Wave 1 fixtures, **33 snapshots** (P&L, L1 L3 L4 L5, T4, E2, E3, expense report, partner calculation and split, brand P&L, income statement, balance sheet, trial balance, cash flow, day book, day book vs journal, journal lines, posting dry run, stock levels / valuation / movements, customer dues / ledger / balance, supplier balance, returns, payments, cash moves, reconcile) are identical (a) before and after pasting 306 to 308, (b) after a second paste, (c) after switching **every** CRM-C setting ON and using every function (refresh, schedule, preview, pages, save, freeze, retire, overview, labels, lapsed, value card, profit, export). The tests also compare a byte-level hash of sales, payments, returns, customers, journal, points, opt-in and stock ledger before and after.
* `crmc_hook.sh`: the `notify_scan` hook (section 3), 8 checks.
* `node tests/web/crm_segments_test.js $(pwd)/tests/web`: 65 assertions, 0 failures, no console errors, 360 px without horizontal overflow, English labels only. `node tests/web/crmc_hooks_run.js $(pwd)/tests/web`: ia, nav, nav2, control, favsync, settings2 and the CRM-C test pass on the hooked scratch copy.
* Older suites: the CRM-C phases create objects only; the failing lines of the older suites are the same on a database through 98 and through 308 (12 suites compared on a clean database through 98 and one through 308: 9, 12, 25, 43, 45, 46, 47, 61, 62, 72, 76, 87 give identical result lines, including the known baseline failures of 12, 47 and 72).

### Performance (tests/sql/crmc_perf.sql: 5000 customers, 40000 sales over 18 months, two outlets)

| Step | Time |
|---|---|
| first score run, 2000 customers per run (as capped) | about 2.0 s per run, 4.2 s for all 5000 (3 runs) |
| incremental run after 200 customers bought | 95 ms |
| "which customers need scores" (stale check) | 27 ms (index on `sales(customer_id)` is used per customer) |
| preview of one rule | 21 to 32 ms; three conditions 79 ms; "bought item within 90 days" 135 ms (one pass over the sales of the window: `lines @> ...`, 9 ms in EXPLAIN); "never bought item" and "agreed to messages" about 115 ms |
| one page of 50 customers | 13 ms |
| overview / label summary / lapsed list | 21 ms / 8 ms / 10 ms |
| customer profit, 180 days, 40000 sales | 213 ms |

EXPLAIN notes: the score read joins `crm_metrics` (5000 rows) to `customers` with a hash join, 2 ms. The item condition is a bitmap scan on `sales_date_loc` followed by a semi join on the jsonb containment: no index was added. Without a date window the item condition scans all done sales; a GIN index on `sales(lines jsonb_path_ops)` would speed that up if a shop has millions of sales, but it would be an index on the hottest table, so it is **not** created here (owner decision). Two slow spots were found and fixed during the run: a CTE re-evaluated per customer (240 ms to 5 ms) and a page built for all customers before the limit (750 ms to 13 ms). Inserting the 40000 test sales took 220 s because of the existing triggers on `sales` (audit, loyalty), not because of CRM-C.

## 9. Decisions made here (the owner can change them)

* Scores are cached and refreshed on demand or by an optional schedule, never by a trigger on `sales`. A score is stale when it was worked out on an earlier day, or a sale or return is newer than it (the sale's own time stamp; an offline sale kept with its old time shows up at the next daily refresh). The screens say how many scores are older than the latest sales.
* "Lifetime value" is realised spend (net of returns), not a forecast. "Repeat-purchase rate" counts customers with at least one order. "Bought at outlet" and the outlet filter of the overview use the last 12 months; a customer belongs to the outlet where they bought most in those months.
* A customer who never bought is never "lapsed".
* The export uses its own switch and limit (`crm_seg_export_on`, `crm_seg_export_max_rows`) so it works without package B; when B is installed its guard and grant `crm_contact_view` still decide who sees full phone numbers. Open question OD-C7 of the design (who may see full numbers) stays with the owner.
* No customer data goes into notifications or digests. Nothing is sent to anyone by this package.

## 10. Not tested / unverified

* Live Supabase, a real phone, real SMS or WhatsApp (this package sends nothing), real customer volumes beyond the 5000 synthetic ones.
* The web screens were tested with stand-in server answers in a headless browser at 360 px, not on a real phone; the (i) info sheet UI is not built here (the JSON is provided for it).
* Package B is simulated (a stand-in `crm_contact_prefs` table, the `crm_pii_guard_on` rule); the real tables of B were not available in this branch.
* The hook text for `ia.js`, `index.html`, `nav.js` was proved on a scratch copy of the current files; if W3-B/W3-I change those files first, re-run `tests/web/crmc_hooks_run.js`.
* Older suites were compared on 12 files (section 8), not all 56.
* pg_cron / GitHub schedule for the score refresh: the optional `notify_scan` line depends on the existing 30-minute notify job being scheduled by the owner.

## 11. BUILD-LOG entry for the integrator

CRM-C (phases 306 to 308): customer lists with a safe rule builder, customer scores and RFM labels from the owner's own cut-offs, overview with repeat-purchase rate and lifetime value, lapsed and at-risk lists, customer profit view, export. 310 SQL checks, 65 web checks, 33 accounting snapshots identical with every setting ON. Everything OFF or blank by default. Not confirmed: live Supabase, a real phone, package B's real tables.
