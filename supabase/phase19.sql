-- Phase 19 (W6): recipes / BOM, packaging rule, production that consumes raw material.
--   Additive and idempotent (paste whole in the Supabase SQL editor; run twice is fine). Needs phase8..phase14 (stock ledger, items, item types). phase15..18 are not required.
--   * recipes (a version per finished good) + recipe_lines (ingredients: raw_material / packaging / resale items, qty, unit, waste % - empty waste = "Data needed")
--     A version that has been used by a production run is immutable (a change is a NEW version). Nothing is deleted: active flag. No cost columns anywhere.
--   * recipe_cost(recipe, loc): cost of one batch from the stock average cost - only for the owner / ITEM_COST / view_cost people.
--   * product_packaging (packaging per product, applies to sale or production) + setting packaging_consume_on (off | sale | production, default off).
--       sale       -> an AFTER INSERT trigger on sales (separate from the stock trigger, record_sale2 is NOT changed) takes the packaging out of the ledger
--                     with the SOFT mode (a sale is never blocked); if one packaging line cannot be posted the sale still goes through and the owner gets a yellow
--                     line `packaging_not_consumed`. A void gives the packaging back.
--       production -> production_post takes the packaging out in the same transaction as the ingredients.
--   * production_post(loc, recipe, batches, client, made_at, note): ONE transaction: ledger OUT per ingredient (qty x batches x (1 + waste%)) at the weighted average
--     cost, ledger IN of the finished good (yield x batches) with batch + expiry from shelf_life_for(), idempotent by client id, period lock, can_loc, grant
--     stock_production (+ its emergency rule em_stock_production), shortage refused (setting production_short_mode) with the full list of what is short.
--   * production_preview / production_can_make for the production sheet and the "what can I make now" view (no costs).
--   * settings: packaging_consume_on, production_requires_recipe (default OFF: the old stock_production_in works as before), production_short_mode,
--     recipe_waste_required (default OFF: an empty waste % is treated as 0 and the owner gets a yellow line). Grant recipe_manage (delegable).
--   The old stock_production_in is re-created with the same body plus one switch check (production_requires_recipe).

-- ---------- settings and grant ----------
insert into public.rules (key, module, kind, default_value, choices, min_value, max_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('packaging_consume_on', 'stock', 'choice', '"off"', '["off","sale","production"]', null, null,
  'প্যাকেজিং কখন স্টক থেকে কমবে: বন্ধ / বিক্রিতে / উৎপাদনে', 'Packaging কখন stock থেকে কমবে: off / sale / production', 'When packaging leaves the stock: off, with a sale, or with production',
  'Off = packaging is not taken out automatically. Uses the per-product packaging list. A sale is never blocked by packaging.', 190),
 ('production_requires_recipe', 'stock', 'switch', 'false', null, null, null,
  'উৎপাদন শুধু রেসিপি দিয়েই (পুরনো সরাসরি "উৎপাদিত মাল তোলা" বন্ধ)', 'Production শুধু recipe দিয়েই (পুরনো সরাসরি "Production in" বন্ধ)', 'Production only through a recipe (the old direct "Production in" is refused)',
  'Off = the direct production-in works as before. On = every production must use a recipe so the raw material is taken out.', 191),
 ('production_short_mode', 'stock', 'choice', '"refuse"', '["refuse","follow_stock_rule"]', null, null,
  'কাঁচামাল কম থাকলে: আটকানো / স্টকের সাধারণ নিয়ম', 'Raw material কম থাকলে: refuse / stock এর সাধারণ rule', 'When raw material is short: refuse, or follow the general stock rule',
  'refuse = the production is refused (unless stock_negative_mode is allow, or the person may sell below zero). follow_stock_rule = same as selling (warn / block / allow).', 192),
 ('recipe_waste_required', 'stock', 'switch', 'false', null, null, null,
  'রেসিপিতে অপচয় % না থাকলে উৎপাদন আটকানো', 'Recipe এ waste % না থাকলে production আটকানো', 'Refuse production when a recipe line has no waste %',
  'Off = an empty waste % counts as 0 and the owner gets a yellow line. The owner sets the real waste %; nothing is guessed.', 193)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('recipe_manage', 'master', 69, 'রেসিপি ও প্যাকেজিং নিয়ম তৈরি / বদল', 'Recipe ও packaging rule তৈরি / বদল', 'Create and change recipes and packaging rules', 'window', null)
on conflict (grant_code) do nothing;

-- ---------- tables ----------
create table if not exists public.recipes (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items(id),
  version int not null check (version >= 1),
  yield_qty numeric not null check (yield_qty > 0 and yield_qty < 1000000000),
  yield_unit text,                                           -- null = the item base unit
  active boolean not null default true,
  note text,
  used_at timestamptz,                                       -- first production run: from then on the version is frozen
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(),
  unique (item_id, version)
);
create index if not exists recipes_item on public.recipes (item_id, active);
create table if not exists public.recipe_lines (
  id bigserial primary key,
  recipe_id uuid not null references public.recipes(id),
  ingredient_item_id uuid not null references public.items(id),
  qty numeric not null check (qty > 0 and qty < 1000000000),
  unit text,                                                 -- null = the ingredient base unit
  waste_pct numeric check (waste_pct is null or (waste_pct >= 0 and waste_pct <= 100)),     -- null = Data needed
  note text,
  sort int not null default 0,
  unique (recipe_id, ingredient_item_id)
);
alter table public.recipe_lines add column if not exists active boolean not null default true;
alter table public.recipe_lines drop constraint if exists recipe_lines_recipe_id_ingredient_item_id_key;
create unique index if not exists recipe_lines_one_active on public.recipe_lines (recipe_id, ingredient_item_id) where active;
create table if not exists public.product_packaging (
  id bigserial primary key,
  product_item_id uuid not null references public.items(id),
  packaging_item_id uuid not null references public.items(id),
  qty_per_unit numeric not null check (qty_per_unit > 0 and qty_per_unit < 1000000),     -- packaging base units per ONE base unit of the product
  applies_to text not null default 'sale' check (applies_to in ('sale', 'production')),
  active boolean not null default true,
  note text,
  updated_by uuid, updated_at timestamptz not null default now(),
  unique (product_item_id, packaging_item_id, applies_to)
);
create table if not exists public.production_runs (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  location_id int not null references public.locations(id),
  recipe_id uuid not null references public.recipes(id),
  item_id uuid not null references public.items(id),
  batches numeric not null check (batches > 0),
  made_at timestamptz not null,
  yield_base numeric not null,
  ledger_in_id bigint, batch_id bigint,
  waste_missing int not null default 0,
  cost_complete boolean,
  note text,
  created_by uuid, created_at timestamptz not null default now()
);
create index if not exists production_runs_loc on public.production_runs (location_id, made_at);

-- ---------- helpers ----------
create or replace function public._recipe_mgr() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('recipe_manage'));
$$;
create or replace function public._recipe_read() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('recipe_manage') or public.has_grant('stock_production') or public.has_grant('stock_issue')
    or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code in ('recipe_manage', 'stock_production', 'stock_issue') and (g.valid_until is null or g.valid_until > now())));
