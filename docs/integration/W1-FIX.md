# Integration note W1-FIX: fixes from the independent Wave 1 check (second round)

Branch `w1-check-fixes-2`, base 47ba1e5. Six findings of the independent check, numbered as in the check report: 3 (backup encryption fails open), 4 (void_sale bypasses the return rules), 5 (supplier payment limit is per call), 6 (fictional names in a Wave 1 test and no guard for tests), 7 (test-project reset does not know Wave 1 tables), 8 (staff exit can be undone by linking a login or by a non-owner reactivation).

SQL numbers **phase140 to phase143**, pasted after phase99 in this order. All four are paste-twice safe, no old phase file is edited, every new behaviour starts OFF (one owner setting each) and keeps today's behaviour at its default. Python, node and test-project files are listed in section 6.

## 1. Patched shared functions (patch helper pattern, same as Wave 1)

Phases 140 to 142 patch four old functions by exact text with `_w1x_patch(regprocedure, text[], marker)`: it reads the CURRENT definition, requires every patch text to exist exactly once, requires the new text to carry the marker, and does nothing when the marker is already there (same logic as `_w1c_patch`; markers `bos140` to `bos149`, so it cannot be mixed up with the Wave 1 markers `bos88` to `bos99`). Each phase applies its own hook at the end; `phase143` adds `_w1x_apply_hooks()`, `_w1x_hooks_state()` and `_w1x_expect()` and applies all four again (a no-op when they are in).

| Phase | Function patched | Marker | Hook text added (the site is the line shown first) |
|---|---|---|---|
| 140 | `void_sale(uuid,text)` | bos140 | after `  if s.status = 'void' then raise exception 'already void'; end if;` the line `  perform public._w1x_void_guard(s.id, p_note); /* bos140 */` |
| 141 | `_w1e_pay_gate(uuid,integer,jsonb,uuid,text,numeric)` | bos141 | `  if ov is not null and p_tot > ov and not public.is_owner() then` becomes `  if ov is not null and p_tot + public._w1x_pay_prior(p_supplier) > ov and not public.is_owner() then   /* bos141 */`; and in the request text `\|\| ' (limit ' \|\| ov::text \|\| ')', 300)` becomes `\|\| ' (limit ' \|\| ov::text \|\| public._w1x_pay_note(p_supplier) \|\| ')', 300)` |
| 142 | `employee_link_profile(uuid,uuid)` | bos142 | before `  return jsonb_build_object('id', e.id, 'profile_id', p_profile);` the line `  perform public._w1x_link_after(e.id, p_profile); /* bos142 */` |
| 142 | `employee_status_set(uuid,text,date,text)` | bos142 | before the line `  update public.employees set status = p_status, status_date = p_date, ...` the line `  perform public._w1x_reactivate_guard(e.id, e.status, p_status); /* bos142 */` (it sits next to the phase90 line `_w1c_exit_apply ... /* bos90 */`; the two do not overlap) |

**Re-paste hazard.** Pasting an old phase again (phase3/6 `void_sale`, phase94 `_w1e_pay_gate`, phase41 employee functions) removes the hook of that function. To put everything back, in this order: `select public._i1_apply_hooks();` (Wave 1, phase99) then `select public._w1x_apply_hooks();` (this package). Both are idempotent; `_w1x_apply_hooks()` is one statement, so a patch site that is missing stops the whole call and nothing is half patched (tested). `_i1_apply_hooks()` and the 37 expected Wave 1 hooks are untouched (tested in either order). `select public._w1x_hooks_state();` lists the four expected (function, marker) pairs with `present` true or false.

## 2. Finding 4: `void_sale` follows the return rules (phase140, setting OFF)

Gap: a void puts every unit back on the shelf (trigger `_sale_stock_void`) with no return window, no never-put-back class rule and no expired-batch rule, so a person refused a return could void the sale instead.

Setting `void_follows_return_rules` (switch, **default OFF = today**). When ON, `void_sale` asks the questions `_w1c_return_eval` asks for a full return of the same sale (all quantities back on the shelf, the receipt of this sale counts as shown):

