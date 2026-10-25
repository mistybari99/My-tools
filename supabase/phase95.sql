-- Phase 95 (bos95) - JOURNAL, CHART AND MAPPING CONTROLS (package W1-E, item U-08). Paste AFTER phase94 (which brings the request list and the approver logic). Paste-twice safe.
-- Earlier phase files are not edited. No shared function is replaced by this file. Controls that can be a trigger ARE triggers (they work without any hook):
--   journal_loc_check  - every line of a MANUAL journal must be in a place the caller may use (or the caller holds the all-places accounts right, or is the owner)
--   mapping_type_guard - a mapping key may only point to the account types listed in table w1e_mapping_types (owner editable)
-- Controls that need the whole journal (its total, its accounts) go through ONE gate function, _w1e_journal_gate, called by a hook in acct_journal_post (integrator, docs/integration/W1-E.md):
--   journal_attach_over        - blank = off; a manual journal above this total needs an attachment (the photo path)
--   journal_control_acct_mode  - allow (default) | request | block; a journal by a non-owner that touches a control account (cash, bank, receivable, payable, inventory)
-- SETTINGS (rules, module books, English label and hint, owner editable at any time, audit_log by the existing audit_rules trigger). Every default keeps TODAY'S behaviour:
--   journal_loc_check off, mapping_type_guard off, journal_attach_over blank, journal_control_acct_mode allow, journal_control_prefixes "11,1210,13,2100" (chart code prefixes of the control accounts)
-- Approval of a held journal uses the approver chosen under phase87 (see phase94). The maker never decides his own request. One-off exceptions: the phase87 grant (rule 'override'),
--   events w1e_journal_loc, w1e_journal_attach, w1e_journal_control, w1e_mapping; reason required, audit_log line, Exceptions row. A journal that does not balance is NEVER excepted.
-- Nothing is deleted. Test data only (test_*).

do $g$ begin
  if to_regprocedure('public._p94_present()') is null then raise exception 'phase95 needs phase94 first'; end if;
  if to_regprocedure('public._acct_write(date,integer,text,text,text,text,text,jsonb,bigint,uuid,text)') is null or to_regprocedure('public.acct_mapping_set(text,bigint)') is null then
    raise exception 'phase95 needs the accounting of phase40';
  end if;
end $g$;

create or replace function public._p95_present() returns boolean language sql immutable as $$ select true $$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, 'books', v.kind, v.dv, v.unit, v.ch, v.mn, v.mx, v.lab, v.lab, v.lab, v.hint, v.hint, v.hint, v.srt
  from (values
 ('journal_loc_check', 'switch', 'false'::jsonb, null::text, null::jsonb, null::numeric, null::numeric,
   'Check the place of every line of a manual journal',
   'When ON, a person may post a manual journal line only to a place he may use, and a line without a place needs the all-places right. Off = today. Recommended: ON.', 750),
 ('mapping_type_guard', 'switch', 'false'::jsonb, null, null, null, null,
   'Check the account type when a mapping is changed',
   'When ON, a mapping key (for example sales) may only point to the account types listed for it (for example income). Off = today. Recommended: ON.', 751),
 ('journal_attach_over', 'number', null, 'Tk', null, 0, 1000000000000,
   'A manual journal above this total needs an attachment',
   'Blank = off. Above this total the journal must carry a photo or file reference.', 752),
 ('journal_control_acct_mode', 'choice', '"allow"'::jsonb, null, '["allow","request","block"]'::jsonb, null, null,
   'Manual journal by a person who is not the owner on a cash, bank, receivable, payable or inventory account',
   'allow = today. request = the journal waits for the approver chosen under "Approval of the owner''s own entries". block = refused unless the owner allows one exception.', 753),
 ('journal_control_prefixes', 'text', '"11,1210,13,2100"'::jsonb, null, null, null, null,
   'Chart codes that count as control accounts',
   'Comma separated code beginnings. Default: 11 (cash, bank, wallets), 1210 (customer receivables), 13 (inventory), 2100 (supplier payables).', 754)
 ) v(key, kind, dv, unit, ch, mn, mx, lab, hint, srt)
on conflict (key) do nothing;

