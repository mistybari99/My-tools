-- Phase 408 (bos408) - RPT-B4 / R4c: RUN-LEVEL YIELD VS STANDARD (#45), REJECT / REWORK / PRODUCTION LOSS (#49), WASTAGE WITH THE BATCH AND PRODUCTION-RUN DIMENSION (#50).
-- Paste after phase407. Paste-twice safe. Read only: nothing here moves stock or money. No earlier phase file is edited.
--
--   rb4_run_yield(from, to, place, item)         one row per finished run: standard output, the output the person typed (blank = "not captured"), the difference and %, and the owner's warning limit
--                                                (rule yield_variance_warn_pct; blank limit = no flag, said in words). Another package may also list the same runs; the numbers come from production_runs only.
--   rb4_losses(from, to, place, item)            reject / rework per run (prod_loss_add): the run's state is recorded / checked-none / not captured. Percentages use only runs whose state is known.
--   rb4_wastage_dim(from, to, place, item)       the wastage records with the batch they were taken from and, when that batch was made by a production run, the run; by reason, item and batch.
--                                                Value = quantity x the ledger cost of the write-off, shown only with the cost right and only where the cost is known.

do $g$ begin
  if to_regprocedure('public.rb4_cost_variance(date,date,int,uuid)') is null then raise exception 'phase408 needs phase407 first'; end if;
end $g$;

create or replace function public.rb4_run_yield(p_from date default null, p_to date default null, p_loc int default null, p_item uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date; t date; thr numeric := public.rule_num('yield_variance_warn_pct'); rows_ jsonb; sm jsonb; trunc boolean; notes jsonb := '[]'::jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select x.f, x.t into f, t from public._rb4_range(p_from, p_to) x;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  with runs as (
    select r.* from public.production_runs r where r.status = 'done' and public._rb4_day(r.made_at) between f and t and (p_loc is null or r.location_id = p_loc) and (p_item is null or r.item_id = p_item) and public._rb4_prod_view(r.location_id)
     order by r.made_at desc limit 2001)
  select (select count(*) > 2000 from runs),
         coalesce(jsonb_agg(jsonb_build_object('run_id', r.id, 'day', public._rb4_day(r.made_at), 'location_id', r.location_id, 'location', l.name_bn, 'location_en', l.name_en,
           'item_id', r.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(r.item_id), 'batches', r.batches,
           'yield_std', r.yield_std, 'yield_actual', r.yield_actual, 'booked_output', r.yield_base,
           'var_qty', case when r.yield_actual is not null and r.yield_std is not null then round(r.yield_actual - r.yield_std, 4) end,
           'var_pct', case when r.yield_actual is not null and r.yield_std > 0 then round((r.yield_actual - r.yield_std) / r.yield_std * 100, 2) end,
           'status', case when r.yield_std is null then 'standard_not_captured' when r.yield_actual is null then 'not_captured' else 'measured' end,
           'over_limit', case when thr is not null and r.yield_actual is not null and r.yield_std > 0 then abs((r.yield_actual - r.yield_std) / r.yield_std * 100) > thr end) order by r.made_at desc), '[]'::jsonb)
    into trunc, rows_
    from (select * from runs limit 2000) r join public.items i on i.id = r.item_id join public.locations l on l.id = r.location_id;
  select coalesce(jsonb_agg(jsonb_build_object('item_id', g.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(g.item_id),
        'runs', g.runs, 'measured', g.m, 'not_captured', g.runs - g.m, 'std_qty_measured', case when g.m > 0 then g.s_std end, 'actual_qty_measured', case when g.m > 0 then g.s_act end,
        'var_pct', case when g.m > 0 and g.s_std > 0 then round((g.s_act - g.s_std) / g.s_std * 100, 2) end, 'over_limit_runs', case when thr is not null then g.over end) order by i.code), '[]'::jsonb) into sm
    from (select (e ->> 'item_id')::uuid as item_id, count(*) as runs, count(*) filter (where e ->> 'status' = 'measured') as m,
                 sum((e ->> 'yield_std')::numeric) filter (where e ->> 'status' = 'measured') as s_std, sum((e ->> 'yield_actual')::numeric) filter (where e ->> 'status' = 'measured') as s_act,
                 count(*) filter (where (e ->> 'over_limit')::boolean) as over
            from jsonb_array_elements(rows_) e group by 1) g join public.items i on i.id = g.item_id;
  if thr is null then notes := notes || jsonb_build_object('code', 'limit_not_set', 'field', 'yield_variance_warn_pct'); end if;
  if jsonb_array_length(rows_) > 0 and not exists (select 1 from jsonb_array_elements(rows_) e where e ->> 'status' = 'measured') then notes := notes || jsonb_build_object('code', 'actual_yield_not_captured', 'field', 'actual yield'); end if;
  return jsonb_build_object('from', f, 'to', t, 'rows', rows_, 'summary', sm, 'limit_pct', thr, 'truncated', coalesce(trunc, false), 'notes', notes);
end $$;

create or replace function public.rb4_losses(p_from date default null, p_to date default null, p_loc int default null, p_item uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date; t date; rows_ jsonb; reasons jsonb; sm jsonb; items_ jsonb; trunc boolean; notes jsonb := '[]'::jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select x.f, x.t into f, t from public._rb4_range(p_from, p_to) x;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  with runs as (
    select r.* from public.production_runs r where r.status = 'done' and public._rb4_day(r.made_at) between f and t and (p_loc is null or r.location_id = p_loc) and (p_item is null or r.item_id = p_item) and public._rb4_prod_view(r.location_id)
     order by r.made_at desc limit 2001),
  agg as (
    select r.id, coalesce(sum(x.qty) filter (where x.kind = 'reject'), 0) as rej, coalesce(sum(x.qty) filter (where x.kind = 'rework'), 0) as rew,
           count(*) filter (where x.kind in ('reject', 'rework')) as recorded_n, count(*) filter (where x.kind = 'none') as none_n,
           coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'kind', x.kind, 'qty', x.qty, 'reason_code', x.reason_code, 'reason', o.label_en, 'reason_bn', o.label_bn, 'note', x.note) order by x.created_at) filter (where x.kind in ('reject', 'rework')), '[]'::jsonb) as lines
      from runs r left join public.production_loss x on x.run_id = r.id and x.status = 'active'
      left join public.option_lists o on o.list_code = 'wastage_reasons' and o.value_code = x.reason_code group by r.id)
  select (select count(*) > 2000 from runs),
         coalesce(jsonb_agg(jsonb_build_object('run_id', r.id, 'day', public._rb4_day(r.made_at), 'location_id', r.location_id, 'location', l.name_bn, 'location_en', l.name_en,
           'item_id', r.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(r.item_id), 'output', r.yield_base,
           'state', case when a.recorded_n > 0 then 'recorded' when a.none_n > 0 then 'none' else 'not_captured' end,
           'reject_qty', case when a.recorded_n > 0 or a.none_n > 0 then a.rej end, 'rework_qty', case when a.recorded_n > 0 or a.none_n > 0 then a.rew end,
           'reject_pct', case when (a.recorded_n > 0 or a.none_n > 0) and r.yield_base > 0 then round(a.rej / r.yield_base * 100, 2) end,
           'rework_pct', case when (a.recorded_n > 0 or a.none_n > 0) and r.yield_base > 0 then round(a.rew / r.yield_base * 100, 2) end, 'lines', a.lines) order by r.made_at desc), '[]'::jsonb)
    into trunc, rows_
    from (select * from runs limit 2000) r join agg a on a.id = r.id join public.items i on i.id = r.item_id join public.locations l on l.id = r.location_id;

  select coalesce(jsonb_agg(jsonb_build_object('reason_code', z.rc, 'reason', o.label_en, 'reason_bn', o.label_bn, 'reject_n', z.rn, 'rework_n', z.wn) order by z.rn + z.wn desc, z.rc), '[]'::jsonb) into reasons
    from (select l ->> 'reason_code' as rc, count(*) filter (where l ->> 'kind' = 'reject') as rn, count(*) filter (where l ->> 'kind' = 'rework') as wn
            from jsonb_array_elements(rows_) e, jsonb_array_elements(e -> 'lines') l group by 1) z left join public.option_lists o on o.list_code = 'wastage_reasons' and o.value_code = z.rc;
  select coalesce(jsonb_agg(jsonb_build_object('item_id', g.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(g.item_id),
        'runs', g.runs, 'runs_known', g.known, 'runs_not_captured', g.runs - g.known, 'output_known', case when g.known > 0 then g.out_k end, 'reject_qty', case when g.known > 0 then g.rej end, 'rework_qty', case when g.known > 0 then g.rew end,
        'reject_pct', case when g.known > 0 and g.out_k > 0 then round(g.rej / g.out_k * 100, 2) end, 'rework_pct', case when g.known > 0 and g.out_k > 0 then round(g.rew / g.out_k * 100, 2) end) order by i.code), '[]'::jsonb) into items_
    from (select (e ->> 'item_id')::uuid as item_id, count(*) as runs, count(*) filter (where e ->> 'state' <> 'not_captured') as known,
                 sum((e ->> 'output')::numeric) filter (where e ->> 'state' <> 'not_captured') as out_k, sum((e ->> 'reject_qty')::numeric) filter (where e ->> 'state' <> 'not_captured') as rej,
                 sum((e ->> 'rework_qty')::numeric) filter (where e ->> 'state' <> 'not_captured') as rew
            from jsonb_array_elements(rows_) e group by 1) g join public.items i on i.id = g.item_id;
  select jsonb_build_object('runs', jsonb_array_length(rows_), 'recorded', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'state' = 'recorded'),
      'none', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'state' = 'none'), 'not_captured', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'state' = 'not_captured')) into sm;
  if (sm ->> 'runs')::int > 0 and (sm ->> 'recorded')::int + (sm ->> 'none')::int = 0 then notes := notes || jsonb_build_object('code', 'loss_not_captured', 'field', 'reject and rework'); end if;
  return jsonb_build_object('from', f, 'to', t, 'rows', rows_, 'by_reason', reasons, 'by_item', items_, 'summary', sm, 'truncated', coalesce(trunc, false), 'notes', notes,
    'basis', 'A reject or rework is a record, not a stock movement: the output of the run is as booked. Percentages use only runs whose state is known (recorded, or checked and none). Stock written off is in the wastage report.');
