-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase91.sql there and is already pasted on the live database under that name.
-- Renumbered to phase517.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- ============================================================
-- Phase 517 (bos91) - Step Vis: per-user (and per-role default) VISIBILITY of every option / menu item / page.
-- Run AFTER phase512 (needs phase8 grants, audit_log, roles). Additive + idempotent (paste twice = no error). No old phase file is changed.
--
--   Vis1 user_option_view  (user_id, option_key, mode show|hide|locked, set_by, set_at)  one row = an owner choice for ONE person and ONE option.
--        role_option_view  (role_code, option_key, mode, set_by, set_at)                  the DEFAULT for everybody holding that role (a user row wins).
--        option_key is the same key nav.js already uses for favourites: 'r:<ia route>' (e.g. r:items) or 'f:<form code>' (e.g. f:10-1).
--   Vis2 Modes:  show   = as today (visible and usable when permitted)               <- default when no row exists: nobody's view changes
--                hide   = not shown at all (drawer, Home, search, bottom bar), even if permitted
--                locked = shown but disabled; tapping it opens an "ask the owner" sheet instead of the page
--   Vis3 RPCs (owner only to set): set_option_view, set_option_view_bulk, set_role_option_view, set_role_option_view_bulk.
--        my_option_views()  - the caller's own effective views (user row, else role default). option_views_for_user(user) - owner, or a person for themself.
--        client_id makes a retried call a no-op (same actor) and a clash with someone else's id an error.
--   Vis4 Audit: every real change writes one audit_log line (old -> new, by whom). set_by / set_at are kept on the row.
--
-- SECURITY NOTE (by design): this is UI tidiness ONLY. No row here grants or removes any permission. has_grant / can_do / RLS never read these tables.
-- A hidden option that the person is permitted to use still works by its direct route; a locked option the person is NOT permitted to use is still refused by the server.
-- r:home and r:optviews can never be hidden or locked (the owner cannot lock himself out of this screen).
-- ============================================================

do $$
begin
  if to_regclass('public.user_grants') is null or to_regclass('public.rule_grants') is null or to_regclass('public.audit_log') is null
     or to_regclass('public.roles') is null or to_regclass('public.role_form_perms') is null or to_regclass('public.telegram_secrets') is null then
    raise exception 'phase517 needs phase8 .. phase512 applied first (user_grants, rule_grants, audit_log, roles, telegram_secrets missing)';
  end if;
end $$;

-- =====================================================================
-- Vis1 tables
-- =====================================================================
create table if not exists public.user_option_view (
  user_id uuid not null references public.profiles(id) on delete cascade,
  option_key text not null check (option_key ~ '^[rf]:[A-Za-z0-9_./-]{1,80}$'),
  mode text not null check (mode in ('show', 'hide', 'locked')),
  set_by uuid, set_at timestamptz not null default now(),
  primary key (user_id, option_key)
);
create table if not exists public.role_option_view (
  role_code text not null references public.roles(code) on delete cascade,
  option_key text not null check (option_key ~ '^[rf]:[A-Za-z0-9_./-]{1,80}$'),
  mode text not null check (mode in ('show', 'hide', 'locked')),
  set_by uuid, set_at timestamptz not null default now(),
  primary key (role_code, option_key)
);
-- remembers client_ids so a retried call does nothing twice (closed table, written only by the functions below)
create table if not exists public.option_view_ops (
  client_id uuid primary key, actor uuid not null, kind text not null, result jsonb, at timestamptz not null default now()
);

-- =====================================================================
-- helpers (not callable from the browser)
-- =====================================================================
create or replace function public._ov_mode(p_mode text) returns text language plpgsql immutable set search_path = public as $$
begin
  if p_mode is null or lower(btrim(p_mode)) = 'default' then return 'default'; end if;
  if lower(btrim(p_mode)) not in ('show', 'hide', 'locked') then raise exception 'bad_mode'; end if;
  return lower(btrim(p_mode));
end $$;

create or replace function public._ov_key(p_key text, p_mode text) returns void language plpgsql immutable set search_path = public as $$
begin
  if p_key is null or p_key !~ '^[rf]:[A-Za-z0-9_./-]{1,80}$' then raise exception 'bad_option_key'; end if;
  if p_key in ('r:home', 'r:optviews') and p_mode in ('hide', 'locked') then raise exception 'protected_option'; end if;
end $$;

-- one user choice. returns {changed, old, new}. 'default' removes the row.
create or replace function public._ov_put_user(p_user uuid, p_key text, p_mode text) returns jsonb language plpgsql security definer set search_path = public as $$
declare m text := public._ov_mode(p_mode); o text;
begin
  perform public._ov_key(p_key, m);
  if not exists (select 1 from public.profiles where id = p_user) then raise exception 'unknown user'; end if;
  select mode into o from public.user_option_view where user_id = p_user and option_key = p_key;
  if m = 'default' then
    delete from public.user_option_view where user_id = p_user and option_key = p_key;
  else
    insert into public.user_option_view (user_id, option_key, mode, set_by, set_at) values (p_user, p_key, m, auth.uid(), now())
      on conflict (user_id, option_key) do update set mode = excluded.mode, set_by = excluded.set_by, set_at = now() where public.user_option_view.mode is distinct from excluded.mode;
  end if;
  return jsonb_build_object('key', p_key, 'old', o, 'new', case when m = 'default' then null else m end, 'changed', o is distinct from case when m = 'default' then null else m end);
