-- ============================================================
-- Phase 484 - X4 AI foundation: provider registry, monthly budgets, redaction rules, agent catalogue, AI call log.
-- Run AFTER phase478 (owner order). Additive and idempotent: paste it twice = no error. Nothing here changes business data.
-- Everything is OFF by default: rule ai_on = false, provider local_rules only, every agent disabled.
--   * No API key is ever stored in a table or a rule. A paid provider keeps its key as a Supabase secret (docs/AI_DEPLOY.md).
--   * A paid provider cannot run without a monthly budget (tokens or money). Money is estimated ONLY from prices the owner typed; blank price = no money figure.
--   * An agent may only PROPOSE (suggestion rows, phase 485). Untrusted-input agents (customer messages, web pages, photos) get NO proposal actions (table check + trigger).
--   * An agent cannot hold a forbidden grant (trigger on ai_agent_grants).
--   * ai_calls is append-only and carries actor_type ('human' | 'agent' | 'system').
-- Naming: every object starts with ai_ or _ai_ (no collision with the existing phases).
-- ============================================================

-- ---------- rules (switches; safe defaults) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('ai_on', 'ai', 'switch', 'false', null, null, null, null, 'AI সহায়ক চালু (প্রদানকারী যোগ করার পরে)', 'AI helper চালু (provider যোগ করার পরে)', 'AI helpers are on (after a provider is linked)',
  'বন্ধ থাকলে কোনো AI কল হয় না, কোনো খরচ হয় না। ডিফল্ট: বন্ধ।', 'When off, no AI call is made and nothing is spent. Default: off.', 950),
 ('ai_pause_all', 'ai', 'switch', 'false', null, null, null, null, 'সব AI এখনই বন্ধ (জরুরি স্টপ)', 'সব AI এখনই বন্ধ (emergency stop)', 'Pause all AI now (emergency stop)',
  'চালু করলে সব এজেন্ট ও সব প্রদানকারী থেমে যায়। কোনো প্রস্তাব তৈরি হয় না।', 'ON stops every agent and every provider at once. No proposals are made.', 951),
 ('ai_default_provider', 'ai', 'choice', '"local_rules"', null, '["local_rules","anthropic","openai_compatible","gemini","custom_http"]'::jsonb, null, null, 'ডিফল্ট AI প্রদানকারী', 'Default AI provider', 'Default AI provider',
  'local_rules = ফোনেই, বিনা খরচে। অন্য প্রদানকারী শুধু মালিক চালু করলে ও বাজেট দিলে কাজ করে।', 'local_rules = on the phone, free. Other providers work only after the owner enables them and sets a budget.', 952),
 ('ai_speech_on', 'ai', 'switch', 'false', null, null, null, null, 'কথা বলে প্রশ্ন (ব্রাউজারের স্পিচ-টু-টেক্সট)', 'Voice question (browser speech-to-text)', 'Voice questions (browser speech-to-text)',
  'বন্ধ থাকলে মাইক্রোফোন বাটন দেখানো হয় না।', 'When off, no microphone button is shown.', 953)
on conflict (key) do nothing;

-- ---------- providers (no key column, ever) ----------
create table if not exists public.ai_providers (
  code text primary key check (code ~ '^[a-z][a-z0-9_]{1,30}$'),
  kind text not null check (kind in ('local_rules', 'anthropic', 'openai_compatible', 'gemini', 'custom_http')),
  label text not null check (length(btrim(label)) between 2 and 80),
  model text check (model is null or length(model) <= 80),
  enabled boolean not null default false,
  data_sharing text not null default 'none' check (data_sharing in ('none', 'redacted', 'full')),
  timeout_ms int not null default 15000 check (timeout_ms between 1000 and 60000),
  max_output_tokens int not null default 1024 check (max_output_tokens between 64 and 8192),
  monthly_token_budget bigint check (monthly_token_budget is null or monthly_token_budget >= 0),
  monthly_money_budget numeric(12, 2) check (monthly_money_budget is null or monthly_money_budget >= 0),
  price_in_per_mtok numeric(12, 4) check (price_in_per_mtok is null or price_in_per_mtok >= 0),
  price_out_per_mtok numeric(12, 4) check (price_out_per_mtok is null or price_out_per_mtok >= 0),
  fallback_order int not null default 100 check (fallback_order between 1 and 999),
  key_location text not null default 'supabase_secret' check (key_location in ('supabase_secret', 'none')),
  updated_at timestamptz not null default now(), updated_by uuid,
  check (kind = 'local_rules' or enabled = false or monthly_token_budget is not null or monthly_money_budget is not null)
);
insert into public.ai_providers (code, kind, label, model, enabled, data_sharing, fallback_order, key_location) values
 ('local_rules', 'local_rules', 'ফোনের নিয়ম-ভিত্তিক সহকারী (বিনা খরচে)', null, true, 'none', 1, 'none'),
 ('anthropic', 'anthropic', 'Anthropic (Claude)', null, false, 'none', 10, 'supabase_secret'),
 ('openai_compatible', 'openai_compatible', 'OpenAI-compatible API', null, false, 'none', 20, 'supabase_secret'),
 ('gemini', 'gemini', 'Google Gemini', null, false, 'none', 30, 'supabase_secret'),
 ('custom_http', 'custom_http', 'নিজস্ব HTTP প্রদানকারী', null, false, 'none', 40, 'supabase_secret')
