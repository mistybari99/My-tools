-- ============================================================================
-- phase83 (BUILDER D): G9 separate wallets (bKash / Nagad / Rocket / others) and G10 production materials.
-- Additive; paste-twice safe. Own tag bos83. Needs phase40 (books) and phase19/73/74 (recipes). No existing function is replaced.
--
-- G9  - d_wallets: one chart account per wallet (1131 bKash, 1132 Nagad, 1133 Rocket, 1134 Upay; more can be added by d_wallet_add)
--       - a wallet balance per wallet (register balance = opening + wallet sales/collections - wallet supplier payments
--         + wallet moves - wallet fees; journal balance = the wallet's chart account)
--       - d_wallet_fees: the fee the wallet company takes, kept as its OWN expense (account 5815, mapping key wallet_fee)
--       - d_wallet_moves: cash-in / cash-out / bank / wallet-to-wallet transfers
--       - d_wallet_checks: the phone balance typed first (blind, form 10-3 rule), then the book figure and the difference are shown
--       - _d_acct_docs(date): the journal sources of this phase, in the exact column shape of _acct_docs, for the integrator to plug in
--         (a payment that names a wallet is moved from the generic mobile account 1130 to the wallet account by a separate balanced
--          entry; an unknown wallet text stays on 1130, so nothing is lost)
-- G10 - d_material_roles (milk, chhana, packing), d_item_roles (which item is which role), d_product_role_req (which product needs which role)
--       - a recipe or a production run that lacks a required role is warned or refused (setting d_recipe_materials_mode, default off)
--       - d_recipe_cost_gaps: ingredients and packaging without a cost
--       - d_material_unit_cost: cost of a material by the chosen method (setting d_material_cost_method, default average_purchase = today)
--       - d_production_cost_breakdown: what a production run really consumed (milk / chhana / packing / other) + conversion
--       NO item is created here. Item master entries are the owner's (import tooling d_item_roles_import maps existing items by code).
--
-- Owner decisions are SETTINGS (rules), safe defaults:
--   d_wallet_fee_treatment   separate_expense (default) | not_posted
--   d_wallet_negative_mode   refuse (default) | warn
--   d_recipe_materials_mode  off (default) | warn | block
--   d_material_cost_method   average_purchase (default) | last_purchase | fixed_price
-- ============================================================================

do $guard$ begin
  if to_regclass('public.coa_accounts') is null or to_regclass('public.journal_entries') is null then raise exception 'phase83 needs phase40 (books) first'; end if;
  if to_regclass('public.recipes') is null or to_regclass('public.production_runs') is null then raise exception 'phase83 needs the recipe phases (19, 73, 74) first'; end if;
end $guard$;

-- ---------- settings (owner decisions; defaults keep today''s behaviour) ----------
insert into public.rules (key, module, kind, default_value, choices, label_bn, label_mix, label_en, hint_en, sort) values
 ('d_wallet_fee_treatment', 'books', 'choice', '"separate_expense"', '["separate_expense","not_posted"]',
  'ওয়ালেটের ফি: আলাদা খরচ হিসেবে খতিয়ানে / খতিয়ানে নয়', 'Wallet fee: আলাদা expense হিসেবে books এ / books এ না',
  'Wallet fee treatment: booked as its own expense (Dr Wallet fees, Cr the wallet), or kept in the register only',
  'separate_expense = every fee is booked as expense 5815 and lowers the wallet balance. not_posted = fees are listed in the wallet register but not booked. Owner decision (question Q1).', 830),
 ('d_wallet_negative_mode', 'books', 'choice', '"refuse"', '["refuse","warn"]',
  'ওয়ালেট ব্যালান্স ঋণাত্মক হলে: আটকানো / সতর্কতা', 'Wallet balance negative হলে: refuse / warn',
  'When a fee or a move would make a wallet balance negative: refuse it, or warn',
  'refuse = the fee or move is refused (wallet_negative). warn = it is saved and the answer carries a warning.', 831),
 ('d_recipe_materials_mode', 'stock', 'choice', '"off"', '["off","warn","block"]',
  'রেসিপিতে প্রয়োজনীয় কাঁচামাল (দুধ, ছানা, প্যাকিং) না থাকলে: বন্ধ / সতর্কতা / আটকানো', 'Recipe এ required material (দুধ, ছানা, packing) না থাকলে: off / warn / block',
  'When a recipe lacks a material its product requires (milk, chhana, packing): off, warn, or block activation and production',
  'off = today''s behaviour. warn = production is saved with a yellow stock exception. block = recipe activation and production are refused (recipe_missing_material).', 832),
 ('d_material_cost_method', 'stock', 'choice', '"average_purchase"', '["average_purchase","last_purchase","fixed_price"]',
  'কাঁচামালের দাম ধরার পদ্ধতি: গড় কেনা দাম / শেষ কেনা দাম / নির্ধারিত দাম', 'Material cost method: average purchase / last purchase / fixed price',
  'How a material''s unit cost is taken: weighted average of purchases, last purchase bill, or an owner-fixed price',
  'Used by d_material_unit_cost and the cost-gap report. average_purchase = what the stock already uses. fixed_price needs a row in d_material_fixed_price. Owner decision (question Q5).', 833)
on conflict (key) do nothing;

-- ---------- chart: wallet fee expense 5815 + mapping ----------
insert into public.coa_accounts (code, name_bn, name_en, type, normal_side, is_group, is_system, sort)
values ('5815', 'ওয়ালেট ফি', 'Wallet fees', 'expense', 'debit', false, true, 409)
on conflict (code) do nothing;
insert into public.acct_mappings (key, account_id, label_bn, label_en)
select 'wallet_fee', a.id, 'ওয়ালেট ফি (বিকাশ/নগদ/রকেট)', 'Wallet fees (bKash / Nagad / Rocket)' from public.coa_accounts a where a.code = '5815'
on conflict (key) do nothing;

-- ---------- tables ----------
create table if not exists public.d_wallets (
  id serial primary key,
  code text not null unique check (code ~ '^[a-z0-9]{2,30}$'),
  name_bn text not null check (length(btrim(name_bn)) between 1 and 80),
  name_en text not null check (length(btrim(name_en)) between 1 and 80),
  aliases text[] not null default '{}',                       -- lower-case spellings found in the free-text wallet column
  coa_account_id bigint not null references public.coa_accounts(id),
  opening_amount numeric not null default 0 check (opening_amount >= 0 and opening_amount <= 1000000000000),
  opening_date date,
  active boolean not null default true,
  sort int not null default 100,
  created_at timestamptz not null default now(),
  created_by uuid
);

create table if not exists public.d_wallet_fees (
  id bigserial primary key,
  wallet_id int not null references public.d_wallets(id),
  location_id int references public.locations(id),
  fee_date date not null,
  amount numeric not null check (amount > 0 and amount <= 1000000000),
  kind text not null default 'other' check (kind in ('cash_out', 'send_money', 'merchant', 'payment', 'other')),
  ref text check (ref is null or length(ref) <= 60),
  note text check (note is null or length(note) <= 200),
  voided boolean not null default false,
  void_note text, void_by uuid, void_at timestamptz,
  client_id uuid unique,
  created_by uuid, created_staff text, created_at timestamptz not null default now()
);
create index if not exists d_wallet_fees_w on public.d_wallet_fees (wallet_id, fee_date);

create table if not exists public.d_wallet_moves (
  id bigserial primary key,
  wallet_id int not null references public.d_wallets(id),
  location_id int references public.locations(id),
  move_date date not null,
  direction text not null check (direction in ('in', 'out')),            -- in = money comes INTO wallet_id
  counter text not null check (counter in ('cash', 'bank', 'wallet')),
  counter_wallet_id int references public.d_wallets(id),
  amount numeric not null check (amount > 0 and amount <= 1000000000),
  ref text check (ref is null or length(ref) <= 60),
  note text check (note is null or length(note) <= 200),
  voided boolean not null default false,
  void_note text, void_by uuid, void_at timestamptz,
  client_id uuid unique,
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  check ((counter = 'wallet') = (counter_wallet_id is not null)),
  check (counter_wallet_id is distinct from wallet_id)
);
create index if not exists d_wallet_moves_w on public.d_wallet_moves (wallet_id, move_date);

create table if not exists public.d_wallet_checks (
  id bigserial primary key,
  wallet_id int not null references public.d_wallets(id),
  location_id int references public.locations(id),
  check_date date not null,
  phone_balance numeric not null check (phone_balance >= 0 and phone_balance <= 1000000000000),   -- typed FIRST by the counter
  book_register numeric not null,                                                                    -- frozen when saved
  book_journal numeric not null,
  diff numeric not null,                                                                             -- phone - book_register, always written, even 0
  status text not null check (status in ('matched', 'difference', 'explained')),
  reason text check (reason is null or length(reason) <= 300),
  reason_by uuid, reason_at timestamptz,
  client_id uuid unique,
  counted_by uuid, counted_staff text, counted_at timestamptz not null default now()
);
create index if not exists d_wallet_checks_w on public.d_wallet_checks (wallet_id, check_date);

-- G10
create table if not exists public.d_material_roles (
  code text primary key check (code ~ '^[a-z0-9_]{2,30}$'),
  name_bn text not null, name_en text not null,
  kind text not null check (kind in ('raw', 'packaging')),
  active boolean not null default true, sort int not null default 100
);
insert into public.d_material_roles (code, name_bn, name_en, kind, sort) values
  ('milk', 'দুধ', 'Milk', 'raw', 10), ('chhana', 'ছানা', 'Chhana (cottage cheese)', 'raw', 20), ('packing', 'প্যাকিং', 'Packing', 'packaging', 30)
on conflict (code) do nothing;

create table if not exists public.d_item_roles (
  item_id uuid not null references public.items(id),
  role_code text not null references public.d_material_roles(code),
  active boolean not null default true,
  created_at timestamptz not null default now(), created_by uuid,
  primary key (item_id, role_code)
);
create table if not exists public.d_product_role_req (
  product_item_id uuid not null references public.items(id),
  role_code text not null references public.d_material_roles(code),
  required boolean not null default true,
  updated_at timestamptz not null default now(), updated_by uuid,
  primary key (product_item_id, role_code)
);
create table if not exists public.d_material_fixed_price (
  id bigserial primary key,
  item_id uuid not null references public.items(id),
  price numeric not null check (price > 0 and price <= 1000000),     -- per base unit of the item
  from_date date not null,
  note text check (note is null or length(note) <= 200),
  created_at timestamptz not null default now(), created_by uuid
);

-- no hard delete, audit, RLS on every table
do $t$ declare t text; begin
  foreach t in array array['d_wallets', 'd_wallet_fees', 'd_wallet_moves', 'd_wallet_checks', 'd_material_roles', 'd_item_roles', 'd_product_role_req', 'd_material_fixed_price'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_nodel', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_nodel', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
  end loop;
  foreach t in array array['d_wallets', 'd_wallet_fees', 'd_wallet_moves', 'd_wallet_checks'] loop
    execute format('drop trigger if exists %I on public.%I', 'audit_' || t, t);
    execute format('create trigger %I after insert or update on public.%I for each row execute function public.log_change(%L)', 'audit_' || t, t, 'id');
  end loop;
end $t$;

-- ---------- permission helpers ----------
create or replace function public._d_view_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public._acct_view() or public.can_do('10-3', 'view') or public.can_do('10-3', 'enter'));
$$;
create or replace function public._d_cash_ok(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public._acct_manage() or public.can_do('10-3', 'enter')) and (p_loc is null or public.can_loc(p_loc));
$$;

do $p$ declare t text; begin
  foreach t in array array['d_wallets', 'd_wallet_fees', 'd_wallet_moves', 'd_wallet_checks'] loop
    execute format('create policy %I on public.%I for select to authenticated using (public._d_view_ok())', t || '_read', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
  foreach t in array array['d_material_roles', 'd_item_roles', 'd_product_role_req'] loop
    execute format('create policy %I on public.%I for select to authenticated using (public.is_active())', t || '_read', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
  execute 'create policy d_material_fixed_price_read on public.d_material_fixed_price for select to authenticated using (public._recipe_cost_ok())';
  execute 'grant select on public.d_material_fixed_price to authenticated';
end $p$;

-- ---------- wallet helpers ----------
create or replace function public._d_wallet_of(p_text text) returns int language sql stable security definer set search_path = public as $$
  select w.id from public.d_wallets w
   where nullif(btrim(p_text), '') is not null
     and (lower(btrim(p_text)) in (w.code, lower(w.name_en), lower(w.name_bn)) or lower(btrim(p_text)) = any (w.aliases))
   order by w.active desc, w.id limit 1;
$$;

-- creates the wallet + its chart account + its mapping key (internal, no permission check)
create or replace function public._d_wallet_create(p_code text, p_bn text, p_en text, p_aliases text[], p_opening numeric, p_odate date, p_sort int, p_by uuid) returns int
language plpgsql security definer set search_path = public as $$
declare ac text; aid bigint; wid int; par bigint; n int; al text[] := '{}'; x text;
begin
  if p_code is null or p_code !~ '^[a-z0-9]{2,30}$' then raise exception 'bad_code'; end if;
  select id into wid from public.d_wallets where code = p_code;
  if wid is not null then return wid; end if;
  select min(c) into ac from (select (1130 + g)::text c from generate_series(1, 9) g) z where not exists (select 1 from public.coa_accounts a where a.code = z.c);
  if ac is null then raise exception 'no_free_account_code'; end if;
  select id into par from public.coa_accounts where code = '1100';
  insert into public.coa_accounts (code, name_bn, name_en, type, normal_side, parent_id, is_group, is_system, sort)
    values (ac, left(btrim(p_bn), 120), left(btrim(p_en), 120), 'asset', 'debit', par, false, true, 14) returning id into aid;
  foreach x in array coalesce(p_aliases, '{}') loop
    if nullif(btrim(x), '') is not null then al := al || lower(left(btrim(x), 40)); end if;
  end loop;
  insert into public.d_wallets (code, name_bn, name_en, aliases, coa_account_id, opening_amount, opening_date, sort, created_by)
    values (p_code, btrim(p_bn), btrim(p_en), al, aid, coalesce(p_opening, 0), p_odate, coalesce(p_sort, 100), p_by) returning id into wid;
  insert into public.acct_mappings (key, account_id, label_bn, label_en) values ('d_wallet_' || p_code, aid, btrim(p_bn) || ' ওয়ালেট', btrim(p_en) || ' wallet')
    on conflict (key) do nothing;
  return wid;
end $$;

-- the wallets that exist today in the option list (structure only, zero opening)
do $seed$ begin
  perform public._d_wallet_create('bkash', 'বিকাশ', 'bKash', array['bkash', 'b-kash', 'বিকাশ'], 0, null, 10, null);
  perform public._d_wallet_create('nagad', 'নগদ', 'Nagad', array['nagad', 'নগদ', 'nagad (নগদ)'], 0, null, 20, null);
  perform public._d_wallet_create('rocket', 'রকেট', 'Rocket', array['rocket', 'রকেট'], 0, null, 30, null);
  perform public._d_wallet_create('upay', 'উপায়', 'Upay', array['upay', 'উপায়'], 0, null, 40, null);
end $seed$;

-- every movement of one wallet, signed (+ into the wallet)
create or replace function public._d_wallet_flows(p_wallet int) returns table(d date, loc int, kind text, amt numeric, src text, src_id text)
language sql stable security definer set search_path = public as $$
  select (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, case p.kind when 'collection' then 'collection' else 'sale' end, p.amount, 'sale_payment'::text, p.id::text
    from public.sale_payments p left join public.sales s on s.id = p.sale_id
   where p.mode = 'mobile' and not p.voided and p.kind in ('sale', 'collection') and (p.sale_id is null or s.status = 'done') and public._d_wallet_of(p.wallet) = p_wallet
  union all
  select (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, 'supplier_payment', -p.amount, 'supplier_payment', p.id::text
    from public.supplier_payments p where p.mode = 'mobile' and not p.voided and public._d_wallet_of(p.wallet) = p_wallet
  union all
  select f.fee_date, f.location_id, 'fee', -f.amount, 'd_wallet_fee', f.id::text from public.d_wallet_fees f where f.wallet_id = p_wallet and not f.voided
  union all
  select m.move_date, m.location_id, 'move_' || m.counter, case m.direction when 'in' then m.amount else -m.amount end, 'd_wallet_move', m.id::text
    from public.d_wallet_moves m where m.wallet_id = p_wallet and not m.voided
  union all
  select m.move_date, m.location_id, 'move_wallet', case m.direction when 'in' then -m.amount else m.amount end, 'd_wallet_move', m.id::text
    from public.d_wallet_moves m where m.counter_wallet_id = p_wallet and not m.voided;
$$;

create or replace function public._d_wallet_book(p_wallet int, p_asof date) returns numeric language sql stable security definer set search_path = public as $$
  select case when w.opening_date is null or w.opening_date <= p_asof then w.opening_amount else 0 end
         + coalesce((select sum(f.amt) from public._d_wallet_flows(w.id) f where f.d <= p_asof and (w.opening_date is null or f.d >= w.opening_date)), 0)
    from public.d_wallets w where w.id = p_wallet;
$$;

create or replace function public._d_wallet_journal(p_wallet int, p_asof date) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(l.debit - l.credit), 0) from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
   join public.d_wallets w on w.coa_account_id = l.account_id where w.id = p_wallet and e.entry_date <= p_asof;
$$;

-- refuse (or warn about) a negative wallet balance, now and at the date of the entry
create or replace function public._d_neg_check(p_wallet int, p_date date, p_amount numeric) returns boolean
language plpgsql security definer set search_path = public as $$
declare b_at numeric; b_all numeric; warn boolean := false;
begin
  b_at := public._d_wallet_book(p_wallet, p_date); b_all := public._d_wallet_book(p_wallet, date '9999-12-31');
  if coalesce(b_at, 0) - p_amount < 0 or coalesce(b_all, 0) - p_amount < 0 then
    if coalesce(public.rule_txt('d_wallet_negative_mode'), 'refuse') = 'refuse' then
      raise exception 'wallet_negative' using detail = 'balance at date ' || coalesce(b_at, 0)::text || ', balance now ' || coalesce(b_all, 0)::text || ', amount ' || p_amount::text;
    end if;
    warn := true;
  end if;
  return warn;
end $$;

-- ---------- journal sources of this phase (same columns as _acct_docs; the integrator plugs this in) ----------
create or replace function public._d_acct_docs(p_start date)
returns table(source_type text, source_id text, entry_date date, location_id integer, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
language plpgsql stable security definer set search_path = public as $$
declare treat text := coalesce(public.rule_txt('d_wallet_fee_treatment'), 'separate_expense');
begin
  -- a sale or collection paid into a named wallet: move it from the generic mobile account to the wallet account
  return query
  select 'd_wallet_split'::text, 'sp:' || p.id::text, (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, ('Wallet ' || w.code || ' payment received')::text, null::text,
    (not p.voided and (p.sale_id is null or s.status = 'done')), public._acct_today(), null::text, null::text,
    case when not p.voided and (p.sale_id is null or s.status = 'done') then jsonb_build_array(jsonb_build_object('a', 'd_wallet_' || w.code, 'd', p.amount), jsonb_build_object('a', 'pay_mobile', 'c', p.amount)) end
  from public.sale_payments p left join public.sales s on s.id = p.sale_id join public.d_wallets w on w.id = public._d_wallet_of(p.wallet)
  where p.mode = 'mobile' and p.kind in ('sale', 'collection') and p.amount > 0 and (p.paid_at at time zone 'Asia/Dhaka')::date >= p_start
    and public._acct_need('d_wallet_split', 'sp:' || p.id::text, (not p.voided and (p.sale_id is null or s.status = 'done')));
  -- a supplier payment from a named wallet
  return query
  select 'd_wallet_split'::text, 'sup:' || p.id::text, (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, ('Wallet ' || w.code || ' supplier payment')::text, null::text,
    not p.voided, public._acct_today(), null::text, null::text,
    case when not p.voided then jsonb_build_array(jsonb_build_object('a', 'pay_mobile', 'd', p.amount), jsonb_build_object('a', 'd_wallet_' || w.code, 'c', p.amount)) end
  from public.supplier_payments p join public.d_wallets w on w.id = public._d_wallet_of(p.wallet)
  where p.mode = 'mobile' and p.amount > 0 and (p.paid_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('d_wallet_split', 'sup:' || p.id::text, not p.voided);
  -- wallet fees: Dr Wallet fees (5815), Cr the wallet
  return query
  select 'd_wallet_fee'::text, f.id::text, f.fee_date, f.location_id, ('Wallet fee ' || w.code)::text, f.kind, (not f.voided and treat = 'separate_expense'), coalesce((f.void_at at time zone 'Asia/Dhaka')::date, public._acct_today()),
    null::text, null::text,
    case when not f.voided and treat = 'separate_expense' then jsonb_build_array(jsonb_build_object('a', 'wallet_fee', 'd', f.amount), jsonb_build_object('a', 'd_wallet_' || w.code, 'c', f.amount)) end
  from public.d_wallet_fees f join public.d_wallets w on w.id = f.wallet_id
  where f.fee_date >= p_start and public._acct_need('d_wallet_fee', f.id::text, (not f.voided and treat = 'separate_expense'));
  -- wallet moves: cash / bank / other wallet on the other side
  return query
  select 'd_wallet_move'::text, m.id::text, m.move_date, m.location_id, ('Wallet ' || w.code || ' ' || m.direction || ' ' || m.counter)::text, m.counter, not m.voided,
    coalesce((m.void_at at time zone 'Asia/Dhaka')::date, public._acct_today()), null::text, null::text,
    case when not m.voided then jsonb_build_array(
      jsonb_build_object('a', case m.direction when 'in' then 'd_wallet_' || w.code else case m.counter when 'cash' then 'pay_cash' when 'bank' then 'pay_bank' else 'd_wallet_' || w2.code end end, 'd', m.amount),
      jsonb_build_object('a', case m.direction when 'out' then 'd_wallet_' || w.code else case m.counter when 'cash' then 'pay_cash' when 'bank' then 'pay_bank' else 'd_wallet_' || w2.code end end, 'c', m.amount)) end
  from public.d_wallet_moves m join public.d_wallets w on w.id = m.wallet_id left join public.d_wallets w2 on w2.id = m.counter_wallet_id
  where m.move_date >= p_start and public._acct_need('d_wallet_move', m.id::text, not m.voided);
end $$;

-- the wallet fee as an expense for the P&L and the day book (integrator hooks; same shapes as the existing readers)
create or replace function public._d_wallet_fee_rows(p_from date, p_to date, p_locs int[]) returns table(m date, loc int, amount numeric)
language sql stable security definer set search_path = public as $$
  select date_trunc('month', f.fee_date)::date, f.location_id, f.amount from public.d_wallet_fees f
   where not f.voided and f.fee_date between p_from and p_to and (p_locs is null or f.location_id = any (p_locs))
     and coalesce(public.rule_txt('d_wallet_fee_treatment'), 'separate_expense') = 'separate_expense';
$$;
create or replace function public._d_daybook_rows(p_locs int[], p_from date, p_to date)
returns table(loc integer, d date, dir text, mode text, typ text, amount numeric, ref text, txt text, who text, at timestamp with time zone, src text, src_id text, internal boolean, sensitive boolean)
language sql stable security definer set search_path = public as $$
  select f.location_id, f.fee_date, 'out'::text, 'mobile'::text, 'wallet_fee'::text, f.amount, f.ref, nullif(btrim(concat_ws(' · ', w.name_en, f.kind, f.note)), ''), f.created_staff, f.created_at,
         'd_wallet_fee'::text, f.id::text, false, false
    from public.d_wallet_fees f join public.d_wallets w on w.id = f.wallet_id
   where not f.voided and f.location_id = any (p_locs) and f.fee_date between p_from and p_to
     and coalesce(public.rule_txt('d_wallet_fee_treatment'), 'separate_expense') = 'separate_expense';
$$;

-- ---------- wallet API ----------
create or replace function public.d_wallet_add(p_code text, p_name_bn text, p_name_en text, p_aliases text[] default '{}', p_opening numeric default 0, p_opening_date date default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare wid int; w public.d_wallets;
begin
  if not (public._acct_manage() or public.is_owner()) then raise exception 'not allowed'; end if;
  if p_name_bn is null or length(btrim(p_name_bn)) = 0 or p_name_en is null or length(btrim(p_name_en)) = 0 then raise exception 'name_required'; end if;
  if exists (select 1 from public.d_wallets where code = p_code) then raise exception 'code_taken'; end if;
  if coalesce(p_opening, 0) < 0 then raise exception 'bad_amount'; end if;
  wid := public._d_wallet_create(p_code, p_name_bn, p_name_en, p_aliases, coalesce(p_opening, 0), p_opening_date, 100, auth.uid());
  select * into w from public.d_wallets where id = wid;
  return jsonb_build_object('id', w.id, 'code', w.code, 'account_id', w.coa_account_id);
end $$;

create or replace function public.d_wallet_update(p_wallet int, p_name_bn text, p_name_en text, p_aliases text[], p_active boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare w public.d_wallets; al text[] := '{}'; x text;
begin
  if not (public._acct_manage() or public.is_owner()) then raise exception 'not allowed'; end if;
  select * into w from public.d_wallets where id = p_wallet for update;
  if not found then raise exception 'not found'; end if;
  foreach x in array coalesce(p_aliases, w.aliases) loop if nullif(btrim(x), '') is not null then al := al || lower(left(btrim(x), 40)); end if; end loop;
  if p_active is false and abs(public._d_wallet_book(w.id, date '9999-12-31')) > 0.004 then raise exception 'wallet_not_empty'; end if;
  update public.d_wallets set name_bn = coalesce(nullif(btrim(p_name_bn), ''), name_bn), name_en = coalesce(nullif(btrim(p_name_en), ''), name_en), aliases = al, active = coalesce(p_active, active) where id = w.id;
  return jsonb_build_object('id', w.id);
end $$;

-- opening of one wallet: typed here (register) - the book journal gets it through the opening screen (G3) on the wallet's account
create or replace function public.d_wallet_opening_set(p_wallet int, p_amount numeric, p_date date) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not (public._acct_manage() or public.is_owner()) then raise exception 'not allowed'; end if;
  if p_amount is null or p_amount < 0 or p_amount > 1000000000000 or p_date is null then raise exception 'bad_amount'; end if;
  if exists (select 1 from public.d_wallet_checks where wallet_id = p_wallet) then raise exception 'opening_locked_after_check'; end if;
  update public.d_wallets set opening_amount = round(p_amount, 2), opening_date = p_date where id = p_wallet;
  if not found then raise exception 'not found'; end if;
  return jsonb_build_object('wallet', p_wallet, 'opening', round(p_amount, 2), 'date', p_date);
end $$;

create or replace function public.d_wallet_fee_add(p_wallet int, p_loc int, p_date date, p_amount numeric, p_kind text default 'other', p_ref text default null, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare w public.d_wallets; f public.d_wallet_fees; sid text; amt numeric := round(p_amount, 2); warn boolean;
begin
  if not public._d_cash_ok(p_loc) then raise exception 'not allowed'; end if;
  if amt is null or amt <= 0 or amt > 1000000000 then raise exception 'bad_amount'; end if;
  if p_date is null or p_date > public._acct_today() + 1 then raise exception 'bad_date'; end if;
  if p_kind is null or p_kind not in ('cash_out', 'send_money', 'merchant', 'payment', 'other') then raise exception 'bad_kind'; end if;
  perform public.lock_check(p_date);
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into f from public.d_wallet_fees where client_id = p_client;
    if found then if f.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if; return jsonb_build_object('dup', true, 'id', f.id); end if;
  end if;
  select * into w from public.d_wallets where id = p_wallet for update;
  if not found or not w.active then raise exception 'wallet_not_found'; end if;
  warn := public._d_neg_check(w.id, p_date, amt);
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.d_wallet_fees (wallet_id, location_id, fee_date, amount, kind, ref, note, client_id, created_by, created_staff)
    values (w.id, p_loc, p_date, amt, p_kind, left(nullif(btrim(p_ref), ''), 60), left(nullif(btrim(p_note), ''), 200), p_client, auth.uid(), sid) returning * into f;
  return jsonb_build_object('id', f.id, 'balance_after', public._d_wallet_book(w.id, date '9999-12-31'), 'warning', case when warn then 'wallet_negative' end);
end $$;

create or replace function public.d_wallet_fee_void(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare f public.d_wallet_fees;
begin
  select * into f from public.d_wallet_fees where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not public._d_cash_ok(f.location_id) then raise exception 'not allowed'; end if;
  if f.voided then raise exception 'already_void'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  perform public.lock_check(f.fee_date);
  update public.d_wallet_fees set voided = true, void_note = left(btrim(p_note), 200), void_by = auth.uid(), void_at = now() where id = f.id;
  return jsonb_build_object('id', f.id, 'voided', true);
end $$;

create or replace function public.d_wallet_move_add(p_wallet int, p_loc int, p_date date, p_direction text, p_counter text, p_counter_wallet int, p_amount numeric,
  p_ref text default null, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare w public.d_wallets; w2 public.d_wallets; m public.d_wallet_moves; sid text; amt numeric := round(p_amount, 2); warn boolean := false; warn2 boolean := false;
begin
  if not public._d_cash_ok(p_loc) then raise exception 'not allowed'; end if;
  if amt is null or amt <= 0 or amt > 1000000000 then raise exception 'bad_amount'; end if;
  if p_date is null or p_date > public._acct_today() + 1 then raise exception 'bad_date'; end if;
  if p_direction not in ('in', 'out') or p_counter not in ('cash', 'bank', 'wallet') then raise exception 'bad_kind'; end if;
  if (p_counter = 'wallet') <> (p_counter_wallet is not null) then raise exception 'wallet_mismatch'; end if;
  if p_counter_wallet is not null and p_counter_wallet = p_wallet then raise exception 'wallet_mismatch'; end if;
  perform public.lock_check(p_date);
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into m from public.d_wallet_moves where client_id = p_client;
    if found then if m.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if; return jsonb_build_object('dup', true, 'id', m.id); end if;
  end if;
  select * into w from public.d_wallets where id = p_wallet order by id for update;
  if not found or not w.active then raise exception 'wallet_not_found'; end if;
  if p_counter_wallet is not null then
    select * into w2 from public.d_wallets where id = p_counter_wallet for update;
    if not found or not w2.active then raise exception 'wallet_not_found'; end if;
  end if;
  if p_direction = 'out' then warn := public._d_neg_check(w.id, p_date, amt);
  elsif p_counter_wallet is not null then warn := public._d_neg_check(w2.id, p_date, amt); end if;      -- money into this wallet comes OUT of the other wallet
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.d_wallet_moves (wallet_id, location_id, move_date, direction, counter, counter_wallet_id, amount, ref, note, client_id, created_by, created_staff)
    values (w.id, p_loc, p_date, p_direction, p_counter, p_counter_wallet, amt, left(nullif(btrim(p_ref), ''), 60), left(nullif(btrim(p_note), ''), 200), p_client, auth.uid(), sid) returning * into m;
  return jsonb_build_object('id', m.id, 'balance_after', public._d_wallet_book(w.id, date '9999-12-31'), 'warning', case when warn then 'wallet_negative' end);
end $$;

create or replace function public.d_wallet_move_void(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.d_wallet_moves; src int;
begin
  select * into m from public.d_wallet_moves where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not public._d_cash_ok(m.location_id) then raise exception 'not allowed'; end if;
  if m.voided then raise exception 'already_void'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  perform public.lock_check(m.move_date);
  -- voiding an "in" must not leave the wallet negative (the money may already be spent)
  if m.direction = 'in' and coalesce(public.rule_txt('d_wallet_negative_mode'), 'refuse') = 'refuse'
     and public._d_wallet_book(m.wallet_id, date '9999-12-31') - m.amount < 0 then raise exception 'wallet_negative'; end if;
  update public.d_wallet_moves set voided = true, void_note = left(btrim(p_note), 200), void_by = auth.uid(), void_at = now() where id = m.id;
  return jsonb_build_object('id', m.id, 'voided', true);
end $$;

-- the phone total typed FIRST; the book figure and the difference are returned only after it is saved
create or replace function public.d_wallet_check_save(p_wallet int, p_date date, p_phone numeric, p_loc int default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare w public.d_wallet_checks; wl public.d_wallets; br numeric; bj numeric; df numeric; sid text; ph numeric := round(p_phone, 2);
begin
  if not public._d_cash_ok(p_loc) then raise exception 'not allowed'; end if;
  if ph is null or ph < 0 or ph > 1000000000000 then raise exception 'bad_amount'; end if;
  if p_date is null or p_date > public._acct_today() then raise exception 'bad_date'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into w from public.d_wallet_checks where client_id = p_client;
    if found then if w.counted_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', w.id, 'book', w.book_register, 'diff', w.diff, 'status', w.status); end if;
  end if;
  select * into wl from public.d_wallets where id = p_wallet;
  if not found then raise exception 'wallet_not_found'; end if;
  br := public._d_wallet_book(wl.id, p_date); bj := public._d_wallet_journal(wl.id, p_date); df := round(ph - br, 2);
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.d_wallet_checks (wallet_id, location_id, check_date, phone_balance, book_register, book_journal, diff, status, client_id, counted_by, counted_staff)
    values (wl.id, p_loc, p_date, ph, br, bj, df, case when df = 0 then 'matched' else 'difference' end, p_client, auth.uid(), sid) returning * into w;
  return jsonb_build_object('id', w.id, 'phone', w.phone_balance, 'book', w.book_register, 'book_journal', w.book_journal, 'diff', w.diff, 'status', w.status);
end $$;

-- the reason for a difference: written once
create or replace function public.d_wallet_check_explain(p_check bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.d_wallet_checks;
begin
  select * into c from public.d_wallet_checks where id = p_check for update;
  if not found then raise exception 'not found'; end if;
  if not public._d_cash_ok(c.location_id) then raise exception 'not allowed'; end if;
  if c.status <> 'difference' then raise exception 'nothing_to_explain'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  update public.d_wallet_checks set reason = left(btrim(p_reason), 300), status = 'explained', reason_by = auth.uid(), reason_at = now() where id = c.id;
  return jsonb_build_object('id', c.id, 'status', 'explained');
end $$;

-- balances of every wallet (register and journal side by side). Owner/accounts: always. A counter sees the book figure of a wallet only after the count of that day is saved.
create or replace function public.d_wallet_balances(p_asof date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_asof, public._acct_today()); full_ boolean;
begin
  if not public._d_view_ok() then raise exception 'not allowed'; end if;
  full_ := public._acct_manage() or public.is_owner();
  return coalesce((select jsonb_agg(jsonb_build_object('wallet_id', w.id, 'code', w.code, 'name_bn', w.name_bn, 'name_en', w.name_en, 'account', a.code, 'active', w.active,
      'counted', exists (select 1 from public.d_wallet_checks c where c.wallet_id = w.id and c.check_date = d),
      'book', case when full_ or exists (select 1 from public.d_wallet_checks c where c.wallet_id = w.id and c.check_date = d) then public._d_wallet_book(w.id, d) end,
      'journal', case when full_ then public._d_wallet_journal(w.id, d) end,
      'journal_gap', case when full_ then public._d_wallet_book(w.id, d) - public._d_wallet_journal(w.id, d) end) order by w.sort, w.id)
    from public.d_wallets w join public.coa_accounts a on a.id = w.coa_account_id), '[]'::jsonb);
end $$;

-- the 10-3 reconcile report: phone total versus book, per wallet, for one day
create or replace function public.d_wallet_recon_report(p_date date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_date, public._acct_today()); full_ boolean; unas numeric;
begin
  if not public._d_view_ok() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  full_ := public._acct_manage() or public.is_owner();
  select coalesce((select sum(p.amount) from public.sale_payments p left join public.sales s on s.id = p.sale_id
                    where p.mode = 'mobile' and not p.voided and p.kind in ('sale', 'collection') and (p.sale_id is null or s.status = 'done')
                      and (p.paid_at at time zone 'Asia/Dhaka')::date <= d and public._d_wallet_of(p.wallet) is null), 0)
       - coalesce((select sum(p.amount) from public.supplier_payments p where p.mode = 'mobile' and not p.voided and (p.paid_at at time zone 'Asia/Dhaka')::date <= d and public._d_wallet_of(p.wallet) is null), 0)
    into unas;
  return jsonb_build_object('date', d, 'unassigned_mobile', unas,
    'wallets', coalesce((select jsonb_agg(jsonb_build_object('wallet_id', w.id, 'code', w.code, 'name_en', w.name_en,
        'check_id', c.id, 'phone', c.phone_balance, 'status', coalesce(c.status, 'not_counted'), 'reason', c.reason,
        'book', case when c.id is not null then c.book_register when full_ then public._d_wallet_book(w.id, d) end,
        'book_journal', case when c.id is not null then c.book_journal when full_ then public._d_wallet_journal(w.id, d) end,
        'diff', c.diff) order by w.sort, w.id)
      from public.d_wallets w
      left join lateral (select * from public.d_wallet_checks k where k.wallet_id = w.id and k.check_date = d and (p_loc is null or k.location_id is not distinct from p_loc) order by k.id desc limit 1) c on true
      where w.active), '[]'::jsonb));
end $$;

create or replace function public.d_wallet_statement(p_wallet int, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._d_view_ok() then raise exception 'not allowed'; end if;
  if not (public._acct_manage() or public.is_owner()) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('date', f.d, 'kind', f.kind, 'amount', f.amt, 'src', f.src, 'src_id', f.src_id, 'location_id', f.loc) order by f.d, f.src, f.src_id)
    from public._d_wallet_flows(p_wallet) f where f.d between coalesce(p_from, date '2000-01-01') and coalesce(p_to, date '9999-12-31')), '[]'::jsonb);
end $$;

-- ---------- G10: materials ----------
create or replace function public.d_item_role_set(p_item uuid, p_role text, p_on boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.items where id = p_item) then raise exception 'item_not_found'; end if;
  if not exists (select 1 from public.d_material_roles where code = p_role and active) then raise exception 'role_not_found'; end if;
  insert into public.d_item_roles (item_id, role_code, active, created_by) values (p_item, p_role, coalesce(p_on, true), auth.uid())
    on conflict (item_id, role_code) do update set active = excluded.active;      -- never deleted: switched off
  return jsonb_build_object('item_id', p_item, 'role', p_role, 'on', coalesce(p_on, true));
end $$;

-- optional import tooling: [{"item_code":"...","role":"milk"}]; unknown codes are reported, nothing is created
create or replace function public.d_item_roles_import(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb; iid uuid; ok int := 0; bad jsonb := '[]'; n int := 0;
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then raise exception 'bad_rows'; end if;
  if jsonb_array_length(p_rows) > 2000 then raise exception 'too_many_rows'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    n := n + 1;
    select id into iid from public.items where code = r->>'item_code';
    if iid is null or not exists (select 1 from public.d_material_roles where code = r->>'role' and active) then bad := bad || jsonb_build_object('row', n, 'item_code', r->>'item_code', 'role', r->>'role');
    else insert into public.d_item_roles (item_id, role_code, created_by) values (iid, r->>'role', auth.uid()) on conflict (item_id, role_code) do update set active = true; ok := ok + 1; end if;
  end loop;
  return jsonb_build_object('mapped', ok, 'rejected', bad);
end $$;

create or replace function public.d_product_req_set(p_product uuid, p_role text, p_required boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.items where id = p_product) then raise exception 'item_not_found'; end if;
  if not exists (select 1 from public.d_material_roles where code = p_role and active) then raise exception 'role_not_found'; end if;
  insert into public.d_product_role_req (product_item_id, role_code, required, updated_by) values (p_product, p_role, coalesce(p_required, true), auth.uid())
    on conflict (product_item_id, role_code) do update set required = excluded.required, updated_at = now(), updated_by = auth.uid();
  return jsonb_build_object('product', p_product, 'role', p_role, 'required', coalesce(p_required, true));
end $$;

create or replace function public.d_fixed_price_set(p_item uuid, p_price numeric, p_from date, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare id_ bigint;
begin
  if not (public._recipe_mgr() and public._recipe_cost_ok()) then raise exception 'not allowed'; end if;
  if p_price is null or p_price <= 0 or p_price > 1000000 or p_from is null then raise exception 'bad_amount'; end if;
  if not exists (select 1 from public.items where id = p_item) then raise exception 'item_not_found'; end if;
  insert into public.d_material_fixed_price (item_id, price, from_date, note, created_by) values (p_item, round(p_price, 6), p_from, left(p_note, 200), auth.uid()) returning id into id_;
  return jsonb_build_object('id', id_);
end $$;

-- roles a recipe is missing (a required role is met by an active ingredient line or an active packaging line of the product)
create or replace function public._d_missing_roles(p_recipe uuid) returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(q.role_code order by q.role_code), '{}') from public.recipes r
   join public.d_product_role_req q on q.product_item_id = r.item_id and q.required
   where r.id = p_recipe
     and not exists (select 1 from public.recipe_lines l join public.d_item_roles ir on ir.item_id = l.ingredient_item_id
                      where l.recipe_id = r.id and l.active and ir.active and ir.role_code = q.role_code)
     and not exists (select 1 from public.product_packaging pp join public.d_item_roles ir on ir.item_id = pp.packaging_item_id
                      where pp.product_item_id = r.item_id and pp.active and ir.active and ir.role_code = q.role_code);
$$;

create or replace function public._d_material_cost(p_item uuid, p_loc int) returns numeric
language plpgsql stable security definer set search_path = public as $$
declare m text := coalesce(public.rule_txt('d_material_cost_method'), 'average_purchase'); c numeric;
begin
  if m = 'fixed_price' then
    select price into c from public.d_material_fixed_price where item_id = p_item and from_date <= public._acct_today() order by from_date desc, id desc limit 1;
  elsif m = 'last_purchase' then
    select l.unit_cost_base into c from public.purchase_lines l join public.purchase_bills b on b.id = l.bill_id
     where l.item_id = p_item and b.status = 'posted' and b.kind = 'bill' and coalesce(l.unit_cost_base, 0) > 0 and (p_loc is null or b.location_id = p_loc)
     order by b.bill_date desc, l.id desc limit 1;
  else
    select case when p_loc is null then sum(qty * avg_cost) / nullif(sum(qty) filter (where avg_cost is not null), 0) else max(avg_cost) end into c
      from public.stock_balance where item_id = p_item and (p_loc is null or location_id = p_loc) and (p_loc is not null or qty > 0);
  end if;
  return case when coalesce(c, 0) > 0 then c end;
end $$;

create or replace function public.d_material_unit_cost(p_item uuid, p_loc int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if p_loc is null then
    if not public._recipe_cost_ok() then raise exception 'not allowed'; end if;
  elsif not (public._cost_ok(p_loc) and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  return jsonb_build_object('item_id', p_item, 'method', coalesce(public.rule_txt('d_material_cost_method'), 'average_purchase'), 'unit_cost', public._d_material_cost(p_item, p_loc));
end $$;

create or replace function public.d_recipe_material_check(p_recipe uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare miss text[];
begin
  if not (public._recipe_read() or public._recipe_mgr()) then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.recipes where id = p_recipe) then raise exception 'recipe_not_found'; end if;
  miss := public._d_missing_roles(p_recipe);
  return jsonb_build_object('recipe_id', p_recipe, 'ok', coalesce(array_length(miss, 1), 0) = 0, 'missing_roles', to_jsonb(miss),
    'has_lines', exists (select 1 from public.recipe_lines where recipe_id = p_recipe and active), 'mode', coalesce(public.rule_txt('d_recipe_materials_mode'), 'off'));
end $$;

-- ingredients and packaging of active recipes that have no cost under the chosen method
create or replace function public.d_recipe_cost_gaps(p_loc int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if p_loc is null or not (public._cost_ok(p_loc) and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('item_id', z.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'kind', z.kind,
      'roles', coalesce((select jsonb_agg(ir.role_code order by ir.role_code) from public.d_item_roles ir where ir.item_id = z.item_id and ir.active), '[]'::jsonb),
      'recipes', z.n, 'method', coalesce(public.rule_txt('d_material_cost_method'), 'average_purchase')) order by i.code)
    from (select x.item_id, min(x.kind) kind, count(distinct x.recipe_id) n from (
            select l.ingredient_item_id item_id, 'ingredient'::text kind, r.id recipe_id from public.recipe_lines l join public.recipes r on r.id = l.recipe_id where l.active and r.active
            union all
            select pp.packaging_item_id, 'packaging', r.id from public.product_packaging pp join public.recipes r on r.item_id = pp.product_item_id where pp.active and r.active) x
          group by x.item_id) z
    join public.items i on i.id = z.item_id
    where public._d_material_cost(z.item_id, p_loc) is null), '[]'::jsonb);
end $$;

-- what one production run really consumed (from the stock ledger) split by role / type, plus the conversion cost
create or replace function public.d_production_cost_breakdown(p_run uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r public.production_runs; mat numeric; lines jsonb; roles jsonb; pack numeric; raw numeric;
begin
  select * into r from public.production_runs where id = p_run;
  if not found then raise exception 'run_not_found'; end if;
  if not (public._cost_ok(r.location_id) and public.can_loc(r.location_id) and public._recipe_read()) then raise exception 'not allowed'; end if;
  select coalesce(sum(-l.qty_delta * coalesce(l.unit_cost, 0)), 0),
         coalesce(sum(-l.qty_delta * coalesce(l.unit_cost, 0)) filter (where i.item_type = 'packaging'), 0),
         coalesce(sum(-l.qty_delta * coalesce(l.unit_cost, 0)) filter (where i.item_type <> 'packaging'), 0),
         coalesce(jsonb_agg(jsonb_build_object('item_id', l.item_id, 'code', i.code, 'type', i.item_type, 'qty', -l.qty_delta, 'unit_cost', l.unit_cost, 'amount', round(-l.qty_delta * coalesce(l.unit_cost, 0), 4)) order by i.code), '[]'::jsonb)
    into mat, pack, raw, lines
    from public.stock_ledger l join public.items i on i.id = l.item_id
   where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out';
  select coalesce(jsonb_object_agg(role_code, amt), '{}'::jsonb) into roles from (
    select ir.role_code, round(sum(-l.qty_delta * coalesce(l.unit_cost, 0)), 4) amt
      from public.stock_ledger l join public.d_item_roles ir on ir.item_id = l.item_id and ir.active
     where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out' group by ir.role_code) z;
  return jsonb_build_object('run_id', r.id, 'material_total', round(mat, 4), 'raw_total', round(raw, 4), 'packaging_total', round(pack, 4), 'by_role', roles,
    'conversion', coalesce(r.conversion_cost, 0), 'production_total', round(mat + coalesce(r.conversion_cost, 0), 4),
    'matches_run_record', r.material_cost is null or abs(coalesce(r.material_cost, 0) - round(mat, 4)) < 0.01, 'lines', lines);
end $$;

-- the guards: self-contained triggers (no existing function is edited)
create or replace function public._d_prod_gate() returns trigger language plpgsql security definer set search_path = public as $$
declare mode_ text := coalesce(public.rule_txt('d_recipe_materials_mode'), 'off'); miss text[]; it public.items;
begin
  if mode_ = 'off' then return new; end if;
  miss := public._d_missing_roles(new.recipe_id);
  if coalesce(array_length(miss, 1), 0) = 0 then return new; end if;
  if mode_ = 'block' then raise exception 'recipe_missing_material' using detail = array_to_string(miss, ', '); end if;
  select * into it from public.items where id = new.item_id;
  perform public._stock_exc(new.location_id, 'recipe_material_missing', 'yellow', coalesce(it.name_bn, '') || ': রেসিপিতে প্রয়োজনীয় কাঁচামাল নেই (' || array_to_string(miss, ', ') || ')',
    coalesce(it.name_en, it.name_bn, '') || ': the recipe lacks a required material (' || array_to_string(miss, ', ') || ')', null, (new.made_at at time zone 'Asia/Dhaka')::date, 'STOCK');
  return new;
end $$;
drop trigger if exists d_production_runs_gate on public.production_runs;
create trigger d_production_runs_gate before insert on public.production_runs for each row execute function public._d_prod_gate();

create or replace function public._d_recipe_activate_gate() returns trigger language plpgsql security definer set search_path = public as $$
declare miss text[];
begin
  if coalesce(public.rule_txt('d_recipe_materials_mode'), 'off') <> 'block' then return new; end if;
  miss := public._d_missing_roles(new.id);
  if coalesce(array_length(miss, 1), 0) > 0 then raise exception 'recipe_missing_material' using detail = array_to_string(miss, ', '); end if;
  return new;
end $$;
drop trigger if exists d_recipes_activate_gate on public.recipes;
create trigger d_recipes_activate_gate before update of active on public.recipes for each row when (new.active and not old.active) execute function public._d_recipe_activate_gate();

-- ---------- privileges: internals closed (the two permission helpers stay callable: the row-level-security policies call them) ----------, API open to signed-in users (each function checks the permission itself) ----------
revoke all on function public._d_view_ok(), public._d_cash_ok(int), public._d_wallet_of(text), public._d_wallet_create(text, text, text, text[], numeric, date, int, uuid), public._d_wallet_flows(int),
  public._d_wallet_book(int, date), public._d_wallet_journal(int, date), public._d_neg_check(int, date, numeric), public._d_acct_docs(date), public._d_wallet_fee_rows(date, date, int[]),
  public._d_daybook_rows(int[], date, date), public._d_missing_roles(uuid), public._d_material_cost(uuid, int), public._d_prod_gate(), public._d_recipe_activate_gate() from public, anon, authenticated;
revoke all on function public.d_wallet_add(text, text, text, text[], numeric, date), public.d_wallet_update(int, text, text, text[], boolean), public.d_wallet_opening_set(int, numeric, date),
  public.d_wallet_fee_add(int, int, date, numeric, text, text, text, uuid), public.d_wallet_fee_void(bigint, text),
  public.d_wallet_move_add(int, int, date, text, text, int, numeric, text, text, uuid), public.d_wallet_move_void(bigint, text),
  public.d_wallet_check_save(int, date, numeric, int, uuid), public.d_wallet_check_explain(bigint, text), public.d_wallet_balances(date), public.d_wallet_recon_report(date, int),
  public.d_wallet_statement(int, date, date), public.d_item_role_set(uuid, text, boolean), public.d_item_roles_import(jsonb), public.d_product_req_set(uuid, text, boolean),
  public.d_fixed_price_set(uuid, numeric, date, text), public.d_material_unit_cost(uuid, int), public.d_recipe_material_check(uuid), public.d_recipe_cost_gaps(int),
  public.d_production_cost_breakdown(uuid) from public, anon, authenticated;
grant execute on function public.d_wallet_add(text, text, text, text[], numeric, date), public.d_wallet_update(int, text, text, text[], boolean), public.d_wallet_opening_set(int, numeric, date),
  public.d_wallet_fee_add(int, int, date, numeric, text, text, text, uuid), public.d_wallet_fee_void(bigint, text),
  public.d_wallet_move_add(int, int, date, text, text, int, numeric, text, text, uuid), public.d_wallet_move_void(bigint, text),
  public.d_wallet_check_save(int, date, numeric, int, uuid), public.d_wallet_check_explain(bigint, text), public.d_wallet_balances(date), public.d_wallet_recon_report(date, int),
  public.d_wallet_statement(int, date, date), public.d_item_role_set(uuid, text, boolean), public.d_item_roles_import(jsonb), public.d_product_req_set(uuid, text, boolean),
  public.d_fixed_price_set(uuid, numeric, date, text), public.d_material_unit_cost(uuid, int), public.d_recipe_material_check(uuid), public.d_recipe_cost_gaps(int),
  public.d_production_cost_breakdown(uuid) to authenticated;
grant execute on function public._d_view_ok(), public._d_cash_ok(int) to authenticated;
