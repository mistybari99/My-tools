-- ============================================================
-- Phase 123 (marker scope123) - GROUP ERP, STAGE C1 first slice: business isolation behind the switch org_scope_on (DEFAULT OFF).
-- Plan: docs/GROUP_ERP_STAGE_A.md sections 3.4, 10, 11; audit docs/audit_c1/RLS_ISOLATION_AUDIT.md (branch local-audit-rls). Canonical order: after phase122 (docs/PASTE_ORDER.md row 51).
-- Paste twice = no change, no error. With org_scope_on OFF (the default) EVERY function below returns exactly what it returned before this file
-- (each re-created body keeps the old expression verbatim in its OFF branch; tests/sql/c1_before_after.sh proves it on seeded data).
-- Needs phase122 (org_units, locations.org_unit_id, rule org_scope_on). Rollback: leave the rule OFF; to remove, re-paste the older phase files that own the re-created
-- functions (phase7 can_loc, phase8 has_grant, phase10 _all_locs, phase40 _acct_all, phase46 _notif_ok, phase2 staff_directory, phase12/105 customer_dues + customer_ledger,
-- phase53 fa_register / fa_schedule / year_close_list, phase88 items_with_cost / item_cost_status88, phase95 drawer_report, phase112 profit_truth112, phase7 decide_emergency), drop the
-- restrictive policies *_scope123, the trigger stock_transfers_biz123 and the new table / functions.
--
--   NEW (all closed to anon; helpers closed to the browser too)
--     table user_org_scopes (user, org_unit, role, status active|revoked; history kept; RLS: own rows / owner / org_manage; no browser write; audit + no-delete triggers)
--       One row = "this user holds this role over this unit and everything below it". A row is live only while the user still holds that role in user_roles.
--     can_scope(unit, role) / business_of_location(loc) / business_of_unit are the public helpers; _org_on123 (the switch), _org_anc123, _scopes123, _user_biz123, _my_biz123,
--       _biz_ok123, _mgmt_covers123, _loc_vis123, _item_cost_scoped123 are internal.
--     org_scope_grant / org_scope_revoke / org_scope_list / org_scope_preflight : owner (list: owner / org_manage see all, others their own rows).
--   WHEN org_scope_on = ON (stricter option chosen wherever the plan left room, see HANDOVER_7)
--     can_loc(loc)   owner = every location. Anybody else: own user_locations row, or a live 'management' scope covering the location's unit (so management = all locations of ITS
--                    business only), or an approved loc_access window for a location of one of their businesses. can_loc(null) = owner only. The global management bypass is gone.
--     _all_locs(), _acct_all()   owner only (a company-wide view is a group-owner view; an accountant sees journals place by place through can_loc).
--     has_grant(code, loc)   with a location: the location must belong to one of the caller's businesses (role grants, personal grants and windows alike), and a personal
--                    grant with NULL location means "the caller's businesses", never the database. Without a location nothing changes (the data is filtered further down).
--     _notif_ok      a notification for the 'manager' audience with no place is owner only.
--     Readers that returned data of every place without can_loc now filter by it: customer_dues, customer_ledger, fa_register, fa_schedule, year_close_list (owner only),
--                    items_with_cost + item_cost_status88 (non-owner: cost computed from the stock of the caller's own places only), drawer_report, staff_directory (people of the
--                    caller's businesses only), profit_truth112 (a place that is not yours is refused).
--     Restrictive read policies (AND-ed with the old ones, true while the switch is OFF) on the location-bearing tables that any active user could read: locations, location_settings,
--                    att_site_geo, blind_count_cfg, doc_template_choice, form_rollout, holidays, path_switch, report_brand_map, sales_channels, shifts, invoice_templates + print_profiles
--                    (read and write), the weak has_grant-only ones: location_setup_steps, paper_books, print_notes, settings_sheets, and budget_log, payment_intents,
--                    payroll_bonus_events; emergency_requests (own rows, or the business's). A row with NULL location = owner only.
--     decide_emergency: the approver must belong to the request's business (the role grant emergency_decide is global).
--     A stock transfer between two businesses is refused by a trigger (intercompany is Stage E).
--   DEFERRED (docs/HANDOVER_7.md): global masters without an owner column (items, customers, suppliers, recipes, vocabularies, rules, roles, grant_defs ...) = Stage C2; per-business
--     rules; the other ~170 unscoped reader RPCs (Appendix B of the audit); owner-only RPC families; storage bucket paths; bot identities; find_customer / customer_balance.
-- ============================================================
begin;

do $g$
declare miss text := '';
begin
  if to_regclass('public.org_units') is null or to_regclass('public.legal_entities') is null or to_regclass('public.locations') is null or to_regclass('public.user_roles') is null
     or to_regclass('public.user_locations') is null or to_regclass('public.user_grants') is null or to_regclass('public.emergency_requests') is null
     or to_regclass('public.stock_transfers') is null or to_regclass('public.fa_assets') is null or to_regclass('public.drawer_events') is null then miss := miss || ' tables'; end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'locations' and column_name = 'org_unit_id') then miss := miss || ' locations.org_unit_id'; end if;
  if not exists (select 1 from public.rules where key = 'org_scope_on') then miss := miss || ' rule:org_scope_on'; end if;
  if to_regprocedure('public.can_loc(integer)') is null or to_regprocedure('public.has_grant(text,integer)') is null or to_regprocedure('public._all_locs()') is null
     or to_regprocedure('public._acct_all()') is null or to_regprocedure('public._item_cost_eff88()') is null or to_regprocedure('public._rcs88()') is null
     or to_regprocedure('public.profit_truth112(date,date,integer)') is null or to_regprocedure('public.drawer_report(date,date)') is null
     or to_regprocedure('public.items_with_cost()') is null or to_regprocedure('public.item_cost_status88()') is null or to_regprocedure('public.fa_register(date)') is null
     or to_regprocedure('public._client_lock(uuid)') is null or to_regprocedure('public.org_unit_save(bigint,bigint,text,text,text,text,text,text,date,date,text,text,jsonb,jsonb,uuid)') is null
     then miss := miss || ' functions'; end if;
  if miss <> '' then raise exception 'phase123 needs the base schema and phases up to 122 pasted first (docs/PASTE_ORDER.md); missing:%', miss; end if;
end $g$;

-- ---------- 1. who holds which role over which unit ----------
create table if not exists public.user_org_scopes (
  id bigserial primary key,
  user_id uuid not null references public.profiles(id),
  org_unit_id bigint not null references public.org_units(id),
  role_code text not null references public.roles(code),
  status text not null default 'active' check (status in ('active', 'revoked')),
  note text check (note is null or length(note) <= 300),
  client_id uuid unique,
  granted_by uuid, granted_at timestamptz not null default now(),
  revoked_by uuid, revoked_at timestamptz, revoked_reason text check (revoked_reason is null or length(revoked_reason) <= 300)
);
create unique index if not exists user_org_scopes_active123 on public.user_org_scopes (user_id, org_unit_id, role_code) where status = 'active';
create index if not exists user_org_scopes_unit123 on public.user_org_scopes (org_unit_id);

drop trigger if exists uos123_no_delete on public.user_org_scopes;
create trigger uos123_no_delete before delete on public.user_org_scopes for each row execute function public.no_hard_delete();
drop trigger if exists audit_uos123 on public.user_org_scopes;
create trigger audit_uos123 after insert or update on public.user_org_scopes for each row execute function public.log_change('id');

alter table public.user_org_scopes enable row level security;
drop policy if exists uos123_read on public.user_org_scopes;
create policy uos123_read on public.user_org_scopes for select to authenticated using (user_id = auth.uid() or public.is_owner() or public.has_grant('org_manage'));
revoke all on public.user_org_scopes from public, anon, authenticated;
grant select on public.user_org_scopes to authenticated;
revoke all on sequence public.user_org_scopes_id_seq from public, anon, authenticated;

-- ---------- 2. helpers ----------
-- the switch (rule org_scope_on). Anything unreadable counts as OFF.
create or replace function public._org_on123() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select (coalesce(r.value, r.default_value) #>> '{}')::boolean from public.rules r where r.key = 'org_scope_on'), false);   -- same value as rule_on('org_scope_on'), one lookup instead of three nested calls
$$;

-- the unit and all its parents
create or replace function public._org_anc123(p_unit bigint) returns setof bigint
language sql stable security definer set search_path = public as $$
  with recursive up(id, parent_id) as (
    select o.id, o.parent_id from public.org_units o where o.id = p_unit
    union
    select p.id, p.parent_id from public.org_units p join up on p.id = up.parent_id)
  select id from up;
$$;

-- the business a unit belongs to (the unit itself when it is one); null above the business level or for null
create or replace function public._business_of_unit123(p_unit bigint) returns bigint
language sql stable security definer set search_path = public as $$
  select o.id from public.org_units o where o.kind = 'business' and o.id in (select public._org_anc123(p_unit)) limit 1;
$$;

-- live scope rows of a user: active AND the user still holds that role
create or replace function public._scopes123(p_user uuid) returns table (org_unit_id bigint, role_code text)
language sql stable security definer set search_path = public as $$
  select s.org_unit_id, s.role_code from public.user_org_scopes s
   where s.user_id = p_user and s.status = 'active'
     and exists (select 1 from public.user_roles ur where ur.user_id = s.user_id and ur.role_code = s.role_code);
$$;

-- the businesses a user belongs to: through a scope that covers the whole business (the business or a parent of it), a scope below it, or an assigned location
create or replace function public._user_biz123(p_user uuid) returns setof bigint
language sql stable security definer set search_path = public as $$
  select b.id from public.org_units b
   where b.kind = 'business' and (
     exists (select 1 from public._scopes123(p_user) sc where sc.org_unit_id in (select public._org_anc123(b.id)))
     or exists (select 1 from public._scopes123(p_user) sc where public._business_of_unit123(sc.org_unit_id) = b.id)
     or exists (select 1 from public.user_locations ul join public.locations l on l.id = ul.location_id
                 where ul.user_id = p_user and l.org_unit_id is not null and public._business_of_unit123(l.org_unit_id) = b.id));
$$;

-- the caller's businesses (the owner: every business)
create or replace function public._my_biz123() returns setof bigint
language sql stable security definer set search_path = public as $$
  select b.id from public.org_units b where b.kind = 'business' and public.is_active() and public.is_owner()
  union
  select x from public._user_biz123(auth.uid()) x where public.is_active();
$$;

-- business of a location (internal, unguarded)
create or replace function public._business_of_loc123(p_loc int) returns bigint
language sql stable security definer set search_path = public as $$
  select public._business_of_unit123(l.org_unit_id) from public.locations l where l.id = p_loc;
$$;

-- does the location belong to one of the caller's businesses? (owner: always; unmapped location: only the owner)
create or replace function public._biz_ok123(p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or (
    p_loc is not null and public._business_of_loc123(p_loc) is not null and public._business_of_loc123(p_loc) in (select public._my_biz123())));
$$;

-- does a live 'management' scope of the caller cover the location?
create or replace function public._mgmt_covers123(p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public._scopes123(auth.uid()) sc join public.locations l on l.id = p_loc
                  where sc.role_code = 'management' and l.org_unit_id is not null and sc.org_unit_id in (select public._org_anc123(l.org_unit_id)));
$$;

-- row filter used by the restrictive policies: true while the switch is OFF; ON: owner, or a location of one of the caller's businesses (NULL location: owner only)
create or replace function public._loc_vis123(p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select not public._org_on123() or (public.is_active() and (public.is_owner() or public._biz_ok123(p_loc)));
$$;

-- does the user share a business with the caller? (owner: everybody)
create or replace function public._shares_biz123(p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or p_user = auth.uid() or exists (select 1 from public._user_biz123(p_user) x where x in (select public._my_biz123())));
$$;

-- PUBLIC: may the caller act over this unit (and everything below it)? owner = yes; others need a live scope row on the unit or a parent of it (p_role null = any role).
-- Independent of the switch (it only says what the scope table grants).
create or replace function public.can_scope(p_unit bigint, p_role text default null) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and p_unit is not null and (public.is_owner() or exists (
    select 1 from public._scopes123(auth.uid()) sc where (p_role is null or sc.role_code = p_role) and sc.org_unit_id in (select public._org_anc123(p_unit))));
$$;

-- PUBLIC: the business of a location. Null when unmapped, or (switch ON, not owner) when the location is not one of the caller's.
create or replace function public.business_of_location(p_loc int) returns bigint
language sql stable security definer set search_path = public as $$
  select case when not public.is_active() then null
              when public._org_on123() and not public._biz_ok123(p_loc) then null
              else public._business_of_loc123(p_loc) end;
$$;

-- ---------- 3. the access primitives (OFF branch = the old text, verbatim) ----------
create or replace function public.can_loc(p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (case when not coalesce((select (coalesce(r.value, r.default_value) #>> '{}')::boolean from public.rules r where r.key = 'org_scope_on'), false) then (   -- the switch read inline (can_loc runs once per row in the policies)
    -- OFF: exactly the rule of phase7
    public.is_owner()
    or exists (select 1 from public.user_roles where user_id = auth.uid() and role_code = 'management')
    or exists (select 1 from public.user_locations where user_id = auth.uid() and location_id = p_loc)
    or exists (select 1 from public.emergency_requests e where e.requested_by = auth.uid() and e.grant_code = 'loc_access' and e.status = 'approved' and e.valid_until > now()
               and e.location_id = p_loc))
  else (
    -- ON (scope123): owner = all; the rest only inside their own business(es); no location (null) = owner only
    public.is_owner()
    or (p_loc is not null and (
         exists (select 1 from public.user_locations where user_id = auth.uid() and location_id = p_loc)
         or public._mgmt_covers123(p_loc)
         or (public._biz_ok123(p_loc) and exists (select 1 from public.emergency_requests e where e.requested_by = auth.uid() and e.grant_code = 'loc_access' and e.status = 'approved'
                                                  and e.valid_until > now() and e.location_id = p_loc))))
  ) end);
$$;

create or replace function public._all_locs() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (case when not public._org_on123()
    then (public.is_owner() or exists (select 1 from public.user_roles where user_id = auth.uid() and role_code = 'management'))   -- OFF: phase10
    else public.is_owner() end);                                                                                                  -- ON (scope123): owner only
$$;

create or replace function public._acct_all() returns boolean language sql stable security definer set search_path = public as $$
  select case when not public._org_on123()
    then (public.can_loc(null) or (public.is_active() and public.has_grant('accounts_manage')))   -- OFF: phase40
    else (public.is_active() and public.is_owner()) end;                                          -- ON (scope123): owner only
$$;

create or replace function public.has_grant(p_code text, p_loc int default null) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or (public.is_active() and (case when not coalesce((select (coalesce(r.value, r.default_value) #>> '{}')::boolean from public.rules r where r.key = 'org_scope_on'), false) then (   -- the switch read inline
    -- OFF: exactly the rule of phase8
    public.can_grant(p_code)
    or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = p_code
               and (g.valid_until is null or g.valid_until > now()) and (g.location_id is null or g.location_id = p_loc))
    or exists (select 1 from public.emergency_requests e join public.grant_defs d on d.grant_code = e.grant_code and d.window_type = 'window'
               where e.requested_by = auth.uid() and e.grant_code = p_code and e.status = 'approved' and e.valid_until > now()
               and (p_loc is null or e.location_id is null or e.location_id = p_loc)))
  else (
    -- ON (scope123): with a location it must be one of the caller's businesses; a personal grant without a location = the caller's businesses, not the database
    (p_loc is null or public._biz_ok123(p_loc)) and (
      public.can_grant(p_code)
      or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = p_code
                 and (g.valid_until is null or g.valid_until > now()) and (g.location_id is null or g.location_id = p_loc))
      or exists (select 1 from public.emergency_requests e join public.grant_defs d on d.grant_code = e.grant_code and d.window_type = 'window'
                 where e.requested_by = auth.uid() and e.grant_code = p_code and e.status = 'approved' and e.valid_until > now()
                 and (p_loc is null or e.location_id is null or e.location_id = p_loc)))
  ) end));
$$;

create or replace function public._notif_ok(p_user uuid, p_aud text, p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (
    case when p_user is not null then p_user = auth.uid()
         else (p_aud = 'all'
               or public.is_owner()
               or (p_aud = 'manager' and (p_loc is not null or not public._org_on123()) and exists (select 1 from public.user_roles r where r.user_id = auth.uid()   -- scope123: no place = owner only
                     and r.role_code in ('management', 'showroom_manager', 'cash_controller', 'factory_incharge', 'purchasing', 'hr')))) end
    and (p_loc is null or p_user is not null or public.can_loc(p_loc)));
$$;

-- ---------- 4. readers that returned several places' data without can_loc ----------
create or replace function public.staff_directory() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when public.is_active()
    then coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'staff_id', p.staff_id, 'full_name', p.full_name) order by p.full_name)
                   from public.profiles p where p.status = 'active' and (not public._org_on123() or public._shares_biz123(p.id))), '[]'::jsonb)   -- scope123: people of my businesses
    else '[]'::jsonb end;
$$;

create or replace function public.customer_dues() returns table (id uuid, name text, mobile text, type text, credit_limit numeric, balance numeric, oldest date)
language sql stable security definer set search_path = public as $$
  with s as (
    select x.id, x.customer_id, x.sale_date, x.sold_at,
           x.total - coalesce((select sum(p.amount) from public.sale_payments p where p.sale_id = x.id and not p.voided), 0) rem
    from public.sales x where x.status = 'done' and x.customer_id is not null and (not (select public._org_on123()) or public.can_loc(x.location_id))),
  cum as (select s.*, sum(s.rem) over (partition by s.customer_id order by s.sold_at, s.id) cr from s where s.rem > 0),
  c as (select z.customer_id, sum(z.a) coll from (
          select customer_id, amount a from public.sale_payments where kind = 'collection' and not voided and customer_id is not null and (not (select public._org_on123()) or public.can_loc(location_id))
          union all select customer_id, credit_amount from public.sale_returns where status = 'done' and customer_id is not null and credit_amount > 0 and (not (select public._org_on123()) or public.can_loc(location_id))) z group by 1),
  t as (select customer_id, sum(rem) rem from s group by 1)
  select cu.id, cu.name, public._cust_pii103('mobile', cu.mobile) /* bos105 */, cu.type, cu.credit_limit, t.rem - coalesce(c.coll, 0),
         (select min(k.sale_date) from cum k where k.customer_id = cu.id and k.cr > coalesce(c.coll, 0))
  from public.customers cu join t on t.customer_id = cu.id left join c on c.customer_id = cu.id
  where (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) and t.rem - coalesce(c.coll, 0) > 0
  order by 6 desc;
$$;

create or replace function public.customer_ledger(p_customer uuid) returns table (at timestamptz, kind text, ref text, location_id int, debit numeric, credit numeric, balance numeric, note text, pid bigint)
language sql stable security definer set search_path = public as $$
  with e as (
    select s.sold_at at, 'sale'::text kind, '#' || s.receipt ref, s.location_id, s.total debit, 0::numeric credit, case when s.sale_type = 'wholesale' then 'wholesale' end note, null::bigint pid
      from public.sales s where s.customer_id = p_customer and s.status = 'done' and (not (select public._org_on123()) or public.can_loc(s.location_id))
    union all
    select p.paid_at, case when p.kind = 'collection' then 'collection' else 'paid' end, coalesce(p.wallet, p.mode), p.location_id, 0, p.amount, p.note, p.id
      from public.sale_payments p where p.customer_id = p_customer and not p.voided and (not (select public._org_on123()) or public.can_loc(p.location_id))
    union all
    select r.created_at, 'sale_return', '#' || s.receipt, r.location_id, 0, r.credit_amount, r.reason_code, null::bigint
      from public.sale_returns r join public.sales s on s.id = r.sale_id where r.customer_id = p_customer and r.status = 'done' and r.credit_amount > 0 and (not (select public._org_on123()) or public.can_loc(r.location_id)))
  select e.at, e.kind, e.ref, e.location_id, e.debit, e.credit, sum(e.debit - e.credit) over (order by e.at, (e.debit > 0) desc, e.kind), e.note, e.pid
  from e where (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) order by e.at, (e.debit > 0) desc, e.kind;
$$;

create or replace function public.fa_register(p_as_of date default null) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare as_ date := coalesce(p_as_of, public._acct_today());
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  return jsonb_build_object('on', public.rule_on('fixed_assets_on'), 'as_of', as_, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'name', a.name, 'category', a.category, 'location_id', a.location_id, 'acquired_on', a.acquired_on, 'cost', a.cost, 'salvage', a.salvage,
      'life_months', a.life_months, 'method', a.method, 'depr_from', a.depr_from, 'status', a.status, 'disposed_on', a.disposed_on,
      'accumulated', coalesce(p.s, 0), 'book_value', a.cost - coalesce(p.s, 0), 'months_posted', coalesce(p.n, 0), 'last_month', p.mx) order by a.code)
    from public.fa_assets a left join lateral (select sum(amount) s, count(*) n, max(month) mx from public.fa_depr_posts x where x.asset_id = a.id and x.month <= as_) p on true
    where (not public._org_on123() or public.can_loc(a.location_id))), '[]'::jsonb));   -- scope123: the caller's places (no place = owner only)
