# Integration note W1-C: U-03 staff exit revokes access, U-04 sale return control

Package W1-C of Wave 1 (`docs/UNIFIED_BUILD_PLAN.md` section 4.3). SQL numbers: **phase90** (U-03) and **phase91** (U-04). Paste after phase87, in this order: 90, 91. Both are paste-twice safe. No existing file was edited; no shared function is changed by these files. Every new function carries the prefix `_w1c_` (tables `w1c_*`, rules `exit_*` and `return_*`, grants `exit_keep_access` and `return_override`).

Files: `supabase/phase90.sql`, `supabase/phase91.sql`, `supabase/phase90_test.sql`, `supabase/phase91_test.sql`, `web/returnrules.js`, `tests/web/returnrules_test.js`, `tests/sql/w1c_before_after.sh`, this note.

## 1. Owner standing rules, and where this package departs from the plan text

| Rule | How it is met |
|---|---|
| Owner choices are settings with a safe default that keeps today's behaviour, English label and hint, editable any time, every change in `audit_log` | Four exit rules and three return rules in `rules` (table 3), plus per class return rules in `w1c_return_class_rules`. Every change is an `audit_log` line: the table audit trigger (`rules`, `w1c_return_class_rules`) and one explicit summary line (`exit_settings_changed`, `return_rules_changed`, `return_rule_changed`, `return_rule_off`) with old and new values |
| New behaviour only by setting or effective-from date, never changes a historic figure | Defaults: exit mode **off**, no class rule, receipt off, window blank, expired = allow. `w1c_return_class_rules.effective_from` (a rule that starts in three days is not applied today, tested). Nothing historic is rewritten. `tests/sql/w1c_before_after.sh` proves identical P&L, balance sheet, trial balance, cash flow, day book, day book vs journal, journal lines, balance check and posting dry run (12 snapshots) after both phases are pasted twice, after the three hooks, and across a second wave of records |
| Exceptions with required reason, `audit_log`, Exceptions list | Return outside the rules: `_w1c_sale_return(... p_override_reason)` by a person holding the grant `return_override` (the owner always does; the owner can give it to anyone, also through an emergency request because the grant is a window grant). One `audit_log` line `return_override` and one row in `exceptions` (flag `return_override`, yellow; red when the expired-batch rule was broken). Exit: `_w1c_exit_keep(employee, reason)` by the owner or a person holding `exit_keep_access`: `audit_log` line `staff_exit_access_kept` and a yellow row (flag `exit_access_kept`). No path is tied to a role |
| Owner's own-entry approver never hard-coded | Not touched. Nothing here reads or writes `owner_approval_mode` / `entry_approver_set` |
| English labels only | Every label and hint is plain English (the `label_bn` and `label_mix` columns hold the same English text because they are NOT NULL). `web/returnrules.js` has no `L(bn,en,mix)` |

Departures from the plan text (all on purpose, all reversible by one setting):

1. **`exit_revoke_mode` default is `off`, the plan says `auto`.** The owner rule "safe default that keeps today's behaviour" wins. The recommended statuses are already the default of `exit_revoke_statuses` (resigned, terminated, retired), so the owner switches ONE setting to `auto` to get the plan's behaviour.
2. **`return_no_restock_classes` default is empty, the plan says "perishable classes".** Same rule. The screen marks classes that look perishable (they have a shelf-life rule or batches with an expiry) and offers "suggest never put back"; the owner confirms by saving. Per class rules live in the table `w1c_return_class_rules` (restock choice, window hours, receipt need, effective-from, active, note) because the classes are data (`items.category`), not a fixed list of rule keys.
3. **Device tokens.** `attendance_devices` rows are devices at a place, shared by every person there; there is no per person token. Disabling "the person's token" would stop attendance for the whole place. So the rule `exit_deactivate_devices` is **off by default** and, when on, switches off only the device tokens that THIS person registered (`attendance_devices.created_by`). The count is in the log and the audit line. Re-hire does not switch them on again.
4. **Grant name.** The plan says grant `return_restock`; the override also covers window, receipt and expired batch, so the grant is `return_override`.
5. **No `p_restock_lines` parameter on `sale_return`.** Changing its signature would create an overload that PostgREST cannot choose between. Instead `_w1c_sale_return(...)` takes the extra arguments, and a one line hook inside `sale_return` makes direct calls obey the same rules. With the hook, an old screen or an offline replay that calls `sale_return` directly gets the class defaults and is refused when a rule is broken (a hidden button is also a refused request). Without the hook only the wrapper is controlled; the report counts the returns that were saved without the rules (`not_covered`), so nothing is hidden.

