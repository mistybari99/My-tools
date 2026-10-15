# C2 coverage: master data per business (phase132)

Branch `local-c2`. Source list: `docs/audit_c1/RLS_ISOLATION_AUDIT.md` section 4.5 ("Global master data", 50 tables). Code: `supabase/phase132.sql`, tests `supabase/phase132_test.sql`, proof `tests/sql/c2_before_after.sh`.
The same table is available at run time: `select * from master_scope_report132();` (owner / `org_manage`; it also counts the rows and the rows that still have no business).

## 1. Counts

| Decision | Tables of the audit list (50) | Extra children added here | Total |
|---|---|---|---|
| scoped (own `org_unit_id`, read policy, write guard) | 30 | 4 | 34 |
| shared_config (stays one shared table, reason below) | 14 | 0 | 14 |
| loc_scoped_c1 (already filtered by place in phase123) | 4 | 0 | 4 |
| deferred (not done here, reason below) | 2 | 0 | 2 |
| **all** | **50** | 4 | **54** |

## 2. How a scoped table works (switch `org_scope_on`)

* Column `org_unit_id` (the BUSINESS unit, nullable FK to `org_units`) on every scoped table. Existing rows are filled with the sweets business on the first paste (fill-null-only; user triggers are paused for the pure column fill, so no `updated_at`, audit row or immutability guard is touched; a second paste changes nothing). Child tables take the business of their parent row (item, recipe, customer, supplier, asset place); employees and artisans take the business of their place.
* New rows: BEFORE INSERT trigger `a132_scope` gives the row the business of its parent / place, else the caller's WORKING business (`master_context_set132`, any user among their own businesses), else the only business of the caller, else the sweets business. The business of a row never moves (`master_org_fixed`; items keep the phase125 message `item_org_fixed`). To correct a wrong business: deactivate and create again.
* Read (switch ON): restrictive policy `<table>_m132` (true while the switch is OFF). Owner = all; others = rows of the businesses they belong to (`_my_biz123`: scope rows or assigned places); rows shared to them by `master_shares132`; vocabulary rows with no business (the `units` list). Everything else simply does not exist for them.
* Write (switch ON): the same trigger refuses an insert into another business (`not allowed`) and an update of another business's row (`not found`, the answer for a missing id), whatever function does it. Owner and the server (no login) pass. Shared rows are read-only for the receiver.
* Lookups by id inside the existing functions (`select ... from public.customers where id = p_x`): 5 regular-expression passes over every function with that shape (customers, suppliers, items, recipes, artisans; marker `/* m132b:<table> */`; the supplier statements that take a lock `for update` / `for no key update` are skipped because phase109 pins their text, the write trigger guards them); a row of another business answers like a missing id (`customer_not_found`, `item_not_found` ...). True while the switch is OFF and for the server.
* Stock guard: an item of business A cannot be booked at a place of business B (`cross_business_item`, trigger on `stock_ledger`; owner included). Sharing an item never allows this: a share is for READING (price lists, pick lists).
* Sharing: `master_shares132` is the only way across. Owner-created (`master_share_create`), default none, revocable, audited, never deleted. A share is "every row of table T of business X" or one row key (`option_lists` / `list_defs`: a whole list by its `list_code`). Shareable tables: items, suppliers, artisans, item_categories, deed_templates, option_lists, list_defs. NEVER shareable: customers and every child table (cost, price history, recipe lines, points ...).

## 3. Uniqueness per business

| Key | New per-business unique index | Global unique | How the global one goes |
|---|---|---|---|
| `customers.mobile` | `customers_org_mobile_uq132 (org_unit_id, mobile)` | `customers_mobile_key` | `org_masters_relax_unique()` |
| `items.code` | `items_org_code_uq125 (org_unit_id, code)` (phase125) | `items_code_key` | same |
| `items.barcode` | `items_org_barcode_uq132 (org_unit_id, barcode) where barcode is not null` | `items_barcode_uq` | same |

