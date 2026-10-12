-- ============================================================
-- Phase 16 (W4): LOCATIONS (kind / model / status / hub / setup steps / pause / close) + CONTROL CENTER counts
--                + SETTINGS SHEET 0-1 VERSIONS (get_limit)   (additive, safe to run twice, paste whole into the Supabase SQL editor)
--   Needs phase8..phase14 applied first. Does NOT need phase15 (list_defs / list_queue_counts are used only when they exist).
--   * locations (existing table): + kind, model, status (planned | setting_up | live | paused | closed), supplied_by, planned_opening, hub_functions,
--     note, paused_reason/by/at, closed_reason/by/at, status_by/at, created_by/at.  Existing 7 rows: kind/model/status filled ONCE
--     (all live, except the stopped Mujgunni factory `mishti_factory` = paused).  Codes stay immutable (phase11); nothing is deleted.
--   * option list 'location_models' (A own place, B franchise, C funded; B and C start retired = hidden, the owner switches them on in Lists)
--   * location_setup_steps: 17 steps per new place (read from Build command 5), gate: steps 1-15 (optional ones aside) before 16 (start)
--   * RPC location_save (edit / add a new place; code = slug of the name, unique), location_set_status (pause / resume / close with checklist
--     warnings; the owner may override), location_set_active, location_step_set, location_steps_init, location_close_check
--   * grants location_manage, head_management, settings_approve (owner delegates; has_grant()); rules location_block_when_paused (ON),
--     location_start_first_of_month (OFF), block_on_missing_limit (OFF), owner_self_approve (ON, same key as phase15)
--   * a paused / closed place refuses NEW entries and sales on the server (triggers on entries and sales); reading stays open
--   * settings_sheets + settings_values: versions of the Location Settings Sheet 0-1, seeded as approved version 1 from location_settings;
--     draft -> approve (maker <> approver, the owner exempt while owner_self_approve is ON); get_limit(loc, key, date) returns the value in force
--     on that date or NULL (= Data needed).  location_settings stays readable and is written through, so every old screen keeps working;
--     an edit through the old screen makes a new (auto) version.
--   * control_counts(): the merged "Needs you" counts for the Control Center / Home (only what the caller may decide)
-- ============================================================

-- ---------- (0) helpers (same text as phase11 / phase15; created only so this file also works alone) ----------
create or replace function public.no_hard_delete() returns trigger
language plpgsql set search_path = public as $$
begin raise exception 'nothing is deleted – retire instead'; end $$;

