# Integration note W1-F: chart and mapping completeness (U-09) and customer receipt channels (U-10)

SQL numbers: **phase96** (needs phase87) and **phase97** (needs phase96). Paste in that order, after phase87 and after any other Wave 1 phase (no ordering clash: nothing here is edited elsewhere). Both are paste-twice safe. No existing file was edited. New files:
`supabase/phase96.sql`, `supabase/phase97.sql`, `supabase/phase96_test.sql`, `supabase/phase97_test.sql`, `web/otherincome.js`, `tests/web/otherincome_test.js`, `tests/sql/w1f_hooks96.sql`, `tests/sql/w1f_hooks97.sql`, `tests/sql/w1f_fixture.sql`, `tests/sql/w1f_snap.sql`, `tests/sql/phase97_before_after.sh`, this note.

Nothing in a shared function is changed by the two phases. Until the integrator pastes the hooks in section 3 the new features are **recorded but not yet in the books**: other income is stored but not posted, a bank receipt is stored with its account but posts to the generic bank account, the POS refuses `bank`. Every hook was proved on a scratch copy inside the tests (applied in a transaction that is rolled back); the committed database never carries a `bos96` / `bos97` marker.

## 1. What the phases do

| Phase | Item | Content |
|---|---|---|
| 96 | U-09 | Seed catalogue `w1f_seed_state` (13 keys): `exp_rent` 5300, `exp_utilities` 5400, `exp_marketing` 5500, `other_income` 4900 (existing accounts: only the mapping key is added); new accounts `courier_receivable` 1250, `staff_deposit` 2700, `purchase_discount` 4910, `rounding` 5880, `bad_debt` 5890, `disposal_gain` 4920, `disposal_loss` 5895, `vat_payable` 2800 and `wht_payable` 2810 (the last two are inactive placeholders and get their mapping key the day the owner switches them on). An existing account, mapping or code is never touched: the row becomes `code_taken`, `type_mismatch`, `owner_mapping_kept` or `history_exists` and the owner chooses. Expense heads `rent`, `utilities`, `marketing` are added to `expense_heads` as RETIRED rows. New list `other_income_heads` (scrap sale, used oil, rent received, supplier discount, other). Table `other_income`, entry / void / list, journal source `_w1f_docs`, day book rows `_w1f_daybook_rows`, mapping coverage `_w1f_mapping_coverage`. |
| 97 | U-10 | `sale_payments.mode` and `sales.pay_mode` accept `bank` (constraints widened). New columns `sale_payments.money_account_id`, `cheque_no`, `cheque_date`, `ref_waiver`. Two new money events `customer_collection` and `pos_split_payment` (behave exactly like the 14 phase87 events: default account, owner-fixed source, source required, one-off owner exception). BEFORE INSERT trigger `w1f_sp_bi` on `sale_payments` (reads the in-band tag `ma#<id>;` that `web/pay.js` already sends, or the column; mode follows the account; refuses bank while OFF; reference rule). New route `_w1f_collect_payment`. Readers `_w1f_receipt_settings`, `_w1f_receipts_list`. |

Chart codes cannot change (phase40 guard `account_fixed`, BUILD-RULES "a code is never given to anything else"). "Owner can use another code" is therefore `_w1f_seed_new_code`: a new account with the owner's code takes over the key, the old one is switched off when it has no postings (otherwise it stays, history never moves). Names, active flag, mapping and heads are editable with `_w1f_seed_edit`, `_w1f_seed_map`, `_w1f_expense_head_set`, `_w1f_other_income_head_set`; each writes `audit_log`.

## 2. Settings added (all through `rules`; every change is an `audit_log` line by the rules trigger)

| Key | Default | Meaning |
|---|---|---|
| `other_income_on` | OFF | the Other income entry refuses everything while OFF |
| `other_income_from` | blank | entries dated before this day are refused (blank = any date) |
| `receipt_bank_on` | OFF | bank / cheque accepted as a customer channel (OFF = today: `bad_mode`) |
| `receipt_ref_required` | `off` | `off` / `bank` (bank and cheque need a transaction or cheque number) / `bank_mobile` (mobile wallet too) |
| `receipt_ref_from` | blank | the reference rule counts only for payments dated on or after this day |
| event `other_income`, `customer_collection`, `pos_split_payment` (`money_event_settings`) | no default account, override allowed, source not required | set on Money Accounts > Payment defaults |