end $$;

create or replace function public.fa_schedule(p_id uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare a public.fa_assets; rows_ jsonb;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  select * into a from public.fa_assets where id = p_id;
  if not found then raise exception 'not found'; end if;
  if public._org_on123() and not public.can_loc(a.location_id) then raise exception 'not found'; end if;   -- scope123: same answer as a missing id
  select coalesce(jsonb_agg(jsonb_build_object('k', k, 'month', m, 'amount', amt, 'accumulated', acc, 'book_value', a.cost - acc, 'posted', p.id is not null,
      'skipped_after_disposal', a.status = 'disposed' and m > public._a53_mon(a.disposed_on)) order by k), '[]'::jsonb) into rows_ from (
    select g k, (a.depr_from + ((g - 1) || ' months')::interval)::date m, public._a53_fa_amt(a.cost, a.salvage, a.life_months, g) amt,
      sum(public._a53_fa_amt(a.cost, a.salvage, a.life_months, g)) over (order by g) acc from generate_series(1, a.life_months) g) s
    left join public.fa_depr_posts p on p.asset_id = a.id and p.month = s.m;
  return jsonb_build_object('asset_id', a.id, 'code', a.code, 'name', a.name, 'cost', a.cost, 'salvage', a.salvage, 'life_months', a.life_months, 'method', a.method, 'status', a.status, 'rows', rows_);
end $$;

create or replace function public.year_close_list() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if public._org_on123() and not public._acct_all() then raise exception 'not allowed'; end if;   -- scope123: year closes are company-level records (owner only until the per-entity books of Stage C2)
  return jsonb_build_object('on', public.rule_on('year_close_on'), 'period_closed_until', public.rule_txt('period_closed_until'), 'owner', public.is_owner(),
    'rows', coalesce((select jsonb_agg(to_jsonb(y) - 'client_id' order by y.fiscal_to desc, y.id desc) from public.year_closes y), '[]'::jsonb));
end $$;

-- item cost seen from the caller's own places only (non-owner, switch ON). Same logic as _item_cost_eff88 with the stock filtered by can_loc;
-- only items the caller's places hold appear (items are still ONE global master until Stage C2).
create or replace function public._item_cost_scoped123() returns table (item_id uuid, cost_price numeric, src text)
language sql stable security definer set search_path = public as $$
  with m as materialized (select public._rcs88() as m),
  lg as (
    select b.item_id as iid,
           coalesce(sum(b.qty * b.avg_cost) filter (where b.qty > 0 and coalesce(b.avg_cost, 0) > 0) / nullif(sum(b.qty) filter (where b.qty > 0 and coalesce(b.avg_cost, 0) > 0), 0),
                    (select l.unit_cost from public.stock_ledger l where l.item_id = b.item_id and public.can_loc(l.location_id) and coalesce(l.unit_cost, 0) > 0 and l.qty_delta > 0 order by l.id desc limit 1)) as c
    from public.stock_balance b where public.can_loc(b.location_id) group by b.item_id),
  ic as (select x.item_id as iid, x.cost_price as c from public.item_costs x where x.cost_price is not null)
  select z.iid, z.cp, z.s from (
    select lg.iid as iid,
           case m.m when 'item_costs' then ic.c when 'ledger_avg' then lg.c else coalesce(lg.c, ic.c) end as cp,
           case m.m when 'item_costs' then 'item_costs' when 'ledger_avg' then 'ledger' else (case when lg.c is not null then 'ledger' else 'item_costs' end) end as s
    from lg left join ic on ic.iid = lg.iid cross join m) z
  where z.cp is not null;
$$;

create or replace function public.items_with_cost() returns table (item_id uuid, cost_price numeric)
language sql stable security definer set search_path = public as $$
  select c.item_id, c.cost_price from (
    select e.item_id, e.cost_price from public._item_cost_eff88() e where (select not public._org_on123() or public.is_owner())   -- bos88: the effective cost of the ONE source (report_cost_source); an item with no known cost has NO row = unknown, never 0
    union all
    select s.item_id, s.cost_price from public._item_cost_scoped123() s where (select public._org_on123() and not public.is_owner())   -- scope123: my own places only
  ) c
  -- a location-scoped personal view_cost grant counts too (the list is company wide, so any location grant is enough; role grants and the owner as before)
  where public.is_active() and (public.is_owner() or public.can_do('ITEM_COST', 'view') or public.has_grant('view_cost')
    or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = 'view_cost' and (g.valid_until is null or g.valid_until > now())));
