# Two-factor sign-in (2FA, TOTP) - gap #18 (safe core)

Bangla summary / সারসংক্ষেপ: পিনের পরে মোবাইল অথেনটিকেটর অ্যাপের ৬ অঙ্কের কোড। এটা ঐচ্ছিক; যাঁর 2FA চালু নেই তাঁর লগইন আগের মতোই (শুধু পিন)। পিনের নিয়ম (`পিন-bos`) বদলানো হয়নি (#16 স্থগিত)।

## 1. Owner: switch MFA on in Supabase (one time, phone browser is fine)
1. supabase.com -> your project.
2. Left menu **Authentication**.
3. **Sign In / Providers** (older dashboards: **Providers**) -> scroll to **Multi-Factor Authentication** (older: Authentication -> Settings -> "Multi-Factor Authentication").
4. Set **TOTP (Authenticator App)** to **Enabled for Enroll and Verify** (both). Save.
   The wording differs between dashboard versions - what you need is: TOTP enrol = on, TOTP verify = on. (UNVERIFIED against the live dashboard: UI labels may have moved.)
5. Paste `supabase/phase71.sql` into the SQL editor (safe to paste twice).
6. Open the app -> `#/twofa` (menu entry added by the lead) -> **Turn 2FA on** -> scan the QR with Google/Microsoft Authenticator -> type the 6-digit code.

## 2. What it does
* After the PIN, a person who has a verified factor must type the code before the app opens. Everyone else logs in with the PIN only, exactly as before.
* `#/twofa` shows status, factors, session level (aal1 = PIN only, aal2 = PIN + code), enrol (QR + secret text), verify, turn off (needs a code).
* Owner can press "Who has 2FA" (server `twofa_status_report()`, no secrets).
* Rules (Rules page, group `security`):
  * `twofa_required_roles` - comma list e.g. `owner,accountant`. Empty (default) = nobody is told to. Informational: the page nags, login is NOT blocked.
  * `twofa_enforce_owner_writes` - default OFF. When ON, these functions refuse with `twofa_required` unless the session is aal2: `set_rule`, `path_switch_set`, `acct_set_start`, `year_close_run`, `set_user_grant`. Applies only to a user who HAS a verified factor (switching it on cannot lock out someone without a factor).

## 3. Limits you must know
* No recovery codes. Lost phone = cannot log in. The owner removes the factor: Supabase dashboard -> Authentication -> Users -> the user -> Factors -> delete. If the OWNER loses the phone and enforcement is ON: SQL editor: `update public.rules set value='false'::jsonb where key='twofa_enforce_owner_writes';` then remove the factor as above.
* The code box in the browser is a UI gate. The server (database) refuses only the five functions above, and only when the switch is ON. All other data access still works with a PIN-only session.
* A cancelled/failed code box signs the person out and the PIN login code counts it as one failed login (existing lockout counter).
* Phone time must be correct (TOTP is time-based).
