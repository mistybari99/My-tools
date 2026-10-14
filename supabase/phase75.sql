-- ============================================================
-- Phase 75 (bos75) - STEP C-2ক: cost sources and allocation (separate or shared bills).
--   Needs phase8 ... phase71 + phase73 + phase74. Additive; paste-twice safe. Old phases are NOT edited.
--   One place to type a bill ONCE (electricity, gas, rent, licence, repair, water, internet, any type the owner adds), in any shape:
--     separate source  = one site pays it  -> the whole bill goes straight to its destination (no allocation step)
--     shared source    = one bill covers several sites -> an allocation RULE splits it: sub-meter reading | fixed percent | floor area | headcount | output kg | whole bill to one
--                        location | other (hand-typed amounts). Every share goes to ONE destination: factory (layer 2) | showroom (layer 3) | admin (layer 3).
--   Factory shares flow BY THEMSELVES into factory_cost_pools (phase74) with the component type mapped from the cost-source type; showroom / admin shares stay in the bill-share table
--   and are read by branch_overhead() for the branch P&L (nothing is absorbed into product cost). A month with no bill is marked 'বিল বাকি' - never filled by an average.
--   Rules: percent must total 100 or saving is refused; a remainder is an 'অভাগিত' row with a yellow flag; a rule applies from its effective date, bills already allocated never change;
--   the person who entered a rule cannot approve it (rule cost_rule_self_approve, default OFF). Everything starts BLANK; the list 'ভাগ নির্ধারিত নয়' shows what has no split yet.
--   A bill is compared with the approved / submitted 10-2 expense vouchers (same place, month, head, amount) -> a yellow duplicate flag; the bill holds the detail, the 10-2 only a number.
--   Cost-right holders only (view + edit), every write has client_id + audit. A new location appears in the pickers by itself (they read the locations table).
-- ============================================================

