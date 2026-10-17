-- Phase 404 (bos404) - RPT-B4 / R3a: PRODUCTION CAPTURE, TABLES AND HELPERS.
-- Paste after phase 99 (and after phases 400-403 / 430-436 if they are used; this file does not need them). Paste-twice safe. Earlier phase files are not edited; no shared function is re-created.
-- Requirements: docs/REPORTS_AUDIT_1.md items #40, #44, #45, #49, #52, #53, #55 (data capture gaps: plan, order, actual issue, reject/rework).
--
-- WHAT THIS ADDS (tables only; the entry functions are in phase 405, the reports in 406-408)
--   production_plans        a plan line: day, place, item, planned batches and/or planned quantity (base unit). Cancelled, never deleted.
--   production_orders       an order for a product: ordered day, due day, producing place, optional requesting outlet, quantity (base unit), status open / closed / cancelled.
--   production_run_links    which plan / order a finished production run belongs to (written by a person; unlinked runs are matched to a plan by place + item + day in the report).
--   production_issue_actual what was REALLY taken for a run, per ingredient (the production screen books exactly the recipe need; a person records the real use). Replaced lines stay as history.
--   production_loss         reject / rework quantity per run with a reason from the existing list wastage_reasons; kind 'none' = "checked, no reject or rework".
-- Nothing here moves stock or money. A blank is "data not captured", never 0. Entry rights reuse the grant stock_production (owner always); reading uses the existing report / recipe rights.
-- Paper form code of the entry screens: to be given by owner.

do $g$ begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'production_runs' and column_name = 'yield_actual') then raise exception 'phase404 needs phase74 (production_runs.yield_actual)'; end if;
  if to_regclass('public.stock_transfers') is null or to_regclass('public.stock_wastage') is null then raise exception 'phase404 needs the stock phases (stock_transfers, stock_wastage)'; end if;
  if to_regprocedure('public._recipe_read()') is null then raise exception 'phase404 needs phase19 (_recipe_read)'; end if;
end $g$;

