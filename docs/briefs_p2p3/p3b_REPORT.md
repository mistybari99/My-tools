# p3b REPORT - P3 gaps #11 online orders, #12 forms 20-x <-> sales, #13 benefits depth, #14 BI export
Files: supabase/phase61.sql (+ phase61_test.sql), web/salesx.js, tests/web/salesx_test.js. Run AFTER phase51. Paste-twice safe (verified). No existing function was re-created and no existing row changed (additive only).

## Built
- **#11 Online orders** - `online_orders` (+ append-only `online_order_events`), flow new -> confirmed -> packed -> delivered | cancelled (forward only).
  `online_order_save` (create/edit while new|confirmed, idempotent on client id, serial 'ORD' per place), `_status`, `_cancel` (reason + advance fate refund/adjust/income recorded, nothing posted),
  `_deliver` (calls the EXISTING `record_sale2` once: advance = first payment, delivery charge = a quick-sale line, discount passes through; sale client id stored on the order; `sale_id` unique; retry returns `dup`; a failed sale leaves the order packed),
  `_link_sale` (links an already-made sale of the same place, needs POS approve; never creates a sale), `online_orders_list`, `online_order_get`. Needs POS enter/view + place access. Order lines use today's list price.
- **#12 Forms 20-1/20-2/20-4 <-> sales** - path domain `sale_forms` (inserted here, domain 8 of the engine), `sale_form_links` (append-only trail, one active link per entry, one per sale+form).
  `sale_form_link` (OWNER only): primary = sales row, shadow = entry, shadow_type `entries:20-x` (distinct per form so one sale can hold 20-1 + 20-2 + 20-4), form must be submitted/approved, same place, sale 'done'.
  A linked form gets the same lock as phase50 shadows (no data change, no re-open) via trigger `entries_saleform_lock61`; 20-x never posts anywhere. `sale_form_unlink` (owner, note) voids link + shadow. `sale_forms_for(sale)`.
  `unlinked_sale_forms(from,to,loc)` = report of unlinked 20-x with up to 3 candidate sales (same place, +-3 days, same total when the form has one). Owner switch: path B locked = no new links (primary is always the sale).
  Amount check: only 20-1 has a readable total (total - discount); returns `amount_diff` (not blocking). 20-2/20-4 give null.
- **#13 Benefits depth** - `benefit_types` (paid_in_payroll default, eligible_after_days, default_for_all; 7 legacy kinds seeded), `employee_benefit_grants` (from, eligible_from = max(from, joining + days), to, paid_in_payroll, value hidden: column not selectable, shown only with salary_view).
  `benefit_type_save` (owner / salary_manage), `employee_benefit_grant` (idempotent, overlap refused, value needs salary_manage), `_grant_end`, `benefits_report(as_of, loc)` = grants with state not_yet/eligible/ended + "eligible but no grant" list for default_for_all types.
  REPORT ONLY: payroll maths is untouched (test proves no payroll function reads the new table). Old phase41 `employee_benefits` left as is.
