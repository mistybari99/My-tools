-- ============================================================
-- Phase 116 (bos116) - BATCH 3, part 1: manufacturing cost ENGINE (audit: docs/audit2/A1_manufacturing_cost.md G1 G4 G5 G6 G7 G8 G10).
-- Run AFTER phase111 (canonical order, docs/PASTE_ORDER.md section N). Needs phases 72..111. Additive; paste twice = no change. Phase117 (GL side) is the companion.
-- EVERY behaviour change is behind a rules switch whose default is today's behaviour; with all switches off the books, costs and screens are exactly as before.
--   semi_finished_ingredient116  finished goods (chhana, dough) may be an ingredient of another recipe; cycles refused                         (G1)
--   packaging_on_actual_yield116 packaging is used for the quantity really made, not the planned yield                                        (G10)
--   std_snapshot_auto116         the first run of a recipe at a place stores the STANDARD (recipe quantities x prices of that day)              (G8)
--   std_cost_true116             production_runs.std_cost = that true standard per unit (today it is actual cost / theoretical output)          (G8)
--   pool_drivers116              overhead pool can be spread by output kg / output units / batches / labour hours, per place and per cost type   (G5, G6)
--   conv_provisional116          a run made before its month's pool exists uses the last month that has a pool, flagged PROVISIONAL              (G4)
--   cost_supply_to_avg116        a cost supplied through the cost-waiting list also reaches stock_balance.avg_cost and re-costs the run           (G7)
-- New read/act functions (no switch needed, they change nothing until called): recipe_std_set116, production_variance116, production_reprice116 and production_recost116 (both dry by default),
--   production_cost_queue116, recipe_stage_cost116, loc_cost_driver_set116, cost_type_driver_set116.
-- Functions re-created (tag bos116, every older tag kept): _recipe_lines_ok, _recipe_need (thin wrapper), production_post (7 args), _conv_cost, cost_wait_supply96, production_run_costs, production_void.
-- Re-paste rule: if phase19/73/74/79/522/109 (anything that re-creates one of those functions) is pasted again, paste phase116 again after it.
-- ============================================================

