# Concurrency report (branch `qa/conc`, from `integration/p72-p79`)

Scope: money and stock paths that many step reports flag as "concurrency not tested". Repo code was read only; only new files under `tests/sql/concurrency/` were added.
Nothing in `supabase/` was changed. The proposed fixes are in `proposed_fixes.sql` and were applied only to a scratch clone (`verify_fixes.sh`).

## 1. Result in one table

211 checks PASS, 9 FAIL, in 34 scenario runs. 6 findings (F1..F6). Deadlocks seen by the server in the whole run: 35, all from two scenarios (S09b: 11, S13: 24). Every other scenario: `pg_stat_database.deadlocks` delta 0 and no `deadlock detected` in the server log.

| # | Scenario (sessions) | Result | Evidence |
|---|---|---|---|
| 1 | `record_sale2`, same item, last unit, `stock_negative_mode` block (30) | PASS | 1 sale, 29 `insufficient_stock`, stock 0, never below 0 |
| 1 | same, mode allow (30) | PASS | 30 sales, balance = 1 - 30, ledger replay equal |
| 1c | two-line sales in opposite line order, 40 sessions (extra) | PASS | 40/40 ok, no deadlock (lines are locked in a fixed order) |
| 2 | same `client_id` replayed (30), `record_sale2` and `record_sale_offline` | PASS | 1 sale row, 29 answer `dup`, 0 errors, 1 stock-out, 1 journal entry |
| 3 | `stock_production_in` (stock_post +) + `stock_transfer` both directions + `stock_count_adjust` + wastage + issue on one balance (48), then every transfer received by 3 sessions at once | PASS | no errors, no deadlock, balance = sum(ledger), avg cost = replay, each transfer received once |
| 4 | `production_post`, 20 cooks on the same raw material, DEFAULT rules (mode warn, `production_short_mode` refuse) | **FAIL (F1)** | 20 of 20 succeed on 100 kg that covers 10; raw material ends at -100 |
| 4 | same with `stock_negative_mode` = block | PASS | exactly 10 succeed, 10 `insufficient_stock`, raw = 0, FG = 80 |
| 5 | `post_purchase` x30 on one draft | PASS | 1 posting, 29 `dup`, stock +10 once |
| 5 | void + payments + re-post on one posted bill (3 mixes, 30 sessions) | PASS | stock 0 (void) once, 1 reversal, payments never above total, GL payable = supplier balances |
| 5 | 30 payments of 100 on a 1000 bill; same payment `client_id` x30 | PASS | exactly 10 accepted, bill.paid = sum(payments); 1 row for the repeated client id |
| 6 | `acct_post_pending` x6 + `acct_autopost_tick` x6 (signed in) + x6 (scheduler path) + 6 sales, 1500 sales, 6 bills, 40 voids (24) | PASS | 0 errors, each non-void sale posted once, 20 voids of posted sales = exactly 20 reversals, `je_source_uq` holds, nothing pending, no deadlock |
| 7 | `landed_post` (same doc, same and different client ids) x10 with 30 sales of the same item | PASS | doc posted once (2 `cost_adjust` rows), stock value conserved, avg cost = replay, GL = valuation (rounding residue up to 0.11 also occurs serially, see 5) |
| 8 | `card_settle`, same `client_id` x20 | PASS | 1 settlement row, 19 `dup` |
| 8 | `card_settle`, 20 different client ids of 600 against a 600 receivable | **FAIL (F6)** | 20 accepted, every answer `over=false`, card receivable ends at -11400 (the same happens serially when the journal is not posted between calls) |
| 9 | bill auto-payment (`auto_cash`, trigger `_bp_pur_auto99`): 6 drafts posted by 5 sessions each + 30 sessions saving and posting their own bill | PASS | 36 bills, 36 payments, 36 links, 0 double payments, 0 errors |
| 9b | `scan_confirm(p_post=true)` (save bill + post in ONE transaction), 12 sessions, same supplier | **FAIL (F2)** | 1 of 12 succeeds, 11 `deadlock detected` |
| 10 | `inbox_unmask` daily maximum 5, one grant holder, 30 parallel calls | **FAIL (F3)** | 15..16 reveals (3x the limit); serial control: exactly 5 |
| 11 | Telegram `update_id`, Meta message id, web-form submission uuid from 10 sessions each, then one Telegram update from 30 sessions | PASS | 1 row each, rest `duplicate`/`dup`, 0 errors |
| 12 | `setup_recommend_apply`, same client id x20 | PASS | 1 batch, 1 audit row, end state = serial run |
| 12 | same, 20 different client ids | **FAIL, low (F5)** | end state equals the serial run, but the first changed rule is reported "applied" (and audited) 20 times |
| 13 | `set_option_view_bulk` / `set_role_option_view_bulk` (200 keys, ascending vs descending), with readers (32) | **FAIL (F4)** | 24 deadlock errors; readers never saw a half-applied set; final state uniform |
| 14 | extra: `void_sale` x20; 12 `sale_return` of 1 on a sale of 3; return + void of one sale; `production_void` x20 | PASS | stock restored once, at most 3 returned, no double restore, no deadlock |