$$;

create or replace function public.item_cost_status88() returns table (item_id uuid, code text, cost_price numeric, source text, cost_missing boolean)
language sql stable security definer set search_path = public as $$
  select i.id, i.code, e.cost_price, coalesce(e.src, 'none'), e.cost_price is null
  from public.items i left join (
    select x.item_id, x.cost_price, x.src from public._item_cost_eff88() x where (select not public._org_on123() or public.is_owner())
    union all
    select y.item_id, y.cost_price, y.src from public._item_cost_scoped123() y where (select public._org_on123() and not public.is_owner())) e on e.item_id = i.id
  where i.is_active and i.count_in_business and public.is_active()
    and (public.is_owner() or public.can_do('ITEM_COST', 'view') or public.has_grant('view_cost')
         or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = 'view_cost' and (g.valid_until is null or g.valid_until > now())))
  order by i.code;
$$;

create or replace function public.drawer_report(p_from date default null, p_to date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := coalesce(p_from, (now() at time zone 'Asia/Dhaka')::date - 29); t date := coalesce(p_to, (now() at time zone 'Asia/Dhaka')::date); res jsonb;
begin
  if not (public.is_owner() or public.has_grant('view_reports')) then raise exception 'not allowed'; end if;
  if t < f then raise exception 'bad_range'; end if;
  if t - f > 366 then raise exception 'range_too_long'; end if;
  with e as (
    select d.*, (d.at at time zone 'Asia/Dhaka')::date as day from public.drawer_events d where (d.at at time zone 'Asia/Dhaka')::date between f and t
      and (not public._org_on123() or public.can_loc(d.location_id)))   -- scope123: the caller's places only
  select jsonb_build_object(
    'from', f, 'to', t,
    'totals', jsonb_build_object(
      'auto_open', (select count(*) from e where event = 'auto_open'), 'no_sale_open', (select count(*) from e where event = 'no_sale_open'),
      'test_open', (select count(*) from e where event = 'test_open'), 'failed', (select count(*) from e where event = 'failed')),
    'by_user', coalesce((select jsonb_agg(x order by (x ->> 'no_sale_open')::int desc, x ->> 'staff') from (
        select jsonb_build_object('user_id', by_user, 'staff', coalesce(max(by_staff), ''), 'name', coalesce(max(p.full_name), ''),
                 'no_sale_open', count(*) filter (where event = 'no_sale_open'), 'auto_open', count(*) filter (where event = 'auto_open'),
                 'failed', count(*) filter (where event = 'failed'), 'last_no_sale', max(e.at) filter (where event = 'no_sale_open')) as x
        from e left join public.profiles p on p.id = e.by_user group by by_user) q), '[]'::jsonb),
    'by_day', coalesce((select jsonb_agg(jsonb_build_object('day', day, 'no_sale_open', n) order by day) from (
        select day, count(*) as n from e where event = 'no_sale_open' group by day) q), '[]'::jsonb),
    'recent_no_sale', coalesce((select jsonb_agg(jsonb_build_object('at', at, 'staff', by_staff, 'location_id', location_id, 'reason', reason) order by at desc) from (
        select * from e where event = 'no_sale_open' order by at desc limit 50) q), '[]'::jsonb))
  into res;
  return res;
end $$;

create or replace function public.profit_truth112(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; rws jsonb; co jsonb; un numeric := 0; unc numeric := 0; wu int := 0; np numeric := 0; npf numeric := 0; prov boolean; notes jsonb := '[]'::jsonb;
begin   -- bos112
  if not (public.biz_ok() and public.biz_cost_ok() and public._acct_view()) then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  if public._org_on123() and p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;   -- scope123
  locs := array(select l.id from public.locations l where (p_loc is null or l.id = p_loc) and public.can_loc(l.id));
  select coalesce(jsonb_agg(t), '[]'::jsonb) into rws from public._pnl_truth112(p_from, p_to, locs) t;
  select coalesce(sum((t ->> 'profit')::numeric), 0), coalesce(sum((t ->> 'profit_if_uncosted_free')::numeric), 0), coalesce(sum((t ->> 'uncosted_rev')::numeric), 0),
         coalesce(sum((t ->> 'wastage_unknown_cost')::int), 0), coalesce(sum((t ->> 'unallocated')::numeric), 0)
    into np, npf, unc, wu, un from jsonb_array_elements(rws) t;
  -- the unallocated row has no profit_if_uncosted_free: it costs the same in both figures
  npf := npf + coalesce((select sum((t ->> 'profit')::numeric) from jsonb_array_elements(rws) t where t ->> 'row_type' = 'unallocated'), 0);
  prov := unc > 0.004 or un > 0.004 or wu > 0;
  if unc > 0.004 then notes := notes || jsonb_build_array('uncosted_revenue'); end if;
  if un > 0.004 then notes := notes || jsonb_build_array('unallocated_shared_costs'); end if;
  if wu > 0 then notes := notes || jsonb_build_array('wastage_cost_unknown'); end if;
  co := jsonb_build_object(
    'net_sales', coalesce((select sum((t ->> 'net_sales')::numeric) from jsonb_array_elements(rws) t), 0),
    'costed_rev', coalesce((select sum((t ->> 'costed_rev')::numeric) from jsonb_array_elements(rws) t), 0),
    'cogs', coalesce((select sum((t ->> 'cogs')::numeric) from jsonb_array_elements(rws) t), 0),
    'expenses', coalesce((select sum((t ->> 'expenses')::numeric) from jsonb_array_elements(rws) t where t ->> 'row_type' = 'truth'), 0),
    'salary', coalesce((select sum((t ->> 'salary')::numeric) from jsonb_array_elements(rws) t), 0),
    'fixed', coalesce((select sum((t ->> 'fixed')::numeric) from jsonb_array_elements(rws) t), 0),
    'wastage', coalesce((select sum((t ->> 'wastage')::numeric) from jsonb_array_elements(rws) t), 0),
    'card_fees', coalesce((select sum((t ->> 'card_fees')::numeric) from jsonb_array_elements(rws) t), 0),
    'overheads_attributed', coalesce((select sum((t ->> 'overheads_attributed')::numeric) from jsonb_array_elements(rws) t), 0),
    'unallocated', un, 'uncosted_rev', unc);
  return jsonb_build_object('from', p_from, 'to', p_to, 'location_id', p_loc, 'mode', coalesce(public.rule_txt('profit_truth_mode'), 'off'),
    'company', co || jsonb_build_object('net_profit', round(np, 2), 'net_profit_if_uncosted_free', round(npf, 2)),
    'rows', rws, 'provisional', prov, 'incomplete', notes);
end $$;

-- ---------- 5. a stock transfer between two businesses is refused while the switch is ON ----------
create or replace function public._xfer_biz123() returns trigger
language plpgsql security definer set search_path = public as $$
declare bf bigint; bt bigint;
begin
  if public._org_on123() then
    bf := public._business_of_loc123(new.from_location_id); bt := public._business_of_loc123(new.to_location_id);
    if bf is null or bt is null or bf <> bt then raise exception 'cross_business_transfer'; end if;
  end if;
  return new;
end $$;
drop trigger if exists stock_transfers_biz123 on public.stock_transfers;
create trigger stock_transfers_biz123 before insert on public.stock_transfers for each row execute function public._xfer_biz123();

-- ---------- 6. restrictive read policies (AND-ed with the old ones; true while the switch is OFF) ----------
do $pol$
declare r record;
begin
  for r in select * from (values
      ('locations', 'id', 'select'), ('location_settings', 'location_id', 'select'), ('att_site_geo', 'location_id', 'select'), ('blind_count_cfg', 'location_id', 'select'),
      ('doc_template_choice', 'location_id', 'select'), ('form_rollout', 'location_id', 'select'), ('holidays', 'location_id', 'select'), ('path_switch', 'location_id', 'select'),
      ('report_brand_map', 'location_id', 'select'), ('sales_channels', 'location_id', 'select'), ('shifts', 'location_id', 'select'),
      ('invoice_templates', 'location_id', 'all'), ('print_profiles', 'location_id', 'all'),
      ('location_setup_steps', 'location_id', 'select'), ('paper_books', 'location_id', 'select'), ('print_notes', 'location_id', 'select'), ('settings_sheets', 'location_id', 'select'),
      ('budget_log', 'location_id', 'select'), ('payment_intents', 'location_id', 'select'), ('payroll_bonus_events', 'location_id', 'select')
    ) v(t, col, cmd)
  loop
    continue when to_regclass('public.' || r.t) is null;
    execute format('drop policy if exists %I on public.%I', r.t || '_scope123', r.t);
    execute format('create policy %I on public.%I as restrictive for %s to authenticated using (public._loc_vis123(%I)) %s',
      r.t || '_scope123', r.t, r.cmd, r.col, case when r.cmd = 'all' then format('with check (public._loc_vis123(%I))', r.col) else '' end);
  end loop;
end $pol$;
-- emergency requests: own rows always; others' rows only for the owner or when the place belongs to one of the caller's businesses (a request with no place: owner only)
drop policy if exists emergency_requests_scope123 on public.emergency_requests;
create policy emergency_requests_scope123 on public.emergency_requests as restrictive for select to authenticated
  using (not public._org_on123() or requested_by = auth.uid() or public.is_owner() or (location_id is not null and public._biz_ok123(location_id)));

-- deciding an emergency request: the approver must belong to the request's business (a role grant 'emergency_decide' is global); the answer is the same as for a missing id
create or replace function public.decide_emergency(p_id bigint, p_approve boolean, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.emergency_requests; sid text; mins numeric;
begin
  if not public.can_grant('emergency_decide') then raise exception 'not allowed'; end if;
  select * into r from public.emergency_requests where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if public._org_on123() and not public.is_owner() and (r.location_id is null or not public._biz_ok123(r.location_id)) then raise exception 'not found'; end if;   -- scope123
  if r.status <> 'pending' then raise exception 'already decided'; end if;
  if r.created_at < now() - interval '1 day' then update public.emergency_requests set status = 'expired' where id = p_id; return; end if;      -- a day-old request is stale: ask again
  if r.requested_by = auth.uid() and not (public.is_owner() and public.rule_on('owner_self_approve')) then raise exception 'own_request'; end if;
  if not p_approve and (p_note is null or length(btrim(p_note)) = 0) then raise exception 'note_required'; end if;
  mins := coalesce(public.rule_num('em_minutes'), 30);
  select staff_id into sid from public.profiles where id = auth.uid();
  update public.emergency_requests set status = case when p_approve then 'approved' else 'rejected' end, decided_by = auth.uid(), decided_staff = sid, decided_at = now(),
    decision_note = left(nullif(btrim(p_note), ''), 300), valid_until = case when p_approve then now() + make_interval(mins => mins::int) end where id = p_id;
end $$;

-- ---------- 7. managing the scope rows (owner) ----------
create or replace function public.org_scope_grant(p_user uuid, p_unit bigint, p_role text default 'management', p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u public.org_units; s public.user_org_scopes; nid bigint;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is null then raise exception 'client_id_needed'; end if;
  select * into s from public.user_org_scopes where client_id = p_client;
  if found then return jsonb_build_object('dup', true, 'id', s.id); end if;
  if p_user is null or not exists (select 1 from public.profiles where id = p_user) then raise exception 'bad_user'; end if;
  select * into u from public.org_units where id = p_unit;
  if not found then raise exception 'bad_unit'; end if;
  if u.kind = 'group' then raise exception 'group_scope_is_owner_only'; end if;
  if u.status = 'inactive' then raise exception 'unit_inactive'; end if;
  if p_role is null or p_role = 'owner' or not exists (select 1 from public.roles where code = p_role and active) then raise exception 'bad_role'; end if;
  if p_note is not null and length(p_note) > 300 then raise exception 'bad_note'; end if;
  select * into s from public.user_org_scopes where user_id = p_user and org_unit_id = p_unit and role_code = p_role and status = 'active';
  if found then return jsonb_build_object('dup', true, 'id', s.id); end if;
  insert into public.user_org_scopes (user_id, org_unit_id, role_code, note, client_id, granted_by) values (p_user, p_unit, p_role, p_note, p_client, auth.uid()) returning id into nid;
  return jsonb_build_object('dup', false, 'id', nid, 'live', exists (select 1 from public.user_roles ur where ur.user_id = p_user and ur.role_code = p_role));
end $$;

create or replace function public.org_scope_revoke(p_id bigint, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.user_org_scopes;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  if p_reason is not null and length(p_reason) > 300 then raise exception 'bad_reason'; end if;
  select * into s from public.user_org_scopes where id = p_id for update;
  if not found then raise exception 'scope_not_found'; end if;
  if s.status = 'revoked' then return jsonb_build_object('dup', true, 'id', s.id); end if;
  update public.user_org_scopes set status = 'revoked', revoked_by = auth.uid(), revoked_at = now(), revoked_reason = p_reason where id = p_id;
  return jsonb_build_object('dup', false, 'id', p_id);
end $$;

create or replace function public.org_scope_list(p_user uuid default null) returns table (id bigint, user_id uuid, staff_id text, full_name text, org_unit_id bigint, unit_code text, role_code text,
  status text, live boolean, note text, granted_at timestamptz, revoked_at timestamptz, revoked_reason text)
language plpgsql stable security definer set search_path = public as $$
declare mgr boolean := public.is_active() and (public.is_owner() or public.has_grant('org_manage'));
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return query
    select s.id, s.user_id, pr.staff_id, pr.full_name, s.org_unit_id, u.code, s.role_code, s.status,
           s.status = 'active' and exists (select 1 from public.user_roles ur where ur.user_id = s.user_id and ur.role_code = s.role_code),
           s.note, s.granted_at, s.revoked_at, s.revoked_reason
      from public.user_org_scopes s join public.profiles pr on pr.id = s.user_id join public.org_units u on u.id = s.org_unit_id
     where (mgr or s.user_id = auth.uid()) and (p_user is null or s.user_id = p_user)
     order by s.id;
end $$;

-- before switching the rule ON: what would change for people (owner only). Read-only.
create or replace function public.org_scope_preflight() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare t text; cfg jsonb := '{}'::jsonb; n bigint;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  foreach t in array array['location_settings', 'att_site_geo', 'blind_count_cfg', 'doc_template_choice', 'form_rollout', 'holidays', 'path_switch', 'report_brand_map', 'sales_channels', 'shifts',
                           'invoice_templates', 'print_profiles', 'location_setup_steps', 'paper_books', 'print_notes', 'settings_sheets'] loop
    if to_regclass('public.' || t) is not null then
      execute format('select count(*) from public.%I where location_id is null', t) into n;
      if n > 0 then cfg := cfg || jsonb_build_object(t, n); end if;
    end if;
  end loop;
  return jsonb_build_object(
    'switch_on', public._org_on123(),
    'businesses', (select count(*) from public.org_units where kind = 'business' and status <> 'inactive'),
    'unmapped_locations', coalesce((select jsonb_agg(l.code order by l.id) from public.locations l where l.org_unit_id is null), '[]'::jsonb),
    'locations_not_under_a_business', coalesce((select jsonb_agg(l.code order by l.id) from public.locations l where l.org_unit_id is not null and public._business_of_unit123(l.org_unit_id) is null), '[]'::jsonb),
    'management_users_without_scope', coalesce((select jsonb_agg(p.staff_id order by p.staff_id) from public.user_roles ur join public.profiles p on p.id = ur.user_id and p.status = 'active'
        where ur.role_code = 'management' and not exists (select 1 from public._scopes123(ur.user_id) sc where sc.role_code = 'management')), '[]'::jsonb),
    'active_users_with_no_business', coalesce((select jsonb_agg(p.staff_id order by p.staff_id) from public.profiles p
        where p.status = 'active' and not exists (select 1 from public.user_roles ur where ur.user_id = p.id and ur.role_code = 'owner')
          and not exists (select 1 from public._user_biz123(p.id))), '[]'::jsonb),
    'personal_grants_without_location', (select count(*) from public.user_grants where location_id is null and (valid_until is null or valid_until > now())),
    'config_rows_without_location', cfg);
end $$;

-- ---------- 8. first paste only: today's management users keep working in the sweets business when the switch is turned ON ----------
do $seed$
declare bz bigint; done_ boolean;
begin
  select id, coalesce((attrs -> 'seed123' ->> 'management_backfilled')::boolean, false) into bz, done_ from public.org_units where code = 'SWEETS';
  if bz is not null and not done_ then
    insert into public.user_org_scopes (user_id, org_unit_id, role_code, note)
      select ur.user_id, bz, 'management', 'phase123 backfill: existing management user = management of the sweets business'
        from public.user_roles ur join public.profiles p on p.id = ur.user_id
       where ur.role_code = 'management'
         and not exists (select 1 from public.user_org_scopes s where s.user_id = ur.user_id and s.org_unit_id = bz and s.role_code = 'management');
    update public.org_units set attrs = attrs || jsonb_build_object('seed123', jsonb_build_object('management_backfilled', true)) where id = bz;
  end if;
end $seed$;

-- ---------- 9. privileges ----------
revoke all on function public._org_anc123(bigint), public._business_of_unit123(bigint), public._scopes123(uuid), public._user_biz123(uuid), public._my_biz123(), public._business_of_loc123(int),
  public._mgmt_covers123(int), public._shares_biz123(uuid), public._item_cost_scoped123(), public._xfer_biz123() from public, anon, authenticated;
revoke all on function public._org_on123(), public._biz_ok123(int), public._loc_vis123(int) from public, anon;
grant execute on function public._org_on123(), public._biz_ok123(int), public._loc_vis123(int) to authenticated;                       -- used inside the policies
revoke all on function public.can_scope(bigint, text), public.business_of_location(int), public.org_scope_grant(uuid, bigint, text, text, uuid), public.org_scope_revoke(bigint, text),
  public.org_scope_list(uuid), public.org_scope_preflight() from public, anon;
grant execute on function public.can_scope(bigint, text), public.business_of_location(int), public.org_scope_grant(uuid, bigint, text, text, uuid), public.org_scope_revoke(bigint, text),
  public.org_scope_list(uuid), public.org_scope_preflight() to authenticated;

-- ---------- 10. advisor row for the switch (text only; the value stays the owner's) ----------
update public.setup_rec_defs81 set phase = '123',
  reason_bn = 'এখনই চালু করবেন না: আগে org_scope_preflight() দেখুন (কোন লোক/লোকেশন বাদ পড়বে) এবং নতুন ব্যবসার লোকেদের জন্য user_org_scopes দিন। বন্ধ থাকুক।',
  reason_mix = 'এখনই on করবেন না: আগে org_scope_preflight() দেখুন (কোন লোক/location বাদ পড়বে) এবং নতুন business-এর লোকেদের জন্য user_org_scopes দিন। off থাকুক।',
  reason_en = 'Do not switch on yet: first read org_scope_preflight() (which people / places would drop out) and give the staff of each new business a user_org_scopes row. Leave it off until then.'
 where code = 'org_scope_on' and phase = '122';

update public.rules set
  label_bn = 'ব্যবসা অনুযায়ী আলাদা ডেটা-সীমা (চালু করলে এক ব্যবসার লোক অন্য ব্যবসার ডেটা দেখবে না)',
  label_mix = 'Business অনুযায়ী আলাদা data-scope (on করলে এক business-এর লোক অন্য business-এর data দেখবে না)',
  label_en = 'Separate data scope per business (when on, staff of one business cannot see another business''s data)',
  hint_en = 'Off = everything works as before. On = management is limited to its own business, role/personal grants without a place stop at the business border, the listed reports and settings tables are filtered. Read org_scope_preflight() first. Owner sees all.'
 where key = 'org_scope_on' and hint_en like '%Does nothing yet%';

commit;
