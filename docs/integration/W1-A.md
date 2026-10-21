# Integration note W1-A: opening dues and payables linked to the customer and supplier sub-ledgers (plan item U-01)

SQL number: **phase88** only. Paste after phase87 (or the latest phase). Paste-twice safe. No existing file was edited. Package W1-A owns: `supabase/phase88.sql`, `supabase/phase88_test.sql`, `web/openparties.js`, `tests/web/openparties_test.js`, `tests/sql/phase88_hooks.sql`, `tests/sql/phase88_before_after.sh`, `tests/sql/p88_fixture.sql`, `tests/sql/p88_snap.sql`.

## 0. What it does

A customer who owed money before go-live could not be collected (`collect_payment` raised `overpaid`), the POS credit limit ignored the old due, and a supplier opening had to be typed twice. After this phase, and after the hooks below, each old due is typed once (one party, or a paste import), counts in the sub-ledger, can be collected, is posted by the opening batch from the same figures, is protected after the batch, and a gate shows every party where sub-ledger and books differ.

Nothing changes until the owner turns a setting on (section 3). Proof: `tests/sql/phase88_before_after.sh` (19 snapshots identical after phase88, after the hooks, and after switching the link ON with no opening typed; second-wave reports identical to a twin database that never got phase88).

## 1. Hooks (the integrator pastes them in phase99; nothing else is needed)

Phase88 patches NO shared function. The four hooks are in `tests/sql/phase88_hooks.sql` (needs phase88; paste-twice safe through the marker `bos88`). The integrator copies the file into the phase99 re-patch file. Exact text:

```sql
-- 1. _cust_bal: the opening due is part of the customer balance. Credit limit check (record_sale2 -> customer_balance), collect_payment ("overpaid") and the sale-return
--    "due first" credit all read this one function.
select public._w1a_patch('public._cust_bal(uuid)'::regprocedure, array[
  $a$select coalesce((select sum(s.total) from public.sales s where s.customer_id = p_customer and s.status = 'done'), 0)$a$,
  $a$select public._w1a_cust_open(p_customer) /* bos88: opening due */ + coalesce((select sum(s.total) from public.sales s where s.customer_id = p_customer and s.status = 'done'), 0)$a$]);

-- 2. customer_dues: customers with an opening due (and perhaps no sale) are in the list; the opening is the oldest item, collections clear it first.
select public._w1a_patch('public.customer_dues()'::regprocedure, array[
  $a$select cu.id, cu.name, cu.mobile, cu.type, cu.credit_limit, t.rem - coalesce(c.coll, 0),$a$,
  $a$select cu.id, cu.name, cu.mobile, cu.type, cu.credit_limit, coalesce(t.rem, 0) + public._w1a_cust_open(cu.id) /* bos88 */ - coalesce(c.coll, 0),$a$,
  $a$(select min(k.sale_date) from cum k where k.customer_id = cu.id and k.cr > coalesce(c.coll, 0))$a$,
  $a$(case when public._w1a_cust_open(cu.id) > coalesce(c.coll, 0) then public._w1a_cust_open_date(cu.id)
              else (select min(k.sale_date) from cum k where k.customer_id = cu.id and k.cr + public._w1a_cust_open(cu.id) > coalesce(c.coll, 0)) end)$a$,
  $a$from public.customers cu join t on t.customer_id = cu.id left join c on c.customer_id = cu.id$a$,
  $a$from public.customers cu left join t on t.customer_id = cu.id left join c on c.customer_id = cu.id$a$,
  $a$and t.rem - coalesce(c.coll, 0) > 0$a$,
  $a$and coalesce(t.rem, 0) + public._w1a_cust_open(cu.id) - coalesce(c.coll, 0) > 0$a$]);

-- 3. customer_ledger: one first row "opening" (debit = the opening due) so the running balance of the ledger ends at the same figure as the dues list.
select public._w1a_patch('public.customer_ledger(uuid)'::regprocedure, array[
  $a$select s.sold_at at, 'sale'::text kind,$a$,
  $a$select public._w1a_cust_open_at(p_customer) at, 'opening'::text kind, null::text ref, null::int location_id, o.ob debit, 0::numeric credit, 'opening balance'::text note, null::bigint pid /* bos88 */
      from (select public._w1a_cust_open(p_customer) ob) o where o.ob <> 0
    union all
    select s.sold_at at, 'sale'::text kind,$a$]);

-- 4. opening_balance_post: the customer_dues and supplier_dues sections also fill the customer and supplier sub-ledger in the same transaction (only while open_parties_link is ON).
--    !! Do not use phase87 _m_patch here: it stops at once because the function already carries bos87.
select public._w1a_patch('public.opening_balance_post(jsonb,uuid,boolean,boolean)'::regprocedure, array[
  $a$jid := (r->>'id')::bigint; perform public._m_opening_mark(p_json); /* bos87 */$a$,
  $a$jid := (r->>'id')::bigint; perform public._m_opening_mark(p_json); /* bos87 */ perform public._w1a_opening_apply(p_json); /* bos88 */$a$]);
```

