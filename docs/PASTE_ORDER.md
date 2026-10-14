# PASTE ORDER (the single canonical order)

Branch `fix/phase-INT4` (supersedes the INT3 list). The machine-readable copy of the order is `tests/sql/paste_order.env` (read by `tests/sql/final_build.sh`, `tests/sql/run_all_sql.sh` and `tools/check_paste_order.py`; the checker fails if this table differs from it). Every file is additive and paste-twice safe. Nothing is edited in an old phase file; later phases only `create or replace`.
This is the order that was built and tested from nothing (fresh Postgres 16, see docs/briefs_p2p3/step_INT2_G_REPORT.md and step_INT3_REPORT.md). Any other order is untested.

## A. Foundation (already on the live database - do NOT paste again)

`schema.sql`, `phase2.sql`, `phase3.sql`, `phase4.sql`, `ALL_NEW.sql`, then
`phase8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 60 61 62 70 71`
(exactly the list in `tests/sql/build_fresh_db.sh`). Never re-paste phase21 after phase24, and never re-paste phase40 / ALL_NEW10 after phase85
(they would bring back the 7-argument `acct_journal_post`; if it ever happens, paste phase89 again - it removes the old overload).

## B. New files, strictly in this order, each once

| # | file | needs (from the file's own header) | note |
|---|------|---------------|------|
| 1 | phase72.sql | foundation | |
| 2 | phase73.sql | foundation (recipes from phase19) | |
| 3 | phase74.sql | 73 | |
| 4 | phase75.sql | 73, 74 | |
| 5 | phase76.sql | 61, 62, 70, 71 | |
| 6 | phase77.sql | 76 | |
| 7 | phase78.sql | 73, 74, 75 | |
| 8 | phase79.sql | 72..78 | merge of 72..78 function bodies; guard inside |
| 9 | phase80.sql | 72..79 | guard inside |
| 10 | phase81.sql | 72..79 | guard inside (does not need 80) |
| 11 | phase82.sql | 78 | |
| 12 | phase83.sql | foundation | |
| 13 | phase84.sql | 78 | |
| 14 | phase85.sql | 72..79 | guard inside |
| 15 | phase86.sql | 76 (and 77..79) | |
| 16 | phase87.sql | 72..79, 82, 84 | guard inside |
| 17 | phase88.sql | 72..79, 82, 83, 84 | guard inside |
| 18 | phase90.sql | foundation .. 84 | guard inside (lists the missing phases) |
| 19 | phase91.sql | 86 | guard inside (checks its tables) |
| 20 | **phase89.sql** (merged function bodies) | 72..88, 90, 91 | guard raises `phase89 needs phases 72..88, 90, 91 pasted first ... missing: <numbers>` if any is absent |
| 21 | phase92.sql | 72..88 | guard inside (invoice on screen) |
| 22 | phase93.sql | base schema | guard inside (print templates) |
| 23 | phase95.sql | base + 8 | guard inside (cash drawer option) |
| 24 | **phase94.sql** | 76, 80, 81, 85, 86, 89, 90, 92, 93 | guard raises `phase94 needs phases 76, 80, 81, 85, 86, 89, 90, 92, 93 pasted first ...`. Security step (docs/briefs_p2p3/step_Sec_REPORT.md): re-creates 9 functions with the tag bos94 (none of them is in phase89's list) and gives `inbound_message_receive` / `web_order_submit` one extra defaulted argument. Do NOT paste phase76 again afterwards (it would bring back the old signatures next to the new ones). |
| 25 | phase96.sql | 80, 85, 89 | guard inside (needs `bos85` and `bos89` in `_acct_docs`; refuses a body with a tag it does not know). Opening-stock helper + cost waiting. Re-creates `_acct_docs`, `_acct_inv_split72`, `_acct_stock_moves85`, `_pvar85`, `inventory_vs_gl` |
| 26 | phase97.sql | 72..88, 90, 91, 89 | guard inside. Landed cost. Re-creates `_acct_docs` from the phase89 body + bos97 blocks, so on its own it ERASES every bos96 line |
| 27 | **phase98.sql** | 72..97 | guard inside (24 marker objects + `bos89`; raises `phase98 needs phases 72..97 pasted first ... missing: <numbers>`). Re-creates 5 functions only: `_acct_docs` = phase89 body + all bos96 lines + both bos97 blocks (tag bos98 on one comment line), and the 4 other phase96 functions byte-identical. Creates run only if both guards passed. No table, rule, data, privilege or trigger |
| 28 | phase99.sql | 72..98 | guard inside (one marker object per phase 72..97 + `bos89` + `bos98` in `_acct_docs`; raises `phase99 needs phases 72..98 pasted first ... missing: <numbers>`). Step Opt: two OPTIONS (bill payment, inbox masking), all default OFF. Re-creates 5 functions only (`inbox_list`, `inbox_get`, `online_orders_list`, `online_order_get`, `telegram_chat_info`, tag bos99) - none of them is touched by phase98, and phase99 does not touch `_acct_docs`. If a later phase re-creates one of the five, merge into the phase99 text. See docs/briefs_p2p3/step_Opt_REPORT.md |
| 29 | phase100.sql | 72..97 | guard inside (Step Cat: one category / sub-category master, rule `category_required_on_item`). Re-creates no existing function. See docs/briefs_p2p3/step_Cat_REPORT.md |
| 30 | phase101.sql | 72..98 | guard inside (Step Rec: setup advisor rows for every rule of phases 82..98; only `setup_rec_defs81` rows, ON CONFLICT DO NOTHING). See docs/briefs_p2p3/step_Rec_REPORT.md |
| 31 | phase102.sql | item images; re-creates no accounting function | goes between 101 and 103; phase103 does not need it |
| 32 | phase103.sql | 72..101 | guard inside (one marker object per phase 72..99 + `bos98` in `_acct_docs` + `item_categories` (100) + the phase101 advisor row; raises `phase103 needs phases 72..101 pasted first ... missing: <numbers>`). Step E2E: defects D-1..D-8 of the independent end-to-end run. Re-creates 20 functions from their LATEST bodies (`_acct_docs`, `_acct_stock_moves85`, `inventory_vs_gl`, `_cw_docs96`, `_cw_rows96`, `_cw_posted96`, `_ob_rows96`, `_ob_plan96`, `opening_stock_apply96`, `recipe_cost`, `_setup_chk81`, `setup_recommendations`, `setup_recommend_apply`, `_inb_pii_f99`, `_inb_pii_json99`, `inbox_list`, `customer_directory`, `find_customer`, and `online_order_get` / `online_orders_list` byte-identical so one paste repairs a re-paste of phase89; every older bosNN tag kept, new tag bos103), adds 3 internal helpers, 1 switch `acct_manual_prod_in103` (default OFF), 1 flow check row, 1 grant def, 1 append-only table `opening_stock_followups103` + view `opening_covered103`. A body with a tag it does not know stops the paste. See docs/briefs_p2p3/step_E2E_REPORT.md |
| 33 | phase104.sql | 72..103 | guard inside (Step Dash). Owner dashboard layouts: table `dash_layouts` (RLS, a user sees only their own row), `dash_layout_get()`, `dash_layout_save()`, one audit trigger. Re-creates no existing function (tag bos104). |
| 34 | phase105.sql | 72..103 | guard inside (one marker object per phase 72..99, `item_categories` (100) and the phase103 advisor row `flw_grn_double103`, plus the phase99 / phase103 functions it re-creates; raises `phase105 needs phases 72..103 pasted first ... missing: <numbers>`; a body guard refuses to overwrite a body that carries a bosNN tag it does not know). Step Sec2: H1 customer phone / address bypass paths, M1 unmask race, M2 auto-payment limits, M3 keep_credit void, M6 phone regex, L3-L6. Re-creates 13 functions from their LATEST bodies (`_bp_uuid99`, `_bp_auto99`, `_bp_pay99`, `_bp_sp_void99`, `inbox_unmask`, `_inb_mask_phones103`, `_cust_pii103`, `customer_dues`, `customer_advances`, `customer_profile`, `customer_directory`, `customer_save`, `_inb_pii_cols76`; older bosNN tags kept, new tag bos105), adds `_bp_auto_ok105`, closed table `bos_salt105`, switch `customers_pii_guard_on` (default OFF). See docs/briefs_p2p3/step_Sec2_REPORT.md |
| 35 | phase106.sql | 72..103 | guard inside; backup / restore-drill coverage (section I). Re-creates only `_backup_tables()` and adds `backup_coverage106()`. |
| 36 | phase107.sql | 72..103 | guard inside; client error log (Step Errlog): 3 tables, 3 rules, 1 grant, 10 functions, all new. See docs/briefs_p2p3/step_Errlog_REPORT.md |
| 37 | phase108.sql | 72..103 | guard inside; Bangla label updates, UPDATE statements only (each fires only while the column still holds the old seed text); no table, column, function or privilege is changed. docs/i18n/BANGLA_REVIEW.md |
| 38 | phase109.sql | 72..103 | guard inside (marker objects 72..99 + `_rec_value103`; body guard refuses to overwrite a function that carries a bosNN tag it does not know). Step Conc: F1 `production_post` row-locks balances, F2 supplier lock `FOR NO KEY UPDATE` in 7 functions, F4 sorted bulk option views, F5 `setup_recommend_apply` one at a time, F6 rule `card_settle_over_mode` + advisor row. Re-creates 12 functions (tag bos109); since INT4 it leaves `_bp_pay99` alone when phase105 is already on it (phase111 merges it). See docs/briefs_p2p3/step_Conc_REPORT.md |
| 39 | phase110.sql | 72..103 | guard inside; performance: 8 indexes first (RUN AT A QUIET TIME), then 6 function patches (`_cogs_lines72`, `_item_cost_eff88`, `_rcs88`, `rpt_agg_sql`, `inbox_list`, `_acct_stock_moves85`; marker perf110). Results identical. See section M and docs/briefs_p2p3/step_Perf_REPORT.md |
| 40 | **phase111.sql** (closes the INT4 chain) | 72..109 (110 optional) | guard inside (marker objects of 72..107 and 109; raises `phase111 needs phases 72..110 pasted first ... missing: <numbers>`; body guard refuses an unknown tag). Step INT4: 3-way merge of `_bp_pay99` (phase103 body + bos105 L4 line + bos109 supplier lock), tags bos105 + bos109 + bos111. Nothing else. See docs/briefs_p2p3/step_INT4_REPORT.md |
| 41 | phase112.sql | 72..111 | guard inside (marker objects + `card_settle_over_mode`; body guard refuses an unknown tag on `_c78_rows`, `_r3q_l3_shop_pnl`, `biz_items`). BATCH 1a "profit truth" (audit A3 G1..G9): one net profit for the shop P&L and the dashboard tile (`profit_truth112`), sheet / payroll-app salary without double count, wastage, card fees, shared bills pro rata by days, unallocated row, returns netted in `biz_items`. Rules `profit_truth_mode`, `cost_share_prorate_mode`, `items_net_of_returns` (all default off) + 3 advisor rows. Tag bos112. Test: `supabase/phase112_test.sql` |
| 42 | phase113.sql | 72..111 | guard inside (body guard on `_acct_docs`, `acct_post_pending`, `_daybook_lines`, `customer_dues`, `collect_payment`, `lock_check`). BATCH 1b "books truth" (audit A4 G01 G03 G04 G05 G08): drawer shortage posts to 5800, dues net of the advance used, closed-period owner / scheduler warnings, day book = journal for voucher mode and card fee, `bank_stmt_post113`. Rules `drawer_short_post`, `dues_net_advance`, `period_lock_owner_mode`, `period_lock_late_warn`, `daybook_align_mode`, `bank_stmt_post_on` (all default off) + 6 advisor rows + mapping `cash_short`. Tag bos113. Test: `supabase/phase113_test.sql` |
| 43 | phase114.sql | 72..103 | guard inside. BATCH 2 stock safety part 1 (audit2 A2): 7 switches, all default OFF (`late_sale_follows_block`, `transfer_needs_stock`, `return_uses_sale_rows`, `item_unit_change_needs_zero`, `item_lifecycle_needs_zero`, `batch_for_adjustments`, `batch_refill_cap`) + advisor rows (phase 114), `stock_batch_reconcile(p_fix)`, 2 triggers. Patches by exact-text insert (helper dropped at the end; older tags kept, stops with a message if the expected line is gone): `_sale_stock_out`, `stock_transfer`, `sale_return`, `stock_count_adjust`, `stock_opening` (tag bos114). Test: `supabase/phase114_test.sql`. |
| 44 | phase115.sql | 72..103 | guard inside. BATCH 2 part 2 (audit2 A5): 4 switches, default OFF (`transfer_late_receive`, `transfer_return_marker`, `transfer_notify_receiver`, `transit_loss_gl_fix`) + advisor rows (phase 115), columns `stock_transfers.kind/reason/ref_transfer_id`, `stock_receive_more`, `stock_return_transfer`. Patches: `stock_transfer` (notify, tag bos115), `_acct_stock_moves85` and `_acct_docs` (the synthetic +short transfer_in of `_transit_loss83` gets no leg; marker `b2s115`, deliberately NOT a bosNN tag, like perf110 / sec2-L6, so the body guards of phase98 / 103 / 110 do not refuse a re-paste). Independent of phase114. Test: `supabase/phase115_test.sql`. |
| 45 | phase116.sql | 72..111 | guard inside (marker objects 72..97, `opening_covered103`, `bos109` in `production_post`; body guard refuses a function that carries a tag it does not know). BATCH 3 (manufacturing cost engine): 7 switches all OFF, semi-finished goods as ingredients, packaging on actual yield, standard-vs-actual (`recipe_std116`, `production_variance116`), pool drivers, provisional conversion + `production_reprice116`, supplied cost reaches the average + `production_recost116`. Re-creates `_recipe_lines_ok`, `_recipe_need`, `production_post` (7 args), `_conv_cost`, `cost_wait_supply96`, `production_run_costs`, `production_void` (tag bos116). Test: `supabase/phase116_test.sql`. |
| 46 | phase117.sql | 72..111, 116 | guard inside. BATCH 3 (factory overhead in the books): `pool_gl_post117` (pool rows posted Dr expense / Cr 2400, reversed when retired) and `factory_labour_absorbed117` (branch P&L), both OFF; `pool_vs_gl117`, `overhead_trueup117`. Re-creates `pool_set`, `_cs_push_pools`, `_p27_pl` (tag bos117). Test: `supabase/phase117_test.sql`. |

**Invariant: the canonical order ends ...109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 120, 121, 122, 125, 126 (rows 27-52, numbered here without the two slots of phase123 and phase124 of the parallel agents C1 and Import-Export, which the integrator slots in between and renumbers; phase119 is a test-only file, 120 is the report-speed file, 121 is the review-fix file). Phase111 closes the INT4 chain, rows 41-47 are the audit-fix batches (112/113 batch 1, 114/115 batch 2, 116/117 batch 3, 118 batch 4 read-only).** **RE-PASTE RULE (final): after re-pasting ANY of phase 89, 94, 96, 97, 98, 103, 105, 109, 110 or 111, paste 112, 113, 114, 115, 116, 117, 118, 121 again (in that order).** For 94, 97, 98, 103, 105, 109, 110, 111 that is enough; phase89 and phase96 put back older bodies that 98 / 103 / 105 / 109 / 110 / 111 own, so after them paste the FULL repair tail 89, 103, 105, 109, 110, 111, 112..118, 121 (it is safe after any of them). Where the old text of a function is put back by an earlier phase and a later body guard refuses it (phase98 / phase103 on `_acct_docs` with bos113, phase109 on `production_post` with bos116), the repair is: phase89 first (puts the older text back), then 103, 105, 109, 110, 111, then 112..118. Proof: `supabase/phase119_test.sql` (a test file only, no phase119.sql exists; md5 of every public function body after the re-paste = fresh canonical build). Older chain rule still holds: 98 after 89 / 94 / 96 / 97; 103 then 105 then 109 then 111.
| 47 | phase118.sql | 72..103 | guard inside (functions of 72 / 78 / 80 / 82 / 85 / 88 and the tables stock_ledger, stock_transfers, card_settlements85). Step B4: three READ-ONLY reconciliation reports (`stock_recon_statement`, `stock_sales_unmatched`, `factory_branch_statement`, `net_profit_report`) + `recon_export_log118`; grants `view_stock_recon`, `view_branch_statement`, `view_net_profit`; rules `profit_variable_heads`, `branch_stmt_ageing_hours` (+ 2 advisor rows). Tag bos118; no existing function is re-created. See section N |
| 48 | phase120.sql | 118 (and 72..103) | guard inside (the phase118 functions and `_base_qty`; a body guard refuses an unknown bosNN tag on the three functions it rewrites). Step C4 (performance of the phase112..118 reports): `CREATE OR REPLACE` of `_rc118_buckets`, `_rc118_gap`, `stock_sales_unmatched` only (same signature, same output, tag bos120 next to bos118); no index (two candidates measured, no gain). stock_recon_statement 2.1 s -> 0.5 s and factory_branch_statement 2.3 s -> 0.6 s for a month on the owner-size scratch DB. Re-paste rule: after a re-paste of phase118 paste phase120 again. Tests: `supabase/phase120_test.sql`, `tests/sql/perf/equality120.sh`. Placed after phase118 and before phase121 (integration C4: phase121 does not touch the three functions; verified with phase121_test on the merged chain). Re-paste of phase118 puts the older bodies back: paste phase120 again. |
| 49 | phase121.sql | 72..118 | guard inside. Security review fixes of 112..118 (marker `sec121`, deliberately not a bosNN tag): `customer_dues_net113` revoked from public / anon; `pool_set` and `_pool_gl_after_bill117` start the GL sync only for owner / accountant; `cost_wait_supply96` moves the item average only for owner / recipe manager / accountant (else `needs_manager`); `sale_return` sold quantity over all lines in base units; `bank_stmt_post113` duplicate lookup first; `stock_return_transfer` locks the original; `production_recost116` checks rights before the row lock. Exact-text patches of the live bodies, paste twice = no change, nothing changes at the defaults. Test: `supabase/phase121_test.sql` |
| 50 | phase122.sql | base schema (no phase 72..121 function is touched) | guard inside. GROUP ERP STAGE B1 (marker `org122`, not a bosNN tag; changes NO existing function): tables `org_units`, `legal_entities`, `business_templates` (RLS, audit, no hard delete, no browser write), nullable `locations.org_unit_id`, seed of one group + one legal entity + one business for the sweets business with the existing locations mapped (fill-null only), rule `org_scope_on` (default OFF, read by nothing), grant `org_manage`, functions `org_tree`, `org_unit_scope`, `org_unit_save`, `org_unit_deactivate`. Test: `phase122_test`; proof of no behaviour change: `tests/sql/b1_before_after.sh`. Plan: `docs/GROUP_ERP_STAGE_A.md` sections 10-11. |
| 51 | phase125.sql | 122 (items, org_units; not 123/124) | guard inside. VARIANT ITEM MODEL (marker `var125`, changes NO existing function): nullable `items.org_unit_id` (filled with the sweets business, fill-null only; a BEFORE INSERT trigger fills new items) + `style_id`, `variant_key`, `variant_opts`; NEW unique index `(org_unit_id, code)` while the global `items.code` unique constraint stays; tables `option_sets`, `option_values`, `item_styles`, `style_axes`, `price_lists`, `price_list_items` (RLS scoped to the caller's business, audit, no hard delete, no browser write); functions `option_set_save`, `option_values_save`, `style_save`, `variants_generate` (idempotent, EAN-13 per variant), `variants_overview`, `variant_matrix`, `my_businesses125`, `price_list_save`, `price_list_items_set`, `price_for125`; rule `variants_on` (switch, default OFF), grant `variants_manage`. `items_read` is replaced only while it is still the original any-active-user policy and only hides other businesses' items while the switch is ON. |
| 52 | phase126.sql | 125 | guard inside. LARGE CATALOGUE READINESS (marker `var126`, changes NO existing function): `items.brand`, btree prefix indexes and (when pg_trgm exists) trigram GIN indexes on the item names, `items_search(org, q, filters, limit, offset)` (server-side search + paging + summary counts, scoped by the caller's businesses, never returns cost), `items_search_info126()`. |


(The number 89 is out of sequence on purpose; it is pasted after 90 and 91. `tests/sql/final_build.sh` builds exactly this order.)

## C. Why phase89 comes after 90 and 91

Each phase was written on its own branch, from the function text that existed there, so a later number could silently put an older body back.
Found by comparing `pg_get_functiondef` after every phase on a fresh build: phase83 dropped the phase82 `unit_conv_required` rule from `_sale_stock_out`,
phase85 dropped the phase80 free-cost rule from `_acct_docs`, phase88 dropped it from `_cogs_lines72`. phase89 re-creates those three as merges and re-asserts
the final body of every other function that two or more phases re-create (28 more), so the result does not depend on who was pasted when.
After phase89 the only functions whose text differs from "numeric order without 89" are those three.

## D. Rules for the next phase (92, 93, ...)

1. Paste it after phase94 (or, if it re-creates a function of phase94, merge into that text), then compare `pg_get_functiondef` before/after for every function it re-creates; if it re-creates one that appears in phase89, merge the new lines into the phase89 text (or paste a new phase89 version) and keep every `bosNN` tag.
2. Run `supabase/phase89_test.sql` (T0 lists 50 function/tag pairs) and `supabase/phase94_test.sql` after the new phase; a lost tag shows up as a FAIL.
3. Never edit an old phase file; add a `phaseNNb_test.sql` copy when an old assertion becomes false by design (done for 72b, 73b, 76b).

## E. Step INT3 (phase96/97/98) - what the per-phase diff showed

Method: fresh build to phase71, then every phase in the order above, `md5(pg_get_functiondef)` + `bosNN` tags of all 1212 public functions stored after each phase. Tags lost by a later phase in this order: only `_acct_docs(date)` (bos96 lost by phase97). All earlier losses (bos72/73/80/82 by phases 73, 74, 78, 83, 85, 88) are repaired by phase79 / phase89 as before. phase94 loses nothing. Phase98 merges the one remaining loss.
`supabase/phase89_test.sql` P2 ("second paste identical") is false by design once phase96/97 exist (phase89 alone is not the end of the chain); use `supabase/phase89c_test.sql` (P2 = phase89 then phase98 = identical, and P2a: phase89 alone changes exactly `_acct_docs` and `inventory_vs_gl`). Do not edit phase89_test.sql.

## F. Rules for the next phase (99, ...)

Same as D, but the last file is now phase98: a phase that re-creates `_acct_docs`, `_acct_inv_split72`, `_acct_stock_moves85`, `_pvar85` or `inventory_vs_gl` must merge into the phase98 text (new phase98 version) and keep every `bosNN` tag; run phase89c_test, phase94_test, phase96_test, phase97_test and phase98_test.


## G. Rules for the next phase (119, ...) - phase111 is the last file that re-creates older functions; phase118 follows it

Same as D and F: a phase that re-creates a function listed in rows 27-40 must merge into the existing text (a new version of the phase that owns the function, or a new phase111 version) and keep every `bosNN` tag. Check with `bash tests/sql/tag_loss_check.sh` (fresh build in the owner order, `md5(pg_get_functiondef)` + bosNN tags after every phase, reports every lost tag). Run phase89c_test, phase89d_test, phase94_test, phase96..99_test, phase103b_test, phase105_test, phase109_test, phase111_test.
Tests that assert a state later phases change by design have `b` / `c` / `d` copies (phase103b, phase103c, phase89f, phase89g, phase98c, phase46b ...); old tests are never edited. Build: `bash tests/sql/final_build.sh <db>` (order from tests/sql/paste_order.env).

## H. Live status (not a table of files - see section B for the order)

- Installed on the owner's live database: phase72 .. phase103 (all 32 new files, each once, in the order of rows 1-32). Checked with `python3 tools/check_paste_order.py`.
- Pending, to paste in this order: phase104, phase105, phase106, phase107, phase108, phase109, phase110, phase111, phase118.
- Next free number after the pending ones: phase112.

## I. phase106 (backup / restore-drill coverage)

`supabase/phase106.sql` goes after phase105; guard inside (72..103). Re-creates only `_backup_tables()` (latest body = phase70, one change: `token_a`/`token_b` are not secrets) and adds `backup_coverage106()`. Independent of phase104 / 105. Audit: docs/backend/BACKUP_COVERAGE.md. Test: `supabase/phase106_test.sql`.
phase106 makes `phase46_test` F13 false by design (perm_conflict rows carry `token_a` / `token_b` keys): `supabase/phase46b_test.sql` is the copy with F13 allowing them; tests/sql/baseline_fails.txt: phase46 1 known fail, phase46b 0.

## J. phase105 (security 2) - notes

phase103 can still be re-pasted (the one line phase105 changes in `customer_directory` carries the marker `sec2-L6`, not a bosNN tag), but it puts back its own older text of `_inb_mask_phones103`, `_cust_pii103` and `customer_directory`: **after a re-paste of phase89 / 94 / 96 / 97 / 98 / 103 paste phase103 and then phase105 (and 109, 111).**
Tests: phase99_test, phase105_test, `tests/sql/p105_conc.sh <db built through 103>` (the unmask race: expects BEFORE 2, AFTER 1). `phase103_test.sql`, `phase89e_test.sql` and `phase98b_test.sql` end with a paste of phase103 and expect it to repair; once phase105 is on top that is false by design, so use `phase103b_test.sql`, `phase89f_test.sql` and `phase98c_test.sql`.

## K. phase109 (concurrency fixes) and phase111 (merge)

`supabase/phase109.sql` goes after phase108. Guard inside (72..103). Its body guard raises if a function it re-creates carries a tag it does not know; INT4 made it know bos105 / bos111 on `_bp_pay99` and skip that one function when bos105 is present. `supabase/phase111.sql` then creates the merged `_bp_pay99`. Tests: `supabase/phase109_test.sql` , `supabase/phase111_test.sql`; parallel proof: `bash tests/sql/concurrency/verify_fixes.sh` (before = NO109 build, after = with phase109).

## L. Step INT4 - what the per-phase diff showed

Fresh build to phase103 (owner order), then 104, 105, 106, 107, 108, 109 with `md5(pg_get_functiondef)` + bosNN tags of all public functions stored after each phase (`tests/sql/tag_loss_check.sh`). Result: phase104, 106 (only `_backup_tables`), 107, 108 touch no function of another phase; phase105 and phase109 both re-create `_bp_pay99` - phase109 as shipped RAISED on it (body guard) and, without the guard, would have erased the bos105 L4 line. After INT4: no bosNN tag lost between the 103 baseline and the final build. Details: docs/briefs_p2p3/step_INT4_REPORT.md.
## M. phase110 (performance)

**phase110**: 8 indexes FIRST, then six function patches (`_cogs_lines72`, `_item_cost_eff88`, `_rcs88`, `rpt_agg_sql`, `inbox_list`, `_acct_stock_moves85`, marker perf110); results identical to before. Report: docs/briefs_p2p3/step_Perf_REPORT.md. Needs 72..103.

phase110 goes after phase109 (or after phase108 while 105 / 109 are not merged). It touches no function of phase104..109 (checked against the phase105 and phase109 drafts: neither re-creates one of its six functions). **Run it at a quiet time**: every index build blocks writes to its table for a moment (about 1-2 s per million stock_ledger rows, 2.5 s per million audit_log rows). The file stops, before the patches, if one of the six functions carries a `bosNN` tag it does not know; a later phase that re-creates one of the six must merge into the phase110 text (rule G applies, with phase110 as the owner of these six). **Re-paste rule**: a re-paste of phase88 / phase89 / phase103 puts the older text of `_rcs88`, `_cogs_lines72`, `inbox_list`, `_acct_stock_moves85` back (results identical, only slow): paste phase110 again after it. `inbox_list` and `_acct_stock_moves85` carry the marker `perf110`, not a bosNN tag, so phase103's body guard still accepts them. Old assertions that are false by design with phase110 in the chain (phase89e P2 / P2a, phase103 T9) are copied to `phase89f_test.sql` / `phase103b_test.sql` (baseline_fails.txt). Test: `supabase/phase110_test.sql`; equality / budget: `tests/sql/perf/README.md`.

## N. phases 112..118 (audit-fix batches 1-4)

All seven files go after phase111 in numeric order (112, 113, 114, 115, 116, 117, 118). Every behaviour change is behind a rule whose default keeps today's behaviour; nothing is switched on by the files. The one re-paste rule that covers all of them is in the Invariant above: after re-pasting any of 89, 94, 96, 97, 98, 103, 105, 109, 110, 111 paste 112..118 again.

### N1. phase112 / phase113 (batch 1: profit and books truth)

Sources: docs/audit2/A3_real_profit.md and A4_cash_accounting_reconciliation.md. Both files re-create functions of earlier phases from their LATEST body (read in canonical order, every older bosNN tag kept, new lines tagged bos112 / bos113) and refuse to overwrite a body that carries a tag they do not know. **Re-paste rule**: pasting phase72 / 78 / 85 / 88 / 89 / 98 / 103 / 105 again puts the older text of `_c78_rows`, `_r3q_l3_shop_pnl`, `biz_items`, `_acct_docs`, `acct_post_pending`, `_daybook_lines`, `customer_dues`, `collect_payment`, `lock_check` back: paste phase112 and phase113 again after it. The body guards of phase98 / phase103 refuse to overwrite `_acct_docs` once it carries bos113 (by design): after a re-paste of an earlier phase the repair is **phase89 first** (puts the older text of 11 functions back), then 103, 105, 109, 110, 111, 112, 113. `customer_dues` is NOT re-created by phase113 (phase105 owns it, its guard would refuse a newer tag); the netted list is the new `customer_dues_net113`, which the app calls when the rule `dues_net_advance` is on. Old tests that assert "identical bodies after a re-paste" are false by design with 112 / 113 on top (tests/sql/baseline_fails.txt): `phase89h_test`, `phase98d_test`, `phase103d_test` are their replacements. Every new behaviour is behind a rule whose default keeps today's behaviour; the setup advisor (rows with phase 112 / 113) recommends the values. Skipped on purpose: see the batch-1 report (partner base, report builder item_sales, factory labour double count, opening-balance link of day book and journal).

### N2. phase114 / phase115 (batch 2: stock safety)

Both go after phase111 (any order between them). Every behaviour change is a rules switch, default OFF = today's behaviour; nothing is switched on by the files (the setup advisor shows recommended values, the owner applies them). They change live function bodies by an exact-text insert into the CURRENT body (`_b2_patch114` / `_b2_patch115`, dropped at the end of each file): paste twice = no change, every older bosNN tag stays, and a body that no longer contains the expected line stops the file (merge by hand). **Re-paste rule:** if phase89 / 94 / 96 / 97 / 98 / 103 / 110 (they re-create `_sale_stock_out`, `_acct_docs`, `_acct_stock_moves85`, `sale_return`, `stock_count_adjust`) is pasted again, paste phase114 and phase115 again after it. Tests: `phase114_test.sql`, `phase115_test.sql`; suites that re-paste an older phase and assert "no body changed" are false by design with 114/115 in the chain: copies phase89h, phase94b, phase98d, phase98e, phase103d, phase110b paste 114/115 again (baseline_fails.txt). Concurrency: `tests/sql/concurrency/s15.sh`.

### N3. phase116 / phase117 (batch 3: manufacturing cost)

`supabase/phase116.sql` and `supabase/phase117.sql` go after phase111 (rows 41-42; the numbers 112-115 and 118-121 belong to other batches and are merged by the integrator - keep these two numbers). Every behaviour is behind a rules switch whose default is today's behaviour; the setup advisor has a row for each. Report: `docs/audit2/B3_REPORT.md`. Tests: `phase116_test`, `phase117_test`.
**Re-paste rule**: a re-paste of phase19 / 73 / 74 / 79 / 96 / 109 (they re-create `production_post`, `_conv_cost`, `cost_wait_supply96` ...) puts the older body back: paste phase116 and phase117 again after it. Both files stop with a message if a function they re-create carries a bosNN tag they do not know (a later phase changed it: merge that change into the phase116 / 117 text first).

### N4. phase118 (batch 4: reconciliation reports)

`supabase/phase118.sql` goes after phase111 (it needs only 72..103 and re-creates nothing, so it is also safe right after phase103). Guard inside. Everything is read-only: the four report functions are `stable`, the only write is the audit row of `recon_export_log118`. Grants: `view_stock_recon` (stock statement + sales lines not matched in the stock ledger), `view_branch_statement` (factory-to-branch statement), `view_net_profit` (net profit per branch and product; also needs `biz_cost_ok()`). Cost keys of the two stock statements appear only for `biz_cost_ok()` holders. Test: `supabase/phase118_test.sql` (A3 hand numbers + A5 supply moves; `bash tests/sql/run_all_sql.sh phase118`). Web: `web/recon118.js`, routes `#/stockrecon`, `#/branchstmt`, `#/netprofit`.

### N5. phase121 (review fixes of 112..118)

See the row 49 above. `sec121` is a plain marker, not a bosNN tag, so the body guards of 98 / 103 / 109 / 114 / 116 / 117 still accept the bodies. Re-paste of 112..118 puts the unpatched text back: paste phase121 again after it.

### N6. phase122 (Group ERP B1: organization layer)

See row 50. It re-creates no existing function, so there is no re-paste rule and no tag can be lost. Paste twice = no change (existing locations are mapped only up to the highest location id that existed at the first paste, fill-null only). Nothing reads `org_scope_on` yet.

### N7. phase125 and phase126 (variants, per-business items, price lists, large-catalogue search)

See rows 51-52. Neither re-creates an existing function, so there is no re-paste rule and no tag can be lost. Paste twice = no change. phase125 does not need phase123/124; phase126 needs phase125. Both are inert until the owner turns `variants_on` on (phase126 adds only read functions and indexes). Plan to relax the global `items.code` uniqueness later: docs/regs/variants125.md.
