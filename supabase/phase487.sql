-- Phase 487 (X6, Market Intelligence & Growth) - FOUNDATION: settings (all OFF or blank), rights, and the tables.
-- Paste AFTER phase478 (the whole owner list). Paste-twice safe. No earlier phase file is edited.
-- Nothing here reads or calls the internet. A research provider, an AI summariser and a scheduled job are only SLOTS: every one is OFF.
-- Tables (all new, all append-only where they hold evidence or decisions; nothing is deleted, items are retired):
--   mi_topics            research topics (competitors, products, prices, customer trends, festivals, channels, technology, operations)
--   mi_sources           source registry (URL, publisher, type, reliability A-D, terms-allow-scraping flag, default NO)
--   mi_findings          one finding = one source URL + summary + optional short quote (append-only; corrections are new findings)
--   mi_finding_files     attachments on a finding (storage path only; append-only)
--   mi_price_obs         competitor price observations (append-only)
--   mi_offer_log         competitor offers (append-only)
--   mi_product_gaps      product-gap list (status can change, never deleted)
--   mi_opportunities     recommendations: evidence, benefit/cost assumptions, risks, confidence limits, KPI, owner, status
--   mi_opp_decisions     every status change, with a MANDATORY reason, kept forever (append-only; pattern of mkt_post_decisions, phase461)
--   mi_opp_links         implementation tasks (crm_tasks rows) linked to an opportunity (append-only)
--   mi_opp_outcomes      outcome measurements computed from ERP data (append-only; never typed in by hand)
--   mi_job_defs          scheduled research job definitions (enabled = false; needs the research gate, phase 490)
--   mi_adapters          provider adapter catalogue (network_allowed = false for every row; the mock adapter needs no network)
--   mi_summary_proposals AI summariser output: PROPOSALS only, a person accepts or rejects (append-only status history in mi_summary_decisions)
-- Build rules applied: every list has Add new (saves a new row) and retire; no hard delete; the change log is written by log_change; new behaviour OFF by default.

do $g$ begin
  if to_regprocedure('public.rule_on(text)') is null or to_regprocedure('public._append_only43()') is null or to_regprocedure('public.no_hard_delete()') is null
     or to_regprocedure('public.log_change()') is null or to_regprocedure('public.is_owner()') is null or to_regprocedure('public.has_grant(text,integer)') is null then
    raise exception 'phase530 needs phases 10, 43 and the rules / grants base first';
  end if;
  if to_regclass('public.crm_tasks') is null or to_regclass('public.items') is null or to_regclass('public.locations') is null then
    raise exception 'phase530 needs phase323 (crm_tasks) first';
  end if;
end $g$;

-- ---------- settings (module reports). Every switch OFF; every number BLANK until the owner types it ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, 'reports', v.kind, v.dv, v.unit, v.ch, v.mn, v.mx, v.lab, v.lab, v.lab, v.hint, v.hint, v.hint, v.srt
  from (values
 ('mi_on', 'switch', 'false'::jsonb, null::text, null::jsonb, null::numeric, null::numeric,
   'Market intelligence workspace (research, findings, opportunities)',
   'OFF = the Market page is empty and no research, finding, price or opportunity can be written. ON = the owner and the people with the market rights can record topics, sources, findings and opportunities. Nothing is searched on the internet by this switch.', 3300),
 ('mi_scrape_on', 'switch', 'false'::jsonb, null::text, null::jsonb, null::numeric, null::numeric,
   'Allow scheduled research jobs to fetch a permitted source',
   'OFF (default) = no source is fetched by any job. ON still needs, for each source: an active source, the terms-allow-scraping flag set by the owner after reading the terms, a robots check that passed, and a rate limit typed in. Logins and paywalls are never bypassed.', 3301),
 ('mi_research_job_on', 'switch', 'false'::jsonb, null::text, null::jsonb, null::numeric, null::numeric,
   'Run scheduled research jobs (job runner must also be on)',
   'OFF = the research job definitions are stored but never run. The job runner (X1 job_runs) checks this switch before every run.', 3302),
 ('mi_ai_summary_on', 'switch', 'false'::jsonb, null::text, null::jsonb, null::numeric, null::numeric,
   'Let the AI summariser propose a summary of chosen findings',
   'OFF = no AI call. ON = the summariser may only PROPOSE a summary text of findings you selected; a person accepts or rejects it. It never creates a finding, an opportunity or a price, and never publishes anything.', 3303),
 ('mi_quote_max_chars', 'number', null::jsonb, 'characters', null::jsonb, 0::numeric, 1000::numeric,
   'Longest quoted snippet kept from a source (characters)',
   'Blank = quotes are NOT stored (only your own summary). Type a number to allow short quotes up to that many characters. Keep it short: the summary is your own words.', 3304),
 ('mi_elast_min_days', 'number', null::jsonb, 'days', null::jsonb, 1::numeric, 365::numeric,
   'Minimum trading days at each price before a price-response hint is shown',
   'Blank = no price-response hint is shown at all. A hint is only a pattern in past data, never a forecast; it is shown with the number of days behind it.', 3305),
 ('mi_watch_threshold_pct', 'number', null::jsonb, '%', null::jsonb, 0::numeric, 1000::numeric,
   'Alert when a competitor price moves by more than this %',
   'Blank = no competitor price alert. Typed number = the watchlist lists each competitor price that moved more than this % since its previous observation.', 3306),
 ('mi_alerts_on', 'switch', 'false'::jsonb, null::text, null::jsonb, null::numeric, null::numeric,
   'Put competitor price alerts in the in-app notifications',
   'OFF = alerts are only listed on the Market page. ON = each alert day adds one in-app line to the owner (counts only, no customer data).', 3307),
 ('mi_digest_on', 'switch', 'false'::jsonb, null::text, null::jsonb, null::numeric, null::numeric,
   'Weekly growth and market digest to the owner (in-app)',
   'OFF = no digest. ON = the digest function adds one in-app line to the owner each time it is run by the scheduled job (X1). The digest has numbers from your own sales and the open opportunities; it is never sent outside the app.', 3308)
  ) as v(key, kind, dv, unit, ch, mn, mx, lab, hint, srt)
