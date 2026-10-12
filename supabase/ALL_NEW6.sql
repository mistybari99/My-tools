-- ALL_NEW6 = phase18..21 (blind count & PIN signatures, recipes/BOM, forms-stock links & brand P&L, reports). Safe to re-run.

-- ===== phase18 =====
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
 ('pin_signature_owner_override', 'entries', 'switch', 'false', null, null, null, null, 'পিন স্বাক্ষর ছাড়া জমা: মালিকের ছাড় (হলুদ এক্সেপশনসহ)', 'PIN signature ছাড়া submit: owner override (yellow exception সহ)', 'Owner may submit without the PIN signatures (yellow exception)',
   'চালু থাকলে শুধু মালিক স্বাক্ষর ছাড়া জমা দিতে পারবেন; হলুদ এক্সেপশন তৈরি হয়', 'চালু থাকলে শুধু owner signature ছাড়া submit করতে পারবেন; yellow exception হয়', 'When on only the owner may submit without signatures; a yellow exception is raised', 97),
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
-- the maker of a draft must not learn expected / diff from the server while blind is on (only an approver, or a see_expected holder, does)
create or replace function public._count_hide18(e public.entries) returns boolean
language sql stable security definer set search_path = public as $$
  select public.blind_active(e.form_code, e.location_id) and e.status = 'draft' and e.created_by = auth.uid() and not public.has_grant('see_expected', e.location_id);
$$;
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
  using (exists (select 1 from public.entries e where e.id = entry_id and not public._count_hide18(e)));      -- rows exist only AFTER the count; the maker of a blind draft does not read expected / diff
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


