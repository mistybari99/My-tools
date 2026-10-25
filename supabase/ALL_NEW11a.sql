-- ===== phase48 =====
-- ============================================================
-- Phase 48 - P1 slice 1: the "one record + locked shadow copy" engine and the owner path switches.
-- Run AFTER phase47. Additive + idempotent (paste twice = no error). No existing table or function is changed; nothing is posted by this file.
--
-- Rule: every transaction has ONE primary record. The other path (quick tab <-> formal paper form) gets a linked, locked "shadow copy".
--       A shadow is never counted: reports, the day book and the journal read the primary only. Posting stays unique on (source_type, source_id).
--
--   path_domains   the 7 places where two paths exist (payroll, stock issue / transfer / count, production, expense, owner money) with labels + default.
--   path_switch    the OWNER's choice per domain (and optionally per place): is path A open or locked, is path B open or locked, and which record is the
--                  primary when both exist: a | b | first (the earlier one).   location_id 0 = all places.  A locked path takes no NEW records.
--   shadow_links   primary record <-> shadow copy (pending until the second path is filled/confirmed; confirmed; void). Append-only trail.
--   Functions: path_cfg, path_primary, path_allowed, path_guard (used by later slices), path_switch_set / path_switches (owner),
--              shadow_link_add / shadow_confirm / shadow_void (internal), is_shadow, shadow_report, shadow_count_once_check (read-only).
-- ============================================================

