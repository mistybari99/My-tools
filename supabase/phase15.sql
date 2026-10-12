-- ============================================================
-- Phase 15 (W3): LIST ADD-RULES + OTHER QUEUE + SHARED LIST CONTROL (additive, safe to run twice, paste whole into the Supabase SQL editor)
--   Needs phase8..phase14 applied first (phase11 for no_hard_delete / code_immutable is expected; created here only if missing).
--   * option_lists (existing table, no second lists table): + created_by/at, retired_by/at/reason (retire = active=false, never delete)
--   * list_defs: one row per list: add_rule open | approval | owner, allow_other, active, locked, hidden, note
--   * option_add(): the ONLY way a non-owner joins a list; the rule is enforced here (open: at once; approval: option_requests row; owner: owner / list manager only)
--     similar-name check (case / spaces / Bangla digits, contains, one-letter slip) returns the similar options so the screen can say "already exists"
--   * option_requests (+ option_request_decide), list_other_entries (+ option_other_log / option_other_resolve: add as new / merge / reject; rows are never deleted)
--   * maker <> approver; the owner is exempt only while the rule owner_self_approve is ON (default ON)
--   * grant list_manage (owner delegates: decide requests / add to owner-rule lists, all lists) and list_managers (the same, one list only)
--   * retire / reactivate / edit through option_retire / option_reactivate / option_update (reason required for retire)
--   * rules owner_self_approve (on), list_search_min (8)
--   Nothing is deleted. Direct insert / update on option_lists stays owner only (policy option_lists_owner); locked lists refuse every change by trigger.
-- ============================================================

-- ---------- (0) helpers from phase11 (same text; created only so this file also works if phase11 was skipped) ----------
create or replace function public.no_hard_delete() returns trigger
language plpgsql set search_path = public as $$
begin raise exception 'nothing is deleted – retire instead'; end $$;

-- ---------- (1) option_lists: who/when created, who/when/why retired ----------
alter table public.option_lists add column if not exists created_by uuid;
alter table public.option_lists add column if not exists created_at timestamptz;
alter table public.option_lists add column if not exists retired_by uuid;
alter table public.option_lists add column if not exists retired_at timestamptz;
alter table public.option_lists add column if not exists retired_reason text;

-- ---------- (2) list_defs ----------
create table if not exists public.list_defs (
  list_code text primary key,
  add_rule text not null default 'approval' check (add_rule in ('open', 'approval', 'owner')),
  allow_other boolean not null default true,
  active boolean not null default true,
  locked boolean not null default false,
  hidden boolean not null default false,
  note text, title_bn text, title_en text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(), updated_by uuid
);
insert into public.list_defs (list_code) select distinct list_code from public.option_lists on conflict (list_code) do nothing;
alter table public.list_defs enable row level security;
drop policy if exists list_defs_read on public.list_defs;
create policy list_defs_read on public.list_defs for select to authenticated using (public.is_active());
revoke all on public.list_defs from anon, authenticated;
grant select on public.list_defs to authenticated;
drop trigger if exists audit_list_defs on public.list_defs;
create trigger audit_list_defs after insert or update on public.list_defs for each row execute function public.log_change('list_code');
drop trigger if exists list_defs_no_delete on public.list_defs;
create trigger list_defs_no_delete before delete on public.list_defs for each row execute function public.no_hard_delete();
drop trigger if exists list_defs_code_immutable on public.list_defs;
create trigger list_defs_code_immutable before update on public.list_defs for each row execute function public.code_immutable('list_code');

-- ---------- (3) rules and grants ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('owner_self_approve', 'lists', 'switch', 'true', null, null, null, null, 'মালিক নিজের অনুরোধ নিজে অনুমোদন করতে পারবেন', 'Owner নিজের request নিজে approve করতে পারবে', 'The owner may approve his / her own request',
   'বন্ধ করলে মালিকের অনুরোধও অন্য অনুমতিপ্রাপ্ত কেউ অনুমোদন করবেন', 'Off করলে owner এর request ও অন্য অনুমতিপ্রাপ্ত কেউ approve করবে', 'Off = even the owner''s own request must be decided by another person who holds list_manage', 210),
 ('list_search_min', 'lists', 'number', '8', null, null, 1, 200, 'তালিকায় এর বেশি অপশন থাকলে সার্চ বক্স দেখাবে', 'List এ এর বেশি option থাকলে search box দেখাবে', 'Show a search box when a list has more options than this', null, null, 'Used by the shared list control in forms', 211)
