-- Phase 130 (package R2-A) - ANNOUNCEMENTS: a message from the owner (or a person he designates) to everyone, a role, a place or one person.
-- Paste after phase99 (needs phase7/8 rules + grants, phase11 no_hard_delete). Paste-twice safe. No earlier phase file is edited and NO shared function is
-- patched or re-created (nothing to hook): with the switch announce_on OFF (the default) nothing reads or writes these tables and every screen is as before.
--
-- WHAT THIS FILE ADDS (every new name starts r2_ / _r2_ so it cannot clash with another package)
--   1. Setting   announce_on (rules, module people)   OFF by default. OFF = the headline bar is never shown, posting is refused (announce_off).
--   2. Grant     announce_post (grant_defs)           who may post. Nobody holds it by default except the owner. The owner gives it to a role (rule_grants)
--                or to one person (user_grants, optionally for one place only) on the existing Delegation board. A person's grant limited to one place can
--                post only to that place; a grant without a place can post to everyone, a role, a place or a person.
--   3. Tables    r2_announcements (the message, who, when, the audience, start / expiry, urgent flag, status active|withdrawn)
--                r2_announce_seen (read receipt: one row per person and announcement, written only by r2_announce_seen)
--                Both: row level security (a person reads only what is addressed to him, or what he posted; the owner reads all), no browser write, no delete.
--   4. API       r2_announce_state()                 switch, may I post, places I may post to
--                r2_announce_post(...)               post (checks switch, grant, target, dates; client id makes a retry harmless)
--                r2_announce_active()                what is on the bar for ME right now (empty when OFF)
--                r2_announce_seen(id)                "I have read this" (only for a person it is addressed to, only while it is on)
--                r2_announce_mine()                  what I posted (owner: all) with audience and seen counts
--                r2_announce_receipts(id)            who has seen it and who has not (poster and owner only)
--                r2_announce_withdraw(id, reason)    stop it now (poster and owner only; the row stays, nothing is deleted)
-- AUDIENCE: all = every active login; role = people holding that role; location = people linked to that place in user_locations; person = one login.
--   (A manager who reaches every place through the management role but has no user_locations row for it is not counted in a place audience.)

do $g$ begin
  if to_regprocedure('public.has_grant(text,integer)') is null or to_regprocedure('public.rule_on(text)') is null
     or to_regprocedure('public.log_change()') is null or to_regprocedure('public.no_hard_delete()') is null
     or to_regprocedure('public._client_lock(uuid)') is null then
    raise exception 'phase130 needs the rules and grants engine (phase 7, 8, 10, 11) first';
  end if;
end $g$;

create or replace function public._r2a_present() returns boolean language sql stable as $$ select true $$;

-- ============================================================================
-- 1. SETTING and GRANT (safe defaults: OFF, nobody)
-- ============================================================================
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('announce_on', 'people', 'switch', 'false'::jsonb, null, null, null, null,
  'ঘোষণা ও নির্দেশ চালু (উপরের চলমান লাইন)', 'ঘোষণা / Announcements চালু (উপরের headline bar)', 'Announcements are on (headline bar at the top)',
  'বন্ধ থাকলে কোনো বার দেখা যায় না এবং ঘোষণা দেওয়া যায় না; অ্যাপ আগের মতোই চলে। চালু করলে যাদের জন্য ঘোষণা আছে তারা উপরে চলমান লাইন দেখবে।',
  'বন্ধ থাকলে কোনো bar দেখা যায় না, ঘোষণা দেওয়া যায় না; app আগের মতোই। চালু করলে যাদের জন্য ঘোষণা আছে তারা উপরে bar দেখবে।',
  'OFF = no bar is shown and nothing can be posted; the app is as before. ON = people an announcement is addressed to see a slim headline bar at the top. Who may post is the grant announce_post.', 1300)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('announce_post', 'people', 76, 'ঘোষণা / নির্দেশ দেওয়া (সবাইকে, ভূমিকাকে, শাখাকে বা একজনকে)', 'ঘোষণা / instruction দেওয়া (সবাই, role, শাখা বা একজন)', 'Post announcements and instructions (to everyone, a role, a place or one person)', 'window', null)
on conflict (grant_code) do nothing;

