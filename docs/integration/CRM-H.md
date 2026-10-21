# Integration note CRM-H: customer feedback and complaints (design 3.1.H, audit rows 46-48)

SQL numbers: **phase328** and **phase329** (CRM label 128 and 129, repo number = label + 200). Paste after phase98, in this order: `phase328`, `phase329`. Both are paste-twice safe. **No existing file is edited.** No shared SQL function is re-created, so re-pasting an older phase can never remove anything of phase328 or phase329. If phase328 is pasted again later, paste phase329 again too (it only adds).

Owner rules kept: every choice is a setting with a safe default and an English label and hint; nothing starts by itself (complaints and ratings are OFF); **a complaint posts nothing** (a refund is made on the existing sale return screen and only LINKED here, read only); closing without a result needs a reason and writes one `audit_log` line and one Exceptions line; the approver is never hard-coded (rights are grants, the owner always passes); English labels only; one short screen at 360 px with the essentials first; every list is cut by outlet and by role.

## 1. What phase328 adds (complaints with a clock)

| Name | Kind | Notes |
|---|---|---|
| `crm_complaints` | table | Outlet, customer (id or free text), sale, online order, item, category (editable list), severity, food-safety mark, text, batch note, status, owner, `due_at` (the SLA clock), first response, result, close reason, `sla_met`, `breached_at`, repeat flag. Closed to browsers (RLS on, no grants). No delete. |
| `crm_complaint_events` | table | Append only trail: created, assigned, status, note, contact, severity, link_return, sla_breach, repeat, food_safety, reopen. |
| `crm_complaint_returns` | table | A finished `sale_returns` row linked to a complaint (one return belongs to one complaint). |
| trigger `crm_complaints_guard` | trigger | The database refuses an illegal status move (`illegal_status_change`), locks a closed row (`complaint_locked`) and refuses a change of outlet, ticket number or author (`complaint_immutable`). Statuses: `open` -> `in_progress` / `resolved` / `closed_no_resolution`; `in_progress` -> `resolved` / `closed_no_resolution`; `resolved` -> `closed` or back to `in_progress` (reopen, reason needed). |
| lists | `option_lists` | `crm_complaint_cats` (the nine causes of form 32-1), `crm_resolution_types`, `crm_close_reasons`. The owner adds or retires entries on the lists screen. |
| grants | `grant_defs` | `crm_complaint_log`, `crm_complaint_manage`, `crm_feedback_view`. Nobody holds them by default. |
| `_crmh_complaint_save(p_client, p)` | API | Log a complaint. Outlet comes from the receipt or order. Idempotent on `p_client`. |
| `_crmh_complaint_assign`, `_crmh_complaint_note`, `_crmh_complaint_move`, `_crmh_complaint_severity_set`, `_crmh_complaint_link_return` | API | Owner, notes and calls, status moves, severity change (the clock restarts from the logged time), link a finished return. |
| `_crmh_complaint_list(p)`, `_crmh_complaint_get(id)`, `_crmh_counts()`, `_crmh_settings()` | API (read only) | Lists are cut by outlet and role; a phone number is masked unless the caller may see it. |
| `_crmh_sla_scan(p_dry)` | API | Marks each newly overdue complaint once (`breached_at`, one event, one Exceptions line). Allowed: owner, a manager (own outlets only), the notify bot, the database scheduler. A dry run writes nothing and works while the switch is OFF. |
| helpers `_crmh_*` (rights, mask, events, audit, exception, repeat count) | internal | Closed to browsers. |

## 2. What phase329 adds (ratings, repeats, report)