-- ---------- 1. domains ----------
create table if not exists public.path_domains (
  domain text primary key check (domain ~ '^[a-z_]{2,30}$'),
  a_bn text not null, a_en text not null,                    -- path A (app / quick / screen)
  b_bn text not null, b_en text not null,                    -- path B (formal paper form / second screen)
  default_primary text not null default 'a' check (default_primary in ('a', 'b', 'first')),   -- which record is counted when both paths hold the same event
  legacy_rule text,                                          -- an older owner switch that already meant "the form is the record": while it is ON the default primary is b (keeps today's behaviour)
  allow_first boolean not null default false,                -- 'first one wins' only where the two records have a natural key (payroll month, owner money amount/date); not for stock
  note_bn text, note_en text,
  sort int not null default 0
);
insert into public.path_domains (domain, a_bn, a_en, b_bn, b_en, default_primary, note_bn, note_en, sort) values
 ('payroll',       'অ্যাপে বেতন (পে-রোল)',      'App payroll (runs / payments)',   'ফর্ম 02-2 (মাসিক বেতন শিট)',   'Form 02-2 (monthly salary sheet)',     'a',
  'দুটোই খোলা; অ্যাপে বেতন শুরু হলে 02-2 লক হয়, গোপন শ্যাডো কপি থাকে।', 'Both open; once app payroll starts for the month, 02-2 is locked and kept as a shadow copy.', 10),
 ('stock_issue',   'স্টক স্ক্রিনে ইস্যু',         'Stock screen issue',               'ফর্ম 04-2 (ইস্যু স্লিপ)',        'Form 04-2 (issue slip)',                'a',
  'ডিফল্ট: স্ক্রিন মূল, ফর্ম রেফারেন্স।', 'Default: screen is primary, form is a reference.', 20),
 ('stock_transfer','স্টক স্ক্রিনে ট্রান্সফার',    'Stock screen transfer',            'ফর্ম 03-1 (ট্রান্সফার চালান)',   'Form 03-1 (transfer challan)',          'a',
  'ডিফল্ট: স্ক্রিন মূল, ফর্ম রেফারেন্স।', 'Default: screen is primary, form is a reference.', 30),
 ('stock_count',   'স্টক স্ক্রিনে গণনা',          'Stock screen count',               'ফর্ম 04-3 (স্টক কাউন্ট শিট)',    'Form 04-3 (stock count sheet)',         'a',
  'ডিফল্ট: স্ক্রিন মূল, ফর্ম রেফারেন্স।', 'Default: screen is primary, form is a reference.', 40),
 ('production',    'রেসিপি প্রোডাকশন রান',        'Recipe production run',            'ফর্ম 05-1 (কারখানা দৈনিক শিট)',  'Form 05-1 (factory daily sheet)',       'a',
  'ডিফল্ট: রান মূল, 05-1 রেফারেন্স।', 'Default: the run is primary, 05-1 is a reference.', 50),
 ('expense',       'ডে-বুকে দ্রুত খরচ এন্ট্রি',    'Day-book quick expense',           'ফর্ম 10-2 (ব্যয় ভাউচার)',       'Form 10-2 (expense voucher)',           'a',
  'দিনের শেষে দ্রুত এন্ট্রির 10-2 শ্যাডো কপি; এক ক্লিকে নিশ্চিত।', 'Quick entries get a 10-2 shadow at day end; one click confirms.', 60),
 ('owner_money',   'পার্টনার ক্যাপিটাল',          'Partner capital',                  'ক্যাশ মুভ (মালিকের জমা/উত্তোলন)', 'Cash move (owner top-up / draw)',       'a',
  'ডিফল্ট: পার্টনার ক্যাপিটাল মূল, ক্যাশ মুভ শ্যাডো।', 'Default: partner capital is primary, the cash move gets the shadow.', 70)
on conflict (domain) do nothing;
update public.path_domains set allow_first = true where domain in ('payroll', 'expense', 'owner_money') and not allow_first;
update public.path_domains set legacy_rule = 'forms_post_to_ledger' where domain in ('stock_issue', 'stock_transfer', 'stock_count', 'production') and legacy_rule is distinct from 'forms_post_to_ledger';

-- ---------- 2. the owner's switch ----------
create table if not exists public.path_switch (
  domain text not null references public.path_domains(domain),
  location_id int not null default 0 check (location_id >= 0),     -- 0 = every place
  a_open boolean not null default true,                            -- false = locked: path A takes no new records
  b_open boolean not null default true,
  primary_rule text check (primary_rule is null or primary_rule in ('a', 'b', 'first')),   -- null = the domain default
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
-- one shadow of a kind per primary. Several primaries may share one shadow record (a day's quick entries -> one voucher): the shadow is simply never counted.
create unique index if not exists shadow_one_per_primary on public.shadow_links (domain, primary_type, primary_id, shadow_type) where state <> 'void';
create unique index if not exists shadow_pair_once on public.shadow_links (primary_type, primary_id, shadow_type, shadow_id) where shadow_id is not null and state <> 'void';
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
-- the effective setting: a place row beats the all-places row beats the domain default
create or replace function public.path_cfg(p_domain text, p_loc int default 0) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('a_open', coalesce(x.a_open, true), 'b_open', coalesce(x.b_open, true), 'primary', coalesce(x.primary_rule, case when d.legacy_rule is not null and public.rule_on(d.legacy_rule) then 'b' else d.default_primary end))
    from public.path_domains d
    left join lateral (select s.* from public.path_switch s where s.domain = d.domain and s.location_id in (0, case when coalesce(p_loc, 0) > 0 then p_loc else 0 end)
                        order by s.location_id desc limit 1) x on true
   where d.domain = p_domain;
$$;
create or replace function public.path_primary(p_domain text, p_loc int default 0) returns text
language sql stable security definer set search_path = public as $$ select public.path_cfg(p_domain, p_loc) ->> 'primary' $$;

-- may this path ('a' | 'b') take a NEW record now?
create or replace function public.path_allowed(p_domain text, p_loc int, p_path text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((public.path_cfg(p_domain, p_loc) ->> (p_path || '_open'))::boolean, false) where p_path in ('a', 'b');
$$;

-- used INSIDE posting functions / triggers of later slices: refuse when the owner has locked this path
create or replace function public.path_guard(p_domain text, p_loc int, p_path text) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if p_path not in ('a', 'b') then raise exception 'bad_path'; end if;
  if not exists (select 1 from public.path_domains where domain = p_domain) then raise exception 'unknown_domain'; end if;
  if not public.path_allowed(p_domain, p_loc, p_path) then raise exception 'path_locked: % path % is locked here by the owner', p_domain, p_path; end if;
end $$;

-- given two records of the same event (existing = already stored, incoming = the one arriving on path p_in), which one is the primary? returns 'incoming' | 'existing'
create or replace function public.path_winner(p_domain text, p_loc int, p_incoming_path text) returns text
language sql stable security definer set search_path = public as $$
  select case public.path_primary(p_domain, p_loc) when 'first' then 'existing' when p_incoming_path then 'incoming' else 'existing' end;
$$;

-- ---------- 5. owner sets the switch ----------
create or replace function public.path_switch_set(p_domain text, p_loc int, p_a_open boolean, p_b_open boolean, p_primary text default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare loc int := coalesce(p_loc, 0); old jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.path_domains where domain = p_domain) then raise exception 'unknown_domain'; end if;
  if p_a_open is null or p_b_open is null then raise exception 'bad_mode'; end if;
  if p_primary is not null and p_primary not in ('a', 'b', 'first') then raise exception 'bad_primary'; end if;
  if p_primary = 'first' and not (select allow_first from public.path_domains where domain = p_domain) then raise exception 'first_not_allowed: stock and production records have no natural key, choose a or b'; end if;
  if loc > 0 and not exists (select 1 from public.locations where id = loc) then raise exception 'unknown_location'; end if;
  old := public.path_cfg(p_domain, loc);
  insert into public.path_switch (domain, location_id, a_open, b_open, primary_rule, note, updated_by, updated_at) values (p_domain, loc, p_a_open, p_b_open, p_primary, nullif(btrim(p_note), ''), auth.uid(), now())
    on conflict (domain, location_id) do update set a_open = excluded.a_open, b_open = excluded.b_open, primary_rule = excluded.primary_rule, note = excluded.note, updated_by = excluded.updated_by, updated_at = now();
  return jsonb_build_object('domain', p_domain, 'location_id', loc, 'from', old, 'to', public.path_cfg(p_domain, loc));
end $$;

-- the full picture for the owner screen: every domain, the all-places setting and the per-place overrides
create or replace function public.path_switches() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('domain', d.domain, 'a_bn', d.a_bn, 'a_en', d.a_en, 'b_bn', d.b_bn, 'b_en', d.b_en, 'note_bn', d.note_bn, 'note_en', d.note_en,
      'default_primary', d.default_primary, 'cfg', public.path_cfg(d.domain, 0),
      'places', coalesce((select jsonb_agg(jsonb_build_object('location_id', s.location_id, 'cfg', public.path_cfg(d.domain, s.location_id), 'note', s.note) order by s.location_id) from public.path_switch s where s.domain = d.domain and s.location_id > 0), '[]'::jsonb))
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
revoke all on function public.path_cfg(text, int), public.path_primary(text, int), public.path_allowed(text, int, text), public.path_guard(text, int, text), public.path_winner(text, int, text),
  public.path_switch_set(text, int, boolean, boolean, text, text), public.path_switches(),
  public.shadow_link_add(text, int, text, text, text, text, text), public.shadow_confirm(bigint, text), public.shadow_void(bigint, text), public.is_shadow(text, text),
  public.shadow_report(text, int), public.shadow_count_once_check() from public, anon;
grant execute on function public.path_cfg(text, int), public.path_primary(text, int), public.path_allowed(text, int, text), public.path_switch_set(text, int, boolean, boolean, text, text), public.path_switches(),
  public.shadow_confirm(bigint, text), public.shadow_void(bigint, text), public.shadow_report(text, int), public.shadow_count_once_check() to authenticated;
-- internal: path_guard, path_winner, shadow_link_add, is_shadow are called by SECURITY DEFINER posting functions / triggers only
revoke all on function public.path_guard(text, int, text), public.path_winner(text, int, text), public.shadow_link_add(text, int, text, text, text, text, text), public.is_shadow(text, text) from authenticated;
notify pgrst, 'reload schema';

-- ===== phase49 =====
-- ============================================================
-- Phase 49 - P1 slice 2: READ-ONLY reports (gap #15 + roadmap A1). Nothing is written, no existing record is touched.
-- Run AFTER phase48. Idempotent (create or replace).
--   daybook_vs_journal(from, to, loc)   per payment mode and per kind of money movement: what the day book shows vs what the journal holds,
--                                       with the difference. Owner or accounts_manage only; needs the accounting start date.
--   dup_suspects(from, to)              owner only. Rows that look like the same event keyed on two paths (payroll D1, stock D2, production D3,
--                                       owner money D4, cash handover D8). A suspect list to review one by one - NOT a verdict, nothing is changed.
-- ============================================================

create or replace function public.daybook_vs_journal(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); d1 date; locs int[]; rows jsonb; tot jsonb; own boolean := public.is_owner();
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then raise exception 'bad_range'; end if;
  if st is null then return jsonb_build_object('data_needed', true, 'why', 'accounting_start_date'); end if;
  d1 := greatest(p_from, st);
  select array_agg(l.id) into locs from public.locations l where (p_loc is null or l.id = p_loc) and (own or public.can_loc(l.id));
  if locs is null then raise exception 'not allowed'; end if;
  with db as (  -- the day book, internal hub lines kept apart, signed per mode (card settles to bank in the day book)
    select case when u.typ in ('bill', 'supplier') then 'supplier_payment' else u.typ end as k, u.mode, u.internal, case when u.dir = 'in' then u.amount else -u.amount end as s
      from (select * from public._daybook_lines(locs, locs, d1, p_to) union all select * from public._daybook_lines12(locs, d1, p_to) union all select * from public._daybook_lines23(locs, d1, p_to)) u
  ), jr as (    -- the journal: movement on the cash / bank / mobile accounts, by kind (cash_move keeps its own kind)
    select case je.source_type when 'cash_move' then coalesce(je.subtype, 'cash_move') when 'expense_voucher' then 'expense' when 'quick_expense' then 'expense' else je.source_type end as k,
           case when a.key = 'pay_cash' then 'cash' when a.key = 'pay_mobile' then 'mobile' else 'bank' end as mode, (jl.debit - jl.credit) as s
      from public.journal_entries je
      join public.journal_lines jl on jl.entry_id = je.id
      join public.acct_mappings a on a.account_id = jl.account_id and a.key in ('pay_cash', 'pay_bank', 'pay_card', 'pay_mobile')
     where je.entry_date between d1 and p_to and je.source_type <> 'opening' and (je.location_id is null or je.location_id = any (locs))
  ), kk as (
    select k, mode, sum(s) filter (where not internal) as dbs, sum(s) filter (where internal) as dbi, 0::numeric as js from db group by k, mode
    union all select k, mode, null, null, sum(s) from jr group by k, mode
  ), agg as (
    select k, mode, coalesce(sum(dbs), 0) as daybook, coalesce(sum(dbi), 0) as hub_internal, coalesce(sum(js), 0) as journal from kk group by k, mode
  )
  select coalesce(jsonb_agg(jsonb_build_object('kind', k, 'mode', mode, 'daybook', daybook, 'journal', journal, 'diff', daybook - journal, 'hub_internal', hub_internal) order by k, mode)
           filter (where abs(daybook - journal) > 0.004 or hub_internal <> 0), '[]'::jsonb),
         jsonb_build_object('daybook', coalesce(sum(daybook), 0), 'journal', coalesce(sum(journal), 0), 'diff', coalesce(sum(daybook - journal), 0),
           'kinds_checked', count(*), 'kinds_differing', count(*) filter (where abs(daybook - journal) > 0.004))
    into rows, tot from agg;
  return jsonb_build_object('from', d1, 'to', p_to, 'location_id', p_loc, 'accounting_start', st, 'rows', rows, 'total', tot,
    'note', 'Day book counts a 10-2 voucher when submitted, the journal only when approved; payroll payments and staff advances are in the day book but have no journal source until the auto-post slice. Reversals post on the day they are made.');
end $$;

create or replace function public.dup_suspects(p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then raise exception 'bad_range'; end if;
  return jsonb_build_object('from', p_from, 'to', p_to,
    -- D1: a payroll month paid in the app AND a 02-2 sheet for the same place and month
    'payroll', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select r.id as run_id, r.month, r.location_id, e.id as entry_id, e.serial, e.status as form_status
          from public.payroll_runs r join public.entries e on e.form_code = '02-2' and e.status in ('submitted', 'approved') and e.location_id = coalesce(r.location_id, e.location_id)
            and date_trunc('month', e.entry_date) = date_trunc('month', r.month::timestamp)
         where r.status <> 'void' and r.month between date_trunc('month', p_from)::date and p_to
           and not public.is_shadow('entries', e.id::text) order by r.month, r.id limit 200) z), '[]'::jsonb),
    -- D2: a form-posted stock line (ref_type entry) and a screen-posted line for the same item, place, day, reason and quantity
    'stock', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select f.item_id, f.location_id, (f.made_at at time zone 'Asia/Dhaka')::date as day, f.reason, f.qty_delta, f.id as form_ledger_id, s.id as screen_ledger_id
          from public.stock_ledger f join public.stock_ledger s on s.item_id = f.item_id and s.location_id = f.location_id and s.reason = f.reason and s.qty_delta = f.qty_delta
            and (s.made_at at time zone 'Asia/Dhaka')::date = (f.made_at at time zone 'Asia/Dhaka')::date and coalesce(s.ref_type, '') <> 'entry' and s.id <> f.id and s.reverses_id is null
         where f.ref_type = 'entry' and f.reverses_id is null and f.reason in ('issue_out', 'transfer_out', 'transfer_in', 'count_adjust', 'production_in', 'purchase_in')
           and f.made_at >= (p_from::timestamp at time zone 'Asia/Dhaka') and f.made_at < ((p_to + 1)::timestamp at time zone 'Asia/Dhaka')
           and coalesce(s.ref_type, '') not in ('sale', 'sale_pack', 'sale_return') order by f.made_at limit 200) z), '[]'::jsonb),
    -- D3: a 05-1 output line posted from the form and a production run for the same finished item, place and day
    'production', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select f.item_id, f.location_id, (f.made_at at time zone 'Asia/Dhaka')::date as day, f.qty_delta, f.id as form_ledger_id, r.id as run_id
          from public.stock_ledger f join public.production_runs r on r.item_id = f.item_id and r.location_id = f.location_id and r.status = 'done'
            and (r.made_at at time zone 'Asia/Dhaka')::date = (f.made_at at time zone 'Asia/Dhaka')::date
         where f.ref_type = 'entry' and f.reason = 'production_in' and f.reverses_id is null
           and f.made_at >= (p_from::timestamp at time zone 'Asia/Dhaka') and f.made_at < ((p_to + 1)::timestamp at time zone 'Asia/Dhaka') order by f.made_at limit 200) z), '[]'::jsonb),
    -- D4: an owner top-up / draw in partner capital and the same amount on a cash move within 3 days
    'owner_money', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select pc.id as capital_id, pc.cap_date, pc.kind as capital_kind, pc.amount, m.id as cash_move_id, m.move_date, m.kind as cash_kind, m.location_id
          from public.partner_capital pc join public.cash_moves m on m.kind in ('owner_topup', 'owner_draw') and m.status = 'done' and m.amount = pc.amount and abs(m.move_date - pc.cap_date) <= 3
         where pc.status = 'posted' and pc.cap_date between p_from and p_to and not public.is_shadow('cash_moves', m.id::text) order by pc.cap_date limit 200) z), '[]'::jsonb),
    -- D8: a hub receipt (cash move) and a cash handover slip 10-1 for the same place and day
    'handover', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select m.id as cash_move_id, m.move_date, m.location_id, m.amount, e.id as entry_id, e.serial
          from public.cash_moves m join public.entries e on e.form_code = '10-1' and e.status in ('submitted', 'approved') and e.entry_date = m.move_date
         where m.kind = 'hub_receipt' and m.status = 'done' and m.move_date between p_from and p_to order by m.move_date limit 200) z), '[]'::jsonb));