The global constraints are NOT touched by the paste. The safe path (all owner only, all logged in `master_unique_log132`):

1. Turn `org_scope_on` ON first. `select org_masters_preflight();` lists `blockers` (switch not ON, a master row without a business, a lookup function that is not business aware, a missing per-business index) and `warnings` (functions that still resolve an item by the global code or a customer by the global mobile and are not business aware yet; the owner without a working business).
2. `select org_masters_relax_unique(true);` = dry run (drops nothing). With warnings: `org_masters_relax_unique(false, true)` (the second argument says "I have read the warnings").
3. While relaxed, `org_scope_on` cannot be switched OFF (trigger `rules_m132`: `masters_unique_relaxed_restore_first`), because the old lookups assume one row per mobile / code.
4. Reverse: `org_masters_restore_unique(true)` (dry) then `(false)`: allowed only while no duplicate mobile / code / barcode exists across businesses, otherwise it refuses and says how many.
5. Recommended: do NOT relax until a second business really needs the same code or mobile. Until then the cross-business collision raises the plain unique-violation error (nothing is read or written across).

## 4. Functions patched by phase132 (93 in all: 18 by explicit text patch, marker `/* m132 */`, the rest by the id-lookup passes, marker `/* m132b:<table> */`)

`record_sale2` (customer lookup by mobile inside the business of the sale place; new customer gets that business), `find_customer`, `customer_pos_info`, `customer_save` (lookup + optional `org_unit_id` key, refused for another business), `customer_directory`, `customer_balance`, `supplier_pick`, `scan_match_suppliers`, `scan_match_items`, `artisan_list`, `category_list`, `item_dup_check`, `_elp_post_line`, `count_lines_seal`, `_entries_countseal_guard23` (an item code resolves inside the business of the place of the entry), `variants_generate` (clash check follows the unique in force), `_item_master_classify`, `item_master_import_apply` (`on conflict (org_unit_id, code)`). Plus the bulk id-lookup patches above. Phase133 (other agent) must not re-create these without the marker; the owner re-pastes 132 after any older file that re-creates one of them (PASTE_ORDER note N11).

## 5. Table by table

### 5.1 scoped

