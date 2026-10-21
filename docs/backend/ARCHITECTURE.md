# Architecture

All facts below come from `supabase/*.sql`, `web/*.js`, `docs/PASTE_ORDER.md` and `docs/briefs_p2p3/*_REPORT.md`. Marked **UNKNOWN** / **UNVERIFIED** where the repository cannot confirm it.

## 1. Layers

```
 phone browser (web/, plain JS, no build)
   BOS_APP (window.BOS_APP: sb, S, t, esc, toast, fail, shell, openSheet, H ...)   web/app.js
   BOS     (window.BOS: modules register on it: B.pos, B.drawer, B.tpl, B.ctl ...)
   service worker sw.js + swreg.js  (same-origin GET cache, network first)
        | supabase-js: sb.rpc(...)  /  sb.from(table).select(...)  /  sb.storage / sb.auth
        v
 Supabase
   Auth (staff logins, optional TOTP MFA)          Storage (private bucket 'photos')
   Postgres: tables + RLS (read-only for browser)  +  RPC = SECURITY DEFINER functions (all writes)
   Edge functions (SOURCE ONLY in this repo): scan-extract, telegram-webhook (supabase/functions/),
                                              meta-webhook, web-order, assistant-proxy (tools/edge/)
   pg_cron (optional, only if the extension exists): acct_scheduler_enable(cron)
 GitHub Actions (.github/workflows/backup.yml, notify.yml): nightly dump through a least-privilege "ops bot"
```

### 1.1 Database: Postgres + RLS + RPC
* **Tables are read-only for the browser.** `authenticated` gets `select` (sometimes only on a column list); inserts/updates happen only inside `SECURITY DEFINER` functions with `set search_path = public`. Example of the pattern: `supabase/phase10.sql` revokes all on `stock_ledger`, `stock_balance` and grants `select` on a **column list that leaves out `unit_cost` / `avg_cost`**.
* **Identity helpers** (`supabase/schema.sql`, `phase7.sql`, `phase8.sql`): `is_active()`, `is_owner()`, `can_do(form, 'view'|'enter'|'approve')`, `can_loc(location)`, `has_grant(code, loc)`. Details in SECURITY_MODEL.md.
* **Settings are data:** table `rules` (switches / numbers / choices / text; read with `rule_on`, `rule_num`, `rule_txt`), written only through `set_rule` (owner, validated, audited). Grants are defined in `grant_defs`, given by role in `rule_grants`, per person in `user_grants`.
* **Edge functions are optional and source-only.** Nothing in them runs until the owner (or a helper with a computer) deploys them and sets secrets (docs/SCAN_SETUP.md, docs/TELEGRAM_SETUP.md). None of them uses the `service_role` key; they act as the calling user or as a dedicated limited "intake bot" user.

### 1.2 Web app
* `web/index.html` loads ~37 scripts in a fixed order (the order is asserted by `tests/web/order_test.js`). `web/config.js` holds only the public project URL and publishable key.
* `web/app.js` creates the Supabase client and `window.BOS_APP`; feature files are IIFEs that read `const A = window.BOS_APP, B = window.BOS;`, register hash routes (`#/pos`, `#/stock`, ...) and `data-act` handlers on `A.H` (names are prefixed per module so they never collide).
* **Navigation has ONE registry:** `web/ia.js` (`BOS.IA`). Drawer, Home tiles, bottom bar, search, Control Center, breadcrumbs all read it (see the `bos-organise` rules in docs/IA_RULES.md). A new screen = one `rec(...)` line in `ia.js` + one `<script>` tag.
* Language: every user-visible string has bn / mix / en through `B.L(bn, mix, en)` or `web/i18n.js`.
* Reads of big lists use `BOS_ALL` (`web/pager.js`) because the server cuts lists at 1000 rows.
* Offline: POS and the form outbox queue work requests in `localStorage` (`bos_pos_queue_<uid>`, `bos_pos_failed_<uid>`) and re-send with the same `client_id`.