-- ============================================================================
-- 2. TABLES
-- ============================================================================
create table if not exists public.r2_announcements (
  id bigserial primary key,
  client_id uuid unique,
  title text not null check (char_length(btrim(title)) between 1 and 120),
  body text not null default '' check (char_length(body) <= 2000),
  urgent boolean not null default false,
  target_kind text not null check (target_kind in ('all', 'role', 'location', 'person')),
  target_role text references public.roles(code),
  target_location int references public.locations(id),
  target_user uuid references public.profiles(id),
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  status text not null default 'active' check (status in ('active', 'withdrawn')),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  withdrawn_by uuid, withdrawn_at timestamptz, withdrawn_reason text,
  check ((target_kind = 'all' and target_role is null and target_location is null and target_user is null)
      or (target_kind = 'role' and target_role is not null and target_location is null and target_user is null)
      or (target_kind = 'location' and target_location is not null and target_role is null and target_user is null)
      or (target_kind = 'person' and target_user is not null and target_role is null and target_location is null)),
  check (ends_at is null or ends_at > starts_at)
);
create index if not exists r2_announcements_live on public.r2_announcements (starts_at, ends_at) where status = 'active';
create index if not exists r2_announcements_by on public.r2_announcements (created_by, created_at desc);

create table if not exists public.r2_announce_seen (
  announcement_id bigint not null references public.r2_announcements(id),
  user_id uuid not null references public.profiles(id),
  seen_at timestamptz not null default now(),
  primary key (announcement_id, user_id)
);

create or replace function public._r2a_seen_guard() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'a read receipt is never changed or removed'; end $$;
drop trigger if exists r2_announce_seen_no_change on public.r2_announce_seen;
create trigger r2_announce_seen_no_change before update or delete on public.r2_announce_seen for each row execute function public._r2a_seen_guard();
drop trigger if exists r2_announcements_no_delete on public.r2_announcements;
create trigger r2_announcements_no_delete before delete on public.r2_announcements for each row execute function public.no_hard_delete();
drop trigger if exists audit_r2_announcements on public.r2_announcements;
create trigger audit_r2_announcements after insert or update on public.r2_announcements for each row execute function public.log_change('id');

