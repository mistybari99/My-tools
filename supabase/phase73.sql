-- ============================================================
-- Phase 73 (bos73) - STEP C-0: recipe master. Artisan register, recipe version history + approval, recipe steps, artisan-wise recipe book.
--   Needs phase8 ... phase71 (recipes/recipe_lines from phase19). Additive; paste-twice safe. Old phases are NOT edited.
--   C0.1 artisans        : the register. The NAME is stored ONLY in artisans.name (column not readable by browsers; only artisan_register() for the owner /
--                          artisan_manage). Everywhere else (recipe book, history, audit log, exceptions) only the artisan id (code 'artisan-N') + post (পদ).
--                          Ids are never reused (identity + no delete); a retired artisan stays in the register and on old recipes.
--   C0.2 recipes.artisan_id : one main artisan per recipe version (blank for every existing recipe - nothing is guessed). recipe_unassigned() = "কারিগর নির্ধারিত নয়".
--   C0.3 recipe_versions : append-only history of every change (who, when, previous values, new values). Approval: recipes.approved_at/by; the person who
--                          last changed a version may NOT approve it (rule recipe_self_approve, default OFF); approver = grant recipe_approve (role recipe_approver).
--                          Rule recipe_approval_required: off (default = today's behaviour) | warn (yellow line) | on (no cost / no production before approval).
--   C0.4 recipe_steps    : ordered method steps (name, free text, minutes, people, fuel, flame note, equipment, QC note, responsible post). minutes x people = a
--                          SUGGESTED labour-hours figure (recipe_labour_suggest) - it never enters any cost.
--   C0.5 recipe_book     : artisan-wise recipe book (no cost unless asked AND the caller has the cost right).
--   C0.6 grant recipe_view (owner + role recipe_approver), rule artisan_self_view (default OFF): a linked artisan sees only his own book. Every view is audited.
--   Functions re-created (tag bos73): recipe_save, recipe_copy (history + artisan + steps carried), recipe_cost, production_post (approval gate only).
-- ============================================================

-- ---------- settings, grants, role ----------
insert into public.rules (key, module, kind, default_value, choices, min_value, max_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('recipe_approval_required', 'stock', 'choice', '"off"', '["off","warn","on"]', null, null,
  'রেসিপি অনুমোদনের আগে খরচ/উৎপাদন: বন্ধ / হলুদ সতর্কতা / আটকানো', 'Recipe approval এর আগে cost/production: off / warn / on', 'Cost and production before a recipe is approved: off, yellow warning, or refuse',
  'off = today''s behaviour (no approval needed). warn = yellow line for the owner. on = recipe_cost and production_post refuse an unapproved recipe (form 05-3: no costing before approval).', 720),
 ('recipe_self_approve', 'stock', 'switch', 'false', null, null, null,
  'যে রেসিপি বদলেছে সে-ই অনুমোদন করতে পারবে', 'যে recipe বদলেছে সে-ই approve করতে পারবে', 'The person who changed a recipe may also approve it',
  'Off (default) = the last changer can never approve; a second person with the recipe_approve grant is needed.', 721),
 ('artisan_self_view', 'stock', 'switch', 'false', null, null, null,
  'কারিগর শুধু নিজের রেসিপি দেখতে পারবে', 'Artisan শুধু নিজের recipe দেখতে পারবে', 'An artisan sees only his own recipes (recipe book)',
  'Off (default) = only holders of recipe_view see the recipe books. On = a login linked to an artisan in the register also sees that artisan''s own book, nobody else''s.', 722)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('recipe_view', 'master', 70, 'কারিগর-ভিত্তিক রেসিপি বই দেখা', 'Artisan-wise recipe book দেখা', 'View the artisan-wise recipe books', 'window', null),
 ('recipe_approve', 'master', 71, 'রেসিপি অনুমোদন', 'Recipe approve', 'Approve a recipe version', 'window', null),
 ('artisan_manage', 'master', 72, 'কারিগর রেজিস্টারে নাম ও তথ্য লেখা', 'Artisan register এ নাম ও তথ্য লেখা', 'Write names and details in the artisan register', 'window', null)
on conflict (grant_code) do nothing;

insert into public.roles (code, name_bn, name_mix, name_en, sort) values
 ('recipe_approver', 'রেসিপি অনুমোদনকারী', 'Recipe অনুমোদনকারী', 'Recipe approver', 95)
on conflict (code) do nothing;
insert into public.rule_grants (grant_code, role_code) values ('recipe_view', 'recipe_approver'), ('recipe_approve', 'recipe_approver')
on conflict do nothing;

-- ---------- C0.1 artisan register ----------
create table if not exists public.artisans (
  id int generated always as identity primary key,                 -- never reused
  post text not null check (post in ('karigor', 'chef', 'asst_karigor', 'other')),             -- কারিগর / শেফ / সহকারী কারিগর / অন্য
  post_other text,
  name text not null check (length(btrim(name)) between 2 and 80),   -- typed by the owner; lives ONLY here
  work_type text not null check (work_type in ('mishti', 'doi', 'jilapi', 'cake', 'bakery', 'other')),   -- মিষ্টি / দই / জিলাপি / কেক / বেকারি / অন্য
  work_other text,
  location_id int references public.locations(id),
  user_id uuid references public.profiles(id),                     -- optional: the login of this artisan (for artisan_self_view)
  active boolean not null default true,
  retired_at timestamptz, retired_by uuid, retired_reason text,
  note text,
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(),
  check (post <> 'other' or length(btrim(coalesce(post_other, ''))) > 0),
  check (work_type <> 'other' or length(btrim(coalesce(work_other, ''))) > 0)
);
create unique index if not exists artisans_user_one on public.artisans (user_id) where user_id is not null;
alter table public.artisans add column if not exists code text generated always as ('artisan-' || id::text) stored;

drop trigger if exists artisans_no_delete on public.artisans;
create trigger artisans_no_delete before delete on public.artisans for each row execute function public.no_hard_delete();

-- audit WITHOUT the name: the audit log must not carry the name either
create or replace function public._artisan_audit() returns trigger language plpgsql security definer set search_path = public as $$
declare o jsonb; n jsonb; k text; oldd jsonb := '{}'; newd jsonb := '{}'; sid text;
begin
  select staff_id into sid from public.profiles where id = auth.uid();
  n := to_jsonb(new) - 'name';
  if tg_op = 'INSERT' then
    insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail) values (auth.uid(), sid, 'insert', 'artisans', new.id::text, jsonb_build_object('new', n));
    return new;
  end if;
  o := to_jsonb(old) - 'name';
  for k in select jsonb_object_keys(n) loop
    if n->k is distinct from o->k then oldd := oldd || jsonb_build_object(k, o->k); newd := newd || jsonb_build_object(k, n->k); end if;
  end loop;
  if new.name is distinct from old.name then newd := newd || jsonb_build_object('name_changed', true); end if;
  if newd = '{}'::jsonb then return new; end if;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail) values (auth.uid(), sid, 'update', 'artisans', new.id::text, jsonb_build_object('old', oldd, 'new', newd));
  return new;