$$;
create or replace function public._recipe_cost_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.can_do('ITEM_COST', 'view') or public.has_grant('view_cost')
    or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = 'view_cost' and (g.valid_until is null or g.valid_until > now())));
$$;

-- immutability: lines and the yield of a used version never change; a used version is never removed
create or replace function public._recipe_frozen() returns trigger language plpgsql security definer set search_path = public as $$
declare rid uuid; used timestamptz;
begin
  if tg_table_name = 'recipes' then
    if tg_op = 'DELETE' then
      if old.used_at is not null then raise exception 'recipe_used'; end if;
      raise exception 'no_delete';
    end if;
    if tg_op = 'UPDATE' and old.used_at is not null and (new.item_id is distinct from old.item_id or new.version is distinct from old.version
        or new.yield_qty is distinct from old.yield_qty or new.yield_unit is distinct from old.yield_unit) then raise exception 'recipe_used'; end if;
    return new;
  end if;
  rid := case when tg_op = 'DELETE' then old.recipe_id else new.recipe_id end;
  select used_at into used from public.recipes where id = rid;
  if used is not null then raise exception 'recipe_used'; end if;
  if tg_op = 'DELETE' then raise exception 'no_delete'; end if;
  if tg_op = 'UPDATE' and new.recipe_id is distinct from old.recipe_id then raise exception 'recipe_used'; end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;
drop trigger if exists recipes_frozen on public.recipes;
create trigger recipes_frozen before update or delete on public.recipes for each row execute function public._recipe_frozen();
drop trigger if exists recipe_lines_frozen on public.recipe_lines;
create trigger recipe_lines_frozen before insert or update or delete on public.recipe_lines for each row execute function public._recipe_frozen();

drop trigger if exists audit_recipes on public.recipes;
create trigger audit_recipes after insert or update on public.recipes for each row execute function public.log_change('id');
drop trigger if exists audit_recipe_lines on public.recipe_lines;
create trigger audit_recipe_lines after insert or update or delete on public.recipe_lines for each row execute function public.log_change('id');
drop trigger if exists audit_product_packaging on public.product_packaging;
create trigger audit_product_packaging after insert or update on public.product_packaging for each row execute function public.log_change('id');
drop trigger if exists audit_production_runs on public.production_runs;
create trigger audit_production_runs after insert on public.production_runs for each row execute function public.log_change('id');

-- ---------- RLS ----------
alter table public.recipes enable row level security;
alter table public.recipe_lines enable row level security;
alter table public.product_packaging enable row level security;
alter table public.production_runs enable row level security;
drop policy if exists recipes_read on public.recipes;
create policy recipes_read on public.recipes for select to authenticated using (public._recipe_read());
drop policy if exists recipe_lines_read on public.recipe_lines;
create policy recipe_lines_read on public.recipe_lines for select to authenticated using (public._recipe_read());
drop policy if exists product_packaging_read on public.product_packaging;
create policy product_packaging_read on public.product_packaging for select to authenticated using (public._recipe_read());
drop policy if exists production_runs_read on public.production_runs;
create policy production_runs_read on public.production_runs for select to authenticated using (public._recipe_read() and public.can_loc(location_id));
revoke all on public.recipes, public.recipe_lines, public.product_packaging, public.production_runs from anon, authenticated;
grant select on public.recipes, public.recipe_lines, public.product_packaging, public.production_runs to authenticated;
revoke all on sequence public.recipe_lines_id_seq, public.product_packaging_id_seq from anon, authenticated;