on conflict (code) do nothing;
alter table public.ai_providers enable row level security;
revoke all on public.ai_providers from public, anon, authenticated;
grant select on public.ai_providers to authenticated;
drop policy if exists ai_providers_owner_read on public.ai_providers;
create policy ai_providers_owner_read on public.ai_providers for select to authenticated using (public.is_owner());
drop trigger if exists ai_providers_nodel on public.ai_providers;
create trigger ai_providers_nodel before delete on public.ai_providers for each row execute function public.no_hard_delete();
drop trigger if exists audit_ai_providers on public.ai_providers;
create trigger audit_ai_providers after insert or update on public.ai_providers for each row execute function public.log_change('code');

-- ---------- redaction rules (applied in the browser BEFORE any text leaves the phone; the server re-checks) ----------
create table if not exists public.ai_redaction_rules (
  code text primary key check (code ~ '^[a-z][a-z0-9_]{1,40}$'),
  label text not null,
  pattern text not null check (length(pattern) between 3 and 300),
  replacement text not null default '[redacted]' check (length(replacement) <= 40),
  enabled boolean not null default true,
  sort int not null default 0,
  updated_at timestamptz not null default now(), updated_by uuid
);
insert into public.ai_redaction_rules (code, label, pattern, replacement, sort) values
 ('bd_mobile', 'বাংলাদেশি মোবাইল নম্বর', '(\+?88)?01[3-9][0-9]{8}', '[phone]', 10),
 ('email', 'ইমেইল ঠিকানা', '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '[email]', 20),
 ('national_id', 'জাতীয় পরিচয়পত্র নম্বর (১০/১৭ সংখ্যা)', '\b[0-9]{10}([0-9]{3}|[0-9]{7})?\b', '[id]', 30),
 ('card_like', 'কার্ড-সদৃশ সংখ্যা', '\b(?:[0-9][ -]?){13,19}\b', '[card]', 40),
 ('secret_key', 'API কী / টোকেন', '(sk-[A-Za-z0-9_-]{16,}|eyJ[A-Za-z0-9_-]{20,})', '[secret]', 50),
 ('pin_words', 'PIN / পাসওয়ার্ড লেখা', '(pin|password|পিন|পাসওয়ার্ড)\s*[:=]?\s*[0-9০-৯]{3,8}', '[secret]', 60)
on conflict (code) do nothing;
alter table public.ai_redaction_rules enable row level security;
revoke all on public.ai_redaction_rules from public, anon, authenticated;
grant select on public.ai_redaction_rules to authenticated;
drop policy if exists ai_redaction_read on public.ai_redaction_rules;
create policy ai_redaction_read on public.ai_redaction_rules for select to authenticated using (public.is_active());
drop trigger if exists ai_redaction_nodel on public.ai_redaction_rules;
create trigger ai_redaction_nodel before delete on public.ai_redaction_rules for each row execute function public.no_hard_delete();

-- ---------- agent catalogue (configuration rows; every agent OFF by default) ----------
create table if not exists public.ai_agents (
  code text primary key check (code ~ '^[a-z][a-z0-9_]{2,40}$'),
  label_bn text not null, label_en text not null,
  purpose text check (purpose is null or length(purpose) <= 300),
  prompt_version text not null default 'v1' check (prompt_version ~ '^v[0-9]{1,3}(\.[0-9]{1,3})?$'),
  enabled boolean not null default false,
  provider_code text not null default 'local_rules' references public.ai_providers(code),
  data_scope text not null default 'none' check (data_scope in ('none', 'summary', 'detail')),
  read_tools text[] not null default '{}',
  proposal_actions text[] not null default '{}',
  untrusted_input boolean not null default false,
  monthly_token_budget bigint check (monthly_token_budget is null or monthly_token_budget >= 0),
  approval text not null default 'approver' check (approval in ('owner', 'approver')),
  sort int not null default 0,
  updated_at timestamptz not null default now(), updated_by uuid,
  check (not untrusted_input or cardinality(proposal_actions) = 0)
);
-- forbidden words: an agent may never be given an action that publishes, deletes, changes rules, grants, roles, the books, money or prices
create or replace function public._ai_forbidden(p text) returns boolean
language sql immutable set search_path = public as $$
  select p ~* '(publish|delete|rule|grant|role|journal|pay|spend|price|schema|send|void|refund|permission|approve|transfer|emergency|owner|user|password|secret|key)';
$$;

create or replace function public._ai_agent_guard() returns trigger
language plpgsql set search_path = public as $$
declare a text;
begin
  foreach a in array coalesce(new.proposal_actions, '{}') loop
    if a !~ '^[a-z]{2,20}\.[a-z_]{2,30}$' then raise exception 'bad_action_name'; end if;
    if public._ai_forbidden(a) then raise exception 'forbidden_action'; end if;
  end loop;
  foreach a in array coalesce(new.read_tools, '{}') loop
    if a !~ '^[a-z0-9_]{1,40}$' then raise exception 'bad_tool_name'; end if;
  end loop;
  if new.untrusted_input and cardinality(coalesce(new.proposal_actions, '{}')) > 0 then raise exception 'untrusted_input_no_proposals'; end if;
  return new;
end $$;
drop trigger if exists ai_agents_guard on public.ai_agents;
create trigger ai_agents_guard before insert or update on public.ai_agents for each row execute function public._ai_agent_guard();
drop trigger if exists ai_agents_nodel on public.ai_agents;
create trigger ai_agents_nodel before delete on public.ai_agents for each row execute function public.no_hard_delete();

insert into public.ai_agents (code, label_bn, label_en, purpose, sort, enabled, read_tools, proposal_actions, untrusted_input, approval) values
 ('erp_guide', 'ERP গাইড ও সেটআপ সহকারী', 'ERP guide and setup helper', 'Explains screens and lists the setup steps still missing.', 10, false, '{assistant_me,assistant_health}', '{setup.draft_checklist}', false, 'owner'),
 ('sales_analyst', 'বিক্রি ও স্টক বিশ্লেষক', 'Sales and inventory analyst', 'Reads sales and stock reports and writes short insight notes.', 20, false, '{sales_summary,top_items,sales_trend,stock_low}', '{insight.note}', false, 'approver'),
 ('report_explainer', 'রিপোর্ট ব্যাখ্যাকারী / অস্বাভাবিকতা', 'Report explainer and anomaly investigator', 'Explains a report movement and points at the exception to check.', 30, false, '{what_changed,unusual,exceptions_summary}', '{insight.note}', false, 'approver'),
 ('marketing_drafter', 'মার্কেটিং ও কনটেন্ট খসড়াকারী', 'Marketing and content drafter', 'Drafts posts and messages for a human to edit and publish by hand.', 40, false, '{}', '{content.draft}', false, 'approver'),
 ('enquiry_classifier', 'অনুসন্ধান শ্রেণিকারী ও উত্তর-খসড়া', 'Enquiry classifier and reply drafter', 'Reads customer messages (untrusted): labels them. No proposal action.', 50, false, '{}', '{}', true, 'approver'),
 ('order_assistant', 'চ্যাট থেকে অর্ডার-খসড়া', 'Chat-to-order draft assistant', 'Turns a customer chat into a suggestion; a person creates the order. Untrusted input: no proposal action.', 60, false, '{}', '{}', true, 'approver'),
 ('production_planner', 'উৎপাদন পরিকল্পনা প্রস্তাবক', 'Production planning suggester', 'Suggests a production plan from sales and stock. Suggestion only.', 70, false, '{top_items,stock_low}', '{production.suggest_plan}', false, 'approver'),
 ('supplier_watcher', 'সরবরাহকারী মূল্য পর্যবেক্ষক', 'Supplier price watcher', 'Notes supplier-cost movements for a human. Never changes a price.', 80, false, '{payables,purchases_by_supplier}', '{supplier.watch_note}', false, 'approver'),
 ('market_summariser', 'বাজার-গবেষণা সারসংক্ষেপক', 'Market research summariser', 'Summarises notes a person pastes. Untrusted web text: no proposal action.', 90, false, '{}', '{}', true, 'approver'),
 ('camera_matcher', 'ক্যামেরা / আইটেম মিলানো সহকারী', 'Camera and item matching helper', 'Suggests a matching item name. Photos are untrusted: no proposal action.', 100, false, '{}', '{}', true, 'approver')
on conflict (code) do nothing;
alter table public.ai_agents enable row level security;
revoke all on public.ai_agents from public, anon, authenticated;
grant select on public.ai_agents to authenticated;
drop policy if exists ai_agents_owner_read on public.ai_agents;
create policy ai_agents_owner_read on public.ai_agents for select to authenticated using (public.is_owner());
drop trigger if exists audit_ai_agents on public.ai_agents;
create trigger audit_ai_agents after insert or update on public.ai_agents for each row execute function public.log_change('code');

-- ---------- agent grants: declared scope; a forbidden grant is refused ----------
create table if not exists public.ai_agent_grants (
  agent_code text not null references public.ai_agents(code),
  grant_code text not null check (grant_code ~ '^[a-z][a-z0-9_]{2,40}$'),
  granted_by uuid, granted_at timestamptz not null default now(),
  primary key (agent_code, grant_code)
);
create or replace function public._ai_grant_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if public._ai_forbidden(new.grant_code) or new.grant_code in ('assistant_use', 'assistant_health', 'head_management') then raise exception 'forbidden_grant'; end if;
  return new;
end $$;
drop trigger if exists ai_agent_grants_guard on public.ai_agent_grants;
create trigger ai_agent_grants_guard before insert or update on public.ai_agent_grants for each row execute function public._ai_grant_guard();
alter table public.ai_agent_grants enable row level security;
revoke all on public.ai_agent_grants from public, anon, authenticated;
grant select on public.ai_agent_grants to authenticated;
drop policy if exists ai_agent_grants_owner_read on public.ai_agent_grants;
create policy ai_agent_grants_owner_read on public.ai_agent_grants for select to authenticated using (public.is_owner());

-- ---------- AI call log (append-only; no business content, no key) ----------
create table if not exists public.ai_calls (
  id bigserial primary key,
  at timestamptz not null default now(),
  user_id uuid,
  actor_type text not null default 'human' check (actor_type in ('human', 'agent', 'system')),
  agent_code text,
  provider_code text not null references public.ai_providers(code),
  kind text not null check (kind in ('call', 'proposal', 'blocked', 'budget_stop', 'redaction', 'timeout', 'invalid_output', 'eval')),
  tokens_in int not null default 0 check (tokens_in between 0 and 10000000),
  tokens_out int not null default 0 check (tokens_out between 0 and 10000000),
  ms int not null default 0 check (ms between 0 and 600000),
  money_est numeric(12, 6) check (money_est is null or money_est >= 0),
  ok boolean not null default true,
  reason text check (reason is null or length(reason) <= 200)
);
create index if not exists ai_calls_at on public.ai_calls (at);
create index if not exists ai_calls_provider_at on public.ai_calls (provider_code, at);
alter table public.ai_calls enable row level security;
revoke all on public.ai_calls from public, anon, authenticated;
grant select on public.ai_calls to authenticated;
drop policy if exists ai_calls_owner_read on public.ai_calls;
create policy ai_calls_owner_read on public.ai_calls for select to authenticated using (public.is_owner());
create or replace function public._ai_ro() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'ai_calls is append-only'; end $$;
drop trigger if exists ai_calls_ro on public.ai_calls;
create trigger ai_calls_ro before update or delete on public.ai_calls for each row execute function public._ai_ro();
drop trigger if exists ai_calls_ro_t on public.ai_calls;
create trigger ai_calls_ro_t before truncate on public.ai_calls for each statement execute function public._ai_ro();

-- ---------- helpers ----------
-- who may use AI helpers: the owner, or a person with assistant_use (the same right as the assistant screen)
create or replace function public._ai_can_use() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('assistant_use'));
$$;