-- ---------- (1) locations: new columns ----------
alter table public.locations add column if not exists kind text;
alter table public.locations add column if not exists model text;
alter table public.locations add column if not exists status text not null default 'live';
alter table public.locations add column if not exists supplied_by int references public.locations(id);
alter table public.locations add column if not exists planned_opening date;
alter table public.locations add column if not exists hub_functions boolean not null default false;
alter table public.locations add column if not exists note text;
alter table public.locations add column if not exists paused_reason text;
alter table public.locations add column if not exists paused_by uuid;
alter table public.locations add column if not exists paused_at timestamptz;
alter table public.locations add column if not exists closed_reason text;
alter table public.locations add column if not exists closed_by uuid;
alter table public.locations add column if not exists closed_at timestamptz;
alter table public.locations add column if not exists status_by uuid;
alter table public.locations add column if not exists status_at timestamptz;
alter table public.locations add column if not exists created_by uuid;
alter table public.locations add column if not exists created_at timestamptz default now();
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'locations_kind_chk') then
    alter table public.locations add constraint locations_kind_chk check (kind is null or kind in ('showroom', 'factory', 'godown', 'hub', 'online', 'other'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'locations_status_chk') then
    alter table public.locations add constraint locations_status_chk check (status in ('planned', 'setting_up', 'live', 'paused', 'closed'));
  end if;
end $$;

-- the seven existing places: filled ONCE (kind is null only before the first run), never overwritten afterwards
update public.locations set
  kind = case code when 'cake_factory' then 'factory' when 'mishti_factory' then 'factory' when 'godown' then 'godown' else 'showroom' end,
  model = 'A',
  hub_functions = (code = 'main'),
  status = case when code = 'mishti_factory' or not is_active then 'paused' else 'live' end,
  paused_reason = case when code = 'mishti_factory' then 'বন্ধ মুজগুন্নি কারখানা (যন্ত্র রাখা) / stopped Mujgunni factory'
                       when not is_active then 'inactive before phase16' end,
  paused_at = case when code = 'mishti_factory' or not is_active then now() end,
  status_at = now()
where kind is null and code in ('main', 'branch2', 'mishti_bari', 'al_cakes', 'cake_factory', 'mishti_factory', 'godown');
-- any other pre-existing row (added by SQL by hand): showroom, own place, live unless inactive
update public.locations set kind = 'showroom', model = 'A', status = case when is_active then 'live' else 'paused' end, status_at = now()
where kind is null;

-- ---------- (2) rules and grants ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('location_block_when_paused', 'locations', 'switch', 'true', null, null, null, null, 'বিরতি/বন্ধ লোকেশনে নতুন এন্ট্রি ও বিক্রি আটকানো', 'Paused/closed location-এ নতুন entry ও sale আটকানো', 'Block new entries and sales at a paused or closed place',
   'চালু থাকলে সার্ভারই নতুন এন্ট্রি/বিক্রি নেবে না; দেখা (রিপোর্ট) চলবে', 'On থাকলে server নতুন entry/sale নেবে না; দেখা চলবে', 'When on the server refuses new entries and sales; reading and reports stay open', 80),
 ('location_start_first_of_month', 'locations', 'switch', 'false', null, null, null, null, 'নতুন লোকেশন শুধু মাসের ১ তারিখে চালু (ধাপ ১৬)', 'নতুন location শুধু মাসের ১ তারিখে চালু (step 16)', 'A new place may start only on the 1st of a month (step 16)',
   'বন্ধ রাখলে যেকোনো দিনে চালু করা যাবে', 'Off থাকলে যেকোনো দিনে start', 'Off = any day', 81),
 ('block_on_missing_limit', 'locations', 'switch', 'false', null, null, null, null, 'সীমা ফাঁকা থাকলে ফর্ম জমা আটকানো', 'Limit ফাঁকা থাকলে Form জমা আটকানো', 'Block a form submit while a limit it needs is blank (Data needed)',
   'ডিফল্ট বন্ধ: ফাঁকা থাকলে শুধু ‘তথ্য লাগবে’ দেখাবে', 'Default Off: শুধু ‘Data needed’ দেখাবে', 'Default off: only shows Data needed', 82),
 ('owner_self_approve', 'lists', 'switch', 'true', null, null, null, null, 'মালিক নিজের অনুরোধ নিজে অনুমোদন করতে পারবেন', 'Owner নিজের request নিজে approve করতে পারবেন', 'Owner may approve their own request',
   'বন্ধ করলে মালিকের অনুরোধও অন্য অনুমতিপ্রাপ্ত কেউ অনুমোদন করবেন', 'Off করলে owner-এর request অন্য কেউ approve করবেন', 'When off, the owner''s own requests need another approver', 50)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('location_manage', 'master', 63, 'লোকেশন পরিচালনা: সম্পাদনা, নতুন শোরুম, বিরতি/বন্ধ, সেটআপ ধাপ', 'Location পরিচালনা: edit, নতুন showroom, pause/close, setup step', 'Manage locations: edit, add a showroom, pause / close, setup steps', 'window', null),
 ('head_management', 'master', 64, 'হেড ম্যানেজমেন্ট: কন্ট্রোল সেন্টারের অংশ (লোকেশন, সীমা, তালিকা) — খরচ/বেতন ছাড়া', 'Head management: Control Center-এর অংশ (location, limit, list) — cost/salary ছাড়া', 'Head management: part of the Control Center (places, limits, lists), no costs or salaries', 'window', null),
 ('settings_approve', 'settings', 65, 'সেটিংস শিট (০-১) এর নতুন সংস্করণ অনুমোদন', 'Settings sheet (0-1) এর নতুন version approve', 'Approve a new version of the settings sheet (0-1)', 'window', null)
on conflict (grant_code) do nothing;

-- who may do what (server side)
create or replace function public._loc_mgr() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or (public.is_active() and (public.has_grant('location_manage') or public.has_grant('head_management')));
$$;
create or replace function public._sheet_viewer() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or (public.is_active() and (public.has_grant('location_manage') or public.has_grant('head_management') or public.has_grant('settings_approve')));
$$;

-- location-scoped versions: a grant given for ONE place (user_grants.location_id) counts for that place only
create or replace function public._loc_mgr_at(p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or (public.is_active() and (public.has_grant('location_manage', p_loc) or public.has_grant('head_management', p_loc)));
$$;
create or replace function public._sheet_viewer_at(p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or (public.is_active() and (public.has_grant('location_manage', p_loc) or public.has_grant('head_management', p_loc) or public.has_grant('settings_approve', p_loc)));
$$;

-- ---------- (3) option list 'location_models' (editable in #/lists) ----------
insert into public.option_lists (list_code, value_code, label_bn, label_mix, label_en, sort, active)
select 'location_models', v.c, v.bn, v.mx, v.en, v.s, v.a from (values
  ('A', 'ক — নিজস্ব স্থান', 'A — Own place', 'A — Own place', 1, true),
  ('B', 'খ — ফ্র্যাঞ্চাইজ (এখনও সিদ্ধান্ত হয়নি)', 'B — Franchise (not decided yet)', 'B — Franchise (not decided yet)', 2, false),
  ('C', 'গ — অংশীদারি/ফান্ডেড (এখনও সিদ্ধান্ত হয়নি)', 'C — Funded (not decided yet)', 'C — Funded partner (not decided yet)', 3, false)) as v(c, bn, mx, en, s, a)
where not exists (select 1 from public.option_lists o where o.list_code = 'location_models' and o.value_code = v.c);
do $$ begin
  if to_regclass('public.list_defs') is not null then
    insert into public.list_defs (list_code, add_rule) values ('location_models', 'owner') on conflict (list_code) do nothing;
  end if;
end $$;

-- ---------- (4) setup steps ----------
create table if not exists public.location_setup_steps (
  location_id int not null references public.locations(id),
  step_no int not null check (step_no between 1 and 17),
  title_bn text not null, title text not null,
  owner_role text, owner_yes boolean not null default false, optional boolean not null default false,
  done boolean not null default false, done_by uuid, done_at timestamptz, note text,
  primary key (location_id, step_no)
);
alter table public.location_setup_steps enable row level security;
drop policy if exists loc_steps_read on public.location_setup_steps;
create policy loc_steps_read on public.location_setup_steps for select to authenticated using (public._loc_mgr_at(location_id));
revoke all on public.location_setup_steps from public, anon, authenticated;
grant select on public.location_setup_steps to authenticated;
drop trigger if exists audit_loc_steps on public.location_setup_steps;
create trigger audit_loc_steps after insert or update on public.location_setup_steps for each row execute function public.log_change('location_id,step_no');
drop trigger if exists loc_steps_no_delete on public.location_setup_steps;
create trigger loc_steps_no_delete before delete on public.location_setup_steps for each row execute function public.no_hard_delete();

-- the 17 steps of Build command 5 (owner_yes = the step marked * : needs the owner's yes)
create or replace function public._loc_steps_def() returns table (n int, bn text, en text, who text, yes boolean, opt boolean)
language sql immutable set search_path = public as $$
  select * from (values
   (1,  'সিদ্ধান্ত: জায়গা, ভাড়া, বাজেট, প্রত্যাশিত বিক্রি, কোন কারখানা সরবরাহ করবে', 'Decide: place, rent, budget, expected sales, which factory supplies it', 'Owner', true, false),
   (2,  'লোকেশন কোড ও লোকেশন তালিকায় একটি সারি', 'Location code and a row in the location list', 'Daily-accounts reconciliation staff', false, false),
   (3,  'পরের ছাপা পর্যন্ত প্রতিটি ফর্মের লোকেশন বক্সে "অন্যান্য"-এ নাম লেখা', 'Name the place under Other on every form''s location box until the next print', 'Head management', false, false),
   (4,  'এই জায়গার আইটেম তালিকা ও বর্তমান মূল্য তালিকা', 'Item list and current price list for this place', 'Head management', false, false),
   (5,  'ডিউটি স্লট: ম্যানেজার, ব্যাকআপ, রাতের দ্বিতীয় গণনাকারী; একই ব্যক্তি দুই স্লটে নয় (ফর্ম ০২-৭)', 'Duty slots: manager, backup, night second counter; the same person is never in two slots (form 02-7)', 'Owner names, head management enters', true, false),
   (6,  'নতুন ডিউটি-ধারকের দক্ষতা যাচাই (ফর্ম ০২-৮)', 'Skill check of the new duty holder (form 02-8)', 'A checker from the list', false, false),
   (7,  'নিয়োগ ও নিবন্ধন (ফর্ম ০২-৪)', 'Hiring and registration (form 02-4)', 'Head management', false, false),
   (8,  'একজন-মানুষের ফাঁক পূরণ: রাতের দ্বিতীয় গণনা, সাক্ষী, শিফট হস্তান্তর (ফর্ম ০২-৭, ১১-১)', 'Cover the one-person gap: night second count, witness, shift handover (forms 02-7, 11-1)', 'Owner', true, false),
   (9,  'ক্যাশ বক্স: ড্রয়ার ফ্লোট ও ইমপ্রেস আলাদা; ব্যবসার মোবাইল-মানি নম্বর (০-১ সারি ১, ২)', 'Cash boxes: drawer float and imprest kept apart; the business mobile-money number (0-1 rows 1 and 2)', 'Head management', false, false),
   (10, 'এই জায়গার নিজস্ব মাপে লোকেশন সেটিংস শিট ০-১ (হেড ম্যানেজমেন্ট পূরণ, মালিক অনুমোদন)', 'Location Settings Sheet 0-1 at this place''s own measures (head management fills, owner approves)', 'Head management fills, owner approves', true, false),
   (11, 'যন্ত্রপাতি ও জায়গা: ফ্রিজ থার্মোমিটার, ওজন পরীক্ষার বাটখারা, হস্তান্তরের জায়গা, চাবির দায়িত্ব (০-১ সারি ১১, ১৩, ৩০)', 'Equipment and places: fridge thermometer, scale test weight, handover place, key duty (0-1 rows 11, 13, 30)', 'Head management', false, false),
   (12, 'কাগজের সেট ছাপা, সিরিয়াল সহ; প্রতিটি বইয়ের প্রথম নম্বর লেখা', 'Print the paper set with serial numbers; write the first number of each book', 'Head management', false, false),
   (13, 'সরবরাহ মানচিত্র: কোন কারখানা, কত ট্রিপ, হস্তান্তর বিন্দু (সরবরাহ মানচিত্র নিশ্চিত না হওয়া পর্যন্ত ঐচ্ছিক)', 'Supply map: which factory, how many trips, the handover point (optional until the supply map is confirmed)', 'Head management', false, true),
   (14, 'প্রশিক্ষণ, এক কাগজ এক করে (ফর্ম ০২-৮)', 'Training, one paper at a time (form 02-8)', 'Head management', false, false),
   (15, 'আগের রাতে উদ্বোধনী গণনা (ফর্ম ০৪-৩, ০৪-৪)', 'Opening count the night before (forms 04-3, 04-4)', 'Two counters', false, false),
   (16, 'মাসের ১ তারিখে চালু: প্রথম সপ্তাহ, এক মাসের পাস/ফেল, তারপর ৭, ৩০, ৯০ দিনের পর্যালোচনা', 'Start on the 1st: first week, then one month pass or fail, then 7, 30 and 90 day reviews', 'Everyone at the place', false, false),
   (17, 'অন্য জায়গার সাথে একই সংখ্যায় সাপ্তাহিক তুলনা (ফর্ম ০১-১, নতুন কলাম)', 'Weekly comparison with the other places on the same figures (form 01-1, a new column)', 'Head management', false, false)
  ) as v(n, bn, en, who, yes, opt);
$$;

create or replace function public._loc_steps_seed(p_loc int) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.location_setup_steps (location_id, step_no, title_bn, title, owner_role, owner_yes, optional)
  select p_loc, d.n, d.bn, d.en, d.who, d.yes, d.opt from public._loc_steps_def() d
  on conflict (location_id, step_no) do nothing;
end $$;

-- ---------- (5) location RPCs ----------
create or replace function public._slug(p text) returns text
language sql immutable set search_path = public as $$
  select left(trim(both '_' from regexp_replace(lower(coalesce(p, '')), '[^a-z0-9]+', '_', 'g')), 30);
$$;

-- status moves are enforced by the DATABASE (any writer, also plain SQL): closed is final
create or replace function public._loc_status_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.status is distinct from old.status then
    if old.status = 'closed' then raise exception 'closed_is_final'; end if;
    if not ((old.status, new.status) in (('planned', 'setting_up'), ('planned', 'live'), ('planned', 'closed'), ('setting_up', 'planned'), ('setting_up', 'live'), ('setting_up', 'paused'), ('setting_up', 'closed'),
                                         ('live', 'paused'), ('live', 'closed'), ('paused', 'live'), ('paused', 'closed'))) then
      raise exception 'bad_transition:%->%', old.status, new.status;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists locations_status_guard on public.locations;
create trigger locations_status_guard before update on public.locations for each row execute function public._loc_status_guard();

-- edit (p_id given) or add (p_id null) a place.  p_patch keys: name_bn name_mix name_en kind model supplied_by planned_opening hub_functions note sort code (add only)
create or replace function public.location_save(p_id int, p_patch jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r public.locations; v_code text; base text; n int := 1; v text; k text; sb int; hops int := 0; nid int; po date; sortv int; hubv boolean;
  newname_bn text; newname_en text;
begin
  if p_id is null then
    if not public._loc_mgr() then raise exception 'not allowed'; end if;
  elsif not public._loc_mgr_at(p_id) then raise exception 'not allowed'; end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then raise exception 'bad_patch'; end if;
  for k in select jsonb_object_keys(p_patch) loop
    if k not in ('name_bn', 'name_mix', 'name_en', 'kind', 'model', 'supplied_by', 'planned_opening', 'hub_functions', 'note', 'sort', 'code') then raise exception 'unknown_field:%', k; end if;
  end loop;
  if p_patch ? 'code' and p_id is not null and (p_patch->>'code') is distinct from (select l.code from public.locations l where l.id = p_id) then raise exception 'code is immutable'; end if;
  if p_patch ? 'kind' and nullif(p_patch->>'kind', '') is not null and (p_patch->>'kind') not in ('showroom', 'factory', 'godown', 'hub', 'online', 'other') then raise exception 'bad_kind'; end if;
  if p_patch ? 'model' and nullif(p_patch->>'model', '') is not null
     and not exists (select 1 from public.option_lists o where o.list_code = 'location_models' and o.value_code = p_patch->>'model' and o.active) then raise exception 'bad_model'; end if;
  foreach v in array array['name_bn', 'name_mix', 'name_en', 'note'] loop
    if p_patch ? v and length(coalesce(p_patch->>v, '')) > (case when v = 'note' then 500 else 120 end) then raise exception 'too_long:%', v; end if;
  end loop;
  -- casts: a bad text is a friendly code, never a raw cast error
  if p_patch ? 'planned_opening' and nullif(p_patch->>'planned_opening', '') is not null then
    begin po := (p_patch->>'planned_opening')::date; exception when others then raise exception 'bad_date'; end;
    if po < date '2000-01-01' or po > date '2100-01-01' then raise exception 'bad_date'; end if;
  end if;
  if p_patch ? 'sort' and nullif(p_patch->>'sort', '') is not null then
    begin sortv := (p_patch->>'sort')::int; exception when others then raise exception 'bad_number'; end;
    if not (sortv between 0 and 9999) then raise exception 'bad_number'; end if;
  end if;
  if p_patch ? 'hub_functions' then
    begin hubv := coalesce((p_patch->>'hub_functions')::boolean, false); exception when others then raise exception 'bad_value'; end;
  end if;
  if p_patch ? 'supplied_by' and nullif(p_patch->>'supplied_by', '') is not null then
    begin sb := (p_patch->>'supplied_by')::int; exception when others then raise exception 'bad_number'; end;
    if not exists (select 1 from public.locations where id = sb) then raise exception 'unknown_supplier_location'; end if;
    if p_id is null or sb is distinct from (select l.supplied_by from public.locations l where l.id = p_id) then
      if not exists (select 1 from public.locations where id = sb and is_active and status <> 'closed') then raise exception 'supplier_not_active'; end if;
    end if;
    if p_id is not null then
      if sb = p_id then raise exception 'supplied_by_itself'; end if;
      -- no loop: walk up the supplied_by chain of the chosen supplier
      declare walk int := sb;
      begin
        loop
          select l.supplied_by into walk from public.locations l where l.id = walk; hops := hops + 1;
          exit when walk is null or hops > 20;
          if walk = p_id then raise exception 'supplied_by_loop'; end if;
        end loop;
      end;
    end if;
  end if;

  if p_id is null then
    perform pg_advisory_xact_lock(1600);
    newname_bn := nullif(btrim(coalesce(p_patch->>'name_bn', '')), ''); newname_en := nullif(btrim(coalesce(p_patch->>'name_en', '')), '');
    if newname_bn is null and newname_en is null then raise exception 'name_required'; end if;
    if newname_bn is null then newname_bn := newname_en; end if;
    if exists (select 1 from public.locations x where lower(btrim(x.name_bn)) = lower(newname_bn) or (newname_en is not null and lower(btrim(coalesce(x.name_en, ''))) = lower(newname_en))) then raise exception 'name_in_use'; end if;
    if nullif(p_patch->>'code', '') is not null then
      v_code := p_patch->>'code';
      if v_code !~ '^[a-z][a-z0-9_]{1,29}$' then raise exception 'bad_code'; end if;
      if exists (select 1 from public.locations x where x.code = v_code) then raise exception 'code_in_use'; end if;
    else
      base := public._slug(coalesce(newname_en, ''));
      if base is null or length(base) < 2 or base !~ '^[a-z]' then base := 'loc'; end if;
      v_code := base;
      while exists (select 1 from public.locations x where x.code = v_code) loop n := n + 1; v_code := left(base, 26) || '_' || n; end loop;
    end if;
    insert into public.locations (code, name_bn, name_mix, name_en, sort, is_active, kind, model, status, supplied_by, planned_opening, hub_functions, note, created_by, created_at, status_by, status_at)
    values (v_code, newname_bn, nullif(btrim(coalesce(p_patch->>'name_mix', '')), ''), newname_en,
            coalesce(sortv, (select coalesce(max(x.sort), 0) + 1 from public.locations x)), true,
            coalesce(nullif(p_patch->>'kind', ''), 'showroom'), coalesce(nullif(p_patch->>'model', ''), 'A'), 'planned', sb, po,
            coalesce(hubv, false), nullif(p_patch->>'note', ''), auth.uid(), now(), auth.uid(), now())
    returning id into nid;
    perform public._loc_steps_seed(nid);
    update public.location_setup_steps set done = true, done_by = auth.uid(), done_at = now(), note = 'created with the place' where location_id = nid and step_no = 2;
    perform public._sheet_sync_due();
    return jsonb_build_object('id', nid, 'code', v_code, 'created', true);
  end if;

  select * into r from public.locations where id = p_id for update;
  if not found then raise exception 'unknown_location'; end if;
  -- a rename may not collide with another place
  if p_patch ? 'name_bn' and nullif(btrim(p_patch->>'name_bn'), '') is not null
     and exists (select 1 from public.locations x where x.id <> p_id and lower(btrim(x.name_bn)) = lower(btrim(p_patch->>'name_bn'))) then raise exception 'name_in_use'; end if;
  if p_patch ? 'name_en' and nullif(btrim(p_patch->>'name_en'), '') is not null
     and exists (select 1 from public.locations x where x.id <> p_id and lower(btrim(coalesce(x.name_en, ''))) = lower(btrim(p_patch->>'name_en'))) then raise exception 'name_in_use'; end if;
  update public.locations l set
    name_bn = case when p_patch ? 'name_bn' then coalesce(nullif(btrim(p_patch->>'name_bn'), ''), l.name_bn) else l.name_bn end,
    name_mix = case when p_patch ? 'name_mix' then nullif(btrim(p_patch->>'name_mix'), '') else l.name_mix end,
    name_en = case when p_patch ? 'name_en' then nullif(btrim(p_patch->>'name_en'), '') else l.name_en end,
    kind = case when p_patch ? 'kind' then coalesce(nullif(p_patch->>'kind', ''), l.kind) else l.kind end,
    model = case when p_patch ? 'model' then coalesce(nullif(p_patch->>'model', ''), l.model) else l.model end,
    supplied_by = case when p_patch ? 'supplied_by' then sb else l.supplied_by end,
    planned_opening = case when p_patch ? 'planned_opening' then po else l.planned_opening end,
    hub_functions = case when p_patch ? 'hub_functions' then coalesce(hubv, false) else l.hub_functions end,
    note = case when p_patch ? 'note' then nullif(p_patch->>'note', '') else l.note end,
    sort = coalesce(sortv, l.sort)
  where l.id = p_id;
  perform public._sheet_sync_due();
  return jsonb_build_object('id', p_id, 'code', r.code, 'created', false);
end $$;

-- things that should be settled before a place stops: open credit, stock on hand, open entries, transfers on the way
create or replace function public.location_close_check(p_id int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare dues numeric := 0; stk numeric := 0; stki int := 0; oe int := 0; tr int := 0; w jsonb := '[]';
begin
  if not public._loc_mgr_at(p_id) then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.locations where id = p_id) then raise exception 'unknown_location'; end if;
  select coalesce(sum(due_amount), 0) into dues from public.sales where location_id = p_id and status = 'done' and due_amount > 0;
  select coalesce(sum(qty), 0), count(*) into stk, stki from public.stock_balance where location_id = p_id and qty > 0;
  select count(*) into oe from public.entries where location_id = p_id and status in ('draft', 'submitted');
  select count(*) into tr from public.stock_transfers where status = 'sent' and (from_location_id = p_id or to_location_id = p_id);
  if dues > 0 then w := w || jsonb_build_object('code', 'open_dues', 'amount', dues); end if;
  if stki > 0 then w := w || jsonb_build_object('code', 'stock_on_hand', 'items', stki, 'qty', stk); end if;
  if oe > 0 then w := w || jsonb_build_object('code', 'open_entries', 'count', oe); end if;
  if tr > 0 then w := w || jsonb_build_object('code', 'transfers_in_transit', 'count', tr); end if;
  return jsonb_build_object('warnings', w, 'ok', jsonb_array_length(w) = 0);
end $$;

-- steps that block the start (1..15 except optional ones)
create or replace function public._loc_open_steps(p_id int) returns int[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(step_no order by step_no), '{}') from public.location_setup_steps
  where location_id = p_id and step_no <= 15 and not done and not optional;
$$;

-- pause / resume / start / close.  Returns {ok:false, warnings:[...]} when a checklist is open and p_override is not set; only the owner may override.
create or replace function public.location_set_status(p_id int, p_status text, p_reason text default null, p_override boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.locations; w jsonb := '[]'; open_steps int[]; cc jsonb; okmove boolean := false; reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not public._loc_mgr_at(p_id) then raise exception 'not allowed'; end if;
  if p_status not in ('planned', 'setting_up', 'live', 'paused', 'closed') then raise exception 'bad_status'; end if;
  if reason is not null and length(reason) > 500 then raise exception 'too_long:reason'; end if;
  select * into r from public.locations where id = p_id for update;
  if not found then raise exception 'unknown_location'; end if;
  if r.status = p_status then return jsonb_build_object('ok', true, 'status', r.status, 'unchanged', true); end if;
  if r.status = 'closed' then raise exception 'closed_is_final'; end if;
  okmove := (r.status, p_status) in (('planned', 'setting_up'), ('planned', 'live'), ('planned', 'closed'), ('setting_up', 'planned'), ('setting_up', 'live'), ('setting_up', 'paused'), ('setting_up', 'closed'),
                                     ('live', 'paused'), ('live', 'closed'), ('paused', 'live'), ('paused', 'closed'));
  if not okmove then raise exception 'bad_transition:%->%', r.status, p_status; end if;
  if p_status in ('paused', 'closed') and reason is null then raise exception 'reason_required'; end if;

  if p_status = 'live' and r.status in ('planned', 'setting_up') then
    open_steps := public._loc_open_steps(p_id);
    if coalesce(array_length(open_steps, 1), 0) > 0 then w := w || jsonb_build_object('code', 'setup_steps_open', 'steps', to_jsonb(open_steps)); end if;
    if public.rule_on('location_start_first_of_month') and extract(day from (now() at time zone 'Asia/Dhaka')::date) <> 1 then w := w || jsonb_build_object('code', 'not_first_of_month'); end if;
  elsif p_status = 'closed' then
    cc := public.location_close_check(p_id); w := cc->'warnings';
  end if;
  if jsonb_array_length(w) > 0 then
    if not coalesce(p_override, false) then return jsonb_build_object('ok', false, 'warnings', w, 'status', r.status); end if;
    if not public.is_owner() then raise exception 'owner_override_only'; end if;
    if reason is null then raise exception 'reason_required'; end if;
  end if;

  update public.locations set status = p_status, status_by = auth.uid(), status_at = now(),
    paused_reason = case when p_status = 'paused' then reason else paused_reason end,
    paused_by = case when p_status = 'paused' then auth.uid() else paused_by end,
    paused_at = case when p_status = 'paused' then now() else paused_at end,
    closed_reason = case when p_status = 'closed' then reason else closed_reason end,
    closed_by = case when p_status = 'closed' then auth.uid() else closed_by end,
    closed_at = case when p_status = 'closed' then now() else closed_at end,
    is_active = case when p_status = 'closed' then false else is_active end
  where id = p_id;
  return jsonb_build_object('ok', true, 'status', p_status, 'overridden', jsonb_array_length(w) > 0, 'warnings', w);
end $$;

-- switch a place active / inactive (a lighter switch than pause).  Closed places stay inactive.
create or replace function public.location_set_active(p_id int, p_active boolean) returns void
language plpgsql security definer set search_path = public as $$
declare st text;
begin
  if not public._loc_mgr_at(p_id) then raise exception 'not allowed'; end if;
  select status into st from public.locations where id = p_id;
  if not found then raise exception 'unknown_location'; end if;
  if st = 'closed' and coalesce(p_active, true) then raise exception 'closed_is_final'; end if;
  update public.locations set is_active = coalesce(p_active, true) where id = p_id;
end $$;

-- make sure a place has its 17 steps (for an older place the owner wants to run the checklist on)
create or replace function public.location_steps_init(p_id int) returns int
language plpgsql security definer set search_path = public as $$
begin
  if not public._loc_mgr_at(p_id) then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.locations where id = p_id) then raise exception 'unknown_location'; end if;
  perform public._loc_steps_seed(p_id);
  return (select count(*) from public.location_setup_steps where location_id = p_id);
end $$;

-- tick / untick one step.  Steps marked * (owner_yes) are the owner's only; step 16 needs 1-15; ticking 16 starts a place that is in setup
-- (a PAUSED place is never resumed silently: resume it on purpose).
create or replace function public.location_step_set(p_loc int, p_step int, p_done boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.location_setup_steps; st jsonb; open_steps int[]; cur text;
begin
  if not public._loc_mgr_at(p_loc) then raise exception 'not allowed'; end if;
  if p_note is not null and length(p_note) > 500 then raise exception 'too_long:note'; end if;
  select * into s from public.location_setup_steps where location_id = p_loc and step_no = p_step for update;
  if not found then raise exception 'unknown_step'; end if;
  select status into cur from public.locations where id = p_loc;
  if cur = 'closed' then raise exception 'closed_is_final'; end if;
  if s.owner_yes and not public.is_owner() then raise exception 'owner_only_step'; end if;
  if coalesce(p_done, true) and p_step = 16 then
    if cur = 'paused' then raise exception 'place_paused'; end if;
    open_steps := public._loc_open_steps(p_loc);
    if coalesce(array_length(open_steps, 1), 0) > 0 then raise exception 'steps_open:%', array_to_string(open_steps, ','); end if;
  end if;
  update public.location_setup_steps set done = coalesce(p_done, true),
    done_by = case when coalesce(p_done, true) then auth.uid() end, done_at = case when coalesce(p_done, true) then now() end,
    note = coalesce(nullif(btrim(p_note), ''), note)
  where location_id = p_loc and step_no = p_step;
  if coalesce(p_done, true) and p_step = 16 and cur in ('planned', 'setting_up') then
    st := public.location_set_status(p_loc, 'live', 'step 16: started', false);
    if (st->>'ok')::boolean is not true then
      update public.location_setup_steps set done = false, done_by = null, done_at = null where location_id = p_loc and step_no = 16;
      return jsonb_build_object('ok', false, 'warnings', st->'warnings');
    end if;
  elsif coalesce(p_done, true) and cur = 'planned' then
    update public.locations set status = 'setting_up', status_by = auth.uid(), status_at = now() where id = p_loc and status = 'planned';
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- ---------- (6) paused / closed places refuse NEW entries and sales ----------
-- Real work that happened BEFORE the status change but reaches the server late (back-dated entry, offline sale synced later) is still accepted:
-- only rows dated on / after the status change are refused.  The owner can open a short window for late work (location_block_override, logged).
create table if not exists public.location_block_overrides (
  id bigserial primary key,
  location_id int not null references public.locations(id),
  reason text not null, created_by uuid, created_at timestamptz not null default now(), expires_at timestamptz not null
);
alter table public.location_block_overrides enable row level security;
drop policy if exists loc_block_ov_read on public.location_block_overrides;
create policy loc_block_ov_read on public.location_block_overrides for select to authenticated using (public.is_owner());
revoke all on public.location_block_overrides from public, anon, authenticated;
grant select on public.location_block_overrides to authenticated;
drop trigger if exists audit_loc_block_ov on public.location_block_overrides;
create trigger audit_loc_block_ov after insert or update on public.location_block_overrides for each row execute function public.log_change('id');
drop trigger if exists loc_block_ov_no_delete on public.location_block_overrides;
create trigger loc_block_ov_no_delete before delete on public.location_block_overrides for each row execute function public.no_hard_delete();

create or replace function public.location_block_override(p_loc int, p_reason text, p_minutes int default 30) returns timestamptz
language plpgsql security definer set search_path = public as $$
declare e timestamptz;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if nullif(btrim(coalesce(p_reason, '')), '') is null then raise exception 'reason_required'; end if;
  if not (coalesce(p_minutes, 0) between 1 and 240) then raise exception 'bad_number'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'unknown_location'; end if;
  e := now() + make_interval(mins => p_minutes);
  insert into public.location_block_overrides (location_id, reason, created_by, expires_at) values (p_loc, left(btrim(p_reason), 300), auth.uid(), e);
  return e;
end $$;

create or replace function public._loc_block_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare st text; sat timestamptz;
begin
  select status, status_at into st, sat from public.locations where id = new.location_id;
  if st in ('paused', 'closed') and public.rule_on('location_block_when_paused') then
    if sat is not null then
      if tg_table_name = 'entries' and (to_jsonb(new) ->> 'entry_date')::date < (sat at time zone 'Asia/Dhaka')::date then return new; end if;
      if tg_table_name = 'sales' and (to_jsonb(new) ->> 'sold_at')::timestamptz < sat then return new; end if;
    end if;
    if exists (select 1 from public.location_block_overrides o where o.location_id = new.location_id and o.expires_at > now()) then return new; end if;
    raise exception 'location_paused:%', st;
  end if;
  return new;
end $$;
drop trigger if exists entries_loc_guard on public.entries;
create trigger entries_loc_guard before insert on public.entries for each row execute function public._loc_block_guard();
drop trigger if exists sales_loc_guard on public.sales;
create trigger sales_loc_guard before insert on public.sales for each row execute function public._loc_block_guard();

-- stock transfers INTO, purchase bills / wastage requests AT a CLOSED place are refused (a paused place only warns: the screens show its status).
create or replace function public._loc_closed_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare lid int := nullif(to_jsonb(new) ->> tg_argv[0], '')::int; st text;
begin
  select status into st from public.locations where id = lid;
  if st = 'closed' and public.rule_on('location_block_when_paused')
     and not exists (select 1 from public.location_block_overrides o where o.location_id = lid and o.expires_at > now()) then raise exception 'location_paused:closed'; end if;
  return new;
end $$;
do $$ declare t record; begin
  for t in select * from (values ('stock_transfers', 'to_location_id'), ('purchase_bills', 'location_id'), ('wastage_requests', 'location_id'), ('stock_wastage', 'location_id')) v(tb, col) loop
    if to_regclass('public.' || t.tb) is not null and exists (select 1 from information_schema.columns c where c.table_schema = 'public' and c.table_name = t.tb and c.column_name = t.col) then
      execute format('drop trigger if exists %I on public.%I', t.tb || '_closed_guard', t.tb);
      execute format('create trigger %I before insert on public.%I for each row execute function public._loc_closed_guard(%L)', t.tb || '_closed_guard', t.tb, t.col);
    end if;
  end loop;
end $$;

-- ---------- (7) settings sheet 0-1 versions ----------
-- the keys a sheet may hold (the 64 keys of the limits screen) with their shape; the owner can add keys with SQL.  Unknown key = refused.
create table if not exists public.settings_keys (
  key text primary key, kind text not null check (kind in ('number', 'text', 'time', 'bool')),
  min_value numeric not null default -1000, max_value numeric not null default 1000000000000, active boolean not null default true
);
alter table public.settings_keys enable row level security;
drop policy if exists settings_keys_read on public.settings_keys;
create policy settings_keys_read on public.settings_keys for select to authenticated using (public.is_active());
revoke all on public.settings_keys from public, anon, authenticated;
grant select on public.settings_keys to authenticated;
drop trigger if exists settings_keys_no_delete on public.settings_keys;
create trigger settings_keys_no_delete before delete on public.settings_keys for each row execute function public.no_hard_delete();
insert into public.settings_keys (key, kind) values
  ('drawer_float', 'number'),
  ('imprest', 'number'),
  ('expense_max', 'number'),
  ('cash_tol', 'number'),
  ('goods_money_tol_pct', 'number'),
  ('goods_money_tol_max', 'number'),
  ('big_sale', 'number'),
  ('avg_daily_sales', 'number'),
  ('discount_limit', 'number'),
  ('refund_limit', 'number'),
  ('hub_cash_max', 'number'),
  ('hub_min_cash', 'number'),
  ('order_hold_days', 'number'),
  ('unclaimed_days', 'number'),
  ('open_time', 'time'),
  ('close_time', 'time'),
  ('busy_day_def', 'text'),
  ('handover_point', 'text'),
  ('crates', 'number'),
  ('trays', 'number'),
  ('fridge1_name', 'text'),
  ('fridge1_min', 'number'),
  ('fridge1_max', 'number'),
  ('fridge2_name', 'text'),
  ('fridge2_min', 'number'),
  ('fridge2_max', 'number'),
  ('fridge3_name', 'text'),
  ('fridge3_min', 'number'),
  ('fridge3_max', 'number'),
  ('shelf_sweet', 'number'),
  ('shelf_cake', 'number'),
  ('shelf_doi', 'number'),
  ('shelf_bakery', 'number'),
  ('daytag_0', 'text'),
  ('daytag_1', 'text'),
  ('daytag_2', 'text'),
  ('daytag_3', 'text'),
  ('daytag_4', 'text'),
  ('daytag_5', 'text'),
  ('daytag_6', 'text'),
  ('waste_classes', 'text'),
  ('count_tol_pct', 'number'),
  ('count_tol_max', 'number'),
  ('quote_over', 'number'),
  ('jalebi_base_pct', 'number'),
  ('jalebi_per_kg_flour', 'number'),
  ('jalebi_tol_pct', 'number'),
  ('jalebi_tol_kg', 'number'),
  ('oil_change_rule', 'text'),
  ('mkt_limit_1', 'number'),
  ('mkt_limit_2', 'number'),
  ('mkt_limit_3', 'number'),
  ('mkt_limit_4', 'number'),
  ('mkt_limit_5', 'number'),
  ('mkt_limit_6', 'number'),
  ('mkt_limit_7', 'number'),
  ('mkt_limit_8', 'number'),
  ('mkt_limit_9', 'number'),
  ('mkt_limit_10', 'number'),
  ('online_order_limit', 'number'),
  ('scale_test', 'text'),
  ('newprod_review_days', 'number'),
  ('fixed_cost_month', 'number'),
  ('anomaly_ratio', 'number')
on conflict (key) do nothing;

create table if not exists public.settings_sheets (
  id bigserial primary key,
  location_id int not null references public.locations(id),
  version int not null,
  status text not null default 'draft' check (status in ('draft', 'approved', 'discarded')),
  effective_from date,
  source text not null default 'sheet' check (source in ('seed', 'sheet', 'legacy')),
  note text,
  created_by uuid, created_at timestamptz not null default now(),
  approved_by uuid, approved_at timestamptz,
  unique (location_id, version)
);
alter table public.settings_sheets add column if not exists base_version int;          -- the version the draft was copied from
alter table public.settings_sheets add column if not exists last_edited_by uuid;
alter table public.settings_sheets add column if not exists applied_at timestamptz;    -- when the version was written through to location_settings
update public.settings_sheets set applied_at = coalesce(approved_at, now()) where applied_at is null and source in ('seed', 'legacy');
create unique index if not exists settings_sheets_one_draft on public.settings_sheets (location_id) where status = 'draft';
create table if not exists public.settings_values (
  sheet_id bigint not null references public.settings_sheets(id),
  key text not null,
  value jsonb,                       -- null = blank = Data needed
  primary key (sheet_id, key)
);
alter table public.settings_sheets enable row level security;
alter table public.settings_values enable row level security;
drop policy if exists settings_sheets_read on public.settings_sheets;
create policy settings_sheets_read on public.settings_sheets for select to authenticated using (public._sheet_viewer_at(location_id));
drop policy if exists settings_values_read on public.settings_values;
create policy settings_values_read on public.settings_values for select to authenticated using (exists (select 1 from public.settings_sheets s where s.id = sheet_id and public._sheet_viewer_at(s.location_id)));
revoke all on public.settings_sheets, public.settings_values from public, anon, authenticated;
grant select on public.settings_sheets, public.settings_values to authenticated;
drop trigger if exists audit_settings_sheets on public.settings_sheets;
create trigger audit_settings_sheets after insert or update on public.settings_sheets for each row execute function public.log_change('id');
drop trigger if exists audit_settings_values on public.settings_values;
create trigger audit_settings_values after insert or update on public.settings_values for each row execute function public.log_change('sheet_id,key');
drop trigger if exists settings_sheets_no_delete on public.settings_sheets;
create trigger settings_sheets_no_delete before delete on public.settings_sheets for each row execute function public.no_hard_delete();
drop trigger if exists settings_values_no_delete on public.settings_values;
create trigger settings_values_no_delete before delete on public.settings_values for each row execute function public.no_hard_delete();
-- an approved version never changes its values (a change is the next version)
create or replace function public._sheet_values_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare st text;
begin
  select status into st from public.settings_sheets where id = new.sheet_id;
  if st is distinct from 'draft' and coalesce(current_setting('bos.sheet_seed', true), '') <> '1' then raise exception 'sheet_not_draft'; end if;
  return new;
end $$;
drop trigger if exists settings_values_guard on public.settings_values;
create trigger settings_values_guard before insert or update on public.settings_values for each row execute function public._sheet_values_guard();

-- version 1 for every place: approved, copied from location_settings (blank = Data needed).  Only places that have no sheet yet.
do $$
declare l record; sid bigint;
begin
  perform set_config('bos.sheet_seed', '1', true);
  for l in select id from public.locations loc where not exists (select 1 from public.settings_sheets s where s.location_id = loc.id) loop
    insert into public.settings_sheets (location_id, version, status, effective_from, source, note, approved_at, applied_at)
      values (l.id, 1, 'approved', date '2000-01-01', 'seed', 'copied from location_settings', now(), now()) returning id into sid;
    insert into public.settings_values (sheet_id, key, value) select sid, ls.key, ls.value from public.location_settings ls where ls.location_id = l.id
      on conflict do nothing;
  end loop;
  perform set_config('bos.sheet_seed', '', true);
end $$;

-- the version in force on a date (latest approved with effective_from <= date; before the first one: the first)
create or replace function public._sheet_in_force(p_loc int, p_date date) returns bigint
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select id from public.settings_sheets where location_id = p_loc and status = 'approved' and effective_from <= p_date order by effective_from desc, version desc limit 1),
    (select id from public.settings_sheets where location_id = p_loc and status = 'approved' order by effective_from, version limit 1));
$$;

-- THE reader: the value in force on that date; NULL = blank = Data needed
create or replace function public.get_limit(p_loc int, p_key text, p_date date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare sid bigint; v jsonb;
begin
  if not (public.is_active() and (public.can_loc(p_loc) or public._sheet_viewer_at(p_loc))) then raise exception 'not allowed'; end if;
  sid := public._sheet_in_force(p_loc, coalesce(p_date, (now() at time zone 'Asia/Dhaka')::date));
  if sid is null then
    select value into v from public.location_settings where location_id = p_loc and key = p_key;
  else
    select value into v from public.settings_values where sheet_id = sid and key = p_key;
  end if;
  if v is null or v = 'null'::jsonb or (jsonb_typeof(v) = 'string' and btrim(v #>> '{}') = '') then return null; end if;
  return v;
end $$;

-- which of these keys are blank at the place on that date
create or replace function public.limit_missing(p_loc int, p_keys text[], p_date date default null) returns text[]
language plpgsql stable security definer set search_path = public as $$
declare k text; res text[] := '{}';
begin
  if not (public.is_active() and (public.can_loc(p_loc) or public._sheet_viewer_at(p_loc))) then raise exception 'not allowed'; end if;
  foreach k in array coalesce(p_keys, '{}') loop
    if public.get_limit(p_loc, k, p_date) is null then res := res || k; end if;
  end loop;
  return res;
end $$;

create or replace function public.sheet_list(p_loc int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._sheet_viewer_at(p_loc) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'version', s.version, 'status', s.status, 'effective_from', s.effective_from, 'source', s.source, 'note', s.note,
      'created_by', s.created_by, 'created_at', s.created_at, 'approved_by', s.approved_by, 'approved_at', s.approved_at, 'base_version', s.base_version,
      'filled', (select count(*) from public.settings_values v where v.sheet_id = s.id and v.value is not null and v.value <> 'null'::jsonb and btrim(v.value #>> '{}') <> ''),
      'blank', (select count(*) from public.settings_values v where v.sheet_id = s.id and (v.value is null or v.value = 'null'::jsonb or btrim(v.value #>> '{}') = '')),
      'in_force', s.id = public._sheet_in_force(p_loc, (now() at time zone 'Asia/Dhaka')::date)) order by s.version desc)
    from public.settings_sheets s where s.location_id = p_loc), '[]');
end $$;

-- the one draft of a place (created from the version in force, remembering which version that was)
create or replace function public._sheet_draft_for(p_loc int, p_uid uuid) returns bigint
language plpgsql security definer set search_path = public as $$
declare d bigint; cur bigint; nv int; bv int;
begin
  perform 1 from public.locations where id = p_loc for update;
  if not found then raise exception 'unknown_location'; end if;
  select id into d from public.settings_sheets where location_id = p_loc and status = 'draft';
  if d is not null then return d; end if;
  select coalesce(max(version), 0) + 1 into nv from public.settings_sheets where location_id = p_loc;
  cur := public._sheet_in_force(p_loc, (now() at time zone 'Asia/Dhaka')::date);
  select version into bv from public.settings_sheets where id = cur;
  insert into public.settings_sheets (location_id, version, status, source, created_by, last_edited_by, base_version) values (p_loc, nv, 'draft', 'sheet', p_uid, p_uid, bv) returning id into d;
  if cur is not null then insert into public.settings_values (sheet_id, key, value) select d, key, value from public.settings_values where sheet_id = cur; end if;
  return d;
end $$;
create or replace function public.sheet_draft(p_loc int) returns bigint
language plpgsql security definer set search_path = public as $$
begin
  if not public._sheet_viewer_at(p_loc) then raise exception 'not allowed'; end if;
  return public._sheet_draft_for(p_loc, auth.uid());
end $$;

-- a value must fit the key: numbers must be real jsonb numbers inside the range (a string such as 'Infinity', 'NaN' or 'abc' is refused for a number key)
create or replace function public._limit_value_ok(p_key text, p_val jsonb) returns jsonb
language plpgsql stable set search_path = public as $$
declare k public.settings_keys; n numeric; t text;
begin
  if p_key is null or p_key !~ '^[a-z0-9_]{1,60}$' then raise exception 'bad_key'; end if;
  select * into k from public.settings_keys where key = p_key and active;
  if not found and not exists (select 1 from public.location_settings where key = p_key) then raise exception 'unknown_key'; end if;
  if p_val is null or p_val = 'null'::jsonb then return null; end if;
  if k.key is null then   -- only known from old location_settings rows: any sane scalar
    if jsonb_typeof(p_val) = 'number' then
      if not ((p_val #>> '{}')::numeric between -1000000000000 and 1000000000000) then raise exception 'bad_number'; end if; return p_val;
    elsif jsonb_typeof(p_val) = 'string' then
      t := btrim(p_val #>> '{}'); if length(t) > 200 or lower(t) in ('infinity', '-infinity', 'nan') then raise exception 'bad_value'; end if; return case when t = '' then null else to_jsonb(t) end;
    elsif jsonb_typeof(p_val) = 'boolean' then return p_val; end if;
    raise exception 'bad_value';
  end if;
  if k.kind = 'number' then
    if jsonb_typeof(p_val) <> 'number' then raise exception 'bad_value'; end if;
    n := (p_val #>> '{}')::numeric;
    if not (n between k.min_value and k.max_value) then raise exception 'bad_number'; end if;
    return p_val;
  elsif k.kind = 'time' then
    if jsonb_typeof(p_val) <> 'string' then raise exception 'bad_value'; end if;
    t := btrim(p_val #>> '{}'); if t = '' then return null; end if;
    if t !~ '^([01]?[0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'bad_value'; end if;
    return to_jsonb(t);
  elsif k.kind = 'bool' then
    if jsonb_typeof(p_val) <> 'boolean' then raise exception 'bad_value'; end if; return p_val;
  end if;
  if jsonb_typeof(p_val) <> 'string' then raise exception 'bad_value'; end if;
  t := btrim(p_val #>> '{}'); if length(t) > 200 then raise exception 'too_long:value'; end if;
  return case when t = '' then null else to_jsonb(t) end;
end $$;

create or replace function public.sheet_set(p_sheet bigint, p_values jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare s public.settings_sheets; k text; n int := 0;
begin
  if p_values is null or jsonb_typeof(p_values) <> 'object' then raise exception 'bad_patch'; end if;
  select * into s from public.settings_sheets where id = p_sheet for update;
  if not found then raise exception 'unknown_sheet'; end if;
  if not public._sheet_viewer_at(s.location_id) then raise exception 'not allowed'; end if;
  if s.status <> 'draft' then raise exception 'sheet_not_draft'; end if;
  for k in select jsonb_object_keys(p_values) loop
    insert into public.settings_values (sheet_id, key, value) values (p_sheet, k, public._limit_value_ok(k, p_values->k))
      on conflict (sheet_id, key) do update set value = excluded.value;
    n := n + 1;
  end loop;
  update public.settings_sheets set last_edited_by = auth.uid() where id = p_sheet;
  return n;
end $$;

create or replace function public.sheet_discard(p_sheet bigint) returns void
language plpgsql security definer set search_path = public as $$
declare s public.settings_sheets;
begin
  select * into s from public.settings_sheets where id = p_sheet for update;
  if not found then raise exception 'unknown_sheet'; end if;
  if not public._sheet_viewer_at(s.location_id) then raise exception 'not allowed'; end if;
  if s.status <> 'draft' then raise exception 'sheet_not_draft'; end if;
  if s.created_by is distinct from auth.uid() and not public.is_owner() then raise exception 'not allowed'; end if;
  update public.settings_sheets set status = 'discarded' where id = p_sheet;
end $$;

-- write the version in force today through to location_settings (old screens and server functions keep reading location_settings)
create or replace function public._sheet_writethrough(p_loc int) returns void
language plpgsql security definer set search_path = public as $$
declare sid bigint; today date := (now() at time zone 'Asia/Dhaka')::date;
begin
  sid := public._sheet_in_force(p_loc, today);
  if sid is null then return; end if;
  perform set_config('bos.sheet_sync', '1', true);
  insert into public.location_settings (location_id, key, value, updated_by)
    select p_loc, v.key, v.value, auth.uid() from public.settings_values v where v.sheet_id = sid
  on conflict (location_id, key) do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
  perform set_config('bos.sheet_sync', '', true);
  update public.settings_sheets set applied_at = now() where location_id = p_loc and status = 'approved' and effective_from <= today and applied_at is null;
end $$;

-- there is no scheduler: a future-dated version is written through lazily, by this cheap check (does nothing when nothing is due).
-- It runs from control_counts() (every Home load of an owner / delegate), location_save, sheet_approve and sheet_sync_all().
-- get_limit() itself is always right by date; only code that reads location_settings DIRECTLY (record_sale2 ...) sees the new value after one of these ran.
create or replace function public._sheet_sync_due() returns int
language plpgsql security definer set search_path = public as $$
declare l record; n int := 0;
begin
  for l in select distinct location_id from public.settings_sheets where status = 'approved' and applied_at is null and effective_from <= (now() at time zone 'Asia/Dhaka')::date loop
    perform public._sheet_writethrough(l.location_id); n := n + 1;
  end loop;
  return n;
end $$;

create or replace function public.sheet_approve(p_sheet bigint, p_effective date default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.settings_sheets; eff date; lastd date; firstd date; today date := (now() at time zone 'Asia/Dhaka')::date; exempt boolean;
begin
  select * into s from public.settings_sheets where id = p_sheet for update;
  if not found then raise exception 'unknown_sheet'; end if;
  if not (public.is_owner() or (public.is_active() and public.has_grant('settings_approve', s.location_id))) then raise exception 'not allowed'; end if;
  if s.status <> 'draft' then raise exception 'sheet_not_draft'; end if;
  exempt := public.is_owner() and public.rule_on('owner_self_approve');
  -- the approver is neither the person who started the draft nor the last person who edited it
  if not exempt and (s.created_by is not distinct from auth.uid() or s.last_edited_by is not distinct from auth.uid()) then raise exception 'maker_cannot_approve'; end if;
  -- a newer version was approved since this draft was copied: refuse (start a new draft from the current version)
  if exists (select 1 from public.settings_sheets x where x.location_id = s.location_id and x.status = 'approved' and x.version > coalesce(s.base_version, 0)) then raise exception 'newer_version_exists'; end if;
  eff := coalesce(p_effective, today);
  select coalesce((select l.created_at::date from public.locations l where l.id = s.location_id and l.created_by is not null), date '2000-01-01') into firstd;
  if eff < firstd then raise exception 'effective_too_early'; end if;
  if eff > today + 365 then raise exception 'effective_too_far'; end if;
  select max(effective_from) into lastd from public.settings_sheets where location_id = s.location_id and status = 'approved' and source <> 'seed';
  if lastd is not null and eff < lastd then raise exception 'effective_before_previous'; end if;
  update public.settings_sheets set status = 'approved', effective_from = eff, approved_by = auth.uid(), approved_at = now(), note = coalesce(nullif(btrim(p_note), ''), note) where id = p_sheet;
  perform public._sheet_writethrough(s.location_id);
  return jsonb_build_object('ok', true, 'version', s.version, 'effective_from', eff);
end $$;

create or replace function public.sheet_sync_all() returns int
language plpgsql security definer set search_path = public as $$
declare l record; n int := 0;
begin
  if not public._sheet_viewer() then raise exception 'not allowed'; end if;
  for l in select id from public.locations loop perform public._sheet_writethrough(l.id); n := n + 1; end loop;
  return n;
end $$;

-- the OLD screen (#/locset) writes location_settings directly (owner only, RLS).  Keep it working AND versioned:
--  * owner_self_approve ON : a direct change makes a new approved version (source 'legacy', effective today, copied from the version in force TODAY);
--    the same person changing again the same day edits that version.
--  * owner_self_approve OFF: the direct change is NOT applied; it goes into the draft (someone else approves it) and location_settings keeps the old value.
create or replace function public._ls_legacy() returns trigger
language plpgsql security definer set search_path = public as $$
declare cur public.settings_sheets; nv int; sid bigint; did bigint; today date := (now() at time zone 'Asia/Dhaka')::date; me uuid := auth.uid();
begin
  if coalesce(current_setting('bos.sheet_sync', true), '') = '1' then return new; end if;
  if tg_op = 'UPDATE' and old.value is not distinct from new.value then return new; end if;
  if me is not null and public.is_owner() and not public.rule_on('owner_self_approve') then
    did := public._sheet_draft_for(new.location_id, me);
    insert into public.settings_values (sheet_id, key, value) values (did, new.key, new.value) on conflict (sheet_id, key) do update set value = excluded.value;
    update public.settings_sheets set last_edited_by = me where id = did;
    perform set_config('bos.sheet_sync', '1', true);
    if tg_op = 'UPDATE' then update public.location_settings set value = old.value where location_id = new.location_id and key = new.key;
    else update public.location_settings set value = null where location_id = new.location_id and key = new.key; end if;
    perform set_config('bos.sheet_sync', '', true);
    return new;
  end if;
  perform set_config('bos.sheet_seed', '1', true);
  select * into cur from public.settings_sheets where id = public._sheet_in_force(new.location_id, today);
  if not found then
    insert into public.settings_sheets (location_id, version, status, effective_from, source, note, approved_at, applied_at) values (new.location_id, 1, 'approved', date '2000-01-01', 'seed', 'created by a direct settings change', now(), now()) returning id into sid;
  elsif cur.source = 'legacy' and cur.effective_from = today and cur.approved_by is not distinct from me and cur.version = (select max(version) from public.settings_sheets where location_id = new.location_id and status = 'approved') then
    sid := cur.id;
  else
    select coalesce(max(version), 0) + 1 into nv from public.settings_sheets where location_id = new.location_id;
    insert into public.settings_sheets (location_id, version, status, effective_from, source, note, created_by, approved_by, approved_at, applied_at, base_version)
      values (new.location_id, nv, 'approved', today, 'legacy', 'changed on the old limits screen', me, me, now(), now(), cur.version) returning id into sid;
    insert into public.settings_values (sheet_id, key, value) select sid, key, value from public.settings_values where sheet_id = cur.id on conflict do nothing;
  end if;
  insert into public.settings_values (sheet_id, key, value) values (sid, new.key, new.value)
    on conflict (sheet_id, key) do update set value = excluded.value;
  perform set_config('bos.sheet_seed', '', true);
  return new;
end $$;
drop trigger if exists location_settings_legacy on public.location_settings;
create trigger location_settings_legacy after insert or update on public.location_settings for each row execute function public._ls_legacy();

-- a new place gets its (blank) version 1 too
create or replace function public._loc_sheet_v1() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.settings_sheets (location_id, version, status, effective_from, source, note, approved_at, applied_at)
    values (new.id, 1, 'approved', date '2000-01-01', 'seed', 'blank: every value needs data', now(), now()) on conflict (location_id, version) do nothing;
  return new;
end $$;
drop trigger if exists locations_sheet_v1 on public.locations;
create trigger locations_sheet_v1 after insert on public.locations for each row execute function public._loc_sheet_v1();

-- ---------- (8) Control Center: what waits for the caller ----------
create or replace function public.control_counts() returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare own boolean := public.is_owner(); hd boolean; lm boolean; sa boolean; lg boolean; res jsonb := '{}'; n int; q jsonb;
begin
  if not public.is_active() then return '{}'::jsonb; end if;
  perform public._sheet_sync_due();
  hd := public.has_grant('head_management'); lm := public.has_grant('location_manage'); sa := public.has_grant('settings_approve'); lg := public.has_grant('list_manage');
  res := jsonb_build_object('tier', case when own then 'owner' when hd then 'head' else 'delegate' end);
  if own then
    select count(*) into n from public.item_changes where status = 'pending'; res := res || jsonb_build_object('item_requests', n);
    select count(*) into n from public.exceptions where status = 'open'; res := res || jsonb_build_object('exceptions', n);
    select count(*) into n from public.release_requests where status = 'pending'; res := res || jsonb_build_object('releases', n);
    select count(*) into n from public.emergency_requests where status = 'pending'; res := res || jsonb_build_object('emergency', n);
    select count(*) into n from public.profiles where status = 'pending'; res := res || jsonb_build_object('staff_pending', n);
    select count(*) into n from public.wastage_requests where status = 'pending'; res := res || jsonb_build_object('wastage', n);
  end if;
  if own or hd or lm then
    select count(*) into n from public.locations where status in ('planned', 'setting_up'); res := res || jsonb_build_object('location_setup', n);
  end if;
  if own or hd or sa then
    select count(*) into n from public.settings_sheets where status = 'draft'; res := res || jsonb_build_object('settings_drafts', n);
  end if;
  -- the list queue is for people who may DECIDE it (the list_manage grant); head_management alone does not (the server would refuse the Lists screen)
  if (own or lg) and to_regprocedure('public.list_queue_counts()') is not null then
    execute 'select public.list_queue_counts()' into q;
    res := res || jsonb_build_object('lists', coalesce((q->>'requests')::int, 0) + coalesce((q->>'other')::int, 0));
  end if;
  return res;
end $$;

-- ---------- (9) privileges ----------
revoke all on function public._loc_mgr(), public._sheet_viewer(), public._loc_mgr_at(int), public._sheet_viewer_at(int), public._loc_steps_def(), public._loc_steps_seed(int), public._slug(text), public._loc_open_steps(int),
  public._loc_block_guard(), public._loc_closed_guard(), public._loc_status_guard(), public._sheet_values_guard(), public._sheet_in_force(int, date), public._limit_value_ok(text, jsonb), public._sheet_writethrough(int),
  public._sheet_sync_due(), public._sheet_draft_for(int, uuid), public._ls_legacy(), public._loc_sheet_v1(),
  public.location_save(int, jsonb), public.location_close_check(int), public.location_set_status(int, text, text, boolean), public.location_set_active(int, boolean),
  public.location_steps_init(int), public.location_step_set(int, int, boolean, text), public.location_block_override(int, text, int),
  public.get_limit(int, text, date), public.limit_missing(int, text[], date), public.sheet_list(int), public.sheet_draft(int), public.sheet_set(bigint, jsonb),
  public.sheet_discard(bigint), public.sheet_approve(bigint, date, text), public.sheet_sync_all(), public.control_counts() from public, anon, authenticated;
grant execute on function public.location_save(int, jsonb), public.location_close_check(int), public.location_set_status(int, text, text, boolean), public.location_set_active(int, boolean),
  public.location_steps_init(int), public.location_step_set(int, int, boolean, text), public.location_block_override(int, text, int),
  public.get_limit(int, text, date), public.limit_missing(int, text[], date), public.sheet_list(int), public.sheet_draft(int), public.sheet_set(bigint, jsonb),
  public.sheet_discard(bigint), public.sheet_approve(bigint, date, text), public.sheet_sync_all(), public.control_counts(), public._loc_mgr(), public._sheet_viewer(), public._loc_mgr_at(int), public._sheet_viewer_at(int) to authenticated;