| Name | Kind | Notes |
|---|---|---|
| `crm_feedback` | table | One star rating (1 to 5) with a short comment for ONE sale or online order. One rating per sale and per order (unique indexes). A rating cannot be edited; only the follow-up fields and the complaint link change. |
| `_crmh_feedback_add(p_client, p)` | API | Rate a sale or order. Refused: switch off, bad stars, cancelled sale or order, other outlet, too old (if a window is set), already rated. |
| `_crmh_feedback_followup(id, note)` | API | Record the follow-up call when the stars were at or under the threshold. |
| `_crmh_feedback_to_complaint(id, p)` | API | Open a complaint from a rating (a complaint only, never a refund). Pressing twice returns the same complaint. |
| `_crmh_feedback_list(p)`, `_crmh_feedback_settings()` | API (read only) | The rating list with average and calls needed. |
| `_crmh_repeat_list(p)` | API (read only) | Customers with repeat complaints in the window. Answers `days_required` while the check is off. |
| `_crmh_report(p)` | API (read only) | Complaints and ratings by outlet, item, category, severity or month, for a period (up to 366 days). Complaint columns: total, open, resolved, closed without a result, overdue now, went overdue, SLA met or missed, food safety, repeats, average hours to resolve, value of linked returns. Rating columns: count, average, stars 1 to 5, calls still needed. By item, a rating counts for every item on its sale or order. |

## 3. Settings (all in the Switchboard under module `crm`; every default keeps today's behaviour)

| Rule key | Default | Meaning |
|---|---|---|
| `crm_complaints_on` | **OFF** | Master switch for complaints. OFF = every write answers `complaints_off`. |
| `crm_complaint_sla_hours_low` / `_medium` / `_high` / `_critical` | **blank** | Target hours to resolve, per severity. Blank = no clock for that severity (state "No clock"). |
| `crm_complaint_fs_exception_on` | ON (only matters once complaints are ON) | A food-safety complaint adds one red line to the Exceptions list. |
| `crm_complaint_fs_categories` | `sick` | Categories that always count as food safety (comma list). Set it to blank (type two quote marks on the Rules page) to let only the box decide. |
| `crm_complaint_fs_severity` | `keep` | `keep` / `high` / `critical`: the lowest severity of a food-safety complaint. |
| `crm_complaint_breach_exception_on` | ON (only matters once complaints are ON and a clock is set) | Newly overdue complaint adds one yellow line (red if food safety) when the check runs. |
| `crm_repeat_days` | **blank** | Repeat check look-back. Blank = no check. |
| `crm_repeat_min` | 2 | Complaints needed, this one included. |
| `crm_repeat_scope` | `customer_item` | `customer_item` or `customer`. |
| `crm_feedback_on` | **OFF** | Master switch for ratings. |
| `crm_feedback_low_max` | **blank** | A rating at or under this many stars needs a follow-up call. Blank = none. |
| `crm_feedback_window_days` | **blank** | Refuse a rating for a sale older than this. Blank = any age. |

The plain-English entries for the (i) info sheet are in `docs/integration/CRM-H_info.json` (what it does, why it matters, default, what changes if switched, who can change it).

## 4. Who sees and does what (the server decides; a hidden button is also a refused request)

| Person | Log a complaint / rating | See lists and report | Move, assign, close, link a return, check overdue |
|---|---|---|---|
| Owner | every outlet | every outlet, full phone | yes |
| Holder of `crm_complaint_manage` (and works at the outlet) | yes | own outlets, full phone | own outlets |
| Holder of `crm_feedback_view` | no | own outlets, phone masked | no |
| POS enter staff (cashier) | own outlet only | only what they logged themselves or own; phone masked | only start and resolve a complaint assigned to them |
| Everybody else | no | nothing | no |

A person is held to the outlets given in `user_locations` (the management role sees all, as everywhere else). Closing without a result, closing a food-safety complaint and reopening are for managers.

## 5. Hooks the integrator adds (each text below was proved on a scratch copy; see section 7)

### 5.1 `web/index.html`: one script tag, next to `customers.js`

```html
<script src="crm_feedback.js"></script>
```

`web/sw.js`: add `crm_feedback.js` to the precache list if the screen files are listed there [not checked].

### 5.2 `web/ia.js`: one line next to the `freshness` record (group `cust`; the test injects this same line)

```js
  rec('crmfeedback', 'cust', ['Feedback and complaints', 'Feedback and complaints', 'Feedback and complaints'], { icon: 'users', ok: (c) => c.own || c.GF.crm_complaint_log === true || c.GF.crm_complaint_manage === true || c.GF.crm_feedback_view === true || c.canPos(), kw: ['complaint', 'feedback', 'rating', 'stars', 'review', 'food safety', 'overdue complaint', 'customer complaint', 'unhappy customer', 'refund complaint', 'repeat complaint'] }),
```