- The file `tests/sql/phase88_hooks.sql` is the source of truth; the block above is a copy.
- Why `_w1a_patch` and not `_m_patch`: phase87 `_m_patch` returns false and patches nothing when the marker `bos87` is already inside the function, and `opening_balance_post` already carries `bos87`. `_w1a_patch(fn, pairs, marker default 'bos88')` is the same exact-text helper with the marker as a parameter. It is shipped in phase88 (revoked from browsers). A missing patch site stops with a clear message and changes nothing in that function.
- Re-paste hazard: re-pasting phase 6 or 12 (`customer_dues`, `customer_ledger`, `_cust_bal`) or phase 80 or 87 (`opening_balance_post`) removes the matching hook. The phase99 re-patch file must run `phase88_hooks.sql` again after them. With the setting OFF the hooks change nothing.
- Proven on a scratch database (`supabase/phase88_test.sql` T2): with the hooks applied and the switch OFF, the customer balance, dues list and ledger of every test customer are identical to before the hooks; at the end (T10) the original definitions are put back, so the database is again phase 88 without hooks. All 56 older SQL suites (phase 8 to 87) give the same failing set on a database with phase88 and on one with phase88 plus the hooks as on the baseline.

## 2. Web hooks (integrator-owned files)

- `web/index.html`: `<script src="openparties.js"></script>` after `moneyaccounts.js` / `balancecheck.js`. `web/sw.js`: add `openparties.js` to the precache list if the others are listed [not checked].
- `web/ia.js`, next to the `moneyaccounts` record (group `acc`). Do not rename the route `openparties`:

```js
  rec('openparties', 'acc', ['Opening dues and payables', 'Opening dues and payables', 'Opening dues and payables'], { icon: 'book', ok: (c) => c.own || c.GF.accounts_view === true || c.GF.accounts_manage === true, kw: ['opening dues', 'opening balance', 'old dues', 'customer due', 'supplier payable', 'import dues', 'sub-ledger', 'party gate'] }),
```
  The web test injects a shortened version of this line itself. `ia_test` record count +1 (intentional). No `i18n.js` keys: labels are English only for now (owner rule).
- `web/dues.js` (customer sheet ledger): with the hook, `customer_ledger` returns a first row with `kind = 'opening'`. Add the label "Opening due" for that kind when convenient. The `at` of that row is a real timestamp (the opening date or the accounting start, 00:00 Dhaka), not `-infinity`.
- Opening screen (the JSON box in `accounts.js`): call `w1a_open_json()` and merge its `customer_dues` and `supplier_dues` sections into the opening data instead of typing them again; optionally call `w1a_open_precheck(json)` before posting. The `openparties` screen already shows both and has a "Compare" box.
- Not covered on purpose: the location-scoped report engine (phase9) reports `customer_dues` and `receivable_aging` compute from sales only and do not show the opening. The dues list, customer sheet, POS credit check and `collect_payment` do. Ageing of opening dues belongs to U-22.

## 3. Settings (rules, module `books`, Rules hub; owner only; every change is an `audit_log` line through the existing `audit_rules` trigger)

| Key | Default | Meaning |
|---|---|---|
| `open_parties_link` (switch) | OFF | ON: the typed opening due is added to the customer balance (credit limit, collect, dues list, ledger) and `opening_balance_post` fills the sub-ledger from the posted figures. OFF: exactly today's behaviour. (A supplier opening was always part of `_sup_balance`; the switch governs customers and the opening-batch fill.) |
| `open_parties_freeze` (choice off / after_opening) | off | after_opening: once an opening batch exists, a direct change of `opening_balance` or `opening_date` on a customer or supplier (also through `save_supplier`) is refused (`opening_frozen`). The way is an adjustment with a reason. |
| `open_parties_adjust_mode` (choice direct / approval) | direct | direct: a holder of Accounts manage adjusts at once with a reason. approval: a second person decides. The maker never decides; the owner's own request follows the owner approval setting (self, logged, off: the owner decides; named: the named role or people decide). No role or person is written in the code. |

`set_rule` takes JSON: a choice is passed as a JSON string, for example `set_rule('open_parties_freeze', '"after_opening"')`. Labels are English; the Bangla column carries the same English text for now.

