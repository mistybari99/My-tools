-- ============================================================
-- Phase 46 - Module F: automatic backup + notifications (in-app bell, Gmail digest / alerts)
-- Run AFTER phase28. Additive and idempotent (paste it twice = no error). Nothing is hard-deleted.
--
-- Who does what
--   * The OWNER marks one dedicated, least-privilege Supabase Auth user as the "ops bot":  select ops_account_set('<user uuid>', 'backup', true);
--     (and 'notify'). The bot is NOT an owner, has no roles and sees no tables directly. It can call only the functions below.
--     The service_role key is never used.
--   * backup_dump / backup_manifest / backup_log  -> bot with purpose 'backup'  (GitHub Actions, tools/backup_dump.py)
--   * notify_scan / daily_digest / urgent_alerts / notifications_mark_emailed / notify_config -> bot with purpose 'notify' (or the owner)
--   * notifications_for_me / notification_read / notification_read_all / notifications_unread_count -> every active user (the bell)
--
-- Backup whitelist (backup_dump / backup_manifest): every BASE TABLE in schema public EXCEPT
--     - names containing "_secret", names starting "ops_"
--     - login data: login_failures, login_attempts, login_throttle
--     - the module's own run-time tables: backup_runs, notifications, notification_reads (re-created by the app; not business records)
--     - any table that has a column named like password / passwd / pin_hash / secret / token / salt / api_key / private_key
--   The list is computed at call time (public._backup_tables()), so new tables are included automatically.
--   Schemas auth / storage are never included (only schema public is read).
--
-- Rules (Switchboard / Settings): notify_*  switches and thresholds, day_close_deadline, backup_max_age_hours, notify_digest_times.
-- Timezone: Asia/Dhaka for "today". Money is numeric, rounded to 2.
-- ============================================================

-- ---------- ops accounts ----------
create table if not exists public.ops_accounts (
  user_id uuid not null references public.profiles(id),
  purpose text not null check (purpose in ('backup', 'notify')),
  active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  primary key (user_id, purpose)
);
create table if not exists public.backup_runs (
  id bigserial primary key,
  started_at timestamptz not null default now(), finished_at timestamptz not null default now(),
  status text not null check (status in ('ok', 'failed', 'partial')),
  tables int, rows bigint, bytes bigint,
  detail jsonb not null default '{}'::jsonb,
  destination text not null default 'github',
  logged_by uuid
);
create table if not exists public.notifications (
  id bigserial primary key,
  user_id uuid references public.profiles(id),                       -- null = everybody the audience covers
  audience text not null default 'owner' check (audience in ('owner', 'manager', 'all')),
  kind text not null check (kind ~ '^[a-z_]{2,40}$'),
  level text not null default 'info' check (level in ('info', 'warn', 'bad')),
  title_bn text not null, title_en text not null, body_bn text, body_en text,
  route text, location_id int references public.locations(id),
  key text not null default '' check (length(key) <= 80),
  day date not null default ((now() at time zone 'Asia/Dhaka')::date),
  created_at timestamptz not null default now(),
  read_at timestamptz, read_by uuid,                                  -- only for a note aimed at one user; per-user reads live in notification_reads
  emailed_at timestamptz,
  unique (kind, key, day)
);
create index if not exists notifications_recent on public.notifications (id desc);
create table if not exists public.notification_reads (
  notification_id bigint not null references public.notifications(id),
  user_id uuid not null, read_at timestamptz not null default now(),
  primary key (notification_id, user_id)
);

do $$ declare t text; begin
  foreach t in array array['ops_accounts', 'backup_runs', 'notifications', 'notification_reads'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop trigger if exists %I on public.%I', t || '_no_delete', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_no_delete', t);
  end loop;
end $$;
revoke usage, select on sequence public.backup_runs_id_seq, public.notifications_id_seq from public, anon, authenticated;

drop trigger if exists audit_ops_accounts on public.ops_accounts;
create trigger audit_ops_accounts after insert or update on public.ops_accounts for each row execute function public.log_change('user_id,purpose');

-- ---------- helpers (not callable from the browser) ----------
create or replace function public._is_ops(p_purpose text) returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and exists (select 1 from public.ops_accounts o where o.user_id = auth.uid() and o.purpose = p_purpose and o.active);
$$;
create or replace function public._today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;

