-- ============================================================
-- Phase 132 (marker mstr132) - GROUP ERP, STAGE C2: strict separation of MASTER DATA between businesses, behind the switch org_scope_on (DEFAULT OFF).
-- Plan: docs/GROUP_ERP_STAGE_A.md sections 3.4, 10, 11; audit docs/audit_c1/RLS_ISOLATION_AUDIT.md section 4.5 (the 50 global master tables); coverage table docs/audit_c1/C2_COVERAGE.md.
-- Canonical order: after phase131 (docs/PASTE_ORDER.md). Paste twice = no change, no error. Needs phases 122, 123, 125.
-- With org_scope_on OFF (the default) every behaviour is the one of phase131: the new columns are filled and ignored, the policies / guards below are true / silent while the switch is OFF,
-- and every patched function keeps its old text in the OFF branch (tests/sql/c2_before_after.sh proves it on seeded data).
--
--   WHAT IT DOES (see C2_COVERAGE.md for the decision per table)
--     master_scope132         the registry: one row per master table = decision (scoped | shared_config | loc_scoped_c1 | deferred), kind, parent link, why.
--     org_unit_id (BUSINESS)  added (nullable, FK org_units) to every SCOPED table; existing rows back-filled to the sweets business (fill-null-only, user triggers paused for the
--                             pure column fill, never overwritten on a second paste); child tables take the business of their parent row (item -> costs / prices / links, recipe -> lines,
--                             customer -> points / gifts / history, asset -> cost); employees / artisans take the business of their place.
--     new rows              a BEFORE INSERT trigger gives every new master row the business of the caller (the working business set with master_context_set132, else the only business
--                             of the caller, else the sweets business) or of its parent / place. The business never moves later (master_org_fixed).
--     reads (switch ON)     restrictive RLS select policy <table>_m132: owner = all; others = the businesses they belong to (_my_biz123), rows shared to them by master_shares132,
--                             vocabulary rows without a business (NULL = shared, e.g. the units list). Other businesses' rows simply do not exist for them.
--     writes (switch ON)    the same trigger refuses a write into / of another business ('not allowed' for an insert, 'not found' for an update = the answer for a missing id), whatever
--                             function does it. Owner and the server (no login) pass.
--     master_shares132      the ONLY way masters cross a business border: owner-created, default none, read-only for the receiver (never used for transactions), revocable, audited.
--     uniqueness            customers.mobile : new unique index (org_unit_id, mobile); items.code : (org_unit_id, code) from phase125; items.barcode : (org_unit_id, barcode).
--                             The GLOBAL unique constraints stay until the owner runs org_masters_relax_unique() (owner only, only while org_scope_on is ON, after
--                             org_masters_preflight() has no blocker, dry-run first, logged, reversible with org_masters_restore_unique()). While relaxed, org_scope_on cannot be switched OFF.
--     patched functions     (text patch of the current body, marker "m132", idempotent): the customer lookups by mobile (find_customer, customer_pos_info, customer_save, record_sale2),
--                             the item-code resolvers (_elp_post_line, count_lines_seal, _entries_countseal_guard23, variants_generate, _item_master_classify, item_master_import_apply)
--                             and the master pick lists (customer_directory, supplier_pick, scan_match_suppliers, scan_match_items, artisan_list, category_list, item_dup_check).
--     stock guard           an item of business A cannot be moved at a location of business B (trigger on stock_ledger, switch ON).
--   NEW FUNCTIONS (owner unless noted): master_share_create / master_share_revoke / master_share_list (owner, org_manage reads), master_context_set132 / master_context_get132 (any user, own businesses),
--     org_masters_preflight, org_masters_relax_unique, org_masters_restore_unique, master_scope_report132 (owner, org_manage).
--   NOT HERE (deferred, see C2_COVERAGE.md): coa_accounts / acct_mappings (posting functions resolve accounts by the global code: per-business chart = Stage C2b with legal-entity books),
--     per-business customer tiers / default tier, per-business rules / roles / grants and the other reader RPCs of the C1 audit Appendix B (phase133, other agent).
-- Rollback: leave the switch OFF. To remove: drop the policies *_m132 and triggers a132_scope / stock_ledger_xbiz132 / rules_m132, re-paste the older phase files of the patched functions
--   (phase 87 record_sale2 ..., see PASTE_ORDER), drop the new tables / functions. The org_unit_id columns can stay (nothing reads them).
-- ============================================================
begin;

do $g$
declare miss text := '';
begin
  if to_regclass('public.org_units') is null or to_regclass('public.user_org_scopes') is null or to_regclass('public.items') is null or to_regclass('public.customers') is null
     or to_regclass('public.suppliers') is null or to_regclass('public.stock_ledger') is null or to_regclass('public.rules') is null then miss := miss || ' tables'; end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'items' and column_name = 'org_unit_id') then miss := miss || ' items.org_unit_id(phase125)'; end if;
  if to_regprocedure('public._my_biz123()') is null or to_regprocedure('public._org_on123()') is null or to_regprocedure('public._business_of_loc123(integer)') is null
     or to_regprocedure('public._biz_default125()') is null or to_regprocedure('public.log_change()') is null or to_regprocedure('public.no_hard_delete()') is null
     or to_regprocedure('public._client_lock(uuid)') is null or to_regprocedure('public.is_owner()') is null then miss := miss || ' functions(phase123/125)'; end if;
  if miss <> '' then raise exception 'phase132 needs the base schema and phases up to 131 pasted first (docs/PASTE_ORDER.md); missing:%', miss; end if;
end $g$;

-- ---------- 1. the registry (one row per master table of the audit, plus a few obvious children) ----------
create table if not exists public.master_scope132 (
  table_name text primary key,
  decision text not null check (decision in ('scoped', 'shared_config', 'loc_scoped_c1', 'deferred')),
  kind text check (kind in ('root', 'vocab', 'self_loc', 'child', 'child_loc')),
  parent_table text, parent_col text, parent_pk text, parent_pk_type text, parent_loc_col text,   -- child: parent_col (fk here) -> parent_table.parent_pk ; child_loc: ... then parent_loc_col -> location -> business
  loc_col text,                                  -- self_loc: the place column of the row itself
  shared_col text, shared_vals text[],           -- vocab: rows whose shared_col is in shared_vals keep org_unit_id NULL = shared by everybody
  key_expr text not null default 'id::text',     -- the row key used by master_shares132
  shareable boolean not null default false,
  audit_set boolean not null default true,       -- true = the table is one of the 50 of the audit (section 4.5); false = an extra child added here
  why text not null,
  sort int not null default 100
);
alter table public.master_scope132 enable row level security;
drop policy if exists master_scope132_read on public.master_scope132;
create policy master_scope132_read on public.master_scope132 for select to authenticated using (public.is_owner() or public.has_grant('org_manage'));
revoke all on public.master_scope132 from public, anon, authenticated;
grant select on public.master_scope132 to authenticated;

