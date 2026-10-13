-- ============================================================
-- Phase 47 - Module G: business assistant (READ-ONLY MVP). Run AFTER phase28. Additive and idempotent (paste it twice = no error).
-- Does not depend on phases 40-46: optional modules (accounting, partners, tiers, backups) are detected at call time (to_regclass / pg_proc).
--
-- What this adds (nothing here changes business data):
--   * rules (Switchboard): assistant_on (ON), assistant_roles (blank = owner + head management + grant assistant_use), assistant_provider (local | llm_proxy,
--     default local), assistant_monthly_token_budget (blank = no paid model may run), assistant_cache_seconds (60), assistant_actions_on (OFF, reserved -
--     the MVP has no write actions), assistant_voice_on (OFF), assistant_rate_per_hour (120), assistant_closed_age_days (45)
--   * grants: assistant_use (may use the assistant), assistant_health (may run the configuration check)
--   * assistant_notes    owner-approved business rules / procedures / facts the assistant quotes as "approved by owner" (owner writes via RPC; never secrets)
--   * assistant_usage    append-only log WITHOUT business content: who, when, provider, intent, tool keys, ms, tokens, ok
--   * assistant_me()        what the caller may ask (capability map; the server still decides on every call)
--   * assistant_health()    read-only findings about incomplete / conflicting configuration, each with a route to the fixing screen
--   * assistant_log(...)    one usage row (with a per-hour rate limit); assistant_usage_summary(month) owner-only token / cost counters
--   * assistant_note_save / assistant_note_retire (owner only)
-- Security: every function is security definer with search_path public, checks is_active, and never takes SQL / table / function names from the caller.
-- ============================================================

-- ---------- rules ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('assistant_on', 'assistant', 'switch', 'true', null, null, null, null, 'ব্যবসার সহকারী (প্রশ্ন করুন) চালু', 'Business assistant (Ask) চালু', 'Business assistant (Ask) is on',
  'শুধু পড়ে: রিপোর্ট ও সেটআপ থেকে উত্তর দেয়, কিছু বদলায় না। কে ব্যবহার করবেন: মালিক, হেড ম্যানেজমেন্ট ও assistant_use অনুমতি।', 'Read-only: answers from reports and setup, changes nothing. Used by the owner, head management and holders of assistant_use.', 900),
 ('assistant_roles', 'assistant', 'text', null, null, null, null, null, 'আর কোন ভূমিকা সহকারী ব্যবহার করবে (কোড, কমা দিয়ে; * = সবাই)', 'আর কোন role assistant ব্যবহার করবে (code, comma; * = সবাই)', 'Other roles that may use the assistant (codes, comma separated; * = everyone)',
  'ফাঁকা = শুধু মালিক, হেড ম্যানেজমেন্ট ও assistant_use। প্রত্যেক উত্তর তবুও ব্যবহারকারীর নিজের অনুমতি মানে।', 'Blank = owner, head management and assistant_use only. Every answer still follows the person''s own rights.', 901),
 ('assistant_provider', 'assistant', 'choice', '"local"', null, '["local","llm_proxy"]'::jsonb, null, null, 'সহকারীর বুদ্ধি: ফোনেই (বিনা খরচে) / AI প্রক্সি', 'Assistant engine: phone-এ (free) / AI proxy', 'Assistant engine: on the phone (free) / AI proxy',
  'llm_proxy কাজ করবে শুধু মালিক Edge Function বসালে ও মাসিক টোকেন সীমা দিলে; নইলে ফোনেই চলে।', 'llm_proxy works only after the owner deploys the Edge Function and sets a monthly token budget; otherwise it stays local.', 902),
 ('assistant_monthly_token_budget', 'assistant', 'number', null, 'tokens', null, 0, 100000000, 'AI প্রক্সির মাসিক টোকেন সীমা', 'AI proxy-র monthly token limit', 'AI proxy monthly token budget',
  'ফাঁকা = কোনো পেইড মডেল চলবে না।', 'Blank = no paid model may run.', 903),
 ('assistant_cache_seconds', 'assistant', 'number', '60', 'sec', null, 0, 600, 'একই প্রশ্নের উত্তর কত সেকেন্ড মনে রাখবে', 'একই প্রশ্নের উত্তর কত second মনে রাখবে', 'Seconds a tool answer is reused', null, null, 904),
 ('assistant_actions_on', 'assistant', 'switch', 'false', null, null, null, null, 'সহকারী থেকে কাজ (লিখা) — এখন বন্ধ, পরে', 'Assistant থেকে action (write) — এখন বন্ধ', 'Assistant actions (writes) - reserved, off',
  'এই সংস্করণে সহকারী কিছুই লেখে না; শুধু সঠিক পেজ খোলার লিংক দেয়।', 'This version writes nothing; it only links to the right screen.', 905),
 ('assistant_voice_on', 'assistant', 'switch', 'false', null, null, null, null, 'সহকারীতে কথা বলে প্রশ্ন', 'Assistant-এ voice input', 'Voice input in the assistant', null, null, 906),
 ('assistant_rate_per_hour', 'assistant', 'number', '120', null, null, 1, 10000, 'এক ঘণ্টায় একজন সর্বোচ্চ কত প্রশ্ন', 'এক ঘণ্টায় একজন সর্বোচ্চ কত প্রশ্ন', 'Most questions per person per hour', null, null, 907),
 ('assistant_closed_age_days', 'assistant', 'number', '45', 'days', null, 1, 3650, 'হিসাব বন্ধের তারিখ কত দিনের পুরনো হলে মনে করাবে', 'Books closed date কত দিন পুরনো হলে মনে করাবে', 'Remind when the books-closed date is older than (days)', null, null, 908)