end $$;
drop trigger if exists audit_artisans on public.artisans;
create trigger audit_artisans after insert or update on public.artisans for each row execute function public._artisan_audit();

-- ---------- recipe columns ----------
alter table public.recipes add column if not exists artisan_id int references public.artisans(id);
alter table public.recipes add column if not exists approved_by uuid;
alter table public.recipes add column if not exists approved_at timestamptz;
alter table public.recipes add column if not exists approve_note text;
alter table public.recipes add column if not exists changed_by uuid;
alter table public.recipes add column if not exists changed_at timestamptz;
alter table public.recipes add column if not exists form_ref text;           -- the printed 05-3 card number: a REFERENCE only, the detail lives here
create index if not exists recipes_artisan on public.recipes (artisan_id) where artisan_id is not null;

-- ---------- C0.4 steps, C0.3 history ----------
create table if not exists public.recipe_steps (
  id bigserial primary key,
  recipe_id uuid not null references public.recipes(id),
  step_no int not null check (step_no >= 1),
  step_name text not null check (length(btrim(step_name)) between 1 and 120),
  description text,
  minutes numeric check (minutes is null or (minutes >= 0 and minutes <= 100000)),            -- null = blank = "অসম্পূর্ণ"
  people int check (people is null or (people >= 0 and people <= 1000)),
  fuel text check (fuel is null or fuel in ('gas', 'electric', 'other')),
  fuel_other text,
  flame_note text,
  equipment text,
  qc_note text,
  resp_post text check (resp_post is null or resp_post in ('karigor', 'chef', 'asst_karigor', 'other')),
  resp_other text,
  active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now(),
  check (fuel is distinct from 'other' or length(btrim(coalesce(fuel_other, ''))) > 0)
);
create unique index if not exists recipe_steps_one on public.recipe_steps (recipe_id, step_no) where active;

create table if not exists public.recipe_versions (
  id bigserial primary key,
  recipe_id uuid not null references public.recipes(id),
  version int not null,
  seq int not null,
  kind text not null check (kind in ('created', 'edited', 'steps_edited', 'artisan_set', 'approved', 'activated', 'retired')),
  changed_by uuid, changed_at timestamptz not null default now(),
  summary text,
  prev jsonb,            -- the values BEFORE this change (kept for ever)
  snap jsonb,            -- the values after it
  client_id uuid unique,
  unique (recipe_id, seq)
);
create or replace function public._rv_immutable() returns trigger language plpgsql as $$ begin raise exception 'append_only'; end $$;
drop trigger if exists recipe_versions_immutable on public.recipe_versions;
create trigger recipe_versions_immutable before update or delete on public.recipe_versions for each row execute function public._rv_immutable();
drop trigger if exists recipe_steps_no_delete on public.recipe_steps;
create trigger recipe_steps_no_delete before delete on public.recipe_steps for each row execute function public.no_hard_delete();
drop trigger if exists audit_recipe_steps on public.recipe_steps;
create trigger audit_recipe_steps after insert or update on public.recipe_steps for each row execute function public.log_change('id');