-- ---------- settings, grants ----------
insert into public.rules (key, module, kind, default_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('cost_rule_self_approve', 'stock', 'switch', 'false',
  'যে ভাগের নিয়ম লিখেছে সে-ই অনুমোদন করতে পারবে', 'যে allocation rule লিখেছে সে-ই approve করতে পারবে', 'The person who entered an allocation rule may also approve it',
  'Off (default) = a second person with the cost_rule_approve grant is needed (the owner can always approve what he did not enter).', 740)
on conflict (key) do nothing;
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('cost_bill_entry', 'cost', 80, 'খরচের বিল ও সোর্স লেখা', 'Cost bill ও source লেখা', 'Enter cost sources, bills and allocation rules', 'window', null),
 ('cost_rule_approve', 'cost', 81, 'ভাগের নিয়ম অনুমোদন', 'Allocation rule approve', 'Approve an allocation rule', 'window', null)
on conflict (grant_code) do nothing;

-- ---------- types of cost source (owner may add types; each maps to a factory component type for the pool) ----------
create table if not exists public.cost_source_types (
  code text primary key check (code ~ '^[a-z0-9_]{2,40}$'),
  label_bn text not null check (length(btrim(label_bn)) between 1 and 80),
  label_en text,
  component_type text not null default 'other' references public.cost_component_types(code),    -- the pool type a FACTORY share lands in
  builtin boolean not null default false,
  active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now()
);
insert into public.cost_source_types (code, label_bn, label_en, component_type, builtin) values
 ('electricity', 'বিদ্যুৎ', 'Electricity', 'electricity', true), ('gas', 'গ্যাস', 'Gas', 'gas', true), ('rent', 'ঘর ভাড়া', 'Rent', 'factory_rent', true),
 ('licence_fee', 'লাইসেন্স ও ফি', 'Licence and fees', 'licence_fee', true), ('machine_repair', 'যন্ত্র মেরামত', 'Machine repair', 'machine_repair', true),
 ('water', 'পানি', 'Water', 'other', true), ('internet', 'ইন্টারনেট', 'Internet', 'other', true), ('other', '☐ অন্য: ______', 'Other: ______', 'other', true)
on conflict (code) do nothing;
create sequence if not exists public.cost_stype_seq;

-- ---------- sources, covered locations ----------
create table if not exists public.cost_sources (
  id bigserial primary key,
  code text generated always as ('src-' || id::text) stored,
  cost_type text not null references public.cost_source_types(code),
  provider text check (provider is null or length(provider) <= 120),                -- provider / meter / contract no (may be blank)
  kind text not null check (kind in ('separate', 'shared')),
  dest text check (dest is null or dest in ('factory', 'showroom', 'admin')),       -- separate sources: where the whole bill goes
  frequency text not null default 'monthly' check (frequency in ('monthly', 'yearly', 'irregular')),   -- only monthly / yearly sources get the 'বিল বাকি' marker
  effective_from date not null,
  active boolean not null default true,
  retired_at timestamptz, retired_reason text,
  note text,
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(),
  check (kind = 'shared' or dest is not null)
);
create table if not exists public.cost_source_locs (
  source_id bigint not null references public.cost_sources(id),
  location_id int not null references public.locations(id),
  primary key (source_id, location_id)
);

-- ---------- allocation rules (versions) ----------
create table if not exists public.cost_source_rules (
  id bigserial primary key,
  source_id bigint not null references public.cost_sources(id),
  method text not null check (method in ('sub_meter', 'fixed_percent', 'floor_area', 'headcount', 'output_kg', 'whole_to_one', 'other_manual')),
  effective_from date not null,
  status text not null default 'draft' check (status in ('draft', 'approved', 'superseded')),
  complete boolean not null default false,                       -- every needed value typed (and percentages total 100)
  note text,
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(),
  approved_by uuid, approved_at timestamptz
);
create unique index if not exists csr_one_approved on public.cost_source_rules (source_id, effective_from) where status = 'approved';
create table if not exists public.cost_source_rule_shares (
  id bigserial primary key,
  rule_id bigint not null references public.cost_source_rules(id),
  location_id int not null references public.locations(id),
  dest text not null check (dest in ('factory', 'showroom', 'admin')),
  value numeric check (value is null or (value >= 0 and value <= 1000000000)),       -- percent | sq ft | headcount; blank until typed
  unique (rule_id, location_id, dest)
);

-- ---------- bills, per-bill inputs, the frozen allocation ----------
create table if not exists public.cost_source_bills (
  id bigserial primary key,
  source_id bigint not null references public.cost_sources(id),
  period_kind text not null default 'month' check (period_kind in ('month', 'year')),    -- a yearly fee is spread /12 by the pool code
  period_month date not null check (period_month = date_trunc('month', period_month)::date),
  amount numeric not null check (amount > 0 and amount <= 1000000000000),
  pay_mode text check (pay_mode is null or pay_mode in ('cash', 'bank', 'mobile', 'card', 'other')),
  bill_no text check (bill_no is null or length(bill_no) <= 60),
  bill_date date,
  one_off boolean not null default false,                         -- a large irregular repair: 'একবারের খরচ'
  voucher_ref text check (voucher_ref is null or length(voucher_ref) <= 40),     -- the 10-2 number, a REFERENCE only
  status text not null default 'active' check (status in ('active', 'void')),
  void_by uuid, void_at timestamptz, void_note text,
  dup_entry_id uuid, dup_head text, dup_ack boolean not null default false, dup_ack_note text,     -- the 10-2 voucher this bill looks like (same place, month, head, amount) + the reason it was accepted as different
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now()
);
create unique index if not exists csb_bill_no on public.cost_source_bills (source_id, bill_no) where bill_no is not null and status = 'active';
create index if not exists csb_month on public.cost_source_bills (period_month) where status = 'active';
create table if not exists public.cost_bill_inputs (
  bill_id bigint not null references public.cost_source_bills(id),
  location_id int not null references public.locations(id),
  dest text not null check (dest in ('factory', 'showroom', 'admin')),
  value numeric not null check (value >= 0 and value <= 1000000000000),         -- sub-meter reading, or a hand-typed amount (method other_manual)
  primary key (bill_id, location_id, dest)
);
create table if not exists public.cost_bill_shares (
  id bigserial primary key,
  bill_id bigint not null references public.cost_source_bills(id),
  kind text not null check (kind in ('share', 'unallocated')),
  location_id int references public.locations(id),
  dest text check (dest is null or dest in ('factory', 'showroom', 'admin')),
  amount numeric not null check (amount >= 0),
  pct numeric,
  rule_id bigint references public.cost_source_rules(id),
  flag text,                                                       -- why an unallocated row exists: no_rule / meter_missing / no_output / remainder / ...
  active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now(),
  check ((kind = 'share' and location_id is not null and dest is not null) or kind = 'unallocated')
);
create index if not exists cbs_bill on public.cost_bill_shares (bill_id) where active;

-- ---------- triggers (audit, nothing is deleted) / RLS ----------
create or replace function public._cs_no_delete() returns trigger language plpgsql as $$ begin raise exception 'nothing is deleted – retire or void instead'; end $$;
drop trigger if exists cs_types_nd on public.cost_source_types; create trigger cs_types_nd before delete on public.cost_source_types for each row execute function public._cs_no_delete();
drop trigger if exists cs_src_nd on public.cost_sources; create trigger cs_src_nd before delete on public.cost_sources for each row execute function public._cs_no_delete();
drop trigger if exists cs_locs_nd on public.cost_source_locs; create trigger cs_locs_nd before delete on public.cost_source_locs for each row execute function public._cs_no_delete();
drop trigger if exists cs_rules_nd on public.cost_source_rules; create trigger cs_rules_nd before delete on public.cost_source_rules for each row execute function public._cs_no_delete();
drop trigger if exists cs_rsh_nd on public.cost_source_rule_shares; create trigger cs_rsh_nd before delete on public.cost_source_rule_shares for each row execute function public._cs_no_delete();
drop trigger if exists cs_bills_nd on public.cost_source_bills; create trigger cs_bills_nd before delete on public.cost_source_bills for each row execute function public._cs_no_delete();
drop trigger if exists cs_inp_nd on public.cost_bill_inputs; create trigger cs_inp_nd before delete on public.cost_bill_inputs for each row execute function public._cs_no_delete();
drop trigger if exists cs_shr_nd on public.cost_bill_shares; create trigger cs_shr_nd before delete on public.cost_bill_shares for each row execute function public._cs_no_delete();
drop trigger if exists audit_cs_types on public.cost_source_types; create trigger audit_cs_types after insert or update on public.cost_source_types for each row execute function public.log_change('code');
drop trigger if exists audit_cs_src on public.cost_sources; create trigger audit_cs_src after insert or update on public.cost_sources for each row execute function public.log_change('id');
drop trigger if exists audit_cs_rules on public.cost_source_rules; create trigger audit_cs_rules after insert or update on public.cost_source_rules for each row execute function public.log_change('id');
drop trigger if exists audit_cs_rsh on public.cost_source_rule_shares; create trigger audit_cs_rsh after insert or update on public.cost_source_rule_shares for each row execute function public.log_change('id');
drop trigger if exists audit_cs_bills on public.cost_source_bills; create trigger audit_cs_bills after insert or update on public.cost_source_bills for each row execute function public.log_change('id');
drop trigger if exists audit_cs_shr on public.cost_bill_shares; create trigger audit_cs_shr after insert or update on public.cost_bill_shares for each row execute function public.log_change('id');

-- the rights: view / edit = the cost right. bill + rule entry = cost right + (owner or cost_bill_entry). rule approval = cost right + (owner or cost_rule_approve): a different person.
create or replace function public._cs_view() returns boolean language sql stable security definer set search_path = public as $$ select public._recipe_cost_ok(); $$;
create or replace function public._cs_enter() returns boolean language sql stable security definer set search_path = public as $$ select public._recipe_cost_ok() and (public.is_owner() or public.has_grant('cost_bill_entry')); $$;
create or replace function public._cs_approve() returns boolean language sql stable security definer set search_path = public as $$ select public._recipe_cost_ok() and (public.is_owner() or public.has_grant('cost_rule_approve')); $$;
-- a person who may not see all places sees only the sources that touch a place of his
create or replace function public._cs_src_ok(p_source bigint) returns boolean language sql stable security definer set search_path = public as $$
  select public._cs_view() and (public._all_locs() or exists (select 1 from public.cost_source_locs l where l.source_id = p_source and public.can_loc(l.location_id)));
$$;

alter table public.cost_source_types enable row level security;
alter table public.cost_sources enable row level security;
alter table public.cost_source_locs enable row level security;
alter table public.cost_source_rules enable row level security;
alter table public.cost_source_rule_shares enable row level security;
alter table public.cost_source_bills enable row level security;
alter table public.cost_bill_inputs enable row level security;
alter table public.cost_bill_shares enable row level security;
drop policy if exists cs_types_read on public.cost_source_types; create policy cs_types_read on public.cost_source_types for select to authenticated using (public._cs_view());
drop policy if exists cs_src_read on public.cost_sources; create policy cs_src_read on public.cost_sources for select to authenticated using (public._cs_src_ok(id));
drop policy if exists cs_locs_read on public.cost_source_locs; create policy cs_locs_read on public.cost_source_locs for select to authenticated using (public._cs_src_ok(source_id));
drop policy if exists cs_rules_read on public.cost_source_rules; create policy cs_rules_read on public.cost_source_rules for select to authenticated using (public._cs_src_ok(source_id));
drop policy if exists cs_rsh_read on public.cost_source_rule_shares; create policy cs_rsh_read on public.cost_source_rule_shares for select to authenticated using (public._cs_src_ok((select r.source_id from public.cost_source_rules r where r.id = rule_id)));
drop policy if exists cs_bills_read on public.cost_source_bills; create policy cs_bills_read on public.cost_source_bills for select to authenticated using (public._cs_src_ok(source_id));
drop policy if exists cs_inp_read on public.cost_bill_inputs; create policy cs_inp_read on public.cost_bill_inputs for select to authenticated using (public._cs_src_ok((select b.source_id from public.cost_source_bills b where b.id = bill_id)));
drop policy if exists cs_shr_read on public.cost_bill_shares; create policy cs_shr_read on public.cost_bill_shares for select to authenticated using (public._cs_src_ok((select b.source_id from public.cost_source_bills b where b.id = bill_id)));
revoke all on public.cost_source_types, public.cost_sources, public.cost_source_locs, public.cost_source_rules, public.cost_source_rule_shares, public.cost_source_bills, public.cost_bill_inputs, public.cost_bill_shares from anon, authenticated;
grant select on public.cost_source_types, public.cost_sources, public.cost_source_locs, public.cost_source_rules, public.cost_source_rule_shares, public.cost_source_bills, public.cost_bill_inputs, public.cost_bill_shares to authenticated;
revoke all on sequence public.cost_sources_id_seq, public.cost_source_rules_id_seq, public.cost_source_rule_shares_id_seq, public.cost_source_bills_id_seq, public.cost_bill_shares_id_seq, public.cost_stype_seq from anon, authenticated;

-- ---------- types ----------
create or replace function public.cost_source_type_add(p_label_bn text, p_label_en text default null, p_component_type text default 'other') returns jsonb
language plpgsql security definer set search_path = public as $$
declare c text;
begin
  if not public._cs_enter() then raise exception 'not allowed'; end if;
  if p_label_bn is null or length(btrim(p_label_bn)) < 1 or length(btrim(p_label_bn)) > 80 then raise exception 'name_needed'; end if;
  if not exists (select 1 from public.cost_component_types where code = coalesce(p_component_type, 'other') and active) then raise exception 'unknown_type'; end if;
  c := 'y' || nextval('public.cost_stype_seq')::text;
  insert into public.cost_source_types (code, label_bn, label_en, component_type, builtin, created_by) values (c, btrim(p_label_bn), left(nullif(btrim(p_label_en), ''), 80), coalesce(p_component_type, 'other'), false, auth.uid());
  return jsonb_build_object('code', c);
end $$;

-- ---------- sources ----------
-- create (p_id null) or edit. After a bill exists the type / kind / places / destination no longer change (open a new source instead).
create or replace function public.cost_source_save(p_id bigint, p_type text, p_provider text, p_kind text, p_dest text, p_locs int[], p_frequency text, p_effective date, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.cost_sources; l int; n int := 0; sid bigint;
begin
  if not public._cs_enter() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_kind not in ('separate', 'shared') then raise exception 'bad_value'; end if;
  if p_frequency not in ('monthly', 'yearly', 'irregular') then raise exception 'bad_value'; end if;
  if not exists (select 1 from public.cost_source_types where code = p_type and active) then raise exception 'unknown_type'; end if;
  if p_effective is null then raise exception 'bad_date'; end if;
  if p_locs is null or coalesce(array_length(p_locs, 1), 0) = 0 then raise exception 'locations_needed'; end if;
  foreach l in array p_locs loop
    if not exists (select 1 from public.locations where id = l) then raise exception 'unknown location'; end if;
    if not (public._all_locs() or public.can_loc(l)) then raise exception 'not allowed'; end if;
  end loop;
  if p_kind = 'separate' then
    if array_length(p_locs, 1) <> 1 then raise exception 'separate_one_location'; end if;
    if p_dest is null or p_dest not in ('factory', 'showroom', 'admin') then raise exception 'dest_needed'; end if;
  else
    if (select count(distinct x) from unnest(p_locs) x) < 2 then raise exception 'shared_needs_two'; end if;
  end if;
  if p_id is null then
    if p_client is not null then
      select * into s from public.cost_sources where client_id = p_client;
      if found then return jsonb_build_object('dup', true, 'id', s.id, 'code', s.code); end if;
    end if;
    insert into public.cost_sources (cost_type, provider, kind, dest, frequency, effective_from, note, client_id, created_by)
      values (p_type, left(nullif(btrim(p_provider), ''), 120), p_kind, case when p_kind = 'separate' then p_dest end, p_frequency, p_effective, left(p_note, 300), p_client, auth.uid()) returning id into sid;
    insert into public.cost_source_locs (source_id, location_id) select sid, x from (select distinct unnest(p_locs) x) z;
  else
    select * into s from public.cost_sources where id = p_id for update;
    if not found then raise exception 'source_not_found'; end if;
    if exists (select 1 from public.cost_source_bills where source_id = p_id) and (s.cost_type <> p_type or s.kind <> p_kind or s.dest is distinct from (case when p_kind = 'separate' then p_dest end)
        or (select array_agg(location_id order by location_id) from public.cost_source_locs where source_id = p_id) is distinct from (select array_agg(x order by x) from (select distinct unnest(p_locs) x) z)) then raise exception 'source_in_use'; end if;
    update public.cost_sources set cost_type = p_type, provider = left(nullif(btrim(p_provider), ''), 120), kind = p_kind, dest = case when p_kind = 'separate' then p_dest end, frequency = p_frequency,
      effective_from = p_effective, note = left(p_note, 300) where id = p_id;
    insert into public.cost_source_locs (source_id, location_id) select p_id, x from (select distinct unnest(p_locs) x) z on conflict do nothing;
    sid := p_id;
  end if;
  return jsonb_build_object('id', sid, 'code', 'src-' || sid::text);
end $$;
create or replace function public.cost_source_set_active(p_id bigint, p_active boolean, p_reason text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public._cs_enter() then raise exception 'not allowed'; end if;
  if p_active is null then raise exception 'bad_value'; end if;
  if not p_active and length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'note_required'; end if;
  update public.cost_sources set active = p_active, retired_at = case when p_active then null else now() end, retired_reason = case when p_active then null else left(btrim(p_reason), 200) end where id = p_id;
  if not found then raise exception 'source_not_found'; end if;
end $$;

-- ---------- allocation rules ----------
-- p_shares = [{location_id, dest, value}] ; value blank = not typed yet (the rule stays a draft that cannot be approved). Percentages: if every value is typed they must total 100.
create or replace function public.cost_rule_save(p_source bigint, p_method text, p_effective date, p_shares jsonb, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.cost_sources; x jsonb; rid bigint; v numeric; n int := 0; nblank int := 0; tot numeric := 0; seen text[] := '{}'; k text; loc int; ds text; dup public.cost_source_rules; cpl boolean;
begin
  if not public._cs_enter() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then select * into dup from public.cost_source_rules where client_id = p_client; if found then return jsonb_build_object('dup', true, 'id', dup.id); end if; end if;
  select * into s from public.cost_sources where id = p_source;
  if not found then raise exception 'source_not_found'; end if;
  if not public._cs_src_ok(p_source) then raise exception 'not allowed'; end if;
  if s.kind <> 'shared' then raise exception 'not_shared'; end if;
  if p_method not in ('sub_meter', 'fixed_percent', 'floor_area', 'headcount', 'output_kg', 'whole_to_one', 'other_manual') then raise exception 'bad_value'; end if;
  if p_effective is null then raise exception 'bad_date'; end if;
  if p_shares is null or jsonb_typeof(p_shares) <> 'array' or jsonb_array_length(p_shares) = 0 then raise exception 'no_lines'; end if;
  for x in select e from jsonb_array_elements(p_shares) e loop
    loc := nullif(x->>'location_id', '')::int; ds := x->>'dest';
    if loc is null or not exists (select 1 from public.cost_source_locs where source_id = p_source and location_id = loc) then raise exception 'location_not_covered'; end if;
    if ds is null or ds not in ('factory', 'showroom', 'admin') then raise exception 'dest_needed'; end if;
    k := loc::text || ':' || ds;
    if k = any(seen) then raise exception 'dup_share'; end if;
    seen := seen || k; n := n + 1;
    v := nullif(btrim(x->>'value'), '')::numeric;
    if v is not null and not (v >= 0 and v <= 1000000000) then raise exception 'bad_qty'; end if;
    if v is null then nblank := nblank + 1; else tot := tot + v; end if;
  end loop;
  if p_method = 'whole_to_one' and n <> 1 then raise exception 'one_target_needed'; end if;
  if p_method <> 'whole_to_one' and n < 2 then raise exception 'two_targets_needed'; end if;
  if p_method = 'fixed_percent' and nblank = 0 and abs(tot - 100) > 0.0001 then raise exception 'percent_not_100' using detail = tot::text; end if;
  cpl := case when p_method in ('fixed_percent', 'floor_area', 'headcount') then nblank = 0 and (p_method <> 'fixed_percent' or abs(tot - 100) <= 0.0001) and (p_method = 'fixed_percent' or tot > 0) else true end;
  insert into public.cost_source_rules (source_id, method, effective_from, complete, note, client_id, created_by) values (p_source, p_method, p_effective, cpl, left(p_note, 300), p_client, auth.uid()) returning id into rid;
  for x in select e from jsonb_array_elements(p_shares) e loop
    insert into public.cost_source_rule_shares (rule_id, location_id, dest, value) values (rid, (x->>'location_id')::int, x->>'dest', case when p_method in ('fixed_percent', 'floor_area', 'headcount') then nullif(btrim(x->>'value'), '')::numeric end);
  end loop;
  return jsonb_build_object('id', rid, 'status', 'draft', 'complete', cpl, 'blank_values', nblank);
end $$;

-- ---------- the allocation of ONE bill (frozen at the time; never recomputed once fully allocated) ----------
create or replace function public._cs_rule_in_force(p_source bigint, p_month date) returns bigint
language sql stable security definer set search_path = public as $$
  select id from public.cost_source_rules where source_id = p_source and status = 'approved' and complete and effective_from <= (p_month + interval '1 month' - interval '1 day')::date
   order by effective_from desc, id desc limit 1;
$$;

create or replace function public._cs_alloc(p_bill bigint) returns void
language plpgsql security definer set search_path = public as $$
declare b public.cost_source_bills; s public.cost_sources; r public.cost_source_rules; sh record; inp record; rid bigint; tot numeric := 0; acc numeric := 0; n int := 0; i int := 0; amt numeric; pct numeric;
        why text := null; rem numeric; l1 int; kgs numeric; arr jsonb := '[]'::jsonb; e jsonb; m date;
begin
  select * into b from public.cost_source_bills where id = p_bill;
  select * into s from public.cost_sources where id = b.source_id;
  update public.cost_bill_shares set active = false where bill_id = p_bill and active;
  if s.kind = 'separate' then
    select location_id into l1 from public.cost_source_locs where source_id = s.id limit 1;
    insert into public.cost_bill_shares (bill_id, kind, location_id, dest, amount, pct, created_by) values (p_bill, 'share', l1, s.dest, b.amount, 100, auth.uid());
  else
    rid := public._cs_rule_in_force(s.id, b.period_month);
    if rid is null then
      insert into public.cost_bill_shares (bill_id, kind, amount, flag, created_by) values (p_bill, 'unallocated', b.amount, 'no_rule', auth.uid());
    else
      select * into r from public.cost_source_rules where id = rid;
      -- a list of {location, dest, weight}
      if r.method = 'whole_to_one' then
        for sh in select * from public.cost_source_rule_shares where rule_id = rid loop arr := arr || jsonb_build_object('l', sh.location_id, 'd', sh.dest, 'w', 1); end loop;
      elsif r.method in ('fixed_percent', 'floor_area', 'headcount') then
        for sh in select * from public.cost_source_rule_shares where rule_id = rid order by location_id, dest loop arr := arr || jsonb_build_object('l', sh.location_id, 'd', sh.dest, 'w', sh.value); end loop;
      elsif r.method = 'sub_meter' then
        if exists (select 1 from public.cost_source_rule_shares h where h.rule_id = rid and not exists (select 1 from public.cost_bill_inputs i2 where i2.bill_id = p_bill and i2.location_id = h.location_id and i2.dest = h.dest)) then why := 'meter_missing';
        else for sh in select h.location_id, h.dest, i2.value from public.cost_source_rule_shares h join public.cost_bill_inputs i2 on i2.bill_id = p_bill and i2.location_id = h.location_id and i2.dest = h.dest where h.rule_id = rid order by h.location_id, h.dest loop
               arr := arr || jsonb_build_object('l', sh.location_id, 'd', sh.dest, 'w', sh.value); end loop; end if;
      elsif r.method = 'output_kg' then
        m := b.period_month;
        for sh in select h.location_id, h.dest from public.cost_source_rule_shares h where h.rule_id = rid order by h.location_id, h.dest loop
          select coalesce(sum(pr.yield_base), 0) into kgs from public.production_runs pr join public.items it on it.id = pr.item_id
            where pr.location_id = sh.location_id and pr.status = 'done' and lower(coalesce(public._item_base(pr.item_id), '')) = 'kg'
              and public._m1((pr.made_at at time zone 'Asia/Dhaka')::date) = m;
          arr := arr || jsonb_build_object('l', sh.location_id, 'd', sh.dest, 'w', kgs);
        end loop;
      else      -- other_manual: hand-typed AMOUNTS for this bill
        for sh in select h.location_id, h.dest, i2.value from public.cost_source_rule_shares h join public.cost_bill_inputs i2 on i2.bill_id = p_bill and i2.location_id = h.location_id and i2.dest = h.dest where h.rule_id = rid order by h.location_id, h.dest loop
          arr := arr || jsonb_build_object('l', sh.location_id, 'd', sh.dest, 'a', sh.value); end loop;
      end if;
      n := jsonb_array_length(arr);
      if why is null and n = 0 then why := case when r.method = 'other_manual' then 'amounts_missing' else 'no_targets' end; end if;
      if why is null and r.method <> 'other_manual' then
        select coalesce(sum((x->>'w')::numeric), 0) into tot from jsonb_array_elements(arr) x;
        if tot <= 0 then why := case when r.method = 'output_kg' then 'no_output' else 'zero_total' end; end if;
      end if;
      if why is not null then
        insert into public.cost_bill_shares (bill_id, kind, amount, flag, rule_id, created_by) values (p_bill, 'unallocated', b.amount, why, rid, auth.uid());
      elsif r.method = 'other_manual' then
        for e in select x from jsonb_array_elements(arr) x loop acc := acc + (e->>'a')::numeric; end loop;
        if acc > b.amount + 0.005 then
          insert into public.cost_bill_shares (bill_id, kind, amount, flag, rule_id, created_by) values (p_bill, 'unallocated', b.amount, 'shares_exceed_bill', rid, auth.uid());
        else
          for e in select x from jsonb_array_elements(arr) x loop
            insert into public.cost_bill_shares (bill_id, kind, location_id, dest, amount, pct, rule_id, created_by) values (p_bill, 'share', (e->>'l')::int, e->>'d', round((e->>'a')::numeric, 2), round((e->>'a')::numeric / b.amount * 100, 4), rid, auth.uid());
          end loop;
          rem := round(b.amount - round(acc, 2), 2);
          if rem > 0.004 then insert into public.cost_bill_shares (bill_id, kind, amount, flag, rule_id, created_by) values (p_bill, 'unallocated', rem, 'remainder', rid, auth.uid()); end if;
        end if;
      else
        i := 0; acc := 0;
        for e in select x from jsonb_array_elements(arr) x loop
          i := i + 1; pct := (e->>'w')::numeric / tot * 100;
          amt := case when i = n then round(b.amount - acc, 2) else round(b.amount * (e->>'w')::numeric / tot, 2) end;      -- the last share takes the rounding: the shares always sum to the bill
          acc := acc + amt;
          insert into public.cost_bill_shares (bill_id, kind, location_id, dest, amount, pct, rule_id, created_by) values (p_bill, 'share', (e->>'l')::int, e->>'d', amt, round(pct, 4), rid, auth.uid());
        end loop;
      end if;
    end if;
  end if;
  perform public._cs_push_pools(p_bill);
  if exists (select 1 from public.cost_bill_shares where bill_id = p_bill and active and kind = 'unallocated') then
    select location_id into l1 from public.cost_source_locs where source_id = s.id order by location_id limit 1;
    perform public._stock_exc(l1, 'cost_bill_unallocated', 'yellow', 'খরচের বিলের অভাগিত অংশ আছে (' || s.code || ')', 'A cost bill has an unallocated part (' || s.code || ')', null, coalesce(b.bill_date, b.period_month), 'STOCK');
  end if;
end $$;

-- factory shares flow BY THEMSELVES into the pools (type mapped from the source type); the rows of a bill are replaced whenever it is allocated again; showroom / admin shares stay here (branch_overhead)
create or replace function public._cs_push_pools(p_bill bigint) returns void
language plpgsql security definer set search_path = public as $$
declare b public.cost_source_bills; ct text; sh record;
begin
  select * into b from public.cost_source_bills where id = p_bill;
  update public.factory_cost_pools set active = false where source = 'allocated' and ref like 'bill:' || p_bill::text || ':%' and active;
  if b.status <> 'active' then return; end if;
  select t.component_type into ct from public.cost_sources s join public.cost_source_types t on t.code = s.cost_type where s.id = b.source_id;
  for sh in select location_id, sum(amount) amt from public.cost_bill_shares where bill_id = p_bill and active and kind = 'share' and dest = 'factory' group by location_id loop
    if sh.amt > 0 then
      insert into public.factory_cost_pools (location_id, month, component_type, period_kind, actual_amount, one_off, source, ref, note, created_by)
        values (sh.location_id, b.period_month, coalesce(ct, 'other'), b.period_kind, sh.amt, b.one_off, 'allocated', 'bill:' || p_bill::text || ':' || sh.location_id::text, 'from cost bill ' || p_bill::text, auth.uid());
    end if;
  end loop;
end $$;

-- ---------- bills ----------
-- p_inputs = [{location_id, dest, value}] : the sub-meter readings of this bill, or the hand-typed amounts (rule method other_manual). Everything else is derived.
create or replace function public.cost_bill_add(p_source bigint, p_period_kind text, p_month date, p_amount numeric, p_pay_mode text default null, p_bill_no text default null, p_bill_date date default null,
  p_one_off boolean default false, p_inputs jsonb default null, p_voucher_ref text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.cost_sources; b public.cost_source_bills; bid bigint; m date := public._m1(p_month); x jsonb; heads text[]; e record; shares jsonb; unalloc numeric; dupid uuid; duph text; bn text := nullif(btrim(p_bill_no), '');
begin
  if not public._cs_enter() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then select * into b from public.cost_source_bills where client_id = p_client; if found then return jsonb_build_object('dup', true, 'id', b.id); end if; end if;
  select * into s from public.cost_sources where id = p_source;
  if not found then raise exception 'source_not_found'; end if;
  if not public._cs_src_ok(p_source) then raise exception 'not allowed'; end if;
  if not s.active then raise exception 'source_retired'; end if;
  if p_period_kind not in ('month', 'year') then raise exception 'bad_value'; end if;
  if p_month is null then raise exception 'bad_date'; end if;
  if p_amount is null or not (p_amount > 0 and p_amount <= 1000000000000) then raise exception 'bad_cost'; end if;
  if p_pay_mode is not null and p_pay_mode not in ('cash', 'bank', 'mobile', 'card', 'other') then raise exception 'bad_value'; end if;
  if bn is not null and exists (select 1 from public.cost_source_bills where source_id = p_source and bill_no = bn and status = 'active') then raise exception 'duplicate_bill'; end if;
  insert into public.cost_source_bills (source_id, period_kind, period_month, amount, pay_mode, bill_no, bill_date, one_off, voucher_ref, client_id, created_by)
    values (p_source, p_period_kind, m, p_amount, p_pay_mode, bn, p_bill_date, coalesce(p_one_off, false), left(nullif(btrim(p_voucher_ref), ''), 40), p_client, auth.uid()) returning id into bid;
  if p_inputs is not null and jsonb_typeof(p_inputs) = 'array' then
    for x in select e2 from jsonb_array_elements(p_inputs) e2 loop
      if not exists (select 1 from public.cost_source_locs where source_id = p_source and location_id = (x->>'location_id')::int) then raise exception 'location_not_covered'; end if;
      if (x->>'dest') not in ('factory', 'showroom', 'admin') then raise exception 'dest_needed'; end if;
      if nullif(btrim(x->>'value'), '') is not null then
        if not ((x->>'value')::numeric >= 0) then raise exception 'bad_qty'; end if;
        insert into public.cost_bill_inputs (bill_id, location_id, dest, value) values (bid, (x->>'location_id')::int, x->>'dest', (x->>'value')::numeric)
          on conflict (bill_id, location_id, dest) do update set value = excluded.value;
      end if;
    end loop;
  end if;
  -- the duplicate guard against form 10-2: same place, month, head and amount (an imprest voucher that already carries this cost)
  heads := case when s.cost_type in ('electricity', 'gas', 'water', 'internet', 'machine_repair') then array['repair'] else array['other'] end;
  select en.id, ln->>'head' into dupid, duph from public.entries en cross join lateral jsonb_array_elements(case when jsonb_typeof(en.data->'lines') = 'array' then en.data->'lines' else '[]'::jsonb end) ln
    where en.form_code = '10-2' and en.status in ('submitted', 'approved') and en.location_id in (select location_id from public.cost_source_locs where source_id = p_source)
      and public._m1(en.entry_date) = m and lower(coalesce(ln->>'head', '')) = any(heads) and public._acct_num(ln->>'amount') = p_amount
    order by en.entry_date desc limit 1;
  if dupid is not null then
    update public.cost_source_bills set dup_entry_id = dupid, dup_head = duph where id = bid;
    perform public._stock_exc((select location_id from public.cost_source_locs where source_id = p_source order by location_id limit 1), 'cost_bill_dup_voucher', 'yellow',
      'খরচের বিল ১০-২ ভাউচারের সাথে মিলে যাচ্ছে (একই জায়গা, মাস, খাত, টাকা) — একবারই ধরুন', 'A cost bill looks like a 10-2 voucher (same place, month, head, amount) - count it once', null, coalesce(p_bill_date, m), 'STOCK', p_amount);
  end if;
  -- hand-typed amounts (rule method other_manual) can never total more than the bill: the whole entry is refused
  if exists (select 1 from public.cost_source_rules r where r.id = public._cs_rule_in_force(p_source, m) and r.method = 'other_manual')
     and coalesce((select sum(value) from public.cost_bill_inputs where bill_id = bid), 0) > p_amount + 0.005 then raise exception 'shares_exceed_bill'; end if;
  perform public._cs_alloc(bid);
  select coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'location_id', location_id, 'dest', dest, 'amount', amount, 'pct', pct, 'flag', flag) order by id), '[]'::jsonb), coalesce(sum(amount) filter (where kind = 'unallocated'), 0)
    into shares, unalloc from public.cost_bill_shares where bill_id = bid and active;
  return jsonb_build_object('id', bid, 'shares', shares, 'unallocated', unalloc, 'dup_voucher', dupid is not null, 'dup_voucher_id', dupid);
end $$;

-- a late sub-meter reading / a rule approved after the bill: allocate again - ONLY a bill that still has an unallocated part (a fully allocated bill never changes)
create or replace function public.cost_bill_reallocate(p_bill bigint, p_inputs jsonb default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare b public.cost_source_bills; x jsonb; unalloc numeric;
begin
  if not public._cs_enter() then raise exception 'not allowed'; end if;
  select * into b from public.cost_source_bills where id = p_bill for update;
  if not found then raise exception 'not_found'; end if;
  if not public._cs_src_ok(b.source_id) then raise exception 'not allowed'; end if;
  if b.status <> 'active' then raise exception 'bill_void'; end if;
  if exists (select 1 from public.cost_bill_shares where bill_id = p_bill and active) and not exists (select 1 from public.cost_bill_shares where bill_id = p_bill and active and kind = 'unallocated') then raise exception 'already_allocated'; end if;
  if p_inputs is not null and jsonb_typeof(p_inputs) = 'array' then
    for x in select e2 from jsonb_array_elements(p_inputs) e2 loop
      if not exists (select 1 from public.cost_source_locs where source_id = b.source_id and location_id = (x->>'location_id')::int) then raise exception 'location_not_covered'; end if;
      if nullif(btrim(x->>'value'), '') is not null then
        insert into public.cost_bill_inputs (bill_id, location_id, dest, value) values (p_bill, (x->>'location_id')::int, x->>'dest', (x->>'value')::numeric) on conflict (bill_id, location_id, dest) do update set value = excluded.value;
      end if;
    end loop;
  end if;
  perform public._cs_alloc(p_bill);
  select coalesce(sum(amount), 0) into unalloc from public.cost_bill_shares where bill_id = p_bill and active and kind = 'unallocated';
  return jsonb_build_object('id', p_bill, 'unallocated', unalloc);
end $$;

create or replace function public.cost_bill_void(p_bill bigint, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare b public.cost_source_bills;
begin
  if not public._cs_enter() then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  select * into b from public.cost_source_bills where id = p_bill for update;
  if not found then raise exception 'not_found'; end if;
  if not public._cs_src_ok(b.source_id) then raise exception 'not allowed'; end if;
  if b.status = 'void' then return; end if;
  update public.cost_source_bills set status = 'void', void_by = auth.uid(), void_at = now(), void_note = left(btrim(p_note), 300) where id = p_bill;
  update public.cost_bill_shares set active = false where bill_id = p_bill and active;
  perform public._cs_push_pools(p_bill);       -- the pool rows of this bill are retired
end $$;

-- "this is a different cost, not the 10-2 one": acknowledges the duplicate flag (kept in the audit log)
create or replace function public.cost_bill_dup_ack(p_bill bigint, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare b public.cost_source_bills;
begin
  if not public._cs_enter() then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  select * into b from public.cost_source_bills where id = p_bill;
  if not found then raise exception 'not_found'; end if;
  if not public._cs_src_ok(b.source_id) then raise exception 'not allowed'; end if;
  update public.cost_source_bills set dup_ack = true, dup_ack_note = left(btrim(p_note), 300) where id = p_bill and dup_entry_id is not null;
end $$;

-- ---------- approval of a rule: a different person; applies from its effective date, never to a fully allocated bill ----------
create or replace function public.cost_rule_approve(p_rule bigint, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.cost_source_rules; b record; n int := 0;
begin
  if not public._cs_approve() then raise exception 'not allowed'; end if;
  select * into r from public.cost_source_rules where id = p_rule for update;
  if not found then raise exception 'not_found'; end if;
  if not public._cs_src_ok(r.source_id) then raise exception 'not allowed'; end if;
  if r.status = 'approved' then return jsonb_build_object('dup', true, 'id', r.id); end if;
  if r.status <> 'draft' then raise exception 'rule_not_draft'; end if;
  if not r.complete then raise exception 'rule_incomplete'; end if;
  if r.created_by is not distinct from auth.uid() and not public.rule_on('cost_rule_self_approve') then raise exception 'self_approve_refused'; end if;
  update public.cost_source_rules set status = 'superseded' where source_id = r.source_id and status = 'approved' and effective_from = r.effective_from;      -- same date: the new one replaces the old (kept)
  update public.cost_source_rules set status = 'approved', approved_by = auth.uid(), approved_at = now() where id = p_rule;
  -- bills that still wait for a split (no rule / blank) may now be allocated; fully allocated bills are NOT touched
  for b in select distinct bl.id from public.cost_source_bills bl where bl.source_id = r.source_id and bl.status = 'active' and bl.period_month >= date_trunc('month', r.effective_from)::date
      and (not exists (select 1 from public.cost_bill_shares x where x.bill_id = bl.id and x.active) or exists (select 1 from public.cost_bill_shares x where x.bill_id = bl.id and x.active and x.kind = 'unallocated')) loop
    perform public._cs_alloc(b.id); n := n + 1;
  end loop;
  return jsonb_build_object('id', p_rule, 'approved', true, 'bills_allocated', n);
end $$;

-- ---------- reports ----------
-- one screen's worth for a month: বিল বাকি, ভাগ নির্ধারিত নয়, অভাগিত, duplicates
create or replace function public.cost_sources_status(p_month date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m date := public._m1(p_month); pend jsonb; noshare jsonb; unal jsonb; dups jsonb;
begin
  if not public._cs_view() then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('source_id', s.id, 'code', s.code, 'cost_type', s.cost_type, 'frequency', s.frequency, 'label_bn', 'বিল বাকি', 'label_en', 'Bill pending') order by s.id), '[]'::jsonb) into pend
    from public.cost_sources s where s.active and public._cs_src_ok(s.id) and s.effective_from <= (m + interval '1 month' - interval '1 day')::date and s.frequency in ('monthly', 'yearly')
     and not exists (select 1 from public.cost_source_bills b where b.source_id = s.id and b.status = 'active' and ((b.period_kind = 'month' and b.period_month = m) or (b.period_kind = 'year' and m >= b.period_month and m < (b.period_month + interval '12 months')::date)));
  select coalesce(jsonb_agg(jsonb_build_object('source_id', s.id, 'code', s.code, 'cost_type', s.cost_type, 'reason', case when rr.id is null then 'no_rule' when rr.status = 'draft' then 'draft' else 'incomplete' end, 'rule_id', rr.id,
      'label_bn', 'ভাগ নির্ধারিত নয়', 'label_en', 'Split not set') order by s.id), '[]'::jsonb) into noshare
    from public.cost_sources s left join lateral (select * from public.cost_source_rules x where x.source_id = s.id and x.status <> 'superseded' order by (x.status = 'approved') desc, x.effective_from desc, x.id desc limit 1) rr on true
   where s.active and s.kind = 'shared' and public._cs_src_ok(s.id) and (public._cs_rule_in_force(s.id, m) is null);
  select coalesce(jsonb_agg(jsonb_build_object('bill_id', b.id, 'source_id', b.source_id, 'amount', x.amount, 'flag', x.flag, 'label_bn', 'অভাগিত', 'label_en', 'Unallocated') order by b.id), '[]'::jsonb) into unal
    from public.cost_bill_shares x join public.cost_source_bills b on b.id = x.bill_id where x.active and x.kind = 'unallocated' and b.status = 'active' and public._cs_src_ok(b.source_id) and b.period_month = m;
  select coalesce(jsonb_agg(jsonb_build_object('bill_id', b.id, 'source_id', b.source_id, 'amount', b.amount, 'voucher_head', b.dup_head, 'entry_id', b.dup_entry_id) order by b.id), '[]'::jsonb) into dups
    from public.cost_source_bills b where b.status = 'active' and b.dup_entry_id is not null and not b.dup_ack and public._cs_src_ok(b.source_id) and b.period_month = m;
  return jsonb_build_object('month', m, 'bills_pending', pend, 'split_not_set', noshare, 'unallocated', unal, 'duplicates', dups);
end $$;

-- the layer-3 view for the BRANCH P&L: showroom + admin shares per place and month (yearly fees spread /12), plus what went into product cost (factory)
create or replace function public.branch_overhead(p_loc int, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows_ jsonb;
begin
  if not (public._cs_view() and (public._all_locs() or public.can_loc(p_loc))) then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('month', z.mth, 'dest', z.dest, 'cost_type', z.cost_type, 'amount', round(z.amt, 2)) order by z.mth, z.dest, z.cost_type), '[]'::jsonb) into rows_ from (
    select (case when b.period_kind = 'month' then b.period_month else (b.period_month + make_interval(months => g))::date end) mth, sh.dest, s.cost_type,
           sum(case when b.period_kind = 'month' then sh.amount else sh.amount / 12 end) amt
      from public.cost_bill_shares sh join public.cost_source_bills b on b.id = sh.bill_id join public.cost_sources s on s.id = b.source_id
      cross join lateral generate_series(0, case when b.period_kind = 'year' then 11 else 0 end) g
     where sh.active and sh.kind = 'share' and b.status = 'active' and sh.location_id = p_loc
       and (case when b.period_kind = 'month' then b.period_month else (b.period_month + make_interval(months => g))::date end) between public._m1(coalesce(p_from, date '2000-01-01')) and coalesce(p_to, date '2999-12-31')
     group by 1, 2, 3) z;
  return jsonb_build_object('location_id', p_loc, 'rows', rows_, 'note', 'showroom / admin rows go to the branch P&L; factory rows are in the product cost through the pools');
end $$;

-- the pickers: every active location of the business, new ones included (nothing in the code names a location)
create or replace function public.cost_pick_locations() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._cs_view() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'code', l.code, 'name_bn', l.name_bn, 'name_en', l.name_en, 'kind', l.kind) order by l.id) from public.locations l where l.is_active and (public._all_locs() or public.can_loc(l.id))), '[]'::jsonb);
end $$;