After every scenario the harness also asserts, as SQL: `stock_reconcile(false)` returns no row (stock_balance qty and avg cost = replay of `stock_ledger`), unbalanced journal entries = 0 and sum(debit - credit) = 0, no duplicated `(source_type, source_id)` among live entries (`je_source_uq`), GL account 2100 = sum of supplier balances, and `inventory_vs_gl().total.unexplained` within 0.05 (7: within 0.20). All of these held in all 34 runs, including the runs that FAILED a scenario-specific check (F1 leaves a negative but internally consistent stock; no scenario produced a lost update or a double GL entry).

## 2. Findings

### F1 (high) `production_post` can take raw material below zero under the DEFAULT rules
- Where: `supabase/phase89.sql:1471` (final text; same lines in phase79.sql:325, phase74.sql:410): `for n in select * from public._recipe_need(...) where need > on_hand` reads `on_hand` without a lock. The later `stock_post(... 'issue_out' ... 'full')` only blocks when `stock_negative_mode = block`; with the default `warn` it lets the balance go negative.
- Impact: `production_short_mode = refuse` (the default) is a promise that production never uses stock that is not there. Two cooks started together both pass the check. Raw material negative, finished goods created from stock that did not exist, cost distorted.
- Minimal repro: raw material 10 kg on hand, recipe uses 10 kg per batch. Sessions A and B both run `select production_post(1, <recipe>, 1, gen_random_uuid());` at the same moment. Both return a `run_id`; `stock_balance.qty` = -10. (Harness: `s04.sh`, 20 sessions: 20 successes, raw = -100. Serial control: the 11th batch is refused.)
- Fix (verified on the scratch clone: exactly 10 succeed, raw = 0): lock the ingredient balances, in item order, before the check:
```sql
-- in production_post, right after:  mode := coalesce(public.rule_txt('production_short_mode'), 'refuse');
perform 1 from public.stock_balance sbl where sbl.location_id = p_loc
  and sbl.item_id in (select n2.item_id from public._recipe_need(r.id, p_batches, p_loc) n2) order by sbl.item_id for update;
```

### F2 (high) `scan_confirm(..., p_post => true)` deadlocks when two bills for the same supplier are confirmed together
- Where: `supabase/phase90.sql:592-595` runs `save_purchase` (insert into `purchase_bills`: takes a `FOR KEY SHARE` lock on the supplier row through the foreign key) and then `post_purchase` in the same transaction; `_post_purchase_p13` asks `SELECT 1 FROM suppliers WHERE id = ... FOR UPDATE` (`supabase/phase89.sql:383`). `FOR UPDATE` conflicts with the other session's key-share lock, and both wait for each other. Same lock text in `_void_purchase_p13` (`phase89.sql:606`), `_bp_pay99` (`phase99.sql:239`), `pay_supplier`, `void_supplier_payment`, `supplier_refund`, `void_supplier_refund` (`phase10.sql:1181/1221...`).
- Impact: with 12 staff confirming scanned bills of one supplier at once, 11 get "deadlock detected" (nothing is half saved, the transaction rolls back; a retry works). Separate `save_purchase` and `post_purchase` calls (what `purchase.js` does) do not deadlock: scenario 9 with separate calls passes.
- Minimal repro: two sessions, bill rows for the same supplier, `begin; insert into purchase_bills (...supplier_id = S...); select 1 from suppliers where id = S for update;` in both, interleaved. Harness: `s09b.sh` (real `scan_confirm`, jobs inserted as `reviewed`).
- Fix (verified: 12/12 succeed, 0 deadlocks; the exclusion between posters is kept because `FOR NO KEY UPDATE` conflicts with itself): in the functions above change the one lock line
```sql
perform 1 from public.suppliers where id = pb.supplier_id for no key update;   -- was: for update
```