on conflict (key) do nothing;

-- ---------- rights. None is given to anyone except the owner until the owner grants it ----------
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('market_view', 'reports', 3310, 'See the market intelligence workspace (findings, prices, opportunities, growth)', 'See the market intelligence workspace (findings, prices, opportunities, growth)', 'See the market intelligence workspace (findings, prices, opportunities, growth)', 'once', null),
 ('market_manage', 'reports', 3311, 'Add topics, sources, findings, prices, opportunities and decide them', 'Add topics, sources, findings, prices, opportunities and decide them', 'Add topics, sources, findings, prices, opportunities and decide them', 'once', null)
on conflict (grant_code) do nothing;

-- ---------- helpers (read-only, security definer, search_path fixed) ----------
create or replace function public._mi_on() returns boolean language sql stable security definer set search_path = public as $$ select public.rule_on('mi_on') $$;
create or replace function public._mi_can_view() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('market_view') or public.has_grant('market_manage')) $$;
create or replace function public._mi_can_manage() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('market_manage')) $$;
create or replace function public._mi_today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
-- a URL reduced to a comparable key: no scheme, no www, no query or fragment, no trailing slash, lower case
create or replace function public._mi_url_key(p text) returns text language sql immutable as $$
  select nullif(regexp_replace(lower(split_part(split_part(regexp_replace(btrim(coalesce(p, '')), '^https?://(www\.)?', '', 'i'), '?', 1), '#', 1)), '/+$', ''), '') $$;
-- every change of a write-once table is refused
create or replace function public._mi_append_only() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: this record can not be changed or removed'; end $$;

-- ---------- tables ----------
create table if not exists public.mi_topics (
  id uuid primary key default gen_random_uuid(),
  client_id uuid,
  category text not null check (category in ('competitors', 'products', 'prices', 'customer_trends', 'festivals', 'channels', 'technology', 'operations_ideas')),
  title_bn text not null check (char_length(btrim(title_bn)) between 1 and 160),
  title_en text check (title_en is null or char_length(title_en) <= 160),
  business_relevance text not null check (char_length(btrim(business_relevance)) between 3 and 600),
  location_id int references public.locations(id),
  brand_code text check (brand_code is null or char_length(brand_code) <= 20),
  owner_user uuid references public.profiles(id),
  review_every_days int check (review_every_days is null or review_every_days between 1 and 366),
  status text not null default 'active' check (status in ('active', 'retired')),
  retired_reason text check (retired_reason is null or char_length(retired_reason) <= 300),
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz not null default now(),
  check ((status = 'retired') = (retired_reason is not null))
);
create unique index if not exists mi_topics_client_uq on public.mi_topics (created_by, client_id) where client_id is not null;