insert into public.master_scope132 (table_name, decision, kind, parent_table, parent_col, parent_pk, parent_pk_type, parent_loc_col, loc_col, shared_col, shared_vals, key_expr, shareable, audit_set, why, sort) values
 -- ROOT masters: own business
 ('items',                 'scoped', 'root',  null, null, null, null, null, null, null, null, 'id::text', true,  true,  'The item list of a business: its own code / barcode / price. org_unit_id comes from phase125; this phase adds the restrictive read policy, the write guard and the per-business barcode.', 10),
 ('customers',             'scoped', 'root',  null, null, null, null, null, null, null, null, 'id::text', false, true,  'Customers are never shared: a mobile number is a customer of ONE business (per-business unique index; global unique relaxed only by org_masters_relax_unique).', 11),
 ('suppliers',             'scoped', 'root',  null, null, null, null, null, null, null, null, 'id::text', true,  true,  'Suppliers and their dues belong to one business; the owner may share the supplier list (read only) with another business.', 12),
 ('artisans',              'scoped', 'self_loc', null, null, null, null, null, 'location_id', null, null, 'id::text', true, true, 'Factory staff register: the business of the artisan place; shareable read only.', 13),
 ('employees',             'scoped', 'self_loc', null, null, null, null, null, 'primary_location_id', null, null, 'id::text', false, true, 'Employees follow the business of their primary place (the pay / leave tables are already place-scoped by phase123 through can_loc).', 14),
 ('item_categories',       'scoped', 'root',  null, null, null, null, null, null, null, null, 'id::text', true,  true,  'The category tree of a business (the sweets tree stays with sweets; other businesses build their own or receive a share).', 15),
 ('deed_templates',        'scoped', 'root',  null, null, null, null, null, null, null, null, 'id::text', true,  true,  'Employment deed wording is a business document.', 16),
 ('item_bulk_batches',     'scoped', 'root',  null, null, null, null, null, null, null, null, 'id::text', false, true,  'Log of bulk item changes (names item codes): belongs to the business that ran it.', 17),
 ('option_lists',          'scoped', 'vocab', null, null, null, null, null, null, 'list_code', array['units'], $k$list_code || '/' || value_code$k$, true, true, 'Dropdown vocabularies (expense heads, wallets, reasons ...) are per business; the units list stays shared (NULL business). A share can hand a whole list (row_key = list_code) to another business.', 18),
 ('list_defs',             'scoped', 'vocab', null, null, null, null, null, null, 'list_code', array['units'], 'list_code', true, true, 'Definition / rule of a vocabulary: follows its list.', 19),
 ('shelf_life_rules',      'scoped', 'child', 'items', 'item_id', 'id', 'uuid', null, null, null, null, 'id::text', false, true, 'Shelf life per item (or per category when no item): the business of the item, else of the creator.', 20),
 ('recipes',               'scoped', 'child', 'items', 'item_id', 'id', 'uuid', null, null, null, null, 'id::text', false, true, 'A recipe belongs to the business of its finished item; never shared (copy by hand).', 21),
 -- CHILDREN of items
 ('item_costs',            'scoped', 'child', 'items', 'item_id', 'id', 'uuid', null, null, null, null, 'item_id::text', false, true, 'Cost of an item: the business of the item.', 30),
 ('item_cost_flags',       'scoped', 'child', 'items', 'item_id', 'id', 'uuid', null, null, null, null, 'item_id::text', false, true, 'Cost-free flag of an item.', 31),
 ('item_logistics',        'scoped', 'child', 'items', 'item_id', 'id', 'uuid', null, null, null, null, 'item_id::text', false, true, 'Weight / volume of an item.', 32),
 ('item_price_history',    'scoped', 'child', 'items', 'item_id', 'id', 'uuid', null, null, null, null, 'id::text', false, true, 'Price history of an item.', 33),
 ('item_changes',          'scoped', 'child', 'items', 'item_id', 'id', 'uuid', null, null, null, null, 'id::text', false, true, 'Item change requests: the business of the item (a request for a NEW item has no item: the business of the requester).', 34),
 ('item_master_links',     'scoped', 'child', 'items', 'item_id', 'id', 'uuid', null, null, null, null, 'id::text', false, true, 'Link of an item to the item dictionary.', 35),
 ('item_mapping_review',   'scoped', 'child', 'items', 'item_id', 'id', 'uuid', null, null, null, null, 'id::text', false, true, 'Dictionary mapping review of an item.', 36),
 ('item_map_actions',      'scoped', 'child', 'items', 'item_id', 'id', 'uuid', null, null, null, null, 'id::text', false, true, 'Dictionary mapping actions (append-only) of an item.', 37),
 ('unit_conversions',      'scoped', 'child', 'items', 'item_id', 'id', 'uuid', null, null, null, null, 'id::text', false, true, 'Unit conversion of an item (the list of units itself is the shared list "units").', 38),
 ('product_packaging',     'scoped', 'child', 'items', 'product_item_id', 'id', 'uuid', null, null, null, null, 'id::text', false, true, 'Packaging of a finished item: the business of the finished item.', 39),
 -- CHILDREN of recipes
 ('recipe_lines',          'scoped', 'child', 'recipes', 'recipe_id', 'id', 'uuid', null, null, null, null, 'id::text', false, true, 'Ingredient lines of a recipe.', 40),
 ('recipe_steps',          'scoped', 'child', 'recipes', 'recipe_id', 'id', 'uuid', null, null, null, null, 'id::text', false, true, 'Method steps of a recipe.', 41),
 ('recipe_versions',       'scoped', 'child', 'recipes', 'recipe_id', 'id', 'uuid', null, null, null, null, 'id::text', false, true, 'Version history of a recipe (append-only).', 42),
 ('recipe_cost_components','scoped', 'child', 'recipes', 'recipe_id', 'id', 'uuid', null, null, null, null, 'id::text', false, true, 'Extra cost components of a recipe (the list of component types is shared config).', 43),
 ('recipe_std116',         'scoped', 'child', 'recipes', 'recipe_id', 'id', 'uuid', null, null, null, null, 'id::text', false, false, 'EXTRA (not in the audit list): standard yield / cost per batch of a recipe.', 44),
 -- CHILDREN of customers
 ('customer_gifts',        'scoped', 'child', 'customers', 'customer_id', 'id', 'uuid', null, null, null, null, 'id::text', false, true, 'Gifts issued to a customer (the gift RULES are shared config).', 50),
 ('customer_points_ledger','scoped', 'child', 'customers', 'customer_id', 'id', 'uuid', null, null, null, null, 'id::text', false, true, 'Loyalty points of a customer (append-only).', 51),
 ('customer_tier_history', 'scoped', 'child', 'customers', 'customer_id', 'id', 'uuid', null, null, null, null, 'id::text', false, true, 'Tier changes of a customer (append-only).', 52),
 ('notify_optin',          'scoped', 'child', 'customers', 'customer_id', 'id', 'uuid', null, null, null, null, 'id::text', false, false, 'EXTRA: message consent of a customer.', 53),
 ('telegram_chat_links',   'scoped', 'child', 'customers', 'customer_id', 'id', 'uuid', null, null, null, null, 'id::text', false, false, 'EXTRA: chat <-> customer link (a link with no customer belongs to the business of the linker).', 54),
 -- CHILDREN of suppliers / assets
 ('landed_supplier_flags', 'scoped', 'child', 'suppliers', 'supplier_id', 'id', 'uuid', null, null, null, null, 'supplier_id::text', false, false, 'EXTRA: landed-cost flags of a supplier.', 60),
 ('asset_costs',           'scoped', 'child_loc', 'assets', 'asset_id', 'id', 'uuid', 'location_id', null, null, null, 'asset_id::text', false, true, 'Cost of an asset: the business of the asset place.', 61)
on conflict (table_name) do update set decision = excluded.decision, kind = excluded.kind, parent_table = excluded.parent_table, parent_col = excluded.parent_col, parent_pk = excluded.parent_pk,
  parent_pk_type = excluded.parent_pk_type, parent_loc_col = excluded.parent_loc_col, loc_col = excluded.loc_col, shared_col = excluded.shared_col, shared_vals = excluded.shared_vals,
  key_expr = excluded.key_expr, shareable = excluded.shareable, audit_set = excluded.audit_set, why = excluded.why, sort = excluded.sort;

