-- Phase 463 (RPT-C3, package R8 part 2) - AUDIT AND CONTROL: approval delays (#180), stock adjustment approval history (#174), missing cost / recipe / batch / expiry data (#183).
-- Paste AFTER phase462. Paste-twice safe. Read-only functions. No earlier phase file is edited.
--
--   aud_approval_delays      for every kind of request that waits for a person (form sheets, change requests, wastage, releases, emergency approvals, new list options, cash short cases,
--                            money requests): how many were asked, decided and are still waiting; clock hours from asked to decided (average, median, longest) by kind and by approver;
--                            and the oldest requests still waiting. Hours are clock hours (nights and holidays included). Nothing is called "late": no limit is invented.
--   aud_stock_adjustments    who asked for and who approved each stock adjustment: wastage requests, wastage recorded directly (no request, so no approver), count adjustments (through the
--                            counted sheet's approver, or direct) and transit-loss decisions. Unit value shown only to people who may see costs.
--   aud_cost_gaps            data that is missing and would make a profit or stock figure wrong: items with no cost price, finished goods with no active recipe, recipe lines with no waste
--                            percentage, ingredient / packaging with no cost under the chosen method (wraps d_recipe_cost_gaps), stock batches with no expiry date.
-- Access: rpt_access('control') (gaps: control OR stock) and the caller's places. Test data only (test_*).

do $g$ begin
  if to_regprocedure('public.aud_void_register(date,date,integer,text,integer)') is null then raise exception 'phase463 needs phase462 first'; end if;
end $g$;

create or replace function public._c3_hours(a timestamptz, b timestamptz) returns numeric language sql immutable as $$
  select case when a is null or b is null then null else round(extract(epoch from (b - a)) / 3600.0, 1) end
$$;

-- ---------- #180 approval delays ----------
create or replace function public._c3_requests(d1 date, d2 date, locs int[])
returns table (kind text, sub text, ref text, asked_by text, asked_at timestamptz, status text, decided_by text, decided_at timestamptz, location_id int)
language sql stable security definer set search_path = public as $$
  with x as (
    select 'form'::text k, e.form_code s, e.form_code || ' #' || e.serial as r, coalesce(e.created_staff, public._c3_staff(e.created_by)) as ab, e.submitted_at as aa,
           case e.status when 'submitted' then 'pending' else e.status end as st, e.checked_staff as db, e.checked_at as da, e.location_id as loc
      from public.entries e where e.submitted_at is not null and e.status in ('submitted', 'approved', 'rejected')
    union all select 'change_request', null, 'Change request ' || c.id, c.requested_staff, c.created_at, c.status, c.decided_staff, c.decided_at, (select e.location_id from public.entries e where e.id = c.entry_id)
      from public.entry_change_requests c
    union all select 'wastage', w.reason_code, 'Wastage request ' || left(w.id::text, 8), w.requested_staff, w.requested_at, w.status, w.decided_staff, w.decided_at, w.location_id
      from public.wastage_requests w
    union all select 'release', r.flag_code, 'Release request ' || r.id, r.requested_staff, r.requested_at, r.status, r.decided_staff, r.decided_at, (select e.location_id from public.entries e where e.id = r.entry_id)
      from public.release_requests r
    union all select 'emergency', g.grant_code, 'Emergency ' || g.id, g.requested_staff, g.created_at, g.status, g.decided_staff, g.decided_at, g.location_id
      from public.emergency_requests g
    union all select 'list_option', o.list_code, 'New option ' || coalesce(o.label_en, o.label_bn), public._c3_staff(o.requested_by), o.requested_at, o.status, public._c3_staff(o.decided_by), o.decided_at, null::int
      from public.option_requests o
    union all select 'cash_short', null, 'Cash short case ' || left(c.id::text, 8), null, c.created_at, case c.status when 'open' then 'pending' else c.status end, public._c3_staff(c.decided_by), c.decided_at, c.location_id
      from public.shortage_cash_cases c where c.status in ('open', 'approved', 'rejected')
    union all select 'money_request', q.kind, 'Money request ' || q.id, q.requested_staff, q.requested_at, q.status, q.decided_staff, q.decided_at, q.location_id
      from public.w1e_requests q)
  select x.k, x.s, x.r, x.ab, x.aa, x.st, x.db, x.da, x.loc from x
   where (x.aa at time zone 'Asia/Dhaka')::date between d1 and d2 and (x.loc is null or x.loc = any (locs))
$$;

create or replace function public.aud_approval_delays(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; bykind jsonb; byappr jsonb; pend jsonb; npend bigint; nodec bigint;
begin
  perform public._c3_need('control'); perform public._c3_range(p_from, p_to); locs := public._c3_locs(p_loc);
  if p_loc is not null and cardinality(locs) = 0 then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('kind', z.kind, 'asked', z.asked, 'decided', z.decided, 'approved', z.approved, 'rejected', z.rejected, 'pending', z.pending, 'cancelled_or_other', z.other,
          'avg_hours', z.avg_h, 'median_hours', z.med_h, 'max_hours', z.max_h) order by z.kind), '[]'::jsonb) into bykind
    from (select r.kind, count(*) as asked, count(*) filter (where r.decided_at is not null) as decided, count(*) filter (where r.status = 'approved') as approved,
                 count(*) filter (where r.status = 'rejected') as rejected, count(*) filter (where r.status = 'pending') as pending,
                 count(*) filter (where r.status not in ('pending', 'approved', 'rejected')) as other,
                 round(avg(public._c3_hours(r.asked_at, r.decided_at)), 1) as avg_h,
                 round((percentile_cont(0.5) within group (order by public._c3_hours(r.asked_at, r.decided_at)))::numeric, 1) as med_h,
                 max(public._c3_hours(r.asked_at, r.decided_at)) as max_h
            from public._c3_requests(p_from, p_to, locs) r where p_loc is null or r.location_id = p_loc group by r.kind) z;
  select coalesce(jsonb_agg(jsonb_build_object('approver', z.dby, 'decided', z.n, 'avg_hours', z.avg_h, 'max_hours', z.max_h) order by z.n desc, z.dby), '[]'::jsonb) into byappr
    from (select coalesce(r.decided_by, '(not recorded)') as dby, count(*) as n, round(avg(public._c3_hours(r.asked_at, r.decided_at)), 1) as avg_h, max(public._c3_hours(r.asked_at, r.decided_at)) as max_h
            from public._c3_requests(p_from, p_to, locs) r where r.decided_at is not null and (p_loc is null or r.location_id = p_loc) group by 1) z;
  select count(*), count(*) filter (where r.decided_at is not null and r.decided_by is null) into npend, nodec from public._c3_requests(p_from, p_to, locs) r where r.status = 'pending' and (p_loc is null or r.location_id = p_loc);
  select coalesce(jsonb_agg(to_jsonb(z) order by z.age_hours desc), '[]'::jsonb) into pend from (
    select r.kind, r.sub, r.ref, r.asked_by, r.asked_at, public._c3_hours(r.asked_at, now()) as age_hours, r.location_id
      from public._c3_requests(p_from, p_to, locs) r where r.status = 'pending' and (p_loc is null or r.location_id = p_loc) order by r.asked_at limit 200) z;
  select count(*) into nodec from public._c3_requests(p_from, p_to, locs) r where r.decided_at is not null and r.decided_by is null and (p_loc is null or r.location_id = p_loc);
  return jsonb_build_object('key', 'aud_approvals', 'from', p_from, 'to', p_to, 'loc', p_loc, 'by_kind', bykind, 'by_approver', byappr, 'pending', pend,
    'totals', jsonb_build_object('pending', npend, 'decided_without_approver_name', nodec),
    'notes', jsonb_build_array('clock_hours_not_working_hours', 'no_late_limit_invented', 'dated_by_the_day_it_was_asked'),
    'basis', 'Hours from "asked" to "decided" on the clock. The list shows the oldest requests still waiting, with their age now.');
end $$;

-- ---------- #174 stock adjustment approval history ----------
create or replace function public._c3_stockadj(d1 date, d2 date, locs int[])
returns table (kind text, rec_id text, on_date date, item_id uuid, qty numeric, unit_cost numeric, reason text, asked_by text, asked_at timestamptz, approver text, decided_at timestamptz,
               status text, note text, location_id int, route text)
language sql stable security definer set search_path = public as $$
  select 'wastage_request'::text, w.id::text, (w.requested_at at time zone 'Asia/Dhaka')::date, w.item_id, -w.qty, null::numeric, w.reason_code, w.requested_staff, w.requested_at, w.decided_staff, w.decided_at, w.status, w.decision_note, w.location_id, 'wastage'::text
    from public.wastage_requests w where (w.requested_at at time zone 'Asia/Dhaka')::date between d1 and d2 and w.location_id = any (locs)
  union all
  select 'wastage_direct', s.id::text, (s.made_at at time zone 'Asia/Dhaka')::date, s.item_id, -s.qty, (select l.unit_cost from public.stock_ledger l where l.id = s.ledger_id), s.reason_code, s.created_staff, s.created_at, null, null, 'recorded', s.note, s.location_id, 'wastage'
    from public.stock_wastage s where (s.made_at at time zone 'Asia/Dhaka')::date between d1 and d2 and s.location_id = any (locs) and not exists (select 1 from public.wastage_requests w where w.wastage_id = s.id)
  union all
  select case when l.ref_type = 'entry' then 'count_sheet' else 'count_direct' end, l.id::text, (l.made_at at time zone 'Asia/Dhaka')::date, l.item_id, l.qty_delta, l.unit_cost, 'count_adjust',
         public._c3_staff(l.created_by), l.created_at, e.checked_staff, e.checked_at, case when l.ref_type = 'entry' then e.status else 'recorded' end, l.note, l.location_id, 'entry'
    from public.stock_ledger l left join public.entries e on l.ref_type = 'entry' and e.id::text = l.ref_id
   where l.reason = 'count_adjust' and (l.made_at at time zone 'Asia/Dhaka')::date between d1 and d2 and l.location_id = any (locs)
  union all
  select 'transit_loss', t.id::text, coalesce(t.received_on, (t.created_at at time zone 'Asia/Dhaka')::date), t.item_id, -t.qty_short, null, t.status, null, t.created_at, public._c3_staff(t.decided_by), t.decided_at, t.status, t.note, t.to_location_id, 'shortages'
    from public.shortage_transit t where coalesce(t.received_on, (t.created_at at time zone 'Asia/Dhaka')::date) between d1 and d2 and t.to_location_id = any (locs)
$$;

create or replace function public.aud_stock_adjustments(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; cost_ok boolean := public.rpt_cost_ok(); rows_ jsonb; bykind jsonb; noappr bigint;
begin
  perform public._c3_need('control'); perform public._c3_range(p_from, p_to); locs := public._c3_locs(p_loc);
  if p_loc is not null and cardinality(locs) = 0 then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(to_jsonb(z) order by z.on_date desc, z.kind), '[]'::jsonb) into rows_ from (
    select a.kind, a.rec_id, a.on_date, i.code as item_code, i.name_en as item_name, a.qty, case when cost_ok then a.unit_cost end as unit_cost,
           case when cost_ok and a.unit_cost is not null then round(a.qty * a.unit_cost, 2) end as value, a.reason, a.asked_by, a.asked_at, a.approver, a.decided_at,
           public._c3_hours(a.asked_at, a.decided_at) as hours_to_decide, a.status, a.note, a.location_id, a.route,
           (a.approver is null and a.status in ('approved', 'written_off', 'claimed', 'recovered')) as approver_missing
      from public._c3_stockadj(p_from, p_to, locs) a left join public.items i on i.id = a.item_id where p_loc is null or a.location_id = p_loc order by a.on_date desc, a.kind limit 2000) z;
  select coalesce(jsonb_agg(jsonb_build_object('kind', k.kind, 'n', k.n, 'with_approver', k.wa, 'without_approver', k.n - k.wa) order by k.kind), '[]'::jsonb) into bykind
    from (select a.kind, count(*) as n, count(*) filter (where a.approver is not null) as wa from public._c3_stockadj(p_from, p_to, locs) a where p_loc is null or a.location_id = p_loc group by a.kind) k;
  select count(*) into noappr from public._c3_stockadj(p_from, p_to, locs) a where a.approver is null and a.status in ('approved', 'written_off', 'claimed', 'recovered') and (p_loc is null or a.location_id = p_loc);
  return jsonb_build_object('key', 'aud_stockadj', 'from', p_from, 'to', p_to, 'loc', p_loc, 'rows', rows_, 'by_kind', bykind, 'totals', jsonb_build_object('rows', jsonb_array_length(rows_), 'approver_missing', noappr),
    'notes', jsonb_build_array('direct_wastage_has_no_request', 'qty_negative_is_stock_out') || case when cost_ok then '[]'::jsonb else jsonb_build_array('cost_hidden') end,
    'basis', 'Each adjustment of stock with who asked, who decided and how long it took. "Direct" entries had no request, so there is no approver to show.');
end $$;

-- ---------- #183 missing cost, recipe, batch or expiry data ----------
create or replace function public.aud_cost_gaps(p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; s1 jsonb; s2 jsonb; s3 jsonb; s4 jsonb := '[]'; s5 jsonb; n1 bigint; n2 bigint; n3 bigint; n5 bigint; lc record; cost_hidden boolean := false; part jsonb; seen text[] := '{}'; rj jsonb;
begin
  if not public.is_active() or not (public.rpt_access('control') or public.rpt_access('stock')) then raise exception 'not allowed'; end if;
  locs := public._c3_locs(p_loc);
  if p_loc is not null and cardinality(locs) = 0 then raise exception 'not allowed'; end if;
  select count(*) into n1 from public.items i where i.is_active and i.count_in_business and coalesce(i.sellable, true) and not exists (select 1 from public.item_costs c where c.item_id = i.id and c.cost_price is not null);
  select coalesce(jsonb_agg(to_jsonb(z) order by z.code), '[]'::jsonb) into s1 from (
    select i.id as item_id, i.code, i.name_bn, i.name_en, i.item_type from public.items i
     where i.is_active and i.count_in_business and coalesce(i.sellable, true) and not exists (select 1 from public.item_costs c where c.item_id = i.id and c.cost_price is not null) order by i.code limit 300) z;
  select count(*) into n2 from public.items i where i.is_active and i.item_type = 'finished_good' and not exists (select 1 from public.recipes r where r.item_id = i.id and r.active);
  select coalesce(jsonb_agg(to_jsonb(z) order by z.code), '[]'::jsonb) into s2 from (
    select i.id as item_id, i.code, i.name_bn, i.name_en from public.items i
     where i.is_active and i.item_type = 'finished_good' and not exists (select 1 from public.recipes r where r.item_id = i.id and r.active) order by i.code limit 300) z;
  select count(*) into n3 from public.recipe_lines l join public.recipes r on r.id = l.recipe_id where l.active and r.active and l.waste_pct is null;
  select coalesce(jsonb_agg(to_jsonb(z) order by z.recipe_item, z.ingredient), '[]'::jsonb) into s3 from (
    select r.id as recipe_id, fi.code as recipe_item, ii.code as ingredient, ii.name_en as ingredient_name, l.qty, l.unit from public.recipe_lines l join public.recipes r on r.id = l.recipe_id
      join public.items fi on fi.id = r.item_id join public.items ii on ii.id = l.ingredient_item_id where l.active and r.active and l.waste_pct is null limit 300) z;
  for lc in select x.id from public.locations x where x.id = any (locs) order by x.id loop
    begin
      part := public.d_recipe_cost_gaps(lc.id);
      for rj in select * from jsonb_array_elements(part) loop
        if not ((rj ->> 'item_id') = any (seen)) then seen := seen || (rj ->> 'item_id'); s4 := s4 || jsonb_build_array(rj || jsonb_build_object('location_id', lc.id)); end if;
      end loop;
    exception when others then cost_hidden := true;
    end;
  end loop;
  select count(*) into n5 from public.stock_batches b where b.qty_remaining > 0 and b.expires_at is null and b.location_id = any (locs) and (p_loc is null or b.location_id = p_loc);
  select coalesce(jsonb_agg(to_jsonb(z) order by z.made_at), '[]'::jsonb) into s5 from (
    select b.id as batch_id, b.batch_no, i.code, i.name_en, b.location_id, b.made_at, b.qty_remaining from public.stock_batches b join public.items i on i.id = b.item_id
     where b.qty_remaining > 0 and b.expires_at is null and b.location_id = any (locs) and (p_loc is null or b.location_id = p_loc) order by b.made_at limit 300) z;
  return jsonb_build_object('key', 'aud_gaps', 'loc', p_loc,
    'sections', jsonb_build_object(
      'item_no_cost', jsonb_build_object('total', n1, 'rows', s1), 'fg_no_recipe', jsonb_build_object('total', n2, 'rows', s2),
      'recipe_waste_missing', jsonb_build_object('total', n3, 'rows', s3), 'ingredient_no_cost', jsonb_build_object('total', jsonb_array_length(s4), 'rows', s4, 'cost_hidden', cost_hidden),
      'batch_no_expiry', jsonb_build_object('total', n5, 'rows', s5)),
    'notes', jsonb_build_array('lists_show_up_to_300_rows_each_total_is_exact', 'no_cost_means_profit_is_only_on_the_costed_part') || case when cost_hidden then jsonb_build_array('ingredient_costs_need_the_cost_right') else '[]'::jsonb end,
    'basis', 'Records the books depend on that are not filled in. A missing cost price is not shown as 0 anywhere; these lists show where that happens.');
end $$;

revoke all on function public._c3_hours(timestamptz, timestamptz), public._c3_requests(date, date, int[]), public._c3_stockadj(date, date, int[]) from public, anon, authenticated;
revoke all on function public.aud_approval_delays(date, date, int), public.aud_stock_adjustments(date, date, int), public.aud_cost_gaps(int) from public, anon;
grant execute on function public.aud_approval_delays(date, date, int), public.aud_stock_adjustments(date, date, int), public.aud_cost_gaps(int) to authenticated;
notify pgrst, 'reload schema';
