# Changelog: phases 72 to 103

One section per phase, newest first. Facts come only from `docs/briefs_p2p3/*_REPORT.md`, `docs/PASTE_ORDER.md` and the headers of `supabase/phaseNN.sql`. Where a fact was not stated there, it is marked `unknown`.

## Reserved: phases 104 to 108 (in progress)

Not built on this branch. Numbers are reserved; no files or behaviour are described here yet.

---

## Phase 103: Step E2E (bos103)

- Fixes defects D-1 to D-8 found by an independent end-to-end run.
- D-1: a production run whose ingredients are all free-cost items is a known cost 0 and is no longer stuck as `cost_missing`. Nothing to book posts nothing.
- D-2: direct production-in without a recipe appears in the cost-waiting list. It posts once the cost is known, only if the new switch `acct_manual_prod_in103` is on.
- D-3 to D-8: `opening_stock_apply96` may run once more for uncovered rows (no double count); `recipe_cost` treats a free-cost ingredient as cost 0; new flow check `flw_grn_double103`; `inventory_vs_gl` no longer counts GRN rows covered by a bill; `inbox_pii_mode` masks phone numbers typed in free text; `customer_directory` and `find_customer` follow `inbox_pii_mode`.
- Re-creates 20 functions from their latest bodies (tag bos103). Adds 3 internal helpers, 1 switch, 1 advisor check row.
- **Default:** `acct_manual_prod_in103` OFF (as before). The other fixes add no new switch.
- **Source files:** `supabase/phase103.sql` (goes last), `supabase/phase103_test.sql`, `supabase/phase89e_test.sql`, `supabase/phase98b_test.sql`, `tests/sql/e2e/`, `tests/sql/baseline_fails.txt`, `docs/briefs_p2p3/step_E2E_REPORT.md`.
- **Test result:** `phase103_test` 68 pass / 0 fail; `phase89e_test` 65 / 0; `phase98b_test` 27 / 0; `phase100` 80 / 0. E2E scripts: 195 PASS / 8 FAIL before the fix, 205 PASS / 0 FAIL after (recommended values; defaults 206 / 0). SQL suites: 80 suites equal the baseline, total 6759 pass, 31 fail (baseline 31).

---

## Phase 102: Step Img (item photos on cards and pickers, bos102)