-- rank of a data level: none 0 < redacted 1 < full 2
create or replace function public._ai_level_rank(p text) returns int
language sql immutable set search_path = public as $$
  select case p when 'none' then 0 when 'redacted' then 1 when 'full' then 2 else null end;
$$;

-- this month's use of one provider (Asia/Dhaka month); money only counts rows that had a price
create or replace function public._ai_month_use(p_provider text, p_agent text default null)
returns table (tokens bigint, money numeric) language sql stable security definer set search_path = public as $$
  select coalesce(sum(c.tokens_in + c.tokens_out), 0)::bigint, coalesce(sum(c.money_est), 0)
    from public.ai_calls c
   where (p_agent is null and c.provider_code = p_provider or p_agent is not null and c.agent_code = p_agent)
     and c.ok and (c.at at time zone 'Asia/Dhaka') >= date_trunc('month', now() at time zone 'Asia/Dhaka');
$$;

-- ---------- the one gate every AI call passes (edge function and browser both ask it, with the user's JWT) ----------
create or replace function public.ai_check(p_provider text, p_agent text default null, p_data_level text default 'none', p_est_tokens int default 0)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare p public.ai_providers; a public.ai_agents; u record; ag record; est int := greatest(coalesce(p_est_tokens, 0), 0);
begin
  if not public._ai_can_use() then return jsonb_build_object('ok', false, 'reason', 'not_allowed'); end if;
  if not public.rule_on('ai_on') then return jsonb_build_object('ok', false, 'reason', 'ai_off'); end if;
  if public.rule_on('ai_pause_all') then return jsonb_build_object('ok', false, 'reason', 'paused'); end if;
  if public._ai_level_rank(p_data_level) is null then return jsonb_build_object('ok', false, 'reason', 'bad_level'); end if;
  select * into p from public.ai_providers where code = p_provider;
  if not found then return jsonb_build_object('ok', false, 'reason', 'unknown_provider'); end if;
  if not p.enabled then return jsonb_build_object('ok', false, 'reason', 'provider_off'); end if;
  if p_agent is not null then
    select * into a from public.ai_agents where code = p_agent;
    if not found then return jsonb_build_object('ok', false, 'reason', 'unknown_agent'); end if;
    if not a.enabled then return jsonb_build_object('ok', false, 'reason', 'agent_off'); end if;
    if a.provider_code <> p_provider then return jsonb_build_object('ok', false, 'reason', 'agent_provider_mismatch'); end if;
  end if;
  if p.kind = 'local_rules' then return jsonb_build_object('ok', true, 'reason', 'local', 'provider', p_provider); end if;
  -- a paid provider: data level must not exceed what the provider may see
  if public._ai_level_rank(p_data_level) > public._ai_level_rank(p.data_sharing) then return jsonb_build_object('ok', false, 'reason', 'data_not_allowed'); end if;
  if p.monthly_token_budget is null and p.monthly_money_budget is null then return jsonb_build_object('ok', false, 'reason', 'no_budget'); end if;
  select * into u from public._ai_month_use(p_provider, null);
  if p.monthly_token_budget is not null and u.tokens + est > p.monthly_token_budget then return jsonb_build_object('ok', false, 'reason', 'budget_spent', 'used', u.tokens, 'budget', p.monthly_token_budget); end if;
  if p.monthly_money_budget is not null then
    if p.price_in_per_mtok is null or p.price_out_per_mtok is null then return jsonb_build_object('ok', false, 'reason', 'price_needed'); end if;
    if u.money >= p.monthly_money_budget then return jsonb_build_object('ok', false, 'reason', 'money_budget_spent'); end if;
  end if;
  if p_agent is not null and a.monthly_token_budget is not null then
    select * into ag from public._ai_month_use(p_provider, p_agent);
    if ag.tokens + est > a.monthly_token_budget then return jsonb_build_object('ok', false, 'reason', 'agent_budget_spent'); end if;
  end if;
  return jsonb_build_object('ok', true, 'reason', 'within_budget', 'provider', p_provider, 'tokens_used', u.tokens,
    'tokens_left', case when p.monthly_token_budget is null then null else p.monthly_token_budget - u.tokens end);
end $$;

-- one call log row (human or agent). The caller is the signed-in person; the agent name is only a label.
create or replace function public.ai_log(p_provider text, p_agent text, p_kind text, p_tokens_in int, p_tokens_out int, p_ms int,
                                         p_money numeric default null, p_ok boolean default true, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.ai_calls; p public.ai_providers;
begin
  if not public._ai_can_use() then raise exception 'not allowed'; end if;
  select * into p from public.ai_providers where code = p_provider;
  if not found then raise exception 'unknown_provider'; end if;
  if p_kind not in ('call', 'proposal', 'blocked', 'budget_stop', 'redaction', 'timeout', 'invalid_output', 'eval') then raise exception 'bad_kind'; end if;
  if coalesce(p_tokens_in, 0) not between 0 and 10000000 or coalesce(p_tokens_out, 0) not between 0 and 10000000 or coalesce(p_ms, 0) not between 0 and 600000 then raise exception 'bad_number'; end if;
  insert into public.ai_calls (user_id, actor_type, agent_code, provider_code, kind, tokens_in, tokens_out, ms, money_est, ok, reason)
    values (auth.uid(), case when p_agent is null then 'human' else 'agent' end, p_agent, p_provider, p_kind,
            coalesce(p_tokens_in, 0), coalesce(p_tokens_out, 0), coalesce(p_ms, 0),
            case when p_money is not null then p_money
                 when p.price_in_per_mtok is not null and p.price_out_per_mtok is not null
                 then round((coalesce(p_tokens_in, 0) * p.price_in_per_mtok + coalesce(p_tokens_out, 0) * p.price_out_per_mtok) / 1000000.0, 6) end,
            coalesce(p_ok, true), left(p_reason, 200))
    returning * into r;
  return jsonb_build_object('id', r.id, 'actor_type', r.actor_type);
end $$;

-- ---------- owner-only configuration RPCs ----------
create or replace function public.ai_provider_save(p_code text, p_kind text, p_label text, p_model text, p_enabled boolean, p_data_sharing text,
    p_timeout_ms int, p_max_out int, p_budget_tokens bigint, p_budget_money numeric, p_price_in numeric, p_price_out numeric, p_fallback int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.ai_providers;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_kind is null or p_kind not in ('local_rules', 'anthropic', 'openai_compatible', 'gemini', 'custom_http') then raise exception 'bad_kind'; end if;
  if p_data_sharing is null or p_data_sharing not in ('none', 'redacted', 'full') then raise exception 'bad_sharing'; end if;
  if p_kind <> 'local_rules' and p_enabled and p_budget_tokens is null and p_budget_money is null then raise exception 'budget_needed'; end if;
  if p_kind <> 'local_rules' and p_enabled and (p_model is null or btrim(p_model) = '') then raise exception 'model_needed'; end if;
  if p_budget_tokens is not null and p_budget_tokens < 0 then raise exception 'bad_budget'; end if;
  insert into public.ai_providers as t (code, kind, label, model, enabled, data_sharing, timeout_ms, max_output_tokens, monthly_token_budget, monthly_money_budget,
      price_in_per_mtok, price_out_per_mtok, fallback_order, updated_at, updated_by)
    values (p_code, p_kind, coalesce(nullif(btrim(p_label), ''), p_code), nullif(btrim(p_model), ''), coalesce(p_enabled, false), p_data_sharing,
      coalesce(p_timeout_ms, 15000), coalesce(p_max_out, 1024), p_budget_tokens, p_budget_money, p_price_in, p_price_out, coalesce(p_fallback, 100), now(), auth.uid())
    on conflict (code) do update set kind = excluded.kind, label = excluded.label, model = excluded.model, enabled = excluded.enabled,
      data_sharing = excluded.data_sharing, timeout_ms = excluded.timeout_ms, max_output_tokens = excluded.max_output_tokens,
      monthly_token_budget = excluded.monthly_token_budget, monthly_money_budget = excluded.monthly_money_budget,
      price_in_per_mtok = excluded.price_in_per_mtok, price_out_per_mtok = excluded.price_out_per_mtok,
      fallback_order = excluded.fallback_order, updated_at = now(), updated_by = auth.uid()
    returning * into r;
  return jsonb_build_object('code', r.code, 'enabled', r.enabled);
end $$;

create or replace function public.ai_agent_save(p_code text, p_enabled boolean, p_provider text, p_data_scope text, p_read_tools text[],
    p_proposals text[], p_untrusted boolean, p_budget bigint, p_approval text, p_prompt_version text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.ai_agents;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.ai_agents where code = p_code) then raise exception 'not_found'; end if;
  if p_approval not in ('owner', 'approver') then raise exception 'bad_approval'; end if;
  if p_data_scope not in ('none', 'summary', 'detail') then raise exception 'bad_scope'; end if;
  update public.ai_agents set enabled = coalesce(p_enabled, false), provider_code = coalesce(p_provider, 'local_rules'), data_scope = p_data_scope,
      read_tools = coalesce(p_read_tools, '{}'), proposal_actions = coalesce(p_proposals, '{}'), untrusted_input = coalesce(p_untrusted, true),
      monthly_token_budget = p_budget, approval = p_approval, prompt_version = coalesce(p_prompt_version, prompt_version), updated_at = now(), updated_by = auth.uid()
    where code = p_code returning * into r;
  return jsonb_build_object('code', r.code, 'enabled', r.enabled);
end $$;

create or replace function public.ai_agent_grant_set(p_agent text, p_grant text, p_on boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_on then
    insert into public.ai_agent_grants (agent_code, grant_code, granted_by) values (p_agent, p_grant, auth.uid()) on conflict do nothing;
  else
    -- a grant is never deleted from the log: the row stays in ai_agent_grants only while it is held (declared scope, not history)
    delete from public.ai_agent_grants where agent_code = p_agent and grant_code = p_grant;
  end if;
  return jsonb_build_object('agent', p_agent, 'grant', p_grant, 'on', coalesce(p_on, false));
end $$;

create or replace function public.ai_pause_all(p_on boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  perform public.set_rule('ai_pause_all', to_jsonb(coalesce(p_on, false)));
  return jsonb_build_object('ai_pause_all', coalesce(p_on, false));
end $$;

-- the picker: enabled agents only, with the pieces the screen shows (no prompt text, no secrets)
create or replace function public.ai_agents_me() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not public._ai_can_use() then '[]'::jsonb else coalesce((
    select jsonb_agg(jsonb_build_object('code', a.code, 'label_bn', a.label_bn, 'label_en', a.label_en, 'provider', a.provider_code,
           'untrusted_input', a.untrusted_input, 'proposals', to_jsonb(a.proposal_actions), 'prompt_version', a.prompt_version) order by a.sort)
      from public.ai_agents a where a.enabled), '[]'::jsonb) end;
$$;

-- privileges
revoke all on function public._ai_forbidden(text), public._ai_agent_guard(), public._ai_grant_guard(), public._ai_ro(),
  public._ai_level_rank(text), public._ai_month_use(text, text) from public, anon, authenticated;
-- _ai_can_use() only answers "may this person use AI" for the caller; the row policies call it as the signed-in person
revoke all on function public._ai_can_use() from public, anon;
grant execute on function public._ai_can_use() to authenticated;
revoke all on function public.ai_check(text, text, text, int), public.ai_log(text, text, text, int, int, int, numeric, boolean, text),
  public.ai_provider_save(text, text, text, text, boolean, text, int, int, bigint, numeric, numeric, numeric, int),
  public.ai_agent_save(text, boolean, text, text, text[], text[], boolean, bigint, text, text), public.ai_agent_grant_set(text, text, boolean),
  public.ai_pause_all(boolean), public.ai_agents_me() from public, anon;
grant execute on function public.ai_check(text, text, text, int), public.ai_log(text, text, text, int, int, int, numeric, boolean, text),
  public.ai_provider_save(text, text, text, text, boolean, text, int, int, bigint, numeric, numeric, numeric, int),
  public.ai_agent_save(text, boolean, text, text, text[], text[], boolean, bigint, text, text), public.ai_agent_grant_set(text, text, boolean),
  public.ai_pause_all(boolean), public.ai_agents_me() to authenticated;