insert into public.master_scope132 (table_name, decision, why, sort) values
 ('forms',                  'shared_config', 'The catalogue of form codes is the application itself; which form a business uses is the module switch (Stage A 3.5), not a copy of the catalogue.', 200),
 ('item_types',             'shared_config', 'Closed list of item kinds that the code branches on (finished good, raw material ...); no business data.', 201),
 ('item_class_map',         'shared_config', 'Maps the control class to an item kind: engine configuration.', 202),
 ('staff_roles',            'shared_config', 'Catalogue of staff role codes referenced by employee rows; no business data. A per-business override belongs to the roles / grants work (phase133).', 203),
 ('leave_types',            'shared_config', 'Catalogue of leave kinds; per-business leave days belong to the per-business rules work (phase133).', 204),
 ('benefit_types',          'shared_config', 'Catalogue of benefit kinds; per-business eligibility belongs to the per-business rules work (phase133).', 205),
 ('cost_component_types',   'shared_config', 'Closed list of cost component kinds the costing code posts with (builtin); the amounts live in the scoped recipe / location tables.', 206),
 ('cost_charge_types',      'shared_config', 'Closed list of landed charge kinds (treatment / expense key); no business data.', 207),
 ('cost_source_types',      'shared_config', 'Closed list of cost source kinds; the sources themselves are place-scoped.', 208),
 ('notify_templates',       'shared_config', 'Wording of system messages; read only through the notification permission (_i62_ok). A per-business wording is a later feature.', 209),
 ('partner_templates',      'shared_config', 'Owner-only select already (policy partner_templates_sel = is_owner): no business user can read it.', 210),
 ('item_import_batches',    'shared_config', 'Owner-only select already (policy = is_owner): the import log is a group-owner tool.', 211),
 ('customer_tiers',         'shared_config', 'One loyalty ladder for the group: the default-tier logic (customer_tiers_one_default, _customer_new43, _tier_guard43, tier_save, customer_tier_refresh) assumes ONE default tier. A tier row holds no customer data; the customer <-> tier link, points, gifts and history ARE scoped. Per-business ladders = deferred.', 212),
 ('gift_rules',             'shared_config', 'Rules hang on the shared ladder (tier_id): same decision as customer_tiers.', 213),
 ('doc_template_choice',    'loc_scoped_c1', 'Already filtered by place for the active business in phase123 (policy doc_template_choice_scope123).', 220),
 ('invoice_templates',      'loc_scoped_c1', 'Already filtered by place in phase123 (policy invoice_templates_scope123, read and write).', 221),
 ('print_profiles',         'loc_scoped_c1', 'Already filtered by place in phase123 (policy print_profiles_scope123, read and write).', 222),
 ('report_brand_map',       'loc_scoped_c1', 'Already filtered by place in phase123 (policy report_brand_map_scope123).', 223),
 ('coa_accounts',           'deferred', 'DEFERRED to Stage C2b: the posting functions resolve accounts by the GLOBAL code (select id from coa_accounts where code = ...); a chart per business needs the legal-entity column on journal_entries and a rewrite of every posting function. Journal LINES are already place-scoped (phase123).', 230),
 ('acct_mappings',          'deferred', 'DEFERRED to Stage C2b: the key -> account mapping is read by the same posting functions; it moves together with the chart of accounts.', 231)
on conflict (table_name) do update set decision = excluded.decision, why = excluded.why, sort = excluded.sort;

-- ---------- 2. who works for which business ----------
create table if not exists public.master_ctx132 (
  user_id uuid primary key references public.profiles(id),
  org_unit_id bigint not null references public.org_units(id),
  set_at timestamptz not null default now()
);
alter table public.master_ctx132 enable row level security;
drop policy if exists master_ctx132_read on public.master_ctx132;
create policy master_ctx132_read on public.master_ctx132 for select to authenticated using (user_id = auth.uid() or public.is_owner());
revoke all on public.master_ctx132 from public, anon, authenticated;
grant select on public.master_ctx132 to authenticated;

create table if not exists public.master_shares132 (
  id bigserial primary key,
  table_name text not null references public.master_scope132(table_name),
  row_key text check (row_key is null or length(row_key) <= 200),     -- NULL = every row of the table of from_org; else one row key (option_lists / list_defs: a whole list by its list_code)
  from_org bigint not null references public.org_units(id),
  to_org bigint not null references public.org_units(id),
  status text not null default 'active' check (status in ('active', 'revoked')),
  note text check (note is null or length(note) <= 300),
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(),
  revoked_by uuid, revoked_at timestamptz, revoked_reason text check (revoked_reason is null or length(revoked_reason) <= 300),
  check (from_org <> to_org)
);
create unique index if not exists master_shares132_active on public.master_shares132 (table_name, coalesce(row_key, ''), from_org, to_org) where status = 'active';
create index if not exists master_shares132_to on public.master_shares132 (to_org, table_name) where status = 'active';
drop trigger if exists master_shares132_nodel on public.master_shares132;
create trigger master_shares132_nodel before delete on public.master_shares132 for each row execute function public.no_hard_delete();
drop trigger if exists audit_master_shares132 on public.master_shares132;
create trigger audit_master_shares132 after insert or update on public.master_shares132 for each row execute function public.log_change('id');
alter table public.master_shares132 enable row level security;
drop policy if exists master_shares132_read on public.master_shares132;
create policy master_shares132_read on public.master_shares132 for select to authenticated using (public.is_owner() or public.has_grant('org_manage'));
revoke all on public.master_shares132 from public, anon, authenticated;
grant select on public.master_shares132 to authenticated;
revoke all on sequence public.master_shares132_id_seq from public, anon, authenticated;

-- the unique-constraint relax log (reversible); the latest row per object tells the state
create table if not exists public.master_unique_log132 (
  id bigserial primary key,
  action text not null check (action in ('relax', 'restore')),
  object_name text not null,
  definition text not null,
  at timestamptz not null default now(),
  by_user uuid
);
drop trigger if exists master_unique_log132_nodel on public.master_unique_log132;
create trigger master_unique_log132_nodel before delete on public.master_unique_log132 for each row execute function public.no_hard_delete();
drop trigger if exists audit_master_unique_log132 on public.master_unique_log132;
create trigger audit_master_unique_log132 after insert or update on public.master_unique_log132 for each row execute function public.log_change('id');
alter table public.master_unique_log132 enable row level security;
drop policy if exists master_unique_log132_read on public.master_unique_log132;
create policy master_unique_log132_read on public.master_unique_log132 for select to authenticated using (public.is_owner());
revoke all on public.master_unique_log132 from public, anon, authenticated;
grant select on public.master_unique_log132 to authenticated;
revoke all on sequence public.master_unique_log132_id_seq from public, anon, authenticated;

-- ---------- 3. helpers (internal ones closed to the browser; the ones used inside policies are granted) ----------
-- the business a new master row belongs to when the row itself does not say: the working business the user picked, else the only business of the user, else nothing
create or replace function public._m132_caller_biz() returns bigint
language sql stable security definer set search_path = public as $$
  select case when auth.uid() is null then null else coalesce(
    (select c.org_unit_id from public.master_ctx132 c where c.user_id = auth.uid() and c.org_unit_id in (select public._my_biz123())),
    (select case when count(*) = 1 then min(q.b) end from (select distinct b from public._my_biz123() b) q)) end;