- Adds three rules: `item_images_mode` (off, pos_only, everywhere), `item_images_thumb_only` (on or off), `item_images_cache_hours` (owner-typed number 1 to 720, blank = this session only).
- Adds 3 advisor rows in `setup_rec_defs81`: `item_images_mode` recommends pos_only, thumb_only recommends on, cache hours has no value.
- New RPC `items_first_image(item_ids uuid[])` returns the first photo path per item. SECURITY INVOKER, authenticated only, max 500 ids, no cost, price or stock column. The brief said int[]; the report uses uuid because `items.id` is uuid.
- New web decorator `web/itemimg.js` adds photos to item cards. With mode off it adds nothing to the DOM.
- Re-creates no existing function.
- **Default:** `item_images_mode` off (today's behaviour).
- **Note:** `docs/PASTE_ORDER.md` row 31 says this file is built on branch `fix/phase-Img` and is not in the `fix/phase-INT3` order (it goes between 101 and 103). The file is present in `supabase/` in this worktree.
- **Source files:** `supabase/phase102.sql`, `supabase/phase102_test.sql`, `web/itemimg.js`, `web/items2.js`, `web/ia.js`, `tests/web/itemimg_test.js`, `tests/web/itemimg_static_test.js`, `docs/briefs_p2p3/step_Img_REPORT.md`.
- **Test result:** `phase102_test` 13 pass / 0 fail. `itemimg_test` 46 / 0. `itemimg_static_test` 17 / 0. All 77 SQL suites with and without phase102: 6537 pass / 29 fail with it, 6524 / 36 without (report counts).

---

## Phase 101: Step Rec (setup advisor covers every rule, bos101)

- Adds 43 rows to `setup_rec_defs81` for the rules and switches of phases 82 to 97 (48 keys found; 43 new rows, the 38 older rows unchanged, per the report).
- Each row gives a recommended value and a reason in bn, mix and en, where a value is recommended. Owner-typed numbers and hardware or outside-setup items get status `info`.
- Backlog-posting accounting switches are apply-ready only when the accounting basics are clean.
- No function is created or re-created; `setup_recommendations()` and `setup_recommend_apply()` are reused.
- Guard refuses if phases 72 to 97 or phase98 are missing.
- **Default:** no rule default changed. The advisor only shows recommendations; nothing is applied by itself.
- **Source files:** `supabase/phase101.sql`, `supabase/phase101_test.sql`, `tests/sql/rec_keys.py`, `tests/sql/phase101_run.sh`, `docs/briefs_p2p3/step_Rec_REPORT.md`.
- **Test result:** `phase101_test` 57 pass / 0 fail (31 / 26 on a build without phase101). All 73 SQL suites give identical result lines with and without it. `setupadvisor_test.js` 22 / 0. `lang_en_test.js` 87 English strings, 0 Bangla.

---

## Phase 100: Step Cat (category and sub-category master, bos100)

- New table `item_categories`: a tree where parent null = category and parent set = sub-category. `code` is the text value kept in `items.category` and `items.sub_category`.
- `items` gets `category_id` and `sub_category_id`, kept in sync by a trigger.
- RPCs: `category_list`, `category_save`, `category_rename`, `category_merge`, `category_move`, `category_reorder`, `item_set_category` (and `_bulk`), `items_missing_category`, `biz_items_by_category`, `stock_valuation_by_category`.
- New screen `#/categories` in `web/catpick.js`; category pickers added to existing screens (tagged bos100).
- **Default:** rule `category_required_on_item` off (warn | required also available; the advisor recommends warn).
- **Source files:** `supabase/phase100.sql`, `supabase/phase100_test.sql`, `web/catpick.js`, `tests/web/catpick_test.js`, `tests/web/catpick_pw_test.js`, `web/pos.js`, `web/stock2.js`, `web/bulkitems.js`, `web/scan.js`, `web/itemmaster.js`, `web/recipes.js`, `docs/briefs_p2p3/step_Cat_REPORT.md`.
- **Test result:** `phase100_test` 80 pass / 0 fail. `catpick_test` 66 / 0. `catpick_pw_test` 77 assertions, 0 failures, no page errors. Regression of the other SQL suites: see the report (summary `unknown` here).

---

## Phase 99: Step Opt (two owner options, bos99)

- Option 1, bill payment: rules `cost_bill_creates_payment` and `purchase_bill_creates_payment` (off, ask, auto_cash, auto_bank, auto_by_supplier_default); `bill_void_payment_mode` (void or keep_credit); `bill_pay_auto_credit_ok` switch.
- Option 1 hooks are triggers `cs_bills_pay99` and `purchase_bills_pay99`. A failed auto-payment never blocks the bill; it leaves a yellow flag.
- Option 2, inbox masking: `inbox_pii_mode` masking. Re-creates `inbox_list`, `inbox_get`, `online_orders_list`, `online_order_get`, `telegram_chat_info` (tag bos99).
- New pages `#/optionsx`, `#/billpay`, `#/inboxpii`; `payment_recommendation()` for the recommendation cards.
- **Default:** all options off (today's behaviour). The system only shows a recommendation.
- **Source files:** `supabase/phase99.sql`, `supabase/phase99_test.sql`, `supabase/phase89d_test.sql`, `web/optionsx.js`, `tests/web/optionsx_test.js`, `tests/web/landed_b_test.js`, `tests/sql/opt_build.sh`, `docs/briefs_p2p3/step_Opt_REPORT.md`.
- **Test result:** `phase99_test` 148 pass / 0 fail; `optionsx_test` 409 / 0. The other 73 SQL suites give identical counts with and without phase99.

---

## Phase 98: Step INT3 (merge of phases 96 and 97, bos98)

- Re-creates `_acct_docs(date)` as a three-way merge: phase89 body + all bos96 lines + both bos97 blocks. One comment line tagged bos98.
- Re-asserts four phase96 functions byte for byte: `_acct_inv_split72`, `_acct_stock_moves85`, `_pvar85`, `inventory_vs_gl`.
- Body guard stops if a live body carries a tag this file does not know. Guard needs phases 72 to 97 (24 marker objects).
- No table, rule, data, privilege or trigger is changed.
- **Default:** no new switch and no default changed.
- **Source files:** `supabase/phase98.sql`, `supabase/phase98_test.sql`, `supabase/phase89c_test.sql`, `docs/PASTE_ORDER.md`, `tests/sql/final_build.sh`, `docs/briefs_p2p3/step_INT3_REPORT.md`.
- **Test result:** `phase98_test` 27 pass / 0 fail. `phase89c_test` 65 / 0. The old `phase89_test` is 63 / 1 on the final build (its P2 check is false by design).

---

## Phase 97: Step Land (landed cost, audit a1-F9, bos97)

- Charge types: freight, duty, insurance, clearing, loading, unloading, bank, packaging, non-recoverable and recoverable tax, delivery, FX difference, and owner-added types (`landed_charge_type_save`).
- Lifecycle draft, approved, posted, void. Allocation by value, quantity, weight, volume, manual or equal.
- Late-arrival handling: `split_remaining_and_cogs` (default), `post_to_remaining_stock`, `variance_account`.
- Stock effect as `cost_adjust` ledger pairs (ref_type `landed`). Journal entries `landed_cost` and `landed_cost_void`; new mapping keys `vat_input`, `landed_payable`, `landed_variance`.
- RPCs: `landed_preview`, `landed_save`, `landed_approve`, `landed_post`, `landed_void`, `landed_get`, `landed_list`, `landed_reminders`, `landed_return_info`, and others. Re-creates only `_acct_docs` (tag bos97).
- **Default:** `landed_cost_mode` off, so an item costs its invoice price as today. `landed_reminder_on` off.
- **Source files:** `supabase/phase97.sql`, `supabase/phase97_test.sql`, `web/landed.js`, `tests/web/landed_test.js`, `tests/web/landed_pw_test.js`, `docs/briefs_p2p3/step_Land_REPORT.md`.
- **Test result:** `phase97_test` 155 pass / 0 fail (twice pasted). `landed_test` 18 / 0. `landed_pw_test` 65 assertions, 0 failures. The 67 older suites: 5762 pass / 34 fail, all known baseline.

---

## Phase 96: Step D23 (opening stock and cost waiting, bos96)

- Opening stock helper (D2): four methods `owner_capital`, `existing_account`, `skip`, `difference`. Functions `opening_stock_check96`, `opening_stock_preview96`, `opening_stock_apply96` (owner only, idempotent by client id), `opening_stock_recommend96`.
- Cost waiting (D3): `cost_wait_list96`, `cost_wait_preview96`, `cost_wait_recommend96`, `cost_wait_supply96` (append-only `ledger_cost_supply96`), `cost_wait_alert96`.
- Rule `acct_cost_wait_alert_days`: the owner types the number; blank = no alert.
- Re-creates `_acct_docs`, `_acct_inv_split72`, `_acct_stock_moves85`, `_pvar85`, `inventory_vs_gl` (tag bos96).
- **Default:** nothing is posted automatically; the owner chooses the method. No built-in alert number (blank = no alert).
- **Source files:** `supabase/phase96.sql`, `supabase/phase96_test.sql`, `tests/sql/gen_phase96.py`, `tests/sql/phase96_parts/`, `web/books96.js`, `tests/web/books96_test.js`, `docs/briefs_p2p3/step_D23_REPORT.md`.
- **Test result:** `phase96_test` 123 pass / 0 fail (17 / 51 without phase96). `books96_test` 356 checks, 0 failed. The 67 older suites are identical with and without phase96 (5763 pass / 21 fail on both, known baseline).

---

## Phase 95: Step Drw (cash drawer option, bos95)

- Rules (module pos): `cash_drawer_mode` (off, on_cash_sale, on_any_sale, manual_only); `cash_drawer_when` (before_payment, after_payment); `cash_drawer_method` (none, browser_print_pulse, web_serial, web_usb, bluetooth, kiosk_url); `cash_drawer_no_sale_requires_reason` (on).
- `kiosk_url` is a planned placeholder; the app says so.
- Grant `drawer_nosale` for opening the drawer with no sale. Table `drawer_events` is append-only (auto_open, no_sale_open, test_open, failed).
- Drawer not connected: a toast, the sale goes on, a `failed` event is logged.
- **Default:** `cash_drawer_mode` off. Nothing opens, nothing is logged, POS is untouched.
- **Source files:** `supabase/phase95.sql`, `supabase/phase95_test.sql`, `web/cashdrawer.js`, `tests/web/cashdrawer_test.js`, `web/pos.js`, `web/ia.js`, `docs/briefs_p2p3/step_Drw_REPORT.md`.
- **Test result:** `phase95_test` 48 pass / 0 fail. `cashdrawer_test` 97 / 0. Old web suites `tplpicker_test` 52 / 0, `invoiceview_test` 65 / 0, `posfail_test` 23 / 0.

---

## Phase 94: Step Sec (security review fixes, bos94)

- H1: the photo and path of a purchase bill follow the cost right. `_scan_photo_ok` and `scan_get` re-created.
- M1: `pii_exposure_report94()` for the owner. M2: optional proof secrets (hash only) for scopes `meta` and `web_form`. M3: `intake_purge(days)` and optional rate limits. M4: `scan_ai_gate94` caps paid AI calls. M5: rule `offline_sale_max_age`. M6: EXECUTE revoked from anon and public on re-created functions; `anon_exec_audit94()` lists what anon can still run.
- Re-creates 9 functions (tag bos94), including `inbound_message_receive` and `web_order_submit`, each with one extra defaulted argument.
- Its 3 `bos94` lines in `_sale_stock_out` are also merged into `phase89.sql`.
- **Default:** every new switch and limit is OFF or empty (today's behaviour).
- **Source files:** `supabase/phase94.sql`, `supabase/phase94_test.sql`, `supabase/phase89.sql`, `tests/sql/final_build.sh`, `docs/PASTE_ORDER.md`, `docs/briefs_p2p3/step_Sec_REPORT.md`.
- **Test result:** `phase94_test` 80 pass / 0 fail on the final build (28 pass / 39 fail without phase94).

---

## Phase 93: Step Tpl (print and message templates, bos93)

- One table holds the template id chosen per document type, optionally per location. A location row beats the all-locations row (location_id null).
- `set_doc_template` (owner only). A null template clears the choice. Each change is written to `audit_log`.
- Templates live in the web app: 20 document types x 5 to 6 designs = 120 templates (per report).
- Guard needs only the base schema (`is_owner`, `is_active`, `audit_log`, `locations`).
- **Default:** no row = no choice = today's output, unchanged.
- **Source files:** `supabase/phase93.sql`, `supabase/phase93_test.sql` (named in the report), `web/tpl_registry.js`, `web/invoiceview.js`, `web/ia.js`, `tests/web/tpl_test.js`, `tests/web/tplpicker_test.js`, `docs/briefs_p2p3/step_Tpl_REPORT.md`.
- **Test result:** `phase93_test` 18 pass / 0 fail. `tpl_test` 2248 pass / 0 fail. `tplpicker_test` 52 checks.

---

## Phase 92: Step Inv (invoice on screen after a sale, bos92)

- Rule `pos_show_invoice_after_sale`: never, ask, always.
- Append-only table `invoice_shares`: one row each time an invoice is printed, emailed, SMSed, WhatsApped, shared, copied or downloaded.
- `invoice_data92(sale, client)` builds the invoice. No cost columns. Customer mobile only for owner, POS approve, `view_customer_mobile` holders, or the cashier of that sale.
- `invoice_share_log92` writes the share log.
- **Default:** `pos_show_invoice_after_sale` = never (today's behaviour).
- **Source files:** `supabase/phase92.sql`, `supabase/phase92_test.sql` (named in the report), `web/invoiceview.js`, `web/pos.js`, `web/ia.js`, `docs/briefs_p2p3/step_Inv_REPORT.md`.
- **Test result:** `phase92_test` 46 pass / 0 fail. `invoiceview_test` 65 / 0. `invoiceview_pw_test` 37 / 0.

---

## Phase 91: Step Vis (show, hide or lock per user, bos91)

- Tables `user_option_view` (per person) and `role_option_view` (role default; a user row wins). Modes `show`, `hide`, `locked`.
- Option keys `r:<route>` and `f:<form code>`, the same keys nav.js uses for favourites.
- RPCs `set_option_view`, `set_option_view_bulk`, `set_role_option_view`, `set_role_option_view_bulk` (owner only to set), `my_option_views()`, `option_views_for_user(user)`.
- Every real change writes one `audit_log` row (old, new, by whom).
- Web: `web/optviews.js`; drawer, Home, search and bottom bar honour the mode.
- **Default:** no row = `show`. Nobody's view changes.
- **Source files:** `supabase/phase91.sql`, `supabase/phase91_test.sql`, `web/optviews.js`, `tests/web/optviews_test.js`, `tests/web/optviews_ui_test.js`, `web/nav.js`, `web/ia.js`, `web/index.html`, `docs/briefs_p2p3/step_Vis_REPORT.md`.
- **Test result:** `phase91_test` 97 pass / 0 fail. `optviews_test` 58 / 0. `optviews_ui_test` all assertions pass.

---

## Phase 90: Step Scan (photo to draft to review to save, bos90)

- Tables `scan_jobs` (status uploaded, extracted, reviewed, confirmed, rejected) and `scan_events` (append-only trail).
- Functions `scan_create`, `scan_set_extracted`, `scan_review_save`, `scan_confirm`, `scan_reject`, `scan_get`, `scan_list`, `scan_match_items`, `scan_match_suppliers`.
- `scan_confirm` calls the existing save functions in one transaction. No auto-confirm exists.
- Grants `scan_upload` and `scan_confirm`. Private storage bucket `photos` with signed URLs only.
- Edge source `supabase/functions/scan-extract/index.ts` (source only, not deployed by this file).
- **Default:** `scan_enabled` OFF. `scan_engine` = manual.
- **Source files:** `supabase/phase90.sql`, `supabase/phase90_test.sql`, `supabase/functions/scan-extract/index.ts`, `web/scan.js`, `tests/web/scan_test.js`, `tests/web/scan_pw_test.js`, `docs/SCAN_SETUP.md`, `docs/briefs_p2p3/step_Scan_REPORT.md`.
- **Test result:** `phase90_test` 119 pass / 0 fail. `scan_test.js` 65 / 0. The 51 older suites are identical with and without phase90.

---

## Phase 89: Integration fix (final bodies, bos89)

- Re-creates the final body of every function that two or more phases re-create (phases 72 to 88, 90, 91). Examples named in the header: `_sale_stock_out`, `_acct_docs`, `_cogs_lines72`.
- Merges the three bos94 lines into `_sale_stock_out` so a repeated paste cannot undo them.
- Pasted after phases 90 and 91 (PASTE_ORDER row 20). Guard refuses if any of 72 to 88, 90, 91 is missing.
- No table, data, rule or privilege is changed.
- **Default:** no default changed.
- **Source files:** `supabase/phase89.sql`, `supabase/phase89_test.sql`, `tests/sql/final_build.sh`, `docs/PASTE_ORDER.md`, `docs/briefs_p2p3/step_INT2_G_REPORT.md`.
- **Test result:** `phase89_test` 64 pass / 0 fail on the final build (50 function and tag pairs).

---

## Phase 88: Step R (one cost source for every report, bos88)

- Rule `report_cost_source`: `ledger_then_item_costs` (default), `ledger_avg`, `item_costs`.
- `biz_items`, the report builder (cogs, gp, gp_pct via `rpt_agg_sql`) and `items_with_cost` now follow the rule.
- Journal COGS always comes from the stock ledger; `profit_source_check` shows report vs journal.
- Re-creates functions from their latest definitions (tag bos88). No table or data change.
- **Default:** `ledger_then_item_costs`. The main P&L numbers stay unchanged.
- **Source files:** `supabase/phase88.sql`, `supabase/phase88_test.sql`, `docs/briefs_p2p3/step_R_REPORT.md`.
- **Test result:** `phase88_test` 47 pass / 0 fail. The 52 older suites give identical fail lines with and without phase88.

---

## Phase 87: Step X (independent QA fixes, bos87)

- Owner can always approve `recipe_approve` and `cost_rule_approve`. Owner approval is logged as `self_approved` with a non-blocking suggestion `ask_another_approver`.
- `expiry_sale_guard` off, warn or refuse. `record_sale2` refuses a client_id used by another user (`client_id_taken`).
- `purchase_backdate_flag` off or warn. `ledger_problem_count()` for a badge.
- `production_double_issue_guard` off or warn; `production_recommendations()` for the owner.
- **Default:** all new rules OFF (today's behaviour).
- **Source files:** `supabase/phase87.sql`, `supabase/phase87_test.sql`, `supabase/phase21b_test.sql`, `supabase/phase22b_test.sql` (copies with expected changes), `docs/briefs_p2p3/step_X_REPORT.md`.
- **Test result:** `phase87_test` 53 pass / 0 fail. Two expected owner-decision changes in `phase73_test` (old file untouched). The 8 `phase22` fails come from phase84, not phase87.

---

## Phase 86: Step Tg (Telegram as a sales and message channel, bos86)

- `sales_channels.kind` accepts `telegram`.
- `telegram_message_receive()` writes into `inbound_messages`. Idempotent on (channel, update_id). No reply, no order, no AI call.
- Verification: only the SHA-256 of the secret token is stored (`telegram_secrets`, closed table). Constant-time comparison. A wrong token is logged as a rejected line with no body.
- `telegram_chat_link`, `telegram_chat_unlink`, `telegram_chat_info` link a chat to a customer or order.
- **Default:** `telegram_intake_on` OFF (also needs `inbox_on`).
- **Source files:** `supabase/phase86.sql`, `supabase/phase86_test.sql`, `supabase/functions/telegram-webhook/index.ts`, `web/inbox.js`, `tests/web/inbox_test.js`, `docs/TELEGRAM_SETUP.md`, `docs/briefs_p2p3/step_Tg_REPORT.md`.
- **Test result:** `phase86_test` 65 pass / 0 fail. `inbox_test.js` 47 / 0. Regression: `phase76` moved from 108 / 0 to 107 / 1 with phase86 (report).

---

## Phase 85: Step D (stock moves to the GL, manual-journal guard, autopost, card settlement, expense mode)

- Stock moves now post: one entry per stock-ledger row for count adjustment, opening stock, own-use issue, transfers, short receipt and purchase return (accounts 5110 to 5140; clearing 1230).
- Rule `acct_transfer_mode`: off, location_tagged, company_wide. Reversal rows are mirrored. Rows without a known cost wait as `cost_missing`.
- Manual-journal guard (reason codes), autopost scheduler, card settlement and expense payment mode, per the report title.
- **Default:** every new switch defaults to today's behaviour. With defaults, nothing new is posted and no report changes.
- **Source files:** `supabase/phase85.sql`, `supabase/phase85_test.sql`, `web/books85.js`, `tests/web/books85_test.js`, `docs/briefs_p2p3/step_D_REPORT.md`, `docs/briefs_p2p3/step_Dscr_REPORT.md`.
- **Test result:** `phase85_test` 85 pass / 0 fail (18 / 41 without phase85). `books85_test` 38 checks, 0 failed. Old suites identical with and without phase85.

---

## Phase 84: Step F (audit trail for the stock cache, batches, transfers, purchase lines, production void)

- `stock_balance`: no delete of a non-empty row; item and location are immutable; audit row for manual changes of qty and avg_cost.
- `stock_batches`: no delete; identity columns immutable; audit row for other changes.
- `stock_transfers`: no delete. `purchase_lines`: delete only on a draft; identity and amounts frozen on posted or void bills.
- `production_runs`: audit row on void. `stock_reconcile` re-created with audit lines.
- **Default:** no switch. These protections are always on (triggers).
- **Source files:** `supabase/phase84.sql`, `supabase/phase84_test.sql`, `docs/briefs_p2p3/step_F_REPORT.md`.
- **Test result:** `phase84_test` 64 pass / 0 fail. Two old fixtures (`phase21`, `phase22`) that delete `stock_balance` are refused by the new trigger (known effect, per report).

---

## Phase 83: Step Eb (form vs screen, expense double count, transit shortage, offline POS failed sales, bos83)

- `form_051_mode`: reference, post, refuse.
- `transit_short_mode`: keep_in_transit or loss (loss books reason `transit_loss`). `transit_open_hours` blank = no limit. Functions `transit_short_open`, `transit_short_resolve`, `transit_open_list`.
- Expense: `suggest_expense_link`, `expense_link_apply`, a dup_suspects branch for expense.
- Offline POS: `record_sale_offline`, `pos_replay_override` (manager override with the original client_id), `pos_failed_*` board table, `offline_soft_stock` switch.
- **Default:** `form_051_mode` = reference; `transit_short_mode` = keep_in_transit; `offline_soft_stock` = off.
- **Source files:** `supabase/phase83.sql`, `supabase/phase83_test.sql`, `web/posfail.js`, `tests/web/posfail_test.js`, `web/pos.js`, `docs/briefs_p2p3/step_Eb_REPORT.md`.
- **Test result:** `phase83_test` 76 pass / 0 fail. `posfail_test` 23 / 0. Output identical before and after across 35 older suites.

---

## Phase 82: Step Ea (stock-side guards, bos82)

- E1 `purchase_grn_guard` (off, skip, link); `grn_bill_link()`, `grn_pending_report()`.
- E2 `purchase_void_guard` (off, warn, refuse); `purchase_void_payments` (void or keep).
- E3 `unit_conv_required` (off, warn, refuse); `unit_unknown_items()`; item-editor trigger.
- E4 `neg_grant_log`; `production_negative_reason` (off, warn, required); `never_opened_negative_items()`.
- Re-creates `_post_purchase_p13`, `_void_purchase_p13`, `_sale_stock_out`, `stock_post`.
- **Default:** every new switch = today's behaviour. `guard_recommendations()` only recommends.
- **Source files:** `supabase/phase82.sql`, `supabase/phase82_test.sql`, `web/guards.js`, `tests/web/guards_test.js`, `web/pos.js`, `web/ia.js`, `docs/briefs_p2p3/step_Ea_REPORT.md`.
- **Test result:** `phase82_test` 57 pass / 0 fail on its own build. `guards_test` 35 / 0. Note: the integrated build showed 53 / 4 until phase89 restored the `_sale_stock_out` rule (per `step_INT2_G_REPORT.md`).

---

## Phase 81: Step S2 (recommendations and activation guide, bos81)

- `setup_recommendations()`: every rule of phases 72 to 79 with recommended value, reason (bn, mix, en) and status `ok`, `recommended`, `owner_chosen`, `info` or `not_installed`.
- Data-driven table `setup_rec_defs81`; later phases add rows by plain INSERT.
- `setup_recommend_apply()` (owner only): never overwrites an owner-chosen value unless `p_overwrite` is true and the code is named; skips rows not ready unless `p_ignore_ready`; append-only trail.
- `setup_readiness([topic])` and `setup_flow_check()`: counts only, no cost values.
- **Default:** advisory only. Nothing blocks; only the owner's tap applies a value.
- **Source files:** `supabase/phase81.sql`, `supabase/phase81_test.sql`, `web/setupadvisor.js`, `tests/web/setupadvisor_test.js`, `web/ia.js`, `web/index.html`, `docs/briefs_p2p3/step_S2_REPORT.md`.
- **Test result:** `phase81_test` 64 pass / 0 fail. `setupadvisor_test.js` 22 / 0. `lang_en_test` 0 Bangla found.

---

## Phase 80: Step S1 (follow-ups of the owner's delegated decisions, bos80)

- Free-cost item flag: table `item_cost_flags`, `item_cost_free_set()`, `cost_unknown_items(loc)`. A free-cost item is a known cost 0.
- Rule `partner_base_estimate` (warn or refuse): `partner_calculate` warns when part of COGS is an estimate.
- Rule `packaging_return_mode` (none, restore, wastage); table `sale_return_packaging80`.
- Dedicated intake bot: role `intake_bot`, form `ONLINE_INTAKE` (enter only), `intake_bot_create`, `intake_bot_check`, gate `_oo_gate80`.
- **Default:** nothing is marked free-cost; `partner_base_estimate` = warn; `packaging_return_mode` = none.
- **Source files:** `supabase/phase80.sql`, `supabase/phase80_test.sql`, `web/s1setup.js`, `tests/web/s1setup_test.js`, `web/ia.js`, `web/index.html`, `web/recipes.js`, `web/partners.js`, `tests/web/lang_en_test.js`, `docs/briefs_p2p3/step_S1_REPORT.md`.
- **Test result:** `phase80_test` 86 pass / 0 fail. `s1setup_test` 21 / 0. `lang_en_test` 69 strings, 0 Bangla.

---

## Phase 79: Integration of phases 72 to 78

- Final merged bodies of: `_acct_docs` (72 + 74), `production_post` 7-argument core (72 + 73 + 74), `recipe_cost` (73 + 74), `pool_set` (74 + 75), `_r3q_l1_pnl` and `_r3q_l3_shop_pnl` (72 + 78).
- The 6-argument `production_post` stays as a thin wrapper.
- Guard refuses if a phase is missing; `phase79_test.sql` proves every tag is present.
- **Default:** `production_requires_cost` = warn; `cost_attrib_in_pl` off; conversion mode off; `recipe_approval_required` off.
- **Source files:** `supabase/phase79.sql`, `supabase/phase79_test.sql`, `docs/briefs_p2p3/step_INT_REPORT.md`.
- **Test result:** `phase79` 77 pass / 0 fail (per `step_INT_REPORT.md`).

---

## Phase 78: Step C-2b (where showroom and admin cost belongs, approval separation hint, bos78)

- `location_cost_attribution`: per place (and optionally per cost type) the layer-3 cost shares go to showroom, main_centre or unallocated. Effective-dated.
- `cost_attrib_main`: which place is the main centre.
- `cost_share_reassign`: append-only trail with mandatory reason; owner override is flagged.
- `branch_cost_view(month, loc)` read-only; `grant_separation_hint(user, grant)` non-blocking suggestion.
- With `cost_attrib_in_pl` ON, `l1_pnl` and `l3_shop_pnl` get separate `cost_share` rows.
- **Default:** `cost_attrib_in_pl` OFF. No row = unallocated.
- **Source files:** `supabase/phase78.sql`, `supabase/phase78_test.sql`, `web/costattrib.js`, `tests/web/costattrib_test.js`, `web/delegation.js`, `docs/briefs_p2p3/step_C2b_REPORT.md`.
- **Test result:** `phase78_test` 101 pass / 0 fail. `costattrib_test` 59 / 0.

---

## Phase 77: Step E9 (existing online-order gaps, bos77)

- Pack-time stock warning in `online_order_status('packed')`; never blocks. `online_order_stock_check(id)` read-only preview. Soft reservation option.
- Keep the order's price (`online_keep_order_price`): `online_order_deliver` sends an override; a refused approval rolls back the delivery.
- Trigger on a voided sale of a delivered order: `online_order_flags` row (kind `sale_voided`), order trail line, red exception. The order status is not changed.
- Re-creates `online_order_status`, `online_order_deliver`, `online_orders_list`, `online_order_get`.
- **Default:** `online_pack_warn_on` OFF; `online_pack_reserve_on` OFF; `online_keep_order_price` OFF.
- **Source files:** `supabase/phase77.sql`, `supabase/phase77_test.sql`, `docs/briefs_p2p3/step_E9_REPORT.md`.
- **Test result:** `phase77_test` 26 pass / 0 fail.

---

## Phase 76: Step H (sales channels, message inbox, web order intake, Meta intake, bos76)

- Table `sales_channels`; `online_orders` gets `channel_id`, `external_ref`, `source`, `pay_mode`, `pay_ref`. `online_order_save2()` wraps the existing save.
- Table `inbound_messages` with trail; `inbox_list`, `inbox_get`, `inbox_set_status`, `inbox_board`. Customer phone and address masked, view audited.
- `web_order_submit()` for the web form: price and total computed by the server; only active sellable items; captcha hook and rate limit.
- `inbound_message_receive()` for Meta (Messenger, Instagram, WhatsApp): pull-in only, no reply. Messages never become orders by themselves; a draft needs a person to verify it.
- `order_dup_flags`: same customer, item and day across channels = flag only.
- **Default:** `inbox_autodraft_on` OFF.
- **Source files:** `supabase/phase76.sql`, `supabase/phase76_test.sql`, `web/inbox.js`, `tests/web/inbox_test.js`, `tools/edge/web-order.ts`, `tools/edge/meta-webhook.ts`, `docs/briefs_p2p3/step_H_REPORT.md`.
- **Test result:** `phase76_test` 108 pass / 0 fail. `inbox_test.js` 29 / 0 at the time (47 / 0 after phase86).

---

## Phase 75: Step C-2a (cost sources and allocation, bos75)

- One place to type a bill once. Separate source: one site pays, the whole bill goes to its destination. Shared source: an allocation rule splits it (sub-meter, fixed percent, floor area, headcount, output kg, whole bill to one place, or hand-typed amounts).
- Destinations: factory (layer 2, flows into `factory_cost_pools`), showroom or admin (layer 3, kept in the bill-share table for `branch_overhead()`).
- A bill is compared with approved 10-2 expense vouchers; a duplicate gives a yellow flag.
- Re-creates `pool_set` (tag bos75).
- **Default:** everything starts blank. `cost_rule_self_approve` OFF.
- **Source files:** `supabase/phase75.sql`, `supabase/phase75_test.sql`, `web/costsources.js`, `tests/web/costsources_test.js`, `docs/briefs_p2p3/step_C2a_REPORT.md`.
- **Test result:** `phase75_test` 76 pass / 0 fail. `costsources_test.js` 34 / 0.

---

## Phase 74: Step C (costing and overhead, bos74)

- Three cost layers: raw material (average cost; today's purchase price shown separately, never booked); conversion cost (labour, gas, electricity, factory rent, licence, repair, depreciation, other); showroom and admin (not in product cost).
- Per-location mode `location_cost_cfg.mode`: `off`, `recipe` (rates typed on the recipe) or `pool` (monthly factory cost pool over normal output, with smoothing `none`, `yearly12` or `avg_n`).
- `production_post` 7-argument core with `p_actual_yield`; 6-argument thin wrapper. Production journal Dr 1310 / Cr 1320, 1330, overhead absorbed.
- **Default:** location mode `off` (today's behaviour).
- **Source files:** `supabase/phase74.sql`, `supabase/phase74_test.sql`, `web/costing.js`, `tests/web/costing_test.js`, `docs/briefs_p2p3/step_C_REPORT.md`.
- **Test result:** `phase74_test` 96 pass / 0 fail. `phase73_test` re-run 98 / 0. `costing_test.js` 39 / 0.

---

## Phase 73: Step C-0 (recipe master: artisans, versions, approval, steps, recipe book, bos73)

- Artisan register: the name is stored only in `artisans.name`; everywhere else only the id `artisan-N` and the post.
- `recipes.artisan_id`; `recipe_versions` append-only history; approval fields (`approved_at`, `approved_by`); `recipe_approval_required` rule (off, warn, on).
- `recipe_steps` table (ordered method steps, minutes, people, equipment, QC note). `recipe_book` artisan-wise, no cost unless asked.
- Grant `recipe_view`; rule `artisan_self_view`. Re-creates `recipe_save`, `recipe_copy`, `recipe_cost`, `production_post` (approval gate only).
- **Default:** `recipe_approval_required` off; `recipe_self_approve` OFF; `artisan_self_view` OFF.
- **Source files:** `supabase/phase73.sql`, `supabase/phase73_test.sql`, `web/recipebook.js`, `tests/web/recipebook_test.js`, `docs/briefs_p2p3/step_C0_REPORT.md`.
- **Test result:** `phase73_test` 98 pass / 0 fail. `recipebook_test.js` 49 assertions, 0 failures.

---

## Phase 72: Phase B (audit fixes B1 to B4)

- B1 rounding: inventory lines of a sale, sale return, production and wastage are rounded per item type; the remainder goes to the largest part (`_acct_inv_split72`). Failed posts kept in `acct_post_errors72`.
- B2 one COGS source: `_cogs_lines72` used by `biz_daily`, `_p27_pl` and `_r3q_l2_margin`. New `biz_daily_src72`, `_p27_src72`, `profit_source_check(from, to, loc)`.
- B3 return margin: the return revenue is scaled by the sale's discount share.
- B4 unknown cost: revenue with no known cost is reported as `unknown_cost_rev`. Rule `production_requires_cost` (warn or refuse).
- **Default:** `production_requires_cost` = warn (today's behaviour).
- **Source files:** `supabase/phase72.sql`, `supabase/phase72_test.sql`, `web/accounts.js`, `tests/web/accounts_test.js`, `docs/briefs_p2p3/phaseB_REPORT.md`.
- **Test result:** `phase72_test` 71 pass / 0 fail on its own build. In the integration run of 72 to 79 it showed 70 / 1 (per `step_INT_REPORT.md`).