### 1.3 Storage
* Bucket `photos` (created in `supabase/phase3.sql`; forced `public = false` by `phase90.sql`). Scan photos live under `SCAN/<place id>/<uuid>.jpg`; policies `scan_photos_insert` / `scan_photos_read` call `_scan_photo_ok(name, 'enter'|'view')`. Only signed URLs exist.

### 1.4 Service worker
* `web/sw.js`: cache name `bos-sw-v1` (constant `VERSION`); only same-origin `GET`; never touches `/rest|auth|storage|realtime|functions/v1/`; **network first**, cache as fallback; navigations fall back to cached `index.html`. Old `bos-sw-*` caches are deleted on activate. Bump `VERSION` to drop the old cache.
* `web/swreg.js`: registers only on `https:`; off switch is rule `offline_cache_on` or `localStorage.bos_sw = 'off'`.

## 2. Module map per phase

Files: `supabase/phaseNN.sql` (+ `phaseNN_test.sql`). "tag" = the `bosNN` marker written on every changed line inside a re-created function (used to prove no later phase erased it). Phase numbers 29..39, 55..59, 63..69 have no file in this tree (**UNKNOWN** whether they were ever used). There is **no SQL for phases 104..105**; web-only steps use tags bos104, bos106, bos107, bos108 (see 2.5). A "phase 105" step is **UNKNOWN** in this tree.

### 2.1 Foundation (already on the live database; never paste again)
| Phase | Added (from the file header) |
|---|---|
| `schema.sql`, `phase2..4`, `ALL_NEW*.sql` | profiles, roles, role_form_perms, locations, user_locations, forms/entries, serials, exceptions, release requests, location settings, POS sales (`record_sale`/`record_sale2`), early reports (bundles of phases 5..28) |
| 8 | masters, settings (`rules`), grants (`has_grant`, `grant_defs`, `user_grants`), invoice templates, saved views, favourites, discount by amount or percent (`record_sale2` + 2 optional args) |
| 9 | report engine core (`report_run`, `rpt_*`) |
| 10 | **stock ledger**, purchases, supplier ledger, batches/expiry: `stock_ledger`, `stock_balance`, `stock_batches`, `stock_wastage`, `stock_transfers`, `purchase_bills/lines`, `supplier_payments`; `stock_post`, `post_purchase`, `stock_reconcile`, `stock_valuation` |
| 11 | `audit_log` append-only, immutable codes, no hard deletes, server-side PIN lockout |
| 12 | items / stock / purchase finishing work |
| 13 | day book, salary report, audited exports |
| 14 | item master (types, flags, retire), dictionary import |
| 15 | list add-rules (`list_defs`, `option_add`), "other" queue |
| 16 | locations lifecycle, Control Center counts, `get_limit` |
| 17 | rollout paper/parallel/app per form x place, locks/revisions/change requests, `client_id` for the form offline queue |
| 18 | server-side blind count, PIN signatures |
| 19 | recipes/BOM, packaging rule, `production_post`, `recipe_cost` |
| 20 | forms -> stock ledger link (`entry_post_ledger`, rule `forms_post_to_ledger`), discount approver, brand P&L |
| 21 | 12 more reports (`report_run2`) |
| 22 | bulk item editor (`items_bulk_apply`, dry run first) |
| 23 | wrong-number fixes: GRN vs purchase page (`grn_receipt_source`, `receipt_duplicates`), sales net of returns, `cash_moves`, `production_void` |
| 24 | report engine 3 (`report_defs3`, `_r3q_<key>`, `report_run3`) |
| 25, 26, 27 | reports on engine 3 (orders, RFM, lapsed; purchase/supplier reports; P&L, margin, shop P&L, owner sheet) |
| 28 | parallel-month comparison, paper books/print notes, "Needs you" list |

