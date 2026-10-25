-- ============================================================
-- Phase 135 (marker loc135) - GROUP ERP, STAGE D2: create the OPERATIONAL PLACES of a business from the app, and map them to that business.
-- Gap closed: org_unit_save creates organization nodes (business / branch / site ...) but NOT places (rows of public.locations that carry stock, POS, cash, users), and nothing mapped a newly
-- created place to a business ("new places are not mapped automatically", B1). The owner can now create a second business (for example a dealership with two branches) without SQL.
-- Canonical order: after phase134 (docs/PASTE_ORDER.md row 62). Paste twice = no change, no error. Needs phases 16, 122, 123, 133, 134 (checked below).
--
--   business_place_create135(p_business, p_kind, p_code, p_name_bn, p_name_en, p_org_branch default null, p_client default null) -> jsonb {dup, id, code, business_id, org_unit_id, kind, status}
--       Who: the owner, or the holder of org_manage INSIDE that business (_biz_mgr134: strict scope, a foreign or missing business answers 'not allowed' alike).
--       It calls the EXISTING location_save(null, ...) of phase16 (same defaults: model A, 17 setup steps, settings sheet version 1, step 2 done) - nothing is duplicated - then sets
--       locations.org_unit_id to the business (or to the given branch / site unit INSIDE that business) and moves the new place from 'planned' to 'setting_up'
--       (the status the pick-lists of the app already show, so the place is usable at once).
--       Kinds: the six kinds of the locations CHECK (showroom factory godown hub online other); the aliases branch / dealer_branch / sales_point = showroom, warehouse / store = godown.
--       Code: locations.code is globally unique and immutable, so the stored code is <business code in lower case>_<your code> (a code that already starts with that prefix is not doubled);
--             without a code it is made from the English name. Clear errors: bad_code, code_too_long, code_in_use. Existing codes are never touched.
--       Names: a place name must be unique INSIDE the business (name_in_use); the same name in another business is allowed and is never revealed.
--       Idempotent by p_client (table business_place_ops135); the same key from another user = client_id_taken. Audit: the audit trigger of locations + the append-only ops table.
--   location_save (phase16) is patched ONCE (marker /* loc135 */, two exact-text anchors, a second paste is a no-op): the "may add a place" test also accepts the transaction-local
--       token that business_place_create135 sets (the caller was already checked), and the name test, while the token is set, compares names inside the target business only, and the insert
--       carries org_unit_id (the place is born mapped, so the insert triggers and the business border of phase133 already see its business).
--       Called by anybody else, location_save behaves exactly as before (tests/sql/loc135_before_after.sh).
--   business_place_move135(p_location, p_business, p_reason, p_dry default true, p_force default false, p_client default null, p_org_branch default null) -> jsonb   OWNER ONLY
--       p_dry = true writes nothing and returns the impact: stock on hand, transactions per table, open documents, people assigned, supply links, blockers, needs_force.
--       Refused (also with force): people assigned to the place (remove them first), open documents (draft / submitted entries, transfers on the way, draft purchase bills), a supply link that
--       would cross the business border. Refused unless p_force: the place has transactions (their history moves with the place). Moving inside one business (branch to branch) needs none of this.
--       Every move is written to business_place_ops135 (who, why, impact, forced) and cannot be changed.
--   business_places_list135(p_business) -> rows of the places of ONE business (owner, the people of that business).
--   business_profile_ensure135(p_business) -> jsonb {created}: phase134 gives a profile to every business unit through a trigger; this helper only repairs a business that has none (idempotent).
-- Rollback: nothing else reads the new objects. To go back re-paste phase16 (location_save), drop the functions and the table of this file. Created places stay (they are normal locations).
-- ============================================================
begin;