-- counted but never submitted (throw-away drafts): an owner exception once the business day is over (no invented time limit)
create or replace function public.count_unsubmitted_scan() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
    select e.id, e.form_code, e.location_id, e.entry_date, 'count_unsubmitted', 'red', null,
           jsonb_build_object('bn', 'গণনা সেভ হয়েছে কিন্তু শিট জমা হয়নি', 'en', 'Count saved but the sheet was never submitted')
    from public.entry_counts c join public.entries e on e.id = c.entry_id
    where c.section = 'drawer' and e.status = 'draft' and e.entry_date < (now() at time zone 'Asia/Dhaka')::date
      and not exists (select 1 from public.exceptions x where x.entry_id = e.id and x.flag_code = 'count_unsubmitted');
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.count_save(p_entry uuid, p_section text, p_counted jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; tot numeric; inp jsonb; ex numeric; df numeric; sid text; c public.entry_counts; peek public.entry_count_peeks; hide boolean;
begin
  if p_section not in ('drawer', 'hub') then raise exception 'bad_section'; end if;
  perform public.count_unsubmitted_scan();
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
      if public._count_hide18(e) then return jsonb_build_object('section', p_section, 'saved', true, 'counted', c.counted, 'hidden', true, 'already', true); end if;
      return jsonb_build_object('section', p_section, 'counted', c.counted, 'expected', c.expected, 'diff', c.diff, 'match', c.diff = 0, 'already', true);
    end if;
    raise exception 'count_already_saved';
  end if;
  if p_section = 'drawer' then
    if not (e.data ? 'cash_count') then raise exception 'count_missing'; end if;
    if public._den_total18(e.data -> 'cash_count', false) <> tot then raise exception 'count_mismatch'; end if;
    -- one counted open draft per person, place and day: no throw-away drafts to read the expected figure
    if exists (select 1 from public.entries x join public.entry_counts k on k.entry_id = x.id and k.section = 'drawer'
               where x.form_code = e.form_code and x.location_id = e.location_id and x.entry_date = e.entry_date and x.created_by = e.created_by and x.status = 'draft' and x.id <> e.id) then
      raise exception 'count_draft_limit';
    end if;
  end if;
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
  update public.entries set check_data = check_data where id = p_entry;          -- the guard trigger mirrors the result into check_data.blind (not while a draft)
  if public._count_hide18(e) then return jsonb_build_object('section', p_section, 'saved', true, 'counted', tot, 'hidden', true); end if;
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
  if found then
    if public._count_hide18(e) then return jsonb_build_object('saved', true, 'counted', c.counted, 'hidden', true); end if;
    return jsonb_build_object('saved', true, 'counted', c.counted, 'expected', c.expected, 'diff', c.diff);
  end if;
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
  if public._count_hide18(e) then return jsonb_build_object('saved', true, 'counted', c.counted, 'hidden', true, 'counted_at', c.counted_at); end if;
  return jsonb_build_object('saved', true, 'counted', c.counted, 'expected', c.expected, 'diff', c.diff, 'match', c.diff = 0, 'counted_at', c.counted_at, 'counted_staff', c.counted_staff,
    'seen_before_count', c.seen_before_count, 'inputs_changed', md5(public._count_inputs18(e, p_section)::text) is distinct from c.inputs_hash);
end $$;

-- guard on entries: a saved count cannot be changed through the entry, the result is mirrored into check_data.blind once the sheet is submitted,
-- and the server adds the cash short/over flag at submit (the maker never sees expected / diff before that)
create or replace function public._entries_blind_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare r public.entry_counts; tol numeric; tj jsonb; lvl text;
begin
  for r in select * from public.entry_counts where entry_id = new.id loop
    if r.section = 'drawer' then
      if new.data is distinct from old.data and (new.data ? 'cash_count') and public._den_total18(new.data -> 'cash_count', false) <> r.counted then raise exception 'count_locked'; end if;
      if old.status = 'draft' and new.status = 'submitted' then
        if not (new.data ? 'cash_count') or public._den_total18(new.data -> 'cash_count', false) <> r.counted then raise exception 'count_locked'; end if;
        if r.diff <> 0 and not exists (select 1 from jsonb_array_elements(new.flags) f where f ->> 'code' = 'cash_short_over') then
          begin tj := public.get_limit(new.location_id, 'cash_tol', new.entry_date); exception when others then tj := null; end;
          tol := case when tj is not null and jsonb_typeof(tj) = 'number' then (tj #>> '{}')::numeric end;
          lvl := case when tol is not null and abs(r.diff) <= tol then 'yellow' else 'red' end;
          new.flags := new.flags || jsonb_build_array(jsonb_build_object('code', 'cash_short_over', 'level', lvl, 'amount', r.diff, 'src', 'system',
            'text', case when r.diff < 0 then jsonb_build_object('bn', 'ক্যাশ কম', 'en', 'Cash short') else jsonb_build_object('bn', 'ক্যাশ বেশি', 'en', 'Cash over') end));
        end if;
      end if;
    elsif new.check_data ? 'rcount' and public._den_total18(new.check_data -> 'rcount', false) <> r.counted then raise exception 'count_locked';
    end if;
  end loop;
  if new.status = 'draft' then
    new.check_data := coalesce(new.check_data, '{}'::jsonb) - 'blind';
  elsif exists (select 1 from public.entry_counts where entry_id = new.id) then
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
  id bigserial primary key,
  entry_id uuid not null references public.entries(id),
  role text not null check (role in ('witness', 'second_sig', 'hub_pair')),
  signer_id uuid not null, signer_staff text,
  signed_at timestamptz not null default now(),
  data_hash text not null,                         -- md5 of the sheet (without the signer names) when it was signed: a later change makes the signature stale
  unique (entry_id, role, data_hash),
  unique (entry_id, signer_id, data_hash)
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

create or replace function public._sig_hash18(d jsonb) returns text
language sql immutable as $$ select md5(((coalesce(d, '{}'::jsonb)) - 'witness' - 'second_sig' - 'pair_by')::text); $$;
create or replace function public._addflag18(fl jsonb, p_code text, p_level text, p_bn text, p_en text) returns jsonb
language sql immutable as $$ select coalesce(fl, '[]'::jsonb) || jsonb_build_array(jsonb_build_object('code', p_code, 'level', p_level, 'src', 'system', 'text', jsonb_build_object('bn', p_bn, 'en', p_en))); $$;

-- called by the SECOND person's own session (their PIN was checked by Supabase Auth in the browser): auth.uid() is the signer
create or replace function public.sign_entry(p_entry uuid, p_role text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; sid text; iat numeric; h text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into e from public.entries where id = p_entry for update;
  -- place first, one text for every refusal of access (no hint whether the entry exists)
  if not found or not public.can_loc(e.location_id) or not (public.can_do(e.form_code, 'enter') or public.can_do(e.form_code, 'approve')) then raise exception 'not allowed'; end if;
  if p_role not in ('witness', 'second_sig', 'hub_pair') then raise exception 'bad_role'; end if;
  if (p_role in ('witness', 'second_sig') and e.form_code <> '14-1') or (p_role = 'hub_pair' and e.form_code <> '10-1') then raise exception 'bad_role'; end if;
  if not public.pin_sig_active(e.form_code) then raise exception 'pin_signature_off'; end if;
  if e.status not in ('draft', 'submitted') then raise exception 'entry is locked'; end if;
  if e.created_by = auth.uid() then raise exception 'signer_is_maker'; end if;
  -- a fresh sign-in just now (the browser signs the signer in on a second client): an old token cannot sign
  begin iat := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'iat', nullif(current_setting('request.jwt.claim.iat', true), ''))::numeric; exception when others then iat := null; end;
  if iat is null or iat < extract(epoch from now()) - 120 then raise exception 'login_not_fresh'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if exists (select 1 from public.login_failures f where f.staff_id = sid and f.locked and (f.locked_until is null or f.locked_until > now())) then raise exception 'signer_locked'; end if;
  h := public._sig_hash18(e.data);
  if exists (select 1 from public.entry_signatures where entry_id = p_entry and signer_id = auth.uid() and data_hash = h) then raise exception 'signer_already_signed'; end if;
  if exists (select 1 from public.entry_signatures where entry_id = p_entry and role = p_role and data_hash = h) then raise exception 'role_already_signed'; end if;
  insert into public.entry_signatures (entry_id, role, signer_id, signer_staff, data_hash) values (p_entry, p_role, auth.uid(), sid, h);
  return jsonb_build_object('entry', p_entry, 'role', p_role, 'signer_staff', sid);
end $$;

-- a draft cannot be submitted without valid (not stale) PIN signatures once they are switched on for the form
create or replace function public._entries_sig_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare roles text[]; r text; s text; h text; missing text[] := '{}';
begin
  if not (old.status = 'draft' and new.status = 'submitted') then return new; end if;
  if not public.pin_sig_active(new.form_code) then return new; end if;
  roles := case new.form_code when '14-1' then array['witness', 'second_sig'] else array['hub_pair'] end;
  h := public._sig_hash18(new.data);
  foreach r in array roles loop
    select signer_staff into s from public.entry_signatures where entry_id = new.id and role = r and data_hash = h order by id desc limit 1;
    if s is null then
      missing := missing || r;
      continue;
    end if;
    if r = 'witness' and coalesce(new.data ->> 'witness', '') <> s then raise exception 'signature_mismatch:witness'; end if;
    if r = 'second_sig' and coalesce(new.data ->> 'second_sig', '') <> s then raise exception 'signature_mismatch:second_sig'; end if;
  end loop;
  if array_length(missing, 1) > 0 then
    if new.entered_later then
      new.flags := public._addflag18(new.flags, 'unsigned_entered_later', 'yellow', 'কাগজ থেকে পরে তোলা — পিন স্বাক্ষর নেই', 'Entered later from paper - no PIN signature');
    elsif public.is_owner() and public.rule_on('pin_signature_owner_override') then
      new.flags := public._addflag18(new.flags, 'unsigned_owner_override', 'yellow', 'মালিকের ছাড়ে পিন স্বাক্ষর ছাড়া জমা', 'Submitted without PIN signatures by the owner override');
    else
      r := missing[1];
      if exists (select 1 from public.entry_signatures where entry_id = new.id and role = r) then raise exception 'pin_signature_stale:%', r; end if;
      raise exception 'pin_signature_required:%', r;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists entries_sig_guard on public.entries;
create trigger entries_sig_guard before update on public.entries for each row execute function public._entries_sig_guard();


-- submit_entry (phase17 body) with ONE change: the exceptions are made from the flags AFTER the update, so flags the server adds at submit
-- (cash_short_over from the saved blind count, unsigned_entered_later, unsigned_owner_override) become exceptions too
create or replace function public.submit_entry(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; f public.forms; fl jsonb; blocked text[] := '{}'; auto boolean;
begin
  select * into e from public.entries where id = p_id for update;
  if not found then raise exception 'entry not found'; end if;
  if e.status <> 'draft' then raise exception 'entry is locked'; end if;
  if e.created_by <> auth.uid() and not public.is_owner() then raise exception 'only the maker can submit'; end if;
  if not public.can_do(e.form_code, 'enter') or not public.can_loc(e.location_id) then raise exception 'not allowed'; end if;
  if public.rollout_mode(e.form_code, e.location_id) = 'paper' and public.rule_on('rollout_enforce') and not e.entered_later then
    raise exception 'rollout_paper:%', e.form_code;
  end if;
  select * into f from public.forms where code = e.form_code;
  if f.red_block then
    for fl in select * from jsonb_array_elements(e.flags) loop
      if fl->>'level' = 'red' and fl->>'code' <> 'entered_later_old' and not exists (select 1 from public.release_requests r
           where r.entry_id = e.id and r.flag_code = fl->>'code' and r.status = 'approved'
             and r.flag_amount is not distinct from nullif(fl->>'amount','')::numeric) then
        blocked := blocked || (fl->>'code');
      end if;
    end loop;
    if array_length(blocked, 1) > 0 then raise exception 'red_blocked:%', array_to_string(blocked, ','); end if;
  end if;
  update public.entries set status = 'submitted', submitted_at = now(), updated_at = now() where id = p_id;
  select * into e from public.entries where id = p_id;
  select coalesce((select (value #>> '{}')::boolean from public.settings where key = 'auto_exceptions'), true) into auto;
  delete from public.exceptions where entry_id = e.id and status = 'open' and flag_code <> 'count_unsubmitted';
  if auto then
    insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      select e.id, e.form_code, e.location_id, e.entry_date, x->>'code', x->>'level', nullif(x->>'amount','')::numeric, x->'text'
      from jsonb_array_elements(e.flags) x;
  end if;
  return jsonb_build_object('status', 'submitted');
end $$;
revoke all on function public.submit_entry(uuid) from public, anon;
grant execute on function public.submit_entry(uuid) to authenticated;

-- ---------- (5) rights ----------
revoke execute on function public.blind_active(text, int), public.pin_sig_active(text), public.blind_cfg_set(text, int, boolean), public.pin_sig_cfg_set(text, boolean),
  public.count_save(uuid, text, jsonb), public.count_peek(uuid, text), public.count_get(uuid, text), public.sign_entry(uuid, text), public.count_unsubmitted_scan(), public._count_hide18(public.entries), public._sig_hash18(jsonb), public._addflag18(jsonb, text, text, text, text),
  public._n18(jsonb, text), public._den_total18(jsonb, boolean), public._count_inputs18(public.entries, text), public._count_expected18(jsonb, text),
  public._count_sec18(text), public._count_can18(public.entries, text, boolean), public._entries_blind_guard(), public._entries_sig_guard(), public._append_only18() from public, anon;
grant execute on function public.blind_active(text, int), public.pin_sig_active(text), public.blind_cfg_set(text, int, boolean), public.pin_sig_cfg_set(text, boolean),
  public.count_save(uuid, text, jsonb), public.count_peek(uuid, text), public.count_get(uuid, text), public.sign_entry(uuid, text), public.count_unsubmitted_scan(), public._count_hide18(public.entries) to authenticated;   -- _count_hide18 is used by the entry_counts read policy
-- the helpers stay internal (they are called inside security definer functions); authenticated needs no direct access
revoke execute on function public._n18(jsonb, text), public._den_total18(jsonb, boolean), public._count_inputs18(public.entries, text), public._count_expected18(jsonb, text),
  public._count_sec18(text), public._count_can18(public.entries, text, boolean), public._entries_blind_guard(), public._entries_sig_guard(), public._append_only18() from authenticated;

-- ===== phase19 =====
-- Phase 19 (W6): recipes / BOM, packaging rule, production that consumes raw material.
--   Additive and idempotent (paste whole in the Supabase SQL editor; run twice is fine). Needs phase8..phase14 (stock ledger, items, item types). phase15..18 are not required.
--   * recipes (a version per finished good) + recipe_lines (ingredients: raw_material / packaging / resale items, qty, unit, waste % - empty waste = "Data needed")
--     A version that has been used by a production run is immutable (a change is a NEW version). Nothing is deleted: active flag. No cost columns anywhere.
--   * recipe_cost(recipe, loc): cost of one batch from the stock average cost - only for the owner / ITEM_COST / view_cost people.
--   * product_packaging (packaging per product, applies to sale or production) + setting packaging_consume_on (off | sale | production, default off).
--       sale       -> an AFTER INSERT trigger on sales (separate from the stock trigger, record_sale2 is NOT changed) takes the packaging out of the ledger
--                     with the SOFT mode (a sale is never blocked); if one packaging line cannot be posted the sale still goes through and the owner gets a yellow
--                     line `packaging_not_consumed`. A void gives the packaging back.
--       production -> production_post takes the packaging out in the same transaction as the ingredients.
--   * production_post(loc, recipe, batches, client, made_at, note): ONE transaction: ledger OUT per ingredient (qty x batches x (1 + waste%)) at the weighted average
--     cost, ledger IN of the finished good (yield x batches) with batch + expiry from shelf_life_for(), idempotent by client id, period lock, can_loc, grant
--     stock_production (+ its emergency rule em_stock_production), shortage refused (setting production_short_mode) with the full list of what is short.
--   * production_preview / production_can_make for the production sheet and the "what can I make now" view (no costs).
--   * settings: packaging_consume_on, production_requires_recipe (default OFF: the old stock_production_in works as before), production_short_mode,
--     recipe_waste_required (default OFF: an empty waste % is treated as 0 and the owner gets a yellow line). Grant recipe_manage (delegable).
--   The old stock_production_in is re-created with the same body plus one switch check (production_requires_recipe).

-- ---------- settings and grant ----------
insert into public.rules (key, module, kind, default_value, choices, min_value, max_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('packaging_consume_on', 'stock', 'choice', '"off"', '["off","sale","production"]', null, null,
  'প্যাকেজিং কখন স্টক থেকে কমবে: বন্ধ / বিক্রিতে / উৎপাদনে', 'Packaging কখন stock থেকে কমবে: off / sale / production', 'When packaging leaves the stock: off, with a sale, or with production',
  'Off = packaging is not taken out automatically. Uses the per-product packaging list. A sale is never blocked by packaging.', 190),
 ('production_requires_recipe', 'stock', 'switch', 'false', null, null, null,
  'উৎপাদন শুধু রেসিপি দিয়েই (পুরনো সরাসরি "উৎপাদিত মাল তোলা" বন্ধ)', 'Production শুধু recipe দিয়েই (পুরনো সরাসরি "Production in" বন্ধ)', 'Production only through a recipe (the old direct "Production in" is refused)',
  'Off = the direct production-in works as before. On = every production must use a recipe so the raw material is taken out.', 191),
 ('production_short_mode', 'stock', 'choice', '"refuse"', '["refuse","follow_stock_rule"]', null, null,
  'কাঁচামাল কম থাকলে: আটকানো / স্টকের সাধারণ নিয়ম', 'Raw material কম থাকলে: refuse / stock এর সাধারণ rule', 'When raw material is short: refuse, or follow the general stock rule',
  'refuse = the production is refused (unless stock_negative_mode is allow, or the person may sell below zero). follow_stock_rule = same as selling (warn / block / allow).', 192),
 ('recipe_waste_required', 'stock', 'switch', 'false', null, null, null,
  'রেসিপিতে অপচয় % না থাকলে উৎপাদন আটকানো', 'Recipe এ waste % না থাকলে production আটকানো', 'Refuse production when a recipe line has no waste %',
  'Off = an empty waste % counts as 0 and the owner gets a yellow line. The owner sets the real waste %; nothing is guessed.', 193)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('recipe_manage', 'master', 69, 'রেসিপি ও প্যাকেজিং নিয়ম তৈরি / বদল', 'Recipe ও packaging rule তৈরি / বদল', 'Create and change recipes and packaging rules', 'window', null)
on conflict (grant_code) do nothing;

-- ---------- tables ----------
create table if not exists public.recipes (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items(id),
  version int not null check (version >= 1),
  yield_qty numeric not null check (yield_qty > 0 and yield_qty < 1000000000),
  yield_unit text,                                           -- null = the item base unit
  active boolean not null default true,
  note text,
  used_at timestamptz,                                       -- first production run: from then on the version is frozen
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(),
  unique (item_id, version)
);
create index if not exists recipes_item on public.recipes (item_id, active);
create table if not exists public.recipe_lines (
  id bigserial primary key,
  recipe_id uuid not null references public.recipes(id),
  ingredient_item_id uuid not null references public.items(id),
  qty numeric not null check (qty > 0 and qty < 1000000000),
  unit text,                                                 -- null = the ingredient base unit
  waste_pct numeric check (waste_pct is null or (waste_pct >= 0 and waste_pct <= 100)),     -- null = Data needed
  note text,
  sort int not null default 0,
  unique (recipe_id, ingredient_item_id)
);
alter table public.recipe_lines add column if not exists active boolean not null default true;
alter table public.recipe_lines drop constraint if exists recipe_lines_recipe_id_ingredient_item_id_key;
create unique index if not exists recipe_lines_one_active on public.recipe_lines (recipe_id, ingredient_item_id) where active;
create table if not exists public.product_packaging (
  id bigserial primary key,
  product_item_id uuid not null references public.items(id),
  packaging_item_id uuid not null references public.items(id),
  qty_per_unit numeric not null check (qty_per_unit > 0 and qty_per_unit < 1000000),     -- packaging base units per ONE base unit of the product
  applies_to text not null default 'sale' check (applies_to in ('sale', 'production')),
  active boolean not null default true,
  note text,
  updated_by uuid, updated_at timestamptz not null default now(),
  unique (product_item_id, packaging_item_id, applies_to)
);
create table if not exists public.production_runs (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  location_id int not null references public.locations(id),
  recipe_id uuid not null references public.recipes(id),
  item_id uuid not null references public.items(id),
  batches numeric not null check (batches > 0),
  made_at timestamptz not null,
  yield_base numeric not null,
  ledger_in_id bigint, batch_id bigint,
  waste_missing int not null default 0,
  cost_complete boolean,
  note text,
  created_by uuid, created_at timestamptz not null default now()
);
create index if not exists production_runs_loc on public.production_runs (location_id, made_at);

-- ---------- helpers ----------
create or replace function public._recipe_mgr() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('recipe_manage'));
$$;
create or replace function public._recipe_read() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('recipe_manage') or public.has_grant('stock_production') or public.has_grant('stock_issue')
    or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code in ('recipe_manage', 'stock_production', 'stock_issue') and (g.valid_until is null or g.valid_until > now())));
$$;
create or replace function public._recipe_cost_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.can_do('ITEM_COST', 'view') or public.has_grant('view_cost')
    or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = 'view_cost' and (g.valid_until is null or g.valid_until > now())));
$$;

-- immutability: lines and the yield of a used version never change; a used version is never removed
create or replace function public._recipe_frozen() returns trigger language plpgsql security definer set search_path = public as $$
declare rid uuid; used timestamptz;
begin
  if tg_table_name = 'recipes' then
    if tg_op = 'DELETE' then
      if old.used_at is not null then raise exception 'recipe_used'; end if;
      raise exception 'no_delete';
    end if;
    if tg_op = 'UPDATE' and old.used_at is not null and (new.item_id is distinct from old.item_id or new.version is distinct from old.version
        or new.yield_qty is distinct from old.yield_qty or new.yield_unit is distinct from old.yield_unit) then raise exception 'recipe_used'; end if;
    return new;
  end if;
  rid := case when tg_op = 'DELETE' then old.recipe_id else new.recipe_id end;
  select used_at into used from public.recipes where id = rid;
  if used is not null then raise exception 'recipe_used'; end if;
  if tg_op = 'DELETE' then raise exception 'no_delete'; end if;
  if tg_op = 'UPDATE' and new.recipe_id is distinct from old.recipe_id then raise exception 'recipe_used'; end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;
drop trigger if exists recipes_frozen on public.recipes;
create trigger recipes_frozen before update or delete on public.recipes for each row execute function public._recipe_frozen();
drop trigger if exists recipe_lines_frozen on public.recipe_lines;
create trigger recipe_lines_frozen before insert or update or delete on public.recipe_lines for each row execute function public._recipe_frozen();

drop trigger if exists audit_recipes on public.recipes;
create trigger audit_recipes after insert or update on public.recipes for each row execute function public.log_change('id');
drop trigger if exists audit_recipe_lines on public.recipe_lines;
create trigger audit_recipe_lines after insert or update or delete on public.recipe_lines for each row execute function public.log_change('id');
drop trigger if exists audit_product_packaging on public.product_packaging;
create trigger audit_product_packaging after insert or update on public.product_packaging for each row execute function public.log_change('id');
drop trigger if exists audit_production_runs on public.production_runs;
create trigger audit_production_runs after insert on public.production_runs for each row execute function public.log_change('id');

-- ---------- RLS ----------
alter table public.recipes enable row level security;
alter table public.recipe_lines enable row level security;
alter table public.product_packaging enable row level security;
alter table public.production_runs enable row level security;
drop policy if exists recipes_read on public.recipes;
create policy recipes_read on public.recipes for select to authenticated using (public._recipe_read());
drop policy if exists recipe_lines_read on public.recipe_lines;
create policy recipe_lines_read on public.recipe_lines for select to authenticated using (public._recipe_read());
drop policy if exists product_packaging_read on public.product_packaging;
create policy product_packaging_read on public.product_packaging for select to authenticated using (public._recipe_read());
drop policy if exists production_runs_read on public.production_runs;
create policy production_runs_read on public.production_runs for select to authenticated using (public._recipe_read() and public.can_loc(location_id));
revoke all on public.recipes, public.recipe_lines, public.product_packaging, public.production_runs from anon, authenticated;
grant select on public.recipes, public.recipe_lines, public.product_packaging, public.production_runs to authenticated;
revoke all on sequence public.recipe_lines_id_seq, public.product_packaging_id_seq from anon, authenticated;

-- ---------- recipe writes ----------
create or replace function public._recipe_lines_ok(p_item uuid, p_lines jsonb) returns void language plpgsql security definer set search_path = public as $$
declare ln jsonb; ing public.items; q numeric; w numeric; seen uuid[] := '{}'; iid uuid;
begin
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'no_lines'; end if;
  if jsonb_array_length(p_lines) > 100 then raise exception 'too_many_lines'; end if;
  for ln in select x from jsonb_array_elements(p_lines) x loop
    iid := nullif(ln->>'ingredient_item_id', '')::uuid;
    select * into ing from public.items where id = iid;
    if not found then raise exception 'item_not_found'; end if;
    if iid = p_item then raise exception 'ingredient_is_product'; end if;
    if ing.item_type not in ('raw_material', 'packaging', 'resale') then raise exception 'bad_ingredient_type' using detail = ing.code; end if;
    if iid = any(seen) then raise exception 'dup_ingredient'; end if;
    seen := seen || iid;
    q := nullif(ln->>'qty', '')::numeric;
    if q is null or not (q > 0 and q < 1000000000) then raise exception 'bad_qty'; end if;
    w := nullif(ln->>'waste_pct', '')::numeric;
    if w is not null and not (w between 0 and 100) then raise exception 'bad_waste'; end if;
    if public._base_qty(iid, q, nullif(btrim(ln->>'unit'), '')) is null then raise exception 'unit_unknown' using detail = ing.code; end if;
  end loop;
end $$;

create or replace function public._recipe_put_lines(p_recipe uuid, p_lines jsonb) returns void language plpgsql security definer set search_path = public as $$
declare ln jsonb; n int := 0;
begin
  for ln in select x from jsonb_array_elements(p_lines) x loop
    n := n + 1;
    insert into public.recipe_lines (recipe_id, ingredient_item_id, qty, unit, waste_pct, note, sort)
      values (p_recipe, (ln->>'ingredient_item_id')::uuid, (ln->>'qty')::numeric, nullif(btrim(ln->>'unit'), ''), nullif(ln->>'waste_pct', '')::numeric, left(nullif(btrim(ln->>'note'), ''), 200), n);
  end loop;
end $$;

-- create a new version (p_id null) or edit a version that has never been used. p_lines = [{ingredient_item_id, qty, unit, waste_pct, note}]
create or replace function public.recipe_save(p_id uuid, p_item uuid, p_yield_qty numeric, p_yield_unit text, p_note text, p_lines jsonb, p_client uuid default null, p_retire_old boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it public.items; r public.recipes; v int; rid uuid; yu text := nullif(btrim(p_yield_unit), '');
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_yield_qty is null or not (p_yield_qty > 0 and p_yield_qty < 1000000000) then raise exception 'bad_qty'; end if;
  if p_id is not null then
    select * into r from public.recipes where id = p_id for update;
    if not found then raise exception 'recipe_not_found'; end if;
    if r.used_at is not null then raise exception 'recipe_used'; end if;
    it := (select i from public.items i where i.id = r.item_id);
  else
    if p_client is not null then
      select * into r from public.recipes where client_id = p_client;
      if found then
        if r.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
        return jsonb_build_object('dup', true, 'id', r.id, 'version', r.version);
      end if;
    end if;
    select * into it from public.items where id = p_item;
    if not found then raise exception 'item_not_found'; end if;
  end if;
  if it.item_type is distinct from 'finished_good' then raise exception 'bad_product_type'; end if;
  if public._base_qty(it.id, p_yield_qty, yu) is null then raise exception 'unit_unknown' using detail = it.code; end if;
  perform public._recipe_lines_ok(it.id, p_lines);
  if p_id is null then
    select coalesce(max(version), 0) + 1 into v from public.recipes where item_id = it.id;
    insert into public.recipes (item_id, version, yield_qty, yield_unit, active, note, client_id, created_by)
      values (it.id, v, p_yield_qty, yu, true, left(p_note, 300), p_client, auth.uid()) returning id into rid;
    if p_retire_old then update public.recipes set active = false where item_id = it.id and id <> rid and active; end if;
  else
    rid := p_id; v := r.version;
    update public.recipes set yield_qty = p_yield_qty, yield_unit = yu, note = left(p_note, 300) where id = rid;
    update public.recipe_lines set active = false where recipe_id = rid and active;      -- a draft only (never used): old lines are retired, never deleted; the trigger refuses this for a used version
  end if;
  perform public._recipe_put_lines(rid, p_lines);
  return jsonb_build_object('id', rid, 'version', v);
end $$;

-- copy a version: same item = next version (optionally retiring the source); another item = version 1 of that item
create or replace function public.recipe_copy(p_from uuid, p_item uuid default null, p_retire_old boolean default false, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.recipes; tgt public.items; v int; rid uuid; dup public.recipes;
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  select * into s from public.recipes where id = p_from;
  if not found then raise exception 'recipe_not_found'; end if;
  if p_client is not null then
    select * into dup from public.recipes where client_id = p_client;
    if found then
      if dup.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', dup.id, 'version', dup.version);
    end if;
  end if;
  select * into tgt from public.items where id = coalesce(p_item, s.item_id);
  if not found then raise exception 'item_not_found'; end if;
  if tgt.item_type is distinct from 'finished_good' then raise exception 'bad_product_type'; end if;
  if exists (select 1 from public.recipe_lines where recipe_id = p_from and active and ingredient_item_id = tgt.id) then raise exception 'ingredient_is_product'; end if;
  select coalesce(max(version), 0) + 1 into v from public.recipes where item_id = tgt.id;
  insert into public.recipes (item_id, version, yield_qty, yield_unit, active, note, client_id, created_by)
    values (tgt.id, v, s.yield_qty, case when tgt.id = s.item_id then s.yield_unit else null end, true, s.note, p_client, auth.uid()) returning id into rid;
  insert into public.recipe_lines (recipe_id, ingredient_item_id, qty, unit, waste_pct, note, sort)
    select rid, ingredient_item_id, qty, unit, waste_pct, note, sort from public.recipe_lines where recipe_id = p_from and active;
  if tgt.id <> s.item_id and public._base_qty(tgt.id, s.yield_qty, null) is null then raise exception 'unit_unknown'; end if;
  if p_retire_old and tgt.id = s.item_id then update public.recipes set active = false where id = p_from; end if;
  return jsonb_build_object('id', rid, 'version', v);
end $$;

create or replace function public.recipe_set_active(p_id uuid, p_active boolean) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  if p_active is null then raise exception 'bad_value'; end if;
  update public.recipes set active = p_active where id = p_id;
  if not found then raise exception 'recipe_not_found'; end if;
end $$;

-- packaging per product (one row per product x packaging x sale|production); inactive instead of delete
create or replace function public.packaging_set(p_product uuid, p_packaging uuid, p_qty numeric, p_applies text default 'sale', p_active boolean default true, p_note text default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare pr public.items; pk public.items; rid bigint;
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  if p_applies not in ('sale', 'production') then raise exception 'bad_value'; end if;
  if p_qty is null or not (p_qty > 0 and p_qty < 1000000) then raise exception 'bad_qty'; end if;
  select * into pr from public.items where id = p_product;
  select * into pk from public.items where id = p_packaging;
  if pr.id is null or pk.id is null then raise exception 'item_not_found'; end if;
  if pk.item_type is distinct from 'packaging' then raise exception 'bad_ingredient_type' using detail = pk.code; end if;
  if pr.item_type not in ('finished_good', 'resale') then raise exception 'bad_product_type'; end if;
  insert into public.product_packaging (product_item_id, packaging_item_id, qty_per_unit, applies_to, active, note, updated_by, updated_at)
    values (p_product, p_packaging, p_qty, p_applies, coalesce(p_active, true), left(p_note, 200), auth.uid(), now())
    on conflict (product_item_id, packaging_item_id, applies_to) do update
      set qty_per_unit = excluded.qty_per_unit, active = excluded.active, note = excluded.note, updated_by = auth.uid(), updated_at = now()
    returning id into rid;
  return rid;
end $$;

-- ---------- the consumption maths (internal; used by preview, can-make and post) ----------
-- one row per thing that leaves the stock for p_batches batches: the ingredients, plus the production-time packaging when the setting says so
create or replace function public._recipe_need(p_recipe uuid, p_batches numeric, p_loc int)
returns table (item_id uuid, kind text, need numeric, on_hand numeric, tracked boolean, unit_ok boolean, waste_missing boolean, code text, name_bn text, name_en text, base_unit text)
language plpgsql stable security definer set search_path = public as $$
declare r public.recipes; yb numeric;
begin
  select * into r from public.recipes where id = p_recipe;
  if not found then return; end if;
  yb := coalesce(public._base_qty(r.item_id, r.yield_qty, r.yield_unit), 0) * p_batches;
  return query
    select z.item_id, min(z.kind), sum(z.need), max(z.on_hand), bool_and(z.tracked), bool_and(z.unit_ok), bool_or(z.waste_missing), z.code, z.name_bn, z.name_en, z.base_unit
    from (
      select i.id as item_id, 'ingredient'::text as kind,
             round(public._base_qty(i.id, l.qty, l.unit) * p_batches * (1 + coalesce(l.waste_pct, 0) / 100), 4) as need,
             coalesce(b.qty, 0) as on_hand, i.tracked, public._base_qty(i.id, l.qty, l.unit) is not null as unit_ok, l.waste_pct is null as waste_missing,
             i.code, i.name_bn, i.name_en, public._item_base(i.id) as base_unit
        from public.recipe_lines l join public.items i on i.id = l.ingredient_item_id
        left join public.stock_balance b on b.item_id = i.id and b.location_id = p_loc
       where l.recipe_id = p_recipe and l.active
      union all
      select i.id, 'packaging'::text, round(pp.qty_per_unit * yb, 4), coalesce(b.qty, 0), i.tracked, true, false, i.code, i.name_bn, i.name_en, public._item_base(i.id)
        from public.product_packaging pp join public.items i on i.id = pp.packaging_item_id
        left join public.stock_balance b on b.item_id = i.id and b.location_id = p_loc
       where coalesce(public.rule_txt('packaging_consume_on'), 'off') = 'production' and pp.product_item_id = r.item_id and pp.active and pp.applies_to = 'production') z
    group by z.item_id, z.code, z.name_bn, z.name_en, z.base_unit;
end $$;

-- preview for the production sheet: what will be used, what is on hand, what is short. No costs.
create or replace function public.production_preview(p_loc int, p_recipe uuid, p_batches numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.recipes; it public.items; yb numeric; ls jsonb; sh jsonb; wm int;
begin
  if not public._recipe_read() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if p_batches is null or not (p_batches between 0.0001 and 100000) then raise exception 'bad_qty'; end if;
  select * into r from public.recipes where id = p_recipe;
  if not found then raise exception 'recipe_not_found'; end if;
  select * into it from public.items where id = r.item_id;
  yb := round(public._base_qty(r.item_id, r.yield_qty, r.yield_unit) * p_batches, 4);
  select coalesce(jsonb_agg(jsonb_build_object('item_id', n.item_id, 'kind', n.kind, 'code', n.code, 'name_bn', n.name_bn, 'name_en', n.name_en, 'need', n.need, 'on_hand', n.on_hand,
           'short', greatest(n.need - n.on_hand, 0), 'unit', n.base_unit, 'tracked', n.tracked, 'unit_ok', n.unit_ok, 'waste_missing', n.waste_missing) order by n.kind, n.code), '[]'::jsonb),
         coalesce(jsonb_agg(n.item_id) filter (where n.need > n.on_hand), '[]'::jsonb), count(*) filter (where n.waste_missing)
    into ls, sh, wm from public._recipe_need(p_recipe, p_batches, p_loc) n;
  return jsonb_build_object('recipe_id', r.id, 'item_id', r.item_id, 'version', r.version, 'active', r.active, 'batches', p_batches, 'yield_base', yb, 'yield_unit', public._item_base(r.item_id),
    'lines', ls, 'short_items', sh, 'waste_missing', wm,
    'can_make', (jsonb_array_length(sh) = 0 and not exists (select 1 from jsonb_array_elements(ls) x where (x->>'tracked')::boolean is not true or (x->>'unit_ok')::boolean is not true)),
    'tracked', it.tracked);
end $$;

-- "what can I make now" at one location: for every active recipe (newest active version per product) how many batches the stock allows
create or replace function public.production_can_make(p_loc int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.recipes; out jsonb := '[]'::jsonb; mx numeric; lim uuid; unk boolean; n record; per numeric; it public.items;
begin
  if not public._recipe_read() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  for r in select distinct on (item_id) * from public.recipes where active order by item_id, version desc loop
    select * into it from public.items where id = r.item_id;
    if not it.is_active then continue; end if;
    mx := null; lim := null; unk := not it.tracked;
    for n in select * from public._recipe_need(r.id, 1, p_loc) loop
      if not n.tracked or not n.unit_ok or n.need <= 0 then unk := true; continue; end if;
      per := n.on_hand / n.need;
      if mx is null or per < mx then mx := per; lim := n.item_id; end if;
    end loop;
    out := out || jsonb_build_object('recipe_id', r.id, 'item_id', r.item_id, 'version', r.version, 'code', it.code, 'name_bn', it.name_bn, 'name_en', it.name_en,
      'max_batches', case when mx is null then null else greatest(floor(mx * 10000) / 10000, 0) end, 'limiting_item_id', lim, 'unknown', unk,
      'yield_per_batch', public._base_qty(r.item_id, r.yield_qty, r.yield_unit), 'yield_unit', public._item_base(r.item_id));
  end loop;
  return out;
end $$;

-- cost of one batch from the average cost in stock (owner / ITEM_COST / view_cost only; unknown cost = null = Data needed)
create or replace function public.recipe_cost(p_recipe uuid, p_loc int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.recipes; ls jsonb := '[]'::jsonb; total numeric := 0; complete boolean := true; l record; need numeric; av numeric; yb numeric;
begin
  if p_loc is not null then
    if not (public._cost_ok(p_loc) and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;      -- same rule as the stock cost columns
  elsif not public._recipe_cost_ok() then raise exception 'not allowed'; end if;
  select * into r from public.recipes where id = p_recipe;
  if not found then raise exception 'recipe_not_found'; end if;
  for l in select x.*, i.code, i.name_bn, i.name_en from public.recipe_lines x join public.items i on i.id = x.ingredient_item_id where x.recipe_id = p_recipe and x.active order by x.sort, x.id loop
    need := round(public._base_qty(l.ingredient_item_id, l.qty, l.unit) * (1 + coalesce(l.waste_pct, 0) / 100), 4);
    if p_loc is not null then
      select avg_cost into av from public.stock_balance where item_id = l.ingredient_item_id and location_id = p_loc;
    else
      select sum(qty * avg_cost) / nullif(sum(qty), 0) into av from public.stock_balance
        where item_id = l.ingredient_item_id and qty > 0 and avg_cost is not null and (public._all_locs() or public.can_loc(location_id)) and public._cost_ok(location_id);
    end if;
    if av is null then complete := false; else total := total + need * av; end if;
    ls := ls || jsonb_build_object('ingredient_item_id', l.ingredient_item_id, 'code', l.code, 'need_base', need, 'unit_cost', av, 'line_cost', case when av is null then null else round(need * av, 4) end,
      'waste_missing', l.waste_pct is null);
  end loop;
  yb := public._base_qty(r.item_id, r.yield_qty, r.yield_unit);
  return jsonb_build_object('recipe_id', p_recipe, 'lines', ls, 'complete', complete, 'batch_cost', case when complete then round(total, 4) end,
    'unit_cost', case when complete and yb > 0 then round(total / yb, 6) end, 'yield_base', yb);
end $$;

-- ---------- production ----------
create or replace function public.production_post(p_loc int, p_recipe uuid, p_batches numeric, p_client uuid default null, p_made_at timestamptz default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.recipes; it public.items; at_ timestamptz := coalesce(p_made_at, now()); run public.production_runs; n record; rid uuid := gen_random_uuid();
        mode text; neg text; yb numeric; f numeric; sl jsonb; exp timestamptz; bid bigint; lin bigint; lid bigint; tot numeric := 0; cost_ok boolean := true; av numeric; wm int := 0;
        shorts text := ''; used jsonb := '[]'::jsonb; ucb numeric; derived uuid;
begin
  if at_ is null or at_ = 'infinity'::timestamptz or at_ = '-infinity'::timestamptz then raise exception 'bad_date'; end if;
  select * into r from public.recipes where id = p_recipe;
  if not found then raise exception 'recipe_not_found'; end if;
  it := public._stock_guard(r.item_id, p_loc, 'stock_production', (at_ at time zone 'Asia/Dhaka')::date);
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into run from public.production_runs where client_id = p_client;
    if found then
      if run.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'run_id', run.id, 'ledger_id', run.ledger_in_id, 'batch_id', run.batch_id, 'qty', run.yield_base);
    end if;
  end if;
  if not r.active then raise exception 'recipe_inactive'; end if;
  if p_batches is null or not (p_batches between 0.0001 and 100000) then raise exception 'bad_qty'; end if;
  if at_ > now() + interval '10 minutes' then raise exception 'bad_date'; end if;
  if not exists (select 1 from public.recipe_lines where recipe_id = r.id and active) then raise exception 'no_lines'; end if;
  f := public._base_qty(r.item_id, r.yield_qty, r.yield_unit);
  if f is null or not (f > 0) then raise exception 'unit_unknown'; end if;
  yb := round(f * p_batches, 4);
  if not (yb between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  -- everything that leaves the stock: checks first, nothing is posted until all are fine
  for n in select * from public._recipe_need(r.id, p_batches, p_loc) loop
    if not n.tracked then raise exception 'ingredient_not_tracked' using detail = coalesce(n.code, ''); end if;
    if not n.unit_ok then raise exception 'unit_unknown' using detail = coalesce(n.code, ''); end if;
    if n.waste_missing then wm := wm + 1; end if;
  end loop;
  if wm > 0 and public.rule_on('recipe_waste_required') then raise exception 'waste_needed'; end if;
  mode := coalesce(public.rule_txt('production_short_mode'), 'refuse');
  if mode = 'refuse' and coalesce(public.rule_txt('stock_negative_mode'), 'warn') <> 'allow' and not public.has_grant('sell_below_zero', p_loc) then
    for n in select * from public._recipe_need(r.id, p_batches, p_loc) where need > on_hand order by code loop
      shorts := shorts || case when shorts = '' then '' else '; ' end || coalesce(n.code, '') || ' ' || coalesce(n.name_bn, '') || ' (' || round(n.on_hand, 4)::text || ' / ' || n.need::text || ')';
    end loop;
    if shorts <> '' then raise exception 'insufficient_stock' using detail = shorts, hint = 'production'; end if;
  end if;
  if not public._may('stock_production', p_loc, 'production:' || r.item_id::text, yb) then raise exception 'not allowed'; end if;
  insert into public.production_runs (id, client_id, location_id, recipe_id, item_id, batches, made_at, yield_base, waste_missing, note, created_by)
    values (rid, p_client, p_loc, r.id, r.item_id, p_batches, at_, yb, wm, left(p_note, 200), auth.uid());
  -- ingredient (and packaging) OUT at the weighted average cost, fixed item order so two productions can never wait on each other in a circle
  for n in select * from public._recipe_need(r.id, p_batches, p_loc) order by item_id loop
    if n.need < 0.0001 then continue; end if;
    select avg_cost into av from public.stock_balance where item_id = n.item_id and location_id = p_loc;
    if av is null then cost_ok := false; else tot := tot + n.need * av; end if;
    derived := md5(coalesce(p_client::text, rid::text) || ':' || n.item_id::text)::uuid;
    lin := public.stock_post(n.item_id, p_loc, -n.need, 'issue_out', 'production', rid::text, null, null, at_, left(p_note, 200), null, 'full', null, derived);
    used := used || jsonb_build_object('item_id', n.item_id, 'kind', n.kind, 'qty', n.need);
  end loop;
  -- finished good IN: batch + expiry from the owner's shelf-life rules (no rule = no expiry); the cost is the ingredient cost when every ingredient has a known cost
  sl := public.shelf_life_for(r.item_id, (at_ at time zone 'Asia/Dhaka')::date);
  exp := case when sl is null then null else at_ + ((sl->>'hours')::float8 * interval '1 hour') end;
  insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by)
    values (r.item_id, p_loc, at_, yb, yb, exp, sl, left(p_note, 200), auth.uid()) returning id into bid;
  ucb := case when cost_ok and yb > 0 then round(tot / yb, 6) end;
  derived := md5(coalesce(p_client::text, rid::text) || ':in')::uuid;
  lid := public.stock_post(r.item_id, p_loc, yb, 'production_in', 'production', rid::text, ucb, bid, at_, left(p_note, 200), null, 'none', null, derived);
  update public.production_runs set ledger_in_id = lid, batch_id = bid, cost_complete = cost_ok where id = rid;
  update public.recipes set used_at = coalesce(used_at, now()) where id = r.id;
  if wm > 0 then
    perform public._stock_exc(p_loc, 'recipe_waste_missing', 'yellow', it.name_bn || ': রেসিপিতে অপচয় % বসানো নেই — ০ ধরা হয়েছে (' || wm::text || ' লাইন)',
      coalesce(it.name_en, it.name_bn) || ': the recipe has no waste % on ' || wm::text || ' line(s) — counted as 0', null, (at_ at time zone 'Asia/Dhaka')::date, 'STOCK');
  end if;
  return jsonb_build_object('run_id', rid, 'ledger_id', lid, 'batch_id', bid, 'qty', yb, 'expires_at', exp, 'consumed', used, 'waste_missing', wm) || case when public._cost_ok(p_loc) then jsonb_build_object('cost_complete', cost_ok) else '{}'::jsonb end;
end $$;

-- the old direct "production in": identical to phase10 except the new switch (production_requires_recipe)
create or replace function public.stock_production_in(p_item uuid, p_loc int, p_qty numeric, p_made_at timestamptz default null, p_unit text default null,
  p_note text default null, p_client uuid default null, p_unit_cost numeric default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it public.items; bq numeric; lid bigint; at_ timestamptz := coalesce(p_made_at, now()); sl jsonb; exp timestamptz; bid bigint; f numeric; ucb numeric; pct numeric; av numeric;
begin
  if at_ is null or at_ = 'infinity'::timestamptz or at_ = '-infinity'::timestamptz then raise exception 'bad_date'; end if;
  it := public._stock_guard(p_item, p_loc, 'stock_production', (at_ at time zone 'Asia/Dhaka')::date);
  perform public._client_lock(p_client);
  if p_client is not null then select id, batch_id into lid, bid from public.stock_ledger where client_id = p_client and reason = 'production_in' order by id limit 1; if found then return jsonb_build_object('dup', true, 'ledger_id', lid, 'batch_id', bid); end if; end if;
  if public.rule_on('production_requires_recipe') then raise exception 'recipe_required'; end if;
  if p_qty is null or not (p_qty between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  if at_ > now() + interval '10 minutes' then raise exception 'bad_date'; end if;
  if p_unit_cost is not null and not (p_unit_cost between 0 and 999999999) then raise exception 'bad_cost'; end if;
  if p_unit_cost is not null and not public._cost_ok(p_loc) then raise exception 'not allowed'; end if;      -- cost is secret: only who may see it may write it
  bq := public._base_qty(p_item, p_qty, p_unit);
  if bq is null then raise exception 'unit_unknown'; end if;
  if not public._may('stock_production', p_loc, 'production:' || p_item::text, bq) then raise exception 'not allowed'; end if;
  f := public._unit_factor_base(p_item, p_unit);
  if f is null or not (f > 0) then raise exception 'unit_unknown'; end if;
  pct := public.rule_num('purchase_cost_jump_pct');
  if p_unit_cost is not null and pct is not null then
    ucb := p_unit_cost / f;
    select avg_cost into av from public.stock_balance where item_id = p_item and location_id = p_loc;
    if av is not null and av > 0 and abs(ucb - av) / av * 100 > pct then
      perform public._stock_exc(p_loc, 'production_cost_jump', 'yellow',
        it.name_bn || ': উৎপাদন খরচ গড় খরচের চেয়ে ' || round((ucb - av) / av * 100, 1)::text || '% বদলেছে',
        coalesce(it.name_en, it.name_bn) || ': production cost moved ' || round((ucb - av) / av * 100, 1)::text || '% from the average cost in stock', null, (at_ at time zone 'Asia/Dhaka')::date, 'STOCK');
    end if;
  end if;
  sl := public.shelf_life_for(p_item, (at_ at time zone 'Asia/Dhaka')::date);
  exp := case when sl is null then null else at_ + ((sl->>'hours')::float8 * interval '1 hour') end;
  insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by)
    values (p_item, p_loc, at_, bq, bq, exp, sl, left(p_note, 200), auth.uid()) returning id into bid;
  lid := public.stock_post(p_item, p_loc, bq, 'production_in', 'production', bid::text, case when p_unit_cost is null then null else p_unit_cost / f end, bid, at_, left(p_note, 200), null, 'none', null, p_client);
  return jsonb_build_object('ledger_id', lid, 'batch_id', bid, 'qty', bq, 'expires_at', exp);
end $$;

-- ---------- packaging with a sale (separate trigger; the stock trigger and record_sale2 are untouched) ----------
create or replace function public._sale_packaging_out() returns trigger language plpgsql security definer set search_path = public as $$
declare pk record; bad boolean := false;
begin
  if new.status <> 'done' or new.lines is null or jsonb_typeof(new.lines) <> 'array' then return new; end if;
  if coalesce(public.rule_txt('packaging_consume_on'), 'off') <> 'sale' then return new; end if;
  begin
    for pk in
      select pp.packaging_item_id as item_id, sum(public._base_qty(li.iid, li.q, li.u) * pp.qty_per_unit) as qty, count(*) filter (where public._base_qty(li.iid, li.q, li.u) is null) as unk,
             i.code, i.name_bn, i.name_en
        from (select (x->>'item_id')::uuid as iid, nullif(x->>'qty', '')::numeric as q, x->>'unit' as u from jsonb_array_elements(new.lines) x where nullif(x->>'item_id', '') is not null) li
        join public.product_packaging pp on pp.product_item_id = li.iid and pp.active and pp.applies_to = 'sale'
        join public.items i on i.id = pp.packaging_item_id
       where li.q > 0 and li.q <= 999999999
       group by pp.packaging_item_id, i.code, i.name_bn, i.name_en order by pp.packaging_item_id loop
      if pk.unk > 0 then bad := true; end if;
      begin
        if pk.qty is null or round(pk.qty, 4) < 0.0001 then continue; end if;
        perform public.stock_post(pk.item_id, new.location_id, -round(pk.qty, 4), 'issue_out', 'sale_pack', new.id::text, null, null, new.sold_at, null, null, 'soft', new.id);
      exception when others then
        bad := true;
        perform public._stock_exc(new.location_id, 'packaging_not_consumed', 'yellow', 'রসিদ ' || new.receipt || ': ' || coalesce(pk.name_bn, '') || ' — প্যাকেজিং স্টক থেকে কমানো যায়নি',
          'Receipt ' || new.receipt || ': ' || coalesce(pk.name_en, pk.name_bn, '') || ' — the packaging could not be taken out of the stock', new.id, new.sale_date, 'POS');
      end;
    end loop;
  exception when others then
    bad := true;
  end;
  if bad then
    perform public._stock_exc(new.location_id, 'packaging_not_consumed', 'yellow', 'রসিদ ' || new.receipt || ': প্যাকেজিং পুরোটা কমানো যায়নি', 'Receipt ' || new.receipt || ': the packaging could not be fully taken out of the stock', new.id, new.sale_date, 'POS');
  end if;
  return new;
end $$;
drop trigger if exists sales_packaging_out on public.sales;
create trigger sales_packaging_out after insert on public.sales for each row execute function public._sale_packaging_out();

create or replace function public._sale_packaging_void() returns trigger language plpgsql security definer set search_path = public as $$
declare r public.stock_ledger;
begin
  for r in select * from public.stock_ledger o where o.ref_type = 'sale_pack' and o.ref_id = new.id::text and o.reason = 'issue_out'
           and not exists (select 1 from public.stock_ledger v where v.reverses_id = o.id) order by o.item_id, o.id loop
    perform public.stock_post(r.item_id, r.location_id, -r.qty_delta, 'sale_void_in', 'sale_pack', new.id::text, r.unit_cost, r.batch_id, now(), null, r.id, 'none', new.id);
  end loop;
  return new;
end $$;
drop trigger if exists sales_packaging_void on public.sales;
create trigger sales_packaging_void after update of status on public.sales for each row
  when (old.status is distinct from 'void' and new.status = 'void') execute function public._sale_packaging_void();

-- ---------- privileges ----------
revoke all on function public._recipe_mgr(), public._recipe_read(), public._recipe_cost_ok(), public._recipe_frozen(), public._recipe_lines_ok(uuid, jsonb), public._recipe_put_lines(uuid, jsonb),
  public._recipe_need(uuid, numeric, int), public._sale_packaging_out(), public._sale_packaging_void() from public, anon, authenticated;
revoke all on function public.recipe_save(uuid, uuid, numeric, text, text, jsonb, uuid, boolean), public.recipe_copy(uuid, uuid, boolean, uuid), public.recipe_set_active(uuid, boolean),
  public.packaging_set(uuid, uuid, numeric, text, boolean, text), public.production_preview(int, uuid, numeric), public.production_can_make(int), public.recipe_cost(uuid, int),
  public.production_post(int, uuid, numeric, uuid, timestamptz, text) from public, anon;
grant execute on function public.recipe_save(uuid, uuid, numeric, text, text, jsonb, uuid, boolean), public.recipe_copy(uuid, uuid, boolean, uuid), public.recipe_set_active(uuid, boolean),
  public.packaging_set(uuid, uuid, numeric, text, boolean, text), public.production_preview(int, uuid, numeric), public.production_can_make(int), public.recipe_cost(uuid, int),
  public.production_post(int, uuid, numeric, uuid, timestamptz, text) to authenticated;
revoke all on function public.stock_production_in(uuid, int, numeric, timestamptz, text, text, uuid, numeric) from public, anon;
grant execute on function public.stock_production_in(uuid, int, numeric, timestamptz, text, text, uuid, numeric) to authenticated;
-- the read policies call this helper as the signed-in person
grant execute on function public._recipe_read() to authenticated;
-- cost_complete is a cost fact: not readable by people who may not see costs
revoke select on public.production_runs from authenticated;
grant select (id, client_id, location_id, recipe_id, item_id, batches, made_at, yield_base, ledger_in_id, batch_id, waste_missing, note, created_by, created_at) on public.production_runs to authenticated;

-- ===== phase20 =====
-- ============================================================
-- Phase 20: FORMS <-> STOCK LEDGER LINKS, discount approver on sales, brand-level P&L.
--   Additive and safe to run twice; paste the whole file into the Supabase SQL editor.  Needs phase8..phase17 (phase18 / 19 are not required).
--   (1) rule forms_post_to_ledger (default OFF) + per-form switches forms_ledger_cfg(form_code, is_on).
--       When an entry of 04-1 GRN / 04-2 issue / 04-3 count / 03-1 transfer / 05-1 factory sheet is APPROVED, an AFTER UPDATE trigger on entries
--       calls entry_post_ledger(entry), which posts into the existing stock ledger through stock_post.  decide_entry is NOT edited.
--       - one log row per form line in entry_ledger_posts (entry, generation, line): the same approval twice posts nothing twice;
--       - reopen + re-approve (or an approved change request) with different content: reverse the earlier generation (reversal rows) and post the new one;
--       - lines whose item is not tracked / not counted in the business, held / returned GRN lines, lines without a quantity: skipped, yellow exception ledger_skip;
--       - any failure (unknown item, not enough stock, unknown unit ...): yellow exception ledger_post_failed with the reason, approval is never blocked;
--         entry_post_ledger_retry(entry) posts the failed lines again (and also posts an entry approved while the switch was off).
--   (2) the 04-4 store ledger and 06-5 supplier ledger need no new data: they become read views over stock_ledger_rows / supplier_ledger (web).
--   (3) sales.discount_approved_by / _staff / discount_approval: filled by a BEFORE INSERT trigger from the approval that record_sale2 used
--       (a granted role = the seller, an emergency approval = the person who approved the request).  record_sale2 is NOT edited.  RPC discounts_report.
--   (4) brand_pnl(from, to): the existing gross-profit figures (biz_daily) grouped by brand through report_brand_map. Costs only for cost-grant holders.
-- ============================================================

-- ---------- (1) switches ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('forms_post_to_ledger', 'stock', 'switch', 'false', null, null, null, null,
  'ফর্ম অনুমোদন হলে স্টক লেজারে নিজে থেকে পোস্ট', 'Form approve হলে stock ledger এ নিজে পোস্ট', 'Approved forms post to the stock ledger',
  'চালু করলে GRN, ইস্যু স্লিপ, কাউন্ট শিট, ট্রান্সফার চালান ও কারখানা শিট অনুমোদনের সময় স্টক লেজারে লাইন যোগ করে। বন্ধ থাকলে কিছুই বদলায় না।',
  null,
  'When on, an approved GRN, issue slip, count sheet, transfer challan or factory sheet adds its lines to the stock ledger. Off = nothing changes (default). Each form also has its own switch.', 71)
on conflict (key) do nothing;

create table if not exists public.forms_ledger_cfg (
  form_code text primary key references public.forms(code),
  is_on boolean not null default true,                     -- the master rule forms_post_to_ledger must be on as well
  changed_by uuid, changed_at timestamptz not null default now()
);
alter table public.forms_ledger_cfg enable row level security;
revoke all on public.forms_ledger_cfg from public, anon, authenticated;
grant select on public.forms_ledger_cfg to authenticated;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'forms_ledger_cfg' and policyname = 'forms_ledger_cfg_read') then
    create policy forms_ledger_cfg_read on public.forms_ledger_cfg for select to authenticated using (public.is_active());
  end if;
end $$;
insert into public.forms_ledger_cfg (form_code) select code from public.forms where code in ('04-1', '04-2', '04-3', '03-1', '05-1') on conflict do nothing;

create table if not exists public.entry_ledger_posts (
  id bigserial primary key,
  entry_id uuid not null references public.entries(id),
  gen int not null check (gen >= 1),                        -- a new generation when the approved content changed (the old one is reversed)
  line_no int not null,                                     -- 1-based line of the form table; 0 = the form as a whole
  form_code text not null,
  location_id int not null references public.locations(id), -- the entry's place
  to_location_id int references public.locations(id),
  kind text not null check (kind in ('in', 'out', 'count', 'transfer', 'prod', 'none')),
  item_id uuid references public.items(id),
  item_code text,
  qty_base numeric,                                         -- base unit; for a count the counted quantity
  sig text not null,                                        -- fingerprint of all lines of this generation
  status text not null check (status in ('posted', 'skipped', 'failed', 'reversed', 'void')),
  reason text,                                              -- why skipped / failed / the short note of a post
  ref text,                                                 -- entry:gen:line, written to stock_ledger.ref_id (ref_type 'entry')
  transfer_id uuid,
  posted_by uuid, posted_at timestamptz not null default now(), reversed_at timestamptz,
  unique (entry_id, gen, line_no)
);
create index if not exists entry_ledger_posts_entry on public.entry_ledger_posts (entry_id, gen);
create index if not exists entry_ledger_posts_bad on public.entry_ledger_posts (status) where status in ('failed', 'skipped');
alter table public.entry_ledger_posts enable row level security;
revoke all on public.entry_ledger_posts from public, anon, authenticated;
grant select on public.entry_ledger_posts to authenticated;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'entry_ledger_posts' and policyname = 'entry_ledger_posts_read') then
    create policy entry_ledger_posts_read on public.entry_ledger_posts for select to authenticated using (public.is_active() and (public.is_owner() or public.can_loc(location_id)));
  end if;
end $$;

-- ---------- small helpers ----------
create or replace function public._elp_num(p text) returns numeric
language sql immutable as $$ select case when btrim(p) ~ '^-?[0-9]+(\.[0-9]+)?$' then btrim(p)::numeric end $$;
create or replace function public._elp_flag(p text) returns boolean
language sql immutable as $$ select coalesce(lower(btrim(p)) in ('true', 't', '1', 'yes', 'on'), false) $$;
create or replace function public._elp_loc(p text) returns int
language sql stable security definer set search_path = public as $$
  select l.id from public.locations l where btrim(p) ~ '^[0-9]{1,9}$' and l.id = btrim(p)::int;
$$;
create or replace function public._elp_enabled(p_form text) returns boolean
language sql stable security definer set search_path = public as $$
  select p_form in ('04-1', '04-2', '04-3', '03-1', '05-1') and public.rule_on('forms_post_to_ledger')
         and coalesce((select c.is_on from public.forms_ledger_cfg c where c.form_code = p_form), true);
$$;

-- ---------- the form -> ledger lines map (what each form means for the ledger; nothing is guessed) ----------
-- one jsonb object per non-empty row: {n, kind, item, qty, cost, from, to, recv, skip, note}.  qty / cost are in the item's own unit as written on the form.
create or replace function public._elp_lines(e public.entries) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out jsonb := '[]'::jsonb; r jsonb; n int; tab text; arr jsonb; q text; cr jsonb; kept boolean; note text; nrate numeric;
begin
  note := left(e.form_code || '-' || e.serial::text || coalesce(' ' || nullif(btrim(e.data->>'supplier'), ''), ''), 120);
  if e.form_code = '04-1' then
    nrate := public._elp_num(e.data->>'new_rate');
    for r, n in select x.v, x.o::int from jsonb_array_elements(case when jsonb_typeof(e.data->'lines') = 'array' then e.data->'lines' else '[]'::jsonb end) with ordinality x(v, o) loop
      continue when coalesce(nullif(btrim(r->>'item'), ''), nullif(btrim(r->>'counted'), '')) is null;
      q := coalesce(r->>'quality', 'accept');
      out := out || jsonb_build_object('n', n, 'kind', 'in', 'item', nullif(btrim(r->>'item'), ''), 'qty', public._elp_num(r->>'counted'),
        'cost', case when q = 'reduced' and nrate is not null then nrate else public._elp_num(r->>'rate') end,
        'skip', case when q = 'hold' then 'quality_hold' when q = 'return' then 'quality_return' end, 'note', note);
    end loop;
  elsif e.form_code = '04-2' then
    kept := not public._elp_flag(e.data->>'not_overnight');       -- the form's own rule: kept overnight = the whole quantity counts as used
    for r, n in select x.v, x.o::int from jsonb_array_elements(case when jsonb_typeof(e.data->'lines') = 'array' then e.data->'lines' else '[]'::jsonb end) with ordinality x(v, o) loop
      continue when coalesce(nullif(btrim(r->>'item'), ''), nullif(btrim(r->>'issued'), '')) is null;
      out := out || jsonb_build_object('n', n, 'kind', 'out', 'item', nullif(btrim(r->>'item'), ''),
        'qty', public._elp_num(r->>'issued') - case when kept then 0 else coalesce(public._elp_num(r->>'ret'), 0) end, 'note', note || ' ' || coalesce(e.data->>'purpose', ''));
    end loop;
  elsif e.form_code = '04-3' then
    for r, n in select x.v, x.o::int from jsonb_array_elements(case when jsonb_typeof(e.data->'rows') = 'array' then e.data->'rows' else '[]'::jsonb end) with ordinality x(v, o) loop
      continue when coalesce(nullif(btrim(r->>'item'), ''), nullif(btrim(r->>'count'), '')) is null;
      out := out || jsonb_build_object('n', n, 'kind', 'count', 'item', nullif(btrim(r->>'item'), ''), 'qty', public._elp_num(r->>'count'), 'book', public._elp_num(r->>'book'),
        'skip', case when public._elp_num(r->>'book') is null then 'no_count_basis' end,
        'note', left(note || ' ' || coalesce(nullif(btrim(r->>'reason'), ''), 'stock count'), 190));
    end loop;
  elsif e.form_code = '03-1' then
    cr := case when jsonb_typeof(e.check_data->'items') = 'array' then e.check_data->'items' else '[]'::jsonb end;
    for r, n in select x.v, x.o::int from jsonb_array_elements(case when jsonb_typeof(e.data->'items') = 'array' then e.data->'items' else '[]'::jsonb end) with ordinality x(v, o) loop
      continue when coalesce(nullif(btrim(r->>'item'), ''), nullif(btrim(r->>'sent'), '')) is null;
      out := out || jsonb_build_object('n', n, 'kind', 'transfer', 'item', nullif(btrim(r->>'item'), ''), 'qty', public._elp_num(r->>'sent'),
        'from', public._elp_loc(e.data->>'from_loc'), 'to', public._elp_loc(e.data->>'to_loc'),
        'recv', public._elp_num(cr->(n - 1)->>'received'), 'note', note);
    end loop;
  elsif e.form_code = '05-1' then
    for r, n in select x.v, x.o::int from jsonb_array_elements(case when jsonb_typeof(e.data->'output') = 'array' then e.data->'output' else '[]'::jsonb end) with ordinality x(v, o) loop
      continue when coalesce(nullif(btrim(r->>'item'), ''), nullif(btrim(r->>'qty'), '')) is null;
      out := out || jsonb_build_object('n', n, 'kind', 'prod', 'item', nullif(btrim(r->>'item'), ''), 'qty', public._elp_num(r->>'qty'), 'note', note);
    end loop;
  end if;
  if jsonb_array_length(out) = 0 then
    out := jsonb_build_array(jsonb_build_object('n', 0, 'kind', 'none', 'skip', 'no_item_lines', 'note', note));
  end if;
  return out;
end $$;

-- ---------- post ONE line (runs inside a sub-transaction of entry_post_ledger: an error here undoes only this line) ----------
create or replace function public._elp_post_line(e public.entries, g int, sg text, l jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare it public.items; n int := (l->>'n')::int; kind text := l->>'kind'; qty numeric := nullif(l->>'qty', '')::numeric; bq numeric; f numeric; ucb numeric;
        ref text := e.id::text || ':g' || g::text || ':' || n::text; lid bigint; olid bigint; bal public.stock_balance; d numeric; tid uuid; fl int := nullif(l->>'from', '')::int;
        tl int := nullif(l->>'to', '')::int; rq numeric; rbq numeric; note text := nullif(l->>'note', ''); at_ timestamptz := now(); sl jsonb; exp timestamptz; bid bigint; sid text;
        stt text := 'posted'; why text; ucost numeric;
begin
  if l->>'skip' is null and kind = 'transfer' then
    if (fl is not null and fl <> e.location_id) or (fl is null and tl is not null and tl <> e.location_id) then why := 'location_mismatch'; stt := 'skipped';
    elsif not (public.is_owner() or ((fl is null or public.can_loc(fl)) and (tl is null or public.can_loc(tl)))) then why := 'location_mismatch'; stt := 'skipped';
    end if;
  end if;
  if l->>'skip' is not null then why := l->>'skip'; stt := 'skipped';
  elsif stt = 'skipped' then null;
  else
    if l->>'item' is null then raise exception 'item_missing'; end if;
    select * into it from public.items where code = l->>'item';
    if not found then raise exception 'item_not_found: %', l->>'item'; end if;
    if not it.is_active then raise exception 'item_not_active: %', it.code; end if;
    if not it.tracked then why := 'not_tracked'; stt := 'skipped';
    elsif not it.count_in_business then why := 'not_counted'; stt := 'skipped';
    end if;
  end if;
  if stt = 'skipped' then
    insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, posted_by)
      values (e.id, g, n, e.form_code, e.location_id, tl, kind, (select i.id from public.items i where i.code = l->>'item'), left(l->>'item', 60), null, sg, 'skipped', why, ref, auth.uid());
    return;
  end if;
  if qty is null then raise exception 'qty_missing'; end if;
  if kind <> 'count' and not (qty between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  if kind = 'count' and not (qty between 0 and 999999999) then raise exception 'bad_qty'; end if;
  bq := public._base_qty(it.id, qty, it.unit);
  if bq is null then raise exception 'unit_unknown: % %', it.code, coalesce(it.unit, ''); end if;
  if not (bq between case when kind = 'count' then 0 else 0.0001 end and 999999999) then raise exception 'bad_qty'; end if;
  f := public._unit_factor_base(it.id, it.unit);
  if f is null or not (f > 0) then raise exception 'unit_unknown: % %', it.code, coalesce(it.unit, ''); end if;
  ucost := nullif(l->>'cost', '')::numeric;
  if ucost is not null and not (ucost between 0 and 1000000000000) then ucost := null; end if;
  ucb := case when ucost is null then null else ucost / f end;

  if kind = 'in' then
    lid := public.stock_post(it.id, e.location_id, bq, 'purchase_in', 'entry', ref, ucb, null, at_, note, null, 'none');
  elsif kind = 'out' then
    lid := public.stock_post(it.id, e.location_id, -bq, 'issue_out', 'entry', ref, null, null, at_, note, null, 'full');
  elsif kind = 'count' then
    -- the count is against the system balance written on the sheet at COUNT time (a snapshot of the live balance is not possible later): delta = counted - that figure, applied to the CURRENT balance
    insert into public.stock_balance (item_id, location_id) values (it.id, e.location_id) on conflict do nothing;
    select * into bal from public.stock_balance where item_id = it.id and location_id = e.location_id for update;
    rbq := public._base_qty(it.id, nullif(l->>'book', '')::numeric, it.unit);
    if rbq is null then raise exception 'unit_unknown: % %', it.code, coalesce(it.unit, ''); end if;
    d := round(bq - rbq, 4);
    if d <> 0 then lid := public.stock_post(it.id, e.location_id, d, 'count_adjust', 'entry', ref, null, null, at_, left(coalesce(note, 'stock count'), 200), null, 'none'); end if;
    why := case when d = 0 then 'no_change' else 'delta ' || d::text end;
  elsif kind = 'prod' then
    sl := public.shelf_life_for(it.id, (at_ at time zone 'Asia/Dhaka')::date);
    exp := case when sl is null then null else at_ + ((sl->>'hours')::float8 * interval '1 hour') end;
    insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by)
      values (it.id, e.location_id, at_, bq, bq, exp, sl, left(note, 200), auth.uid()) returning id into bid;
    lid := public.stock_post(it.id, e.location_id, bq, 'production_in', 'entry', ref, null, bid, at_, left(note, 200), null, 'none');
  elsif kind = 'transfer' then
    if fl is not null and tl is not null then
      if fl = tl then raise exception 'same_location'; end if;
      rq := nullif(l->>'recv', '')::numeric;
      if rq is not null then
        if not (rq between 0 and 999999999) then raise exception 'bad_qty'; end if;
        rbq := public._base_qty(it.id, rq, it.unit);
        if rbq is null then raise exception 'unit_unknown: % %', it.code, coalesce(it.unit, ''); end if;
        if rbq > bq then raise exception 'over_received'; end if;
      end if;
      tid := gen_random_uuid(); select staff_id into sid from public.profiles where id = auth.uid();
      insert into public.stock_transfers (id, from_location_id, to_location_id, item_id, qty, status, received_qty, note, sent_by, sent_staff, sent_at,
          received_by, received_staff, received_at)
        values (tid, fl, tl, it.id, bq, case when rq is null then 'sent' else 'received' end, rbq, left(note, 200), auth.uid(), sid, at_,
          case when rq is null then null else auth.uid() end, case when rq is null then null else sid end, case when rq is null then null else at_ end);
      olid := public.stock_post(it.id, fl, -bq, 'transfer_out', 'transfer', tid::text, null, null, at_, left(note, 200), null, 'full');
      if rq is not null and rbq > 0 then
        select unit_cost into ucost from public.stock_ledger where id = olid;
        perform public.stock_post(it.id, tl, rbq, 'transfer_in', 'transfer', tid::text, ucost, null, at_, left(note, 200), null, 'none');
      end if;
      why := case when rq is null then 'in_transit' when rbq < bq then 'short ' || (bq - rbq)::text else null end;
      insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, transfer_id, posted_by)
        values (e.id, g, n, e.form_code, e.location_id, tl, kind, it.id, it.code, bq, sg, 'posted', why, ref, tid, auth.uid());
      return;
    elsif fl is not null then          -- goods leave for a place outside the tracked places (customer, party ...): the sender's out leg only
      lid := public.stock_post(it.id, fl, -bq, 'transfer_out', 'entry', ref, null, null, at_, left(note, 200), null, 'full');
    elsif tl is not null then          -- goods come in from outside (party return ...): the receiver's in leg only
      lid := public.stock_post(it.id, tl, coalesce(public._base_qty(it.id, nullif(l->>'recv', '')::numeric, it.unit), bq), 'transfer_in', 'entry', ref, null, null, at_, left(note, 200), null, 'none');
    else raise exception 'location_missing';
    end if;
  end if;
  insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, posted_by)
    values (e.id, g, n, e.form_code, coalesce(fl, e.location_id), tl, kind, it.id, it.code, bq, sg, 'posted', why, ref, auth.uid());
end $$;

-- ---------- undo one generation (reversal rows; nothing is deleted) ----------
create or replace function public._elp_reverse(e public.entries, g int) returns void
language plpgsql security definer set search_path = public as $$
declare p public.entry_ledger_posts; o public.stock_ledger;
begin
  for p in select * from public.entry_ledger_posts where entry_id = e.id and gen = g and status = 'posted' order by line_no desc loop
    for o in select x.* from public.stock_ledger x where x.reason <> 'reversal'
             and ((p.transfer_id is not null and x.ref_type = 'transfer' and x.ref_id = p.transfer_id::text) or (p.transfer_id is null and x.ref_type = 'entry' and x.ref_id = p.ref))
             and not exists (select 1 from public.stock_ledger y where y.reverses_id = x.id) order by x.id desc loop
      perform public.stock_post(o.item_id, o.location_id, -o.qty_delta, 'reversal', o.ref_type, o.ref_id, o.unit_cost, o.batch_id, now(), 'entry revised: earlier posting undone', o.id, 'none');
    end loop;
    if p.transfer_id is not null then update public.stock_transfers set status = 'cancelled', cancelled_by = auth.uid(), cancelled_at = now() where id = p.transfer_id; end if;
    update public.entry_ledger_posts set status = 'reversed', reversed_at = now() where id = p.id;
  end loop;
  update public.entry_ledger_posts set status = 'void' where entry_id = e.id and gen = g and status in ('failed', 'skipped');
end $$;

create or replace function public._elp_exceptions(e public.entries, g int) returns void
language plpgsql security definer set search_path = public as $$
declare sk text; fl text; nsk int; nfl int;
begin
  delete from public.exceptions where entry_id = e.id and status = 'open' and flag_code in ('ledger_skip', 'ledger_post_failed');
  select count(*), string_agg('#' || line_no::text || ' ' || coalesce(item_code, '-') || ' ' || coalesce(reason, ''), '; ' order by line_no) into nsk, sk
    from public.entry_ledger_posts where entry_id = e.id and gen = g and status = 'skipped';
  select count(*), string_agg('#' || line_no::text || ' ' || coalesce(item_code, '-') || ': ' || coalesce(reason, ''), '; ' order by line_no) into nfl, fl
    from public.entry_ledger_posts where entry_id = e.id and gen = g and status = 'failed';
  if nsk > 0 then
    insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (e.id, e.form_code, e.location_id, e.entry_date, 'ledger_skip', 'yellow', nsk,
        jsonb_build_object('bn', e.form_code || '-' || e.serial || ': ' || nsk || ' লাইন স্টক লেজারে যায়নি — ' || left(sk, 300),
                           'en', e.form_code || '-' || e.serial || ': ' || nsk || ' line(s) were not posted to the stock ledger — ' || left(sk, 300)));
  end if;
  if nfl > 0 then
    insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (e.id, e.form_code, e.location_id, e.entry_date, 'ledger_post_failed', 'yellow', nfl,
        jsonb_build_object('bn', e.form_code || '-' || e.serial || ': ' || nfl || ' লাইন স্টক লেজারে পোস্ট হয়নি (আবার চেষ্টা করা যাবে) — ' || left(fl, 300),
                           'en', e.form_code || '-' || e.serial || ': ' || nfl || ' line(s) could not be posted to the stock ledger (retry is possible) — ' || left(fl, 300)));
  end if;
end $$;

-- ---------- the poster: idempotent. Same content = nothing new; changed content = reverse the old generation and post the new one ----------
create or replace function public.entry_post_ledger(p_entry uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; lines jsonb; sg text; g int; cur text; l jsonb; n int; nposted int := 0; nfail int := 0; nskip int := 0; msg text; sid text;
begin
  select * into e from public.entries where id = p_entry for update;
  if not found or e.status <> 'approved' then return jsonb_build_object('ok', false, 'why', 'not_approved'); end if;
  if not public._elp_enabled(e.form_code) then return jsonb_build_object('ok', true, 'enabled', false); end if;
  lines := public._elp_lines(e); sg := md5(lines::text);
  select max(gen) into g from public.entry_ledger_posts where entry_id = e.id;
  if g is null then g := 1;
  else
    select sig into cur from public.entry_ledger_posts where entry_id = e.id and gen = g limit 1;
    if cur is distinct from sg then
      begin
        perform public._elp_reverse(e, g);
        g := g + 1;
      exception when others then
        msg := sqlerrm;
        delete from public.exceptions where entry_id = e.id and status = 'open' and flag_code = 'ledger_post_failed';
        insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
          values (e.id, e.form_code, e.location_id, e.entry_date, 'ledger_post_failed', 'yellow', null,
            jsonb_build_object('bn', e.form_code || '-' || e.serial || ': সংশোধিত ফর্মের আগের লেজার পোস্টিং ফেরানো যায়নি — ' || left(msg, 200),
                               'en', e.form_code || '-' || e.serial || ': the earlier ledger posting of the revised form could not be undone — ' || left(msg, 200)));
        return jsonb_build_object('ok', false, 'why', 'reverse_failed', 'error', msg);
      end;
    end if;
  end if;
  for l in select * from jsonb_array_elements(lines) loop
    n := (l->>'n')::int;
    if exists (select 1 from public.entry_ledger_posts where entry_id = e.id and gen = g and line_no = n and status in ('posted', 'skipped')) then continue; end if;
    delete from public.entry_ledger_posts where entry_id = e.id and gen = g and line_no = n and status = 'failed';
    begin
      perform public._elp_post_line(e, g, sg, l);
    exception when others then
      insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_code, qty_base, sig, status, reason, posted_by)
        values (e.id, g, n, e.form_code, e.location_id, nullif(l->>'to', '')::int, coalesce(l->>'kind', 'none'), left(l->>'item', 60), null, sg, 'failed', left(sqlerrm, 200), auth.uid());
    end;
  end loop;
  select count(*) filter (where status = 'posted'), count(*) filter (where status = 'failed'), count(*) filter (where status = 'skipped') into nposted, nfail, nskip
    from public.entry_ledger_posts where entry_id = e.id and gen = g;
  perform public._elp_exceptions(e, g);
  return jsonb_build_object('ok', true, 'enabled', true, 'gen', g, 'posted', nposted, 'failed', nfail, 'skipped', nskip);
end $$;
revoke all on function public.entry_post_ledger(uuid), public._elp_post_line(public.entries, int, text, jsonb), public._elp_reverse(public.entries, int),
  public._elp_exceptions(public.entries, int), public._elp_lines(public.entries) from public, anon, authenticated;

-- the trigger: never blocks the approval (a failure of the whole poster becomes one exception)
create or replace function public._entries_post_ledger() returns trigger
language plpgsql security definer set search_path = public as $$
declare msg text;
begin
  if not public._elp_enabled(new.form_code) then return null; end if;
  begin
    perform public.entry_post_ledger(new.id);
  exception when others then
    msg := sqlerrm;
    begin
      insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
        values (new.id, new.form_code, new.location_id, new.entry_date, 'ledger_post_failed', 'yellow', null,
          jsonb_build_object('bn', new.form_code || '-' || new.serial || ': স্টক লেজারে পোস্ট হয়নি — ' || left(msg, 200),
                             'en', new.form_code || '-' || new.serial || ': could not post to the stock ledger — ' || left(msg, 200)));
    exception when others then null;
    end;
  end;
  return null;
end $$;
revoke all on function public._entries_post_ledger() from public, anon, authenticated;
drop trigger if exists entries_post_ledger on public.entries;
create trigger entries_post_ledger after update on public.entries for each row
  when (new.status = 'approved' and (old.status is distinct from 'approved' or old.data is distinct from new.data or old.check_data is distinct from new.check_data))
  execute function public._entries_post_ledger();

-- ---------- public RPCs ----------
create or replace function public._elp_may(p_entry uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and exists (select 1 from public.entries e where e.id = p_entry
    and (public.is_owner() or (public.can_loc(e.location_id) and public.can_do(e.form_code, 'approve'))));
$$;
revoke all on function public._elp_may(uuid) from public, anon, authenticated;

create or replace function public.entry_post_ledger_retry(p_entry uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public._elp_may(p_entry) then raise exception 'not allowed'; end if;
  return public.entry_post_ledger(p_entry);
end $$;

-- lines of one entry (what went to the ledger); no costs
create or replace function public.entry_ledger_lines(p_entry uuid)
returns table (gen int, line_no int, kind text, item_code text, qty_base numeric, status text, reason text, posted_at timestamptz, reversed_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_active() and exists (select 1 from public.entries e where e.id = p_entry and (public.is_owner() or public.can_loc(e.location_id)))) then raise exception 'not allowed'; end if;
  return query select x.gen, x.line_no, x.kind, x.item_code, x.qty_base, x.status, x.reason, x.posted_at, x.reversed_at from public.entry_ledger_posts x where x.entry_id = p_entry order by x.gen, x.line_no;
end $$;

-- approved entries whose latest generation has failed lines (the retry list)
create or replace function public.ledger_post_problems(p_loc int default null)
returns table (entry_id uuid, form_code text, serial int, location_id int, entry_date date, failed int, skipped int, first_reason text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return query
    with cur as (select x.entry_id, max(x.gen) g from public.entry_ledger_posts x group by 1)
    select e.id, e.form_code, e.serial, e.location_id, e.entry_date,
           (count(*) filter (where x.status = 'failed'))::int, (count(*) filter (where x.status = 'skipped'))::int,
           min(x.reason) filter (where x.status = 'failed')
    from cur join public.entry_ledger_posts x on x.entry_id = cur.entry_id and x.gen = cur.g
    join public.entries e on e.id = x.entry_id
    where (p_loc is null or e.location_id = p_loc) and (public.is_owner() or (public.can_loc(e.location_id) and public.can_do(e.form_code, 'approve')))
    group by e.id, e.form_code, e.serial, e.location_id, e.entry_date
    having count(*) filter (where x.status in ('failed', 'skipped')) > 0
    order by e.entry_date desc, e.serial desc limit 200;
end $$;

-- owner: per-form switch
create or replace function public.forms_ledger_cfg_set(p_form text, p_on boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_form not in ('04-1', '04-2', '04-3', '03-1', '05-1') or p_on is null then raise exception 'bad_form'; end if;
  insert into public.forms_ledger_cfg (form_code, is_on, changed_by, changed_at) values (p_form, p_on, auth.uid(), now())
    on conflict (form_code) do update set is_on = excluded.is_on, changed_by = auth.uid(), changed_at = now();
  return jsonb_build_object('form_code', p_form, 'is_on', p_on);
end $$;

-- ---------- (3) discount approver on sales ----------
alter table public.sales add column if not exists discount_approved_by uuid;
alter table public.sales add column if not exists discount_approved_staff text;
alter table public.sales add column if not exists discount_approval text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'sales_discount_approval_chk') then
    alter table public.sales add constraint sales_discount_approval_chk check (discount_approval is null or discount_approval in ('grant', 'emergency'));
  end if;
end $$;

-- record_sale2 asks rule_ok('discount_over_limit', ...) BEFORE the insert: a granted role passes can_grant (= the seller holds the right), otherwise the one-use / window
-- emergency approval is consumed and use_emergency leaves 'id:grant' in the transaction setting bos.em_used.  The trigger reads exactly that.
create or replace function public._sales_discount_approver() returns trigger
language plpgsql security definer set search_path = public as $$
declare em text; rid bigint; r public.emergency_requests; lim jsonb;
begin
  if coalesce(new.discount, 0) <= 0 or new.discount_approved_by is not null then return new; end if;
  em := current_setting('bos.em_used', true);
  if em is not null and em ~ ':discount_over_limit' then
    select (x.m)[1]::bigint into rid from regexp_matches(em, '([0-9]+):discount_over_limit', 'g') as x(m) order by (x.m)[1]::bigint desc limit 1;
    select * into r from public.emergency_requests where id = rid;
    if found and r.decided_by is not null then
      new.discount_approved_by := r.decided_by; new.discount_approved_staff := r.decided_staff; new.discount_approval := 'emergency'; return new;
    end if;
  end if;
  select value into lim from public.location_settings where location_id = new.location_id and key = 'discount_limit';
  if public.rule_on('pos_discount_manager') and (lim is null or jsonb_typeof(lim) = 'null' or new.discount > (lim #>> '{}')::numeric) and public.can_grant('discount_over_limit') then
    new.discount_approved_by := new.created_by;
    select staff_id into new.discount_approved_staff from public.profiles where id = new.created_by;
    new.discount_approval := 'grant';
  end if;
  return new;
end $$;
revoke all on function public._sales_discount_approver() from public, anon, authenticated;
drop trigger if exists sales_discount_approver on public.sales;
create trigger sales_discount_approver before insert on public.sales for each row execute function public._sales_discount_approver();

create or replace function public.discounts_report(p_from date, p_to date, p_loc int default null, p_only_approved boolean default false)
returns table (sale_id uuid, location_id int, receipt int, sale_date date, status text, subtotal numeric, discount numeric, discount_kind text, discount_input numeric, total numeric,
               seller_staff text, approver_staff text, approval text, over_limit boolean, customer text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.biz_ok() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  return query
    select s.id, s.location_id, s.receipt, s.sale_date, s.status, s.subtotal, s.discount, s.discount_kind, s.discount_input, s.total, s.created_staff,
           s.discount_approved_staff, s.discount_approval,
           (s.discount_approval is not null), s.customer
    from public.sales s
    where s.sale_date between p_from and p_to and s.discount > 0 and (p_loc is null or s.location_id = p_loc) and public.can_loc(s.location_id)
      and (not coalesce(p_only_approved, false) or s.discount_approval is not null)
    order by s.sale_date desc, s.location_id, s.receipt desc limit 2000;
end $$;

-- ---------- (4) brand-level P&L ----------
-- The existing gross-profit figures (biz_daily: revenue, discount, voids, costed revenue, cost of goods) grouped by brand.  A location that is not in report_brand_map is
-- shown as 'unmapped' (nothing is guessed).  Cost / gross profit are NULL for callers without a cost right (biz_daily already blanks them).  Combined = the sum of the rows (web).
create or replace function public.brand_pnl(p_from date, p_to date, p_brand text default null)
returns table (brand_code text, brand_bn text, brand_en text, locations int, n bigint, revenue numeric, discount numeric, void_n bigint, void_amt numeric,
               costed_rev numeric, cogs numeric, gross_profit numeric, gp_pct numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.biz_ok() then raise exception 'not allowed'; end if;
  return query
    with d as (select x.* from public.biz_daily(p_from, p_to, null) x),
    m as (select d.*, coalesce(b.brand_code, 'unmapped') bc, b.brand_bn bbn, b.brand_en ben from d left join public.report_brand_map b on b.location_id = d.location_id)
    select m.bc, coalesce(max(m.bbn), 'ব্র্যান্ড ঠিক করা নেই'), coalesce(max(m.ben), 'Not mapped to a brand'), (count(distinct m.location_id))::int,
           sum(m.n)::bigint, sum(m.revenue), sum(m.discount), sum(m.void_n)::bigint, sum(m.void_amt),
           sum(m.costed_rev), sum(m.cogs),
           case when public.biz_cost_ok() then sum(m.costed_rev) - sum(m.cogs) end,
           case when public.biz_cost_ok() and sum(m.costed_rev) > 0 then round((sum(m.costed_rev) - sum(m.cogs)) / sum(m.costed_rev) * 100, 2) end
    from m where p_brand is null or m.bc = p_brand
    group by m.bc order by sum(m.revenue) desc nulls last;
end $$;

-- ---------- grants ----------
revoke all on function public.entry_post_ledger_retry(uuid), public.entry_ledger_lines(uuid), public.ledger_post_problems(int), public.forms_ledger_cfg_set(text, boolean),
  public.discounts_report(date, date, int, boolean), public.brand_pnl(date, date, text) from public, anon;
grant execute on function public.entry_post_ledger_retry(uuid), public.entry_ledger_lines(uuid), public.ledger_post_problems(int), public.forms_ledger_cfg_set(text, boolean),
  public.discounts_report(date, date, int, boolean), public.brand_pnl(date, date, text) to authenticated;
revoke all on function public._elp_num(text), public._elp_flag(text), public._elp_loc(text), public._elp_enabled(text), public._sales_discount_approver() from public, anon, authenticated;

-- ===== phase21 =====
-- ============================================================
-- BOS tool · Phase 21: MORE REPORTS (12) for the Reports hub, beside the phase9 engine.
-- Run AFTER phase9 (needs report_presets, rpt_* helpers, report_brand_map) and phase10 (stock tables) and the purchase tables.
-- Additive and idempotent: safe to run again. NOTHING from phase9 is replaced or edited.
--
-- Why a second function: phase9's report_run reads its whitelist from rpt_def / rpt_keys (immutable SQL functions inside an already
-- applied file). Replacing them would silently lose the new reports the day phase9 is pasted again. So the new reports have their OWN
-- whitelist and their own three functions with the SAME answer shape as report_run (columns, rows, totals, page, has_more, notes, meta):
--   report_catalog2()                              list for the hub (same fields as report_catalog)
--   report_run2(key, filters, group, sort, page)   the data; user input never becomes SQL (keys in a fixed list, values quoted with %L)
--   log_report_export2(key, kind, filters, rows)   audit row after a CSV / print (owner or grant export_data)
-- The app (web/reports.js + web/reports2.js) merges the two catalogues and sends a key to the function that owns it.
--
-- Security (same rules as phase9)
--   * every call needs the grant report_<group> or view_reports (owner always); rows limited to can_loc() locations
--   * cost columns exist only for owner / ITEM_COST view / grant view_cost or view_profit (not computed otherwise);
--     the two supplier-money reports are cost-only: without that right they are locked, not shown empty
--   * numbers read from the jsonb of forms are parsed safely (text that is not a plain number is skipped and counted, never guessed)
--   * thresholds are RULES with no built-in value: aging buckets reuse report_aging_buckets; "expiring soon" needs report_expiry_soon_days
-- ============================================================

-- ---------- grants (seeded only when missing; nobody gets them by default except the owner: the owner gives them in Who may do what) ----------
do $$
declare r record;
begin
  for r in select * from (values
    ('report_stock',    64, 'রিপোর্ট: স্টক ও অপচয়', 'Report: Stock & wastage', 'Reports: Stock and wastage'),
    ('report_purchase', 65, 'রিপোর্ট: ক্রয় ও সরবরাহকারী', 'Report: Purchases & suppliers', 'Reports: Purchases and suppliers'),
    ('report_expense',  66, 'রিপোর্ট: খরচ', 'Report: Expenses', 'Reports: Expenses'),
    ('report_staff',    67, 'রিপোর্ট: কর্মীর হাজিরা', 'Report: Staff attendance', 'Reports: Staff attendance'),
    ('report_control',  68, 'রিপোর্ট: ব্যতিক্রম (গরমিল)', 'Report: Exceptions', 'Reports: Exceptions')) v(code, sort, bn, mix, en)
  loop
    if not exists (select 1 from public.grant_defs where grant_code = r.code) then
      insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
        values (r.code, 'reports', r.sort, r.bn, r.mix, r.en, 'once', null);
    end if;
  end loop;
end $$;

insert into public.rules (key, module, kind, default_value, unit, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('report_expiry_soon_days', 'reports', 'number', null, 'দিন', 0, 3650, 'মেয়াদ কত দিনের মধ্যে শেষ হলে "শিগগির শেষ" ধরা হবে', 'Expiry কত দিনের মধ্যে হলে "শিগগির শেষ"', 'Days ahead that count as "expiring soon"', 'ফাঁকা থাকলে শুধু মেয়াদ-শেষ ব্যাচ দেখাবে', 'Empty = only batches already past expiry are listed', 65)
 on conflict (key) do nothing;
-- the staff home lists "today's sheets to fill": empty = every sheet the person may enter; the owner can narrow it to the daily sheets (codes separated by commas)
insert into public.rules (key, module, kind, default_value, unit, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('home_daily_forms', 'settings', 'text', null, null, null, null, 'হোমে "আজকের শিট"-এ কোন ফর্মগুলো দেখাবে (কোড, কমা দিয়ে)', 'Home-এ "আজকের Sheet"-এ কোন Form (code, comma দিয়ে)', 'Daily sheets shown on the staff home (form codes, comma separated)', 'ফাঁকা = কর্মী যে ফর্মে লিখতে পারে সবগুলো', 'Empty = every form the person may enter', 66)
 on conflict (key) do nothing;

-- ---------- small helpers ----------
create or replace function public._r2_num(j jsonb) returns numeric
language sql immutable set search_path = public as $$
  select case when j is null then null
    when jsonb_typeof(j) = 'number' then case when (j #>> '{}')::numeric between -1000000000000 and 1000000000000 then (j #>> '{}')::numeric end
    when jsonb_typeof(j) = 'string' and btrim(j #>> '{}') ~ '^-?[0-9]{1,12}(\.[0-9]{1,4})?$' then btrim(j #>> '{}')::numeric end;
$$;

-- locations the caller may use, narrowed by the filters locations / brands
create or replace function public._r2_locs(p_flt jsonb) returns int[]
language plpgsql stable security definer set search_path = public as $$
declare al int[]; lo int[]; br text[];
begin
  al := coalesce((select array_agg(l.id) from public.locations l where public.can_loc(l.id)), '{}');
  lo := public.rpt_arr_int(p_flt -> 'locations');
  if lo is not null then al := coalesce(array(select unnest(al) intersect select unnest(lo)), '{}'); end if;
  br := public.rpt_arr_text(p_flt -> 'brands');
  if br is not null then al := coalesce(array(select x from unnest(al) x where exists (select 1 from public.report_brand_map m where m.location_id = x and m.brand_code = any (br))), '{}'); end if;
  return al;
end $$;

-- the whitelist: group, names, which filters, sort, groups (dims) and fixed columns [key, bn, en, type]
create or replace function public._r2_def(p_key text) returns jsonb
language sql immutable set search_path = public as $j$
  select ($c${
   "item_slow":{"group":"sales","bn":"ধীর ও অবিক্রীত আইটেম","en":"Slow and unsold items","mix":"ধীর ও unsold Item","allow":["locations","brands","categories"],"sort":"qty:asc"},
   "stock_low":{"group":"stock","bn":"স্টক কম (ন্যূনতমের নিচে)","en":"Stock at or below minimum","mix":"Stock কম (minimum-এর নিচে)","allow":["locations","brands","categories"],"nodate":1,"sort":"short_by:desc"},
   "stock_balance":{"group":"stock","bn":"স্টক ব্যালান্স","en":"Stock balance","mix":"Stock balance","allow":["locations","brands","categories"],"nodate":1,"sort":"item_name:asc"},
   "wastage":{"group":"stock","bn":"অপচয় (কারণ / আইটেম অনুযায়ী)","en":"Wastage by reason / item","mix":"অপচয় (reason / item অনুযায়ী)","allow":["locations","brands"],"gdef":"reason","dims":["reason","item","location","day"],"sort":"@dim"},
   "expiry_soon":{"group":"stock","bn":"মেয়াদ শেষ / শিগগির শেষ","en":"Expired and expiring soon","mix":"Expiry শেষ / শিগগির শেষ","allow":["locations","brands","categories"],"nodate":1,"sort":"days_left:asc"},
   "transfers_gap":{"group":"stock","bn":"ট্রান্সফার: পৌঁছায়নি / কম পৌঁছেছে","en":"Transfers not received or short","mix":"Transfer: পৌঁছায়নি / কম","allow":["locations","brands"],"sort":"sent_day:desc"},
   "supplier_ageing":{"group":"purchase","bn":"সরবরাহকারীকে দেনার বয়স","en":"Supplier payables ageing","mix":"Supplier-কে দেনার বয়স","allow":["locations","brands"],"nodate":1,"cost":1,"sort":"balance:desc"},
   "purchases_by_supplier":{"group":"purchase","bn":"ক্রয় (সরবরাহকারী অনুযায়ী)","en":"Purchases by supplier","mix":"Purchase (supplier অনুযায়ী)","allow":["locations","brands"],"cost":1,"gdef":"supplier","dims":["supplier","location","day"],"sort":"total:desc"},
   "expense_by_head":{"group":"expense","bn":"খরচ (খাত অনুযায়ী)","en":"Expenses by head","mix":"খরচ (head অনুযায়ী)","allow":["locations","brands"],"gdef":"head","dims":["head","location","day"],"sort":"amount:desc"},
   "cash_short_over":{"group":"cash","bn":"ক্যাশ কম / বেশি","en":"Cash short / over","mix":"Cash কম / বেশি","allow":["locations","brands"],"gdef":"location","dims":["location","day","staff"],"sort":"net:asc"},
   "attendance_summary":{"group":"staff","bn":"হাজিরার সারসংক্ষেপ","en":"Attendance summary","mix":"হাজিরার summary","allow":["locations","brands"],"gdef":"person","dims":["person","location"],"sort":"absent:desc"},
   "exceptions_summary":{"group":"control","bn":"ব্যতিক্রম (গরমিল) সারসংক্ষেপ","en":"Exceptions summary","mix":"Exception summary","allow":["locations","brands"],"gdef":"form","dims":["form","location","flag","level","day"],"sort":"total:desc"}
  }$c$::jsonb) -> p_key;
$j$;

create or replace function public._r2_keys() returns text[]
language sql immutable set search_path = public as $$
  select array['item_slow','stock_low','stock_balance','wastage','expiry_soon','transfers_gap','supplier_ageing','purchases_by_supplier','expense_by_head','cash_short_over','attendance_summary','exceptions_summary'];
$$;

-- group (dimension) labels for the hub / group picker
create or replace function public._r2_dimlab(p_dim text) returns jsonb
language sql immutable set search_path = public as $$
  select ($c${"reason":["কারণ","Reason"],"item":["আইটেম","Item"],"location":["লোকেশন","Location"],"day":["দিন","Day"],"supplier":["সরবরাহকারী","Supplier"],
    "head":["খরচের খাত","Expense head"],"staff":["কর্মী","Staff"],"person":["কর্মী","Person"],"form":["ফর্ম","Form"],"flag":["ব্যতিক্রমের ধরন","Exception type"],"level":["মাত্রা","Level"]}$c$::jsonb) -> p_dim;
$$;

-- access: group grant (or view_reports), cost-only reports also need the cost right
create or replace function public._r2_ok(p_key text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare d jsonb := public._r2_def(p_key);
begin
  if d is null then return false; end if;
  return public.rpt_access(d ->> 'group') and (coalesce((d ->> 'cost')::int, 0) = 0 or public.rpt_cost_ok());
end $$;

-- ---------- catalogue ----------
create or replace function public.report_catalog2() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare k text; d jsonb; out_ jsonb := '[]'::jsonb; dl jsonb; g text; ok boolean;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  foreach k in array public._r2_keys() loop
    d := public._r2_def(k); ok := public._r2_ok(k); dl := '[]'::jsonb;
    if d ? 'dims' then
      for g in select jsonb_array_elements_text(d -> 'dims') loop
        dl := dl || jsonb_build_array(jsonb_build_object('key', g, 'time', g = 'day', 'label_bn', public._r2_dimlab(g) ->> 0, 'label_en', public._r2_dimlab(g) ->> 1, 'needs_rule', null));
      end loop;
    end if;
    out_ := out_ || jsonb_build_array(jsonb_build_object('key', k, 'group', d ->> 'group', 'grant', 'report_' || (d ->> 'group'), 'allowed', ok, 'kind', 'raw', 'engine', 2,
      'name_bn', d ->> 'bn', 'name_en', d ->> 'en', 'name_mix', d ->> 'mix',
      'filters', to_jsonb(case when coalesce((d ->> 'nodate')::int, 0) = 0 then array['date'] else '{}'::text[] end || coalesce((select array_agg(x) from jsonb_array_elements_text(d -> 'allow') x), '{}')),
      'dims', dl, 'default_group', nullif(d ->> 'gdef', ''), 'columns', '[]'::jsonb, 'compare', false, 'needs_date', coalesce((d ->> 'nodate')::int, 0) = 0, 'cost_only', coalesce((d ->> 'cost')::int, 0) = 1));
  end loop;
  return out_;
end $$;

-- ---------- the data ----------
create or replace function public.report_run2(p_key text, p_filters jsonb default '{}'::jsonb, p_group text default null, p_sort text default null, p_page int default 1) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  def jsonb; flt jsonb; notes jsonb := '[]'::jsonb; today date := (now() at time zone 'Asia/Dhaka')::date; cost_ok boolean; eff int[]; nloc int;
  d1 date; d2 date; pr jsonb; preset text; pgsize int; pg int := least(greatest(coalesce(p_page, 1), 1), 1000); off int; lim int; cap constant int := 500;
  g text; t text; tot text; cols jsonb := '[]'::jsonb; outc jsonb := '[]'::jsonb; allowkeys text[] := '{}'; c jsonb; sk text; sd text; sraw text; sparts text[]; ordr text; dsort text;
  rows_ jsonb; totals_ jsonb; ngroups bigint := 0; hm boolean; dn boolean := false; cat text[]; cf text := ''; days_ numeric; bk text; buckets int[]; i int; lo int; hi int; bsel text := '';
  de text; dcols jsonb; dgrp text; n_unset bigint; n_bad bigint; cs text := ''; ct text := ''; allow_all boolean;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  def := public._r2_def(p_key);
  if def is null then raise exception 'unknown_report'; end if;
  if not public._r2_ok(p_key) then raise exception 'not allowed'; end if;
  flt := case when p_filters is not null and jsonb_typeof(p_filters) = 'object' then p_filters else '{}'::jsonb end;
  cost_ok := public.rpt_cost_ok();
  eff := public._r2_locs(flt);
  select count(*) into nloc from public.locations;
  if cardinality(public._r2_locs('{}'::jsonb)) < nloc then notes := notes || jsonb_build_array(jsonb_build_object('code', 'location_scope')); end if;
  if cardinality(eff) = 0 then notes := notes || jsonb_build_array(jsonb_build_object('code', 'no_location', 'text_en', 'No location is open to you', 'text_bn', 'কোনো লোকেশন আপনার জন্য খোলা নেই')); end if;
  pgsize := least(greatest(coalesce(public.rule_num('report_page_size'), 50), 10), 200)::int;
  off := (pg - 1) * pgsize; lim := greatest(least(pgsize, cap - off), 0);
  -- unknown filter keys are reported, never used
  for g in select jsonb_object_keys(flt) loop
    if g in ('from', 'to', 'preset', 'compare_mode') or jsonb_typeof(flt -> g) = 'null' then continue; end if;
    if not (def -> 'allow' @> to_jsonb(g)) then notes := notes || jsonb_build_array(jsonb_build_object('code', 'filter_ignored', 'what', left(g, 40))); end if;
  end loop;
  cat := case when def -> 'allow' @> '"categories"' then public.rpt_arr_text(flt -> 'categories') end;

  if coalesce((def ->> 'nodate')::int, 0) = 0 then
    preset := flt ->> 'preset';
    if preset is not null then
      pr := public.report_presets() -> preset;
      if pr is null or jsonb_typeof(pr) = 'null' then
        return jsonb_build_object('report', p_key, 'columns', '[]'::jsonb, 'rows', '[]'::jsonb, 'totals', null, 'compare', null, 'has_more', false, 'data_needed', true,
          'page', jsonb_build_object('n', pg, 'size', pgsize, 'groups', 0, 'cap', cap),
          'notes', jsonb_build_array(jsonb_build_object('code', 'data_needed', 'what', left(preset, 30), 'text_en', 'Unknown date preset', 'text_bn', 'তারিখের প্রিসেটের নাম ভুল')));
      end if;
      d1 := (pr ->> 'from')::date; d2 := (pr ->> 'to')::date;
    else
      d1 := public.rpt_date(flt ->> 'from'); d2 := public.rpt_date(flt ->> 'to');
      if d1 is null and d2 is null then d1 := date_trunc('month', today)::date; d2 := today;
        notes := notes || jsonb_build_array(jsonb_build_object('code', 'default_period', 'text_en', 'No period given: this month to date', 'text_bn', 'সময় দেওয়া হয়নি: এই মাসের আজ পর্যন্ত'));
      elsif d1 is null then d1 := d2; elsif d2 is null then d2 := today; end if;
    end if;
    if d2 < d1 or d2 - d1 > 365 then raise exception 'bad_range'; end if;
  end if;

  -- group (one dimension)
  if def ? 'dims' then
    dgrp := lower(btrim(coalesce(p_group, '')));
    if dgrp = '' then dgrp := def ->> 'gdef';
    elsif dgrp like '%,%' then
      notes := notes || jsonb_build_array(jsonb_build_object('code', 'group_ignored', 'what', left(split_part(dgrp, ',', 2), 30))); dgrp := split_part(dgrp, ',', 1);
    end if;
    if dgrp in ('none', 'total', '-') then dgrp := null;
    elsif dgrp is not null and not (def -> 'dims' @> to_jsonb(dgrp)) then
      notes := notes || jsonb_build_array(jsonb_build_object('code', 'group_ignored', 'what', left(dgrp, 30))); dgrp := def ->> 'gdef';
    end if;
  elsif p_group is not null and btrim(p_group) <> '' then
    notes := notes || jsonb_build_array(jsonb_build_object('code', 'group_ignored', 'what', left(p_group, 30)));
  end if;

  -- ============ the queries ============
  if p_key = 'item_slow' then
    if cat is not null then cf := format(' and it.category = any (%L::text[])', cat); end if;
    t := format($f$with s as (select f.item_id, sum(f.qty) as qty, sum(f.net) as net, count(distinct f.sale_id) as bills, max(f.day) as last_sold
        from public.sales_fact f where f.status = 'done' and f.item_id is not null and f.day between %L and %L and f.location_id = any (%L::int[]) group by 1)
      select it.code as item_code, it.name_bn as item_name, it.name_en as item_name_en, coalesce(it.category, '(none)') as category,
        coalesce(round(s.qty, 3), 0) as qty, coalesce(round(s.net, 2), 0) as net, coalesce(s.bills, 0) as bills, s.last_sold
      from public.items it left join s on s.item_id = it.id
      where it.is_active and it.sellable and it.retired_at is null%s$f$, d1, d2, eff, cf);
    tot := 'count(*) as items, count(*) filter (where qty = 0) as unsold_items, coalesce(sum(net), 0) as net';
    cols := '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["category","ক্যাটাগরি","Category","text"],["qty","বিক্রি পরিমাণ","Qty sold","num"],["net","বিক্রি","Sales","money"],["bills","বিল","Bills","int"],["last_sold","শেষ বিক্রি","Last sold","date"]]';
    notes := notes || jsonb_build_array(jsonb_build_object('code', 'info', 'text_en', 'Active sellable items with no sale in the period show 0. Smallest quantity first.', 'text_bn', 'এই সময়ে বিক্রি না হওয়া চালু আইটেম ০ দেখাবে। কম বিক্রি আগে।'));

  elsif p_key = 'stock_low' or p_key = 'stock_balance' then
    if cat is not null then cf := format(' and it.category = any (%L::text[])', cat); end if;
    if p_key = 'stock_low' then
      cs := case when cost_ok then ', round(greatest(it.min_stock - b.qty, 0) * b.avg_cost, 2) as reorder_value' else '' end;
      t := format($f$select it.code as item_code, it.name_bn as item_name, it.name_en as item_name_en, coalesce(it.category, '(none)') as category, l.id as location_id,
          l.name_bn as location_bn, l.name_en as location_en, b.qty, it.min_stock, round(it.min_stock - b.qty, 3) as short_by, it.unit%s
        from public.stock_balance b join public.items it on it.id = b.item_id join public.locations l on l.id = b.location_id
        where b.location_id = any (%L::int[]) and it.is_active and it.min_stock is not null and b.qty <= it.min_stock%s$f$, cs, eff, cf);
      tot := 'count(*) as lines, count(*) filter (where qty <= 0) as at_zero' || case when cost_ok then ', sum(reorder_value) as reorder_value' else '' end;
      cols := '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["category","ক্যাটাগরি","Category","text"],["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["qty","আছে","On hand","num"],["min_stock","ন্যূনতম","Minimum","num"],["short_by","ঘাটতি","Short by","num"],["unit","একক","Unit","text"]]';
      select count(*) into n_unset from public.items it where it.is_active and it.tracked and it.min_stock is null;
      if n_unset > 0 then notes := notes || jsonb_build_array(jsonb_build_object('code', 'data_needed', 'what', 'min_stock', 'text_en', n_unset || ' tracked items have no minimum set, so they cannot be checked', 'text_bn', n_unset || 'টি ট্র্যাক করা আইটেমে ন্যূনতম স্টক বসানো নেই, তাই যাচাই হয়নি')); end if;
    else
      cs := case when cost_ok then ', b.avg_cost, round(b.qty * b.avg_cost, 2) as value' else '' end;
      t := format($f$select it.code as item_code, it.name_bn as item_name, it.name_en as item_name_en, coalesce(it.category, '(none)') as category, l.id as location_id,
          l.name_bn as location_bn, l.name_en as location_en, b.qty, it.unit, it.min_stock,
          case when it.min_stock is null then 'no_min' when b.qty <= it.min_stock then 'low' else 'ok' end as state%s
        from public.stock_balance b join public.items it on it.id = b.item_id join public.locations l on l.id = b.location_id
        where b.location_id = any (%L::int[]) and it.is_active%s$f$, cs, eff, cf);
      tot := 'count(*) as lines, count(*) filter (where state = ''low'') as low_lines, count(*) filter (where state = ''no_min'') as no_min_lines' || case when cost_ok then ', sum(value) as value' else '' end;
      cols := '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["category","ক্যাটাগরি","Category","text"],["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["qty","আছে","On hand","num"],["unit","একক","Unit","text"],["min_stock","ন্যূনতম","Minimum","num"],["state","অবস্থা","State","text"]]';
    end if;
    if cost_ok then
      cols := cols || case when p_key = 'stock_low' then '[["reorder_value","পূরণের আনুমানিক খরচ","Approx. cost to refill","money"]]'::jsonb
                           else '[["avg_cost","গড় খরচ","Avg cost","money"],["value","মূল্য","Value","money"]]'::jsonb end;
    else notes := notes || jsonb_build_array(jsonb_build_object('code', 'cost_hidden')); end if;

  elsif p_key = 'wastage' then
    dcols := case dgrp when 'item' then '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["unit","একক","Unit","text"]]'
                       when 'location' then '[["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"]]'
                       when 'day' then '[["day","দিন","Day","date"]]'
                       when 'reason' then '[["reason","","","id"],["reason_bn","কারণ","Reason","text"],["reason_en","Reason (EN)","Reason (EN)","text"]]'
                       else '[]' end::jsonb;
    cs := case when cost_ok then ', round(sum(w.qty * sl.unit_cost) filter (where sl.unit_cost is not null), 2) as value, count(*) filter (where sl.unit_cost is null) as uncosted_entries' else '' end;
    t := format($f$select %s count(*) as entries%s%s
      from public.stock_wastage w join public.items it on it.id = w.item_id join public.locations l on l.id = w.location_id
        left join public.option_lists o on o.list_code = 'wastage_reasons' and o.value_code = w.reason_code
        left join public.stock_ledger sl on sl.id = w.ledger_id
      where (w.made_at at time zone 'Asia/Dhaka')::date between %L and %L and w.location_id = any (%L::int[])%s$f$,
      case dgrp when 'item' then 'it.code as item_code, it.name_bn as item_name, it.name_en as item_name_en, it.unit as unit,'
                when 'location' then 'l.id as location_id, l.name_bn as location_bn, l.name_en as location_en,'
                when 'day' then '(w.made_at at time zone ''Asia/Dhaka'')::date as day,'
                when 'reason' then 'w.reason_code as reason, coalesce(o.label_bn, w.reason_code) as reason_bn, coalesce(o.label_en, w.reason_code) as reason_en,'
                else '' end,
      case when dgrp = 'item' then ', round(sum(w.qty), 3) as qty' else '' end, cs, d1, d2, eff,
      case dgrp when 'item' then ' group by it.id, it.code, it.name_bn, it.name_en, it.unit'
                when 'location' then ' group by l.id, l.name_bn, l.name_en'
                when 'day' then ' group by 1'
                when 'reason' then ' group by w.reason_code, o.label_bn, o.label_en'
                else '' end);
    tot := 'sum(entries) as entries' || case when cost_ok then ', sum(value) as value, sum(uncosted_entries) as uncosted_entries' else '' end;
    cols := dcols || '[["entries","বার","Entries","int"]]'::jsonb || case when dgrp = 'item' then '[["qty","পরিমাণ","Qty","num"]]'::jsonb else '[]'::jsonb end;
    if cost_ok then cols := cols || '[["value","মূল্য (খরচ জানা অংশে)","Value (costed part)","money"],["uncosted_entries","খরচ অজানা সারি","Entries with no cost","int"]]'::jsonb;
    else notes := notes || jsonb_build_array(jsonb_build_object('code', 'cost_hidden')); end if;
    if dgrp is distinct from 'item' then notes := notes || jsonb_build_array(jsonb_build_object('code', 'info', 'text_en', 'Quantity is shown only per item (units differ between items).', 'text_bn', 'পরিমাণ শুধু আইটেম অনুযায়ী দেখানো হয় (আইটেমের একক আলাদা)।')); end if;

  elsif p_key = 'expiry_soon' then
    days_ := public.rule_num('report_expiry_soon_days');
    if cat is not null then cf := format(' and it.category = any (%L::text[])', cat); end if;
    cs := case when cost_ok then ', round(b.qty_remaining * sb.avg_cost, 2) as value' else '' end;
    t := format($f$select it.code as item_code, it.name_bn as item_name, it.name_en as item_name_en, l.id as location_id, l.name_bn as location_bn, l.name_en as location_en,
        (b.made_at at time zone 'Asia/Dhaka')::date as made_on, (b.expires_at at time zone 'Asia/Dhaka')::date as expires_on,
        (b.expires_at at time zone 'Asia/Dhaka')::date - %L::date as days_left, b.qty_remaining as qty, it.unit,
        case when (b.expires_at at time zone 'Asia/Dhaka')::date < %L::date then 'expired' else 'soon' end as state%s
      from public.stock_batches b join public.items it on it.id = b.item_id join public.locations l on l.id = b.location_id
        left join public.stock_balance sb on sb.item_id = b.item_id and sb.location_id = b.location_id
      where b.qty_remaining > 0 and b.expires_at is not null and b.location_id = any (%L::int[])
        and (b.expires_at at time zone 'Asia/Dhaka')::date <= %L::date + %s%s$f$,
      today, today, cs, eff, today, case when days_ is null then '-1' else (days_::int)::text end, cf);
    tot := 'count(*) as batches, count(*) filter (where state = ''expired'') as expired_batches' || case when cost_ok then ', sum(value) as value' else '' end;
    cols := '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["made_on","তৈরি","Made","date"],["expires_on","মেয়াদ শেষ","Expires","date"],["days_left","বাকি দিন","Days left","int"],["qty","পরিমাণ (বাকি)","Qty left","num"],["unit","একক","Unit","text"],["state","অবস্থা","State","text"]]';
    if cost_ok then cols := cols || '[["value","আনুমানিক মূল্য","Approx. value","money"]]'::jsonb; else notes := notes || jsonb_build_array(jsonb_build_object('code', 'cost_hidden')); end if;
    if days_ is null then notes := notes || jsonb_build_array(jsonb_build_object('code', 'data_needed', 'what', 'report_expiry_soon_days', 'text_en', 'Set "days ahead" in Rules to also see batches that expire soon. Only batches already expired are listed.', 'text_bn', 'শিগগির শেষ হবে এমন ব্যাচ দেখতে নিয়মে দিনের সংখ্যা বসান। এখন শুধু মেয়াদ-শেষ ব্যাচ দেখাচ্ছে।')); end if;

  elsif p_key = 'transfers_gap' then
    t := format($f$select (x.sent_at at time zone 'Asia/Dhaka')::date as sent_day, lf.name_bn as from_bn, lf.name_en as from_en, lt.name_bn as to_bn, lt.name_en as to_en,
        it.code as item_code, it.name_bn as item_name, it.name_en as item_name_en, x.qty as sent_qty, x.received_qty,
        case when x.status = 'received' then round(x.qty - coalesce(x.received_qty, x.qty), 3) end as diff_qty, x.status, x.sent_staff, x.received_staff
      from public.stock_transfers x join public.items it on it.id = x.item_id join public.locations lf on lf.id = x.from_location_id join public.locations lt on lt.id = x.to_location_id
      where (x.sent_at at time zone 'Asia/Dhaka')::date between %L and %L and (x.from_location_id = any (%L::int[]) or x.to_location_id = any (%L::int[]))
        and x.status <> 'cancelled' and (x.status = 'sent' or coalesce(x.received_qty, x.qty) <> x.qty)$f$, d1, d2, eff, eff);
    tot := 'count(*) as transfers, count(*) filter (where status = ''sent'') as not_received, count(*) filter (where diff_qty <> 0) as short_received';
    cols := '[["sent_day","পাঠানো","Sent","date"],["from_bn","কোথা থেকে","From","text"],["from_en","From (EN)","From (EN)","text"],["to_bn","কোথায়","To","text"],["to_en","To (EN)","To (EN)","text"],["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],["sent_qty","পাঠানো পরিমাণ","Sent qty","num"],["received_qty","পৌঁছেছে","Received qty","num"],["diff_qty","পার্থক্য","Difference","num"],["status","অবস্থা","Status","text"],["sent_staff","পাঠিয়েছে","Sent by","text"],["received_staff","গ্রহণ করেছে","Received by","text"]]';

  elsif p_key = 'supplier_ageing' then
    allow_all := public._all_locs() and public.rpt_arr_int(flt -> 'locations') is null and public.rpt_arr_text(flt -> 'brands') is null;
    bk := public.rule_txt('report_aging_buckets');
    if bk is not null and bk ~ '^[0-9]{1,4}(,[0-9]{1,4}){0,5}$' then
      buckets := string_to_array(bk, ',')::int[];
      for i in 2..cardinality(buckets) loop if buckets[i] <= buckets[i - 1] then buckets := null; exit; end if; end loop;
    end if;
    cols := '[["supplier_id","","","id"],["supplier","সরবরাহকারী","Supplier","text"],["balance","মোট দেনা","Total payable","money"],["opening_part","শুরুর বাকি (তারিখ ছাড়া)","Opening balance part","money"]]';
    if buckets is not null and cardinality(buckets) > 0 then
      for i in 1..cardinality(buckets) + 1 loop
        lo := case when i = 1 then 0 else buckets[i - 1] + 1 end; hi := case when i <= cardinality(buckets) then buckets[i] end;
        bsel := bsel || format(', round(coalesce(sum(o.open_amt) filter (where o.bill_date is not null and (%L::date - o.bill_date) %s), 0), 2) as bucket_%s', today,
          case when hi is null then '>= ' || lo else 'between ' || lo || ' and ' || hi end, i);
        cols := cols || jsonb_build_array(jsonb_build_array('bucket_' || i, case when hi is null then lo || '+ দিন' else lo || '–' || hi || ' দিন' end, case when hi is null then lo || '+ days' else lo || '–' || hi || ' days' end, 'money'));
      end loop;
    else notes := notes || jsonb_build_array(jsonb_build_object('code', 'data_needed', 'what', 'report_aging_buckets', 'text_en', 'Set the ageing buckets (days) in Rules to split by age', 'text_bn', 'বয়স ভাগ করতে নিয়মে দিনের ভাগ বসান')); end if;
    cols := cols || '[["oldest_days","সবচেয়ে পুরনো (দিন)","Oldest (days)","int"],["credit_days","বাকির মেয়াদ (দিন)","Credit days","int"],["overdue","মেয়াদ পার","Past credit days","money"]]'::jsonb;
    t := format($f$with o as (select * from public._sup_open(null) where open_amt > 0)
      select s.id as supplier_id, s.name as supplier, round(sum(o.open_amt), 2) as balance, round(coalesce(sum(o.open_amt) filter (where o.bill_date is null), 0), 2) as opening_part%s,
        max(%L::date - o.bill_date) as oldest_days, s.credit_days,
        round(coalesce(sum(o.open_amt) filter (where s.credit_days is not null and o.bill_date is not null and o.bill_date + s.credit_days < %L::date), 0), 2) as overdue
      from o join public.suppliers s on s.id = o.supplier_id
      where o.location_id = any (%L::int[]) or (o.location_id is null and %L::boolean)
      group by s.id, s.name, s.credit_days$f$, bsel, today, today, eff, allow_all);
    tot := 'count(*) as suppliers, sum(balance) as balance, sum(overdue) as overdue' || (select coalesce(string_agg(format(', sum(bucket_%s) as bucket_%s', n, n), ''), '') from generate_series(1, coalesce(cardinality(buckets), -1) + 1) n where buckets is not null);
    if not allow_all then notes := notes || jsonb_build_array(jsonb_build_object('code', 'info', 'text_en', 'Opening balances (no shop) are included only when all locations are selected', 'text_bn', 'শুরুর বাকি (দোকান ছাড়া) শুধু সব লোকেশন বাছা থাকলে ধরা হয়')); end if;

  elsif p_key = 'purchases_by_supplier' then
    de := case dgrp when 'supplier' then 's.id as supplier_id, s.name as supplier,' when 'location' then 'l.id as location_id, l.name_bn as location_bn, l.name_en as location_en,'
                    when 'day' then 'b.bill_date as day,' else '' end;
    t := format($f$select %s count(*) filter (where b.kind = 'bill') as bills, coalesce(sum(b.subtotal) filter (where b.kind = 'bill'), 0) as subtotal,
        coalesce(sum(b.discount) filter (where b.kind = 'bill'), 0) as discount, coalesce(sum(b.total) filter (where b.kind = 'bill'), 0) as total,
        coalesce(sum(b.paid) filter (where b.kind = 'bill'), 0) as paid, coalesce(sum(b.total - b.paid) filter (where b.kind = 'bill'), 0) as due,
        count(*) filter (where b.kind = 'return') as returns, coalesce(sum(b.total) filter (where b.kind = 'return'), 0) as returns_total
      from public.purchase_bills b join public.suppliers s on s.id = b.supplier_id join public.locations l on l.id = b.location_id
      where b.status = 'posted' and b.bill_date between %L and %L and b.location_id = any (%L::int[])%s$f$, de, d1, d2, eff,
      case dgrp when 'supplier' then ' group by s.id, s.name' when 'location' then ' group by l.id, l.name_bn, l.name_en' when 'day' then ' group by b.bill_date' else '' end);
    tot := 'sum(bills) as bills, sum(subtotal) as subtotal, sum(discount) as discount, sum(total) as total, sum(paid) as paid, sum(due) as due, sum(returns) as returns, sum(returns_total) as returns_total';
    cols := (case dgrp when 'supplier' then '[["supplier_id","","","id"],["supplier","সরবরাহকারী","Supplier","text"]]' when 'location' then '[["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"]]'
                       when 'day' then '[["day","দিন","Day","date"]]' else '[]' end)::jsonb
      || '[["bills","বিল","Bills","int"],["subtotal","সাবটোটাল","Subtotal","money"],["discount","ছাড়","Discount","money"],["total","মোট","Total","money"],["paid","পরিশোধ","Paid","money"],["due","বাকি","Due","money"],["returns","রিটার্ন","Returns","int"],["returns_total","রিটার্নের টাকা","Returns amount","money"]]'::jsonb;

  elsif p_key = 'expense_by_head' then
    t := format($f$select %s count(*) filter (where x.amt is not null) as lines, coalesce(sum(x.amt), 0) as amount,
        count(*) filter (where x.amt is not null and x.rcpt = 'no') as no_receipt_lines, coalesce(sum(x.amt) filter (where x.rcpt = 'no'), 0) as no_receipt_amount,
        round(100 * coalesce(sum(x.amt), 0) / nullif(sum(sum(x.amt)) over (), 0), 2) as share_pct, count(*) filter (where x.amt is null) as skipped_lines
      from (select e.id, e.location_id, e.entry_date, public._r2_num(ln -> 'amount') as amt, ln ->> 'receipt' as rcpt, coalesce(nullif(btrim(ln ->> 'head'), ''), '-') as head
            from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) ln
            where e.form_code = '10-2' and e.status in ('submitted', 'approved') and e.entry_date between %L and %L and e.location_id = any (%L::int[])) x
        join public.locations l on l.id = x.location_id left join public.option_lists o on o.list_code = 'expense_heads' and o.value_code = x.head
      %s$f$,
      case dgrp when 'head' then 'x.head as head, coalesce(o.label_bn, x.head) as head_bn, coalesce(o.label_en, x.head) as head_en,'
                when 'location' then 'l.id as location_id, l.name_bn as location_bn, l.name_en as location_en,'
                when 'day' then 'x.entry_date as day,' else '' end, d1, d2, eff,
      case dgrp when 'head' then 'group by x.head, o.label_bn, o.label_en' when 'location' then 'group by l.id, l.name_bn, l.name_en' when 'day' then 'group by x.entry_date' else '' end);
    tot := 'sum(lines) as lines, sum(amount) as amount, sum(no_receipt_lines) as no_receipt_lines, sum(no_receipt_amount) as no_receipt_amount, sum(skipped_lines) as skipped_lines';
    cols := (case dgrp when 'head' then '[["head","","","id"],["head_bn","খাত","Head","text"],["head_en","Head (EN)","Head (EN)","text"]]' when 'location' then '[["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"]]'
                       when 'day' then '[["day","দিন","Day","date"]]' else '[]' end)::jsonb
      || '[["lines","লাইন","Lines","int"],["amount","টাকা","Amount","money"],["share_pct","অংশ %","Share %","pct"],["no_receipt_lines","রসিদ ছাড়া লাইন","Lines without receipt","int"],["no_receipt_amount","রসিদ ছাড়া টাকা","Amount without receipt","money"],["skipped_lines","পড়া যায়নি এমন লাইন","Unreadable lines","int"]]'::jsonb;
    notes := notes || jsonb_build_array(jsonb_build_object('code', 'info', 'text_en', 'From submitted and approved expense vouchers (10-2). Drafts are not counted. A line whose amount is not a plain number is skipped and counted.', 'text_bn', 'জমা ও অনুমোদিত ব্যয় ভাউচার (১০-২) থেকে। খসড়া ধরা হয়নি। অঙ্ক পড়া না গেলে লাইন বাদ ও গণনা।'));

  elsif p_key = 'cash_short_over' then
    t := format($f$select %s count(*) as sheets, count(*) filter (where x.so < 0) as short_sheets, count(*) filter (where x.so > 0) as over_sheets,
        coalesce(-sum(x.so) filter (where x.so < 0), 0) as short_amount, coalesce(sum(x.so) filter (where x.so > 0), 0) as over_amount, coalesce(sum(x.so), 0) as net,
        coalesce(max(abs(x.so)), 0) as worst
      from (select e.id, e.location_id, e.entry_date, coalesce(nullif(btrim(e.created_staff), ''), '-') as staff,
              coalesce((select sum(public._r2_num(f -> 'amount')) from jsonb_array_elements(case when jsonb_typeof(e.flags) = 'array' then e.flags else '[]'::jsonb end) f where f ->> 'code' = 'cash_short_over'), 0) as so
            from public.entries e where e.form_code = '14-1' and e.status in ('submitted', 'approved') and e.entry_date between %L and %L and e.location_id = any (%L::int[])) x
        join public.locations l on l.id = x.location_id
      %s$f$,
      case dgrp when 'location' then 'l.id as location_id, l.name_bn as location_bn, l.name_en as location_en,' when 'day' then 'x.entry_date as day,' when 'staff' then 'x.staff as staff,' else '' end, d1, d2, eff,
      case dgrp when 'location' then 'group by l.id, l.name_bn, l.name_en' when 'day' then 'group by x.entry_date' when 'staff' then 'group by x.staff' else '' end);
    tot := 'sum(sheets) as sheets, sum(short_sheets) as short_sheets, sum(over_sheets) as over_sheets, sum(short_amount) as short_amount, sum(over_amount) as over_amount, sum(net) as net, max(worst) as worst';
    cols := (case dgrp when 'location' then '[["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"]]' when 'day' then '[["day","দিন","Day","date"]]'
                       when 'staff' then '[["staff","কর্মী (শিট লেখক)","Staff (sheet writer)","text"]]' else '[]' end)::jsonb
      || '[["sheets","শিট","Sheets","int"],["short_sheets","কম হওয়া শিট","Sheets short","int"],["over_sheets","বেশি হওয়া শিট","Sheets over","int"],["short_amount","কম (মোট)","Short (total)","money"],["over_amount","বেশি (মোট)","Over (total)","money"],["net","নিট (বেশি − কম)","Net (over − short)","money"],["worst","সবচেয়ে বড় পার্থক্য","Largest gap","money"]]'::jsonb;
    notes := notes || jsonb_build_array(jsonb_build_object('code', 'info', 'text_en', 'Taken from the short/over flag of each daily showroom sheet (14-1), worked out on the phone when the sheet was saved. A sheet with an exact match carries no flag and counts as 0.', 'text_bn', 'প্রতিটি দৈনিক শোরুম শিটের (১৪-১) কম/বেশি চিহ্ন থেকে, যা ফোনে শিট সেভের সময় হিসাব হয়েছিল। ঠিকঠাক মিললে চিহ্ন থাকে না, ০ ধরা হয়।'));

  elsif p_key = 'attendance_summary' then
    t := format($f$select %s count(distinct x.id) as sheets, coalesce(sum(x.present), 0) as present, coalesce(sum(x.late), 0) as late, coalesce(sum(x.absent), 0) as absent,
        coalesce(sum(x.leave_unpaid), 0) as leave_unpaid, coalesce(sum(x.leave_paid), 0) as leave_paid, coalesce(sum(x.ot_hours), 0) as ot_hours
      from (select e.id, e.location_id, btrim(r ->> 'name') as person, public._r2_num(r -> 'present') as present, public._r2_num(r -> 'late') as late, public._r2_num(r -> 'absent') as absent,
              public._r2_num(r -> 'leave_unpaid') as leave_unpaid, public._r2_num(r -> 'leave_paid') as leave_paid, public._r2_num(r -> 'ot_hours') as ot_hours
            from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'staff') = 'array' then e.data -> 'staff' else '[]'::jsonb end) r
            where e.form_code = '02-1' and e.status in ('submitted', 'approved') and e.entry_date between %L and %L and e.location_id = any (%L::int[])
              and btrim(coalesce(r ->> 'name', '')) <> '') x
        join public.locations l on l.id = x.location_id
      %s$f$,
      case dgrp when 'person' then 'x.person as person,' when 'location' then 'l.id as location_id, l.name_bn as location_bn, l.name_en as location_en,' else '' end, d1, d2, eff,
      case dgrp when 'person' then 'group by x.person' when 'location' then 'group by l.id, l.name_bn, l.name_en' else '' end);
    tot := 'sum(present) as present, sum(late) as late, sum(absent) as absent, sum(leave_unpaid) as leave_unpaid, sum(leave_paid) as leave_paid, sum(ot_hours) as ot_hours';
    cols := (case dgrp when 'person' then '[["person","কর্মী","Person","text"]]' when 'location' then '[["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"]]' else '[]' end)::jsonb
      || '[["sheets","শিট","Sheets","int"],["present","উপস্থিত","Present","num"],["late","দেরি","Late","num"],["absent","অনুপস্থিত","Absent","num"],["leave_unpaid","বিনা বেতনের ছুটি","Unpaid leave","num"],["leave_paid","সবেতন ছুটি","Paid leave","num"],["ot_hours","ওভারটাইম ঘণ্টা","Overtime hours","num"]]'::jsonb;
    notes := notes || jsonb_build_array(jsonb_build_object('code', 'info', 'text_en', 'From monthly attendance registers (02-1) dated inside the period. Same person on two sheets is added up by name.', 'text_bn', 'সময়ের মধ্যে তারিখের মাসিক হাজিরা রেজিস্টার (০২-১) থেকে। একই নাম দুই শিটে থাকলে যোগ হয়।'));

  elsif p_key = 'exceptions_summary' then
    t := format($f$select %s count(*) as total, count(*) filter (where x.status = 'open') as open, count(*) filter (where x.status = 'resolved') as resolved,
        count(*) filter (where x.level = 'red') as red, count(*) filter (where x.level = 'yellow') as yellow,
        round(avg(extract(epoch from (x.resolved_at - x.created_at)) / 3600.0) filter (where x.status = 'resolved' and x.resolved_at is not null), 1) as avg_hours_to_resolve
      from public.exceptions x join public.locations l on l.id = x.location_id
      where x.entry_date between %L and %L and x.location_id = any (%L::int[])
      %s$f$,
      case dgrp when 'form' then 'x.form_code as form,' when 'location' then 'l.id as location_id, l.name_bn as location_bn, l.name_en as location_en,' when 'flag' then 'x.flag_code as flag,'
                when 'level' then 'x.level as level,' when 'day' then 'x.entry_date as day,' else '' end, d1, d2, eff,
      case dgrp when 'form' then 'group by x.form_code' when 'location' then 'group by l.id, l.name_bn, l.name_en' when 'flag' then 'group by x.flag_code' when 'level' then 'group by x.level' when 'day' then 'group by x.entry_date' else '' end);
    tot := 'sum(total) as total, sum(open) as open, sum(resolved) as resolved, sum(red) as red, sum(yellow) as yellow';
    cols := (case dgrp when 'form' then '[["form","ফর্ম","Form","text"]]' when 'location' then '[["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"]]'
                       when 'flag' then '[["flag","ধরন","Type","text"]]' when 'level' then '[["level","মাত্রা","Level","text"]]' when 'day' then '[["day","দিন (শিটের)","Day (of sheet)","date"]]' else '[]' end)::jsonb
      || '[["total","মোট","Total","int"],["open","খোলা","Open","int"],["resolved","সমাধান","Resolved","int"],["red","লাল","Red","int"],["yellow","হলুদ","Yellow","int"],["avg_hours_to_resolve","গড় সমাধানের ঘণ্টা","Avg hours to resolve","num"]]'::jsonb;
  end if;

  -- columns -> response shape, sort whitelist
  for c in select * from jsonb_array_elements(cols) loop
    outc := outc || jsonb_build_array(jsonb_build_object('key', c ->> 0, 'label_bn', c ->> 1, 'label_en', c ->> 2, 'type', c ->> 3,
      'role', case when c ->> 3 in ('money', 'int', 'num', 'pct') then 'measure' else 'dim' end, 'cost', (c ->> 0) in ('value', 'avg_cost', 'reorder_value', 'uncosted_entries')));
    allowkeys := allowkeys || (c ->> 0);
  end loop;
  sraw := lower(btrim(coalesce(p_sort, '')));
  if sraw <> '' then
    if left(sraw, 1) = '-' then sd := 'desc'; sraw := substr(sraw, 2); end if;
    sparts := regexp_split_to_array(sraw, '[: ]+');
    if sparts[1] = any (allowkeys) then sk := sparts[1]; sd := coalesce(sd, case when sparts[2] = 'desc' then 'desc' else 'asc' end);
    else notes := notes || jsonb_build_array(jsonb_build_object('code', 'sort_ignored', 'what', left(sparts[1], 30))); end if;
  end if;
  if sk is null then
    dsort := def ->> 'sort';
    if dsort = '@dim' or split_part(dsort, ':', 1) <> all (allowkeys) then
      sk := coalesce((select c2 ->> 0 from jsonb_array_elements(cols) c2 where c2 ->> 3 <> 'id' limit 1), allowkeys[1]); sd := 'asc';
    else sk := split_part(dsort, ':', 1); sd := split_part(dsort, ':', 2); end if;
  end if;
  ordr := quote_ident(sk) || ' ' || case when sd = 'desc' then 'desc' else 'asc' end || ' nulls last, 1';

  execute format('select coalesce(jsonb_agg(to_jsonb(x) - ''_n'' - ''_rn'' order by x._rn), ''[]''::jsonb), coalesce(max(x._n), 0) from (select q.*, count(*) over () as _n, row_number() over (order by %s) as _rn from (%s) q order by %s limit %s offset %s) x',
    ordr, t, ordr, lim, off) into rows_, ngroups;
  execute format('select to_jsonb(x) from (select %s from (%s) q) x', tot, t) into totals_;
  hm := (off + pgsize) < least(ngroups, cap);
  if ngroups > cap then notes := notes || jsonb_build_array(jsonb_build_object('code', 'truncated', 'cap', cap, 'groups', ngroups)); end if;
  if jsonb_array_length(rows_) = 0 or ngroups = 0 then
    dn := true;
    notes := notes || jsonb_build_array(jsonb_build_object('code', 'no_data', 'text_en', 'Data needed: nothing matches this period / filters', 'text_bn', 'তথ্য দরকার: এই সময়/ফিল্টারে কিছু নেই'));
  end if;
  return jsonb_build_object('report', p_key, 'columns', outc, 'rows', rows_, 'totals', totals_, 'compare', null,
    'page', jsonb_build_object('n', pg, 'size', pgsize, 'groups', ngroups, 'cap', cap), 'has_more', coalesce(hm, false), 'notes', notes, 'data_needed', dn,
    'meta', jsonb_build_object('from', d1, 'to', d2, 'group', case when dgrp is null then '[]'::jsonb else jsonb_build_array(dgrp) end, 'sort', sk, 'dir', sd, 'cost_shown', cost_ok, 'today', today));
end $$;

-- ---------- export log ----------
create or replace function public.log_report_export2(p_key text, p_kind text, p_filters jsonb, p_rows int) returns void
language plpgsql security definer set search_path = public as $$
declare sid text; f jsonb := coalesce(p_filters, '{}'::jsonb);
begin
  if not public.is_active() or not (public.is_owner() or public.rpt_grant('export_data')) then raise exception 'not allowed'; end if;
  if p_key is null or not (p_key = any (public._r2_keys())) then raise exception 'unknown_report'; end if;
  if p_kind is null or lower(p_kind) !~ '^[a-z0-9_]{1,20}$' then raise exception 'bad_kind'; end if;
  if length(f::text) > 4000 then f := jsonb_build_object('truncated', true); end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'export', 'report', p_key, jsonb_build_object('kind', lower(p_kind), 'rows', least(greatest(coalesce(p_rows, 0), 0), 100000000), 'filters', f));
end $$;

-- ---------- privileges ----------
revoke all on function public._r2_num(jsonb), public._r2_locs(jsonb), public._r2_def(text), public._r2_keys(), public._r2_dimlab(text), public._r2_ok(text),
  public.report_catalog2(), public.report_run2(text, jsonb, text, text, int), public.log_report_export2(text, text, jsonb, int) from public, anon, authenticated;
grant execute on function public.report_catalog2(), public.report_run2(text, jsonb, text, text, int), public.log_report_export2(text, text, jsonb, int) to authenticated;

notify pgrst, 'reload schema';