* return window per class (`w1c_return_class_rules.window_hours`) or the general `return_window_hours`;
* a class set to `no_restock` (a void would put it all back);
* `return_expired_restock` = `writeoff` or `block` and any unit of the sale came from an expired batch (a void cannot write goods off, so it may not put them back).

If any rule is broken the void is refused with the same code the return screen already words (`return_window_exceeded`, `return_restock_not_allowed`, `return_expired_restock`) and nothing is written. The owner, and a person holding the grant `return_override` (the owner can give it), may still void: the void note (already required) is the reason and must have three letters (`return_override_reason_required` otherwise); one `audit_log` line `void_override` and one Exceptions row `void_outside_return_rules` (yellow, red when an expired batch is involved) are written. The receipt rule is not asked. A sale with no item lines (quick sale) is checked against the general window only. With the setting OFF the guard returns at once. Departure from the check's wording: the override is the existing grant `return_override` (owner always holds it) instead of "owner only", so one rule serves returns and voids.

Not covered: `void_sale_return` (voiding a return) is unchanged; offline replays call `void_sale`, so they obey the same rule once the hook is in.

## 3. Finding 5: supplier payment limit over several days (phase141, setting 0)

Gap: `supplier_pay_over` (phase94) is compared with ONE call. Setting `supplier_pay_over_cumulative_days` (number 0 to 365, **default 0 = per call as today**). With N more than 0 the limit is compared with this payment PLUS what the SAME person already paid to the SAME supplier in the last N days (`supplier_payments`, not voided, `created_by` = caller) PLUS that person's requests for that supplier still `pending`. An approved request is not added a second time because the payment it creates keeps the maker's login (`_w1e_apply_supplier_pay`); rejected and cancelled requests count for nothing. The owner is still never held. The request text tells the approver why ("limit 5000, plus 3000 already paid or waiting by this person in the last 7 day(s)"). Splitting while a request waits does not help (tested). Only used when `supplier_pay_over` has a number.

## 4. Finding 8: staff exit (phase142, follows `exit_revoke_mode`)

Reproduced on a database built through phase 99 with `exit_revoke_mode` = auto (reproduction script kept in the test file as T2/T4):

1. A person left with no login (`no_linked_login`); `employee_link_profile` later linked a login: the login stayed **active** (the exit step runs only when the status changes). Confirmed.
2. With `on_leave` in `exit_revoke_statuses`, a person with only `employee_manage` set the status back to `active` and phase90 enabled the login the exit had disabled. Confirmed. (For resigned, terminated, retired `employee_status_set` already said `owner_only`; unchanged.)

Fix, no new switch (it is the same owner decision, `exit_revoke_mode`; with it `off`, the default, neither hook does anything):