-- ---------- which account types a mapping key may point to (editable by the owner, never deleted: switch a row off) ----------
create table if not exists public.w1e_mapping_types (
  key_like text primary key check (length(key_like) between 2 and 60),
  allowed text[] not null check (array_length(allowed, 1) >= 1 and allowed <@ array['asset', 'liability', 'equity', 'income', 'expense']),
  active boolean not null default true,
  note text, updated_by uuid, updated_at timestamptz not null default now()
);
drop trigger if exists w1e_mapping_types_nodel on public.w1e_mapping_types;
create trigger w1e_mapping_types_nodel before delete on public.w1e_mapping_types for each row execute function public.no_hard_delete();
drop trigger if exists audit_w1e_mapping_types on public.w1e_mapping_types;
create trigger audit_w1e_mapping_types after insert or update on public.w1e_mapping_types for each row execute function public.log_change('key_like');
alter table public.w1e_mapping_types enable row level security;
revoke all on public.w1e_mapping_types from public, anon, authenticated;
insert into public.w1e_mapping_types (key_like, allowed, note) values
 ('sales', '{income}', 'sales'), ('sales\_returns', '{income}', 'contra income'), ('sales\_discount', '{income}', 'contra income'), ('cogs', '{expense}', null),
 ('exp\_%', '{expense}', 'expense heads'), ('inv\_%', '{asset}', 'inventory'), ('receivable', '{asset}', null), ('payable', '{liability}', null), ('pay\_%', '{asset}', 'cash, bank, mobile, card'),
 ('cust\_advance', '{liability}', null), ('owner\_capital', '{equity}', null), ('owner\_drawings', '{equity}', 'contra equity'), ('retained', '{equity}', null), ('retained\_close', '{equity}', null),
 ('partner\_ps\_%', '{equity,expense}', 'partner profit share'), ('partner\_loan', '{liability}', null), ('partner\_payable', '{liability}', null),
 ('salary\_exp', '{expense}', null), ('salary\_accrued', '{liability}', null), ('staff\_advance', '{asset}', null), ('fixed\_assets', '{asset}', null), ('accum\_depr', '{asset}', 'contra asset'),
 ('depreciation', '{expense}', null), ('cash\_short', '{expense,income}', 'short or over'), ('wastage', '{expense}', null), ('transit\_loss', '{expense}', null), ('carrier\_claim', '{asset}', null),
 ('hub\_clearing', '{asset,liability}', 'clearing'), ('wallet\_fee', '{expense}', null), ('m\_bank\_charge', '{expense}', null), ('m\_interest\_income', '{income}', null),
 ('overhead\_absorbed', '{expense}', 'contra expense'), ('purch\_%', '{expense}', null), ('m\_acct\_%', '{asset}', 'money accounts'), ('d\_wallet\_%', '{asset}', 'legacy wallets')
on conflict (key_like) do nothing;

-- ---------- helpers ----------
create or replace function public._w1e_is_control(p_account bigint) returns boolean language plpgsql stable security definer set search_path = public as $$
declare code text; pf text;
begin
  select a.code into code from public.coa_accounts a where a.id = p_account;
  if code is null then return false; end if;
  for pf in select btrim(x) from unnest(string_to_array(coalesce(public.rule_txt('journal_control_prefixes'), '11,1210,13,2100'), ',')) x loop
    if pf <> '' and code like pf || '%' then return true; end if;
  end loop;
  return false;
end $$;

create or replace function public._w1e_journal_loc_ok(p_lines jsonb, p_loc int) returns boolean language plpgsql stable security definer set search_path = public as $$
declare e jsonb; lc int;
begin
  for e in select * from jsonb_array_elements(p_lines) loop
    lc := coalesce(nullif(e ->> 'location_id', '')::int, p_loc);
    if not (public._acct_all() or (lc is not null and public.can_loc(lc))) then return false; end if;
  end loop;
  return true;
end $$;

-- ---------- control 1: the place of every line of a manual journal (trigger; works without the hook) ----------
create or replace function public._w1e_jl_bi() returns trigger language plpgsql security definer set search_path = public as $$
declare e record; lc int;
begin
  if auth.uid() is null or not public.rule_on('journal_loc_check') or coalesce(current_setting('w1e.apply', true), '') = '1' or coalesce(current_setting('w1e.jl_loc', true), '') = '1' then return new; end if;
  select entry_date, location_id, source_type, reverses_id, client_id, id into e from public.journal_entries where id = new.entry_id;
  if not found or e.source_type <> 'manual' or e.reverses_id is not null then return new; end if;
  lc := coalesce(new.location_id, e.location_id);
  if public._acct_all() or (lc is not null and public.can_loc(lc)) then return new; end if;
  if public._m_grant_take('override', 'w1e_journal_loc', e.client_id, null, null, e.entry_date, 'journal_entries:' || e.id::text) then
    perform set_config('w1e.jl_loc', '1', true);
    return new;
  end if;
  raise exception 'journal_place_not_allowed' using detail = 'line ' || new.line_no::text || ' place ' || coalesce(lc::text, 'none');
