# Integration note CRM-G: enquiry and lead pipeline, follow-up tasks (CRM package G, labels 123 to 127)

SQL numbers: **phase323 to phase327** (CRM label + 200, as in `CRM_AUDIT_AND_DESIGN.md` section 4.0). Paste after phase98 (and after 99 or before it, see section 5). Each file is paste-twice safe and stops with a clear message when an earlier file is missing. **No existing file is edited.** No shared SQL function is created again or patched: every new name is `_crmg_*` (functions) or `crm_*` (tables). Re-pasting an older phase can therefore never remove anything of this package; nothing needs a re-patch.

Owner rules kept: every policy is a setting with a safe default (section 2); nothing starts by itself; no reminder is made unless the owner switches that on; **a lead, a quote and a task post nothing** (proved, section 7); reopening a lost lead, a late quote and winning without a quote are exceptions that need a written reason and go to the Exceptions list and the audit log; no approver is written into the code (rights are grants the owner gives to roles or people); English labels only; short screens (essentials first, a More fold) tested at 360 px; a lead is seen per outlet and per right.

## 1. What the five files add

| File | Adds |
|---|---|
| `phase323.sql` | 13 settings (rules, module `crm`), 4 rights (grants), 3 owner-editable lists (lost reasons, sources, occasions, each with the entry Other), tables `crm_leads`, `crm_lead_events`, `crm_lead_quotes`, `crm_tasks`, `crm_task_events`, `crm_lead_lists` (RLS on, closed to browser roles, no hard delete, audit trigger), guards in the database itself (illegal stage jump, lost without a listed reason, a closed lead or task cannot change, a sent quote cannot change, trails are append-only), 3 new kinds on the Exceptions list (`crmg_lead_reopen`, `crmg_late_quote`, `crmg_win_without_quote`, merged into the live constraint without dropping any other kind), helpers, `_crmg_lists`, `_crmg_list_save` |
| `phase324.sql` | `_crmg_lead_save` (create or edit, idempotent on a client key, links the customer who owns the mobile, warns about another open enquiry with the same phone, takes an inbox message), `_crmg_lead_note`, `_crmg_lead_assign`, `_crmg_lead_stage` (enquiry, quoted, following up, won, lost; lost needs a reason from the list), `_crmg_lead_reopen` (reason, exception), `_crmg_quote_save` (items from the item list or typed lines, discount, validity, versions, late reason), `_crmg_quote_respond`, `_crmg_lead_get` (the sheet) |
| `phase325.sql` | `_crmg_lead_convert` (see 3), `_crmg_lead_list`, `_crmg_lead_board`, `_crmg_lead_report` (win and loss) |
| `phase326.sql` | `_crmg_task_save`, `_crmg_task_done`, `_crmg_task_snooze`, `_crmg_task_skip`, `_crmg_my_tasks` (overdue first), `_crmg_task_counts` (Home strip), `_crmg_tasks_sweep`, `_crmg_task_scan` (optional in-app reminders, OFF) |
| `phase327.sql` | `_crmg_status` (what the person may do; drives the buttons), `_crmg_settings`, `_crmg_readiness` (go-live checklist) |
| `web/crm_leads.js`, `web/crm_tasks.js` | the screens `#/crmleads` (Board, Report, Lists; `#/crmleads/<lead id>` opens one enquiry) and `#/crmtasks` (My tasks). English only |
| `docs/integration/CRM-G_info.json` | plain-English (i) texts for every setting, right and screen (also carried in `BOS.crmLeads.INFO`) |

## 2. Settings (all in Settings, module crm; changes are logged by the existing rules audit) and rights

| Rule key | Kind | Default | What the default means |
|---|---|---|---|
| `crm_lead_on` | switch | **OFF** | no enquiry function works; the screen says it is off |
| `crm_task_on` | switch | **OFF** | no task can be added |
| `crm_lead_lost_by` | choice manager / assignee | manager | only a manager closes as lost |
| `crm_lead_reopen_mode` | choice reason / owner / off | reason | a manager may reopen with a reason (Exceptions list) |
| `crm_lead_win_needs_quote` | switch | OFF | an enquiry can be won without a quote |
| `crm_lead_quote_valid_days` | number | blank | the valid-until date must be typed; a quote without one is refused |
| `crm_quote_min_lead_days` | number | blank | no event-date check (a past valid-until date still needs a reason) |
| `crm_lead_stale_days` | number | blank | no stale flag |
| `crm_lead_list_add_mode` | choice owner / manager | owner | only the owner edits the lists |
| `crm_task_default_due_hours` | number | blank | a due date and time must be typed |
| `crm_task_snooze_max_days` | number | blank | no limit |
| `crm_order_task_days` | number | blank | no delivery task when an enquiry becomes an order |
| `crm_task_reminder_on` | switch | **OFF** | no in-app reminder is made |