-- who may see a note: aimed at me, or for everybody its audience covers (and the place, when it names one)
create or replace function public._notif_ok(p_user uuid, p_aud text, p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (
    case when p_user is not null then p_user = auth.uid()
         else (p_aud = 'all'
               or public.is_owner()
               or (p_aud = 'manager' and exists (select 1 from public.user_roles r where r.user_id = auth.uid()
                     and r.role_code in ('management', 'showroom_manager', 'cash_controller', 'factory_incharge', 'purchasing', 'hr')))) end
    and (p_loc is null or p_user is not null or public.can_loc(p_loc)));
$$;

drop policy if exists ops_accounts_read on public.ops_accounts;
create policy ops_accounts_read on public.ops_accounts for select to authenticated using (public.is_owner());
drop policy if exists backup_runs_read on public.backup_runs;
create policy backup_runs_read on public.backup_runs for select to authenticated using (public.is_owner());
drop policy if exists notifications_read on public.notifications;
create policy notifications_read on public.notifications for select to authenticated using (public._notif_ok(user_id, audience, location_id));
drop policy if exists notification_reads_read on public.notification_reads;
create policy notification_reads_read on public.notification_reads for select to authenticated using (user_id = auth.uid());

-- the owner marks (or retires) an ops bot
create or replace function public.ops_account_set(p_user uuid, p_purpose text, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_user is null or p_purpose not in ('backup', 'notify') or p_active is null then raise exception 'bad_input'; end if;
  if not exists (select 1 from public.profiles where id = p_user) then raise exception 'user_not_found'; end if;
  if exists (select 1 from public.user_roles where user_id = p_user and role_code = 'owner') then raise exception 'owner_cannot_be_bot'; end if;
  insert into public.ops_accounts (user_id, purpose, active, created_by) values (p_user, p_purpose, p_active, auth.uid())
    on conflict (user_id, purpose) do update set active = excluded.active, updated_at = now();
  return jsonb_build_object('user_id', p_user, 'purpose', p_purpose, 'active', p_active);
end $$;

-- ---------- rules ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('notify_on', 'notify', 'switch', 'true', null, null, null, null, 'নোটিফিকেশন (ঘণ্টা-আইকন)', 'Notification (bell)', 'Notifications (the bell)', 'বন্ধ করলে অ্যাপে নতুন নোটিফিকেশন তৈরি হবে না।', 'Off = no new notifications are made.', 300),
 ('notify_email_on', 'notify', 'switch', 'true', null, null, null, null, 'জিমেইলে জরুরি সতর্কতা ও দৈনিক সারাংশ', 'Gmail-এ জরুরি alert ও daily digest', 'Gmail urgent alerts and daily digest', 'বন্ধ করলে ইমেইল যাবে না (অ্যাপের ঘণ্টা চলবে)।', 'Off = no email is sent (the bell keeps working).', 301),
 ('notify_digest_times', 'notify', 'choice', '"08,21"', null, '["off","08","21","08,21"]', null, null, 'দৈনিক সারাংশ ইমেইলের সময় (ঢাকা, ঘণ্টা)', 'Daily digest email সময় (Dhaka, ঘণ্টা)', 'Daily digest email hours (Dhaka)', 'সকাল ৮টা, রাত ৯টা, দুটোই, অথবা বন্ধ।', '08 = 8am, 21 = 9pm, both, or off.', 302),
 ('notify_exceptions_on', 'notify', 'switch', 'true', null, null, null, null, 'লাল এক্সেপশন অনেকক্ষণ খোলা থাকলে জানান', 'Red exception অনেকক্ষণ open থাকলে জানান', 'Tell me when red exceptions stay open', null, null, 310),
 ('notify_exceptions_hours', 'notify', 'number', '24', 'ঘণ্টা', null, 1, 720, 'লাল এক্সেপশন কত ঘণ্টা খোলা থাকলে', 'Red exception কত ঘণ্টা open থাকলে', 'Red exception open for more than (hours)', null, null, 311),
 ('notify_approvals_on', 'notify', 'switch', 'true', null, null, null, null, 'অনুমোদন বাকি থাকলে জানান', 'Approval বাকি থাকলে জানান', 'Tell me when approvals wait too long', null, null, 312),
 ('notify_approvals_hours', 'notify', 'number', '24', 'ঘণ্টা', null, 1, 720, 'অনুমোদন কত ঘণ্টা বাকি থাকলে', 'Approval কত ঘণ্টা বাকি থাকলে', 'Approval waiting for more than (hours)', null, null, 313),
 ('notify_lowstock_on', 'notify', 'switch', 'true', null, null, null, null, 'কম স্টকের সতর্কতা', 'Low stock alert', 'Low stock alert', null, null, 314),
 ('notify_lowstock_min', 'notify', 'number', '1', 'আইটেম', null, 1, 10000, 'কমপক্ষে কয়টি আইটেম কম হলে জানাবেন', 'কমপক্ষে কয়টি item কম হলে', 'Alert when at least this many items are low', null, null, 315),
 ('notify_expiry_on', 'notify', 'switch', 'true', null, null, null, null, 'মেয়াদ শেষ হতে চলা ব্যাচের সতর্কতা', 'মেয়াদ শেষ হতে চলা batch-এর alert', 'Expiring batches alert', null, null, 316),
 ('notify_expiry_days', 'notify', 'number', '3', 'দিন', null, 0, 365, 'মেয়াদ শেষের কত দিন আগে', 'মেয়াদ শেষের কত দিন আগে', 'Days before expiry', null, null, 317),
 ('notify_supdue_on', 'notify', 'switch', 'true', null, null, null, null, 'সরবরাহকারীর মেয়াদোত্তীর্ণ পাওনা', 'Supplier-এর overdue পাওনা', 'Overdue supplier dues', null, null, 318),
 ('notify_supdue_min', 'notify', 'number', '1000', '৳', null, 0, 1000000000, 'মেয়াদোত্তীর্ণ পাওনা কত টাকার বেশি হলে', 'Overdue কত টাকার বেশি হলে', 'Overdue amount above (৳)', null, null, 319),
 ('notify_credit_on', 'notify', 'switch', 'true', null, null, null, null, 'গ্রাহকের বাকির সীমা পার হলে', 'Customer-এর credit limit পার হলে', 'Customer credit limit breached', null, null, 320),
 ('notify_dayclose_on', 'notify', 'switch', 'true', null, null, null, null, 'দিন-শেষের হিসাব (১৪-১) জমা না হলে', 'Day-close (14-1) জমা না হলে', 'Shop has not closed the day (14-1)', null, null, 321),
 ('day_close_deadline', 'notify', 'text', '"22:00"', null, null, null, null, 'দিন-শেষ জমার শেষ সময় (HH:MM, ঢাকা)', 'Day-close deadline (HH:MM, Dhaka)', 'Day-close deadline (HH:MM, Dhaka)', 'যেমন 22:00। এর পরেও জমা না হলে জানানো হয়।', 'Example 22:00. A shop that has not closed by then is reported.', 322),
 ('notify_wastage_on', 'notify', 'switch', 'true', null, null, null, null, 'অপচয় হঠাৎ বাড়লে জানান', 'Wastage হঠাৎ বাড়লে জানান', 'Wastage spike alert', null, null, 323),
 ('notify_wastage_factor', 'notify', 'number', '3', 'গুণ', null, 1, 100, 'আগের ৭ দিনের গড়ের কত গুণ হলে', 'আগের ৭ দিনের গড়ের কত গুণ', 'Times the previous 7-day average', null, null, 324),
 ('notify_wastage_min', 'notify', 'number', '1000', '৳', null, 0, 1000000000, 'অপচয় কত টাকার কম হলে জানাবেন না', 'Wastage কত টাকার কম হলে চুপ থাকবে', 'Ignore wastage below (৳)', null, null, 325),
 ('notify_cash_on', 'notify', 'switch', 'true', null, null, null, null, 'বড় ক্যাশ কম/বেশি হলে', 'বড় cash কম/বেশি হলে', 'Big cash short / over', null, null, 326),
 ('notify_cash_limit', 'notify', 'number', '500', '৳', null, 0, 1000000000, 'ক্যাশ কম/বেশি কত টাকার বেশি হলে', 'Cash কম/বেশি কত টাকার বেশি হলে', 'Cash short / over above (৳)', null, null, 327),
 ('notify_parallel_on', 'notify', 'switch', 'true', null, null, null, null, 'পাশাপাশি মাসের সিদ্ধান্ত বাকি থাকলে', 'Parallel month-এর decision বাকি থাকলে', 'Parallel-month decision waiting', null, null, 328),
 ('notify_backup_on', 'notify', 'switch', 'true', null, null, null, null, 'ব্যাকআপ পুরনো বা ব্যর্থ হলে জানান', 'Backup পুরনো বা failed হলে জানান', 'Backup stale or failed', null, null, 329),
 ('backup_max_age_hours', 'notify', 'number', '36', 'ঘণ্টা', null, 1, 720, 'শেষ সফল ব্যাকআপ কত ঘণ্টার পুরনো হলে সতর্কতা', 'শেষ OK backup কত ঘণ্টার পুরনো হলে alert', 'Alert when the last OK backup is older than (hours)', null, null, 330)
 on conflict (key) do nothing;

-- ---------- backup: whitelist, manifest, dump, log ----------
create or replace function public._backup_tables() returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(c.relname::text order by c.relname), '{}'::text[])
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relispartition
     and c.relname::text not like '%\_secret%' escape '\'
     and c.relname::text not like 'ops\_%' escape '\'
     and c.relname::text not in ('login_failures', 'login_attempts', 'login_throttle', 'backup_runs', 'notifications', 'notification_reads')
     and not exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
                      and a.attname::text ~* '(password|passwd|pin_hash|secret|token|salt|api_key|private_key)');