create table if not exists public.mi_sources (
  id uuid primary key default gen_random_uuid(),
  client_id uuid,
  name text not null check (char_length(btrim(name)) between 1 and 160),
  url text not null check (char_length(btrim(url)) between 8 and 500),
  url_key text not null,
  publisher text not null check (char_length(btrim(publisher)) between 1 and 160),
  source_type text not null check (source_type in ('website', 'rss', 'sitemap', 'marketplace', 'social', 'report', 'manual_note', 'other')),
  reliability text not null check (reliability in ('A', 'B', 'C', 'D')),
  reliability_note text check (reliability_note is null or char_length(reliability_note) <= 300),
  terms_allow_scraping boolean not null default false,
  terms_checked_on date,
  robots_ok boolean,
  robots_checked_on date,
  rate_limit_per_hour int check (rate_limit_per_hour is null or rate_limit_per_hour between 1 and 3600),
  status text not null default 'active' check (status in ('active', 'retired')),
  retired_reason text check (retired_reason is null or char_length(retired_reason) <= 300),
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz not null default now(),
  check (terms_allow_scraping = false or terms_checked_on is not null),
  check ((status = 'retired') = (retired_reason is not null))
);
create unique index if not exists mi_sources_client_uq on public.mi_sources (created_by, client_id) where client_id is not null;
create index if not exists mi_sources_key on public.mi_sources (url_key);

create table if not exists public.mi_findings (
  id uuid primary key default gen_random_uuid(),
  client_id uuid,
  topic_id uuid references public.mi_topics(id),
  source_id uuid references public.mi_sources(id),
  source_url text not null check (char_length(btrim(source_url)) between 8 and 500),
  url_key text not null,
  publisher text not null check (char_length(btrim(publisher)) between 1 and 160),
  published_on date,
  retrieved_on date not null,
  title text check (title is null or char_length(title) <= 200),
  summary text not null check (char_length(btrim(summary)) between 3 and 1500),
  summary_key text not null,
  quote text check (quote is null or char_length(quote) <= 1000),
  finding_type text not null check (finding_type in ('sourced_fact', 'source_claim', 'analysis', 'hypothesis')),
  duplicate_of uuid references public.mi_findings(id),
  freshness_score int not null check (freshness_score between 0 and 3),
  quality_score int not null check (quality_score between 0 and 6),
  quality_basis text not null,
  created_by uuid, created_at timestamptz not null default now(),
  check (retrieved_on <= (now() at time zone 'Asia/Dhaka')::date + 1),
  check (published_on is null or published_on <= retrieved_on)
);
create unique index if not exists mi_findings_client_uq on public.mi_findings (created_by, client_id) where client_id is not null;
create index if not exists mi_findings_key on public.mi_findings (url_key, summary_key);

create table if not exists public.mi_finding_files (
  id bigint generated by default as identity primary key,
  finding_id uuid not null references public.mi_findings(id),
  storage_path text not null check (storage_path like 'market/%' and char_length(storage_path) <= 300),
  file_name text not null check (char_length(file_name) <= 200),
  mime text check (mime is null or char_length(mime) <= 80),
  created_by uuid, created_at timestamptz not null default now()
);

create table if not exists public.mi_price_obs (
  id bigint generated by default as identity primary key,
  client_id uuid,
  competitor text not null check (char_length(btrim(competitor)) between 1 and 160),
  item_id uuid references public.items(id),
  item_label text not null check (char_length(btrim(item_label)) between 1 and 200),
  price numeric(12, 2) not null check (price >= 0),
  unit text check (unit is null or char_length(unit) <= 30),
  observed_on date not null,
  source_url text check (source_url is null or char_length(source_url) <= 500),
  source_note text check (source_note is null or char_length(source_note) <= 300),
  created_by uuid, created_at timestamptz not null default now(),
  check (observed_on <= (now() at time zone 'Asia/Dhaka')::date + 1)
);
create unique index if not exists mi_price_obs_client_uq on public.mi_price_obs (created_by, client_id) where client_id is not null;
create index if not exists mi_price_obs_key on public.mi_price_obs (lower(competitor), lower(item_label), observed_on);

create table if not exists public.mi_offer_log (
  id bigint generated by default as identity primary key,
  client_id uuid,
  competitor text not null check (char_length(btrim(competitor)) between 1 and 160),
  offer_text text not null check (char_length(btrim(offer_text)) between 3 and 300),
  starts_on date, ends_on date,
  source_url text check (source_url is null or char_length(source_url) <= 500),
  created_by uuid, created_at timestamptz not null default now(),
  check (ends_on is null or starts_on is null or ends_on >= starts_on)
);