Exceptions (owner rule 3): a missing reference is waived per payment with a written reason (`exception_reason`, stored in `sale_payments.ref_waiver`): `audit_log` line `receipt_reference_waived` + a yellow row in the Exceptions list (`exceptions`, flag `receipt_reference_waived`). A seed recode, a key re-pointed to another account and an expense head mapped while older unposted documents exist need a reason and write `audit_log` + a yellow Exceptions row (`chart_code_replaced`, `chart_mapping_changed`, `expense_head_history`). The phase87 exception grants (`require_source`, `override`) work unchanged for the two receipt events and for `other_income`.

Owner rule 2 (nothing historic moves): `tests/sql/phase97_before_after.sh` pastes phase96 + phase97 (twice) on a database with the phase87 fixture plus an unposted voucher with head `utilities`, an unposted quick expense with head `marketing`, cash and mobile collections and a POS split sale, and compares 19 snapshots (P&L, income statement, balance sheet, trial balance, cash flow, day book, day book vs journal, journal lines, balance check, posting dry run, the account every unposted document would post to, payments, dues): 0 differ. A second wave of ordinary documents on that database and on a twin without the phases gives identical reports. The two heads with older unposted documents are NOT mapped by the seed (`history_exists`), so their figures stay on Other expenses.

## 3. Hooks for the integrator (exact text)