$$;

create or replace function public.backup_manifest() returns jsonb
language plpgsql security definer set search_path = public as $$
declare t text; n bigint; mx timestamptz; tabs jsonb := '[]'::jsonb; total bigint := 0; fp text; mxcol text;
begin
  if not public._is_ops('backup') then raise exception 'not allowed'; end if;
  foreach t in array public._backup_tables() loop
    execute format('select count(*) from public.%I', t) into n;
    mxcol := (select a.attname::text from pg_attribute a where a.attrelid = ('public.' || quote_ident(t))::regclass and a.attname::text in ('updated_at', 'created_at') and not a.attisdropped order by a.attname::text desc limit 1);
    mx := null;
    if mxcol is not null then execute format('select max(%I) from public.%I', mxcol, t) into mx; end if;
    tabs := tabs || jsonb_build_object('name', t, 'rows', n, 'max_updated_at', mx,
      'columns_md5', (select md5(string_agg(a.attname::text || ':' || format_type(a.atttypid, a.atttypmod), ',' order by a.attnum)) from pg_attribute a where a.attrelid = ('public.' || quote_ident(t))::regclass and a.attnum > 0 and not a.attisdropped));
    total := total + n;
  end loop;
  select md5(coalesce(string_agg(c.relname::text || '.' || a.attname::text || ':' || format_type(a.atttypid, a.atttypmod), ',' order by c.relname, a.attnum), '')) into fp
    from pg_class c join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
   where c.relnamespace = 'public'::regnamespace and c.relname::text = any (public._backup_tables());
  return jsonb_build_object('schema_version', 46, 'generated_at', now(), 'fingerprint', fp, 'table_count', jsonb_array_length(tabs), 'rows', total, 'tables', tabs);
end $$;

-- p_after_id is the cursor the previous call returned in "next" (a JSON array of the primary-key values, or "off:N" for a table without a primary key).
create or replace function public.backup_dump(p_table text, p_after_id text default null, p_limit int default 2000) returns jsonb
language plpgsql security definer set search_path = public as $$
declare lim int; pk text[]; pt text[]; cols text; keyexpr text; cond text := ''; vals text; cur jsonb; i int;
        rows_ jsonb; last_k text; cnt int; total bigint; nxt text; off_ bigint := 0;
