# Plan: reference-app functions vs Islamia BOS (planning only, no code)
Basis: docs MODULE_MAP/ROADMAP/DECISIONS, schema.sql, phase3-7.sql. Research on Odoo/ERPNext/Zoho/Xero/QuickBooks/Tally/Vyapar is from knowledge (no web check); BD tax points are UNVERIFIED and must go to a VAT adviser. No numbers invented: every threshold below is a Rule / Limit / List the owner sets (empty = "data needed").

## 0. What exists (facts from repo)
- items(code, name bn/en/mix, category, unit, sell_price, is_active) + item_costs (separate, ITEM_COST permission) + item_changes (approval queue) + item_price_history. Seed 57 items, CSV import exists as seed only.
- sales(lines jsonb, price snapshot, discount, pay_mode, customer_id, paid, due_amount, sale_type retail/wholesale), sale_payments, customers (mobile, credit limit), collect_payment/void_collection/void_sale, customer_ledger, dues.
- entries(form_code, data jsonb) = 42 BOS forms incl. 04-1 GRN, 04-2 issue, 04-4 store ledger, 03-1 transfer, 06-1..06-5 PR/CS/PO/bill check/supplier ledger, 10-x cash, 18-1, 20-x orders/returns/party invoice. These are paper-style records in JSON: NO live stock balance, no relational supplier table.
- rules/rule_grants/grant_defs/emergency_requests, option_lists (editable lists), books_closed_until, exceptions, audit_log, biz_* analytics (ABC, outlook, margin).
- Biggest structural gap: no stock ledger, no supplier master, no payable/receivable book, no batch/expiry. Everything else in the reference list is smaller.

## 1. Gap table
Priority: A = do first (fixes real control/loss), B = next, C = later/optional, X = skip.