### 2.2 Modules 40..71
| Phase | Added |
|---|---|
| 40 | **Accounting:** `coa_accounts`, `journal_entries` + `journal_lines` (append-only, debit = credit), `acct_mappings`, `acct_post_pending`, reports (`acct_trial_balance`, `acct_income_statement`, `acct_balance_sheet`...), manual journal, opening balances. Rules `accounting_on` (OFF), `accounting_autopost`, `accounting_start_date` |
| 41 | employees, pay structure, deeds (agreements), documents |
| 42 | attendance, leave, automatic payroll, fingerprint device import |
| 43 | customers, tiers, tier discount, gifts, loyalty points |
| 44 | partnership / investment / profit-sharing deeds (owner only) |
| 45 | owner board (`owner_board_get/save`) |
| 46 | automatic backup + notifications (ops bot: `ops_account_set`, `_is_ops`) |
| 47 | read-only business assistant |
| 48..51 | **shadow engine** (section 3): paths, shadow links; payroll/expense (50); stock/production/owner money (51); read-only checks (49) |
| 52 | accounting sources for payroll payments, staff advances, partner capital |
| 53 | bank statement reconcile, year-end close, VAT report, fixed assets, budgets (all switches OFF) |
| 54 | attendance two paths counted once, form equation recompute |
| 60 | reorder report, wastage reasons, batch/expiry on GRN, QC records |
| 61 | online orders (`online_orders`), forms 20-x linked to sales, benefits, BI export |
| 62 | SMS/WhatsApp queue, payment-gateway intents + webhook log, accounting CSV export, assistant access |
| 70 | restore-drill record |
| 71 | TOTP 2FA safe core (factors live in Supabase Auth) |

### 2.3 Phases 72..103 (the integration series; order in docs/PASTE_ORDER.md)
| Phase (tag) | Added |
|---|---|
| 72 (bos72) | one COGS source `_cogs_lines72`, balanced inventory lines `_acct_inv_split72`, unknown-cost warnings, `inventory_vs_gl`, `acct_status`, `acct_post_errors72` |
| 73 | recipe master: artisan register (name readable only via `artisan_register()`), recipe versions + approval, steps, recipe book |
| 74 | costing: conversion cost into product cost (section 4), `production_post` 7-arg core, `recipe_cost` rows |
| 75 | cost sources and allocation (one bill split over sites) |
| 76 | sales channels, message inbox, web order form intake, Meta intake, `intake_bots`, PII mask + view audit |
| 77 | online-order gaps: pack-time stock warning, soft reservation |
| 78 | where showroom/admin cost belongs (`location_cost_attribution`, re-assign trail), approval-separation hint |
| 79 | **merge** of the function bodies phases 72..78 re-created |
| 80 | free-cost item flag (`item_cost_flags`), intake bot role + form `ONLINE_INTAKE` |
| 81 | setup advisor: `setup_recommendations`, activation guide, flow checks |
| 82 | stock guards: GRN vs bill, void guard, unit conversion, negative stock |
| 83 | form vs screen, expense double count, transit shortage, offline POS `record_sale_offline` |
| 84 | audit trail for stock cache/batches/transfers; `stock_reconcile` logging |
| 85 | stock moves to the GL, manual-journal guard, autopost scheduler, `card_settle`, expense payment mode |
| 86 | Telegram channel (`telegram_message_receive`, secret hash) |
| 87 | QA fixes (owner can approve, `expiry_sale_guard`, `client_id_taken`...) |
| 88 | one cost source for every report (`report_cost_source`) |
| 89 (bos89) | **merge** of function bodies that two or more phases re-created |
| 90 | scan: photo -> draft -> review -> existing save functions (`scan_jobs`, `scan_confirm`) |
| 91 | per-user / per-role visibility of every option (`user_option_view`, `role_option_view`) |
| 92 | invoice on screen after sale, share log |
| 93 | selectable print/message templates (`doc_template_choice`) |
| 94 (bos94) | security review fixes (section "Step Sec" in docs/briefs_p2p3/step_Sec_REPORT.md) |
| 95 | cash drawer option (OFF) |
| 96 | opening-stock helper, **cost waiting** (`cost_wait_list96`, `ledger_cost_supply96`) |
| 97 | **landed cost** (`landed_*`, `stock_ledger.reason = 'cost_adjust'`) |
| 98 (bos98) | final merge of `_acct_docs` (96 + 97) |
| 99 | two options: bill payment, inbox masking (`inbox_pii_mode`, `inbox_unmask`) |
| 100 | one category / sub-category master (`item_categories`) |
| 101 | setup-advisor rows for every rule of phases 82..98 (advisory only) |
| 102 | item photos option (`item_images_mode`, default off); not in the paste order table's numbered rows (listed as "(31)") |
| 103 (bos103) | end-to-end defect fixes; **goes LAST**; re-creates 20 functions from their latest bodies |

