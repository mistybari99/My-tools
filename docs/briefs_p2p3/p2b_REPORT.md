# p2b report - P2 gaps #1-#5 (phase53 + web/finance2.js)
Files: supabase/phase53.sql, supabase/phase53_test.sql, web/finance2.js, tests/web/finance2_test.js. Phase40 is untouched (no existing function re-created; additive only).

## What is built
* #1 Bank statement reconcile. Tables bank_statement_lines (append-only, unique (account,row_hash) so re-pasting a statement adds nothing), bank_recon_matches (current state, one active match per statement line and per journal line), bank_recon_trail (append-only). Fns: bank_stmt_import (JSON rows, dry first, refuses the whole import if any row is invalid, p_client idempotent), bank_recon_suggest (suggestions only, "confident" = single candidate or single reference hit), bank_recon_candidates, bank_recon_match / _match_many (dry first, per-pair failures listed), bank_recon_unmatch (reason required), bank_recon_report (unmatched both sides, totals, difference, last statement balance), bank_recon_lines. Match needs the exact same signed amount on the same account (accounts under 1100 only). NOTHING is posted to the journal.
* #2 Year-end close. year_closes + year_close_run(from,to,note,client,dry default TRUE) / year_close_reverse / year_close_list. One closing entry (source_type year_close, flags year_close) dated the year end, one line per P&L account and location, balancing line(s) to mapping `retained_close` (default 3900) per location. Owner only; needs period_closed_until >= year end (else problem `period_not_locked`); refuses overlap/double close; reverse = phase40 _acct_reverse (void + reversing entry on the year-end date), year can be closed again. acct_pnl_ex_close(from,to,loc) gives the real profit of a closed year (phase40 acct_income_statement reads 0 once closed - by design, that is what a close does).
* #3 VAT ledger (report only): vat_report(from,to,loc). Reuses the existing phase8 switches vat_on (OFF) and vat_rate (no default). New switch vat_prices_include (default ON: prices already contain VAT; OWNER MUST CONFIRM with the adviser). Output VAT = sales (done) minus sale returns; input VAT = posted purchase bills minus supplier returns; only items with vat_applicable = true are taxed; items with undecided VAT (null / free-text purchase lines) are reported as undecided_amount, never taxed. Off -> {off:true}; on without a rate -> {data_needed:true}. No journal lines, no tables.
* #4 Fixed assets. fa_assets (owner-entered: code, cost, salvage, life months, depreciation start month; method = straight_line only), fa_depr_posts (append-only, unique (asset,month)). fa_asset_save (dry first), fa_schedule (equal months, last month takes the rounding remainder), fa_depr_post(through, dry default TRUE; completed months only; posts in order per asset; skips with reason before_start / period_closed; one journal entry per asset-month, Dr 5820 / Cr 1590 via mappings depreciation / accum_depr), fa_register, fa_asset_dispose (stops further depreciation, reason required).
* #5 Budgets. budgets (account, month, optional location), budget_log (append-only old -> new), budget_set (dry first, many rows), budget_list, budget_vs_actual (excludes year-close entries; variance positive = good; per month optional).
* All writes: SECURITY DEFINER, `_acct_manage()` (owner or accounts_manage); tables RLS read-only, no write grants; helper fns closed to browsers; new helper _a53_mgr() is granted so RLS policies can call it.

## Switches (rules, module books, all default OFF)
bank_recon_on, year_close_on, fixed_assets_on, budgets_on; VAT = existing vat_on + vat_rate (+ new vat_prices_include, default ON). New mapping keys: depreciation (5820), accum_depr (1590), retained_close (3900).

## Tests
* SQL: phase53_test.sql 112 pass / 0 fail on a fresh DB (phase8..51 + 53); phase53.sql applied 2nd time on the same DB: error-free.
* Web: tests/web/finance2_test.js - 0 assert failures, 0 JS errors (parser, all 5 tabs, dry-run-first flows, switches-off banners, VAT off/no-rate, non-owner close, no-permission, Bangla, no overflow at 360px).
* Regression: phase40_test.sql 119/0 on DB through 53 (first run showed one changed message because of an FK I had added on journal_lines; FK removed, now identical to a DB built through phase51). phase47_test.sql: same 3 failures on both DBs (pre-existing, not mine).

## Lead integration
web/ia.js (group acc; icon key doc exists):
`  rec('finance2', 'acc', ['আর্থিক হিসাব ২ (ব্যাংক, বছর শেষ, ভ্যাট, সম্পদ, বাজেট)', 'Finance 2 (bank, year-end, VAT, assets, budgets)', 'Finance 2 (bank, year-end, VAT, assets, budget)'], { icon: 'doc', ok: (c) => c.own || c.GF.accounts_manage === true, kw: ['bank reconcile', 'bank statement', 'year end', 'closing', 'vat', 'fixed asset', 'depreciation', 'budget', 'ব্যাংক স্টেটমেন্ট', 'বছর শেষ', 'ভ্যাট', 'অবচয়', 'বাজেট'] }),`
web/index.html: `<script src="finance2.js"></script>` right after `<script src="accounts.js"></script>`.
Paste order: ... phase51, phase52 (other agent), phase53. Owner then turns on switches in #/switchboard and enters vat_rate himself.

## NOT done / UNVERIFIED
* Year close does not check for unposted source documents (acct_post_pending backlog) before closing - the owner must run Post now first; the lock requirement is the only gate.
* Closing is company-wide only (no per-location close); year_close entries have no location_id (lines carry it).
* Depreciation: straight line only; no disposal/sale journal (use manual journal); no reversal of a posted depreciation month (use acct_journal_reverse is NOT allowed for source fa_depr - none built); no partial first month.
* Statement import is JSON-rows on the server; CSV parsing is in the browser (tested for comma/semicolon/tab, Dr/Cr columns, Bangla digits) - real bank formats beyond these are UNVERIFIED. No auto-matching of many-to-one (one deposit = several sales).
* VAT: assumes VAT is per item flag, whole-document discount share, same inclusive/exclusive setting for sales and purchases; rounding is per report not per invoice; not a legal VAT return format (Mushak) - needs the adviser.
* Location-limited accounts_manage holders: reports are filtered by location, but the bank tables are company-wide for anyone with accounts_manage.
* Budget has no approval flow; web page has no budget history view (log exists in budget_log).