begin
  if not public._is_ops('backup') then raise exception 'not allowed'; end if;
  if p_table is null or not (p_table = any (public._backup_tables())) then raise exception 'table_not_allowed'; end if;
  lim := least(greatest(coalesce(p_limit, 2000), 1), 5000);
  select array_agg(a.attname::text order by k.ord), array_agg(format_type(a.atttypid, a.atttypmod) order by k.ord) into pk, pt
    from pg_index ix cross join lateral unnest(ix.indkey::int2[]) with ordinality k(attnum, ord)
    join pg_attribute a on a.attrelid = ix.indrelid and a.attnum = k.attnum
   where ix.indrelid = ('public.' || quote_ident(p_table))::regclass and ix.indisprimary;
  execute format('select count(*) from public.%I', p_table) into total;
  if pk is null then
    if p_after_id is not null then
      if p_after_id !~ '^off:[0-9]{1,12}$' then raise exception 'bad_cursor'; end if;
      off_ := substr(p_after_id, 5)::bigint;
    end if;
    execute format('select coalesce(jsonb_agg(j order by rn), ''[]''::jsonb), count(*) from (select to_jsonb(t) j, row_number() over (order by to_jsonb(t)::text) rn from public.%I t order by to_jsonb(t)::text offset %s limit %s) x', p_table, off_, lim) into rows_, cnt;
    nxt := case when cnt = lim then 'off:' || (off_ + lim) end;
  else
    cols := (select string_agg(format('t.%I', c), ', ') from unnest(pk) c);
    keyexpr := 'jsonb_build_array(' || cols || ')';
    if p_after_id is not null then
      begin cur := p_after_id::jsonb; exception when others then raise exception 'bad_cursor'; end;
      if jsonb_typeof(cur) <> 'array' or jsonb_array_length(cur) <> array_length(pk, 1) then raise exception 'bad_cursor'; end if;
      vals := '';
      for i in 1 .. array_length(pk, 1) loop vals := vals || case when i > 1 then ', ' else '' end || format('%L::%s', cur ->> (i - 1), pt[i]); end loop;
      cond := format(' where (%s) > (%s)', cols, vals);
    end if;
    execute format('select coalesce(jsonb_agg(j order by rn), ''[]''::jsonb), count(*), (array_agg(k::text order by rn desc))[1] from (select to_jsonb(t) j, %s k, row_number() over (order by %s) rn from public.%I t%s order by %s limit %s) x',
                   keyexpr, cols, p_table, cond, cols, lim) into rows_, cnt, last_k;
    nxt := case when cnt = lim then last_k end;
  end if;
  return jsonb_build_object('table', p_table, 'rows', rows_, 'next', nxt, 'total', total);
end $$;

create or replace function public.backup_log(p_status text, p_detail jsonb default '{}'::jsonb, p_started timestamptz default null, p_tables int default null,
                                             p_rows bigint default null, p_bytes bigint default null, p_destination text default 'github') returns bigint
language plpgsql security definer set search_path = public as $$
declare rid bigint;
begin
  if not public._is_ops('backup') then raise exception 'not allowed'; end if;
  if p_status not in ('ok', 'failed', 'partial') then raise exception 'bad_status'; end if;
  if p_detail is not null and pg_column_size(p_detail) > 200000 then raise exception 'detail_too_big'; end if;
  if coalesce(p_tables, 0) < 0 or coalesce(p_rows, 0) < 0 or coalesce(p_bytes, 0) < 0 then raise exception 'bad_input'; end if;
  insert into public.backup_runs (started_at, status, tables, rows, bytes, detail, destination, logged_by)
    values (coalesce(least(p_started, now()), now()), p_status, p_tables, p_rows, p_bytes, coalesce(p_detail, '{}'::jsonb), left(coalesce(nullif(btrim(p_destination), ''), 'github'), 40), auth.uid())
    returning id into rid;
  return rid;
end $$;

-- last runs and whether the newest OK run is too old (owner or the backup / notify bot)
create or replace function public.backup_status() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare lastok record; lastrun record; maxh numeric := coalesce(public.rule_num('backup_max_age_hours'), 36); age numeric; configured boolean;
begin
  if not (public.is_owner() or public._is_ops('backup') or public._is_ops('notify')) then raise exception 'not allowed'; end if;
  select * into lastok from public.backup_runs where status = 'ok' order by finished_at desc, id desc limit 1;
  select * into lastrun from public.backup_runs order by finished_at desc, id desc limit 1;
  configured := exists (select 1 from public.ops_accounts where purpose = 'backup' and active);
  age := case when lastok.id is null then null else round(extract(epoch from (now() - lastok.finished_at)) / 3600, 1) end;
  return jsonb_build_object('configured', configured, 'max_age_hours', maxh, 'age_hours', age,
    'last_ok', case when lastok.id is null then null else jsonb_build_object('at', lastok.finished_at, 'tables', lastok.tables, 'rows', lastok.rows, 'bytes', lastok.bytes, 'destination', lastok.destination) end,
    'last_run', case when lastrun.id is null then null else jsonb_build_object('at', lastrun.finished_at, 'status', lastrun.status) end,
    'failed_last', coalesce(lastrun.status = 'failed', false),
    'stale', configured and (age is null or age > maxh));
end $$;

-- ---------- notifications ----------
create or replace function public._notif_add(p_kind text, p_level text, p_tbn text, p_ten text, p_bbn text, p_ben text, p_route text, p_key text, p_aud text, p_loc int) returns boolean
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into public.notifications (audience, kind, level, title_bn, title_en, body_bn, body_en, route, location_id, key)
    values (p_aud, p_kind, p_level, p_tbn, p_ten, p_bbn, p_ben, p_route, p_loc, left(coalesce(p_key, ''), 80))
    on conflict (kind, key, day) do nothing;
  get diagnostics n = row_count;
  return n > 0;
end $$;

-- Generates today's notifications from existing data. Idempotent per day: (kind, key, day) is unique, so a second run adds nothing.
-- Every kind has a switch and thresholds (rules notify_*). Optional tables are guarded with to_regclass.
create or replace function public.notify_scan() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  today date := public._today(); nowd timestamp := (now() at time zone 'Asia/Dhaka');
  made jsonb := '{}'::jsonb; cnt int; amt numeric; hrs numeric; r record; dl text; dl_t time; st jsonb;