end $$;

create or replace function public._ov_put_role(p_role text, p_key text, p_mode text) returns jsonb language plpgsql security definer set search_path = public as $$
declare m text := public._ov_mode(p_mode); o text;
begin
  perform public._ov_key(p_key, m);
  if not exists (select 1 from public.roles where code = p_role) then raise exception 'unknown role'; end if;
  select mode into o from public.role_option_view where role_code = p_role and option_key = p_key;
  if m = 'default' then
    delete from public.role_option_view where role_code = p_role and option_key = p_key;
  else
    insert into public.role_option_view (role_code, option_key, mode, set_by, set_at) values (p_role, p_key, m, auth.uid(), now())
      on conflict (role_code, option_key) do update set mode = excluded.mode, set_by = excluded.set_by, set_at = now() where public.role_option_view.mode is distinct from excluded.mode;
  end if;
  return jsonb_build_object('key', p_key, 'old', o, 'new', case when m = 'default' then null else m end, 'changed', o is distinct from case when m = 'default' then null else m end);
end $$;

-- client_id: a stored result for the same actor and kind = replay it; someone else's id = error
create or replace function public._ov_replay(p_client uuid, p_kind text) returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.option_view_ops;
begin
  if p_client is null then return null; end if;
  select * into r from public.option_view_ops where client_id = p_client;
  if not found then return null; end if;
  if r.actor is distinct from auth.uid() or r.kind <> p_kind then raise exception 'client_id_taken'; end if;
  return coalesce(r.result, '{}'::jsonb) || jsonb_build_object('dup', true);
end $$;

create or replace function public._ov_remember(p_client uuid, p_kind text, p_result jsonb) returns void language plpgsql security definer set search_path = public as $$
begin
  if p_client is null then return; end if;
  insert into public.option_view_ops (client_id, actor, kind, result) values (p_client, auth.uid(), p_kind, p_result) on conflict (client_id) do nothing;
end $$;

create or replace function public._ov_audit(p_table text, p_record text, p_changes jsonb) returns void language plpgsql security definer set search_path = public as $$
begin
  if p_changes is null or jsonb_array_length(p_changes) = 0 then return; end if;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'update', p_table, p_record, jsonb_build_object('changes', p_changes, 'event', 'option_view'));
end $$;

-- the effective mode of every option that has a row for this user: the user row, else the role defaults.
-- Several roles with different defaults: the LEAST restrictive wins (show > locked > hide), so a second role never takes an option away by accident.
create or replace function public._ov_effective(p_user uuid) returns table (option_key text, mode text, src text) language sql stable security definer set search_path = public as $$
  select u.option_key, u.mode, 'user'::text from public.user_option_view u where u.user_id = p_user
  union all
  select d.option_key, (array_agg(d.mode order by case d.mode when 'show' then 1 when 'locked' then 2 else 3 end))[1], 'role'::text
    from public.role_option_view d
    join public.user_roles ur on ur.role_code = d.role_code and ur.user_id = p_user
    join public.roles r on r.code = d.role_code and r.active
   where not exists (select 1 from public.user_option_view u2 where u2.user_id = p_user and u2.option_key = d.option_key)
   group by d.option_key;
$$;

