-- ============================================================
-- Phase 48 - P1 slice 1: the "one record + locked shadow copy" engine and the owner path switches.
-- Run AFTER phase47. Additive + idempotent (paste twice = no error). No existing table or function is changed; nothing is posted by this file.
--
-- Rule: every transaction has ONE primary record. The other path (quick tab <-> formal paper form) gets a linked, locked "shadow copy".
--       A shadow is never counted: reports, the day book and the journal read the primary only. Posting stays unique on (source_type, source_id).
--
--   path_domains   the 7 places where two paths exist (payroll, stock issue / transfer / count, production, expense, owner money) with labels + default.
--   path_switch    the OWNER's choice per domain (and optionally per place): a = path A only | b = path B only | either = both open (first one wins, the
--                  other becomes the shadow) | locked = no new records.   location_id 0 = all places.
--   shadow_links   primary record <-> shadow copy (pending until the second path is filled/confirmed; confirmed; void). Append-only trail.
--   Functions: path_mode, path_allowed, path_guard (used by later slices inside the posting functions), path_switch_set / path_switches (owner),
--              shadow_link_add / shadow_confirm / shadow_void (internal), is_shadow, shadow_report, shadow_count_once_check (read-only).
-- ============================================================

-- ---------- 1. domains ----------
create table if not exists public.path_domains (
  domain text primary key check (domain ~ '^[a-z_]{2,30}$'),
  a_bn text not null, a_en text not null,                    -- path A (app / quick / screen)
  b_bn text not null, b_en text not null,                    -- path B (formal paper form / second screen)
  default_mode text not null check (default_mode in ('a', 'b', 'either', 'locked')),
  note_bn text, note_en text,
  sort int not null default 0
);
insert into public.path_domains (domain, a_bn, a_en, b_bn, b_en, default_mode, note_bn, note_en, sort) values
 ('payroll',       'অ্যাপে বেতন (পে-রোল)',      'App payroll (runs / payments)',   'ফর্ম 02-2 (মাসিক বেতন শিট)',   'Form 02-2 (monthly salary sheet)',     'either',
  'দুটোই খোলা; অ্যাপে এন্ট্রি হলে 02-2 লক হয়, গোপন শ্যাডো কপি থাকে।', 'Both open; once app payroll is entered, 02-2 is locked and kept as a shadow copy.', 10),
 ('stock_issue',   'স্টক স্ক্রিনে ইস্যু',         'Stock screen issue',               'ফর্ম 04-2 (ইস্যু স্লিপ)',        'Form 04-2 (issue slip)',                'a',
  'ডিফল্ট: স্ক্রিন মূল, ফর্ম রেফারেন্স।', 'Default: screen is primary, form is a reference.', 20),
 ('stock_transfer','স্টক স্ক্রিনে ট্রান্সফার',    'Stock screen transfer',            'ফর্ম 03-1 (ট্রান্সফার চালান)',   'Form 03-1 (transfer challan)',          'a',
  'ডিফল্ট: স্ক্রিন মূল, ফর্ম রেফারেন্স।', 'Default: screen is primary, form is a reference.', 30),
 ('stock_count',   'স্টক স্ক্রিনে গণনা',          'Stock screen count',               'ফর্ম 04-3 (স্টক কাউন্ট শিট)',    'Form 04-3 (stock count sheet)',         'a',
  'ডিফল্ট: স্ক্রিন মূল, ফর্ম রেফারেন্স।', 'Default: screen is primary, form is a reference.', 40),
 ('production',    'রেসিপি প্রোডাকশন রান',        'Recipe production run',            'ফর্ম 05-1 (কারখানা দৈনিক শিট)',  'Form 05-1 (factory daily sheet)',       'a',
  'ডিফল্ট: রান মূল, 05-1 রেফারেন্স।', 'Default: the run is primary, 05-1 is a reference.', 50),
 ('expense',       'ডে-বুকে দ্রুত খরচ এন্ট্রি',    'Day-book quick expense',           'ফর্ম 10-2 (ব্যয় ভাউচার)',       'Form 10-2 (expense voucher)',           'either',
  'দিনের শেষে দ্রুত এন্ট্রির 10-2 শ্যাডো কপি; এক ক্লিকে নিশ্চিত।', 'Quick entries get a 10-2 shadow at day end; one click confirms.', 60),
 ('owner_money',   'পার্টনার ক্যাপিটাল',          'Partner capital',                  'ক্যাশ মুভ (মালিকের জমা/উত্তোলন)', 'Cash move (owner top-up / draw)',       'a',
  'ডিফল্ট: পার্টনার ক্যাপিটাল মূল, ক্যাশ মুভ শ্যাডো।', 'Default: partner capital is primary, the cash move gets the shadow.', 70)
