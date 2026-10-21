# Integration note CRM-B: consent, privacy and duplicate customers (CRM design package B)

SQL numbers (CRM label + 200): **phase303, phase304, phase305** (labels 103 to 105). Paste after phase62 and phase43, in this order, each once; paste-twice safe. No existing file was edited and no shared function was re-created by these three files.
Package CRM-B owns: `supabase/phase303.sql`, `phase304.sql`, `phase305.sql` and their `_test.sql` files, `web/crm_consent.js`, `web/crm_dupes.js`, `tests/web/crm_consent_test.js`, `tests/web/crm_hooks.js`, `tests/sql/crmb_run.sh`, `crmb_build.sh`, `crmb_before_after.sh`, `crmb_fixture.sql`, `crmb_snap.sql`, `phase303_hooks.sql`, this note and `docs/integration/CRM-B_info.json` (plain-English entries for the (i) info sheet).
Names: every new function starts `_crmb_`, every new table starts `crm_`, every new setting starts `crm_`.
Owner rules kept: every policy is a setting with a safe default that keeps today's behaviour; nothing starts by itself; no journal posting and no accounting figure is read or written; exceptions need a written reason; no approver is written in the code (the people who may link are the owner and the holders of the grant `crm_merge`, which the owner gives); English labels only; essentials first on a 360px screen; existing customers need no migration (no row is created for anybody); the tighter privacy is a setting (`crm_pii_guard_on`, OFF).

## 0. What it does, in plain words

1. **Consent.** A customer's "yes" or "no" to messages, per channel (SMS, WhatsApp), can now be written down: by the owner or a customer manager at the customer sheet, from a paper list, and (only when the owner switches it on) by counter staff with a tick at the POS. Each entry keeps how it was given (counter tick, phone, paper form, message reply, owner entry, import), the outlet, the wording version, a note and who wrote it. A "no" cancels waiting messages at once. A "yes" after a "no" needs a reason. A customer never asked has no row and nothing is sent (unchanged). A **do-not-contact** flag stops every channel and beats any "yes".
2. **Privacy by role.** The customer list, the customer sheet and the "Call" button can hide phone numbers and addresses from everybody except the owner and people the owner gave "See customers' full phone and address". Opening a hidden number needs a reason and is logged. The customer export is off, needs a row cap, a reason and the right "Export the customer list", and is logged. Printing a customer list is logged and can be tied to the export right. The default shows numbers exactly as today.
3. **Duplicates.** A "possible duplicates" list (same phone, same name, a name one letter apart) and a **soft link**: two customers are marked as the same person. Customer ids never change; sales, payments, dues and the journal are not touched (proved by a before/after snapshot). The collapsed customer list, the person view and the message check treat them as one; dues stay on each customer.

## 1. SQL

| File | Adds |
|---|---|
| `phase303.sql` | tables `crm_consent_events` (append-only evidence), `crm_contact_prefs` (do-not-contact); settings `crm_consent_pos_on`, `crm_quiet_from`, `crm_quiet_to`; functions `_crmb_consent_set`, `_crmb_consent_set_mobile`, `_crmb_prefs_set`, `_crmb_consent_get`, `_crmb_consent_get_mobile`, `_crmb_consent_history`, `_crmb_consent_summary`, `_crmb_consent_import`, `_crmb_consent_ok` (browser-callable); `_crmb_send_allowed(customer, channel, purpose, now)`, `_crmb_block_reason`, `_crmb_enqueue_guard`, `_crmb_group_root`, `_crmb_group_ids`, `_crmb_patch`, `_crmb_hook_pairs` (closed to browsers) |
| `phase304.sql` | tables `crm_view_log`, `crm_export_log` (append-only, owner reads); settings `crm_pii_guard_on`, `crm_mask_style`, `crm_unmask_reason_required`, `crm_reveal_for_call`, `crm_export_on`, `crm_export_max_rows`, `crm_print_needs_export`; grants `crm_contact_view`, `crm_export`; functions `_crmb_customer_list(limit, collapse)`, `_crmb_customer_profile`, `_crmb_phone_reveal`, `_crmb_export`, `_crmb_print_log`, `_crmb_policy`, `_crmb_consent_register`, `_crmb_view_log_list`, `_crmb_export_log_list` |
| `phase305.sql` | tables `crm_customer_links` (the soft link, append-only, undone by a stamp), `crm_dup_reviews`; settings `crm_dup_check_on`, `crm_dup_similar_names_on`; grant `crm_merge`; functions `_crmb_dup_candidates`, `_crmb_dup_review`, `_crmb_link_customers`, `_crmb_unlink_customers`, `_crmb_customer_group`, `_crmb_links_list` |