### 2.4 Web files (by area; every file header names its phase)
POS/sales: `pos.js`, `posfail.js`, `salereturn.js`, `salesx.js`, `invoice.js`, `invoiceview.js`, `cashdrawer.js`, `pay.js`, `dues.js`. Stock/purchase: `stock2.js`, `stockx.js`, `purchase.js`, `purchaseprint.js`, `guards.js`, `landed.js`, `landed_q4.js`. Items: `items2.js`, `itemmaster.js`, `bulkitems.js`, `catpick.js`, `itemimg.js`. Factory/cost: `recipes.js`, `recipebook.js`, `costing.js`, `costsources.js`, `costattrib.js`, `costboard.js`, `s1setup.js`. Accounting: `accounts.js`, `books85.js`, `books96.js`, `finance2.js`, `cashmoves.js`, `daybook.js`. People: `employees.js`, `attendance.js`, `attend2.js`, `payroll.js`, `salary.js`, `customers.js`, `partners.js`. Channels: `inbox.js`, `chanedit.js`, `packflags.js`. Control: `rules.js`, `switchboard.js`, `setupadvisor.js`, `setupundo.js`, `optviews.js`, `optionsx.js`, `rollout.js`, `paths.js`, `control.js`, `ownerboard.js`. Shell: `app.js`, `nav.js`, `ia.js`, `controls.js`, `kbdfix.js`, `theme.css`, `i18n.js`. Intake/ops: `scan.js`, `integrations.js`, `restoredrill.js`, `twofa.js`, `notifications.js`, `assistant*.js`. Templates: `tpl_registry.js`, `tpl_docs.js`, `tpl_labels.js`, `tpl_msgs.js`, `tpl_samples.js`, `tplpicker.js`.

### 2.5 Web-only steps (no SQL)
bos92/98/104 invoice and template wiring, bos101 collapsible drawer footer (Navfold), bos102 keyboard fix, bos106 test-harness fix (Q2), bos107 landed GRN picker + badge strip + setup undo (Q4), bos108 visual QA fixes (Pol). Reports: `docs/briefs_p2p3/step_*_REPORT.md`.

## 3. Shadow engine: one record + locked shadow copy, count once (phase 48..51, 54, 61)

Problem: the same event can be entered on two paths (quick screen vs paper form; app payroll vs form 21-1). Rule: **one primary record counts; the other path gets a linked, locked shadow copy that is never counted.** Posting stays unique on `(source_type, source_id)`.

| Object (`supabase/phase48.sql`) | Role |
|---|---|
| `path_domains` | The places where two paths exist: `payroll`, `stock_issue`, `stock_transfer`, `stock_count`, `production`, `expense`, `owner_money` (phase 54 adds attendance, phase 61 `sale_forms`) with the default primary (`a`/`b`/`first`) |
| `path_switch` | The **owner's** choice per domain and optionally per place (`location_id 0` = all): `a_open`, `b_open` (a locked path takes no NEW records), `primary_rule` |
| `shadow_links` | primary <-> shadow, `state` pending / confirmed / void, `locked`; unique index `shadow_one_per_primary`; append-only except pending -> confirmed -> void |
| `path_cfg`, `path_primary`, `path_allowed`, `path_guard`, `path_winner` | Read the switch; `path_guard(domain, loc, path)` is what the write functions call to refuse a locked path |
| `shadow_link_add`, `shadow_confirm`, `shadow_void` | Internal; create / confirm / void a shadow |
| `is_shadow(type, id)` | Used by readers (reports, day book, `_acct_docs`) to skip shadows, e.g. `not public.is_shadow('entries', e.id::text)` in the expense-voucher source |
| `shadow_report`, `shadow_count_once_check`, `dup_suspects` (phase 49) | Read-only checks that nothing is counted twice |