end $$;

revoke all on function public.daybook_vs_journal(date, date, int), public.dup_suspects(date, date) from public, anon;
grant execute on function public.daybook_vs_journal(date, date, int), public.dup_suspects(date, date) to authenticated;
notify pgrst, 'reload schema';

-- ===== phase50 =====
-- ============================================================
-- Phase 50 - P1 slice 3: payroll (gap #24) and expense (gap #28) - one record + locked shadow copy.
-- Run AFTER phase48 (phase49 is optional). Idempotent (paste twice = no error). No existing row is changed or deleted.
--
--   PAYROLL  path A = app payroll (payroll_runs / payroll_payments), path B = form 02-2.  Same place + month (+ year) = same event.
--            Owner default: the app payroll is the record; the 02-2 sheet becomes a locked shadow (kept, shown, never counted in the day book).
--            Owner may switch the primary to the form, or "first one wins", or lock either path (Switch board, domain payroll).
--            A voided run releases its shadows: the forms count again.
--   EXPENSE  path A = quick expense typed in the day-book tab (quick_expenses), path B = form 10-2.
--            A quick entry counts at once (day book, journal, P&L). It gets a pending shadow; quick_expense_close_day() builds ONE draft 10-2 from the
--            day's unlinked quick entries (one click) and confirms the shadows. The 10-2 shadow is never counted again.
--   Guards   BEFORE INSERT triggers refuse a new record on a path the owner has locked (payroll_runs, entries of 02-2 / 10-2 / 04-2 / 03-1 / 04-3 / 05-1).
--   Lock     a shadow form that is submitted/approved cannot have its data changed or be re-opened.
--   Counting once: _daybook_lines, _daybook_skipped, _daybook_lines23, _acct_docs, _p27_pl, _r3q_e2_expense_trend are RE-CREATED from their latest definitions;
--            ONLY the blocks marked "bos50" differ.
-- ============================================================

-- ---------- 1. form -> domain map, guard for the form path ----------
create or replace function public._entry_domain(p_form text) returns text language sql immutable as $$
  select case p_form when '02-2' then 'payroll' when '10-2' then 'expense' when '04-2' then 'stock_issue' when '03-1' then 'stock_transfer' when '04-3' then 'stock_count' when '05-1' then 'production' end;
$$;

create or replace function public._entries_path_guard50() returns trigger
language plpgsql security definer set search_path = public as $$
declare d text := public._entry_domain(new.form_code);
begin
  if d is not null and coalesce(current_setting('bos.shadow_create', true), '') <> '1' then perform public.path_guard(d, new.location_id, 'b'); end if;
  return new;
end $$;
drop trigger if exists entries_path_guard50 on public.entries;
create trigger entries_path_guard50 before insert on public.entries for each row execute function public._entries_path_guard50();

-- a shadow form that is submitted / approved is locked: no data change, no re-open
create or replace function public._entries_shadow_lock50() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.status in ('submitted', 'approved') and (new.data is distinct from old.data or new.status = 'draft') and public.is_shadow('entries', old.id::text) then
    raise exception 'shadow_locked: this form is a locked copy of another record; it cannot be changed or re-opened';
  end if;
  return new;
end $$;
drop trigger if exists entries_shadow_lock50 on public.entries;
create trigger entries_shadow_lock50 before update on public.entries for each row execute function public._entries_shadow_lock50();

-- ---------- 2. PAYROLL: guard, link, release ----------
create or replace function public._payroll_run_guard50() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.path_guard('payroll', coalesce(new.location_id, 0), 'a');
  return new;
end $$;
drop trigger if exists payroll_runs_path_guard50 on public.payroll_runs;
create trigger payroll_runs_path_guard50 before insert on public.payroll_runs for each row execute function public._payroll_run_guard50();

-- the month / year a 02-2 sheet is written for (null when it cannot be read)
create or replace function public._entry_pay_month50(p_data jsonb) returns date
language sql immutable as $$
  select case when p_data->>'month' ~ '^(1[0-2]|[1-9])$' and p_data->>'year' ~ '^20[0-9]{2}$' then make_date((p_data->>'year')::int, (p_data->>'month')::int, 1) end;
$$;

create or replace function public._payroll_pair50(p_run bigint, p_entry uuid, p_loc int, p_incoming_path text) returns void
language plpgsql security definer set search_path = public as $$
begin
  begin
    if public.path_winner('payroll', p_loc, p_incoming_path) = 'incoming' then
      -- the record that just arrived is the primary: the older one becomes its shadow
      if p_incoming_path = 'a' then perform public.shadow_link_add('payroll', p_loc, 'payroll_runs', p_run::text, 'entries', p_entry::text, 'form 02-2 kept as a copy');
      else perform public.shadow_link_add('payroll', p_loc, 'entries', p_entry::text, 'payroll_runs', p_run::text, 'app payroll kept as a copy'); end if;
    else
      if p_incoming_path = 'a' then perform public.shadow_link_add('payroll', p_loc, 'entries', p_entry::text, 'payroll_runs', p_run::text, 'app payroll kept as a copy');
      else perform public.shadow_link_add('payroll', p_loc, 'payroll_runs', p_run::text, 'entries', p_entry::text, 'form 02-2 kept as a copy'); end if;
    end if;
  exception when others then
    if sqlerrm not like 'primary_is_already_a_shadow%' and sqlerrm not like 'shadow_is_already_a_primary%' then raise; end if;   -- an older decision already settled this pair
  end;
end $$;

create or replace function public._payroll_run_link50() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  if new.status = 'void' then return new; end if;
  for r in select e.id, e.location_id from public.entries e
            where e.form_code = '02-2' and e.status in ('submitted', 'approved') and (new.location_id is null or e.location_id = new.location_id)
              and public._entry_pay_month50(e.data) = new.month loop
    perform public._payroll_pair50(new.id, r.id, r.location_id, 'a');
  end loop;
  return new;
end $$;
drop trigger if exists payroll_runs_link50 on public.payroll_runs;
create trigger payroll_runs_link50 after insert or update of status on public.payroll_runs for each row execute function public._payroll_run_link50();

create or replace function public._payroll_entry_link50() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record; m date := public._entry_pay_month50(new.data);
begin
  if m is null or new.form_code <> '02-2' or new.status not in ('submitted', 'approved') then return new; end if;
  for r in select pr.id from public.payroll_runs pr where pr.status <> 'void' and pr.month = m and (pr.location_id is null or pr.location_id = new.location_id) loop
    perform public._payroll_pair50(r.id, new.id, new.location_id, 'b');
  end loop;
  return new;
end $$;
drop trigger if exists entries_payroll_link50 on public.entries;
create trigger entries_payroll_link50 after insert or update of status on public.entries for each row when (new.form_code = '02-2') execute function public._payroll_entry_link50();

-- a voided run releases everything it held: the forms count again
create or replace function public._payroll_run_release50() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'void' and old.status is distinct from 'void' then
    update public.shadow_links set state = 'void', note = left(coalesce(note || ' | ', '') || 'released: payroll run voided', 300)
     where domain = 'payroll' and state <> 'void' and ((primary_type = 'payroll_runs' and primary_id = new.id::text) or (shadow_type = 'payroll_runs' and shadow_id = new.id::text));
  end if;
  return new;
end $$;
drop trigger if exists payroll_runs_release50 on public.payroll_runs;
create trigger payroll_runs_release50 after update of status on public.payroll_runs for each row execute function public._payroll_run_release50();

-- ---------- 3. EXPENSE: quick expense (path A) ----------
create table if not exists public.quick_expenses (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  location_id int not null references public.locations(id),
  exp_date date not null,
  head text not null check (head ~ '^[a-z0-9_]{2,30}$'),
  paid_to text check (paid_to is null or length(paid_to) <= 120),
  amount numeric not null check (amount > 0 and amount <= 1000000000),
  mode text not null default 'cash' check (mode in ('cash', 'bank', 'mobile')),
  receipt boolean not null default false,
  note text check (note is null or length(note) <= 300),
  status text not null default 'done' check (status in ('done', 'void')),
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  void_by uuid, void_at timestamptz, void_note text
);
create index if not exists quick_exp_day on public.quick_expenses (location_id, exp_date);
drop trigger if exists audit_quick_expenses on public.quick_expenses;
create trigger audit_quick_expenses after insert or update on public.quick_expenses for each row execute function public.log_change('id');
create or replace function public._quick_exp_ro50() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' and old.status = 'done' and new.status = 'void' and (to_jsonb(new) - 'status' - 'void_by' - 'void_at' - 'void_note') = (to_jsonb(old) - 'status' - 'void_by' - 'void_at' - 'void_note') then return new; end if;
  raise exception 'append_only: a quick expense cannot be changed or deleted (void it)';
end $$;
drop trigger if exists quick_exp_ro on public.quick_expenses;
create trigger quick_exp_ro before update or delete on public.quick_expenses for each row execute function public._quick_exp_ro50();
alter table public.quick_expenses enable row level security;
revoke all on public.quick_expenses from public, anon, authenticated;
grant select on public.quick_expenses to authenticated;
drop policy if exists quick_expenses_sel on public.quick_expenses;
create policy quick_expenses_sel on public.quick_expenses for select to authenticated using (public.is_owner() or (public.can_do('10-2', 'view') and public.can_loc(location_id)));

create or replace function public.quick_expense_add(p_loc int, p_date date, p_head text, p_to text, p_amount numeric, p_mode text default 'cash', p_receipt boolean default false,
                                                    p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare q public.quick_expenses; today date := (now() at time zone 'Asia/Dhaka')::date; d date := coalesce(p_date, (now() at time zone 'Asia/Dhaka')::date); sid text;
begin
  if not (public.can_do('10-2', 'enter') and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  if p_client is not null then
    select * into q from public.quick_expenses where client_id = p_client;
    if found then
      if q.created_by <> auth.uid() then raise exception 'client_id_in_use'; end if;
      return jsonb_build_object('id', q.id, 'duplicate', true);
    end if;
  end if;
  perform public.path_guard('expense', p_loc, 'a');
  if p_amount is null or p_amount <= 0 then raise exception 'bad_amount'; end if;
  if nullif(btrim(p_head), '') is null then raise exception 'head_needed'; end if;
  if d > today or (d < today - 7 and not public.is_owner()) then raise exception 'bad_date'; end if;
  perform public.lock_check(d);
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.quick_expenses (client_id, location_id, exp_date, head, paid_to, amount, mode, receipt, note, created_by, created_staff)
    values (p_client, p_loc, d, lower(btrim(p_head)), nullif(btrim(p_to), ''), p_amount, coalesce(p_mode, 'cash'), coalesce(p_receipt, false), nullif(btrim(p_note), ''), auth.uid(), sid) returning * into q;
  -- the form copy is owed at day end: a pending shadow
  perform public.shadow_link_add('expense', p_loc, 'quick_expenses', q.id::text, 'entries', null, 'form 10-2 owed at day end');
  return jsonb_build_object('id', q.id);
end $$;

create or replace function public.quick_expense_void(p_id uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare q public.quick_expenses;
begin
  select * into q from public.quick_expenses where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not (public.is_owner() or (q.created_by = auth.uid() and q.exp_date = (now() at time zone 'Asia/Dhaka')::date and public.can_loc(q.location_id))) then raise exception 'not allowed'; end if;
  if nullif(btrim(p_note), '') is null then raise exception 'note_needed'; end if;
  if q.status = 'void' then return jsonb_build_object('id', q.id, 'noop', true); end if;
  perform public.lock_check(q.exp_date);
  if exists (select 1 from public.shadow_links l where l.primary_type = 'quick_expenses' and l.primary_id = q.id::text and l.state = 'confirmed') then raise exception 'already_in_voucher: the day-end form was made; re-do it first'; end if;
  update public.quick_expenses set status = 'void', void_by = auth.uid(), void_at = now(), void_note = btrim(p_note) where id = p_id;
  update public.shadow_links set state = 'void', note = left(coalesce(note || ' | ', '') || 'quick expense voided', 300) where primary_type = 'quick_expenses' and primary_id = p_id::text and state = 'pending';
  return jsonb_build_object('id', q.id, 'status', 'void');
end $$;

-- what is typed today and what is still owed to the form
create or replace function public.quick_expense_day(p_loc int, p_date date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_owner() or (public.can_do('10-2', 'view') and public.can_loc(p_loc))) then raise exception 'not allowed'; end if;
  return jsonb_build_object('location_id', p_loc, 'date', p_date,
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'head', q.head, 'paid_to', q.paid_to, 'amount', q.amount, 'mode', q.mode, 'receipt', q.receipt, 'note', q.note, 'status', q.status,
        'form', (select l.shadow_id from public.shadow_links l where l.primary_type = 'quick_expenses' and l.primary_id = q.id::text and l.state = 'confirmed' limit 1)) order by q.created_at)
        from public.quick_expenses q where q.location_id = p_loc and q.exp_date = p_date), '[]'::jsonb),
    'total', coalesce((select sum(q.amount) from public.quick_expenses q where q.location_id = p_loc and q.exp_date = p_date and q.status = 'done'), 0),
    'owed', (select count(*) from public.quick_expenses q join public.shadow_links l on l.primary_type = 'quick_expenses' and l.primary_id = q.id::text and l.state = 'pending'
              where q.location_id = p_loc and q.exp_date = p_date and q.status = 'done'));