| Table | Source | Kind | Parent / place | Shareable | Why |
|---|---|---|---|---|---|
| `items` | audit 4.5 | root | - | yes | The item list of a business: its own code / barcode / price. org_unit_id comes from phase125; this phase adds the restrictive read policy, the write guard and the per-business barcode. |
| `customers` | audit 4.5 | root | - | - | Customers are never shared: a mobile number is a customer of ONE business (per-business unique index; global unique relaxed only by org_masters_relax_unique). |
| `suppliers` | audit 4.5 | root | - | yes | Suppliers and their dues belong to one business; the owner may share the supplier list (read only) with another business. |
| `artisans` | audit 4.5 | self_loc | `location_id` | yes | Factory staff register: the business of the artisan place; shareable read only. |
| `employees` | audit 4.5 | self_loc | `primary_location_id` | - | Employees follow the business of their primary place (the pay / leave tables are already place-scoped by phase123 through can_loc). |
| `item_categories` | audit 4.5 | root | - | yes | The category tree of a business (the sweets tree stays with sweets; other businesses build their own or receive a share). |
| `deed_templates` | audit 4.5 | root | - | yes | Employment deed wording is a business document. |
| `item_bulk_batches` | audit 4.5 | root | - | - | Log of bulk item changes (names item codes): belongs to the business that ran it. |
| `option_lists` | audit 4.5 | vocab | - | yes | Dropdown vocabularies (expense heads, wallets, reasons ...) are per business; the units list stays shared (NULL business). A share can hand a whole list (row_key = list_code) to another business. |
| `list_defs` | audit 4.5 | vocab | - | yes | Definition / rule of a vocabulary: follows its list. |
| `shelf_life_rules` | audit 4.5 | child | `items.item_id` | - | Shelf life per item (or per category when no item): the business of the item, else of the creator. |
| `recipes` | audit 4.5 | child | `items.item_id` | - | A recipe belongs to the business of its finished item; never shared (copy by hand). |
| `item_costs` | audit 4.5 | child | `items.item_id` | - | Cost of an item: the business of the item. |
| `item_cost_flags` | audit 4.5 | child | `items.item_id` | - | Cost-free flag of an item. |
| `item_logistics` | audit 4.5 | child | `items.item_id` | - | Weight / volume of an item. |
| `item_price_history` | audit 4.5 | child | `items.item_id` | - | Price history of an item. |
| `item_changes` | audit 4.5 | child | `items.item_id` | - | Item change requests: the business of the item (a request for a NEW item has no item: the business of the requester). |
| `item_master_links` | audit 4.5 | child | `items.item_id` | - | Link of an item to the item dictionary. |
| `item_mapping_review` | audit 4.5 | child | `items.item_id` | - | Dictionary mapping review of an item. |
| `item_map_actions` | audit 4.5 | child | `items.item_id` | - | Dictionary mapping actions (append-only) of an item. |
| `unit_conversions` | audit 4.5 | child | `items.item_id` | - | Unit conversion of an item (the list of units itself is the shared list "units"). |
| `product_packaging` | audit 4.5 | child | `items.product_item_id` | - | Packaging of a finished item: the business of the finished item. |
| `recipe_lines` | audit 4.5 | child | `recipes.recipe_id` | - | Ingredient lines of a recipe. |
| `recipe_steps` | audit 4.5 | child | `recipes.recipe_id` | - | Method steps of a recipe. |
| `recipe_versions` | audit 4.5 | child | `recipes.recipe_id` | - | Version history of a recipe (append-only). |
| `recipe_cost_components` | audit 4.5 | child | `recipes.recipe_id` | - | Extra cost components of a recipe (the list of component types is shared config). |
| `recipe_std116` | extra | child | `recipes.recipe_id` | - | EXTRA (not in the audit list): standard yield / cost per batch of a recipe. |
| `customer_gifts` | audit 4.5 | child | `customers.customer_id` | - | Gifts issued to a customer (the gift RULES are shared config). |
| `customer_points_ledger` | audit 4.5 | child | `customers.customer_id` | - | Loyalty points of a customer (append-only). |
| `customer_tier_history` | audit 4.5 | child | `customers.customer_id` | - | Tier changes of a customer (append-only). |
| `notify_optin` | extra | child | `customers.customer_id` | - | EXTRA: message consent of a customer. |
| `telegram_chat_links` | extra | child | `customers.customer_id` | - | EXTRA: chat <-> customer link (a link with no customer belongs to the business of the linker). |
| `landed_supplier_flags` | extra | child | `suppliers.supplier_id` | - | EXTRA: landed-cost flags of a supplier. |
| `asset_costs` | audit 4.5 | child_loc | `assets.asset_id` | - | Cost of an asset: the business of the asset place. |

### 5.2 shared_config (no change: one shared table)

