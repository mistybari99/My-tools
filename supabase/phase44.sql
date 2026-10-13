-- ============================================================
-- PHASE 44 (Module D): PARTNERSHIP / INVESTMENT / PROFIT-SHARING / FRANCHISE - a flexible DEED (agreement) engine.
-- Additive + idempotent (paste twice = no error). Needs phase27 (_p27_pl, the P&L extraction) and phase28 order. OWNER ONLY (sensitive).
--   * partner_parties       who (individual / company)
--   * partner_ventures      what the deal is about (a place, the business, a product line, anything), model own|franchise|funded|partnership|loan|custom
--   * partner_agreements    the DEED: editable clauses while draft; IMMUTABLE once active. An amendment is a new revision (supersedes_id); the old one stays readable.
--     agreement_parties     roles + stated share % per agreement
--   * partner_capital       append-only capital ledger (contribution / return_of_capital / loan_in / loan_repayment / owner_drawing), void flag only
--   * partner_rules         ordered steps of the profit-sharing ENGINE (step kinds below); partner_rule_validate(kind, config) checks every config
--   * partner_calculate     the trial calculation: returns the whole waterfall step by step and WRITES NOTHING
--   * partner_settlements (+lines, +payments)  preview -> save a draft snapshot -> approve -> payments -> party statement. Overlapping periods refused.
--   * partner_party_statement / partner_overview / partner_capital_balances  read models
-- Step kinds (config jsonb):  base | royalty | management_fee | expense_allow | expense_disallow | loss_carry_forward | priority_return | payback |
--   split | tiered_split | minimum_guarantee | cap | floor | rounding.   A party in a config is {"party_id": n} OR {"role": "investor"} (role = the one active party holding it).
--   Bases come from the books (sales net of returns, costed COGS, 10-2 expenses, 02-2 salary - the very _p27_pl extraction); a base that cannot be computed honestly
--   (items without a cost, product-line scope) is NULL + a warning and the owner types a manual base. Nothing is invented. The journal base of module A is not read here.
-- Settings: rule partners_module_on (default ON). Everything is audited (audit_log). Nothing is hard-deleted.
-- ============================================================

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('partners_module_on', 'partners', 'switch', 'true', null, null, null, null, 'অংশীদারি / বিনিয়োগ / লাভ-ভাগ (চুক্তি) মডিউল', 'অংশীদারি / বিনিয়োগ / profit-ভাগ (deed) module', 'Partnership / investment / profit-sharing (deed) module',
  'শুধু মালিক দেখেন। বন্ধ করলে এই পর্দা ও হিসাব বন্ধ থাকে; আগের চুক্তি ও হিসাব মোছে না।', 'Owner only. Off = the screens and calculations stop; saved deeds and settlements are kept.', 94)
 on conflict (key) do nothing;

-- ============================================================
-- 1. tables
-- ============================================================
create table if not exists public.partner_parties (
  id bigserial primary key,
  name text not null check (length(btrim(name)) between 1 and 200),
  kind text not null default 'individual' check (kind in ('individual', 'company')),
  mobile text check (mobile is null or length(mobile) <= 40), email text check (email is null or length(email) <= 200),
  nid_or_reg text check (nid_or_reg is null or length(nid_or_reg) <= 100), address text check (address is null or length(address) <= 500),
  photo_path text check (photo_path is null or length(photo_path) <= 300), notes text check (notes is null or length(notes) <= 2000),
  active boolean not null default true,
  client_id uuid unique, created_by uuid, created_at timestamptz not null default now()
);
create table if not exists public.partner_ventures (
  id bigserial primary key,
  name_bn text not null check (length(btrim(name_bn)) between 1 and 200), name_en text check (name_en is null or length(name_en) <= 200),
  scope text not null default 'business' check (scope in ('location', 'business', 'product_line', 'custom')),
  location_id int references public.locations(id),
  model text not null default 'partnership' check (model in ('own', 'franchise', 'funded', 'partnership', 'loan', 'custom')),
  start_date date, end_date date,
  status text not null default 'draft' check (status in ('draft', 'active', 'closed')),
  notes text check (notes is null or length(notes) <= 2000),
  client_id uuid unique, created_by uuid, created_at timestamptz not null default now(),
  check (end_date is null or start_date is null or end_date >= start_date),
  check (scope <> 'location' or location_id is not null)
);
create table if not exists public.partner_agreements (
  id bigserial primary key,
  venture_id bigint not null references public.partner_ventures(id),
  title text not null check (length(btrim(title)) between 1 and 300),
  version int not null default 1,
  status text not null default 'draft' check (status in ('draft', 'active', 'amended', 'closed')),
  effective_from date, effective_to date,
  clauses jsonb not null default '[]'::jsonb check (jsonb_typeof(clauses) = 'array'),
  signed_doc_path text check (signed_doc_path is null or length(signed_doc_path) <= 300),
  supersedes_id bigint references public.partner_agreements(id),
  is_example boolean not null default false,
  activated_by uuid, activated_at timestamptz, closed_by uuid, closed_at timestamptz, closed_note text,
  client_id uuid unique, created_by uuid, created_at timestamptz not null default now(),
  check (effective_to is null or effective_from is null or effective_to >= effective_from)
);
create unique index if not exists partner_agreements_one_child on public.partner_agreements (supersedes_id) where supersedes_id is not null;
create index if not exists partner_agreements_venture on public.partner_agreements (venture_id);
create table if not exists public.agreement_parties (
  id bigserial primary key,
  agreement_id bigint not null references public.partner_agreements(id),
  party_id bigint not null references public.partner_parties(id),
  role text not null check (role in ('owner', 'partner', 'investor', 'franchisee', 'manager', 'lender')),
  share_percent numeric check (share_percent is null or (share_percent >= 0 and share_percent <= 100)),
  notes text check (notes is null or length(notes) <= 1000),
  active boolean not null default true,
  unique (agreement_id, party_id, role)
);
create table if not exists public.partner_rules (
  id bigserial primary key,
  agreement_id bigint not null references public.partner_agreements(id),
  step_no int not null, step_key uuid not null default gen_random_uuid(),
  name text not null check (length(btrim(name)) between 1 and 200),
  kind text not null check (kind in ('base', 'royalty', 'management_fee', 'expense_allow', 'expense_disallow', 'loss_carry_forward', 'priority_return', 'payback',
                                      'split', 'tiered_split', 'minimum_guarantee', 'cap', 'floor', 'rounding')),
  config jsonb not null default '{}'::jsonb check (jsonb_typeof(config) = 'object'),
  active boolean not null default true,
  unique (agreement_id, step_no)
);
create table if not exists public.partner_capital (
  id bigserial primary key,
  agreement_id bigint not null references public.partner_agreements(id),
  party_id bigint not null references public.partner_parties(id),
  kind text not null check (kind in ('contribution', 'return_of_capital', 'loan_in', 'loan_repayment', 'owner_drawing')),
  amount numeric not null check (amount > 0 and amount <= 1000000000000),
  cap_date date not null,
  mode text not null check (mode in ('cash', 'bank', 'mobile', 'in_kind')),
  description text check (description is null or length(description) <= 500), ref text check (ref is null or length(ref) <= 200),
  status text not null default 'posted' check (status in ('posted', 'void')),
  void_reason text, void_by uuid, void_at timestamptz,
  client_id uuid unique, created_by uuid, created_at timestamptz not null default now()
);
create index if not exists partner_capital_party on public.partner_capital (party_id, cap_date);
create table if not exists public.partner_settlements (
  id bigserial primary key,
  agreement_id bigint not null references public.partner_agreements(id),
  period_from date not null, period_to date not null,
  status text not null default 'draft' check (status in ('draft', 'approved', 'paid', 'void')),
  calc jsonb not null, manual_base jsonb,
  total_distributable numeric not null,
  carry_out numeric not null default 0,
  approved_by uuid, approved_at timestamptz, void_reason text, void_by uuid, void_at timestamptz,
  note text check (note is null or length(note) <= 1000),
  client_id uuid unique, created_by uuid, created_at timestamptz not null default now(),
  check (period_to >= period_from)
);
create index if not exists partner_settlements_agr on public.partner_settlements (agreement_id, period_from);
create table if not exists public.partner_settlement_lines (
  id bigserial primary key,
  settlement_id bigint not null references public.partner_settlements(id),
  party_id bigint not null references public.partner_parties(id),
  amount numeric not null check (amount > 0),
  kind text not null check (kind in ('share', 'royalty', 'fee', 'return', 'payback', 'guarantee')),
  funded_outside boolean not null default false,
  paid_amount numeric not null default 0 check (paid_amount >= 0), paid_at date, pay_mode text check (pay_mode is null or pay_mode in ('cash', 'bank', 'mobile')),
  unique (settlement_id, party_id, kind, funded_outside)
);
create table if not exists public.partner_settlement_payments (
  id bigserial primary key,
  line_id bigint not null references public.partner_settlement_lines(id),
  amount numeric not null check (amount > 0 and amount <= 1000000000000),
  paid_on date not null, mode text not null check (mode in ('cash', 'bank', 'mobile')),
  ref text check (ref is null or length(ref) <= 200),
  client_id uuid unique, created_by uuid, created_at timestamptz not null default now()
);
create table if not exists public.partner_templates (
  code text primary key,
  name_bn text not null, name_en text not null, description_bn text, description_en text,
  model text not null, clauses jsonb not null default '[]'::jsonb, rules jsonb not null default '[]'::jsonb, roles jsonb not null default '[]'::jsonb,
  is_example boolean not null default true, active boolean not null default false
);

-- ============================================================
-- 2. helpers (private)
-- ============================================================
create or replace function public._a44_guard() returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() or not public.is_owner() then raise exception 'not allowed'; end if;
  if not coalesce(public.rule_on('partners_module_on'), true) then raise exception 'module_off'; end if;