Exceptions: every adjustment needs a reason (3 characters or more) and writes one `audit_log` line (`open_party_adjust`), a balanced manual journal entry (Dr or Cr receivable or payable with the party, against the mapping `retained`), and one row in the Exceptions list (`exceptions`, form `ACC`, flag `opening_adjusted`, yellow). The owner sees it in `#/exceptions`.

## 4. Tables and functions (all in `supabase/phase88.sql`)

Columns: `customers.opening_balance` (>= 0, empty = none), `customers.opening_date`, `suppliers.opening_date` (`suppliers.opening_balance` existed). Table `open_party_adjustments` (RLS read for Accounts view, no delete). Triggers `customers_open_guard88`, `suppliers_open_guard88` (freeze).

API (security definer, each checks the permission; granted to authenticated): `w1a_open_state`, `w1a_open_list(kind, search, only, limit, offset)` (difference = books minus sub-ledger), `w1a_open_set`, `w1a_open_import(kind, rows, dry default true, create)` (all or nothing, at most 2000 rows), `w1a_open_json`, `w1a_open_precheck`, `w1a_open_from_journal(dry default true)`, `w1a_open_adjust`, `w1a_open_adjust_decide`, `w1a_open_adjust_list`, `w1a_party_gate(kind)` (wraps `acct_reconcile`, adds `typed_opening`, `journal_opening` and a `cause`). Internal (closed): `_w1a_patch`, `_w1a_mgr`, `_w1a_cust_open`, `_w1a_cust_open_date`, `_w1a_cust_open_at`, `_w1a_opening_apply`, `_w1a_adj_apply`, `_w1a_may_decide`, `_w1a_open_guard`, `_w1a_audit`, `_w1a_exc`, `_w1a_batch_exists`, `_w1a_frozen`.

Permission: the list and the gate need Accounts view for all places; typing, importing, adjusting and deciding need Accounts manage for all places (`_w1a_mgr`). A branch accountant (Accounts manage at one place only) and a salesperson are refused on the server (tested).

## 5. Behaviour to know

- Typing and import are staging: allowed only BEFORE the opening batch (`opening_posted_use_adjust` afterwards). The batch posts the sections from `w1a_open_json()`; the posted figure wins over a typed one and the difference is an `audit_log` line (`open_party_json_override`).
- A supplier who owes us (negative opening) cannot go in `supplier_dues`; `w1a_open_json` lists it under `not_postable` (enter it afterwards as an adjustment).
- An opening batch posted before this phase: `w1a_open_from_journal` fills the sub-ledger fields from the posted entry (dry run first; different figures are listed as conflicts and never overwritten). Adjustments are journal entries of type manual and are not in that fill.
- The customer opening is the oldest item: collections clear it before sales; `customer_dues.oldest` is the opening date (or the accounting start) while it is unpaid.
- Old customers who never bought in the system can be created by the import (needs mobile and name); suppliers are never created.
- The opening is a company figure: no place on the party line.

## 6. Tests

- `supabase/phase88_test.sql` (fresh database through phase 87, then phase 88): **146 pass, 0 fail** (local Postgres 16, port 5561). Run: `psql -qAt -f supabase/phase88_test.sql | grep -E 'FAIL|RESULT'`. Negative tests: salesperson and branch accountant refused on every function; bad kind, negative customer opening, NaN, unknown party; import with seven kinds of bad row (nothing written, whole file refused), more than 2000 rows, empty file; opening typed after the batch refused; unbalanced opening refused with no party touched; second opening post refused; collect 600 on 500 refused; credit limit counts the opening; supplier `overpaid` uses the adjusted figure; freeze refuses a direct change, a date change, a new supplier with an opening and the `save_supplier` path; adjustment without reason, with 2 characters, same figure, pending twice, maker decides own, non-named approver; gate red with causes and repaired by the fill; paste twice.
- `tests/sql/phase88_before_after.sh`: all equal (section 0). Needs a base database through phase 87 (`BASE`, `PORT`).
- `tests/web/openparties_test.js`: 0 assert failures, no console errors (headless Chromium, mocked server functions, 360px, bn and mix modes, no horizontal overflow). Run: `node tests/web/openparties_test.js $PWD/tests/web`. It writes no screenshot into the repository (set `OP_SHOTS` to write them elsewhere).
- Older SQL suites 8 to 87 (56 files): the failing set is identical on baseline, with phase88, and with phase88 plus the hooks.

## 7. Not confirmed

Live Supabase, a real phone, real data. How many live customers already have a posted opening batch (use `w1a_open_from_journal`). The owner's source list of old dues (OD-16). The `ORDER` string for fresh builds needs `phase88` (integrator). `docs/BUILD-LOG.md` and `docs/BUILD_PLAN_GAPS.md` entries are the integrator's.