Legacy rule: where an older switch already meant "the form is the record" (`forms_post_to_ledger`), the default primary stays `b` so today's behaviour is unchanged. "Never both posting" for stock: exactly one path posts to the stock ledger (phase 51).

## 4. Costing structure (phase 74, 75, 78, 80, 88)

| Layer | What | In product cost? |
|---|---|---|
| 1 raw material | Weighted-average cost from the stock ledger (`stock_balance.avg_cost`). The latest purchase price ("today's price") is shown in a **separate** row and never booked | yes |
| 2 conversion cost | labour, gas/fuel, electricity, factory rent, licence & fees, machine repair, depreciation, other (owner may add types: `cost_component_types`) | **yes** (`production_post` adds it; per place mode `location_cost_cfg.mode` = off (default) / recipe / pool) |
| 3 showroom + admin | Cost shares of a bill with destination showroom/admin (phase 75 `cost_bill_shares`) | **no** - goes to the branch P&L; phase 78 `location_cost_attribution` chooses showroom / main centre / unallocated; shown in `l1_pnl`/`l3_shop_pnl` only when rule `cost_attrib_in_pl` is ON |

Product cost = material cost + conversion rate x quantity; unit cost of the finished good = (material + conversion) / actual output (`production_post`, `supabase/phase79.sql`). Pool mode divides a monthly pool by the **normal** monthly output, with smoothing none / yearly12 / avg_n; months without entry are gaps, never filled by a guess.
Unknown cost: cost NULL or 0 counts as **unknown** (phase 72) except items flagged free (phase 80 `item_cost_free_set`). Reports follow rule `report_cost_source` (phase 88): `ledger_then_item_costs` (default), `ledger_avg`, `item_costs`.

## 5. Stock engine (phase 10, 82, 84, 97)

* `stock_ledger` is **immutable** (update/delete/truncate blocked by triggers). One row per movement: `qty_delta` in the item base unit, `unit_cost` (secret), `reason` in {opening, purchase_in, purchase_return, sale_out, sale_void_in, sale_return, issue_out, production_in, transfer_out, transfer_in, wastage, count_adjust, reversal, and since phase 97 cost_adjust}, `ref_type/ref_id`, `batch_id`, `reverses_id` (unique: one reversal per row), `client_id` (unique with `reason`), `made_at` (business time; a late-synced sale keeps its sale time).
* `stock_balance (item_id, location_id, qty, avg_cost)` is **only a cache**, updated by a trigger on the ledger (`_avg_next`) under a row lock. `stock_reconcile(p_fix)` proves cache = ledger (phase 84 logs fixes).
* `stock_post(...)` is the single entry point: takes `for update` on the balance row, honours `client_id` (re-sent request returns the old row), applies negative-stock mode (`stock_negative_mode` allow / warn / block, default warn; per-call `p_neg` full/soft/none), consumes **batches FEFO** (expiry first, then oldest), caps a batch rest under 0.0005 as conversion dust.
* **Weighted average:** in-movements with a cost move the average; outs take the current average. `cost_adjust` (landed cost) is a *pair* of ledger rows (quantity out at the old average, back in at the new one) so the ledger stays replayable and `stock_reconcile` / `inventory_vs_gl` need no change.
* Only items with `items.tracked` are counted.

## 6. Accounting engine (phase 40, 52, 72, 85, 89, 96..98, 103)

