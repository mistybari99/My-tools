-- Phase 488 (X6) - THE WORKSPACE: topics, sources, findings, competitor prices, offers, product gaps, opportunities (status machine with a reason on every move), tasks and outcome measurement.
-- Paste AFTER phase530. Paste-twice safe. Every write needs rule mi_on = ON and the market_manage right (or the owner). Reads are RLS-gated on market_view.
-- Scores are computed here and the basis is stored next to them (transparent, not a model):
--   freshness_score (0-3): age of the PUBLICATION date when the page was retrieved: 30 days or less = 3, up to 180 = 2, up to 365 = 1, older or unknown = 0.
--   quality_score   (0-6): finding type (sourced_fact 3, source_claim 2, analysis 1, hypothesis 0) + source reliability (A 3, B 2, C 1, D 0; no registered source = 0).
-- Status machine for opportunities (every move writes mi_opp_decisions with a reason; nothing is deleted):
--   proposed -> saved | approved | rejected
--   saved    -> approved | rejected
--   approved -> in_progress | rejected            (approval is given by someone other than the person who asked: build rule 8)
--   proposed / saved -> in_progress               only when approval_needed = false
--   in_progress -> done
--   done -> measured                              only through mi_opportunity_measure (needs ERP data)
--   rejected and measured are final.

do $g$ begin
  if to_regprocedure('public._mi_can_manage()') is null or to_regprocedure('public._mi_url_key(text)') is null then raise exception 'phase531 needs phase530 first'; end if;
end $g$;