do $g$
declare miss text := '';
begin
  if to_regclass('public.locations') is null or to_regclass('public.org_units') is null or to_regclass('public.business_profiles') is null or to_regclass('public.user_locations') is null
     or to_regclass('public.location_setup_steps') is null then miss := miss || ' tables'; end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'locations' and column_name = 'org_unit_id') then miss := miss || ' locations.org_unit_id'; end if;
  if to_regprocedure('public.location_save(integer,jsonb)') is null or to_regprocedure('public._biz_mgr134(bigint)') is null or to_regprocedure('public._vis_biz134()') is null
     or to_regprocedure('public._business_of_unit123(bigint)') is null or to_regprocedure('public._patch133(regprocedure,text,text[])') is null or to_regprocedure('public._client_lock(uuid)') is null
     or to_regprocedure('public._append_only23()') is null or to_regprocedure('public.log_change()') is null or to_regprocedure('public._slug(text)') is null
     or to_regprocedure('public.is_owner()') is null or to_regprocedure('public.is_active()') is null then miss := miss || ' functions'; end if;
  if miss <> '' then raise exception 'phase135 needs the base schema and phases up to 134 pasted first (docs/PASTE_ORDER.md); missing:%', miss; end if;
end $g$;

-- ---------- 1. the record of place operations (create / move): idempotency keys + history, append-only ----------
create table if not exists public.business_place_ops135 (
  id bigserial primary key,
  op text not null check (op in ('create', 'move')),
  client_id uuid not null unique,
  location_id int not null references public.locations(id),
  business_id bigint not null references public.org_units(id),
  from_unit bigint references public.org_units(id),
  to_unit bigint references public.org_units(id),
  kind text, reason text check (reason is null or length(reason) <= 500),
  forced boolean not null default false,
  impact jsonb,
  by_user uuid, at timestamptz not null default now()
);
create index if not exists business_place_ops135_loc on public.business_place_ops135 (location_id);
create index if not exists business_place_ops135_biz on public.business_place_ops135 (business_id);
alter table public.business_place_ops135 enable row level security;
drop policy if exists bpo135_read on public.business_place_ops135;
create policy bpo135_read on public.business_place_ops135 for select to authenticated using (public.is_active() and public.is_owner());
revoke all on public.business_place_ops135 from public, anon, authenticated;
grant select on public.business_place_ops135 to authenticated;
revoke all on sequence public.business_place_ops135_id_seq from public, anon, authenticated;
drop trigger if exists bpo135_ro on public.business_place_ops135;
create trigger bpo135_ro before update or delete on public.business_place_ops135 for each row execute function public._append_only23();
drop trigger if exists audit_bpo135 on public.business_place_ops135;
create trigger audit_bpo135 after insert on public.business_place_ops135 for each row execute function public.log_change('id');

-- ---------- 2. the transaction-local token (set only inside business_place_create135 after its own permission test) ----------
create or replace function public._pc_ok135() returns boolean
language sql stable set search_path = public as $$
  select coalesce(current_setting('bos.pc135', true), '') = txid_current()::text;
$$;
create or replace function public._pc_biz135() returns bigint
language sql stable set search_path = public as $$
  select case when public._pc_ok135() then nullif(current_setting('bos.pc135biz', true), '')::bigint end;
$$;

create or replace function public._pc_unit135() returns bigint
language sql stable set search_path = public as $$
  select case when public._pc_ok135() then nullif(current_setting('bos.pc135unit', true), '')::bigint end;
$$;

