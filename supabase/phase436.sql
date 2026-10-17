-- Phase 436 (bos436) - RPT-B3: AUDIT LINE FOR THE CSV EXPORT OF THE NEW REPORTS.
-- Paste after phase435. Paste-twice safe. Earlier phase files are not edited. log_page_export (phase13) accepts only the day book and the salary report, so the new reports get their own
-- function with the SAME rule: the owner or a holder of the export right (export_data), plus the right to read the report itself. The screen calls it BEFORE it builds the file; a refusal
-- means no file. One audit_log line per export: who, what, how many rows, which filters.
--   keys: trace, recall, quality_checks, transfer_damage, stockout, yield, shelf_life            (stock / quality report right, recall_manage, stockout_log)
--         supplier_returns, rejection, dependency, delivery, item_suppliers        (purchase report right; rejection also the quality right)
--         price_variance, agreed_prices                                            (purchase report right AND the cost right: they show prices)

do $g$ begin
  if to_regprocedure('public._rb3_purch_ok()') is null then raise exception 'phase436 needs phase435 first'; end if;
end $g$;

create or replace function public.rb3_log_export(p_key text, p_kind text, p_filters jsonb, p_rows int) returns void
language plpgsql security definer set search_path = public as $$
declare sid text; f jsonb := coalesce(p_filters, '{}'::jsonb); ok boolean;
begin
  if not public.is_active() or not (public.is_owner() or public.rpt_grant('export_data')) then raise exception 'not allowed'; end if;
  if p_key is null or p_key not in ('trace', 'recall', 'quality_checks', 'transfer_damage', 'stockout', 'yield', 'shelf_life', 'supplier_returns', 'rejection', 'dependency', 'delivery', 'item_suppliers', 'price_variance', 'agreed_prices') then
    raise exception 'unknown_report';
  end if;
  ok := case
    when p_key in ('trace', 'recall', 'quality_checks', 'transfer_damage', 'yield', 'shelf_life') then public.is_owner() or public.rpt_access('stock') or public.rpt_access('quality') or public.has_grant('recall_manage')
    when p_key = 'stockout' then public.is_owner() or public.rpt_access('stock') or exists (select 1 from public.locations l where public.can_loc(l.id) and public.has_grant('stockout_log', l.id))
    when p_key = 'rejection' then public.is_owner() or public.rpt_access('purchase') or public.rpt_access('quality')
    when p_key in ('supplier_returns', 'dependency', 'delivery', 'item_suppliers') then public.is_owner() or public.rpt_access('purchase')
    else public.is_owner() or (public.rpt_access('purchase') and public.rpt_cost_ok()) or public.has_grant('supplier_terms_manage')
  end;
  if not coalesce(ok, false) then raise exception 'not allowed'; end if;
  if p_kind is null or lower(p_kind) !~ '^[a-z0-9_]{1,20}$' then raise exception 'bad_kind'; end if;
  if length(f::text) > 4000 then f := jsonb_build_object('truncated', true); end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'export', 'report', p_key, jsonb_build_object('kind', lower(p_kind), 'rows', least(greatest(coalesce(p_rows, 0), 0), 100000000), 'filters', f));
end $$;

revoke all on function public.rb3_log_export(text, text, jsonb, int) from public, anon;
grant execute on function public.rb3_log_export(text, text, jsonb, int) to authenticated;

notify pgrst, 'reload schema';
