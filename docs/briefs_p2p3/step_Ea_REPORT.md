# Step E-a report (fix/phase-Ea, supabase/phase82.sql) - E1 GRN vs bill, E2 bill void, E3 unit conversion, E4 negative stock
Base: fix/phase-C2b (phases to 75 and 78). phase72 is on another branch and is NOT needed. New switches all default to today's behaviour. Nothing forced: guard_recommendations() only recommends.

## যাচাই হয়েছে (run on scratch DBs 82t1 / 82r*)
- phase82_test.sql: 57 pass / 0 fail on a fresh DB built phase8..phase78 + phase82; phase82.sql applied a second time without error (paste-twice).
- E1: guard off + source grn = +20 (the audit finding, today); guard skip: GRN 10 kg + bill 10 kg = +10; bill still records money/supplier balance; bill-less GRN under source grn adds +7; link mode: unlinked bill refused (grn_link_required), after grn_bill_link it posts and stock stays +7; source purchase: the bill-less receive appears in grn_pending_report().receipts_without_bill, leaves it after linking; bills_without_receipt list under source grn.
- E2 (purchase_void_guard=refuse): refusals void_has_return, void_would_go_negative, void_has_grn_batch each tested, refused void leaves bill/stock/payment intact; warn mode proceeds with a red purchase_void_unsafe line; purchase_void_payments=keep: payment NOT voided, supplier credit 50 shown by the existing supplier_credits(), existing supplier_refund() takes 10 back; =void (today) still voids the payment.
- E3: warn (today) = sale accepted, stock not reduced, yellow; refuse = online sale refused unit_unknown, late offline sale (sold_at > 2 min old) accepted + RED stock_unit_unknown_late; item editor (trigger on items) refuses tracked=true / new tracked item without conversion; after a conversion row exists it works and the sale deducts qty x factor; off = no exception; unit_unknown_items() count; owner-only.
- E4: never-opened item sold under warn goes -1 with no stock_negative line (gap confirmed), appears in never_opened_negative_items(), leaves it after an opening row; neg_grant_log off = no line (today), on = one yellow sell_below_zero_used line (item, qty, staff id); user without the grant still refused insufficient_stock; production_negative_reason required: refused without note (production_negative_reason_needed), with a note passes + yellow production_negative line; off = as today.
- Language: tests assert no Bangla letter in any new English text (rule labels/hints, exception en texts, recommendation reason_en, web messages). node tests/web/guards_test.js: 35 pass / 0 fail (bn/mix/en, apply only calls set_rule).
- Regression, same fail lines before (build to phase78) and after (+phase82): phase10 (T12 date-dependent known + 1 more) 2 / 2 fails; phase12 0 of 97; phase13 0; phase14 0 of 153; phase19 1 / 1 (pre-existing T0); phase23 91 pass 1 fail / 91 pass 1 fail; phase43 0 / 0; phase53 112 pass 0 fail / same; phase60 62 pass 0 fail / same.

## পড়ে বোঝা (code read, not run)
- Re-created functions (latest definition via pg_get_functiondef, lines tagged `-- bos82`): `_post_purchase_p13`, `_void_purchase_p13`, `_sale_stock_out`, `stock_post`. NOT re-created: production_post, recipe_cost, _acct_docs, _p27_pl, biz_daily, acct_status. production_post gets the negative-reason rule through stock_post (ref_type 'production', its note is the reason).
- New: tables none; trigger items_unit_conv82 (after insert/update of tracked, unit, base_unit); path_domains row 'grn' (link only, no a/b lock; it shows in the path switches screen); functions grn_bill_link, grn_pending_report, unit_unknown_items, never_opened_negative_items, guard_recommendations (owner-only except grn_bill_link / grn_pending_report).
- GRN link is primary=entries (GRN), shadow=purchase_bills; one GRN to one bill, one bill may have several GRNs.
- Web: web/guards.js (page `guards`, BOS.guardMsg(code) messages in 3 languages) - not wired into the app yet.

## যাচাই হয়নি
- The page web/guards.js was never opened in a real browser (only the node stub test); lead must wire it.
- Day book / GL treatment of a kept payment after a bill void and of supplier_refund cash: relies on existing code (_acct_docs untouched); not verified end to end.
- `link` mode refuses bills when no GRN exists yet (goods not received): owner may prefer skip.
- A consumed GRN batch (qty_remaining 0) does not trigger void_has_grn_batch; negative-stock check covers it. Owner decision.
- Real phone/offline POS replay of unit_unknown not run (see lines below).

## Lines for the lead (not edited by me)
- web/ia.js: `rec('guards', ...)` for owner (route key `guards`), script tag `<script src="guards.js"></script>` in web/index.html.
- web/pos.js: add `unit_unknown` and `production_negative_reason_needed` to the BUSINESS regex (line ~75) so a refused queued sale goes to the failed list at once instead of 3 retries; use BOS.guardMsg(code) in the error display (also stock2.js ERR map, rules.js ERRGRANT unaffected).
- Exception labels: stock2.js line ~559 map lacks stock_unit_unknown_late, sell_below_zero_used, production_negative, purchase_void_unsafe, purchase_void_credit (text itself is in the row, so it displays anyway).

## Owner decisions (app recommends, never forces)
1 purchase_grn_guard: recommended skip when source = GRN (else off). 2 purchase_void_guard: recommended refuse. 3 purchase_void_payments: recommended keep. 4 unit_conv_required: refuse only when unit_unknown_items() = 0, else stay warn. 5 neg_grant_log: recommended on. 6 production_negative_reason: recommended required. 7 stock_negative_mode: recommended block after the first stock count/opening exists (stays owner-chosen). 8 link vs skip; 9 whether consumed GRN batches should also block a void.

## Phone-impossible
None added by this step (all SQL paste + app taps). Still open from before: scheduler activation, Meta/edge-function setup.