end $$;

create or replace function public.rb4_wastage_dim(p_from date default null, p_to date default null, p_loc int default null, p_item uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date; t date; rows_ jsonb; by_reason jsonb; by_item jsonb; by_batch jsonb; trunc boolean; hidden boolean := false; sm jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select x.f, x.t into f, t from public._rb4_range(p_from, p_to) x;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  select exists (select 1 from public.stock_wastage w where public._rb4_day(w.made_at) between f and t and (p_loc is null or w.location_id = p_loc) and public._rb4_prod_view(w.location_id) and not public._cost_ok(w.location_id)) into hidden;
  with w as (
    select w.*, b.made_at as batch_made, b.qty_made as batch_qty, r.id as run_id, public._cost_ok(w.location_id) as money,
           case when lg.unit_cost is not null and lg.unit_cost > 0 then lg.unit_cost end as ucost
      from public.stock_wastage w
      left join public.stock_batches b on b.id = w.batch_id
      left join public.production_runs r on r.batch_id = w.batch_id and r.status = 'done'
      left join public.stock_ledger lg on lg.id = w.ledger_id
     where public._rb4_day(w.made_at) between f and t and (p_loc is null or w.location_id = p_loc) and (p_item is null or w.item_id = p_item) and public._rb4_prod_view(w.location_id)
     order by w.made_at desc limit 2001)
  select (select count(*) > 2000 from w),
         coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'day', public._rb4_day(x.made_at), 'location_id', x.location_id, 'location', l.name_bn, 'location_en', l.name_en,
           'item_id', x.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(x.item_id), 'qty', x.qty,
           'reason_code', x.reason_code, 'reason', o.label_en, 'reason_bn', o.label_bn,
           'batch_id', x.batch_id, 'batch_made_at', x.batch_made, 'run_id', x.run_id, 'batch_state', case when x.batch_id is null then 'batch_not_captured' when x.run_id is null then 'not_from_a_run' else 'from_run' end,
           'value', case when x.money and x.ucost is not null then round(x.qty * x.ucost, 2) end, 'value_state', case when not x.money then 'cost_hidden' when x.ucost is null then 'cost_not_captured' else 'known' end,
           'note', x.note, 'created_staff', x.created_staff) order by x.made_at desc), '[]'::jsonb)
    into trunc, rows_
    from (select * from w limit 2000) x join public.items i on i.id = x.item_id join public.locations l on l.id = x.location_id left join public.option_lists o on o.list_code = 'wastage_reasons' and o.value_code = x.reason_code;

  select coalesce(jsonb_agg(jsonb_build_object('reason_code', g.rc, 'reason', o.label_en, 'reason_bn', o.label_bn, 'records', g.n, 'value', case when g.vk > 0 then g.v end, 'value_known_n', g.vk, 'value_not_known_n', g.n - g.vk) order by g.n desc, g.rc), '[]'::jsonb) into by_reason
    from (select e ->> 'reason_code' as rc, count(*) as n, count(*) filter (where e ->> 'value_state' = 'known') as vk, sum((e ->> 'value')::numeric) as v from jsonb_array_elements(rows_) e group by 1) g
    left join public.option_lists o on o.list_code = 'wastage_reasons' and o.value_code = g.rc;
  select coalesce(jsonb_agg(jsonb_build_object('item_id', g.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(g.item_id), 'records', g.n, 'qty', g.q,
        'value', case when g.vk > 0 then g.v end, 'value_known_n', g.vk, 'value_not_known_n', g.n - g.vk) order by i.code), '[]'::jsonb) into by_item
    from (select (e ->> 'item_id')::uuid as item_id, count(*) as n, sum((e ->> 'qty')::numeric) as q, count(*) filter (where e ->> 'value_state' = 'known') as vk, sum((e ->> 'value')::numeric) as v from jsonb_array_elements(rows_) e group by 1) g
    join public.items i on i.id = g.item_id;
  select coalesce(jsonb_agg(jsonb_build_object('batch_id', g.bid, 'run_id', g.rid, 'batch_made_at', g.bm, 'item_id', g.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(g.item_id),
        'records', g.n, 'qty', g.q, 'value', case when g.vk > 0 then g.v end, 'value_not_known_n', g.n - g.vk) order by g.bm desc nulls last), '[]'::jsonb) into by_batch
    from (select (e ->> 'batch_id')::bigint as bid, (e ->> 'run_id')::uuid as rid, (e ->> 'batch_made_at')::timestamptz as bm, (e ->> 'item_id')::uuid as item_id, count(*) as n, sum((e ->> 'qty')::numeric) as q,
                 count(*) filter (where e ->> 'value_state' = 'known') as vk, sum((e ->> 'value')::numeric) as v
            from jsonb_array_elements(rows_) e where e ->> 'batch_id' is not null group by 1, 2, 3, 4) g join public.items i on i.id = g.item_id;
  select jsonb_build_object('records', jsonb_array_length(rows_), 'batch_not_captured', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'batch_state' = 'batch_not_captured'),
      'from_run', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'batch_state' = 'from_run'),
      'value_known_n', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'value_state' = 'known'),
      'value', (select sum((e ->> 'value')::numeric) from jsonb_array_elements(rows_) e where e ->> 'value_state' = 'known')) into sm;
  return jsonb_build_object('from', f, 'to', t, 'rows', rows_, 'by_reason', by_reason, 'by_item', by_item, 'by_batch', by_batch, 'summary', sm, 'cost_hidden', hidden, 'truncated', coalesce(trunc, false),
    'basis', 'Quantity is never added across different items. A value is shown only where the ledger cost of the write-off is known and the reader has the cost right; the others are counted as not known, never as 0.');
end $$;

do $p$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('rb4_run_yield', 'rb4_losses', 'rb4_wastage_dim') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $p$;

notify pgrst, 'reload schema';
