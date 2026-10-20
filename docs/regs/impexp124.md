# Import-Export (phase124) - registration for the lead

## (a) web/ia.js - add this line (group `settings`; visible to the owner or anyone holding impexp_view / impexp_manage)
```js
  rec('impexp', 'settings', ['আমদানি-রপ্তানি', 'Import-Export', 'Import-Export'], { icon: 'doc', ok: (c) => c.own || c.GF.impexp_view === true || c.GF.impexp_manage === true, kw: ['import', 'export', 'shipment', 'currency', 'exchange rate', 'fx', 'landed cost', 'customs', 'আমদানি', 'রপ্তানি', 'শিপমেন্ট', 'মুদ্রা', 'ডলার', 'রেট'] }),
```
(`c.GF` is filled from grant_defs, so the two new grants must be in the grant list the page loads; the page and every server function check scope again. No OWNER_ONLY entry: non-owners with the grant may open it.)

## (b) web/index.html - script tag, after org122.js / cashmoves.js (needs only web/app.js globals: BOS_APP, BOS.L / lab)
```html
<script src="impexp124.js"></script>
```
Optional: add `#ie_body` to the 44px tap-size list in web/theme.css (the page already sets min-height 44px inline on its buttons).

## (c) SQL / grants / rules added by supabase/phase124.sql (after phase122; canonical order ...122, 123, 124; idempotent)
* Grants (grant_defs, module `impexp`): `impexp_view` (read the business), `impexp_manage` (write shipments, currencies, rates; also reads). Give them per LOCATION of the import-export business (user_grants.location_id null = every location the user is assigned to).
* Rule `impexp_on` (switch, default OFF, shown in #/switchboard). OFF = shipment_save, shipment_set_status, currency_save, fx_rate_set refuse with `impexp_off`; reading still works.
* `business_templates` row `import_export`: status `needs_setup`; `modules` jsonb lists every part as built / not_built (letter of credit, customs automation, GL posting, stock link, bank payments = not_built).
* Tables `ie_currencies`, `ie_fx_rates` (append-only), `ie_shipments`, `ie_shipment_events` (append-only): every row carries `org_unit_id` = the import_export business; RLS on and NO browser access to the tables at all; only the functions.
* Functions for the browser (all take the business id `p_org`): `ie_businesses124`, `ie_currencies_list`, `ie_fx_rates_list`, `currency_save`, `fx_rate_set`, `shipment_save`, `shipment_set_status`, `shipments_list`, `shipment_events_list`, `shipment_cost_summary`, `shipments_by_currency`.
* How the owner starts: #/organization -> add a legal entity (set its base currency) -> add a business with template `import_export` -> map a location to it (locations.org_unit_id) -> assign people to that location + grants -> turn `impexp_on` ON -> #/impexp -> add currencies and rates -> add shipments.
* Pending (stated, not built): posting to the GL, letters of credit, customs automation, stock link, bank / payment tracking.
