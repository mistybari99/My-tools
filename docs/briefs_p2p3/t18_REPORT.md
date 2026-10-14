# t18 report - gap #18 two-factor (2FA, TOTP) for staff: SAFE CORE (phase71)
Files: supabase/phase71.sql, supabase/phase71_test.sql, web/twofa.js, tests/web/twofa_test.js, docs/TWOFA.md (owner click path + limits), this report. PIN scheme untouched (#16 stays postponed).

## Built
* **SQL phase71 (bos71)**: rules `twofa_required_roles` (text, comma list, default empty = nobody told to) and `twofa_enforce_owner_writes` (switch, default OFF). Helpers `_aal2()` (reads jwt claim `aal` from request.jwt.claims; browser-closed), `_twofa_has_factor(uuid)` (auth.mfa_factors, status verified, dynamic so a DB without the table just says false), `_twofa_guard71()`.
  `twofa_policy()` (any active user: required / has_verified_factor / aal2 / must_enroll / sensitive_actions_blocked_now), `twofa_status_report()` (owner only; per active user roles + verified-factor count + missing flag; no secrets).
* **Guard** injected (tag bos71, one line after the owner check) into ALL FIVE: set_rule, path_switch_set, acct_set_start, year_close_run, set_user_grant. Done by a DO block that takes the LIVE function definition and inserts the line (skips if already tagged or pattern absent), so signatures/privileges/other agents' changes are kept. Refuses `twofa_required` only if switch ON and jwt aal is not aal2 and the user HAS a verified factor (no lock-out for owner without a factor; half-enrolled factor does not count).
* **Web twofa.js** (`#/twofa`, all signed-in users): status (ON/OFF, session level aal1/aal2, factors), enrol (QR from enroll response + secret text + code verify; stale unverified factors cleaned first; cancel removes the unfinished one), turn off (code first -> aal2 -> unenroll), policy notices, owner "who has 2FA" list, honest no-recovery-code warning, bn/mix/en via B.L. Login hook: wraps `sb.auth.signInWithPassword`; with a verified factor a full-screen code box (5 tries, sign-out button) must pass before the original login result is returned; with no factor / MFA off / wrong PIN the original result passes through untouched. Boot check gates a leftover PIN-only (aal1) session on page load.

## Tests
* SQL phase71_test: **26 pass / 0 fail** (mock auth.mfa_factors + request.jwt.claims aal): defaults, helpers closed, _aal2, switch OFF no effect, policy/report, all five refused at aal1 / allowed at aal2, non-owner still "not allowed", no lock-out (no / unverified factor), paste-twice (2nd apply error-free, exactly one bos71 line per function).
* Web twofa_test (playwright, stubbed supabase.auth.mfa): **31 pass / 0 fail** (enrol, wrong/short code, unenroll needs code, stale factor, login gate wrong/right/cancel/5-tries, bad PIN passthrough, boot gate, MFA-off server, 360px overflow). node --check ok.
* Regression (build to phase62 vs +phase71, same test, compare): phase48,49,50,51,52,53,54,60,61 identical, 0 FAIL both (phase62/28/43 were still running at report time; the loop printed 0 diff for the ones finished).

## Lead integration
* script tag (after app.js, any place among page scripts): `<script src="twofa.js"></script>` - must load before the user signs in (wraps signIn at load).
* ia.js line (suggest, adapt to the rec(...) signature in ia.js; page is for everyone, not owner-only, route `twofa`): `rec('twofa', 'twofa', <area/group e.g. settings>, 'lock'-or-existing-icon-key, {bn:'দুই-ধাপ যাচাই (2FA)', en:'Two-factor sign-in (2FA)'}, keywords '2fa otp authenticator totp security')`. I did not touch ia.js; icon key must be an existing one. app.js OWNER_ONLY does not contain `twofa`, so every user reaches it.

## NOT done / UNVERIFIED
* **TOTP enrolment/verify/unenroll/AAL were NOT run against a real Supabase** - only against a stub; real response shapes (`data.totp.qr_code`, `listFactors().data.all`, error texts) follow supabase-js v2 docs from memory. Dashboard click path in docs/TWOFA.md is also unverified against the live UI.
* `_aal2()` reads `request.jwt.claims` (what auth.jwt() returns on Supabase); real JWT aal claim after verify() needs the client to use the refreshed session - not exercised.
* Real auth.mfa_factors columns (user_id, status) assumed from Supabase docs; function runs as definer and degrades to "no factor" if the table is missing.
* Only the five listed functions are guarded; RLS / all other writes still accept a PIN-only session. The code box is a browser gate (bypassable by a modified client); real enforcement = owner-writes switch only. `twofa_required_roles` is informational (no login block).
* No recovery codes; lost phone = owner removes factor in Supabase (documented, with SQL escape hatch if owner is locked). A cancelled code box counts as one failed PIN login in the existing lockout counter (cannot avoid without editing app.js).
* If another phase later re-creates one of the five functions from an older definition, the bos71 line is lost; re-paste phase71.sql last.