end $$;

-- one click at day end: ONE draft 10-2 from the day's quick entries that are not yet in a form; the shadows are confirmed
create or replace function public.quick_expense_close_day(p_loc int, p_date date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare lines jsonb; n int; sv jsonb; eid uuid; r record;
begin
  if not (public.can_do('10-2', 'enter') and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('head', q.head, 'to', coalesce(q.paid_to, ''), 'receipt', case when q.receipt then 'yes' else 'no' end, 'amount', q.amount) order by q.created_at), '[]'::jsonb), count(*)
    into lines, n
    from public.quick_expenses q join public.shadow_links l on l.primary_type = 'quick_expenses' and l.primary_id = q.id::text and l.state = 'pending'
   where q.location_id = p_loc and q.exp_date = p_date and q.status = 'done';
  if n = 0 then return jsonb_build_object('made', 0, 'note', 'nothing owed'); end if;
  perform set_config('bos.shadow_create', '1', true);
  sv := public.save_entry(null, '10-2', p_loc, p_date, jsonb_build_object('lines', lines, 'from_quick', true), '[]'::jsonb, 'made from the day''s quick expenses', null);
  perform set_config('bos.shadow_create', '', true);
  eid := (sv->>'id')::uuid;
  update public.shadow_links l set state = 'confirmed', shadow_id = eid::text, confirmed_by = auth.uid(), confirmed_at = now()
    from public.quick_expenses q
   where l.primary_type = 'quick_expenses' and l.primary_id = q.id::text and l.state = 'pending' and q.location_id = p_loc and q.exp_date = p_date and q.status = 'done';
  return jsonb_build_object('made', n, 'entry_id', eid, 'serial', sv->'serial');
end $$;

revoke all on function public.quick_expense_add(int, date, text, text, numeric, text, boolean, text, uuid), public.quick_expense_void(uuid, text), public.quick_expense_day(int, date),
  public.quick_expense_close_day(int, date) from public, anon;
grant execute on function public.quick_expense_add(int, date, text, text, numeric, text, boolean, text, uuid), public.quick_expense_void(uuid, text), public.quick_expense_day(int, date),
  public.quick_expense_close_day(int, date) to authenticated;
revoke all on function public._entry_domain(text), public._entries_path_guard50(), public._entries_shadow_lock50(), public._payroll_run_guard50(), public._entry_pay_month50(jsonb),
  public._payroll_pair50(bigint, uuid, int, text), public._payroll_run_link50(), public._payroll_entry_link50(), public._payroll_run_release50(), public._quick_exp_ro50() from public, anon, authenticated;

-- ============================================================
-- 4. COUNT ONCE: consumers re-created from their latest definitions. ONLY the lines marked bos50 differ.
-- ============================================================

CREATE OR REPLACE FUNCTION public._daybook_lines(p_locs integer[], p_sal integer[], p_from date, p_to date)
 RETURNS TABLE(loc integer, d date, dir text, mode text, typ text, amount numeric, ref text, txt text, who text, at timestamp with time zone, src text, src_id text, internal boolean, sensitive boolean)
 LANGUAGE sql
 STABLE