-- =====================================================================
-- Vis3 setters (owner only)
-- =====================================================================
create or replace function public.set_option_view(p_user uuid, p_key text, p_mode text, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare rp jsonb; res jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  rp := public._ov_replay(p_client, 'user'); if rp is not null then return rp; end if;
  res := public._ov_put_user(p_user, p_key, p_mode);
  if (res->>'changed')::boolean then perform public._ov_audit('user_option_view', p_user::text, jsonb_build_array(res)); end if;
  res := res || jsonb_build_object('user_id', p_user);
  perform public._ov_remember(p_client, 'user', res);
  return res;
end $$;

-- p_items = [{"key":"r:items","mode":"hide"}, ...] (mode 'default' = remove the choice). All or nothing. At most 500.
create or replace function public.set_option_view_bulk(p_user uuid, p_items jsonb, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare rp jsonb; it jsonb; r jsonb; ch jsonb := '[]'::jsonb; n int := 0; res jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  rp := public._ov_replay(p_client, 'user_bulk'); if rp is not null then return rp; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then raise exception 'bad_items'; end if;
  if jsonb_array_length(p_items) > 500 then raise exception 'too_many_items'; end if;
  for it in select * from jsonb_array_elements(p_items) loop
    r := public._ov_put_user(p_user, it->>'key', it->>'mode'); n := n + 1;
    if (r->>'changed')::boolean then ch := ch || jsonb_build_array(r); end if;
  end loop;
  perform public._ov_audit('user_option_view', p_user::text, ch);
  res := jsonb_build_object('user_id', p_user, 'count', n, 'changed', jsonb_array_length(ch));
  perform public._ov_remember(p_client, 'user_bulk', res);
  return res;
end $$;

create or replace function public.set_role_option_view(p_role text, p_key text, p_mode text, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare rp jsonb; res jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  rp := public._ov_replay(p_client, 'role'); if rp is not null then return rp; end if;
  res := public._ov_put_role(p_role, p_key, p_mode);
  if (res->>'changed')::boolean then perform public._ov_audit('role_option_view', p_role, jsonb_build_array(res)); end if;
  res := res || jsonb_build_object('role_code', p_role);
  perform public._ov_remember(p_client, 'role', res);
  return res;
end $$;

create or replace function public.set_role_option_view_bulk(p_role text, p_items jsonb, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare rp jsonb; it jsonb; r jsonb; ch jsonb := '[]'::jsonb; n int := 0; res jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  rp := public._ov_replay(p_client, 'role_bulk'); if rp is not null then return rp; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then raise exception 'bad_items'; end if;
  if jsonb_array_length(p_items) > 500 then raise exception 'too_many_items'; end if;
  for it in select * from jsonb_array_elements(p_items) loop
    r := public._ov_put_role(p_role, it->>'key', it->>'mode'); n := n + 1;
    if (r->>'changed')::boolean then ch := ch || jsonb_build_array(r); end if;
  end loop;
  perform public._ov_audit('role_option_view', p_role, ch);
  res := jsonb_build_object('role_code', p_role, 'count', n, 'changed', jsonb_array_length(ch));
  perform public._ov_remember(p_client, 'role_bulk', res);
  return res;
end $$;

-- =====================================================================
-- readers
-- =====================================================================
-- the caller's own effective choices: [{"key","mode","src"}]. Empty = nothing changes for this person.
create or replace function public.my_option_views() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when auth.uid() is null or not public.is_active() then '[]'::jsonb
    else coalesce((select jsonb_agg(jsonb_build_object('key', e.option_key, 'mode', e.mode, 'src', e.src) order by e.option_key) from public._ov_effective(auth.uid()) e), '[]'::jsonb) end;
$$;

-- everything the owner screen needs for ONE person: their choices, role defaults, and what they may use today (to show granted / not granted).
-- Owner: any person. Anybody else: only themself.
create or replace function public.option_views_for_user(p_user uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare p public.profiles; own boolean; perms jsonb; roles_ jsonb; locs jsonb; gr jsonb;
begin
  if not (public.is_owner() or (p_user is not null and p_user = auth.uid())) then raise exception 'not allowed'; end if;
  select * into p from public.profiles where id = p_user;
  if not found then raise exception 'unknown user'; end if;
  own := p.status = 'active' and exists (select 1 from public.user_roles where user_id = p.id and role_code = 'owner');
  select coalesce(jsonb_agg(role_code order by role_code), '[]') into roles_ from public.user_roles where user_id = p.id;
  select coalesce(jsonb_agg(location_id order by location_id), '[]') into locs from public.user_locations where user_id = p.id;
  if p.status <> 'active' then perms := '{}'::jsonb;
  elsif own then select coalesce(jsonb_object_agg(code, jsonb_build_object('view', true, 'enter', true, 'approve', true)), '{}') into perms from public.forms;
  else
    select coalesce(jsonb_object_agg(form_code, jsonb_build_object('view', v, 'enter', e, 'approve', a)), '{}') into perms from (
      select pf.form_code, bool_or(pf.can_view) v, bool_or(pf.can_enter) e, bool_or(pf.can_approve) a
        from public.user_roles ur join public.role_form_perms pf on pf.role_code = ur.role_code
        join public.roles r on r.code = ur.role_code and r.active where ur.user_id = p.id group by pf.form_code) x;
  end if;
  if p.status <> 'active' then gr := '[]'::jsonb;
  elsif own then select coalesce(jsonb_agg(grant_code order by grant_code), '[]') into gr from public.grant_defs;
  else
    select coalesce(jsonb_agg(c order by c), '[]') into gr from (
      select g.grant_code c from public.user_roles ur join public.rule_grants g on g.role_code = ur.role_code and g.allowed
        join public.roles r on r.code = ur.role_code and r.active where ur.user_id = p.id
      union
      select ug.grant_code from public.user_grants ug where ug.user_id = p.id and (ug.valid_until is null or ug.valid_until > now())) z;
  end if;
  return jsonb_build_object('user', jsonb_build_object('id', p.id, 'staff_id', p.staff_id, 'name', p.full_name, 'status', p.status),
    'is_owner', own, 'roles', roles_, 'locations', locs, 'perms', perms, 'grants', gr,
    'overrides', coalesce((select jsonb_agg(jsonb_build_object('key', u.option_key, 'mode', u.mode, 'set_at', u.set_at) order by u.option_key) from public.user_option_view u where u.user_id = p.id), '[]'::jsonb),
    'role_defaults', coalesce((select jsonb_agg(jsonb_build_object('role', d.role_code, 'key', d.option_key, 'mode', d.mode) order by d.role_code, d.option_key)
        from public.role_option_view d join public.user_roles ur on ur.role_code = d.role_code and ur.user_id = p.id), '[]'::jsonb),
    'effective', coalesce((select jsonb_agg(jsonb_build_object('key', e.option_key, 'mode', e.mode, 'src', e.src) order by e.option_key) from public._ov_effective(p.id) e), '[]'::jsonb));
end $$;

-- owner: the role defaults of one role (or all roles when null)
create or replace function public.role_option_views(p_role text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('role', d.role_code, 'key', d.option_key, 'mode', d.mode, 'set_at', d.set_at) order by d.role_code, d.option_key)
    from public.role_option_view d where p_role is null or d.role_code = p_role), '[]'::jsonb);
end $$;

-- =====================================================================
-- Vis5 permission RECOMMENDATIONS (advice only: nothing here blocks, grants or removes anything by itself)
--   perm_reco_role      role -> grants usually appropriate for it (seeded from today's rule_grants + a few plain additions; the owner can edit)
--   perm_conflict       two tokens a person should usually NOT hold together (segregation of duties). Token = a grant code | 'role:<code>' | 'module:<grant module>' | 'form:<code>' (any enter / approve right)
--   perm_reco_ignore    items the owner chose to ignore for one person
-- =====================================================================
create table if not exists public.perm_reco_role (
  role_code text not null references public.roles(code) on delete cascade,
  grant_code text not null references public.grant_defs(grant_code) on delete cascade,
  reason_bn text not null, reason_mix text not null, reason_en text not null,
  primary key (role_code, grant_code)
);
create table if not exists public.perm_conflict (
  token_a text not null, token_b text not null, check (token_a <> token_b),
  reason_bn text not null, reason_mix text not null, reason_en text not null,
  active boolean not null default true,
  primary key (token_a, token_b)
);
create table if not exists public.perm_reco_ignore (
  user_id uuid not null references public.profiles(id) on delete cascade,
  item_key text not null check (char_length(item_key) between 3 and 200),
  set_by uuid, set_at timestamptz not null default now(),
  primary key (user_id, item_key)
);

-- seed 1: what each role already gets today is "usual for the role"
insert into public.perm_reco_role (role_code, grant_code, reason_bn, reason_mix, reason_en)
  select g.role_code, g.grant_code, 'এই ভূমিকায় সাধারণত দরকার (আজকের ডিফল্ট)', 'এই role-এ সাধারণত দরকার (আজকের default)', 'Usually needed by this role (today''s default)'
    from public.rule_grants g where g.allowed and exists (select 1 from public.roles r where r.code = g.role_code) and exists (select 1 from public.grant_defs d where d.grant_code = g.grant_code)
  on conflict do nothing;
-- seed 2: a few plain additions for roles that have no default grants
insert into public.perm_reco_role (role_code, grant_code, reason_bn, reason_mix, reason_en)
  select v.r, v.g, v.bn, v.mx, v.en from (values
    ('cash_controller', 'cash_move', 'ক্যাশ নিয়ন্ত্রকের কাজ: জমা ও টাকা ঢোকানো লেখা', 'Cash controller-এর কাজ: deposit ও টাকা ঢোকানো লেখা', 'A cash controller records deposits and top-ups'),
    ('cash_controller', 'view_daybook', 'দিনের খাতা মেলাতে দেখতে হয়', 'Day book মেলাতে দেখতে হয়', 'Needs the day book to tally cash'),
    ('cash_controller', 'report_cash', 'পেমেন্ট ও ওয়ালেটের রিপোর্ট দেখা', 'Payment ও wallet report দেখা', 'Needs the payments and wallets report'),
    ('party_coordinator', 'sale_without_customer', 'পার্টি/পাইকারি বিক্রিতে মোবাইল ছাড়া বাকি লাগতে পারে', 'Party/wholesale sale-এ mobile ছাড়া due লাগতে পারে', 'Party and wholesale sales may need a due sale without a mobile'),
    ('party_coordinator', 'report_orders', 'অর্ডার ও ডেলিভারির রিপোর্ট দেখা', 'Order ও delivery report দেখা', 'Needs the orders and delivery report')
  ) v(r, g, bn, mx, en)
  where exists (select 1 from public.roles r where r.code = v.r) and exists (select 1 from public.grant_defs d where d.grant_code = v.g)
  on conflict do nothing;

-- seed 3: do-not-combine pairs (the owner can switch any off or add his own)
insert into public.perm_conflict (token_a, token_b, reason_bn, reason_mix, reason_en) values
 ('purchase_entry', 'supplier_pay', 'একই লোক ক্রয় বিল লিখলে আবার সরবরাহকারীকে টাকা দেওয়ার অনুমতি না থাকাই ভালো', 'একই লোক purchase bill লিখলে আবার supplier-কে payment-এর অনুমতি না থাকাই ভালো', 'The person who enters purchase bills should not also pay suppliers'),
 ('purchase_entry', 'purchase_void', 'যে বিল লেখে সে-ই বাতিল করতে পারলে ভুল/গড়বড় ধরা কঠিন', 'যে bill লেখে সে-ই void করতে পারলে ভুল/গড়বড় ধরা কঠিন', 'If the same person enters and voids a bill, mistakes are hard to catch'),
 ('recipe_manage', 'recipe_approve', 'যে রেসিপি বদলায় সে-ই অনুমোদন করা ঠিক নয়', 'যে recipe বদলায় সে-ই approve করা ঠিক নয়', 'The person who edits a recipe should not approve it'),
 ('wastage_write_off', 'wastage_approve', 'যে নষ্ট লেখে সে-ই বড় নষ্টের অনুমোদন দেবে না', 'যে wastage লেখে সে-ই বড় wastage approve করবে না', 'The person who writes off wastage should not approve large write-offs'),
 ('sale_void', 'stock_count_adjust', 'বিক্রি বাতিল ও স্টক গণনা সমন্বয় একসাথে থাকলে ঘাটতি লুকানো যায়', 'Sale void ও stock count adjust একসাথে থাকলে ঘাটতি লুকানো যায়', 'Voiding sales and adjusting stock counts together can hide a shortage'),
 ('sell_below_zero', 'stock_count_adjust', 'স্টকের চেয়ে বেশি বিক্রি ও গণনা সমন্বয় একসাথে থাকলে হিসাব ঢাকা পড়ে', 'Stock-এর চেয়ে বেশি sale ও count adjust একসাথে থাকলে হিসাব ঢাকা পড়ে', 'Selling beyond stock and adjusting counts together can cover up differences'),
 ('cash_move', 'accounts_manage', 'যে টাকা ঢোকায়/জমা লেখে সে-ই খাতা (জার্নাল) বদলালে নজরদারি থাকে না', 'যে cash move লেখে সে-ই journal বদলালে নজরদারি থাকে না', 'The person who records cash moves should not also edit the ledger or journal'),
 ('supplier_pay', 'accounts_manage', 'সরবরাহকারীকে টাকা দেওয়া ও খাতা বদলানো একজনের হাতে ঠিক নয়', 'Supplier payment ও ledger edit একজনের হাতে ঠিক নয়', 'Paying suppliers and editing the ledger should not be in one person''s hands'),
 ('closed_period_edit', 'accounts_manage', 'বন্ধ সময়ে বদল ও খাতা বদল একসাথে থাকা ঝুঁকিপূর্ণ', 'Closed period edit ও ledger edit একসাথে থাকা ঝুঁকিপূর্ণ', 'Editing closed periods together with the ledger is risky'),
 ('view_cost', 'price_override', 'ক্রয়মূল্য দেখা ও দাম বদলানো একসাথে থাকলে ইচ্ছামতো দাম ঠিক করা যায়', 'Cost দেখা ও price বদলানো একসাথে থাকলে ইচ্ছামতো দাম ঠিক করা যায়', 'Seeing cost and changing prices together makes it easy to set prices privately'),
 ('view_cost', 'discount_over_limit', 'ক্রয়মূল্য দেখা ও সীমার বেশি ছাড় দেওয়া একসাথে না থাকাই ভালো', 'Cost দেখা ও limit-এর বেশি discount দেওয়া একসাথে না থাকাই ভালো', 'Seeing cost and giving discounts above the limit should not go together'),
 ('item_bulk', 'change_approve', 'যে একসাথে বদলায় সে-ই পরিবর্তন অনুমোদন করা ঠিক নয়', 'যে bulk বদলায় সে-ই change approve করা ঠিক নয়', 'The person who changes items in bulk should not approve changes'),
 ('payroll_manage', 'salary_manage', 'বেতন কাঠামো বানানো ও বেতন দেওয়া একজনের হাতে ঠিক নয়', 'Pay structure বানানো ও salary দেওয়া একজনের হাতে ঠিক নয়', 'Setting pay structures and paying salaries should be two people'),
 ('role:intake_bot', 'module:pos', 'ইনটেক বটের কোনো POS অধিকার থাকা উচিত নয়', 'Intake bot-এর কোনো POS right থাকা উচিত নয়', 'An intake bot should hold no POS right'),
 ('role:intake_bot', 'form:POS', 'ইনটেক বট POS-এ ঢুকতে বা বিক্রি করতে পারবে না', 'Intake bot POS-এ ঢুকতে বা sell করতে পারবে না', 'An intake bot should not enter or use POS')
on conflict do nothing;

-- all grant codes a person holds right now (role grants + personal grants not expired). The owner holds everything.
create or replace function public._ov_grants(p_user uuid) returns text[] language sql stable security definer set search_path = public as $$
  select case
    when exists (select 1 from public.profiles p join public.user_roles ur on ur.user_id = p.id and ur.role_code = 'owner' where p.id = p_user and p.status = 'active')
      then coalesce((select array_agg(grant_code) from public.grant_defs), '{}')
    when not exists (select 1 from public.profiles where id = p_user and status = 'active') then '{}'
    else coalesce((select array_agg(c) from (
      select g.grant_code c from public.user_roles ur join public.rule_grants g on g.role_code = ur.role_code and g.allowed
        join public.roles r on r.code = ur.role_code and r.active where ur.user_id = p_user
      union
      select ug.grant_code from public.user_grants ug where ug.user_id = p_user and (ug.valid_until is null or ug.valid_until > now())) z), '{}') end;
$$;

-- does the person hold this token?
create or replace function public._ov_holds(p_user uuid, p_tok text, p_grants text[]) returns boolean language sql stable security definer set search_path = public as $$
  select case
    when p_tok like 'role:%' then exists (select 1 from public.user_roles where user_id = p_user and role_code = substr(p_tok, 6))
    when p_tok like 'module:%' then exists (select 1 from public.grant_defs d where d.module = substr(p_tok, 8) and d.grant_code = any (p_grants))
    when p_tok like 'form:%' then exists (select 1 from public.user_roles ur join public.role_form_perms pf on pf.role_code = ur.role_code
         join public.roles r on r.code = ur.role_code and r.active where ur.user_id = p_user and pf.form_code = substr(p_tok, 6) and (pf.can_enter or pf.can_approve))
    else p_tok = any (p_grants) end;
$$;

-- owner: advice for ONE person (never blocks anything). Items the owner ignored are listed apart, not hidden.
create or replace function public.permission_recommendations(p_user uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare p public.profiles; gr text[]; own boolean; miss jsonb; combo jsonb; unu jsonb; ign jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select * into p from public.profiles where id = p_user;
  if not found then raise exception 'unknown user'; end if;
  own := p.status = 'active' and exists (select 1 from public.user_roles where user_id = p.id and role_code = 'owner');
  if own then return jsonb_build_object('is_owner', true, 'recommended_missing', '[]'::jsonb, 'not_recommended_combo', '[]'::jsonb, 'unused', '[]'::jsonb, 'ignored', '[]'::jsonb); end if;
  gr := public._ov_grants(p.id);
  select coalesce(jsonb_agg(ig.item_key), '[]'::jsonb) into ign from public.perm_reco_ignore ig where ig.user_id = p.id;
  select coalesce(jsonb_agg(jsonb_build_object('item', 'miss:' || x.grant_code, 'grant', x.grant_code, 'role', x.role_code,
         'label', jsonb_build_object('bn', d.label_bn, 'mix', d.label_mix, 'en', d.label_en),
         'reason', jsonb_build_object('bn', x.reason_bn, 'mix', x.reason_mix, 'en', x.reason_en), 'ignored', exists (select 1 from public.perm_reco_ignore ig where ig.user_id = p.id and ig.item_key = 'miss:' || x.grant_code))
         order by x.grant_code), '[]'::jsonb) into miss
    from (select distinct on (r.grant_code) r.* from public.perm_reco_role r join public.user_roles ur on ur.role_code = r.role_code and ur.user_id = p.id
           join public.roles ro on ro.code = r.role_code and ro.active where not (r.grant_code = any (gr)) order by r.grant_code, r.role_code) x
    join public.grant_defs d on d.grant_code = x.grant_code;
  select coalesce(jsonb_agg(jsonb_build_object('item', 'combo:' || c.token_a || '|' || c.token_b, 'a', c.token_a, 'b', c.token_b,
         'reason', jsonb_build_object('bn', c.reason_bn, 'mix', c.reason_mix, 'en', c.reason_en), 'ignored', exists (select 1 from public.perm_reco_ignore ig where ig.user_id = p.id and ig.item_key = 'combo:' || c.token_a || '|' || c.token_b))
         order by c.token_a, c.token_b), '[]'::jsonb) into combo
    from public.perm_conflict c where c.active and public._ov_holds(p.id, c.token_a, gr) and public._ov_holds(p.id, c.token_b, gr);
  -- unused / never needed: forms the person cannot even view and has no Hide choice for yet (screens are judged by the app, which knows the screen list)
  select coalesce(jsonb_agg(jsonb_build_object('item', 'unused:f:' || f.code, 'key', 'f:' || f.code, 'suggest', 'hide',
         'reason', jsonb_build_object('bn', 'এই ফর্মের অনুমতি নেই; দরকার না হলে লুকিয়ে রাখুন', 'mix', 'এই form-এর permission নেই; দরকার না হলে hide করুন', 'en', 'No permission for this form; hide it if never needed'),
         'ignored', exists (select 1 from public.perm_reco_ignore ig where ig.user_id = p.id and ig.item_key = 'unused:f:' || f.code)) order by f.code), '[]'::jsonb) into unu
    from public.forms f
   where f.code <> 'POS' and p.status = 'active'
     and not exists (select 1 from public.user_roles ur join public.role_form_perms pf on pf.role_code = ur.role_code join public.roles r on r.code = ur.role_code and r.active
                      where ur.user_id = p.id and pf.form_code = f.code and pf.can_view)
     and not exists (select 1 from public._ov_effective(p.id) e where e.option_key = 'f:' || f.code and e.mode = 'hide');
  return jsonb_build_object('is_owner', false, 'recommended_missing', miss, 'not_recommended_combo', combo, 'unused', unu, 'ignored', ign);
end $$;

-- owner: ignore (or stop ignoring) one advice item for one person
create or replace function public.reco_ignore_set(p_user uuid, p_item text, p_ignore boolean default true, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare rp jsonb; res jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  rp := public._ov_replay(p_client, 'reco_ignore'); if rp is not null then return rp; end if;
  if p_item is null or p_item !~ '^(miss|combo|unused):.{1,190}$' then raise exception 'bad_item'; end if;
  if not exists (select 1 from public.profiles where id = p_user) then raise exception 'unknown user'; end if;
  if coalesce(p_ignore, true) then
    insert into public.perm_reco_ignore (user_id, item_key, set_by) values (p_user, p_item, auth.uid()) on conflict do nothing;
  else delete from public.perm_reco_ignore where user_id = p_user and item_key = p_item; end if;
  perform public._ov_audit('perm_reco_ignore', p_user::text, jsonb_build_array(jsonb_build_object('item', p_item, 'ignore', coalesce(p_ignore, true))));
  res := jsonb_build_object('user_id', p_user, 'item', p_item, 'ignored', coalesce(p_ignore, true));
  perform public._ov_remember(p_client, 'reco_ignore', res);
  return res;
end $$;

-- owner: apply ONE advice item with one tap (audited).  miss:<grant> = give the personal grant; unused:<key> = Hide that option;
--        combo:<a>|<b> = take back the PERSONAL grant b (or a) if that one was given personally; a grant that comes from the role must be changed in the role.
create or replace function public.reco_apply(p_user uuid, p_item text, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare rp jsonb; res jsonb; k text; a text; b text; n int := 0;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  rp := public._ov_replay(p_client, 'reco_apply'); if rp is not null then return rp; end if;
  if not exists (select 1 from public.profiles where id = p_user) then raise exception 'unknown user'; end if;
  if p_item like 'miss:%' then
    k := substr(p_item, 6);
    if not exists (select 1 from public.perm_reco_role r join public.user_roles ur on ur.role_code = r.role_code and ur.user_id = p_user where r.grant_code = k) then raise exception 'not_recommended'; end if;
    perform public.set_user_grant(p_user, k, null, null, true, 'recommended (bos91)');
    res := jsonb_build_object('applied', 'grant', 'grant', k);
  elsif p_item like 'unused:%' then
    k := substr(p_item, 8);
    res := jsonb_build_object('applied', 'hide') || public._ov_put_user(p_user, k, 'hide');
    if (res->>'changed')::boolean then perform public._ov_audit('user_option_view', p_user::text, jsonb_build_array(res - 'applied')); end if;
  elsif p_item like 'combo:%' then
    a := split_part(substr(p_item, 7), '|', 1); b := split_part(substr(p_item, 7), '|', 2);
    if not exists (select 1 from public.perm_conflict where token_a = a and token_b = b) then raise exception 'unknown_combo'; end if;
    delete from public.user_grants where user_id = p_user and grant_code = b and (select count(*) from public.grant_defs where grant_code = b) = 1; get diagnostics n = row_count;
    if n = 0 then delete from public.user_grants where user_id = p_user and grant_code = a and (select count(*) from public.grant_defs where grant_code = a) = 1; get diagnostics n = row_count; end if;
    if n = 0 then raise exception 'not_personal_grant'; end if;
    res := jsonb_build_object('applied', 'revoke_personal', 'removed', n);
  else raise exception 'bad_item'; end if;
  perform public._ov_audit('perm_reco_apply', p_user::text, jsonb_build_array(jsonb_build_object('item', p_item, 'result', res)));
  res := res || jsonb_build_object('user_id', p_user, 'item', p_item);
  perform public._ov_remember(p_client, 'reco_apply', res);
  return res;
end $$;

-- owner edits the advice lists
create or replace function public.reco_role_set(p_role text, p_grant text, p_on boolean, p_bn text default null, p_mix text default null, p_en text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.roles where code = p_role) then raise exception 'unknown role'; end if;
  if not exists (select 1 from public.grant_defs where grant_code = p_grant) then raise exception 'unknown grant'; end if;
  if coalesce(p_on, true) then
    insert into public.perm_reco_role (role_code, grant_code, reason_bn, reason_mix, reason_en)
      values (p_role, p_grant, coalesce(nullif(btrim(p_bn), ''), 'মালিক যোগ করেছেন'), coalesce(nullif(btrim(p_mix), ''), 'Owner যোগ করেছেন'), coalesce(nullif(btrim(p_en), ''), 'Added by the owner'))
      on conflict (role_code, grant_code) do update set reason_bn = coalesce(nullif(btrim(p_bn), ''), perm_reco_role.reason_bn), reason_mix = coalesce(nullif(btrim(p_mix), ''), perm_reco_role.reason_mix), reason_en = coalesce(nullif(btrim(p_en), ''), perm_reco_role.reason_en);
  else delete from public.perm_reco_role where role_code = p_role and grant_code = p_grant; end if;
  perform public._ov_audit('perm_reco_role', p_role, jsonb_build_array(jsonb_build_object('grant', p_grant, 'on', coalesce(p_on, true))));
end $$;

create or replace function public.reco_conflict_set(p_a text, p_b text, p_active boolean, p_bn text default null, p_mix text default null, p_en text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_a is null or p_b is null or p_a = p_b or p_a !~ '^[a-z_]+(:[A-Za-z0-9_.-]+)?$' or p_b !~ '^[a-z_]+(:[A-Za-z0-9_.-]+)?$' then raise exception 'bad_token'; end if;
  insert into public.perm_conflict (token_a, token_b, reason_bn, reason_mix, reason_en, active)
    values (p_a, p_b, coalesce(nullif(btrim(p_bn), ''), 'মালিকের নিয়ম'), coalesce(nullif(btrim(p_mix), ''), 'Owner-এর নিয়ম'), coalesce(nullif(btrim(p_en), ''), 'Owner rule'), coalesce(p_active, true))
    on conflict (token_a, token_b) do update set active = coalesce(p_active, true), reason_bn = coalesce(nullif(btrim(p_bn), ''), perm_conflict.reason_bn),
      reason_mix = coalesce(nullif(btrim(p_mix), ''), perm_conflict.reason_mix), reason_en = coalesce(nullif(btrim(p_en), ''), perm_conflict.reason_en);
  perform public._ov_audit('perm_conflict', p_a || '|' || p_b, jsonb_build_array(jsonb_build_object('active', coalesce(p_active, true))));
end $$;

alter table public.perm_reco_role enable row level security;
alter table public.perm_conflict enable row level security;
alter table public.perm_reco_ignore enable row level security;
revoke all on public.perm_reco_role, public.perm_conflict, public.perm_reco_ignore from public, anon, authenticated;
grant select on public.perm_reco_role, public.perm_conflict, public.perm_reco_ignore to authenticated;
drop policy if exists perm_reco_role_read on public.perm_reco_role;
create policy perm_reco_role_read on public.perm_reco_role for select to authenticated using (public.is_owner());
drop policy if exists perm_conflict_read on public.perm_conflict;
create policy perm_conflict_read on public.perm_conflict for select to authenticated using (public.is_owner());
drop policy if exists perm_reco_ignore_read on public.perm_reco_ignore;
create policy perm_reco_ignore_read on public.perm_reco_ignore for select to authenticated using (public.is_owner());
revoke all on function public.permission_recommendations(uuid), public.reco_ignore_set(uuid, text, boolean, uuid), public.reco_apply(uuid, text, uuid),
  public.reco_role_set(text, text, boolean, text, text, text), public.reco_conflict_set(text, text, boolean, text, text, text) from public, anon;
grant execute on function public.permission_recommendations(uuid), public.reco_ignore_set(uuid, text, boolean, uuid), public.reco_apply(uuid, text, uuid),
  public.reco_role_set(text, text, boolean, text, text, text), public.reco_conflict_set(text, text, boolean, text, text, text) to authenticated;
revoke all on function public._ov_grants(uuid), public._ov_holds(uuid, text, text[]) from public, anon, authenticated;

-- =====================================================================
-- RLS + privileges (the browser can read its own rows; every write goes through the functions)
-- =====================================================================
alter table public.user_option_view enable row level security;
alter table public.role_option_view enable row level security;
alter table public.option_view_ops enable row level security;
revoke all on public.user_option_view, public.role_option_view, public.option_view_ops from public, anon, authenticated;
grant select on public.user_option_view, public.role_option_view to authenticated;
drop policy if exists user_option_view_read on public.user_option_view;
create policy user_option_view_read on public.user_option_view for select to authenticated using (user_id = auth.uid() or public.is_owner());
drop policy if exists role_option_view_read on public.role_option_view;
create policy role_option_view_read on public.role_option_view for select to authenticated using (public.is_owner());

revoke all on function public.set_option_view(uuid, text, text, uuid), public.set_option_view_bulk(uuid, jsonb, uuid), public.set_role_option_view(text, text, text, uuid),
  public.set_role_option_view_bulk(text, jsonb, uuid), public.my_option_views(), public.option_views_for_user(uuid), public.role_option_views(text) from public, anon;
grant execute on function public.set_option_view(uuid, text, text, uuid), public.set_option_view_bulk(uuid, jsonb, uuid), public.set_role_option_view(text, text, text, uuid),
  public.set_role_option_view_bulk(text, jsonb, uuid), public.my_option_views(), public.option_views_for_user(uuid), public.role_option_views(text) to authenticated;
revoke all on function public._ov_mode(text), public._ov_key(text, text), public._ov_put_user(uuid, text, text), public._ov_put_role(text, text, text), public._ov_replay(uuid, text),
  public._ov_remember(uuid, text, jsonb), public._ov_audit(text, text, jsonb), public._ov_effective(uuid) from public, anon, authenticated;
notify pgrst, 'reload schema';