begin
  if not (public._is_ops('notify') or public.is_owner()) then raise exception 'not allowed'; end if;
  if not public.rule_on('notify_on') then return jsonb_build_object('created', 0, 'kinds', '{}'::jsonb, 'off', true); end if;

  -- 1. red exceptions open too long
  if public.rule_on('notify_exceptions_on') then
    hrs := coalesce(public.rule_num('notify_exceptions_hours'), 24);
    select count(*), round(max(extract(epoch from (now() - created_at)) / 3600)) into cnt, amt from public.exceptions where level = 'red' and status = 'open' and created_at < now() - make_interval(secs => hrs * 3600);
    if cnt > 0 and public._notif_add('red_exceptions', 'bad', cnt || 'টি লাল এক্সেপশন খোলা পড়ে আছে', cnt || ' red exception(s) still open',
         'সবচেয়ে পুরনোটি ' || amt || ' ঘণ্টা ধরে খোলা। দেখে নিষ্পত্তি করুন।', 'The oldest has been open ' || amt || ' hours. Please look and resolve.', 'exceptions', 'all', 'owner', null) then
      made := made || jsonb_build_object('red_exceptions', 1); end if;
  end if;

  -- 2. approvals waiting too long (same sources as phase 28 needs_you_oldest, for the owner's whole view)
  if public.rule_on('notify_approvals_on') then
    hrs := coalesce(public.rule_num('notify_approvals_hours'), 24);
    select count(*), round(max(extract(epoch from (now() - s)) / 3600)) into cnt, amt from (
      select coalesce(e.submitted_at, e.created_at) s from public.entries e where e.status = 'submitted'
      union all select r.requested_at from public.release_requests r where r.status = 'pending'
      union all select q.created_at from public.emergency_requests q where q.status = 'pending'
      union all select c.requested_at from public.item_changes c where c.status = 'pending'
      union all select p.created_at from public.profiles p where p.status = 'pending'
      union all select w.requested_at from public.wastage_requests w where w.status = 'pending') u
     where u.s < now() - make_interval(secs => hrs * 3600);
    if cnt > 0 and public._notif_add('approvals_waiting', 'warn', cnt || 'টি অনুমোদন অপেক্ষায়', cnt || ' approval(s) waiting',
         'সবচেয়ে পুরনোটি ' || amt || ' ঘণ্টা ধরে অপেক্ষায়।', 'The oldest has waited ' || amt || ' hours.', 'pending', 'all', 'owner', null) then
      made := made || jsonb_build_object('approvals_waiting', 1); end if;
  end if;

  -- 3. low stock (per place)
  if public.rule_on('notify_lowstock_on') then
    for r in select b.location_id, count(*) c from public.stock_balance b join public.items i on i.id = b.item_id join public.locations l on l.id = b.location_id
              where i.is_active and coalesce(i.min_stock, 0) > 0 and b.qty <= i.min_stock and l.is_active and l.status = 'live'
              group by b.location_id having count(*) >= coalesce(public.rule_num('notify_lowstock_min'), 1) loop
      if public._notif_add('low_stock', 'warn', r.c || 'টি আইটেমের স্টক কম', r.c || ' item(s) low in stock', 'ন্যূনতম স্টকের নিচে নেমেছে।', 'At or below the minimum stock.', 'stock', r.location_id::text, 'manager', r.location_id) then
        made := made || jsonb_build_object('low_stock', coalesce((made ->> 'low_stock')::int, 0) + 1); end if;
    end loop;
  end if;

  -- 4. batches about to expire (per place)
  if public.rule_on('notify_expiry_on') then
    for r in select b.location_id, count(*) c, min(b.expires_at) first_at from public.stock_batches b join public.items i on i.id = b.item_id
              where b.qty_remaining > 0 and b.expires_at is not null and b.expires_at < now() + make_interval(days => coalesce(public.rule_num('notify_expiry_days'), 3)::int)
              group by b.location_id loop
      if public._notif_add('expiring_batches', 'warn', r.c || 'টি ব্যাচের মেয়াদ শেষ হতে চলেছে', r.c || ' batch(es) expiring soon',
           'সবচেয়ে আগের মেয়াদ: ' || to_char(r.first_at at time zone 'Asia/Dhaka', 'YYYY-MM-DD'), 'Earliest expiry: ' || to_char(r.first_at at time zone 'Asia/Dhaka', 'YYYY-MM-DD'), 'stock', r.location_id::text, 'manager', r.location_id) then
        made := made || jsonb_build_object('expiring_batches', coalesce((made ->> 'expiring_batches')::int, 0) + 1); end if;
    end loop;
  end if;

  -- 5. supplier dues overdue
  if public.rule_on('notify_supdue_on') then
    select coalesce(sum(o.open_amt), 0), count(distinct o.supplier_id) into amt, cnt
      from public._sup_open(null) o join public.suppliers s on s.id = o.supplier_id
     where o.open_amt > 0 and s.credit_days is not null and o.bill_date is not null and o.bill_date + s.credit_days < today;
    if cnt > 0 and amt > coalesce(public.rule_num('notify_supdue_min'), 0) and public._notif_add('supplier_overdue', 'warn', cnt || ' সরবরাহকারীর পাওনা মেয়াদ পেরিয়েছে', cnt || ' supplier(s) overdue',
         'মোট ৳' || round(amt, 2), 'Total ৳' || round(amt, 2), 'payables', 'all', 'owner', null) then
      made := made || jsonb_build_object('supplier_overdue', 1); end if;
  end if;

  -- 6. customers over their credit limit
  if public.rule_on('notify_credit_on') then
    select count(*) into cnt from public.customers c where c.active and coalesce(c.credit_limit, 0) > 0 and public._cust_bal(c.id) > c.credit_limit;
    if cnt > 0 and public._notif_add('credit_breach', 'warn', cnt || ' জন গ্রাহকের বাকি সীমা ছাড়িয়েছে', cnt || ' customer(s) over their credit limit', 'বাকির তালিকা দেখুন।', 'See the dues list.', 'dues', 'all', 'owner', null) then
      made := made || jsonb_build_object('credit_breach', 1); end if;
  end if;

  -- 7. shops with no day-close (14-1) after the deadline
  if public.rule_on('notify_dayclose_on') then
    dl := coalesce(public.rule_txt('day_close_deadline'), '22:00');
    if dl !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then dl := '22:00'; end if;
    dl_t := dl::time;
    if nowd::time >= dl_t then
      for r in select l.id, l.name_bn, l.name_en from public.locations l where l.is_active and l.status = 'live' and l.kind = 'showroom' and public.rollout_mode('14-1', l.id) <> 'paper'
                  and not exists (select 1 from public.entries e where e.form_code = '14-1' and e.location_id = l.id and e.entry_date = today and e.status in ('submitted', 'approved')) loop
        if public._notif_add('day_close_missing', 'warn', r.name_bn || ': আজকের দিন-শেষ জমা হয়নি', r.name_en || ': today''s day-close is not submitted',
             'শেষ সময় ' || dl || ' পেরিয়ে গেছে।', 'The deadline ' || dl || ' has passed.', 'home', r.id::text, 'manager', r.id) then
          made := made || jsonb_build_object('day_close_missing', coalesce((made ->> 'day_close_missing')::int, 0) + 1); end if;
      end loop;
    end if;
  end if;

  -- 8. wastage spike (money value today vs the average of the previous 7 days)
  if public.rule_on('notify_wastage_on') then
    with w as (select (x.made_at at time zone 'Asia/Dhaka')::date d, round(sum(x.qty * coalesce(b.avg_cost, 0)), 2) v
                 from public.stock_wastage x left join public.stock_balance b on b.item_id = x.item_id and b.location_id = x.location_id
                where (x.made_at at time zone 'Asia/Dhaka')::date between today - 7 and today group by 1)
    select coalesce((select v from w where d = today), 0), coalesce((select sum(v) from w where d < today), 0) / 7 into amt, hrs;
    if amt > 0 and amt >= coalesce(public.rule_num('notify_wastage_min'), 0) and amt >= coalesce(public.rule_num('notify_wastage_factor'), 3) * hrs
       and public._notif_add('wastage_spike', 'warn', 'আজ অপচয় হঠাৎ বেশি: ৳' || amt, 'Wastage spike today: ৳' || amt,
         'আগের ৭ দিনের গড় ৳' || round(hrs, 2), 'Previous 7-day average ৳' || round(hrs, 2), 'stock', 'all', 'owner', null) then
      made := made || jsonb_build_object('wastage_spike', 1); end if;
  end if;

  -- 9. big cash short / over (each exception once, ever)
  if public.rule_on('notify_cash_on') then
    for r in select x.id, x.location_id, x.amount, l.name_bn, l.name_en from public.exceptions x left join public.locations l on l.id = x.location_id
              where x.flag_code = 'cash_short_over' and x.status = 'open' and abs(coalesce(x.amount, 0)) > coalesce(public.rule_num('notify_cash_limit'), 500) and x.created_at > now() - interval '3 days'
                and not exists (select 1 from public.notifications n where n.kind = 'cash_gap' and n.key = x.id::text) loop
      if public._notif_add('cash_gap', 'bad', coalesce(r.name_bn, '') || ': ক্যাশ ' || case when r.amount < 0 then 'কম' else 'বেশি' end || ' ৳' || abs(r.amount),
           coalesce(r.name_en, '') || ': cash ' || case when r.amount < 0 then 'short' else 'over' end || ' ৳' || abs(r.amount), 'এক্সেপশন দেখে নিষ্পত্তি করুন।', 'Please look at the exception and resolve it.', 'exceptions', r.id::text, 'owner', r.location_id) then
        made := made || jsonb_build_object('cash_gap', coalesce((made ->> 'cash_gap')::int, 0) + 1); end if;
    end loop;
  end if;

  -- 10. parallel-month decision waiting (same rule as phase 28 parallel_waiting, for the owner)
  if public.rule_on('notify_parallel_on') and public.rule_on('parallel_compare_on') then
    for r in select f.form_code, f.location_id from public.form_rollout f
              where f.mode = 'parallel'
                and exists (select 1 from public.comparison_days d where d.form_code = f.form_code and d.location_id = f.location_id
                              and d.day >= (date_trunc('month', today) - interval '1 month')::date and d.day < date_trunc('month', today)::date)
                and not exists (select 1 from public.parallel_months p where p.form_code = f.form_code and p.location_id = f.location_id and p.month = (date_trunc('month', today) - interval '1 month')::date) loop
      if public._notif_add('parallel_decision', 'info', r.form_code || ': গত মাসের পাশাপাশি সিদ্ধান্ত বাকি', r.form_code || ': last month''s parallel decision is waiting', 'পাস/ফেল ঠিক করুন।', 'Decide pass or fail.', 'parallel', r.form_code || ':' || r.location_id, 'owner', r.location_id) then
        made := made || jsonb_build_object('parallel_decision', coalesce((made ->> 'parallel_decision')::int, 0) + 1); end if;
    end loop;
  end if;

  -- 11. backup stale or failed
  if public.rule_on('notify_backup_on') then
    st := public.backup_status();
    if (st ->> 'stale')::boolean and public._notif_add('backup_stale', 'bad', 'ব্যাকআপ পুরনো হয়ে গেছে', 'Backup is out of date',
         coalesce('শেষ সফল ব্যাকআপ ' || (st ->> 'age_hours') || ' ঘণ্টা আগে।', 'এখনো কোনো সফল ব্যাকআপ নেই।'), coalesce('Last good backup ' || (st ->> 'age_hours') || ' hours ago.', 'There is no good backup yet.'), 'notifications', 'stale', 'owner', null) then
      made := made || jsonb_build_object('backup_stale', 1); end if;
    if (st ->> 'failed_last')::boolean and public._notif_add('backup_failed', 'bad', 'শেষ ব্যাকআপ ব্যর্থ হয়েছে', 'The last backup failed', 'GitHub Actions-এর লগ দেখুন।', 'Check the GitHub Actions log.', 'notifications', 'failed', 'owner', null) then
      made := made || jsonb_build_object('backup_failed', 1); end if;
  end if;

  select coalesce(sum(v::int), 0) into cnt from jsonb_each_text(made) e(k, v);
  return jsonb_build_object('created', cnt, 'kinds', made);
end $$;

-- the bell
create or replace function public.notifications_for_me(p_limit int default 50, p_unread_only boolean default false, p_level text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out_ jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(x order by x.id desc), '[]'::jsonb) into out_ from (
    select n.id, n.kind, n.level, n.title_bn, n.title_en, n.body_bn, n.body_en, n.route, n.location_id, n.created_at,
           (r.user_id is not null) as is_read
      from public.notifications n left join public.notification_reads r on r.notification_id = n.id and r.user_id = auth.uid()
     where public._notif_ok(n.user_id, n.audience, n.location_id)
       and (not coalesce(p_unread_only, false) or r.user_id is null)
       and (p_level is null or n.level = p_level)
     order by n.id desc limit least(greatest(coalesce(p_limit, 50), 1), 200)) x;
  return out_;
end $$;
create or replace function public.notifications_unread_count() returns int
language plpgsql stable security definer set search_path = public as $$
declare c int;
begin
  if not public.is_active() then return 0; end if;
  select count(*) into c from public.notifications n
   where n.created_at > now() - interval '90 days' and public._notif_ok(n.user_id, n.audience, n.location_id)
     and not exists (select 1 from public.notification_reads r where r.notification_id = n.id and r.user_id = auth.uid());
  return c;
end $$;
create or replace function public.notification_read(p_id bigint) returns boolean
language plpgsql security definer set search_path = public as $$
declare n public.notifications;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into n from public.notifications where id = p_id;
  if not found or not public._notif_ok(n.user_id, n.audience, n.location_id) then raise exception 'not allowed'; end if;
  insert into public.notification_reads (notification_id, user_id) values (p_id, auth.uid()) on conflict do nothing;
  if n.user_id is not null and n.read_at is null then update public.notifications set read_at = now(), read_by = auth.uid() where id = p_id; end if;
  return true;
end $$;
create or replace function public.notification_read_all() returns int
language plpgsql security definer set search_path = public as $$
declare c int;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  insert into public.notification_reads (notification_id, user_id)
    select n.id, auth.uid() from public.notifications n
     where n.created_at > now() - interval '90 days' and public._notif_ok(n.user_id, n.audience, n.location_id)
    on conflict do nothing;
  get diagnostics c = row_count;
  return c;
end $$;

-- ---------- e-mail side ----------
create or replace function public.notify_config() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public._is_ops('notify') or public.is_owner()) then raise exception 'not allowed'; end if;
  return jsonb_build_object('email_on', public.rule_on('notify_email_on'), 'digest_times', coalesce(public.rule_txt('notify_digest_times'), '08,21'), 'now_hour', to_char(now() at time zone 'Asia/Dhaka', 'HH24'));
