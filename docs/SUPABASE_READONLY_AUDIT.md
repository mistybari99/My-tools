# Supabase read-only audit — project Islamiya-Bos

Date 2026-10-16 · project `rpqrcmesbhwtyrikabhy` · Postgres 17.11 · region ap-southeast-2 · status ACTIVE_HEALTHY.
Method: only `list_projects`, `execute_sql` (SELECT only) and `get_advisors`. **No change was made.**

## 1. Data state
- 265 public tables, all with RLS enabled. Tables with rows are mostly setup data (items 1,369; options 322; rules 322; forms 46; role_form_perms 118; audit_log ~2,370).
- **`stock_ledger` = 0 rows**, `stock_balance` empty: no stock has ever been posted. `purchase_bills` 0, `production_runs` 0.
- Sales 10 (test), customers 1, entries 1, exceptions 5.
- Accounts: 1 profile; `user_roles` = owner + management on the same user. No other staff.
- Switches: `forms_post_to_ledger` OFF, `blind_count_on` OFF, `owner_self_approve` ON, `period_closed_until` empty, `stock_negative_mode` warn.

## 2. Security advisor (5 lint types)
| Lint | Level | Count | Meaning / suggested action (owner to approve before any change) |
|---|---|---|---|
| authenticated SECURITY DEFINER function executable | WARN | 850 | Signed-in users can call 850 definer functions through the API. Expected for this design (functions enforce grants inside), but each should check `auth.uid()`/grants. Review the list; revoke EXECUTE from `authenticated` on internal helpers (names starting `_`). |
| anon SECURITY DEFINER function executable | WARN | 12 | Callable **without login**. Review these first; revoke from `anon` unless intended (e.g. login throttle, intake). |
| function_search_path_mutable | WARN | 80 | Set `search_path` on those functions (`ALTER FUNCTION … SET search_path = public`). |
| auth_leaked_password_protection | WARN | 1 | Turn on in Dashboard → Auth → Passwords. No SQL needed. |
| rls_enabled_no_policy | INFO | 33 | RLS on, no policy = table closed to API; fine for server-only tables (intake_*, landed_cost_*, telegram_secrets, bos_salt105). Confirm each is meant to be closed. |

## 3. Performance advisor
unindexed foreign keys 197 (INFO) · unused index 124 (INFO, expected: no traffic yet — do not drop now) · auth_rls_initplan 34 (WARN: wrap `auth.uid()` as `(select auth.uid())` in policies) · multiple permissive policies 15 (WARN) · duplicate index 1 (WARN).

## 4. Suggested order (all need owner OK; none done)
1. Dashboard: enable leaked-password protection.
2. Review the 12 anon-callable definer functions.
3. Set `search_path` on 80 functions.
4. Fix 34 RLS initplan policies and the duplicate index.
5. Leave unused-index and FK-index items until real traffic exists.

Full advisor lists were not copied here (about 560 KB of JSON); re-run `get_advisors` for detail.
