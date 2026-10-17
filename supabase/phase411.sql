-- Phase 411 (bos411) - RPT-B4 / R5c: OUTLET TARGET TILE FOR THE OWNER BOARD.
-- Paste after phase410. Paste-twice safe. Read only. The owner board (web/ownerboard.js, phase45) keeps its own widget list; this phase gives the one function the new widget "target_vs" calls.
--
--   rb4_target_tile(month)   this month (or the month asked): per place with a target - target, achieved, achievement %, pace % (the share of the month gone, today counted), status - and one total line over the places that
--                            have a target. Places that sold something but have no target are listed by name ("target not set"). Nothing is invented: no target = no tile line.

do $g$ begin
  if to_regprocedure('public.rb4_target_report(date,date,int)') is null then raise exception 'phase411 needs phase410 first'; end if;
end $g$;

create or replace function public.rb4_target_tile(p_month date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m date := date_trunc('month', coalesce(p_month, public._rb4_today()))::date; rep jsonb; rows_ jsonb; tt_ numeric; ta_ numeric; pace numeric; notgt jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  rep := public.rb4_target_report(m, m, null);
  select coalesce(jsonb_agg(jsonb_build_object('location_id', e ->> 'location_id', 'location', e ->> 'location', 'location_en', e ->> 'location_en', 'target', e -> 'target', 'achieved', e -> 'achieved',
         'achievement_pct', e -> 'achievement_pct', 'pace_pct', e -> 'pace_pct', 'status', e ->> 'status', 'gp_pct', e -> 'gp_pct', 'gp_target_pct', e -> 'gp_target_pct') order by (e ->> 'location_id')::int), '[]'::jsonb) into rows_
    from jsonb_array_elements(rep -> 'rows') e where e ->> 'target_id' is not null;
  select coalesce(jsonb_agg(jsonb_build_object('location_id', e ->> 'location_id', 'location', e ->> 'location', 'location_en', e ->> 'location_en', 'achieved', e -> 'achieved') order by (e ->> 'location_id')::int), '[]'::jsonb) into notgt
    from jsonb_array_elements(rep -> 'rows') e where e ->> 'target_id' is null;
  select sum((e ->> 'target')::numeric), sum((e ->> 'achieved')::numeric), max((e ->> 'pace_pct')::numeric) into tt_, ta_, pace from jsonb_array_elements(rows_) e;
  return jsonb_build_object('month', m, 'rows', rows_, 'no_target', notgt,
    'total', case when jsonb_array_length(rows_) > 0 then jsonb_build_object('target', tt_, 'achieved', ta_, 'achievement_pct', case when tt_ > 0 then round(ta_ / tt_ * 100, 1) end, 'pace_pct', pace) end,
    'behind', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'status' in ('behind', 'closed_missed')),
    'notes', case when jsonb_array_length(rows_) = 0 then jsonb_build_array(jsonb_build_object('code', 'target_not_set', 'field', 'sales target')) else '[]'::jsonb end);
end $$;

revoke all on function public.rb4_target_tile(date) from public, anon;
grant execute on function public.rb4_target_tile(date) to authenticated;

notify pgrst, 'reload schema';
