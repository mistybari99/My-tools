# Integration note CRM-A: customer profile plus and Customer 360 (CRM design package A)

SQL numbers: **phase300, phase301, phase302** (CRM local labels 100-102, repo number = label + 200; the plan reserves 88-239). Paste in this order after phase99 (a database built only through phase98 works too). Each file is paste-twice safe. No existing file was edited. Package CRM-A owns: `supabase/phase300.sql` .. `phase302.sql`, `supabase/phase300_test.sql` .. `phase302_test.sql`, `web/crm_profile.js`, `web/crm_360.js`, `tests/web/crm_profile_test.js`, `tests/sql/crm_a_before_after.sh`, `crm_a_fixture.sql`, `crm_a_fixture_core.sql`, `crm_a_snap.sql`, this note and `CRM-A_info.json`.

Function naming: browser-callable functions are `crma_*`, internal helpers are `_crma_*` (closed to browsers). Tables keep the design names (`customer_phones`, `customer_addresses`, `customer_dates`, `crm_tags`, `customer_tags`, `crm_notes`).

## 0. What it does

- **Profile plus**: extra phones (label, WhatsApp yes/no), delivery points (label, area, landmark, note, one default), family dates (spouse, child, parent birthday / anniversary / other, month + day, year optional), tags (owner-editable list), notes with author and time (append-only, retired with a reason), language (bn / en), preferred outlet, account owner (staff member), customer type from the editable list (`customers.type_code`, it was never writable before) and credit days (credit terms; **informational, not enforced**: enforcement is plan item U-22).
- **Customer 360**: one call `crma_customer_360` (profile + totals + points + favourites + counts) and one paged timeline `crma_timeline` over sales, returns, dues paid, online orders, points, gifts, tier changes and, for holders of `crm_view`, messages, notes and enquiries. `crma_favourites`, `crma_dates_upcoming(days)` (who has a birthday / anniversary / family date in the next N days; for the later CRM "Today" list).
- **Privacy**: `crma_customer_directory` is the masked variant of `customer_directory` (same columns). With the setting off it returns exactly the same rows. `crma_phone_reveal` gives a masked caller the number once, with a reason, and writes one change-log line.
- Each field is optional. **Existing customers need no migration and no backfill**: the main mobile, WhatsApp, address, birthday and anniversary are read straight from `customers`, so the old customer form (`customer_save`) and this package cannot drift apart; the side tables hold only what is additional. (This replaces the backfill in the design, deliberately.)

Nothing changes until the owner switches a setting on (section 3). Proof: `tests/sql/crm_a_before_after.sh` (23 snapshots: day book, P&L, balance sheet, trial balance, cash flow, journal lines, balance check, posting dry run, customer directory / dues / profiles / ledgers / `find_customer` / `customer_pos_info` / balances, the best-customer and customer-dues reports, `customer_save` duplicate answer, and an md5 of the definition of every shared customer / sale / notify function). All equal after the three phases at defaults, and still equal after all three switches are ON and profile data is written. No journal entry is created by the CRM.

## 1. Hooks (all in integrator-owned files; none is needed for the SQL to work)

The exact text below is the text the web test applies to a scratch copy of `customers.js` (`tests/web/crm_profile_test.js`, `HOOKS_CUSTOMERS`); the repository file is not changed by this package.

### 1a. `web/index.html`
After `customers.js`: `<script src="crm_360.js"></script><script src="crm_profile.js"></script>` (360 first; both only use `window.BOS_APP` and `window.BOS`). Add both to the `web/sw.js` precache list if the other scripts are listed there [not checked].

### 1b. `web/ia.js` (one `rec(...)` line, next to the `customers` record, group `cust`)
```js
  rec('crm360', 'cust', ['Customer 360', 'Customer 360', 'Customer 360'], { icon: 'users', ok: pos, drawer: false, kw: ['customer 360', 'customer profile', 'customer history', 'timeline', 'favourite items', 'birthday', 'family date', 'delivery point', 'extra phone', 'tags', 'language'] }),
```
`drawer: false` because the page needs a customer id (`#/crm360/<id>`); it is reached from the customer list. `ia_test` record count +1 (intentional). No `i18n.js` keys: labels are English only (owner rule).