AS $function$
  -- POS: money taken with a sale (kind sale) and due collections (kind collection); card settles to the bank
  select p.location_id, (p.paid_at at time zone 'Asia/Dhaka')::date, 'in'::text,
         case p.mode when 'cash' then 'cash' when 'mobile' then 'mobile' else 'bank' end,
         case p.kind when 'collection' then 'collection' else 'sale' end,
         p.amount,
         case when s.receipt is not null then '#' || s.receipt::text end,
         nullif(btrim(concat_ws(' · ', c.name, p.wallet, p.ref)), ''), p.created_staff, p.paid_at,
         case when p.sale_id is not null then 'sale' else 'customer' end, coalesce(p.sale_id::text, p.customer_id::text), false, false
    from public.sale_payments p
    left join public.sales s on s.id = p.sale_id
    left join public.customers c on c.id = p.customer_id
   where not p.voided and p.location_id = any (p_locs) and p.amount between 0.01 and 1000000000000
     and p.paid_at >= (p_from::timestamp at time zone 'Asia/Dhaka') and p.paid_at < ((p_to + 1)::timestamp at time zone 'Asia/Dhaka')
  union all
  -- supplier payments (with or without a bill)
  select sp.location_id, (sp.paid_at at time zone 'Asia/Dhaka')::date, 'out',
         case sp.mode when 'cash' then 'cash' when 'mobile' then 'mobile' else 'bank' end,
         case when sp.bill_id is not null then 'bill' else 'supplier' end,
         sp.amount, pb.bill_no, nullif(btrim(concat_ws(' · ', su.name, sp.wallet, sp.ref)), ''), sp.created_staff, sp.paid_at,
         case when sp.bill_id is not null then 'bill' else 'supplier' end, coalesce(sp.bill_id::text, sp.supplier_id::text), false, false
    from public.supplier_payments sp
    left join public.suppliers su on su.id = sp.supplier_id
    left join public.purchase_bills pb on pb.id = sp.bill_id
   where not sp.voided and sp.location_id = any (p_locs) and sp.amount between 0.01 and 1000000000000
     and sp.paid_at >= (p_from::timestamp at time zone 'Asia/Dhaka') and sp.paid_at < ((p_to + 1)::timestamp at time zone 'Asia/Dhaka')
  union all
  -- 10-2 expense vouchers (submitted or approved): one line per voucher = the sum of its lines
  select e.location_id, e.entry_date, 'out', 'cash', 'expense', x.tot, '#' || e.serial::text,
         x.n::text || ' line(s)', e.created_staff, coalesce(e.submitted_at, e.created_at), 'entry', e.id::text, false, false
    from public.entries e
    cross join lateral (select coalesce(sum(public._db_num(l -> 'amount')) filter (where public._db_num(l -> 'amount') > 0), 0) as tot,
                               count(*) filter (where public._db_num(l -> 'amount') > 0) as n
                          from jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) l) x
   where e.form_code = '10-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.location_id = any (p_locs)
     and e.entry_date between p_from and p_to and x.tot between 0.01 and 1000000000000
  union all
  -- 10-1 cash handover slips: counted notes - float left behind. Cash leaves the showroom for the hub (hub side is not recorded -> internal).
  select e.location_id, e.entry_date, 'out', 'cash', 'handover', h.amt, '#' || e.serial::text, nullif(btrim(e.data ->> 'carrier'), ''), e.created_staff,
         coalesce(e.submitted_at, e.created_at), 'entry', e.id::text, true, false
    from public.entries e
    cross join lateral (select coalesce(public._db_num(e.data #> '{count,n1000}'), 0) * 1000 + coalesce(public._db_num(e.data #> '{count,n500}'), 0) * 500
        + coalesce(public._db_num(e.data #> '{count,n200}'), 0) * 200 + coalesce(public._db_num(e.data #> '{count,n100}'), 0) * 100
        + coalesce(public._db_num(e.data #> '{count,n50}'), 0) * 50 + coalesce(public._db_num(e.data #> '{count,n20}'), 0) * 20
        + coalesce(public._db_num(e.data #> '{count,n10}'), 0) * 10 + coalesce(public._db_num(e.data #> '{count,n5}'), 0) * 5
        + coalesce(public._db_num(e.data #> '{count,n2}'), 0) * 2 + coalesce(public._db_num(e.data #> '{count,n1}'), 0)
        + coalesce(public._db_num(e.data #> '{count,coin}'), 0) - coalesce(public._db_num(e.data -> 'leave_float'), 0) as amt) h
   where e.form_code = '10-1' and e.status in ('submitted', 'approved') and e.location_id = any (p_locs)
     and e.entry_date between p_from and p_to and h.amt between 0.01 and 1000000000000
  union all
  -- 02-3 staff advances given in cash / bank / mobile (goods and owner's personal money are not business cash). Salary-sensitive.
  select e.location_id, coalesce(public._db_date(a ->> 'date'), e.entry_date), 'out', a ->> 'method', 'advance', public._db_num(a -> 'amount'),
         '#' || e.serial::text, nullif(btrim(concat_ws(' · ', coalesce(pr.full_name, e.data ->> 'staff'), a ->> 'reason')), ''), e.created_staff,
         coalesce(e.submitted_at, e.created_at), 'entry', e.id::text, false, true
    from public.entries e
    cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'adv') = 'array' then e.data -> 'adv' else '[]'::jsonb end) a
    left join public.profiles pr on pr.staff_id = e.data ->> 'staff'
   where e.form_code = '02-3' and e.status in ('submitted', 'approved') and e.location_id = any (p_sal)
     and (a ->> 'method') in ('cash', 'bank', 'mobile') and public._db_num(a -> 'amount') between 0.01 and 1000000000000
     and coalesce(public._db_date(a ->> 'date'), e.entry_date) between p_from and p_to
  union all
  -- 02-2 salary actually paid (receipt acknowledgement lines: net, method, date). Salary-sensitive.
  select e.location_id, coalesce(public._db_date(r ->> 'date'), public._db_date(e.data ->> 'pay_date'), e.entry_date), 'out',
         coalesce(nullif(r ->> 'method', ''), e.data ->> 'pay_method'), 'salary', public._db_num(r -> 'net'),
         '#' || e.serial::text, nullif(btrim(r ->> 'name'), ''), e.created_staff, coalesce(e.submitted_at, e.created_at), 'entry', e.id::text, false, true
    from public.entries e
    cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'receipts') = 'array' then e.data -> 'receipts' else '[]'::jsonb end) r
   where e.form_code = '02-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.location_id = any (p_sal)
     and coalesce(nullif(r ->> 'method', ''), e.data ->> 'pay_method') in ('cash', 'bank', 'mobile') and public._db_num(r -> 'net') between 0.01 and 1000000000000
     and coalesce(public._db_date(r ->> 'date'), public._db_date(e.data ->> 'pay_date'), e.entry_date) between p_from and p_to;
$function$;

CREATE OR REPLACE FUNCTION public._daybook_skipped(p_locs integer[], p_sal integer[], p_from date, p_to date)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
  select (
    (select count(*) from public.entries e cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) l
      where e.form_code = '10-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.location_id = any (p_locs) and e.entry_date between p_from and p_to
        and nullif(btrim(l ->> 'amount'), '') is not null and public._db_num(l -> 'amount') is null)
  + (select count(*) from public.entries e cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'adv') = 'array' then e.data -> 'adv' else '[]'::jsonb end) a
      where e.form_code = '02-3' and e.status in ('submitted', 'approved') and e.location_id = any (p_sal) and e.entry_date between p_from and p_to
        and nullif(btrim(a ->> 'amount'), '') is not null and public._db_num(a -> 'amount') is null)
  + (select count(*) from public.entries e cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'receipts') = 'array' then e.data -> 'receipts' else '[]'::jsonb end) r
      where e.form_code = '02-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.location_id = any (p_sal) and e.entry_date between p_from and p_to
        and nullif(btrim(r ->> 'net'), '') is not null and public._db_num(r -> 'net') is null))::int;
$function$;

CREATE OR REPLACE FUNCTION public._daybook_lines23(p_locs integer[], p_from date, p_to date)
 RETURNS TABLE(loc integer, d date, dir text, mode text, typ text, amount numeric, ref text, txt text, who text, at timestamp with time zone, src text, src_id text, internal boolean, sensitive boolean)
 LANGUAGE sql
 STABLE
AS $function$
  select m.location_id, m.move_date, x.dir, x.mode, m.kind, m.amount, m.ref, nullif(btrim(concat_ws(' · ', c.name, m.note)), ''), m.created_staff, m.created_at,
         case when m.customer_id is not null then 'customer' else 'cash_move' end, coalesce(m.customer_id::text, m.id::text), (m.kind = 'hub_receipt'), false
    from public.cash_moves m
    left join public.customers c on c.id = m.customer_id
    cross join lateral (values (1)) one
    cross join lateral (
      select * from (values
        ('bank_deposit', 'out', 'cash'), ('bank_deposit', 'in', 'bank'), ('bank_withdraw', 'out', 'bank'), ('bank_withdraw', 'in', 'cash'),
        ('owner_topup', 'in', m.mode), ('owner_draw', 'out', m.mode), ('cust_advance', 'in', m.mode), ('cust_advance_refund', 'out', m.mode), ('hub_receipt', 'in', 'cash')
      ) v(k, dir, mode) where v.k = m.kind) x
   where m.status = 'done' and m.location_id = any (p_locs) and m.move_date between p_from and p_to
  union all
  -- phase42: salary paid from a payroll run (salary-sensitive: only with salary_view at that place)
  select p.location_id, p.pay_date, 'out', p.mode, 'salary', p.amount, 'PR-' || p.run_id::text, nullif(btrim(concat_ws(' · ', e.employee_no, e.full_name_bn, p.note)), ''), pr.staff_id, p.created_at,
         'payroll', p.id::text, false, true
    from public.payroll_payments p
    join public.employees e on e.id = p.employee_id
    left join public.profiles pr on pr.id = p.created_by
   where p.status = 'done' and not public.is_shadow('payroll_runs', p.run_id::text) /* bos50 */ and p.location_id = any (p_locs) and p.pay_date between p_from and p_to and (public.is_owner() or public.has_grant('salary_view', p.location_id))
  union all
  -- phase42: staff advance paid out in cash / bank / mobile from the advance register (mode none = already in a 02-3 form, not counted again)
  select a.location_id, a.adv_date, 'out', a.mode, 'advance', a.amount, 'ADV-' || a.id::text, nullif(btrim(concat_ws(' · ', e.employee_no, e.full_name_bn, a.note)), ''), pr.staff_id, a.created_at,
         'staff_advance', a.id::text, false, true
    from public.employee_advances a
    join public.employees e on e.id = a.employee_id
    left join public.profiles pr on pr.id = a.created_by
   where a.status = 'active' and a.mode in ('cash', 'bank', 'mobile') and a.location_id = any (p_locs) and a.adv_date between p_from and p_to
     and (public.is_owner() or public.has_grant('salary_view', a.location_id))
  union all
  -- bos50: a quick expense typed in the day-book tab (its 10-2 copy is a locked shadow and is not counted again)
  select q.location_id, q.exp_date, 'out', q.mode, 'expense', q.amount, 'Q-' || left(q.id::text, 8), nullif(btrim(concat_ws(' · ', q.paid_to, q.head, q.note)), ''), q.created_staff, q.created_at,
         'quick_expense', q.id::text, false, false
    from public.quick_expenses q
   where q.status = 'done' and q.location_id = any (p_locs) and q.exp_date between p_from and p_to;
$function$;

CREATE OR REPLACE FUNCTION public._acct_docs(p_start date)
 RETURNS TABLE(source_type text, source_id text, entry_date date, location_id integer, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- sales (payments split, discount, revenue, COGS only from real unit costs)
  return query
  select 'sale'::text, s.id::text, s.sale_date, s.location_id, ('Receipt ' || s.receipt)::text, null::text, s.status = 'done', (s.void_at at time zone 'Asia/Dhaka')::date,
    case when s.status = 'done' and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = s.id::text and l.reason = 'sale_out'
                   and l.item_id = (e->>'item_id')::uuid and l.unit_cost is not null)) then 'cogs_missing' end,
    null::text,
    case when s.status = 'done' then (
      select coalesce(jsonb_agg(j order by o), '[]'::jsonb) from (
        select 1 o, jsonb_build_object('a', 'pay_' || p.mode, 'd', sum(p.amount)) j from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided group by p.mode
        union all select 2, jsonb_build_object('a', 'receivable', 'd', round(s.total - pp.paid, 2), 'pt', case when s.customer_id is not null then 'customer' end, 'pid', s.customer_id::text) where s.total - pp.paid > 0.004
        union all select 3, jsonb_build_object('a', 'sales_discount', 'd', s.discount) where s.discount > 0
        union all select 4, jsonb_build_object('a', 'sales', 'c', s.subtotal)
        union all select 5, jsonb_build_object('a', 'cogs', 'd', cg.amt) from (select round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l where l.ref_id = s.id::text and l.ref_type in ('sale', 'sale_pack') and l.reason in ('sale_out', 'issue_out') and l.unit_cost is not null) cg where cg.amt > 0
        union all select 6, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt) from (select it.item_type t, round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l join public.items it on it.id = l.item_id where l.ref_id = s.id::text and l.ref_type in ('sale', 'sale_pack') and l.reason in ('sale_out', 'issue_out') and l.unit_cost is not null group by it.item_type) z where z.amt > 0
      ) x) end
  from public.sales s cross join lateral (select coalesce(sum(p.amount), 0) paid from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided) pp
  where s.sale_date >= p_start and s.subtotal > 0 and public._acct_need('sale', s.id::text, s.status = 'done');

  -- sale returns
  return query
  select 'sale_return'::text, r.id::text, (r.created_at at time zone 'Asia/Dhaka')::date, r.location_id, ('Return of receipt ' || coalesce(s.receipt::text, '-'))::text, null::text, r.status = 'done', (r.void_at at time zone 'Asia/Dhaka')::date,
    case when r.status = 'done' and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(r.lines) = 'array' then r.lines else '[]'::jsonb end) e
                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return'
                   and l.item_id = (e->>'item_id')::uuid and l.unit_cost is not null)) then 'cogs_missing' end,
    null::text,
    case when r.status = 'done' then (
      select coalesce(jsonb_agg(j order by o), '[]'::jsonb) from (
        select 1 o, jsonb_build_object('a', 'sales_returns', 'd', r.amount) j
        union all select 2, jsonb_build_object('a', 'receivable', 'c', r.credit_amount, 'pt', case when r.customer_id is not null then 'customer' end, 'pid', r.customer_id::text) where r.credit_amount > 0
        union all select 3, jsonb_build_object('a', public._acct_paykey(coalesce(r.refund_mode, 'cash')), 'c', r.refund_amount) where r.refund_amount > 0
        union all select 4, jsonb_build_object('a', public._acct_inv_key(z.t), 'd', z.amt) from (select it.item_type t, round(sum(l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l join public.items it on it.id = l.item_id where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return' and l.unit_cost is not null group by it.item_type) z where z.amt > 0
        union all select 5, jsonb_build_object('a', 'cogs', 'c', cg.amt) from (select round(sum(l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return' and l.unit_cost is not null) cg where cg.amt > 0
      ) x) end
  from public.sale_returns r left join public.sales s on s.id = r.sale_id
  where (r.created_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('sale_return', r.id::text, r.status = 'done');

  -- customer collections (later payments of dues)
  return query
  select 'collection'::text, p.id::text, (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, 'Due collection'::text, null::text, not p.voided, public._acct_today(), null::text, null::text,
    case when not p.voided then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(p.mode), 'd', p.amount),
      jsonb_build_object('a', 'receivable', 'c', p.amount, 'pt', case when p.customer_id is not null then 'customer' end, 'pid', p.customer_id::text)) end
  from public.sale_payments p
  where p.kind = 'collection' and (p.paid_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('collection', p.id::text, not p.voided);

  -- purchase bills and purchase returns
  return query
  select 'purchase'::text, b.id::text, b.bill_date, b.location_id, ((case b.kind when 'return' then 'Purchase return ' else 'Purchase bill ' end) || coalesce(b.bill_no, '-'))::text, b.kind, b.status = 'posted' and b.total > 0, (b.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when b.status = 'posted' and b.total > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'payable', case when b.kind = 'return' then 'd' else 'c' end, b.total, 'pt', 'supplier', 'pid', b.supplier_id::text) j
        union all select 2, jsonb_build_object('a', al.k, case when b.kind = 'return' then 'c' else 'd' end, al.amt) from public._acct_purchase_alloc(b.id) al
      ) x) end
  from public.purchase_bills b
  where b.bill_date >= p_start and public._acct_need('purchase', b.id::text, b.status = 'posted' and b.total > 0);

  -- supplier payments
  return query
  select 'supplier_payment'::text, p.id::text, (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, 'Supplier payment'::text, null::text, not p.voided, public._acct_today(), null::text, null::text,
    case when not p.voided then jsonb_build_array(jsonb_build_object('a', 'payable', 'd', p.amount, 'pt', 'supplier', 'pid', p.supplier_id::text),
      jsonb_build_object('a', public._acct_paykey(p.mode, true), 'c', p.amount)) end
  from public.supplier_payments p
  where (p.paid_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('supplier_payment', p.id::text, not p.voided);

  -- supplier refunds
  return query
  select 'supplier_refund'::text, f.id::text, (f.refunded_at at time zone 'Asia/Dhaka')::date, f.location_id, 'Supplier refund'::text, null::text, not f.voided, public._acct_today(), null::text, null::text,
    case when not f.voided then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(f.mode, true), 'd', f.amount),
      jsonb_build_object('a', 'payable', 'c', f.amount, 'pt', 'supplier', 'pid', f.supplier_id::text)) end
  from public.supplier_refunds f
  where (f.refunded_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('supplier_refund', f.id::text, not f.voided);

  -- 10-2 expense vouchers (approved; a re-opened or re-numbered voucher is reversed, the new revision posted)
  return query
  select 'expense_voucher'::text, e.id::text || ':' || coalesce(e.rev_no, 0)::text, e.entry_date, e.location_id, ('Expense voucher ' || e.serial)::text, null::text, v.total > 0, public._acct_today(),
    case when v.bad > 0 then 'unreadable_lines' end, null::text,
    case when v.total > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'exp_' || h.head, 'd', h.amt) j from (
          select regexp_replace(lower(coalesce(nullif(btrim(x->>'head'), ''), 'other')), '[^a-z0-9_]', '_', 'g') head, sum(public._acct_num(x->>'amount')) amt
          from jsonb_array_elements(case when jsonb_typeof(e.data->'lines') = 'array' then e.data->'lines' else '[]'::jsonb end) x
          where public._acct_num(x->>'amount') > 0 group by 1) h
        union all select 2, jsonb_build_object('a', 'pay_cash', 'c', v.total)
      ) y) end
  from public.entries e cross join lateral (
    select coalesce(sum(public._acct_num(x->>'amount')) filter (where public._acct_num(x->>'amount') > 0), 0) total,
           count(*) filter (where coalesce(btrim(x->>'amount'), '') <> '' and public._acct_num(x->>'amount') is null) bad
    from jsonb_array_elements(case when jsonb_typeof(e.data->'lines') = 'array' then e.data->'lines' else '[]'::jsonb end) x) v
  where e.form_code = '10-2' and e.status = 'approved' and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.entry_date >= p_start and public._acct_need('expense_voucher', e.id::text || ':' || coalesce(e.rev_no, 0)::text, v.total > 0);
  return query
  select 'expense_voucher'::text, je.source_id, je.entry_date, je.location_id, 'Expense voucher no longer approved'::text, null::text, false, public._acct_today(), null::text, null::text, null::jsonb
  from public.journal_entries je
  where je.source_type = 'expense_voucher' and je.reverses_id is null
    and not exists (select 1 from public.entries e where e.form_code = '10-2' and e.status = 'approved' and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.id::text || ':' || coalesce(e.rev_no, 0)::text = je.source_id)
    and not exists (select 1 from public.journal_entries r where r.reverses_id = je.id);

  -- bos50: quick expenses typed in the day-book tab: expense head debit, cash / bank / mobile credit
  return query
  select 'quick_expense'::text, q.id::text, q.exp_date, q.location_id, ('Quick expense: ' || q.head)::text, null::text, q.status = 'done', (q.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when q.status = 'done' then jsonb_build_array(
      jsonb_build_object('a', case when exists (select 1 from public.acct_mappings m where m.key = 'exp_' || q.head) then 'exp_' || q.head else 'exp_other' end, 'd', q.amount),
      jsonb_build_object('a', public._acct_paykey(q.mode), 'c', q.amount)) end
  from public.quick_expenses q
  where q.exp_date >= p_start and public._acct_need('quick_expense', q.id::text, q.status = 'done');

  -- cash moves (bank deposit / withdraw, owner top-up / draw, customer advances, hub receipt)
  return query
  select 'cash_move'::text, m.id::text, m.move_date, m.location_id, ('Cash move: ' || m.kind)::text, m.kind, m.status = 'done', (m.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when m.status = 'done' then case m.kind
      when 'bank_deposit' then jsonb_build_array(jsonb_build_object('a', 'pay_bank', 'd', m.amount), jsonb_build_object('a', 'pay_cash', 'c', m.amount))
      when 'bank_withdraw' then jsonb_build_array(jsonb_build_object('a', 'pay_cash', 'd', m.amount), jsonb_build_object('a', 'pay_bank', 'c', m.amount))
      when 'owner_topup' then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(m.mode), 'd', m.amount), jsonb_build_object('a', 'owner_capital', 'c', m.amount))
      when 'owner_draw' then jsonb_build_array(jsonb_build_object('a', 'owner_drawings', 'd', m.amount), jsonb_build_object('a', public._acct_paykey(m.mode), 'c', m.amount))
      when 'cust_advance' then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(m.mode), 'd', m.amount), jsonb_build_object('a', 'cust_advance', 'c', m.amount, 'pt', 'customer', 'pid', m.customer_id::text))
      when 'cust_advance_refund' then jsonb_build_array(jsonb_build_object('a', 'cust_advance', 'd', m.amount, 'pt', 'customer', 'pid', m.customer_id::text), jsonb_build_object('a', public._acct_paykey(m.mode), 'c', m.amount))
      when 'cust_advance_used' then jsonb_build_array(jsonb_build_object('a', 'cust_advance', 'd', m.amount, 'pt', 'customer', 'pid', m.customer_id::text), jsonb_build_object('a', 'receivable', 'c', m.amount, 'pt', 'customer', 'pid', m.customer_id::text))
      when 'hub_receipt' then jsonb_build_array(jsonb_build_object('a', 'pay_cash', 'd', m.amount), jsonb_build_object('a', 'hub_clearing', 'c', m.amount))
    end end
  from public.cash_moves m
  where m.move_date >= p_start and public._acct_need('cash_move', m.id::text, m.status = 'done');

  -- wastage at the real cost in the stock ledger
  return query
  select 'wastage'::text, w.id::text, (w.made_at at time zone 'Asia/Dhaka')::date, w.location_id, 'Wastage written off'::text, null::text, true, null::date,
    case when c.nulls > 0 and c.amt > 0 then 'cogs_missing' end,
    case when c.amt is null or c.amt <= 0 then 'cost_missing' end,
    case when c.amt > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'wastage', 'd', c.amt) j
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)
          from (select it.item_type t, round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l join public.items it on it.id = l.item_id
                where l.ref_type = 'wastage' and l.ref_id = w.id::text and l.reason = 'wastage' and l.unit_cost is not null group by it.item_type) z where z.amt > 0
      ) y) end
  from public.stock_wastage w cross join lateral (
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where l.unit_cost is null) nulls
    from public.stock_ledger l where l.ref_type = 'wastage' and l.ref_id = w.id::text and l.reason = 'wastage') c
  where (w.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('wastage', w.id::text, true);

  -- production: ingredients (at their real cost) move from raw / packaging to finished goods
  return query
  select 'production'::text, r.id::text, (r.made_at at time zone 'Asia/Dhaka')::date, r.location_id, 'Production run'::text, null::text, r.status = 'done', (r.void_at at time zone 'Asia/Dhaka')::date,
    case when c.nulls > 0 and c.amt > 0 then 'cogs_missing' end,
    case when r.status = 'done' and (c.amt is null or c.amt <= 0) then 'cost_missing' end,
    case when r.status = 'done' and c.amt > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'inv_finished', 'd', c.amt) j
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)
          from (select it.item_type t, round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l join public.items it on it.id = l.item_id
                where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out' and l.unit_cost is not null group by it.item_type) z where z.amt > 0
      ) y) end
  from public.production_runs r cross join lateral (
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where l.unit_cost is null) nulls
    from public.stock_ledger l where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out') c
  where (r.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('production', r.id::text, r.status = 'done');
end $function$;

CREATE OR REPLACE FUNCTION public._p27_pl(d1 date, d2 date, locs integer[])
 RETURNS TABLE(o_m date, o_loc integer, o_gross numeric, o_ret numeric, o_net numeric, o_costed numeric, o_cogs numeric, o_exp numeric, o_sal numeric, o_fixed numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with net_on as (select coalesce(public.rule_on('reports_net_of_returns'), true) as v),
  cst as (select ic.item_id, ic.cost_price from public.item_costs ic join public.items i on i.id = ic.item_id where i.count_in_business and ic.cost_price is not null),
  s as (select x.id, date_trunc('month', x.sale_date)::date as m, x.location_id, x.total, x.subtotal, x.lines from public.sales x
        where x.status = 'done' and x.sale_date between d1 and d2 and x.location_id = any (locs)),
  tot as (select m, location_id, sum(total) as rev from s group by 1, 2),
  ln as (
    select s.m, s.location_id, (case when s.subtotal > 0 then s.total / s.subtotal else 1 end) as f,
           case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'amount')::numeric end as amt,
           case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end as qty,
           case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end as iid
    from s, jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e),
  ag as (
    select ln.m, ln.location_id, sum(ln.amt * ln.f) filter (where c.cost_price is not null) as cr, sum(ln.qty * c.cost_price) filter (where c.cost_price is not null) as cg
    from ln left join cst c on c.item_id = ln.iid group by 1, 2),
  rr as (select r.id, date_trunc('month', (r.created_at at time zone 'Asia/Dhaka')::date)::date as m, r.location_id, r.amount, r.lines
         from public.sale_returns r, net_on
         where net_on.v and r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date between d1 and d2 and r.location_id = any (locs)),
  rt as (select m, location_id, sum(amount) as ra from rr group by 1, 2),
  rl as (
    select rr.m, rr.location_id, c.cost_price,
           case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'amount')::numeric end as amt,
           case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end as qty
    from rr cross join lateral jsonb_array_elements(case when jsonb_typeof(rr.lines) = 'array' then rr.lines else '[]'::jsonb end) e
    left join cst c on c.item_id = (case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end)),
  rg as (select m, location_id, sum(amt) filter (where cost_price is not null) as rcr, sum(qty * cost_price) filter (where cost_price is not null) as rcg from rl group by 1, 2),
  ex as (
    select u.m, u.location_id, sum(u.amt) as amt from (
      select date_trunc('month', e.entry_date)::date as m, e.location_id, public._r2_num(ln -> 'amount') as amt
      from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) ln
      where e.form_code = '10-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.entry_date between d1 and d2 and e.location_id = any (locs)
      union all  -- bos50: quick expenses
      select date_trunc('month', q.exp_date)::date, q.location_id, q.amount from public.quick_expenses q
      where q.status = 'done' and q.exp_date between d1 and d2 and q.location_id = any (locs)) u group by 1, 2),
  sa as (
    select date_trunc('month', e.entry_date)::date as m, e.location_id,
           sum(coalesce(public._r2_num(r -> 'due'), 0) + coalesce(public._r2_num(r -> 'overtime'), 0) + coalesce(public._r2_num(r -> 'other'), 0)) as amt
    from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'pay') = 'array' then e.data -> 'pay' else '[]'::jsonb end) r
    where e.form_code = '02-2' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs) group by 1, 2),
  k as (select m, location_id from tot union select m, location_id from rt union select m, location_id from ex union select m, location_id from sa)
  select k.m, k.location_id,
         coalesce(t.rev, 0), coalesce(x.ra, 0), coalesce(t.rev, 0) - coalesce(x.ra, 0),
         round(coalesce(a.cr, 0) - coalesce(g.rcr, 0), 2), round(coalesce(a.cg, 0) - coalesce(g.rcg, 0), 2),
         e.amt, s2.amt,
         case when fm.v is not null then round(fm.v * (least(d2, (k.m + interval '1 month')::date - 1) - greatest(d1, k.m) + 1)
                / extract(day from (k.m + interval '1 month' - interval '1 day')), 2) end
  from k
  left join tot t on t.m = k.m and t.location_id = k.location_id
  left join rt x on x.m = k.m and x.location_id = k.location_id
  left join ag a on a.m = k.m and a.location_id = k.location_id
  left join rg g on g.m = k.m and g.location_id = k.location_id
  left join ex e on e.m = k.m and e.location_id = k.location_id
  left join sa s2 on s2.m = k.m and s2.location_id = k.location_id
  left join lateral (select public._r2_num(ls.value) as v from public.location_settings ls where ls.location_id = k.location_id and ls.key = 'fixed_cost_month') fm on true;
