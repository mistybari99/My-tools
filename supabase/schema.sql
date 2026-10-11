-- ============================================================
-- BOS tool · Phase 1 schema (Supabase / Postgres)
-- Run once in Supabase: SQL Editor -> paste all -> Run.
-- Safe to re-run? NO for the first run on a fresh project only.
-- ============================================================

-- ---------- Tables ----------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  staff_id text not null unique,
  full_name text not null default '',
  status text not null default 'pending' check (status in ('pending','active','disabled')),
  lang text not null default 'bn' check (lang in ('bn','mix','en')),
  created_at timestamptz not null default now()
);

create table public.roles (
  code text primary key,
  name_bn text not null, name_mix text, name_en text,
  sort int not null default 0,
  allow_self_approve boolean not null default false,
  active boolean not null default true
);

create table public.user_roles (
  user_id uuid not null references public.profiles(id) on delete cascade,
  role_code text not null references public.roles(code),
  primary key (user_id, role_code)
);

create table public.locations (
  id serial primary key,
  code text not null unique,
  name_bn text not null, name_mix text, name_en text,
  sort int not null default 0,
  is_active boolean not null default true
);

create table public.user_locations (
  user_id uuid not null references public.profiles(id) on delete cascade,
  location_id int not null references public.locations(id),
  primary key (user_id, location_id)
);

create table public.forms (
  code text primary key,
  area text not null,
  name_bn text not null, name_mix text, name_en text,
  version text,
  sort int not null default 0,
  count_first boolean not null default true,   -- count before system figure is shown
  red_block boolean not null default true,     -- red control blocks day close
  enabled boolean not null default true
);

create table public.role_form_perms (
  role_code text not null references public.roles(code) on delete cascade,
  form_code text not null references public.forms(code) on delete cascade,
  can_view boolean not null default false,
  can_enter boolean not null default false,
  can_approve boolean not null default false,
  primary key (role_code, form_code)
);

create sequence public.item_code_seq;
create table public.items (
  id uuid primary key default gen_random_uuid(),
  code text not null unique default ('I-' || lpad(nextval('public.item_code_seq')::text, 3, '0')),
  name_bn text not null, name_en text, name_mix text,
  category text, category_bn text,
  unit text,
  sell_price numeric(12,2) check (sell_price >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid
);

-- Cost price lives apart so it can be hidden from roles without the ITEM_COST permission.
create table public.item_costs (
  item_id uuid primary key references public.items(id) on delete cascade,
  cost_price numeric(12,2) check (cost_price >= 0),
  updated_at timestamptz not null default now(),
  updated_by uuid
);

-- Every item/price change by anyone but the owner waits here for final approval.
create table public.item_changes (
  id bigserial primary key,
  item_id uuid references public.items(id),     -- null = proposal to create a new item
  patch jsonb not null,
  note text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  requested_by uuid not null, requested_staff text, requested_at timestamptz not null default now(),
  decided_by uuid, decided_staff text, decided_at timestamptz, decision_note text
);

create table public.item_price_history (
  id bigserial primary key,
  item_id uuid not null references public.items(id),
  sell_price numeric(12,2), cost_price numeric(12,2),   -- one of them per row (the one that changed)
  changed_at timestamptz not null default now(),
  changed_by uuid
);

create table public.settings (
  key text primary key,
  value jsonb,                 -- null means "data needed"
  label_bn text, label_mix text, label_en text,
  updated_at timestamptz not null default now(),
  updated_by uuid
);

create table public.audit_log (
  id bigserial primary key,
  at timestamptz not null default now(),
  user_id uuid, staff_id text,
  action text not null, table_name text not null, record_id text,
  detail jsonb
);

create table public.corrections (
  id bigserial primary key,
  at timestamptz not null default now(),
  user_id uuid not null, staff_id text,
  form_code text, entry_id text,
  note text not null check (length(btrim(note)) > 0),
  before jsonb, after jsonb
);

create table public.login_failures (
  staff_id text primary key,
  fails int not null default 0,
  locked boolean not null default false,
  last_fail timestamptz not null default now()
);

-- ---------- Helper functions ----------
create or replace function public.is_active() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and status = 'active');
$$;

create or replace function public.is_owner() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and exists (
    select 1 from public.user_roles where user_id = auth.uid() and role_code = 'owner');
$$;

