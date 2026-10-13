-- ============================================================
-- PHASE 28 (groups C+D): parallel-month comparison (pairs, daily rows, month-end Pass / Fail), Print & books (paper book register, print notes),
--   "Needs you" oldest-first list. Additive and idempotent (paste twice = no error). Needs phase17 (form_rollout, rollout_set) and phase8.
--   * comparison_pairs: named by the OWNER (created empty - nothing is invented). comparison_days: one row per pair x place x day, the keeper writes the paper figure,
--     another person the app figure; the same person cannot do both on a row; result match / differ / waiting is computed.
--   * parallel_month_decide(form, place, month, pass, note): owner only, after the month has ended. Pass needs at least one comparison day, none waiting, every differ with a
--     reason and a fix; it then sets the form x place to 'app' (rollout_set) and records the decision. Fail records why; the form stays parallel.
--   * paper_books: first / last serial of each printed book per form x place; paper_books_check() lists gaps and overlaps; print_notes: what to change at the next print
--     (created when a place is renamed or closed, or by hand), cleared only by recording the new print (date + who).
--   * needs_you_oldest(limit): the oldest waiting things the caller may decide, oldest first.
-- Nothing is hard-deleted. Settings switches: rules parallel_compare_on (ON) and print_notes_auto (ON).
-- ============================================================

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('parallel_compare_on', 'entries', 'switch', 'true', null, null, null, null, 'পাশাপাশি মাস: দৈনিক তুলনা ও মাস-শেষের পাস/ফেল', 'Parallel মাস: daily comparison ও month-end pass/fail', 'Parallel month: daily comparison and month-end pass / fail',
  'বন্ধ করলে মাস-শেষে পাস/ফেল ছাড়াই মালিক নিজে কাগজ→অ্যাপ বদলাতে পারবেন (আগের মতো)।', 'Off = the owner can move paper→app without the month-end pass / fail (as before).', 90),
 ('print_notes_auto', 'settings', 'switch', 'true', null, null, null, null, 'জায়গার নাম বদল/বন্ধে ছাপার নোট নিজে হবে', 'জায়গার নাম বদল/বন্ধে print note নিজে হবে', 'Print note is made when a place is renamed or closed',
  'পরের ছাপায় কী বদলাতে হবে তার নোট। ছাপার তারিখ লেখা না হওয়া পর্যন্ত নোট থাকে।', 'A note of what to change at the next print; it stays until the new print is recorded.', 91)
 on conflict (key) do nothing;

-- ---------- parallel comparison ----------
create table if not exists public.comparison_pairs (
  id bigserial primary key,
  form_code text not null references public.forms(code),
  name_bn text not null, name_en text,
  how_paper text, how_app text,                     -- how each figure is read, in words (the owner defines them)
  is_active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now()
);
create table if not exists public.comparison_days (
  id bigserial primary key,
  pair_id bigint not null references public.comparison_pairs(id),
  form_code text not null references public.forms(code),
  location_id int not null references public.locations(id),
  day date not null,
  paper_value numeric check (paper_value is null or abs(paper_value) <= 1000000000000),
  app_value numeric check (app_value is null or abs(app_value) <= 1000000000000),
  result text not null default 'waiting' check (result in ('match', 'differ', 'waiting')),
  reason text, fix text,
  keeper_user uuid, enterer_user uuid,
  keeper_at timestamptz, enterer_at timestamptz,
  unique (pair_id, location_id, day),
  check (keeper_user is null or enterer_user is null or keeper_user <> enterer_user)
);
create table if not exists public.parallel_months (
  form_code text not null references public.forms(code),
  location_id int not null references public.locations(id),
  month date not null,                              -- first day of the month
  result text not null check (result in ('pass', 'fail')),
  note text, days int, differ int,
  decided_by uuid, decided_at timestamptz not null default now(),
  primary key (form_code, location_id, month)
);
do $$ declare t text; begin
  foreach t in array array['comparison_pairs', 'comparison_days', 'parallel_months'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.is_active())', t || '_read', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop trigger if exists %I on public.%I', 'audit_' || t, t);
    execute format('create trigger %I after insert or update on public.%I for each row execute function public.log_change(%L)', 'audit_' || t, t, case when t = 'parallel_months' then 'form_code,location_id,month' else 'id' end);
    execute format('drop trigger if exists %I on public.%I', t || '_no_delete', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_no_delete', t);
  end loop;
end $$;

create or replace function public._par_mgr() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('rollout_manage'));
$$;