do $g$
declare miss text := ''; m record; d text; t text; bad text := '';
begin
  for m in select * from (values
    ('72', 'public._cogs_lines72(date,date,integer[])'), ('73', 'public._recipe_gate73(uuid)'), ('74', 'public._pool_rate(integer,date,text)'),
    ('75', 'public._cs_alloc(bigint)'), ('80', 'public._cost_free80(uuid)'), ('81', 'public._setup_chk81(text)'), ('96', 'public._cw_docs96()'),
    ('97', 'public._landed_jlines97(uuid,text)'), ('87', 'public._prod_double_issue87()')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  if to_regclass('public.setup_rec_defs81') is null then miss := miss || ' 81'; end if;
  if to_regclass('public.opening_covered103') is null then miss := miss || ' 103'; end if;
  if to_regprocedure('public.production_post(integer,uuid,numeric,uuid,timestamptz,text,numeric)') is null
     or coalesce(position('bos109' in pg_get_functiondef(to_regprocedure('public.production_post(integer,uuid,numeric,uuid,timestamptz,text,numeric)'))), 0) = 0
        and coalesce(position('bos116' in pg_get_functiondef(to_regprocedure('public.production_post(integer,uuid,numeric,uuid,timestamptz,text,numeric)'))), 0) = 0 then miss := miss || ' 109'; end if;
  if miss <> '' then raise exception 'phase116 needs phases 72..111 pasted first (see docs/PASTE_ORDER.md); missing:%', miss; end if;
  -- body guard: a function this file re-creates must carry no bosNN tag that this file does not know (a later phase changed it: merge into this file first)
  for m in select * from (values
    ('public.production_post(integer,uuid,numeric,uuid,timestamptz,text,numeric)', 'bos72 bos73 bos74 bos80 bos109 bos116'),
    ('public._recipe_lines_ok(uuid,jsonb)', 'bos116'), ('public._recipe_need(uuid,numeric,integer)', 'bos116'), ('public._conv_cost(uuid,integer,numeric,numeric,date,text)', 'bos116'),
    ('public.cost_wait_supply96(text,text,text,jsonb,text,uuid,boolean)', 'bos116'), ('public.production_run_costs(integer,date,date)', 'bos116'), ('public.production_void(uuid,text)', 'bos116')) v(fn, ok)
  loop
    d := pg_get_functiondef(to_regprocedure(m.fn));
    for t in select distinct x[1] from regexp_matches(d, '(bos[0-9]+)', 'g') x loop
      if position(t in m.ok) = 0 then bad := bad || ' ' || m.fn || '->' || t; end if;
    end loop;
  end loop;
  if bad <> '' then raise exception 'phase116 refuses: a function it re-creates carries a tag it does not know (merge that change into phase116 first):%', bad; end if;
end $g$;

-- ---------- switches (all default OFF = today's behaviour) ----------
insert into public.rules (key, module, kind, default_value, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('semi_finished_ingredient116', 'stock', 'switch', 'false', null, null, null,
  'তৈরি পণ্য (আধা-তৈরি মাল) অন্য রেসিপির উপাদান হতে পারবে', 'Finished good (semi-finished) অন্য recipe-র ingredient হতে পারবে', 'A finished good (semi-finished) may be an ingredient of another recipe',
  'Off (default) = আজকের মতো, শুধু কাঁচামাল / প্যাকেজিং / রিসেল। On = ছানার মতো আধা-তৈরি মাল মিষ্টির রেসিপিতে বসানো যাবে; উৎপাদনে সেই মাল stock থেকে গড় খরচে কমবে। ঘুরে-আসা রেসিপি (ক → খ → ক) আটকানো হয়।',
  'Off (default) = as today: only raw material, packaging and resale items. On = a semi-finished good such as chhana can be an ingredient; production takes it out of stock at its average cost. A circle (A uses B, B uses A) is refused.', 750),
 ('packaging_on_actual_yield116', 'stock', 'switch', 'false', null, null, null,
  'প্যাকেজিং আসল উৎপাদনের হিসাবে', 'Packaging আসল উৎপাদনের হিসাবে', 'Packaging is used for the quantity really made',
  'Off (default) = আজকের মতো, পরিকল্পিত ফলনের হিসাবে। On = আসল ফলন দিলে প্যাকেজিংয়ের পরিমাণ ও খরচ সেই আসল পরিমাণের উপর (শুধু packaging_consume_on = production হলে)।',
  'Off (default) = as today, planned yield. On = when an actual yield is given, packaging quantity and cost follow the quantity really made (only with packaging_consume_on = production).', 751),
 ('std_snapshot_auto116', 'stock', 'switch', 'false', null, null, null,
  'প্রথম উৎপাদনে রেসিপির স্ট্যান্ডার্ড খরচ সংরক্ষণ', 'প্রথম production-এ recipe-র standard cost save', 'Store the recipe standard cost at the first run',
  'Off (default) = আজকের মতো, কিছু সংরক্ষণ হয় না। On = কোনো জায়গায় রেসিপির প্রথম উৎপাদনে সেদিনের গড় দাম × রেসিপির পরিমাণ standard হিসেবে রাখা হয় (price / usage variance report-এর জন্য)। হাতে বসাতে recipe_std_set116।',
  'Off (default) = nothing is stored. On = at the first run of a recipe at a place, the recipe quantities x that day''s average prices are kept as the standard (for the price / usage variance report). To set one by hand use recipe_std_set116.', 752),
 ('std_cost_true116', 'stock', 'switch', 'false', null, null, null,
  'std_cost = সত্যিকারের standard (রেসিপির পরিমাণ × standard দাম)', 'std_cost = আসল standard (recipe qty × standard price)', 'std_cost holds the true standard cost per unit',
  'Off (default) = আজকের মতো: std_cost = (আসল কাঁচামাল + আসল রূপান্তর) / তাত্ত্বিক উৎপাদন (এটা standard নয়, নাম ভুল)। On = std_cost = সংরক্ষিত standard খরচ প্রতি একক। পুরনো সংখ্যাটা cost_full_yield116-এ সবসময় থাকে।',
  'Off (default) = as today: std_cost = (actual material + actual conversion) / theoretical output (a mislabelled number, not a standard). On = std_cost = the stored standard cost per unit. The old number is always kept in cost_full_yield116.', 753),
 ('pool_drivers116', 'stock', 'switch', 'false', null, null, null,
  'ওভারহেড পুল ভাগের একক: কেজি / একক / ব্যাচ / শ্রম-ঘণ্টা', 'Overhead pool ভাগের driver: kg / unit / batch / labour hour', 'Overhead pool drivers: kg, units, batches, labour hours',
  'Off (default) = আজকের মতো, শুধু কেজি (পিস / লিটারের পণ্যে রূপান্তর খরচ শূন্য)। On = জায়গা ও খরচের ধরন অনুযায়ী driver বেছে নেওয়া যায় (loc_cost_driver_set116), সংশ্লিষ্ট "স্বাভাবিক মাসিক পরিমাণ" লিখতে হয়। কোনো সংখ্যা আন্দাজ করা হয় না।',
  'Off (default) = as today: output kg only (piece / litre products get no conversion cost in pool mode). On = pick the driver per place and per cost type (loc_cost_driver_set116); the matching normal monthly quantity must be typed. Nothing is guessed.', 754),
 ('conv_provisional116', 'stock', 'switch', 'false', null, null, null,
  'মাসের পুল না থাকলে আগের মাসের হার দিয়ে সাময়িক রূপান্তর খরচ', 'Month-এর pool না থাকলে আগের মাসের rate-এ provisional conversion cost', 'Provisional conversion cost from the last month with a pool',
  'Off (default) = আজকের মতো, রূপান্তর খরচ শূন্য + হলুদ সতর্কতা। On = মাসের কোনো পুলই না লেখা থাকলে আগের ৬ মাসের মধ্যে সবচেয়ে সাম্প্রতিক পুলের হার ধরা হয়, run "সাময়িক" চিহ্নিত; বিল এলে production_reprice116 দিয়ে ঠিক করুন।',
  'Off (default) = as today, conversion 0 + a yellow flag. On = when the month has no pool at all, the rate of the latest month (up to 6 back) that has one is used and the run is marked PROVISIONAL; re-price it with production_reprice116 once the bills are in.', 755),
 ('cost_supply_to_avg116', 'stock', 'switch', 'false', null, null, null,
  'cost-waiting-এ দেওয়া দাম গড় খরচেও যাবে, রান নতুন করে খরচ ধরবে', 'Cost-waiting-এ দেওয়া দাম avg cost-এও যাবে, run re-cost হবে', 'A supplied cost also reaches the item average and re-costs the run',
  'Off (default) = আজকের মতো, দেওয়া দাম শুধু খাতার overlay-তে থাকে, stock-এর গড় খরচ ফাঁকা থেকে যায়। On = দাম দিলে stock_balance.avg_cost-ও বসে (বা গড়ে মেশে) এবং সেই উৎপাদন run-এর খরচ হালনাগাদ হয়।',
  'Off (default) = as today: the supplied cost lives only in the ledger overlay and the item average stays blank. On = the supplied cost also sets (or blends into) stock_balance.avg_cost and the production run it belongs to is re-costed.', 756)
on conflict (key) do nothing;

-- ---------- columns / tables ----------
alter table public.production_runs add column if not exists conversion_provisional116 boolean not null default false;
alter table public.production_runs add column if not exists cost_full_yield116 numeric;     -- (material + conversion) / theoretical output: what std_cost always held
alter table public.production_runs add column if not exists std_unit_cost116 numeric;       -- the true standard cost per unit (stored standard), when one exists
alter table public.location_cost_cfg add column if not exists driver116 text check (driver116 is null or driver116 in ('output_kg', 'output_units', 'batches', 'labour_hours'));
alter table public.location_cost_cfg add column if not exists normal_units116 numeric check (normal_units116 is null or (normal_units116 > 0 and normal_units116 <= 1000000000));
alter table public.location_cost_cfg add column if not exists normal_batches116 numeric check (normal_batches116 is null or (normal_batches116 > 0 and normal_batches116 <= 1000000000));
alter table public.location_cost_cfg add column if not exists normal_labour_hours116 numeric check (normal_labour_hours116 is null or (normal_labour_hours116 > 0 and normal_labour_hours116 <= 1000000000));
alter table public.cost_component_types add column if not exists driver116 text check (driver116 is null or driver116 in ('output_kg', 'output_units', 'batches', 'labour_hours'));

create table if not exists public.recipe_std116 (
  id bigserial primary key,
  recipe_id uuid not null references public.recipes(id),
  location_id int not null references public.locations(id),
  yield_per_batch numeric not null check (yield_per_batch > 0),      -- base units of finished good per batch
  mat_per_batch numeric,                                              -- NULL = some ingredient price was unknown (no number is invented)
  conv_per_batch numeric,
  lines jsonb not null,                                               -- [{item_id, kind, qty_per_batch, unit_cost}]
  conv_detail jsonb,
  complete boolean not null,
  source text not null default 'auto' check (source in ('auto', 'manual')),
  active boolean not null default true,
  note text,
  set_by uuid,
  set_at timestamptz not null default now()
);
create unique index if not exists recipe_std116_one_active on public.recipe_std116 (recipe_id, location_id) where active;
create index if not exists recipe_std116_lookup on public.recipe_std116 (recipe_id, location_id, set_at);

create table if not exists public.production_reprice116 (
  id bigserial primary key,
  run_id uuid not null references public.production_runs(id),
  old_conversion numeric not null,
  new_conversion numeric not null,
  delta numeric not null,
  delta_inventory numeric not null,
  delta_cogs numeric not null,
  entry_id bigint,
  by_user uuid,
  at timestamptz not null default now()
);
create unique index if not exists production_reprice116_run on public.production_reprice116 (run_id);

drop trigger if exists rs116_no_delete on public.recipe_std116;
create trigger rs116_no_delete before delete on public.recipe_std116 for each row execute function public.no_hard_delete();
drop trigger if exists pr116_no_delete on public.production_reprice116;
create trigger pr116_no_delete before delete on public.production_reprice116 for each row execute function public.no_hard_delete();
drop trigger if exists audit_rs116 on public.recipe_std116;
create trigger audit_rs116 after insert or update on public.recipe_std116 for each row execute function public.log_change('id');
drop trigger if exists audit_pr116 on public.production_reprice116;
create trigger audit_pr116 after insert or update on public.production_reprice116 for each row execute function public.log_change('id');
alter table public.recipe_std116 enable row level security;
alter table public.production_reprice116 enable row level security;
-- cost secrecy: NO browser SELECT on these tables (like the cost columns of production_runs); they are read only through the cost-right functions (production_variance116, recipe_stage_cost116 ...)
drop policy if exists rs116_read on public.recipe_std116;
drop policy if exists pr116_read on public.production_reprice116;
revoke all on public.recipe_std116, public.production_reprice116 from anon, authenticated;
revoke all on sequence public.recipe_std116_id_seq, public.production_reprice116_id_seq from anon, authenticated;
-- bos116: does the (active) recipe tree of p_from contain p_target? (cycle guard for semi-finished ingredients; depth capped at 12)
create or replace function public._recipe_reaches116(p_from uuid, p_target uuid) returns boolean
language sql stable security definer set search_path = public as $$
  with recursive t(i, d) as (
    select p_from, 1
    union all
    select rl.ingredient_item_id, t.d + 1 from t join public.recipes r on r.item_id = t.i and r.active join public.recipe_lines rl on rl.recipe_id = r.id and rl.active where t.d < 12)
  select exists (select 1 from t where i = p_target);
$$;

CREATE OR REPLACE FUNCTION public._recipe_lines_ok(p_item uuid, p_lines jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare ln jsonb; ing public.items; q numeric; w numeric; seen uuid[] := '{}'; iid uuid;
begin
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'no_lines'; end if;
  if jsonb_array_length(p_lines) > 100 then raise exception 'too_many_lines'; end if;
  for ln in select x from jsonb_array_elements(p_lines) x loop
    iid := nullif(ln->>'ingredient_item_id', '')::uuid;
    select * into ing from public.items where id = iid;
    if not found then raise exception 'item_not_found'; end if;
    if iid = p_item then raise exception 'ingredient_is_product'; end if;
    if ing.item_type not in ('raw_material', 'packaging', 'resale') and not (ing.item_type = 'finished_good' and public.rule_on('semi_finished_ingredient116')) then raise exception 'bad_ingredient_type' using detail = ing.code; end if;   -- bos116: semi-finished goods behind a switch
    if ing.item_type = 'finished_good' and public.rule_on('semi_finished_ingredient116') and public._recipe_reaches116(iid, p_item) then raise exception 'recipe_cycle' using detail = ing.code; end if;   -- bos116
    if iid = any(seen) then raise exception 'dup_ingredient'; end if;
    seen := seen || iid;
    q := nullif(ln->>'qty', '')::numeric;
    if q is null or not (q > 0 and q < 1000000000) then raise exception 'bad_qty'; end if;
    w := nullif(ln->>'waste_pct', '')::numeric;
    if w is not null and not (w between 0 and 100) then raise exception 'bad_waste'; end if;
    if public._base_qty(iid, q, nullif(btrim(ln->>'unit'), '')) is null then raise exception 'unit_unknown' using detail = ing.code; end if;
  end loop;
end $function$;

CREATE OR REPLACE FUNCTION public._recipe_need116(p_recipe uuid, p_batches numeric, p_loc integer, p_out numeric)
 RETURNS TABLE(item_id uuid, kind text, need numeric, on_hand numeric, tracked boolean, unit_ok boolean, waste_missing boolean, code text, name_bn text, name_en text, base_unit text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      select i.id, 'packaging'::text, round(pp.qty_per_unit * case when p_out is not null and public.rule_on('packaging_on_actual_yield116') then p_out else yb end, 4) /* bos116: packaging on the quantity really made, behind a switch */, coalesce(b.qty, 0), i.tracked, true, false, i.code, i.name_bn, i.name_en, public._item_base(i.id)
        from public.product_packaging pp join public.items i on i.id = pp.packaging_item_id
        left join public.stock_balance b on b.item_id = i.id and b.location_id = p_loc
       where coalesce(public.rule_txt('packaging_consume_on'), 'off') = 'production' and pp.product_item_id = r.item_id and pp.active and pp.applies_to = 'production') z
    group by z.item_id, z.code, z.name_bn, z.name_en, z.base_unit;
end $function$;

-- bos116: the old 3-argument entry point is a thin wrapper (planned yield) so every reader keeps working
create or replace function public._recipe_need(p_recipe uuid, p_batches numeric, p_loc integer)
returns table(item_id uuid, kind text, need numeric, on_hand numeric, tracked boolean, unit_ok boolean, waste_missing boolean, code text, name_bn text, name_en text, base_unit text)
language sql stable security definer set search_path = public as $$
  select * from public._recipe_need116(p_recipe, p_batches, p_loc, null::numeric);   -- bos116
$$;

-- bos116: provisional pool rate of a cost type: the latest of the 6 months before p_month that has a pool figure (never a guess: the month is named in the result)
create or replace function public._pool_rate_prov116(p_loc int, p_month date, p_type text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare k int; pm date; pr jsonb;
begin
  for k in 1 .. 6 loop
    pm := (p_month - make_interval(months => k))::date;
    pr := public._pool_rate(p_loc, pm, p_type);
    if (pr ->> 'amount') is not null then return pr || jsonb_build_object('from', pm); end if;
  end loop;
  return jsonb_build_object('amount', null);
end $$;

CREATE OR REPLACE FUNCTION public._conv_cost(p_recipe uuid, p_loc integer, p_batches numeric, p_out numeric, p_date date, p_force_mode text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare md text; c record; ty record; det jsonb := '[]'::jsonb; tot numeric := 0; complete boolean := true; amt numeric; norm numeric; m date := public._m1(p_date); any_pool boolean := false; ncomp int := 0; why text := null; a numeric; pr jsonb;
        drv boolean := public.rule_on('pool_drivers116'); cfg public.location_cost_cfg; dn text; nd numeric; qd numeric; hrs numeric; prov boolean := false; use_prov boolean := false; pj jsonb; base_u text;   -- bos116
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
    select * into cfg from public.location_cost_cfg where location_id = p_loc;      -- bos116
    norm := cfg.normal_monthly_output;
    -- bos116: provisional only when the run month has NO pool row at all (nothing typed yet) and the owner switched it on; reprice sets bos.no_prov116 to see the real pool only
    use_prov := public.rule_on('conv_provisional116') and coalesce(current_setting('bos.no_prov116', true), '') <> 'on'
                and not exists (select 1 from public.factory_cost_pools f where f.active and f.location_id = p_loc and f.month = m);
    base_u := lower(coalesce((select public._item_base(r.item_id) from public.recipes r where r.id = p_recipe), ''));
    if not drv then
      if base_u <> 'kg' then complete := false; why := 'pool_unit_not_kg';      -- the pool rate is per kg of output: a piece-based product needs recipe rates (or pool_drivers116)
      elsif norm is null or norm <= 0 then complete := false; why := 'normal_output_blank';
      else
        for ty in select code from public.cost_component_types where active order by code loop
          pr := public._pool_rate(p_loc, m, ty.code); a := (pr ->> 'amount')::numeric; pj := null;
          if a is null and use_prov then pj := public._pool_rate_prov116(p_loc, m, ty.code); a := (pj ->> 'amount')::numeric; end if;      -- bos116
          if a is not null then any_pool := true; amt := a / norm * p_out; tot := tot + amt;
            if pj is not null and (pj ->> 'amount') is not null then prov := true; end if;
            det := det || jsonb_build_object('type', ty.code, 'basis', 'pool', 'rate', round(a / norm, 8), 'amount', round(amt, 6), 'incomplete', false, 'months', coalesce(pj -> 'span', pr -> 'span'), 'gap_months', coalesce(pj -> 'gaps', pr -> 'gaps'))
              || case when pj is not null and (pj ->> 'amount') is not null then jsonb_build_object('provisional', true, 'provisional_from', pj ->> 'from') else '{}'::jsonb end; end if;
        end loop;
        if not any_pool then complete := false; why := 'no_pool'; end if;
      end if;
    else
      -- bos116: driver per cost type (type override, else the place default, else output kg = today)
      for ty in select code, driver116 from public.cost_component_types where active order by code loop
        pr := public._pool_rate(p_loc, m, ty.code); a := (pr ->> 'amount')::numeric; pj := null;
        if a is null and use_prov then pj := public._pool_rate_prov116(p_loc, m, ty.code); a := (pj ->> 'amount')::numeric; end if;
        if a is null then continue; end if;
        dn := coalesce(ty.driver116, cfg.driver116, 'output_kg'); nd := null; qd := null;
        if dn = 'output_kg' then
          nd := norm; qd := p_out;
          if base_u <> 'kg' then complete := false; why := 'pool_unit_not_kg'; continue; end if;
        elsif dn = 'output_units' then nd := cfg.normal_units116; qd := p_out;
        elsif dn = 'batches' then nd := cfg.normal_batches116; qd := p_batches;
        else
          nd := cfg.normal_labour_hours116;
          select sum(c2.hours_per_batch) into hrs from public.recipe_cost_components c2 where c2.recipe_id = p_recipe and c2.active and c2.basis = 'per_labour_hour' and c2.hours_per_batch is not null;
          qd := hrs * p_batches;
        end if;
        if nd is null or nd <= 0 then complete := false; why := 'normal_' || dn || '_blank'; continue; end if;
        if qd is null then complete := false; why := 'no_labour_hours'; continue; end if;
        any_pool := true; amt := a / nd * qd; tot := tot + amt;
        if pj is not null and (pj ->> 'amount') is not null then prov := true; end if;
        det := det || jsonb_build_object('type', ty.code, 'basis', 'pool', 'driver', dn, 'rate', round(a / nd, 8), 'amount', round(amt, 6), 'incomplete', false, 'months', coalesce(pj -> 'span', pr -> 'span'), 'gap_months', coalesce(pj -> 'gaps', pr -> 'gaps'))
          || case when pj is not null and (pj ->> 'amount') is not null then jsonb_build_object('provisional', true, 'provisional_from', pj ->> 'from') else '{}'::jsonb end;
      end loop;
      if not any_pool and why is null then complete := false; why := 'no_pool'; end if;
    end if;
  end if;
  return jsonb_build_object('mode', md, 'amount', tot, 'complete', complete, 'detail', det, 'reason', why) || case when prov then jsonb_build_object('provisional', true) else '{}'::jsonb end;      -- bos116
end $function$;

CREATE OR REPLACE FUNCTION public.production_post(p_loc integer, p_recipe uuid, p_batches numeric, p_client uuid, p_made_at timestamp with time zone, p_note text, p_actual_yield numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.recipes; it public.items; at_ timestamptz := coalesce(p_made_at, now()); run public.production_runs; n record; rid uuid := gen_random_uuid();
        mode text; neg text; yb numeric; f numeric; sl jsonb; exp timestamptz; bid bigint; lin bigint; lid bigint; tot numeric := 0; cost_ok boolean := true; av numeric; wm int := 0;
        shorts text := ''; nocost text := ''; used jsonb := '[]'::jsonb; ucb numeric; derived uuid; gate text;
        outq numeric; conv jsonb; conv_amt numeric := 0; cinc boolean; yvp numeric; ythr numeric;   -- bos74
        prov boolean := false; sn public.recipe_std116; stdu numeric; stdc numeric;   -- bos116
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
  for n in select * from public._recipe_need116(r.id, p_batches, p_loc, outq) loop
    if not n.tracked then raise exception 'ingredient_not_tracked' using detail = coalesce(n.code, ''); end if;
    if not n.unit_ok then raise exception 'unit_unknown' using detail = coalesce(n.code, ''); end if;
    if n.waste_missing then wm := wm + 1; end if;
  end loop;
  if wm > 0 and public.rule_on('recipe_waste_required') then raise exception 'waste_needed'; end if;
  mode := coalesce(public.rule_txt('production_short_mode'), 'refuse');
  -- bos109: lock every ingredient / packaging balance AND the finished-good balance of this place in ONE item order BEFORE the shortage check, so two cooks (or a cook and a sale)
  -- cannot both pass the check on the same stock, and the later stock_post calls never take a lock in another order (no lock-order deadlock between recipes)
  perform 1 from public.stock_balance sbl where sbl.location_id = p_loc and (sbl.item_id = r.item_id or sbl.item_id in (select n2.item_id from public._recipe_need116(r.id, p_batches, p_loc, outq) n2)) order by sbl.item_id for update;   -- bos109
  if mode = 'refuse' and coalesce(public.rule_txt('stock_negative_mode'), 'warn') <> 'allow' and not public.has_grant('sell_below_zero', p_loc) then
    for n in select * from public._recipe_need116(r.id, p_batches, p_loc, outq) where need > on_hand order by code loop
      shorts := shorts || case when shorts = '' then '' else '; ' end || coalesce(n.code, '') || ' ' || coalesce(n.name_bn, '') || ' (' || round(n.on_hand, 4)::text || ' / ' || n.need::text || ')';
    end loop;
    if shorts <> '' then raise exception 'insufficient_stock' using detail = shorts, hint = 'production'; end if;
  end if;
  -- bos72: rule production_requires_cost = refuse: no ingredient may have an unknown (NULL or 0) cost (default warn = today's behaviour)
  if coalesce(public.rule_txt('production_requires_cost'), 'warn') = 'refuse' then
    for n in select * from public._recipe_need116(r.id, p_batches, p_loc, outq) order by code loop
      if n.need >= 0.0001 and coalesce((select b.avg_cost from public.stock_balance b where b.item_id = n.item_id and b.location_id = p_loc), 0) <= 0
         and not public._cost_free80(n.item_id) then      -- bos80: an item marked 'cost really zero' is a known cost
        nocost := nocost || case when nocost = '' then '' else '; ' end || coalesce(n.code, '') || ' ' || coalesce(n.name_bn, '');
      end if;
    end loop;
    if nocost <> '' then raise exception 'cost_missing' using detail = nocost, hint = 'production'; end if;
  end if;
  if public.rule_on('std_snapshot_auto116') and not exists (select 1 from public.recipe_std116 where recipe_id = r.id and location_id = p_loc) then      -- bos116: the first run stores the standard (prices of today, before anything is issued)
    perform public._recipe_std_snap116(r.id, p_loc, 'auto', null, (at_ at time zone 'Asia/Dhaka')::date);
  end if;
  if not public._may('stock_production', p_loc, 'production:' || r.item_id::text, yb) then raise exception 'not allowed'; end if;
  insert into public.production_runs (id, client_id, location_id, recipe_id, item_id, batches, made_at, yield_base, waste_missing, note, created_by)
    values (rid, p_client, p_loc, r.id, r.item_id, p_batches, at_, outq, wm, left(p_note, 200), auth.uid());      -- bos74: yield_base = the quantity really booked
  -- ingredient (and packaging) OUT at the weighted average cost, fixed item order so two productions can never wait on each other in a circle
  for n in select * from public._recipe_need116(r.id, p_batches, p_loc, outq) order by item_id loop
    if n.need < 0.0001 then continue; end if;
    select avg_cost into av from public.stock_balance where item_id = n.item_id and location_id = p_loc;
    if coalesce(av, 0) <= 0 and not public._cost_free80(n.item_id) then cost_ok := false; else tot := tot + n.need * coalesce(av, 0); end if;   -- bos72: cost 0 = unknown; bos80: unless the item is marked 'cost really zero'
    derived := md5(coalesce(p_client::text, rid::text) || ':' || n.item_id::text)::uuid;
    lin := public.stock_post(n.item_id, p_loc, -n.need, 'issue_out', 'production', rid::text, null, null, at_, left(p_note, 200), null, 'full', null, derived);
    used := used || jsonb_build_object('item_id', n.item_id, 'kind', n.kind, 'qty', n.need);
  end loop;
  -- bos74: conversion cost (layer 2) of this run: off = nothing (today's behaviour); recipe = the recipe's rates; pool = monthly pool / NORMAL output
  conv := public._conv_cost(r.id, p_loc, p_batches, outq, (at_ at time zone 'Asia/Dhaka')::date);
  conv_amt := coalesce((conv->>'amount')::numeric, 0); cinc := (conv->>'mode') <> 'off' and not (conv->>'complete')::boolean;
  prov := coalesce((conv->>'provisional')::boolean, false);      -- bos116
  -- finished good IN: batch + expiry from the owner's shelf-life rules (no rule = no expiry); the cost is material + conversion when every ingredient has a known cost
  sl := public.shelf_life_for(r.item_id, (at_ at time zone 'Asia/Dhaka')::date);
  exp := case when sl is null then null else at_ + ((sl->>'hours')::float8 * interval '1 hour') end;
  insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by)
    values (r.item_id, p_loc, at_, outq, outq, exp, sl, left(p_note, 200), auth.uid()) returning id into bid;
  ucb := case when cost_ok and outq > 0 then round((tot + conv_amt) / outq, 6) end;      -- bos74: (material + conversion) / actual output
  derived := md5(coalesce(p_client::text, rid::text) || ':in')::uuid;
  lid := public.stock_post(r.item_id, p_loc, outq, 'production_in', 'production', rid::text, ucb, bid, at_, left(p_note, 200), null, 'none', null, derived);
  yvp := case when p_actual_yield is not null and yb > 0 then round((outq - yb) / yb * 100, 2) end;
  select * into sn from public.recipe_std116 where recipe_id = r.id and location_id = p_loc and active;      -- bos116: the stored standard (if any)
  stdu := case when sn.id is not null and sn.complete and sn.mat_per_batch is not null and sn.conv_per_batch is not null then round((sn.mat_per_batch + sn.conv_per_batch) / sn.yield_per_batch, 6) end;      -- bos116
  update public.production_runs set ledger_in_id = lid, batch_id = bid, cost_complete = cost_ok,
      material_cost = case when cost_ok then round(tot, 4) end, conversion_cost = round(conv_amt, 4), unit_cost = ucb,
      std_cost = case when public.rule_on('std_cost_true116') then stdu when cost_ok and yb > 0 then round((tot + conv_amt) / yb, 6) end, actual_cost = ucb,
      cost_full_yield116 = case when cost_ok and yb > 0 then round((tot + conv_amt) / yb, 6) end, std_unit_cost116 = stdu, conversion_provisional116 = prov,      -- bos116
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
  if prov then      -- bos116
    perform public._stock_exc(p_loc, 'conversion_provisional', 'yellow', it.name_bn || ': রূপান্তর খরচ সাময়িক (আগের মাসের হারে) — মাসের বিল এলে production_reprice116 দিয়ে ঠিক করুন',
      coalesce(it.name_en, it.name_bn) || ': conversion cost is PROVISIONAL (last month''s rate) — re-price it with production_reprice116 once this month''s bills are in', null, (at_ at time zone 'Asia/Dhaka')::date, 'STOCK');
  end if;
  ythr := public.rule_num('yield_variance_warn_pct');      -- bos74
  if yvp is not null and ythr is not null and abs(yvp) > ythr then
    perform public._stock_exc(p_loc, 'yield_variance', 'yellow', it.name_bn || ': আসল উৎপাদন রেসিপির ফলন থেকে ' || yvp::text || '% আলাদা',
      coalesce(it.name_en, it.name_bn) || ': actual yield differs from the recipe yield by ' || yvp::text || '%', null, (at_ at time zone 'Asia/Dhaka')::date, 'STOCK');
  end if;
  return jsonb_build_object('run_id', rid, 'ledger_id', lid, 'batch_id', bid, 'qty', outq, 'expires_at', exp, 'consumed', used, 'waste_missing', wm) ||
    case when public._cost_ok(p_loc) then jsonb_build_object('cost_complete', cost_ok, 'conversion_complete', not cinc, 'unit_cost', ucb) else '{}'::jsonb end;
end $function$;

CREATE OR REPLACE FUNCTION public.production_run_costs(p_loc integer, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not (public._cost_ok(p_loc) and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('run_id', r.id, 'made_at', r.made_at, 'status', r.status, 'item_id', r.item_id, 'code', i.code, 'batches', r.batches, 'yield_std', r.yield_std, 'yield_actual', r.yield_actual,
      'yield_var_pct', r.yield_var_pct, 'output', r.yield_base, 'material_cost', r.material_cost, 'conversion_cost', r.conversion_cost, 'unit_cost', r.unit_cost, 'std_cost', r.std_cost, 'actual_cost', r.actual_cost,
      'conversion_mode', r.conversion_mode, 'conversion_complete', r.conversion_complete, 'conversion_detail', r.conversion_detail,
      'cost_full_yield', r.cost_full_yield116, 'std_unit_cost', r.std_unit_cost116, 'conversion_provisional', r.conversion_provisional116,
      'yield_loss_money', case when r.cost_complete and coalesce(r.yield_std, 0) > 0 and r.yield_actual is not null then round((coalesce(r.material_cost, 0) + coalesce(r.conversion_cost, 0)) * (1 - r.yield_base / r.yield_std), 2) end) order by r.made_at, r.id)      -- bos116
    from public.production_runs r join public.items i on i.id = r.item_id
    where r.location_id = p_loc and (r.made_at at time zone 'Asia/Dhaka')::date between coalesce(p_from, date '2000-01-01') and coalesce(p_to, date '2999-12-31')), '[]'::jsonb);
end $function$;

CREATE OR REPLACE FUNCTION public.production_void(p_run uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare run public.production_runs; r record; b public.stock_batches; n int := 0;
begin
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  select * into run from public.production_runs where id = p_run for update;
  if not found then raise exception 'not_found'; end if;
  if not public.can_loc(run.location_id) or not (public.is_owner() or public.has_grant('production_void', run.location_id)) then raise exception 'not allowed'; end if;
  if run.status = 'void' then return jsonb_build_object('id', run.id, 'status', 'void', 'dup', true); end if;
  if exists (select 1 from public.production_reprice116 x where x.run_id = run.id) then raise exception 'run_repriced'; end if;      -- bos116: a re-priced run has an adjustment entry; it cannot be undone silently
  perform public.lock_check((run.made_at at time zone 'Asia/Dhaka')::date);
  -- the finished goods must still be unsold: a partly sold batch cannot be undone (use wastage / count instead)
  if run.batch_id is not null then
    select * into b from public.stock_batches where id = run.batch_id for update;
    if found and b.qty_remaining < b.qty_made - 0.0001 then raise exception 'batch_partly_used'; end if;
  end if;
  for r in select o.* from public.stock_ledger o where o.ref_type = 'production' and o.ref_id = run.id::text and o.reason in ('issue_out', 'production_in')
           and not exists (select 1 from public.stock_ledger v where v.reverses_id = o.id) order by o.item_id, o.id loop
    perform public.stock_post(r.item_id, r.location_id, -r.qty_delta, 'reversal', 'production', run.id::text, r.unit_cost, r.batch_id, now(), left('void: ' || btrim(p_note), 200), r.id, 'soft');
    n := n + 1;
  end loop;
  update public.production_runs set status = 'void', void_by = auth.uid(), void_at = now(), void_note = left(btrim(p_note), 300) where id = run.id;
  return jsonb_build_object('id', run.id, 'status', 'void', 'reversed_lines', n);
end $function$;

CREATE OR REPLACE FUNCTION public.cost_wait_supply96(p_kind text, p_ref text, p_method text, p_manual jsonb DEFAULT NULL::jsonb, p_reason text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid, p_post boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pl jsonb; it jsonb; lid jsonb; n int := 0; staff text; pr jsonb; cnt int; posted boolean;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_client is null then raise exception 'client_id_needed'; end if;
  if p_method is null or p_method not in ('item_average', 'last_purchase', 'recipe_standard', 'manual') then raise exception 'bad_method'; end if;
  perform public._client_lock(p_client);
  select count(*) into cnt from public.ledger_cost_supply96 where client_id = p_client;
  if cnt > 0 then return jsonb_build_object('dup', true, 'rows', cnt, 'posted', public._cw_posted96(p_kind, p_ref)); end if;
  if exists (select 1 from public._cw_rows96(p_kind, p_ref) r where not (public.can_loc(r.loc) and public._cost_ok(r.loc))) then raise exception 'not allowed'; end if;
  if p_method = 'manual' and length(btrim(coalesce(p_reason, ''))) = 0 then raise exception 'reason_needed'; end if;
  perform pg_advisory_xact_lock(hashtextextended('cost_supply96', 0));
  if public._cw_posted96(p_kind, p_ref) then raise exception 'already_posted'; end if;
  pl := public._cw_plan96(p_kind, p_ref, p_method, p_manual);
  if not (pl->>'ok')::boolean then raise exception '%', pl->>'error' using detail = left(coalesce(pl->>'detail', ''), 500); end if;
  select staff_id into staff from public.profiles where id = auth.uid();
  for it in select * from jsonb_array_elements(pl->'items') loop
    for lid in select * from jsonb_array_elements(it->'lids') loop
      insert into public.ledger_cost_supply96 (ledger_id, unit_cost, method, reason, doc_kind, doc_ref, client_id, basis, supplied_by, supplied_staff)
        values ((lid #>> '{}')::bigint, (it->>'unit_cost')::numeric, it->>'method', left(nullif(btrim(p_reason), ''), 300), p_kind, p_ref, p_client, it->'candidates', auth.uid(), staff);
      n := n + 1;
    end loop;
  end loop;
  for it in select * from jsonb_array_elements(pl->'derived') loop
    for lid in select * from jsonb_array_elements(it->'lids') loop
      insert into public.ledger_cost_supply96 (ledger_id, unit_cost, method, reason, doc_kind, doc_ref, client_id, basis, supplied_by, supplied_staff)
        values ((lid #>> '{}')::bigint, (it->>'unit_cost')::numeric, 'from_ingredients', left(nullif(btrim(p_reason), ''), 300), p_kind, p_ref, p_client, null, auth.uid(), staff);
      n := n + 1;
    end loop;
  end loop;
  if public.rule_on('cost_supply_to_avg116') then perform public._cw_apply_avg116(p_client, p_kind, p_ref); end if;      -- bos116: the supplied cost also reaches the item average and the run
  if coalesce(p_post, true) and public.rule_on('accounting_on') and public._acct_manage() then pr := public.acct_post_pending(false, 1500); end if;
  posted := public._cw_posted96(p_kind, p_ref);
  return jsonb_build_object('kind', p_kind, 'ref', p_ref, 'method', p_method, 'rows', n, 'total', pl->'total', 'posted', posted,
    'post_run', case when pr is null then null else jsonb_build_object('posted', pr->'posted', 'locked', pr->'locked', 'errors', pr->'errors') end);
end $function$;

-- ============================================================
-- New functions (nothing here runs until somebody calls it)
-- ============================================================

-- the standard of a recipe at a place: recipe quantities (waste included, per ONE batch) x the weighted-average price of that day; conversion per batch from the place's mode.
-- A price that is unknown stays NULL and the snapshot is marked incomplete: no number is invented.
create or replace function public._recipe_std_snap116(p_recipe uuid, p_loc int, p_source text, p_note text, p_date date) returns bigint
language plpgsql security definer set search_path = public as $$
declare r public.recipes; yb numeric; ln jsonb := '[]'::jsonb; mat numeric := 0; ok boolean := true; n record; av numeric; conv jsonb; cv numeric; nid bigint;
begin
  select * into r from public.recipes where id = p_recipe;
  if not found then raise exception 'recipe_not_found'; end if;
  yb := public._base_qty(r.item_id, r.yield_qty, r.yield_unit);
  if yb is null or not (yb > 0) then raise exception 'unit_unknown'; end if;
  for n in select * from public._recipe_need116(p_recipe, 1, p_loc, null) order by item_id loop
    select b.avg_cost into av from public.stock_balance b where b.item_id = n.item_id and b.location_id = p_loc;
    if coalesce(av, 0) <= 0 and not public._cost_free80(n.item_id) then ok := false; av := null; else mat := mat + n.need * coalesce(av, 0); end if;
    ln := ln || jsonb_build_object('item_id', n.item_id, 'kind', n.kind, 'qty_per_batch', n.need, 'unit_cost', av);
  end loop;
  conv := public._conv_cost(p_recipe, p_loc, 1, yb, coalesce(p_date, (now() at time zone 'Asia/Dhaka')::date));
  cv := case when (conv ->> 'mode') = 'off' or (conv ->> 'complete')::boolean then (conv ->> 'amount')::numeric end;
  if cv is null then ok := false; end if;
  update public.recipe_std116 set active = false where recipe_id = p_recipe and location_id = p_loc and active;
  insert into public.recipe_std116 (recipe_id, location_id, yield_per_batch, mat_per_batch, conv_per_batch, lines, conv_detail, complete, source, note, set_by)
    values (p_recipe, p_loc, yb, case when ok then round(mat, 4) end, case when cv is not null then round(cv, 4) end, ln, conv -> 'detail', ok and cv is not null, p_source, left(p_note, 300), auth.uid()) returning id into nid;
  return nid;
end $$;

-- the owner (or a recipe manager with the cost right) sets / renews the standard of a recipe at a place from TODAY's average prices
create or replace function public.recipe_std_set116(p_recipe uuid, p_loc int, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare nid bigint; s public.recipe_std116;
begin
  if not (public._recipe_mgr() and public._cost_ok(p_loc) and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  nid := public._recipe_std_snap116(p_recipe, p_loc, 'manual', p_note, null);
  select * into s from public.recipe_std116 where id = nid;
  return jsonb_build_object('id', nid, 'complete', s.complete, 'material_per_batch', s.mat_per_batch, 'conversion_per_batch', s.conv_per_batch, 'yield_per_batch', s.yield_per_batch,
    'standard_unit_cost', case when s.complete then round((s.mat_per_batch + s.conv_per_batch) / s.yield_per_batch, 6) end);
end $$;

-- standard vs actual per run (money). Standard = the snapshot that was active when the run was made (p_use_latest = true: the newest snapshot, to look back at old runs).
--   price_var   = sum (actual price - standard price) x actual quantity                      (+ = dearer than standard)
--   usage_var   = sum (actual quantity - standard quantity for the OUTPUT really made) x standard price   (includes the yield loss at standard price)
--   conv_var    = actual conversion - standard conversion x (output / theoretical output)
--   total_var   = actual cost - standard cost of the output = price_var + usage_var + conv_var
--   yield_loss_money = actual cost x (1 - output / theoretical output): the share of what was spent that produced nothing (A1 a8: 3237 x 1.5/20 = 242.78)
create or replace function public.production_variance116(p_loc int, p_from date, p_to date, p_use_latest boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r record; sn public.recipe_std116; rows_ jsonb := '[]'::jsonb; scale numeric; act_mat numeric; unk int; pv numeric; uv numeric; cvv numeric; std_mat numeric; std_conv numeric; act_conv numeric; act_tot numeric; ylm numeric; ylS numeric; ok boolean; why text;
        t_pv numeric := 0; t_uv numeric := 0; t_cv numeric := 0; t_yl numeric := 0; t_act numeric := 0; t_std numeric := 0; nrun int := 0; nstd int := 0;
begin
  if not (public._cost_ok(p_loc) and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  for r in select pr.*, i.code from public.production_runs pr join public.items i on i.id = pr.item_id
            where pr.location_id = p_loc and pr.status = 'done' and (pr.made_at at time zone 'Asia/Dhaka')::date between coalesce(p_from, date '2000-01-01') and coalesce(p_to, date '2999-12-31') order by pr.made_at, pr.id loop
    nrun := nrun + 1; ok := true; why := null; pv := null; uv := null; cvv := null; std_mat := null; std_conv := null; ylm := null; ylS := null;
    select s.* into sn from public.recipe_std116 s where s.recipe_id = r.recipe_id and s.location_id = r.location_id and (s.set_at <= r.created_at or coalesce(p_use_latest, false)) order by s.set_at desc, s.id desc limit 1;
    act_conv := coalesce(r.conversion_cost, 0);
    select coalesce(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 0), count(*) filter (where coalesce(l.unit_cost, 0) = 0 and not public._cost_free80(l.item_id))
      into act_mat, unk from public.stock_ledger_eff96 l where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out' and l.reverses_id is null
        and not exists (select 1 from public.stock_ledger v where v.reverses_id = l.id);
    act_tot := act_mat + act_conv;
    if unk > 0 then ok := false; why := 'ingredient_cost_unknown'; end if;
    if coalesce(r.yield_std, 0) > 0 and unk = 0 then ylm := round(act_tot * (1 - r.yield_base / r.yield_std), 2); end if;
    if sn.id is null then ok := false; why := coalesce(why, 'no_standard');
    elsif not sn.complete then ok := false; why := coalesce(why, 'standard_incomplete');
    elsif unk = 0 and coalesce(r.yield_std, 0) > 0 then
      scale := r.yield_base / r.yield_std;
      with act as (select l.item_id, sum(-l.qty_delta) q, sum(-l.qty_delta * l.unit_cost) amt from public.stock_ledger_eff96 l
                    where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out' and l.reverses_id is null and not exists (select 1 from public.stock_ledger v where v.reverses_id = l.id) group by l.item_id),
           std as (select (x ->> 'item_id')::uuid item_id, (x ->> 'qty_per_batch')::numeric qb, nullif(x ->> 'unit_cost', '')::numeric sp from jsonb_array_elements(sn.lines) x),
           j as (select a.q, a.amt, s.qb, s.sp, s.item_id sid from act a full join std s on s.item_id = a.item_id)
      select coalesce(sum(case when j.sp is not null and j.q is not null then coalesce(j.amt, 0) - j.sp * j.q else 0 end), 0),
             coalesce(sum(case when j.sp is not null then (coalesce(j.q, 0) - coalesce(j.qb, 0) * r.batches * scale) * j.sp else coalesce(j.amt, 0) end), 0),
             coalesce(sum(coalesce(j.qb, 0) * r.batches * scale * j.sp), 0)
        into pv, uv, std_mat from j;
      std_conv := sn.conv_per_batch * r.batches * scale;
      cvv := act_conv - std_conv;
    end if;
    if ok and pv is not null then
      t_pv := t_pv + pv; t_uv := t_uv + uv; t_cv := t_cv + cvv; t_act := t_act + act_tot; t_std := t_std + std_mat + std_conv; nstd := nstd + 1;
    end if;
    if ylm is not null and unk = 0 then t_yl := t_yl + ylm; end if;
    rows_ := rows_ || jsonb_build_object('run_id', r.id, 'made_at', r.made_at, 'item_id', r.item_id, 'code', r.code, 'batches', r.batches, 'theoretical_output', r.yield_std, 'output', r.yield_base,
      'actual_material', round(act_mat, 2), 'actual_conversion', round(act_conv, 2), 'actual_total', round(act_tot, 2), 'standard_available', sn.id is not null, 'standard_set_at', sn.set_at,
      'standard_material', case when ok and pv is not null then round(std_mat, 2) end, 'standard_conversion', case when ok and pv is not null then round(std_conv, 2) end,
      'standard_total', case when ok and pv is not null then round(std_mat + std_conv, 2) end,
      'price_var', case when ok and pv is not null then round(pv, 2) end, 'usage_var', case when ok and pv is not null then round(uv, 2) end, 'conv_var', case when ok and pv is not null then round(cvv, 2) end,
      'total_var', case when ok and pv is not null then round(act_tot - std_mat - std_conv, 2) end,
      'yield_loss_money', ylm, 'conversion_provisional', r.conversion_provisional116, 'complete', ok and pv is not null, 'why', why);
  end loop;
  return jsonb_build_object('location_id', p_loc, 'from', p_from, 'to', p_to, 'runs', nrun, 'runs_with_standard', nstd, 'rows', rows_,
    'totals', jsonb_build_object('price_var', round(t_pv, 2), 'usage_var', round(t_uv, 2), 'conv_var', round(t_cv, 2), 'total_var', round(t_pv + t_uv + t_cv, 2), 'actual_total', round(t_act, 2), 'standard_total', round(t_std, 2), 'yield_loss_money', round(t_yl, 2)),
    'note', 'price_var + usage_var + conv_var = actual cost - standard cost of the output really made. yield_loss_money is a memo at ACTUAL cost (already inside usage_var at standard price). A run with no stored standard shows only its actual figures.');
end $$;

-- place default driver and the normal monthly quantity that goes with it (owner only). A NULL quantity leaves the stored one.
create or replace function public.loc_cost_driver_set116(p_loc int, p_driver text, p_normal_units numeric default null, p_normal_batches numeric default null, p_normal_hours numeric default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_driver is not null and p_driver not in ('output_kg', 'output_units', 'batches', 'labour_hours') then raise exception 'bad_value'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'unknown location'; end if;
  if (p_normal_units is not null and not (p_normal_units > 0 and p_normal_units <= 1000000000)) or (p_normal_batches is not null and not (p_normal_batches > 0 and p_normal_batches <= 1000000000))
     or (p_normal_hours is not null and not (p_normal_hours > 0 and p_normal_hours <= 1000000000)) then raise exception 'bad_qty'; end if;
  insert into public.location_cost_cfg (location_id, mode, driver116, normal_units116, normal_batches116, normal_labour_hours116, updated_by, updated_at)
    values (p_loc, 'off', p_driver, p_normal_units, p_normal_batches, p_normal_hours, auth.uid(), now())
    on conflict (location_id) do update set driver116 = excluded.driver116, normal_units116 = coalesce(excluded.normal_units116, public.location_cost_cfg.normal_units116),
      normal_batches116 = coalesce(excluded.normal_batches116, public.location_cost_cfg.normal_batches116), normal_labour_hours116 = coalesce(excluded.normal_labour_hours116, public.location_cost_cfg.normal_labour_hours116),
      updated_by = auth.uid(), updated_at = now();
end $$;

-- driver of ONE cost type (labour by labour hours, gas by kg ...); NULL = follow the place default
create or replace function public.cost_type_driver_set116(p_code text, p_driver text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_driver is not null and p_driver not in ('output_kg', 'output_units', 'batches', 'labour_hours') then raise exception 'bad_value'; end if;
  update public.cost_component_types set driver116 = p_driver where code = p_code;
  if not found then raise exception 'unknown_type'; end if;
end $$;

-- G7: a cost supplied from the cost-waiting list reaches stock_balance.avg_cost (and re-costs the run it belongs to).
--   avg blank / 0: the item takes the supplied cost.   avg known: blended, the units that were supplied weigh with their supplied cost, the rest with the average (same formula as _avg_next).
--   The average is moved through the ledger, not by an UPDATE: the whole on-hand stock goes out and comes back IN AT THE NEW AVERAGE (reason cost_adjust, same cost on both rows = no change of
--   ledger value, the overlay already carries the value), so stock_reconcile (replay of the ledger) still agrees with the cached average and a reconcile-fix cannot undo it.
create or replace function public._cw_apply_avg116(p_client uuid, p_kind text, p_ref text) returns void
language plpgsql security definer set search_path = public as $$
declare r record; bal public.stock_balance; qs numeric; na numeric;
begin
  for r in select l.item_id, l.location_id, sum(l.qty_delta) q, sum(l.qty_delta * s.unit_cost) / nullif(sum(l.qty_delta), 0) uc
             from public.ledger_cost_supply96 s join public.stock_ledger l on l.id = s.ledger_id
            where s.client_id = p_client and l.qty_delta > 0 group by 1, 2 order by 1, 2 loop
    select * into bal from public.stock_balance b where b.item_id = r.item_id and b.location_id = r.location_id for update;
    if not found or r.uc is null or r.uc <= 0 or bal.qty <= 0 then continue; end if;
    qs := least(r.q, bal.qty);
    na := round(case when coalesce(bal.avg_cost, 0) <= 0 then r.uc else (bal.avg_cost * (bal.qty - qs) + r.uc * qs) / bal.qty end, 6);
    if na is not distinct from bal.avg_cost then continue; end if;
    insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at, note, created_by)
      values (r.item_id, r.location_id, -bal.qty, na, 'cost_adjust', 'costsupply116', p_ref, now(), 'supplied cost: stock out (no value change)', auth.uid());
    insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at, note, created_by)
      values (r.item_id, r.location_id, bal.qty, na, 'cost_adjust', 'costsupply116', p_ref, now(), 'supplied cost: stock back in at the new average', auth.uid());
  end loop;
  if p_kind = 'production' and p_ref ~ '^[0-9a-f-]{36}$' then perform public._cw_run_recost116(p_ref::uuid); end if;
end $$;

create or replace function public._cw_run_recost116(p_run uuid) returns void
language plpgsql security definer set search_path = public as $$
declare run public.production_runs; mat numeric; unk int; cnt int; conv numeric;
begin
  select * into run from public.production_runs where id = p_run for update;
  if not found or run.status <> 'done' or coalesce(run.yield_base, 0) <= 0 then return; end if;
  select coalesce(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 0), count(*) filter (where coalesce(l.unit_cost, 0) = 0 and not public._cost_free80(l.item_id)), count(*)
    into mat, unk, cnt from public.stock_ledger_eff96 l where l.ref_type = 'production' and l.ref_id = p_run::text and l.reason = 'issue_out' and l.reverses_id is null
      and not exists (select 1 from public.stock_ledger v where v.reverses_id = l.id);
  if unk > 0 or cnt = 0 then return; end if;
  conv := coalesce(run.conversion_cost, 0);
  update public.production_runs set material_cost = round(mat, 4), cost_complete = true, unit_cost = round((mat + conv) / yield_base, 6), actual_cost = round((mat + conv) / yield_base, 6),
      cost_full_yield116 = case when coalesce(yield_std, 0) > 0 then round((mat + conv) / yield_std, 6) end,
      std_cost = case when public.rule_on('std_cost_true116') then std_cost when coalesce(yield_std, 0) > 0 then round((mat + conv) / yield_std, 6) else std_cost end
    where id = p_run;
end $$;

-- G4: work queue of runs whose cost is not final: conversion provisional or incomplete (pool mode), or an ingredient cost unknown
create or replace function public.production_cost_queue116(p_loc int, p_from date default null, p_to date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public._cost_ok(p_loc) and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('run_id', r.id, 'made_at', r.made_at, 'code', i.code, 'output', r.yield_base, 'unit_cost', r.unit_cost, 'conversion_mode', r.conversion_mode,
      'reason', case when r.cost_complete is not true then 'ingredient_cost_unknown' when r.conversion_provisional116 then 'conversion_provisional' else 'conversion_incomplete' end,
      'month', public._m1((r.made_at at time zone 'Asia/Dhaka')::date)) order by r.made_at, r.id)
    from public.production_runs r join public.items i on i.id = r.item_id
    where r.location_id = p_loc and r.status = 'done' and (r.made_at at time zone 'Asia/Dhaka')::date between coalesce(p_from, date '2000-01-01') and coalesce(p_to, date '2999-12-31')
      and (r.cost_complete is not true or r.conversion_provisional116 or (r.conversion_mode is not null and r.conversion_mode <> 'off' and r.conversion_complete is not true))), '[]'::jsonb);
end $$;

-- G4: re-price the POOL-mode runs of a month whose conversion was provisional or incomplete, now that the month's pool is typed. DRY by default.
--   Per run: delta = new conversion - booked conversion. The on-hand share of the run's output (min(1, finished good on hand / run output)) moves the item average and
--   Dr/Cr 1310; the sold share goes to cost of goods sold. Cr/Dr overhead absorbed takes the whole delta. One adjustment entry per run (source prod_reprice116), dated today.
--   If the run's own journal entry is not posted yet, no adjustment entry is made (it will post with the new conversion cost).
create or replace function public.production_reprice116(p_loc int, p_month date, p_dry boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m date := public._m1(p_month); r record; conv jsonb; d numeric; bal public.stock_balance; q numeric; share numeric; dinv numeric; dcogs numeric; rows_ jsonb := '[]'::jsonb; skipped jsonb := '[]'::jsonb;
        acct boolean; today_ date; lines jsonb; ent bigint; has_je boolean; n int := 0; tot numeric := 0; newc numeric; rdate date; na numeric;
begin
  if not (public._recipe_mgr() and public._cost_ok(p_loc) and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  if p_month is null then raise exception 'bad_date'; end if;
  perform set_config('bos.no_prov116', 'on', true);      -- _conv_cost sees only the REAL pool of the month
  acct := public.rule_on('accounting_on') and public._acct_start() is not null;
  today_ := public._acct_today();
  for r in select pr.* from public.production_runs pr where pr.location_id = p_loc and pr.status = 'done' and public._m1((pr.made_at at time zone 'Asia/Dhaka')::date) = m
             and pr.conversion_mode = 'pool' and (pr.conversion_provisional116 or pr.conversion_complete is not true) order by pr.made_at, pr.id for update loop
    rdate := (r.made_at at time zone 'Asia/Dhaka')::date;
    if r.cost_complete is not true then skipped := skipped || jsonb_build_object('run_id', r.id, 'why', 'ingredient_cost_unknown'); continue; end if;
    conv := public._conv_cost(r.recipe_id, p_loc, r.batches, r.yield_base, rdate, 'pool');
    if not (conv ->> 'complete')::boolean then skipped := skipped || jsonb_build_object('run_id', r.id, 'why', coalesce(conv ->> 'reason', 'pool_missing')); continue; end if;
    newc := (conv ->> 'amount')::numeric;
    d := round(newc - coalesce(r.conversion_cost, 0), 2);
    select * into bal from public.stock_balance b where b.item_id = r.item_id and b.location_id = p_loc;
    q := coalesce(bal.qty, 0);
    share := case when bal.avg_cost is null or coalesce(r.yield_base, 0) <= 0 then 0 else least(1, greatest(q, 0) / r.yield_base) end;
    dinv := round(d * share, 2); dcogs := d - dinv;
    has_je := exists (select 1 from public.journal_entries e where e.source_type = 'production' and e.source_id = r.id::text and e.reverses_id is null);
    if acct and has_je and abs(d) >= 0.005 and (rdate < public._acct_start() or public._acct_locked(today_)) then skipped := skipped || jsonb_build_object('run_id', r.id, 'why', 'period_closed_or_before_start'); continue; end if;
    n := n + 1; tot := tot + d;
    rows_ := rows_ || jsonb_build_object('run_id', r.id, 'made_at', r.made_at, 'old_conversion', coalesce(r.conversion_cost, 0), 'new_conversion', round(newc, 4), 'delta', d, 'to_inventory', dinv, 'to_cogs', dcogs, 'journal', acct and has_je and abs(d) >= 0.005);
    if p_dry then continue; end if;
    if dinv <> 0 and q > 0 and bal.avg_cost is not null then      -- same technique as landed_post: the whole on-hand stock goes out at the old average and comes back at the new one (reason cost_adjust), so the ledger value and the average move together
      select * into bal from public.stock_balance b where b.item_id = r.item_id and b.location_id = p_loc for update;
      q := bal.qty; na := greatest(round((q * bal.avg_cost + dinv) / q, 6), 0);
      insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at, note, created_by)
        values (r.item_id, p_loc, -q, bal.avg_cost, 'cost_adjust', 'reprice116', r.id::text, now(), 'overhead re-price: stock out at the old average', auth.uid());
      insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at, note, created_by)
        values (r.item_id, p_loc, q, na, 'cost_adjust', 'reprice116', r.id::text, now(), 'overhead re-price: stock back in at the new average', auth.uid());
    end if;
    ent := null;
    if acct and has_je and abs(d) >= 0.005 then
      lines := '[]'::jsonb;
      if dinv <> 0 then lines := lines || jsonb_build_object('a', 'inv_finished', case when dinv > 0 then 'd' else 'c' end, abs(dinv)); end if;
      if dcogs <> 0 then lines := lines || jsonb_build_object('a', 'cogs', case when dcogs > 0 then 'd' else 'c' end, abs(dcogs)); end if;
      lines := lines || jsonb_build_object('a', 'overhead_absorbed', case when d > 0 then 'c' else 'd' end, abs(d));
      ent := public._acct_write(today_, p_loc, 'prod_reprice116', r.id::text, null, 'Overhead re-priced for run ' || to_char(r.made_at at time zone 'Asia/Dhaka', 'YYYY-MM-DD'), null, public._acct_resolve(lines, p_loc));
    end if;
    update public.production_runs set conversion_cost = round(newc, 4), conversion_detail = conv -> 'detail', conversion_complete = true, conversion_provisional116 = false,
        unit_cost = round((coalesce(material_cost, 0) + newc) / yield_base, 6), actual_cost = round((coalesce(material_cost, 0) + newc) / yield_base, 6),
        cost_full_yield116 = case when coalesce(yield_std, 0) > 0 then round((coalesce(material_cost, 0) + newc) / yield_std, 6) end,
        std_cost = case when public.rule_on('std_cost_true116') then std_cost when coalesce(yield_std, 0) > 0 then round((coalesce(material_cost, 0) + newc) / yield_std, 6) else std_cost end
      where id = r.id;
    insert into public.production_reprice116 (run_id, old_conversion, new_conversion, delta, delta_inventory, delta_cogs, entry_id, by_user)
      values (r.id, coalesce(r.conversion_cost, 0), round(newc, 4), d, dinv, dcogs, ent, auth.uid());
  end loop;
  return jsonb_build_object('dry', p_dry, 'location_id', p_loc, 'month', m, 'runs', n, 'total_delta', round(tot, 2), 'rows', rows_, 'skipped', skipped,
    'note', 'Only POOL-mode runs of this month that were provisional or incomplete. Stock average moves for the on-hand share; the sold share goes to cost of goods sold; one entry per run.');
end $$;

-- G1: the stage split of a recipe's material cost: which lines are semi-finished goods (made in-house) and what that semi-finished good cost to make (its latest run)
create or replace function public.recipe_stage_cost116(p_recipe uuid, p_loc int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r public.recipes; n record; av numeric; ln jsonb := '[]'::jsonb; semi_t numeric := 0; other_t numeric := 0; amt numeric; it public.items; lr public.production_runs; unknown boolean := false;
begin
  if not (public._recipe_cost_ok() and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  select * into r from public.recipes where id = p_recipe;
  if not found then raise exception 'recipe_not_found'; end if;
  for n in select * from public._recipe_need116(p_recipe, 1, p_loc, null) order by kind, code loop
    select * into it from public.items where id = n.item_id;
    select b.avg_cost into av from public.stock_balance b where b.item_id = n.item_id and b.location_id = p_loc;
    amt := case when coalesce(av, 0) > 0 then round(n.need * av, 4) end;
    if amt is null and not public._cost_free80(n.item_id) then unknown := true; end if;
    if it.item_type = 'finished_good' then semi_t := semi_t + coalesce(amt, 0); else other_t := other_t + coalesce(amt, 0); end if;
    lr := null;
    if it.item_type = 'finished_good' then select * into lr from public.production_runs x where x.item_id = n.item_id and x.location_id = p_loc and x.status = 'done' order by x.made_at desc limit 1; end if;
    ln := ln || jsonb_build_object('item_id', n.item_id, 'code', n.code, 'kind', n.kind, 'semi_finished', it.item_type = 'finished_good', 'qty', n.need, 'avg_cost', av, 'amount', amt,
      'stage', case when lr.id is not null then jsonb_build_object('run_id', lr.id, 'material_cost', lr.material_cost, 'conversion_cost', lr.conversion_cost, 'unit_cost', lr.unit_cost) end);
  end loop;
  return jsonb_build_object('recipe_id', p_recipe, 'location_id', p_loc, 'lines', ln, 'semi_finished_amount', round(semi_t, 4), 'other_amount', round(other_t, 4), 'unknown_cost', unknown);
end $$;

-- G7: re-cost a run whose ingredient cost was unknown when it was made (cost_complete false), now that the ingredients have an average cost.
--   Ingredient lines with no cost are priced at the CURRENT item average (never guessed: an ingredient with no average stops the run, supply it first through the cost-waiting list).
--   The cost goes into the ledger overlay (as the cost-waiting list does), the run row is re-costed, the finished-good average takes the new unit cost (blend by quantity),
--   and if the run's journal entry was already posted (partial, flag cogs_missing) it is reversed and re-posted at the full cost (source prod_recost116). DRY by default.
create or replace function public.production_recost116(p_run uuid, p_dry boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare run public.production_runs; n record; av numeric; items_ jsonb := '[]'::jsonb; missing text := ''; mat_known numeric; added numeric := 0; conv numeric; mat_new numeric; uc numeric; cl uuid := gen_random_uuid();
        ent bigint; today_ date := public._acct_today(); lines jsonb; z record; sum_d numeric := 0; ev text; staff text; lin bigint; acct boolean;
begin
  select * into run from public.production_runs where id = p_run for update;
  if not found then raise exception 'not_found'; end if;
  if not (public._recipe_mgr() and public._cost_ok(run.location_id) and public.can_loc(run.location_id)) then raise exception 'not allowed'; end if;
  if run.status <> 'done' then raise exception 'run_void'; end if;
  if run.cost_complete is true then return jsonb_build_object('run_id', run.id, 'nothing_to_do', true); end if;
  for n in select l.id lid, l.item_id, -l.qty_delta q, i.code from public.stock_ledger_eff96 l join public.items i on i.id = l.item_id
            where l.ref_type = 'production' and l.ref_id = p_run::text and l.reason = 'issue_out' and l.reverses_id is null and not exists (select 1 from public.stock_ledger v where v.reverses_id = l.id)
              and coalesce(l.unit_cost, 0) = 0 and not public._cost_free80(l.item_id) order by l.id loop
    select b.avg_cost into av from public.stock_balance b where b.item_id = n.item_id and b.location_id = run.location_id;
    if coalesce(av, 0) <= 0 then missing := missing || case when missing = '' then '' else ', ' end || n.code; continue; end if;
    items_ := items_ || jsonb_build_object('ledger_id', n.lid, 'item_id', n.item_id, 'code', n.code, 'qty', n.q, 'unit_cost', av, 'amount', round(n.q * av, 2));
    added := added + round(n.q * av, 2);
  end loop;
  if missing <> '' then raise exception 'cost_unavailable' using detail = missing, hint = 'Supply the ingredient cost first (cost-waiting list or a purchase)'; end if;
  if jsonb_array_length(items_) = 0 then raise exception 'nothing_waiting'; end if;
  select coalesce(sum(-l.qty_delta * l.unit_cost) filter (where coalesce(l.unit_cost, 0) > 0), 0) into mat_known from public.stock_ledger_eff96 l
    where l.ref_type = 'production' and l.ref_id = p_run::text and l.reason = 'issue_out' and l.reverses_id is null and not exists (select 1 from public.stock_ledger v where v.reverses_id = l.id);
  conv := coalesce(run.conversion_cost, 0);
  mat_new := mat_known + added; uc := round((mat_new + conv) / run.yield_base, 6);
  if p_dry then
    return jsonb_build_object('dry', true, 'run_id', p_run, 'lines', items_, 'material_known', round(mat_known, 2), 'material_added', added, 'material_new', round(mat_new, 2), 'conversion', conv, 'unit_cost_new', uc);
  end if;
  acct := public.rule_on('accounting_on') and public._acct_start() is not null;
  select e.id into ent from public.journal_entries e where e.source_type = 'production' and e.source_id = p_run::text and e.reverses_id is null
     and not exists (select 1 from public.journal_entries r where r.reverses_id = e.id);
  if acct and ent is not null and (public._acct_locked(today_) or today_ < public._acct_start()) then raise exception 'period_closed'; end if;
  select staff_id into staff from public.profiles where id = auth.uid();
  for n in select * from jsonb_to_recordset(items_) as x(ledger_id bigint, unit_cost numeric) loop
    insert into public.ledger_cost_supply96 (ledger_id, unit_cost, method, reason, doc_kind, doc_ref, client_id, supplied_by, supplied_staff)
      values (n.ledger_id, n.unit_cost, 'item_average', 'run re-costed (production_recost116)', 'production', p_run::text, cl, auth.uid(), staff);
  end loop;
  if run.ledger_in_id is not null and not exists (select 1 from public.stock_ledger_eff96 l where l.id = run.ledger_in_id and coalesce(l.unit_cost, 0) > 0) and uc > 0 then
    insert into public.ledger_cost_supply96 (ledger_id, unit_cost, method, reason, doc_kind, doc_ref, client_id, supplied_by, supplied_staff)
      values (run.ledger_in_id, uc, 'from_ingredients', 'run re-costed (production_recost116)', 'production', p_run::text, cl, auth.uid(), staff);
  end if;
  perform public._cw_apply_avg116(cl, 'production', p_run::text);
  if acct and ent is not null then
    perform public._acct_reverse(ent, today_, 'Reversal: production re-costed');
    lines := '[]'::jsonb;
    for z in select * from public._acct_inv_split72(array['production'], p_run::text, array['issue_out'], -1) where amt > 0 loop
      lines := lines || jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt); sum_d := sum_d + z.amt;
    end loop;
    if round(conv, 2) >= 0.005 then lines := lines || jsonb_build_object('a', 'overhead_absorbed', 'c', round(conv, 2)); end if;
    lines := jsonb_build_array(jsonb_build_object('a', 'inv_finished', 'd', sum_d + case when round(conv, 2) >= 0.005 then round(conv, 2) else 0 end)) || lines;
    perform public._acct_write(today_, run.location_id, 'prod_recost116', p_run::text, null, 'Production re-costed (ingredient cost became known)', null, public._acct_resolve(lines, run.location_id));
  end if;
  return jsonb_build_object('dry', false, 'run_id', p_run, 'lines', items_, 'material_new', round(mat_new, 2), 'conversion', conv, 'unit_cost', uc, 'journal_reposted', acct and ent is not null);
end $$;

-- ---------- privileges ----------
revoke all on function public._recipe_reaches116(uuid, uuid), public._recipe_need116(uuid, numeric, integer, numeric), public._pool_rate_prov116(int, date, text), public._recipe_std_snap116(uuid, int, text, text, date),
  public._cw_apply_avg116(uuid, text, text), public._cw_run_recost116(uuid) from public, anon, authenticated;
revoke all on function public.recipe_std_set116(uuid, int, text), public.production_variance116(int, date, date, boolean), public.loc_cost_driver_set116(int, text, numeric, numeric, numeric), public.cost_type_driver_set116(text, text),
  public.production_cost_queue116(int, date, date), public.production_reprice116(int, date, boolean), public.recipe_stage_cost116(uuid, int), public.production_recost116(uuid, boolean) from public, anon;
grant execute on function public.recipe_std_set116(uuid, int, text), public.production_variance116(int, date, date, boolean), public.loc_cost_driver_set116(int, text, numeric, numeric, numeric), public.cost_type_driver_set116(text, text),
  public.production_cost_queue116(int, date, date), public.production_reprice116(int, date, boolean), public.recipe_stage_cost116(uuid, int), public.production_recost116(uuid, boolean) to authenticated;

-- ---------- setup advisor rows (advisory only; phase507 mechanism) ----------
insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort)
select v.code, v.code, v.phase, v.module, v.rec_value, v.ready_checks, v.reason_bn, v.reason_mix, v.reason_en, v.sort from (values
 ('semi_finished_ingredient116', '116', 'stock', null::jsonb, '{}'::text[],
  'আপনার কারখানায় ছানা / ডো-র মতো আধা-তৈরি মাল দিয়ে আরেকটা পণ্য বানানো হলে চালু করুন; তখন উৎপাদনে সেই মাল stock থেকে কমবে ও খরচ পরের পণ্যে যাবে। না হলে বন্ধ থাকুক।',
  'আপনার factory-তে ছানা / dough-এর মতো semi-finished মাল দিয়ে আরেকটা পণ্য বানানো হলে চালু করুন; তখন production-এ সেই মাল stock থেকে কমবে ও cost পরের পণ্যে যাবে। না হলে off থাকুক।',
  'Switch on only if your factory makes one product out of another (chhana into sweets, dough into biscuits): production then takes the semi-finished good out of stock and carries its cost into the next product. It depends on how you make things, so no value is recommended.', 360),
 ('packaging_on_actual_yield116', '116', 'stock', null::jsonb, '{}'::text[],
  'আসল উৎপাদন পরিকল্পনার চেয়ে কম বা বেশি হলে প্যাকেজিং যতটা সত্যিই লাগল ততটাই কমবে ও খরচে ধরবে; নইলে প্যাকেজিংয়ের stock ধীরে ধীরে ভুল হয়ে যায়। শুধু "উৎপাদনে প্যাকেজিং" নিয়মে প্রযোজ্য।',
  'আসল production পরিকল্পনার চেয়ে কম বা বেশি হলে packaging যতটা সত্যিই লাগল ততটাই কমবে ও cost-এ ধরবে; নইলে packaging stock ধীরে ধীরে ভুল হয়ে যায়। শুধু packaging_consume_on = production হলে প্রযোজ্য।',
  'When the quantity really made differs from the plan, packaging used and its cost follow the real quantity; otherwise the packaging stock drifts. Applies only with packaging_consume_on = production.', 361),
 ('std_snapshot_auto116', '116', 'stock', null::jsonb, '{}'::text[],
  'প্রথম উৎপাদনে রেসিপির standard খরচ রাখা হয়; পরে "কেন খরচ বাড়ল" (দাম / ব্যবহার / ফলন / ওভারহেড) দেখতে এটা লাগে। কিছু বদলায় না, শুধু একটি হিসাব জমে।',
  'প্রথম production-এ recipe-র standard cost রাখা হয়; পরে "কেন cost বাড়ল" (price / usage / yield / overhead) দেখতে এটা লাগে। কিছু বদলায় না, শুধু একটি হিসাব জমে।',
  'The first run stores the recipe standard; it is needed later to see why a cost went up (price, usage, yield, overhead). Nothing else changes.', 362),
 ('std_cost_true116', '116', 'stock', null::jsonb, '{}'::text[],
  'চালু করলে রান-তালিকার std_cost হবে সংরক্ষিত standard (রেসিপি × standard দাম), আগের মতো "আসল খরচ / তাত্ত্বিক উৎপাদন" নয়। আগে std_cost_snapshot (std_snapshot_auto116) চালু করে কিছু রান করুন।',
  'চালু করলে run-তালিকার std_cost হবে stored standard (recipe × standard price), আগের মতো "actual cost / theoretical output" নয়। আগে std_snapshot_auto116 চালু করে কিছু run করুন।',
  'When on, std_cost of a run is the stored standard (recipe x standard prices) instead of actual cost / theoretical output. Switch std_snapshot_auto116 on first and make some runs. The old number stays in cost_full_yield.', 363),
 ('pool_drivers116', '116', 'stock', null::jsonb, '{}'::text[],
  'পুল মোডে পিস / লিটারের পণ্যে রূপান্তর খরচ ধরতে বা শ্রম-ঘণ্টা / ব্যাচ অনুযায়ী ভাগ করতে চালু করুন; তারপর জায়গার driver ও "স্বাভাবিক মাসিক পরিমাণ" লিখুন। সংখ্যা আপনার নিজের, কোনো মান ধরে দেওয়া হয়নি।',
  'Pool mode-এ piece / litre-এর পণ্যে conversion cost ধরতে বা labour hour / batch অনুযায়ী ভাগ করতে চালু করুন; তারপর place-এর driver ও normal monthly quantity লিখুন। সংখ্যা আপনার নিজের, কোনো মান ধরে দেওয়া হয়নি।',
  'Switch on to give piece / litre products a conversion cost in pool mode, or to spread overhead by batches or labour hours; then type the driver and the normal monthly quantity. The numbers are yours; none is assumed.', 364),
 ('conv_provisional116', '116', 'stock', null::jsonb, '{}'::text[],
  'মাসের শুরুতে বিল আসার আগেই উৎপাদন হলে আজ রূপান্তর খরচ শূন্য ধরা হয়। চালু করলে আগের মাসের হারে সাময়িক খরচ বসে (চিহ্নিত), বিল এলে production_reprice116 দিয়ে ঠিক হয়। আপনার পুল-মোড কারখানায় এটাই সাধারণত ভালো।',
  'মাসের শুরুতে bill আসার আগেই production হলে আজ conversion cost শূন্য ধরা হয়। চালু করলে আগের মাসের rate-এ provisional cost বসে (flagged), bill এলে production_reprice116 দিয়ে ঠিক হয়।',
  'A run made early in the month, before the bills are in, gets conversion cost 0 today. With this on it gets the last month''s rate, flagged provisional, and production_reprice116 fixes it when the bills arrive. It depends on whether you use pool mode, so no value is recommended.', 365),
 ('cost_supply_to_avg116', '116', 'stock', null::jsonb, '{}'::text[],
  'cost-waiting তালিকায় দাম দিলে আজ তা শুধু খাতার overlay-তে থাকে, মালের গড় খরচ ফাঁকা থেকে যায় ও পরের উৎপাদন আবার আংশিক খরচে বুক হয়। চালু করলে দামটা গড় খরচেও বসে ও সেই উৎপাদন run-এর খরচ ঠিক হয়।',
  'Cost-waiting তালিকায় দাম দিলে আজ তা শুধু ledger overlay-তে থাকে, item-এর avg cost ফাঁকা থেকে যায় ও পরের production আবার partial cost-এ book হয়। চালু করলে দামটা avg cost-এও বসে ও সেই production run-এর cost ঠিক হয়।',
  'Today a cost typed in the cost-waiting list lives only in the ledger overlay: the item average stays blank and the next run is again booked at a partial cost. With this on the cost also reaches the item average and the run is re-costed.', 366)
) v(code, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort)
on conflict (code) do nothing;