create table if not exists public.mi_product_gaps (
  id uuid primary key default gen_random_uuid(),
  topic_id uuid references public.mi_topics(id),
  product_label text not null check (char_length(btrim(product_label)) between 1 and 200),
  evidence_note text check (evidence_note is null or char_length(evidence_note) <= 500),
  status text not null default 'open' check (status in ('open', 'in_review', 'closed')),
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz not null default now()
);

create table if not exists public.mi_opportunities (
  id uuid primary key default gen_random_uuid(),
  client_id uuid,
  title text not null check (char_length(btrim(title)) between 3 and 160),
  category text not null check (category in ('competitors', 'products', 'prices', 'customer_trends', 'festivals', 'channels', 'technology', 'operations_ideas', 'growth_own_data')),
  topic_id uuid references public.mi_topics(id),
  location_id int references public.locations(id),
  scope_item_id uuid references public.items(id),
  evidence_finding_ids uuid[] not null default '{}',
  evidence_note text check (evidence_note is null or char_length(evidence_note) <= 600),
  benefit_low numeric(14, 2), benefit_base numeric(14, 2), benefit_basis text check (benefit_basis is null or char_length(benefit_basis) <= 600),
  cost_estimate numeric(14, 2), cost_basis text check (cost_basis is null or char_length(cost_basis) <= 600),
  assumptions text check (assumptions is null or char_length(assumptions) <= 1000),
  risks text check (risks is null or char_length(risks) <= 1000),
  confidence text not null check (confidence in ('low', 'medium', 'high')),
  confidence_limits text not null check (char_length(btrim(confidence_limits)) between 3 and 600),
  next_action text check (next_action is null or char_length(next_action) <= 300),
  approval_needed boolean not null default true,
  approval_note text check (approval_note is null or char_length(approval_note) <= 300),
  success_kpi text check (success_kpi is null or char_length(success_kpi) <= 200),
  kpi_baseline numeric(14, 2), kpi_target numeric(14, 2),
  owner_user uuid references public.profiles(id),
  review_due date,
  status text not null default 'proposed' check (status in ('proposed', 'saved', 'approved', 'rejected', 'in_progress', 'done', 'measured')),
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz not null default now()
);
create unique index if not exists mi_opp_client_uq on public.mi_opportunities (created_by, client_id) where client_id is not null;

create table if not exists public.mi_opp_decisions (
  id bigint generated by default as identity primary key,
  opp_id uuid not null references public.mi_opportunities(id),
  from_status text not null,
  to_status text not null,
  reason text not null check (length(btrim(reason)) >= 3 and length(reason) <= 300),
  decided_by uuid, decided_staff text, decided_at timestamptz not null default now()
);
create index if not exists mi_opp_decisions_key on public.mi_opp_decisions (opp_id, id);

create table if not exists public.mi_opp_links (
  id bigint generated by default as identity primary key,
  opp_id uuid not null references public.mi_opportunities(id),
  task_id uuid not null references public.crm_tasks(id),
  created_by uuid, created_at timestamptz not null default now()
);

create table if not exists public.mi_opp_outcomes (
  id bigint generated by default as identity primary key,
  opp_id uuid not null references public.mi_opportunities(id),
  window_from date not null, window_to date not null, base_from date not null, base_to date not null,
  scope jsonb not null,
  actual_value numeric(16, 2), baseline_value numeric(16, 2), change_value numeric(16, 2),
  actual_days int not null, baseline_days int not null,
  coverage_note text not null,
  warning text not null,
  created_by uuid, created_at timestamptz not null default now(),
  check (window_to >= window_from and base_to >= base_from)
);

create table if not exists public.mi_adapters (
  code text primary key check (code ~ '^[a-z][a-z0-9_]{2,30}$'),
  kind text not null check (kind in ('mock', 'rss', 'sitemap', 'search_api')),
  label text not null check (char_length(btrim(label)) between 3 and 120),
  network_allowed boolean not null default false,
  note text check (note is null or char_length(note) <= 300),
  created_at timestamptz not null default now()
);

create table if not exists public.mi_job_defs (
  key text primary key check (key ~ '^[a-z][a-z0-9_]{2,40}$'),
  label text not null check (char_length(btrim(label)) between 3 and 160),
  source_id uuid references public.mi_sources(id),
  adapter_code text not null references public.mi_adapters(code),
  schedule_cron text check (schedule_cron is null or char_length(schedule_cron) <= 60),
  enabled boolean not null default false,
  last_run_at timestamptz,
  updated_by uuid, updated_at timestamptz not null default now(), created_by uuid, created_at timestamptz not null default now(),
  check (enabled = false or source_id is not null)
);