-- ---------- recipe writes ----------
create or replace function public._recipe_lines_ok(p_item uuid, p_lines jsonb) returns void language plpgsql security definer set search_path = public as $$
declare ln jsonb; ing public.items; q numeric; w numeric; seen uuid[] := '{}'; iid uuid;
begin
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'no_lines'; end if;
  if jsonb_array_length(p_lines) > 100 then raise exception 'too_many_lines'; end if;
  for ln in select x from jsonb_array_elements(p_lines) x loop
    iid := nullif(ln->>'ingredient_item_id', '')::uuid;
    select * into ing from public.items where id = iid;
    if not found then raise exception 'item_not_found'; end if;
    if iid = p_item then raise exception 'ingredient_is_product'; end if;
    if ing.item_type not in ('raw_material', 'packaging', 'resale') then raise exception 'bad_ingredient_type' using detail = ing.code; end if;
    if iid = any(seen) then raise exception 'dup_ingredient'; end if;
    seen := seen || iid;
    q := nullif(ln->>'qty', '')::numeric;
    if q is null or not (q > 0 and q < 1000000000) then raise exception 'bad_qty'; end if;
    w := nullif(ln->>'waste_pct', '')::numeric;
    if w is not null and not (w between 0 and 100) then raise exception 'bad_waste'; end if;
    if public._base_qty(iid, q, nullif(btrim(ln->>'unit'), '')) is null then raise exception 'unit_unknown' using detail = ing.code; end if;
  end loop;
end $$;

create or replace function public._recipe_put_lines(p_recipe uuid, p_lines jsonb) returns void language plpgsql security definer set search_path = public as $$
declare ln jsonb; n int := 0;
begin
  for ln in select x from jsonb_array_elements(p_lines) x loop
    n := n + 1;
    insert into public.recipe_lines (recipe_id, ingredient_item_id, qty, unit, waste_pct, note, sort)
      values (p_recipe, (ln->>'ingredient_item_id')::uuid, (ln->>'qty')::numeric, nullif(btrim(ln->>'unit'), ''), nullif(ln->>'waste_pct', '')::numeric, left(nullif(btrim(ln->>'note'), ''), 200), n);
  end loop;
end $$;