on conflict (domain) do nothing;

-- ---------- 2. the owner's switch ----------
create table if not exists public.path_switch (
  domain text not null references public.path_domains(domain),
  location_id int not null default 0 check (location_id >= 0),     -- 0 = every place
  mode text not null check (mode in ('a', 'b', 'either', 'locked')),
  note text check (note is null or length(note) <= 300),
  updated_by uuid, updated_at timestamptz not null default now(),
  primary key (domain, location_id)
);
drop trigger if exists audit_path_switch on public.path_switch;
create trigger audit_path_switch after insert or update on public.path_switch for each row execute function public.log_change('domain,location_id');

-- ---------- 3. the shadow trail ----------
create table if not exists public.shadow_links (
  id bigint generated always as identity primary key,
  domain text not null references public.path_domains(domain),
  location_id int not null default 0,
  primary_type text not null check (length(primary_type) between 1 and 40),      -- e.g. payroll_runs, entries:02-2, partner_capital
  primary_id text not null check (length(primary_id) between 1 and 80),
  shadow_type text not null check (length(shadow_type) between 1 and 40),
  shadow_id text check (shadow_id is null or length(shadow_id) between 1 and 80),  -- null while the shadow is only pending
  state text not null default 'pending' check (state in ('pending', 'confirmed', 'void')),
  locked boolean not null default true,
  note text check (note is null or length(note) <= 300),
  created_by uuid, created_at timestamptz not null default now(),
  confirmed_by uuid, confirmed_at timestamptz
);
-- one shadow of a kind per primary; a record can be the shadow of ONE primary only (so it can never be counted twice)
create unique index if not exists shadow_one_per_primary on public.shadow_links (domain, primary_type, primary_id, shadow_type) where state <> 'void';
create unique index if not exists shadow_record_once on public.shadow_links (shadow_type, shadow_id) where shadow_id is not null and state <> 'void';
create index if not exists shadow_by_state on public.shadow_links (domain, state, location_id);
-- a primary can never also be a shadow (checked in shadow_link_add); the trail itself is append-only except pending -> confirmed -> void
create or replace function public._shadow_ro() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' and (to_jsonb(new) - 'state' - 'shadow_id' - 'confirmed_by' - 'confirmed_at' - 'note') = (to_jsonb(old) - 'state' - 'shadow_id' - 'confirmed_by' - 'confirmed_at' - 'note')
     and ((old.state = 'pending' and new.state in ('confirmed', 'void')) or (old.state = 'confirmed' and new.state = 'void') or (old.state = new.state and old.shadow_id is null)) then return new; end if;
  raise exception 'append_only: shadow_links is a trail, it cannot be changed or deleted (void it instead)';
end $$;
drop trigger if exists shadow_ro on public.shadow_links;
create trigger shadow_ro before update or delete on public.shadow_links for each row execute function public._shadow_ro();
drop trigger if exists audit_shadow_links on public.shadow_links;
create trigger audit_shadow_links after insert or update on public.shadow_links for each row execute function public.log_change('id');

do $$
declare t text;
begin
  foreach t in array array['path_domains', 'path_switch', 'shadow_links'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_sel', t);
  end loop;
end $$;
create policy path_domains_sel on public.path_domains for select to authenticated using (public.is_active());
create policy path_switch_sel on public.path_switch for select to authenticated using (public.is_active());
create policy shadow_links_sel on public.shadow_links for select to authenticated using (public.is_owner() or (location_id > 0 and public.can_loc(location_id)));

-- ---------- 4. reading the switch ----------
create or replace function public.path_mode(p_domain text, p_loc int default 0) returns text
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select s.mode from public.path_switch s where s.domain = p_domain and s.location_id = coalesce(p_loc, 0) and coalesce(p_loc, 0) > 0),
    (select s.mode from public.path_switch s where s.domain = p_domain and s.location_id = 0),
    (select d.default_mode from public.path_domains d where d.domain = p_domain));
$$;

-- may this path ('a' | 'b') create a new primary record now?
create or replace function public.path_allowed(p_domain text, p_loc int, p_path text) returns boolean
language sql stable security definer set search_path = public as $$
  select case public.path_mode(p_domain, p_loc) when 'either' then p_path in ('a', 'b') when 'a' then p_path = 'a' when 'b' then p_path = 'b' else false end;
$$;

