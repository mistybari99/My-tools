-- Phase 89 (bos89) - PERIOD INTEGRITY (U-02). Paste after phase87 (phase88 is a separate package and is not needed). Paste-twice safe. Earlier phase files are not edited.
-- Package W1-B. Owner standing rules applied: every policy is a SETTING with a safe default that keeps TODAY's behaviour, every change is an audit_log line,
-- the books of the past are never changed, an exception needs a reason and shows in the Exceptions list (money_exceptions, phase87).
--
-- WHAT THIS FILE ADDS (all of it works on its own; the five shared functions below are NOT touched here, their hook text is in docs/integration/W1-B.md and docs/integration/W1-B_hooks.sql)
--   * a pure date test for the period lock: _w1b_lock_date() / _w1b_is_locked(date) never look at who is asking.
--   * lock policy as settings: period_lock_mode (manual [default, today] | auto | off), auto_lock_day, owner_closed_period_mode (off [default, today] | log | reason).
--   * period_override_start / period_override_end: a short window (reason, from, to, minutes) in which ONE person may edit closed dates or back-date; every use is one audit_log line
--     and one row of the Exceptions list. Reuses the phase87 one-off grants (rule period_lock / override) for other people.
--   * back-date window per document type: backdate_max_days_purchase / cash_move / expense / production (blank = off). Over the limit needs a window, a one-off grant or a role grant.
--   * late offline sale policy: late_sale_policy redate [default, today] | redate_flag (re-dated and written to the Exceptions list) | park (held for the owner: accept with its own time, re-date, reject).
--   * guards on rules (only for calls that come through the API, like the phase80 guard): accounting_start_date cannot move after an opening exists (switch),
--     accounting_on OFF -> ON needs a reason (switch), the lock date cannot move back without a reason (lock_backward_policy).
--   * period_lock_state(), period_lock_set(date, reason), period_lock_policy_set(key, value, note), period_override_log(), period_lateness_report(days), accounting_on_preview(), accounting_on_set(on, reason),
--     late_sales_held_list(status), late_sale_release(id, action, reason).
-- NOTHING CHANGES FOR AN EXISTING INSTALL until the owner changes a setting AND the hooks of the integrator are installed: every default equals today's behaviour.
-- !! Re-pasting phase 6, 8, 10, 14, 19, 23, 43, 50, 73, 74 or 87 after the hooks removes them: the integrator's re-patch phase puts them back.

do $g$ begin
  if to_regprocedure('public._p87_present()') is null then raise exception 'phase89 needs phase87 (and the phases before it) first'; end if;
  if to_regprocedure('public.lock_check(date)') is null or to_regprocedure('public._acct_locked(date)') is null or to_regprocedure('public._m_lock_exc(date)') is null
     or to_regprocedure('public._m_grant_take(text,text,uuid,bigint,numeric,date,text)') is null or to_regclass('public.money_exceptions') is null
     or to_regprocedure('public.rule_ok(text,integer,numeric,date,text)') is null or to_regprocedure('public.no_hard_delete()') is null then
    raise exception 'phase89 needs the shared functions of phases 6, 7 and 87';
  end if;
end $g$;

create or replace function public._p89_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- generic: patch a live function by exact text, with a marker of your own (the phase87 helper _m_patch only knows the marker bos87, and lock_check already carries it) ----------
-- p_pairs = [old1, new1, old2, new2 ...]. Every old text must exist (otherwise nothing is changed and the paste stops). The marker must appear in the new text. Already patched = no-op.
create or replace function public._w1b_patch(p_fn regprocedure, p_marker text, p_pairs text[]) returns boolean language plpgsql set search_path = public as $$
declare def text := pg_get_functiondef(p_fn); i int;
begin
  if p_marker is null or length(p_marker) < 4 then raise exception 'phase89 patch needs a marker'; end if;
  if position(p_marker in def) > 0 then return false; end if;
  for i in 1 .. array_length(p_pairs, 1) by 2 loop
    if position(p_pairs[i] in def) = 0 then raise exception 'phase89 patch site not found in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    def := replace(def, p_pairs[i], p_pairs[i + 1]);
  end loop;
  if position(p_marker in def) = 0 then raise exception 'phase89 patch of % carries no marker', p_fn::text; end if;
  execute def;
  return true;
end $$;

-- ---------- tables ----------
create table if not exists public.period_overrides (          -- a short window in which one person may work in a closed period / back-date (reason required)
  id bigserial primary key,
  scope text not null default 'lock' check (scope in ('lock', 'backdate', 'both')),
  user_id uuid not null,
  from_date date not null, to_date date not null,
  doc_type text check (doc_type is null or doc_type in ('purchase', 'cash_move', 'expense', 'production')),
  reason text not null check (length(btrim(reason)) >= 3 and length(reason) <= 300),
  started_by uuid not null, started_at timestamptz not null default now(),
  expires_at timestamptz not null,
  ended_at timestamptz, ended_by uuid, end_note text,
  uses int not null default 0, last_used_at timestamptz,
  check (from_date <= to_date)
);
create index if not exists period_overrides_user on public.period_overrides (user_id, expires_at);

create table if not exists public.late_sales_held (            -- offline sales older than pos_offline_hours when late_sale_policy = park
  id bigserial primary key,
  client_id uuid,
  user_id uuid not null,
  location_id int not null,
  sold_at timestamptz not null,
  received_at timestamptz not null default now(),
  hours_late numeric,
  payload jsonb not null,
  status text not null default 'held' check (status in ('held', 'accepted', 'redated', 'rejected')),
  decided_by uuid, decided_at timestamptz, decide_reason text,
  sale_id uuid, result jsonb,
  exception_id bigint
);
create unique index if not exists late_sales_held_client on public.late_sales_held (client_id, user_id) where client_id is not null;
create index if not exists late_sales_held_status on public.late_sales_held (status, id);