-- create a new version (p_id null) or edit a version that has never been used. p_lines = [{ingredient_item_id, qty, unit, waste_pct, note}]
create or replace function public.recipe_save(p_id uuid, p_item uuid, p_yield_qty numeric, p_yield_unit text, p_note text, p_lines jsonb, p_client uuid default null, p_retire_old boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it public.items; r public.recipes; v int; rid uuid; yu text := nullif(btrim(p_yield_unit), '');
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_yield_qty is null or not (p_yield_qty > 0 and p_yield_qty < 1000000000) then raise exception 'bad_qty'; end if;
  if p_id is not null then
    select * into r from public.recipes where id = p_id for update;
    if not found then raise exception 'recipe_not_found'; end if;
    if r.used_at is not null then raise exception 'recipe_used'; end if;
    it := (select i from public.items i where i.id = r.item_id);
  else
    if p_client is not null then
      select * into r from public.recipes where client_id = p_client;
      if found then
        if r.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
        return jsonb_build_object('dup', true, 'id', r.id, 'version', r.version);
      end if;
    end if;
    select * into it from public.items where id = p_item;
    if not found then raise exception 'item_not_found'; end if;
  end if;
  if it.item_type is distinct from 'finished_good' then raise exception 'bad_product_type'; end if;
  if public._base_qty(it.id, p_yield_qty, yu) is null then raise exception 'unit_unknown' using detail = it.code; end if;
  perform public._recipe_lines_ok(it.id, p_lines);
  if p_id is null then
    select coalesce(max(version), 0) + 1 into v from public.recipes where item_id = it.id;
    insert into public.recipes (item_id, version, yield_qty, yield_unit, active, note, client_id, created_by)
      values (it.id, v, p_yield_qty, yu, true, left(p_note, 300), p_client, auth.uid()) returning id into rid;
    if p_retire_old then update public.recipes set active = false where item_id = it.id and id <> rid and active; end if;
  else
    rid := p_id; v := r.version;
    update public.recipes set yield_qty = p_yield_qty, yield_unit = yu, note = left(p_note, 300) where id = rid;
    update public.recipe_lines set active = false where recipe_id = rid and active;      -- a draft only (never used): old lines are retired, never deleted; the trigger refuses this for a used version
  end if;
  perform public._recipe_put_lines(rid, p_lines);
  return jsonb_build_object('id', rid, 'version', v);
end $$;

-- copy a version: same item = next version (optionally retiring the source); another item = version 1 of that item
create or replace function public.recipe_copy(p_from uuid, p_item uuid default null, p_retire_old boolean default false, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.recipes; tgt public.items; v int; rid uuid; dup public.recipes;
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  select * into s from public.recipes where id = p_from;
  if not found then raise exception 'recipe_not_found'; end if;
  if p_client is not null then
    select * into dup from public.recipes where client_id = p_client;
    if found then
      if dup.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', dup.id, 'version', dup.version);
    end if;
  end if;
  select * into tgt from public.items where id = coalesce(p_item, s.item_id);
  if not found then raise exception 'item_not_found'; end if;
  if tgt.item_type is distinct from 'finished_good' then raise exception 'bad_product_type'; end if;
  if exists (select 1 from public.recipe_lines where recipe_id = p_from and active and ingredient_item_id = tgt.id) then raise exception 'ingredient_is_product'; end if;
  select coalesce(max(version), 0) + 1 into v from public.recipes where item_id = tgt.id;
  insert into public.recipes (item_id, version, yield_qty, yield_unit, active, note, client_id, created_by)
    values (tgt.id, v, s.yield_qty, case when tgt.id = s.item_id then s.yield_unit else null end, true, s.note, p_client, auth.uid()) returning id into rid;
  insert into public.recipe_lines (recipe_id, ingredient_item_id, qty, unit, waste_pct, note, sort)
    select rid, ingredient_item_id, qty, unit, waste_pct, note, sort from public.recipe_lines where recipe_id = p_from and active;
  if tgt.id <> s.item_id and public._base_qty(tgt.id, s.yield_qty, null) is null then raise exception 'unit_unknown'; end if;
  if p_retire_old and tgt.id = s.item_id then update public.recipes set active = false where id = p_from; end if;
  return jsonb_build_object('id', rid, 'version', v);
end $$;

create or replace function public.recipe_set_active(p_id uuid, p_active boolean) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  if p_active is null then raise exception 'bad_value'; end if;
  update public.recipes set active = p_active where id = p_id;
  if not found then raise exception 'recipe_not_found'; end if;
end $$;

-- packaging per product (one row per product x packaging x sale|production); inactive instead of delete
create or replace function public.packaging_set(p_product uuid, p_packaging uuid, p_qty numeric, p_applies text default 'sale', p_active boolean default true, p_note text default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare pr public.items; pk public.items; rid bigint;
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  if p_applies not in ('sale', 'production') then raise exception 'bad_value'; end if;
  if p_qty is null or not (p_qty > 0 and p_qty < 1000000) then raise exception 'bad_qty'; end if;
  select * into pr from public.items where id = p_product;
  select * into pk from public.items where id = p_packaging;
  if pr.id is null or pk.id is null then raise exception 'item_not_found'; end if;
  if pk.item_type is distinct from 'packaging' then raise exception 'bad_ingredient_type' using detail = pk.code; end if;
  if pr.item_type not in ('finished_good', 'resale') then raise exception 'bad_product_type'; end if;
  insert into public.product_packaging (product_item_id, packaging_item_id, qty_per_unit, applies_to, active, note, updated_by, updated_at)
    values (p_product, p_packaging, p_qty, p_applies, coalesce(p_active, true), left(p_note, 200), auth.uid(), now())
    on conflict (product_item_id, packaging_item_id, applies_to) do update
      set qty_per_unit = excluded.qty_per_unit, active = excluded.active, note = excluded.note, updated_by = auth.uid(), updated_at = now()
    returning id into rid;
  return rid;
end $$;

-- ---------- the consumption maths (internal; used by preview, can-make and post) ----------
-- one row per thing that leaves the stock for p_batches batches: the ingredients, plus the production-time packaging when the setting says so
create or replace function public._recipe_need(p_recipe uuid, p_batches numeric, p_loc int)
returns table (item_id uuid, kind text, need numeric, on_hand numeric, tracked boolean, unit_ok boolean, waste_missing boolean, code text, name_bn text, name_en text, base_unit text)
language plpgsql stable security definer set search_path = public as $$
declare r public.recipes; yb numeric;
begin
  select * into r from public.recipes where id = p_recipe;
  if not found then return; end if;
  yb := coalesce(public._base_qty(r.item_id, r.yield_qty, r.yield_unit), 0) * p_batches;
  return query
    select z.item_id, min(z.kind), sum(z.need), max(z.on_hand), bool_and(z.tracked), bool_and(z.unit_ok), bool_or(z.waste_missing), z.code, z.name_bn, z.name_en, z.base_unit
    from (
      select i.id as item_id, 'ingredient'::text as kind,
             round(public._base_qty(i.id, l.qty, l.unit) * p_batches * (1 + coalesce(l.waste_pct, 0) / 100), 4) as need,
             coalesce(b.qty, 0) as on_hand, i.tracked, public._base_qty(i.id, l.qty, l.unit) is not null as unit_ok, l.waste_pct is null as waste_missing,
             i.code, i.name_bn, i.name_en, public._item_base(i.id) as base_unit
        from public.recipe_lines l join public.items i on i.id = l.ingredient_item_id
        left join public.stock_balance b on b.item_id = i.id and b.location_id = p_loc
       where l.recipe_id = p_recipe and l.active
      union all
      select i.id, 'packaging'::text, round(pp.qty_per_unit * yb, 4), coalesce(b.qty, 0), i.tracked, true, false, i.code, i.name_bn, i.name_en, public._item_base(i.id)
        from public.product_packaging pp join public.items i on i.id = pp.packaging_item_id
        left join public.stock_balance b on b.item_id = i.id and b.location_id = p_loc
       where coalesce(public.rule_txt('packaging_consume_on'), 'off') = 'production' and pp.product_item_id = r.item_id and pp.active and pp.applies_to = 'production') z
    group by z.item_id, z.code, z.name_bn, z.name_en, z.base_unit;
end $$;

-- preview for the production sheet: what will be used, what is on hand, what is short. No costs.
create or replace function public.production_preview(p_loc int, p_recipe uuid, p_batches numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.recipes; it public.items; yb numeric; ls jsonb; sh jsonb; wm int;
begin
  if not public._recipe_read() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if p_batches is null or not (p_batches between 0.0001 and 100000) then raise exception 'bad_qty'; end if;
  select * into r from public.recipes where id = p_recipe;
  if not found then raise exception 'recipe_not_found'; end if;
  select * into it from public.items where id = r.item_id;
  yb := round(public._base_qty(r.item_id, r.yield_qty, r.yield_unit) * p_batches, 4);
  select coalesce(jsonb_agg(jsonb_build_object('item_id', n.item_id, 'kind', n.kind, 'code', n.code, 'name_bn', n.name_bn, 'name_en', n.name_en, 'need', n.need, 'on_hand', n.on_hand,
           'short', greatest(n.need - n.on_hand, 0), 'unit', n.base_unit, 'tracked', n.tracked, 'unit_ok', n.unit_ok, 'waste_missing', n.waste_missing) order by n.kind, n.code), '[]'::jsonb),
         coalesce(jsonb_agg(n.item_id) filter (where n.need > n.on_hand), '[]'::jsonb), count(*) filter (where n.waste_missing)
    into ls, sh, wm from public._recipe_need(p_recipe, p_batches, p_loc) n;
  return jsonb_build_object('recipe_id', r.id, 'item_id', r.item_id, 'version', r.version, 'active', r.active, 'batches', p_batches, 'yield_base', yb, 'yield_unit', public._item_base(r.item_id),
    'lines', ls, 'short_items', sh, 'waste_missing', wm,
    'can_make', (jsonb_array_length(sh) = 0 and not exists (select 1 from jsonb_array_elements(ls) x where (x->>'tracked')::boolean is not true or (x->>'unit_ok')::boolean is not true)),
    'tracked', it.tracked);
end $$;

-- "what can I make now" at one location: for every active recipe (newest active version per product) how many batches the stock allows
create or replace function public.production_can_make(p_loc int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.recipes; out jsonb := '[]'::jsonb; mx numeric; lim uuid; unk boolean; n record; per numeric; it public.items;
begin
  if not public._recipe_read() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  for r in select distinct on (item_id) * from public.recipes where active order by item_id, version desc loop
    select * into it from public.items where id = r.item_id;
    if not it.is_active then continue; end if;
    mx := null; lim := null; unk := not it.tracked;
    for n in select * from public._recipe_need(r.id, 1, p_loc) loop
      if not n.tracked or not n.unit_ok or n.need <= 0 then unk := true; continue; end if;
      per := n.on_hand / n.need;
      if mx is null or per < mx then mx := per; lim := n.item_id; end if;
    end loop;
    out := out || jsonb_build_object('recipe_id', r.id, 'item_id', r.item_id, 'version', r.version, 'code', it.code, 'name_bn', it.name_bn, 'name_en', it.name_en,
      'max_batches', case when mx is null then null else greatest(floor(mx * 10000) / 10000, 0) end, 'limiting_item_id', lim, 'unknown', unk,
      'yield_per_batch', public._base_qty(r.item_id, r.yield_qty, r.yield_unit), 'yield_unit', public._item_base(r.item_id));
  end loop;
  return out;
end $$;

-- cost of one batch from the average cost in stock (owner / ITEM_COST / view_cost only; unknown cost = null = Data needed)
create or replace function public.recipe_cost(p_recipe uuid, p_loc int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.recipes; ls jsonb := '[]'::jsonb; total numeric := 0; complete boolean := true; l record; need numeric; av numeric; yb numeric;
begin
  if p_loc is not null then
    if not (public._cost_ok(p_loc) and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;      -- same rule as the stock cost columns
  elsif not public._recipe_cost_ok() then raise exception 'not allowed'; end if;
  select * into r from public.recipes where id = p_recipe;
  if not found then raise exception 'recipe_not_found'; end if;
  for l in select x.*, i.code, i.name_bn, i.name_en from public.recipe_lines x join public.items i on i.id = x.ingredient_item_id where x.recipe_id = p_recipe and x.active order by x.sort, x.id loop
    need := round(public._base_qty(l.ingredient_item_id, l.qty, l.unit) * (1 + coalesce(l.waste_pct, 0) / 100), 4);
    if p_loc is not null then
      select avg_cost into av from public.stock_balance where item_id = l.ingredient_item_id and location_id = p_loc;
    else
      select sum(qty * avg_cost) / nullif(sum(qty), 0) into av from public.stock_balance
        where item_id = l.ingredient_item_id and qty > 0 and avg_cost is not null and (public._all_locs() or public.can_loc(location_id)) and public._cost_ok(location_id);
    end if;
    if av is null then complete := false; else total := total + need * av; end if;
    ls := ls || jsonb_build_object('ingredient_item_id', l.ingredient_item_id, 'code', l.code, 'need_base', need, 'unit_cost', av, 'line_cost', case when av is null then null else round(need * av, 4) end,
      'waste_missing', l.waste_pct is null);
  end loop;
  yb := public._base_qty(r.item_id, r.yield_qty, r.yield_unit);
  return jsonb_build_object('recipe_id', p_recipe, 'lines', ls, 'complete', complete, 'batch_cost', case when complete then round(total, 4) end,
    'unit_cost', case when complete and yb > 0 then round(total / yb, 6) end, 'yield_base', yb);
end $$;

-- ---------- production ----------
create or replace function public.production_post(p_loc int, p_recipe uuid, p_batches numeric, p_client uuid default null, p_made_at timestamptz default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.recipes; it public.items; at_ timestamptz := coalesce(p_made_at, now()); run public.production_runs; n record; rid uuid := gen_random_uuid();
        mode text; neg text; yb numeric; f numeric; sl jsonb; exp timestamptz; bid bigint; lin bigint; lid bigint; tot numeric := 0; cost_ok boolean := true; av numeric; wm int := 0;
        shorts text := ''; used jsonb := '[]'::jsonb; ucb numeric; derived uuid;
begin
  if at_ is null or at_ = 'infinity'::timestamptz or at_ = '-infinity'::timestamptz then raise exception 'bad_date'; end if;
  select * into r from public.recipes where id = p_recipe;
  if not found then raise exception 'recipe_not_found'; end if;
  it := public._stock_guard(r.item_id, p_loc, 'stock_production', (at_ at time zone 'Asia/Dhaka')::date);
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into run from public.production_runs where client_id = p_client;
    if found then
      if run.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'run_id', run.id, 'ledger_id', run.ledger_in_id, 'batch_id', run.batch_id, 'qty', run.yield_base);
    end if;
  end if;
  if not r.active then raise exception 'recipe_inactive'; end if;
  if p_batches is null or not (p_batches between 0.0001 and 100000) then raise exception 'bad_qty'; end if;
  if at_ > now() + interval '10 minutes' then raise exception 'bad_date'; end if;
  if not exists (select 1 from public.recipe_lines where recipe_id = r.id and active) then raise exception 'no_lines'; end if;
  f := public._base_qty(r.item_id, r.yield_qty, r.yield_unit);
  if f is null or not (f > 0) then raise exception 'unit_unknown'; end if;
  yb := round(f * p_batches, 4);
  if not (yb between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  -- everything that leaves the stock: checks first, nothing is posted until all are fine
  for n in select * from public._recipe_need(r.id, p_batches, p_loc) loop
    if not n.tracked then raise exception 'ingredient_not_tracked' using detail = coalesce(n.code, ''); end if;
    if not n.unit_ok then raise exception 'unit_unknown' using detail = coalesce(n.code, ''); end if;
    if n.waste_missing then wm := wm + 1; end if;
  end loop;
  if wm > 0 and public.rule_on('recipe_waste_required') then raise exception 'waste_needed'; end if;
  mode := coalesce(public.rule_txt('production_short_mode'), 'refuse');
  if mode = 'refuse' and coalesce(public.rule_txt('stock_negative_mode'), 'warn') <> 'allow' and not public.has_grant('sell_below_zero', p_loc) then
    for n in select * from public._recipe_need(r.id, p_batches, p_loc) where need > on_hand order by code loop
      shorts := shorts || case when shorts = '' then '' else '; ' end || coalesce(n.code, '') || ' ' || coalesce(n.name_bn, '') || ' (' || round(n.on_hand, 4)::text || ' / ' || n.need::text || ')';
    end loop;
    if shorts <> '' then raise exception 'insufficient_stock' using detail = shorts, hint = 'production'; end if;
  end if;
  if not public._may('stock_production', p_loc, 'production:' || r.item_id::text, yb) then raise exception 'not allowed'; end if;
  insert into public.production_runs (id, client_id, location_id, recipe_id, item_id, batches, made_at, yield_base, waste_missing, note, created_by)
    values (rid, p_client, p_loc, r.id, r.item_id, p_batches, at_, yb, wm, left(p_note, 200), auth.uid());
  -- ingredient (and packaging) OUT at the weighted average cost, fixed item order so two productions can never wait on each other in a circle
  for n in select * from public._recipe_need(r.id, p_batches, p_loc) order by item_id loop
    if n.need < 0.0001 then continue; end if;
    select avg_cost into av from public.stock_balance where item_id = n.item_id and location_id = p_loc;
    if av is null then cost_ok := false; else tot := tot + n.need * av; end if;
    derived := md5(coalesce(p_client::text, rid::text) || ':' || n.item_id::text)::uuid;
    lin := public.stock_post(n.item_id, p_loc, -n.need, 'issue_out', 'production', rid::text, null, null, at_, left(p_note, 200), null, 'full', null, derived);
    used := used || jsonb_build_object('item_id', n.item_id, 'kind', n.kind, 'qty', n.need);
  end loop;
  -- finished good IN: batch + expiry from the owner's shelf-life rules (no rule = no expiry); the cost is the ingredient cost when every ingredient has a known cost
  sl := public.shelf_life_for(r.item_id, (at_ at time zone 'Asia/Dhaka')::date);
  exp := case when sl is null then null else at_ + ((sl->>'hours')::float8 * interval '1 hour') end;
  insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by)
    values (r.item_id, p_loc, at_, yb, yb, exp, sl, left(p_note, 200), auth.uid()) returning id into bid;
  ucb := case when cost_ok and yb > 0 then round(tot / yb, 6) end;
  derived := md5(coalesce(p_client::text, rid::text) || ':in')::uuid;
  lid := public.stock_post(r.item_id, p_loc, yb, 'production_in', 'production', rid::text, ucb, bid, at_, left(p_note, 200), null, 'none', null, derived);
  update public.production_runs set ledger_in_id = lid, batch_id = bid, cost_complete = cost_ok where id = rid;
  update public.recipes set used_at = coalesce(used_at, now()) where id = r.id;
  if wm > 0 then
    perform public._stock_exc(p_loc, 'recipe_waste_missing', 'yellow', it.name_bn || ': রেসিপিতে অপচয় % বসানো নেই — ০ ধরা হয়েছে (' || wm::text || ' লাইন)',
      coalesce(it.name_en, it.name_bn) || ': the recipe has no waste % on ' || wm::text || ' line(s) — counted as 0', null, (at_ at time zone 'Asia/Dhaka')::date, 'STOCK');
  end if;
  return jsonb_build_object('run_id', rid, 'ledger_id', lid, 'batch_id', bid, 'qty', yb, 'expires_at', exp, 'consumed', used, 'waste_missing', wm) || case when public._cost_ok(p_loc) then jsonb_build_object('cost_complete', cost_ok) else '{}'::jsonb end;
end $$;

-- the old direct "production in": identical to phase10 except the new switch (production_requires_recipe)
create or replace function public.stock_production_in(p_item uuid, p_loc int, p_qty numeric, p_made_at timestamptz default null, p_unit text default null,
  p_note text default null, p_client uuid default null, p_unit_cost numeric default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it public.items; bq numeric; lid bigint; at_ timestamptz := coalesce(p_made_at, now()); sl jsonb; exp timestamptz; bid bigint; f numeric; ucb numeric; pct numeric; av numeric;
begin
  if at_ is null or at_ = 'infinity'::timestamptz or at_ = '-infinity'::timestamptz then raise exception 'bad_date'; end if;
  it := public._stock_guard(p_item, p_loc, 'stock_production', (at_ at time zone 'Asia/Dhaka')::date);
  perform public._client_lock(p_client);
  if p_client is not null then select id, batch_id into lid, bid from public.stock_ledger where client_id = p_client and reason = 'production_in' order by id limit 1; if found then return jsonb_build_object('dup', true, 'ledger_id', lid, 'batch_id', bid); end if; end if;
  if public.rule_on('production_requires_recipe') then raise exception 'recipe_required'; end if;
  if p_qty is null or not (p_qty between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  if at_ > now() + interval '10 minutes' then raise exception 'bad_date'; end if;
  if p_unit_cost is not null and not (p_unit_cost between 0 and 999999999) then raise exception 'bad_cost'; end if;
  if p_unit_cost is not null and not public._cost_ok(p_loc) then raise exception 'not allowed'; end if;      -- cost is secret: only who may see it may write it
  bq := public._base_qty(p_item, p_qty, p_unit);
  if bq is null then raise exception 'unit_unknown'; end if;
  if not public._may('stock_production', p_loc, 'production:' || p_item::text, bq) then raise exception 'not allowed'; end if;
  f := public._unit_factor_base(p_item, p_unit);
  if f is null or not (f > 0) then raise exception 'unit_unknown'; end if;
  pct := public.rule_num('purchase_cost_jump_pct');
  if p_unit_cost is not null and pct is not null then
    ucb := p_unit_cost / f;
    select avg_cost into av from public.stock_balance where item_id = p_item and location_id = p_loc;
    if av is not null and av > 0 and abs(ucb - av) / av * 100 > pct then
      perform public._stock_exc(p_loc, 'production_cost_jump', 'yellow',
        it.name_bn || ': উৎপাদন খরচ গড় খরচের চেয়ে ' || round((ucb - av) / av * 100, 1)::text || '% বদলেছে',
        coalesce(it.name_en, it.name_bn) || ': production cost moved ' || round((ucb - av) / av * 100, 1)::text || '% from the average cost in stock', null, (at_ at time zone 'Asia/Dhaka')::date, 'STOCK');
    end if;
  end if;
  sl := public.shelf_life_for(p_item, (at_ at time zone 'Asia/Dhaka')::date);
  exp := case when sl is null then null else at_ + ((sl->>'hours')::float8 * interval '1 hour') end;
  insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by)
    values (p_item, p_loc, at_, bq, bq, exp, sl, left(p_note, 200), auth.uid()) returning id into bid;
  lid := public.stock_post(p_item, p_loc, bq, 'production_in', 'production', bid::text, case when p_unit_cost is null then null else p_unit_cost / f end, bid, at_, left(p_note, 200), null, 'none', null, p_client);
  return jsonb_build_object('ledger_id', lid, 'batch_id', bid, 'qty', bq, 'expires_at', exp);
end $$;

-- ---------- packaging with a sale (separate trigger; the stock trigger and record_sale2 are untouched) ----------
create or replace function public._sale_packaging_out() returns trigger language plpgsql security definer set search_path = public as $$
declare pk record; bad boolean := false;
begin
  if new.status <> 'done' or new.lines is null or jsonb_typeof(new.lines) <> 'array' then return new; end if;
  if coalesce(public.rule_txt('packaging_consume_on'), 'off') <> 'sale' then return new; end if;
  begin
    for pk in
      select pp.packaging_item_id as item_id, sum(public._base_qty(li.iid, li.q, li.u) * pp.qty_per_unit) as qty, count(*) filter (where public._base_qty(li.iid, li.q, li.u) is null) as unk,
             i.code, i.name_bn, i.name_en
        from (select (x->>'item_id')::uuid as iid, nullif(x->>'qty', '')::numeric as q, x->>'unit' as u from jsonb_array_elements(new.lines) x where nullif(x->>'item_id', '') is not null) li
        join public.product_packaging pp on pp.product_item_id = li.iid and pp.active and pp.applies_to = 'sale'
        join public.items i on i.id = pp.packaging_item_id
       where li.q > 0 and li.q <= 999999999
       group by pp.packaging_item_id, i.code, i.name_bn, i.name_en order by pp.packaging_item_id loop
      if pk.unk > 0 then bad := true; end if;
      begin
        if pk.qty is null or round(pk.qty, 4) < 0.0001 then continue; end if;
        perform public.stock_post(pk.item_id, new.location_id, -round(pk.qty, 4), 'issue_out', 'sale_pack', new.id::text, null, null, new.sold_at, null, null, 'soft', new.id);
      exception when others then
        bad := true;
        perform public._stock_exc(new.location_id, 'packaging_not_consumed', 'yellow', 'রসিদ ' || new.receipt || ': ' || coalesce(pk.name_bn, '') || ' — প্যাকেজিং স্টক থেকে কমানো যায়নি',
          'Receipt ' || new.receipt || ': ' || coalesce(pk.name_en, pk.name_bn, '') || ' — the packaging could not be taken out of the stock', new.id, new.sale_date, 'POS');
      end;
    end loop;
  exception when others then
    bad := true;
  end;
  if bad then
    perform public._stock_exc(new.location_id, 'packaging_not_consumed', 'yellow', 'রসিদ ' || new.receipt || ': প্যাকেজিং পুরোটা কমানো যায়নি', 'Receipt ' || new.receipt || ': the packaging could not be fully taken out of the stock', new.id, new.sale_date, 'POS');
  end if;
  return new;
end $$;
drop trigger if exists sales_packaging_out on public.sales;
create trigger sales_packaging_out after insert on public.sales for each row execute function public._sale_packaging_out();

create or replace function public._sale_packaging_void() returns trigger language plpgsql security definer set search_path = public as $$
declare r public.stock_ledger;
begin
  for r in select * from public.stock_ledger o where o.ref_type = 'sale_pack' and o.ref_id = new.id::text and o.reason = 'issue_out'
           and not exists (select 1 from public.stock_ledger v where v.reverses_id = o.id) order by o.item_id, o.id loop
    perform public.stock_post(r.item_id, r.location_id, -r.qty_delta, 'sale_void_in', 'sale_pack', new.id::text, r.unit_cost, r.batch_id, now(), null, r.id, 'none', new.id);
  end loop;
  return new;
end $$;
drop trigger if exists sales_packaging_void on public.sales;
create trigger sales_packaging_void after update of status on public.sales for each row
  when (old.status is distinct from 'void' and new.status = 'void') execute function public._sale_packaging_void();

-- ---------- privileges ----------
revoke all on function public._recipe_mgr(), public._recipe_read(), public._recipe_cost_ok(), public._recipe_frozen(), public._recipe_lines_ok(uuid, jsonb), public._recipe_put_lines(uuid, jsonb),
  public._recipe_need(uuid, numeric, int), public._sale_packaging_out(), public._sale_packaging_void() from public, anon, authenticated;
revoke all on function public.recipe_save(uuid, uuid, numeric, text, text, jsonb, uuid, boolean), public.recipe_copy(uuid, uuid, boolean, uuid), public.recipe_set_active(uuid, boolean),
  public.packaging_set(uuid, uuid, numeric, text, boolean, text), public.production_preview(int, uuid, numeric), public.production_can_make(int), public.recipe_cost(uuid, int),
  public.production_post(int, uuid, numeric, uuid, timestamptz, text) from public, anon;
grant execute on function public.recipe_save(uuid, uuid, numeric, text, text, jsonb, uuid, boolean), public.recipe_copy(uuid, uuid, boolean, uuid), public.recipe_set_active(uuid, boolean),
  public.packaging_set(uuid, uuid, numeric, text, boolean, text), public.production_preview(int, uuid, numeric), public.production_can_make(int), public.recipe_cost(uuid, int),
  public.production_post(int, uuid, numeric, uuid, timestamptz, text) to authenticated;
revoke all on function public.stock_production_in(uuid, int, numeric, timestamptz, text, text, uuid, numeric) from public, anon;
grant execute on function public.stock_production_in(uuid, int, numeric, timestamptz, text, text, uuid, numeric) to authenticated;
-- the read policies call this helper as the signed-in person
grant execute on function public._recipe_read() to authenticated;
-- cost_complete is a cost fact: not readable by people who may not see costs
revoke select on public.production_runs from authenticated;
grant select (id, client_id, location_id, recipe_id, item_id, batches, made_at, yield_base, ledger_in_id, batch_id, waste_missing, note, created_by, created_at) on public.production_runs to authenticated;