* **Table ownership.** The CRM design listed `crm_customer_links` under package A. Package B builds it (this package owns the soft link). Package A must NOT create it; it may read it. Package A's `customer_phones` table is read by the duplicate list when it exists (columns `customer_id`, `phone`, `active`); nothing breaks when it does not.
* **Reuses** `notify_optin` and `notify_optin_log` (written by every consent change, so `notify_enqueue` keeps reading the same rows) and the `rules`, `grant_defs`, `audit_log`, `exceptions`, `no_hard_delete` machinery.
* **Re-paste hazard.** Re-pasting phase62 re-creates `notify_enqueue` and `notify_optin_set` and removes the two hooks of section 2: run `tests/sql/phase303_hooks.sql` again (or add it to the `_i1_apply_hooks` re-patch). Pasting 303, 304 or 305 again changes nothing (proved).
* Build order: 303, 304, 305 after the Wave 1 phases (88 to 99); no dependence on a CRM-A phase.

## 2. SQL hooks (integrator; two statements, file `tests/sql/phase303_hooks.sql`)

```sql
select public._crmb_patch('public.notify_enqueue(uuid,uuid,text,text,jsonb,text,text,text)'::regprocedure, public._crmb_hook_pairs('notify_enqueue'));
select public._crmb_patch('public.notify_optin_set(uuid,text,boolean,text,text)'::regprocedure, public._crmb_hook_pairs('notify_optin_set'));
```

The texts (marker `bosCRMB`; a missing site stops with `patch site not found` and changes nothing; a second paste is a no-op):

1. `notify_enqueue`, directly after its own opt-in check, so a do-not-contact customer, and a customer whose linked duplicate said no, can no longer be queued:

```
  if not exists (select 1 from public.notify_optin o where o.customer_id = p_customer and o.channel = p_channel and o.status = 'in') then raise exception 'not_opted_in'; end if;
  perform public._crmb_enqueue_guard(p_customer, p_channel); /* bosCRMB: do-not-contact and linked duplicates */
  ph := public._i62_phone(c.mobile);
```

2. `notify_optin_set`, before its "opting out cancels" block: one evidence line for a change made the old way (it can never block the change):

```
  perform public._crmb_legacy_evidence(p_customer, p_channel, st, coalesce(p_source, 'owner_entry'), p_note); /* bosCRMB: evidence line */
  if not p_in then   -- opting out cancels what is still waiting
```

Proof: `supabase/phase303_test.sql` T9 copies `notify_enqueue` and `notify_optin_set` into schema `tt`, patches the copies, and shows (a) the real function still queues a do-not-contact customer (today), (b) the patched copy refuses with `do_not_contact`, still refuses the withdrawn customer and the never-asked customer, still queues a normal opted-in customer, (c) the second paste is a no-op, (d) a wrong site stops, (e) the patched `notify_optin_set` copy writes the evidence line while the real one does not. Also run on a database through phase 99: same result.

The campaign package (CRM-D) and the receivable reminders (U-22) should call `public._crmb_send_allowed(customer, channel, purpose, now)` before queueing: it returns `{ok, reason, overridable}`. Reasons: `customer_not_found`, `bad_channel`, `dnc`, `group_dnc`, `opted_out`, `group_opted_out`, `not_asked`, `bad_phone` (none of these can be overridden) and `quiet_hours` (the only overridable one, with a written reason, by the package that owns the override). An explicit opt-out or do-not-contact is never overridable (owner decision OD-C2, built as recommended).

## 3. Web hooks (integrator-owned files; exact text)

`tests/web/crm_consent_test.js` applies exactly these texts to a scratch copy of `web/customers.js` and `web/pos.js` in memory, checks that every old text occurs exactly once in the real file and that THIS document contains each text word for word, and then runs the hooked screens. The real files are not changed by this package.

### 3.1 `web/customers.js`

Site 1. Old text (must occur exactly once):

```js
const r = await sb.rpc('customer_directory'); if (r.error) {
```

New text:

```js
const r = await (B.crmConsent ? B.crmConsent.directory() : sb.rpc('customer_directory')); if (r.error) {
```

Site 2. Old text (must occur exactly once):

```js
const r = await sb.rpc('customer_profile', { p_customer: id }); if (r.error) return toast(eText(r.error));
```

New text:

```js
const r = await (B.crmConsent ? B.crmConsent.profile(id) : sb.rpc('customer_profile', { p_customer: id })); if (r.error) return toast(eText(r.error));
```

Site 3. Old text (must occur exactly once):

```js
<a class="full tog" href="tel:${esc(c.mobile)}" style="text-align:center;padding:10px">${esc(T('menuCall'))}</a>
```

