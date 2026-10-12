-- PHASE 18 (W5): server-side BLIND COUNT for forms 14-1 (drawer) and 10-1 (hub), and PIN SIGNATURES (second signature = another login).
-- Additive, idempotent, safe to paste whole in the Supabase SQL editor.  ORDER: phase8..phase17 first (needs phase16 get_limit and phase17 for nothing else).
-- Everything is OFF by default: rules blind_count_on, pin_signature_on = false.  Nothing changes for any form until the owner switches them on.
--
-- BLIND COUNT (rule 9)
--   count_save(entry, section, counted): the counted figure is stored FIRST (immutable), the expected figure is computed on the server from the
--   entry's other saved data and returned only after the save.  Short/over is stored always (also 0) in entry_counts and mirrored to
--   entries.check_data.blind.  `expected` is never stored in entries.data and never returned by any function before the count is saved,
--   except to the owner / holders of the delegable grant see_expected (count_peek, logged; rule owner_sees_expected_first can take it from the owner too).
--   sections: 'drawer' = 14-1 (the maker counts the cash drawer), 'hub' = 10-1 (the hub person counts the handover).
-- PIN SIGNATURES (rule 10)
--   A second signature is a different login with its own PIN.  The browser signs the second person in on a throw-away client (no session kept)
--   and that client calls sign_entry: auth.uid() is the signer.  The server refuses signer = maker, one login twice, a role signed twice,
--   a signer without access to the place, a locked login.  entry_signatures is append-only.  Wrong PINs go through login_failed (phase11).
--   NOTE: SQL cannot check another user's password, so the PIN itself is checked by Supabase Auth, not by this file.

-- ---------- (1) rules + grant ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('blind_count_on', 'entries', 'switch', 'false', null, null, null, null, 'অন্ধ গণনা: আগে গণনা সেভ, তারপর প্রত্যাশিত অঙ্ক', 'Blind count: আগে count save, তারপর expected', 'Blind count: save the count first, then see the expected figure',
   'চালু করলে ১৪-১ (ড্রয়ার) ও ১০-১ (হাব)-এ প্রত্যাশিত অঙ্ক গণনা সেভের আগে দেখা যাবে না। ফর্ম × লোকেশন আলাদা করে বন্ধ করা যায়', 'চালু করলে 14-1 (drawer) ও 10-1 (hub)-এ expected figure count save-এর আগে দেখা যাবে না। form × location আলাদা বন্ধ করা যায়', 'When on, forms 14-1 (drawer) and 10-1 (hub) do not show the expected figure before the count is saved. Can be switched off per form x place', 94),
 ('owner_sees_expected_first', 'entries', 'switch', 'true', null, null, null, null, 'মালিক গণনার আগেও প্রত্যাশিত অঙ্ক দেখতে পারবেন', 'Owner count-এর আগেও expected দেখতে পারবেন', 'Owner may see the expected figure before the count is saved',
   'বন্ধ করলে মালিকও আগে দেখতে পারবেন না (see_expected অনুমতিপ্রাপ্ত অন্য কেউ পারবেন)। প্রতিবার দেখা লগে থাকে', 'বন্ধ করলে owner-ও আগে দেখতে পারবেন না (see_expected grant-ওয়ালা অন্য কেউ পারবেন)। প্রতিবার log-এ থাকে', 'When off the owner is blind too (a person holding see_expected still may). Every early look is logged', 95),
 ('pin_signature_on', 'entries', 'switch', 'false', null, null, null, null, 'পিন স্বাক্ষর: দ্বিতীয় স্বাক্ষর অন্য লগইন + নিজের পিন', 'PIN signature: দ্বিতীয় signature অন্য login + নিজের PIN', 'PIN signature: the second signature is another login with its own PIN',
   'বন্ধ থাকলে আগের মতো নাম বেছে সাক্ষী। চালু করলে ফর্ম অনুযায়ী (তালিকা) সাক্ষী নিজের পিন দিয়ে স্বাক্ষর করবেন; লেখক নিজে স্বাক্ষর করতে পারবেন না', 'বন্ধ থাকলে আগের মতো name বেছে witness। চালু করলে form অনুযায়ী witness নিজের PIN দিয়ে sign করবেন', 'When off the old name-picker witness stays. When on (per form list) the witness signs with their own PIN; the maker can never be the signer', 96)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('see_expected', 'master', 69, 'গণনা সেভের আগে প্রত্যাশিত অঙ্ক দেখা', 'Count save-এর আগে expected দেখা', 'See the expected figure before the count is saved', 'window', null)