-- ---------- topics ----------
create or replace function public.mi_topic_save(p_id uuid, p jsonb, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.mi_topics; d jsonb := coalesce(p, '{}'::jsonb); loc int := nullif(d->>'location_id', '')::int; rv int := nullif(d->>'review_every_days', '')::int;
begin
  if not public._mi_on() then raise exception 'module_off: the market workspace is switched off'; end if;
  if not public._mi_can_manage() then raise exception 'not allowed'; end if;
  if loc is not null and not public.can_loc(loc) then raise exception 'not allowed for this location'; end if;
  if p_id is null then
    if p_client is not null then select * into t from public.mi_topics where created_by = auth.uid() and client_id = p_client; if found then return jsonb_build_object('id', t.id, 'dup', true); end if; end if;
    insert into public.mi_topics (client_id, category, title_bn, title_en, business_relevance, location_id, brand_code, owner_user, review_every_days, created_by, updated_by)
      values (p_client, d->>'category', btrim(d->>'title_bn'), nullif(btrim(d->>'title_en'), ''), btrim(d->>'business_relevance'), loc, nullif(btrim(d->>'brand_code'), ''),
              coalesce(nullif(d->>'owner_user', '')::uuid, auth.uid()), rv, auth.uid(), auth.uid()) returning * into t;
  else
    update public.mi_topics set category = coalesce(d->>'category', category), title_bn = coalesce(nullif(btrim(d->>'title_bn'), ''), title_bn),
      title_en = case when d ? 'title_en' then nullif(btrim(d->>'title_en'), '') else title_en end,
      business_relevance = coalesce(nullif(btrim(d->>'business_relevance'), ''), business_relevance),
      location_id = case when d ? 'location_id' then loc else location_id end,
      brand_code = case when d ? 'brand_code' then nullif(btrim(d->>'brand_code'), '') else brand_code end,
      owner_user = coalesce(nullif(d->>'owner_user', '')::uuid, owner_user),
      review_every_days = case when d ? 'review_every_days' then rv else review_every_days end,
      updated_by = auth.uid(), updated_at = now()
      where id = p_id and status = 'active' returning * into t;
    if not found then raise exception 'not_found_or_retired'; end if;
  end if;
  return jsonb_build_object('id', t.id, 'status', t.status);
end $$;

create or replace function public.mi_topic_retire(p_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public._mi_on() then raise exception 'module_off: the market workspace is switched off'; end if;
  if not public._mi_can_manage() then raise exception 'not allowed'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  update public.mi_topics set status = 'retired', retired_reason = left(btrim(p_reason), 300), updated_by = auth.uid(), updated_at = now() where id = p_id and status = 'active';
  if not found then raise exception 'not_found_or_retired'; end if;
  return jsonb_build_object('id', p_id, 'status', 'retired');
end $$;

-- ---------- sources ----------
-- only the owner sets terms_allow_scraping and robots_ok (the owner reads the terms)
create or replace function public.mi_source_save(p_id uuid, p jsonb, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.mi_sources; d jsonb := coalesce(p, '{}'::jsonb); v_url text := btrim(d->>'url'); tallow boolean; tchk date := nullif(d->>'terms_checked_on', '')::date;
begin
  if not public._mi_on() then raise exception 'module_off: the market workspace is switched off'; end if;
  if not public._mi_can_manage() then raise exception 'not allowed'; end if;
  if (d ? 'terms_allow_scraping' or d ? 'robots_ok' or d ? 'rate_limit_per_hour' or d ? 'terms_checked_on') and not public.is_owner() then raise exception 'not allowed: only the owner sets the terms, robots and rate limit of a source'; end if;
  tallow := coalesce((d->>'terms_allow_scraping')::boolean, false);
  if p_id is null then
    if p_client is not null then select * into s from public.mi_sources where created_by = auth.uid() and client_id = p_client; if found then return jsonb_build_object('id', s.id, 'dup', true); end if; end if;
    insert into public.mi_sources (client_id, name, url, url_key, publisher, source_type, reliability, reliability_note, terms_allow_scraping, terms_checked_on, robots_ok, rate_limit_per_hour, created_by, updated_by)
      values (p_client, btrim(d->>'name'), v_url, public._mi_url_key(v_url), btrim(d->>'publisher'), coalesce(d->>'source_type', 'other'), coalesce(d->>'reliability', 'C'),
              nullif(btrim(d->>'reliability_note'), ''), tallow, tchk, (d->>'robots_ok')::boolean, nullif(d->>'rate_limit_per_hour', '')::int, auth.uid(), auth.uid()) returning * into s;
  else
    update public.mi_sources set name = coalesce(nullif(btrim(d->>'name'), ''), name),
      url = coalesce(nullif(v_url, ''), url), url_key = public._mi_url_key(coalesce(nullif(v_url, ''), url)),
      publisher = coalesce(nullif(btrim(d->>'publisher'), ''), publisher),
      source_type = coalesce(d->>'source_type', source_type), reliability = coalesce(d->>'reliability', reliability),
      reliability_note = case when d ? 'reliability_note' then nullif(btrim(d->>'reliability_note'), '') else reliability_note end,
      terms_allow_scraping = case when d ? 'terms_allow_scraping' then tallow else terms_allow_scraping end,
      terms_checked_on = case when d ? 'terms_checked_on' then tchk else terms_checked_on end,
      robots_ok = case when d ? 'robots_ok' then (d->>'robots_ok')::boolean else robots_ok end,
      rate_limit_per_hour = case when d ? 'rate_limit_per_hour' then nullif(d->>'rate_limit_per_hour', '')::int else rate_limit_per_hour end,
      updated_by = auth.uid(), updated_at = now()
      where id = p_id and status = 'active' returning * into s;
    if not found then raise exception 'not_found_or_retired'; end if;
  end if;
  return jsonb_build_object('id', s.id, 'status', s.status, 'terms_allow_scraping', s.terms_allow_scraping);
end $$;

create or replace function public.mi_source_retire(p_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public._mi_on() then raise exception 'module_off: the market workspace is switched off'; end if;
  if not public._mi_can_manage() then raise exception 'not allowed'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  update public.mi_sources set status = 'retired', terms_allow_scraping = false, retired_reason = left(btrim(p_reason), 300), updated_by = auth.uid(), updated_at = now() where id = p_id and status = 'active';
  if not found then raise exception 'not_found_or_retired'; end if;
  return jsonb_build_object('id', p_id, 'status', 'retired');
end $$;

-- ---------- findings (manual entry; the URL, publisher, dates, summary and type are all required) ----------
create or replace function public.mi_finding_add(p jsonb, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d jsonb := coalesce(p, '{}'::jsonb); f public.mi_findings; src public.mi_sources; url text := btrim(d->>'source_url'); pub date := nullif(d->>'published_on', '')::date;
  ret date := coalesce(nullif(d->>'retrieved_on', '')::date, public._mi_today()); quote text := nullif(btrim(d->>'quote'), ''); maxq numeric := public.rule_num('mi_quote_max_chars');
  sk text; dup uuid; fs int; ftxt text; tw int; rw int; qb text; qs int; ftype text := d->>'finding_type'; sid uuid := nullif(d->>'source_id', '')::uuid; tid uuid := nullif(d->>'topic_id', '')::uuid;
  pubname text := nullif(btrim(d->>'publisher'), ''); age int; has_src boolean := sid is not null;
begin
  if not public._mi_on() then raise exception 'module_off: the market workspace is switched off'; end if;
  if not public._mi_can_manage() then raise exception 'not allowed'; end if;
  if p_client is not null then select * into f from public.mi_findings where created_by = auth.uid() and client_id = p_client; if found then return jsonb_build_object('id', f.id, 'dup', true); end if; end if;
  if quote is not null and (maxq is null or char_length(quote) > maxq) then raise exception 'quote_not_allowed: quotes are off or longer than the limit the owner set; write your own short summary instead'; end if;
  if ftype not in ('sourced_fact', 'source_claim', 'analysis', 'hypothesis') then raise exception 'bad_finding_type'; end if;
  if sid is not null then
    select * into src from public.mi_sources where id = sid and status = 'active';
    if not found then raise exception 'source_not_active'; end if;
    pubname := coalesce(pubname, src.publisher);
  end if;
  if tid is not null and not exists (select 1 from public.mi_topics where id = tid and status = 'active') then raise exception 'topic_not_active'; end if;
  if pubname is null then raise exception 'publisher_required'; end if;
  sk := md5(lower(regexp_replace(btrim(coalesce(d->>'summary', '')), '\s+', ' ', 'g')));
  select id into dup from public.mi_findings where url_key = public._mi_url_key(url) or summary_key = sk order by created_at, id limit 1;
  -- freshness (age of the publication date when retrieved)
  if pub is null then fs := 0; ftxt := 'no publication date: freshness 0';
  else age := ret - pub;
    fs := case when age <= 30 then 3 when age <= 180 then 2 when age <= 365 then 1 else 0 end;
    ftxt := 'published ' || age || ' days before retrieval: freshness ' || fs;
  end if;
  tw := case ftype when 'sourced_fact' then 3 when 'source_claim' then 2 when 'analysis' then 1 else 0 end;
  rw := case when not has_src then 0 else case src.reliability when 'A' then 3 when 'B' then 2 when 'C' then 1 else 0 end end;
  qs := tw + rw;
  qb := ftype || ' ' || tw || ' + ' || case when not has_src then 'no registered source 0' else 'source ' || src.reliability || ' ' || rw end || ' = ' || qs;
  insert into public.mi_findings (client_id, topic_id, source_id, source_url, url_key, publisher, published_on, retrieved_on, title, summary, summary_key, quote, finding_type,
      duplicate_of, freshness_score, quality_score, quality_basis, created_by)
    values (p_client, tid, sid, url, public._mi_url_key(url), pubname, pub, ret, nullif(btrim(d->>'title'), ''), btrim(d->>'summary'), sk, quote, ftype, dup, fs, qs, qb || '; ' || ftxt, auth.uid())
    returning * into f;
  return jsonb_build_object('id', f.id, 'duplicate_of', dup, 'freshness_score', fs, 'quality_score', qs, 'quality_basis', qb, 'freshness_basis', ftxt);
end $$;

create or replace function public.mi_finding_file_add(p_finding uuid, p_path text, p_name text, p_mime text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public._mi_on() then raise exception 'module_off: the market workspace is switched off'; end if;
  if not public._mi_can_manage() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.mi_findings where id = p_finding) then raise exception 'not_found'; end if;
  select count(*) into n from public.mi_finding_files where finding_id = p_finding;
  if n >= 5 then raise exception 'too_many_files: at most 5 attachments per finding'; end if;
  insert into public.mi_finding_files (finding_id, storage_path, file_name, mime, created_by) values (p_finding, p_path, left(btrim(p_name), 200), p_mime, auth.uid());
  return jsonb_build_object('ok', true, 'files', n + 1);
end $$;

-- ---------- competitor prices, offers, product gaps ----------
create or replace function public._mi_price_insert(d jsonb, p_client uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.mi_price_obs; iid uuid := nullif(d->>'item_id', '')::uuid; od date := coalesce(nullif(d->>'observed_on', '')::date, public._mi_today());
begin
  if p_client is not null then select * into o from public.mi_price_obs where created_by = auth.uid() and client_id = p_client; if found then return jsonb_build_object('id', o.id, 'dup', true); end if; end if;
  if iid is not null and not exists (select 1 from public.items where id = iid) then raise exception 'item_not_found'; end if;
  insert into public.mi_price_obs (client_id, competitor, item_id, item_label, price, unit, observed_on, source_url, source_note, created_by)
    values (p_client, btrim(d->>'competitor'), iid, btrim(coalesce(d->>'item_label', '')), (d->>'price')::numeric, nullif(btrim(d->>'unit'), ''), od,
            nullif(btrim(d->>'source_url'), ''), nullif(btrim(d->>'source_note'), ''), auth.uid()) returning * into o;
  return jsonb_build_object('id', o.id);
end $$;

create or replace function public.mi_price_add(p jsonb, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public._mi_on() then raise exception 'module_off: the market workspace is switched off'; end if;
  if not public._mi_can_manage() then raise exception 'not allowed'; end if;
  if coalesce(p->>'price', '') = '' then raise exception 'price_required'; end if;
  return public._mi_price_insert(coalesce(p, '{}'::jsonb), p_client);
end $$;

-- CSV import: the browser reads the file and sends the rows here. Each row is checked and written on its own; bad rows are reported, never guessed.
create or replace function public.mi_price_import(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb; i int := 0; ok int := 0; bad jsonb := '[]'::jsonb; res jsonb;
begin
  if not public._mi_on() then raise exception 'module_off: the market workspace is switched off'; end if;
  if not public._mi_can_manage() then raise exception 'not allowed'; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 500 then raise exception 'bad_rows: a list of at most 500 rows'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    i := i + 1;
    begin
      if coalesce(r->>'price', '') !~ '^\d+(\.\d{1,2})?$' then raise exception 'bad_price'; end if;
      if coalesce(btrim(r->>'competitor'), '') = '' or coalesce(btrim(r->>'item_label'), '') = '' then raise exception 'competitor_and_item_required'; end if;
      res := public._mi_price_insert(r, null);
      ok := ok + 1;
    exception when others then
      bad := bad || jsonb_build_object('row', i, 'error', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('rows', jsonb_array_length(p_rows), 'inserted', ok, 'rejected', bad);
end $$;

create or replace function public.mi_offer_add(p jsonb, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.mi_offer_log; d jsonb := coalesce(p, '{}'::jsonb);
begin
  if not public._mi_on() then raise exception 'module_off: the market workspace is switched off'; end if;
  if not public._mi_can_manage() then raise exception 'not allowed'; end if;
  if p_client is not null then select * into o from public.mi_offer_log where created_by = auth.uid() and client_id = p_client; if found then return jsonb_build_object('id', o.id, 'dup', true); end if; end if;
  insert into public.mi_offer_log (client_id, competitor, offer_text, starts_on, ends_on, source_url, created_by)
    values (p_client, btrim(d->>'competitor'), btrim(d->>'offer_text'), nullif(d->>'starts_on', '')::date, nullif(d->>'ends_on', '')::date, nullif(btrim(d->>'source_url'), ''), auth.uid())
    returning * into o;
  return jsonb_build_object('id', o.id);
end $$;

create or replace function public.mi_gap_save(p_id uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g public.mi_product_gaps; d jsonb := coalesce(p, '{}'::jsonb);
begin
  if not public._mi_on() then raise exception 'module_off: the market workspace is switched off'; end if;
  if not public._mi_can_manage() then raise exception 'not allowed'; end if;
  if p_id is null then
    insert into public.mi_product_gaps (topic_id, product_label, evidence_note, created_by, updated_by)
      values (nullif(d->>'topic_id', '')::uuid, btrim(d->>'product_label'), nullif(btrim(d->>'evidence_note'), ''), auth.uid(), auth.uid()) returning * into g;
  else
    update public.mi_product_gaps set status = coalesce(nullif(d->>'status', ''), status), evidence_note = coalesce(nullif(btrim(d->>'evidence_note'), ''), evidence_note),
      updated_by = auth.uid(), updated_at = now() where id = p_id returning * into g;
    if not found then raise exception 'not_found'; end if;
  end if;
  return jsonb_build_object('id', g.id, 'status', g.status);
end $$;

-- ---------- opportunities ----------
create or replace function public.mi_opportunity_save(p_id uuid, p jsonb, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.mi_opportunities; d jsonb := coalesce(p, '{}'::jsonb); ev uuid[]; cat text; bl numeric; bb numeric; loc int := nullif(d->>'location_id', '')::int;
begin
  if not public._mi_on() then raise exception 'module_off: the market workspace is switched off'; end if;
  if not public._mi_can_manage() then raise exception 'not allowed'; end if;
  if loc is not null and not public.can_loc(loc) then raise exception 'not allowed for this location'; end if;
  if p_id is not null then
    select * into o from public.mi_opportunities where id = p_id;
    if not found then raise exception 'not_found'; end if;
    if o.status not in ('proposed', 'saved') then raise exception 'locked_after_decision: a decided record is not edited; ask the owner for a change (build rule 11)'; end if;
  elsif p_client is not null then
    select * into o from public.mi_opportunities where created_by = auth.uid() and client_id = p_client;
    if found then return jsonb_build_object('id', o.id, 'status', o.status, 'dup', true); end if;
  end if;
  if p_id is null and nullif(d->>'category', '') is null then raise exception 'category_required'; end if;
  cat := coalesce(nullif(d->>'category', ''), case when p_id is null then null else o.category end);
  ev := case when d ? 'evidence_finding_ids' then array(select jsonb_array_elements_text(d->'evidence_finding_ids'))::uuid[] else coalesce(o.evidence_finding_ids, '{}') end;
  if cardinality(ev) > 0 and (select count(*) from public.mi_findings f where f.id = any (ev)) <> cardinality(ev) then raise exception 'evidence_not_found'; end if;
  if cardinality(ev) = 0 and cat <> 'growth_own_data' then raise exception 'evidence_required: link at least one finding (or use the own-data category)'; end if;
  bl := case when d ? 'benefit_low' then nullif(d->>'benefit_low', '')::numeric else o.benefit_low end;
  bb := case when d ? 'benefit_base' then nullif(d->>'benefit_base', '')::numeric else o.benefit_base end;
  if bl is not null and bb is not null and bl > bb then raise exception 'benefit_low_above_base'; end if;
  if p_id is null and (nullif(btrim(d->>'success_kpi'), '') is null or nullif(d->>'kpi_target', '') is null) then raise exception 'kpi_required: write the measurable success KPI and its target'; end if;
  if p_id is null and nullif(btrim(d->>'confidence_limits'), '') is null then raise exception 'confidence_limits_required: say what this does not prove'; end if;
  if p_id is null then
    insert into public.mi_opportunities (client_id, title, category, topic_id, location_id, scope_item_id, evidence_finding_ids, evidence_note, benefit_low, benefit_base, benefit_basis,
        cost_estimate, cost_basis, assumptions, risks, confidence, confidence_limits, next_action, approval_needed, approval_note, success_kpi, kpi_baseline, kpi_target,
        owner_user, review_due, status, created_by, updated_by)
      values (p_client, btrim(d->>'title'), cat, nullif(d->>'topic_id', '')::uuid, loc, nullif(d->>'scope_item_id', '')::uuid, ev, nullif(btrim(d->>'evidence_note'), ''), bl, bb,
        nullif(btrim(d->>'benefit_basis'), ''), nullif(d->>'cost_estimate', '')::numeric, nullif(btrim(d->>'cost_basis'), ''), nullif(btrim(d->>'assumptions'), ''), nullif(btrim(d->>'risks'), ''),
        coalesce(nullif(d->>'confidence', ''), 'low'), btrim(d->>'confidence_limits'), nullif(btrim(d->>'next_action'), ''), coalesce((d->>'approval_needed')::boolean, true),
        nullif(btrim(d->>'approval_note'), ''), btrim(d->>'success_kpi'), nullif(d->>'kpi_baseline', '')::numeric, (d->>'kpi_target')::numeric,
        coalesce(nullif(d->>'owner_user', '')::uuid, auth.uid()), nullif(d->>'review_due', '')::date, 'proposed', auth.uid(), auth.uid())
      returning * into o;
  else
    update public.mi_opportunities set title = coalesce(nullif(btrim(d->>'title'), ''), title), category = cat,
      topic_id = case when d ? 'topic_id' then nullif(d->>'topic_id', '')::uuid else topic_id end,
      location_id = case when d ? 'location_id' then loc else location_id end,
      scope_item_id = case when d ? 'scope_item_id' then nullif(d->>'scope_item_id', '')::uuid else scope_item_id end,
      evidence_finding_ids = ev, evidence_note = case when d ? 'evidence_note' then nullif(btrim(d->>'evidence_note'), '') else evidence_note end,
      benefit_low = bl, benefit_base = bb,
      benefit_basis = case when d ? 'benefit_basis' then nullif(btrim(d->>'benefit_basis'), '') else benefit_basis end,
      cost_estimate = case when d ? 'cost_estimate' then nullif(d->>'cost_estimate', '')::numeric else cost_estimate end,
      cost_basis = case when d ? 'cost_basis' then nullif(btrim(d->>'cost_basis'), '') else cost_basis end,
      assumptions = case when d ? 'assumptions' then nullif(btrim(d->>'assumptions'), '') else assumptions end,
      risks = case when d ? 'risks' then nullif(btrim(d->>'risks'), '') else risks end,
      confidence = coalesce(nullif(d->>'confidence', ''), confidence),
      confidence_limits = coalesce(nullif(btrim(d->>'confidence_limits'), ''), confidence_limits),
      next_action = case when d ? 'next_action' then nullif(btrim(d->>'next_action'), '') else next_action end,
      approval_needed = coalesce((d->>'approval_needed')::boolean, approval_needed),
      approval_note = case when d ? 'approval_note' then nullif(btrim(d->>'approval_note'), '') else approval_note end,
      success_kpi = coalesce(nullif(btrim(d->>'success_kpi'), ''), success_kpi),
      kpi_baseline = case when d ? 'kpi_baseline' then nullif(d->>'kpi_baseline', '')::numeric else kpi_baseline end,
      kpi_target = coalesce(nullif(d->>'kpi_target', '')::numeric, kpi_target),
      owner_user = coalesce(nullif(d->>'owner_user', '')::uuid, owner_user),
      review_due = case when d ? 'review_due' then nullif(d->>'review_due', '')::date else review_due end,
      updated_by = auth.uid(), updated_at = now()
      where id = p_id returning * into o;
  end if;
  return jsonb_build_object('id', o.id, 'status', o.status);
end $$;

-- every status change goes through here: the reason is mandatory, every move is kept
create or replace function public.mi_opportunity_move(p_id uuid, p_to text, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.mi_opportunities; sid text; ok boolean := false;
begin
  if not public._mi_on() then raise exception 'module_off: the market workspace is switched off'; end if;
  if not public._mi_can_manage() then raise exception 'not allowed'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required: write why (kept for ever)'; end if;
  if p_to = 'measured' then raise exception 'use_measure: measured is set only by measuring from ERP data'; end if;
  select * into o from public.mi_opportunities where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if o.location_id is not null and not public.can_loc(o.location_id) then raise exception 'not allowed for this location'; end if;
  ok := (o.status = 'proposed' and p_to in ('saved', 'approved', 'rejected', 'in_progress'))
     or (o.status = 'saved' and p_to in ('approved', 'rejected'))
     or (o.status = 'approved' and p_to in ('in_progress', 'rejected'))
     or (o.status = 'in_progress' and p_to = 'done');
  if not ok then raise exception 'bad_move: % to % is not allowed', o.status, p_to; end if;
  if o.status in ('proposed', 'saved') and p_to = 'in_progress' and o.approval_needed then raise exception 'approval_needed: approve it first'; end if;
  if p_to = 'approved' and o.created_by = auth.uid() then raise exception 'own_request: the person who asked can not approve it (build rule 8)'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.mi_opp_decisions (opp_id, from_status, to_status, reason, decided_by, decided_staff) values (p_id, o.status, p_to, left(btrim(p_reason), 300), auth.uid(), sid);
  update public.mi_opportunities set status = p_to, updated_by = auth.uid(), updated_at = now() where id = p_id;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'mi_opp_move', 'mi_opportunities', p_id::text, jsonb_build_object('from', o.status, 'to', p_to, 'reason', left(btrim(p_reason), 300)));
  return jsonb_build_object('id', p_id, 'from', o.status, 'to', p_to);
end $$;

-- an implementation task in the existing task list (crm_tasks, phase 323); only for approved or in-progress work
create or replace function public.mi_opportunity_task(p_id uuid, p_title text, p_due timestamptz, p_assign uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.mi_opportunities; a uuid := coalesce(p_assign, auth.uid()); t uuid;
begin
  if not public._mi_on() then raise exception 'module_off: the market workspace is switched off'; end if;
  if not public._mi_can_manage() then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_task_on') then raise exception 'module_off: tasks are switched off'; end if;
  select * into o from public.mi_opportunities where id = p_id;
  if not found then raise exception 'not_found'; end if;
  if o.status not in ('approved', 'in_progress') then raise exception 'not_approved: tasks are made after approval'; end if;
  if nullif(btrim(coalesce(p_title, '')), '') is null or p_due is null then raise exception 'title_and_due_required'; end if;
  if not exists (select 1 from public.profiles where id = a and status = 'active') then raise exception 'assignee_not_active'; end if;
  insert into public.crm_tasks (location_id, kind, title, due_at, assigned_to, source, created_by)
    values (o.location_id, 'other', left(btrim(p_title), 120), p_due, a, 'manual', auth.uid()) returning id into t;
  insert into public.mi_opp_links (opp_id, task_id, created_by) values (p_id, t, auth.uid());
  return jsonb_build_object('task_id', t);
end $$;

-- ---------- measuring from ERP data (never typed in). The result is a number from sales_fact, with its coverage and the warning ----------
create or replace function public.mi_opportunity_measure(p_id uuid, p_from date, p_to date, p_base_from date, p_base_to date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.mi_opportunities; a numeric; b numeric; ad int; bd int; cal_a int := p_to - p_from + 1; cal_b int := p_base_to - p_base_from + 1; sid text; scope jsonb; oid bigint;
  warn text := 'This shows what sales did in the two windows. It does not prove the opportunity caused the change: season, festivals, prices, stock and other events can explain it too.';
begin
  if not public._mi_on() then raise exception 'module_off: the market workspace is switched off'; end if;
  if not public._mi_can_manage() then raise exception 'not allowed'; end if;
  if p_to < p_from or p_base_to < p_base_from then raise exception 'bad_window'; end if;
  select * into o from public.mi_opportunities where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if o.status <> 'done' then raise exception 'not_done: measure after the work is done'; end if;
  scope := jsonb_build_object('item_id', o.scope_item_id, 'location_id', o.location_id, 'measure', 'net sales of status done, per window, sales the person may see');
  select coalesce(sum(f.net), 0), count(distinct f.day) into a, ad from public.sales_fact f
    where f.status = 'done' and f.day between p_from and p_to and (o.scope_item_id is null or f.item_id = o.scope_item_id) and (o.location_id is null or f.location_id = o.location_id) and public.can_loc(f.location_id);
  select coalesce(sum(f.net), 0), count(distinct f.day) into b, bd from public.sales_fact f
    where f.status = 'done' and f.day between p_base_from and p_base_to and (o.scope_item_id is null or f.item_id = o.scope_item_id) and (o.location_id is null or f.location_id = o.location_id) and public.can_loc(f.location_id);
  insert into public.mi_opp_outcomes (opp_id, window_from, window_to, base_from, base_to, scope, actual_value, baseline_value, change_value, actual_days, baseline_days, coverage_note, warning, created_by)
    values (p_id, p_from, p_to, p_base_from, p_base_to, scope, a, b, a - b, ad, bd,
      'trading days: ' || ad || ' of ' || cal_a || ' calendar days in the window; ' || bd || ' of ' || cal_b || ' in the comparison window', warn, auth.uid()) returning id into oid;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.mi_opp_decisions (opp_id, from_status, to_status, reason, decided_by, decided_staff)
    values (p_id, 'done', 'measured', 'measured from ERP sales (outcome ' || oid || ')', auth.uid(), sid);
  update public.mi_opportunities set status = 'measured', updated_by = auth.uid(), updated_at = now() where id = p_id;
  return jsonb_build_object('outcome_id', oid, 'actual', a, 'baseline', b, 'change', a - b, 'actual_days', ad, 'baseline_days', bd,
    'kpi_baseline', o.kpi_baseline, 'kpi_target', o.kpi_target, 'warning', warn);
end $$;

-- ---------- one summary for the page (read) ----------
create or replace function public.mi_summary() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._mi_can_view() then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'on', public._mi_on(),
    'topics', (select count(*) from public.mi_topics where status = 'active'),
    'sources', (select count(*) from public.mi_sources where status = 'active'),
    'findings', (select count(*) from public.mi_findings),
    'findings_duplicates', (select count(*) from public.mi_findings where duplicate_of is not null),
    'price_obs', (select count(*) from public.mi_price_obs),
    'opportunities', coalesce((select jsonb_object_agg(s, n) from (select status s, count(*) n from public.mi_opportunities group by status) z), '{}'::jsonb),
    'open_gaps', (select count(*) from public.mi_product_gaps where status <> 'closed'));
end $$;

revoke all on function public.mi_topic_save(uuid, jsonb, uuid), public.mi_topic_retire(uuid, text), public.mi_source_save(uuid, jsonb, uuid), public.mi_source_retire(uuid, text),
  public.mi_finding_add(jsonb, uuid), public.mi_finding_file_add(uuid, text, text, text), public._mi_price_insert(jsonb, uuid), public.mi_price_add(jsonb, uuid), public.mi_price_import(jsonb),
  public.mi_offer_add(jsonb, uuid), public.mi_gap_save(uuid, jsonb), public.mi_opportunity_save(uuid, jsonb, uuid), public.mi_opportunity_move(uuid, text, text),
  public.mi_opportunity_task(uuid, text, timestamptz, uuid), public.mi_opportunity_measure(uuid, date, date, date, date), public.mi_summary() from public, anon;
grant execute on function public.mi_topic_save(uuid, jsonb, uuid), public.mi_topic_retire(uuid, text), public.mi_source_save(uuid, jsonb, uuid), public.mi_source_retire(uuid, text),
  public.mi_finding_add(jsonb, uuid), public.mi_finding_file_add(uuid, text, text, text), public.mi_price_add(jsonb, uuid), public.mi_price_import(jsonb),
  public.mi_offer_add(jsonb, uuid), public.mi_gap_save(uuid, jsonb), public.mi_opportunity_save(uuid, jsonb, uuid), public.mi_opportunity_move(uuid, text, text),
  public.mi_opportunity_task(uuid, text, timestamptz, uuid), public.mi_opportunity_measure(uuid, date, date, date, date), public.mi_summary() to authenticated;

notify pgrst, 'reload schema';
