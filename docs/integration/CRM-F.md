# Integration notes: CRM package F (loyalty extras: points expiry and burn rules, referral, coupons and vouchers, hooks, statement, summary)

Branch files (all new; no existing file was edited, no existing SQL function was re-created):
`supabase/phase316.sql` .. `phase319.sql` and `phase316_test.sql` .. `phase319_test.sql`, `web/crm_loyalty.js`, `web/crm_coupons.js`, `tests/web/crm_loyalty_test.js`,
`tests/sql/crmf_build.sh`, `crmf_before_after.sh`, `crmf_race.sh`, `crmf_oldsuites.sh`, `crmf_after99.sh`, `crmf_run_all.sh`,
`docs/integration/CRM-F.md` (this file), `CRM-F_info.json` (plain-English entries for an (i) info sheet), `CRM-F_hooks.json` (the exact hook texts, proved by the web test).
Not in scope and not built: gift cards that are SOLD for cash (package F2). Sending a message belongs to package D.

## 1. What the owner gets (every item is a SETTING, default = today's behaviour, nothing starts by itself)

| Area | What it does | Where |
|---|---|---|
| Points expiry | Preview (writes nothing), then Apply (writes `expire` rows once). Points earned before the effective-from date count as earned on that date. | phase316, Loyalty extras > Expiry |
| Burn rules | Cap as a percent of the bill, cap in points, step. The till uses the checked redeem; a rule can be passed by the owner / loyalty manager WITH a reason. | phase316 |
| Manual adjustment | The old function already needs a reason and cannot go below zero. The wrapper adds a yellow Exceptions line above an alert size. | phase316 |
| Referral | A code per customer, a link for a new customer, a one-time reward on the new customer's first completed sale; taken back (never below zero) if that sale is voided. | phase317, Referral tab |
| Coupons / vouchers | Percent or amount; validity dates (required), minimum bill, total and per-customer limits, one customer only, scope by outlet / item / item category; every use logged. | phase318, `#/crmcoupons` |
| Voucher liability | OFF. If switched on: a balanced provision with an effective-from date, through `crmf_voucher_liability_sync()`. | phase318 |
| Birthday / anniversary / festival hooks | Rules only: who is due (`crmf_hooks_due`), optional bonus points once per customer per year (`crmf_hook_run`, dry run first). Nothing sends a message. | phase319, Hooks tab |
| Points statement | Opening, each line with a running balance, closing, expiring soon. | `crmf_points_statement`, Statement tab |
| Loyalty summary | Points in / out / expired, outstanding points and their value (information only, not booked), referrals, coupons, hooks, liability held. | `crmf_loyalty_summary`, Summary tab |

## 2. Settings (rules, module `crm`; Switchboard and the settings hub list them by themselves; English labels)

| Key | Kind | Default | At the default |
|---|---|---|---|
| `crm_points_expiry_months` | number 1..120 | blank | points never expire |
| `crm_points_expiry_from` | date text | blank | expiry cannot be applied |
| `crm_points_expiry_warn_days` | number | blank | no warning list |
| `crm_burn_max_percent` | number | blank | no percent cap |
| `crm_burn_max_points` | number | blank | no points cap |
| `crm_burn_step_points` | number | blank | any number of points |
| `crm_points_adjust_alert_over` | number | blank | no alert |
| `crm_referral_on` | switch | OFF | no code, no link, no reward |
| `crm_referral_reward_points` | number | blank | no reward can be given |
| `crm_referral_referred_points` | number | blank | nothing extra for the new customer |
| `crm_referral_min_bill` | number | blank | any first bill counts |
| `crm_voucher_on` | switch | OFF | the till cannot use a coupon (coupons can be prepared) |
| `crm_voucher_max_percent` | number | blank | percent coupons cannot be created |
| `crm_voucher_max_amount` | number | blank | amount coupons cannot be created |
| `crm_voucher_liability_on` | switch | OFF | coupons never touch the books |
| `crm_voucher_liability_from` | date text | blank | liability cannot be switched on |
| `crm_voucher_liability_account` | chart code | blank | cannot be switched on |
| `crm_voucher_expense_account` | chart code | blank | cannot be switched on |
| `crm_hooks_on` | switch | OFF | due list empty, nothing given |