on conflict (grant_code) do nothing;

-- ---------- (2) per form x place / per form switch lists ----------
create table if not exists public.blind_count_cfg (
  form_code text not null references public.forms(code),
  location_id int not null references public.locations(id),
  enabled boolean not null default true,
  changed_by uuid, changed_at timestamptz not null default now(),
  primary key (form_code, location_id)
);
create table if not exists public.pin_sig_cfg (
  form_code text primary key references public.forms(code),
  enabled boolean not null default true,
  changed_by uuid, changed_at timestamptz not null default now()
);
alter table public.blind_count_cfg enable row level security;
alter table public.pin_sig_cfg enable row level security;
drop policy if exists blind_count_cfg_read on public.blind_count_cfg;
create policy blind_count_cfg_read on public.blind_count_cfg for select to authenticated using (public.is_active());
drop policy if exists pin_sig_cfg_read on public.pin_sig_cfg;
create policy pin_sig_cfg_read on public.pin_sig_cfg for select to authenticated using (public.is_active());
revoke all on public.blind_count_cfg, public.pin_sig_cfg from public, anon, authenticated;
grant select on public.blind_count_cfg, public.pin_sig_cfg to authenticated;
drop trigger if exists audit_blind_count_cfg on public.blind_count_cfg;
create trigger audit_blind_count_cfg after insert or update on public.blind_count_cfg for each row execute function public.log_change('form_code,location_id');
drop trigger if exists audit_pin_sig_cfg on public.pin_sig_cfg;
create trigger audit_pin_sig_cfg after insert or update on public.pin_sig_cfg for each row execute function public.log_change('form_code');
drop trigger if exists blind_count_cfg_no_delete on public.blind_count_cfg;
create trigger blind_count_cfg_no_delete before delete on public.blind_count_cfg for each row execute function public.no_hard_delete();
drop trigger if exists pin_sig_cfg_no_delete on public.pin_sig_cfg;
create trigger pin_sig_cfg_no_delete before delete on public.pin_sig_cfg for each row execute function public.no_hard_delete();