$$;

-- the caller's businesses, callable from a policy (the underlying _my_biz123 is closed to the browser)
create or replace function public._m132_mybiz() returns setof bigint
language sql stable security definer set search_path = public as $$
  select public._my_biz123();
$$;

-- the business of a place (null when the place is unmapped)
create or replace function public._m132_biz_of_loc(p_loc int) returns bigint
language sql stable security definer set search_path = public as $$
  select public._business_of_loc123(p_loc);
$$;

-- is a master row (customer / item) of the business of this place? true while the switch is OFF, and for an unmapped place
create or replace function public._m132_at(p_org bigint, p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select not public._org_on123() or public._business_of_loc123(p_loc) is null or p_org is not distinct from public._business_of_loc123(p_loc);
$$;

-- may the caller use a master row of this business (lookups inside functions)? true while the switch is OFF and for the server (no login); ON: the owner and the members of the business
create or replace function public._m132_own(p_org bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select not public._org_on123() or auth.uid() is null or (public.is_active() and (public.is_owner() or p_org in (select public._my_biz123())));
$$;

-- is a row shared to the caller's business by an active master_shares132 row?
create or replace function public._m132_shared(p_tbl text, p_org bigint, p_key text) returns boolean
language sql stable security definer set search_path = public as $$
  select public._org_on123() and p_org is not null and exists (
    select 1 from public.master_shares132 s
     where s.status = 'active' and s.table_name = p_tbl and s.from_org = p_org and s.to_org in (select public._my_biz123())
       and (s.row_key is null or p_key = s.row_key or starts_with(p_key, s.row_key || '/')));
$$;

-- row visibility as a function (for lookups inside patched functions): switch OFF = true; ON = owner, own business, NULL business when p_null_ok, or shared
create or replace function public._m132_vis(p_tbl text, p_org bigint, p_key text, p_null_ok boolean default false) returns boolean
language sql stable security definer set search_path = public as $$
  select not public._org_on123() or auth.uid() is null or (public.is_active() and (public.is_owner() or (p_org is null and p_null_ok)
     or p_org in (select public._my_biz123()) or public._m132_shared(p_tbl, p_org, p_key)));
$$;

-- is the global unique on customers.mobile / items.code currently relaxed? (latest log row of customers_mobile_key decides)
create or replace function public._m132_relaxed() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select l.action = 'relax' from public.master_unique_log132 l where l.object_name = 'customers_mobile_key' order by l.id desc limit 1), false);
$$;

-- ---------- 4. the fill + guard trigger (one function for every scoped table; the arguments come from the registry) ----------
create or replace function public._m132_scope() returns trigger
language plpgsql security definer set search_path = public as $$
declare kind_ text := tg_argv[0]; ptab text := nullif(tg_argv[1], ''); pcol text := nullif(tg_argv[2], ''); ppk text := coalesce(nullif(tg_argv[3], ''), 'id');
  ptype text := coalesce(nullif(tg_argv[4], ''), 'uuid'); ploc text := nullif(tg_argv[5], ''); lcol text := nullif(tg_argv[6], ''); scol text := nullif(tg_argv[7], '');
  svals text[] := string_to_array(coalesce(tg_argv[8], ''), ','); j jsonb; o bigint; v text;