-- ---------- re-created from phase74: pool_set now warns when a bill already feeds the same pool (two entries would count twice) ----------
create or replace function public.pool_set(p_loc int, p_month date, p_type text, p_amount numeric, p_period_kind text default 'month', p_one_off boolean default false, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d public.factory_cost_pools; nid bigint; m date := public._m1(p_month); alloc boolean;
begin
  if not (public._recipe_cost_ok() and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then select * into d from public.factory_cost_pools where client_id = p_client; if found then return jsonb_build_object('dup', true, 'id', d.id); end if; end if;
  if p_month is null then raise exception 'bad_date'; end if;
  if not exists (select 1 from public.cost_component_types where code = p_type and active) then raise exception 'unknown_type'; end if;
  if p_period_kind not in ('month', 'year') then raise exception 'bad_value'; end if;
  if p_amount is null or not (p_amount >= 0 and p_amount <= 1000000000000) then raise exception 'bad_cost'; end if;
  perform public.lock_check(m);
  update public.factory_cost_pools set active = false where location_id = p_loc and month = m and component_type = p_type and period_kind = p_period_kind and source = 'manual' and active;
  insert into public.factory_cost_pools (location_id, month, component_type, period_kind, actual_amount, one_off, source, note, client_id, created_by)
    values (p_loc, m, p_type, p_period_kind, p_amount, coalesce(p_one_off, false), 'manual', left(p_note, 200), p_client, auth.uid()) returning id into nid;
  alloc := exists (select 1 from public.factory_cost_pools where location_id = p_loc and month = m and component_type = p_type and period_kind = p_period_kind and source = 'allocated' and active);      -- bos75
  if alloc then
    perform public._stock_exc(p_loc, 'pool_double_entry', 'yellow', 'এই মাসের এই খরচ বিল থেকে আগেই এসেছে — হাতে আবার লিখলে দুবার গোনা হবে',
      'A cost bill already feeds this pool - a manual amount on top is counted twice', null, m, 'STOCK');
  end if;
  return jsonb_build_object('id', nid, 'allocated_exists', alloc);
end $$;

-- ---------- privileges ----------
grant execute on function public._cs_src_ok(bigint), public._cs_view() to authenticated;       -- used by the read policies
revoke all on function public._cs_no_delete(), public._cs_enter(), public._cs_approve(), public._cs_rule_in_force(bigint, date), public._cs_alloc(bigint), public._cs_push_pools(bigint) from public, anon, authenticated;
revoke all on function public._cs_view(), public._cs_src_ok(bigint) from public, anon;
revoke all on function public.cost_source_type_add(text, text, text), public.cost_source_save(bigint, text, text, text, text, int[], text, date, text, uuid), public.cost_source_set_active(bigint, boolean, text),
  public.cost_rule_save(bigint, text, date, jsonb, text, uuid), public.cost_bill_add(bigint, text, date, numeric, text, text, date, boolean, jsonb, text, uuid), public.cost_bill_reallocate(bigint, jsonb),
  public.cost_bill_void(bigint, text), public.cost_bill_dup_ack(bigint, text), public.cost_rule_approve(bigint, text), public.cost_sources_status(date), public.branch_overhead(int, date, date),
  public.cost_pick_locations(), public.pool_set(int, date, text, numeric, text, boolean, text, uuid) from public, anon;
grant execute on function public.cost_source_type_add(text, text, text), public.cost_source_save(bigint, text, text, text, text, int[], text, date, text, uuid), public.cost_source_set_active(bigint, boolean, text),
  public.cost_rule_save(bigint, text, date, jsonb, text, uuid), public.cost_bill_add(bigint, text, date, numeric, text, text, date, boolean, jsonb, text, uuid), public.cost_bill_reallocate(bigint, jsonb),
  public.cost_bill_void(bigint, text), public.cost_bill_dup_ack(bigint, text), public.cost_rule_approve(bigint, text), public.cost_sources_status(date), public.branch_overhead(int, date, date),
  public.cost_pick_locations(), public.pool_set(int, date, text, numeric, text, boolean, text, uuid) to authenticated;
