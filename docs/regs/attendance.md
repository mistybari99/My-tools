# Registration: module B2 (attendance, leave, payroll, fingerprint) - for the lead to apply

## (a) web/ia.js lines (group `people`; put them after the `salary` line)
```js
  rec('attendance', 'people', ['হাজিরা', 'Attendance', 'Attendance'], { icon: 'check', ok: (c) => c.own || c.GF.attendance_manage === true || c.GF.employee_view === true || c.GF.employee_manage === true, kw: ['attendance', 'present', 'absent', 'late', 'overtime', 'fingerprint', 'device', 'punch', 'shift', 'holiday', 'হাজিরা', 'উপস্থিত', 'অনুপস্থিত', 'দেরি', 'ওভারটাইম', 'ফিঙ্গারপ্রিন্ট', 'শিফট', 'ছুটির দিন'] }),
  rec('leave', 'people', ['ছুটি', 'Leave', 'Leave'], { icon: 'doc', ok: (c) => c.own || c.GF.attendance_manage === true || c.GF.employee_view === true, kw: ['leave', 'holiday request', 'sick', 'casual', 'balance', 'ছুটি', 'অসুস্থ', 'নৈমিত্তিক', 'ছুটির আবেদন'] }),
  rec('payroll', 'people', ['বেতন শিট', 'Payroll', 'Payroll'], { icon: 'money', ok: (c) => c.own || c.GF.payroll_manage === true || c.GF.salary_view === true, home: { acc: 10 }, kw: ['payroll', 'salary', 'payslip', 'wage', 'bonus', 'advance', 'settlement', 'বেতন', 'বেতন শিট', 'পে-স্লিপ', 'বোনাস', 'অগ্রিম', 'মজুরি'] }),
```
web/nav.js: add `attendance_manage` and `payroll_manage` (and `employee_view` if B1 has not yet) to the `codes` list in `loadGrantFlags()` so the `ok` predicates work for non-owners.
Staff with a login and no grant can still open `#/attendance` (check in / out, only when `app_punch_on` is ON) and `#/leave` (their own requests) by link; RLS shows them only their own rows. Add a menu line for them only if the owner switches `app_punch_on` on.

## (b) web/index.html script tags (after stock2.js, which provides B.s2, and after entry.js / app.js; next to employees.js)
```html
<script src="attendance.js"></script>
<script src="payroll.js"></script>
```
Also add both files to the service-worker list in web/sw.js if that file lists pages. Routes: `#/attendance` (tabs Today / Month grid / Device file / Devices / Shifts & holidays), `#/leave`, `#/payroll`.

## (c) SQL, grants and rules (supabase/phase42.sql, run after phase28 and phase41; paste twice is safe)
* Grants (grant_defs, module `people`): `attendance_manage` (default for roles management / showroom_manager / factory_incharge / hr via rule_grants) and `payroll_manage` (nobody by default). The existing `salary_view` is reused: pay figures = owner, salary_view or payroll_manage at the place. Payroll approval and device registration = owner only.
* Rules (Switchboard, module `people`): `attendance_on` (ON), `app_punch_on` (OFF), `att_weekly_off` ("fri"), `att_double_punch_min` (5), `att_ot_min_minutes` (30), `att_ot_cap_hours` (2), `att_late_mode` (count | per_minute | none), `att_lates_per_day` (3), `pay_weekly_off_paid` (ON), `pay_holiday_paid` (ON), `ot_mult_holiday` (2), `att_bonus_amount` (0 = off), `pay_round_net` (nearest), `payroll_on` (ON), `att_push_per_min` (30). The existing `owner_self_approve` decides whether the owner may approve his own manual attendance mark / leave request.
* Tables (RLS, reads only, writes through SECURITY DEFINER functions): shifts, employee_shift_assignments, holidays, attendance_devices (token_hash column not readable), attendance_import_batches, attendance_punches (append-only), attendance_days, leave_requests, employee_advances, employee_advance_recoveries, payroll_bonus_events, payroll_runs, payroll_lines, payroll_payments. A default "General shift" 09:00-18:00 is seeded.
* **anon** may execute exactly one function: `attendance_punch_push(text, jsonb)` (fingerprint bridge, device token). Nothing else is open to anon.
* Day book: `public._daybook_lines23` is re-created (phase23 text kept, two unions added): salary payments from payroll runs (`typ 'salary'`, sensitive) and staff advances paid out in cash / bank / mobile from the advance register (`typ 'advance'`, sensitive; advances with mode `none` are already on a 35-1 form and are not counted twice). Both show only to the owner or salary_view at the place. **If another phase re-creates `_daybook_lines23` later, it must keep these two unions.**
* Owner to do after pasting: (1) Switchboard: check the weekly off day (`att_weekly_off`, default Friday) and the late / overtime rules; (2) Attendance > Shifts & holidays: adjust the shift times, add the year's holidays; (3) Attendance > Devices: register each machine, copy its token once, run `tools/fingerprint_bridge.py` on a PC (docs/FINGERPRINT.md), or import the USB export in Attendance > Device file; (4) give every employee their machine id (Employees > edit "Fingerprint device ID", or link from the "Unknown device ids" list); (5) Payroll > Bonus & settlement: name the festival bonus of the month (e.g. "Eid", the same name as in the pay structures) before previewing that month.