-- an approved version never changes (yield, lines, steps); a change is a NEW version
create or replace function public._recipe_approved_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare rid uuid; ap timestamptz;
begin
  if tg_table_name = 'recipes' then
    if old.approved_at is not null and (new.item_id is distinct from old.item_id or new.version is distinct from old.version
       or new.yield_qty is distinct from old.yield_qty or new.yield_unit is distinct from old.yield_unit) then raise exception 'recipe_approved'; end if;
    if old.approved_at is not null and (new.approved_at is distinct from old.approved_at or new.approved_by is distinct from old.approved_by) then raise exception 'recipe_approved'; end if;
    return new;
  end if;
  rid := case when tg_op = 'DELETE' then old.recipe_id else new.recipe_id end;
  select approved_at into ap from public.recipes where id = rid;
  if ap is not null then raise exception 'recipe_approved'; end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;
drop trigger if exists recipes_approved_guard on public.recipes;
create trigger recipes_approved_guard before update on public.recipes for each row execute function public._recipe_approved_guard();
drop trigger if exists recipe_lines_approved_guard on public.recipe_lines;
create trigger recipe_lines_approved_guard before insert or update or delete on public.recipe_lines for each row execute function public._recipe_approved_guard();
drop trigger if exists recipe_steps_approved_guard on public.recipe_steps;
create trigger recipe_steps_approved_guard before insert or update on public.recipe_steps for each row execute function public._recipe_approved_guard();

-- ---------- RLS ----------
alter table public.artisans enable row level security;
alter table public.recipe_steps enable row level security;
alter table public.recipe_versions enable row level security;
drop policy if exists artisans_read on public.artisans;
create policy artisans_read on public.artisans for select to authenticated using (public._recipe_read() or public.has_grant('recipe_view') or public.has_grant('artisan_manage'));
drop policy if exists recipe_steps_read on public.recipe_steps;
create policy recipe_steps_read on public.recipe_steps for select to authenticated using (public._recipe_read());
drop policy if exists recipe_versions_read on public.recipe_versions;
create policy recipe_versions_read on public.recipe_versions for select to authenticated using (public._recipe_read());
revoke all on public.artisans, public.recipe_steps, public.recipe_versions from anon, authenticated;
grant select (id, code, post, post_other, work_type, work_other, location_id, user_id, active, retired_at, retired_reason, note, created_at) on public.artisans to authenticated;      -- NOT name
grant select on public.recipe_steps, public.recipe_versions to authenticated;
revoke all on sequence public.recipe_steps_id_seq, public.recipe_versions_id_seq from anon, authenticated;

-- ---------- helpers ----------
-- the read right for the recipe tables: phase19 definition + the two new grants (an approver must be able to read what he approves)
create or replace function public._recipe_read() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('recipe_manage') or public.has_grant('stock_production') or public.has_grant('stock_issue')
    or public.has_grant('recipe_view') or public.has_grant('recipe_approve')      -- bos73
    or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code in ('recipe_manage', 'stock_production', 'stock_issue') and (g.valid_until is null or g.valid_until > now())));
$$;
create or replace function public._artisan_mgr() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('artisan_manage'));
$$;
create or replace function public._artisan_of_user() returns int language sql stable security definer set search_path = public as $$
  select a.id from public.artisans a where a.user_id = auth.uid() and a.active limit 1;
$$;
create or replace function public._recipe_view_ok(p_artisan int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.has_grant('recipe_view') or (public.rule_on('artisan_self_view') and p_artisan is not null
    and exists (select 1 from public.artisans a where a.id = p_artisan and a.user_id = auth.uid())));
$$;
create or replace function public._audit_view(p_table text, p_rec text, p_detail jsonb) returns void language plpgsql security definer set search_path = public as $$
declare sid text;
begin
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail) values (auth.uid(), sid, 'view', p_table, p_rec, p_detail);
end $$;

