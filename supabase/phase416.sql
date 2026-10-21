-- Phase 416 (bos416) - RPT-B4 / R9b: FACTORY VS RETAIL (#7) AND THE AUDIT LINE FOR THE CSV OF EVERY NEW REPORT OF THIS PACKAGE.
-- Paste after phase415 (and after 406-413 for the export keys to be useful; the report itself needs 404, 409, 410 and 415; the guard below says so). Paste-twice safe. Read only. No earlier phase file is edited.
--
--   rb4_factory_vs_retail(from, to)   three blocks side by side, per place the reader may see:
--     factory   what each factory place produced (runs, output per item, the cost booked on the runs) and what it sent to the shops;
--     transfers factory -> shop per item: quantity sent / received, the ledger cost of the goods, and their value under the owner's basis (setting transfer_valuation_basis, default none = "not valued");
--     retail    each shop: sales net of returns, the cost of goods sold from the ledger, gross profit on the part whose cost is known.
--   Shop gross profit is at ledger cost (what the system books). It is NOT reduced by a transfer value: the report puts the factory margin on transfers next to it and never nets the two.
--   Cost and value columns appear only for readers with the cost right at that place; a missing cost is "cost not captured", never 0.
--   rb4_log_export(key, kind, filters, rows)   the audit line written BEFORE a CSV of one of these reports is built (same rule as log_page_export: the owner or the export right, plus the right to read the report).

do $g$ begin
  if to_regprocedure('public._rb4_transfer_value(uuid,numeric,numeric,text,numeric)') is null then raise exception 'phase416 needs phase415 first'; end if;
  if to_regprocedure('public._rb4_target_view(int)') is null then raise exception 'phase416 needs phase409 (reader checks)'; end if;
  if to_regprocedure('public._rb4_sales_days(date,date,int[])') is null then raise exception 'phase416 needs phase410 (daily sales helper)'; end if;
end $g$;

create or replace function public.rb4_factory_vs_retail(p_from date default null, p_to date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date; t date; basis text := coalesce(public.rule_txt('transfer_valuation_basis'), 'none'); pct numeric := public.rule_num('transfer_price_pct'); net_on boolean := coalesce(public.rule_on('reports_net_of_returns'), true);
        facs int[]; rets int[]; costfac int[]; costret int[]; fac_rows jsonb; tr_rows jsonb; ret_rows jsonb; fac_tot jsonb; tr_tot jsonb; ret_tot jsonb; notes jsonb := '[]'::jsonb; hidden boolean;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select x.f, x.t into f, t from public._rb4_range(p_from, p_to) x;
  select coalesce(array_agg(l.id), '{}') into facs from public.locations l where l.kind = 'factory' and (public._rb4_prod_view(l.id) or public._rb4_target_view(l.id));
  select coalesce(array_agg(l.id), '{}') into rets from public.locations l where l.kind = 'showroom' and (public._rb4_target_view(l.id) or public._rb4_prod_view(l.id));
  select coalesce(array_agg(x), '{}') into costfac from unnest(facs) x where public._cost_ok(x);
  select coalesce(array_agg(x), '{}') into costret from unnest(rets) x where public._cost_ok(x);
  hidden := cardinality(costfac) < cardinality(facs) or cardinality(costret) < cardinality(rets);

  -- factory side: production per place and item
  select coalesce(jsonb_agg(jsonb_build_object('location_id', z.loc, 'location', l.name_bn, 'location_en', l.name_en, 'item_id', z.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(z.item_id),
        'runs', z.runs, 'output', z.qty, 'costed_runs', case when z.loc = any (costfac) then z.costed end,
        'production_cost', case when z.loc = any (costfac) and z.costed = z.runs then round(z.cost, 2) end,
        'cost_state', case when not (z.loc = any (costfac)) then 'cost_hidden' when z.costed < z.runs then 'cost_not_captured' else 'known' end) order by l.sort, i.code), '[]'::jsonb) into fac_rows
    from (select r.location_id as loc, r.item_id, count(*) as runs, sum(r.yield_base) as qty, count(*) filter (where r.cost_complete and r.material_cost is not null and coalesce(r.conversion_complete, true)) as costed,
                 sum(coalesce(r.material_cost, 0) + coalesce(r.conversion_cost, 0)) as cost
            from public.production_runs r where r.status = 'done' and public._rb4_day(r.made_at) between f and t and r.location_id = any (facs) group by 1, 2) z
    join public.items i on i.id = z.item_id join public.locations l on l.id = z.loc;

  -- transfers factory -> shop, one value per transfer then grouped
  with tr as (
    select s.id, s.from_location_id as fl, s.to_location_id as tl, s.item_id, s.qty, s.status, s.received_qty,
           (select sum(-l.qty_delta * coalesce(l.unit_cost, 0)) from public.stock_ledger l where l.ref_type = 'transfer' and l.ref_id = s.id::text and l.reason = 'transfer_out') as cost_val,
           (select bool_and(coalesce(l.unit_cost, 0) > 0) from public.stock_ledger l where l.ref_type = 'transfer' and l.ref_id = s.id::text and l.reason = 'transfer_out') as cost_known
      from public.stock_transfers s
     where s.status in ('sent', 'received') and public._rb4_day(s.sent_at) between f and t and s.from_location_id = any (facs)
       and exists (select 1 from public.locations d where d.id = s.to_location_id and d.kind = 'showroom')),
  v as (
    select tr.*, (public._rb4_transfer_value(tr.item_id, tr.qty, case when tr.cost_known and tr.qty > 0 then tr.cost_val / tr.qty end, basis, pct)).value as tv,
                 (public._rb4_transfer_value(tr.item_id, tr.qty, case when tr.cost_known and tr.qty > 0 then tr.cost_val / tr.qty end, basis, pct)).state as tstate
      from tr)
  select coalesce(jsonb_agg(jsonb_build_object('from_location_id', g.fl, 'from_location', fo.name_bn, 'from_location_en', fo.name_en, 'to_location_id', g.tl, 'to_location', tlo.name_bn, 'to_location_en', tlo.name_en,
        'item_id', g.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(g.item_id), 'transfers', g.n, 'sent', g.qty, 'received', coalesce(g.rec, 0), 'in_transit', coalesce(g.transit, 0),
        'cost_value', case when g.fl = any (costfac) and g.cost_unknown = 0 then round(g.cost_val, 2) end,
        'cost_state', case when not (g.fl = any (costfac)) then 'cost_hidden' when g.cost_unknown > 0 then 'cost_not_captured' else 'known' end,
        'transfer_value', case when g.fl = any (costfac) and g.val_unknown = 0 then round(g.tv, 2) end,
        'value_state', case when not (g.fl = any (costfac)) then 'cost_hidden' when basis = 'none' then 'not_valued' when g.val_unknown > 0 then (select min(v2.tstate) from v v2 where v2.fl = g.fl and v2.tl = g.tl and v2.item_id = g.item_id and v2.tv is null) else basis end,
        'margin', case when g.fl = any (costfac) and g.cost_unknown = 0 and g.val_unknown = 0 and basis <> 'none' then round(g.tv - g.cost_val, 2) end) order by fo.sort, tlo.sort, i.code), '[]'::jsonb) into tr_rows
    from (select v.fl, v.tl, v.item_id, count(*) as n, sum(v.qty) as qty, sum(coalesce(v.received_qty, 0)) filter (where v.status = 'received') as rec, sum(v.qty) filter (where v.status = 'sent') as transit,
                 sum(v.cost_val) as cost_val, count(*) filter (where not coalesce(v.cost_known, false)) as cost_unknown, sum(v.tv) as tv, count(*) filter (where v.tv is null) as val_unknown
            from v group by 1, 2, 3) g
    join public.items i on i.id = g.item_id join public.locations fo on fo.id = g.fl join public.locations tlo on tlo.id = g.tl;

  -- retail side: each shop
  select coalesce(jsonb_agg(jsonb_build_object('location_id', z.loc, 'location', l.name_bn, 'location_en', l.name_en, 'gross_sales', z.gross, 'returns', z.ret, 'net_sales', z.gross - case when net_on then z.ret else 0 end, 'bills', z.bills,
        'cogs', case when z.loc = any (costret) and z.crev is not null then round(z.cogs, 2) end, 'costed_sales', case when z.loc = any (costret) and z.crev is not null then round(z.crev, 2) end,
        'gross_profit', case when z.loc = any (costret) and z.crev > 0 then round(z.crev - z.cogs, 2) end, 'gp_pct', case when z.loc = any (costret) and z.crev > 0 then round((z.crev - z.cogs) / z.crev * 100, 2) end,
        'uncosted_pct', case when z.loc = any (costret) and z.crev + coalesce(z.unk, 0) > 0 then round(coalesce(z.unk, 0) / (z.crev + coalesce(z.unk, 0)) * 100, 1) end,
        'cost_state', case when not (z.loc = any (costret)) then 'cost_hidden' when z.crev is null or z.crev <= 0 then 'cost_not_captured' else 'known' end) order by l.sort, z.loc), '[]'::jsonb) into ret_rows
    from (select s.loc, sum(s.gross) as gross, sum(s.returns_amt) as ret, sum(s.bills) as bills, c.crev, c.cogs, c.unk
            from public._rb4_sales_days(f, t, rets) s
            left join (select h.loc, sum((case h.src when 'sale' then 1 else -1 end) * (h.led_rev + h.fb_rev)) as crev, sum((case h.src when 'sale' then 1 else -1 end) * (h.led_cogs + h.fb_cogs)) as cogs,
                              sum((case h.src when 'sale' then 1 else -1 end) * h.unk_rev) as unk from public._cogs_lines72(f, t, costret) h group by 1) c on c.loc = s.loc
           group by s.loc, c.crev, c.cogs, c.unk) z join public.locations l on l.id = z.loc;

  select jsonb_build_object('runs', coalesce((select sum((e ->> 'runs')::int) from jsonb_array_elements(fac_rows) e), 0),
      'production_cost', (select sum((e ->> 'production_cost')::numeric) from jsonb_array_elements(fac_rows) e where e ->> 'cost_state' = 'known'),
      'items_not_costed', (select count(*) from jsonb_array_elements(fac_rows) e where e ->> 'cost_state' <> 'known')) into fac_tot;
  select jsonb_build_object('rows', jsonb_array_length(tr_rows), 'cost_value', (select sum((e ->> 'cost_value')::numeric) from jsonb_array_elements(tr_rows) e where e ->> 'cost_state' = 'known'),
      'transfer_value', (select sum((e ->> 'transfer_value')::numeric) from jsonb_array_elements(tr_rows) e where e -> 'transfer_value' <> 'null'::jsonb),
      'factory_margin', (select sum((e ->> 'margin')::numeric) from jsonb_array_elements(tr_rows) e where e -> 'margin' <> 'null'::jsonb),
      'rows_not_valued', (select count(*) from jsonb_array_elements(tr_rows) e where e -> 'transfer_value' = 'null'::jsonb)) into tr_tot;
  select jsonb_build_object('net_sales', (select sum((e ->> 'net_sales')::numeric) from jsonb_array_elements(ret_rows) e), 'gross_profit', (select sum((e ->> 'gross_profit')::numeric) from jsonb_array_elements(ret_rows) e where e -> 'gross_profit' <> 'null'::jsonb),
      'shops_without_cost', (select count(*) from jsonb_array_elements(ret_rows) e where e ->> 'cost_state' <> 'known')) into ret_tot;
  if basis = 'none' then notes := notes || jsonb_build_object('code', 'transfers_not_valued', 'field', 'transfer_valuation_basis'); end if;
  if basis = 'price_pct' and pct is null then notes := notes || jsonb_build_object('code', 'pct_not_set', 'field', 'transfer_price_pct'); end if;
  if cardinality(facs) = 0 then notes := notes || jsonb_build_object('code', 'no_factory_place', 'field', 'factory place'); end if;
  return jsonb_build_object('from', f, 'to', t, 'basis', basis, 'price_pct', pct, 'net_of_returns', net_on, 'cost_hidden', hidden, 'factory', jsonb_build_object('rows', fac_rows, 'totals', fac_tot),
    'transfers', jsonb_build_object('rows', tr_rows, 'totals', tr_tot), 'retail', jsonb_build_object('rows', ret_rows, 'totals', ret_tot), 'notes', notes,
    'statement', 'Shop gross profit is at ledger cost, the figure the system books. It is not reduced by a transfer value. The factory margin on transfers is shown next to it and the two are never netted here.');
end $$;

-- ---------- audit line for the CSV ----------
create or replace function public.rb4_log_export(p_key text, p_kind text, p_filters jsonb, p_rows int) returns void
language plpgsql security definer set search_path = public as $$
declare sid text; f jsonb := coalesce(p_filters, '{}'::jsonb); ok boolean; any_prod boolean; any_tgt boolean;
begin
  if not public.is_active() or not (public.is_owner() or public.rpt_grant('export_data')) then raise exception 'not allowed'; end if;
  if p_key is null or p_key not in ('plan_vs_actual', 'order_status', 'dispatch_recon', 'consumption', 'cost_variance', 'run_yield', 'losses', 'wastage_dim', 'labour_productivity', 'capacity',
                                    'target_report', 'kpi_trend', 'factory_vs_retail', 'production_runs', 'capacity_ratings', 'sales_targets') then
    raise exception 'unknown_report';
  end if;
  select exists (select 1 from public.locations l where public._rb4_prod_view(l.id)) into any_prod;
  select exists (select 1 from public.locations l where public._rb4_target_view(l.id)) into any_tgt;
  ok := case
    when p_key in ('target_report', 'kpi_trend', 'sales_targets') then any_tgt
    when p_key = 'factory_vs_retail' then any_prod or any_tgt
    else any_prod end;
  if not coalesce(ok, false) then raise exception 'not allowed'; end if;
  if p_kind is null or lower(p_kind) !~ '^[a-z0-9_]{1,20}$' then raise exception 'bad_kind'; end if;
  if length(f::text) > 4000 then f := jsonb_build_object('truncated', true); end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'export', 'report', p_key, jsonb_build_object('kind', lower(p_kind), 'rows', least(greatest(coalesce(p_rows, 0), 0), 100000000), 'filters', f));
end $$;

do $p$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('rb4_factory_vs_retail', 'rb4_log_export') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $p$;

notify pgrst, 'reload schema';