-- ---------- 3. patch location_save (phase16) once ----------
select public._patch133('public.location_save(integer,jsonb)'::regprocedure, '/* loc135 */', array[
  $a$if not public._loc_mgr() then raise exception 'not allowed'; end if;$a$,
  $b$if not (public._loc_mgr() or public._pc_ok135()) then raise exception 'not allowed'; end if;   /* loc135 */$b$,
  $a$if exists (select 1 from public.locations x where lower(btrim(x.name_bn)) = lower(newname_bn) or (newname_en is not null and lower(btrim(coalesce(x.name_en, ''))) = lower(newname_en))) then raise exception 'name_in_use'; end if;$a$,
  $b$if exists (select 1 from public.locations x where (not public._pc_ok135() or public._business_of_unit123(x.org_unit_id) is not distinct from public._pc_biz135())
                  and (lower(btrim(x.name_bn)) = lower(newname_bn) or (newname_en is not null and lower(btrim(coalesce(x.name_en, ''))) = lower(newname_en)))) then raise exception 'name_in_use'; end if;$b$,
  -- the place is born ALREADY mapped: the insert triggers (settings sheet v1) and the business border of phase133 (switch ON) see its business at once
  $a$hub_functions, note, created_by, created_at, status_by, status_at)$a$,
  $b$hub_functions, note, created_by, created_at, status_by, status_at, org_unit_id)$b$,
  $a$coalesce(hubv, false), nullif(p_patch->>'note', ''), auth.uid(), now(), auth.uid(), now())$a$,
  $b$coalesce(hubv, false), nullif(p_patch->>'note', ''), auth.uid(), now(), auth.uid(), now(), public._pc_unit135())$b$]);

