# Integration note W1-B (item U-02, period integrity, phase 89)

Package files: `supabase/phase89.sql`, `supabase/phase89_test.sql`, `web/periodlock.js`, `tests/web/periodlock_test.js`, `tests/sql/phase89_before_after.sh` (+ `tests/sql/p89_wave2.sql`), `docs/integration/W1-B_hooks.sql` (the hook SQL below, byte for byte).
No existing file was edited. Needs phase87 (not phase88). Paste-twice safe. Public RPC names follow the plan (`period_*`, `late_sale*`, `accounting_on_*`); every internal helper is `_w1b_*`.

## What phase89 adds on its own (works without any hook)
- Tables `period_overrides` (windows) and `late_sales_held` (parked offline sales): append-only (no_hard_delete), audit trigger, RLS, no browser write.
- Settings (rules, English labels, all defaults equal today): `period_lock_mode` manual|auto|off [manual], `auto_lock_day` [blank], `owner_closed_period_mode` off|log|reason [off], `period_override_default_minutes` [60], `lock_backward_policy` allow|reason_after_year_close|reason_always [allow], `backdate_max_days_purchase|cash_move|expense|production` [blank = off], `late_sale_policy` redate|redate_flag|park [redate], `start_date_lock_after_opening` [off], `accounting_on_needs_reason` [off]. Grants `late_sale_release`, `backdate_over_limit` (nobody holds them by default).
  Every change is an `audit_log` line (rules trigger) and, through `period_lock_policy_set(key, value, note)`, a second line with the note. Plan default `owner_closed_period_mode = reason` and `late_sale_policy = park` were NOT used: the owner's standing rule is "default keeps today". Owner decision OD-5 / OD-7: the recommended values are reason and park.
- `_w1b_lock_date()` / `_w1b_is_locked(date)` (pure date test, same for every user), `_w1b_lock_allowed(date)` (what lock_check will call), `_w1b_override_take`, `_w1b_backdate_check(doc, date, client, ref)`, `_w1b_late_sale(...)`, `_w1b_pure_posting()`.
- RPCs: `period_lock_state`, `period_lock_set(date, reason)`, `period_lock_policy_set`, `period_override_start(reason, from, to, minutes, scope, for_user, doc)`, `period_override_end`, `period_override_log`, `period_lateness_report(days)`, `accounting_on_preview`, `accounting_on_set(on, reason)`, `late_sales_held_list`, `late_sale_release(id, accept|redate|reject, reason)`.
- Guards on `rules` (trigger `w1b_rules_guard`, only for API calls, like the phase80 guard): lock date back, start date after an opening, accounting ON after OFF, auto mode without a day.
- Trigger `w1b_sales_redate_flag` on `sales` (writes the `late_sale_redated` line when `late_sale_policy = redate_flag`; inert otherwise).
- `money_exceptions.kind` check is MERGED with the existing list and gets `late_sale_held`, `late_sale_redated`, `backdate_exception`. **Integrator: if another package re-creates `money_exceptions_kind_check` with a fixed list, make the final list the union of all kinds.**
- One-off exceptions reuse phase87: `money_exception_grant('period_lock' | 'override', reason, user, client, event, ...)`; for back-dating the event is `backdate:<purchase|cash_move|expense|production>`.

## Hooks the integrator must install (shared functions, not touched by phase89)
Run `docs/integration/W1-B_hooks.sql` after phase89 and again in the wave re-patch phase (phase99). It uses `_w1b_patch(fn, 'bos89', pairs)` (shipped by phase89: same design as `_m_patch`, marker is a parameter, because `lock_check` already carries `bos87` and `_m_patch` would silently do nothing). Each call reads the live definition, replaces exact texts, stops if a site is missing, is a no-op the second time.
Re-paste hazard: re-pasting phase 6, 8, 10, 14, 19, 23, 43, 50, 73, 74 or 87 removes the matching hook; the re-patch phase puts them back. `period_lock_state()` reports `hooks` per function so the screen shows what is missing.