begin
  -- the business of a row never moves (the owner's correction path is: deactivate and create again in the right business)
  if tg_op = 'UPDATE' and old.org_unit_id is not null and new.org_unit_id is distinct from old.org_unit_id then
    raise exception '%', case when tg_table_name = 'items' then 'item_org_fixed' else 'master_org_fixed' end;      -- items keep the message of phase125
  end if;
  if tg_op = 'INSERT' and new.org_unit_id is null then
    j := to_jsonb(new);
    if scol is not null and (j ->> scol) = any(svals) then return new; end if;     -- a shared vocabulary row (the units list) keeps NULL = shared
    v := case when pcol is not null then j ->> pcol end;
    if kind_ = 'child' and ptab is not null and v is not null then
      execute format('select p.org_unit_id from public.%I p where p.%I = ($1)::%s', ptab, ppk, ptype) into o using v;
    elsif kind_ = 'child_loc' and ptab is not null and v is not null then
      execute format('select public._business_of_loc123(p.%I) from public.%I p where p.%I = ($1)::%s', ploc, ptab, ppk, ptype) into o using v;
    elsif kind_ = 'self_loc' and lcol is not null and (j ->> lcol) is not null then
      o := public._business_of_loc123((j ->> lcol)::int);
    end if;
    new.org_unit_id := coalesce(o, public._m132_caller_biz(), public._biz_default125());
  end if;
  -- the guard (switch ON, a logged-in user who is not the owner; the server / cron has no login and passes)
  if public._org_on123() and auth.uid() is not null and not public.is_owner() then
    if tg_op = 'INSERT' then
      if new.org_unit_id is null or not (new.org_unit_id in (select public._my_biz123())) then raise exception 'not allowed'; end if;
    else
      if old.org_unit_id is null or not (old.org_unit_id in (select public._my_biz123())) then raise exception 'not found'; end if;
    end if;
  end if;
  return new;
end $$;

-- a stock movement of an item of another business is refused (switch ON)
create or replace function public._m132_xbiz() returns trigger
language plpgsql security definer set search_path = public as $$
declare bl bigint; bi bigint;
begin
  if public._org_on123() and auth.uid() is not null then
    bl := public._business_of_loc123(new.location_id);
    select i.org_unit_id into bi from public.items i where i.id = new.item_id;
    if bl is not null and bi is not null and bl <> bi then raise exception 'cross_business_item'; end if;
  end if;
  return new;
end $$;
drop trigger if exists stock_ledger_xbiz132 on public.stock_ledger;
create trigger stock_ledger_xbiz132 before insert on public.stock_ledger for each row execute function public._m132_xbiz();

-- ---------- 5. apply the registry: column, index, trigger, back-fill, policy ----------
do $ap$
declare r record; dflt bigint := public._biz_default125(); has_null boolean; pol text; sh text; shared_cond text; q text;
begin
  for r in select * from public.master_scope132 where decision = 'scoped' order by sort, table_name loop
    if to_regclass('public.' || r.table_name) is null then raise notice 'phase132: table % does not exist here, skipped', r.table_name; continue; end if;
    if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = r.table_name and column_name = 'org_unit_id') then
      execute format('alter table public.%I add column org_unit_id bigint references public.org_units(id)', r.table_name);
    end if;
    execute format('create index if not exists %I on public.%I (org_unit_id)', r.table_name || '_org132', r.table_name);
    -- back-fill (fill-null-only; the user triggers are paused so that a pure column fill touches no updated_at, audit row or immutability guard)
    execute format('select exists (select 1 from public.%I where org_unit_id is null)', r.table_name) into has_null;
    if has_null and dflt is not null then
      shared_cond := case when r.shared_col is not null then format(' and coalesce(%I::text, '''') <> all (%L::text[])', r.shared_col, r.shared_vals) else '' end;
      execute format('alter table public.%I disable trigger user', r.table_name);
      if r.kind = 'child' then
        execute format('update public.%I t set org_unit_id = p.org_unit_id from public.%I p where t.%I = p.%I and t.org_unit_id is null and p.org_unit_id is not null', r.table_name, r.parent_table, r.parent_col, r.parent_pk);
      elsif r.kind = 'child_loc' then
        execute format('update public.%I t set org_unit_id = coalesce(public._business_of_loc123(p.%I), %s) from public.%I p where t.%I = p.%I and t.org_unit_id is null', r.table_name, r.parent_loc_col, dflt, r.parent_table, r.parent_col, r.parent_pk);
      elsif r.kind = 'self_loc' then
        execute format('update public.%I set org_unit_id = coalesce(public._business_of_loc123(%I), %s) where org_unit_id is null', r.table_name, r.loc_col, dflt);
      end if;
      execute format('update public.%I set org_unit_id = %s where org_unit_id is null%s', r.table_name, dflt, shared_cond);
      execute format('alter table public.%I enable trigger user', r.table_name);
    end if;
    -- the fill + guard trigger
    execute format('drop trigger if exists a132_scope on public.%I', r.table_name);
    execute format('drop trigger if exists m132_scope on public.%I', r.table_name);
    execute format('create trigger a132_scope before insert or update on public.%I for each row execute function public._m132_scope(%L, %L, %L, %L, %L, %L, %L, %L, %L)',
      r.table_name, r.kind, coalesce(r.parent_table, ''), coalesce(r.parent_col, ''), coalesce(r.parent_pk, ''), coalesce(r.parent_pk_type, ''), coalesce(r.parent_loc_col, ''),
      coalesce(r.loc_col, ''), coalesce(r.shared_col, ''), coalesce(array_to_string(r.shared_vals, ','), ''));
    -- the restrictive read policy (true while the switch is OFF)
    sh := case when r.shareable then format(' or public._m132_shared(%L, org_unit_id, %s)', r.table_name, r.key_expr) else '' end;
    pol := '(select not public._org_on123()) or (select public.is_owner()) or org_unit_id in (select public._m132_mybiz())' || sh || case when r.kind = 'vocab' then ' or org_unit_id is null' else '' end;
    execute format('alter table public.%I enable row level security', r.table_name);
    execute format('drop policy if exists %I on public.%I', r.table_name || '_m132', r.table_name);
    execute format('create policy %I on public.%I as restrictive for select to authenticated using (%s)', r.table_name || '_m132', r.table_name, pol);
  end loop;
end $ap$;

-- per-business uniqueness (the global unique constraints are NOT touched here; see org_masters_relax_unique)
create unique index if not exists customers_org_mobile_uq132 on public.customers (org_unit_id, mobile);
create unique index if not exists items_org_barcode_uq132 on public.items (org_unit_id, barcode) where barcode is not null;
create unique index if not exists items_org_code_uq125 on public.items (org_unit_id, code);     -- phase125 made it; kept here so that this phase stands on its own

-- ---------- 6. text patches of existing functions (marker "m132"; idempotent; the OFF branch is the old text) ----------
create or replace function public._m132_patch(p_sig text, p_marker text, p_pairs text[]) returns text
language plpgsql security definer set search_path = public as $$
declare o oid := to_regprocedure(p_sig); d text; i int := 1;
begin
  if o is null then raise exception 'phase132 patch: function % not found', p_sig; end if;
  d := pg_get_functiondef(o);
  if position(p_marker in d) > 0 then return 'already'; end if;
  while i < array_length(p_pairs, 1) loop
    if position(p_pairs[i] in d) = 0 then raise exception 'phase132 patch: text "%" not found in %', left(p_pairs[i], 70), p_sig; end if;
    d := replace(d, p_pairs[i], p_pairs[i + 1]);
    i := i + 2;
  end loop;
  execute d;
  return 'patched';
end $$;

select public._m132_patch('public.record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamp with time zone,text,numeric)', '/* m132 */', array[
  'where cu.mobile = public.norm_mobile(p_customer_mobile) and cu.active and t.active and t.discount_percent > 0;',
  'where cu.mobile = public.norm_mobile(p_customer_mobile) and cu.active and t.active and t.discount_percent > 0 and public._m132_at(cu.org_unit_id, p_loc) /* m132 */;',
  'select * into cust from public.customers where mobile = mob for update;',
  'select * into cust from public.customers where mobile = mob and public._m132_at(org_unit_id, p_loc) /* m132 */ order by (org_unit_id is not distinct from public._m132_biz_of_loc(p_loc)) desc, org_unit_id limit 1 for update;',
  'insert into public.customers (mobile, name, type, created_by) values (mob, left(btrim(p_customer_name), 80), stype, auth.uid()) returning * into cust;',
  'insert into public.customers (mobile, name, type, created_by, org_unit_id) values (mob, left(btrim(p_customer_name), 80), stype, auth.uid(), public._m132_biz_of_loc(p_loc) /* m132 */) returning * into cust;']);

select public._m132_patch('public.find_customer(text)', '/* m132 */', array[
  'select * into c from public.customers where mobile = m;',
  'select * into c from public.customers where mobile = m and public._m132_own(org_unit_id) /* m132 */ order by (org_unit_id is not distinct from public._m132_caller_biz()) desc, org_unit_id limit 1;']);

select public._m132_patch('public.customer_pos_info(text)', '/* m132 */', array[
  'select * into c from public.customers where mobile = m;',
  'select * into c from public.customers where mobile = m and public._m132_own(org_unit_id) /* m132 */ order by (org_unit_id is not distinct from public._m132_caller_biz()) desc, org_unit_id limit 1;']);

select public._m132_patch('public.customer_save(uuid,jsonb,uuid)', '/* m132 */', array[
  'select * into c from public.customers where mobile = mob;',
  'select * into c from public.customers where mobile = mob and public._m132_own(org_unit_id) /* m132 */ order by (org_unit_id is not distinct from public._m132_caller_biz()) desc, org_unit_id limit 1;',
  'insert into public.customers (mobile, name, type, created_by, tier_id,',
  'insert into public.customers (org_unit_id, mobile, name, type, created_by, tier_id,',
  'values (mob, nm, coalesce(ty, ''retail''), auth.uid(), tid,',
  'values (nullif(p ->> ''org_unit_id'', '''')::bigint /* m132 */, mob, nm, coalesce(ty, ''retail''), auth.uid(), tid,']);

select public._m132_patch('public.customer_directory(integer)', '/* m132 */', array[
  'order by lower(c.name), c.mobile limit',
  'where public._m132_own(c.org_unit_id) /* m132 */ order by lower(c.name), c.mobile limit']);

select public._m132_patch('public.customer_balance(uuid)', '/* m132 */', array[
  'then public._cust_bal(p_customer) end;',
  'then (case when public._m132_own((select c.org_unit_id from public.customers c where c.id = p_customer)) /* m132 */ then public._cust_bal(p_customer) end) end;']);

select public._m132_patch('public.supplier_pick()', '/* m132 */', array[
  'where public.is_active() and s.active order by lower(s.name);',
  'where public.is_active() and s.active and public._m132_vis(''suppliers'', s.org_unit_id, s.id::text, false) /* m132 */ order by lower(s.name);']);

select public._m132_patch('public.scan_match_suppliers(text,integer)', '/* m132 */', array[
  'from public.suppliers s where s.active) z',
  'from public.suppliers s where s.active and public._m132_vis(''suppliers'', s.org_unit_id, s.id::text, false) /* m132 */) z']);

select public._m132_patch('public.scan_match_items(text,integer)', '/* m132 */', array[
  'from public.items i where i.is_active and not coalesce(i.hidden, false)) z',
  'from public.items i where i.is_active and not coalesce(i.hidden, false) and public._m132_vis(''items'', i.org_unit_id, i.id::text, false) /* m132 */) z']);

