-- Phase 490 (X6) - THE SCHEDULED RESEARCH HOOK (OFF), the AI summariser slot (proposal only), competitor price alerts and the weekly owner digest. Paste AFTER phase489. Paste-twice safe.
-- Nothing here fetches anything. The job runner (X1 job_runs, phases 480-489) is NOT in this build: it will call mi_research_gate() before every run and mi_job_mark_run() after it. Until X1 is pasted and the owner switches the job on, no job runs.
-- The research GATE (every condition must hold; the reasons are returned in words):
--   mi_on and mi_research_job_on and mi_scrape_on are ON; the source is active; the owner has set terms_allow_scraping ON with a terms check date;
--   robots_ok is true and checked; a rate limit (requests per hour) is typed; the adapter is allowed to use the network (set by the owner, mi_adapter_set).
--   The mock adapter never uses the network and is the only adapter a test can run.
-- Never bypassed: logins, paywalls, bulk copying (findings keep the owner's own summary; quotes only within mi_quote_max_chars).

do $g$ begin
  if to_regprocedure('public.mi_finding_add(jsonb, uuid)') is null or to_regclass('public.notifications') is null then raise exception 'phase533 needs phase531 and the notifications base first'; end if;
end $g$;

create or replace function public.mi_research_gate(p_source uuid, p_adapter text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s public.mi_sources; a public.mi_adapters; why text[] := '{}'; ad text;
begin
  if not public._mi_on() then why := array_append(why, 'the market workspace is off'); end if;
  if not public.rule_on('mi_research_job_on') then why := array_append(why, 'scheduled research is off (mi_research_job_on)'); end if;
  if not public.rule_on('mi_scrape_on') then why := array_append(why, 'fetching of sources is off (mi_scrape_on)'); end if;
  select * into s from public.mi_sources where id = p_source;
  if not found or s.status <> 'active' then why := array_append(why, 'the source is not active or does not exist'); end if;
  if found and not s.terms_allow_scraping then why := array_append(why, 'the owner has not allowed scraping this source (terms flag is NO)'); end if;
  if found and s.terms_allow_scraping and s.terms_checked_on is null then why := array_append(why, 'terms check date is missing'); end if;
  if found and s.robots_ok is distinct from true then why := array_append(why, 'robots.txt check has not passed'); end if;
  if found and s.rate_limit_per_hour is null then why := array_append(why, 'no rate limit typed for this source'); end if;
  ad := coalesce(p_adapter, 'mock_offline');
  select * into a from public.mi_adapters where code = ad;
  if not found then why := array_append(why, 'unknown adapter'); elsif a.kind <> 'mock' and not a.network_allowed then why := array_append(why, 'the adapter may not use the network yet (owner has not linked it)'); end if;
  return jsonb_build_object('allowed', cardinality(why) = 0, 'reasons', to_jsonb(why), 'adapter', ad,
    'rule', 'Every condition must hold. Logins, paywalls and bulk copying are never used.');
end $$;

-- the owner links (or unlinks) an adapter to the network. Owner only; written to the change log.
create or replace function public.mi_adapter_set(p_code text, p_network_allowed boolean, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare sid text; a public.mi_adapters;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  if p_code = 'mock_offline' and p_network_allowed then raise exception 'mock_never_uses_network'; end if;
  update public.mi_adapters set network_allowed = coalesce(p_network_allowed, false) where code = p_code returning * into a;
  if not found then raise exception 'not_found'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'mi_adapter_set', 'mi_adapters', p_code, jsonb_build_object('network_allowed', a.network_allowed, 'reason', left(btrim(p_reason), 300)));
  return jsonb_build_object('code', p_code, 'network_allowed', a.network_allowed);
end $$;

-- a research job definition. Stored OFF. Turning it ON is refused unless the gate passes for its source.
create or replace function public.mi_job_save(p_key text, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d jsonb := coalesce(p, '{}'::jsonb); j public.mi_job_defs; want boolean := coalesce((d->>'enabled')::boolean, false); g jsonb; sid uuid := nullif(d->>'source_id', '')::uuid;
begin
  if not public._mi_on() then raise exception 'module_off: the market workspace is switched off'; end if;
  if not public.is_owner() then raise exception 'not allowed: only the owner schedules research'; end if;
  if want then
    if sid is null then raise exception 'source_required'; end if;
    g := public.mi_research_gate(sid, coalesce(d->>'adapter_code', 'mock_offline'));
    if not (g->>'allowed')::boolean then raise exception 'gate_closed: %', g->>'reasons'; end if;
  end if;
  insert into public.mi_job_defs (key, label, source_id, adapter_code, schedule_cron, enabled, created_by, updated_by)
    values (p_key, btrim(d->>'label'), sid, coalesce(d->>'adapter_code', 'mock_offline'), nullif(btrim(d->>'schedule_cron'), ''), want, auth.uid(), auth.uid())
    on conflict (key) do update set label = excluded.label, source_id = excluded.source_id, adapter_code = excluded.adapter_code,
      schedule_cron = excluded.schedule_cron, enabled = excluded.enabled, updated_by = auth.uid(), updated_at = now();
  return jsonb_build_object('key', p_key, 'enabled', want);
end $$;

-- written by the job runner after a run that the gate allowed (the runner itself is X1)
create or replace function public.mi_job_mark_run(p_key text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.mi_job_defs;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  update public.mi_job_defs set last_run_at = now() where key = p_key and enabled returning * into j;
  if not found then raise exception 'not_enabled'; end if;
  return jsonb_build_object('key', p_key, 'last_run_at', j.last_run_at);
end $$;

-- ---------- AI summariser: PROPOSALS only (the agent runs under a person's login; the person who asked can not accept it) ----------
create or replace function public.mi_summary_propose(p_finding_ids uuid[], p_text text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare n int; pr public.mi_summary_proposals;
begin
  if not public._mi_on() or not public.rule_on('mi_ai_summary_on') then raise exception 'module_off: the AI summariser is switched off'; end if;
  if not public._mi_can_manage() then raise exception 'not allowed'; end if;
  if cardinality(p_finding_ids) = 0 then raise exception 'findings_required'; end if;
  select count(*) into n from public.mi_findings where id = any (p_finding_ids);
  if n <> cardinality(p_finding_ids) then raise exception 'findings_not_found'; end if;
  insert into public.mi_summary_proposals (finding_ids, proposed_text, created_by) values (p_finding_ids, btrim(p_text), auth.uid()) returning * into pr;
  return jsonb_build_object('id', pr.id, 'status', 'proposed', 'note', 'A proposal only. Nothing is saved as a finding until a person accepts it and writes it as a finding.');
end $$;

create or replace function public.mi_summary_decide(p_id bigint, p_decision text, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pr public.mi_summary_proposals;
begin
  if not public._mi_can_manage() then raise exception 'not allowed'; end if;
  if p_decision not in ('accepted', 'rejected') then raise exception 'bad_decision'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  select * into pr from public.mi_summary_proposals where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if exists (select 1 from public.mi_summary_decisions d where d.proposal_id = p_id) then raise exception 'already_decided'; end if;
  if pr.created_by = auth.uid() then raise exception 'own_request: the person who asked can not accept it (build rule 8)'; end if;
  insert into public.mi_summary_decisions (proposal_id, decision, reason, decided_by) values (p_id, p_decision, left(btrim(p_reason), 300), auth.uid());
  return jsonb_build_object('id', p_id, 'status', p_decision);
end $$;

-- ---------- competitor price watchlist: the last two observations of each competitor item ----------
create or replace function public.mi_watch_alerts() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare th numeric := public.rule_num('mi_watch_threshold_pct'); rows_ jsonb;
begin
  if not public._mi_can_view() then raise exception 'not allowed'; end if;
  if th is null then return jsonb_build_object('threshold', null, 'alerts', '[]'::jsonb, 'note', 'Blank threshold: no competitor price alert is produced.'); end if;
  select coalesce(jsonb_agg(to_jsonb(z) order by abs(z.change_pct) desc), '[]'::jsonb) into rows_ from (
    select competitor, item_label, prev_price, price as last_price, prev_on, observed_on as last_on, round(100 * (price - prev_price) / prev_price, 1) as change_pct
      from (select o.*, lag(o.price) over (partition by lower(o.competitor), lower(o.item_label) order by o.observed_on, o.id) as prev_price,
                   lag(o.observed_on) over (partition by lower(o.competitor), lower(o.item_label) order by o.observed_on, o.id) as prev_on,
                   row_number() over (partition by lower(o.competitor), lower(o.item_label) order by o.observed_on desc, o.id desc) as rn
              from public.mi_price_obs o) q
     where rn = 1 and prev_price is not null and prev_price > 0 and abs(100 * (price - prev_price) / prev_price) > th) z;
  return jsonb_build_object('threshold', th, 'alerts', rows_, 'note', 'Each row: a competitor price that moved more than the threshold since its previous observation.');
end $$;

-- one in-app line per day for the owner when alerts exist and the switches allow it (counts only, no customer data)
create or replace function public.mi_alert_notify() returns jsonb
language plpgsql security definer set search_path = public as $$
declare n int; day_ date := public._mi_today(); made boolean := false; a jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if not (public._mi_on() and public.rule_on('mi_alerts_on')) then return jsonb_build_object('created', false, 'why', 'switched off'); end if;
  a := public.mi_watch_alerts();
  n := jsonb_array_length(a->'alerts');
  if n = 0 then return jsonb_build_object('created', false, 'why', 'no alerts'); end if;
  insert into public.notifications (user_id, audience, kind, level, title_bn, title_en, body_bn, body_en, route, key, day)
    values (null, 'owner', 'mi_price_alert', 'info', 'প্রতিযোগীর দাম বদলেছে', 'Competitor prices moved', n || ' item(s) moved beyond your threshold', n || ' item(s) moved beyond your threshold', 'market', 'mi_price_alert', day_)
    on conflict (kind, key, day) do nothing;
  made := found;
  return jsonb_build_object('created', made, 'alerts', n);
end $$;

-- weekly digest (in-app, owner): your sales growth and decline, open opportunities, price alerts. Numbers only; no customer data.
create or replace function public.mi_growth_digest(p_d1 date, p_d2 date, p_c1 date, p_c2 date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g jsonb; summ jsonb; al jsonb; made boolean := false; body text;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  g := public.mi_growth_items(p_d1, p_d2, p_c1, p_c2, null, 5);
  summ := public.mi_summary();
  al := public.mi_watch_alerts();
  body := 'Top movers in the week: ' || coalesce((select string_agg(x->>'item_name' || ' ' || coalesce(x->>'growth_pct', 'n/a') || '%', ', ') from jsonb_array_elements(g->'rows') x), 'none')
        || '. Open opportunities: ' || (summ->'opportunities')::text || '. Price alerts: ' || jsonb_array_length(al->'alerts') || '.';
  if public.rule_on('mi_digest_on') and public._mi_on() then
    insert into public.notifications (user_id, audience, kind, level, title_bn, title_en, body_bn, body_en, route, key, day)
      values (null, 'owner', 'mi_weekly_digest', 'info', 'সাপ্তাহিক বাজার ও বৃদ্ধির সারসংক্ষেপ', 'Weekly market and growth digest', body, body, 'market', 'mi_digest', public._mi_today())
      on conflict (kind, key, day) do nothing;
    made := found;
  end if;
  return jsonb_build_object('digest', body, 'created', made, 'growth', g, 'summary', summ, 'alerts', al->'alerts');
end $$;

-- ---------- privileges ----------
revoke all on function public.mi_research_gate(uuid, text), public.mi_adapter_set(text, boolean, text), public.mi_job_save(text, jsonb), public.mi_job_mark_run(text),
  public.mi_summary_propose(uuid[], text), public.mi_summary_decide(bigint, text, text), public.mi_watch_alerts(), public.mi_alert_notify(),
  public.mi_growth_digest(date, date, date, date) from public, anon;
grant execute on function public.mi_research_gate(uuid, text), public.mi_adapter_set(text, boolean, text), public.mi_job_save(text, jsonb), public.mi_job_mark_run(text),
  public.mi_summary_propose(uuid[], text), public.mi_summary_decide(bigint, text, text), public.mi_watch_alerts(), public.mi_alert_notify(),
  public.mi_growth_digest(date, date, date, date) to authenticated;

notify pgrst, 'reload schema';