New text:

```js
${B.crmConsent ? B.crmConsent.callHTML(c, T('menuCall')) : `<a class="full tog" href="tel:${esc(c.mobile)}" style="text-align:center;padding:10px">${esc(T('menuCall'))}</a>`}
```

Site 4. Old text (must occur exactly once):

```js
<a class="full tog" href="${esc(wa)}" target="_blank" rel="noopener" style="text-align:center;padding:10px">${esc(T('menuWa'))}</a>
```

New text:

```js
${c.masked ? '' : `<a class="full tog" href="${esc(wa)}" target="_blank" rel="noopener" style="text-align:center;padding:10px">${esc(T('menuWa'))}</a>`}
```

Site 5. Old text (must occur exactly once):

```js
${D.mgr ? b('cu_active', c.active ? T('menuOff') : T('menuOn')) : ''}
```

New text:

```js
${D.mgr ? b('cu_active', c.active ? T('menuOff') : T('menuOn')) : ''}${B.crmConsent ? B.crmConsent.menuHTML(c) : ''}${B.crmDupes ? B.crmDupes.menuHTML(c) : ''}
```

What the five sites do: the list is read through `_crmb_customer_list` (the same columns as `customer_directory`, plus `masked`, `linked_to`, `linked_count`; it falls back to `customer_directory` when phase304 is not on the server); the profile through `_crmb_customer_profile` (same shape plus `masked`); the Call button asks first when the number is hidden (a reason, logged); the WhatsApp link is dropped when the number is hidden; and the menu gets "Messages (consent)" and "Same person / duplicates" buttons only for people who may use them. With the privacy switch OFF (default) nothing is hidden, the tel and WhatsApp links are the same as today.

There is no print or export button in `customers.js` today. If one is added, call `await B.crmConsent.printGate('customer_list', rows.length)` first and print only when it answers `true` (it logs the print and honours `crm_print_needs_export`). The server cannot stop a browser print; the log and the screen rule are the control (stated plainly).

### 3.2 `web/pos.js`

Site 1. Old text (must occur exactly once):

```js
<input id="cu_name" value="${esc(c.name)}">` : ''}</div>`;
```

New text:

```js
<input id="cu_name" value="${esc(c.name)}">` : ''}${B.crmConsent ? B.crmConsent.posStrip(c.mobile) : ''}</div>`;
```

Site 2. Old text (must occur exactly once):

```js
if (B.invoice && B.invoice.offer) B.invoice.offer(data.id, p.p_loc);
```

New text:

```js
if (B.invoice && B.invoice.offer) B.invoice.offer(data.id, p.p_loc);
    if (B.crmConsent && B.crmConsent.afterSale) B.crmConsent.afterSale(p.p_customer_mobile);
```

Site 1 draws "Agrees to messages? Yes / No / Not asked" under the mobile number, only while the owner has switched `crm_consent_pos_on` ON and the cashier may record. Site 2 writes the tick after the sale was sent (by mobile, way `pos_tick`); a sale is never held up or failed by it. A sale queued offline does not write the tick (documented gap; the next tick at the counter will).

### 3.3 `web/index.html` and `web/ia.js`

`web/index.html`: after `customers.js`:

```html
<script src="crm_consent.js"></script>
<script src="crm_dupes.js"></script>
```

`web/ia.js`, group `cust`, one `rec(...)` line each (never rename a route). Labels are English only (owner rule):

```js
  rec('crmconsent', 'cust', ['Customer consent and privacy', 'Customer consent and privacy', 'Customer consent and privacy'], { icon: 'lock', ok: (c) => c.own || c.canPos() || c.GF.customer_manage === true, kw: ['consent', 'opt in', 'opt out', 'do not contact', 'sms', 'whatsapp', 'privacy', 'phone number', 'hide', 'export', 'access log', 'paper list', 'messages'] }),
  rec('crmdupes', 'cust', ['Duplicate customers', 'Duplicate customers', 'Duplicate customers'], { icon: 'users', ok: (c) => c.own || c.GF.customer_manage === true || c.GF.crm_merge === true, kw: ['duplicate', 'same person', 'merge', 'link', 'second number', 'double customer'] }),
```

`ia_test` record count +2 (intentional). `web/sw.js` has no precache list. No Home tile and no bottom-bar slot are taken.

## 4. Settings (module crm, Switchboard / settings hub; the owner only; every change is an `audit_log` line)