on conflict (key) do nothing;

-- ---------- grants ----------
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'assistant_use', 'reports', 90, 'ব্যবসার সহকারী ব্যবহার', 'Business assistant ব্যবহার', 'Use the business assistant', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'assistant_use');
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'assistant_health', 'reports', 91, 'সেটআপ-চেক (কনফিগারেশনের ঘাটতি) দেখা', 'Setup check (configuration gap) দেখা', 'See the setup check (configuration gaps)', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'assistant_health');

-- ---------- who may use it ----------
create or replace function public._assistant_ok() returns boolean
language plpgsql stable security definer set search_path = public as $$
declare r text := coalesce(public.rule_txt('assistant_roles'), '');
begin
  if not public.is_active() then return false; end if;
  if not public.rule_on('assistant_on') then return false; end if;
  if public.is_owner() or public.has_grant('head_management') or public.has_grant('assistant_use') then return true; end if;
  if btrim(r) = '*' then return true; end if;
  return exists (select 1 from public.user_roles ur where ur.user_id = auth.uid()
                  and ur.role_code = any (select btrim(x) from unnest(string_to_array(r, ',')) x where btrim(x) <> ''));
end $$;

create or replace function public._assistant_health_ok() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('head_management') or public.has_grant('assistant_health'));
$$;