Rights (`grant_defs`, given to nobody; only the owner has them until the owner gives them to a role or a person): `crm_lead_manage` (see all enquiries of my outlets, give, close as lost, reopen, convert), `crm_lead_all` (every outlet), `crm_task_assign`, `crm_task_all`.

Visibility: the owner and holders of `crm_lead_all` see every enquiry. Everyone else sees an enquiry only inside an outlet the existing `can_loc()` allows, and only as the assignee, the maker, or a holder of `crm_lead_manage`. An enquiry of another outlet answers `not_found` (no hint that it exists). A showroom manager (role `showroom_manager`, listed for one outlet) therefore sees only that outlet unless granted. The existing head-office role `management` passes `can_loc()` for every outlet, as everywhere else in the app, but still sees only enquiries it made, was given, or holds `crm_lead_manage` for. Phone numbers follow `crm_pii_guard_on` when the customer package defines it (masked unless owner, assignee or `crm_contact_view`); the key is read, never created, here.

## 3. How a won enquiry becomes a real record (accounting is never copied)

`_crmg_lead_convert(lead, client key, kind, args)`; manager only; the stage rules run first (so the setting that asks for a quote applies); one conversion per enquiry (a repeat with the same client key returns the first answer, any other repeat is refused `already_converted`); everything happens in one transaction (a refusal leaves the stage as it was).

| kind | what it calls | result |
|---|---|---|
| `online_order` | the EXISTING `online_order_save2` (which calls `online_order_save`) with the quote lines (every line needs an item with a list price), channel, delivery mode and date, address; discount = list price total minus quote total (a quote above list price is refused `price_above_list`); advance 0 | the normal new order (`online_orders`); the inbox message, when the enquiry came from one, is marked converted by the same existing function |
| `form_20_4` | the EXISTING `save_entry` | a **draft** party invoice (doc = invoice) filled from the quote; the person completes and submits it the usual way; nothing is posted by this call |
| `form_20_1` | the EXISTING `save_entry` | a **draft** customer order form (custom, party channel) |
| `link_order`, `link_form` | nothing is created | links an order or a 05-1 / 24-1 entry that exists, same outlet, not cancelled, not already linked to another enquiry |

If `crm_order_task_days` is set and tasks are on, a task for the assigned person is added before the delivery date; it ends by itself when the order is delivered or cancelled (the list hides it at once, `_crmg_tasks_sweep` makes it stick). The caller needs the existing rights of the function used (POS enter and the setting `online_orders_on` for an order; the form right for a form: a showroom manager needs the role that may enter 24-1, e.g. `party_coordinator`).

## 4. Local build recipe (throwaway Postgres on port 5575; live Supabase is never touched)

```
initdb -D /tmp/pg5575 -A trust ; pg_ctl -D /tmp/pg5575 -o '-p 5575 -k /tmp' start ; create roles anon, authenticated, service_role
build phases 8 to 98 in the order of tests/sql/ORDER.txt (docs/HANDOVER_5.md recipe; tests/sql/build_fresh_db.sh with port 5575)
for each n in 323 324 325 326 327: psql -h /tmp -p 5575 -U postgres -d <db> -v ON_ERROR_STOP=1 -f supabase/phase$n.sql   (twice)
tests: psql ... -qAt -f supabase/phase32N_test.sql | grep -E 'FAIL|RESULT'      (each on a fresh database through its own phase)
bash tests/sql/crmg_before_after.sh      (PORT=5575 BASE=<db built through phase 98>)
node tests/web/crm_leads_test.js <abs tests/web> [shots dir]
python3 -I tests/py/test_crmg_info.py ; python3 -I tests/py/test_crmg_hooks.py
```

## 5. Hooks needed (integrator). Each text below was applied to a SCRATCH COPY and proved by `tests/py/test_crmg_hooks.py`, which also checks that every added line is printed here verbatim

### 5.1 `web/ia.js`: two registry lines (group `cust`, "Customers, Orders & Invoices"), placed before the `customers` line

