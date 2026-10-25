-- ============================================================
-- Phase 129 (marker dl129) - DEALER / HARDWARE-PAINT BUSINESS, part 3: TINTING machine (ADDITIVE ONLY).
-- Canonical order: after phase128 (uses phase127's scope helpers). Paste twice = no change, no error.
-- Rule dealer_tint_on is OFF by default: while OFF every write function refuses ('feature_off'); the dry run (preview) and reads still work.
--   Table dealer_shades           a shade code (and name) of one business. Owner data, nothing seeded.
--   Table dealer_tint_formulas    one VERSION of the formula of a shade for one BASE item (the base paint in its pack, e.g. "Emulsion white base 4L") and a pack label.
--                                 base_qty_per_pack = base units used per pack tinted. Same idea as the recipe engine (versioned, never edited: a change = a new version,
--                                 the old one is retired; status active | retired; one active version per shade + base).
--   Table dealer_tint_formula_lines  the colorants: colorant item + quantity per ONE pack (in the item's base unit, e.g. ml). Append-only.
--   Table dealer_tint_jobs        one tint job: formula, packs, customer (optional), cost, charge (entered), status done | void. Cost columns are not readable by the
--                                 browser role; they are returned only to the owner / rpt_cost_ok() users by tint_job_cost / tint_cost_report.
--   Table dealer_tint_job_lines   what the job consumed: the base + each colorant (qty, and cost for cost-visible users).
--   Stock: tint_job_run consumes base + colorants with the EXISTING stock_post (reason issue_out, ref_type tint_job, ref_id = job id) at the average cost of the moment,
--     honouring the stock_negative_mode rule (block / warn); tint_job_void reverses every row with stock_post (reason reversal, reverses_id) - the ledger is never edited.
--     Nothing is posted to the books by this phase (the existing acct_issue_out switch decides that for issue_out rows; it is OFF by default).
--   p_dry = true on tint_job_run is the PREVIEW: it writes nothing and returns the quantities, on-hand stock, shortages and (cost-visible users) the estimated cost.
--   Shade history per customer: tint_customer_shades. Business scope exactly as phase127 (owner, or explicitly assigned location + grant, inside that business).
--   Grants dealer_tint_view, dealer_tint_manage (shades, formulas), dealer_tint_run (jobs). Costs: owner or rpt_cost_ok().
-- Rollback: leave dealer_tint_on OFF. To remove: drop the functions and the five tables (nothing else refers to them).
-- ============================================================
begin;

do $g$
declare miss text := '';
begin
  if to_regclass('public.dealer_cheques') is null or to_regprocedure('public._dl_ok127(integer,text,text)') is null or to_regprocedure('public._dl_biz_ok127(bigint,text,text)') is null
     or to_regprocedure('public._dl_biz127(integer)') is null or to_regprocedure('public._dl_append_only127()') is null then miss := miss || ' phase127'; end if;
  if to_regclass('public.items') is null or to_regclass('public.stock_ledger') is null or to_regclass('public.stock_balance') is null or to_regclass('public.customers') is null then miss := miss || ' tables'; end if;
  if to_regprocedure('public.stock_post(uuid,integer,numeric,text,text,text,numeric,bigint,timestamp with time zone,text,bigint,text,uuid,uuid)') is null
     or to_regprocedure('public.rpt_cost_ok()') is null then miss := miss || ' functions'; end if;
  if miss <> '' then raise exception 'phase129 needs the base schema and phases up to 128 pasted first (docs/PASTE_ORDER.md); missing:%', miss; end if;
end $g$;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type)
select v.c, 'dealer', v.s, v.b, v.m, v.e, 'once' from (values
  ('dealer_tint_view', 131, 'টিন্টিং ফর্মুলা ও জব দেখা', 'Tinting formula ও job দেখা', 'View tinting formulas and jobs'),
  ('dealer_tint_manage', 132, 'শেড ও টিন্টিং ফর্মুলা তৈরি', 'Shade ও tinting formula তৈরি', 'Create shades and tinting formulas'),
  ('dealer_tint_run', 133, 'টিন্টিং জব চালানো (বেস ও কালারেন্ট স্টক থেকে কাটা)', 'Tinting job চালানো (base ও colorant stock থেকে কাটা)', 'Run tint jobs (consumes base and colorants from stock)')
) v(c, s, b, m, e) where not exists (select 1 from public.grant_defs g where g.grant_code = v.c);

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('dealer_tint_on', 'dealer', 'switch', 'false', null, null, null, null,
  'টিন্টিং মেশিন চালু', 'Tinting machine চালু', 'Tinting machine',
  'চালু করলে শেড ফর্মুলা ও টিন্ট জব লেখা যাবে; জব বেস ও কালারেন্ট স্টক থেকে কাটে।',
  'চালু করলে shade formula ও tint job লেখা যাবে; job base ও colorant stock থেকে কাটে।',
  'When on, shade formulas and tint jobs can be written; a job consumes the base and colorants from stock.', 1290)
on conflict (key) do nothing;

insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort)
select 'dealer_tint_on', 'dealer_tint_on', '129', 'dealer', null::jsonb, '{}'::text[],
  'যে দোকানে টিন্টিং মেশিন আছে শুধু সেখানে চালু করুন।', 'যে দোকানে tinting machine আছে শুধু সেখানে চালু করুন।',
  'Turn on only for a shop that has a tinting machine.', 1290
