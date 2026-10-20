# Step F (phase84) - audit trail: report
Branch fix/phase-F (base fix/phase-C2b). Files: supabase/phase84.sql, supabase/phase84_test.sql. No web, live DB not touched. Additive, paste-twice safe (applied twice, 0 errors). No amount hard-coded. Only stock_reconcile re-created (latest = phase10 definition; changed lines tagged `-- bos84`; grants unchanged: authenticated yes, anon no).

## ১. যাচাই হয়েছে (tested on a fresh DB built phase8..phase78 without 72, then phase84)
phase84_test.sql: 64 pass / 0 fail. What was proved:
- stock_balance: delete refused (also a zero balance that has ledger rows); only an EMPTY phantom row (qty 0, no cost, no ledger row) may go; item/place change refused; direct qty/avg_cost change writes 1 audit_log row (old, new, user_id, staff_id, db_user, record_id item:place); updated_at-only change not logged; sale path (stock_post) NOT logged by design (see overhead).
- stock_batches: delete refused; item/place/qty_made/made_at change refused; qty_remaining change by stock_post audited (old 40 -> new 36); expiry/note change audited.
- stock_transfers: delete refused; status change audit (existing since phase10) shows old sent / new cancelled.
- purchase_lines: delete refused on a posted bill; allowed on a DRAFT (save_purchase edit replaces lines - tested, still works); qty/unit_cost/bill_id of a posted line cannot change; base_qty/unit_cost_base (set at posting) stay writable; description change audited (existing trigger).
- stock_wastage: already immutable since phase10 (UPDATE + DELETE raise ledger_immutable) - tested, nothing added.
- production_runs: new AFTER UPDATE audit only when status/void_by/void_at/void_note change. Real production_void writes 1 row: old status done / new void + void_note + void_by + void_at + user. Normal post-time updates and a repeated void add no row.
- stock_reconcile(true): clean-up + tampered ia (qty+7) and ic (qty-2, avg 9): dry run lists 2 and writes nothing; fix writes exactly ONE reconcile_fix row per corrected balance (old qty/avg, new qty/avg, user_id, staff_id, source) and no extra generic 'update' row; 2nd run finds nothing; next direct tamper is logged again; non-owner refused.
- Privileges: new trigger functions closed to anon/authenticated; RLS still on; app role still cannot write/delete these tables.
### Overhead, 10,000 stock_post(sale_out) calls, 3 runs each, fresh DB copies (ms, mean)
| case | before (phase78) | after (phase84, gated) | audit EVERY balance update (not shipped) |
|---|---|---|---|
| item without batch | 5430 | 5420 (~0%, noise) | 6460 (+19%) |
| item with batch (p_batch) | 24990 | 26010 (+4%) | 26530 (+6%) |
The gate: the stock_balance audit trigger skips when pg_trigger_depth() > 1, i.e. when the update comes from the ledger insert trigger (_ledger_to_balance). Those updates are 100% derivable from the immutable ledger, so logging them would only cost +19% per sale. Every other writer (any SECURITY DEFINER function, SQL editor, service_role) is at depth 1 and IS logged. Batch changes are audited on every change (+4%). (The session-marker idea needs stock_post/_ledger_to_balance re-created, which this step was told not to do, so depth is used instead.)
### Regression, before (84base = phase78) vs after (+phase84), same suites on same build
phase10,11,12,13,14,15,16,17,18,19,20,23..28,40..54,60,61,62,70,71,73,74,75,78: identical PASS/FAIL sets (e.g. phase10 306/2, 12 97/1, 19 93/2, 20 63/0, 23 91/1 - the pre-existing fails are the same before and after).
Exception - phase21 and phase22 (test FIXTURES, not product code): they run `delete from stock_balance` as postgres to fake a cache state. The new no-delete refuses that: phase21 gets 2 fixture errors (pass/fail counts unchanged 75/1), phase22 8 knock-on fails (82/1 -> 71/9). With only the stock_balance guard trigger disabled the same two suites give exactly the old numbers (phase21 75/1, phase22 82/1). Old test files were not edited (not mine); the lead may change those two fixture lines to `update stock_balance` or disable the trigger in the fixture.

## ২. পড়ে বোঝা (code-read, not run)
- stock_balance/stock_batches rows cannot be changed by the app roles at all (no grant) - the new triggers matter for definer functions and direct DB.
- Audit rows use auth.uid(); inside a definer function called by a user that is the user. From the SQL editor it is NULL, so `db_user` (session_user) is stored too.
- Depth gate caveat: a direct UPDATE of stock_balance made from INSIDE another trigger (depth > 1) would be skipped. No such code exists today (grep of phase10..78); a future one would need its own audit.
- Batch audit: every stock_post batch decrement writes a row (volume = number of batch sales).
- Not added (not asked): no-delete on production_runs, entry_ledger_posts, serials, item_price_history audit (a4 F9 mentions them).

## ৩. যাচাই হয়নি
- service_role / direct-DB path: the triggers are table-level and fire for every role, but a real Supabase project with service_role / edge functions was NOT available here; only `postgres` in a scratch DB was tested. Treat as unverified.
- Live DB, real traffic volume of audit_log growth (batch sales), concurrency (parallel sales while audit trigger runs).
- Overhead numbers are from a scratch Postgres 16 with plpgsql loops (noise about +-10%); the live Supabase plan may differ.

## Owner decisions
1. OK that the stock_balance audit skips ledger-driven (sale/receive) updates (derivable from the ledger)? Alternative: log all (+19% per sale, big audit_log).
2. Add no-delete (and a void-only update rule) to production_runs, and audit for entry_ledger_posts / serials / item_price_history? (not done)
3. Posted purchase lines are now frozen (qty/cost/item); drafts stay editable. OK?
4. Two old test fixtures (phase21/22) delete stock_balance - change the fixtures (lead) or accept.