$function$;

CREATE OR REPLACE FUNCTION public._r3q_e2_expense_trend(d1 date, d2 date, locs integer[], flt jsonb)
 RETURNS SETOF jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with ln as (select e.entry_date as d, coalesce(nullif(btrim(l ->> 'head'), ''), '-') as head, public._r2_num(l -> 'amount') as amt
                from public.entries e
                cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) l
               where e.form_code = '10-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.location_id = any (locs)
                 and e.entry_date between d1 - (d2 - d1 + 1) and d2
              union all  -- bos50: quick expenses
              select q.exp_date, coalesce(nullif(btrim(q.head), ''), '-'), q.amount from public.quick_expenses q
               where q.status = 'done' and q.location_id = any (locs) and q.exp_date between d1 - (d2 - d1 + 1) and d2),
  g as (select head, coalesce(sum(amt) filter (where d >= d1), 0) as cur, coalesce(sum(amt) filter (where d < d1), 0) as prev from ln group by head)
  select jsonb_build_object('head', coalesce(o.label_bn, g.head), 'current', g.cur, 'previous', g.prev, 'change', g.cur - g.prev,
      'change_pct', case when g.prev > 0 then round(100 * (g.cur - g.prev) / g.prev, 2) end)
    from g left join public.option_lists o on o.list_code = 'expense_heads' and o.value_code = g.head;