Setting guard (trigger `crmf_rules_guard` on `rules`, only for keys `crm_*`): dates must be real dates; the two account codes must be existing, active, non-group accounts of the right type; the liability switch can go ON only with its date (not in the past at that moment), both accounts, and accounting ON with a start date.
Grants (none given to anyone): `crm_loyalty_manage` (apply expiry, reject a referral, create hooks and run them, pass a burn rule with a reason), `crm_voucher_issue` (create / edit coupons), `crm_coupon_override` (accept a coupon outside its limits with a reason). The owner always may. `customer_manage` keeps its meaning and may PREVIEW expiry and read the lists and reports, not apply. The owner is never hard-coded as an approver.
Exceptions with a reason: burn rule override, coupon override, referral reject, wind down of the voucher liability, a coupon above the maximum (owner only). Each writes an audit line, and (where a bill is involved) a yellow line in the Exceptions list (flag codes `loyalty_burn_override`, `loyalty_adjust_large`, `coupon_refused`, `coupon_override`, `coupon_discount_mismatch`). Never overridable: a retired or used-up coupon, another customer's personal coupon, a bill with nothing in the coupon's scope.

## 3. Accounting

Nothing in this package writes a journal entry, a sale, a payment or stock, EXCEPT `_crmf_liab_post` (called by `crmf_voucher_liability_sync`, the coupon save, the redemption and the void trigger) and only while `crm_voucher_liability_on` is ON. Model (a proposal for the owner and the accountant to confirm, UNTESTED with an accountant):
for an AMOUNT coupon marked "post liability" with a total use limit, issued on or after the effective-from date, the books hold `value x max uses - discount already given` as a provision: Dr the chosen expense account, Cr the chosen liability account; it falls (Dr liability, Cr expense) as the coupon is used, and goes to zero when the coupon expires, is retired, or a sale that used it is voided. Each entry has two lines, Dr = Cr (the one journal writer `_acct_write` refuses anything else), is dated today, source type `crmf_voucher`, never in a closed period. It posts only the difference between what the books hold and what should be held, so running it again posts nothing. `crmf_voucher_liability_wind_down(reason)` moves everything back to zero (use before switching off). The automatic callers turn an error into a warning (a sale or a void is never stopped); `crmf_voucher_liability_sync()` repairs it. These entries are not touched by `acct_post_pending` (it only handles known document types) and `acct_journal_reverse` refuses them (only the package functions move them).
Proof: `tests/sql/crmf_before_after.sh`: with every new setting at its default, 12 report snapshots (P&L, income statement, balance sheet, trial balance, cash flow, day book, journal lines, ...) are identical before and after pasting 316-319 twice, and a second wave of documents plus customer sales with points ON gives identical journal lines, sales rows and points ledger on a twin database without CRM-F; no `crmf` journal entry exists; balance check green.

## 4. Hooks for the integrator (exact text in `CRM-F_hooks.json`; the web test applies every one to a scratch copy and runs the result)

| # | File | Change | Without it |
|---|---|---|---|
| H1 | `web/pos.js` | `B.pos = { flush, normMobile };` becomes `B.pos = { flush, normMobile, ctx: () => ({ loc, lines, sub, customerId, setDiscount }) };  // bosCRMF` | the coupon box has nothing to read; the POS is as today |
| H2 | `web/pos.js` | in `cartSheet()` insert `${B.crmf && B.crmf.posBox ? B.crmf.posBox() : ''}` before the total row | no coupon box |
| H3 | `web/pos.js` | in `submitSale()` after `B.invoice.offer(...)`: `if (B.crmf && B.crmf.afterSale) B.crmf.afterSale(data.id);` | a coupon is checked but its use is never recorded |
| H4 | `web/customers.js` | `customer_points_adjust` -> `crmf_points_adjust` (same arguments) | no alert on a large manual change |
| H5, H6 | `web/customers.js` | `customer_points_redeem` -> `crmf_points_redeem` with `p_bill: null, p_override: null` added (dry run and real) | burn rules not applied on the customers screen |
| H7 | `web/index.html` | `<script src="crm_loyalty.js"></script><script src="crm_coupons.js"></script>` after `customers.js` | the two screens do not load |
| H8 | `web/ia.js` | two `rec(...)` lines (group `cust`, routes `crmloyalty` and `crmcoupons`) before the `tiers` line | the screens have no menu entry (the routes still open by address) |

How the coupon box works (H1-H3, proved in `crm_loyalty_test.js` on a scratch copy of the real POS): the cashier types the code in the cart sheet; "Check" calls `crmf_coupon_check`, which writes nothing; the answer fills the normal discount box (the normal discount rules, limit and approval still apply to that discount); after the sale is sent, `crmf_coupon_redeem_after_sale(code, sale)` records the use and writes a yellow line when the discount on the bill differs from what the coupon gives. `record_sale2` is called with exactly its old arguments (tested). Offline: a sale queued offline does not record its coupon (the server never saw the sale); this is a known limit.
Points burn at the till (a "Use points" step in the cart sheet) is NOT built into `pos.js` by this package: the helper `B.crmf.redeemPoints(customerId, points, bill, note, client, dry, override)` and the server function `crmf_points_redeem(... p_bill ...)` are ready for it (the percent cap needs the bill total, which the customers screen does not have; with a percent cap set the customers screen answers `bill_total_needed`). Referral "Referred by" box: `B.crmf.referralApply(customerId, code, client)` and `B.crmf.referralCode(customerId)` are ready; the box itself is a pos.js job for the integrator (UNTESTED in the UI).
Plain-English error texts for the integrator's own screens: `B.crmf.errText(error)`.