create or replace function public.comparison_pair_save(p_form text, p_name_bn text, p_name_en text default null, p_how_paper text default null, p_how_app text default null,
  p_id bigint default null, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare nid bigint;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_name_bn is null or length(btrim(p_name_bn)) < 2 then raise exception 'name_required'; end if;
  if not exists (select 1 from public.forms where code = p_form) then raise exception 'form_not_found'; end if;
  if p_id is null then
    insert into public.comparison_pairs (form_code, name_bn, name_en, how_paper, how_app, is_active, created_by)
      values (p_form, left(btrim(p_name_bn), 120), left(nullif(btrim(p_name_en), ''), 120), left(nullif(btrim(p_how_paper), ''), 300), left(nullif(btrim(p_how_app), ''), 300), coalesce(p_active, true), auth.uid()) returning id into nid;
  else
    update public.comparison_pairs set name_bn = left(btrim(p_name_bn), 120), name_en = left(nullif(btrim(p_name_en), ''), 120), how_paper = left(nullif(btrim(p_how_paper), ''), 300),
      how_app = left(nullif(btrim(p_how_app), ''), 300), is_active = coalesce(p_active, true) where id = p_id and form_code = p_form returning id into nid;
    if nid is null then raise exception 'not_found'; end if;
  end if;
  return jsonb_build_object('id', nid);
end $$;

-- the keeper writes the paper figure, someone else the app figure; role = 'paper' | 'app'
create or replace function public.comparison_record(p_pair bigint, p_loc int, p_day date, p_role text, p_value numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pr public.comparison_pairs; r public.comparison_days; today date := (now() at time zone 'Asia/Dhaka')::date;
begin
  if not public.is_active() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if p_role not in ('paper', 'app') then raise exception 'bad_role'; end if;
  if p_value is null or abs(p_value) > 1000000000000 then raise exception 'bad_amount'; end if;
  if p_day is null or p_day > today or p_day < today - 62 then raise exception 'bad_date'; end if;
  select * into pr from public.comparison_pairs where id = p_pair and is_active;
  if not found then raise exception 'pair_not_found'; end if;
  if public.rollout_mode(pr.form_code, p_loc) is distinct from 'parallel' then raise exception 'not_parallel'; end if;
  if not (public.is_owner() or public.can_do(pr.form_code, 'enter') or public.can_do(pr.form_code, 'approve') or public.has_grant('rollout_manage', p_loc)) then raise exception 'not allowed'; end if;
  insert into public.comparison_days (pair_id, form_code, location_id, day) values (p_pair, pr.form_code, p_loc, p_day) on conflict (pair_id, location_id, day) do nothing;
  select * into r from public.comparison_days where pair_id = p_pair and location_id = p_loc and day = p_day for update;
  if p_role = 'paper' then
    if r.enterer_user = auth.uid() then raise exception 'keeper_is_enterer'; end if;
    if r.paper_value is not null and r.keeper_user is distinct from auth.uid() then raise exception 'already_recorded'; end if;
    update public.comparison_days set paper_value = round(p_value, 4), keeper_user = auth.uid(), keeper_at = now() where id = r.id;
  else
    if r.keeper_user = auth.uid() then raise exception 'keeper_is_enterer'; end if;
    if r.app_value is not null and r.enterer_user is distinct from auth.uid() then raise exception 'already_recorded'; end if;
    update public.comparison_days set app_value = round(p_value, 4), enterer_user = auth.uid(), enterer_at = now() where id = r.id;
  end if;
  update public.comparison_days set result = case when paper_value is null or app_value is null then 'waiting' when abs(paper_value - app_value) < 0.005 then 'match' else 'differ' end
    where id = r.id returning * into r;
  return jsonb_build_object('id', r.id, 'result', r.result);
end $$;

create or replace function public.comparison_explain(p_id bigint, p_reason text, p_fix text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.comparison_days;
begin
  select * into r from public.comparison_days where id = p_id for update;
  if not found or not public.can_loc(r.location_id) then raise exception 'not allowed'; end if;
  if not (public.is_owner() or public.has_grant('rollout_manage', r.location_id) or r.keeper_user = auth.uid() or r.enterer_user = auth.uid()) then raise exception 'not allowed'; end if;
  if r.result <> 'differ' then raise exception 'not_differ'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 or p_fix is null or length(btrim(p_fix)) < 3 then raise exception 'reason_and_fix_required'; end if;
  update public.comparison_days set reason = left(btrim(p_reason), 300), fix = left(btrim(p_fix), 300) where id = r.id;
  return jsonb_build_object('id', r.id);
end $$;

create or replace function public.parallel_month_status(p_form text, p_loc int, p_month date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m date := date_trunc('month', coalesce(p_month, (now() at time zone 'Asia/Dhaka')::date))::date; today date := (now() at time zone 'Asia/Dhaka')::date;
        n int; mt int; df int; dfx int; wt int; pairs int; dec public.parallel_months; ended boolean;
begin
  if not public.is_active() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  select count(*) into pairs from public.comparison_pairs where form_code = p_form and is_active;
  select count(*), count(*) filter (where result = 'match'), count(*) filter (where result = 'differ'), count(*) filter (where result = 'differ' and nullif(btrim(coalesce(reason, '')), '') is not null and nullif(btrim(coalesce(fix, '')), '') is not null),
         count(*) filter (where result = 'waiting')
    into n, mt, df, dfx, wt from public.comparison_days where form_code = p_form and location_id = p_loc and day >= m and day < (m + interval '1 month')::date;
  select * into dec from public.parallel_months where form_code = p_form and location_id = p_loc and month = m;
  ended := (m + interval '1 month')::date <= today;
  return jsonb_build_object('form', p_form, 'location_id', p_loc, 'month', m, 'mode', public.rollout_mode(p_form, p_loc), 'pairs', pairs, 'days', n, 'match', mt, 'differ', df, 'differ_explained', dfx, 'waiting', wt,
    'month_ended', ended, 'decision', case when dec.form_code is null then null else jsonb_build_object('result', dec.result, 'note', dec.note, 'at', dec.decided_at) end,
    'pass_ready', ended and pairs > 0 and n > 0 and wt = 0 and df = dfx and dec.form_code is null);
end $$;

create or replace function public.parallel_month_decide(p_form text, p_loc int, p_month date, p_pass boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m date := date_trunc('month', p_month)::date; st jsonb; today date := (now() at time zone 'Asia/Dhaka')::date;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_pass is null then raise exception 'bad_value'; end if;
  if public.rollout_mode(p_form, p_loc) is distinct from 'parallel' then raise exception 'not_parallel'; end if;
  if (m + interval '1 month')::date > today then raise exception 'month_not_ended'; end if;
  if exists (select 1 from public.parallel_months where form_code = p_form and location_id = p_loc and month = m) then raise exception 'already_decided'; end if;
  if not p_pass and (p_note is null or length(btrim(p_note)) < 3) then raise exception 'note_required'; end if;
  st := public.parallel_month_status(p_form, p_loc, m);
  if p_pass and public.rule_on('parallel_compare_on') then
    if (st ->> 'pairs')::int = 0 then raise exception 'no_pair_named'; end if;
    if (st ->> 'days')::int = 0 then raise exception 'no_comparison_days'; end if;
    if (st ->> 'waiting')::int > 0 then raise exception 'days_waiting'; end if;
    if (st ->> 'differ')::int <> (st ->> 'differ_explained')::int then raise exception 'differ_without_reason'; end if;
  end if;
  insert into public.parallel_months (form_code, location_id, month, result, note, days, differ, decided_by)
    values (p_form, p_loc, m, case when p_pass then 'pass' else 'fail' end, left(nullif(btrim(p_note), ''), 300), (st ->> 'days')::int, (st ->> 'differ')::int, auth.uid());
  if p_pass then perform public.rollout_set(p_form, p_loc, 'app', 'parallel month ' || to_char(m, 'YYYY-MM') || ' passed'); end if;
  return jsonb_build_object('result', case when p_pass then 'pass' else 'fail' end, 'month', m);
end $$;

-- forms x places that are in parallel and whose last full month still has no decision (the owner's waiting list)
create or replace function public.parallel_waiting() returns table (form_code text, location_id int, month date)
language sql stable security definer set search_path = public as $$
  select r.form_code, r.location_id, (date_trunc('month', (now() at time zone 'Asia/Dhaka')::date) - interval '1 month')::date
    from public.form_rollout r
   where r.mode = 'parallel' and public.is_owner() and public.rule_on('parallel_compare_on')
     and exists (select 1 from public.comparison_days d where d.form_code = r.form_code and d.location_id = r.location_id
                   and d.day >= (date_trunc('month', (now() at time zone 'Asia/Dhaka')::date) - interval '1 month')::date and d.day < date_trunc('month', (now() at time zone 'Asia/Dhaka')::date)::date)
     and not exists (select 1 from public.parallel_months p where p.form_code = r.form_code and p.location_id = r.location_id
                   and p.month = (date_trunc('month', (now() at time zone 'Asia/Dhaka')::date) - interval '1 month')::date);
$$;

-- ---------- print & books ----------
create table if not exists public.paper_books (
  id bigserial primary key,
  form_code text not null references public.forms(code),
  location_id int not null references public.locations(id),
  prefix text, first_no bigint not null check (first_no >= 0), last_no bigint not null,
  issued_on date, holder text, note text,
  status text not null default 'active' check (status in ('active', 'used', 'void')),
  created_by uuid, created_at timestamptz not null default now(),
  check (last_no >= first_no)
);
create index if not exists paper_books_fl on public.paper_books (form_code, location_id, first_no);
create table if not exists public.print_notes (
  id bigserial primary key,
  form_code text references public.forms(code),   -- null = every printed form that carries a place line
  location_id int not null references public.locations(id),
  reason text not null, change_to text,
  created_by uuid, created_at timestamptz not null default now(),
  cleared_on date, cleared_by uuid, cleared_at timestamptz
);
do $$ declare t text; begin
  foreach t in array array['paper_books', 'print_notes'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.is_owner() or public.has_grant(%L) or public.has_grant(%L, location_id))', t || '_read', t, 'head_management', 'print_books');
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop trigger if exists %I on public.%I', 'audit_' || t, t);
    execute format('create trigger %I after insert or update on public.%I for each row execute function public.log_change(%L)', 'audit_' || t, t, 'id');
    execute format('drop trigger if exists %I on public.%I', t || '_no_delete', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_no_delete', t);
  end loop;
end $$;
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'print_books', 'master', 64, 'ছাপা ও বই: সিরিয়াল ও ছাপার নোট লেখা', 'Print ও books: serial ও print note লেখা', 'Print & books: record serials and print notes', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'print_books');

create or replace function public._books_mgr(p_loc int default null) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('head_management') or public.has_grant('print_books', p_loc));
$$;

create or replace function public.paper_book_add(p_form text, p_loc int, p_first bigint, p_last bigint, p_prefix text default null, p_issued date default null, p_holder text default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare nid bigint; ov record;
begin
  if not public._books_mgr(p_loc) or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.forms where code = p_form) or not exists (select 1 from public.locations where id = p_loc) then raise exception 'not_found'; end if;
  if p_first is null or p_last is null or p_first < 0 or p_last < p_first or p_last > 999999999999 then raise exception 'bad_range'; end if;
  select * into ov from public.paper_books b where b.form_code = p_form and b.location_id = p_loc and b.status <> 'void' and coalesce(b.prefix, '') = coalesce(nullif(btrim(p_prefix), ''), '') and p_first <= b.last_no and p_last >= b.first_no limit 1;
  if found then raise exception 'books_overlap' using detail = ov.first_no::text || '-' || ov.last_no::text; end if;
  insert into public.paper_books (form_code, location_id, prefix, first_no, last_no, issued_on, holder, note, created_by)
    values (p_form, p_loc, nullif(btrim(p_prefix), ''), p_first, p_last, p_issued, left(nullif(btrim(p_holder), ''), 80), left(nullif(btrim(p_note), ''), 300), auth.uid()) returning id into nid;
  return jsonb_build_object('id', nid);
end $$;

create or replace function public.paper_book_set_status(p_id bigint, p_status text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare b public.paper_books;
begin
  select * into b from public.paper_books where id = p_id for update;
  if not found or not public._books_mgr(b.location_id) or not public.can_loc(b.location_id) then raise exception 'not allowed'; end if;
  if p_status not in ('active', 'used', 'void') then raise exception 'bad_value'; end if;
  if p_status = 'void' and (p_note is null or length(btrim(p_note)) < 3) then raise exception 'note_required'; end if;
  update public.paper_books set status = p_status, note = coalesce(left(nullif(btrim(p_note), ''), 300), note) where id = p_id;
  return jsonb_build_object('id', p_id, 'status', p_status);
end $$;

-- gaps and overlaps between the books of one form x place, and the first serial the app may use next
create or replace function public.paper_books_check(p_form text, p_loc int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare prev public.paper_books; b public.paper_books; issues jsonb := '[]'::jsonb; mx bigint;
begin
  if not public._books_mgr(p_loc) or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  for b in select * from public.paper_books where form_code = p_form and location_id = p_loc and status <> 'void' order by coalesce(prefix, ''), first_no loop
    if prev.id is not null and coalesce(prev.prefix, '') = coalesce(b.prefix, '') then
      if b.first_no <= prev.last_no then issues := issues || jsonb_build_array(jsonb_build_object('type', 'overlap', 'from', prev.last_no, 'to', b.first_no));
      elsif b.first_no > prev.last_no + 1 then issues := issues || jsonb_build_array(jsonb_build_object('type', 'gap', 'from', prev.last_no + 1, 'to', b.first_no - 1)); end if;
    end if;
    prev := b;
  end loop;
  select max(last_no) into mx from public.paper_books where form_code = p_form and location_id = p_loc and status <> 'void';
  return jsonb_build_object('issues', issues, 'last_paper_no', mx, 'app_continues_from', case when mx is null then null else mx + 1 end);
end $$;

create or replace function public.print_note_add(p_loc int, p_form text, p_reason text, p_change text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare nid bigint;
begin
  if not public._books_mgr(p_loc) or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  if p_form is not null and not exists (select 1 from public.forms where code = p_form) then raise exception 'form_not_found'; end if;
  insert into public.print_notes (form_code, location_id, reason, change_to, created_by) values (p_form, p_loc, left(btrim(p_reason), 300), left(nullif(btrim(p_change), ''), 300), auth.uid()) returning id into nid;
  return jsonb_build_object('id', nid);
end $$;

create or replace function public.print_note_clear(p_id bigint, p_printed_on date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare n public.print_notes;
begin
  select * into n from public.print_notes where id = p_id for update;
  if not found or not public._books_mgr(n.location_id) or not public.can_loc(n.location_id) then raise exception 'not allowed'; end if;
  if n.cleared_at is not null then return jsonb_build_object('id', n.id, 'dup', true); end if;
  if p_printed_on is null or p_printed_on > (now() at time zone 'Asia/Dhaka')::date + 1 or p_printed_on < date '2000-01-01' then raise exception 'bad_date'; end if;
  update public.print_notes set cleared_on = p_printed_on, cleared_by = auth.uid(), cleared_at = now() where id = n.id;
  return jsonb_build_object('id', n.id);
end $$;

-- a place renamed or closed -> one note (null form = every printed form with a place line)
create or replace function public._loc_print_note() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.rule_on('print_notes_auto') then return new; end if;
  if new.name_bn is distinct from old.name_bn or new.name_en is distinct from old.name_en or new.name_mix is distinct from old.name_mix then
    insert into public.print_notes (form_code, location_id, reason, change_to, created_by)
      values (null, new.id, 'place renamed: ' || coalesce(old.name_bn, '') || ' -> ' || coalesce(new.name_bn, ''), 'Change the place line at the next print', auth.uid());
  end if;
  if new.status is distinct from old.status and new.status = 'closed' then
    insert into public.print_notes (form_code, location_id, reason, change_to, created_by) values (null, new.id, 'place closed: ' || coalesce(new.name_bn, ''), 'Remove the place from the next print', auth.uid());
  end if;
  return new;
end $$;
drop trigger if exists locations_print_note on public.locations;
create trigger locations_print_note after update on public.locations for each row execute function public._loc_print_note();

-- ---------- Needs you: the oldest waiting things the caller may decide ----------
create or replace function public.needs_you_oldest(p_limit int default 8) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out_ jsonb; lim int := least(greatest(coalesce(p_limit, 8), 1), 30);
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.since), '[]'::jsonb) into out_ from (
    select * from (
      select 'entry'::text kind, e.id::text id, e.form_code || ' #' || coalesce(e.serial::text, '') as label, e.location_id, e.submitted_at as since, ('entry/' || e.id)::text as route
        from public.entries e where e.status = 'submitted' and public.can_loc(e.location_id) and (public.is_owner() or public.can_do(e.form_code, 'approve')) and e.created_by is distinct from auth.uid()
      union all
      select 'release', r.id::text, r.flag_code, (select en.location_id from public.entries en where en.id = r.entry_id), r.requested_at, 'releases'
        from public.release_requests r where r.status = 'pending' and public._release_can_see(r.entry_id)
      union all
      select 'emergency', q.id::text, q.grant_code, q.location_id, q.created_at, 'emergency' from public.emergency_requests q where q.status = 'pending' and public.is_owner()
      union all
      select 'item_change', c.id::text, 'item change', null::int, c.requested_at, 'itemreq' from public.item_changes c where c.status = 'pending' and (public.is_owner() or public.has_grant('item_create') or public.can_do('ITEMS', 'approve'))
      union all
      select 'staff', p.id::text, coalesce(p.full_name, p.staff_id), null::int, p.created_at, 'staff' from public.profiles p where p.status = 'pending' and public.is_owner()
      union all
      select 'wastage', w.id::text, 'wastage', w.location_id, w.requested_at, 'stock' from public.wastage_requests w where w.status = 'pending' and public.can_loc(w.location_id) and public.has_grant('wastage_approve', w.location_id) and w.requested_by is distinct from auth.uid()
      union all
      select 'parallel', pw.form_code || ':' || pw.location_id, pw.form_code || ' ' || to_char(pw.month, 'YYYY-MM'), pw.location_id, (pw.month + interval '1 month')::timestamptz, 'parallel' from public.parallel_waiting() pw
    ) u where u.since is not null order by u.since limit lim
  ) x;
  return out_;
end $$;

revoke all on function public._par_mgr(), public._books_mgr(int), public._loc_print_note(), public.comparison_pair_save(text, text, text, text, text, bigint, boolean), public.comparison_record(bigint, int, date, text, numeric),
  public.comparison_explain(bigint, text, text), public.parallel_month_status(text, int, date), public.parallel_month_decide(text, int, date, boolean, text), public.parallel_waiting(),
  public.paper_book_add(text, int, bigint, bigint, text, date, text, text), public.paper_book_set_status(bigint, text, text), public.paper_books_check(text, int),
  public.print_note_add(int, text, text, text), public.print_note_clear(bigint, date), public.needs_you_oldest(int) from public, anon;
revoke all on function public._par_mgr(), public._books_mgr(int), public._loc_print_note() from authenticated;
grant execute on function public.comparison_pair_save(text, text, text, text, text, bigint, boolean), public.comparison_record(bigint, int, date, text, numeric),
  public.comparison_explain(bigint, text, text), public.parallel_month_status(text, int, date), public.parallel_month_decide(text, int, date, boolean, text), public.parallel_waiting(),
  public.paper_book_add(text, int, bigint, bigint, text, date, text, text), public.paper_book_set_status(bigint, text, text), public.paper_books_check(text, int),
  public.print_note_add(int, text, text, text), public.print_note_clear(bigint, date), public.needs_you_oldest(int) to authenticated;
notify pgrst, 'reload schema';