Helper: `_w1f_patch(fn regprocedure, pairs text[], marker text)` (phase96). Phase87 `_m_patch` is a no-op on every function that already carries `bos87` (all of the shared ones), so it cannot be reused; `_w1f_patch` has the same behaviour with the marker as a parameter (stops if a site is missing, marker = no-op on a second paste). The integrator may fold both into the wave's own patch helper. Both files below are the exact text the tests apply on a scratch copy. Apply them as the last statements of the wave, after the other packages' patches (each site is a small anchor that stays valid after the other packages' additions at the same function, because every package appends a line and keeps the anchor text). Re-pasting an older phase (13, 40, 50, 52, 79, 80, 82, 85, 86, 87) removes the patched functions: paste the hook files again (marker `bos96` / `bos97`).

| Hook | Function | Why | Without it |
|---|---|---|---|
| H96-1 | `_acct_docs` | journal source `_w1f_docs` (other income) | other income is recorded, never posted |
| H96-2 | `_daybook_lines` | `_w1f_daybook_rows` (other income) | not in the day book |
| H96-3 | `_e_balance_check` | line `mapping_coverage` (amber, never red) | no coverage line |
| H96-4 | `acct_cash_flow` | legacy wallets 1131-1134 (`d_wallet_*` keys) count as cash | with `d_wallet_split_on` the closing cash misses the wallet balances (A-17, proved in phase96_test T6: 500 missing) |
| H96-5 | `daybook_vs_journal` | same legacy wallets | the wallet split shows as a difference (`d_wallet_split`, mobile) |
| H97-1 | `_acct_docs` | a sale payment and a collection post to the payment's own money account (`_m_key(p.money_account_id, ...)`) | they post to the generic cash / bank / mobile accounts |
| H97-2 | `_daybook_lines` | day book line names the account and the cheque number | plain text as before |
| H97-3 | `collect_payment` | the old route accepts bank, cheque, account, reference, exception reason | use the new route `_w1f_collect_payment` from the screen instead |
| H97-4 | `record_sale2` | POS split payments accept `bank` with cheque fields and account | the POS keeps refusing `bank`; a card payment tied to a bank account through the in-band tag already works without this hook |

H97-3 and H97-4 read `_w1f_receipt_modes()` (`cash, mobile, card` plus `bank` only while `receipt_bank_on` is ON), so the old behaviour returns when the switch is OFF (tested: H5).

### tests/sql/w1f_hooks96.sql

```sql
-- W1-F hooks for phase 96 (marker bos96). THESE ARE NOT PART OF phase96.sql: the wave integrator pastes them (docs/integration/W1-F.md section 2).
-- phase96_test.sql runs this file inside a transaction that is rolled back, so the patched shared functions only ever exist on a scratch copy.
-- Every pair is [old exact text, new exact text]. A missing site stops the paste (nothing half changed). Paste twice = no-op (marker bos96).

-- H96-1 _acct_docs: the journal source of other income
select public._w1f_patch('public._acct_docs(date)'::regprocedure, array[
  $a$return query select * from public._m_docs(p_start); /* bos87: transfers and charges between money accounts */$a$,
  $a$return query select * from public._m_docs(p_start); /* bos87: transfers and charges between money accounts */
  return query select * from public._w1f_docs(p_start); /* bos96: other income */$a$], 'bos96');

-- H96-2 _daybook_lines: other income rows in the day book
select public._w1f_patch('public._daybook_lines(integer[],integer[],date,date)'::regprocedure, array[
  $a$union all select * from public._m_daybook_rows(p_locs, p_from, p_to) /* bos87 */;$a$,
  $a$union all select * from public._m_daybook_rows(p_locs, p_from, p_to) /* bos87 */
  union all select * from public._w1f_daybook_rows(p_locs, p_from, p_to) /* bos96 */;$a$], 'bos96');

-- H96-3 _e_balance_check: the mapping coverage line (amber, never red)
select public._w1f_patch('public._e_balance_check(date,integer,integer)'::regprocedure, array[
  $a$  red := not (eq ->> 'ok')::boolean or not (trial ->> 'ok')::boolean or jr_n > 0 or st_n > 0 or coalesce((mnc ->> 'red')::boolean, false);$a$,
  $a$  begin   -- bos96: mapping coverage (amber): every key the posting needs points to an active account
    xc := xc || jsonb_build_object('mapping_coverage', public._w1f_mapping_coverage());
    if not coalesce((xc #>> '{mapping_coverage,ok}')::boolean, true) then warn := warn || to_jsonb('mapping_coverage'::text); end if;
  exception when others then xc := xc || jsonb_build_object('mapping_coverage', jsonb_build_object('ran', false, 'skipped', sqlerrm));
  end;
  red := not (eq ->> 'ok')::boolean or not (trial ->> 'ok')::boolean or jr_n > 0 or st_n > 0 or coalesce((mnc ->> 'red')::boolean, false);$a$], 'bos96');

-- H96-4 acct_cash_flow: the legacy wallets 1131-1134 (keys d_wallet_*) are cash too
select public._w1f_patch('public.acct_cash_flow(date,date,integer)'::regprocedure, array[
  $a$union select coa_account_id from public.money_accounts) z; /* bos87 */$a$,
  $a$union select coa_account_id from public.money_accounts union select account_id from public.acct_mappings where key like 'd\_wallet\_%' /* bos96: legacy wallets */) z; /* bos87 */$a$], 'bos96');

-- H96-5 daybook_vs_journal: the same legacy wallets, so a wallet split does not show as a difference
select public._w1f_patch('public.daybook_vs_journal(date,date,integer)'::regprocedure, array[
  $a$from public.acct_mappings m0 union select ma.coa_account_id$a$,
  $a$from public.acct_mappings m0 union select w0.account_id, 'pay_mobile' from public.acct_mappings w0 where w0.key like 'd\_wallet\_%' /* bos96: legacy wallets */ union select ma.coa_account_id$a$], 'bos96');
```

### tests/sql/w1f_hooks97.sql

```sql
-- W1-F hooks for phase 97 (marker bos97). THESE ARE NOT PART OF phase97.sql: the wave integrator pastes them (docs/integration/W1-F.md section 3).
-- phase97_test.sql runs this file inside a transaction that is rolled back, so the patched shared functions only ever exist on a scratch copy.
-- Every pair is [old exact text, new exact text]. A missing site stops the paste (nothing half changed). Paste twice = no-op (marker bos97).

-- H97-1 _acct_docs: a sale payment and a collection post to the payment's own money account when it has one (generic cash / bank / mobile account otherwise, exactly as before)
select public._w1f_patch('public._acct_docs(date)'::regprocedure, array[
  $a$jsonb_build_object('a', 'pay_' || p.mode, 'd', sum(p.amount)) j from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided group by p.mode$a$,
  $a$jsonb_build_object('a', public._m_key(p.money_account_id, 'pay_' || p.mode) /* bos97 */, 'd', sum(p.amount)) j from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided group by p.mode, p.money_account_id$a$,
  $a$case when not p.voided then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(p.mode), 'd', p.amount),$a$,
  $a$case when not p.voided then jsonb_build_array(jsonb_build_object('a', public._m_key(p.money_account_id, public._acct_paykey(p.mode)) /* bos97 */, 'd', p.amount),$a$], 'bos97');

-- H97-2 _daybook_lines: the day book line of a customer receipt names the money account and the cheque number
select public._w1f_patch('public._daybook_lines(integer[],integer[],date,date)'::regprocedure, array[
  $a$nullif(btrim(concat_ws(' · ', c.name, p.wallet, p.ref)), ''), p.created_staff, p.paid_at,$a$,
  $a$nullif(btrim(concat_ws(' · ', c.name, coalesce(public._m_name(p.money_account_id), p.wallet), p.ref, case when p.cheque_no is not null then 'cheque ' || p.cheque_no end) /* bos97 */), ''), p.created_staff, p.paid_at,$a$], 'bos97');

-- H97-3 collect_payment: the old route accepts the same channels as _w1f_collect_payment (optional: the screen can call the new route instead)
select public._w1f_patch('public.collect_payment(uuid,integer,uuid,jsonb,text)'::regprocedure, array[
  $a$if pm is null or pm not in ('cash', 'mobile', 'card') then raise exception 'bad_mode'; end if;$a$,
  $a$if pm is null or pm <> all (public._w1f_receipt_modes()) /* bos97 */ then raise exception 'bad_mode'; end if;$a$,
  $a$insert into public.sale_payments (sale_id, customer_id, location_id, kind, mode, wallet, ref, amount, note, created_by, created_staff, client_id)$a$,
  $a$insert into public.sale_payments (sale_id, customer_id, location_id, kind, mode, wallet, ref, cheque_no, cheque_date, money_account_id, ref_waiver, amount, note, created_by, created_staff, client_id) /* bos97 */$a$,
  $a$left(nullif(pay->>'ref', ''), 60), round((pay->>'amount')::numeric, 2),$a$,
  $a$left(nullif(pay->>'ref', ''), 60), public._w1f_pj_text(pay, 'cheque_no', 40), public._w1f_pj_date(pay, 'cheque_date'), public._w1f_pj_acc(pay), public._w1f_pj_text(pay, 'exception_reason', 200), round((pay->>'amount')::numeric, 2),$a$], 'bos97');

-- H97-4 record_sale2: POS split payments accept bank (and cheque) and carry the payment source and the reference fields
select public._w1f_patch('public.record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamptz,text,numeric)'::regprocedure, array[
  $a$if pm is null or pm not in ('cash', 'mobile', 'card') then raise exception 'bad_mode'; end if;$a$,
  $a$if pm is null or pm <> all (public._w1f_receipt_modes()) /* bos97 */ then raise exception 'bad_mode'; end if;$a$,
  $a$insert into public.sale_payments (sale_id, customer_id, location_id, kind, mode, wallet, ref, amount, paid_at, created_by, created_staff)$a$,
  $a$insert into public.sale_payments (sale_id, customer_id, location_id, kind, mode, wallet, ref, cheque_no, cheque_date, money_account_id, ref_waiver, amount, paid_at, created_by, created_staff) /* bos97 */$a$,
  $a$left(nullif(pay->>'ref', ''), 60), round((pay->>'amount')::numeric, 2), at_,$a$,
  $a$left(nullif(pay->>'ref', ''), 60), public._w1f_pj_text(pay, 'cheque_no', 40), public._w1f_pj_date(pay, 'cheque_date'), public._w1f_pj_acc(pay), public._w1f_pj_text(pay, 'exception_reason', 200), round((pay->>'amount')::numeric, 2), at_,$a$], 'bos97');
```

## 4. Web hooks (integrator-owned files)

- `web/index.html`: add `<script src="otherincome.js"></script>` after `moneysrc.js` and `settings2.js` (the file reads `BOS.s2.uploadPhoto` only when a photo is picked, and `BOS.moneySrc` when present).
- `web/sw.js`: precache `otherincome.js` if the other screen files are listed [not checked].
- `web/ia.js` (next to the `moneyaccounts` / `dues` records; `pos` is the helper `dues` uses). The test `tests/web/otherincome_test.js` injects exactly these two lines:

```js
  rec('otherincome', 'acc', ['Other income', 'Other income', 'Other income'], { icon: 'money', ok: (c) => c.own || c.GF.cash_move === true || c.GF.accounts_view === true || c.GF.accounts_manage === true, kw: ['other income', 'scrap', 'old oil', 'rent received', 'chart', 'expense heads'] }),
  rec('bankreceipt', 'cust', ['Bank & cheque receipts', 'Bank & cheque receipts', 'Bank & cheque receipts'], { icon: 'money', ok: pos, kw: ['bank receipt', 'cheque', 'bank transfer', 'customer payment'] }),
```
  Run `node tests/web/ia_test.js <abs tests/web>` plus nav, nav2, control, favsync, settings2 (the record count in `ia_test` may need +2). Do not rename the routes `otherincome`, `bankreceipt`.
- `web/pay.js` (shared payment rows, used by POS and dues): add `['bank', L('ব্যাংক', 'Bank transfer')]` and a cheque row (mode `bank` + `cheque_no`, `cheque_date`) to `MODES` only when `BOS.receiptCfg.bank_on` (read once from `_w1f_receipt_settings`), send `ref` for bank rows too, and set `st.moneyEvent = 'customer_collection'` (dues) or `'pos_split_payment'` (POS) so the existing `B.moneySrc.rowSelect` and `taggedWallet` carry the account. `list()` must send `cheque_no`, `cheque_date`, `exception_reason` for those rows.
- `web/dues.js`: call `_w1f_collect_payment` (same arguments as `collect_payment`) instead of `collect_payment`, or keep `collect_payment` after hook H97-3.
- `web/pos.js`: nothing beyond the pay.js rows once H97-4 is in. `web/salereturn.js`, `web/cashmoves.js`: unchanged.

## 5. Tests and results (local Postgres 16, port 5566, fresh build through phase87)

| Suite | Result |
|---|---|
| `supabase/phase96_test.sql` (build: phase87 + phase96) | 127 pass, 0 fail |
| `supabase/phase97_test.sql` (build: phase87 + phase96 + phase97) | 79 pass, 0 fail |
| `tests/sql/phase97_before_after.sh` | 19 snapshots, 0 differ; wave 2: 9 reports equal with and without the phases |
| `node tests/web/otherincome_test.js $PWD/tests/web` | 86 asserts, 0 fail, no console errors (360x780, en / bn / mix) |
| Older SQL suites, same test on a build through phase87 vs through phase97 (10, 12, 14, 19, 20, 22, 23, 40, 43, 49, 81-87) | identical failing sets (baseline fails unchanged) except **phase87_test T0**, which counts exactly 14 money event settings: it now sees 17 (three new events are the point of this package). Expected and harmless; the integrator may relax that one count. |

Negative tests included: salesperson / storekeeper refused on the server, owner-only head changes, bad head code, wrong account type, group account, unknown and inactive money account, account of another place, fixed source, source required, duplicate client id, other user's client id, overpaid, zero / negative / NaN-like amounts, bad cheque date, cheque number on a non-bank payment, bank while OFF (new route, old route, direct insert), reference missing / too-short reason / waived with reason, closed period, start date, update and delete of a recorded row, code taken, history guard, unbalanced check (every suite ends with `tt.unbalanced() = 0`), second paste changes nothing.

## 6. Hazards and what was NOT done

- Hooks are not applied by the phases; the features stay dormant (recorded, not posted) until the integrator pastes them. The registry lines and script tag are the integrator's.
- `_m_src` (the phase87 register of payments per account) and `_m_linked_types()` were not hooked: a customer receipt reaches the account statement and the Balance Check "money accounts" line when it is POSTED (it does not appear under "not posted yet", and the blind real-balance check ignores it until posted). `_m_prove` stays green because the journal source types `sale` and `collection` are not in the linked list.
- The shared poster resolver `_acct_resolve` has no date. Turning an expense head ON therefore cannot be dated: the guard refuses (or needs a reason) while older documents with that head are unposted, and the seed leaves such heads unmapped (`history_exists`). Posting those documents first (Accounts > Post now) removes the block.
- A card payment tied to a bank money account is stored as a bank receipt of that account (phase87 rule, also for the in-band tag); it then does not go through Card receivable 1140. Card settlement and fees remain U-20.
- Unverified: real Supabase, a real phone, the real `ia.js` registry (injected lines only), `pay.js` / `pos.js` / `dues.js` changes (not written), the printed receipt text for bank / cheque, the Bangla wording (English only by owner decision).
- `phase84_test_project_only.sql` was not needed and not used.

## 7. Owner decisions this package depends on

OD-2 (payment mix: count payments by mode for 30 days; bank mode is built, card settlement only for modes with real volume) and OD-16 (which expense heads, other income heads and account names the owner confirms: the seed names are proposals; heads are OFF until turned on).
