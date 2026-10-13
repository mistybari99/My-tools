# p3a REPORT - P3 gaps #7-#10 (phase60 + web/stockx.js)
Files: supabase/phase60.sql, supabase/phase60_test.sql, web/stockx.js, tests/web/stockx_test.js. Additive, paste-twice safe (2nd apply: no error). stock_post / stock_wastage NOT changed (test asserts no bos60 in stock_post).

## Built per gap
- #7 reorder: `reorder_report(p_loc, p_days)` read-only. Avg daily usage = sale_out + issue_out minus sale_void_in / sale_return over N days. Suggest = max(avg*(lead+cover), min_stock) - on hand. Why = below_min | runs_out_in_lead | cover. No PO, no cost. Rules (owner, Settings): reorder_lookback_days 30, reorder_lead_days 3, reorder_cover_days 7.
- #8 wastage: phase10 ALREADY had option_lists 'wastage_reasons' + validation (bad_reason) in stock_wastage. Added 6 reasons (qc_reject, spillage, overproduction, weight_loss, pest, power_cut; insert-if-missing) and `wastage_by_reason(loc, from, to)` (default last 30 days, label bn/mix/en, unknown codes still shown). Old rows untouched (stock_wastage is immutable).
- #9 batch/expiry: phase10 already had stock_batches + FEFO inside stock_post + expiry_list; GRN/purchase posting passes batch null. Reused them: new column `stock_batches.batch_no`, append-only `grn_batch_links` (no FK to stock_batches on purpose, keeps the phase10 truncate test passing). `grn_batch_add(source_type purchase|grn, source_id, item, qty, unit, batch_no, expiry, made, client)` creates a batch for goods already received (limit: bill qty received; unbatched on-hand; unique batch no per item+place; expiry today..+10y; grant grn_batch). `near_expiry_report(loc, days)` (wraps expiry_list, adds batch_no and QC flag), `fefo_hint(item, loc)` (same order as stock_post). Rule expiry_warn_days 7.
- #10 QC: `qc_record(source_type production|grn, source_id, status pass|hold|reject, checks [{code,ok}], note, photo, client)`; checklist = option list 'qc_checks' (8 seeded); pass cannot carry a failed check; hold/reject need a note; each record supersedes the previous (append-only, update/delete/truncate blocked). `qc_list` (latest per source), `qc_history`, `qc_gate`. hold/reject always raises a YELLOW exception (RED if switch on). Grant qc_record (owner always).
- Switch `quality_block_on` default OFF. When ON: grn_batch_add refuses new batches on a held/rejected GRN (qc_blocked) and fefo_hint / near_expiry_report mark such batches `qc_blocked`.

## New grants / rules
Grants: grn_batch (storekeeper, purchasing, factory_incharge), qc_record (storekeeper, factory_incharge, management). Rules: reorder_lookback_days, reorder_lead_days, reorder_cover_days, expiry_warn_days, quality_block_on(false).

## Tests
- SQL phase60_test.sql on fresh DB p60db (phase8..51 + 60): RESULT 62 pass, 0 fail (reorder maths, lookback window, owner lead days, wastage report, FEFO really consumed by stock_issue, batch limits, duplicates, permissions/location scoping, append-only, RLS, switch OFF/ON).
- Web: node tests/web/stockx_test.js -> assert failures 0, errors none (360px no overflow, Bangla, friendly error).
- Regression: phase10_test 0 failed (after dropping the FK); phase12/19/23 FAIL lines identical to a DB built only through phase51. No existing function was re-created.

## Registration for lead
ia.js: `rec('stockx', 'stock', ['স্টক রিপোর্ট ও কোয়ালিটি', 'Stock reports & quality', 'Stock report ও quality'], { icon: 'items', ok: locOk, kw: ['reorder', 'expiry', 'batch', 'fefo', 'wastage reason', 'quality', 'qc', 'রিঅর্ডার', 'মেয়াদ', 'ব্যাচ', 'নষ্টের কারণ', 'কোয়ালিটি'] }),`
index.html: `<script src="stockx.js"></script>` (after the stock/paths scripts; needs BOS_APP). Route name = stockx.

## NOT done / UNVERIFIED
- quality_block_on does NOT stop sales, issues, transfers or production posting (would need changes to stock_post / posting functions, forbidden). It only blocks new GRN batches and marks batches blocked.
- Batch capture is a separate step after the receipt (ledger rows are immutable, so the receipt row keeps batch_id null); GRN source 04-1 is only checked for "item on a line" and on-hand room, not its counted qty (default setting skips GRN stock posting).
- Transfers do not carry batch_no to the destination batch (phase10 transfer creates the batch without it).
- No per-item lead days (one owner rule); no on-order qty because there is no PO table in the ledger. Reorder usage ignores transfers/wastage by design.
- Web page not browser-checked in the real index.html (script tag not yet added); tested via injected script with mocked RPCs. QC photo field not in UI. No Bangla-mode visual review beyond overflow.