create or replace function public._recipe_snapshot(p_recipe uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('item_id', r.item_id, 'version', r.version, 'yield_qty', r.yield_qty, 'yield_unit', r.yield_unit, 'active', r.active, 'note', r.note,
    'artisan_id', r.artisan_id, 'form_ref', r.form_ref, 'approved_at', r.approved_at,
    'lines', coalesce((select jsonb_agg(jsonb_build_object('ingredient_item_id', l.ingredient_item_id, 'qty', l.qty, 'unit', l.unit, 'waste_pct', l.waste_pct, 'note', l.note) order by l.sort, l.id)
                       from public.recipe_lines l where l.recipe_id = r.id and l.active), '[]'::jsonb),
    'steps', coalesce((select jsonb_agg(jsonb_build_object('step_no', s.step_no, 'step_name', s.step_name, 'description', s.description, 'minutes', s.minutes, 'people', s.people,
                       'fuel', s.fuel, 'fuel_other', s.fuel_other, 'flame_note', s.flame_note, 'equipment', s.equipment, 'qc_note', s.qc_note, 'resp_post', s.resp_post, 'resp_other', s.resp_other) order by s.step_no)
                       from public.recipe_steps s where s.recipe_id = r.id and s.active), '[]'::jsonb))
  from public.recipes r where r.id = p_recipe;
$$;

create or replace function public._rv_log(p_recipe uuid, p_kind text, p_prev jsonb, p_summary text, p_client uuid default null) returns void
language plpgsql security definer set search_path = public as $$
declare r public.recipes;
begin
  select * into r from public.recipes where id = p_recipe;
  insert into public.recipe_versions (recipe_id, version, seq, kind, changed_by, changed_at, summary, prev, snap, client_id)
    values (p_recipe, r.version, coalesce((select max(seq) from public.recipe_versions where recipe_id = p_recipe), 0) + 1, p_kind, auth.uid(), now(), left(p_summary, 300), p_prev, public._recipe_snapshot(p_recipe), p_client);
end $$;

-- ---------- C0.1 artisan writes / reads ----------
-- create (p_id null) or edit. The name is typed by the owner (or a person the owner gave artisan_manage). Returns id + code only.
create or replace function public.artisan_save(p_id int, p_post text, p_post_other text, p_name text, p_work_type text, p_work_other text, p_location int default null, p_user uuid default null, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.artisans; rid int;
begin
  if not public._artisan_mgr() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_post not in ('karigor', 'chef', 'asst_karigor', 'other') then raise exception 'bad_post'; end if;
  if p_work_type not in ('mishti', 'doi', 'jilapi', 'cake', 'bakery', 'other') then raise exception 'bad_work_type'; end if;
  if p_post = 'other' and length(btrim(coalesce(p_post_other, ''))) = 0 then raise exception 'post_other_needed'; end if;
  if p_work_type = 'other' and length(btrim(coalesce(p_work_other, ''))) = 0 then raise exception 'work_other_needed'; end if;
  if p_name is null or length(btrim(p_name)) < 2 or length(btrim(p_name)) > 80 then raise exception 'name_needed'; end if;
  if p_location is not null and not exists (select 1 from public.locations where id = p_location) then raise exception 'unknown location'; end if;
  if p_user is not null and not exists (select 1 from public.profiles where id = p_user) then raise exception 'unknown user'; end if;
  if p_id is null then
    if p_client is not null then
      select * into a from public.artisans where client_id = p_client;
      if found then
        if a.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
        return jsonb_build_object('dup', true, 'id', a.id, 'code', a.code);
      end if;
    end if;
    insert into public.artisans (post, post_other, name, work_type, work_other, location_id, user_id, note, client_id, created_by)
      values (p_post, case when p_post = 'other' then left(btrim(p_post_other), 60) end, btrim(p_name), p_work_type, case when p_work_type = 'other' then left(btrim(p_work_other), 60) end,
              p_location, p_user, left(p_note, 300), p_client, auth.uid()) returning * into a;
  else
    update public.artisans set post = p_post, post_other = case when p_post = 'other' then left(btrim(p_post_other), 60) end, name = btrim(p_name), work_type = p_work_type,
      work_other = case when p_work_type = 'other' then left(btrim(p_work_other), 60) end, location_id = p_location, user_id = p_user, note = left(p_note, 300)
      where id = p_id returning * into a;
    if not found then raise exception 'artisan_not_found'; end if;
  end if;
  return jsonb_build_object('id', a.id, 'code', a.code);
end $$;

create or replace function public.artisan_set_active(p_id int, p_active boolean, p_reason text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public._artisan_mgr() then raise exception 'not allowed'; end if;
  if p_active is null then raise exception 'bad_value'; end if;
  if not p_active and length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'note_required'; end if;
  update public.artisans set active = p_active, retired_at = case when p_active then null else now() end, retired_by = case when p_active then null else auth.uid() end,
    retired_reason = case when p_active then null else left(btrim(p_reason), 200) end where id = p_id;
  if not found then raise exception 'artisan_not_found'; end if;
end $$;

-- the register with names: owner / artisan_manage ONLY (audited as a view)
create or replace function public.artisan_register() returns jsonb language plpgsql security definer set search_path = public as $$
declare out jsonb;
begin
  if not public._artisan_mgr() then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'name', a.name, 'post', a.post, 'post_other', a.post_other, 'work_type', a.work_type, 'work_other', a.work_other,
    'location_id', a.location_id, 'user_id', a.user_id, 'active', a.active, 'retired_at', a.retired_at, 'retired_reason', a.retired_reason, 'note', a.note,
    'recipes', (select count(*) from public.recipes r where r.artisan_id = a.id and r.active)) order by a.id), '[]'::jsonb) into out from public.artisans a;
  perform public._audit_view('artisan_register', null, jsonb_build_object('n', jsonb_array_length(out)));
  return out;
end $$;

-- the list for pickers: id + code + post + work type + place. NEVER the name.
create or replace function public.artisan_list(p_include_retired boolean default false) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not (public._recipe_read() or public.has_grant('recipe_view') or public._artisan_mgr()) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'post', a.post, 'post_other', a.post_other, 'work_type', a.work_type, 'work_other', a.work_other,
    'location_id', a.location_id, 'active', a.active) order by a.id) from public.artisans a where p_include_retired or a.active), '[]'::jsonb);