### 1c. `web/customers.js` (four exact-text edits)
1. Masked list (fixes the unmasked `customer_directory` exposure; falls back to the old function if phase302 is not installed):
```
old: const r = await sb.rpc('customer_directory'); if (r.error) {
new: let r = await sb.rpc('crma_customer_directory'); if (r.error && /crma_customer_directory/.test(r.error.message || '')) r = await sb.rpc('customer_directory'); if (r.error) {
```
2. The profile opens Customer 360 (first line of `openProfile`):
```
old: async function openProfile(id) {
new: async function openProfile(id) {
       if (B.crm && B.crm.open360) return B.crm.open360(id);
```
3. "More profile details" button in the edit form (opens the editor sheet; `crm_profile.js` registers the click handler `crm_more` itself). Insert before the Cancel / Save row of `formSheet`:
```
${edit && B.crm && B.crm.openEdit ? `<button type="button" class="full" data-act="crm_more" data-v="${esc(e.id)}">More profile details</button>` : ''}
```
4. Call and WhatsApp links in `menuSheet` must not be built from a masked number. Wrap the two `<a ...>` lines: `${/\*/.test(c.mobile || '') ? '' : `<a class="full tog" href="tel:${esc(c.mobile)}" ...>...</a>`}` and the same with `c.whatsapp || c.mobile` for the WhatsApp link (exact old / new text: `HOOKS_CUSTOMERS` entries 4 and 5 in the test).

### 1d. `web/pos.js` (second-phone lookup, risk R4; text proof only, see UNTESTED)
In `lookup()`, after `find_customer` returns `found:false`, try the other numbers. The sale then goes to the existing customer's main number, so no duplicate customer is created:
```
old: P.cust.found = r.data; if (r.data && r.data.found) P.cust.name = r.data.name;
new: let mm = m; if (r.data && !r.data.found && B.crm && B.crm.findAny) { const a = await B.crm.findAny(m); if (a) { r.data = a; mm = a.mobile; P.cust.mobile = a.mobile; } }
     P.cust.found = r.data; if (r.data && r.data.found) P.cust.name = r.data.name;
old: const ri = await sb.rpc('customer_pos_info', { p_mobile: m }); if (!ri.error && ri.data && normMobile(P.cust.mobile) === m)
new: const ri = await sb.rpc('customer_pos_info', { p_mobile: mm }); if (!ri.error && ri.data && normMobile(P.cust.mobile) === mm)
```
`crma_find_by_any_phone` returns the customer's MAIN number in full (the cashier typed one of the customer's own numbers and the sale needs the main number; `find_customer` has the same exposure for a typed number). If two customers hold the typed number the answer carries `ambiguous: true` and the first (active, oldest) customer is returned.

### 1e. SQL hook for the old `customer_directory` itself (optional, for screens that still call it)
`customer_directory` is not patched. If the integrator wants every caller masked without touching the web, the exact-text patch below was proved on a scratch copy in `phase302_test.sql` T6 (identical to `customer_directory` with `crm_mask_phone` OFF, identical to `crma_customer_directory` when ON). Marker `bos300`; apply with the phase87 / phase88 style exact-text helper; re-pasting phase43 removes it, so add it to the phase99-style re-patch file.
```
old: select c.id, c.mobile, c.name, c.type,
new: select c.id, public._crma_ph(c.mobile) /* bos300 */, c.name, c.type,
old: c.birthday, c.anniversary, c.address, c.whatsapp, c.note,
new: c.birthday, c.anniversary, case when public._crma_show_phone() then c.address end, public._crma_ph(c.whatsapp), case when public._crma_show_phone() or public._crma_view_ok() then c.note end,
```
**Residual exposure (document, owner decision OD-C7):** other screens read `customers` directly through row security (`customers_read` lets every POS-view user select all rows): `pos.js` receipt lookups, `nav.js` search, `filters.js`, `dues.js`, `accounts.js`, `cashmoves.js`, `otherincome.js`, `invoice.js`. Masking is applied only in the new functions. Closing this fully needs a column-level revoke or a masked view on `customers`; that is package CRM-B's decision (design risk R6), not done here.

### 1f. Paste order string (`tests/sql/ORDER.txt`)
Append `phase300 phase301 phase302` after `phase99` (they do not patch anything, so the phase99 re-patch file needs nothing for them except the optional 1e).

## 2. Re-paste hazards
None for the three files (no shared function is patched or re-created). Re-pasting an old phase never removes anything of CRM-A. Only the optional hook 1e is removed by re-pasting phase43.

## 3. Settings (rules, module `crm`; owner only through Switchboard / `set_rule`; every change is an `audit_log` line through `audit_rules`)