end $$;

create or replace function public.urgent_alerts(p_since timestamptz default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public._is_ops('notify') or public.is_owner()) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'kind', n.kind, 'title_bn', n.title_bn, 'title_en', n.title_en, 'body_bn', n.body_bn, 'body_en', n.body_en, 'route', n.route, 'created_at', n.created_at) order by n.id)
                     from public.notifications n
                    where n.level = 'bad' and n.emailed_at is null and n.user_id is null and n.audience in ('owner', 'all')
                      and n.created_at >= coalesce(p_since, now() - interval '2 days')), '[]'::jsonb);
end $$;

create or replace function public.notifications_mark_emailed(p_ids bigint[]) returns int
language plpgsql security definer set search_path = public as $$
declare c int;
begin
  if not (public._is_ops('notify') or public.is_owner()) then raise exception 'not allowed'; end if;
  if p_ids is null or coalesce(array_length(p_ids, 1), 0) > 500 then raise exception 'bad_input'; end if;
  update public.notifications set emailed_at = now() where id = any (p_ids) and emailed_at is null;
  get diagnostics c = row_count;
  return c;
end $$;

-- money of one day: sales (done) and returns, net when the report rule says so (same logic as sales_summary)
create or replace function public._day_sales(p_d date) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('bills', s.n, 'total', s.t, 'discount', s.d, 'returns', r.a,
           'net', case when public.rule_on('reports_net_of_returns') then s.t - r.a else s.t end)
    from (select count(*) n, coalesce(sum(total), 0) t, coalesce(sum(discount), 0) d from public.sales where status = 'done' and sale_date = p_d) s,
         (select coalesce(sum(amount), 0) a from public.sale_returns where status = 'done' and (created_at at time zone 'Asia/Dhaka')::date = p_d) r;