-- ============================================================================
-- 3. HELPERS (answer about the caller only)
-- ============================================================================
-- is this announcement's audience the caller? (used by the read policy, so authenticated may execute it)
create or replace function public._r2_ann_to_me(p_kind text, p_role text, p_loc int, p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and case p_kind
    when 'all' then true
    when 'role' then exists (select 1 from public.user_roles ur where ur.user_id = auth.uid() and ur.role_code = p_role)
    when 'location' then exists (select 1 from public.user_locations ul where ul.user_id = auth.uid() and ul.location_id = p_loc)
    when 'person' then p_user = auth.uid()
    else false end;
$$;

-- the audience of one announcement: active logins it is addressed to
create or replace function public._r2_ann_audience(p_id bigint) returns table (user_id uuid)
language sql stable security definer set search_path = public as $$
  select p.id from public.profiles p join public.r2_announcements a on a.id = p_id
   where p.status = 'active' and case a.target_kind
     when 'all' then true
     when 'role' then exists (select 1 from public.user_roles ur where ur.user_id = p.id and ur.role_code = a.target_role)
     when 'location' then exists (select 1 from public.user_locations ul where ul.user_id = p.id and ul.location_id = a.target_location)
     when 'person' then p.id = a.target_user
     else false end;
$$;

-- ============================================================================
-- 4. ROW LEVEL SECURITY (reads only; every write goes through the functions)
-- ============================================================================
alter table public.r2_announcements enable row level security;
alter table public.r2_announce_seen enable row level security;
revoke all on public.r2_announcements, public.r2_announce_seen from public, anon, authenticated;
grant select on public.r2_announcements, public.r2_announce_seen to authenticated;

drop policy if exists r2_ann_read on public.r2_announcements;
create policy r2_ann_read on public.r2_announcements for select to authenticated using (
  public.is_active() and (public.is_owner() or created_by = auth.uid() or (
    public.rule_on('announce_on') and status = 'active' and starts_at <= now() and (ends_at is null or ends_at > now())
    and public._r2_ann_to_me(target_kind, target_role, target_location, target_user))));
drop policy if exists r2_ann_seen_read on public.r2_announce_seen;
create policy r2_ann_seen_read on public.r2_announce_seen for select to authenticated using (
  public.is_active() and (public.is_owner() or user_id = auth.uid()
    or exists (select 1 from public.r2_announcements a where a.id = announcement_id and a.created_by = auth.uid())));

-- ============================================================================
-- 5. API
-- ============================================================================
create or replace function public.r2_announce_state() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_on boolean := public.rule_on('announce_on');
begin
  if not public.is_active() then return jsonb_build_object('on', false, 'can_post', false, 'can_post_all', false, 'post_locations', '[]'::jsonb); end if;
  return jsonb_build_object('on', v_on,
    'can_post_all', v_on and (public.is_owner() or public.has_grant('announce_post')),
    'can_post', v_on and (public.is_owner() or public.has_grant('announce_post')
                          or exists (select 1 from public.locations l where l.is_active and public.has_grant('announce_post', l.id))),
    'post_locations', case when v_on then coalesce((select jsonb_agg(l.id order by l.sort, l.id) from public.locations l where l.is_active and (public.is_owner() or public.has_grant('announce_post', l.id))), '[]'::jsonb) else '[]'::jsonb end);
end $$;

create or replace function public.r2_announce_post(p_title text, p_body text, p_urgent boolean, p_kind text, p_target text,
                                                    p_starts timestamptz default null, p_ends timestamptz default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_role text; v_loc int; v_user uuid; v_id bigint; v_start timestamptz := coalesce(p_starts, now());
        v_title text := btrim(coalesce(p_title, '')); v_body text := btrim(coalesce(p_body, '')); n int;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('announce_on') then raise exception 'announce_off'; end if;
  if p_kind is null or p_kind not in ('all', 'role', 'location', 'person') then raise exception 'bad_target'; end if;
  begin
    if p_kind = 'role' then v_role := nullif(btrim(coalesce(p_target, '')), '');
    elsif p_kind = 'location' then v_loc := p_target::int;
    elsif p_kind = 'person' then v_user := p_target::uuid; end if;
  exception when others then raise exception 'bad_target'; end;
  -- who may post: the owner, or a holder of announce_post (a grant limited to one place covers only that place)
  if not (public.is_owner() or public.has_grant('announce_post', v_loc)) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then select id into v_id from public.r2_announcements where client_id = p_client; if found then return jsonb_build_object('id', v_id, 'repeat', true); end if; end if;
  if char_length(v_title) < 1 or char_length(v_title) > 120 then raise exception 'title_required'; end if;
  if char_length(v_body) > 2000 then raise exception 'text_too_long'; end if;
  if p_kind = 'role' and not exists (select 1 from public.roles where code = v_role and active) then raise exception 'bad_target'; end if;
  if p_kind = 'location' and not exists (select 1 from public.locations where id = v_loc and is_active) then raise exception 'bad_target'; end if;
  if p_kind = 'person' and not exists (select 1 from public.profiles where id = v_user and status = 'active') then raise exception 'bad_target'; end if;
  if v_start < now() - interval '1 day' or v_start > now() + interval '400 days' then raise exception 'bad_date'; end if;
  if p_ends is not null and (p_ends <= v_start or p_ends <= now()) then raise exception 'bad_date'; end if;
  insert into public.r2_announcements (client_id, title, body, urgent, target_kind, target_role, target_location, target_user, starts_at, ends_at, created_by)
    values (p_client, v_title, v_body, coalesce(p_urgent, false), p_kind, v_role, v_loc, v_user, v_start, p_ends, auth.uid()) returning id into v_id;
  select count(*) into n from public._r2_ann_audience(v_id);
  return jsonb_build_object('id', v_id, 'audience', n);
end $$;

-- what is on the bar for the caller right now
create or replace function public.r2_announce_active() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() or not public.rule_on('announce_on') then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'title', a.title, 'body', a.body, 'urgent', a.urgent, 'target_kind', a.target_kind,
            'starts_at', a.starts_at, 'ends_at', a.ends_at, 'posted_at', a.created_at, 'poster', coalesce(nullif(p.full_name, ''), p.staff_id),
            'seen', exists (select 1 from public.r2_announce_seen s where s.announcement_id = a.id and s.user_id = auth.uid()))
            order by a.urgent desc, a.starts_at desc, a.id desc)
     from public.r2_announcements a left join public.profiles p on p.id = a.created_by
    where a.status = 'active' and a.starts_at <= now() and (a.ends_at is null or a.ends_at > now())
      and public._r2_ann_to_me(a.target_kind, a.target_role, a.target_location, a.target_user)), '[]'::jsonb);
end $$;

