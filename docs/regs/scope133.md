# Stage C3 (phase133) - what the web / the lead needs from it (no screen is built in this slice)

No `web/` file, no `ia.js` line and no `index.html` tag were changed by this slice (the B2 slice owns them). The calls below are the contract for the screens that come next. Everything is SECURITY DEFINER, `p_client uuid` where it writes, owner = the group owner.

## Per-business rule values (Switchboard)
| RPC | Who | Returns / does |
|---|---|---|
| `rules_effective133(p_unit bigint default null)` | any active user (own business; the owner any business) | rows `(key, value, source)` with source `business` / `group` / `default`: **the Switchboard and every screen that shows a rule value must read this instead of the `rules` table** (the table holds the group values only) |
| `rule_overrides_list133(p_unit)` | owner, management of that business | the override rows of the business (key, value, group value, active, note) |
| `rule_override_set133(p_unit, p_key, p_value jsonb, p_note, p_client)` | owner | set a value, or `p_value null` = reset (the row is kept, inactive). Errors: `not allowed`, `client_id_needed`, `bad_business`, `rule not found`, `group_only_rule`, `bad_value`, `bad_note` |
| `rule_val_in133(p_key, p_unit)` | owner, members of that business | the value one business uses |

Group-only keys (cannot be overridden): `org_scope_on`, `twofa*`, `client_error*`, `scan_*`, `backup_*`, `restore_*`, `notify_backup / email / digest / sms*`, `owner_self_approve`, `intake_*`, `meta_intake*`, `inbox_rate*`, `item_images_*`, `bi_export*`, `barcode_*`, `ia_home*`, `offline_cache*`, `pay_gateway*`, `assistant_*` and every rule of module security / assistant / ui / integrations. Books keys (`accounting_on`, `period_closed_until`, `acct_*`, fiscal year) CAN be overridden but the posting engine still runs on one ledger until Stage C2b: the screen should warn.

## Per-business role grants and form rights
`role_matrix_list133(p_unit)` (owner, management of the business) -> `{grants:[{grant, role, allowed, source}], forms:[{role, form, view, enter, approve, source}]}`; `rule_grant_override_set133(p_unit, p_grant, p_role, p_allowed boolean|null, p_note, p_client)` and `role_form_override_set133(p_unit, p_role, p_form, p_view, p_enter, p_approve, p_note, p_client)` (owner; null = reset); `role_scope_set133(p_role, p_unit|null)` and `grant_scope_set133(p_grant, p_unit|null)` (owner) make a role / grant definition visible to one business only. Personal grants (`user_grants`) are not touched by a role override.

## Digest and storage
`daily_digest_biz133(p_biz, p_date)` (owner, the notify bot, management of the business): same JSON as `daily_digest` for one business (+ `business`), without backup status and group-only counts. New uploads: `photo_path133(prefix, place, name)` returns `<PREFIX>/<place>/<name>` (refused for a place outside the caller's businesses); `photo_business133(path)`; `photo_unmapped133()` (owner).

## Error codes the screens must word (bn / en / mix)
`group_only_rule`, `bad_business`, `source_not_found`, `payment_not_found` (existing), `not found` for a row of another business (the same answer as a missing id), `not allowed` on an insert at a place outside the caller's businesses (border trigger).

## Registration lines
None in this slice. When a screen for the above is added: `rec('overrides133', 'settings', [...], { ok: owner })` in `web/ia.js` and its `<script>` tag after `org122.js`; the lead applies them.
