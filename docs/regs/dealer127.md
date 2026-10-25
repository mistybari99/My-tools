# Registration for the dealer / hardware-paint business (phases 127-129) - to be applied by the lead

Nothing in web/ia.js, web/index.html, web/nav.js or web/app.js was edited by this work. Apply the lines below. Without them the screens are simply not reachable (the SQL and the tests do not depend on them).

## (a) web/ia.js lines (groups: cheques in `acc`, schemes in `purch`, tinting in `stock`; `ok` uses locOk because the server decides on every call - a stricter `c.GF.dealer_*` test is possible once the lead adds the dealer_* codes to the grant-flag fetch in nav.js)
```js
  rec('cheques', 'acc', ['চেক / PDC খাতা', 'Cheque / PDC register', 'Cheque / PDC খাতা'], { icon: 'money', ok: (c) => c.own || c.locOk(), kw: ['cheque', 'check', 'pdc', 'post dated', 'bounce', 'deposit', 'clear', 'bank', 'চেক', 'পিডিসি', 'বাউন্স', 'জমা', 'ক্লিয়ার'] }),
  rec('schemes', 'purch', ['প্রিন্সিপাল স্কিম ও ক্লেইম', 'Principal schemes & claims', 'Principal scheme ও claim'], { icon: 'doc', ok: (c) => c.own || c.locOk(), kw: ['scheme', 'rebate', 'slab', 'target', 'claim', 'principal', 'asian', 'berger', 'স্কিম', 'রিবেট', 'ক্লেইম', 'প্রিন্সিপাল'] }),
  rec('tinting', 'stock', ['টিন্টিং মেশিন', 'Tinting machine', 'Tinting machine'], { icon: 'settings', ok: (c) => c.own || c.locOk(), kw: ['tint', 'tinting', 'shade', 'colorant', 'base', 'formula', 'paint', 'টিন্ট', 'শেড', 'কালারেন্ট', 'রং'] }),
```
(`acc`, `purch`, `stock` are existing groups; icons `money`, `doc`, `settings` exist.)

## (b) web/index.html: add after `cashmoves.js` (they need `B.s2` from stock2.js, `BOS_APP`, `BOS.L`; any order after stock2.js works)
```html
<script src="cheques127.js"></script><script src="schemes128.js"></script><script src="tinting129.js"></script>
```
Routes: `#/cheques`, `#/schemes`, `#/tinting`. Each is a plain screen: `shell(title, html, true)`, bilingual `L(bn, en, mix)`, every dynamic string through `esc()`, no horizontal scroll at 360px (checked by tests/web/dealer127_test.js). If the build uses lazy loading (tools/web_lazy.json), add the three routes there with their files.

## (c) SQL (supabase/phase127.sql, phase128.sql, phase129.sql - after phase122, in this order; paste twice = no change)
* Rules (module `dealer`, switch, default OFF, visible in #/switchboard): `dealer_cheque_on`, `dealer_scheme_on`, `dealer_tint_on`. While OFF every write function refuses with `feature_off`; reads and the dry-run previews still work.
* Grants (module `dealer`, not given to any role by default): `dealer_cheque_view`, `dealer_cheque_manage`, `dealer_scheme_view`, `dealer_scheme_manage`, `dealer_tint_view`, `dealer_tint_manage`, `dealer_tint_run`. Cost figures of tint jobs: owner or `rpt_cost_ok()` (grants view_cost / view_profit).
* Scope: a user needs the grant AND an explicit assignment (user_locations) to a location of the business; the `management` role bypass of can_loc is NOT used; owner sees every business.
* Tables (RLS on, select policies by business / location, no browser write, audit triggers, no hard delete): dealer_cheques, dealer_cheque_events, dealer_schemes, dealer_scheme_items, dealer_scheme_slabs, dealer_scheme_accruals, dealer_scheme_claims, dealer_scheme_claim_events, dealer_shades, dealer_tint_formulas, dealer_tint_formula_lines, dealer_tint_jobs (cost columns not granted), dealer_tint_job_lines (cost columns not granted).
* One existing object is widened: `sale_payments_mode_check` also allows `bank` (a cleared customer cheque is written as one `collection` row of mode bank; `_acct_paykey` already maps bank to the bank account).
* Functions for the browser: cheque_register / deposit / clear / bounce / cancel / replace / bank_candidates / bank_link / list / events, cheques_due, cheques_bounced, post_dated_exposure, cheque_ledger_check; scheme_save / activate / accrue / close / cancel / list / get, claim_create / receive / reject / cancel / list, scheme_reconciliation; tint_formula_save / retire / list / get, tint_job_run / void / list, tint_customer_shades, tint_job_cost, tint_cost_report. Internal (closed to the browser): `_dl_*127` helpers (except `_dl_ok127` / `_dl_biz_ok127`, which the row policies call), `_cheque_*127`, `_scheme_*128`, `_tint_*129`.
* business_templates: `hardware_paint` and `dealership` get a `modules` list that says what is built and what is NOT built (status stays `not_implemented`; neither template is ready as a whole).