end $$;
create or replace function public._a44_n(j jsonb) returns numeric language sql immutable as $$
  select case when j is null then null when jsonb_typeof(j) = 'number' then (j #>> '{}')::numeric
              when jsonb_typeof(j) = 'string' and (j #>> '{}') ~ '^-?[0-9]+(\.[0-9]+)?$' then (j #>> '{}')::numeric end $$;
create or replace function public._a44_today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function public._a44_chk_date(d date) returns void language plpgsql stable as $$
begin if d is null or d < date '2000-01-01' or d > public._a44_today() then raise exception 'bad_date'; end if; end $$;
create or replace function public._a44_chk_money(x numeric) returns void language plpgsql immutable as $$
begin if x is null or x <> x or x <= 0 or x > 1000000000000 then raise exception 'bad_amount'; end if; end $$;
-- all revisions of one deed (walk up to the first, then down)
create or replace function public._a44_chain(p_agr bigint) returns table (id bigint) language sql stable security definer set search_path = public as $$
  with recursive up as (select a.id, a.supersedes_id from public.partner_agreements a where a.id = p_agr
                        union all select a.id, a.supersedes_id from public.partner_agreements a join up on a.id = up.supersedes_id),
  dn as (select a.id from public.partner_agreements a where a.id = (select u.id from up u where u.supersedes_id is null limit 1)
         union all select a.id from public.partner_agreements a join dn on a.supersedes_id = dn.id)
  select dn.id from dn $$;
-- fraction of calendar months covered (a whole month = 1)
create or replace function public._a44_months(d1 date, d2 date) returns numeric language sql immutable as $$
  select coalesce(sum(((least(d2, ((g.ms + interval '1 month')::date) - 1) - greatest(d1, g.ms) + 1)::numeric) / (((g.ms + interval '1 month')::date) - g.ms)), 0)
  from (select ms::date as ms from generate_series(date_trunc('month', d1::timestamp), date_trunc('month', d2::timestamp), interval '1 month') ms) g $$;
create or replace function public._a44_round(x numeric, p_to numeric, p_mode text) returns numeric language sql immutable as $$
  select case when x is null then null else round(case p_mode when 'down' then floor(x / p_to) * p_to when 'up' then ceil(x / p_to) * p_to else round(x / p_to) * p_to end, 2) end $$;
-- a party reference {party_id|role} -> party id (must be active in that agreement; a role must be held by exactly one)
create or replace function public._a44_ref(p_agr bigint, p_ref jsonb) returns bigint language plpgsql stable security definer set search_path = public as $$
declare pid bigint; c int;
begin
  if p_ref is null or jsonb_typeof(p_ref) <> 'object' then return null; end if;
  if public._a44_n(p_ref -> 'party_id') is not null then
    pid := public._a44_n(p_ref -> 'party_id')::bigint;
    return (select ap.party_id from public.agreement_parties ap where ap.agreement_id = p_agr and ap.party_id = pid and ap.active limit 1);
  end if;
  if p_ref ->> 'role' is not null then
    select count(distinct ap.party_id), min(ap.party_id) into c, pid from public.agreement_parties ap where ap.agreement_id = p_agr and ap.active and ap.role = p_ref ->> 'role';
    if c = 1 then return pid; end if;
  end if;
  return null;
end $$;
create or replace function public._a44_need(p_agr bigint, p_ref jsonb, p_what text) returns bigint language plpgsql stable security definer set search_path = public as $$
declare pid bigint;
begin pid := public._a44_ref(p_agr, p_ref); if pid is null then raise exception 'party_unresolved: %', p_what; end if; return pid; end $$;
-- spread an amount over shares [{party_id|role, percent}]; the rounding remainder goes to the largest share
create or replace function public._a44_distribute(p_agr bigint, p_amount numeric, p_shares jsonb, p_to numeric, p_mode text, p_what text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e record; out jsonb := '[]'::jsonb; sum_a numeric := 0; big_ord int := 1; big_p numeric := -1; a numeric; pid bigint; i int := 0;
begin
  for e in select value as v, ord from jsonb_array_elements(p_shares) with ordinality as t(value, ord) order by ord loop
    pid := public._a44_need(p_agr, e.v, p_what);
    a := public._a44_round(p_amount * public._a44_n(e.v -> 'percent') / 100, p_to, p_mode);
    out := out || jsonb_build_array(jsonb_build_object('party_id', pid, 'amount', a, 'percent', public._a44_n(e.v -> 'percent')));
    sum_a := sum_a + a;
    if public._a44_n(e.v -> 'percent') > big_p then big_p := public._a44_n(e.v -> 'percent'); big_ord := e.ord; end if;
  end loop;
  if jsonb_array_length(out) > 0 then
    out := jsonb_set(out, array[(big_ord - 1)::text, 'amount'], to_jsonb(round((out -> (big_ord - 1) ->> 'amount')::numeric + (round(p_amount, 2) - sum_a), 2)));
  end if;
  return out;
end $$;
create or replace function public._a44_party_total(p_lines jsonb, p_party bigint, p_outside boolean default false) returns numeric language sql immutable as $$
  select coalesce(sum((e ->> 'amount')::numeric), 0) from jsonb_array_elements(p_lines) e
   where (e ->> 'party_id')::bigint = p_party and (p_outside or not coalesce((e ->> 'outside')::boolean, false)) $$;
-- capital balance of one party (all revisions of the deed) on a date: contributions + loans in - capital returned - loans repaid
create or replace function public._a44_cap(p_agr bigint, p_party bigint, p_asof date) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(case c.kind when 'contribution' then c.amount when 'loan_in' then c.amount when 'return_of_capital' then -c.amount when 'loan_repayment' then -c.amount else 0 end), 0)
  from public.partner_capital c where c.agreement_id in (select id from public._a44_chain(p_agr)) and c.party_id = p_party and c.status = 'posted' and c.cap_date <= p_asof $$;
-- sum over every day of the period of the capital balance of that day (time-weighted capital)
create or replace function public._a44_capdays(p_agr bigint, p_party bigint, p_from date, p_to date) returns numeric language sql stable security definer set search_path = public as $$
  with m as (select c.cap_date, case c.kind when 'contribution' then c.amount when 'loan_in' then c.amount when 'return_of_capital' then -c.amount when 'loan_repayment' then -c.amount else 0 end as s
             from public.partner_capital c where c.agreement_id in (select id from public._a44_chain(p_agr)) and c.party_id = p_party and c.status = 'posted' and c.cap_date <= p_to)
  select coalesce(sum((select coalesce(sum(m.s), 0) from m where m.cap_date <= d::date)), 0) from generate_series(p_from::timestamp, p_to::timestamp, interval '1 day') d $$;
-- what earlier (non-void) settlements of the same deed already gave through one rule step
create or replace function public._a44_step_hist(p_agr bigint, p_from date, p_key text, out paid_before numeric, out shortfall_in numeric) language plpgsql stable security definer set search_path = public as $$
begin
  select coalesce(sum((e ->> 'core')::numeric), 0) into paid_before
    from public.partner_settlements s, jsonb_array_elements(s.calc -> 'steps') e
   where s.agreement_id in (select id from public._a44_chain(p_agr)) and s.status <> 'void' and s.period_to < p_from and e ->> 'key' = p_key;
  select coalesce((e ->> 'shortfall_out')::numeric, 0) into shortfall_in
    from public.partner_settlements s, jsonb_array_elements(s.calc -> 'steps') e
   where s.agreement_id in (select id from public._a44_chain(p_agr)) and s.status <> 'void' and s.period_to < p_from and e ->> 'key' = p_key
   order by s.period_to desc limit 1;
  shortfall_in := coalesce(shortfall_in, 0);
end $$;

-- ============================================================
-- 3. rule config validation
-- ============================================================
create or replace function public._a44_vref(c jsonb) returns void language plpgsql immutable as $$
begin
  if c is null or jsonb_typeof(c) <> 'object' or (public._a44_n(c -> 'party_id') is null and nullif(btrim(coalesce(c ->> 'role', '')), '') is null) then raise exception 'bad_config: party'; end if;
  if c ->> 'role' is not null and c ->> 'role' not in ('owner', 'partner', 'investor', 'franchisee', 'manager', 'lender') then raise exception 'bad_config: role'; end if;
end $$;
create or replace function public._a44_vshares(sh jsonb) returns void language plpgsql immutable as $$
declare e jsonb; s numeric := 0; p numeric;
begin
  if sh is null or jsonb_typeof(sh) <> 'array' or jsonb_array_length(sh) < 1 or jsonb_array_length(sh) > 20 then raise exception 'bad_config: shares'; end if;
  for e in select value from jsonb_array_elements(sh) loop
    perform public._a44_vref(e); p := public._a44_n(e -> 'percent');
    if p is null or p <= 0 or p > 100 then raise exception 'bad_config: percent'; end if;
    s := s + p;
  end loop;
  if abs(s - 100) > 0.0001 then raise exception 'split_not_100'; end if;
end $$;
create or replace function public.partner_rule_validate(p_kind text, p_config jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c jsonb := coalesce(p_config, '{}'::jsonb); x numeric; e jsonb; prev numeric := 0; u numeric; n int := 0; allowed_b text[] := array['gross_sales', 'net_sales', 'gross_profit', 'net_profit_before_fees'];
begin
  perform public._a44_guard();
  if jsonb_typeof(c) <> 'object' then raise exception 'bad_config: object'; end if;
  case p_kind
    when 'base' then
      if c ->> 'base' is null or c ->> 'base' not in ('gross_sales', 'net_sales', 'gross_profit', 'net_profit_before_fees', 'net_profit', 'fixed_amount', 'manual') then raise exception 'bad_config: base'; end if;
      if c ->> 'base' = 'fixed_amount' then x := public._a44_n(c -> 'amount'); if x is null or abs(x) > 1000000000000 then raise exception 'bad_config: amount'; end if; end if;
    when 'royalty' then
      perform public._a44_vref(c); x := public._a44_n(c -> 'percent');
      if x is null or x < 0 or x > 100 then raise exception 'bad_config: percent'; end if;
      if c ->> 'base' is not null and not (c ->> 'base' = any (allowed_b)) then raise exception 'bad_config: base'; end if;
    when 'management_fee' then
      perform public._a44_vref(c);
      if (public._a44_n(c -> 'percent') is null) = (public._a44_n(c -> 'fixed') is null) then raise exception 'bad_config: percent_or_fixed'; end if;
      x := coalesce(public._a44_n(c -> 'percent'), public._a44_n(c -> 'fixed'));
      if x < 0 or x > 1000000000000 or (public._a44_n(c -> 'percent') is not null and x > 100) then raise exception 'bad_config: amount'; end if;
      if c ->> 'per' is not null and c ->> 'per' not in ('period', 'month') then raise exception 'bad_config: per'; end if;
      if c ->> 'base' is not null and not (c ->> 'base' = any (allowed_b)) then raise exception 'bad_config: base'; end if;
    when 'expense_allow', 'expense_disallow' then
      if c -> 'items' is null or jsonb_typeof(c -> 'items') <> 'array' or jsonb_array_length(c -> 'items') > 50 then raise exception 'bad_config: items'; end if;
      for e in select value from jsonb_array_elements(c -> 'items') loop
        x := public._a44_n(e -> 'amount');
        if x is null or x < 0 or x > 1000000000000 or nullif(btrim(coalesce(e ->> 'name', '')), '') is null then raise exception 'bad_config: items'; end if;
      end loop;
    when 'loss_carry_forward' then null;
    when 'priority_return' then
      perform public._a44_vref(c);
      if (public._a44_n(c -> 'percent_per_year') is null) = (public._a44_n(c -> 'fixed_monthly') is null) then raise exception 'bad_config: percent_or_fixed'; end if;
      x := coalesce(public._a44_n(c -> 'percent_per_year'), public._a44_n(c -> 'fixed_monthly'));
      if x < 0 or x > 1000000000000 or (public._a44_n(c -> 'percent_per_year') is not null and x > 1000) then raise exception 'bad_config: amount'; end if;
      if c -> 'cap' is not null and jsonb_typeof(c -> 'cap') <> 'null' and (public._a44_n(c -> 'cap') is null or public._a44_n(c -> 'cap') < 0 or public._a44_n(c -> 'cap') > 1000000000000) then raise exception 'bad_config: cap'; end if;
      if c -> 'catch_up' is not null and jsonb_typeof(c -> 'catch_up') <> 'boolean' then raise exception 'bad_config: catch_up'; end if;
    when 'payback' then
      perform public._a44_vref(c); x := coalesce(public._a44_n(c -> 'percent'), 100);
      if x <= 0 or x > 100 then raise exception 'bad_config: percent'; end if;
      if c -> 'target' is not null and jsonb_typeof(c -> 'target') <> 'null' and (public._a44_n(c -> 'target') is null or public._a44_n(c -> 'target') <= 0 or public._a44_n(c -> 'target') > 1000000000000) then raise exception 'bad_config: target'; end if;
      if c -> 'then_percent' is not null and jsonb_typeof(c -> 'then_percent') <> 'null' and (public._a44_n(c -> 'then_percent') is null or public._a44_n(c -> 'then_percent') < 0 or public._a44_n(c -> 'then_percent') > 100) then raise exception 'bad_config: then_percent'; end if;
    when 'split' then perform public._a44_vshares(c -> 'shares');
    when 'tiered_split' then
      if c -> 'slabs' is null or jsonb_typeof(c -> 'slabs') <> 'array' or jsonb_array_length(c -> 'slabs') < 1 or jsonb_array_length(c -> 'slabs') > 10 then raise exception 'bad_config: slabs'; end if;
      for e in select value from jsonb_array_elements(c -> 'slabs') loop
        n := n + 1; perform public._a44_vshares(e -> 'shares');
        if e -> 'upto' is null or jsonb_typeof(e -> 'upto') = 'null' then
          if n <> jsonb_array_length(c -> 'slabs') then raise exception 'slab_order'; end if;
        else
          u := public._a44_n(e -> 'upto');
          if u is null or u <= prev or u > 1000000000000 then raise exception 'slab_order'; end if;
          prev := u;
        end if;
      end loop;
    when 'minimum_guarantee' then
      perform public._a44_vref(c); x := public._a44_n(c -> 'amount');
      if x is null or x < 0 or x > 1000000000000 then raise exception 'bad_config: amount'; end if;
      if c ->> 'per' is not null and c ->> 'per' not in ('period', 'month') then raise exception 'bad_config: per'; end if;
      if c ->> 'funded_by' is not null and c ->> 'funded_by' not in ('pool', 'outside') then raise exception 'bad_config: funded_by'; end if;
    when 'cap', 'floor' then
      x := public._a44_n(c -> 'amount');
      if x is null or x < 0 or x > 1000000000000 then raise exception 'bad_config: amount'; end if;
      if coalesce(c ->> 'target', 'pool') not in ('pool', 'party') then raise exception 'bad_config: target'; end if;
      if c ->> 'target' = 'party' then perform public._a44_vref(c); end if;
      if c ->> 'per' is not null and c ->> 'per' not in ('period', 'month') then raise exception 'bad_config: per'; end if;
    when 'rounding' then
      x := public._a44_n(c -> 'to');
      if x is null or x not in (0.01, 0.1, 1, 5, 10, 50, 100, 1000) then raise exception 'bad_config: to'; end if;
      if coalesce(c ->> 'mode', 'nearest') not in ('nearest', 'down', 'up') then raise exception 'bad_config: mode'; end if;
    else raise exception 'bad_kind';
  end case;
  return c;
end $$;

-- ============================================================
-- 4. guards (immutability, append-only)
-- ============================================================
create or replace function public._a44_agr_guard() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'append_only: a deed is never deleted'; end if;
  if tg_op = 'UPDATE' and old.status <> 'draft' then
    if new.venture_id is distinct from old.venture_id or new.title is distinct from old.title or new.version is distinct from old.version
       or new.effective_from is distinct from old.effective_from or new.clauses is distinct from old.clauses
       or new.supersedes_id is distinct from old.supersedes_id or new.is_example is distinct from old.is_example or new.created_by is distinct from old.created_by then
      raise exception 'agreement_immutable: an active deed cannot be edited - make an amendment';
    end if;
    if new.status is distinct from old.status and not (old.status = 'active' and new.status in ('amended', 'closed')) then raise exception 'agreement_immutable: bad status change'; end if;
    if new.status is not distinct from old.status and new.effective_to is distinct from old.effective_to then raise exception 'agreement_immutable: dates are fixed'; end if;
  end if;
  if tg_op = 'UPDATE' and old.status = 'draft' and new.status not in ('draft', 'active') then raise exception 'agreement_immutable: bad status change'; end if;
  return new;
end $$;
drop trigger if exists partner_agreements_guard on public.partner_agreements;
create trigger partner_agreements_guard before update or delete on public.partner_agreements for each row execute function public._a44_agr_guard();

create or replace function public._a44_child_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare st text; aid bigint;
begin
  if tg_op = 'DELETE' then raise exception 'append_only: retire it with the active flag, never delete'; end if;
  aid := new.agreement_id;
  select status into st from public.partner_agreements where id = aid;
  if st is distinct from 'draft' then raise exception 'agreement_immutable: the deed is not a draft - make an amendment'; end if;
  return new;
end $$;
drop trigger if exists partner_rules_guard on public.partner_rules;
create trigger partner_rules_guard before insert or update or delete on public.partner_rules for each row execute function public._a44_child_guard();
drop trigger if exists agreement_parties_guard on public.agreement_parties;
create trigger agreement_parties_guard before insert or update or delete on public.agreement_parties for each row execute function public._a44_child_guard();

create or replace function public._a44_ro() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end $$;
drop trigger if exists partner_settlement_payments_ro on public.partner_settlement_payments;
create trigger partner_settlement_payments_ro before update or delete on public.partner_settlement_payments for each row execute function public._a44_ro();
drop trigger if exists partner_settlement_payments_ro_t on public.partner_settlement_payments;
create trigger partner_settlement_payments_ro_t before truncate on public.partner_settlement_payments for each statement execute function public._a44_ro();

create or replace function public._a44_cap_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'append_only: capital rows are never deleted - void them'; end if;
  if (to_jsonb(new) - 'status' - 'void_reason' - 'void_by' - 'void_at') is distinct from (to_jsonb(old) - 'status' - 'void_reason' - 'void_by' - 'void_at') then
    raise exception 'append_only: capital rows cannot be changed'; end if;
  if new.status is distinct from old.status and not (old.status = 'posted' and new.status = 'void') then raise exception 'append_only: a void row stays void'; end if;
  return new;
end $$;
drop trigger if exists partner_capital_guard on public.partner_capital;
create trigger partner_capital_guard before update or delete on public.partner_capital for each row execute function public._a44_cap_guard();
drop trigger if exists partner_capital_guard_t on public.partner_capital;
create trigger partner_capital_guard_t before truncate on public.partner_capital for each statement execute function public._a44_ro();

create or replace function public._a44_set_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'append_only: settlements are never deleted - void them'; end if;
  if new.agreement_id is distinct from old.agreement_id or new.period_from is distinct from old.period_from or new.period_to is distinct from old.period_to
     or new.calc is distinct from old.calc or new.manual_base is distinct from old.manual_base or new.total_distributable is distinct from old.total_distributable
     or new.carry_out is distinct from old.carry_out or new.created_by is distinct from old.created_by then
    raise exception 'settlement_immutable: the saved calculation cannot be changed - void it and make a new one';
  end if;
  if old.status in ('void') then raise exception 'settlement_immutable: a void settlement stays void'; end if;
  if new.status is distinct from old.status and not ((old.status = 'draft' and new.status in ('approved', 'void')) or (old.status = 'approved' and new.status in ('paid', 'void'))) then
    raise exception 'settlement_immutable: bad status change'; end if;
  if old.status <> 'draft' and new.note is distinct from old.note then raise exception 'settlement_immutable: the note is fixed after approval'; end if;
  return new;
end $$;
drop trigger if exists partner_settlements_guard on public.partner_settlements;
create trigger partner_settlements_guard before update or delete on public.partner_settlements for each row execute function public._a44_set_guard();
create or replace function public._a44_line_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'append_only: settlement lines are never deleted'; end if;
  if (to_jsonb(new) - 'paid_amount' - 'paid_at' - 'pay_mode') is distinct from (to_jsonb(old) - 'paid_amount' - 'paid_at' - 'pay_mode') then
    raise exception 'settlement_immutable: only payments can change a line'; end if;
  return new;
end $$;
drop trigger if exists partner_settlement_lines_guard on public.partner_settlement_lines;
create trigger partner_settlement_lines_guard before update or delete on public.partner_settlement_lines for each row execute function public._a44_line_guard();

-- audit
drop trigger if exists audit_partner_parties on public.partner_parties;
create trigger audit_partner_parties after insert or update on public.partner_parties for each row execute function public.log_change('id');
drop trigger if exists audit_partner_ventures on public.partner_ventures;
create trigger audit_partner_ventures after insert or update on public.partner_ventures for each row execute function public.log_change('id');
drop trigger if exists audit_partner_agreements on public.partner_agreements;
create trigger audit_partner_agreements after insert or update on public.partner_agreements for each row execute function public.log_change('id');
drop trigger if exists audit_agreement_parties on public.agreement_parties;
create trigger audit_agreement_parties after insert or update on public.agreement_parties for each row execute function public.log_change('id');
drop trigger if exists audit_partner_rules on public.partner_rules;
create trigger audit_partner_rules after insert or update on public.partner_rules for each row execute function public.log_change('id');
drop trigger if exists audit_partner_capital on public.partner_capital;
create trigger audit_partner_capital after insert or update on public.partner_capital for each row execute function public.log_change('id');
drop trigger if exists audit_partner_settlements on public.partner_settlements;
create trigger audit_partner_settlements after insert or update on public.partner_settlements for each row execute function public.log_change('id');
drop trigger if exists audit_partner_settlement_lines on public.partner_settlement_lines;
create trigger audit_partner_settlement_lines after insert or update on public.partner_settlement_lines for each row execute function public.log_change('id');
drop trigger if exists audit_partner_settlement_payments on public.partner_settlement_payments;
create trigger audit_partner_settlement_payments after insert on public.partner_settlement_payments for each row execute function public.log_change('id');

-- ============================================================
-- 5. RLS: owner reads, nobody writes directly
-- ============================================================
do $$
declare t text;
begin
  foreach t in array array['partner_parties', 'partner_ventures', 'partner_agreements', 'agreement_parties', 'partner_rules', 'partner_capital',
                           'partner_settlements', 'partner_settlement_lines', 'partner_settlement_payments', 'partner_templates'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_sel', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.is_owner())', t || '_sel', t);
  end loop;
end $$;

-- ============================================================
-- 6. parties, ventures
-- ============================================================
create or replace function public.partner_party_save(p_id bigint, p_name text, p_kind text, p_mobile text, p_email text, p_nid text, p_address text, p_photo text, p_notes text, p_active boolean, p_client uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.partner_parties;
begin
  perform public._a44_guard();
  if nullif(btrim(coalesce(p_name, '')), '') is null or length(p_name) > 200 then raise exception 'name_required'; end if;
  if coalesce(p_kind, 'individual') not in ('individual', 'company') then raise exception 'bad_kind'; end if;
  if p_id is null then
    if p_client is not null then perform public._client_lock(p_client); select * into r from public.partner_parties where client_id = p_client; if found then return to_jsonb(r); end if; end if;
    insert into public.partner_parties (name, kind, mobile, email, nid_or_reg, address, photo_path, notes, active, client_id, created_by)
      values (btrim(p_name), coalesce(p_kind, 'individual'), nullif(btrim(p_mobile), ''), nullif(btrim(p_email), ''), nullif(btrim(p_nid), ''), nullif(btrim(p_address), ''), nullif(p_photo, ''), nullif(btrim(p_notes), ''),
              coalesce(p_active, true), p_client, auth.uid()) returning * into r;
  else
    update public.partner_parties set name = btrim(p_name), kind = coalesce(p_kind, kind), mobile = nullif(btrim(p_mobile), ''), email = nullif(btrim(p_email), ''), nid_or_reg = nullif(btrim(p_nid), ''),
           address = nullif(btrim(p_address), ''), photo_path = coalesce(nullif(p_photo, ''), photo_path), notes = nullif(btrim(p_notes), ''), active = coalesce(p_active, active)
     where id = p_id returning * into r;
    if not found then raise exception 'not_found'; end if;
  end if;
  return to_jsonb(r);
end $$;

create or replace function public.partner_venture_save(p_id bigint, p_name_bn text, p_name_en text, p_scope text, p_location_id int, p_model text, p_start date, p_end date, p_status text, p_notes text, p_client uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.partner_ventures; st text := coalesce(p_status, 'draft');
begin
  perform public._a44_guard();
  if nullif(btrim(coalesce(p_name_bn, '')), '') is null then raise exception 'name_required'; end if;
  if coalesce(p_scope, 'business') not in ('location', 'business', 'product_line', 'custom') then raise exception 'bad_scope'; end if;
  if coalesce(p_model, 'partnership') not in ('own', 'franchise', 'funded', 'partnership', 'loan', 'custom') then raise exception 'bad_model'; end if;
  if st not in ('draft', 'active', 'closed') then raise exception 'bad_status'; end if;
  if coalesce(p_scope, 'business') = 'location' and not exists (select 1 from public.locations where id = p_location_id) then raise exception 'location_not_found'; end if;
  if p_end is not null and p_start is not null and p_end < p_start then raise exception 'bad_date'; end if;
  if p_id is null then
    if p_client is not null then perform public._client_lock(p_client); select * into r from public.partner_ventures where client_id = p_client; if found then return to_jsonb(r); end if; end if;
    insert into public.partner_ventures (name_bn, name_en, scope, location_id, model, start_date, end_date, status, notes, client_id, created_by)
      values (btrim(p_name_bn), nullif(btrim(p_name_en), ''), coalesce(p_scope, 'business'), case when p_scope = 'location' then p_location_id end, coalesce(p_model, 'partnership'), p_start, p_end, st, nullif(btrim(p_notes), ''), p_client, auth.uid())
      returning * into r;
  else
    if st = 'closed' and exists (select 1 from public.partner_agreements where venture_id = p_id and status = 'active') then raise exception 'agreements_open'; end if;
    update public.partner_ventures set name_bn = btrim(p_name_bn), name_en = nullif(btrim(p_name_en), ''), scope = coalesce(p_scope, scope), location_id = case when coalesce(p_scope, scope) = 'location' then p_location_id end,
           model = coalesce(p_model, model), start_date = p_start, end_date = p_end, status = st, notes = nullif(btrim(p_notes), '') where id = p_id returning * into r;
    if not found then raise exception 'not_found'; end if;
  end if;
  return to_jsonb(r);
end $$;

-- ============================================================
-- 7. agreements (deeds)
-- ============================================================
create or replace function public._a44_clauses_ok(c jsonb) returns void language plpgsql immutable as $$
declare e jsonb;
begin
  if c is null or jsonb_typeof(c) <> 'array' or jsonb_array_length(c) > 200 then raise exception 'bad_clauses'; end if;
  for e in select value from jsonb_array_elements(c) loop
    if jsonb_typeof(e) <> 'object' or length(coalesce(e ->> 'text_bn', '')) > 20000 or length(coalesce(e ->> 'text_en', '')) > 20000
       or length(coalesce(e ->> 'title_bn', '')) > 300 or length(coalesce(e ->> 'title_en', '')) > 300 then raise exception 'bad_clauses'; end if;
  end loop;
end $$;

-- create (p_id null) or edit a DRAFT deed. Clauses are free text, reordered by sending the array in the new order (no is renumbered here).
create or replace function public.partner_agreement_save(p_id bigint, p_venture bigint, p_title text, p_from date, p_to date, p_clauses jsonb, p_signed_doc text, p_client uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.partner_agreements; cl jsonb; i int := 0; e jsonb;
begin
  perform public._a44_guard();
  if nullif(btrim(coalesce(p_title, '')), '') is null then raise exception 'name_required'; end if;
  if p_to is not null and p_from is not null and p_to < p_from then raise exception 'bad_date'; end if;
  perform public._a44_clauses_ok(coalesce(p_clauses, '[]'::jsonb));
  cl := '[]'::jsonb;
  for e in select value from jsonb_array_elements(coalesce(p_clauses, '[]'::jsonb)) loop i := i + 1; cl := cl || jsonb_build_array(jsonb_set(e, '{no}', to_jsonb(i))); end loop;
  if p_id is null then
    if not exists (select 1 from public.partner_ventures where id = p_venture) then raise exception 'venture_not_found'; end if;
    if p_client is not null then perform public._client_lock(p_client); select * into r from public.partner_agreements where client_id = p_client; if found then return to_jsonb(r); end if; end if;
    insert into public.partner_agreements (venture_id, title, effective_from, effective_to, clauses, signed_doc_path, client_id, created_by)
      values (p_venture, btrim(p_title), p_from, p_to, cl, nullif(p_signed_doc, ''), p_client, auth.uid()) returning * into r;
  else
    select * into r from public.partner_agreements where id = p_id for update;
    if not found then raise exception 'not_found'; end if;
    if r.status <> 'draft' then
      -- the only thing a live deed accepts is the scan of the signed paper
      update public.partner_agreements set signed_doc_path = coalesce(nullif(p_signed_doc, ''), signed_doc_path) where id = p_id returning * into r;
    else
      update public.partner_agreements set title = btrim(p_title), effective_from = p_from, effective_to = p_to, clauses = cl, signed_doc_path = coalesce(nullif(p_signed_doc, ''), signed_doc_path) where id = p_id returning * into r;
    end if;
  end if;
  return to_jsonb(r);
end $$;

create or replace function public.partner_agreement_party_set(p_agr bigint, p_party bigint, p_role text, p_share numeric, p_notes text, p_active boolean default true)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.agreement_parties;
begin
  perform public._a44_guard();
  if p_role not in ('owner', 'partner', 'investor', 'franchisee', 'manager', 'lender') then raise exception 'bad_role'; end if;
  if p_share is not null and (p_share < 0 or p_share > 100) then raise exception 'bad_percent'; end if;
  if not exists (select 1 from public.partner_agreements where id = p_agr) then raise exception 'not_found'; end if;
  if not exists (select 1 from public.partner_parties where id = p_party) then raise exception 'party_not_found'; end if;
  insert into public.agreement_parties (agreement_id, party_id, role, share_percent, notes, active) values (p_agr, p_party, p_role, p_share, nullif(btrim(p_notes), ''), coalesce(p_active, true))
    on conflict (agreement_id, party_id, role) do update set share_percent = excluded.share_percent, notes = excluded.notes, active = excluded.active returning * into r;
  return to_jsonb(r);
end $$;

create or replace function public.partner_rule_save(p_agr bigint, p_step_no int, p_name text, p_kind text, p_config jsonb, p_active boolean default true)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.partner_rules; cfg jsonb; n int := p_step_no;
begin
  perform public._a44_guard();
  if nullif(btrim(coalesce(p_name, '')), '') is null then raise exception 'name_required'; end if;
  cfg := public.partner_rule_validate(p_kind, p_config);
  if not exists (select 1 from public.partner_agreements where id = p_agr) then raise exception 'not_found'; end if;
  if n is null then select coalesce(max(step_no), 0) + 1 into n from public.partner_rules where agreement_id = p_agr; end if;
  insert into public.partner_rules (agreement_id, step_no, name, kind, config, active) values (p_agr, n, btrim(p_name), p_kind, cfg, coalesce(p_active, true))
    on conflict (agreement_id, step_no) do update set name = excluded.name, kind = excluded.kind, config = excluded.config, active = excluded.active returning * into r;
  return to_jsonb(r);
end $$;

-- new order = array of step numbers
create or replace function public.partner_rules_reorder(p_agr bigint, p_order jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare cnt int; i int := 0; e jsonb; st text;
begin
  perform public._a44_guard();
  select status into st from public.partner_agreements where id = p_agr;
  if st is null then raise exception 'not_found'; end if;
  if st <> 'draft' then raise exception 'agreement_immutable: the deed is not a draft'; end if;
  if p_order is null or jsonb_typeof(p_order) <> 'array' then raise exception 'bad_order'; end if;
  select count(*) into cnt from public.partner_rules where agreement_id = p_agr;
  if jsonb_array_length(p_order) <> cnt or (select count(distinct v) from jsonb_array_elements_text(p_order) v) <> cnt
     or exists (select 1 from jsonb_array_elements_text(p_order) v where not exists (select 1 from public.partner_rules r where r.agreement_id = p_agr and r.step_no = v::int)) then raise exception 'bad_order'; end if;
  update public.partner_rules set step_no = step_no + 100000 where agreement_id = p_agr;
  for e in select value from jsonb_array_elements(p_order) loop
    i := i + 1; update public.partner_rules set step_no = i where agreement_id = p_agr and step_no = (e #>> '{}')::int + 100000;
  end loop;
  return jsonb_build_object('agreement_id', p_agr, 'steps', cnt);
end $$;

-- a deed must be coherent before it goes live
create or replace function public._a44_check_ready(p_agr bigint) returns void language plpgsql stable security definer set search_path = public as $$
declare r record; nb int := 0; first_kind text; i int := 0; e jsonb;
begin
  if not exists (select 1 from public.agreement_parties where agreement_id = p_agr and active) then raise exception 'no_parties'; end if;
  if (select count(*) from public.partner_rules where agreement_id = p_agr and active) = 0 then raise exception 'no_rules'; end if;
  for r in select * from public.partner_rules where agreement_id = p_agr and active order by step_no loop
    i := i + 1; perform public.partner_rule_validate(r.kind, r.config);
    if i = 1 then first_kind := r.kind; end if;
    if r.kind = 'base' then nb := nb + 1; end if;
    if r.kind in ('royalty', 'management_fee', 'priority_return', 'payback', 'minimum_guarantee') or (r.kind in ('cap', 'floor') and r.config ->> 'target' = 'party') then
      if public._a44_ref(p_agr, r.config) is null then raise exception 'party_unresolved: %', r.name; end if;
    elsif r.kind = 'split' then
      for e in select value from jsonb_array_elements(r.config -> 'shares') loop if public._a44_ref(p_agr, e) is null then raise exception 'party_unresolved: %', r.name; end if; end loop;
    elsif r.kind = 'tiered_split' then
      for e in select s.value from jsonb_array_elements(r.config -> 'slabs') sl, jsonb_array_elements(sl.value -> 'shares') s loop if public._a44_ref(p_agr, e) is null then raise exception 'party_unresolved: %', r.name; end if; end loop;
    end if;
  end loop;
  if nb <> 1 or first_kind is distinct from 'base' then raise exception 'base_step_first'; end if;
end $$;

create or replace function public.partner_agreement_activate(p_agr bigint, p_numbers_confirmed boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.partner_agreements; prev public.partner_agreements;
begin
  perform public._a44_guard();
  select * into a from public.partner_agreements where id = p_agr for update;
  if not found then raise exception 'not_found'; end if;
  if a.status <> 'draft' then raise exception 'not_draft'; end if;
  if a.effective_from is null then raise exception 'dates_required'; end if;
  if a.is_example and not coalesce(p_numbers_confirmed, false) then raise exception 'example_numbers_not_confirmed'; end if;
  perform public._a44_check_ready(p_agr);
  if a.supersedes_id is not null then
    select * into prev from public.partner_agreements where id = a.supersedes_id for update;
    if prev.status <> 'active' then raise exception 'previous_not_active'; end if;
    if a.effective_from <= prev.effective_from then raise exception 'bad_date'; end if;
    if exists (select 1 from public.partner_settlements s where s.agreement_id in (select id from public._a44_chain(p_agr)) and s.status <> 'void' and s.period_to >= a.effective_from) then raise exception 'period_already_settled'; end if;
    update public.partner_agreements set status = 'amended', effective_to = a.effective_from - 1, closed_at = now(), closed_by = auth.uid(), closed_note = 'amended by #' || a.id where id = prev.id;
  elsif exists (select 1 from public.partner_agreements x where x.venture_id = a.venture_id and x.status = 'active' and x.id <> a.id) then
    null;   -- several deeds on one venture are allowed (e.g. one per investor); the owner chooses
  end if;
  update public.partner_agreements set status = 'active', activated_by = auth.uid(), activated_at = now() where id = p_agr returning * into a;
  update public.partner_ventures set status = 'active' where id = a.venture_id and status = 'draft';
  return to_jsonb(a);
end $$;

create or replace function public.partner_agreement_amend(p_agr bigint, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.partner_agreements; n public.partner_agreements;
begin
  perform public._a44_guard();
  if p_client is not null then perform public._client_lock(p_client); select * into n from public.partner_agreements where client_id = p_client; if found then return to_jsonb(n); end if; end if;
  select * into a from public.partner_agreements where id = p_agr for update;
  if not found then raise exception 'not_found'; end if;
  if a.status <> 'active' then raise exception 'not_active'; end if;
  if exists (select 1 from public.partner_agreements where supersedes_id = a.id) then raise exception 'draft_exists'; end if;
  insert into public.partner_agreements (venture_id, title, version, status, effective_from, effective_to, clauses, signed_doc_path, supersedes_id, is_example, client_id, created_by)
    values (a.venture_id, a.title, a.version + 1, 'draft', null, null, a.clauses, null, a.id, false, p_client, auth.uid()) returning * into n;
  insert into public.agreement_parties (agreement_id, party_id, role, share_percent, notes, active) select n.id, party_id, role, share_percent, notes, active from public.agreement_parties where agreement_id = a.id;
  insert into public.partner_rules (agreement_id, step_no, step_key, name, kind, config, active) select n.id, step_no, step_key, name, kind, config, active from public.partner_rules where agreement_id = a.id;
  return to_jsonb(n);
end $$;

create or replace function public.partner_agreement_close(p_agr bigint, p_note text default null, p_date date default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.partner_agreements; d date := coalesce(p_date, public._a44_today());
begin
  perform public._a44_guard();
  select * into a from public.partner_agreements where id = p_agr for update;
  if not found then raise exception 'not_found'; end if;
  if a.status <> 'active' then raise exception 'not_active'; end if;
  if d < a.effective_from then raise exception 'bad_date'; end if;
  update public.partner_agreements set status = 'closed', effective_to = d, closed_by = auth.uid(), closed_at = now(), closed_note = left(p_note, 500) where id = p_agr returning * into a;
  return to_jsonb(a);
end $$;

-- a draft deed from a seeded EXAMPLE template (parties and numbers still to be chosen; activation asks the owner to confirm the numbers)
create or replace function public.partner_agreement_from_template(p_venture bigint, p_code text, p_title text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.partner_templates; r public.partner_agreements; e jsonb; i int := 0;
begin
  perform public._a44_guard();
  select * into t from public.partner_templates where code = p_code;
  if not found then raise exception 'template_not_found'; end if;
  if not exists (select 1 from public.partner_ventures where id = p_venture) then raise exception 'venture_not_found'; end if;
  if p_client is not null then perform public._client_lock(p_client); select * into r from public.partner_agreements where client_id = p_client; if found then return to_jsonb(r); end if; end if;
  insert into public.partner_agreements (venture_id, title, clauses, is_example, client_id, created_by)
    values (p_venture, coalesce(nullif(btrim(p_title), ''), 'EXAMPLE - ' || t.name_en), t.clauses, true, p_client, auth.uid()) returning * into r;
  for e in select value from jsonb_array_elements(t.rules) loop
    i := i + 1;
    insert into public.partner_rules (agreement_id, step_no, name, kind, config, active) values (r.id, i, e ->> 'name', e ->> 'kind', e -> 'config', true);
  end loop;
  return to_jsonb(r);
end $$;

-- ============================================================
-- 8. capital ledger
-- ============================================================
create or replace function public.partner_capital_add(p_agr bigint, p_party bigint, p_kind text, p_amount numeric, p_date date, p_mode text, p_desc text, p_ref text, p_client uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.partner_capital; a public.partner_agreements; bal numeric;
begin
  perform public._a44_guard();
  if p_kind not in ('contribution', 'return_of_capital', 'loan_in', 'loan_repayment', 'owner_drawing') then raise exception 'bad_kind'; end if;
  if p_mode not in ('cash', 'bank', 'mobile', 'in_kind') then raise exception 'bad_mode'; end if;
  perform public._a44_chk_money(p_amount); perform public._a44_chk_date(p_date); perform public.lock_check(p_date);
  if p_client is not null then perform public._client_lock(p_client); select * into r from public.partner_capital where client_id = p_client; if found then return to_jsonb(r); end if; end if;
  select * into a from public.partner_agreements where id = p_agr;
  if not found then raise exception 'not_found'; end if;
  if a.status <> 'active' then raise exception 'not_active'; end if;
  if not exists (select 1 from public.agreement_parties where agreement_id = p_agr and party_id = p_party and active) then raise exception 'party_not_in_deed'; end if;
  if p_kind in ('return_of_capital', 'loan_repayment') then
    bal := public._a44_cap(p_agr, p_party, p_date);
    if p_amount > bal + 0.004 then raise exception 'exceeds_capital'; end if;
  end if;
  insert into public.partner_capital (agreement_id, party_id, kind, amount, cap_date, mode, description, ref, client_id, created_by)
    values (p_agr, p_party, p_kind, round(p_amount, 2), p_date, p_mode, nullif(btrim(p_desc), ''), nullif(btrim(p_ref), ''), p_client, auth.uid()) returning * into r;
  return to_jsonb(r);
end $$;

create or replace function public.partner_capital_void(p_id bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.partner_capital;
begin
  perform public._a44_guard();
  if nullif(btrim(coalesce(p_reason, '')), '') is null then raise exception 'reason_required'; end if;
  select * into r from public.partner_capital where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if r.status = 'void' then return to_jsonb(r); end if;
  perform public.lock_check(r.cap_date);
  update public.partner_capital set status = 'void', void_reason = left(p_reason, 300), void_by = auth.uid(), void_at = now() where id = p_id returning * into r;
  return to_jsonb(r);
end $$;

-- per party: contributed, loans in, returned, repaid, drawings, balance, paid back through settlements, outstanding payback
create or replace function public.partner_capital_balances(p_agr bigint, p_asof date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_asof, public._a44_today()); out jsonb;
begin
  perform public._a44_guard();
  select coalesce(jsonb_agg(x order by x ->> 'name'), '[]'::jsonb) into out from (
    select jsonb_build_object('party_id', p.id, 'name', p.name,
      'contributed', coalesce(sum(c.amount) filter (where c.kind = 'contribution'), 0), 'loan_in', coalesce(sum(c.amount) filter (where c.kind = 'loan_in'), 0),
      'returned', coalesce(sum(c.amount) filter (where c.kind = 'return_of_capital'), 0), 'repaid', coalesce(sum(c.amount) filter (where c.kind = 'loan_repayment'), 0),
      'drawings', coalesce(sum(c.amount) filter (where c.kind = 'owner_drawing'), 0),
      'balance', public._a44_cap(p_agr, p.id, d),
      'paid_back', (select coalesce(sum(l.amount), 0) from public.partner_settlement_lines l join public.partner_settlements s on s.id = l.settlement_id
                     where s.agreement_id in (select id from public._a44_chain(p_agr)) and s.status <> 'void' and l.kind = 'payback' and l.party_id = p.id and s.period_to <= d),
      'outstanding_payback', public._a44_cap(p_agr, p.id, d) - (select coalesce(sum(l.amount), 0) from public.partner_settlement_lines l join public.partner_settlements s on s.id = l.settlement_id
                     where s.agreement_id in (select id from public._a44_chain(p_agr)) and s.status <> 'void' and l.kind = 'payback' and l.party_id = p.id and s.period_to <= d)) as x
    from public.partner_parties p
    left join public.partner_capital c on c.party_id = p.id and c.agreement_id in (select id from public._a44_chain(p_agr)) and c.status = 'posted' and c.cap_date <= d
    where p.id in (select party_id from public.agreement_parties where agreement_id in (select id from public._a44_chain(p_agr)))
    group by p.id, p.name) q;
  return out;
end $$;

-- ============================================================
-- 9. the calculation engine (trial - writes nothing)
-- ============================================================
create or replace function public.partner_calculate(p_agr bigint, p_from date, p_to date, p_manual jsonb default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  ag public.partner_agreements; vn public.partner_ventures; locs int[]; k text; r record; cfg jsonb; sh jsonb; er record; er2 record;
  bases jsonb := '{}'::jsonb; src jsonb := '{}'::jsonb; warns jsonb := '[]'::jsonb; steps jsonb := '[]'::jsonb; lines jsonb := '[]'::jsonb; nl jsonb;
  v_gs numeric; v_ns numeric; v_costed numeric; v_cogs numeric; v_exp numeric; v_sal numeric; v_fix numeric; v_gp numeric; v_nf numeric; v_n int;
  pool numeric; poolset boolean := false; incomplete boolean := false; fees numeric := 0;
  rto numeric := 0.01; rmode text := 'nearest';
  carry_in numeric := 0; carry_out numeric := 0; retained numeric := 0; floor_added numeric := 0;
  amt numeric; core numeric; stepamt numeric; pool_before numeric; pid bigint; pct numeric; mths numeric := public._a44_months(p_from, p_to); days int := p_to - p_from + 1;
  capb numeric; due numeric; capc numeric; paid_b numeric; sf_in numeric; short_out numeric; outb numeric; a1 numeric; a2 numeric; used numeric; tgt numeric; lim numeric; tot numeric; exc numeric; rem numeric; red numeric;
  detail jsonb; skipped boolean; remaining numeric; prev_up numeric; size numeric; dist jsonb; d jsonb; need numeric; outside boolean; names jsonb; ptot jsonb; tdist numeric := 0; tout numeric := 0;
  nbase int := 0; newlines jsonb;
begin
  perform public._a44_guard();
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 3660 then raise exception 'bad_range'; end if;
  select * into ag from public.partner_agreements where id = p_agr;
  if not found then raise exception 'not_found'; end if;
  select * into vn from public.partner_ventures where id = ag.venture_id;
  -- manual figures typed by the owner
  if p_manual is not null then
    if jsonb_typeof(p_manual) <> 'object' then raise exception 'bad_manual'; end if;
    for k in select jsonb_object_keys(p_manual) loop
      if k not in ('gross_sales', 'net_sales', 'gross_profit', 'net_profit_before_fees', 'manual', 'carry_in') or public._a44_n(p_manual -> k) is null or abs(public._a44_n(p_manual -> k)) > 1000000000000 then raise exception 'bad_manual'; end if;
    end loop;
  end if;
  -- bases from the books (only what can be computed honestly)
  if vn.scope in ('location', 'business') then
    locs := case when vn.scope = 'location' then array[vn.location_id] else array(select id from public.locations) end;
    select count(*), coalesce(sum(o_gross), 0), coalesce(sum(o_net), 0), coalesce(sum(o_costed), 0), coalesce(sum(o_cogs), 0), coalesce(sum(o_exp), 0), coalesce(sum(o_sal), 0), sum(o_fixed)
      into v_n, v_gs, v_ns, v_costed, v_cogs, v_exp, v_sal, v_fix from public._p27_pl(p_from, p_to, locs);
    bases := jsonb_build_object('gross_sales', v_gs, 'net_sales', v_ns);
    if abs(v_ns - v_costed) <= greatest(1, abs(v_ns) * 0.001) then
      v_gp := round(v_ns - v_cogs, 2); v_nf := round(v_gp - v_exp - v_sal - coalesce(v_fix, 0), 2);
      bases := bases || jsonb_build_object('gross_profit', v_gp, 'net_profit_before_fees', v_nf);
    else
      warns := warns || jsonb_build_array(jsonb_build_object('code', 'uncosted_sales', 'detail', round(v_ns - v_costed, 2), 'msg', 'Some sold items have no cost price, so gross profit cannot be computed honestly. Type a manual base.'));
      bases := bases || jsonb_build_object('gross_profit', null, 'net_profit_before_fees', null);
    end if;
    bases := bases || jsonb_build_object('expenses', v_exp, 'salary', v_sal, 'fixed_cost', v_fix, 'cogs', v_cogs);
    if v_n = 0 then warns := warns || jsonb_build_array(jsonb_build_object('code', 'no_book_rows', 'msg', 'No sales, expenses or salary were recorded in this period.')); end if;
  else
    bases := jsonb_build_object('gross_sales', null, 'net_sales', null, 'gross_profit', null, 'net_profit_before_fees', null);
    warns := warns || jsonb_build_array(jsonb_build_object('code', 'manual_only', 'msg', 'A product-line or custom venture has no books of its own - type the manual base.'));
  end if;
  for k in select jsonb_object_keys(coalesce(p_manual, '{}'::jsonb)) loop
    if k <> 'carry_in' then bases := bases || jsonb_build_object(k, public._a44_n(p_manual -> k)); src := src || jsonb_build_object(k, 'manual'); end if;
  end loop;
  for k in select unnest(array['gross_sales', 'net_sales', 'gross_profit', 'net_profit_before_fees']) loop
    if not src ? k then src := src || jsonb_build_object(k, case when bases -> k is null or jsonb_typeof(bases -> k) = 'null' then 'unavailable' else 'books' end); end if;
  end loop;
  -- loss carried from the earlier settlement
  if p_manual ? 'carry_in' then carry_in := greatest(public._a44_n(p_manual -> 'carry_in'), 0);
  else
    select coalesce(s.carry_out, 0) into carry_in from public.partner_settlements s
     where s.agreement_id in (select id from public._a44_chain(p_agr)) and s.status <> 'void' and s.period_to < p_from order by s.period_to desc limit 1;
    carry_in := coalesce(carry_in, 0);
  end if;

  for r in select * from public.partner_rules where agreement_id = p_agr and active order by step_no loop
    cfg := r.config; stepamt := 0; core := null; detail := '{}'::jsonb; skipped := false; pool_before := pool; short_out := null;
    if r.kind <> 'base' and r.kind <> 'rounding' and not poolset then raise exception 'base_step_first'; end if;
    if incomplete and r.kind <> 'rounding' and r.kind <> 'base' then
      skipped := true; detail := jsonb_build_object('skipped', 'no_base');
    else
    case r.kind
      when 'base' then
        nbase := nbase + 1; if nbase > 1 then raise exception 'base_twice'; end if;
        k := cfg ->> 'base';
        pool := case k when 'fixed_amount' then public._a44_n(cfg -> 'amount')
                       when 'manual' then public._a44_n(bases -> 'manual')
                       when 'net_profit' then case when public._a44_n(bases -> 'net_profit_before_fees') is null then null else public._a44_n(bases -> 'net_profit_before_fees') - fees end
                       else public._a44_n(bases -> k) end;
        poolset := true;
        if pool is null then
          incomplete := true;
          warns := warns || jsonb_build_array(jsonb_build_object('code', 'base_unavailable', 'base', k, 'step_no', r.step_no, 'msg', 'This base cannot be computed from the books - type a manual base.'));
        end if;
        detail := jsonb_build_object('base', k, 'value', pool); pool_before := null;
      when 'royalty' then
        pid := public._a44_need(p_agr, cfg, r.name); k := coalesce(cfg ->> 'base', 'net_sales');
        if public._a44_n(bases -> k) is null then
          incomplete := true; skipped := true; detail := jsonb_build_object('skipped', 'no_base');
          warns := warns || jsonb_build_array(jsonb_build_object('code', 'base_unavailable', 'base', k, 'step_no', r.step_no, 'msg', 'The royalty base cannot be computed - type a manual base.'));
        else
          amt := public._a44_round(greatest(public._a44_n(bases -> k), 0) * public._a44_n(cfg -> 'percent') / 100, rto, rmode);
          lines := lines || jsonb_build_array(jsonb_build_object('step_no', r.step_no, 'party_id', pid, 'kind', 'royalty', 'amount', amt, 'outside', false));
          pool := pool - amt; fees := fees + amt; stepamt := amt; core := amt;
          detail := jsonb_build_object('base', k, 'base_value', public._a44_n(bases -> k), 'percent', public._a44_n(cfg -> 'percent'), 'party_id', pid);
        end if;
      when 'management_fee' then
        pid := public._a44_need(p_agr, cfg, r.name);
        if public._a44_n(cfg -> 'fixed') is not null then
          amt := public._a44_round(public._a44_n(cfg -> 'fixed') * case when coalesce(cfg ->> 'per', 'period') = 'month' then mths else 1 end, rto, rmode);
        else
          k := cfg ->> 'base';
          if k is not null and public._a44_n(bases -> k) is null then amt := null; incomplete := true; skipped := true; detail := jsonb_build_object('skipped', 'no_base');
            warns := warns || jsonb_build_array(jsonb_build_object('code', 'base_unavailable', 'base', k, 'step_no', r.step_no, 'msg', 'The fee base cannot be computed - type a manual base.'));
          else amt := public._a44_round(greatest(coalesce(public._a44_n(bases -> k), pool), 0) * public._a44_n(cfg -> 'percent') / 100, rto, rmode); end if;
        end if;
        if amt is not null then
          lines := lines || jsonb_build_array(jsonb_build_object('step_no', r.step_no, 'party_id', pid, 'kind', 'fee', 'amount', amt, 'outside', false));
          pool := pool - amt; fees := fees + amt; stepamt := amt; core := amt; detail := jsonb_build_object('party_id', pid, 'months', round(mths, 4));
        end if;
      when 'expense_allow' then
        select coalesce(sum(public._a44_n(i -> 'amount')), 0) into amt from jsonb_array_elements(cfg -> 'items') i;
        pool := pool - amt; stepamt := -amt; detail := jsonb_build_object('items', cfg -> 'items', 'total', amt);
      when 'expense_disallow' then
        select coalesce(sum(public._a44_n(i -> 'amount')), 0) into amt from jsonb_array_elements(cfg -> 'items') i;
        pool := pool + amt; stepamt := amt; detail := jsonb_build_object('items', cfg -> 'items', 'total', amt);
      when 'loss_carry_forward' then
        amt := pool - carry_in;
        if amt < 0 then carry_out := -amt; pool := 0; else carry_out := 0; pool := amt; end if;
        detail := jsonb_build_object('carry_in', carry_in, 'carry_out', carry_out);
      when 'priority_return' then
        pid := public._a44_need(p_agr, cfg, r.name);
        if public._a44_n(cfg -> 'percent_per_year') is not null then
          due := round(public._a44_capdays(p_agr, pid, p_from, p_to) * public._a44_n(cfg -> 'percent_per_year') / 100 / 365, 2);
        else due := round(public._a44_n(cfg -> 'fixed_monthly') * mths, 2); end if;
        select h.paid_before, h.shortfall_in into paid_b, sf_in from public._a44_step_hist(p_agr, p_from, r.step_key::text) h;
        if coalesce((cfg ->> 'catch_up')::boolean, false) then due := due + sf_in; else sf_in := 0; end if;
        due := public._a44_round(due, rto, rmode);
        if public._a44_n(cfg -> 'cap') is not null then due := least(due, greatest(public._a44_n(cfg -> 'cap') - paid_b, 0)); end if;
        amt := least(due, greatest(pool, 0));
        short_out := case when coalesce((cfg ->> 'catch_up')::boolean, false) then due - amt else 0 end;
        if amt > 0 then lines := lines || jsonb_build_array(jsonb_build_object('step_no', r.step_no, 'party_id', pid, 'kind', 'return', 'amount', amt, 'outside', false)); end if;
        pool := pool - amt; stepamt := amt; core := amt;
        detail := jsonb_build_object('party_id', pid, 'due', due, 'catch_up_in', sf_in, 'paid_before', paid_b, 'shortfall_out', short_out);
        if amt < due and not coalesce((cfg ->> 'catch_up')::boolean, false) then warns := warns || jsonb_build_array(jsonb_build_object('code', 'return_short', 'step_no', r.step_no, 'msg', 'The profit was not enough for the whole priority return.')); end if;
      when 'payback' then
        pid := public._a44_need(p_agr, cfg, r.name); pct := coalesce(public._a44_n(cfg -> 'percent'), 100);
        select h.paid_before into paid_b from public._a44_step_hist(p_agr, p_from, r.step_key::text) h;
        outb := coalesce(public._a44_n(cfg -> 'target'), public._a44_cap(p_agr, pid, p_to)) - paid_b;
        a1 := 0; a2 := 0;
        if outb > 0 then
          a1 := least(outb, public._a44_round(greatest(pool, 0) * pct / 100, rto, rmode));
          if public._a44_n(cfg -> 'then_percent') is not null and a1 >= outb - 0.004 and greatest(pool, 0) * pct / 100 > outb then
            used := outb / (pct / 100); a2 := public._a44_round(greatest(pool - used, 0) * public._a44_n(cfg -> 'then_percent') / 100, rto, rmode);
          end if;
        elsif public._a44_n(cfg -> 'then_percent') is not null then
          a2 := public._a44_round(greatest(pool, 0) * public._a44_n(cfg -> 'then_percent') / 100, rto, rmode);
        end if;
        if a1 > 0 then lines := lines || jsonb_build_array(jsonb_build_object('step_no', r.step_no, 'party_id', pid, 'kind', 'payback', 'amount', a1, 'outside', false)); end if;
        if a2 > 0 then lines := lines || jsonb_build_array(jsonb_build_object('step_no', r.step_no, 'party_id', pid, 'kind', 'share', 'amount', a2, 'outside', false)); end if;
        pool := pool - a1 - a2; stepamt := a1 + a2; core := a1;
        detail := jsonb_build_object('party_id', pid, 'outstanding_before', greatest(outb, 0), 'payback', a1, 'then_share', a2, 'outstanding_after', greatest(outb - a1, 0));
      when 'split' then
        if pool > 0 then
          dist := public._a44_distribute(p_agr, pool, cfg -> 'shares', rto, rmode, r.name);
          for d in select value from jsonb_array_elements(dist) loop
            lines := lines || jsonb_build_array(jsonb_build_object('step_no', r.step_no, 'party_id', (d ->> 'party_id')::bigint, 'kind', 'share', 'amount', (d ->> 'amount')::numeric, 'outside', false));
          end loop;
          stepamt := pool; detail := jsonb_build_object('distributed', pool, 'parts', dist); pool := 0;
        else
          warns := warns || jsonb_build_array(jsonb_build_object('code', 'no_profit', 'step_no', r.step_no, 'msg', 'There is no profit to share at this step.'));
          detail := jsonb_build_object('distributed', 0);
        end if;
      when 'tiered_split' then
        if pool > 0 then
          remaining := pool; prev_up := 0; detail := jsonb_build_object('slabs', '[]'::jsonb);
          for er in select value as v, ord from jsonb_array_elements(cfg -> 'slabs') with ordinality as t(value, ord) order by ord loop
            exit when remaining <= 0;
            size := case when public._a44_n(er.v -> 'upto') is null then remaining else least(remaining, public._a44_n(er.v -> 'upto') - prev_up) end;
            dist := public._a44_distribute(p_agr, size, er.v -> 'shares', rto, rmode, r.name);
            for d in select value from jsonb_array_elements(dist) loop
              lines := lines || jsonb_build_array(jsonb_build_object('step_no', r.step_no, 'party_id', (d ->> 'party_id')::bigint, 'kind', 'share', 'amount', (d ->> 'amount')::numeric, 'outside', false));
            end loop;
            detail := jsonb_set(detail, '{slabs}', (detail -> 'slabs') || jsonb_build_array(jsonb_build_object('slab', er.ord, 'amount', size, 'parts', dist)));
            remaining := remaining - size; stepamt := stepamt + size;
            if public._a44_n(er.v -> 'upto') is not null then prev_up := public._a44_n(er.v -> 'upto'); end if;
          end loop;
          pool := remaining;
        else
          warns := warns || jsonb_build_array(jsonb_build_object('code', 'no_profit', 'step_no', r.step_no, 'msg', 'There is no profit to share at this step.'));
        end if;
      when 'minimum_guarantee', 'floor' then
        if r.kind = 'floor' and coalesce(cfg ->> 'target', 'pool') = 'pool' then
          lim := public._a44_n(cfg -> 'amount');
          if pool < lim then floor_added := floor_added + (lim - pool); stepamt := lim - pool;
            warns := warns || jsonb_build_array(jsonb_build_object('code', 'floor_topup', 'step_no', r.step_no, 'detail', lim - pool, 'msg', 'The pool was lifted to the floor; the difference is funded outside the books.'));
            pool := lim; end if;
          detail := jsonb_build_object('floor', lim, 'added', greatest(stepamt, 0));
        else
          pid := public._a44_need(p_agr, cfg, r.name);
          need := public._a44_n(cfg -> 'amount') * case when coalesce(cfg ->> 'per', 'period') = 'month' then mths else 1 end;
          tot := public._a44_party_total(lines, pid, true);
          amt := 0; outside := coalesce(cfg ->> 'funded_by', 'pool') = 'outside';
          if tot < need then
            amt := need - tot;
            if not outside then
              if amt > greatest(pool, 0) then warns := warns || jsonb_build_array(jsonb_build_object('code', 'guarantee_short', 'step_no', r.step_no, 'detail', amt - greatest(pool, 0), 'msg', 'The pool could not pay the whole guarantee.')); amt := greatest(pool, 0); end if;
              pool := pool - amt;
            end if;
            amt := public._a44_round(amt, rto, rmode);
            if amt > 0 then lines := lines || jsonb_build_array(jsonb_build_object('step_no', r.step_no, 'party_id', pid, 'kind', 'guarantee', 'amount', amt, 'outside', outside)); end if;
          end if;
          stepamt := amt; core := amt; detail := jsonb_build_object('party_id', pid, 'needed', need, 'had', tot, 'topup', amt, 'funded_by', case when outside then 'outside' else 'pool' end);
        end if;
      when 'cap' then
        if coalesce(cfg ->> 'target', 'pool') = 'pool' then
          lim := public._a44_n(cfg -> 'amount');
          if pool > lim then retained := retained + (pool - lim); stepamt := -(pool - lim); pool := lim; end if;
          detail := jsonb_build_object('cap', lim, 'retained', retained);
        else
          pid := public._a44_need(p_agr, cfg, r.name);
          lim := public._a44_n(cfg -> 'amount') * case when coalesce(cfg ->> 'per', 'period') = 'month' then mths else 1 end;
          tot := public._a44_party_total(lines, pid, false); exc := greatest(tot - lim, 0); rem := exc;
          if exc > 0 then
            newlines := '[]'::jsonb;
            for er2 in select value as v, ord from jsonb_array_elements(lines) with ordinality as t(value, ord) order by ord desc loop
              if rem > 0 and (er2.v ->> 'party_id')::bigint = pid and not coalesce((er2.v ->> 'outside')::boolean, false) then
                red := least(rem, (er2.v ->> 'amount')::numeric); rem := rem - red;
                newlines := jsonb_build_array(jsonb_set(er2.v, '{amount}', to_jsonb(round((er2.v ->> 'amount')::numeric - red, 2)))) || newlines;
              else newlines := jsonb_build_array(er2.v) || newlines; end if;
            end loop;
            lines := newlines; pool := pool + exc; stepamt := -exc;
          end if;
          detail := jsonb_build_object('party_id', pid, 'cap', lim, 'had', tot, 'returned_to_pool', exc);
        end if;
      when 'rounding' then
        rto := public._a44_n(cfg -> 'to'); rmode := coalesce(cfg ->> 'mode', 'nearest'); detail := jsonb_build_object('to', rto, 'mode', rmode);
      else raise exception 'bad_kind';
    end case;
    end if;
    steps := steps || jsonb_build_array(jsonb_build_object('step_no', r.step_no, 'key', r.step_key, 'name', r.name, 'kind', r.kind, 'skipped', skipped,
        'pool_before', pool_before, 'pool_after', pool, 'amount', round(stepamt, 2), 'core', round(coalesce(core, stepamt), 2), 'shortfall_out', short_out, 'detail', detail));
  end loop;
  if nbase = 0 then raise exception 'base_step_first'; end if;
  if pool is not null and pool > 0.004 then
    retained := retained + pool;
    warns := warns || jsonb_build_array(jsonb_build_object('code', 'retained', 'detail', pool, 'msg', 'Part of the profit was not given to anybody by the rules.'));
  end if;
  select coalesce(sum((e ->> 'amount')::numeric) filter (where not coalesce((e ->> 'outside')::boolean, false)), 0), coalesce(sum((e ->> 'amount')::numeric) filter (where coalesce((e ->> 'outside')::boolean, false)), 0)
    into tdist, tout from jsonb_array_elements(lines) e;
  select coalesce(jsonb_agg(jsonb_build_object('party_id', q.pid, 'name', p.name, 'amount', q.a) order by p.name), '[]'::jsonb) into ptot
    from (select (e ->> 'party_id')::bigint as pid, sum((e ->> 'amount')::numeric) as a from jsonb_array_elements(lines) e group by 1) q join public.partner_parties p on p.id = q.pid;
  return jsonb_build_object('agreement_id', p_agr, 'venture_id', ag.venture_id, 'from', p_from, 'to', p_to, 'days', days, 'months', round(mths, 4),
    'status', case when incomplete then 'incomplete' else 'ok' end, 'bases', bases, 'sources', src, 'manual_used', coalesce(p_manual, '{}'::jsonb),
    'steps', steps, 'lines', lines, 'party_totals', ptot, 'carry_in', carry_in, 'carry_out', carry_out, 'retained', round(retained, 2), 'floor_added', round(floor_added, 2),
    'total_distributable', round(tdist, 2), 'outside_total', round(tout, 2), 'warnings', warns, 'wrote', false);
end $$;

-- ============================================================
-- 10. settlements: draft snapshot -> approve -> pay -> void
-- ============================================================
create or replace function public.partner_settlement_save(p_agr bigint, p_from date, p_to date, p_manual jsonb, p_note text, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.partner_agreements; c jsonb; s public.partner_settlements;
begin
  perform public._a44_guard();
  if p_client is not null then perform public._client_lock(p_client); select * into s from public.partner_settlements where client_id = p_client; if found then return to_jsonb(s); end if; end if;
  select * into a from public.partner_agreements where id = p_agr for update;
  if not found then raise exception 'not_found'; end if;
  if a.status <> 'active' then raise exception 'not_active'; end if;
  if p_from is null or p_to is null or p_to < p_from then raise exception 'bad_range'; end if;
  if p_from < a.effective_from or (a.effective_to is not null and p_to > a.effective_to) then raise exception 'outside_deed_dates'; end if;
  if p_to > public._a44_today() then raise exception 'bad_date'; end if;
  perform public.lock_check(p_to);
  if exists (select 1 from public.partner_settlements x where x.agreement_id in (select id from public._a44_chain(p_agr)) and x.status <> 'void' and x.period_from <= p_to and x.period_to >= p_from) then raise exception 'period_overlap'; end if;
  c := public.partner_calculate(p_agr, p_from, p_to, p_manual);
  if c ->> 'status' <> 'ok' then raise exception 'calc_incomplete'; end if;
  insert into public.partner_settlements (agreement_id, period_from, period_to, status, calc, manual_base, total_distributable, carry_out, note, client_id, created_by)
    values (p_agr, p_from, p_to, 'draft', c, p_manual, (c ->> 'total_distributable')::numeric, (c ->> 'carry_out')::numeric, left(p_note, 1000), p_client, auth.uid()) returning * into s;
  insert into public.partner_settlement_lines (settlement_id, party_id, amount, kind, funded_outside)
    select s.id, (e ->> 'party_id')::bigint, round(sum((e ->> 'amount')::numeric), 2), e ->> 'kind', coalesce((e ->> 'outside')::boolean, false)
      from jsonb_array_elements(c -> 'lines') e group by 2, 4, 5 having round(sum((e ->> 'amount')::numeric), 2) > 0;
  return to_jsonb(s);
end $$;

create or replace function public.partner_settlement_approve(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.partner_settlements;
begin
  perform public._a44_guard();
  select * into s from public.partner_settlements where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if s.status <> 'draft' then raise exception 'not_draft'; end if;
  update public.partner_settlements set status = 'approved', approved_by = auth.uid(), approved_at = now() where id = p_id returning * into s;
  return to_jsonb(s);
end $$;

create or replace function public.partner_settlement_void(p_id bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.partner_settlements;
begin
  perform public._a44_guard();
  if nullif(btrim(coalesce(p_reason, '')), '') is null then raise exception 'reason_required'; end if;
  select * into s from public.partner_settlements where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if s.status not in ('draft', 'approved') then raise exception 'cannot_void'; end if;
  if exists (select 1 from public.partner_settlement_lines where settlement_id = p_id and paid_amount > 0) then raise exception 'has_payments'; end if;
  update public.partner_settlements set status = 'void', void_reason = left(p_reason, 300), void_by = auth.uid(), void_at = now() where id = p_id returning * into s;
  return to_jsonb(s);
end $$;

create or replace function public.partner_settlement_pay(p_line bigint, p_amount numeric, p_mode text, p_date date, p_ref text, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l public.partner_settlement_lines; s public.partner_settlements; pay public.partner_settlement_payments;
begin
  perform public._a44_guard();
  if p_mode not in ('cash', 'bank', 'mobile') then raise exception 'bad_mode'; end if;
  perform public._a44_chk_money(p_amount); perform public._a44_chk_date(p_date); perform public.lock_check(p_date);
  if p_client is not null then perform public._client_lock(p_client); select * into pay from public.partner_settlement_payments where client_id = p_client; if found then return to_jsonb(pay); end if; end if;
  select * into l from public.partner_settlement_lines where id = p_line for update;
  if not found then raise exception 'not_found'; end if;
  select * into s from public.partner_settlements where id = l.settlement_id for update;
  if s.status <> 'approved' then raise exception 'not_approved'; end if;
  if p_date < s.period_from then raise exception 'bad_date'; end if;
  if l.paid_amount + round(p_amount, 2) > l.amount + 0.004 then raise exception 'overpay'; end if;
  insert into public.partner_settlement_payments (line_id, amount, paid_on, mode, ref, client_id, created_by) values (p_line, round(p_amount, 2), p_date, p_mode, nullif(btrim(p_ref), ''), p_client, auth.uid()) returning * into pay;
  update public.partner_settlement_lines set paid_amount = paid_amount + round(p_amount, 2), paid_at = p_date, pay_mode = p_mode where id = p_line;
  if not exists (select 1 from public.partner_settlement_lines where settlement_id = s.id and paid_amount < amount - 0.004) then
    update public.partner_settlements set status = 'paid' where id = s.id;
  end if;
  return to_jsonb(pay);
end $$;

-- ============================================================
-- 11. read models
-- ============================================================
create or replace function public.partner_party_statement(p_party bigint, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare pt public.partner_parties; cap jsonb; due jsonb; pays jsonb; opening numeric; closing numeric; owed numeric; tdue numeric; tpaid numeric;
begin
  perform public._a44_guard();
  if p_from is null or p_to is null or p_to < p_from then raise exception 'bad_range'; end if;
  select * into pt from public.partner_parties where id = p_party;
  if not found then raise exception 'not_found'; end if;
  select coalesce(sum(case c.kind when 'contribution' then c.amount when 'loan_in' then c.amount when 'return_of_capital' then -c.amount when 'loan_repayment' then -c.amount else 0 end), 0) into opening
    from public.partner_capital c where c.party_id = p_party and c.status = 'posted' and c.cap_date < p_from;
  select coalesce(sum(case c.kind when 'contribution' then c.amount when 'loan_in' then c.amount when 'return_of_capital' then -c.amount when 'loan_repayment' then -c.amount else 0 end), 0) into closing
    from public.partner_capital c where c.party_id = p_party and c.status = 'posted' and c.cap_date <= p_to;
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'date', c.cap_date, 'kind', c.kind, 'amount', c.amount, 'mode', c.mode, 'agreement_id', c.agreement_id, 'description', c.description, 'ref', c.ref) order by c.cap_date, c.id), '[]'::jsonb) into cap
    from public.partner_capital c where c.party_id = p_party and c.status = 'posted' and c.cap_date between p_from and p_to;
  select coalesce(jsonb_agg(jsonb_build_object('line_id', l.id, 'settlement_id', s.id, 'agreement_id', s.agreement_id, 'period_from', s.period_from, 'period_to', s.period_to, 'kind', l.kind, 'amount', l.amount, 'paid', l.paid_amount, 'status', s.status, 'outside', l.funded_outside) order by s.period_to, l.id), '[]'::jsonb) into due
    from public.partner_settlement_lines l join public.partner_settlements s on s.id = l.settlement_id
   where l.party_id = p_party and s.status in ('approved', 'paid') and s.period_to between p_from and p_to;
  select coalesce(jsonb_agg(jsonb_build_object('id', y.id, 'date', y.paid_on, 'amount', y.amount, 'mode', y.mode, 'ref', y.ref, 'line_id', y.line_id) order by y.paid_on, y.id), '[]'::jsonb) into pays
    from public.partner_settlement_payments y join public.partner_settlement_lines l on l.id = y.line_id where l.party_id = p_party and y.paid_on between p_from and p_to;
  select coalesce(sum(l.amount), 0) into tdue from public.partner_settlement_lines l join public.partner_settlements s on s.id = l.settlement_id
   where l.party_id = p_party and s.status in ('approved', 'paid') and s.period_to <= p_to;
  select coalesce(sum(y.amount), 0) into tpaid from public.partner_settlement_payments y join public.partner_settlement_lines l on l.id = y.line_id
   join public.partner_settlements s on s.id = l.settlement_id where l.party_id = p_party and s.status in ('approved', 'paid') and y.paid_on <= p_to;
  owed := tdue - tpaid;
  return jsonb_build_object('party', jsonb_build_object('id', pt.id, 'name', pt.name, 'kind', pt.kind, 'mobile', pt.mobile, 'email', pt.email, 'nid_or_reg', pt.nid_or_reg, 'address', pt.address),
    'from', p_from, 'to', p_to, 'capital_opening', opening, 'capital_movements', cap, 'capital_closing', closing,
    'drawings', (select coalesce(sum(c.amount), 0) from public.partner_capital c where c.party_id = p_party and c.status = 'posted' and c.kind = 'owner_drawing' and c.cap_date between p_from and p_to),
    'shares_due', due, 'payments', pays,
    'due_in_period', (select coalesce(sum((x ->> 'amount')::numeric), 0) from jsonb_array_elements(due) x),
    'paid_in_period', (select coalesce(sum((x ->> 'amount')::numeric), 0) from jsonb_array_elements(pays) x),
    'due_to_date', tdue, 'paid_to_date', tpaid, 'balance_owed', owed);
end $$;

create or replace function public.partner_overview() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out jsonb;
begin
  perform public._a44_guard();
  select coalesce(jsonb_agg(x order by (x ->> 'id')::bigint), '[]'::jsonb) into out from (
    select jsonb_build_object('id', v.id, 'name_bn', v.name_bn, 'name_en', v.name_en, 'scope', v.scope, 'model', v.model, 'status', v.status, 'location_id', v.location_id,
      'agreements', (select count(*) from public.partner_agreements a where a.venture_id = v.id and a.status = 'active'),
      'drafts', (select count(*) from public.partner_agreements a where a.venture_id = v.id and a.status = 'draft'),
      'capital', (select coalesce(sum(case c.kind when 'contribution' then c.amount when 'loan_in' then c.amount when 'return_of_capital' then -c.amount when 'loan_repayment' then -c.amount else 0 end), 0)
                    from public.partner_capital c join public.partner_agreements a on a.id = c.agreement_id where a.venture_id = v.id and c.status = 'posted'),
      'next_due', (select min(coalesce((select max(s.period_to) + 1 from public.partner_settlements s where s.agreement_id in (select id from public._a44_chain(a.id)) and s.status <> 'void'), a.effective_from))
                     from public.partner_agreements a where a.venture_id = v.id and a.status = 'active'),
      'owed', (select coalesce(sum(l.amount - l.paid_amount), 0) from public.partner_settlement_lines l join public.partner_settlements s on s.id = l.settlement_id
                 join public.partner_agreements a on a.id = s.agreement_id where a.venture_id = v.id and s.status = 'approved')) as x
    from public.partner_ventures v) q;
  return jsonb_build_object('ventures', out, 'owed_total', (select coalesce(sum(l.amount - l.paid_amount), 0) from public.partner_settlement_lines l join public.partner_settlements s on s.id = l.settlement_id where s.status = 'approved'),
    'capital_total', (select coalesce(sum(case c.kind when 'contribution' then c.amount when 'loan_in' then c.amount when 'return_of_capital' then -c.amount when 'loan_repayment' then -c.amount else 0 end), 0) from public.partner_capital c where c.status = 'posted'));
end $$;

-- ============================================================
-- 12. example templates (EXAMPLE only - inactive, numbers are placeholders the owner must replace)
-- ============================================================
insert into public.partner_templates (code, name_bn, name_en, description_bn, description_en, model, clauses, roles, rules, is_example, active)
select * from (values
 ('franchise', 'উদাহরণ - ফ্র্যাঞ্চাইজ', 'Franchise (EXAMPLE)', 'বিক্রির উপর রয়্যালটি + মাসিক ফি; বাকি লাভ ফ্র্যাঞ্চাইজির। সংখ্যাগুলো উদাহরণ - বদলান।', 'Royalty on net sales + a monthly fee; the rest of the profit stays with the franchisee. Numbers are EXAMPLES - change them.', 'franchise',
  '[{"no":1,"title_bn":"চুক্তির উদ্দেশ্য","title_en":"Purpose","text_bn":"(এখানে লিখুন)","text_en":"(write here)"},{"no":2,"title_bn":"রয়্যালটি ও ফি","title_en":"Royalty and fee","text_bn":"(এখানে লিখুন)","text_en":"(write here)"}]'::jsonb,
  '["owner","franchisee"]'::jsonb,
  '[{"name":"Base: profit before fees","kind":"base","config":{"base":"net_profit_before_fees"}},
    {"name":"Royalty on net sales (EXAMPLE 5%)","kind":"royalty","config":{"role":"owner","percent":5,"base":"net_sales"}},
    {"name":"Monthly fee (EXAMPLE 10000)","kind":"management_fee","config":{"role":"owner","fixed":10000,"per":"month"}},
    {"name":"Rest to franchisee","kind":"split","config":{"shares":[{"role":"franchisee","percent":100}]}}]'::jsonb, true, false),
 ('investor_payback', 'উদাহরণ - বিনিয়োগকারীর পুঁজি ফেরত', 'Investor payback (EXAMPLE)', 'পুঁজি ফেরত না আসা পর্যন্ত লাভের একটি অংশ বিনিয়োগকারীর, তারপর কম অংশ। সংখ্যা উদাহরণ।', 'A share of profit goes to the investor until the capital is paid back, then a smaller share. Numbers are EXAMPLES.', 'funded',
  '[{"no":1,"title_bn":"বিনিয়োগ","title_en":"Investment","text_bn":"(এখানে লিখুন)","text_en":"(write here)"},{"no":2,"title_bn":"পুঁজি ফেরত","title_en":"Payback","text_bn":"(এখানে লিখুন)","text_en":"(write here)"}]'::jsonb,
  '["owner","investor"]'::jsonb,
  '[{"name":"Base: net profit before fees","kind":"base","config":{"base":"net_profit_before_fees"}},
    {"name":"Carry earlier losses","kind":"loss_carry_forward","config":{}},
    {"name":"Investor payback (EXAMPLE 50% then 20%)","kind":"payback","config":{"role":"investor","percent":50,"then_percent":20}},
    {"name":"Rest to owner","kind":"split","config":{"shares":[{"role":"owner","percent":100}]}}]'::jsonb, true, false),
 ('partnership_5050', 'উদাহরণ - ৫০/৫০ অংশীদারি', '50/50 partnership (EXAMPLE)', 'ক্ষতি পরের মাসে টেনে নিয়ে বাকি লাভ সমান ভাগ। ভাগের হার উদাহরণ।', 'Losses are carried forward; the rest of the profit is split equally. The split is an EXAMPLE.', 'partnership',
  '[{"no":1,"title_bn":"মূলধন ও দায়িত্ব","title_en":"Capital and duties","text_bn":"(এখানে লিখুন)","text_en":"(write here)"}]'::jsonb,
  '["owner","partner"]'::jsonb,
  '[{"name":"Base: net profit before fees","kind":"base","config":{"base":"net_profit_before_fees"}},
    {"name":"Carry earlier losses","kind":"loss_carry_forward","config":{}},
    {"name":"Split (EXAMPLE 50/50)","kind":"split","config":{"shares":[{"role":"owner","percent":50},{"role":"partner","percent":50}]}}]'::jsonb, true, false),
 ('fixed_return_loan', 'উদাহরণ - নির্দিষ্ট রিটার্নের ঋণ', 'Fixed-return loan (EXAMPLE)', 'ঋণদাতা পুঁজির উপর বছরে নির্দিষ্ট % পান (ঘাটতি পরে মেটে); বাকি লাভ মালিকের। হার উদাহরণ।', 'The lender gets a fixed yearly % on the loan (a shortfall is caught up later); the rest of the profit is the owner''s. The rate is an EXAMPLE.', 'loan',
  '[{"no":1,"title_bn":"ঋণ ও সুদ/রিটার্ন","title_en":"Loan and return","text_bn":"(এখানে লিখুন)","text_en":"(write here)"}]'::jsonb,
  '["owner","lender"]'::jsonb,
  '[{"name":"Base: net profit before fees","kind":"base","config":{"base":"net_profit_before_fees"}},
    {"name":"Lender return (EXAMPLE 12% a year, catch-up)","kind":"priority_return","config":{"role":"lender","percent_per_year":12,"catch_up":true}},
    {"name":"Rest to owner","kind":"split","config":{"shares":[{"role":"owner","percent":100}]}}]'::jsonb, true, false)
) v(code, name_bn, name_en, description_bn, description_en, model, clauses, roles, rules, is_example, active)
where not exists (select 1 from public.partner_templates t where t.code = v.code);

-- ============================================================
-- 13. grants
-- ============================================================
revoke all on function public._a44_guard(), public._a44_n(jsonb), public._a44_today(), public._a44_chk_date(date), public._a44_chk_money(numeric), public._a44_chain(bigint),
  public._a44_months(date, date), public._a44_round(numeric, numeric, text), public._a44_ref(bigint, jsonb), public._a44_need(bigint, jsonb, text),
  public._a44_distribute(bigint, numeric, jsonb, numeric, text, text), public._a44_party_total(jsonb, bigint, boolean), public._a44_cap(bigint, bigint, date),
  public._a44_capdays(bigint, bigint, date, date), public._a44_step_hist(bigint, date, text), public._a44_vref(jsonb), public._a44_vshares(jsonb), public._a44_clauses_ok(jsonb),
  public._a44_check_ready(bigint), public._a44_agr_guard(), public._a44_child_guard(), public._a44_ro(), public._a44_cap_guard(), public._a44_set_guard(), public._a44_line_guard()
  from public, anon, authenticated;
revoke all on function public.partner_rule_validate(text, jsonb), public.partner_party_save(bigint, text, text, text, text, text, text, text, text, boolean, uuid),
  public.partner_venture_save(bigint, text, text, text, int, text, date, date, text, text, uuid), public.partner_agreement_save(bigint, bigint, text, date, date, jsonb, text, uuid),
  public.partner_agreement_party_set(bigint, bigint, text, numeric, text, boolean), public.partner_rule_save(bigint, int, text, text, jsonb, boolean), public.partner_rules_reorder(bigint, jsonb),
  public.partner_agreement_activate(bigint, boolean), public.partner_agreement_amend(bigint, uuid), public.partner_agreement_close(bigint, text, date),
  public.partner_agreement_from_template(bigint, text, text, uuid), public.partner_capital_add(bigint, bigint, text, numeric, date, text, text, text, uuid), public.partner_capital_void(bigint, text),
  public.partner_capital_balances(bigint, date), public.partner_calculate(bigint, date, date, jsonb), public.partner_settlement_save(bigint, date, date, jsonb, text, uuid),
  public.partner_settlement_approve(bigint), public.partner_settlement_void(bigint, text), public.partner_settlement_pay(bigint, numeric, text, date, text, uuid),
  public.partner_party_statement(bigint, date, date), public.partner_overview() from public, anon;
grant execute on function public.partner_rule_validate(text, jsonb), public.partner_party_save(bigint, text, text, text, text, text, text, text, text, boolean, uuid),
  public.partner_venture_save(bigint, text, text, text, int, text, date, date, text, text, uuid), public.partner_agreement_save(bigint, bigint, text, date, date, jsonb, text, uuid),
  public.partner_agreement_party_set(bigint, bigint, text, numeric, text, boolean), public.partner_rule_save(bigint, int, text, text, jsonb, boolean), public.partner_rules_reorder(bigint, jsonb),
  public.partner_agreement_activate(bigint, boolean), public.partner_agreement_amend(bigint, uuid), public.partner_agreement_close(bigint, text, date),
  public.partner_agreement_from_template(bigint, text, text, uuid), public.partner_capital_add(bigint, bigint, text, numeric, date, text, text, text, uuid), public.partner_capital_void(bigint, text),
  public.partner_capital_balances(bigint, date), public.partner_calculate(bigint, date, date, jsonb), public.partner_settlement_save(bigint, date, date, jsonb, text, uuid),
  public.partner_settlement_approve(bigint), public.partner_settlement_void(bigint, text), public.partner_settlement_pay(bigint, numeric, text, date, text, uuid),
  public.partner_party_statement(bigint, date, date), public.partner_overview() to authenticated;