do $t$ declare t text; begin
  foreach t in array array['period_overrides', 'late_sales_held'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_nodel', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_nodel', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('drop trigger if exists %I on public.%I', 'audit_' || t, t);
    execute format('create trigger %I after insert or update on public.%I for each row execute function public.log_change(%L)', 'audit_' || t, t, 'id');
  end loop;
  drop policy if exists period_overrides_read on public.period_overrides;
  create policy period_overrides_read on public.period_overrides for select to authenticated using (public.is_owner());
  grant select on public.period_overrides to authenticated;
  drop policy if exists late_sales_held_read on public.late_sales_held;
  create policy late_sales_held_read on public.late_sales_held for select to authenticated using (public.can_grant('late_sale_release'));
  grant select on public.late_sales_held to authenticated;
end $t$;

-- the Exceptions list (phase87 money_exceptions) learns the new kinds. The list is MERGED with what is allowed now, so another package that added kinds is not wiped out.
do $k$ declare def text; cur text[]; want text[] := array['late_sale_held', 'late_sale_redated', 'backdate_exception']; allk text[]; k text;
begin
  select pg_get_constraintdef(oid) into def from pg_constraint where conrelid = 'public.money_exceptions'::regclass and conname = 'money_exceptions_kind_check';
  if def is null then return; end if;
  select coalesce(array_agg(m[1]), '{}') into cur from regexp_matches(def, '''([a-z_0-9]+)''::text', 'g') m;          -- the form ARRAY['a'::text, 'b'::text]
  if cardinality(cur) = 0 then cur := coalesce(string_to_array(substring(def from '\{([^}]*)\}'), ','), '{}'); end if;   -- the form '{a,b}'::text[] (what this block itself writes)
  if cardinality(cur) = 0 then return; end if;                                                                           -- unknown shape: leave the constraint alone
  allk := cur;
  foreach k in array want loop if not k = any (allk) then allk := allk || k; end if; end loop;
  if cardinality(allk) = cardinality(cur) then return; end if;
  alter table public.money_exceptions drop constraint money_exceptions_kind_check;
  execute format('alter table public.money_exceptions add constraint money_exceptions_kind_check check (kind = any (%L::text[]))', allk);
end $k$;

-- ---------- settings (English labels only for now; Bangla later). Every default equals today's behaviour ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('period_lock_mode', 'books', 'choice', '"manual"', null, '["manual","auto","off"]', null, null,
  'Period lock: how the books are closed', 'Period lock: how the books are closed', 'Period lock: how the books are closed',
  'manual = the date typed in "Books closed until" (today). auto = the previous month locks by itself after the day set below, and the typed date still counts. off = no lock at all.',
  'manual = the date typed in "Books closed until" (today). auto = the previous month locks by itself after the day set below, and the typed date still counts. off = no lock at all.',
  'manual = the date typed in "Books closed until" (today). auto = the previous month locks by itself after the day set below, and the typed date still counts. off = no lock at all.', 200),
 ('auto_lock_day', 'books', 'number', null, 'day of month', null, 1, 28, 'Automatic lock: lock last month after this day', 'Automatic lock: lock last month after this day', 'Automatic lock: lock last month after this day',
  'Used only when the period lock is auto. Example 10: from the 11th of each month the whole previous month is closed. Blank = not set (auto then locks nothing by itself).',
  'Used only when the period lock is auto. Example 10: from the 11th of each month the whole previous month is closed. Blank = not set (auto then locks nothing by itself).',
  'Used only when the period lock is auto. Example 10: from the 11th of each month the whole previous month is closed. Blank = not set (auto then locks nothing by itself).', 201),
 ('owner_closed_period_mode', 'books', 'choice', '"off"', null, '["off","log","reason"]', null, null,
  'Owner in a closed period', 'Owner in a closed period', 'Owner in a closed period',
  'off = the owner changes closed dates silently (today). log = allowed, but every use is logged to the Exceptions list. reason = refused until the owner opens an override window with a written reason (recommended once the books are really closed).',
  'off = the owner changes closed dates silently (today). log = allowed, but every use is logged to the Exceptions list. reason = refused until the owner opens an override window with a written reason (recommended once the books are really closed).',
  'off = the owner changes closed dates silently (today). log = allowed, but every use is logged to the Exceptions list. reason = refused until the owner opens an override window with a written reason (recommended once the books are really closed).', 202),
 ('period_override_default_minutes', 'books', 'number', '60', 'minutes', null, 5, 1440, 'Override window: default length', 'Override window: default length', 'Override window: default length',
  'How long an override window stays open when no length is typed.', 'How long an override window stays open when no length is typed.', 'How long an override window stays open when no length is typed.', 203),
 ('lock_backward_policy', 'books', 'choice', '"allow"', null, '["allow","reason_after_year_close","reason_always"]', null, null,
  'Moving the lock date back', 'Moving the lock date back', 'Moving the lock date back',
  'allow = anytime (today). reason_after_year_close = moving the date back into a closed year needs a written reopen reason. reason_always = any move back needs a reason.',
  'allow = anytime (today). reason_after_year_close = moving the date back into a closed year needs a written reopen reason. reason_always = any move back needs a reason.',
  'allow = anytime (today). reason_after_year_close = moving the date back into a closed year needs a written reopen reason. reason_always = any move back needs a reason.', 204),
 ('backdate_max_days_purchase', 'books', 'number', null, 'days', null, 0, 3650, 'Back-date limit: purchase bill date', 'Back-date limit: purchase bill date', 'Back-date limit: purchase bill date',
  'How many days back a new purchase bill may be dated. Blank = no limit (today). Over the limit needs an override window, a one-off owner grant or a role with the back-date grant.',
  'How many days back a new purchase bill may be dated. Blank = no limit (today). Over the limit needs an override window, a one-off owner grant or a role with the back-date grant.',
  'How many days back a new purchase bill may be dated. Blank = no limit (today). Over the limit needs an override window, a one-off owner grant or a role with the back-date grant.', 205),
 ('backdate_max_days_cash_move', 'books', 'number', null, 'days', null, 0, 3650, 'Back-date limit: cash move date', 'Back-date limit: cash move date', 'Back-date limit: cash move date',
  'How many days back a new cash move (deposit, withdrawal, owner top-up or draw, advance) may be dated. Blank = no limit (today).',
  'How many days back a new cash move (deposit, withdrawal, owner top-up or draw, advance) may be dated. Blank = no limit (today).',
  'How many days back a new cash move (deposit, withdrawal, owner top-up or draw, advance) may be dated. Blank = no limit (today).', 206),
 ('backdate_max_days_expense', 'books', 'number', null, 'days', null, 0, 3650, 'Back-date limit: quick expense date', 'Back-date limit: quick expense date', 'Back-date limit: quick expense date',
  'How many days back a new quick expense may be dated. Blank = no limit (today).', 'How many days back a new quick expense may be dated. Blank = no limit (today).', 'How many days back a new quick expense may be dated. Blank = no limit (today).', 207),
 ('backdate_max_days_production', 'books', 'number', null, 'days', null, 0, 3650, 'Back-date limit: production date', 'Back-date limit: production date', 'Back-date limit: production date',
  'How many days back a production run may be dated (the made-at time). Blank = no limit (today).', 'How many days back a production run may be dated (the made-at time). Blank = no limit (today).', 'How many days back a production run may be dated (the made-at time). Blank = no limit (today).', 208),
 ('late_sale_policy', 'pos', 'choice', '"redate"', null, '["redate","redate_flag","park"]', null, null,
  'Offline sale older than the offline limit', 'Offline sale older than the offline limit', 'Offline sale older than the offline limit',
  'redate = the sale takes the time it reached the server (today). redate_flag = same, and a line goes to the Exceptions list. park = the sale is held for the owner, who accepts it with its own time, re-dates it, or rejects it. The limit itself is the setting "How many hours an offline sale keeps its own time".',
  'redate = the sale takes the time it reached the server (today). redate_flag = same, and a line goes to the Exceptions list. park = the sale is held for the owner, who accepts it with its own time, re-dates it, or rejects it. The limit itself is the setting "How many hours an offline sale keeps its own time".',
  'redate = the sale takes the time it reached the server (today). redate_flag = same, and a line goes to the Exceptions list. park = the sale is held for the owner, who accepts it with its own time, re-dates it, or rejects it. The limit itself is the setting "How many hours an offline sale keeps its own time".', 209),
 ('start_date_lock_after_opening', 'books', 'switch', 'false', null, null, null, null, 'Do not move the accounting start date after the opening is posted', 'Do not move the accounting start date after the opening is posted', 'Do not move the accounting start date after the opening is posted',
  'On = once an opening balance entry exists the start date cannot be changed (reverse the opening first). Off = as today.',
  'On = once an opening balance entry exists the start date cannot be changed (reverse the opening first). Off = as today.',
  'On = once an opening balance entry exists the start date cannot be changed (reverse the opening first). Off = as today.', 210),
 ('accounting_on_needs_reason', 'books', 'switch', 'false', null, null, null, null, 'Switching accounting ON needs a reason', 'Switching accounting ON needs a reason', 'Switching accounting ON needs a reason',
  'On = turning Accounting from OFF to ON must be done from the Period lock screen with a written reason, after a preview of the backlog that will be posted. Off = as today.',
  'On = turning Accounting from OFF to ON must be done from the Period lock screen with a written reason, after a preview of the backlog that will be posted. Off = as today.',
  'On = turning Accounting from OFF to ON must be done from the Period lock screen with a written reason, after a preview of the backlog that will be posted. Off = as today.', 211)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('late_sale_release', 'pos', 40, 'Decide a held late offline sale', 'Decide a held late offline sale', 'Decide a held late offline sale', 'once', null),
 ('backdate_over_limit', 'books', 41, 'Date a record further back than the limit', 'Date a record further back than the limit', 'Date a record further back than the limit', 'once', null)
on conflict (grant_code) do nothing;

-- ---------- small helpers ----------
create or replace function public._w1b_exc(p_kind text, p_reason text, p_src_table text, p_src_id text, p_amount numeric default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare id_ bigint;
begin
  insert into public.money_exceptions (kind, reason, src_table, src_id, amount, by_user) values (p_kind, left(coalesce(p_reason, ''), 500), p_src_table, p_src_id, p_amount, auth.uid()) returning id into id_;
  return id_;
end $$;

create or replace function public._w1b_audit(p_action text, p_table text, p_id text, p_detail jsonb) returns void
language sql security definer set search_path = public as $$
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
  values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), p_action, p_table, p_id, p_detail) $$;

create or replace function public._w1b_today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;

create or replace function public._w1b_pdate(t text) returns date language plpgsql immutable as $$
begin
  if t is null or t !~ '^\d{4}-\d{2}-\d{2}$' then return null; end if;
  return t::date;
exception when others then return null;      -- an impossible date (2026-02-30) locks nobody out
end $$;

-- ---------- the pure date test (never looks at who asks) ----------
-- automatic month lock: from the day AFTER day N of a month the whole previous month is closed; up to and including day N the month before that is the last closed one
create or replace function public._w1b_auto_date(p_today date, p_day int) returns date language plpgsql immutable as $$
declare a date;
begin
  if p_today is null or p_day is null or p_day not between 1 and 28 then return null; end if;
  a := date_trunc('month', p_today)::date - 1;                                   -- last day of the previous month
  if extract(day from p_today)::int <= p_day then a := date_trunc('month', a)::date - 1; end if;     -- not yet past day N: the month before that
  return a;
end $$;

create or replace function public._w1b_lock_date() returns date
language plpgsql stable security definer set search_path = public as $$
declare m text := coalesce(public.rule_txt('period_lock_mode'), 'manual'); d date;
begin
  if m = 'off' then return null; end if;
  d := public._w1b_pdate(public.rule_txt('period_closed_until'));
  if m = 'auto' then d := greatest(d, public._w1b_auto_date(public._w1b_today(), public.rule_num('auto_lock_day')::int)); end if;
  return d;
end $$;

create or replace function public._w1b_is_locked(p_date date) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare d date := public._w1b_lock_date();
begin return p_date is not null and d is not null and p_date <= d; end $$;

-- the owner is not exempt from the books-posting date test when the owner mode is log or reason (see the hook of _acct_locked)
create or replace function public._w1b_pure_posting() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.rule_txt('owner_closed_period_mode'), 'off') in ('log', 'reason') $$;

-- ---------- override windows ----------
create or replace function public._w1b_override_take(p_scope text, p_date date, p_doc text default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare o public.period_overrides; k text; cur text := coalesce(current_setting('bos89.ovx', true), '');
begin
  if auth.uid() is null or p_date is null then return null; end if;
  select * into o from public.period_overrides x
   where x.user_id = auth.uid() and x.ended_at is null and x.expires_at > now() and x.scope in (p_scope, 'both') and p_date between x.from_date and x.to_date
     and (x.doc_type is null or x.doc_type = p_doc) order by x.id limit 1;
  if not found then return null; end if;
  k := '|' || o.id::text || ':' || p_scope || '|';
  if position(k in cur) = 0 then           -- the first use in this transaction is the one that is logged
    update public.period_overrides set uses = uses + 1, last_used_at = now() where id = o.id;
    perform public._w1b_exc(case p_scope when 'lock' then 'period_lock_exception' else 'backdate_exception' end,
      o.reason || ' (override window #' || o.id::text || ', date ' || p_date::text || ')', 'period_overrides', o.id::text, null);
    perform public._w1b_audit('period_override_used', 'period_overrides', o.id::text, jsonb_build_object('scope', p_scope, 'date', p_date, 'doc', p_doc, 'reason', o.reason, 'started_by', o.started_by));
    perform set_config('bos89.ovx', cur || k, true);
  end if;
  return o.id;
end $$;

-- the decision behind lock_check (the hook calls this). true = the date may be used. false = period_closed. Raises period_closed_reason_required for the owner in mode reason.
create or replace function public._w1b_lock_allowed(p_date date) returns boolean
language plpgsql security definer set search_path = public as $$
declare d date := public._w1b_lock_date(); om text; k text; cur text;
begin
  if d is null or p_date is null or p_date > d then return true; end if;
  if public.is_owner() then
    om := coalesce(public.rule_txt('owner_closed_period_mode'), 'off');
    if om = 'off' then return true; end if;                                      -- today: the owner is silent
    if public._w1b_override_take('lock', p_date) is not null then return true; end if;
    if om = 'log' then
      k := '|log:' || p_date::text || '|'; cur := coalesce(current_setting('bos89.ovx', true), '');
      if position(k in cur) = 0 then
        perform public._w1b_exc('period_lock_exception', 'owner used a closed date (log mode), date ' || p_date::text, 'lock_check', null, null);
        perform public._w1b_audit('period_owner_closed_date', 'rules', 'period_closed_until', jsonb_build_object('date', p_date, 'mode', 'log'));
        perform set_config('bos89.ovx', cur || k, true);
      end if;
      return true;
    end if;
    raise exception 'period_closed_reason_required' using detail = 'books are closed until ' || d::text || '; open an override window with a reason';
  end if;
  if public.rule_ok('closed_period_edit', null, null, p_date, 'entry') then return true; end if;
  if public._m_lock_exc(p_date) then return true; end if;
  if public._w1b_override_take('lock', p_date) is not null then return true; end if;
  return false;
end $$;

-- ---------- back-date window per document type ----------
-- p_doc: purchase | cash_move | expense | production. Blank limit = off. Called by the hooks of the integrator (after the duplicate check, so a retry of a saved record is never refused).
create or replace function public._w1b_backdate_check(p_doc text, p_date date, p_client uuid default null, p_ref text default null) returns void
language plpgsql security definer set search_path = public as $$
declare lim numeric; t date := public._w1b_today();
begin
  if p_doc is null or p_doc not in ('purchase', 'cash_move', 'expense', 'production') or p_date is null then return; end if;
  lim := public.rule_num('backdate_max_days_' || p_doc);
  if lim is null then return; end if;                                        -- blank = off
  if p_date >= t - lim::int then return; end if;
  if public._w1b_override_take('backdate', p_date, p_doc) is not null then return; end if;
  if public._m_grant_take('override', 'backdate:' || p_doc, p_client, null, null, p_date, p_ref) then return; end if;     -- a one-off grant of the owner (phase87)
  if auth.uid() is not null and exists (select 1 from public.user_roles ur join public.rule_grants g on g.role_code = ur.role_code and g.grant_code = 'backdate_over_limit' and g.allowed
                                         join public.roles r on r.code = ur.role_code and r.active where ur.user_id = auth.uid()) then       -- a role the owner trusts with it
    perform public._w1b_exc('backdate_exception', p_doc || ' dated ' || p_date::text || ', limit ' || lim::text || ' days (role grant)', coalesce(p_ref, p_doc), null, null);
    perform public._w1b_audit('backdate_over_limit', p_doc, coalesce(p_client::text, p_ref, ''), jsonb_build_object('date', p_date, 'limit_days', lim));
    return;
  end if;
  raise exception 'backdate_over_limit' using detail = p_doc || ' dated ' || p_date::text || ' is more than ' || lim::text || ' days back';
end $$;

-- ---------- late offline sales ----------
-- Called by the hook of record_sale2 when the sale time is outside the offline window. Returns null = re-date to now (as today), {"keep":true} = keep the sale time, anything else = the parked answer.
create or replace function public._w1b_late_sale(p_client uuid, p_loc int, p_lines jsonb, p_discount numeric, p_payments jsonb, p_mobile text, p_name text, p_type text, p_note text,
  p_quick boolean, p_sold_at timestamptz, p_dk text, p_di numeric, p_at timestamptz) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pol text := coalesce(public.rule_txt('late_sale_policy'), 'redate'); okf text := coalesce(current_setting('bos89.late_ok', true), ''); h public.late_sales_held; eid bigint; hrs numeric;
begin
  if p_at is null or p_at > now() then return null; end if;                   -- a time in the future is always corrected (as before)
  if okf like 'keep:%' then return jsonb_build_object('keep', true); end if;  -- the owner accepted this sale with its own time
  if okf like 'redate:%' then return null; end if;
  hrs := round(extract(epoch from (now() - p_at)) / 3600, 1);
  if pol = 'park' then
    if p_client is not null then
      select * into h from public.late_sales_held where client_id = p_client and user_id = auth.uid();
      if found then return jsonb_build_object('parked', true, 'held_id', h.id, 'dup', true, 'status', h.status); end if;
    end if;
    insert into public.late_sales_held (client_id, user_id, location_id, sold_at, hours_late, payload)
      values (p_client, auth.uid(), p_loc, p_at, hrs, jsonb_build_object('lines', p_lines, 'discount', p_discount, 'payments', p_payments, 'customer_mobile', p_mobile, 'customer_name', p_name,
        'sale_type', p_type, 'note', p_note, 'quick', p_quick, 'discount_kind', p_dk, 'discount_input', p_di)) returning * into h;
    eid := public._w1b_exc('late_sale_held', 'offline sale made ' || to_char(p_at at time zone 'Asia/Dhaka', 'YYYY-MM-DD HH24:MI') || ', ' || hrs::text || ' h before it reached the server (limit '
      || coalesce(public.rule_num('pos_offline_hours'), 72)::text || ' h); held for the owner', 'late_sales_held', h.id::text, null);
    update public.late_sales_held set exception_id = eid where id = h.id;
    perform public._w1b_audit('late_sale_held', 'late_sales_held', h.id::text, jsonb_build_object('location', p_loc, 'sold_at', p_at, 'hours_late', hrs, 'client_id', p_client));
    return jsonb_build_object('parked', true, 'held_id', h.id, 'hours_late', hrs);
  elsif pol = 'redate_flag' then
    perform set_config('bos89.redated', to_char(p_at at time zone 'Asia/Dhaka', 'YYYY-MM-DD HH24:MI'), true);
  end if;
  return null;
end $$;

create or replace function public._w1b_sale_redate_flag() returns trigger language plpgsql security definer set search_path = public as $$
declare o text := coalesce(current_setting('bos89.redated', true), '');
begin
  if o = '' then return new; end if;
  perform set_config('bos89.redated', '', true);
  perform public._w1b_exc('late_sale_redated', 'receipt ' || new.receipt::text || ' was made ' || o || ' and was re-dated to the time it reached the server', 'sales', new.id::text, new.total);
  perform public._w1b_audit('late_sale_redated', 'sales', new.id::text, jsonb_build_object('receipt', new.receipt, 'made_at', o));
  return new;
end $$;
drop trigger if exists w1b_sales_redate_flag on public.sales;
create trigger w1b_sales_redate_flag after insert on public.sales for each row execute function public._w1b_sale_redate_flag();

-- ---------- guards on rules (only for calls that come through the API; the owner pasting SQL is not stopped) ----------
create or replace function public._w1b_rules_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare ov jsonb := coalesce(old.value, old.default_value); nv jsonb := coalesce(new.value, new.default_value); od date; nd date; pol text; need boolean;
begin
  if current_setting('role', true) is distinct from 'authenticated' then return new; end if;
  if ov is not distinct from nv then return new; end if;
  if new.key = 'accounting_start_date' then
    if public.rule_on('start_date_lock_after_opening') and nullif(ov #>> '{}', '') is not null
       and (exists (select 1 from public.journal_entries o where o.source_type = 'opening' and o.reverses_id is null
                     and not exists (select 1 from public.journal_entries r where r.reverses_id = o.id))
            or (to_regclass('public.opening_batches') is not null and exists (select 1 from public.opening_batches))) then
      raise exception 'start_date_locked_by_opening' using detail = 'an opening balance exists; reverse it before moving the accounting start date';
    end if;
  elsif new.key = 'period_closed_until' then
    pol := coalesce(public.rule_txt('lock_backward_policy'), 'allow');
    od := public._w1b_pdate(ov #>> '{}'); nd := public._w1b_pdate(nv #>> '{}');
    if pol <> 'allow' and od is not null and (nd is null or nd < od) then
      need := pol = 'reason_always' or exists (select 1 from public.year_closes y where y.status = 'closed' and (nd is null or y.fiscal_to >= nd));
      if need and coalesce(current_setting('bos89.lockreason', true), '') = '' then
        raise exception 'lock_backward_needs_reason' using detail = 'use Period lock > Set the lock date and write the reopen reason';
      end if;
    end if;
  elsif new.key = 'accounting_on' then
    if nv = 'true'::jsonb and ov is distinct from 'true'::jsonb and public.rule_on('accounting_on_needs_reason') and coalesce(current_setting('bos89.accreason', true), '') = '' then
      raise exception 'accounting_on_needs_reason' using detail = 'use Period lock > Accounting ON, read the backlog preview and write the reason';
    end if;
  elsif new.key = 'period_lock_mode' then
    if nv #>> '{}' = 'auto' and public.rule_num('auto_lock_day') is null then raise exception 'auto_lock_day_missing' using detail = 'set the automatic lock day first'; end if;
  elsif new.key = 'auto_lock_day' then
    if nullif(nv #>> '{}', '') is null and coalesce(public.rule_txt('period_lock_mode'), 'manual') = 'auto' then raise exception 'auto_lock_day_missing' using detail = 'the lock mode is auto: switch it first'; end if;
  end if;
  return new;
end $$;
drop trigger if exists w1b_rules_guard on public.rules;
create trigger w1b_rules_guard before update on public.rules for each row execute function public._w1b_rules_guard();

-- ============================================================================
-- Screens' functions
-- ============================================================================
create or replace function public._w1b_hooked(p_sig text) returns boolean language plpgsql stable security definer set search_path = public as $$
declare f regprocedure := to_regprocedure(p_sig);
begin
  if f is null then return false; end if;
  return position('bos89' in pg_get_functiondef(f)) > 0;
end $$;

create or replace function public.period_lock_state() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare own boolean := public.is_owner();
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'owner', own,
    'today', public._w1b_today(),
    'mode', coalesce(public.rule_txt('period_lock_mode'), 'manual'),
    'manual_date', public._w1b_pdate(public.rule_txt('period_closed_until')),
    'auto_day', public.rule_num('auto_lock_day'),
    'effective_lock_date', public._w1b_lock_date(),
    'owner_mode', coalesce(public.rule_txt('owner_closed_period_mode'), 'off'),
    'override_minutes', public.rule_num('period_override_default_minutes'),
    'backward_policy', coalesce(public.rule_txt('lock_backward_policy'), 'allow'),
    'backdate', jsonb_build_object('purchase', public.rule_num('backdate_max_days_purchase'), 'cash_move', public.rule_num('backdate_max_days_cash_move'),
                                   'expense', public.rule_num('backdate_max_days_expense'), 'production', public.rule_num('backdate_max_days_production')),
    'late_sale_policy', coalesce(public.rule_txt('late_sale_policy'), 'redate'),
    'offline_hours', coalesce(public.rule_num('pos_offline_hours'), 72),
    'start_date_lock_after_opening', public.rule_on('start_date_lock_after_opening'),
    'accounting_on', public.rule_on('accounting_on'),
    'accounting_on_needs_reason', public.rule_on('accounting_on_needs_reason'),
    'held_sales', (select count(*) from public.late_sales_held where status = 'held'),
    'hooks', jsonb_build_object(
      'lock_check', public._w1b_hooked('public.lock_check(date)'), 'acct_locked', public._w1b_hooked('public._acct_locked(date)'),
      'record_sale2', public._w1b_hooked('public.record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamp with time zone,text,numeric)'),
      'cash_move_add', public._w1b_hooked('public.cash_move_add(integer,text,numeric,date,text,uuid,text,text,uuid,boolean)'),
      'quick_expense_add', public._w1b_hooked('public.quick_expense_add(integer,date,text,text,numeric,text,boolean,text,uuid)'),
      'save_purchase', public._w1b_hooked('public.save_purchase(uuid,uuid,uuid,integer,text,date,jsonb,numeric,text,text,text,uuid,text)'),
      'production_post', public._w1b_hooked('public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)')),
    'my_windows', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'scope', o.scope, 'from', o.from_date, 'to', o.to_date, 'doc', o.doc_type, 'expires_at', o.expires_at, 'reason', o.reason) order by o.id)
                             from public.period_overrides o where o.user_id = auth.uid() and o.ended_at is null and o.expires_at > now()), '[]'::jsonb),
    'open_windows', case when own then coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'user_id', o.user_id, 'staff', (select staff_id from public.profiles where id = o.user_id), 'scope', o.scope,
                                'from', o.from_date, 'to', o.to_date, 'doc', o.doc_type, 'expires_at', o.expires_at, 'reason', o.reason, 'uses', o.uses) order by o.id)
                             from public.period_overrides o where o.ended_at is null and o.expires_at > now()), '[]'::jsonb) else '[]'::jsonb end);
end $$;

-- owner: set / clear the typed lock date. Moving back follows lock_backward_policy; a move back always leaves a line in the Exceptions list.
create or replace function public.period_lock_set(p_date date, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare cur date := public._w1b_pdate(public.rule_txt('period_closed_until')); back boolean; pol text := coalesce(public.rule_txt('lock_backward_policy'), 'allow');
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_date is not null and (p_date < date '2000-01-01' or p_date > public._w1b_today() + 366) then raise exception 'bad_date'; end if;
  back := cur is not null and (p_date is null or p_date < cur);
  if back and pol <> 'allow' and (p_reason is null or length(btrim(p_reason)) < 3) then
    if pol = 'reason_always' or exists (select 1 from public.year_closes y where y.status = 'closed' and (p_date is null or y.fiscal_to >= p_date)) then raise exception 'reason_required'; end if;
  end if;
  if back then perform set_config('bos89.lockreason', coalesce(nullif(btrim(p_reason), ''), 'moved back'), true); end if;
  perform public.set_rule('period_closed_until', case when p_date is null then null else to_jsonb(p_date::text) end);
  perform public._w1b_audit('period_lock_set', 'rules', 'period_closed_until', jsonb_build_object('old', cur, 'new', p_date, 'back', back, 'reason', left(btrim(coalesce(p_reason, '')), 300)));
  if back then perform public._w1b_exc('period_lock_exception', 'lock date moved back from ' || cur::text || ' to ' || coalesce(p_date::text, 'none') || ': ' || left(btrim(coalesce(p_reason, '')), 300), 'rules', 'period_closed_until', null); end if;
  perform set_config('bos89.lockreason', '', true);
  return jsonb_build_object('old', cur, 'new', p_date, 'back', back);
end $$;

create or replace function public.period_lock_policy_set(p_key text, p_value jsonb, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare old_ jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_key is null or p_key not in ('period_lock_mode', 'auto_lock_day', 'owner_closed_period_mode', 'period_override_default_minutes', 'lock_backward_policy', 'backdate_max_days_purchase',
       'backdate_max_days_cash_move', 'backdate_max_days_expense', 'backdate_max_days_production', 'late_sale_policy', 'start_date_lock_after_opening', 'accounting_on_needs_reason') then
    raise exception 'unknown_setting';
  end if;
  select coalesce(value, default_value) into old_ from public.rules where key = p_key;
  perform public.set_rule(p_key, p_value);
  perform public._w1b_audit('period_policy_set', 'rules', p_key, jsonb_build_object('old', old_, 'new', p_value, 'note', left(btrim(coalesce(p_note, '')), 300)));
  return jsonb_build_object('key', p_key, 'old', old_, 'new', p_value);
end $$;

-- owner: open a window (reason required) for himself or a named person
create or replace function public.period_override_start(p_reason text, p_from date, p_to date, p_minutes int default null, p_scope text default 'lock', p_for_user uuid default null, p_doc text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare mins int; u uuid := coalesce(p_for_user, auth.uid()); id_ bigint; exp timestamptz;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  if p_from is null or p_to is null or p_from > p_to or p_from < date '2000-01-01' or p_to > public._w1b_today() + 366 then raise exception 'bad_date'; end if;
  if p_scope is null or p_scope not in ('lock', 'backdate', 'both') then raise exception 'bad_scope'; end if;
  if p_doc is not null and p_doc not in ('purchase', 'cash_move', 'expense', 'production') then raise exception 'bad_doc'; end if;
  mins := coalesce(p_minutes, public.rule_num('period_override_default_minutes')::int, 60);
  if mins < 1 or mins > 1440 then raise exception 'bad_minutes'; end if;
  if not exists (select 1 from public.profiles where id = u and status = 'active') then raise exception 'unknown_user'; end if;
  exp := now() + make_interval(mins => mins);
  insert into public.period_overrides (scope, user_id, from_date, to_date, doc_type, reason, started_by, expires_at)
    values (p_scope, u, p_from, p_to, p_doc, left(btrim(p_reason), 300), auth.uid(), exp) returning id into id_;
  perform public._w1b_audit('period_override_start', 'period_overrides', id_::text, jsonb_build_object('scope', p_scope, 'for_user', u, 'from', p_from, 'to', p_to, 'doc', p_doc, 'minutes', mins, 'reason', left(btrim(p_reason), 300)));
  return jsonb_build_object('id', id_, 'expires_at', exp, 'minutes', mins);
end $$;

create or replace function public.period_override_end(p_id bigint, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  update public.period_overrides set ended_at = now(), ended_by = auth.uid(), end_note = left(btrim(coalesce(p_note, '')), 300) where id = p_id and ended_at is null;
  if not found then raise exception 'not found'; end if;
  perform public._w1b_audit('period_override_end', 'period_overrides', p_id::text, jsonb_build_object('note', left(btrim(coalesce(p_note, '')), 300)));
  return jsonb_build_object('id', p_id, 'ended', true);
end $$;

-- owner: every window ever opened, the Exceptions-list lines this package wrote, and the audit lines about the lock
create or replace function public.period_override_log(p_limit int default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare lim int := least(greatest(coalesce(p_limit, 100), 1), 500);
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'windows', coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (
        select o.id, o.scope, o.user_id, (select staff_id from public.profiles where id = o.user_id) as staff, o.from_date, o.to_date, o.doc_type, o.reason, o.started_at, o.expires_at, o.ended_at, o.uses, o.last_used_at
          from public.period_overrides o order by o.id desc limit lim) z), '[]'::jsonb),
    'exceptions', coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (
        select x.id, x.at, x.kind, x.reason, x.src_table, x.src_id, x.status from public.money_exceptions x
         where x.kind in ('period_lock_exception', 'backdate_exception', 'late_sale_held', 'late_sale_redated') order by x.id desc limit lim) z), '[]'::jsonb),
    'audit', coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (
        select a.id, a.at, a.staff_id, a.action, a.record_id, a.detail from public.audit_log a
         where a.action in ('period_lock_set', 'period_policy_set', 'period_override_start', 'period_override_used', 'period_override_end', 'period_owner_closed_date', 'late_sale_held', 'late_sale_redated',
                            'late_sale_release', 'backdate_over_limit', 'accounting_on_set') order by a.id desc limit lim) z), '[]'::jsonb));
end $$;

-- how late are records entered: read this for 30 days before choosing a back-date number (counts by days between the record date and the day it was entered)
create or replace function public.period_lateness_report(p_days int default 30) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare dd int := least(greatest(coalesce(p_days, 30), 1), 365); t date := public._w1b_today(); res jsonb := '{}'::jsonb; r record;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  for r in
    with x as (
      select 'purchase' as doc, (b.created_at at time zone 'Asia/Dhaka')::date - b.bill_date as late from public.purchase_bills b where b.status <> 'void' and b.created_at >= now() - make_interval(days => dd)
      union all select 'cash_move', (m.created_at at time zone 'Asia/Dhaka')::date - m.move_date from public.cash_moves m where m.status = 'done' and m.created_at >= now() - make_interval(days => dd)
      union all select 'expense', (q.created_at at time zone 'Asia/Dhaka')::date - q.exp_date from public.quick_expenses q where q.status <> 'void' and q.created_at >= now() - make_interval(days => dd)
      union all select 'production', (p.created_at at time zone 'Asia/Dhaka')::date - (p.made_at at time zone 'Asia/Dhaka')::date from public.production_runs p where p.created_at >= now() - make_interval(days => dd))
    select doc, count(*) n, coalesce(max(late), 0) max_late, count(*) filter (where late <= 0) d0, count(*) filter (where late between 1 and 2) d1_2, count(*) filter (where late between 3 and 7) d3_7,
           count(*) filter (where late between 8 and 30) d8_30, count(*) filter (where late > 30) d31 from x group by doc
  loop
    res := res || jsonb_build_object(r.doc, jsonb_build_object('records', r.n, 'max_days_late', r.max_late, 'same_day', r.d0, 'days_1_2', r.d1_2, 'days_3_7', r.d3_7, 'days_8_30', r.d8_30, 'over_30', r.d31));
  end loop;
  return jsonb_build_object('days', dd, 'as_of', t, 'by_document', res, 'note', 'Sales are not listed: a sale carries no entry time. The offline sale limit is the setting pos_offline_hours.');
end $$;

-- accounting ON after OFF: what would be posted at once
create or replace function public.accounting_on_preview() returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb; oldest date;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  begin r := public.acct_post_pending(true, 5000);
  exception when others then return jsonb_build_object('ran', false, 'why', sqlerrm, 'accounting_on', public.rule_on('accounting_on')); end;
  select min((x ->> 'date')::date) into oldest from jsonb_array_elements(coalesce(r -> 'preview', '[]'::jsonb)) x;
  return jsonb_build_object('ran', true, 'accounting_on', public.rule_on('accounting_on'), 'start_date', public._w1b_pdate(public.rule_txt('accounting_start_date')),
    'would_post', coalesce((r ->> 'posted')::int, 0), 'would_reverse', coalesce((r ->> 'reversed')::int, 0), 'skipped_locked', coalesce((r ->> 'locked')::int, 0), 'by_type', coalesce(r -> 'by_type', '{}'::jsonb),
    'oldest_in_sample', oldest, 'data_needed', coalesce((r ->> 'data_needed')::boolean, false), 'more', coalesce((r ->> 'more')::boolean, false));
end $$;

create or replace function public.accounting_on_set(p_on boolean, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare was boolean := public.rule_on('accounting_on'); pv jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_on is null then raise exception 'bad_value'; end if;
  if p_on and not was and public.rule_on('accounting_on_needs_reason') and (p_reason is null or length(btrim(p_reason)) < 3) then raise exception 'reason_required'; end if;
  if p_on and not was then pv := public.accounting_on_preview(); end if;
  if p_on and not was then perform set_config('bos89.accreason', coalesce(nullif(btrim(p_reason), ''), 'switched on'), true); end if;
  perform public.set_rule('accounting_on', to_jsonb(p_on));
  perform set_config('bos89.accreason', '', true);
  perform public._w1b_audit('accounting_on_set', 'rules', 'accounting_on', jsonb_build_object('old', was, 'new', p_on, 'reason', left(btrim(coalesce(p_reason, '')), 300), 'backlog', pv));
  return jsonb_build_object('old', was, 'new', p_on, 'backlog', pv);
end $$;

-- ---------- held late sales ----------
create or replace function public.late_sales_held_list(p_status text default 'held') returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.can_grant('late_sale_release') then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (
    select h.id, h.client_id, h.location_id, h.sold_at, h.received_at, h.hours_late, h.status, h.user_id, (select staff_id from public.profiles where id = h.user_id) as staff,
           jsonb_array_length(coalesce(h.payload -> 'lines', '[]'::jsonb)) as n_lines,
           coalesce((select sum(nullif(p ->> 'amount', '')::numeric) from jsonb_array_elements(coalesce(h.payload -> 'payments', '[]'::jsonb)) p), 0) as paid,
           h.payload -> 'lines' as lines, h.decide_reason, h.decided_at, h.sale_id
      from public.late_sales_held h where p_status is null or h.status = p_status order by h.id desc limit 300) z), '[]'::jsonb);
end $$;

-- action: accept (the sale keeps its own time) | redate (it takes the time of now) | reject (it is not recorded). The sale is recorded AS the cashier who made it.
create or replace function public.late_sale_release(p_id bigint, p_action text, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare h public.late_sales_held; pl jsonb; res jsonb; me uuid := auth.uid();
  prev_sub text := coalesce(current_setting('request.jwt.claim.sub', true), ''); prev_claims text := coalesce(current_setting('request.jwt.claims', true), '');
begin
  if not public.is_active() or not public.can_grant('late_sale_release') then raise exception 'not allowed'; end if;
  if p_action is null or p_action not in ('accept', 'redate', 'reject') then raise exception 'bad_action'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  select * into h from public.late_sales_held where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if h.status <> 'held' then raise exception 'already_decided'; end if;
  if h.user_id = me and not (public.is_owner() and public.rule_on('owner_self_approve')) then raise exception 'maker_cannot_decide'; end if;
  if p_action <> 'reject' then
    pl := h.payload;
    perform set_config('request.jwt.claim.sub', h.user_id::text, true);
    perform set_config('request.jwt.claims', jsonb_build_object('sub', h.user_id::text, 'role', 'authenticated')::text, true);
    perform set_config('bos89.late_ok', case p_action when 'accept' then 'keep:' else 'redate:' end || h.id::text, true);
    res := public.record_sale2(h.client_id, h.location_id, pl -> 'lines', nullif(pl ->> 'discount', '')::numeric, pl -> 'payments', pl ->> 'customer_mobile', pl ->> 'customer_name', pl ->> 'sale_type',
      pl ->> 'note', nullif(pl ->> 'quick', '')::boolean, case when p_action = 'accept' then h.sold_at end, pl ->> 'discount_kind', nullif(pl ->> 'discount_input', '')::numeric);
    perform set_config('bos89.late_ok', '', true);
    perform set_config('request.jwt.claim.sub', prev_sub, true);
    perform set_config('request.jwt.claims', prev_claims, true);
  end if;
  update public.late_sales_held set status = case p_action when 'accept' then 'accepted' when 'redate' then 'redated' else 'rejected' end, decided_by = me, decided_at = now(),
         decide_reason = left(btrim(p_reason), 300), sale_id = nullif(res ->> 'id', '')::uuid, result = res where id = h.id;
  if h.exception_id is not null then
    update public.money_exceptions set status = 'resolved', resolved_by = me, resolved_at = now(), resolve_note = left(p_action || ': ' || btrim(p_reason), 300) where id = h.exception_id and status = 'open';
  end if;
  perform public._w1b_audit('late_sale_release', 'late_sales_held', h.id::text, jsonb_build_object('action', p_action, 'reason', left(btrim(p_reason), 300), 'maker', h.user_id, 'sale', res ->> 'id'));
  return jsonb_build_object('id', h.id, 'action', p_action, 'sale', res);
end $$;

-- ---------- privileges ----------
revoke all on function public._w1b_patch(regprocedure, text, text[]), public._w1b_exc(text, text, text, text, numeric), public._w1b_audit(text, text, text, jsonb), public._w1b_today(), public._w1b_pdate(text),
  public._w1b_auto_date(date, int), public._w1b_lock_date(), public._w1b_is_locked(date), public._w1b_pure_posting(), public._w1b_override_take(text, date, text), public._w1b_lock_allowed(date),
  public._w1b_backdate_check(text, date, uuid, text), public._w1b_late_sale(uuid, int, jsonb, numeric, jsonb, text, text, text, text, boolean, timestamptz, text, numeric, timestamptz),
  public._w1b_sale_redate_flag(), public._w1b_rules_guard(), public._w1b_hooked(text) from public, anon, authenticated;
revoke all on function public.period_lock_state(), public.period_lock_set(date, text), public.period_lock_policy_set(text, jsonb, text), public.period_override_start(text, date, date, int, text, uuid, text),
  public.period_override_end(bigint, text), public.period_override_log(int), public.period_lateness_report(int), public.accounting_on_preview(), public.accounting_on_set(boolean, text),
  public.late_sales_held_list(text), public.late_sale_release(bigint, text, text) from public, anon;
grant execute on function public.period_lock_state(), public.period_lock_set(date, text), public.period_lock_policy_set(text, jsonb, text), public.period_override_start(text, date, date, int, text, uuid, text),
  public.period_override_end(bigint, text), public.period_override_log(int), public.period_lateness_report(int), public.accounting_on_preview(), public.accounting_on_set(boolean, text),
  public.late_sales_held_list(text), public.late_sale_release(bigint, text, text) to authenticated;