end $$;
drop trigger if exists a95_w1e_jl_bi on public.journal_lines;
create trigger a95_w1e_jl_bi before insert on public.journal_lines for each row execute function public._w1e_jl_bi();

-- ---------- control 2: the account type of a mapping (trigger; works without the hook) ----------
create or replace function public._w1e_mapping_bi() returns trigger language plpgsql security definer set search_path = public as $$
declare t text; allowed text[];
begin
  if auth.uid() is null or not public.rule_on('mapping_type_guard') or coalesce(current_setting('w1e.apply', true), '') = '1' then return new; end if;
  if tg_op = 'UPDATE' and new.account_id is not distinct from old.account_id then return new; end if;
  select m.allowed into allowed from public.w1e_mapping_types m where m.active and new.key like m.key_like order by length(m.key_like) desc, m.key_like limit 1;
  if allowed is null then return new; end if;
  select a.type into t from public.coa_accounts a where a.id = new.account_id;
  if t = any (allowed) then return new; end if;
  if coalesce(current_setting('w1e.map_ok', true), '') = new.key || ':' || new.account_id::text then return new; end if;      -- INSERT .. ON CONFLICT fires the trigger twice: one exception covers both
  if public._m_grant_take('override', 'w1e_mapping', null, null, null, public._w1e_today(), 'acct_mappings:' || new.key) then
    perform set_config('w1e.map_ok', new.key || ':' || new.account_id::text, true);
    return new;
  end if;
  raise exception 'mapping_type_mismatch' using detail = 'key ' || new.key || ' needs ' || array_to_string(allowed, ' or ') || ', account is ' || coalesce(t, '?');
end $$;
drop trigger if exists a95_w1e_mapping_bi on public.acct_mappings;
create trigger a95_w1e_mapping_bi before insert or update on public.acct_mappings for each row execute function public._w1e_mapping_bi();