end $$;

-- ---------- C0.2 artisan on a recipe version ----------
create or replace function public._recipe_set_artisan(p_recipe uuid, p_artisan int, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.recipes; prev jsonb;
begin
  select * into r from public.recipes where id = p_recipe for update;
  if not found then raise exception 'recipe_not_found'; end if;
  if p_artisan is not null and not exists (select 1 from public.artisans where id = p_artisan and active) then raise exception 'artisan_not_found'; end if;
  if r.artisan_id is not distinct from p_artisan then return; end if;
  prev := public._recipe_snapshot(p_recipe);
  update public.recipes set artisan_id = p_artisan where id = p_recipe;
  perform public._rv_log(p_recipe, 'artisan_set', prev, left(p_note, 200));
end $$;
create or replace function public.recipe_set_artisan(p_recipe uuid, p_artisan int, p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  perform public._recipe_set_artisan(p_recipe, p_artisan, p_note);
end $$;

-- recipes with no artisan: the list "কারিগর নির্ধারিত নয়"
create or replace function public.recipe_unassigned() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not (public._recipe_mgr() or public.has_grant('recipe_view')) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('recipe_id', r.id, 'version', r.version, 'item_id', r.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en,
    'approved', r.approved_at is not null) order by i.code, r.version) from public.recipes r join public.items i on i.id = r.item_id where r.active and r.artisan_id is null), '[]'::jsonb);
end $$;

-- ---------- C0.4 steps ----------
create or replace function public.recipe_steps_save(p_recipe uuid, p_steps jsonb, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.recipes; s jsonb; n int := 0; prev jsonb; mins numeric; ppl int; fu text; rp text; dup public.recipe_versions;
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into dup from public.recipe_versions where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'recipe_id', dup.recipe_id); end if;
  end if;
  select * into r from public.recipes where id = p_recipe for update;
  if not found then raise exception 'recipe_not_found'; end if;
  if r.approved_at is not null then raise exception 'recipe_approved'; end if;
  if p_steps is null or jsonb_typeof(p_steps) <> 'array' then raise exception 'bad_value'; end if;
  if jsonb_array_length(p_steps) > 100 then raise exception 'too_many_lines'; end if;
  for s in select x from jsonb_array_elements(p_steps) x loop
    if length(btrim(coalesce(s->>'step_name', ''))) = 0 then raise exception 'step_name_needed'; end if;
    mins := nullif(btrim(s->>'minutes'), '')::numeric;
    if mins is not null and not (mins >= 0 and mins <= 100000) then raise exception 'bad_qty'; end if;
    ppl := nullif(btrim(s->>'people'), '')::int;
    if ppl is not null and not (ppl >= 0 and ppl <= 1000) then raise exception 'bad_qty'; end if;
    fu := nullif(btrim(s->>'fuel'), '');
    if fu is not null and fu not in ('gas', 'electric', 'other') then raise exception 'bad_value'; end if;
    if fu = 'other' and length(btrim(coalesce(s->>'fuel_other', ''))) = 0 then raise exception 'fuel_other_needed'; end if;
    rp := nullif(btrim(s->>'resp_post'), '');
    if rp is not null and rp not in ('karigor', 'chef', 'asst_karigor', 'other') then raise exception 'bad_post'; end if;
  end loop;
  prev := public._recipe_snapshot(p_recipe);
  update public.recipe_steps set active = false where recipe_id = p_recipe and active;          -- old steps are retired, never deleted
  for s in select x from jsonb_array_elements(p_steps) x loop
    n := n + 1;
    insert into public.recipe_steps (recipe_id, step_no, step_name, description, minutes, people, fuel, fuel_other, flame_note, equipment, qc_note, resp_post, resp_other, created_by)
      values (p_recipe, n, left(btrim(s->>'step_name'), 120), left(nullif(btrim(s->>'description'), ''), 2000), nullif(btrim(s->>'minutes'), '')::numeric, nullif(btrim(s->>'people'), '')::int,
        nullif(btrim(s->>'fuel'), ''), case when s->>'fuel' = 'other' then left(btrim(s->>'fuel_other'), 60) end, left(nullif(btrim(s->>'flame_note'), ''), 200), left(nullif(btrim(s->>'equipment'), ''), 200),
        left(nullif(btrim(s->>'qc_note'), ''), 300), nullif(btrim(s->>'resp_post'), ''), case when s->>'resp_post' = 'other' then left(btrim(s->>'resp_other'), 60) end, auth.uid());
  end loop;
  update public.recipes set changed_by = auth.uid(), changed_at = now() where id = p_recipe;
  perform public._rv_log(p_recipe, 'steps_edited', prev, n::text || ' steps', p_client);
  return jsonb_build_object('recipe_id', p_recipe, 'steps', n) || (public.recipe_labour_suggest(p_recipe));