-- used INSIDE posting functions of later slices: refuse when the owner has closed this path
create or replace function public.path_guard(p_domain text, p_loc int, p_path text) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if p_path not in ('a', 'b') then raise exception 'bad_path'; end if;
  if not exists (select 1 from public.path_domains where domain = p_domain) then raise exception 'unknown_domain'; end if;
  if not public.path_allowed(p_domain, p_loc, p_path) then raise exception 'path_locked: % path % is closed here (owner switch = %)', p_domain, p_path, public.path_mode(p_domain, p_loc); end if;
end $$;

-- ---------- 5. owner sets the switch ----------
create or replace function public.path_switch_set(p_domain text, p_loc int, p_mode text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare loc int := coalesce(p_loc, 0); old text;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.path_domains where domain = p_domain) then raise exception 'unknown_domain'; end if;
  if p_mode not in ('a', 'b', 'either', 'locked') then raise exception 'bad_mode'; end if;
  if loc > 0 and not exists (select 1 from public.locations where id = loc) then raise exception 'unknown_location'; end if;
  old := public.path_mode(p_domain, loc);
  insert into public.path_switch (domain, location_id, mode, note, updated_by, updated_at) values (p_domain, loc, p_mode, nullif(btrim(p_note), ''), auth.uid(), now())
    on conflict (domain, location_id) do update set mode = excluded.mode, note = excluded.note, updated_by = excluded.updated_by, updated_at = now();
  return jsonb_build_object('domain', p_domain, 'location_id', loc, 'from', old, 'to', p_mode);
end $$;

-- the full picture for the owner screen: every domain, its default, the all-places choice and the per-place overrides
create or replace function public.path_switches() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('domain', d.domain, 'a_bn', d.a_bn, 'a_en', d.a_en, 'b_bn', d.b_bn, 'b_en', d.b_en, 'note_bn', d.note_bn, 'note_en', d.note_en,
      'default', d.default_mode, 'mode', public.path_mode(d.domain, 0),
      'places', coalesce((select jsonb_agg(jsonb_build_object('location_id', s.location_id, 'mode', s.mode, 'note', s.note) order by s.location_id) from public.path_switch s where s.domain = d.domain and s.location_id > 0), '[]'::jsonb))
      order by d.sort) from public.path_domains d), '[]'::jsonb);
end $$;