$$;

-- numbers for the e-mail (labels are added by the sender). Owner or notify bot only.
create or replace function public.daily_digest(p_date date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_date, public._today()); td jsonb; yd jsonb; lw jsonb; byloc jsonb; top5 jsonb; cash jsonb; coll numeric; custdue numeric; custn int;
        sup jsonb; waste jsonb; voids jsonb; ex jsonb; appr int; lowc int; expc int; closes jsonb; st jsonb; plan_ numeric;
begin
  if not (public._is_ops('notify') or public.is_owner()) then raise exception 'not allowed'; end if;
  if d > public._today() or d < public._today() - 400 then raise exception 'bad_date'; end if;
  td := public._day_sales(d); yd := public._day_sales(d - 1); lw := public._day_sales(d - 7);
  select coalesce(jsonb_agg(jsonb_build_object('location_id', l.id, 'name_bn', l.name_bn, 'name_en', l.name_en, 'net', v.net) order by l.sort), '[]'::jsonb) into byloc
    from public.locations l cross join lateral (
      select coalesce((select sum(total) from public.sales where status = 'done' and sale_date = d and location_id = l.id), 0)
           - case when public.rule_on('reports_net_of_returns') then coalesce((select sum(amount) from public.sale_returns where status = 'done' and location_id = l.id and (created_at at time zone 'Asia/Dhaka')::date = d), 0) else 0 end as net) v
   where l.is_active and l.status = 'live' and l.kind = 'showroom';
  select coalesce(jsonb_agg(jsonb_build_object('name', z.nm, 'qty', z.q, 'amount', z.a) order by z.a desc), '[]'::jsonb) into top5 from (
    select coalesce(x.ln ->> 'name', '?') nm, round(sum((x.ln ->> 'qty')::numeric), 3) q, round(sum((x.ln ->> 'amount')::numeric), 2) a
      from (select jsonb_array_elements(s.lines) ln from public.sales s where s.status = 'done' and s.sale_date = d) x
     where (x.ln ->> 'amount') ~ '^-?[0-9.]+$' and (x.ln ->> 'qty') ~ '^-?[0-9.]+$' group by coalesce(x.ln ->> 'name', '?') order by sum((x.ln ->> 'amount')::numeric) desc limit 5) z;
  select jsonb_build_object('count', count(*), 'short', coalesce(sum(-amount) filter (where amount < 0), 0), 'over', coalesce(sum(amount) filter (where amount > 0), 0)) into cash
    from public.exceptions where flag_code = 'cash_short_over' and entry_date = d;
  select coalesce(sum(amount), 0) into coll from public.sale_payments where kind = 'collection' and not voided and (paid_at at time zone 'Asia/Dhaka')::date = d;
  select coalesce(sum(b), 0), count(*) into custdue, custn from (select public._cust_bal(c.id) b from public.customers c) z where b > 0;
  select jsonb_build_object('payable', coalesce(sum(o.open_amt), 0), 'suppliers', count(distinct o.supplier_id),
           'overdue', coalesce(sum(o.open_amt) filter (where s.credit_days is not null and o.bill_date is not null and o.bill_date + s.credit_days < public._today()), 0)) into sup
    from public._sup_open(null) o join public.suppliers s on s.id = o.supplier_id where o.open_amt > 0;
  select jsonb_build_object('count', count(*), 'value', coalesce(round(sum(x.qty * coalesce(b.avg_cost, 0)), 2), 0)) into waste
    from public.stock_wastage x left join public.stock_balance b on b.item_id = x.item_id and b.location_id = x.location_id where (x.made_at at time zone 'Asia/Dhaka')::date = d;
  select jsonb_build_object('void_count', count(*) filter (where status = 'void'), 'void_total', coalesce(sum(total) filter (where status = 'void'), 0),
           'discount_count', count(*) filter (where status = 'done' and discount > 0), 'discount_total', coalesce(sum(discount) filter (where status = 'done'), 0)) into voids
    from public.sales where sale_date = d;
  select jsonb_build_object('red', count(*) filter (where level = 'red'), 'yellow', count(*) filter (where level = 'yellow')) into ex from public.exceptions where status = 'open';
  select count(*) into appr from (
      select 1 from public.entries where status = 'submitted' union all select 1 from public.release_requests where status = 'pending'
      union all select 1 from public.emergency_requests where status = 'pending' union all select 1 from public.item_changes where status = 'pending'
      union all select 1 from public.profiles where status = 'pending' union all select 1 from public.wastage_requests where status = 'pending') u;
  select count(*) into lowc from public.stock_balance b join public.items i on i.id = b.item_id where i.is_active and coalesce(i.min_stock, 0) > 0 and b.qty <= i.min_stock;
  select count(*) into expc from public.stock_batches where qty_remaining > 0 and expires_at is not null and expires_at < now() + make_interval(days => coalesce(public.rule_num('notify_expiry_days'), 3)::int);
  select coalesce(jsonb_agg(jsonb_build_object('location_id', l.id, 'name_bn', l.name_bn, 'name_en', l.name_en,
           'closed', exists (select 1 from public.entries e where e.form_code = '14-1' and e.location_id = l.id and e.entry_date = d and e.status in ('submitted', 'approved')),
           'mode', public.rollout_mode('14-1', l.id)) order by l.sort), '[]'::jsonb) into closes
    from public.locations l where l.is_active and l.status = 'live' and l.kind = 'showroom';
  st := public.backup_status();
  return jsonb_build_object('date', d, 'generated_at', now(),
    'sales', jsonb_build_object('today', td, 'yesterday', yd, 'last_week', lw,
       'vs_yesterday_pct', case when (yd ->> 'net')::numeric > 0 then round(((td ->> 'net')::numeric - (yd ->> 'net')::numeric) * 100 / (yd ->> 'net')::numeric, 1) end,
       'vs_last_week_pct', case when (lw ->> 'net')::numeric > 0 then round(((td ->> 'net')::numeric - (lw ->> 'net')::numeric) * 100 / (lw ->> 'net')::numeric, 1) end,
       'by_location', byloc),
    'top_items', top5, 'cash', cash, 'collections', coll,
    'dues', jsonb_build_object('customers_total', round(custdue, 2), 'customers', custn, 'suppliers', sup),
    'wastage', waste, 'voids_discounts', voids, 'exceptions_open', ex, 'approvals_pending', appr,
    'stock_alerts', jsonb_build_object('low_items', lowc, 'expiring_batches', expc),
    'day_close', closes, 'backup', st);
end $$;

-- ---------- grants ----------
do $$ declare f text; r regprocedure; begin
  foreach f in array array['_is_ops', '_today', '_notif_ok', '_notif_add', '_backup_tables', '_day_sales', 'ops_account_set', 'backup_manifest', 'backup_dump', 'backup_log', 'backup_status',
      'notify_scan', 'notifications_for_me', 'notifications_unread_count', 'notification_read', 'notification_read_all', 'notify_config', 'urgent_alerts', 'notifications_mark_emailed', 'daily_digest'] loop
    for r in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = f loop
      execute format('revoke all on function %s from public, anon, authenticated', r);
      if f in ('_notif_ok', 'ops_account_set', 'backup_manifest', 'backup_dump', 'backup_log', 'backup_status', 'notify_scan', 'notifications_for_me', 'notifications_unread_count', 'notification_read', 'notification_read_all',
               'notify_config', 'urgent_alerts', 'notifications_mark_emailed', 'daily_digest') then
        execute format('grant execute on function %s to authenticated', r);
      end if;
    end loop;
  end loop;
end $$;
notify pgrst, 'reload schema';