### F3 (medium; Sec2 is fixing it, this is the behaviour at this commit) `inbox_unmask` daily limit is not enforced under parallel calls
- Where: `supabase/phase99.sql:610` counts today's `revealed` rows, `phase99.sql:623` inserts the new one; no lock between them.
- Impact: a user with `inbox_unmask` and `inbox_unmask_daily_max = 5` revealed 15-16 of 30 messages in one burst (every reveal is still logged, so the audit trail is complete; only the limit is bypassed).
- Repro: `inbox_unmask_daily_max` = 5, user with the grant, 30 sessions each `select inbox_unmask('message', <id>, 'x');`. Harness `s10.sh`, serial control passes (exactly 5).
- Fix (verified: exactly 5, log = replies): one advisory lock per user before the count
```sql
if lim is not null and not public.is_owner() then
  perform pg_advisory_xact_lock(hashtextextended('inbox_unmask:' || auth.uid()::text, 0));
  select count(*) into used ...
```

### F4 (medium-low) `set_option_view_bulk` / `set_role_option_view_bulk` deadlock when two owners send the same keys in a different order
- Where: `supabase/phase91.sql:160` and `:191`: `for it in select * from jsonb_array_elements(p_items) loop` upserts rows in the order the client sent them.
- Impact: 24 of 32 calls failed with `deadlock detected` when half the callers sent 200 keys ascending and half descending (user and role level). Readers are safe: every read saw 0 or all 200 overrides, and the final state is uniform.
- Repro: session A `set_option_view_bulk(u, '[k1..k200]')`, session B `set_option_view_bulk(u, '[k200..k1]')` at the same time. Harness `s13.sh`.
- Fix (verified: 0 deadlocks, state uniform): `for it in select e.value from jsonb_array_elements(p_items) e order by e.value->>'key' loop` in both functions.

### F5 (low) `setup_recommend_apply`: a second tap with a new client id repeats the first rule
- Where: `supabase/phase103.sql:1027`: only `_client_lock(p_client)` (per client id). Concurrent calls with different client ids all read the rule before any commits; the first changed rule is set by all (they queue on the row lock) and each batch reports and audits it as "applied" (`production_requires_cost` x20). Later rules are correct ('already'). Same client id is safe.
- Impact: duplicate audit lines and `setup_apply_lines81` rows, no wrong setting.
- Fix (verified): after the client lock add `perform pg_advisory_xact_lock(hashtextextended('setup_recommend_apply', 0));`.

### F6 (medium) `card_settle` never refuses an over-settlement, and its "over" warning is blind to settlements not yet posted
- Where: `supabase/phase85.sql:827-830`: `bal` = GL balance of the card account (only changes when `acct_post_pending` runs), result `over = gross > bal`, no check, no lock.
- Impact: 20 parallel (or 3 serial, without posting in between) settlements of 600 against a 600 receivable are all accepted, every answer says `over=false`, and after posting the card receivable is -11400. Same client id is safe (1 row).
- Behaviour change, so it needs a decision: the fix below refuses with `over_settlement`; if the owner prefers flag-only, keep the flag but compute it with the same corrected balance.
```sql
perform pg_advisory_xact_lock(hashtextextended('card_settle:' || p_loc::text, 0));
bal := bal - coalesce((select sum(c2.gross) from public.card_settlements85 c2 where c2.location_id = p_loc and c2.status = 'done'
        and not exists (select 1 from public.journal_entries e where e.source_type = 'card_settlement' and e.source_id = c2.id::text and e.reverses_id is null)), 0);
if round(p_gross, 2) > bal then raise exception 'over_settlement' using detail = 'unsettled ' || bal::text; end if;
```
(verified: 1 accepted, receivable 0.00).