-- ---------- controls 3 and 4: attachment above a total, and journals on control accounts (called from the acct_journal_post hook with the resolved lines) ----------
create or replace function public._w1e_journal_gate(p_date date, p_loc int, p_memo text, p_lines jsonb, p_photo text, p_client uuid, p_total numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ov numeric := public.rule_num('journal_attach_over'); md text := public._w1e_choice('journal_control_acct_mode', 'allow'); ctl boolean := false; x jsonb; rid bigint; ex public.w1e_requests;
begin
  if auth.uid() is null or coalesce(current_setting('w1e.apply', true), '') = '1' then return null; end if;
  if p_client is not null then
    select * into ex from public.w1e_requests where client_id = p_client and kind = 'journal_control';
    if found then return jsonb_build_object('pending', true, 'request_id', ex.id, 'dup', true); end if;
  end if;
  if ov is not null and p_total > ov and nullif(btrim(coalesce(p_photo, '')), '') is null then
    if not public._m_grant_take('override', 'w1e_journal_attach', p_client, null, p_total, p_date, 'journal') then
      raise exception 'attachment_required' using detail = 'total ' || p_total::text || ' is above ' || ov::text;
    end if;
  end if;
  if md <> 'allow' and not public.is_owner() then
    for x in select * from jsonb_array_elements(p_lines) loop
      if public._w1e_is_control((x ->> 'account_id')::bigint) then ctl := true; exit; end if;
    end loop;
    if ctl then
      if md = 'block' then
        if not public._m_grant_take('override', 'w1e_journal_control', p_client, null, p_total, p_date, 'journal') then raise exception 'control_account_blocked'; end if;
      else
        if public.rule_on('journal_loc_check') and not public._w1e_journal_loc_ok(p_lines, p_loc) then      -- the approver posts it later: the maker's own place rights are checked now
          if not public._m_grant_take('override', 'w1e_journal_loc', p_client, null, null, p_date, 'journal') then raise exception 'journal_place_not_allowed'; end if;
        end if;
        insert into public.w1e_requests (kind, location_id, amount, ref_date, summary, payload, client_id, requested_by, requested_staff)
          values ('journal_control', p_loc, p_total, p_date, left('Manual journal ' || p_total::text || ' on ' || p_date::text || ': ' || coalesce(p_memo, ''), 300),
                  jsonb_build_object('date', p_date, 'loc', p_loc, 'memo', p_memo, 'lines', p_lines, 'photo', p_photo, 'client', p_client, 'total', p_total), p_client, auth.uid(), public._w1e_staff())
          returning id into rid;
        perform public._w1e_audit('w1e_request_create', 'w1e_requests', rid::text, jsonb_build_object('kind', 'journal_control', 'amount', p_total, 'date', p_date));
        perform public._w1e_exc('w1e_journal_request', 'w1e_journal_control', p_total, 'w1e_requests', rid::text, 'manual journal on a control account waits for the approver');
        return jsonb_build_object('pending', true, 'request_id', rid, 'total', p_total);
      end if;
    end if;
  end if;
  return null;
end $$;

create or replace function public._w1e_apply_journal_control(r public.w1e_requests) returns text language plpgsql security definer set search_path = public as $$
declare p jsonb := r.payload; id_ bigint;
begin
  perform public.lock_check((p ->> 'date')::date);
  id_ := public._acct_write((p ->> 'date')::date, nullif(p ->> 'loc', '')::int, 'manual', coalesce(nullif(p ->> 'client', ''), gen_random_uuid()::text), null,
                            left(coalesce(p ->> 'memo', ''), 240) || ' [request ' || r.id::text || ']', null, p -> 'lines', null, nullif(p ->> 'client', '')::uuid, nullif(p ->> 'photo', ''));
  return 'journal_entries:' || id_::text;
end $$;

-- ---------- API ----------
create or replace function public.w1e_mapping_check(p_key text, p_account bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare t text; allowed text[];
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  select m.allowed into allowed from public.w1e_mapping_types m where m.active and p_key like m.key_like order by length(m.key_like) desc, m.key_like limit 1;
  select a.type into t from public.coa_accounts a where a.id = p_account;
  return jsonb_build_object('key', p_key, 'type', t, 'allowed', to_jsonb(allowed), 'ok', allowed is null or t = any (allowed), 'guard_on', public.rule_on('mapping_type_guard'));
end $$;

create or replace function public.w1e_mapping_types_list() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public._acct_view() or public.is_owner()) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('key_like', key_like, 'allowed', to_jsonb(allowed), 'active', active, 'note', note) order by key_like) from public.w1e_mapping_types), '[]'::jsonb);
end $$;

create or replace function public.w1e_mapping_type_set(p_key_like text, p_allowed text[], p_active boolean default true, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare old_ public.w1e_mapping_types;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  if p_key_like is null or p_key_like !~ '^[a-z0-9_%\\]{2,60}$' then raise exception 'bad_key'; end if;
  select * into old_ from public.w1e_mapping_types where key_like = p_key_like;
  insert into public.w1e_mapping_types (key_like, allowed, active, note, updated_by, updated_at) values (p_key_like, p_allowed, coalesce(p_active, true), left(btrim(p_reason), 300), auth.uid(), now())
    on conflict (key_like) do update set allowed = excluded.allowed, active = excluded.active, note = excluded.note, updated_by = auth.uid(), updated_at = now();
  perform public._w1e_audit('w1e_mapping_type_set', 'w1e_mapping_types', p_key_like, jsonb_build_object('old', case when old_.key_like is not null then jsonb_build_object('allowed', to_jsonb(old_.allowed), 'active', old_.active) end,
          'new', jsonb_build_object('allowed', to_jsonb(p_allowed), 'active', coalesce(p_active, true)), 'reason', left(p_reason, 300)));
  return jsonb_build_object('key_like', p_key_like, 'allowed', to_jsonb(p_allowed), 'active', coalesce(p_active, true));
end $$;

-- ---------- privileges ----------
revoke all on function public._p95_present(), public._w1e_is_control(bigint), public._w1e_journal_loc_ok(jsonb, int), public._w1e_jl_bi(), public._w1e_mapping_bi(),
  public._w1e_journal_gate(date, int, text, jsonb, text, uuid, numeric), public._w1e_apply_journal_control(public.w1e_requests) from public, anon, authenticated;
revoke all on function public.w1e_mapping_check(text, bigint), public.w1e_mapping_types_list(), public.w1e_mapping_type_set(text, text[], boolean, text) from public, anon, authenticated;
grant execute on function public.w1e_mapping_check(text, bigint), public.w1e_mapping_types_list(), public.w1e_mapping_type_set(text, text[], boolean, text) to authenticated;