| Table | Source | Kind | Parent / place | Shareable | Why |
|---|---|---|---|---|---|
| `forms` | audit 4.5 | - | - | - | The catalogue of form codes is the application itself; which form a business uses is the module switch (Stage A 3.5), not a copy of the catalogue. |
| `item_types` | audit 4.5 | - | - | - | Closed list of item kinds that the code branches on (finished good, raw material ...); no business data. |
| `item_class_map` | audit 4.5 | - | - | - | Maps the control class to an item kind: engine configuration. |
| `staff_roles` | audit 4.5 | - | - | - | Catalogue of staff role codes referenced by employee rows; no business data. A per-business override belongs to the roles / grants work (phase133). |
| `leave_types` | audit 4.5 | - | - | - | Catalogue of leave kinds; per-business leave days belong to the per-business rules work (phase133). |
| `benefit_types` | audit 4.5 | - | - | - | Catalogue of benefit kinds; per-business eligibility belongs to the per-business rules work (phase133). |
| `cost_component_types` | audit 4.5 | - | - | - | Closed list of cost component kinds the costing code posts with (builtin); the amounts live in the scoped recipe / location tables. |
| `cost_charge_types` | audit 4.5 | - | - | - | Closed list of landed charge kinds (treatment / expense key); no business data. |
| `cost_source_types` | audit 4.5 | - | - | - | Closed list of cost source kinds; the sources themselves are place-scoped. |
| `notify_templates` | audit 4.5 | - | - | - | Wording of system messages; read only through the notification permission (_i62_ok). A per-business wording is a later feature. |
| `partner_templates` | audit 4.5 | - | - | - | Owner-only select already (policy partner_templates_sel = is_owner): no business user can read it. |
| `item_import_batches` | audit 4.5 | - | - | - | Owner-only select already (policy = is_owner): the import log is a group-owner tool. |
| `customer_tiers` | audit 4.5 | - | - | - | One loyalty ladder for the group: the default-tier logic (customer_tiers_one_default, _customer_new43, _tier_guard43, tier_save, customer_tier_refresh) assumes ONE default tier. A tier row holds no customer data; the customer <-> tier link, points, gifts and history ARE scoped. Per-business ladders = deferred. |
| `gift_rules` | audit 4.5 | - | - | - | Rules hang on the shared ladder (tier_id): same decision as customer_tiers. |

### 5.3 loc_scoped_c1 (already done in phase123)

| Table | Source | Kind | Parent / place | Shareable | Why |
|---|---|---|---|---|---|
| `doc_template_choice` | audit 4.5 | - | - | - | Already filtered by place for the active business in phase123 (policy doc_template_choice_scope123). |
| `invoice_templates` | audit 4.5 | - | - | - | Already filtered by place in phase123 (policy invoice_templates_scope123, read and write). |
| `print_profiles` | audit 4.5 | - | - | - | Already filtered by place in phase123 (policy print_profiles_scope123, read and write). |
| `report_brand_map` | audit 4.5 | - | - | - | Already filtered by place in phase123 (policy report_brand_map_scope123). |

### 5.4 deferred

| Table | Source | Kind | Parent / place | Shareable | Why |
|---|---|---|---|---|---|
| `coa_accounts` | audit 4.5 | - | - | - | DEFERRED to Stage C2b: the posting functions resolve accounts by the GLOBAL code (select id from coa_accounts where code = ...); a chart per business needs the legal-entity column on journal_entries and a rewrite of every posting function. Journal LINES are already place-scoped (phase123). |
| `acct_mappings` | audit 4.5 | - | - | - | DEFERRED to Stage C2b: the key -> account mapping is read by the same posting functions; it moves together with the chart of accounts. |

## 6. What is NOT covered (honest list)

* Chart of accounts and account mapping (see 5.4). Journal lines are place-scoped since phase123; the chart itself is one list that only a user with `_acct_view()` can read.
* One loyalty ladder for the group (`customer_tiers`, `gift_rules`): a tier row has no customer data.
* Primary keys of vocabularies: `option_lists (list_code, value_code)` and `list_defs (list_code)` stay global keys. A business can add its own value with a different `value_code`; the same code as another business's value is refused (the error reveals only that the code is taken). Per-business primary keys are deferred.
* `employees.nid_no` and `employees.device_user_id` stay globally unique (one person = one NID).
* Reader RPCs that are not about masters (the C1 audit Appendix B, about 170) and per-business rules / roles / grants: phase133 (other agent).
* Entry forms keep item codes inside JSON. The resolvers listed in section 4 are business aware; the report functions that join items by code (`_r3q_*`, `_p26_rates`, `rpt131_*` ...) are listed by `org_masters_preflight()` as warnings: they only matter after the unique constraints were relaxed AND the same code exists in two businesses.
* Customer-facing views and the web: nothing in `web/` changed. A second business owner sees empty pick lists until the owner creates their masters or shares existing ones.
* Storage bucket paths and edge-function identities per business (unchanged, see HANDOVER_7 remaining work).