on conflict (key) do nothing;
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('other_pending_cap', 'lists', 'number', '50', null, null, 1, 10000, 'একজনের সর্বোচ্চ অপেক্ষমাণ "অন্যান্য" লেখা', 'একজনের maximum pending "Other" লেখা', 'Most pending "Other" write-ins one person may have', null, null, 'More are refused until the owner decides some', 212)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('list_manage', 'master', 62, 'তালিকা পরিচালনা: নতুন অপশনের অনুরোধ ও "অন্যান্য" তালিকা সিদ্ধান্ত, মালিক-নিয়মের তালিকায় যোগ', 'List পরিচালনা: নতুন option এর request ও "Other" queue সিদ্ধান্ত, owner-rule list এ যোগ', 'Manage lists: decide new-option requests and the Other queue, add to owner-rule lists', 'once', null)
on conflict (grant_code) do nothing;

-- one list only (the owner delegates a single list to a person)
create table if not exists public.list_managers (
  list_code text not null, user_id uuid not null references public.profiles(id),
  active boolean not null default true, granted_by uuid, granted_at timestamptz not null default now(),
  primary key (list_code, user_id)
);
alter table public.list_managers enable row level security;
drop policy if exists list_managers_read on public.list_managers;
create policy list_managers_read on public.list_managers for select to authenticated using (user_id = auth.uid() or public.is_owner());
revoke all on public.list_managers from anon, authenticated;
grant select on public.list_managers to authenticated;
drop trigger if exists audit_list_managers on public.list_managers;
create trigger audit_list_managers after insert or update on public.list_managers for each row execute function public.log_change('list_code,user_id');
drop trigger if exists list_managers_no_delete on public.list_managers;
create trigger list_managers_no_delete before delete on public.list_managers for each row execute function public.no_hard_delete();

-- may the caller manage this list (decide requests / Other queue, add to an owner-rule list)?
create or replace function public._list_mgr(p_list text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or (public.is_active() and (public.has_grant('list_manage')
    or exists (select 1 from public.list_managers m where m.list_code = p_list and m.user_id = auth.uid() and m.active)));
$$;

create or replace function public.list_manager_set(p_list text, p_user uuid, p_on boolean default true) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.list_defs where list_code = p_list) then raise exception 'unknown_list'; end if;
  if not exists (select 1 from public.profiles where id = p_user) then raise exception 'unknown user'; end if;
  insert into public.list_managers (list_code, user_id, active, granted_by) values (p_list, p_user, coalesce(p_on, true), auth.uid())
    on conflict (list_code, user_id) do update set active = coalesce(p_on, true), granted_by = auth.uid(), granted_at = now();
end $$;

-- ---------- (4) name helpers (similar-name check) ----------
create or replace function public._opt_norm(p text) returns text
language sql immutable set search_path = public as $$
  -- NFC, zero-width joiners and the danda removed, precomposed য় ড় ঢ় written as base + nukta, Bangla digits as ASCII digits
  select regexp_replace(translate(replace(replace(replace(replace(replace(replace(normalize(lower(coalesce(p, '')), NFC),
      U&'\200C', ''), U&'\200D', ''), U&'\09DF', U&'\09AF\09BC'), U&'\09DC', U&'\09A1\09BC'), U&'\09DD', U&'\09A2\09BC'), U&'\0964', ''),
      '০১২৩৪৫৬৭৮৯', '0123456789'), '[[:space:].,;:!?(){}/_&+-]+', '', 'g');
$$;
-- true when the two (already normalised) names differ by one inserted / removed / changed character (both at least 4 long)
create or replace function public._opt_lev1(a text, b text) returns boolean
language plpgsql immutable set search_path = public as $$
declare la int := length(coalesce(a, '')); lb int := length(coalesce(b, '')); i int := 1;
begin
  if abs(la - lb) > 1 or least(la, lb) < 4 then return false; end if;
  if a = b then return true; end if;
  while i <= least(la, lb) and substr(a, i, 1) = substr(b, i, 1) loop i := i + 1; end loop;
  if la = lb then return substr(a, i + 1) = substr(b, i + 1);
  elsif la > lb then return substr(a, i + 1) = substr(b, i);
  else return substr(a, i) = substr(b, i + 1); end if;
