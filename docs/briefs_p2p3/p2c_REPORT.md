# p2c report - attendance counted once (#29), form retry queue (#19), equation recompute (#20)
Files: supabase/phase54.sql, supabase/phase54_test.sql, web/attend2.js, tests/web/attend2_test.js (nothing else touched). Run phase54 AFTER phase51.

## Task A - gap #29 (built)
* Shadow engine: new path_domains row `attendance` (insert ... on conflict do nothing). Path A = attendance record (punch / device / app / manager entry), path B = form 02-1. Default primary = A.
  A submitted/approved 02-1 whose place+month path A already holds becomes a LOCKED shadow (existing phase50 trigger blocks edits/re-open); if path A has nothing for that month the form stays the only record.
  Primary b or "lock path B" work through the existing Switch board (`path_switch_set('attendance', ...)`); a locked B refuses new 02-1 (`path_locked`); a locked A refuses self punch and mark-others.
  `attendance_form_link_run(loc, month)` links late; `attendance_count_once(loc, month)` is a read-only per-person report (record vs register, which one is counted, shadows, differences).
  Form 14-1 is deliberately NOT mapped: it is the cash-drawer sheet, a path lock would stop the drawer count; it has no staff attendance rows.
* (a) Self punch: `attendance_self_punch(...)` + `att_my_status()`. Master = existing rule `app_punch_on` (OFF). Owner locks per person or per role: `att_self_lock_set` (table att_self_lock, audited). Old `attendance_app_punch(dir)` is now a thin wrapper (bos54), same errors / 1-minute rule.
* (b) Evidence only: `att_evidence_reg` (kinds webauthn, face_photo, finger_device) = flag + reference, no biometric template. Punch stores evidence_kind/ref/state (registered|unregistered|none) and soft GPS flag (ok|outside|no_fix|unchecked, never refuses). Place coordinates: `att_site_geo_set` (owner). Fingerprint only as a flag set by a manager ("enrolled on the device"); real fingerprint punches still come through the phase42 device bridge.
* (c) New grant `attendance_mark_others` (NO role has it by default; owner assigns it to a person at a place). `attendance_mark_others(emp, day, status, in, out, rest_min, source device|finger|face|manual, reason, note, client)` : closing time = out, rest minutes stored, cannot mark himself, bos path guard, payroll lock (`month_locked`), client-id idempotent, every call in append-only `att_mark_log54` (with previous row). Pending approval via the existing attendance_approve. `att_others_board` for grant holders. A trigger resets rest/tag if a plain attendance_mark later overwrites the day.
* Honest limits are in the UI (collapsible "Honest limits" box + hint under the source tag + 14-1 note) in bn / en / mix, and in the SQL header and function answers (`evidence_only_not_identity_proof`).

## Task B
* #19 forms retry queue: ALREADY EXISTS (web/entry.js W5a: localStorage queue, client_id meta, retry on online, #/outbox, tests/web/outbox_test.js). I did NOT touch it. Added in attend2.js a generic client-id RPC outbox `BOS.rpcq` (IndexedDB + localStorage copy, resend on online / start / 30 s, server answer to a repeated key is a success, server refusals kept visible and not retried, `saveEntry()` helper that queues save_entry with its client_id meta). It is wired into "Mark others" only; the form screen still uses its own queue (switching entry.js to rpcq = lead decision, not done).
* #20 `entry_equation_check(entry)` (read-only) for 10-2 and 02-2: re-works total, cash+receipts vs imprest, no-receipt amount, over-limit, per-person net / other-without-reason / unsigned payments, t_net; lists differences against the flags the phone stored (flag_missing / flag_extra / amount_differs) + information line receipts_vs_net. 14-1 NOT covered (returns supported=false). Optional switch `entry_equation_flag_on` (OFF): deferred constraint trigger raises one red exception `equation_mismatch` after a submit; does not block the submit and does not touch submit_entry. Page `#/eqcheck` lists the last 30 10-2 / 02-2 sheets with a Check button.
  Note: totals are not stored in entries.data (computed on the phone), so "mismatch" = recomputed flags vs stored flags; limits (expense_max, imprest) are read as they are today.

## Switches / defaults
app_punch_on (existing, OFF), att_geo_check_on OFF, att_geo_radius_m 300, entry_equation_flag_on OFF, path switch attendance: both open, primary a. Grant attendance_mark_others: nobody.

## Tests
* SQL phase54_test.sql: 84 pass / 0 fail on a fresh build (phase8..51 + 54); phase54.sql applied a 2nd time: no error. Covers locks (person/role/path), evidence, soft GPS, mark-others (grant, scope, self, client id, log append-only, payroll lock), shadow link / lock / primary b / path B lock / link-run, equation cases (10-2, 02-2, Bangla digits, 14-1), red exception ON/OFF.
* Web tests/web/attend2_test.js: 37 asserts, 0 failures, no JS errors, no overflow at 360px.
* Regression (built through 54 vs built through 51, FAIL lines compared): phase42 160/0 same, phase50 same, phase51 same, phase13, 17, 18, 21 identical. phase48_test: 3 expected FAILs (T0, T1, T6 hard-code "7 domains"; now 8 because of the new `attendance` domain) - update those three counts to 8 in phase48_test (not my file). Everything else in phase48_test same.

## ia.js / index.html lines for the lead
```
<script src="attend2.js"></script>   (after attendance.js)
rec('attend2', 'people', ['হাজিরা ২ (পাঞ্চ, লেখা, একবার গোনা)', 'Attendance 2 (punch, mark, counted once)', 'Attendance 2 (punch, mark, একবার গোনা)'], { icon: 'check', ok: (c) => true, kw: ['punch', 'check in', 'passkey', 'face', 'finger', 'gps', 'mark others', 'self punch', 'lock', 'হাজিরা', 'পাঞ্চ', 'আঙুল', 'মুখ'] }),
rec('eqcheck', 'appr', ['সার্ভারে হিসাব মেলানো', 'Server re-check of totals', 'Server-এ হিসাব মেলানো'], { icon: 'check', ok: (c) => c.own || c.anyApprove(), kw: ['equation', 'total', 'recompute', 'mismatch', '10-2', '02-2', 'হিসাব', 'মেলানো'] }),
```
Also add `'attendance_mark_others'` to the `codes` list in nav.js loadGrantFlags if you want a non-owner grant holder to see it in navigation (`ok: true` already shows the page; the Mark tab explains if the grant is missing).

## NOT done / UNVERIFIED
* Real WebAuthn / face / camera / GPS not exercised on a device: headless test stubs navigator.credentials and geolocation. Passkey assertions are NOT verified server-side (impossible without a challenge store); evidence is a reference, not identity proof.
* Existing 02-1 readers (salary_report attendance list, report engine attendance_summary) were not re-created to skip shadow forms; payroll itself reads attendance_days only (not 02-1), so no money is double counted, but those two reports still list every submitted 02-1 including shadows.
* Only ONE 02-1 per place+month is shadowed (one link per month key); a second register for the same month stays visible as a record and is shown as a difference in the report. Person matching in the report is by name / employee no. (unverified for messy names).
* Device / file imports are not blocked by a locked path A (data from machines is always kept).
* #19: entry.js not migrated to rpcq (it already has a working queue). #20: 14-1 not covered; the red-exception switch is only tested with direct submit_entry.