## 5. Paste order and re-paste hazard

Needs phase43 and phase40 (and everything through phase98). Paste 316, 317, 318, 319 after phase99 (also tested before 99: both orders pass). Add to `tests/sql/ORDER.txt` after `phase99`: `phase316 phase317 phase318 phase319`. Paste twice is safe (tested; functions byte for byte identical). No existing function is re-created, so re-pasting an old phase (8, 43, 40, ...) does not remove anything of CRM-F, and CRM-F removes nothing of theirs; no `_m_patch` marker is needed. Re-pasting phase316 after 318 is safe (the setting guard lives in 316 with its complete body).
Two additive things touch existing tables: the points ledger reason check also accepts `referral` and `bonus` (the table stays append-only, old rows unchanged); three triggers on `sales` (`sales_referral_crmf`, `sales_referral_void_crmf`, `sales_void_coupon_crmf`) that return at once while their switch is OFF and turn any error into a warning. One trigger on `rules` (`crmf_rules_guard`, keys `crm_*` only).

## 6. Tests (local throwaway Postgres 16 on port 5574; the live Supabase was never touched)

| Suite | Result |
|---|---|
| `phase316_test.sql` (expiry, burn, adjust alert, helpers; negative: no permission, below zero, bad date, replay) | 62 pass, 0 fail |
| `phase317_test.sql` (referral: off, blank reward, min bill, first sale only, void take-back capped, loyalty off, reject, no permission) | 37 pass, 0 fail |
| `phase318_test.sql` (coupons: reuse, expired, not started, wrong outlet, item / category scope, personal, cap, override, used up, void frees a use, mismatch, no permission; liability: off, guards, issue, use, void, expiry, closed period, wind down, balanced) | 102 pass, 0 fail |
| `phase319_test.sql` (hooks, statement, summary, status) | 43 pass, 0 fail |
| `crmf_before_after.sh` | 12 snapshots identical, twins equal, RESULT all equal |
| `crmf_race.sh` (two sessions, last use of a coupon; same customer, per-customer limit 1) | exactly one wins in both |
| `crmf_oldsuites.sh` (phase 43, 62, 76, 81 with and without CRM-F) | identical lines (144, 74, 108, 110 pass) |
| `crmf_after99.sh` (build through phase 99, paste 316-319 twice, run the four suites) | all four pass |
| `tests/web/crm_loyalty_test.js` (Playwright, mocked RPCs, 360 px, three language modes, storage blocked, hooks on scratch copies of pos.js / customers.js / index.html / ia.js including the till flow) | 94 pass, 0 fail, no console errors |
`ia_test` passes on the real tree (nothing in the real tree was edited). Run everything: `PORT=5574 bash tests/sql/crmf_run_all.sh`; web: `node tests/web/crm_loyalty_test.js <abs tests/web>`.

## 7. UNTESTED / not confirmed

- A real phone, a real Supabase project, real money. The web screens ran only against mocked RPCs.
- The voucher-liability accounting treatment with the owner's accountant (provision model above). The owner decides whether to switch it on at all.
- Points burn step and the "Referred by" box inside the real POS UI (helpers and server functions are tested; the UI parts are not built).
- Offline POS sale with a coupon (not recorded).
- FIFO of points is not tracked: expiry assumes the oldest points are spent first (the kinder reading), stated on the screen.
- Sending a message about expiry, birthdays or coupons (package D); a scheduler for `crmf_hook_run` or `crmf_voucher_liability_sync` (package E / integrator; today both are buttons).
- Bangla labels: English only for now (owner decision OD-C1); the L() wrapper keeps the slots.

## 8. BUILD-LOG entry for the integrator to paste (rule 16)

"phase316-319 (CRM-F loyalty extras): points expiry (preview then apply, effective-from date), burn rules, referral codes and rewards, coupons and vouchers (percent / amount, validity, minimum bill, limits, outlet / item scope, redemption log, overrides with a reason), optional voucher liability (OFF, balanced, effective-from date), birthday / anniversary / festival hook rules, points statement, loyalty summary. 19 settings, all OFF or blank. No existing function edited. Hooks H1-H8 in docs/integration/CRM-F_hooks.json. Not confirmed: real phone / Supabase, accountant sign-off on the liability model, POS UI for points burn and referral box, offline coupon."