$function$;

notify pgrst, 'reload schema';

-- ===== phase51 =====
-- ============================================================
-- Phase 51 - P1 slice 4: stock issue / transfer / count (gaps #25), production (#26), owner top-up / draw (#27).
-- Run AFTER phase50. Idempotent (paste twice = no error). No existing row is changed or deleted.
--
--   STOCK + PRODUCTION  path A = the stock screen / recipe run, path B = the paper form (04-2 issue, 03-1 transfer, 04-3 count, 05-1 factory sheet).
--       Rule "never both posting": exactly one of them posts to the stock ledger.
--       primary a (owner default): the screen / recipe run posts; an approved form is a reference - its lines are kept as "skipped: covered_by_screen",
--                                  nothing is posted twice.
--       primary b:                 the form posts (needs forms_post_to_ledger ON as before); the stock screen / recipe run cannot post the same action.
--       A path the owner has locked takes no new record.  Reversals / voids are never blocked.
--   OWNER MONEY  path A = partner capital (contribution / owner_drawing), path B = cash move (owner_topup / owner_draw).
--       Today only the cash move reaches the day book and the journal, partner capital is an equity sub-ledger, so nothing is counted twice now.
--       owner_money_link() joins the two records of one event (primary per the switch); the shadow is excluded from counting once partner capital
--       is auto-posted (P2, gap #6). Guards refuse a new record on a locked path.
--   Re-created from their latest definitions (only lines marked bos51 differ): entry_post_ledger, _elp_post_line.
-- ============================================================

-- ---------- 1. screen / recipe-run side: BEFORE INSERT guard on the stock ledger ----------
create or replace function public._stock_ledger_path_guard51() returns trigger
language plpgsql security definer set search_path = public as $$
declare d text;
begin
  if new.reverses_id is not null or coalesce(current_setting('bos.form_post', true), '') = '1' then return new; end if;
  d := case when new.reason = 'issue_out' and new.ref_type = 'issue' then 'stock_issue'
            when new.reason = 'count_adjust' and new.ref_type = 'count' then 'stock_count'
            when new.reason = 'transfer_out' and new.ref_type = 'transfer' then 'stock_transfer'
            when new.reason = 'production_in' and new.ref_type = 'production' then 'production' end;
  if d is null then return new; end if;
  perform public.path_guard(d, new.location_id, 'a');
  if public.path_primary(d, new.location_id) = 'b' then
    raise exception 'path_locked: % - the paper form is the record here (owner switch), the screen cannot post this action', d;
  end if;
  return new;
end $$;
drop trigger if exists stock_ledger_path_guard51 on public.stock_ledger;
create trigger stock_ledger_path_guard51 before insert on public.stock_ledger for each row execute function public._stock_ledger_path_guard51();

-- ---------- 2. owner money: guards + the link ----------
create or replace function public._partner_capital_guard51() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.kind in ('contribution', 'owner_drawing') then perform public.path_guard('owner_money', 0, 'a'); end if;
  return new;
end $$;
drop trigger if exists partner_capital_path_guard51 on public.partner_capital;
create trigger partner_capital_path_guard51 before insert on public.partner_capital for each row execute function public._partner_capital_guard51();

create or replace function public._cash_moves_guard51() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.kind in ('owner_topup', 'owner_draw') then perform public.path_guard('owner_money', new.location_id, 'b'); end if;
  return new;
end $$;
drop trigger if exists cash_moves_path_guard51 on public.cash_moves;
create trigger cash_moves_path_guard51 before insert on public.cash_moves for each row execute function public._cash_moves_guard51();

-- owner joins the two records of ONE event: contribution <-> owner_topup, owner_drawing <-> owner_draw (same amount). The primary follows the switch:
-- a = partner capital is the record (cash move = shadow), b = cash move is the record, first = the earlier record.
create or replace function public.owner_money_link(p_capital bigint, p_cash uuid, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.partner_capital; m public.cash_moves; prim text; cash_first boolean; lk bigint;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select * into c from public.partner_capital where id = p_capital;
  if not found or c.status <> 'posted' then raise exception 'capital_not_found'; end if;
  select * into m from public.cash_moves where id = p_cash;
  if not found or m.status <> 'done' then raise exception 'cash_move_not_found'; end if;
  if not ((c.kind = 'contribution' and m.kind = 'owner_topup') or (c.kind = 'owner_drawing' and m.kind = 'owner_draw')) then raise exception 'kind_mismatch'; end if;
  if c.amount <> m.amount then raise exception 'amount_mismatch'; end if;
  prim := public.path_primary('owner_money', m.location_id);
  if prim = 'first' then cash_first := m.created_at < c.created_at; else cash_first := (prim = 'b'); end if;
  if cash_first then lk := public.shadow_link_add('owner_money', m.location_id, 'cash_moves', m.id::text, 'partner_capital', c.id::text, coalesce(p_note, 'partner capital kept as a copy'));
  else lk := public.shadow_link_add('owner_money', m.location_id, 'partner_capital', c.id::text, 'cash_moves', m.id::text, coalesce(p_note, 'cash move kept as a copy')); end if;
  return jsonb_build_object('link', lk, 'primary', case when cash_first then 'cash_move' else 'partner_capital' end);
end $$;
revoke all on function public.owner_money_link(bigint, uuid, text) from public, anon;
grant execute on function public.owner_money_link(bigint, uuid, text) to authenticated;
revoke all on function public._stock_ledger_path_guard51(), public._partner_capital_guard51(), public._cash_moves_guard51() from public, anon, authenticated;

-- ---------- 3. form side: a form is a reference while the screen is primary ----------
CREATE OR REPLACE FUNCTION public._elp_post_line(e entries, g integer, sg text, l jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it public.items; n int := (l->>'n')::int; kind text := l->>'kind'; qty numeric := nullif(l->>'qty', '')::numeric; bq numeric; f numeric; ucb numeric;
        ref text := e.id::text || ':g' || g::text || ':' || n::text; lid bigint; olid bigint; bal public.stock_balance; d numeric; tid uuid; fl int := nullif(l->>'from', '')::int;
        tl int := nullif(l->>'to', '')::int; rq numeric; rbq numeric; note text := nullif(l->>'note', ''); at_ timestamptz := now(); sl jsonb; exp timestamptz; bid bigint; sid text;
        stt text := 'posted'; why text; ucost numeric;
begin
  -- phase 23: the purchase page already posts bought goods; a GRN (04-1) 'in' line would count them twice unless the owner chose the GRN as the source
  if l->>'skip' is null and kind = 'in' and e.form_code = '04-1' and coalesce(public.rule_txt('grn_receipt_source'), 'purchase') = 'purchase' then
    insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, posted_by)
      values (e.id, g, n, e.form_code, e.location_id, null, kind, (select i.id from public.items i where i.code = l->>'item'), left(l->>'item', 60), null, sg, 'skipped', 'covered_by_purchase_page', ref, auth.uid());
    return;
  end if;
  -- bos51: while the stock screen / recipe run is the record (owner switch), a form line is a reference: kept, shown as skipped, never posted a second time
  if l->>'skip' is null and public._entry_domain(e.form_code) is not null and public.path_primary(public._entry_domain(e.form_code), e.location_id) = 'a' then
    insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, posted_by)
      values (e.id, g, n, e.form_code, e.location_id, tl, kind, (select i.id from public.items i where i.code = l->>'item'), left(l->>'item', 60), null, sg, 'skipped', 'covered_by_screen', ref, auth.uid());
    return;
  end if;
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
end $function$;

CREATE OR REPLACE FUNCTION public.entry_post_ledger(p_entry uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  perform set_config('bos.form_post', '1', true);  -- bos51: rows posted by a form are not blocked by the screen guard
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
  perform set_config('bos.form_post', '', true);  -- bos51
  select count(*) filter (where status = 'posted'), count(*) filter (where status = 'failed'), count(*) filter (where status = 'skipped') into nposted, nfail, nskip
    from public.entry_ledger_posts where entry_id = e.id and gen = g;
  perform public._elp_exceptions(e, g);
  return jsonb_build_object('ok', true, 'enabled', true, 'gen', g, 'posted', nposted, 'failed', nfail, 'skipped', nskip);
end $function$;

notify pgrst, 'reload schema';