-- AI summariser output: PROPOSALS only. Nothing is created from a proposal until a person accepts it outside this table.
create table if not exists public.mi_summary_proposals (
  id bigint generated by default as identity primary key,
  finding_ids uuid[] not null check (cardinality(finding_ids) between 1 and 20),
  proposed_text text not null check (char_length(btrim(proposed_text)) between 3 and 1500),
  proposed_by_agent text not null default 'market-research summariser',
  created_by uuid, created_at timestamptz not null default now()
);
create table if not exists public.mi_summary_decisions (
  id bigint generated by default as identity primary key,
  proposal_id bigint not null references public.mi_summary_proposals(id),
  decision text not null check (decision in ('accepted', 'rejected')),
  reason text not null check (length(btrim(reason)) >= 3 and length(reason) <= 300),
  decided_by uuid, decided_at timestamptz not null default now()
);

-- ---------- seeds: adapters (no network in any row) ----------
insert into public.mi_adapters (code, kind, label, network_allowed, note) values
 ('mock_offline', 'mock', 'Test adapter (no network, fixed sample data for tests)', false, 'Used only by the test suite. Never fetches anything.'),
 ('rss_feed', 'rss', 'Public RSS feed of a permitted source', false, 'Off until a source is switched on by the owner and the research gate (phase 533) passes.'),
 ('sitemap_page', 'sitemap', 'Public sitemap then title/date of pages the terms allow', false, 'Respects robots.txt and the terms flag. No login, no paywall bypass, no bulk copy.'),
 ('search_api', 'search_api', 'Paid search / research API (provider to be linked later)', false, 'Needs the owner to link a provider and a budget. Not linked today.')
on conflict (code) do nothing;

-- ---------- row level security: closed by default; reads only through the rights above; writes only through the functions (phase 488+) ----------
do $r$ declare t text; begin
  foreach t in array array['mi_topics', 'mi_sources', 'mi_findings', 'mi_finding_files', 'mi_price_obs', 'mi_offer_log', 'mi_product_gaps', 'mi_opportunities',
                           'mi_opp_decisions', 'mi_opp_links', 'mi_opp_outcomes', 'mi_job_defs', 'mi_adapters', 'mi_summary_proposals', 'mi_summary_decisions'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (public._mi_can_view())', t || '_read', t);
  end loop;
end $r$;

-- ---------- append-only and no-delete guards ----------
do $t$ declare t text; begin
  foreach t in array array['mi_findings', 'mi_finding_files', 'mi_price_obs', 'mi_offer_log', 'mi_opp_decisions', 'mi_opp_links', 'mi_opp_outcomes', 'mi_summary_proposals', 'mi_summary_decisions'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_ro', t);
    execute format('create trigger %I before update or delete on public.%I for each row execute function public._mi_append_only()', t || '_ro', t);
    execute format('drop trigger if exists %I on public.%I', t || '_ro_t', t);
    execute format('create trigger %I before truncate on public.%I for each statement execute function public._mi_append_only()', t || '_ro_t', t);
  end loop;
  foreach t in array array['mi_topics', 'mi_sources', 'mi_product_gaps', 'mi_opportunities', 'mi_job_defs', 'mi_adapters'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_nodel', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_nodel', t);
  end loop;
end $t$;

-- change log (who, when, what) for every table that is edited in place
drop trigger if exists audit_mi_topics on public.mi_topics;
create trigger audit_mi_topics after insert or update on public.mi_topics for each row execute function public.log_change('id');
drop trigger if exists audit_mi_sources on public.mi_sources;
create trigger audit_mi_sources after insert or update on public.mi_sources for each row execute function public.log_change('id');
drop trigger if exists audit_mi_opportunities on public.mi_opportunities;
create trigger audit_mi_opportunities after insert or update on public.mi_opportunities for each row execute function public.log_change('id');
drop trigger if exists audit_mi_job_defs on public.mi_job_defs;
create trigger audit_mi_job_defs after insert or update on public.mi_job_defs for each row execute function public.log_change('key');

-- writes are never granted directly; the functions in phase 488 / 489 / 490 are the only way in
revoke all on function public._mi_on(), public._mi_can_view(), public._mi_can_manage(), public._mi_today(), public._mi_url_key(text), public._mi_append_only() from public, anon;
grant execute on function public._mi_can_view(), public._mi_can_manage(), public._mi_on() to authenticated;

notify pgrst, 'reload schema';