| Key | Kind | Default | What it does at the default (= today) |
|---|---|---|---|
| `crm_consent_pos_on` | switch | OFF | Only the owner or a customer manager records consent. ON: POS staff may tick yes / no (counter ways only). |
| `crm_quiet_from`, `crm_quiet_to` | text | blank | No quiet time. Read by `_crmb_send_allowed` only. |
| `crm_pii_guard_on` | switch | OFF | Customer lists show phone numbers as today. ON: hidden except for the owner and holders of `crm_contact_view`. |
| `crm_mask_style` | choice | first3_last2 | Used only while the guard is ON (`017******78`, or last4). |
| `crm_unmask_reason_required` | switch | ON | Only matters while the guard is ON: staff other than the owner write a reason to open a hidden number. |
| `crm_reveal_for_call` | switch | OFF | Only while the guard is ON: ON lets masked staff open one number at a time to call, with a reason and a log line. |
| `crm_export_on` | switch | OFF | No customer export. |
| `crm_export_max_rows` | number | blank | Blank blocks the export even when switched ON. |
| `crm_print_needs_export` | switch | OFF | Anyone who sees the list can print it (the print is logged). ON: printing needs the export right. |
| `crm_dup_check_on` | switch | OFF | No duplicate list, no new link; saving a customer still stops on an identical mobile number. |
| `crm_dup_similar_names_on` | switch | OFF | Names must match after removing spaces, capitals and punctuation. ON: names one letter apart are also listed (a weak hint). |

Grants (nobody holds them until the owner gives them): `crm_contact_view`, `crm_export`, `crm_merge`. The grants are created with `where not exists`, so a package that seeds the same code does not clash.

## 5. Exceptions with a reason, and what is deliberately NOT overridable

* A yes after a no: a written reason; an audit line `crm_consent_resubscribe`.
* Do-not-contact OFF: a written reason, a manager only.
* Opening a hidden number: a reason (setting), a log line, the owner is exempt from the reason but is logged.
* Export: a reason (not for the owner), a row cap, a log line, an audit line.
* Link two customers: a written reason, an audit line and one yellow row in the Exceptions list (form `CRM`, flag `customers_linked`).
* **Never overridable:** sending to a customer who said no or is do-not-contact (OD-C2); a paper list or a bulk import turning a "no" back into a "yes" (the row is kept as `withdrawn_kept`).

## 6. Residual exposure and owner decisions (stated plainly)

1. **Direct table reads.** The policy `customers_read` (phase6) is not changed (risk R6 of the design): a person with POS view can still read the `customers` table through the API, and `find_customer` still returns the number the cashier typed. The privacy switch hides numbers in the CRM functions and screens above; closing the table read is a separate owner decision (OD-C7), because `pos.js` and `dues.js` select `name,mobile` from `customers` directly.
2. **Print.** The server cannot see a browser print; it can only log it when the screen reports it (`_crmb_print_log`).
3. **Retention and "forget this customer" (OD-C17)** is not built; a customer's contact details can be hidden but not erased.
4. **Hard merge (OD-C6)** is not built; only the soft link, as recommended.
5. SMS rules for promotional messages in Bangladesh were not checked; the consent register is evidence, not legal advice.

## 7. Tests and proof

* `bash tests/sql/crmb_build.sh crmb_base 98` builds a throwaway database through phase 98 (port 5572); `bash tests/sql/crmb_run.sh` pastes 303, 304, 305 twice on a fresh clone per suite and runs `phase303_test.sql` (consent, DNC, import, message check, hooks on scratch copies), `phase304_test.sql` (masked list, reveal, export, print, policy, register), `phase305_test.sql` (duplicate list, review, soft link, merge loop, self-duplicate, regroup, unlink, group view, link effect on consent, accounting hash, second-phone table, 2000-customer speed). Negative tests: withdrawn consent blocks queueing, no permission, merge loop, self-duplicate, bad input, anon.
* `bash tests/sql/crmb_before_after.sh`: 24 snapshots (all accounting reports of `p87_snap.sql` and the customer figures of `crmb_snap.sql`: dues, directory, ledgers, balances, profiles, sales, payments, journal party lines, best-customers / lapsed / RFM reports, non-CRM rules) equal before and after pasting, and equal again after every switch is ON and consent, an export, a link and an unlink were done. The customer list at defaults equals `customer_directory` (0 rows differ).
* Web: `node tests/web/crm_consent_test.js <abs tests/web>`.

## 8. UNTESTED

Not run on a real phone or a real Supabase project; no browser was used with real data; the `tel:` call hand-off was not exercised on a handset; PostgREST behaviour of functions whose names start with an underscore was not run (the existing `_w1c_sale_return` uses the same style); the offline POS queue does not carry the consent tick; the 2000-customer speed test used synthetic names (real name distributions may differ); SMS delivery and provider rules were not tested (nothing here sends).