where not exists (select 1 from public.setup_rec_defs81 where code = 'dealer_tint_on');

-- ---------- tables ----------
create table if not exists public.dealer_shades (
  id uuid primary key default gen_random_uuid(),
  business_id bigint not null references public.org_units(id),
  shade_code text not null check (shade_code = upper(btrim(shade_code)) and length(shade_code) between 1 and 40),
  name text check (name is null or length(name) <= 120),
  active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now(),
  unique (business_id, shade_code)
);
create table if not exists public.dealer_tint_formulas (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null unique,
  business_id bigint not null references public.org_units(id),
  shade_id uuid not null references public.dealer_shades(id),
  base_item_id uuid not null references public.items(id),
  pack_label text check (pack_label is null or length(pack_label) <= 40),
  base_qty_per_pack numeric(14,4) not null default 1 check (base_qty_per_pack > 0 and base_qty_per_pack <= 1000000),
  version int not null check (version >= 1),
  status text not null default 'active' check (status in ('active', 'retired')),
  used_at timestamptz,
  note text check (note is null or length(note) <= 300),
  created_by uuid, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (shade_id, base_item_id, version)
);
create unique index if not exists dealer_tint_formulas_active129 on public.dealer_tint_formulas (shade_id, base_item_id) where status = 'active';
create table if not exists public.dealer_tint_formula_lines (
  formula_id uuid not null references public.dealer_tint_formulas(id),
  seq int not null check (seq >= 1),
  colorant_item_id uuid not null references public.items(id),
  qty_per_pack numeric(14,4) not null check (qty_per_pack > 0 and qty_per_pack <= 1000000),
  business_id bigint not null references public.org_units(id),
  primary key (formula_id, seq),
  unique (formula_id, colorant_item_id)
);
create table if not exists public.dealer_tint_jobs (
  id uuid primary key default gen_random_uuid(),
  job_no bigint generated by default as identity,
  client_id uuid not null unique,
  business_id bigint not null references public.org_units(id),
  location_id int not null references public.locations(id),
  formula_id uuid not null references public.dealer_tint_formulas(id),
  shade_id uuid not null references public.dealer_shades(id),
  shade_code text not null,
  formula_version int not null,
  base_item_id uuid not null references public.items(id),
  customer_id uuid references public.customers(id),
  customer_name text check (customer_name is null or length(customer_name) <= 120),
  packs numeric(12,3) not null check (packs > 0 and packs <= 100000),
  job_date date not null,
  charge_amount numeric(16,2) check (charge_amount is null or (charge_amount >= 0 and charge_amount <= 1000000000000)),
  cost_total numeric(16,2),                       -- SECRET (cost): not granted to the browser role
  cost_known boolean,                             -- SECRET
  status text not null default 'done' check (status in ('done', 'void')),
  note text check (note is null or length(note) <= 300),
  void_note text, void_by uuid, void_at timestamptz,
  created_by uuid, created_at timestamptz not null default now()
);
create index if not exists dealer_tint_jobs_loc129 on public.dealer_tint_jobs (location_id, job_date);
create index if not exists dealer_tint_jobs_cust129 on public.dealer_tint_jobs (customer_id, job_date) where customer_id is not null;
create table if not exists public.dealer_tint_job_lines (
  job_id uuid not null references public.dealer_tint_jobs(id),
  seq int not null,
  role text not null check (role in ('base', 'colorant')),
  item_id uuid not null references public.items(id),
  qty numeric(18,4) not null check (qty > 0),
  unit_cost numeric,                              -- SECRET
  cost numeric(16,2),                             -- SECRET
  business_id bigint not null references public.org_units(id),
  location_id int not null references public.locations(id),
  primary key (job_id, seq)
);