```sql
-- W1-B hooks (marker bos89). For the integrator: paste after phase89, and again in the wave's re-patch phase (phase99) after any older phase that re-creates one of these functions.
-- Each call reads the LIVE definition, replaces exact texts, stops with a message if one text is missing (nothing is half changed), and does nothing the second time (marker bos89).
-- With every W1-B setting at its default these hooks change no behaviour (proved by supabase/phase89_test.sql and tests/sql/phase89_before_after.sh).
-- The helper _w1b_patch(fn, marker, pairs) is shipped by phase89 because the phase87 helper _m_patch only knows the marker bos87 and lock_check already carries it.

-- 1. lock_check: a pure date test; the owner is no longer silent when owner_closed_period_mode is log or reason; override windows. The old body stays below the new lines and is no longer reached.
select public._w1b_patch('public.lock_check(date)'::regprocedure, 'bos89', array[
  $a$if p_date is null or public.is_owner() then return; end if;$a$,
  $a$if p_date is null then return; end if;
  if public._w1b_lock_allowed(p_date) then return; end if;   -- bos89: pure date test, owner mode, override windows
  raise exception 'period_closed';                            -- bos89: the statements below are the old body and are not reached any more$a$]);

-- 2. _acct_locked: a document is in or out of a closed month the same way for every user (only when owner_closed_period_mode is log or reason; with off nothing changes)
select public._w1b_patch('public._acct_locked(date)'::regprocedure, 'bos89', array[
  $a$begin perform public.lock_check(p_date); return false;$a$,
  $a$begin if public._w1b_pure_posting() then return public._w1b_is_locked(p_date); end if; /* bos89 */ perform public.lock_check(p_date); return false;$a$]);

-- 3. record_sale2: a sale older than pos_offline_hours follows late_sale_policy (redate = as today, redate_flag, park). The new variable is declared next to the bos43 ones.
select public._w1b_patch('public.record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamp with time zone,text,numeric)'::regprocedure, 'bos89', array[
  $a$tier_id43 bigint; tier_pct43 numeric; tier_cap43 numeric; tier_amt43 numeric := 0;   -- bos43$a$,
  $a$tier_id43 bigint; tier_pct43 numeric; tier_cap43 numeric; tier_amt43 numeric := 0;   -- bos43
  lt89 jsonb;   -- bos89$a$,
  $a$if at_ > now() + interval '10 minutes' or at_ < now() - make_interval(hours => coalesce(public.rule_num('pos_offline_hours'), 72)::int) then at_ := now(); end if;$a$,
  $a$if at_ > now() + interval '10 minutes' or at_ < now() - make_interval(hours => coalesce(public.rule_num('pos_offline_hours'), 72)::int) then
    lt89 := public._w1b_late_sale(p_client, p_loc, p_lines, p_discount, p_payments, p_customer_mobile, p_customer_name, p_sale_type, p_note, p_quick, p_sold_at, p_discount_kind, p_discount_input, at_);   -- bos89
    if lt89 is not null and (lt89 ->> 'keep') is null then return lt89; end if;   -- parked for the owner
    if lt89 is null then at_ := now(); end if;                                    -- re-dated, as before
  end if;$a$]);

-- 4. cash_move_add: back-date window for cash moves (after the duplicate check, so a retry of a saved move is never refused)
select public._w1b_patch('public.cash_move_add(integer,text,numeric,date,text,uuid,text,text,uuid,boolean)'::regprocedure, 'bos89', array[
  $a$if p_dry then$a$,
  $a$perform public._w1b_backdate_check('cash_move', d, p_client, 'cash_moves');   -- bos89
  if p_dry then$a$]);

-- 5. quick_expense_add: back-date window for quick expenses
select public._w1b_patch('public.quick_expense_add(integer,date,text,text,numeric,text,boolean,text,uuid)'::regprocedure, 'bos89', array[
  $a$perform public.lock_check(d);$a$,
  $a$perform public.lock_check(d);
  perform public._w1b_backdate_check('expense', d, p_client, 'quick_expenses');   -- bos89$a$]);

-- 6. save_purchase: back-date window for the bill date (a draft that keeps its date is not asked again)
select public._w1b_patch('public.save_purchase(uuid,uuid,uuid,integer,text,date,jsonb,numeric,text,text,text,uuid,text)'::regprocedure, 'bos89', array[
  $a$if p_bill_date is null or not (p_bill_date <= (now() at time zone 'Asia/Dhaka')::date + 1) then raise exception 'bad_date'; end if;$a$,
  $a$if p_bill_date is null or not (p_bill_date <= (now() at time zone 'Asia/Dhaka')::date + 1) then raise exception 'bad_date'; end if;
  if bid is null then perform public._w1b_backdate_check('purchase', p_bill_date, p_client, 'purchase_bills');   -- bos89
  elsif pb.bill_date is distinct from p_bill_date then perform public._w1b_backdate_check('purchase', p_bill_date, p_client, 'purchase_bills'); end if;$a$]);

-- 7. production_post (7 arguments; the 6-argument form calls it): back-date window for the made-at day
select public._w1b_patch('public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)'::regprocedure, 'bos89', array[
  $a$if at_ > now() + interval '10 minutes' then raise exception 'bad_date'; end if;$a$,
  $a$if at_ > now() + interval '10 minutes' then raise exception 'bad_date'; end if;
  perform public._w1b_backdate_check('production', (at_ at time zone 'Asia/Dhaka')::date, p_client, 'production_runs');   -- bos89$a$]);
```