No Home tile or bottom-bar slot. Do not rename the route `crmfeedback`. `ia_test` record count +1 (intentional).

### 5.3 `tools/notify_digest.py`: the overdue check, once every 30 minutes, with the existing notify bot

Add right after the W1-G posting block (inside `if not dry:`; the anchor is its last line `oc.log('journal posting failed:', type(e).__name__)`; if W1-G is not integrated, put it after `oc.log(f"scan: {sc.get('created')} new notification(s)")` instead):

```python
        try:   # bos328 (CRM-H): mark complaints that passed their target time. The server answers "skipped" while the switch crm_complaints_on is OFF (default).
            cs = api.rpc('_crmh_sla_scan', {'p_dry': False})
            res['complaints'] = {k: cs.get(k) for k in ('marked', 'skipped')} if isinstance(cs, dict) else None
            oc.log('complaint check:', res['complaints'])
        except Exception as e:   # the alerts and the digest must never stop because the complaint check failed
            res['complaints'] = {'error': type(e).__name__}
            oc.log('complaint check failed:', type(e).__name__)
```

The bot needs no new grant: `_crmh_sla_scan` accepts `_is_ops('notify')`. Without this hook the page still shows the live overdue state (it is computed from the time) and a manager can press "Check for overdue now"; the hook only makes the Exceptions line and the marker appear without a person pressing a button.

### 5.4 Optional, not provided: rating chips after a sale in `web/pos.js`

The design mentions "rating chips after sale". It needs the exact success point of the sale in `pos.js` (owned by the integrator) and was **not** written or tested here. The ratings tab already records a rating by receipt number. A later hook can call `_crmh_feedback_add` with the new sale id.

### 5.5 Switch list

`ORDER` string (`tests/sql/ORDER.txt`, integrator): append `phase328 phase329` after the last phase. Test lists: `phase328_test.sql`, `phase329_test.sql`, `tests/web/crm_feedback_test.js`, `tests/sql/crmh_before_after.sh`, `tools/test_crmh_hooks.py`.

## 6. Overlap with the unified plan (U-25)

U-25 plans its own `complaints` table and a batch trace screen. These tables are named `crm_complaints` and do not clash. If U-25 is built later the owner picks one register: the recommended path is to keep `crm_complaints` for the clock, owner and report and let U-25 add the batch trace and hold-batch part, reading `crm_complaints.batch_ref`. `crm_complaints.sale_id`, `item_id` and `batch_ref` are the join keys. Nothing here reads or writes the paper form 32-1 and the `q3_complaints` report is untouched.

## 7. Proof

* `supabase/phase328_test.sql` (122 checks) and `supabase/phase329_test.sql` (83 checks) on a local throwaway Postgres (port 5576) built with phases 8 to 98: defaults, illegal status changes, no permission, other outlet, SLA breach marking (dry run, once each, manager limited to own outlet, notify bot, late resolution), food-safety routing, return link refusals, repeat flags, privacy by outlet and role, one rating per sale, paste twice.
* `tests/sql/crmh_before_after.sh`: 33 snapshots of the existing reports (P&L, income statement, balance sheet, trial balance, cash flow, day book, journal lines, posting dry run, stock levels and valuation, customer dues and ledger, supplier balance, returns, payments ...) are identical before and after pasting 328 and 329, after pasting both again, and after every CRM-H setting is switched ON and every function is used.
* `tests/web/crm_feedback_test.js`: 360 px, no horizontal scroll, English in all three language modes, validation before anything is sent, exact RPC arguments.
* `tools/test_crmh_hooks.py`: the notify hook on a scratch copy.

## 8. Not done or not confirmed

* Nothing was run against a real Supabase project, a real phone or a real browser session of the live app.
* The pos.js rating chips (5.4) are not written.
* No message is sent to a customer from any of this (sending belongs to the messaging packages).
* The SLA clock counts wall-clock hours from the time the complaint is logged (no working-hours calendar).
* Batch trace and hold batch (U-25) are not built.
* The Switchboard is expected to list the `crm` module automatically (it groups rules by module); not seen in a browser.