-- records: formulas change only status / used_at; formula lines are append-only; jobs change only status / void columns / cost columns
create or replace function public._tint_formula_guard129() returns trigger language plpgsql set search_path = public as $$
begin
  if (new.business_id, new.shade_id, new.base_item_id, new.pack_label, new.base_qty_per_pack, new.version, new.note, new.client_id)
     is distinct from (old.business_id, old.shade_id, old.base_item_id, old.pack_label, old.base_qty_per_pack, old.version, old.note, old.client_id) then
    raise exception 'formula_frozen'; end if;
  return new;
end $$;
create or replace function public._tint_job_guard129() returns trigger language plpgsql set search_path = public as $$
begin
  if old.status = 'void' then raise exception 'job_void'; end if;
  if (new.business_id, new.location_id, new.formula_id, new.shade_id, new.shade_code, new.formula_version, new.base_item_id, new.customer_id, new.customer_name, new.packs, new.job_date, new.charge_amount, new.client_id)
     is distinct from (old.business_id, old.location_id, old.formula_id, old.shade_id, old.shade_code, old.formula_version, old.base_item_id, old.customer_id, old.customer_name, old.packs, old.job_date, old.charge_amount, old.client_id) then
    raise exception 'job_frozen'; end if;
  return new;
end $$;
drop trigger if exists dealer_tint_formulas_guard on public.dealer_tint_formulas;
create trigger dealer_tint_formulas_guard before update on public.dealer_tint_formulas for each row execute function public._tint_formula_guard129();
drop trigger if exists dealer_tint_jobs_guard on public.dealer_tint_jobs;
create trigger dealer_tint_jobs_guard before update on public.dealer_tint_jobs for each row execute function public._tint_job_guard129();
drop trigger if exists dealer_tint_formula_lines_ro on public.dealer_tint_formula_lines;
create trigger dealer_tint_formula_lines_ro before update or delete on public.dealer_tint_formula_lines for each row execute function public._dl_append_only127();
drop trigger if exists dealer_tint_job_lines_ro on public.dealer_tint_job_lines;
create trigger dealer_tint_job_lines_ro before delete on public.dealer_tint_job_lines for each row execute function public._dl_append_only127();
do $t$ declare t text; begin
  foreach t in array array['dealer_shades', 'dealer_tint_formulas', 'dealer_tint_jobs'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_no_delete', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_no_delete', t);
    execute format('drop trigger if exists %I on public.%I', 'audit_' || t, t);
    execute format('create trigger %I after insert or update on public.%I for each row execute function public.log_change(%L)', 'audit_' || t, t, 'id');
  end loop;
end $t$;

-- RLS: business-level for shades / formulas, location-level for jobs
alter table public.dealer_shades enable row level security;
alter table public.dealer_tint_formulas enable row level security;
alter table public.dealer_tint_formula_lines enable row level security;
alter table public.dealer_tint_jobs enable row level security;
alter table public.dealer_tint_job_lines enable row level security;
drop policy if exists dealer_shades_read129 on public.dealer_shades;
create policy dealer_shades_read129 on public.dealer_shades for select to authenticated using (public._dl_biz_ok127(business_id, 'dealer_tint_view', 'dealer_tint_manage'));
drop policy if exists dealer_tint_formulas_read129 on public.dealer_tint_formulas;
create policy dealer_tint_formulas_read129 on public.dealer_tint_formulas for select to authenticated using (public._dl_biz_ok127(business_id, 'dealer_tint_view', 'dealer_tint_manage'));
drop policy if exists dealer_tint_formula_lines_read129 on public.dealer_tint_formula_lines;
create policy dealer_tint_formula_lines_read129 on public.dealer_tint_formula_lines for select to authenticated using (public._dl_biz_ok127(business_id, 'dealer_tint_view', 'dealer_tint_manage'));
drop policy if exists dealer_tint_jobs_read129 on public.dealer_tint_jobs;
create policy dealer_tint_jobs_read129 on public.dealer_tint_jobs for select to authenticated using (public._dl_ok127(location_id, 'dealer_tint_view', 'dealer_tint_run'));
drop policy if exists dealer_tint_job_lines_read129 on public.dealer_tint_job_lines;
create policy dealer_tint_job_lines_read129 on public.dealer_tint_job_lines for select to authenticated using (public._dl_ok127(location_id, 'dealer_tint_view', 'dealer_tint_run'));
revoke all on public.dealer_shades, public.dealer_tint_formulas, public.dealer_tint_formula_lines, public.dealer_tint_jobs, public.dealer_tint_job_lines from public, anon, authenticated;
grant select on public.dealer_shades, public.dealer_tint_formulas, public.dealer_tint_formula_lines to authenticated;
grant select (id, job_no, client_id, business_id, location_id, formula_id, shade_id, shade_code, formula_version, base_item_id, customer_id, customer_name, packs, job_date, charge_amount, status, note, void_note, void_at, created_at)
  on public.dealer_tint_jobs to authenticated;                                  -- cost_total / cost_known are NOT granted