-- ---------- who may read / write ----------
-- reading production data: the owner, the stock report right, or anyone who may read recipes / production, or move stock between places; and the place must be theirs
create or replace function public._rb4_prod_view(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and public.can_loc(p_loc) and (public.is_owner() or public.rpt_access('stock') or public._recipe_read() or public.has_grant('stock_transfer', p_loc));
$$;
-- writing production capture: the owner or the grant stock_production at that place
create or replace function public._rb4_prod_entry(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and public.can_loc(p_loc) and (public.is_owner() or public.has_grant('stock_production', p_loc));
$$;
-- the Dhaka calendar day of a timestamp
create or replace function public._rb4_day(p_ts timestamptz) returns date language sql immutable as $$ select (p_ts at time zone 'Asia/Dhaka')::date $$;
create or replace function public._rb4_today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
-- range check shared by every report: both days present, to >= from, at most 800 days
create or replace function public._rb4_range(p_from date, p_to date, out f date, out t date) language plpgsql stable as $$
begin
  f := coalesce(p_from, public._rb4_today() - 30); t := coalesce(p_to, public._rb4_today());
  if t < f or t - f > 800 then raise exception 'bad_range'; end if;
end $$;

-- ---------- tables ----------
create table if not exists public.production_plans (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  plan_date date not null,
  location_id int not null references public.locations(id),
  item_id uuid not null references public.items(id),
  recipe_id uuid references public.recipes(id),
  planned_batches numeric check (planned_batches is null or (planned_batches > 0 and planned_batches <= 100000)),
  planned_qty numeric check (planned_qty is null or (planned_qty > 0 and planned_qty <= 999999999)),      -- item base unit
  note text check (note is null or length(note) <= 300),
  status text not null default 'planned' check (status in ('planned', 'cancelled')),
  cancel_note text, cancelled_by uuid, cancelled_at timestamptz,
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  check (planned_batches is not null or planned_qty is not null)
);
create index if not exists production_plans_day on public.production_plans (plan_date, location_id);
create index if not exists production_plans_item on public.production_plans (item_id, plan_date);

create table if not exists public.production_orders (
  id bigint generated always as identity primary key,       -- shown as the order number; it is NOT a paper form code
  client_id uuid unique,
  order_date date not null,
  due_date date,
  location_id int not null references public.locations(id),          -- the producing place
  for_location_id int references public.locations(id),               -- the outlet that asked (blank = for stock)
  item_id uuid not null references public.items(id),
  qty numeric not null check (qty > 0 and qty <= 999999999),         -- item base unit
  note text check (note is null or length(note) <= 300),
  status text not null default 'open' check (status in ('open', 'closed', 'cancelled')),
  close_note text, closed_by uuid, closed_at timestamptz,
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  check (due_date is null or due_date >= order_date)
);
create index if not exists production_orders_open on public.production_orders (status, due_date);
create index if not exists production_orders_loc on public.production_orders (location_id, order_date);

create table if not exists public.production_run_links (
  run_id uuid primary key references public.production_runs(id),
  plan_id uuid references public.production_plans(id),
  order_id bigint references public.production_orders(id),
  linked_by uuid, linked_at timestamptz not null default now()
);
create index if not exists production_run_links_plan on public.production_run_links (plan_id) where plan_id is not null;
create index if not exists production_run_links_order on public.production_run_links (order_id) where order_id is not null;

create table if not exists public.production_issue_actual (
  id bigserial primary key,
  run_id uuid not null references public.production_runs(id),
  item_id uuid not null references public.items(id),
  actual_qty numeric not null check (actual_qty >= 0 and actual_qty <= 999999999),     -- item base unit; 0 = checked, none used
  note text check (note is null or length(note) <= 300),
  status text not null default 'active' check (status in ('active', 'replaced')),
  entered_by uuid, entered_staff text, entered_at timestamptz not null default now(),
  replaced_by uuid, replaced_at timestamptz
);
create unique index if not exists production_issue_actual_one on public.production_issue_actual (run_id, item_id) where status = 'active';
create index if not exists production_issue_actual_run on public.production_issue_actual (run_id);

create table if not exists public.production_loss (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  run_id uuid not null references public.production_runs(id),
  kind text not null check (kind in ('reject', 'rework', 'none')),
  qty numeric not null check (qty >= 0 and qty <= 999999999),          -- finished-item base unit; 0 only for kind 'none'
  reason_code text,                                                      -- option_lists.value_code of list wastage_reasons (the id, never the label)
  note text check (note is null or length(note) <= 300),
  status text not null default 'active' check (status in ('active', 'void')),
  void_note text, void_by uuid, void_at timestamptz,
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  check ((kind = 'none' and qty = 0) or (kind <> 'none' and qty > 0))
);
create index if not exists production_loss_run on public.production_loss (run_id);

-- ---------- audit lines (who, when, what changed) and read rules ----------
do $t$
declare t text;
begin
  foreach t in array array['production_plans', 'production_orders', 'production_run_links', 'production_issue_actual', 'production_loss'] loop
    execute format('drop trigger if exists audit_%1$s on public.%1$s', t);
    execute format('create trigger audit_%1$s after insert or update on public.%1$s for each row execute function public.log_change(%2$L)', t, case t when 'production_run_links' then 'run_id' else 'id' end);
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $t$;
drop policy if exists production_plans_read on public.production_plans;
create policy production_plans_read on public.production_plans for select to authenticated using (public._rb4_prod_view(location_id));
drop policy if exists production_orders_read on public.production_orders;
create policy production_orders_read on public.production_orders for select to authenticated using (public._rb4_prod_view(location_id));
drop policy if exists production_run_links_read on public.production_run_links;
create policy production_run_links_read on public.production_run_links for select to authenticated using (exists (select 1 from public.production_runs r where r.id = run_id and public._rb4_prod_view(r.location_id)));
drop policy if exists production_issue_actual_read on public.production_issue_actual;
create policy production_issue_actual_read on public.production_issue_actual for select to authenticated using (exists (select 1 from public.production_runs r where r.id = run_id and public._rb4_prod_view(r.location_id)));
drop policy if exists production_loss_read on public.production_loss;
create policy production_loss_read on public.production_loss for select to authenticated using (exists (select 1 from public.production_runs r where r.id = run_id and public._rb4_prod_view(r.location_id)));

-- ---------- helpers are closed to browsers ----------
do $c$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_rb4_prod_view', '_rb4_prod_entry', '_rb4_day', '_rb4_today', '_rb4_range') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);      -- row-level-security policies and the report functions run as the caller, so the checks must be callable
  end loop;
end $c$;

notify pgrst, 'reload schema';