-- "I have read this"
create or replace function public.r2_announce_seen(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.r2_announcements; v_at timestamptz;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('announce_on') then raise exception 'announce_off'; end if;
  select * into a from public.r2_announcements where id = p_id;
  if not found or a.status <> 'active' or a.starts_at > now() or (a.ends_at is not null and a.ends_at <= now())
     or not public._r2_ann_to_me(a.target_kind, a.target_role, a.target_location, a.target_user) then raise exception 'not allowed'; end if;
  insert into public.r2_announce_seen (announcement_id, user_id) values (p_id, auth.uid()) on conflict do nothing;
  select seen_at into v_at from public.r2_announce_seen where announcement_id = p_id and user_id = auth.uid();
  return jsonb_build_object('id', p_id, 'seen', true, 'seen_at', v_at);
end $$;

-- what I posted (the owner sees everything), newest first, with audience and seen counts
create or replace function public.r2_announce_mine(p_limit int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(x order by (x ->> 'created_at') desc, (x ->> 'id')::bigint desc) from (
    select jsonb_build_object('id', a.id, 'title', a.title, 'body', a.body, 'urgent', a.urgent, 'target_kind', a.target_kind, 'target_role', a.target_role,
           'target_location', a.target_location, 'target_user', a.target_user,
           'target_name', case a.target_kind when 'person' then (select coalesce(nullif(t.full_name, ''), t.staff_id) from public.profiles t where t.id = a.target_user) end,
           'starts_at', a.starts_at, 'ends_at', a.ends_at, 'status', a.status, 'created_at', a.created_at, 'created_by', a.created_by,
           'poster', coalesce(nullif(p.full_name, ''), p.staff_id), 'withdrawn_reason', a.withdrawn_reason,
           'live', (a.status = 'active' and a.starts_at <= now() and (a.ends_at is null or a.ends_at > now())),
           'audience', (select count(*) from public._r2_ann_audience(a.id)),
           'seen', (select count(*) from public.r2_announce_seen s where s.announcement_id = a.id)) as x
      from public.r2_announcements a left join public.profiles p on p.id = a.created_by
     where public.is_owner() or a.created_by = auth.uid()
     order by a.created_at desc, a.id desc limit greatest(1, least(coalesce(p_limit, 50), 200))) z), '[]'::jsonb);
end $$;

-- read receipts: who has seen it, who has not (poster and owner only)
create or replace function public.r2_announce_receipts(p_id bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare a public.r2_announcements;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into a from public.r2_announcements where id = p_id;
  if not found or not (public.is_owner() or a.created_by = auth.uid()) then raise exception 'not allowed'; end if;
  return jsonb_build_object('id', a.id, 'title', a.title, 'status', a.status,
    'seen', coalesce((select jsonb_agg(jsonb_build_object('user_id', p.id, 'staff_id', p.staff_id, 'name', coalesce(nullif(p.full_name, ''), p.staff_id), 'seen_at', s.seen_at) order by s.seen_at)
                        from public.r2_announce_seen s join public.profiles p on p.id = s.user_id where s.announcement_id = a.id), '[]'::jsonb),
    'unseen', coalesce((select jsonb_agg(jsonb_build_object('user_id', p.id, 'staff_id', p.staff_id, 'name', coalesce(nullif(p.full_name, ''), p.staff_id)) order by p.full_name, p.staff_id)
                          from public._r2_ann_audience(a.id) au join public.profiles p on p.id = au.user_id
                         where not exists (select 1 from public.r2_announce_seen s where s.announcement_id = a.id and s.user_id = au.user_id)), '[]'::jsonb));
end $$;

create or replace function public.r2_announce_withdraw(p_id bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.r2_announcements;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into a from public.r2_announcements where id = p_id for update;
  if not found or not (public.is_owner() or a.created_by = auth.uid()) then raise exception 'not allowed'; end if;
  if nullif(btrim(coalesce(p_reason, '')), '') is null or char_length(p_reason) > 200 then raise exception 'reason_required'; end if;
  if a.status = 'withdrawn' then return jsonb_build_object('id', p_id, 'repeat', true); end if;
  update public.r2_announcements set status = 'withdrawn', withdrawn_by = auth.uid(), withdrawn_at = now(), withdrawn_reason = btrim(p_reason) where id = p_id;
  return jsonb_build_object('id', p_id, 'status', 'withdrawn');
end $$;

-- ============================================================================
-- 6. WHO MAY CALL WHAT (browsers: signed-in users only; helpers closed, except the one the read policy needs)
-- ============================================================================
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname in ('r2_announce_state', 'r2_announce_post', 'r2_announce_active', 'r2_announce_seen', 'r2_announce_mine', 'r2_announce_receipts', 'r2_announce_withdraw',
                                                            '_r2_ann_to_me', '_r2_ann_audience', '_r2a_seen_guard', '_r2a_present') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname in ('r2_announce_state', 'r2_announce_post', 'r2_announce_active', 'r2_announce_seen', 'r2_announce_mine', 'r2_announce_receipts', 'r2_announce_withdraw', '_r2_ann_to_me') then
      execute format('grant execute on function %s to authenticated', f.sig);
    end if;
  end loop;
end $$;