* **Pull model.** `_acct_docs(p_start date)` is a function that *describes* every business document as a journal proposal (`source_type, source_id, entry_date, location_id, flags, waiting, lines jsonb`): `sale`, `sale_return`, `collection`, `purchase`, `supplier_payment`, `supplier_refund`, `expense_voucher`, `quick_expense`, production, wastage, payroll/advance/partner sources (52), stock moves (85: `stock_adjust`, `stock_opening`, `stock_issue`, `stock_transfer`, `transit_loss`, `purchase_variance`, `stock_prodin`), `landed_cost` / `landed_cost_void` (97), cards (85).
* `acct_post_pending(dry, limit)` posts every proposal that has no entry yet. Uniqueness: `create unique index je_source_uq on journal_entries (source_type, source_id) where reverses_id is null` - **a document posts once, ever**. A voided source gets a *reversing entry* (`_acct_need` decides). Locked periods are skipped. Entries must balance (debit = credit, each line debit XOR credit); failures are kept in `acct_post_errors72` (upsert on failure, delete on success) and shown by `acct_status`.
* **Mappings:** `acct_mappings` (payment mode / event -> account) the owner can re-point; account keys such as `pay_cash`, `receivable`, `payable`, `sales`, `cogs`, `inv_raw/inv_pack/inv_finished`, `stock_adjust` (5110), `stock_issue_use` (5120), `transit_loss` (5130), `purchase_variance` (5140), `interloc_clearing` (1230), `vat_input`, `landed_payable`, `landed_variance`.
* **Rounding (72):** inventory lines are rounded per item type and the remainder is put on the largest part (`_acct_inv_split72`), so entries always balance.
* **Autopost:** rule `accounting_autopost` (opening the accounts page posts); phase 85 `acct_autopost_tick()` is the same posting callable by a scheduler (rule `acct_scheduler_on`; each run kept in `acct_autopost_runs85`); `acct_scheduler_enable(cron)` uses pg_cron **only if the extension exists**.
* **Switches with default = today:** `accounting_on` (OFF), `accounting_start_date` (empty = "Data needed"), `acct_count_adjust`, `acct_stock_opening`, `acct_issue_out`, `acct_transfer_mode`, `acct_transit_loss`, `acct_purchase_variance`, `manual_journal_guard`, `acct_manual_prod_in103`.
* **Cost waiting (96/103):** a stock move without a known cost is **not posted**; it waits as `cost_missing` in `cost_wait_list96`. The owner or a cost-right holder supplies a cost (`cost_wait_supply96`: item_average / last_purchase / recipe_standard / manual with reason) kept in append-only `ledger_cost_supply96` (the ledger is not edited); then the document posts once.
* **Opening stock** (96/103): `opening_stock_apply96` (owner only, idempotent by client id, one entry per place) with four ways (owner_capital, existing_account, skip, difference) and follow-ups in append-only `opening_stock_followups103`; this prevents counting opening stock twice (once in the opening journal, once from the ledger).

### `inventory_vs_gl(date, loc)` (read-only)
Per item type: GL balance of the inventory account vs stock valuation (average cost for today, ledger replay for a past date), the difference, and the **explained reasons** computed from the ledger and journal (manual journals, production, purchase return variance, count adjustments, issue, transfers, opening, landed cost, waiting-for-cost). A non-zero *unexplained* figure is the signal that something bypassed the engine. Latest body: `supabase/phase103.sql`.

## 7. The "latest body" problem (why phases 79, 89, 98, 103 exist)
Each phase file re-creates whole functions from the text that existed on its own branch, so a later number can silently put an older body back. Found by comparing `md5(pg_get_functiondef)` and `bosNN` tags after every phase on a fresh build. Merge files: 79 (72..78), 89 (72..88, 90, 91), 98 (`_acct_docs` of 96 + 97), 103 (20 functions). Guards inside each file refuse to run if a prerequisite marker is missing or if a live function carries a tag the file does not know. See DEVELOPER_RUNBOOK.md.