* after a login is linked to a person whose status is a leaving status, the exit step runs again (`_w1c_exit_apply`): auto = the new login is disabled and its grants end (kept access, the owner role and the caller's own login are handled exactly as at the moment of leaving), alert = the red line `exit_access_open`. Written to `w1c_exit_log` (reason "login linked after the person had left") and one `audit_log` line `staff_exit_link_checked`.
* with mode auto, moving a person from a leaving status to a staying one is refused with `owner_only` when the login was disabled by the exit step (last exit log line is `revoked`). The owner does it as before; the existing step enables the login and logs `staff_exit_login_reenabled` with the reason. A login disabled by someone else, or a person with no login, is not blocked (phase90 rule unchanged).

## 5. Findings 3, 6, 7 (no phase number)

* **3. `tools/backup_dump.py` `resolve_encryption`**: in `auto` mode only a MISSING function (HTTP 404 or PostgREST `PGRST202`, a database older than phase98) means "off". Any other error (network, 5xx, 401/403, an answer that is not an object) stops the run with `RuntimeError`; the failure is logged to `backup_log` by `run()` and no file is written. `--encrypt off` and `on` are unchanged. A night's backup that could not read the setting now fails visibly instead of pushing plain files while the owner believes encryption is on.
* **6. demo/person-like names**: `tests/web/wave1_wiring_test.js` used two roster names and a login id; now `test_staff_01`, `test_cashier`, `test_customer`. A grep of all Wave 1 additions (`git diff 4460d09..HEAD`) in tests/, web/, supabase/, tools/ and docs/ found no other person-like names. Not Wave 1 and left alone: `web/invoice.js` `SAMPLE` (receipt preview) has cashier `karim02` and customer `Rafiq` since commit 976de38; the owner decides whether to rename them. `tools/check_no_demo_leak.py` now also scans every test file (tests/, `*_test.sql`, `*_test.js`, `test_*.py`) for the roster names it already knows, in any letter case, as a ratchet: the files that already carried names are frozen in `tools/demo_leak_test_baseline.json` (file to count of hits, no names); a count may go down, never up, and any other test file must have none. `python3 tools/check_no_demo_leak.py --write-baseline` lowers the baseline after names are removed and refuses to raise it.
* **7. test-project reset**: `supabase/phase84_test_project_only.sql` refuses on a database that has phase 87 and Wave 1 ("tables outside the clear list point at cleared tables: entry_approvers -> entries, w1c_returns -> sale_returns, w1c_returns -> sales") and did not know the Wave 1 tables. It is a test-only file, so the new test-only file `supabase/phase84b_test_project_only_wave1.sql` redefines only the two lists (`_e_reset_tables`, `_e_reset_protected`) as the old lists plus the phase 87 and Wave 1 tables (classification in the file header). The reset function, its three checks (owner, `allow_test_reset` ON, phrase `DELETE ALL TEST DATA`), the reset log and the old file are not changed. **TEST PROJECTS ONLY, never in the live project, never in `tests/sql/ORDER.txt`**; paste it after `phase84_test_project_only.sql` (and again after any later paste of the old file). `supabase/phase84b_test.sql` proves it on a throwaway database; `tools/test_testonly_files.py` guards that neither file is ever listed in the paste order or used by a workflow/tool. `CLAUDE.md` still names only `phase84_test_project_only.sql` in its database-safety rule; the same rule applies to the new file (the owner may want to add its name to that line; not edited by this package).

## 6. Files and tests (local throwaway Postgres 16 on port 5610; live Supabase never touched)

SQL: `supabase/phase140.sql` to `phase143.sql`, `phase140_test.sql` to `phase143_test.sql`, `phase84b_test_project_only_wave1.sql`, `phase84b_test.sql`. Runner: `tests/sql/run_all_sql.sh` (phases 140 to 143 built and tested, old suites compared on the full build, phase84b test run on its own copy), `tests/sql/ORDER.txt` (phases 140 to 143 appended), `tests/sql/phase99_before_after.sh` (takes `PHASES` and `DBP`), new `tests/sql/w1fix_before_after.sh` (the same proof with phases 140 to 143 added). Python: `tools/backup_dump.py`, `tools/test_backup_crypto.py`, `tools/test_testonly_files.py`, `tools/check_no_demo_leak.py`, `tools/demo_leak_test_baseline.json`. Node: `tests/web/wave1_wiring_test.js`.

Results are in `docs/BUILD-LOG.md` (entry "W1-FIX").

## 7. Not confirmed

* Live Supabase, a real phone, real staff. The void and return screens were not changed: they show the server's error code; `web/returnrules.js` already words `return_window_exceeded`, `return_restock_not_allowed`, `return_expired_restock`; the new code `return_override_reason_required` and the new settings are shown by the generic Rules page only (no dedicated switch on the Return & exit rules screen yet).
* `employee_status_set` refusing with `owner_only` for a non-owner coming back from `on_leave` changes a workflow that only exists when the owner counts `on_leave` as leaving AND `exit_revoke_mode` is auto.
* Cumulative limit: payments made by the same person through other doors than `pay_supplier` (for example a purchase bill paid in the same screen) are counted only if they are rows of `supplier_payments` made by that login.
* The `void_sale` expired-batch rule reads `stock_ledger` rows with `reason = 'sale_out'` of that sale; a sale whose goods came from a batch without an expiry is never refused for it.
