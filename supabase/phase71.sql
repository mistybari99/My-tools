-- ============================================================
-- Phase 71 (bos71) - gap #18 two-factor (2FA, TOTP) for staff: SAFE CORE.
-- Factors live in Supabase Auth (auth.mfa_factors); the owner must enable MFA in the dashboard (docs/TWOFA.md). PIN scheme is NOT touched (#16 stays postponed).
--   rules   : twofa_required_roles (text, comma list, default empty = nobody is told they must), twofa_enforce_owner_writes (switch, default OFF)
--   helpers : _aal2() reads the jwt claim aal; _twofa_has_factor(uuid); _twofa_guard71()
--   reads   : twofa_policy() (caller), twofa_status_report() (owner only, no secrets)
--   guard   : when twofa_enforce_owner_writes is ON, set_rule / path_switch_set / acct_set_start / year_close_run / set_user_grant refuse
--             ('twofa_required') unless the jwt aal is aal2 - but ONLY for a user who has a verified factor (so nobody is locked out by switching it on).
-- Additive + paste-twice safe. Lock-out escape hatch (SQL editor, role postgres): update public.rules set value='false'::jsonb where key='twofa_enforce_owner_writes';
-- ============================================================

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('twofa_required_roles', 'security', 'text', '""', null, null, null, null,
  'যেসব ভূমিকার 2FA লাগবে (কমা দিয়ে)', '2FA লাগবে এমন role (comma দিয়ে)', 'Roles that should use 2FA (comma list)',
  'ফাঁকা = কাউকে বাধ্য করা হয় না। যেমন: owner,accountant। এটা শুধু জানানোর নীতি; লগইন আটকায় না।', 'ফাঁকা = কেউ forced না। যেমন owner,accountant। শুধু policy জানায়, login আটকায় না।', 'Empty = nobody is told they must. Example: owner,accountant. Informational only; it does not block login.', 710),
 ('twofa_enforce_owner_writes', 'security', 'switch', 'false', null, null, null, null,
  'মালিকের সংবেদনশীল কাজে 2FA বাধ্যতামূলক', 'Owner-এর sensitive কাজে 2FA বাধ্যতামূলক', 'Require 2FA code for the most sensitive owner actions',
  'চালু হলে নিয়ম বদল, পথ সুইচ, হিসাব শুরুর তারিখ, বছর-শেষ ক্লোজ ও অনুমতি দেওয়া — 2FA কোড দিয়ে ঢোকা ছাড়া হবে না। শুধু যাঁর যাচাই-করা 2FA আছে তাঁর জন্য।', 'ON হলে rule বদল, path switch, accounting start, year close, grant দেওয়া — 2FA code দিয়ে login ছাড়া হবে না। শুধু verified 2FA আছে এমন user-এর জন্য।', 'When ON: changing rules, path switches, accounting start date, year close and granting permissions need a session verified with a 2FA code. Applies only to users who HAVE a verified factor.', 711)
on conflict (key) do nothing;

-- jwt claim reader (what auth.jwt()->>'aal' returns on Supabase; PostgREST puts the claims in request.jwt.claims)
create or replace function public._aal2() returns boolean
language plpgsql stable set search_path = public as $$
declare c jsonb;
begin
  begin c := nullif(current_setting('request.jwt.claims', true), '')::jsonb; exception when others then c := null; end;
  return coalesce(c ->> 'aal', nullif(current_setting('request.jwt.claim.aal', true), ''), '') = 'aal2';
end $$;

create or replace function public._twofa_has_factor(p_user uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare r boolean := false;
begin
  if p_user is null or to_regclass('auth.mfa_factors') is null then return false; end if;
  execute 'select exists (select 1 from auth.mfa_factors where user_id = $1 and status = ''verified'')' into r using p_user;
  return coalesce(r, false);
end $$;

create or replace function public._twofa_guard71() returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if public.rule_on('twofa_enforce_owner_writes') and not public._aal2() and public._twofa_has_factor(auth.uid()) then
    raise exception 'twofa_required: sign in again and enter your 2FA code (aal2) for this action';
  end if;
end $$;

create or replace function public.twofa_policy() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); lst text[]; roles text[]; req boolean; hf boolean; aal2 boolean := public._aal2();
begin
  if uid is null or not public.is_active() then raise exception 'not allowed'; end if;
  lst := array(select btrim(x) from unnest(string_to_array(lower(coalesce(public.rule_val('twofa_required_roles') #>> '{}', '')), ',')) x where btrim(x) <> '');
  roles := array(select role_code from public.user_roles where user_id = uid);
  req := roles && lst;
  hf := public._twofa_has_factor(uid);
  return jsonb_build_object('required', req, 'has_verified_factor', hf, 'aal2', aal2,
    'enforce_owner_writes', public.rule_on('twofa_enforce_owner_writes'),
    'listed_roles', to_jsonb(lst), 'my_roles', to_jsonb(roles),
    'must_enroll', req and not hf,
    'sensitive_actions_blocked_now', public.rule_on('twofa_enforce_owner_writes') and hf and not aal2);
end $$;

create or replace function public.twofa_status_report() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out jsonb; lst text[];
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  lst := array(select btrim(x) from unnest(string_to_array(lower(coalesce(public.rule_val('twofa_required_roles') #>> '{}', '')), ',')) x where btrim(x) <> '');
  select coalesce(jsonb_agg(jsonb_build_object('user_id', p.id, 'staff_id', p.staff_id, 'name', p.full_name, 'roles', to_jsonb(rl.roles),
      'verified_factors', f.n, 'has_2fa', f.n > 0, 'required', rl.roles && lst, 'missing', (rl.roles && lst) and f.n = 0) order by p.staff_id), '[]'::jsonb) into out
  from public.profiles p
  cross join lateral (select coalesce(array_agg(role_code), '{}'::text[]) as roles from public.user_roles ur where ur.user_id = p.id) rl
  cross join lateral (select case when to_regclass('auth.mfa_factors') is null then 0 else
      (select count(*)::int from auth.mfa_factors m where m.user_id = p.id and m.status = 'verified') end as n) f
  where p.status = 'active';
  return jsonb_build_object('enforce_owner_writes', public.rule_on('twofa_enforce_owner_writes'), 'listed_roles', to_jsonb(lst), 'users', out);
end $$;

-- guard injection: take the LIVE definition, add one line after the owner check (skips if already tagged bos71 or the pattern is absent)
do $do$
declare f text; def text; pat text := 'if not public.is_owner() then raise exception ''not allowed''; end if;';
begin
  foreach f in array array['set_rule(text,jsonb)', 'path_switch_set(text,integer,boolean,boolean,text,text)', 'acct_set_start(date)', 'year_close_run(date,date,text,uuid,boolean)', 'set_user_grant(uuid,text,integer,timestamp with time zone,boolean,text)'] loop
    if to_regprocedure('public.' || f) is null then raise notice 'bos71: % not found, skipped', f; continue; end if;
    def := pg_get_functiondef(to_regprocedure('public.' || f));
    if position('bos71' in def) > 0 then continue; end if;
    if position(pat in def) = 0 then raise notice 'bos71: owner check not found in %, skipped', f; continue; end if;
    def := replace(def, pat, pat || E'\n  perform public._twofa_guard71(); -- bos71');
    execute def;
  end loop;
end $do$;

revoke all on function public._aal2() from public, anon, authenticated;
revoke all on function public._twofa_has_factor(uuid) from public, anon, authenticated;
revoke all on function public._twofa_guard71() from public, anon, authenticated;
revoke all on function public.twofa_policy() from public, anon;
revoke all on function public.twofa_status_report() from public, anon;
grant execute on function public.twofa_policy() to authenticated;
grant execute on function public.twofa_status_report() to authenticated;