-- ---------- 6. the shadow engine (internal: called by the domain slices, never by the browser) ----------
create or replace function public.shadow_link_add(p_domain text, p_loc int, p_ptype text, p_pid text, p_stype text, p_sid text default null, p_note text default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare v bigint;
begin
  if not exists (select 1 from public.path_domains where domain = p_domain) then raise exception 'unknown_domain'; end if;
  if p_ptype is null or p_pid is null or p_stype is null then raise exception 'bad_link'; end if;
  if p_sid is not null and p_stype = p_ptype and p_sid = p_pid then raise exception 'self_shadow'; end if;
  -- a record that is already a shadow cannot become a primary, and a primary cannot become a shadow (this is what makes "count once" hold)
  if exists (select 1 from public.shadow_links x where x.shadow_type = p_ptype and x.shadow_id = p_pid and x.state <> 'void') then raise exception 'primary_is_already_a_shadow'; end if;
  if p_sid is not null and exists (select 1 from public.shadow_links x where x.primary_type = p_stype and x.primary_id = p_sid and x.state <> 'void') then raise exception 'shadow_is_already_a_primary'; end if;
  insert into public.shadow_links (domain, location_id, primary_type, primary_id, shadow_type, shadow_id, state, note, created_by)
    values (p_domain, coalesce(p_loc, 0), p_ptype, p_pid, p_stype, p_sid, case when p_sid is null then 'pending' else 'confirmed' end, p_note, auth.uid())
    on conflict (domain, primary_type, primary_id, shadow_type) where state <> 'void' do nothing
    returning id into v;
  if v is null then
    select id into v from public.shadow_links x where x.domain = p_domain and x.primary_type = p_ptype and x.primary_id = p_pid and x.shadow_type = p_stype and x.state <> 'void';
  end if;
  return v;
end $$;

-- the owner / a manager with place access confirms a pending shadow ("one click"): it points at the record that now holds the second copy
create or replace function public.shadow_confirm(p_link bigint, p_shadow_id text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.shadow_links;
begin
  select * into r from public.shadow_links where id = p_link for update;
  if not found then raise exception 'not_found'; end if;
  if not (public.is_owner() or (r.location_id > 0 and public.can_loc(r.location_id))) then raise exception 'not allowed'; end if;
  if r.state <> 'pending' then return jsonb_build_object('id', r.id, 'state', r.state, 'noop', true); end if;
  if coalesce(p_shadow_id, r.shadow_id) is null then raise exception 'shadow_id_needed'; end if;
  if exists (select 1 from public.shadow_links x where x.primary_type = r.shadow_type and x.primary_id = coalesce(p_shadow_id, r.shadow_id) and x.state <> 'void') then raise exception 'shadow_is_already_a_primary'; end if;
  update public.shadow_links set state = 'confirmed', shadow_id = coalesce(p_shadow_id, shadow_id), confirmed_by = auth.uid(), confirmed_at = now() where id = p_link;
  return jsonb_build_object('id', r.id, 'state', 'confirmed');
end $$;

create or replace function public.shadow_void(p_link bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.shadow_links;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if nullif(btrim(p_note), '') is null then raise exception 'note_needed'; end if;
  select * into r from public.shadow_links where id = p_link for update;
  if not found then raise exception 'not_found'; end if;
  if r.state = 'void' then return jsonb_build_object('id', r.id, 'state', 'void', 'noop', true); end if;
  update public.shadow_links set state = 'void', note = left(coalesce(note || ' | ', '') || 'void: ' || btrim(p_note), 300) where id = p_link;
  return jsonb_build_object('id', r.id, 'state', 'void');
end $$;

-- is this record a (locked) shadow? posting / report functions of later slices skip it so it is counted once
create or replace function public.is_shadow(p_type text, p_id text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.shadow_links x where x.shadow_type = p_type and x.shadow_id = p_id and x.state <> 'void');
$$;

-- ---------- 7. read-only reports ----------
create or replace function public.shadow_report(p_domain text default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare ok boolean := public.is_owner();
begin
  if not (ok or (p_loc is not null and p_loc > 0 and public.can_loc(p_loc))) then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'counts', coalesce((select jsonb_object_agg(k, c) from (select x.domain || ':' || x.state as k, count(*) as c from public.shadow_links x
                         where (p_domain is null or x.domain = p_domain) and (p_loc is null or x.location_id in (0, p_loc)) and (ok or x.location_id = p_loc) group by 1) q), '{}'::jsonb),
    'pending', coalesce((select jsonb_agg(to_jsonb(z)) from (select x.id, x.domain, x.location_id, x.primary_type, x.primary_id, x.shadow_type, x.created_at from public.shadow_links x
                         where x.state = 'pending' and (p_domain is null or x.domain = p_domain) and (p_loc is null or x.location_id in (0, p_loc)) and (ok or x.location_id = p_loc)
                         order by x.created_at limit 100) z), '[]'::jsonb));
end $$;

-- count-once check: a shadow that ALSO reached the journal (as its own source) would be a double count. Read-only, owner only.
create or replace function public.shadow_count_once_check() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'shadow_in_journal', coalesce((select jsonb_agg(jsonb_build_object('link', x.id, 'domain', x.domain, 'shadow_type', x.shadow_type, 'shadow_id', x.shadow_id, 'journal_id', j.id))
        from public.shadow_links x join public.journal_entries j on j.source_type = x.shadow_type and j.source_id = x.shadow_id and j.reverses_id is null
       where x.state <> 'void'), '[]'::jsonb),
    'both_roles', coalesce((select jsonb_agg(jsonb_build_object('type', a.primary_type, 'id', a.primary_id))
        from public.shadow_links a join public.shadow_links b on b.shadow_type = a.primary_type and b.shadow_id = a.primary_id and b.state <> 'void' where a.state <> 'void'), '[]'::jsonb));
end $$;

-- ---------- 8. privileges ----------
revoke all on function public.path_mode(text, int), public.path_allowed(text, int, text), public.path_guard(text, int, text), public.path_switch_set(text, int, text, text), public.path_switches(),
  public.shadow_link_add(text, int, text, text, text, text, text), public.shadow_confirm(bigint, text), public.shadow_void(bigint, text), public.is_shadow(text, text),
  public.shadow_report(text, int), public.shadow_count_once_check() from public, anon;
grant execute on function public.path_mode(text, int), public.path_allowed(text, int, text), public.path_switch_set(text, int, text, text), public.path_switches(),
  public.shadow_confirm(bigint, text), public.shadow_void(bigint, text), public.shadow_report(text, int), public.shadow_count_once_check() to authenticated;
-- internal: path_guard, shadow_link_add, is_shadow are called by SECURITY DEFINER posting functions only
revoke all on function public.path_guard(text, int, text), public.shadow_link_add(text, int, text, text, text, text, text), public.is_shadow(text, text) from authenticated;
notify pgrst, 'reload schema';
