-- ============================================================
-- Phase 74 (bos74) - STEP C: costing and overhead (conversion cost into product cost).
--   Needs phase8 ... phase71 + phase73. Additive; paste-twice safe. Old phases are NOT edited.
--   Cost structure the code follows:
--     layer 1 raw material      = weighted-average cost (existing) + "আজকের কেনা দাম" (latest purchase_in cost) shown in a SEPARATE row, never booked (C5)
--     layer 2 conversion cost   = labour, gas/fuel, electricity, factory rent, licence & fees, machine repair, depreciation, other (+ owner-added types). GOES INTO product cost (C1-C3)
--     layer 3 showroom + admin  = NOT in product cost; it goes to the branch P&L (nothing here touches it)
--   Product cost = material cost + conversion rate x quantity.
--   Two ways to get the conversion rate, chosen PER LOCATION (location_cost_cfg.mode): off (default = today's behaviour) | recipe | pool.
--     recipe : rates typed on the recipe (recipe_cost_components: per batch / per base unit / per labour-hour). A blank amount = "রূপান্তর খরচ অসম্পূর্ণ".
--     pool   : monthly pool of actual factory cost per component type (factory_cost_pools) / NORMAL monthly output of the location (not actual output).
--              Smoothing (settings on the type, cost_type_smoothing): none = that month, yearly12 = a yearly amount / 12 per month, avg_n = the N months ending at the run month (repair 12, gas and electricity 3)
--              divided by the months since the first entry (capped at N); months with no entry are counted as gaps, never filled by a guess.
--   Changes marked bos74: production_post (new 7-argument core with p_actual_yield; the 6-argument signature stays as a thin wrapper; conversion cost; run snapshot columns), recipe_cost (same _recipe_need as the run; raw / packaging /
--   conversion rows; today-price row), stock_production_in (reason + yellow flag for a typed cost), _acct_docs (production journal: Dr 1310 / Cr 1320 + 1330 + overhead_absorbed).
--   !! A parallel change (phase72, Part 1 step B) also re-creates production_post / recipe_cost / _p27_pl: the lead MUST re-merge those functions (see docs/briefs_p2p3/step_C_REPORT.md).
-- ============================================================

-- ---------- settings ----------
insert into public.rules (key, module, kind, default_value, choices, min_value, max_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('cost_gap_warn_pct', 'stock', 'number', null, null, 0, 1000,
  '"আজকের কেনা দাম" ও গড় দামের ফারাক % — এর বেশি হলে হলুদ সতর্কতা', '"আজকের কেনা দাম" vs গড় দামের gap % — এর বেশি হলে yellow', 'Yellow warning when today''s purchase price differs from the average cost by more than this %',
  'Blank = no warning. It is a display warning only; it never changes a booked cost.', 730),
 ('yield_variance_warn_pct', 'stock', 'number', null, null, 0, 1000,
  'আসল উৎপাদন রেসিপির ফলন থেকে এর বেশি % আলাদা হলে হলুদ সতর্কতা', 'Actual yield recipe yield থেকে এর বেশি % আলাদা হলে yellow', 'Yellow warning when the actual yield differs from the recipe yield by more than this %',
  'Blank = no warning.', 731),
 ('production_manual_needs_reason', 'stock', 'switch', 'false', null, null, null,
  'সরাসরি "উৎপাদিত মাল তোলা"-য় কারণ (নোট) বাধ্যতামূলক', 'Direct "Production in"-এ reason (note) বাধ্যতামূলক', 'The direct production-in needs a reason note',
  'Off (default) = as today. On = a note of at least 3 characters is required while production_requires_recipe is off. Recommended: switch production_requires_recipe ON instead.', 732)
on conflict (key) do nothing;

-- ---------- types of conversion cost (owner may add types) ----------
create table if not exists public.cost_component_types (
  code text primary key check (code ~ '^[a-z0-9_]{2,40}$'),
  label_bn text not null check (length(btrim(label_bn)) between 1 and 80),
  label_en text,
  builtin boolean not null default false,
  smooth text not null default 'none' check (smooth in ('none', 'yearly12', 'avg_n')),     -- how the pool figure of a month is made
  avg_months int check (avg_months is null or avg_months between 1 and 36),                  -- the window for avg_n (a setting)
  active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now()
);
insert into public.cost_component_types (code, label_bn, label_en, builtin, smooth, avg_months) values
 ('labour', 'শ্রম / মজুরি', 'Labour', true, 'none', null),
 ('gas', 'গ্যাস / জ্বালানি', 'Gas / fuel', true, 'avg_n', 3),
 ('electricity', 'বিদ্যুৎ', 'Electricity', true, 'avg_n', 3),
 ('factory_rent', 'কারখানার ভাড়া', 'Factory rent', true, 'none', null),
 ('licence_fee', 'লাইসেন্স ও ফি', 'Licence and fees', true, 'yearly12', null),
 ('machine_repair', 'যন্ত্র মেরামত', 'Machine repair', true, 'avg_n', 12),
 ('depreciation', 'অবচয়', 'Depreciation', true, 'none', null),
 ('other', '☐ অন্য: ______', 'Other: ______', true, 'none', null)
on conflict (code) do nothing;
create sequence if not exists public.cost_type_seq;

-- ---------- C1: conversion cost rates on a recipe (amounts may be blank) ----------
create table if not exists public.recipe_cost_components (
  id bigserial primary key,
  recipe_id uuid not null references public.recipes(id),
  component_type text not null references public.cost_component_types(code),
  type_note text,                                                      -- for "other": what it is (typed)
  basis text not null check (basis in ('per_batch', 'per_unit', 'per_labour_hour')),   -- per batch / per base unit (kg) of output / per labour-hour
  amount numeric check (amount is null or (amount >= 0 and amount <= 1000000000)),    -- BLANK = "রূপান্তর খরচ অসম্পূর্ণ"
  hours_per_batch numeric check (hours_per_batch is null or (hours_per_batch >= 0 and hours_per_batch <= 100000)),   -- typed by hand for per_labour_hour (the step suggestion never flows in by itself)
  note text,
  active boolean not null default true,                                -- a change retires the row and inserts a new one: previous values are kept
  set_by uuid, set_at timestamptz not null default now(),
  client_id uuid unique
);
create unique index if not exists rcc_one_active on public.recipe_cost_components (recipe_id, component_type, coalesce(type_note, '')) where active;

-- ---------- C2: monthly pools of ACTUAL factory cost + the per-location choice ----------
create table if not exists public.factory_cost_pools (
  id bigserial primary key,
  location_id int not null references public.locations(id),
  month date not null check (month = date_trunc('month', month)::date),
  component_type text not null references public.cost_component_types(code),
  period_kind text not null default 'month' check (period_kind in ('month', 'year')),   -- a 'year' amount (licence) starts at its month and is spread /12 over 12 months
  actual_amount numeric not null check (actual_amount >= 0 and actual_amount <= 1000000000000),
  one_off boolean not null default false,                              -- a large irregular repair: flagged "একবারের খরচ"
  source text not null default 'manual' check (source in ('manual', 'allocated')),    -- allocated = pushed by a cost source bill (phase75)
  ref text,                                                            -- source bill id for allocated rows
  note text,
  active boolean not null default true,
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now()
);
create unique index if not exists fcp_one_active on public.factory_cost_pools (location_id, month, component_type, period_kind, source, coalesce(ref, '')) where active;
create index if not exists fcp_loc_month on public.factory_cost_pools (location_id, month) where active;

create table if not exists public.location_cost_cfg (
  location_id int primary key references public.locations(id),
  mode text not null default 'off' check (mode in ('off', 'recipe', 'pool')),
  normal_monthly_output numeric check (normal_monthly_output is null or (normal_monthly_output > 0 and normal_monthly_output <= 1000000000)),   -- base units (kg) per month; BLANK until the owner sets it
  updated_by uuid, updated_at timestamptz not null default now()
);

-- ---------- production_runs: the cost snapshot of a run (visible only through production_run_costs; the browser column grant of phase19 does not include them) ----------
alter table public.production_runs add column if not exists material_cost numeric;
alter table public.production_runs add column if not exists conversion_cost numeric;
alter table public.production_runs add column if not exists unit_cost numeric;          -- booked per base unit (material + conversion) / output booked
alter table public.production_runs add column if not exists std_cost numeric;           -- (material + conversion) / the recipe's standard yield
alter table public.production_runs add column if not exists actual_cost numeric;        -- (material + conversion) / the actual output
alter table public.production_runs add column if not exists conversion_mode text;
alter table public.production_runs add column if not exists conversion_complete boolean;
alter table public.production_runs add column if not exists conversion_detail jsonb;
alter table public.production_runs add column if not exists yield_std numeric;
alter table public.production_runs add column if not exists yield_actual numeric;
alter table public.production_runs add column if not exists yield_var_pct numeric;

-- triggers / RLS
drop trigger if exists cost_types_no_delete on public.cost_component_types;
create trigger cost_types_no_delete before delete on public.cost_component_types for each row execute function public.no_hard_delete();
drop trigger if exists rcc_no_delete on public.recipe_cost_components;
create trigger rcc_no_delete before delete on public.recipe_cost_components for each row execute function public.no_hard_delete();
drop trigger if exists fcp_no_delete on public.factory_cost_pools;
create trigger fcp_no_delete before delete on public.factory_cost_pools for each row execute function public.no_hard_delete();
drop trigger if exists lcc_no_delete on public.location_cost_cfg;
create trigger lcc_no_delete before delete on public.location_cost_cfg for each row execute function public.no_hard_delete();
drop trigger if exists audit_cost_types on public.cost_component_types;
create trigger audit_cost_types after insert or update on public.cost_component_types for each row execute function public.log_change('code');
drop trigger if exists audit_rcc on public.recipe_cost_components;
create trigger audit_rcc after insert or update on public.recipe_cost_components for each row execute function public.log_change('id');
drop trigger if exists audit_fcp on public.factory_cost_pools;
create trigger audit_fcp after insert or update on public.factory_cost_pools for each row execute function public.log_change('id');
drop trigger if exists audit_lcc on public.location_cost_cfg;
create trigger audit_lcc after insert or update on public.location_cost_cfg for each row execute function public.log_change('location_id');

alter table public.cost_component_types enable row level security;
alter table public.recipe_cost_components enable row level security;
alter table public.factory_cost_pools enable row level security;
alter table public.location_cost_cfg enable row level security;
drop policy if exists cost_types_read on public.cost_component_types;
create policy cost_types_read on public.cost_component_types for select to authenticated using (public.is_active());
drop policy if exists rcc_read on public.recipe_cost_components;
create policy rcc_read on public.recipe_cost_components for select to authenticated using (public._recipe_cost_ok());
drop policy if exists fcp_read on public.factory_cost_pools;
create policy fcp_read on public.factory_cost_pools for select to authenticated using (public._recipe_cost_ok() and public.can_loc(location_id));
drop policy if exists lcc_read on public.location_cost_cfg;
create policy lcc_read on public.location_cost_cfg for select to authenticated using (public._recipe_cost_ok() and public.can_loc(location_id));
revoke all on public.cost_component_types, public.recipe_cost_components, public.factory_cost_pools, public.location_cost_cfg from anon, authenticated;
grant select on public.cost_component_types, public.recipe_cost_components, public.factory_cost_pools, public.location_cost_cfg to authenticated;
revoke all on sequence public.recipe_cost_components_id_seq, public.factory_cost_pools_id_seq, public.cost_type_seq from anon, authenticated;

-- ---------- helpers ----------
-- the first day of the month of a date in Dhaka
create or replace function public._m1(p_date date) returns date language sql immutable as $$ select date_trunc('month', p_date)::date $$;

-- ACTUAL cost of a type in a month: month rows + year rows / 12 that cover the month. null = nothing entered (never 0 by guess).
create or replace function public._pool_month_actual(p_loc int, p_month date, p_type text) returns numeric
language sql stable security definer set search_path = public as $$
  select case when count(*) = 0 then null else coalesce(sum(case when period_kind = 'month' then actual_amount else actual_amount / 12 end), 0) end
    from public.factory_cost_pools
   where active and location_id = p_loc and component_type = p_type
     and ((period_kind = 'month' and month = p_month) or (period_kind = 'year' and p_month >= month and p_month < (month + interval '12 months')::date));
$$;

-- the figure used for the RATE of a month, after the type's smoothing. avg_n = sum of the N months ending at the run month / the months of that window since the first
-- entry (so a young book is not understated); months with no entry inside the span are counted as gaps ("বিল বাকি") and are NOT filled by a guess.
-- returns {amount, span, gaps}; amount null = nothing entered at all.
create or replace function public._pool_rate(p_loc int, p_month date, p_type text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare t public.cost_component_types; s numeric := 0; i int; v numeric; first_m date; span int; gaps int := 0; k int;
begin
  select * into t from public.cost_component_types where code = p_type;
  if not found then return jsonb_build_object('amount', null, 'span', 0, 'gaps', 0); end if;
  if t.smooth <> 'avg_n' or t.avg_months is null then
    v := public._pool_month_actual(p_loc, p_month, p_type);
    return jsonb_build_object('amount', v, 'span', case when v is null then 0 else 1 end, 'gaps', 0);
  end if;
  select min(month) into first_m from public.factory_cost_pools where active and location_id = p_loc and component_type = p_type and month <= p_month;
  if first_m is null then return jsonb_build_object('amount', null, 'span', 0, 'gaps', 0); end if;
  k := (extract(year from age(p_month, first_m)) * 12 + extract(month from age(p_month, first_m)))::int + 1;       -- months from the first entry to the run month, inclusive
  span := least(t.avg_months, k);
  for i in 0 .. span - 1 loop
    v := public._pool_month_actual(p_loc, (p_month - make_interval(months => i))::date, p_type);
    if v is null then gaps := gaps + 1; else s := s + v; end if;
  end loop;
  return jsonb_build_object('amount', s / span, 'span', span, 'gaps', gaps);
end $$;
create or replace function public._pool_rate_amount(p_loc int, p_month date, p_type text) returns numeric
language sql stable security definer set search_path = public as $$ select (public._pool_rate(p_loc, p_month, p_type) ->> 'amount')::numeric $$;

-- the conversion cost of ONE production (or of one batch for the preview): jsonb {mode, amount, complete, detail[], reason}
-- p_force_mode lets recipe_cost show the recipe rate when no location is given. Never guesses: a blank amount / blank normal output = complete false.
create or replace function public._conv_cost(p_recipe uuid, p_loc int, p_batches numeric, p_out numeric, p_date date, p_force_mode text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare md text; c record; ty record; det jsonb := '[]'::jsonb; tot numeric := 0; complete boolean := true; amt numeric; norm numeric; m date := public._m1(p_date); any_pool boolean := false; ncomp int := 0; why text := null; a numeric; pr jsonb;
begin
  md := coalesce(p_force_mode, (select mode from public.location_cost_cfg where location_id = p_loc), 'off');
  if md = 'off' then return jsonb_build_object('mode', 'off', 'amount', 0, 'complete', true, 'detail', '[]'::jsonb, 'reason', null); end if;
  if md = 'recipe' then
    for c in select * from public.recipe_cost_components where recipe_id = p_recipe and active order by component_type, id loop
      ncomp := ncomp + 1; amt := null;
      if c.amount is null then complete := false;
      elsif c.basis = 'per_batch' then amt := c.amount * p_batches;
      elsif c.basis = 'per_unit' then amt := c.amount * p_out;
      elsif c.hours_per_batch is null then complete := false;
      else amt := c.amount * c.hours_per_batch * p_batches; end if;
      if amt is not null then tot := tot + amt; end if;
      det := det || jsonb_build_object('type', c.component_type, 'note', c.type_note, 'basis', c.basis, 'amount', case when amt is null then null else round(amt, 6) end, 'incomplete', amt is null);
    end loop;
    if ncomp = 0 then complete := false; why := 'no_components'; end if;
  else
    select normal_monthly_output into norm from public.location_cost_cfg where location_id = p_loc;
    if lower(coalesce((select public._item_base(r.item_id) from public.recipes r where r.id = p_recipe), '')) <> 'kg' then complete := false; why := 'pool_unit_not_kg';      -- the pool rate is per kg of output: a piece-based product needs recipe rates
    elsif norm is null or norm <= 0 then complete := false; why := 'normal_output_blank';
    else
      for ty in select code from public.cost_component_types where active order by code loop
        pr := public._pool_rate(p_loc, m, ty.code); a := (pr ->> 'amount')::numeric;
        if a is not null then any_pool := true; amt := a / norm * p_out; tot := tot + amt;
          det := det || jsonb_build_object('type', ty.code, 'basis', 'pool', 'rate', round(a / norm, 8), 'amount', round(amt, 6), 'incomplete', false, 'months', pr -> 'span', 'gap_months', pr -> 'gaps'); end if;
      end loop;
      if not any_pool then complete := false; why := 'no_pool'; end if;
    end if;
  end if;
  return jsonb_build_object('mode', md, 'amount', tot, 'complete', complete, 'detail', det, 'reason', why);
end $$;

-- the latest booked purchase price of an item (a purchase_in row that has not been reversed); optional place
create or replace function public._today_cost(p_item uuid, p_loc int) returns numeric
language sql stable security definer set search_path = public as $$
  select l.unit_cost from public.stock_ledger l
   where l.item_id = p_item and l.reason = 'purchase_in' and l.unit_cost is not null and (p_loc is null or l.location_id = p_loc)
     and not exists (select 1 from public.stock_ledger v where v.reverses_id = l.id)
     and (p_loc is not null or ((public._all_locs() or public.can_loc(l.location_id)) and public._cost_ok(l.location_id)))
   order by l.made_at desc, l.id desc limit 1;
$$;

-- ---------- C1 writes ----------
create or replace function public.cost_type_add(p_label_bn text, p_label_en text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c text;
begin
  if not public._recipe_cost_ok() then raise exception 'not allowed'; end if;
  if p_label_bn is null or length(btrim(p_label_bn)) < 1 or length(btrim(p_label_bn)) > 80 then raise exception 'name_needed'; end if;
  c := 'x' || nextval('public.cost_type_seq')::text;
  insert into public.cost_component_types (code, label_bn, label_en, builtin, created_by) values (c, btrim(p_label_bn), left(nullif(btrim(p_label_en), ''), 80), false, auth.uid());
  return jsonb_build_object('code', c);
end $$;
create or replace function public.cost_type_smoothing(p_code text, p_smooth text, p_months int default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public._recipe_cost_ok() then raise exception 'not allowed'; end if;
  if p_smooth not in ('none', 'yearly12', 'avg_n') then raise exception 'bad_value'; end if;
  if p_smooth = 'avg_n' and (p_months is null or p_months not between 1 and 36) then raise exception 'bad_value'; end if;
  update public.cost_component_types set smooth = p_smooth, avg_months = case when p_smooth = 'avg_n' then p_months end where code = p_code;
  if not found then raise exception 'unknown_type'; end if;
end $$;

-- set / change one conversion rate of a recipe. The old row is retired (kept), a new active one is inserted: previous values stay. Cost-right holders only.
create or replace function public.recipe_cost_component_set(p_recipe uuid, p_type text, p_basis text, p_amount numeric, p_hours numeric default null, p_type_note text default null, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d public.recipe_cost_components; nid bigint; tn text := nullif(btrim(p_type_note), '');
begin
  if not public._recipe_cost_ok() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then select * into d from public.recipe_cost_components where client_id = p_client; if found then return jsonb_build_object('dup', true, 'id', d.id); end if; end if;
  if not exists (select 1 from public.recipes where id = p_recipe) then raise exception 'recipe_not_found'; end if;
  if not exists (select 1 from public.cost_component_types where code = p_type and active) then raise exception 'unknown_type'; end if;
  if p_type = 'other' and tn is null then raise exception 'type_note_needed'; end if;
  if p_basis not in ('per_batch', 'per_unit', 'per_labour_hour') then raise exception 'bad_value'; end if;
  if p_amount is not null and not (p_amount >= 0 and p_amount <= 1000000000) then raise exception 'bad_cost'; end if;
  if p_hours is not null and not (p_hours >= 0 and p_hours <= 100000) then raise exception 'bad_qty'; end if;
  update public.recipe_cost_components set active = false where recipe_id = p_recipe and component_type = p_type and coalesce(type_note, '') = coalesce(tn, '') and active;
  insert into public.recipe_cost_components (recipe_id, component_type, type_note, basis, amount, hours_per_batch, note, set_by, client_id)
    values (p_recipe, p_type, case when p_type = 'other' then left(tn, 80) end, p_basis, p_amount, case when p_basis = 'per_labour_hour' then p_hours end, left(p_note, 200), auth.uid(), p_client) returning id into nid;
  return jsonb_build_object('id', nid, 'incomplete', p_amount is null or (p_basis = 'per_labour_hour' and p_hours is null));
end $$;
create or replace function public.recipe_cost_component_retire(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public._recipe_cost_ok() then raise exception 'not allowed'; end if;
  update public.recipe_cost_components set active = false where id = p_id and active;
  if not found then raise exception 'not_found'; end if;
end $$;

-- the components of a recipe with the flag "রূপান্তর খরচ অসম্পূর্ণ" (cost-right holders only)
create or replace function public.recipe_cost_components_get(p_recipe uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows_ jsonb; inc boolean;
begin
  if not public._recipe_cost_ok() then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'type', c.component_type, 'type_note', c.type_note, 'label_bn', t.label_bn, 'label_en', t.label_en, 'basis', c.basis, 'amount', c.amount, 'hours_per_batch', c.hours_per_batch, 'note', c.note,
    'incomplete', c.amount is null or (c.basis = 'per_labour_hour' and c.hours_per_batch is null)) order by t.code, c.id), '[]'::jsonb) into rows_
    from public.recipe_cost_components c join public.cost_component_types t on t.code = c.component_type where c.recipe_id = p_recipe and c.active;
  inc := jsonb_array_length(rows_) = 0 or exists (select 1 from jsonb_array_elements(rows_) x where (x->>'incomplete')::boolean);
  return jsonb_build_object('recipe_id', p_recipe, 'components', rows_, 'incomplete', inc, 'flag', case when inc then 'রূপান্তর খরচ অসম্পূর্ণ' end,
    'suggested_labour_hours', public.recipe_labour_suggest(p_recipe)->'suggested_labour_hours');
end $$;

-- ---------- C2 writes ----------
create or replace function public.pool_set(p_loc int, p_month date, p_type text, p_amount numeric, p_period_kind text default 'month', p_one_off boolean default false, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d public.factory_cost_pools; nid bigint; m date := public._m1(p_month);
begin
  if not (public._recipe_cost_ok() and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then select * into d from public.factory_cost_pools where client_id = p_client; if found then return jsonb_build_object('dup', true, 'id', d.id); end if; end if;
  if p_month is null then raise exception 'bad_date'; end if;
  if not exists (select 1 from public.cost_component_types where code = p_type and active) then raise exception 'unknown_type'; end if;
  if p_period_kind not in ('month', 'year') then raise exception 'bad_value'; end if;
  if p_amount is null or not (p_amount >= 0 and p_amount <= 1000000000000) then raise exception 'bad_cost'; end if;
  perform public.lock_check(m);
  update public.factory_cost_pools set active = false where location_id = p_loc and month = m and component_type = p_type and period_kind = p_period_kind and source = 'manual' and active;
  insert into public.factory_cost_pools (location_id, month, component_type, period_kind, actual_amount, one_off, source, note, client_id, created_by)
    values (p_loc, m, p_type, p_period_kind, p_amount, coalesce(p_one_off, false), 'manual', left(p_note, 200), p_client, auth.uid()) returning id into nid;
  return jsonb_build_object('id', nid);
end $$;

-- the per-location choice (owner only): off | recipe | pool, and the NORMAL monthly output (base units)
create or replace function public.loc_cost_cfg_set(p_loc int, p_mode text, p_normal numeric default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_mode not in ('off', 'recipe', 'pool') then raise exception 'bad_value'; end if;
  if p_normal is not null and not (p_normal > 0 and p_normal <= 1000000000) then raise exception 'bad_qty'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'unknown location'; end if;
  insert into public.location_cost_cfg (location_id, mode, normal_monthly_output, updated_by, updated_at) values (p_loc, p_mode, p_normal, auth.uid(), now())
    on conflict (location_id) do update set mode = excluded.mode, normal_monthly_output = excluded.normal_monthly_output, updated_by = auth.uid(), updated_at = now();
end $$;

-- ---------- C4 / C5: recipe_cost - the SAME _recipe_need as the production run (packaging included), raw / packaging / conversion as separate rows, "today's price" in its own row ----------
create or replace function public.recipe_cost(p_recipe uuid, p_loc int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.recipes; ls jsonb := '[]'::jsonb; raw_t numeric := 0; pack_t numeric := 0; raw_d numeric := 0; pack_d numeric := 0; complete boolean := true; n record; av numeric; td numeric; yb numeric; gate text;
        conv jsonb; conv_amt numeric; mat numeric; matd numeric; gap numeric; thr numeric; gl numeric; fb int := 0; cinc boolean; mode_ text;
begin
  if p_loc is not null then
    if not (public._cost_ok(p_loc) and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;      -- same rule as the stock cost columns
  elsif not public._recipe_cost_ok() then raise exception 'not allowed'; end if;
  select * into r from public.recipes where id = p_recipe;
  if not found then raise exception 'recipe_not_found'; end if;
  gate := public._recipe_gate73(p_recipe);      -- bos73: 'on' = refuse an unapproved recipe
  yb := public._base_qty(r.item_id, r.yield_qty, r.yield_unit);
  for n in select * from public._recipe_need(p_recipe, 1, coalesce(p_loc, 0)) order by kind, code loop      -- bos74: the same function the production run uses
    if p_loc is not null then
      select avg_cost into av from public.stock_balance where item_id = n.item_id and location_id = p_loc;
    else
      select sum(qty * avg_cost) / nullif(sum(qty), 0) into av from public.stock_balance
        where item_id = n.item_id and qty > 0 and avg_cost is not null and (public._all_locs() or public.can_loc(location_id)) and public._cost_ok(location_id);
    end if;
    td := public._today_cost(n.item_id, p_loc);
    if av is null then complete := false;
    elsif n.kind = 'packaging' then pack_t := pack_t + n.need * av; else raw_t := raw_t + n.need * av; end if;
    if td is null then fb := fb + 1; end if;
    if coalesce(td, av) is not null then
      if n.kind = 'packaging' then pack_d := pack_d + n.need * coalesce(td, av); else raw_d := raw_d + n.need * coalesce(td, av); end if;
    end if;
    gl := case when av is not null and av > 0 and td is not null then round((td - av) / av * 100, 2) end;
    ls := ls || jsonb_build_object('ingredient_item_id', n.item_id, 'code', n.code, 'kind', n.kind, 'need_base', n.need, 'unit_cost', av, 'line_cost', case when av is null then null else round(n.need * av, 4) end,
      'today_unit_cost', td, 'gap_pct', gl, 'waste_missing', n.waste_missing);
  end loop;
  conv := public._conv_cost(p_recipe, p_loc, 1, yb, (now() at time zone 'Asia/Dhaka')::date, case when p_loc is null then 'recipe' end);
  conv_amt := coalesce((conv->>'amount')::numeric, 0); mode_ := conv->>'mode'; cinc := mode_ <> 'off' and not (conv->>'complete')::boolean;
  mat := raw_t + pack_t; matd := raw_d + pack_d;
  gap := case when complete and mat > 0 then round((matd - mat) / mat * 100, 2) end;
  thr := public.rule_num('cost_gap_warn_pct');
  return jsonb_build_object('recipe_id', p_recipe, 'lines', ls, 'complete', complete,
    'rows', jsonb_build_array(jsonb_build_object('row', 'raw', 'amount', case when complete then round(raw_t, 4) end), jsonb_build_object('row', 'packaging', 'amount', case when complete then round(pack_t, 4) end),
      jsonb_build_object('row', 'conversion', 'amount', round(conv_amt, 4), 'mode', mode_, 'complete', not cinc)),
    'raw_cost', case when complete then round(raw_t, 4) end, 'packaging_cost', case when complete then round(pack_t, 4) end, 'material_cost', case when complete then round(mat, 4) end,
    'conversion_cost', round(conv_amt, 4), 'conversion_mode', mode_, 'conversion_complete', not cinc, 'conversion_detail', conv->'detail', 'conversion_reason', conv->>'reason',
    'conversion_flag', case when cinc then 'রূপান্তর খরচ অসম্পূর্ণ' end,
    'batch_cost', case when complete then round(mat + conv_amt, 4) end,
    'unit_cost', case when complete and yb > 0 then round((mat + conv_amt) / yb, 6) end, 'yield_base', yb,
    'approved', r.approved_at is not null, 'approval_warn', gate = 'warn',
    'today', jsonb_build_object('raw_cost', round(raw_d, 4), 'packaging_cost', round(pack_d, 4), 'material_cost', round(matd, 4), 'batch_cost', round(matd + conv_amt, 4),
      'unit_cost', case when yb > 0 then round((matd + conv_amt) / yb, 6) end, 'gap_pct', gap, 'gap_warn', thr is not null and gap is not null and abs(gap) > thr,
      'lines_without_purchase_price', fb, 'note', 'display only - never booked'));
end $$;

-- ---------- C3 / C7: production_post with conversion cost and an optional actual yield ----------
create or replace function public.production_post(p_loc int, p_recipe uuid, p_batches numeric, p_client uuid, p_made_at timestamptz, p_note text, p_actual_yield numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.recipes; it public.items; at_ timestamptz := coalesce(p_made_at, now()); run public.production_runs; n record; rid uuid := gen_random_uuid();
        mode text; neg text; yb numeric; f numeric; sl jsonb; exp timestamptz; bid bigint; lin bigint; lid bigint; tot numeric := 0; cost_ok boolean := true; av numeric; wm int := 0;
        shorts text := ''; used jsonb := '[]'::jsonb; ucb numeric; derived uuid; gate text;
        outq numeric; conv jsonb; conv_amt numeric := 0; cinc boolean; yvp numeric; ythr numeric;   -- bos74
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
  gate := public._recipe_gate73(r.id);      -- bos73: on = refuse an unapproved recipe; warn = a yellow line below
  if p_batches is null or not (p_batches between 0.0001 and 100000) then raise exception 'bad_qty'; end if;
  if at_ > now() + interval '10 minutes' then raise exception 'bad_date'; end if;
  if not exists (select 1 from public.recipe_lines where recipe_id = r.id and active) then raise exception 'no_lines'; end if;
  f := public._base_qty(r.item_id, r.yield_qty, r.yield_unit);
  if f is null or not (f > 0) then raise exception 'unit_unknown'; end if;
  yb := round(f * p_batches, 4);
  if not (yb between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  if p_actual_yield is not null and not (round(p_actual_yield, 4) between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;      -- bos74
  outq := case when p_actual_yield is null then yb else round(p_actual_yield, 4) end;      -- bos74: what is really booked into stock
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
    values (rid, p_client, p_loc, r.id, r.item_id, p_batches, at_, outq, wm, left(p_note, 200), auth.uid());      -- bos74: yield_base = the quantity really booked
  -- ingredient (and packaging) OUT at the weighted average cost, fixed item order so two productions can never wait on each other in a circle
  for n in select * from public._recipe_need(r.id, p_batches, p_loc) order by item_id loop
    if n.need < 0.0001 then continue; end if;
    select avg_cost into av from public.stock_balance where item_id = n.item_id and location_id = p_loc;
    if av is null then cost_ok := false; else tot := tot + n.need * av; end if;
    derived := md5(coalesce(p_client::text, rid::text) || ':' || n.item_id::text)::uuid;
    lin := public.stock_post(n.item_id, p_loc, -n.need, 'issue_out', 'production', rid::text, null, null, at_, left(p_note, 200), null, 'full', null, derived);
    used := used || jsonb_build_object('item_id', n.item_id, 'kind', n.kind, 'qty', n.need);
  end loop;
  -- bos74: conversion cost (layer 2) of this run: off = nothing (today's behaviour); recipe = the recipe's rates; pool = monthly pool / NORMAL output
  conv := public._conv_cost(r.id, p_loc, p_batches, outq, (at_ at time zone 'Asia/Dhaka')::date);
  conv_amt := coalesce((conv->>'amount')::numeric, 0); cinc := (conv->>'mode') <> 'off' and not (conv->>'complete')::boolean;
  -- finished good IN: batch + expiry from the owner's shelf-life rules (no rule = no expiry); the cost is material + conversion when every ingredient has a known cost
  sl := public.shelf_life_for(r.item_id, (at_ at time zone 'Asia/Dhaka')::date);
  exp := case when sl is null then null else at_ + ((sl->>'hours')::float8 * interval '1 hour') end;
  insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by)
    values (r.item_id, p_loc, at_, outq, outq, exp, sl, left(p_note, 200), auth.uid()) returning id into bid;
  ucb := case when cost_ok and outq > 0 then round((tot + conv_amt) / outq, 6) end;      -- bos74: (material + conversion) / actual output
  derived := md5(coalesce(p_client::text, rid::text) || ':in')::uuid;
  lid := public.stock_post(r.item_id, p_loc, outq, 'production_in', 'production', rid::text, ucb, bid, at_, left(p_note, 200), null, 'none', null, derived);
  yvp := case when p_actual_yield is not null and yb > 0 then round((outq - yb) / yb * 100, 2) end;
  update public.production_runs set ledger_in_id = lid, batch_id = bid, cost_complete = cost_ok,
      material_cost = case when cost_ok then round(tot, 4) end, conversion_cost = round(conv_amt, 4), unit_cost = ucb,
      std_cost = case when cost_ok and yb > 0 then round((tot + conv_amt) / yb, 6) end, actual_cost = ucb,
      conversion_mode = conv->>'mode', conversion_complete = not cinc, conversion_detail = conv->'detail', yield_std = yb, yield_actual = p_actual_yield, yield_var_pct = yvp where id = rid;   -- bos74
  update public.recipes set used_at = coalesce(used_at, now()) where id = r.id;
  if wm > 0 then
    perform public._stock_exc(p_loc, 'recipe_waste_missing', 'yellow', it.name_bn || ': রেসিপিতে অপচয় % বসানো নেই — ০ ধরা হয়েছে (' || wm::text || ' লাইন)',
      coalesce(it.name_en, it.name_bn) || ': the recipe has no waste % on ' || wm::text || ' line(s) — counted as 0', null, (at_ at time zone 'Asia/Dhaka')::date, 'STOCK');
  end if;
  if gate = 'warn' then      -- bos73
    perform public._stock_exc(p_loc, 'recipe_not_approved', 'yellow', it.name_bn || ': রেসিপি (ভার্সন ' || r.version::text || ') অনুমোদিত নয়',
      coalesce(it.name_en, it.name_bn) || ': recipe version ' || r.version::text || ' is not approved', null, (at_ at time zone 'Asia/Dhaka')::date, 'STOCK');
  end if;
  if cinc then      -- bos74
    perform public._stock_exc(p_loc, 'conversion_incomplete', 'yellow', it.name_bn || ': রূপান্তর খরচ অসম্পূর্ণ (খালি ঘর আছে) — যা জানা ছিল শুধু তা ধরা হয়েছে',
      coalesce(it.name_en, it.name_bn) || ': conversion cost incomplete (blank amounts) — only the known part was booked', null, (at_ at time zone 'Asia/Dhaka')::date, 'STOCK');
  end if;
  ythr := public.rule_num('yield_variance_warn_pct');      -- bos74
  if yvp is not null and ythr is not null and abs(yvp) > ythr then
    perform public._stock_exc(p_loc, 'yield_variance', 'yellow', it.name_bn || ': আসল উৎপাদন রেসিপির ফলন থেকে ' || yvp::text || '% আলাদা',
      coalesce(it.name_en, it.name_bn) || ': actual yield differs from the recipe yield by ' || yvp::text || '%', null, (at_ at time zone 'Asia/Dhaka')::date, 'STOCK');
  end if;
  return jsonb_build_object('run_id', rid, 'ledger_id', lid, 'batch_id', bid, 'qty', outq, 'expires_at', exp, 'consumed', used, 'waste_missing', wm) ||
    case when public._cost_ok(p_loc) then jsonb_build_object('cost_complete', cost_ok, 'conversion_complete', not cinc, 'unit_cost', ucb) else '{}'::jsonb end;
end $$;

-- the 6-argument signature stays (callers and older tests use it): it is a thin wrapper, there is NO default on the 7th parameter so a 6-argument call is never ambiguous
create or replace function public.production_post(p_loc int, p_recipe uuid, p_batches numeric, p_client uuid default null, p_made_at timestamptz default null, p_note text default null) returns jsonb
language sql security definer set search_path = public as $$
  select public.production_post(p_loc, p_recipe, p_batches, p_client, p_made_at, p_note, null::numeric);
$$;

-- the cost snapshot of runs: cost-right holders ONLY (the new production_runs columns are not in the browser column grant)
create or replace function public.production_run_costs(p_loc int, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public._cost_ok(p_loc) and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('run_id', r.id, 'made_at', r.made_at, 'status', r.status, 'item_id', r.item_id, 'code', i.code, 'batches', r.batches, 'yield_std', r.yield_std, 'yield_actual', r.yield_actual,
      'yield_var_pct', r.yield_var_pct, 'output', r.yield_base, 'material_cost', r.material_cost, 'conversion_cost', r.conversion_cost, 'unit_cost', r.unit_cost, 'std_cost', r.std_cost, 'actual_cost', r.actual_cost,
      'conversion_mode', r.conversion_mode, 'conversion_complete', r.conversion_complete, 'conversion_detail', r.conversion_detail) order by r.made_at, r.id)
    from public.production_runs r join public.items i on i.id = r.item_id
    where r.location_id = p_loc and (r.made_at at time zone 'Asia/Dhaka')::date between coalesce(p_from, date '2000-01-01') and coalesce(p_to, date '2999-12-31')), '[]'::jsonb);
end $$;

-- ---------- C6: month-end true-up: ACTUAL factory cost (pools) vs ABSORBED into products; the difference is the row 'অনাবশোষিত ওভারহেড' ----------
create or replace function public.overhead_trueup(p_loc int, p_month date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m date := public._m1(p_month); rows_ jsonb := '[]'::jsonb; t record; act numeric; ab numeric; act_tot numeric := 0; ab_tot numeric := 0; ab_noact numeric := 0; have_actual boolean := false; oneoff int;
begin
  if not (public._recipe_cost_ok() and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  if p_month is null then raise exception 'bad_date'; end if;
  for t in select c.code, c.label_bn, c.label_en from public.cost_component_types c where c.active order by c.code loop
    act := public._pool_month_actual(p_loc, m, t.code);
    select coalesce(sum((d->>'amount')::numeric), 0) into ab from public.production_runs r, jsonb_array_elements(coalesce(r.conversion_detail, '[]'::jsonb)) d
      where r.location_id = p_loc and r.status = 'done' and public._m1((r.made_at at time zone 'Asia/Dhaka')::date) = m and d->>'type' = t.code and (d->>'amount') is not null;
    if act is null and ab = 0 then continue; end if;
    if act is not null then have_actual := true; act_tot := act_tot + act; ab_tot := ab_tot + ab; else ab_noact := ab_noact + ab; end if;
    rows_ := rows_ || jsonb_build_object('type', t.code, 'label_bn', t.label_bn, 'label_en', t.label_en, 'actual', act, 'absorbed', round(ab, 2), 'unabsorbed', case when act is null then null else round(act - ab, 2) end,
      'note', case when act is null then 'বাস্তব খরচ ঢোকানো নেই / no actual entered' end);
  end loop;
  select count(*) into oneoff from public.factory_cost_pools where active and location_id = p_loc and month = m and one_off;
  return jsonb_build_object('location_id', p_loc, 'month', m, 'rows', rows_, 'actual_total', case when have_actual then round(act_tot, 2) end, 'absorbed_total', round(ab_tot + ab_noact, 2),
    'absorbed_matched', round(ab_tot, 2), 'absorbed_without_actual', round(ab_noact, 2),
    'unabsorbed_overhead', case when have_actual then round(act_tot - ab_tot - ab_noact, 2) end, 'unabsorbed_label_bn', 'অনাবশোষিত ওভারহেড', 'unabsorbed_label_en', 'Unabsorbed overhead',
    'one_off_rows', oneoff, 'note', 'showroom and admin cost are not absorbed into products');
end $$;

-- ---------- C7: the 05-4 yield test gives a SUGGESTION only; the recipe is never changed ----------
create or replace function public.recipe_yield_suggestion(p_recipe uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r public.recipes; it public.items; e record; lines_ jsonb;
begin
  if not (public._recipe_read() or public.has_grant('recipe_view')) then raise exception 'not allowed'; end if;
  select * into r from public.recipes where id = p_recipe;
  if not found then raise exception 'recipe_not_found'; end if;
  select * into it from public.items where id = r.item_id;
  select x.serial, x.entry_date, x.location_id, x.w into e from (
    select en.serial, en.entry_date, en.location_id,
           (select avg(public._r2_num(b -> 'waste') / nullif(coalesce(public._r2_num(b -> 'good'), 0) + coalesce(public._r2_num(b -> 'second'), 0) + coalesce(public._r2_num(b -> 'waste'), 0), 0) * 100)
              from jsonb_array_elements(public._p26_arr(en.data -> 'b')) b where public._r2_num(b -> 'waste') is not null) as w
      from public.entries en where en.form_code = '05-4' and en.status = 'approved' and en.data ->> 'item' = it.code and public.can_loc(en.location_id)
     order by en.entry_date desc, en.serial desc limit 1) x;
  select coalesce(jsonb_agg(jsonb_build_object('code', i.code, 'waste_pct', l.waste_pct) order by l.sort, l.id), '[]'::jsonb) into lines_
    from public.recipe_lines l join public.items i on i.id = l.ingredient_item_id where l.recipe_id = p_recipe and l.active;
  return jsonb_build_object('recipe_id', p_recipe, 'suggested_waste_pct', case when e.w is null then null else round(e.w, 2) end, 'source_serial', e.serial, 'source_date', e.entry_date,
    'recipe_lines_waste', lines_, 'note', 'suggestion_only', 'applied', false);
end $$;

-- ---------- C8: the manual production path ----------
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
  if public.rule_on('production_manual_needs_reason') and length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;      -- bos74
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
  if p_unit_cost is not null then      -- bos74: a hand-typed cost on the no-recipe path is always flagged
    perform public._stock_exc(p_loc, 'production_manual_cost', 'yellow', it.name_bn || ': উৎপাদনের খরচ হাতে লেখা (রেসিপি ছাড়া) — রেসিপি দিয়ে উৎপাদন করুন',
      coalesce(it.name_en, it.name_bn) || ': production cost was typed by hand (no recipe) — prefer a recipe production', null, (at_ at time zone 'Asia/Dhaka')::date, 'STOCK');
  end if;
  sl := public.shelf_life_for(p_item, (at_ at time zone 'Asia/Dhaka')::date);
  exp := case when sl is null then null else at_ + ((sl->>'hours')::float8 * interval '1 hour') end;
  insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by)
    values (p_item, p_loc, at_, bq, bq, exp, sl, left(p_note, 200), auth.uid()) returning id into bid;
  lid := public.stock_post(p_item, p_loc, bq, 'production_in', 'production', bid::text, case when p_unit_cost is null then null else p_unit_cost / f end, bid, at_, left(p_note, 200), null, 'none', null, p_client);
  return jsonb_build_object('ledger_id', lid, 'batch_id', bid, 'qty', bq, 'expires_at', exp);
end $$;

-- ---------- C6: the GL account + mapping key overhead_absorbed (the owner may re-point it with acct_mapping_set) ----------
insert into public.coa_accounts (code, name_bn, name_en, type, normal_side, is_group, is_system, sort)
  values ('5950', 'কারখানার ওভারহেড অবশোষিত (বিপরীত খরচ)', 'Factory overhead absorbed into products (contra expense)', 'expense', 'credit', false, true, 5950)
  on conflict (code) do nothing;
insert into public.acct_mappings (key, account_id, label_bn, label_en)
  select 'overhead_absorbed', a.id, 'পণ্যের খরচে ধরা কারখানার ওভারহেড', 'Factory overhead absorbed into products' from public.coa_accounts a where a.code = '5950'
  on conflict (key) do nothing;

-- ---------- privileges ----------
-- the read policies of the new cost tables call this helper as the signed-in person
grant execute on function public._recipe_cost_ok() to authenticated;
revoke all on function public._m1(date), public._pool_month_actual(int, date, text), public._pool_rate(int, date, text), public._pool_rate_amount(int, date, text), public._conv_cost(uuid, int, numeric, numeric, date, text), public._today_cost(uuid, int) from public, anon, authenticated;
revoke all on function public.cost_type_add(text, text), public.cost_type_smoothing(text, text, int), public.recipe_cost_component_set(uuid, text, text, numeric, numeric, text, text, uuid), public.recipe_cost_component_retire(bigint),
  public.recipe_cost_components_get(uuid), public.pool_set(int, date, text, numeric, text, boolean, text, uuid), public.loc_cost_cfg_set(int, text, numeric), public.production_run_costs(int, date, date),
  public.overhead_trueup(int, date), public.recipe_yield_suggestion(uuid), public.recipe_cost(uuid, int), public.production_post(int, uuid, numeric, uuid, timestamptz, text, numeric), public.production_post(int, uuid, numeric, uuid, timestamptz, text) from public, anon;
grant execute on function public.cost_type_add(text, text), public.cost_type_smoothing(text, text, int), public.recipe_cost_component_set(uuid, text, text, numeric, numeric, text, text, uuid), public.recipe_cost_component_retire(bigint),
  public.recipe_cost_components_get(uuid), public.pool_set(int, date, text, numeric, text, boolean, text, uuid), public.loc_cost_cfg_set(int, text, numeric), public.production_run_costs(int, date, date),
  public.overhead_trueup(int, date), public.recipe_yield_suggestion(uuid), public.recipe_cost(uuid, int), public.production_post(int, uuid, numeric, uuid, timestamptz, text, numeric), public.production_post(int, uuid, numeric, uuid, timestamptz, text) to authenticated;
revoke all on function public.stock_production_in(uuid, int, numeric, timestamptz, text, text, uuid, numeric) from public, anon;
grant execute on function public.stock_production_in(uuid, int, numeric, timestamptz, text, text, uuid, numeric) to authenticated;

-- ---------- C6: the journal source _acct_docs re-created (LATEST definition = phase52; only the production block changed, marked bos74) ----------
CREATE OR REPLACE FUNCTION public._acct_docs(p_start date)
 RETURNS TABLE(source_type text, source_id text, entry_date date, location_id integer, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- sales (payments split, discount, revenue, COGS only from real unit costs)
  return query
  select 'sale'::text, s.id::text, s.sale_date, s.location_id, ('Receipt ' || s.receipt)::text, null::text, s.status = 'done', (s.void_at at time zone 'Asia/Dhaka')::date,
    case when s.status = 'done' and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = s.id::text and l.reason = 'sale_out'
                   and l.item_id = (e->>'item_id')::uuid and l.unit_cost is not null)) then 'cogs_missing' end,
    null::text,
    case when s.status = 'done' then (
      select coalesce(jsonb_agg(j order by o), '[]'::jsonb) from (
        select 1 o, jsonb_build_object('a', 'pay_' || p.mode, 'd', sum(p.amount)) j from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided group by p.mode
        union all select 2, jsonb_build_object('a', 'receivable', 'd', round(s.total - pp.paid, 2), 'pt', case when s.customer_id is not null then 'customer' end, 'pid', s.customer_id::text) where s.total - pp.paid > 0.004
        union all select 3, jsonb_build_object('a', 'sales_discount', 'd', s.discount) where s.discount > 0
        union all select 4, jsonb_build_object('a', 'sales', 'c', s.subtotal)
        union all select 5, jsonb_build_object('a', 'cogs', 'd', cg.amt) from (select round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l where l.ref_id = s.id::text and l.ref_type in ('sale', 'sale_pack') and l.reason in ('sale_out', 'issue_out') and l.unit_cost is not null) cg where cg.amt > 0
        union all select 6, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt) from (select it.item_type t, round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l join public.items it on it.id = l.item_id where l.ref_id = s.id::text and l.ref_type in ('sale', 'sale_pack') and l.reason in ('sale_out', 'issue_out') and l.unit_cost is not null group by it.item_type) z where z.amt > 0
      ) x) end
  from public.sales s cross join lateral (select coalesce(sum(p.amount), 0) paid from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided) pp
  where s.sale_date >= p_start and s.subtotal > 0 and public._acct_need('sale', s.id::text, s.status = 'done');

  -- sale returns
  return query
  select 'sale_return'::text, r.id::text, (r.created_at at time zone 'Asia/Dhaka')::date, r.location_id, ('Return of receipt ' || coalesce(s.receipt::text, '-'))::text, null::text, r.status = 'done', (r.void_at at time zone 'Asia/Dhaka')::date,
    case when r.status = 'done' and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(r.lines) = 'array' then r.lines else '[]'::jsonb end) e
                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return'
                   and l.item_id = (e->>'item_id')::uuid and l.unit_cost is not null)) then 'cogs_missing' end,
    null::text,
    case when r.status = 'done' then (
      select coalesce(jsonb_agg(j order by o), '[]'::jsonb) from (
        select 1 o, jsonb_build_object('a', 'sales_returns', 'd', r.amount) j
        union all select 2, jsonb_build_object('a', 'receivable', 'c', r.credit_amount, 'pt', case when r.customer_id is not null then 'customer' end, 'pid', r.customer_id::text) where r.credit_amount > 0
        union all select 3, jsonb_build_object('a', public._acct_paykey(coalesce(r.refund_mode, 'cash')), 'c', r.refund_amount) where r.refund_amount > 0
        union all select 4, jsonb_build_object('a', public._acct_inv_key(z.t), 'd', z.amt) from (select it.item_type t, round(sum(l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l join public.items it on it.id = l.item_id where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return' and l.unit_cost is not null group by it.item_type) z where z.amt > 0
        union all select 5, jsonb_build_object('a', 'cogs', 'c', cg.amt) from (select round(sum(l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return' and l.unit_cost is not null) cg where cg.amt > 0
      ) x) end
  from public.sale_returns r left join public.sales s on s.id = r.sale_id
  where (r.created_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('sale_return', r.id::text, r.status = 'done');

  -- customer collections (later payments of dues)
  return query
  select 'collection'::text, p.id::text, (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, 'Due collection'::text, null::text, not p.voided, public._acct_today(), null::text, null::text,
    case when not p.voided then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(p.mode), 'd', p.amount),
      jsonb_build_object('a', 'receivable', 'c', p.amount, 'pt', case when p.customer_id is not null then 'customer' end, 'pid', p.customer_id::text)) end
  from public.sale_payments p
  where p.kind = 'collection' and (p.paid_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('collection', p.id::text, not p.voided);

  -- purchase bills and purchase returns
  return query
  select 'purchase'::text, b.id::text, b.bill_date, b.location_id, ((case b.kind when 'return' then 'Purchase return ' else 'Purchase bill ' end) || coalesce(b.bill_no, '-'))::text, b.kind, b.status = 'posted' and b.total > 0, (b.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when b.status = 'posted' and b.total > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'payable', case when b.kind = 'return' then 'd' else 'c' end, b.total, 'pt', 'supplier', 'pid', b.supplier_id::text) j
        union all select 2, jsonb_build_object('a', al.k, case when b.kind = 'return' then 'c' else 'd' end, al.amt) from public._acct_purchase_alloc(b.id) al
      ) x) end
  from public.purchase_bills b
  where b.bill_date >= p_start and public._acct_need('purchase', b.id::text, b.status = 'posted' and b.total > 0);

  -- supplier payments
  return query
  select 'supplier_payment'::text, p.id::text, (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, 'Supplier payment'::text, null::text, not p.voided, public._acct_today(), null::text, null::text,
    case when not p.voided then jsonb_build_array(jsonb_build_object('a', 'payable', 'd', p.amount, 'pt', 'supplier', 'pid', p.supplier_id::text),
      jsonb_build_object('a', public._acct_paykey(p.mode, true), 'c', p.amount)) end
  from public.supplier_payments p
  where (p.paid_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('supplier_payment', p.id::text, not p.voided);

  -- supplier refunds
  return query
  select 'supplier_refund'::text, f.id::text, (f.refunded_at at time zone 'Asia/Dhaka')::date, f.location_id, 'Supplier refund'::text, null::text, not f.voided, public._acct_today(), null::text, null::text,
    case when not f.voided then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(f.mode, true), 'd', f.amount),
      jsonb_build_object('a', 'payable', 'c', f.amount, 'pt', 'supplier', 'pid', f.supplier_id::text)) end
  from public.supplier_refunds f
  where (f.refunded_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('supplier_refund', f.id::text, not f.voided);

  -- 10-2 expense vouchers (approved; a re-opened or re-numbered voucher is reversed, the new revision posted)
  return query
  select 'expense_voucher'::text, e.id::text || ':' || coalesce(e.rev_no, 0)::text, e.entry_date, e.location_id, ('Expense voucher ' || e.serial)::text, null::text, v.total > 0, public._acct_today(),
    case when v.bad > 0 then 'unreadable_lines' end, null::text,
    case when v.total > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'exp_' || h.head, 'd', h.amt) j from (
          select regexp_replace(lower(coalesce(nullif(btrim(x->>'head'), ''), 'other')), '[^a-z0-9_]', '_', 'g') head, sum(public._acct_num(x->>'amount')) amt
          from jsonb_array_elements(case when jsonb_typeof(e.data->'lines') = 'array' then e.data->'lines' else '[]'::jsonb end) x
          where public._acct_num(x->>'amount') > 0 group by 1) h
        union all select 2, jsonb_build_object('a', 'pay_cash', 'c', v.total)
      ) y) end
  from public.entries e cross join lateral (
    select coalesce(sum(public._acct_num(x->>'amount')) filter (where public._acct_num(x->>'amount') > 0), 0) total,
           count(*) filter (where coalesce(btrim(x->>'amount'), '') <> '' and public._acct_num(x->>'amount') is null) bad
    from jsonb_array_elements(case when jsonb_typeof(e.data->'lines') = 'array' then e.data->'lines' else '[]'::jsonb end) x) v
  where e.form_code = '10-2' and e.status = 'approved' and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.entry_date >= p_start and public._acct_need('expense_voucher', e.id::text || ':' || coalesce(e.rev_no, 0)::text, v.total > 0);
  return query
  select 'expense_voucher'::text, je.source_id, je.entry_date, je.location_id, 'Expense voucher no longer approved'::text, null::text, false, public._acct_today(), null::text, null::text, null::jsonb
  from public.journal_entries je
  where je.source_type = 'expense_voucher' and je.reverses_id is null
    and not exists (select 1 from public.entries e where e.form_code = '10-2' and e.status = 'approved' and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.id::text || ':' || coalesce(e.rev_no, 0)::text = je.source_id)
    and not exists (select 1 from public.journal_entries r where r.reverses_id = je.id);

  -- bos50: quick expenses typed in the day-book tab: expense head debit, cash / bank / mobile credit
  return query
  select 'quick_expense'::text, q.id::text, q.exp_date, q.location_id, ('Quick expense: ' || q.head)::text, null::text, q.status = 'done', (q.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when q.status = 'done' then jsonb_build_array(
      jsonb_build_object('a', case when exists (select 1 from public.acct_mappings m where m.key = 'exp_' || q.head) then 'exp_' || q.head else 'exp_other' end, 'd', q.amount),
      jsonb_build_object('a', public._acct_paykey(q.mode), 'c', q.amount)) end
  from public.quick_expenses q
  where q.exp_date >= p_start and public._acct_need('quick_expense', q.id::text, q.status = 'done');

  -- cash moves (bank deposit / withdraw, owner top-up / draw, customer advances, hub receipt)
  return query
  select 'cash_move'::text, public._acct_sid52('cash_move', m.id::text) /* bos52 */, m.move_date, m.location_id, ('Cash move: ' || m.kind)::text, m.kind, m.status = 'done' and not public._shadowed52('cash_moves', m.id::text) /* bos52 */, (m.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when m.status = 'done' and not public._shadowed52('cash_moves', m.id::text) /* bos52 */ then case m.kind
      when 'bank_deposit' then jsonb_build_array(jsonb_build_object('a', 'pay_bank', 'd', m.amount), jsonb_build_object('a', 'pay_cash', 'c', m.amount))
      when 'bank_withdraw' then jsonb_build_array(jsonb_build_object('a', 'pay_cash', 'd', m.amount), jsonb_build_object('a', 'pay_bank', 'c', m.amount))
      when 'owner_topup' then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(m.mode), 'd', m.amount), jsonb_build_object('a', 'owner_capital', 'c', m.amount))
      when 'owner_draw' then jsonb_build_array(jsonb_build_object('a', 'owner_drawings', 'd', m.amount), jsonb_build_object('a', public._acct_paykey(m.mode), 'c', m.amount))
      when 'cust_advance' then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(m.mode), 'd', m.amount), jsonb_build_object('a', 'cust_advance', 'c', m.amount, 'pt', 'customer', 'pid', m.customer_id::text))
      when 'cust_advance_refund' then jsonb_build_array(jsonb_build_object('a', 'cust_advance', 'd', m.amount, 'pt', 'customer', 'pid', m.customer_id::text), jsonb_build_object('a', public._acct_paykey(m.mode), 'c', m.amount))
      when 'cust_advance_used' then jsonb_build_array(jsonb_build_object('a', 'cust_advance', 'd', m.amount, 'pt', 'customer', 'pid', m.customer_id::text), jsonb_build_object('a', 'receivable', 'c', m.amount, 'pt', 'customer', 'pid', m.customer_id::text))
      when 'hub_receipt' then jsonb_build_array(jsonb_build_object('a', 'pay_cash', 'd', m.amount), jsonb_build_object('a', 'hub_clearing', 'c', m.amount))
    end end
  from public.cash_moves m
  where m.move_date >= p_start and public._acct_need('cash_move', public._acct_sid52('cash_move', m.id::text), m.status = 'done' and not public._shadowed52('cash_moves', m.id::text) /* bos52 */);

  -- wastage at the real cost in the stock ledger
  return query
  select 'wastage'::text, w.id::text, (w.made_at at time zone 'Asia/Dhaka')::date, w.location_id, 'Wastage written off'::text, null::text, true, null::date,
    case when c.nulls > 0 and c.amt > 0 then 'cogs_missing' end,
    case when c.amt is null or c.amt <= 0 then 'cost_missing' end,
    case when c.amt > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'wastage', 'd', c.amt) j
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)
          from (select it.item_type t, round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l join public.items it on it.id = l.item_id
                where l.ref_type = 'wastage' and l.ref_id = w.id::text and l.reason = 'wastage' and l.unit_cost is not null group by it.item_type) z where z.amt > 0
      ) y) end
  from public.stock_wastage w cross join lateral (
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where l.unit_cost is null) nulls
    from public.stock_ledger l where l.ref_type = 'wastage' and l.ref_id = w.id::text and l.reason = 'wastage') c
  where (w.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('wastage', w.id::text, true);

  -- production: ingredients (at their real cost) move from raw / packaging to finished goods
  return query
  select 'production'::text, r.id::text, (r.made_at at time zone 'Asia/Dhaka')::date, r.location_id, 'Production run'::text, null::text, r.status = 'done', (r.void_at at time zone 'Asia/Dhaka')::date,
    case when c.nulls > 0 and c.amt > 0 then 'cogs_missing' end,
    case when r.status = 'done' and (c.amt is null or c.amt <= 0) then 'cost_missing' end,
    case when r.status = 'done' and c.amt > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'inv_finished', 'd', c.amt + round(coalesce(r.conversion_cost, 0), 2)) j /* bos74: material + conversion */
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)
          from (select it.item_type t, round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l join public.items it on it.id = l.item_id
                where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out' and l.unit_cost is not null group by it.item_type) z where z.amt > 0
        union all select 3, jsonb_build_object('a', 'overhead_absorbed', 'c', round(r.conversion_cost, 2)) where coalesce(r.conversion_cost, 0) >= 0.005 /* bos74: Cr overhead absorbed */
      ) y) end
  from public.production_runs r cross join lateral (
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where l.unit_cost is null) nulls
    from public.stock_ledger l where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out') c
  where (r.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('production', r.id::text, r.status = 'done');

  -- bos52: payroll payments of the app payroll (a run whose sheet is the record, i.e. the run is a locked shadow, is skipped). Dr salary expense, Cr cash / bank / mobile.
  -- The advance recovery on the pay line is split over the payments pro rata and credited to the staff-advance asset (data: payroll_lines.advance_recovery).
  return query
  select 'payroll_payment'::text, public._acct_sid52('payroll_payment', p.id::text), p.pay_date, p.location_id, ('Salary payment PR-' || p.run_id::text)::text, null::text,
    p.status = 'done' and not public.is_shadow('payroll_runs', p.run_id::text), (p.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when p.status = 'done' and not public.is_shadow('payroll_runs', p.run_id::text) then
      jsonb_build_array(jsonb_build_object('a', 'salary_exp', 'd', p.amount + r.rec, 'pt', 'staff', 'pid', p.employee_id::text),
                        jsonb_build_object('a', public._acct_paykey(p.mode), 'c', p.amount))
      || case when r.rec > 0 then jsonb_build_array(jsonb_build_object('a', 'staff_advance', 'c', r.rec, 'pt', 'staff', 'pid', p.employee_id::text)) else '[]'::jsonb end
    end
  from public.payroll_payments p
  cross join lateral (select case when l.advance_recovery > 0 and l.net > 0 then least(round(l.advance_recovery * p.amount / l.net, 2), l.advance_recovery) else 0 end as rec
                        from public.payroll_lines l where l.id = p.line_id) r
  where p.pay_date >= p_start
    and public._acct_need('payroll_payment', public._acct_sid52('payroll_payment', p.id::text), p.status = 'done' and not public.is_shadow('payroll_runs', p.run_id::text));

  -- bos52: staff advances paid out of the business (cash / bank / mobile only; mode none = money not moved here, nothing posted). Dr staff advances, Cr cash / bank / mobile.
  return query
  select 'staff_advance'::text, a.id::text, a.adv_date, a.location_id, ('Staff advance ADV-' || a.id::text)::text, null::text,
    a.status = 'active' and a.mode in ('cash', 'bank', 'mobile'), (a.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when a.status = 'active' and a.mode in ('cash', 'bank', 'mobile') then
      jsonb_build_array(jsonb_build_object('a', 'staff_advance', 'd', a.amount, 'pt', 'staff', 'pid', a.employee_id::text),
                        jsonb_build_object('a', public._acct_paykey(a.mode), 'c', a.amount)) end
  from public.employee_advances a
  where a.adv_date >= p_start and public._acct_need('staff_advance', a.id::text, a.status = 'active' and a.mode in ('cash', 'bank', 'mobile'));

  -- bos52: partner capital (contribution / return of capital / loan in / loan repayment / owner drawing). The partner-capital record that is a locked shadow of a cash move
  -- is not posted (the cash move is the record then). A partner-capital record that is the primary of a cash-move shadow takes the place of the cash move (same place, once).
  -- In-kind contributions move no money: they are reported as waiting (in_kind), nothing is guessed.
  return query
  select 'partner_capital'::text, public._acct_sid52('partner_capital', c.id::text), c.cap_date, nullif(lk.loc, 0), ('Partner capital: ' || c.kind)::text, c.kind,
    c.status = 'posted' and not public._shadowed52('partner_capital', c.id::text), (c.void_at at time zone 'Asia/Dhaka')::date, null::text,
    case when c.mode = 'in_kind' then 'in_kind' end,
    case when c.status = 'posted' and c.mode <> 'in_kind' and not public._shadowed52('partner_capital', c.id::text) then case c.kind
      when 'contribution' then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(c.mode), 'd', c.amount), jsonb_build_object('a', 'owner_capital', 'c', c.amount, 'pt', 'partner', 'pid', c.party_id::text))
      when 'return_of_capital' then jsonb_build_array(jsonb_build_object('a', 'owner_capital', 'd', c.amount, 'pt', 'partner', 'pid', c.party_id::text), jsonb_build_object('a', public._acct_paykey(c.mode), 'c', c.amount))
      when 'loan_in' then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(c.mode), 'd', c.amount), jsonb_build_object('a', 'partner_loan', 'c', c.amount, 'pt', 'partner', 'pid', c.party_id::text))
      when 'loan_repayment' then jsonb_build_array(jsonb_build_object('a', 'partner_loan', 'd', c.amount, 'pt', 'partner', 'pid', c.party_id::text), jsonb_build_object('a', public._acct_paykey(c.mode), 'c', c.amount))
      when 'owner_drawing' then jsonb_build_array(jsonb_build_object('a', 'owner_drawings', 'd', c.amount, 'pt', 'partner', 'pid', c.party_id::text), jsonb_build_object('a', public._acct_paykey(c.mode), 'c', c.amount))
    end end
  from public.partner_capital c
  left join lateral (select x.location_id as loc from public.shadow_links x where x.primary_type = 'partner_capital' and x.primary_id = c.id::text and x.shadow_type = 'cash_moves'
                      and x.shadow_id is not null and x.state <> 'void' order by x.id limit 1) lk on true
  where c.cap_date >= p_start and public._acct_need('partner_capital', public._acct_sid52('partner_capital', c.id::text), c.status = 'posted' and not public._shadowed52('partner_capital', c.id::text));
end $function$;