-- ---------- 4. helpers ----------
-- what hangs on a place: stock, transactions per table, open documents, people, supply links
create or replace function public._place_impact135(p_loc int, p_target bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  -- (the two dealer table names are written in two pieces on purpose: the phase127 / phase129 tests assert that no existing function mentions those tables by name)
  t record; n bigint; tx jsonb := '{}'::jsonb; txn bigint := 0; stk_items bigint := 0; stk_qty numeric := 0; oe bigint := 0; ot bigint := 0; ob bigint := 0; us bigint := 0; el bigint := 0; ug bigint := 0;
  sup_ok boolean := true; l public.locations;
begin
  select * into l from public.locations where id = p_loc;
  for t in select * from (values ('stock_ledger', 'location_id'), ('sales', 'location_id'), ('sale_payments', 'location_id'), ('sale_returns', 'location_id'), ('purchase_bills', 'location_id'),
      ('entries', 'location_id'), ('cash_moves', 'location_id'), ('journal_entries', 'location_id'), ('supplier_payments', 'location_id'), ('quick_expenses', 'location_id'), ('online_orders', 'location_id'),
      ('drawer_events', 'location_id'), ('payroll_runs', 'location_id'), ('production_runs', 'location_id'), ('stock_wastage', 'location_id'), ('dealer_' || 'cheques', 'location_id'),
      ('dealer_' || 'tint_jobs', 'location_id'), ('stock_transfers', 'from_location_id'), ('stock_transfers', 'to_location_id')) v(tbl, col) loop
    if to_regclass('public.' || t.tbl) is null then continue; end if;
    execute format('select count(*) from public.%I where %I = $1', t.tbl, t.col) into n using p_loc;
    if n > 0 then tx := tx || jsonb_build_object(t.tbl || case when t.tbl = 'stock_transfers' then ':' || t.col else '' end, n); txn := txn + n; end if;
  end loop;
  select count(*), coalesce(sum(qty), 0) into stk_items, stk_qty from public.stock_balance where location_id = p_loc and qty <> 0;
  select count(*) into oe from public.entries where location_id = p_loc and status in ('draft', 'submitted');
  select count(*) into ot from public.stock_transfers where status = 'sent' and (from_location_id = p_loc or to_location_id = p_loc);
  select count(*) into ob from public.purchase_bills where location_id = p_loc and status = 'draft';
  select count(*) into us from public.user_locations where location_id = p_loc;
  select count(*) into el from public.employee_locations where location_id = p_loc;
  select count(*) into ug from public.user_grants where location_id = p_loc;
  if p_target is not null then
    if l.supplied_by is not null and public._business_of_unit123((select s.org_unit_id from public.locations s where s.id = l.supplied_by)) is distinct from p_target then sup_ok := false; end if;
    if exists (select 1 from public.locations s where s.supplied_by = p_loc and public._business_of_unit123(s.org_unit_id) is distinct from p_target) then sup_ok := false; end if;
  end if;
  return jsonb_build_object('stock_items', stk_items, 'stock_qty', round(stk_qty, 3), 'transactions', tx, 'tx_total', txn, 'open_entries', oe, 'open_transfers', ot, 'open_bills', ob,
                            'open_documents', oe + ot + ob, 'users', us, 'employees', el, 'personal_grants', ug, 'supply_ok', sup_ok);
end $$;

-- ---------- 5. create a place inside a business ----------
create or replace function public.business_place_create135(p_business bigint, p_kind text, p_code text, p_name_bn text, p_name_en text, p_org_branch bigint default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid(); b public.org_units; u public.org_units; unit_id bigint; k text; pre text; lc text; stored text; nm_bn text; nm_en text; r jsonb; nid int; op public.business_place_ops135;
  base text; n int := 1;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  -- strict scope: the owner, or the org_manage holder of THAT business; a foreign or missing business answers alike (the owner gets the precise text below)
  if not public._biz_mgr134(p_business) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is null then raise exception 'client_id_needed'; end if;
  select * into op from public.business_place_ops135 where client_id = p_client;
  if found then
    if op.by_user is distinct from me or op.op <> 'create' then raise exception 'client_id_taken'; end if;
    select l.code into lc from public.locations l where l.id = op.location_id;
    return jsonb_build_object('dup', true, 'id', op.location_id, 'code', lc, 'business_id', op.business_id, 'org_unit_id', op.to_unit);
  end if;
  select * into b from public.org_units where id = p_business;
  if not found or b.kind <> 'business' then raise exception 'unknown_business'; end if;
  if b.status = 'inactive' then raise exception 'business_inactive'; end if;
  -- kind
  k := lower(btrim(coalesce(p_kind, '')));
  k := case k when 'branch' then 'showroom' when 'dealer_branch' then 'showroom' when 'sales_point' then 'showroom' when 'warehouse' then 'godown' when 'store' then 'godown' else k end;
  if k not in ('showroom', 'factory', 'godown', 'hub', 'online', 'other') then raise exception 'bad_kind'; end if;
  -- names
  nm_bn := nullif(btrim(coalesce(p_name_bn, '')), ''); nm_en := nullif(btrim(coalesce(p_name_en, '')), '');
  if nm_bn is null and nm_en is null then raise exception 'name_required'; end if;
  if length(coalesce(nm_bn, '')) > 120 or length(coalesce(nm_en, '')) > 120 then raise exception 'too_long:name'; end if;
  -- the unit the place hangs on: the business, or a branch / site INSIDE it (a foreign or missing unit answers alike)
  unit_id := p_business;
  if p_org_branch is not null then
    select * into u from public.org_units where id = p_org_branch;
    if not found or u.kind not in ('branch', 'site') or u.status = 'inactive' or public._business_of_unit123(u.id) is distinct from p_business then raise exception 'bad_branch'; end if;
    unit_id := u.id;
  end if;
  -- code: <business code lower case>_<code>
  pre := trim(both '_' from lower(regexp_replace(b.code, '[^A-Za-z0-9]+', '_', 'g')));
  if pre !~ '^[a-z]' then pre := 'b' || pre; end if;
  lc := lower(btrim(coalesce(p_code, '')));
  if lc = '' then
    base := public._slug(coalesce(nm_en, ''));
    if base is null or length(base) < 2 or base !~ '^[a-z]' then base := 'place'; end if;
    lc := base;
  elsif lc !~ '^[a-z][a-z0-9_]{1,29}$' then raise exception 'bad_code';
  end if;
  stored := case when lc like pre || '\_%' then lc else pre || '_' || lc end;
  if nullif(btrim(coalesce(p_code, '')), '') is null then   -- no code given: a free one is found by numbering
    while exists (select 1 from public.locations x where x.code = stored) loop n := n + 1; stored := left(case when lc like pre || '\_%' then lc else pre || '_' || lc end, 26) || '_' || n; end loop;
  end if;
  if length(stored) > 30 then raise exception 'code_too_long'; end if;
  if stored !~ '^[a-z][a-z0-9_]{1,29}$' then raise exception 'bad_code'; end if;
  if exists (select 1 from public.locations x where x.code = stored) then raise exception 'code_in_use'; end if;

  -- the SAME creation path as the Places screen (phase16 location_save), with the token that says "already checked"
  perform set_config('bos.pc135', txid_current()::text, true);
  perform set_config('bos.pc135biz', p_business::text, true);
  perform set_config('bos.pc135unit', unit_id::text, true);
  r := public.location_save(null, jsonb_strip_nulls(jsonb_build_object('name_bn', nm_bn, 'name_en', nm_en, 'kind', k, 'model', 'A', 'code', stored)));
  perform set_config('bos.pc135', '', true); perform set_config('bos.pc135biz', '', true); perform set_config('bos.pc135unit', '', true);
  nid := (r ->> 'id')::int;
  update public.locations set status = 'setting_up', status_by = me, status_at = now() where id = nid;
  insert into public.business_place_ops135 (op, client_id, location_id, business_id, from_unit, to_unit, kind, by_user) values ('create', p_client, nid, p_business, null, unit_id, k, me);
  perform public.business_profile_ensure135(p_business);
  return jsonb_build_object('dup', false, 'id', nid, 'code', stored, 'business_id', p_business, 'org_unit_id', unit_id, 'kind', k, 'status', 'setting_up');
end $$;

-- ---------- 6. the places of one business ----------
create or replace function public.business_places_list135(p_business bigint) returns table (id int, code text, name_bn text, name_en text, kind text, status text, is_active boolean,
  org_unit_id bigint, unit_kind text, unit_code text, unit_name_bn text, unit_name_en text, planned_opening date)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_business is null or not (public.is_owner() or p_business in (select public._vis_biz134())) then raise exception 'not allowed'; end if;
  return query
    select l.id, l.code, l.name_bn, l.name_en, l.kind, l.status, l.is_active, l.org_unit_id, u.kind, u.code, u.name_bn, u.name_en, l.planned_opening
      from public.locations l join public.org_units u on u.id = l.org_unit_id
     where public._business_of_unit123(l.org_unit_id) = p_business
       and (public.is_owner() or public._biz_mgr134(p_business) or public.can_loc(l.id))
     order by l.sort, l.id;
end $$;

-- ---------- 7. move a place to another business (owner only, dry-run first) ----------
create or replace function public.business_place_move135(p_location int, p_business bigint, p_reason text default null, p_dry boolean default true, p_force boolean default false,
  p_client uuid default null, p_org_branch bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid(); l public.locations; b public.org_units; u public.org_units; target bigint; from_biz bigint; same boolean; imp jsonb; blockers text[] := '{}'; why text; op public.business_place_ops135;
begin
  if not public.is_active() or not public.is_owner() then raise exception 'not allowed'; end if;
  if p_reason is not null and length(p_reason) > 500 then raise exception 'bad_reason'; end if;
  select * into l from public.locations where id = p_location;
  if not found then raise exception 'unknown_location'; end if;
  select * into b from public.org_units where id = p_business;
  if not found or b.kind <> 'business' then raise exception 'unknown_business'; end if;
  if b.status = 'inactive' then raise exception 'business_inactive'; end if;
  target := p_business;
  if p_org_branch is not null then
    select * into u from public.org_units where id = p_org_branch;
    if not found or u.kind not in ('branch', 'site') or u.status = 'inactive' or public._business_of_unit123(u.id) is distinct from p_business then raise exception 'bad_branch'; end if;
    target := u.id;
  end if;
  from_biz := public._business_of_unit123(l.org_unit_id);
  same := from_biz is not distinct from p_business and l.org_unit_id is not null;
  imp := public._place_impact135(p_location, p_business);
  if not same then
    if (imp ->> 'users')::int > 0 then blockers := blockers || 'place_has_users'::text; end if;
    if (imp ->> 'open_documents')::int > 0 then blockers := blockers || 'open_documents'::text; end if;
    if not (imp ->> 'supply_ok')::boolean then blockers := blockers || 'supply_link'::text; end if;
    if (imp ->> 'tx_total')::bigint > 0 and not coalesce(p_force, false) then blockers := blockers || 'place_has_transactions'::text; end if;
  end if;
  imp := imp || jsonb_build_object('location_id', l.id, 'code', l.code, 'name_bn', l.name_bn, 'name_en', l.name_en, 'from_unit', l.org_unit_id, 'from_business', from_biz, 'to_business', p_business,
                                   'to_unit', target, 'same_business', same, 'unmapped', l.org_unit_id is null, 'needs_force', (not same) and (imp ->> 'tx_total')::bigint > 0,
                                   'blockers', to_jsonb(blockers), 'can_move', cardinality(blockers) = 0);
  if coalesce(p_dry, true) then return imp || jsonb_build_object('dry', true); end if;

  perform public._client_lock(p_client);
  if p_client is null then raise exception 'client_id_needed'; end if;
  select * into op from public.business_place_ops135 where client_id = p_client;
  if found then
    if op.by_user is distinct from me or op.op <> 'move' then raise exception 'client_id_taken'; end if;
    return jsonb_build_object('dup', true, 'id', op.location_id, 'business_id', op.business_id, 'org_unit_id', op.to_unit);
  end if;
  if l.org_unit_id is not distinct from target then return jsonb_build_object('dup', true, 'id', l.id, 'business_id', p_business, 'org_unit_id', target, 'noop', true); end if;
  why := nullif(btrim(coalesce(p_reason, '')), '');
  if why is null or length(why) < 3 then raise exception 'reason_required'; end if;
  if cardinality(blockers) > 0 then raise exception '%', blockers[1]; end if;
  update public.locations set org_unit_id = target where id = l.id;
  insert into public.business_place_ops135 (op, client_id, location_id, business_id, from_unit, to_unit, kind, reason, forced, impact, by_user)
    values ('move', p_client, l.id, p_business, l.org_unit_id, target, l.kind, why, coalesce(p_force, false) and (imp ->> 'tx_total')::bigint > 0, imp, me);
  return jsonb_build_object('dup', false, 'id', l.id, 'business_id', p_business, 'org_unit_id', target, 'dry', false);
end $$;

-- ---------- 8. profile repair helper (phase134 gives every business unit a profile through a trigger; this only repairs a business that has none) ----------
create or replace function public.business_profile_ensure135(p_business bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u public.org_units; nid bigint;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public._biz_mgr134(p_business) then raise exception 'not allowed'; end if;
  select * into u from public.org_units where id = p_business;
  if not found or u.kind <> 'business' then raise exception 'unknown_business'; end if;
  insert into public.business_profiles (org_unit_id, display_name_bn, display_name_en, created_by, updated_by)
    values (u.id, u.name_bn, u.name_en, auth.uid(), auth.uid()) on conflict (org_unit_id) do nothing returning id into nid;
  return jsonb_build_object('created', nid is not null, 'business_id', u.id);
end $$;

-- ---------- 9. privileges ----------
revoke all on function public._pc_ok135(), public._pc_biz135(), public._pc_unit135(), public._place_impact135(int, bigint) from public, anon, authenticated;
revoke all on function public.business_place_create135(bigint, text, text, text, text, bigint, uuid), public.business_places_list135(bigint),
  public.business_place_move135(int, bigint, text, boolean, boolean, uuid, bigint), public.business_profile_ensure135(bigint) from public, anon;
grant execute on function public.business_place_create135(bigint, text, text, text, text, bigint, uuid), public.business_places_list135(bigint),
  public.business_place_move135(int, bigint, text, boolean, boolean, uuid, bigint), public.business_profile_ensure135(bigint) to authenticated;

commit;