end $$;

-- similar existing options (active AND retired ones, so a retired value is not re-added by accident)
create or replace function public.option_similar(p_list text, p_bn text default null, p_en text default null, p_mix text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare names text[]; r record; rn text[]; k text; res jsonb := '[]'; hit text; a text; b text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if length(coalesce(p_bn, '')) > 120 or length(coalesce(p_en, '')) > 120 or length(coalesce(p_mix, '')) > 120 then raise exception 'name_too_long'; end if;
  names := array(select x from unnest(array[public._opt_norm(p_bn), public._opt_norm(p_en), public._opt_norm(p_mix)]) x where x <> '');
  if coalesce(array_length(names, 1), 0) = 0 then return res; end if;
  for r in select * from public.option_lists where list_code = p_list order by sort loop
    rn := array(select x from unnest(array[public._opt_norm(r.label_bn), public._opt_norm(r.label_en), public._opt_norm(r.label_mix), public._opt_norm(r.value_code)]) x where x <> '');
    hit := null;
    foreach a in array names loop
      foreach b in array rn loop
        if a = b then hit := 'same';
        elsif hit is distinct from 'same' and least(length(a), length(b)) >= 3 and (position(a in b) > 0 or position(b in a) > 0) then hit := coalesce(hit, 'contains');
        elsif hit is null and public._opt_lev1(a, b) then hit := 'close'; end if;
      end loop;
    end loop;
    if hit is not null then
      res := res || jsonb_build_array(jsonb_build_object('value_code', r.value_code, 'label_bn', r.label_bn, 'label_en', r.label_en, 'label_mix', r.label_mix, 'active', r.active, 'kind', hit));
    end if;
  end loop;
  -- same first, then contains, then close; at most 8
  return coalesce((select jsonb_agg(e) from (select e from jsonb_array_elements(res) e
      order by case e->>'kind' when 'same' then 0 when 'contains' then 1 else 2 end limit 8) q), '[]'::jsonb);
end $$;

-- ---------- (5) option_lists guard: audit fields, retire stamps, locked lists ----------
create or replace function public.option_lists_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare lk boolean;
begin
  if tg_op = 'INSERT' then
    insert into public.list_defs (list_code) values (new.list_code) on conflict (list_code) do nothing;
  end if;
  select locked into lk from public.list_defs where list_code = new.list_code;
  if tg_op = 'INSERT' then
    if coalesce(lk, false) then raise exception 'list_locked'; end if;
    new.created_by := coalesce(new.created_by, auth.uid()); new.created_at := coalesce(new.created_at, now());
    if not new.active then new.retired_at := coalesce(new.retired_at, now()); new.retired_by := coalesce(new.retired_by, auth.uid()); end if;
    return new;
  end if;
  if coalesce(lk, false) and (new.label_bn is distinct from old.label_bn or new.label_en is distinct from old.label_en or new.label_mix is distinct from old.label_mix
     or new.active is distinct from old.active or new.sort is distinct from old.sort or (new.extra - 'cat_no') is distinct from (old.extra - 'cat_no')) then
    raise exception 'list_locked';
  end if;
  if old.active and not new.active then
    new.retired_at := now(); new.retired_by := auth.uid();
  elsif not old.active and new.active then
    new.retired_at := null; new.retired_by := null; new.retired_reason := null;          -- the audit log keeps the history
  end if;
  return new;
end $$;
drop trigger if exists option_lists_guard on public.option_lists;
create trigger option_lists_guard before insert or update on public.option_lists for each row execute function public.option_lists_guard();

-- ---------- (6) requests and the Other queue ----------
create table if not exists public.option_requests (
  id uuid primary key default gen_random_uuid(),
  list_code text not null, label_bn text not null, label_en text, label_mix text, extra jsonb not null default '{}',
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  requested_by uuid not null default auth.uid(), requested_at timestamptz not null default now(),
  client_id uuid, similar_opts jsonb,
  decided_by uuid, decided_at timestamptz, decision_note text, resulting_value text
);
create unique index if not exists option_requests_client_uq on public.option_requests (requested_by, client_id) where client_id is not null;
create index if not exists option_requests_list_idx on public.option_requests (list_code, status);
create table if not exists public.list_other_entries (
  id uuid primary key default gen_random_uuid(),
  list_code text not null, text text not null check (length(text) between 1 and 200),
  entered_by uuid not null default auth.uid(), entered_at timestamptz not null default now(),
  form_code text, entry_id uuid, client_id uuid, ctx jsonb not null default '{}',
  status text not null default 'pending' check (status in ('pending', 'merged', 'added', 'rejected')),
  resolved_option text, resolved_by uuid, resolved_at timestamptz, resolved_note text
);
create unique index if not exists list_other_client_uq on public.list_other_entries (entered_by, client_id) where client_id is not null;
create index if not exists list_other_list_idx on public.list_other_entries (list_code, status);
alter table public.option_requests enable row level security;
alter table public.list_other_entries enable row level security;
drop policy if exists option_requests_read on public.option_requests;
create policy option_requests_read on public.option_requests for select to authenticated using (requested_by = auth.uid() or public._list_mgr(list_code));
drop policy if exists list_other_read on public.list_other_entries;
create policy list_other_read on public.list_other_entries for select to authenticated using (entered_by = auth.uid() or public._list_mgr(list_code));
revoke all on public.option_requests, public.list_other_entries from anon, authenticated;
grant select on public.option_requests, public.list_other_entries to authenticated;
drop trigger if exists audit_option_requests on public.option_requests;
create trigger audit_option_requests after insert or update on public.option_requests for each row execute function public.log_change('id');
drop trigger if exists audit_list_other on public.list_other_entries;
create trigger audit_list_other after insert or update on public.list_other_entries for each row execute function public.log_change('id');
drop trigger if exists option_requests_no_delete on public.option_requests;
create trigger option_requests_no_delete before delete on public.option_requests for each row execute function public.no_hard_delete();
drop trigger if exists list_other_no_delete on public.list_other_entries;
create trigger list_other_no_delete before delete on public.list_other_entries for each row execute function public.no_hard_delete();

-- ---------- (7) insert one option (internal): unique, immutable value_code ----------
create or replace function public._opt_insert(p_list text, p_bn text, p_en text, p_mix text, p_extra jsonb) returns text
language plpgsql security definer set search_path = public as $$
declare base text; vc text; n int := 1; mx int;
begin
  perform pg_advisory_xact_lock(hashtext('optlist:' || p_list));
  base := left(trim(both '_' from lower(regexp_replace(coalesce(nullif(btrim(p_en), ''), ''), '[^a-zA-Z0-9]+', '_', 'g'))), 24);
  if base is null or base = '' then base := 'o'; end if;
  vc := base;
  while vc = 'other' or exists (select 1 from public.option_lists where list_code = p_list and value_code = vc) loop n := n + 1; vc := base || '_' || n; end loop;   -- retired codes stay reserved
  select coalesce(max(sort), 0) + 1 into mx from public.option_lists where list_code = p_list;
  insert into public.option_lists (list_code, value_code, label_bn, label_en, label_mix, sort, active, extra, created_by, created_at)
    values (p_list, vc, btrim(p_bn), nullif(btrim(p_en), ''), nullif(btrim(p_mix), ''), mx, true, coalesce(p_extra, '{}'), auth.uid(), now());
  return vc;
end $$;

-- ---------- (8) option_add: THE add path; the list's rule is enforced here ----------
create or replace function public.option_add(p_list text, p_bn text, p_en text default null, p_mix text default null, p_extra jsonb default '{}',
                                             p_force boolean default false, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d public.list_defs; sim jsonb; same jsonb; bn text := nullif(btrim(p_bn), ''); mgr boolean; direct boolean; rq public.option_requests; vc text; rid uuid;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if bn is null or public._opt_norm(bn) = '' then raise exception 'name_required'; end if;
  if length(bn) > 120 or length(coalesce(p_en, '')) > 120 or length(coalesce(p_mix, '')) > 120 then raise exception 'name_too_long'; end if;
  if p_extra is not null and jsonb_typeof(p_extra) <> 'object' then raise exception 'bad_value'; end if;
  if not exists (select 1 from public.list_defs where list_code = p_list) and not exists (select 1 from public.option_lists where list_code = p_list) then raise exception 'unknown_list'; end if;
  insert into public.list_defs (list_code) values (p_list) on conflict (list_code) do nothing;
  select * into d from public.list_defs where list_code = p_list;
  if not d.active then raise exception 'list_inactive'; end if;
  if d.locked then raise exception 'list_locked'; end if;
  if p_client is not null then
    select * into rq from public.option_requests where requested_by = auth.uid() and client_id = p_client;
    if found then return jsonb_build_object('status', case rq.status when 'approved' then 'added' else 'requested' end, 'request_id', rq.id, 'value_code', rq.resulting_value, 'repeat', true); end if;
  end if;
  sim := public.option_similar(p_list, bn, p_en, p_mix);
  select e into same from jsonb_array_elements(sim) e where e->>'kind' = 'same' limit 1;
  if same is not null then return jsonb_build_object('status', 'exists', 'value_code', same->>'value_code', 'similar', sim); end if;
  if jsonb_array_length(sim) > 0 and not coalesce(p_force, false) then return jsonb_build_object('status', 'similar', 'similar', sim); end if;
  mgr := public._list_mgr(p_list);
  -- limits, cat_no and the like are business data: only the owner / a list manager may send them along (everybody else's extra is dropped)
  p_extra := case when mgr then coalesce(p_extra, '{}') - 'cat_no' else '{}'::jsonb end;
  direct := d.add_rule = 'open' or (d.add_rule = 'owner' and mgr) or (d.add_rule = 'approval' and public.is_owner() and public.rule_on('owner_self_approve'));
  if direct then
    vc := public._opt_insert(p_list, bn, p_en, p_mix, p_extra);
    return jsonb_build_object('status', 'added', 'value_code', vc);
  end if;
  if d.add_rule = 'owner' then raise exception 'owner_only'; end if;
  -- approval: a pending request (the same name already waiting is not filed twice)
  select * into rq from public.option_requests where list_code = p_list and status = 'pending' and public._opt_norm(label_bn) = public._opt_norm(bn) limit 1;
  if found then return jsonb_build_object('status', 'requested', 'request_id', rq.id, 'duplicate', true); end if;
  insert into public.option_requests (list_code, label_bn, label_en, label_mix, extra, client_id, similar_opts)
    values (p_list, bn, nullif(btrim(p_en), ''), nullif(btrim(p_mix), ''), coalesce(p_extra, '{}'), p_client, case when jsonb_array_length(sim) > 0 then sim end) returning id into rid;
  return jsonb_build_object('status', 'requested', 'request_id', rid);
end $$;

-- ---------- (9) decide a request: owner or list manager; maker <> approver (owner exempt only while owner_self_approve is on) ----------
create or replace function public.option_request_decide(p_id uuid, p_approve boolean, p_note text default null, p_bn text default null, p_en text default null, p_mix text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.option_requests; d public.list_defs; vc text; bn text; same text;
begin
  select * into r from public.option_requests where id = p_id;
  if not found then raise exception 'request_not_found'; end if;
  perform pg_advisory_xact_lock(hashtext('optlist:' || r.list_code));
  select * into r from public.option_requests where id = p_id for update;
  if not public._list_mgr(r.list_code) then raise exception 'not allowed'; end if;
  if r.status <> 'pending' then return jsonb_build_object('status', r.status, 'value_code', r.resulting_value, 'repeat', true); end if;
  if r.requested_by = auth.uid() and not (public.is_owner() and public.rule_on('owner_self_approve')) then raise exception 'self_approval'; end if;
  if coalesce(p_approve, false) then
    select * into d from public.list_defs where list_code = r.list_code;
    if d.locked then raise exception 'list_locked'; end if;
    if not d.active then raise exception 'list_inactive'; end if;
    bn := coalesce(nullif(btrim(p_bn), ''), r.label_bn);
    select e->>'value_code' into same from jsonb_array_elements(public.option_similar(r.list_code, bn, coalesce(p_en, r.label_en), coalesce(p_mix, r.label_mix))) e where e->>'kind' = 'same' and (e->>'active')::boolean limit 1;
    vc := coalesce(same, public._opt_insert(r.list_code, bn, coalesce(nullif(btrim(p_en), ''), r.label_en), coalesce(nullif(btrim(p_mix), ''), r.label_mix), r.extra));
    update public.option_requests set status = 'approved', decided_by = auth.uid(), decided_at = now(), decision_note = left(p_note, 300), resulting_value = vc where id = p_id;
    return jsonb_build_object('status', 'approved', 'value_code', vc);
  end if;
  update public.option_requests set status = 'rejected', decided_by = auth.uid(), decided_at = now(), decision_note = left(p_note, 300) where id = p_id;
  return jsonb_build_object('status', 'rejected');
end $$;

-- ---------- (10) Other queue ----------
create or replace function public.option_other_log(p_list text, p_text text, p_ctx jsonb default '{}') returns jsonb
language plpgsql security definer set search_path = public as $$
declare d public.list_defs; tx text := nullif(btrim(p_text), ''); ex record; rid uuid; cl uuid; ent uuid; cap int; c2 jsonb := '{}'; k text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if tx is null or public._opt_norm(tx) = '' then raise exception 'name_required'; end if;
  if length(tx) > 200 then raise exception 'name_too_long'; end if;
  select * into d from public.list_defs where list_code = p_list;
  if not found then raise exception 'unknown_list'; end if;
  if not d.allow_other or not d.active then raise exception 'other_not_allowed'; end if;
  p_ctx := case when jsonb_typeof(coalesce(p_ctx, '{}')) = 'object' then coalesce(p_ctx, '{}') else '{}'::jsonb end;
  if length(p_ctx::text) > 2048 then raise exception 'ctx_too_large'; end if;
  begin cl := nullif(p_ctx->>'client_id', '')::uuid; exception when others then cl := null; end;
  begin ent := nullif(p_ctx->>'entry_id', '')::uuid; exception when others then ent := null; end;
  foreach k in array array['form_code', 'item_id', 'field', 'supplier_id'] loop       -- only these keys are kept, each a short string
    if p_ctx ? k and jsonb_typeof(p_ctx->k) = 'string' then c2 := c2 || jsonb_build_object(k, left(p_ctx->>k, 60)); end if;
  end loop;
  if cl is not null then
    select id, status into ex from public.list_other_entries where entered_by = auth.uid() and client_id = cl;
    if found then return jsonb_build_object('status', ex.status, 'id', ex.id, 'repeat', true); end if;
  end if;
  -- a text that is already a listed option is not queued: the screen uses the option
  select o.value_code into ex from public.option_lists o where o.list_code = p_list and o.active
    and public._opt_norm(tx) in (public._opt_norm(o.label_bn), public._opt_norm(o.label_en), public._opt_norm(o.label_mix)) limit 1;
  if found then return jsonb_build_object('status', 'exists', 'value_code', ex.value_code); end if;
  cap := coalesce(public.rule_num('other_pending_cap'), 50)::int;
  if (select count(*) from public.list_other_entries where entered_by = auth.uid() and status = 'pending') >= cap then raise exception 'other_queue_full'; end if;
  insert into public.list_other_entries (list_code, text, form_code, entry_id, client_id, ctx)
    values (p_list, tx, left(p_ctx->>'form_code', 20), ent, cl, c2) returning id into rid;
  return jsonb_build_object('status', 'pending', 'id', rid);
end $$;

-- p_action: 'add' (becomes a new option), 'merge' (joins p_value, an existing option), 'reject'. Equal texts waiting in the same list are decided together.
drop function if exists public.option_other_resolve(uuid, text, text, text, text, text, text);
create or replace function public.option_other_resolve(p_id uuid, p_action text, p_value text default null, p_bn text default null, p_en text default null, p_mix text default null, p_note text default null, p_force boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.list_other_entries; d public.list_defs; vc text; bn text; ownok boolean; st text; n int; o public.option_lists; sim jsonb; same jsonb;
begin
  select * into r from public.list_other_entries where id = p_id;
  if not found then raise exception 'other_not_found'; end if;
  perform pg_advisory_xact_lock(hashtext('optlist:' || r.list_code));          -- one lock per list, always taken first: no deadlock between two deciders
  select * into r from public.list_other_entries where id = p_id for update;
  if not public._list_mgr(r.list_code) then raise exception 'not allowed'; end if;
  if r.status <> 'pending' then return jsonb_build_object('status', r.status, 'value_code', r.resolved_option, 'repeat', true); end if;
  ownok := public.is_owner() and public.rule_on('owner_self_approve');
  if r.entered_by = auth.uid() and not ownok then raise exception 'self_approval'; end if;
  if p_action = 'reject' then
    st := 'rejected'; vc := null;
  elsif p_action = 'merge' then
    select * into o from public.option_lists where list_code = r.list_code and value_code = p_value;
    if not found then raise exception 'bad_option'; end if;
    if not o.active then raise exception 'option_inactive'; end if;
    st := 'merged'; vc := p_value;
  elsif p_action = 'add' then
    select * into d from public.list_defs where list_code = r.list_code;
    if d.locked then raise exception 'list_locked'; end if;
    if not d.active then raise exception 'list_inactive'; end if;
    bn := coalesce(nullif(btrim(p_bn), ''), r.text);
    if length(bn) > 120 or length(coalesce(p_en, '')) > 120 or length(coalesce(p_mix, '')) > 120 then raise exception 'name_too_long'; end if;
    sim := public.option_similar(r.list_code, bn, p_en, p_mix);
    select e into same from jsonb_array_elements(sim) e where e->>'kind' = 'same' limit 1;
    if same is not null then return jsonb_build_object('status', 'exists', 'value_code', same->>'value_code', 'similar', sim); end if;
    if jsonb_array_length(sim) > 0 and not coalesce(p_force, false) then return jsonb_build_object('status', 'similar', 'similar', sim); end if;
    vc := public._opt_insert(r.list_code, bn, nullif(btrim(p_en), ''), nullif(btrim(p_mix), ''), '{}');
    st := 'added';
  else raise exception 'bad_value'; end if;
  update public.list_other_entries set status = st, resolved_option = vc, resolved_by = auth.uid(), resolved_at = now(), resolved_note = left(p_note, 300)
    where id in (select id from public.list_other_entries where list_code = r.list_code and status = 'pending' and public._opt_norm(text) = public._opt_norm(r.text)
                   and (entered_by <> auth.uid() or ownok or id = p_id) order by id for update);
  get diagnostics n = row_count;
  return jsonb_build_object('status', st, 'value_code', vc, 'resolved', n);
end $$;

-- ---------- (11) edit / retire / reactivate (owner or list manager); retire needs a reason; nothing is deleted ----------
create or replace function public.option_retire(p_list text, p_value text, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.option_lists;
begin
  if not public._list_mgr(p_list) then raise exception 'not allowed'; end if;
  if nullif(btrim(p_reason), '') is null then raise exception 'reason_required'; end if;
  select * into o from public.option_lists where list_code = p_list and value_code = p_value for update;
  if not found then raise exception 'bad_option'; end if;
  if not o.active then return jsonb_build_object('status', 'retired', 'repeat', true); end if;
  update public.option_lists set active = false, retired_reason = left(btrim(p_reason), 200) where list_code = p_list and value_code = p_value;
  return jsonb_build_object('status', 'retired');
end $$;
create or replace function public.option_reactivate(p_list text, p_value text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public._list_mgr(p_list) then raise exception 'not allowed'; end if;
  update public.option_lists set active = true where list_code = p_list and value_code = p_value;
  if not found then raise exception 'bad_option'; end if;
  return jsonb_build_object('status', 'active');
end $$;
drop function if exists public.option_update(text, text, text, text, text);
create or replace function public.option_update(p_list text, p_value text, p_bn text, p_en text default null, p_mix text default null, p_extra jsonb default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public._list_mgr(p_list) then raise exception 'not allowed'; end if;
  if nullif(btrim(p_bn), '') is null then raise exception 'name_required'; end if;
  if length(p_bn) > 120 or length(coalesce(p_en, '')) > 120 or length(coalesce(p_mix, '')) > 120 then raise exception 'name_too_long'; end if;
  if p_extra is not null and (jsonb_typeof(p_extra) <> 'object' or not public.is_owner()) then raise exception 'not allowed'; end if;   -- limits and the like: owner only
  update public.option_lists set label_bn = btrim(p_bn), label_en = nullif(btrim(p_en), ''), label_mix = nullif(btrim(p_mix), ''),
      extra = case when p_extra is null then extra else jsonb_strip_nulls((extra - 'limit_month') || (p_extra - 'cat_no')) end
    where list_code = p_list and value_code = p_value;
  if not found then raise exception 'bad_option'; end if;
  return jsonb_build_object('status', 'saved');
end $$;
create or replace function public.option_reorder(p_list text, p_codes text[]) returns jsonb
language plpgsql security definer set search_path = public as $$
declare i int := 0; c text;
begin
  if not public._list_mgr(p_list) then raise exception 'not allowed'; end if;
  foreach c in array coalesce(p_codes, '{}') loop
    i := i + 1;
    update public.option_lists set sort = i where list_code = p_list and value_code = c;
  end loop;
  return jsonb_build_object('status', 'saved', 'n', i);
end $$;

-- owner edits the list's own settings (rule, Other on/off, active, locked, hidden, note, titles)
create or replace function public.list_def_set(p_list text, p_patch jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k text; v jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then raise exception 'bad_value'; end if;
  if not exists (select 1 from public.option_lists where list_code = p_list) and not exists (select 1 from public.list_defs where list_code = p_list) then raise exception 'unknown_list'; end if;
  insert into public.list_defs (list_code) values (p_list) on conflict (list_code) do nothing;
  for k, v in select * from jsonb_each(p_patch) loop
    if k = 'add_rule' then
      if jsonb_typeof(v) <> 'string' or (v #>> '{}') not in ('open', 'approval', 'owner') then raise exception 'bad_value'; end if;
      update public.list_defs set add_rule = v #>> '{}' where list_code = p_list;
    elsif k in ('allow_other', 'active', 'locked', 'hidden') then
      if jsonb_typeof(v) <> 'boolean' then raise exception 'bad_value'; end if;
      execute format('update public.list_defs set %I = $1 where list_code = $2', k) using (v #>> '{}')::boolean, p_list;
    elsif k in ('note', 'title_bn', 'title_en') then
      if jsonb_typeof(v) not in ('string', 'null') then raise exception 'bad_value'; end if;
      execute format('update public.list_defs set %I = left(nullif(btrim($1), ''''), 200) where list_code = $2', k) using v #>> '{}', p_list;
    else raise exception 'bad_value'; end if;
  end loop;
  update public.list_defs set updated_at = now(), updated_by = auth.uid() where list_code = p_list;
  return (select to_jsonb(x) from public.list_defs x where list_code = p_list);
end $$;

-- ---------- (12) counts for the Needs-you badge (only for people who may decide) ----------
create or replace function public.list_queue_counts() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare res jsonb := '{"requests":0,"other":0,"lists":{}}'; r record; rq int := 0; ot int := 0;
begin
  if not public.is_active() then return res; end if;
  for r in select d.list_code,
      (select count(*) from public.option_requests q where q.list_code = d.list_code and q.status = 'pending') as rq,
      (select count(*) from public.list_other_entries o where o.list_code = d.list_code and o.status = 'pending') as ot
    from public.list_defs d loop
    if (r.rq > 0 or r.ot > 0) and public._list_mgr(r.list_code) then
      rq := rq + r.rq; ot := ot + r.ot;
      res := jsonb_set(res, array['lists', r.list_code], jsonb_build_object('requests', r.rq, 'other', r.ot));
    end if;
  end loop;
  return jsonb_set(jsonb_set(res, '{requests}', to_jsonb(rq)), '{other}', to_jsonb(ot));
end $$;

-- ---------- (13) privileges: authenticated only; internal helpers not callable from outside ----------
revoke all on function public._opt_insert(text, text, text, text, jsonb), public.option_lists_guard() from public, anon, authenticated;
revoke all on function public.option_add(text, text, text, text, jsonb, boolean, uuid), public.option_request_decide(uuid, boolean, text, text, text, text),
  public.option_other_log(text, text, jsonb), public.option_other_resolve(uuid, text, text, text, text, text, text, boolean), public.option_retire(text, text, text),
  public.option_reactivate(text, text), public.option_update(text, text, text, text, text, jsonb), public.option_reorder(text, text[]), public.list_def_set(text, jsonb),
  public.list_manager_set(text, uuid, boolean), public.list_queue_counts(), public.option_similar(text, text, text, text), public._list_mgr(text),
  public._opt_norm(text), public._opt_lev1(text, text) from public, anon;
grant execute on function public.option_add(text, text, text, text, jsonb, boolean, uuid), public.option_request_decide(uuid, boolean, text, text, text, text),
  public.option_other_log(text, text, jsonb), public.option_other_resolve(uuid, text, text, text, text, text, text, boolean), public.option_retire(text, text, text),
  public.option_reactivate(text, text), public.option_update(text, text, text, text, text, jsonb), public.option_reorder(text, text[]), public.list_def_set(text, jsonb),
  public.list_manager_set(text, uuid, boolean), public.list_queue_counts(), public.option_similar(text, text, text, text), public._list_mgr(text),
  public._opt_norm(text), public._opt_lev1(text, text) to authenticated;