-- action: 'view' | 'enter' | 'approve'
create or replace function public.can_do(p_form text, p_action text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or (
    public.is_active() and exists (
      select 1 from public.user_roles ur
      join public.role_form_perms p on p.role_code = ur.role_code and p.form_code = p_form
      join public.roles r on r.code = ur.role_code and r.active
      where ur.user_id = auth.uid()
        and case p_action when 'view' then p.can_view when 'enter' then p.can_enter
                          when 'approve' then p.can_approve else false end));
$$;

-- ---------- Triggers ----------
-- New auth user -> profile. The very first user becomes the active owner.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare first_user boolean;
begin
  select not exists (select 1 from public.profiles) into first_user;
  insert into public.profiles (id, staff_id, full_name, status)
  values (new.id, lower(split_part(new.email, '@', 1)),
          coalesce(new.raw_user_meta_data->>'full_name', ''),
          case when first_user then 'active' else 'pending' end);
  if first_user then
    insert into public.user_roles (user_id, role_code) values (new.id, 'owner');
  end if;
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Generic audit trigger. tg_argv[0] = comma separated key columns.
create or replace function public.log_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  o jsonb; n jsonb; k text; oldd jsonb := '{}'; newd jsonb := '{}';
  cols text[] := string_to_array(tg_argv[0], ','); c text; rid text := ''; src jsonb; sid text;
begin
  if tg_op = 'DELETE' then src := to_jsonb(old); else src := to_jsonb(new); end if;
  foreach c in array cols loop rid := rid || case when rid = '' then '' else ':' end || coalesce(src->>c, ''); end loop;
  select staff_id into sid from public.profiles where id = auth.uid();
  if tg_op = 'UPDATE' then
    o := to_jsonb(old); n := to_jsonb(new);
    for k in select jsonb_object_keys(n) loop
      if n->k is distinct from o->k then oldd := oldd || jsonb_build_object(k, o->k); newd := newd || jsonb_build_object(k, n->k); end if;
    end loop;
    if newd = '{}'::jsonb then return new; end if;
    insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
      values (auth.uid(), sid, 'update', tg_table_name, rid, jsonb_build_object('old', oldd, 'new', newd));
    return new;
  elsif tg_op = 'INSERT' then
    insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
      values (auth.uid(), sid, 'insert', tg_table_name, rid, jsonb_build_object('new', to_jsonb(new)));
    return new;
  else
    insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
      values (auth.uid(), sid, 'delete', tg_table_name, rid, jsonb_build_object('old', to_jsonb(old)));
    return old;
  end if;
end $$;

create trigger audit_items after insert or update on public.items for each row execute function public.log_change('id');
create trigger audit_item_costs after insert or update on public.item_costs for each row execute function public.log_change('item_id');
create trigger audit_item_changes after insert or update on public.item_changes for each row execute function public.log_change('id');
create trigger audit_roles after insert or update on public.roles for each row execute function public.log_change('code');
create trigger audit_forms after insert or update on public.forms for each row execute function public.log_change('code');
create trigger audit_locations after insert or update on public.locations for each row execute function public.log_change('id');
create trigger audit_settings after insert or update on public.settings for each row execute function public.log_change('key');
create trigger audit_profiles after update on public.profiles for each row execute function public.log_change('id');
create trigger audit_user_roles after insert or delete on public.user_roles for each row execute function public.log_change('user_id,role_code');
create trigger audit_user_locations after insert or delete on public.user_locations for each row execute function public.log_change('user_id,location_id');
create trigger audit_perms after insert or update or delete on public.role_form_perms for each row execute function public.log_change('role_code,form_code');

-- Items: code never changes; price history; who/when
create or replace function public.items_before() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.code is distinct from old.code then
    raise exception 'item code cannot be changed';
  end if;
  new.updated_at := now(); new.updated_by := auth.uid();
  return new;
end $$;
create trigger items_before before insert or update on public.items
  for each row execute function public.items_before();

create or replace function public.items_price_history() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' or new.sell_price is distinct from old.sell_price then
    insert into public.item_price_history (item_id, sell_price, changed_by) values (new.id, new.sell_price, auth.uid());
  end if;
  return new;
end $$;
create trigger items_price_history after insert or update on public.items
  for each row execute function public.items_price_history();

create or replace function public.item_costs_history() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now(); new.updated_by := auth.uid();
  return new;
end $$;
create trigger item_costs_before before insert or update on public.item_costs
  for each row execute function public.item_costs_history();

create or replace function public.item_costs_history_after() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' or new.cost_price is distinct from old.cost_price then
    insert into public.item_price_history (item_id, cost_price, changed_by) values (new.item_id, new.cost_price, auth.uid());
  end if;
  return new;
end $$;
create trigger item_costs_history_after after insert or update on public.item_costs
  for each row execute function public.item_costs_history_after();

-- Never leave the business without an active owner
create or replace function public.guard_last_owner() returns trigger
language plpgsql security definer set search_path = public as $$
declare uid uuid; others int;
begin
  if tg_table_name = 'user_roles' then
    if old.role_code <> 'owner' then return old; end if;
    uid := old.user_id;
  else
    if not (old.status = 'active' and new.status <> 'active') then return new; end if;
    uid := old.id;
    if not exists (select 1 from public.user_roles where user_id = uid and role_code = 'owner') then return new; end if;
  end if;
  select count(*) into others from public.user_roles ur join public.profiles p on p.id = ur.user_id
    where ur.role_code = 'owner' and p.status = 'active' and ur.user_id <> uid;
  if others = 0 then raise exception 'at least one active owner is required'; end if;
  if tg_table_name = 'user_roles' then return old; else return new; end if;
end $$;
create trigger guard_owner_roles before delete on public.user_roles for each row execute function public.guard_last_owner();
create trigger guard_owner_profile before update on public.profiles for each row execute function public.guard_last_owner();

-- Audit and login-failure tables are append-only for everyone but the system
-- (no update/delete privileges are granted below)

-- ---------- RPC (called by the app) ----------
create or replace function public.my_context() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare p public.profiles; owner boolean; perms jsonb; roles_ jsonb; locs jsonb;
begin
  select * into p from public.profiles where id = auth.uid();
  if not found then return null; end if;
  owner := p.status = 'active' and exists (select 1 from public.user_roles where user_id = p.id and role_code = 'owner');
  select coalesce(jsonb_agg(role_code), '[]') into roles_ from public.user_roles where user_id = p.id;
  select coalesce(jsonb_agg(location_id), '[]') into locs from public.user_locations where user_id = p.id;
  if p.status <> 'active' then perms := '{}'::jsonb;
  elsif owner then
    select coalesce(jsonb_object_agg(code, jsonb_build_object('view', true, 'enter', true, 'approve', true)), '{}') into perms from public.forms;
  else
    select coalesce(jsonb_object_agg(form_code, jsonb_build_object('view', v, 'enter', e, 'approve', a)), '{}') into perms from (
      select pf.form_code, bool_or(pf.can_view) v, bool_or(pf.can_enter) e, bool_or(pf.can_approve) a
      from public.user_roles ur join public.role_form_perms pf on pf.role_code = ur.role_code
      join public.roles r on r.code = ur.role_code and r.active
      where ur.user_id = p.id group by pf.form_code) x;
  end if;
  return jsonb_build_object('profile', to_jsonb(p), 'is_owner', owner, 'roles', roles_, 'locations', locs, 'perms', perms);
end $$;

create or replace function public.set_my_lang(p_lang text) returns void
language sql security definer set search_path = public as $$
  update public.profiles set lang = p_lang where id = auth.uid() and p_lang in ('bn','mix','en');
$$;

-- Login lock: after max_fails wrong PINs the account is locked until the owner unlocks it.
create or replace function public.login_precheck(p_staff text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('locked', coalesce((select locked from public.login_failures where staff_id = lower(p_staff)), false));
$$;

create or replace function public.login_failed(p_staff text) returns void
language plpgsql security definer set search_path = public as $$
declare mx int := coalesce((select (value #>> '{}')::int from public.settings where key = 'max_fails'), 5);
begin
  if not exists (select 1 from public.profiles where staff_id = lower(p_staff)) then return; end if;
  insert into public.login_failures (staff_id, fails, locked) values (lower(p_staff), 1, 1 >= mx)
  on conflict (staff_id) do update set fails = public.login_failures.fails + 1,
      locked = public.login_failures.fails + 1 >= mx, last_fail = now();
end $$;

create or replace function public.login_success() returns void
language sql security definer set search_path = public as $$
  delete from public.login_failures where staff_id = (select staff_id from public.profiles where id = auth.uid());
$$;

create or replace function public.unlock_staff(p_staff text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'owner only'; end if;
  delete from public.login_failures where staff_id = lower(p_staff);
end $$;

-- ---------- Item change workflow ----------
-- Apply a patch to items (+ item_costs). Internal helper, not exposed to the app.
create or replace function public.apply_item_patch(p_item uuid, p_patch jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare iid uuid := p_item; cp numeric;
begin
  if iid is null then
    insert into public.items (name_bn, name_en, name_mix, category, category_bn, unit, sell_price, is_active)
    values (p_patch->>'name_bn', p_patch->>'name_en', p_patch->>'name_mix', p_patch->>'category', p_patch->>'category_bn',
            p_patch->>'unit', nullif(p_patch->>'sell_price','')::numeric, coalesce((p_patch->>'is_active')::boolean, true))
    returning id into iid;
  else
    update public.items set
      name_bn = coalesce(p_patch->>'name_bn', name_bn),
      name_en = case when p_patch ? 'name_en' then p_patch->>'name_en' else name_en end,
      name_mix = case when p_patch ? 'name_mix' then p_patch->>'name_mix' else name_mix end,
      category = case when p_patch ? 'category' then p_patch->>'category' else category end,
      category_bn = case when p_patch ? 'category_bn' then p_patch->>'category_bn' else category_bn end,
      unit = case when p_patch ? 'unit' then p_patch->>'unit' else unit end,
      sell_price = case when p_patch ? 'sell_price' then nullif(p_patch->>'sell_price','')::numeric else sell_price end,
      is_active = case when p_patch ? 'is_active' then (p_patch->>'is_active')::boolean else is_active end
    where id = iid;
  end if;
  if p_patch ? 'cost_price' then
    cp := nullif(p_patch->>'cost_price','')::numeric;
    insert into public.item_costs (item_id, cost_price) values (iid, cp)
      on conflict (item_id) do update set cost_price = excluded.cost_price;
  end if;
  return iid;
end $$;

-- Anyone allowed to enter ITEMS submits here. Owner's change is applied at once;
-- everyone else's waits for an approver.  Changing cost needs ITEM_COST 'enter'.
create or replace function public.submit_item_change(p_item uuid, p_patch jsonb, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare sid text; cid bigint;
begin
  if not public.can_do('ITEMS', 'enter') then raise exception 'not allowed'; end if;
  if p_patch ? 'cost_price' and not public.can_do('ITEM_COST', 'enter') then raise exception 'not allowed to change cost'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if public.is_owner() then
    return jsonb_build_object('status', 'applied', 'item_id', public.apply_item_patch(p_item, p_patch));
  end if;
  insert into public.item_changes (item_id, patch, note, requested_by, requested_staff)
    values (p_item, p_patch, p_note, auth.uid(), sid) returning id into cid;
  return jsonb_build_object('status', 'pending', 'id', cid);
end $$;

create or replace function public.decide_item_change(p_id bigint, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.item_changes; sid text; self_ok boolean;
begin
  if not (public.is_owner() or public.can_do('ITEMS', 'approve')) then raise exception 'not allowed'; end if;
  select * into c from public.item_changes where id = p_id for update;
  if not found or c.status <> 'pending' then raise exception 'request is not pending'; end if;
  self_ok := public.is_owner() or exists (select 1 from public.user_roles ur join public.roles r on r.code = ur.role_code
              where ur.user_id = auth.uid() and r.allow_self_approve);
  if c.requested_by = auth.uid() and not self_ok then raise exception 'you cannot approve your own request'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if p_approve then perform public.apply_item_patch(c.item_id, c.patch); end if;
  update public.item_changes set status = case when p_approve then 'approved' else 'rejected' end,
    decided_by = auth.uid(), decided_staff = sid, decided_at = now(), decision_note = p_note where id = p_id;
  return jsonb_build_object('status', case when p_approve then 'approved' else 'rejected' end);
end $$;

-- ---------- Privileges (Data API: nothing is open by default) ----------
revoke all on all tables in schema public from anon, authenticated;
revoke all on all functions in schema public from public;
grant usage on schema public to anon, authenticated;

grant select on public.profiles, public.roles, public.user_roles, public.locations, public.user_locations,
  public.forms, public.role_form_perms, public.items, public.item_price_history, public.settings,
  public.audit_log, public.corrections, public.login_failures, public.item_costs, public.item_changes to authenticated;
grant update on public.profiles to authenticated;
grant insert, update, delete on public.user_roles, public.user_locations, public.role_form_perms to authenticated;
grant insert, update on public.roles, public.locations, public.forms, public.settings to authenticated;
grant insert on public.corrections to authenticated;
grant usage on sequence public.audit_log_id_seq, public.corrections_id_seq to authenticated;

grant execute on function public.is_active(), public.is_owner(), public.can_do(text, text),
  public.my_context(), public.set_my_lang(text), public.login_success(), public.unlock_staff(text),
  public.submit_item_change(uuid, jsonb, text), public.decide_item_change(bigint, boolean, text) to authenticated;
grant execute on function public.login_precheck(text), public.login_failed(text) to anon, authenticated;

-- ---------- Row Level Security ----------
alter table public.profiles enable row level security;
alter table public.roles enable row level security;
alter table public.user_roles enable row level security;
alter table public.locations enable row level security;
alter table public.user_locations enable row level security;
alter table public.forms enable row level security;
alter table public.role_form_perms enable row level security;
alter table public.items enable row level security;
alter table public.item_price_history enable row level security;
alter table public.item_costs enable row level security;
alter table public.item_changes enable row level security;
alter table public.settings enable row level security;
alter table public.audit_log enable row level security;
alter table public.corrections enable row level security;
alter table public.login_failures enable row level security;   -- written only by security-definer functions; the owner may read it

create policy profiles_read on public.profiles for select to authenticated using (id = auth.uid() or public.is_owner());
create policy profiles_owner_update on public.profiles for update to authenticated using (public.is_owner()) with check (public.is_owner());

create policy roles_read on public.roles for select to authenticated using (public.is_active());
create policy roles_owner_write on public.roles for all to authenticated using (public.is_owner()) with check (public.is_owner());

create policy user_roles_read on public.user_roles for select to authenticated using (user_id = auth.uid() or public.is_owner());
create policy user_roles_owner_write on public.user_roles for all to authenticated using (public.is_owner()) with check (public.is_owner());

create policy locations_read on public.locations for select to authenticated using (public.is_active());
create policy locations_owner_write on public.locations for all to authenticated using (public.is_owner()) with check (public.is_owner());

create policy user_locations_read on public.user_locations for select to authenticated using (user_id = auth.uid() or public.is_owner());
create policy user_locations_owner_write on public.user_locations for all to authenticated using (public.is_owner()) with check (public.is_owner());

create policy forms_read on public.forms for select to authenticated using (public.is_active());
create policy forms_owner_write on public.forms for all to authenticated using (public.is_owner()) with check (public.is_owner());

create policy perms_read on public.role_form_perms for select to authenticated using (public.is_active());
create policy perms_owner_write on public.role_form_perms for all to authenticated using (public.is_owner()) with check (public.is_owner());

create policy items_read on public.items for select to authenticated using (public.is_active());
-- items are written only through submit_item_change / decide_item_change (no direct insert/update)

create policy item_costs_read on public.item_costs for select to authenticated using (public.can_do('ITEM_COST', 'view'));
create policy item_changes_read on public.item_changes for select to authenticated
  using (requested_by = auth.uid() or public.is_owner() or public.can_do('ITEMS', 'approve'));
create policy price_history_read on public.item_price_history for select to authenticated using (public.can_do('ITEM_COST', 'view'));

create policy settings_read on public.settings for select to authenticated using (public.is_active());
create policy settings_owner_write on public.settings for all to authenticated using (public.is_owner()) with check (public.is_owner());

create policy login_failures_owner_read on public.login_failures for select to authenticated using (public.is_owner());

create policy audit_owner_read on public.audit_log for select to authenticated using (public.is_owner());

create policy corrections_read on public.corrections for select to authenticated using (public.is_owner() or user_id = auth.uid());
create policy corrections_insert on public.corrections for insert to authenticated with check (user_id = auth.uid() and public.is_active());

-- ---------- Seed data ----------
insert into public.roles (code, name_bn, name_mix, name_en, sort) values
  ('owner','মালিক','মালিক (Owner)','Owner',1),
  ('management','ব্যবস্থাপনা','ব্যবস্থাপনা (Management)','Management',2),
  ('cash_controller','ক্যাশ নিয়ন্ত্রক','Cash নিয়ন্ত্রক','Cash Controller',3),
  ('showroom_manager','শোরুম ম্যানেজার','Showroom Manager','Showroom Manager',4),
  ('salesperson','বিক্রয়কারী','বিক্রয়কারী (Salesperson)','Salesperson',5),
  ('storekeeper','স্টোরকিপার','Storekeeper','Storekeeper',6),
  ('factory_incharge','কারখানা ইনচার্জ','Factory ইনচার্জ','Factory In-charge',7),
  ('purchasing','ক্রয় (দর সংগ্রহ)','ক্রয় (Purchasing)','Purchasing',8),
  ('party_coordinator','পার্টি ও পাইকারি সমন্বয়ক','Party ও Wholesale সমন্বয়ক','Party & Wholesale Coordinator',9),
  ('carrier','বাহক','বাহক (Carrier)','Carrier',10),
  ('hr','এইচআর ও প্রশাসন','HR ও প্রশাসন','HR & Admin',11);

insert into public.locations (code, name_bn, name_mix, name_en, sort) values
  ('main','ইসলামিয়া মেইন','ইসলামিয়া Main','Islamia Main',1),
  ('branch2','২য় শাখা','২য় Branch','2nd Branch',2),
  ('mishti_bari','মিষ্টি বাড়ি','মিষ্টি বাড়ি','Mishti Bari',3),
  ('al_cakes','আল-কেকিজ','আল-কেকিজ','Al-Cakes',4),
  ('mishti_factory','মিষ্টি কারখানা','মিষ্টি Factory','Sweet Factory',5),
  ('cake_factory','কেক কারখানা','কেক Factory','Cake Factory',6),
  ('godown','গোডাউন','Godown','Godown',7);

insert into public.forms (code, area, name_bn, name_mix, name_en, version, sort) values
  ('ITEMS','master','আইটেম তালিকা ও দাম','Item তালিকা ও Price','Item List & Prices','',0),
  ('ITEM_COST','master','ক্রয়মূল্য (দেখা ও বদলানো)','Cost Price (দেখা ও বদলানো)','Cost Price (view & change)','',0),
  ('14-1','showroom','দৈনিক শোরুম শিট','দৈনিক Showroom Sheet','Daily Showroom Sheet','v2.18',1),
  ('03-1','stock','ট্রান্সফার চালান','Transfer Challan','Transfer Challan (IBT)','v2.10',2),
  ('20-1','sales','কাস্টমার অর্ডার ফরম','কাস্টমার Order Form','Customer Order Form','v3.6',3),
  ('10-1','cash','ক্যাশ হ্যান্ডওভার স্লিপ','Cash Handover Slip','Cash Handover Slip','v1.6',4),
  ('0-1','settings','লোকেশন সেটিংস শিট','Location Settings Sheet','Location Settings Sheet','v1.16',5),
  ('11-1','staff','শিফট হ্যান্ডওভার রেজিস্টার','Shift Handover Register','Shift Handover Register','v1.5',6),
  ('10-2','cash','ব্যয় ভাউচার','Expense Voucher','Expense Voucher','v1.9',7),
  ('04-1','stock','মালামাল গ্রহণ রসিদ','Goods Receive Receipt','Goods Received Note (GRN)','v1.11',8),
  ('04-2','stock','মালামাল ইস্যু স্লিপ','Goods Issue Slip','Material Issue Slip','v1.9',9),
  ('20-2','sales','ডিসকাউন্ট অনুমোদন স্লিপ','Discount Approval Slip','Discount Approval Slip','v1.7',10),
  ('20-3','sales','রিটার্ন ও অভিযোগ রেজিস্টার','Return ও Complaint Register','Return & Complaint Register','v1.9',11),
  ('05-1','factory','কারখানা দৈনিক শিট','Factory দৈনিক Sheet','Factory Daily Sheet','v1.7',12),
  ('05-2','factory','প্রোডাক্ট স্পেক কার্ড','Product স্পেক Card','Product Spec Card','v2.5',13),
  ('06-1','purchase','পারচেজ রিকুইজিশন','Purchase Requisition','Purchase Requisition (PR)','v1.9',14),
  ('06-2','purchase','কোটেশন তুলনা ও সাপ্লায়ার নির্বাচন','Quotation Comparison ও Supplier Selection','Comparative Statement (CS)','v1.4',15),
  ('06-3','purchase','পারচেজ অর্ডার','Purchase Order','Purchase Order (PO)','v1.8',16),
  ('06-4','purchase','বিল যাচাই ও পেমেন্ট অনুরোধ','বিল Check ও Payment Request','Bill Check & Payment Request','v1.8',17),
  ('06-5','purchase','সাপ্লায়ার লেজার','Supplier Ledger','Supplier Ledger','v1.8',18),
  ('10-3','cash','ডিজিটাল পেমেন্ট রিকনসিলিয়েশন রেজিস্টার','Digital Payment Reconciliation Register','Digital Payment Reconciliation Register','v1.8',19),
  ('10-4','cash','ক্যাশ পজিশন ও পারচেজ বাজেট','Cash Position ও Purchase Budget','Cash Position & Purchase Budget','v1.9',20),
  ('04-3','stock','স্টক কাউন্ট শিট','Stock Count Sheet','Stock Count Sheet','v1.8',21),
  ('10-5','cash','প্রাপ্য ও অ্যাডভান্স রিকনসিলিয়েশন','Receivable ও Advance Reconciliation','Receivable & Advance Reconciliation','v1.10',22),
  ('01-1','owner','সাপ্তাহিক রিভিউ নোট','সাপ্তাহিক Review Note','Weekly Review Note','v1.8',23),
  ('01-2','owner','মাসিক লাভ-ক্ষতি ও KPI শিট','মাসিক P&L ও KPI Sheet','Monthly P&L and KPI Sheet','v1.3',24),
  ('02-1','staff','মাসিক হাজিরা রেজিস্টার','মাসিক Attendance Register','Monthly Attendance Register','v1.8',25),
  ('02-2','staff','মাসিক বেতন শিট','মাসিক Salary Sheet','Monthly Salary Sheet','v1.8',26),
  ('02-3','staff','স্টাফ অ্যাডভান্স রেজিস্টার','Staff Advance Register','Staff Advance Register','v1.6',27),
  ('02-4','staff','নিয়োগপত্র শর্ত ও দায়িত্ব','নিয়োগপত্র শর্ত ও দায়িত্ব','Appointment Letter — Terms & Duties','v1.5',28),
  ('02-5','staff','ছুটির আবেদন ফরম','Leave Application Form','Leave Application','v1.6',29),
  ('02-6','staff','ছাড়পত্র এক্সিট ক্লিয়ারেন্স','ছাড়পত্র এক্সিট Clearance','Exit Clearance Form','v1.8',30),
  ('08-1','assets','মেইনটেন্যান্স অনুরোধ ও রেকর্ড','Maintenance Request ও Record','Maintenance Request & Record','v1.6',31),
  ('20-4','sales','পার্টি ও পাইকারি ইনভয়েস','Party ও Wholesale Invoice','Party & Wholesale Invoice','v1.5',32),
  ('20-5','sales','পার্টি ও পাইকারি লেজার','Party ও Wholesale Ledger','Party & Wholesale Ledger','v1.6',33),
  ('05-3','factory','রেসিপি কার্ড','Recipe Card','Recipe Card','v1.5',34),
  ('05-4','factory','ফলন টেস্ট শিট','Yield Test Sheet','Yield Test Sheet','v1.4',35),
  ('02-7','staff','ডিউটি ও ব্যাকআপ কার্ড','Duty ও Backup Card','Duty & Backup Card','v1.10',36),
  ('02-8','staff','স্কিল চেকলিস্ট','Skill Checklist','Skill Checklist','v1.10',37),
  ('14-2','showroom','জিলাপি কাউন্টার দৈনিক রেকর্ড','জিলাপি Counter দৈনিক Record','Jalebi Counter Daily Record','v1.6',38),
  ('04-4','stock','স্টোর লেজার','Store Ledger','Store Ledger','v1.4',39),
  ('18-1','sales','মার্কেটিং ব্যয় রেজিস্টার','Marketing Expense Register','Marketing Expense Register','v1.4',40),
  ('20-6','sales','অনলাইন ও ডেলিভারি লেজার','Online ও Delivery Ledger','Online & Delivery Ledger','v1.4',41),
  ('05-5','factory','নতুন প্রোডাক্ট সিদ্ধান্ত শিট','নতুন Product Decision Sheet','New Product Decision Sheet','v1.4',42)
;

create temp table seed_items (code text, name_bn text, name_en text, category text, category_bn text, unit text, sell_price numeric, cost_price numeric);
insert into seed_items values
  ('I-001','সাদা মিষ্টি – কেজি','White Misti KG','sweet_kg','মিষ্টি (কেজি)','kg',260,230),
  ('I-002','কালো মিষ্টি – কেজি','Black Misti KG','sweet_kg','মিষ্টি (কেজি)','kg',260,230),
  ('I-003','পোড়াবাড়ি – কেজি','Porabari KG','sweet_kg','মিষ্টি (কেজি)','kg',350,320),
  ('I-004','সাদা লম্বা – কেজি','White Lomba KG','sweet_kg','মিষ্টি (কেজি)','kg',350,320),
  ('I-005','কালো লম্বা – কেজি','Black Lomba KG','sweet_kg','মিষ্টি (কেজি)','kg',350,320),
  ('I-006','স্পঞ্জ মিষ্টি – কেজি','Sponge Misti KG','sweet_kg','মিষ্টি (কেজি)','kg',450,400),
  ('I-007','লাল লাড্ডু – কেজি','Red Laddu KG','sweet_kg','মিষ্টি (কেজি)','kg',300,280),
  ('I-008','সাদা লাড্ডু – কেজি','White Laddu KG','sweet_kg','মিষ্টি (কেজি)','kg',350,330),
  ('I-009','সাদা ক্রিমজাম – কেজি','White Creamjam KG','sweet_kg','মিষ্টি (কেজি)','kg',400,370),
  ('I-010','কালো ক্রিমজাম – কেজি','Black Creamjam KG','sweet_kg','মিষ্টি (কেজি)','kg',400,370),
  ('I-011','সরপুরিয়া – কেজি','Sarpuria KG','sweet_kg','মিষ্টি (কেজি)','kg',450,420),
  ('I-012','গুড়ের সন্দেশ – কেজি','Gurer Sandesh KG','sweet_kg','মিষ্টি (কেজি)','kg',450,420),
  ('I-013','কাজু সন্দেশ – কেজি','Cashew Sandesh KG','sweet_kg','মিষ্টি (কেজি)','kg',500,470),
  ('I-014','ইলিশপেটি – কেজি','Ilishpeti KG','sweet_kg','মিষ্টি (কেজি)','kg',500,470),
  ('I-015','ক্ষির আইটেম – কেজি','Kheer Item KG','sweet_kg','মিষ্টি (কেজি)','kg',500,470),
  ('I-016','রসমালাই - কেজি','Rasmalai KG','sweet_kg','মিষ্টি (কেজি)','kg',450,420),
  ('I-017','লাল দই বড় মালসা','Red Doi Large Malsha','doi','দই','pc',160,140),
  ('I-018','লাল দই মাঝারি মালসা','Red Doi Medium Malsha','doi','দই','pc',80,80),
  ('I-019','সাদা দই বড় মালসা','White Doi Large Malsha','doi','দই','pc',160,140),
  ('I-020','সাদা দই মাঝারি মালসা','White Doi Medium Malsha','doi','দই','pc',80,75),
  ('I-021','স্বরা দই (বাংলা)','Shara Doi (Bangla)','doi','দই','pc',180,170),
  ('I-022','স্বরা দই (বাটি)','Shara Doi (Bowl)','doi','দই','pc',200,180),
  ('I-023','স্বরা দই (প্লেট)','Shara Doi (Plate)','doi','দই','pc',250,230),
  ('I-024','কাপ দই','Cup Doi','doi','দই','pc',30,25),
  ('I-025','টক দই','Sour Doi','doi','দই','pc',120,140),
  ('I-026','মালাইকারি – পিস','Malaikari Piece','sweet_pc','মিষ্টি (পিস)','pc',50,45),
  ('I-027','রসগোল্লা ছোট – পিস','Rasgolla Small Piece','sweet_pc','মিষ্টি (পিস)','pc',20,18),
  ('I-028','রসগোল্লা বড় – পিস','Rasgolla Large Piece','sweet_pc','মিষ্টি (পিস)','pc',30,25),
  ('I-029','সাদা মিষ্টি – পিস','White Misti Piece','sweet_pc','মিষ্টি (পিস)','pc',15,12.11),
  ('I-030','কালো মিষ্টি – পিস','Black Misti Piece','sweet_pc','মিষ্টি (পিস)','pc',15,12.11),
  ('I-031','পোড়াবাড়ি – পিস','Porabari Piece','sweet_pc','মিষ্টি (পিস)','pc',25,21.33),
  ('I-032','সাদা লম্বা – পিস','White Lomba Piece','sweet_pc','মিষ্টি (পিস)','pc',20,18.82),
  ('I-033','কালো লম্বা – পিস','Black Lomba Piece','sweet_pc','মিষ্টি (পিস)','pc',20,18.82),
  ('I-034','স্পঞ্জ মিষ্টি – পিস','Sponge Misti Piece','sweet_pc','মিষ্টি (পিস)','pc',25,19.05),
  ('I-035','লাল লাড্ডু – পিস','Red Laddu Piece','sweet_pc','মিষ্টি (পিস)','pc',15,13.33),
  ('I-036','সাদা লাড্ডু – পিস','White Laddu Piece','sweet_pc','মিষ্টি (পিস)','pc',20,15.71),
  ('I-037','সাদা ক্রিমজাম – পিস','White Creamjam Piece','sweet_pc','মিষ্টি (পিস)','pc',30,20.56),
  ('I-038','কালো ক্রিমজাম – পিস','Black Creamjam Piece','sweet_pc','মিষ্টি (পিস)','pc',30,20.56),
  ('I-039','সরপুরিয়া – পিস','Sarpuria Piece','sweet_pc','মিষ্টি (পিস)','pc',30,22.11),
  ('I-040','গুড়ের সন্দেশ – পিস','Gurer Sandesh Piece','sweet_pc','মিষ্টি (পিস)','pc',30,22.11),
  ('I-041','কাজু সন্দেশ – পিস','Cashew Sandesh Piece','sweet_pc','মিষ্টি (পিস)','pc',30,22.38),
  ('I-042','ইলিশপেটি – পিস','Ilishpeti Piece','sweet_pc','মিষ্টি (পিস)','pc',30,18.8),
  ('I-043','ক্ষির আইটেম – পিস','Kheer Item Piece','sweet_pc','মিষ্টি (পিস)','pc',25,18.8),
  ('I-044','ভ্যানিলা রেগুলার ১ পাউন্ড','Vanilla Regular 1 Pound','cake_lb','কেক (পাউন্ড)','lb',300,200),
  ('I-045','চকলেট রেগুলার ১ পাউন্ড','Chocolate Regular 1 Pound','cake_lb','কেক (পাউন্ড)','lb',350,200),
  ('I-046','ভ্যানিলা স্পেশাল ১ পাউন্ড','Vanilla Special 1 Pound','cake_lb','কেক (পাউন্ড)','lb',400,200),
  ('I-047','চকলেট স্পেশাল ১ পাউন্ড','Chocolate Special 1 Pound','cake_lb','কেক (পাউন্ড)','lb',450,200),
  ('I-048','ভ্যানিলা রেগুলার ২ পাউন্ড','Vanilla Regular 2 Pound','cake_lb','কেক (পাউন্ড)','lb',600,400),
  ('I-049','চকলেট রেগুলার ২ পাউন্ড','Chocolate Regular 2 Pound','cake_lb','কেক (পাউন্ড)','lb',700,400),
  ('I-050','ভ্যানিলা স্পেশাল ২ পাউন্ড','Vanilla Special 2 Pound','cake_lb','কেক (পাউন্ড)','lb',800,400),
  ('I-051','চকলেট স্পেশাল ২ পাউন্ড','Chocolate Special 2 Pound','cake_lb','কেক (পাউন্ড)','lb',900,400),
  ('I-052','ভ্যানিলা হাফ পাউন্ড','Vanilla Half Pound','cake_lb','কেক (পাউন্ড)','lb',200,120),
  ('I-053','চকলেট হাফ পাউন্ড','Chocolate Half Pound','cake_lb','কেক (পাউন্ড)','lb',200,120),
  ('I-054','ভ্যানিলা স্লাইস (৮ পিস)','Vanilla Slice (৮ pcs)','cake_pc','কেক (পিস)','pc',70,50),
  ('I-055','চকলেট স্লাইস ( ৮ পিস )','Chocolate Slice (৮ Piece )','cake_pc','কেক (পিস)','pc',80,50),
  ('I-056','অরেঞ্জ স্লাইস( ৮ পিস)','Orange স্লাইস(৮ pcs)','cake_pc','কেক (পিস)','pc',80,50),
  ('I-057','জার কেক','Jar Cake','cake_pc','কেক (পিস)','pc',100,80)
;
insert into public.items (code, name_bn, name_en, category, category_bn, unit, sell_price)
  select code, name_bn, name_en, category, category_bn, unit, sell_price from seed_items order by code;
insert into public.item_costs (item_id, cost_price)
  select i.id, s.cost_price from seed_items s join public.items i on i.code = s.code;
select setval('public.item_code_seq', 57);

insert into public.settings (key, value, label_bn, label_mix, label_en) values
  ('max_fails', '5', 'ভুল PIN কতবার হলে লক হবে', 'ভুল PIN কতবার হলে Lock', 'Wrong PIN attempts before lock'),
  ('business_name', '"ইসলামিয়া মিষ্টি ঘর"', 'প্রতিষ্ঠানের নাম', 'প্রতিষ্ঠানের Name', 'Business name');

-- Suggested default permissions (owner can change every box in the app)
insert into public.role_form_perms (role_code, form_code, can_view, can_enter, can_approve) values
  ('management','14-1',true,false,true),
  ('management','03-1',true,false,true),
  ('management','20-1',true,false,true),
  ('management','10-1',true,false,true),
  ('management','0-1',true,false,true),
  ('management','11-1',true,false,true),
  ('management','10-2',true,false,true),
  ('management','04-1',true,false,true),
  ('management','04-2',true,false,true),
  ('management','20-2',true,false,true),
  ('management','20-3',true,false,true),
  ('management','05-1',true,false,true),
  ('management','05-2',true,false,true),
  ('management','06-1',true,false,true),
  ('management','06-2',true,false,true),
  ('management','06-3',true,false,true),
  ('management','06-4',true,false,true),
  ('management','06-5',true,false,true),
  ('management','10-3',true,false,true),
  ('management','10-4',true,false,true),
  ('management','04-3',true,false,true),
  ('management','10-5',true,false,true),
  ('management','01-1',true,false,true),
  ('management','01-2',true,false,true),
  ('management','02-1',true,false,true),
  ('management','02-2',true,false,true),
  ('management','02-3',true,false,true),
  ('management','02-4',true,false,true),
  ('management','02-5',true,false,true),
  ('management','02-6',true,false,true),
  ('management','08-1',true,false,true),
  ('management','20-4',true,false,true),
  ('management','20-5',true,false,true),
  ('management','05-3',true,false,true),
  ('management','05-4',true,false,true),
  ('management','02-7',true,false,true),
  ('management','02-8',true,false,true),
  ('management','14-2',true,false,true),
  ('management','04-4',true,false,true),
  ('management','18-1',true,false,true),
  ('management','20-6',true,false,true),
  ('management','05-5',true,false,true),
  ('management','ITEMS',true,true,true),
  ('management','ITEM_COST',true,true,true),
  ('cash_controller','14-1',true,false,false),
  ('cash_controller','10-1',true,true,true),
  ('cash_controller','10-2',true,true,true),
  ('cash_controller','10-3',true,true,false),
  ('cash_controller','10-4',true,true,false),
  ('cash_controller','10-5',true,true,false),
  ('cash_controller','14-2',true,false,false),
  ('cash_controller','04-4',true,false,false),
  ('cash_controller','ITEMS',true,false,false),
  ('showroom_manager','14-1',true,true,false),
  ('showroom_manager','03-1',true,true,false),
  ('showroom_manager','20-1',true,true,false),
  ('showroom_manager','10-1',true,true,false),
  ('showroom_manager','11-1',true,true,false),
  ('showroom_manager','10-2',true,true,false),
  ('showroom_manager','20-2',true,true,false),
  ('showroom_manager','20-3',true,true,false),
  ('showroom_manager','04-3',true,true,false),
  ('showroom_manager','02-5',true,true,false),
  ('showroom_manager','08-1',true,true,false),
  ('showroom_manager','14-2',true,true,false),
  ('showroom_manager','04-4',true,false,false),
  ('showroom_manager','ITEMS',true,false,false),
  ('salesperson','14-1',true,false,false),
  ('salesperson','20-1',true,true,false),
  ('salesperson','20-3',true,true,false),
  ('salesperson','14-2',true,true,false),
  ('salesperson','ITEMS',true,false,false),
  ('storekeeper','03-1',true,true,false),
  ('storekeeper','04-1',true,true,false),
  ('storekeeper','04-2',true,true,false),
  ('storekeeper','06-3',true,false,false),
  ('storekeeper','04-3',true,true,false),
  ('storekeeper','04-4',true,true,false),
  ('storekeeper','ITEMS',true,false,false),
  ('factory_incharge','03-1',true,true,false),
  ('factory_incharge','04-2',true,true,false),
  ('factory_incharge','05-1',true,true,false),
  ('factory_incharge','05-2',true,true,false),
  ('factory_incharge','04-3',true,true,false),
  ('factory_incharge','05-3',true,true,false),
  ('factory_incharge','05-4',true,true,false),
  ('factory_incharge','05-5',true,true,false),
  ('factory_incharge','ITEMS',true,false,false),
  ('purchasing','04-1',true,false,false),
  ('purchasing','06-1',true,true,false),
  ('purchasing','06-2',true,true,false),
  ('purchasing','06-3',true,true,false),
  ('purchasing','06-4',true,false,false),
  ('purchasing','06-5',true,false,false),
  ('purchasing','ITEMS',true,true,false),
  ('purchasing','ITEM_COST',true,false,false),
  ('party_coordinator','20-1',true,true,false),
  ('party_coordinator','20-2',true,true,false),
  ('party_coordinator','20-4',true,true,false),
  ('party_coordinator','20-5',true,true,false),
  ('party_coordinator','ITEMS',true,false,false),
  ('carrier','03-1',true,false,false),
  ('carrier','10-1',true,false,false),
  ('carrier','20-6',true,true,false),
  ('hr','11-1',true,false,false),
  ('hr','02-1',true,true,false),
  ('hr','02-2',true,true,false),
  ('hr','02-3',true,true,false),
  ('hr','02-4',true,true,false),
  ('hr','02-5',true,true,false),
  ('hr','02-6',true,true,false),
  ('hr','02-7',true,true,false),
  ('hr','02-8',true,true,false);