select public._m132_patch('public.artisan_list(boolean)', '/* m132 */', array[
  'from public.artisans a where p_include_retired or a.active)',
  'from public.artisans a where (p_include_retired or a.active) and public._m132_vis(''artisans'', a.org_unit_id, a.id::text, false) /* m132 */)']);

select public._m132_patch('public.category_list(boolean)', '/* m132 */', array[
  'where (p_include_inactive or (c.active and (c.parent_id is null or exists (select 1 from public.item_categories p where p.id = c.parent_id and p.active))))',
  'where public._m132_vis(''item_categories'', c.org_unit_id, c.id::text, false) /* m132 */ and (p_include_inactive or (c.active and (c.parent_id is null or exists (select 1 from public.item_categories p where p.id = c.parent_id and p.active))))']);

select public._m132_patch('public.item_dup_check(text,text,uuid)', '/* m132 */', array[
  'where public.is_active() and (p_exclude is null or i.id <> p_exclude)',
  'where public.is_active() and public._m132_vis(''items'', i.org_unit_id, i.id::text, false) /* m132 */ and (p_exclude is null or i.id <> p_exclude)']);

-- item-code resolvers: an item code is resolved inside the business of the place of the entry (switch ON); the clash checks follow the unique constraint that is really in force
select public._m132_patch('public._elp_post_line(entries,integer,text,jsonb)', '/* m132 */', array[
  'from public.items i where i.code = l->>''item'')', 'from public.items i where i.code = l->>''item'' and public._m132_at(i.org_unit_id, e.location_id) /* m132 */)',
  'select * into it from public.items where code = l->>''item'';', 'select * into it from public.items where code = l->>''item'' and public._m132_at(org_unit_id, e.location_id) /* m132 */;']);

select public._m132_patch('public.count_lines_seal(uuid)', '/* m132 */', array[
  'select * into it from public.items where code = btrim(r ->> ''item'');',
  'select * into it from public.items where code = btrim(r ->> ''item'') and public._m132_at(org_unit_id, e.location_id) /* m132 */;']);

select public._m132_patch('public._entries_countseal_guard23()', '/* m132 */', array[
  'left join public.items i on i.code = sl.item_code where',
  'left join public.items i on i.code = sl.item_code and public._m132_at(i.org_unit_id, new.location_id) /* m132 */ where']);

select public._m132_patch('public.variants_generate(bigint,jsonb,boolean)', '/* m132 */', array[
  'join public.items i on i.code = g.vcode and (i.style_id is distinct from p_style or i.variant_key is distinct from g.vkey);',
  'join public.items i on i.code = g.vcode and (i.style_id is distinct from p_style or i.variant_key is distinct from g.vkey) and (not public._m132_relaxed() or i.org_unit_id is not distinct from st.org_unit_id) /* m132 */;']);

select public._m132_patch('public._item_master_classify(jsonb)', '/* m132 */', array[
  'exists (select 1 from public.items i where i.code = c.code)',
  'exists (select 1 from public.items i where i.code = c.code and (not public._m132_relaxed() or i.org_unit_id is not distinct from public._m132_caller_biz()) /* m132 */)']);

select public._m132_patch('public.item_master_import_apply(jsonb,text,integer)', '/* m132 */', array[
  'on conflict (code) do nothing', 'on conflict (org_unit_id, code) /* m132 */ do nothing']);