Hook summary: `lock_check` (pure date test, owner mode, windows), `_acct_locked` (user-independent only when owner mode is log/reason), `record_sale2` (late offline sale policy; new variable `lt89`), `cash_move_add`, `quick_expense_add`, `save_purchase`, `production_post` (7-argument form) for the back-date limit. The back-date check sits AFTER the duplicate-client-id answer, so a retried record is never refused.

## Web hooks (integrator-owned files)
- `web/index.html`: add `<script src="periodlock.js"></script>` after `moneyaccounts.js`.
- `web/ia.js`: `rec('periodlock', 'acc', ['Period lock', 'Period lock', 'Period lock'], { icon: 'lock', ok: (c) => c.own || c.GF.accounts_manage === true, kw: ['period lock', 'lock books', 'close month', 'closed period', 'override', 'back date', 'late sale', 'offline sale', 'lock date', 'reopen'], verbs: ['lock the books', 'open an override window', 'set back-date limit', 'decide a held sale'] })` (use an existing icon key; the server decides, non-owners only see the state).
- `web/pos.js`: when `record_sale2` returns `{parked: true, held_id}` (policy park) the phone must treat it as sent (no retry loop) and show "Held for the owner" instead of a receipt. Not written here (pos.js is integrator-owned). A parked sale has no receipt number until the owner accepts it.
- Optional: an attention count `held_sales` from `period_lock_state()` for the owner Home.

## Behaviour notes
- Owner modes: off = silent as today; log = allowed, one `period_lock_exception` line and one audit line `period_owner_closed_date` per transaction and date; reason = refused (`period_closed_reason_required`) until `period_override_start` (reason, dates, minutes; for himself or a named person, scope lock / backdate / both, optional document type). Every use: one audit line `period_override_used` and one Exceptions line (first use per transaction).
- Non-owner order unchanged: role grant `closed_period_edit`, phase87 one-off grant, then (new) an override window opened for that person.
- Posting: with owner mode log/reason `_acct_locked` ignores who asks, so autopost skips a document dated in a closed month for everyone. With off the old user-dependent answer remains. An edit made under an override window does not change a closed month's journal by itself; use a manual journal.
- Auto lock: from the day after `auto_lock_day` the whole previous month is closed; the typed date still counts (the later of the two). Auto with a blank day locks nothing by itself and the setting cannot be switched to auto while the day is blank.
- Late offline sale (`park`): the sale is held in `late_sales_held` (idempotent by client id and cashier), exception `late_sale_held` opened. `late_sale_release` (owner or grant holder; the maker cannot decide his own unless he is the owner and `owner_self_approve` is on) records it AS the cashier (identity set for that one call, restored after): accept keeps the sale time, redate uses now, reject records nothing. Prices are the current list prices at release (a drift line appears if the phone showed another). Accept into a closed month fails unless the owner opens a window for that cashier.
- Lateness report covers purchases, cash moves, quick expenses and production (a sale has no entry time).
- Not built (recorded): a block for `accounting_start_date` after an opening is a setting, no exception path (it keeps the books consistent: reverse the opening first).

## Proof
- `supabase/phase89_test.sql`: PART A before the hooks (shared functions untouched, everything as today), PART B installs the hooks on the throwaway database and proves defaults = old behaviour, then every new behaviour. Result on a fresh build through 87 + 89: 182 pass, 0 fail.
- `tests/sql/phase89_before_after.sh`: 12 report snapshots identical before/after phase89 + hooks; a second wave (owner in a closed period, year-2000 cash move, 400-day purchase, 80-hour offline sale, posting run) gives identical P&L, balance sheet, trial balance, cash flow, day book and journal lines against a twin without phase89; no exception line written.
- Older suites (56 files) run on a copy of the database through 87 and on one through 87 + 89 + hooks: identical pass and fail lists (known baseline fails unchanged: 8, 14, 15, 16, 18, 19, 21, 23, 47, 72, 82, 84).
- `tests/web/periodlock_test.js`: 40 assertions, 0 failures, no console errors, 360 px width.

## Not confirmed
Live Supabase, a real phone, real POS offline queue behaviour with a parked answer, `request.jwt.claims` handling on the real Supabase auth.uid() (the release sets both `request.jwt.claim.sub` and `request.jwt.claims`; tested only with the mock auth.uid() that reads `request.jwt.claim.sub`).