## 2. Hooks the integrator must add

All three use the generic helper `_w1c_patch(regprocedure, text[], marker)` (defined in phase90 and again, harmlessly, in phase91). It reads the CURRENT definition, requires every patch text to exist exactly once, requires the new text to carry the marker, and does nothing when the marker is already there. (Phase 87's `_m_patch` has the marker `bos87` fixed inside, so it cannot patch a function that already carries a `bos87` mark and cannot carry a new marker; these three target functions carry no `bos87`, so `_m_patch` would also work if the replacement text contained the literal `bos87`. `_w1c_patch` avoids that.)

The phase99 re-patch file runs these three calls again. They are exact copies of what the tests run on a scratch copy.

```sql
-- Hook 1 (phase90, marker bos90): employee_status_set ends the person's access
select public._w1c_patch('public.employee_status_set(uuid,text,date,text)'::regprocedure, array[
  E'  return jsonb_build_object(''id'', e.id, ''status'', p_status);',
  E'  perform public._w1c_exit_apply(e.id, e.status, p_status, p_date, v_reason); /* bos90 */\n  return jsonb_build_object(''id'', e.id, ''status'', p_status);'
], 'bos90');

-- Hook 2 (phase91, marker bos91): sale_return applies the return rules before it answers
select public._w1c_patch('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)'::regprocedure, array[
  E'  return jsonb_build_object(''id'', rid, ''amount'', amt, ''credit'', credit, ''refund'', refund);',
  E'  perform public._w1c_return_hook(rid); /* bos91 */\n  return jsonb_build_object(''id'', rid, ''amount'', amt, ''credit'', credit, ''refund'', refund);'
], 'bos91');

-- Hook 3 (phase91, marker bos91): a return that wrote goods off cannot be voided
select public._w1c_patch('public.void_sale_return(uuid,text)'::regprocedure, array[
  E'  if r.status = ''void'' then return jsonb_build_object(''dup'', true, ''status'', ''void''); end if;',
  E'  if r.status = ''void'' then return jsonb_build_object(''dup'', true, ''status'', ''void''); end if;\n  perform public._w1c_return_void_guard(p_id); /* bos91 */'
], 'bos91');
```

Proof: `supabase/phase90_test.sql` T14 and `supabase/phase91_test.sql` T12 create a scratch copy of the database (`create database ... template`), apply the patch there, run the behaviour tests, drop the copy and check that the tested database still has the original functions. `tests/sql/w1c_before_after.sh` applies the three hooks and shows nothing financial changes with default settings.

The `ORDER` string for fresh builds (integrator-owned) gets `phase90 phase91` after `phase87`.

Re-paste hazard: phase41 re-creates `employee_status_set`; phase12 re-creates `sale_return` and `void_sale_return`. Re-pasting either removes the hook; run the three calls again (idempotent by marker).

Optional hook 4 (alert scan in the notification run; `notify_scan` is integrator-owned). Without it the owner presses "Check now" on the screen, or a scheduler calls `_w1c_exit_scan_run()`. The red lines it raises (`exit_access_open`) are already picked up by `notify_scan` section 1 (red exceptions):

```sql
select public._w1c_patch('public.notify_scan()'::regprocedure, array[
  E'  select coalesce(sum(v::int), 0) into cnt from jsonb_each_text(made) e(k, v);',
  E'  perform public._w1c_exit_scan_run(); /* bos90 */\n  select coalesce(sum(v::int), 0) into cnt from jsonb_each_text(made) e(k, v);'
], 'bos90');
```

(The patch applies cleanly in a rolled back transaction on a database through phase 91 and the site is unique there. Its behaviour inside `notify_scan` was not run, and `notify_scan` may be patched by other Wave 1 packages: `_w1c_patch` stops with a message if the site is missing or not unique.)

## 3. Settings added (defaults keep today's behaviour)

| Key | Kind | Default | Meaning |
|---|---|---|---|
| `exit_revoke_mode` | choice off / alert / auto | **off** | off = nothing touched; alert = only a red line in Exceptions; auto = login disabled, grants ended |
| `exit_revoke_statuses` | text | `resigned,terminated,retired` | which statuses count as leaving (`on_leave` allowed, not recommended); a trigger on `rules` refuses an unknown status |
| `exit_alert_hours` | number 0 to 8760 | blank (off) | a leaver whose login is still active after N hours gets the red line `exit_access_open` |
| `exit_deactivate_devices` | switch | off | also switch off device tokens this person registered |
| `return_needs_receipt` | switch | off | the receipt number must be typed and match the sale |
| `return_window_hours` | number 1 to 87600 | blank (off) | return window for classes without their own |
| `return_expired_restock` | choice allow / writeoff / block | allow | goods from an expired batch: back on the shelf (today) / written off automatically / refused unless an override |
| `w1c_return_class_rules` (table) | per class | no rows | restock or no_restock, window hours, receipt need (follow general / yes / no), effective from, active, note; a class without a row = today |

Grants (seeded with `on conflict do nothing`, held by nobody except the owner until the owner gives them): `exit_keep_access` (once), `return_override` (window grant, so an approved emergency request also works). Wastage reason `customer_return` is added to the `wastage_reasons` list (it also becomes selectable on the manual wastage screen).

## 4. What each phase adds

Phase 90: tables `w1c_exit_log` (append-only), `w1c_exit_keep`; functions `_w1c_exit_apply` (internal), `_w1c_employee_status_set` (wrapper for the screen: same arguments as `employee_status_set`, does the exit step once with or without the hook), `_w1c_exit_keep`, `_w1c_exit_keep_end`, `_w1c_exit_scan`, `_w1c_exit_scan_run` (internal), `_w1c_exit_settings`, `_w1c_exit_settings_set` (owner only), `_w1c_exit_open_list`, `_w1c_exit_log_list`, helpers `_w1c_patch`, `_w1c_audit`, `_w1c_exc`, `_w1c_append_only`.
Behaviour (mode auto): the login is set to `disabled`, `user_grants.valid_until` is set to now (rows kept), `list_managers` rows are set inactive, one `audit_log` line `staff_exit_access_revoked` with the counts. Re-hire (status back to a non-leaving status) enables only a login that this feature disabled; grants and tokens are not restored. A login holding the owner role and the caller's own login are never disabled by this feature: a red exception tells the owner. A person with no linked login gets a yellow exception. A person disabled by someone else is not enabled by a re-hire.

Phase 91: tables `w1c_return_class_rules`, `w1c_returns` and `w1c_return_lines` (the last two append-only); functions `_w1c_return_eval` (read only check), `_w1c_return_finish`, `_w1c_return_hook`, `_w1c_return_void_guard`, `_w1c_writeoff` (internal), `_w1c_sale_return` (the call for the screen), `_w1c_return_preview`, `_w1c_return_settings`, `_w1c_return_class_set`, `_w1c_return_class_off`, `_w1c_return_global_set` (owner only), `_w1c_return_report`.
Behaviour: when a return is saved, the quantity that may not go back on the shelf (class rule no_restock, the cashier's choice, or an expired batch in mode writeoff) is written off right after the existing return code put it back: same batch, same cost as the sale, through the existing wastage source (`stock_wastage`, reason `customer_return`), so the existing posting run books Dr 5100 wastage / Cr inventory and every entry balances (tested: 5100 = 770 on the fixture). The return itself (money back to the customer, COGS reversal) is unchanged. A refused return writes nothing (whole transaction). A return that wrote goods off cannot be voided (the write-off cannot be reversed in the books: `wastage` has no void); fix with a stock adjustment.

## 5. `web/returnrules.js` and the other web files (integrator)

- `web/index.html`: add `<script src="returnrules.js"></script>` after `moneyaccounts.js`. `web/sw.js`: add it to the precache list if the other screen files are listed.
- `web/ia.js`, group `settings`, one line (owner and people who may act; the server decides):
  ```js
  rec('returnrules', 'settings', ['Return & exit rules', 'Return & exit rules', 'Return & exit rules'], { icon: 'settings', ok: (c) => c.own || c.GF.employee_manage === true || c.GF.sale_return === true || c.GF.return_override === true, kw: ['return', 'sale return', 'restock', 'write off', 'return window', 'receipt', 'perishable', 'exit', 'resign', 'revoke login', 'leave', 'dismiss', 'staff exit', 'keep access'], verbs: ['set return rules', 'staff exit rules'] }),
  ```
  `tests/web/returnrules_test.js` injects the script tag itself, so it passes before and after this line is added. `ia_test` may need its record count +1 (intentional). Do not rename the route `returnrules`.
- `web/salereturn.js` (integrator-owned): call `BOS.returnRules.preview(sale_id, lines, restock_or_null, receipt_or_null)` while the cashier fills the form, render `BOS.returnRules.pickerHTML(preview, {item_id: name})` (one quantity per item to put back, receipt field when needed, override reason field when a rule is broken and the person may override), and save with `BOS.returnRules.saleReturn({ p_client, p_sale, p_lines, p_reason, p_note, p_refund_mode, p_wallet, p_ref, ...BOS.returnRules.collect(rootElement) })` which calls `_w1c_sale_return`. Show `BOS.returnRules.errorText(e)` for the refusals (`return_window_exceeded`, `return_receipt_required`, `return_restock_not_allowed`, `return_expired_restock`, `return_override_not_allowed`, `return_bad_restock_qty`). The answer carries `w1c: { written_off_items, restocked_items, override, rules_broken }`. For `void_sale_return` show `return_written_off` in words.
- `web/employees.js` (integrator-owned): either call `_w1c_employee_status_set` (same arguments and answer, plus `exit`) or keep `employee_status_set` with hook 1. A screen section for keep access and the open list is in `returnrules.js` (tab Staff exit).
- Accounts: nothing to hook. The existing posting run posts the write-offs because they are ordinary `stock_wastage` rows.

## 6. Tests and results (local throwaway Postgres 16 on port 5563; live Supabase never touched)

| Suite | Result |
|---|---|
| `supabase/phase90_test.sql` on a fresh DB through phase 90 | 71 pass, 0 fail |
| `supabase/phase91_test.sql` on a fresh DB through phase 91 | 70 pass, 0 fail |
| `tests/sql/w1c_before_after.sh` | 12 snapshots equal after the paste (twice), equal after the three hooks, wave 2 reports and stock movements equal to the twin without the phases |
| `node tests/web/returnrules_test.js <abs tests/web> [shots dir]` | 44 assertions, 0 failures, no console errors, no horizontal scroll at 360px |
| Older SQL suites (`supabase/*_test.sql`) | 56 suites run on a fresh copy of a database through 87 and of one through 91: identical fail counts in every suite. Known baseline failures are unchanged (phase 8, 10, 11, 12, 14, 15, 16, 18, 19, 21, 22, 23, 47, 72, 82 (3 by design), 84 (needs the test-project file)) |

Negative tests included: HR and cashier refused on every owner function; keep access without reason, with a two letter reason and without the grant refused; owner login and own login never disabled; bad mode, status, hours, window, class, restock value refused; restock more than returned, malformed restock line, restock line for an item not in the return refused and nothing written; window, receipt and expired-batch refusals write nothing; override without the grant refused; second paste safe; logs append-only; no delete.

## 7. Not confirmed

- Live Supabase, a real phone, real staff. `web/returnrules.js` was tested with a stand-in server only; the picker is not wired into `salereturn.js` (integrator).
- `auth.users` is not touched: a disabled profile is refused by every protected call (`is_active()`), but an already issued session token stays valid until it expires and Supabase Auth itself is not told. Banning the auth user needs the Auth admin API and is not done.
- The alert scan runs only when the owner presses "Check now", when hook 4 is added or when a scheduler calls `_w1c_exit_scan_run()`.
- Wastage entries cannot be voided in the books today (existing limit); that is why voiding a return with write-offs is refused.
- Return line units: the write-off is computed in base units from the stock rows the return created; a line whose unit conversion is unknown (existing `stock_unit_unknown` case) has no stock rows, is recorded as `not_tracked`, and nothing is written off.
- Hook 4 (`notify_scan`) was only checked for a clean, unique patch site, not run.

## 8. Fix W1-FIX (phase140): a void follows the return rules when the owner switches it on

Finding of the independent check: `void_sale` cancels a whole sale and the stock trigger puts every unit back on the shelf, with no return window, no never-put-back class and no expired-batch rule, so a refused return could be done as a void. Setting **`void_follows_return_rules`** (switch, default **OFF** = today). When ON, `void_sale` asks the same questions as a full return of that sale (class window or `return_window_hours`; class rule `no_restock`; `return_expired_restock` writeoff/block with units from an expired batch) and refuses with the codes `return_window_exceeded`, `return_restock_not_allowed`, `return_expired_restock`. The owner and anyone holding the grant `return_override` may still void with the void note as the reason (at least three letters): `audit_log` line `void_override`, Exceptions row `void_outside_return_rules` (yellow; red for an expired batch). The receipt rule is not asked. Hook: one line in `void_sale` (marker `bos140`) written by `_w1x_patch`; details, re-paste order and tests in `docs/integration/W1-FIX.md`. Hook 3 above (`void_sale_return`) is unchanged.