-- the lookups BY ID of a master row inside the other functions ("select * into x from public.customers where id = p_x"): the row of another business answers like a missing id (switch ON).
-- One regular-expression patch per master table over every function that has the shape; marker "m132b"; the predicate is true while the switch is OFF and for the server.
create or replace function public._m132_patch_lookups(p_table text, p_pred text, p_skip_locks boolean default false) returns int
language plpgsql security definer set search_path = public as $$
declare r record; d text; nd text; n int := 0; pat text; pr text := replace(p_pred, '#', p_table);
begin
  -- p_skip_locks: a statement "... where id = x for update / for no key update" is a supplier lock of the money functions (phase109 pins their exact text): the write trigger guards it
  pat := '(from public\.' || p_table || ' where id = [a-z_][a-z_0-9.]*(::[a-z]+)?)(?![a-z_0-9.(])' || case when p_skip_locks then '(?! for )' else '' end;
  for r in select p.oid from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and p.proname !~ '^(_m132|org_masters|master_)' loop
    d := pg_get_functiondef(r.oid);
    continue when position('/* m132b:' || p_table || ' */' in d) > 0 or d !~* pat;
    nd := regexp_replace(d, pat, '\1 and ' || replace(pr, '\', '\\') || ' /* m132b:' || p_table || ' */', 'gi');
    if nd <> d then execute nd; n := n + 1; end if;
  end loop;
  return n;
end $$;

select public._m132_patch_lookups('customers', 'public._m132_own(#.org_unit_id)');
select public._m132_patch_lookups('suppliers', 'public._m132_vis(''suppliers'', #.org_unit_id, #.id::text, false)', true);
select public._m132_patch_lookups('items', 'public._m132_own(#.org_unit_id)');
select public._m132_patch_lookups('recipes', 'public._m132_own(#.org_unit_id)');
select public._m132_patch_lookups('artisans', 'public._m132_vis(''artisans'', #.org_unit_id, #.id::text, false)');

-- ---------- 7. sharing (owner only; default none; read only for the receiver) ----------
create or replace function public.master_share_create(p_table text, p_row_key text, p_from bigint, p_to bigint, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.master_scope132; s public.master_shares132; nid bigint; k text; ok boolean;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is null then raise exception 'client_id_needed'; end if;
  select * into s from public.master_shares132 where client_id = p_client;
  if found then return jsonb_build_object('dup', true, 'id', s.id); end if;
  select * into m from public.master_scope132 where table_name = p_table and decision = 'scoped';
  if not found or not m.shareable then raise exception 'table_not_shareable'; end if;
  if p_from is null or p_to is null or p_from = p_to then raise exception 'bad_business'; end if;
  if (select count(*) from public.org_units where id in (p_from, p_to) and kind = 'business' and status <> 'inactive') <> 2 then raise exception 'bad_business'; end if;
  if p_note is not null and length(p_note) > 300 then raise exception 'bad_note'; end if;
  k := nullif(btrim(coalesce(p_row_key, '')), '');
  if k is not null then
    execute format('select exists (select 1 from public.%I where org_unit_id = $1 and ((%s) = $2 or starts_with((%s), $2 || ''/'')))', p_table, m.key_expr, m.key_expr) into ok using p_from, k;
    if not ok then raise exception 'row_not_found'; end if;
  end if;
  select * into s from public.master_shares132 where table_name = p_table and coalesce(row_key, '') = coalesce(k, '') and from_org = p_from and to_org = p_to and status = 'active';
  if found then return jsonb_build_object('dup', true, 'id', s.id); end if;
  insert into public.master_shares132 (table_name, row_key, from_org, to_org, note, client_id, created_by) values (p_table, k, p_from, p_to, p_note, p_client, auth.uid()) returning id into nid;
  return jsonb_build_object('dup', false, 'id', nid);
end $$;

create or replace function public.master_share_revoke(p_id bigint, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.master_shares132;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  if p_reason is not null and length(p_reason) > 300 then raise exception 'bad_reason'; end if;
  select * into s from public.master_shares132 where id = p_id for update;
  if not found then raise exception 'share_not_found'; end if;
  if s.status = 'revoked' then return jsonb_build_object('dup', true, 'id', s.id); end if;
  update public.master_shares132 set status = 'revoked', revoked_by = auth.uid(), revoked_at = now(), revoked_reason = p_reason where id = p_id;
  return jsonb_build_object('dup', false, 'id', p_id);
end $$;

create or replace function public.master_share_list() returns table (id bigint, table_name text, row_key text, from_org bigint, from_code text, to_org bigint, to_code text, status text, note text, created_at timestamptz, revoked_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_active() and (public.is_owner() or public.has_grant('org_manage'))) then raise exception 'not allowed'; end if;
  return query select s.id, s.table_name, s.row_key, s.from_org, f.code, s.to_org, t.code, s.status, s.note, s.created_at, s.revoked_at
    from public.master_shares132 s join public.org_units f on f.id = s.from_org join public.org_units t on t.id = s.to_org order by s.id;
end $$;

-- the working business: new masters created by this user land in it (only among the user's own businesses; NULL clears)
create or replace function public.master_context_set132(p_org bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_org is null then delete from public.master_ctx132 where user_id = auth.uid(); return jsonb_build_object('org_unit_id', null); end if;
  if not exists (select 1 from public.org_units where id = p_org and kind = 'business' and status <> 'inactive') then raise exception 'bad_business'; end if;
  if not (p_org in (select public._my_biz123())) then raise exception 'not allowed'; end if;
  insert into public.master_ctx132 (user_id, org_unit_id) values (auth.uid(), p_org) on conflict (user_id) do update set org_unit_id = excluded.org_unit_id, set_at = now();
  return jsonb_build_object('org_unit_id', p_org);
end $$;

create or replace function public.master_context_get132() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when public.is_active() then jsonb_build_object('working', public._m132_caller_biz(), 'businesses', coalesce((select jsonb_agg(distinct b) from public._my_biz123() b), '[]'::jsonb)) end;
$$;

-- ---------- 8. the global unique constraints: preflight, relax, restore ----------
create or replace function public.org_masters_preflight() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r record; n bigint; nulls jsonb := '{}'::jsonb; blockers jsonb := '[]'::jsonb; warns jsonb := '[]'::jsonb; fns jsonb := '{}'::jsonb; f text; patched boolean; unp jsonb; ownmulti bigint;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  for r in select m.table_name, m.shared_col, m.shared_vals from public.master_scope132 m where m.decision = 'scoped' order by m.sort loop
    continue when to_regclass('public.' || r.table_name) is null;
    execute format('select count(*) from public.%I where org_unit_id is null%s', r.table_name,
      case when r.shared_col is not null then format(' and coalesce(%I::text, '''') <> all (%L::text[])', r.shared_col, r.shared_vals) else '' end) into n;   -- the shared vocabulary rows (units) are meant to have no business
    if n > 0 then nulls := nulls || jsonb_build_object(r.table_name, n); end if;
  end loop;
  if (select count(*) from public.master_scope132 where decision = 'scoped' and table_name in ('customers', 'items')) = 2 then
    if coalesce((nulls ->> 'customers')::bigint, 0) > 0 then blockers := blockers || to_jsonb('customers_without_business'::text); end if;
    if coalesce((nulls ->> 'items')::bigint, 0) > 0 then blockers := blockers || to_jsonb('items_without_business'::text); end if;
  end if;
  if not public._org_on123() then blockers := blockers || to_jsonb('org_scope_on_must_be_on'::text); end if;
  foreach f in array array['public.record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamp with time zone,text,numeric)', 'public.find_customer(text)', 'public.customer_pos_info(text)',
      'public.customer_save(uuid,jsonb,uuid)', 'public._elp_post_line(entries,integer,text,jsonb)', 'public.count_lines_seal(uuid)', 'public._entries_countseal_guard23()',
      'public.variants_generate(bigint,jsonb,boolean)', 'public._item_master_classify(jsonb)', 'public.item_master_import_apply(jsonb,text,integer)'] loop
    patched := to_regprocedure(f) is not null and position('/* m132 */' in pg_get_functiondef(to_regprocedure(f))) > 0;
    fns := fns || jsonb_build_object(f, patched);
    if not patched then blockers := blockers || to_jsonb('lookup_not_business_aware:' || f); end if;
  end loop;
  foreach f in array array['customers_org_mobile_uq132', 'items_org_code_uq125', 'items_org_barcode_uq132'] loop
    if not exists (select 1 from pg_class c join pg_index i on i.indexrelid = c.oid where c.relname = f and c.relnamespace = 'public'::regnamespace and i.indisvalid and i.indisunique) then
      blockers := blockers || to_jsonb('missing_unique_index:' || f);
    end if;
  end loop;
  -- functions that still resolve an item / customer by the global code or mobile and are NOT business aware (information for the owner, not a blocker)
  select coalesce(jsonb_agg(z.fn order by z.fn), '[]'::jsonb) into unp from (
    select p.oid::regprocedure::text fn from pg_proc p
     where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and position('/* m132 */' in pg_get_functiondef(p.oid)) = 0
       and p.proname !~ '^(_m132|org_masters|master_)'
       and (pg_get_functiondef(p.oid) ~* '(from|join) +(public\.)?items +(as +)?[a-z_]* *(on|where)[^;]{0,40}\mcode *= *[^;]{0,25}'
            or pg_get_functiondef(p.oid) ~* '(from|join) +(public\.)?customers +(as +)?[a-z_]* *(on|where)[^;]{0,40}\mmobile *= *[^;]{0,25}')) z;
  if jsonb_array_length(unp) > 0 then warns := warns || jsonb_build_array('code_or_mobile_lookups_not_business_aware'); end if;
  select count(*) into ownmulti from public.profiles p where p.status = 'active' and exists (select 1 from public.user_roles ur where ur.user_id = p.id and ur.role_code = 'owner')
     and not exists (select 1 from public.master_ctx132 c where c.user_id = p.id) and (select count(*) from public.org_units where kind = 'business' and status <> 'inactive') > 1;
  if ownmulti > 0 then warns := warns || jsonb_build_array('owner_has_no_working_business'); end if;
  return jsonb_build_object(
    'switch_on', public._org_on123(), 'unique_relaxed', public._m132_relaxed(),
    'businesses', (select count(*) from public.org_units where kind = 'business' and status <> 'inactive'),
    'scoped_tables', (select count(*) from public.master_scope132 where decision = 'scoped'),
    'rows_without_business', nulls,
    'active_shares', (select count(*) from public.master_shares132 where status = 'active'),
    'customer_mobile_duplicates_across_businesses', (select count(*) from (select mobile from public.customers group by mobile having count(*) > 1) q),
    'item_code_duplicates_across_businesses', (select count(*) from (select code from public.items group by code having count(*) > 1) q),
    'patched_functions', fns, 'lookups_not_business_aware', unp,
    'owners_without_working_business', ownmulti,
    'blockers', blockers, 'warnings', warns);
end $$;

create or replace function public.org_masters_relax_unique(p_dry boolean default true, p_ack_warnings boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pf jsonb; did jsonb := '[]'::jsonb; me uuid := auth.uid(); d text;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  if public._m132_relaxed() then return jsonb_build_object('dup', true, 'relaxed', true); end if;
  pf := public.org_masters_preflight();
  if jsonb_array_length(pf -> 'blockers') > 0 then
    if p_dry then return jsonb_build_object('dry', true, 'would_apply', false, 'blockers', pf -> 'blockers', 'warnings', pf -> 'warnings'); end if;
    raise exception 'preflight_failed' using hint = (pf -> 'blockers')::text;
  end if;
  if jsonb_array_length(pf -> 'warnings') > 0 and not p_ack_warnings and not p_dry then raise exception 'warnings_need_ack' using hint = (pf -> 'warnings')::text; end if;
  if p_dry then
    return jsonb_build_object('dry', true, 'would_apply', true, 'warnings', pf -> 'warnings', 'lookups_not_business_aware', pf -> 'lookups_not_business_aware',
      'would_drop', jsonb_build_array('customers_mobile_key', 'items_code_key', 'items_barcode_uq'));
  end if;
  if exists (select 1 from pg_constraint where conname = 'customers_mobile_key' and conrelid = 'public.customers'::regclass) then
    d := pg_get_constraintdef((select oid from pg_constraint where conname = 'customers_mobile_key' and conrelid = 'public.customers'::regclass));
    insert into public.master_unique_log132 (action, object_name, definition, by_user) values ('relax', 'customers_mobile_key', d, me);
    alter table public.customers drop constraint customers_mobile_key;
    did := did || to_jsonb('customers_mobile_key'::text);
  end if;
  if exists (select 1 from pg_constraint where conname = 'items_code_key' and conrelid = 'public.items'::regclass) then
    d := pg_get_constraintdef((select oid from pg_constraint where conname = 'items_code_key' and conrelid = 'public.items'::regclass));
    insert into public.master_unique_log132 (action, object_name, definition, by_user) values ('relax', 'items_code_key', d, me);
    alter table public.items drop constraint items_code_key;
    did := did || to_jsonb('items_code_key'::text);
  end if;
  if to_regclass('public.items_barcode_uq') is not null then
    insert into public.master_unique_log132 (action, object_name, definition, by_user) select 'relax', 'items_barcode_uq', pg_get_indexdef('public.items_barcode_uq'::regclass), me;
    drop index public.items_barcode_uq;
    did := did || to_jsonb('items_barcode_uq'::text);
  end if;
  return jsonb_build_object('dry', false, 'relaxed', true, 'dropped', did);
end $$;

create or replace function public.org_masters_restore_unique(p_dry boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare dm bigint; dc bigint; db bigint; did jsonb := '[]'::jsonb; me uuid := auth.uid();
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  if not public._m132_relaxed() then return jsonb_build_object('dup', true, 'relaxed', false); end if;
  select count(*) into dm from (select mobile from public.customers group by mobile having count(*) > 1) q;
  select count(*) into dc from (select code from public.items group by code having count(*) > 1) q;
  select count(*) into db from (select barcode from public.items where barcode is not null group by barcode having count(*) > 1) q;
  if dm + dc + db > 0 then
    if p_dry then return jsonb_build_object('dry', true, 'would_restore', false, 'duplicate_mobiles', dm, 'duplicate_codes', dc, 'duplicate_barcodes', db); end if;
    raise exception 'duplicates_block_restore' using hint = format('mobiles %s, codes %s, barcodes %s', dm, dc, db);
  end if;
  if p_dry then return jsonb_build_object('dry', true, 'would_restore', true); end if;
  if not exists (select 1 from pg_constraint where conname = 'customers_mobile_key' and conrelid = 'public.customers'::regclass) then
    alter table public.customers add constraint customers_mobile_key unique (mobile);
    insert into public.master_unique_log132 (action, object_name, definition, by_user) values ('restore', 'customers_mobile_key', 'UNIQUE (mobile)', me);
    did := did || to_jsonb('customers_mobile_key'::text);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'items_code_key' and conrelid = 'public.items'::regclass) then
    alter table public.items add constraint items_code_key unique (code);
    insert into public.master_unique_log132 (action, object_name, definition, by_user) values ('restore', 'items_code_key', 'UNIQUE (code)', me);
    did := did || to_jsonb('items_code_key'::text);
  end if;
  if to_regclass('public.items_barcode_uq') is null then
    create unique index items_barcode_uq on public.items (barcode) where barcode is not null;
    insert into public.master_unique_log132 (action, object_name, definition, by_user) values ('restore', 'items_barcode_uq', 'UNIQUE (barcode) WHERE barcode IS NOT NULL', me);
    did := did || to_jsonb('items_barcode_uq'::text);
  end if;
  return jsonb_build_object('dry', false, 'relaxed', false, 'restored', did);
end $$;

-- while the global unique constraints are relaxed the switch cannot be turned OFF (the old lookups assume one row per mobile / code)
create or replace function public._m132_rule_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.key = 'org_scope_on' and public._m132_relaxed()
     and not coalesce((coalesce(new.value, new.default_value) #>> '{}')::boolean, false) then
    raise exception 'masters_unique_relaxed_restore_first';
  end if;
  return new;
end $$;
drop trigger if exists rules_m132 on public.rules;
create trigger rules_m132 before update on public.rules for each row when (old.key = 'org_scope_on') execute function public._m132_rule_guard();

-- ---------- 9. the coverage report (owner / org_manage) ----------
create or replace function public.master_scope_report132() returns table (table_name text, decision text, kind text, shareable boolean, in_audit_list boolean, total_rows bigint, rows_without_business bigint, why text)
language plpgsql stable security definer set search_path = public as $$
declare r record; n bigint; z bigint;
begin
  if not (public.is_active() and (public.is_owner() or public.has_grant('org_manage'))) then raise exception 'not allowed'; end if;
  for r in select * from public.master_scope132 m order by m.sort, m.table_name loop
    n := null; z := null;
    if to_regclass('public.' || r.table_name) is not null then
      execute format('select count(*) from public.%I', r.table_name) into n;
      if r.decision = 'scoped' then
        execute format('select count(*) from public.%I where org_unit_id is null%s', r.table_name,
          case when r.shared_col is not null then format(' and coalesce(%I::text, '''') <> all (%L::text[])', r.shared_col, r.shared_vals) else '' end) into z;
      end if;
    end if;
    table_name := r.table_name; decision := r.decision; kind := r.kind; shareable := r.shareable; in_audit_list := r.audit_set; total_rows := n; rows_without_business := z; why := r.why;
    return next;
  end loop;
end $$;

-- ---------- 10. privileges ----------
revoke all on function public._m132_caller_biz(), public._m132_biz_of_loc(int), public._m132_relaxed(), public._m132_scope(), public._m132_xbiz(), public._m132_rule_guard(),
  public._m132_patch(text, text, text[]), public._m132_patch_lookups(text, text, boolean) from public, anon, authenticated;
revoke all on function public._m132_at(bigint, int), public._m132_own(bigint), public._m132_vis(text, bigint, text, boolean) from public, anon, authenticated;     -- used only inside the SECURITY DEFINER functions
revoke all on function public._m132_mybiz(), public._m132_shared(text, bigint, text) from public, anon;
grant execute on function public._m132_mybiz(), public._m132_shared(text, bigint, text) to authenticated;   -- used inside the policies
revoke all on function public.master_share_create(text, text, bigint, bigint, text, uuid), public.master_share_revoke(bigint, text), public.master_share_list(), public.master_context_set132(bigint),
  public.master_context_get132(), public.org_masters_preflight(), public.org_masters_relax_unique(boolean, boolean), public.org_masters_restore_unique(boolean), public.master_scope_report132() from public, anon;
grant execute on function public.master_share_create(text, text, bigint, bigint, text, uuid), public.master_share_revoke(bigint, text), public.master_share_list(), public.master_context_set132(bigint),
  public.master_context_get132(), public.org_masters_preflight(), public.org_masters_relax_unique(boolean, boolean), public.org_masters_restore_unique(boolean), public.master_scope_report132() to authenticated;

commit;
