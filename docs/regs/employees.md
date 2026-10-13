# Registration: module B1 (employees) - for the lead to apply

## (a) web/ia.js lines (group `settings` does not fit people; `acc` is used because staff cost lives with accounts. Move to another existing group if you prefer)
```js
  rec('employees', 'acc', ['কর্মচারী', 'Employees', 'Employees'], { icon: 'users', ok: (c) => c.own || c.GF.employee_view === true || c.GF.employee_manage === true, kw: ['employee', 'staff', 'worker', 'register', 'salary', 'deed', 'photo', 'কর্মচারী', 'স্টাফ', 'কর্মী', 'নিবন্ধন', 'বেতন', 'ডিড'] }),
  rec('employees/new', 'acc', ['নতুন কর্মচারী নিবন্ধন', 'Register an employee', 'নতুন Employee নিবন্ধন'], { icon: 'plus', ok: (c) => c.own || c.GF.employee_manage === true, kw: ['new employee', 'add staff', 'registration', 'নতুন কর্মচারী', 'নিবন্ধন'] }),
  rec('deeds', 'acc', ['ডিড ও চুক্তি', 'Deeds & agreements', 'Deed ও চুক্তি'], { icon: 'doc', ok: (c) => c.own || c.GF.deed_manage === true || c.GF.employee_manage === true, kw: ['deed', 'agreement', 'contract', 'guarantor', 'security deposit', 'ডিড', 'চুক্তি', 'জামিন', 'জামানত'] }),
```
`#/employee/<id>` (the profile) is opened from the list, it needs no menu line. Pages are reached by `employees` / `employee` / `deeds` in `window.BOS_PAGES`.

web/nav.js: add `employee_view`, `employee_manage`, `deed_manage` (and `salary_view` if not there yet) to the list of grant codes that fill `GF`, so the `ok` predicates above work for non-owners.

## (b) web/index.html script tag (after stock2.js, which provides B.s2, and after entry.js/app.js; put it next to the other late pages, e.g. after recipes.js)
```html
<script src="employees.js"></script>
```
Also add `employees.js` to the service-worker file list in web/sw.js if that file lists pages.

## (c) SQL and rules (supabase/phase41.sql, run after phase28; paste twice is safe)
* Grants (grant_defs, module `people`): `employee_view` (default for roles management / showroom_manager / factory_incharge via rule_grants), `employee_manage`, `salary_manage`, `deed_manage`. The existing `salary_view` is reused for pay figures. Owner passes all; non-owners get the rest from Delegation / user grants.
* Rules: `employees_module_on` (ON), `employee_mobile_unique` (ON), `deed_expiry_warn_days` (30).
* Lists: option_lists `emp_designation` (12 values), `emp_department` (6 values), owner-edited (list_defs add_rule = owner).
* Tables (RLS, reads only): employees, employee_locations, employee_status_log, employee_documents, employee_pay, employee_pay_components, employee_benefits, employee_leave_entitlements, leave_types, staff_roles, deed_templates, employee_deeds. The columns employees.bank_account / mobile_wallet and employee_benefits.value_per_month are closed to the browser (read through salary_view functions).
* Storage (private bucket `photos`): new policies `emp_photos_insert` / `emp_photos_read` for the prefixes `EMP/<place>/` (portraits) and `EMPDOC/<place>/` (documents, employee_manage only). The bucket allows only image/jpeg, so documents are photographed pages.
* For attendance / payroll (B2): schema cheat sheet at the top of supabase/phase41.sql; server helper `public._emp_pay_on(employee, date)`.