grant select (job_id, seq, role, item_id, qty, business_id, location_id) on public.dealer_tint_job_lines to authenticated;      -- unit_cost / cost are NOT granted

-- ---------- helpers ----------
create or replace function public._tint_gate129(p_biz bigint, p_loc int, p_grant text, p_write boolean) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_loc is not null then
    if not (case when p_write then public._dl_ok127(p_loc, p_grant) else public._dl_ok127(p_loc, 'dealer_tint_view', p_grant) end) then raise exception 'not allowed'; end if;
  else
    if not (case when p_write then public._dl_biz_ok127(p_biz, p_grant) else public._dl_biz_ok127(p_biz, 'dealer_tint_view', p_grant) end) then raise exception 'not allowed'; end if;
  end if;
  if p_write and not public.rule_on('dealer_tint_on') then raise exception 'feature_off'; end if;
end $$;

-- ---------- shades and formulas ----------
-- Creates the shade if the code is new, then a NEW version of the formula for (shade, base). The previous active version of that pair becomes retired.
-- p_lines: [{"item": "<colorant item id>", "qty": <per ONE pack, item base unit>}]
create or replace function public.tint_formula_save(p_client uuid, p_business bigint, p_shade_code text, p_shade_name text, p_base_item uuid, p_pack_label text, p_base_qty numeric,
  p_lines jsonb, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare f public.dealer_tint_formulas; sh public.dealer_shades; code text; v int; fid uuid; l jsonb; n int := 0; q numeric; it uuid; bq numeric;
begin
  perform public._tint_gate129(p_business, null, 'dealer_tint_manage', true);
  if p_client is null then raise exception 'client_required'; end if;
  perform public._client_lock(p_client);
  select * into f from public.dealer_tint_formulas where client_id = p_client;
  if found then
    if f.business_id <> p_business then raise exception 'client_key_used'; end if;
    return jsonb_build_object('id', f.id, 'version', f.version, 'dup', true);
  end if;
  if not exists (select 1 from public.dl_unit_tree127 u where u.id = p_business and u.kind = 'business') then raise exception 'bad_business'; end if;
  code := upper(btrim(coalesce(p_shade_code, '')));
  if length(code) not between 1 and 40 then raise exception 'shade_code_required'; end if;
  if p_shade_name is not null and length(p_shade_name) > 120 then raise exception 'name_too_long'; end if;
  if not exists (select 1 from public.items i where i.id = p_base_item) then raise exception 'item_not_found'; end if;
  if p_pack_label is not null and length(p_pack_label) > 40 then raise exception 'pack_label_too_long'; end if;
  if p_note is not null and length(p_note) > 300 then raise exception 'note_too_long'; end if;
  if p_base_qty is null or p_base_qty = 'NaN'::numeric or not (p_base_qty between 0.0001 and 1000000) then raise exception 'bad_qty'; end if;
  bq := round(p_base_qty, 4);
  if bq <= 0 then raise exception 'bad_qty'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'lines_required'; end if;
  if jsonb_array_length(p_lines) > 40 then raise exception 'too_many_lines'; end if;
  -- validate every line before anything is written
  for l in select * from jsonb_array_elements(p_lines) loop
    begin it := (l->>'item')::uuid; q := (l->>'qty')::numeric; exception when others then raise exception 'bad_line'; end;
    if it is null or q is null or q = 'NaN'::numeric or not (q between 0.0001 and 1000000) or round(q, 4) <= 0 then raise exception 'bad_qty'; end if;
    if not exists (select 1 from public.items i where i.id = it) then raise exception 'item_not_found'; end if;
    if it = p_base_item then raise exception 'colorant_is_base'; end if;
  end loop;
  if (select count(distinct (x->>'item')) from jsonb_array_elements(p_lines) x) <> jsonb_array_length(p_lines) then raise exception 'duplicate_colorant'; end if;
  insert into public.dealer_shades (business_id, shade_code, name, created_by) values (p_business, code, nullif(btrim(coalesce(p_shade_name, '')), ''), auth.uid())
    on conflict (business_id, shade_code) do update set name = coalesce(nullif(btrim(coalesce(p_shade_name, '')), ''), public.dealer_shades.name)
    returning * into sh;
  if not sh.active then raise exception 'shade_inactive'; end if;
  select coalesce(max(version), 0) + 1 into v from public.dealer_tint_formulas where shade_id = sh.id and base_item_id = p_base_item;
  update public.dealer_tint_formulas set status = 'retired', updated_at = now() where shade_id = sh.id and base_item_id = p_base_item and status = 'active';
  insert into public.dealer_tint_formulas (client_id, business_id, shade_id, base_item_id, pack_label, base_qty_per_pack, version, note, created_by)
    values (p_client, p_business, sh.id, p_base_item, nullif(btrim(coalesce(p_pack_label, '')), ''), bq, v, nullif(btrim(coalesce(p_note, '')), ''), auth.uid()) returning id into fid;
  for l in select * from jsonb_array_elements(p_lines) loop
    n := n + 1;
    insert into public.dealer_tint_formula_lines (formula_id, seq, colorant_item_id, qty_per_pack, business_id) values (fid, n, (l->>'item')::uuid, round((l->>'qty')::numeric, 4), p_business);
  end loop;
  return jsonb_build_object('id', fid, 'shade_id', sh.id, 'shade_code', code, 'version', v, 'status', 'active');
end $$;

create or replace function public.tint_formula_retire(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare f public.dealer_tint_formulas;
begin
  select * into f from public.dealer_tint_formulas where id = p_id;
  if not found then raise exception 'formula_not_found'; end if;
  perform public._tint_gate129(f.business_id, null, 'dealer_tint_manage', true);
  if f.status = 'retired' then return jsonb_build_object('id', f.id, 'status', 'retired', 'dup', true); end if;
  update public.dealer_tint_formulas set status = 'retired', updated_at = now() where id = p_id;
  return jsonb_build_object('id', f.id, 'status', 'retired');
end $$;

-- ---------- the job ----------
create or replace function public._tint_uuid129(p_client uuid, p_seq int) returns uuid
language sql immutable set search_path = public as $$ select md5(p_client::text || ':tint:' || p_seq::text)::uuid; $$;

create or replace function public.tint_job_run(p_client uuid, p_loc int, p_formula uuid, p_packs numeric, p_customer uuid default null, p_customer_name text default null,
  p_date date default null, p_charge numeric default null, p_note text default null, p_dry boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare f public.dealer_tint_formulas; sh public.dealer_shades; j public.dealer_tint_jobs; today date := public._dl_today127(); d date; packs numeric; biz bigint; jid uuid := gen_random_uuid();
        lines jsonb := '[]'::jsonb; r record; q numeric; n int := 0; onhand numeric; avgc numeric; est numeric := 0; est_ok boolean := true; costok boolean := public.is_owner() or public.rpt_cost_ok();
        short boolean := false; tot numeric; known boolean; lid bigint; sid text; chg numeric;
begin
  select * into f from public.dealer_tint_formulas where id = p_formula;
  if not found then raise exception 'formula_not_found'; end if;
  biz := public._dl_biz127(p_loc);
  if biz is null or biz <> f.business_id then raise exception 'not allowed'; end if;
  perform public._tint_gate129(biz, p_loc, 'dealer_tint_run', not coalesce(p_dry, false));
  if f.status <> 'active' then raise exception 'formula_retired'; end if;
  if p_packs is null or p_packs = 'NaN'::numeric or not (p_packs between 0.001 and 100000) then raise exception 'bad_packs'; end if;
  packs := round(p_packs, 3);
  if packs <= 0 then raise exception 'bad_packs'; end if;
  d := coalesce(p_date, today);
  if d > today or d < today - 3 then raise exception 'bad_date'; end if;
  if p_customer_name is not null and length(p_customer_name) > 120 then raise exception 'name_too_long'; end if;
  if p_note is not null and length(p_note) > 300 then raise exception 'note_too_long'; end if;
  if p_charge is not null and (p_charge = 'NaN'::numeric or not (p_charge between 0 and 1000000000000)) then raise exception 'bad_amount'; end if;
  chg := round(p_charge, 2);
  if p_customer is not null and not exists (select 1 from public.customers c where c.id = p_customer) then raise exception 'customer_not_found'; end if;
  select * into sh from public.dealer_shades where id = f.shade_id;
  -- the lines: base first, then colorants
  for r in select 'base'::text role, f.base_item_id item, round(packs * f.base_qty_per_pack, 4) qty, 0 s
           union all select 'colorant', fl.colorant_item_id, round(packs * fl.qty_per_pack, 4), fl.seq from public.dealer_tint_formula_lines fl where fl.formula_id = f.id
           order by 4 loop
    if r.qty <= 0 then raise exception 'bad_qty'; end if;
    select b.qty, b.avg_cost into onhand, avgc from public.stock_balance b where b.item_id = r.item and b.location_id = p_loc;
    onhand := coalesce(onhand, 0);
    if onhand < r.qty then short := true; end if;
    if avgc is null then est_ok := false; else est := est + r.qty * avgc; end if;
    lines := lines || jsonb_build_object('role', r.role, 'item_id', r.item, 'qty', r.qty, 'on_hand', onhand, 'short', onhand < r.qty);
  end loop;
  if p_dry then
    return jsonb_build_object('dry', true, 'shade_code', sh.shade_code, 'formula_version', f.version, 'packs', packs, 'lines', lines, 'short', short,
      'estimated_cost', case when costok and est_ok then round(est, 2) end);
  end if;
  if p_client is null then raise exception 'client_required'; end if;
  perform public._client_lock(p_client);
  select * into j from public.dealer_tint_jobs where client_id = p_client;
  if found then
    if j.location_id <> p_loc then raise exception 'client_key_used'; end if;
    return jsonb_build_object('id', j.id, 'job_no', j.job_no, 'status', j.status, 'dup', true);
  end if;
  perform public.lock_check(d);
  insert into public.dealer_tint_jobs (id, client_id, business_id, location_id, formula_id, shade_id, shade_code, formula_version, base_item_id, customer_id, customer_name, packs, job_date, charge_amount, note, created_by)
    values (jid, p_client, biz, p_loc, f.id, f.shade_id, sh.shade_code, f.version, f.base_item_id, p_customer, nullif(btrim(coalesce(p_customer_name, '')), ''), packs, d, chg, nullif(btrim(coalesce(p_note, '')), ''), auth.uid());
  -- consume from stock through the existing stock function (average cost of the moment); stock_negative_mode decides what a shortage does
  for r in select (x->>'role') role, (x->>'item_id')::uuid item, (x->>'qty')::numeric qty from jsonb_array_elements(lines) x loop
    n := n + 1;
    lid := public.stock_post(r.item, p_loc, -r.qty, 'issue_out', 'tint_job', jid::text, null, null, (d::timestamp + time '12:00') at time zone 'Asia/Dhaka', left('tint ' || sh.shade_code, 200), null, 'full', null, public._tint_uuid129(p_client, n));
    insert into public.dealer_tint_job_lines (job_id, seq, role, item_id, qty, business_id, location_id) values (jid, n, r.role, r.item, r.qty, biz, p_loc);
  end loop;
  -- cost from the ledger rows just written (one line may span several batches)
  update public.dealer_tint_job_lines jl set
    unit_cost = case when s.q > 0 then round(s.c / s.q, 6) end,
    cost = round(s.c, 2)
    from (select l.item_id, sum(-l.qty_delta) q, sum(-l.qty_delta * l.unit_cost) c from public.stock_ledger l where l.ref_type = 'tint_job' and l.ref_id = jid::text and l.reason = 'issue_out' and l.unit_cost is not null group by l.item_id) s
    where jl.job_id = jid and jl.item_id = s.item_id;
  select coalesce(sum(cost), 0), bool_and(cost is not null) into tot, known from public.dealer_tint_job_lines where job_id = jid;
  update public.dealer_tint_jobs set cost_total = tot, cost_known = coalesce(known, false) where id = jid;
  if f.used_at is null then update public.dealer_tint_formulas set used_at = now() where id = f.id; end if;
  return jsonb_build_object('id', jid, 'job_no', (select job_no from public.dealer_tint_jobs where id = jid), 'status', 'done', 'shade_code', sh.shade_code, 'packs', packs, 'lines', lines, 'short', short,
    'cost_total', case when costok then tot end, 'cost_known', case when costok then coalesce(known, false) end);
end $$;

create or replace function public.tint_job_void(p_job uuid, p_client uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.dealer_tint_jobs; r record;
begin
  select * into j from public.dealer_tint_jobs where id = p_job;
  if not found then raise exception 'job_not_found'; end if;
  perform public._tint_gate129(j.business_id, j.location_id, 'dealer_tint_run', true);
  if p_client is null then raise exception 'client_required'; end if;
  perform public._client_lock(p_client);
  select * into j from public.dealer_tint_jobs where id = p_job for update;
  if j.status = 'void' then return jsonb_build_object('id', j.id, 'status', 'void', 'dup', true); end if;
  if p_reason is null or length(btrim(p_reason)) not between 1 and 200 then raise exception 'reason_required'; end if;
  perform public.lock_check(j.job_date);
  for r in select * from public.stock_ledger o where o.ref_type = 'tint_job' and o.ref_id = j.id::text and o.reason = 'issue_out'
           and not exists (select 1 from public.stock_ledger v where v.reverses_id = o.id) order by o.item_id, o.id loop
    perform public.stock_post(r.item_id, r.location_id, -r.qty_delta, 'reversal', 'tint_job', j.id::text, r.unit_cost, r.batch_id, now(), left('void: ' || btrim(p_reason), 200), r.id, 'soft');
  end loop;
  update public.dealer_tint_jobs set status = 'void', void_note = left(btrim(p_reason), 200), void_by = auth.uid(), void_at = now() where id = j.id;
  return jsonb_build_object('id', j.id, 'status', 'void');
end $$;

-- ---------- reads ----------
create or replace function public.tint_formula_list(p_business bigint, p_shade text default null, p_status text default null)
returns table (id uuid, shade_code text, shade_name text, base_item_id uuid, pack_label text, base_qty_per_pack numeric, version int, status text, used boolean, colorants int)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._tint_gate129(p_business, null, 'dealer_tint_manage', false);
  return query
    select f.id, s.shade_code, s.name, f.base_item_id, f.pack_label, f.base_qty_per_pack, f.version, f.status, f.used_at is not null,
           (select count(*)::int from public.dealer_tint_formula_lines l where l.formula_id = f.id)
    from public.dealer_tint_formulas f join public.dealer_shades s on s.id = f.shade_id
    where f.business_id = p_business and (p_shade is null or s.shade_code = upper(btrim(p_shade))) and (p_status is null or f.status = p_status)
    order by s.shade_code, f.base_item_id, f.version desc;
end $$;

create or replace function public.tint_formula_get(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f public.dealer_tint_formulas;
begin
  select * into f from public.dealer_tint_formulas where id = p_id;
  if not found then raise exception 'formula_not_found'; end if;
  perform public._tint_gate129(f.business_id, null, 'dealer_tint_manage', false);
  return (to_jsonb(f) - 'client_id') || jsonb_build_object('shade_code', (select shade_code from public.dealer_shades where id = f.shade_id),
    'lines', coalesce((select jsonb_agg(jsonb_build_object('seq', l.seq, 'item_id', l.colorant_item_id, 'qty_per_pack', l.qty_per_pack) order by l.seq) from public.dealer_tint_formula_lines l where l.formula_id = f.id), '[]'::jsonb));
end $$;

create or replace function public.tint_job_list(p_business bigint, p_from date default null, p_to date default null, p_customer uuid default null, p_limit int default 200)
returns table (id uuid, job_no bigint, location_id int, shade_code text, formula_version int, base_item_id uuid, customer_id uuid, customer_name text, packs numeric, job_date date, charge_amount numeric, status text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return query
    select j.id, j.job_no, j.location_id, j.shade_code, j.formula_version, j.base_item_id, j.customer_id, coalesce((select c.name from public.customers c where c.id = j.customer_id), j.customer_name), j.packs, j.job_date, j.charge_amount, j.status
    from public.dealer_tint_jobs j
    where j.business_id = p_business and public._dl_ok127(j.location_id, 'dealer_tint_view', 'dealer_tint_run')
      and (p_from is null or j.job_date >= p_from) and (p_to is null or j.job_date <= p_to) and (p_customer is null or j.customer_id = p_customer)
    order by j.job_date desc, j.job_no desc limit greatest(1, least(coalesce(p_limit, 200), 1000));
end $$;

-- the shade codes a customer has had mixed (history), only from jobs the caller may see
create or replace function public.tint_customer_shades(p_customer uuid, p_business bigint default null)
returns table (shade_code text, jobs int, packs numeric, last_date date, last_base_item uuid, last_formula_version int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return query
    select j.shade_code, count(*)::int, sum(j.packs), max(j.job_date), (array_agg(j.base_item_id order by j.job_date desc, j.job_no desc))[1], (array_agg(j.formula_version order by j.job_date desc, j.job_no desc))[1]
    from public.dealer_tint_jobs j
    where j.customer_id = p_customer and j.status = 'done' and public._dl_ok127(j.location_id, 'dealer_tint_view', 'dealer_tint_run') and (p_business is null or j.business_id = p_business)
    group by j.shade_code order by max(j.job_date) desc, j.shade_code;
end $$;

-- COST (owner or rpt_cost_ok only): cost per job and the cost of the colorants / base, margin against the entered charge
create or replace function public.tint_job_cost(p_job uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare j public.dealer_tint_jobs;
begin
  select * into j from public.dealer_tint_jobs where id = p_job;
  if not found then raise exception 'job_not_found'; end if;
  perform public._tint_gate129(j.business_id, j.location_id, 'dealer_tint_run', false);
  if not (public.is_owner() or public.rpt_cost_ok()) then raise exception 'not allowed'; end if;
  return jsonb_build_object('id', j.id, 'job_no', j.job_no, 'shade_code', j.shade_code, 'packs', j.packs, 'status', j.status, 'cost_total', j.cost_total, 'cost_known', j.cost_known, 'charge', j.charge_amount,
    'margin', case when j.charge_amount is not null and j.cost_total is not null then round(j.charge_amount - j.cost_total, 2) end,
    'cost_per_pack', case when j.cost_total is not null then round(j.cost_total / j.packs, 4) end,
    'lines', coalesce((select jsonb_agg(jsonb_build_object('seq', l.seq, 'role', l.role, 'item_id', l.item_id, 'qty', l.qty, 'unit_cost', l.unit_cost, 'cost', l.cost) order by l.seq) from public.dealer_tint_job_lines l where l.job_id = j.id), '[]'::jsonb));
end $$;

create or replace function public.tint_cost_report(p_business bigint, p_from date default null, p_to date default null)
returns table (shade_code text, jobs int, packs numeric, cost_total numeric, cost_per_pack numeric, charge_total numeric, unknown_cost_jobs int)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._tint_gate129(p_business, null, 'dealer_tint_run', false);
  if not (public.is_owner() or public.rpt_cost_ok()) then raise exception 'not allowed'; end if;
  return query
    select j.shade_code, count(*)::int, sum(j.packs), sum(coalesce(j.cost_total, 0)), case when sum(j.packs) > 0 then round(sum(coalesce(j.cost_total, 0)) / sum(j.packs), 4) end, sum(coalesce(j.charge_amount, 0)),
           (count(*) filter (where not coalesce(j.cost_known, false)))::int
    from public.dealer_tint_jobs j
    where j.business_id = p_business and j.status = 'done' and public._dl_ok127(j.location_id, 'dealer_tint_view', 'dealer_tint_run')
      and (p_from is null or j.job_date >= p_from) and (p_to is null or j.job_date <= p_to)
    group by j.shade_code order by 4 desc, 1;
end $$;

-- ---------- business templates: say honestly what exists (status is NOT changed: neither template is ready for use as a whole) ----------
-- filled only while the list is still empty, so a second paste (or an owner edit) is never overwritten. built = a database part with tests (phase 127-129); not_built = nothing exists yet.
update public.business_templates set modules = '[
  {"code":"cheque_pdc","state":"built","phase":127,"rule":"dealer_cheque_on"},
  {"code":"principal_schemes","state":"built","phase":128,"rule":"dealer_scheme_on"},
  {"code":"tinting","state":"built","phase":129,"rule":"dealer_tint_on"},
  {"code":"bulk_item_import","state":"not_built"},
  {"code":"item_variants","state":"not_built"},
  {"code":"dealer_pos_screens","state":"not_built"},
  {"code":"party_scope_per_business","state":"not_built"},
  {"code":"scheme_books_posting","state":"not_built"}
]'::jsonb where code = 'hardware_paint' and modules = '[]'::jsonb;
update public.business_templates set modules = '[
  {"code":"cheque_pdc","state":"built","phase":127,"rule":"dealer_cheque_on"},
  {"code":"principal_schemes","state":"built","phase":128,"rule":"dealer_scheme_on"},
  {"code":"vehicle_stock_and_sales","state":"not_built"},
  {"code":"dealer_pos_screens","state":"not_built"},
  {"code":"party_scope_per_business","state":"not_built"}
]'::jsonb where code = 'dealership' and modules = '[]'::jsonb;

-- ---------- function grants ----------
revoke all on function public._tint_gate129(bigint, int, text, boolean), public._tint_uuid129(uuid, int), public._tint_formula_guard129(), public._tint_job_guard129() from public, anon, authenticated;
revoke all on function public.tint_formula_save(uuid, bigint, text, text, uuid, text, numeric, jsonb, text), public.tint_formula_retire(uuid),
  public.tint_job_run(uuid, int, uuid, numeric, uuid, text, date, numeric, text, boolean), public.tint_job_void(uuid, uuid, text),
  public.tint_formula_list(bigint, text, text), public.tint_formula_get(uuid), public.tint_job_list(bigint, date, date, uuid, int), public.tint_customer_shades(uuid, bigint),
  public.tint_job_cost(uuid), public.tint_cost_report(bigint, date, date) from public, anon;
grant execute on function public.tint_formula_save(uuid, bigint, text, text, uuid, text, numeric, jsonb, text), public.tint_formula_retire(uuid),
  public.tint_job_run(uuid, int, uuid, numeric, uuid, text, date, numeric, text, boolean), public.tint_job_void(uuid, uuid, text),
  public.tint_formula_list(bigint, text, text), public.tint_formula_get(uuid), public.tint_job_list(bigint, date, date, uuid, int), public.tint_customer_shades(uuid, bigint),
  public.tint_job_cost(uuid), public.tint_cost_report(bigint, date, date) to authenticated;

commit;