| Key | Default | Meaning |
|---|---|---|
| `crm_on` (switch) | OFF | ON: staff may add extras to a profile (language, outlet, delivery points, family dates, tags, notes, type, credit days). OFF: every write answers `crm_off`; reading is unchanged. |
| `crm_second_phone_on` (switch) | OFF | ON: a customer may have extra phone numbers. OFF: only mobile and WhatsApp. |
| `crm_mask_phone` (switch) | OFF | ON: phone numbers and addresses are hidden (017******78) in the new functions for everyone except the owner, a holder of `crm_contact_view`, or a person who already sees mobiles in reports (`rpt_mobile_ok`). OFF = today. The hook text for the old list is in 1c / 1e. |

Grants (`grant_defs`, nobody holds them until the owner gives them): `crm_view` (notes, messages, enquiries in the timeline, upcoming dates), `crm_contact_view` (full phone and address when masking is ON). The design's `crm_mask_style` choice is not built (fixed first 3 + last 2 digits); the design's `crm_pii_guard_on` of package B is the same idea as `crm_mask_phone`: the integrator keeps one of them (recommended: keep `crm_mask_phone`, drop the duplicate).

Exceptions with a reason (all written to the change log): changing the main number (`crma_phone_make_primary`: customer manager, reason of 3+ characters), showing a masked number (`crma_phone_reveal`: reason of 3+ characters), retiring a note (reason of 3+ characters). No role or person is written in the code; the permission is the existing POS-enter right, the existing `customer_manage` grant and the two new grants.

## 4. Tables and functions

Phase300: columns `customers.preferred_location_id / language / owner_user / credit_days` (all nullable), tables above (row security on, **no select grant for browsers** except the tag list, delete guard, change-log trigger; notes have their own append-only guard), rules, grants, helpers `_crma_norm / _mask / _valid_md / _next_date / _on / _mask_on / _contact_ok / _show_phone / _ph / _view_ok / _write_ok / _phones`. `_crma_phones` returns the numbers used to match online orders and inbox messages (they carry a phone, not a customer id): the main mobile always; WhatsApp and extra numbers only when no other customer holds the same number, so one customer's orders never appear on another customer's timeline.
Phase301 writes: `crma_customer_extras_save, crma_phone_add / retire / make_primary, crma_address_save / retire, crma_date_save / retire, crma_tag_save / set, crma_note_add / retire, crma_phone_reveal, crma_find_by_any_phone, crma_phone_conflicts`. A repeated call (client id or natural key) changes nothing and answers `dup: true`.
Phase302 reads (all STABLE, write nothing): `crma_state, crma_customer_360, crma_timeline, crma_favourites, crma_dates_upcoming, crma_customer_directory`.

Online orders and inbox messages are **not** given a `customer_id` column (design said so): adding a trigger or an index on those hot tables is avoided; the match is read-time by phone (design risk R10: at large volume add an index on the normalised phone).

## 5. Tests (all local, throwaway Postgres on port 5571)

| File | Result |
|---|---|
| `supabase/phase300_test.sql` | 34 pass, 0 fail |
| `supabase/phase301_test.sql` | 120 pass, 0 fail |
| `supabase/phase302_test.sql` | 69 pass, 0 fail |
| `tests/sql/crm_a_before_after.sh` | all equal (23 snapshots) at defaults and with all switches ON |
| `tests/web/crm_profile_test.js` | 0 assert failures, no console errors |

Run on a fresh build through phase98 and again on one through phase99, same results. Older suites 43, 62, 76, 9, 88 give the same failing set with and without the three phases; 12 has 1 pre-existing failing line on both.

## 6. UNTESTED / not verified
- Nothing was run on a real phone or against a real Supabase project. Web pieces are tested with mocked server calls at 360 px in a desktop browser only.
- The `pos.js` hook (1d) is proved only as exact-text application (each site found once); no browser run of the POS.
- `crm_profile_test.js` proves the `customers.js` hooks on a patched copy; the integrator must re-run `customers_test.js`, `ia_test`, nav, nav2, control, favsync, settings2 after applying them.
- Real-life data volume (timeline union and the phone match on `online_orders` are read-time scans).
- Whether the SMS queue rows (`notify_outbox`) hold the numbers in `+8801...` form is assumed from `_i62_phone`.
- `docs/BUILD-LOG.md` entry is left to the integrator (shared file).