```js
  rec('crmleads', 'cust', ['Party and gift enquiries', 'Party and gift enquiries', 'Party and gift enquiries'], { icon: 'doc', ok: (c) => c.own || c.GF.crm_lead_manage === true || c.GF.crm_lead_all === true || c.canPos(), kw: ['enquiry', 'enquiries', 'lead', 'quote', 'quotation', 'party order', 'wholesale', 'corporate', 'gift box', 'hamper', 'follow up', 'won', 'lost', 'pipeline'], verbs: ['new enquiry', 'send a quote', 'follow up an enquiry'] }),
  rec('crmtasks', 'cust', ['My tasks', 'My tasks', 'My tasks'], { icon: 'doc', kw: ['task', 'tasks', 'to do', 'reminder', 'follow up', 'overdue', 'snooze'], verbs: ['see my tasks', 'add a task'] }),
```

The route is the first segment of the hash, so the pages are `#/crmleads` and `#/crmtasks` (the design's `crm/leads` and `crm/tasks` would dispatch to a page named `crm`). `#/crmleads/<id>` opens one enquiry. No Home tile or bottom-bar slot is taken. The server decides every call; `ok` only hides the entry.

### 5.2 `web/index.html`: two script tags directly after `customers.js` (and before `salesx.js`)

```html
<script src="customers.js"></script><script src="crm_tasks.js"></script><script src="crm_leads.js"></script>
```

### 5.3 `web/nav.js`: the My tasks strip on Home (two edits; silent while tasks are off or nothing is due)

After the existing line that mounts `B.freshness`, add:

```js
  setTimeout(() => { const el = $('#hv_tasks'); if (el && B.crmTasks) B.crmTasks.stripHTML().then((h) => { if (h) el.innerHTML = h; }).catch(() => {}); }, 0);   // bos326 (CRM-G): the My tasks strip (silent while tasks are off)
```

and in the Home template change the start of the `hv_main` assignment from `$('#hv_main').innerHTML = \`${posBtn}${attn}` to:

```js
$('#hv_main').innerHTML = `${posBtn}<div id="hv_tasks"></div>${attn}
```

### 5.4 `web/inbox.js`: "Track as enquiry" on a message (two edits)

Button, directly after the existing Ignore button in the new/seen branch:

```js
<button type="button" class="mini" data-act="ib_ignore" data-id="${esc(String(m.id))}">${esc(T('ignore'))}</button><button type="button" class="mini" data-act="ib_track" data-id="${esc(String(m.id))}">Track as enquiry</button>
```

Handler, directly before `ib_addline`:

```js
  ib_track: async (a) => { const r = await sb.rpc('inbox_get', { p_id: Number(a.dataset.id) }); if (r.error) return toast(msg(r.error)); const m = r.data; if (m.masked) return toast(T('e_not_allowed')); if (!B.crmLeads) return toast('Enquiry tracking is not installed'); try { await B.crmLeads.track({ id: m.id, location_id: m.location_id, customer_name: m.name, phone: phoneLike(m.handle) }); } catch (e) { toast(e.message); } },   // bos325 (CRM-G): turn a message into an enquiry
```

### 5.5 `tools/notify_digest.py`: in-app task reminders from the existing 30-minute job (no change to `notify.yml`)

Directly after the W1-G journal posting block (still inside `if not dry:`):

```python
        try:   # bos326 (CRM-G): in-app task reminders. The server answers "skipped" while the switch crm_task_reminder_on is OFF (default); a failure never stops the alerts.
            ts = api.rpc('_crmg_task_scan', {'p_dry': False})
            res['crm_tasks'] = {k: ts.get(k) for k in ('created', 'people', 'skipped')} if isinstance(ts, dict) else None
            oc.log('task reminders:', res['crm_tasks'])
        except Exception as e:   # the alerts and the digest must never stop because a reminder could not be made
            res['crm_tasks'] = {'error': type(e).__name__}
            oc.log('task reminders failed:', type(e).__name__)
```

The bot needs no new right (`_crmg_task_scan` accepts the ops bot with purpose notify, the owner, or the database scheduler). This is the one line the CRM design called "the single CRM notify hook"; if package E later adds `crm_scan()`, both can sit side by side.

### 5.6 Fresh-build order and the test lists (integrator-owned)

* `tests/sql/ORDER.txt`: add `phase323 phase324 phase325 phase326 phase327` after `phase98` and **before** `phase99` (phase99 stays last).
* `supabase/phase99.sql` `_i1_exc_kinds()`: add `'crmg_late_quote', 'crmg_lead_reopen', 'crmg_win_without_quote'` to the list (and the same three names to the expected list in `phase99_test.sql` T1). Without this the Exceptions constraint keeps the three kinds anyway (phase99 merges what the live constraint holds, proved in `tests/sql/crmg_before_after.sh`), but phase99's own test T1 asserts that the constraint equals its list exactly and will report one difference.
* Test lists: `supabase/phase323_test.sql` to `phase327_test.sql`, `tests/sql/crmg_before_after.sh`, `tests/web/crm_leads_test.js`, `tests/py/test_crmg_info.py`, `tests/py/test_crmg_hooks.py`.

## 6. Settings screen and the (i) info sheet

All 13 rules appear in the Switchboard by module `crm`. `docs/integration/CRM-G_info.json` holds one plain-English entry per setting, right and screen (what it does, why it matters, default, what changes if switched, who can change it); `BOS.crmLeads.INFO` carries the same text for an (i) button. `_crmg_readiness()` is the go-live checklist (switch on, a manager named, lists filled, quote validity decided, orders on, a channel exists, forms on).

Suggested owner order: 1 give the right Manage enquiries to the showroom managers; 2 review the three lists; 3 decide quote validity; 4 switch enquiry tracking on; 5 switch tasks on; 6 reminders last, after the notify hook (5.5) is installed.

## 7. Proof that the books do not move

`tests/sql/crmg_before_after.sh` (local Postgres, uses the existing Wave 1 fixtures and the 33 snapshots of `w1d_snap.sql` and `p99_snap_extra.sql`: P&L, L1 L3 L4 L5, T4, E2, E3, expense report, partner calculation and split, brand P&L, income statement, balance sheet, trial balance, cash flow, day book, day book vs journal, journal lines, posting dry run, stock levels, valuation, movements, customer dues / ledger / balance, supplier balance, returns, payments, cash moves, acct_reconcile):

1. with every CRM-G setting at its default the 33 snapshots are identical before and after the five phases, and after pasting them a second time (and all 59 `_crmg_` function definitions are byte for byte the same on the second paste); no lead, task or quote exists (nothing starts by itself); no setting changed;
2. after EVERY function of the package was used once with everything switched on (a lead, notes, a quote, an order made through `online_order_save2`, a draft party invoice through `save_entry`, tasks, reminders, sweep, report), the snapshots are still identical, the journal / sale / payment / stock / cash-move row counts did not change, every journal entry still balances, no journal entry has a CRM source;
3. phase99 pasted on top keeps the three Exceptions kinds and the snapshots stay identical.

## 8. Tests run (local Postgres 16, port 5575, live Supabase never touched)

See the final lines of `docs/BUILD-LOG.md` after the integrator merges this note; counts at build time: phase323 39, phase324 88, phase325 56, phase326 67, phase327 18 checks, all passing (each on a fresh database through its own phase); before/after 14 checks all equal; web 58 assertions (0 failures, no console errors, no horizontal scroll at 360 px); info test 13; hooks test as listed in 5.

Negative tests present: illegal stage jump (won to enquiry, lost to won, lost to enquiry, in the functions and written directly in the table), lost without a reason / with a reason not in the list / Other without a note, no permission (salesperson, no-role user, head office without the right, manager of another outlet), another outlet's enquiry (`not_found`), double conversion (another key, another kind), a record already linked to another enquiry, a closed lead / sent quote / done task cannot be changed, trails cannot be edited or deleted, a snooze beyond the owner's limit, a skip without a reason, module OFF refuses every function, reminder OFF makes nothing.

## 9. What was not built, and what could not be confirmed

* A **won** enquiry cannot be reopened (final), as the design allows only lost ones; a won enquiry marked by mistake before conversion has no undo yet (owner decision).
* No customer-facing message is sent by anything here (no SMS, no WhatsApp); the reminder is an in-app line to staff only. The campaign package owns customer messages.
* A quote is a priced list on the enquiry. There is no printed quotation document here (the paper form 24-1 in Quotation mode remains the printed one; `quote_ref` can hold its number). The planned quote document of plan item U-23, if built, can be linked through `quote_ref`.
* `online_order_save` always uses today's list price; an order from a quote above the list price is therefore refused and the draft party invoice is the way (its rate is typed).
* The conversion to a draft 05-1 or 24-1 uses `save_entry`, so the rollout mode of the form (paper, parallel, app) and the form switch apply; a refusal from those guards is shown as is.
* UNTESTED: the live Supabase project, a real phone, the real notify workflow run, pg_cron, the board with hundreds of enquiries (the board shows at most 60 cards per stage and the last 30 days of won and lost), the Bangla look (English only by decision), `_crmg_status().staff_here` lists active staff with their names to people who may assign (names are staff data, no phones).
* Not run: the older SQL suites on a database with these phases were not repeated, except `phase99_test` (identical to without, apart from the one expected T1 difference in 5.6) and the before/after script; the packages add no change to any older function.