create or replace function public.blind_active(p_form text, p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select p_form in ('14-1', '10-1') and public.rule_on('blind_count_on')
     and coalesce((select enabled from public.blind_count_cfg where form_code = p_form and location_id = p_loc), true);
$$;
create or replace function public.pin_sig_active(p_form text) returns boolean
language sql stable security definer set search_path = public as $$
  select p_form in ('14-1', '10-1') and public.rule_on('pin_signature_on')
     and coalesce((select enabled from public.pin_sig_cfg where form_code = p_form), true);
$$;
create or replace function public.blind_cfg_set(p_form text, p_loc int, p_enabled boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_form not in ('14-1', '10-1') then raise exception 'form_not_supported'; end if;
  if p_enabled is null then raise exception 'bad_value'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'location_not_found'; end if;
  insert into public.blind_count_cfg (form_code, location_id, enabled, changed_by, changed_at) values (p_form, p_loc, p_enabled, auth.uid(), now())
    on conflict (form_code, location_id) do update set enabled = excluded.enabled, changed_by = excluded.changed_by, changed_at = excluded.changed_at;
  return jsonb_build_object('form', p_form, 'location_id', p_loc, 'enabled', p_enabled);
end $$;
create or replace function public.pin_sig_cfg_set(p_form text, p_enabled boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_form not in ('14-1', '10-1') then raise exception 'form_not_supported'; end if;
  if p_enabled is null then raise exception 'bad_value'; end if;
  insert into public.pin_sig_cfg (form_code, enabled, changed_by, changed_at) values (p_form, p_enabled, auth.uid(), now())
    on conflict (form_code) do update set enabled = excluded.enabled, changed_by = excluded.changed_by, changed_at = excluded.changed_at;
  return jsonb_build_object('form', p_form, 'enabled', p_enabled);
end $$;

-- ---------- (3) counts ----------
create table if not exists public.entry_counts (
  entry_id uuid not null references public.entries(id),
  section text not null check (section in ('drawer', 'hub')),
  counted_detail jsonb not null,                 -- what the person typed (notes by denomination, or one number)
  counted numeric not null check (counted between 0 and 1000000000),
  expected numeric not null,                     -- computed on the server at save time (kept here, never in entries.data)
  diff numeric not null,                         -- counted - expected, ALWAYS stored, also 0
  inputs_hash text,                              -- hash of the figures the expected value was made from
  counted_by uuid not null, counted_staff text, counted_at timestamptz not null default now(),
  expected_seen_by uuid, expected_seen_at timestamptz,
  seen_before_count boolean not null default false,
  primary key (entry_id, section)
);
create table if not exists public.entry_count_peeks (
  id bigserial primary key,
  entry_id uuid not null references public.entries(id),
  section text not null,
  seen_by uuid not null, seen_staff text, seen_at timestamptz not null default now()
);
create or replace function public._append_only18() returns trigger
language plpgsql set search_path = public as $$
begin raise exception '% is append-only', tg_table_name; end $$;
drop trigger if exists entry_counts_no_change on public.entry_counts;
create trigger entry_counts_no_change before update or delete on public.entry_counts for each row execute function public._append_only18();
drop trigger if exists entry_counts_no_truncate on public.entry_counts;
create trigger entry_counts_no_truncate before truncate on public.entry_counts for each statement execute function public._append_only18();
alter table public.entry_counts enable always trigger entry_counts_no_truncate;
drop trigger if exists entry_count_peeks_no_change on public.entry_count_peeks;
create trigger entry_count_peeks_no_change before update or delete on public.entry_count_peeks for each row execute function public._append_only18();
drop trigger if exists entry_count_peeks_no_truncate on public.entry_count_peeks;
create trigger entry_count_peeks_no_truncate before truncate on public.entry_count_peeks for each statement execute function public._append_only18();
alter table public.entry_count_peeks enable always trigger entry_count_peeks_no_truncate;
alter table public.entry_counts enable row level security;
alter table public.entry_count_peeks enable row level security;
drop policy if exists entry_counts_read on public.entry_counts;
create policy entry_counts_read on public.entry_counts for select to authenticated
  using (exists (select 1 from public.entries e where e.id = entry_id));      -- rows exist only AFTER the count; same visibility as the entry
drop policy if exists entry_count_peeks_read on public.entry_count_peeks;
create policy entry_count_peeks_read on public.entry_count_peeks for select to authenticated using (public.is_owner());
revoke all on public.entry_counts, public.entry_count_peeks from public, anon, authenticated;
grant select on public.entry_counts, public.entry_count_peeks to authenticated;
revoke all on sequence public.entry_count_peeks_id_seq from public, anon, authenticated;

-- lenient number of a json field (blank / junk / Infinity = 0), same as the browser's num()
create or replace function public._n18(j jsonb, k text) returns numeric
language plpgsql immutable set search_path = public as $$
declare v numeric;
begin
  v := nullif(btrim(coalesce(j ->> k, '')), '')::numeric;
  if v is null or not (v between -1000000000000 and 1000000000000) then return 0; end if;
  return v;
exception when others then return 0;
end $$;

-- total of a count: a plain number, or notes by denomination {n1000..n1, coin}.  strict = refuse bad input
create or replace function public._den_total18(j jsonb, strict boolean) returns numeric
language plpgsql immutable set search_path = public as $$
declare t numeric := 0; d int; v numeric; k text;
begin
  if j is null or jsonb_typeof(j) = 'null' then return 0; end if;
  if jsonb_typeof(j) = 'number' then
    v := (j #>> '{}')::numeric;
    if not (v between 0 and 1000000000) then if strict then raise exception 'bad_count'; end if; return 0; end if;
    return v;
  end if;
  if jsonb_typeof(j) <> 'object' then if strict then raise exception 'bad_count'; end if; return 0; end if;
  foreach d in array array[1000, 500, 200, 100, 50, 20, 10, 5, 2, 1] loop
    k := 'n' || d;
    if j ? k then
      begin v := nullif(btrim(j ->> k), '')::numeric; exception when others then v := null; if strict then raise exception 'bad_count'; end if; end;
      if v is not null then
        if not (v between 0 and 1000000) or (strict and v <> trunc(v)) then if strict then raise exception 'bad_count'; end if; v := 0; end if;
        t := t + d * v;
      end if;
    end if;
  end loop;
  if j ? 'coin' then
    begin v := nullif(btrim(j ->> 'coin'), '')::numeric; exception when others then v := null; if strict then raise exception 'bad_count'; end if; end;
    if v is not null then
      if not (v between 0 and 1000000000) then if strict then raise exception 'bad_count'; end if; v := 0; end if;
      t := t + v;
    end if;
  end if;
  if not (t between 0 and 1000000000) then if strict then raise exception 'bad_count'; end if; return 0; end if;
  return t;
end $$;

-- the figures the expected value is made of (also hashed, to show later changes)
create or replace function public._count_inputs18(e public.entries, p_section text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare fl numeric; fj jsonb; d jsonb := e.data;
begin
  if p_section = 'drawer' then
    begin fj := public.get_limit(e.location_id, 'drawer_float', e.entry_date); exception when others then fj := null; end;
    fl := case when fj is null or jsonb_typeof(fj) <> 'number' then null else (fj #>> '{}')::numeric end;
    return jsonb_build_object('float', fl, 'open_counted', nullif(btrim(coalesce(d ->> 'open_counted', '')), ''),
      'total', public._n18(d, 'total_entered'), 'digital', public._n18(d, 'd_bkash') + public._n18(d, 'd_nagad') + public._n18(d, 'd_card') + public._n18(d, 'd_bank') + public._n18(d, 'd_other'),
      'dues', public._n18(d, 'dues'), 'new_adv', public._n18(d, 'new_adv'), 'prior_adv', public._n18(d, 'prior_adv'), 'refund', public._n18(d, 'refund'),
      'credit', public._n18(d, 'credit_sales'), 'midday', public._n18(d, 'midday_hub'), 'rounding', public._n18(d, 'rounding'));
  end if;
  return jsonb_build_object('sent', public._den_total18(d -> 'count', false), 'leave', public._n18(d, 'leave_float'));
end $$;
-- same arithmetic as forms.js (14-1: guidebook G.6 equation 1; 10-1: handover = counted - float left)
create or replace function public._count_expected18(p_in jsonb, p_section text) returns numeric
language plpgsql immutable set search_path = public as $$
declare openf numeric;
begin
  if p_section = 'drawer' then
    openf := case when p_in ->> 'open_counted' is not null then (p_in ->> 'open_counted')::numeric when p_in ->> 'float' is not null then (p_in ->> 'float')::numeric else 0 end;
    return openf + (p_in ->> 'total')::numeric - (p_in ->> 'digital')::numeric + (p_in ->> 'dues')::numeric + (p_in ->> 'new_adv')::numeric - (p_in ->> 'prior_adv')::numeric
      - (p_in ->> 'refund')::numeric - (p_in ->> 'credit')::numeric - (p_in ->> 'midday')::numeric + (p_in ->> 'rounding')::numeric;
  end if;
  return (p_in ->> 'sent')::numeric - (p_in ->> 'leave')::numeric;
end $$;

create or replace function public._count_sec18(p_section text) returns text
language sql immutable as $$ select case p_section when 'drawer' then '14-1' when 'hub' then '10-1' end; $$;

-- may the caller count / peek at this entry?
create or replace function public._count_can18(e public.entries, p_section text, p_for_save boolean) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare self_ok boolean;
begin
  if not public.is_active() or not public.can_loc(e.location_id) then return false; end if;
  if public.is_owner() then return true; end if;
  if p_section = 'drawer' then
    return e.created_by = auth.uid() or (not p_for_save and public.can_do(e.form_code, 'approve'));
  end if;
  if not public.can_do(e.form_code, 'approve') then return false; end if;
  select exists (select 1 from public.user_roles ur join public.roles r on r.code = ur.role_code where ur.user_id = auth.uid() and r.allow_self_approve) into self_ok;
  return e.created_by <> auth.uid() or self_ok;
end $$;

create or replace function public.count_save(p_entry uuid, p_section text, p_counted jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; tot numeric; inp jsonb; ex numeric; df numeric; sid text; c public.entry_counts; peek public.entry_count_peeks;
begin
  if p_section not in ('drawer', 'hub') then raise exception 'bad_section'; end if;
  select * into e from public.entries where id = p_entry for update;
  if not found then raise exception 'entry not found'; end if;
  if e.form_code <> public._count_sec18(p_section) then raise exception 'bad_section'; end if;
  if not public._count_can18(e, p_section, true) then raise exception 'not allowed'; end if;
  if (p_section = 'drawer' and e.status <> 'draft') or (p_section = 'hub' and e.status <> 'submitted') then raise exception 'count_not_open'; end if;
  tot := public._den_total18(p_counted, true);
  select * into c from public.entry_counts where entry_id = p_entry and section = p_section;
  if found then
    -- a retry of the same count (lost answer) gets the saved result; a different figure is refused: the count never changes
    if c.counted = tot and c.counted_by = auth.uid() then
      return jsonb_build_object('section', p_section, 'counted', c.counted, 'expected', c.expected, 'diff', c.diff, 'match', c.diff = 0, 'already', true);
    end if;
    raise exception 'count_already_saved';
  end if;
  if p_section = 'drawer' and (e.data ? 'cash_count') and public._den_total18(e.data -> 'cash_count', false) <> tot then raise exception 'count_mismatch'; end if;
  if p_section = 'hub' and (e.check_data ? 'rcount') and public._den_total18(e.check_data -> 'rcount', false) <> tot then raise exception 'count_mismatch'; end if;
  inp := public._count_inputs18(e, p_section);
  ex := public._count_expected18(inp, p_section);
  df := tot - ex;
  select staff_id into sid from public.profiles where id = auth.uid();
  select * into peek from public.entry_count_peeks where entry_id = p_entry and section = p_section and seen_by = auth.uid() order by id limit 1;
  insert into public.entry_counts (entry_id, section, counted_detail, counted, expected, diff, inputs_hash, counted_by, counted_staff, counted_at, expected_seen_by, expected_seen_at, seen_before_count)
    values (p_entry, p_section, coalesce(p_counted, 'null'::jsonb), tot, ex, df, md5(inp::text), auth.uid(), sid, now(),
            coalesce(peek.seen_by, auth.uid()), coalesce(peek.seen_at, now()),
            exists (select 1 from public.entry_count_peeks where entry_id = p_entry and section = p_section));
  update public.entries set check_data = check_data where id = p_entry;          -- the guard trigger mirrors the result into check_data.blind
  return jsonb_build_object('section', p_section, 'counted', tot, 'expected', ex, 'diff', df, 'match', df = 0);
end $$;

-- the expected figure BEFORE the count: only the owner (rule owner_sees_expected_first) or a holder of see_expected; every look is logged
create or replace function public.count_peek(p_entry uuid, p_section text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; c public.entry_counts; inp jsonb; sid text;
begin
  if p_section not in ('drawer', 'hub') then raise exception 'bad_section'; end if;
  select * into e from public.entries where id = p_entry;
  if not found then raise exception 'entry not found'; end if;
  if e.form_code <> public._count_sec18(p_section) then raise exception 'bad_section'; end if;
  if not public._count_can18(e, p_section, false) then raise exception 'not allowed'; end if;
  select * into c from public.entry_counts where entry_id = p_entry and section = p_section;
  if found then return jsonb_build_object('saved', true, 'counted', c.counted, 'expected', c.expected, 'diff', c.diff); end if;
  if public.blind_active(e.form_code, e.location_id) then
    if public.is_owner() and not public.rule_on('owner_sees_expected_first') and not exists (
         select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = 'see_expected' and (g.valid_until is null or g.valid_until > now()) and (g.location_id is null or g.location_id = e.location_id)) then
      raise exception 'not allowed';
    end if;
    if not public.has_grant('see_expected', e.location_id) then raise exception 'not allowed'; end if;
    select staff_id into sid from public.profiles where id = auth.uid();
    insert into public.entry_count_peeks (entry_id, section, seen_by, seen_staff) values (p_entry, p_section, auth.uid(), sid);
  end if;
  inp := public._count_inputs18(e, p_section);
  return jsonb_build_object('saved', false, 'expected', public._count_expected18(inp, p_section));
end $$;

-- the saved count of an entry (no expected figure unless it is saved)
create or replace function public.count_get(p_entry uuid, p_section text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e public.entries; c public.entry_counts;
begin
  select * into e from public.entries where id = p_entry;
  if not found or not public.is_active() or not public.can_loc(e.location_id) then raise exception 'not allowed'; end if;
  select * into c from public.entry_counts where entry_id = p_entry and section = p_section;
  if not found then return jsonb_build_object('saved', false, 'blind', public.blind_active(e.form_code, e.location_id)); end if;
  return jsonb_build_object('saved', true, 'counted', c.counted, 'expected', c.expected, 'diff', c.diff, 'match', c.diff = 0, 'counted_at', c.counted_at, 'counted_staff', c.counted_staff,
    'seen_before_count', c.seen_before_count, 'inputs_changed', md5(public._count_inputs18(e, p_section)::text) is distinct from c.inputs_hash);
end $$;

-- guard on entries: a saved count cannot be changed through the entry, the result is mirrored into check_data.blind
create or replace function public._entries_blind_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare r public.entry_counts;
begin
  for r in select * from public.entry_counts where entry_id = new.id loop
    if r.section = 'drawer' and (new.data is distinct from old.data) and public._den_total18(new.data -> 'cash_count', false) <> r.counted then raise exception 'count_locked'; end if;
    if r.section = 'hub' and (new.check_data ? 'rcount' or (new.status in ('approved', 'rejected') and old.status = 'submitted'))
       and public._den_total18(new.check_data -> 'rcount', false) <> r.counted then raise exception 'count_locked'; end if;
  end loop;
  if exists (select 1 from public.entry_counts where entry_id = new.id) then
    new.check_data := coalesce(new.check_data, '{}'::jsonb) || jsonb_build_object('blind', (
      select jsonb_object_agg(section, jsonb_build_object('counted', counted, 'expected', expected, 'diff', diff, 'match', diff = 0, 'counted_at', counted_at))
      from public.entry_counts where entry_id = new.id));
  end if;
  return new;
end $$;
drop trigger if exists entries_blind_guard on public.entries;
create trigger entries_blind_guard before update on public.entries for each row execute function public._entries_blind_guard();

-- ---------- (4) PIN signatures ----------
create table if not exists public.entry_signatures (
  entry_id uuid not null references public.entries(id),
  role text not null check (role in ('witness', 'second_sig', 'hub_pair')),
  signer_id uuid not null, signer_staff text,
  signed_at timestamptz not null default now(),
  primary key (entry_id, role),
  unique (entry_id, signer_id)
);
drop trigger if exists entry_signatures_no_change on public.entry_signatures;
create trigger entry_signatures_no_change before update or delete on public.entry_signatures for each row execute function public._append_only18();
drop trigger if exists entry_signatures_no_truncate on public.entry_signatures;
create trigger entry_signatures_no_truncate before truncate on public.entry_signatures for each statement execute function public._append_only18();
alter table public.entry_signatures enable always trigger entry_signatures_no_truncate;
alter table public.entry_signatures enable row level security;
drop policy if exists entry_signatures_read on public.entry_signatures;
create policy entry_signatures_read on public.entry_signatures for select to authenticated using (exists (select 1 from public.entries e where e.id = entry_id));
revoke all on public.entry_signatures from public, anon, authenticated;
grant select on public.entry_signatures to authenticated;
drop trigger if exists audit_entry_signatures on public.entry_signatures;
create trigger audit_entry_signatures after insert on public.entry_signatures for each row execute function public.log_change('entry_id,role');

-- called by the SECOND person's own session (their PIN was checked by Supabase Auth in the browser): auth.uid() is the signer
create or replace function public.sign_entry(p_entry uuid, p_role text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; sid text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_role not in ('witness', 'second_sig', 'hub_pair') then raise exception 'bad_role'; end if;
  select * into e from public.entries where id = p_entry for update;
  if not found then raise exception 'entry not found'; end if;
  if (p_role in ('witness', 'second_sig') and e.form_code <> '14-1') or (p_role = 'hub_pair' and e.form_code <> '10-1') then raise exception 'bad_role'; end if;
  if not public.pin_sig_active(e.form_code) then raise exception 'pin_signature_off'; end if;
  if e.status not in ('draft', 'submitted') then raise exception 'entry is locked'; end if;
  if e.created_by = auth.uid() then raise exception 'signer_is_maker'; end if;
  if not public.can_loc(e.location_id) then raise exception 'not allowed for this location'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if exists (select 1 from public.login_failures f where f.staff_id = sid and f.locked and (f.locked_until is null or f.locked_until > now())) then raise exception 'signer_locked'; end if;
  if exists (select 1 from public.entry_signatures where entry_id = p_entry and signer_id = auth.uid()) then raise exception 'signer_already_signed'; end if;
  if exists (select 1 from public.entry_signatures where entry_id = p_entry and role = p_role) then raise exception 'role_already_signed'; end if;
  insert into public.entry_signatures (entry_id, role, signer_id, signer_staff) values (p_entry, p_role, auth.uid(), sid);
  return jsonb_build_object('entry', p_entry, 'role', p_role, 'signer_staff', sid);
end $$;

-- a draft cannot be submitted without the PIN signatures once they are switched on for the form
create or replace function public._entries_sig_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare roles text[]; r text; s text;
begin
  if not (old.status = 'draft' and new.status = 'submitted') then return new; end if;
  if not public.pin_sig_active(new.form_code) then return new; end if;
  roles := case new.form_code when '14-1' then array['witness', 'second_sig'] else array['hub_pair'] end;
  foreach r in array roles loop
    select signer_staff into s from public.entry_signatures where entry_id = new.id and role = r;
    if s is null then raise exception 'pin_signature_required:%', r; end if;
    if r = 'witness' and coalesce(new.data ->> 'witness', '') <> s then raise exception 'signature_mismatch:witness'; end if;
    if r = 'second_sig' and coalesce(new.data ->> 'second_sig', '') <> s then raise exception 'signature_mismatch:second_sig'; end if;
  end loop;
  return new;
end $$;
drop trigger if exists entries_sig_guard on public.entries;
create trigger entries_sig_guard before update on public.entries for each row execute function public._entries_sig_guard();

-- ---------- (5) rights ----------
revoke execute on function public.blind_active(text, int), public.pin_sig_active(text), public.blind_cfg_set(text, int, boolean), public.pin_sig_cfg_set(text, boolean),
  public.count_save(uuid, text, jsonb), public.count_peek(uuid, text), public.count_get(uuid, text), public.sign_entry(uuid, text),
  public._n18(jsonb, text), public._den_total18(jsonb, boolean), public._count_inputs18(public.entries, text), public._count_expected18(jsonb, text),
  public._count_sec18(text), public._count_can18(public.entries, text, boolean), public._entries_blind_guard(), public._entries_sig_guard(), public._append_only18() from public, anon;
grant execute on function public.blind_active(text, int), public.pin_sig_active(text), public.blind_cfg_set(text, int, boolean), public.pin_sig_cfg_set(text, boolean),
  public.count_save(uuid, text, jsonb), public.count_peek(uuid, text), public.count_get(uuid, text), public.sign_entry(uuid, text) to authenticated;
-- the helpers stay internal (they are called inside security definer functions); authenticated needs no direct access
revoke execute on function public._n18(jsonb, text), public._den_total18(jsonb, boolean), public._count_inputs18(public.entries, text), public._count_expected18(jsonb, text),
  public._count_sec18(text), public._count_can18(public.entries, text, boolean), public._entries_blind_guard(), public._entries_sig_guard(), public._append_only18() from authenticated;