| Function | Exists today | Missing | Design for us (simple, sweets, phone) | Data model | Pri / phase |
|---|---|---|---|---|---|
| Item master core (category, unit, details) | items: category, unit, price; cost separate | sub-category, details, active flags per use, stock-tracked flag, shelf-life, sell-online flag | Keep ONE items table. Add: sub_category (List), base_unit + sell_units (see units), tracked (bool; true for packaged/raw, false for made-to-order sweets if owner says), shelf_life_hours/days (nullable, owner-entered per item/category, never defaulted), min_stock (nullable), vat_applicable (nullable until VAT decided), sell_online, wholesale_price, image_count | alter items add cols; wholesale_price on items (not secret); cost stays in item_costs | A (P-B1) |
| Images up to 5 | photos bucket for 3 forms | item photos | Up to 5 jpeg on phone, compressed client-side, first = POS tile. Public repo + storage: item photos fine, no costs | table item_images(item_id, path, sort) + storage policy like photo_ok | C (needed only with online shop) |
| Barcode scan | none | scan | Phone camera scan (BarcodeDetector API / small JS lib) for PACKAGED items (box, drinks, packed dry sweets). Fresh sweets sold by weight: no barcode, use quick keys. Optional scale label barcode: skip | items.barcode (unique, nullable) | B |
| Low-stock alert | none (ROADMAP: needs live balance) | balance | Alert when balance <= items.min_stock; shown in dashboard "problems first"; reorder suggestion = sales speed x lead time (existing biz_outlook data). min_stock empty = no alert | view stock_balance; rule `low_stock_alert` on/off | B (after stock ledger) |
| VAT applicable / VAT settings | none; Mushak 6.3 open | | See 2.4. Store flag + rate in settings, receipt prints only what owner enables. No computing until adviser answers | items.vat_applicable; settings vat_mode (off/included/added), vat_rate (rule number, no default); sales.vat_amount | C, blocked by owner decision |
| Warranty | none | | Not for sweets. Replace with "best before / use within" (expiry). Skip warranty | - | X |
| Discount (item-level / settings) | POS discount w/ limit per location, manager approval, slip 20-2 | per-item default discount, campaign/period discount | Keep current limit+grant model. Add only "festival price" = dated price row (valid_from/to) in price table, not a separate discount engine | item_prices(item_id, kind retail/wholesale/online, price, from, to) later; until then items.wholesale_price | C |
| Sell online | form 20-6 online/delivery ledger (paper) | catalog/orders | Phase later; first make WhatsApp/Facebook order -> existing POS sale type 'online' + delivery fields. No public web shop at this stage | sales.sale_type add 'online'; sales.delivery jsonb (addr, fee, rider, status) | C |
| Wholesale price | sale_type wholesale, needs customer | separate price | items.wholesale_price; POS picks it when sale_type=wholesale; override still needs grant price_override | col above | A (cheap) |
| Cost price owner-only | ITEM_COST perm, hidden via API | - | Keep. Purchase receipts hold actual unit cost; avg cost computed server-side, only ITEM_COST roles can read. Staff see qty not value | stock_ledger.unit_cost column-level protected: put value columns in a separate table stock_values or view with biz_cost_ok() check | A |
| Bulk upload | seed CSV only | in-app import | Owner pastes/uploads CSV from phone -> preview -> items go through item_changes approval as ONE batch (owner's own apply at once). Template download. Never overwrite price silently | RPC import_items(jsonb) w/ dry_run flag; item_import_batches(id, rows, status) | B |
| Manufacturer / brand / colour / size / attribute sets | brand = locations/brand in settings | | Sweets: DROP colour/size/manufacturer. Keep: (a) brand = which of 3 brands sells it (item_brands link or tag List) (b) unit set (c) weight variants (d) "produced by" = factory vs bought-in (flag, matters for production vs purchase) | items.source ('made'/'bought'), items.brands text[] | A (unit), rest C |
| Unit sets (kg / piece / box) | unit text free | conversions | Each item: base_unit (what stock is counted in: kg for loose sweets, piece for boxed) + conversion table, e.g. 1 box = N pieces = X kg (owner enters, no default). POS sells in any listed unit, converts to base for stock | item_units(item_id, unit, factor_to_base, is_sell, is_buy) + List `units` | A |
| Variants by weight | items are separate per kg item (e.g. "– কেজি") | | Do NOT build variant matrix. Weight packs (250g/500g/1kg box) = item_units rows of the same item when contents are same sweet; if box has a different price/pack cost, separate item. Rule of thumb in UI help | via item_units + price per unit | A |
| Customer types | retail/wholesale | party, corporate, online, staff/free | List `customer_types` (editable) + column on customers; default discount % optional per type (owner entry); credit limit stays per customer | customers.type_code (List value) | B |
| Suppliers + types | free text in 06-x forms | master | suppliers(id, name, mobile, type List, address, credit_days nullable, opening_balance, active, nid/tin nullable). Types List: milk/chhana, sugar, packaging, fuel, gas, services etc. (owner edits). 06-x forms get a supplier picker instead of free text | table suppliers; option_lists key supplier_types | A |
| Purchase: direct bill | 04-1 GRN, 06-4 bill check, 06-5 ledger (paper) | relational bill | One "purchase" doc: supplier, lines (item, qty, unit, unit cost), paid now, due, photo of bill. Creates stock IN + payable. Keep 06-1 PR -> 06-2 CS -> 06-3 PO as optional upstream (only big buys; Limit quote_over already) | purchases(id, location, supplier_id, ref, date, status draft/received, lines jsonb or purchase_lines table, total, paid, due, photo, po_entry_id); purchase_lines | A |
| Purchase order / receipt | 06-3 PO, 04-1 GRN forms | link PO -> receipt -> bill, partial receipt | 3-way match already on 06-4; make GRN post stock, PO->GRN link by number. Do not duplicate: GRN IS the receipt; direct bill = PO-less GRN | purchases.po_ref, received_qty per line | A/B |
| Purchase return | none | | Return to supplier doc: lines, reason (List), reduces stock (OUT), reduces payable OR becomes supplier credit note. Needs grant `purchase_return` | purchase_returns + lines (or purchases.kind='return') | B |
| Batch payment to supplier | none | | Pay supplier: amount, mode, allocate to oldest bills (FIFO, same as collect_payment pattern), reference; reversible like void_collection; counts against cash (10-4) | supplier_payments(id, supplier_id, location, amount, mode, ref, allocations jsonb, voided) + RPC pay_supplier | A |
| Supplier credit / refund | none | | Supplier balance can go negative (supplier owes us) = credit; refund = supplier pays back cash -> payment row of kind 'refund' | supplier_payments.kind | B |
| Sale: direct invoice | POS record_sale2 | - | exists | - | done |
| Sale: order / delivery | 20-1 order form, 20-4 party invoice (paper) | order -> advance -> delivery | Order = sale with status 'order', advance payment row, delivery date, then 'delivered' posts stock OUT and balance as due. Party/wedding/Eid orders are the real use case | sales.status ('sold','order','delivered','cancelled'), sales.deliver_on, sale_payments.kind 'advance'; order lines frozen price | B |
| Sale return | 20-3 form (paper) | stock + money effect | sale_return doc linked to original sale; reason List; refund cash/mobile or credit to customer balance; stock IN only if reason is "resaleable" (sweets: usually not -> wastage). Grant `sale_return`, limit per location | sale_returns(id, sale_id, lines, refund_mode, amount, reason, restock bool) | A (money leak risk) |
| Customer batch payment / debit / refund | collect_payment, customer_ledger, void_collection | refund of advance/overpay | Add refund kind (cash out) with grant; ledger already handles negative balance | sale_payments.kind refund | B |
| Chart of accounts + transactions | none (Cash forms + P&L form 01-2) | | See section 2: NOT a free chart of accounts. Fixed small set of "books" | see 2 | B/C |
| Income / expense add | expenses 10-2, heads List, 18-1 marketing; no "other income" | other income (scrap sale, rent received, tips, interest) | Add `other_income` form-like quick entry w/ heads List; show in P&L | entries via form engine (new form 10-6) or table money_in | B |
| Cashbox | drawer count 14-1, handover 10-1, cash position 10-4, imprest 18-1 | running book | Cashbox per location = computed book: opening + cash sales + collections + other income - expenses - supplier cash payments - hub handover; compared with blind count (existing). Do not store balance; compute from sources | view cash_book(location, date) | B |
| Stock book | 04-4 store ledger form (paper) | live ledger | See section 3 | stock_ledger | A |
| Expired product tracking | none | batch/expiry | See section 3. Sweets: shelf life hours/days from production, not printed expiry. Track "made at" per production batch for tracked items; daily "sell-by today" list; end-of-day unsold -> wastage w/ reason | batches table | A (high value) |
| Recycle bin | audit_log; voids; is_active | | Do NOT build a generic bin. Soft-delete (is_active/voided) already is the model; add one owner page "Deleted/voided in last N days" reading audit_log + voided rows with Restore for items/customers/suppliers only. Money docs are never deleted, only voided | page only; no new table (maybe deleted_at on masters) | C |
| Topup (mobile recharge etc.) | none | | Not a sweet-shop function. Skip unless the owner says shops sell recharge | - | X |
| Printer / receipt | receipt number, share | thermal print | Phone-first: Bluetooth thermal ESC/POS via Web Bluetooth does not work on iOS/Safari; use "share as image/PDF" + optional RawBT app intent on Android. Receipt layout from settings (header per brand, footer, VAT line only if enabled). Test on owner's real printer first | settings receipt_* ; no tables | B |
| Multi-shop combined report | biz_*, dashboard per location | consolidated P&L incl. COGS, stock value, payables across 8 locations | RPC branch_pnl(from,to): sales, discounts, returns, COGS (from stock ledger avg cost), wastage, expenses, other income; per location + total + hub; owner/management only | RPCs report_branch_pnl, report_stock_value, report_payables | B |
| Sale / purchase / customer settings | rules/grants/lists | few new keys | Add rules (all owner-set, no defaults for numbers): see section 4 | rules rows | with each phase |

## 2. Accounting model decision
Options: (A) full double-entry (chart of accounts, journals; Odoo/ERPNext/Zoho/Tally/QuickBooks/Xero core); (B) lightweight books: cash book, receivable (customer ledger), payable (supplier ledger), stock ledger, expense/income lists, computed P&L; (C) status quo.
Recommend B now, designed so A can be derived later.
Reasons: owner is a non-accountant and phone-only; data entry by shop staff; a free-form chart of accounts and debit/credit entries are the #1 way staff create wrong books. Every money event in BOS already has a source document (sale, payment, expense entry, GRN/bill). Therefore:
- Keep source documents as the truth (sales, sale_payments, purchases, supplier_payments, expenses, stock_ledger, other_income).
- Publish FIXED reports: Cash book, Receivable, Payable, Stock value, P&L (sales - returns - discounts - COGS - wastage - expenses), per location and combined.
- Give each doc a fixed "account tag" (a read-only mapping table acct_map: doc_kind -> account code/name, e.g. sales->Income, supplier bill->Inventory/Payable). This is a hidden chart of accounts: the accountant/VAT adviser can export a journal (CSV) generated from documents without staff ever seeing debit/credit. Owner can rename labels, not restructure.
- Why not A now: cost > benefit before stock ledger and supplier ledger exist; double entry on top of missing subledgers gives wrong books with a nice look. Revisit when (1) an accountant is hired, (2) bank loan/investor needs statements, (3) VAT filing needs journals. Trigger to review: owner decision.
- Stock valuation: weighted average cost per location (Odoo/ERPNext/Zoho default AVCO; FIFO is available there but needs layers). Sweets turn in days, price swings (sugar, milk) are small per week: average is adequate and explainable. FIFO only for expiry-driven consumption order (physical), not for costing. Cost visible only to ITEM_COST holders.
- Honest limit: P&L from this is management P&L, not statutory accounts or tax computation; say so on the report.

## 3. Stock model
Single append-only `stock_ledger` (never edited, errors fixed by reversing rows, same philosophy as voids):
columns: id, location_id, item_id, batch_id nullable, qty_base (+in / -out), unit_cost (nullable, value-protected), reason enum, ref_kind, ref_id, note, user, at. Balance = SUM(qty) per location/item (+ cached table stock_balance updated in same RPC, row-locked).
Reasons and source mapping:
- purchase_in <- purchases/GRN 04-1 (qty, cost, supplier)
- purchase_return_out <- purchase return
- sale_out <- record_sale2 (only for items with tracked=true); sale_void_in on void
- sale_return_in/out <- sale return (restock only if flagged)
- issue_to_production_out <- 04-2 material issue (raw items, e.g. sugar, chhana, milk)
- production_in <- factory daily sheet 05-x (finished item qty made, with batch) ; yield test 05-3 gives expected vs actual -> variance exception
- transfer_out / transfer_in <- 03-1 challan (OUT at sender on dispatch, IN at receiver on receiver check; difference = transit-short exception; "in transit" shown, not lost)
- wastage_out <- NEW wastage form/page: reason List (expired, spoiled, burnt, broken, sample/free, staff meal, theft-suspected) ; needs photo above a Limit; grant `wastage_write_off`; reason "unknown" raises exception
- count_adjust <- 04-3 stock count: counted vs system -> adjustment row after approval; tolerance Limits count_tol_pct/max already exist
- opening_balance one-time at go-live (via count, not typed guess)
Batches: batches(id, item_id, location_id, made_at, source production entry, shelf_life_until = made_at + item shelf life (owner-entered), qty_remaining). Only for items with shelf life. POS deducts oldest-first (FIFO physical). "Sell today / expiring" list on home; end-of-day button "move unsold to wastage with reason". No shelf life set = no expiry features (no invention).
Fresh made-to-order sweets: allow tracked=false so POS never blocks; only the factory production vs sales reconciliation reports (made - sold - wastage - closing = unexplained).
POS behaviour when stock insufficient: Rule `pos_stock_mode` block / warn / off (default off until opening balances are done), grant `sell_below_zero`, emergency request path exists.
Tie to forms: 04-1 posts IN, 04-2 posts OUT, 04-3 posts adjust, 04-4 becomes a VIEW of the ledger (print/export), 03-1 transfer, 05-x production, 06-4 matching reads purchases, 06-5 becomes a view of supplier ledger. Forms stay as the approval/evidence layer; posting happens on approve (decide_entry hook) so the maker-checker rules still apply.
Wastage figures = the owner's real leak finder: report wastage % by location/reason, ABC (biz_items) + exceptions.

## 4. Permissions / rules / emergency per new function
Use grant_defs (once/window kinds), rules table (switch/number/choice), option_lists, Limits per location, entries maker!=checker. All numbers empty by default.
| Function | Grants (new) | Rules / Limits / Lists | Emergency |
|---|---|---|---|
| Item master edit | existing ITEMS approve; ITEM_COST | list `units`, `sub_categories`; rule `item_require_unit` | n/a |
| Bulk upload | `bulk_import` (owner default) | max rows rule | owner only |
| Stock negative / sale w/o stock | `sell_below_zero` (once) | rule `pos_stock_mode` | once approval by owner |
| Wastage write-off | `wastage_write_off` (staff enter, manager approve above Limit `wastage_max`) | list `wastage_reasons`; Limit `wastage_photo_over` | once |
| Stock adjust after count | existing count approval | count_tol_* | once for closed period |
| Purchase bill | `purchase_enter` (storekeeper/purchasing), approve by other person | rule `purchase_price_variance_pct` (flag if unit cost differs from last by owner %), `supplier_credit_mode` block/warn/off, per-supplier credit limit | once |
| Purchase return, supplier refund | `purchase_return`, `supplier_refund` (owner/management) | list `return_reasons` | once |
| Supplier payment | `supplier_pay` , `supplier_pay_void` ; pay by cash needs drawer/hub cash availability (10-4) | Limit `supplier_pay_cash_max` | once |
| Sale return / refund | `sale_return` (manager), `refund_cash` | Limit `return_max`, rule `return_needs_receipt`, `return_window_hours` (owner number) | once |
| Order advance / cancel | `order_cancel` | rule `order_min_advance_pct` (number, empty=off) | once |
| Other income | `income_enter` ; approver separate | list `income_heads` | - |
| Cashbox/books | existing closed_period_edit | books_closed_until applies to all new docs (extend lock_check) | window |
| VAT settings | owner only (`vat_settings`) | vat_mode/rate rules | none |
| Recycle/restore | `restore_deleted` owner only | - | - |
| Combined reports | existing biz_ok; cost/profit parts require ITEM_COST | - | - |
Every new RPC: SECURITY DEFINER, uses can_loc + rule_ok, writes audit_log, respects lock_check, raises exception rows (new codes: stock_negative, wastage_unknown, purchase_price_jump, return_no_sale_link, transit_short).

## 5. Reference-app things NOT worth copying
- Free chart of accounts and manual journals for staff; multi-currency; fixed assets depreciation; bank reconciliation engine.
- Colour/size/manufacturer/attribute matrices, warranty, serial numbers, IMEI.
- Topup/recharge, SMS marketing, loyalty points, multiple price lists per customer group (until real demand), coupon engine.
- Full public online shop with payment gateway (phase later; ordering via POS first); courier integrations.
- Generic recycle bin for money records (use void + audit log).
- Touch-screen heavy desktop layouts; tiny-text tables; lots of tabs. Keep phone-first, one task per screen.
- Auto-apply "AI suggestions" (consistent with current rule: suggestions only).
- Barcode-for-everything (loose sweets have none).

## 6. Phases and checkpoints (each ends with: local DB test, audit agent, owner phone test, update ROADMAP checkpoint)
Phase B0 (design lock, no code): owner answers section 8 Q1-Q8. Checkpoint: written decisions in DECISIONS.md.
Phase B1 Masters: suppliers, item extra columns (sub-category, base_unit, item_units, wholesale_price, tracked, shelf_life, min_stock, barcode, source), customer_types, option lists (units, wastage reasons, return reasons, income heads, supplier types). Additive migration only. Checkpoint: existing POS unchanged; items import round-trip test.
Phase B2 Stock ledger (opening balance via count first): stock_ledger, stock_balance, posting hooks from 04-1, 04-2, 04-3, 03-1; POS sale_out under Rule pos_stock_mode=off then warn. Wastage entry. Checkpoint: for a pilot location (1 shop + hub) 2 weeks: ledger balance vs physical count within owner tolerance before turning on.
Phase B3 Purchase and supplier ledger: purchases, supplier_payments, payable/aging, purchase return, price-jump flag, 06-x forms linked to supplier picker. Checkpoint: payable total = sum of unpaid bills; supplier ledger matches owner's paper ledger for 1 month.
Phase B4 Batches + expiry + production posting (05-x), end-of-day wastage flow, low-stock and expiry alerts on dashboard. Checkpoint: made - sold - wasted - closing reconciles for pilot items.
Phase B5 Sales extensions: sale return, order/advance/delivery, refunds, wholesale price in POS, online sale type. Checkpoint: customer balance and cash book still reconcile after returns.
Phase B6 Money books and reports: other income, cash book, combined branch P&L with COGS (avg cost), stock value, payables; acct_map export CSV for adviser. Checkpoint: owner compares with existing 01-2 monthly P&L for one closed month.
Phase B7 Optional: VAT/Mushak (after adviser), receipt printing, item images, bulk upload polish, online catalog, recycle/restore page.
Build order rationale: stock before purchase before reports; each phase usable alone; phases B1-B3 give most control value (cost leaks: purchase, wastage, supplier credit).

## 7. Risks and migration safety
- Real DB already has data (user ran phase3+4; phase5-7 / ALL_NEW not yet run). FIRST ensure ALL_NEW.sql is run and verified before any new migration; new SQL as phase8+.sql, idempotent (create if not exists, add column if not exists, nullable columns, defaults that keep old behaviour). No destructive change to sales.lines, entries.data, or items.
- Backfill: do NOT backfill stock from history (no reliable balances). Start with a counted opening balance per location on a chosen date; ledger starts there. Old GRN entries stay as paper records.
- Feature flags: every new behaviour behind a Rule defaulting to off/warn; old POS path must still work if SQL not run (current app already falls back; keep that pattern).
- Free Supabase plan: row limits/size 500MB DB, no auto-backup. Ledger rows + photos grow; keep photos compressed, batch jsonb lines, add an index plan, owner downloads backup before each migration (existing backup button). Unverified plan limits: check current Supabase free limits before B2.
- Performance of balance: use cached stock_balance with row locks to avoid races from 8 shops selling; ledger is the audit truth, a nightly/ondemand reconcile RPC compares both.
- Offline POS queue: stock deduct on late sync can go negative; warn mode must tolerate; reconcile report.
- Staff gaming: wastage as theft cover, returns as theft, fake purchase prices; controls = wastage reason+photo+limit+trend by staff in biz_staff, return linked to original sale, price-jump flag, supplier-bill photo, hub receives blind count.
- Data entry burden on phone: too many fields = staff skip. Measure taps per sale/receipt; keep sale path unchanged.
- Public repo: costs never in web/ code or seed; keep cost in item_costs/value view only.
- Tax/law: VAT, Mushak 6.3, TIN/BIN, turnover thresholds unverified; wrong receipts = penalty risk. Do not print VAT numbers until adviser confirms.
- Scope creep: 8 locations x 3 brands; reports must filter by brand if owner wants brand P&L (needs sales.brand or location->brand mapping; open Q).

## 8. Open owner decisions (need answers before build)
1. VAT: is the business VAT-registered (BIN)? Which brands/locations? Turnover? Prices VAT-inclusive? Adviser answer on Mushak 6.3 for sweet shops (and 6.1/6.2 purchase/sales records). Until answered: no VAT on receipts.
2. Which items are stock-tracked (packaged/raw) vs made-to-order untracked? Start with how many items/locations as pilot?
3. Shelf life per category (hours/days) - owner/factory to state; and who records "made at" (factory in-charge on 05-x?).
4. Unit conversions for box/pack/piece/kg per item (owner list).
5. Stock valuation: average cost OK? (recommended) 
6. Is production quantity recorded daily per product at the factory today? If not, production_in will be weak and stock will drift.
7. Supplier credit: which suppliers give credit, typical days (owner-entered), who pays (hub only, or shops with imprest)?
8. Returns policy for sweets (restock never? refund cash or credit only? time window?) and who approves.
9. Brand-level P&L needed? (3 brands x locations mapping)
10. Online selling: WhatsApp/Facebook orders only, or a public catalog? Delivery fees/riders?
11. Receipt printer model/hardware at shops (Bluetooth thermal? Android only?) 
12. Accounting: will an accountant/VAT adviser need a journal export? Should we plan a double-entry export (acct_map) now?
13. Sell-below-zero policy at go-live and tolerance for count differences.
14. Topup/warranty/online-shop images: confirm skipped.