end $$;

-- SUGGESTION only: minutes x people / 60. It is never read by recipe_cost, production_post or any report.
create or replace function public.recipe_labour_suggest(p_recipe uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare tot numeric; n int; miss int;
begin
  if not (public._recipe_read() or public.has_grant('recipe_view')) then raise exception 'not allowed'; end if;
  select coalesce(sum(minutes * people) filter (where minutes is not null and people is not null), 0), count(*), count(*) filter (where minutes is null or people is null)
    into tot, n, miss from public.recipe_steps where recipe_id = p_recipe and active;
  return jsonb_build_object('suggested_labour_hours', round(tot / 60, 2), 'steps_total', n, 'steps_incomplete', miss, 'incomplete', miss > 0, 'note', 'suggestion_only');
end $$;

-- ---------- C0.3 approval ----------
create or replace function public.recipe_approve(p_recipe uuid, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.recipes; prev jsonb;
begin
  if not public.is_active() or not public.has_grant('recipe_approve') then raise exception 'not allowed'; end if;
  select * into r from public.recipes where id = p_recipe for update;
  if not found then raise exception 'recipe_not_found'; end if;
  if r.approved_at is not null then return jsonb_build_object('dup', true, 'recipe_id', r.id, 'approved_at', r.approved_at); end if;
  if not exists (select 1 from public.recipe_lines where recipe_id = r.id and active) then raise exception 'no_lines'; end if;
  if coalesce(r.changed_by, r.created_by) is not distinct from auth.uid() and not public.rule_on('recipe_self_approve') then raise exception 'self_approve_refused'; end if;
  prev := public._recipe_snapshot(r.id);
  update public.recipes set approved_by = auth.uid(), approved_at = now(), approve_note = left(p_note, 200) where id = r.id;
  perform public._rv_log(r.id, 'approved', prev, left(p_note, 200));
  return jsonb_build_object('recipe_id', r.id, 'approved', true);
end $$;

-- the approval gate for cost / production. off = today's behaviour; warn = continue (the caller adds a yellow line); on = refuse.
create or replace function public._recipe_gate73(p_recipe uuid) returns text language plpgsql stable security definer set search_path = public as $$
declare m text := coalesce(public.rule_txt('recipe_approval_required'), 'off'); ap timestamptz;
begin
  select approved_at into ap from public.recipes where id = p_recipe;
  if ap is not null or m = 'off' then return 'ok'; end if;
  if m = 'on' then raise exception 'recipe_not_approved'; end if;
  return 'warn';
end $$;

-- ---------- re-created: recipe_save (history, changer, approved guard) ----------
create or replace function public.recipe_save(p_id uuid, p_item uuid, p_yield_qty numeric, p_yield_unit text, p_note text, p_lines jsonb, p_client uuid default null, p_retire_old boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it public.items; r public.recipes; v int; rid uuid; yu text := nullif(btrim(p_yield_unit), ''); prev jsonb; /* bos73 */
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_yield_qty is null or not (p_yield_qty > 0 and p_yield_qty < 1000000000) then raise exception 'bad_qty'; end if;
  if p_id is not null then
    select * into r from public.recipes where id = p_id for update;
    if not found then raise exception 'recipe_not_found'; end if;
    if r.approved_at is not null then raise exception 'recipe_approved'; end if;   -- bos73
    if r.used_at is not null then raise exception 'recipe_used'; end if;
    it := (select i from public.items i where i.id = r.item_id);
    prev := public._recipe_snapshot(p_id);   -- bos73
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
    insert into public.recipes (item_id, version, yield_qty, yield_unit, active, note, client_id, created_by, changed_by, changed_at)
      values (it.id, v, p_yield_qty, yu, true, left(p_note, 300), p_client, auth.uid(), auth.uid(), now()) returning id into rid;   -- bos73: changed_by
    if p_retire_old then update public.recipes set active = false where item_id = it.id and id <> rid and active; end if;
  else
    rid := p_id; v := r.version;
    update public.recipes set yield_qty = p_yield_qty, yield_unit = yu, note = left(p_note, 300), changed_by = auth.uid(), changed_at = now() where id = rid;   -- bos73
    update public.recipe_lines set active = false where recipe_id = rid and active;      -- a draft only (never used): old lines are retired, never deleted; the trigger refuses this for a used version
  end if;
  perform public._recipe_put_lines(rid, p_lines);
  perform public._rv_log(rid, case when p_id is null then 'created' else 'edited' end, prev, null);   -- bos73
  return jsonb_build_object('id', rid, 'version', v);
end $$;

-- ---------- re-created: recipe_copy (artisan + steps follow a same-product copy; history row) ----------
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
  insert into public.recipes (item_id, version, yield_qty, yield_unit, active, note, client_id, created_by, changed_by, changed_at, artisan_id)
    values (tgt.id, v, s.yield_qty, case when tgt.id = s.item_id then s.yield_unit else null end, true, s.note, p_client, auth.uid(), auth.uid(), now(),
            case when tgt.id = s.item_id and exists (select 1 from public.artisans a where a.id = s.artisan_id and a.active) then s.artisan_id end) returning id into rid;   -- bos73
  insert into public.recipe_lines (recipe_id, ingredient_item_id, qty, unit, waste_pct, note, sort)
    select rid, ingredient_item_id, qty, unit, waste_pct, note, sort from public.recipe_lines where recipe_id = p_from and active;
  insert into public.recipe_steps (recipe_id, step_no, step_name, description, minutes, people, fuel, fuel_other, flame_note, equipment, qc_note, resp_post, resp_other, created_by)
    select rid, step_no, step_name, description, minutes, people, fuel, fuel_other, flame_note, equipment, qc_note, resp_post, resp_other, auth.uid()
      from public.recipe_steps where recipe_id = p_from and active;   -- bos73
  if tgt.id <> s.item_id and public._base_qty(tgt.id, s.yield_qty, null) is null then raise exception 'unit_unknown'; end if;
  if p_retire_old and tgt.id = s.item_id then update public.recipes set active = false where id = p_from; end if;
  perform public._rv_log(rid, 'created', null, 'copy of version ' || s.version::text);   -- bos73
  return jsonb_build_object('id', rid, 'version', v);
end $$;

-- one atomic call for the editor: lines + steps + artisan + form reference
create or replace function public.recipe_save_full(p_id uuid, p_item uuid, p_yield_qty numeric, p_yield_unit text, p_note text, p_lines jsonb, p_steps jsonb default null,
  p_artisan int default null, p_set_artisan boolean default false, p_form_ref text default null, p_client uuid default null, p_retire_old boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare res jsonb; rid uuid;
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  res := public.recipe_save(p_id, p_item, p_yield_qty, p_yield_unit, p_note, p_lines, p_client, p_retire_old);
  if (res->>'dup')::boolean is true then return res; end if;
  rid := (res->>'id')::uuid;
  if p_steps is not null then perform public.recipe_steps_save(rid, p_steps, null); end if;
  if p_set_artisan then perform public._recipe_set_artisan(rid, p_artisan, null); end if;
  if p_form_ref is not null then update public.recipes set form_ref = left(nullif(btrim(p_form_ref), ''), 40) where id = rid; end if;
  return res;
end $$;

-- ---------- re-created: recipe_cost (approval gate; same maths as phase19) ----------
create or replace function public.recipe_cost(p_recipe uuid, p_loc int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.recipes; ls jsonb := '[]'::jsonb; total numeric := 0; complete boolean := true; l record; need numeric; av numeric; yb numeric; gate text;
begin
  if p_loc is not null then
    if not (public._cost_ok(p_loc) and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;      -- same rule as the stock cost columns
  elsif not public._recipe_cost_ok() then raise exception 'not allowed'; end if;
  select * into r from public.recipes where id = p_recipe;
  if not found then raise exception 'recipe_not_found'; end if;
  gate := public._recipe_gate73(p_recipe);      -- bos73: 'on' = refuse an unapproved recipe
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
    'unit_cost', case when complete and yb > 0 then round(total / yb, 6) end, 'yield_base', yb, 'approved', r.approved_at is not null, 'approval_warn', gate = 'warn');
end $$;

-- ---------- re-created: production_post (ONLY change: the approval gate, marked bos73) ----------
create or replace function public.production_post(p_loc int, p_recipe uuid, p_batches numeric, p_client uuid default null, p_made_at timestamptz default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.recipes; it public.items; at_ timestamptz := coalesce(p_made_at, now()); run public.production_runs; n record; rid uuid := gen_random_uuid();
        mode text; neg text; yb numeric; f numeric; sl jsonb; exp timestamptz; bid bigint; lin bigint; lid bigint; tot numeric := 0; cost_ok boolean := true; av numeric; wm int := 0;
        shorts text := ''; used jsonb := '[]'::jsonb; ucb numeric; derived uuid; gate text;
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
  gate := public._recipe_gate73(r.id);      -- bos73: on = refuse an unapproved recipe; warn = a yellow line below
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
  if gate = 'warn' then      -- bos73
    perform public._stock_exc(p_loc, 'recipe_not_approved', 'yellow', it.name_bn || ': রেসিপি (ভার্সন ' || r.version::text || ') অনুমোদিত নয়',
      coalesce(it.name_en, it.name_bn) || ': recipe version ' || r.version::text || ' is not approved', null, (at_ at time zone 'Asia/Dhaka')::date, 'STOCK');
  end if;
  return jsonb_build_object('run_id', rid, 'ledger_id', lid, 'batch_id', bid, 'qty', yb, 'expires_at', exp, 'consumed', used, 'waste_missing', wm) || case when public._cost_ok(p_loc) then jsonb_build_object('cost_complete', cost_ok) else '{}'::jsonb end;
end $$;

-- ---------- C0.5 / C0.6 the artisan-wise recipe book ----------
-- p_artisan null = the caller's own artisan record (artisan_self_view). Cost columns only when asked AND the caller has the cost right. Every call is audited.
create or replace function public.recipe_book(p_artisan int default null, p_with_cost boolean default false, p_loc int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.artisans; aid int := coalesce(p_artisan, public._artisan_of_user()); rs jsonb := '[]'::jsonb; r record; ln jsonb; st jsonb; lab jsonb; cst jsonb; cost_on boolean;
begin
  if aid is null or not public._recipe_view_ok(aid) then raise exception 'not allowed'; end if;
  select * into a from public.artisans where id = aid;
  if not found then raise exception 'artisan_not_found'; end if;
  cost_on := coalesce(p_with_cost, false) and public._recipe_cost_ok();
  for r in select rc.*, i.code, i.name_bn, i.name_en from public.recipes rc join public.items i on i.id = rc.item_id where rc.artisan_id = aid and rc.active order by i.code, rc.version loop
    select coalesce(jsonb_agg(jsonb_build_object('ingredient_item_id', l.ingredient_item_id, 'code', x.code, 'name_bn', x.name_bn, 'name_en', x.name_en, 'qty', l.qty, 'unit', coalesce(l.unit, public._item_base(l.ingredient_item_id)),
        'waste_pct', l.waste_pct, 'waste_missing', l.waste_pct is null) order by l.sort, l.id), '[]'::jsonb) into ln
      from public.recipe_lines l join public.items x on x.id = l.ingredient_item_id where l.recipe_id = r.id and l.active;
    select coalesce(jsonb_agg(jsonb_build_object('step_no', s.step_no, 'step_name', s.step_name, 'description', s.description, 'minutes', s.minutes, 'people', s.people, 'fuel', s.fuel, 'fuel_other', s.fuel_other,
        'flame_note', s.flame_note, 'equipment', s.equipment, 'qc_note', s.qc_note, 'resp_post', s.resp_post, 'resp_other', s.resp_other) order by s.step_no), '[]'::jsonb) into st
      from public.recipe_steps s where s.recipe_id = r.id and s.active;
    lab := public.recipe_labour_suggest(r.id);
    cst := null;
    if cost_on then
      begin cst := public.recipe_cost(r.id, p_loc); exception when others then cst := jsonb_build_object('error', sqlerrm); end;
    end if;
    rs := rs || (jsonb_build_object('recipe_id', r.id, 'version', r.version, 'item_id', r.item_id, 'code', r.code, 'name_bn', r.name_bn, 'name_en', r.name_en, 'yield_qty', r.yield_qty,
        'yield_unit', coalesce(r.yield_unit, public._item_base(r.item_id)), 'approved', r.approved_at is not null, 'approved_at', r.approved_at, 'form_ref', r.form_ref,
        'lines', ln, 'steps', st, 'labour', lab) || case when cost_on then jsonb_build_object('cost', cst) else '{}'::jsonb end);
  end loop;
  perform public._audit_view('recipe_book', aid::text, jsonb_build_object('with_cost', cost_on, 'recipes', jsonb_array_length(rs)));
  return jsonb_build_object('artisan', jsonb_build_object('id', a.id, 'code', a.code, 'post', a.post, 'post_other', a.post_other, 'work_type', a.work_type, 'work_other', a.work_other,
    'location_id', a.location_id, 'active', a.active), 'recipes', rs, 'with_cost', cost_on, 'generated_at', now());
end $$;

-- ---------- privileges ----------
revoke all on function public._artisan_audit(), public._rv_immutable(), public._recipe_approved_guard(), public._artisan_mgr(), public._artisan_of_user(), public._audit_view(text, text, jsonb),
  public._recipe_snapshot(uuid), public._rv_log(uuid, text, jsonb, text, uuid), public._recipe_set_artisan(uuid, int, text), public._recipe_gate73(uuid) from public, anon, authenticated;
revoke all on function public._recipe_view_ok(int) from public, anon;
grant execute on function public._recipe_view_ok(int) to authenticated;
revoke all on function public.artisan_save(int, text, text, text, text, text, int, uuid, text, uuid), public.artisan_set_active(int, boolean, text), public.artisan_register(), public.artisan_list(boolean),
  public.recipe_set_artisan(uuid, int, text), public.recipe_unassigned(), public.recipe_steps_save(uuid, jsonb, uuid), public.recipe_labour_suggest(uuid), public.recipe_approve(uuid, text),
  public.recipe_save_full(uuid, uuid, numeric, text, text, jsonb, jsonb, int, boolean, text, uuid, boolean), public.recipe_book(int, boolean, int) from public, anon;
grant execute on function public.artisan_save(int, text, text, text, text, text, int, uuid, text, uuid), public.artisan_set_active(int, boolean, text), public.artisan_register(), public.artisan_list(boolean),
  public.recipe_set_artisan(uuid, int, text), public.recipe_unassigned(), public.recipe_steps_save(uuid, jsonb, uuid), public.recipe_labour_suggest(uuid), public.recipe_approve(uuid, text),
  public.recipe_save_full(uuid, uuid, numeric, text, text, jsonb, jsonb, int, boolean, text, uuid, boolean), public.recipe_book(int, boolean, int) to authenticated;