- **#14 BI export** - `bi_export(dataset, from, to, loc, format json|csv, limit)`: datasets sales, sale_lines, purchases, stock_ledger, journal. Owner or grant `export_data`; rule cap `bi_export_max_rows` (default 5000, hard max 20000) + `truncated` flag; <= 366 days; place scope = the same predicates as the table RLS.
  Cost: stock_ledger.unit_cost blank unless `rpt_cost_ok()`; purchases refused without it; journal needs accounts_view; sales/sale_lines need POS view; no customer mobile exported. CSV has a formula-injection guard (leading = + - @ prefixed with ') and proper quoting.
  One `bi_export_log` row per successful call (append-only, owner reads via `bi_export_log_list`). Denied calls raise and are not logged.
- **Switches (all OFF by default)**: `online_orders_on`, `sale_forms_link_on`, `benefit_grants_on`, `bi_export_on`; number `bi_export_max_rows`. Owner turns them on in the switch board. No new grant codes (reuses POS, export_data, employee_manage, salary_manage, salary_view).

## Tests
- supabase/phase61_test.sql: **114 pass / 0 fail** on a fresh DB (phase8..51 + 61); phase61.sql re-applied a 2nd time without error.
  Covers: privileges/RLS/column hiding, switch off/on, create idempotency, status flow, deliver = exactly one sale + stock once + retry dup + overpaid rollback, cancel fate, link existing sale, link/unlink 20-x, locked shadow, count-once check, path lock, report + candidates, benefit eligibility/overlap/value hiding/missing list, export json+csv, cap/truncation, cost blanking, scope, log append-only.
- Regression: built DB through 61 vs DB through 51 and ran phase49/50/51 tests: identical (16/45/23 pass, 0 fail).
  **phase48_test.sql: 3 expected failures** (`T0 seven domains seeded`, `T1 path_switches lists 7 domains`, `T6 still 7 domains`) because those asserts hard-code count = 7 and the brief tells me to add the domain `sale_forms`. They pass again if the count is changed to the real number (phase54 by another agent adds `attendance` too, so the lead should update those 3 numbers to 9 once both are in). I did not edit phase48_test.sql (not my file).
- Web: tests/web/salesx_test.js (Playwright, 360px, injects the script tag itself): see result line at the bottom.

## ia.js lines (lead to add) and script tag
```
rec('onlineorders', 'sale', ['অনলাইন অর্ডার', 'Online orders', 'Online অর্ডার'], { icon: 'doc', ok: pos, kw: ['online order', 'facebook', 'whatsapp', 'delivery', 'advance', 'অনলাইন', 'অর্ডার', 'ডেলিভারি'] }),
rec('saleforms', 'settings', ['ফর্ম 20-১/২/৪ ↔ বিক্রি', 'Forms 20-1/2/4 <-> sales', 'Form 20-1/2/4 ↔ sale'], { icon: 'doc', ok: owner, kw: ['20-1', '20-2', '20-4', 'link', 'shadow', 'order form', 'invoice', 'জোড়া'] }),
rec('benefitsx', 'people', ['কর্মীর সুবিধা (রিপোর্ট)', 'Employee benefits (report)', 'Employee সুবিধা (report)'], { icon: 'users', ok: (c) => c.own || c.GF.employee_manage === true || c.GF.salary_view === true, kw: ['benefit', 'allowance', 'eligible', 'festival', 'সুবিধা', 'ভাতা'] }),
rec('biexport', 'reports', ['BI এক্সপোর্ট', 'BI export', 'BI export'], { icon: 'doc', ok: (c) => c.own || c.GF.export_data === true, kw: ['export', 'csv', 'json', 'bi', 'power bi', 'sheet', 'এক্সপোর্ট'] }),
```
`<script src="salesx.js"></script>` after payroll.js / customers.js (needs BOS_APP, B.L/lab, B.loadStatic; no other dependency). Add salesx.js to the sw.js precache list if the lead keeps one.
Handlers use unique data-act names (sx_, sf_, bx_, ex_ prefixes). Existing icon keys only (doc, users).

## NOT done / UNVERIFIED
- Web UI was run only against a mocked Supabase (no real DB round trip); real RPC shapes were checked by the SQL test, the page mapping by the mock test. No visual review on a real phone.
- Order price: lines carry the list price of the order day; if the list price changes before delivery, record_sale2 uses the shown price and raises its usual price_changed exception (it is not overridden). Discount at delivery follows the normal POS discount approval rules and may raise `discount_needs_approval`.
- Order advance and its refund/adjust fate are only recorded on the order; no cash move / journal line is posted for the advance before delivery (the advance becomes a sale payment on delivery). Cancel with advance_fate=refund does NOT move money; the cashier must do a normal cash move.
- #12: no automatic matching; amount check exists for 20-1 only; 20-2/20-4 field names for totals were not mapped (null diff). 20-3/20-5/20-6 are not linkable by design. The `primary` setting of domain sale_forms is ignored (the sale is always the record).
- #13: no payroll integration (by design), no auto-grant, no import of old phase41 `employee_benefits` rows into grants, no benefit_type retire screen (only active flag via function). Web UI has report + "grant" + "end grant"; types are created through the function only (no screen).
- #14: no scheduled/automatic export, no BI push, no per-column choice; journal export shows posted lines incl. reversals as stored. The export size is bounded by the row cap (max 20000) and the JSON is returned in one RPC response.
- Denied export attempts are not logged (an exception rolls back). If the owner wants denied attempts logged, it needs a second autonomous log path (not built).
- One more domain row changes phase48_test counts (see above).