`proposed_fixes.sql` contains all of the above as runnable `create or replace` statements built from the live definitions (the "tag" for the new lines is `bos104`). They must be merged into the latest text of each function in the phase files by the follow-up step; per `docs/PASTE_ORDER.md` rule G, `production_post`, `inbox_unmask`, `setup_recommend_apply` are re-created functions, so merge into phase89 / phase99 / phase103 texts and keep every `bosNN` tag.

## 3. Notes that are not defects

- Rounding: `inventory_vs_gl` can show an "unexplained" of a few cents after many sales of an item whose average cost has 3 decimals (e.g. 0.07 after a serial run of 30 sales with a landed cost in the middle; control `S07s`). COGS is rounded per sale, valuation once per balance. Not concurrency related, so the tolerance is 0.05 (0.20 in scenario 7).
- Locking design that held up: `stock_post` row-locks the balance (`for update`) so every writer of one item/place is serial; sale lines and production ingredients are posted in a fixed item order (S01c, S04 show no lock-order deadlocks); supplier lock serialises post/void/pay per supplier (S05: no double GL, `bill_pay_record` cannot overpay); `acct_post_pending` takes `pg_advisory_xact_lock('acct_post')` so two runners never post the same document; client-id replay on sale, offline sale, payment, transfer, card settlement, landed post, setup apply is exact.
- Artifact of the first draft of scenario 9, kept out: saving and posting a purchase bill inside ONE SQL statement deadlocks for the same reason as F2. The browser uses two calls, so it is not a finding; `scan_confirm(p_post)` is the one place that does it for real.
- Not covered: cost bills (`cost_bill_creates_payment`), GRN/`entry` receipts, sale packaging consumption, expiry batches under parallel sales, payroll. The harness is DB level (psql sessions, `set role authenticated`, mocked `auth.uid()`); it does not go through PostgREST or a connection pooler. Transaction retry on `deadlock detected` in the app was not examined.

## 4. How to run

```
bash tests/sql/concurrency/run_all.sh            # builds the final DB (phases 8..103 in PASTE_ORDER) + clean seed into template conc_tpl, then runs s01..s14 (about 8 minutes)
bash tests/sql/concurrency/run_all.sh s04 s10    # selected scenarios (SKIP_BUILD=1 reuses the template)
bash tests/sql/concurrency/verify_fixes.sh       # conc_tpl + proposed_fixes.sql -> conc_tpl_fixed, re-runs the failing scenarios
```
Method: N psql sessions connect first and queue on a shared advisory lock held by a "holder" session; when all N are waiting the holder is killed and all N fire together (`lib.sh: race`). Output per session in `out/<scenario>/<i>.out|err`, verdicts in `out/results.tsv`. Seed: `e2e/00_common.sql` + `01_setup.sql` (users, items, accounting start, opening stock) + `seed_extra.sql` (second place, scenario items, approved recipe, opening-stock journal). Each scenario runs on its own clone of the template (`cc_*` databases). Deadlocks are read from `pg_stat_database.deadlocks` (before/after) and from the server log.

## 5. Re-run with the proposed fixes applied (scratch clone only)

`verify_fixes.sh` clones the template, applies `proposed_fixes.sql` (9 functions patched, each patch asserts that the text it replaces exists exactly once) and re-runs the six scenarios that failed. Result: every check of S04 (default and block, serial control still refuses the 11th batch), S08, S09b (12/12 confirmed, 0 deadlocks), S10 (exactly 5 reveals), S12 (one "applied" per rule, end state = serial run), S13 (0 deadlocks, uniform state) is PASS, and the standard invariants (stock replay, trial balance, `je_source_uq`, AP = GL, inventory = GL) still hold. A full-suite regression on the fixed clone was started but stopped part-way (the machine was shared and loaded): the part that ran (S01 to S05, 114 checks) shows 0 FAIL; the later scenarios were verified on the fixed clone only for the six listed above. Run `TPL=conc_tpl_fixed bash run_all.sh` for the full regression before merging the fixes.