-- does the caller hold a grant at ANY place (location-scoped grants included)
create or replace function public._assistant_any_grant(p_code text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.has_grant(p_code) or exists (select 1 from public.locations l where public.has_grant(p_code, l.id));
$$;

-- ---------- notes (owner-approved rules / procedures / facts) ----------
create table if not exists public.assistant_notes (
  id bigserial primary key,
  kind text not null check (kind in ('rule', 'procedure', 'fact')),
  title text not null check (length(btrim(title)) between 2 and 120),
  body_bn text, body_en text,
  status text not null default 'approved' check (status in ('approved', 'retired')),
  client_id uuid unique,
  created_by uuid, at timestamptz not null default now(),
  updated_by uuid, updated_at timestamptz,
  retired_reason text,
  check (coalesce(length(body_bn), 0) + coalesce(length(body_en), 0) between 2 and 4000)
);
alter table public.assistant_notes enable row level security;
revoke all on public.assistant_notes from public, anon, authenticated;
grant select on public.assistant_notes to authenticated;
drop policy if exists assistant_notes_read on public.assistant_notes;
create policy assistant_notes_read on public.assistant_notes for select to authenticated using (public._assistant_ok() and (status = 'approved' or public.is_owner()));
drop trigger if exists assistant_notes_nodel on public.assistant_notes;
create trigger assistant_notes_nodel before delete on public.assistant_notes for each row execute function public.no_hard_delete();
drop trigger if exists audit_assistant_notes on public.assistant_notes;
create trigger audit_assistant_notes after insert or update on public.assistant_notes for each row execute function public.log_change('id');

-- text that looks like a secret is never stored (passwords, PINs, keys, tokens)
create or replace function public._assistant_secretish(p text) returns boolean
language sql immutable set search_path = public as $$
  select p is not null and (
       p ~* '(password|passwd|পাসওয়ার্ড|পাসওয়ার্ড|api[ _-]?key|secret|token|service_role|otp)'
    or p ~* '(pin|পিন)\s*(code|কোড|no|number|নম্বর)?\s*[:=]?\s*[0-9০-৯]{4,8}'
    or p ~ '(sk-[A-Za-z0-9_-]{16,}|eyJ[A-Za-z0-9_-]{20,}|[A-Za-z0-9_+/=-]{40,})');
$$;

create or replace function public.assistant_note_save(p_id bigint, p_client uuid, p_kind text, p_title text, p_body_bn text, p_body_en text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.assistant_notes; t text := btrim(coalesce(p_title, '')); bb text := nullif(btrim(coalesce(p_body_bn, '')), ''); be text := nullif(btrim(coalesce(p_body_en, '')), '');
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_kind is null or p_kind not in ('rule', 'procedure', 'fact') then raise exception 'bad_kind'; end if;
  if length(t) < 2 or length(t) > 120 then raise exception 'title_required'; end if;
  if bb is null and be is null then raise exception 'body_required'; end if;
  if coalesce(length(bb), 0) + coalesce(length(be), 0) > 4000 then raise exception 'too_long'; end if;
  if public._assistant_secretish(t) or public._assistant_secretish(bb) or public._assistant_secretish(be) then raise exception 'looks_like_secret'; end if;
  if p_id is null then
    if p_client is null then raise exception 'client_required'; end if;
    perform public._client_lock(p_client);
    select * into r from public.assistant_notes where client_id = p_client;
    if found then return jsonb_build_object('id', r.id, 'dup', true); end if;
    insert into public.assistant_notes (kind, title, body_bn, body_en, client_id, created_by) values (p_kind, t, bb, be, p_client, auth.uid()) returning * into r;
    return jsonb_build_object('id', r.id);
  end if;
  select * into r from public.assistant_notes where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if r.status <> 'approved' then raise exception 'retired'; end if;
  update public.assistant_notes set kind = p_kind, title = t, body_bn = bb, body_en = be, updated_by = auth.uid(), updated_at = now() where id = p_id;
  return jsonb_build_object('id', p_id);
end $$;

create or replace function public.assistant_note_retire(p_id bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.assistant_notes;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  select * into r from public.assistant_notes where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if r.status = 'retired' then return jsonb_build_object('id', p_id, 'status', 'retired', 'dup', true); end if;
  update public.assistant_notes set status = 'retired', retired_reason = left(btrim(p_reason), 300), updated_by = auth.uid(), updated_at = now() where id = p_id;
  return jsonb_build_object('id', p_id, 'status', 'retired');
end $$;

-- ---------- usage log (no business content) ----------
create table if not exists public.assistant_usage (
  id bigserial primary key,
  user_id uuid not null,
  at timestamptz not null default now(),
  provider text not null check (provider in ('local', 'llm_proxy')),
  intent text not null check (intent ~ '^[a-z0-9_]{1,40}$'),
  tool_keys text[] not null default '{}',
  ms int not null default 0 check (ms between 0 and 600000),
  tokens_in int not null default 0 check (tokens_in between 0 and 10000000),
  tokens_out int not null default 0 check (tokens_out between 0 and 10000000),
  ok boolean not null default true
);
create index if not exists assistant_usage_user_at on public.assistant_usage (user_id, at);
create index if not exists assistant_usage_at on public.assistant_usage (at);
alter table public.assistant_usage enable row level security;
revoke all on public.assistant_usage from public, anon, authenticated;
grant select on public.assistant_usage to authenticated;
drop policy if exists assistant_usage_read on public.assistant_usage;
create policy assistant_usage_read on public.assistant_usage for select to authenticated using (public.is_owner());
create or replace function public._assistant_usage_ro() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'assistant_usage is append-only'; end $$;
drop trigger if exists assistant_usage_ro on public.assistant_usage;
create trigger assistant_usage_ro before update or delete on public.assistant_usage for each row execute function public._assistant_usage_ro();
drop trigger if exists assistant_usage_ro_t on public.assistant_usage;
create trigger assistant_usage_ro_t before truncate on public.assistant_usage for each statement execute function public._assistant_usage_ro();

create or replace function public.assistant_log(p_provider text, p_intent text, p_tools text[], p_ms int, p_tokens_in int default 0, p_tokens_out int default 0, p_ok boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare n int; lim int := greatest(coalesce(public.rule_num('assistant_rate_per_hour'), 120), 1)::int; k text;
begin
  if not public._assistant_ok() then raise exception 'not allowed'; end if;
  if p_provider is null or p_provider not in ('local', 'llm_proxy') then raise exception 'bad_provider'; end if;
  if p_intent is null or p_intent !~ '^[a-z0-9_]{1,40}$' then raise exception 'bad_intent'; end if;
  if cardinality(coalesce(p_tools, '{}')) > 12 then raise exception 'too_many_tools'; end if;
  foreach k in array coalesce(p_tools, '{}') loop
    if k is null or k !~ '^[a-z0-9_]{1,40}$' then raise exception 'bad_tool_key'; end if;
  end loop;
  if p_ms is null or p_ms < 0 or p_ms > 600000 or coalesce(p_tokens_in, 0) not between 0 and 10000000 or coalesce(p_tokens_out, 0) not between 0 and 10000000 then raise exception 'bad_number'; end if;
  select count(*) into n from public.assistant_usage where user_id = auth.uid() and at > now() - interval '1 hour';
  if n >= lim then return jsonb_build_object('ok', false, 'limited', true, 'count_hour', n, 'limit', lim); end if;
  insert into public.assistant_usage (user_id, provider, intent, tool_keys, ms, tokens_in, tokens_out, ok)
    values (auth.uid(), p_provider, p_intent, coalesce(p_tools, '{}'), p_ms, coalesce(p_tokens_in, 0), coalesce(p_tokens_out, 0), coalesce(p_ok, true));
  return jsonb_build_object('ok', true, 'limited', false, 'count_hour', n + 1, 'limit', lim);
end $$;

-- owner: counts and tokens for one month (token cost is computed in the browser from documented prices, never stored as money)
create or replace function public.assistant_usage_summary(p_month date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m date := date_trunc('month', coalesce(p_month, (now() at time zone 'Asia/Dhaka')::date))::date; res jsonb; bud numeric := public.rule_num('assistant_monthly_token_budget');
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select jsonb_build_object('month', m, 'questions', count(*), 'ok', count(*) filter (where ok), 'failed', count(*) filter (where not ok),
      'users', count(distinct user_id), 'avg_ms', coalesce(round(avg(ms)), 0),
      'local', count(*) filter (where provider = 'local'), 'llm_proxy', count(*) filter (where provider = 'llm_proxy'),
      'tokens_in', coalesce(sum(tokens_in), 0), 'tokens_out', coalesce(sum(tokens_out), 0),
      'budget', bud, 'budget_used_pct', case when bud > 0 then round(100.0 * coalesce(sum(tokens_in + tokens_out), 0) / bud, 1) end,
      'top_intents', coalesce((select jsonb_agg(jsonb_build_object('intent', z.intent, 'n', z.n) order by z.n desc) from (
          select intent, count(*) n from public.assistant_usage u2 where (u2.at at time zone 'Asia/Dhaka')::date >= m and (u2.at at time zone 'Asia/Dhaka')::date < (m + interval '1 month')::date
          group by intent order by count(*) desc limit 8) z), '[]'::jsonb))
    into res from public.assistant_usage u where (u.at at time zone 'Asia/Dhaka')::date >= m and (u.at at time zone 'Asia/Dhaka')::date < (m + interval '1 month')::date;
  return res;
end $$;

-- the edge function (if the owner ever deploys it) asks this with the caller's JWT before spending tokens
create or replace function public.assistant_proxy_check() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare bud numeric := public.rule_num('assistant_monthly_token_budget'); used numeric; m date := date_trunc('month', (now() at time zone 'Asia/Dhaka')::date)::date;
begin
  if not public._assistant_ok() then return jsonb_build_object('ok', false, 'reason', 'not_allowed'); end if;
  if coalesce(public.rule_txt('assistant_provider'), 'local') <> 'llm_proxy' then return jsonb_build_object('ok', false, 'reason', 'provider_local'); end if;
  if bud is null or bud <= 0 then return jsonb_build_object('ok', false, 'reason', 'no_budget'); end if;
  select coalesce(sum(tokens_in + tokens_out), 0) into used from public.assistant_usage where provider = 'llm_proxy' and (at at time zone 'Asia/Dhaka')::date >= m;
  if used >= bud then return jsonb_build_object('ok', false, 'reason', 'budget_spent', 'used', used, 'budget', bud); end if;
  return jsonb_build_object('ok', true, 'used', used, 'budget', bud, 'left', bud - used);
end $$;

-- ---------- capability map: what this person may ask (the server still decides on every call) ----------
create or replace function public.assistant_me() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare g text; grp jsonb := '{}'::jsonb; opt jsonb := '[]'::jsonb; own boolean := public.is_owner();
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public._assistant_ok() then
    return jsonb_build_object('allowed', false, 'reason', case when not public.rule_on('assistant_on') then 'assistant_off' else 'no_right' end);
  end if;
  foreach g in array array['sales','pos','cash','customers','stock','purchase','expense','staff','control','profit','orders','marketing','quality'] loop
    grp := grp || jsonb_build_object(g, public.rpt_access(g));
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('name', p.proname,
           'args', coalesce((select jsonb_agg(a.n order by a.o) from unnest(coalesce(p.proargnames, '{}'::text[])) with ordinality a(n, o)
                              where p.proargmodes is null or p.proargmodes[a.o] in ('i', 'b')), '[]'::jsonb))
           order by p.proname), '[]'::jsonb) into opt
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = any (array['acct_balance_sheet','acct_income_statement','acct_trial_balance','acct_overview','balance_sheet','income_statement','trial_balance','partner_overview','tier_usage_report','backup_status'])
     and has_function_privilege('authenticated', p.oid, 'execute');
  return jsonb_build_object('allowed', true, 'is_owner', own,
    'health', public._assistant_health_ok(), 'cost', public.rpt_cost_ok(), 'biz', public.biz_ok(),
    'salary', own or public._assistant_any_grant('salary_view'), 'daybook', own or public._assistant_any_grant('view_daybook'),
    'purchase', public._pur_ok(null) or exists (select 1 from public.locations l where public._pur_ok(l.id)),
    'pos', public.can_do('POS', 'view') or public.can_do('POS', 'enter'),
    'reports', grp, 'optional', opt,
    'provider', coalesce(public.rule_txt('assistant_provider'), 'local'), 'cache_seconds', coalesce(public.rule_num('assistant_cache_seconds'), 60),
    'actions_on', false, 'voice_on', public.rule_on('assistant_voice_on'), 'rate_per_hour', coalesce(public.rule_num('assistant_rate_per_hour'), 120));
end $$;

-- ---------- the configuration check ----------
create or replace function public._ah(p_code text, p_sev text, p_bn text, p_en text, p_detail text, p_route text, p_ev jsonb default '{}'::jsonb) returns jsonb
language sql immutable set search_path = public as $$
  select jsonb_build_array(jsonb_build_object('code', p_code, 'severity', p_sev, 'title_bn', p_bn, 'title_en', p_en, 'detail', p_detail, 'route', p_route, 'evidence', coalesce(p_ev, '{}'::jsonb)));
$$;

create or replace function public.assistant_health() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  f jsonb := '[]'::jsonb; locs int[]; n bigint; n2 bigint; ev jsonb; r record; d date; today date := (now() at time zone 'Asia/Dhaka')::date;
  age int := coalesce(public.rule_num('assistant_closed_age_days'), 45)::int; sid bigint; miss text[]; k text; v jsonb; maxh numeric; last timestamptz; fin boolean;
  keys constant text[] := array['drawer_float', 'cash_tol', 'discount_limit', 'expense_max'];
begin
  if not public._assistant_health_ok() then raise exception 'not allowed'; end if;
  select coalesce(array_agg(l.id order by l.id), '{}') into locs from public.locations l
   where coalesce(l.status, 'live') in ('live', 'setting_up') and (public.is_owner() or public.has_grant('head_management') or public.can_loc(l.id));

  -- items
  select count(*), coalesce(jsonb_agg(code order by code) filter (where rn <= 5), '[]') into n, ev from (
    select i.code, row_number() over (order by i.code) rn from public.items i
     where i.is_active and coalesce(i.sellable, true) and not coalesce(i.hidden, false) and i.retired_at is null and (i.sell_price is null or i.sell_price <= 0)) z;
  if n > 0 then f := f || public._ah('items_no_price', 'warn', 'দাম ছাড়া বিক্রয়যোগ্য আইটেম', 'Sellable items without a price', n || ' active sellable items have no selling price', 'bulkitems', jsonb_build_object('count', n, 'sample', ev)); end if;
  select count(*) into n from public.items i where i.is_active and i.retired_at is null and i.unit is null and i.base_unit is null;
  if n > 0 then f := f || public._ah('items_no_unit', 'warn', 'একক ছাড়া আইটেম', 'Items without a unit', n || ' active items have no unit', 'bulkitems', jsonb_build_object('count', n)); end if;
  select count(*) into n from public.items i where i.is_active and i.retired_at is null and i.tracked and i.base_unit is null;
  if n > 0 then f := f || public._ah('items_tracked_no_base', 'warn', 'স্টক-হিসাবি আইটেমের মূল একক নেই', 'Stock-tracked items without a base unit', n || ' tracked items have no base unit', 'bulkitems', jsonb_build_object('count', n)); end if;
  select count(*) filter (where i.tracked), count(*) into n, n2 from public.items i where i.is_active and i.retired_at is null;
  if n2 > 0 and n = 0 then f := f || public._ah('items_none_tracked', 'info', 'কোনো আইটেমে স্টক-হিসাব চালু নেই', 'No item has stock tracking on', 'Stock pages and stock reports stay empty until items are tracked', 'bulkitems', jsonb_build_object('active_items', n2)); end if;

  -- places: settings sheet and key limits (showrooms)
  for r in select l.id, l.code, l.kind from public.locations l where l.id = any (locs) order by l.id loop
    sid := public._sheet_in_force(r.id, today);
    if not exists (select 1 from public.settings_sheets s where s.location_id = r.id and s.status = 'approved') then
      f := f || public._ah('loc_no_sheet', 'warn', 'জায়গার সেটিংস-শিট অনুমোদিত নয়', 'Place has no approved settings sheet', r.code || ': no approved Location Settings Sheet (0-1)', 'locset', jsonb_build_object('location_id', r.id, 'code', r.code));
    end if;
    if coalesce(r.kind, 'showroom') = 'showroom' then
      miss := '{}';
      foreach k in array keys loop
        if sid is null then select value into v from public.location_settings where location_id = r.id and key = k; else select value into v from public.settings_values where sheet_id = sid and key = k; end if;
        if v is null or v = 'null'::jsonb or (jsonb_typeof(v) = 'string' and btrim(v #>> '{}') = '') then miss := miss || k; end if;
        v := null;
      end loop;
      if cardinality(miss) > 0 then
        f := f || public._ah('loc_limit_blank', 'warn', 'জায়গার সীমা ফাঁকা (তথ্য দরকার)', 'Blank limits at a place (data needed)', r.code || ': ' || array_to_string(miss, ', '), 'locset', jsonb_build_object('location_id', r.id, 'code', r.code, 'missing', to_jsonb(miss)));
      end if;
    end if;
  end loop;

  -- rollout
  select count(*) into n from public.form_rollout fr where fr.mode = 'paper' and fr.location_id = any (locs)
     and not exists (select 1 from public.entries e where e.form_code = fr.form_code and e.location_id = fr.location_id);
  if n > 0 then f := f || public._ah('paper_never_app', 'info', 'কাগজে চলা ফর্ম, অ্যাপে কখনো লেখা হয়নি', 'Forms on paper never tried in the app', n || ' form x place cells are on Paper and have no app entry yet', 'rollout', jsonb_build_object('count', n)); end if;
  if public.rule_on('parallel_compare_on') then
    select count(*), coalesce(jsonb_agg(fr.form_code || '@' || fr.location_id) filter (where true), '[]') into n, ev from public.form_rollout fr
     where fr.mode = 'parallel' and fr.location_id = any (locs) and not exists (select 1 from public.comparison_pairs p where p.form_code = fr.form_code and p.is_active);
    if n > 0 then f := f || public._ah('parallel_no_pair', 'warn', 'পাশাপাশি চলছে কিন্তু তুলনার জোড়া নেই', 'Parallel without a comparison pair', n || ' parallel cells cannot record a comparison day', 'parallel', jsonb_build_object('count', n, 'cells', ev)); end if;
  end if;
  select count(*) into n from public.form_rollout fr where fr.mode = 'app' and fr.location_id = any (locs) and fr.changed_at < now() - interval '14 days'
     and not exists (select 1 from public.entries e where e.form_code = fr.form_code and e.location_id = fr.location_id and e.created_at > now() - interval '14 days');
  if n > 0 then f := f || public._ah('app_unused', 'info', 'অ্যাপে বদলানো ফর্ম ১৪ দিন ব্যবহার হয়নি', 'Forms moved to the app but unused for 14 days', n || ' form x place cells', 'rollout', jsonb_build_object('count', n)); end if;

  -- rule conflicts (each justified in docs/ASSISTANT_AUDIT.md section 6)
  if coalesce(public.rule_txt('grn_receipt_source'), 'purchase') = 'grn' then
    if public.rule_on('forms_post_to_ledger') then
      f := f || public._ah('grn_double_count', 'warn', 'GRN ও ক্রয় পেজ দুটোই স্টক বাড়াতে পারে', 'GRN and the purchase page may both add stock', 'grn_receipt_source = grn and forms_post_to_ledger ON: the purchase page still posts purchase_in; check receipt duplicates', 'switchboard', jsonb_build_object('grn_receipt_source', 'grn', 'forms_post_to_ledger', true));
    else
      f := f || public._ah('grn_source_no_effect', 'info', 'GRN-কে উৎস করা হয়েছে, কিন্তু ফর্ম লেজারে যায় না', 'GRN chosen as the source but forms do not post', 'grn_receipt_source = grn while forms_post_to_ledger is OFF: the choice has no effect', 'switchboard', jsonb_build_object('grn_receipt_source', 'grn', 'forms_post_to_ledger', false));
    end if;
  end if;
  if public.rule_on('vat_on') and public.rule_num('vat_rate') is null then
    f := f || public._ah('vat_no_rate', 'bad', 'ভ্যাট চালু কিন্তু হার নেই', 'VAT is on but the rate is blank', 'vat_on ON, vat_rate blank', 'switchboard', '{}'::jsonb);
  end if;
  if public.rule_on('production_requires_recipe') and not exists (select 1 from public.recipes rc where rc.active) then
    f := f || public._ah('production_no_recipe', 'bad', 'রেসিপি বাধ্যতামূলক কিন্তু কোনো রেসিপি নেই', 'Recipe required but no active recipe', 'production_requires_recipe ON: every production is refused', 'recipes', '{}'::jsonb);
  end if;
  if public.rule_on('recipe_waste_required') then
    select count(*) into n from public.recipe_lines rl join public.recipes rc on rc.id = rl.recipe_id where rc.active and rl.active and rl.waste_pct is null;
    if n > 0 then f := f || public._ah('recipe_waste_blank', 'warn', 'রেসিপির লাইনে অপচয় % নেই', 'Recipe lines without waste %', n || ' active lines: production with them is refused', 'recipes', jsonb_build_object('count', n)); end if;
  end if;
  select count(*) into n from public.recipes rc where rc.active and (rc.yield_qty is null or rc.yield_qty <= 0);
  if n > 0 then f := f || public._ah('recipe_no_yield', 'warn', 'রেসিপির উৎপাদন-পরিমাণ (yield) নেই', 'Recipes without yield', n || ' active recipes', 'recipes', jsonb_build_object('count', n)); end if;
  if public.rule_on('blind_count_on') and not exists (select 1 from public.blind_count_cfg b where b.enabled) then
    f := f || public._ah('blind_no_form', 'info', 'ব্লাইন্ড কাউন্ট চালু, কিন্তু কোনো ফর্মে নয়', 'Blind count is on for no form', 'blind_count_on ON but no form x place is switched on', 'switchboard', '{}'::jsonb);
  end if;
  if public.rule_on('pin_signature_on') and not exists (select 1 from public.pin_sig_cfg p where p.enabled) then
    f := f || public._ah('pin_no_form', 'info', 'পিন-সই চালু, কিন্তু কোনো ফর্মে নয়', 'PIN signature is on for no form', 'pin_signature_on ON but no form is switched on', 'switchboard', '{}'::jsonb);
  end if;
  if coalesce(public.rule_txt('stock_negative_mode'), 'warn') = 'allow' and not public.rule_on('block_expired_sale') then
    f := f || public._ah('stock_guards_off', 'info', 'বিক্রিতে স্টকের কোনো বাধা নেই (দুর্বল নিয়ন্ত্রণ)', 'No stock guard at the till (weak control)', 'stock_negative_mode = allow and block_expired_sale OFF', 'switchboard', '{}'::jsonb);
  end if;

  -- books and day book
  d := public.rpt_date(public.rule_txt('period_closed_until'));
  if d is null then f := f || public._ah('books_never_closed', 'warn', 'হিসাব কখনো বন্ধ (লক) করা হয়নি', 'Books were never closed', 'period_closed_until is blank: any old date can still be changed', 'rules', '{}'::jsonb);
  elsif d < today - age then f := f || public._ah('books_closed_old', 'info', 'হিসাব বন্ধের তারিখ পুরনো', 'Books-closed date is old', 'closed until ' || d || ' (' || (today - d) || ' days ago)', 'rules', jsonb_build_object('closed_until', d, 'days', today - d)); end if;
  if public.rule_on('daybook_enabled') then
    if public._db_start() is null then f := f || public._ah('daybook_no_start', 'warn', 'দৈনিক খাতার শুরুর তারিখ নেই', 'Day book has no start date', 'running cash / bank / mobile totals are unknown', 'daybook', '{}'::jsonb);
    elsif public.rule_num('daybook_open_cash') is null or public.rule_num('daybook_open_bank') is null or public.rule_num('daybook_open_mobile') is null then
      f := f || public._ah('daybook_no_opening', 'info', 'শুরুর ক্যাশ/ব্যাংক/মোবাইল ব্যালান্স ফাঁকা', 'Opening cash / bank / mobile balance blank', 'closing balances cannot be shown (data needed)', 'daybook', '{}'::jsonb);
    end if;
  end if;
  if public.rule_txt('fiscal_year_start_month') is null or public.rule_txt('week_start') is null then
    f := f || public._ah('calendar_defaults', 'info', 'অর্থবছর / সপ্তাহের শুরু ঠিক করা হয়নি', 'Fiscal year / week start not set', 'reports use the calendar year and Saturday', 'switchboard', '{}'::jsonb);
  end if;

  -- people
  select count(*) into n from public.profiles p where p.status = 'pending';
  if n > 0 then f := f || public._ah('staff_pending', 'warn', 'নতুন স্টাফ অনুমোদনের অপেক্ষায়', 'Staff accounts waiting for approval', n || ' pending', 'staff', jsonb_build_object('count', n)); end if;
  select count(*) into n from public.profiles p where p.status = 'active'
     and not exists (select 1 from public.user_roles ur where ur.user_id = p.id and ur.role_code in ('owner', 'management'))
     and not exists (select 1 from public.user_locations ul where ul.user_id = p.id);
  if n > 0 then f := f || public._ah('staff_no_location', 'warn', 'সক্রিয় স্টাফের কোনো জায়গা নেই', 'Active staff without a place', n || ' people cannot work anywhere', 'staff', jsonb_build_object('count', n)); end if;
  select count(*) into n from public.profiles p where p.status = 'active' and not exists (select 1 from public.user_roles ur where ur.user_id = p.id);
  if n > 0 then f := f || public._ah('staff_no_role', 'warn', 'সক্রিয় স্টাফের ভূমিকা নেই', 'Active staff without a role', n || ' people', 'staff', jsonb_build_object('count', n)); end if;
  foreach k in array array['release_decide', 'wastage_approve', 'change_approve'] loop
    if not exists (select 1 from public.user_grants g join public.profiles p on p.id = g.user_id and p.status = 'active' where g.grant_code = k and (g.valid_until is null or g.valid_until > now())
                     and not exists (select 1 from public.user_roles ur where ur.user_id = g.user_id and ur.role_code = 'owner'))
       and not exists (select 1 from public.rule_grants rg where rg.grant_code = k and rg.allowed and rg.role_code <> 'owner') then
      f := f || public._ah('only_owner_' || k, 'info', 'এই অনুমোদন শুধু মালিক দিতে পারেন', 'Only the owner can decide this', k || ': nobody else holds it (owner absent = waiting)', 'delegation', jsonb_build_object('grant', k));
    end if;
  end loop;
  if not exists (select 1 from public.user_grants g join public.profiles p on p.id = g.user_id and p.status = 'active' where (g.grant_code like 'report\_%' or g.grant_code = 'view_reports') and (g.valid_until is null or g.valid_until > now())
                   and not exists (select 1 from public.user_roles ur where ur.user_id = g.user_id and ur.role_code = 'owner'))
     and not exists (select 1 from public.rule_grants rg where (rg.grant_code like 'report\_%' or rg.grant_code = 'view_reports') and rg.allowed and rg.role_code <> 'owner') then
    f := f || public._ah('reports_owner_only', 'info', 'রিপোর্ট শুধু মালিক দেখেন', 'Only the owner sees reports', 'no report grant is given to anyone else', 'delegation', '{}'::jsonb);
  end if;

  -- parties
  select count(*) into n from public.suppliers s where s.active and s.credit_days is null;
  if n > 0 then f := f || public._ah('supplier_no_credit_days', 'info', 'সরবরাহকারীর বাকির দিন নেই', 'Suppliers without credit days', n || ' suppliers: overdue cannot be worked out for them', 'settings2/suppliers', jsonb_build_object('count', n)); end if;
  select count(*), coalesce(round(sum(c.balance - c.credit_limit), 2), 0) into n, n2 from public.customer_dues() c where c.credit_limit is not null and c.balance > c.credit_limit;
  if n > 0 then f := f || public._ah('customers_over_limit', 'warn', 'বাকির সীমা পেরোনো গ্রাহক', 'Customers over their credit limit', n || ' customers, ' || n2 || ' over in total', 'dues', jsonb_build_object('count', n, 'over_total', n2)); end if;

  -- optional modules (only when installed)
  if to_regclass('public.backup_runs') is not null then
    maxh := coalesce(public.rule_num('backup_max_age_hours'), 36);
    execute 'select max(finished_at) from public.backup_runs where status = ''ok''' into last;
    if last is null then f := f || public._ah('backup_none', 'warn', 'কোনো সফল ব্যাকআপ নেই', 'No successful backup recorded', 'backup_runs has no ok run', 'backup', '{}'::jsonb);
    elsif last < now() - make_interval(hours => maxh::int) then f := f || public._ah('backup_stale', 'bad', 'ব্যাকআপ পুরনো', 'Backup is stale', 'last ok backup ' || round(extract(epoch from now() - last) / 3600) || ' hours ago (limit ' || maxh || ')', 'backup', jsonb_build_object('hours', round(extract(epoch from now() - last) / 3600), 'limit', maxh)); end if;
  end if;
  if exists (select 1 from public.rules where key = 'accounting_on') and public.rule_on('accounting_on') and public.rule_txt('accounting_start_date') is null then
    f := f || public._ah('accounting_no_start', 'bad', 'হিসাব (অ্যাকাউন্টিং) চালু কিন্তু শুরুর তারিখ / প্রারম্ভিক ব্যালান্স নেই', 'Accounting on without a start date / opening balances', 'accounting_on ON, accounting_start_date blank', 'accounts', '{}'::jsonb);
  elsif exists (select 1 from public.rules where key = 'accounting_on') and public.rule_on('accounting_on') and to_regclass('public.journal_entries') is not null then
    execute 'select exists (select 1 from public.journal_entries o where o.source_type = ''opening'' and o.reverses_id is null and not exists (select 1 from public.journal_entries r where r.reverses_id = o.id))' into fin;
    if not fin then f := f || public._ah('accounting_no_opening', 'warn', 'হিসাব চালু কিন্তু প্রারম্ভিক ব্যালান্স (opening journal) নেই', 'Accounting on without an opening journal', 'no active opening journal (phase40 acct_opening)', 'accounts', '{}'::jsonb); end if;
  end if;
  return f;
end $$;

-- ---------- privileges ----------
revoke all on function public._assistant_ok(), public._assistant_health_ok(), public._assistant_any_grant(text), public._assistant_secretish(text),
  public._ah(text, text, text, text, text, text, jsonb), public._assistant_usage_ro() from public, anon, authenticated;
grant execute on function public._assistant_ok() to authenticated;   -- used inside the notes read policy
revoke all on function public.assistant_me(), public.assistant_health(), public.assistant_log(text, text, text[], int, int, int, boolean), public.assistant_usage_summary(date),
  public.assistant_proxy_check(), public.assistant_note_save(bigint, uuid, text, text, text, text), public.assistant_note_retire(bigint, text) from public, anon;
grant execute on function public.assistant_me(), public.assistant_health(), public.assistant_log(text, text, text[], int, int, int, boolean), public.assistant_usage_summary(date),
  public.assistant_proxy_check(), public.assistant_note_save(bigint, uuid, text, text, text, text), public.assistant_note_retire(bigint, text) to authenticated;
