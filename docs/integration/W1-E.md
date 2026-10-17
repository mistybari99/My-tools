# Integration note W1-E: cash and payment controls (U-07) and journal, chart and mapping controls (U-08)

SQL numbers: **phase94** (U-07) and **phase95** (U-08) only. Paste after phase87, in this order: 94, 95. Both are paste-twice safe. No existing file was edited (no old phase, no shared function, no web file, no BUILD-LOG). Test data only (`test_*`).

Package files: `supabase/phase94.sql`, `supabase/phase95.sql`, `supabase/phase94_test.sql`, `supabase/phase95_test.sql`, `tests/sql/phase94_95_before_after.sh`, `web/moneycontrols.js`, `tests/web/moneycontrols_test.js`, this note.

## 1. What the package does and what needs no hook

| Control | How it is enforced | Hook needed |
|---|---|---|
| Owner draw / owner top-up by someone who is not the owner (`owner_money_entry_mode`) | BEFORE INSERT trigger `a94_w1e_cash_bi` on `cash_moves` (sorts before phase87's `aa87_money_src_bi`). `approval`: the row is held in `w1e_requests` with the same id and client id, nothing is posted, nothing is in the day book. | none (optional H2 only changes the answer text) |
| Bank slip required, large and back-dated bank moves | same trigger | none |
| Duplicate vendor (name, mobile, TIN) | trigger `a94_w1e_supplier_bi` on `suppliers` | none |
| One pay account per employee, red line on change | trigger `a94_w1e_employee_bi` on `employees` | none |
| Place of every line of a manual journal (`journal_loc_check`) | BEFORE INSERT trigger `a95_w1e_jl_bi` on `journal_lines` (manual, non-reversal entries only; automatic postings are never touched) | none |
| Mapping type guard (`mapping_type_guard`) | trigger `a95_w1e_mapping_bi` on `acct_mappings`, table `w1e_mapping_types` (35 seeded rows, owner editable, switched off never deleted) | none |
| Repeat supplier payment, supplier payment above the limit (`supplier_pay_dup_mode`, `supplier_pay_over`) | `_w1e_pay_gate(...)`, needs the exact total of the whole call | **H1 pay_supplier** |
| Attachment above a total, manual journal on a control account (`journal_attach_over`, `journal_control_acct_mode`) | `_w1e_journal_gate(...)`, needs the resolved lines and the total | **H3 acct_journal_post** |

Without H1 and H3 everything else works and those four settings simply do nothing (the screen shows "waiting for the hook" chips, read from `w1e_state().hooks`).

## 2. Settings added (table `rules`, module `books`, English label and hint, owner editable, every change in `audit_log` through the existing `audit_rules` trigger)

All defaults keep TODAY'S behaviour (owner standing rules 1 and 2). The recommended value is in each hint.

| Key | Kind | Default | Meaning |
|---|---|---|---|
| `owner_money_entry_mode` | choice open / approval / owner | **open** | who may record owner draw and owner top-up |
| `bank_slip_required` | switch | **off** | slip number mandatory in the Reference of bank deposit / withdraw |
| `bank_move_large_over` | number Tk | blank = off | yellow exception for a bank move above this amount |
| `bank_move_backdate_days` | number days | blank = off | yellow exception when dated more days back |
| `supplier_pay_dup_mode` | choice off / flag / block | **off** | same supplier + same total again |
| `supplier_pay_dup_hours` | number hours | blank = same calendar day | window of the check |
| `supplier_pay_over` | number Tk | blank = off | non-owner payment above this waits for the approver |
| `supplier_dup_mode` | choice off / warn / block | **off** | second supplier with same name, mobile or TIN |
| `employee_pay_dup_mode` | choice off / warn / block | **off** | two employees on one bank account or wallet number |
| `employee_pay_change_flag` | switch | **off** | red exception when a pay account is changed |
| `journal_loc_check` | switch | **off** | place of every manual journal line |
| `mapping_type_guard` | switch | **off** | account type of a mapping |
| `journal_attach_over` | number Tk | blank = off | attachment above this total |
| `journal_control_acct_mode` | choice allow / request / block | **allow** | non-owner journal on cash, bank, receivable, payable, inventory |
| `journal_control_prefixes` | text | `11,1210,13,2100` | chart code beginnings that count as control accounts |

Deviation from the plan table (section 2.1 U-07, U-08), on purpose: the plan shows `owner only`, `bank_slip_required (on)` and `request` as defaults. The owner's standing rules say a new policy choice defaults to today's behaviour and switches on only by setting, so the defaults above are the old behaviour. Today a cashier with the `cash_move` grant CAN record an owner draw, so "keeps today" for `owner_money_entry_mode` is `open`. The owner (or the integrator, on the owner's yes) sets `approval` / `owner`, `bank_slip_required` on and `journal_control_acct_mode` `request` when ready. Proof that the defaults change nothing and that switching everything on never moves a historic figure: `tests/sql/phase94_95_before_after.sh` (section 7).

`purchase_separate_poster` (phase10, default off, owner still allowed) already exists. It is NOT flipped here (it would change today's behaviour); the screen lists it with the others so the owner can switch it on.

## 3. Approver and exceptions (nothing hard-coded)

- A held request (`owner_money`, `supplier_pay`, `journal_control`) is decided by: the approver the owner set for that ONE request (`w1e_request_approver_set`: a person or a role, reason required, never the maker) or, otherwise, the approver chosen under phase87 `owner_approval_mode_set2` (mode `named`: its role and/or people; modes `self`, `logged`, `off`: an owner). The maker never decides his own request, also not the owner (`self_approval`). In `named` mode the owner is not an approver; he can allow ONE approver exception (`money_exception_grant('approver', reason, himself, null, 'w1e_owner_money')`), which writes `audit_log` and an `approver_exception` line, or return to `self` (phase87 recovery path).
- One-off overrides for every blocking control reuse the phase87 mechanism: `money_exception_grant('override', reason, for_user | client, event)` with event `w1e_owner_money`, `w1e_bank_slip`, `w1e_dup_payment`, `w1e_pay_over`, `w1e_vendor_dup`, `w1e_pay_account`, `w1e_journal_loc`, `w1e_journal_attach`, `w1e_journal_control`, `w1e_mapping`. Reason required, used once, `audit_log` line `money_exception_used`, Exceptions row `override_exception`. A journal that does not balance is never excepted (`unbalanced` is raised before the gate).
- New Exceptions kinds (added to the phase87 check list by `_w1e_add_exc_kinds`, which READS the current list and only adds, so another package that adds kinds the same way cannot lose them): `w1e_bank_move_flag`, `w1e_duplicate_payment`, `w1e_pay_over_request`, `w1e_vendor_duplicate`, `w1e_pay_account_duplicate` (red), `w1e_pay_account_changed` (red), `w1e_owner_money_request`, `w1e_journal_request`. `w1e_exceptions_list()` returns them (and the overrides with a `w1e_*` event) with a `level` of red or yellow. The existing Exceptions screen (`money_exceptions_list`) lists them too. Hazard: if any other phase REPLACES that check with a fixed list (instead of adding to the current one), these kinds disappear and the controls fail with a check violation; the re-patch phase should call `select public._w1e_add_exc_kinds(array['w1e_bank_move_flag','w1e_duplicate_payment','w1e_pay_over_request','w1e_vendor_duplicate','w1e_pay_account_duplicate','w1e_pay_account_changed','w1e_owner_money_request','w1e_journal_request'])` again (idempotent).

## 4. Hooks (integrator). Use `_m_patch`; it reads the live definition, patches by exact text, stops if a site is missing. Run each call ONCE in the wave's re-patch phase (the last phase of the wave), after phases 94 and 95.

The three calls below are exactly the ones executed and proved in `phase94_test.sql` (T6, T9) and `phase95_test.sql` (T4) on the scratch database. The tests restore the original function bodies at the end, so the shared functions are not patched by this package.

### H1 `pay_supplier` (marker `w1e94`)

```sql
select public._m_patch('public.pay_supplier(uuid,integer,jsonb,uuid,text)'::regprocedure, array[
 $h$declare pay jsonb; pm text; amt numeric; tot numeric := 0; bal numeric; sid text; dupby uuid;$h$,
 $h$declare pay jsonb; pm text; amt numeric; tot numeric := 0; bal numeric; sid text; dupby uuid; gate jsonb; /* bos87 w1e94 */$h$,
 $h$  if tot > bal then raise exception 'overpaid'; end if;
$h$,
 $h$  if tot > bal then raise exception 'overpaid'; end if;
  gate := public._w1e_pay_gate(p_supplier, p_loc, p_payments, p_client, p_note, tot);
  if gate is not null then return gate; end if;
$h$]);
```
Effect: when a payment must wait, `pay_supplier` returns `{"pending": true, "request_id": n, "paid": 0, "balance": <unchanged>}` and writes nothing. `purchase.js` (integrator file) should read `pending` and show "Waiting for the approver" instead of "Paid". The pay-at-bill payments of `_post_purchase_p13` (rows with a bill) are never held or compared.

### H2 `cash_move_add` (marker `w1e94c`, display only; the control works without it)

```sql
select public._m_patch('public.cash_move_add(integer,text,numeric,date,text,uuid,text,text,uuid,boolean)'::regprocedure, array[
 $h$  return jsonb_build_object('id', id_, 'kind', p_kind, 'amount', round(p_amount, 2));$h$,
 $h$  return jsonb_build_object('id', id_, 'kind', p_kind, 'amount', round(p_amount, 2)) || public._w1e_cash_pending(id_); /* bos87 w1e94c */$h$]);
```
Effect: a held owner-money entry answers `{"id": .., "pending": true, "request_id": n}`. `cashmoves.js` should show "Waiting for the approver" when `pending` is true (the held row is not in the list because it is not in `cash_moves` yet).

### H3 `acct_journal_post` (marker `w1e95`)

```sql
select public._m_patch('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)'::regprocedure, array[
 $h$declare st date := public._acct_start(); r public.journal_entries; ln jsonb; id_ bigint; td numeric := 0; tc numeric := 0; x jsonb;$h$,
 $h$declare st date := public._acct_start(); r public.journal_entries; ln jsonb; id_ bigint; td numeric := 0; tc numeric := 0; x jsonb; gate jsonb; /* bos87 w1e95 */$h$,
 $h$  id_ := public._acct_write(p_date, p_loc, 'manual', coalesce(p_client::text, gen_random_uuid()::text), null, p_memo, null, ln, null, p_client, p_photo);$h$,
 $h$  gate := public._w1e_journal_gate(p_date, p_loc, p_memo, ln, p_photo, p_client, td);
  if gate is not null then return gate; end if;
  id_ := public._acct_write(p_date, p_loc, 'manual', coalesce(p_client::text, gen_random_uuid()::text), null, p_memo, null, ln, null, p_client, p_photo);$h$]);
```
Effect: errors `attachment_required`, `control_account_blocked`; a held journal answers `{"pending": true, "request_id": n, "total": ..}`. `accounts.js` (integrator file) should show "Waiting for the approver" for `pending`. Dry runs and the balance check run before the gate, so an unbalanced journal is refused first.

Hook notes and hazards:
- `_m_patch` is a no-op (returns false) on a function that already carries the text `bos87`, and the new text MUST carry `bos87` (the markers above do). If another package also patches `pay_supplier`, `cash_move_add` or `acct_journal_post` through `_m_patch` in the same wave, merge the pairs into ONE call, or the second call is silently skipped.
- Re-pasting phase10 (`pay_supplier`), phase23 (`cash_move_add`) or phase40 (`acct_journal_post`) removes the hook: run the call again. The triggers of phases 94 and 95 sit on tables and survive a re-paste of old phases. `w1e_state().hooks` shows which hooks are present; `phase99_test.sql` may assert it.
- The shared functions' original bodies were read from the phase87 build (`base` = phases 8 to 87). If a wave-1 package changes the same lines first, `_m_patch` stops with "patch site not found" and nothing is half done.

## 5. Web hooks (integrator)

- `web/index.html`: `<script src="moneycontrols.js"></script>` (after `app.js`, next to `moneyaccounts.js`); add to the `web/sw.js` precache list if the other screen files are listed there.
- `web/ia.js` (one line, group `acc`; the test injects the same line; English only, owner rule 5):
```js
  rec('moneycontrols', 'acc', ['Money controls', 'Money controls', 'Money controls'], { icon: 'check', ok: (c) => c.own || c.GF.accounts_view === true || c.GF.accounts_manage === true || c.GF.cash_move === true || c.GF.supplier_pay === true, kw: ['money controls', 'owner draw', 'bank slip', 'duplicate payment', 'control account', 'waiting for approver', 'exceptions', 'mapping type'] }),
```
  Run `ia_test`, nav, nav2, control, favsync, settings2 afterwards (the record count in `ia_test` may need +1). No Home tile, no bottom bar slot.
- Optional (files of the integrator): a "Waiting for the approver" message for `pending` answers in `cashmoves.js`, `purchase.js`, `accounts.js`; a call to `w1e_vendor_check(name, mobile, tin, exclude)` before saving a supplier and `w1e_pay_account_check(bank, wallet, exclude)` before saving an employee pay account, to warn before the server does; `w1e_mapping_check(key, account)` in the mapping editor.
- Delegation: the 7 new `grant_separation_pairs` reach `#/delegation` through `grant_separation_report()` without a change in `delegation.js`.

## 6. Tables, functions, triggers added

Tables: `w1e_requests` (append only, no delete, audited, RLS on, no browser access), `w1e_mapping_types` (same). Rules: 15 (section 2). Separation pairs: `cash_move_release`, `supplier_pay_purchase`, `payroll_employee`, `accounts_purchase`, `supplier_pay_manage`, `cash_move_accounts`, `purchase_enter_void`.

API (authenticated, each checks its own permission): `w1e_state`, `w1e_requests_list`, `w1e_request_decide`, `w1e_request_cancel`, `w1e_request_approver_set` (owner), `w1e_exceptions_list`, `w1e_checks`, `w1e_vendor_check`, `w1e_pay_account_check`, `w1e_mapping_check`, `w1e_mapping_types_list`, `w1e_mapping_type_set` (owner). Internals are closed to browser roles (`_w1e_*`). Triggers: `a94_w1e_cash_bi`, `a94_w1e_supplier_bi`, `a94_w1e_employee_bi`, `a95_w1e_jl_bi`, `a95_w1e_mapping_bi`.

Applying a held request: `_w1e_apply_owner_money` (inserts the original `cash_moves` row with its original id, client id and maker), `_w1e_apply_supplier_pay` (re-checks the balance, `overpaid` stops it; inserts the rows as the maker), `_w1e_apply_journal_control` (posts through `_acct_write`; the memo ends with `[request n]`; the approver is the poster of record, the maker is in `w1e_requests` and the audit line). Everything is re-checked at approval (`lock_check`, balance, accounting start). Posting dates stay as the maker entered them.

## 7. Tests (local Postgres 16, port 5565, base = phases 8 to 87 in the owner's order)

| Suite | Result |
|---|---|
| `supabase/phase94_test.sql` (fresh DB through 87 + 94) | 119 pass, 0 fail |
| `supabase/phase95_test.sql` (fresh DB through 87 + 94 + 95; run from the repository root) | 84 pass, 0 fail |
| `bash tests/sql/phase94_95_before_after.sh` | 12 snapshots identical after the paste; posting run posts 0; wave 2 at defaults identical to a twin without 94/95 (9 reports); all 15 settings ON: 0 snapshots moved; 0 unbalanced entries |
| All older SQL suites on a fresh copy, with and without phases 94 and 95 | same pass/fail counts everywhere except `phase78_test` T0 (see below) |
| `node tests/web/moneycontrols_test.js <abs tests/web>` (headless Chromium, stubbed server, 360px, English) | 0 assert failures, no console errors. `ia_test`, nav, nav2, control, favsync, settings2 NOT run: no registry line is added by this package (integrator step) |

Known and intended: `phase78_test.sql` T0 asserts "exactly two separation pairs seeded". U-07 requires 6 to 8 more pairs, so that one assertion now fails by design (101 pass / 0 fail becomes 100 / 1), like the two phase47 asserts after phase62. The integrator should relax that assertion in the wave's re-patch tests; the old file was not edited here. The baseline failing sets of the older suites (phase 8, 14, 15, 16, 18, 19, 21, 23, 47, 72, 82, 84 on a build that includes phase 87) are unchanged by this package.

Negative tests present (server side, as a salesperson-level login): non-owner owner draw refused in `owner` mode; maker cannot decide; a non-approver cannot decide; named mode keeps the owner out; maker equals approver refused for a named approver; slip required; duplicate payment blocked and excepted; payment over the limit held and approved or rejected; overpaid at approval refused; duplicate vendor and pay account refused; place of a journal line refused; sales mapped to an expense account refused; attachment required; control account held, blocked, excepted; non-owner cannot change the type list; unbalanced journal still refused first; delete of a request or a type row refused; internals closed to browser roles.

## 8. Not done, and what could not be confirmed

- **Supplier opening frozen after go-live** (listed under U-07 "with U-01"): depends on the opening change of W1-A (`customers.opening_balance` / freeze). Not built here.
- **Partner capital by a non-owner**: `partner_capital_add` is owner-only on the server today (`_a44_guard`), which is stricter than every mode of `owner_money_entry_mode`; nothing was changed there. If the owner wants a non-owner to enter partner capital for approval, that is a later change in the integrator-owned partner functions.
- Real Supabase project, real phone, live data: never touched. The screen is unverified on a phone.
- `acct_cash_flow`, day book and journal readers were not changed; held requests are not in `cash_moves` / `journal_entries`, so no report counts them until they are approved.
- Posting date of an approved request is the date the maker entered; a request that is approved after the period was closed is refused by `lock_check` when the approver is not the owner (an owner approver passes `lock_check` as for any entry today; W1-B changes that rule for everybody).

## W1-FIX (phase141): the supplier payment limit can count several days

`supplier_pay_over` is compared with one `pay_supplier` call, so paying in smaller parts avoids it. New setting **`supplier_pay_over_cumulative_days`** (number 0 to 365, default **0** = per call as today). With N more than 0 the limit is compared with this payment plus what the same person already paid to the same supplier in the last N days plus that person's pending requests for that supplier (the owner is never held). Two exact-text lines in `_w1e_pay_gate` (marker `bos141`), see `docs/integration/W1-FIX.md`. The hook H1 of this note is unchanged.
